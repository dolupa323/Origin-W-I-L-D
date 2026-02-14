-- DataService.lua
-- 데이터 로드 및 검증 서비스
-- 검증 실패 시 error()로 서버 부팅 중단

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = ReplicatedStorage:WaitForChild("Data")

local Validator = require(Shared.Types.Validator)
local Enums = require(Shared.Enums.Enums)

local DataService = {}

--========================================
-- Private State
--========================================
local initialized = false
local tables = {}  -- 로드된 데이터 테이블 (맵 형태로 변환됨)

-- 데이터 테이블 목록 (로드 순서 중요: 의존성 순)
local TABLE_NAMES = {
	"ItemData",           -- 기본 (참조 대상)
	"CreatureData",       -- 기본
	"RecipeData",         -- Item 참조
	"FacilityData",       -- Recipe 참조 가능
	"TechUnlockData",     -- 다양한 참조
	"QuestData",          -- 다양한 참조
	"NPCShopData",        -- Item 참조
	"DropTableData",      -- Item 참조
	"DurabilityProfiles", -- 독립
}

--========================================
-- Internal Functions
--========================================

--- 모든 데이터 테이블 로드
local function _loadAll()
	print("[DataService] Loading data tables...")
	
	for _, tableName in ipairs(TABLE_NAMES) do
		local moduleInstance = Data:FindFirstChild(tableName)
		
		if moduleInstance then
			local success, rawData = pcall(require, moduleInstance)
			
			if not success then
				error(string.format("[DataService] Failed to require %s: %s", tableName, tostring(rawData)))
			end
			
			-- 빈 테이블은 허용
			if rawData == nil or (type(rawData) == "table" and next(rawData) == nil) then
				tables[tableName] = {}
				print(string.format("[DataService] Loaded %s: empty", tableName))
			else
				-- validateIdTable로 검증 + 맵 형태 변환
				local mapData = Validator.validateIdTable(rawData, tableName)
				tables[tableName] = mapData
				
				local count = 0
				for _ in pairs(mapData) do count += 1 end
				print(string.format("[DataService] Loaded %s: %d entries", tableName, count))
			end
		else
			-- 모듈이 없으면 빈 테이블
			tables[tableName] = {}
			warn(string.format("[DataService] %s not found, using empty table", tableName))
		end
	end
end

--- 모든 참조 검증
local function _validateRefs()
	print("[DataService] Validating references...")
	
	local items = tables.ItemData or {}
	local recipes = tables.RecipeData or {}
	local dropTables = tables.DropTableData or {}
	local facilities = tables.FacilityData or {}
	
	-- Recipe → Item 참조 검증
	if next(recipes) then
		Validator.validateRecipeRefs(recipes, items, "RecipeData")
		print("[DataService] RecipeData -> ItemData: OK")
	end
	
	-- DropTable → Item 참조 검증
	if next(dropTables) then
		Validator.validateDropTableRefs(dropTables, items, "DropTableData")
		print("[DataService] DropTableData -> ItemData: OK")
	end
	
	-- Facility → Recipe 참조 검증 (있다면)
	if next(facilities) then
		for facilityId, facility in pairs(facilities) do
			if facility.recipes then
				for i, recipeId in ipairs(facility.recipes) do
					Validator.assert(recipes[recipeId] ~= nil, Enums.ErrorCode.BAD_REQUEST,
						string.format("FacilityData[%s].recipes[%d]: recipeId '%s' not found in RecipeData",
							facilityId, i, recipeId))
				end
			end
		end
		print("[DataService] FacilityData -> RecipeData: OK")
	end
	
	print("[DataService] All references validated")
end

--========================================
-- Public API
--========================================

--- 모든 테이블 반환
function DataService.getTables(): {[string]: {[string]: any}}
	return tables
end

--- 특정 테이블 반환
--- @param tableName string 테이블 이름 ("ItemData", "RecipeData" 등)
--- @return table? 맵 형태 {id = record}
function DataService.get(tableName: string): {[string]: any}?
	return tables[tableName]
end

--- 특정 테이블에서 ID로 조회
--- @param tableName string 테이블 이름
--- @param id string 아이템 ID
--- @return table? 레코드
function DataService.getById(tableName: string, id: string): any
	local tbl = tables[tableName]
	if tbl then
		return tbl[id]
	end
	return nil
end

--- 아이템 조회 (단축)
function DataService.getItem(id: string): any
	return DataService.getById("ItemData", id)
end

--- 레시피 조회 (단축)
function DataService.getRecipe(id: string): any
	return DataService.getById("RecipeData", id)
end

--- 크리처 조회 (단축)
function DataService.getCreature(id: string): any
	return DataService.getById("CreatureData", id)
end

--========================================
-- Initialization
--========================================

function DataService.Init()
	if initialized then
		warn("[DataService] Already initialized")
		return
	end
	
	-- 1. 모든 데이터 로드 + 기본 검증 (id 중복 등)
	_loadAll()
	
	-- 2. 참조 검증 (Recipe -> Item 등)
	_validateRefs()
	
	initialized = true
	print("[DataService] Initialized - All data validated")
end

return DataService
