-- DebuffService.lua
-- Phase 4-4 & 4-5: 상태이상(디버프) 및 환경 효과 관리
-- BloodSmell(피냄새), Freezing(추위), Poison(독) 등

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local DebuffService = {}

-- Dependencies
local NetController
local TimeService

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
		duration = 120, -- 2분
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

function DebuffService.Init(_NetController, _TimeService)
	NetController = _NetController
	TimeService = _TimeService
	
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
			task.wait(10) -- 10초마다 환경 체크
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
					
					-- 플레이어 Humanoid에 데미지
					local char = player.Character
					if char then
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
		
		if isNight then
			-- 불(Campfire) 근처인지 체크
			local nearFire = false
			
			-- Workspace에서 Campfire 파트 검색 (간단한 거리 체크)
			-- BuildService가 "Facilities" 폴더를 생성함
			local campfires = workspace:FindFirstChild("Facilities")
			if campfires then
				for _, obj in ipairs(campfires:GetChildren()) do
					if obj:GetAttribute("FacilityType") == "COOKING" then
						-- Part일 수도 있고 Model일 수도 있으므로 안전하게 위치 가져오기
						local objPos
						if obj:IsA("BasePart") then
							objPos = obj.Position
						elseif obj:IsA("Model") and obj.PrimaryPart then
							objPos = obj.PrimaryPart.Position
						end
						
						if objPos then
							local dist = (hrp.Position - objPos).Magnitude
							if dist <= 15 then -- 15 스터드 이내
								nearFire = true
								break
							end
						end
					end
				end
			end
			
			if nearFire then
				-- 불 근처면 추위 해제
				DebuffService.removeDebuff(userId, "FREEZING")
			else
				-- 추위 적용
				if not DebuffService.hasDebuff(userId, "FREEZING") then
					DebuffService.applyDebuff(userId, "FREEZING")
				end
			end
		else
			-- 낮이면 추위 해제
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
