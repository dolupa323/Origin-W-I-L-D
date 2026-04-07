-- DropTableData.lua
-- 크리처 드롭 아이템 데이터 정의
-- ※ 실제 모델이 있는 크리처만 등록
-- DNA 드랍: 약한 크리처일수록 높은 확률, 강한 크리처일수록 낮은 확률

local DropTableData = {
	--========================================
	-- 초식 / PASSIVE
	--========================================
	["DODO"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "DODO_FEATHER", chance = 0.8, min = 1, max = 3 },
		{ itemId = "DODO_DNA", chance = 0.25, min = 1, max = 1 },
	},
	["COMPY"] = {
		{ itemId = "MEAT", chance = 0.8, min = 1, max = 1 },
		{ itemId = "SMALL_BONE", chance = 0.6, min = 1, max = 2 },
		{ itemId = "COMPY_DNA", chance = 0.20, min = 1, max = 1 },
	},
	["PARASAUR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 6 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.7, min = 2, max = 4 },
		{ itemId = "PARASAUR_DNA", chance = 0.15, min = 1, max = 1 },
	},

	--========================================
	-- 초식 / NEUTRAL
	--========================================
	["TRICERATOPS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 8 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.8, min = 3, max = 6 },
		{ itemId = "HORN", chance = 0.3, min = 1, max = 1 },
		{ itemId = "TRICERATOPS_DNA", chance = 0.08, min = 1, max = 1 },
	},
	["BABY_TRICERATOPS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "LEATHER", chance = 1.0, min = 4, max = 7 },
		{ itemId = "HORN", chance = 0.1, min = 1, max = 1 },
		{ itemId = "BABY_TRICERATOPS_DNA", chance = 0.15, min = 1, max = 1 },
	},
	["STEGOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 7 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.8, min = 3, max = 5 },
		{ itemId = "BONE", chance = 0.4, min = 1, max = 2 },
		{ itemId = "STEGOSAURUS_DNA", chance = 0.08, min = 1, max = 1 },
	},
	["ANKYLOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 5 },
		{ itemId = "BONE", chance = 0.5, min = 2, max = 3 },
		{ itemId = "IRON_ORE", chance = 0.2, min = 1, max = 2 },
		{ itemId = "ANKYLOSAURUS_DNA", chance = 0.06, min = 1, max = 1 },
	},

	--========================================
	-- 육식 / AGGRESSIVE
	--========================================
	["RAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.6, min = 2, max = 3 },
		{ itemId = "BONE", chance = 0.3, min = 1, max = 1 },
		{ itemId = "SHARP_TOOTH", chance = 0.4, min = 1, max = 2 },
		{ itemId = "RAPTOR_DNA", chance = 0.10, min = 1, max = 1 },
	},
	["TREX"] = {
		{ itemId = "MEAT", chance = 1.0, min = 8, max = 15 },
		{ itemId = "BONE", chance = 0.8, min = 3, max = 6 },
		{ itemId = "HORN", chance = 0.4, min = 1, max = 2 },
		{ itemId = "TREX_DNA", chance = 0.03, min = 1, max = 1 },
	},
}

return DropTableData
