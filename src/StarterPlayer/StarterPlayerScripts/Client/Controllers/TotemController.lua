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
local ownInfoCache = nil
local ownInfoFetchedAt = 0
local ownInfoRequestPending = false

-- 사유지 진입 알림 상태
local currentTerritoryOwnerId = nil  -- 현재 위치한 사유지 주인
local territoryNotifyCooldown = {}   -- [ownerId] = lastNotifiedAt
local TERRITORY_NOTIFY_COOLDOWN = 120 -- 같은 사유지 재알림 대기(초)
local playerNameCache = {}            -- [userId] = displayName

local PREVIEW_REFRESH_INTERVAL = 0.35
local INFO_CACHE_TTL = 5
local OWN_INFO_CACHE_TTL = 30
local PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 200, 50)
local PREVIEW_COLOR_INACTIVE = Color3.fromRGB(200, 160, 60)
local OWN_PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 180, 30)
local OWN_PREVIEW_COLOR_INACTIVE = Color3.fromRGB(200, 155, 50)
local STARTER_PREVIEW_COLOR = Color3.fromRGB(100, 180, 255)
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

local function requestOwnInfo(callback)
	if ownInfoRequestPending then
		return false, "PENDING"
	end
	ownInfoRequestPending = true

	local ok, data = NetClient.Request("Totem.GetInfo.Request", {})
	ownInfoRequestPending = false
	ownInfoFetchedAt = tick()

	if ok and type(data) == "table" and tonumber(data.ownerId) == Players.LocalPlayer.UserId then
		ownInfoCache = data
		if callback then
			callback(true, data)
		end
		return true, data
	end

	-- 실패 시 기존 캐시를 지우지 않는다 (일시적 네트워크 오류에도 영역 표시 유지)
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

local function getCachedOwnInfo()
	if type(ownInfoCache) ~= "table" then
		return nil
	end
	if (tick() - ownInfoFetchedAt) > OWN_INFO_CACHE_TTL then
		return nil
	end
	return ownInfoCache
end

-- 플레이어 이름 해석 (온라인 → 캐시)
local function resolvePlayerName(userId)
	if playerNameCache[userId] then
		return playerNameCache[userId]
	end
	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		playerNameCache[userId] = onlinePlayer.DisplayName
		return onlinePlayer.DisplayName
	end
	-- 비동기 조회 (오프라인 플레이어)
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		playerNameCache[userId] = name
		return name
	end
	return "???"
end

-- 사유지 진입 감지 및 알림
local function checkTerritoryEntry(hrpPos)
	local localUserId = Players.LocalPlayer.UserId
	local detectedOwner = nil

	-- 캐시된 모든 토템 정보를 순회하여 현재 위치가 누군가의 사유지 안인지 판별
	for _, entry in pairs(infoCache) do
		local info = entry.data
		if type(info) == "table" and typeof(info.centerPosition) == "Vector3" and info.ownerId then
			local ownerId = tonumber(info.ownerId)
			if ownerId and ownerId ~= localUserId then
				local radius = tonumber(info.radius) or (Balance.BASE_DEFAULT_RADIUS or 30)
				local dx = hrpPos.X - info.centerPosition.X
				local dz = hrpPos.Z - info.centerPosition.Z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= radius then
					detectedOwner = ownerId
					break
				end
			end
		end
	end

	if detectedOwner and detectedOwner ~= currentTerritoryOwnerId then
		-- 새 사유지 진입
		currentTerritoryOwnerId = detectedOwner
		local now = tick()
		local lastNotified = territoryNotifyCooldown[detectedOwner]
		if not lastNotified or (now - lastNotified) > TERRITORY_NOTIFY_COOLDOWN then
			territoryNotifyCooldown[detectedOwner] = now
			task.spawn(function()
				local ownerName = resolvePlayerName(detectedOwner)
				local UIManager = require(Client.UIManager)
				UIManager.sideNotify(ownerName .. " 의 사유지입니다.", Color3.fromRGB(220, 200, 140))
			end)
		end
	elseif not detectedOwner then
		currentTerritoryOwnerId = nil
	end
end

local function renderPreviewRing(centerPos: Vector3, radius: number, color: Color3, transparency: number, excludeModel: Instance?)
	local thickness = math.max(0.8, Balance.TOTEM_PREVIEW_HEIGHT or 1.2)
	local centerX, centerY, centerZ = centerPos.X, centerPos.Y, centerPos.Z

	local terrainY = centerY
	local rayParams = RaycastParams.new()
	-- 지형(Terrain)만 감지하여 나무/풀/건물 등 위에 영역이 뜨지 않도록 함
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local rayResult = workspace:Raycast(Vector3.new(centerX, centerY + 180, centerZ), Vector3.new(0, -500, 0), rayParams)
	if rayResult then
		terrainY = rayResult.Position.Y
	end

	local fill, _ = ensurePreviewParts()
	local fillRadius = math.max(1, radius - PREVIEW_BORDER_WIDTH)
	-- 실린더 중심을 지면에서 thickness/2만큼 내려서 윗면이 지면과 일치하도록 배치
	local baseCFrame = CFrame.new(centerX, terrainY - (thickness * 0.5) + 0.05, centerZ) * CFrame.Angles(0, 0, math.rad(90))

	fill.Size = Vector3.new(thickness, fillRadius * 2, fillRadius * 2)
	fill.CFrame = baseCFrame
	fill.Transparency = transparency
	fill.Color = color
end

local function refreshNearbyPreview()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hidePreview()
		return
	end

	-- 근처 토템 정보를 항상 캐시 (사유지 진입 감지용)
	local nearestTotem = findNearestTotem()
	if nearestTotem then
		local sid = nearestTotem:GetAttribute("StructureId") or nearestTotem.Name
		if not getCachedInfo(sid) then
			task.spawn(function()
				requestInfo(sid)
			end)
		end
	end

	-- 타인 사유지 진입 감지
	checkTerritoryEntry(hrp.Position)

	-- 본인 토템(사유지)은 상시 표시한다.
	local ownInfo = getCachedOwnInfo()
	if not ownInfo then
		task.spawn(function()
			requestOwnInfo()
		end)
	end
	-- 캐시 만료 시에도 이전 데이터로 계속 표시
	ownInfo = ownInfo or ownInfoCache
	if type(ownInfo) == "table" and typeof(ownInfo.centerPosition) == "Vector3" then
		local ownRadius = tonumber(ownInfo.radius) or (Balance.BASE_DEFAULT_RADIUS or 30)
		local ownActive = ownInfo.upkeep and ownInfo.upkeep.active
		renderPreviewRing(
			ownInfo.centerPosition,
			ownRadius,
			ownActive and OWN_PREVIEW_COLOR_ACTIVE or OWN_PREVIEW_COLOR_INACTIVE,
			ownActive and 0.55 or 0.5,
			nil
		)
		return
	end

	local totemModel = nearestTotem
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

		renderPreviewRing(starterZone.centerPosition, starterZone.radius, STARTER_PREVIEW_COLOR, 0.6, nil)
		return
	end

	local pp
	if totemModel:IsA("Model") then
		pp = totemModel.PrimaryPart or totemModel:FindFirstChildWhichIsA("BasePart")
	elseif totemModel:IsA("BasePart") then
		pp = totemModel
	end
	if not pp then
		hidePreview()
		return
	end

	local structureId = totemModel:GetAttribute("StructureId") or totemModel.Name
	local info = getCachedInfo(structureId)

	local radius = (info and tonumber(info.radius)) or (Balance.BASE_DEFAULT_RADIUS or 30)
	local active = info and info.upkeep and info.upkeep.active
	local centerPos = (info and info.centerPosition) or pp.Position
	renderPreviewRing(centerPos, radius, active and PREVIEW_COLOR_ACTIVE or PREVIEW_COLOR_INACTIVE, active and 0.6 or 0.5, totemModel)
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

	-- 게임 시작 직후 본인 토템 정보를 미리 가져온다
	task.delay(1.5, function()
		requestOwnInfo()
	end)

	print("[TotemController] Initialized")
end

return TotemController
