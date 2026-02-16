# Phase 5: 테이밍 & 팰(Pal) 시스템

> **시작일**: 2026-02-16  
> **목표**: 야생 크리처를 포획하여 동료(팰)로 만들고, 소환/파티/보관/작업 배치 기능 구현  
> **마일스톤**: M3 — Pal (포획/소환/작업)

---

## 전체 개요

Palworld 스타일의 포획 시스템을 구현한다.  
- 약해진 야생 크리처에게 포획 도구(CaptureSphere)를 던져 포획
- 포획한 팰은 Palbox에 보관
- 파티에 편성하여 소환/전투/작업에 활용
- Server-Authoritative + Data-Driven 원칙 유지

---

## 하위 Phase 상세

---

### Phase 5-1: 데이터 레이어 & 포획 도구

**목표**: 팰 시스템을 위한 데이터 정의 및 포획 아이템 추가

**구현 내용**:
1. `Data/PalData.lua` — 포획 가능한 크리처별 팰 데이터 정의
   ```lua
   {
     creatureId = "RAPTOR",
     palName = "랩터",
     captureRate = 0.3,     -- 기본 포획률 (HP 100%일 때)
     workTypes = {"MINING", "TRANSPORT"},  -- 가능한 작업
     workPower = 2,         -- 작업 효율
     combatPower = 50,      -- 전투력
     passiveSkill = "SPEED_BOOST",
   }
   ```

2. `Data/CaptureItemData.lua` — 포획 도구 정의
   ```lua
   {
     id = "CAPTURE_SPHERE_BASIC",
     name = "기본 포획구",
     captureMultiplier = 1.0,  -- 포획률 배율
     maxRange = 30,            -- 투척 사거리
   }
   ```

3. `ItemDB.lua` 업데이트 — 포획구 아이템 추가
4. `RecipeData.lua` 업데이트 — 포획구 제작 레시피

**새 파일**:  
- `src/ReplicatedStorage/Data/PalData.lua`
- `src/ReplicatedStorage/Data/CaptureItemData.lua`

**완료 기준 (DoD)**:
- [ ] PalData에 최소 3종(RAPTOR, TRICERATOPS, DODO) 정의
- [ ] CaptureItemData에 기본/고급 포획구 2종 정의
- [ ] 포획구가 인벤토리에서 확인 가능

---

### Phase 5-2: CaptureService (포획 서비스)

**목표**: 서버 권위 기반 포획 판정 시스템 구현

**구현 내용**:
1. `CaptureService.lua` — 핵심 포획 로직
   ```lua
   -- API
   CaptureService.Init(NetController, DataService, CreatureService, InventoryService)
   CaptureService.attemptCapture(player, targetId, captureItemSlot) → success, palData
   CaptureService.GetHandlers() → { ["Capture.Attempt.Request"] = handler }
   ```

2. **포획 확률 공식**:
   ```
   finalRate = baseRate × (1 + (1 - currentHP/maxHP) × 2) × captureMultiplier
   
   예시: 
   - RAPTOR (baseRate=0.3), HP 50% → 0.3 × (1 + 0.5×2) × 1.0 = 0.6 (60%)
   - RAPTOR, HP 10% → 0.3 × (1 + 0.9×2) × 1.0 = 0.84 (84%)
   - RAPTOR, HP 100% → 0.3 × (1 + 0×2) × 1.0 = 0.3 (30%)
   ```

3. **포획 흐름**:
   ```
   Client → Capture.Attempt.Request(targetId, captureItemSlot)
   Server:
     1. 포획구 아이템 검증 (인벤토리에 있는지)
     2. 대상 크리처 검증 (존재, 거리, 포획 가능 여부)
     3. 포획구 소모 (InventoryService.removeItem)
     4. 확률 판정 (math.random() vs finalRate)
     5a. 성공 → 크리처 제거 + PalboxService에 등록
     5b. 실패 → 크리처 유지 (HP 변동 없음)
     6. 결과 이벤트 전송 (Capture.Result)
   ```

4. **포획 제한**:
   - BOSS 크리처는 포획 불가
   - 이미 포획된(다른 플레이어의) 팰은 포획 불가
   - Palbox 가득 차면 포획 불가

**새 파일**:
- `src/ServerScriptService/Server/Services/CaptureService.lua`

**완료 기준 (DoD)**:
- [ ] 약해진 DODO에게 포획구를 사용하면 높은 확률로 포획 성공
- [ ] HP가 풀인 RAPTOR 포획 시도 시 낮은 확률
- [ ] 포획 성공 시 크리처 모델 제거됨
- [ ] 포획구 아이템 소모됨
- [ ] 서버 로그에 포획 성공/실패 기록

---

### Phase 5-3: PalboxService (팰 보관 시스템)

**목표**: 포획한 팰을 저장/관리하는 보관 시스템

**구현 내용**:
1. `PalboxService.lua` — 팰 보관함
   ```lua
   -- API
   PalboxService.Init(NetController, DataService, SaveService)
   PalboxService.addPal(userId, palData) → palUID
   PalboxService.removePal(userId, palUID) → success
   PalboxService.getPalList(userId) → { palUID → palInfo }
   PalboxService.getPal(userId, palUID) → palInfo
   PalboxService.GetHandlers() → { ["Palbox.List.Request"] = handler }
   ```

2. **팰 데이터 구조** (저장용):
   ```lua
   {
     uid = "pal_abc123",       -- 고유 ID
     creatureId = "RAPTOR",    -- 종류
     nickname = "번개",         -- 닉네임 (플레이어 지정)
     level = 1,
     exp = 0,
     stats = {
       hp = 100,
       attack = 15,
       defense = 5,
     },
     workTypes = {"MINING", "TRANSPORT"},
     capturedAt = 1771214000,  -- 포획 시각
     isInParty = false,        -- 파티 편성 여부
     assignedFacility = nil,   -- 배치된 시설 ID
   }
   ```

3. **보관 제한**:
   - 최대 보관 수: `Balance.MAX_PALBOX = 30`
   - SaveService 연동 (서버 재시작 시 유지)

**새 파일**:
- `src/ServerScriptService/Server/Services/PalboxService.lua`

**완료 기준 (DoD)**:
- [ ] 포획 성공 시 PalboxService에 팰 자동 등록
- [ ] Palbox.List.Request로 보유 팰 목록 조회 가능
- [ ] 서버 재시작 후 팰 데이터 유지 (SaveService 연동)
- [ ] MAX_PALBOX 초과 시 포획 거부

---

### Phase 5-4: PartyService (파티 & 소환)

**목표**: 보관함의 팰을 파티에 편성하고 월드에 소환

**구현 내용**:
1. `PartyService.lua` — 파티 편성 및 소환
   ```lua
   -- API
   PartyService.Init(NetController, PalboxService, CreatureService)
   PartyService.addToParty(userId, palUID) → success
   PartyService.removeFromParty(userId, palUID) → success
   PartyService.getParty(userId) → { slot → palUID }
   PartyService.summon(userId, partySlot) → success
   PartyService.recall(userId) → success
   PartyService.GetHandlers()
   ```

2. **파티 규칙**:
   - 최대 파티 크기: `Balance.MAX_PARTY = 5`
   - 한 번에 소환 가능한 팰: 1마리
   - 소환된 팰은 플레이어를 따라다님 (AI: FOLLOW 상태)
   - 전투 시 자동으로 적을 공격 (AI: COMBAT 상태)

3. **소환 흐름**:
   ```
   Client → Party.Summon.Request(partySlot)
   Server:
     1. 파티 슬롯 검증
     2. 이미 소환된 팰이 있으면 먼저 회수
     3. 팰 모델 생성 (CreatureService.spawnPal 활용)
     4. 팰 AI 시작 (FOLLOW → 적 감지 시 COMBAT)
     5. 소환 이벤트 전송
   ```

4. **팰 AI 상태**:
   - `FOLLOW`: 주인 뒤 3-5스터드 거리 유지
   - `COMBAT`: 주인이 공격한 대상 or 주인을 공격한 대상 추격
   - `IDLE`: 주인이 정지 시 근처에서 대기

**새 파일**:
- `src/ServerScriptService/Server/Services/PartyService.lua`

**완료 기준 (DoD)**:
- [ ] 보관함의 팰을 파티(최대 5슬롯)에 편성/해제 가능
- [ ] 파티의 팰을 월드에 소환 → 플레이어를 따라다님
- [ ] 소환된 팰이 적 크리처를 자동 공격
- [ ] 소환된 팰 회수 시 모델 제거 + 상태 저장

---

### Phase 5-5: 작업 배치 시스템 (Automation 연동 준비)

**목표**: 팰을 시설물에 배치하여 자동 작업 수행

**구현 내용**:
1. `FacilityService` 확장 — 팰 작업자 슬롯
   ```lua
   -- 기존 FacilityService에 추가
   FacilityService.assignPal(userId, facilityUID, palUID) → success
   FacilityService.unassignPal(userId, facilityUID) → success
   ```

2. **작업 로직**:
   - 팰의 `workTypes`와 시설의 `facilityType` 매칭
   - 팰의 `workPower`에 따라 작업 속도 배율 적용
   - 예: workPower=2인 팰 배치 → 제작 시간 50% 단축

3. **제한사항**:
   - 소환 중인 팰은 시설 배치 불가
   - 시설 배치 중인 팰은 소환 불가
   - 하나의 시설에 최대 1마리 배치

**수정 파일**:
- `src/ServerScriptService/Server/Services/FacilityService.lua` (확장)

**완료 기준 (DoD)**:
- [ ] 팰을 Campfire(COOKING) 시설에 배치 가능
- [ ] 배치된 팰의 workPower에 따라 작업 속도 변경
- [ ] 이미 소환 중인 팰 배치 시도 시 에러 반환

---

## ServerInit 초기화 순서

```lua
-- Phase 5 서비스 추가
local PalboxService = require(Services.PalboxService)
PalboxService.Init(NetController, DataService, SaveService)

local CaptureService = require(Services.CaptureService)
CaptureService.Init(NetController, DataService, CreatureService, InventoryService, PalboxService)

local PartyService = require(Services.PartyService)
PartyService.Init(NetController, PalboxService, CreatureService)
```

---

## Balance 상수 추가

```lua
-- Shared/Config/Balance.lua에 추가
Balance.MAX_PALBOX = 30      -- 팰 보관함 최대 수
Balance.MAX_PARTY = 5        -- 파티 최대 슬롯
Balance.PAL_FOLLOW_DIST = 4  -- 팰이 주인과 유지하는 거리
Balance.PAL_COMBAT_RANGE = 15 -- 팰이 전투를 시작하는 감지 범위
```

---

## 구현 순서 (권장)

```
Phase 5-1 (데이터) → 5-2 (포획) → 5-3 (보관) → 5-4 (파티/소환) → 5-5 (작업배치)
```

각 단계는 이전 단계의 완료 기준(DoD)을 만족해야 다음 단계로 진행합니다.
