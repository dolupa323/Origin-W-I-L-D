-- CombatService.lua
-- 전투 시스템 (Phase 3-3)
-- 플레이어와 크리처 간의 데미지 처리 및 사망 로직, 드롭 아이템 생성

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local Data = ReplicatedStorage:WaitForChild("Data")
local MaterialAttributeData = require(Data.MaterialAttributeData)
local SpawnConfig = require(Shared.Config.SpawnConfig)

local CombatService = {}

-- Dependencies
local NetController
local CreatureService
local InventoryService
local DurabilityService
local DataService
local DebuffService
local StaminaService
local WorldDropService
local PlayerStatService
local HungerService -- Cached (Phase 11)
local TechService
local SkillService -- 스킬 패시브 보너스

-- Constants
local DEFAULT_ATTACK_RANGE = Balance.REACH_BAREHAND or 12 -- 맨손 사거리 (Balance 반영)
local DEFAULT_BAREHAND_DAMAGE = 5
local MIN_ATTACK_COOLDOWN = 0.35 -- 서버 측 최소 공격 쿨다운 보안 검증 (클라이언트 0.4~0.5초 대비 타이트하게)
local PVP_ENABLED = true  -- 지역별 PvP 시스템 활성화 (개별 지역별 판정은 내부 로직으로 수행)
local PVP_ZONES = {
	TROPICAL = true,
	DESERT = true,
	SNOWY = true,
}

-- Combat Engagement Constants
local COMBAT_DISENGAGE_TIMEOUT = 8   -- 교전 없이 8초 경과 → 전투 해제
local COMBAT_DISENGAGE_DISTANCE = 130 -- 130스터드 이상 벗어나면 즉시 전투 해제 (활 사거리 120 대응)
local CONTACT_KNOCKBACK_FORCE = 10   -- 전투 중 접촉 시 밀어내기 힘 (18 → 10, 플레이어 튕김 방지)
local CONTACT_STAGGER_DURATION = 0.3 -- 접촉 경직 시간 (초)
local CONTACT_STAGGER_COOLDOWN = 2.0 -- 접촉 경직 쿨다운 (경직 해제 후 재발동까지)
local CONTACT_CHECK_DIST = 3         -- 접촉 판정 거리 (스터드) (5 → 3, 과도한 감지 방지)

-- Level Gap Constants
local LEVEL_GAP_MULTIPLIER = 0.05 -- 레벨 차이당 5% 증감
local MIN_DAMAGE_MODIFIER = 0.1  -- 최소 10% 데미지 보장
local MAX_DAMAGE_MODIFIER = 3.0  -- 최대 300% 데미지 제한

-- State
local playerAttackCooldowns = {} -- [userId] = nextAttackTime

-- Combat Engagement State
local playerCombatTargets = {}    -- [userId] = { [instanceId] = true } (플레이어가 전투 중인 크리처들)
local playerCombatLastHit = {}    -- [userId] = { [instanceId] = tick() } (대상별 마지막 교전 시각)
local playerCombatPrimaryTarget = {} -- [userId] = instanceId (대표 타겟/팰 AI용)
local playerDirectCombatTargets = {} -- [userId] = { [instanceId] = true } (플레이어 직접 공격/피격으로 성립한 전투 대상)
local creatureCombatants = {}     -- [instanceId] = { [userId] = true } (크리처와 전투 중인 플레이어 목록)

-- Quest callback (Phase 8)
local questCallback = nil

--========================================
-- Combat Engagement System
--========================================

--- 크리처 모델의 충돌 그룹을 CombatCreatures/Creatures로 전환
local function setCreatureCollisionGroup(instanceId, group)
	if not CreatureService or not CreatureService.getCreatureRuntime then return end
	local creature = CreatureService.getCreatureRuntime(instanceId)
	if not creature or not creature.model then return end
	for _, part in ipairs(creature.model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

--- 접촉 시 플레이어를 밀어내고 경직 부여
local staggeredPlayers = {} -- [userId] = true (중복 경직 방지)
local knockbackImmunity = {} -- [userId][creatureInstanceId] = true (넉백 면역)

local function applyContactKnockback(userId, creaturePos, creatureInstanceId)
	if staggeredPlayers[userId] then return end
	
	-- ★ [추가] 같은 크리처에 대한 넉백 면역 체크 (0.5초 동안 무적)
	if knockbackImmunity[userId] and knockbackImmunity[userId][creatureInstanceId] then return end
	
	-- ★ 구르기 무적 프레임 존중: 무적 상태면 접촉 밀어내기/경직 무시
	if CombatService.isPlayerInvulnerable(userId) then return end
	local player = Players:GetPlayerByUserId(userId)
	if not player or not player.Character then return end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character:FindFirstChild("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	-- 밀어내기 방향 (크리처 → 플레이어)
	local pushDir = (hrp.Position - creaturePos)
	pushDir = Vector3.new(pushDir.X, 0, pushDir.Z)
	if pushDir.Magnitude < 0.1 then
		pushDir = hrp.CFrame.LookVector * -1
	else
		pushDir = pushDir.Unit
	end

	-- ★ [수정] 먼저 넉백 면역 설정 (FireClient 호출 전)
	if not knockbackImmunity[userId] then
		knockbackImmunity[userId] = {}
	end
	knockbackImmunity[userId][creatureInstanceId] = true
	
	-- 짧은 경직 (StaminaService 경유 속도 배율 적용)
	staggeredPlayers[userId] = true
	if StaminaService and StaminaService.setStagger then
		StaminaService.setStagger(userId, 0.15, CONTACT_STAGGER_DURATION)
	end
	
	-- 클라이언트에 접촉 경직 + 넉백 정보 전송 (클라이언트에서 물리 적용)
	if NetController then
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			NetController.FireClient(plr, "Combat.Contact.Stagger", {
				sourcePos = {creaturePos.X, creaturePos.Y, creaturePos.Z},
				knockbackForce = CONTACT_KNOCKBACK_FORCE,
			})
		end
	end

	-- 쿨다운: 경직 해제 후에도 일정 시간 재발동 방지
	task.delay(CONTACT_STAGGER_DURATION + CONTACT_STAGGER_COOLDOWN, function()
		staggeredPlayers[userId] = nil
	end)
	
	-- ★ [추가] 0.5초 후 넉백 면역 해제 (다른 크리처로부터는 즉시 피격 가능)
	task.delay(0.5, function()
		if knockbackImmunity[userId] then
			knockbackImmunity[userId][creatureInstanceId] = nil
		end
	end)
end

local function getAnyCombatTarget(userId)
	local targets = playerCombatTargets[userId]
	if type(targets) ~= "table" then
		return nil
	end
	for instanceId in pairs(targets) do
		return instanceId
	end
	return nil
end

local function notifyPlayerCombatState(userId, inCombat)
	if not NetController then
		return
	end
	local plr = Players:GetPlayerByUserId(userId)
	if not plr then
		return
	end
	NetController.FireClient(plr, "Combat.PlayerState.Changed", {
		inCombat = inCombat == true,
	})
end

local function hasAnyDirectCombatTarget(userId)
	local targets = playerDirectCombatTargets[userId]
	return type(targets) == "table" and next(targets) ~= nil
end

local function setDirectCombatTarget(userId, instanceId)
	if not instanceId then
		return
	end
	if type(playerDirectCombatTargets[userId]) ~= "table" then
		playerDirectCombatTargets[userId] = {}
	end
	local hadAnyDirectTarget = hasAnyDirectCombatTarget(userId)
	playerDirectCombatTargets[userId][instanceId] = true
	if not hadAnyDirectTarget then
		notifyPlayerCombatState(userId, true)
	end
end

local function clearDirectCombatTarget(userId, instanceId)
	local targets = playerDirectCombatTargets[userId]
	if type(targets) ~= "table" then
		return
	end
	local hadAnyDirectTarget = next(targets) ~= nil
	if instanceId then
		targets[instanceId] = nil
	else
		for targetInstanceId in pairs(targets) do
			targets[targetInstanceId] = nil
		end
	end
	if not next(targets) then
		playerDirectCombatTargets[userId] = nil
		if hadAnyDirectTarget then
			notifyPlayerCombatState(userId, false)
		end
	end
end

--- 전투 상태 진입 (플레이어 → 크리처)
local function engageCombat(userId, instanceId, countsAsDirectPlayerCombat)
	local now = tick()

	if type(playerCombatTargets[userId]) ~= "table" then
		playerCombatTargets[userId] = {}
	end
	if type(playerCombatLastHit[userId]) ~= "table" then
		playerCombatLastHit[userId] = {}
	end

	local hadAnyTarget = next(playerCombatTargets[userId]) ~= nil
	playerCombatTargets[userId][instanceId] = true
	playerCombatLastHit[userId][instanceId] = now
	playerCombatPrimaryTarget[userId] = instanceId

	if not creatureCombatants[instanceId] then
		creatureCombatants[instanceId] = {}
	end
	local wasEmpty = not next(creatureCombatants[instanceId])
	creatureCombatants[instanceId][userId] = true

	-- 전투 진입 알림 (새 크리처)
	if wasEmpty and NetController then
		NetController.FireAllClients("Combat.Engagement.Changed", {
			instanceId = instanceId,
			inCombat = true,
		})
		-- 전투 중 크리처 → 플레이어와 충돌 활성화
		setCreatureCollisionGroup(instanceId, "CombatCreatures")
	end

	if countsAsDirectPlayerCombat then
		setDirectCombatTarget(userId, instanceId)
	end

	-- ★ 소환 팰에게 전투 대상 공유 (활 원거리 전투 대응)
	local okPcall, PartyService = pcall(require, game:GetService("ServerScriptService").Server.Services.PartyService)
	if okPcall and PartyService and PartyService.setOwnerCombatTarget then
		PartyService.setOwnerCombatTarget(userId, instanceId)
	end
end

--- 전투 상태 해제 (플레이어)
local function disengageCombat(userId, instanceId)
	local targets = playerCombatTargets[userId]
	if type(targets) ~= "table" then return end

	local toRemove = {}
	if instanceId then
		if targets[instanceId] then
			table.insert(toRemove, instanceId)
		end
	else
		for targetInstanceId in pairs(targets) do
			table.insert(toRemove, targetInstanceId)
		end
	end

	for _, targetInstanceId in ipairs(toRemove) do
		targets[targetInstanceId] = nil
		clearDirectCombatTarget(userId, targetInstanceId)
		if type(playerCombatLastHit[userId]) == "table" then
			playerCombatLastHit[userId][targetInstanceId] = nil
		end

		if creatureCombatants[targetInstanceId] then
			creatureCombatants[targetInstanceId][userId] = nil
			if not next(creatureCombatants[targetInstanceId]) then
				creatureCombatants[targetInstanceId] = nil
				setCreatureCollisionGroup(targetInstanceId, "Creatures")
				if NetController then
					NetController.FireAllClients("Combat.Engagement.Changed", {
						instanceId = targetInstanceId,
						inCombat = false,
					})
				end
			end
		end
	end

	if not next(targets) then
		playerCombatTargets[userId] = nil
		playerCombatLastHit[userId] = nil
		playerCombatPrimaryTarget[userId] = nil
	else
		playerCombatPrimaryTarget[userId] = getAnyCombatTarget(userId)
	end

	local okPcall, PartyService = pcall(require, game:GetService("ServerScriptService").Server.Services.PartyService)
	if okPcall and PartyService and PartyService.setOwnerCombatTarget then
		PartyService.setOwnerCombatTarget(userId, playerCombatPrimaryTarget[userId])
	end
end

--- 크리처 사망/디스폰 시 전투 상태 전체 해제
local function disengageCreature(instanceId)
	local combatants = creatureCombatants[instanceId]
	if not combatants then return end

	for uid, _ in pairs(combatants) do
		if type(playerCombatTargets[uid]) == "table" then
			playerCombatTargets[uid][instanceId] = nil
			clearDirectCombatTarget(uid, instanceId)
			if not next(playerCombatTargets[uid]) then
				playerCombatTargets[uid] = nil
				playerCombatLastHit[uid] = nil
				playerCombatPrimaryTarget[uid] = nil
			else
				if type(playerCombatLastHit[uid]) == "table" then
					playerCombatLastHit[uid][instanceId] = nil
				end
				playerCombatPrimaryTarget[uid] = getAnyCombatTarget(uid)
			end
		end

		local okPcall, PartyService = pcall(require, game:GetService("ServerScriptService").Server.Services.PartyService)
		if okPcall and PartyService and PartyService.setOwnerCombatTarget then
			PartyService.setOwnerCombatTarget(uid, playerCombatPrimaryTarget[uid])
		end
	end
	creatureCombatants[instanceId] = nil

	-- 충돌 그룹 복구 (사망/디스폰 전 모델이 아직 있을 수 있음)
	setCreatureCollisionGroup(instanceId, "Creatures")

	if NetController then
		NetController.FireAllClients("Combat.Engagement.Changed", {
			instanceId = instanceId,
			inCombat = false,
		})
	end
end

local function isBowWeapon(itemData): boolean
	if not itemData then return false end
	local itemId = string.upper(tostring(itemData.id or ""))
	if itemId:find("BOW", 1, true) then
		return true
	end
	local opt = string.upper(tostring(itemData.optimalTool or ""))
	return opt == "BOW" or opt == "CROSSBOW"
end

local BOW_AMMO_TYPES = {"BRONZE_ARROW", "STONE_ARROW"}

local function getAmmoForWeapon(itemId: string): string?
	local upper = string.upper(tostring(itemId or ""))
	if upper == "CROSSBOW" then return "IRON_BOLT" end
	return nil
end

--- 무기 아이템 정보로 스킬 트리 ID 결정 (SWORD/BOW/AXE)
local function getWeaponTreeId(itemData)
	if not itemData then return nil end
	local toolRole = tostring(itemData.optimalTool or ""):upper()
	if toolRole == "AXE" then return "AXE"
	elseif toolRole == "PICKAXE" then return "PICKAXE"
	elseif toolRole == "SWORD" then return "SWORD"
	elseif toolRole == "SPEAR" then return "SPEAR"
	elseif toolRole == "HAMMER" then return "HAMMER"
	elseif toolRole == "BOW" or toolRole == "CROSSBOW" then return "BOW"
	end
	
	-- itemId 기반 폴백
	local id = string.upper(tostring(itemData.id or ""))
	if id:find("SWORD", 1, true) then return "SWORD" end
	if id:find("BOW", 1, true) then return "BOW" end
	if id:find("AXE", 1, true) then return "AXE" end
	return nil
end

function CombatService.getLevelModifier(attackerLevel, defenderLevel)
	local gap = attackerLevel - defenderLevel
	local modifier = 1 + (gap * LEVEL_GAP_MULTIPLIER)
	return math.clamp(modifier, MIN_DAMAGE_MODIFIER, MAX_DAMAGE_MODIFIER)
end

local BOW_HIT_CONE_HALF_ANGLE = 5   -- 화살 판정 원뿔 반각 (도) — 거의 직선에 가까운 보정만
local BOW_HIT_SCAN_RADIUS = 6       -- 발사 경로 주변 탐색 반경 (스터드)

local function findAttackTargetByRay(player: Player, direction: Vector3, range: number, originOverride: Vector3?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then return nil, nil end

	if direction.Magnitude <= 0.001 then return nil, nil end
	local dirUnit = direction.Unit
	local origin = originOverride or (hrp.Position + Vector3.new(0, 1.6, 0))

	-- 1차: 레이캐스트 직격
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = workspace:Raycast(origin, dirUnit * range, params)
	if result and result.Instance then
		local current = result.Instance
		while current and current ~= workspace do
			if current:IsA("Model") then
				local instanceId = current:GetAttribute("InstanceId")
				if instanceId then
					return instanceId, result.Position
				end
			end
			current = current.Parent
		end
	end

	-- 2차: 레이 직격 실패 → 발사 경로 주변 원뿽 탐색 (널널한 판정)
	local creaturesFolder = workspace:FindFirstChild("ActiveCreatures") or workspace:FindFirstChild("Creatures")
	if not creaturesFolder then return nil, origin + (dirUnit * range) end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { creaturesFolder }

	-- 발사 경로 중간 지점을 중심으로 탐색
	local scanCenter = origin + dirUnit * math.min(range * 0.5, 60)
	local scanRadius = math.max(range * 0.5, 30)
	local parts = workspace:GetPartBoundsInRadius(scanCenter, scanRadius, overlap)

	local bestId = nil
	local bestScore = math.huge
	local bestPos = nil
	local seen = {}

	for _, p in ipairs(parts) do
		local model = p:FindFirstAncestorWhichIsA("Model")
		if model then
			local instanceId = model:GetAttribute("InstanceId")
			if instanceId and not seen[instanceId] then
				seen[instanceId] = true
				local targetPos = (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")).Position
				local toTarget = targetPos - origin
				local dist = toTarget.Magnitude

				if dist <= range + BOW_HIT_SCAN_RADIUS and dist > 0.1 then
					-- 방향 각도 차이 계산
					local dot = dirUnit:Dot(toTarget.Unit)
					local angleDeg = math.deg(math.acos(math.clamp(dot, -1, 1)))

					-- 각도가 원뿽 반각 이내이면 히트 후보
					if angleDeg <= BOW_HIT_CONE_HALF_ANGLE then
						-- 점수: 각도 * 거리 (작을수록 좋음)
						local score = angleDeg * 2 + dist * 0.1
						if score < bestScore then
							bestScore = score
							bestId = instanceId
							bestPos = targetPos
						end
					end
				end
			end
		end
	end

	if bestId then
		return bestId, bestPos
	end

	return nil, result and result.Position or (origin + (dirUnit * range))
end

--========================================
-- Telegraph Attack Pattern Hit Detection
--========================================

--- 부채꼴(CONE) 범위 판정: 크리처 전방 기준 angle 내 + range 내
function CombatService.isInCone(creaturePos: Vector3, creatureLook: Vector3, playerPos: Vector3, range: number, halfAngleDeg: number): boolean
	local toPlayer = playerPos - creaturePos
	toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
	local flatLook = Vector3.new(creatureLook.X, 0, creatureLook.Z)
	if toPlayer.Magnitude < 0.01 or flatLook.Magnitude < 0.01 then return true end
	if toPlayer.Magnitude > range then return false end
	local dot = flatLook.Unit:Dot(toPlayer.Unit)
	local angleRad = math.acos(math.clamp(dot, -1, 1))
	return angleRad <= math.rad(halfAngleDeg)
end

--- 원형(CIRCLE) 범위 판정: 크리처 중심 반경 내
function CombatService.isInCircle(creaturePos: Vector3, playerPos: Vector3, radius: number): boolean
	local dist = (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(creaturePos.X, 0, creaturePos.Z)).Magnitude
	return dist <= radius
end

--- 직선 돌진(CHARGE) 범위 판정: 크리처 전방 직사각형 통로 내
function CombatService.isInCharge(creaturePos: Vector3, creatureLook: Vector3, playerPos: Vector3, width: number, length: number): boolean
	local flatLook = Vector3.new(creatureLook.X, 0, creatureLook.Z)
	if flatLook.Magnitude < 0.01 then return false end
	flatLook = flatLook.Unit
	local toPlayer = playerPos - creaturePos
	toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
	-- 전방 투영 (forward distance)
	local forwardDist = flatLook:Dot(toPlayer)
	if forwardDist < 0 or forwardDist > length then return false end
	-- 횡방향 투영 (lateral distance)
	local rightDir = Vector3.new(flatLook.Z, 0, -flatLook.X)
	local lateralDist = math.abs(rightDir:Dot(toPlayer))
	return lateralDist <= (width / 2)
end

--- 원거리 투사체(PROJECTILE) 범위 판정: 착탄 지점 기준 반경 내
function CombatService.isInProjectile(impactPos: Vector3, playerPos: Vector3, impactRadius: number): boolean
	local dist = (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(impactPos.X, 0, impactPos.Z)).Magnitude
	return dist <= impactRadius
end

--- 공격 패턴에 따라 적절한 판정 함수 호출
function CombatService.isPlayerInAttackArea(attackData: any, creaturePos: Vector3, creatureLook: Vector3, playerPos: Vector3, targetLockPos: Vector3?): boolean
	local pattern = attackData.pattern
	if pattern == "CONE" then
		return CombatService.isInCone(creaturePos, creatureLook, playerPos, attackData.range, (attackData.angle or 60) / 2)
	elseif pattern == "CIRCLE" then
		return CombatService.isInCircle(creaturePos, playerPos, attackData.radius)
	elseif pattern == "CHARGE" then
		return CombatService.isInCharge(creaturePos, creatureLook, playerPos, attackData.width, attackData.length)
	elseif pattern == "PROJECTILE" then
		local impactPos = targetLockPos or playerPos
		return CombatService.isInProjectile(impactPos, playerPos, attackData.impactRadius or 5)
	end
	return false
end

function CombatService.SetStaminaService(_StaminaService)
	StaminaService = _StaminaService
end

function CombatService.SetSkillService(_SkillService)
	SkillService = _SkillService
end

--- 플레이어가 무적 상태인지 확인 (구르기 중)
function CombatService.isPlayerInvulnerable(userId: number): boolean
	if StaminaService then
		return StaminaService.isInvulnerable(userId)
	end
	return false
end

--========================================
-- Public API
--========================================

function CombatService.Init(_NetController, _DataService, _CreatureService, _InventoryService, _DurabilityService, _DebuffService, _WorldDropService, _PlayerStatService, _HungerService, _TechService)
	NetController = _NetController
	DataService = _DataService
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	DurabilityService = _DurabilityService
	DebuffService = _DebuffService
	WorldDropService = _WorldDropService
	PlayerStatService = _PlayerStatService
	HungerService = _HungerService
	TechService = _TechService
	
	-- 플레이어 퇴장 시 데이터 정리
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		playerAttackCooldowns[uid] = nil
		disengageCombat(uid)
		staggeredPlayers[uid] = nil
		if knockbackImmunity[uid] then
			knockbackImmunity[uid] = nil
		end
	end)
	
	-- 플레이어 사망 시 전투 상태 정리
	local function setupCharacterCleanup(player)
		if not player.Character then return end
		local hum = player.Character:FindFirstChild("Humanoid")
		if not hum then return end
		
		hum.Died:Connect(function()
			local uid = player.UserId
			disengageCombat(uid)
			staggeredPlayers[uid] = nil
			if knockbackImmunity[uid] then
				knockbackImmunity[uid] = nil
			end
		end)
	end
	
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			setupCharacterCleanup(player)
		end)
		if player.Character then
			setupCharacterCleanup(player)
		end
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			setupCharacterCleanup(player)
		end)
		if player.Character then
			setupCharacterCleanup(player)
		end
	end
	
	-- 전투 교전 타임아웃 / 거리 이탈 체크 루프
	task.spawn(function()
		while true do
			task.wait(1)
			local now = tick()
			local toDisengage = {}
			for uid, targetMap in pairs(playerCombatTargets) do
				if type(targetMap) == "table" then
					for instanceId in pairs(targetMap) do
						local shouldDisengage = false
						local lastHit = type(playerCombatLastHit[uid]) == "table" and playerCombatLastHit[uid][instanceId] or nil
						if lastHit and (now - lastHit) >= COMBAT_DISENGAGE_TIMEOUT then
							shouldDisengage = true
						end
						if not shouldDisengage then
							local plr = Players:GetPlayerByUserId(uid)
							local playerHrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
							if playerHrp and CreatureService and CreatureService.getCreaturePosition then
								local creaturePos = CreatureService.getCreaturePosition(instanceId)
								if creaturePos then
									local dist = (playerHrp.Position - creaturePos).Magnitude
									if dist >= COMBAT_DISENGAGE_DISTANCE then
										shouldDisengage = true
									end
								else
									shouldDisengage = true
								end
							end
						end
						if shouldDisengage then
							table.insert(toDisengage, { userId = uid, instanceId = instanceId })
						end
					end
				end
			end
			for _, entry in ipairs(toDisengage) do
				disengageCombat(entry.userId, entry.instanceId)
			end
		end
	end)
	
	-- 전투 중 접촉 밀어내기 체크 루프
	task.spawn(function()
		while true do
			task.wait(0.2)
			for uid, targetMap in pairs(playerCombatTargets) do
				local plr = Players:GetPlayerByUserId(uid)
				local playerHrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if playerHrp and type(targetMap) == "table" and CreatureService and CreatureService.getCreaturePosition then
					for instanceId in pairs(targetMap) do
						local creaturePos = CreatureService.getCreaturePosition(instanceId)
						if creaturePos then
							local dist = (playerHrp.Position - creaturePos).Magnitude
							if dist <= CONTACT_CHECK_DIST then
								applyContactKnockback(uid, creaturePos, instanceId)
							end
						end
					end
				end
			end
		end
	end)
	
	print("[CombatService] Initialized")
end

--- 플레이어가 대상을 공격 (Client Request)
function CombatService.processPlayerAttack(player: Player, targetId: string?, attackMeta: any?)
	if not player then return false, Enums.ErrorCode.BAD_REQUEST end
	attackMeta = attackMeta or {}
	local userId = player.UserId
	
	-- print(string.format("[CombatService] Attack Request from %s (Target: %s)", player.Name, tostring(targetId)))
	local toolSlot = 1
	if InventoryService then
		toolSlot = InventoryService.getActiveSlot(userId) or 1
	end
	
	local baseDamage = DEFAULT_BAREHAND_DAMAGE
	local range = DEFAULT_ATTACK_RANGE
	local dynamicCooldown = MIN_ATTACK_COOLDOWN
	local itemData = nil
	local toolItem = nil
	local isBlunt = true
	local isBowShot = false
	local ammoItemId = nil
	local bowChargeRatio = 0
	local bowHeldSec = 0
	local bowEffectiveRange = nil
	local bowMinAimTime = 0.2
	local bowOrigin = nil
	local rawAimDir = attackMeta.aimDirection
	local rawAimOrigin = attackMeta.aimOrigin

	local char = player.Character
	if not char then return false, Enums.ErrorCode.INTERNAL_ERROR end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	if InventoryService then
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData then
			itemData = DataService.getItem(slotData.itemId)
			if itemData then
				baseDamage = itemData.damage or 5
				range = itemData.range or (itemData.optimalTool == "SWORD" and Balance.REACH_SWORD or Balance.REACH_TOOL or 14)
				isBlunt = itemData.isBlunt == true
				toolItem = slotData
				
				if TechService and not TechService.isRecipeUnlocked(userId, slotData.itemId) then
					return false, Enums.ErrorCode.RECIPE_LOCKED
				end

				if slotData.durability and slotData.durability <= 0 then
					return false, Enums.ErrorCode.INVALID_STATE
				end

				if itemData.attackSpeed then
					dynamicCooldown = math.max(0.15, itemData.attackSpeed - 0.05)
				end

				isBowShot = (attackMeta.bowShot == true) and isBowWeapon(itemData)
				if isBowShot then
					ammoItemId = getAmmoForWeapon(slotData.itemId)
					bowChargeRatio = math.clamp(tonumber(attackMeta.chargeRatio) or 0, 0, 1)
					bowHeldSec = math.max(0, tonumber(attackMeta.heldSec) or 0)
					bowMinAimTime = math.max(0.05, tonumber(itemData.minAimTime) or 0.2)
					local maxRange = tonumber(itemData.maxRange or itemData.range) or 120
					local minRange = math.max(8, tonumber(itemData.minRange) or math.floor(maxRange * 0.25))
					bowEffectiveRange = minRange + ((maxRange - minRange) * bowChargeRatio)
					local head = char:FindFirstChild("Head")
					bowOrigin = head and head.Position or (hrp.Position + Vector3.new(0, 1.6, 0))
				end
			end
		end
	end

	if isBowShot and bowHeldSec < bowMinAimTime then
		return false, Enums.ErrorCode.INVALID_STATE
	end

	local now = tick()
	if playerAttackCooldowns[userId] and now < playerAttackCooldowns[userId] then
		return false, Enums.ErrorCode.COOLDOWN
	end
	playerAttackCooldowns[userId] = now + dynamicCooldown
	
	if isBowShot and (not targetId or targetId == "") then
		local aimDir = nil
		if type(rawAimDir) == "table" then
			aimDir = Vector3.new(tonumber(rawAimDir.x) or 0, tonumber(rawAimDir.y) or 0, tonumber(rawAimDir.z) or 0)
		elseif typeof(rawAimDir) == "Vector3" then
			aimDir = rawAimDir
		end
		if aimDir then
			targetId = findAttackTargetByRay(player, aimDir, bowEffectiveRange or range, bowOrigin)
		end
	end

	if isBowShot then
		local skipArrow = false
		if SkillService then
			local bonuses = SkillService.getPassiveBonuses(userId, "BOW")
			if (bonuses.NO_ARROW_CONSUME or 0) > 0 then
				skipArrow = true
			end
		end
		if not skipArrow then
			local consumed = false
			if ammoItemId then
				consumed = InventoryService.removeItem(userId, ammoItemId, 1) >= 1
			else
				for _, arrowId in ipairs(BOW_AMMO_TYPES) do
					if InventoryService.removeItem(userId, arrowId, 1) >= 1 then
						consumed = true
						break
					end
				end
			end
			if not consumed then
				return false, Enums.ErrorCode.MISSING_REQUIREMENTS
			end
		end
	end

	local targetObject = nil
	local targetType = "NONE"
	
	local creature = CreatureService.getCreatureRuntime(targetId)
	if creature and creature.rootPart then
		targetObject = creature.rootPart
		targetType = "CREATURE"
	end

	if targetType == "NONE" and PVP_ENABLED and targetId ~= nil then
		local targetPlayer = Players:GetPlayerFromCharacter(workspace:FindFirstChild(tostring(targetId), true))
		if not targetPlayer then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character and p.Character:GetAttribute("InstanceId") == targetId then
					targetPlayer = p
					break
				end
			end
		end
		if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
			targetObject = targetPlayer.Character.HumanoidRootPart
			targetType = "PLAYER"
		end
	end
	
	if targetType == "NONE" then
		local BuildService = require(game:GetService("ServerScriptService").Server.Services.BuildService)
		local structure = BuildService.get(targetId)
		if structure then
			return false, Enums.ErrorCode.INVALID_TARGET
		end
	end
	
	if not targetObject then
		if isBowShot then
			if NetController then
				NetController.FireClient(player, "Combat.Hit.Result", { damage = 0, torporDamage = 0, killed = false, targetId = "", miss = true })
			end
			return true, nil, { damage = 0, torporDamage = 0, killed = false, miss = true }
		end
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	local targetPos = targetObject.Position
	local dist
	if isBowShot and bowOrigin then
		dist = (targetPos - bowOrigin).Magnitude
	else
		dist = (Vector2.new(hrp.Position.X, hrp.Position.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude
	end
	
	local creatureHalfExtent = 0
	if targetType == "CREATURE" and creature and creature.model then
		local ok, extents = pcall(function() return creature.model:GetExtentsSize() end)
		if ok and extents then creatureHalfExtent = math.max(extents.X, extents.Z) * 0.5 end
	end
	
	local allowedRange = isBowShot and (bowEffectiveRange or range) or (range + 8 + creatureHalfExtent)
	if dist > allowedRange + (isBowShot and 2 or 0) then 
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	local calculated = PlayerStatService.GetCalculatedStats(userId)
	local attackMult = calculated.attackMult or 1.0

	if targetType == "CREATURE" and itemData and itemData.type == "TOOL" then
		local toolRole = tostring(itemData.optimalTool or ""):upper()
		if toolRole == "AXE" or toolRole == "PICKAXE" then
			local skipNerf = false
			if toolRole == "AXE" and SkillService then
				local treeId = SkillService.getCombatTreeId(userId)
				if treeId == "AXE" then skipNerf = true end
			end
			if not skipNerf then
				baseDamage = DEFAULT_BAREHAND_DAMAGE
				isBlunt = true
			end
		end
	end

	if targetType == "PLAYER" then
		local attackerZone = SpawnConfig.GetZoneAtPosition(hrp.Position)
		local targetZone = SpawnConfig.GetZoneAtPosition(targetPos)
		if not (PVP_ZONES[attackerZone] and PVP_ZONES[targetZone]) then
			return false, Enums.ErrorCode.PVP_DISABLED
		end
	end

	local totalDamage = baseDamage * attackMult
	if isBowShot then
		totalDamage = totalDamage * (0.55 + (bowChargeRatio * 0.85))
	end

	local skillBonuses = nil
	local weaponTreeId = getWeaponTreeId(itemData)
	if SkillService and weaponTreeId then
		skillBonuses = SkillService.getPassiveBonuses(userId, weaponTreeId)
		if skillBonuses.DAMAGE_MULT then
			totalDamage = totalDamage * (1 + skillBonuses.DAMAGE_MULT)
		end
	end

	local attrCritChance = 0
	local attrCritDamageMult = 0
	if toolItem and toolItem.attributes then
		for attrId, level in pairs(toolItem.attributes) do
			local fx = MaterialAttributeData.getEffectValues(attrId, level)
			if fx then
				if fx.damageMult then totalDamage = totalDamage * (1 + fx.damageMult) end
				attrCritChance = attrCritChance + (fx.critChance or 0)
				attrCritDamageMult = attrCritDamageMult + (fx.critDamageMult or 0)
			end
		end
	end

	if skillBonuses then
		attrCritChance = attrCritChance + (skillBonuses.CRIT_CHANCE or 0)
		attrCritDamageMult = attrCritDamageMult + (skillBonuses.CRIT_DAMAGE_MULT or 0)
	end

	local variance = Balance.DAMAGE_VARIANCE or 0.15
	totalDamage = totalDamage * (1 + (math.random() * 2 - 1) * variance)

	local isCritical = false
	if attrCritChance > 0 and math.random() < attrCritChance then
		isCritical = true
		totalDamage = totalDamage * (1.5 + attrCritDamageMult)
	end

	local hpDamage = totalDamage
	local torporDamage = 0
	if isBlunt then
		hpDamage = totalDamage * 0.5
		torporDamage = totalDamage * 0.5
	end

	-- ★ 레벨 차이 데미지 보정 (Player -> Creature)
	if targetType == "CREATURE" and creature then
		local playerLevel = PlayerStatService.getLevel(userId)
		local creatureLevel = creature.level or 1
		local levelMod = CombatService.getLevelModifier(playerLevel, creatureLevel)
		
		hpDamage = hpDamage * levelMod
		torporDamage = torporDamage * levelMod
	end
	
	local killed = false
	local dropPos = nil
	
	if targetType == "CREATURE" then
		engageCombat(userId, targetId, true)
		killed, dropPos = CreatureService.processAttack(targetId, hpDamage, torporDamage, player)
		if killed then disengageCreature(targetId) end
		
		if creature and creature.rootPart then
			local creaturePos = creature.rootPart.Position
			if not killed then
				local knockDir = (creaturePos - hrp.Position)
				knockDir = Vector3.new(knockDir.X, 0, knockDir.Z).Unit
				creature.rootPart.AssemblyLinearVelocity = knockDir * (Balance.CREATURE_KNOCKBACK_FORCE or 12) + Vector3.new(0, creature.rootPart.AssemblyLinearVelocity.Y * 0.8, 0)
				task.delay(0.08, function()
					if creature and creature.rootPart then
						creature.rootPart.AssemblyLinearVelocity = Vector3.new(0, creature.rootPart.AssemblyLinearVelocity.Y, 0)
					end
				end)
			end
			if NetController then
				NetController.FireAllClients("Combat.Creature.Hit", { instanceId = targetId, hitPosition = { x = creaturePos.X, y = creaturePos.Y, z = creaturePos.Z }, damage = hpDamage, killed = killed })
			end
		end
	elseif targetType == "PLAYER" then
		local targetPlayer = Players:GetPlayerFromCharacter(targetObject.Parent)
		if targetPlayer then
			CombatService.damagePlayer(targetPlayer.UserId, hpDamage, hrp.Position)
			killed = (targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") and targetPlayer.Character.Humanoid.Health <= 0) or false
		end
	end
	
	if (not isBowShot) and toolItem and toolSlot and toolItem.durability then
		DurabilityService.reduceDurability(player, toolSlot, 1)
	end
	
	if HungerService then
		HungerService.consumeHunger(userId, Balance.HUNGER_COMBAT_COST)
	end

	if skillBonuses and targetType == "CREATURE" and hpDamage > 0 then
		local healChance = skillBonuses.HEAL_ON_HIT_CHANCE or 0
		if healChance > 0 and math.random() < healChance then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + (humanoid.MaxHealth * (skillBonuses.HEAL_ON_HIT_PCT or 0)))
			end
		end
	end
	
	if killed and targetType == "CREATURE" and DebuffService then
		DebuffService.applyDebuff(userId, "BLOOD_SMELL")
	end
	
	if killed and targetType == "CREATURE" and questCallback and creature and creature.data then
		questCallback(userId, creature.data.id or creature.data.creatureId)
	end
	
	if NetController then
		NetController.FireClient(player, "Combat.Hit.Result", {
			damage = hpDamage,
			torporDamage = torporDamage,
			killed = killed,
			targetId = targetId,
			bowShot = isBowShot,
			chargeRatio = bowChargeRatio,
			isCritical = isCritical,
			currentHP = creature and creature.currentHealth or 0,
			maxHP = creature and (creature.maxHealth or (creature.data and creature.data.maxHealth)) or 100,
		})
	end
	
	return true, nil, { damage = hpDamage, torporDamage = torporDamage, killed = killed }
end

function CombatService.damagePlayer(userId: number, rawDamage: number, sourcePos: Vector3?, sourceCreatureId: string?)
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player or not player.Character then return end
	
	local humanoid = player.Character:FindFirstChild("Humanoid")
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid.Health <= 0 then return end
	
	if CombatService.isPlayerInvulnerable(userId) then return end
	
	if sourceCreatureId then engageCombat(userId, sourceCreatureId, true) end
	
	local defense = 0
	if InventoryService and InventoryService.getTotalDefense then
		defense = InventoryService.getTotalDefense(userId)
	end
	
	local reductionMult = 100 / (100 + defense)
	local variance = Balance.DAMAGE_VARIANCE or 0.15
	local finalDamage = rawDamage * reductionMult * (1 + (math.random() * 2 - 1) * variance)

	-- ★ 레벨 차이 데미지 보정 (Creature -> Player)
	if sourceCreatureId then
		local creature = CreatureService.getCreatureRuntime(sourceCreatureId)
		if creature then
			local playerLevel = PlayerStatService.getLevel(userId)
			local creatureLevel = creature.level or 1
			local levelMod = CombatService.getLevelModifier(creatureLevel, playerLevel)
			
			finalDamage = finalDamage * levelMod
		end
	end
	
	finalDamage = math.max(1, finalDamage)
	
	if InventoryService and InventoryService.decreaseEquipmentDurability then
		local armorDamage = math.max(1, math.floor(rawDamage * (Balance.ARMOR_DURABILITY_LOSS_RATIO or 0.1)))
		local equip = InventoryService.getEquipment(userId)
		if equip.SUIT then
			local headDamage = equip.HEAD and math.max(1, math.ceil(armorDamage * 0.2)) or 0
			InventoryService.decreaseEquipmentDurability(userId, "SUIT", armorDamage - headDamage)
			if headDamage > 0 then InventoryService.decreaseEquipmentDurability(userId, "HEAD", headDamage) end
		elseif equip.HEAD then
			InventoryService.decreaseEquipmentDurability(userId, "HEAD", armorDamage)
		end
	end
	
	humanoid:TakeDamage(finalDamage)
	
	if NetController then
		NetController.FireClient(player, "Combat.Player.Hit", {
			damage = finalDamage,
			sourcePos = sourcePos,
			knockbackForce = sourcePos and (Balance.KNOCKBACK_FORCE or 25) or nil,
		})
	end
end

function CombatService.GetHandlers()
	return {
		["Combat.Hit.Request"] = function(player, payload)
			local targetId = payload.targetId or payload.targetInstanceId
			local success, errorCode, result = CombatService.processPlayerAttack(player, targetId, {
				bowShot = payload.bowShot,
				chargeRatio = payload.chargeRatio,
				aimDirection = payload.aimDirection,
				aimOrigin = payload.aimOrigin,
				heldSec = payload.heldSec,
			})
			if not success then return { success = false, errorCode = errorCode } end
			return { success = true, data = result }
		end
	}
end

function CombatService.SetQuestCallback(callback) questCallback = callback end
function CombatService.disengageCreature(instanceId: string) disengageCreature(instanceId) end
function CombatService.engageCombat(userId: number, instanceId: string) engageCombat(userId, instanceId, false) end
function CombatService.engagePlayerCombat(userId: number, instanceId: string) engageCombat(userId, instanceId, true) end
function CombatService.getPlayerCombatTarget(userId: number): string? return playerCombatPrimaryTarget[userId] end

return CombatService
