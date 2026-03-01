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

-- 상호작용 거리 (Balance에서 가져옴, 여유분 추가)
local INTERACT_DISTANCE = (Balance.HARVEST_RANGE or 10) + 4

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
	
	local targetFolderNames = {"ResourceNodes", "WorldDrops", "NPCs", "Facilities"}
	local includeList = {}
	for _, name in ipairs(targetFolderNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then table.insert(includeList, folder) end
	end
	
	if #includeList == 0 then return nil, nil end
	overlapParams.FilterDescendantsInstances = includeList
	
	-- 반경 내 파트 검색
	local nearbyParts = workspace:GetPartBoundsInRadius(playerPos, INTERACT_DISTANCE, overlapParams)
	
	local closestTarget = nil
	local closestType = nil
	local closestDist = INTERACT_DISTANCE + 1
	
	local typeMap = {
		ResourceNodes = "resource",
		WorldDrops = "drop",
		NPCs = "npc",
		Facilities = "facility"
	}
	
	for _, part in ipairs(nearbyParts) do
		-- 모델 또는 최상위 객체 찾기
		local entity = part
		while entity and entity.Parent and not typeMap[entity.Parent.Name] do
			entity = entity.Parent
		end
		
		if not entity or not entity.Parent then continue end
		local folderName = entity.Parent.Name
		local currentType = typeMap[folderName]
		if not currentType then continue end
		
		-- 고갈된 노드 스킵
		if currentType == "resource" and entity:GetAttribute("Depleted") then
			continue
		end
		
		-- 거리 계산 (표면 거리 대신 중심 거리로 근사화해도 충분히 빠름)
		local dist = (part.Position - playerPos).Magnitude
		if dist < closestDist then
			closestDist = dist
			closestTarget = entity
			closestType = currentType
		end
	end
	
	return closestTarget, closestType
end

--========================================
-- Interaction Handlers
--========================================


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
		-- [제거] 작업대 개념 없음. 모든 제작은 인벤토리[I]에서 수행됩니다.
		if UIManager then
			UIManager.notify("제작 및 요리는 인벤토리[I]의 제작 탭에서 가능합니다.", Color3.fromRGB(255, 210, 80))
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

--- 주변 대상 감지 업데이트 (10Hz)
local function onUpdate()
	local target, targetType = findNearbyInteractable()
	
	if target ~= currentTarget then
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
	print("[InteractController] Initialized (Z = Interact)")
end

return InteractController
