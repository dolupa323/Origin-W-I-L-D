-- InteractController.lua
-- 상호작용 컨트롤러 (채집, NPC 대화, 구조물 상호작용)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared.Config.AnimationIds)
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

local InteractController = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 상호작용 가능 대상
local currentTarget = nil
local currentTargetType = nil  -- "resource", "npc", "facility", "drop"

-- 채집 홀드 상태
local isHarvesting = false
local harvestStartTime = 0
local harvestTarget = nil
local harvestNodeUID = nil

-- 채집 애니메이션
local currentHarvestTrack = nil

-- 상호작용 거리 (Balance에서 가져옴, 여유분 추가)
local INTERACT_DISTANCE = (Balance.HARVEST_RANGE or 10) + 4
local HARVEST_CANCEL_DISTANCE = INTERACT_DISTANCE + 6  -- 채집 중 취소 거리 (더 관대)

-- 상호작용 가능 폴더들
local interactableFolders = {}

-- UIManager 참조 (Init 후 설정)
local UIManager = nil

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

--- 플레이어 근처의 상호작용 가능 대상 찾기
local function findNearbyInteractable(): (Instance?, string?)
	local character = player.Character
	if not character then return nil, nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end
	
	local playerPos = hrp.Position
	local closestTarget = nil
	local closestType = nil
	local closestDist = INTERACT_DISTANCE + 1
	
	-- ResourceNodes 검색
	local resourceNodes = workspace:FindFirstChild("ResourceNodes")
	if resourceNodes then
		for _, node in pairs(resourceNodes:GetChildren()) do
			-- 고갈된 노드는 건너뛰기
			if node:GetAttribute("Depleted") then
				continue
			end
			
			local dist
			if node:IsA("Model") then
				dist = getDistToModel(node, playerPos)
			elseif node:IsA("BasePart") then
				dist = getDistToSurface(node, playerPos)
			end
			
			if dist and dist < closestDist and dist <= INTERACT_DISTANCE then
				closestTarget = node
				closestType = "resource"
				closestDist = dist
			end
		end
	end
	
	-- WorldDrops 검색
	local worldDrops = workspace:FindFirstChild("WorldDrops")
	if worldDrops then
		for _, drop in pairs(worldDrops:GetChildren()) do
			local dist
			if drop:IsA("Model") then
				dist = getDistToModel(drop, playerPos)
			elseif drop:IsA("BasePart") then
				dist = getDistToSurface(drop, playerPos)
			end
			
			if dist and dist < closestDist and dist <= INTERACT_DISTANCE then
				closestTarget = drop
				closestType = "drop"
				closestDist = dist
			end
		end
	end
	
	-- NPCs 검색
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, npc in pairs(npcs:GetChildren()) do
			local part
			if npc:IsA("Model") then
				part = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart", true)
			elseif npc:IsA("BasePart") then
				part = npc
			end
			
			if part and part:IsA("BasePart") then
				local dist = (part.Position - playerPos).Magnitude
				if dist < closestDist and dist <= INTERACT_DISTANCE then
					closestTarget = npc
					closestType = "npc"
					closestDist = dist
				end
			end
		end
	end
	
	-- Facilities 검색  
	local facilities = workspace:FindFirstChild("Facilities")
	if facilities then
		for _, facility in pairs(facilities:GetChildren()) do
			local part
			if facility:IsA("Model") then
				part = facility.PrimaryPart or facility:FindFirstChildWhichIsA("BasePart", true)
			elseif facility:IsA("BasePart") then
				part = facility
			end
			
			if part and part:IsA("BasePart") then
				local dist = (part.Position - playerPos).Magnitude
				if dist < closestDist and dist <= INTERACT_DISTANCE then
					closestTarget = facility
					closestType = "facility"
					closestDist = dist
				end
			end
		end
	end
	
	return closestTarget, closestType
end

--========================================
-- Interaction Handlers
--========================================

--- 현재 장착 도구 가져오기
local function getEquippedTool(): string?
	local character = player.Character
	if not character then return nil end
	
	-- Humanoid에 장착된 Tool 확인
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		return tool:GetAttribute("ToolType") or tool.Name:upper()
	end
	
	return nil
end

--- 채집 시간 계산 (도구에 따라)
local function getHarvestTime(target: Instance): number
	local nodeData = target:GetAttribute("NodeData")
	local optimalTool = target:GetAttribute("OptimalTool")
	local equippedTool = getEquippedTool()
	
	local baseTime = Balance.HARVEST_HOLD_TIME_BASE or 2.0
	local optimalTime = Balance.HARVEST_HOLD_TIME_OPTIMAL or 0.8
	
	-- 최적 도구가 없으면 맨손이 최적
	if not optimalTool or optimalTool == "" then
		return optimalTime
	end
	
	-- 최적 도구 사용
	if equippedTool and equippedTool:upper() == optimalTool:upper() then
		return optimalTime
	end
	
	-- 다른 도구 사용
	if equippedTool then
		return baseTime * 0.8  -- 잘못된 도구
	end
	
	-- 맨손
	return baseTime
end

local AnimationManager = require(Client.Utils.AnimationManager)

--- 채집 애니메이션 재생
local function playHarvestAnimation(target: Instance)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- 기존 채집 애니메이션 중지
	if currentHarvestTrack and currentHarvestTrack.IsPlaying then
		currentHarvestTrack:Stop(0.1)
	end
	
	-- 노드 타입에 따른 애니메이션 선택
	local nodeType = target:GetAttribute("NodeType") or "TREE"
	local equippedTool = getEquippedTool()
	local animName
	
	if nodeType == "TREE" then
		if equippedTool and (equippedTool:upper() == "AXE") then
			animName = AnimationIds.HARVEST.CHOP  -- 도끼 휘두르기
		else
			animName = AnimationIds.HARVEST.GATHER  -- 손으로 모으기
		end
	elseif nodeType == "ROCK" or nodeType == "ORE" then
		if equippedTool and (equippedTool:upper() == "PICKAXE") then
			animName = AnimationIds.HARVEST.MINE  -- 곡괭이
		else
			animName = AnimationIds.HARVEST.GATHER
		end
	else
		animName = AnimationIds.HARVEST.GATHER  -- 기본 손 채집
	end
	
	-- 애니메이션 재생 (AnimationManager 사용)
	local track = AnimationManager.play(humanoid, animName)
	if track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true  -- 채집 중 반복
		track:AdjustSpeed(0.8)  -- 느리게
		currentHarvestTrack = track
	end
end

--- 채집 애니메이션 중지
local function stopHarvestAnimation()
	if currentHarvestTrack and currentHarvestTrack.IsPlaying then
		currentHarvestTrack:Stop(0.2)
		currentHarvestTrack = nil
	end
end

--- 자원 채집 시작
local function startHarvest(target: Instance)
	local nodeUID = target:GetAttribute("NodeUID")
	
	if not nodeUID then
		warn("[InteractController] No NodeUID attribute on resource node:", target.Name)
		return
	end
	
	isHarvesting = true
	harvestStartTime = tick()
	harvestTarget = target
	harvestNodeUID = nodeUID
	
	local harvestTime = getHarvestTime(target)
	
	-- 채집 애니메이션 시작
	playHarvestAnimation(target)
	
	-- UI 진행바 표시 (대상 이름 전달)
	local targetName = target:GetAttribute("DisplayName") or target:GetAttribute("NodeType") or target.Name
	if UIManager and UIManager.showHarvestProgress then
		UIManager.showHarvestProgress(harvestTime, targetName)
	end
	
	print("[InteractController] Start harvesting:", nodeUID)
end

--- 자원 채집 중단
local function cancelHarvest()
	if not isHarvesting then return end
	
	isHarvesting = false
	harvestStartTime = 0
	harvestTarget = nil
	harvestNodeUID = nil
	
	-- 채집 애니메이션 중지
	stopHarvestAnimation()
	
	-- UI 진행바 숨기기
	if UIManager and UIManager.hideHarvestProgress then
		UIManager.hideHarvestProgress()
	end
	
	print("[InteractController] Harvest cancelled")
end

--- 자원 채집 완료 (서버 요청)
local function completeHarvest()
	if not isHarvesting or not harvestNodeUID then return end
	
	local nodeUID = harvestNodeUID
	
	isHarvesting = false
	harvestStartTime = 0
	harvestTarget = nil
	harvestNodeUID = nil
	
	-- 채집 애니메이션 중지
	stopHarvestAnimation()
	
	-- UI 진행바 숨기기
	if UIManager and UIManager.hideHarvestProgress then
		UIManager.hideHarvestProgress()
	end
	
	print("[InteractController] Harvesting:", nodeUID)
	
	local success, data = NetClient.Request("Harvest.Hit.Request", {
		nodeUID = nodeUID,
		toolSlot = UIManager.getSelectedSlot(),
		hitCount = 99, -- 전량 채집
	})
	if success then
		print("[InteractController] Harvest success!")
	else
		print("[InteractController] Harvest failed:", tostring(data))
	end
end

--- 채집 홀드 업데이트 (매 프레임)
local function updateHarvest()
	if not isHarvesting then return end
	
	-- 타겟이 사라졌거나 거리 벗어남
	if not harvestTarget or not harvestTarget.Parent then
		cancelHarvest()
		return
	end
	
	local character = player.Character
	if not character then
		cancelHarvest()
		return
	end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		cancelHarvest()
		return
	end
	
	-- 거리 체크용 파트 찾기 (Hitbox/InteractPart 우선)
	local part
	if harvestTarget:IsA("Model") then
		part = harvestTarget:FindFirstChild("Hitbox")
			or harvestTarget:FindFirstChild("InteractPart")
			or harvestTarget.PrimaryPart
			or harvestTarget:FindFirstChildWhichIsA("BasePart", true)
	elseif harvestTarget:IsA("BasePart") then
		part = harvestTarget
	end
	
	-- 표면 거리로 채집 취소 판정 (더 관대한 거리 사용)
	local dist
	if harvestTarget:IsA("Model") then
		dist = getDistToModel(harvestTarget, hrp.Position)
	elseif harvestTarget:IsA("BasePart") then
		dist = getDistToSurface(harvestTarget, hrp.Position)
	end
	if dist and dist > HARVEST_CANCEL_DISTANCE then
		cancelHarvest()
		return
	end
	
	-- 진행률 계산
	local elapsed = tick() - harvestStartTime
	local harvestTime = getHarvestTime(harvestTarget)
	local progress = math.clamp(elapsed / harvestTime, 0, 1)
	
	-- UI 업데이트
	if UIManager and UIManager.updateHarvestProgress then
		UIManager.updateHarvestProgress(progress)
	end
	
	-- 완료 확인
	if progress >= 1 then
		completeHarvest()
	end
end

--- 월드 드롭 줍기
local function pickupDrop(target: Instance)
	local dropId = target:GetAttribute("DropId")
	
	-- GUID 형식의 Name인 경우 (이전 방식 호환)
	if not dropId and target.Name:find("drop_") then
		dropId = target.Name
	end
	
	if not dropId then
		warn("[InteractController] No DropId found for target:", target.Name)
		return
	end
	
	print("[InteractController] Picking up:", dropId)
	
	local success, data = NetClient.Request("WorldDrop.Loot.Request", {
		dropId = dropId,
	})
	if success then
		print("[InteractController] Pickup success!")
	else
		print("[InteractController] Pickup failed:", tostring(data))
	end
end

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
	
	if facilityData.functionType == "CRAFTING" or facilityData.functionType == "COOKING" then
		-- 제작/작업대 UI 열기
		if UIManager then
			UIManager.openWorkbench(structureId, facilityId)
		end
	elseif facilityData.functionType == "STORAGE" then
		-- 보관함 UI 열기 (별도 구현 필요)
		print("[InteractController] Storage UI not implemented yet")
	elseif facilityData.functionType == "RESPAWN" then
		-- 리스폰 위치 설정
		print("[InteractController] Respawn point set")
		UIManager.notify("부활 지점이 설정되었습니다.")
	end
end

--========================================
-- Public API
--========================================

--- Z키 눌림 처리 (줍기, 대화 등)
function InteractController.onInteractPress()
	if InputManager.isUIOpen() then
		return
	end
	
	if currentTarget and currentTargetType then
		if currentTargetType == "resource" then
			-- 채집은 이제 공격(좌클릭)으로 처리하므로 여기서는 무시하거나 안내만 함
			print("[InteractController] 공격(좌클릭)으로 채집하세요.")
		elseif currentTargetType == "drop" then
			-- 드롭 줍기는 즉시
			pickupDrop(currentTarget)
		elseif currentTargetType == "npc" then
			interactNPC(currentTarget)
		elseif currentTargetType == "facility" then
			interactFacility(currentTarget)
		end
	end
end

--- 매 프레임 업데이트 (근처 대상 감지)
local function onHeartbeat()
	-- 채집 홀드 업데이트
	updateHarvest()
	
	local target, targetType = findNearbyInteractable()
	
	if target ~= currentTarget then
		-- 타겟이 바뀌면 채집 취소
		if isHarvesting then
			cancelHarvest()
		end
		
		currentTarget = target
		currentTargetType = targetType
		
		if UIManager then
			if target then
				local promptText = "[Z] "
				local rawName = target:GetAttribute("DisplayName") or target:GetAttribute("Name") or target.Name
				local targetName = rawName
				
				if targetType == "resource" then
					promptText = "" -- 안내문 삭제 (HP바로 대체)
				elseif targetType == "drop" then
					promptText = promptText .. "줍기"
					
					-- 만약 이름이 구별 기호(Drop_)로 남아있다면 한국어로 아이템이라고 처리
					local dropId = target:GetAttribute("DropId")
					if dropId then
						local itemData = DataHelper.GetData("ItemData", dropId)
						if itemData then targetName = itemData.name end
					end
					
					if type(targetName) == "string" and (targetName:lower():find("^drop_") or targetName:find("Drop")) then
						targetName = "아이템"
					end
				elseif targetType == "npc" then
					promptText = promptText .. "대화"
				elseif targetType == "facility" then
					promptText = promptText .. "사용"
				else
					promptText = promptText .. "상호작용"
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
	
	-- 매 프레임 대상 감지 업데이트
	RunService.Heartbeat:Connect(onHeartbeat)
	
	initialized = true
	print("[InteractController] Initialized (Z = Interact)")
end

return InteractController
