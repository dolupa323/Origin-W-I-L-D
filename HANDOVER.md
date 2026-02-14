# DinoTribeSurvival (Origin-WILD) 프로젝트 인수인계 문서

> **작성일**: 2026-02-14  
> **현재 진행 상태**: Phase 2-1 완료, Phase 2-2 대기  
> **게임 개요**: 로블록스 기반 공룡+생존 서바이벌 게임

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
Balance.BUILD_MIN_GROUND_DIST = 0.5
Balance.BUILD_COLLISION_RADIUS = 2
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
InventoryService.split(player, slot, count)              -- 분할
InventoryService.drop(player, slot, count?)              -- 드롭 (서버에서만 슬롯 비움)
InventoryService.canAdd(userId, itemId, count)           -- 추가 가능 여부
InventoryService.addItem(userId, itemId, count)          -- 아이템 추가

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

---

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

- [x] **2-1**: Build 전제조건 (Protocol, FacilityData, Enums, Balance)
- [ ] **2-2**: BuildService 구현 (다음 작업)

---

## 10. 다음 작업: Phase 2-2 BuildService

### 10.1 구현 목표

- `BuildService.lua` 생성
- 시설물 배치/해체/조회 기능

### 10.2 API 설계

```lua
BuildService.Init(NetController, DataService, InventoryService, SaveService)

BuildService.place(player, facilityId, position, rotation)
-- 검증: 거리, 충돌, 재료 소모, 구조물 Cap
-- 성공 시: 구조물 생성, Inventory 재료 차감

BuildService.remove(player, structureId)
-- 검증: 권한, 거리
-- 성공 시: 구조물 제거, 재료 일부 반환(?)

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

## 11. 코딩 컨벤션

### 11.1 파일명

- 서버 스크립트: `*.server.lua`
- 클라이언트 스크립트: `*.client.lua`
- 모듈: `*.lua`

### 11.2 서비스 패턴

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

### 11.3 핸들러 반환값

```lua
-- 성공
return { success = true, data = { ... } }

-- 실패
return { success = false, errorCode = Enums.ErrorCode.XXX }
```

### 11.4 이벤트 발행

```lua
NetController.FireClient(player, "EventName", { ... })
NetController.FireAllClients("EventName", { ... })
```

---

## 12. 트러블슈팅 히스토리

### 12.1 Remote event queue exhausted

**원인**: 서버에서 이벤트를 보내지만 클라이언트에서 수신하는 리스너 없음  
**해결**: 각 서비스에 대응하는 클라이언트 컨트롤러 생성 (InventoryController 등)

### 12.2 Inventory.Drop이 월드 드롭 생성 안 함

**원인**: InventoryService.drop()은 슬롯만 비움, WorldDrop 생성 로직 없음  
**해결**: ServerInit에서 `Inventory.Drop.Request` 핸들러 오버라이드, WorldDropService.spawnDrop() 호출

### 12.3 move/split 검증 순서 버그

**원인**: 슬롯 범위 검증 전에 같은 슬롯 체크 → 잘못된 에러  
**해결**: `_validateSlotRange()` 먼저 호출 후 `fromSlot == toSlot` 체크

---

## 13. 참고 명령어

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

## 14. 연락처 / 추가 참고

- **게임명**: DinoTribeSurvival (디노트라이브서바이벌)
- **프로젝트폴더**: Origin-WILD
- **언어**: 한국어 UI + 한국어 주석

---

_이 문서는 AI 에이전트 간 인수인계를 위해 작성됨. 모든 Phase 구현 시 위 패턴과 원칙 준수 필수._
