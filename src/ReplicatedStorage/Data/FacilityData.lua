-- FacilityData.lua
-- 시설 데이터 정의 (리펙터링: 초원섬 기초 시설만 유지)

local FacilityData = {
	--========================================
	-- 기초 생존 시설
	--========================================
	{
		id = "CAMPFIRE",
		name = "모닥불",
		description = "요리와 빛을 제공하고 체온을 유지합니다.",
		modelName = "Campfire",
		iconName = "CAMPFIRE",
		requirements = { { itemId = "BRANCH", amount = 5 }, { itemId = "SMALL_STONE", amount = 3 } },
		maxHealth = 100,
		interactRange = 15,
		passiveHealthDecayPerSec = 0.04,
		techLevel = 1,
		functionType = "COOKING",
		fuelConsumption = 1,
		hasFuelSlot = true,
		hasInputSlot = true,
		hasOutputSlot = true,
	},
	{
		id = "CAMP_TOTEM",
		name = "거점 토템",
		description = "해당 지역을 플레이어의 거점으로 선언합니다.",
		modelName = "CampTotem",
		iconName = "CAMP_TOTEM",
		requirements = { { itemId = "LOG", amount = 3 }, { itemId = "STONE", amount = 3 } },
		maxHealth = 500,
		techLevel = 1,
		functionType = "BASE_CORE",
	},
	{
		id = "LEAN_TO",
		name = "간이천막",
		description = "비바람을 피하고 부활 지점을 설정할 수 있는 거처입니다.",
		modelName = "LeanTo",
		placementYawOffset = 180,
		modelAliases = { "LEAN_TO", "Lean_To", "Leanto" },
		iconName = "LEAN_TO",
		iconAliases = { "LeanTo", "LEAN_TO", "Lean_To" },
		requirements = { { itemId = "LOG", amount = 3 }, { itemId = "FIBER", amount = 3 } },
		maxHealth = 150,
		techLevel = 1,
		functionType = "RESPAWN",
	},
	{
		id = "BASIC_WORKBENCH",
		name = "기초작업대",
		description = "기초적인 도구와 장비를 제작할 수 있습니다.",
		modelName = "PrimitiveWorkbench",
		modelAliases = { "BASIC_WORKBENCH", "PRIMITIVE_WORKBENCH", "BasicWorkbench" },
		iconName = "BASIC_WORKBENCH",
		iconAliases = { "PrimitiveWorkbench", "PRIMITIVE_WORKBENCH", "BASIC_WORKBENCH" },
		requirements = { { itemId = "LOG", amount = 3 }, { itemId = "FIBER", amount = 3 } },
		maxHealth = 200,
		techLevel = 1,
		functionType = "CRAFTING_T1",
		craftSpeed = 1.0,
	},
}

return FacilityData
