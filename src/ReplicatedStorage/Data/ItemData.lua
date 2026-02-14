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
}

return ItemData
