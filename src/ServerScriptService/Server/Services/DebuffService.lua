-- DebuffService.lua
-- Phase 4-4 & 4-5: 상태이상(디버프) 및 환경 효과 관리
-- BloodSmell(피냄새), Freezing(추위), Poison(독) 등

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local SEA_LEVEL = Balance.SEA_LEVEL or 2

local DebuffService = {}

-- Dependencies
local NetController
local TimeService
local DataService
local StaminaService
local FacilityService
local InventoryService

-- [userId] = { [debuffId] = { startTime, duration, tickDamage, ... } }
local activeDebuffs = {}

--========================================
-- Debuff Definitions
--========================================
local DEBUFF_DEFS = {
	BLOOD_SMELL = {
		id = "BLOOD_SMELL",
		name = "피냄새",
		description = "사냥 후 피냄새가 나서 포식자가 유인됩니다",
		duration = 35, -- 짧은 유지시간으로 조정
		tickInterval = 0, -- 틱 데미지 없음
		tickDamage = 0,
		-- 특수 효과: CreatureService AI에서 감지 범위 증가
		aggroMultiplier = 2.0, -- 감지 범위 2배
	},
	FREEZING = {
		id = "FREEZING",
		name = "추위",
		description = "밤이 되면 체온이 떨어집니다. 불 근처에서 해소됩니다.",
		duration = -1, -- 지속 (조건 해제)
		tickInterval = 5, -- 5초마다
		tickDamage = 3, -- 3 데미지
	},
	BURNING = {
		id = "BURNING",
		name = "화상",
		description = "불에 데었습니다",
		duration = 10,
		tickInterval = 2,
		tickDamage = 5,
	},
	CHILLY = {
		id = "CHILLY",
		name = "쌀쌀함",
		description = "밤에 온기 수단이 없어 체온이 낮아집니다. 모닥불 근처로 이동하거나 횃불을 사용하세요.",
		duration = -1, -- 밤 동안 지속
		tickInterval = 2,
		tickDamage = 4, -- 기본 체력 재생을 상회하도록 상향
	},
	WARMTH = {
		id = "WARMTH",
		name = "따뜻함",
		description = "모닥불 근처에서 온기를 느끼고 있습니다.",
		duration = -1, -- 근처에 있는 동안만
		tickInterval = 0,
		tickDamage = 0,
		isBuff = true,
	},
}

--========================================
-- Internal Helpers
--========================================

local function getPlayerDebuffs(userId: number)
	if not activeDebuffs[userId] then
		activeDebuffs[userId] = {}
	end
	return activeDebuffs[userId]
end

local function isPlayerNearCampfire(hrp: BasePart): boolean
	local overlapParams = OverlapParams.new()
	local facilitiesFolder = workspace:FindFirstChild("Facilities")
	if not facilitiesFolder then
		return false
	end

	overlapParams.FilterDescendantsInstances = { facilitiesFolder }
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	local nearbyParts = workspace:GetPartBoundsInRadius(hrp.Position, 18, overlapParams)
	for _, part in ipairs(nearbyParts) do
		local model = part:FindFirstAncestorOfClass("Model")
		local facilityId = string.upper(tostring(part:GetAttribute("FacilityId") or (model and model:GetAttribute("FacilityId")) or ""))
		if facilityId == "CAMPFIRE" then
			return true
		end
	end

	return false
end

local function isPlayerHoldingTorch(userId: number): boolean
	if not (InventoryService and InventoryService.getActiveSlot and InventoryService.getSlot) then
		return false
	end

	local activeSlot = InventoryService.getActiveSlot(userId)
	if not activeSlot then
		return false
	end

	local activeItem = InventoryService.getSlot(userId, activeSlot)
	local activeItemId = activeItem and string.upper(tostring(activeItem.itemId or "")) or ""
	return activeItemId == "TORCH"
end

--- 플레이어가 물/바다에 있는지 체크
local function isPlayerInWater(hrp: BasePart): boolean
	-- Raycast로 물 Material 체크
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.FilterType = Enum.RaycastFilterType.Include

	local result = workspace:Raycast(hrp.Position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), params)
	if result and result.Material == Enum.Material.Water then
		return true
	end

	-- 해수면 아래이면 물로 판정
	if hrp.Position.Y < SEA_LEVEL then
		return true
	end

	return false
end

local function getChillyEnvironmentState(player: Player)
	if not player then
		return nil
	end
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local isNight = TimeService and TimeService.getPhase and TimeService.getPhase() == "NIGHT"
	local nearFire = isPlayerNearCampfire(hrp)
	local holdingTorch = isPlayerHoldingTorch(player.UserId)
	local inWater = isPlayerInWater(hrp)

	-- 물에 있으면 불/횃불 관계없이 무조건 쌀쌀함
	local shouldBeChilly = inWater or (isNight and (not nearFire) and (not holdingTorch))
	local shouldBeWarm = (not shouldBeChilly) and (nearFire or holdingTorch)

	return {
		isNight = isNight,
		nearFire = nearFire,
		holdingTorch = holdingTorch,
		inWater = inWater,
		shouldBeChilly = shouldBeChilly,
		shouldBeWarm = shouldBeWarm,
	}
end

local function hasPortalSafeWindow(player: Player): boolean
	if not player then
		return false
	end

	local safeUntil = tonumber(player:GetAttribute("PortalSafeUntil"))
	return safeUntil ~= nil and safeUntil > os.clock()
end

--========================================
-- Public API
--========================================

function DebuffService.Init(_NetController, _TimeService, _DataService, _StaminaService, _FacilityService, _InventoryService)
	NetController = _NetController
	TimeService = _TimeService
	DataService = _DataService
	StaminaService = _StaminaService
	FacilityService = _FacilityService
	InventoryService = _InventoryService
	
	-- 디버프 틱 루프 (2초마다)
	task.spawn(function()
		while true do
			task.wait(2)
			DebuffService._tickLoop()
		end
	end)
	
	-- 밤/낮 전환 시 추위 디버프 (Phase 4-5)
	task.spawn(function()
		while true do
			task.wait(2) -- 2초마다 환경 체크 (물/밤 상태를 빠르게 반영)
			DebuffService._environmentCheck()
		end
	end)
	
	-- 로그아웃 시 정리
	Players.PlayerRemoving:Connect(function(player)
		activeDebuffs[player.UserId] = nil
	end)
	
	print("[DebuffService] Initialized")
end

--- 디버프 적용
function DebuffService.applyDebuff(userId: number, debuffId: string, customDuration: number?)
	local def = DEBUFF_DEFS[debuffId]
	if not def then
		warn("[DebuffService] Unknown debuff:", debuffId)
		return false
	end
	
	local debuffs = getPlayerDebuffs(userId)
	
	-- 이미 같은 디버프가 있으면 갱신 (duration 리셋)
	debuffs[debuffId] = {
		defId = debuffId,
		startTime = os.time(),
		duration = customDuration or def.duration,
		lastTick = os.time(),
	}
	
	-- 클라이언트 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Debuff.Applied", {
			debuffId = debuffId,
			name = def.name,
			description = def.description,
			duration = customDuration or def.duration,
		})
	end
	
	print(string.format("[DebuffService] Applied %s to player %d", debuffId, userId))
	return true
end

--- 디버프 해제
function DebuffService.removeDebuff(userId: number, debuffId: string)
	local debuffs = getPlayerDebuffs(userId)
	if debuffs[debuffId] then
		debuffs[debuffId] = nil
		
		local player = Players:GetPlayerByUserId(userId)
		if player and NetController then
			NetController.FireClient(player, "Debuff.Removed", {
				debuffId = debuffId,
			})
		end
		
		print(string.format("[DebuffService] Removed %s from player %d", debuffId, userId))
	end
end

--- 특정 디버프 활성 여부
function DebuffService.hasDebuff(userId: number, debuffId: string): boolean
	local debuffs = getPlayerDebuffs(userId)
	return debuffs[debuffId] ~= nil
end

--- BloodSmell에 의한 어그로 배율
function DebuffService.getAggroMultiplier(userId: number): number
	if DebuffService.hasDebuff(userId, "BLOOD_SMELL") then
		return DEBUFF_DEFS.BLOOD_SMELL.aggroMultiplier
	end
	return 1.0
end

--========================================
-- Internal Loops
--========================================

--- 디버프 틱 처리 (데미지, 만료)
function DebuffService._tickLoop()
	local now = os.time()
	
	for userId, debuffs in pairs(activeDebuffs) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			activeDebuffs[userId] = nil
			continue
		end

		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if hum and hum.Health <= 0 then
			-- 사망 상태에서는 디버프를 모두 정리해 UI 잔상(아이콘 고착)을 방지한다.
			for debuffId in pairs(debuffs) do
				DebuffService.removeDebuff(userId, debuffId)
			end
			activeDebuffs[userId] = nil
			continue
		end
		
		-- 만료된 디버프를 수집 (pairs 순회 중 직접 삭제하면 정의되지 않은 동작)
		local toRemove = {}
		
		for debuffId, state in pairs(debuffs) do
			local def = DEBUFF_DEFS[debuffId]
			if not def then
				table.insert(toRemove, debuffId)
				continue
			end

			if debuffId == "CHILLY" then
				if hasPortalSafeWindow(player) then
					table.insert(toRemove, debuffId)
					continue
				end
				local env = getChillyEnvironmentState(player)
				if env and not env.shouldBeChilly then
					table.insert(toRemove, debuffId)
					continue
				end
			end

			if debuffId == "FREEZING" and hasPortalSafeWindow(player) then
				table.insert(toRemove, debuffId)
				continue
			end
			
			-- 만료 체크 (duration == -1 이면 영구)
			if state.duration > 0 then
				local elapsed = now - state.startTime
				if elapsed >= state.duration then
					table.insert(toRemove, debuffId)
					continue
				end
			end
			
			-- 틱 데미지
			if def.tickDamage > 0 and def.tickInterval > 0 then
				if now - state.lastTick >= def.tickInterval then
					state.lastTick = now
					
					-- [UX 개선] 무적 프레임(I-Frame) 체크 연동
					local isInvulnerable = StaminaService and StaminaService.isInvulnerable(userId)
					
					-- 플레이어 Humanoid에 데미지 (무적이 아닐 때만)
					local char = player.Character
					if char and not isInvulnerable then
						local hum = char:FindFirstChild("Humanoid")
						if hum and hum.Health > 0 then
							hum:TakeDamage(def.tickDamage)
						end
					end
				end
			end
		end
		
		-- 수집된 디버프 일괄 삭제
		for _, debuffId in ipairs(toRemove) do
			DebuffService.removeDebuff(userId, debuffId)
		end
	end
end

--- 환경 체크 (밤 추위, 불 근처 해제) - Phase 4-5
function DebuffService._environmentCheck()
	if not TimeService then return end
	
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId

		-- ★ ForceField(포탈 무적) 중에는 환경 디버프 스킵
		local char = player.Character
		if hasPortalSafeWindow(player) or (char and char:FindFirstChildOfClass("ForceField")) then
			DebuffService.removeDebuff(userId, "CHILLY")
			DebuffService.removeDebuff(userId, "WARMTH")
			DebuffService.removeDebuff(userId, "FREEZING")
			continue
		end

		local env = getChillyEnvironmentState(player)
		if not env then
			DebuffService.removeDebuff(userId, "CHILLY")
			DebuffService.removeDebuff(userId, "WARMTH")
			DebuffService.removeDebuff(userId, "FREEZING")
			continue
		end

		local shouldBeChilly = env.shouldBeChilly
		local shouldBeWarm = env.shouldBeWarm

		-- 적용/해제 처리
		if shouldBeChilly then
			if not DebuffService.hasDebuff(userId, "CHILLY") then
				DebuffService.applyDebuff(userId, "CHILLY")
			end
			DebuffService.removeDebuff(userId, "WARMTH")
		elseif shouldBeWarm then
			if not DebuffService.hasDebuff(userId, "WARMTH") then
				DebuffService.applyDebuff(userId, "WARMTH")
			end
			DebuffService.removeDebuff(userId, "CHILLY")
		else
			-- 낮이거나 온기 수단이 있을 때 쌀쌀함/따뜻함 동시 정리
			DebuffService.removeDebuff(userId, "CHILLY")
			DebuffService.removeDebuff(userId, "WARMTH")
		end
		
		-- 극한 추위(FREEZING)는 온기 수단이 있거나 낮이면 해제
		if (not env.isNight) or env.nearFire or env.holdingTorch then
			DebuffService.removeDebuff(userId, "FREEZING")
		end
	end
end

--========================================
-- Network Handlers
--========================================

function DebuffService.GetHandlers()
	return {}
end

return DebuffService
