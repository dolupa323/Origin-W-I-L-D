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
	["Facility.AssignPal.Request"] = true,     -- 팰 작업 배치 (Phase 5-5)
	["Facility.UnassignPal.Request"] = true,   -- 팰 작업 해제 (Phase 5-5)
	
	-- Recipe 명령어
	["Recipe.GetInfo.Request"] = true,         -- 레시피 정보 조회 (효율 보정 포함)
	["Recipe.GetAll.Request"] = true,          -- 전체 해금 레시피 조회
	
	-- Capture 명령어 (Phase 5-2)
	["Capture.Attempt.Request"] = true,        -- 포획 시도
	
	-- Combat 명령어 (Phase 3-3)
	["Combat.Hit.Request"] = true,             -- 전투 공격 요청
	
	-- Palbox 명령어 (Phase 5-3)
	["Palbox.List.Request"] = true,            -- 보관함 목록 조회
	["Palbox.Rename.Request"] = true,          -- 팰 닉네임 변경
	["Palbox.Release.Request"] = true,         -- 팰 해방 (삭제)
	
	-- Party 명령어 (Phase 5-4)
	["Party.List.Request"] = true,             -- 파티 목록 조회
	["Party.Add.Request"] = true,              -- 파티에 편성
	["Party.Remove.Request"] = true,           -- 파티에서 해제
	["Party.Summon.Request"] = true,           -- 팰 소환
	["Party.Recall.Request"] = true,           -- 팰 회수
	
	-- Player Stats 명령어 (Phase 6)
	["Player.Stats.Request"] = true,           -- 레벨/XP/포인트 조회
	
	-- Tech 명령어 (Phase 6)
	["Tech.Unlock.Request"] = true,            -- 기술 해금 요청
	["Tech.List.Request"] = true,              -- 해금된 기술 목록 조회
	["Tech.Tree.Request"] = true,              -- 전체 기술 트리 조회
	
	-- Harvest 명령어 (Phase 7)
	["Harvest.Hit.Request"] = true,            -- 자원 수확 타격
	["Harvest.GetNodes.Request"] = true,       -- 활성 노드 목록 조회
	
	-- Base 명령어 (Phase 7)
	["Base.Get.Request"] = true,               -- 베이스 정보 조회
	["Base.Expand.Request"] = true,            -- 베이스 확장
	
	-- Quest 명령어 (Phase 8)
	["Quest.List.Request"] = true,             -- 퀘스트 목록 요청
	["Quest.Accept.Request"] = true,           -- 퀘스트 수락
	["Quest.Claim.Request"] = true,            -- 보상 수령
	["Quest.Abandon.Request"] = true,          -- 퀘스트 포기
	
	-- Shop 명령어 (Phase 9)
	["Shop.List.Request"] = true,              -- 상점 목록 요청
	["Shop.GetInfo.Request"] = true,           -- 특정 상점 정보 조회
	["Shop.Buy.Request"] = true,               -- 아이템 구매
	["Shop.Sell.Request"] = true,              -- 아이템 판매
	["Shop.GetGold.Request"] = true,           -- 보유 골드 조회
}

-- 에러 코드는 Enums.ErrorCode 사용
Protocol.Errors = Enums.ErrorCode

return Protocol
