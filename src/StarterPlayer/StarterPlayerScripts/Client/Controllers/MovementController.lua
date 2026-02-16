-- MovementController.lua
-- Phase 10: 플레이어 이동 컨트롤러
-- 스프린트, 구르기 등 고급 이동 액션 처리

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local MovementController = {}

--========================================
-- Dependencies
--========================================
local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 스태미나 상태 (서버에서 동기화)
local currentStamina = Balance.STAMINA_MAX
local maxStamina = Balance.STAMINA_MAX

-- 이동 상태
local isSprinting = false
local isDodging = false
local lastDodgeTime = 0

-- 키 상태
local shiftHeld = false
local movementDirection = Vector3.zero

-- 이벤트
local staminaChangedCallbacks = {}
local dodgeCallbacks = {}

--========================================
-- Internal Helpers
--========================================

local function getMoveDirection(): Vector3
	local character = player.Character
	if not character then return Vector3.zero end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return Vector3.zero end
	
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0 then
		return moveDir.Unit
	end
	
	-- 이동 중이 아니면 바라보는 방향
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		return rootPart.CFrame.LookVector
	end
	
	return Vector3.new(0, 0, -1)
end

local function fireStaminaChanged()
	for _, callback in ipairs(staminaChangedCallbacks) do
		task.spawn(callback, currentStamina, maxStamina)
	end
end

local function playDodgeAnimation()
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- 구르기 애니메이션 재생
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		-- 기본 구르기 애니메이션 (애셋이 없으면 생략)
		local dodgeAnim = Instance.new("Animation")
		dodgeAnim.AnimationId = "rbxassetid://0" -- 구르기 애니메이션 ID (나중에 교체)
		
		-- 임시: 애니메이션 없이 카메라 효과만
	end
	
	-- 카메라 쉐이크 효과
	local camera = workspace.CurrentCamera
	if camera then
		task.spawn(function()
			local originalCFrame = camera.CFrame
			for i = 1, 5 do
				local shake = CFrame.new(
					math.random(-5, 5) / 100,
					math.random(-5, 5) / 100,
					0
				)
				camera.CFrame = camera.CFrame * shake
				task.wait(0.02)
			end
		end)
	end
	
	-- 콜백 호출
	for _, callback in ipairs(dodgeCallbacks) do
		task.spawn(callback, getMoveDirection())
	end
end

--========================================
-- Sprint Logic
--========================================

local function updateSprint()
	local shouldSprint = shiftHeld and not isDodging and currentStamina >= Balance.SPRINT_MIN_STAMINA
	
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			-- 이동 중인지 체크
			local isMoving = humanoid.MoveDirection.Magnitude > 0
			shouldSprint = shouldSprint and isMoving
		end
	end
	
	if shouldSprint and not isSprinting then
		-- 스프린트 시작
		NetClient.Request("Movement.StartSprint")
		isSprinting = true
	elseif not shouldSprint and isSprinting then
		-- 스프린트 종료
		NetClient.Request("Movement.StopSprint")
		isSprinting = false
	end
end

--========================================
-- Dodge Logic
--========================================

local function performDodge()
	local now = tick()
	
	-- 쿨다운 체크 (클라이언트 사전 검사)
	if now - lastDodgeTime < Balance.DODGE_COOLDOWN then
		return
	end
	
	-- 스태미나 체크 (클라이언트 사전 검사)
	if currentStamina < Balance.DODGE_STAMINA_COST then
		return
	end
	
	-- 이미 구르기 중
	if isDodging then
		return
	end
	
	-- UI 열림 상태면 불가
	if InputManager.isUIOpen() then
		return
	end
	
	-- 방향 계산
	local direction = getMoveDirection()
	
	-- 서버에 구르기 요청
	local success, result = NetClient.Request("Movement.Dodge", { direction = direction })
	
	if success and result and result.success then
		lastDodgeTime = now
		isDodging = true
		
		-- 클라이언트 측 애니메이션 즉시 재생
		playDodgeAnimation()
		
		-- 구르기 종료
		task.delay(Balance.DODGE_DURATION, function()
			isDodging = false
		end)
	end
end

--========================================
-- Input Handling
--========================================

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	
	-- UI 열림 상태면 무시
	if InputManager.isUIOpen() then return end
	
	-- Shift: 스프린트 시작
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = true
		updateSprint()
	end
	
	-- Space (또는 Ctrl): 구르기
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		performDodge()
	end
end

local function onInputEnded(input: InputObject, gameProcessed: boolean)
	-- Shift: 스프린트 종료
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = false
		updateSprint()
	end
end

--========================================
-- Server Event Handlers
--========================================

local function onStaminaUpdate(data)
	currentStamina = data.current
	maxStamina = data.max
	
	if data.isSprinting ~= nil then
		isSprinting = data.isSprinting
	end
	
	fireStaminaChanged()
end

local function onDodgeStarted(data)
	-- 서버에서 구르기 시작 알림 (다른 플레이어용)
	-- 로컬 플레이어는 이미 performDodge에서 처리함
end

--========================================
-- Public API
--========================================

function MovementController.Init()
	if initialized then
		warn("[MovementController] Already initialized!")
		return
	end
	
	-- 입력 연결
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	
	-- 서버 이벤트 리스너
	NetClient.On("Stamina.Update", onStaminaUpdate)
	NetClient.On("Movement.DodgeStarted", onDodgeStarted)
	
	-- 키 바인딩 안내 추가
	InputManager.bindKey(Enum.KeyCode.LeftControl, "Dodge", performDodge)
	
	-- 프레임 업데이트 (스프린트 상태 체크)
	RunService.Heartbeat:Connect(function()
		if shiftHeld then
			updateSprint()
		end
	end)
	
	-- 초기 스태미나 요청
	task.spawn(function()
		local success, state = NetClient.Request("Stamina.GetState")
		if success and state then
			currentStamina = state.current
			maxStamina = state.max
			isSprinting = state.isSprinting
			fireStaminaChanged()
		end
	end)
	
	initialized = true
	print("[MovementController] Initialized")
end

--- 현재 스태미나 가져오기
function MovementController.getStamina(): (number, number)
	return currentStamina, maxStamina
end

--- 스프린트 중인지 확인
function MovementController.isSprinting(): boolean
	return isSprinting
end

--- 구르기 중인지 확인
function MovementController.isDodging(): boolean
	return isDodging
end

--- 스태미나 변경 이벤트 구독
function MovementController.onStaminaChanged(callback: (number, number) -> ())
	table.insert(staminaChangedCallbacks, callback)
end

--- 구르기 이벤트 구독
function MovementController.onDodge(callback: (Vector3) -> ())
	table.insert(dodgeCallbacks, callback)
end

return MovementController
