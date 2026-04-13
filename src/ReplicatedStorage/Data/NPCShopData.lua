-- NPCShopData.lua
-- NPC 상점 데이터 정의 (Phase 9)
-- 4단계 아이템 체계 반영 및 오타 수정

local NPCShopData = {}

--========================================
-- 잡화점 (General Store)
--========================================
NPCShopData.GENERAL_STORE = {
	id = "GENERAL_STORE",
	name = "잡화점",
	description = "기본 물품을 판매하는 상점입니다.",
	npcName = "상인 톰",
	
	-- 판매 상품 (플레이어가 구매 가능)
	buyList = {
		{ itemId = "WOOD", price = 5, stock = -1 },
		{ itemId = "STONE", price = 3, stock = -1 },
		{ itemId = "FIBER", price = 2, stock = -1 },
		{ itemId = "TORCH", price = 15, stock = 50 },
		{ itemId = "RESIN", price = 10, stock = -1 },
	},
	
	
	-- 특수 구매 목록 (플레이어가 상점에 팔 수 있는 아이템)
	sellList = {
		{ itemId = "WOOD", price = 2 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "FIBER", price = 1 },
		{ itemId = "MEAT", price = 8 },       -- RAW_MEAT -> MEAT 수정
		{ itemId = "LEATHER", price = 15 },
		{ itemId = "BONE", price = 10 },
		{ itemId = "HORN", price = 25 },
	},
}

--========================================
-- 도구점 (Tool Shop)
--========================================
NPCShopData.TOOL_SHOP = {
	id = "TOOL_SHOP",
	name = "도구점",
	description = "각종 도구와 무기를 판매합니다.",
	npcName = "대장장이 한스",
	
	buyList = {
		{ itemId = "FIRM_STONE_PICKAXE", price = 50, stock = -1 },
		{ itemId = "FIRM_STONE_AXE", price = 50, stock = -1 },
		{ itemId = "WOODEN_CLUB", price = 40, stock = -1 },
		{ itemId = "BRONZE_PICKAXE", price = 250, stock = 10 },
		{ itemId = "BRONZE_AXE", price = 250, stock = 10 },
	},
	

	sellList = {
		{ itemId = "FIRM_STONE_PICKAXE", price = 15 },
		{ itemId = "FIRM_STONE_AXE", price = 15 },
		{ itemId = "BRONZE_PICKAXE", price = 75 },
		{ itemId = "IRON_PICKAXE", price = 200 },
	},
}


--========================================
-- 식료품점 (Food Shop)
--========================================
NPCShopData.FOOD_SHOP = {
	id = "FOOD_SHOP",
	name = "식료품점",
	description = "음식과 물약을 판매합니다.",
	npcName = "요리사 루시",
	
	buyList = {
		{ itemId = "BERRY", price = 5, stock = -1 },
	},
	

	sellList = {
		{ itemId = "MEAT", price = 10 },
		{ itemId = "BERRY", price = 2 },
	},
}

--========================================
-- 건축 상점 (Building Shop)
--========================================
NPCShopData.BUILDING_SHOP = {
	id = "BUILDING_SHOP",
	name = "건축 상점",
	description = "건축 재료와 설계도를 판매합니다.",
	npcName = "건축가 벤",
	
	buyList = {
		{ itemId = "WOOD", price = 4, stock = -1 },
		{ itemId = "STONE", price = 2, stock = -1 },
		{ itemId = "FIBER", price = 2, stock = -1 },
	},
	

	sellList = {
		{ itemId = "WOOD", price = 1 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "FIBER", price = 1 },
	},
}

--========================================
-- 섬별 부산물 매입상 (Island Traders)
-- optional:
-- modelTemplateName = "MyNpcModel"  -- ReplicatedStorage/Assets/NPCModels 또는 ServerStorage/NPCModels에서 탐색
-- showAutoLabel = false             -- 커스텀 모델에 자체 이름표가 있으면 비활성화 가능
-- labelOffset = Vector3.new(0, 5, 0)
-- labelMaxDistance = 36
-- modelPositionOffset = Vector3.new(0, 0, 0)
-- modelRotationOffset = Vector3.new(0, 0, 0) -- degrees
-- interactPartSize = Vector3.new(4, 4, 4)
-- interactPartOffset = Vector3.new(0, 0, 0)
--========================================
NPCShopData.ISLAND_TRADER_GRASSLAND = {
	id = "ISLAND_TRADER_GRASSLAND",
	name = "초원섬 부산물 상점",
	description = "초원섬의 부산물, 채집 자원, 각종 잡템을 매입합니다.",
	npcName = "수집상 마로",
	zoneName = "GRASSLAND",
	npcSpawnOffset = Vector3.new(52, 0, 34),
	labelMaxDistance = 30,
	modelPositionOffset = Vector3.new(0, 3.5, 0),
	modelRotationOffset = Vector3.new(180, 0, 0),
	interactPartSize = Vector3.new(4, 4, 4),
	interactPartOffset = Vector3.new(0, 0, 0),
	sellOnly = true,
	acceptAllItems = true,
	dynamicSellPricing = true,
	sellPricing = {
		positiveLevelPenaltyPerLevel = 0.08,
		positiveMinMultiplier = 0.35,
		negativeLevelBonusPerLevel = 0.12,
	},
	buyList = {},
	sellList = {
		{ itemId = "MEAT", price = 9 },
		{ itemId = "DODO_FEATHER", price = 14 },
		{ itemId = "SMALL_BONE", price = 12 },
		{ itemId = "LEATHER", price = 17 },
		{ itemId = "HORN", price = 24 },
	},
}

NPCShopData.ISLAND_TRADER_TROPICAL = {
	id = "ISLAND_TRADER_TROPICAL",
	name = "열대섬 부산물 상점",
	description = "열대섬의 부산물, 채집 자원, 각종 잡템을 매입합니다.",
	npcName = "교역상 세라",
	zoneName = "TROPICAL",
	npcSpawnOffset = Vector3.new(132, 0, 96),
	labelMaxDistance = 30,
	modelPositionOffset = Vector3.new(0, 3.5, 0),
	modelRotationOffset = Vector3.new(180, 0, 0),
	interactPartSize = Vector3.new(4, 4, 4),
	interactPartOffset = Vector3.new(0, 0, 0),
	sellOnly = true,
	acceptAllItems = true,
	dynamicSellPricing = true,
	sellPricing = {
		positiveLevelPenaltyPerLevel = 0.08,
		positiveMinMultiplier = 0.35,
		negativeLevelBonusPerLevel = 0.12,
	},
	buyList = {},
	sellList = {
		{ itemId = "MEAT", price = 11 },
		{ itemId = "TROPICAL_LEATHER", price = 26 },
		{ itemId = "BONE", price = 17 },
		{ itemId = "HORN", price = 32 },
		{ itemId = "SHARP_TOOTH", price = 28 },
	},
}

return NPCShopData
