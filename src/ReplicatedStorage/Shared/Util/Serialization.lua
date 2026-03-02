-- Serialization.lua
-- 데이터를 DataStore에 저장 가능한 형식으로 변환하거나 복구하는 유틸리티

local Serialization = {}

--- 테이블이 순차적인 배열(Array) 형태인지 확인 (인덱스 순서 및 길이 보존)
local function isArray(t)
	if type(t) ~= "table" then return false end
	local count = 0
	for k, _ in pairs(t) do
		if type(k) ~= "number" then return false end
		count += 1
	end
	return count == #t
end

--- 데이터를 JSON 저장이 가능한 형식으로 변환 (Vector3, CFrame 등 처리)
function Serialization.serialize(data: any): any
	local dataType = typeof(data)
	
	if dataType == "Vector3" then
		return { __type = "Vector3", x = data.X, y = data.Y, z = data.Z }
	elseif dataType == "CFrame" then
		return { __type = "CFrame", components = { data:GetComponents() } }
	elseif dataType == "Color3" then
		return { __type = "Color3", r = data.R, g = data.G, b = data.B }
	elseif dataType == "table" then
		local result = {}
		
		if isArray(data) then
			-- 배열(Array) 직렬화: 연속된 순서(1, 2, 3...) 보장 및 hash 변질 방지
			for i = 1, #data do
				result[i] = Serialization.serialize(data[i])
			end
		else
			-- 딕셔너리(Dictionary) 직렬화
			for k, v in pairs(data) do
				-- 키와 값 모두 직렬화 (키가 Enum 등일 경우 대비)
				result[Serialization.serialize(k)] = Serialization.serialize(v)
			end
		end
		
		return result
	else
		return data
	end
end

--- 저장된 형식을 원래의 데이터 타입으로 복구
function Serialization.deserialize(data: any): any
	if type(data) ~= "table" then
		return data
	end
	
	if data.__type == "Vector3" then
		return Vector3.new(data.x, data.y, data.z)
	elseif data.__type == "CFrame" then
		return CFrame.new(table.unpack(data.components))
	elseif data.__type == "Color3" then
		return Color3.new(data.r, data.g, data.b)
	else
		local result = {}
		
		if isArray(data) then
			-- 배열 역직렬화
			for i = 1, #data do
				result[i] = Serialization.deserialize(data[i])
			end
		else
			-- 딕셔너리 역직렬화
			for k, v in pairs(data) do
				-- JSON 변환기로 인해 숫자 인덱스(1, 2)가 문자열("1", "2")로 강제 캐스팅된 경우, 원상 복구 시도
				local numKey = tonumber(k)
				if type(k) == "string" and numKey and tostring(numKey) == k then
					k = numKey
				end
				
				result[Serialization.deserialize(k)] = Serialization.deserialize(v)
			end
		end
		
		return result
	end
end

return Serialization
