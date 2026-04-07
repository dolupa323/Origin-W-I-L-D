-- HitFeedbackController.lua
-- 플레이어 피격 연출 및 물리적 상태 보정, 히트스톱, 크리처 피격 연출
-- Phase 11-5: 전투 피드백 강화

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local HitFeedbackController = {}

-- Constants
local SHAKE_INTENSITY = 0.8
local SHAKE_DURATION = 0.15
local HITSTOP_DURATION = 0.06       -- 히트스톱 프레임 정지 시간 (60ms)
local ATTACKER_HITSTOP_DURATION = 0.05 -- 공격자 히트스톱 (50ms)
local STAGGER_DURATION = 0.25       -- 경직 시간 (이동속도 감소)
local STAGGER_SPEED_MULT = 0.15     -- 경직 중 이동속도 배율 (15%)
local VIGNETTE_FADE_TIME = 0.35     -- 피격 레드 비네트 페이드아웃 시간

local player = Players.LocalPlayer
local initialized = false
local isStaggered = false            -- 경직 중복 방지
local ACTION_EFFECTS_ENABLED = false

--========================================
-- Internal Functions
--========================================

--- 화면 흔들림 효과
local function playScreenShake(intensity)
	local cam = workspace.CurrentCamera
	if not cam then return end
	
	task.spawn(function()
		local originalCF = cam.CFrame
		for i = 1, 6 do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)
			cam.CFrame = originalCF * CFrame.new(offset)
			task.wait(0.02)
		end
		cam.CFrame = originalCF
	end)
end

--- 캐릭터 피격 흔들림 (채집 노드 흔들림과 유사한 연출)
local function playCharacterShake(sourcePos)
	local char = player.Character
	if not char or not char.PrimaryPart then return end
	
	local hrp = char.PrimaryPart
	local origPivot = char:GetPivot()
	
	task.spawn(function()
		-- 피격 방향으로부터 살짝 뒤로 튕김 (Recoil)
		local hitDir
		if sourcePos then
			hitDir = (hrp.Position - sourcePos)
		else
			hitDir = -hrp.CFrame.LookVector
		end
		-- ★ [FIX] Y축 제거: 지형 아래로 밀려들어가면 물리 발사 유발
		hitDir = Vector3.new(hitDir.X, 0, hitDir.Z)
		if hitDir.Magnitude < 0.01 then
			hitDir = -hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
		end
		hitDir = hitDir.Unit
		
		-- ★ [FIX] 월드 좌표 오프셋 사용 (origPivot * CFrame.new은 로컬 좌표 적용)
		-- CFrame.new(worldOffset) + origPivot 회전 조합 → 월드 방향 그대로 유지
		local offset1 = CFrame.new(hitDir * 0.5)
		local offset2 = CFrame.new(-hitDir * 0.2)
		
		-- 1단계: 반동
		char:PivotTo(offset1 * origPivot)
		task.wait(0.04)
		-- 2단계: 복원 시 미세 진동
		char:PivotTo(offset2 * origPivot)
		task.wait(0.04)
		char:PivotTo(origPivot)
	end)
end

--- 경직 효과 (피격 시 짧은 이동속도 감소)
--- NOTE: WalkSpeed 조작은 서버 StaminaService.setStagger에서 일원화.
---       클라이언트에서 중복 조작하면 경쟁 조건으로 속도가 영구 저하될 수 있으므로 제거.
local function applyStagger()
	-- 서버가 이미 경직을 처리하므로 클라이언트에서는 시각 연출만 담당
end

--- 피격 레드 비네트 플래시 (화면 테두리 빨갛게)
local function flashRedVignette()
	task.spawn(function()
		local playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return end
		
		-- 기존 비네트 제거
		local existing = playerGui:FindFirstChild("HitVignette")
		if existing then existing:Destroy() end
		
		local screen = Instance.new("ScreenGui")
		screen.Name = "HitVignette"
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = 100
		screen.Parent = playerGui
		
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
		frame.BackgroundTransparency = 0.65
		frame.BorderSizePixel = 0
		frame.Parent = screen
		
		-- 가장자리만 보이게 하는 UIGradient (중앙 투명, 가장자리 빨강)
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		gradient.Parent = frame
		
		-- 페이드아웃
		local tween = TweenService:Create(frame, TweenInfo.new(VIGNETTE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1
		})
		tween:Play()
		tween.Completed:Connect(function()
			screen:Destroy()
		end)
	end)
end

--- 캐릭터 상태 리셋 (드러눕는 현상 방지)
local function preventLyingDown()
	local char = player.Character
	if not char then return end
	
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	-- 매 프레임 GettingUp 상태로 리셋 시도 (물리 엔진에 의한 강제 눕기 방지)
	if humanoid:GetState() == Enum.HumanoidStateType.FallingDown or 
	   humanoid:GetState() == Enum.HumanoidStateType.Ragdoll or
	   humanoid:GetState() == Enum.HumanoidStateType.Landed then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

--- 히트스톱 (애니메이션 속도를 0으로 잠시 정지)
local function applyHitStop(humanoid: Humanoid, duration: number)
	if not humanoid then return end
	task.spawn(function()
		-- 현재 재생 중인 모든 애니메이션 트랙을 일시 정지
		local tracks = humanoid:GetPlayingAnimationTracks()
		for _, track in ipairs(tracks) do
			track:AdjustSpeed(0)
		end
		task.wait(duration)
		for _, track in ipairs(tracks) do
			if track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end
	end)
end

--- 피격 파티클 효과 생성
local function spawnHitParticle(position: Vector3)
	task.spawn(function()
		-- 임팩트 파트 (작은 원형 파티클 + 스파크)
		local emitterPart = Instance.new("Part")
		emitterPart.Size = Vector3.new(0.5, 0.5, 0.5)
		emitterPart.Transparency = 1
		emitterPart.CanCollide = false
		emitterPart.Anchored = true
		emitterPart.Position = position
		emitterPart.Parent = workspace.CurrentCamera

		-- 1. 메인 임팩트 파티클 (방사형 스파크)
		local spark = Instance.new("ParticleEmitter")
		spark.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(255, 80, 50))
		spark.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		})
		spark.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		spark.Lifetime = NumberRange.new(0.15, 0.35)
		spark.Speed = NumberRange.new(8, 18)
		spark.SpreadAngle = Vector2.new(180, 180)
		spark.Rate = 0
		spark.LightEmission = 1
		spark.LightInfluence = 0
		spark.Drag = 5
		spark.Parent = emitterPart

		-- 2. 작은 파편 파티클
		local debris = Instance.new("ParticleEmitter")
		debris.Color = ColorSequence.new(Color3.fromRGB(255, 255, 200))
		debris.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		})
		debris.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		debris.Lifetime = NumberRange.new(0.2, 0.5)
		debris.Speed = NumberRange.new(4, 12)
		debris.SpreadAngle = Vector2.new(360, 360)
		debris.Rate = 0
		debris.LightEmission = 0.8
		debris.Drag = 3
		debris.Acceleration = Vector3.new(0, -20, 0)
		debris.Parent = emitterPart

		-- 버스트 방출
		spark:Emit(8)
		debris:Emit(6)

		task.wait(0.6)
		emitterPart:Destroy()
	end)
end

--- 크리처 모델 찾기
local function findCreatureModel(instanceId: string): Model?
	for _, folderName in ipairs({"ActiveCreatures", "Creatures"}) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				if model:GetAttribute("InstanceId") == instanceId then
					return model
				end
			end
		end
	end
	return nil
end

--========================================
-- Public API
--========================================

function HitFeedbackController.Init()
	if initialized then return end
	
	-- 서버로부터 플레이어 피격 이벤트 수신
	NetClient.On("Combat.Player.Hit", function(data)
		-- 1. 화면 흔들림
		playScreenShake(SHAKE_INTENSITY)
		
		-- 2. 캐릭터 흔들림 (소스 위치가 있을 때)
		if data.sourcePos then
			playCharacterShake(data.sourcePos)
		end
		
		-- 3. 피격 히트스톱 (피격자: 잠깐 모든 애니메이션 정지)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			applyHitStop(hum, HITSTOP_DURATION)
		end
		
		-- 4. 경직 (이동속도 감소)
		applyStagger()
		
		-- 5. 피격 레드 비네트 플래시
		flashRedVignette()
		
		-- 6. 피격 파티클 (플레이어 위치)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			spawnHitParticle(hrp.Position + Vector3.new(0, 1, 0))
		end
		
		-- 7. ★ 넉백 제거: 크리처 반격 시 플레이어 위치 변경 없음 (튕김 방지)
		-- 화면 흔들림 + 경직만으로 피격 피드백 제공
	end)
	
	-- 크리처 피격 연출 이벤트 수신 (모든 클라이언트)
	NetClient.On("Combat.Creature.Hit", function(data)
		if not ACTION_EFFECTS_ENABLED then
			return
		end
		-- data: { instanceId, hitPosition {x,y,z}, damage, killed }
		if not data then return end
		
		local hitPos
		if data.hitPosition then
			hitPos = Vector3.new(data.hitPosition.x or 0, data.hitPosition.y or 0, data.hitPosition.z or 0)
		end
		
		-- 1. 피격 파티클 생성 (킬 시에도 재생)
		if hitPos then
			spawnHitParticle(hitPos)
		end
		
		-- 2. 크리처 히트스톱 (생존 시만 — 사망 시 사망 연출 방해 방지)
		if not data.killed then
			local model = findCreatureModel(data.instanceId)
			if model then
				local creatureHum = model:FindFirstChildOfClass("Humanoid")
				if creatureHum then
					applyHitStop(creatureHum, HITSTOP_DURATION)
				end
			end
		end
		
		-- 3. 공격자(로컬 플레이어) 히트스톱
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			applyHitStop(hum, ATTACKER_HITSTOP_DURATION)
		end
	end)
	
	-- 전투 중 접촉 경직 이벤트 수신 (크리처와 접촉 시 밀어내기)
	NetClient.On("Combat.Contact.Stagger", function(data)
		if not data then return end
		
		-- 가벼운 화면 흔들림 (공격 피격보다 약하게)
		playScreenShake(SHAKE_INTENSITY * 0.5)
		
		-- 짧은 비네트 (접촉 피드백)
		flashRedVignette()
		
		-- ★ 접촉 넉백 제거: 플레이어 위치 변경 없음 (튕김 방지)
		-- 화면 흔들림 + 비네트만으로 접촉 피드백 제공
	end)
	
	-- 눕는 현상을 방지하기 위한 주기적 체크 부하가 적으므로 Heartbeat 사용
	RunService.Heartbeat:Connect(preventLyingDown)
	
	initialized = true
	print("[HitFeedbackController] Initialized")
end

return HitFeedbackController
