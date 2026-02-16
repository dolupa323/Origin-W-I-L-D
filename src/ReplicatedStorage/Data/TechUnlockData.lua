-- TechUnlockData.lua
-- 기술 해금 데이터 정의 (Phase 6)
-- 형태: 배열 { { id = "...", unlocks = {...} }, ... }
-- Validator.validateIdTable()로 Map 변환 후 사용

local TechUnlockData = {
	--========================================
	-- Tier 0: 기초 (시작 시 자동 해금)
	--========================================
	{
		id = "TECH_BASICS",
		name = "기초 지식",
		description = "생존의 기본을 배웁니다.",
		techLevel = 0,
		techPointCost = 0,        -- 무료 (시작 해금)
		prerequisites = {},
		unlocks = {
			recipes = {},         -- 맨손 제작은 기본 가능
			facilities = {},
			features = {},
		},
		category = "BASICS",
	},
	
	--========================================
	-- Tier 1: 초급 (레벨 1~5)
	--========================================
	{
		id = "TECH_STONE_TOOLS",
		name = "석기 도구",
		description = "돌로 만든 기본 도구를 제작합니다.",
		techLevel = 1,
		techPointCost = 1,
		prerequisites = { "TECH_BASICS" },
		unlocks = {
			recipes = { "CRAFT_STONE_PICKAXE", "CRAFT_STONE_AXE" },
			facilities = {},
			features = {},
		},
		category = "TOOLS",
	},
	{
		id = "TECH_FIBER_CRAFT",
		name = "섬유 가공",
		description = "섬유를 활용한 기본 아이템을 제작합니다.",
		techLevel = 1,
		techPointCost = 1,
		prerequisites = { "TECH_BASICS" },
		unlocks = {
			recipes = {},  -- CRAFT_ROPE 등 추가 예정
			facilities = {},
			features = {},
		},
		category = "CRAFTING",
	},
	{
		id = "TECH_CAMPFIRE",
		name = "캠프파이어",
		description = "불을 피워 요리하고 따뜻하게 지냅니다.",
		techLevel = 1,
		techPointCost = 1,
		prerequisites = { "TECH_BASICS" },
		unlocks = {
			recipes = { "CRAFT_CAMPFIRE_KIT" },
			facilities = { "CAMPFIRE" },
			features = {},
		},
		category = "STRUCTURES",
	},
	
	--========================================
	-- Tier 2: 중급 (레벨 5~15)
	--========================================
	{
		id = "TECH_WORKBENCH",
		name = "작업대",
		description = "다양한 도구와 장비를 제작할 수 있는 작업대.",
		techLevel = 2,
		techPointCost = 2,
		prerequisites = { "TECH_STONE_TOOLS" },
		unlocks = {
			recipes = {},  -- CRAFT_WORKBENCH 추가 예정
			facilities = { "WORKBENCH" },
			features = {},
		},
		category = "STRUCTURES",
	},
	{
		id = "TECH_CAPTURE_BASIC",
		name = "기본 포획술",
		description = "약해진 크리처를 포획하는 기술.",
		techLevel = 2,
		techPointCost = 2,
		prerequisites = { "TECH_FIBER_CRAFT" },
		unlocks = {
			recipes = { "CRAFT_CAPTURE_SPHERE_BASIC" },
			facilities = {},
			features = { "CAPTURE" },
		},
		category = "PAL",
	},
	{
		id = "TECH_STORAGE",
		name = "보관함 제작",
		description = "아이템을 안전하게 보관하는 보관함.",
		techLevel = 2,
		techPointCost = 2,
		prerequisites = { "TECH_STONE_TOOLS" },
		unlocks = {
			recipes = {},  -- CRAFT_STORAGE_BOX 추가 예정
			facilities = { "STORAGE" },
			features = {},
		},
		category = "STRUCTURES",
	},
	
	--========================================
	-- Tier 3: 상급 (레벨 15~30)
	--========================================
	{
		id = "TECH_CAPTURE_MEGA",
		name = "고급 포획술",
		description = "더 강력한 포획구로 포획 확률을 높입니다.",
		techLevel = 3,
		techPointCost = 3,
		prerequisites = { "TECH_CAPTURE_BASIC" },
		unlocks = {
			recipes = { "CRAFT_CAPTURE_SPHERE_MEGA" },
			facilities = {},
			features = {},
		},
		category = "PAL",
	},
	{
		id = "TECH_SMELTING",
		name = "제련 기술",
		description = "광석을 녹여 금속을 추출합니다.",
		techLevel = 3,
		techPointCost = 3,
		prerequisites = { "TECH_WORKBENCH", "TECH_CAMPFIRE" },
		unlocks = {
			recipes = {},  -- CRAFT_FURNACE 추가 예정
			facilities = { "FURNACE" },
			features = {},
		},
		category = "STRUCTURES",
	},
	{
		id = "TECH_METAL_TOOLS",
		name = "금속 도구",
		description = "더 강력하고 내구성 있는 금속 도구.",
		techLevel = 3,
		techPointCost = 3,
		prerequisites = { "TECH_SMELTING" },
		unlocks = {
			recipes = {},  -- CRAFT_METAL_PICKAXE 등 추가 예정
			facilities = {},
			features = {},
		},
		category = "TOOLS",
	},
	
	--========================================
	-- Tier 4: 고급 (레벨 30~50)
	--========================================
	{
		id = "TECH_CAPTURE_ULTRA",
		name = "최고급 포획술",
		description = "최강의 포획구로 어떤 크리처도 포획합니다.",
		techLevel = 4,
		techPointCost = 4,
		prerequisites = { "TECH_CAPTURE_MEGA" },
		unlocks = {
			recipes = { "CRAFT_CAPTURE_SPHERE_ULTRA" },
			facilities = {},
			features = {},
		},
		category = "PAL",
	},
	{
		id = "TECH_PAL_RIDING",
		name = "팰 탑승",
		description = "팰에 올라타 빠르게 이동합니다.",
		techLevel = 4,
		techPointCost = 5,
		prerequisites = { "TECH_CAPTURE_MEGA" },
		unlocks = {
			recipes = {},  -- CRAFT_SADDLE 추가 예정
			facilities = {},
			features = { "PAL_RIDING" },
		},
		category = "PAL",
	},
	{
		id = "TECH_PAL_BREEDING",
		name = "팰 교배",
		description = "두 팰을 교배하여 새로운 팰을 얻습니다.",
		techLevel = 4,
		techPointCost = 5,
		prerequisites = { "TECH_CAPTURE_ULTRA" },
		unlocks = {
			recipes = {},  -- CRAFT_BREEDING_PEN 추가 예정
			facilities = { "BREEDING_PEN" },
			features = { "PAL_BREEDING" },
		},
		category = "PAL",
	},
}

return TechUnlockData
