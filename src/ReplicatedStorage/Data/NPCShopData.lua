-- NPCShopData.lua
-- NPC 상점 데이터 정의 (Phase 9)

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
		{ itemId = "WOOD", price = 5, stock = -1 },          -- -1 = 무한 재고
		{ itemId = "STONE", price = 3, stock = -1 },
		{ itemId = "FIBER", price = 2, stock = -1 },
		{ itemId = "FLINT", price = 4, stock = -1 },
		{ itemId = "TORCH", price = 15, stock = 50 },
	},
	
	-- 구매 가격 배율 (플레이어가 판매 시)
	sellMultiplier = 0.5,
	
	-- 특수 구매 목록 (플레이어가 상점에 팔 수 있는 아이템)
	sellList = {
		{ itemId = "WOOD", price = 2 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "FIBER", price = 1 },
		{ itemId = "FLINT", price = 2 },
		{ itemId = "RAW_MEAT", price = 8 },
		{ itemId = "LEATHER", price = 15 },
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
		{ itemId = "STONE_PICKAXE", price = 50, stock = -1 },
		{ itemId = "STONE_AXE", price = 50, stock = -1 },
		{ itemId = "WOODEN_CLUB", price = 30, stock = -1 },
		{ itemId = "STONE_SWORD", price = 80, stock = 20 },
		{ itemId = "TORCH", price = 10, stock = -1 },
	},
	
	sellMultiplier = 0.3,  -- 도구는 30% 가격에 구매
	
	sellList = {
		{ itemId = "STONE_PICKAXE", price = 15 },
		{ itemId = "STONE_AXE", price = 15 },
		{ itemId = "WOODEN_CLUB", price = 9 },
		{ itemId = "STONE_SWORD", price = 24 },
	},
}

--========================================
-- 팰 상점 (Pal Shop)
--========================================
NPCShopData.PAL_SHOP = {
	id = "PAL_SHOP",
	name = "팰 상점",
	description = "포획 도구와 팰 관련 용품을 판매합니다.",
	npcName = "조련사 미아",
	
	buyList = {
		{ itemId = "PAL_SPHERE", price = 50, stock = 30 },
		{ itemId = "SUPER_SPHERE", price = 150, stock = 10 },
		{ itemId = "ULTRA_SPHERE", price = 500, stock = 5 },
		{ itemId = "PAL_FOOD", price = 20, stock = -1 },
	},
	
	sellMultiplier = 0.4,
	
	sellList = {
		{ itemId = "PAL_SPHERE", price = 20 },
		{ itemId = "SUPER_SPHERE", price = 60 },
		{ itemId = "PAL_FOOD", price = 8 },
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
		{ itemId = "COOKED_MEAT", price = 25, stock = -1 },
		{ itemId = "BERRY", price = 5, stock = -1 },
		{ itemId = "HEALTH_POTION", price = 100, stock = 20 },
		{ itemId = "STAMINA_POTION", price = 80, stock = 20 },
	},
	
	sellMultiplier = 0.5,
	
	sellList = {
		{ itemId = "RAW_MEAT", price = 10 },
		{ itemId = "COOKED_MEAT", price = 12 },
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
		{ itemId = "IRON_INGOT", price = 30, stock = 50 },
		{ itemId = "NAILS", price = 5, stock = -1 },
		{ itemId = "ROPE", price = 10, stock = -1 },
	},
	
	sellMultiplier = 0.4,
	
	sellList = {
		{ itemId = "WOOD", price = 1 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "IRON_INGOT", price = 12 },
	},
}

return NPCShopData
