-- Protocol.lua
-- 네트워크 프로토콜 정의

local Protocol = {}

-- RemoteFunction / RemoteEvent 이름 (고정)
Protocol.CMD_NAME = "NetCmd"
Protocol.EVT_NAME = "NetEvt"

-- 명령어 테이블
Protocol.Commands = {
	-- Net 기본 명령어
	["Net.Ping"] = true,
	["Net.Echo"] = true,
}

-- 에러 코드
Protocol.Errors = {
	NET_UNKNOWN_COMMAND = "NET_UNKNOWN_COMMAND",
	NET_INVALID_REQUEST = "NET_INVALID_REQUEST",
	NET_DUPLICATE_REQUEST = "NET_DUPLICATE_REQUEST",
}

return Protocol
