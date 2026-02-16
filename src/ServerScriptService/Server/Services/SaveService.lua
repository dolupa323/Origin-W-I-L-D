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

local Server = ServerScriptService:WaitForChild("Server")
local Persistence = Server:WaitForChild("Persistence")
local DataStoreClient = require(Persistence.DataStoreClient)

local SaveService = {}

--========================================
-- Configuration
--========================================
local AUTOSAVE_INTERVAL = 60  -- 초
local MAX_SNAPSHOTS = 3       -- 롤백 스냅샷 수
local SAVE_VERSION = 1        -- 스키마 버전

--========================================
-- Private State
--========================================
local initialized = false
local playerStates = {}   -- [userId] = playerState
local worldState = nil    -- 월드 상태
local lastSaveTime = 0

-- NetController 참조
local NetController = nil

--========================================
-- Schema Definitions (Phase 1-3 초기 구조)
--========================================

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
		unlockedTech = {},
		-- 통계
		stats = {
			playTime = 0,
			createdAt = os.time(),
			lastLogin = os.time(),
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
			createdAt = os.time(),
			lastSave = os.time(),
		},
		-- 스냅샷 (롤백용)
		snapshots = {},
		-- 중요: 다음 필드는 절대 저장 금지!
		-- drops = XXX (금지)
		-- wildlife = XXX (금지)
		-- resourceNodes = XXX (금지)
	}
end

--========================================
-- Internal Functions
--========================================

--- 스냅샷 로테이션 (FIFO, max 3개)
local function _rotateSnapshots(snapshots: {any}, newSnapshot: any, maxSnapshots: number?): {any}
	local max = maxSnapshots or MAX_SNAPSHOTS
	local result = snapshots or {}
	
	-- 새 스냅샷 추가
	table.insert(result, 1, {
		timestamp = os.time(),
		data = newSnapshot,
	})
	
	-- 최대 개수 초과 시 오래된 것 제거
	while #result > max do
		table.remove(result)
	end
	
	return result
end

--- 플레이어 스냅샷 생성
local function _makePlayerSnapshot(playerState: any): any
	-- 스냅샷은 현재 상태의 복사본 (스냅샷 필드 제외)
	local snapshot = {}
	for key, value in pairs(playerState) do
		if key ~= "snapshots" then
			snapshot[key] = value
		end
	end
	return snapshot
end

--- 월드 스냅샷 생성
local function _makeWorldSnapshot(worldStateData: any): any
	local snapshot = {}
	for key, value in pairs(worldStateData) do
		if key ~= "snapshots" then
			snapshot[key] = value
		end
	end
	return snapshot
end

--========================================
-- Player Save/Load
--========================================

--- 플레이어 데이터 로드
function SaveService.loadPlayer(userId: number): (boolean, any)
	local key = DataStoreClient.GetPlayerKey(userId)
	local success, data = DataStoreClient.get(key)
	
	if not success then
		warn(string.format("[SaveService] Failed to load player %d: %s", userId, tostring(data)))
		return false, data
	end
	
	if data == nil then
		-- 신규 플레이어
		data = _getDefaultPlayerSave()
	else
		-- 기존 플레이어
		data.stats.lastLogin = os.time()
	end
	
	-- 메모리에 캐시
	playerStates[userId] = data
	
	return true, data
end

--- 플레이어 데이터 저장
function SaveService.savePlayer(userId: number, snapshot: any?): (boolean, string?)
	local state = snapshot or playerStates[userId]
	
	if not state then
		warn(string.format("[SaveService] No state for player %d", userId))
		return false, "NO_STATE"
	end
	
	-- 스냅샷 로테이션
	state.snapshots = _rotateSnapshots(state.snapshots, _makePlayerSnapshot(state))
	state.stats.lastSave = os.time()
	
	local key = DataStoreClient.GetPlayerKey(userId)
	local success, err = DataStoreClient.set(key, state)
	
	if not success then
		warn(string.format("[SaveService] Failed to save player %d: %s", userId, tostring(err)))
	end
	
	return success, err
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
	end
	
	worldState = data
	
	return true, data
end

--- 월드 데이터 저장
function SaveService.saveWorld(snapshot: any?): (boolean, string?)
	local state = snapshot or worldState
	
	if not state then
		warn("[SaveService] No world state to save")
		return false, "NO_STATE"
	end
	
	-- 스냅샷 로테이션
	state.snapshots = _rotateSnapshots(state.snapshots, _makeWorldSnapshot(state))
	state.stats.lastSave = os.time()
	
	local key = DataStoreClient.Keys.WORLD_MAIN
	local success, err = DataStoreClient.set(key, state)
	
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
-- Save All (Admin/Autosave)
--========================================

--- 전체 저장 (모든 플레이어 + 월드)
function SaveService.saveNow(): (boolean, number, number)
	local playerSuccess = 0
	local playerFail = 0
	
	-- 모든 플레이어 저장
	for userId, _ in pairs(playerStates) do
		local ok, _ = SaveService.savePlayer(userId)
		if ok then
			playerSuccess += 1
		else
			playerFail += 1
		end
	end
	
	-- 월드 저장
	local worldOk, _ = SaveService.saveWorld()
	
	lastSaveTime = os.time()
	
	return worldOk, playerSuccess, playerFail
end

--========================================
-- Event Handlers
--========================================

--- PlayerAdded 이벤트
local function onPlayerAdded(player: Player)
	local userId = player.UserId
	SaveService.loadPlayer(userId)
end

--- PlayerRemoving 이벤트
local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	
	-- 저장
	local ok, err = SaveService.savePlayer(userId)
	if not ok then
		warn(string.format("[SaveService] PlayerRemoving save failed: %d - %s", userId, tostring(err)))
	end
	
	-- 메모리에서 제거
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
