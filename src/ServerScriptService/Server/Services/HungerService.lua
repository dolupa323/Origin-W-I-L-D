-- HungerService.lua
-- Phase 11: 배고픔 및 생존 관리 서비스
-- 시간이 지남에 따라 배고픔이 줄어들고 0이 되면 체력을 소모함.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local HungerService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController

--========================================
-- Internal State
--========================================
-- [userId] = { current, max }
local playerHunger = {}

--========================================
-- Internal Helpers
--========================================

local function getHungerData(userId: number)
	if not playerHunger[userId] then
		playerHunger[userId] = {
			current = Balance.HUNGER_MAX,
			max = Balance.HUNGER_MAX,
		}
	end
	return playerHunger[userId]
end

local function syncHungerToClient(player: Player)
	if not NetController then return end
	
	local data = getHungerData(player.UserId)
	NetController.FireClient(player, "Hunger.Update", {
		current = data.current,
		max = data.max,
	})
end

--========================================
-- Public API
--========================================

function HungerService.Init(_NetController)
	if initialized then return end
	
	NetController = _NetController
	
	-- 클라이언트 요청 핸들러 등록
	if NetController then
		NetController.RegisterHandler("Hunger.GetState", function(player)
			local data = getHungerData(player.UserId)
			return {
				current = data.current,
				max = data.max,
			}
		end)
	end
	
	-- 플레이어 접속 시 초기화
	Players.PlayerAdded:Connect(function(player)
		getHungerData(player.UserId)
		task.defer(function()
			syncHungerToClient(player)
		end)
	end)
	
	-- 플레이어 퇴장 시 정리
	Players.PlayerRemoving:Connect(function(player)
		playerHunger[player.UserId] = nil
	end)
	
	-- 배고픔 틱 루프 (1초마다)
	task.spawn(function()
		while true do
			task.wait(1)
			HungerService._tickLoop()
		end
	end)
	
	initialized = true
	print("[HungerService] Initialized")
end

--========================================
-- Hunger Tick Loop
--========================================

function HungerService._tickLoop()
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		local character = player.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		
		local data = playerHunger[userId]
		if not data then continue end
		
		-- 살아있는 경우에만 감소 (사망 시에는 멈춤)
		if humanoid and humanoid.Health > 0 then
			local changed = false
			
			if data.current > 0 then
				data.current = math.max(0, data.current - Balance.HUNGER_DECREASE_RATE)
				changed = true
			end
			
			if data.current <= 0 then
				-- 아사 데미지 적용
				humanoid.Health = math.max(0, humanoid.Health - Balance.HUNGER_STARVATION_DAMAGE)
			end
			
			if changed then
				syncHungerToClient(player)
			end
		else
			-- 죽었거나 스폰 중이면 배고픔 리셋
			if data.current < data.max then
				data.current = data.max
				syncHungerToClient(player)
			end
		end
	end
end

--========================================
-- Query / Consume API
--========================================

function HungerService.getHunger(userId: number): (number, number)
	local data = getHungerData(userId)
	return data.current, data.max
end

function HungerService.consumeHunger(userId: number, amount: number)
	local data = getHungerData(userId)
	
	if data.current > 0 then
		data.current = math.max(0, data.current - amount)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			syncHungerToClient(player)
		end
	end
end

function HungerService.eatFood(userId: number, foodValue: number): boolean
	local data = getHungerData(userId)
	
	data.current = math.min(data.max, data.current + foodValue)
	
	local player = Players:GetPlayerByUserId(userId)
	if player then
		syncHungerToClient(player)
	end
	
	return true
end

return HungerService
