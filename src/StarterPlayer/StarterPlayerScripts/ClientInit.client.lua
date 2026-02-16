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
	-- WorldDropController 초기화 (이벤트 소비자)
	local WorldDropController = require(Controllers.WorldDropController)
	WorldDropController.Init()
	
	-- InventoryController 초기화 (이벤트 소비자)
	local InventoryController = require(Controllers.InventoryController)
	InventoryController.Init()
	
	-- TimeController 초기화 (이벤트 소비자)
	local TimeController = require(Controllers.TimeController)
	TimeController.Init()
	
	-- StorageController 초기화 (이벤트 소비자)
	local StorageController = require(Controllers.StorageController)
	StorageController.Init()
	
	-- BuildController 초기화 (이벤트 소비자)
	local BuildController = require(Controllers.BuildController)
	BuildController.Init()
	
	-- CraftController 초기화 (이벤트 소비자)
	local CraftController = require(Controllers.CraftController)
	CraftController.Init()
	
	-- FacilityController 초기화 (이벤트 소비자)
	local FacilityController = require(Controllers.FacilityController)
	FacilityController.Init()
end

print("[ClientInit] Client initialized")
