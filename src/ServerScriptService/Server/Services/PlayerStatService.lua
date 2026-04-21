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
local DataHelper = require(Shared.Util.DataHelper)

--========================================
-- Internal State
--========================================
local playerStats = {}  -- [userId] = { level, currentXP, totalXP, techPointsSpent, statPoints = { StatId -> Level } }
local totalXPTable = {} -- [level] = totalXPRequired (Pre-calculated lookup table)
local recentActionXP = {} -- [userId] = { [bucketKey] = { count, lastAt } }

-- Level up callback (Phase 8)
local levelUpCallback = nil
local INIT_STATE_WAIT_TIMEOUT = 45
local INIT_STATE_WAIT_INTERVAL = 0.1

local function _waitForPlayerState(userId: number)
	if not SaveService or not SaveService.getPlayerState then
		return nil
	end

	local state = SaveService.getPlayerState(userId)
	local deadline = os.clock() + INIT_STATE_WAIT_TIMEOUT
	while not state and os.clock() < deadline do
		task.wait(INIT_STATE_WAIT_INTERVAL)
		state = SaveService.getPlayerState(userId)
	end

	return state
end

local function _normalizeStatInvested(raw: any): {[string]: number}
	local normalized = {
		[Enums.StatId.MAX_HEALTH] = 0,
		[Enums.StatId.MAX_STAMINA] = 0,
		[Enums.StatId.INV_SLOTS] = 0,
		[Enums.StatId.WORK_SPEED] = 0,
		[Enums.StatId.ATTACK] = 0,
		[Enums.StatId.DEFENSE] = 0,
	}

	if type(raw) == "table" then
		for statId, value in pairs(raw) do
			if Enums.StatId[statId] then
				normalized[statId] = math.max(0, math.floor(tonumber(value) or 0))
			end
		end
	end

	-- 레거시 마이그레이션: 기존 WEIGHT 스탯을 INV_SLOTS로 변환
	if type(raw) == "table" and raw["WEIGHT"] and raw["WEIGHT"] > 0 then
		normalized[Enums.StatId.INV_SLOTS] = (normalized[Enums.StatId.INV_SLOTS] or 0) + raw["WEIGHT"]
	end

	return normalized
end

local function _hydrateStatsFromSave(userId: number, state: any): boolean
	if not state or type(state.stats) ~= "table" then
		return false
	end

	local savedStats = state.stats
	local target = playerStats[userId]
	if not target then
		return false
	end

	target.level = savedStats.level or target.level or 1
	target.currentXP = savedStats.currentXP or target.currentXP or 0
	target.totalXP = savedStats.totalXP or target.totalXP or 0
	target.techPointsSpent = savedStats.techPointsSpent or target.techPointsSpent or 0
	target.statInvested = _normalizeStatInvested(savedStats.statInvested)
	target._hydratedFromSave = true
	return true
end

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
	if playerStats[userId] then
		-- SaveService 지연 로딩으로 기본값이 먼저 들어온 경우를 보정
		if not playerStats[userId]._hydratedFromSave and SaveService and SaveService.getPlayerState then
			local state = SaveService.getPlayerState(userId)
			if state then
				_hydrateStatsFromSave(userId, state)
			end
		end
		return
	end
	
	-- SaveService에서 로드
	local state = _waitForPlayerState(userId)
	local savedStats = state and state.stats
	
	playerStats[userId] = {
		level = savedStats and savedStats.level or 1,
		currentXP = savedStats and savedStats.currentXP or 0,
		totalXP = savedStats and savedStats.totalXP or 0,
		techPointsSpent = savedStats and savedStats.techPointsSpent or 0,
		-- 투자된 스탯 포인트 (포인트 수치)
		statInvested = _normalizeStatInvested(savedStats and savedStats.statInvested),
		_hydratedFromSave = savedStats ~= nil,
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

local function _cleanupRecentActionXP(userId: number, nowTime: number)
	local byUser = recentActionXP[userId]
	if not byUser then
		return
	end

	local expireAfter = (Balance.XP_REPEAT_WINDOW or 120) * 2
	for bucketKey, entry in pairs(byUser) do
		if not entry or (nowTime - (entry.lastAt or 0)) > expireAfter then
			byUser[bucketKey] = nil
		end
	end

	if next(byUser) == nil then
		recentActionXP[userId] = nil
	end
end

local function _getActionXPMultiplier(userId: number, bucketKey: string?): number
	if not bucketKey or bucketKey == "" then
		return 1
	end

	local nowTime = os.clock()
	local repeatWindow = Balance.XP_REPEAT_WINDOW or 120
	local repeatStep = Balance.XP_REPEAT_STEP or 0.12
	local repeatMinMult = Balance.XP_REPEAT_MIN_MULT or 0.25

	_cleanupRecentActionXP(userId, nowTime)
	local byUser = recentActionXP[userId]
	if not byUser then
		byUser = {}
		recentActionXP[userId] = byUser
	end

	local entry = byUser[bucketKey]
	if entry and (nowTime - (entry.lastAt or 0)) <= repeatWindow then
		entry.count = (entry.count or 1) + 1
		entry.lastAt = nowTime
	else
		entry = {
			count = 1,
			lastAt = nowTime,
		}
		byUser[bucketKey] = entry
	end

	return math.clamp(1 - ((entry.count - 1) * repeatStep), repeatMinMult, 1)
end

--========================================
-- XP Addition
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
		
		print(string.format("[PlayerStatService] Player %d leveled up: %d \226\134\146 %d (gained %d TP, %d SP)", 
			userId, oldLevel, newLevel, techPointsGained, statPointsGained))
		
		if levelUpCallback then
			for reachedLevel = oldLevel + 1, newLevel do
				levelUpCallback(userId, reachedLevel, oldLevel, newLevel)
			end
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

function PlayerStatService.grantActionXP(userId: number, baseAmount: number, payload: any?): (boolean, number, number)
	if typeof(baseAmount) ~= "number" or baseAmount <= 0 then
		return false, PlayerStatService.getLevel(userId), 0
	end

	local source = nil
	local actionKey = nil
	local disableDiminishing = false
	if type(payload) == "table" then
		source = payload.source
		actionKey = payload.actionKey
		disableDiminishing = payload.disableDiminishing == true
	else
		source = payload
	end

	local bucketKey = nil
	if source and actionKey then
		bucketKey = tostring(source) .. "::" .. tostring(actionKey)
	elseif actionKey then
		bucketKey = tostring(actionKey)
	elseif source then
		bucketKey = tostring(source)
	end

	local multiplier = disableDiminishing and 1 or _getActionXPMultiplier(userId, bucketKey)
	local finalAmount = math.max(1, math.floor(baseAmount * multiplier + 0.0001))
	local leveledUp, level = PlayerStatService.addXP(userId, finalAmount, source)
	return leveledUp, level, finalAmount
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
	
	-- 인벤토리 칸 스탯: 120칸 상한 검사
	if statId == Enums.StatId.INV_SLOTS then
		local currentInvested = stats.statInvested[Enums.StatId.INV_SLOTS] or 0
		local currentSlots = Balance.BASE_INV_SLOTS + (currentInvested * Balance.SLOTS_PER_POINT)
		if currentSlots >= Balance.MAX_INV_SLOTS then
			return false, "MAX_SLOTS_REACHED"
		end
	end

	-- 작업 속도 스탯: 상한 검사 (평균 50포인트)
	if statId == Enums.StatId.WORK_SPEED then
		local currentInvested = stats.statInvested[Enums.StatId.WORK_SPEED] or 0
		if currentInvested >= (Balance.MAX_WORKSPEED_POINTS or 50) then
			return false, "MAX_WORKSPEED_REACHED"
		end
	end
	
	stats.statInvested[statId] = (stats.statInvested[statId] or 0) + 1
	_savePlayerStats(userId)
	
	-- 실제 캐릭터에 스탯 보너스 적용
	PlayerStatService.applyStats(userId)
	
	-- 업그레이드 성공 알림 (Changed 이벤트에 통합)
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player and NetController then
		local fullStats = PlayerStatService.getStats(userId)
		fullStats.upgradedStat = statId
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
	
	local defense = 0
	local setBonuses = nil
	-- 순환 참조 방지 위해 지연 로딩 (InventoryService)
	local success, InventoryService = pcall(function() 
		return require(game:GetService("ServerScriptService").Server.Services.InventoryService) 
	end)
	if success and InventoryService then
		if InventoryService.getTotalDefense then
			defense = InventoryService.getTotalDefense(userId)
		end
		if InventoryService.getArmorSetBonuses then
			setBonuses = InventoryService.getArmorSetBonuses(userId)
		end
	end
	
	local finalHp = 100 + ((stats[Enums.StatId.MAX_HEALTH] or 0) * Balance.HP_PER_POINT)
	local finalSta = 100 + ((stats[Enums.StatId.MAX_STAMINA] or 0) * Balance.STAMINA_PER_POINT)
	local finalAtk = 1.0 + ((stats[Enums.StatId.ATTACK] or 0) * Balance.ATTACK_PER_POINT)
	
	if setBonuses then
		if setBonuses.maxHealth then finalHp = finalHp + setBonuses.maxHealth end
		if setBonuses.maxStamina then finalSta = finalSta + setBonuses.maxStamina end
		if setBonuses.attackMult then finalAtk = finalAtk + setBonuses.attackMult end
	end
	
	local finalWork = 100 + ((stats[Enums.StatId.WORK_SPEED] or 0) * Balance.WORKSPEED_PER_POINT)

	-- 이동 속도 보너스 (방어구 세트 등)
	local speedMult = 0
	if setBonuses and setBonuses.speedMult then
		speedMult = speedMult + setBonuses.speedMult
	end
	
	return {
		maxHealth = finalHp,
		maxStamina = finalSta,
		maxSlots = math.min(
			Balance.MAX_INV_SLOTS,
			Balance.BASE_INV_SLOTS + ((stats[Enums.StatId.INV_SLOTS] or 0) * Balance.SLOTS_PER_POINT)
		),
		workSpeed = finalWork,
		attackMult = finalAtk,
		defense = defense,
		speedMult = speedMult, -- StaminaService 안티치트에서 참조
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
			
			-- [Defense] 로블록스 엔진이 간혹 스폰 직후 MaxHealth를 100으로 리셋하는 경우를 대비해 한 번 더 적용
			task.delay(0.1, function()
				if humanoid and humanoid.Parent then
					humanoid.MaxHealth = calc.maxHealth
				end
			end)
			
			print(string.format("[PlayerStatService] Applied stats to %s: MaxHealth=%.1f (was %.1f), MaxStamina=%.1f", 
				player.Name, calc.maxHealth, oldMax, calc.maxStamina))
		end
	end
	
	-- 2. 스태미나 적용 (StaminaService 연동)
	if StaminaService then
		StaminaService.setMaxStamina(userId, calc.maxStamina)
	end
	
	-- 3. 기타 속성 적용 (인벤토리 칸, 공격력 등은 관련 서비스에서 GetCalculatedStats 호출하여 참조)
	if character then
		character:SetAttribute("MaxSlots", calc.maxSlots)
		character:SetAttribute("AttackMult", calc.attackMult)
		character:SetAttribute("WorkSpeed", calc.workSpeed)
		character:SetAttribute("Defense", calc.defense)
	end
	
	-- 4. 클라이언트에 최종 스탯 전송
	if NetController then
		local fullStats = PlayerStatService.getStats(userId)
		NetController.FireClient(player, "Player.Stats.Changed", fullStats)
	end
end

--- 스탯 재계산 (에일리어스)
function PlayerStatService.recalculateStats(userId: number)
	PlayerStatService.applyStats(userId)
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
-- Public API: Reset All Stats
--========================================

--- 모든 투자 스탯을 초기화하고 포인트 환급
function PlayerStatService.resetAllStats(userId: number): (boolean, number)
	_initPlayerStats(userId)
	local stats = playerStats[userId]
	if not stats then return false, 0 end
	
	local totalRefunded = 0
	for statId, invested in pairs(stats.statInvested) do
		totalRefunded = totalRefunded + (invested or 0)
		stats.statInvested[statId] = 0
	end
	
	if totalRefunded <= 0 then return false, 0 end
	
	_savePlayerStats(userId)
	PlayerStatService.applyStats(userId)
	
	return true, totalRefunded
end

--========================================
-- Handlers for Networking
--========================================

local function handleGetStats(player: Player, payload: any)
	return { success = true, data = PlayerStatService.getStats(player.UserId) }
end

local function handleUpgradeStat(player: Player, payload: any)
	if not payload then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	-- Bulk upgrade support (multiple stats)
	if payload.stats and type(payload.stats) == "table" then
		local anySuccess = false
		for statId, count in pairs(payload.stats) do
			for i = 1, count do
				local ok = PlayerStatService.upgradeStat(player.UserId, statId)
				if ok then anySuccess = true end
			end
		end
		return { success = anySuccess }
	end
	
	-- Single upgrade support (compatibility)
	if payload.statId then
		local ok, err = PlayerStatService.upgradeStat(player.UserId, payload.statId)
		return { success = ok, errorCode = err }
	end
	
	return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
end

local function handleResetStats(player: Player, payload: any)
	local userId = player.UserId
	
	local oldCalc = PlayerStatService.GetCalculatedStats(userId)
	local oldMaxSlots = oldCalc.maxSlots or Balance.BASE_INV_SLOTS
	
	local ok, refunded = PlayerStatService.resetAllStats(userId)
	if not ok then
		return { success = false, errorCode = "NOTHING_TO_RESET" }
	end
	
	local newMaxSlots = Balance.BASE_INV_SLOTS
	
	local droppedItems = {}
	if newMaxSlots < oldMaxSlots then
		local invOk, InventoryService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.InventoryService)
		end)
		if invOk and InventoryService and InventoryService.dropExcessItems then
			droppedItems = InventoryService.dropExcessItems(player, newMaxSlots)
		end
	end
	
	return { success = true, data = { refunded = refunded, droppedCount = #droppedItems } }
end

function PlayerStatService.GetHandlers()
	return {
		["Player.Stats.Request"] = handleGetStats,
		["Player.Stats.Upgrade.Request"] = handleUpgradeStat,
		["Player.Stats.Reset.Request"] = handleResetStats,
	}
end

function PlayerStatService.Init(netController, saveService, dataService, staminaService)
	if initialized then return end
	initialized = true
	
	NetController = netController
	SaveService = saveService
	DataService = dataService
	StaminaService = staminaService
	
	-- [PRE-CALCULATE] XP Lookup Table
	local runningTotal = 0
	totalXPTable[1] = 0
	for l = 1, Balance.PLAYER_MAX_LEVEL - 1 do
		local xpNeededForThisLevel = math.floor(Balance.BASE_XP_PER_LEVEL * (Balance.XP_SCALING ^ (l - 1)))
		runningTotal = runningTotal + xpNeededForThisLevel
		totalXPTable[l+1] = runningTotal
	end
	
	-- Player 접속 시 스탯 초기화 및 리스너 연결
	local function onPlayerAdded(player)
		_initPlayerStats(player.UserId)
		
		task.spawn(function()
			-- SaveService 로딩 대기 루프
			local deadline = os.clock() + INIT_STATE_WAIT_TIMEOUT
			while player.Parent and os.clock() < deadline do
				local state = SaveService and SaveService.getPlayerState and SaveService.getPlayerState(player.UserId)
				if state and state.stats then
					local stats = playerStats[player.UserId]
					if stats and not stats._hydratedFromSave then
						_hydrateStatsFromSave(player.UserId, state)
						PlayerStatService.applyStats(player.UserId)
					end
					break
				end
				task.wait(0.5)
			end
		end)

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				PlayerStatService.applyStats(player.UserId)
			end
		end)
		
		-- 초기 접속 시 캐릭터가 이미 있으면 즉시 적용
		if player.Character then
			PlayerStatService.applyStats(player.UserId)
		end
	end

	game:GetService("Players").PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Player 퇴장 시 정리
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		_savePlayerStats(player.UserId)
		playerStats[player.UserId] = nil
		recentActionXP[player.UserId] = nil
	end)

	print("[PlayerStatService] Initialized (with CharacterAdded fix)")
end

function PlayerStatService.SetLevelUpCallback(callback)
	levelUpCallback = callback
end

return PlayerStatService
