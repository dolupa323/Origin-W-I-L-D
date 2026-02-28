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
			local cost = Balance.SPRINT_STAMINA_COST * 0.1 -- 0.1초 단위
			data.current = math.max(0, data.current - cost)
			data.lastUseTime = now
			changed = true
			
			-- 달리기 시 배고픔 소모 연동
			local HSuccess, HungerService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
			if HSuccess and HungerService then
				HungerService.consumeHunger(userId, Balance.HUNGER_SPRINT_COST * 0.1)
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
		
		-- 클라이언트에 동기화 (변경 있을 때만, 0.5초마다)
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
	
	-- 기본 속도 (default 16)
	local baseSpeed = 16
	
	if sprinting then
		humanoid.WalkSpeed = baseSpeed * Balance.SPRINT_SPEED_MULT
	else
		humanoid.WalkSpeed = baseSpeed
	end
end

--========================================
-- Dodge System
--========================================

function StaminaService.performDodge(player: Player, direction: Vector3?): { success: boolean, reason: string? }
	local userId = player.UserId
	local data = getStaminaData(userId)
	local now = tick()
	
	-- 쿨다운 체크
	local lastDodge = data.lastDodgeTime or 0
	if now - lastDodge < Balance.DODGE_COOLDOWN then
		return { success = false, reason = "cooldown" }
	end
	
	-- 스태미나 체크
	if data.current < Balance.DODGE_STAMINA_COST then
		return { success = false, reason = "no_stamina" }
	end
	
	-- 이미 구르기 중
	if data.isDodging then
		return { success = false, reason = "already_dodging" }
	end
	
	-- 스태미나 소모
	data.current = data.current - Balance.DODGE_STAMINA_COST
	data.lastUseTime = now
	data.lastDodgeTime = now
	data.isDodging = true
	
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
	
	-- 캐릭터에 힘 적용 (서버 authoritative)
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			-- 방향 계산 (없으면 캐릭터가 바라보는 방향)
			local dodgeDir = direction
			if not dodgeDir or dodgeDir.Magnitude == 0 then
				dodgeDir = rootPart.CFrame.LookVector
			else
				dodgeDir = dodgeDir.Unit
			end
			
			-- BodyVelocity로 구르기 힘 적용
			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.Name = "DodgeVelocity"
			bodyVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
			bodyVelocity.Velocity = dodgeDir * (Balance.DODGE_DISTANCE / Balance.DODGE_DURATION)
			bodyVelocity.Parent = rootPart
			
			-- 구르기 종료 시 제거
			task.delay(Balance.DODGE_DURATION, function()
				if bodyVelocity and bodyVelocity.Parent then
					bodyVelocity:Destroy()
				end
			end)
		end
	end
	
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
	local data = getStaminaData(userId)
	
	if data.current < amount then
		return false
	end
	
	data.current = data.current - amount
	data.lastUseTime = tick()
	
	local player = Players:GetPlayerByUserId(userId)
	if player then
		syncStaminaToClient(player)
	end
	
	return true
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
