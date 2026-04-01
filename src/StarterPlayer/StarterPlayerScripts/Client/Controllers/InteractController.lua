-- InteractController.lua
-- 상호작용 컨트롤러 (채집, NPC 대화, 구조물 상호작용)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared.Config.AnimationIds)
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)
local UILocalizer = require(Client.Localization.UILocalizer)
local BuildController = require(Client.Controllers.BuildController)
local RadioStoryController = require(Client.Controllers.RadioStoryController)
local WindowManager = require(Client.Utils.WindowManager)
local HarvestUI = require(Client.UI.HarvestUI)
local UIManager = nil -- Circular dependency check (will require inside if needed)

local InteractController = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 상호작용 가능 대상
local currentTarget = nil
local currentTargetType = nil  -- "resource", "npc", "facility", "drop"
local currentFacilityTarget = nil  -- 가장 가까운 시설 (별도 추적, 채집노드와 겹쳐도 R키 사용 가능)

-- 상호작용 거리 (Balance에서 가져옴, 여유분 추가)
local INTERACT_DISTANCE = (Balance.HARVEST_RANGE or 10) + (Balance.INTERACT_OFFSET or 4)
local FACILITY_INTERACT_BONUS = 6
local sleepTransitionBusy = false
local sleepConfirmGui = nil
local sleepConfirmActive = false
local RADIO_MODEL_NAME = "Motorola DP4800"
local RADIO_INTERACT_DISTANCE = 14
local REMOVE_CONFIRM_WINDOW = 2.5
local pendingRemoveStructureId = nil
local pendingRemoveExpireAt = 0
local playSleepTransitionAndRequest

-- UIManager 참조 (Init 후 설정)
local UIManager = nil

local function getStructureIdFromTarget(target: Instance): string?
	if not target then
		return nil
	end
	local structureId = target:GetAttribute("StructureId") or target:GetAttribute("id") or target.Name
	if not structureId or structureId == "" then
		return nil
	end
	return tostring(structureId)
end

local function clearPendingRemove()
	pendingRemoveStructureId = nil
	pendingRemoveExpireAt = 0
end

local function closeSleepConfirm()
	if sleepConfirmGui then
		sleepConfirmGui:Destroy()
		sleepConfirmGui = nil
	end
	sleepConfirmActive = false
end

local function showSleepConfirm(structureId: string)
	if sleepConfirmActive or sleepTransitionBusy then return end
	sleepConfirmActive = true

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then sleepConfirmActive = false return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SleepConfirmGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9998
	gui.Parent = playerGui
	sleepConfirmGui = gui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0.5
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local box = Instance.new("Frame")
	box.Size = UDim2.new(0, 320, 0, 160)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	box.BorderSizePixel = 0
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(180, 160, 100)
	stroke.Parent = box

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 50)
	title.Position = UDim2.new(0, 0, 0, 15)
	title.BackgroundTransparency = 1
	title.Text = "간이천막에서 취침하시겠습니까?"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.Parent = box

	local subtext = Instance.new("TextLabel")
	subtext.Size = UDim2.new(1, 0, 0, 24)
	subtext.Position = UDim2.new(0, 0, 0, 58)
	subtext.BackgroundTransparency = 1
	subtext.Text = "체력/스태미나 회복, 시간 경과 (정오)"
	subtext.TextColor3 = Color3.fromRGB(180, 180, 160)
	subtext.TextSize = 13
	subtext.Font = Enum.Font.Gotham
	subtext.Parent = box

	local yesBtn = Instance.new("TextButton")
	yesBtn.Size = UDim2.new(0, 120, 0, 40)
	yesBtn.Position = UDim2.new(0.5, -130, 1, -55)
	yesBtn.BackgroundColor3 = Color3.fromRGB(80, 170, 80)
	yesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	yesBtn.Text = "예"
	yesBtn.TextSize = 18
	yesBtn.Font = Enum.Font.GothamBold
	yesBtn.Parent = box
	Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 8)

	local noBtn = Instance.new("TextButton")
	noBtn.Size = UDim2.new(0, 120, 0, 40)
	noBtn.Position = UDim2.new(0.5, 10, 1, -55)
	noBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
	noBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	noBtn.Text = "아니오"
	noBtn.TextSize = 18
	noBtn.Font = Enum.Font.GothamBold
	noBtn.Parent = box
	Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, 8)

	yesBtn.MouseButton1Click:Connect(function()
		closeSleepConfirm()
		playSleepTransitionAndRequest(structureId)
	end)

	noBtn.MouseButton1Click:Connect(function()
		closeSleepConfirm()
	end)

	-- 배경 클릭으로도 닫기
	bg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			closeSleepConfirm()
		end
	end)
end

playSleepTransitionAndRequest = function(structureId: string)
	if sleepTransitionBusy then
		return
	end
	sleepTransitionBusy = true

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		sleepTransitionBusy = false
		return
	end

	local fadeGui = playerGui:FindFirstChild("SleepFadeGui")
	if not fadeGui then
		fadeGui = Instance.new("ScreenGui")
		fadeGui.Name = "SleepFadeGui"
		fadeGui.ResetOnSpawn = false
		fadeGui.IgnoreGuiInset = true
		fadeGui.DisplayOrder = 9999
		fadeGui.Parent = playerGui
	end

	local black = fadeGui:FindFirstChild("Black")
	if not black then
		black = Instance.new("Frame")
		black.Name = "Black"
		black.Size = UDim2.fromScale(1, 1)
		black.Position = UDim2.fromScale(0, 0)
		black.BackgroundColor3 = Color3.new(0, 0, 0)
		black.BorderSizePixel = 0
		black.Parent = fadeGui
	end

	black.Visible = true
	black.BackgroundTransparency = 1

	local fadeOut = TweenService:Create(
		black,
		TweenInfo.new(Balance.SLEEP_FADE_OUT_TIME or 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	fadeOut:Play()
	fadeOut.Completed:Wait()

	task.wait(0.05)
	local ok, data = NetClient.Request("Facility.Sleep.Request", { structureId = structureId })

	task.wait(Balance.SLEEP_BLACK_HOLD_TIME or 0.5)

	local fadeIn = TweenService:Create(
		black,
		TweenInfo.new(Balance.SLEEP_FADE_IN_TIME or 1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	fadeIn:Play()
	fadeIn.Completed:Wait()
	black.Visible = false

	if ok then
		if UIManager then
			UIManager.notify("간이천막에서 휴식했습니다. 상쾌한 아침입니다.")
		end
	else
		if UIManager then
			if data == "SLEEP_COOLDOWN" then
				UIManager.notify("방금 잠에서 깼습니다. 잠시 후 다시 휴식할 수 있습니다.", Color3.fromRGB(255, 180, 120))
			else
				UIManager.notify("휴식을 취할 수 없습니다.", Color3.fromRGB(255, 120, 120))
			end
		end
	end

	sleepTransitionBusy = false
end

--========================================
-- Interactable Detection
--========================================

--- 파트의 표면까지 최단 거리 계산 (중심점이 아닌 실제 표면)
local function getDistToSurface(part: BasePart, playerPos: Vector3): number
	local cf = part.CFrame
	local size = part.Size
	-- 월드 좌표를 로컬로 변환하여 가장 가까운 점 계산
	local offset = cf:PointToObjectSpace(playerPos)
	local halfSize = size / 2
	local clamped = Vector3.new(
		math.clamp(offset.X, -halfSize.X, halfSize.X),
		math.clamp(offset.Y, -halfSize.Y, halfSize.Y),
		math.clamp(offset.Z, -halfSize.Z, halfSize.Z)
	)
	local closestWorld = cf:PointToWorldSpace(clamped)
	return (closestWorld - playerPos).Magnitude
end

--- 모델에서 가장 가까운 파트까지의 거리 계산
local function getDistToModel(model: Instance, playerPos: Vector3): number
	local minDist = math.huge
	-- Hitbox/InteractPart 우선
	local hitbox = model:FindFirstChild("Hitbox") or model:FindFirstChild("InteractPart")
	if hitbox and hitbox:IsA("BasePart") then
		return getDistToSurface(hitbox, playerPos)
	end
	-- PrimaryPart
	if model:IsA("Model") and model.PrimaryPart then
		return getDistToSurface(model.PrimaryPart, playerPos)
	end
	-- 가장 가까운 BasePart
	for _, child in pairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local d = getDistToSurface(child, playerPos)
			if d < minDist then minDist = d end
		end
	end
	return minDist
end

--- 플레이어 근처의 상호작용 가능 대상 찾기 (GetPartBoundsInRadius 최적화)
local function findNearbyInteractable(): (Instance?, string?)
	local character = player.Character
	if not character then return nil, nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end
	
	local playerPos = hrp.Position
	
	-- 공간 쿼리 파라미터 설정
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	
	local targetFolderNames = {"ResourceNodes", "NPCs", "Facilities"}
	local folderObjects = {}
	local includeList = {}
	for _, name in ipairs(targetFolderNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then 
			folderObjects[name] = folder
			table.insert(includeList, folder) 
		end
	end
	
	if #includeList == 0 then return nil, nil end
	overlapParams.FilterDescendantsInstances = includeList
	
	-- 반경 내 파트 검색
	local nearbyParts = workspace:GetPartBoundsInRadius(playerPos, INTERACT_DISTANCE, overlapParams)
	
	local closestTarget = nil
	local closestType = nil
	local closestDist = INTERACT_DISTANCE + 1

	local closestFacility = nil
	local closestFacilityDist = INTERACT_DISTANCE + FACILITY_INTERACT_BONUS + 1
	
	local typeMap = {
		ResourceNodes = "resource",
		NPCs = "npc",
		Facilities = "facility"
	}
	
	for _, part in ipairs(nearbyParts) do
		-- [UX 개선] IsDescendantOf 및 Marker 기반 탐색으로 중첩 폴더 대응
		local entity = nil
		local currentType = nil
		
		for folderName, folder in pairs(folderObjects) do
			if part:IsDescendantOf(folder) then
				currentType = typeMap[folderName]
				
				-- 상호작용 가능한 루트 탐색 (ID 속성 우선)
				local check = part
				while check and check ~= folder do
					if check:GetAttribute("NodeId") or 
					   check:GetAttribute("FacilityId") or 
					   check:GetAttribute("NPCId") or
					   game:GetService("CollectionService"):HasTag(check, "ResourceNode") then
						entity = check
						break
					end
					
					-- 폴더의 직계 자식이면 엔티티로 후보 등록
					if check.Parent == folder then
						entity = entity or check
						break
					end
					check = check.Parent
				end
				break
			end
		end
		
		if not entity or not currentType then continue end
		
		-- 고갈된 노드 스킵
		if currentType == "resource" and entity:GetAttribute("Depleted") then
			continue
		end
		
		local allowedDistance = INTERACT_DISTANCE
		if currentType == "facility" then
			local facilityId = entity:GetAttribute("FacilityId")
			local facilityData = facilityId and DataHelper.GetData("FacilityData", tostring(facilityId)) or nil
			local serverRange = (facilityData and facilityData.interactRange) or INTERACT_DISTANCE
			-- 서버의 getInfo 거리 검증 기준과 클라 탐지 기준을 맞춰 접근 실패를 줄인다.
			allowedDistance = math.max(4, serverRange + 1)
		elseif currentType == "npc" then
			allowedDistance = math.max(INTERACT_DISTANCE, (Balance.SHOP_INTERACT_RANGE or 10) + 2)
		end

		local dist = getDistToModel(entity, playerPos)
		if currentType == "facility" then
			if entity:IsA("Model") then
				dist = (entity:GetPivot().Position - playerPos).Magnitude
			elseif entity:IsA("BasePart") then
				dist = (entity.Position - playerPos).Magnitude
			end
			-- 시설은 별도 추적 (채집노드가 가까워도 R키로 상호작용 가능)
			if dist <= allowedDistance and dist < closestFacilityDist then
				closestFacilityDist = dist
				closestFacility = entity
			end
		end
		if dist <= allowedDistance and dist < closestDist then
			closestDist = dist
			closestTarget = entity
			closestType = currentType
		end
	end

	-- 스토리 무전기 탐색 (워크스페이스 어디에 있든 상호작용 가능)
	if not RadioStoryController.isCompleted() then
		local radioModel = workspace:FindFirstChild(RADIO_MODEL_NAME, true)
		if radioModel then
			local radioDist = getDistToModel(radioModel, playerPos)
			if radioDist <= math.max(INTERACT_DISTANCE, RADIO_INTERACT_DISTANCE) and radioDist < closestDist then
				closestDist = radioDist
				closestTarget = radioModel
				closestType = "radio"
			end
		end
	end
	
	return closestTarget, closestType, closestFacility
end

--========================================
-- Interaction Handlers
--========================================


-- pickupDrop function removed (moved to WorldDropController's ProximityPrompt)

--- NPC 대화/상점
local function interactNPC(target: Instance)
	local npcId = target:GetAttribute("NPCId") or target.Name
	local npcType = target:GetAttribute("NPCType") or "shop"
	
	print("[InteractController] Interacting with NPC:", npcId)
	
	if npcType == "shop" then
		-- 상점 열기
		if UIManager then
			UIManager.openShop(npcId)
		end
	else
		-- 대화 등 다른 상호작용
		print("[InteractController] NPC dialogue not implemented")
	end
end

--- 시설 상호작용
local function interactFacility(target: Instance)
	local facilityId = target:GetAttribute("FacilityId")
	local structureId = target:GetAttribute("StructureId") or target:GetAttribute("id") or target.Name
	
	print("[InteractController] Interacting with facility:", facilityId, "(ID:", structureId .. ")")
	
	if not facilityId then return end
	
	local facilityData = DataHelper.GetData("FacilityData", facilityId)
	if not facilityData then return end
	
	if facilityData.functionType == "CRAFTING_T1" then
		-- 기초작업대는 이제 전용 제작 UI(FacilityUI)를 엽니다.
		local FacilityController = require(Client.Controllers.FacilityController)
		FacilityController.openFacility(structureId)
	elseif facilityData.functionType == "CRAFTING" or facilityData.functionType == "CRAFTING_T2" or facilityData.functionType == "CRAFTING_T3" then
		-- 일반 제작대는 인벤토리 제작 탭 안내
		if UIManager then
			UIManager.notify("도구 및 장비 제작은 인벤토리[I]의 제작 탭에서 가능합니다.", Color3.fromRGB(255, 210, 80))
		end
	elseif facilityData.functionType == "COOKING" or facilityData.functionType:find("SMELTING") then
		-- 요리, 제련용 시설 UI 열기
		local FacilityController = require(Client.Controllers.FacilityController)
		FacilityController.openFacility(structureId)
	elseif facilityData.functionType == "STORAGE" then
		-- 보관함 UI 열기
		local StorageController = require(Client.Controllers.StorageController)
		StorageController.openStorage(structureId)
	elseif facilityData.functionType == "BASE_CORE" then
		local TotemController = require(Client.Controllers.TotemController)
		TotemController.openTotem(structureId)
	elseif facilityData.functionType == "RESPAWN" then
		showSleepConfirm(structureId)
	end
end

local function removeFacility(target: Instance)
	local structureId = getStructureIdFromTarget(target)
	if not structureId then
		clearPendingRemove()
		return
	end

	local now = tick()
	local isConfirmed = (pendingRemoveStructureId == structureId) and (now <= pendingRemoveExpireAt)
	if not isConfirmed then
		pendingRemoveStructureId = structureId
		pendingRemoveExpireAt = now + REMOVE_CONFIRM_WINDOW
		if UIManager then
			UIManager.notify("해체 확인: 2.5초 내 [T]를 다시 누르세요.", Color3.fromRGB(255, 210, 120))
		end
		return
	end

	clearPendingRemove()

	local ok, data = BuildController.requestRemove(structureId)
	if ok then
		if UIManager then
			UIManager.notify("시설을 해체했습니다.", Color3.fromRGB(140, 230, 140))
		end
	else
		if UIManager then
			local code = tostring(data)
			if code == "NO_PERMISSION" then
				UIManager.notify("토템 보호가 활성화되어 해체할 수 없습니다. 유지비 만료 후 약탈 가능합니다.", Color3.fromRGB(255, 120, 120))
			else
				UIManager.notify("해체 실패: " .. code, Color3.fromRGB(255, 120, 120))
			end
		end
	end
end



--========================================
-- Public API
--========================================

--- Z키 눌림 처리 (NPC/일반 상호작용)
function InteractController.onInteractPress()
	if InputManager.isUIOpen() then
		return
	end
	
	if currentTarget and currentTargetType then
		if currentTargetType == "resource" then
			-- R키로 채집 UI를 여세요
		elseif currentTargetType == "npc" then
			interactNPC(currentTarget)
		end
	end
end

--- R키 눌림 처리 (건물/시설 상호작용 전용)
function InteractController.onFacilityInteractPress()
	if InputManager.isUIOpen() then
		-- 시설 상호작용 키(R)로 UI 닫기까지 일관 처리
		if HarvestUI.IsOpen() then
			HarvestUI.Close()
			return
		end
		if WindowManager then
			WindowManager.closeAll()
		end
		return
	end

	if RadioStoryController.shouldConsumeInteractKey and RadioStoryController.shouldConsumeInteractKey() then
		RadioStoryController.interact()
		return
	end

	if currentTarget and currentTargetType == "radio" then
		RadioStoryController.interact()
		return
	end

	-- 자원 노드: R키로 채집 UI 열기
	if currentTarget and currentTargetType == "resource" then
		local nodeUID = currentTarget:GetAttribute("NodeUID")
		local nodeId = currentTarget:GetAttribute("NodeId")
		if nodeUID and nodeId then
			HarvestUI.Open(nodeUID, nodeId, currentTarget)
			return
		else
			warn("[InteractController] Resource node missing attributes - NodeUID:", nodeUID, "NodeId:", nodeId, "Model:", currentTarget:GetFullName())
		end
	end

	-- 시설은 별도 추적된 대상 우선 사용 (채집노드가 가까워도 R키 작동)
	local facTarget = currentFacilityTarget or (currentTargetType == "facility" and currentTarget)
	if facTarget then
		interactFacility(facTarget)
	end
end

function InteractController.onFacilityRemovePress()
	if InputManager.isUIOpen() then
		return
	end

	local facTarget = currentFacilityTarget or (currentTargetType == "facility" and currentTarget)
	if facTarget then
		removeFacility(facTarget)
	else
		clearPendingRemove()
	end
end

--- 주변 대상 감지 업데이트 (10Hz)
local function onUpdate()
	-- UI가 열려있거나 제작 중이면 상호작용 레이블 숨김
	if InputManager.isUIOpen() or (UIManager and UIManager.isCrafting and UIManager.isCrafting()) then
		if currentTarget then
			currentTarget = nil
			currentTargetType = nil
			if UIManager then UIManager.hideInteractPrompt() end
		end
		return
	end

	local target, targetType, nearbyFacility = findNearbyInteractable()
	currentFacilityTarget = nearbyFacility
	
	if target ~= currentTarget or targetType == "facility" or targetType == "radio" then
		if target ~= currentTarget or targetType ~= currentTargetType then
			clearPendingRemove()
		end
		currentTarget = target
		currentTargetType = targetType
		
		if UIManager then
			RadioStoryController.ensureRinging()
			if target then
				local promptText = ""
				local targetName = nil
				local fId = target:GetAttribute("FacilityId") or target:GetAttribute("id")
				local structureId = target:GetAttribute("StructureId") or target:GetAttribute("id") or target.Name
				if fId then
					local fid = tostring(fId):upper()
					local data = DataHelper.GetData("FacilityData", fid)
					targetName = UILocalizer.LocalizeDataText("FacilityData", fid, "name", data and data.name or fid)
				end
				
				if not targetName then
					local nId = target:GetAttribute("NodeId")
					if nId then
						local nid = tostring(nId):upper()
						local data = DataHelper.GetData("ResourceNodeData", nid)
						targetName = UILocalizer.LocalizeDataText("ResourceNodeData", nid, "name", data and data.name or nid)
					end
				end

				targetName = targetName or target:GetAttribute("DisplayName")

				if targetType == "radio" then
					targetName = UILocalizer.Localize("비상 무전기")
				end
				
				if targetType == "resource" then
					-- R키로 채집 UI 열기
					promptText = UILocalizer.Localize("[R] 채집")
				elseif targetType == "npc" then
					promptText = UILocalizer.Localize("[Z] 대화")
				elseif targetType == "facility" then
					promptText = UILocalizer.Localize("[R] 사용") .. "  " .. UILocalizer.Localize("[T] 해체")
				elseif targetType == "radio" then
					promptText = UILocalizer.Localize("[R] 무전 수신")
				else
					promptText = UILocalizer.Localize("[Z] 상호작용")
				end
				
				if promptText ~= "" then
					UIManager.showInteractPrompt(promptText, targetName)
				else
					UIManager.hideInteractPrompt()
				end
			else
				UIManager.hideInteractPrompt()
			end
		end
	end
end

--========================================
-- Initialization
--========================================

function InteractController.Init()
	if initialized then
		warn("[InteractController] Already initialized!")
		return
	end
	
	-- UIManager 로드 (지연)
	task.spawn(function()
		UIManager = require(Client.UIManager)
	end)

	RadioStoryController.Init()
	
	-- 주기적으로 대상 감지 업데이트 (0.1초 - 10Hz)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local success, err = pcall(onUpdate)
			if not success then
				-- warn("[InteractController] Update error:", err)
			end
		end
	end)
	
	initialized = true
	print("[InteractController] Initialized (Z = Interact, R = Facility)")
end

return InteractController
