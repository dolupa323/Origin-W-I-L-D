# Phase 6: 기술 트리 & 플레이어 성장 시스템

> **시작일**: 2026-02-16  
> **목표**: 기술 해금 및 플레이어 레벨/스탯 시스템 구현  
> **마일스톤**: M4 — 베이스/자동화 전 완성

---

## 전체 개요

Palworld/ARK 스타일의 기술 트리와 플레이어 성장 시스템을 구현한다.

- 경험치를 획득하여 레벨업
- 기술 포인트로 새로운 레시피/기능 해금
- 플레이어 스탯 보너스 (제작 속도, 피해량 등)
- Server-Authoritative + Data-Driven 원칙 유지

---

## 하위 Phase 상세

---

### Phase 6-1: 데이터 레이어 (TechUnlockData)

**목표**: 기술 트리 데이터 정의

**구현 내용**:

1. `Data/TechUnlockData.lua` — 기술 노드 정의

   ```lua
   {
     id = "TECH_STONE_TOOLS",
     name = "석기 도구",
     description = "돌로 만든 기본 도구 해금",
     techLevel = 1,
     techPointCost = 1,         -- 해금에 필요한 포인트
     prerequisites = {},         -- 선행 기술 ID 목록
     unlocks = {
       recipes = { "CRAFT_STONE_PICKAXE", "CRAFT_STONE_AXE" },
       facilities = {},
       features = {},           -- 특수 기능 (ex: "RIDING")
     },
     category = "TOOLS",        -- UI 분류
   }
   ```

2. **Balance.lua 상수 추가**:

   ```lua
   Balance.PLAYER_MAX_LEVEL = 50
   Balance.BASE_XP_PER_LEVEL = 100
   Balance.XP_SCALING = 1.2        -- 레벨당 필요 XP 증가율
   Balance.TECH_POINTS_PER_LEVEL = 2
   Balance.XP_SOURCES = {
     CREATURE_KILL = 25,
     CRAFT_ITEM = 5,
     CAPTURE_PAL = 50,
     HARVEST_RESOURCE = 2,
   }
   ```

3. **Enums.lua 확장**:

   ```lua
   Enums.XPSource = {
     CREATURE_KILL = "CREATURE_KILL",
     CRAFT_ITEM = "CRAFT_ITEM",
     CAPTURE_PAL = "CAPTURE_PAL",
     HARVEST_RESOURCE = "HARVEST_RESOURCE",
   }

   Enums.TechCategory = {
     TOOLS = "TOOLS",
     WEAPONS = "WEAPONS",
     ARMOR = "ARMOR",
     STRUCTURES = "STRUCTURES",
     FACILITIES = "FACILITIES",
     PAL = "PAL",
   }
   ```

**완료 기준 (DoD)**:

- [ ] TechUnlockData에 최소 10개 기술 노드 정의
- [ ] Balance.lua에 레벨/XP 상수 추가
- [ ] 기술 노드 간 선행 관계 정의 (트리 구조)

---

### Phase 6-2: PlayerStatService (플레이어 성장)

**목표**: 경험치 및 레벨 시스템 구현

**구현 내용**:

1. `PlayerStatService.lua` — 플레이어 성장 로직

   ```lua
   -- API
   PlayerStatService.Init(NetController, SaveService, DataService)
   PlayerStatService.addXP(userId, amount, source) → leveledUp, newLevel
   PlayerStatService.getLevel(userId) → level
   PlayerStatService.getXP(userId) → current, required
   PlayerStatService.getTechPoints(userId) → available
   PlayerStatService.getStats(userId) → { craftSpeed, gatherSpeed, ... }
   PlayerStatService.GetHandlers() → { ["Player.GetStats.Request"] = handler }
   ```

2. **레벨업 공식**:

   ```
   requiredXP(level) = BASE_XP × (XP_SCALING ^ (level - 1))

   예시 (BASE=100, SCALING=1.2):
   - Level 1→2: 100 XP
   - Level 2→3: 120 XP
   - Level 3→4: 144 XP
   - Level 10→11: 515 XP
   ```

3. **SaveService 연동**:

   ```lua
   playerState.stats.level = 1
   playerState.stats.currentXP = 0
   playerState.stats.techPointsSpent = 0
   ```

4. **스탯 보너스 계산** (RecipeService.calculateEfficiency 연동):
   ```
   playerStatBonus = (level - 1) × 0.02
   -- Level 50 기준: 0.98 (98% 보너스)
   ```

**완료 기준 (DoD)**:

- [ ] 크리처 처치 시 XP 획득
- [ ] 레벨업 시 기술 포인트 지급
- [ ] 서버 재시작 후 레벨/XP 유지

---

### Phase 6-3: TechService (기술 해금)

**목표**: 기술 트리 해금 시스템 구현

**구현 내용**:

1. `TechService.lua` — 기술 해금 로직

   ```lua
   -- API
   TechService.Init(NetController, DataService, PlayerStatService, SaveService)
   TechService.unlock(userId, techId) → success, errorCode
   TechService.isUnlocked(userId, techId) → boolean
   TechService.getUnlockedTech(userId) → { techId → true }
   TechService.getAvailableTech(userId) → { techId → data }  -- 해금 가능한 목록
   TechService.getTechTree() → 전체 기술 트리 데이터
   TechService.GetHandlers()
   ```

2. **해금 검증**:
   - 기술 포인트 충분한지
   - 선행 기술 모두 해금했는지
   - 이미 해금한 기술 아닌지

3. **CraftingService 연동**:
   - 레시피 시작 시 기술 해금 여부 확인
   - 미해금 레시피는 제작 불가

4. **Protocol 명령어**:
   ```lua
   ["Tech.Unlock.Request"]     -- 기술 해금 요청
   ["Tech.List.Request"]       -- 기술 목록 조회
   ["Tech.Tree.Request"]       -- 전체 트리 조회
   ["Player.Stats.Request"]    -- 레벨/XP/포인트 조회
   ["Player.Stats.Changed"]    -- 스탯 변경 이벤트
   ["Tech.Unlocked"]           -- 기술 해금 이벤트
   ```

**완료 기준 (DoD)**:

- [ ] 기술 포인트로 새 기술 해금 가능
- [ ] 선행 기술 미해금 시 해금 거부
- [ ] 해금된 기술의 레시피만 제작 가능
- [ ] 서버 재시작 후 해금 상태 유지

---

### Phase 6-4: 외부 서비스 연동

**목표**: 기존 서비스에 XP 지급 로직 추가

**연동 대상**:

1. **CreatureService.lua** — 크리처 처치 시 XP

   ```lua
   -- _handleDeath에서
   PlayerStatService.addXP(attackerUserId, Balance.XP_SOURCES.CREATURE_KILL)
   ```

2. **CaptureService.lua** — 팰 포획 시 XP

   ```lua
   -- 포획 성공 시
   PlayerStatService.addXP(userId, Balance.XP_SOURCES.CAPTURE_PAL)
   ```

3. **CraftingService.lua** — 레시피 해금 검증 + 제작 완료 XP

   ```lua
   -- start() 시 TechService.isRecipeUnlocked(userId, recipeId) 확인
   -- collect() 시 XP 지급
   PlayerStatService.addXP(userId, Balance.XP_SOURCES.CRAFT_ITEM)
   ```

4. **FacilityService.lua** (선택) — 자원 채집 시 XP

**완료 기준 (DoD)**:

- [ ] 크리처 처치/포획/제작 시 XP 획득 확인
- [ ] 미해금 레시피 제작 시도 시 거부

---

### Phase 6-5: 클라이언트 연동

**목표**: 클라이언트 컨트롤러 및 이벤트 핸들링

**구현 내용**:

1. `TechController.lua` — 기술 해금 이벤트 수신
2. `Players.Stats.Changed` 이벤트 핸들링 (레벨업 알림)

**완료 기준 (DoD)**:

- [ ] 레벨업 시 클라이언트 이벤트 수신
- [ ] 기술 해금 시 클라이언트 이벤트 수신

---

## 데이터 스키마

### TechUnlockData 예시

```lua
{
  -- Tier 0: 기본 해금 (시작 시)
  { id = "TECH_BASICS",          name = "기초 지식",     techLevel = 0, techPointCost = 0, prerequisites = {}, unlocks = { recipes = {} } },

  -- Tier 1: 초급
  { id = "TECH_STONE_TOOLS",     name = "석기 도구",     techLevel = 1, techPointCost = 1, prerequisites = {"TECH_BASICS"}, unlocks = { recipes = {"CRAFT_STONE_PICKAXE", "CRAFT_STONE_AXE"} } },
  { id = "TECH_FIBER_CRAFT",     name = "섬유 가공",     techLevel = 1, techPointCost = 1, prerequisites = {"TECH_BASICS"}, unlocks = { recipes = {"CRAFT_ROPE"} } },
  { id = "TECH_CAMPFIRE",        name = "캠프파이어",    techLevel = 1, techPointCost = 1, prerequisites = {"TECH_BASICS"}, unlocks = { recipes = {"CRAFT_CAMPFIRE_KIT"}, facilities = {"CAMPFIRE"} } },

  -- Tier 2: 중급
  { id = "TECH_WORKBENCH",       name = "작업대",        techLevel = 2, techPointCost = 2, prerequisites = {"TECH_STONE_TOOLS"}, unlocks = { facilities = {"WORKBENCH"} } },
  { id = "TECH_CAPTURE_BASIC",   name = "기본 포획술",   techLevel = 2, techPointCost = 2, prerequisites = {"TECH_FIBER_CRAFT"}, unlocks = { recipes = {"CRAFT_CAPTURE_SPHERE_BASIC"} } },

  -- Tier 3: 상급
  { id = "TECH_SMELTING",        name = "제련",          techLevel = 3, techPointCost = 3, prerequisites = {"TECH_WORKBENCH"}, unlocks = { facilities = {"FURNACE"} } },
  { id = "TECH_CAPTURE_MEGA",    name = "고급 포획술",   techLevel = 3, techPointCost = 3, prerequisites = {"TECH_CAPTURE_BASIC"}, unlocks = { recipes = {"CRAFT_CAPTURE_SPHERE_MEGA"} } },
}
```

### PlayerState 확장

```lua
playerState.stats = {
  level = 1,
  currentXP = 0,
  totalXP = 0,
  techPointsSpent = 0,
  -- 선택: 스탯 분배 (나중 확장)
  -- statPoints = 0,
  -- allocatedStats = { strength = 0, ... }
}

playerState.unlockedTech = {
  TECH_BASICS = true,      -- 시작 시 기본 해금
  TECH_STONE_TOOLS = true, -- 해금됨
}
```

---

## Protocol 명령어 목록

```lua
-- 플레이어 스탯
["Player.Stats.Request"] = true
["Player.Stats.Changed"] = true       -- Event

-- 기술 해금
["Tech.Unlock.Request"] = true
["Tech.List.Request"] = true
["Tech.Tree.Request"] = true
["Tech.Unlocked"] = true              -- Event
```

---

## ErrorCode 추가

```lua
Enums.ErrorCode.TECH_ALREADY_UNLOCKED = "TECH_ALREADY_UNLOCKED"
Enums.ErrorCode.TECH_NOT_FOUND = "TECH_NOT_FOUND"
Enums.ErrorCode.INSUFFICIENT_TECH_POINTS = "INSUFFICIENT_TECH_POINTS"
Enums.ErrorCode.PREREQUISITES_NOT_MET = "PREREQUISITES_NOT_MET"
Enums.ErrorCode.RECIPE_LOCKED = "RECIPE_LOCKED"
```

---

## 구현 순서

1. **Phase 6-1**: TechUnlockData + Balance/Enums 확장
2. **Phase 6-2**: PlayerStatService (XP/레벨)
3. **Phase 6-3**: TechService (기술 해금)
4. **Phase 6-4**: 외부 서비스 XP 연동
5. **Phase 6-5**: 클라이언트 컨트롤러

---

## 의존성 그래프

```
DataService ─┬─► PlayerStatService ─► TechService
             │
SaveService ─┤
             │
NetController ┘

TechService ─► CraftingService (레시피 해금 검증)
PlayerStatService ─► CreatureService (처치 XP)
PlayerStatService ─► CaptureService (포획 XP)
PlayerStatService ─► CraftingService (제작 XP)
```

---

_작성일: 2026-02-16_
