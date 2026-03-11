-- ResourceNodeData.lua
-- 자원 노드 데이터 정의
-- 초원섬 전전 업데이트 기반

local ResourceNodeData = {
	--========================================
	-- [초원섬 특화] 나뭇가지 / 잔돌 (바닥 상호작용)
	--========================================
	{
		id = "GROUND_BRANCH",
		name = "나뭇가지",
		modelName = "Twig",
		nodeType = "TREE",
		optimalTool = nil,
		resources = {
			{ itemId = "BRANCH", min = 1, max = 1, weight = 1.0 },
		},
		maxHealth = 10,
		respawnTime = 60,
		xpPerHit = 1,
		requiresTool = false, -- 맨손 가능
	},
	{
		id = "GROUND_STONE",
		name = "잔돌",
		modelName = "SmallStone",
		nodeType = "ROCK",
		optimalTool = nil,
		resources = {
			{ itemId = "SMALL_STONE", min = 1, max = 1, weight = 1.0 },
		},
		maxHealth = 10,
		respawnTime = 60,
		xpPerHit = 1,
		requiresTool = false,
	},
	{
		id = "GROUND_FIBER",
		name = "섬유",
		modelName = "Grass", -- 기존 Grass 모델 사용
		nodeType = "FIBER",
		optimalTool = nil,
		resources = {
			{ itemId = "FIBER", min = 1, max = 2, weight = 1.0 },
		},
		maxHealth = 10,
		respawnTime = 60,
		xpPerHit = 1,
		requiresTool = false,
	},

	--========================================
	-- [초원섬 특화] 식물 및 덤불
	--========================================
	{
		id = "BUSH_BERRY",
		name = "열매 덤불",
		modelName = "BerryBush",
		nodeType = "BUSH",
		optimalTool = nil,
		resources = {
			{ itemId = "BERRY", min = 2, max = 3, weight = 1.0 },
		},
		maxHealth = 30,
		respawnTime = 180,
		xpPerHit = 1,
		requiresTool = false,
	},


	--========================================
	-- [초원섬 특화] 대형 자원 (도구 필수)
	--========================================
	{
		id = "TREE_THIN",
		name = "가는 나무",
		modelName = "TREE_THIN",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "LOG", min = 1, max = 2, weight = 1.0 },
		},
		maxHealth = 150,
		respawnTime = 300,
		xpPerHit = 3,
		requiresTool = true, -- 도끼 필수
	},
	{
		id = "ROCK_SOFT",
		name = "무른 바위",
		modelName = "SoftRock",
		nodeType = "ROCK",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "STONE", min = 1, max = 2, weight = 1.0 },
		},
		maxHealth = 150,
		respawnTime = 300,
		xpPerHit = 3,
		requiresTool = true, -- 곡괭이 필수
	},

	--========================================
	-- 일반 자원 노드 (타 섬 용도 포함)
	--========================================
	{
		id = "TREE_OAK",
		name = "참나무",
		modelName = "OakTree",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "WOOD", min = 5, max = 10, weight = 1.0 },
		},
		maxHealth = 250,
		respawnTime = 400,
		xpPerHit = 5,
		requiresTool = true,
	},
	{
		id = "ROCK_NORMAL",
		name = "바위",
		modelName = "Rock",
		nodeType = "ROCK",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "STONE", min = 4, max = 8, weight = 1.0 },
		},
		maxHealth = 200,
		respawnTime = 300,
		xpPerHit = 4,
		requiresTool = true,
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
		},
		maxHealth = 300,
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
		},
		maxHealth = 300,
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
		},
		maxHealth = 500,
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
		maxHealth = 250,
		respawnTime = 420,
		xpPerHit = 5,
		requiresTool = true,
	},
}

return ResourceNodeData
