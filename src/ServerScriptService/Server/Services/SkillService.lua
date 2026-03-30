-- SkillService.lua
-- 스킬 트리 서버 서비스
-- 전투 계열 택1 잠금 + SP 소모 해금 + 패시브 보너스 조회

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)

local SkillService = {}

-- Dependencies (injected via Init)
local NetController
local PlayerStatService
local SaveService

-- 유저별 런타임 캐시 { [userId] = { unlockedSkills={}, combatTreeId=nil, skillPointsSpent=0, activeSkillSlots={} } }
local playerSkillCache = {}

--========================================
-- Internal Helpers
--========================================

--- 플레이어 스킬 캐시 초기화 (SaveService 데이터 로드)
local function _initPlayerSkills(userId: number)
	if playerSkillCache[userId] then return end

	local state = SaveService.getPlayerState(userId)
	if not state then
		playerSkillCache[userId] = {
			unlockedSkills = {},
			combatTreeId = nil,
			skillPointsSpent = 0,
			activeSkillSlots = { nil, nil, nil },
		}
		return
	end

	playerSkillCache[userId] = {
		unlockedSkills = type(state.unlockedSkills) == "table" and state.unlockedSkills or {},
		combatTreeId = state.combatTreeId,
		skillPointsSpent = state.skillPointsSpent or 0,
		activeSkillSlots = type(state.activeSkillSlots) == "table" and state.activeSkillSlots or { nil, nil, nil },
	}
end

--- SP 잔여량 계산 (총 획득 - 소모)
local function _getAvailableSP(userId: number): number
	_initPlayerSkills(userId)
	local level = PlayerStatService.getLevel(userId) or 1
	local totalEarned = math.max(0, (level - 1) * Balance.SKILL_POINTS_PER_LEVEL)
	return math.max(0, totalEarned - playerSkillCache[userId].skillPointsSpent)
end

--- 스킬 데이터 조회 (모든 트리 탐색)
local function _findSkill(skillId: string)
	return SkillTreeData.GetSkill(skillId)
end

--- 스킬이 속한 트리 ID 반환
local function _getTreeIdForSkill(skillId: string): string?
	return SkillTreeData.GetTreeIdForSkill(skillId)
end

--- 전투 계열인지 체크
local function _isCombatTreeId(treeId: string): boolean
	for _, id in ipairs(SkillTreeData.COMBAT_TREE_IDS) do
		if id == treeId then return true end
	end
	return false
end

--- 선행 스킬 해금 여부 체크
local function _arePrereqsMet(userId: number, skill): boolean
	if not skill.prereqs or #skill.prereqs == 0 then return true end
	local cache = playerSkillCache[userId]
	for _, prereqId in ipairs(skill.prereqs) do
		if not cache.unlockedSkills[prereqId] then
			return false
		end
	end
	return true
end

--- SaveService에 스킬 데이터 즉시 반영
local function _syncToSave(userId: number)
	local cache = playerSkillCache[userId]
	if not cache then return end

	local state = SaveService.getPlayerState(userId)
	if not state then return end

	state.unlockedSkills = cache.unlockedSkills
	state.combatTreeId = cache.combatTreeId
	state.skillPointsSpent = cache.skillPointsSpent
	state.activeSkillSlots = cache.activeSkillSlots
end

--========================================
-- Public API
--========================================

--- 해금된 스킬 목록 조회
function SkillService.getUnlockedSkills(userId: number): { [string]: boolean }
	_initPlayerSkills(userId)
	return playerSkillCache[userId].unlockedSkills
end

--- 선택한 전투 계열 ID (nil = 아직 미선택)
function SkillService.getCombatTreeId(userId: number): string?
	_initPlayerSkills(userId)
	return playerSkillCache[userId].combatTreeId
end

--- 잔여 SP
function SkillService.getAvailableSP(userId: number): number
	return _getAvailableSP(userId)
end

--- 특정 스킬 해금 여부
function SkillService.isSkillUnlocked(userId: number, skillId: string): boolean
	_initPlayerSkills(userId)
	return playerSkillCache[userId].unlockedSkills[skillId] == true
end

--- 현재 장착한 무기 타입에 해당하는 해금된 패시브 효과 합산
--- weaponTreeId: "SWORD" | "BOW" | "AXE"
function SkillService.getPassiveBonuses(userId: number, weaponTreeId: string): { [string]: number }
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]
	local bonuses = {}

	-- 해당 무기 계열만 적용 (전투 계열이 다르면 보너스 없음)
	if cache.combatTreeId ~= weaponTreeId then
		return bonuses
	end

	local treeData = SkillTreeData[weaponTreeId]
	if not treeData then return bonuses end

	for _, skill in ipairs(treeData) do
		if skill.type == "PASSIVE" and cache.unlockedSkills[skill.id] then
			for _, eff in ipairs(skill.effects) do
				bonuses[eff.stat] = (bonuses[eff.stat] or 0) + eff.value
			end
		end
	end

	return bonuses
end

--- 액티브 스킬 슬롯 조회
function SkillService.getActiveSkillSlots(userId: number): { string? }
	_initPlayerSkills(userId)
	return playerSkillCache[userId].activeSkillSlots
end

--========================================
-- Handlers
--========================================

--- 스킬 해금 요청 처리
local function handleUnlockSkill(player: Player, payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	local skillId = payload and payload.skillId
	if type(skillId) ~= "string" or skillId == "" then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	-- 스킬 데이터 검증
	local skill = _findSkill(skillId)
	if not skill then
		return { success = false, errorCode = "SKILL_NOT_FOUND" }
	end

	-- 이미 해금?
	if cache.unlockedSkills[skillId] then
		return { success = false, errorCode = "ALREADY_UNLOCKED" }
	end

	-- 건축 계열은 SP 불요, 레벨만 체크
	local treeId = _getTreeIdForSkill(skillId)
	if not treeId then
		return { success = false, errorCode = "SKILL_NOT_FOUND" }
	end

	local level = PlayerStatService.getLevel(userId) or 1

	if skill.type == "BUILD_TIER" then
		-- 건축은 레벨만 체크
		if level < skill.reqLevel then
			return { success = false, errorCode = "LEVEL_TOO_LOW" }
		end
		-- 선행 체크
		if not _arePrereqsMet(userId, skill) then
			return { success = false, errorCode = "PREREQS_NOT_MET" }
		end
		cache.unlockedSkills[skillId] = true
		_syncToSave(userId)
		return { success = true, data = { skillId = skillId, type = "BUILD_TIER" } }
	end

	-- 전투 계열: 택1 잠금 체크
	if _isCombatTreeId(treeId) then
		if cache.combatTreeId and cache.combatTreeId ~= treeId then
			return { success = false, errorCode = "TREE_LOCKED" }
		end

		-- 첫 투자 시 계열 확정 (클라이언트에서 확인 다이얼로그 후 전송)
		if not cache.combatTreeId then
			cache.combatTreeId = treeId
		end
	end

	-- 레벨 체크
	if level < skill.reqLevel then
		return { success = false, errorCode = "LEVEL_TOO_LOW" }
	end

	-- SP 체크
	local available = _getAvailableSP(userId)
	if available < skill.spCost then
		return { success = false, errorCode = "NOT_ENOUGH_SP" }
	end

	-- 선행 체크
	if not _arePrereqsMet(userId, skill) then
		return { success = false, errorCode = "PREREQS_NOT_MET" }
	end

	-- 해금 처리
	cache.unlockedSkills[skillId] = true
	cache.skillPointsSpent = cache.skillPointsSpent + skill.spCost
	_syncToSave(userId)

	print(string.format("[SkillService] %s unlocked skill %s (SP spent: %d, remaining: %d)",
		player.Name, skillId, skill.spCost, _getAvailableSP(userId)))

	return {
		success = true,
		data = {
			skillId = skillId,
			spRemaining = _getAvailableSP(userId),
			combatTreeId = cache.combatTreeId,
		},
	}
end

--- 스킬 데이터 전체 조회 (UI 렌더링용)
local function handleGetData(player: Player, _payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	return {
		success = true,
		data = {
			unlockedSkills = cache.unlockedSkills,
			combatTreeId = cache.combatTreeId,
			spAvailable = _getAvailableSP(userId),
			spSpent = cache.skillPointsSpent,
			activeSkillSlots = cache.activeSkillSlots,
			level = PlayerStatService.getLevel(userId) or 1,
		},
	}
end

--- 액티브 스킬 슬롯 설정
local function handleSetSlot(player: Player, payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	local slotIndex = payload and payload.slot
	local skillId = payload and payload.skillId -- nil = 슬롯 비우기

	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 3 then
		return { success = false, errorCode = "BAD_REQUEST" }
	end
	slotIndex = math.floor(slotIndex)

	if skillId ~= nil then
		if type(skillId) ~= "string" then
			return { success = false, errorCode = "BAD_REQUEST" }
		end
		-- 해금 여부 체크
		if not cache.unlockedSkills[skillId] then
			return { success = false, errorCode = "SKILL_NOT_UNLOCKED" }
		end
		-- 액티브 타입만 슬롯 가능
		local skill = _findSkill(skillId)
		if not skill or skill.type ~= "ACTIVE" then
			return { success = false, errorCode = "NOT_ACTIVE_SKILL" }
		end
		-- 이미 다른 슬롯에 장착된 경우 제거
		for i = 1, 3 do
			if cache.activeSkillSlots[i] == skillId then
				cache.activeSkillSlots[i] = nil
			end
		end
	end

	cache.activeSkillSlots[slotIndex] = skillId
	_syncToSave(userId)

	return {
		success = true,
		data = {
			activeSkillSlots = cache.activeSkillSlots,
		},
	}
end

--- [DEV] SP 초기화 요청 처리
local function handleResetSkills(player: Player, _payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	cache.unlockedSkills = {}
	cache.combatTreeId = nil
	cache.skillPointsSpent = 0
	cache.activeSkillSlots = { nil, nil, nil }
	_syncToSave(userId)

	print(string.format("[SkillService] %s RESET all skills (SP refunded)", player.Name))

	return {
		success = true,
		data = {
			unlockedSkills = cache.unlockedSkills,
			combatTreeId = cache.combatTreeId,
			spAvailable = _getAvailableSP(userId),
			spSpent = cache.skillPointsSpent,
			activeSkillSlots = cache.activeSkillSlots,
			level = PlayerStatService.getLevel(userId) or 1,
		},
	}
end

--========================================
-- Init / GetHandlers
--========================================

function SkillService.GetHandlers()
	return {
		["Skill.Unlock.Request"] = handleUnlockSkill,
		["Skill.GetData.Request"] = handleGetData,
		["Skill.SetSlot.Request"] = handleSetSlot,
		["Skill.Reset.Request"] = handleResetSkills,
	}
end

function SkillService.Init(_NetController, _PlayerStatService, _SaveService)
	NetController = _NetController
	PlayerStatService = _PlayerStatService
	SaveService = _SaveService

	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		SkillService.onPlayerRemoving(player.UserId)
	end)

	print("[SkillService] Initialized")
end

--- 플레이어 정리 (로그아웃 시 캐시 해제)
function SkillService.onPlayerRemoving(userId: number)
	playerSkillCache[userId] = nil
end

return SkillService
