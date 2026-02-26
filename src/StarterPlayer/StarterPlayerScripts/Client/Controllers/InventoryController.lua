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

--- 아이템 슬롯 변경 (드래그 앤 드롭용)
function InventoryController.swapSlots(fromSlot: number, toSlot: number)
	if fromSlot == toSlot then return end
	
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Move.Request", {
			fromSlot = fromSlot,
			toSlot = toSlot
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
	
	if data.changes then
		for _, change in ipairs(data.changes) do
			local slot = change.slot
			if change.empty then
				inventoryCache[slot] = nil
			else
				inventoryCache[slot] = {
					itemId = change.itemId,
					count = change.count,
				}
			end
		end
	end

	if data.totalWeight then totalWeight = data.totalWeight end
	if data.maxWeight then maxWeight = data.maxWeight end
	
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
	
	-- 초기 데이터 요청
	task.spawn(function()
		local ok, data = NetClient.Request("Inventory.Get.Request", {})
		if ok and data and data.inventory then
			inventoryCache = {}
			for _, item in ipairs(data.inventory) do
				inventoryCache[item.slot] = {
					itemId = item.itemId,
					count = item.count,
				}
			end
			totalWeight = data.totalWeight or 0
			maxWeight = data.maxWeight or 300
			fireChangeListeners()
			
			-- 초기 정렬 (Auto-stacking on first load)
			InventoryController.requestSort()
		end
	end)

	initialized = true
	print("[InventoryController] Initialized - Weight support added")
end

return InventoryController
