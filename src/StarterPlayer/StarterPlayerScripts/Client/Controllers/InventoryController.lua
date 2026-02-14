-- InventoryController.lua
-- 클라이언트 인벤토리 컨트롤러
-- 서버 Inventory 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local Client = StarterPlayerScripts:WaitForChild("Client")
local NetClient = require(Client.NetClient)

local InventoryController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 인벤토리 캐시 [slot] = { itemId, count } or nil
local inventoryCache = {}

--========================================
-- Public API: Cache Access
--========================================

function InventoryController.getInventoryCache()
	return inventoryCache
end

function InventoryController.getSlot(slot: number)
	return inventoryCache[slot]
end

--========================================
-- Event Handlers
--========================================

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
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[InventoryController] Changed: %d slots updated", #data.changes))
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
