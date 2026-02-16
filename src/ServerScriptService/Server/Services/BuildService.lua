-- BuildService.lua
-- 건설 서비스 (서버 권위, SSOT)
-- Cap: Balance.BUILD_STRUCTURE_CAP (500)
-- Range: Balance.BUILD_RANGE (20)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local BuildService = {}

--========================================
-- Dependencies
--========================================
local initialized = false
local NetController = nil
local DataService = nil
local InventoryService = nil
local SaveService = nil
local FacilityService = nil  -- SetFacilityService로 주입 (Phase 6 버그픽스)
local BaseClaimService = nil -- SetBaseClaimService로 주입 (Phase 7)
local TechService = nil      -- Phase 6 연동
local PlayerStatService = nil -- Phase 6 연동

--========================================
-- Private State
--========================================
-- structures[structureId] = { id, facilityId, position, rotation, health, ownerId, placedAt }
local structures = {}
local structureCount = 0

-- Quest callback (Phase 8)
local questCallback = nil

-- Workspace 폴더
local facilitiesFolder = nil

--========================================
-- Internal: ID 생성
--========================================
local function generateStructureId(): string
	return "struct_" .. HttpService:GenerateGUID(false)
end

--========================================
-- Internal: 거리 계산
--========================================
local function distanceBetween(pos1: Vector3, pos2: Vector3): number
	return (pos1 - pos2).Magnitude
end

--========================================
-- Internal: 충돌 검사
--========================================
local function checkCollision(position: Vector3, facilityId: string): boolean
	local facilityData = DataService.getFacility(facilityId)
	local collisionRadius = Balance.BUILD_COLLISION_RADIUS
	
	-- 기존 구조물과 충돌 검사
	for _, struct in pairs(structures) do
		local dist = distanceBetween(position, struct.position)
		if dist < collisionRadius * 2 then
			return true  -- 충돌
		end
	end
	
	return false  -- 충돌 없음
end

--========================================
-- Internal: 위치 검증
--========================================
local function validatePosition(position: Vector3): (boolean, string?)
	-- 기본 위치 검증 (Y 좌표 체크)
	if position.Y < Balance.BUILD_MIN_GROUND_DIST then
		return false, Enums.ErrorCode.INVALID_POSITION
	end
	
	-- Raycast로 지면 확인 (간이 구현)
	local rayOrigin = position + Vector3.new(0, 5, 0)
	local rayDirection = Vector3.new(0, -10, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { facilitiesFolder }
	
	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if not result then
		return false, Enums.ErrorCode.INVALID_POSITION
	end
	
	return true, nil
end

--========================================
-- Internal: 재료 검증
--========================================
local function validateRequirements(userId: number, requirements: any): (boolean, string?)
	for _, req in ipairs(requirements) do
		if not InventoryService.hasItem(userId, req.itemId, req.amount) then
			return false, Enums.ErrorCode.MISSING_REQUIREMENTS
		end
	end
	return true, nil
end

--========================================
-- Internal: 재료 소모
--========================================
local function consumeRequirements(userId: number, requirements: any)
	for _, req in ipairs(requirements) do
		InventoryService.removeItem(userId, req.itemId, req.amount)
	end
end

--========================================
-- Internal: 이벤트 발행
--========================================
local function emitPlaced(structure: any)
	if NetController then
		NetController.FireAllClients("Build.Placed", {
			id = structure.id,
			facilityId = structure.facilityId,
			position = structure.position,
			rotation = structure.rotation,
			health = structure.health,
			ownerId = structure.ownerId,
		})
	end
end

local function emitRemoved(structureId: string, reason: string)
	if NetController then
		NetController.FireAllClients("Build.Removed", {
			id = structureId,
			reason = reason,
		})
	end
end

local function emitChanged(structureId: string, changes: any)
	if NetController then
		NetController.FireAllClients("Build.Changed", {
			id = structureId,
			changes = changes,
		})
	end
end

--========================================
-- Internal: Cap 관리
--========================================
local function pruneOldestIfNeeded()
	if structureCount < Balance.BUILD_STRUCTURE_CAP then
		return
	end
	
	-- 가장 오래된 구조물 찾기
	local oldest = nil
	local oldestTime = math.huge
	
	for id, struct in pairs(structures) do
		if struct.placedAt < oldestTime then
			oldestTime = struct.placedAt
			oldest = struct
		end
	end
	
	if oldest then
		BuildService.removeStructure(oldest.id, "CAP_PRUNE")
	end
end

--========================================
-- Internal: 구조물 생성 (Workspace)
--========================================
local function spawnFacilityModel(facilityId: string, position: Vector3, rotation: Vector3, structureId: string, ownerId: number): Instance?
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then return nil end
	
	-- 임시 구현: 간단한 Part 생성
	-- 실제로는 ReplicatedStorage.Assets.Facilities에서 모델 복제
	local facility = Instance.new("Part")
	facility.Name = structureId
	facility.Size = Vector3.new(4, 4, 4)
	facility.Position = position
	facility.Anchored = true
	facility.CanCollide = true
	facility.BrickColor = BrickColor.new("Bright orange")
	
	-- 속성 설정
	facility:SetAttribute("FacilityId", facilityId)
	facility:SetAttribute("StructureId", structureId)
	facility:SetAttribute("OwnerId", ownerId)
	facility:SetAttribute("Health", facilityData.maxHealth)
	
	facility.Parent = facilitiesFolder
	
	return facility
end

--========================================
-- Internal: 구조물 제거 (Workspace)
--========================================
local function despawnFacilityModel(structureId: string)
	local facility = facilitiesFolder:FindFirstChild(structureId)
	if facility then
		facility:Destroy()
	end
end

--========================================
-- Public API: Place
--========================================
function BuildService.place(player: Player, facilityId: string, position: Vector3, rotation: Vector3?): (boolean, string?, any?)
	local userId = player.UserId
	local character = player.Character
	
	-- 1. 시설 데이터 검증
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 1a. 기술 해금 검증 (Phase 6)
	if TechService and not TechService.isFacilityUnlocked(userId, facilityId) then
		return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	end
	
	-- 2. 거리 검증 (서버 권위)
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = distanceBetween(hrp.Position, position)
			if dist > Balance.BUILD_RANGE then
				return false, Enums.ErrorCode.OUT_OF_RANGE, nil
			end
		end
	end
	
	-- 3. Cap 검사
	if structureCount >= Balance.BUILD_STRUCTURE_CAP then
		return false, Enums.ErrorCode.STRUCTURE_CAP, nil
	end
	
	-- 4. 충돌 검사
	if checkCollision(position, facilityId) then
		return false, Enums.ErrorCode.COLLISION, nil
	end
	
	-- 5. 위치 검증
	local posOk, posErr = validatePosition(position)
	if not posOk then
		return false, posErr, nil
	end
	
	-- 6. 재료 검증
	local reqOk, reqErr = validateRequirements(userId, facilityData.requirements)
	if not reqOk then
		return false, reqErr, nil
	end
	
	-- === 실행 단계 ===
	
	-- 7. 재료 소모
	consumeRequirements(userId, facilityData.requirements)
	
	-- 8. 구조물 ID 생성
	local structureId = generateStructureId()
	local actualRotation = rotation or Vector3.new(0, 0, 0)
	
	-- 9. 구조물 데이터 저장
	local structure = {
		id = structureId,
		facilityId = facilityId,
		position = position,
		rotation = actualRotation,
		health = facilityData.maxHealth,
		ownerId = userId,
		placedAt = os.time(),
	}
	
	structures[structureId] = structure
	structureCount = structureCount + 1
	
	-- 10. Workspace에 모델 생성
	local model = spawnFacilityModel(facilityId, position, actualRotation, structureId, userId)
	
	-- 11. 이벤트 발행
	emitPlaced(structure)
	
	-- 11a. 경험치 보상 (Phase 6)
	if PlayerStatService then
		PlayerStatService.addXP(userId, Balance.XP_BUILD or 30, "BUILD")
	end
	
	-- 11b. 퀘스트 콜백 (Phase 8)
	if questCallback then
		questCallback(userId, facilityId)
	end
	
	-- 12. FacilityService에 등록 (Lazy Update 상태 관리용)
	if FacilityService and FacilityService.register then
		FacilityService.register(structureId, facilityId, userId)
	end
	
	-- 13. SaveService에 구조물 영속화
	if SaveService and SaveService.updateWorldState then
		SaveService.updateWorldState(function(state)
			if not state.structures then
				state.structures = {}
			end
			state.structures[structureId] = structure
			return state
		end)
	end
	
	-- 14. BaseClaimService 연동: 첫 건물 설치 시 베이스 자동 생성 (Phase 7)
	if BaseClaimService and BaseClaimService.onStructurePlaced then
		BaseClaimService.onStructurePlaced(userId, position)
	end
	
	print(string.format("[BuildService] Placed %s at (%.1f, %.1f, %.1f) by player %d", 
		facilityId, position.X, position.Y, position.Z, userId))
	
	return true, nil, {
		structureId = structureId,
		facilityId = facilityId,
		position = position,
	}
end

--========================================
-- Public API: Remove
--========================================
function BuildService.remove(player: Player, structureId: string): (boolean, string?, any?)
	local userId = player.UserId
	local character = player.Character
	
	-- 1. 구조물 존재 확인
	local structure = structures[structureId]
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 2. 거리 검증
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = distanceBetween(hrp.Position, structure.position)
			if dist > Balance.BUILD_RANGE then
				return false, Enums.ErrorCode.OUT_OF_RANGE, nil
			end
		end
	end
	
	-- 3. 권한 검증 (소유자만 해체 가능)
	if structure.ownerId ~= userId then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	-- === 실행 단계 ===
	BuildService.removeStructure(structureId, "PLAYER_REMOVE")
	
	print(string.format("[BuildService] Removed %s by player %d", structureId, userId))
	
	return true, nil, { structureId = structureId }
end

--========================================
-- Public API: 내부 제거 (CAP/파괴 등)
--========================================
function BuildService.removeStructure(structureId: string, reason: string)
	local structure = structures[structureId]
	if not structure then return end
	
	-- FacilityService에서 등록 해제 (팰 배치 해제 등)
	if FacilityService and FacilityService.unregister then
		FacilityService.unregister(structureId)
	end
	
	-- Workspace에서 제거
	despawnFacilityModel(structureId)
	
	-- 데이터 제거
	structures[structureId] = nil
	structureCount = structureCount - 1
	
	-- SaveService에서 구조물 제거
	if SaveService and SaveService.updateWorldState then
		SaveService.updateWorldState(function(state)
			if state.structures then
				state.structures[structureId] = nil
			end
			return state
		end)
	end
	
	-- 이벤트 발행
	emitRemoved(structureId, reason)
end

--========================================
-- Public API: GetAll
--========================================
function BuildService.getAll(): {any}
	local result = {}
	for _, struct in pairs(structures) do
		table.insert(result, {
			id = struct.id,
			facilityId = struct.facilityId,
			position = struct.position,
			rotation = struct.rotation,
			health = struct.health,
			ownerId = struct.ownerId,
		})
	end
	return result
end

--========================================
-- Public API: Get
--========================================
function BuildService.get(structureId: string): any?
	return structures[structureId]
end

--========================================
-- Public API: GetCount
--========================================
function BuildService.getCount(): number
	return structureCount
end

--========================================
-- Network Handlers
--========================================

local function handlePlace(player: Player, payload: any)
	local facilityId = payload.facilityId
	local position = payload.position
	local rotation = payload.rotation
	
	-- Vector3 변환 (클라이언트에서 테이블로 올 수 있음)
	if type(position) == "table" then
		position = Vector3.new(position.X or position.x or 0, position.Y or position.y or 0, position.Z or position.z or 0)
	end
	if rotation and type(rotation) == "table" then
		rotation = Vector3.new(rotation.X or rotation.x or 0, rotation.Y or rotation.y or 0, rotation.Z or rotation.z or 0)
	end
	
	local success, errorCode, data = BuildService.place(player, facilityId, position, rotation)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleRemove(player: Player, payload: any)
	local structureId = payload.structureId
	
	local success, errorCode, data = BuildService.remove(player, structureId)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleGetAll(player: Player, payload: any)
	local all = BuildService.getAll()
	return { success = true, data = { structures = all } }
end

--========================================
-- Initialization
--========================================

function BuildService.Init(netController: any, dataService: any, inventoryService: any, saveService: any, techService: any, playerStatService: any)
	if initialized then
		warn("[BuildService] Already initialized")
		return
	end
	
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	SaveService = saveService
	TechService = techService
	PlayerStatService = playerStatService
	
	-- Workspace 폴더 생성
	facilitiesFolder = workspace:FindFirstChild("Facilities")
	if not facilitiesFolder then
		facilitiesFolder = Instance.new("Folder")
		facilitiesFolder.Name = "Facilities"
		facilitiesFolder.Parent = workspace
	end
	
	-- 월드 상태에서 구조물 로드 (영속화)
	local worldState = saveService.getWorldState()
	if worldState and worldState.structures then
		for structureId, struct in pairs(worldState.structures) do
			structures[structureId] = struct
			structureCount = structureCount + 1
			
			-- Workspace에 모델 생성
			local pos = struct.position
			if type(pos) == "table" then
				pos = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
			end
			local rot = struct.rotation
			if type(rot) == "table" then
				rot = Vector3.new(rot.X or rot.x or 0, rot.Y or rot.y or 0, rot.Z or rot.z or 0)
			end
			spawnFacilityModel(struct.facilityId, pos, rot, structureId, struct.ownerId)
		end
		print(string.format("[BuildService] Loaded %d structures from WorldState", structureCount))
	else
		-- 초기화
		if worldState then
			worldState.structures = {}
		end
	end
	
	initialized = true
	print(string.format("[BuildService] Initialized - Cap: %d, Range: %d", 
		Balance.BUILD_STRUCTURE_CAP, Balance.BUILD_RANGE))
end

--- FacilityService 의존성 주입 (ServerInit에서 FacilityService Init 후 호출)
function BuildService.SetFacilityService(facilityService)
	FacilityService = facilityService
	
	-- 이미 로드된 구조물들 FacilityService에 등록
	if facilityService and facilityService.register then
		for structureId, struct in pairs(structures) do
			facilityService.register(structureId, struct.facilityId, struct.ownerId)
		end
		print(string.format("[BuildService] Registered %d structures to FacilityService", structureCount))
	end
end

--- BaseClaimService 의존성 주입 (Phase 7)
function BuildService.SetBaseClaimService(baseClaimService)
	BaseClaimService = baseClaimService
end

function BuildService.GetHandlers()
	return {
		["Build.Place.Request"] = handlePlace,
		["Build.Remove.Request"] = handleRemove,
		["Build.GetAll.Request"] = handleGetAll,
	}
end

--========================================
-- Debug API
--========================================

--- 디버그: 모든 구조물 제거
function BuildService.clearAll()
	for structureId, _ in pairs(structures) do
		BuildService.removeStructure(structureId, "DEBUG_CLEAR")
	end
	print("[BuildService] Debug: Cleared all structures")
end

--- 퀘스트 콜백 설정 (Phase 8)
function BuildService.SetQuestCallback(callback)
	questCallback = callback
end

return BuildService
