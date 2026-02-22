-- CreatureService.lua
-- 크리처 스폰 및 관리 서비스 (Phase 3-1)
-- 서버 권위로 크리처 엔티티를 생성하고 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local CreatureService = {}

-- Dependencies
local NetController
local DataService
local WorldDropService
local PlayerStatService -- Phase 6 연동
local DropTableData -- require 나중에 (상호참조 방지)
local DebuffService -- Phase 4-4 연동

-- Private State
local activeCreatures = {} -- [instanceId] = { model=Part, data=Data, state=..., targetPosition=Vector3, lastStateChange=number }
local creatureCount = 0

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- AI Constants
local SPAWN_INTERVAL = 30 -- 30초마다 스폰 시도
local AI_UPDATE_INTERVAL = 0.3 -- 0.3초마다 AI 로직 수행 (더 부드러운 이동)
local MIN_SPAWN_DIST = 40
local MAX_SPAWN_DIST = 80
local WANDER_RADIUS = 18
local DESPAWN_DIST = 150
local CREATURE_ATTACK_COOLDOWN = 2 -- 크리처 공격 쿨다운 (초)

-- 자연스러운 AI 행동 상수
local IDLE_MIN_TIME = 2.0   -- IDLE 최소 지속시간
local IDLE_MAX_TIME = 7.0   -- IDLE 최대 지속시간
local WANDER_MIN_TIME = 4.0 -- WANDER 최소 지속시간
local WANDER_MAX_TIME = 12.0 -- WANDER 최대 지속시간
local SPEED_VARIATION = 0.25 -- 속도 변동 범위 (±25%)
local WANDER_ANGLE_RANGE = 120 -- 배회 방향 변동 범위 (±도)

-- 어그로 시스템 상수
local AGGRO_TIMEOUT = 3 -- 추격 시간 제한 (초)
local MAX_CHASE_DISTANCE = 50 -- 어그로 해제 절대 거리 (studs)

-- 물/해수면 상수
local SEA_LEVEL = 10 -- 해수면 높이 (이 아래는 물로 간주)
local WATER_CHECK_DISTANCE = 5 -- 이동 전 물 체크 거리

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
		-- 모델 중심 계산
		local center = getModelCenter(model)
		
		-- HumanoidRootPart 생성 (투명, 중심에 위치)
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 2)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.Position = center
		rootPart.Parent = model
		
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
	
	-- 2. 모든 파트 Anchored = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	
	-- 3. PrimaryPart 설정
	model.PrimaryPart = rootPart
	
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
	
	-- 7. 근거리 전용 울음소리 (RollOff로 가까이에서만 들림)
	local ambientSound = Instance.new("Sound")
	ambientSound.Name = "AmbientCry"
	ambientSound.Volume = 0.6
	ambientSound.RollOffMode = Enum.RollOffMode.Linear
	ambientSound.RollOffMinDistance = 10
	ambientSound.RollOffMaxDistance = 60  -- 60 스터드 밖에서는 안 들림
	ambientSound.Looped = false
	ambientSound.Parent = rootPart
	
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
		
		print(string.format("[CreatureService] Loaded model '%s' for %s", template.Name, creatureId))
	else
		-- 폴백: 임시 플레이스홀더 모델 생성
		warn(string.format("[CreatureService] Model '%s' not found in CreatureModels, using placeholder", modelName))
		
		model = Instance.new("Model")
		model.Name = creatureId
		
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 2)
		rootPart.Position = position + Vector3.new(0, 3, 0)
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
	
	-- 빌보드 GUI (이름/체력 표시)
	local modelHeight = getModelHeight(model)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 100, 0, 50)
	bg.StudsOffset = Vector3.new(0, modelHeight / 2 + 1, 0)
	bg.AlwaysOnTop = true
	bg.Parent = rootPart
	
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Text = string.format("%s\nHP: %d/%d", data.name, data.maxHealth, data.maxHealth)
	txt.TextColor3 = Color3.new(1, 1, 1)
	txt.Parent = bg
	
	model.Parent = creatureFolder
	
	local instanceId = game:GetService("HttpService"):GenerateGUID(false)
	model:SetAttribute("InstanceId", instanceId)
	
	print(string.format("[CreatureService] Spawned %s at (%.1f, %.1f, %.1f) [ID:%s]", 
		creatureId, position.X, position.Y, position.Z, instanceId))
	
	activeCreatures[instanceId] = {
		id = instanceId,
		creatureId = creatureId,
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		data = data,
		maxHealth = data.maxHealth,
		currentHealth = data.maxHealth,
		state = "IDLE",
		targetPosition = nil,
		lastStateChange = tick(),
		gui = txt, -- GUI 업데이트용
	}
	creatureCount = creatureCount + 1
	
	print(string.format("[CreatureService] Spawned %s (%s)", creatureId, instanceId))
	
	return instanceId
end

--- 크리처 런타임 조회 (CombatService 연동용)
function CreatureService.getCreatureRuntime(instanceId: string)
	return activeCreatures[instanceId]
end

--- 크리처 강제 제거 (포획 등 특수 상황용)
function CreatureService.removeCreature(instanceId: string)
	local creature = activeCreatures[instanceId]
	if not creature then return end
	
	-- 즉시 런타임에서 제거
	activeCreatures[instanceId] = nil
	creatureCount = creatureCount - 1
	
	-- 시각적 제거
	if creature.gui then
		creature.gui:Destroy()
	end
	
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

--- 데미지 적용 및 사망 처리
function CreatureService.applyDamage(instanceId: string, damage: number, attacker: Player): (boolean, Vector3?)
	local creature = activeCreatures[instanceId]
	if not creature or not creature.humanoid or creature.currentHealth <= 0 then
		return false, nil
	end
	
	creature.currentHealth = creature.currentHealth - damage
	creature.humanoid.Health = creature.currentHealth
	
	-- 피격 시 상태 변경 (Neutral/Aggressive -> Chase Attacker)
	if creature.data.behavior ~= "PASSIVE" then
		creature.state = "CHASE"
		creature.lastStateChange = tick()
		creature.chaseStartTime = tick() -- 어그로 시간 추적 시작
		-- attacker를 target으로 설정해야 하지만, 현재 AI 루프는 "가장 가까운 플레이어"를 쫓음.
		-- 일단은 상태만 변경해도 가까이 있는 attacker를 쫓게 됨.
	else
		-- 도망 (PASSIVE)
		creature.state = "FLEE" -- (Wander의 빠른 버전으로 구현 필요)
		creature.humanoid.WalkSpeed = (creature.data.runSpeed or 20) * 1.2
	end
	
	-- GUI 갱신
	if creature.gui then
		creature.gui.Text = string.format("%s\nState: %s\nHP: %d", creature.data.name, creature.state, creature.currentHealth)
	end

	-- 사망 처리
	if creature.currentHealth <= 0 then
		local attackerName = attacker and attacker.Name or "Unknown/Environment"
		print(string.format("[CreatureService] %s killed by %s", creature.creatureId, attackerName))
		
		local deathPos = creature.rootPart.Position
		
		-- 1. 드롭 아이템 생성
		local drops = DropTableData[creature.creatureId]
		if drops then
			for _, drop in ipairs(drops) do
				if math.random() <= drop.chance then
					local count = math.random(drop.min, drop.max)
					WorldDropService.spawnDrop(deathPos + Vector3.new(math.random(-2,2), 1, math.random(-2,2)), drop.itemId, count)
				end
			end
		end
		
		-- 2. 경험치 보상 (Phase 6)
		if PlayerStatService and attacker then
			local xpAmount = Balance.XP_CREATURE_KILL or 25
			-- 필요 시 크리처 데이터에 정의된 XP 사용
			if creature.data and creature.data.xpReward then
				xpAmount = creature.data.xpReward
			end
			PlayerStatService.addXP(attacker.UserId, xpAmount, Enums.XPSource.CREATURE_KILL)
		end
		
		-- 3. 사망 연출 (Anchored, Tipped Over)
		if creature.rootPart then
			creature.rootPart.Anchored = true
			creature.rootPart.CanCollide = false
			creature.rootPart.Transparency = 0.5
			creature.rootPart.Orientation = Vector3.new(0, 0, 90) -- 눕기
		end
		if creature.gui then creature.gui:Destroy() end
		
		-- 3. 데이터 삭제 & 모델 제거 딜레이
		activeCreatures[instanceId] = nil -- 로직에서 제외
		creatureCount = creatureCount - 1
		
		task.delay(2, function()
			if creature.model then creature.model:Destroy() end
		end)
		
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

--- 물에서 가장 가까운 육지 방향 찾기
function CreatureService._findLandDirection(position: Vector3): Vector3?
	local bestDir = nil
	local bestDist = math.huge
	
	-- 8방향 체크
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		
		-- 해당 방향으로 Raycast
		local checkPos = position + dir * 20
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
		end
	end
	
	return bestDir
end

--- 안전한 이동 위치 계산 (물 회피)
function CreatureService._getSafeTarget(currentPos: Vector3, targetPos: Vector3): Vector3
	-- 목표가 물이면 현재 위치 방향으로 육지 찾기
	if CreatureService._isWaterPosition(targetPos) then
		-- 현재 위치와 목표 사이에서 물이 아닌 위치 찾기
		local dir = (targetPos - currentPos)
		if dir.Magnitude > 0.1 then
			dir = dir.Unit
		else
			return currentPos
		end
		
		-- 점진적으로 거리 줄여서 안전한 위치 찾기
		for dist = 5, 20, 5 do
			local safePos = currentPos + dir * dist
			if not CreatureService._isWaterPosition(safePos) then
				return safePos
			end
		end
		
		-- 안전한 위치 못 찾으면 현재 위치 유지
		return currentPos
	end
	
	return targetPos
end

--- 유효한 스폰 위치 찾기 (Donut Shape around player)
function CreatureService._findSpawnPosition(playerRootPart: Part): Vector3?
	if not playerRootPart then return nil end
	
	-- 제외 대상: 크리처, 자원노드, 드롭아이템 (지형만 감지하려면 이것들 제외)
	local excludeList = {}
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if creaturesFolder then table.insert(excludeList, creaturesFolder) end
	local resourceNodesFolder = workspace:FindFirstChild("ResourceNodes")
	if resourceNodesFolder then table.insert(excludeList, resourceNodesFolder) end
	local dropsFolder = workspace:FindFirstChild("WorldDrops")
	if dropsFolder then table.insert(excludeList, dropsFolder) end
	-- 플레이어 캐릭터 제외
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(excludeList, player.Character) end
	end
	
	for i = 1, 15 do -- 15회 시도
		local angle = math.rad(math.random(1, 360))
		local distance = math.random(MIN_SPAWN_DIST, MAX_SPAWN_DIST)
		
		local offset = Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
		local origin = playerRootPart.Position + offset + Vector3.new(0, 100, 0)
		
		-- Raycast (Exclude 방식으로 지형 감지)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = excludeList
		params.FilterType = Enum.RaycastFilterType.Exclude
		
		local result = workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
		if result then
			-- 물/바다 Material 체크 (육지만 허용)
			local isWater = result.Material == Enum.Material.Water
				or result.Material == Enum.Material.CrackedLava -- 용암도 제외
			
			-- 해수면 아래 체크 (Y가 너무 낮으면 물로 간주)
			local belowSeaLevel = result.Position.Y < SEA_LEVEL
			
			-- 물이 아니고 해수면 위인 경우만 허용
			if not isWater and not belowSeaLevel then
				local spawnPos = result.Position + Vector3.new(0, 2, 0)
				-- 추가 안전 체크: isWaterPosition으로 한번 더 확인
				if not CreatureService._isWaterPosition(spawnPos) then
					return spawnPos
				end
			end
		end
	end
	return nil
end

-- 가중치 기반 스폰 풀 (실제 모델이 있는 크리처만)
local HERBIVORE_POOL = {
	-- PASSIVE (도망형)
	{id = "DODO", weight = 25},
	{id = "COMPY", weight = 18},
	{id = "PARASAUR", weight = 12},
	-- NEUTRAL (반격형)
	{id = "TRICERATOPS", weight = 8},
	{id = "STEGOSAURUS", weight = 6},
	{id = "ANKYLOSAURUS", weight = 4},
}

local CARNIVORE_POOL = {
	{id = "RAPTOR", weight = 30},
	{id = "TREX", weight = 3},
}

-- 가중치 기반 랜덤 선택
local function weightedRandom(pool)
	local totalWeight = 0
	for _, entry in ipairs(pool) do totalWeight = totalWeight + entry.weight end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then return entry.id end
	end
	return pool[1].id
end

--- 맵 중심 주변에 스폰 위치 찾기 (플레이어 없이도 동작)
function CreatureService._findMapSpawnPosition(center: Vector3, radius: number): Vector3?
	local excludeList = {}
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if creaturesFolder then table.insert(excludeList, creaturesFolder) end
	local resourceNodesFolder = workspace:FindFirstChild("ResourceNodes")
	if resourceNodesFolder then table.insert(excludeList, resourceNodesFolder) end
	
	for i = 1, 10 do
		-- 사각형 맵 전역 분포 (Corners 포함)
		local xOffset = (math.random() * 2 - 1) * radius
		local zOffset = (math.random() * 2 - 1) * radius
		local x = center.X + xOffset
		local z = center.Z + zOffset
		local origin = Vector3.new(x, center.Y + 400, z) -- 높은 곳에서 발사
		
		-- 지형/맵만 감지하도록 필터링 강화
		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		if workspace:FindFirstChild("Map") then
			table.insert(filterList, workspace.Map)
		end
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		local result = workspace:Raycast(origin, Vector3.new(0, -800, 0), params)
		if result then
			-- 물/바다 Material 체크 (육지만 허용)
			local isWater = result.Material == Enum.Material.Water 
				or result.Material == Enum.Material.CrackedLava
			
			-- 해수면 체크 (Balance.SEA_LEVEL 또는 로컬 10)
			local currentSeaLevel = Balance.SEA_LEVEL or SEA_LEVEL or 10
			local belowSeaLevel = result.Position.Y < currentSeaLevel
			
			if not isWater and not belowSeaLevel then
				local pos = result.Position + Vector3.new(0, 2, 0)
				-- 추가적인 물 체크 (있다면)
				if not CreatureService._isWaterPosition(pos) then
					return pos
				end
			end
		end
	end
	return nil
end

--- ★ 초기 대량 스폰 (서버 시작 시 맵 전체에 크리처 배치)
function CreatureService._initialSpawn()
	local INITIAL_COUNT = Balance.INITIAL_CREATURE_COUNT or 80
	local SPAWN_RADIUS = Balance.MAP_EXTENT or 1500
	local MAP_CENTER = Vector3.new(0, 0, 0)
	
	-- 맵 중심 찾기
	local spawnLoc = workspace:FindFirstChild("SpawnLocation", true)
	if spawnLoc and spawnLoc:IsA("BasePart") then
		MAP_CENTER = spawnLoc.Position
	end
	
	print(string.format("[CreatureService] Starting initial spawn: %d creatures across radius %.0f", 
		INITIAL_COUNT, SPAWN_RADIUS))
	
	local spawned = 0
	local attempts = 0
	local MAX_ATTEMPTS = INITIAL_COUNT * 10
	
	-- 초식:육식 = 80%:20%
	local herbivoreCount = math.floor(INITIAL_COUNT * 0.8)
	local carnivoreCount = INITIAL_COUNT - herbivoreCount
	
	-- 초식동물 스폰
	while spawned < herbivoreCount and attempts < MAX_ATTEMPTS do
		attempts = attempts + 1
		local pos = CreatureService._findMapSpawnPosition(MAP_CENTER, SPAWN_RADIUS)
		if pos then
			local cid = weightedRandom(HERBIVORE_POOL)
			local result = CreatureService.spawn(cid, pos)
			if result then
				spawned = spawned + 1
			end
		end
	end
	
	local herbSpawned = spawned
	
	-- 육식동물 스폰
	local carnSpawned = 0
	attempts = 0
	while carnSpawned < carnivoreCount and attempts < MAX_ATTEMPTS do
		attempts = attempts + 1
		local pos = CreatureService._findMapSpawnPosition(MAP_CENTER, SPAWN_RADIUS)
		if pos then
			local cid = weightedRandom(CARNIVORE_POOL)
			local result = CreatureService.spawn(cid, pos)
			if result then
				carnSpawned = carnSpawned + 1
			end
		end
	end
	
	print(string.format("[CreatureService] Initial spawn complete: %d herbivores + %d carnivores = %d total", 
		herbSpawned, carnSpawned, herbSpawned + carnSpawned))
end

--- 보충 스폰 루프 (CAP 대비 부족분만 플레이어 주변에 보충)
function CreatureService._replenishLoop()
	if creatureCount >= CREATURE_CAP then return end
	
	local deficit = CREATURE_CAP - creatureCount
	-- 한 번에 최대 2마리씩 보충 (자연스러운 등장)
	local toSpawn = math.min(deficit, 2)
	
	for _, player in ipairs(Players:GetPlayers()) do
		if toSpawn <= 0 or creatureCount >= CREATURE_CAP then break end
		
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			-- 초식 보충 (85% 확률)
			if math.random() <= 0.85 then
				local pos = CreatureService._findSpawnPosition(char.HumanoidRootPart)
				if pos then
					local cid = weightedRandom(HERBIVORE_POOL)
					CreatureService.spawn(cid, pos)
					toSpawn = toSpawn - 1
				end
			else
				-- 육식 보충 (15% 확률)
				local pos = CreatureService._findSpawnPosition(char.HumanoidRootPart)
				if pos then
					local cid = weightedRandom(CARNIVORE_POOL)
					CreatureService.spawn(cid, pos)
					toSpawn = toSpawn - 1
				end
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

--- AI 업데이트 루프 (상태 머신)
function CreatureService._updateAILoop()
	local now = tick()
	
	for id, creature in pairs(activeCreatures) do
		if not creature.model or not creature.model.Parent then
			-- 모델이 사라졌으면 정리
			activeCreatures[id] = nil
			creatureCount = creatureCount - 1
			continue
		end
		
		local hrp = creature.rootPart
		if not hrp then continue end
		
		-- 1. 가장 가까운 플레이어 찾기
		local closestPlayer, minDist = nil, 9999
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				local d = (char.HumanoidRootPart.Position - hrp.Position).Magnitude
				if d < minDist then
					minDist = d
					closestPlayer = char.HumanoidRootPart
				end
			end
		end
		
		-- 2. Despawn Check
		if minDist > DESPAWN_DIST then
			creature.model:Destroy()
			activeCreatures[id] = nil
			creatureCount = creatureCount - 1
			print("[CreatureService] Despawned (Too far):", id)
			continue
		end
		
		-- 3. State Machine
		local behavior = creature.data.behavior -- AGGRESSIVE, NEUTRAL, PASSIVE
		local detectRange = creature.data.detectRange or 20
		
		-- BloodSmell 어그로 배율 적용 (Phase 4-4)
		if DebuffService and closestPlayer then
			local playerUserId = nil
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Character and player.Character:FindFirstChild("HumanoidRootPart") == closestPlayer then
					playerUserId = player.UserId
					break
				end
			end
			if playerUserId then
				detectRange = detectRange * DebuffService.getAggroMultiplier(playerUserId)
			end
		end
		
		local newState = creature.state
		local chaseDuration = (creature.chaseStartTime and (now - creature.chaseStartTime)) or 0
		
		-- 랜덤 상태 지속시간 (최초 또는 상태 변경 시 설정)
		if not creature.stateDuration then
			creature.stateDuration = getRandomDuration(IDLE_MIN_TIME, IDLE_MAX_TIME)
		end
		local elapsed = now - creature.lastStateChange
		
		if behavior == "AGGRESSIVE" then
			if creature.state == "CHASE" then
				if chaseDuration >= AGGRO_TIMEOUT or minDist > MAX_CHASE_DISTANCE then
					newState = "WANDER"
					creature.chaseStartTime = nil
				end
			elseif minDist <= detectRange then
				newState = "CHASE"
				if not creature.chaseStartTime then
					creature.chaseStartTime = now
				end
			elseif creature.state == "IDLE" and elapsed > creature.stateDuration then
				newState = "WANDER"
			elseif creature.state == "WANDER" and elapsed > creature.stateDuration then
				newState = "IDLE"
			end
		else -- NEUTRAL, PASSIVE
			if creature.state == "CHASE" then
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
			creature.state = newState
			creature.lastStateChange = now
			-- 새 상태에 맞는 랜덤 지속시간 설정
			if newState == "IDLE" then
				creature.stateDuration = getRandomDuration(IDLE_MIN_TIME, IDLE_MAX_TIME)
			elseif newState == "WANDER" then
				creature.stateDuration = getRandomDuration(WANDER_MIN_TIME, WANDER_MAX_TIME)
			end
		end
		
		-- 4. Behavior Execution
		local humanoid = creature.humanoid
		
		-- ============================================
		-- 물 진입 방지 (최우선 처리)
		-- ============================================
		local isInWater = CreatureService._isWaterPosition(hrp.Position)
		if isInWater then
			-- 긴급: 즉시 육지로 복귀
			local landDir = CreatureService._findLandDirection(hrp.Position)
			if landDir then
				local escapeTarget = hrp.Position + landDir * 30
				-- Raycast로 실제 육지 높이 찾기
				local rayParams = RaycastParams.new()
				rayParams.FilterDescendantsInstances = { workspace.Terrain }
				rayParams.FilterType = Enum.RaycastFilterType.Include
				local rayResult = workspace:Raycast(escapeTarget + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), rayParams)
				if rayResult and rayResult.Position.Y >= SEA_LEVEL then
					-- 안전한 육지 발견 → 즉시 텔레포트
					local safePos = rayResult.Position + Vector3.new(0, 3, 0)
					hrp.CFrame = CFrame.new(safePos)
					creature.targetPosition = nil
					creature.state = "IDLE"
					creature.lastStateChange = now
					creature.stateDuration = getRandomDuration(IDLE_MIN_TIME, IDLE_MAX_TIME)
				else
					-- 육지 못 찾으면 위로 이동
					hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0)
				end
			else
				-- 방향도 못 찾으면 높이 올리기
				hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0)
			end
			humanoid:MoveTo(hrp.Position) -- 정지
		elseif creature.state == "CHASE" and closestPlayer then
			-- 추격: 목표가 물이면 추격 포기
			if CreatureService._isWaterPosition(closestPlayer.Position) then
				creature.state = "WANDER"
				creature.lastStateChange = now
				creature.stateDuration = getRandomDuration(WANDER_MIN_TIME, WANDER_MAX_TIME)
				creature.chaseStartTime = nil
				humanoid:MoveTo(hrp.Position) -- 정지
			else
				local safeTarget = CreatureService._getSafeTarget(hrp.Position, closestPlayer.Position)
				humanoid:MoveTo(safeTarget)
				humanoid.WalkSpeed = creature.data.runSpeed or 20
			end
			
		elseif creature.state == "WANDER" then
			-- 목적지 도착했거나 아직 없음
			if not creature.targetPosition or (hrp.Position - creature.targetPosition).Magnitude < 6 then
				-- 현재 이동 방향 계산
				local currentDir = creature.lastMoveDir or Vector3.zero
				
				-- 자연스러운 새 목적지 (급격한 U턴 방지)
				local attempts = 0
				local target
				repeat
					target = getSmartWanderTarget(hrp.Position, currentDir, WANDER_RADIUS)
					attempts = attempts + 1
				until not CreatureService._isWaterPosition(target) or attempts >= 5
				
				-- 안전한 위치 찾기
				target = CreatureService._getSafeTarget(hrp.Position, target)
				
				-- 이동 방향 기록
				local diff = target - hrp.Position
				if diff.Magnitude > 0.1 then
					creature.lastMoveDir = Vector3.new(diff.X, 0, diff.Z).Unit
				end
				
				creature.targetPosition = target
				humanoid:MoveTo(target)
				-- 속도 자연스럽게 변동 (매번 조금씩 다르게)
				humanoid.WalkSpeed = getVariedSpeed(creature.data.walkSpeed or 10)
			end
			
		elseif creature.state == "FLEE" and closestPlayer then
			-- 가장 가까운 플레이어 반대 방향으로 도주
			local diff = hrp.Position - closestPlayer.Position
			local dir
			if diff.Magnitude > 0.1 then
				dir = diff.Unit
			else
				-- 동일 위치일 때 랜덤 방향
				local a = math.rad(math.random(1, 360))
				dir = Vector3.new(math.sin(a), 0, math.cos(a))
			end
			local fleeTarget = hrp.Position + dir * WANDER_RADIUS * 2
			
			-- 도주 방향이 물이면 다른 방향 찾기
			if CreatureService._isWaterPosition(fleeTarget) then
				-- 90도 회전해서 시도
				local rotatedDir = Vector3.new(dir.Z, 0, -dir.X)
				fleeTarget = hrp.Position + rotatedDir * WANDER_RADIUS * 2
				if CreatureService._isWaterPosition(fleeTarget) then
					-- 반대 방향
					fleeTarget = hrp.Position + (-rotatedDir) * WANDER_RADIUS * 2
				end
			end
			
			fleeTarget = CreatureService._getSafeTarget(hrp.Position, fleeTarget)
			creature.targetPosition = fleeTarget
			humanoid:MoveTo(fleeTarget)
			humanoid.WalkSpeed = (creature.data.runSpeed or 20) * 1.2
			
		elseif creature.state == "IDLE" then
			creature.targetPosition = nil
			humanoid:MoveTo(hrp.Position) -- 정지
			
			-- IDLE 시 가까운 플레이어가 있으면 울음소리 + 머리 회전
			if minDist < 80 then
				-- 주기적 울음소리 (15~30초 간격)
				if not creature.lastCryTime or (now - creature.lastCryTime > 15 + math.random() * 15) then
					creature.lastCryTime = now
					local cry = hrp:FindFirstChild("AmbientCry")
					if cry then
						cry:Play()
					end
				end
				
				-- IDLE 시 좌우 둘러보기 (Y축 회전)
				if not creature.idleLookTime or (now - creature.idleLookTime > 2 + math.random() * 3) then
					creature.idleLookTime = now
					local lookAngle = math.rad(math.random(-40, 40))
					local currentCF = hrp.CFrame
					local lookCF = CFrame.new(currentCF.Position) * CFrame.Angles(0, lookAngle, 0)
					hrp.CFrame = lookCF
				end
			end
		end
		
		-- 5. Creature -> Player Damage (Phase 4-1)
		if creature.state == "CHASE" and closestPlayer then
			local attackRange = creature.data.attackRange or 5
			local dmg = creature.data.damage or 0
			
			if dmg > 0 and minDist <= attackRange then
				-- 쿨다운 체크
				if not creature.lastAttackTime or (now - creature.lastAttackTime >= CREATURE_ATTACK_COOLDOWN) then
					creature.lastAttackTime = now
					
					-- 플레이어 Humanoid에 데미지
					local targetChar = closestPlayer.Parent -- HumanoidRootPart.Parent = Character
					if targetChar then
						local targetHum = targetChar:FindFirstChild("Humanoid")
						if targetHum and targetHum.Health > 0 then
							targetHum:TakeDamage(dmg)
							print(string.format("[CreatureService] %s attacked player for %d dmg", creature.creatureId, dmg))
						end
					end
				end
			end
		end
		
		-- GUI 업데이트
		if creature.gui then
			creature.gui.Text = string.format("%s\nState: %s\nHP: %d", creature.data.name, creature.state, creature.currentHealth)
		end
	end
end

--========================================
-- Network Handlers
--========================================

function CreatureService.GetHandlers()
	return {}
end

return CreatureService
