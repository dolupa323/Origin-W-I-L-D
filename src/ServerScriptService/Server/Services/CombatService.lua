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

function CombatService.Init(_NetController, _DataService, _CreatureService, _InventoryService, _DurabilityService, _DebuffService)
	NetController = _NetController
	DataService = _DataService
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	DurabilityService = _DurabilityService
	DebuffService = _DebuffService
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
	local damage = 5 -- 맨손 데미지
	local range = DEFAULT_ATTACK_RANGE
	local toolItem = nil
	
	if toolSlot then
		local slotData = InventoryService.getSlot(player.UserId, toolSlot)
		if slotData then
			local itemData = DataService.getItem(slotData.itemId)
			if itemData and (itemData.type == "TOOL" or itemData.type == "WEAPON") then
				damage = itemData.damage or 5
				range = itemData.range or DEFAULT_ATTACK_RANGE
				toolItem = slotData
			end
		end
	end
	
	-- 2. 대상(크리처) 확인 및 거리 검증
	local creature = CreatureService.getCreatureRuntime(targetId)
	if not creature or not creature.rootPart then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	local dist = (hrp.Position - creature.rootPart.Position).Magnitude
	if dist > range + 2 then -- 약간의 오차 허용
		warn(string.format("[CombatService] Out of range: %.1f > %.1f", dist, range))
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	-- 3. 데미지 적용 (CreatureService 위임)
	local killed, dropPos = CreatureService.applyDamage(targetId, damage, player)
	
	-- 4. 도구 내구도 감소
	if toolItem and toolSlot then
		DurabilityService.reduceDurability(player, toolSlot, 1)
	end
	
	-- 5. 피냄새 디버프 적용 (크리처를 킬했을 때)
	if killed and DebuffService then
		DebuffService.applyDebuff(player.UserId, "BLOOD_SMELL")
	end
	
	-- 5.5 퀘스트 콜백 (Phase 8)
	if killed and questCallback and creature.data then
		questCallback(player.UserId, creature.data.id or creature.data.creatureId)
	end
	
	-- 6. 타격 피드백 (Client Event)
	if NetController then
		NetController.FireClient(player, "Combat.Hit.Result", {
			damage = damage,
			killed = killed,
			targetId = targetId,
		})
	end
	
	print(string.format("[CombatService] %s hit %s for %d dmg%s", 
		player.Name, creature.data and creature.data.name or "?", damage, killed and " (KILLED)" or ""))
	
	return true, nil, { damage = damage, killed = killed }
end

--========================================
-- Network Handlers
--========================================

local function handleHitRequest(player, payload)
	local targetId = payload.targetInstanceId -- InstanceId (GUID)
	local toolSlot = payload.toolSlot -- 인벤토리 슬롯 번호
	
	local success, errorCode, result = CombatService.processPlayerAttack(player, targetId, toolSlot)
	
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
