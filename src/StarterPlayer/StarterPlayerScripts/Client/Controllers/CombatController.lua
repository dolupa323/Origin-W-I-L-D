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
		animNames = { AnimationIds.ATTACK_SPEAR.THRUST }
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

--- 카메라 쉐이크 (타격감)
local function playHitShake(intensity)
	local cam = workspace.CurrentCamera
	if not cam then return end
	
	task.spawn(function()
		local originalCF = cam.CFrame
		for i = 1, 4 do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)
			cam.CFrame = cam.CFrame * CFrame.new(offset)
			task.wait(0.02)
		end
	end)
end

local function findTarget()
	local creaturesFolder = workspace:FindFirstChild("ActiveCreatures") or workspace:FindFirstChild("Creatures")
	local nodesFolder = workspace:FindFirstChild("ResourceNodes")
	local facilitiesFolder = workspace:FindFirstChild("Facilities")

	local function checkModel(part)
		if not part then return nil, nil end
		
		local current = part
		while current and current ~= workspace do
			if current:IsA("Model") then
				-- 자원 노드 체크
				local nodeUID = current:GetAttribute("NodeUID")
				if nodeUID then
					return current, nodeUID, "resource"
				end

				-- 크리처 체크
				local instanceId = current:GetAttribute("InstanceId")
				if instanceId then
					return current, instanceId, "creature"
				end

				-- 구조물 체크
				local structureId = current:GetAttribute("StructureId")
				if structureId then
					return current, structureId, "structure"
				end
			end

			local structureIdFromPart = current:GetAttribute("StructureId")
			if structureIdFromPart then
				local model = current:FindFirstAncestorWhichIsA("Model")
				return model or current, structureIdFromPart, "structure"
			end
			current = current.Parent
		end
		
		return nil, nil
	end

	local char = player.Character
	if not char or not char.PrimaryPart then return nil end
	
	-- 도구별 사거리 결정
	local toolType = getEquippedToolType()
	local reach = Balance.REACH_BAREHAND or 10
	if toolType == "SPEAR" then
		reach = Balance.REACH_SPEAR or 16
	elseif toolType == "AXE" or toolType == "PICKAXE" or toolType == "CLUB" then
		reach = Balance.REACH_TOOL or 12
	end

	-- 1. 캐릭터 주변 엔티티 탐색 (Sphere)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local filterInstances = {}
	if creaturesFolder then table.insert(filterInstances, creaturesFolder) end
	if nodesFolder then table.insert(filterInstances, nodesFolder) end
	if facilitiesFolder then table.insert(filterInstances, facilitiesFolder) end
	overlap.FilterDescendantsInstances = filterInstances
	
	-- 판정 반경은 리치보다 넉넉하게 (각도/정밀 사거리 판정 전 단계)
	local scanRadius = reach + 15
	local parts = workspace:GetPartBoundsInRadius(char.PrimaryPart.Position, scanRadius, overlap)
	local reachableTargets = {}

	for _, p in ipairs(parts) do
		local model, id, tType = checkModel(p)
		if model then
			-- [개선] 모든 파트를 검사하여 가장 가까운 지점을 찾음 (히트박스 전영역화)
			local targetPos = p.Position
			local toTarget = (targetPos - char.PrimaryPart.Position)
			local dist = toTarget.Magnitude
			
			-- 현재 모델에 대해 더 가까운 파트가 있으면 갱신
			if not reachableTargets[id] or dist < reachableTargets[id].dist then
				-- Y축 무시한 방향 벡터 (평면 판정)
				local toTargetFlat = Vector3.new(toTarget.X, 0, toTarget.Z).Unit
				local lookFlat = Vector3.new(char.PrimaryPart.CFrame.LookVector.X, 0, char.PrimaryPart.CFrame.LookVector.Z).Unit
				local dot = lookFlat:Dot(toTargetFlat)
				local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
				
				-- 사거리 이내 & 정면 부근(75도)인 것들만 수집
				if dist <= reach + 5 and angle <= (Balance.REACH_ANGLE or 75) then
					reachableTargets[id] = {model=model, pos=targetPos, id=id, type=tType, dist=dist, angle=angle}
				end
			end
		end
	end

	-- 2. 타겟 우선순위 결정
	-- [우선순위 1] 마우스가 가리키는 대상 (에임)
	local mousePart = InputManager.getMouseTarget()
	if mousePart then
		local mModel, mId, mType = checkModel(mousePart)
		if mId then
			local mPos = mousePart.Position
			local mDist = (mPos - char.PrimaryPart.Position).Magnitude
			
			-- 마우스로 직접 찍은 경우 정면 판정 완화 (히트박스 우선)
			if mDist <= reach + 8 then
				return mModel, mPos, mId, mType
			end
		end
	end

	-- [우선순위 2] 정면에서 가장 가깝거나 점수가 높은 대상
	local bestTarget = nil
	local minScore = math.huge
	
	for id, data in pairs(reachableTargets) do
		local score = data.dist * (1 + data.angle / 45)
		if score < minScore then
			minScore = score
			bestTarget = data
		end
	end

	if bestTarget then
		return bestTarget.model, bestTarget.pos, bestTarget.id, bestTarget.type
	end

	return nil
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
	
	-- 1. 선택된 슬롯 및 아이템 데이터 가져오기 (쿨다운, 음식 섭취, 사거리 등)
	local selectedSlot = UIManager.getSelectedSlot()
	local InventoryController = require(Client.Controllers.InventoryController)
	local slotData = InventoryController.getSlot(selectedSlot)
	local itm = nil
	
	if slotData then
		local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
		for _, v in ipairs(ItemData) do
			if v.id == slotData.itemId then itm = v; break end
		end
	end
	
	-- 2. 도구별 동적 쿨다운 결정
	local dynamicCooldown = ATTACK_COOLDOWN -- 기본 0.5초
	if itm and itm.attackSpeed then
		dynamicCooldown = itm.attackSpeed
	end
	
	-- 3. 쿨다운 체크
	local now = tick()
	if now - lastAttackTime < dynamicCooldown then
		return
	end
	lastAttackTime = now
	
	-- 4. 음식이면 먹기 처리
	if itm and (itm.type == Enums.ItemType.FOOD or itm.foodValue) then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			AnimationManager.play(humanoid, AnimationIds.CONSUME.EAT)
		end
		InventoryController.requestUse(selectedSlot)
		return
	end
	
	-- 2. 대상 검색
	local targetModel, targetPos, targetId, targetType = findTarget()
	
	if targetModel and targetPos and targetId then
		local distance = getDistanceToTarget(targetPos)
		
		-- 도구별 사거리 결정 (서버와 싱크)
		-- 도구별 사거리 결정 (findTarget과 동일하게)
		local toolType = getEquippedToolType()
		local reach = Balance.REACH_BAREHAND or 10
		if toolType == "SPEAR" then
			reach = Balance.REACH_SPEAR or 16
		elseif toolType == "AXE" or toolType == "PICKAXE" or toolType == "CLUB" then
			reach = Balance.REACH_TOOL or 12
		end

		-- 장착 도구 데이터에 의한 추가 보정
		if itm and itm.range then
			reach = math.max(reach, itm.range)
		end
		
		local maxRange = reach + 4 -- 서버 오차 보정용 여유분
		
		-- 최종 공격 범위 체크
		if distance > maxRange then
			-- 범위 밖 - 공기 가르기 (빈 스윙)
			playAttackAnimation(false)
			return
		end
		
		-- [FIX] 타격 타이밍(Windup) 보정: 애니메이션 피격 시점에 맞춰 Request 전송
		playAttackAnimation(true)
		
		local toolType = getEquippedToolType() -- 도구 타입 (windup 계산용)
		local windupTime = 0.2 -- 기본 0.2초 딜레이
		if itm and itm.windup then
			windupTime = itm.windup
		elseif toolType == "SPEAR" then
			windupTime = 0.3
		elseif toolType == "CLUB" or toolType == "AXE" then
			windupTime = 0.4
		end
		
		-- 애니메이션 트랙에서 직접 'Hit' 마커를 기다리거나, 타임아웃 딜레이 사용
		task.spawn(function()
			local hitTriggered = false
			local conn
			
			if currentAttackTrack then
				conn = currentAttackTrack:GetMarkerReachedSignal("Hit"):Connect(function()
					hitTriggered = true
					if conn then conn:Disconnect(); conn = nil end
				end)
			end
			
			-- 마커가 없거나 안 불릴 경우를 대비해 windup만큼 대기 (또는 마커 불릴 때까지 대기)
			local startWait = tick()
			while tick() - startWait < windupTime and not hitTriggered do
				task.wait()
			end
			
			if conn then conn:Disconnect() end

			-- [FX] 타격 피드백 (카메라 쉐이크 & 대상 흔들림)
			playHitShake(0.5) -- 더욱 강한 쉐이크 (기존 0.3)
			local char = player.Character
			if targetType ~= "structure" and targetModel and char and char.PrimaryPart then
				local targetPos = targetModel:GetPivot().Position
				local charPos = char.PrimaryPart.Position
				local origCFrame = targetModel:GetPivot()
				
				task.spawn(function()
					local shakeDir = (targetPos - charPos).Unit
					-- 2단계 흔들기로 반동 연출 (더욱 큰 피드백)
					targetModel:PivotTo(origCFrame * CFrame.new(shakeDir * 0.6))
					task.wait(0.04)
					targetModel:PivotTo(origCFrame * CFrame.new(-shakeDir * 0.2))
					task.wait(0.04)
					targetModel:PivotTo(origCFrame)
				end)
			end

			if targetType == "resource" then
				-- [개선] 노드 정보 미리 가져오기 (메시지용)
				local nodeType = targetModel:GetAttribute("NodeType")
				
				-- 자원 채집 처리
				local ok, errorOrData = NetClient.Request("Harvest.Hit.Request", {
					nodeUID = targetId,
					toolSlot = UIManager.getSelectedSlot(),
				})
				
				if not ok then
					local err = errorOrData
					if err == Enums.ErrorCode.NO_TOOL or err == Enums.ErrorCode.WRONG_TOOL then
						if nodeType == "TREE" then
							UIManager.notify("나무를 베려면 도끼를 장착해야 합니다!", Color3.fromRGB(255, 150, 50))
						elseif nodeType == "ROCK" or nodeType == "ORE" then
							UIManager.notify("채광을 하려면 곡괭이를 장착해야 합니다!", Color3.fromRGB(255, 150, 50))
						else
							UIManager.notify("이 작업을 하기에 적합한 도구가 아닙니다.", Color3.fromRGB(255, 100, 100))
						end
					elseif err == Enums.ErrorCode.INVALID_STATE then
						UIManager.notify("도구가 파손되어 기능을 상실했습니다!", Color3.fromRGB(255, 50, 50))
					elseif err == Enums.ErrorCode.OUT_OF_RANGE then
						UIManager.notify("대상과 너무 멉니다.", Color3.fromRGB(255, 100, 100))
					elseif err == Enums.ErrorCode.COOLDOWN then
						-- 쿨다운은 조용히 무시 (혹은 연출)
					else
						UIManager.notify("채집할 수 없는 상태입니다: " .. tostring(err), Color3.fromRGB(255, 100, 100))
					end
				end
			else
				-- 크리처 공격 처리
				local ok, errorOrData = NetClient.Request("Combat.Hit.Request", {
					targetId = targetId,
					toolSlot = UIManager.getSelectedSlot(),
				})
				
				if not ok then
					if errorOrData == Enums.ErrorCode.INVALID_STATE then
						UIManager.notify("무기가 파손되어 공격할 수 없습니다!", Color3.fromRGB(255, 50, 50))
					end
				end
			end
		end)
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
