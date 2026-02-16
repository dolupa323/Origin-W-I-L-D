-- StorageService.lua
-- 공유 창고 서비스 (서버 권위, SSOT)
-- 누구나 열기/닫기/꺼내기 가능 (도둑질 허용)
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

--========================================
-- Internal: Storage Management
--========================================

--- 기본 창고 스키마 생성
local function _createDefaultStorage()
	return {
		slots = {},
		version = 1,
		updatedAt = os.time(),
	}
end

--- WorldSave에서 storages 참조 가져오기
local function _getStorages(): {[string]: any}
	local worldState = SaveService.getWorldState()
	if not worldState then
		return {}
	end
	if not worldState.storages then
		worldState.storages = {}
	end
	return worldState.storages
end

--- 특정 창고 가져오기 (없으면 생성)
local function _getOrCreateStorage(storageId: string): any
	local storages = _getStorages()
	
	if not storages[storageId] then
		storages[storageId] = _createDefaultStorage()
	end
	
	return storages[storageId]
end

--- 특정 창고 가져오기 (없으면 nil)
local function _getStorage(storageId: string): any?
	local storages = _getStorages()
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

--- Storage.Changed 이벤트 발생 (모든 클라이언트에게)
local function _emitStorageChanged(storageId: string, changes: any)
	if NetController then
		NetController.FireAllClients("Storage.Changed", {
			storageId = storageId,
			changes = changes,
		})
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

--- 창고 닫기 (클라이언트 UI 정리용, 서버에서는 특별한 처리 없음)
function StorageService.close(player: Player, storageId: string): (boolean, string?, any?)
	if not storageId or type(storageId) ~= "string" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
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

--- 모든 창고 ID 목록
function StorageService.getAllStorageIds(): {string}
	local storages = _getStorages()
	local ids = {}
	for id, _ in pairs(storages) do
		table.insert(ids, id)
	end
	return ids
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

function StorageService.Init(netController: any, saveService: any, inventoryService: any)
	if initialized then
		warn("[StorageService] Already initialized")
		return
	end
	
	NetController = netController
	SaveService = saveService
	InventoryService = inventoryService
	
	initialized = true
	print(string.format("[StorageService] Initialized - Slots: %d, MaxStack: %d",
		Balance.STORAGE_SLOTS, Balance.MAX_STACK))
end

function StorageService.GetHandlers()
	return {
		["Storage.Open.Request"] = handleOpen,
		["Storage.Close.Request"] = handleClose,
		["Storage.Move.Request"] = handleMove,
	}
end

return StorageService
