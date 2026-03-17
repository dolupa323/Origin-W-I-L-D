-- DebuffService.lua
-- Phase 4-4 & 4-5: 상태이상(디버프) 및 환경 효과 관리
-- BloodSmell(피냄새), Freezing(추위), Poison(독) 등

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

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
		description = "밤이 되어 기온이 떨어졌습니다. 모닥불 근처로 가세요.",
		duration = -1, -- 밤 동안 지속
		tickInterval = 8,
		tickDamage = 1, -- 매우 미미한 데미지 (학습용)
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
	
	local isNight = TimeService.getPhase and TimeService.getPhase() == "NIGHT"
	
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		local char = player.Character
		if not char then continue end
		
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		
		-- 1. 물(Water) 체크
		local isSwimming = false
		local hum = char:FindFirstChild("Humanoid")
		if hum then
			-- 수영 판정은 상태/바닥재질 모두 허용해 누락을 방지한다.
			local state = hum:GetState()
			if state == Enum.HumanoidStateType.Swimming or hum.FloorMaterial == Enum.Material.Water then
				isSwimming = true
			end
		end

		-- 2. 불(Campfire) 근처인지 체크
		local nearFire = false
		local overlapParams = OverlapParams.new()
		local facilitiesFolder = workspace:FindFirstChild("Facilities")
		if facilitiesFolder then
			overlapParams.FilterDescendantsInstances = { facilitiesFolder }
			overlapParams.FilterType = Enum.RaycastFilterType.Include
			local nearbyParts = workspace:GetPartBoundsInRadius(hrp.Position, 18, overlapParams)
			for _, part in ipairs(nearbyParts) do
				local facilityId = part:GetAttribute("FacilityId") or (part:FindFirstAncestorOfClass("Model") and part:FindFirstAncestorOfClass("Model"):GetAttribute("FacilityId"))
				if facilityId and DataService then
					local facilityData = DataService.getFacility(facilityId)
					if facilityData and facilityData.functionType == "COOKING" then
						local facilityModel = part:FindFirstAncestorOfClass("Model")
						local structureId = facilityModel and facilityModel:GetAttribute("StructureId")
						local runtime = structureId and FacilityService and FacilityService.getRuntime(structureId)
						if runtime and runtime.state == Enums.FacilityState.ACTIVE then
							nearFire = true
							break
						end
					end
				end
			end
		end

		-- 2.5 손에 든 횃불 체크 (밤 추위 완화)
		local holdingTorch = false
		if InventoryService and InventoryService.getActiveSlot and InventoryService.getSlot then
			local activeSlot = InventoryService.getActiveSlot(userId)
			if activeSlot then
				local activeItem = InventoryService.getSlot(userId, activeSlot)
				local activeItemId = activeItem and string.upper(tostring(activeItem.itemId or "")) or ""
				holdingTorch = (activeItemId == "TORCH")
			end
		end

		-- 3. 최종 상태 결정
		local shouldBeChilly = isSwimming or (isNight and not nearFire and not holdingTorch)
		local shouldBeWarm = (nearFire or holdingTorch) and not isSwimming -- 물속에선 따뜻함 유지 불가

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
			-- 낮이고, 물 밖이며, 불 근처도 아님
			DebuffService.removeDebuff(userId, "CHILLY")
			DebuffService.removeDebuff(userId, "WARMTH")
		end
		
		-- 극한 추위(FREEZING)는 일단 밤+불없음 일 때만 (Phase 확장 대비)
		if not isNight or nearFire or holdingTorch then
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
