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
local StaminaService

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

--========================================
-- Internal State
--========================================
local playerStats = {}  -- [userId] = { level, currentXP, totalXP, techPointsSpent, statPoints = { StatId -> Level } }
local totalXPTable = {} -- [level] = totalXPRequired (Pre-calculated lookup table)

-- Level up callback (Phase 8)
local levelUpCallback = nil

--========================================
-- Internal: XP/Level Calculations
--========================================

--- 레벨에 필요한 총 XP 계산 (Lookup Table 사용으로 O(1) 최적화)
local function _getTotalXPForLevel(level: number): number
	if level <= 1 then return 0 end
	if level > Balance.PLAYER_MAX_LEVEL then
		return totalXPTable[Balance.PLAYER_MAX_LEVEL] or math.huge
	end
	return totalXPTable[level] or 0
end

--- XP로부터 레벨 계산
local function _calculateLevelFromXP(totalXP: number): number
	-- 역순으로 순회하거나 이진 탐색 가능 (최대 레벨이 작으므로 역순 순회로도 충분히 빠름)
	for level = Balance.PLAYER_MAX_LEVEL, 1, -1 do
		if totalXP >= _getTotalXPForLevel(level) then
			return level
		end
	end
	return 1
end

--- 다음 레벨까지 필요한 XP (순수 해당 레벨 구간)
local function _getXPForNextLevel(currentLevel: number): number
	if currentLevel >= Balance.PLAYER_MAX_LEVEL then return 0 end
	return math.floor(Balance.BASE_XP_PER_LEVEL * (Balance.XP_SCALING ^ (currentLevel - 1)))
end

--- 현재 레벨에서의 진행 XP
local function _getCurrentLevelXP(totalXP: number, currentLevel: number): number
	local xpAtStartOfLevel = _getTotalXPForLevel(currentLevel)
	return math.max(0, totalXP - xpAtStartOfLevel)
end

--========================================
-- Internal: XP/Level Calculations (Helper)
--========================================
local function _getTotalEarnedPoints(level: number, perLevel: number): number
	return math.max(0, (level - 1) * perLevel)
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
		-- 투자된 스탯 포인트 (포인트 수치)
		statInvested = savedStats and savedStats.statInvested or {
			[Enums.StatId.MAX_HEALTH] = 0,
			[Enums.StatId.MAX_STAMINA] = 0,
			[Enums.StatId.WEIGHT] = 0,
			[Enums.StatId.WORK_SPEED] = 0,
			[Enums.StatId.ATTACK] = 0,
		}
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
			state.stats.statInvested = stats.statInvested
			return state
		end)
	end
end

--========================================
-- XP Addition (Updated with logging)
--========================================
function PlayerStatService.addXP(userId: number, amount: number, source: string?): (boolean, number)
	_initPlayerStats(userId)
	
	local stats = playerStats[userId]
	local oldLevel = stats.level
	
	if oldLevel >= Balance.PLAYER_MAX_LEVEL then
		return false, oldLevel
	end
	
	stats.totalXP = stats.totalXP + amount
	stats.currentXP = stats.currentXP + amount
	
	local newLevel = _calculateLevelFromXP(stats.totalXP)
	local leveledUp = newLevel > oldLevel
	
	if leveledUp then
		stats.level = newLevel
		stats.currentXP = _getCurrentLevelXP(stats.totalXP, newLevel)
		
		local techPointsGained = (newLevel - oldLevel) * Balance.TECH_POINTS_PER_LEVEL
		local statPointsGained = (newLevel - oldLevel) * Balance.STAT_POINTS_PER_LEVEL
		
		print(string.format("[PlayerStatService] Player %d leveled up: %d → %d (gained %d TP, %d SP)", 
			userId, oldLevel, newLevel, techPointsGained, statPointsGained))
		
		if levelUpCallback then
			levelUpCallback(userId, newLevel)
		end
		
		-- 레벨업 시 스탯 재적용 (최대치 상승 등)
		PlayerStatService.applyStats(userId)
	end
	
	_savePlayerStats(userId)
	
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player and NetController then
		local currentInLevel = _getCurrentLevelXP(stats.totalXP, stats.level)
		local requiredXP = _getXPForNextLevel(stats.level)
		NetController.FireClient(player, "Player.Stats.Changed", {
			level = stats.level,
			currentXP = currentInLevel,
			requiredXP = requiredXP,
			totalXP = stats.totalXP,
			leveledUp = leveledUp,
			source = source,
			statPointsAvailable = PlayerStatService.getStatPoints(userId),
			techPointsAvailable = PlayerStatService.getTechPoints(userId),
		})
	end
	
	return leveledUp, stats.level
end

--========================================
-- Public API: Tech & Stat Points
--========================================

function PlayerStatService.getTechPoints(userId: number): number
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	local totalEarned = _getTotalEarnedPoints(stats.level, Balance.TECH_POINTS_PER_LEVEL)
	return math.max(0, totalEarned - stats.techPointsSpent)
end

function PlayerStatService.getStatPoints(userId: number): number
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	local totalEarned = _getTotalEarnedPoints(stats.level, Balance.STAT_POINTS_PER_LEVEL)
	
	local spent = 0
	for _, value in pairs(stats.statInvested) do
		spent = spent + value
	end
	
	return math.max(0, totalEarned - spent)
end

--- 스탯 업그레이드
function PlayerStatService.upgradeStat(userId: number, statId: string): (boolean, string?)
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	
	if not Enums.StatId[statId] then
		return false, Enums.ErrorCode.BAD_REQUEST
	end
	
	local available = PlayerStatService.getStatPoints(userId)
	if available < 1 then
		return false, Enums.ErrorCode.INSUFFICIENT_STAT_POINTS
	end
	
	stats.statInvested[statId] = (stats.statInvested[statId] or 0) + 1
	_savePlayerStats(userId)
	
	-- 실제 캐릭터에 스탯 보너스 적용
	PlayerStatService.applyStats(userId)
	
	-- 업그레이드 성공 알림
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player and NetController then
		-- 1. 개별 업그레이드 이벤트 (이전 버전 호환용)
		NetController.FireClient(player, "Player.Stats.Upgraded", {
			statId = statId,
			newValue = stats.statInvested[statId],
			pointsRemaining = PlayerStatService.getStatPoints(userId)
		})
		
		-- 2. 전체 스탯 변경 이벤트 (클라이언트 상태 동기화용)
		local fullStats = PlayerStatService.getStats(userId)
		NetController.FireClient(player, "Player.Stats.Changed", fullStats)
	end
	
	return true
end

--========================================
-- Public API: Final Calculated Stats
--========================================

--- 플레이어의 실제 계산된 스탯 수치 조회
function PlayerStatService.GetCalculatedStats(userId: number)
	_initPlayerStats(userId)
	local stats = playerStats[userId].statInvested
	
	return {
		maxHealth = 100 + (stats[Enums.StatId.MAX_HEALTH] * Balance.HP_PER_POINT),
		maxStamina = 100 + (stats[Enums.StatId.MAX_STAMINA] * Balance.STAMINA_PER_POINT),
		maxWeight = 300 + (stats[Enums.StatId.WEIGHT] * Balance.WEIGHT_PER_POINT),
		workSpeed = 100 + (stats[Enums.StatId.WORK_SPEED] * Balance.WORKSPEED_PER_POINT),
		attackMult = 1.0 + (stats[Enums.StatId.ATTACK] * Balance.ATTACK_PER_POINT),
	}
end

--- 실제 캐릭터 인스턴스에 스탯 반영 (체력, 기력 등)
function PlayerStatService.applyStats(userId: number)
	_initPlayerStats(userId)
	local calc = PlayerStatService.GetCalculatedStats(userId)
	
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player then return end
	
	-- 1. 체력 적용
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			local oldMax = humanoid.MaxHealth
			humanoid.MaxHealth = calc.maxHealth
			-- 최대 체력이 늘어났을 때 현재 체력도 그만큼 비율로 채워주거나, 최소한 줄어들진 않게 함
			if calc.maxHealth > oldMax then
				humanoid.Health = humanoid.Health + (calc.maxHealth - oldMax)
			end
		end
	end
	
	-- 2. 기력(스태미나) 적용
	if StaminaService then
		StaminaService.setMaxStamina(userId, calc.maxStamina)
	end
	
	-- 3. 기타 속성 적용 (무게, 공격력 등은 관련 서비스에서 GetCalculatedStats 호출하여 참조)
	if character then
		character:SetAttribute("MaxWeight", calc.maxWeight)
		character:SetAttribute("AttackMult", calc.attackMult)
		character:SetAttribute("WorkSpeed", calc.workSpeed)
	end
end

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
		statPointsAvailable = PlayerStatService.getStatPoints(userId),
		statInvested = stats.statInvested,
		calculated = PlayerStatService.GetCalculatedStats(userId),
	}
end

--========================================
-- Handlers
--========================================

--- 플레이어 레벨 조회
function PlayerStatService.getLevel(userId: number): number
	_initPlayerStats(userId)
	return playerStats[userId].level
end

--- 플레이어 XP 조회
function PlayerStatService.getXP(userId: number): (number, number)
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	local currentInLevel = _getCurrentLevelXP(stats.totalXP, stats.level)
	local required = _getXPForNextLevel(stats.level)
	return currentInLevel, required
end

--- 기술 포인트 소모
function PlayerStatService.spendTechPoints(userId: number, amount: number): boolean
	_initPlayerStats(userId)
	local available = PlayerStatService.getTechPoints(userId)
	if available < amount then return false end
	playerStats[userId].techPointsSpent = playerStats[userId].techPointsSpent + amount
	_savePlayerStats(userId)
	return true
end

--- 기술 포인트 환급
function PlayerStatService.refundTechPoints(userId: number, amount: number)
	_initPlayerStats(userId)
	local currentSpent = playerStats[userId].techPointsSpent or 0
	playerStats[userId].techPointsSpent = math.max(0, currentSpent - amount)
	_savePlayerStats(userId)
end

--========================================
-- Handlers
--========================================

local function handleGetStats(player: Player, payload: any)
	return { success = true, data = PlayerStatService.getStats(player.UserId) }
end

local function handleUpgradeStat(player: Player, payload: any)
	if not payload or not payload.statId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local ok, err = PlayerStatService.upgradeStat(player.UserId, payload.statId)
	return { success = ok, errorCode = err }
end

function PlayerStatService.GetHandlers()
	return {
		["Player.Stats.Request"] = handleGetStats,
		["Player.Stats.Upgrade.Request"] = handleUpgradeStat,
	}
end

function PlayerStatService.Init(netController, saveService, dataService, staminaService)
	if initialized then return end
	initialized = true
	
	NetController = netController
	SaveService = saveService
	DataService = dataService
	StaminaService = staminaService
	
	-- [PRE-CALCULATE] XP Lookup Table (O(N^2) 방지)
	local runningTotal = 0
	totalXPTable[1] = 0
	for l = 1, Balance.PLAYER_MAX_LEVEL - 1 do
		local xpNeededForThisLevel = math.floor(Balance.BASE_XP_PER_LEVEL * (Balance.XP_SCALING ^ (l - 1)))
		runningTotal = runningTotal + xpNeededForThisLevel
		totalXPTable[l + 1] = runningTotal
	end
	
	-- Player 접속 시 스탯 초기화
	game:GetService("Players").PlayerAdded:Connect(function(player)
		_initPlayerStats(player.UserId)
		player.CharacterAdded:Connect(function(character)
			task.wait(0.5) -- 로딩 대기
			PlayerStatService.applyStats(player.UserId)
		end)
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

--- 레벨업 콜백 설정 (Phase 8)
function PlayerStatService.SetLevelUpCallback(callback)
	levelUpCallback = callback
end

return PlayerStatService
