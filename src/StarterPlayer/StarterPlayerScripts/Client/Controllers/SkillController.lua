-- SkillController.lua
-- 클라이언트 스킬 트리 컨트롤러
-- 서버 SkillService와 연동하여 해금 상태 관리 및 UI 데이터 제공

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)

local SkillController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 상태 캐시
local unlockedSkills = {}    -- { [skillId] = true }
local combatTreeId = nil     -- "SWORD" | "BOW" | "AXE" | nil
local spAvailable = 0
local spSpent = 0
local activeSkillSlots = { nil, nil, nil, nil }
local playerLevel = 1

-- 액티브 스킬 쿨다운 (클라이언트 예측)
local DEV_NO_COOLDOWN = true  -- ★ 개발용 노쿨 (릴리즈 시 false로 변경)
local skillCooldowns = {}     -- { [skillId] = endTime (tick) }
local skillGCD = 0            -- 글로벌 쿨다운 종료 시각

-- 이벤트 리스너
local listeners = {
	skillDataUpdated = {},
	cooldownUpdated = {},
}

--========================================
-- Internal
--========================================

local function _fireListeners()
	for _, cb in ipairs(listeners.skillDataUpdated) do
		pcall(cb)
	end
end

local function _fireCooldownListeners()
	for _, cb in ipairs(listeners.cooldownUpdated) do
		pcall(cb)
	end
end

--========================================
-- Public API: Cache Access
--========================================

function SkillController.getUnlockedSkills()
	return unlockedSkills
end

function SkillController.getCombatTreeId()
	return combatTreeId
end

function SkillController.getSPAvailable()
	return spAvailable
end

function SkillController.getSPSpent()
	return spSpent
end

function SkillController.getActiveSkillSlots()
	return activeSkillSlots
end

function SkillController.getPlayerLevel()
	return playerLevel
end

function SkillController.isSkillUnlocked(skillId: string): boolean
	return unlockedSkills[skillId] == true
end

--- 스킬 해금 가능 여부 체크 (로컬 판단)
function SkillController.canUnlock(skillId: string): (boolean, string?)
	local skill = SkillTreeData.GetSkill(skillId)
	if not skill then return false, "SKILL_NOT_FOUND" end
	if unlockedSkills[skillId] then return false, "ALREADY_UNLOCKED" end

	-- 레벨 체크
	if playerLevel < skill.reqLevel then return false, "LEVEL_TOO_LOW" end

	-- 건축은 SP 불요
	if skill.type ~= "BUILD_TIER" then
		-- 전투 계열 택1 체크
		local treeId = SkillTreeData.GetTreeIdForSkill(skillId)
		if treeId and SkillTreeData.IsCombatTree(treeId) then
			if combatTreeId and combatTreeId ~= treeId then
				return false, "TREE_LOCKED"
			end
		end
		-- SP 체크
		if spAvailable < skill.spCost then return false, "NOT_ENOUGH_SP" end
	end

	-- 선행 체크
	if skill.prereqs and #skill.prereqs > 0 then
		for _, pid in ipairs(skill.prereqs) do
			if not unlockedSkills[pid] then
				return false, "PREREQS_NOT_MET"
			end
		end
	end

	return true, nil
end

--========================================
-- Server Requests
--========================================

--- 서버에서 스킬 데이터 전체 조회
function SkillController.requestData(callback: ((boolean) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.GetData.Request", {})
		if ok and data then
			unlockedSkills = data.unlockedSkills or {}
			combatTreeId = data.combatTreeId
			spAvailable = data.spAvailable or 0
			spSpent = data.spSpent or 0
			activeSkillSlots = data.activeSkillSlots or { nil, nil, nil, nil }
			playerLevel = data.level or 1
			_fireListeners()
		end
		if callback then callback(ok) end
	end)
end

--- 스킬 해금 요청
function SkillController.requestUnlock(skillId: string, callback: ((boolean, string?) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.Unlock.Request", { skillId = skillId })
		if ok and data then
			-- 로컬 캐시 즉시 반영
			unlockedSkills[skillId] = true
			if data.spRemaining ~= nil then
				spAvailable = data.spRemaining
			end
			if data.combatTreeId then
				combatTreeId = data.combatTreeId
			end
			local skill = SkillTreeData.GetSkill(skillId)
			if skill then
				spSpent = spSpent + skill.spCost
			end
			_fireListeners()
		end
		if callback then
			callback(ok, (not ok and data) and tostring(data.errorCode or "UNKNOWN") or nil)
		end
	end)
end

--- 액티브 스킬 슬롯 설정
function SkillController.requestSetSlot(slotIndex: number, skillId: string?, callback: ((boolean) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.SetSlot.Request", { slot = slotIndex, skillId = skillId })
		if ok and data and data.activeSkillSlots then
			activeSkillSlots = data.activeSkillSlots
			_fireListeners()
		end
		if callback then callback(ok) end
	end)
end

--========================================
-- Active Skill Usage
--========================================

--- 슬롯 인덱스(1~3)로 스킬 사용
function SkillController.useSkillBySlot(slotIndex: number, targetId: string?)
	if slotIndex < 1 or slotIndex > 4 then return end
	local skillId = activeSkillSlots[slotIndex]
	if not skillId then return end
	SkillController.useSkill(skillId, targetId)
end

--- 스킬 ID로 직접 사용
function SkillController.useSkill(skillId: string, targetId: string?)
	-- 로컬 쿨다운 프리체크
	local now = tick()
	if not DEV_NO_COOLDOWN then
		if skillGCD > now then return end
		if skillCooldowns[skillId] and skillCooldowns[skillId] > now then return end
	end
	
	-- 스킬 데이터 조회
	local skill = SkillTreeData.GetSkill(skillId)
	if not skill or skill.type ~= "ACTIVE" then return end
	
	-- 로컬 쿨다운 즉시 설정 (클라이언트 예측)
	if not DEV_NO_COOLDOWN then
		skillCooldowns[skillId] = now + skill.cooldown
		skillGCD = now + 0.5
	end
	_fireCooldownListeners()
	
	-- ★ aimDirection 계산: 캐릭터 정면 방향(LookVector) 사용
	local aimDirection = nil
	local Players = game:GetService("Players")
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local look = hrp.CFrame.LookVector
		aimDirection = { x = look.X, y = look.Y, z = look.Z }
	end
	
	task.spawn(function()
		local payload = { skillId = skillId, targetId = targetId }
		if aimDirection then
			payload.aimDirection = aimDirection
		end
		local ok, data = NetClient.Request("Skill.Use.Request", payload)
		if ok and data then
			-- 서버에서 받은 쿨다운으로 보정
			if data.cooldowns then
				for sid, remaining in pairs(data.cooldowns) do
					skillCooldowns[sid] = tick() + remaining
				end
			end
		else
			-- 실패 시 로컬 쿨다운 롤백
			skillCooldowns[skillId] = nil
			skillGCD = 0
			-- ★ 에러 피드백 표시
			local errorCode = data -- NetClient는 실패 시 (false, errorCode) 반환
			local UIManager = require(script.Parent.Parent.UIManager)
			if UIManager and UIManager.notify then
				local SKILL_ERROR_MESSAGES = {
					WEAPON_MISMATCH = "해당 스킬에 맞는 무기를 장착해주세요.",
					SKILL_NOT_IN_SLOT = "스킬이 슬롯에 장착되어 있지 않습니다.",
					SKILL_NOT_UNLOCKED = "스킬이 해금되지 않았습니다.",
					NOT_ENOUGH_STAMINA = "스태미나가 부족합니다.",
					PLAYER_DEAD = "사용할 수 없는 상태입니다.",
					COOLDOWN = "스킬이 재사용 대기 중입니다.",
				}
				local msg = SKILL_ERROR_MESSAGES[errorCode]
				if not msg then
					msg = "스킬을 사용할 수 없습니다."
					warn("[SkillController] Unknown skill error:", errorCode)
				end
				UIManager.notify(msg, Color3.fromRGB(255, 140, 140))
			end
		end
		_fireCooldownListeners()
	end)
end

--- 특정 스킬 잔여 쿨다운 조회 (초)
function SkillController.getSkillCooldownRemaining(skillId: string): number
	local cd = skillCooldowns[skillId]
	if not cd then return 0 end
	local remaining = cd - tick()
	return remaining > 0 and remaining or 0
end

--- 슬롯별 쿨다운 조회
function SkillController.getSlotCooldownRemaining(slotIndex: number): number
	local skillId = activeSkillSlots[slotIndex]
	if not skillId then return 0 end
	return SkillController.getSkillCooldownRemaining(skillId)
end

--- 특정 스킬이 사용 가능한지 체크
function SkillController.canUseSkill(skillId: string): boolean
	return SkillController.getSkillCooldownRemaining(skillId) <= 0
end

--========================================
-- Event Listeners
--========================================

function SkillController.onSkillDataUpdated(callback: () -> ())
	table.insert(listeners.skillDataUpdated, callback)
end

function SkillController.onCooldownUpdated(callback: () -> ())
	table.insert(listeners.cooldownUpdated, callback)
end

--========================================
-- [DEV] SP 초기화
--========================================

function SkillController.requestReset(callback: ((boolean) -> ())?)
	task.spawn(function()
		print("[SkillController] Requesting SP reset...")
		local ok, data = NetClient.Request("Skill.Reset.Request", {})
		print("[SkillController] Reset response:", ok, data)
		if ok and data then
			unlockedSkills = data.unlockedSkills or {}
			combatTreeId = data.combatTreeId
			spAvailable = data.spAvailable or 0
			spSpent = data.spSpent or 0
			activeSkillSlots = data.activeSkillSlots or { nil, nil, nil, nil }
			playerLevel = data.level or 1
			_fireListeners()
		end
		if callback then callback(ok) end
	end)
end

--========================================
-- Init
--========================================

function SkillController.Init()
	if initialized then return end
	initialized = true

	-- 초기 데이터 로드 (재시도 포함 — 서버 SaveService 로딩 대기 대응)
	task.spawn(function()
		for _attempt = 1, 5 do
			local ok, data = NetClient.Request("Skill.GetData.Request", {})
			if ok and data then
				unlockedSkills = data.unlockedSkills or {}
				combatTreeId = data.combatTreeId
				spAvailable = data.spAvailable or 0
				spSpent = data.spSpent or 0
				activeSkillSlots = data.activeSkillSlots or { nil, nil, nil, nil }
				playerLevel = data.level or 1
				_fireListeners()
				break
			end
			task.wait(2)
		end
	end)

	print("[SkillController] Initialized")
end

return SkillController
