-- CreatureAnimationController.lua
-- 크리처 모델의 애니메이션을 상태별로 자동 재생하는 컨트롤러

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureAnimationIds = require(Shared.Config.CreatureAnimationIds)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local AnimationManager = require(Client.Utils.AnimationManager)

local CreatureAnimationController = {}

--========================================
-- Internal State
--========================================
local initialized = false
local activeCreatures = {} -- [model] = { currentTrack = AnimationTrack, lastAnim = string }

--========================================
-- Private Functions
--========================================

local function getAnimNameForState(creatureModel, speed)
	local creatureId = creatureModel:GetAttribute("CreatureId") or "DEFAULT"
	local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
	
	-- 서버 상태(State) 속성 확인
	local state = creatureModel:GetAttribute("State") or "IDLE"
	
	local animKey = "IDLE"
	if state == "STUNNED" then
		animKey = "STUNNED"
	elseif state == "DEAD" then
		animKey = "DEATH"
	elseif state == "CHASE" or state == "FLEE" then
		animKey = "RUN"
	elseif state == "WANDER" then
		animKey = "WALK"
	elseif speed and speed > 1.5 then
		animKey = speed > 15 and "RUN" or "WALK"
	end
	
	-- 해당 애니메이션 키가 세트에 없으면 무시 (불필요한 로딩 방지)
	return animSet[animKey]
end

local function updateCreatureAnimation(model, info)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then 
		return 
	end
	
	local rootPart = model.PrimaryPart
	if not rootPart then return end
	
	-- 1. 속도 기반 상태 측정
	local velocity = rootPart.Velocity * Vector3.new(1, 0, 1)
	local speed = velocity.Magnitude
	
	-- 2. 대상 애니메이션 결정
	local targetAnimName = getAnimNameForState(model, speed)
	
	-- [중요] 공격 중일 때는 이동 애니메이션으로 덮어쓰지 않음
	local creatureId = model:GetAttribute("CreatureId") or "DEFAULT"
	local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
	local attackAnimName = animSet.ATTACK
	
	if info.isAttacking then
		-- 공격 애니메이션이 끝났는지 체크 (캐시된 트랙 활용)
		local attackTrack = AnimationManager.load(humanoid, attackAnimName)
		if attackTrack and not attackTrack.IsPlaying then
			info.isAttacking = false
		else
			-- 아직 공격 중이면 이동 애니메이션 생략
			return
		end
	end

	-- 3. 애니메이션 전환 처리
	if info.lastAnim ~= targetAnimName then
		-- 기존 이동 트랙 서서히 중지
		if info.lastAnim and info.lastAnim ~= "" then
			AnimationManager.stop(humanoid, info.lastAnim, 0.3)
		end
		
		-- 새 트랙 재생
		if targetAnimName and targetAnimName ~= "" then
			local track = AnimationManager.play(humanoid, targetAnimName, 0.3)
			if track then
				-- 보행/달리기 속도 조절
				if targetAnimName:lower():find("walk") or targetAnimName:lower():find("run") then
					track:AdjustSpeed(speed / math.max(humanoid.WalkSpeed, 1))
				end
			end
			info.lastAnim = targetAnimName
		else
			info.lastAnim = ""
		end
	elseif targetAnimName and targetAnimName ~= "" then
		-- 재생 중인 트랙 속도 실시간 동기화
		local track = AnimationManager.load(humanoid, targetAnimName)
		if track and track.IsPlaying then
			if targetAnimName:lower():find("walk") or targetAnimName:lower():find("run") then
				local playbackSpeed = math.clamp(speed / math.max(humanoid.WalkSpeed, 1), 0.5, 2.0)
				track:AdjustSpeed(playbackSpeed)
			end
		end
	end
end

local function setupFolderListeners(creatureFolder)
	local function onAdded(child)
		if child:IsA("Model") then
			task.wait(0.1) -- 속성 데이터 동기화 대기
			if not activeCreatures[child] then
				activeCreatures[child] = { lastAnim = "", isAttacking = false }
			end
		end
	end

	for _, model in ipairs(creatureFolder:GetChildren()) do
		onAdded(model)
	end
	
	creatureFolder.ChildAdded:Connect(onAdded)
	creatureFolder.ChildRemoved:Connect(function(child)
		activeCreatures[child] = nil
	end)
end

--========================================
-- Public API
--========================================

function CreatureAnimationController.Init()
	if initialized then return end
	
	task.spawn(function()
		local creatureFolder = Workspace:WaitForChild("Creatures", 30)
		if creatureFolder then
			setupFolderListeners(creatureFolder)
		end
	end)

	-- 서버 공격 이벤트 수신
	NetClient.On("Creature.Attack.Play", function(data)
		local model = nil
		for m, _ in pairs(activeCreatures) do
			if m:GetAttribute("InstanceId") == data.instanceId then
				model = m
				break
			end
		end
		
		if model then
			local info = activeCreatures[model]
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and info then
				local creatureId = model:GetAttribute("CreatureId") or "DEFAULT"
				local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
				local attackAnimName = animSet.ATTACK
				
				if attackAnimName then
					-- 현재 재생 중인 이동 애니메이션 잠시 중지 (부드러운 타격)
					if info.lastAnim ~= "" then
						AnimationManager.stop(humanoid, info.lastAnim, 0.1)
						info.lastAnim = "" -- 상태 강제 리셋하여 타격 후 다시 걷기 시작하게 함
					end
					
					local track = AnimationManager.play(humanoid, attackAnimName, 0.1)
					if track then
						track.Priority = Enum.AnimationPriority.Action
						info.isAttacking = true
						-- 애니메이션 종료 감지
						track.Stopped:Once(function()
							info.isAttacking = false
						end)
					end
				end
			end
		end
	end)
	
	-- 루프 업데이트 (최적화: 0.1초 간격으로 상태 체크)
	RunService.Heartbeat:Connect(function()
		for model, info in pairs(activeCreatures) do
			if model:IsDescendantOf(Workspace) then
				updateCreatureAnimation(model, info)
			else
				activeCreatures[model] = nil
			end
		end
	end)
	
	initialized = true
	print("[CreatureAnimationController] Initialized")
end

return CreatureAnimationController
