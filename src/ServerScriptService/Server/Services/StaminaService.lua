-- StaminaService.lua
-- Phase 10: 스태미나 관리 서비스
-- 스프린트, 구르기 등 스태미나 소모 액션 처리

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local StaminaService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController

--========================================
-- Internal State
--========================================
-- [userId] = { current, max, lastUseTime, isSprinting, isDodging, isInvulnerable }
local playerStamina = {}

-- [FIX #7] 동시성 보호: 스태미나 업데이트 중 플래그
-- [userId] = true (업데이트 중) 또는 nil (대기 중)
local staminaUpdateLocks = {}

-- Stagger (경직) 상태: [userId] = { mult = 0.15, expireTime = tick()+0.3 }
local playerStagger = {}

--========================================
-- Internal Helpers
--========================================

local function getStaminaData(userId: number)
	if not playerStamina[userId] then
		playerStamina[userId] = {
			current = Balance.STAMINA_MAX,
			max = Balance.STAMINA_MAX,
			lastUseTime = 0,
			isSprinting = false,
			isDodging = false,
			isInvulnerable = false,
		}
	end
	return playerStamina[userId]
end

local function syncStaminaToClient(player: Player)
	if not NetController then return end
	
	local data = getStaminaData(player.UserId)
	NetController.FireClient(player, "Stamina.Update", {
		current = data.current,
		max = data.max,
		isSprinting = data.isSprinting,
	})
end

-- 플레이어의 버프/스탯 반영된 기본 이동 속도 산출
local function _getBaseSpeed(userId: number): number
	local base = Balance.BASE_WALK_SPEED
	local ok, PlayerStatService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.PlayerStatService)
	end)
	if ok and PlayerStatService and PlayerStatService.GetCalculatedStats then
		local calc = PlayerStatService.GetCalculatedStats(userId)
		if calc and calc.speedMult then
			base = base * (1 + calc.speedMult)
		end
	end
	return base
end

--========================================
-- Public API
--========================================

function StaminaService.Init(_NetController)
	if initialized then return end
	
	NetController = _NetController
	
	-- 클라이언트 요청 핸들러 등록
	if NetController then
		NetController.RegisterHandler("Movement.StartSprint", function(player)
			return StaminaService.startSprint(player)
		end)
		
		NetController.RegisterHandler("Movement.StopSprint", function(player)
			return StaminaService.stopSprint(player)
		end)
		
		NetController.RegisterHandler("Movement.Dodge", function(player, data)
			return StaminaService.performDodge(player, data.direction)
		end)
		
		NetController.RegisterHandler("Stamina.GetState", function(player)
			local data = getStaminaData(player.UserId)
			return {
				current = data.current,
				max = data.max,
				isSprinting = data.isSprinting,
			}
		end)
	end
	
	-- 플레이어 접속 시 초기화
	Players.PlayerAdded:Connect(function(player)
		getStaminaData(player.UserId)
		task.defer(function()
			syncStaminaToClient(player)
		end)
	end)
	
	-- 플레이어 퇴장 시 정리
	Players.PlayerRemoving:Connect(function(player)
		playerStamina[player.UserId] = nil
		playerStagger[player.UserId] = nil
	end)
	
	-- 스태미나 틱 루프 (0.1초마다)
	task.spawn(function()
		while true do
			task.wait(0.1)
			StaminaService._tickLoop()
		end
	end)
	
	initialized = true
	print("[StaminaService] Initialized")
end

function StaminaService.setMaxStamina(userId: number, max: number)
	local data = getStaminaData(userId)
	local oldMax = data.max
	data.max = max
	
	-- 최대치가 늘어났을 때 현재치도 그만큼 채워줌 (로그인 시 초기화 대응)
	if max > oldMax then
		data.current = data.current + (max - oldMax)
	end
	
	-- 만약 현재 스태미나가 새로운 최대치를 넘는다면 조정
	if data.current > max then
		data.current = max
	end
	
	-- 변경사항 동기화
	local player = Players:GetPlayerByUserId(userId)
	if player then
		syncStaminaToClient(player)
	end
end

function StaminaService.GetHandlers()
	return {}
end

--========================================
-- Stamina Tick Loop
--========================================

function StaminaService._tickLoop()
	local now = tick()
	
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		local data = playerStamina[userId]
		if not data then continue end
		
		local changed = false
		
		-- 스프린트 중이면 소모
		if data.isSprinting then
			-- [FIX] 실제 이동 중인지 서버에서 검증 (가만히 서서 Shift만 누르는 경우 방지)
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid")
			local isMoving = humanoid and humanoid.MoveDirection.Magnitude > 0
			
			if isMoving then
				local cost = Balance.SPRINT_STAMINA_COST * 0.1 -- 0.1초 단위
				data.current = math.max(0, data.current - cost)
				data.lastUseTime = now
				changed = true
				
				-- 달리기 시 배고픔 소모 연동
				local HSuccess, HungerService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
				if HSuccess and HungerService then
					HungerService.consumeHunger(userId, Balance.HUNGER_SPRINT_COST * 0.1)
				end
			end
			
			-- 스태미나 바닥나면 스프린트 중지
			if data.current <= 0 then
				data.isSprinting = false
				StaminaService._updatePlayerSpeed(player, false)
			end
		else
			-- 회복 딜레이 체크
			local timeSinceUse = now - data.lastUseTime
			if timeSinceUse >= Balance.STAMINA_REGEN_DELAY then
				-- 스태미나 회복
				local regenAmount = Balance.STAMINA_REGEN * 0.1
				local newStamina = math.min(data.max, data.current + regenAmount)
				if newStamina ~= data.current then
					data.current = newStamina
					changed = true
				end
			end
		end
		
		-- [Stagger] 경직 만료 시 속도 복구
		local stagger = playerStagger[player.UserId]
		if stagger and tick() >= stagger.expireTime then
			playerStagger[player.UserId] = nil
			StaminaService._updatePlayerSpeed(player, data.isSprinting)
		end
		
		-- [Anti-Cheat] 속도 검증 (버프/스탯 반영 최대 속도 기준)
		local character = player.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		if humanoid then
			local baseSpeed = _getBaseSpeed(player.UserId)
			local maxAllowedSpeed = baseSpeed * (data.isSprinting and Balance.SPRINT_SPEED_MULT or 1.0)
			-- 무게 초과 등 다른 감속 요인이 있을 수 있으므로, '초과'하는 경우만 제재
			if humanoid.WalkSpeed > maxAllowedSpeed + 0.1 then
				humanoid.WalkSpeed = maxAllowedSpeed
			end
		end

		-- 클라이언트에 동기화 (변경 있을 때만)
		if changed then
			syncStaminaToClient(player)
		end
	end
end

--========================================
-- Sprint System
--========================================

function StaminaService.startSprint(player: Player): boolean
	local userId = player.UserId
	local data = getStaminaData(userId)
	
	-- 이미 스프린트 중
	if data.isSprinting then
		return true
	end
	
	-- 스태미나 부족
	if data.current < Balance.SPRINT_MIN_STAMINA then
		return false
	end
	
	-- 구르기 중에는 스프린트 불가
	if data.isDodging then
		return false
	end
	
	data.isSprinting = true
	StaminaService._updatePlayerSpeed(player, true)
	
	return true
end

function StaminaService.stopSprint(player: Player): boolean
	local userId = player.UserId
	local data = getStaminaData(userId)
	
	if not data.isSprinting then
		return true
	end
	
	data.isSprinting = false
	StaminaService._updatePlayerSpeed(player, false)
	
	return true
end

function StaminaService._updatePlayerSpeed(player: Player, sprinting: boolean)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- 버프/스탯 반영된 기본 속도
	local baseSpeed = _getBaseSpeed(player.UserId)
	
	local speed
	if sprinting then
		speed = baseSpeed * Balance.SPRINT_SPEED_MULT
	else
		speed = baseSpeed
	end
	
	-- 경직(Stagger) 배율 적용
	local stagger = playerStagger[player.UserId]
	if stagger and tick() < stagger.expireTime then
		speed = speed * stagger.mult
	end
	
	humanoid.WalkSpeed = speed
end

--========================================
-- Stagger (경직) System
--========================================

--- 경직 상태 부여: mult 배율로 speed를 감소시키고 duration 후 자동 해제
function StaminaService.setStagger(userId: number, mult: number, duration: number)
	playerStagger[userId] = {
		mult = mult,
		expireTime = tick() + duration,
	}
	-- 즉시 속도 반영
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local data = getStaminaData(userId)
		StaminaService._updatePlayerSpeed(player, data.isSprinting)
	end
end

--- 경직 상태 즉시 해제
function StaminaService.clearStagger(userId: number)
	if not playerStagger[userId] then return end
	playerStagger[userId] = nil
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local data = getStaminaData(userId)
		StaminaService._updatePlayerSpeed(player, data.isSprinting)
	end
end

--- 경직 중인지 확인
function StaminaService.isStaggered(userId: number): boolean
	local stagger = playerStagger[userId]
	return stagger ~= nil and tick() < stagger.expireTime
end

--========================================
-- Dodge System
--========================================

function StaminaService.performDodge(player: Player, direction: Vector3?): { success: boolean, reason: string? }
	local userId = player.UserId
	local data = getStaminaData(userId)
	local now = tick()
	
	-- [FIX #7] 뮤텍스: 동시 dodge 요청 방지
	-- 최대 100ms 대기 후 강제 진행
	local waitStart = tick()
	while staminaUpdateLocks[userId] and (tick() - waitStart) < 0.1 do
		task.wait(0.001)
	end
	
	-- 쿨다운 체크
	local lastDodge = data.lastDodgeTime or 0
	if now - lastDodge < Balance.DODGE_COOLDOWN then
		return { success = false, reason = "cooldown" }
	end
	
	-- 스태미나 체크
	if data.current < Balance.DODGE_STAMINA_COST then
		return { success = false, reason = "no_stamina" }
	end
	
	-- [FIX] 공중 구르기(Air Dash) 방지
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.FloorMaterial == Enum.Material.Air then
		return { success = false, reason = "not_grounded" }
	end

	-- 이미 구르기 중
	if data.isDodging then
		return { success = false, reason = "already_dodging" }
	end
	
	-- [FIX #7] 락 설정 후 최종 검증
	staminaUpdateLocks[userId] = true
	
	-- 최종 스태미나 검증 (락 획득 후 재확인)
	if data.current < Balance.DODGE_STAMINA_COST then
		staminaUpdateLocks[userId] = nil
		return { success = false, reason = "no_stamina" }
	end
	
	-- 스태미나 소모 (원자적)
	data.current = math.max(0, data.current - Balance.DODGE_STAMINA_COST)
	data.lastUseTime = now
	data.lastDodgeTime = now
	data.isDodging = true
	
	-- 락 해제
	staminaUpdateLocks[userId] = nil
	
	-- 구르기 시 배고픔 소모 연동
	local HSuccess, HungerService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
	if HSuccess and HungerService then
		HungerService.consumeHunger(userId, Balance.HUNGER_DODGE_COST)
	end
	
	-- 무적 프레임 설정
	data.isInvulnerable = true
	task.delay(Balance.DODGE_IFRAMES, function()
		if playerStamina[userId] then
			playerStamina[userId].isInvulnerable = false
		end
	end)
	
	-- 구르기 종료
	task.delay(Balance.DODGE_DURATION, function()
		if playerStamina[userId] then
			playerStamina[userId].isDodging = false
		end
	end)
	
	-- [IMPORTANT] 서버 사이드 물리 이동(BodyVelocity) 제거
	-- 캐릭터의 Network Ownership은 클라이언트에 있으므로, 
	-- 서버에서 직접 힘을 가하면 위치 동기화(Rubberbanding) 문제가 발생함.
	-- 이동 처리는 클라이언트(MovementController.lua)에서 수행함.
	
	-- 클라이언트에 동기화
	syncStaminaToClient(player)
	
	-- 클라이언트에 구르기 애니메이션 재생 요청
	if NetController then
		NetController.FireClient(player, "Movement.DodgeStarted", {
			direction = direction,
		})
	end
	
	return { success = true }
end

--========================================
-- Query API
--========================================

function StaminaService.getStamina(userId: number): (number, number)
	local data = getStaminaData(userId)
	return data.current, data.max
end

function StaminaService.hasEnoughStamina(userId: number, amount: number): boolean
	local data = getStaminaData(userId)
	return data.current >= amount
end

function StaminaService.consumeStamina(userId: number, amount: number): boolean
	-- [FIX #7] 뮤텍스: 동시 업데이트 방지
	-- 최대 100ms 대기 후 강제 진행 (데드락 방지)
	local waitStart = tick()
	while staminaUpdateLocks[userId] and (tick() - waitStart) < 0.1 do
		task.wait(0.001)
	end
	
	-- 락 설정
	staminaUpdateLocks[userId] = true
	
	local data = getStaminaData(userId)
	
	-- 스태미나 검증 및 차감 (원자적 연산)
	if data.current < amount then
		staminaUpdateLocks[userId] = nil
		return false
	end
	
	data.current = math.max(0, data.current - amount)
	data.lastUseTime = tick()
	
	-- 락 해제
	staminaUpdateLocks[userId] = nil
	
	local player = Players:GetPlayerByUserId(userId)
	if player then
		syncStaminaToClient(player)
	end
	
	return true
end

function StaminaService.restoreFull(userId: number)
	local data = getStaminaData(userId)
	data.current = data.max
	data.lastUseTime = 0

	local player = Players:GetPlayerByUserId(userId)
	if player then
		syncStaminaToClient(player)
	end
end

function StaminaService.isInvulnerable(userId: number): boolean
	local data = playerStamina[userId]
	return data and data.isInvulnerable or false
end

function StaminaService.isSprinting(userId: number): boolean
	local data = playerStamina[userId]
	return data and data.isSprinting or false
end

function StaminaService.isDodging(userId: number): boolean
	local data = playerStamina[userId]
	return data and data.isDodging or false
end

return StaminaService
