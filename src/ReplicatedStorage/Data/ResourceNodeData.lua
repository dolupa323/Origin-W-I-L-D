-- ResourceNodeData.lua
-- 자원 노드 데이터 정의 (나무, 돌, 풀 등)
-- 형태: 배열 { {id="...", ...}, ... }
-- DataService에서 Map으로 변환됨
-- optimalTool: 최적 도구 (없으면 맨손, 있으면 해당 도구가 가장 효율적)
-- 모든 자원은 맨손으로 채집 가능하나, 최적 도구 사용 시 빠르고 효율적
-- modelName: Assets/ResourceNodeModels/ 폴더에서 찾을 모델 이름 (Toolbox 모델 지원)

local ResourceNodeData = {
	--========================================
	-- 나무 (TREE) - AXE 최적
	--========================================
	{
		id = "TREE_OAK",
		name = "참나무",
		modelName = "OakTree",  -- Assets/ResourceNodeModels/OakTree
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "WOOD", min = 3, max = 5, weight = 1.0 },
		},
		maxHits = 5,
		respawnTime = 300,
		xpPerHit = 2,
	},
	{
		id = "TREE_PINE",
		name = "소나무",
		modelName = "PineTree",  -- Assets/ResourceNodeModels/PineTree
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "WOOD", min = 4, max = 6, weight = 1.0 },
			{ itemId = "RESIN", min = 0, max = 1, weight = 0.2 },
		},
		maxHits = 6,
		respawnTime = 360,
		xpPerHit = 3,
	},
	
	--========================================
	-- 바위 (ROCK) - PICKAXE 최적
	--========================================
	{
		id = "ROCK_NORMAL",
		name = "바위",
		modelName = "Rock",  -- Assets/ResourceNodeModels/Rock
		nodeType = "ROCK",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "STONE", min = 2, max = 4, weight = 1.0 },
			{ itemId = "FLINT", min = 0, max = 1, weight = 0.3 },
		},
		maxHits = 4,
		respawnTime = 240,
		xpPerHit = 2,
	},
	{
		id = "ROCK_IRON",
		name = "철광석 바위",
		modelName = "IronRock",  -- Assets/ResourceNodeModels/IronRock
		nodeType = "ROCK",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "STONE", min = 1, max = 2, weight = 0.5 },
			{ itemId = "IRON_ORE", min = 1, max = 3, weight = 1.0 },
		},
		maxHits = 6,
		respawnTime = 480,
		xpPerHit = 4,
	},
	
	--========================================
	-- 덤불/식물 (BUSH) - 맨손 또는 도구
	--========================================
	{
		id = "BUSH_BERRY",
		name = "베리 덤불",
		modelName = "BerryBush",  -- Assets/ResourceNodeModels/BerryBush
		nodeType = "BUSH",
		optimalTool = nil,  -- 최적 도구 없음 (맨손이 최적)
		resources = {
			{ itemId = "BERRY", min = 2, max = 5, weight = 1.0 },
		},
		maxHits = 3,
		respawnTime = 180,
		xpPerHit = 1,
	},
	
	--========================================
	-- 섬유 (FIBER) - 맨손 채집
	--========================================
	{
		id = "FIBER_GRASS",
		name = "풀",
		modelName = "Grass",  -- Assets/ResourceNodeModels/Grass
		nodeType = "FIBER",
		optimalTool = nil,  -- 최적 도구 없음 (맨손이 최적)
		resources = {
			{ itemId = "FIBER", min = 2, max = 4, weight = 1.0 },
		},
		maxHits = 2,
		respawnTime = 120,
		xpPerHit = 1,
	},
	
	--========================================
	-- 광석 (ORE) - PICKAXE 최적, 고급 자원
	--========================================
	{
		id = "ORE_COAL",
		name = "석탄 광맥",
		modelName = "CoalOre",  -- Assets/ResourceNodeModels/CoalOre
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "COAL", min = 2, max = 4, weight = 1.0 },
		},
		maxHits = 5,
		respawnTime = 420,
		xpPerHit = 3,
	},
	{
		id = "ORE_GOLD",
		name = "금 광맥",
		modelName = "GoldOre",  -- Assets/ResourceNodeModels/GoldOre
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "GOLD_ORE", min = 1, max = 2, weight = 1.0 },
			{ itemId = "STONE", min = 1, max = 2, weight = 0.5 },
		},
		maxHits = 8,
		respawnTime = 600,
		xpPerHit = 5,
	},
}

return ResourceNodeData
