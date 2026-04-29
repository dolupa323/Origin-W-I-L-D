-- InteractController.lua
-- 상호작용 컨트롤러 (채집, NPC 대화, 구조물 상호작용)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared.Config.AnimationIds)
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)
local UILocalizer = require(Client.Localization.UILocalizer)
local BuildController = require(Client.Controllers.BuildController)
local WindowManager = require(Client.Utils.WindowManager)
local HarvestUI = require(Client.UI.HarvestUI)
local UIManager = nil -- Circular dependency check (will require inside if needed)
local FacilityRadialUI = require(Client.UI.FacilityRadialUI)
local NPCRadialUI = require(Client.UI.NPCRadialUI)

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
local pendingRemoveStructureId = nil
local pendingRemoveExpireAt = 0
local playSleepTransitionAndRequest
local mountedJumpBound = false
local MOUNT_JUMP_ACTION = "MountedDinoJumpBlock"
local MOUNT_MOVE_ACTION = "MountedDinoMoveSink"
local mountedControlState = { forward = false, backward = false, left = false, right = false }
local lastMountControlThrottle = 0
local lastMountControlSteer = 0
local NPC_TARGET_PRIORITY_BONUS = 3.5
local isResting = false
local restAnimTrack = nil
local restMovementConn = nil

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

function InteractController.showSleepConfirm(structureId: string)
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
	title.Text = "침대에서 취침하시겠습니까?"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.Parent = box

	local subtext = Instance.new("TextLabel")
	subtext.Size = UDim2.new(1, 0, 0, 24)
	subtext.Position = UDim2.new(0, 0, 0, 58)
	subtext.BackgroundTransparency = 1
	subtext.Text = "체력 회복 및 부활 지점 설정"
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
		
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = fadeGui
	end

	local black = fadeGui:FindFirstChild("Black") or fadeGui:FindFirstChild("Frame")
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
			UIManager.notify("침대에서 휴식했습니다.")
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
	if model:IsA("BasePart") then
		return getDistToSurface(model, playerPos)
	end
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
	
	local targetFolderNames = {"ResourceNodes", "NPCs", "Facilities", "Creatures"}
	local folderObjects = {}
	local includeList = {}
	for _, name in ipairs(targetFolderNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then 
			folderObjects[name] = folder
			table.insert(includeList, folder) 
		end
	end

	-- [특수 처리] Con_Doctor는 폴더 외부에 있어도 상호작용 가능하도록 추가
	local doctor = workspace:FindFirstChild("Con_Doctor")
	if doctor then
		table.insert(includeList, doctor)
		if not folderObjects["NPCs"] then
			folderObjects["NPCs"] = doctor
		end
	end
	
	if #includeList == 0 then 
		return nil, nil 
	end
	overlapParams.FilterDescendantsInstances = includeList
	
	-- 반경 내 파트 검색
	local searchRadius = math.max(INTERACT_DISTANCE, (Balance.SHOP_INTERACT_RANGE or 10) + 4)
	local nearbyParts = workspace:GetPartBoundsInRadius(playerPos, searchRadius, overlapParams)
	
	local closestTarget = nil
	local closestType = nil
	local closestDist = searchRadius + 1
	local closestScore = math.huge

	local closestFacility = nil
	local closestFacilityDist = searchRadius + FACILITY_INTERACT_BONUS + 1
	
	local typeMap = {
		ResourceNodes = "resource",
		NPCs = "npc",
		Facilities = "facility",
		Creatures = "pal",
	}
	
	for _, part in ipairs(nearbyParts) do
		local entity = nil
		local currentType = nil
		
		-- 1. 특수 대상(Con_Doctor) 우선 체크
		local isDoctor = (doctor and (part == doctor or part:IsDescendantOf(doctor)))
		if isDoctor then
			currentType = "npc"
			-- 상호작용 가능한 루트(Con_Doctor 모델) 탐색
			local check = part
			while check do
				if check == doctor then
					entity = check
					break
				end
				if check == workspace then break end
				check = check.Parent
			end
		end

		-- 2. 일반 폴더 기반 체크 (아직 대상을 못 찾은 경우)
		if not entity then
			for folderName, folder in pairs(folderObjects) do
				if part:IsDescendantOf(folder) then
					currentType = typeMap[folderName]
					
					local check = part
					while check do
						if check:GetAttribute("NodeId") or 
						   check:GetAttribute("FacilityId") or 
						   check:GetAttribute("NPCId") or
						   check:GetAttribute("IsPal") or
						   check:GetAttribute("ResourceNode") or
						   game:GetService("CollectionService"):HasTag(check, "ResourceNode") then
							entity = check
							break
						end
						
						if check.Parent == folder then
							entity = entity or check
							break
						end
						
						if check == folder or check == workspace then break end
						check = check.Parent
					end
					break
				end
			end
		end
		
		if not entity or not currentType then continue end

		-- 팰인 경우 내 팰인지 체크 (RootPart 또는 Model에 걸린 IsPal 속성)
		if currentType == "pal" then
			local ownerId = entity:GetAttribute("OwnerUserId")
			if not ownerId or ownerId ~= player.UserId then
				continue -- 내 팰이 아니면 상호작용 후보에서 제외
			end
			-- 모델 자체로 entity 변경 (IsPal이 rootPart에 있을시)
			if entity:IsA("BasePart") and entity.Parent:IsA("Model") then
				entity = entity.Parent
			end
		end
		
		-- 고갈된 노드 스킵
		if currentType == "resource" and entity:GetAttribute("Depleted") then
			continue
		end
		
		local allowedDistance = INTERACT_DISTANCE
		if currentType == "pal" then
			allowedDistance = (Balance.HARVEST_RANGE or 10) + 4
		elseif currentType == "facility" then
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
		-- ★ 시체(CORPSE_)는 일반 채집노드보다 항상 우선
		local nodeId = entity:GetAttribute("NodeId")
		local isCorpse = nodeId and string.sub(tostring(nodeId), 1, 7) == "CORPSE_"
		local closestIsCorpse = closestTarget and closestTarget:GetAttribute("NodeId")
			and string.sub(tostring(closestTarget:GetAttribute("NodeId")), 1, 7) == "CORPSE_"
		local score = dist
		if currentType == "npc" then
			score -= NPC_TARGET_PRIORITY_BONUS
		end
		
		if dist <= allowedDistance then
			-- 시체가 일반 노드를 밀어냄 / 같은 종류면 거리 비교
			if (isCorpse and not closestIsCorpse) or (score < closestScore and (isCorpse == closestIsCorpse or not closestIsCorpse)) then
				closestDist = dist
				closestScore = score
				closestTarget = entity
				closestType = currentType
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
	
	if npcId == "Con_Doctor" or target.Name == "Con_Doctor" then
		if NPCRadialUI.IsOpen() then
			NPCRadialUI.Close()
		else
			NPCRadialUI.Open(target)
		end
		return
	end

	if npcType == "shop" then
		-- 상점 열기
		if UIManager then
			UIManager.openShop(npcId)
		end
	else
		-- 대화 등 다른 상호작용
		print("[InteractController] NPC interaction for", npcId, "falling back to radial menu")
		if NPCRadialUI.IsOpen() then
			NPCRadialUI.Close()
		else
			NPCRadialUI.Open(target)
		end
	end
end

--- 시설 상호작용
local function interactFacility(target: Instance)
	if not FacilityRadialUI then
		FacilityRadialUI = require(Client.UI.FacilityRadialUI)
	end
	
	if FacilityRadialUI.IsOpen() then
		FacilityRadialUI.Close()
	else
		FacilityRadialUI.Open(target)
	end
end

function InteractController.startRest()
	if isResting then return end
	
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	
	isResting = true
	NetClient.Request("Facility.Rest.Start", {})
	
	-- 애니메이션 재생
	local animId = AnimationIds.MISC.REST
	if animId then
		-- Assets에서 애니메이션 로드
		local asset = ReplicatedStorage.Assets.Animations:FindFirstChild(animId)
		if asset then
			restAnimTrack = humanoid:LoadAnimation(asset)
			restAnimTrack.Priority = Enum.AnimationPriority.Action
			restAnimTrack.Looped = false
			restAnimTrack:Play()
			
			-- 마지막 프레임에서 멈추기 (애니메이션 길이만큼 대기 후 속도 0)
			task.spawn(function()
				task.wait(restAnimTrack.Length * 0.95)
				if isResting and restAnimTrack then
					restAnimTrack:AdjustSpeed(0)
				end
			end)
		end
	end
	
	if UIManager then
		UIManager.notify("휴식 중... 이동하면 취소됩니다.", Color3.fromRGB(150, 255, 150))
	end
	
	-- 움직임 감지하여 자동 취소
	restMovementConn = RunService.Heartbeat:Connect(function()
		local moveDir = humanoid.MoveDirection
		if moveDir.Magnitude > 0.1 or humanoid.Jump then
			InteractController.stopRest()
		end
	end)
end

function InteractController.stopRest()
	if not isResting then return end
	isResting = false
	
	if restMovementConn then
		restMovementConn:Disconnect()
		restMovementConn = nil
	end
	
	if restAnimTrack then
		restAnimTrack:Stop(0.3)
		restAnimTrack = nil
	end
	
	NetClient.Request("Facility.Rest.Stop", {})
	
	if UIManager then
		UIManager.notify("휴식을 마쳤습니다.")
	end
end

local function removeFacility(target: Instance, skipConfirm: boolean)
	local structureId = getStructureIdFromTarget(target)
	if not structureId then
		clearPendingRemove()
		return
	end

	local now = tick()
	local isConfirmed = skipConfirm or ((pendingRemoveStructureId == structureId) and (now <= pendingRemoveExpireAt))
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
				UIManager.notify("해체할 수 없습니다. 다시 시도해주세요.", Color3.fromRGB(255, 120, 120))
				warn("[InteractController] Remove failed:", code)
			end
		end
	end
end



--========================================
-- Public API
--========================================

--- Z키 눌림 처리 (NPC/일반 상호작용)
function InteractController.onInteractPress()
	InteractController.onFacilityInteractPress()
end

--- R키 눌림 처리 (건물/시설 상호작용 전용)
function InteractController.onFacilityInteractPress()
	if InputManager.isUIOpen() then
		-- 시설 상호작용 키(R)로 UI 닫기까지 일관 처리
		if HarvestUI.IsOpen() then
			HarvestUI.Close()
			return
		end
		if FacilityRadialUI.IsOpen() then
			FacilityRadialUI.Close()
			return
		end
		local PalRadialUI = require(Client.UI.PalRadialUI)
		if PalRadialUI.IsOpen() then
			PalRadialUI.Close()
			return
		end
		local PortalRUI = require(Client.UI.PortalRadialUI)
		if PortalRUI.IsOpen() then
			PortalRUI.Close()
			return
		end
		if NPCRadialUI.IsOpen() then
			NPCRadialUI.Close()
			return
		end
		-- 윈도우 UI (인벤토리 등) 닫기 시도
		local ok_WM, WindowManagerMod = pcall(require, Client.Utils.WindowManager)
		if ok_WM and WindowManagerMod and WindowManagerMod.closeAll then
			WindowManagerMod.closeAll()
		end
		return
	end

	local mountedPalUID = player:GetAttribute("MountedPalUID")
	if mountedPalUID then
		local ok, err = NetClient.Request("Party.Dismount.Request", {})
		if not ok and UIManager then
			UIManager.notify("지금은 내릴 수 없습니다.", Color3.fromRGB(255, 120, 120))
		end
		return
	end

	if currentTarget and currentTargetType == "npc" then
		interactNPC(currentTarget)
		return
	end

	-- R키 대상: Facility 및 Pal (Pal은 우선순위를 위해 별도 조건 처리)
	if currentTarget and currentTargetType == "pal" then
		-- Pal UI 띄우기 처리 (Radial UI)
		local PalRadialUI = require(Client.UI.PalRadialUI)
		if PalRadialUI.IsOpen() then
			PalRadialUI.Close()
		else
			PalRadialUI.Open(currentTarget)
		end
		return
	end

	-- 자원 노드: R키로 채집 UI 열기
	if currentTarget and currentTargetType == "resource" then
		local nodeUID = currentTarget:GetAttribute("NodeUID")
		local nodeId = currentTarget:GetAttribute("NodeId")
		if nodeUID and nodeId then
			if UIManager then UIManager.hideInteractPrompt() end
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

function InteractController.onFacilityRemovePress(skipConfirm: boolean)
	skipConfirm = skipConfirm or false
	
	if not skipConfirm and InputManager.isUIOpen() then
		return
	end

	local facTarget = currentFacilityTarget or (currentTargetType == "facility" and currentTarget)
	if facTarget then
		removeFacility(facTarget, skipConfirm)
	else
		clearPendingRemove()
	end
end

local function getMountControlValues()
	local throttle = 0
	if mountedControlState.forward then
		throttle += 1
	end
	if mountedControlState.backward then
		throttle -= 1
	end

	local steer = 0
	if mountedControlState.left then
		steer -= 1
	end
	if mountedControlState.right then
		steer += 1
	end

	return throttle, steer
end

local function sendMountedControl(force)
	local mountedPalUID = player:GetAttribute("MountedPalUID")
	local throttle, steer = getMountControlValues()
	if not mountedPalUID then
		throttle = 0
		steer = 0
	end

	lastMountControlThrottle = throttle
	lastMountControlSteer = steer

	local camera = workspace.CurrentCamera
	local lookDir = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)

	NetClient.Request("Party.Mount.Control.Request", {
		throttle = throttle,
		steer = steer,
		lookDir = lookDir,
	})
end

local function isMountedMovementKey(input: InputObject): boolean
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return false
	end

	local keyCode = input.KeyCode
	return keyCode == Enum.KeyCode.W
		or keyCode == Enum.KeyCode.A
		or keyCode == Enum.KeyCode.S
		or keyCode == Enum.KeyCode.D
		or keyCode == Enum.KeyCode.Up
		or keyCode == Enum.KeyCode.Down
		or keyCode == Enum.KeyCode.Left
		or keyCode == Enum.KeyCode.Right
end

local function updateMountedControlKey(input: InputObject, isPressed: boolean)
	local keyCode = input.KeyCode
	local handled = true
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		mountedControlState.forward = isPressed
	elseif keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		mountedControlState.backward = isPressed
	elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		mountedControlState.left = isPressed
	elseif keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		mountedControlState.right = isPressed
	else
		handled = false
	end

	if handled and player:GetAttribute("MountedPalUID") then
		sendMountedControl(false)
	end
end

local function syncMountedJumpBinding()
	local isMounted = player:GetAttribute("MountedPalUID") ~= nil

	if isMounted and not mountedJumpBound then
		ContextActionService:BindActionAtPriority(MOUNT_JUMP_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.PlayerActions.CharacterJump)
		mountedJumpBound = true
	elseif not isMounted and mountedJumpBound then
		ContextActionService:UnbindAction(MOUNT_JUMP_ACTION)
		mountedJumpBound = false
	end

	if isMounted then
		ContextActionService:BindActionAtPriority(MOUNT_MOVE_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight)
	else
		ContextActionService:UnbindAction(MOUNT_MOVE_ACTION)
	end

	if not isMounted then
		mountedControlState.forward = false
		mountedControlState.backward = false
		mountedControlState.left = false
		mountedControlState.right = false
		sendMountedControl(true)
	end
end

--- 주변 대상 감지 업데이트 (10Hz)
local function onUpdate()
	syncMountedJumpBinding()

	if player:GetAttribute("MountedPalUID") then
		currentTarget = nil
		currentTargetType = nil
		currentFacilityTarget = nil
		if UIManager then
			UIManager.hideInteractPrompt()
		end
		return
	end

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
	
	if target ~= currentTarget or targetType ~= currentTargetType then
		clearPendingRemove()
		currentTarget = target
		currentTargetType = targetType
	end

	if UIManager then
		if currentTarget then
			local promptText = ""
			local targetName = nil
			local fId = currentTarget:GetAttribute("FacilityId") or currentTarget:GetAttribute("id")
			if fId then
				local fid = tostring(fId):upper()
				local data = DataHelper.GetData("FacilityData", fid)
				targetName = UILocalizer.LocalizeDataText("FacilityData", fid, "name", data and data.name or fid)
			end
			
			if not targetName then
				local nId = currentTarget:GetAttribute("NodeId")
				if nId then
					local nid = tostring(nId):upper()
					local data = DataHelper.GetData("ResourceNodeData", nid)
					targetName = UILocalizer.LocalizeDataText("ResourceNodeData", nid, "name", data and data.name or nid)
				end
			end

			targetName = targetName or currentTarget:GetAttribute("DisplayName")
			if not targetName or targetName == "" then
				if currentTarget.Name == "Con_Doctor" then
					targetName = "콘닥터"
				else
					targetName = currentTarget.Name
				end
			end

			if currentTargetType == "radio" then
				targetName = UILocalizer.Localize("비상 무전기")
			elseif currentTargetType == "pal" then
				local cId = currentTarget:GetAttribute("CreatureId")
				if cId then
					local cData = DataHelper.GetData("CreatureData", cId)
					targetName = cData and cData.name or cId
				end
			end
			
			if currentTargetType == "resource" then
				promptText = UILocalizer.Localize("[R] 채집")
			elseif currentTargetType == "npc" then
				promptText = UILocalizer.Localize("[R] 대화")
			elseif currentTargetType == "facility" then
				promptText = UILocalizer.Localize("[R] 사용") .. "  " .. UILocalizer.Localize("[T] 해체")
			elseif currentTargetType == "pal" then
				promptText = UILocalizer.Localize("[R] 공룡 메뉴")
			elseif currentTargetType == "radio" then
				promptText = UILocalizer.Localize("[R] 무전 수신")
			else
				promptText = UILocalizer.Localize("[R] 상호작용")
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

	InteractController.rebindDefaultKeys()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local allowMountedMovement = player:GetAttribute("MountedPalUID")
			and isMountedMovementKey(input)
			and not UserInputService:GetFocusedTextBox()
		if gameProcessed and not allowMountedMovement then
			return
		end
		updateMountedControlKey(input, true)
	end)
	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		updateMountedControlKey(input, false)
	end)
	player:GetAttributeChangedSignal("MountedPalUID"):Connect(syncMountedJumpBinding)
	syncMountedJumpBinding()
	
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
	
	-- 탑승 중 공룡 조작 입력 주기적 전송 (0.05초 - 20Hz)
	task.spawn(function()
		while true do
			task.wait(0.05)
			if player:GetAttribute("MountedPalUID") then
				sendMountedControl(false)
			end
		end
	end)

	-- [UX 개선] 클라이언트측 물리 업데이트 (부드러운 카메라 상대 이동 및 회전)
	RunService.Heartbeat:Connect(function(dt)
		local mountedUID = player:GetAttribute("MountedPalUID")
		if not mountedUID then return end

		-- 현재 내가 타고 있는 공룡 모델 찾기
		local creatures = workspace:FindFirstChild("Creatures")
		local myMount = nil
		if creatures then
			for _, m in ipairs(creatures:GetChildren()) do
				if m:GetAttribute("MountedByUserId") == player.UserId then
					myMount = m
					break
				end
			end
		end

		if not myMount then return end
		local rootPart = myMount.PrimaryPart or myMount:FindFirstChild("HumanoidRootPart")
		local humanoid = myMount:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid then return end

		local throttle, steer = getMountControlValues()
		local hasThrottle = math.abs(throttle) > 0.01
		local hasSteer = math.abs(steer) > 0.01

		if hasThrottle or hasSteer then
			local camera = workspace.CurrentCamera
			if not camera then return end

			local camCF = camera.CFrame
			local camForward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
			local camRight = camCF.RightVector.Unit

			local moveDir = (camForward * throttle) + (camRight * steer)
			if moveDir.Magnitude > 0 then
				moveDir = moveDir.Unit
			end

			-- 회전 처리: S키(후진) 시에는 정면(카메라 앞)을 바라보고, 그 외에는 이동 방향을 바라보며 즉시 회전
			local faceDir = moveDir
			if throttle < 0 then
				faceDir = camForward
			end

			if faceDir.Magnitude > 0.01 then
				-- [Refinement] 즉시 스냅 대신 부드러운 회전(Lerp) 적용하여 더 자연스러운 느낌 제공
				local targetCF = CFrame.lookAt(rootPart.Position, rootPart.Position + faceDir)
				-- 0.05초(20Hz) 원격 호출 대비 Heartbeat(60Hz)에서 쾌적하게 작동하도록 높은 가중치(18) 사용
				-- [Improvement] 유타랍토르 등 고속 크리처를 위해 회전 가중치 상향 (18 -> 24)하여 드리프트 현상 감소
				rootPart.CFrame = rootPart.CFrame:Lerp(targetCF, math.clamp(dt * 24, 0, 1))
			end

			humanoid:Move(moveDir, false)
		else
			humanoid:Move(Vector3.zero, false)
		end
	end)
	
	initialized = true
	print("[InteractController] Initialized (R = Interact)")
end

--- 전역 상호작용 키 바인딩 복구 (타 UI나 모드에서 가로챈 키 반환용)
function InteractController.rebindDefaultKeys()
	local InputManager = require(Client.InputManager)
	
	-- R = 모든 상호작용 통합
	InputManager.bindKey(Enum.KeyCode.R, "InteractFacilityR", function()
		if InteractController.onFacilityInteractPress then
			InteractController.onFacilityInteractPress()
		end
	end)

	-- T = 건물 해체
	InputManager.bindKey(Enum.KeyCode.T, "InteractFacilityRemoveT", function()
		if InteractController.onFacilityRemovePress then
			InteractController.onFacilityRemovePress()
		end
	end)
	
	-- ESC = 모든 UI 닫기 통합
	InputManager.bindKey(Enum.KeyCode.Escape, "CloseUI", function()
		-- UIManager가 로드되지 않았을 수 있으므로 안전하게 처리
		local ok, UIManagerMod = pcall(require, Client.UIManager)
		if ok and UIManagerMod then
			UIManagerMod.closeInventory()
			UIManagerMod.closeCrafting()
			UIManagerMod.closeEquipment()
			UIManagerMod.closeBuild()
			UIManagerMod.closeShop()
			if UIManagerMod.closeTotem then UIManagerMod.closeTotem() end
		end
		
		-- Radial UIs
		local FRUI = require(Client.UI.FacilityRadialUI)
		if FRUI.IsOpen() then FRUI.Close() end
		
		local PRUI = require(Client.UI.PalRadialUI)
		if PRUI.IsOpen() then PRUI.Close() end
		
		local PortalRUI = require(Client.UI.PortalRadialUI)
		if PortalRUI.IsOpen() then PortalRUI.Close() end
		
		local HarvestUI = require(Client.UI.HarvestUI)
		if HarvestUI.IsOpen() then HarvestUI.Close() end
		
		local ok_WM, WindowManagerMod = pcall(require, Client.Utils.WindowManager)
		if ok_WM and WindowManagerMod and WindowManagerMod.closeAll then
			WindowManagerMod.closeAll()
		end
	end)
	
	print("[InteractController] Default keys (R, T, ESC) rebound.")
end

return InteractController
