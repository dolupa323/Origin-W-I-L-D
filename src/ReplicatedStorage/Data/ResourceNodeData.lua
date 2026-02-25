-- ResourceNodeData.lua
-- 자원 노드 데이터 정의
-- 0단계 상호작용 및 티어별 광맥 추가

local ResourceNodeData = {
	--========================================
	-- 나무 (TREE) - AXE 최적
	--========================================
	{
		id = "TREE_OAK",
		name = "참나무",
		modelName = "OakTree",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "WOOD", min = 3, max = 5, weight = 1.0 },
		},
		maxHits = 10,
		respawnTime = 300,
		xpPerHit = 2,
		requiresTool = true,
	},
	{
		id = "TREE_PINE",
		name = "소나무",
		modelName = "PineTree",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "WOOD", min = 4, max = 6, weight = 1.0 },
			{ itemId = "RESIN", min = 0, max = 1, weight = 0.2 },
		},
		maxHits = 15,
		respawnTime = 360,
		xpPerHit = 3,
		requiresTool = true,
	},
	
	--========================================
	-- 바위 (ROCK) - PICKAXE 최적
	--========================================
	{
		id = "ROCK_NORMAL",
		name = "바위",
		modelName = "Rock",
		nodeType = "ROCK",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "STONE", min = 2, max = 4, weight = 1.0 },
		},
		maxHits = 8,
		respawnTime = 240,
		xpPerHit = 2,
		requiresTool = true,
	},
	
	--========================================
	-- 덤불 및 식물 (Tier 0 개선)
	--========================================
	{
		id = "BUSH_BERRY",
		name = "야생 덤불",
		modelName = "BerryBush",
		nodeType = "BUSH",
		optimalTool = nil,
		resources = {
			{ itemId = "WOOD", min = 1, max = 2, weight = 0.8 },  -- 덤불에서도 나무 수급 가능
			{ itemId = "BERRY", min = 2, max = 4, weight = 1.0 },
			{ itemId = "FIBER", min = 1, max = 3, weight = 1.0 },
		},
		maxHits = 3,
		respawnTime = 180,
		xpPerHit = 1,
		requiresTool = false, -- 상시 맨손 가능
	},
	{
		id = "FIBER_GRASS",
		name = "풀",
		modelName = "Grass",
		nodeType = "FIBER",
		optimalTool = nil,
		resources = {
			{ itemId = "FIBER", min = 2, max = 4, weight = 1.0 },
		},
		maxHits = 1,
		respawnTime = 120,
		xpPerHit = 1,
	},
	
	--========================================
	-- 광석 광맥 (Tier 3-4)
	--========================================
	{
		id = "ORE_COPPER",
		name = "구리 광맥",
		modelName = "CopperOre",
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "COPPER_ORE", min = 3, max = 6, weight = 1.0 },
			{ itemId = "STONE", min = 1, max = 2, weight = 0.5 },
		},
		maxHits = 20,
		respawnTime = 400,
		xpPerHit = 5,
		requiresTool = true,
	},
	{
		id = "ORE_TIN",
		name = "주석 광맥",
		modelName = "TinOre",
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "TIN_ORE", min = 3, max = 6, weight = 1.0 },
			{ itemId = "STONE", min = 1, max = 2, weight = 0.5 },
		},
		maxHits = 20,
		respawnTime = 400,
		xpPerHit = 5,
		requiresTool = true,
	},
	{
		id = "ORE_IRON",
		name = "철 광맥",
		modelName = "IronOre",
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "IRON_ORE", min = 4, max = 8, weight = 1.0 },
			{ itemId = "COAL", min = 1, max = 2, weight = 0.3 },
		},
		maxHits = 35,
		respawnTime = 600,
		xpPerHit = 10,
		requiresTool = true,
	},
	{
		id = "ORE_COAL",
		name = "석탄 광맥",
		modelName = "CoalOre",
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "COAL", min = 2, max = 4, weight = 1.0 },
		},
		maxHits = 15,
		respawnTime = 420,
		xpPerHit = 5,
		requiresTool = true,
	},
	
	--========================================
	-- 바닥 자원 (Tier 0 상호작용)
	--========================================
	{
		id = "GROUND_STONE",
		name = "작은 돌 (바닥)",
		modelName = "SmallStone",
		nodeType = "ROCK",
		optimalTool = nil,
		resources = {
			{ itemId = "STONE", min = 1, max = 1, weight = 1.0 },
		},
		maxHits = 1,
		respawnTime = 60,
		xpPerHit = 1,
	},
	{
		id = "GROUND_BRANCH",
		name = "나뭇가지 (바닥)",
		modelName = "Twig",
		nodeType = "TREE",
		optimalTool = nil,
		resources = {
			{ itemId = "WOOD", min = 1, max = 1, weight = 1.0 },
		},
		maxHits = 1,
		respawnTime = 60,
		xpPerHit = 1,
	},
}

return ResourceNodeData
