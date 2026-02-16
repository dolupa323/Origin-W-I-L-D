-- CombatController.lua
-- 클라이언트 전투 컨트롤러 (공격 요청)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)

local CombatController = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 공격 쿨다운
local lastAttackTime = 0
local ATTACK_COOLDOWN = 0.5  -- 0.5초

--========================================
-- Internal Functions
--========================================

--- 공격 대상 찾기 (마우스 위치 기준)
local function findTarget(): (Instance?, Vector3?, string?)
	local target = InputManager.getMouseTarget()
	
	if not target then
		return nil, nil, nil
	end
	
	-- Creatures 폴더 하위인지 확인
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if creaturesFolder and target:IsDescendantOf(creaturesFolder) then
		-- 모델 찾기 (루트 파트의 부모)
		local model = target:FindFirstAncestorOfClass("Model")
		if model then
			local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			local instanceId = model:GetAttribute("InstanceId")
			if hrp and instanceId then
				return model, hrp.Position, instanceId
			end
		end
	end
	
	return nil, nil, nil
end

--- 플레이어와 대상 간 거리 확인
local function getDistanceToTarget(targetPos: Vector3): number
	local character = player.Character
	if not character then return math.huge end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return math.huge end
	
	return (hrp.Position - targetPos).Magnitude
end

--========================================
-- Public API
--========================================

--- 공격 실행
function CombatController.attack()
	-- UI가 열려있으면 무시
	if InputManager.isUIOpen() then
		return
	end
	
	-- 쿨다운 체크
	local now = tick()
	if now - lastAttackTime < ATTACK_COOLDOWN then
		return
	end
	
	local targetModel, targetPos, instanceId = findTarget()
	
	if targetModel and targetPos and instanceId then
		local distance = getDistanceToTarget(targetPos)
		
		-- 공격 범위 체크 (10 스터드)
		if distance > 10 then
			print("[CombatController] Target too far: " .. string.format("%.1f", distance))
			return
		end
		
		-- 서버에 공격 요청 (InstanceId 전송)
		NetClient.Request("Combat.Hit.Request", {
			targetInstanceId = instanceId,
			targetPosition = { x = targetPos.X, y = targetPos.Y, z = targetPos.Z },
		}, function(response)
			if response.success then
				print("[CombatController] Attack hit!")
			else
				print("[CombatController] Attack failed:", response.errorCode or "unknown")
			end
		end)
		
		lastAttackTime = now
	else
		-- 대상 없이 빈 공격 (공기 스윙)
		print("[CombatController] Swing (no target)")
		lastAttackTime = now
	end
end

--========================================
-- Initialization
--========================================

function CombatController.Init()
	if initialized then
		warn("[CombatController] Already initialized!")
		return
	end
	
	-- 좌클릭 = 공격
	InputManager.onLeftClick(function(hitPos)
		CombatController.attack()
	end)
	
	initialized = true
	print("[CombatController] Initialized")
end

return CombatController
