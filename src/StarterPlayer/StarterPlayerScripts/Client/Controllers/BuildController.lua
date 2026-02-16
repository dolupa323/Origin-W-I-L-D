-- BuildController.lua
-- 클라이언트 건설 컨트롤러
-- 서버 Build 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local BuildController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 구조물 캐시 [structureId] = { id, facilityId, position, rotation, health, ownerId }
local structuresCache = {}
local structureCount = 0

--========================================
-- Public API: Cache Access
--========================================

function BuildController.getStructuresCache()
	return structuresCache
end

function BuildController.getStructure(structureId: string)
	return structuresCache[structureId]
end

function BuildController.getStructureCount(): number
	return structureCount
end

--========================================
-- Public API: Build Requests
--========================================

--- 건설 요청 (시설물 배치)
function BuildController.requestPlace(facilityId: string, position: Vector3, rotation: Vector3?): (boolean, any)
	print(string.format("[BuildController] Requesting build: %s at (%.1f, %.1f, %.1f)", 
		facilityId, position.X, position.Y, position.Z))
	
	local success, data = NetClient.Request("Build.Place.Request", {
		facilityId = facilityId,
		position = position,
		rotation = rotation or Vector3.new(0, 0, 0),
	})
	
	if not success then
		warn("[BuildController] Build request failed:", data)
	else
		print("[BuildController] Build request success:", data)
	end
	
	return success, data
end

--- 해체 요청 (시설물 제거)
function BuildController.requestRemove(structureId: string): (boolean, any)
	print(string.format("[BuildController] Requesting remove: %s", structureId))
	
	local success, data = NetClient.Request("Build.Remove.Request", {
		structureId = structureId,
	})
	
	if not success then
		warn("[BuildController] Remove request failed:", data)
	end
	
	return success, data
end

--- 전체 구조물 조회 요청
function BuildController.requestGetAll(): (boolean, any)
	local success, data = NetClient.Request("Build.GetAll.Request", {})
	
	if success and data and data.structures then
		-- 캐시 동기화
		structuresCache = {}
		structureCount = 0
		for _, struct in ipairs(data.structures) do
			structuresCache[struct.id] = struct
			structureCount = structureCount + 1
		end
		print(string.format("[BuildController] Synced %d structures", structureCount))
	end
	
	return success, data
end

--========================================
-- Event Handlers
--========================================

local function onPlaced(data)
	if not data or not data.id then return end
	
	structuresCache[data.id] = {
		id = data.id,
		facilityId = data.facilityId,
		position = data.position,
		rotation = data.rotation,
		health = data.health,
		ownerId = data.ownerId,
	}
	structureCount = structureCount + 1
	
	-- 디버그 로그
	print(string.format("[BuildController] Placed: %s (%s)", data.id, data.facilityId))
end

local function onRemoved(data)
	if not data or not data.id then return end
	
	local structure = structuresCache[data.id]
	if structure then
		structuresCache[data.id] = nil
		structureCount = structureCount - 1
		
		print(string.format("[BuildController] Removed: %s (reason: %s)", data.id, data.reason or "unknown"))
	end
end

local function onChanged(data)
	if not data or not data.id then return end
	
	local structure = structuresCache[data.id]
	if not structure then return end
	
	-- 변경 사항 적용
	if data.changes then
		for key, value in pairs(data.changes) do
			structure[key] = value
		end
	end
	
	-- 디버그 로그 (주석 처리)
	-- print(string.format("[BuildController] Changed: %s", data.id))
end

--========================================
-- Initialization
--========================================

function BuildController.Init()
	if initialized then return end
	
	-- 이벤트 리스너 등록
	NetClient.On("Build.Placed", onPlaced)
	NetClient.On("Build.Removed", onRemoved)
	NetClient.On("Build.Changed", onChanged)
	
	initialized = true
	print("[BuildController] Initialized")
end

return BuildController
