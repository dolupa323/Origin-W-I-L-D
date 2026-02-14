-- FacilityData.lua
-- 시설 데이터 정의
-- 형태: 배열 { {id="...", ...}, ... }
-- DataService에서 Map으로 변환됨

local FacilityData = {
	-- 기본 시설: 캠프파이어
	{
		id = "CAMPFIRE",
		name = "캠프파이어",
		description = "요리와 빛을 제공합니다. 밤에 야생동물을 쪰아냅니다.",
		modelName = "Campfire",  -- ReplicatedStorage.Assets.Facilities 내 모델명
		requirements = {
			{ itemId = "WOOD", amount = 5 },
			{ itemId = "STONE", amount = 2 },
		},
		buildTime = 0,      -- 0 = 즉시 배치
		maxHealth = 100,
		interactRange = 5,  -- 상호작용 가능 거리
		functionType = "COOKING",  -- 기능 타입
	},
	
	-- 기본 시설: 보관함
	{
		id = "STORAGE_BOX",
		name = "보관함",
		description = "아이템을 보관할 수 있는 나무 상자입니다.",
		modelName = "StorageBox",
		requirements = {
			{ itemId = "WOOD", amount = 10 },
			{ itemId = "FIBER", amount = 5 },
		},
		buildTime = 0,
		maxHealth = 150,
		interactRange = 3,
		functionType = "STORAGE",
		storageSlots = 20,  -- 창고 전용 속성
	},
	
	-- 기본 시설: 작업대
	{
		id = "CRAFTING_TABLE",
		name = "작업대",
		description = "기본 도구와 장비를 제작할 수 있습니다.",
		modelName = "CraftingTable",
		requirements = {
			{ itemId = "WOOD", amount = 15 },
			{ itemId = "STONE", amount = 5 },
			{ itemId = "FLINT", amount = 3 },
		},
		buildTime = 0,
		maxHealth = 200,
		interactRange = 4,
		functionType = "CRAFTING",
		recipes = {},  -- 이 시설에서 제작 가능한 레시피 ID 목록
	},
	
	-- 기본 시설: 침낭
	{
		id = "SLEEPING_BAG",
		name = "침낭",
		description = "밤을 스킵하고 리스폰 위치를 설정합니다.",
		modelName = "SleepingBag",
		requirements = {
			{ itemId = "FIBER", amount = 20 },
			{ itemId = "WOOD", amount = 5 },
		},
		buildTime = 0,
		maxHealth = 50,
		interactRange = 2,
		functionType = "RESPAWN",
	},
}

return FacilityData
