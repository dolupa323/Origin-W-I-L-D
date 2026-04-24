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
		level = 1,
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
		id = "GROUND_STONE", -- 잔돌 (스폰 중단됨, 레거시 호환용)
		name = "잔돌(비활성)",
		level = 1,
		modelName = "SmallStone",
		nodeType = "ROCK",
		optimalTool = nil,
		resources = {
			{ itemId = "STONE", min = 1, max = 1, weight = 1.0 },
		},
		maxHealth = 10,
		respawnTime = 60,
		xpPerHit = 1,
		requiresTool = false,
	},
	{
		id = "GROUND_FIBER",
		name = "섬유",
		level = 1,
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
		level = 2,
		modelName = "BerryBush",
		nodeType = "BUSH",
		optimalTool = nil,
		resources = {
			{ itemId = "BERRY", min = 2, max = 3, weight = 1.0 },
			{ itemId = "BRANCH", min = 1, max = 2, weight = 1.0 }, -- 나뭇가지 추가
			{ itemId = "FIBER", min = 1, max = 2, weight = 1.0 },
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
		level = 3,
		modelName = "TREE_THIN",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "LOG", min = 1, max = 2, weight = 1.0 },
		},
		maxHealth = 50,
		respawnTime = 300,
		xpPerHit = 3,
		requiresTool = true, -- 도끼 필수
	},
	{
		id = "ROCK_SOFT",
		name = "무른 바위",
		level = 3,
		modelName = "SoftRock",
		nodeType = "ROCK",
		optimalTool = nil, -- 곡괭이 없이도 동일 효율
		resources = {
			{ itemId = "STONE", min = 1, max = 2, weight = 1.0 },
		},
		maxHealth = 50,
		respawnTime = 300,
		xpPerHit = 3,
		requiresTool = false, -- 곡괭이 불필요 (패치)
	},

	--========================================
	-- 일반 자원 노드 (타 섬 용도 포함)
	--========================================
	{
		id = "FALM_TREE",
		name = "야자나무",
		level = 4,
		modelName = "FALM_TREE",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "PALM_LOG", min = 2, max = 4, weight = 1.0 },
			{ itemId = "COCONUT", min = 1, max = 2, weight = 0.6 },
		},
		maxHealth = 80,
		respawnTime = 300,
		xpPerHit = 4,
		requiresTool = true,
	},
	{
		id = "ROCK_NORMAL",
		name = "바위",
		level = 5,
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
		id = "ORE_IRON",
		name = "철 광맥",
		level = 10,
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
		level = 8,
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

	--========================================
	-- [열대섬 특화] 흑요석, 억새 갈대
	--========================================
	{
		id = "OBSIDIAN_NODE",
		name = "흑요석 바위",
		level = 8,
		modelName = "OBSIDIAN_NODE",
		nodeType = "ROCK",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "OBSIDIAN", min = 2, max = 5, weight = 1.0 },
			{ itemId = "STONE", min = 1, max = 3, weight = 0.4 },
		},
		maxHealth = 400,
		respawnTime = 500,
		xpPerHit = 8,
		requiresTool = true,
	},
	{
		id = "REED_BUSH",
		name = "억새 갈대",
		level = 3,
		modelName = "REED_BUSH",
		nodeType = "FIBER",
		optimalTool = "AXE",
		resources = {
			{ itemId = "REED", min = 2, max = 4, weight = 1.0 },
			{ itemId = "FIBER", min = 1, max = 2, weight = 0.5 },
		},
		maxHealth = 40,
		respawnTime = 180,
		xpPerHit = 3,
		requiresTool = false,
	},

	--========================================
	-- 크리처 시체 (사냥 후 채집)
	--========================================
	{
		id = "CORPSE_ARCHAEOPTERYX",
		name = "시조새 사체",
		level = 1,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 1, max = 2, weight = 1.0 },
			{ itemId = "FEATHER", min = 1, max = 3, weight = 0.8 },
		},
		maxHealth = 6,
		respawnTime = 0,
		xpPerHit = 2,
		requiresTool = false,
	},
	{
		id = "CORPSE_TROODON",
		name = "트로오돈 사체",
		level = 2,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 1, max = 1, weight = 0.8 },
			{ itemId = "SMALL_BONE", min = 1, max = 2, weight = 0.6 },
		},
		maxHealth = 4,
		respawnTime = 0,
		xpPerHit = 1,
		requiresTool = false,
	},
	{
		id = "CORPSE_PARASAUR",
		name = "파라사우롤로푸스 사체",
		level = 5,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 3, max = 6, weight = 1.0 },
			{ itemId = "TROPICAL_LEATHER", min = 2, max = 4, weight = 0.7 },
		},
		maxHealth = 7,
		respawnTime = 0,
		xpPerHit = 5,
		requiresTool = false,
	},
	{
		id = "CORPSE_TRICERATOPS",
		name = "트리케라톱스 사체",
		level = 8,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 4, max = 8, weight = 1.0 },
			{ itemId = "LEATHER", min = 3, max = 6, weight = 0.8 },
			{ itemId = "HORN", min = 1, max = 1, weight = 0.3 },
		},
		maxHealth = 10,
		respawnTime = 0,
		xpPerHit = 8,
		requiresTool = false,
	},
	{
		id = "CORPSE_OLOROTITAN",
		name = "올로로티탄 사체",
		level = 3,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 1, max = 3, weight = 1.0 },
			{ itemId = "LEATHER", min = 1, max = 3, weight = 1.0 },
		},
		maxHealth = 12,
		respawnTime = 0,
		xpPerHit = 4,
		requiresTool = false,
	},
	{
		id = "CORPSE_STEGOSAURUS",
		name = "스테고사우루스 사체",
		level = 7,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 4, max = 7, weight = 1.0 },
			{ itemId = "TROPICAL_LEATHER", min = 3, max = 5, weight = 0.8 },
			{ itemId = "BONE", min = 1, max = 2, weight = 0.4 },
		},
		maxHealth = 10,
		respawnTime = 0,
		xpPerHit = 7,
		requiresTool = false,
	},
	{
		id = "CORPSE_ANKYLOSAURUS",
		name = "안킬로사우루스 사체",
		level = 10,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 3, max = 5, weight = 1.0 },
			{ itemId = "BONE", min = 2, max = 3, weight = 0.5 },
			{ itemId = "IRON_ORE", min = 1, max = 2, weight = 0.2 },
		},
		maxHealth = 11,
		respawnTime = 0,
		xpPerHit = 10,
		requiresTool = false,
	},
	{
		id = "CORPSE_RAPTOR",
		name = "랩터 사체",
		level = 6,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 1, max = 3, weight = 1.0 },
			{ itemId = "TROPICAL_LEATHER", min = 2, max = 3, weight = 0.6 },
			{ itemId = "BONE", min = 1, max = 1, weight = 0.3 },
			{ itemId = "SHARP_TOOTH", min = 1, max = 2, weight = 0.4 },
		},
		maxHealth = 5,
		respawnTime = 0,
		xpPerHit = 5,
		requiresTool = false,
	},
	{
		id = "CORPSE_TREX",
		name = "티라노사우루스 사체",
		level = 15,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 8, max = 15, weight = 1.0 },
			{ itemId = "BONE", min = 3, max = 6, weight = 0.8 },
			{ itemId = "HORN", min = 1, max = 2, weight = 0.4 },
		},
		maxHealth = 24,
		respawnTime = 0,
		xpPerHit = 20,
		requiresTool = false,
	},
	{
		id = "CORPSE_KELENKEN",
		name = "켈렌켄 사체",
		level = 4,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 1, max = 3, weight = 1.0 },
			{ itemId = "FEATHER", min = 2, max = 4, weight = 0.8 },
			{ itemId = "BONE", min = 1, max = 2, weight = 0.4 },
		},
		maxHealth = 8,
		respawnTime = 0,
		xpPerHit = 4,
		requiresTool = false,
	},
	{
		id = "CORPSE_DEINOCHEIRUS",
		name = "데이노키루스 사체",
		level = 7,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 4, max = 8, weight = 1.0 },
			{ itemId = "TROPICAL_LEATHER", min = 3, max = 6, weight = 0.8 },
			{ itemId = "BONE", min = 2, max = 4, weight = 0.5 },
		},
		maxHealth = 15,
		respawnTime = 0,
		xpPerHit = 8,
		requiresTool = false,
	},
	{
		id = "CORPSE_ALLOSAURUS",
		name = "알로사우루스 사체",
		level = 12,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 5, max = 10, weight = 1.0 },
			{ itemId = "BONE", min = 2, max = 4, weight = 1.0 },
			{ itemId = "SHARP_TOOTH", min = 2, max = 5, weight = 0.8 },
		},
		maxHealth = 18,
		respawnTime = 0,
		xpPerHit = 12,
		requiresTool = false,
	},
	{
		id = "CORPSE_GIGANTORAPTOR",
		name = "기간토랍토르 사체",
		level = 7,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 1, max = 2, weight = 1.0 },
			{ itemId = "LEATHER", min = 1, max = 2, weight = 1.0 },
			{ itemId = "BONE", min = 1, max = 1, weight = 0.5 },
		},
		maxHealth = 6,
		respawnTime = 0,
		xpPerHit = 6,
		requiresTool = false,
	},
	{
		id = "CORPSE_TITANOSAURUS",
		name = "티타노사우루스 사체",
		level = 10,
		modelName = nil,
		nodeType = "CORPSE",
		optimalTool = nil,
		resources = {
			{ itemId = "MEAT", min = 10, max = 20, weight = 1.0 },
			{ itemId = "BONE", min = 5, max = 10, weight = 1.0 },
			{ itemId = "IRON_ORE", min = 2, max = 4, weight = 0.5 },
		},
		maxHealth = 30,
		respawnTime = 0,
		xpPerHit = 25,
		requiresTool = false,
	},
	--========================================
	-- [사막섬 특화] 사막나무, 갈대, 청동 광맥 (고정 배치)
	--========================================
	{
		id = "DESERT_TREE",
		name = "사막나무",
		level = 24,
		modelName = "DESERT_TREE",
		nodeType = "TREE",
		optimalTool = "AXE",
		resources = {
			{ itemId = "DESERT_LOG", min = 2, max = 5, weight = 1.0 },
			{ itemId = "DATE", min = 1, max = 2, weight = 0.6 },
		},
		maxHealth = 250,
		respawnTime = 400,
		xpPerHit = 15,
		requiresTool = true,
	},
	{
		id = "DESERT_REED",
		name = "사막 갈대",
		level = 22,
		modelName = "DESERT_REED",
		nodeType = "FIBER",
		optimalTool = "AXE",
		resources = {
			{ itemId = "DESERT_REED", min = 3, max = 6, weight = 1.0 },
			{ itemId = "FIBER", min = 1, max = 3, weight = 0.5 },
		},
		maxHealth = 60,
		respawnTime = 240,
		xpPerHit = 10,
		requiresTool = true,
	},
	{
		id = "BRONZE_ROCK",
		name = "청동 광맥",
		level = 28,
		modelName = "BRONZE_ROCK",
		nodeType = "ORE",
		optimalTool = "PICKAXE",
		resources = {
			{ itemId = "BRONZE_ORE", min = 5, max = 10, weight = 1.0 },
			{ itemId = "STONE", min = 2, max = 4, weight = 0.6 },
		},
		maxHealth = 600,
		respawnTime = 600,
		xpPerHit = 25,
		requiresTool = true,
	},
}

return ResourceNodeData
