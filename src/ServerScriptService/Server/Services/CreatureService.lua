-- CreatureService.lua
-- 크리처 스폰 및 관리 서비스 (Phase 3-1)
-- 서버 권위로 크리처 엔티티를 생성하고 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)
local SpawnConfig = require(Shared.Config.SpawnConfig)

-- Zone별 스폰 완료 여부 추적
local spawnedZones = {}

local CreatureService = {}

-- Dependencies
local NetController
local DataService
local WorldDropService
local PlayerStatService -- Phase 6 연동
local HarvestService -- 시체 채집 연동
local DropTableData -- require 나중에 (상호참조 방지)
local DebuffService -- Phase 4-4 연동
local protectedZoneChecker = nil -- TotemService에서 주입

local function getProtectedZoneInfo(position: Vector3)
	if not protectedZoneChecker then
		return nil
	end

	local result = protectedZoneChecker(position)
	if result == true then
		return {
			active = true,
			centerPosition = position,
			radius = 20,
		}
	end

	if type(result) == "table" and result.active then
		return result
	end

	return nil
end

-- Private State
local activeCreatures = {} -- [instanceId] = { model=Part, data=Data, state=..., targetPosition=Vector3, lastStateChange=number }
local creatureCount = 0
local _lastKnownPlayerPos = {} -- [userId] = Vector3 (리스폰 대기 중 디스폰 방지용)

--- 크리처 상태 설정 헬퍼 (내부 상태 + 클라이언트 속성 동기화)
local function setCreatureState(creature, newState)
	creature.state = newState
	creature.lastStateChange = tick()
	if creature.model then
		creature.model:SetAttribute("State", newState)
	end
end

-- groupSize > 1인 크리처는 cap 기여량을 줄여 과잉 점유 방지
local function getCapWeight(data)
	local gs = (data and data.groupSize) or 1
	return gs > 1 and (1 / gs) or 1
end

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")

-- AI Constants
local SPAWN_INTERVAL = 30 -- 30초마다 스폰 시도
local AI_UPDATE_INTERVAL = Balance.CREATURE_AI_TICK or 0.3 -- 0.3초마다 AI 로직 수행 (더 부드러운 이동)
local MIN_SPAWN_DIST = 40
local MAX_SPAWN_DIST = 80
local WANDER_RADIUS = 18
local DESPAWN_DIST = Balance.CREATURE_DESPAWN_DIST or 300 -- 150 -> 300 (LOD가 있으므로 시야 상향)
local CREATURE_DESPAWN_GRACE_AFTER_COMBAT = 60
local CREATURE_ATTACK_COOLDOWN = 2 -- 크리처 공격 쿨다운 (초)
local DEATH_FADE_TIME = 1.1
local DEATH_SINK_DISTANCE = 2.5
local NETWORK_ANIM_BUFFER = 0.35 -- ★ 유령 이빨 방지: 데미지를 애니메이션보다 늦게 적용 (네트워크 지연 + 애니 로드 보상)
local LABEL_VISIBLE_DURATION = 6

-- LOD (Level of Detail) 상수
local LOD_NEAR_DIST = 60    -- 이내: 0.3s (매 턴)
local LOD_MID_DIST = 150    -- 이내: 0.9s (매 3턴)
local LOD_FAR_DIST = 300    -- 이내: 1.5s (매 5턴)

-- 자연스러운 AI 행동 상수
local IDLE_MIN_TIME = 2.0   -- IDLE 최소 지속시간
local IDLE_MAX_TIME = 7.0   -- IDLE 최대 지속시간
local WANDER_MIN_TIME = 4.0 -- WANDER 최소 지속시간
local WANDER_MAX_TIME = 12.0 -- WANDER 최대 지속시간
local SPEED_VARIATION = 0.25 -- 속도 변동 범위 (±25%)
local WANDER_ANGLE_RANGE = 120 -- 배회 방향 변동 범위 (±도)

-- 어그로 시스템 상수
local AGGRO_TIMEOUT = 6 -- 추격 시간 제한 (초) -> 더 부드러운 추격 (너무 짧으면 끊김)
local MAX_CHASE_DISTANCE = 40 -- 어그로 해제 절대 거리 (studs) -> 도망치기 쉽게 축소 (50->40)
local AGGRO_COOLDOWN = 5 -- 어그로 다시 끌리기까지의 최소 시간 -> 한번 따돌리면 잠시 안전

-- 물/해수면 상수
local SEA_LEVEL = Balance.SEA_LEVEL or 2 -- Balance 기준 해수면 높이 사용
local WATER_CHECK_DISTANCE = 5 -- 이동 전 물 체크 거리
local WATER_MARGIN = 10 -- 물 반경 접근 금지 거리 (studs)
local CREATURE_MIN_SPAWN_SEPARATION = 18
local isSpawnPositionOccupied

-- Torpor 관련 (Phase 6)
local TORPOR_DECAY_RATE = 2 -- 초당 Torpor 감소량
local STUN_RECOVERY_THRESHOLD = 0 -- Torpor가 이 이하로 내려가면 깨어남

-- Pathfinding Constants
local PATH_RECALC_DIST = 8 -- 목표가 이 거리 이상 움직이면 경로 재계산
local WAYPOINT_REACH_DIST_BASE = 4 -- 웨이포인트 도달 판정 기본 거리 (소형 크리처)
local MOVETO_RETHRESHOLD = 2 -- MoveTo 재호출 최소 거리 차이 (마이크로 스터터 방지)
local PACK_MENTALITY_HEIGHT_DIFF = 15 -- 동족 인식 최대 고저차 (절벽 투시 방지)

-- ★ 쓰러짐(넘어짐) 시스템 상수
local COLLAPSE_HP_RATIO = 0.2 -- 체력 20% 이하 시 쓰러짐
-- local COLLAPSE_DURATION = 15.0 -- ★ 제거: 영구 쓰러짐으로 변경 (회복 없음)

-- 크리처 지면 스냅 (CreatureData의 corpseOffset 참조)

--- 크리처 모델을 지면에 스냅하는 헬퍼 (HarvestService.snapToGround와 동일 로직)
local function snapCreatureToGround(model, rootPart, creatureData)
	if not rootPart or not model or not model.Parent then return end
	local groundOffset = (creatureData and creatureData.corpseOffset) or 2

	local lowestY = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 0.9 then
			local bottomY = part.Position.Y - part.Size.Y / 2
			if bottomY < lowestY then lowestY = bottomY end
		end
	end
	if lowestY == math.huge then
		lowestY = rootPart.Position.Y - rootPart.Size.Y / 2
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local rayOrigin = rootPart.Position + Vector3.new(0, 250, 0)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), rayParams)
	if rayResult then
		local groundY = rayResult.Position.Y
		local dropDist = (lowestY + groundOffset) - groundY
		if math.abs(dropDist) > 0.1 then
			rootPart.CFrame = rootPart.CFrame - Vector3.new(0, dropDist, 0)
		end
	end
end

-- ★ 크리처 크기 기반 동적 웨이포인트 도달 거리 계산
local function getWaypointReachDist(creature)
	if not creature or not creature.model then return WAYPOINT_REACH_DIST_BASE end
	local ok, _, cSize = pcall(function() return creature.model:GetBoundingBox() end)
	if not ok or not cSize then return WAYPOINT_REACH_DIST_BASE end
	-- 몸통 크기의 절반 + 기본 2스터드 여유, 최소 4 최대 15
	return math.clamp(math.max(cSize.X, cSize.Z) / 2 + 2, WAYPOINT_REACH_DIST_BASE, 15)
end

local creatureFolder = workspace:FindFirstChild("Creatures") or Instance.new("Folder", workspace)
creatureFolder.Name = "Creatures"

-- 크리처 최대 수 (Balance에서 가져옴)
local CREATURE_CAP = Balance.WILDLIFE_CAP or 250

--========================================
-- Public API
--========================================

function CreatureService.Init(_NetController, _DataService, _WorldDropService, _DebuffService, _PlayerStatService)
	NetController = _NetController
	DataService = _DataService
	WorldDropService = _WorldDropService
	DebuffService = _DebuffService
	PlayerStatService = _PlayerStatService
	
	-- DropTableData 로드 (ReplicatedStorage)
	DropTableData = require(game:GetService("ReplicatedStorage").Data.DropTableData)
	
	-- [추가] 신규 플레이어 충돌 그룹 할당 루틴
	local function setCharGroup(char)
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Players"
			end
		end
		char.DescendantAdded:Connect(function(child)
			if child:IsA("BasePart") then child.CollisionGroup = "Players" end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(setCharGroup)
		if player.Character then setCharGroup(player.Character) end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then setCharGroup(p.Character) end
	end
	
	-- ★ 콘텐츠 스폰은 등록된 섬에서만 실행
	if SpawnConfig.IsContentPlace() then
		-- ★ 초기 대량 스폰 (서버 시작 시 즉시)
		task.spawn(function()
			task.wait(2) -- 맵 로드 대기
			CreatureService._initialSpawn()
		end)
		
		-- 보충 스폰 루프 (죽은 수만큼만 보충)
		local REPLENISH_INTERVAL = Balance.CREATURE_REPLENISH_INTERVAL or 45
		task.spawn(function()
			task.wait(15) -- 초기 스폰 완료 후 시작
			while true do
				task.wait(REPLENISH_INTERVAL)
				CreatureService._replenishLoop()
			end
		end)
	else
		warn("[CreatureService] 미등록 PlaceId — 크리처 자동 스폰 비활성화")
	end
	
	-- AI 루프 시작
	task.spawn(function()
		while true do
			task.wait(AI_UPDATE_INTERVAL)
			CreatureService._updateAILoop()
		end
	end)
	
	print("[CreatureService] Initialized with initial spawn + replenish + AI systems")
end

--========================================
-- Model Setup Helper (어떤 구조든 지원)
--========================================

--- 모델의 BoundingBox 중심 계산
local function getModelCenter(model: Model): Vector3
	local parts = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	
	if #parts == 0 then
		return Vector3.new(0, 0, 0)
	end
	
	local minPos = Vector3.new(math.huge, math.huge, math.huge)
	local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)
	
	for _, part in ipairs(parts) do
		local pos = part.Position
		local halfSize = part.Size / 2
		
		minPos = Vector3.new(
			math.min(minPos.X, pos.X - halfSize.X),
			math.min(minPos.Y, pos.Y - halfSize.Y),
			math.min(minPos.Z, pos.Z - halfSize.Z)
		)
		maxPos = Vector3.new(
			math.max(maxPos.X, pos.X + halfSize.X),
			math.max(maxPos.Y, pos.Y + halfSize.Y),
			math.max(maxPos.Z, pos.Z + halfSize.Z)
		)
	end
	
	return (minPos + maxPos) / 2
end

--- 모델의 높이 계산 (BillboardGui offset용)
local function getModelHeight(model: Model): number
	local maxY = -math.huge
	local minY = math.huge
	
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local topY = part.Position.Y + part.Size.Y / 2
			local bottomY = part.Position.Y - part.Size.Y / 2
			maxY = math.max(maxY, topY)
			minY = math.min(minY, bottomY)
		end
	end
	
	return maxY - minY
end

--- 어떤 구조의 모델이든 크리처로 설정
local function setupModelForCreature(model: Model, position: Vector3, data: any)
	-- 0. 기존 스크립트/사운드 제거 (Toolbox 모델 충돌 방지)
	local removedCount = 0
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
			child:Destroy()
			removedCount = removedCount + 1
		elseif child:IsA("Sound") then
			child:Destroy()
			removedCount = removedCount + 1
		elseif child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
			-- 기존 GUI도 제거 (우리가 새로 만들 것임)
			child:Destroy()
			removedCount = removedCount + 1
		end
	end
	if removedCount > 0 then
		print(string.format("[CreatureService] Removed %d embedded scripts/sounds/GUIs from model", removedCount))
	end
	
	-- 1. HumanoidRootPart 찾기 또는 생성
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	
	if not rootPart then
		-- 모델 중심 및 크기 계산
		local _, modelSize = model:GetBoundingBox()
		local center = getModelCenter(model)
		
		-- HumanoidRootPart 생성 (고정 사이즈로 생성하여 단차/경사로 걸림 방지)
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 2) -- 물리에 최적화된 작은 크기
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.CanQuery = true
		rootPart.Position = center
		rootPart.Parent = model
		
		-- [추가] 실제 판정용 Hitbox (공격용)
		local hitbox = Instance.new("Part")
		hitbox.Name = "ModelHitbox"
		hitbox.Size = modelSize
		hitbox.Transparency = 1
		hitbox.CanCollide = false -- 물리 충돌은 Humanoid가 담당
		hitbox.CanQuery = true
		hitbox.CFrame = rootPart.CFrame
		hitbox.Parent = model
		local hw = Instance.new("WeldConstraint")
		hw.Part0 = rootPart
		hw.Part1 = hitbox
		hw.Parent = hitbox
		
		-- 모든 BasePart를 HumanoidRootPart에 Weld로 연결
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part ~= rootPart then
				-- 기존 Anchor 해제
				part.Anchored = false
				
				-- 이미 Weld가 있는지 확인
				local hasWeld = false
				for _, constraint in ipairs(part:GetChildren()) do
					if constraint:IsA("WeldConstraint") or constraint:IsA("Weld") or constraint:IsA("Motor6D") then
						hasWeld = true
						break
					end
				end
				
				-- Weld 없으면 HumanoidRootPart에 연결
				if not hasWeld then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = rootPart
					weld.Part1 = part
					weld.Parent = rootPart
				end
			end
		end
		
		print(string.format("[CreatureService] Created HumanoidRootPart for model (center: %.1f, %.1f, %.1f)", center.X, center.Y, center.Z))
	end
	
	-- 2. 모든 파트 Anchored = false 및 충돌 그룹 설정 + ★ CanQuery 보장 (히트박스 전체 적용)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CollisionGroup = "Creatures"
			part.CanQuery = true  -- ★ 모든 파트를 GetPartBoundsInRadius로 감지 가능하게
		end
	end
	
	-- ★ 물리 안정화: 합리적 밀도 + 높은 마찰 → 플레이어 발사 방지
	rootPart.CustomPhysicalProperties = PhysicalProperties.new(
		1.0,  -- Density: 합리적 무게 (기본 0.7 대비 미세 추가 안정성)
		2,    -- Friction: 높은 마찰력
		0,    -- Elasticity: 반발력 없음 (튕김 방지)
		1,    -- FrictionWeight
		0     -- ElasticityWeight
	)
	rootPart.RootPriority = 127  -- 최대 우선순위: 다른 파트에 의해 밀리지 않음
	
	-- 3. PrimaryPart 설정
	model.PrimaryPart = rootPart
	if not model.PrimaryPart then
		warn(string.format("[CreatureService] FAILED to set PrimaryPart for %s (Root: %s)", model.Name, rootPart and rootPart.Name or "nil"))
	else
		print(string.format("[CreatureService] Set PrimaryPart for %s to %s", model.Name, rootPart.Name))
	end
	
	-- 4. 위치 이동
	local modelHeight = getModelHeight(model)
	local offset = Vector3.new(0, modelHeight / 2 + 1, 0)
	model:PivotTo(CFrame.new(position + offset))
	
	-- 5. Humanoid 찾기 또는 생성
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	
	-- 6. Humanoid 설정
	humanoid.WalkSpeed = data.walkSpeed or 16
	humanoid.MaxHealth = data.maxHealth
	humanoid.Health = data.maxHealth
	
	-- [추가] 지형 적응력 향상 (오르막/내리막)
	humanoid.MaxSlopeAngle = 89 -- ★ 거의 모든 경사면 이동 가능 (경사 실패 방지)
	humanoid.AutoJumpEnabled = false -- ★ 비활성화: 랜덤 점프/바운스 방지
	
	-- [추가] 물리적 이상 현상 방지 (쓰러짐/날아감 방지)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)   -- ★ 활성화: 경사면 내부 마이크로 점프 필요
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)  -- ★ 수영 물리 비활성화
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)   -- ★ 경사면 등반 활성화
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 5 -- ★ 최소 점프력: 지형 미세 단차 물리 보정용 (시각적 점프 발생 안 함)
	
	-- [수정] HipHeight 계산 공식: 지면에 정확히 붙도록 보정
	-- HipHeight = HRP 바닥 ~ 모델 바닥 거리 (추가 여유 없음)
	local modelCF, modelSize = model:GetBoundingBox()
	-- ★ 실제 모델 바닥을 레이캐스트로 측정
	local lowestY = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 0.9 then
			local bottomY = part.Position.Y - part.Size.Y / 2
			if bottomY < lowestY then lowestY = bottomY end
		end
	end
	if lowestY == math.huge then
		lowestY = modelCF.Position.Y - modelSize.Y / 2
	end
	-- HRP 바닥면에서 모델 바닥까지의 거리
	local hrpBottom = rootPart.Position.Y - rootPart.Size.Y / 2
	humanoid.HipHeight = math.max(0, hrpBottom - lowestY)
	
	-- 7. 크리처 사운드 (전투 진입 시 한 번 재생)
	-- 에셋 폴더: Assets/Sounds/Creatures/{크리처ID}
	local combatCry = Instance.new("Sound")
	combatCry.Name = "CombatCry"
	combatCry.Volume = 0.5
	combatCry.RollOffMode = Enum.RollOffMode.Linear
	combatCry.RollOffMinDistance = 15
	combatCry.RollOffMaxDistance = 80
	combatCry.Looped = false
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local cf = assetsFolder:FindFirstChild("CreatureSounds")
		if cf then
			local snd = cf:FindFirstChild(data.id)
			if snd and snd:IsA("Sound") then
				combatCry.SoundId = snd.SoundId
				print(string.format("[CreatureService] CombatCry loaded for %s: %s", data.id, snd.SoundId))
			else
				warn(string.format("[CreatureService] No sound found for creature: %s", data.id))
			end
		end
	end
	combatCry.Parent = rootPart
	
	-- ★ 크리처 파트 CanCollide=false + Massless=true: 플레이어와 물리 충돌 완전 제거
	-- 밀림/끼임/튕김 방지 — Humanoid 내부 캡슐이 지면 충돌을 담당
	-- Massless=true: 물리 겹침 발생 시에도 크리처 파트가 플레이어에게 힘을 전달하지 못함
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			if part ~= rootPart then
				part.Massless = true
			end
		end
	end
	
	-- ★ [FIX] 런타임 중 추가되는 파트도 충돌/질량 설정 적용 (애니메이션 본, 이펙트 파트 등)
	model.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			desc.CollisionGroup = rootPart.CollisionGroup -- 현재 그룹 (Creatures / CombatCreatures)
			desc.CanCollide = false
			if desc ~= rootPart then
				desc.Massless = true
			end
		end
	end)
	
	-- ★ [FIX] Humanoid 엔진이 HumanoidRootPart.CanCollide를 매 프레임 true로 강제하므로,
	-- GetPropertyChangedSignal로 감시하여 즉시 false로 되돌림 (플레이어 발사 방지)
	rootPart:GetPropertyChangedSignal("CanCollide"):Connect(function()
		if rootPart.CanCollide then
			rootPart.CanCollide = false
		end
	end)
	
	return model, rootPart, humanoid
end

--- 모델 찾기 (유연한 이름 매칭)
local function findCreatureModel(modelsFolder, modelName, creatureId)
	if not modelsFolder then return nil end
	
	-- 1. 정확한 이름 매칭
	local template = modelsFolder:FindFirstChild(modelName)
	if template then return template end
	
	-- 2. creatureId로 매칭 (예: "RAPTOR" -> "Raptor")
	template = modelsFolder:FindFirstChild(creatureId)
	if template then return template end
	
	-- 3. 대소문자 무시 매칭
	local lowerModelName = modelName:lower()
	local lowerCreatureId = creatureId:lower()
	
	for _, child in ipairs(modelsFolder:GetChildren()) do
		local childNameLower = child.Name:lower()
		
		-- modelName 또는 creatureId와 대소문자 무시 매칭
		if childNameLower == lowerModelName or childNameLower == lowerCreatureId then
			return child
		end
		
		-- 부분 문자열 매칭 (예: "VelociraptorModel"에서 "raptor" 찾기)
		if childNameLower:find(lowerCreatureId) or lowerCreatureId:find(childNameLower) then
			return child
		end
	end
	
	return nil
end

--- 크리처 스폰 (위치 지정)
function CreatureService.spawn(creatureId, position)
	local wildlifeCap = Balance and Balance.WILDLIFE_CAP or 50
	if creatureCount >= wildlifeCap then
		warn("[CreatureService] Creature cap reached")
		return nil
	end

	if not position or isSpawnPositionOccupied(position) then
		return nil
	end

	local data = DataService.getCreature(creatureId)
	if not data then
		warn("[CreatureService] Invalid creature ID:", creatureId)
		return nil
	end
	
	local model = nil
	local rootPart = nil
	local humanoid = nil
	
	-- 1. ReplicatedStorage/Assets/CreatureModels에서 모델 찾기
	local modelsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if modelsFolder then
		modelsFolder = modelsFolder:FindFirstChild("CreatureModels")
	end
	
	local modelName = data.modelName or creatureId
	local template = findCreatureModel(modelsFolder, modelName, creatureId)
	
	if template then
		-- 실제 모델 복제
		model = template:Clone()
		model.Name = creatureId
		
		-- 어떤 구조든 자동 설정
		model, rootPart, humanoid = setupModelForCreature(model, position, data)
		
		-- [추가] 모델 스케일 적용 (아기 공룡 등)
		if data.scale and data.scale ~= 1 then
			model:ScaleTo(data.scale)
		end
		
		print(string.format("[CreatureService] Loaded model '%s' for %s", template.Name, creatureId))
	else
		-- 폴백: 임시 플레이스홀더 모델 생성
		warn(string.format("[CreatureService] Model '%s' not found in CreatureModels, using placeholder", modelName))
		
		model = Instance.new("Model")
		model.Name = creatureId
		
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 2)
		rootPart.Position = position + Vector3.new(0, 1, 0)
		rootPart.BrickColor = BrickColor.Random()
		rootPart.Transparency = 0.5
		rootPart.Anchored = false
		rootPart.Parent = model
		model.PrimaryPart = rootPart
		
		humanoid = Instance.new("Humanoid")
		humanoid.WalkSpeed = data.walkSpeed or 16
		humanoid.MaxHealth = data.maxHealth
		humanoid.Health = data.maxHealth
		humanoid.Parent = model
	end
	
	-- ★ UI 데이터를 Attribute로 설정 (클라이언트에서 BillboardGui를 생성·관리)
	-- 서버에서 GUI를 직접 조작하면 250마리분의 UI 속성 복제로 대역폭 낭비 → Attribute만 설정
	local creatureName = data.name or creatureId
	if data.level then
		creatureName = "Lv." .. data.level .. " " .. creatureName
	end
	model:SetAttribute("DisplayName", creatureName)
	model:SetAttribute("MaxHealth", data.maxHealth)
	model:SetAttribute("CurrentHealth", data.maxHealth)
	model:SetAttribute("LabelVisibleUntil", 0)
	
	-- ★ 스폰 물리 안정화: workspace 배치 전 rootPart를 Anchored로 고정
	-- 모든 파트가 Anchored=false인 채 배치되면 지형 겹침으로 물리 발사 발생
	-- (열대섬 등 경사 지형에서 크리처가 물로 날아가는 버그 방지)
	rootPart.Anchored = true
	
	model.Parent = creatureFolder
	
	local instanceId = game:GetService("HttpService"):GenerateGUID(false)
	model:SetAttribute("InstanceId", instanceId)
	model:SetAttribute("CreatureId", creatureId)
	model:SetAttribute("Behavior", data.behavior or "NEUTRAL")
	
	-- Collision Group 설정
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Creatures"
		end
	end
	
	-- ★ 서버 물리 권한 고정: 클라이언트 물리 간섭 완전 차단
	pcall(function()
		rootPart:SetNetworkOwner(nil) -- nil = 서버 소유
	end)
	
	-- ★ 개선: StreamingEnabled 대응 지형 로딩 감지 → 정확한 높이 배치 후 Anchored 해제
	-- 레이캐스트로 지형을 감지할 때까지 대기, 최대 5초
	task.spawn(function()
		local maxWait = 5
		local elapsedTime = 0
		local checkInterval = 0.1
		
		-- Raycast 필터: Terrain + Map 모두 포함 (Map 위 스폰 대응)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		local filterList = { workspace.Terrain }
		local map = workspace:FindFirstChild("Map")
		if map then table.insert(filterList, map) end
		raycastParams.FilterDescendantsInstances = filterList
		
		while elapsedTime < maxWait do
			if not rootPart or not rootPart.Parent then
				return  -- 크리처가 삭제됨
			end
			
			-- 레이캐스트로 지형/맵 감지
			local rayOrigin = rootPart.Position + Vector3.new(0, 2, 0)
			local rayDirection = Vector3.new(0, -50, 0)
			local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			
			if rayResult then
				-- ✅ 지면 감지됨 → 정확한 높이로 재배치 후 Anchored 해제
				if rootPart.Anchored then
					local groundY = rayResult.Position.Y
					local hipHeight = humanoid.HipHeight
					local correctY = groundY + hipHeight + rootPart.Size.Y / 2
					local currentCF = rootPart.CFrame
					local yDiff = correctY - currentCF.Position.Y
					model:PivotTo(currentCF + Vector3.new(0, yDiff, 0))
					rootPart.Anchored = false
				end
				return
			end
			
			task.wait(checkInterval)
			elapsedTime = elapsedTime + checkInterval
		end
		
		-- ⏱️ 최대 시간 초과 시에도 강제 해제 (폴백)
		if rootPart and rootPart.Parent and rootPart.Anchored then
			rootPart.Anchored = false
		end
	end)
	
	activeCreatures[instanceId] = {
		id = instanceId,
		creatureId = creatureId,
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		data = data,
		maxHealth = data.maxHealth,
		currentHealth = data.maxHealth,
		maxTorpor = data.maxTorpor or 100,
		currentTorpor = 0,
		state = "IDLE",
		labelVisibleUntil = 0,
		targetPosition = nil,
		lastStateChange = tick(),
		lastUpdate = tick(),
		lastUpdateAt = tick(),
	}
	creatureCount = creatureCount + getCapWeight(data)
	
	-- ★ 클라이언트 애니메이션 연동: 초기 상태 속성 설정
	model:SetAttribute("State", "IDLE")
	
	print(string.format("[CreatureService] Spawned %s (%s)", creatureId, instanceId))
	
	return instanceId
end

--- 크리처 런타임 조회 (CombatService 연동용)
function CreatureService.getCreatureRuntime(instanceId: string)
	return activeCreatures[instanceId]
end

--- 전체 활성 크리처 런타임 맵 반환 (AOE 스킬용)
function CreatureService.getActiveCreatures()
	return activeCreatures
end

--- 크리처 현재 위치 반환
function CreatureService.getCreaturePosition(instanceId: string): Vector3?
	local creature = activeCreatures[instanceId]
	if creature and creature.rootPart then
		return creature.rootPart.Position
	end
	return nil
end

--========================================
-- 액티브 스킬 디버프 효과 (크리처 대상)
--========================================

--- 둔화 효과 (이동속도 감소, 기간 후 복구)
function CreatureService.applySlowEffect(instanceId: string, slowAmount: number, duration: number)
	local creature = activeCreatures[instanceId]
	if not creature or not creature.humanoid then return end
	local original = creature.humanoid.WalkSpeed
	creature.humanoid.WalkSpeed = original * (1 - math.clamp(slowAmount, 0, 0.9))
	task.delay(duration, function()
		local c = activeCreatures[instanceId]
		if c and c.humanoid then
			c.humanoid.WalkSpeed = original
		end
	end)
end

--- 경직 효과 (잠시 이동 불능)
function CreatureService.applyStaggerEffect(instanceId: string, duration: number)
	local creature = activeCreatures[instanceId]
	if not creature or not creature.humanoid then return end
	local original = creature.humanoid.WalkSpeed
	creature.humanoid.WalkSpeed = 0
	task.delay(duration, function()
		local c = activeCreatures[instanceId]
		if c and c.humanoid then
			c.humanoid.WalkSpeed = original
		end
	end)
end

--- 기절 효과 (행동 불능 + 이동 불능)
function CreatureService.applyStunEffect(instanceId: string, duration: number)
	local creature = activeCreatures[instanceId]
	if not creature or not creature.humanoid then return end
	local original = creature.humanoid.WalkSpeed
	creature.humanoid.WalkSpeed = 0
	-- 기절 중 AI 비활성화 (간이 구현: WalkSpeed=0으로 이동 차단)
	creature.stunned = true
	task.delay(duration, function()
		local c = activeCreatures[instanceId]
		if c then
			c.stunned = false
			if c.humanoid then
				c.humanoid.WalkSpeed = original
			end
		end
	end)
end

--- 크리처 강제 제거 (포획 등 특수 상황용)
function CreatureService.removeCreature(instanceId: string)
	local creature = activeCreatures[instanceId]
	if not creature then return end
	
	-- 전투 교전 상태 정리
	local CombatService = require(game:GetService("ServerScriptService").Server.Services.CombatService)
	if CombatService.disengageCreature then
		CombatService.disengageCreature(instanceId)
	end
	
	-- ★ 텔레그래프 범위 표시 정리 신호
	if NetController then
		NetController.FireAllClients("Creature.Removed", { instanceId = instanceId })
	end
	
	-- 즉시 런타임에서 제거
	local weight = getCapWeight(creature.data)
	activeCreatures[instanceId] = nil
	creatureCount = creatureCount - weight
	
	-- 시각적 제거 (클라이언트 BillboardGui는 모델 제거 시 자동 정리됨)
	
	if creature.model then
		-- 연출을 위해 투명화 후 제거
		for _, part in ipairs(creature.model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
			end
		end
		
		task.delay(1, function()
			creature.model:Destroy()
		end)
	end
end

local function playNaturalDeathSequence(creature)
	if not creature or not creature.model or not creature.model.Parent then
		return
	end

	local model = creature.model
	local rootPart = creature.rootPart

	-- ★ 사망 상태 설정: 클라이언트에서 DEAD 상태 감지 → 사망 애니메이션 재생
	setCreatureState(creature, "DEAD")

	-- ★ 시체 방패 방지: 즉시 모든 파트의 충돌/쿼리 비활성화
	model:SetAttribute("IsDead", true)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		end
	end
	-- ★ rootPart만 CanQuery 유지: HarvestService 시체 채집 감지에 필요
	if rootPart and rootPart.Parent then
		rootPart.CanQuery = true
	end

	if creature.humanoid then
		creature.humanoid.WalkSpeed = 0
		creature.humanoid.JumpPower = 0
		creature.humanoid.AutoRotate = false
	end

	-- ★ 이동 정지 (Anchored는 HarvestService가 지면 스냅 후 설정)
	if rootPart and rootPart.Parent then
		rootPart.AssemblyLinearVelocity = Vector3.zero
	end

	-- 시체 채집 시스템: HarvestService에 시체 노드 등록
	-- HarvestService가 Anchored, 지면 스냅, 데스 애니메이션 프리즈를 모두 처리
	if HarvestService and creature.creatureId then
		local position = rootPart and rootPart.Position or model:GetPivot().Position
		local nodeUID = HarvestService.registerCorpseNode(creature.creatureId, position, model)
		if nodeUID then
			-- registerCorpseNode가 모델 소유권을 가져감 → 여기서 파괴하지 않음
			print(string.format("[CreatureService] Corpse registered: %s → %s", creature.creatureId, nodeUID))
			return
		end
	end

	-- 시체 등록 실패 시 기존 사망 연출 (페이드 + 하강)으로 폴백
	if rootPart and rootPart.Parent then
		rootPart.Anchored = true
	end

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			TweenService:Create(inst, TweenInfo.new(DEATH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			TweenService:Create(inst, TweenInfo.new(DEATH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		end
	end

	if rootPart and rootPart.Parent then
		TweenService:Create(rootPart, TweenInfo.new(DEATH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = rootPart.CFrame * CFrame.new(0, -DEATH_SINK_DISTANCE, 0),
		}):Play()
	end

	task.delay(DEATH_FADE_TIME + 0.2, function()
		if model and model.Parent then
			model:Destroy()
		end
	end)
end

--- 크리처 사망 처리 (포획 실패 등 외부 호출용)
function CreatureService.killCreature(instanceId: string)
	local creature = activeCreatures[instanceId]
	if not creature then return end
	playNaturalDeathSequence(creature)
end

--- 공격 처리 (데미지 및 기절 수치 적용)
function CreatureService.processAttack(instanceId: string, hpDamage: number, torporDamage: number, attacker: Player): (boolean, Vector3?)
	local creature = activeCreatures[instanceId]
	if not creature or not creature.humanoid or creature.currentHealth <= 0 then
		return false, nil
	end

	creature.lastDamagedAt = tick()
	
	-- 1. 데미지 적용
	creature.currentHealth = math.max(0, creature.currentHealth - hpDamage)
	creature.labelVisibleUntil = tick() + LABEL_VISIBLE_DURATION
	
	-- ★ Attribute 갱신 (클라이언트에서 UI 반영)
	if creature.model then
		creature.model:SetAttribute("CurrentHealth", creature.currentHealth)
		creature.model:SetAttribute("LabelVisibleUntil", creature.labelVisibleUntil)
	end
	
	creature.humanoid.Health = creature.currentHealth
	
	-- ★ 사망 시 Humanoid Dead 상태 진입 방지 (사망 애니메이션 재생을 위해)
	-- Health가 0이면 Roblox가 Humanoid를 Dead 상태로 전환하여 Animator 비활성화
	if creature.currentHealth <= 0 and creature.humanoid then
		creature.humanoid.Health = 1 -- 임시 유지 (뒤에서 다시 0 설정)
	end
	
	-- 2. 상태 변화 및 연쇄 어그로 (Pack Mentality)
	if creature.currentHealth > 0 then
		-- ★ 쓰러짐 체크: HP가 20% 이하로 떨어지면 최초 1회 쓰러짐 발동
		local collapseThreshold = (creature.maxHealth or creature.data.maxHealth) * COLLAPSE_HP_RATIO
		if creature.currentHealth <= collapseThreshold and not creature._hasCollapsed then
			creature._hasCollapsed = true
			local prevState = creature.state
			local prevSpeed = creature.humanoid.WalkSpeed

			-- 사망 애니메이션 재생을 위해 DEAD 상태로 전환
			setCreatureState(creature, "DEAD")
			creature.humanoid.WalkSpeed = 0
			creature.humanoid.JumpPower = 0
			creature.humanoid.AutoRotate = false
			if creature.rootPart then
				creature.rootPart.AssemblyLinearVelocity = Vector3.zero
				creature.rootPart.Anchored = true
				
				-- ★ 사망 위치와 쓰러짐 위치 불일치 수정
				-- 서있는 자세(T-Pose) 기준으로 스냅하지 않고, 서버에서 데스 애니메이션을 
				-- 플레이하여 완전히 바닥에 누운 포즈가 완성된 후 스냅(snap)하도록 개선.
				task.spawn(function()
					local animator = creature.humanoid:FindFirstChildOfClass("Animator")
					if not animator then
						animator = Instance.new("Animator")
						animator.Parent = creature.humanoid
					end
					
					local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
					local CreatureAnimationIds = require(Shared.Config.CreatureAnimationIds)
					local animSet = CreatureAnimationIds[creature.creatureId] or CreatureAnimationIds.DEFAULT or {}
					local deathAnimName = animSet.DEATH or (creature.creatureId .. "_Death")
					
					local animObj = nil
					local assetsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
					if assetsFolder and assetsFolder:FindFirstChild("Animations") then
						animObj = assetsFolder.Animations:FindFirstChild(deathAnimName, true)
					end
					if not animObj then
						animObj = game:GetService("ReplicatedStorage"):FindFirstChild(deathAnimName, true)
					end
					
					if animObj and animObj:IsA("Animation") then
						local collapseTrack = animator:LoadAnimation(animObj)
						collapseTrack.Looped = false
						collapseTrack.Priority = Enum.AnimationPriority.Action4
						collapseTrack:Play(0.2)
						
						local waited = 0
						while collapseTrack.Length <= 0 and waited < 2 do
							task.wait(0.1)
							waited = waited + 0.1
						end
						local trackLength = collapseTrack.Length
						if trackLength > 0 then
							task.wait(math.max(0, trackLength - 0.05))
							if not collapseTrack.IsPlaying then collapseTrack:Play() end
							collapseTrack.TimePosition = trackLength * 0.98
						else
							task.wait(2.0)
						end
						collapseTrack:AdjustSpeed(0)
						task.wait(0.1) -- Motor6D 업데이트 대기
					end
					
					-- 누운 포즈의 Bounding Box를 기준으로 스냅!
					if activeCreatures[instanceId] and creature.rootPart and creature.model then
						-- ★ 늘어짐(Stretching) 방지: 모든 파트의 앵커를 잠시 풀고 이동 후 다시 고정
						for _, part in ipairs(creature.model:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Anchored = false
							end
						end
						
						snapCreatureToGround(creature.model, creature.rootPart, creature.data)
						
						-- ★ 포즈 및 위치 영구 고정
						for _, part in ipairs(creature.model:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Anchored = true
								part.CanCollide = false
							end
						end
					end
				end)
			end

			-- 공격자에게 알림
			local creatureName = creature.data.name or creature.data.id or creature.creatureId
			if attacker and NetController then
				NetController.FireClient(attacker, "Notify.Message", {
					text = creatureName .. "이(가) 쓰러졌습니다!",
				})
			end

			-- ★ 쓰러짐 후 모델에 HasCollapsed 속성 설정 (HarvestService에서 사망 시 활용)
			if creature.model then
				creature.model:SetAttribute("HasCollapsed", true)
			end

			-- ★ 영구 쓰러짐: 죽을 때까지 DEAD 상태 유지 (회복 없음)
			return false, nil -- 쓰러짐은 사망이 아님
		end

		if creature.state ~= "DEAD" then
			-- 피격 시 어그로/도망 (쓰러짐/기절 상태에서는 상태 전환 금지)
			local oldState = creature.state
			if creature.data.behavior ~= "PASSIVE" then
				setCreatureState(creature, "CHASE")
			else
				setCreatureState(creature, "FLEE")
				creature.humanoid.WalkSpeed = (creature.data.runSpeed or 20) * 1.2
			end

			-- ★ 피격 전투 진입 사운드 (IDLE/WANDER에서 전환된 경우만)
			if (oldState == "IDLE" or oldState == "WANDER") then
				local cry = creature.rootPart:FindFirstChild("CombatCry")
				if cry and cry.SoundId ~= "" then
					cry:Play()
				end
			end

			-- [시스템 추가] 주변 동족 인식 (Pack Mentality)
			-- 공격받은 크리처 주변 50스터드 내 같은 creatureId를 가진 개체들을 깨움
			local pPos = creature.rootPart.Position
			for _, other in pairs(activeCreatures) do
				if other.id ~= instanceId and other.creatureId == creature.creatureId then
					local otherPos = other.rootPart.Position
					local dist = (otherPos - pPos).Magnitude
					if dist < (Balance.PACK_AGGRO_RADIUS or 50) then
						-- ★ 고저차 체크: 절벽 위/아래 투시 방지
						local heightDiff = math.abs(otherPos.Y - pPos.Y)
						if heightDiff > PACK_MENTALITY_HEIGHT_DIFF then
							continue
						end
						
						-- ★ 시야(LOS) 확인: 중간에 지형 장애물이 있으면 감지 불가
						local losParams = RaycastParams.new()
						losParams.FilterDescendantsInstances = { creature.model, other.model, creatureFolder }
						losParams.FilterType = Enum.RaycastFilterType.Exclude
						local losRay = workspace:Raycast(pPos, (otherPos - pPos), losParams)
						if losRay and (losRay.Position - otherPos).Magnitude > 5 then
							-- 지형에 막혀서 시야가 없음 → 동족 인식 실패
							continue
						end
						
						if other.state == "IDLE" or other.state == "WANDER" then
							local otherOldState = other.state
							if other.data.behavior ~= "PASSIVE" then
								setCreatureState(other, "CHASE")
							else
								setCreatureState(other, "FLEE")
								other.humanoid.WalkSpeed = (other.data.runSpeed or 20) * 1.2
							end
							-- 동족도 전투 진입 사운드 재생
							local otherCry = other.rootPart:FindFirstChild("CombatCry")
							if otherCry and otherCry.SoundId ~= "" then
								otherCry:Play()
							end
						end
					end
				end
			end
		end
	end
	
	-- 3. GUI 갱신 → Attribute 기반으로 클라이언트에서 처리 (서버 복제 대역폭 절감)
	-- (CurrentHealth, CurrentTorpor, LabelVisibleUntil은 위에서 이미 설정됨)

	-- 4. 사망 처리
	if creature.currentHealth <= 0 then
		local attackerName = attacker and attacker.Name or "Unknown"
		local deathPos = creature.rootPart.Position

		-- ★ 사망 알림
		local creatureName = creature.data.name or creature.data.id or creature.creatureId
		if attacker and NetController then
			NetController.FireClient(attacker, "Notify.Message", {
				text = creatureName .. "을(를) 사냥했습니다!",
			})
		end
		
		-- 경험치 보상
		if PlayerStatService and attacker then
			local xpAmount = creature.data.xpReward or 25
			PlayerStatService.grantActionXP(attacker.UserId, xpAmount, {
				source = Enums.XPSource.CREATURE_KILL,
				actionKey = "CREATURE:" .. tostring(creature.creatureId),
			})
		end
		
		-- 즉시 제거 대신 자연스러운 사망 연출(페이드 + 하강) 적용
		if creature.model and creature.model:FindFirstChild("HumanoidRootPart") then
			local labels = creature.model.HumanoidRootPart:FindFirstChild("CreatureLabel")
			if labels then labels:Destroy() end
		end
		
		local weight = getCapWeight(creature.data)
		activeCreatures[instanceId] = nil 
		creatureCount = creatureCount - weight
		
		-- ★ 텔레그래프 범위 표시 정리 신호
		if NetController then
			NetController.FireAllClients("Creature.Removed", { instanceId = instanceId })
		end
		
		playNaturalDeathSequence(creature)
		
		return true, deathPos
	end
	
	return false, nil
end

--========================================
-- Internal AI & Spawn Logic
--========================================

--- 위치가 물/바다인지 체크
function CreatureService._isWaterPosition(position: Vector3): boolean
	-- Raycast로 바닥 체크
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.FilterType = Enum.RaycastFilterType.Include
	
	local result = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), params)
	if result then
		-- Material 체크
		if result.Material == Enum.Material.Water then
			return true
		end
		-- 해수면 아래 체크
		if result.Position.Y < SEA_LEVEL then
			return true
		end
	end
	
	-- 현재 Y 위치가 해수면 아래인 경우
	if position.Y < SEA_LEVEL then
		return true
	end
	
	return false
end

--- 위치가 물 반경 WATER_MARGIN 이내인지 체크 (물 자체 포함)
function CreatureService._isNearWater(position: Vector3): boolean
	-- 자기 자신이 물이면 당연히 true
	if CreatureService._isWaterPosition(position) then
		return true
	end
	-- 4방향 + 대각선 4방향 (총 8방향) 으로 margin 거리 체크
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local checkPos = position + Vector3.new(math.sin(angle) * WATER_MARGIN, 0, math.cos(angle) * WATER_MARGIN)
		if CreatureService._isWaterPosition(checkPos) then
			return true
		end
	end
	return false
end

--- 물에서 가장 가까운 육지 방향 찾기
function CreatureService._findLandDirection(position: Vector3): Vector3?
	local bestDir = nil
	local bestDist = math.huge
	
	-- 8방향, 다중 거리 체크 (20, 40, 60 studs)
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		
		for _, checkDist in ipairs({20, 40, 60}) do
			local checkPos = position + dir * checkDist
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { workspace.Terrain }
			params.FilterType = Enum.RaycastFilterType.Include
			
			local result = workspace:Raycast(checkPos + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), params)
			if result and result.Material ~= Enum.Material.Water and result.Position.Y >= SEA_LEVEL then
				local dist = (result.Position - position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestDir = dir
				end
				break -- 이 방향에서 찾았으면 다음 방향으로
			end
		end
	end
	
	return bestDir
end

--- 안전한 이동 위치 계산 (물 반경 회피 + 경로 중간 체크)
function CreatureService._getSafeTarget(currentPos: Vector3, targetPos: Vector3): Vector3
	-- 목표가 물 근처이면 안전한 지점으로 후퇴
	if CreatureService._isNearWater(targetPos) then
		local dir = (targetPos - currentPos)
		if dir.Magnitude > 0.1 then
			dir = dir.Unit
		else
			return currentPos
		end
		
		for dist = 5, 20, 5 do
			local safePos = currentPos + dir * dist
			if not CreatureService._isNearWater(safePos) then
				return safePos
			end
		end
		
		return currentPos
	end
	
	-- 경로 중간 지점 물 근접 체크 (25%, 50%, 75% 지점)
	local diff = targetPos - currentPos
	if diff.Magnitude > 8 then
		for _, frac in ipairs({0.25, 0.5, 0.75}) do
			local midPos = currentPos + diff * frac
			if CreatureService._isNearWater(midPos) then
				-- 중간에 물 근처이면 그 직전까지만 이동
				local safeFrac = math.max(0, frac - 0.15)
				local safePos = currentPos + diff * safeFrac
				if not CreatureService._isNearWater(safePos) then
					return safePos
				end
				return currentPos
			end
		end
	end
	
	return targetPos
end

--- 유효한 스폰 위치 찾기 (Donut Shape around player)
function CreatureService._findSpawnPosition(playerRootPart: Part): Vector3?
	if not playerRootPart then return nil end
	
	for i = 1, 15 do -- 15회 시도
		local angle = math.rad(math.random(1, 360))
		local distance = math.random(MIN_SPAWN_DIST, MAX_SPAWN_DIST)
		
		local offset = Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
		local origin = playerRootPart.Position + offset + Vector3.new(0, 300, 0)
		
		-- Raycast (Include 방식: Terrain + Map만 정확히 감지)
		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		local map = workspace:FindFirstChild("Map")
		if map then table.insert(filterList, map) end
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		local result = workspace:Raycast(origin, Vector3.new(0, -800, 0), params)
		if result then
			-- 물/바다 Material 체크 (육지만 허용)
			local isWater = result.Material == Enum.Material.Water
				or result.Material == Enum.Material.CrackedLava -- 용암도 제외
			
			-- 해수면 아래 체크 (Y가 너무 낮으면 물로 간주)
			local belowSeaLevel = result.Position.Y < SEA_LEVEL
			
			-- 물이 아니고 해수면 위인 경우만 허용
			if not isWater and not belowSeaLevel then
				local spawnPos = result.Position + Vector3.new(0, 0.5, 0)
				-- 추가 안전 체크: 물 반경 이내 스폰 방지
				if not CreatureService._isNearWater(spawnPos) and not isSpawnPositionOccupied(spawnPos) then
					return spawnPos
				end
			end
		end
	end
	return nil
end

--- 맵 중심 주변에 스폰 위치 찾기 (플레이어 없이도 동작)
function CreatureService._findMapSpawnPosition(center: Vector3, radius: number): Vector3?
	for i = 1, 30 do
		-- 사각형 맵 전역 분포 (Corners 포함)
		local xOffset = (math.random() * 2 - 1) * radius
		local zOffset = (math.random() * 2 - 1) * radius
		local x = center.X + xOffset
		local z = center.Z + zOffset
		local origin = Vector3.new(x, center.Y + 400, z) -- 높은 곳에서 발사
		
		-- 지형/맵만 감지하도록 필터링 강화
		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		local map = workspace:FindFirstChild("Map")
		if map then table.insert(filterList, map) end
		
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		-- 훨씬 높은 곳에서 더 깊게 발사하여 정확한 바닥 찾기
		local result = workspace:Raycast(origin, Vector3.new(0, -1200, 0), params)
		if result then
			-- 물/바다 Material 체크 (육지만 허용)
			local isWater = result.Material == Enum.Material.Water 
				or result.Material == Enum.Material.CrackedLava
			
			-- 해수면 체크 (Balance.SEA_LEVEL 사용)
			local belowSeaLevel = result.Position.Y < SEA_LEVEL
			
			if not isWater and not belowSeaLevel then
				local pos = result.Position + Vector3.new(0, 0.5, 0)
				-- 물 반경 이내 스폰 방지
				if not CreatureService._isNearWater(pos) and not isSpawnPositionOccupied(pos) then
					return pos
				end
			end
		end
	end
	return nil
end

local function getZoneCreatureSpawnRadius(zoneInfo, fallbackRadius)
	if zoneInfo and tonumber(zoneInfo.creatureSpawnRadius) then
		return tonumber(zoneInfo.creatureSpawnRadius)
	end
	return fallbackRadius
end

	-- ★ 초기 대량 스폰 (서버 시작 시 허브 Zone만 크리처 배치, 비허브는 SpawnZone으로 지연)
function CreatureService._initialSpawn()
	local PER_ZONE_COUNT = math.floor((Balance.INITIAL_CREATURE_COUNT or 80) / math.max(1, #SpawnConfig.GetAllZoneNames()))
	local SPAWN_RADIUS = Balance.CREATURE_INITIAL_SPAWN_RADIUS or 300
	local totalSpawned = 0
	local HUB_ZONE = SpawnConfig.HUB_ZONE or "GRASSLAND"

	for _, zoneName in ipairs(SpawnConfig.GetAllZoneNames()) do
		-- 허브가 아닌 Zone은 초기 스폰에서 제외
		if zoneName ~= HUB_ZONE then
			print(string.format("[CreatureService] Zone '%s' deferred (non-hub)", zoneName))
			continue
		end

		local zoneInfo = SpawnConfig.GetZoneInfo(zoneName)
		if not zoneInfo then continue end

		local zoneCenter = zoneInfo.center
		local zoneRadius = math.min(getZoneCreatureSpawnRadius(zoneInfo, SPAWN_RADIUS), zoneInfo.radius)

		print(string.format("[CreatureService] Zone '%s' initial spawn: %d creatures, radius %.0f, center %s",
			zoneName, PER_ZONE_COUNT, zoneRadius, tostring(zoneCenter)))

		local spawned = 0
		local attempts = 0
		local MAX_ATTEMPTS = PER_ZONE_COUNT * 10

		while spawned < PER_ZONE_COUNT and attempts < MAX_ATTEMPTS do
			attempts = attempts + 1
			local pos = CreatureService._findMapSpawnPosition(zoneCenter, zoneRadius)
			if pos then
				local cid = SpawnConfig.GetRandomCreatureForZone(zoneName)
				if not cid then continue end
				local data = DataService.getCreature(cid)
				local groupSize = (data and data.groupSize) or 1

				for i = 1, groupSize do
					if spawned >= PER_ZONE_COUNT then break end
					local spawnPos = pos
					if groupSize > 1 and i > 1 then
						local ox = math.random(-8, 8)
						local oz = math.random(-8, 8)
						local rayOrigin = pos + Vector3.new(ox, 200, oz)
						local rayParams = RaycastParams.new()
						local filterList = { workspace.Terrain }
						local mapRef = workspace:FindFirstChild("Map")
						if mapRef then table.insert(filterList, mapRef) end
						rayParams.FilterDescendantsInstances = filterList
						rayParams.FilterType = Enum.RaycastFilterType.Include
						local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), rayParams)
						if rayResult and rayResult.Material ~= Enum.Material.Water and rayResult.Position.Y >= SEA_LEVEL then
							spawnPos = rayResult.Position + Vector3.new(0, 0.5, 0)
						end
					end
					local result = CreatureService.spawn(cid, spawnPos)
					if result then
						spawned = spawned + 1
					end
				end
			end
		end
		totalSpawned = totalSpawned + spawned
	end

	spawnedZones[HUB_ZONE] = true
	print(string.format("[CreatureService] Initial spawn complete: %d total (hub zone only)", totalSpawned))
end

--- Zone별 지연 스폰 (포탈 이동 시 호출)
function CreatureService.SpawnZone(zoneName)
	if spawnedZones[zoneName] then return end
	spawnedZones[zoneName] = true

	local PER_ZONE_COUNT = math.floor((Balance.INITIAL_CREATURE_COUNT or 80) / math.max(1, #SpawnConfig.GetAllZoneNames()))
	local SPAWN_RADIUS = Balance.CREATURE_INITIAL_SPAWN_RADIUS or 300

	local zoneInfo = SpawnConfig.GetZoneInfo(zoneName)
	if not zoneInfo then return end

	local zoneCenter = zoneInfo.center
	local zoneRadius = math.min(getZoneCreatureSpawnRadius(zoneInfo, SPAWN_RADIUS), zoneInfo.radius)

	print(string.format("[CreatureService] SpawnZone '%s': %d creatures, radius %.0f", zoneName, PER_ZONE_COUNT, zoneRadius))

	local spawned = 0
	local attempts = 0
	local MAX_ATTEMPTS = PER_ZONE_COUNT * 10

	while spawned < PER_ZONE_COUNT and attempts < MAX_ATTEMPTS do
		attempts = attempts + 1
		-- ★ 10회마다 yield: 게임 루프 블로킹 방지 (포탈 등 다른 요청 처리 가능)
		if attempts % 10 == 0 then task.wait() end
		local pos = CreatureService._findMapSpawnPosition(zoneCenter, zoneRadius)
		if pos then
			local cid = SpawnConfig.GetRandomCreatureForZone(zoneName)
			if not cid then continue end
			local data = DataService.getCreature(cid)
			local groupSize = (data and data.groupSize) or 1

			for i = 1, groupSize do
				if spawned >= PER_ZONE_COUNT then break end
				local spawnPos = pos
				if groupSize > 1 and i > 1 then
					-- ★ 그룹 멤버: 오프셋 위치에서 지면 재Raycast
					-- Y좌표 미보정 시 경사 지형에서 지면 아래/위에 스폰되어 물리 발사 발생
					local ox = math.random(-8, 8)
					local oz = math.random(-8, 8)
					local rayOrigin = pos + Vector3.new(ox, 200, oz)
					local rayParams = RaycastParams.new()
					local filterList = { workspace.Terrain }
					local map = workspace:FindFirstChild("Map")
					if map then table.insert(filterList, map) end
					rayParams.FilterDescendantsInstances = filterList
					rayParams.FilterType = Enum.RaycastFilterType.Include
					local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), rayParams)
					if rayResult and rayResult.Material ~= Enum.Material.Water and rayResult.Position.Y >= SEA_LEVEL then
						spawnPos = rayResult.Position + Vector3.new(0, 0.5, 0)
					else
						spawnPos = pos -- 실패 시 원래 위치 사용
					end
				end
				local result = CreatureService.spawn(cid, spawnPos)
				if result then
					spawned = spawned + 1
				end
			end
		end
	end

	print(string.format("[CreatureService] SpawnZone '%s' complete: %d/%d creatures spawned", zoneName, spawned, PER_ZONE_COUNT))

	-- ★ 목표 대비 50% 미만이면 spawnedZones 리셋 (다음 포탈 진입 시 재시도 허용)
	if spawned < math.floor(PER_ZONE_COUNT * 0.5) then
		spawnedZones[zoneName] = nil
		warn(string.format("[CreatureService] SpawnZone '%s' under 50%% target (%d/%d), allowing retry", zoneName, spawned, PER_ZONE_COUNT))
	end
end

--- 보충 스폰 루프 (CAP 대비 부족분만 플레이어 주변에 보충 — Zone별 크리처 선택)
function CreatureService._replenishLoop()
	if creatureCount >= CREATURE_CAP then return end
	
	local deficit = CREATURE_CAP - creatureCount
	local toSpawn = math.min(deficit, 5)
	
	local players = Players:GetPlayers()
	for i = #players, 2, -1 do
		local j = math.random(i)
		players[i], players[j] = players[j], players[i]
	end
	
	for _, player in ipairs(players) do
		if toSpawn <= 0 or creatureCount >= CREATURE_CAP then break end
		
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local hrpPos = char.HumanoidRootPart.Position
			local zoneName = SpawnConfig.GetZoneAtPosition(hrpPos)
			if not zoneName then continue end

			local pos = CreatureService._findSpawnPosition(char.HumanoidRootPart)
			if not pos then
				local zoneInfo = SpawnConfig.GetZoneInfo(zoneName)
				if zoneInfo then
					local fallbackRadius = getZoneCreatureSpawnRadius(zoneInfo, Balance.CREATURE_INITIAL_SPAWN_RADIUS or 300)
					pos = CreatureService._findMapSpawnPosition(zoneInfo.center, math.min(fallbackRadius, zoneInfo.radius))
				end
			end
			if pos then
				local cid = SpawnConfig.GetRandomCreatureForZone(zoneName)
				if not cid then continue end
				local data = DataService.getCreature(cid)
				local groupSize = (data and data.groupSize) or 1
				
				for i = 1, groupSize do
					if creatureCount >= CREATURE_CAP then break end
					local spawnPos = pos
					if groupSize > 1 and i > 1 then
						local ox = math.random(-5, 5)
						local oz = math.random(-5, 5)
						local rayOrigin = pos + Vector3.new(ox, 200, oz)
						local rayParams = RaycastParams.new()
						local filterList = { workspace.Terrain }
						local mapRef = workspace:FindFirstChild("Map")
						if mapRef then table.insert(filterList, mapRef) end
						rayParams.FilterDescendantsInstances = filterList
						rayParams.FilterType = Enum.RaycastFilterType.Include
						local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), rayParams)
						if rayResult and rayResult.Material ~= Enum.Material.Water and rayResult.Position.Y >= SEA_LEVEL then
							spawnPos = rayResult.Position + Vector3.new(0, 0.5, 0)
						end
					end
					CreatureService.spawn(cid, spawnPos)
				end
				toSpawn = toSpawn - 1
			end
		end
	end
end

--- 랜덤 상태 전환 지속시간 계산
local function getRandomDuration(minT, maxT)
	return minT + math.random() * (maxT - minT)
end

--- 속도에 자연스러운 변동 추가
local function getVariedSpeed(baseSpeed)
	local variation = 1.0 + (math.random() * 2 - 1) * SPEED_VARIATION
	return baseSpeed * variation
end

--- 현재 방향 기준 자연스러운 배회 목적지 계산 (급격한 U턴 방지)
local function getSmartWanderTarget(hrpPos, currentDir, radius)
	-- 현재 방향이 없으면 랜덤
	if not currentDir or currentDir.Magnitude < 0.01 then
		local angle = math.rad(math.random(0, 359))
		return hrpPos + Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
	end
	
	-- 현재 방향에서 ±WANDER_ANGLE_RANGE 이내로 회전
	local baseAngle = math.atan2(currentDir.X, currentDir.Z)
	local deviation = math.rad(math.random(-WANDER_ANGLE_RANGE, WANDER_ANGLE_RANGE))
	local newAngle = baseAngle + deviation
	local dist = radius * (0.4 + math.random() * 0.6) -- 거리도 변동
	return hrpPos + Vector3.new(math.sin(newAngle) * dist, 0, math.cos(newAngle) * dist)
end

isSpawnPositionOccupied = function(position: Vector3, minDistance: number?): boolean
	local requiredDistance = minDistance or CREATURE_MIN_SPAWN_SEPARATION
	for _, creature in pairs(activeCreatures) do
		if creature and creature.rootPart and creature.model and creature.model.Parent then
			if (creature.rootPart.Position - position).Magnitude < requiredDistance then
				return true
			end
		end
	end
	return false
end

--- AI 업데이트 루프 (상태 머신)
function CreatureService._updateAILoop()
	local now = tick()
	
	-- [OPTIMIZATION] Inverse proximity calculation (Player -> Creature)
	-- O(P * log(C)) + O(NearbyCreatures) 대신 O(C * P) 연산 회피
	
	-- 1. 모든 크리처의 근접 데이터 초기화
	for _, creature in pairs(activeCreatures) do
		creature.minDist = 9999 -- DESPAWN_DIST보다 큰 기본값
		creature.closestPlayerPos = nil
		creature.closestPlayerRoot = nil
		creature.closestPlayerHum = nil
		creature.closestPlayerUserId = nil
		
		-- ★ [추가] 장애물 끼임 감지 초기화
		if not creature.stuckCheckPos then
			creature.stuckCheckPos = creature.rootPart.Position
			creature.stuckTime = 0
		end
	end

	-- 2. 공간 분할 색인(GetPartBoundsInRadius)을 통한 벌크 업데이트
	-- 플레이어 관점에서 주변 크리처를 찾으므로 연산량이 대폭 감소함
	local spatialParams = OverlapParams.new()
	spatialParams.FilterDescendantsInstances = { creatureFolder }
	spatialParams.FilterType = Enum.RaycastFilterType.Include
	
	local allPlayers = Players:GetPlayers()
	
	-- ★ [FIX] 리스폰 대기 중 플레이어의 마지막 위치 저장 (캐릭터 nil → 디스폰 방지)
	-- 플레이어 사망 → 캐릭터 제거 → 리스폰 대기(5초) 동안 hrp가 nil이 되면
	-- 솔로 플레이 시 모든 크리처가 minDist=9999으로 디스폰되는 버그 방지
	
	-- 퇴장한 플레이어 정리
	local activeUserIds = {}
	for _, p in ipairs(allPlayers) do
		activeUserIds[p.UserId] = true
	end
	for uid, _ in pairs(_lastKnownPlayerPos) do
		if not activeUserIds[uid] then
			_lastKnownPlayerPos[uid] = nil
		end
	end
	
	local hasAnyPresence = false
	
	for _, p in ipairs(allPlayers) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")
		local isAlive = hum and hum.Health > 0
		
		-- 현재 위치 또는 마지막으로 알려진 위치 사용
		local pPos = nil
		if hrp then
			pPos = hrp.Position
			_lastKnownPlayerPos[p.UserId] = pPos -- 위치 갱신
		else
			-- 캐릭터 없음 (사망 리스폰 대기 중) → 마지막 위치 사용
			pPos = _lastKnownPlayerPos[p.UserId]
		end
		
		if not pPos then continue end
		hasAnyPresence = true
		
		-- [FIX] 사망한 플레이어도 proximity 계산에 포함 (despawn 방지)
		-- 어그로 대상에서만 제외함 (closestPlayerHum은 살아있는 경우만 설정)
		-- ★ hrp 없어도 pPos(마지막 위치)로 proximity 계산 수행
		
		-- 플레이어 주변 300스터드(DESPAWN_DIST) 내의 크리처 파트 탐색
		local nearbyParts = workspace:GetPartBoundsInRadius(pPos, DESPAWN_DIST, spatialParams)
		
		-- 한 명의 플레이어가 같은 크리처의 여러 파트를 감지하는 것 방지
		local processedForThisPlayer = {} 
		
		for _, part in ipairs(nearbyParts) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model.Parent == creatureFolder then
				local instanceId = model:GetAttribute("InstanceId")
				if instanceId and not processedForThisPlayer[instanceId] then
					processedForThisPlayer[instanceId] = true
					
					local creature = activeCreatures[instanceId]
					if creature and creature.rootPart then
						local d = (pPos - creature.rootPart.Position).Magnitude
						if d < creature.minDist then
							creature.minDist = d
							creature.closestPlayerPos = pPos
							creature.closestPlayerRoot = hrp -- nil일 수 있음 (리스폰 대기)
							-- [FIX] 어그로 대상은 살아있는 플레이어만
							creature.closestPlayerHum = isAlive and hum or creature.closestPlayerHum
							creature.closestPlayerUserId = isAlive and p.UserId or creature.closestPlayerUserId
							
							-- [추가] 공격 판정용 머리(Head) 위치 탐색
							local head = creature.model:FindFirstChild("Head", true) or creature.model:FindFirstChild("Neck", true)
							if head then
								creature.headDist = (pPos - head.Position).Magnitude
							else
								creature.headDist = d
							end
						end
					end
				end
			end
		end
	end
	
	-- 3. 각 크리처별 AI 로직 실행 (상태 머신)
	for id, creature in pairs(activeCreatures) do
		if not creature.model or not creature.model.Parent then
			local CombatService = require(game:GetService("ServerScriptService").Server.Services.CombatService)
			if CombatService.disengageCreature then CombatService.disengageCreature(id) end
			activeCreatures[id] = nil
			creatureCount = creatureCount - 1
			continue
		end

		if (creature.currentHealth or 0) <= 0 or creature.state == "DEAD" then
			continue
		end
		
		local hrp = creature.rootPart
		if not hrp then continue end

		-- ★ 라벨 표시 타이머: Attribute 기반으로 클라이언트에서 처리
		-- (클라이언트의 CreatureHealthUIController가 LabelVisibleUntil Attribute를 감시)
		
		-- 위에서 미리 계산된 근접 데이터 활용
		local minDist = creature.minDist or 9999
		local closestPlayerPos = creature.closestPlayerPos
		local closestPlayerRoot = creature.closestPlayerRoot
		local closestPlayerHum = creature.closestPlayerHum
		local closestPlayerUserId = creature.closestPlayerUserId
		local behavior = creature.data.behavior -- AGGRESSIVE, NEUTRAL, PASSIVE
		
		-- 1.1 LOD 업데이트 주기 결정
		local updateInterval = AI_UPDATE_INTERVAL -- 기본 0.3s
		
		-- 선공형(AGGRESSIVE) 공룡은 인식 범위 밖이어도 좀 더 빠릿하게 체크하게 함
		local awarenessFactor = (behavior == "AGGRESSIVE") and 1.5 or 1.0
		local effectiveNearDist = LOD_NEAR_DIST * awarenessFactor
		local effectiveMidDist = LOD_MID_DIST * awarenessFactor

		if minDist > effectiveMidDist then
			updateInterval = 1.2 -- 1.5 -> 1.2 (약간 단축)
		elseif minDist > effectiveNearDist then
			updateInterval = 0.6 -- 0.9 -> 0.6 (상향)
		end
		
		-- 업데이트 타임아웃 체크
		if creature.lastUpdate and (now - creature.lastUpdate < updateInterval) then
			-- 이번 턴은 스킵 (연산량 절감)
			continue
		end
		creature.lastUpdate = now
		
		-- 2. Despawn Check
		-- [FIX] 플레이어가 1명이라도 있을 때만 Despawn 체크 수행 (서버 시작 시 멸종 방지)
		-- 또한 minDist가 9999(초기값)라는 것은 주변에 플레이어가 아예 없다는 뜻임.
		if #allPlayers > 0 and minDist > DESPAWN_DIST then
			local recentlyEngaged = creature.lastDamagedAt and ((now - creature.lastDamagedAt) < CREATURE_DESPAWN_GRACE_AFTER_COMBAT)
			local isWounded = creature.currentHealth and creature.maxHealth and creature.currentHealth < creature.maxHealth
			local isInActiveCombatState = creature.state == "CHASE" or creature.state == "ATTACK" or creature.state == "FLEE" or creature.state == "STUNNED"
			if not recentlyEngaged and not isWounded and not isInActiveCombatState then
				local CombatService = require(game:GetService("ServerScriptService").Server.Services.CombatService)
				if CombatService.disengageCreature then CombatService.disengageCreature(id) end
				creature.model:Destroy()
				activeCreatures[id] = nil
				creatureCount = creatureCount - 1
				continue
			end
		end
		
		-- 2.5 Torpor Decay (Phase 6)
		local dt = now - creature.lastUpdateAt
		creature.lastUpdateAt = now
		
		if creature.currentTorpor > 0 then
			creature.currentTorpor = math.max(0, creature.currentTorpor - (TORPOR_DECAY_RATE * dt))
			
			-- ★ Torpor Attribute 갱신 (클라이언트 UI 반영)
			if creature.model then
				creature.model:SetAttribute("CurrentTorpor", creature.currentTorpor)
			end
			
			-- 기절 회복 체크
			if creature.state == "STUNNED" and creature.currentTorpor <= STUN_RECOVERY_THRESHOLD then
				setCreatureState(creature, "IDLE")
				-- ★ 기절 해제: Anchored 해제 + 이동 능력 복원
				if creature.rootPart then
					creature.rootPart.Anchored = false
					-- CanCollide는 false 유지 (GetPropertyChangedSignal 리스너가 관리)
					-- true로 복원하면 Humanoid 충돌로 플레이어 지형 끌림 발생
				end
				creature.humanoid.WalkSpeed = creature.data.walkSpeed or 10
				creature.humanoid.JumpPower = 5
				-- ★ 큰 초식공룡은 AutoRotate=false 유지 (수동 Lerp 회전)
				local cId = creature.creatureId
				local isLargeCreature = (cId == "TRICERATOPS" or cId == "STEGOSAURUS" or cId == "PARASAUR")
				creature.humanoid.AutoRotate = not isLargeCreature
				print(string.format("[CreatureService] %s recovered from STUN!", id))
			end
		end

		-- [추가] 베이스 팰 예외 처리
		if creature.model:GetAttribute("IsBasePal") then
			-- 베이스 팰은 야생 AI 로직(Despawn, Hunger, Aggro 등)을 타지 않음
			-- 오직 TASK 상태에서의 이동만 처리함
			if creature.state == "TASK" and creature.targetPosition then
				local target = creature.targetPosition
				local wpReachDist = getWaypointReachDist(creature)
				local needsNewPath = false
				if not creature.pathData then
					needsNewPath = true
				elseif (creature.pathData.targetPos - target).Magnitude > PATH_RECALC_DIST then
					needsNewPath = true
				elseif creature.pathData.currentIndex > #creature.pathData.waypoints then
					needsNewPath = true
				end
				
				-- ★ PathfindingService를 사용하여 베이스 내 장애물(벽, 시설물) 우회
				if needsNewPath then
					if not creature.lastPathCompute or (now - creature.lastPathCompute) >= 1.0 then
						creature.lastPathCompute = now
						local startPos = hrp.Position
						local targetPos = target
						
						-- 장애물 유무 확인 (Raycast)
						local rayParams = RaycastParams.new()
						rayParams.FilterDescendantsInstances = { creature.model, creatureFolder, workspace.Terrain }
						rayParams.FilterType = Enum.RaycastFilterType.Exclude
						local rayResult = workspace:Raycast(startPos, (targetPos - startPos), rayParams)
						local isObstructed = rayResult and (rayResult.Position - targetPos).Magnitude > 3
						
						if isObstructed then
							-- 장애물 있음 → Pathfinding 사용
							task.spawn(function()
								local _, cSize = creature.model:GetBoundingBox()
								local agentRadius = math.clamp(math.max(cSize.X, cSize.Z) / 2, 2, 8)
								local agentHeight = math.clamp(cSize.Y, 4, 12)
								
								local path = PathfindingService:CreatePath({
									AgentRadius = agentRadius,
									AgentHeight = agentHeight,
									AgentCanJump = false, -- ★ 점프 경로 비활성: 자연스러운 도보 이동
									AgentStepHeight = math.clamp(agentHeight * 0.5, 3, 8), -- ★ 높은 스텝: 단차를 걸어서 넘기
								})
								local ok = pcall(function() path:ComputeAsync(startPos, targetPos) end)
								local latest = activeCreatures[creature.id]
								if not latest then return end
								
								if ok and path.Status == Enum.PathStatus.Success then
									local waypoints = path:GetWaypoints()
									local startIndex = (#waypoints >= 2) and 2 or 1
									latest.pathData = {
										waypoints = waypoints,
										currentIndex = startIndex,
										targetPos = targetPos,
										lastRecalc = now,
									}
								else
									-- 경로 계산 실패 시 직선 폴백
									latest.pathData = { waypoints = {{Position = targetPos}}, currentIndex = 1, targetPos = targetPos, lastRecalc = now }
								end
							end)
						else
							-- 장애물 없음 → 직선 이동
							creature.pathData = { waypoints = {{Position = targetPos}}, currentIndex = 1, targetPos = targetPos, lastRecalc = now }
						end
					end
				end
				
				-- 웨이포인트 이동 실행
				if creature.pathData and creature.pathData.currentIndex <= #creature.pathData.waypoints then
					local wp = creature.pathData.waypoints[creature.pathData.currentIndex]
					local wpPos = wp.Position or wp
					if not creature.lastMoveToPos or (creature.lastMoveToPos - wpPos).Magnitude > MOVETO_RETHRESHOLD then
						humanoid:MoveTo(wpPos)
						creature.lastMoveToPos = wpPos
						-- ★ [추가] MoveTo 호출 시 stuck 상태 초기화
						creature.stuckTime = 0
						creature.stuckCheckPos = nil
					end
					
					-- ★ [추가] 장애물 끼임 감지 및 점프 극복
					if humanoid.MoveDirection.Magnitude > 0 then
						if not creature.stuckCheckPos then
							creature.stuckCheckPos = hrp.Position
							creature.stuckTime = 0
						else
							local distMoved = (hrp.Position - creature.stuckCheckPos).Magnitude
							if distMoved < 0.2 then
								-- 이동 명령이 있지만 움직이지 않음
								creature.stuckTime = creature.stuckTime + AI_UPDATE_INTERVAL
								if creature.stuckTime > 0.5 then  -- 0.5초 이상 제자리
									-- 점프로 장애물 극복 시도
									humanoid.Jump = true
									creature.stuckTime = 0
								end
							else
								-- 정상 이동 중
								creature.stuckTime = 0
								creature.stuckCheckPos = hrp.Position
							end
						end
					end
					
					if (hrp.Position - wpPos).Magnitude < wpReachDist then
						creature.pathData.currentIndex = creature.pathData.currentIndex + 1
						-- ★ 목표 도달 확인: 모든 웨이포인트 완료 시 IDLE로 복귀
						if creature.pathData.currentIndex > #creature.pathData.waypoints then
							creature.targetPosition = nil
							creature.pathData = nil
							setCreatureState(creature, "IDLE")
							humanoid:MoveTo(hrp.Position)
							creature.lastMoveToPos = hrp.Position
						end
					end
				end
			else
				humanoid:MoveTo(hrp.Position) -- 정지
			end
			continue
		end

		-- ★ 쓰러짐/사망 상태면 AI 로직 전체 스킵 (공격, 이동, 상태 전환 전부 차단)
		if creature.state == "DEAD" then
			continue
		end

		-- 기절 상태면 AI 로직 스킵 (이동 전)
		if creature.state == "STUNNED" then
			creature.humanoid:MoveTo(hrp.Position) -- 정지
			continue
		end
		
		-- 3. State Machine
		local detectRange = creature.data.detectRange or 20
		
		-- BloodSmell 어그로 배율 적용 (Phase 4-4)
		if DebuffService and closestPlayerUserId then
			detectRange = detectRange * DebuffService.getAggroMultiplier(closestPlayerUserId)
		end
		
		local newState = creature.state
		local chaseDuration = (creature.chaseStartTime and (now - creature.chaseStartTime)) or 0
		
		-- 랜덤 상태 지속시간 (최초 또는 상태 변경 시 설정)
		if not creature.stateDuration then
			creature.stateDuration = getRandomDuration(IDLE_MIN_TIME, IDLE_MAX_TIME)
		end
		local elapsed = now - creature.lastStateChange
		
		if behavior == "AGGRESSIVE" then
			-- ATTACK 상태에서 공격 완료 후 CHASE로 자동 복귀
			if creature.state == "ATTACK" then
				local isStillAttacking = creature.attackingUntil and now < creature.attackingUntil
				if not isStillAttacking then
					newState = "CHASE"
				end
			elseif creature.state == "CHASE" then
				if chaseDuration >= AGGRO_TIMEOUT or minDist > MAX_CHASE_DISTANCE then
					newState = "WANDER"
					creature.chaseStartTime = nil
					creature.lostAggroAt = now -- 어그로 상실 시점 기록
				end
			elseif minDist <= detectRange then
				-- 전투 중인 플레이어는 선공 대상에서 제외
				local playerInCombat = false
				if closestPlayerUserId then
					local CS = require(game:GetService("ServerScriptService").Server.Services.CombatService)
					if CS.getPlayerCombatTarget and CS.getPlayerCombatTarget(closestPlayerUserId) then
						playerInCombat = true
					end
				end
				
				-- 어그로 쿨다운 체크 (한번 따돌리면 잠시 동안 다시 인식 못하게 함)
				local isCold = not creature.lostAggroAt or (now - creature.lostAggroAt > AGGRO_COOLDOWN)
				
				if isCold and not playerInCombat then
					-- 공격 사거리 내: CHASE 전환 건너뛰고 직접 공격 (달리기 애니메이션 방지)
					local immediateRange = (creature.data.attackRange or 5) * 1.3
					local atkReady = not creature.lastAttackTime or (now - creature.lastAttackTime >= (creature.data.attackCooldown or CREATURE_ATTACK_COOLDOWN))
					if minDist <= immediateRange and atkReady then
						-- CHASE 없이 직접 공격 플래그 (섹션 5에서 처리)
						creature._directAttack = true
						if not creature.chaseStartTime then
							creature.chaseStartTime = now
						end
					else
						newState = "CHASE"
						if not creature.chaseStartTime then
							creature.chaseStartTime = now
						end
					end
				end
			elseif creature.state == "IDLE" and elapsed > creature.stateDuration then
				newState = "WANDER"
			elseif creature.state == "WANDER" and elapsed > creature.stateDuration then
				newState = "IDLE"
			end
		else -- NEUTRAL, PASSIVE
			if creature.state == "ATTACK" then
				local isStillAttacking = creature.attackingUntil and now < creature.attackingUntil
				if not isStillAttacking then
					newState = "CHASE"
				end
			elseif creature.state == "CHASE" then
				if chaseDuration >= AGGRO_TIMEOUT or minDist > MAX_CHASE_DISTANCE then
					newState = "WANDER"
					creature.chaseStartTime = nil
				end
			elseif creature.state == "FLEE" then
				if elapsed > 6 + math.random() * 4 then -- 6~10초 후 WANDER로
					newState = "WANDER"
				end
			elseif creature.state == "IDLE" and elapsed > creature.stateDuration then
				newState = "WANDER"
			elseif creature.state == "WANDER" and elapsed > creature.stateDuration then
				newState = "IDLE"
			end
		end
		
		-- 상태 변경 처리
		if newState ~= creature.state then
			local oldState2 = creature.state
			setCreatureState(creature, newState)

			-- ★ 전투 진입 사운드 (IDLE/WANDER → CHASE/FLEE 전환 시 한 번)
			if (oldState2 == "IDLE" or oldState2 == "WANDER") and (newState == "CHASE" or newState == "FLEE") then
				local cry = creature.rootPart:FindFirstChild("CombatCry")
				if cry and cry.SoundId ~= "" then
					cry:Play()
				end
			end

			-- 새 상태에 맞는 랜덤 지속시간 설정
			if newState == "IDLE" then
				creature.stateDuration = getRandomDuration(IDLE_MIN_TIME, IDLE_MAX_TIME)
			elseif newState == "WANDER" then
				creature.stateDuration = getRandomDuration(WANDER_MIN_TIME, WANDER_MAX_TIME)
			end
			-- ★ 상태 전환 시 MoveTo 캐시 초기화 (새 상태의 첫 MoveTo가 즉시 실행되도록)
			creature.lastMoveToPos = nil
		end
		
		-- 4. Behavior Execution
		local humanoid = creature.humanoid
		local attackRange = creature.data.attackRange or 5
		
		-- [수정] 머리(Head) 기준 사거리 체크 적용 (더 실감나는 이빨 판정)
		local headDist = creature.headDist or minDist
		local isInAttackRange = (headDist <= attackRange)
		
		-- ============================================
		-- 물 진입 방지 (최우선 처리)
		-- ============================================
		local isInWater = CreatureService._isWaterPosition(hrp.Position)
		local isNearWater = not isInWater and CreatureService._isNearWater(hrp.Position)
		
		if isNearWater and creature.state ~= "IDLE" then
			-- 물 근처에 접근: 이동 취소 + 육지 쪽으로 걸어서 후퇴
			creature.targetPosition = nil
			creature.pathData = nil
			local landDir = CreatureService._findLandDirection(hrp.Position)
			if landDir then
				local retreatTarget = hrp.Position + landDir * (WATER_MARGIN + 5)
				humanoid:MoveTo(retreatTarget)
			end
			-- ★ WANDER 상태로 전환 (걸어서 이동 애니메이션 유지)
			setCreatureState(creature, "WANDER")
			creature.stateDuration = getRandomDuration(IDLE_MIN_TIME, IDLE_MAX_TIME)
			continue
		end
		
		if isInWater then
			-- ★ 물에 빠진 크리처 즉시 구출 (텔레포트)
			-- Swimming 상태가 비활성화되어 MoveTo로는 물에서 이동 불가
			-- 즉시 안전한 육지로 텔레포트하여 갇힘 방지
			local landDir = CreatureService._findLandDirection(hrp.Position)
			if landDir then
				-- 육지 방향으로 Raycast하여 정확한 지면 위치 찾기
				local searchDist = 80
				local rescued = false
				for _, dist in ipairs({20, 40, 60, 80}) do
					local checkPos = hrp.Position + landDir * dist
					local rayParams = RaycastParams.new()
					rayParams.FilterDescendantsInstances = { workspace.Terrain }
					rayParams.FilterType = Enum.RaycastFilterType.Include
					local rayResult = workspace:Raycast(checkPos + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), rayParams)
					if rayResult and rayResult.Material ~= Enum.Material.Water and rayResult.Position.Y >= SEA_LEVEL then
						local safePos = rayResult.Position + Vector3.new(0, 2, 0)
						if not CreatureService._isNearWater(safePos) then
							hrp.CFrame = CFrame.new(safePos)
							hrp.AssemblyLinearVelocity = Vector3.zero
							rescued = true
							break
						end
					end
				end
				if not rescued then
					-- 가까운 육지 못 찾음 → 스폰 존 중심으로 텔레포트
					local zoneName = SpawnConfig.GetZoneAtPosition(hrp.Position)
					local zoneInfo = zoneName and SpawnConfig.GetZoneInfo(zoneName)
					if zoneInfo and zoneInfo.spawnPoint then
						hrp.CFrame = CFrame.new(zoneInfo.spawnPoint + Vector3.new(0, 3, 0))
						hrp.AssemblyLinearVelocity = Vector3.zero
					else
						hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0)
						hrp.AssemblyLinearVelocity = Vector3.zero
					end
				end
			else
				-- 육지 방향 자체를 못 찾음 → 스폰 존 중심으로 텔레포트
				local zoneName = SpawnConfig.GetZoneAtPosition(hrp.Position)
				local zoneInfo = zoneName and SpawnConfig.GetZoneInfo(zoneName)
				if zoneInfo and zoneInfo.spawnPoint then
					hrp.CFrame = CFrame.new(zoneInfo.spawnPoint + Vector3.new(0, 3, 0))
					hrp.AssemblyLinearVelocity = Vector3.zero
				else
					hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0)
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
			end
			setCreatureState(creature, "IDLE")
			humanoid:MoveTo(hrp.Position)
			creature.targetPosition = nil
			creature.pathData = nil
			continue -- ★ 물 탈출 로직 후 나머지 AI 로직 스킵
		elseif creature.state == "CHASE" or creature.state == "WANDER" or creature.state == "FLEE" then
			local currentZone = getProtectedZoneInfo(hrp.Position)
			if currentZone then
				local center = currentZone.centerPosition or hrp.Position
				local radius = tonumber(currentZone.radius) or 30
				local dir = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
				if dir.Magnitude < 0.1 then
					dir = Vector3.new((math.random() - 0.5), 0, (math.random() - 0.5))
				end
				setCreatureState(creature, "FLEE")
				creature.stateDuration = getRandomDuration(WANDER_MIN_TIME, WANDER_MAX_TIME)
				creature.chaseStartTime = nil
				if dir.Magnitude > 0.1 then
					local escapeTarget = center + dir.Unit * (radius + 10)
					creature.targetPosition = CreatureService._getSafeTarget(hrp.Position, escapeTarget)
				else
					creature.targetPosition = nil
				end
			end

			-- [목적지 결정]
			local target = nil
			if creature.state == "CHASE" and closestPlayerPos then
				-- 추격: 목표가 물 근처이면 추격 포기
				if CreatureService._isNearWater(closestPlayerPos) or getProtectedZoneInfo(closestPlayerPos) then
					setCreatureState(creature, "WANDER")
					creature.stateDuration = getRandomDuration(WANDER_MIN_TIME, WANDER_MAX_TIME)
					creature.targetPosition = nil
				else
					target = closestPlayerPos
				end
			elseif creature.state == "WANDER" then
				if not creature.targetPosition or (hrp.Position - creature.targetPosition).Magnitude < 6 then
					local currentDir = creature.lastMoveDir or Vector3.zero
					local wTarget
					local attempts = 0
					repeat
						wTarget = getSmartWanderTarget(hrp.Position, currentDir, WANDER_RADIUS)
						attempts = attempts + 1
					until not CreatureService._isNearWater(wTarget) or attempts >= 10
					creature.targetPosition = CreatureService._getSafeTarget(hrp.Position, wTarget)
					
					local diff = creature.targetPosition - hrp.Position
					if diff.Magnitude > 0.1 then creature.lastMoveDir = Vector3.new(diff.X, 0, diff.Z).Unit end
					creature.wanderSpeed = getVariedSpeed(creature.data.walkSpeed or 10)
				end
				target = creature.targetPosition
			elseif creature.state == "FLEE" and closestPlayerPos then
				-- 도망: 플레이어 반대 방향으로 주기적 갱신
				if not creature.targetPosition or (now - (creature.lastFleeUpdate or 0) > 1.0) then
					creature.lastFleeUpdate = now
					local diff = hrp.Position - closestPlayerPos
					local dir = diff.Magnitude > 0.1 and diff.Unit or Vector3.new(1,0,0)
					local fTarget = hrp.Position + dir * WANDER_RADIUS * 2
					if CreatureService._isNearWater(fTarget) then
						local rot = Vector3.new(dir.Z, 0, -dir.X)
						fTarget = hrp.Position + rot * WANDER_RADIUS * 2
					end
					creature.targetPosition = CreatureService._getSafeTarget(hrp.Position, fTarget)
				end
				target = creature.targetPosition
			end

			-- [이동 실행 (Pathfinding)]
			if target then
				local targetZone = getProtectedZoneInfo(target)
				if targetZone then
					local center = targetZone.centerPosition or target
					local radius = tonumber(targetZone.radius) or 30
					local escapeDir = hrp.Position - center
					if escapeDir.Magnitude < 0.1 then
						escapeDir = Vector3.new((math.random() - 0.5), 0, (math.random() - 0.5))
					end
					if escapeDir.Magnitude > 0.1 then
						local fallbackTarget = center + escapeDir.Unit * (radius + 8)
						if not CreatureService._isNearWater(fallbackTarget) then
							target = fallbackTarget
							creature.targetPosition = target
						else
							target = nil
							creature.targetPosition = nil
							humanoid:MoveTo(hrp.Position)
						end
					end
				end

				if not target then
					continue
				end

				-- [추가] 공격 사거리 내에 있거나 공격 애니메이션 중이면 정지 (미끄러짐 방지)
				-- ★ 정지 거리 = attackRange * 1.3: 공격 사거리 직전에 멈춰서 플레이어와 겹치지 않음
				local stopRange = attackRange * 1.3
				-- ★ 공격 직후 쿨다운 대기 중에도 정지 유지 (겹치며 따라가기 방지)
				local isInCooldown = creature.lastAttackTime and (now - creature.lastAttackTime < (creature.data.attackCooldown or CREATURE_ATTACK_COOLDOWN))
				local shouldStop = (headDist <= stopRange) or (creature.attackingUntil and now < creature.attackingUntil) or (isInCooldown and headDist <= stopRange * 2)
				local isAttacking = creature.attackingUntil and now < creature.attackingUntil
				if (creature.state == "CHASE" or creature.state == "ATTACK") and shouldStop then
					-- ★ 공격 중 WalkSpeed=0: Humanoid 내부 물리가 이동력을 재적용하는 것을 원천 차단
					humanoid.WalkSpeed = 0
					humanoid:MoveTo(hrp.Position)
					creature.lastMoveToPos = hrp.Position
					-- ★ 관성 제거: 수평 속도 즉시 0으로
					hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
					-- ★ 공격 중에는 회전 금지 (인디케이터 방향 고정)
					if not isAttacking and closestPlayerPos then
						local dir = (closestPlayerPos - hrp.Position) * Vector3.new(1, 0, 1)
						if dir.Magnitude > 0.1 then
							local targetCF = CFrame.lookAt(hrp.Position, hrp.Position + dir.Unit)
							-- ★ 크리처 체형별 회전 속도: 큰 초식공룡은 느리게, 소형/포식자는 빠르게
							local cId = creature.creatureId
							local isLarge = (cId == "TRICERATOPS" or cId == "STEGOSAURUS" or cId == "PARASAUR")
							local baseTurn = isLarge and 0.5 or 3.0
							local turnAlpha = math.clamp(updateInterval * baseTurn, 0.02, isLarge and 0.08 or 0.4)
							hrp.CFrame = hrp.CFrame:Lerp(targetCF, turnAlpha)
						end
					end
				else
					-- ★ 공격 모션 중이면 경로 이동 차단 (같은 프레임에서 attackingUntil 셋 전에 도달한 경우 방어)
					if creature.attackingUntil and now < creature.attackingUntil then
						humanoid.WalkSpeed = 0
						humanoid:MoveTo(hrp.Position)
						hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
					else
					-- 1. 경로 재계산 조건 체크
					local needsNewPath = false
					if not creature.pathData then
						needsNewPath = true
					elseif (creature.pathData.targetPos - target).Magnitude > PATH_RECALC_DIST then
						needsNewPath = true
					elseif creature.pathData.currentIndex > #creature.pathData.waypoints then
						needsNewPath = true
					elseif now - creature.pathData.lastRecalc > 2.0 then
						needsNewPath = true
					end

					if needsNewPath then
						-- [OPTIMIZATION] Pathfinding Rate Limit - 초당 1회 이하로 호출 제한 (CPU 스파이크 방지)
						if creature.lastPathCompute and (now - creature.lastPathCompute) < 1.0 then
							needsNewPath = false
						end
						if creature.pathComputeInFlight then
							needsNewPath = false
						end
					end

					if needsNewPath then
						local rayParams = RaycastParams.new()
						rayParams.FilterDescendantsInstances = { creature.model, creatureFolder, workspace.Terrain }
						rayParams.FilterType = Enum.RaycastFilterType.Exclude
						local rayResult = workspace:Raycast(hrp.Position, (target - hrp.Position), rayParams)
						
						local isObstructed = false
						if rayResult and (rayResult.Position - target).Magnitude > 3 then isObstructed = true end

						if isObstructed then
							creature.lastPathCompute = now
							creature.pathComputeInFlight = true
							-- ★ 백그라운드 스왑: 기존 경로를 유지한 채 이동 계속
							-- ComputeAsync 완료 후 pathData를 원자적으로 교체하여 끊김 제거
							if not creature.pathData then
								-- 기존 경로 없음 → 대상 방향으로 직선 이동 유지
								if not creature.lastMoveToPos or (creature.lastMoveToPos - target).Magnitude > MOVETO_RETHRESHOLD then
									humanoid:MoveTo(target)
									creature.lastMoveToPos = target
								end
							end
							
							creature.pathReqToken = (creature.pathReqToken or 0) + 1
							local reqToken = creature.pathReqToken
							local creatureId = creature.id
							local startPos = hrp.Position
							local targetPos = target
							local recalcAt = now

							task.spawn(function()
								-- ★ 크리처 바운딩박스 기반 동적 NavMesh 파라미터
							local ok2, _, cSize = pcall(function() return creature.model:GetBoundingBox() end)
							if not ok2 or not cSize then
								local latest = activeCreatures[creatureId]
								if latest then latest.pathComputeInFlight = false end
								return
							end
							local agentRadius = math.clamp(math.max(cSize.X, cSize.Z) / 2, 2, 12)
							local agentHeight = math.clamp(cSize.Y, 4, 20)
								
								local path = PathfindingService:CreatePath({
									AgentRadius = agentRadius,
									AgentHeight = agentHeight,
									AgentCanJump = false, -- ★ 점프 경로 비활성: 자연스러운 도보 이동
									AgentStepHeight = math.clamp(agentHeight * 0.5, 3, 8), -- ★ 높은 스텝: 단차를 걸어서 넘기
								})

								local ok = pcall(function()
									path:ComputeAsync(startPos, targetPos)
								end)

								local latest = activeCreatures[creatureId]
								if not latest then
									return
								end
								if latest.pathReqToken ~= reqToken then
									return
								end

								latest.pathComputeInFlight = false
								if ok and path.Status == Enum.PathStatus.Success then
									local waypoints = path:GetWaypoints()
									local startIndex = (#waypoints >= 2) and 2 or 1
									latest.pathData = {
										waypoints = waypoints,
										currentIndex = startIndex,
										targetPos = targetPos,
										lastRecalc = recalcAt,
									}
								else
									-- 실패 시 쿨다운을 위해 더미 경로 생성
									latest.pathData = {
										waypoints = {{Position = targetPos}},
										currentIndex = 1,
										targetPos = targetPos,
										lastRecalc = recalcAt,
									}
								end
							end)
						else
							-- 3. 장애물 없음 → 직접 이동 (최우선)
							creature.pathData = nil
							-- ★ MoveTo 반복 호출 방지: 목표가 유의미하게 바뀔 때만 재호출
							if not creature.lastMoveToPos or (creature.lastMoveToPos - target).Magnitude > MOVETO_RETHRESHOLD then
								humanoid:MoveTo(target)
								creature.lastMoveToPos = target
							end
						end
					end
					
					-- 1.5 웨이포인트 이동 (pathData가 있을 때만)
					if creature.pathData and creature.pathData.currentIndex <= #creature.pathData.waypoints then
						local wp = creature.pathData.waypoints[creature.pathData.currentIndex]
						-- 웨이포인트가 물 근처이면 스킵
						if CreatureService._isNearWater(wp.Position) then
							creature.pathData = nil
							creature.targetPosition = nil
							humanoid:MoveTo(hrp.Position) -- 정지
							creature.lastMoveToPos = hrp.Position
						else
							-- ★ 같은 웨이포인트에 대해 반복 호출 방지
							if not creature.lastMoveToPos or (creature.lastMoveToPos - wp.Position).Magnitude > MOVETO_RETHRESHOLD then
								humanoid:MoveTo(wp.Position)
								creature.lastMoveToPos = wp.Position
							end
							-- ★ 큰 초식공룡 이동 중 부드러운 회전 (AutoRotate=false 대체)
							local cId2 = creature.creatureId
							local isLarge2 = (cId2 == "TRICERATOPS" or cId2 == "STEGOSAURUS" or cId2 == "PARASAUR")
							if isLarge2 then
								local moveDir = (wp.Position - hrp.Position) * Vector3.new(1, 0, 1)
								if moveDir.Magnitude > 0.5 then
									local moveCF = CFrame.lookAt(hrp.Position, hrp.Position + moveDir.Unit)
									hrp.CFrame = hrp.CFrame:Lerp(moveCF, math.clamp(updateInterval * 1.0, 0.03, 0.1))
								end
							end
							-- ★ Jump 웨이포인트 무시: 경사면에서 폴짝거림 방지, MaxSlopeAngle=89로 도보 이동
							local wpReach = getWaypointReachDist(creature)
							if (hrp.Position - wp.Position).Magnitude < wpReach then
								creature.pathData.currentIndex = creature.pathData.currentIndex + 1
							end
						end
					elseif not creature.pathData then
						-- 직접 이동 중인 경우 — pathData nil이므로 위에서 이미 MoveTo 처리됨
						-- ★ 중복 MoveTo 호출 제거 (같은 틱에서 이미 호출했으므로 스킵)
					end
					end -- 공격 모션 중 경로 이동 차단 end
				end
			end

			-- 3. 속도 설정
			if creature.state == "CHASE" or creature.state == "ATTACK" then
				local stopRange2 = attackRange * 1.3
				local isInCooldown2 = creature.lastAttackTime and (now - creature.lastAttackTime < (creature.data.attackCooldown or CREATURE_ATTACK_COOLDOWN))
				if (headDist <= stopRange2) or (creature.attackingUntil and now < creature.attackingUntil) or (isInCooldown2 and headDist <= stopRange2 * 2) then
					humanoid.WalkSpeed = 0
				else
					humanoid.WalkSpeed = creature.data.runSpeed or 20
				end
			elseif creature.state == "FLEE" then
				humanoid.WalkSpeed = (creature.data.runSpeed or 20) * 1.2
			else
				humanoid.WalkSpeed = creature.wanderSpeed or (creature.data.walkSpeed or 10)
			end
			
		elseif creature.state == "IDLE" then
			creature.targetPosition = nil
			humanoid:MoveTo(hrp.Position) -- 정지
			
			-- IDLE 시 가까운 플레이어가 있으면 머리 회전
			if minDist < 80 then
				-- IDLE 시 좌우 둘러보기 (직접 CFrame 조작 대신 회전 유도)
				if not creature.idleLookTime or (now - creature.idleLookTime > 3 + math.random() * 4) then
					creature.idleLookTime = now
					local lookAngle = math.rad(math.random(-60, 60))
					local lookDir = (CFrame.Angles(0, lookAngle, 0) * hrp.CFrame.LookVector).Unit
					local lookTarget = hrp.Position + lookDir * 5
					humanoid:MoveTo(lookTarget) -- 살짝 몸을 틀게 함 (물리 엔진 존중)
				end
			end
		end
		
		-- 5. Creature -> Player/Structure Damage (Phase 11-4)
		-- AGGRESSIVE: IDLE/WANDER에서도 공격 사거리 내면 직접 공격 가능 (달리기 불필요)
		local canDoAttack = (creature.state == "CHASE") or (creature._directAttack == true)
		local wasDirectAttack = creature._directAttack
		creature._directAttack = nil
		if canDoAttack then
			if getProtectedZoneInfo(hrp.Position) then
				setCreatureState(creature, "FLEE")
				creature.chaseStartTime = nil
				continue
			end

			-- 직접 공격: 플레이어를 향해 회전
			if wasDirectAttack and closestPlayerPos then
				local faceDir = (closestPlayerPos - hrp.Position) * Vector3.new(1, 0, 1)
				if faceDir.Magnitude > 0.1 then
					hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + faceDir.Unit)
				end
			end

			local dmg = creature.data.damage or 0
			if dmg > 0 then
				-- ★ 공격 판정 거리 = 정지 거리와 동일 (attackRange * 1.3)
				local attackTriggerRange = attackRange * 1.3
				if closestPlayerPos and (headDist <= attackTriggerRange) then
					if getProtectedZoneInfo(closestPlayerPos) then
						setCreatureState(creature, "FLEE")
						creature.chaseStartTime = nil
						continue
					end

					if not creature.lastAttackTime or (now - creature.lastAttackTime >= (creature.data.attackCooldown or CREATURE_ATTACK_COOLDOWN)) then
						creature.lastAttackTime = now
						
						-- ★ 텔레그래프 공격 패턴 선택
						local attacks = creature.data.attacks
						local chosenAttack = nil
						if attacks and #attacks > 0 then
							-- 사거리 내 사용 가능한 패턴 중 랜덤 선택
							local validAttacks = {}
							for _, atk in ipairs(attacks) do
								local atkRange = atk.range or atk.radius or atk.length or attackRange
								if headDist <= atkRange * 1.5 then
									table.insert(validAttacks, atk)
								end
							end
							if #validAttacks > 0 then
								chosenAttack = validAttacks[math.random(1, #validAttacks)]
							else
								chosenAttack = attacks[1] -- 폴백: 첫 번째 패턴
							end
						end
						
						-- attacks 배열이 없는 크리처 → 레거시 즉시 공격 (초원섬 크리처 등)
						if not chosenAttack then
							local attackDelay = creature.data.attackDelay or 0.5
							creature.attackingUntil = now + attackDelay + NETWORK_ANIM_BUFFER

							if NetController then
								NetController.FireAllClients("Creature.Attack.Play", {
									instanceId = id,
									attackRange = attackRange,
									creaturePos = {hrp.Position.X, hrp.Position.Y, hrp.Position.Z},
									creatureLook = {hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Y, hrp.CFrame.LookVector.Z},
									attackDelay = creature.data.attackDelay or 0.5,
								})
							end

							if closestPlayerHum and closestPlayerHum.Health > 0 then
								task.delay(attackDelay, function()
									local currentCreature = activeCreatures[id]
									if not currentCreature or not currentCreature.model or not currentCreature.model.Parent then return end
									if (currentCreature.currentHealth or 0) <= 0 or currentCreature.state == "DEAD" then return end

									local player = Players:GetPlayerByUserId(closestPlayerUserId)
									if not player then return end
									local playerChar = player.Character
									local playerHrp = playerChar and playerChar:FindFirstChild("HumanoidRootPart")
									if not playerHrp then return end
									if getProtectedZoneInfo(playerHrp.Position) then return end

									local CombatService = require(game:GetService("ServerScriptService").Server.Services.CombatService)
									if CombatService.isPlayerInvulnerable(closestPlayerUserId) then return end

									local dist = (playerHrp.Position - currentCreature.rootPart.Position).Magnitude
									if dist <= attackRange * 1.3 then
										CombatService.damagePlayer(closestPlayerUserId, dmg, currentCreature.rootPart.Position, id)
									end
									
									-- 범위 내 소환된 팰에게도 데미지
									local PartyService = require(game:GetService("ServerScriptService").Server.Services.PartyService)
									local summon = PartyService.getSummon(closestPlayerUserId)
									if summon and summon.rootPart and summon.currentHP > 0 then
										local palDist = (summon.rootPart.Position - currentCreature.rootPart.Position).Magnitude
										if palDist <= attackRange * 1.5 then
											PartyService.damagePal(closestPlayerUserId, dmg, currentCreature.rootPart.Position)
										end
									end
								end)
							end
							-- 직접 공격 후 CHASE 상태로 전환 (후속 추격 행동을 위해)
							if creature.state ~= "CHASE" then
								setCreatureState(creature, "CHASE")
							end
							continue
						end
						
						-- 선행/공격 시간 계산
						local windupTime = chosenAttack.windupTime or 0.5
						local attackTime = chosenAttack.attackTime or 0.5
						local totalTime = windupTime + attackTime
						creature.attackingUntil = now + totalTime + NETWORK_ANIM_BUFFER

						-- 텔레그래프 공격 시작 → ATTACK 상태로 전환 (클라이언트에서 RUN 재생 방지)
						setCreatureState(creature, "ATTACK")

						-- ★ 텔레그래프 시작 즉시 이동 정지 (인디케이터 위치 고정)
						humanoid.WalkSpeed = 0
						humanoid:MoveTo(hrp.Position)
						hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
						
						local attackDamage = (chosenAttack and chosenAttack.damage) or dmg
						
						if closestPlayerHum and closestPlayerHum.Health > 0 then
							-- 공격 선언 시점의 크리처 방향 기록 (PROJECTILE용 타겟 위치 포함)
							local lockedCreaturePos = hrp.Position
							local lockedCreatureLook = hrp.CFrame.LookVector
							local lockedTargetPos = closestPlayerPos
								
								-- ★ CONE 패턴: 머리(Head) 위치를 기준점으로 사용
								local lockedAttackOrigin = lockedCreaturePos
								if chosenAttack and chosenAttack.pattern == "CONE" then
									local headPart = nil
									for _, desc in ipairs(creature.model:GetDescendants()) do
										if desc:IsA("BasePart") and desc.Name:match("^Head") then
											headPart = desc
											break
										end
									end
									if headPart then
										lockedAttackOrigin = headPart.Position
									end
								end
							
							-- ★ 클라이언트에 텔레그래프 데이터 전송 (선행 모션 + 범위 표시)
							if NetController then
								NetController.FireAllClients("Creature.Attack.Telegraph", {
									instanceId = id,
									creatureId = creature.creatureId,
									targetUserId = closestPlayerUserId,
									pattern = chosenAttack and chosenAttack.pattern or "CONE",
									windupTime = windupTime,
									attackTime = attackTime,
									-- 공격 애니메이션 키 (nil이면 애니 없이 대기)
									anim = chosenAttack and chosenAttack.anim or nil,
									-- 패턴별 범위 데이터
									angle = chosenAttack and chosenAttack.angle,
									range = chosenAttack and chosenAttack.range,
									radius = chosenAttack and chosenAttack.radius,
									width = chosenAttack and chosenAttack.width,
									length = chosenAttack and chosenAttack.length,
									impactRadius = chosenAttack and chosenAttack.impactRadius,
									-- 위치/방향 정보 (CONE은 머리 위치 전송)
									creaturePos = {lockedAttackOrigin.X, lockedAttackOrigin.Y, lockedAttackOrigin.Z},
									creatureLook = {lockedCreatureLook.X, lockedCreatureLook.Y, lockedCreatureLook.Z},
									targetPos = {lockedTargetPos.X, lockedTargetPos.Y, lockedTargetPos.Z},
								})
							end

							-- ★ 공격 모션 종료 시점에 판정 (windupTime + attackTime 후)
							task.delay(totalTime + NETWORK_ANIM_BUFFER, function()
								-- 1. 크리처 활성 상태 재확인
								local currentCreature = activeCreatures[id]
								if not currentCreature or not currentCreature.model or not currentCreature.model.Parent then return end
								if (currentCreature.currentHealth or 0) <= 0 or currentCreature.state == "DEAD" then return end

								if getProtectedZoneInfo(currentCreature.rootPart.Position) then
									return
								end
								
								local player = Players:GetPlayerByUserId(closestPlayerUserId)
								if not player then return end
								
								local playerChar = player.Character
								local playerHrp = playerChar and playerChar:FindFirstChild("HumanoidRootPart")
								if not playerHrp then return end
								if getProtectedZoneInfo(playerHrp.Position) then return end
								
								-- ★ 텔레그래프 범위 기반 피격 판정 (공격 모션 종료 시점)
								local CombatService = require(game:GetService("ServerScriptService").Server.Services.CombatService)
								
								-- 무적 상태 체크
								if CombatService.isPlayerInvulnerable(closestPlayerUserId) then return end
								
								local playerCurrentPos = playerHrp.Position
								
								-- ★ 선언 시점 고정 위치/방향으로 판정 (시각 인디케이터 = 판정 범위 일치)
								local isHit = false
								if chosenAttack then
									isHit = CombatService.isPlayerInAttackArea(
										chosenAttack,
										lockedAttackOrigin,
										lockedCreatureLook,
										playerCurrentPos,
										lockedTargetPos -- PROJECTILE 착탄 지점
									)
								end
								
								if isHit then
									CombatService.damagePlayer(closestPlayerUserId, attackDamage, currentCreature.rootPart.Position, id)
								end
								
								-- 범위 내 소환된 팰에게도 데미지
								local PartyService = require(game:GetService("ServerScriptService").Server.Services.PartyService)
								local summon = PartyService.getSummon(closestPlayerUserId)
								if summon and summon.rootPart and summon.currentHP > 0 then
									local palPos = summon.rootPart.Position
									-- 팰도 공격 영역 판정 (isPlayerInAttackArea 재활용)
									local palHit = false
									if chosenAttack then
										palHit = CombatService.isPlayerInAttackArea(
											chosenAttack,
											lockedAttackOrigin,
											lockedCreatureLook,
											palPos,
											lockedTargetPos
										)
									end
									if palHit then
										PartyService.damagePal(closestPlayerUserId, attackDamage, currentCreature.rootPart.Position)
									end
								end
							end)
						end
					end
				else
					if not creature.lastAttackTime or (now - creature.lastAttackTime >= (creature.data.attackCooldown or CREATURE_ATTACK_COOLDOWN)) then
						if getProtectedZoneInfo(hrp.Position) then
							continue
						end
						local facFolder = workspace:FindFirstChild("Facilities")
						if facFolder then
							local params = OverlapParams.new()
							params.FilterDescendantsInstances = { facFolder }
							params.FilterType = Enum.RaycastFilterType.Include
							local hits = workspace:GetPartBoundsInRadius(hrp.Position, attackRange + 2, params)
							if #hits > 0 then
								local sModel = hits[1]:FindFirstAncestorOfClass("Model")
								local sId = sModel and sModel:GetAttribute("StructureId")
								if sId then
									creature.lastAttackTime = now
									if NetController then
										NetController.FireAllClients("Creature.Attack.Play", {
											instanceId = id,
											targetStructureId = sId,
											attackRange = attackRange,
											creaturePos = {hrp.Position.X, hrp.Position.Y, hrp.Position.Z},
											creatureLook = {hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Y, hrp.CFrame.LookVector.Z},
											attackDelay = creature.data.attackDelay or 0.3,
										})
									end
									
									-- 구조물 공격도 딜레이 도입
									local attackDelay = creature.data.attackDelay or 0.3
									task.delay(attackDelay, function()
										local BuildService = require(game:GetService("ServerScriptService").Server.Services.BuildService)
										BuildService.takeDamage(sId, dmg)
									end)
								end
							end
						end
					end
				end
			end
		end
		
		-- ★ GUI 업데이트 제거 — 클라이언트에서 Attribute 기반으로 처리
		-- (CurrentHealth는 processAttack에서 이미 Attribute에 반영됨)
	end
end

function CreatureService.SetProtectedZoneChecker(checkerFn)
	protectedZoneChecker = checkerFn
end

--========================================
-- 후순위 의존성 주입
--========================================

--- HarvestService를 후순위 주입 (ServerInit에서 초기화 순서 차이로 인해)
function CreatureService.SetHarvestService(_HarvestService)
	HarvestService = _HarvestService
end

--========================================
-- Network Handlers
--========================================

function CreatureService.GetHandlers()
	return {}
end

return CreatureService
