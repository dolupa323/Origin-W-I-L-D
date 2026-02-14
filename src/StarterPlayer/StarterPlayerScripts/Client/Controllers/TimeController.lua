-- TimeController.lua
-- 클라이언트 시간 컨트롤러
-- 서버 Time 이벤트 수신 및 로컬 상태 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local Client = StarterPlayerScripts:WaitForChild("Client")
local NetClient = require(Client.NetClient)

local TimeController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 시간 캐시
local timeCache = {
	gameTime = 0,
	phase = "DAY",
	serverTime = 0,
}

--========================================
-- Public API: Cache Access
--========================================

function TimeController.getTimeCache()
	return timeCache
end

function TimeController.getPhase(): string
	return timeCache.phase
end

function TimeController.getGameTime(): number
	return timeCache.gameTime
end

--========================================
-- Event Handlers
--========================================

local function onPhaseChanged(data)
	if not data then return end
	
	timeCache.phase = data.phase or timeCache.phase
	timeCache.gameTime = data.gameTime or timeCache.gameTime
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[TimeController] Phase changed: %s at %.1f", timeCache.phase, timeCache.gameTime))
end

local function onSyncChanged(data)
	if not data then return end
	
	timeCache.gameTime = data.gameTime or timeCache.gameTime
	timeCache.phase = data.phase or timeCache.phase
	timeCache.serverTime = data.serverTime or timeCache.serverTime
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[TimeController] Sync: gameTime=%.1f, phase=%s", timeCache.gameTime, timeCache.phase))
end

--========================================
-- Initialization
--========================================

function TimeController.Init()
	if initialized then
		warn("[TimeController] Already initialized")
		return
	end
	
	-- 이벤트 리스너 등록
	NetClient.On("Time.Phase.Changed", onPhaseChanged)
	NetClient.On("Time.Sync.Changed", onSyncChanged)
	
	initialized = true
	print("[TimeController] Initialized - listening for Time events")
end

return TimeController
