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
-- 월드 / 맵 설정
--========================================
Balance.MAP_EXTENT = 2500          -- 초기 스폰 시 탐색할 맵 최대 범위 (스터드, 1500 -> 2500)
Balance.SEA_LEVEL = 10              -- 해수면 높이 (이보다 낮으면 바다, 0 -> 10)

--========================================
-- 야생동물 / 크리처
--========================================
Balance.WILDLIFE_CAP = 300         -- 서버 전체 야생동물 최대 수
Balance.CREATURE_COOLDOWN = 600    -- 크리처 리스폰 쿨다운 (초)
Balance.INITIAL_CREATURE_COUNT = 80 -- 서버 시작 시 초기 스폰 크리처 수 (30->80)
Balance.CREATURE_REPLENISH_INTERVAL = 45 -- 보충 스폰 간격 (초)

--========================================
-- 자원 노드 (Resource Nodes)
--========================================
Balance.RESOURCE_NODE_CAP = 250    -- 서버 전체 자동 스폰 자원 노드 최대 수
Balance.NODE_SPAWN_INTERVAL = 20   -- 자원 노드 보충 스폰 간격 (초)
Balance.NODE_DESPAWN_DIST = 150    -- 자원 노드 디스폰 거리
Balance.INITIAL_NODE_COUNT = 150   -- 서버 시작 시 초기 스폰 노드 수 (60->150)

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

--========================================
-- 제작 (Craft)
--========================================
Balance.CRAFT_RANGE = 10               -- 시설 제작 가능 거리 (스터드)
Balance.CRAFT_QUEUE_MAX = 5            -- 플레이어 동시 제작 큐 최대 크기
Balance.CRAFT_CANCEL_REFUND = 1.0      -- 취소 시 재료 환불 비율 (1.0 = 전액)

--========================================
-- 팰 (Pal) 시스템 (Phase 5)
--========================================
Balance.MAX_PALBOX = 30                -- 팰 보관함 최대 수
Balance.MAX_PARTY = 5                  -- 파티 최대 슬롯
Balance.PAL_FOLLOW_DIST = 4            -- 팰이 주인과 유지하는 거리 (스터드)
Balance.PAL_COMBAT_RANGE = 15          -- 팰이 전투를 시작하는 감지 범위 (스터드)
Balance.CAPTURE_RANGE = 30             -- 기본 포획 사거리 (스터드)

--========================================
-- 플레이어 레벨 & 경험치 (Phase 6)
--========================================
Balance.PLAYER_MAX_LEVEL = 50          -- 최대 레벨
Balance.BASE_XP_PER_LEVEL = 100        -- 레벨 1→2 필요 XP
Balance.XP_SCALING = 1.2               -- 레벨당 필요 XP 증가율
Balance.TECH_POINTS_PER_LEVEL = 2      -- 레벨업당 기술 포인트 지급

--========================================
-- XP 획득량 (Phase 6)
--========================================
Balance.XP_CREATURE_KILL = 25          -- 크리처 처치
Balance.XP_CRAFT_ITEM = 5              -- 아이템 제작
Balance.XP_CAPTURE_PAL = 50            -- 팰 포획 성공
Balance.XP_HARVEST_RESOURCE = 2        -- 자원 채집

--========================================
-- 플레이어 스탯 보너스 (Phase 6)
--========================================
Balance.STAT_BONUS_PER_LEVEL = 0.02    -- 레벨당 스탯 보너스 (2%)

--========================================
-- 스태미나 & 이동 시스템 (Phase 10)
--========================================
Balance.STAMINA_MAX = 100              -- 최대 스태미나
Balance.STAMINA_REGEN = 8              -- 초당 스태미나 회복량
Balance.STAMINA_REGEN_DELAY = 1.5      -- 스태미나 사용 후 회복 시작 딜레이 (초)

-- 스프린트 (빠르게 달리기)
Balance.SPRINT_SPEED_MULT = 2.0        -- 스프린트 속도 배율 (기본 1.6 → 2.0)
Balance.SPRINT_STAMINA_COST = 20       -- 초당 스태미나 소모 (기본 12 → 20)
Balance.SPRINT_MIN_STAMINA = 10        -- 스프린트 시작 최소 스태미나

-- 구르기 (회피)
Balance.DODGE_STAMINA_COST = 25        -- 구르기 1회 스태미나 소모
Balance.DODGE_COOLDOWN = 0.8           -- 구르기 쿨다운 (초)
Balance.DODGE_DISTANCE = 12            -- 구르기 이동 거리 (스터드)
Balance.DODGE_DURATION = 0.4           -- 구르기 소요 시간 (초)
Balance.DODGE_IFRAMES = 0.25           -- 무적 프레임 지속 시간 (초)
--========================================
-- 수확 시스템 (Phase 7)
--========================================
Balance.HARVEST_COOLDOWN = 0.5         -- 연속 타격 카다운 (초)
Balance.HARVEST_RANGE = 12             -- 수확 가능 거리 (스터드) — 기본 8 → 12 확대
Balance.HARVEST_XP_PER_HIT = 2         -- 타격당 XP

-- 채집 홀드 시스템 (E키 꿉 누르기)
Balance.HARVEST_HOLD_TIME_BASE = 2.0   -- 기본 채집 시간 (초, 맨손 기준)
Balance.HARVEST_HOLD_TIME_OPTIMAL = 0.8 -- 최적 도구 사용 시 채집 시간 (초)
Balance.HARVEST_EFFICIENCY_BAREHAND = 0.5 -- 맨손 효율 (자원 획득량 배율)
Balance.HARVEST_EFFICIENCY_WRONG_TOOL = 0.7 -- 맞지 않는 도구 효율
Balance.HARVEST_EFFICIENCY_OPTIMAL = 1.2 -- 최적 도구 효율

--========================================
-- 베이스 시스템 (Phase 7)
--========================================
Balance.BASE_DEFAULT_RADIUS = 30       -- 기본 베이스 반경
Balance.BASE_MAX_RADIUS = 100          -- 최대 베이스 반경
Balance.BASE_RADIUS_PER_LEVEL = 10     -- 레벨당 추가 반경
Balance.BASE_MAX_PER_PLAYER = 1        -- 플레이어당 최대 베이스 수

--========================================
-- 자동화 시스템 (Phase 7)
--========================================
Balance.AUTO_HARVEST_INTERVAL = 10     -- 팸 자동 수확 간격 (초)
Balance.AUTO_DEPOSIT_INTERVAL = 5      -- 자동 저장 간격 (초)
Balance.AUTO_DEPOSIT_RANGE = 20        -- Storage 검색 범위 (스터드)

--========================================
-- 퀘스트 시스템 (Phase 8)
--========================================
Balance.QUEST_MAX_ACTIVE = 10          -- 동시 진행 가능 퀘스트 수
Balance.QUEST_DAILY_RESET_HOUR = 0     -- 일일 퀘스트 리셋 시간 (UTC)
Balance.QUEST_ABANDON_COOLDOWN = 60    -- 퀘스트 포기 후 재수락 쿨다운 (초)

--========================================
-- NPC 상점 시스템 (Phase 9)
--========================================
Balance.SHOP_INTERACT_RANGE = 10       -- NPC 상점 상호작용 최대 거리 (스터드)
Balance.SHOP_DEFAULT_SELL_MULT = 0.5   -- 기본 판매 배율 (구매가의 50%)
Balance.SHOP_RESTOCK_TIME = 300        -- 재고 리필 시간 (초)
Balance.STARTING_GOLD = 100            -- 신규 플레이어 기본 골드
Balance.GOLD_CAP = 999999              -- 최대 보유 가능 골드
Balance.GOLD_EARN_MULTIPLIER = 1.0     -- 골드 획득 배율 (이벤트용)

-- 테이블 동결 (런타임 수정 방지)
table.freeze(Balance)

return Balance
