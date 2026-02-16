-- RecipeData.lua
-- 레시피 데이터 정의
-- 형태: 배열 { {id="...", inputs={}, outputs={}, ...}, ... }
-- requiredFacility: nil=맨손제작, "CRAFTING"=작업대 필요 (Enums.FacilityType 기준)

local RecipeData = {
	-- 돌 곡괭이 제작 (작업대 필요)
	{
		id = "CRAFT_STONE_PICKAXE",
		name = "돌 곡괭이 제작",
		category = "TOOL",
		requiredFacility = "CRAFTING",  -- FacilityType
		craftTime = 3,                   -- 기본 제작 소요 시간 (초)
		techLevel = 0,                   -- 필요 테크 레벨 (0=기본 해금)
		inputs = {
			{ itemId = "STONE", count = 3 },
			{ itemId = "WOOD", count = 2 },
			{ itemId = "FIBER", count = 5 },
		},
		outputs = {
			{ itemId = "STONE_PICKAXE", count = 1 },
		},
	},
	-- 돌 도끼 제작 (작업대 필요)
	{
		id = "CRAFT_STONE_AXE",
		name = "돌 도끼 제작",
		category = "TOOL",
		requiredFacility = "CRAFTING",
		craftTime = 3,
		techLevel = 0,
		inputs = {
			{ itemId = "STONE", count = 2 },
			{ itemId = "WOOD", count = 3 },
			{ itemId = "FIBER", count = 5 },
		},
		outputs = {
			{ itemId = "STONE_AXE", count = 1 },
		},
	},
	-- 캠프파이어 키트 (맨손 제작 가능)
	{
		id = "CRAFT_CAMPFIRE_KIT",
		name = "캠프파이어 키트 제작",
		category = "PLACEABLE",
		requiredFacility = nil,  -- 맨손 제작 가능
		craftTime = 0,           -- 즉시 제작
		techLevel = 0,
		inputs = {
			{ itemId = "WOOD", count = 5 },
			{ itemId = "STONE", count = 2 },
		},
		outputs = {
			{ itemId = "WOOD", count = 3 },  -- 임시: 캠프파이어 아이템 미구현으로 wood 반환
		},
	},
	-- 기본 포획구 제작 (Phase 5)
	{
		id = "CRAFT_CAPTURE_SPHERE_BASIC",
		name = "기본 포획구 제작",
		category = "CONSUMABLE",
		requiredFacility = "CRAFTING",
		craftTime = 5,
		techLevel = 0,
		inputs = {
			{ itemId = "STONE", count = 5 },
			{ itemId = "WOOD", count = 3 },
			{ itemId = "FIBER", count = 10 },
		},
		outputs = {
			{ itemId = "CAPTURE_SPHERE_BASIC", count = 3 },
		},
	},
	-- 고급 포획구 제작 (Phase 5)
	{
		id = "CRAFT_CAPTURE_SPHERE_MEGA",
		name = "고급 포획구 제작",
		category = "CONSUMABLE",
		requiredFacility = "CRAFTING",
		craftTime = 10,
		techLevel = 1,
		inputs = {
			{ itemId = "STONE", count = 10 },
			{ itemId = "WOOD", count = 5 },
			{ itemId = "FIBER", count = 15 },
			{ itemId = "HORN", count = 1 },
		},
		outputs = {
			{ itemId = "CAPTURE_SPHERE_MEGA", count = 2 },
		},
	},
	-- 마스터 포획구 제작 (Phase 5)
	{
		id = "CRAFT_CAPTURE_SPHERE_ULTRA",
		name = "마스터 포획구 제작",
		category = "CONSUMABLE",
		requiredFacility = "CRAFTING",
		craftTime = 20,
		techLevel = 2,
		inputs = {
			{ itemId = "STONE", count = 15 },
			{ itemId = "WOOD", count = 10 },
			{ itemId = "FIBER", count = 20 },
			{ itemId = "HORN", count = 3 },
			{ itemId = "LEATHER", count = 5 },
		},
		outputs = {
			{ itemId = "CAPTURE_SPHERE_ULTRA", count = 1 },
		},
	},
}

return RecipeData
