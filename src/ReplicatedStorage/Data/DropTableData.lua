-- DropTableData.lua
-- Phase 3-3: 크리처 드롭 아이템 데이터 정의

local DropTableData = {
	["RAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "LEATHER", chance = 0.5, min = 1, max = 2 },
	},
	["TRICERATOPS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 5 },
		{ itemId = "LEATHER", chance = 0.8, min = 2, max = 4 },
		{ itemId = "HORN", chance = 0.3, min = 1, max = 1 }, -- 희귀
	},
	["DODO"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 1 },
		{ itemId = "FEATHER", chance = 0.7, min = 1, max = 3 },
	},
}

return DropTableData
