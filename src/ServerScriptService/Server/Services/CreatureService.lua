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
local SPAWN_INTERVAL = 5 -- 5초마다 스폰 시도
local AI_UPDATE_INTERVAL = 0.5 -- 0.5초마다 AI 로직 수행 (최적화)
local MIN_SPAWN_DIST = 40
local MAX_SPAWN_DIST = 80
local WANDER_RADIUS = 15
local DESPAWN_DIST = 150
local CREATURE_ATTACK_COOLDOWN = 2 -- 크리처 공격 쿨다운 (초)

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
	
	-- 스폰 루프 시작
	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL)
			CreatureService._spawnLoop()
		end
	end)
	
	-- AI 루프 시작
	task.spawn(function()
		while true do
			task.wait(AI_UPDATE_INTERVAL)
			CreatureService._updateAILoop()
		end
	end)
	
	print("[CreatureService] Initialized with Spawn & AI Loops")
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
	
	-- 임시 모델 (Part → Model + Humanoid) 구조
	-- 추후 실제 3D 모델로 대체
	
	local model = Instance.new("Model")
	model.Name = creatureId
	
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 2)
	rootPart.Position = position + Vector3.new(0, 3, 0)
	rootPart.BrickColor = BrickColor.Random()
	rootPart.Transparency = 0.5
	rootPart.Anchored = false -- 물리 적용을 위해 해제 필수
	rootPart.Parent = model
	model.PrimaryPart = rootPart
	
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = data.walkSpeed or 16
	humanoid.MaxHealth = data.maxHealth
	humanoid.Health = data.maxHealth
	humanoid.Parent = model
	
	-- 빌보드 GUI (이름/체력 표시)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 100, 0, 50)
	bg.StudsOffset = Vector3.new(0, 3, 0)
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
		lastStateChange = os.time(),
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
		creature.lastStateChange = os.time()
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
		print(string.format("[CreatureService] %s killed by %s", creature.creatureId, attacker.Name))
		
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

--- 유효한 스폰 위치 찾기 (Donut Shape around player)
function CreatureService._findSpawnPosition(playerRootPart: Part): Vector3?
	if not playerRootPart then return nil end
	
	for i = 1, 5 do -- 5회 시도
		local angle = math.rad(math.random(1, 360))
		local distance = math.random(MIN_SPAWN_DIST, MAX_SPAWN_DIST)
		
		local offset = Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
		local origin = playerRootPart.Position + offset + Vector3.new(0, 50, 0)
		
		-- Raycast
		local params = RaycastParams.new()
		-- workspace 전체를 포함하면 자기 자신이나 다른 크리처 위에 스폰될 수 있으므로 Terrain 위주로 검사
		local filterList = { workspace.Terrain }
		if workspace:FindFirstChild("Map") then
			table.insert(filterList, workspace.Map)
		end
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		local result = workspace:Raycast(origin, Vector3.new(0, -100, 0), params)
		if result then
			if result.Material ~= Enum.Material.Water then
				return result.Position + Vector3.new(0, 2, 0)
			end
		end
	end
	return nil
end

--- 스폰 루프
function CreatureService._spawnLoop()
	if creatureCount >= CREATURE_CAP then return end
	
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			-- 확률적으로 스폰
			if math.random() > 0.7 then -- 30% 확률
				local pos = CreatureService._findSpawnPosition(char.HumanoidRootPart)
				if pos then
					-- 랜덤 크리처 선택
					local pool = {"RAPTOR", "TRICERATOPS", "DODO"}
					local cid = pool[math.random(1, #pool)]
					CreatureService.spawn(cid, pos)
					
					if creatureCount >= CREATURE_CAP then break end
				end
			end
		end
	end
end

--- AI 업데이트 루프 (상태 머신)
function CreatureService._updateAILoop()
	local now = os.time()
	
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
		
		if behavior == "AGGRESSIVE" then
			if minDist <= detectRange then
				newState = "CHASE"
			elseif creature.state == "CHASE" and minDist > detectRange * 1.5 then
				newState = "WANDER" -- 추격 포기
			elseif creature.state == "IDLE" and (now - creature.lastStateChange > 3) then
				newState = "WANDER"
			elseif creature.state == "WANDER" and (now - creature.lastStateChange > 5) then
				newState = "IDLE"
			end
		else -- NEUTRAL, PASSIVE
			-- NEUTRAL은 피격 시 CHASE 상태가 됨 (applyDamage에서 설정)
			if creature.state == "CHASE" then
				-- 반격 모드: 거리가 멀어지면 추격 포기
				if minDist > detectRange * 2 then
					newState = "WANDER"
				end
			elseif creature.state == "FLEE" then
				-- FLEE 상태는 applyDamage에서 설정됨 (PASSIVE가 피격 시)
				-- 도망 중이면 일정 시간 후 WANDER로
				if now - creature.lastStateChange > 8 then
					newState = "WANDER"
				end
			elseif creature.state == "IDLE" and (now - creature.lastStateChange > 3) then
				newState = "WANDER"
			elseif creature.state == "WANDER" and (now - creature.lastStateChange > 5) then
				newState = "IDLE"
			end
		end
		
		-- 상태 변경 처리
		if newState ~= creature.state then
			creature.state = newState
			creature.lastStateChange = now
			-- print(id, "State:", newState)
		end
		
		-- 4. Behavior Execution
		local humanoid = creature.humanoid
		
		if creature.state == "CHASE" and closestPlayer then
			humanoid:MoveTo(closestPlayer.Position)
			humanoid.WalkSpeed = creature.data.runSpeed or 20
			
		elseif creature.state == "WANDER" then
			-- 목적지 도착했거나 타임아웃
			if not creature.targetPosition or (hrp.Position - creature.targetPosition).Magnitude < 4 then
				-- 새 목적지
				local rx = math.random(-WANDER_RADIUS, WANDER_RADIUS)
				local rz = math.random(-WANDER_RADIUS, WANDER_RADIUS)
				local target = hrp.Position + Vector3.new(rx, 0, rz)
				creature.targetPosition = target
				humanoid:MoveTo(target)
				humanoid.WalkSpeed = creature.data.walkSpeed or 10
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
			creature.targetPosition = fleeTarget
			humanoid:MoveTo(fleeTarget)
			humanoid.WalkSpeed = (creature.data.runSpeed or 20) * 1.2
			
		elseif creature.state == "IDLE" then
			creature.targetPosition = nil
			humanoid:MoveTo(hrp.Position) -- 정지
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
