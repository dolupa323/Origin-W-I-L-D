-- InteractController.lua
-- 상호작용 컨트롤러 (채집, NPC 대화, 구조물 상호작용)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)

local InteractController = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 상호작용 가능 대상
local currentTarget = nil
local currentTargetType = nil  -- "resource", "npc", "facility", "drop"

-- 상호작용 거리
local INTERACT_DISTANCE = 8

-- 상호작용 가능 폴더들
local interactableFolders = {}

-- UIManager 참조 (Init 후 설정)
local UIManager = nil

--========================================
-- Interactable Detection
--========================================

--- 상호작용 가능 타입 판별
local function getInteractableType(instance: Instance): string?
	-- 부모 폴더로 타입 판별
	local resourceNodes = workspace:FindFirstChild("ResourceNodes")
	local npcs = workspace:FindFirstChild("NPCs")
	local facilities = workspace:FindFirstChild("Facilities")
	local worldDrops = workspace:FindFirstChild("WorldDrops")
	
	if resourceNodes and instance:IsDescendantOf(resourceNodes) then
		return "resource"
	elseif npcs and instance:IsDescendantOf(npcs) then
		return "npc"
	elseif facilities and instance:IsDescendantOf(facilities) then
		return "facility"
	elseif worldDrops and instance:IsDescendantOf(worldDrops) then
		return "drop"
	end
	
	return nil
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
			local part = node:IsA("Model") and (node.PrimaryPart or node:FindFirstChild("Part")) or node
			if part and part:IsA("BasePart") then
				local dist = (part.Position - playerPos).Magnitude
				if dist < closestDist and dist <= INTERACT_DISTANCE then
					closestTarget = node
					closestType = "resource"
					closestDist = dist
				end
			end
		end
	end
	
	-- WorldDrops 검색
	local worldDrops = workspace:FindFirstChild("WorldDrops")
	if worldDrops then
		for _, drop in pairs(worldDrops:GetChildren()) do
			local part = drop:IsA("Model") and (drop.PrimaryPart or drop:FindFirstChild("Part")) or drop
			if part and part:IsA("BasePart") then
				local dist = (part.Position - playerPos).Magnitude
				if dist < closestDist and dist <= INTERACT_DISTANCE then
					closestTarget = drop
					closestType = "drop"
					closestDist = dist
				end
			end
		end
	end
	
	-- NPCs 검색
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, npc in pairs(npcs:GetChildren()) do
			local part = npc:IsA("Model") and (npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart")) or npc
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
			local part = facility:IsA("Model") and facility.PrimaryPart or facility
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

--- 자원 채집
local function harvestResource(target: Instance)
	-- NodeUID 속성 우선 사용 (NodeId는 fallback)
	local nodeUID = target:GetAttribute("NodeUID")
	
	if not nodeUID then
		warn("[InteractController] No NodeUID attribute on resource node:", target.Name)
		return
	end
	
	print("[InteractController] Harvesting:", nodeUID)
	
	NetClient.Request("Harvest.Hit.Request", {
		nodeUID = nodeUID,
	}, function(response)
		if response.success then
			print("[InteractController] Harvest success!")
		else
			print("[InteractController] Harvest failed:", response.errorCode or "unknown")
		end
	end)
end

--- 월드 드롭 줍기
local function pickupDrop(target: Instance)
	local dropId = target:GetAttribute("DropId") or target.Name
	
	print("[InteractController] Picking up:", dropId)
	
	NetClient.Request("WorldDrop.Loot.Request", {
		dropId = dropId,
	}, function(response)
		if response.success then
			print("[InteractController] Pickup success!")
		else
			print("[InteractController] Pickup failed:", response.errorCode or "unknown")
		end
	end)
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
	local facilityId = target:GetAttribute("FacilityId") or target.Name
	
	print("[InteractController] Interacting with facility:", facilityId)
	
	-- TODO: 시설 UI 열기
end

--========================================
-- Public API
--========================================

--- 현재 대상과 상호작용
function InteractController.interact()
	if InputManager.isUIOpen() then
		return
	end
	
	if currentTarget and currentTargetType then
		if currentTargetType == "resource" then
			harvestResource(currentTarget)
		elseif currentTargetType == "drop" then
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
	local target, targetType = findNearbyInteractable()
	
	if target ~= currentTarget then
		currentTarget = target
		currentTargetType = targetType
		
		if UIManager then
			if target then
				local promptText = "[E] "
				if targetType == "resource" then
					promptText = promptText .. "채집"
				elseif targetType == "drop" then
					promptText = promptText .. "줍기"
				elseif targetType == "npc" then
					promptText = promptText .. "대화"
				elseif targetType == "facility" then
					promptText = promptText .. "사용"
				else
					promptText = promptText .. "상호작용"
				end
				UIManager.showInteractPrompt(promptText)
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
	
	-- E 키 바인딩
	InputManager.bindKey(Enum.KeyCode.E, "Interact", function()
		InteractController.interact()
	end)
	
	-- 매 프레임 대상 감지
	RunService.Heartbeat:Connect(onHeartbeat)
	
	initialized = true
	print("[InteractController] Initialized")
end

return InteractController
