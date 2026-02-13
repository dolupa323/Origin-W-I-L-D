-- ServerInit.server.lua
-- 서버 초기화 스크립트

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local Services = Server:WaitForChild("Services")

-- NetController 초기화 (가장 먼저)
local NetController = require(Controllers.NetController)
NetController.Init()

-- TimeService 초기화
local TimeService = require(Services.TimeService)
TimeService.Init(NetController)

-- TimeService 핸들러 등록
for command, handler in pairs(TimeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

print("[ServerInit] Server initialized")
