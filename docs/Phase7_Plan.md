# Phase 7: 베이스 자동화 완성

> **작성일**: 2026-02-16  
> **목표**: 베이스 자동화 시스템 완성 (팰 자동 수확, 자동 제작, 자동 저장)  
> **마일스톤**: M4 — 베이스/자동화 완성

---

## 개요

Phase 6까지 완료된 상태에서, 이제 베이스 자동화를 완성한다:

- 플레이어가 베이스 영역을 설정
- 팰이 베이스 내 자원 노드에서 자동 수확
- 시설에서 제작 완료 시 Output 또는 Storage로 자동 이동
- 팰의 workType과 시설 functionType 매칭으로 자동 작업

---

## Phase 7-1: HarvestService (수확 시스템 기반)

**목표**: 자원 노드(나무, 돌, 풀 등)에서 아이템을 수확하는 기본 시스템

### 데이터 구조

```lua
-- ResourceNodeData.lua (신규)
{
  id = "TREE_OAK",
  name = "참나무",
  nodeType = "TREE",           -- TREE, ROCK, BUSH, FIBER
  requiredTool = "AXE",        -- 필요 도구 타입
  resources = {
    { itemId = "WOOD", min = 3, max = 5, weight = 1.0 },
    { itemId = "RESIN", min = 0, max = 1, weight = 0.3 },
  },
  maxHits = 5,                 -- 완전 채집까지 타격 횟수
  respawnTime = 300,           -- 리스폰 시간 (초)
  xpPerHit = 2,                -- 타격당 XP
}
```

### HarvestService API

```lua
HarvestService.Init(NetController, DataService, InventoryService, PlayerStatService, DurabilityService)

-- 수확 시도 (플레이어가 노드 타격)
HarvestService.hit(player, nodeId) → success, drops[]

-- 노드 상태 조회
HarvestService.getNodeState(nodeId) → { remainingHits, isActive }

-- 노드 리스폰 (내부)
HarvestService._respawnNode(nodeId)
```

### Protocol 추가

```lua
["Harvest.Hit.Request"] = true,      -- 자원 채집 타격
["Harvest.Node.Spawned"] = true,     -- 노드 스폰 이벤트
["Harvest.Node.Depleted"] = true,    -- 노드 고갈 이벤트
```

### 완료 기준 (DoD)

- [ ] 나무/돌/풀 노드에서 자원 채집 가능
- [ ] 도구 타입 검증 (AXE로 나무, PICKAXE로 돌)
- [ ] 채집 시 도구 내구도 감소
- [ ] 채집 시 XP 획득
- [ ] 노드 고갈 후 일정 시간 뒤 리스폰

---

## Phase 7-2: BaseClaimService (베이스 영역 시스템)

**목표**: 플레이어가 베이스 영역을 설정하고, 그 안에서만 자동화 작동

### 데이터 구조

```lua
-- 베이스 상태
BaseClaim = {
  id = "base_12345",
  ownerId = userId,
  centerPosition = Vector3,    -- 베이스 중심
  radius = 50,                 -- 베이스 반경 (스터드)
  createdAt = timestamp,
  level = 1,                   -- 베이스 레벨 (확장 가능)
}
```

### Balance 상수

```lua
Balance.BASE_DEFAULT_RADIUS = 30        -- 기본 베이스 반경
Balance.BASE_MAX_RADIUS = 100           -- 최대 베이스 반경
Balance.BASE_RADIUS_PER_LEVEL = 10      -- 레벨당 추가 반경
Balance.BASE_MAX_PER_PLAYER = 1         -- 플레이어당 최대 베이스 수
```

### BaseClaimService API

```lua
BaseClaimService.Init(NetController, SaveService, BuildService)

-- 베이스 생성 (첫 번째 건물 설치 시 자동 or 명시적 호출)
BaseClaimService.create(userId, position) → baseId

-- 베이스 정보 조회
BaseClaimService.getBase(userId) → BaseClaim?

-- 위치가 베이스 안인지 확인
BaseClaimService.isInBase(userId, position) → boolean

-- 베이스 내 시설/노드 목록
BaseClaimService.getStructuresInBase(userId) → structureId[]
BaseClaimService.getNodesInBase(userId) → nodeId[]
```

### 완료 기준 (DoD)

- [ ] 첫 건물 설치 시 베이스 자동 생성
- [ ] 베이스 반경 내에서만 자동화 작동
- [ ] SaveService에 베이스 영속화

---

## Phase 7-3: AutoHarvestService (팰 자동 수확)

**목표**: 배치된 팰이 베이스 내 자원 노드를 자동으로 수확

### 로직 흐름

```
1. FacilityService에 workType="GATHERING" 시설 정의 (또는 기존 시설 확장)
2. 팰이 시설에 배치됨 (FacilityService.assignPal)
3. 매 틱마다:
   a. 베이스 내 자원 노드 검색
   b. 팰의 workTypes와 노드의 nodeType 매칭
   c. 수확 실행 → 아이템을 Output/Storage에 추가
```

### 추가 시설: 채집 스테이션

```lua
-- FacilityData.lua 추가
{
  id = "GATHERING_POST",
  name = "채집 기지",
  description = "팰이 주변 자원을 자동으로 수집합니다.",
  modelName = "GatheringPost",
  requirements = {
    { itemId = "WOOD", amount = 20 },
    { itemId = "STONE", amount = 10 },
  },
  buildTime = 0,
  maxHealth = 200,
  interactRange = 3,
  functionType = "GATHERING",
  gatherRadius = 30,            -- 자원 수집 범위
  gatherInterval = 10,          -- 수집 간격 (초)
  hasOutputSlot = true,         -- 수집한 아이템 저장
  outputSlots = 20,
}
```

### AutoHarvestService API

```lua
AutoHarvestService.Init(HarvestService, FacilityService, BaseClaimService, PalboxService)

-- 틱 처리 (Heartbeat에서 호출)
AutoHarvestService.tick(deltaTime)

-- 특정 시설의 자동 수확 강제 실행
AutoHarvestService.forceGather(structureId) → drops[]
```

### 완료 기준 (DoD)

- [ ] 채집 기지에 팰 배치 시 주변 자원 자동 수확
- [ ] 수확 속도 = 기본 속도 × 팰 workPower
- [ ] 수확된 아이템이 시설 Output 슬롯에 저장
- [ ] Output 가득 차면 수확 중단

---

## Phase 7-4: AutoDepositService (자동 저장)

**목표**: 시설 Output이 가득 차면 근처 Storage로 자동 이동

### 로직 흐름

```
1. FacilityService에서 Output 슬롯이 가득 참
2. AutoDepositService가 베이스 내 Storage 검색
3. 여유 공간 있는 Storage에 아이템 이동
4. 이동 성공 시 Output 비움
```

### AutoDepositService API

```lua
AutoDepositService.Init(FacilityService, StorageService, BaseClaimService)

-- 틱 처리
AutoDepositService.tick(deltaTime)

-- 강제 이동
AutoDepositService.depositFromFacility(structureId) → success, count
```

### 완료 기준 (DoD)

- [ ] 작업대 Output → 근처 Storage 자동 이동
- [ ] 캠프파이어 Output → 근처 Storage 자동 이동
- [ ] 채집 기지 Output → 근처 Storage 자동 이동
- [ ] Storage 우선순위: 가장 가까운 Storage 먼저

---

## 구현 순서

```
Phase 7-1: HarvestService (기반)
    ↓
Phase 7-2: BaseClaimService (영역)
    ↓
Phase 7-3: AutoHarvestService (팰 자동 수확)
    ↓
Phase 7-4: AutoDepositService (자동 저장)
```

---

## 파일 리스트

### 신규 생성

- `src/ReplicatedStorage/Data/ResourceNodeData.lua`
- `src/ServerScriptService/Server/Services/HarvestService.lua`
- `src/ServerScriptService/Server/Services/BaseClaimService.lua`
- `src/ServerScriptService/Server/Services/AutoHarvestService.lua`
- `src/ServerScriptService/Server/Services/AutoDepositService.lua`

### 수정

- `src/ReplicatedStorage/Shared/Net/Protocol.lua` (Harvest 명령어)
- `src/ReplicatedStorage/Shared/Enums/Enums.lua` (NodeType, HarvestError)
- `src/ReplicatedStorage/Shared/Config/Balance.lua` (베이스, 채집 상수)
- `src/ReplicatedStorage/Data/FacilityData.lua` (채집 기지 추가)
- `src/ServerScriptService/ServerInit.server.lua` (서비스 초기화)
- `src/ServerScriptService/Server/Services/SaveService.lua` (베이스 영속화)

---

## Balance 상수 추가

```lua
-- 베이스 시스템
Balance.BASE_DEFAULT_RADIUS = 30
Balance.BASE_MAX_RADIUS = 100
Balance.BASE_RADIUS_PER_LEVEL = 10
Balance.BASE_MAX_PER_PLAYER = 1

-- 수확 시스템
Balance.HARVEST_XP_PER_HIT = 2
Balance.HARVEST_COOLDOWN = 0.5        -- 연속 타격 쿨다운 (초)
Balance.NODE_RESPAWN_MIN = 180        -- 최소 리스폰 시간
Balance.NODE_RESPAWN_MAX = 600        -- 최대 리스폰 시간

-- 자동화 시스템
Balance.AUTO_HARVEST_INTERVAL = 10    -- 팰 자동 수확 간격 (초)
Balance.AUTO_DEPOSIT_INTERVAL = 5     -- 자동 저장 간격 (초)
Balance.AUTO_DEPOSIT_RANGE = 20       -- Storage 검색 범위
```

---

## Enum 추가

```lua
-- NodeType (자원 노드 타입)
Enums.NodeType = {
  TREE = "TREE",
  ROCK = "ROCK",
  BUSH = "BUSH",
  FIBER = "FIBER",
  ORE = "ORE",
}

-- HarvestError
Enums.ErrorCode.NO_TOOL = "NO_TOOL"
Enums.ErrorCode.WRONG_TOOL = "WRONG_TOOL"
Enums.ErrorCode.NODE_DEPLETED = "NODE_DEPLETED"
Enums.ErrorCode.NODE_NOT_FOUND = "NODE_NOT_FOUND"

-- FacilityType (추가)
Enums.FacilityType.GATHERING = "GATHERING"
```

---

## 검증 시나리오

### 플레이어 수동 채집

1. 플레이어가 돌 곡괭이 장착
2. 바위 노드에 접근하여 타격
3. 돌/부싯돌 아이템 인벤토리에 추가
4. 곡괭이 내구도 감소
5. XP 2 획득
6. 5회 타격 후 노드 고갈 → 5분 후 리스폰

### 팰 자동 수확

1. 채집 기지 건설
2. workType=GATHERING인 팰 배치
3. 10초마다 베이스 내 나무/돌 자동 수확
4. 수확 속도 = 기본 × 팰 workPower
5. Output 슬롯에 자원 축적
6. Output 가득 차면 근처 Storage로 자동 이동

---

## 완료 기준 (Phase 7 전체)

- [ ] 플레이어가 자원 노드에서 수동 채집 가능
- [ ] 도구 타입에 따른 채집 가능 노드 제한
- [ ] 채집 시 XP 획득 및 도구 내구도 감소
- [ ] 베이스 영역 자동 생성 및 확장
- [ ] 팰이 베이스 내 자원 자동 수확
- [ ] 시설 Output → Storage 자동 이동
- [ ] SaveService에 베이스 영속화

---

_Phase 7 완료 시 README 완료 기준 "베이스 자동화 가능" 달성_
