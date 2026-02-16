# Roblox Studio 작업 가이드

> **작성일**: 2026-02-16  
> **대상**: Roblox Studio 작업자  
> **프로젝트**: DinoTribeSurvival (Origin-WILD)  
> **현재 Phase**: Phase 9 완료 (NPC 상점 시스템)

---

## 1. 프로젝트 개요

### 1.1 게임 컨셉

- **장르**: 공룡+생존 서바이벌 게임 (팰월드 스타일)
- **핵심 루프**: 채집 → 제작 → 건설 → 포획 → 자동화
- **서버 권위**: 모든 게임 로직은 서버에서 처리 (SSOT 원칙)

### 1.2 Rojo 연동 방법

```powershell
cd c:\YJS\Roblox\Origin-WILD
.\rojo.exe serve default.project.json
```

Roblox Studio에서 Rojo 플러그인 → Connect

### 1.3 폴더 구조 (소스 → 스튜디오 매핑)

| 소스 경로                                 | 스튜디오 위치                      |
| ----------------------------------------- | ---------------------------------- |
| `src/ReplicatedStorage/`                  | ReplicatedStorage                  |
| `src/ServerScriptService/`                | ServerScriptService                |
| `src/StarterPlayer/StarterPlayerScripts/` | StarterPlayer.StarterPlayerScripts |

---

## 2. 스튜디오에서 생성해야 할 항목

### 2.1 Workspace 구조

#### 2.1.1 필수 폴더 생성

```
Workspace
├── ResourceNodes/        -- 채집 자원 노드 (나무, 바위 등)
├── Creatures/            -- 야생 크리처 스폰
├── Structures/           -- 플레이어 건설물
├── WorldDrops/           -- 월드 드롭 아이템
├── NPCs/                 -- NPC 상점 캐릭터
└── SpawnLocations/       -- 플레이어 스폰 위치
```

#### 2.1.2 ServerStorage 구조

```
ServerStorage
├── CreatureModels/       -- 크리처 프리팹
├── FacilityModels/       -- 시설 프리팹 (캠프파이어, 작업대 등)
├── ResourceNodeModels/   -- 자원 노드 프리팹
├── ItemModels/           -- 아이템 3D 모델 (드롭용)
└── NPCModels/            -- NPC 모델
```

---

## 3. 모델 & 에셋 요구사항

### 3.1 크리처 모델 (CreatureModels/)

| ID            | 이름         | 설명                     | 모델 이름          |
| ------------- | ------------ | ------------------------ | ------------------ |
| `RAPTOR`      | 랩터         | 빠른 소형 육식공룡, 선공 | `Raptor.rbxm`      |
| `TRICERATOPS` | 트리케라톱스 | 대형 초식공룡, 중립      | `Triceratops.rbxm` |
| `DODO`        | 도도새       | 약한 새, 도망형          | `Dodo.rbxm`        |

#### 크리처 모델 필수 구조:

```
[CreatureName] (Model)
├── HumanoidRootPart (Part, Anchored=false)
├── Humanoid (Humanoid)
│   └── Health = CreatureData.maxHealth
├── [BodyParts...] (Part)
└── CreatureId (StringValue) = "RAPTOR" 등
```

#### CreatureData.lua 참조 스탯:

```lua
RAPTOR = {
    maxHealth = 100,
    walkSpeed = 16,
    runSpeed = 24,
    damage = 10,
    attackRange = 5,
    detectRange = 30,
    behavior = "AGGRESSIVE"
}

TRICERATOPS = {
    maxHealth = 300,
    walkSpeed = 12,
    runSpeed = 20,
    damage = 25,
    attackRange = 8,
    detectRange = 20,
    behavior = "NEUTRAL"
}

DODO = {
    maxHealth = 20,
    walkSpeed = 8,
    runSpeed = 12,
    damage = 0,
    behavior = "PASSIVE"
}
```

---

### 3.2 시설 모델 (FacilityModels/)

| ID               | 이름       | 기능                 | 모델 이름            |
| ---------------- | ---------- | -------------------- | -------------------- |
| `CAMPFIRE`       | 캠프파이어 | 요리, 밤 안전지대    | `Campfire.rbxm`      |
| `STORAGE_BOX`    | 보관함     | 아이템 저장 (20슬롯) | `StorageBox.rbxm`    |
| `CRAFTING_TABLE` | 작업대     | 도구/장비 제작       | `CraftingTable.rbxm` |
| `SLEEPING_BAG`   | 침낭       | 리스폰 설정          | `SleepingBag.rbxm`   |
| `GATHERING_POST` | 채집 기지  | 자동 자원 수집       | `GatheringPost.rbxm` |

#### 시설 모델 필수 구조:

```
[FacilityName] (Model)
├── PrimaryPart (Part, Anchored=true)
├── InteractPoint (Part, Transparency=1) -- 상호작용 위치
├── FacilityId (StringValue) = "CAMPFIRE" 등
├── OwnerId (IntValue) = 0 -- 건설자 UserId
└── [Visual Parts...]
```

#### 시설별 특수 구조:

```
Campfire (요리 시설)
├── FireEffect (ParticleEmitter) -- 불 효과
├── LightSource (PointLight) -- 조명
└── SafeZone (Part, Transparency=1, Size=30,30,30) -- 밤 안전지대

StorageBox (저장 시설)
└── ProximityPrompt (ProximityPrompt, ActionText="열기")

CraftingTable (제작 시설)
└── ProximityPrompt (ProximityPrompt, ActionText="제작하기")
```

#### FacilityData.lua 참조:

```lua
CAMPFIRE = {
    requirements = { WOOD x5, STONE x2 },
    maxHealth = 100,
    interactRange = 5,
    functionType = "COOKING",
    fuelConsumption = 1  -- 초당 연료 1 소모
}

STORAGE_BOX = {
    requirements = { WOOD x10, FIBER x5 },
    storageSlots = 20
}

CRAFTING_TABLE = {
    requirements = { WOOD x15, STONE x5, FLINT x3 },
    queueMax = 10
}
```

---

### 3.3 자원 노드 모델 (ResourceNodeModels/)

| ID            | 이름        | 필요 도구 | 자원             | 모델 이름         |
| ------------- | ----------- | --------- | ---------------- | ----------------- |
| `TREE_OAK`    | 참나무      | 도끼      | 나무 3-5개       | `TreeOak.rbxm`    |
| `TREE_PINE`   | 소나무      | 도끼      | 나무 4-6개, 수지 | `TreePine.rbxm`   |
| `ROCK_NORMAL` | 바위        | 곡괭이    | 돌 2-4개, 부싯돌 | `RockNormal.rbxm` |
| `ROCK_IRON`   | 철광석 바위 | 곡괭이    | 철광석 1-3개     | `RockIron.rbxm`   |
| `BUSH_BERRY`  | 베리 덤불   | 맨손      | 베리 2-5개       | `BushBerry.rbxm`  |
| `FIBER_GRASS` | 풀          | 맨손      | 섬유 2-4개       | `FiberGrass.rbxm` |

#### 자원 노드 모델 필수 구조:

```
[NodeName] (Model)
├── PrimaryPart (Part, Anchored=true)
├── NodeId (StringValue) = "TREE_OAK" 등
├── HitsRemaining (IntValue) = maxHits
├── Depleted (BoolValue) = false
└── [Visual Parts...]
```

#### ResourceNodeData.lua 참조:

```lua
TREE_OAK = {
    nodeType = "TREE",
    requiredTool = "AXE",
    maxHits = 5,
    respawnTime = 300,  -- 5분
    resources = { WOOD min=3 max=5 }
}

ROCK_NORMAL = {
    nodeType = "ROCK",
    requiredTool = "PICKAXE",
    maxHits = 4,
    respawnTime = 240,  -- 4분
    resources = { STONE min=2 max=4, FLINT min=0 max=1 (30%) }
}

FIBER_GRASS = {
    nodeType = "FIBER",
    requiredTool = nil,  -- 맨손 가능
    maxHits = 2,
    respawnTime = 120   -- 2분
}
```

---

### 3.4 아이템 모델 (ItemModels/)

월드 드롭 시 표시될 3D 모델. 모델명 = ItemId

| ID                     | 이름          | 타입        | 모델 예시        |
| ---------------------- | ------------- | ----------- | ---------------- |
| `STONE`                | 돌            | 자원        | 작은 회색 돌     |
| `WOOD`                 | 나무          | 자원        | 나무 통나무      |
| `FIBER`                | 섬유          | 자원        | 풀 묶음          |
| `FLINT`                | 부싯돌        | 자원        | 날카로운 돌      |
| `MEAT`                 | 생고기        | 자원        | 붉은 고기        |
| `LEATHER`              | 가죽          | 자원        | 갈색 가죽        |
| `HORN`                 | 뿔            | 자원 (희귀) | 뾰족한 뿔        |
| `STONE_PICKAXE`        | 돌 곡괭이     | 도구        | 곡괭이 모양      |
| `STONE_AXE`            | 돌 도끼       | 도구        | 도끼 모양        |
| `CAPTURE_SPHERE_BASIC` | 기본 포획구   | 소모품      | 구형             |
| `CAPTURE_SPHERE_MEGA`  | 고급 포획구   | 소모품      | 구형 (색상 다름) |
| `CAPTURE_SPHERE_ULTRA` | 마스터 포획구 | 소모품      | 구형 (고급 색상) |

#### 아이템 모델 필수 구조:

```
[ItemId] (Model)
├── PrimaryPart (Part, Anchored=true in template, false when dropped)
├── ItemId (StringValue) = "STONE" 등
└── [Visual Parts...]
```

---

### 3.5 NPC 모델 (NPCModels/)

| 상점 ID         | NPC 이름      | 역할      | 모델 이름      |
| --------------- | ------------- | --------- | -------------- |
| `GENERAL_STORE` | 상인 톰       | 잡화점    | `NPCTom.rbxm`  |
| `TOOL_SHOP`     | 대장장이 한스 | 도구점    | `NPCHans.rbxm` |
| `PAL_SHOP`      | 조련사 미아   | 팰 상점   | `NPCMia.rbxm`  |
| `FOOD_SHOP`     | 요리사 루시   | 식료품점  | `NPCLucy.rbxm` |
| `BUILDING_SHOP` | 건축가 벤     | 건축 상점 | `NPCBen.rbxm`  |

#### NPC 모델 필수 구조:

```
[NPCName] (Model)
├── HumanoidRootPart (Part, Anchored=true)
├── Humanoid (Humanoid)
├── ShopId (StringValue) = "GENERAL_STORE" 등
├── ProximityPrompt (ProximityPrompt)
│   ├── ObjectText = "상인 톰"
│   ├── ActionText = "대화하기"
│   └── MaxActivationDistance = 10
└── [Body Parts...]
```

#### NPCShopData.lua 참조:

```lua
GENERAL_STORE = {
    npcName = "상인 톰",
    buyList = {  -- 플레이어가 구매 가능
        WOOD: 5골드, STONE: 3골드, FIBER: 2골드
    },
    sellList = {  -- 플레이어가 판매 가능
        WOOD: 2골드, STONE: 1골드, RAW_MEAT: 8골드
    }
}

TOOL_SHOP = {
    npcName = "대장장이 한스",
    buyList = {
        STONE_PICKAXE: 50골드, STONE_AXE: 50골드
    },
    sellMultiplier = 0.3  -- 30% 가격에 구매
}
```

---

## 4. 게임 메커니즘 참조

### 4.1 밸런스 상수 (Balance.lua)

스튜디오에서 맵 디자인 시 참조해야 할 핵심 수치:

```lua
-- 시간
DAY_LENGTH = 2400초 (40분)
DAY_DURATION = 1800초 (30분 낮)
NIGHT_DURATION = 600초 (10분 밤)

-- 인벤토리
INV_SLOTS = 20
MAX_STACK = 99

-- 드롭
DROP_CAP = 400 (서버 전체 최대)
DROP_MERGE_RADIUS = 5 스터드
DROP_DESPAWN_DEFAULT = 300초 (5분)
DROP_LOOT_RANGE = 10 스터드

-- 건설
BUILD_STRUCTURE_CAP = 500 (서버 전체)
BUILD_RANGE = 20 스터드

-- 크리처
WILDLIFE_CAP = 250 (서버 전체)
CREATURE_COOLDOWN = 600초 (10분 리스폰)

-- 베이스
BASE_DEFAULT_RADIUS = 30 스터드
BASE_MAX_RADIUS = 100 스터드

-- 포획
CAPTURE_RANGE = 30 스터드
MAX_PALBOX = 30
MAX_PARTY = 5

-- 상점
SHOP_INTERACT_RANGE = 10 스터드
STARTING_GOLD = 100
GOLD_CAP = 999999
```

---

### 4.2 크리처 행동 패턴

| 행동         | 설명                       | 적용 크리처  |
| ------------ | -------------------------- | ------------ |
| `AGGRESSIVE` | 감지 범위 내 플레이어 선공 | 랩터         |
| `NEUTRAL`    | 공격받으면 반격            | 트리케라톱스 |
| `PASSIVE`    | 공격받으면 도망            | 도도새       |

---

### 4.3 포획 시스템

#### 포획률 공식:

```
포획확률 = baseRate × (1 - currentHP/maxHP) × captureMultiplier
```

- HP가 낮을수록 포획 확률 증가
- 포획구 등급에 따라 배율 적용

| 포획구 | 배율 |
| ------ | ---- |
| 기본   | 1.0x |
| 고급   | 1.5x |
| 마스터 | 2.5x |

---

### 4.4 밤 시스템

- 밤 시간: 600초 (10분)
- NIGHT 페이즈 동안 모닥불 없으면 `Freezing` 디버프
- 캠프파이어 SafeZone (30 스터드) 내에 있으면 안전

---

## 5. UI 구현 참조

### 5.1 필요한 UI 목록

| UI             | 설명                  | 연동 컨트롤러       |
| -------------- | --------------------- | ------------------- |
| 인벤토리       | 20슬롯 그리드         | InventoryController |
| 퀵슬롯         | 하단 5-10슬롯         | InventoryController |
| HP/스태미나 바 | 플레이어 상태         | PlayerLifeService   |
| 시간 표시      | 낮/밤 아이콘          | TimeController      |
| 제작 메뉴      | 레시피 목록           | CraftController     |
| 건설 메뉴      | 시설 목록             | BuildController     |
| 퀘스트 UI      | 활성 퀘스트 목록      | QuestController     |
| 상점 UI        | 상점 아이템 목록      | ShopController      |
| 골드 표시      | 현재 보유 골드        | ShopController      |
| 팰 파티        | 동행 팰 목록 (5슬롯)  | PartyService        |
| 팰 보관함      | 보관 팰 목록 (30슬롯) | PalboxService       |

---

### 5.2 클라이언트 이벤트 목록

NetClient가 수신하는 주요 이벤트:

```lua
-- 인벤토리
"Inventory.Changed" → 슬롯 변경
"Inventory.Full" → 공간 부족

-- 월드 드롭
"WorldDrop.Spawned" → 드롭 생성
"WorldDrop.Despawned" → 드롭 제거
"WorldDrop.Merged" → 드롭 병합

-- 시간
"Time.PhaseChanged" → 낮/밤 전환

-- 건설/제작
"Build.Placed" → 건물 배치
"Craft.QueueUpdated" → 제작 상태

-- 퀘스트
"Quest.Updated" → 퀘스트 진행
"Quest.Completed" → 퀘스트 완료

-- 상점
"Shop.GoldChanged" → 골드 변경
```

---

## 6. 맵 디자인 가이드라인

### 6.1 월드 레이아웃 권장

```
[스폰 지역] (중앙)
├── 초보자 구역: 도도새, 베리 덤불, 풀
├── 중급 구역: 랩터, 참나무, 바위
└── 고급 구역: 트리케라톱스, 철광석

[상점 마을] (스폰 근처)
├── 5개 NPC 상점 배치
└── 안전 지역 (크리처 미스폰)

[자원 밀집 지역]
├── 숲: 참나무, 소나무 밀집
├── 채석장: 바위, 철광석 바위 밀집
└── 평원: 풀, 베리 덤불 밀집
```

### 6.2 크리처 스폰 구역

- 도넛 형태 스폰 (중앙 반경 외곽)
- Raycast로 지면 확인
- 최대 250마리 서버 전체 제한

---

## 7. 테스트 체크리스트

### 7.1 코어 시스템

- [ ] 플레이어 스폰 위치 확인
- [ ] 인벤토리 20슬롯 작동
- [ ] 아이템 드롭 → 월드 드롭 생성
- [ ] 아이템 루팅 (10 스터드 내)

### 7.2 자원 채집

- [ ] 맨손 풀 채집 가능
- [ ] 도끼로 나무 채집
- [ ] 곡괭이로 바위 채집
- [ ] 노드 고갈 → 리스폰 확인

### 7.3 크리처 시스템

- [ ] 크리처 스폰 확인
- [ ] AI 행동 (선공/중립/도망)
- [ ] 전투 데미지 처리
- [ ] 드롭 아이템 생성

### 7.4 제작/건설

- [ ] 작업대 제작 메뉴
- [ ] 레시피 제작 완료
- [ ] 시설 배치 (캠프파이어)
- [ ] 연료 시스템 (나무 연료)

### 7.5 포획/팰

- [ ] 포획구 사용
- [ ] 포획 성공/실패
- [ ] 팰 보관함 저장
- [ ] 팰 소환/파티 편성

### 7.6 퀘스트

- [ ] 자동 퀘스트 부여
- [ ] 진행 상황 추적
- [ ] 보상 수령

### 7.7 상점

- [ ] NPC 상호작용
- [ ] 아이템 구매 (골드 차감)
- [ ] 아이템 판매 (골드 획득)

---

## 8. 디버그 명령어

ServerScriptService/Server/Debug/ 폴더에 디버그 도구 스크립트 있음.
개발 중 테스트에 활용 가능.

```lua
-- 예시: 아이템 지급
InventoryService.addItem(player.UserId, "STONE_PICKAXE", 1)

-- 예시: 골드 지급
NPCShopService.addGold(player.UserId, 1000)

-- 예시: 레벨업
PlayerStatService.addXP(player.UserId, 500)
```

---

## 9. 참고 문서

- [HANDOVER.md](../HANDOVER.md) - 전체 프로젝트 인수인계 문서
- [Phase9_Plan.md](./Phase9_Plan.md) - Phase 9 상점 시스템 계획

---

_이 문서는 Roblox Studio 작업자를 위해 작성됨. 코드 수정 시 HANDOVER.md와 소스 코드 동기화 필수._
