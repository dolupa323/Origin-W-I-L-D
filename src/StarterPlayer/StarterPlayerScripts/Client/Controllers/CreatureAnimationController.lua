-- CreatureAnimationController.lua
-- 크리처 모델의 애니메이션을 상태별로 자동 재생하는 컨트롤러

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureAnimationIds = require(Shared.Config.CreatureAnimationIds)
local DataHelper = require(Shared.Util.DataHelper)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local AnimationManager = require(Client.Utils.AnimationManager)

local CreatureAnimationController = {}

--========================================
-- Internal State
--========================================
local initialized = false
local activeCreatures = {} -- [model] = { currentTrack = AnimationTrack, lastAnim = string }

local function refreshCreatureLabel(model)
	if not model or not model:IsA("Model") then return end

	local creatureId = tostring(model:GetAttribute("CreatureId") or model.Name or ""):upper()
	if creatureId == "" then return end

	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then return end

	local label = root:FindFirstChild("CreatureLabel")
	if not label then return end

	local main = label:FindFirstChildWhichIsA("Frame")
	if not main then return end

	local nameLabel = main:FindFirstChild("NameLabel")
	if nameLabel and nameLabel:IsA("TextLabel") then
		local creatureData = DataHelper.GetData("CreatureData", creatureId)
		nameLabel.Text = (creatureData and creatureData.name) or creatureId
	end
end

--========================================
-- Private Functions
--========================================

local function getAnimNameForState(creatureModel, speed, info)
	-- [개선] 더 다양한 이름 형식 지원
	local attrId = creatureModel:GetAttribute("CreatureId")
	local nameId = creatureModel.Name:upper()
	
	local creatureId = attrId or nameId
	local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds[creatureModel.Name] or CreatureAnimationIds.DEFAULT
	
	-- 서버 상태(State) 속성 확인
	local state = creatureModel:GetAttribute("State")
	
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
	
	-- IDLE 상태에서 IDLE_VARIANTS가 있으면 일정 시간마다 랜덤 교체
	if animKey == "IDLE" and animSet and animSet.IDLE_VARIANTS and info then
		local now = tick()
		if not info.idleVariantUntil or now >= info.idleVariantUntil then
			local variants = animSet.IDLE_VARIANTS
			info.idleVariantAnim = variants[math.random(1, #variants)]
			info.idleVariantUntil = now + math.random(4, 8) -- 4~8초 유지
		end
		return info.idleVariantAnim
	end
	
	-- IDLE이 아닌 상태로 전환 시 변형 리셋
	if info and animKey ~= "IDLE" then
		info.idleVariantUntil = nil
		info.idleVariantAnim = nil
	end
	
	return animSet and animSet[animKey]
end

local function updateCreatureAnimation(model, info)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	-- ★ DEAD 상태에서도 사망 애니메이션 재생 허용
	local currentState = model:GetAttribute("State")
	if humanoid.Health <= 0 and currentState ~= "DEAD" then 
		return 
	end

	-- ★ 실제 사망(IsDead=true)이면 서버 HarvestService가 애니메이션을 처리하므로 클라이언트 스킵
	if model:GetAttribute("IsDead") == true then
		return
	end
	
	local rootPart = model.PrimaryPart
	if not rootPart then 
		-- 대기 로직 제거 (다음 프레임에 자연스럽게 처리되도록 함)
		return 
	end
	
	-- 1. 속도 기반 상태 측정 (★ EMA 스무딩 적용 — 네트워크 지연으로 인한 떨림 방지)
	local velocity = rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local rawSpeed = velocity.Magnitude
	local smoothing = 0.25 -- EMA 계수 (0~1, 낮을수록 부드러움)
	info.smoothedSpeed = info.smoothedSpeed and (info.smoothedSpeed + (rawSpeed - info.smoothedSpeed) * smoothing) or rawSpeed
	local speed = info.smoothedSpeed
	
	-- ★ 넉백 달리기 모션 방지: WalkSpeed가 0 이상이고 실제 물리 속도가 WalkSpeed의 1.5배 초과
	-- → 자발적 이동이 아닌 외부 충격(넉백)으로 판단하여 속도 0 취급
	-- 단, 서버 State가 이동 상태(WANDER/CHASE/FLEE)이면 넉백 억제 적용하지 않음
	local walkSpeed = humanoid.WalkSpeed
	local isServerMoving = (currentState == "WANDER" or currentState == "CHASE" or currentState == "FLEE")
	if not isServerMoving and walkSpeed > 0.1 and speed > walkSpeed * 1.5 then
		speed = 0
	end
	
	-- 2. 대상 애니메이션 결정
	local targetAnimName = getAnimNameForState(model, speed, info)
	
	-- [중요] 공격 중일 때는 이동 애니메이션으로 덮어쓰지 않음
	local creatureId = model:GetAttribute("CreatureId") or model.Name:upper()
	local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
	local attackAnimName = animSet.ATTACK
	
	-- ★ 사망 상태면 공격 플래그 강제 해제 → 사망 애니메이션 우선
	if currentState == "DEAD" then
		info.isAttacking = false
	elseif info.isAttacking then
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
	local isLocomotion = targetAnimName and (targetAnimName:lower():find("walk") or targetAnimName:lower():find("run"))
	
	-- ★ 보행/달리기 애니메이션 재생 속도 계산
	-- 서버 State가 이동 중이면 물리 속도가 0이어도 기본 1.0 보장 (미끄러짐 방지)
	local locomotionSpeed = 1.0
	if isLocomotion then
		local effectiveSpeed = math.max(speed, rawSpeed * 0.5)
		if isServerMoving and effectiveSpeed < 1 then
			-- 서버가 이동 상태인데 물리 속도가 거의 없는 경우 (시작/정지 순간)
			locomotionSpeed = 1.0
		else
			locomotionSpeed = math.clamp(effectiveSpeed / math.max(walkSpeed, 1), 0.5, 2.0)
		end
	end
	
	if info.lastAnim ~= targetAnimName then
		-- 기존 이동 트랙 서서히 중지
		if info.lastAnim and info.lastAnim ~= "" then
			AnimationManager.stop(humanoid, info.lastAnim, 0.3)
		end
		
		-- 새 트랙 재생
		if targetAnimName and targetAnimName ~= "" then
			local track = AnimationManager.play(humanoid, targetAnimName, 0.3)
			if track then
				local isDeath = (currentState == "DEAD")
				track.Looped = not isDeath
				-- 보행/달리기 속도 조절
				if isLocomotion then
					track:AdjustSpeed(locomotionSpeed)
				end
				info.lastAnim = targetAnimName

				-- ★ DEATH 애니메이션: 95% 지점에서 프리즈 (마지막 포즈 유지)
				if isDeath then
					info._deathFrozen = false
					task.spawn(function()
						-- Length 로딩 대기
						local waited = 0
						while track.Length <= 0 and waited < 2 do
							task.wait(0.1)
							waited += 0.1
						end
						local len = track.Length
						if len > 0 then
							local targetTime = len * 0.95
							while track.IsPlaying and track.TimePosition < targetTime do
								task.wait()
							end
						else
							task.wait(2.0)
						end
						if track and track.IsPlaying then
							track:AdjustSpeed(0) -- 마지막 프레임에서 프리즈
						end
						info._deathFrozen = true
					end)
				end
			else
				-- 애니메이션 로드 실패 시 잠금 방지 (다음 프레임 재시도 허용)
				info.lastAnim = ""
			end
		else
			info.lastAnim = ""
		end
	elseif targetAnimName and targetAnimName ~= "" then
		-- 동일 애니메이션 유지 중
		local track = AnimationManager.load(humanoid, targetAnimName)
		if track then
			-- ★ DEAD 상태에서는 DEATH 애니 재시작 방지 (프리즈 유지)
			if currentState == "DEAD" then
				-- 프리즈 상태 유지 — 아무것도 하지 않음
				return
			elseif not track.IsPlaying then
				-- 트랙이 중지된 경우 재시작 (루프 안 걸린 트랙 보호)
				track.Looped = true
				track:Play(0.3)
			end
			-- 보행/달리기 속도 실시간 동기화
			if isLocomotion then
				track:AdjustSpeed(locomotionSpeed)
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
			refreshCreatureLabel(child)
			child.DescendantAdded:Connect(function(desc)
				if desc.Name == "NameLabel" then
					task.defer(function()
						refreshCreatureLabel(child)
					end)
				end
			end)
		end
	end

	for _, model in ipairs(creatureFolder:GetChildren()) do
		onAdded(model)
	end
	
	creatureFolder.ChildAdded:Connect(onAdded)
	creatureFolder.ChildRemoved:Connect(function(child)
		-- 클라이언트 애니메이션 트랙 전부 정지 (공격 모션 잔류 방지)
		local humanoid = child:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0.2)
				end
			end
		end
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

	-- 펫 폴더도 동일하게 감시 (펫도 크리처 애니메이션 사용)
	task.spawn(function()
		local petFolder = Workspace:WaitForChild("ActivePets", 30)
		if petFolder then
			setupFolderListeners(petFolder)
		end
	end)

	-- 서버 공격 이벤트 수신 (레거시 호환 유지)
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
				local creatureId = model:GetAttribute("CreatureId") or model.Name:upper()
				local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
				local attackAnimName = animSet.ATTACK
				
				if attackAnimName then
					if info.lastAnim ~= "" then
						AnimationManager.stop(humanoid, info.lastAnim, 0.1)
						info.lastAnim = "" 
					end
					
					task.spawn(function()
						info.isAttacking = true
						local prepTrack = AnimationManager.play(humanoid, attackAnimName, 0.1)
						if prepTrack then
							prepTrack.Priority = Enum.AnimationPriority.Action
							task.wait(prepTrack.Length > 0 and prepTrack.Length or 0.5)
						end
						task.wait(0.1)
						info.isAttacking = false
					end)
				end
			end
		end
	end)

	-- ★ 텔레그래프 공격 이벤트 수신 (2단계: 선행 모션 → 공격 모션)
	NetClient.On("Creature.Attack.Telegraph", function(data)
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
				local creatureId = model:GetAttribute("CreatureId") or model.Name:upper()
				local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
				local windupTime = data.windupTime or 0.5
				local attackTime = data.attackTime or 0.5
				
				-- data.anim으로 애니메이션 결정 (nil이면 애니 없이 대기)
				local attackAnimName = nil
				if data.anim then
					attackAnimName = animSet[data.anim] or animSet.ATTACK
				end
				local windupAnimName = animSet.ATTACK_WINDUP or nil
				
				-- 현재 이동 애니메이션 중단
				if info.lastAnim ~= "" then
					AnimationManager.stop(humanoid, info.lastAnim, 0.1)
					info.lastAnim = ""
				end
				
				task.spawn(function()
					info.isAttacking = true
					
					-- 1단계: 선행 모션 (windup) — 공격 준비 자세
					local windupTrack = nil
					if windupAnimName and windupAnimName ~= attackAnimName then
						windupTrack = AnimationManager.play(humanoid, windupAnimName, 0.15)
						if windupTrack then
							windupTrack.Priority = Enum.AnimationPriority.Action
							if windupTrack.Length > 0 then
								windupTrack:AdjustSpeed(windupTrack.Length / windupTime)
							end
						end
						-- ★ 선딜 대부분 대기 후, 마지막 0.5초에 발광 경고
						local flashLeadTime = math.min(0.5, windupTime * 0.8)
						task.wait(windupTime - flashLeadTime)
						
						-- ★ 공격 직전 발광 경고: 노란 Highlight 반짝
						local highlight = Instance.new("Highlight")
						highlight.Name = "TelegraphGlow"
						highlight.FillColor = Color3.fromRGB(255, 240, 130)
						highlight.FillTransparency = 0.5
						highlight.OutlineColor = Color3.fromRGB(255, 220, 60)
						highlight.OutlineTransparency = 0.2
						highlight.Adornee = model
						highlight.Parent = model
						
						task.wait(flashLeadTime)
						
						if highlight and highlight.Parent then
							highlight:Destroy()
						end
					else
						-- windupAnim 없는 경우에도 마지막 0.5초 발광
						local flashLeadTime = math.min(0.5, windupTime * 0.8)
						task.wait(windupTime - flashLeadTime)
						
						local highlight = Instance.new("Highlight")
						highlight.Name = "TelegraphGlow"
						highlight.FillColor = Color3.fromRGB(255, 240, 130)
						highlight.FillTransparency = 0.5
						highlight.OutlineColor = Color3.fromRGB(255, 220, 60)
						highlight.OutlineTransparency = 0.2
						highlight.Adornee = model
						highlight.Parent = model
						
						task.wait(flashLeadTime)
						
						if highlight and highlight.Parent then
							highlight:Destroy()
						end
					end
					
					-- 2단계: 공격 모션 (attack) — 선행 모션과 크로스페이드
					if attackAnimName then
						local attackTrack = AnimationManager.play(humanoid, attackAnimName, 0.05)
						if attackTrack then
							attackTrack.Priority = Enum.AnimationPriority.Action
							if attackTrack.Length > 0 then
								attackTrack:AdjustSpeed(attackTrack.Length / attackTime)
							end
						end
						-- 공격 모션 시작 후 선행 모션 정지 (크로스페이드)
						if windupTrack and windupAnimName and windupAnimName ~= attackAnimName then
							AnimationManager.stop(humanoid, windupAnimName, 0.05)
						end
						task.wait(attackTime)
					else
						if windupTrack and windupAnimName then
							AnimationManager.stop(humanoid, windupAnimName, 0.1)
						end
						task.wait(attackTime)
					end
					
					task.wait(0.1)
					info.isAttacking = false
				end)
			end
		end
	end)
	
	-- ★ 육식공룡 야간 눈빛 효과
	local EYE_GLOW_COLOR = Color3.fromRGB(180, 255, 120) -- 옅은 초록빛
	local EYE_GLOW_BRIGHTNESS = 1.5
	local EYE_GLOW_RANGE = 4
	local lastNightCheck = 0
	local isCurrentlyNight = false

	local function updateNightEyeGlow()
		local now = tick()
		-- 2초마다 밤낮 체크 (성능)
		if now - lastNightCheck > 2 then
			lastNightCheck = now
			local clockTime = Lighting.ClockTime
			-- ★ [FIX] 밤 시간: 18:30 ~ 5:30 (18.5 ~ 5.5)
			isCurrentlyNight = (clockTime >= 18.5 or clockTime <= 5.5)
			-- 디버그: 밤낮 전환 시에만 로깅
			if (clockTime >= 18.4 and clockTime <= 18.6) or (clockTime >= 5.4 and clockTime <= 5.6) then
				print(string.format("[CreatureAnimationController] ClockTime=%.1f, isNight=%s", clockTime, tostring(isCurrentlyNight)))
			end
		end

		for model, info in pairs(activeCreatures) do
			if not model:IsDescendantOf(Workspace) then continue end
			local behavior = model:GetAttribute("Behavior")
			local isDead = model:GetAttribute("IsDead")
			
			-- 육식이 아니거나 죽었으면 기존 빛 제거
			if behavior ~= "AGGRESSIVE" or isDead then
				-- ★ [FIX] Head 파트 찾기 개선 (recursive 옵션 사용하고 모든 파트 확인)
				local head = model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart", true)
				if head then
					local existing = head:FindFirstChild("NightEyeGlow")
					if existing then existing:Destroy() end
				end
				continue
			end

			-- ★ [FIX] Head 찾기: 먼저 직접 자식 확인, 없으면 recursive 검색
			local head = model:FindFirstChild("Head")
			if not head then
				-- 실제 Head 파트 이름이 다를 수 있음 (예: HeadPart, Head_Part 등)
				for _, part in ipairs(model:FindFirstChild("Humanoid") and model:GetDescendants() or {}) do
					if part:IsA("BasePart") and (part.Name:lower():find("head") or (model.PrimaryPart and part == model.PrimaryPart)) then
						head = part
						break
					end
				end
			end
			
			if not head or not head:IsA("BasePart") then continue end

			local glow = head:FindFirstChild("NightEyeGlow")
			if isCurrentlyNight then
				if not glow then
					glow = Instance.new("PointLight")
					glow.Name = "NightEyeGlow"
					glow.Color = EYE_GLOW_COLOR
					glow.Brightness = EYE_GLOW_BRIGHTNESS
					glow.Range = EYE_GLOW_RANGE
					glow.Shadows = false
					glow.Parent = head
					print(string.format("[CreatureAnimationController] 눈빛 추가: %s (Part: %s)", model.Name, head.Name))
				end
				glow.Enabled = true
			else
				if glow then
					glow:Destroy()
				end
			end
		end
	end

	-- 루프 업데이트 (최적화: 0.1초 간격으로 상태 체크)
	local eyeGlowTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		for model, info in pairs(activeCreatures) do
			if model:IsDescendantOf(Workspace) then
				updateCreatureAnimation(model, info)
			else
				activeCreatures[model] = nil
			end
		end
		-- 눈빛 업데이트: 3초마다 (매 프레임 불필요)
		eyeGlowTimer = eyeGlowTimer + dt
		if eyeGlowTimer >= 3 then
			eyeGlowTimer = 0
			updateNightEyeGlow()
		end
	end)
	
	-- ★ [FIX] 초기 시작 시에도 한 번 updateNightEyeGlow 호출 (대기 없음)
	task.defer(updateNightEyeGlow)
	
	initialized = true
	print("[CreatureAnimationController] Initialized")
end

return CreatureAnimationController
