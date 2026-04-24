-- PalTraitData.lua
-- 팰 개체 속성(특성) 시스템 데이터 정의
-- 포획/길들이기 시 크리처 레벨만큼의 랜덤 속성 부여 (1 ~ level개)
-- 각 카테고리에서 긍정 또는 부정 속성이 선택됨

local PalTraitData = {}

--========================================
-- 속성 정의 (카테고리별)
--========================================
-- positive = true: 긍정 속성 (능력치 상승)
-- positive = false: 부정 속성 (능력치 하락)
-- stat: 영향받는 스탯 키
-- perLevel: 레벨당 효과 값 (%, 고정값 등)
-- icon: UI 표시용 이모지

PalTraitData.Traits = {
	-- 공격 카테고리
	-- 공격 카테고리
	-- 공격 카테고리
	ATTACK = {
		{ id = "BOLD",    name = "과감함", positive = true,  weight = 10, stat = "attack",  perLevel = 0.02, effect = "공격력 증가" },
		{ id = "TIMID",   name = "소심함", positive = false, weight = 12, stat = "attack",  perLevel = 0.015, effect = "공격력 감소" },
	},
	-- 방어 카테고리
	DEFENSE = {
		{ id = "CAREFUL",  name = "신중함", positive = true,  weight = 10, stat = "defense", perLevel = 0.02, effect = "방어력 증가" },
		{ id = "RECKLESS", name = "경솔함", positive = false, weight = 12, stat = "defense", perLevel = 0.015, effect = "방어력 감소" },
	},
	-- 속도 카테고리
	SPEED = {
		{ id = "AGILE",    name = "민첩함", positive = true,  weight = 10, stat = "speed",   perLevel = 0.02, effect = "이동속도 증가" },
		{ id = "SLUGGISH", name = "둔감함", positive = false, weight = 12, stat = "speed",   perLevel = 0.015, effect = "이동속도 감소" },
	},
	-- 생명 카테고리
	HEALTH = {
		{ id = "HARDY",  name = "강인함", positive = true,  weight = 10, stat = "hp",      perLevel = 0.02, effect = "생명력 증가" },
		{ id = "FRAIL",  name = "나약함", positive = false, weight = 12, stat = "hp",      perLevel = 0.015, effect = "생명력 감소" },
	},
}

-- [내부 함수] 특성 레벨 롤링 (지수적 확률 감소 적용)
local function rollTraitLevel(creatureLevel: number)
	local maxLvl = math.max(1, creatureLevel)
	local current = 1
	
	-- [핵심] 레벨이 올라갈수록 성공 확률이 비례하여 줄어드는 모델
	-- 75% 확률로 레벨 +1 성공, 실패 시 중단
	-- 레벨 50 도달 확률: (0.75)^49 = 약 0.00007%
	local p = 0.75 
	
	while current < maxLvl and math.random() < p do
		current = current + 1
	end
	
	return current
end

-- stat 한글 매핑 (UI 표시용)
PalTraitData.StatNames = {
	attack = "공격",
	defense = "방어",
	speed = "속도",
	hp = "생명",
}

-- 카테고리 순서 (UI 표시용)
PalTraitData.CategoryOrder = { "ATTACK", "DEFENSE", "SPEED", "HEALTH" }

-- 카테고리 표시 이름
PalTraitData.CategoryNames = {
	ATTACK = "공격",
	DEFENSE = "방어",
	SPEED = "속도",
	HEALTH = "생명",
}

--========================================
-- 속성 롤링 (포획/길들이기 시 호출)
--========================================

--- 가중치 기반 랜덤 선택 (카테고리 내에서 하나 선택)
local function weightedPick(traitList)
	local totalWeight = 0
	for _, t in ipairs(traitList) do
		totalWeight = totalWeight + t.weight
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, t in ipairs(traitList) do
		cumulative = cumulative + t.weight
		if roll <= cumulative then
			return t
		end
	end
	return traitList[#traitList]
end

--- 크리처 레벨 기반 랜덤 속성 생성
--- @param creatureLevel number 크리처 레벨 (최대 속성 개수)
--- @return table traits 배열 { { id, name, positive, stat, level, icon, category }, ... }
function PalTraitData.RollTraits(creatureLevel: number)
	local level = math.max(1, creatureLevel or 1)
	-- 속성 개수: 1 ~ level/10 + 1 (최대 4개)
	local traitCount = math.random(1, math.max(1, math.floor(level / 10) + 1))
	traitCount = math.min(traitCount, 4)

	-- 카테고리 셔플 → 중복 카테고리 방지
	local categories = {}
	for _, cat in ipairs(PalTraitData.CategoryOrder) do
		table.insert(categories, cat)
	end
	-- Fisher-Yates 셔플
	for i = #categories, 2, -1 do
		local j = math.random(1, i)
		categories[i], categories[j] = categories[j], categories[i]
	end

	local traits = {}
	for i = 1, traitCount do
		local category = categories[i]
		local traitList = PalTraitData.Traits[category]
		if traitList then
			local picked = weightedPick(traitList)
			-- [수정] 편중된 확률로 레벨 결정
			local traitLevel = rollTraitLevel(level)
			table.insert(traits, {
				id = picked.id,
				name = picked.name,
				positive = picked.positive,
				stat = picked.stat,
				level = traitLevel,
				category = category,
				perLevel = picked.perLevel,
			})
		end
	end

	return traits
end

--========================================
-- 속성 기반 스탯 보정값 계산
--========================================

--- traits 배열에서 특정 스탯의 총 배율 계산
--- @param traits table 속성 배열
--- @param statKey string "attack" | "defense" | "speed" | "hp"
--- @return number multiplier 1.0 기준 배율 (예: 1.16 = +16%, 0.88 = -12%)
function PalTraitData.GetStatMultiplier(traits, statKey: string): number
	if not traits then return 1.0 end
	local mult = 1.0
	for _, trait in ipairs(traits) do
		if trait.stat == statKey then
			local delta = (trait.perLevel or 0.08) * (trait.level or 1)
			if trait.positive then
				mult = mult + delta
			else
				mult = mult - delta
			end
		end
	end
	return math.max(0.1, mult) -- 최소 10%
end

--- 모든 스탯 배율을 한번에 계산
--- @param traits table 속성 배열
--- @return table { attack=1.16, defense=0.94, speed=1.08, hp=1.0 }
function PalTraitData.GetAllMultipliers(traits)
	return {
		attack = PalTraitData.GetStatMultiplier(traits, "attack"),
		defense = PalTraitData.GetStatMultiplier(traits, "defense"),
		speed = PalTraitData.GetStatMultiplier(traits, "speed"),
		hp = PalTraitData.GetStatMultiplier(traits, "hp"),
	}
end

--========================================
-- ID로 속성 정보 조회
--========================================

function PalTraitData.GetTraitById(traitId: string)
	for _, category in pairs(PalTraitData.Traits) do
		for _, trait in ipairs(category) do
			if trait.id == traitId then
				return trait
			end
		end
	end
	return nil
end

return PalTraitData
