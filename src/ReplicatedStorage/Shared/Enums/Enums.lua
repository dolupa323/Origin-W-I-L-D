-- Enums.lua
-- 게임 전역 열거형 (동결)
-- 모든 상태/에러코드는 여기서만 정의. 문자열 하드코딩 금지.

local Enums = {}

--========================================
-- 로그 레벨
--========================================
Enums.LogLevel = {
	DEBUG = "DEBUG",
	INFO = "INFO",
	WARN = "WARN",
	ERROR = "ERROR",
}

--========================================
-- 에러 코드
--========================================
Enums.ErrorCode = {
	-- 성공
	OK = "OK",
	
	-- 네트워크 관련
	NET_UNKNOWN_COMMAND = "NET_UNKNOWN_COMMAND",
	NET_DUPLICATE_REQUEST = "NET_DUPLICATE_REQUEST",
	
	-- 요청 관련
	BAD_REQUEST = "BAD_REQUEST",
	OUT_OF_RANGE = "OUT_OF_RANGE",
	INVALID_STATE = "INVALID_STATE",
	NO_PERMISSION = "NO_PERMISSION",
	MISSING_REQUIREMENTS = "MISSING_REQUIREMENTS",
	COOLDOWN = "COOLDOWN",
	
	-- 인벤토리 관련
	INV_FULL = "INV_FULL",
	INVALID_SLOT = "INVALID_SLOT",
	SLOT_EMPTY = "SLOT_EMPTY",
	INVALID_COUNT = "INVALID_COUNT",
	NOT_STACKABLE = "NOT_STACKABLE",
	STACK_OVERFLOW = "STACK_OVERFLOW",
	SLOT_NOT_EMPTY = "SLOT_NOT_EMPTY",
	ITEM_MISMATCH = "ITEM_MISMATCH",
	INVALID_ITEM = "INVALID_ITEM",     -- 해당 작업에 사용할 수 없는 아이템
	
	-- 건설 관련
	COLLISION = "COLLISION",               -- 배치 위치 충돌
	INVALID_POSITION = "INVALID_POSITION", -- 유효하지 않은 위치
	STRUCTURE_CAP = "STRUCTURE_CAP",       -- 구조물 최대 개수 초과
	
	-- 제작 관련
	CRAFT_QUEUE_FULL = "CRAFT_QUEUE_FULL", -- 제작 큐 가득 참
	NO_FACILITY = "NO_FACILITY",           -- 필요 시설 없음/범위 밖
	CRAFT_NOT_FOUND = "CRAFT_NOT_FOUND",   -- 제작 항목 없음
	
	-- 일반
	NOT_FOUND = "NOT_FOUND",
	INTERNAL_ERROR = "INTERNAL_ERROR",
	NOT_SUPPORTED = "NOT_SUPPORTED",       -- 미지원 기능
	
	-- 포획/팰 관련 (Phase 5)
	PALBOX_FULL = "PALBOX_FULL",           -- 팰 보관함 가득 참
	PARTY_FULL = "PARTY_FULL",             -- 파티 가득 참
	NOT_CAPTURABLE = "NOT_CAPTURABLE",     -- 포획 불가 대상
	CAPTURE_FAILED = "CAPTURE_FAILED",     -- 포획 실패 (확률 탈락)
	PAL_ALREADY_ASSIGNED = "PAL_ALREADY_ASSIGNED", -- 이미 배치됨
	PAL_IN_PARTY = "PAL_IN_PARTY",         -- 파티 편성 중
	NO_CAPTURE_ITEM = "NO_CAPTURE_ITEM",   -- 포획 아이템 없음
	
	-- 기술/레벨 관련 (Phase 6)
	TECH_ALREADY_UNLOCKED = "TECH_ALREADY_UNLOCKED", -- 이미 해금됨
	TECH_NOT_FOUND = "TECH_NOT_FOUND",               -- 기술 없음
	INSUFFICIENT_TECH_POINTS = "INSUFFICIENT_TECH_POINTS", -- 기술 포인트 부족
	PREREQUISITES_NOT_MET = "PREREQUISITES_NOT_MET", -- 선행 기술 미해금
	RECIPE_LOCKED = "RECIPE_LOCKED",                 -- 레시피 미해금
	INSUFFICIENT_STAT_POINTS = "INSUFFICIENT_STAT_POINTS", -- 스탯 포인트 부족
	
	-- 수확/노드 관련 (Phase 7)
	NO_TOOL = "NO_TOOL",                             -- 도구 없음
	WRONG_TOOL = "WRONG_TOOL",                       -- 잘못된 도구
	NODE_DEPLETED = "NODE_DEPLETED",                 -- 노드 고갈됨
	NODE_NOT_FOUND = "NODE_NOT_FOUND",               -- 노드 없음
	
	-- 퀘스트 관련 (Phase 8)
	QUEST_NOT_FOUND = "QUEST_NOT_FOUND",             -- 퀘스트 없음
	QUEST_PREREQ_NOT_MET = "QUEST_PREREQ_NOT_MET",   -- 선행 퀘스트 미완료
	QUEST_LEVEL_NOT_MET = "QUEST_LEVEL_NOT_MET",     -- 필요 레벨 미충족
	QUEST_ALREADY_ACTIVE = "QUEST_ALREADY_ACTIVE",   -- 이미 진행 중
	QUEST_NOT_COMPLETED = "QUEST_NOT_COMPLETED",     -- 미완료 상태에서 보상 요청
	QUEST_ALREADY_CLAIMED = "QUEST_ALREADY_CLAIMED", -- 이미 보상 수령
	QUEST_MAX_ACTIVE = "QUEST_MAX_ACTIVE",           -- 동시 진행 한도 초과
	QUEST_NOT_REPEATABLE = "QUEST_NOT_REPEATABLE",   -- 비반복 퀘스트 재수락
	
	-- 상점 관련 (Phase 9)
	SHOP_NOT_FOUND = "SHOP_NOT_FOUND",               -- 상점 없음
	INSUFFICIENT_GOLD = "INSUFFICIENT_GOLD",         -- 골드 부족
	SHOP_OUT_OF_STOCK = "SHOP_OUT_OF_STOCK",         -- 재고 부족
	ITEM_NOT_IN_SHOP = "ITEM_NOT_IN_SHOP",           -- 상점에 해당 아이템 없음
	ITEM_NOT_SELLABLE = "ITEM_NOT_SELLABLE",         -- 판매 불가 아이템
	SHOP_TOO_FAR = "SHOP_TOO_FAR",                   -- 상점 거리 초과
	LEVEL_NOT_MET = "LEVEL_NOT_MET",                 -- 필요 레벨 미충족
	GOLD_CAP_REACHED = "GOLD_CAP_REACHED",           -- 골드 한도 도달
}

--========================================
-- 플레이어 스탯 ID
--========================================
Enums.StatId = {
	MAX_HEALTH = "MAX_HEALTH",     -- 최대 체력
	MAX_STAMINA = "MAX_STAMINA",   -- 최대 스태미나
	WEIGHT = "WEIGHT",             -- 소지 무게
	WORK_SPEED = "WORK_SPEED",     -- 작업 속도
	ATTACK = "ATTACK",             -- 공격력
}

--========================================
-- 시간 페이즈
--========================================
Enums.TimePhase = {
	DAY = "DAY",
	NIGHT = "NIGHT",
}

--========================================
-- 아이템 타입 (Phase 1-2에서 확장)
--========================================
Enums.ItemType = {
	RESOURCE = "RESOURCE",
	TOOL = "TOOL",
	WEAPON = "WEAPON",
	ARMOR = "ARMOR",
	CONSUMABLE = "CONSUMABLE",
	FOOD = "FOOD",
	PLACEABLE = "PLACEABLE",
	MISC = "MISC",
}

--========================================
-- 희귀도
--========================================
Enums.Rarity = {
	COMMON = "COMMON",
	UNCOMMON = "UNCOMMON",
	RARE = "RARE",
	EPIC = "EPIC",
	LEGENDARY = "LEGENDARY",
}

--========================================
-- 시설 기능 타입
--========================================
Enums.FacilityType = {
	COOKING = "COOKING",       -- 요리 (캠프파이어)
	STORAGE = "STORAGE",       -- 저장 (보관함)
	CRAFTING = "CRAFTING",     -- 제작 (작업대)
	RESPAWN = "RESPAWN",       -- 리스폰 (침낭)
	SMELTING = "SMELTING",     -- 제련 (용광로)
	FARMING = "FARMING",       -- 농사 (화분/농장)
	DEFENSE = "DEFENSE",       -- 방어 (함정 등)
	GATHERING = "GATHERING",   -- 채집 (자동화)
	BASE_CORE = "BASE_CORE",   -- 거점 핵심 (토템)
	FEEDING = "FEEDING",       -- 먹이 공급
	RESTING = "RESTING",       -- 휴식 및 회복
	BUILDING = "BUILDING",     -- 건축용 구조물 (벽, 바닥 등)
}

--========================================
-- 제작 상태
--========================================
Enums.CraftState = {
	IDLE = "IDLE",             -- 대기
	CRAFTING = "CRAFTING",     -- 제작 중
	COMPLETED = "COMPLETED",   -- 완료 (수거 대기)
	CANCELLED = "CANCELLED",   -- 취소됨
}

--========================================
-- 시설 가동 상태
--========================================
Enums.FacilityState = {
	IDLE = "IDLE",             -- 대기 (큐 없음)
	ACTIVE = "ACTIVE",         -- 가동 중 (연료+큐 있음)
	FULL = "FULL",             -- 출력 슬롯 가득 참
	NO_POWER = "NO_POWER",     -- 연료 없음
}

--========================================
-- 팰(Pal) 상태 (Phase 5)
--========================================
Enums.PalState = {
	STORED = "STORED",         -- 보관함에 저장
	IN_PARTY = "IN_PARTY",     -- 파티에 편성 (미소환)
	SUMMONED = "SUMMONED",     -- 월드에 소환됨
	WORKING = "WORKING",       -- 시설에서 작업 중
}

--========================================
-- XP 획득 원천 (Phase 6)
--========================================
Enums.XPSource = {
	CREATURE_KILL = "CREATURE_KILL",     -- 크리처 처치
	CRAFT_ITEM = "CRAFT_ITEM",           -- 아이템 제작
	CAPTURE_PAL = "CAPTURE_PAL",         -- 팰 포획
	HARVEST_RESOURCE = "HARVEST_RESOURCE", -- 자원 채집
}

--========================================
-- 기술 카테고리 (Phase 6)
--========================================
Enums.TechCategory = {
	BASICS = "BASICS",           -- 기초
	TOOLS = "TOOLS",             -- 도구
	WEAPONS = "WEAPONS",         -- 무기
	ARMOR = "ARMOR",             -- 방어구
	STRUCTURES = "STRUCTURES",   -- 구조물
	FACILITIES = "FACILITIES",   -- 시설
	CRAFTING = "CRAFTING",       -- 제작
	PAL = "PAL",                 -- 팰 관련
}
--========================================
-- 자원 노드 타입 (Phase 7)
--========================================
Enums.NodeType = {
	TREE = "TREE",               -- 나무
	ROCK = "ROCK",               -- 바위
	BUSH = "BUSH",               -- 덤불
	FIBER = "FIBER",             -- 섬유/풀
	ORE = "ORE",                 -- 광석
}

-- (Quest 시스템 삭제됨)

-- 테이블 동결
for key, subTable in pairs(Enums) do
	if type(subTable) == "table" then
		table.freeze(subTable)
	end
end
table.freeze(Enums)

return Enums
