-- AttackIndicatorController.lua
-- 크리처 공격 범위 3D 볼륨 표시기
-- Part 기반 반투명 Neon 볼륨으로 공격 범위를 시각화
-- telegraph(패턴) 공격 + 레거시(즉시) 공격 모두 지원

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local AttackIndicatorController = {}

--========================================
-- Constants
--========================================
local VOLUME_HEIGHT = 3                          -- 볼륨 높이 (studs)
local VOLUME_TRANSPARENCY = 0.85                 -- 기본 투명도 (높을수록 투명)
local VOLUME_COLOR = Color3.fromRGB(255, 80, 80) -- 위험 영역 빨간색 (연한 톤)
local FLASH_SPEED = 4.0                          -- 깜빡임 속도
local INDICATOR_OVERSIZE = 1.0                   -- 판정 범위와 정확히 일치
local FADE_IN_TIME = 0.08                        -- 페이드인 시간 (짧게)
local FADE_OUT_TIME = 0.15                       -- 페이드아웃 시간

-- Active indicators: [instanceId] = { model: Model, conn: RBXScriptConnection? }
local activeIndicators = {}

-- Workspace 인디케이터 폴더
local indicatorFolder = Instance.new("Folder")
indicatorFolder.Name = "AttackIndicators"
indicatorFolder.Parent = Workspace

--========================================
-- Utility
--========================================

--- 모델 내부에서 Head 본/파트를 재귀적으로 찾는 함수
local function findHeadPart(model: Model): BasePart?
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^Head") then
			return desc
		end
	end
	return nil
end

--- instanceId로 Workspace 내 크리처 모델 검색
local function findCreatureModel(instanceId: string): Model?
	local folder = Workspace:FindFirstChild("Creatures")
	if not folder then return nil end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("InstanceId") == instanceId then
			return child
		end
	end
	return nil
end

--- 지면 높이를 Raycast로 구함 (Terrain만 대상)
local function getGroundY(pos: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local result = Workspace:Raycast(
		Vector3.new(pos.X, pos.Y + 50, pos.Z),
		Vector3.new(0, -100, 0),
		params
	)
	return result and result.Position.Y or pos.Y
end

--========================================
-- 3D Volume Part Creation
--========================================

--- 반투명 Neon Part 생성 (공통)
local function createVolumePart(size: Vector3, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "AttackVolume"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = VOLUME_COLOR
	part.Transparency = 1 -- 시작 시 투명 (페이드인)
	part.Size = size
	part.CFrame = cf
	return part
end

--- CONE (부채꼴) → 박스로 근사
local function createConeVolume(origin: Vector3, lookVector: Vector3, range: number, angleDeg: number): Model
	local model = Instance.new("Model")
	model.Name = "ConeVolume"

	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	flatLook = flatLook.Unit

	local halfAngleRad = math.rad(angleDeg / 2)
	local width = range * math.sin(halfAngleRad) * 2

	local groundY = getGroundY(origin)
	local center = Vector3.new(origin.X, groundY + VOLUME_HEIGHT / 2, origin.Z) + flatLook * (range / 2)
	local cf = CFrame.lookAt(center, center + flatLook)

	local part = createVolumePart(Vector3.new(width, VOLUME_HEIGHT, range), cf)
	part.Parent = model

	return model
end

--- CIRCLE (원형) → 실린더
local function createCircleVolume(origin: Vector3, radius: number): Model
	local model = Instance.new("Model")
	model.Name = "CircleVolume"

	local groundY = getGroundY(origin)
	local center = Vector3.new(origin.X, groundY + VOLUME_HEIGHT / 2, origin.Z)

	-- Cylinder: X축이 원통 축 → Z축 90° 회전으로 수직 원통
	local cf = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	local part = createVolumePart(Vector3.new(VOLUME_HEIGHT, radius * 2, radius * 2), cf)
	part.Shape = Enum.PartType.Cylinder
	part.Parent = model

	return model
end

--- CHARGE (돌진) → 직사각형 박스
local function createChargeVolume(origin: Vector3, lookVector: Vector3, width: number, length: number): Model
	local model = Instance.new("Model")
	model.Name = "ChargeVolume"

	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	flatLook = flatLook.Unit

	local groundY = getGroundY(origin)
	local center = Vector3.new(origin.X, groundY + VOLUME_HEIGHT / 2, origin.Z) + flatLook * (length / 2)
	local cf = CFrame.lookAt(center, center + flatLook)

	local part = createVolumePart(Vector3.new(width, VOLUME_HEIGHT, length), cf)
	part.Parent = model

	return model
end

--- PROJECTILE (투사체 착탄) → 실린더
local function createProjectileVolume(targetPos: Vector3, impactRadius: number): Model
	local model = Instance.new("Model")
	model.Name = "ProjectileVolume"

	local groundY = getGroundY(targetPos)
	local center = Vector3.new(targetPos.X, groundY + VOLUME_HEIGHT / 2, targetPos.Z)

	local cf = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	local part = createVolumePart(Vector3.new(VOLUME_HEIGHT, impactRadius * 2, impactRadius * 2), cf)
	part.Shape = Enum.PartType.Cylinder
	part.Parent = model

	return model
end

--========================================
-- Flash & Lifecycle
--========================================

--- 깜빡임 효과 (Part.Transparency 조작)
local function startFlashEffect(model: Model, windupTime: number, attackTime: number): RBXScriptConnection
	local startTime = tick()
	local totalTime = windupTime + attackTime

	-- 페이드인
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			TweenService:Create(desc, TweenInfo.new(FADE_IN_TIME), {
				Transparency = VOLUME_TRANSPARENCY
			}):Play()
		end
	end

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not model or not model.Parent then
			if conn then conn:Disconnect() end
			return
		end

		local elapsed = tick() - startTime
		if elapsed > totalTime then
			if conn then conn:Disconnect() end
			return
		end

		-- 선행 구간: 느린 깜빡임 / 공격 구간: 빠른 깜빡임
		local isAttackPhase = elapsed > windupTime
		local speed = isAttackPhase and (FLASH_SPEED * 2.5) or FLASH_SPEED
		local pulse = 0.5 + 0.5 * math.sin(elapsed * speed * math.pi * 2)

		-- 공격 구간에서 더 불투명 (더 강하게 표시)
		local baseTransparency = isAttackPhase and 0.65 or VOLUME_TRANSPARENCY
		local flashTransparency = baseTransparency + pulse * 0.08

		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = math.clamp(flashTransparency, 0.6, 0.95)
			end
		end
	end)

	return conn
end

--- 인디케이터 정리 (페이드아웃 + 제거)
local function clearIndicator(instanceId: string)
	local indicator = activeIndicators[instanceId]
	if not indicator then return end

	if indicator.conn then indicator.conn:Disconnect() end
	if indicator.model and indicator.model.Parent then
		for _, desc in ipairs(indicator.model:GetDescendants()) do
			if desc:IsA("BasePart") then
				TweenService:Create(desc, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1
				}):Play()
			end
		end
		task.delay(FADE_OUT_TIME + 0.05, function()
			if indicator.model and indicator.model.Parent then
				indicator.model:Destroy()
			end
		end)
	end
	activeIndicators[instanceId] = nil
end

--========================================
-- Show Indicators
--========================================

--- 텔레그래프(패턴) 공격 범위 표시 — 크리처 발광(flashLeadTime)과 동기화
local function showTelegraphIndicator(instanceId: string, data: any)
	clearIndicator(instanceId)

	local pattern = data.pattern or "CONE"
	local creaturePos = Vector3.new(data.creaturePos[1], data.creaturePos[2], data.creaturePos[3])
	local creatureLook = Vector3.new(data.creatureLook[1], data.creatureLook[2], data.creatureLook[3])
	local targetPos = Vector3.new(data.targetPos[1], data.targetPos[2], data.targetPos[3])
	local windupTime = data.windupTime or 0.5
	local attackTime = data.attackTime or 0.5

	-- ★ 발광 타이밍 계산 (CreatureAnimationController와 동일)
	local flashLeadTime = math.min(0.5, windupTime * 0.8)
	local delayBeforeShow = math.max(0, windupTime - flashLeadTime)

	-- 지연 후 볼륨 표시 (발광과 동시에 나타남)
	task.delay(delayBeforeShow, function()
		-- 이미 다른 인디케이터가 등록되었으면 무시
		if activeIndicators[instanceId] then return end

		-- 실시간 크리처 위치 반영
		local creatureModel = findCreatureModel(instanceId)
		if creatureModel then
			local hrp = creatureModel:FindFirstChild("HumanoidRootPart")
			if hrp then
				creaturePos = hrp.Position
				creatureLook = hrp.CFrame.LookVector
			end
		end

		-- CONE 패턴: Head 위치를 시작점으로
		local indicatorOrigin = creaturePos
		if pattern == "CONE" and creatureModel then
			local headPart = findHeadPart(creatureModel)
			if headPart then
				indicatorOrigin = headPart.Position
			end
		end

		-- 패턴별 3D 볼륨 생성
		local indicatorModel
		if pattern == "CONE" then
			local visRange = (data.range or 10) * INDICATOR_OVERSIZE
			local visAngle = (data.angle or 60) * INDICATOR_OVERSIZE
			indicatorModel = createConeVolume(indicatorOrigin, creatureLook, visRange, visAngle)
		elseif pattern == "CIRCLE" then
			local visRadius = (data.radius or 10) * INDICATOR_OVERSIZE
			indicatorModel = createCircleVolume(creaturePos, visRadius)
		elseif pattern == "CHARGE" then
			local visWidth = (data.width or 6) * INDICATOR_OVERSIZE
			local visLength = (data.length or 20) * INDICATOR_OVERSIZE
			indicatorModel = createChargeVolume(creaturePos, creatureLook, visWidth, visLength)
		elseif pattern == "PROJECTILE" then
			local visRadius = (data.impactRadius or 5) * INDICATOR_OVERSIZE
			indicatorModel = createProjectileVolume(targetPos, visRadius)
		else
			local visRange = (data.range or 10) * INDICATOR_OVERSIZE
			local visAngle = (data.angle or 60) * INDICATOR_OVERSIZE
			indicatorModel = createConeVolume(indicatorOrigin, creatureLook, visRange, visAngle)
		end

		indicatorModel.Parent = indicatorFolder

		-- ★ flashLeadTime 동안만 깜빡임 (windup 0 + attack = flashLeadTime)
		local flashConn = startFlashEffect(indicatorModel, 0, flashLeadTime)

		activeIndicators[instanceId] = {
			model = indicatorModel,
			conn = flashConn,
		}

		-- ★ flashLeadTime 후 자동 제거 (발광 끝나면 즉시 사라짐)
		task.delay(flashLeadTime + 0.1, function()
			clearIndicator(instanceId)
		end)
	end)
end

--- 레거시(기본) 공격 범위 표시 — attackRange 기반 원형
local function showBasicIndicator(instanceId: string, data: any)
	clearIndicator(instanceId)

	local attackRange = data.attackRange
	if not attackRange then return end

	local creaturePos = Vector3.new(data.creaturePos[1], data.creaturePos[2], data.creaturePos[3])

	-- 실시간 위치 반영
	local creatureModel = findCreatureModel(instanceId)
	if creatureModel then
		local hrp = creatureModel:FindFirstChild("HumanoidRootPart")
		if hrp then
			creaturePos = hrp.Position
		end
	end

	local visRange = attackRange * INDICATOR_OVERSIZE
	local indicatorModel = createCircleVolume(creaturePos, visRange)
	indicatorModel.Parent = indicatorFolder

	local attackDelay = data.attackDelay or 0.5
	local flashConn = startFlashEffect(indicatorModel, 0, attackDelay)

	activeIndicators[instanceId] = {
		model = indicatorModel,
		conn = flashConn,
	}

	task.delay(attackDelay + 0.15, function()
		clearIndicator(instanceId)
	end)
end

--========================================
-- Public API
--========================================

function AttackIndicatorController.Init()
	-- 텔레그래프 공격 (패턴 기반 3D 볼륨)
	NetClient.On("Creature.Attack.Telegraph", function(data)
		if data and data.instanceId then
			showTelegraphIndicator(data.instanceId, data)
		end
	end)

	-- 레거시 즉시 공격 (attackRange 기반 원형 볼륨)
	NetClient.On("Creature.Attack.Play", function(data)
		if data and data.instanceId and data.attackRange then
			showBasicIndicator(data.instanceId, data)
		end
	end)

	-- 크리처 사망/디스폰 시 잔여 표시 정리
	NetClient.On("Creature.Removed", function(data)
		if data and data.instanceId then
			clearIndicator(data.instanceId)
		end
	end)

	print("[AttackIndicatorController] Initialized (3D volume indicators)")
end

return AttackIndicatorController
