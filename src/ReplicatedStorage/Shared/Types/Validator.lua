-- Validator.lua
-- 타입 검증 유틸리티 (규격 확정)
-- Data가 비정상이면 서버 부팅 실패를 유발할 수 있음

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local Validator = {}

--========================================
-- 기본 타입 검사
--========================================

--- 테이블인지 확인
function Validator.isTable(x): boolean
	return type(x) == "table"
end

--- 문자열인지 확인
function Validator.isString(x): boolean
	return type(x) == "string"
end

--- 숫자인지 확인
function Validator.isNumber(x): boolean
	return type(x) == "number"
end

--- 정수인지 확인
function Validator.isInteger(x): boolean
	return type(x) == "number" and x == math.floor(x)
end

--- 양수인지 확인
function Validator.isPositive(x): boolean
	return type(x) == "number" and x > 0
end

--- nil이 아닌지 확인
function Validator.exists(x): boolean
	return x ~= nil
end

--========================================
-- 조건 검증 (실패 시 error)
--========================================

--- 조건이 false면 에러 발생
--- @param condition boolean 검증할 조건
--- @param code string? 에러코드 (Enums.ErrorCode)
--- @param message string? 상세 메시지
function Validator.assert(condition: boolean, code: string?, message: string?)
	if not condition then
		local errorCode = code or Enums.ErrorCode.BAD_REQUEST
		local errorMsg = message or "Validation failed"
		error(string.format("[%s] %s", errorCode, errorMsg), 2)
	end
end

--- 소프트 검증 (에러 대신 false 반환)
--- @return boolean, string?
function Validator.check(condition: boolean, code: string?, message: string?): (boolean, string?)
	if not condition then
		return false, code or Enums.ErrorCode.BAD_REQUEST
	end
	return true, nil
end

--========================================
-- 데이터 구조 검증
--========================================

--- ID 맵 검증 (map[id] = record 형태)
--- @param map table 검증할 맵
--- @param what string 맵 이름 (에러 메시지용)
--- @return boolean 검증 성공 여부
function Validator.validateIdMap(map: any, what: string): boolean
	Validator.assert(Validator.isTable(map), Enums.ErrorCode.BAD_REQUEST, 
		string.format("%s must be a table", what))
	
	local seenIds = {}
	
	for id, record in pairs(map) do
		-- ID는 문자열이어야 함
		Validator.assert(Validator.isString(id), Enums.ErrorCode.BAD_REQUEST,
			string.format("%s: id must be string, got %s", what, type(id)))
		
		-- ID는 비어있으면 안 됨
		Validator.assert(#id > 0, Enums.ErrorCode.BAD_REQUEST,
			string.format("%s: id cannot be empty", what))
		
		-- ID 중복 체크
		Validator.assert(not seenIds[id], Enums.ErrorCode.BAD_REQUEST,
			string.format("%s: duplicate id '%s'", what, id))
		
		-- 레코드는 테이블이어야 함
		Validator.assert(Validator.isTable(record), Enums.ErrorCode.BAD_REQUEST,
			string.format("%s[%s]: record must be a table", what, id))
		
		seenIds[id] = true
	end
	
	return true
end

--- 필수 필드 검증
--- @param record table 검증할 레코드
--- @param fields table 필수 필드 목록 {"field1", "field2"}
--- @param what string 레코드 이름
function Validator.validateRequired(record: any, fields: {string}, what: string)
	Validator.assert(Validator.isTable(record), Enums.ErrorCode.BAD_REQUEST,
		string.format("%s must be a table", what))
	
	for _, field in ipairs(fields) do
		Validator.assert(record[field] ~= nil, Enums.ErrorCode.BAD_REQUEST,
			string.format("%s: missing required field '%s'", what, field))
	end
end

--- 참조 검증 (다른 데이터 테이블의 ID 참조)
--- @param refId string 참조할 ID
--- @param sourceTable table 참조 대상 테이블 (맵 형태)
--- @param what string 설명
--- @param failFast boolean? true면 실패 시 error (기본 true)
function Validator.validateRefs(refId: string?, sourceTable: any?, what: string?, failFast: boolean?): boolean
	if refId == nil then
		return true -- nil 참조는 허용 (옵션 필드)
	end
	
	if sourceTable == nil then
		if failFast ~= false then
			error(string.format("[DataService] %s: sourceTable not provided", what or "unknown"))
		end
		return false
	end
	
	local exists = sourceTable[refId] ~= nil
	
	if not exists and failFast ~= false then
		error(string.format("[DataService] %s: reference '%s' not found", what or "unknown", refId))
	end
	
	return exists
end

--========================================
-- Data Table 검증 (Phase 1-4)
--========================================

--- ID 테이블 검증 (배열형 또는 맵형 지원)
--- 배열형: { {id="STONE", ...}, {id="WOOD", ...} }
--- 맵형: { STONE = {id="STONE", ...}, WOOD = {id="WOOD", ...} }
--- @param records table 검증할 테이블
--- @param what string 테이블 이름
--- @param requiredFields table? 필수 필드 목록
--- @return table 맵 형태로 변환된 테이블 {id = record}
function Validator.validateIdTable(records: any, what: string, requiredFields: {string}?): {[string]: any}
	Validator.assert(Validator.isTable(records), Enums.ErrorCode.BAD_REQUEST,
		string.format("%s must be a table", what))
	
	local seenIds = {}
	local resultMap = {}
	local isArray = (#records > 0) or next(records) == nil
	
	-- 배열인지 맵인지 판단
	for k, _ in pairs(records) do
		if type(k) ~= "number" then
			isArray = false
			break
		end
	end
	
	if isArray then
		-- 배열형 처리
		for index, record in ipairs(records) do
			Validator.assert(Validator.isTable(record), Enums.ErrorCode.BAD_REQUEST,
				string.format("%s[%d]: record must be a table", what, index))
			
			local id = record.id
			
			-- id 필드 필수
			Validator.assert(id ~= nil, Enums.ErrorCode.BAD_REQUEST,
				string.format("%s[%d]: missing 'id' field", what, index))
			
			-- id는 문자열
			Validator.assert(Validator.isString(id), Enums.ErrorCode.BAD_REQUEST,
				string.format("%s[%d]: id must be string, got %s", what, index, type(id)))
			
			-- id 비어있으면 안 됨
			Validator.assert(#id > 0, Enums.ErrorCode.BAD_REQUEST,
				string.format("%s[%d]: id cannot be empty", what, index))
			
			-- id 중복 체크
			Validator.assert(not seenIds[id], Enums.ErrorCode.BAD_REQUEST,
				string.format("%s: duplicate id '%s'", what, id))
			
			-- 필수 필드 체크
			if requiredFields then
				for _, field in ipairs(requiredFields) do
					Validator.assert(record[field] ~= nil, Enums.ErrorCode.BAD_REQUEST,
						string.format("%s[%s]: missing required field '%s'", what, id, field))
				end
			end
			
			seenIds[id] = true
			resultMap[id] = record
		end
	else
		-- 맵형 처리
		for id, record in pairs(records) do
			-- id(키)는 문자열
			Validator.assert(Validator.isString(id), Enums.ErrorCode.BAD_REQUEST,
				string.format("%s: key must be string, got %s", what, type(id)))
			
			-- id 비어있으면 안 됨
			Validator.assert(#id > 0, Enums.ErrorCode.BAD_REQUEST,
				string.format("%s: key cannot be empty", what))
			
			-- 레코드는 테이블
			Validator.assert(Validator.isTable(record), Enums.ErrorCode.BAD_REQUEST,
				string.format("%s[%s]: record must be a table", what, id))
			
			-- id 중복 체크 (맵형에서는 자동으로 불가능하지만 안전장치)
			Validator.assert(not seenIds[id], Enums.ErrorCode.BAD_REQUEST,
				string.format("%s: duplicate id '%s'", what, id))
			
			-- 레코드에 id 필드가 있다면 키와 일치해야 함
			if record.id ~= nil then
				Validator.assert(record.id == id, Enums.ErrorCode.BAD_REQUEST,
					string.format("%s[%s]: record.id '%s' does not match key", what, id, tostring(record.id)))
			end
			
			-- 필수 필드 체크
			if requiredFields then
				for _, field in ipairs(requiredFields) do
					Validator.assert(record[field] ~= nil, Enums.ErrorCode.BAD_REQUEST,
						string.format("%s[%s]: missing required field '%s'", what, id, field))
				end
			end
			
			seenIds[id] = true
			resultMap[id] = record
			resultMap[id].id = id  -- id 필드 보장
		end
	end
	
	return resultMap
end

--- Recipe → Item 참조 검증
--- @param recipes table 레시피 맵 {id = recipe}
--- @param items table 아이템 맵 {id = item}
--- @param what string 테이블 이름
function Validator.validateRecipeRefs(recipes: {[string]: any}, items: {[string]: any}, what: string)
	for recipeId, recipe in pairs(recipes) do
		-- inputs 참조 검증
		if recipe.inputs then
			for i, input in ipairs(recipe.inputs) do
				if input.itemId then
					Validator.assert(items[input.itemId] ~= nil, Enums.ErrorCode.BAD_REQUEST,
						string.format("%s[%s].inputs[%d]: itemId '%s' not found in ItemData", 
							what, recipeId, i, input.itemId))
				end
			end
		end
		
		-- outputs 참조 검증
		if recipe.outputs then
			for i, output in ipairs(recipe.outputs) do
				if output.itemId then
					Validator.assert(items[output.itemId] ~= nil, Enums.ErrorCode.BAD_REQUEST,
						string.format("%s[%s].outputs[%d]: itemId '%s' not found in ItemData", 
							what, recipeId, i, output.itemId))
				end
			end
		end
	end
end

--- DropTable → Item 참조 검증
--- @param dropTables table 드롭테이블 맵
--- @param items table 아이템 맵
--- @param what string 테이블 이름
function Validator.validateDropTableRefs(dropTables: {[string]: any}, items: {[string]: any}, what: string)
	for tableId, dropTable in pairs(dropTables) do
		-- dropTable이 직접 배열이거나 { drops = {...} } 구조일 수 있음
		local drops = dropTable.drops or dropTable
		
		if type(drops) == "table" then
			for i, drop in ipairs(drops) do
				if drop.itemId then
					Validator.assert(items[drop.itemId] ~= nil, Enums.ErrorCode.BAD_REQUEST,
						string.format("%s[%s].drops[%d]: itemId '%s' not found in ItemData", 
							what, tableId, i, drop.itemId))
				end
			end
		end
	end
end

--- 범위 검증
--- @param value number 검증할 값
--- @param min number 최소값
--- @param max number 최대값
--- @param what string 필드 이름
function Validator.validateRange(value: number, min: number, max: number, what: string)
	Validator.assert(Validator.isNumber(value), Enums.ErrorCode.BAD_REQUEST,
		string.format("%s must be a number", what))
	Validator.assert(value >= min and value <= max, Enums.ErrorCode.OUT_OF_RANGE,
		string.format("%s must be between %d and %d, got %d", what, min, max, value))
end

--- Enum 값 검증
--- @param value any 검증할 값
--- @param enumTable table Enum 테이블
--- @param what string 필드 이름
function Validator.validateEnum(value: any, enumTable: any, what: string)
	local found = false
	for _, v in pairs(enumTable) do
		if v == value then
			found = true
			break
		end
	end
	Validator.assert(found, Enums.ErrorCode.BAD_REQUEST,
		string.format("%s: invalid enum value '%s'", what, tostring(value)))
end

return Validator
