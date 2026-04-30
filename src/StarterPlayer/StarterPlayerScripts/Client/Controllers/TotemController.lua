-- TotemController.lua
-- Totem interaction / Upkeep / Zone preview control

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local SpawnConfig = require(Shared.Config.SpawnConfig)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local TotemController = {}

local initialized = false
local currentStructureId = nil
local infoCache = {} -- [structureId] = {data, fetchedAt}

-- Structures for multiple zone previews
-- [zoneId] = { folder, segments, prevCount, lastRenderedAt }
-- zoneId: "OWN", "STARTER", structureId (for others)
local activePreviews = {}

local fenceTemplate = nil     -- Original fence model
local fenceSegmentWidth = 4   -- Measured from model
local fencePivotOffsetY = 0   -- Pivot to floor offset
local previewConn = nil
local ownInfoCache = nil
local ownInfoFetchedAt = 0
local ownInfoRequestPending = false
local isTeleporting = false -- Network request stop flag during teleport
local _portalCache = {}      -- Portal object cache for preview

-- Territory entry notification state
local currentTerritoryOwnerId = nil  -- Owner of territory player is currently in
local territoryNotifyCooldown = {}   -- [ownerId] = lastNotifiedAt
local TERRITORY_NOTIFY_COOLDOWN = 120 -- Cooldown for same territory notification (sec)
local playerNameCache = {}            -- [userId] = displayName

local PREVIEW_REFRESH_INTERVAL = 0.35
local INFO_CACHE_TTL = 5
local OWN_INFO_CACHE_TTL = 30
local PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 200, 120)
local PREVIEW_COLOR_INACTIVE = Color3.fromRGB(240, 180, 100)
local OWN_PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 195, 110)
local OWN_PREVIEW_COLOR_INACTIVE = Color3.fromRGB(235, 175, 95)
local STARTER_PREVIEW_COLOR = Color3.fromRGB(170, 210, 255)
local PORTAL_PREVIEW_COLOR = Color3.fromRGB(255, 120, 120) -- Reddish for restriction
local PREVIEW_BORDER_WIDTH = 1.2

local PORTAL_NAMES = {
	"Portal_Tropical", "Portal_Return_Tropical",
	"Portal_Desert", "Portal_Return_Desert",
	"Portal_Snowy", "Portal_Return_Snowy"
}
local PORTAL_RESTRICTION_MARGIN = Balance.PORTAL_RESTRICTION_MARGIN or 10

local function getExtentsFromInfo(info, fallbackRadius)
	local radius = tonumber(fallbackRadius) or tonumber(info and info.radius) or (Balance.BASE_DEFAULT_RADIUS or 30)
	return {
		west = tonumber(info and info.westExtent) or radius,
		east = tonumber(info and info.eastExtent) or radius,
		north = tonumber(info and info.northExtent) or radius,
		south = tonumber(info and info.southExtent) or radius,
	}
end

local function destroyPreviewZone(zoneId)
	local p = activePreviews[zoneId]
	if not p then return end
	
	if p.segments then
		for _, seg in ipairs(p.segments) do
			if seg and seg.Parent then seg:Destroy() end
		end
	end
	if p.folder then
		p.folder:Destroy()
	end
	activePreviews[zoneId] = nil
end

local function destroyAllPreviews()
	for zoneId, _ in pairs(activePreviews) do
		destroyPreviewZone(zoneId)
	end
	activePreviews = {}
end

local function hidePreview()
	destroyAllPreviews()
end

local function getFenceTemplate()
	if fenceTemplate then return fenceTemplate end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local facilityModels = assets:FindFirstChild("FacilityModels")
	if not facilityModels then return nil end
	local tmpl = facilityModels:FindFirstChild("TotemFence")
	if not tmpl then return nil end
	fenceTemplate = tmpl

	if tmpl:IsA("Model") then
		local cf, size = tmpl:GetBoundingBox()
		local pivot = tmpl:GetPivot()
		fenceSegmentWidth = size.X
		fencePivotOffsetY = pivot.Y - (cf.Y - size.Y / 2)
	elseif tmpl:IsA("BasePart") then
		fenceSegmentWidth = tmpl.Size.X
		fencePivotOffsetY = tmpl.Size.Y / 2
	end
	if fenceSegmentWidth < 0.5 then fenceSegmentWidth = 4 end
	return fenceTemplate
end

local function ensureZoneFolder(zoneId)
	if activePreviews[zoneId] and activePreviews[zoneId].folder and activePreviews[zoneId].folder.Parent then
		return activePreviews[zoneId].folder
	end
	
	local folder = Instance.new("Folder")
	folder.Name = "TotemZonePreview_" .. tostring(zoneId)
	folder.Parent = workspace
	
	if not activePreviews[zoneId] then
		activePreviews[zoneId] = {}
	end
	activePreviews[zoneId].folder = folder
	activePreviews[zoneId].segments = {}
	activePreviews[zoneId].prevCount = 0
	
	return folder
end

local function findNearestTotem()
	local facilities = workspace:FindFirstChild("Facilities")
	if not facilities then
		return nil
	end

	local player = Players.LocalPlayer
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local maxDist = Balance.TOTEM_PROXIMITY_SHOW_RANGE or 65
	local nearest = nil
	local nearestDist = maxDist

	for _, obj in ipairs(facilities:GetChildren()) do
		if not (obj:IsA("Model") or obj:IsA("BasePart")) then
			continue
		end
		if obj:GetAttribute("FacilityId") ~= "CAMP_TOTEM" then
			continue
		end
		local pp
		if obj:IsA("Model") then
			pp = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")
		else
			pp = obj
		end
		if not pp then
			continue
		end
		local dist = (hrp.Position - pp.Position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = obj
		end
	end

	return nearest
end

local function requestInfo(structureId, callback)
	local ok, result = NetClient.Request("Totem.GetInfo.Request", { structureId = structureId })
	if ok and type(result) == "table" and result.success then
		local data = result.data
		infoCache[structureId] = {
			data = data,
			fetchedAt = tick(),
		}
		if callback then
			callback(true, data)
		end
		return true, data
	end
	if callback then
		callback(false, data)
	end
	return false, data
end

local function requestOwnInfo(callback)
	if ownInfoRequestPending then
		return false, "PENDING"
	end
	ownInfoRequestPending = true

	local ok, result = NetClient.Request("Totem.GetInfo.Request", {})
	ownInfoRequestPending = false
	ownInfoFetchedAt = tick()

	if ok and type(result) == "table" and result.success then
		local data = result.data
		if tonumber(data.ownerId) == Players.LocalPlayer.UserId then
			ownInfoCache = data
			if callback then
				callback(true, data)
			end
			return true, data
		end
	end

	if callback then
		callback(false, data)
	end
	return false, data
end

local function getStarterZoneInfo()
	local center = nil
	local spawnPart = workspace:FindFirstChild("SpawnLocation", true)
	if spawnPart then
		if spawnPart:IsA("BasePart") then
			center = spawnPart.Position
		elseif spawnPart:IsA("Model") then
			local ok, pivot = pcall(function()
				return spawnPart:GetPivot()
			end)
			if ok and pivot then
				center = pivot.Position
			elseif spawnPart.PrimaryPart then
				center = spawnPart.PrimaryPart.Position
			end
		end
	elseif SpawnConfig and typeof(SpawnConfig.DEFAULT_START_SPAWN) == "Vector3" then
		center = SpawnConfig.DEFAULT_START_SPAWN
	end

	if not center then
		return nil
	end

	return {
		centerPosition = center,
		radius = Balance.STARTER_PROTECTION_RADIUS or 45,
		westExtent = Balance.STARTER_PROTECTION_RADIUS or 45,
		eastExtent = Balance.STARTER_PROTECTION_RADIUS or 45,
		northExtent = Balance.STARTER_PROTECTION_RADIUS or 45,
		southExtent = Balance.STARTER_PROTECTION_RADIUS or 45,
	}
end

local function getCachedInfo(structureId)
	local entry = infoCache[structureId]
	if not entry then
		return nil
	end
	if (tick() - entry.fetchedAt) > INFO_CACHE_TTL then
		return nil
	end
	return entry.data
end

local function getCachedOwnInfo()
	if type(ownInfoCache) ~= "table" then
		return nil
	end
	if (tick() - ownInfoFetchedAt) > OWN_INFO_CACHE_TTL then
		return nil
	end
	return ownInfoCache
end

local function resolvePlayerName(userId)
	if playerNameCache[userId] then
		return playerNameCache[userId]
	end
	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		playerNameCache[userId] = onlinePlayer.DisplayName
		return onlinePlayer.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		playerNameCache[userId] = name
		return name
	end
	return "???"
end

local function checkTerritoryEntry(hrpPos)
	local localUserId = Players.LocalPlayer.UserId
	local detectedOwner = nil

	for _, entry in pairs(infoCache) do
		local info = entry.data
		if type(info) == "table" and typeof(info.centerPosition) == "Vector3" and info.ownerId then
			local ownerId = tonumber(info.ownerId)
			if ownerId and ownerId ~= localUserId then
				local extents = getExtentsFromInfo(info, Balance.BASE_DEFAULT_RADIUS or 30)
				local dxLeft = hrpPos.X - info.centerPosition.X
				local dzForward = hrpPos.Z - info.centerPosition.Z
				if dxLeft >= -extents.west and dxLeft <= extents.east and dzForward >= -extents.south and dzForward <= extents.north then
					detectedOwner = ownerId
					break
				end
			end
		end
	end

	if detectedOwner and detectedOwner ~= currentTerritoryOwnerId then
		currentTerritoryOwnerId = detectedOwner
		local now = tick()
		local lastNotified = territoryNotifyCooldown[detectedOwner]
		if not lastNotified or (now - lastNotified) > TERRITORY_NOTIFY_COOLDOWN then
			territoryNotifyCooldown[detectedOwner] = now
			task.spawn(function()
				local ownerName = resolvePlayerName(detectedOwner)
				local UIManager = require(Client.UIManager)
				UIManager.sideNotify(ownerName .. " 's territory.", Color3.fromRGB(220, 200, 140))
			end)
		end
	elseif not detectedOwner then
		currentTerritoryOwnerId = nil
	end
end

local function renderPreviewRing(zoneId, centerPos: Vector3, infoOrRadius: any, _color: Color3, transparency: number, _excludeModel: Instance?)
	local template = getFenceTemplate()
	if not template then return end

	local centerX, centerY, centerZ = centerPos.X, centerPos.Y, centerPos.Z
	local extents = type(infoOrRadius) == "table" and getExtentsFromInfo(infoOrRadius) or getExtentsFromInfo(nil, tonumber(infoOrRadius) or (Balance.BASE_DEFAULT_RADIUS or 30))

	-- Terrain height tracking
	local terrainY = centerY
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local rayResult = workspace:Raycast(Vector3.new(centerX, centerY + 180, centerZ), Vector3.new(0, -500, 0), rayParams)
	if rayResult then
		terrainY = rayResult.Position.Y
	end

	local folder = ensureZoneFolder(zoneId)
	local p = activePreviews[zoneId]

	local west = math.max(1, extents.west - PREVIEW_BORDER_WIDTH)
	local east = math.max(1, extents.east - PREVIEW_BORDER_WIDTH)
	local north = math.max(1, extents.north - PREVIEW_BORDER_WIDTH)
	local south = math.max(1, extents.south - PREVIEW_BORDER_WIDTH)
	local sideLenX = west + east
	local sideLenZ = north + south
	local segPerNorthSouth = math.max(1, math.ceil(sideLenX / fenceSegmentWidth))
	local segPerEastWest = math.max(1, math.ceil(sideLenZ / fenceSegmentWidth))
	local totalNeeded = segPerNorthSouth * 2 + segPerEastWest * 2

	-- Recreate segments if count changed
	if totalNeeded ~= p.prevCount then
		for _, seg in ipairs(p.segments) do
			if seg and seg.Parent then seg:Destroy() end
		end
		p.segments = {}

		for i = 1, totalNeeded do
			local clone = template:Clone()
			clone.Name = "Fence_" .. i
			local parts = clone:IsA("Model") and clone:GetDescendants() or { clone }
			for _, part in ipairs(parts) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
				end
			end
			clone.Parent = folder
			p.segments[i] = clone
		end
		p.prevCount = totalNeeded
	end

	-- Apply transparency and color
	for _, seg in ipairs(p.segments) do
		if seg and seg.Parent then
			local parts = seg:IsA("Model") and seg:GetDescendants() or { seg }
			for _, part in ipairs(parts) do
				if part:IsA("BasePart") then
					part.Transparency = transparency
					part.Color = _color
				end
			end
		end
	end

	-- Arrange fences on 4 sides
	local baseY = terrainY + fencePivotOffsetY
	local sides = {
		{ axis = "X", count = segPerNorthSouth, offset = Vector3.new((east - west) * 0.5, 0, north), length = sideLenX, rotY = 0 },
		{ axis = "X", count = segPerNorthSouth, offset = Vector3.new((east - west) * 0.5, 0, -south), length = sideLenX, rotY = math.pi },
		{ axis = "Z", count = segPerEastWest, offset = Vector3.new(east, 0, (north - south) * 0.5), length = sideLenZ, rotY = math.pi / 2 },
		{ axis = "Z", count = segPerEastWest, offset = Vector3.new(-west, 0, (north - south) * 0.5), length = sideLenZ, rotY = -math.pi / 2 },
	}

	local idx = 0
	for _, side in ipairs(sides) do
		local axis, offset, rotY = side.axis, side.offset, side.rotY
		for s = 1, side.count do
			idx += 1
			local seg = p.segments[idx]
			if not seg then continue end

			local along = ((s - 0.5) / side.count - 0.5) * side.length
			local pos
			if axis == "X" then
				pos = Vector3.new(centerX + along, baseY, centerZ) + offset
			else
				pos = Vector3.new(centerX, baseY, centerZ + along) + offset
			end

			local cf = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)
			if seg:IsA("Model") then
				seg:PivotTo(cf)
			else
				seg.CFrame = cf
			end
		end
	end
	
	p.lastRenderedAt = tick()
end

local function refreshNearbyPreview()
	if isTeleporting then return end 

	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hidePreview()
		return
	end
	
	local now = tick()
	local hrpPos = hrp.Position

	-- 1. Own territory
	local ownInfo = getCachedOwnInfo()
	if not ownInfo then
		task.spawn(function() requestOwnInfo() end)
	end
	ownInfo = ownInfo or ownInfoCache
	if type(ownInfo) == "table" and typeof(ownInfo.centerPosition) == "Vector3" then
		local ownActive = ownInfo.upkeep and ownInfo.upkeep.active
		renderPreviewRing(
			"OWN",
			ownInfo.centerPosition,
			ownInfo,
			ownActive and OWN_PREVIEW_COLOR_ACTIVE or OWN_PREVIEW_COLOR_INACTIVE,
			ownActive and 0.3 or 0.5
		)
	end

	-- 2. Starter zone
	local starterZone = getStarterZoneInfo()
	if starterZone then
		local showRange = Balance.STARTER_PROTECTION_SHOW_RANGE or 130
		if (hrpPos - starterZone.centerPosition).Magnitude <= showRange then
			renderPreviewRing("STARTER", starterZone.centerPosition, starterZone, STARTER_PREVIEW_COLOR, 0.3)
		else
			destroyPreviewZone("STARTER")
		end
	end

	-- 2.5 Portal restricted zones
	local PORTAL_COLORS = {
		Portal_Tropical = Color3.fromRGB(120, 255, 120),
		Portal_Return_Tropical = Color3.fromRGB(120, 255, 120),
		Portal_Desert = Color3.fromRGB(255, 240, 120),
		Portal_Return_Desert = Color3.fromRGB(255, 240, 120),
		Portal_Snowy = Color3.fromRGB(255, 255, 255),
		Portal_Return_Snowy = Color3.fromRGB(255, 255, 255),
	}

	for _, portalName in ipairs(PORTAL_NAMES) do
		-- Use a more robust cache and search
		local portal = _portalCache[portalName]
		if not (portal and portal.Parent) then
			-- Try direct workspace first, then recursive
			portal = workspace:FindFirstChild(portalName) or workspace:FindFirstChild(portalName, true)
			if portal then
				_portalCache[portalName] = portal
			end
		end

		if portal then
			local pp = nil
			if portal:IsA("Model") then
				pp = portal.PrimaryPart or portal:FindFirstChildWhichIsA("BasePart")
			elseif portal:IsA("BasePart") then
				pp = portal
			end
			
			if pp then
				local dist = (hrpPos - pp.Position).Magnitude
				if dist <= 130 then
					local boxCFrame, boxSize
					if portal:IsA("Model") then
						boxCFrame, boxSize = portal:GetBoundingBox()
					else
						boxCFrame, boxSize = portal.CFrame, portal.Size
					end
					
					-- Use a simple box extent for rendering (Portal zone is usually larger than the model)
					local radius = (math.max(boxSize.X, boxSize.Z) * 0.5) + PORTAL_RESTRICTION_MARGIN
					local portalColor = PORTAL_COLORS[portalName] or PORTAL_PREVIEW_COLOR
					
					renderPreviewRing(
						"PORTAL_" .. portalName,
						boxCFrame.Position,
						{ radius = radius },
						portalColor,
						0.4
					)
				else
					destroyPreviewZone("PORTAL_" .. portalName)
				end
			end
		end
	end

	-- 3. Nearby other players' territories
	local facilities = workspace:FindFirstChild("Facilities")
	if facilities then
		local maxDist = Balance.TOTEM_PROXIMITY_SHOW_RANGE or 150
		local localUserId = Players.LocalPlayer.UserId
		
		for _, obj in ipairs(facilities:GetChildren()) do
			if obj:GetAttribute("FacilityId") ~= "CAMP_TOTEM" then continue end
			
			local sid = obj:GetAttribute("StructureId") or obj.Name
			local pp = nil
			if obj:IsA("Model") then
				pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			elseif obj:IsA("BasePart") then
				pp = obj
			end
			
			if not pp then continue end
			
			local dist = (hrpPos - pp.Position).Magnitude
			if dist <= maxDist then
				local info = getCachedInfo(sid)
				if not info then
					task.spawn(function() requestInfo(sid) end)
				else
					if tonumber(info.ownerId) ~= localUserId then
						local active = info.upkeep and info.upkeep.active
						local centerPos = info.centerPosition or pp.Position
						renderPreviewRing(
							sid, 
							centerPos, 
							info, 
							active and PREVIEW_COLOR_ACTIVE or PREVIEW_COLOR_INACTIVE, 
							active and 0.3 or 0.5
						)
					end
				end
			else
				if sid ~= "OWN" and sid ~= "STARTER" then
					destroyPreviewZone(sid)
				end
			end
		end
	end
	
	-- 4. Cleanup old previews
	for zoneId, p in pairs(activePreviews) do
		if zoneId ~= "OWN" and zoneId ~= "STARTER" and not tostring(zoneId):find("PORTAL_") then
			if (now - (p.lastRenderedAt or 0)) > PREVIEW_REFRESH_INTERVAL * 2 then
				destroyPreviewZone(zoneId)
			end
		end
	end
	
	checkTerritoryEntry(hrpPos)
end

function TotemController.getCurrentStructureId()
	return currentStructureId
end

function TotemController.getInfo(structureId)
	local sid = structureId or currentStructureId
	if not sid then
		return nil
	end
	return getCachedInfo(sid)
end

function TotemController.refreshInfo(structureId, callback)
	local sid = structureId or currentStructureId
	if not sid then
		if callback then
			callback(false, "TOTEM_NOT_FOUND")
		end
		return
	end
	requestInfo(sid, callback)
end

function TotemController.openTotem(structureId)
	currentStructureId = structureId
	requestInfo(structureId, function(ok, data)
		local UIManager = require(Client.UIManager)
		if ok then
			UIManager.openTotem(structureId, data)
		else
			UIManager.notify("Failed to fetch totem info.")
		end
	end)
end

function TotemController.requestPay(days, callback)
	if not currentStructureId then
		if callback then
			callback(false, "TOTEM_NOT_FOUND")
		end
		return
	end

	local ok, data = NetClient.Request("Totem.PayUpkeep.Request", {
		structureId = currentStructureId,
		days = days,
	})

	if ok and type(data) == "table" then
		infoCache[currentStructureId] = {
			data = data,
			fetchedAt = tick(),
		}
	end

	if callback then
		callback(ok, data)
	end
end

function TotemController.requestExpand(direction, callback)
	if not currentStructureId then
		if callback then
			callback(false, "TOTEM_NOT_FOUND")
		end
		return
	end

	local ok, data = NetClient.Request("Totem.Expand.Request", {
		structureId = currentStructureId,
		direction = direction,
	})

	if ok and type(data) == "table" then
		infoCache[currentStructureId] = {
			data = data,
			fetchedAt = tick(),
		}
		if tonumber(data.ownerId) == Players.LocalPlayer.UserId then
			ownInfoCache = data
			ownInfoFetchedAt = tick()
		end
	end

	if callback then
		callback(ok, data)
	end
end

function TotemController.flashPreview()
	local function setFenceTransparency(zoneId, t)
		local p = activePreviews[zoneId]
		if not p or not p.segments then return end
		for _, seg in ipairs(p.segments) do
			if seg and seg.Parent then
				local parts = seg:IsA("Model") and seg:GetDescendants() or { seg }
				for _, part in ipairs(parts) do
					if part:IsA("BasePart") then
						part.Transparency = t
					end
				end
			end
		end
	end
	
	for zoneId, _ in pairs(activePreviews) do
		setFenceTransparency(zoneId, 0.1)
	end
	
	task.delay(0.3, function()
		for zoneId, p in pairs(activePreviews) do
			setFenceTransparency(zoneId, 0.3)
		end
	end)
end

function TotemController.Init()
	if initialized then
		return
	end

	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Folder") and child.Name:find("TotemZonePreview") then
			child:Destroy()
		end
	end

	NetClient.On("Portal.Teleporting", function()
		isTeleporting = true
		hidePreview()
	end)
	NetClient.On("Portal.Arrived", function()
		isTeleporting = false
	end)
	NetClient.On("Portal.Error", function()
		isTeleporting = false
	end)

	NetClient.On("Totem.Upkeep.Changed", function(data)
		if type(data) ~= "table" then
			return
		end
		if tonumber(data.ownerId) == Players.LocalPlayer.UserId then
			ownInfoCache = data
			ownInfoFetchedAt = tick()
		end
		local sid = data.structureId
		if sid then
			infoCache[sid] = {
				data = data,
				fetchedAt = tick(),
			}
		end
		local UIManager = require(Client.UIManager)
		if currentStructureId and sid == currentStructureId then
			UIManager.refreshTotem()
		end
	end)

	NetClient.On("Totem.Upkeep.Expired", function(data)
		if type(data) ~= "table" then
			return
		end
		if tonumber(data.ownerId) == Players.LocalPlayer.UserId then
			if type(ownInfoCache) == "table" and type(ownInfoCache.upkeep) == "table" then
				ownInfoCache.upkeep.active = false
				ownInfoCache.upkeep.remainingSeconds = 0
				ownInfoCache.upkeep.expiresAt = tonumber(data.expiresAt) or (ownInfoCache.upkeep.expiresAt or 0)
			else
				task.spawn(function()
					requestOwnInfo()
				end)
			end
			ownInfoFetchedAt = tick()
		end

		local sid = data.structureId
		if sid then
			local cached = getCachedInfo(sid)
			if type(cached) == "table" and type(cached.upkeep) == "table" then
				cached.upkeep.active = false
				cached.upkeep.remainingSeconds = 0
				cached.upkeep.expiresAt = tonumber(data.expiresAt) or (cached.upkeep.expiresAt or 0)
				infoCache[sid] = {
					data = cached,
					fetchedAt = tick(),
				}
			end
		end

		local UIManager = require(Client.UIManager)
		UIManager.notify("Totem upkeep expired! Territory is now lootable.", Color3.fromRGB(255, 120, 120))
		if currentStructureId and sid and currentStructureId == sid then
			UIManager.refreshTotem()
		end
	end)

	NetClient.On("Base.Relocated", function(data)
		if type(data) ~= "table" then
			return
		end
		if type(ownInfoCache) == "table" then
			if typeof(data.centerPosition) == "Vector3" then
				ownInfoCache.centerPosition = data.centerPosition
			end
			if data.radius then
				ownInfoCache.radius = data.radius
			end
			if data.westExtent then ownInfoCache.westExtent = data.westExtent end
			if data.eastExtent then ownInfoCache.eastExtent = data.eastExtent end
			if data.northExtent then ownInfoCache.northExtent = data.northExtent end
			if data.southExtent then ownInfoCache.southExtent = data.southExtent end
			ownInfoFetchedAt = tick()
		end
		if not ownInfoCache then
			task.spawn(function()
				requestOwnInfo()
			end)
		end
	end)

	NetClient.On("Base.Expanded", function(data)
		if type(data) ~= "table" then
			return
		end
		if type(ownInfoCache) == "table" then
			if data.radius then ownInfoCache.radius = data.radius end
			if data.westExtent then ownInfoCache.westExtent = data.westExtent end
			if data.eastExtent then ownInfoCache.eastExtent = data.eastExtent end
			if data.northExtent then ownInfoCache.northExtent = data.northExtent end
			if data.southExtent then ownInfoCache.southExtent = data.southExtent end
			ownInfoFetchedAt = tick()
		end
	end)

	NetClient.On("Build.Removed", function(data)
		if type(data) ~= "table" or not data.id then
			return
		end
		local removedId = data.id

		if infoCache[removedId] then
			infoCache[removedId] = nil
		end

		if type(ownInfoCache) == "table" and ownInfoCache.structureId == removedId then
			ownInfoCache = nil
			ownInfoFetchedAt = 0
			hidePreview()
		end

		if currentStructureId == removedId then
			currentStructureId = nil
			local UIManager = require(Client.UIManager)
			if UIManager.closeTotem then
				UIManager.closeTotem()
			end
		end

		task.delay(0.5, function()
			requestOwnInfo()
		end)
	end)

	if previewConn then
		previewConn:Disconnect()
		previewConn = nil
	end

	local accum = 0
	previewConn = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < PREVIEW_REFRESH_INTERVAL then
			return
		end
		accum = 0
		refreshNearbyPreview()
	end)

	initialized = true

	task.delay(1.5, function()
		requestOwnInfo()
	end)

	print("[TotemController] Initialized")
end

return TotemController
