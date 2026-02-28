-- BuildController.lua
-- 클라이언트 건설 컨트롤러
-- 서버 Build 이벤트 수신 및 로컬 캐시 관리 + 건축 배치(Ghost) 로직

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local NetClient = require(script.Parent.Parent.NetClient)
local InputManager = require(script.Parent.Parent.InputManager)
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
local heartbeatConn = nil

--========================================
-- Helpers
--========================================

local function createGhost(facilityId)
	local facilityData = DataHelper.GetData("FacilityData", facilityId)
	if not facilityData then return nil end

	-- ReplicatedStorage/Assets/FacilityModels 에서 모델 복사 시도
	local models = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FacilityModels")
	local sourceModel = models and models:FindFirstChild(facilityData.modelName)
	
	local ghost
	if sourceModel then
		ghost = sourceModel:Clone()
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
	
	-- 매 프레임 위치 업데이트
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not currentGhost then return end
		
		-- 마우스가 가리키는 지면 찾기
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {currentGhost, player.Character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local mousePos = UserInputService:GetMouseLocation()
		local ray = workspace.CurrentCamera:ViewportPointToRay(mousePos.X, mousePos.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 100, rayParams)
		
		local isPlaceable = false
		if result then
			local hitPos = result.Position
			local hitNormal = result.Normal
			
			local finalRotation = CFrame.Angles(0, math.rad(currentRotation), 0)
			
			-- 기본적으로 hitNormal 방향으로 UpVector 설정 (지형을 따라감)
			local lookAt = hitPos + finalRotation.LookVector
			currentGhost:SetPrimaryPartCFrame(CFrame.lookAt(hitPos, lookAt, hitNormal))
			
			-- 건설 가능 조건 체크
			local dist = (player.Character.PrimaryPart.Position - hitPos).Magnitude
			isPlaceable = (dist <= 25) -- 25 스터드 이내
			-- 추가 조건: 경사도 체크
			local slope = math.deg(math.acos(hitNormal.Dot(Vector3.new(0, 1, 0))))
			if slope > 45 then isPlaceable = false end -- 너무 가파르면 불가
		else
			isPlaceable = false
		end
		
		-- Ghost 색상 업데이트
		local color = isPlaceable and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
		for _, p in ipairs(currentGhost:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Color = color
				p.Transparency = 0.6
			end
		end
	end)
	
	-- 키 입력 바인딩 (R: 회전, X: 취소)
	InputManager.bindKey(Enum.KeyCode.R, "BuildRotate", function()
		currentRotation = (currentRotation + 45) % 360
	end)
	
	InputManager.bindKey(Enum.KeyCode.X, "BuildCancel", function()
		BuildController.cancelPlacement()
	end)
	
	-- 좌클릭: 배치 확정
	InputManager.onLeftClick("BuildPlace", function()
		if isPlacing and currentGhost then
			-- Ghost 색상이 빨간색이면(불가) 무시
			local isRed = false
			local pPart = currentGhost.PrimaryPart
			if pPart and pPart.Color.R > pPart.Color.G then isRed = true end
			
			if isRed then
				local UIManager = require(script.Parent.Parent.UIManager)
				UIManager.notify("이 위치에는 건설할 수 없습니다.", Color3.fromRGB(255, 100, 100))
				return
			end
			
			local pos = currentGhost.PrimaryPart.Position
			-- rotation은 currentRotation 기반 또는 Ghost의 실제 rotation 전달
			local rot = Vector3.new(0, currentRotation, 0)
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
	InputManager.unbindLeftClick("BuildPlace")
	
	isPlacing = false
	currentFacilityId = nil
	
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
end

--========================================
-- Initialization
--========================================

function BuildController.Init()
	if initialized then return end
	
	NetClient.On("Build.Placed", onPlaced)
	NetClient.On("Build.Removed", onRemoved)
	NetClient.On("Build.Changed", onChanged)
	
	initialized = true
	print("[BuildController] Initialized")
end

return BuildController
