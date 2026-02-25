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

**위치**: `ReplicatedStorage/Assets/CreatureModels/`

| ID            | 이름         | 설명                     | 권장 모델 이름 |
| ------------- | ------------ | ------------------------ | -------------- |
| `RAPTOR`      | 랩터         | 빠른 소형 육식공룡, 선공 | `Raptor`       |
| `TRICERATOPS` | 트리케라톱스 | 대형 초식공룡, 중립      | `Triceratops`  |
| `DODO`        | 도도새       | 약한 새, 도망형          | `DodoBird`     |

#### 모델 배치 방법 (Toolbox에서 가져오기):

1. **Roblox Studio** → View → Toolbox
2. 원하는 동물/공룡 모델 검색 (예: "Dodo Bird", "Raptor", "Triceratops")
3. 모델을 **ReplicatedStorage/Assets/CreatureModels** 폴더에 배치
4. 끝! (스크립트, GUI, 사운드는 자동 제거됨)

```
ReplicatedStorage
└── Assets
    └── CreatureModels
        ├── DodoBird (Model)      ← Toolbox에서 가져온 그대로
        ├── Raptor (Model)
        ├── Triceratops (Model)
        └── [기타 모델...]
```

#### 유연한 모델 매칭 시스템:

CreatureService는 다음 순서로 모델을 찾습니다:

1. **정확한 이름** 매칭 (예: `DodoBird`)
2. **creatureId** 매칭 (예: `DODO`)
3. **대소문자 무시** 매칭 (예: `dodobird`, `DODOBIRD`)
4. **부분 문자열** 매칭 (예: `VelociraptorModel` → `RAPTOR`)

> **중요**: 어떤 모델 구조든 자동 처리됩니다.
>
> - HumanoidRootPart 없음 → 자동 생성
> - Humanoid 없음 → 자동 생성
> - 파트 연결 안됨 → WeldConstraint 자동 생성
> - 기존 스크립트/사운드/GUI → 자동 제거

#### 모델 없으면 플레이스홀더 사용:

모델이 없으면 임시 플레이스홀더(2x2x2 랜덤색상 박스)가 생성됩니다.
Output에서 `[CreatureService] Model 'X' not found` 경고를 확인하세요.

#### CreatureData.lua 참조 스탯 (권장):

```lua
DODO = {
    maxHealth = 30,
    maxTorpor = 20,
    damage = 0,
    behavior = "PASSIVE"
}

RAPTOR = {
    maxHealth = 150,
    maxTorpor = 120,
    damage = 15,
    behavior = "AGGRESSIVE"
}

TRICERATOPS = {
    maxHealth = 1200,
    maxTorpor = 1000,
    damage = 40,
    behavior = "NEUTRAL"
}
```

---

### 3.2 시설 모델 (FacilityModels/)

| ID               | 이름       | 기능                 | 모델 이름            |
| ---------------- | ---------- | -------------------- | -------------------- |
| `CAMPFIRE`       | 캠프파이어 | 요리, 밤 안전지대    | `Campfire.rbxm`      |
| `STORAGE_BOX`    | 보관함     | 아이템 저장 (20슬롯) | `StorageBox.rbxm`    |
| `PRIMITIVE_WORKBENCH` | 원시 작업대 | 도구/장비 제작       | `PrimitiveWorkbench.rbxm` |
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
    storageSlots = 20,
    techLevel = 10
}

PRIMITIVE_WORKBENCH = {
    requirements = { WOOD x15, STONE x5 },
    queueMax = 10,
    techLevel = 10
}
```

---

### 3.3 자원 노드 모델 (ResourceNodeModels/)

**유연한 모델 로딩 시스템** - Toolbox에서 가져온 어떤 구조의 모델도 자원 노드로 변환됩니다.

| ID            | 이름        | 필요 도구 | 자원             | modelName (권장) |
| ------------- | ----------- | --------- | ---------------- | ---------------- |
| `TREE_OAK`    | 참나무      | 도끼      | 나무 3-5개       | `OakTree`        |
| `TREE_PINE`   | 소나무      | 도끼      | 나무 4-6개, 수지 | `PineTree`       |
| `ROCK_NORMAL` | 바위        | 곡괭이    | 돌 2-4개, 부싯돌 | `Rock`           |
| `ORE_IRON`    | 철 광맥     | 곡괭이    | 철광석 4-8개     | `IronOre`        |
| `BUSH_BERRY`  | 베리 덤불   | 맨손      | 베리 2-5개       | `BerryBush`      |
| `FIBER_GRASS` | 풀          | 맨손      | 섬유 2-4개       | `Grass`          |
| `ORE_COAL`    | 석탄 광맥   | 곡괭이    | 석탄 2-4개       | `CoalOre`        |
| `ORE_GOLD`    | 금 광맥     | 곡괭이    | 금광석 1-2개     | `GoldOre`        |

#### Toolbox 모델 사용 방법:

1. **Toolbox에서 원하는 나무/바위/광석 모델 검색**
2. **ReplicatedStorage/Assets/ResourceNodeModels/ 폴더에 배치**
3. **ResourceNodeData.lua의 modelName 필드에 모델 이름 지정**

```
ReplicatedStorage/
└── Assets/
    └── ResourceNodeModels/
        ├── OakTree         -- Toolbox에서 가져온 참나무 모델
        ├── PineTree        -- Toolbox에서 가져온 소나무 모델
        ├── Rock            -- Toolbox에서 가져온 바위 모델
        ├── IronRock        -- 철광석 바위 (빛나는 효과 추가)
        └── BerryBush       -- 베리 덤불 모델
```

#### 자동 모델 설정 (setupModelForNode):

HarvestService가 자동으로 처리하는 것들:

- **스크립트 제거**: Script, LocalScript, ModuleScript 자동 제거
- **사운드/GUI 제거**: Sound, BillboardGui, SurfaceGui 자동 제거
- **Anchored 설정**: 모든 파트를 Anchored=true로 설정
- **Humanoid 제거**: Humanoid가 있으면 제거 (NPC용 모델도 사용 가능)
- **PrimaryPart 자동 탐색**: PrimaryPart → HumanoidRootPart → 첫 번째 BasePart
- **CollectionService 태그**: "ResourceNode" 태그 자동 추가

#### 모델 이름 매칭 규칙 (findResourceModel):

1. **정확한 이름**: `modelName`과 정확히 일치
2. **nodeId 매칭**: `TREE_OAK` → `Tree_Oak`, `TreeOak`
3. **대소문자 무시**: `oaktree` = `OakTree` = `OAKTREE`
4. **부분 매칭**: `OakTreeModel` → `oak` 포함 시 매칭
5. **nodeType 매칭**: `TREE_*` → `tree` 포함 모델 검색

#### ResourceNodeData.lua 예시:

```lua
{
    id = "TREE_OAK",
    name = "참나무",
    modelName = "OakTree",  -- Assets/ResourceNodeModels/OakTree
    nodeType = "TREE",
    optimalTool = "AXE",
    resources = {
        { itemId = "WOOD", min = 3, max = 5, weight = 1.0 }
    },
    maxHits = 5,
    respawnTime = 300,  -- 5분
    xpPerHit = 2,
}

{
    id = "ORE_IRON",
    name = "철 광맥",
    modelName = "IronOre",  -- Assets/ResourceNodeModels/IronOre
    nodeType = "ORE",
    optimalTool = "PICKAXE",
    resources = {
        { itemId = "IRON_ORE", min = 4, max = 8, weight = 1.0 },
        { itemId = "COAL", min = 1, max = 2, weight = 0.3 },
    },
    maxHits = 8,
    respawnTime = 600,
    xpPerHit = 6,
}
```

#### 모델 없을 때 폴백:

모델을 찾지 못하면 자동으로 플레이스홀더 생성:

- **TREE**: 갈색 원기둥 (나무 줄기)
- **ROCK/ORE**: 회색 구형 (바위)
- **BUSH/FIBER**: 녹색 작은 박스 (풀)

---

### 3.3.1 자원 노드 자동 스폰 시스템

**공룡 스폰과 동일한 방식으로 자원 노드도 자동 스폰됩니다.**

#### 스폰 규칙:

| 지형 Material                | 스폰되는 자원                 |
| ---------------------------- | ----------------------------- |
| Grass, LeafyGrass            | 참나무, 소나무, 베리 덤불, 풀 |
| Rock, Slate, Basalt, Granite | 바위, 철광석 바위, 석탄       |
| Sand, Sandstone              | 바위, 풀                      |
| Ground, Mud                  | 참나무, 바위, 베리 덤불, 풀   |

#### 자동 스폰 흐름:

```
1. 플레이어 주변 20~60 studs 범위에서 스폰 위치 검색
2. Raycast로 지형 Material 확인
3. Material에 맞는 자원 노드 선택 (풀밭→나무, 바위→광석)
4. Assets/ResourceNodeModels에서 모델 복제
5. workspace.ResourceNodes에 배치
6. 플레이어가 150 studs 이상 멀어지면 디스폰
```

#### 채집 → 드롭 → 리스폰 흐름:

```
1. 플레이어가 자원 노드 채집 (E키 또는 도구 사용)
2. 채집 완료 시:
   - 노드 모델 투명화 (Transparency=1, CanCollide=false, CanQuery=false)
   - 월드 드롭 생성 (WorldDropService.spawnDrop)
   - 드롭된 아이템은 3D 시각화 + ProximityPrompt로 루팅 가능
3. respawnTime 후 노드 복원 (모델 다시 보임, 채집 가능)
```

#### Balance.lua 설정:

```lua
Balance.RESOURCE_NODE_CAP = 100    -- 자동 스폰 노드 최대 수
Balance.NODE_SPAWN_INTERVAL = 20   -- 스폰 간격 (초)
Balance.NODE_DESPAWN_DIST = 150    -- 디스폰 거리
```

#### 수동 배치 vs 자동 스폰:

| 구분      | 수동 배치                                      | 자동 스폰                                |
| --------- | ---------------------------------------------- | ---------------------------------------- |
| 배치 방법 | Studio에서 workspace.ResourceNodes에 직접 배치 | HarvestService.\_spawnLoop()가 자동 생성 |
| 속성      | `AutoSpawned = nil`                            | `AutoSpawned = true`                     |
| 디스폰    | 안됨 (항상 유지)                               | 플레이어와 멀면 디스폰                   |
| 리스폰    | respawnTime 후 같은 위치에 복원                | respawnTime 후 같은 위치에 복원          |

---

### 3.3.2 자원 노드 채집 판정 파트 배치 가이드

> **중요**: 자원 노드 모델에는 반드시 채집 판정용 파트(Hitbox 또는 InteractPart)가 포함되어야 하며, 이 파트의 위치는 플레이어가 채집 시 접근하는 시선 위치(몸통, 표면 등)에 배치해야 합니다.
>
> - 모델 하위에 `Hitbox` 또는 `InteractPart` 파트를 추가
> - 판정 파트는 투명(Transparency=1)으로 설정 가능, 크기와 위치는 상호작용이 자연스럽게 이루어지도록 조정
> - 판정 파트가 없으면 채집이 불가능하거나 판정이 어색해질 수 있음
> - 모델링 시 반드시 판정 파트 위치를 플레이어 접근 위치에 맞게 배치

#### 예시 구조:

```
OakTree (Model)
├── Hitbox (Part, Transparency=1, Size=3,3,3, 위치=몸통 중앙)
├── [Visual Parts...]
```

HarvestService와 InteractController는 판정 파트를 우선 탐색하며, 없을 경우 PrimaryPart 또는 첫 BasePart를 사용합니다.

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
| `VINE_BOLA`            | 넝쿨 볼라     | 소모품      | 투척용 볼라      |
| `BONE_BOLA`            | 뼈 볼라       | 소모품      | 투척용 볼라      |
| `BRONZE_BOLA`          | 청동 볼라     | 소모품      | 포획용 볼라      |
| `IRON_BOLA`            | 철제 볼라     | 소모품      | 포획용 볼라      |

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

| 볼라 티어 | 배율 |
| ------ | ---- |
| 1단 (넝쿨) | 1.0x |
| 2단 (뼈)   | 1.5x |
| 3단 (청동) | 2.0x |
| 4단 (철제) | 3.5x |

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
