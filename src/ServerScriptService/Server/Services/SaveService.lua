-- SaveService.lua
-- 저장 서비스 (Autosave, PlayerRemoving, Snapshot 로테이션)
-- 영속: PlayerSave, WorldSave
-- 비영속: WorldDrop, Wildlife, ResourceNodes (저장 금지)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)
local Serialization = require(Shared.Util.Serialization)

local Server = ServerScriptService:WaitForChild("Server")
local Persistence = Server:WaitForChild("Persistence")
local DataStoreClient = require(Persistence.DataStoreClient)

local SaveService = {}

--========================================
-- Configuration
--========================================
local AUTOSAVE_INTERVAL = 60  -- 초 (데이터 유실 방지용)
local SNAPSHOT_INTERVAL = 300 -- 초 (5분마다 스냅샷 생성 - 연산 부하 경감)
local MAX_SNAPSHOTS = 3       -- 롤백 스냅샷 수
local SAVE_VERSION = 1        -- 스키마 버전
local PLAYER_LOAD_RETRY_WINDOW = RunService:IsStudio() and 25 or 45
local PLAYER_LOAD_RETRY_INTERVAL = 2
local SESSION_LOCK_FORCE_ACQUIRE_DELAY = RunService:IsStudio() and 4 or 10
local ENABLE_SESSION_LOCK_FORCE_ACQUIRE = true
local SESSION_LOCK_STABLE_RETRY_THRESHOLD = math.max(
	3,
	math.min(
		math.ceil((AUTOSAVE_INTERVAL + PLAYER_LOAD_RETRY_INTERVAL) / PLAYER_LOAD_RETRY_INTERVAL),
		math.max(3, math.floor((PLAYER_LOAD_RETRY_WINDOW / PLAYER_LOAD_RETRY_INTERVAL) - 2))
	)
)

--========================================
-- Private State
--========================================
local initialized = false
local playerStates = {}   -- [userId] = playerState
local worldState = nil    -- 월드 상태 (Global: Metadata, Time 등)
local partitionStates = {} -- [partitionId] = partitionState (Local: Base-specific structures, storages)
local lastSaveTime = 0
local CURRENT_JOB_ID = game.JobId

-- NetController 참조
local NetController = nil

--========================================
-- Schema Definitions (Phase 1-3 초기 구조)
--========================================

local function _getDefaultEquipment()
	return {
		HEAD = nil,
		SUIT = nil,
		HAND = nil,
	}
end

--- 기본 플레이어 저장 스키마
local function _getDefaultPlayerSave()
	return {
		version = SAVE_VERSION,
		-- 인벤토리 (나중에 InventoryService에서 채움)
		inventory = {},
		-- 자원 (나중에 ResourceService에서 채움)
		resources = {
			stone = 0,
			wood = 0,
			fiber = 0,
		},
		-- 소유 크리처 (길들여진 공룡)
		creatures = {},
		-- 외양간 내 크리처
		barn = {},
		-- 기술 해금
		unlockedTech = {["TECH_Lv1_BASICS"] = true},
		-- 제작 큐 (persistence)
		craftingQueue = {},
		-- 팰 보관함 (Phase 5)
		palbox = {},
		-- 파티 정보 (Phase 5-4)
		party = {
			slots = {},
			summonedSlot = nil,
		},
		-- 통계 및 스탯 (Phase 6)
		stats = {
			playTime = 0,
			createdAt = os.time(),
			lastLogin = os.time(),
			level = 1,
			currentXP = 0,
			totalXP = 0,
			techPointsSpent = 0,
			statInvested = {
				[Enums.StatId.MAX_HEALTH] = 0,
				[Enums.StatId.MAX_STAMINA] = 0,
				[Enums.StatId.INV_SLOTS] = 0,
				[Enums.StatId.WORK_SPEED] = 0,
				[Enums.StatId.ATTACK] = 0,
			}
		},
		-- 스킬 트리 (전투 택1 + 건축 자동해금)
		skillPointsSpent = 0,
		unlockedSkills = {},
		combatTreeId = nil,
		activeSkillSlots = { nil, nil, nil },
		-- 장착 중인 아이템 (Head, Body, Feet, Hand)
		equipment = _getDefaultEquipment(),
		-- 고대 포탈 진행도 (개인 저장)
		portalRepaired = false,
		portalProgress = {},
		-- 마지막 로그아웃/수면 위치 (Phase 4-3)
		lastPosition = nil,
		-- 세션 제어 (Session Locking)
		_session = {
			jobId = nil,
			timestamp = 0,
		},
		-- 스냅샷 (롤백용)
		snapshots = {},
	}
end

--- 기본 월드 저장 스키마
local function _getDefaultWorldSave()
	return {
		version = SAVE_VERSION,
		-- 건물/구조물 (영속)
		structures = {},
		-- 시설 (영속)
		facilities = {},
		-- 창고 (영속)
		storages = {},
		-- 외양간 (영속)
		barns = {},
		-- 통계
		stats = {
			lastSave = 0,
			lastSnapshotTime = 0,
		},
		snapshots = {},
		-- 중요: 다음 필드는 절대 저장 금지 (동적 객체)
		-- drops, wildlife, resourceNodes
	}
end

--- 기본 베이스 파티션 스키마
local function _getDefaultPartitionSave(baseId: string, ownerId: number)
	return {
		version = SAVE_VERSION,
		baseId = baseId,
		ownerId = ownerId,
		structures = {},
		storages = {},
		facilityStates = {}, -- 연료량, 가동 상태 등
		lastSave = os.time(),
	}
end

--========================================
-- Internal Functions
--========================================

--- 스냅샷 로테이션 (FIFO, max 3개)
local function _rotateSnapshots(snapshots: {any}, newSnapshot: any): {any}
	local result = snapshots or {}
	
	-- 새 스냅샷 추가
	table.insert(result, 1, {
		timestamp = os.time(),
		data = newSnapshot,
	})
	
	-- 최대 개수 초과 시 오래된 것 제거
	while #result > MAX_SNAPSHOTS do
		table.remove(result)
	end
	
	return result
end

--- 최적화된 딥카피 (성능 중심)
local function _deepCopy(original: any): any
	if type(original) ~= "table" then
		return original
	end
	
	local copy = table.create(#original) -- 처리 속도 향상 (배열인 경우)
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = _deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

--- 플레이어 스냅샷 생성 (딥카피)
local function _makePlayerSnapshot(playerState: any): any
	-- 스냅샷은 현재 상태의 딥카피 (스냅샷 필드 제외)
	local snapshot = {}
	for key, value in pairs(playerState) do
		if key ~= "snapshots" then
			snapshot[key] = _deepCopy(value)
		end
	end
	return snapshot
end

--- 월드 스냅샷 생성 (딥카피)
local function _makeWorldSnapshot(worldStateData: any): any
	local snapshot = {}
	for key, value in pairs(worldStateData) do
		if key ~= "snapshots" then
			snapshot[key] = _deepCopy(value)
		end
	end
	return snapshot
end

local function _normalizeEquipment(equipment: any): any
	local normalized = _getDefaultEquipment()
	if type(equipment) ~= "table" then
		return normalized
	end

	normalized.HEAD = equipment.HEAD or equipment.Head
	normalized.SUIT = equipment.SUIT or equipment.Suit
	normalized.HAND = equipment.HAND or equipment.Hand

	return normalized
end

local function _normalizePlayerState(state: any): any
	if type(state) ~= "table" then
		state = _getDefaultPlayerSave()
	end

	state.inventory = type(state.inventory) == "table" and state.inventory or {}
	state.equipment = _normalizeEquipment(state.equipment)
	state.portalRepaired = state.portalRepaired == true
	state.portalProgress = type(state.portalProgress) == "table" and state.portalProgress or {}
	state.portalProgress.LOG = math.max(0, math.floor(tonumber(state.portalProgress.LOG) or 0))
	state.portalProgress.STONE = math.max(0, math.floor(tonumber(state.portalProgress.STONE) or 0))
	state.stats = type(state.stats) == "table" and state.stats or {}
	state.stats.lastLogin = state.stats.lastLogin or 0
	state.snapshots = type(state.snapshots) == "table" and state.snapshots or {}
	state._session = type(state._session) == "table" and state._session or { jobId = nil, timestamp = 0 }

	-- 스킬 트리 필드 정규화
	state.skillPointsSpent = type(state.skillPointsSpent) == "number" and state.skillPointsSpent or 0
	state.unlockedSkills = type(state.unlockedSkills) == "table" and state.unlockedSkills or {}
	state.combatTreeId = (type(state.combatTreeId) == "string") and state.combatTreeId or nil
	state.activeSkillSlots = type(state.activeSkillSlots) == "table" and state.activeSkillSlots or { nil, nil, nil }

	-- ★ SPEAR → SWORD 마이그레이션 (v1 레거시 세이브 호환)
	if state.combatTreeId == "SPEAR" then
		state.combatTreeId = "SWORD"
	end
	do
		local migrated = {}
		local changed = false
		for key, val in pairs(state.unlockedSkills) do
			local newKey = key:gsub("^SPEAR_", "SWORD_")
			if newKey ~= key then changed = true end
			migrated[newKey] = val
		end
		if changed then state.unlockedSkills = migrated end
	end
	for i, slotId in ipairs(state.activeSkillSlots) do
		if type(slotId) == "string" then
			state.activeSkillSlots[i] = slotId:gsub("^SPEAR_", "SWORD_")
		end
	end

	return state
end

local function _normalizeWorldState(state: any): any
	if type(state) ~= "table" then
		state = _getDefaultWorldSave()
	end

	state.structures = type(state.structures) == "table" and state.structures or {}
	state.wildernessStructures = type(state.wildernessStructures) == "table" and state.wildernessStructures or {}
	state.facilities = type(state.facilities) == "table" and state.facilities or {}
	state.storages = type(state.storages) == "table" and state.storages or {}
	state.barns = type(state.barns) == "table" and state.barns or {}
	state.stats = type(state.stats) == "table" and state.stats or {}
	state.stats.lastSave = state.stats.lastSave or 0
	state.stats.lastSnapshotTime = state.stats.lastSnapshotTime or 0
	state.snapshots = type(state.snapshots) == "table" and state.snapshots or {}

	return state
end

--========================================
-- Player Save/Load
--========================================

--- 플레이어 데이터 로드 (UpdateAsync를 통한 세션 잠금)
--- forceAcquire=true 이면 유효 잠금을 강제로 인수 (신중히 사용)
function SaveService.loadPlayer(userId: number, forceAcquire: boolean?): (boolean, any)
	local key = DataStoreClient.GetPlayerKey(userId)
	local shouldForceAcquire = forceAcquire == true
	local lockOwnerJobId = nil
	local lockTimestamp = nil
	
	local success, data = DataStoreClient.update(key, function(oldData)
		if not oldData then 
			local newSave = _getDefaultPlayerSave()
			newSave._session.jobId = CURRENT_JOB_ID
			newSave._session.timestamp = os.time()
			return newSave
		end
		
		-- 세션 잠금 확인
		if oldData._session and oldData._session.jobId and oldData._session.jobId ~= CURRENT_JOB_ID then
			lockOwnerJobId = oldData._session.jobId
			lockTimestamp = oldData._session.timestamp
			if not shouldForceAcquire then
				-- 아직 다른 서버가 사용 중 (로딩 거부)
				return nil -- 이 값은 DataStoreClient.update에서 success=true, result=nil로 반환됨
			end
			warn(string.format("[SaveService] Force-acquiring session lock for user %d (from %s -> %s)", userId, tostring(oldData._session.jobId), CURRENT_JOB_ID))
		end
		
		-- 잠금 획득
		if not oldData._session then oldData._session = {} end
		oldData._session.jobId = CURRENT_JOB_ID
		oldData._session.timestamp = os.time()
		return oldData
	end)
	
	if not success then
		warn(string.format("[SaveService] Failed to load/lock player %d: %s", userId, tostring(data)))
		return false, data
	end
	
	if data == nil then
		-- 세션이 잠겨있음
		warn(string.format("[SaveService] Player %d is locked by another server (JobId: %s)", userId, tostring(lockOwnerJobId or "Unknown")))
		return false, "SESSION_LOCKED", {
			jobId = lockOwnerJobId,
			timestamp = lockTimestamp,
		}
	end
	
	-- 데이터 전처리
	local state = _normalizePlayerState(Serialization.deserialize(data))
	state.stats.lastLogin = os.time()
	
	-- 메모리에 캐시
	playerStates[userId] = state
	
	return true, state
end

--- 플레이어 데이터 저장 (UpdateAsync)
function SaveService.savePlayer(userId: number, snapshot: any?, isLogout: boolean?): (boolean, string?)
	local state = snapshot or playerStates[userId]
	
	if not state then
		warn(string.format("[SaveService] No state for player %d", userId))
		return false, "NO_STATE"
	end
	
	-- [수면/로그아웃 위치 저장] 간이천막 리스폰 설정이 없을 때만 현재 좌표로 갱신
	-- 로딩 화면 중(Anchored + Y>3000)에는 저장하지 않음 (클라이언트가 Y+5000으로 올려놓은 상태)
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Character and not state.respawnStructureId then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and not hrp.Anchored and hrp.Position.Y < 3000 then
			state.lastPosition = {
				x = hrp.Position.X,
				y = hrp.Position.Y,
				z = hrp.Position.Z
			}
		end
	end
	
	-- [최적화] 스냅샷 로테이션은 주기적으로만 수행 (매 Autosave마다 딥카피 방지)
	local lastSnapshot = state.stats.lastSnapshotTime or 0
	if not snapshot and (os.time() - lastSnapshot > SNAPSHOT_INTERVAL) then
		state.snapshots = _rotateSnapshots(state.snapshots, _makePlayerSnapshot(state))
		state.stats.lastSnapshotTime = os.time()
	end
	
	if not snapshot then
		state.stats.lastSave = os.time()
		if state._session then
			state._session.timestamp = os.time()
		end
	end
	
	local key = DataStoreClient.GetPlayerKey(userId)
	
	-- UpdateAsync를 통해 저장
	local success, result = DataStoreClient.update(key, function(oldData)
		-- 세션 검증 (내 서버가 아닐 경우 덮어쓰기 금지)
		if oldData and oldData._session and oldData._session.jobId and oldData._session.jobId ~= CURRENT_JOB_ID then
			warn(string.format("[SaveService] Refusing to overwrite player %d: Session owned by %s", userId, oldData._session.jobId))
			return nil 
		end
		
		-- 저장 전 데이터 직렬화
		local serializedState = Serialization.serialize(state)
		
		-- 세션 유지 또는 해제
		if isLogout then
			serializedState._session.jobId = nil
		else
			serializedState._session.jobId = CURRENT_JOB_ID
		end
		serializedState._session.timestamp = os.time()
		
		return serializedState
	end)
	
	if not success then
		warn(string.format("[SaveService] Failed to save/update player %d: %s", userId, tostring(result)))
	end
	
	return success, result
end

--- 플레이어 상태 가져오기 (메모리에서)
function SaveService.getPlayerState(userId: number): any
	return playerStates[userId]
end

--- 플레이어 상태 업데이트 (메모리에)
function SaveService.updatePlayerState(userId: number, updateFn: (any) -> any)
	local state = playerStates[userId]
	if state then
		playerStates[userId] = updateFn(state)
	end
end

--========================================
-- World Save/Load
--========================================

--- 월드 데이터 로드
function SaveService.loadWorld(): (boolean, any)
	local key = DataStoreClient.Keys.WORLD_MAIN
	local success, data = DataStoreClient.get(key)
	
	if not success then
		warn(string.format("[SaveService] Failed to load world: %s", tostring(data)))
		return false, data
	end
	
	if data == nil then
		-- 신규 월드
		data = _getDefaultWorldSave()
	else
		-- 기존 월드: 데이터 복구
		data = _normalizeWorldState(Serialization.deserialize(data))
	end
	
	worldState = data
	
	return true, data
end

--- 월드 데이터 저장 (UpdateAsync)
local _lastWorldSaveTime = 0
local WORLD_SAVE_DEBOUNCE = 3 -- 3초 이내 중복 저장 방지

function SaveService.saveWorld(snapshot: any?): (boolean, string?)
	local now = os.clock()
	if not snapshot and (now - _lastWorldSaveTime) < WORLD_SAVE_DEBOUNCE then
		return true, "DEBOUNCED"
	end
	
	local state = snapshot or worldState
	
	if not state then
		warn("[SaveService] No world state to save")
		return false, "NO_STATE"
	end
	
	_lastWorldSaveTime = now
	
	-- [최적화] 월드 스냅샷도 주기적으로만 생성
	local lastSnapshot = state.stats.lastSnapshotTime or 0
	if not snapshot and (os.time() - lastSnapshot > SNAPSHOT_INTERVAL) then
		state.snapshots = _rotateSnapshots(state.snapshots, _makeWorldSnapshot(state))
		state.stats.lastSnapshotTime = os.time()
	end
	
	state.stats.lastSave = os.time()
	
	local key = DataStoreClient.Keys.WORLD_MAIN
	
	-- UpdateAsync 활용
	local success, err = DataStoreClient.update(key, function(oldData)
		-- 월드는 세션 잠금이 필수적이지 않으나(서버당 1개), UpdateAsync를 쓰는 것이 안전
		return Serialization.serialize(state)
	end)
	
	if not success then
		warn(string.format("[SaveService] Failed to save world: %s", tostring(err)))
	end
	
	return success, err
end

--- 월드 상태 가져오기
function SaveService.getWorldState(): any
	return worldState
end

--- 월드 상태 업데이트
function SaveService.updateWorldState(updateFn: (any) -> any)
	if worldState then
		worldState = updateFn(worldState)
	end
end

--========================================
-- Partition Save/Load (Base-specific)
--========================================

--- 파티션 데이터 로드
function SaveService.loadPartition(partitionId: string): (boolean, any)
	local key = DataStoreClient.Keys.BASE_PARTITION_PREFIX .. partitionId
	local success, data = DataStoreClient.get(key)
	
	if not success then
		return false, data
	end
	
	if data == nil then
		return true, nil -- 신규 파티션 (BaseClaimService에서 초기화)
	end
	
	local state = Serialization.deserialize(data)
	partitionStates[partitionId] = state
	
	return true, state
end

--- 파티션 데이터 저장
function SaveService.savePartition(partitionId: string, snapshot: any?): (boolean, string?)
	local state = snapshot or partitionStates[partitionId]
	if not state then return false, "NO_STATE" end
	
	state.lastSave = os.time()
	local key = DataStoreClient.Keys.BASE_PARTITION_PREFIX .. partitionId
	
	local success, err = DataStoreClient.update(key, function(oldData)
		return Serialization.serialize(state)
	end)
	
	return success, err
end

--- 파티션 초기화
function SaveService.initPartition(partitionId: string, ownerId: number)
	if partitionStates[partitionId] then return end
	partitionStates[partitionId] = _getDefaultPartitionSave(partitionId, ownerId)
end

--- 파티션 상태 가져오기
function SaveService.getPartition(partitionId: string): any?
	return partitionStates[partitionId]
end

--- 파티션 상태 업데이트 (Dirty 플래그 포함)
function SaveService.updatePartition(partitionId: string, updateFn: (any) -> any)
	local state = partitionStates[partitionId]
	if state then
		partitionStates[partitionId] = updateFn(state)
		return true
	end
	warn(string.format("[SaveService] Partition '%s' not found for update", partitionId))
	return false
end

--- 파티션 삭제
function SaveService.deletePartition(partitionId: string)
	partitionStates[partitionId] = nil
	local key = DataStoreClient.Keys.BASE_PARTITION_PREFIX .. partitionId
	DataStoreClient.remove(key)
end

--========================================
-- Save All (Admin/Autosave)
--========================================

--- 전체 저장 (모든 플레이어 + 월드)
function SaveService.saveNow(): (boolean, number, number)
	local playerSuccess = 0
	local playerFail = 0
	
	-- 모든 플레이어 저장 (Staggered: API 부하 분산)
	local STAGGER_INTERVAL = 0.5 
	for userId, _ in pairs(playerStates) do
		local ok, _ = SaveService.savePlayer(userId)
		if ok then
			playerSuccess += 1
		else
			playerFail += 1
		end
		
		-- [중요] 일시에 모든 유저를 저장하면 Throttling 리밋에 걸리므로 간격을 둠
		task.wait(STAGGER_INTERVAL)
	end
	
	-- 월드 저장
	local worldOk, _ = SaveService.saveWorld()
	
	-- 모든 파티션 저장 (Staggered)
	local partitionCount = 0
	for pId, _ in pairs(partitionStates) do
		SaveService.savePartition(pId)
		partitionCount += 1
		if partitionCount % 5 == 0 then task.wait(0.1) end
	end
	
	lastSaveTime = os.time()
	
	return worldOk, playerSuccess, playerFail
end

--========================================
-- Event Handlers
--========================================

-- 데이터 로드 성공 후 스폰 위치 결정 + LoadCharacter (공통 함수)
local function _spawnAfterDataLoad(player: Player, userId: number)
	local state = playerStates[userId]
	local spawnPos = nil

	-- 우선순위 1: lastPosition (간이천막 취침 시 저장)
	if state and state.lastPosition then
		spawnPos = Vector3.new(
			state.lastPosition.x or 0,
			(state.lastPosition.y or 0) + 5,
			state.lastPosition.z or 0
		)
		print(string.format("[SaveService] Spawn from lastPosition: %.1f, %.1f, %.1f", spawnPos.X, spawnPos.Y, spawnPos.Z))
	end

	-- 우선순위 2: respawnStructureId → BuildService에서 구조물 위치 조회
	if not spawnPos and state and state.respawnStructureId then
		local buildOk, BSvc = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.BuildService)
		end)
		if buildOk and BSvc and BSvc.get then
			local struct = BSvc.get(state.respawnStructureId)
			if struct and struct.position then
				local pos = struct.position
				if typeof(pos) == "Vector3" then
					spawnPos = pos + Vector3.new(0, 5, 0)
				elseif type(pos) == "table" then
					spawnPos = Vector3.new(pos.X or pos.x or 0, (pos.Y or pos.y or 0) + 5, pos.Z or pos.z or 0)
				end
				if spawnPos then
					print(string.format("[SaveService] Spawn from respawnStructureId(%s): %.1f, %.1f, %.1f",
						state.respawnStructureId, spawnPos.X, spawnPos.Y, spawnPos.Z))
				end
			end
		end
	end

	-- 우선순위 3: SpawnLocation 모델 (신규/데이터없음)
	if not spawnPos then
		local spawnModel = workspace:FindFirstChild("SpawnLocation")
		if spawnModel and spawnModel:IsA("Model") then
			local cf, size = spawnModel:GetBoundingBox()
			spawnPos = cf.Position + Vector3.new(0, size.Y / 2 + 5, 0)
			print(string.format("[SaveService] Spawn from SpawnLocation model: %.1f, %.1f, %.1f", spawnPos.X, spawnPos.Y, spawnPos.Z))
		elseif spawnModel and spawnModel:IsA("BasePart") then
			spawnPos = spawnModel.Position + Vector3.new(0, 5, 0)
		else
			spawnPos = Vector3.new(0, 50, 0)
			print("[SaveService] No spawn target found, using fallback (0,50,0)")
		end
	end

	-- 스폰 위치를 player attribute로 전달 (LoadingScreen + CharacterSetupService가 읽음)
	player:SetAttribute("SpawnPosX", spawnPos.X)
	player:SetAttribute("SpawnPosY", spawnPos.Y)
	player:SetAttribute("SpawnPosZ", spawnPos.Z)
	player:SetAttribute("DataLoaded", true)

	-- LoadCharacter 호출 (CharacterAutoLoads=false이므로 수동)
	if player.Parent then
		player:LoadCharacter()
		print(string.format("[SaveService] LoadCharacter called for %s at %.1f, %.1f, %.1f",
			player.Name, spawnPos.X, spawnPos.Y, spawnPos.Z))
	end
end

--- PlayerAdded 이벤트
local function onPlayerAdded(player: Player)
	task.spawn(function()
		local userId = player.UserId
		local deadline = os.clock() + PLAYER_LOAD_RETRY_WINDOW
		local lastErr = nil
		local forceTried = false
		local lastLockSignature = nil
		local stableLockRetries = 0

		while player.Parent and os.clock() < deadline do
			local ok, stateOrErr, lockMeta = SaveService.loadPlayer(userId)
			if ok then
				print(string.format("[SaveService] Player %d data loaded successfully, spawning character", userId))
				_spawnAfterDataLoad(player, userId)
				return
			end

			lastErr = stateOrErr
			if stateOrErr == "SESSION_LOCKED" then
				local owner = lockMeta and lockMeta.jobId or "unknown"
				local stamp = lockMeta and lockMeta.timestamp or "nil"
				local signature = tostring(owner) .. ":" .. tostring(stamp)

				if signature == lastLockSignature then
					stableLockRetries += 1
				else
					lastLockSignature = signature
					stableLockRetries = 1
				end

				local retriesReady = stableLockRetries >= SESSION_LOCK_STABLE_RETRY_THRESHOLD
				local delayReady = (stableLockRetries * PLAYER_LOAD_RETRY_INTERVAL) >= SESSION_LOCK_FORCE_ACQUIRE_DELAY
				if ENABLE_SESSION_LOCK_FORCE_ACQUIRE and not forceTried and retriesReady and delayReady then
					forceTried = true
					warn(string.format("[SaveService] Trying force acquire for player %d after stable lock observation (%d retries)", userId, stableLockRetries))
					local forceOk, forceStateOrErr = SaveService.loadPlayer(userId, true)
					if forceOk then
						print(string.format("[SaveService] Player %d force-acquired successfully, spawning character", userId))
						_spawnAfterDataLoad(player, userId)
						return
					end
					lastErr = forceStateOrErr
				end

				warn(string.format("[SaveService] Player %d still session-locked (owner=%s). Retrying...", userId, tostring(owner)))
			else
				lastLockSignature = nil
				stableLockRetries = 0
				warn(string.format("[SaveService] Retrying load for player %d (reason=%s)", userId, tostring(stateOrErr)))
			end

			task.wait(PLAYER_LOAD_RETRY_INTERVAL)
		end

		if player.Parent then
			warn(string.format("[SaveService] Failed to load player %d after retries. Last error: %s", userId, tostring(lastErr)))
			if lastErr == "SESSION_LOCKED" then
				player:Kick("이전 접속 세션이 아직 정리되지 않았습니다. 잠시 후 다시 접속해 주세요.")
			else
				player:Kick("데이터 로드에 실패했습니다. 잠시 후 다시 접속해 주세요.")
			end
		end
	end)
end

--- PlayerRemoving 이벤트
local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	print(string.format("[SaveService] Handling PlayerRemoving for %d...", userId))
	
	-- 1. [CRITICAL] 시스템별 순차 정리 시작
	-- (상태 변경 -> 데이터 동기화 -> 최종 저장 순서 엄수)
	
	-- A. 파티/소환 정리 (PalboxState 변경을 수반하므로 먼저 실행)
	local partyOk, PartyService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.PartyService) end)
	if partyOk and PartyService and PartyService.prepareLogout then
		PartyService.prepareLogout(userId)
	end

	-- B. 팰 보관함 정리 (메모리 캐시를 playerState로 반영)
	local palOk, PalboxService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.PalboxService) end)
	if palOk and PalboxService and PalboxService.prepareLogout then
		PalboxService.prepareLogout(player)
	end
	
	-- 2. 최종 저장 (isLogout=true로 세션 잠금 해제)
	local ok, err = SaveService.savePlayer(userId, nil, true)
	if not ok then
		warn(string.format("[SaveService] PlayerRemoving save failed for %d: %s", userId, tostring(err)))
	else
		print(string.format("[SaveService] Successfully saved and unlocked player %d on logout", userId))
	end

	-- 2b. 월드/파티션 저장은 BindToClose에서 일괄 처리 (DataStore 큐 오버플로 방지)
	
	-- 3. 메모리 정리
	-- 인벤토리 서비스 정리
	local invOk, InventoryService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.InventoryService) end)
	if invOk and InventoryService and InventoryService.removeInventory then
		InventoryService.removeInventory(userId)
	end
	
	-- 캐시 제거
	playerStates[userId] = nil
end

--- Autosave 루프
local function startAutosave()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			SaveService.saveNow()
		end
	end)
end

--========================================
-- Network Handlers
--========================================

--- Save.Now 핸들러 (디버그/어드민용)
local function handleSaveNow(player: Player, payload: any)
	local worldOk, playerOk, playerFail = SaveService.saveNow()
	return {
		worldSaved = worldOk,
		playersSaved = playerOk,
		playersFailed = playerFail,
	}
end

--- Save.Status 핸들러
local function handleSaveStatus(player: Player, payload: any)
	return {
		lastSaveTime = lastSaveTime,
		playerCount = 0, -- 카운트
		autosaveInterval = AUTOSAVE_INTERVAL,
	}
end

--========================================
-- Initialization
--========================================

function SaveService.Init(netController: any)
	if initialized then
		warn("[SaveService] Already initialized")
		return
	end
	
	NetController = netController
	
	-- DataStoreClient 초기화
	DataStoreClient.Init()
	
	-- 월드 로드
	SaveService.loadWorld()
	
	-- 플레이어 이벤트 연결
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	
	-- Autosave 시작
	startAutosave()

	-- BindToClose: 서버 종료 시 월드 + 파티션 + 모든 플레이어 강제 저장
	game:BindToClose(function()
		print("[SaveService] BindToClose triggered — saving all data...")
		-- 플레이어 저장 (onPlayerRemoving에서 이미 처리되지 않은 플레이어만)
		for userId, _ in pairs(playerStates) do
			local p = Players:GetPlayerByUserId(userId)
			if p then
				pcall(SaveService.savePlayer, userId, nil, true)
			end
		end
		-- 월드 저장 (saveWorld 내부 디바운스가 중복 호출 방지)
		_lastWorldSaveTime = 0 -- BindToClose는 반드시 저장
		pcall(SaveService.saveWorld)
		for pId, _ in pairs(partitionStates) do
			pcall(SaveService.savePartition, pId)
		end
		print("[SaveService] BindToClose save complete")
	end)
	
	initialized = true
	print(string.format("[SaveService] Initialized - Autosave: %ds, Snapshots: %d", 
		AUTOSAVE_INTERVAL, MAX_SNAPSHOTS))
end

--- 네트워크 핸들러 반환
function SaveService.GetHandlers()
	return {
		["Save.Now"] = handleSaveNow,
		["Save.Status"] = handleSaveStatus,
	}
end

return SaveService
