-- DataHelper.lua
-- 클라이언트와 서버에서 공통으로 사용하는 데이터 조회 유틸리티

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = ReplicatedStorage:WaitForChild("Data")
local Validator = require(Shared.Types.Validator)

local DataHelper = {}

-- 로컬 캐시 (맵 형태로 변환된 데이터)
local tableCache = {}

--- 특정 테이블 조회 및 캐싱
function DataHelper.GetTable(tableName: string)
	if tableCache[tableName] then
		return tableCache[tableName]
	end
	
	local module = Data:FindFirstChild(tableName)
	if module and module:IsA("ModuleScript") then
		local data = require(module)
		-- Validator를 사용하여 맵 형태로 변환 (ID 중복 체크 포함)
		local mapData = Validator.validateIdTable(data, tableName)
		tableCache[tableName] = mapData
		return mapData
	end
	
	warn("[DataHelper] Table not found:", tableName)
	return nil
end

--- 특정 테이블에서 ID로 항목 조회
function DataHelper.GetData(tableName: string, id: string)
	local tbl = DataHelper.GetTable(tableName)
	if tbl then
		return tbl[id]
	end
	return nil
end

return DataHelper
