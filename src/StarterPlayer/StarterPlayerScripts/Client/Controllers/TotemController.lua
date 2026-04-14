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
local previewFolder = nil     -- 울타리 세그먼트 폴더
local fenceSegments = {}      -- 복제된 울타리 세그먼트 배열
local fenceTemplate = nil     -- 울타리 모델 원본 (ReplicatedStorage)
local fenceSegmentWidth = 4   -- 기본값, 실제 모델에서 자동 측정
local fencePivotOffsetY = 0   -- 피벗~바닥 오프셋
local prevSegmentCount = 0    -- 세그먼트 수 변경 감지용
local previewConn = nil
local ownInfoCache = nil
local ownInfoFetchedAt = 0
local ownInfoRequestPending = false
local isTeleporting = false -- 텔레포트 중 네트워크 요청 중단 플래그

-- 사유지 진입 알림 상태
local currentTerritoryOwnerId = nil  -- 현재 위치한 사유지 주인
local territoryNotifyCooldown = {}   -- [ownerId] = lastNotifiedAt
local TERRITORY_NOTIFY_COOLDOWN = 120 -- 같은 사유지 재알림 대기(초)
local playerNameCache = {}            -- [userId] = displayName

local PREVIEW_REFRESH_INTERVAL = 0.35
local INFO_CACHE_TTL = 5
local OWN_INFO_CACHE_TTL = 30
local PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 200, 120)
local PREVIEW_COLOR_INACTIVE = Color3.fromRGB(240, 180, 100)
local OWN_PREVIEW_COLOR_ACTIVE = Color3.fromRGB(255, 195, 110)
local OWN_PREVIEW_COLOR_INACTIVE = Color3.fromRGB(235, 175, 95)
local STARTER_PREVIEW_COLOR = Color3.fromRGB(170, 210, 255)
local PREVIEW_BORDER_WIDTH = 1.2

local function getExtentsFromInfo(info, fallbackRadius)
	local radius = tonumber(fallbackRadius) or tonumber(info and info.radius) or (Balance.BASE_DEFAULT_RADIUS or 30)
	return {
		west = tonumber(info and info.westExtent) or radius,
		east = tonumber(info and info.eastExtent) or radius,
		north = tonumber(info and info.northExtent) or radius,
		south = tonumber(info and info.southExtent) or radius,
	}
end

local function destroyPreviewParts()
	for _, seg in ipairs(fenceSegments) do
		if seg and seg.Parent then
			seg:Destroy()
		end
	end
	fenceSegments = {}
	prevSegmentCount = 0
	if previewFolder then
		previewFolder:Destroy()
		previewFolder = nil
	end
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

local function ensureFolder()
	if previewFolder and previewFolder.Parent then return end
	destroyPreviewParts()
	local folder = Instance.new("Folder")
	folder.Name = "TotemZonePreview"
	folder.Parent = workspace
	previewFolder = folder
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

local function renderPreviewRing(centerPos: Vector3, infoOrRadius: any, _color: Color3, transparency: number, _excludeModel: Instance?)
	local template = getFenceTemplate()
	if not template then return end

	local centerX, centerY, centerZ = centerPos.X, centerPos.Y, centerPos.Z
	local extents = type(infoOrRadius) == "table" and getExtentsFromInfo(infoOrRadius) or getExtentsFromInfo(nil, tonumber(infoOrRadius) or (Balance.BASE_DEFAULT_RADIUS or 30))

	-- 지형 높이 추적
	local terrainY = centerY
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local rayResult = workspace:Raycast(Vector3.new(centerX, centerY + 180, centerZ), Vector3.new(0, -500, 0), rayParams)
	if rayResult then
		terrainY = rayResult.Position.Y
	end

	ensureFolder()
	local west = math.max(1, extents.west - PREVIEW_BORDER_WIDTH)
	local east = math.max(1, extents.east - PREVIEW_BORDER_WIDTH)
	local north = math.max(1, extents.north - PREVIEW_BORDER_WIDTH)
	local south = math.max(1, extents.south - PREVIEW_BORDER_WIDTH)
	local sideLenX = west + east
	local sideLenZ = north + south
	local segPerNorthSouth = math.max(1, math.ceil(sideLenX / fenceSegmentWidth))
	local segPerEastWest = math.max(1, math.ceil(sideLenZ / fenceSegmentWidth))
	local totalNeeded = segPerNorthSouth * 2 + segPerEastWest * 2

	-- 세그먼트 수가 바뀌면 재생성
	if totalNeeded ~= prevSegmentCount then
		for _, seg in ipairs(fenceSegments) do
			if seg and seg.Parent then seg:Destroy() end
		end
		fenceSegments = {}

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
			clone.Parent = previewFolder
			fenceSegments[i] = clone
		end
		prevSegmentCount = totalNeeded
	end

	-- 투명도 적용 (모델 원본 색상/재질 유지)
	for _, seg in ipairs(fenceSegments) do
		if seg and seg.Parent then
			local parts = seg:IsA("Model") and seg:GetDescendants() or { seg }
			for _, part in ipairs(parts) do
				if part:IsA("BasePart") then
					part.Transparency = transparency
				end
			end
		end
	end

	-- 4면에 울타리 배치
	local baseY = terrainY + fencePivotOffsetY

	-- 각 면: {along축, edge오프셋, 회전Y}
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
			local seg = fenceSegments[idx]
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
end

local function refreshNearbyPreview()
	if isTeleporting then return end -- 텔레포트 중에는 불필요한 네트워크 요청 및 UI 갱신 방지

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
		local ownActive = ownInfo.upkeep and ownInfo.upkeep.active
		renderPreviewRing(
			ownInfo.centerPosition,
			ownInfo,
			ownActive and OWN_PREVIEW_COLOR_ACTIVE or OWN_PREVIEW_COLOR_INACTIVE,
			ownActive and 0.3 or 0.5,
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

		renderPreviewRing(starterZone.centerPosition, starterZone, STARTER_PREVIEW_COLOR, 0.3, nil)
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

	local active = info and info.upkeep and info.upkeep.active
	local centerPos = (info and info.centerPosition) or pp.Position
	renderPreviewRing(centerPos, info or { radius = Balance.BASE_DEFAULT_RADIUS or 30 }, active and PREVIEW_COLOR_ACTIVE or PREVIEW_COLOR_INACTIVE, active and 0.3 or 0.5, totemModel)
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
	local function setFenceTransparency(t)
		for _, seg in ipairs(fenceSegments) do
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
	setFenceTransparency(0.1)
	task.delay(0.3, function()
		setFenceTransparency(0.3)
	end)
end

function TotemController.Init()
	if initialized then
		return
	end

	-- 이전 세션/핫리로드 잔존 프리뷰 파트 정리
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Folder") and child.Name == "TotemZonePreview" then
			child:Destroy()
		elseif child:IsA("BasePart") and (child.Name == "TotemZonePreviewFill" or child.Name == "TotemZonePreviewBorder" or child.Name == "TotemZonePreviewInner" or child.Name == "TotemZonePreviewBottom") then
			child:Destroy()
		end
	end

	-- 텔레포트 대역폭 병목 처리
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
		UIManager.notify("⚠ 토템 유지비가 만료되었습니다. 거점이 약탈 가능 상태가 되었습니다.", Color3.fromRGB(255, 120, 120))
		if UIManager.sideNotify then
			UIManager.sideNotify("토템 만료: 거점 약탈 가능", Color3.fromRGB(255, 120, 120))
		end
		if currentStructureId and sid and currentStructureId == sid then
			UIManager.refreshTotem()
		end
	end)

	-- 베이스 중심 이동 수신 → 영역 표시 즉시 갱신
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
		-- 캐시 없으면 즉시 재요청
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

	-- 토템 철거/이동 시 영역 표시 즉시 갱신
	NetClient.On("Build.Removed", function(data)
		if type(data) ~= "table" or not data.id then
			return
		end
		local removedId = data.id

		-- 해당 구조물 캐시 제거
		if infoCache[removedId] then
			infoCache[removedId] = nil
		end

		-- 본인 토템이 철거된 경우 캐시 초기화 + 영역 숨김
		if type(ownInfoCache) == "table" and ownInfoCache.structureId == removedId then
			ownInfoCache = nil
			ownInfoFetchedAt = 0
			hidePreview()
		end

		-- 현재 열려있는 토템 UI가 철거된 토템이면 닫기
		if currentStructureId == removedId then
			currentStructureId = nil
			local UIManager = require(Client.UIManager)
			if UIManager.closeTotem then
				UIManager.closeTotem()
			end
		end

		-- 본인 토템 정보 재요청 (이동/재배치 대응)
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

	-- 게임 시작 직후 본인 토템 정보를 미리 가져온다
	task.delay(1.5, function()
		requestOwnInfo()
	end)

	print("[TotemController] Initialized")
end

return TotemController
