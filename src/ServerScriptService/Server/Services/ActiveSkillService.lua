-- ActiveSkillService.lua
-- 액티브 스킬 실행 서버 서비스
-- 스킬 발동 검증, 쿨다운 관리, 데미지 계산, 디버프 적용

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)
local MaterialAttributeData = require(Data.MaterialAttributeData)

local ActiveSkillService = {}

-- Dependencies (injected via Init)
local NetController
local SkillService
local CombatService
local CreatureService
local InventoryService
local DataService
local PlayerStatService
local DebuffService
local StaminaService
local HungerService

-- Constants
local DEV_NO_COOLDOWN = true             -- ★ 개발용 노쿨 (릴리즈 시 false로 변경)
local SKILL_STAMINA_COST = 15           -- 스킬 사용 시 스태미나 소모
local SKILL_GCD = 0.5                    -- 글로벌 쿨다운 (연타 방지)
local MULTI_HIT_INTERVAL = 0.3          -- 멀티히트 간격 (초)
local CHARGE_SKILL_GCD = 0.3            -- 차지 스킬 완료 후 GCD
local DEFAULT_BAREHAND_DAMAGE = 5

-- State
local playerSkillCooldowns = {}  -- [userId] = { [skillId] = nextAvailableTime }
local playerGCD = {}              -- [userId] = nextGCDTime

--========================================
-- Internal Helpers
--========================================

--- 무기 트리 ID 판별 (CombatService 패턴 동일)
local function getWeaponTreeId(itemData)
	if not itemData then return nil end
	local tool = tostring(itemData.optimalTool or ""):upper()
	if tool == "SWORD" then return "SWORD" end
	if tool == "BOW" or tool == "CROSSBOW" then return "BOW" end
	if tool == "AXE" then return "AXE" end
	-- itemId 패턴 폴백
	local id = tostring(itemData.itemId or ""):upper()
	if id:find("SWORD") then return "SWORD" end
	if id:find("BOW") or id:find("CROSSBOW") then return "BOW" end
	if id:find("AXE") then return "AXE" end
	return nil
end

--- 스킬 이펙트에서 특정 stat 값 추출
local function getEffectValue(skill, statName: string): number
	if not skill or not skill.effects then return 0 end
	for _, eff in ipairs(skill.effects) do
		if eff.stat == statName then
			return eff.value
		end
	end
	return 0
end

--- 기본 무기 데미지 조회 (CombatService 로직 미러)
local function getWeaponBaseDamage(player: Player): (number, any, number?)
	local userId = player.UserId
	if not InventoryService then return DEFAULT_BAREHAND_DAMAGE, nil, nil end
	
	local toolSlot = InventoryService.getActiveSlot(userId) or 1
	local slotData = InventoryService.getSlot(userId, toolSlot)
	if not slotData then return DEFAULT_BAREHAND_DAMAGE, nil, nil end
	
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData then return DEFAULT_BAREHAND_DAMAGE, nil, nil end
	
	return itemData.damage or DEFAULT_BAREHAND_DAMAGE, itemData, toolSlot
end

--- AOE 범위 내 크리처 검색
local function findCreaturesInRadius(center: Vector3, radius: number, excludeId: string?): { any }
	local results = {}
	if not CreatureService or not CreatureService.getActiveCreatures then return results end
	
	local allCreatures = CreatureService.getActiveCreatures()
	for instanceId, creature in pairs(allCreatures) do
		if instanceId ~= excludeId and creature.rootPart then
			local dist = (creature.rootPart.Position - center).Magnitude
			if dist <= radius then
				table.insert(results, { instanceId = instanceId, creature = creature, distance = dist })
			end
		end
	end
	return results
end

--- 치명타 확률/배율 계산 (무기 속성 + 스킬 패시브 반영)
local function getCritInfo(player: Player, itemData: any?): (number, number)
	local userId = player.UserId
	local critChance = 0
	local critDamageMult = 0
	
	-- 무기 속성 효과
	if InventoryService then
		local toolSlot = InventoryService.getActiveSlot(userId) or 1
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData and slotData.attributes then
			for attrId, level in pairs(slotData.attributes) do
				local fx = MaterialAttributeData.getEffectValues(attrId, level)
				if fx then
					critChance = critChance + (fx.critChance or 0)
					critDamageMult = critDamageMult + (fx.critDamageMult or 0)
				end
			end
		end
	end
	
	-- 스킬 패시브 보너스
	local weaponTreeId = getWeaponTreeId(itemData)
	if SkillService and weaponTreeId then
		local bonuses = SkillService.getPassiveBonuses(userId, weaponTreeId)
		if bonuses then
			critChance = critChance + (bonuses.CRIT_CHANCE or 0)
			critDamageMult = critDamageMult + (bonuses.CRIT_DAMAGE_MULT or 0)
		end
	end
	
	return critChance, critDamageMult
end

--- 치명타 판정 및 데미지 적용
local function rollCritical(damage: number, critChance: number, critDamageMult: number): (number, boolean)
	if critChance > 0 and math.random() < critChance then
		local multiplier = 1.5 + critDamageMult  -- 기본 150% + 속성 보너스
		return damage * multiplier, true
	end
	return damage, false
end

--- 단일 타겟에 스킬 데미지 적용 (lastKnownPos: 크리처 사망 후에도 데미지 표시를 위한 마지막 위치)
local function applySkillDamage(player: Player, targetInstanceId: string, damage: number, isBlunt: boolean?, lastKnownPos: Vector3?, isCritical: boolean?)
	if not CreatureService then return false, false end
	
	local userId = player.UserId
	local hpDamage = damage
	local torporDamage = 0
	
	if isBlunt then
		hpDamage = damage * 0.5
		torporDamage = damage * 0.5
	end
	
	local killed, dropPos = CreatureService.processAttack(targetInstanceId, hpDamage, torporDamage, player)
	
	-- 넉백 + 피격 연출
	local creature = CreatureService.getCreatureRuntime(targetInstanceId)
	local displayPos = lastKnownPos -- 폴백 위치
	if creature and creature.rootPart then
		local creaturePos = creature.rootPart.Position
		displayPos = creaturePos
		local char = player.Character
		local attackerPos = char and char.PrimaryPart and char.PrimaryPart.Position or creaturePos
		
		if not killed then
			local knockDir = (creaturePos - attackerPos)
			knockDir = Vector3.new(knockDir.X, 0, knockDir.Z)
			if knockDir.Magnitude > 0.01 then
				knockDir = knockDir.Unit
			else
				knockDir = Vector3.new(0, 0, 1)
			end
			local knockForce = (Balance.CREATURE_KNOCKBACK_FORCE or 12) * 1.2
			creature.rootPart.AssemblyLinearVelocity = knockDir * knockForce + Vector3.new(0, 5, 0)
		end
		
		if NetController then
			NetController.FireAllClients("Combat.Creature.Hit", {
				instanceId = targetInstanceId,
				hitPosition = { x = creaturePos.X, y = creaturePos.Y, z = creaturePos.Z },
				damage = hpDamage,
				killed = killed,
				isSkill = true,
			})
		end
	elseif displayPos and NetController then
		-- 크리처 런타임 제거됨 (사망 후) — 피격 연출만 전송 (넉백 없음)
		NetController.FireAllClients("Combat.Creature.Hit", {
			instanceId = targetInstanceId,
			hitPosition = { x = displayPos.X, y = displayPos.Y, z = displayPos.Z },
			damage = hpDamage,
			killed = false,
			isSkill = true,
		})
	end
	
	-- ★ 데미지 숫자 UI 표시 — creature 상태와 무관하게 항상 전송 (hitPosition 포함)
	if NetController then
		local hitPosData = nil
		if displayPos then
			hitPosData = { x = displayPos.X, y = displayPos.Y, z = displayPos.Z }
		end
		NetController.FireClient(player, "Combat.Hit.Result", {
			damage = hpDamage,
			torporDamage = torporDamage,
			killed = killed,
			targetId = targetInstanceId,
			isSkill = true,
			isCritical = isCritical or false,
			hitPosition = hitPosData,
		})
	end
	
	-- 킬 시 드롭 + 피냄새
	if killed and dropPos and creature then
		if DebuffService then
			DebuffService.applyDebuff(userId, "BLOOD_SMELL")
		end
		-- 드롭은 CombatService에서만 처리 (중복 방지) → 여기서는 생략
	end
	
	return killed, dropPos
end

--- 디버프 효과 적용 (둔화, 경직, 기절)
local function applySkillDebuffs(skill, targetInstanceId: string)
	if not skill or not skill.effects then return end
	
	local slowDuration = getEffectValue(skill, "SLOW_DURATION")
	local slowAmount = getEffectValue(skill, "SLOW_AMOUNT")
	local staggerDuration = getEffectValue(skill, "STAGGER_DURATION")
	local stunDuration = getEffectValue(skill, "STUN_DURATION")
	
	-- 크리처에 대한 디버프는 속도 배율로 처리
	if not CreatureService then return end
	local creature = CreatureService.getCreatureRuntime(targetInstanceId)
	if not creature or not creature.rootPart then return end
	
	if slowDuration > 0 then
		-- 둔화: 이동속도 감소 (기간 후 복구)
		if CreatureService.applySlowEffect then
			CreatureService.applySlowEffect(targetInstanceId, slowAmount > 0 and slowAmount or 0.3, slowDuration)
		end
	end
	
	if staggerDuration > 0 then
		-- 경직: 잠시 행동 불능
		if CreatureService.applyStaggerEffect then
			CreatureService.applyStaggerEffect(targetInstanceId, staggerDuration)
		end
	end
	
	if stunDuration > 0 then
		-- 기절: 행동 불능
		if CreatureService.applyStunEffect then
			CreatureService.applyStunEffect(targetInstanceId, stunDuration)
		end
	end
end

--- DOT (지속 피해) 적용
local function applyDOT(player: Player, targetInstanceId: string, baseDamage: number, dotDuration: number, tickPct: number)
	if dotDuration <= 0 or tickPct <= 0 then return end
	
	task.spawn(function()
		local elapsed = 0
		local tickInterval = 1.0 -- 1초마다 틱
		while elapsed < dotDuration do
			task.wait(tickInterval)
			elapsed = elapsed + tickInterval
			
			local creature = CreatureService and CreatureService.getCreatureRuntime(targetInstanceId)
			if not creature or not creature.rootPart then break end
			
			local dotDamage = baseDamage * tickPct
			CreatureService.processAttack(targetInstanceId, dotDamage, 0, player)
			
			-- DOT 피격 연출
			if NetController and creature.rootPart then
				local pos = creature.rootPart.Position
				NetController.FireAllClients("Combat.Creature.Hit", {
					instanceId = targetInstanceId,
					hitPosition = { x = pos.X, y = pos.Y, z = pos.Z },
					damage = dotDamage,
					killed = false,
					isDOT = true,
				})
			end
		end
	end)
end

--========================================
-- Skill Execution Logic
--========================================

--- 단일 타겟 스킬 (강타, 강사, 내려찍기)
local function executeSingleTarget(player, skill, targetId, baseDamage, itemData)
	local damageMult = getEffectValue(skill, "SKILL_DAMAGE_MULT")
	if damageMult <= 0 then damageMult = 1.0 end
	
	-- 공격력 보정
	local calculated = PlayerStatService.GetCalculatedStats(player.UserId)
	local attackMult = calculated.attackMult or 1.0
	local totalDamage = baseDamage * damageMult * attackMult
	
	-- 데미지 등락폭
	local variance = Balance.DAMAGE_VARIANCE or 0.15
	totalDamage = math.max(1, totalDamage * (1 + (math.random() * 2 - 1) * variance))
	
	-- 치명타 판정
	local critChance, critDamageMult = getCritInfo(player, itemData)
	local isCritical
	totalDamage, isCritical = rollCritical(totalDamage, critChance, critDamageMult)
	
	local isBlunt = itemData and itemData.isBlunt
	local killed = applySkillDamage(player, targetId, totalDamage, isBlunt, nil, isCritical)
	
	-- 디버프 적용
	if not killed then
		applySkillDebuffs(skill, targetId)
	end
	
	-- DOT 적용
	local dotDuration = getEffectValue(skill, "SKILL_DOT_DURATION")
	local dotTickPct = getEffectValue(skill, "SKILL_DOT_TICK_PCT")
	if dotDuration > 0 and dotTickPct > 0 and not killed then
		applyDOT(player, targetId, totalDamage, dotDuration, dotTickPct)
	end
	
	return true, { damage = totalDamage, killed = killed }
end

--- AOE 스킬 (회전 베기, 폭렬 사격)
local function executeAOE(player, skill, targetId, baseDamage, itemData)
	local damageMult = getEffectValue(skill, "SKILL_DAMAGE_MULT")
	if damageMult <= 0 then damageMult = 1.0 end
	local aoeRadius = getEffectValue(skill, "SKILL_AOE_RADIUS")
	if aoeRadius <= 0 then aoeRadius = 5 end
	
	local calculated = PlayerStatService.GetCalculatedStats(player.UserId)
	local attackMult = calculated.attackMult or 1.0
	local totalDamage = baseDamage * damageMult * attackMult
	
	local variance = Balance.DAMAGE_VARIANCE or 0.15
	totalDamage = math.max(1, totalDamage * (1 + (math.random() * 2 - 1) * variance))
	
	-- 치명타 판정 (AOE 전체에 동일 적용)
	local critChance, critDamageMult = getCritInfo(player, itemData)
	local isCritical
	totalDamage, isCritical = rollCritical(totalDamage, critChance, critDamageMult)
	
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, { errorCode = "INTERNAL_ERROR" } end
	
	local center = hrp.Position
	local isBlunt = itemData and itemData.isBlunt
	
	-- AOE 범위 내 모든 크리처에 피해
	local targets = findCreaturesInRadius(center, aoeRadius)
	local totalKills = 0
	local hitCount = 0
	
	for _, target in ipairs(targets) do
		local killed = applySkillDamage(player, target.instanceId, totalDamage, isBlunt, nil, isCritical)
		hitCount = hitCount + 1
		if killed then totalKills = totalKills + 1 end
		if not killed then
			applySkillDebuffs(skill, target.instanceId)
		end
	end
	
	-- 메인 타겟도 추가 (AOE 범위 밖일 수 있음)
	if targetId and targetId ~= "" then
		local alreadyHit = false
		for _, t in ipairs(targets) do
			if t.instanceId == targetId then alreadyHit = true break end
		end
		if not alreadyHit then
			local creature = CreatureService.getCreatureRuntime(targetId)
			if creature and creature.rootPart then
				local killed = applySkillDamage(player, targetId, totalDamage, isBlunt, nil, isCritical)
				hitCount = hitCount + 1
				if killed then totalKills = totalKills + 1 end
				if not killed then
					applySkillDebuffs(skill, targetId)
				end
			end
		end
	end
	
	-- DOT (폭렬 사격)
	local dotDuration = getEffectValue(skill, "SKILL_DOT_DURATION")
	local dotTickPct = getEffectValue(skill, "SKILL_DOT_TICK_PCT")
	if dotDuration > 0 and dotTickPct > 0 then
		for _, target in ipairs(targets) do
			applyDOT(player, target.instanceId, totalDamage, dotDuration, dotTickPct)
		end
	end
	
	return true, { damage = totalDamage, hitCount = hitCount, kills = totalKills }
end

--- 멀티히트 스킬 (난무, 속사, 도끼 폭풍)
local function executeMultiHit(player, skill, targetId, baseDamage, itemData)
	local multiHit = getEffectValue(skill, "SKILL_MULTI_HIT")
	if multiHit <= 0 then multiHit = 1 end
	local damageMult = getEffectValue(skill, "SKILL_DAMAGE_MULT")
	if damageMult <= 0 then damageMult = 1.0 end
	local finalHitMult = getEffectValue(skill, "SKILL_FINAL_HIT_MULT")
	local aoeRadius = getEffectValue(skill, "SKILL_AOE_RADIUS")
	
	local calculated = PlayerStatService.GetCalculatedStats(player.UserId)
	local attackMult = calculated.attackMult or 1.0
	local isBlunt = itemData and itemData.isBlunt
	local critChance, critDamageMult = getCritInfo(player, itemData)
	
	-- 첫 타 즉시, 나머지 딜레이 (크리처 사망 후에도 남은 타수 데미지 전부 표시)
	task.spawn(function()
		local lastKnownPos = nil
		
		-- 시작 전 타겟 위치 저장
		local initCreature = CreatureService and CreatureService.getCreatureRuntime(targetId)
		if initCreature and initCreature.rootPart then
			lastKnownPos = initCreature.rootPart.Position
		end
		
		for i = 1, multiHit do
			if i > 1 then
				task.wait(MULTI_HIT_INTERVAL)
			end
			
			-- 타겟 위치 갱신 (생존 시)
			local creature = CreatureService and CreatureService.getCreatureRuntime(targetId)
			if creature and creature.rootPart then
				lastKnownPos = creature.rootPart.Position
			end
			
			local hitMult = damageMult
			if i == multiHit and finalHitMult > 0 then
				hitMult = finalHitMult
			end
			
			local variance = Balance.DAMAGE_VARIANCE or 0.15
			local hitDamage = math.max(1, baseDamage * hitMult * attackMult * (1 + (math.random() * 2 - 1) * variance))
			
			-- 히트별 치명타 판정
			local isCritical
			hitDamage, isCritical = rollCritical(hitDamage, critChance, critDamageMult)
			
			-- AOE가 있으면 범위 공격 (도끼 폭풍)
			if aoeRadius > 0 then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local targets = findCreaturesInRadius(hrp.Position, aoeRadius)
					for _, t in ipairs(targets) do
						applySkillDamage(player, t.instanceId, hitDamage, isBlunt, lastKnownPos, isCritical)
					end
					-- 메인 타겟
					local alreadyHit = false
					for _, t in ipairs(targets) do
						if t.instanceId == targetId then alreadyHit = true break end
					end
					if not alreadyHit then
						applySkillDamage(player, targetId, hitDamage, isBlunt, lastKnownPos, isCritical)
					end
				end
			else
				applySkillDamage(player, targetId, hitDamage, isBlunt, lastKnownPos, isCritical)
			end
			
			-- 마지막 히트에 디버프 적용
			if i == multiHit then
				local stillAlive = CreatureService.getCreatureRuntime(targetId)
				if stillAlive and stillAlive.rootPart then
					applySkillDebuffs(skill, targetId)
				end
			end
		end
	end)
	
	return true, { multiHit = multiHit, damageMult = damageMult }
end

--========================================
-- Main Handler
--========================================

local function handleUseSkill(player: Player, payload: any)
	local userId = player.UserId
	local now = tick()
	
	-- 1. payload 검증
	local skillId = payload and payload.skillId
	local targetId = payload and payload.targetId
	if type(skillId) ~= "string" or skillId == "" then
		return { success = false, errorCode = "BAD_REQUEST" }
	end
	
	-- 2. GCD 체크
	if playerGCD[userId] and now < playerGCD[userId] then
		return { success = false, errorCode = "COOLDOWN" }
	end
	
	-- 3. 스킬 데이터 검증
	local skill = SkillTreeData.GetSkill(skillId)
	if not skill or skill.type ~= "ACTIVE" then
		return { success = false, errorCode = "SKILL_NOT_FOUND" }
	end
	
	-- 4. 스킬 해금 여부
	if not SkillService.isSkillUnlocked(userId, skillId) then
		return { success = false, errorCode = "SKILL_NOT_UNLOCKED" }
	end
	
	-- 5. 액티브 슬롯에 장착되어 있는지 확인
	local slots = SkillService.getActiveSkillSlots(userId)
	local isInSlot = false
	for i = 1, 3 do
		if slots[i] == skillId then
			isInSlot = true
			break
		end
	end
	if not isInSlot then
		return { success = false, errorCode = "SKILL_NOT_IN_SLOT" }
	end
	
	-- 6. 무기 매칭 검증 (검 스킬 → 검 장비 필요)
	local _, itemData, _ = getWeaponBaseDamage(player)
	local weaponTreeId = getWeaponTreeId(itemData)
	local skillTreeId = SkillTreeData.GetTreeIdForSkill(skillId)
	
	if not weaponTreeId or weaponTreeId ~= skillTreeId then
		return { success = false, errorCode = "WEAPON_MISMATCH" }
	end
	
	-- 7. 개별 스킬 쿨다운 체크
	if not playerSkillCooldowns[userId] then
		playerSkillCooldowns[userId] = {}
	end
	local cd = playerSkillCooldowns[userId][skillId]
	if not DEV_NO_COOLDOWN and cd and now < cd then
		local remaining = math.ceil(cd - now)
		return { success = false, errorCode = "COOLDOWN", remaining = remaining }
	end
	
	-- 8. 스태미나 체크
	if StaminaService then
		if not StaminaService.hasEnoughStamina(userId, SKILL_STAMINA_COST) then
			return { success = false, errorCode = "NOT_ENOUGH_STAMINA" }
		end
	end
	
	-- 9. 캐릭터 생존 확인
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not humanoid or humanoid.Health <= 0 then
		return { success = false, errorCode = "PLAYER_DEAD" }
	end
	
	-- 10. 타겟 검증 — 타겟이 있을 때만 검증 (허공 스킬 허용, 좌클릭과 동일)
	local aoeRadius = getEffectValue(skill, "SKILL_AOE_RADIUS")
	if targetId and targetId ~= "" then
		local creature = CreatureService.getCreatureRuntime(targetId)
		if not creature or not creature.rootPart then
			targetId = nil -- 유효하지 않은 타겟 → 허공으로 처리
		else
			-- 사거리 체크 (무기 사거리 + 여유)
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = (creature.rootPart.Position - hrp.Position).Magnitude
				local maxRange = (itemData and itemData.range or 14) + 8
				if dist > maxRange then
					targetId = nil -- 사거리 밖 → 허공으로 처리
				end
			end
		end
	end
	
	-- ★ 모든 검증 통과 — 스킬 발동
	
	-- 스태미나 소모
	if StaminaService then
		StaminaService.consumeStamina(userId, SKILL_STAMINA_COST)
	end
	
	-- 배고픔 소모
	if HungerService then
		HungerService.consumeHunger(userId, Balance.HUNGER_COMBAT_COST or 1)
	end
	
	-- 쿨다운 등록
	local cdTime = DEV_NO_COOLDOWN and 0 or skill.cooldown
	playerSkillCooldowns[userId][skillId] = now + cdTime
	playerGCD[userId] = now + (DEV_NO_COOLDOWN and 0 or SKILL_GCD)
	
	-- 무기 기본 데미지
	local baseDamage = getWeaponBaseDamage(player)
	
	-- ★ 클라이언트에 이펙트 브로드캐스트 먼저 전송 (애니메이션/VFX/사운드 재생)
	if NetController then
		NetController.FireAllClients("ActiveSkill.Used", {
			userId = userId,
			skillId = skillId,
			targetId = targetId,
		})
	end
	
	-- ★ 데미지는 애니메이션 진행 후 적용 (딜레이)
	local multiHit = getEffectValue(skill, "SKILL_MULTI_HIT")
	local hasAOE = aoeRadius > 0
	local SKILL_HIT_DELAY = 0.6  -- 애니메이션 '타격점' 도달 시간 (초)
	
	task.spawn(function()
		task.wait(SKILL_HIT_DELAY)
		
		-- 딜레이 후 캐릭터 생존 재확인
		local charCheck = player.Character
		local humCheck = charCheck and charCheck:FindFirstChildOfClass("Humanoid")
		if not charCheck or not humCheck or humCheck.Health <= 0 then return end
		
		local execResult
		if hasAOE then
			-- AOE (회전 베기, 폭렬 사격) — 타겟 없어도 주변 적에게 피해
			_, execResult = executeAOE(player, skill, targetId, baseDamage, itemData)
		elseif targetId and targetId ~= "" then
			-- 단일/멀티히트 — 유효한 타겟이 있을 때만 데미지
			if multiHit > 0 then
				_, execResult = executeMultiHit(player, skill, targetId, baseDamage, itemData)
			else
				_, execResult = executeSingleTarget(player, skill, targetId, baseDamage, itemData)
			end
		end
		-- 타겟 없으면 데미지 스킵 (허공 사용 — 애니메이션/VFX만 재생됨)
	end)
	
	print(string.format("[ActiveSkillService] %s used %s (cd:%.0fs)", player.Name, skillId, skill.cooldown))
	
	return {
		success = true,
		data = {
			skillId = skillId,
			cooldown = skill.cooldown,
			cooldowns = ActiveSkillService.getPlayerCooldowns(userId),
		},
	}
end

--========================================
-- Public API
--========================================

--- 플레이어의 모든 스킬 쿨다운 조회
function ActiveSkillService.getPlayerCooldowns(userId: number): { [string]: number }
	local result = {}
	local now = tick()
	local cds = playerSkillCooldowns[userId]
	if not cds then return result end
	for skillId, endTime in pairs(cds) do
		if endTime > now then
			result[skillId] = endTime - now
		end
	end
	return result
end

--========================================
-- Init / GetHandlers
--========================================

function ActiveSkillService.GetHandlers()
	return {
		["Skill.Use.Request"] = handleUseSkill,
	}
end

function ActiveSkillService.Init(_NetController, _SkillService, _CombatService, _CreatureService, _InventoryService, _DataService, _PlayerStatService, _DebuffService, _StaminaService, _HungerService)
	NetController = _NetController
	SkillService = _SkillService
	CombatService = _CombatService
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	DataService = _DataService
	PlayerStatService = _PlayerStatService
	DebuffService = _DebuffService
	StaminaService = _StaminaService
	HungerService = _HungerService
	
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		playerSkillCooldowns[uid] = nil
		playerGCD[uid] = nil
	end)
	
	print("[ActiveSkillService] Initialized")
end

return ActiveSkillService
