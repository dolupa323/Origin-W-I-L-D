-- CombatController.lua
-- 클라이언트 전투 컨트롤러 (공격 요청, 애니메이션)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared.Config.AnimationIds)

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

-- 콤보 시스템
local currentComboIndex = 1
local comboResetTime = 1.0  -- 1초 내 다음 공격 안하면 콤보 리셋

-- 애니메이션 트랙
local currentAttackTrack = nil

--========================================
-- Internal Functions
--========================================

--- 장착 도구 타입 확인
local function getEquippedToolType(): string?
	local character = player.Character
	if not character then return nil end
	
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		return tool:GetAttribute("ToolType") or tool.Name:upper()
	end
	
	return nil
end

local AnimationManager = require(Client.Utils.AnimationManager)

--- 공격 애니메이션 재생
local function playAttackAnimation(isHit: boolean)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- 기존 공격 애니메이션 중지
	if currentAttackTrack and currentAttackTrack.IsPlaying then
		currentAttackTrack:Stop(0.1)
	end
	
	-- 도구 타입에 따른 애니메이션 선택
	local toolType = getEquippedToolType()
	local animNames
	
	if toolType == "AXE" or toolType == "PICKAXE" then
		animNames = AnimationIds.COMBO_TOOL
	elseif toolType == "SPEAR" then
		animNames = { AnimationIds.ATTACK_SPEAR.THRUST, AnimationIds.ATTACK_SPEAR.SWING }
	elseif toolType == "CLUB" then
		animNames = { AnimationIds.ATTACK_CLUB.SMASH, AnimationIds.ATTACK_CLUB.SWING }
	else
		-- 맨손 공격
		animNames = AnimationIds.COMBO_UNARMED
	end
	
	-- 콤보 인덱스에 따른 애니메이션 선택
	local animName = animNames[currentComboIndex] or animNames[1]
	
	-- 애니메이션 재생 (AnimationManager 사용)
	local track = AnimationManager.play(humanoid, animName, 0.05)
	if track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		
		-- 맞았을 때 속도 조절 (임팩트 느낌)
		if isHit then
			track:AdjustSpeed(1.2)  -- 빠르게
		else
			track:AdjustSpeed(1.0)
		end
		
		currentAttackTrack = track
	end
	
	-- 콤보 증가 (다음 공격시 다른 모션)
	currentComboIndex = currentComboIndex + 1
	if currentComboIndex > #animNames then
		currentComboIndex = 1
	end
	
	-- 콤보 리셋 타이머
	task.delay(comboResetTime, function()
		if tick() - lastAttackTime >= comboResetTime then
			currentComboIndex = 1
		end
	end)
end

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
	
	lastAttackTime = now
	
	local targetModel, targetPos, instanceId = findTarget()
	
	if targetModel and targetPos and instanceId then
		local distance = getDistanceToTarget(targetPos)
		
		-- 공격 범위 체크 (10 스터드)
		if distance > 10 then
			-- 범위 밖 - 빈 스윙 애니메이션
			playAttackAnimation(false)
			print("[CombatController] Target too far: " .. string.format("%.1f", distance))
			return
		end
		
		-- 공격 성공 애니메이션 (타격)
		playAttackAnimation(true)
		
		-- 서버에 공격 요청 (InstanceId 전송)
		local success, data = NetClient.Request("Combat.Hit.Request", {
			targetInstanceId = instanceId,
			targetPosition = { x = targetPos.X, y = targetPos.Y, z = targetPos.Z },
		})
		if success then
			print("[CombatController] Attack hit!")
		else
			print("[CombatController] Attack failed:", tostring(data))
		end
	else
		-- 대상 없이 빈 공격 (공기 스윙)
		playAttackAnimation(false)
		print("[CombatController] Swing (no target)")
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
