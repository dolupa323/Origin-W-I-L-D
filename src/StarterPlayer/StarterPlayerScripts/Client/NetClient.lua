-- NetClient.lua
-- 클라이언트 네트워크 모듈

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Protocol = require(Shared.Net.Protocol)

local NetClient = {}

-- Remote 인스턴스
local Cmd: RemoteFunction
local Evt: RemoteEvent

-- 이벤트 리스너 테이블
local eventListeners = {}

-- requestId 생성
local function generateRequestId(): string
	return HttpService:GenerateGUID(false)
end

-- 서버에 요청 전송 (request 메서드 추가)
function NetClient.request(command: string, payload: any?): (boolean, any)
	return NetClient.Request(command, payload)
end

-- 서버에 요청 전송
function NetClient.Request(command: string, payload: any?): (boolean, any)
	if not Cmd then
		return false, "NOT_INITIALIZED"
	end
	
	local requestId = generateRequestId()
	
	-- 타임아웃 처리 (UI 프리징 방지)
	local thread = coroutine.running()
	local completed = false
	local timeoutSeconds = 5
	
	task.delay(timeoutSeconds, function()
		if not completed then
			completed = true
			task.spawn(thread, false, "TIMEOUT")
		end
	end)
	
	task.spawn(function()
		local success, responseValue = pcall(function()
			local compressedPayload = Protocol.Compress(payload or {})
			local requestData = {
				command = command,
				requestId = requestId,
				payload = compressedPayload,
			}
			return Cmd:InvokeServer(requestData)
		end)
		
		if not completed then
			completed = true
			task.spawn(thread, success, responseValue)
		end
	end)
	
	local success, response = coroutine.yield()
	
	if not success then
		if response == "TIMEOUT" then
			warn("[NetClient] Request timeout:", command)
			-- UI 프리징 해제 및 알림 (Circular Dependency 방지를 위해 지연 require)
			task.spawn(function()
				local UIManager = require(script.Parent.UIManager)
				if UIManager then
					if UIManager.hideAllLoading then
						UIManager.hideAllLoading()
					end
					if UIManager.notify then
						UIManager.notify("서버 응답이 지연되고 있습니다.", Color3.fromRGB(255, 100, 100))
					end
				end
			end)
			return false, "TIMEOUT"
		end
		warn("[NetClient] Request failed:", response)
		return false, "NETWORK_ERROR"
	end
	
	if type(response) ~= "table" then
		return false, "INVALID_RESPONSE"
	end
	
	if response.success then
		local decompressedData = Protocol.Decompress(response.data)
		return true, decompressedData
	else
		return false, response.error
	end
end

-- Ping 요청
function NetClient.Ping(): (boolean, any)
	return NetClient.Request("Net.Ping", {})
end

-- Echo 요청
function NetClient.Echo(text: string): (boolean, any)
	return NetClient.Request("Net.Echo", { text = text })
end

-- 이벤트 리스너 등록
function NetClient.On(eventName: string, callback: (any) -> ())
	if not eventListeners[eventName] then
		eventListeners[eventName] = {}
	end
	table.insert(eventListeners[eventName], callback)
end

-- 이벤트 리스너 해제
function NetClient.Off(eventName: string, callback: (any) -> ())
	local listeners = eventListeners[eventName]
	if not listeners then return end
	
	for i, cb in ipairs(listeners) do
		if cb == callback then
			table.remove(listeners, i)
			break
		end
	end
end

-- 서버 이벤트 수신 처리
local function onClientEvent(data)
	if type(data) ~= "table" then return end
	
	local eventName = data.event
	local eventData = Protocol.Decompress(data.data)
	
	local listeners = eventListeners[eventName]
	if not listeners then return end
	
	for _, callback in ipairs(listeners) do
		task.spawn(callback, eventData)
	end
end

-- 초기화
function NetClient.Init()
	-- RemoteFunction 대기
	Cmd = ReplicatedStorage:WaitForChild(Protocol.CMD_NAME, 10)
	if not Cmd then
		warn("[NetClient] Failed to find RemoteFunction:", Protocol.CMD_NAME)
		return false
	end
	
	-- RemoteEvent 대기
	Evt = ReplicatedStorage:WaitForChild(Protocol.EVT_NAME, 10)
	if not Evt then
		warn("[NetClient] Failed to find RemoteEvent:", Protocol.EVT_NAME)
		return false
	end
	
	-- 이벤트 연결
	Evt.OnClientEvent:Connect(onClientEvent)
	
	print("[NetClient] Initialized")
	return true
end

return NetClient
