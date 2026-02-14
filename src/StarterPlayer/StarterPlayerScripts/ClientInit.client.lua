-- ClientInit.client.lua
-- 클라이언트 초기화 스크립트

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")

local NetClient = require(Client.NetClient)

-- NetClient 초기화
local success = NetClient.Init()

if success then
	-- 테스트: Ping
	local pingOk, pingResult = NetClient.Ping()
	print("[ClientInit] Ping:", pingOk, pingResult and pingResult.ok)
	
	-- 테스트: Echo
	local echoOk, echoResult = NetClient.Echo("Hello")
	print("[ClientInit] Echo:", echoOk, echoResult and echoResult.text)
	
	-- WorldDropController 초기화 (이벤트 소비자)
	local WorldDropController = require(Controllers.WorldDropController)
	WorldDropController.Init()
	
	-- InventoryController 초기화 (이벤트 소비자)
	local InventoryController = require(Controllers.InventoryController)
	InventoryController.Init()
	
	-- TimeController 초기화 (이벤트 소비자)
	local TimeController = require(Controllers.TimeController)
	TimeController.Init()
end

print("[ClientInit] Client initialized")
