-- InventoryController.lua
-- 클라이언트 인벤토리 컨트롤러
-- 서버 Inventory 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local InventoryController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 인벤토리 캐시 [slot] = { itemId, count } or nil
local inventoryCache = {}
local equipmentCache = {
	HEAD = nil,
	TOP = nil,
	BOTTOM = nil,
	SUIT = nil,
	HAND = nil,
}
local totalWeight = 0
local maxWeight = 300

-- 변경 콜백 리스너
local changeListeners = {}

--========================================
-- Public API: Cache Access
--========================================

function InventoryController.getInventoryCache()
	return inventoryCache
end

function InventoryController.getItems()
	return inventoryCache
end

function InventoryController.getSlot(slot: number)
	return inventoryCache[slot]
end

function InventoryController.getWeightInfo()
	return totalWeight, maxWeight
end

function InventoryController.getEquipment()
	return equipmentCache
end

function InventoryController.requestEquip(fromSlot: number, toSlotName: string)
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Equip.Request", {
			fromSlot = fromSlot,
			toSlot = toSlotName
		})
		if not ok then
			warn("[InventoryController] Equip failed:", data)
		end
	end)
end

function InventoryController.requestUnequip(slotName: string)
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Unequip.Request", {
			slot = slotName
		})
		if not ok then
			warn("[InventoryController] Unequip failed:", data)
		end
	end)
end

--- 아이템별 총 보유 수량 집계 (ID 기반)
function InventoryController.getItemCounts()
	local counts = {}
	for _, data in pairs(inventoryCache) do
		if data and data.itemId then
			counts[data.itemId] = (counts[data.itemId] or 0) + (data.count or 0)
		end
	end
	return counts
end

--- 아이템 이동/교환 (드래그 앤 드롭 지원)
function InventoryController.moveItem(fromSlot: any, toSlot: any, toType: string)
	if fromSlot == toSlot and toType == "bag" then return end
	
	if toType == "bag" or toType == "hotbar" then
		-- 가방이나 핫바는 모두 인벤토리 슬롯 번호로 취급
		InventoryController.swapSlots(tonumber(fromSlot), tonumber(toSlot))
	elseif toType == "equip" then
		-- 장비 슬롯으로 이동 (장착 요청)
		InventoryController.requestEquip(tonumber(fromSlot), toSlot)
	end
end

function InventoryController.swapSlots(fromSlot: number, toSlot: number)
	if fromSlot == toSlot then return end
	
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Move.Request", {
			fromSlot = tonumber(fromSlot) or fromSlot,
			toSlot = tonumber(toSlot) or toSlot
		})
		
		if ok then
			-- 서버에서 Inventory.Changed 이벤트를 보내므로 로컬 캐시는 자동으로 업데이트됨
			print("[InventoryController] Swapped slots:", fromSlot, "->", toSlot)
		else
			warn("[InventoryController] Failed to swap slots:", data)
		end
	end)
end

function InventoryController.requestDrop(slot: number, count: number)
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Drop.Request", {
			slot = slot,
			count = count
		})
		if not ok then
			warn("[InventoryController] Drop failed:", data)
		end
	end)
end

function InventoryController.requestUse(slot: number)
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Use.Request", {
			slot = slot
		})
		if not ok then
			warn("[InventoryController] Use failed:", data)
		end
	end)
end

function InventoryController.requestSort()
	task.spawn(function()
		NetClient.Request("Inventory.Sort.Request", {})
	end)
end

function InventoryController.requestSetActiveSlot(slot: number)
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.ActiveSlot.Request", { slot = slot })
		if not ok then
			warn("[InventoryController] Failed to set active slot:", data)
		end
	end)
end


--========================================
-- Public API: Event Listeners
--========================================

function InventoryController.onChanged(callback: () -> ())
	table.insert(changeListeners, callback)
end

--========================================
-- Event Handlers
--========================================

local function fireChangeListeners()
	for _, callback in ipairs(changeListeners) do
		pcall(callback)
	end
end

local function onInventoryChanged(data)
	if not data then return end
	
	-- Store old cache to calc diff for notifications
	local oldTotals = {}
	for k, v in pairs(inventoryCache) do
		if v and v.itemId then oldTotals[v.itemId] = (oldTotals[v.itemId] or 0) + (v.count or 0) end
	end
	
	if data.fullInventory then
		-- 전체 동기화 (Full Sync) - 배열 형식 [{slot, itemId, count}, ...]
		inventoryCache = {}
		for _, item in ipairs(data.fullInventory) do
			if item and item.slot then
				inventoryCache[item.slot] = {
					itemId = item.itemId,
					count = item.count,
					durability = item.durability,
				}
			end
		end
	elseif data.changes then
		-- 부분 동기화 (Delta Sync)
		for _, change in ipairs(data.changes) do
			local slot = change.slot
			if change.empty then
				inventoryCache[slot] = nil
			else
				inventoryCache[slot] = {
					itemId = change.itemId,
					count = change.count,
					durability = change.durability,
				}
			end
		end
	end

	if data.totalWeight then totalWeight = data.totalWeight end
	if data.maxWeight then maxWeight = data.maxWeight end
	if data.equipment then equipmentCache = data.equipment end
	
	-- Toast UI Notification check (Only run if actual item count increased)
	local UISuccess, UIMgr = pcall(function() return require(script.Parent.Parent.UIManager) end)
	if data.changes and UISuccess and UIMgr and UIMgr.notify then
		local newTotals = {}
		for k, v in pairs(inventoryCache) do
			if v and v.itemId then newTotals[v.itemId] = (newTotals[v.itemId] or 0) + (v.count or 0) end
		end
		
		local notified = {}
		for _, change in ipairs(data.changes) do
			if change and not change.empty and change.count and change.itemId then
				local itemId = change.itemId
				if not notified[itemId] then
					notified[itemId] = true
					local diff = (newTotals[itemId] or 0) - (oldTotals[itemId] or 0)
					if diff > 0 then
						local DSuccess, DataHelper = pcall(function() return require(ReplicatedStorage.Shared.Util.DataHelper) end)
						local name = itemId
						if DSuccess and DataHelper then
							local itemData = DataHelper.GetData("ItemData", itemId)
							if itemData then
								name = itemData.name or itemId
							end
						end
						UIMgr.notify(string.format("획득: %s x%d", name, diff)) -- 색상 파라미터 제외하여 UITheme의 기본 흰색(C.WHITE)을 따르게 함
					end
				end
			end
		end
	end
	
	-- 콜백 호출
	fireChangeListeners()
end

--========================================
-- Initialization
--========================================

function InventoryController.Init()
	if initialized then return end
	
	-- 이벤트 리스너 등록
	NetClient.On("Inventory.Changed", onInventoryChanged)
	
	NetClient.On("Inventory.Equipment.Changed", function(data)
		if data and data.equipment then
			equipmentCache = data.equipment
			fireChangeListeners()
		end
	end)
	
	-- 초기 데이터 요청 (서버쪽 SaveStore 지연으로 인한 타임아웃 방지 및 재시도)
	task.spawn(function()
		local fetchedData = nil
		local maxRetries = 15
		local currentTry = 0
		
		while not fetchedData and currentTry < maxRetries do
			local ok, data = NetClient.Request("Inventory.Get.Request", {})
			if ok and data and data.inventory then
				fetchedData = data
				break
			else
				currentTry = currentTry + 1
				if currentTry <= 3 then
					print(string.format("[InventoryController] Waiting for inventory sync... (Attempt %d/%d)", currentTry, maxRetries))
				elseif currentTry % 3 == 0 then
					warn(string.format("[InventoryController] Inventory sync still pending... (Attempt %d/%d)", currentTry, maxRetries))
				end
				task.wait(2) -- 2초마다 동기화 상태 재요청
			end
		end
		
		if fetchedData then
			inventoryCache = {}
			for _, item in ipairs(fetchedData.inventory) do
				inventoryCache[item.slot] = {
					itemId = item.itemId,
					count = item.count,
					durability = item.durability,
				}
			end
			if fetchedData.equipment then equipmentCache = fetchedData.equipment end
			totalWeight = fetchedData.totalWeight or 0
			maxWeight = fetchedData.maxWeight or 300
			fireChangeListeners()
			
			-- 초기 정렬 (Auto-stacking on first load)
			InventoryController.requestSort()
			
			local player = game:GetService("Players").LocalPlayer
			if player then
				player:SetAttribute("InventoryLoaded", true)
			end
		else
			warn("[InventoryController] FATAL: Failed to sync inventory data. The server might have kicked the player or is unreachable.")
			-- 서버에서 킥을 시키겠지만 만일의 사태에 대비해 강제 로딩 해제
			local player = game:GetService("Players").LocalPlayer
			if player then
				player:SetAttribute("InventoryLoaded", true)
			end
		end
	end)

	initialized = true
	print("[InventoryController] Initialized - Weight support added")
end

return InventoryController
