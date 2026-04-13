-- StorageController.lua
-- 클라이언트 창고 컨트롤러
-- 서버 StorageService와 통신 및 UI 상태 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)
local InventoryController = require(script.Parent.Parent.Controllers.InventoryController)

local StorageController = {}

--========================================
-- Private State
--========================================
local initialized = false
local currentStorageId = nil
local storageData = nil -- { storageId, slots, maxSlots, maxStack }
local lastOpenTime = 0

--========================================
-- Public API
--========================================

function StorageController.openStorage(storageId: string)
	if currentStorageId == storageId and (tick() - lastOpenTime < 0.5) then return end
	
	local success, data = NetClient.Request("Storage.Open.Request", {
		storageId = storageId
	})
	
	if success and data then
		currentStorageId = storageId
		storageData = data
		lastOpenTime = tick()
		
		-- UIManager를 통해 UI 표시
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.openStorage(currentStorageId, storageData)
	else
		local UIManager = require(script.Parent.Parent.UIManager)
		if tostring(data) == "NO_PERMISSION" then
			UIManager.notify("토템 보호가 활성화된 거점 보관함입니다. 유지비 만료 후 약탈 가능합니다.", Color3.fromRGB(255, 120, 120))
		else
			UIManager.notify("보관함을 열 수 없습니다. 다시 시도해주세요.", Color3.fromRGB(255, 120, 120))
		end
		warn("[StorageController] Failed to open storage:", storageId, data)
	end
end

function StorageController.closeStorage()
	if not currentStorageId then return end
	
	NetClient.Request("Storage.Close.Request", {
		storageId = currentStorageId
	})
	
	currentStorageId = nil
	storageData = nil
end

function StorageController.getStorageData()
	return storageData
end

function StorageController.getStorageSlot(slot: number)
	if not storageData or type(storageData.slots) ~= "table" then
		return nil
	end
	for _, item in ipairs(storageData.slots) do
		if item.slot == slot then
			return item
		end
	end
	return nil
end

--- 아이템 이동 요청 (인벤토리 <-> 창고)
--- @param slot 이동할 슬롯 번호
--- @param fromType "player" | "storage"
function StorageController.moveItem(slot: number, fromType: string, targetSlot: number?, targetType: string?)
	if not currentStorageId then return end
	
	targetType = targetType or ((fromType == "player") and "storage" or "player")
	targetSlot = targetSlot or 0
	if targetSlot == slot and targetType == fromType then
		return
	end
	
	local success, err = NetClient.Request("Storage.Move.Request", {
		storageId = currentStorageId,
		sourceType = fromType,
		sourceSlot = slot,
		targetType = targetType,
		targetSlot = targetSlot,
	})

	if not success and tostring(err) == "NO_PERMISSION" then
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.notify("토템 보호가 활성화되어 아이템 이동이 차단되었습니다.", Color3.fromRGB(255, 120, 120))
	end
end

function StorageController.moveGold(sourceType: string, amount: number?)
	if not currentStorageId then return end

	local success, err = NetClient.Request("Storage.MoveGold.Request", {
		storageId = currentStorageId,
		sourceType = sourceType,
		amount = amount,
	})

	if not success then
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.notify("골드를 이동할 수 없습니다.", Color3.fromRGB(255, 120, 120))
		warn("[StorageController] Failed to move gold:", err)
	end
end

--========================================
-- Event Handlers
--========================================

local function onStorageChanged(data)
	if not currentStorageId or data.storageId ~= currentStorageId then return end
	
	-- 로컬 데이터 업데이트
	if data.changes then
		for _, change in ipairs(data.changes) do
			if change.empty then
				-- 슬롯 제거
				for i, si in ipairs(storageData.slots) do
					if si.slot == change.slot then
						table.remove(storageData.slots, i)
						break
					end
				end
			else
				-- 슬롯 업데이트 또는 추가
				local found = false
				for i, si in ipairs(storageData.slots) do
					if si.slot == change.slot then
						si.itemId = change.itemId
						si.count = change.count
						si.durability = change.durability
						si.attributes = change.attributes
						found = true
						break
					end
				end
				if not found then
					table.insert(storageData.slots, {
						slot = change.slot,
						itemId = change.itemId,
						count = change.count,
						durability = change.durability,
						attributes = change.attributes,
					})
				end
			end
		end
	end

	if data.gold ~= nil then
		storageData.gold = data.gold
	end
	
	-- UI 리프레시
	local UIManager = require(script.Parent.Parent.UIManager)
	UIManager.refreshStorage()
end

--========================================
-- Initialization
--========================================

function StorageController.Init()
	if initialized then return end
	
	NetClient.On("Storage.Changed", onStorageChanged)
	
	initialized = true
	print("[StorageController] Initialized")
end

return StorageController
