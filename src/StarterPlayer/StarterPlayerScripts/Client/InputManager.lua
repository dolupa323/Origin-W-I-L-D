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
local keyHoldCallbacks = {}  -- [keyCode] = { onPress, onRelease, name }
local mouseCallbacks = {
	leftClick = {},  -- { [name] = callback }
	rightClick = {}, -- { [name] = callback }
}
local leftClickOrder = {} -- 리스트로 순서 관리
local rightClickOrder = {}

-- 현재 누르고 있는 키 상태
local heldKeys = {}  -- [keyCode] = true/false

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

--- 키 홀드 바인딩 등록 (누름/뗌 시점 모두 콜백)
function InputManager.bindKeyHold(keyCode: Enum.KeyCode, name: string, onPress: () -> (), onRelease: () -> ())
	keyHoldCallbacks[keyCode] = {
		onPress = onPress,
		onRelease = onRelease,
		name = name,
	}
end

--- 키 홀드 바인딩 해제
function InputManager.unbindKeyHold(keyCode: Enum.KeyCode)
	keyHoldCallbacks[keyCode] = nil
end

--- 특정 키가 현재 눌려있는지 확인
function InputManager.isKeyHeld(keyCode: Enum.KeyCode): boolean
	return heldKeys[keyCode] == true
end

--========================================
-- Public API: Mouse Binding
--========================================

--- 좌클릭 콜백 등록 (레이어드 지원)
function InputManager.onLeftClick(name: string, callback: (Vector3?) -> ())
	if not callback then
		InputManager.unbindLeftClick(name)
		return
	end
	
	mouseCallbacks.leftClick[name] = callback
	
	-- 순서 관리 (이미 있으면 제거 후 끝으로)
	for i, n in ipairs(leftClickOrder) do
		if n == name then
			table.remove(leftClickOrder, i)
			break
		end
	end
	table.insert(leftClickOrder, name)
end

function InputManager.unbindLeftClick(name: string)
	mouseCallbacks.leftClick[name] = nil
	for i, n in ipairs(leftClickOrder) do
		if n == name then
			table.remove(leftClickOrder, i)
			break
		end
	end
end

--- 우클릭 콜백 등록
function InputManager.onRightClick(name: string, callback: (Vector3?) -> ())
	if not callback then
		InputManager.unbindRightClick(name)
		return
	end
	
	mouseCallbacks.rightClick[name] = callback
	
	for i, n in ipairs(rightClickOrder) do
		if n == name then
			table.remove(rightClickOrder, i)
			break
		end
	end
	table.insert(rightClickOrder, name)
end

function InputManager.unbindRightClick(name: string)
	mouseCallbacks.rightClick[name] = nil
	for i, n in ipairs(rightClickOrder) do
		if n == name then
			table.remove(rightClickOrder, i)
			break
		end
	end
end

--========================================
-- Internal: Input Handling
--========================================

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	-- 키보드 입력 (채팅 등 UI 입력 처리 중이면 무시)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if gameProcessed then return end
		
		-- 키 홀드 상태 업데이트
		heldKeys[input.KeyCode] = true
		
		-- 일반 키 콜백
		local binding = keyCallbacks[input.KeyCode]
		if binding then
			binding.callback()
		end
		
		-- 키 홀드 콜백 (눌림)
		local holdBinding = keyHoldCallbacks[input.KeyCode]
		if holdBinding and holdBinding.onPress then
			holdBinding.onPress()
		end
	end
	
	-- 마우스 입력 (gameProcessed 무시 - 기본 클릭도 처리)
	if not isUIOpen then
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			-- 좌클릭/터치 (최신/가장 높은 레이어부터 호출)
			if #leftClickOrder > 0 then
				local name = leftClickOrder[#leftClickOrder]
				local callback = mouseCallbacks.leftClick[name]
				if callback then
					-- 터치 시에도 히트 위치 계산 (Raycast 유틸 활용 가능)
					local hitPos = nil
					if input.UserInputType == Enum.UserInputType.Touch then
						local pos = input.Position
						hitPos = InputManager.getTouchWorldPosition(pos.X, pos.Y)
					else
						local mouse = player:GetMouse()
						hitPos = mouse.Hit and mouse.Hit.Position
					end
					callback(hitPos)
				end
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- 우클릭
			if #rightClickOrder > 0 then
				local name = rightClickOrder[#rightClickOrder]
				local callback = mouseCallbacks.rightClick[name]
				if callback then
					local mouse = player:GetMouse()
					local hitPos = mouse.Hit and mouse.Hit.Position
					callback(hitPos)
				end
			end
		end
	end
end

local function onInputEnded(input: InputObject, gameProcessed: boolean)
	-- 키보드 입력
	if input.UserInputType == Enum.UserInputType.Keyboard then
		-- 키 홀드 상태 업데이트
		heldKeys[input.KeyCode] = false
		
		-- 키 홀드 콜백 (뗌)
		local holdBinding = keyHoldCallbacks[input.KeyCode]
		if holdBinding and holdBinding.onRelease then
			holdBinding.onRelease()
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

--- 터치 위치의 월드 좌표 가져오기
function InputManager.getTouchWorldPosition(x: number, y: number): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	
	local ray = camera:ViewportPointToRay(x, y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return result and result.Position or (ray.Origin + ray.Direction * 10)
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
	UserInputService.InputEnded:Connect(onInputEnded)
	
	initialized = true
	print("[InputManager] Initialized")
end

return InputManager
