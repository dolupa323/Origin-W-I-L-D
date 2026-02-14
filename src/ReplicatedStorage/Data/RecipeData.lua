-- RecipeData.lua
-- 레시피 데이터 정의
-- 형태: 배열 { {id="...", inputs={}, outputs={}, ...}, ... }

local RecipeData = {
	-- 돌 곡괭이 제작
	{
		id = "CRAFT_STONE_PICKAXE",
		name = "돌 곡괭이 제작",
		category = "TOOL",
		craftTime = 3,
		inputs = {
			{ itemId = "STONE", count = 3 },
			{ itemId = "WOOD", count = 2 },
			{ itemId = "FIBER", count = 5 },
		},
		outputs = {
			{ itemId = "STONE_PICKAXE", count = 1 },
		},
	},
	-- 돌 도끼 제작
	{
		id = "CRAFT_STONE_AXE",
		name = "돌 도끼 제작",
		category = "TOOL",
		craftTime = 3,
		inputs = {
			{ itemId = "STONE", count = 2 },
			{ itemId = "WOOD", count = 3 },
			{ itemId = "FIBER", count = 5 },
		},
		outputs = {
			{ itemId = "STONE_AXE", count = 1 },
		},
	},
}

return RecipeData
