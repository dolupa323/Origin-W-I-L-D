-- ItemData.lua
-- 아이템 데이터 정의
-- 형태: 배열 { {id="...", ...}, ... }

local ItemData = {
	--========================================
	-- 기초 자원 (Tier 0-1)
	--========================================
	{
		id = "STONE",
		name = "돌",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		weight = 1.0,
		icon = "rbxassetid://15573752528", -- Stone icon
		description = "가장 기본적인 자원. 도구와 건물에 사용된다.",
		dropDespawn = "GATHER",
	},
	{
		id = "WOOD",
		name = "나무",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		weight = 1.0, -- 추가
		description = "기본 건축 재료.",
		dropDespawn = "GATHER",
		fuelValue = 15,
	},
	{
		id = "FIBER",
		name = "섬유",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		weight = 0.5, -- 추가
		description = "풀에서 채집한 섬유. 밧줄과 천을 만들 수 있다.",
		dropDespawn = "GATHER",
	},
	{
		id = "BERRY",
		name = "베리",
		type = "FOOD",
		rarity = "COMMON",
		maxStack = 99,
		weight = 0.1, -- 추가
		description = "덤불에서 채집한 베리. 먹으면 체력이 조금 회복된다.",
		dropDespawn = "GATHER",
		foodValue = 5,
	},
	{
		id = "RESIN",
		name = "수지",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "나무에서 나오는 끈적한 수지. 접착제로 사용된다.",
		dropDespawn = "GATHER",
	},
	
	--========================================
	-- 광석 및 주괴 (Tier 3-4)
	--========================================
	{
		id = "COPPER_ORE",
		name = "구리 광석",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "구리를 추출할 수 있는 광석.",
		dropDespawn = "GATHER",
	},
	{
		id = "TIN_ORE",
		name = "주석 광석",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "주석을 추출할 수 있는 광석.",
		dropDespawn = "GATHER",
	},
	{
		id = "IRON_ORE",
		name = "철광석",
		type = "RESOURCE",
		rarity = "UNCOMMON",
		maxStack = 99,
		description = "철을 추출할 수 있는 광석.",
		dropDespawn = "GATHER",
	},
	{
		id = "COAL",
		name = "석탄",
		type = "RESOURCE",
		rarity = "COMMON",
		maxStack = 99,
		description = "검은 광석. 연료와 제련에 사용된다.",
		dropDespawn = "GATHER",
		fuelValue = 30,
	},
	{
		id = "BRONZE_INGOT",
		name = "청동 주괴",
		type = "RESOURCE",
		rarity = "UNCOMMON",
		maxStack = 99,
		description = "구리와 주석을 제련하여 만든 합금 주괴.",
		dropDespawn = "GATHER",
	},
	{
		id = "IRON_INGOT",
		name = "철 주괴",
		type = "RESOURCE",
		rarity = "RARE",
		maxStack = 99,
		description = "철광석을 제련하여 만든 단단한 주괴.",
		dropDespawn = "GATHER",
	},
	{
		id = "GOLD_ORE",
		name = "금광석",
		type = "RESOURCE",
		rarity = "RARE",
		maxStack = 50,
		description = "희귀한 금이 포함된 광석.",
		dropDespawn = "GATHER",
	},

	--========================================
	-- 1단계 도구 및 무기 (원시 시대)
	--========================================
	{
		id = "STONE_PICKAXE",
		name = "돌 곡괭이",
		type = "TOOL",
		rarity = "COMMON",
		maxStack = 1,
		weight = 5.0, -- 추가
		durability = 100,
		damage = 8,
		description = "돌을 캘 수 있는 기본 도구.",
		optimalTool = "PICKAXE",
	},
	{
		id = "STONE_AXE",
		name = "돌 도끼",
		type = "TOOL",
		rarity = "COMMON",
		maxStack = 1,
		durability = 100,
		damage = 8,
		description = "나무를 벨 수 있는 기본 도구.",
		optimalTool = "AXE",
	},
	{
		id = "STONE_SPEAR",
		name = "돌 창",
		type = "WEAPON",
		rarity = "COMMON",
		maxStack = 1,
		durability = 100,
		damage = 25,
		description = "기초 근접 무기.",
		optimalTool = "SPEAR",
	},
	{
		id = "TORCH",
		name = "횃불",
		type = "TOOL",
		rarity = "COMMON",
		maxStack = 1,
		durability = 60,
		damage = 5,
		description = "시야 확보 및 체온 유지.",
	},
	{
		id = "WOODEN_CLUB",
		name = "나무 몽둥이",
		type = "WEAPON",
		rarity = "COMMON",
		maxStack = 1,
		durability = 120,
		damage = 15,
		isBlunt = true,  -- 기절 수치 적용용
		description = "야수를 때려서 기절시키거나 체력을 깎는 둔기.",
		optimalTool = "CLUB",
	},
	{
		id = "VINE_BOLA",
		name = "넝쿨 볼라",
		type = "CONSUMABLE",
		rarity = "COMMON",
		maxStack = 10,
		description = "소형 크리처에게 던져 묶고 길들이는 기초 투척 도구.",
		captureMultiplier = 1.0,
		tier = 1,
		optimalTool = "BOLA",
	},

	--========================================
	-- 2단계 도구 및 무기 (목조 시대)
	--========================================
	{
		id = "WOODEN_BOW",
		name = "나무 활",
		type = "WEAPON",
		rarity = "COMMON",
		maxStack = 1,
		durability = 150,
		damage = 40,
		description = "원거리 공격이 가능한 기초적인 활.",
	},
	{
		id = "STONE_ARROW",
		name = "돌 화살",
		type = "AMMO",
		rarity = "COMMON",
		maxStack = 100,
		description = "나무 활 전용 기초 화살.",
	},
	{
		id = "STONE_HOE",
		name = "돌 괭이",
		type = "TOOL",
		rarity = "COMMON",
		maxStack = 1,
		durability = 100,
		damage = 5,
		description = "농경지 개간용 기초 도구.",
	},
	{
		id = "BONE_BOLA",
		name = "뼈 볼라",
		type = "CONSUMABLE",
		rarity = "UNCOMMON",
		maxStack = 10,
		description = "포획 확률을 높인 강화된 투척 도구.",
		captureMultiplier = 1.5,
		tier = 2,
		optimalTool = "BOLA",
	},

	--========================================
	-- 3단계 도구 및 무기 (청동기 시대)
	--========================================
	{
		id = "BRONZE_PICKAXE",
		name = "청동 곡괭이",
		type = "TOOL",
		rarity = "UNCOMMON",
		maxStack = 1,
		durability = 250,
		damage = 25,
		description = "더 단단한 광석을 캘 수 있는 청동 곡괭이.",
		optimalTool = "PICKAXE",
	},
	{
		id = "BRONZE_AXE",
		name = "청동 도끼",
		type = "TOOL",
		rarity = "UNCOMMON",
		maxStack = 1,
		durability = 250,
		damage = 25,
		description = "벌목 속도가 향상된 청동 도끼.",
		optimalTool = "AXE",
	},
	{
		id = "BRONZE_SPEAR",
		name = "청동 창",
		type = "WEAPON",
		rarity = "UNCOMMON",
		maxStack = 1,
		durability = 250,
		damage = 75,
		description = "공격력이 향상된 청동 창.",
	},
	{
		id = "BRONZE_BOW",
		name = "청동 활",
		type = "WEAPON",
		rarity = "UNCOMMON",
		maxStack = 1,
		durability = 300,
		damage = 90,
		description = "안정적인 사격이 가능한 청동 활.",
	},
	{
		id = "BRONZE_ARROW",
		name = "청동 화살",
		type = "AMMO",
		rarity = "UNCOMMON",
		maxStack = 100,
		description = "높은 관통력을 가진 청동 화살.",
	},
	{
		id = "BRONZE_BOLA",
		name = "청동 볼라",
		type = "CONSUMABLE",
		rarity = "RARE",
		maxStack = 10,
		description = "중형 공룡을 제압하는 강력한 투척 도구.",
		captureMultiplier = 2.0,
		tier = 3,
		optimalTool = "BOLA",
	},

	--========================================
	-- 4단계 도구 및 무기 (철기 시대)
	--========================================
	{
		id = "IRON_PICKAXE",
		name = "철 곡괭이",
		type = "TOOL",
		rarity = "RARE",
		maxStack = 1,
		durability = 500,
		damage = 50,
		description = "모든 광석을 캘 수 있는 가장 강력한 곡괭이.",
		optimalTool = "PICKAXE",
	},
	{
		id = "IRON_AXE",
		name = "철 도끼",
		type = "TOOL",
		rarity = "RARE",
		maxStack = 1,
		durability = 500,
		damage = 50,
		description = "최고의 벌목 성능을 자랑하는 철 도끼.",
		optimalTool = "AXE",
	},
	{
		id = "IRON_SPEAR",
		name = "철 창",
		type = "WEAPON",
		rarity = "RARE",
		maxStack = 1,
		durability = 500,
		damage = 130,
		description = "가장 강력한 위력을 가진 철 창.",
	},
	{
		id = "CROSSBOW",
		name = "석궁",
		type = "WEAPON",
		rarity = "RARE",
		maxStack = 1,
		durability = 400,
		damage = 180,
		description = "파괴력이 높고 조준이 쉬운 기계식 무기.",
	},
	{
		id = "IRON_BOLT",
		name = "철제 볼트",
		type = "AMMO",
		rarity = "RARE",
		maxStack = 100,
		description = "석궁 전용 강력한 탄약.",
	},
	{
		id = "IRON_BOLA",
		name = "철제 볼라",
		type = "CONSUMABLE",
		rarity = "EPIC",
		maxStack = 10,
		description = "대형 포식자 공룡을 포획하기 위한 최강의 도구.",
		captureMultiplier = 3.5,
		optimalTool = "BOLA",
	},

	--========================================
	-- 드롭/기타 자원
	--========================================
	{
		id = "MEAT", name = "생고기", type = "RESOURCE", rarity = "COMMON", maxStack = 99,
		description = "조리해서 먹을 수 있다.",
	},
	{
		id = "LEATHER", name = "가죽", type = "RESOURCE", rarity = "COMMON", maxStack = 99,
		description = "방어구 제작에 사용된다.",
	},
	{
		id = "BONE", name = "뼈", type = "RESOURCE", rarity = "COMMON", maxStack = 99,
		description = "강화된 도구와 볼라 제작에 사용된다.",
	},
	{
		id = "HORN", name = "뿔", type = "RESOURCE", rarity = "UNCOMMON", maxStack = 99,
		description = "강력한 크리처의 뿔. 고급 장비 제작에 사용된다.",
	},
}

return ItemData
