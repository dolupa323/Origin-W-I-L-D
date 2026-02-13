-- TimeService.lua
-- 서버 권위 시간 서비스 (SSOT)
-- 하루 = 2400초 (40분), 낮 = 1800초, 밤 = 600초

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local TimeService = {}

--========================================
-- Private State
--========================================
local serverStartTime: number = 0
local timeOffset: number = 0  -- Warp 오프셋 (디버그용)
local currentPhase: string = Enums.TimePhase.DAY
local initialized: boolean = false
local phaseChangeCount: number = 0  -- 디버그용 카운터

-- NetController 참조 (초기화 시 설정)
local NetController = nil

--========================================
-- Internal Functions
--========================================

--- 현재 서버 시간 계산 (오프셋 포함)
local function _getElapsed(): number
	return (os.clock() - serverStartTime) + timeOffset
end

--- 하루 내 시간 계산 (0 ~ DAY_LENGTH)
local function _getDayTime(): number
	local elapsed = _getElapsed()
	return elapsed % Balance.DAY_LENGTH
end

--- 페이즈 계산 (DAY or NIGHT)
local function _computePhase(): string
	local dayTime = _getDayTime()
	if dayTime < Balance.DAY_DURATION then
		return Enums.TimePhase.DAY
	else
		return Enums.TimePhase.NIGHT
	end
end

--- 페이즈 변경 이벤트 발생
local function _emitPhaseChanged(newPhase: string)
	phaseChangeCount += 1
	
	if NetController then
		NetController.FireAllClients("Time.Phase.Changed", {
			phase = newPhase,
			dayTime = _getDayTime(),
			serverTime = _getElapsed(),
		})
	end
	print(string.format("[TimeService] Phase changed: %s (count: %d)", newPhase, phaseChangeCount))
end

--- 시간 동기 이벤트 발생 (특정 플레이어 또는 전체)
local function _emitSyncChanged(player: Player?)
	local data = {
		serverTime = _getElapsed(),
		dayTime = _getDayTime(),
		phase = currentPhase,
	}
	
	if NetController then
		if player then
			NetController.FireClient(player, "Time.Sync.Changed", data)
		else
			NetController.FireAllClients("Time.Sync.Changed", data)
		end
	end
end

--- Heartbeat 업데이트 (페이즈 변경 감지)
local function _update(dt: number)
	local newPhase = _computePhase()
	
	if newPhase ~= currentPhase then
		currentPhase = newPhase
		_emitPhaseChanged(newPhase)
	end
end

--========================================
-- Public API
--========================================

--- 현재 시간 정보 반환
--- @return table { serverTime, dayTime, phase }
function TimeService.getTime(): { serverTime: number, dayTime: number, phase: string }
	return {
		serverTime = _getElapsed(),
		dayTime = _getDayTime(),
		phase = currentPhase,
	}
end

--- 현재 페이즈 반환
--- @return string Enums.TimePhase
function TimeService.getPhase(): string
	return currentPhase
end

--- 특정 플레이어 또는 전체에게 시간 동기
--- @param player Player? nil이면 전체 브로드캐스트
function TimeService.sync(player: Player?)
	_emitSyncChanged(player)
end

--- 디버그: 페이즈 변경 횟수 반환
function TimeService.getPhaseChangeCount(): number
	return phaseChangeCount
end

--- 디버그: 페이즈 변경 횟수 리셋
function TimeService.resetPhaseChangeCount()
	phaseChangeCount = 0
end

--========================================
-- Debug Commands
--========================================

--- 워프 후 페이즈 즉시 업데이트 (내부용)
local function _forcePhaseUpdate()
	local newPhase = _computePhase()
	if newPhase ~= currentPhase then
		currentPhase = newPhase
		_emitPhaseChanged(newPhase)
	end
end

--- 시간 워프 (디버그용)
--- @param seconds number 워프할 초
function TimeService.warp(seconds: number)
	timeOffset += seconds
	_forcePhaseUpdate()  -- 즉시 페이즈 갱신
	print(string.format("[TimeService] Warped %d seconds. New dayTime: %.1f, Phase: %s", 
		seconds, _getDayTime(), currentPhase))
end

--- 특정 페이즈로 워프 (디버그용)
--- @param targetPhase string "DAY" or "NIGHT"
function TimeService.warpToPhase(targetPhase: string)
	local dayTime = _getDayTime()
	
	if targetPhase == Enums.TimePhase.DAY then
		-- 낮으로 이동: dayTime을 0으로
		local toDay = Balance.DAY_LENGTH - dayTime
		timeOffset += toDay
	elseif targetPhase == Enums.TimePhase.NIGHT then
		-- 밤으로 이동: dayTime을 DAY_DURATION으로
		local toNight = Balance.DAY_DURATION - dayTime
		if toNight <= 0 then
			toNight += Balance.DAY_LENGTH
		end
		timeOffset += toNight
	end
	
	_forcePhaseUpdate()  -- 즉시 페이즈 갱신
	print(string.format("[TimeService] Warped to %s. DayTime: %.1f", currentPhase, _getDayTime()))
end

--========================================
-- Network Handlers
--========================================

--- Time.Sync.Request 핸들러
local function handleSyncRequest(player: Player, payload: any)
	return TimeService.getTime()
end

--- Time.Warp 핸들러 (디버그용)
local function handleWarp(player: Player, payload: any)
	local seconds = payload.seconds or 0
	TimeService.warp(seconds)
	return TimeService.getTime()
end

--- Time.WarpToPhase 핸들러 (디버그용)
local function handleWarpToPhase(player: Player, payload: any)
	local targetPhase = payload.phase
	if targetPhase then
		TimeService.warpToPhase(targetPhase)
	end
	return TimeService.getTime()
end

--- Time.Debug 핸들러 (디버그 정보)
local function handleDebug(player: Player, payload: any)
	return {
		phaseChangeCount = phaseChangeCount,
		currentPhase = currentPhase,
		dayTime = _getDayTime(),
		serverTime = _getElapsed(),
		timeOffset = timeOffset,
	}
end

--========================================
-- Initialization
--========================================

--- 서비스 초기화
--- @param netController table NetController 참조
function TimeService.Init(netController: any)
	if initialized then
		warn("[TimeService] Already initialized")
		return
	end
	
	-- NetController 참조 저장
	NetController = netController
	
	-- 서버 시작 시간 기록
	serverStartTime = os.clock()
	timeOffset = 0
	phaseChangeCount = 0
	
	-- 초기 페이즈 계산
	currentPhase = _computePhase()
	
	-- Heartbeat 연결 (페이즈 변경 감지)
	RunService.Heartbeat:Connect(_update)
	
	initialized = true
	print(string.format("[TimeService] Initialized - Phase: %s, DayLength: %d, DayDuration: %d, NightDuration: %d",
		currentPhase, Balance.DAY_LENGTH, Balance.DAY_DURATION, Balance.NIGHT_DURATION))
end

--- 네트워크 핸들러 반환 (외부 등록용)
function TimeService.GetHandlers()
	return {
		["Time.Sync.Request"] = handleSyncRequest,
		["Time.Warp"] = handleWarp,
		["Time.WarpToPhase"] = handleWarpToPhase,
		["Time.Debug"] = handleDebug,
	}
end

return TimeService
