-- Protocol.lua
-- 네트워크 프로토콜 정의

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local Protocol = {}

-- RemoteFunction / RemoteEvent 이름 (고정)
Protocol.CMD_NAME = "NetCmd"
Protocol.EVT_NAME = "NetEvt"

-- 명령어 테이블
Protocol.Commands = {
	-- Net 기본 명령어
	["Net.Ping"] = true,
	["Net.Echo"] = true,
	
	-- Time 명령어
	["Time.Sync.Request"] = true,
	["Time.Warp"] = true,           -- 디버그용
	["Time.WarpToPhase"] = true,    -- 디버그용
	["Time.Debug"] = true,          -- 디버그용
}

-- 에러 코드는 Enums.ErrorCode 사용
Protocol.Errors = Enums.ErrorCode

return Protocol
