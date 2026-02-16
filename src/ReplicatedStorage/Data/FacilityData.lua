-- FacilityData.lua
-- 시설 데이터 정의
-- 형태: 배열 { {id="...", ...}, ... }
-- DataService에서 Map으로 변환됨

local FacilityData = {
	-- 기본 시설: 캠프파이어 (연료 기반 요리)
	{
		id = "CAMPFIRE",
		name = "캠프파이어",
		description = "요리와 빛을 제공합니다. 밤에 야생동물을 쫓아냅니다.",
		modelName = "Campfire",
		requirements = {
			{ itemId = "WOOD", amount = 5 },
			{ itemId = "STONE", amount = 2 },
		},
		buildTime = 0,
		maxHealth = 100,
		interactRange = 5,
		functionType = "COOKING",
		-- FacilityService 전용 필드
		fuelConsumption = 1,    -- 초당 연료값 1 소모
		craftSpeed = 1.0,       -- 제작 속도 배율 (1.0 = 기본)
		hasInputSlot = true,    -- Input 슬롯 보유
		hasFuelSlot = true,     -- Fuel 슬롯 보유
		hasOutputSlot = true,   -- Output 슬롯 보유
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
		storageSlots = 20,
	},
	
	-- 기본 시설: 작업대 (큐 기반 제작, 연료 불필요)
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
		-- FacilityService 전용 필드
		fuelConsumption = 0,    -- 연료 불필요
		craftSpeed = 1.0,       -- 제작 속도 배율
		hasInputSlot = false,   -- 슬롯 없음 (CraftingService 큐 방식)
		hasFuelSlot = false,
		hasOutputSlot = false,  -- 결과물은 바닥 드랍
		queueMax = 10,          -- 제작 대기열 최대 크기
		recipes = {},
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
