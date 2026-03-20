-- TechUnlockData.lua
-- 상세 기술 해금 데이터 정의
-- 4단계 시대를 유지하되, 레벨 제한 시스템을 철거하고, 기술 연구소(TechLab)에서 아이템을 지불하여 해금하도록 변경함.

local TechUnlockData = {
	--========================================
	-- 🪨 1단계: 원시 시대 (기초 기술)
	--========================================
	{
		id = "TECH_BASICS",
		name = "기초 생존 및 건축",
		cost = {},
		prerequisites = {},
		unlocks = { 
			recipes = { 
				"CRAFT_CRUDE_STONE_PICKAXE", "CRAFT_CRUDE_STONE_AXE", 
				"CRAFT_CRUDE_WOODEN_SPEAR", "CRAFT_TORCH",
				"CRAFT_SPLIT_LOG_TO_PLANK", "CRAFT_FIRM_STONE_AXE", "CRAFT_FIRM_STONE_PICKAXE"
			}, 
			facilities = { 
				"CAMPFIRE", "BASIC_WORKBENCH", "STORAGE_BOX",
				"WOODEN_FOUNDATION", "WOODEN_WALL", "WOODEN_ROOF", "WOODEN_DOOR"
			} 
		},
		category = "SURVIVAL",
		description = "맨손으로 재료를 모아 기초 도구와 모닥불, 그리고 기본적인 나무 가옥을 건설합니다. (기본 지급)",
	},
	{
		id = "TECH_SETTLEMENT",
		name = "부락의 발전",
		cost = { { itemId = "LOG", amount = 10 }, { itemId = "SMALL_STONE", amount = 10 } },
		prerequisites = { "TECH_BASICS" },
		unlocks = { recipes = {}, facilities = { "CAMP_TOTEM" } },
		category = "SETTLEMENT",
		description = "본격적인 정착을 위해 거점 영역을 확보합니다.",
	},
	{
		id = "TECH_CLOTHES",
		name = "기초 방어구",
		cost = { { itemId = "FIBER", amount = 20 }, { itemId = "DURABLE_LEAF", amount = 10 } },
		prerequisites = { "TECH_SETTLEMENT" },
		unlocks = { recipes = { "CRAFT_LEATHER_ARMOR", "CRAFT_FEATHER_HELMET" }, facilities = {} },
		category = "SURVIVAL",
		description = "작업대에서 깃털 투구와 가죽옷까지 제작 가능한 방어구 체계를 해금합니다.",
	},
	{
		id = "TECH_HUNTING",
		name = "본격 수렵",
		cost = { { itemId = "SHARP_TOOTH", amount = 2 }, { itemId = "FIBER", amount = 20 } },
		prerequisites = { "TECH_SETTLEMENT" },
		unlocks = { recipes = { "CRAFT_BONE_SPEAR" }, facilities = {} },
		category = "WEAPONS",
		description = "야수들의 부산물을 연마하여 강력한 뼈 창을 제작합니다.",
	},
	{
		id = "TECH_BOW",
		name = "나무 활",
		cost = { { itemId = "LOG", amount = 15 }, { itemId = "FIBER", amount = 40 }, { itemId = "DODO_FEATHER", amount = 5 } },
		prerequisites = { "TECH_HUNTING" },
		unlocks = { recipes = { "CRAFT_WOODEN_BOW", "CRAFT_STONE_ARROW" }, facilities = {} },
		category = "WEAPONS",
		description = "나무로 만든 활과 돌 화살로 멀리 떨어진 적을 제압합니다.",
	},

	--========================================
	-- 🏚️ 2단계: 나무 건축 시대 (Wood Build)
	--========================================
	{
		id = "TECH_WOOD_BUILD",
		name = "나무 건축 숙련",
		cost = { { itemId = "PLANK", amount = 20 }, { itemId = "FIBER", amount = 15 } },
		prerequisites = { "TECH_SETTLEMENT" },
		unlocks = { recipes = {}, facilities = {} },
		category = "SETTLEMENT",
		description = "나무 건축 기술을 숙련하여 더 발전된 시설을 건설할 수 있는 기반을 마련합니다.",
	},

	{
		id = "TECH_FARMING",
		name = "농경 기술",
		cost = { { itemId = "STONE", amount = 30 }, { itemId = "WOOD", amount = 20 } },
		prerequisites = { "TECH_WOOD_BUILD" },
		unlocks = { recipes = { "CRAFT_STONE_HOE" }, facilities = { "BERRY_PLANTATION", "BEAST_FEEDING_TROUGH" } },
		category = "SURVIVAL",
		description = "땅을 일구어 베리 농장을 건설하고 먹이통을 마련합니다.",
	},

	--========================================
	-- 🥉 3단계: 청동기 시대 (Bronze Age)
	--========================================
	{
		id = "TECH_FURNACE1",
		name = "돌 용광로",
		cost = { { itemId = "STONE", amount = 50 }, { itemId = "LOG", amount = 20 } },
		prerequisites = { "TECH_WOOD_BUILD" },
		unlocks = { recipes = {}, facilities = { "STONE_FURNACE" } },
		category = "FACILITIES",
		description = "돌로 만든 용광로를 통해 광석으로부터 주괴를 추출하기 시작합니다.",
	},
	{
		id = "TECH_BRONZE_SMELT",
		name = "청동 제련",
		cost = { { itemId = "STONE", amount = 20 }, { itemId = "COMPY_DNA", amount = 5 } },
		prerequisites = { "TECH_FURNACE1" },
		unlocks = { recipes = { "SMELT_BRONZE_INGOT" }, facilities = {} },
		category = "FACILITIES",
		description = "구리와 주석을 배합하여 더욱 단단한 청동 주괴를 제련합니다.",
	},
	{
		id = "TECH_WORKBENCH2",
		name = "청동기 작업대",
		cost = { { itemId = "LOG", amount = 30 }, { itemId = "BRONZE_INGOT", amount = 10 } },
		prerequisites = { "TECH_BRONZE_SMELT" },
		unlocks = { recipes = {}, facilities = { "BRONZE_WORKBENCH" } },
		category = "FACILITIES",
		description = "청동기 시대를 위한 전용 작업대를 건설해 상위 장비를 제작합니다.",
	},
	{
		id = "TECH_BRONZE_TOOLS",
		name = "청동 도구",
		cost = { { itemId = "BRONZE_INGOT", amount = 15 } },
		prerequisites = { "TECH_WORKBENCH2" },
		unlocks = { recipes = { "CRAFT_BRONZE_PICKAXE", "CRAFT_BRONZE_AXE" }, facilities = {} },
		category = "TOOLS",
		description = "청동의 강도를 활용해 더욱 빠른 채집이 가능한 도구를 제작합니다.",
	},
	{
		id = "TECH_BRONZE_WEAPONS",
		name = "청동 무기 및 갑옷",
		cost = { { itemId = "BRONZE_INGOT", amount = 30 }, { itemId = "LEATHER", amount = 20 } },
		prerequisites = { "TECH_BRONZE_TOOLS", "TECH_BOW" },
		unlocks = { recipes = { "CRAFT_BRONZE_SPEAR", "CRAFT_BRONZE_BOW", "CRAFT_BRONZE_ARROW", "CRAFT_BRONZE_ARMOR" }, facilities = {} },
		category = "WEAPONS",
		description = "청동 무기와 갑옷을 갖춰 더욱 치명적인 위협에 대비합니다.",
	},
	{
		id = "TECH_LARGE_BOX",
		name = "대형 보관함",
		cost = { { itemId = "WOOD", amount = 50 }, { itemId = "STONE", amount = 50 } },
		prerequisites = { "TECH_WOOD_BUILD" },
		unlocks = { recipes = {}, facilities = { "LARGE_STORAGE_BOX" } },
		category = "SETTLEMENT",
		description = "훨씬 더 많은 자원을 안전하게 보관할 수 있는 대형 상자를 설치합니다.",
	},

	--========================================
	-- ⚔️ 4단계: 철기 시대 (Iron Age)
	--========================================
	{
		id = "TECH_FURNACE2",
		name = "철 용광로",
		cost = { { itemId = "STONE", amount = 100 }, { itemId = "BRONZE_INGOT", amount = 20 } },
		prerequisites = { "TECH_BRONZE_SMELT" },
		unlocks = { recipes = { "SMELT_IRON_INGOT" }, facilities = { "IRON_FURNACE" } },
		category = "FACILITIES",
		description = "고열을 견디는 철 용광로에서 순도 높은 철 주괴를 생산합니다.",
	},
	{
		id = "TECH_STONE_BUILD",
		name = "석조 건축",
		cost = { { itemId = "STONE", amount = 200 }, { itemId = "IRON_INGOT", amount = 10 } },
		prerequisites = { "TECH_FURNACE2", "TECH_WOOD_BUILD" },
		unlocks = { recipes = {}, facilities = { "STONE_FOUNDATION", "STONE_WALL", "STONE_ROOF" } },
		category = "SETTLEMENT",
		description = "돌을 깎아 만든 견고한 벽과 천장으로 습격으로부터 완벽히 보호받습니다.",
	},
	{
		id = "TECH_WORKBENCH3",
		name = "철기 작업대",
		cost = { { itemId = "IRON_INGOT", amount = 30 }, { itemId = "STONE", amount = 50 } },
		prerequisites = { "TECH_FURNACE2", "TECH_WORKBENCH2" },
		unlocks = { recipes = {}, facilities = { "IRON_WORKBENCH" } },
		category = "FACILITIES",
		description = "철기 문명을 위한 정밀 작업대에서 최고 수준의 장비를 제작합니다.",
	},
	{
		id = "TECH_IRON_TOOLS",
		name = "철제 도구 및 무기",
		cost = { { itemId = "IRON_INGOT", amount = 50 } },
		prerequisites = { "TECH_WORKBENCH3" },
		unlocks = { recipes = { "CRAFT_IRON_PICKAXE", "CRAFT_IRON_AXE", "CRAFT_IRON_SPEAR", "CRAFT_CROSSBOW", "CRAFT_IRON_BOLT", "CRAFT_IRON_ARMOR" }, facilities = {} },
		category = "WEAPONS",
		description = "강철 수준의 장비를 개발하여 최고 수준의 적을 제압합니다.",
	},
}

return TechUnlockData
