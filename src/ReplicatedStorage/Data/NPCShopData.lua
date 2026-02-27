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
	
	-- 구매 가격 배율 (플레이어가 판매 시)
	sellMultiplier = 0.5,
	
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
		{ itemId = "STONE_PICKAXE", price = 50, stock = -1 },
		{ itemId = "STONE_AXE", price = 50, stock = -1 },
		{ itemId = "STONE_SPEAR", price = 60, stock = -1 },
		{ itemId = "WOODEN_CLUB", price = 40, stock = -1 },
		{ itemId = "BRONZE_PICKAXE", price = 250, stock = 10 },
		{ itemId = "BRONZE_AXE", price = 250, stock = 10 },
	},
	
	sellMultiplier = 0.3,
	
	sellList = {
		{ itemId = "STONE_PICKAXE", price = 15 },
		{ itemId = "STONE_AXE", price = 15 },
		{ itemId = "STONE_SPEAR", price = 18 },
		{ itemId = "BRONZE_PICKAXE", price = 75 },
		{ itemId = "IRON_PICKAXE", price = 200 },
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
		{ itemId = "VINE_BOLA", price = 30, stock = 50 },     -- Sphere -> Bola 변경
		{ itemId = "BONE_BOLA", price = 100, stock = 20 },
		{ itemId = "BRONZE_BOLA", price = 300, stock = 10 },
	},
	
	sellMultiplier = 0.4,
	
	sellList = {
		{ itemId = "VINE_BOLA", price = 10 },
		{ itemId = "BONE_BOLA", price = 40 },
		{ itemId = "BRONZE_BOLA", price = 120 },
		{ itemId = "IRON_BOLA", price = 300 },
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
	
	sellMultiplier = 0.5,
	
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
	
	sellMultiplier = 0.4,
	
	sellList = {
		{ itemId = "WOOD", price = 1 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "FIBER", price = 1 },
	},
}

return NPCShopData
