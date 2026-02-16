# Phase 8: 퀘스트 시스템 (Quest System)

> **작성일**: 2026-02-16  
> **목표**: 플레이어 목표 시스템 구현 - 진행 추적, 조건 검증, 보상 지급

---

## 1. 개요

### 1.1 핵심 목표

- 다양한 유형의 퀘스트 정의 및 진행 관리
- 조건 기반 자동 완료 감지
- 보상 지급 시스템 (아이템, XP, 기술 포인트)

### 1.2 시스템 구성

```
QuestData.lua         - 퀘스트 정의 데이터
QuestService.lua      - 퀘스트 상태 관리 (서버)
QuestController.lua   - 클라이언트 UI 연동
```

---

## 2. 데이터 구조

### 2.1 QuestData.lua

```lua
{
  id = "QUEST_FIRST_HARVEST",
  name = "첫 수확",
  description = "나무를 3번 수확하세요",
  category = "TUTORIAL",        -- TUTORIAL | MAIN | SIDE | DAILY | ACHIEVEMENT

  -- 선행 조건
  prerequisites = {},           -- 선행 퀘스트 ID 목록
  requiredLevel = 1,            -- 필요 레벨

  -- 완료 목표
  objectives = {
    {
      type = "HARVEST",         -- HARVEST | KILL | CRAFT | BUILD | COLLECT | CAPTURE | TALK
      targetId = "TREE",        -- 대상 ID (노드타입/크리처타입/아이템ID 등)
      count = 3,                -- 필요 횟수
    }
  },

  -- 보상
  rewards = {
    xp = 50,
    techPoints = 0,
    items = {
      { itemId = "WOOD", count = 10 },
    }
  },

  -- 자동 부여
  autoGrant = true,             -- 조건 충족시 자동 부여
  autoGrantLevel = 1,           -- 자동 부여 레벨

  -- 반복 여부
  repeatable = false,           -- 반복 가능 여부
  repeatCooldown = 0,           -- 반복 쿨다운 (초, DAILY용)
}
```

### 2.2 QuestType (Enums)

```lua
QuestType = {
  TUTORIAL = 1,     -- 튜토리얼 (신규 플레이어)
  MAIN = 2,         -- 메인 스토리
  SIDE = 3,         -- 사이드 퀘스트
  DAILY = 4,        -- 일일 퀘스트
  ACHIEVEMENT = 5,  -- 업적
}
```

### 2.3 QuestObjectiveType (Enums)

```lua
QuestObjectiveType = {
  HARVEST = 1,      -- 자원 수확
  KILL = 2,         -- 크리처 처치
  CRAFT = 3,        -- 아이템 제작
  BUILD = 4,        -- 시설 건설
  COLLECT = 5,      -- 아이템 수집 (인벤토리 보유)
  CAPTURE = 6,      -- 팰 포획
  TALK = 7,         -- NPC 대화
  REACH_LEVEL = 8,  -- 레벨 달성
  UNLOCK_TECH = 9,  -- 기술 해금
}
```

### 2.4 QuestStatus (Enums)

```lua
QuestStatus = {
  LOCKED = 1,       -- 잠김 (선행조건 미충족)
  AVAILABLE = 2,    -- 수락 가능
  ACTIVE = 3,       -- 진행 중
  COMPLETED = 4,    -- 완료 (보상 수령 전)
  CLAIMED = 5,      -- 보상 수령 완료
}
```

---

## 3. 서비스 API

### 3.1 QuestService

```lua
-- 초기화
QuestService.Init(NetController, DataService, SaveService, InventoryService, PlayerStatService)

-- 퀘스트 관리
QuestService.getPlayerQuests(userId)           -- 플레이어 퀘스트 상태
QuestService.acceptQuest(player, questId)      -- 퀘스트 수락
QuestService.checkProgress(userId, questId)    -- 진행 상황 확인
QuestService.claimReward(player, questId)      -- 보상 수령
QuestService.abandonQuest(player, questId)     -- 퀘스트 포기

-- 진행 업데이트 (다른 서비스에서 호출)
QuestService.onHarvest(userId, nodeType, count)      -- 수확시
QuestService.onKill(userId, creatureType, count)     -- 처치시
QuestService.onCraft(userId, recipeId, count)        -- 제작시
QuestService.onBuild(userId, facilityId)             -- 건설시
QuestService.onCapture(userId, palType)              -- 포획시
QuestService.onLevelUp(userId, newLevel)             -- 레벨업시
QuestService.onTechUnlock(userId, techId)            -- 기술 해금시

-- 핸들러
QuestService.GetHandlers()
```

### 3.2 Protocol 명령어

```lua
["Quest.List.Request"] = true,        -- 퀘스트 목록 요청
["Quest.Accept.Request"] = true,      -- 퀘스트 수락
["Quest.Claim.Request"] = true,       -- 보상 수령
["Quest.Abandon.Request"] = true,     -- 퀘스트 포기
```

### 3.3 이벤트

```lua
"Quest.Updated"      -- 퀘스트 상태/진행 변경
"Quest.Completed"    -- 퀘스트 완료
"Quest.NewAvailable" -- 새 퀘스트 수락 가능
```

---

## 4. Balance 상수

```lua
Balance.QUEST_MAX_ACTIVE = 10           -- 동시 진행 가능 퀘스트 수
Balance.QUEST_DAILY_RESET_HOUR = 0      -- 일일 퀘스트 리셋 시간 (UTC)
Balance.QUEST_ABANDON_COOLDOWN = 60     -- 퀘스트 포기 후 재수락 쿨다운 (초)
```

---

## 5. 구현 순서

### 8-1: 데이터 레이어

- [ ] QuestData.lua (10개 튜토리얼 + 5개 메인 퀘스트)
- [ ] Enums 확장 (QuestType, QuestObjectiveType, QuestStatus)
- [ ] Balance 확장 (QUEST_MAX_ACTIVE 등)
- [ ] Protocol 확장 (Quest.\* 명령어)

### 8-2: QuestService 코어

- [ ] 퀘스트 상태 관리 (SaveService 연동)
- [ ] acceptQuest / abandonQuest
- [ ] checkProgress / updateProgress
- [ ] claimReward (InventoryService, PlayerStatService 연동)

### 8-3: 진행 추적 연동

- [ ] HarvestService → onHarvest
- [ ] CombatService → onKill
- [ ] CraftingService → onCraft
- [ ] BuildService → onBuild
- [ ] CaptureService → onCapture
- [ ] PlayerStatService → onLevelUp
- [ ] TechService → onTechUnlock

### 8-4: 클라이언트 컨트롤러

- [ ] QuestController.lua (이벤트 수신, UI 연동 준비)

---

## 6. 샘플 퀘스트 목록

### 튜토리얼 퀘스트

| ID                     | 이름    | 목표            | 보상                |
| ---------------------- | ------- | --------------- | ------------------- |
| QUEST_TUTORIAL_HARVEST | 첫 수확 | 나무 3회 수확   | 50 XP, 나무 10개    |
| QUEST_TUTORIAL_CRAFT   | 첫 제작 | 나무 도끼 제작  | 100 XP              |
| QUEST_TUTORIAL_BUILD   | 첫 건설 | 모닥불 설치     | 100 XP, 돌 20개     |
| QUEST_TUTORIAL_HUNT    | 첫 사냥 | 도도 1마리 처치 | 150 XP              |
| QUEST_TUTORIAL_CAPTURE | 첫 포획 | 팰 1마리 포획   | 200 XP, 팰 구슬 5개 |

### 메인 퀘스트

| ID                    | 이름          | 목표           | 보상                   |
| --------------------- | ------------- | -------------- | ---------------------- |
| QUEST_MAIN_BASE       | 거점 구축     | 창고 1개 건설  | 300 XP, 기술 포인트 1  |
| QUEST_MAIN_PARTY      | 동료 모으기   | 팰 3마리 보유  | 500 XP, 기술 포인트 2  |
| QUEST_MAIN_TECH       | 기술 연구     | 기술 5개 해금  | 500 XP                 |
| QUEST_MAIN_LEVEL10    | 성장의 첫걸음 | 레벨 10 달성   | 1000 XP, 기술 포인트 3 |
| QUEST_MAIN_AUTOMATION | 자동화 시작   | 채집 기지 건설 | 800 XP                 |

---

## 7. 검증 항목

| 검증        | ErrorCode             | 조건                      |
| ----------- | --------------------- | ------------------------- |
| 퀘스트 존재 | NOT_FOUND             | 퀘스트 데이터 없음        |
| 선행조건    | QUEST_PREREQ_NOT_MET  | 선행 퀘스트 미완료        |
| 레벨        | QUEST_LEVEL_NOT_MET   | 필요 레벨 미충족          |
| 진행 중     | QUEST_ALREADY_ACTIVE  | 이미 진행 중              |
| 완료 상태   | QUEST_NOT_COMPLETED   | 미완료 상태에서 보상 요청 |
| 보상 수령   | QUEST_ALREADY_CLAIMED | 이미 보상 수령            |
| 최대 진행   | QUEST_MAX_ACTIVE      | 동시 진행 한도 초과       |
| 반복 불가   | QUEST_NOT_REPEATABLE  | 비반복 퀘스트 재수락      |

---

_Phase 8 완료 기준: 퀘스트 수락 → 진행 → 완료 → 보상 수령 전체 플로우 동작_
