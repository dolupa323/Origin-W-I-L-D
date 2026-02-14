-- Balance.lua
-- 게임 밸런스 상수 (동결 - 단일 진실)
-- 이 파일의 값만 참조할 것. 매직 넘버 금지.

local Balance = {}

--========================================
-- 시간 시스템
--========================================
Balance.DAY_LENGTH = 2400          -- 하루 총 길이 (초 단위 게임 시간)
Balance.DAY_DURATION = 1800        -- 낮 지속 시간 (초)
Balance.NIGHT_DURATION = 600       -- 밤 지속 시간 (초)

--========================================
-- 인벤토리
--========================================
Balance.INV_SLOTS = 20             -- 인벤토리 슬롯 수
Balance.MAX_STACK = 99             -- 최대 스택 수량

--========================================
-- 창고 (Storage)
--========================================
Balance.STORAGE_SLOTS = 20         -- 창고 슬롯 수 (INV_SLOTS와 동일)

--========================================
-- 월드 드롭
--========================================
Balance.DROP_CAP = 400             -- 서버 전체 드롭 아이템 최대 개수
Balance.DROP_MERGE_RADIUS = 5      -- 드롭 병합 반경 (스터드)
Balance.DROP_INACTIVE_DIST = 150   -- 비활성화 거리 (스터드)
Balance.DROP_DESPAWN_DEFAULT = 300 -- 기본 디스폰 시간 (초)
Balance.DROP_DESPAWN_GATHER = 600  -- 채집 드롭 디스폰 시간 (초)
Balance.DROP_LOOT_RANGE = 10       -- 루팅 최대 거리 (스터드)

--========================================
-- 야생동물 / 크리처
--========================================
Balance.WILDLIFE_CAP = 250         -- 서버 전체 야생동물 최대 수
Balance.CREATURE_COOLDOWN = 600    -- 크리처 리스폰 쿨다운 (초)

--========================================
-- 시설
--========================================
Balance.FACILITY_QUEUE_MAX = 10    -- 시설 대기열 최대 크기
Balance.FACILITY_ACTIVE_CAP = 15   -- 동시 활성 시설 최대 수

--========================================
-- 건축 (Build)
--========================================
Balance.BUILD_STRUCTURE_CAP = 500    -- 서버 전체 구조물 최대 수
Balance.BUILD_RANGE = 20             -- 플레이어 건축 가능 거리 (스터드)
Balance.BUILD_MIN_GROUND_DIST = 0.5  -- 지면 최소 거리 (스터드)
Balance.BUILD_COLLISION_RADIUS = 2   -- 기본 충돌 체크 반경 (스터드)

-- 테이블 동결 (런타임 수정 방지)
table.freeze(Balance)

return Balance
