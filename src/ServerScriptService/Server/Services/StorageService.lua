-- StorageService.lua
-- 공유 창고 서비스 (서버 권위, SSOT)
-- 유지비 활성 보호영역에서는 소유자만 접근, 만료 시 누구나 약탈 가능
-- 영속 저장: WorldSave.storages

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local StorageService = {}

--========================================
-- Dependencies
--========================================
local initialized = false
local NetController = nil
local SaveService = nil
local InventoryService = nil

-- [userId] = { [storageId] = true }
local playerSessions = {}
-- [storageId] = { [userId] = true }
local viewingPlayers = {}

-- BuildService 참조 (파티션 조회를 위해 필요)
local BuildService = nil
local BaseClaimService = nil
local TotemService = nil
-- Internal: Storage Management
--========================================

local function _canAccessStorage(player: Player, storageId: string): boolean
	if not BuildService or not BuildService.get then
		return false
	end

	local structure = BuildService.get(storageId)
	if not structure then
		-- 야생/비구조물 창고는 기존처럼 접근 허용
		return true
	end

	if structure.ownerId == player.UserId then
		return true
	end

	if TotemService and TotemService.canRaidStructure then
		return TotemService.canRaidStructure(player.UserId, structure)
	end

	return false
end

--- 기본 창고 스키마 생성
local function _createDefaultStorage()
	return {
		slots = {},
		version = 1,
		updatedAt = os.time(),
	}
end

--- 특정 창고의 파티션 ID 찾기
local function _getPartitionIdForStorage(storageId: string): string?
	if not BuildService then return nil end
	local struct = BuildService.get(storageId)
	return struct and struct.partitionId
end

--- 창고 데이터 참조 가져오기 (파티셔닝 지원)
local function _getStorages(storageId: string): {[string]: any}
	local pId = _getPartitionIdForStorage(storageId)
	
	if pId then
		-- 베이스 파티션에서 가져오기
		local pState = SaveService.getPartition(pId)
		if pState then
			if not pState.storages then pState.storages = {} end
			return pState.storages
		end
	end
	
	-- 파티션이 없거나 야생일 경우 월드 상태에서 가져오기
	local worldState = SaveService.getWorldState()
	if not worldState then return {} end
	
	if not worldState.wildernessStorages then
		-- 하위 호환성: 기존 storages가 있으면 wildernessStorages로 간주
		worldState.wildernessStorages = worldState.storages or {}
		worldState.storages = nil
	end
	
	return worldState.wildernessStorages
end

--- 특정 창고 가져오기 (없으면 생성)
local function _getOrCreateStorage(storageId: string): any
	local storages = _getStorages(storageId)
	
	if not storages[storageId] then
		storages[storageId] = _createDefaultStorage()
	end
	
	return storages[storageId]
end

--- 특정 창고 가져오기 (없으면 nil)
local function _getStorage(storageId: string): any?
	local storages = _getStorages(storageId)
	return storages[storageId]
end

--- 창고 dirty 플래그 설정 (저장 필요 표시)
local function _markStorageDirty(storageId: string)
	local storage = _getStorage(storageId)
	if storage then
		storage.updatedAt = os.time()
	end
end

--========================================
-- Internal: Events
--========================================

--- Storage.Changed 이벤트 발생 (해당 창고를 보고 있는 유저에게만)
local function _emitStorageChanged(storageId: string, changes: any)
	if NetController and viewingPlayers[storageId] then
		for userId, _ in pairs(viewingPlayers[storageId]) do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				NetController.FireClient(player, "Storage.Changed", {
					storageId = storageId,
					changes = changes,
				})
			end
		end
	end
end

--- 세션 관리: 창고 시청자 추가
local function _addViewer(storageId: string, userId: number)
	if not viewingPlayers[storageId] then
		viewingPlayers[storageId] = {}
	end
	viewingPlayers[storageId][userId] = true
	
	if not playerSessions[userId] then
		playerSessions[userId] = {}
	end
	playerSessions[userId][storageId] = true
end

--- 세션 관리: 창고 시청자 제거
local function _removeViewer(storageId: string, userId: number)
	if viewingPlayers[storageId] then
		viewingPlayers[storageId][userId] = nil
		if next(viewingPlayers[storageId]) == nil then
			viewingPlayers[storageId] = nil
		end
	end
	
	if playerSessions[userId] then
		playerSessions[userId][storageId] = nil
		if next(playerSessions[userId]) == nil then
			playerSessions[userId] = nil
		end
	end
end

--- 슬롯 데이터를 변경 델타로 변환
local function _makeChange(storage: any, slot: number): any
	local slotData = storage.slots[slot]
	if slotData then
		return { slot = slot, itemId = slotData.itemId, count = slotData.count }
	else
		return { slot = slot, empty = true }
	end
end

--========================================
-- Public API: Open
--========================================

--- 창고 열기
function StorageService.open(player: Player, storageId: string): (boolean, string?, any?)
	if not storageId or type(storageId) ~= "string" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end

	if not _canAccessStorage(player, storageId) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	local storage = _getOrCreateStorage(storageId)
	
	-- 슬롯 데이터 변환
	local slots = {}
	for slot = 1, Balance.STORAGE_SLOTS do
		local slotData = storage.slots[slot]
		if slotData then
			table.insert(slots, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
			})
		end
	end
	
	_addViewer(storageId, player.UserId)
	
	return true, nil, {
		storageId = storageId,
		slots = slots,
		maxSlots = Balance.STORAGE_SLOTS,
		maxStack = Balance.MAX_STACK,
	}
end

--========================================
-- Public API: Close
--========================================

function StorageService.close(player: Player, storageId: string): (boolean, string?, any?)
	if not storageId or type(storageId) ~= "string" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	_removeViewer(storageId, player.UserId)
	return true, nil, { storageId = storageId }
end

--========================================
-- Public API: Move (핵심)
--========================================

--- 창고 <-> 플레이어 인벤토리 간 아이템 이동
--- sourceType: "player" | "storage"
--- targetType: "player" | "storage"
function StorageService.move(
	player: Player,
	storageId: string,
	sourceType: string,
	sourceSlot: number,
	targetType: string,
	targetSlot: number,
	count: number?
): (boolean, string?, any?)
	
	local userId = player.UserId
	
	-- storageId 검증
	if not storageId or type(storageId) ~= "string" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- sourceType / targetType 검증
	if sourceType ~= "player" and sourceType ~= "storage" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	if targetType ~= "player" and targetType ~= "storage" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end

	if not _canAccessStorage(player, storageId) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	-- 컨테이너 참조 가져오기
	local storage = _getOrCreateStorage(storageId)
	local playerInv = InventoryService.getInventory(userId)
	
	if not playerInv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 소스/타겟 컨테이너 결정
	local sourceContainer, sourceMaxSlots
	local targetContainer, targetMaxSlots
	
	if sourceType == "player" then
		sourceContainer = playerInv
		sourceMaxSlots = Balance.INV_SLOTS
	else
		sourceContainer = storage
		sourceMaxSlots = Balance.STORAGE_SLOTS
	end
	
	if targetType == "player" then
		targetContainer = playerInv
		targetMaxSlots = Balance.INV_SLOTS
	else
		targetContainer = storage
		targetMaxSlots = Balance.STORAGE_SLOTS
	end
	
	-- MoveInternal 호출
	local success, errorCode, data = InventoryService.MoveInternal(
		sourceContainer,
		sourceSlot,
		sourceMaxSlots,
		targetContainer,
		targetSlot,
		targetMaxSlots,
		count
	)
	
	if not success then
		return false, errorCode, nil
	end
	
	-- 이벤트 발행
	-- 1. 플레이어 인벤토리 변경 시 Inventory.Changed
	local invChanges = {}
	if sourceType == "player" and data.sourceChanges then
		for _, change in ipairs(data.sourceChanges) do
			table.insert(invChanges, change)
		end
	end
	if targetType == "player" and data.targetChanges then
		for _, change in ipairs(data.targetChanges) do
			table.insert(invChanges, change)
		end
	end
	
	if #invChanges > 0 then
		NetController.FireClient(player, "Inventory.Changed", {
			userId = userId,
			changes = invChanges,
		})
	end
	
	-- 2. 창고 변경 시 Storage.Changed (모든 클라이언트에게)
	local storageChanges = {}
	if sourceType == "storage" and data.sourceChanges then
		for _, change in ipairs(data.sourceChanges) do
			table.insert(storageChanges, change)
		end
	end
	if targetType == "storage" and data.targetChanges then
		for _, change in ipairs(data.targetChanges) do
			table.insert(storageChanges, change)
		end
	end
	
	if #storageChanges > 0 then
		_emitStorageChanged(storageId, storageChanges)
		_markStorageDirty(storageId)
	end
	
	return true, nil, {
		movedItem = data.movedItem,
		invChanges = invChanges,
		storageChanges = storageChanges,
	}
end

--========================================
-- Public API: Utility
--========================================

--- 창고 정보 가져오기 (디버그용)
function StorageService.getStorageInfo(storageId: string): any?
	return _getStorage(storageId)
end

--- 모든 창고 ID 목록 (주의: 파티셔닝으로 인해 전체 순회 부하 발생 가능, 실사용 시 최적화 필요)
function StorageService.getAllStorageIds(): {string}
	local ids = {}
	-- 1. 야생 창고
	local worldState = SaveService.getWorldState()
	if worldState and worldState.wildernessStorages then
		for id, _ in pairs(worldState.wildernessStorages) do table.insert(ids, id) end
	end
	-- 2. 빌드 서비스 내 모든 구조물 순회 (Storage인 것만)
	if BuildService then
		for _, struct in pairs(BuildService.getAll()) do
			-- 편의상 일단 ID만 수집
			table.insert(ids, struct.id)
		end
	end
	return ids
end

--- 내부 API: 아이템 직접 추가 (자동화 서비스용)
--- @param storageId 창고 ID
--- @param itemId 아이템 ID
--- @param count 수량
--- @return remaining 남은 수량 (추가 못한 양)
function StorageService.addItemInternal(storageId: string, itemId: string, count: number): number
	if not storageId or not itemId or count <= 0 then
		return count
	end
	
	local storage = _getOrCreateStorage(storageId)
	local maxStack = Balance.MAX_STACK or 99
	local maxSlots = Balance.STORAGE_SLOTS or 20
	local remaining = count
	local changes = {}
	
	-- 1단계: 기존 스택에 먼저 추가
	for slot = 1, maxSlots do
		if remaining <= 0 then break end
		
		local slotData = storage.slots[slot]
		if slotData and slotData.itemId == itemId and slotData.count < maxStack then
			local space = maxStack - slotData.count
			local toAdd = math.min(remaining, space)
			slotData.count = slotData.count + toAdd
			remaining = remaining - toAdd
			table.insert(changes, _makeChange(storage, slot))
		end
	end
	
	-- 2단계: 빈 슬롯에 추가
	for slot = 1, maxSlots do
		if remaining <= 0 then break end
		
		local slotData = storage.slots[slot]
		if slotData == nil then
			local toAdd = math.min(remaining, maxStack)
			storage.slots[slot] = { itemId = itemId, count = toAdd }
			remaining = remaining - toAdd
			table.insert(changes, _makeChange(storage, slot))
		end
	end
	
	-- 변경 사항 브로드캐스트
	if #changes > 0 then
		_emitStorageChanged(storageId, changes)
	end
	
	return remaining
end

--========================================
-- Network Handlers
--========================================

local function handleOpen(player: Player, payload: any)
	local storageId = payload.storageId
	
	local success, errorCode, data = StorageService.open(player, storageId)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleClose(player: Player, payload: any)
	local storageId = payload.storageId
	
	local success, errorCode, data = StorageService.close(player, storageId)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleMove(player: Player, payload: any)
	local storageId = payload.storageId
	local sourceType = payload.sourceType
	local sourceSlot = payload.sourceSlot
	local targetType = payload.targetType
	local targetSlot = payload.targetSlot
	local count = payload.count  -- optional
	
	local success, errorCode, data = StorageService.move(
		player, storageId, sourceType, sourceSlot, targetType, targetSlot, count
	)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

--========================================
-- Initialization
--========================================

function StorageService.Init(netController: any, saveService: any, inventoryService: any, buildService: any, baseClaimService: any)
	if initialized then
		warn("[StorageService] Already initialized")
		return
	end
	
	NetController = netController
	SaveService = saveService
	InventoryService = inventoryService
	BuildService = buildService
	BaseClaimService = baseClaimService
	
	-- 퇴장 시 시청 세션 정리
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if playerSessions[userId] then
			for sId, _ in pairs(playerSessions[userId]) do
				_removeViewer(sId, userId)
			end
		end
	end)
	
	initialized = true
	print(string.format("[StorageService] Initialized - Slots: %d, MaxStack: %d",
		Balance.STORAGE_SLOTS, Balance.MAX_STACK))
end

function StorageService.SetTotemService(totemService: any)
	TotemService = totemService
end

function StorageService.GetHandlers()
	return {
		["Storage.Open.Request"] = handleOpen,
		["Storage.Close.Request"] = handleClose,
		["Storage.Move.Request"] = handleMove,
	}
end

return StorageService
