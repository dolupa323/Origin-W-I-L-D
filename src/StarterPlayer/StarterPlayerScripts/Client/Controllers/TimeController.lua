-- TimeController.lua
-- 클라이언트 시간 컨트롤러
-- 서버 Time 이벤트 수신 및 로컬 상태 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local NetClient = require(script.Parent.Parent.NetClient)

local TimeController = {}

--========================================
-- Private State
--========================================
local initialized = false
local renderConn = nil
local lastSyncClientClock = 0
local lastSyncDayTime = 0
local hasSync = false

-- 로컬 시간 캐시
local timeCache = {
	dayTime = 0,
	phase = "DAY",
	serverTime = 0,
}

--========================================
-- Internal Helpers
--========================================

local function getDayLength(): number
	return math.max(1, Balance.DAY_LENGTH or 2400)
end

local function getDayDuration(): number
	return math.clamp(Balance.DAY_DURATION or 1800, 0, getDayLength())
end

local function phaseFromDayTime(dayTime: number): string
	if dayTime < getDayDuration() then
		return "DAY"
	end
	return "NIGHT"
end

local function applyLighting(dayTime: number)
	local dayLength = getDayLength()
	local dayDuration = getDayDuration()
	local nightDuration = math.max(1, dayLength - dayDuration)
	local t = (dayTime % dayLength)

	local clockTime
	if t < dayDuration then
		-- DAY 구간은 항상 06:00 ~ 18:00으로 매핑하여 시각과 서버 페이즈를 일치시킨다.
		local p = t / math.max(1, dayDuration)
		clockTime = 6 + (p * 12)
	else
		-- NIGHT 구간은 18:00 ~ 06:00으로 매핑 (자정 경유).
		local p = (t - dayDuration) / nightDuration
		clockTime = 18 + (p * 12)
		if clockTime >= 24 then
			clockTime -= 24
		end
	end

	Lighting.ClockTime = clockTime
end

--========================================
-- Public API: Cache Access
--========================================

function TimeController.getTimeCache()
	return timeCache
end

function TimeController.getPhase(): string
	return timeCache.phase
end

function TimeController.getDayTime(): number
	return timeCache.dayTime
end

--========================================
-- Event Handlers
--========================================

local function onPhaseChanged(data)
	if not data then return end
	
	timeCache.phase = data.phase or timeCache.phase
	timeCache.dayTime = data.dayTime or timeCache.dayTime
	timeCache.serverTime = data.serverTime or timeCache.serverTime

	if data.dayTime ~= nil then
		lastSyncDayTime = data.dayTime
		lastSyncClientClock = os.clock()
		hasSync = true
		applyLighting(lastSyncDayTime)
	end
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[TimeController] Phase changed: %s at dayTime=%.1f", timeCache.phase, timeCache.dayTime))
end

local function onSyncChanged(data)
	if not data then return end
	
	timeCache.dayTime = data.dayTime or timeCache.dayTime
	timeCache.phase = data.phase or timeCache.phase
	timeCache.serverTime = data.serverTime or timeCache.serverTime

	if data.dayTime ~= nil then
		lastSyncDayTime = data.dayTime
		lastSyncClientClock = os.clock()
		hasSync = true
		applyLighting(lastSyncDayTime)
	end
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[TimeController] Sync: dayTime=%.1f, phase=%s", timeCache.dayTime, timeCache.phase))
end

local function requestInitialSync()
	for _ = 1, 5 do
		local ok, data = NetClient.Request("Time.Sync.Request", {})
		if ok and type(data) == "table" then
			onSyncChanged(data)
			return true
		end
		task.wait(0.5)
	end

	warn("[TimeController] Initial time sync failed")
	return false
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

	-- 첫 진입 시 서버 시간 동기화
	task.spawn(requestInitialSync)

	-- 서버 시각을 기반으로 클라이언트에서 부드럽게 시각 연출 업데이트
	renderConn = RunService.RenderStepped:Connect(function()
		if not hasSync then
			applyLighting(timeCache.dayTime)
			return
		end

		local dayLength = getDayLength()
		local elapsed = os.clock() - lastSyncClientClock
		local predictedDayTime = (lastSyncDayTime + elapsed) % dayLength
		timeCache.dayTime = predictedDayTime
		timeCache.phase = phaseFromDayTime(predictedDayTime)
		applyLighting(predictedDayTime)
	end)
	
	initialized = true
	print("[TimeController] Initialized - listening for Time events")
end

return TimeController
