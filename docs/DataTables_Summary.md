# 데이터 테이블 요약

> **프로젝트**: DinoTribeSurvival (Origin-WILD)  
> **경로**: `src/ReplicatedStorage/Data/`

---

## 1. ItemData.lua - 아이템 정의 (GDD v1.0 반영)

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

### 무기 및 도구 (전투/채집)

| ID | 이름 | 공격력 | 내구도 | 특징 |
| :--- | :--- | :--- | :--- | :--- |
| `STONE_PICKAXE` | 돌 곡괭이 | 10 | 100 | 바위 채집 특화 |
| `STONE_AXE` | 돌 도끼 | 10 | 100 | 나무 채집 특화 |
| `WOODEN_CLUB` | 나무 몽둥이 | 15 | 80 | **기절 수치 50% 부여** |
| `STONE_SPEAR` | 돌 창 | 25 | 100 | 리치 깁 |
| `WOODEN_BOW` | 나무 활 | 40 | 150 | 원거리 (돌 화살 소모) |
| `BRONZE_SPEAR` | 청동 창 | 75 | 250 | |
| `BRONZE_BOW` | 청동 활 | 90 | 300 | 원거리 (청동 화살 소모) |
| `IRON_SPEAR` | 철 창 | 130 | 500 | |
| `CROSSBOW` | 석궁 | 180 | 450 | 원거리 (철제 볼트 소모) |

### 포획 도구 (Bola 시스템)

| ID | 이름 | 포획 배율 | 최대 사거리 | 희귀도 |
| :--- | :--- | :--- | :--- | :--- |
| `VINE_BOLA` | 넝쿨 볼라 | 1.0x | 30 | COMMON |
| `BONE_BOLA` | 뼈 볼라 | 1.5x | 35 | UNCOMMON |
| `BRONZE_BOLA` | 청동 볼라 | 2.0x | 40 | RARE |
| `IRON_BOLA` | 철제 볼라 | 3.5x | 50 | EPIC |

---

## 2. CreatureData.lua - 크리처 정의 (디자인 v2 반영)

| ID | 이름 | HP | MaxTorpor | 공격력 | 특징 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `DODO` | 도도새 | 30 | 20 | 0 | 몽둥이 2~3방에 기절 |
| `RAPTOR` | 랩터 | 150 | 120 | 15 | 초반 스피드 위협 |
| `PARASAUR` | 파라사우롤로푸스 | 400 | 300 | 0 | 도망형 대형 초식 |
| `TRICERATOPS` | 트리케라톱스 | 1200 | 1000 | 40 | 중립, 높은 체력 |
| `TREX` | 티라노사우루스 | 4500 | 3500 | 120 | 최종 레이드 대상 |

---

## 3. PalData.lua - 팰 데이터

| creatureId | 포획률 | 작업 타입 | workPower | 패시브 스킬 |
| :--- | :--- | :--- | :--- | :--- |
| `RAPTOR` | 25% | TRANSPORT, COMBAT | 2 | 이동속도 +10% |
| `TRICERATOPS` | 15% | MINING, TRANSPORT | 4 | 방어력 +15% |
| `DODO` | 60% | FARMING | 1 | 채집량 +20% |
| `PARASAUR` | 35% | TRANSPORT, FARMING | 3 | 무게 한도 +100 |

---

## 5. FacilityData.lua - 시설 정의

| ID | 이름 | 테크레벨 | 건설 재료 | HP | 기능 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `CAMPFIRE` | 캠프파이어 | 1 | WOOD×5, STONE×2 | 100 | 요리, 시야 |
| `STORAGE_BOX` | 보관함 | **10** | WOOD×10, FIBER×5 | 150 | 20슬롯 저장 |
| `PRIMITIVE_WORKBENCH` | 원시 작업대 | **10** | WOOD×15, STONE×5 | 200 | 2단계 제작 |
| `SLEEPING_BAG` | 침낭 | 5 | FIBER×20, WOOD×5 | 50 | 리스폰 설정 |
| `CAMP_TOTEM` | 거점 토템 | 10 | STONE×20, WOOD×10 | 500 | 거점 영역 생성 |
| `STONE_FURNACE` | 돌 용광로 | 20 | STONE×40, FLINT×10 | 400 | 제련 (주괴 제작) |

---

## 7. RecipeData.lua - 주요 레시피

| 결과물 | 재료 | 시설 | 시간 | 테크레벨 |
| :--- | :--- | :--- | :--- | :--- |
| **돌 도끼** | STONE×2, WOOD×3, FIBER×5 | 인벤토리 | 3초 | 1 |
| **나무 몽둥이** | WOOD×10, FIBER×5 | 인벤토리 | 5초 | 4 |
| **넝쿨 볼라** | FIBER×10, WOOD×5 | 인벤토리 | 5초 | 5 |
| **청동 주괴** | COPPER_ORE×2, TIN_ORE×1 | 용광로 | 15초 | 21 |
| **청동 볼라** | BRONZE_INGOT×2, LEATHER×2 | 작업대 | 10초 | 25 |

---

## 8. TechUnlockData.lua - 기술 트리 개편 (Phase 0~4)

### 🪨 Phase 1: 원시 시대 (Lv. 1 ~ 9)
- `TECH_Lv1_BASICS`: 돌 도끼, 돌 곡괭이, 횃불, 모닥불
- `TECH_Lv5_BOLA_V1`: 넝쿨 볼라 (포획 시작)
- `TECH_Lv8_REPAIR`: 수리대

### ⛺ Phase 2: 목조 정착 시대 (Lv. 10 ~ 19)
- `TECH_Lv10_BASE_TOTEM`: 거점 토템, **원시 작업대, 보관함**
- `TECH_Lv12_WOOD_BUILD`: 목재 건축 세트
- `TECH_Lv15_BOW_V1`: 나무 활, 돌 화살

### 🥉 Phase 3: 청동기 시대 (Lv. 20 ~ 34)
- `TECH_Lv20_FURNACE`: 돌 용광로, 청동 주괴
- `TECH_Lv25_BRONZE_GEAR`: 청동 도구 및 무기

---

## 11. CaptureItemData.lua - 볼라 데이터

| ID | 이름 | 포획 배율 | 사거리 | 희귀도 |
| :--- | :--- | :--- | :--- | :--- |
| `VINE_BOLA` | 넝쿨 볼라 | 1.0x | 30 | COMMON |
| `BONE_BOLA` | 뼈 볼라 | 1.5x | 35 | UNCOMMON |
| `BRONZE_BOLA` | 청동 볼라 | 2.0x | 40 | RARE |
| `IRON_BOLA` | 철제 볼라 | 3.5x | 50 | EPIC |

---

_이 문서는 GDD v1.0 및 최신 업데이트 설계를 바탕으로 작성되었습니다._
