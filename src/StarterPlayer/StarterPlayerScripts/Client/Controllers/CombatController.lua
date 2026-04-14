-- CombatController.lua
-- 클라이언트 전투 컨트롤러 (공격 요청, 애니메이션)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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
local itemDataTable = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))

-- 공격 쿨다운
local lastAttackTime = 0
local ATTACK_COOLDOWN = 0.5  -- 0.5초

-- 콤보 시스템
local currentComboIndex = 1
local comboResetTime = 1.0  -- 1초 내 다음 공격 안하면 콤보 리셋

-- 애니메이션 트랙
local currentAttackTrack = nil
local currentBowDrawTrack = nil
local currentBowDrawConn = nil
local bowDrawPassedHalf = false
local bowDrawReadyToFire = false
local bowDrawActive = false
local bowDrawStartedAt = 0
local bowDrawPressedHitPos: Vector3? = nil
local bowDrawPressedTargetCenter: Vector3? = nil
local bowPreviousAutoRotate: boolean? = nil
local bowPreviewLinePart: Part? = nil
local bowPreviewTipPart: Part? = nil
local bowPredictedOrigin: Vector3? = nil
local bowPredictedDirection: Vector3? = nil
local bowPredictedHitPos: Vector3? = nil
local bowPredictedChargeRatio = 0
local bowPredictedHeldSec = 0

-- 화살 비주얼 회전 보정
local ARROW_MODEL_ROTATION_OFFSET = CFrame.Angles(0, math.rad(-90), 0)
local BOW_DRAW_FRONT_SPEED = 0.85
local DEFAULT_MIN_AIM_TIME = 0.2
local DEFAULT_MAX_CHARGE_TIME = 1.2
local BOW_DRAW_HOLD_SPEED = 0.45
local BOW_DRAW_FRONT_RATIO = 0.45
local BOW_DRAW_END_EPSILON = 0.03
local BOW_PREVIEW_WIDTH = 0.06
local BOW_PREVIEW_MIN_DISTANCE = 0.2
local BOW_AIM_RAYCAST_DISTANCE = 1200
local BOW_GHOST_LINE_COLOR = Color3.fromRGB(218, 255, 210)
local BOW_GHOST_TIP_COLOR = Color3.fromRGB(232, 255, 226)
local BOW_AIM_SNAP_RADIUS = 8
local BOW_NOTIFY_COOLDOWN = 0.45
local BOW_AIM_VERTICAL_COMPENSATION = 0
local bowNoAmmoNotifyAt = 0
local bowIncompleteNotifyAt = 0
local ACTION_EFFECTS_ENABLED = true

-- 활 조준 카메라 줌
local AIM_ZOOM_FOV = 45
local AIM_ZOOM_TWEEN_IN = 0.18
local AIM_ZOOM_TWEEN_OUT = 0.18
local originalFOV: number? = nil
local isAimZoomed = false
local currentZoomTween: Tween? = nil

local function enterAimZoom()
	local cam = workspace.CurrentCamera
	if not cam or isAimZoomed then return end
	isAimZoomed = true
	originalFOV = cam.FieldOfView
	if currentZoomTween then currentZoomTween:Cancel() end
	currentZoomTween = TweenService:Create(cam, TweenInfo.new(AIM_ZOOM_TWEEN_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = AIM_ZOOM_FOV })
	currentZoomTween:Play()
end

local function exitAimZoom()
	if not isAimZoomed then return end
	isAimZoomed = false
	local cam = workspace.CurrentCamera
	if not cam then originalFOV = nil return end
	local restoreFOV = originalFOV or 70
	originalFOV = nil
	if currentZoomTween then currentZoomTween:Cancel() end
	currentZoomTween = TweenService:Create(cam, TweenInfo.new(AIM_ZOOM_TWEEN_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = restoreFOV })
	currentZoomTween:Play()
end

local ARROW_TRAIL_COLOR = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 180, 60))

local function getDominantAxis(size: Vector3): Vector3
	if size.X >= size.Y and size.X >= size.Z then
		return Vector3.new(1, 0, 0)
	elseif size.Y >= size.X and size.Y >= size.Z then
		return Vector3.new(0, 1, 0)
	end
	return Vector3.new(0, 0, 1)
end

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

local function getEquippedItemData()
	local selectedSlot = UIManager.getSelectedSlot and UIManager.getSelectedSlot() or nil
	if not selectedSlot then return nil end
	local InventoryController = require(Client.Controllers.InventoryController)
	local slotData = InventoryController.getSlot(selectedSlot)
	if not slotData or not slotData.itemId then return nil end
	for _, v in ipairs(itemDataTable) do
		if v.id == slotData.itemId then
			return v
		end
	end
	return nil
end

local function isBowWeapon(itemData, toolType: string?): boolean
	local upperTool = string.upper(tostring(toolType or ""))
	if upperTool:find("BOW", 1, true) then
		return true
	end
	if not itemData then return false end
	local itemId = string.upper(tostring(itemData.id or ""))
	if itemId:find("BOW", 1, true) then
		return true
	end
	local opt = string.upper(tostring(itemData.optimalTool or ""))
	return opt == "BOW" or opt == "CROSSBOW"
end

local function canBreakBlocksWithItem(itemData): boolean
	if type(itemData) ~= "table" then
		return false
	end
	local itemType = tostring(itemData.type or "")
	if itemType == "TOOL" then
		return true
	end
	if itemType ~= "WEAPON" then
		return false
	end
	local toolKind = string.upper(tostring(itemData.optimalTool or ""))
	return toolKind ~= "BOW" and toolKind ~= "CROSSBOW"
end

local function getBowMuzzleOrigin(): Vector3?
	local character = player.Character
	if not character then return nil end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle.Position
		end
	end

	local rightHand = character:FindFirstChild("RightHand")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand.Position
	end
	local rightArm = character:FindFirstChild("Right Arm")
	if rightArm and rightArm:IsA("BasePart") then
		return rightArm.Position
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position + Vector3.new(0, 1.35, 0)
	end
	return character:GetPivot().Position
end

local function getBowForwardDirection(): Vector3
	local character = player.Character
	if not character then
		return Vector3.new(0, 0, -1)
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local refForward = (hrp and hrp:IsA("BasePart") and hrp.CFrame.LookVector) or character:GetPivot().LookVector
	refForward = Vector3.new(refForward.X, 0, refForward.Z)
	if refForward.Magnitude <= 0.001 then
		refForward = Vector3.new(0, 0, -1)
	end
	refForward = refForward.Unit

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			local candidates = {
				handle.CFrame.LookVector,
				handle.CFrame.RightVector,
				handle.CFrame.UpVector,
				-handle.CFrame.LookVector,
				-handle.CFrame.RightVector,
				-handle.CFrame.UpVector,
			}
			local best = refForward
			local bestDot = -1
			for _, v in ipairs(candidates) do
				local u = v.Unit
				local d = refForward:Dot(u)
				if d > bestDot then
					bestDot = d
					best = u
				end
			end
			best = Vector3.new(best.X, 0, best.Z)
			if best.Magnitude <= 0.001 then
				return refForward
			end
			return best.Unit
		end
	end

	return refForward
end

local function resolveMouseTargetCenter(fallbackHitPos: Vector3?): Vector3?
	local target = InputManager.getMouseTarget()
	if target then
		local model = target:FindFirstAncestorWhichIsA("Model")
		if model and model ~= player.Character then
			return model:GetPivot().Position
		end
		if target:IsA("BasePart") then
			return target.Position
		end
	end
	return fallbackHitPos
end

local function notifyBowNoAmmo()
	local now = tick()
	if now - bowNoAmmoNotifyAt < BOW_NOTIFY_COOLDOWN then
		return
	end
	bowNoAmmoNotifyAt = now
	UIManager.notify("화살이 없습니다.", Color3.fromRGB(255, 150, 80))
end

local function notifyBowIncomplete()
	local now = tick()
	if now - bowIncompleteNotifyAt < BOW_NOTIFY_COOLDOWN then
		return
	end
	bowIncompleteNotifyAt = now
	UIManager.notify("조준이 완료되지 않았습니다.", Color3.fromRGB(255, 210, 120))
end

local function resolveNearbyAimSnap(basePos: Vector3, origin: Vector3): Vector3?
	local creaturesFolder = workspace:FindFirstChild("ActiveCreatures") or workspace:FindFirstChild("Creatures")
	if not creaturesFolder then
		return nil
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { creaturesFolder }
	local parts = workspace:GetPartBoundsInRadius(basePos, BOW_AIM_SNAP_RADIUS, overlap)

	local bestPos = nil
	local bestDist = math.huge
	for _, p in ipairs(parts) do
		local model = p:FindFirstAncestorWhichIsA("Model")
		if model and model:GetAttribute("InstanceId") then
			local pos = model:GetPivot().Position
			local d = (pos - basePos).Magnitude
			if d < bestDist and (pos - origin).Magnitude <= BOW_AIM_RAYCAST_DISTANCE then
				bestDist = d
				bestPos = pos
			end
		end
	end

	return bestPos
end

local function getMouseAimTarget(origin: Vector3): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	-- 마우스 레이로 월드 좌표를 구한다
	local _, camHitPos = InputManager.raycastFromMouse(nil, BOW_AIM_RAYCAST_DISTANCE)
	if not camHitPos then
		-- 레이가 월드에 안 맞으면 수평 전방으로 발사
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local fwd = hrp.CFrame.LookVector
				camHitPos = origin + Vector3.new(fwd.X, 0, fwd.Z).Unit * 80
			else
				camHitPos = origin + Vector3.new(0, 0, -80)
			end
		else
			camHitPos = origin + Vector3.new(0, 0, -80)
		end
	end

	-- 활 origin → 카메라 히트 포인트 방향으로 재투영 (3인칭 시차 보정)
	local aimDir = (camHitPos - origin)
	if aimDir.Magnitude < 0.001 then return camHitPos end
	aimDir = aimDir.Unit

	-- 상향 각도 제한: Y 성분 제한으로 위로 튐는 것 방지
	if aimDir.Y > 0.15 then
		aimDir = Vector3.new(aimDir.X, 0.15, aimDir.Z).Unit
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(origin, aimDir * BOW_AIM_RAYCAST_DISTANCE, rayParams)
	local finalPos = result and result.Position or (origin + aimDir * BOW_AIM_RAYCAST_DISTANCE)

	local snap = resolveNearbyAimSnap(finalPos, origin)
	if snap then
		return Vector3.new(snap.X, finalPos.Y, snap.Z)
	end
	return finalPos
end

local BOW_AMMO_TYPES = {"BRONZE_ARROW", "STONE_ARROW"}

local function getAmmoForWeapon(itemId: string?): string?
	local upper = string.upper(tostring(itemId or ""))
	if upper == "CROSSBOW" then return "IRON_BOLT" end
	return nil
end

local function hasRequiredBowAmmo(itm): boolean
	if not itm or not itm.id then
		return false
	end
	local isBow = string.upper(tostring(itm.optimalTool or "")) == "BOW"
	local ammoId = getAmmoForWeapon(itm.id)
	if not ammoId and not isBow then
		return true
	end
	-- NO_ARROW_CONSUME 패시브 체크
	local SkillController = require(Client.Controllers.SkillController)
	local unlocked = SkillController.getUnlockedSkills()
	local SkillTreeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("SkillTreeData"))
	for skillId in pairs(unlocked) do
		local skill = SkillTreeData.GetSkill(skillId)
		if skill and skill.effects then
			for _, eff in ipairs(skill.effects) do
				if eff.stat == "NO_ARROW_CONSUME" and eff.value > 0 then
					return true
				end
			end
		end
	end
	local InventoryController = require(Client.Controllers.InventoryController)
	local counts = InventoryController.getItemCounts and InventoryController.getItemCounts() or nil
	if not counts then
		return false
	end
	-- 석궩: 특정 탄약
	if ammoId then
		return (tonumber(counts[ammoId]) or 0) > 0
	end
	-- 활: 아무 화살이나 사용 가능
	for _, arrowId in ipairs(BOW_AMMO_TYPES) do
		if (tonumber(counts[arrowId]) or 0) > 0 then
			return true
		end
	end
	return false
end

local function getLiveBowAimDirection(origin: Vector3): Vector3
	local targetPos = getMouseAimTarget(origin)
	if targetPos then
		targetPos = targetPos + Vector3.new(0, BOW_AIM_VERTICAL_COMPENSATION, 0)
		local dir = targetPos - origin
		if dir.Magnitude > 0.001 then
			return dir.Unit
		end
	end
	return getBowForwardDirection()
end

local function orientCharacterToAim(direction: Vector3)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude <= 0.001 then return end
	flat = flat.Unit

	local pos = hrp.Position
	hrp.CFrame = CFrame.lookAt(pos, pos + flat)
end

local function clearBowPreview()
	if bowPreviewLinePart then
		bowPreviewLinePart:Destroy()
		bowPreviewLinePart = nil
	end
	if bowPreviewTipPart then
		bowPreviewTipPart:Destroy()
		bowPreviewTipPart = nil
	end
	bowPredictedOrigin = nil
	bowPredictedDirection = nil
	bowPredictedHitPos = nil
	bowPredictedChargeRatio = 0
	bowPredictedHeldSec = 0
end

local function hideBowPreviewVisuals()
	if bowPreviewTipPart then bowPreviewTipPart.Transparency = 1 end
end

local function ensureBowPreviewParts()
	if not bowPreviewTipPart then
		local tip = Instance.new("Part")
		tip.Name = "BowImpactMarker"
		tip.Shape = Enum.PartType.Cylinder
		tip.Anchored = true
		tip.CanCollide = false
		tip.CanQuery = false
		tip.CanTouch = false
		tip.Material = Enum.Material.Neon
		tip.Color = Color3.fromRGB(130, 210, 110)
		tip.Transparency = 0.4
		tip.Size = Vector3.new(0.08, 1.2, 1.2)
		tip.Parent = workspace.CurrentCamera
		bowPreviewTipPart = tip
	end
end

local function updateBowPreview(itm)
	if not bowDrawActive then
		clearBowPreview()
		return
	end

	local origin = getBowMuzzleOrigin()
	if not origin then
		clearBowPreview()
		return
	end
	local direction = getLiveBowAimDirection(origin)
	orientCharacterToAim(direction)
	local heldSec = math.max(0, tick() - bowDrawStartedAt)
	local minAimTime = math.max(0.05, tonumber(itm and itm.minAimTime) or DEFAULT_MIN_AIM_TIME)
	local maxChargeTime = math.max(minAimTime + 0.1, tonumber(itm and itm.maxChargeTime) or DEFAULT_MAX_CHARGE_TIME)
	local chargeRatio = math.clamp((heldSec - minAimTime) / (maxChargeTime - minAimTime), 0, 1)
	local maxRange = tonumber(itm and (itm.maxRange or itm.range)) or 120
	local minRange = math.max(8, tonumber(itm and itm.minRange) or math.floor(maxRange * 0.25))
	local effectiveRange = minRange + ((maxRange - minRange) * chargeRatio)

	local aimTarget = getMouseAimTarget(origin)
	local hitPos = nil
	if aimTarget then
		local toAim = aimTarget - origin
		if toAim.Magnitude > 0.001 then
			if toAim.Magnitude > effectiveRange then
				hitPos = origin + (toAim.Unit * effectiveRange)
			else
				hitPos = aimTarget
			end
		end
	end
	if not hitPos then
		hitPos = origin + (direction * effectiveRange)
	end

	direction = (hitPos - origin).Magnitude > 0.001 and (hitPos - origin).Unit or direction

	bowPredictedOrigin = origin
	bowPredictedDirection = direction
	bowPredictedHitPos = hitPos
	bowPredictedChargeRatio = chargeRatio
	bowPredictedHeldSec = math.min(heldSec, maxChargeTime)

	-- 요구사항: DRAW 애니메이션이 완료되기 전에는 조준선을 표시하지 않는다.
	if not bowDrawReadyToFire then
		hideBowPreviewVisuals()
		return
	end

	ensureBowPreviewParts()

	-- 타격 지점 마커 갱신 (카메라를 향하는 원형 마커)
	if bowPreviewTipPart then
		local cam = workspace.CurrentCamera
		if cam then
			-- 카메라→타격지점 방향으로 Cylinder 축(X)을 정렬 → 정면에서 원형으로 보임
			bowPreviewTipPart.CFrame = CFrame.lookAt(hitPos, cam.CFrame.Position) * CFrame.Angles(0, math.rad(90), 0)
		end
		bowPreviewTipPart.Transparency = 0.4
	end
end

local playAttackAnimation
local spawnArrowTracer

--- 좌클릭 즉시 활 발사 (조준 시스템 없음)
local function fireBowInstant(clickHitPos: Vector3?)
	if InputManager.isUIOpen() then return end

	local itm = getEquippedItemData()
	if not isBowWeapon(itm, getEquippedToolType()) then return end

	-- 쿨다운
	local dynamicCooldown = (itm and itm.attackSpeed) or ATTACK_COOLDOWN
	local now = tick()
	if now - lastAttackTime < dynamicCooldown then return end
	lastAttackTime = now

	-- 탄약 체크
	if not hasRequiredBowAmmo(itm) then
		notifyBowNoAmmo()
		return
	end

	local origin = getBowMuzzleOrigin()
	if not origin then return end

	-- 클릭 위치 → 발사 방향 계산
	local direction
	if clickHitPos then
		local dir = clickHitPos - origin
		if dir.Magnitude > 0.5 then
			direction = dir.Unit
		end
	end
	if not direction then
		-- 클릭 위치가 없으면 마우스 레이캐스트
		local _, mouseHit = InputManager.raycastFromMouse(nil, BOW_AIM_RAYCAST_DISTANCE)
		if mouseHit then
			local dir = mouseHit - origin
			if dir.Magnitude > 0.5 then
				direction = dir.Unit
			end
		end
	end
	if not direction then
		direction = getBowForwardDirection()
	end

	-- 캐릭터를 발사 방향으로 회전
	orientCharacterToAim(direction)

	-- 사거리 계산 (충전 없으므로 최대 사거리)
	local maxRange = tonumber(itm and (itm.maxRange or itm.range)) or 120
	local chargeRatio = 1.0
	local heldSec = 1.0

	-- 발사 애니메이션
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid and AnimationIds.ATTACK_BOW and AnimationIds.ATTACK_BOW.DRAW then
		local track = AnimationManager.play(humanoid, AnimationIds.ATTACK_BOW.DRAW, 0.05)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			track:AdjustSpeed(2.0) -- 빠르게 재생
		end
	end

	-- 발사 효과음 (BOW_A1 강사 스킬과 동일)
	do
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local skillSounds = assets and assets:FindFirstChild("SkillSounds")
		local castFolder = skillSounds and skillSounds:FindFirstChild("Cast")
		local castSnd = castFolder and castFolder:FindFirstChild("SkillBow_Power_Cast")
		if castSnd and character then
			local hrpSnd = character:FindFirstChild("HumanoidRootPart")
			if hrpSnd then
				local sfx = castSnd:Clone()
				sfx.Volume = (sfx.Volume or 0.5) * 0.3
				sfx.Parent = hrpSnd
				sfx:Play()
				sfx.Ended:Once(function()
					if sfx and sfx.Parent then sfx:Destroy() end
				end)
			end
		end
	end

	-- 착탄점 계산
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { player.Character }
	local rayResult = workspace:Raycast(origin, direction * maxRange, rayParams)
	local aimHitPos = rayResult and rayResult.Position or (origin + direction * maxRange)

	-- 서버에 발사 요청
	local ok, errorOrData = NetClient.Request("Combat.Hit.Request", {
		targetId = nil,
		toolSlot = UIManager.getSelectedSlot(),
		bowShot = true,
		chargeRatio = chargeRatio,
		aimDirection = { x = direction.X, y = direction.Y, z = direction.Z },
		aimOrigin = { x = origin.X, y = origin.Y, z = origin.Z },
		heldSec = heldSec,
	})

	if not ok then
		if errorOrData == Enums.ErrorCode.MISSING_REQUIREMENTS then
			notifyBowNoAmmo()
		end
		return
	end

	-- 화살 비주얼
	spawnArrowTracer(aimHitPos, origin, direction, nil)
end

-- 안전 클리어 (구 조준 시스템 잔여 상태 정리용)
local function cleanupBowState()
	bowDrawActive = false
	bowDrawReadyToFire = false
	if currentBowDrawConn then
		currentBowDrawConn:Disconnect()
		currentBowDrawConn = nil
	end
	clearBowPreview()
	exitAimZoom()
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
	bowPreviousAutoRotate = nil
	bowDrawStartedAt = 0
	bowDrawPressedHitPos = nil
	bowDrawPressedTargetCenter = nil
end

spawnArrowTracer = function(targetPos: Vector3?, startPos: Vector3?, directionOverride: Vector3?, onArrived: (() -> ())?)
	if not ACTION_EFFECTS_ENABLED then
		if onArrived then onArrived() end
		return
	end
	if not targetPos then return end
	if not startPos then
		local camera = workspace.CurrentCamera
		if camera then
			startPos = camera.CFrame.Position
		else
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			startPos = hrp.Position + Vector3.new(0, 1.45, 0)
		end
	end

	local direction = directionOverride
	if not direction or direction.Magnitude < 0.001 then
		direction = targetPos - startPos
	end
	if direction.Magnitude < 0.001 then
		direction = Vector3.new(0, 0, -1)
	end
	direction = direction.Unit

	local distance = (targetPos - startPos).Magnitude
	local travel = math.clamp(distance / 42, 0.55, 1.9)
	local finalPos = startPos + (direction * distance)

	local visual: Instance? = nil
	local isModelVisual = false
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local itemModels = assets and (assets:FindFirstChild("ItemModels") or assets:FindFirstChild("Models"))
	local template = itemModels and (itemModels:FindFirstChild("ARROW_PROJECTILE") or itemModels:FindFirstChild("ArrowProjectile") or itemModels:FindFirstChild("ARROW"))

	if template and (template:IsA("Model") or template:IsA("BasePart") or template:IsA("MeshPart")) then
		visual = template:Clone()
		if visual:IsA("Model") then
			isModelVisual = true
			for _, d in ipairs(visual:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Size = d.Size * 2
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			-- 초기 위치를 즉시 startPos로 설정 (템플릿 원점=땅바닥 방지)
			local initCf = CFrame.lookAt(startPos, startPos + direction)
			visual:PivotTo(initCf * ARROW_MODEL_ROTATION_OFFSET)
		elseif visual:IsA("BasePart") then
			visual.Size = visual.Size * 2
			visual.Anchored = true
			visual.CanCollide = false
			visual.CanQuery = false
			visual.CanTouch = false
			visual.CFrame = CFrame.lookAt(startPos, startPos + direction) * ARROW_MODEL_ROTATION_OFFSET
		end
		visual.Parent = workspace
	else
		local part = Instance.new("Part")
		part.Name = "ArrowTracer"
		part.Size = Vector3.new(0.3, 0.3, 2.8)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(245, 215, 120)
		part.CFrame = CFrame.lookAt(startPos, startPos + direction)
		part.Parent = workspace
		visual = part
	end

	-- 화살에 Trail 효과 부착
	local arrowTrailPart = nil
	if visual then
		if visual:IsA("Model") then
			arrowTrailPart = visual:FindFirstChildWhichIsA("BasePart")
		elseif visual:IsA("BasePart") then
			arrowTrailPart = visual
		end
	end
	if arrowTrailPart then
		local dominantAxis = getDominantAxis(arrowTrailPart.Size)
		local halfLen = math.max(arrowTrailPart.Size.X, arrowTrailPart.Size.Y, arrowTrailPart.Size.Z) * 0.5
		local arrowTrailLife = math.clamp(travel * 0.18, 0.12, 0.24)
		local at0 = Instance.new("Attachment")
		at0.Name = "ArrowTrailA0"
		at0.Position = dominantAxis * halfLen
		at0.Parent = arrowTrailPart

		local at1 = Instance.new("Attachment")
		at1.Name = "ArrowTrailA1"
		at1.Position = -dominantAxis * halfLen
		at1.Parent = arrowTrailPart

		local arrowTrail = Instance.new("Trail")
		arrowTrail.Name = "ArrowTrail"
		arrowTrail.Attachment0 = at0
		arrowTrail.Attachment1 = at1
		arrowTrail.Color = ARROW_TRAIL_COLOR
		arrowTrail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.45, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		arrowTrail.Lifetime = arrowTrailLife
		arrowTrail.MinLength = 0.02
		arrowTrail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		arrowTrail.FaceCamera = false
		arrowTrail.LightEmission = 0.5
		arrowTrail.LightInfluence = 0.5
		arrowTrail.Enabled = true
		arrowTrail.Parent = arrowTrailPart
	end

	task.spawn(function()
		local t0 = tick()
		while true do
			local alpha = math.clamp((tick() - t0) / travel, 0, 1)
			local pos = startPos:Lerp(finalPos, alpha)
			if visual then
				local cf = CFrame.lookAt(pos, pos + direction)
				if isModelVisual and visual:IsA("Model") then
					visual:PivotTo(cf * ARROW_MODEL_ROTATION_OFFSET)
				elseif visual:IsA("BasePart") then
					visual.CFrame = cf * ARROW_MODEL_ROTATION_OFFSET
				end
			end
			if alpha >= 1 then break end
			task.wait()
		end
		if onArrived then onArrived() end

		if visual and visual.Parent then
			visual:Destroy()
		end
	end)
end

--- 공격 애니메이션 재생
playAttackAnimation = function(isHit: boolean)
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
		animNames = { AnimationIds.ATTACK_SWORD.SWING }
	elseif toolType == "PICKAXE" then
		animNames = { "AttackTool_Mine" }
	elseif toolType == "SWORD" then
		animNames = { AnimationIds.ATTACK_SWORD.SWING }
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
	
	-- 애니메이션 재생
	local track = AnimationManager.play(humanoid, animName, 0.05, nil, isHit and 1.2 or 1.0)
	if track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
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
	if not ACTION_EFFECTS_ENABLED then
		return
	end
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
			cam.CFrame = originalCF * CFrame.new(offset)
			task.wait(0.02)
		end
		cam.CFrame = originalCF
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
	local equippedItem = getEquippedItemData()
	local reach = Balance.REACH_BAREHAND or 10
	if toolType == "SWORD" then
		reach = Balance.REACH_SWORD or 16
	elseif toolType == "AXE" or toolType == "PICKAXE" or toolType == "CLUB" then
		reach = Balance.REACH_TOOL or 12
	end
	if equippedItem and equippedItem.range then
		reach = math.max(reach, equippedItem.range)
	elseif isBowWeapon(equippedItem, toolType) then
		reach = math.max(reach, 120)
	end

	-- 1. 캐릭터 주변 엔티티 탐색 (Sphere) — 건축물(Facilities)은 공격 대상에서 제외
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local filterInstances = {}
	if creaturesFolder then table.insert(filterInstances, creaturesFolder) end
	if nodesFolder then table.insert(filterInstances, nodesFolder) end
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
			-- ★ XZ 평면 거리 사용 (큰 공룡의 높이 차이로 인한 히트 실패 방지)
			local flatDist = Vector2.new(toTarget.X, toTarget.Z).Magnitude
			
			-- 현재 모델에 대해 더 가까운 파트가 있으면 갱신
			if not reachableTargets[id] or flatDist < reachableTargets[id].dist then
				-- Y축 무시한 방향 벡터 (평면 판정)
				local toTargetFlat = Vector3.new(toTarget.X, 0, toTarget.Z)
				if toTargetFlat.Magnitude < 0.01 then toTargetFlat = Vector3.new(0, 0, 1) end
				toTargetFlat = toTargetFlat.Unit
				local lookFlat = Vector3.new(char.PrimaryPart.CFrame.LookVector.X, 0, char.PrimaryPart.CFrame.LookVector.Z).Unit
				local dot = lookFlat:Dot(toTargetFlat)
				local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
				
				-- ★ 초근접 사각지대 방지: 거리가 리치의 30% 이내(또는 3스터드)이면
				-- 대형 공룡 다리 사이 등에서 각도 왜곡이 극심하므로 각도 검증 생략
				local closeThreshold = math.max(reach * 0.3, 3)
				local angleOk = flatDist <= closeThreshold or angle <= (Balance.REACH_ANGLE or 75)
				
				-- 사거리 이내 & (초근접 or 정면 부근)인 것들만 수집
				if flatDist <= reach + 5 and angleOk then
					reachableTargets[id] = {model=model, pos=targetPos, id=id, type=tType, dist=flatDist, angle=angle}
				end
			end
		end
	end

	-- 2. 타겟 우선순위 결정
	-- [우선순위 1] 마우스가 가리키는 대상 (에임)
	local mousePart = InputManager.getMouseTarget()
	if mousePart then
		local mModel, mId, mType = checkModel(mousePart)
		if mId and mType ~= "structure" then
			local mPos = mousePart.Position
			-- ★ XZ 평면 거리 사용 (머리/꼬리 등 높은 파트도 타격 가능)
			local mToTarget = mPos - char.PrimaryPart.Position
			local mDist = Vector2.new(mToTarget.X, mToTarget.Z).Magnitude
			
			-- 마우스로 직접 찍은 경우 정면 판정 완화 (히트박스 우선)
			if mDist <= reach + 8 then
				if mType ~= "creature" then
					local nearestCreature = nil
					local nearestDist = math.huge
					for _, data in pairs(reachableTargets) do
						if data.type == "creature" and data.dist < nearestDist then
							nearestDist = data.dist
							nearestCreature = data
						end
					end
					if nearestCreature then
						return nearestCreature.model, nearestCreature.pos, nearestCreature.id, nearestCreature.type
					end
				end
				return mModel, mPos, mId, mType
			end
		end
	end

	-- [우선순위 2] 정면에서 가장 가깝거나 점수가 높은 대상
	local bestCreature = nil
	local bestCreatureScore = math.huge
	local bestOther = nil
	local bestOtherScore = math.huge
	
	for id, data in pairs(reachableTargets) do
		local score = data.dist * (1 + data.angle / 45)
		if data.type == "creature" then
			if score < bestCreatureScore then
				bestCreatureScore = score
				bestCreature = data
			end
		else
			if score < bestOtherScore then
				bestOtherScore = score
				bestOther = data
			end
		end
	end

	if bestCreature then
		return bestCreature.model, bestCreature.pos, bestCreature.id, bestCreature.type
	end

	if bestOther then
		return bestOther.model, bestOther.pos, bestOther.id, bestOther.type
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
function CombatController.attack(attackMeta)
	attackMeta = attackMeta or {}
	-- UI가 열려있으면 무시
	if InputManager.isUIOpen() then
		return
	end
	
	-- 1. 선택된 슬롯 및 아이템 데이터 가져오기 (쿨다운, 음식 섭취, 사거리 등)
	local selectedSlot = UIManager.getSelectedSlot()
	local InventoryController = require(Client.Controllers.InventoryController)
	local slotData = InventoryController.getSlot(selectedSlot)
	local itm = getEquippedItemData()
	local isBow = isBowWeapon(itm, getEquippedToolType())
	
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

	if isBow then
		-- 활은 홀드-릴리즈 입력 경로에서만 발사한다.
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
		if toolType == "SWORD" then
			reach = Balance.REACH_SWORD or 16
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
		elseif toolType == "SWORD" then
			windupTime = 0.2
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

			-- [FX] 타격 피드백 (카메라 쉐이크 & Highlight 플래시)
			playHitShake(0.5) -- 더욱 강한 쉐이크 (기존 0.3)
			-- ★ PivotTo 제거: 서버 소유(SetNetworkOwner(nil)) 크리처를 클라이언트에서
			-- 움직이면 서버 물리 롤백으로 극심한 떨림(Rubberbanding)이 발생하므로
			-- Highlight 플래시로 대체하여 물리 간섭 없이 시각적 피드백 제공
			if ACTION_EFFECTS_ENABLED and targetType ~= "structure" and targetModel then
				task.spawn(function()
					local highlight = Instance.new("Highlight")
					highlight.Name = "HitFlash"
					highlight.FillColor = Color3.fromRGB(255, 255, 255)
					highlight.OutlineColor = Color3.fromRGB(255, 200, 100)
					highlight.FillTransparency = 0.7
					highlight.OutlineTransparency = 0
					highlight.DepthMode = Enum.HighlightDepthMode.Occluded
					highlight.Adornee = targetModel
					highlight.Parent = targetModel
					task.wait(0.08)
					highlight:Destroy()
				end)
			end

			if targetType == "resource" then
				-- 채집은 R키 UI로 전환됨 — 좌클릭은 무시
			else
				-- 크리처 공격 처리
				local ok, errorOrData = NetClient.Request("Combat.Hit.Request", {
					targetId = targetId,
					toolSlot = UIManager.getSelectedSlot(),
				})
				
				if not ok then
					if errorOrData == Enums.ErrorCode.INVALID_STATE then
						UIManager.notify("무기가 파손되어 공격할 수 없습니다!", Color3.fromRGB(255, 50, 50))
					elseif errorOrData == Enums.ErrorCode.ALREADY_IN_COMBAT then
						UIManager.notify("이미 다른 대상과 전투 중입니다!", Color3.fromRGB(255, 150, 50))
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

-- Combat Engagement Indicator (전투 교전 표시 아이콘)
local engagementIndicators = {} -- [instanceId] = BillboardGui

local function findCreatureModel(instanceId: string): Model?
	local folder = workspace:FindFirstChild("Creatures")
	if not folder then return nil end
	for _, model in ipairs(folder:GetChildren()) do
		if model:GetAttribute("InstanceId") == instanceId then
			return model
		end
	end
	return nil
end

local function createEngagementIndicator(instanceId: string)
	if engagementIndicators[instanceId] then return end
	local model = findCreatureModel(instanceId)
	if not model then return end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CombatIndicator"
	billboard.Size = UDim2.new(0, 32, 0, 32)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = root
	billboard.MaxDistance = 80

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://129366828374431" -- TODO: 실제 칼 아이콘 에셋 ID 교체 필요
	icon.ImageColor3 = Color3.fromRGB(255, 60, 60)
	icon.Parent = billboard

	billboard.Parent = root
	engagementIndicators[instanceId] = billboard
end

local function removeEngagementIndicator(instanceId: string)
	local gui = engagementIndicators[instanceId]
	if gui then
		gui:Destroy()
		engagementIndicators[instanceId] = nil
	end
end

function CombatController.Init()
	if initialized then
		warn("[CombatController] Already initialized!")
		return
	end
	
	-- 좌클릭 = 공격
	InputManager.onLeftClick("CombatAttack", function(hitPos)
		local itm = getEquippedItemData()
		if isBowWeapon(itm, getEquippedToolType()) then
			fireBowInstant(hitPos)
			return
		end

		local BlockBuildController = require(Client.Controllers.BlockBuildController)
		local hoveredBlockId = BlockBuildController.getHoveredBlockId and BlockBuildController.getHoveredBlockId() or nil
		if hoveredBlockId and canBreakBlocksWithItem(itm) then
			local ok, err = NetClient.Request("BlockBuild.Remove.Request", {
				blockId = hoveredBlockId,
			})
			if not ok then
				UIManager.notify(BlockBuildController.getFriendlyError(err), Color3.fromRGB(255, 100, 100))
			end
			return
		end

		CombatController.attack()
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			cleanupBowState()
		end
	end)

	UserInputService.WindowFocusReleased:Connect(function()
		cleanupBowState()
	end)

	player.CharacterAdded:Connect(function()
		cleanupBowState()
		-- 리스폰 시 FOV 즉시 복귀
		if isAimZoomed then
			isAimZoomed = false
			if currentZoomTween then currentZoomTween:Cancel() end
			currentZoomTween = nil
			local cam = workspace.CurrentCamera
			if cam then cam.FieldOfView = originalFOV or 70 end
			originalFOV = nil
		end
	end)

	-- 전투 교전 표시 아이콘 수신
	NetClient.On("Combat.Engagement.Changed", function(data)
		if data.inCombat then
			createEngagementIndicator(data.instanceId)
		else
			removeEngagementIndicator(data.instanceId)
		end
	end)
	
	initialized = true
	print("[CombatController] Initialized")
end

--- 현재 정면의 가장 가까운 크리처 instanceId 반환 (액티브 스킬 타겟팅용)
function CombatController.getCurrentTarget(): string?
	local char = player.Character
	if not char or not char.PrimaryPart then return nil end
	
	local creaturesFolder = workspace:FindFirstChild("ActiveCreatures") or workspace:FindFirstChild("Creatures")
	if not creaturesFolder then return nil end
	
	local hrp = char.PrimaryPart
	local lookFlat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if lookFlat.Magnitude > 0.01 then lookFlat = lookFlat.Unit end
	
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { creaturesFolder }
	
	-- 활/섛보 장착 시 스킬 사거리 확장
	local toolType = getEquippedToolType()
	local scanRadius = 20
	if toolType == "BOW" or toolType == "CROSSBOW" then
		scanRadius = 120
	end
	local parts = workspace:GetPartBoundsInRadius(hrp.Position, scanRadius, overlap)
	
	local bestId = nil
	local bestDist = math.huge
	local seen = {}
	
	for _, p in ipairs(parts) do
		local current = p
		while current and current ~= workspace do
			if current:IsA("Model") then
				local instanceId = current:GetAttribute("InstanceId")
				if instanceId and not seen[instanceId] then
					seen[instanceId] = true
					local dist = (p.Position - hrp.Position).Magnitude
					local toTarget = Vector3.new(p.Position.X - hrp.Position.X, 0, p.Position.Z - hrp.Position.Z)
					if toTarget.Magnitude > 0.01 then
						local dot = lookFlat:Dot(toTarget.Unit)
						if dot > 0.3 and dist < bestDist then
							bestDist = dist
							bestId = instanceId
						end
					end
				end
				break
			end
			current = current.Parent
		end
	end
	
	return bestId
end

--- 화살 트레이서 공개 API (스킬 이펙트에서 호출용)
function CombatController.fireArrowTracer(targetPos, startPos, direction)
	spawnArrowTracer(targetPos, startPos, direction, nil)
end

return CombatController
