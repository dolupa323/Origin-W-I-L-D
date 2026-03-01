-- CombatService.lua
-- 전투 시스템 (Phase 3-3)
-- 플레이어와 크리처 간의 데미지 처리 및 사망 로직, 드롭 아이템 생성

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

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

-- Constants
local DEFAULT_ATTACK_RANGE = 5 -- 맨손 사거리
local PVP_ENABLED = false       -- PvP 비활성화

-- Quest callback (Phase 8)
local questCallback = nil

--========================================
-- StaminaService Integration (Phase 10)
--========================================

function CombatService.SetStaminaService(_StaminaService)
	StaminaService = _StaminaService
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

function CombatService.Init(_NetController, _DataService, _CreatureService, _InventoryService, _DurabilityService, _DebuffService, _WorldDropService, _PlayerStatService)
	NetController = _NetController
	DataService = _DataService
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	DurabilityService = _DurabilityService
	DebuffService = _DebuffService
	WorldDropService = _WorldDropService
	PlayerStatService = _PlayerStatService
	
	-- HungerService 로드 및 캐싱 (성능 최적화)
	local HSuccess, HService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
	if HSuccess then HungerService = HService end
	
	print("[CombatService] Initialized")
end

--- 플레이어가 대상을 공격 (Client Request)
function CombatService.processPlayerAttack(player: Player, targetId: string, toolSlot: number?)
	if not player or not targetId then 
		return false, Enums.ErrorCode.BAD_REQUEST 
	end

	local char = player.Character
	if not char then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, Enums.ErrorCode.INTERNAL_ERROR end

	-- 1. 무기(도구) 검증
	local baseDamage = 5 -- 맨손 기본 데미지
	local range = DEFAULT_ATTACK_RANGE
	local toolItem = nil
	local isBlunt = false
	
	if toolSlot then
		local slotData = InventoryService.getSlot(player.UserId, toolSlot)
		if slotData then
			local itemData = DataService.getItem(slotData.itemId)
			if itemData then
				baseDamage = itemData.damage or 5
				range = itemData.range or DEFAULT_ATTACK_RANGE
				isBlunt = itemData.isBlunt == true
				toolItem = slotData
			end
		end
	end
	
	-- 2. 플레이어 공격력 스탯 보너스 적용
	local calculated = PlayerStatService.GetCalculatedStats(player.UserId)
	local attackMult = calculated.attackMult or 1.0
	local totalDamage = baseDamage * attackMult
	
	-- 3. 대상(크리처) 확인 및 거리 검증
	local creature = CreatureService.getCreatureRuntime(targetId)
	if not creature or not creature.rootPart then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	local dist = (hrp.Position - creature.rootPart.Position).Magnitude
	if dist > range + 2 then -- 약간의 오차 허용
		warn(string.format("[CombatService] Out of range: %.1f > %.1f", dist, range))
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	-- 4. 데미지 및 기절 수치 적용
	local hpDamage = totalDamage
	local torporDamage = 0
	
	if isBlunt then
		hpDamage = totalDamage * 0.5  -- 둔기는 체력 데미지 50%
		torporDamage = totalDamage * 0.5 -- 기절 데미지 50% (합계 100%)
	end
	
	-- CreatureService.applyDamage를 확장하거나 새 함수 사용
	-- 여기서는 기존 applyDamage를 유지하되 내부에서 Torpor 처리하거나, 
	-- CombatService에서 직접 Torpor를 다룰 수 있지만 아키텍처상 CreatureService가 엔티티 상태 관리
	local killed, dropPos = CreatureService.processAttack(targetId, hpDamage, torporDamage, player)
	
	-- 4. 도구 내구도 감소
	if toolItem and toolSlot and toolItem.durability then
		DurabilityService.reduceDurability(player, toolSlot, 1)
	end
	
	-- 4.5 전투 시 배고픔 소모 연동 (Phase 11)
	if HungerService then
		HungerService.consumeHunger(player.UserId, Balance.HUNGER_COMBAT_COST)
	end
	
	-- 5. 피냄새 디버프 및 드롭 생성 (크리처를 킬했을 때)
	if killed and dropPos then
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
						local spawnPos = dropPos + Vector3.new(math.cos(angle) * radius, 1, math.sin(angle) * radius)
						
						WorldDropService.spawnDrop(spawnPos, entry.itemId, count)
					end
				end
			end
		end
	end
	
	-- 5.5 퀘스트 콜백 (Phase 8)
	if killed and questCallback and creature.data then
		questCallback(player.UserId, creature.data.id or creature.data.creatureId)
	end
	
	-- 6. 타격 피드백 (Client Event)
	if NetController then
		NetController.FireClient(player, "Combat.Hit.Result", {
			damage = hpDamage,
			torporDamage = torporDamage,
			killed = killed,
			targetId = targetId,
		})
	end
	
	print(string.format("[CombatService] %s hit %s for %.1f (Torpor: %.1f) dmg%s", 
		player.Name, creature.data and creature.data.name or "?", hpDamage, torporDamage, killed and " (KILLED)" or ""))
	
	return true, nil, { damage = hpDamage, torporDamage = torporDamage, killed = killed }
end

--========================================
-- Network Handlers
--========================================

local function handleHitRequest(player, payload)
	local targetId = payload.targetInstanceId -- InstanceId (GUID)
	
	-- 보안/기획: 클라이언트가 보낸 toolSlot 대신, 서버의 현재 활성 슬롯(Active Slot)을 사용
	local activeSlot = 1
	if InventoryService then
		activeSlot = InventoryService.getActiveSlot(player.UserId)
	end
	
	local success, errorCode, result = CombatService.processPlayerAttack(player, targetId, activeSlot)
	
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

return CombatService
