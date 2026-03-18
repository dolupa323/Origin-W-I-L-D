-- TotemController.lua
-- 거점 토템 상호작용/유지비/범위 프리뷰 제어

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
local previewFillPart = nil
local previewBorderPart = nil
local previewConn = nil

local PREVIEW_REFRESH_INTERVAL = 0.35
local INFO_CACHE_TTL = 5
local PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 245, 170)
local PREVIEW_COLOR_INACTIVE = Color3.fromRGB(245, 232, 160)
local STARTER_PREVIEW_COLOR = Color3.fromRGB(190, 228, 255)
local PREVIEW_BORDER_WIDTH = 1.2

local function destroyPreviewParts()
	if previewFillPart then
		previewFillPart:Destroy()
		previewFillPart = nil
	end
	if previewBorderPart then
		previewBorderPart:Destroy()
		previewBorderPart = nil
	end
end

local function ensurePreviewParts()
	if previewFillPart and previewFillPart.Parent and previewBorderPart and previewBorderPart.Parent then
		return previewFillPart, previewBorderPart
	end
	if previewFillPart and previewFillPart.Parent then
		return previewFillPart, nil
	end

	local fill = Instance.new("Part")
	fill.Name = "TotemZonePreviewFill"
	fill.Anchored = true
	fill.CanCollide = false
	fill.CanQuery = false
	fill.CanTouch = false
	fill.Shape = Enum.PartType.Cylinder
	fill.Material = Enum.Material.SmoothPlastic
	fill.Transparency = 0.9
	fill.Color = PREVIEW_COLOR_ACTIVE
	fill.Size = Vector3.new(math.max(0.8, Balance.TOTEM_PREVIEW_HEIGHT or 1.2), 1, 1)
	fill.Parent = workspace
	previewFillPart = fill
	return previewFillPart, nil
end

local function hidePreview()
	destroyPreviewParts()
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

	for _, model in ipairs(facilities:GetChildren()) do
		if not model:IsA("Model") then
			continue
		end
		if model:GetAttribute("FacilityId") ~= "CAMP_TOTEM" then
			continue
		end
		local pp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
		if not pp then
			continue
		end
		local dist = (hrp.Position - pp.Position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = model
		end
	end

	return nearest
end

local function requestInfo(structureId, callback)
	local ok, data = NetClient.Request("Totem.GetInfo.Request", { structureId = structureId })
	if ok and type(data) == "table" then
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

local function refreshNearbyPreview()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hidePreview()
		return
	end

	local totemModel = findNearestTotem()
	if not totemModel then
		local starterZone = getStarterZoneInfo()
		if not starterZone then
			hidePreview()
			return
		end

		local showRange = Balance.STARTER_PROTECTION_SHOW_RANGE or 130
		if (hrp.Position - starterZone.centerPosition).Magnitude > showRange then
			hidePreview()
			return
		end

		local thickness = math.max(0.8, Balance.TOTEM_PREVIEW_HEIGHT or 1.2)
		local centerPos = starterZone.centerPosition
		local centerX, centerY, centerZ = centerPos.X, centerPos.Y, centerPos.Z

		local terrainY = centerY
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local excludeList = {}
		local localCharacter = Players.LocalPlayer and Players.LocalPlayer.Character
		if localCharacter then
			table.insert(excludeList, localCharacter)
		end
		if previewFillPart then
			table.insert(excludeList, previewFillPart)
		end
		if previewBorderPart then
			table.insert(excludeList, previewBorderPart)
		end
		rayParams.FilterDescendantsInstances = excludeList
		local rayResult = workspace:Raycast(Vector3.new(centerX, centerY + 180, centerZ), Vector3.new(0, -500, 0), rayParams)
		if rayResult then
			terrainY = rayResult.Position.Y
		end

		local fill, _ = ensurePreviewParts()
		local fillRadius = math.max(1, starterZone.radius - PREVIEW_BORDER_WIDTH)
		local baseCFrame = CFrame.new(centerX, terrainY + (thickness * 0.5) + 0.03, centerZ) * CFrame.Angles(0, 0, math.rad(90))

		fill.Size = Vector3.new(thickness, fillRadius * 2, fillRadius * 2)
		fill.CFrame = baseCFrame + Vector3.new(0, 0.002, 0)
		fill.Transparency = 0.96
		fill.Color = STARTER_PREVIEW_COLOR
		return
	end

	local pp = totemModel.PrimaryPart or totemModel:FindFirstChildWhichIsA("BasePart")
	if not pp then
		hidePreview()
		return
	end

	local structureId = totemModel:GetAttribute("StructureId") or totemModel.Name
	local info = getCachedInfo(structureId)
	if not info then
		task.spawn(function()
			requestInfo(structureId)
		end)
	end

	local radius = (info and tonumber(info.radius)) or (Balance.BASE_DEFAULT_RADIUS or 30)
	local active = info and info.upkeep and info.upkeep.active
	local thickness = math.max(0.8, Balance.TOTEM_PREVIEW_HEIGHT or 1.2)
	local centerPos = (info and info.centerPosition) or pp.Position
	local centerX = centerPos.X or pp.Position.X
	local centerY = centerPos.Y or pp.Position.Y
	local centerZ = centerPos.Z or pp.Position.Z

	local terrainY = centerY
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = { totemModel }
	local localCharacter = Players.LocalPlayer and Players.LocalPlayer.Character
	if localCharacter then
		table.insert(excludeList, localCharacter)
	end
	if previewFillPart then
		table.insert(excludeList, previewFillPart)
	end
	if previewBorderPart then
		table.insert(excludeList, previewBorderPart)
	end
	rayParams.FilterDescendantsInstances = excludeList
	local rayResult = workspace:Raycast(Vector3.new(centerX, centerY + 180, centerZ), Vector3.new(0, -500, 0), rayParams)
	if rayResult then
		terrainY = rayResult.Position.Y
	end

	local fill, _ = ensurePreviewParts()
	local fillRadius = math.max(1, radius - PREVIEW_BORDER_WIDTH)
	local baseCFrame = CFrame.new(centerX, terrainY + (thickness * 0.5) + 0.03, centerZ) * CFrame.Angles(0, 0, math.rad(90))

	fill.Size = Vector3.new(thickness, fillRadius * 2, fillRadius * 2)
	fill.CFrame = baseCFrame + Vector3.new(0, 0.002, 0)
	fill.Transparency = active and 0.965 or 0.93
	fill.Color = active and PREVIEW_COLOR_ACTIVE or PREVIEW_COLOR_INACTIVE
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
			UIManager.notify("토템 정보를 불러오지 못했습니다.")
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

function TotemController.flashPreview()
	if previewFillPart and previewFillPart.Parent then
		previewFillPart.Transparency = 0.93
	end
		task.delay(0.3, function()
			if previewFillPart and previewFillPart.Parent then
				previewFillPart.Transparency = 0.965
			end
		end)
end

function TotemController.Init()
	if initialized then
		return
	end

	-- 이전 세션/핫리로드 잔존 프리뷰 파트 정리
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("BasePart") and (child.Name == "TotemZonePreviewFill" or child.Name == "TotemZonePreviewBorder") then
			child:Destroy()
		end
	end

	NetClient.On("Totem.Upkeep.Changed", function(data)
		if type(data) ~= "table" then
			return
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
		UIManager.notify("⚠ 토템 유지비가 만료되었습니다. 거점이 약탈 가능 상태가 되었습니다.", Color3.fromRGB(255, 120, 120))
		if UIManager.sideNotify then
			UIManager.sideNotify("토템 만료: 거점 약탈 가능", Color3.fromRGB(255, 120, 120))
		end
		if currentStructureId and sid and currentStructureId == sid then
			UIManager.refreshTotem()
		end
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
	print("[TotemController] Initialized")
end

return TotemController
