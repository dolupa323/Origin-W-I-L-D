# 데이터 테이블 요약

> **프로젝트**: DinoTribeSurvival (Origin-WILD)  
> **경로**: `src/ReplicatedStorage/Data/`

---

## 1. ItemData.lua - 아이템 정의

### 자원 아이템

| ID        | 이름   | 스택 | 설명                   |
| --------- | ------ | ---- | ---------------------- |
| `STONE`   | 돌     | 99   | 기본 자원              |
| `WOOD`    | 나무   | 99   | 건축 재료, 연료 (15초) |
| `FIBER`   | 섬유   | 99   | 밧줄/천 재료           |
| `FLINT`   | 부싯돌 | 99   | 도구 재료              |
| `MEAT`    | 생고기 | 99   | 요리 재료              |
| `LEATHER` | 가죽   | 99   | 방어구 재료            |
| `FEATHER` | 깃털   | 99   | 화살/침낭 재료         |
| `HORN`    | 뿔     | 50   | 희귀, 고급 장비 재료   |

### 도구 아이템

| ID              | 이름      | 내구도 | 용도      |
| --------------- | --------- | ------ | --------- |
| `STONE_PICKAXE` | 돌 곡괭이 | 100    | 바위 채집 |
| `STONE_AXE`     | 돌 도끼   | 100    | 나무 채집 |

### 포획 아이템

| ID                     | 이름          | 배율 | 스택 |
| ---------------------- | ------------- | ---- | ---- |
| `CAPTURE_SPHERE_BASIC` | 기본 포획구   | 1.0x | 20   |
| `CAPTURE_SPHERE_MEGA`  | 고급 포획구   | 1.5x | 15   |
| `CAPTURE_SPHERE_ULTRA` | 마스터 포획구 | 2.5x | 10   |

---

## 2. CreatureData.lua - 크리처 정의

| ID            | 이름         | HP  | 이동속도 | 공격력 | 행동 | 모델명      |
| ------------- | ------------ | --- | -------- | ------ | ---- | ----------- |
| `RAPTOR`      | 랩터         | 100 | 16/24    | 10     | 선공 | Raptor      |
| `TRICERATOPS` | 트리케라톱스 | 300 | 12/20    | 25     | 중립 | Triceratops |
| `DODO`        | 도도새       | 20  | 8/12     | 0      | 도망 | Dodo        |

---

## 3. PalData.lua - 팰 데이터

| creatureId    | 포획률 | 작업 타입         | workPower | 패시브 스킬   |
| ------------- | ------ | ----------------- | --------- | ------------- |
| `RAPTOR`      | 25%    | TRANSPORT, COMBAT | 2         | 이동속도 +10% |
| `TRICERATOPS` | 15%    | MINING, TRANSPORT | 4         | 방어력 +15%   |
| `DODO`        | 60%    | FARMING           | 1         | 채집량 +20%   |

---

## 4. DropTableData.lua - 드롭 테이블

| 크리처      | 드롭 아이템 | 확률 | 수량 |
| ----------- | ----------- | ---- | ---- |
| RAPTOR      | MEAT        | 100% | 1-2  |
| RAPTOR      | LEATHER     | 50%  | 1-2  |
| TRICERATOPS | MEAT        | 100% | 3-5  |
| TRICERATOPS | LEATHER     | 80%  | 2-4  |
| TRICERATOPS | HORN        | 30%  | 1    |
| DODO        | MEAT        | 100% | 1    |
| DODO        | FEATHER     | 70%  | 1-3  |

---

## 5. FacilityData.lua - 시설 정의

| ID               | 이름       | 기능   | 건설 재료                 | HP  | 특수      |
| ---------------- | ---------- | ------ | ------------------------- | --- | --------- |
| `CAMPFIRE`       | 캠프파이어 | 요리   | WOOD×5, STONE×2           | 100 | 연료 소모 |
| `STORAGE_BOX`    | 보관함     | 저장   | WOOD×10, FIBER×5          | 150 | 20슬롯    |
| `CRAFTING_TABLE` | 작업대     | 제작   | WOOD×15, STONE×5, FLINT×3 | 200 | 큐 10개   |
| `SLEEPING_BAG`   | 침낭       | 리스폰 | FIBER×20, WOOD×5          | 50  | -         |
| `GATHERING_POST` | 채집 기지  | 자동화 | WOOD×20, STONE×10         | 200 | 팰 배치   |

---

## 6. ResourceNodeData.lua - 자원 노드

### 나무 (AXE 필요)

| ID          | 이름   | 타격 | 리스폰 | 자원                |
| ----------- | ------ | ---- | ------ | ------------------- |
| `TREE_OAK`  | 참나무 | 5회  | 300초  | WOOD 3-5            |
| `TREE_PINE` | 소나무 | 6회  | 360초  | WOOD 4-6, RESIN 0-1 |

### 바위 (PICKAXE 필요)

| ID            | 이름        | 타격 | 리스폰 | 자원                 |
| ------------- | ----------- | ---- | ------ | -------------------- |
| `ROCK_NORMAL` | 바위        | 4회  | 240초  | STONE 2-4, FLINT 0-1 |
| `ROCK_IRON`   | 철광석 바위 | 6회  | 480초  | IRON_ORE 1-3         |

### 맨손 채집

| ID            | 이름      | 타격 | 리스폰 | 자원      |
| ------------- | --------- | ---- | ------ | --------- |
| `BUSH_BERRY`  | 베리 덤불 | 3회  | 180초  | BERRY 2-5 |
| `FIBER_GRASS` | 풀        | 2회  | 120초  | FIBER 2-4 |

---

## 7. RecipeData.lua - 레시피

| ID                           | 결과물          | 재료                               | 시설   | 시간 | 테크레벨 |
| ---------------------------- | --------------- | ---------------------------------- | ------ | ---- | -------- |
| `CRAFT_STONE_PICKAXE`        | 돌 곡괭이 ×1    | STONE×3, WOOD×2, FIBER×5           | 작업대 | 3초  | 0        |
| `CRAFT_STONE_AXE`            | 돌 도끼 ×1      | STONE×2, WOOD×3, FIBER×5           | 작업대 | 3초  | 0        |
| `CRAFT_CAMPFIRE_KIT`         | 캠프파이어 키트 | WOOD×5, STONE×2                    | 맨손   | 0초  | 0        |
| `CRAFT_CAPTURE_SPHERE_BASIC` | 기본 포획구 ×3  | STONE×5, WOOD×3, FIBER×10          | 작업대 | 5초  | 0        |
| `CRAFT_CAPTURE_SPHERE_MEGA`  | 고급 포획구 ×2  | STONE×10, WOOD×5, FIBER×15, HORN×1 | 작업대 | 10초 | 1        |

---

## 8. TechUnlockData.lua - 기술 트리

### Tier 0 (시작 해금)

| ID            | 이름      | 비용 | 해금 내용 |
| ------------- | --------- | ---- | --------- |
| `TECH_BASICS` | 기초 지식 | 0    | 기본 기능 |

### Tier 1 (레벨 1-5)

| ID                 | 이름       | 비용 | 선행   | 해금 내용           |
| ------------------ | ---------- | ---- | ------ | ------------------- |
| `TECH_STONE_TOOLS` | 석기 도구  | 1    | BASICS | 곡괭이, 도끼 레시피 |
| `TECH_FIBER_CRAFT` | 섬유 가공  | 1    | BASICS | 밧줄 등             |
| `TECH_CAMPFIRE`    | 캠프파이어 | 1    | BASICS | 캠프파이어 시설     |

### Tier 2 (레벨 5-15)

| ID                   | 이름        | 비용 | 선행          | 해금 내용              |
| -------------------- | ----------- | ---- | ------------- | ---------------------- |
| `TECH_WORKBENCH`     | 작업대      | 2    | STONE_TOOLS   | 작업대 시설            |
| `TECH_CAPTURE_BASIC` | 기본 포획술 | 2    | FIBER_CRAFT   | 포획 기능, 기본 포획구 |
| `TECH_CAPTURE_ADV`   | 고급 포획술 | 3    | CAPTURE_BASIC | 고급 포획구            |

---

## 9. QuestData.lua - 퀘스트

### 튜토리얼 (TUTORIAL)

| ID                       | 이름    | 목표             | 보상                  |
| ------------------------ | ------- | ---------------- | --------------------- |
| `QUEST_TUTORIAL_HARVEST` | 첫 수확 | 나무 3회 수확    | XP 50, WOOD×10        |
| `QUEST_TUTORIAL_CRAFT`   | 첫 제작 | 나무 도끼 제작   | XP 100                |
| `QUEST_TUTORIAL_BUILD`   | 첫 건설 | 모닥불 설치      | XP 100, STONE×20      |
| `QUEST_TUTORIAL_HUNT`    | 첫 사냥 | 도도 1마리 처치  | XP 150                |
| `QUEST_TUTORIAL_CAPTURE` | 첫 포획 | 아무 크리처 포획 | XP 200, 기본 포획구×5 |

### 메인 스토리 (MAIN)

| ID                 | 이름         | 목표                          | 보상                  |
| ------------------ | ------------ | ----------------------------- | --------------------- |
| `QUEST_MAIN_BASE`  | 거점 구축    | 캠프파이어+보관함+작업대 건설 | XP 300                |
| `QUEST_MAIN_PAL`   | 동료 모으기  | 팰 3마리 포획                 | XP 500, 고급 포획구×3 |
| `QUEST_MAIN_TECH`  | 기술 연구    | 기술 5개 해금                 | XP 400, TP 2          |
| `QUEST_MAIN_LEVEL` | 레벨 10 달성 | 레벨 10 도달                  | XP 1000               |
| `QUEST_MAIN_AUTO`  | 자동화 시작  | 채집 기지 건설                | XP 600                |

### 일일 퀘스트 (DAILY)

| ID                    | 이름      | 목표                | 보상   |
| --------------------- | --------- | ------------------- | ------ |
| `QUEST_DAILY_HARVEST` | 일일 수확 | 아무 자원 20회 수확 | XP 100 |
| `QUEST_DAILY_HUNT`    | 일일 사냥 | 크리처 5마리 처치   | XP 150 |

---

## 10. NPCShopData.lua - NPC 상점

### 잡화점 (GENERAL_STORE) - 상인 톰

| 판매 (Buy) | 가격 | 구매 (Sell) | 가격 |
| ---------- | ---- | ----------- | ---- |
| WOOD       | 5    | WOOD        | 2    |
| STONE      | 3    | STONE       | 1    |
| FIBER      | 2    | FIBER       | 1    |
| FLINT      | 4    | RAW_MEAT    | 8    |
| TORCH      | 15   | LEATHER     | 15   |

### 도구점 (TOOL_SHOP) - 대장장이 한스

| 판매          | 가격 | 구매          | 가격 |
| ------------- | ---- | ------------- | ---- |
| STONE_PICKAXE | 50   | STONE_PICKAXE | 15   |
| STONE_AXE     | 50   | STONE_AXE     | 15   |
| WOODEN_CLUB   | 30   | WOODEN_CLUB   | 9    |
| TORCH         | 10   | -             | -    |

### 팰 상점 (PAL_SHOP) - 조련사 미아

| 판매         | 가격 | 재고 |
| ------------ | ---- | ---- |
| PAL_SPHERE   | 50   | 30   |
| SUPER_SPHERE | 150  | 10   |
| ULTRA_SPHERE | 500  | 5    |
| PAL_FOOD     | 20   | ∞    |

### 식료품점 (FOOD_SHOP) - 요리사 루시

| 판매           | 가격 |
| -------------- | ---- |
| COOKED_MEAT    | 25   |
| BERRY          | 5    |
| HEALTH_POTION  | 100  |
| STAMINA_POTION | 80   |

### 건축 상점 (BUILDING_SHOP) - 건축가 벤

| 판매       | 가격 |
| ---------- | ---- |
| WOOD       | 4    |
| STONE      | 2    |
| IRON_INGOT | 30   |
| NAILS      | 5    |
| ROPE       | 10   |

---

## 11. CaptureItemData.lua - 포획 도구

| ID                     | 이름          | 배율 | 사거리 | 희귀도   |
| ---------------------- | ------------- | ---- | ------ | -------- |
| `CAPTURE_SPHERE_BASIC` | 기본 포획구   | 1.0x | 30     | COMMON   |
| `CAPTURE_SPHERE_MEGA`  | 고급 포획구   | 1.5x | 35     | UNCOMMON |
| `CAPTURE_SPHERE_ULTRA` | 마스터 포획구 | 2.5x | 40     | RARE     |

---

## 12. DurabilityProfiles.lua - 내구도 설정

| 프로필 | 타격당 소모 | 적용 대상    |
| ------ | ----------- | ------------ |
| TOOL   | 1           | 곡괭이, 도끼 |
| WEAPON | 2           | 검, 클럽     |
| ARMOR  | 0.5         | 방어구       |

---

_이 문서는 모든 데이터 테이블의 요약입니다. 상세 내용은 각 Lua 파일 참조._
