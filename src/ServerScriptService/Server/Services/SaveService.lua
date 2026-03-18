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

--========================================
-- Private State
--========================================
local initialized = false
local playerStates = {}   -- [userId] = playerState
local worldState = nil    -- 월드 상태 (Global: Metadata, Time 등)
local partitionStates = {} -- [partitionId] = partitionState (Local: Base-specific structures, storages)
local lastSaveTime = 0
local CURRENT_JOB_ID = game.JobId
local SESSION_LOCK_TIMEOUT = 600 -- 10분 이상 업데이트 없으면 강제 잠금 해제

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
				[Enums.StatId.WEIGHT] = 0,
				[Enums.StatId.WORK_SPEED] = 0,
				[Enums.StatId.ATTACK] = 0,
			}
		},
		-- 장착 중인 아이템 (Head, Body, Feet, Hand)
		equipment = _getDefaultEquipment(),
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
	state.stats = type(state.stats) == "table" and state.stats or {}
	state.stats.lastLogin = state.stats.lastLogin or 0
	state.snapshots = type(state.snapshots) == "table" and state.snapshots or {}
	state._session = type(state._session) == "table" and state._session or { jobId = nil, timestamp = 0 }

	return state
end

local function _normalizeWorldState(state: any): any
	if type(state) ~= "table" then
		state = _getDefaultWorldSave()
	end

	state.structures = type(state.structures) == "table" and state.structures or {}
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
	
	local success, data = DataStoreClient.update(key, function(oldData)
		if not oldData then 
			local newSave = _getDefaultPlayerSave()
			newSave._session.jobId = CURRENT_JOB_ID
			newSave._session.timestamp = os.time()
			return newSave
		end
		
		-- 세션 잠금 확인
		if oldData._session and oldData._session.jobId and oldData._session.jobId ~= CURRENT_JOB_ID then
			local lastUpdate = oldData._session.timestamp or 0
			if os.time() - lastUpdate < SESSION_LOCK_TIMEOUT then
				if not shouldForceAcquire then
					-- 아직 다른 서버가 사용 중 (로딩 거부)
					return nil -- 이 값은 DataStoreClient.update에서 success=true, result=nil로 반환됨
				end
				warn(string.format("[SaveService] Force-acquiring session lock for user %d (from %s -> %s)", userId, tostring(oldData._session.jobId), CURRENT_JOB_ID))
			end
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
		warn(string.format("[SaveService] Player %d is locked by another server (JobId: %s)", userId, data and data._session and data._session.jobId or "Unknown"))
		return false, "SESSION_LOCKED"
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
	
	-- [수면/로그아웃 위치 저장] 게임에 접속중인 상태라면 현재 좌표를 마지막 수면 위치로 갱신
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
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
			local lastUpdate = oldData._session.timestamp or 0
			if os.time() - lastUpdate < SESSION_LOCK_TIMEOUT then
				warn(string.format("[SaveService] Refusing to overwrite player %d: Session owned by %s", userId, oldData._session.jobId))
				return nil 
			end
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
function SaveService.saveWorld(snapshot: any?): (boolean, string?)
	local state = snapshot or worldState
	
	if not state then
		warn("[SaveService] No world state to save")
		return false, "NO_STATE"
	end
	
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
	end
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

--- PlayerAdded 이벤트
local function onPlayerAdded(player: Player)
	local userId = player.UserId
	local deadline = os.clock() + PLAYER_LOAD_RETRY_WINDOW
	local lastErr = nil
	local lockSeenAt = nil
	local forceTried = false

	while player.Parent and os.clock() < deadline do
		local ok, stateOrErr = SaveService.loadPlayer(userId)
		if ok then
			return
		end

		lastErr = stateOrErr
		if stateOrErr == "SESSION_LOCKED" then
			if not lockSeenAt then
				lockSeenAt = os.clock()
			end

			if ENABLE_SESSION_LOCK_FORCE_ACQUIRE and not forceTried and lockSeenAt and (os.clock() - lockSeenAt) >= SESSION_LOCK_FORCE_ACQUIRE_DELAY then
				forceTried = true
				warn(string.format("[SaveService] Trying force acquire for player %d after session-lock delay", userId))
				local forceOk, forceStateOrErr = SaveService.loadPlayer(userId, true)
				if forceOk then
					return
				end
				lastErr = forceStateOrErr
			end

			warn(string.format("[SaveService] Player %d still session-locked. Retrying...", userId))
		else
			lockSeenAt = nil
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
