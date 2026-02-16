-- PlayerStatService.lua
-- 플레이어 성장 서비스 (Phase 6)
-- 경험치 획득, 레벨업, 기술 포인트 관리

local PlayerStatService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController
local SaveService
local DataService

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

--========================================
-- Internal State
--========================================
local playerStats = {}  -- [userId] = { level, currentXP, totalXP, techPointsSpent }

-- Level up callback (Phase 8)
local levelUpCallback = nil

--========================================
-- Internal: XP/Level Calculations
--========================================

--- 특정 레벨 달성에 필요한 총 XP 계산
--- @param level number 목표 레벨
--- @return number 필요한 총 XP
local function _getTotalXPForLevel(level: number): number
	if level <= 1 then return 0 end
	
	local totalXP = 0
	for lvl = 1, level - 1 do
		-- requiredXP(lvl) = BASE_XP × (XP_SCALING ^ (lvl - 1))
		local required = math.floor(Balance.BASE_XP_PER_LEVEL * (Balance.XP_SCALING ^ (lvl - 1)))
		totalXP = totalXP + required
	end
	return totalXP
end

--- 현재 레벨에서 다음 레벨까지 필요한 XP
--- @param level number 현재 레벨
--- @return number 필요 XP
local function _getXPForNextLevel(level: number): number
	if level >= Balance.PLAYER_MAX_LEVEL then return 0 end
	return math.floor(Balance.BASE_XP_PER_LEVEL * (Balance.XP_SCALING ^ (level - 1)))
end

--- 총 XP에서 레벨 계산
--- @param totalXP number 총 획득 XP
--- @return number 현재 레벨
local function _calculateLevelFromXP(totalXP: number): number
	local level = 1
	local accumulated = 0
	
	while level < Balance.PLAYER_MAX_LEVEL do
		local required = _getXPForNextLevel(level)
		if accumulated + required > totalXP then
			break
		end
		accumulated = accumulated + required
		level = level + 1
	end
	
	return level
end

--- 현재 레벨에서의 진행 XP 계산
--- @param totalXP number 총 XP
--- @param level number 현재 레벨
--- @return number 현재 레벨 내 XP
local function _getCurrentLevelXP(totalXP: number, level: number): number
	local baseXP = _getTotalXPForLevel(level)
	return totalXP - baseXP
end

--========================================
-- Internal: State Management
--========================================

--- 플레이어 스탯 초기화/로드
local function _initPlayerStats(userId: number)
	if playerStats[userId] then return end
	
	-- SaveService에서 로드
	local state = SaveService and SaveService.getPlayerState(userId)
	local savedStats = state and state.stats
	
	playerStats[userId] = {
		level = savedStats and savedStats.level or 1,
		currentXP = savedStats and savedStats.currentXP or 0,
		totalXP = savedStats and savedStats.totalXP or 0,
		techPointsSpent = savedStats and savedStats.techPointsSpent or 0,
	}
end

--- 플레이어 스탯 저장
local function _savePlayerStats(userId: number)
	local stats = playerStats[userId]
	if not stats then return end
	
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.stats = state.stats or {}
			state.stats.level = stats.level
			state.stats.currentXP = stats.currentXP
			state.stats.totalXP = stats.totalXP
			state.stats.techPointsSpent = stats.techPointsSpent
			return state
		end)
	end
end

--========================================
-- Public API: Level & XP
--========================================

--- 플레이어 레벨 조회
--- @param userId number
--- @return number level
function PlayerStatService.getLevel(userId: number): number
	_initPlayerStats(userId)
	return playerStats[userId].level
end

--- 플레이어 XP 조회
--- @param userId number
--- @return number currentLevelXP, number requiredXP
function PlayerStatService.getXP(userId: number): (number, number)
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	local currentInLevel = _getCurrentLevelXP(stats.totalXP, stats.level)
	local required = _getXPForNextLevel(stats.level)
	return currentInLevel, required
end

--- 경험치 추가 (레벨업 자동 처리)
--- @param userId number
--- @param amount number 추가할 XP
--- @param source string? XP 획득 원천 (Enums.XPSource)
--- @return boolean leveledUp, number newLevel
function PlayerStatService.addXP(userId: number, amount: number, source: string?): (boolean, number)
	_initPlayerStats(userId)
	
	local stats = playerStats[userId]
	local oldLevel = stats.level
	
	-- 최대 레벨이면 XP 추가 안 함
	if oldLevel >= Balance.PLAYER_MAX_LEVEL then
		return false, oldLevel
	end
	
	-- XP 추가
	stats.totalXP = stats.totalXP + amount
	stats.currentXP = stats.currentXP + amount
	
	-- 레벨업 체크
	local newLevel = _calculateLevelFromXP(stats.totalXP)
	local leveledUp = newLevel > oldLevel
	
	if leveledUp then
		stats.level = newLevel
		stats.currentXP = _getCurrentLevelXP(stats.totalXP, newLevel)
		
		-- 기술 포인트 지급 (레벨업당 TECH_POINTS_PER_LEVEL)
		local techPointsGained = (newLevel - oldLevel) * Balance.TECH_POINTS_PER_LEVEL
		
		-- 저장
		_savePlayerStats(userId)
		
		-- 이벤트 발행
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player and NetController then
			NetController.FireClient(player, "Player.Stats.Changed", {
				level = newLevel,
				currentXP = stats.currentXP,
				requiredXP = _getXPForNextLevel(newLevel),
				totalXP = stats.totalXP,
				techPointsAvailable = PlayerStatService.getTechPoints(userId),
				techPointsGained = techPointsGained,
				source = source,
			})
		end
		
		print(string.format("[PlayerStatService] Player %d leveled up: %d → %d (gained %d tech points)", 
			userId, oldLevel, newLevel, techPointsGained))
		
		-- Phase 8: 레벨업 콜백
		if levelUpCallback then
			levelUpCallback(userId, newLevel)
		end
	else
		-- 저장만 (이벤트 없이)
		_savePlayerStats(userId)
	end
	
	return leveledUp, stats.level
end

--========================================
-- Public API: Tech Points
--========================================

--- 사용 가능한 기술 포인트 조회
--- @param userId number
--- @return number available tech points
function PlayerStatService.getTechPoints(userId: number): number
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	
	-- 총 획득 포인트 = (level - 1) × TECH_POINTS_PER_LEVEL
	-- 시작 레벨 1은 포인트 0
	local totalEarned = (stats.level - 1) * Balance.TECH_POINTS_PER_LEVEL
	local available = totalEarned - stats.techPointsSpent
	
	return math.max(0, available)
end

--- 기술 포인트 소모 (TechService에서 호출)
--- @param userId number
--- @param amount number
--- @return boolean success
function PlayerStatService.spendTechPoints(userId: number, amount: number): boolean
	_initPlayerStats(userId)
	
	local available = PlayerStatService.getTechPoints(userId)
	if available < amount then
		return false
	end
	
	playerStats[userId].techPointsSpent = playerStats[userId].techPointsSpent + amount
	_savePlayerStats(userId)
	
	return true
end

--========================================
-- Public API: Stats Info
--========================================

--- 플레이어 스탯 전체 조회
--- @param userId number
--- @return table stats
function PlayerStatService.getStats(userId: number): { [string]: any }
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	
	local currentInLevel, required = PlayerStatService.getXP(userId)
	
	return {
		level = stats.level,
		currentXP = currentInLevel,
		requiredXP = required,
		totalXP = stats.totalXP,
		techPointsAvailable = PlayerStatService.getTechPoints(userId),
		techPointsSpent = stats.techPointsSpent,
		-- 제작 속도 보너스 (Phase 6 RecipeService 연동용)
		craftSpeedBonus = (stats.level - 1) * Balance.STAT_BONUS_PER_LEVEL,
	}
end

--========================================
-- Handlers
--========================================

local function handleGetStats(player: Player, payload: any)
	local userId = player.UserId
	local stats = PlayerStatService.getStats(userId)
	
	return {
		success = true,
		data = stats,
	}
end

--========================================
-- Lifecycle
--========================================

function PlayerStatService.Init(netController, saveService, dataService)
	if initialized then return end
	initialized = true
	
	NetController = netController
	SaveService = saveService
	DataService = dataService
	
	-- Player 접속 시 스탯 초기화
	game:GetService("Players").PlayerAdded:Connect(function(player)
		_initPlayerStats(player.UserId)
	end)
	
	-- Player 퇴장 시 정리
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		_savePlayerStats(player.UserId)
		playerStats[player.UserId] = nil
	end)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		_initPlayerStats(player.UserId)
	end
	
	print("[PlayerStatService] Initialized")
end

function PlayerStatService.GetHandlers()
	return {
		["Player.Stats.Request"] = handleGetStats,
	}
end

--- 레벨업 콜백 설정 (Phase 8)
function PlayerStatService.SetLevelUpCallback(callback)
	levelUpCallback = callback
end

return PlayerStatService
