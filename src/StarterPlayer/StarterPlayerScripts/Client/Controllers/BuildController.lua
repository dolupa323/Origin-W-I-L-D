-- BuildController.lua
-- 클라이언트 건설 컨트롤러
-- 서버 Build 이벤트 수신 및 로컬 캐시 관리 + 건축 배치(Ghost) 로직

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local NetClient = require(script.Parent.Parent.NetClient)
local InputManager = require(script.Parent.Parent.InputManager)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

local BuildController = {}

--========================================
-- Private State
--========================================
local player = Players.LocalPlayer
local initialized = false

-- 로컬 구조물 캐시 [structureId] = { id, facilityId, position, rotation, health, ownerId }
local structuresCache = {}
local structureCount = 0

-- Placement Mode State
local isPlacing = false
local currentFacilityId = nil
local currentGhost = nil
local currentRotation = 0 -- Degree
local currentPlacementYawOffset = 0 -- Facility-specific forward-axis correction (Degree)
local currentPlacementTiltOffset = Vector3.new(0, 0, 0) -- Facility-specific X/Z tilt correction (Degree)
local currentPlacementGroundPosition = nil
local currentGhostGroundOffset = 0
local currentGhostBoundsSize = Vector3.new(4, 4, 4)
local currentIsPlaceable = false
local heartbeatConn = nil

local MAX_PLACE_DISTANCE = 35
local DEFAULT_MAX_GROUND_SLOPE_DEG = Balance.BUILD_MAX_GROUND_SLOPE_DEG or 42
local STRICT_MAX_GROUND_SLOPE_DEG = Balance.BUILD_STRICT_MAX_GROUND_SLOPE_DEG or 12

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

-- World Durability Bar (look-at structure)
local lookConn = nil
local durabilityBillboard = nil
local durabilityFill = nil
local durabilityLabel = nil
local durabilityTitle = nil
local focusedStructureId = nil
local lookRayAccumulator = 0

--========================================
-- Helpers
--========================================

local function createGhost(facilityId)
	local facilityData = DataHelper.GetData("FacilityData", facilityId)
	if not facilityData then return nil end

	-- ReplicatedStorage/Assets/FacilityModels 에서 모델 복사 시도
	local models = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FacilityModels")
	local sourceModel = nil
	if models then
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
			sourceModel = models:FindFirstChild(name)
			if sourceModel then
				break
			end
		end

		if not sourceModel then
			local normalized = {}
			for _, name in ipairs(candidates) do
				normalized[name:lower():gsub("_", "")] = true
			end
			for _, child in ipairs(models:GetChildren()) do
				local key = child.Name:lower():gsub("_", "")
				if normalized[key] then
					sourceModel = child
					break
				end
			end
		end
	end
	
	local ghost
	if sourceModel then
		ghost = sourceModel:Clone()
		if not ghost.PrimaryPart then
			ghost.PrimaryPart = ghost:FindFirstChildWhichIsA("BasePart", true)
		end
	else
		-- 모델이 없으면 임시 박스 생성
		ghost = Instance.new("Model")
		local part = Instance.new("Part")
		part.Size = Vector3.new(4, 4, 4)
		part.Color = Color3.fromRGB(0, 255, 0)
		part.Parent = ghost
		ghost.PrimaryPart = part
	end

	-- Ghost 효과 (반투명 녹색)
	for _, p in ipairs(ghost:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 0.5
			p.Color = Color3.fromRGB(100, 255, 100)
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		elseif p:IsA("Script") or p:IsA("LocalScript") then
			p:Destroy()
		end
	end
	
	ghost.Name = "BUILD_GHOST"
	ghost.Parent = workspace
	return ghost
end

local function computeGhostGroundOffset(ghost: Model): number
	if not ghost or not ghost.PrimaryPart then
		return 0
	end

	local minY = math.huge
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			local pMinY = part.Position.Y - (part.Size.Y * 0.5)
			if pMinY < minY then
				minY = pMinY
			end
		end
	end

	if minY == math.huge then
		local _, fallbackBounds = ghost:GetBoundingBox()
		return math.max(0, fallbackBounds.Y * 0.5)
	end

	local pivotY = ghost:GetPivot().Position.Y
	return math.max(0, pivotY - minY)
end

local function computeGhostBoundsSize(ghost: Model): Vector3
	if not ghost then
		return Vector3.new(4, 4, 4)
	end
	local _, bounds = ghost:GetBoundingBox()
	return Vector3.new(
		math.max(bounds.X, 1),
		math.max(bounds.Y, 1),
		math.max(bounds.Z, 1)
	)
end

local function resolvePlacementTiltOffset(facilityId: string, facilityData: any, ghost: Model): Vector3
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

	if facilityId == "LEAN_TO" and ghost then
		local rx, _, rz = ghost:GetPivot():ToOrientation()
		return Vector3.new(math.deg(rx), 0, math.deg(rz))
	end

	return Vector3.new(0, 0, 0)
end

local function isEmptyFieldHit(result: RaycastResult): boolean
	if not result or not result.Instance then
		return false
	end

	local hit = result.Instance
	if hit == workspace.Terrain and result.Material == Enum.Material.Water then
		return false
	end

	local disallowedMaterials = {
		[Enum.Material.Water] = true,
	}

	if disallowedMaterials[result.Material] then
		return false
	end

	local strict = isStrictFieldProfile()
	if strict then
		if hit ~= workspace.Terrain then
			return false
		end

		local strictAllowedTerrainMaterial = {
			[Enum.Material.Grass] = true,
			[Enum.Material.Ground] = true,
			[Enum.Material.LeafyGrass] = true,
			[Enum.Material.Mud] = true,
		}
		if not strictAllowedTerrainMaterial[result.Material] then
			return false
		end
	end

	if result.Material == Enum.Material.Water then
		return false
	end

	local facilitiesFolder = workspace:FindFirstChild("Facilities")
	if facilitiesFolder and hit:IsDescendantOf(facilitiesFolder) then
		return false
	end
	local nodesFolder = workspace:FindFirstChild("ResourceNodes")
	if nodesFolder and hit:IsDescendantOf(nodesFolder) then
		return false
	end
	local npcsFolder = workspace:FindFirstChild("NPCs")
	if npcsFolder and hit:IsDescendantOf(npcsFolder) then
		return false
	end
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if creaturesFolder and hit:IsDescendantOf(creaturesFolder) then
		return false
	end
	local charactersFolder = workspace:FindFirstChild("Characters")
	if charactersFolder and hit:IsDescendantOf(charactersFolder) then
		return false
	end

	local model = hit:FindFirstAncestorWhichIsA("Model")
	if model and (model:GetAttribute("NodeId") or model:GetAttribute("StructureId") or model:GetAttribute("NPCId")) then
		return false
	end

	return true
end

local function isBlockedByWorld(finalCF: CFrame, surfaceInstance: Instance?): boolean
	if not currentGhost then
		return true
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = { currentGhost }
	if player.Character then
		table.insert(excludeList, player.Character)
	end
	overlap.FilterDescendantsInstances = excludeList

	local querySize = currentGhostBoundsSize + Vector3.new(0.35, 0.2, 0.35)
	local parts = workspace:GetPartBoundsInBox(finalCF, querySize, overlap)
	for _, part in ipairs(parts) do
		if surfaceInstance and part == surfaceInstance then
			continue
		end
		if part:IsDescendantOf(currentGhost) then
			continue
		end
		if part.Transparency >= 1 and not part.CanCollide then
			continue
		end
		return true
	end

	return false
end

local function getStructureModel(structureId: string)
	local facilitiesFolder = workspace:FindFirstChild("Facilities")
	if not facilitiesFolder then return nil end
	return facilitiesFolder:FindFirstChild(structureId)
end

local function getAdorneeFromModel(model: Instance)
	if not model then return nil end
	if model:IsA("Model") then
		return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	elseif model:IsA("BasePart") then
		return model
	end
	return nil
end

local function ensureDurabilityBillboard()
	if durabilityBillboard then return end

	durabilityBillboard = Instance.new("BillboardGui")
	durabilityBillboard.Name = "StructureDurabilityBar"
	durabilityBillboard.Size = UDim2.new(0, 140, 0, 34)
	durabilityBillboard.StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0)
	durabilityBillboard.AlwaysOnTop = true
	durabilityBillboard.MaxDistance = 70
	durabilityBillboard.Enabled = false
	durabilityBillboard.Parent = player:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.45
	bg.BorderSizePixel = 0
	bg.Parent = durabilityBillboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	durabilityTitle = Instance.new("TextLabel")
	durabilityTitle.Name = "Title"
	durabilityTitle.Size = UDim2.new(1, -8, 0, 14)
	durabilityTitle.Position = UDim2.new(0, 4, 0, 1)
	durabilityTitle.BackgroundTransparency = 1
	durabilityTitle.Font = Enum.Font.GothamBold
	durabilityTitle.TextSize = 10
	durabilityTitle.TextColor3 = Color3.fromRGB(255, 235, 170)
	durabilityTitle.TextStrokeTransparency = 0.7
	durabilityTitle.TextXAlignment = Enum.TextXAlignment.Center
	durabilityTitle.Text = UILocalizer.Localize("시설")
	durabilityTitle.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBG"
	barBg.Size = UDim2.new(1, -10, 0, 10)
	barBg.Position = UDim2.new(0, 5, 1, -14)
	barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = barBg

	durabilityFill = Instance.new("Frame")
	durabilityFill.Name = "Fill"
	durabilityFill.Size = UDim2.new(1, 0, 1, 0)
	durabilityFill.BackgroundColor3 = Color3.fromRGB(95, 200, 120)
	durabilityFill.BorderSizePixel = 0
	durabilityFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = durabilityFill

	durabilityLabel = Instance.new("TextLabel")
	durabilityLabel.Name = "Percent"
	durabilityLabel.Size = UDim2.new(1, 0, 1, 0)
	durabilityLabel.BackgroundTransparency = 1
	durabilityLabel.Font = Enum.Font.GothamSemibold
	durabilityLabel.TextSize = 9
	durabilityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	durabilityLabel.Text = "100%"
	durabilityLabel.Parent = barBg
end

local function hideWorldDurabilityBar()
	focusedStructureId = nil
	if durabilityBillboard then
		durabilityBillboard.Enabled = false
		durabilityBillboard.Adornee = nil
	end
end

local function updateWorldDurabilityBar(structureId: string)
	local struct = structuresCache[structureId]
	if not struct then
		hideWorldDurabilityBar()
		return
	end

	local facilityData = DataHelper.GetData("FacilityData", struct.facilityId)
	if not facilityData or not facilityData.maxHealth or facilityData.maxHealth <= 0 then
		hideWorldDurabilityBar()
		return
	end

	local model = getStructureModel(structureId)
	local adornee = getAdorneeFromModel(model)
	if not adornee then
		hideWorldDurabilityBar()
		return
	end

	ensureDurabilityBillboard()
	local ratio = math.clamp((struct.health or 0) / facilityData.maxHealth, 0, 1)

	durabilityBillboard.Adornee = adornee
	durabilityBillboard.Enabled = true
	focusedStructureId = structureId

	if durabilityTitle then
		durabilityTitle.Text = UILocalizer.Localize(facilityData.name or struct.facilityId or "시설")
	end

	if durabilityLabel then
		durabilityLabel.Text = string.format("%d%%", math.floor(ratio * 100))
	end

	if durabilityFill then
		TweenService:Create(durabilityFill, TweenInfo.new(0.1), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		if ratio < 0.25 then
			durabilityFill.BackgroundColor3 = Color3.fromRGB(210, 80, 80)
		elseif ratio < 0.5 then
			durabilityFill.BackgroundColor3 = Color3.fromRGB(220, 150, 70)
		else
			durabilityFill.BackgroundColor3 = Color3.fromRGB(95, 200, 120)
		end
	end
end

local function getLookedStructureId(): string?
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)

	local facilitiesFolder = workspace:FindFirstChild("Facilities")
	if not facilitiesFolder then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { facilitiesFolder }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 90, params)
	if not result then return nil end

	local hit = result.Instance
	if not hit then return nil end
	local model = hit:FindFirstAncestorWhichIsA("Model")

	return hit:GetAttribute("StructureId")
		or (hit.Parent and hit.Parent:GetAttribute("StructureId"))
		or (model and model:GetAttribute("StructureId"))
		or (model and model.Name)
end

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
-- Public API: Build Requests & Placement
--========================================

--- 건설 배치 모드 시작
function BuildController.startPlacement(facilityId: string)
	if isPlacing then BuildController.cancelPlacement() end
	
	local facilityData = DataHelper.GetData("FacilityData", facilityId)
	if not facilityData then return end
	
	currentFacilityId = facilityId
	currentGhost = createGhost(facilityId)
	if not currentGhost then return end
	
	isPlacing = true
	currentRotation = 0
	currentPlacementYawOffset = tonumber(facilityData.placementYawOffset) or 0
	currentPlacementTiltOffset = resolvePlacementTiltOffset(facilityId, facilityData, currentGhost)
	currentPlacementGroundPosition = nil
	currentGhostGroundOffset = computeGhostGroundOffset(currentGhost)
	currentGhostBoundsSize = computeGhostBoundsSize(currentGhost)
	currentIsPlaceable = false
	
	-- 매 프레임 위치 업데이트
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not currentGhost then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		
		-- 마우스가 가리키는 지면 찾기
		local rayParams = RaycastParams.new()
		local filterList = { currentGhost }
		if player.Character then
			table.insert(filterList, player.Character)
		end
		rayParams.FilterDescendantsInstances = filterList
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local mousePos = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 150, rayParams) -- 사거리 소폭 상향
		
		local isPlaceable = false
		local finalCF = nil
		
		if result then
			local hitPos = result.Position
			local hitNormal = result.Normal
			local hitPart = result.Instance
			currentPlacementGroundPosition = hitPos

			-- 기본 위치 설정 (빈 들판만 허용, 경사면 정렬 금지)
			local yaw = currentRotation + currentPlacementYawOffset
			local pitch = currentPlacementTiltOffset.X
			local roll = currentPlacementTiltOffset.Z
			finalCF = CFrame.new(hitPos + Vector3.new(0, currentGhostGroundOffset, 0))
				* CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
			
			if currentGhost.PrimaryPart then
				currentGhost:SetPrimaryPartCFrame(finalCF)
			end
			
			-- 건설 가능 조건 체크
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = (hrp.Position - hitPos).Magnitude
				isPlaceable = (dist <= MAX_PLACE_DISTANCE)
			else
				isPlaceable = false
			end

			local dot = hitNormal:Dot(Vector3.new(0, 1, 0))
			local slope = math.deg(math.acos(math.clamp(dot, -1, 1)))
			if slope > getMaxGroundSlopeDeg() then
				isPlaceable = false
			end

			if not isEmptyFieldHit(result) then
				isPlaceable = false
			end

			if isPlaceable and finalCF and isBlockedByWorld(finalCF, hitPart) then
				isPlaceable = false
			end
		else
			isPlaceable = false
			currentPlacementGroundPosition = nil
		end

		currentIsPlaceable = isPlaceable

		
		-- Ghost 색상 업데이트
		local color = isPlaceable and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
		for _, p in ipairs(currentGhost:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Color = color
				p.Transparency = 0.6
			end
		end
	end)
	
	-- 키 입력 바인딩 (R: 회전, X/ESC/우클릭: 취소)
	InputManager.bindKey(Enum.KeyCode.R, "BuildRotate", function()
		currentRotation = (currentRotation + 45) % 360
	end)
	
	InputManager.bindKey(Enum.KeyCode.X, "BuildCancel", function()
		BuildController.cancelPlacement()
	end)

	InputManager.bindKey(Enum.KeyCode.Escape, "BuildCancelEsc", function()
		BuildController.cancelPlacement()
	end)

	InputManager.onRightClick("BuildCancel", function()
		BuildController.cancelPlacement()
	end)
	
	-- 좌클릭: 배치 확정
	InputManager.onLeftClick("BuildPlace", function()
		if isPlacing and currentGhost then
			if not currentIsPlaceable then
				local UIManager = require(script.Parent.Parent.UIManager)
				UIManager.notify("이 위치에는 건설할 수 없습니다.", Color3.fromRGB(255, 100, 100))
				return
			end
			
			local pos = currentPlacementGroundPosition or currentGhost.PrimaryPart.Position
			-- rotation은 currentRotation 기반 또는 Ghost의 실제 rotation 전달
			local rot = Vector3.new(0, (currentRotation + currentPlacementYawOffset) % 360, 0)
			BuildController.requestPlace(currentFacilityId, pos, rot)
		end
	end)

    -- UI 가이드 표시 (UIManager 연동은 UIManager에서 처리하거나 여기서 호출)
    local UIManager = require(script.Parent.Parent.UIManager)
    UIManager.showBuildPrompt(true)
end

--- 건설 배치 취소
function BuildController.cancelPlacement()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	if currentGhost then currentGhost:Destroy(); currentGhost = nil end
	
	InputManager.unbindKey(Enum.KeyCode.R)
	InputManager.unbindKey(Enum.KeyCode.X)
	InputManager.unbindKey(Enum.KeyCode.Escape)
	InputManager.unbindLeftClick("BuildPlace")
	InputManager.unbindRightClick("BuildCancel")

	-- Build 모드가 R 바인딩을 덮어쓰므로 종료 시 시설 상호작용 R 바인딩을 복구
	InputManager.bindKey(Enum.KeyCode.R, "InteractFacilityR", function()
		local InteractController = require(script.Parent.InteractController)
		if InteractController.onFacilityInteractPress then
			InteractController.onFacilityInteractPress()
		end
	end)
	
	isPlacing = false
	currentFacilityId = nil
	currentPlacementYawOffset = 0
	currentPlacementTiltOffset = Vector3.new(0, 0, 0)
	currentPlacementGroundPosition = nil
	currentGhostGroundOffset = 0
	currentIsPlaceable = false
	
    local UIManager = require(script.Parent.Parent.UIManager)
    UIManager.showBuildPrompt(false)
end

--- 건설 요청 (시설물 배치)
function BuildController.requestPlace(facilityId: string, position: Vector3, rotation: Vector3?): (boolean, any)
	print(string.format("[BuildController] Requesting build: %s", facilityId))
	
	local success, data = NetClient.Request("Build.Place.Request", {
		facilityId = facilityId,
		position = position,
		rotation = rotation or Vector3.new(0, 0, 0),
	})
	
	if success then
		print("[BuildController] Build success")
		BuildController.cancelPlacement()
	else
		warn("[BuildController] Build failed:", data)
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.notify("건설 실패: " .. tostring(data), Color3.fromRGB(255, 100, 100))
	end
	
	return success, data
end

--- 해체 요청 (시설물 제거)
function BuildController.requestRemove(structureId: string): (boolean, any)
	local success, data = NetClient.Request("Build.Remove.Request", {
		structureId = structureId,
	})
	return success, data
end

--- 전체 구조물 조회 요청
function BuildController.requestGetAll(): (boolean, any)
	local success, data = NetClient.Request("Build.GetAll.Request", {})
	
	if success and data and data.structures then
		structuresCache = {}
		structureCount = 0
		for _, struct in ipairs(data.structures) do
			structuresCache[struct.id] = struct
			structureCount = structureCount + 1
		end
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
end

local function onRemoved(data)
	if not data or not data.id then return end
	if structuresCache[data.id] then
		structuresCache[data.id] = nil
		structureCount = structureCount - 1
	end

	if focusedStructureId == data.id then
		hideWorldDurabilityBar()
	end
end

local function onChanged(data)
	if not data or not data.id then return end
	local structure = structuresCache[data.id]
	if not structure then return end
	
	if data.changes then
		for key, value in pairs(data.changes) do
			structure[key] = value
		end
	end

	if focusedStructureId == data.id then
		updateWorldDurabilityBar(data.id)
	end
end

--========================================
-- Initialization
--========================================

function BuildController.Init()
	if initialized then return end
	
	NetClient.On("Build.Placed", onPlaced)
	NetClient.On("Build.Removed", onRemoved)
	NetClient.On("Build.Changed", onChanged)

	lookConn = RunService.Heartbeat:Connect(function(dt)
		lookRayAccumulator = lookRayAccumulator + dt
		if lookRayAccumulator < 0.08 then
			return
		end
		lookRayAccumulator = 0

		local lookedId = getLookedStructureId()
		if lookedId then
			updateWorldDurabilityBar(lookedId)
		else
			hideWorldDurabilityBar()
		end
	end)
	
	initialized = true
	print("[BuildController] Initialized")
end

return BuildController
