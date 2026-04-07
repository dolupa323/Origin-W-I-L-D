-- AttackIndicatorController.lua
-- 크리처 텔레그래프 공격 범위 표시 (데칼 기반)
-- ReplicatedStorage > Assets > AttackIndicators 폴더의 Decal 사용
-- 선행 모션 시작 시 범위 ON → 공격 모션 종료 시 범위 OFF

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
local INDICATOR_HEIGHT = Balance.TELEGRAPH_INDICATOR_HEIGHT or 0.15
local FLASH_SPEED = Balance.TELEGRAPH_FLASH_SPEED or 3.0
local INDICATOR_OPACITY = Balance.TELEGRAPH_INDICATOR_OPACITY or 0.35
local INDICATOR_OVERSIZE = Balance.TELEGRAPH_INDICATOR_OVERSIZE or 1.15

-- Active indicators: [instanceId] = { model: Model, conn: RBXScriptConnection? }
local activeIndicators = {}

-- Workspace 인디케이터 폴더
local indicatorFolder = Instance.new("Folder")
indicatorFolder.Name = "AttackIndicators"
indicatorFolder.Parent = Workspace

-- 데칼 에셋 캐시
local decalCache = {}

--========================================
-- Decal Asset Loader
--========================================

--- 데칼 에셋 폴더 로드 (Assets/AttackIndicators)
local function getDecalAsset(pattern: string, creatureId: string?): Decal?
	-- 1. 크리처 전용 데칼 검색 (Decal_CONE_PARASAUR 등)
	if creatureId then
		local specificName = "Decal_" .. pattern .. "_" .. creatureId
		if decalCache[specificName] then
			return decalCache[specificName]
		end
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			local folder = assets:FindFirstChild("AttackIndicators")
			if folder then
				local decal = folder:FindFirstChild(specificName)
				if decal then
					decalCache[specificName] = decal
					return decal
				end
			end
		end
	end

	-- 2. 범용 데칼 폴백 (Decal_CONE 등)
	local genericName = "Decal_" .. pattern
	if decalCache[genericName] then
		return decalCache[genericName]
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local folder = assets:FindFirstChild("AttackIndicators")
		if folder then
			local decal = folder:FindFirstChild(genericName)
			if decal then
				decalCache[genericName] = decal
				return decal
			end
		end
	end

	return nil
end

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

--========================================
-- Ground Height Raycast
--========================================

--- 지면 높이를 Raycast로 구함 (Terrain만 대상)
local function getGroundY(pos: Vector3): number
	local rayOrigin = Vector3.new(pos.X, pos.Y + 50, pos.Z)
	local rayDir = Vector3.new(0, -100, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local result = Workspace:Raycast(rayOrigin, rayDir, params)
	if result then
		return result.Position.Y + INDICATOR_HEIGHT
	end
	return pos.Y + INDICATOR_HEIGHT
end

--- 여러 샘플 지점 중 가장 높은 지면 Y를 반환 (고저차 대응)
local function getMaxGroundY(samplePoints: {Vector3}): number
	local maxY = -math.huge
	for _, pt in ipairs(samplePoints) do
		local y = getGroundY(pt)
		if y > maxY then
			maxY = y
		end
	end
	return maxY
end

--========================================
-- Decal-Based Indicator Creation
--========================================

--- 데칼 기반 인디케이터 Part 생성 (공통)
local function createDecalPart(decalSource: Decal, sizeX: number, sizeZ: number, origin: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "IndicatorSurface"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 1, 1)
	part.Transparency = 1 -- Part 자체는 투명, 데칼만 보임
	part.Size = Vector3.new(sizeX, 0.05, sizeZ)
	part.CFrame = cframe

	-- Top면에 데칼 복사
	local decal = decalSource:Clone()
	decal.Face = Enum.NormalId.Top
	decal.Parent = part

	return part
end

--- CONE (부채꼴) 인디케이터 생성
--- ★ 데칼 크기 = 판정 범위와 정확히 일치
--- origin(Head 위치)에서 전방 range까지가 판정 범위
--- Part는 origin을 뒷변으로, 전방 range를 앞변으로 배치
local function createConeIndicator(origin: Vector3, lookVector: Vector3, range: number, angleDeg: number, decalSource: Decal): Model
	local model = Instance.new("Model")
	model.Name = "ConeIndicator"

	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	flatLook = flatLook.Unit

	-- 범위 내 샘플 포인트에서 가장 높은 지면 높이 사용
	local halfAngleRad = math.rad(angleDeg / 2)
	local right = Vector3.new(flatLook.Z, 0, -flatLook.X)
	local halfW = range * math.sin(halfAngleRad)
	local samples = {
		origin,
		origin + flatLook * (range * 0.5),
		origin + flatLook * range,
		origin + flatLook * range + right * halfW,
		origin + flatLook * range - right * halfW,
	}
	local groundY = getMaxGroundY(samples)
	local groundOrigin = Vector3.new(origin.X, groundY, origin.Z)

	local sizeX = halfW * 2
	local sizeZ = range
	local center = groundOrigin + flatLook * (range / 2)

	local cf = CFrame.lookAt(center, center + flatLook)
	local part = createDecalPart(decalSource, sizeX, sizeZ, groundOrigin, cf)
	part.Parent = model

	return model
end

--- CIRCLE (원형) 인디케이터 생성
local function createCircleIndicator(origin: Vector3, radius: number, decalSource: Decal): Model
	local model = Instance.new("Model")
	model.Name = "CircleIndicator"

	local samples = {
		origin,
		origin + Vector3.new(radius, 0, 0),
		origin + Vector3.new(-radius, 0, 0),
		origin + Vector3.new(0, 0, radius),
		origin + Vector3.new(0, 0, -radius),
	}
	local groundY = getMaxGroundY(samples)
	local groundOrigin = Vector3.new(origin.X, groundY, origin.Z)

	local sizeXZ = radius * 2
	local cf = CFrame.new(groundOrigin)
	local part = createDecalPart(decalSource, sizeXZ, sizeXZ, groundOrigin, cf)
	part.Parent = model

	return model
end

--- CHARGE (직선 돌진) 인디케이터 생성
local function createChargeIndicator(origin: Vector3, lookVector: Vector3, width: number, length: number, decalSource: Decal): Model
	local model = Instance.new("Model")
	model.Name = "ChargeIndicator"

	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	flatLook = flatLook.Unit
	local right = Vector3.new(flatLook.Z, 0, -flatLook.X)
	local halfW = width / 2

	local samples = {
		origin,
		origin + flatLook * (length / 2),
		origin + flatLook * length,
		origin + flatLook * length + right * halfW,
		origin + flatLook * length - right * halfW,
	}
	local groundY = getMaxGroundY(samples)
	local groundOrigin = Vector3.new(origin.X, groundY, origin.Z)
	local center = groundOrigin + flatLook * (length / 2)

	local cf = CFrame.lookAt(center, center + flatLook)
	local part = createDecalPart(decalSource, width, length, groundOrigin, cf)
	part.Parent = model

	return model
end

--- PROJECTILE (착탄) 인디케이터 생성
local function createProjectileIndicator(targetPos: Vector3, impactRadius: number, decalSource: Decal): Model
	local model = Instance.new("Model")
	model.Name = "ProjectileIndicator"

	local samples = {
		targetPos,
		targetPos + Vector3.new(impactRadius, 0, 0),
		targetPos + Vector3.new(-impactRadius, 0, 0),
		targetPos + Vector3.new(0, 0, impactRadius),
		targetPos + Vector3.new(0, 0, -impactRadius),
	}
	local groundY = getMaxGroundY(samples)
	local groundOrigin = Vector3.new(targetPos.X, groundY, targetPos.Z)

	local sizeXZ = impactRadius * 2
	local cf = CFrame.new(groundOrigin)
	local part = createDecalPart(decalSource, sizeXZ, sizeXZ, groundOrigin, cf)
	part.Parent = model

	return model
end

--========================================
-- Flash & Lifecycle
--========================================

--- 데칼 깜빡임 효과 (Decal.Transparency 조작)
local function startFlashEffect(model: Model, windupTime: number, attackTime: number)
	local startTime = tick()
	local totalTime = windupTime + attackTime

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

		-- 공격 구간에서 더 불투명하게
		local baseTransparency = isAttackPhase and 0.2 or (1 - INDICATOR_OPACITY)
		local flashTransparency = baseTransparency + pulse * 0.15

		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("Decal") then
				desc.Transparency = math.clamp(flashTransparency, 0, 0.95)
			end
		end
	end)

	return conn
end

--- 범위 표시 생성 및 표시
local function showIndicator(instanceId: string, data: any)
	-- 기존 표시 제거
	if activeIndicators[instanceId] then
		local old = activeIndicators[instanceId]
		if old.conn then old.conn:Disconnect() end
		if old.model and old.model.Parent then old.model:Destroy() end
		activeIndicators[instanceId] = nil
	end

	local pattern = data.pattern or "CONE"
	local creatureId = data.creatureId or nil
	local creaturePos = Vector3.new(data.creaturePos[1], data.creaturePos[2], data.creaturePos[3])
	local creatureLook = Vector3.new(data.creatureLook[1], data.creatureLook[2], data.creatureLook[3])
	local targetPos = Vector3.new(data.targetPos[1], data.targetPos[2], data.targetPos[3])
	local windupTime = data.windupTime or 0.5
	local attackTime = data.attackTime or 0.5

	-- 데칼 에셋 로드
	local decalSource = getDecalAsset(pattern, creatureId)
	if not decalSource then
		warn("[AttackIndicatorController] Decal not found: Decal_" .. pattern)
		return
	end

	-- 크리처 모델 검색 (실시간 위치 사용)
	local creatureModel = nil
	local creatureFolder = Workspace:FindFirstChild("Creatures")
	if creatureFolder then
		for _, child in ipairs(creatureFolder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("InstanceId") == instanceId then
				creatureModel = child
				break
			end
		end
	end

	-- 실시간 크리처 위치 사용
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

	-- 패턴별 인디케이터 생성
	local indicatorModel
	if pattern == "CONE" then
		local visRange = (data.range or 10) * INDICATOR_OVERSIZE
		local visAngle = (data.angle or 60) * INDICATOR_OVERSIZE
		indicatorModel = createConeIndicator(indicatorOrigin, creatureLook, visRange, visAngle, decalSource)
	elseif pattern == "CIRCLE" then
		local visRadius = (data.radius or 10) * INDICATOR_OVERSIZE
		indicatorModel = createCircleIndicator(creaturePos, visRadius, decalSource)
	elseif pattern == "CHARGE" then
		local visWidth = (data.width or 6) * INDICATOR_OVERSIZE
		local visLength = (data.length or 20) * INDICATOR_OVERSIZE
		indicatorModel = createChargeIndicator(creaturePos, creatureLook, visWidth, visLength, decalSource)
	elseif pattern == "PROJECTILE" then
		local visRadius = (data.impactRadius or 5) * INDICATOR_OVERSIZE
		indicatorModel = createProjectileIndicator(targetPos, visRadius, decalSource)
	else
		local visRange = (data.range or 10) * INDICATOR_OVERSIZE
		local visAngle = (data.angle or 60) * INDICATOR_OVERSIZE
		indicatorModel = createConeIndicator(indicatorOrigin, creatureLook, visRange, visAngle, decalSource)
	end

	indicatorModel.Parent = indicatorFolder

	-- 깜빡임 효과 시작
	local flashConn = startFlashEffect(indicatorModel, windupTime, attackTime)

	activeIndicators[instanceId] = {
		model = indicatorModel,
		conn = flashConn,
	}

	-- 총 시간 후 자동 제거 (페이드 아웃)
	local totalTime = windupTime + attackTime + 0.1
	task.delay(totalTime, function()
		local indicator = activeIndicators[instanceId]
		if indicator then
			if indicator.conn then indicator.conn:Disconnect() end
			if indicator.model and indicator.model.Parent then
				-- 데칼 페이드 아웃
				for _, desc in ipairs(indicator.model:GetDescendants()) do
					if desc:IsA("Decal") then
						TweenService:Create(desc, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Transparency = 1
						}):Play()
					end
				end
				task.delay(0.25, function()
					if indicator.model and indicator.model.Parent then
						indicator.model:Destroy()
					end
				end)
			end
			activeIndicators[instanceId] = nil
		end
	end)
end

--========================================
-- Public API
--========================================

function AttackIndicatorController.Init()
	-- ★ 바닥 범위 표시 제거됨 — 크리처 발광 효과로 대체 (CreatureAnimationController)
	-- 크리처 사망/디스폰 시 잔여 표시 정리 (안전장치)
	NetClient.On("Creature.Removed", function(data)
		if data and data.instanceId then
			local indicator = activeIndicators[data.instanceId]
			if indicator then
				if indicator.conn then indicator.conn:Disconnect() end
				if indicator.model and indicator.model.Parent then
					indicator.model:Destroy()
				end
				activeIndicators[data.instanceId] = nil
			end
		end
	end)

	print("[AttackIndicatorController] Initialized (ground indicator disabled)")
end

return AttackIndicatorController
