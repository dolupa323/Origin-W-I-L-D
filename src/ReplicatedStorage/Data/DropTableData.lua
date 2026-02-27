-- DropTableData.lua
-- 크리처 드롭 아이템 데이터 정의
-- ※ 실제 모델이 있는 크리처만 등록

local DropTableData = {
	--========================================
	-- 초식 / PASSIVE
	--========================================
	["DODO"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 1 },
	},
	["COMPY"] = {
		{ itemId = "MEAT", chance = 0.8, min = 1, max = 1 },
		{ itemId = "LEATHER", chance = 0.3, min = 1, max = 1 },
	},
	["PARASAUR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 6 },
		{ itemId = "LEATHER", chance = 0.8, min = 2, max = 4 },
	},

	--========================================
	-- 초식 / NEUTRAL
	--========================================
	["TRICERATOPS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 8 },
		{ itemId = "LEATHER", chance = 0.9, min = 3, max = 5 },
		{ itemId = "HORN", chance = 0.3, min = 1, max = 1 },
	},
	["STEGOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 7 },
		{ itemId = "LEATHER", chance = 0.8, min = 3, max = 5 },
		{ itemId = "BONE", chance = 0.4, min = 1, max = 2 },
	},
	["ANKYLOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 5 },
		{ itemId = "LEATHER", chance = 0.7, min = 2, max = 4 },
		{ itemId = "BONE", chance = 0.5, min = 2, max = 3 },
		{ itemId = "IRON_ORE", chance = 0.2, min = 1, max = 2 },
	},

	--========================================
	-- 육식 / AGGRESSIVE
	--========================================
	["RAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "LEATHER", chance = 0.6, min = 1, max = 2 },
		{ itemId = "BONE", chance = 0.3, min = 1, max = 1 },
	},
	["TREX"] = {
		{ itemId = "MEAT", chance = 1.0, min = 8, max = 15 },
		{ itemId = "LEATHER", chance = 1.0, min = 5, max = 8 },
		{ itemId = "BONE", chance = 0.8, min = 3, max = 6 },
		{ itemId = "HORN", chance = 0.4, min = 1, max = 2 },
	},
}

return DropTableData
