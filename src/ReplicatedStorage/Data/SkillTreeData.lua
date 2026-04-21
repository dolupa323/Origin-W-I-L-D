-- SkillTreeData.lua
-- 스킬 트리 데이터 정의 (전투 택1 + 건축/포획 자동해금)
-- 전투 계열: SWORD, BOW, AXE (택 1)
-- 비전투 계열: BUILD, TAMING (SP 불요, 레벨 자동 해금)

local SkillTreeData = {}

--========================================
-- 스킬 트리 탭 정의
--========================================
SkillTreeData.TABS = {
	{ id = "SWORD", name = "검술 연마", isCombat = true },
	{ id = "BOW",   name = "궁술 연마", isCombat = true },
	{ id = "AXE",   name = "도끼 연마", isCombat = true },
	{ id = "BUILD", name = "건축 연구", isCombat = false },
	{ id = "TAMING", name = "포획 연구", isCombat = false },
}

-- 전투 계열 ID 목록 (택1 잠금용)
SkillTreeData.COMBAT_TREE_IDS = { "SWORD", "BOW", "AXE" }

--========================================
-- 스킬 타입
--========================================
-- PASSIVE: 무기 장착 시 자동 적용
-- ACTIVE: 슬롯 장착 후 발동
-- BUILD_TIER: SP 불요, 레벨 도달 시 자동 해금

--========================================
-- 검술 연마 (SWORD) — 총 32 SP
--========================================
SkillTreeData.SWORD = {
	-- 패시브 5개
	{
		id = "SWORD_P1",
		name = "검술 수련 I",
		type = "PASSIVE",
		icon = "PASSIVE_SWORD",
		reqLevel = 3,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.08 },
		},
		description = "검 공격력 +8%",
	},
	{
		id = "SWORD_P2",
		name = "검술 수련 II",
		type = "PASSIVE",
		icon = "PASSIVE_SWORD",
		reqLevel = 10,
		spCost = 3,
		prereqs = { "SWORD_P1" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.12 },
		},
		description = "검 공격력 +12%",
	},
	{
		id = "SWORD_P3",
		name = "검술 숙련",
		type = "PASSIVE",
		icon = "PASSIVE_SWORD",
		reqLevel = 20,
		spCost = 5,
		prereqs = { "SWORD_P2" },
		effects = {
			{ stat = "CRIT_CHANCE", value = 0.08 },
		},
		description = "검 치명타율 +8%",
	},
	{
		id = "SWORD_P4",
		name = "검술 전문화",
		type = "PASSIVE",
		icon = "PASSIVE_SWORD",
		reqLevel = 35,
		spCost = 6,
		prereqs = { "SWORD_P3" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.15 },
		},
		description = "검 공격력 +15%",
	},
	{
		id = "SWORD_P5",
		name = "검술 대가",
		type = "PASSIVE",
		icon = "PASSIVE_SWORD",
		reqLevel = 45,
		spCost = 8,
		prereqs = { "SWORD_P4" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.20 },
			{ stat = "CRIT_DAMAGE_MULT", value = 0.25 },
		},
		description = "검 공격력 +20%, 치명타 데미지 +25%",
	},
	-- 액티브 3개
	{
		id = "SWORD_A1",
		name = "강타",
		type = "ACTIVE",
		icon = "ACTIVE_SWORD_STRIKE",
		reqLevel = 8,
		spCost = 2,
		prereqs = { "SWORD_P1" },
		cooldown = 12,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 2.00 },
		},
		description = "전방 강력 베기, 기본 공격력 200%",
	},
	{
		id = "SWORD_A2",
		name = "돌진",
		type = "ACTIVE",
		icon = "ACTIVE_SWORD_CHARGE",
		reqLevel = 25,
		spCost = 3,
		prereqs = { "SWORD_P3" },
		cooldown = 18,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 3.50 },
			{ stat = "SLOW_DURATION", value = 2.5 },
		},
		description = "전방 8스터드 돌진, 350%, 2.5초 둔화",
	},
	{
		id = "SWORD_A3",
		name = "난무",
		type = "ACTIVE",
		icon = "ACTIVE_SWORD_FLURRY",
		reqLevel = 40,
		spCost = 3,
		prereqs = { "SWORD_P4" },
		cooldown = 30,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 5 },
			{ stat = "SKILL_DAMAGE_MULT", value = 1.60 },
			{ stat = "SKILL_FINAL_HIT_MULT", value = 3.50 },
		},
		description = "1.5초간 5회 연속 베기, 각 160%, 마지막 350% (총 1150%)",
	},
}

--========================================
-- 궁술 연마 (BOW) — 총 32 SP
--========================================
SkillTreeData.BOW = {
	-- 패시브 5개
	{
		id = "BOW_P1",
		name = "궁술 수련 I",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 3,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.05 },
		},
		description = "활 공격력 +5%",
	},
	{
		id = "BOW_P2",
		name = "궁술 수련 II",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 10,
		spCost = 3,
		prereqs = { "BOW_P1" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.08 },
		},
		description = "활 공격력 +8%",
	},
	{
		id = "BOW_P3",
		name = "궁술 숙련",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 20,
		spCost = 5,
		prereqs = { "BOW_P2" },
		effects = {
			{ stat = "CRIT_CHANCE", value = 0.08 },
			{ stat = "NO_ARROW_CONSUME", value = 1 },
		},
		description = "활 치명타율 +8%, 화살 소모 없음",
	},
	{
		id = "BOW_P4",
		name = "궁술 전문화",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 35,
		spCost = 6,
		prereqs = { "BOW_P3" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.10 },
		},
		description = "활 공격력 +10%",
	},
	{
		id = "BOW_P5",
		name = "궁술 대가",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 45,
		spCost = 8,
		prereqs = { "BOW_P4" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.15 },
		},
		description = "활 공격력 +15%",
	},
	-- 액티브 3개
	{
		id = "BOW_A1",
		name = "강사",
		type = "ACTIVE",
		icon = "ACTIVE_BOW_POWER",
		reqLevel = 8,
		spCost = 2,
		prereqs = { "BOW_P1" },
		cooldown = 14,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 2.50 },
			{ stat = "STAGGER_DURATION", value = 2.0 },
			{ stat = "SKILL_CHARGE_TIME", value = 1.5 },
		},
		description = "1.5초 충전, 250%, 2초 경직",
	},
	{
		id = "BOW_A2",
		name = "속사",
		type = "ACTIVE",
		icon = "ACTIVE_BOW_RAPID",
		reqLevel = 25,
		spCost = 3,
		prereqs = { "BOW_P3" },
		cooldown = 20,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 5 },
			{ stat = "SKILL_DAMAGE_MULT", value = 0.90 },
		},
		description = "1초간 5발 연속 사격, 각 90% (총 450%)",
	},
	{
		id = "BOW_A3",
		name = "폭렬 사격",
		type = "ACTIVE",
		icon = "ACTIVE_BOW_EXPLOSIVE",
		reqLevel = 40,
		spCost = 3,
		prereqs = { "BOW_P4" },
		cooldown = 35,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 3.00 },
			{ stat = "SKILL_AOE_RADIUS", value = 8 },
			{ stat = "SKILL_DOT_DURATION", value = 5 },
			{ stat = "SKILL_DOT_TICK_PCT", value = 0.05 },
		},
		description = "폭발 화살, 8스터드 범위 300%, 5초 화상(틱당 5%)",
	},
}

--========================================
-- 도끼 연마 (AXE) — 총 32 SP
--========================================
SkillTreeData.AXE = {
	-- 패시브 5개
	{
		id = "AXE_P1",
		name = "도끼 수련 I",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 3,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.08 },
		},
		description = "도끼 공격력 +8%",
	},
	{
		id = "AXE_P2",
		name = "도끼 수련 II",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 10,
		spCost = 3,
		prereqs = { "AXE_P1" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.12 },
		},
		description = "도끼 공격력 +12%",
	},
	{
		id = "AXE_P3",
		name = "도끼 숙련",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 20,
		spCost = 5,
		prereqs = { "AXE_P2" },
		effects = {
			{ stat = "CRIT_CHANCE", value = 0.10 },
		},
		description = "도끼 치명타율 +10%",
	},
	{
		id = "AXE_P4",
		name = "도끼 전문화",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 35,
		spCost = 6,
		prereqs = { "AXE_P3" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.15 },
		},
		description = "도끼 공격력 +15%",
	},
	{
		id = "AXE_P5",
		name = "도끼 대가",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 45,
		spCost = 8,
		prereqs = { "AXE_P4" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.20 },
			{ stat = "HEAL_ON_HIT_CHANCE", value = 0.10 },
			{ stat = "HEAL_ON_HIT_PCT", value = 0.03 },
		},
		description = "도끼 공격력 +20%, 평타 적중 10% 확률로 최대HP 3% 회복",
	},
	-- 액티브 3개
	{
		id = "AXE_A1",
		name = "내려찍기",
		type = "ACTIVE",
		icon = "ACTIVE_AXE_SLAM",
		reqLevel = 8,
		spCost = 2,
		prereqs = { "AXE_P1" },
		cooldown = 12,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 4 },
			{ stat = "SKILL_DAMAGE_MULT", value = 0.625 },
			{ stat = "SLOW_DURATION", value = 2.5 },
			{ stat = "SLOW_AMOUNT", value = 0.40 },
		},
		description = "수직 타격, 4회 각 62.5% (총 250%), 2.5초 둔화(-40%)",
	},
	{
		id = "AXE_A2",
		name = "회전 베기",
		type = "ACTIVE",
		icon = "ACTIVE_AXE_SPIN",
		reqLevel = 25,
		spCost = 3,
		prereqs = { "AXE_P3" },
		cooldown = 22,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 28 },
			{ stat = "SKILL_DAMAGE_MULT", value = 0.10 },
			{ stat = "SKILL_AOE_RADIUS", value = 8 },
		},
		description = "360도 8스터드 범위, 28회 연타 각 10% (총 280%)",
	},
	{
		id = "AXE_A3",
		name = "도끼 폭풍",
		type = "ACTIVE",
		icon = "ACTIVE_AXE_STORM",
		reqLevel = 40,
		spCost = 3,
		prereqs = { "AXE_P4" },
		cooldown = 35,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 8 },
			{ stat = "SKILL_DAMAGE_MULT", value = 1.50 },
		},
		description = "2초간 8회 연타, 각 150% (총 1200%)",
	},
}

--========================================
-- 건축 연구 (BUILD) — SP 불요, 레벨 자동 해금
--========================================
SkillTreeData.BUILD = {
	{
		id = "BUILD_T0",
		name = "기초 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 1,
		spCost = 0,
		prereqs = {},
		effects = {},
		description = "캠프파이어, 임시 침대 등 기본 구조물",
	},
	{
		id = "BUILD_T1",
		name = "초급 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 10,
		spCost = 0,
		prereqs = { "BUILD_T0" },
		effects = {},
		description = "기초작업대 이상의 블럭 가공과 기본 블럭 건축을 해금합니다.",
	},
	{
		id = "BUILD_T2",
		name = "중급 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 20,
		spCost = 0,
		prereqs = { "BUILD_T1" },
		effects = {},
		description = "청동기 작업대 및 중급 건축 시설을 해금합니다.",
	},
	{
		id = "BUILD_T3",
		name = "고급 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 30,
		spCost = 0,
		prereqs = { "BUILD_T2" },
		effects = {},
		description = "철기 작업대 및 고급 건축 시설을 해금합니다.",
	},
	{
		id = "BUILD_T4",
		name = "마스터 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 40,
		spCost = 0,
		prereqs = { "BUILD_T3" },
		effects = {},
		description = "석조 건축 블럭 등 최상위 건축 기술을 해금합니다.",
	},
}

--========================================
-- 포획 연구 (TAMING) — SP 필요, 레벨 도달 + SP 투자
--========================================
SkillTreeData.TAMING = {
	{
		id = "TAMING_T1",
		name = "초급 포획",
		type = "PASSIVE",
		icon = "TAMING_TIER",
		reqLevel = 10,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "TAMING_RATE_BONUS", value = 0.02 },
		},
		unlockCreatures = { "DODO", "COMPY", "ARCHAEOPTERYX", "TROODON", "OLOROTITAN" },
		description = "포획 확률 +2%\n초원 소형/중형 크리처 포획 해금",
	},
	{
		id = "TAMING_T2",
		name = "중급 포획",
		type = "PASSIVE",
		icon = "TAMING_TIER",
		reqLevel = 20,
		spCost = 3,
		prereqs = { "TAMING_T1" },
		effects = {
			{ stat = "TAMING_RATE_BONUS", value = 0.03 },
		},
		unlockCreatures = { "KELENKEN" },
		description = "포획 확률 +3%\n켈렌켄 포획 해금",
	},
	{
		id = "TAMING_T3",
		name = "고급 포획",
		type = "PASSIVE",
		icon = "TAMING_TIER",
		reqLevel = 30,
		spCost = 4,
		prereqs = { "TAMING_T2" },
		effects = {
			{ stat = "TAMING_RATE_BONUS", value = 0.04 },
		},
		unlockCreatures = { "PARASAUR", "TRICERATOPS", "DEINOCHEIRUS", "STEGOSAURUS" },
		description = "포획 확률 +4%\n파라사우롤로푸스, 트리케라톱스, 데이노키루스, 스테고사우루스 포획 해금",
	},
	{
		id = "TAMING_T4",
		name = "전문 포획",
		type = "PASSIVE",
		icon = "TAMING_TIER",
		reqLevel = 40,
		spCost = 4,
		prereqs = { "TAMING_T3" },
		effects = {
			{ stat = "TAMING_RATE_BONUS", value = 0.05 },
		},
		unlockCreatures = {},
		description = "포획 확률 +5%\n(추후 확장 패치 예정)",
	},
	{
		id = "TAMING_T5",
		name = "마스터 포획",
		type = "PASSIVE",
		icon = "TAMING_TIER",
		reqLevel = 50,
		spCost = 5,
		prereqs = { "TAMING_T4" },
		effects = {
			{ stat = "TAMING_RATE_BONUS", value = 0.06 },
		},
		unlockCreatures = {},
		description = "포획 확률 +6%\n(추후 확장 패치 예정)",
	},
}

--========================================
-- 유틸리티 함수
--========================================

--- 스킬 ID로 스킬 데이터 조회
function SkillTreeData.GetSkill(skillId: string)
	for _, treeId in ipairs({ "SWORD", "BOW", "AXE", "BUILD", "TAMING" }) do
		local tree = SkillTreeData[treeId]
		if tree then
			for _, skill in ipairs(tree) do
				if skill.id == skillId then
					return skill, treeId
				end
			end
		end
	end
	return nil, nil
end

--- 특정 트리의 전체 SP 비용 합산
function SkillTreeData.GetTreeTotalCost(treeId: string): number
	local tree = SkillTreeData[treeId]
	if not tree then return 0 end
	local total = 0
	for _, skill in ipairs(tree) do
		total = total + (skill.spCost or 0)
	end
	return total
end

--- 스킬 ID가 속한 트리 ID 반환
function SkillTreeData.GetTreeIdForSkill(skillId: string): string?
	for _, treeId in ipairs({ "SWORD", "BOW", "AXE", "BUILD", "TAMING" }) do
		local tree = SkillTreeData[treeId]
		if tree then
			for _, skill in ipairs(tree) do
				if skill.id == skillId then
					return treeId
				end
			end
		end
	end
	return nil
end

--- 트리가 전투 계열인지 확인
function SkillTreeData.IsCombatTree(treeId: string): boolean
	for _, tab in ipairs(SkillTreeData.TABS) do
		if tab.id == treeId then
			return tab.isCombat == true
		end
	end
	return false
end

--- 학습된 스킬 목록으로 포획 가능한 크리처 ID 집합 반환
function SkillTreeData.GetUnlockedCreatures(learnedSkills: {string}): {[string]: boolean}
	local set = {}
	for _, skillId in ipairs(learnedSkills) do
		for _, skill in ipairs(SkillTreeData.TAMING) do
			if skill.id == skillId and skill.unlockCreatures then
				for _, creatureId in ipairs(skill.unlockCreatures) do
					set[creatureId] = true
				end
			end
		end
	end
	return set
end

--- 학습된 스킬 목록으로 포획 확률 보너스 합산 반환
function SkillTreeData.GetTamingRateBonus(learnedSkills: {string}): number
	local bonus = 0
	for _, skillId in ipairs(learnedSkills) do
		for _, skill in ipairs(SkillTreeData.TAMING) do
			if skill.id == skillId and skill.effects then
				for _, eff in ipairs(skill.effects) do
					if eff.stat == "TAMING_RATE_BONUS" then
						bonus = bonus + eff.value
					end
				end
			end
		end
	end
	return bonus
end

return SkillTreeData
