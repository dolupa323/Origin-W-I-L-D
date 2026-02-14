-- DropTableData.lua
-- 드롭 테이블 데이터 정의
-- 형태: 배열 { {id="...", drops={...}}, ... }

local DropTableData = {
	-- 돌 노드 드롭
	{
		id = "STONE_NODE",
		drops = {
			{ itemId = "STONE", countMin = 1, countMax = 3, weight = 100 },
			{ itemId = "FLINT", countMin = 1, countMax = 1, weight = 20 },
		},
	},
	-- 나무 노드 드롭
	{
		id = "TREE_NODE",
		drops = {
			{ itemId = "WOOD", countMin = 2, countMax = 5, weight = 100 },
		},
	},
	-- 풀 노드 드롭
	{
		id = "BUSH_NODE",
		drops = {
			{ itemId = "FIBER", countMin = 1, countMax = 3, weight = 100 },
		},
	},
}

return DropTableData
