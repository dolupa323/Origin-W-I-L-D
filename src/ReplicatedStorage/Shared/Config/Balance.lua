-- Balance.lua
-- 게임 밸런스 상수 (동결 - 단일 진실)
-- 이 파일의 값만 참조할 것. 매직 넘버 금지.

local Balance = {}

--========================================
-- 시간 시스템
--========================================
Balance.DAY_LENGTH = 960           -- 하루 총 길이 (초, 16분)
Balance.DAY_DURATION = 640         -- 낮 지속 시간 (초, 10.67분)
Balance.NIGHT_DURATION = 320       -- 밤 지속 시간 (초, 5.33분)

--========================================
-- 인벤토리
--========================================
Balance.INV_SLOTS = 60             -- 기본 인벤토리 슬롯 수
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
Balance.DROP_LOOT_RANGE = 14       -- [상향] 루팅 최대 거리 (10 -> 14)

--========================================
-- 월드 / 맵 설정
--========================================
Balance.MAP_EXTENT = 2500          -- 초기 스폰 시 탐색할 맵 최대 범위 (스터드, 1500 -> 2500)
Balance.SEA_LEVEL = 2              -- 해수면 높이 (0 -> 2)

--========================================
-- 야생동물 / 크리처
--========================================
Balance.WILDLIFE_CAP = 400         -- 서버 전체 야생동물 최대 수
Balance.CREATURE_COOLDOWN = 600    -- 크리처 리스폰 쿨다운 (초)
Balance.INITIAL_CREATURE_COUNT = 160 -- 서버 시작 시 초기 스폰 크리처 수 (Zone당 80마리)
Balance.CREATURE_REPLENISH_INTERVAL = 60 -- 보충 스폰 간격 (초) (45 -> 60)

--========================================
-- 자원 노드 (Resource Nodes)
--========================================
Balance.RESOURCE_NODE_CAP = 600    -- 서버 전체 자원 노드 최대 수
Balance.NODE_SPAWN_INTERVAL = 5   -- 자원 노드 보충 스폰 간격 (초)
Balance.NODE_DESPAWN_DIST = 500    -- 자원 노드 디스폰 거리 (멀리서도 유지)
Balance.INITIAL_NODE_COUNT = 400   -- 서버 시작 시 초기 스폰 노드 수

--========================================
-- 시설
--========================================
Balance.FACILITY_QUEUE_MAX = 10    -- 시설 대기열 최대 크기
Balance.FACILITY_ACTIVE_CAP = 15   -- 동시 활성 시설 최대 수
Balance.MAX_FACILITY_OUTPUT = 1000 -- 시설 Output 슬롯 최대 아이템 개수
Balance.FACILITY_WORK_HP_LOSS = 0.1   -- 작업 1회당 시설 내구도 소모
Balance.FACILITY_PASSIVE_DECAY_TICK = 5 -- 시설 자연 내구도 감소 적용 주기(초)

--========================================
-- 건축 (Build)
--========================================
Balance.BUILD_STRUCTURE_CAP = 500    -- 서버 전체 구조물 최대 수
Balance.BUILD_RANGE = 20             -- 플레이어 건축 가능 거리 (스터드)
Balance.BUILD_MIN_GROUND_DIST = 0.5  -- 지면 최소 거리 (스터드)
Balance.BUILD_COLLISION_RADIUS = 2   -- 기본 충돌 체크 반경 (스터드)
Balance.BUILD_PLACEMENT_PROFILE = "STRICT_FIELD" -- DEFAULT | STRICT_FIELD
Balance.BUILD_MAX_GROUND_SLOPE_DEG = 42      -- 일반 공간의 허용 경사
Balance.BUILD_STRICT_MAX_GROUND_SLOPE_DEG = 12 -- 엄격 모드 허용 경사
Balance.BUILD_MAX_GROUND_GAP = 3.5           -- 일반 공간 지면 오차 허용
Balance.BUILD_STRICT_MAX_GROUND_GAP = 1.2    -- 엄격 모드 지면 오차 허용

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

-- 팰 유지비 (Maintenance)
Balance.PAL_HUNGER_MAX = 100           -- 팰 최대 배고픔
Balance.PAL_SAN_MAX = 100              -- 팰 최대 정신력(SAN)
Balance.PAL_WORK_HUNGER_COST = 2.0     -- 작업 1회당 배고픔 소모
Balance.PAL_WORK_SAN_COST = 1.0        -- 작업 1회당 정신력 소모
Balance.PAL_MIN_WORK_HUNGER = 15       -- 작업 가능 최소 배고픔
Balance.PAL_MIN_WORK_SAN = 20          -- 작업 가능 최소 정신력

--========================================
-- 플레이어 레벨 & 경험치 (Phase 6)
--========================================
Balance.PLAYER_MAX_LEVEL = 50          -- 최대 레벨
Balance.BASE_XP_PER_LEVEL = 100        -- 레벨 1→2 필요 XP
Balance.XP_SCALING = 1.2               -- 레벨당 필요 XP 증가율
Balance.TECH_POINTS_PER_LEVEL = 3      -- 레벨업당 기술 포인트 지급 (2~3)
Balance.STAT_POINTS_PER_LEVEL = 3      -- 레벨업당 스탯 포인트 지급
Balance.SKILL_POINTS_PER_LEVEL = 1     -- 레벨업당 스킬 포인트 지급 (택1 전투계열)

--========================================
-- XP 획득량 (Phase 6 - 개발용 폭발적 상향)
--========================================
Balance.XP_CREATURE_KILL = 200000        -- 크리처 처치 (10000 -> 200000)
Balance.XP_CRAFT_ITEM = 50000          -- 아이템 제작 (2000 -> 50000)
Balance.XP_CAPTURE_PAL = 500000         -- 팰 포획 성공 (20000 -> 500000)
Balance.XP_HARVEST_RESOURCE = 1000000     -- 자원 채집 (100000 -> 1000000)
Balance.XP_BUILD = 30                  -- 구조물 배치 보상 XP

--========================================
-- 플레이어 스탯 보너스 (Phase 6)
--========================================
Balance.HP_PER_POINT = 10              -- 포인트당 체력 증가
Balance.STAMINA_PER_POINT = 10         -- 포인트당 스태미너 증가
Balance.SLOTS_PER_POINT = 5            -- 포인트당 인벤토리 칸 증가
Balance.BASE_INV_SLOTS = 60            -- 기본 인벤토리 칸 수
Balance.MAX_INV_SLOTS = 120            -- 최대 인벤토리 칸 수 (120 이상 불가)
Balance.WORKSPEED_PER_POINT = 10       -- 포인트당 작업 속도 증가
Balance.ATTACK_PER_POINT = 0.05        -- 포인트당 공격력 증가 (5%)

Balance.STAT_BONUS_PER_LEVEL = 0       -- 레벨당 자동 보너스 (배제됨, 포인트제로 통합)

--========================================
-- 스태미나 & 이동 시스템 (Phase 10)
--========================================
Balance.STAMINA_MAX = 100              -- 최대 스태미나
Balance.STAMINA_REGEN = 25             -- 초당 스태미나 회복량 (상향: 8 -> 25)
Balance.STAMINA_REGEN_DELAY = 0.8      -- 회복 시작 딜레이 (단축: 1.5 -> 0.8)

-- 스프린트 (빠르게 달리기)
Balance.SPRINT_SPEED_MULT = 1.25       -- 스프린트 속도 배율 (소폭 상향)
Balance.SPRINT_STAMINA_COST = 18       -- 초당 스태미나 소모 (강화: 12 -> 18)
Balance.SPRINT_MIN_STAMINA = 5         -- 스프린트 시작 최소 스태미나 (10 -> 5)
Balance.AUTO_SPRINT_HOLD_TIME = 1.6    -- 자동 달리기 전환까지 직진 유지 시간(초)
Balance.AUTO_SPRINT_DIRECTION_DOT = 0.94 -- 직진 판정 민감도(1에 가까울수록 엄격)
Balance.AUTO_SPRINT_MIN_MOVE = 0.25    -- 자동 달리기 판정을 시작할 최소 이동 입력 크기

-- 구르기 (회피)
Balance.DODGE_STAMINA_COST = 25        -- 구르기 1회 스태미나 소모
Balance.DODGE_COOLDOWN = 0.8           -- 구르기 쿨다운 (초)
Balance.DODGE_DISTANCE = 12            -- 구르기 이동 거리 (스터드)
Balance.DODGE_DURATION = 0.4           -- 구르기 소요 시간 (초)
Balance.DODGE_IFRAMES = 0.35           -- [수정] 무적 프레임 지속 시간 (0.25 → 0.35초, 네트워크 지연 보상)
--========================================
-- 수확 및 공격 판정 (Phase 7)
--========================================
Balance.HARVEST_COOLDOWN = 0.4         -- 연속 타격 쿨다운 (0.5 -> 0.4 단축)
Balance.HARVEST_RANGE = 12             -- [수정] 기본 수확 거리 (25 -> 12, 도구 사거리 시스템으로 대체)
Balance.COMBAT_HITBOX_SIZE = 10        -- [수정] 기본 공격 판정 반경 (12 -> 10)
Balance.XP_HARVEST_XP_PER_HIT = 100000    -- 타격당 XP (10000 -> 100000)

-- 도구별 사거리 (Reach)
Balance.REACH_BAREHAND = 12             -- 맨손 (8 -> 12)
Balance.REACH_TOOL = 14               -- 도끼, 곡괭이, 몽둥이 (10 -> 14)
Balance.REACH_SWORD = 16               -- 검 (근접 무기)
Balance.REACH_ANGLE = 75               -- 공격 인정 각도 (정면 기준 +-75도)

--========================================
-- 배고픔 (생존) 시스템
--========================================
Balance.HUNGER_MAX = 100               -- 최대 배고픔 수치
Balance.HUNGER_DECREASE_RATE = 0.08     -- 초당 배고픔 감소량 (0.5 -> 0.08 완화)
Balance.HUNGER_STARVATION_DAMAGE = 1   -- 배고픔이 0일 때 초당 잃는 체력
Balance.HEALTH_REGEN_RATE = 0.001       -- 초당 체력 회복 비율 (0.1% MaxHealth/초, 거의 없음)
Balance.HUNGER_SPRINT_COST = 0.15      -- 달리기 시 초당 배고픔 추가 소모량 (0.5 -> 0.15 완화)
Balance.HUNGER_DODGE_COST = 0.5        -- 구르기 1회당 배고픔 소모량 (2.0 -> 0.5 완화)
Balance.HUNGER_HARVEST_COST = 0.2      -- 채집 1회당 배고픔 소모량 (1.0 -> 0.2 완화)
Balance.HUNGER_COMBAT_COST = 0.2       -- 공격 1회당 배고픔 소모량 (1.0 -> 0.2 완화)

-- 수면(간이천막) 연출/제한
Balance.SLEEP_COOLDOWN = 20            -- 연속 수면 방지 쿨다운(초)
Balance.RECALL_CAST_TIME = 5           -- 귀환 시전 시간(초)
Balance.RECALL_COOLDOWN = 60           -- 귀환 쿨다운(초)
Balance.SLEEP_FADE_OUT_TIME = 0.8      -- 수면 페이드아웃 시간(초)
Balance.SLEEP_BLACK_HOLD_TIME = 0.5    -- 암전 유지 시간(초)
Balance.SLEEP_FADE_IN_TIME = 1.0       -- 기상 페이드인 시간(초)


-- 채집 홀드 시스템 (E키 꿉 누르기)
Balance.HARVEST_HOLD_TIME_BASE = 2.0   -- 기본 채집 시간 (초, 맨손 기준)
Balance.HARVEST_HOLD_TIME_OPTIMAL = 0.8 -- 최적 도구 사용 시 채집 시간 (초)
Balance.HARVEST_EFFICIENCY_BAREHAND = 0.5 -- 맨손 효율 (자원 획득량 배율)
Balance.HARVEST_EFFICIENCY_WRONG_TOOL = 0.7 -- 맞지 않는 도구 효율
Balance.HARVEST_EFFICIENCY_OPTIMAL = 1.2 -- 최적 도구 효율
Balance.HARVEST_BAREHAND_HP_PENALTY = 2 -- 맨손으로 나무/바위 타격 시 체력 감소량

--========================================
-- 베이스 시스템 (Phase 7)
--========================================
Balance.BASE_DEFAULT_RADIUS = 30       -- 기본 베이스 반경
Balance.BASE_MAX_RADIUS = 100          -- 최대 베이스 반경
Balance.BASE_RADIUS_PER_LEVEL = 10     -- 레벨당 추가 반경
Balance.BASE_MAX_PER_PLAYER = 1        -- 플레이어당 최대 베이스 수
Balance.TOTEM_UPKEEP_DAY_SECONDS = 86400 -- 유지비 단위 시간(24시간)
Balance.TOTEM_UPKEEP_COST_1D = 100       -- 1일 유지비
Balance.TOTEM_UPKEEP_COST_3D = 280       -- 3일 유지비(할인)
Balance.TOTEM_UPKEEP_COST_7D = 630       -- 7일 유지비(할인)
Balance.TOTEM_INITIAL_GRACE_SECONDS = 86400 -- 토템 첫 설치 무료 유지시간
Balance.TOTEM_PREVIEW_HEIGHT = 0.25      -- 토템 범위 프리뷰 높이
Balance.TOTEM_PROXIMITY_SHOW_RANGE = 65  -- 토템 범위 프리뷰 노출 거리
Balance.STARTER_PROTECTION_RADIUS = 45   -- 초보자 스폰 보호존 반경
Balance.STARTER_PROTECTION_SHOW_RANGE = 130 -- 스폰 보호존 프리뷰 표시 거리

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
Balance.ARMOR_DURABILITY_LOSS_RATIO = 0.1 -- 피격 시 방어구 내구도 감소 비율
Balance.KNOCKBACK_FORCE = 25               -- 피격 시 기본 넉백 강도 (플레이어)
Balance.CREATURE_KNOCKBACK_FORCE = 12      -- 크리처 피격 넉백 강도
Balance.DAMAGE_VARIANCE = 0.15             -- 데미지 등락폭 (±15%)

--========================================
-- 텔레그래프 공격 시스템 (크리처 공격 패턴)
--========================================
-- 패턴별 기본 선행(windup) 시간 (크리처 개별 설정이 우선)
Balance.TELEGRAPH_WINDUP_CONE = 0.35       -- 부채꼴: 짧음 (즉발에 가까움)
Balance.TELEGRAPH_WINDUP_CIRCLE = 1.2      -- 원형 범위: 길음
Balance.TELEGRAPH_WINDUP_CHARGE = 1.5      -- 직선 돌진: 길음
Balance.TELEGRAPH_WINDUP_PROJECTILE = 0.4  -- 원거리: 짧음
-- 범위 표시 시각 효과 (비활성 — 크리처 Highlight 발광으로 대체)
-- Balance.TELEGRAPH_INDICATOR_COLOR = Color3.fromRGB(255, 240, 130)
-- Balance.TELEGRAPH_INDICATOR_OPACITY = 0.35
-- Balance.TELEGRAPH_INDICATOR_HEIGHT = 0.15
-- Balance.TELEGRAPH_INDICATOR_OVERSIZE = 1.15
-- Balance.TELEGRAPH_FLASH_SPEED = 3.0
Balance.PACK_AGGRO_RADIUS = 50             -- 피격 시 주변 동족 연쇄 어그로 반경
Balance.DROP_BILLBOARD_MAX_DIST = 25       -- 드롭 아이템 라벨 표시 최대 거리
Balance.DROP_PROMPT_RANGE = 5              -- [하향] 너무 멀리서 보이지 않도록 거리 추가 축소 (8 -> 5)
Balance.DROP_MODEL_DEFAULT = "POUCH"       -- 드롭 아이템 기본 모델 이름
Balance.DROP_SIZE = Vector3.new(0.8, 0.8, 0.8) -- 드롭 아이템 기본 크기 (Fallback)
Balance.DROP_BILLBOARD_OFFSET = Vector3.new(0, 2, 0) -- 드롭 라벨 상단 오프셋

Balance.BASE_WALK_SPEED = 16               -- 플레이어 기본 이동 속도
Balance.INTERACT_OFFSET = 4                -- 상호작용 거리 보정값
Balance.CREATURE_AI_TICK = 0.3             -- 크리처 AI 업데이트 간격 (초)
Balance.CREATURE_INITIAL_SPAWN_RADIUS = 300 -- 서버 시작 시 크리처 스폰 반경
Balance.CREATURE_DESPAWN_DIST = 300        -- 크리처 디스폰 거리

-- 펫 시스템
Balance.PET_MAX_SLOTS = 3                  -- 최대 펫 슬롯 수
Balance.PET_DEFAULT_SLOTS = 1              -- 기본 해금 슬롯 수
Balance.PET_FOLLOW_DIST = 5                -- 펫 추적 거리 (스터드)
Balance.PET_FOLLOW_SPEED = 18              -- 펫 추적 이동 속도
Balance.PET_ATTACK_RANGE = 10              -- 펫 공격 범위 (스터드)
Balance.PET_ATTACK_COOLDOWN = 1.5          -- 펫 공격 쿨다운 (초)
Balance.PET_RESPAWN_TIME = 30              -- 펫 사망 후 재소환 시간 (초)
Balance.PET_DETECT_RANGE = 20              -- 펫 적 감지 범위 (스터드)
Balance.PET_LEASH_DIST = 40                -- 펫 최대 이탈 거리 (초과 시 텔레포트)

table.freeze(Balance)

return Balance
