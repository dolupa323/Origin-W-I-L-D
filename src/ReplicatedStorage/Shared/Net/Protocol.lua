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
	
	-- Save 명령어
	["Save.Now"] = true,            -- 디버그/어드민용
	["Save.Status"] = true,
	
	-- Inventory 명령어
	["Inventory.Move.Request"] = true,
	["Inventory.Split.Request"] = true,
	["Inventory.Drop.Request"] = true,
	["Inventory.Get.Request"] = true,      -- 전체 인벤 조회
	["Inventory.GiveItem"] = true,         -- 디버그용
	
	-- WorldDrop 명령어
	["WorldDrop.Loot.Request"] = true,
	
	-- Storage 명령어
	["Storage.Open.Request"] = true,
	["Storage.Close.Request"] = true,
	["Storage.Move.Request"] = true,
	
	-- Build 명령어
	["Build.Place.Request"] = true,     -- 시설물 배치 요청
	["Build.Remove.Request"] = true,    -- 시설물 해체 요청
	["Build.GetAll.Request"] = true,    -- 전체 시설물 조회
	
	-- Craft 명령어
	["Craft.Start.Request"] = true,     -- 제작 시작 요청
	["Craft.Cancel.Request"] = true,    -- 제작 취소 요청
	["Craft.Collect.Request"] = true,   -- 완성품 수거 요청
	["Craft.GetQueue.Request"] = true,  -- 제작 큐 조회
	
	-- Facility 명령어
	["Facility.GetInfo.Request"] = true,       -- 시설 정보 조회 (Lazy Update 트리거)
	["Facility.AddFuel.Request"] = true,       -- 연료 투입
	["Facility.AddInput.Request"] = true,      -- 재료 투입 (Input 슬롯)
	["Facility.CollectOutput.Request"] = true, -- 산출물 수거 (Output 슬롯)
	
	-- Recipe 명령어
	["Recipe.GetInfo.Request"] = true,         -- 레시피 정보 조회 (효율 보정 포함)
	["Recipe.GetAll.Request"] = true,          -- 전체 해금 레시피 조회
}

-- 에러 코드는 Enums.ErrorCode 사용
Protocol.Errors = Enums.ErrorCode

return Protocol
