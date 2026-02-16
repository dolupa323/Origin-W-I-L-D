-- InputManager.lua
-- 입력 처리 모듈 (키 바인딩, 마우스 입력)

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local InputManager = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 키 바인딩 콜백
local keyCallbacks = {}  -- [keyCode] = { callback, name }
local mouseCallbacks = {
	leftClick = nil,
	rightClick = nil,
}

-- 상태
local isUIOpen = false  -- UI 열림 상태 (게임 입력 차단용)

--========================================
-- Public API: State
--========================================

function InputManager.setUIOpen(open: boolean)
	isUIOpen = open
end

function InputManager.isUIOpen(): boolean
	return isUIOpen
end

--========================================
-- Public API: Key Binding
--========================================

--- 키 바인딩 등록
function InputManager.bindKey(keyCode: Enum.KeyCode, name: string, callback: () -> ())
	keyCallbacks[keyCode] = {
		callback = callback,
		name = name,
	}
end

--- 키 바인딩 해제
function InputManager.unbindKey(keyCode: Enum.KeyCode)
	keyCallbacks[keyCode] = nil
end

--========================================
-- Public API: Mouse Binding
--========================================

--- 좌클릭 콜백 등록
function InputManager.onLeftClick(callback: (Vector3?) -> ())
	mouseCallbacks.leftClick = callback
end

--- 우클릭 콜백 등록
function InputManager.onRightClick(callback: (Vector3?) -> ())
	mouseCallbacks.rightClick = callback
end

--========================================
-- Internal: Input Handling
--========================================

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	-- 키보드 입력 (채팅 등 UI 입력 처리 중이면 무시)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if gameProcessed then return end
		local binding = keyCallbacks[input.KeyCode]
		if binding then
			binding.callback()
		end
	end
	
	-- 마우스 입력 (gameProcessed 무시 - 기본 클릭도 처리)
	if not isUIOpen then
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- 좌클릭
			if mouseCallbacks.leftClick then
				local mouse = player:GetMouse()
				local hitPos = mouse.Hit and mouse.Hit.Position
				mouseCallbacks.leftClick(hitPos)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- 우클릭
			if mouseCallbacks.rightClick then
				local mouse = player:GetMouse()
				local hitPos = mouse.Hit and mouse.Hit.Position
				mouseCallbacks.rightClick(hitPos)
			end
		end
	end
end

--========================================
-- Raycast Utility
--========================================

--- 마우스 위치에서 레이캐스트
function InputManager.raycastFromMouse(filterInstances: {Instance}?, maxDistance: number?): (Instance?, Vector3?, Vector3?)
	local mouse = player:GetMouse()
	local camera = workspace.CurrentCamera
	
	if not camera then return nil, nil, nil end
	
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local distance = maxDistance or 100
	
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filterInstances or { player.Character }
	
	local result = workspace:Raycast(ray.Origin, ray.Direction * distance, params)
	
	if result then
		return result.Instance, result.Position, result.Normal
	end
	
	return nil, nil, nil
end

--- 마우스 타겟 가져오기
function InputManager.getMouseTarget(): Instance?
	local mouse = player:GetMouse()
	return mouse.Target
end

--========================================
-- Initialization
--========================================

function InputManager.Init()
	if initialized then
		warn("[InputManager] Already initialized!")
		return
	end
	
	UserInputService.InputBegan:Connect(onInputBegan)
	
	initialized = true
	print("[InputManager] Initialized")
end

return InputManager
