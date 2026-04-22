-- DropTableData.lua
-- 크리처 드롭 아이템 데이터 정의
-- ※ 실제 모델이 있는 크리처만 등록

local DropTableData = {
	--========================================
	-- 초식 / PASSIVE
	--========================================
	["ARCHAEOPTERYX"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "FEATHER", chance = 0.8, min = 1, max = 3 },
	},
	["TROODON"] = {
		{ itemId = "MEAT", chance = 0.8, min = 1, max = 1 },
		{ itemId = "SMALL_BONE", chance = 0.6, min = 1, max = 2 },
	},
	["PARASAUR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 6 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.7, min = 2, max = 4 },
	},

	--========================================
	-- 초식 / NEUTRAL
	--========================================
	["TRICERATOPS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 8 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.8, min = 3, max = 6 },
		{ itemId = "HORN", chance = 0.3, min = 1, max = 1 },
	},
	["OLOROTITAN"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "LEATHER", chance = 1.0, min = 1, max = 3 },
	},
	["STEGOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 7 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.8, min = 3, max = 5 },
		{ itemId = "BONE", chance = 0.4, min = 1, max = 2 },
	},
	["TITANOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 10, max = 20 },
		{ itemId = "BONE", chance = 1.0, min = 5, max = 10 },
		{ itemId = "IRON_ORE", chance = 0.5, min = 2, max = 4 },
	},

	--========================================
	-- 육식 / AGGRESSIVE
	--========================================
	["RAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.6, min = 2, max = 3 },
		{ itemId = "BONE", chance = 0.3, min = 1, max = 1 },
		{ itemId = "SHARP_TOOTH", chance = 0.4, min = 1, max = 2 },
	},
	["TREX"] = {
		{ itemId = "MEAT", chance = 1.0, min = 8, max = 15 },
		{ itemId = "BONE", chance = 0.8, min = 3, max = 6 },
		{ itemId = "HORN", chance = 0.4, min = 1, max = 2 },
	},
	["ALLOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 5, max = 10 },
		{ itemId = "BONE", chance = 1.0, min = 2, max = 4 },
		{ itemId = "SHARP_TOOTH", chance = 0.8, min = 2, max = 5 },
	},
	["UTAH_RAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "LEATHER", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BONE", chance = 0.5, min = 1, max = 1 },
	},
}

return DropTableData
