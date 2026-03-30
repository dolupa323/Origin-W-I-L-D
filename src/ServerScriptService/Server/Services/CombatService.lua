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
local PVP_ENABLED = false       -- PvP 비활성화

-- Combat Engagement Constants
local COMBAT_DISENGAGE_TIMEOUT = 8   -- 교전 없이 8초 경과 → 전투 해제
local COMBAT_DISENGAGE_DISTANCE = 50 -- 50스터드 이상 벗어나면 즉시 전투 해제
local CONTACT_KNOCKBACK_FORCE = 18   -- 전투 중 접촉 시 밀어내기 힘
local CONTACT_STAGGER_DURATION = 0.3 -- 접촉 경직 시간 (초)
local CONTACT_STAGGER_COOLDOWN = 2.0 -- 접촉 경직 쿨다운 (경직 해제 후 재발동까지)
local CONTACT_CHECK_DIST = 5         -- 접촉 판정 거리 (스터드)

-- State
local playerAttackCooldowns = {} -- [userId] = nextAttackTime

-- Combat Engagement State
local playerCombatTarget = {}     -- [userId] = instanceId (플레이어가 전투 중인 크리처)
local playerCombatLastHit = {}    -- [userId] = tick() (마지막 교전 시각)
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

local function applyContactKnockback(userId, creaturePos)
	if staggeredPlayers[userId] then return end
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

	-- 밀어내기
	hrp.AssemblyLinearVelocity = pushDir * CONTACT_KNOCKBACK_FORCE + Vector3.new(0, 4, 0)

	-- 짧은 경직 (StaminaService 경유 속도 배율 적용)
	staggeredPlayers[userId] = true
	if StaminaService and StaminaService.setStagger then
		StaminaService.setStagger(userId, 0.15, CONTACT_STAGGER_DURATION)
	end
	
	-- 클라이언트에 접촉 경직 알림 (화면 효과용)
	if NetController then
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			NetController.FireClient(plr, "Combat.Contact.Stagger", {
				sourcePos = {creaturePos.X, creaturePos.Y, creaturePos.Z},
			})
		end
	end

	-- 쿨다운: 경직 해제 후에도 일정 시간 재발동 방지
	task.delay(CONTACT_STAGGER_DURATION + CONTACT_STAGGER_COOLDOWN, function()
		staggeredPlayers[userId] = nil
	end)
end

--- 전투 상태 진입 (플레이어 → 크리처)
local function engageCombat(userId, instanceId)
	local now = tick()
	local prevTarget = playerCombatTarget[userId]

	-- 이미 같은 대상과 전투 중이면 시각만 갱신
	if prevTarget == instanceId then
		playerCombatLastHit[userId] = now
		return
	end

	-- 기존 전투 대상에서 제거
	if prevTarget and creatureCombatants[prevTarget] then
		creatureCombatants[prevTarget][userId] = nil
		if not next(creatureCombatants[prevTarget]) then
			creatureCombatants[prevTarget] = nil
			-- 기존 크리처 충돌 그룹 복구 (더 이상 전투 중인 플레이어 없음)
			setCreatureCollisionGroup(prevTarget, "Creatures")
			-- 전투 해제 알림 (기존 크리처)
			if NetController then
				NetController.FireAllClients("Combat.Engagement.Changed", {
					instanceId = prevTarget,
					inCombat = false,
				})
			end
		end
	end

	-- 새 전투 등록
	playerCombatTarget[userId] = instanceId
	playerCombatLastHit[userId] = now

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
end

--- 전투 상태 해제 (플레이어)
local function disengageCombat(userId)
	local instanceId = playerCombatTarget[userId]
	if not instanceId then return end

	playerCombatTarget[userId] = nil
	playerCombatLastHit[userId] = nil

	if creatureCombatants[instanceId] then
		creatureCombatants[instanceId][userId] = nil
		if not next(creatureCombatants[instanceId]) then
			creatureCombatants[instanceId] = nil
			-- 전투 해제 → 충돌 그룹 복구
			setCreatureCollisionGroup(instanceId, "Creatures")
			if NetController then
				NetController.FireAllClients("Combat.Engagement.Changed", {
					instanceId = instanceId,
					inCombat = false,
				})
			end
		end
	end
end

--- 크리처 사망/디스폰 시 전투 상태 전체 해제
local function disengageCreature(instanceId)
	local combatants = creatureCombatants[instanceId]
	if not combatants then return end

	for uid, _ in pairs(combatants) do
		playerCombatTarget[uid] = nil
		playerCombatLastHit[uid] = nil
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

local function getAmmoForWeapon(itemId: string): string?
	local upper = string.upper(tostring(itemId or ""))
	if upper == "WOODEN_BOW" then return "STONE_ARROW" end
	if upper == "BRONZE_BOW" then return "BRONZE_ARROW" end
	if upper == "CROSSBOW" then return "IRON_BOLT" end
	return nil
end

--- 무기 아이템 정보로 스킬 트리 ID 결정 (SWORD/BOW/AXE)
local function getWeaponTreeId(itemData): string?
	if not itemData then return nil end
	local opt = string.upper(tostring(itemData.optimalTool or ""))
	if opt == "SWORD" then return "SWORD" end
	if opt == "BOW" or opt == "CROSSBOW" then return "BOW" end
	if opt == "AXE" then return "AXE" end
	-- itemId 기반 폴백
	local id = string.upper(tostring(itemData.id or ""))
	if id:find("SWORD", 1, true) then return "SWORD" end
	if id:find("BOW", 1, true) then return "BOW" end
	if id:find("AXE", 1, true) then return "AXE" end
	return nil
end

local function findAttackTargetByRay(player: Player, direction: Vector3, range: number, originOverride: Vector3?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then return nil, nil end

	if direction.Magnitude <= 0.001 then return nil, nil end
	local dirUnit = direction.Unit
	local origin = hrp.Position + Vector3.new(0, 1.6, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = workspace:Raycast(origin, dirUnit * range, params)
	if not result or not result.Instance then
		return nil, origin + (dirUnit * range)
	end

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

	return nil, result.Position
end

--========================================
-- StaminaService Integration (Phase 10)
--========================================

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
	end)
	
	-- 전투 교전 타임아웃 / 거리 이탈 체크 루프
	task.spawn(function()
		while true do
			task.wait(1)
			local now = tick()
			local toDisengage = {}
			for uid, instanceId in pairs(playerCombatTarget) do
				local shouldDisengage = false
				-- 시간 초과 체크
				local lastHit = playerCombatLastHit[uid]
				if lastHit and (now - lastHit) >= COMBAT_DISENGAGE_TIMEOUT then
					shouldDisengage = true
				end
				-- 거리 이탈 체크
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
						end
					end
				end
				if shouldDisengage then
					table.insert(toDisengage, uid)
				end
			end
			for _, uid in ipairs(toDisengage) do
				disengageCombat(uid)
			end
		end
	end)
	
	-- 전투 중 접촉 밀어내기 체크 루프 (0.2초 간격)
	task.spawn(function()
		while true do
			task.wait(0.2)
			for uid, instanceId in pairs(playerCombatTarget) do
				local plr = Players:GetPlayerByUserId(uid)
				local playerHrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if playerHrp and CreatureService and CreatureService.getCreaturePosition then
					local creaturePos = CreatureService.getCreaturePosition(instanceId)
					if creaturePos then
						local dist = (playerHrp.Position - creaturePos).Magnitude
						if dist <= CONTACT_CHECK_DIST then
							applyContactKnockback(uid, creaturePos)
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
	if not player then 
		return false, Enums.ErrorCode.BAD_REQUEST 
	end
	attackMeta = attackMeta or {}

	-- 0. 서버 메모리의 실제 활성 슬롯 데이터 로드 (보안: 클라이언트 요청 슬롯 무시)
	local userId = player.UserId
	local toolSlot = 1
	if InventoryService then
		toolSlot = InventoryService.getActiveSlot(userId) or 1
	end
	
	local baseDamage = DEFAULT_BAREHAND_DAMAGE -- 맨손 기본 데미지
	local range = DEFAULT_ATTACK_RANGE
	local dynamicCooldown = MIN_ATTACK_COOLDOWN -- 기본 0.35초
	local itemData = nil
	local toolItem = nil
	local isBlunt = true -- 맨손은 기본적으로 타격(Blunt) 판정 (기절 수치 부여)
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
				
				-- [보안/기획] 기술 해금 체크 (Relinquish 어뷰징 방지)
				if TechService and not TechService.isRecipeUnlocked(userId, slotData.itemId) then
					return false, Enums.ErrorCode.RECIPE_LOCKED
				end

				-- 내구도 체크: 파손된 도구는 공격 불가능
				if slotData.durability and slotData.durability <= 0 then
					return false, Enums.ErrorCode.INVALID_STATE
				end

				-- 아이템의 attackSpeed를 쿨다운으로 사용
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

					if type(rawAimOrigin) == "table" then
						-- [보안] 클라이언트 aimOrigin 무시 - 서버 권위 위치 사용
						local head = char and char:FindFirstChild("Head")
						bowOrigin = head and head.Position or (hrp.Position + Vector3.new(0, 1.6, 0))
					end
				end
			end
		end
	end

	if isBowShot and bowHeldSec < bowMinAimTime then
		return false, Enums.ErrorCode.INVALID_STATE
	end

	-- 1. 서버 측 공격 쿨다운 검증 (Exploit 방지 - 무기 스왑 어뷰징 차단)
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

	if isBowShot and ammoItemId then
		-- 스킬 패시브: NO_ARROW_CONSUME 체크
		local skipArrow = false
		if SkillService then
			local bonuses = SkillService.getPassiveBonuses(userId, "BOW")
			if (bonuses.NO_ARROW_CONSUME or 0) > 0 then
				skipArrow = true
			end
		end
		if not skipArrow then
			local removed = InventoryService.removeItem(userId, ammoItemId, 1)
			if removed < 1 then
				return false, Enums.ErrorCode.MISSING_REQUIREMENTS
			end
		end
	end

	-- 2. 대상(크리처 또는 건축물) 확인 및 거리 검증
	local targetObject = nil
	local targetType = "NONE"
	
	-- 3.1 크리처 먼저 체크
	local creature = CreatureService.getCreatureRuntime(targetId)
	if creature and creature.rootPart then
		targetObject = creature.rootPart
		targetType = "CREATURE"
	end
	
	-- 3.2 건축물 체크 — 일반 공격으로는 건축물에 피해를 줄 수 없음
	if targetType == "NONE" then
		local BuildServiceCheck = require(game:GetService("ServerScriptService").Server.Services.BuildService)
		local structure = BuildServiceCheck.get(targetId)
		if structure then
			return false, Enums.ErrorCode.INVALID_TARGET
		end
	end
	
	if not targetObject then
		if isBowShot then
			if NetController then
				NetController.FireClient(player, "Combat.Hit.Result", {
					damage = 0,
					torporDamage = 0,
					killed = false,
					targetId = "",
					miss = true,
				})
			end
			return true, nil, { damage = 0, torporDamage = 0, killed = false, miss = true }
		end
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	local targetPos = (targetType == "STRUCTURE" and targetObject.Position) or targetObject.Position
	local dist
	if isBowShot and bowOrigin then
		dist = (targetPos - bowOrigin).Magnitude
	else
		local p1 = Vector2.new(hrp.Position.X, hrp.Position.Z)
		local p2 = Vector2.new(targetPos.X, targetPos.Z)
		dist = (p1 - p2).Magnitude
	end
	
	-- 활은 조준 시간 기반 유효 사거리로 엄격 검증, 근접 무기는 기존 완화 검증 유지
	local allowedRange = isBowShot and (bowEffectiveRange or range) or (range + 50)
	if dist > allowedRange + (isBowShot and 2 or 0) then 
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	-- 3. 플레이어 공격력 스탯 보너스 적용
	local calculated = PlayerStatService.GetCalculatedStats(player.UserId)
	local attackMult = calculated.attackMult or 1.0

	-- 도끼/곡괭이는 동물/공룡 상대로 맨손 데미지로 고정.
	if targetType == "CREATURE" and itemData and itemData.type == "TOOL" then
		local toolRole = tostring(itemData.optimalTool or ""):upper()
		if toolRole == "AXE" or toolRole == "PICKAXE" then
			baseDamage = DEFAULT_BAREHAND_DAMAGE
			isBlunt = true
		end
	end

	local totalDamage = baseDamage * attackMult
	if isBowShot then
		local chargeMult = 0.55 + (bowChargeRatio * 0.85) -- 55% ~ 140%
		totalDamage = totalDamage * chargeMult
	end

	-- ★ 스킬 패시브 보너스 적용 (DAMAGE_MULT, CRIT_CHANCE, CRIT_DAMAGE_MULT)
	local skillBonuses = nil
	local weaponTreeId = getWeaponTreeId(itemData)
	if SkillService and weaponTreeId then
		skillBonuses = SkillService.getPassiveBonuses(userId, weaponTreeId)
		local skillDmgMult = skillBonuses.DAMAGE_MULT or 0
		if skillDmgMult > 0 then
			totalDamage = totalDamage * (1 + skillDmgMult)
		end
	end

	-- ★ 무기 속성 효과 적용 (다중 속성 합산)
	local attrCritChance = 0
	local attrCritDamageMult = 0
	if toolItem and toolItem.attributes then
		for attrId, level in pairs(toolItem.attributes) do
			local fx = MaterialAttributeData.getEffectValues(attrId, level)
			if fx then
				if fx.damageMult ~= 0 then
					totalDamage = totalDamage * (1 + fx.damageMult)
				end
				attrCritChance = attrCritChance + (fx.critChance or 0)
				attrCritDamageMult = attrCritDamageMult + (fx.critDamageMult or 0)
			end
		end
	end

	-- ★ 스킬 패시브 크릿 보너스 합산
	if skillBonuses then
		attrCritChance = attrCritChance + (skillBonuses.CRIT_CHANCE or 0)
		attrCritDamageMult = attrCritDamageMult + (skillBonuses.CRIT_DAMAGE_MULT or 0)
	end

	-- ★ 데미지 등락폭 적용 (±VARIANCE)
	local variance = Balance.DAMAGE_VARIANCE or 0.15
	local varianceMult = 1 + (math.random() * 2 - 1) * variance
	totalDamage = math.max(1, totalDamage * varianceMult)

	-- ★ 치명타 판정 (속성 기반 확률)
	local isCritical = false
	if attrCritChance > 0 and math.random() < attrCritChance then
		isCritical = true
		local critMultiplier = 1.5 + attrCritDamageMult  -- 기본 치명타 150% + 속성 보너스
		totalDamage = totalDamage * critMultiplier
	end

	-- 4. 데미지 및 기절 수치 적용
	local hpDamage = totalDamage
	local torporDamage = 0
	
	if isBlunt then
		hpDamage = totalDamage * 0.5  -- 둔기는 체력 데미지 50%
		torporDamage = totalDamage * 0.5 -- 기절 데미지 50%
	end
	
	local killed = false
	local dropPos = nil
	
	if targetType == "CREATURE" then
		-- 이미 다른 크리처와 전투 중이면 공격 불가
		local currentTarget = playerCombatTarget[userId]
		if currentTarget and currentTarget ~= targetId then
			return false, Enums.ErrorCode.ALREADY_IN_COMBAT
		end
		-- 전투 상태 진입 (플레이어 선공)
		engageCombat(userId, targetId)
		killed, dropPos = CreatureService.processAttack(targetId, hpDamage, torporDamage, player)
		if killed then
			disengageCreature(targetId)
		end
		
		-- ★ 크리처 넉백 + 피격 연출 (모든 클라이언트에 전달)
		if creature and creature.rootPart then
			local creaturePos = creature.rootPart.Position
			local attackerPos = char and char.PrimaryPart and char.PrimaryPart.Position or creaturePos
			
			-- 넉백 (생존 시만)
			if not killed then
				local knockDir = (creaturePos - attackerPos)
				knockDir = Vector3.new(knockDir.X, 0, knockDir.Z)
				if knockDir.Magnitude > 0.01 then
					knockDir = knockDir.Unit
				else
					knockDir = Vector3.new(0, 0, 1)
				end
				local knockForce = Balance.CREATURE_KNOCKBACK_FORCE or 12
				creature.rootPart.AssemblyLinearVelocity = knockDir * knockForce + Vector3.new(0, 4, 0)
			end
			
			-- 모든 클라이언트에 피격 연출 이벤트 (파티클 + 히트스톱)
			if NetController then
				NetController.FireAllClients("Combat.Creature.Hit", {
					instanceId = targetId,
					hitPosition = { x = creaturePos.X, y = creaturePos.Y, z = creaturePos.Z },
					damage = hpDamage,
					killed = killed,
				})
			end
		end
	end
	
	-- 4. 도구 내구도 감소
	if (not isBowShot) and toolItem and toolSlot and toolItem.durability then
		DurabilityService.reduceDurability(player, toolSlot, 1)
	end
	
	-- 4.5 전투 시 배고픔 소모 연동 (Phase 11)
	if HungerService then
		HungerService.consumeHunger(player.UserId, Balance.HUNGER_COMBAT_COST)
	end

	-- 4.6 스킬 패시브: 적중 시 HP 회복 (도끼 대가 HEAL_ON_HIT)
	if skillBonuses and targetType == "CREATURE" and hpDamage > 0 then
		local healChance = skillBonuses.HEAL_ON_HIT_CHANCE or 0
		local healPct = skillBonuses.HEAL_ON_HIT_PCT or 0
		if healChance > 0 and healPct > 0 and math.random() < healChance then
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local healAmount = humanoid.MaxHealth * healPct
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
			end
		end
	end
	
	-- 5. 피냄새 디버프 및 드롭 생성 (크리처를 킬했을 때)
	if killed and dropPos and targetType == "CREATURE" and creature then
		-- 피냄새 적용
		if DebuffService then
			DebuffService.applyDebuff(player.UserId, "BLOOD_SMELL")
		end
		
		-- 드롭 아이템 생성
		if WorldDropService and DataService then
			local dropTable = DataService.getDropTable(creature.creatureId)
			if dropTable then
				for _, entry in ipairs(dropTable) do
					if math.random() <= (entry.chance or 1.0) then
						local count = math.random(entry.min or 1, entry.max or 1)
						-- 랜덤 오프셋
						local angle = math.random() * math.pi * 2
						local radius = math.random() * 2
						local baseSpawnPos = dropPos + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
						
						-- [개선] 지면 인식 레이캐스트 (피격 대상 및 플레이어 제외하여 바닥 찾기)
						local rayParams = RaycastParams.new()
						local excludeList = {char}
						if creature and creature.model then table.insert(excludeList, creature.model) end
						rayParams.FilterDescendantsInstances = excludeList
						rayParams.FilterType = Enum.RaycastFilterType.Exclude
						
						local rayResult = workspace:Raycast(baseSpawnPos, Vector3.new(0, -30, 0), rayParams)
						local finalSpawnPos = rayResult and rayResult.Position or (dropPos + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
						
						local creatureLevel = creature.data and creature.data.level or 1
						WorldDropService.spawnDrop(finalSpawnPos, entry.itemId, count, nil, creatureLevel)
					end
				end
			end
		end
	end
	
	-- 5.5 퀘스트 콜백 (Phase 8)
	if killed and targetType == "CREATURE" and questCallback and creature and creature.data then
		questCallback(player.UserId, creature.data.id or creature.data.creatureId)
	end
	
	-- 6. 타격 피드백 (Client Event)
	if NetController then
		NetController.FireClient(player, "Combat.Hit.Result", {
			damage = hpDamage,
			torporDamage = torporDamage,
			killed = killed,
			targetId = targetId,
			bowShot = isBowShot,
			chargeRatio = bowChargeRatio,
			isCritical = isCritical,
		})
	end
	
	local targetLabel = targetId
	if targetType == "CREATURE" and creature and creature.data then
		targetLabel = creature.data.name or creature.data.id or targetId
	end

	print(string.format("[CombatService] %s hit %s for %.1f (Torpor: %.1f) dmg%s", 
		player.Name, targetLabel, hpDamage, torporDamage, killed and " (KILLED)" or ""))
	
	return true, nil, { damage = hpDamage, torporDamage = torporDamage, killed = killed }
end

--- 플레이어에게 데미지 적용 (방어력 반영 + 넉백 적용)
--- sourceCreatureId: 공격한 크리처 instanceId (선택) — 전투 교전 등록에 사용
function CombatService.damagePlayer(userId: number, rawDamage: number, sourcePos: Vector3?, sourceCreatureId: string?)
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player or not player.Character then return end
	
	local humanoid = player.Character:FindFirstChild("Humanoid")
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid.Health <= 0 then return end
	
	-- 1. 무적 상태 체크 (구르기 등)
	if CombatService.isPlayerInvulnerable(userId) then
		return
	end
	
	-- 1.5 크리처 선공 → 전투 교전 등록
	if sourceCreatureId then
		engageCombat(userId, sourceCreatureId)
	end
	
	-- 2. 방어력 계산
	local defense = 0
	if InventoryService and InventoryService.getTotalDefense then
		defense = InventoryService.getTotalDefense(userId)
	end
	
	-- 데미지 감쇄 공식: final = raw * (100 / (100 + defense))
	local reductionMult = 100 / (100 + defense)
	-- ★ 크리처 공격 데미지 등락폭 (±VARIANCE)
	local variance = Balance.DAMAGE_VARIANCE or 0.15
	local varianceMult = 1 + (math.random() * 2 - 1) * variance
	local finalDamage = math.max(1, rawDamage * reductionMult * varianceMult)
	
	-- 3. 방어구 내구도 감소
	if InventoryService and InventoryService.decreaseEquipmentDurability then
		local armorDamage = math.max(1, math.floor(rawDamage * (Balance.ARMOR_DURABILITY_LOSS_RATIO or 0.1)))
		local equip = InventoryService.getEquipment(userId)
		
		if equip.SUIT then
			local headDamage = equip.HEAD and math.max(1, math.ceil(armorDamage * 0.2)) or 0
			local suitDamage = math.max(1, armorDamage - headDamage)
			InventoryService.decreaseEquipmentDurability(userId, "SUIT", suitDamage)
			if equip.HEAD and headDamage > 0 then
				InventoryService.decreaseEquipmentDurability(userId, "HEAD", headDamage)
			end
		else
			if equip.HEAD then
				InventoryService.decreaseEquipmentDurability(userId, "HEAD", armorDamage)
			end
		end
	end
	
	-- 4. 데미지 적용
	humanoid:TakeDamage(finalDamage)
	
	-- 5. ★ 물리적 피격 피드백 (넉백 + 클라이언트 연출)
	if sourcePos then
		-- 반대 방향으로 밀어냄
		local diff = (hrp.Position - sourcePos)
		local dir = Vector3.new(diff.X, 0, diff.Z).Unit
		
		-- 넉백 강도 상향 및 Y축 방향성 추가 (살짝 뜨게 하여 마찰력 무시)
		hrp.AssemblyLinearVelocity = dir * (Balance.KNOCKBACK_FORCE or 25) + Vector3.new(0, 15, 0)
		
		-- [추가] 눕기/넘어짐 방지를 위해 서버에서도 상태 강제 고정
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	
	-- 6. 클라이언트 연출 요청 (화면 흔들림, 피격 효과 등)
	if NetController then
		NetController.FireClient(player, "Combat.Player.Hit", {
			damage = finalDamage,
			sourcePos = sourcePos
		})
	end
	
	print(string.format("[CombatService] Player %s took %.1f damage (Raw: %.1f, Def: %d)", 
		player.Name, finalDamage, rawDamage, defense))
end

--========================================
-- Network Handlers
--========================================

local function handleHitRequest(player, payload)
	local targetId = payload.targetId or payload.targetInstanceId
	local attackMeta = {
		bowShot = payload.bowShot,
		chargeRatio = payload.chargeRatio,
		aimDirection = payload.aimDirection,
		aimOrigin = payload.aimOrigin,
		heldSec = payload.heldSec,
	}
	
	local success, errorCode, result = CombatService.processPlayerAttack(player, targetId, attackMeta)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = result }
end

function CombatService.GetHandlers()
	return {
		["Combat.Hit.Request"] = handleHitRequest
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function CombatService.SetQuestCallback(callback)
	questCallback = callback
end

--- 크리처 디스폰/사망 시 외부 호출용 전투 상태 해제
function CombatService.disengageCreature(instanceId: string)
	disengageCreature(instanceId)
end

--- 플레이어의 현재 전투 대상 반환
function CombatService.getPlayerCombatTarget(userId: number): string?
	return playerCombatTarget[userId]
end

return CombatService
