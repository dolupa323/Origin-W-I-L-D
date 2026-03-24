-- MaterialAttributeData.lua
-- 재료 속성 시스템 데이터 정의
-- 모든 루팅 가능한 재료에 0~1개의 랜덤 속성을 부여
-- 부정 속성이 더 높은 확률로 등장

local MaterialAttributeData = {}

--========================================
-- 속성 정의 (카테고리별)
--========================================
-- positive = true: 긍정 속성 (낮은 확률)
-- positive = false: 부정 속성 (높은 확률)
-- weight: 가중치 (높을수록 자주 등장)

MaterialAttributeData.Attributes = {
	-- 날 (Blade) 카테고리: 돌, 광석, 주괴 등
	BLADE = {
		{ id = "SHARP",        name = "날카로운",   positive = true,  weight = 8  },
		{ id = "ROUNDED",      name = "둥근단면",   positive = false, weight = 15 },
		{ id = "POINTED",      name = "뾰족함",     positive = true,  weight = 8  },
		{ id = "BLUNT",        name = "뭉특함",     positive = false, weight = 15 },
		{ id = "SOLID",        name = "속이꽉참",   positive = true,  weight = 8  },
		{ id = "HOLLOW",       name = "속이빔",     positive = false, weight = 15 },
	},

	-- 자루 (Handle) 카테고리: 나뭇가지, 통나무, 판자, 뼈 등
	HANDLE = {
		{ id = "LIGHT",        name = "가벼움",     positive = true,  weight = 8  },
		{ id = "STURDY",       name = "단단함",     positive = true,  weight = 8  },
		{ id = "DENSE",        name = "치밀함",     positive = true,  weight = 8  },
		{ id = "HIGH_DENSITY", name = "높은밀도",   positive = false, weight = 15 },
		{ id = "SOFT",         name = "무름",       positive = false, weight = 15 },
		{ id = "LOW_DENSITY",  name = "낮은밀도",   positive = false, weight = 15 },
	},

	-- 가죽 (Leather) 카테고리: 가죽, 깃털 등
	LEATHER = {
		{ id = "L_HIGH_DENSITY", name = "높은밀도", positive = true,  weight = 6  },
		{ id = "L_LOW_DENSITY",  name = "낮은밀도", positive = false, weight = 12 },
		{ id = "COOL",           name = "시원함",   positive = true,  weight = 6  },
		{ id = "BREATHABLE",     name = "통기성",   positive = true,  weight = 6  },
		{ id = "FLUFFY",         name = "푹신함",   positive = true,  weight = 6  },
		{ id = "THICK",          name = "두꺼움",   positive = false, weight = 12 },
		{ id = "THIN",           name = "얇음",     positive = false, weight = 12 },
		{ id = "TIGHT_WEAVE",    name = "촘촘함",   positive = true,  weight = 6  },
		{ id = "LOOSE_WEAVE",    name = "엉성함",   positive = false, weight = 12 },
	},
}

--========================================
-- 아이템 → 카테고리 매핑
--========================================
MaterialAttributeData.ItemCategory = {
	-- Blade 카테고리 (돌, 광석, 주괴, 부싯돌)
	SMALL_STONE    = "BLADE",
	STONE          = "BLADE",
	FLINT          = "BLADE",
	COPPER_ORE     = "BLADE",
	TIN_ORE        = "BLADE",
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
	SMALL_BONE     = "HANDLE",
	BONE           = "HANDLE",

	-- Leather 카테고리 (가죽, 깃털)
	LEATHER        = "LEATHER",
	DODO_FEATHER   = "LEATHER",

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

--- 아이템에 속성 롤링
--- @param itemId string 아이템 ID
--- @return string? 속성 ID (nil이면 무속성), number? 레벨 (1~3)
function MaterialAttributeData.rollAttribute(itemId: string): (string?, number?)
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

	return selected.id, 1
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

return MaterialAttributeData
