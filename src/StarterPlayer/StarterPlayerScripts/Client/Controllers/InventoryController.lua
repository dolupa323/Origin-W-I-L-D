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
	if not data or not data.changes then return end
	
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
	
	-- 콜백 호출
	fireChangeListeners()
end

--========================================
-- Initialization
--========================================

function InventoryController.Init()
	if initialized then
		warn("[InventoryController] Already initialized")
		return
	end
	
	-- 이벤트 리스너 등록
	NetClient.On("Inventory.Changed", onInventoryChanged)
	
	initialized = true
	print("[InventoryController] Initialized - listening for Inventory events")
end

return InventoryController
