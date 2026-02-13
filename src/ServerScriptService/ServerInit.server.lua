-- ServerInit.server.lua
-- 서버 초기화 스크립트

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")

-- NetController 초기화
local NetController = require(Controllers.NetController)
NetController.Init()

print("[ServerInit] Server initialized")
