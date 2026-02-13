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
--- Phase 1-4에서 확장 예정
--- @param refId string 참조할 ID
--- @param sourceTable table 참조 대상 테이블
--- @param what string 설명
function Validator.validateRefs(refId: string?, sourceTable: any?, what: string?): boolean
	-- 스텁: Phase 1-4에서 구현
	if refId == nil then
		return true -- nil 참조는 허용 (옵션 필드)
	end
	
	if sourceTable == nil then
		warn("[Validator] validateRefs: sourceTable not provided for", what)
		return true
	end
	
	return sourceTable[refId] ~= nil
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
