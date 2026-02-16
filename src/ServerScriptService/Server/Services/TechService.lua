-- TechService.lua
-- 기술 해금 서비스 (Phase 6)
-- 기술 트리 관리, 해금 처리, 레시피 잠금 연동

local TechService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController
local DataService
local PlayerStatService
local SaveService

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

--========================================
-- Internal State
--========================================
local techDataMap = {}   -- [techId] = techData (Init에서 로드)
local playerUnlocks = {} -- [userId] = { [techId] = true }

-- Tech unlock callback (Phase 8)
local unlockCallback = nil

--========================================
-- Internal: Tech Tree
--========================================

--- 기술 데이터 로드 (DataService에서)
local function _loadTechData()
	local techData = DataService.get("TechUnlockData")
	if not techData then
		warn("[TechService] TechUnlockData not found!")
		return
	end
	
	-- DataService.get은 Map 형식 {id -> record}를 반환 (Validator.validateIdTable 적용 후)
	local count = 0
	for techId, tech in pairs(techData) do
		techDataMap[techId] = tech
		count = count + 1
	end
	
	print(string.format("[TechService] Loaded %d tech nodes", count))
end

--- 플레이어 해금 상태 초기화/로드
local function _initPlayerUnlocks(userId: number)
	if playerUnlocks[userId] then return end
	
	-- SaveService에서 로드
	local state = SaveService and SaveService.getPlayerState(userId)
	local savedUnlocks = state and state.unlockedTech
	
	playerUnlocks[userId] = savedUnlocks or {}
	
	-- 기본 기술 자동 해금 (TECH_BASICS 등 cost=0인 것들)
	for techId, tech in pairs(techDataMap) do
		if tech.techPointCost == 0 and not playerUnlocks[userId][techId] then
			playerUnlocks[userId][techId] = true
		end
	end
end

--- 플레이어 해금 상태 저장
local function _savePlayerUnlocks(userId: number)
	local unlocks = playerUnlocks[userId]
	if not unlocks then return end
	
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.unlockedTech = unlocks
			return state
		end)
	end
end

--========================================
-- Internal: Validation
--========================================

--- 선행 기술 모두 해금 여부 확인
local function _checkPrerequisites(userId: number, techId: string): boolean
	local tech = techDataMap[techId]
	if not tech then return false end
	
	local unlocks = playerUnlocks[userId]
	if not unlocks then return false end
	
	for _, prereqId in ipairs(tech.prerequisites or {}) do
		if not unlocks[prereqId] then
			return false
		end
	end
	
	return true
end

--========================================
-- Public API: Tech Unlock
--========================================

--- 기술 해금
--- @param userId number
--- @param techId string
--- @return boolean success, string? errorCode
function TechService.unlock(userId: number, techId: string): (boolean, string?)
	_initPlayerUnlocks(userId)
	
	-- 기술 존재 확인
	local tech = techDataMap[techId]
	if not tech then
		return false, Enums.ErrorCode.TECH_NOT_FOUND
	end
	
	-- 이미 해금 확인
	if playerUnlocks[userId][techId] then
		return false, Enums.ErrorCode.TECH_ALREADY_UNLOCKED
	end
	
	-- 선행 기술 확인
	if not _checkPrerequisites(userId, techId) then
		return false, Enums.ErrorCode.PREREQUISITES_NOT_MET
	end
	
	-- 기술 포인트 확인 및 소모
	local cost = tech.techPointCost or 0
	if cost > 0 then
		local available = PlayerStatService.getTechPoints(userId)
		if available < cost then
			return false, Enums.ErrorCode.INSUFFICIENT_TECH_POINTS
		end
		
		-- 포인트 소모
		local spent = PlayerStatService.spendTechPoints(userId, cost)
		if not spent then
			return false, Enums.ErrorCode.INSUFFICIENT_TECH_POINTS
		end
	end
	
	-- 해금 처리
	playerUnlocks[userId][techId] = true
	_savePlayerUnlocks(userId)
	
	-- 이벤트 발행
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Tech.Unlocked", {
			techId = techId,
			name = tech.name,
			unlocks = tech.unlocks,
			techPointsRemaining = PlayerStatService.getTechPoints(userId),
		})
	end
	
	print(string.format("[TechService] Player %d unlocked tech: %s", userId, techId))
	
	-- Phase 8: 기술 해금 콜백
	if unlockCallback then
		unlockCallback(userId, techId)
	end
	
	return true
end

--- 기술 해금 여부 확인
--- @param userId number
--- @param techId string
--- @return boolean
function TechService.isUnlocked(userId: number, techId: string): boolean
	_initPlayerUnlocks(userId)
	return playerUnlocks[userId][techId] == true
end

--- 해금된 기술 목록 조회
--- @param userId number
--- @return table { techId → true }
function TechService.getUnlockedTech(userId: number): { [string]: boolean }
	_initPlayerUnlocks(userId)
	return playerUnlocks[userId] or {}
end

--- 해금 가능한 기술 목록 조회 (선행 기술 충족, 미해금)
--- @param userId number
--- @return table { techId → techData }
function TechService.getAvailableTech(userId: number): { [string]: any }
	_initPlayerUnlocks(userId)
	
	local available = {}
	local unlocks = playerUnlocks[userId]
	
	for techId, tech in pairs(techDataMap) do
		-- 이미 해금된 건 제외
		if not unlocks[techId] then
			-- 선행 기술 충족 여부
			if _checkPrerequisites(userId, techId) then
				available[techId] = {
					id = tech.id,
					name = tech.name,
					description = tech.description,
					techLevel = tech.techLevel,
					techPointCost = tech.techPointCost,
					prerequisites = tech.prerequisites,
					unlocks = tech.unlocks,
					category = tech.category,
				}
			end
		end
	end
	
	return available
end

--- 전체 기술 트리 데이터 조회
--- @return table
function TechService.getTechTree(): { [string]: any }
	return techDataMap
end

--========================================
-- Public API: Recipe Lock Check
--========================================

--- 특정 레시피가 해금되었는지 확인
--- @param userId number
--- @param recipeId string
--- @return boolean
function TechService.isRecipeUnlocked(userId: number, recipeId: string): boolean
	_initPlayerUnlocks(userId)
	local unlocks = playerUnlocks[userId]
	
	-- 모든 기술 순회하여 레시피가 해금되었는지 확인
	for techId, isUnlocked in pairs(unlocks) do
		if isUnlocked then
			local tech = techDataMap[techId]
			if tech and tech.unlocks and tech.unlocks.recipes then
				for _, recipe in ipairs(tech.unlocks.recipes) do
					if recipe == recipeId then
						return true
					end
				end
			end
		end
	end
	
	return false
end

--- 특정 시설이 해금되었는지 확인
--- @param userId number
--- @param facilityId string
--- @return boolean
function TechService.isFacilityUnlocked(userId: number, facilityId: string): boolean
	_initPlayerUnlocks(userId)
	local unlocks = playerUnlocks[userId]
	
	for techId, isUnlocked in pairs(unlocks) do
		if isUnlocked then
			local tech = techDataMap[techId]
			if tech and tech.unlocks and tech.unlocks.facilities then
				for _, fac in ipairs(tech.unlocks.facilities) do
					if fac == facilityId then
						return true
					end
				end
			end
		end
	end
	
	return false
end

--- 특정 기능이 해금되었는지 확인
--- @param userId number
--- @param featureId string
--- @return boolean
function TechService.isFeatureUnlocked(userId: number, featureId: string): boolean
	_initPlayerUnlocks(userId)
	local unlocks = playerUnlocks[userId]
	
	for techId, isUnlocked in pairs(unlocks) do
		if isUnlocked then
			local tech = techDataMap[techId]
			if tech and tech.unlocks and tech.unlocks.features then
				for _, feat in ipairs(tech.unlocks.features) do
					if feat == featureId then
						return true
					end
				end
			end
		end
	end
	
	return false
end

--========================================
-- Handlers
--========================================

local function handleUnlock(player: Player, payload: any)
	if not payload or not payload.techId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode = TechService.unlock(player.UserId, payload.techId)
	
	if success then
		return {
			success = true,
			data = {
				techId = payload.techId,
				techPointsRemaining = PlayerStatService.getTechPoints(player.UserId),
			}
		}
	else
		return { success = false, errorCode = errorCode }
	end
end

local function handleList(player: Player, payload: any)
	local userId = player.UserId
	_initPlayerUnlocks(userId)
	
	return {
		success = true,
		data = {
			unlocked = TechService.getUnlockedTech(userId),
			available = TechService.getAvailableTech(userId),
			techPoints = PlayerStatService.getTechPoints(userId),
		}
	}
end

local function handleTree(player: Player, payload: any)
	-- 전체 기술 트리 반환 (클라이언트 UI용)
	local tree = {}
	for techId, tech in pairs(techDataMap) do
		tree[techId] = {
			id = tech.id,
			name = tech.name,
			description = tech.description,
			techLevel = tech.techLevel,
			techPointCost = tech.techPointCost,
			prerequisites = tech.prerequisites,
			category = tech.category,
			-- unlocks는 보안상 제외하거나 포함 (선택)
			unlocks = tech.unlocks,
		}
	end
	
	return {
		success = true,
		data = {
			tree = tree,
		}
	}
end

--========================================
-- Lifecycle
--========================================

function TechService.Init(netController, dataService, playerStatService, saveService)
	if initialized then return end
	initialized = true
	
	NetController = netController
	DataService = dataService
	PlayerStatService = playerStatService
	SaveService = saveService
	
	-- 기술 데이터 로드
	_loadTechData()
	
	-- Player 접속 시 해금 상태 초기화
	game:GetService("Players").PlayerAdded:Connect(function(player)
		_initPlayerUnlocks(player.UserId)
	end)
	
	-- Player 퇴장 시 정리
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		_savePlayerUnlocks(player.UserId)
		playerUnlocks[player.UserId] = nil
	end)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		_initPlayerUnlocks(player.UserId)
	end
	
	print("[TechService] Initialized")
end

function TechService.GetHandlers()
	return {
		["Tech.Unlock.Request"] = handleUnlock,
		["Tech.List.Request"] = handleList,
		["Tech.Tree.Request"] = handleTree,
	}
end

--- 기술 해금 콜백 설정 (Phase 8)
function TechService.SetUnlockCallback(callback)
	unlockCallback = callback
end

return TechService
