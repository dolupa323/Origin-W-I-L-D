-- ResourceNodeData.lua
-- 자원 노드 데이터 정의 (나무, 돌, 풀 등)
-- 형태: 배열 { {id="...", ...}, ... }
-- DataService에서 Map으로 변환됨

local ResourceNodeData = {
	--========================================
	-- 나무 (TREE) - AXE 필요
	--========================================
	{
		id = "TREE_OAK",
		name = "참나무",
		nodeType = "TREE",
		requiredTool = "AXE",
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
		nodeType = "TREE",
		requiredTool = "AXE",
		resources = {
			{ itemId = "WOOD", min = 4, max = 6, weight = 1.0 },
			{ itemId = "RESIN", min = 0, max = 1, weight = 0.2 },
		},
		maxHits = 6,
		respawnTime = 360,
		xpPerHit = 3,
	},
	
	--========================================
	-- 바위 (ROCK) - PICKAXE 필요
	--========================================
	{
		id = "ROCK_NORMAL",
		name = "바위",
		nodeType = "ROCK",
		requiredTool = "PICKAXE",
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
		nodeType = "ROCK",
		requiredTool = "PICKAXE",
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
		nodeType = "BUSH",
		requiredTool = nil,  -- 맨손 채집 가능
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
		nodeType = "FIBER",
		requiredTool = nil,  -- 맨손 채집 가능
		resources = {
			{ itemId = "FIBER", min = 2, max = 4, weight = 1.0 },
		},
		maxHits = 2,
		respawnTime = 120,
		xpPerHit = 1,
	},
	
	--========================================
	-- 광석 (ORE) - PICKAXE 필요, 고급 자원
	--========================================
	{
		id = "ORE_COAL",
		name = "석탄 광맥",
		nodeType = "ORE",
		requiredTool = "PICKAXE",
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
		nodeType = "ORE",
		requiredTool = "PICKAXE",
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
