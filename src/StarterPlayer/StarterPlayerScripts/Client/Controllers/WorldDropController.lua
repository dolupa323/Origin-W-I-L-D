-- WorldDropController.lua
-- 클라이언트 월드 드롭 컨트롤러
-- 서버 WorldDrop 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local Client = StarterPlayerScripts:WaitForChild("Client")
local NetClient = require(Client.NetClient)

local WorldDropController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 드롭 캐시 [dropId] = { dropId, pos, itemId, count, despawnAt, inactive }
local dropsCache = {}
local dropCount = 0

--========================================
-- Public API: Cache Access
--========================================

function WorldDropController.getDropsCache()
	return dropsCache
end

function WorldDropController.getDrop(dropId: string)
	return dropsCache[dropId]
end

function WorldDropController.getDropCount(): number
	return dropCount
end

--========================================
-- Event Handlers
--========================================

local function onSpawned(data)
	if not data or not data.dropId then return end
	
	dropsCache[data.dropId] = {
		dropId = data.dropId,
		pos = data.pos,
		itemId = data.itemId,
		count = data.count,
		despawnAt = data.despawnAt,
		inactive = data.inactive,
	}
	dropCount = dropCount + 1
	
	-- 디버그 로그 (Studio에서만)
	-- print(string.format("[WorldDropController] Spawned: %s (%s x%d)", data.dropId, data.itemId, data.count))
end

local function onChanged(data)
	if not data or not data.dropId then return end
	
	local drop = dropsCache[data.dropId]
	if drop then
		drop.count = data.count
		-- print(string.format("[WorldDropController] Changed: %s -> %d", data.dropId, data.count))
	end
end

local function onDespawned(data)
	if not data or not data.dropId then return end
	
	if dropsCache[data.dropId] then
		dropsCache[data.dropId] = nil
		dropCount = dropCount - 1
		-- print(string.format("[WorldDropController] Despawned: %s (%s)", data.dropId, data.reason))
	end
end

--========================================
-- Initialization
--========================================

function WorldDropController.Init()
	if initialized then
		warn("[WorldDropController] Already initialized")
		return
	end
	
	-- 이벤트 리스너 등록
	NetClient.On("WorldDrop.Spawned", onSpawned)
	NetClient.On("WorldDrop.Changed", onChanged)
	NetClient.On("WorldDrop.Despawned", onDespawned)
	
	initialized = true
	print("[WorldDropController] Initialized - listening for WorldDrop events")
end

return WorldDropController
