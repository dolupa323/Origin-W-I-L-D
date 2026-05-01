-- BaseClaimService.lua
-- 베이???�역 관�??�스??(Phase 7-2)
-- ?�레?�어 베이???�역 ?�정 �??�동??범위 관�?

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local BaseClaimService = {}

local PORTAL_NAME = "Portal_Tropical"
local PORTAL_RESTRICTION_MARGIN = Balance.PORTAL_RESTRICTION_MARGIN or 18

--========================================
-- Dependencies (Init?�서 주입)
--========================================
local initialized = false
local NetController = nil
local SaveService = nil
local BuildService = nil

--========================================
-- Internal State
--========================================
-- 베이???�역 { [userId] = BaseClaim }
local bases = {}
local baseSpatialGrid = {} -- ["gx_gz"] = { [ownerId] = true }
local BASE_GRID_SIZE = Balance.BASE_GRID_SIZE or math.max(64, (Balance.BASE_DEFAULT_RADIUS or 30) * 2)
local DEFAULT_EXTENT = Balance.BASE_DEFAULT_RADIUS or 30
local MAX_EXTENT = Balance.BASE_MAX_RADIUS or 100
local EXPAND_STEP = Balance.BASE_DIRECTIONAL_EXPAND_STEP or 8

-- BaseClaim 구조
-- {
--   id = "base_12345",
--   ownerId = userId,
--   centerPosition = Vector3,
--   radius = 30,
--   level = 1,
--   createdAt = timestamp,
-- }

--========================================
-- Internal Functions
--========================================

local function makeGridKey(gx: number, gz: number): string
	return string.format("%d_%d", gx, gz)
end

local function getGridKey(position: Vector3): (number, number)
	return math.floor(position.X / BASE_GRID_SIZE), math.floor(position.Z / BASE_GRID_SIZE)
end

local function getGridRange(radius: number): number
	return math.max(0, math.ceil(radius / BASE_GRID_SIZE))
end

local function getBaseExtents(baseClaim: any): (number, number, number, number)
	local fallback = tonumber(baseClaim and baseClaim.radius) or DEFAULT_EXTENT
	local west = tonumber(baseClaim and baseClaim.westExtent) or fallback
	local east = tonumber(baseClaim and baseClaim.eastExtent) or fallback
	local north = tonumber(baseClaim and baseClaim.northExtent) or fallback
	local south = tonumber(baseClaim and baseClaim.southExtent) or fallback
	return west, east, north, south
end

local function computeBaseRadiusFromExtents(baseClaim: any): number
	local west, east, north, south = getBaseExtents(baseClaim)
	return math.max(west, east, north, south)
end

local function syncBaseDerivedFields(baseClaim: any)
	if not baseClaim then
		return
	end

	local west, east, north, south = getBaseExtents(baseClaim)
	baseClaim.westExtent = west
	baseClaim.eastExtent = east
	baseClaim.northExtent = north
	baseClaim.southExtent = south
	baseClaim.radius = math.max(west, east, north, south)
	baseClaim.purchasedExpansions = math.max(0, math.floor(tonumber(baseClaim.purchasedExpansions) or math.max(0, (tonumber(baseClaim.level) or 1) - 1)))
	baseClaim.availableExpansionPoints = math.max(0, math.floor(tonumber(baseClaim.availableExpansionPoints) or 0))
	baseClaim.level = 1 + baseClaim.purchasedExpansions
	baseClaim.resetOnNextTotemPlacement = baseClaim.resetOnNextTotemPlacement == true
end

local function getBaseBounds(baseClaim: any, centerOverride: Vector3?, extentsOverride: any?): (number, number, number, number)
	local center = centerOverride or baseClaim.centerPosition
	local west, east, north, south
	if type(extentsOverride) == "table" then
		west = tonumber(extentsOverride.westExtent or extentsOverride.west) or DEFAULT_EXTENT
		east = tonumber(extentsOverride.eastExtent or extentsOverride.east) or DEFAULT_EXTENT
		north = tonumber(extentsOverride.northExtent or extentsOverride.north) or DEFAULT_EXTENT
		south = tonumber(extentsOverride.southExtent or extentsOverride.south) or DEFAULT_EXTENT
	else
		west, east, north, south = getBaseExtents(baseClaim)
	end
	return center.X - west, center.X + east, center.Z - south, center.Z + north
end

local function isPointInBaseArea(centerPosition: Vector3, radius: number, position: Vector3): boolean
	return math.abs(position.X - centerPosition.X) <= radius
		and math.abs(position.Z - centerPosition.Z) <= radius
end

local function isPointInExtents(centerPosition: Vector3, extents: any, position: Vector3): boolean
	local west = tonumber(extents.westExtent or extents.west) or DEFAULT_EXTENT
	local east = tonumber(extents.eastExtent or extents.east) or DEFAULT_EXTENT
	local north = tonumber(extents.northExtent or extents.north) or DEFAULT_EXTENT
	local south = tonumber(extents.southExtent or extents.south) or DEFAULT_EXTENT
	return position.X >= (centerPosition.X - west)
		and position.X <= (centerPosition.X + east)
		and position.Z >= (centerPosition.Z - south)
		and position.Z <= (centerPosition.Z + north)
end

local function isPointInBaseClaim(baseClaim: any, position: Vector3): boolean
	return isPointInExtents(baseClaim.centerPosition, baseClaim, position)
end

local function doBaseAreasOverlap(centerA: Vector3, extentsA: any, centerB: Vector3, extentsB: any): boolean
	local minXA, maxXA, minZA, maxZA = getBaseBounds({ centerPosition = centerA }, centerA, extentsA)
	local minXB, maxXB, minZB, maxZB = getBaseBounds({ centerPosition = centerB }, centerB, extentsB)
	return minXA < maxXB and maxXA > minXB and minZA < maxZB and maxZA > minZB
end

local function getAxisAlignedBaseCorners(centerPosition: Vector3, radius: number): { Vector2 }
	return {
		Vector2.new(centerPosition.X - radius, centerPosition.Z - radius),
		Vector2.new(centerPosition.X - radius, centerPosition.Z + radius),
		Vector2.new(centerPosition.X + radius, centerPosition.Z - radius),
		Vector2.new(centerPosition.X + radius, centerPosition.Z + radius),
	}
end

local function getOrientedBoxCornersXZ(boxCFrame: CFrame, boxSize: Vector3): { Vector2 }
	local halfX = boxSize.X * 0.5
	local halfZ = boxSize.Z * 0.5
	local corners = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local worldPos = boxCFrame:PointToWorldSpace(Vector3.new(halfX * sx, 0, halfZ * sz))
			table.insert(corners, Vector2.new(worldPos.X, worldPos.Z))
		end
	end
	return corners
end

local function projectCorners(axis: Vector2, corners: { Vector2 }): (number, number)
	local minProj = math.huge
	local maxProj = -math.huge
	for _, corner in ipairs(corners) do
		local projection = corner:Dot(axis)
		if projection < minProj then
			minProj = projection
		end
		if projection > maxProj then
			maxProj = projection
		end
	end
	return minProj, maxProj
end

local function rangesOverlap(minA: number, maxA: number, minB: number, maxB: number): boolean
	return not (maxA < minB or maxB < minA)
end

local function normalizeXZAxis(vector: Vector3, fallback: Vector2): Vector2
	local axis = Vector2.new(vector.X, vector.Z)
	if axis.Magnitude < 1e-4 then
		return fallback
	end
	return axis.Unit
end

local function doesBaseAreaOverlapOrientedBox(centerPosition: Vector3, radius: number, boxCFrame: CFrame, boxSize: Vector3): boolean
	local baseCorners = getAxisAlignedBaseCorners(centerPosition, radius)
	local boxCorners = getOrientedBoxCornersXZ(boxCFrame, boxSize)
	local axes = {
		Vector2.new(1, 0),
		Vector2.new(0, 1),
		normalizeXZAxis(boxCFrame.RightVector, Vector2.new(1, 0)),
		normalizeXZAxis(boxCFrame.LookVector, Vector2.new(0, 1)),
	}

	for _, axis in ipairs(axes) do
		local minBase, maxBase = projectCorners(axis, baseCorners)
		local minBox, maxBox = projectCorners(axis, boxCorners)
		if not rangesOverlap(minBase, maxBase, minBox, maxBox) then
			return false
		end
	end

	return true
end

local function doesExtentsOverlapOrientedBox(centerPosition: Vector3, extents: any, boxCFrame: CFrame, boxSize: Vector3): boolean
	local west = tonumber(extents.westExtent or extents.west) or DEFAULT_EXTENT
	local east = tonumber(extents.eastExtent or extents.east) or DEFAULT_EXTENT
	local north = tonumber(extents.northExtent or extents.north) or DEFAULT_EXTENT
	local south = tonumber(extents.southExtent or extents.south) or DEFAULT_EXTENT
	local baseCorners = {
		Vector2.new(centerPosition.X - west, centerPosition.Z - south),
		Vector2.new(centerPosition.X - west, centerPosition.Z + north),
		Vector2.new(centerPosition.X + east, centerPosition.Z - south),
		Vector2.new(centerPosition.X + east, centerPosition.Z + north),
	}
	local boxCorners = getOrientedBoxCornersXZ(boxCFrame, boxSize)
	local axes = {
		Vector2.new(1, 0),
		Vector2.new(0, 1),
		normalizeXZAxis(boxCFrame.RightVector, Vector2.new(1, 0)),
		normalizeXZAxis(boxCFrame.LookVector, Vector2.new(0, 1)),
	}

	for _, axis in ipairs(axes) do
		local minBase, maxBase = projectCorners(axis, baseCorners)
		local minBox, maxBox = projectCorners(axis, boxCorners)
		if not rangesOverlap(minBase, maxBase, minBox, maxBox) then
			return false
		end
	end

	return true
end

local function makeDefaultExtents(): any
	return {
		westExtent = DEFAULT_EXTENT,
		eastExtent = DEFAULT_EXTENT,
		northExtent = DEFAULT_EXTENT,
		southExtent = DEFAULT_EXTENT,
	}
end

local function getNextExpandCost(baseClaim: any): number
	local purchased = math.max(0, math.floor(tonumber(baseClaim and baseClaim.purchasedExpansions) or 0))
	return (Balance.BASE_DIRECTIONAL_EXPAND_COST_BASE or 500)
		+ purchased * (Balance.BASE_DIRECTIONAL_EXPAND_COST_STEP or 500)
end

local function unindexBase(baseClaim: any)
	if not baseClaim or type(baseClaim._gridCells) ~= "table" then
		return
	end

	for _, cellKey in ipairs(baseClaim._gridCells) do
		local bucket = baseSpatialGrid[cellKey]
		if bucket then
			bucket[baseClaim.ownerId] = nil
			if next(bucket) == nil then
				baseSpatialGrid[cellKey] = nil
			end
		end
	end

	baseClaim._gridCells = nil
end

local function indexBase(baseClaim: any)
	if not baseClaim or not baseClaim.centerPosition then
		return
	end

	syncBaseDerivedFields(baseClaim)
	local gx, gz = getGridKey(baseClaim.centerPosition)
	local radius = baseClaim.radius or DEFAULT_EXTENT
	local range = getGridRange(radius)
	local cells = {}

	for x = -range, range do
		for z = -range, range do
			local key = makeGridKey(gx + x, gz + z)
			local bucket = baseSpatialGrid[key]
			if not bucket then
				bucket = {}
				baseSpatialGrid[key] = bucket
			end
			bucket[baseClaim.ownerId] = true
			table.insert(cells, key)
		end
	end

	baseClaim._gridCells = cells
end

local function reindexBase(baseClaim: any)
	unindexBase(baseClaim)
	indexBase(baseClaim)
end

local function forEachNearbyBase(position: Vector3, radius: number, callback: (number, any) -> ()): boolean
	local gx, gz = getGridKey(position)
	local range = getGridRange(radius)
	local visited = {}

	for x = -range, range do
		for z = -range, range do
			local bucket = baseSpatialGrid[makeGridKey(gx + x, gz + z)]
			if bucket then
				for ownerId, _ in pairs(bucket) do
					if not visited[ownerId] then
						visited[ownerId] = true
						local baseClaim = bases[ownerId]
						if baseClaim then
							local shouldStop = callback(ownerId, baseClaim)
							if shouldStop then
								return true
							end
						end
					end
				end
			end
		end
	end

	return false
end

local function hasWildernessStructureConflict(centerPosition: Vector3, extents: any, ownerId: number): boolean
	local facilitiesFolder = Workspace:FindFirstChild("Facilities")
	local npcFolder = Workspace:FindFirstChild("NPCs")
	if not facilitiesFolder and not npcFolder then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	local included = {}
	if facilitiesFolder then
		table.insert(included, facilitiesFolder)
	end
	if npcFolder then
		table.insert(included, npcFolder)
	end
	overlapParams.FilterDescendantsInstances = included

	local west = tonumber(extents.westExtent or extents.west) or DEFAULT_EXTENT
	local east = tonumber(extents.eastExtent or extents.east) or DEFAULT_EXTENT
	local north = tonumber(extents.northExtent or extents.north) or DEFAULT_EXTENT
	local south = tonumber(extents.southExtent or extents.south) or DEFAULT_EXTENT
	local queryCenter = Vector3.new(centerPosition.X + ((east - west) * 0.5), centerPosition.Y + 128, centerPosition.Z + ((north - south) * 0.5))
	local querySize = Vector3.new(west + east, 256, south + north)
	local parts = Workspace:GetPartBoundsInBox(CFrame.new(queryCenter), querySize, overlapParams)
	local checkedStructures = {}

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorWhichIsA("Model")
		local container = model or part
		if container then
			local structureId = container:GetAttribute("StructureId") or container.Name
			local npcType = container:GetAttribute("NPCType")
			if npcType == "shop" then
				return true
			end
			if structureId and not checkedStructures[structureId] then
				checkedStructures[structureId] = true
				local structOwnerId = container:GetAttribute("OwnerId")
				if type(structOwnerId) == "number" and structOwnerId ~= ownerId then
					local ownerBase = bases[structOwnerId]
					local isInsideOwnerBase = false
					local structPos = container:GetPivot().Position
					if ownerBase then
						isInsideOwnerBase = isPointInBaseClaim(ownerBase, structPos)
					end

					if not isInsideOwnerBase then
						return true
					end
				end
			end
		end
	end

	return false
end

local function overlapsPortalRestrictionZone(centerPosition: Vector3, extents: any): boolean
	if typeof(centerPosition) ~= "Vector3" then
		return false
	end

	local portalObject = Workspace:FindFirstChild(PORTAL_NAME)
	if not portalObject then
		return false
	end

	local boxCFrame, boxSize
	if portalObject:IsA("Model") then
		boxCFrame, boxSize = portalObject:GetBoundingBox()
	elseif portalObject:IsA("BasePart") then
		boxCFrame, boxSize = portalObject.CFrame, portalObject.Size
	else
		return false
	end

	local expandedSize = Vector3.new(
		boxSize.X + PORTAL_RESTRICTION_MARGIN * 2,
		math.max(boxSize.Y, 256),
		boxSize.Z + PORTAL_RESTRICTION_MARGIN * 2
	)

	return doesExtentsOverlapOrientedBox(centerPosition, extents, boxCFrame, expandedSize)
end

--- 고유 베이??ID ?�성
local function generateBaseId(userId: number): string
	return string.format("base_%d_%d", userId, os.time())
end

--- ?�드 ?�태?�서 베이??로드
local function loadBases()
	if not SaveService then return end
	
	local worldState = SaveService.getWorldState()
	if worldState and worldState.bases then
		local loadedCount = 0
		for baseId, baseData in pairs(worldState.bases) do
			-- ?�티???�이??로드
			local ok, pData = SaveService.loadPartition(baseId)
			if ok then
				-- Vector3 복원 �?캐싱
				if baseData.centerPosition then
					local pos = baseData.centerPosition
					baseData.centerPosition = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
				end
				syncBaseDerivedFields(baseData)
				bases[baseData.ownerId] = baseData
				indexBase(baseData)
				
				if not pData and SaveService.initPartition then
					SaveService.initPartition(baseId, baseData.ownerId)
				end

				-- BuildService???�당 ?�티??구조�?로드 ?�청
				if pData and BuildService then
					BuildService.loadStructuresFromPartition(baseId)
				end
				loadedCount = loadedCount + 1
			else
				warn(string.format("[BaseClaimService] Failed to load partition for base %s", baseId))
			end
		end
		print(string.format("[BaseClaimService] Loaded %d bases from world state", loadedCount))
	end
end

--- 베이???�??
local function saveBase(baseClaim: any)
	if not SaveService or not SaveService.updateWorldState then return end
	
	SaveService.updateWorldState(function(state)
		if not state.bases then
			state.bases = {}
		end
		-- Vector3�??�반 ?�이블로 변??(?�?�용)
		local saveData = {
			id = baseClaim.id,
			ownerId = baseClaim.ownerId,
			centerPosition = {
				X = baseClaim.centerPosition.X,
				Y = baseClaim.centerPosition.Y,
				Z = baseClaim.centerPosition.Z,
			},
			radius = baseClaim.radius,
			westExtent = baseClaim.westExtent,
			eastExtent = baseClaim.eastExtent,
			northExtent = baseClaim.northExtent,
			southExtent = baseClaim.southExtent,
			level = baseClaim.level,
			purchasedExpansions = baseClaim.purchasedExpansions,
			availableExpansionPoints = baseClaim.availableExpansionPoints,
			resetOnNextTotemPlacement = baseClaim.resetOnNextTotemPlacement == true,
			createdAt = baseClaim.createdAt,
		}
		state.bases[baseClaim.id] = saveData
		return state
	end)
end

--========================================
-- Public API
--========================================

--- 베이???�성 (�?건물 ?�치 ???�동 ?�출)
function BaseClaimService.create(userId: number, position: Vector3): (boolean, string?, string?)
	-- ?��? 베이???�는지 ?�인
	if bases[userId] then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- ?�레?�어??최�? 베이?????�인
	local maxBases = Balance.BASE_MAX_PER_PLAYER or 1
	if maxBases <= 0 then
		return false, Enums.ErrorCode.NOT_SUPPORTED, nil
	end
	
	-- 중첩 검??(Overlap Protection: (NewRadius + OtherRadius) < Distance)
	local defaultExtents = makeDefaultExtents()
	if overlapsPortalRestrictionZone(position, defaultExtents) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	local hasCollision = forEachNearbyBase(position, DEFAULT_EXTENT, function(otherOwnerId, otherBase)
		if otherOwnerId == userId then
			return false
		end
		if doBaseAreasOverlap(position, defaultExtents, otherBase.centerPosition, otherBase) then
			print(string.format("[BaseClaimService] Create failed: Overlap with player %d's base", otherBase.ownerId))
			return true
		end
		return false
	end)
	if hasCollision then
		return false, Enums.ErrorCode.COLLISION, nil
	end
	
	-- 베이???�성
	local baseId = generateBaseId(userId)
	local baseClaim = {
		id = baseId,
		ownerId = userId,
		centerPosition = position,
		radius = DEFAULT_EXTENT,
		westExtent = DEFAULT_EXTENT,
		eastExtent = DEFAULT_EXTENT,
		northExtent = DEFAULT_EXTENT,
		southExtent = DEFAULT_EXTENT,
		level = 1,
		purchasedExpansions = 0,
		availableExpansionPoints = 0,
		resetOnNextTotemPlacement = false,
		createdAt = os.time(),
	}
	syncBaseDerivedFields(baseClaim)
	
	bases[userId] = baseClaim
	indexBase(baseClaim)
	
	-- ?�티??초기??(SaveService)
	if SaveService then
		SaveService.initPartition(baseId, userId)
	end
	
	saveBase(baseClaim)
	
	-- ?�라?�언???�림
	if NetController then
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			NetController.FireClient(player, "Base.Created", {
				baseId = baseId,
				centerPosition = position,
				radius = baseClaim.radius,
				westExtent = baseClaim.westExtent,
				eastExtent = baseClaim.eastExtent,
				northExtent = baseClaim.northExtent,
				southExtent = baseClaim.southExtent,
			})
		end
	end
	
	print(string.format("[BaseClaimService] Created base %s for player %d at (%.1f, %.1f, %.1f)",
		baseId, userId, position.X, position.Y, position.Z))
	
	return true, nil, baseId
end

--- 베이??조회
function BaseClaimService.getBase(userId: number): any?
	local baseClaim = bases[userId]
	if baseClaim then
		syncBaseDerivedFields(baseClaim)
	end
	return baseClaim
end

--- ?�당 ?�치�??�유??베이??주인 ID 반환
function BaseClaimService.getOwnerAt(position: Vector3): number?
	local ownerIdAt = nil
	forEachNearbyBase(position, 0, function(userId, baseClaim)
		if isPointInBaseClaim(baseClaim, position) then
			ownerIdAt = userId
			return true
		end
		return false
	end)

	if ownerIdAt then
		return ownerIdAt
	end
	return nil
end

--- ?�치가 베이???�인지 ?�인
function BaseClaimService.isInBase(userId: number, position: Vector3): boolean
	local baseClaim = bases[userId]
	if not baseClaim then return false end

	return isPointInBaseClaim(baseClaim, position)
end

function BaseClaimService.getExpandInfo(userId: number): any?
	local baseClaim = bases[userId]
	if not baseClaim then
		return nil
	end

	syncBaseDerivedFields(baseClaim)
	return {
		nextCost = getNextExpandCost(baseClaim),
		availablePoints = baseClaim.availableExpansionPoints,
		purchasedExpansions = baseClaim.purchasedExpansions,
		step = EXPAND_STEP,
		maxExtent = MAX_EXTENT,
	}
end

--- 베이??방향 ?�장
function BaseClaimService.expand(userId: number, direction: string, consumeAvailablePoint: boolean?): (boolean, string?)
	local baseClaim = bases[userId]
	if not baseClaim then
		return false, Enums.ErrorCode.NOT_FOUND
	end

	syncBaseDerivedFields(baseClaim)
	direction = string.upper(tostring(direction or ""))
	if direction ~= "NORTH" and direction ~= "SOUTH" and direction ~= "EAST" and direction ~= "WEST" then
		return false, Enums.ErrorCode.BAD_REQUEST
	end

	local requested = {
		westExtent = baseClaim.westExtent,
		eastExtent = baseClaim.eastExtent,
		northExtent = baseClaim.northExtent,
		southExtent = baseClaim.southExtent,
	}
	requested[string.lower(direction) .. "Extent"] += EXPAND_STEP

	if requested.westExtent > MAX_EXTENT or requested.eastExtent > MAX_EXTENT
		or requested.northExtent > MAX_EXTENT or requested.southExtent > MAX_EXTENT then
		return false, Enums.ErrorCode.INVALID_STATE
	end

	local requestedRadius = math.max(requested.westExtent, requested.eastExtent, requested.northExtent, requested.southExtent)
	local hasCollision = forEachNearbyBase(baseClaim.centerPosition, requestedRadius, function(otherUserId, otherBase)
		if otherUserId ~= userId then
			if doBaseAreasOverlap(baseClaim.centerPosition, requested, otherBase.centerPosition, otherBase) then
				print(string.format("[BaseClaimService] Expand failed for player %d: Would overlap with player %d's base", userId, otherUserId))
				return true
			end
		end
		return false
	end)
	if hasCollision then
		return false, Enums.ErrorCode.COLLISION
	end

	if overlapsPortalRestrictionZone(baseClaim.centerPosition, requested) then
		return false, Enums.ErrorCode.NO_PERMISSION
	end

	if hasWildernessStructureConflict(baseClaim.centerPosition, requested, userId) then
		warn(string.format("[BaseClaimService] Expand blocked for player %d: foreign wilderness structure detected in target radius", userId))
		return false, Enums.ErrorCode.COLLISION
	end

	baseClaim.westExtent = requested.westExtent
	baseClaim.eastExtent = requested.eastExtent
	baseClaim.northExtent = requested.northExtent
	baseClaim.southExtent = requested.southExtent
	if consumeAvailablePoint and baseClaim.availableExpansionPoints > 0 then
		baseClaim.availableExpansionPoints -= 1
	else
		baseClaim.purchasedExpansions += 1
	end
	syncBaseDerivedFields(baseClaim)
	reindexBase(baseClaim)
	saveBase(baseClaim)
	
	-- ?�라?�언???�림
	if NetController then
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			NetController.FireClient(player, "Base.Expanded", {
				baseId = baseClaim.id,
				radius = baseClaim.radius,
				westExtent = baseClaim.westExtent,
				eastExtent = baseClaim.eastExtent,
				northExtent = baseClaim.northExtent,
				southExtent = baseClaim.southExtent,
				level = baseClaim.level,
				availableExpansionPoints = baseClaim.availableExpansionPoints,
				purchasedExpansions = baseClaim.purchasedExpansions,
			})
		end
	end
	
	return true, nil
end

--- 베이??중심 ?�동 (?�템 ?�배치용)
--- skipPortalCheck: ?��? 건설 검증을 ?�과???�템 배치 ??true
function BaseClaimService.moveBaseCenter(userId: number, newPosition: Vector3, skipPortalCheck: boolean?): (boolean, string?)
	local baseClaim = bases[userId]
	if not baseClaim then
		return false, Enums.ErrorCode.NOT_FOUND
	end

	if not skipPortalCheck and overlapsPortalRestrictionZone(newPosition, baseClaim) then
		return false, Enums.ErrorCode.NO_PERMISSION
	end

	local hasCollision = forEachNearbyBase(newPosition, baseClaim.radius or DEFAULT_EXTENT, function(otherUserId, otherBase)
		if otherUserId ~= userId then
			if doBaseAreasOverlap(newPosition, baseClaim, otherBase.centerPosition, otherBase) then
				return true
			end
		end
		return false
	end)
	if hasCollision then
		return false, Enums.ErrorCode.COLLISION
	end

	baseClaim.centerPosition = newPosition
	reindexBase(baseClaim)
	saveBase(baseClaim)

	if NetController then
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			NetController.FireClient(player, "Base.Relocated", {
				baseId = baseClaim.id,
				centerPosition = newPosition,
				radius = baseClaim.radius,
				westExtent = baseClaim.westExtent,
				eastExtent = baseClaim.eastExtent,
				northExtent = baseClaim.northExtent,
				southExtent = baseClaim.southExtent,
				level = baseClaim.level,
			})
		end
	end

	return true, nil
end

--- 베이?????�설 목록 조회
function BaseClaimService.getStructuresInBase(userId: number): {string}
	local baseClaim = bases[userId]
	if not baseClaim then return {} end
	if not BuildService then return {} end
	
	local result = {}
	local allStructures = BuildService.getAll()
	
	for _, structure in ipairs(allStructures) do
		if BaseClaimService.isInBase(userId, structure.position) then
			table.insert(result, structure.id)
		end
	end
	
	return result
end

--- 베이????�� (?�버�??�드민용)
function BaseClaimService.delete(userId: number): boolean
	local baseClaim = bases[userId]
	if not baseClaim then return false end
	
	-- 1. 베이????모든 구조�?철거
	if BuildService then
		local structureIds = BaseClaimService.getStructuresInBase(userId)
		for _, structureId in ipairs(structureIds) do
			BuildService.removeStructure(structureId)
		end
		print(string.format("[BaseClaimService] Removed %d structures from base being deleted (%s)", #structureIds, baseClaim.id))
	end
	
	-- 2. SaveService?�서 ?�거 (?�드 ?�태 �??�티??
	if SaveService then
		SaveService.updateWorldState(function(state)
			if state.bases then
				state.bases[baseClaim.id] = nil
			end
			return state
		end)
		-- ?�티???�구 ??��
		SaveService.deletePartition(baseClaim.id)
	end
	
	-- 3. 메모�??�리
	unindexBase(baseClaim)
	bases[userId] = nil
	
	-- ?�라?�언???�림 (?�적?�로 ??��?�는 경우 ?�??
	if NetController then
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			NetController.FireClient(player, "Base.Deleted", { baseId = baseClaim.id })
		end
	end
	
	return true
end

--- 모든 베이??조회 (?�버그용)
function BaseClaimService.getAllBases(): {any}
	local result = {}
	for _, baseClaim in pairs(bases) do
		table.insert(result, {
			id = baseClaim.id,
			ownerId = baseClaim.ownerId,
			centerPosition = baseClaim.centerPosition,
			radius = baseClaim.radius,
			westExtent = baseClaim.westExtent,
			eastExtent = baseClaim.eastExtent,
			northExtent = baseClaim.northExtent,
			southExtent = baseClaim.southExtent,
			level = baseClaim.level,
			purchasedExpansions = baseClaim.purchasedExpansions,
			availableExpansionPoints = baseClaim.availableExpansionPoints,
		})
	end
	return result
end

--========================================
-- BuildService ?�동: �?건물 ?�치 ??베이???�동 ?�성
--========================================
function BaseClaimService.onStructurePlaced(userId: number, position: Vector3)
	-- ?��? 베이?��? ?�으�?무시
	if bases[userId] then return end
	
	-- 베이???�동 ?�성
	BaseClaimService.create(userId, position)
end

function BaseClaimService.onTotemRemoved(userId: number)
	local baseClaim = bases[userId]
	if not baseClaim then
		return
	end

	syncBaseDerivedFields(baseClaim)
	baseClaim.availableExpansionPoints = baseClaim.purchasedExpansions
	baseClaim.resetOnNextTotemPlacement = baseClaim.purchasedExpansions > 0
	saveBase(baseClaim)
end

function BaseClaimService.onTotemPlaced(userId: number, position: Vector3): (boolean, string?)
	local baseClaim = bases[userId]
	if not baseClaim then
		local created, err = BaseClaimService.create(userId, position)
		if not created then
			return false, err
		end
		baseClaim = bases[userId]
	end
	if not baseClaim then
		return false, Enums.ErrorCode.NOT_FOUND
	end

	syncBaseDerivedFields(baseClaim)
	if baseClaim.resetOnNextTotemPlacement then
		local prevWest = baseClaim.westExtent
		local prevEast = baseClaim.eastExtent
		local prevNorth = baseClaim.northExtent
		local prevSouth = baseClaim.southExtent
		local defaults = makeDefaultExtents()
		baseClaim.westExtent = defaults.westExtent
		baseClaim.eastExtent = defaults.eastExtent
		baseClaim.northExtent = defaults.northExtent
		baseClaim.southExtent = defaults.southExtent
		syncBaseDerivedFields(baseClaim)
		local moved, err = BaseClaimService.moveBaseCenter(userId, position, true)
		if moved then
			baseClaim.resetOnNextTotemPlacement = false
			saveBase(baseClaim)
			return true, nil
		end
		baseClaim.westExtent = prevWest
		baseClaim.eastExtent = prevEast
		baseClaim.northExtent = prevNorth
		baseClaim.southExtent = prevSouth
		baseClaim.resetOnNextTotemPlacement = true
		syncBaseDerivedFields(baseClaim)
		saveBase(baseClaim)
		return false, err
	end

	return BaseClaimService.moveBaseCenter(userId, position, true)
end

--========================================
-- Network Handlers
--========================================

local function handleGetBase(player: Player, payload: any)
	local baseClaim = BaseClaimService.getBase(player.UserId)
	
	if baseClaim then
		return {
			success = true,
			data = {
				id = baseClaim.id,
				centerPosition = baseClaim.centerPosition,
				radius = baseClaim.radius,
				westExtent = baseClaim.westExtent,
				eastExtent = baseClaim.eastExtent,
				northExtent = baseClaim.northExtent,
				southExtent = baseClaim.southExtent,
				level = baseClaim.level,
				purchasedExpansions = baseClaim.purchasedExpansions,
				availableExpansionPoints = baseClaim.availableExpansionPoints,
			}
		}
	else
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end
end

local function handleExpand(player: Player, payload: any)
	local direction = payload and payload.direction
	local consumeAvailablePoint = payload and payload.consumeAvailablePoint == true
	local success, errorCode = BaseClaimService.expand(player.UserId, direction, consumeAvailablePoint)
	
	if success then
		return { success = true }
	else
		return { success = false, errorCode = errorCode }
	end
end

--========================================
-- Initialization
--========================================

function BaseClaimService.Init(netController: any, saveService: any, buildService: any)
	if initialized then return end
	
	NetController = netController
	SaveService = saveService
	BuildService = buildService
	
	-- ?�?�된 베이??로드
	loadBases()
	
	initialized = true
	print("[BaseClaimService] Initialized")
end

function BaseClaimService.GetHandlers()
	return {
		["Base.Get.Request"] = handleGetBase,
		["Base.Expand.Request"] = handleExpand,
	}
end

return BaseClaimService

