-- MaterialAttributeData.lua
-- 재료 속성 시스템 데이터 정의
-- 모든 루팅 가능한 재료에 0~1개의 랜덤 속성을 부여
-- 부정 속성이 더 높은 확률로 등장
-- 속성 레벨: 드랍 대상(채집노드/크리처)의 level이 최대치

local MaterialAttributeData = {}

--========================================
-- 속성 정의 (카테고리별)
--========================================
-- positive = true: 긍정 속성 (낮은 확률)
-- positive = false: 부정 속성 (높은 확률)
-- weight: 가중치 (높을수록 자주 등장)
-- effect: 속성이 부여하는 효과 설명

MaterialAttributeData.Attributes = {
	-- 날 (Blade) 카테고리: 돌, 금속 재료
	BLADE = {
		{ id = "SHARP",        name = "날카로운",   positive = true,  weight = 8,  effect = "치명타 확률 증가" },
		{ id = "ROUNDED",      name = "둥근단면",   positive = false, weight = 15, effect = "치명타 확률 감소" },
		{ id = "POINTED",      name = "뾰족함",     positive = true,  weight = 8,  effect = "공격력 증가" },
		{ id = "BLUNT",        name = "뭉특함",     positive = false, weight = 15, effect = "공격력 감소" },
		{ id = "SOLID",        name = "속이 꽉참",  positive = true,  weight = 8,  effect = "내구도 증가" },
		{ id = "HOLLOW",       name = "속이 빔",    positive = false, weight = 15, effect = "내구도 감소" },
	},

	-- 자루 (Handle) 카테고리: 뼈, 나무, 이빨 재료
	HANDLE = {
		{ id = "LIGHT",        name = "가벼움",     positive = true,  weight = 8,  effect = "치명타 확률 증가" },
		{ id = "STURDY",       name = "단단함",     positive = true,  weight = 8,  effect = "공격력 증가" },
		{ id = "DENSE_H",      name = "치밀함",     positive = true,  weight = 8,  effect = "치명타 피해량 증가" },
		{ id = "HIGH_DENSITY", name = "높은 밀도",  positive = true,  weight = 8,  effect = "내구도 증가" },
		{ id = "SOFT",         name = "무름",       positive = false, weight = 15, effect = "공격력 감소" },
		{ id = "LOW_DENSITY",  name = "낮은 밀도",  positive = false, weight = 15, effect = "내구도 감소" },
	},

	-- 가죽 (Leather) 카테고리: 가죽, 깃털 류 (방어구용)
	LEATHER = {
		{ id = "L_HIGH_DENSITY", name = "높은밀도", positive = true,  weight = 6,  effect = "내구도 증가" },
		{ id = "L_LOW_DENSITY",  name = "낮은밀도", positive = false, weight = 12, effect = "내구도 감소" },
		{ id = "COOL",           name = "시원함",   positive = true,  weight = 6,  effect = "더위 내성" },
		{ id = "BREATHABLE",     name = "통기성",   positive = true,  weight = 6,  effect = "습기 내성" },
		{ id = "FLUFFY",         name = "푹신함",   positive = true,  weight = 6,  effect = "추위 내성" },
		{ id = "THICK",          name = "두꺼움",   positive = true,  weight = 6,  effect = "체력 증가" },
		{ id = "THIN",           name = "얇음",     positive = false, weight = 12, effect = "체력 감소" },
		{ id = "TIGHT_WEAVE",    name = "촘촘함",   positive = true,  weight = 6,  effect = "방어력 증가" },
		{ id = "LOOSE_WEAVE",    name = "엉성함",   positive = false, weight = 12, effect = "방어력 감소" },
	},
}

--========================================
-- 아이템 → 카테고리 매핑
--========================================
MaterialAttributeData.ItemCategory = {
	-- Blade 카테고리 (돌, 광석, 주괴, 부싯돌)
	STONE          = "BLADE",
	FLINT          = "BLADE",
	BRONZE_ORE     = "BLADE",
	IRON_ORE       = "BLADE",
	GOLD_ORE       = "BLADE",
	COAL           = "BLADE",
	BRONZE_INGOT   = "BLADE",
	IRON_INGOT     = "BLADE",
	SHARP_TOOTH    = "BLADE",
	HORN           = "BLADE",

	-- Handle 카테고리 (나무, 뼈)
	BRANCH         = "HANDLE",
	WOOD           = "HANDLE",
	LOG            = "HANDLE",
	PLANK          = "HANDLE",
	PALM_LOG       = "HANDLE",
	REED           = "HANDLE",
	SMALL_BONE     = "HANDLE",
	BONE           = "HANDLE",

	-- Leather 카테고리 (가죽, 깃털)
	LEATHER            = "LEATHER",
	TROPICAL_LEATHER   = "LEATHER",
	FEATHER            = "LEATHER",

	-- Blade 추가 (열대/사막 광석)
	OBSIDIAN       = "BLADE",
	BRONZE_ORE     = "BLADE",

	-- Handle 추가 (사막 나무/갈대)
	DESERT_LOG     = "HANDLE",
	DESERT_REED    = "HANDLE",

	-- 속성 미부여 (FIBER, RESIN, DURABLE_LEAF 등은 속성 없음)
	-- FIBER       = nil (매핑 없으면 속성 부여 안 됨)
	-- RESIN       = nil
	-- DURABLE_LEAF = nil
	-- MEAT        = nil (음식)
}

--========================================
-- 속성 부여 확률
--========================================
-- 아이템 드롭 시 속성이 붙을 확률 (카테고리에 매핑된 아이템만)
MaterialAttributeData.ATTRIBUTE_CHANCE = 0.65 -- 65% 확률로 속성 부여, 35%는 무속성

--========================================
-- 속성 롤링 함수
--========================================

--- 가중치 기반 랜덤 속성 선택
--- @param pool table 속성 풀 (Attributes[category])
--- @return table? 선택된 속성 {id, name, positive} 또는 nil
local function weightedRandom(pool: {any}): any?
	local totalWeight = 0
	for _, attr in ipairs(pool) do
		totalWeight = totalWeight + attr.weight
	end

	if totalWeight <= 0 then return nil end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, attr in ipairs(pool) do
		cumulative = cumulative + attr.weight
		if roll <= cumulative then
			return attr
		end
	end

	return pool[#pool] -- fallback (부동소수점 오차 방어)
end

-- [내부 함수] 속성 레벨 롤링 (공룡과 동일한 지수적 확률 감소 적용)
local function rollAttributeLevel(maxLevel: number)
	local maxLvl = math.max(1, maxLevel or 1)
	local current = 1
	
	-- 75% 확률로 레벨 +1 성공, 실패 시 중단
	local p = 0.75 
	
	while current < maxLvl and math.random() < p do
		current = current + 1
	end
	
	return current
end

--- 아이템에 속성 롤링
--- @param itemId string 아이템 ID
--- @param maxLevel number? 부여 가능한 최대 레벨 (드랍 대상의 level, 기본 1)
--- @return string? 속성 ID (nil이면 무속성), number? 레벨
function MaterialAttributeData.rollAttribute(itemId: string, maxLevel: number?): (string?, number?)
	local category = MaterialAttributeData.ItemCategory[itemId]
	if not category then
		return nil, nil
	end

	local pool = MaterialAttributeData.Attributes[category]
	if not pool or #pool == 0 then
		return nil, nil
	end

	-- 속성 부여 확률 체크
	if math.random() > MaterialAttributeData.ATTRIBUTE_CHANCE then
		return nil, nil
	end

	-- 가중치 기반 속성 선택
	local selected = weightedRandom(pool)
	if not selected then return nil, nil end

	-- [수정] 지수적 확률 감소 로직 적용하여 레벨 결정
	local level = rollAttributeLevel(maxLevel or 1)
	return selected.id, level
end

--- 속성 ID로 속성 정보 조회
--- @param attributeId string 속성 ID
--- @return table? {id, name, positive, weight, category}
function MaterialAttributeData.getAttribute(attributeId: string): any?
	for category, pool in pairs(MaterialAttributeData.Attributes) do
		for _, attr in ipairs(pool) do
			if attr.id == attributeId then
				return {
					id = attr.id,
					name = attr.name,
					positive = attr.positive,
					weight = attr.weight,
					effect = attr.effect,
					category = category,
				}
			end
		end
	end
	return nil
end

--- 아이템의 속성 카테고리 조회
--- @param itemId string 아이템 ID
--- @return string? 카테고리 ("BLADE" | "HANDLE" | "LEATHER" | nil)
function MaterialAttributeData.getCategory(itemId: string): string?
	return MaterialAttributeData.ItemCategory[itemId]
end

--========================================
-- 속성 효과 수치 계산
--========================================
-- 각 속성이 레벨에 비례하여 부여하는 수치 보너스
-- 반환값: { damageMult, critChance, critDamageMult, durabilityMult, harvestMult, maxHealthMult, defenseMult, heatResist, coldResist, humidResist }
-- 모든 값은 0이 기본 (보너스 없음), 양수=버프, 음수=디버프

local EFFECT_PER_LEVEL = {
	-- BLADE 카테고리
	SHARP        = { critChance = 0.03 },        -- 레벨당 치명타 확률 +3%
	ROUNDED      = { critChance = -0.02 },        -- 레벨당 치명타 확률 -2%
	POINTED      = { damageMult = 0.04 },         -- 레벨당 공격력 +4%
	BLUNT        = { damageMult = -0.03 },        -- 레벨당 공격력 -3%
	SOLID        = { durabilityMult = 0.05 },     -- 레벨당 내구도 +5%
	HOLLOW       = { durabilityMult = -0.04 },    -- 레벨당 내구도 -4%

	-- HANDLE 카테고리
	LIGHT        = { critChance = 0.03 },         -- 레벨당 치명타 확률 +3%
	STURDY       = { damageMult = 0.04 },         -- 레벨당 공격력 +4%
	DENSE_H      = { critDamageMult = 0.06 },     -- 레벨당 치명타 피해량 +6%
	HIGH_DENSITY = { durabilityMult = 0.05 },     -- 레벨당 내구도 +5%
	SOFT         = { damageMult = -0.03 },        -- 레벨당 공격력 -3%
	LOW_DENSITY  = { durabilityMult = -0.04 },    -- 레벨당 내구도 -4%

	-- LEATHER 카테고리
	L_HIGH_DENSITY = { durabilityMult = 0.05 },   -- 레벨당 내구도 +5%
	L_LOW_DENSITY  = { durabilityMult = -0.04 },  -- 레벨당 내구도 -4%
	COOL           = { heatResist = 0.05 },       -- 레벨당 더위 내성 +5%
	BREATHABLE     = { humidResist = 0.05 },      -- 레벨당 습기 내성 +5%
	FLUFFY         = { coldResist = 0.05 },       -- 레벨당 추위 내성 +5%
	THICK          = { maxHealthMult = 0.03 },    -- 레벨당 체력 +3%
	THIN           = { maxHealthMult = -0.02 },   -- 레벨당 체력 -2%
	TIGHT_WEAVE    = { defenseMult = 0.04 },      -- 레벨당 방어력 +4%
	LOOSE_WEAVE    = { defenseMult = -0.03 },     -- 레벨당 방어력 -3%
}

--- 속성 효과 수치를 레벨에 비례하여 계산
--- @param attributeId string 속성 ID (예: "SHARP", "LIGHT")
--- @param level number 속성 레벨 (1~)
--- @return table { damageMult, critChance, critDamageMult, durabilityMult, harvestMult, maxHealthMult, defenseMult, heatResist, coldResist, humidResist }
function MaterialAttributeData.getEffectValues(attributeId: string, level: number): any
	local result = {
		damageMult = 0,
		critChance = 0,
		critDamageMult = 0,
		durabilityMult = 0,
		harvestMult = 0,
		maxHealthMult = 0,
		defenseMult = 0,
		heatResist = 0,
		coldResist = 0,
		humidResist = 0,
	}

	if not attributeId or not level or level <= 0 then
		return result
	end

	local perLevel = EFFECT_PER_LEVEL[attributeId]
	if not perLevel then
		return result
	end

	for key, value in pairs(perLevel) do
		result[key] = value * level
	end

	return result
end

return MaterialAttributeData
