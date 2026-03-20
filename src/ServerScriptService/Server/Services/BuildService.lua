-- BuildService.lua
-- 건설 서비스 (서버 권위, SSOT)
-- Cap: Balance.BUILD_STRUCTURE_CAP (500)
-- Range: Balance.BUILD_RANGE (20)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

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
local TotemService = nil     -- SetTotemService로 주입
local TechService = nil      -- Phase 6 연동
local PlayerStatService = nil -- Phase 6 연동
local WorldDropService = nil

--========================================
-- Private State
--========================================
-- structures[structureId] = { id, facilityId, position, rotation, health, ownerId, placedAt }
local structures = {}
local structureCount = 0
local orderedIds = {} -- 설치 순서 기록 (Prune 최적화용)

local ROTATION_STEP_DEG = 45

local DEFAULT_MAX_GROUND_SLOPE_DEG = Balance.BUILD_MAX_GROUND_SLOPE_DEG or 42
local STRICT_MAX_GROUND_SLOPE_DEG = Balance.BUILD_STRICT_MAX_GROUND_SLOPE_DEG or 12
local DEFAULT_MAX_GROUND_GAP = Balance.BUILD_MAX_GROUND_GAP or 3.5
local STRICT_MAX_GROUND_GAP = Balance.BUILD_STRICT_MAX_GROUND_GAP or 1.2

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
	local collisionRadius = Balance.BUILD_COLLISION_RADIUS
	
	-- [최적화] O(N) 순회 대신 공간 쿼리(Spatial Query) 사용
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { facilitiesFolder }
	
	local parts = workspace:GetPartBoundsInRadius(position, collisionRadius * 1.5, overlapParams)
	return #parts > 0
end

local function getPlacementProfile(): string
	local attrProfile = workspace:GetAttribute("BuildPlacementProfile")
	if type(attrProfile) == "string" and attrProfile ~= "" then
		return string.upper(attrProfile)
	end
	return string.upper(Balance.BUILD_PLACEMENT_PROFILE or "DEFAULT")
end

local function isStrictFieldProfile(): boolean
	return getPlacementProfile() == "STRICT_FIELD"
end

local function getMaxGroundSlopeDeg(): number
	if isStrictFieldProfile() then
		return STRICT_MAX_GROUND_SLOPE_DEG
	end
	return DEFAULT_MAX_GROUND_SLOPE_DEG
end

local function getMaxGroundGap(): number
	if isStrictFieldProfile() then
		return STRICT_MAX_GROUND_GAP
	end
	return DEFAULT_MAX_GROUND_GAP
end

local function normalizeYaw(deg: number): number
	local value = deg % 360
	if value < 0 then
		value = value + 360
	end
	return value
end

local function validateRotation(rotation: Vector3?): (boolean, string?, Vector3?)
	local rot = rotation or Vector3.new(0, 0, 0)
	if typeof(rot) ~= "Vector3" then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end

	if math.abs(rot.X) > 1 or math.abs(rot.Z) > 1 then
		return false, Enums.ErrorCode.INVALID_POSITION, nil
	end

	local yaw = normalizeYaw(rot.Y)
	local snapped = math.floor((yaw / ROTATION_STEP_DEG) + 0.5) * ROTATION_STEP_DEG
	local snappedYaw = normalizeYaw(snapped)

	if math.abs(yaw - snappedYaw) > 0.01 and math.abs((yaw + 360) - snappedYaw) > 0.01 then
		return false, Enums.ErrorCode.INVALID_POSITION, nil
	end

	return true, nil, Vector3.new(0, snappedYaw, 0)
end

local function isValidFieldSurface(hitInstance: Instance?, hitNormal: Vector3, hitMaterial: Enum.Material?): boolean
	if not hitInstance then
		return false
	end

	local upDot = hitNormal:Dot(Vector3.new(0, 1, 0))
	local slope = math.deg(math.acos(math.clamp(upDot, -1, 1)))
	if slope > getMaxGroundSlopeDeg() then
		return false
	end

	if hitMaterial == Enum.Material.Water then
		return false
	end

	local strict = isStrictFieldProfile()
	if strict then
		if hitInstance ~= workspace.Terrain then
			return false
		end

		local strictAllowedTerrainMaterial = {
			[Enum.Material.Grass] = true,
			[Enum.Material.Ground] = true,
			[Enum.Material.LeafyGrass] = true,
			[Enum.Material.Mud] = true,
		}
		if not strictAllowedTerrainMaterial[hitMaterial] then
			return false
		end
	end

	local foldersToReject = {
		workspace:FindFirstChild("Facilities"),
		workspace:FindFirstChild("ResourceNodes"),
		workspace:FindFirstChild("NPCs"),
		workspace:FindFirstChild("Creatures"),
		workspace:FindFirstChild("Characters"),
	}

	for _, folder in ipairs(foldersToReject) do
		if folder and hitInstance:IsDescendantOf(folder) then
			return false
		end
	end

	local model = hitInstance:FindFirstAncestorWhichIsA("Model")
	if model and (model:GetAttribute("StructureId") or model:GetAttribute("NodeId") or model:GetAttribute("NPCId")) then
		return false
	end

	return true
end

--========================================
-- Internal: 위치 검증
--========================================
local function validatePosition(position: Vector3): (boolean, string?, string?, number?, Vector3?, Instance?, Enum.Material?)
	-- 1. 해수면/최소 높이 검증 (지하 건설 및 수중 건설 방지)
	local minHeight = math.max(Balance.BUILD_MIN_GROUND_DIST, Balance.SEA_LEVEL or 0)
	if position.Y < minHeight then
		return false, Enums.ErrorCode.INVALID_POSITION
	end
	
	-- 2. Raycast로 지면 확인
	local rayOrigin = position + Vector3.new(0, 8, 0)
	local rayDirection = Vector3.new(0, -24, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	-- 시설물 외에도 플레이어, 크리처 등 동적 개체 제외
	local ignoreList = {}
	local charFolder = workspace:FindFirstChild("Characters")
	if charFolder then table.insert(ignoreList, charFolder) end
	local creatureFolder = workspace:FindFirstChild("Creatures")
	if creatureFolder then table.insert(ignoreList, creatureFolder) end
	
	raycastParams.FilterDescendantsInstances = ignoreList
	
	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if not result then
		return false, Enums.ErrorCode.INVALID_POSITION, nil, nil, nil, nil
	end
	
	local hitInstance = result.Instance
	local hitMaterial = result.Material
	local groundY = result.Position.Y
	local parentId = nil
	
	if hitInstance then
		-- 부모 모델에서 StructureId 속성 찾기 (시설물 위에 짓는 경우)
		local model = hitInstance:FindFirstAncestorWhichIsA("Model")
		if model then
			parentId = model:GetAttribute("StructureId")
		end
	end
	
	return true, nil, parentId, groundY, result.Normal, hitInstance, hitMaterial
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

local function scatterDropPosition(basePos: Vector3, index: number): Vector3
	local angle = (index * 2.39996323) % (math.pi * 2)
	local radius = 1.2 + ((index % 3) * 0.55)
	return basePos + Vector3.new(math.cos(angle) * radius, 2, math.sin(angle) * radius)
end

--========================================
-- Internal: 이벤트 발행
--========================================
local function emitPlaced(structure: any)
	if NetController then
		-- 네트워크 최적화: 600 스터드 내 플레이어에게만 전송
		NetController.FireClientsInRange(structure.position, 600, "Build.Placed", {
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
		local struct = structures[structureId]
		if struct then
			NetController.FireClientsInRange(struct.position, 600, "Build.Removed", {
				id = structureId,
				reason = reason,
			})
		end
	end
end

local function emitChanged(structureId: string, changes: any)
	if NetController then
		local struct = structures[structureId]
		if struct then
			NetController.FireClientsInRange(struct.position, 600, "Build.Changed", {
				id = structureId,
				changes = changes,
			})
		end
	end
end

--========================================
-- Internal: Cap 관리
--========================================
local function pruneOldestIfNeeded()
	if structureCount < Balance.BUILD_STRUCTURE_CAP then
		return
	end
	
	-- [최적화] O(N) 순회 대신 orderedIds 큐의 맨 앞(가장 오래된 것) 제거
	local oldestId = orderedIds[1]
	if oldestId then
		BuildService.removeStructure(oldestId, "CAP_PRUNE")
	end
end

--========================================
-- Internal: 구조물 생성 (Workspace)
--========================================
--- 설비 모델 정리 (스크립트 제거 등)
local function cleanModelForBuild(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end
end

local function resolveServerPlacementTiltOffset(facilityId: string, facilityData: any, model: Model): Vector3
	if type(facilityData) == "table" then
		local configured = facilityData.placementTiltOffset or facilityData.placementRotationOffset
		if typeof(configured) == "Vector3" then
			return Vector3.new(configured.X, 0, configured.Z)
		elseif type(configured) == "table" then
			local x = tonumber(configured.X or configured.x) or 0
			local z = tonumber(configured.Z or configured.z) or 0
			return Vector3.new(x, 0, z)
		end
	end

	if facilityId == "LEAN_TO" and model then
		local rx, _, rz = model:GetPivot():ToOrientation()
		return Vector3.new(math.deg(rx), 0, math.deg(rz))
	end

	return Vector3.new(0, 0, 0)
end

--- 모델을 시설물로 설정 (위치/회전/히트박스)
local function setupFacilityModel(model: Model, facilityId: string, facilityData: any, position: Vector3, rotation: Vector3): Model
	cleanModelForBuild(model)
	
	-- PrimaryPart 설정
	local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if primaryPart then
		model.PrimaryPart = primaryPart
		local tiltOffset = resolveServerPlacementTiltOffset(facilityId, facilityData, model)
		
		-- 지면 정렬 (하단 기준 위치 설정)
		local minY = math.huge
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				local pMinY = p.Position.Y - (p.Size.Y / 2)
				if pMinY < minY then minY = pMinY end
			end
		end
		
		local currentPivot = model:GetPivot()
		local pivotOffset = currentPivot.Position.Y - minY
		
		-- 위치 및 회전 적용
		local targetCF = CFrame.new(position) 
			* CFrame.Angles(math.rad(rotation.X + tiltOffset.X), math.rad(rotation.Y + tiltOffset.Y), math.rad(rotation.Z + tiltOffset.Z))
			* CFrame.new(0, pivotOffset, 0)
		model:PivotTo(targetCF)
	end
	
	-- 물리 및 충돌 설정
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = true
		end
	end
	
	return model
end

--========================================
-- Internal: 구조물 생성 (Workspace)
--========================================
local function spawnFacilityModel(facilityId: string, position: Vector3, rotation: Vector3, structureId: string, ownerId: number): Instance?
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then return nil end
	
	-- ReplicatedStorage/Assets/FacilityModels 폴더 찾기
	local modelsFolder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FacilityModels")
	local template = nil
	if modelsFolder then
		local candidates = {}
		local function pushCandidate(name)
			if type(name) ~= "string" or name == "" then
				return
			end
			for _, existing in ipairs(candidates) do
				if existing == name then
					return
				end
			end
			table.insert(candidates, name)
		end

		pushCandidate(facilityData.modelName)
		pushCandidate(facilityId)
		if type(facilityData.modelAliases) == "table" then
			for _, alias in ipairs(facilityData.modelAliases) do
				pushCandidate(alias)
			end
		end

		for _, name in ipairs(candidates) do
			template = modelsFolder:FindFirstChild(name)
			if template then
				break
			end
		end

		if not template then
			local normalized = {}
			for _, name in ipairs(candidates) do
				normalized[name:lower():gsub("_", "")] = true
			end
			for _, child in ipairs(modelsFolder:GetChildren()) do
				local key = child.Name:lower():gsub("_", "")
				if normalized[key] then
					template = child
					break
				end
			end
		end
	end
	
	local model
	if template then
		model = template:Clone()
		model.Name = structureId
		model.Parent = facilitiesFolder
		setupFacilityModel(model, facilityId, facilityData, position, rotation)
	else
		-- 폴백: 모델이 없을 경우 임시 파트 생성
		warn(string.format("[BuildService] Model not found for facility '%s' (primary='%s'), using fallback", facilityId, tostring(facilityData.modelName or facilityId)))
		model = Instance.new("Part")
		model.Name = structureId
		model.Size = Vector3.new(4, 4, 4)
		model.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
		model.Anchored = true
		model.BrickColor = BrickColor.new("Bright orange")
		model.Parent = facilitiesFolder
	end
	
	-- 속성 설정
	model:SetAttribute("FacilityId", facilityId)
	model:SetAttribute("StructureId", structureId)
	model:SetAttribute("DisplayName", facilityData.name or facilityId)
	model:SetAttribute("OwnerId", ownerId)
	model:SetAttribute("Health", facilityData.maxHealth)
	
	return model
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
	local isCampfire = facilityId == "CAMPFIRE"
	local isCampTotem = facilityId == "CAMP_TOTEM"
	
	-- Vector3 type safety (in case called from other server scripts)
	if type(position) == "table" then
		position = Vector3.new(position.X or position.x or 0, position.Y or position.y or 0, position.Z or position.z or 0)
	end
	if rotation and type(rotation) == "table" then
		rotation = Vector3.new(rotation.X or rotation.x or 0, rotation.Y or rotation.y or 0, rotation.Z or rotation.z or 0)
	end
	
	-- 1. 시설 데이터 검증
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	-- 1aa. 토템 선행 규칙 검증
	-- 기본 규칙: 토템 없이는 건설 불가
	-- 예외: CAMPFIRE, CAMP_TOTEM
	if TotemService and TotemService.isBuildAllowed then
		local buildAllowed, buildErr = TotemService.isBuildAllowed(userId, facilityId, position)
		if not buildAllowed then
			return false, buildErr or Enums.ErrorCode.NO_PERMISSION, nil
		end
	else
		if not isCampfire and not isCampTotem then
			local hasBase = BaseClaimService and BaseClaimService.getBase and BaseClaimService.getBase(userId)
			if not hasBase then
				return false, Enums.ErrorCode.TOTEM_REQUIRED, nil
			end
		end
	end
	
	-- 1a. 기술 해금 검증 (장기적 리뉴얼을 위해 일시 제거)
	-- if TechService and not TechService.isFacilityUnlocked(userId, facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end
	
	-- 1b. 타 유저 베이스 영역 검증 (Griefing Protection)
	if BaseClaimService and BaseClaimService.getOwnerAt then
		local zoneOwnerId = BaseClaimService.getOwnerAt(position)
		if zoneOwnerId and zoneOwnerId ~= userId then
			local zoneProtected = true
			if TotemService and TotemService.isProtectionActiveForOwner then
				zoneProtected = TotemService.isProtectionActiveForOwner(zoneOwnerId)
			end
			if zoneProtected then
				return false, Enums.ErrorCode.NO_PERMISSION, nil
			end
		end
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
	
	-- 3. Cap 검사 (제한 도달 시 오래된 것 자동 정리 시도)
	if structureCount >= Balance.BUILD_STRUCTURE_CAP then
		pruneOldestIfNeeded()
	end
	
	if structureCount >= Balance.BUILD_STRUCTURE_CAP then
		return false, Enums.ErrorCode.STRUCTURE_CAP, nil
	end
	
	-- 4. 충돌 검사
	if checkCollision(position, facilityId) then
		return false, Enums.ErrorCode.COLLISION, nil
	end

	-- 4.5 회전 검증
	local rotOk, rotErr, normalizedRotation = validateRotation(rotation)
	if not rotOk then
		return false, rotErr, nil
	end
	
	-- 5. 위치 검증
	local posOk, posErr, parentId, groundY, groundNormal, hitInstance, hitMaterial = validatePosition(position)
	if not posOk then
		return false, posErr, nil
	end

	if not isValidFieldSurface(hitInstance, groundNormal or Vector3.new(0, 1, 0), hitMaterial) then
		return false, Enums.ErrorCode.INVALID_POSITION, nil
	end

	if isStrictFieldProfile() and parentId then
		return false, Enums.ErrorCode.INVALID_POSITION, nil
	end
	
	-- 지면이 아닌데 지지대(parentId)도 없으면 공중부양 금지
	-- 절대좌표가 아닌, 감지된 지면과의 거리(오차 범위 3.5 스터드)로 체크
	if math.abs(position.Y - groundY) > getMaxGroundGap() then
		return false, Enums.ErrorCode.INVALID_POSITION, nil
	end

	position = Vector3.new(position.X, groundY, position.Z)
	
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
	local actualRotation = normalizedRotation or Vector3.new(0, 0, 0)
	
	-- 9. 구조물 데이터 저장
	local structure = {
		id = structureId,
		facilityId = facilityId,
		position = position,
		rotation = actualRotation,
		health = facilityData.maxHealth,
		ownerId = userId,
		placedAt = os.time(),
		parentId = parentId, -- 지지대 기록
	}
	
	structures[structureId] = structure
	structureCount = structureCount + 1
	table.insert(orderedIds, structureId)
	
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
	
	-- 13. SaveService에 구조물 영속화 (파티셔닝 지원)
	if SaveService then
		local zoneOwnerId = BaseClaimService and BaseClaimService.getOwnerAt(position)
		local base = nil
		if zoneOwnerId and BaseClaimService and BaseClaimService.getBase then
			base = BaseClaimService.getBase(zoneOwnerId)
		end
		local baseId = base and base.id
		
		if baseId then
			-- 베이스 파티션에 저장
			structure.partitionId = baseId
			local saved = SaveService.updatePartition(baseId, function(pState)
				if not pState.structures then pState.structures = {} end
				pState.structures[structureId] = structure
				return pState
			end)
			if not saved then
				-- 파티션 미초기화 → wilderness로 폴백
				structure.partitionId = nil
				SaveService.updateWorldState(function(state)
					if not state.wildernessStructures then state.wildernessStructures = {} end
					state.wildernessStructures[structureId] = structure
					return state
				end)
			end
		else
			-- 야생(Wilderness)으로 월드 공용 상태에 저장
			SaveService.updateWorldState(function(state)
				if not state.wildernessStructures then state.wildernessStructures = {} end
				state.wildernessStructures[structureId] = structure
				return state
			end)
		end
	end
	
	-- 14. BaseClaimService 연동: 첫 건물 설치 시 베이스 자동 생성 (Phase 7)
	if BaseClaimService and BaseClaimService.onStructurePlaced then
		BaseClaimService.onStructurePlaced(userId, position)
	end

	-- 14a. 토템 설치 시 기본 유지시간 부여
	if isCampTotem and TotemService and TotemService.onTotemPlaced then
		TotemService.onTotemPlaced(userId)
	end

	if isCampTotem and BaseClaimService and BaseClaimService.moveBaseCenter then
		local moved, moveErr = BaseClaimService.moveBaseCenter(userId, position)
		if not moved then
			warn(string.format("[BuildService] Failed to move base center for totem placement (user=%d, err=%s)", userId, tostring(moveErr)))
		end
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
		local canRaid = false
		if TotemService and TotemService.canRaidStructure then
			canRaid = TotemService.canRaidStructure(userId, structure)
		end
		if not canRaid then
			return false, Enums.ErrorCode.NO_PERMISSION, nil
		end
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

	-- 토템 캐시 무효화 (해체된 건물이 CAMP_TOTEM인 경우)
	if structure.facilityId == "CAMP_TOTEM" and TotemService and TotemService.invalidateTotemCache then
		TotemService.invalidateTotemCache(structure.ownerId)
	end
	
	-- Workspace에서 제거
	despawnFacilityModel(structureId)
	
	-- 이벤트 발행 (데이터 제거 전에 수행하여 위치 정보 확보)
	emitRemoved(structureId, reason)
	
	-- 데이터 제거
	structures[structureId] = nil
	structureCount = structureCount - 1
	
	local idx = table.find(orderedIds, structureId)
	if idx then
		table.remove(orderedIds, idx)
	end
	
	-- 5. 자원 반환 (Refund)
	if reason == "PLAYER_REMOVE" or reason == "DESTRUCTION" then
		local facilityData = DataService.getFacility(structure.facilityId)
		if facilityData and facilityData.requirements then
			local ownerId = structure.ownerId
			local player = ownerId and Players:GetPlayerByUserId(ownerId)
			local dropService = WorldDropService
			local dropIndex = 0
			
			for _, req in ipairs(facilityData.requirements) do
				local itemId = req.itemId
				local amount = req.amount or 1

				if reason == "PLAYER_REMOVE" then
					-- 해체는 항상 월드에 재료를 배출한다.
					if dropService then
						dropIndex += 1
						dropService.spawnDrop(scatterDropPosition(structure.position, dropIndex), itemId, amount)
					elseif player then
						-- 드롭 서비스 이상 시 최소한 자원 유실은 막는다.
						InventoryService.addItem(ownerId, itemId, amount)
					end
				else
					local added, remaining = 0, amount
					if player then
						added, remaining = InventoryService.addItem(ownerId, itemId, amount)
					end

					if remaining > 0 and dropService then
						dropIndex += 1
						dropService.spawnDrop(scatterDropPosition(structure.position, dropIndex), itemId, remaining)
					end
				end
			end
		end
	end

	-- 6. 연쇄 파괴 (Structural failure)
	-- 나를 지지대로 쓰던 아이들 다 파괴
	for childId, childData in pairs(structures) do
		if childData.parentId == structureId then
			task.spawn(function()
				task.wait(0.1) -- 연쇄 파괴 연출을 위한 미세 지연
				BuildService.removeStructure(childId, "STRUCTURAL_FAILURE")
			end)
		end
	end

	-- 7. SaveService에서 구조물 제거
	if SaveService then
		if structure.partitionId then
			SaveService.updatePartition(structure.partitionId, function(pState)
				if pState and pState.structures then
					pState.structures[structureId] = nil
				end
				return pState
			end)
		else
			SaveService.updateWorldState(function(state)
				if state.wildernessStructures then
					state.wildernessStructures[structureId] = nil
				end
				return state
			end)
		end
	end
end

--- 건축물 피해 입히기
function BuildService.takeDamage(structureId: string, amount: number, dealer: Player?): (boolean, number)
	local structure = structures[structureId]
	if not structure then return false, 0 end
	
	structure.health = math.max(0, structure.health - amount)
	
	-- Workspace 모델 속성 업데이트
	local model = facilitiesFolder:FindFirstChild(structureId)
	if model then
		model:SetAttribute("Health", structure.health)
	end
	
	-- 이펙트/사운드 발행
	emitChanged(structureId, { health = structure.health })
	
	if structure.health <= 0 then
		BuildService.removeStructure(structureId, "DESTRUCTION")
		return true, 0
	end
	
	return true, structure.health
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

--- 특정 소유자의 모든 구조물 조회
function BuildService.getStructuresByOwner(ownerId: number): {any}
	local result = {}
	for _, struct in pairs(structures) do
		if struct.ownerId == ownerId then
			table.insert(result, struct)
		end
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

local function handleListFacilities(player: Player, payload: any)
	local allFacilities = DataService.get("FacilityData")
	if not allFacilities then
		return { success = true, data = { facilities = {} } }
	end
	
	local result = {}
	for facilityId, facility in pairs(allFacilities) do
		table.insert(result, {
			id = facility.id or facilityId,
			name = facility.name,
			description = facility.description,
			techLevel = facility.techLevel or 0,
			inputs = facility.requirements or {}, -- UIManager uses 'inputs'
			buildTime = facility.buildTime or 0,
			maxHealth = facility.maxHealth or 100,
		})
	end
	
	return { success = true, data = { facilities = result } }
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
	
	-- 월드 상태에서 야생 구조물 로드
	local worldState = saveService.getWorldState()
	if worldState then
		-- 하위 호환성: 기존 structures도 체크
		local legacy = worldState.structures or {}
		local wilderness = worldState.wildernessStructures or {}
		
		local function loadStructMap(map)
			for structureId, struct in pairs(map) do
				structures[structureId] = struct
				structureCount = structureCount + 1
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
		end

		loadStructMap(legacy)
		loadStructMap(wilderness)
		
		-- [추가] 설치 순서대로 정렬하여 orderedIds 초기화
		local temp = {}
		for id, struct in pairs(structures) do table.insert(temp, struct) end
		table.sort(temp, function(a, b) return a.placedAt < b.placedAt end)
		for _, s in ipairs(temp) do table.insert(orderedIds, s.id) end
		
		print(string.format("[BuildService] Loaded %d wilderness/legacy structures", structureCount))
	end
	
	initialized = true
end

--- 파티션 기반 구조물 로드 (BaseClaimService에서 호출)
function BuildService.loadStructuresFromPartition(partitionId: string)
	local pState = SaveService.getPartition(partitionId)
	if not pState or not pState.structures then return end
	
	local count = 0
	for structureId, struct in pairs(pState.structures) do
		if structures[structureId] then continue end -- 이미 로드됨
		
		structures[structureId] = struct
		structureCount = structureCount + 1
		count = count + 1
		table.insert(orderedIds, structureId)
		
		local pos = struct.position
		if type(pos) == "table" then
			pos = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
		end
		local rot = struct.rotation
		if type(rot) == "table" then
			rot = Vector3.new(rot.X or rot.x or 0, rot.Y or rot.y or 0, rot.Z or rot.z or 0)
		end
		spawnFacilityModel(struct.facilityId, pos, rot, structureId, struct.ownerId)
		
		-- 신규 로드 시 FacilityService 등록
		if FacilityService and FacilityService.register then
			FacilityService.register(structureId, struct.facilityId, struct.ownerId)
		end
	end
	
	print(string.format("[BuildService] Loaded %d structures from partition %s", count, partitionId))
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

function BuildService.SetTotemService(totemService)
	TotemService = totemService
end

function BuildService.SetWorldDropService(worldDropService)
	WorldDropService = worldDropService
end

function BuildService.GetHandlers()
	return {
		["Build.Place.Request"] = handlePlace,
		["Build.Remove.Request"] = handleRemove,
		["Build.GetAll.Request"] = handleGetAll,
		["Facility.List.Request"] = handleListFacilities,
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
