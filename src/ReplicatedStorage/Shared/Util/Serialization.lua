-- Serialization.lua
-- 데이터를 DataStore에 저장 가능한 형식으로 변환하거나 복구하는 유틸리티

local Serialization = {}

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
		for k, v in pairs(data) do
			-- 키와 값 모두 직렬화 (키가 Enum 등일 경우 대비)
			result[Serialization.serialize(k)] = Serialization.serialize(v)
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
		for k, v in pairs(data) do
			result[Serialization.deserialize(k)] = Serialization.deserialize(v)
		end
		return result
	end
end

return Serialization
