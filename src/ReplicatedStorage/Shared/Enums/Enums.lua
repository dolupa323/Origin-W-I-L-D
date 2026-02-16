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
	FARMING = "FARMING",       -- 농사 (화분)
	DEFENSE = "DEFENSE",       -- 방어 (벽, 문)
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

-- 테이블 동결
for key, subTable in pairs(Enums) do
	if type(subTable) == "table" then
		table.freeze(subTable)
	end
end
table.freeze(Enums)

return Enums
