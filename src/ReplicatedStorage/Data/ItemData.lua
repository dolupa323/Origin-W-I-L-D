-- ItemData.lua
-- 아이템 데이터 정의
-- 형태: 배열 { {id="...", ...}, ... }

local ItemData = {
	-- 기본 자원
	{
		id = "STONE",
		name = "돌",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "가장 기본적인 자원. 도구와 건물에 사용된다.",
		dropDespawn = "GATHER",
	},
	{
		id = "WOOD",
		name = "나무",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "기본 건축 재료.",
		dropDespawn = "GATHER",
		fuelValue = 15,  -- 연료 가치 (15초 가동)
	},
	{
		id = "FIBER",
		name = "섬유",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "풀에서 채집한 섬유. 밧줄과 천을 만들 수 있다.",		dropDespawn = "GATHER",	},
	{
		id = "FLINT",
		name = "부싯돌",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "날카로운 돌. 초기 도구 제작에 필수.",
		dropDespawn = "GATHER",
	},
	
	-- 기본 도구
	{
		id = "STONE_PICKAXE",
		name = "돌 곡괭이",
		type = "TOOL",
		rarity = "COMMON",
		maxStack = 1,
		durability = 100,
		description = "돌을 캘 수 있는 기본 도구.",
	},
	{
		id = "STONE_AXE",
		name = "돌 도끼",
		type = "TOOL",
		rarity = "COMMON",
		maxStack = 1,
		durability = 100,
		description = "나무를 벨 수 있는 기본 도구.",
	},
	
	-- 전투 드롭 아이템
	{
		id = "MEAT",
		name = "생고기",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "크리처에서 얻은 날고기. 조리해서 먹을 수 있다.",
	},
	{
		id = "LEATHER",
		name = "가죽",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "동물 가죽. 방어구 제작에 사용된다.",
	},
	{
		id = "FEATHER",
		name = "깃털",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "새의 깃털. 화살과 침낭 제작에 사용된다.",
	},
	{
		id = "HORN",
		name = "뿔",
		type = "RESOURCE",
		rarity = "RARE",
		maxStack = 50,
		description = "강력한 초식공룡의 뿔. 고급 장비 제작에 필수.",
	},
	
	-- Phase 5: 포획 도구
	{
		id = "CAPTURE_SPHERE_BASIC",
		name = "기본 포획구",
		type = "CONSUMABLE",
		rarity = "COMMON",
		maxStack = 20,
		description = "약해진 크리처를 포획할 수 있는 기본 도구.",
		captureMultiplier = 1.0,
	},
	{
		id = "CAPTURE_SPHERE_MEGA",
		name = "고급 포획구",
		type = "CONSUMABLE",
		rarity = "UNCOMMON",
		maxStack = 15,
		description = "더 높은 포획률을 가진 개량형 포획구.",
		captureMultiplier = 1.5,
	},
	{
		id = "CAPTURE_SPHERE_ULTRA",
		name = "마스터 포획구",
		type = "CONSUMABLE",
		rarity = "RARE",
		maxStack = 10,
		description = "최고급 포획구. 거의 확실한 포획이 가능.",
		captureMultiplier = 2.5,
	},
}

return ItemData
