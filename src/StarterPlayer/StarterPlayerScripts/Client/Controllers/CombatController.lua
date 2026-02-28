-- CombatController.lua
-- 클라이언트 전투 컨트롤러 (공격 요청, 애니메이션)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local AnimationIds = require(Shared.Config.AnimationIds)
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UIManager = require(Client.UIManager)
local AnimationManager = require(Client.Utils.AnimationManager)

local CombatController = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 공격 쿨다운
local lastAttackTime = 0
local ATTACK_COOLDOWN = 0.5  -- 0.5초

-- 콤보 시스템
local currentComboIndex = 1
local comboResetTime = 1.0  -- 1초 내 다음 공격 안하면 콤보 리셋

-- 애니메이션 트랙
local currentAttackTrack = nil

--========================================
-- Internal Functions
--========================================

--- 장착 도구 타입 확인
local function getEquippedToolType(): string?
	local character = player.Character
	if not character then return nil end
	
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		return tool:GetAttribute("ToolType") or tool.Name:upper()
	end
	
	return nil
end

local AnimationManager = require(Client.Utils.AnimationManager)

--- 공격 애니메이션 재생
local function playAttackAnimation(isHit: boolean)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- 기존 공격 애니메이션 중지
	if currentAttackTrack and currentAttackTrack.IsPlaying then
		currentAttackTrack:Stop(0.1)
	end
	
	-- 도구 타입에 따른 애니메이션 선택
	local toolType = getEquippedToolType()
	local animNames
	
	if toolType == "AXE" then
		animNames = { AnimationIds.ATTACK_SPEAR.SWING }
	elseif toolType == "PICKAXE" then
		animNames = { "AttackTool_Mine" }
	elseif toolType == "SPEAR" then
		animNames = { AnimationIds.ATTACK_SPEAR.THRUST, AnimationIds.ATTACK_SPEAR.SWING }
	elseif toolType == "BOLA" then
		animNames = { AnimationIds.BOLA.THROW }
	elseif toolType == "CLUB" or toolType == "TORCH" then
		-- 나무 몽둥이와 횃불은 맨손 1, 2타만 사용 (3타 제외)
		animNames = { AnimationIds.COMBO_UNARMED[1], AnimationIds.COMBO_UNARMED[2] }
	else
		-- 맨손 공격 (1, 2, 3타 모두 사용)
		animNames = AnimationIds.COMBO_UNARMED
	end
	
	-- 콤보 인덱스에 따른 애니메이션 선택
	local animName = animNames[currentComboIndex] or animNames[1]
	
	-- 애니메이션 재생 (AnimationManager 사용)
	local track = AnimationManager.play(humanoid, animName, 0.05)
	if track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		
		-- 맞았을 때 속도 조절 (임팩트 느낌)
		if isHit then
			track:AdjustSpeed(1.2)  -- 빠르게
		else
			track:AdjustSpeed(1.0)
		end
		
		currentAttackTrack = track
	end
	
	-- 콤보 증가 (다음 공격시 다른 모션)
	currentComboIndex = currentComboIndex + 1
	if currentComboIndex > #animNames then
		currentComboIndex = 1
	end
	
	-- 콤보 리셋 타이머
	task.delay(comboResetTime, function()
		if tick() - lastAttackTime >= comboResetTime then
			currentComboIndex = 1
		end
	end)
end

--- 공격 대상 찾기 (마우스 위치 + 구체 영역 체크)
local function findTarget(): (Instance?, Vector3?, string?, string?)
	-- 1. 마우스 위치 타겟 확인
	local target = InputManager.getMouseTarget()
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	local nodesFolder = workspace:FindFirstChild("ResourceNodes")
	
	local function checkModel(part)
		if not part then return nil end
		local model = part:FindFirstAncestorOfClass("Model")
		if not model then return nil end
		
		if creaturesFolder and model:IsDescendantOf(creaturesFolder) then
			local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			local instanceId = model:GetAttribute("InstanceId")
			if hrp and instanceId then
				return model, hrp.Position, instanceId, "creature"
			end
		elseif nodesFolder and model:IsDescendantOf(nodesFolder) then
			local nodeUID = model:GetAttribute("NodeUID")
			local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if nodeUID and primary then
				return model, primary.Position, nodeUID, "resource"
			end
		end
		return nil
	end

	-- 마우스 타겟 우선 확인
	local mModel, mPos, mId, mType = checkModel(target)
	if mModel then return mModel, mPos, mId, mType end
	
	-- 2. 플레이어 전방 구체 범위(Hitbox) 체크
	local char = player.Character
	if char and char.PrimaryPart then
		local findRadius = Balance.COMBAT_HITBOX_SIZE or 8
		local pos = char.PrimaryPart.Position + char.PrimaryPart.CFrame.LookVector * (findRadius * 0.6)
		
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {creaturesFolder, nodesFolder}
		
		local parts = workspace:GetPartBoundsInRadius(pos, findRadius, overlap)
		local bestTarget, bestPos, bestId, bestType
		local minDist = math.huge
		
		for _, p in ipairs(parts) do
			local model, pPos, id, tType = checkModel(p)
			if model then
				local dist = (char.PrimaryPart.Position - pPos).Magnitude
				if dist < minDist then
					minDist = dist
					bestTarget, bestPos, bestId, bestType = model, pPos, id, tType
				end
			end
		end
		
		if bestTarget then
			return bestTarget, bestPos, bestId, bestType
		end
	end
	
	return nil, nil, nil, nil
end

local function getDistanceToTarget(targetPos: Vector3): number
	local character = player.Character
	if not character then return math.huge end
	
	local hrp = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not hrp then return math.huge end
	
	-- Y축 차이를 줄인 평면 거리로 계산 (거대 공룡/나무 대응)
	local p1 = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
	local p2 = Vector3.new(targetPos.X, 0, targetPos.Z)
	return (p1 - p2).Magnitude
end

--========================================
-- Public API
--========================================

--- 공격 실행
function CombatController.attack()
	-- UI가 열려있으면 무시
	if InputManager.isUIOpen() then
		return
	end
	
	-- 쿨다운 체크
	local now = tick()
	if now - lastAttackTime < ATTACK_COOLDOWN then
		return
	end
	
	lastAttackTime = now
	
	-- 선택된 아이템이 음식인지 확인 (들고 있는 상태에서 좌클릭 시 먹기)
	local selectedSlot = UIManager.getSelectedSlot()
	local InventoryController = require(Client.Controllers.InventoryController)
	local slotData = InventoryController.getSlot(selectedSlot)
	
	if slotData then
		local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
		local itm = nil
		for _, v in ipairs(ItemData) do
			if v.id == slotData.itemId then
				itm = v
				break
			end
		end
		
		if itm and (itm.type == Enums.ItemType.FOOD or itm.foodValue) then
			-- 섭취 애니메이션 재생
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				AnimationManager.play(humanoid, AnimationIds.CONSUME.EAT)
			end
			
			InventoryController.requestUse(selectedSlot)
			return
		end
	end
	
	local targetModel, targetPos, targetId, targetType = findTarget()
	
	if targetModel and targetPos and targetId then
		local distance = getDistanceToTarget(targetPos)
		local maxRange = Balance.HARVEST_RANGE or 15
		
		-- 공격 범위 체크
		if distance > maxRange then
			-- 범위 밖 - 빈 스윙 애니메이션
			playAttackAnimation(false)
			return
		end
		
		-- 공격 성공 애니메이션 (타격)
		playAttackAnimation(true)
		
		if targetType == "resource" then
			-- 자원 채집 처리 (좌클릭 공격으로 수확!)
			local success, result = NetClient.Request("Harvest.Hit.Request", {
				nodeUID = targetId,
				toolSlot = UIManager.getSelectedSlot(),
			})
			if not success then
				if result == Enums.ErrorCode.WRONG_TOOL or result == "WRONG_TOOL" then
					UIManager.notify("이 자원을 채집하려면 도구가 필요합니다!", Color3.fromRGB(255, 100, 100))
				end
			end
		else
			-- 크리처 공격 처리
			local success, data = NetClient.Request("Combat.Hit.Request", {
				targetInstanceId = targetId,
				toolSlot = UIManager.getSelectedSlot(),
			})
		end
	else
		-- 대상 없이 빈 공격 (공기 스윙)
		playAttackAnimation(false)
	end
end

--========================================
-- Initialization
--========================================

function CombatController.Init()
	if initialized then
		warn("[CombatController] Already initialized!")
		return
	end
	
	-- 좌클릭 = 공격
	InputManager.onLeftClick("CombatAttack", function(hitPos)
		CombatController.attack()
	end)
	
	initialized = true
	print("[CombatController] Initialized")
end

return CombatController
