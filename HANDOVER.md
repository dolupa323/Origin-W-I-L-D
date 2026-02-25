# DinoTribeSurvival (Origin-WILD) 프로젝트 인수인계 문서

> **작성일**: 2026-02-25  
> **현재 진행 상태**: Phase 1-4 GDD 정렬 완료 (전투 밸런스, 테크트리 개편)  
> **게임 개요**: 로블록스 기반 공룡+생존 서바이벌 게임 (서버 권위 모델)

---

## 1. 프로젝트 기본 정보

### 1.1 폴더 구조

```
c:\YJS\Roblox\Origin-WILD\
├── default.project.json    # Rojo 프로젝트 설정
├── rojo.exe                # Rojo CLI
├── README.md
└── src/
    ├── ReplicatedStorage/  # 공유 모듈 (클라/서버 공용)
    │   ├── Data/           # 게임 데이터 테이블
    │   └── Shared/         # 공유 유틸/설정
    ├── ServerScriptService/ # 서버 전용
    │   ├── ServerInit.server.lua
    │   └── Server/
    │       ├── Controllers/ # 네트워크 컨트롤러
    │       ├── Services/    # 게임 서비스
    │       ├── Persistence/ # 저장 클라이언트
    │       └── Debug/       # 디버그 도구
    └── StarterPlayer/
        └── StarterPlayerScripts/
            ├── ClientInit.client.lua
            ├── Client/
            │   ├── NetClient.lua
            │   └── Controllers/  # 클라이언트 컨트롤러
            └── NetProtocolTest.client.lua
```

### 1.2 Rojo 설정 (default.project.json)

```json
{
  "name": "DinoTribeSurvival",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": { "$path": "src/ReplicatedStorage" },
    "ServerScriptService": { "$path": "src/ServerScriptService" },
    "StarterPlayer": {
      "StarterPlayerScripts": {
        "$path": "src/StarterPlayer/StarterPlayerScripts"
      }
    }
  }
}
```

### 1.3 실행 방법

```powershell
cd c:\YJS\Roblox\Origin-WILD
.\rojo.exe serve default.project.json
# Roblox Studio에서 Rojo 플러그인으로 연결
```

---

## 2. 핵심 설계 원칙

### 2.1 SSOT (Single Source of Truth)

- **서버 권위**: 모든 게임 상태는 서버에서만 변경
- **클라이언트는 뷰어**: 서버 이벤트를 받아 UI만 업데이트
- **검증은 서버에서**: 클라이언트 입력은 신뢰하지 않음

### 2.2 데이터 검증 (Data Panic)

- **Validator.assert()**: 조건 실패 시 `error()` 발생 → 서버 부팅 중단
- **목적**: 잘못된 데이터로 게임 운영 방지
- **적용 시점**: 서버 시작 시 모든 데이터 테이블 검증

### 2.3 requestId 중복 방지 (Dedup)

- **TTL**: 10초
- **동작**: 같은 requestId 재요청 시 `NET_DUPLICATE_REQUEST` 반환
- **목적**: 네트워크 재전송으로 인한 중복 처리 방지

### 2.4 이벤트 드리븐 UI

- **패턴**: 서버 → `*.Changed` 이벤트 → 클라이언트 UI 갱신
- **예시**: `Inventory.Changed`, `WorldDrop.Spawned`, `Storage.Changed`

---

## 3. 핵심 모듈 상세

### 3.1 Balance.lua (상수 정의)

**경로**: `src/ReplicatedStorage/Shared/Config/Balance.lua`

```lua
Balance.DAY_LENGTH = 2400          -- 하루 총 길이 (초)
Balance.DAY_DURATION = 1800        -- 낮 시간 (초)
Balance.NIGHT_DURATION = 600       -- 밤 시간 (초)

Balance.INV_SLOTS = 20             -- 인벤토리 슬롯 수
Balance.MAX_STACK = 99             -- 최대 스택

Balance.STORAGE_SLOTS = 20         -- 창고 슬롯 수

Balance.DROP_CAP = 400             -- 서버 드롭 최대 개수
Balance.DROP_MERGE_RADIUS = 5      -- 드롭 병합 반경 (스터드)
Balance.DROP_LOOT_RANGE = 10       -- 루팅 거리 (스터드)
Balance.DROP_DESPAWN_DEFAULT = 300 -- 기본 디스폰 (초)
Balance.DROP_DESPAWN_GATHER = 600  -- 채집 디스폰 (초)

Balance.BUILD_STRUCTURE_CAP = 500  -- 구조물 최대 개수
Balance.BUILD_RANGE = 20           -- 건축 거리 (스터드)

-- 플레이어 스탯 보너스 (Phase 6)
Balance.HP_PER_POINT = 10              -- 포인트당 체력 증가
Balance.STAMINA_PER_POINT = 10         -- 포인트당 스태미너 증가
Balance.WEIGHT_PER_POINT = 50          -- 포인트당 무게 증가
Balance.BASE_WEIGHT_CAPACITY = 300     -- 기본 소지 무게 (kg)
Balance.WORKSPEED_PER_POINT = 10       -- 포인트당 작업 속도 증가
Balance.ATTACK_PER_POINT = 0.05        -- 포인트당 공격력 증가 (5%)
```

### 3.2 Enums.lua (열거형)

**경로**: `src/ReplicatedStorage/Shared/Enums/Enums.lua`

**주요 열거형**:

- `ErrorCode`: OK, BAD_REQUEST, INV_FULL, SLOT_EMPTY, COLLISION, STRUCTURE_CAP 등
- `TimePhase`: DAY, NIGHT
- `ItemType`: RESOURCE, TOOL, WEAPON, ARMOR, CONSUMABLE, PLACEABLE, MISC
- `Rarity`: COMMON, UNCOMMON, RARE, EPIC, LEGENDARY
- `FacilityType`: COOKING, STORAGE, CRAFTING, RESPAWN, SMELTING, FARMING, DEFENSE

### 3.3 Protocol.lua (네트워크 프로토콜)

**경로**: `src/ReplicatedStorage/Shared/Net/Protocol.lua`

**명령어 목록**:

```lua
-- 기본
Net.Ping, Net.Echo

-- 시간
Time.Sync.Request, Time.Warp, Time.WarpToPhase, Time.Debug

-- 저장
Save.Now, Save.Status

-- 인벤토리
Inventory.Move.Request, Inventory.Split.Request, Inventory.Drop.Request
Inventory.Get.Request, Inventory.GiveItem

-- 월드드롭
WorldDrop.Loot.Request

-- 창고
Storage.Open.Request, Storage.Close.Request, Storage.Move.Request

-- 건설 (Phase 2-1 추가)
Build.Place.Request, Build.Remove.Request, Build.GetAll.Request
```

### 3.4 Validator.lua (검증 유틸)

**경로**: `src/ReplicatedStorage/Shared/Types/Validator.lua`

**주요 API**:

```lua
Validator.assert(condition, errorCode, message)  -- 실패 시 error()
Validator.check(condition, errorCode)            -- 실패 시 false, errorCode 반환
Validator.validateIdTable(array, tableName)      -- 배열 → Map 변환 + id 검증
Validator.validateRecipeRefs(recipes, items)     -- Recipe → Item 참조 검증
Validator.validateDropTableRefs(tables, items)   -- DropTable → Item 참조 검증
```

---

## 4. 서버 서비스 상세

### 4.1 DataService

**경로**: `src/ServerScriptService/Server/Services/DataService.lua`

**역할**: 모든 데이터 테이블 로드 및 검증

**로드 순서**:

1. ItemData (기본)
2. CreatureData
3. RecipeData (Item 참조)
4. FacilityData (Recipe 참조 가능)
5. TechUnlockData, QuestData, NPCShopData, DropTableData, DurabilityProfiles

**API**:

```lua
DataService.Init()                    -- 서버 시작 시 호출
DataService.getItem(itemId)           -- ItemData 조회
DataService.getRecipe(recipeId)       -- RecipeData 조회
DataService.getFacility(facilityId)   -- FacilityData 조회
DataService.getCreature(creatureId)   -- CreatureData 조회
DataService.getDropTable(tableId)     -- DropTableData 조회
```

### 4.2 TimeService

**경로**: `src/ServerScriptService/Server/Services/TimeService.lua`

**역할**: 게임 내 시간 관리 (낮/밤 사이클)

**API**:

```lua
TimeService.Init(NetController)
TimeService.getServerTime()           -- 서버 시간 (초)
TimeService.GetHandlers()             -- 핸들러 테이블 반환
```

**이벤트**: `Time.SyncResponse`, `Time.PhaseChange`

### 4.3 SaveService

**경로**: `src/ServerScriptService/Server/Services/SaveService.lua`

**역할**: 플레이어/월드 데이터 영속화

**API**:

```lua
SaveService.Init(NetController)
SaveService.getPlayerState(userId)    -- 플레이어 데이터
SaveService.getWorldState()           -- 월드 데이터 (공유)
SaveService.GetHandlers()
```

### 4.4 InventoryService

**경로**: `src/ServerScriptService/Server/Services/InventoryService.lua`

**역할**: 플레이어 인벤토리 관리

**API**:

```lua
InventoryService.Init(NetController, DataService)
InventoryService.getOrCreateInventory(userId)
InventoryService.getInventory(userId)
InventoryService.removeInventory(userId)

-- 조작
InventoryService.move(player, fromSlot, toSlot, count?)  -- 이동/합치기/스왑
InventoryService.split(player, fromSlot, toSlot, count)  -- 분할 (toSlot은 빈 슬롯 필수)
InventoryService.drop(player, slot, count?)              -- 드롭 (서버에서만 슬롯 비움)
InventoryService.canAdd(userId, itemId, count)           -- 추가 가능 여부
InventoryService.addItem(userId, itemId, count)          -- 아이템 추가
InventoryService.hasItem(userId, itemId, count)          -- 보유 여부 확인
InventoryService.removeItem(userId, itemId, count)       -- 아이템 제거 (여러 슬롯 분산)

-- 내부용 (다른 서비스에서 사용)
InventoryService.MoveInternal(userId, fromSlot, toSlot, count, containerFrom, containerTo)
InventoryService._decreaseSlot(inv, slot, count)
InventoryService._increaseSlot(inv, slot, itemId, count)
InventoryService._makeChange(inv, slot)

InventoryService.GetHandlers()
```

**이벤트**: `Inventory.Changed`

### 4.5 WorldDropService

**경로**: `src/ServerScriptService/Server/Services/WorldDropService.lua`

**역할**: 월드 드롭 아이템 관리

**Cap 관리**:

- 최대 400개 제한
- 초과 시 가장 오래된 드롭 제거 (prune)

**병합 (Merge)**:

- 5스터드 이내 같은 아이템 자동 병합
- MAX_STACK 초과 시 별도 드롭

**디스폰**:

- DEFAULT: 300초
- GATHER: 600초

**API**:

```lua
WorldDropService.Init(NetController, DataService, InventoryService, TimeService)
WorldDropService.spawnDrop(pos, itemId, count)   -- 드롭 생성
WorldDropService.loot(player, dropId, count?)    -- 루팅
WorldDropService.getDrops()                      -- 전체 드롭 조회
WorldDropService.GetHandlers()
```

**이벤트**: `WorldDrop.Spawned`, `WorldDrop.Changed`, `WorldDrop.Despawned`

### 4.6 StorageService

**경로**: `src/ServerScriptService/Server/Services/StorageService.lua`

**역할**: 공유 창고 시스템 (도둑질 허용)

**API**:

```lua
StorageService.Init(NetController, SaveService, InventoryService)
StorageService.open(player, storageId)           -- 창고 열기
StorageService.close(player, storageId)          -- 창고 닫기
StorageService.move(player, storageId, fromSlot, toSlot, count?, direction)
-- direction: "STORAGE_TO_INV" | "INV_TO_STORAGE" | "STORAGE_TO_STORAGE"
StorageService.GetHandlers()
```

**이벤트**: `Storage.Changed`, `Storage.Opened`, `Storage.Closed`

### 4.7 BuildService

**경로**: `src/ServerScriptService/Server/Services/BuildService.lua`

**역할**: 건설 시스템 (시설물 배치/해체/조회)

**Cap 관리**:

- 최대 500개 구조물 제한 (BUILD_STRUCTURE_CAP)
- 초과 시 가장 오래된 구조물 제거 (prune)

**검증**:

- 거리: BUILD_RANGE (20 스터드)
- 충돌: BUILD_COLLISION_RADIUS (2 스터드)
- 위치: 지면 레이캐스트 검증
- 재료: InventoryService.hasItem()으로 확인

**API**:

```lua
BuildService.Init(NetController, DataService, InventoryService, SaveService)
BuildService.place(player, facilityId, position, rotation)   -- 배치
BuildService.remove(player, structureId)                     -- 해체
BuildService.removeStructure(structureId, reason)            -- 내부 제거
BuildService.getAll()                                        -- 전체 조회
BuildService.get(structureId)                                -- 단일 조회
BuildService.getCount()                                      -- 개수 조회
BuildService.clearAll()                                      -- 디버그: 전체 제거
BuildService.GetHandlers()
```

**이벤트**: `Build.Placed`, `Build.Removed`, `Build.Changed`

### 4.8 CraftingService

**경로**: `src/ServerScriptService/Server/Services/CraftingService.lua`

**역할**: 제작 시스템 (Phase 2-2)

**핵심 패턴**: Timestamp 기반 Lazy Update

- craftTime == 0: 즐시 제작 (재료 차감 → 결과물 즈시 인벤 추가)
- craftTime > 0: 대기 제작 (재료 차감 → 큐 등록 → 완료 시 collect로 수거)

**검증**:

- 레시피 존재 여부
- 제작 큐 크기 (CRAFT_QUEUE_MAX = 5)
- 시설 접근 검증 (requiredFacility → BuildService.get + 거리 CRAFT_RANGE)
- 재료 보유 검증 (InventoryService.hasItem)
- 인벤토리 여유 검증 (canAdd)

**API**:

```lua
CraftingService.Init(NetController, DataService, InventoryService, BuildService)
CraftingService.start(player, recipeId, structureId?)  -- 제작 시작
CraftingService.cancel(player, craftId)                -- 제작 취소 (재료 환불)
CraftingService.collect(player, craftId)               -- 완성품 수거
CraftingService.getQueue(player)                       -- 큐 조회
CraftingService.getAvailableRecipes(player, structureId?)  -- 사용 가능 레시피
CraftingService.GetHandlers()
```

**이벤트**: `Craft.Started`, `Craft.Completed`, `Craft.Ready`, `Craft.Cancelled`

### 4.9 FacilityService

**경로**: `src/ServerScriptService/Server/Services/FacilityService.lua`

**역할**: 시설 상태 관리 서비스 (Phase 2-2)

**핵심 패턴**: 상태머신(IDLE/ACTIVE/FULL/NO_POWER) + Lazy Update

- 연료 기반 시설 (화로): Input → Fuel 소모 → Output 생산
- Lazy Update: 상호작용 시점에 (now - lastUpdateAt) 계산으로 일괄 처리
- 연료값: ItemData.fuelValue (WOOD=15초)
- 제작속도: FacilityData.craftSpeed (배율)
- 연료소모: FacilityData.fuelConsumption (초당)

**API**:

```lua
FacilityService.Init(NetController, DataService, InventoryService, BuildService, Balance)
FacilityService.register(structureId, facilityId, ownerId)  -- 시설 등록
FacilityService.unregister(structureId)                     -- 시설 제거
FacilityService.getInfo(player, structureId)                -- 정보 조회 (Lazy Update 트리거)
FacilityService.addFuel(player, structureId, invSlot)       -- 연료 투입
FacilityService.addInput(player, structureId, invSlot, count?)  -- 재료 투입
FacilityService.collectOutput(player, structureId)          -- 산출물 수거
FacilityService.GetHandlers()
```

**이벤트**: `Facility.StateChanged`

### 4.10 RecipeService

**경로**: `src/ServerScriptService/Server/Services/RecipeService.lua`

**역할**: 제작 효율 계산 서비스 (Phase 2-3)

**로직**:

- `Efficiency = FacilitySpeed * (1 + CreatureBonus + BondBonus + TraitBonus + PlayerStat)`
- `RealTime = BaseCraftTime / Efficiency`
- **목적**: 동적 제작 시간 계산을 위한 중앙 서비스

**API**:

```lua
RecipeService.Init(DataService)
RecipeService.calculateEfficiency(context) -- 효율 배율 반환
RecipeService.calculateCraftTime(recipeId, context) -- 실제 소요 시간 반환
RecipeService.getRecipeInfo(recipeId, context) -- 보정된 정보 반환
RecipeService.GetHandlers()
```

### 4.11 DurabilityService (Phase 2-4)

- **역할**: 아이템 내구도 관리
- **API**: `reduceDurability(player, slot, amount)`
- **Integration**: `InventoryService`와 연동하여 내구도 0 시 파괴 처리

### 4.12 CreatureService (Phase 3-1)

- **역할**: 크리처 엔티티 관리 및 스폰
- **API**: `spawn(creatureId, position)`
- **Data**: `CreatureData.lua` (Raptor, Triceratops, Dodo)
- **Features**:
  - **Spawn Loop**: 플레이어 주변 40~80m 내 랜덤 스폰 (Cap 50)
  - **AI Loop**: 상태 머신 (IDLE, WANDER, CHASE) 및 Humanoid 이동
  - **Despawn**: 플레이어와 150m 이상 멀어지면 삭제
  - **Damage & Death**: `applyDamage()` 호출 시 체력 차감 및 사망 처리 (아이템 드롭)

### 4.13 CombatService (Phase 3-3)

- **역할**: 전투 로직 및 데미지 계산
- **API**: `processPlayerAttack(player, targetId, toolSlot)`
- **Integration**:
  - `CreatureService`에 데미지 적용 위임
  - `DurabilityService`로 무기 내구도 차감
  - `InventoryService`에서 무기 정보 조회 (검증)

## 5. 네트워크 계층

### 5.1 NetController (서버)

**경로**: `src/ServerScriptService/Server/Controllers/NetController.lua`

**역할**: 서버 측 네트워크 처리

**API**:

```lua
NetController.Init()
NetController.RegisterHandler(command, handlerFn)
NetController.FireClient(player, eventName, data)
NetController.FireAllClients(eventName, data)
```

**구조**:

- RemoteFunction `NetCmd`: 요청-응답
- RemoteEvent `NetEvt`: 서버→클라이언트 푸시

### 5.2 NetClient (클라이언트)

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/NetClient.lua`

**API**:

```lua
NetClient.request(command, payload)              -- 서버에 요청 (자동 requestId)
NetClient.onEvent(eventName, callback)           -- 이벤트 리스너 등록
```

---

## 6. 클라이언트 컨트롤러

### 6.1 목록

| 파일                      | 역할                                     |
| ------------------------- | ---------------------------------------- |
| `InventoryController.lua` | `Inventory.Changed` 이벤트 수신, UI 갱신 |
| `WorldDropController.lua` | `WorldDrop.*` 이벤트 수신, 드롭 렌더링   |
| `StorageController.lua`   | `Storage.*` 이벤트 수신                  |
| `TimeController.lua`      | `Time.*` 이벤트 수신, 시간 UI            |
| `InteractController.lua`  | 상호작용 처리 (스텁)                     |
| `BuildController.lua`     | `Build.*` 이벤트 수신, 구조물 캐시       |
| `CraftController.lua`     | `Craft.*` 이벤트 수신, 제작 UI           |

---

## 7. 데이터 스키마

### 7.1 ItemData

```lua
{
  id = "WOOD",
  name = "나무",
  description = "기본 건축 재료",
  type = "RESOURCE",      -- Enums.ItemType
  rarity = "COMMON",      -- Enums.Rarity
  maxStack = 99,
  weight = 1,
  dropDespawn = "DEFAULT", -- "DEFAULT" | "GATHER"
}
```

### 7.2 FacilityData

```lua
{
  id = "CAMPFIRE",
  name = "캠프파이어",
  description = "요리와 빛을 제공합니다",
  modelName = "Campfire",           -- Assets 폴더 내 모델명
  requirements = {
    { itemId = "WOOD", amount = 5 },
    { itemId = "STONE", amount = 2 },
  },
  buildTime = 0,                    -- 0 = 즉시 배치
  maxHealth = 100,
  interactRange = 5,
  functionType = "COOKING",         -- Enums.FacilityType
}
```

### 7.3 인벤토리 슬롯

```lua
-- 서버 내부 구조
playerInventories[userId] = {
  slots = {
    [1] = { itemId = "WOOD", count = 50 },
    [2] = nil,  -- 빈 슬롯
    ...
  }
}
```

### 7.4 월드 드롭

```lua
drops[dropId] = {
  dropId = "drop_xxxx",
  pos = Vector3.new(x, y, z),
  itemId = "WOOD",
  count = 10,
  spawnedAt = 1234567890,
  despawnAt = 1234567890 + 300,
  inactive = false,
}
```

---

## 8. 서버 초기화 순서

**파일**: `src/ServerScriptService/ServerInit.server.lua`

```lua
1. DataService.Init()         -- 데이터 검증 (실패 시 부팅 중단)
2. NetController.Init()       -- 네트워크 설정
3. TimeService.Init()         -- 시간 시스템
4. SaveService.Init()         -- 저장 시스템
5. InventoryService.Init()    -- 인벤토리
6. WorldDropService.Init()    -- 월드 드롭
7. StorageService.Init()      -- 창고
-- 각 서비스 핸들러 등록
-- Inventory.Drop 오버라이드 (월드 드롭 연결)
```

---

## 9. 완료된 Phase 목록

### Phase 0: 프로젝트 기반

- [x] **0-2**: 폴더 구조 + Rojo 설정
- [x] **0-3**: NetProtocol v1 (Ping/Echo)

### Phase 1: 핵심 인프라

- [x] **1-1**: Balance, Enums, Validator
- [x] **1-2**: TimeService (낮/밤 사이클)
- [x] **1-3**: SaveService + DataStoreClient
- [x] **1-4**: DataService (데이터 로드/검증)
- [x] **1-5**: InventoryService (move/split/drop)
- [x] **1-6**: WorldDropService (Cap 400, Merge, Despawn, Loot)
- [x] **1-7**: StorageService (공유 창고, MoveInternal)

### Phase 1 DoD 검증 결과

- [x] **Data Panic**: Validator.assert() 사용, 잘못된 데이터시 error()
- [x] **requestId Dedup**: 10초 TTL, NET_DUPLICATE_REQUEST 반환
- [x] **Cap Prune**: DROP_CAP 초과 시 오래된 드롭 자동 제거
- [x] **Event-driven**: 모든 상태 변경 → 클라이언트 이벤트 발행

### Phase 2: 게임플레이 시스템

- [x] **2-1**: Build 전제조건 (Protocol, FacilityData, Enums, Balance) + BuildService 구현
- [x] **2-2**: CraftingService + FacilityService (상태머신, Lazy Update)
- [x] **2-3**: RecipeService (효율 계산 로직)
- [x] **2-4**: DurabilityService (내구도 시스템)
- [x] **Phase 3**: Creature System
  - [x] **3-1**: CreatureData 정의 및 Service 스켈레톤
  - [x] **3-2**: Spawn System (Donut Shape, Raycast) & Basic AI (FSM: Idle/Wander/Chase)
  - [x] **3-3**: Combat & Loot (Player Attack, Death Handling, WorldDrop)
- [x] **Phase 4**: 전투 & 생존 (손맛 구현)
  - [x] **4-1**: CombatService 보강 (Creature→Player 공격, BloodSmell 연동, Hit Result Event)
  - [x] **4-2**: PlayerLifeService (사망 처리, 아이템 30% 손실, 침대 리스폰 준비, 5초 리스폰 딜레이)
  - [x] **4-4**: DebuffService (BloodSmell/Freezing/Burning, 틱 데미지, 어그로 배율)
  - [x] **4-5**: Night & Fire System (밤 추위 디버프, Campfire 안전지대 판정)
  - [x] **Phase 5**: 테이밍 & 팰(Pal) 시스템
    - [x] **5-1**: 데이터 레이어 (PalData, CaptureItemData, ItemData 포획구 추가, Balance/Enums 확장)
    - [x] **5-2**: CaptureService (포획 판정, HP 비율 포획률 공식, 포획구 소모)
    - [x] **5-3**: PalboxService (보관함 CRUD, SaveService 연동, 닉네임/해방)
    - [x] **5-4**: PartyService (파티 편성/해제, 소환/회수, 팰 AI FOLLOW/COMBAT/IDLE)
    - [x] **5-5**: 작업 배치 (FacilityService 확장, 팰 workPower 연동)
  - [x] **Phase 6**: 기술 트리 & 플레이어 성장
    - [x] **6-1**: TechUnlockData (기술 트리 데이터 정의)
    - [x] **6-2**: PlayerStatService (XP, 레벨, 기술 포인트)
    - [x] **6-3**: TechService (기술 해금, 선행 기술, 레시피/시설 잠금)
  - [x] **Phase 7**: 베이스 자동화
    - [x] **7-1**: HarvestService (자원 수확 기반)
    - [x] **7-2**: BaseClaimService (베이스 영역 관리)
    - [x] **7-3**: AutoHarvestService (팸 자동 수확)
    - [x] **7-4**: AutoDepositService (자동 저장)
  - [x] **Phase 8**: 퀘스트 시스템
    - [x] **8-1**: QuestData (15개 퀘스트 정의)
    - [x] **8-2**: QuestService (상태 관리, 진행 추적, 보상 지급)
    - [x] **8-3**: 진행 추적 연동 (Harvest/Kill/Craft/Build/Capture/LevelUp/TechUnlock)
    - [x] **8-4**: QuestController (클라이언트 이벤트 수신)
  - [x] **Phase 9**: NPC 상점 시스템
    - [x] **9-1**: NPCShopData (5개 상점 정의)
    - [x] **9-2**: NPCShopService (골드 관리, 구매/판매 로직)
    - [x] **Phase 10: GDD 데이터 정령 (Phase 0~4)**
      - [x] **10-1**: 아이템 데미지 공식 적용 (Stone Spear 25, Wooden Bow 40 등)
      - [x] **10-2**: 테크트리 단계적 개편 (Phase 0: 맨손, Phase 2: 작업대 Era)
      - [x] **10-3**: Bola 시스템 명칭 정합 (넝쿨/뼈/청동/철제 볼라)
      - [x] **10-4**: 둔기(Club) 기절 데미지 50% 적용 로직 완성
    - [x] **9-3**: ShopController (클라이언트 상점 캐시)
    - [x] **9-4**: Enums/Balance/Protocol 확장

---

## 10. 완료: Phase 5-5 팰 작업 배치 시스템

### 10.1 구현 완료

- `FacilityService.lua`에 팰 배치/해제 API 추가
- 팰 workPower에 따른 작업 속도 보정
- Protocol.lua에 팰 배치 명령어 추가

### 10.2 API

```lua
-- FacilityService 확장 (Phase 5-5)
FacilityService.SetPalboxService(PalboxService) -- 의존성 주입
FacilityService.assignPal(userId, structureId, palUID) -- 팰 배치
FacilityService.unassignPal(userId, structureId) -- 팰 해제
FacilityService.getAssignedPal(structureId) -- 배치된 팰 조회
```

### 10.3 작업 속도 보정 공식

```lua
-- workPower에 따른 creatureBonus 계산
creatureBonus = (pal.workPower - 1) * 0.5
-- 예: workPower=2 → creatureBonus=0.5 → 50% 속도 증가
-- 예: workPower=3 → creatureBonus=1.0 → 100% 속도 증가

-- RecipeService.calculateEfficiency에 creatureBonus 적용
efficiency = facilitySpeed × (1 + creatureBonus + ...)
realCraftTime = baseCraftTime / efficiency
```

### 10.4 검증 항목

| 검증            | ErrorCode            | 조건                                    |
| --------------- | -------------------- | --------------------------------------- |
| 팰 존재         | NOT_FOUND            | 팰이 없거나 시설이 없음                 |
| 팰 상태         | PAL_IN_PARTY         | 소환 중인 팰 배치 시도                  |
| 중복 배치       | PAL_ALREADY_ASSIGNED | 이미 배치된 팰 또는 시설                |
| workType 불일치 | BAD_REQUEST          | 팰 workTypes와 시설 functionType 불일치 |
| 권한            | NO_PERMISSION        | 팰 소유자 아님                          |

### 10.5 Protocol 명령어

```lua
["Facility.AssignPal.Request"] = true   -- 팰 작업 배치
["Facility.UnassignPal.Request"] = true -- 팰 작업 해제
```

---

## 11. 완료: Phase 6 기술 트리 & 플레이어 성장

### 11.1 구현 완료

- `TechUnlockData.lua` 기술 트리 데이터 정의 (13개 노드)
- `PlayerStatService.lua` XP/레벨/기술 포인트 관리
- `TechService.lua` 기술 해금 및 잠금 검증
- Balance.lua/Enums.lua 확장

### 11.2 Balance 상수 (Phase 6)

```lua
Balance.PLAYER_MAX_LEVEL = 50          -- 최대 레벨
Balance.BASE_XP_PER_LEVEL = 100        -- 레벨 1→2 필요 XP
Balance.XP_SCALING = 1.2               -- 레벨당 필요 XP 증가율
Balance.TECH_POINTS_PER_LEVEL = 2      -- 레벨업당 기술 포인트
Balance.STAT_BONUS_PER_LEVEL = 0.02    -- 레벨당 스탯 보너스

-- XP 획득량
Balance.XP_CREATURE_KILL = 25
Balance.XP_CRAFT_ITEM = 5
Balance.XP_CAPTURE_PAL = 50
Balance.XP_HARVEST_RESOURCE = 2
```

### 11.3 PlayerStatService API

```lua
PlayerStatService.Init(NetController, SaveService, DataService)
PlayerStatService.getLevel(userId) → level
PlayerStatService.getXP(userId) → currentLevelXP, requiredXP
PlayerStatService.addXP(userId, amount, source) → leveledUp, newLevel
PlayerStatService.getTechPoints(userId) → available
PlayerStatService.spendTechPoints(userId, amount) → success
PlayerStatService.getStats(userId) → { level, currentXP, requiredXP, ... }
```

### 11.4 TechService API

```lua
TechService.Init(NetController, DataService, PlayerStatService, SaveService)
TechService.unlock(userId, techId) → success, errorCode
TechService.isUnlocked(userId, techId) → boolean
TechService.getUnlockedTech(userId) → { techId → true }
TechService.getAvailableTech(userId) → { techId → techData }
TechService.isRecipeUnlocked(userId, recipeId) → boolean
TechService.isFacilityUnlocked(userId, facilityId) → boolean
TechService.getTechTree() → 전체 기술 트리 데이터
```

### 11.5 기술 트리 구조 (TechUnlockData)

| Tier | ID                 | 이름          | 포인트 | 선행 기술                 | 해금                |
| ---- | ------------------ | ------------- | ------ | ------------------------- | ------------------- |
| 0    | TECH_BASICS        | 기초 지식     | 0      | -                         | (기본)              |
| 1    | TECH_STONE_TOOLS   | 석기 도구     | 1      | TECH_BASICS               | 곡괭이, 도끼 레시피 |
| 1    | TECH_FIBER_CRAFT   | 섬유 가공     | 1      | TECH_BASICS               | -                   |
| 1    | TECH_CAMPFIRE      | 캠프파이어    | 1      | TECH_BASICS               | CAMPFIRE 시설       |
| 2    | TECH_WORKBENCH     | 작업대        | 2      | TECH_STONE_TOOLS          | WORKBENCH 시설      |
| 2    | TECH_CAPTURE_BASIC | 기본 포획술   | 2      | TECH_FIBER_CRAFT          | 기본 포획구         |
| 2    | TECH_STORAGE       | 보관함 제작   | 2      | TECH_STONE_TOOLS          | STORAGE 시설        |
| 3    | TECH_CAPTURE_MEGA  | 고급 포획술   | 3      | TECH_CAPTURE_BASIC        | 고급 포획구         |
| 3    | TECH_SMELTING      | 제련 기술     | 3      | TECH_WORKBENCH + CAMPFIRE | FURNACE             |
| 3    | TECH_METAL_TOOLS   | 금속 도구     | 3      | TECH_SMELTING             | 금속 도구 레시피    |
| 4    | TECH_CAPTURE_ULTRA | 최고급 포획술 | 4      | TECH_CAPTURE_MEGA         | 울트라 포획구       |
| 4    | TECH_PAL_RIDING    | 팰 탑승       | 5      | TECH_CAPTURE_MEGA         | PAL_RIDING 기능     |
| 4    | TECH_PAL_BREEDING  | 팰 교배       | 5      | TECH_CAPTURE_ULTRA        | BREEDING_PEN        |

### 11.6 Protocol 명령어

```lua
["Player.Stats.Request"] = true        -- 레벨/XP/포인트 조회
["Tech.Unlock.Request"] = true         -- 기술 해금 요청
["Tech.List.Request"] = true           -- 해금된 기술 목록
["Tech.Tree.Request"] = true           -- 전체 트리 조회
```

### 11.7 이벤트

```lua
"Player.Stats.Changed"  -- 레벨업 시 발행
"Tech.Unlocked"         -- 기술 해금 시 발행
```

### 11.8 ErrorCode 추가

```lua
TECH_ALREADY_UNLOCKED      -- 이미 해금됨
TECH_NOT_FOUND             -- 기술 없음
INSUFFICIENT_TECH_POINTS   -- 기술 포인트 부족
PREREQUISITES_NOT_MET      -- 선행 기술 미해금
RECIPE_LOCKED              -- 레시피 미해금
```

---

## 12. 완료: BuildService (Phase 2-1)

### 10.1 구현 완료

- `BuildService.lua` 생성 완료
- 시설물 배치/해체/조회 기능 구현
- `BuildController.lua` 클라이언트 컨트롤러 생성

### 10.2 API

```lua
BuildService.Init(NetController, DataService, InventoryService, SaveService)

BuildService.place(player, facilityId, position, rotation)
-- 검증: 거리, 충돌, 재료 소모, 구조물 Cap
-- 성공 시: 구조물 생성, Inventory 재료 차감

BuildService.remove(player, structureId)
-- 검증: 권한, 거리
-- 성공 시: 구조물 제거

BuildService.getAll()
-- 모든 구조물 목록 반환

BuildService.GetHandlers()
```

### 10.3 이벤트

- `Build.Placed`: 새 구조물 배치됨
- `Build.Removed`: 구조물 제거됨
- `Build.Changed`: 구조물 상태 변경

### 10.4 검증 항목

| 검증 | ErrorCode            | 조건                                 |
| ---- | -------------------- | ------------------------------------ |
| 거리 | OUT_OF_RANGE         | `distance > BUILD_RANGE (20)`        |
| 충돌 | COLLISION            | 기존 구조물과 겹침                   |
| 위치 | INVALID_POSITION     | 지면 거리 < 0.5 또는 장애물          |
| Cap  | STRUCTURE_CAP        | `count >= BUILD_STRUCTURE_CAP (500)` |
| 재료 | MISSING_REQUIREMENTS | 필요 아이템 부족                     |

### 10.5 저장 구조

```lua
-- WorldSave 내부
worldState.structures = {
  [structureId] = {
    id = structureId,
    facilityId = "CAMPFIRE",
    position = Vector3,
    rotation = CFrame,
    health = 100,
    ownerId = userId,
    placedAt = timestamp,
  }
}
```

---

## 13. 코딩 컨벤션

### 13.1 파일명

- 서버 스크립트: `*.server.lua`
- 클라이언트 스크립트: `*.client.lua`
- 모듈: `*.lua`

### 13.2 서비스 패턴

```lua
local MyService = {}

-- Dependencies
local initialized = false
local NetController = nil

-- Internal Functions (underscore prefix)
local function _internalFn()
end

-- Public API
function MyService.publicMethod()
end

function MyService.Init(netController, ...)
  if initialized then return end
  initialized = true
  NetController = netController
  -- 초기화 로직
end

function MyService.GetHandlers()
  return {
    ["My.Command"] = function(player, payload)
      -- 핸들러 로직
      return { success = true, data = ... }
    end,
  }
end

return MyService
```

### 13.3 핸들러 반환값

```lua
-- 성공
return { success = true, data = { ... } }

-- 실패
return { success = false, errorCode = Enums.ErrorCode.XXX }
```

### 13.4 이벤트 발행

```lua
NetController.FireClient(player, "EventName", { ... })
NetController.FireAllClients("EventName", { ... })
```

---

## 14. 트러블슈팅 히스토리

### 14.1 Remote event queue exhausted

**원인**: 서버에서 이벤트를 보내지만 클라이언트에서 수신하는 리스너 없음  
**해결**: 각 서비스에 대응하는 클라이언트 컨트롤러 생성 (InventoryController 등)

### 14.2 Inventory.Drop이 월드 드롭 생성 안 함

**원인**: InventoryService.drop()은 슬롯만 비움, WorldDrop 생성 로직 없음  
**해결**: ServerInit에서 `Inventory.Drop.Request` 핸들러 오버라이드, WorldDropService.spawnDrop() 호출

### 14.3 move/split 검증 순서 버그

**원인**: 슬롯 범위 검증 전에 같은 슬롯 체크 → 잘못된 에러  
**해결**: `_validateSlotRange()` 먼저 호출 후 `fromSlot == toSlot` 체크

---

## 15. 참고 명령어

### Rojo 실행

```powershell
cd c:\YJS\Roblox\Origin-WILD
.\rojo.exe serve default.project.json
```

### 파일 구조 확인

```powershell
Get-ChildItem -Recurse src | Select-Object FullName
```

---

## 16. 연락처 / 추가 참고

- **게임명**: DinoTribeSurvival (디노트라이브서바이벌)
- **프로젝트폴더**: Origin-WILD
- **언어**: 한국어 UI + 한국어 주석

---

## 17. 완료: Phase 7 베이스 자동화

### 17.1 구현 완료

- `HarvestService.lua` - 자원 노드 수확 시스템
- `BaseClaimService.lua` - 베이스 영역 관리
- `AutoHarvestService.lua` - 팰 자동 수확
- `AutoDepositService.lua` - 시설 Output → Storage 자동 이동
- `ResourceNodeData.lua` - 자원 노드 데이터 (나무, 돌, 풀, 광석)

### 17.2 주요 API

```lua
-- HarvestService
HarvestService.registerNode(nodeId, position) → nodeUID
HarvestService.hit(player, nodeUID) → success, errorCode, drops
HarvestService.getAllNodes() → nodes[]

-- BaseClaimService
BaseClaimService.create(userId, position) → success, errorCode, baseId
BaseClaimService.getBase(userId) → BaseClaim?
BaseClaimService.isInBase(userId, position) → boolean
BaseClaimService.expand(userId) → success, errorCode

-- AutoHarvestService (자동 틱 처리)
AutoHarvestService.forceGather(structureId) → drops[]

-- AutoDepositService (자동 틱 처리)
AutoDepositService.depositFromFacility(structureId) → success, count
```

### 17.3 Balance 상수 (Phase 7)

```lua
-- 수확 시스템
Balance.HARVEST_COOLDOWN = 0.5         -- 연속 타격 쿨다운 (초)
Balance.HARVEST_RANGE = 5              -- 수확 가능 거리 (스터드)
Balance.HARVEST_XP_PER_HIT = 2         -- 타격당 XP

-- 베이스 시스템
Balance.BASE_DEFAULT_RADIUS = 30       -- 기본 베이스 반경
Balance.BASE_MAX_RADIUS = 100          -- 최대 베이스 반경
Balance.BASE_RADIUS_PER_LEVEL = 10     -- 레벨당 추가 반경
Balance.BASE_MAX_PER_PLAYER = 1        -- 플레이어당 최대 베이스 수

-- 자동화 시스템
Balance.AUTO_HARVEST_INTERVAL = 10     -- 팰 자동 수확 간격 (초)
Balance.AUTO_DEPOSIT_INTERVAL = 5      -- 자동 저장 간격 (초)
Balance.AUTO_DEPOSIT_RANGE = 20        -- Storage 검색 범위 (스터드)
```

### 17.4 Protocol 명령어 (Phase 7)

```lua
["Harvest.Hit.Request"] = true            -- 자원 수확 타격
["Harvest.GetNodes.Request"] = true       -- 활성 노드 목록 조회
["Base.Get.Request"] = true               -- 베이스 정보 조회
["Base.Expand.Request"] = true            -- 베이스 확장
```

### 17.5 새 시설: 채집 기지

```lua
{
  id = "GATHERING_POST",
  name = "채집 기지",
  description = "팰이 주변 자원을 자동으로 수집합니다.",
  functionType = "GATHERING",
  gatherRadius = 30,
  gatherInterval = 10,
  hasOutputSlot = true,
  outputSlots = 20,
}
```

### 17.6 자동화 작동 흐름

1. 플레이어가 첫 건물 설치 → BaseClaimService가 베이스 자동 생성
2. 채집 기지 건설 + GATHERING workType 팰 배치
3. AutoHarvestService가 매 10초마다 베이스 내 자원 자동 수확
4. 수확된 아이템이 채집 기지 Output에 저장
5. AutoDepositService가 매 5초마다 Output → 근처 Storage 자동 이동

---

## 18. 완료: Phase 8 퀘스트 시스템

### 18.1 구현 완료

- `QuestData.lua` - 15개 퀘스트 정의 (튜토리얼 5 + 메인 5 + 사이드 3 + 일일 2)
- `QuestService.lua` - 퀘스트 상태 관리, 진행 추적, 보상 지급
- `QuestController.lua` - 클라이언트 이벤트 수신
- 진행 추적 콜백 연동 (7개 서비스)

### 18.2 주요 API

```lua
-- QuestService (서버)
QuestService.Init(NetController, DataService, SaveService, InventoryService, PlayerStatService, PalboxService)
QuestService.getPlayerQuests(userId)           -- 플레이어 퀘스트 상태
QuestService.acceptQuest(player, questId)      -- 퀘스트 수락
QuestService.claimReward(player, questId)      -- 보상 수령
QuestService.abandonQuest(player, questId)     -- 퀘스트 포기

-- 진행 추적 (다른 서비스에서 호출)
QuestService.onHarvest(userId, nodeType, count)
QuestService.onKill(userId, creatureType, count)
QuestService.onCraft(userId, recipeId, count)
QuestService.onBuild(userId, facilityId)
QuestService.onCapture(userId, palType)
QuestService.onLevelUp(userId, newLevel)
QuestService.onTechUnlock(userId, techId)

-- QuestController (클라이언트)
QuestController.Init()
QuestController.getQuestCache()
QuestController.getActiveQuests()
QuestController.requestList(callback)
QuestController.requestAccept(questId, callback)
QuestController.requestClaim(questId, callback)
QuestController.requestAbandon(questId, callback)
QuestController.onUpdated(callback)
QuestController.onCompleted(callback)
```

### 18.3 Balance 상수 (Phase 8)

```lua
Balance.QUEST_MAX_ACTIVE = 10          -- 동시 진행 가능 퀘스트 수
Balance.QUEST_DAILY_RESET_HOUR = 0     -- 일일 퀘스트 리셋 시간 (UTC)
Balance.QUEST_ABANDON_COOLDOWN = 60    -- 퀘스트 포기 후 재수락 쿨다운 (초)
```

### 18.4 Protocol 명령어 (Phase 8)

```lua
["Quest.List.Request"] = true             -- 퀘스트 목록 요청
["Quest.Accept.Request"] = true           -- 퀘스트 수락
["Quest.Claim.Request"] = true            -- 보상 수령
["Quest.Abandon.Request"] = true          -- 퀘스트 포기
```

### 18.5 새 Enums (Phase 8)

```lua
-- 퀘스트 카테고리
Enums.QuestCategory = { TUTORIAL, MAIN, SIDE, DAILY, ACHIEVEMENT }

-- 퀘스트 목표 타입
Enums.QuestObjectiveType = { HARVEST, KILL, CRAFT, BUILD, COLLECT, CAPTURE, TALK, REACH_LEVEL, UNLOCK_TECH }

-- 퀘스트 상태
Enums.QuestStatus = { LOCKED, AVAILABLE, ACTIVE, COMPLETED, CLAIMED }

-- 에러 코드
QUEST_NOT_FOUND, QUEST_PREREQ_NOT_MET, QUEST_LEVEL_NOT_MET, QUEST_ALREADY_ACTIVE,
QUEST_NOT_COMPLETED, QUEST_ALREADY_CLAIMED, QUEST_MAX_ACTIVE, QUEST_NOT_REPEATABLE
```

### 18.6 퀘스트 데이터 요약

| 카테고리 | 개수 | 예시                                                         |
| -------- | ---- | ------------------------------------------------------------ |
| TUTORIAL | 5    | 첫 수확, 첫 제작, 첫 건설, 첫 사냥, 첫 포획                  |
| MAIN     | 5    | 거점 구축, 동료 모으기, 기술 연구, 레벨 10 달성, 자동화 시작 |
| SIDE     | 3    | 수집가, 사냥꾼, 장인                                         |
| DAILY    | 2    | 일일 수확, 일일 사냥                                         |

### 18.7 콜백 연동 서비스

| 서비스            | 콜백 함수          | 트리거         |
| ----------------- | ------------------ | -------------- |
| HarvestService    | SetQuestCallback   | 자원 수확 시   |
| CombatService     | SetQuestCallback   | 크리처 처치 시 |
| CraftingService   | SetQuestCallback   | 제작 완료 시   |
| BuildService      | SetQuestCallback   | 건설 완료 시   |
| CaptureService    | SetQuestCallback   | 포획 성공 시   |
| PlayerStatService | SetLevelUpCallback | 레벨업 시      |
| TechService       | SetUnlockCallback  | 기술 해금 시   |

---

## 19. 완료: Phase 9 NPC 상점 시스템

### 19.1 구현 파일

| 파일               | 역할                           |
| ------------------ | ------------------------------ |
| NPCShopData.lua    | 5개 상점 데이터 정의           |
| NPCShopService.lua | 서버 골드 관리, 구매/판매 처리 |
| ShopController.lua | 클라이언트 상점 캐시           |

### 19.2 상점 목록

| ID            | 이름      | NPC명         | 설명                    |
| ------------- | --------- | ------------- | ----------------------- |
| GENERAL_STORE | 잡화점    | 상인 톰       | 기본 소재 (Wood, Stone) |
| TOOL_SHOP     | 도구점    | 대장장이 한스 | 도구와 무기             |
| PAL_SHOP      | 팔 상점   | 조련사 미아   | 포획 도구 (Pal Sphere)  |
| FOOD_SHOP     | 식료품점  | 요리사 루시   | 음식과 물약             |
| BUILDING_SHOP | 건축 상점 | 건축가 로이   | 건축 자재               |

### 19.3 Balance 상수 (Phase 9)

```lua
Balance.SHOP_INTERACT_RANGE = 10     -- NPC 상호작용 거리
Balance.SHOP_DEFAULT_SELL_MULT = 0.5 -- 기본 판매 배율
Balance.SHOP_RESTOCK_TIME = 300      -- 재고 리필 시간
Balance.STARTING_GOLD = 100          -- 신규 플레이어 기본 골드
Balance.GOLD_CAP = 999999            -- 최대 보유 골드
Balance.GOLD_EARN_MULTIPLIER = 1.0   -- 골드 획득 배율
```

### 19.4 Protocol 명령어 (Phase 9)

```lua
["Shop.List.Request"]     -- 상점 목록 요청
["Shop.GetInfo.Request"]  -- 상점 상세 조회
["Shop.Buy.Request"]      -- 아이템 구매
["Shop.Sell.Request"]     -- 아이템 판매
["Shop.GetGold.Request"]  -- 골드 조회
```

### 19.5 에러 코드 (Phase 9)

| 코드              | 설명                    |
| ----------------- | ----------------------- |
| SHOP_NOT_FOUND    | 상점 없음               |
| INSUFFICIENT_GOLD | 골드 부족               |
| SHOP_OUT_OF_STOCK | 재고 부족               |
| ITEM_NOT_IN_SHOP  | 상점에 해당 아이템 없음 |
| ITEM_NOT_SELLABLE | 판매 불가 아이템        |
| SHOP_TOO_FAR      | 상점 거리 초과          |
| GOLD_CAP_REACHED  | 골드 한도 도달          |

### 19.6 API 요약

#### NPCShopService (Server)

```lua
NPCShopService.getGold(userId)                    -- 보유 골드 조회
NPCShopService.addGold(userId, amount)            -- 골드 추가
NPCShopService.removeGold(userId, amount)         -- 골드 차감
NPCShopService.getShopList()                      -- 전체 상점 목록
NPCShopService.getShopInfo(shopId)                -- 상점 상세
NPCShopService.buy(userId, shopId, itemId, count) -- 구매
NPCShopService.sell(userId, shopId, slot, count)  -- 판매
```

#### ShopController (Client)

```lua
ShopController.getGold()                                -- 캐시된 골드
ShopController.requestGold(callback)                    -- 서버 곢8드 요청
ShopController.requestShopList(callback)                -- 상점 목록 요청
ShopController.requestShopInfo(shopId, callback)        -- 상점 상세 요청
ShopController.requestBuy(shopId, itemId, count, cb)    -- 구매 요청
ShopController.requestSell(shopId, slot, count, cb)     -- 판매 요청
ShopController.onGoldChanged(callback)                  -- 곢8드 변경 리스너
```

---

_이 문서는 AI 에이전트 간 인수인계를 위해 작성됨. 모든 Phase 구현 시 위 패턴과 원칙 준수 필수._
