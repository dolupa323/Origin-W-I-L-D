# API & Protocol 레퍼런스

> **프로젝트**: DinoTribeSurvival (Origin-WILD)  
> **현재 버전**: Phase 1-4 GDD 정렬 완료 (2026-02-25)

---

## 1. 네트워크 프로토콜 개요

### 1.1 통신 방식

- **RemoteFunction**: `NetCmd` (요청-응답)
- **RemoteEvent**: `NetEvt` (서버→클라이언트 이벤트)

### 1.2 요청 형식

```lua
-- 클라이언트 → 서버
NetClient.Request(command, payload, callback)

-- payload 예시
{
    requestId = "unique-id",  -- 자동 생성
    ...params
}
```

### 1.3 응답 형식

```lua
{
    success = true/false,
    errorCode = "ERROR_CODE",  -- 실패 시
    data = { ... }             -- 성공 시
}
```

---

## 2. 프로토콜 명령어 목록

### 2.1 기본 명령어

| 명령어     | 설명        | Payload       | Response             |
| ---------- | ----------- | ------------- | -------------------- |
| `Net.Ping` | 연결 확인   | `{}`          | `{ pong = true }`    |
| `Net.Echo` | 메시지 반향 | `{ message }` | `{ echo = message }` |

---

### 2.2 시간 명령어 (TimeService)

| 명령어              | 설명               | Payload                    | Response                             |
| ------------------- | ------------------ | -------------------------- | ------------------------------------ |
| `Time.Sync.Request` | 시간 동기화        | `{}`                       | `{ serverTime, phase, dayProgress }` |
| `Time.Warp`         | 시간 이동 (디버그) | `{ hours }`                | `{ ok }`                             |
| `Time.WarpToPhase`  | 페이즈 이동        | `{ phase: "DAY"/"NIGHT" }` | `{ ok }`                             |

#### 이벤트:

```lua
"Time.PhaseChanged" → { phase = "DAY"/"NIGHT" }
"Time.Tick" → { serverTime, normalizedTime }
```

---

### 2.3 저장 명령어 (SaveService)

| 명령어        | 설명               | Payload | Response                |
| ------------- | ------------------ | ------- | ----------------------- |
| `Save.Now`    | 즉시 저장 (디버그) | `{}`    | `{ saved = true }`      |
| `Save.Status` | 저장 상태 조회     | `{}`    | `{ lastSave, isDirty }` |

---

### 2.4 인벤토리 명령어 (InventoryService)

| 명령어                    | 설명                 | Payload                       | Response                  |
| ------------------------- | -------------------- | ----------------------------- | ------------------------- |
| `Inventory.Get.Request`   | 전체 조회            | `{}`                          | `{ slots: {...} }`        |
| `Inventory.Move.Request`  | 슬롯 이동            | `{ from, to }`                | `{ ok }`                  |
| `Inventory.Split.Request` | 스택 분할            | `{ slot, targetSlot, count }` | `{ ok }`                  |
| `Inventory.Drop.Request`  | 아이템 드롭          | `{ slot, count? }`            | `{ dropped, worldDrop? }` |
| `Inventory.GiveItem`      | 아이템 지급 (디버그) | `{ itemId, count }`           | `{ ok }`                  |

#### 이벤트:

```lua
"Inventory.Changed" → { slots: {...}, changedSlots: [...] }
"Inventory.Full" → {}
```

---

### 2.5 월드 드롭 명령어 (WorldDropService)

| 명령어                   | 설명      | Payload      | Response            |
| ------------------------ | --------- | ------------ | ------------------- |
| `WorldDrop.Loot.Request` | 드롭 루팅 | `{ dropId }` | `{ itemId, count }` |

#### 이벤트:

```lua
"WorldDrop.Spawned" → { id, position, itemId, count }
"WorldDrop.Despawned" → { id }
"WorldDrop.Merged" → { sourceId, targetId, newCount }
```

---

### 2.6 저장소 명령어 (StorageService)

| 명령어                  | 설명        | Payload                           | Response           |
| ----------------------- | ----------- | --------------------------------- | ------------------ |
| `Storage.Open.Request`  | 창고 열기   | `{ structureId }`                 | `{ slots: {...} }` |
| `Storage.Close.Request` | 창고 닫기   | `{ structureId }`                 | `{ ok }`           |
| `Storage.Move.Request`  | 아이템 이동 | `{ from, to, count?, direction }` | `{ ok }`           |

※ direction: `"INV_TO_STORAGE"` / `"STORAGE_TO_INV"` / `"STORAGE_INTERNAL"`

#### 이벤트:

```lua
"Storage.Changed" → { structureId, slots: {...} }
```

---

### 2.7 건설 명령어 (BuildService)

| 명령어                 | 설명      | Payload                               | Response                |
| ---------------------- | --------- | ------------------------------------- | ----------------------- |
| `Build.Place.Request`  | 시설 배치 | `{ facilityId, position, rotation? }` | `{ structureId }`       |
| `Build.Remove.Request` | 시설 해체 | `{ structureId }`                     | `{ refunded: [...] }`   |
| `Build.GetAll.Request` | 전체 조회 | `{}`                                  | `{ structures: [...] }` |

#### 이벤트:

```lua
"Build.Placed" → { structureId, facilityId, position, ownerId }
"Build.Removed" → { structureId }
```

---

### 2.8 제작 명령어 (CraftingService)

| 명령어                   | 설명        | Payload                      | Response                     |
| ------------------------ | ----------- | ---------------------------- | ---------------------------- |
| `Craft.Start.Request`    | 제작 시작   | `{ recipeId, structureId? }` | `{ craftId, estimatedTime }` |
| `Craft.Cancel.Request`   | 제작 취소   | `{ craftId }`                | `{ refunded: [...] }`        |
| `Craft.Collect.Request`  | 완성품 수거 | `{ craftId }`                | `{ items: [...] }`           |
| `Craft.GetQueue.Request` | 큐 조회     | `{}`                         | `{ queue: [...] }`           |

#### 이벤트:

```lua
"Craft.Started" → { craftId, recipeId, endTime }
"Craft.Completed" → { craftId, recipeId, outputs }
"Craft.Cancelled" → { craftId }
```

---

### 2.9 시설 명령어 (FacilityService)

| 명령어                           | 설명           | Payload                         | Response                                |
| -------------------------------- | -------------- | ------------------------------- | --------------------------------------- |
| `Facility.GetInfo.Request`       | 시설 정보 조회 | `{ structureId }`               | `{ state, fuel, input, output, queue }` |
| `Facility.AddFuel.Request`       | 연료 추가      | `{ structureId, slot }`         | `{ ok, fuelValue }`                     |
| `Facility.AddInput.Request`      | 재료 추가      | `{ structureId, slot, count? }` | `{ ok }`                                |
| `Facility.CollectOutput.Request` | 산출물 수거    | `{ structureId }`               | `{ items: [...] }`                      |
| `Facility.AssignPal.Request`     | 팰 배치        | `{ structureId, palUID }`       | `{ ok }`                                |
| `Facility.UnassignPal.Request`   | 팰 해제        | `{ structureId }`               | `{ ok }`                                |

#### 이벤트:

```lua
"Facility.StateChanged" → { structureId, state, fuel, ... }
"Facility.CraftCompleted" → { structureId, itemId, count }
```

---

### 2.10 레시피 명령어 (RecipeService)

| 명령어                   | 설명        | Payload                      | Response                           |
| ------------------------ | ----------- | ---------------------------- | ---------------------------------- |
| `Recipe.GetInfo.Request` | 레시피 정보 | `{ recipeId, structureId? }` | `{ recipe, efficiency, realTime }` |
| `Recipe.GetAll.Request`  | 전체 레시피 | `{}`                         | `{ recipes: [...] }`               |

---

### 2.11 전투 명령어 (CombatService)

| 명령어               | 설명      | Payload                     | Response                          |
| -------------------- | --------- | --------------------------- | --------------------------------- |
| `Combat.Hit.Request` | 공격 수행 | `{ targetId, weaponSlot? }` | `{ damage, remainingHP, killed }` |

#### 이벤트:

```lua
"Combat.HitResult" → { attackerId, targetId, damage, remainingHP }
"Combat.CreatureDied" → { creatureId, drops: [...] }
"Combat.PlayerDamaged" → { damage, currentHP, source }
```

---

### 2.12 포획 명령어 (CaptureService)

| 명령어                    | 설명      | Payload                  | Response                            |
| ------------------------- | --------- | ------------------------ | ----------------------------------- |
| `Capture.Attempt.Request` | 포획 시도 | `{ targetId, itemSlot }` | `{ success, captureRate, palUID? }` |

#### 이벤트:

```lua
"Capture.Success" → { palUID, creatureType, palName }
"Capture.Failed" → { creatureType, captureRate }
```

---

### 2.13 팰 보관함 명령어 (PalboxService)

| 명령어                   | 설명        | Payload               | Response          |
| ------------------------ | ----------- | --------------------- | ----------------- |
| `Palbox.List.Request`    | 보관함 조회 | `{}`                  | `{ pals: [...] }` |
| `Palbox.Rename.Request`  | 이름 변경   | `{ palUID, newName }` | `{ ok }`          |
| `Palbox.Release.Request` | 팰 해방     | `{ palUID }`          | `{ ok }`          |

#### 이벤트:

```lua
"Palbox.Updated" → { pals: [...] }
```

---

### 2.14 파티 명령어 (PartyService)

| 명령어                 | 설명      | Payload             | Response                     |
| ---------------------- | --------- | ------------------- | ---------------------------- |
| `Party.List.Request`   | 파티 조회 | `{}`                | `{ party: [...], maxSlots }` |
| `Party.Add.Request`    | 파티 편성 | `{ palUID, slot? }` | `{ ok, slot }`               |
| `Party.Remove.Request` | 파티 해제 | `{ slot }`          | `{ ok }`                     |
| `Party.Summon.Request` | 팰 소환   | `{ slot }`          | `{ ok }`                     |
| `Party.Recall.Request` | 팰 회수   | `{ slot }`          | `{ ok }`                     |

#### 이벤트:

```lua
"Party.Changed" → { party: [...] }
"Party.PalSummoned" → { slot, palUID }
"Party.PalRecalled" → { slot, palUID }
```

---

### 2.15 플레이어 스탯 명령어 (PlayerStatService)

| 명령어                 | 설명      | Payload | Response                              |
| ---------------------- | --------- | ------- | ------------------------------------- |
| `Player.Stats.Request` | 스탯 조회 | `{}` | `{ level, currentXP, requiredXP, statPointsAvailable, statInvested, calculated }` |
| `Player.Stats.Upgrade.Request` | 스탯 포인트 투자 | `{ statId }` | `{ success }` |

#### 이벤트:

```lua
"Player.Stats.Changed" → { level, currentXP, requiredXP, leveledUp, statPointsAvailable, ... }
"Player.Stats.Upgraded" → { statId, newValue, pointsRemaining }
```

#### 이벤트:

```lua
"Player.XPGained" → { amount, source, totalXP }
"Player.LevelUp" → { newLevel, techPointsGained }
```

---

### 2.16 기술 명령어 (TechService)

| 명령어                | 설명      | Payload      | Response                                      |
| --------------------- | --------- | ------------ | --------------------------------------------- |
| `Tech.Unlock.Request` | 기술 해금 | `{ techId }` | `{ ok, unlockedRecipes, unlockedFacilities }` |
| `Tech.List.Request`   | 해금 목록 | `{}`         | `{ unlockedTechs: [...] }`                    |
| `Tech.Tree.Request`   | 전체 트리 | `{}`         | `{ tree: [...] }`                             |

#### 이벤트:

```lua
"Tech.Unlocked" → { techId, unlocks: {...} }
```

---

### 2.17 수확 명령어 (HarvestService)

| 명령어                     | 설명      | Payload       | Response                                   |
| -------------------------- | --------- | ------------- | ------------------------------------------ |
| `Harvest.Hit.Request`      | 자원 타격 | `{ nodeId }`  | `{ resources: [...], depleted, xpGained }` |
| `Harvest.GetNodes.Request` | 노드 조회 | `{ radius? }` | `{ nodes: [...] }`                         |

#### 이벤트:

```lua
"Harvest.NodeHit" → { nodeId, hitsRemaining }
"Harvest.NodeDepleted" → { nodeId, respawnTime }
"Harvest.NodeRespawned" → { nodeId }
```

---

### 2.18 베이스 명령어 (BaseClaimService)

| 명령어                | 설명        | Payload | Response                            |
| --------------------- | ----------- | ------- | ----------------------------------- |
| `Base.Get.Request`    | 베이스 정보 | `{}`    | `{ baseId, center, radius, level }` |
| `Base.Expand.Request` | 베이스 확장 | `{}`    | `{ newRadius }`                     |

---

### 2.19 퀘스트 명령어 (QuestService)

| 명령어                  | 설명        | Payload       | Response             |
| ----------------------- | ----------- | ------------- | -------------------- |
| `Quest.List.Request`    | 퀘스트 목록 | `{}`          | `{ quests: {...} }`  |
| `Quest.Accept.Request`  | 퀘스트 수락 | `{ questId }` | `{ ok }`             |
| `Quest.Claim.Request`   | 보상 수령   | `{ questId }` | `{ rewards: {...} }` |
| `Quest.Abandon.Request` | 퀘스트 포기 | `{ questId }` | `{ ok }`             |

#### 이벤트:

```lua
"Quest.Updated" → { questId, status, progress, objectives }
"Quest.Completed" → { questId, name, rewards }
"Quest.Available" → { questId, name }
```

---

### 2.20 상점 명령어 (NPCShopService)

| 명령어                 | 설명        | Payload                      | Response           |
| ---------------------- | ----------- | ---------------------------- | ------------------ |
| `Shop.List.Request`    | 상점 목록   | `{}`                         | `{ shops: [...] }` |
| `Shop.GetInfo.Request` | 상점 정보   | `{ shopId }`                 | `{ shop: {...} }`  |
| `Shop.Buy.Request`     | 아이템 구매 | `{ shopId, itemId, count? }` | `{ ok }`           |
| `Shop.Sell.Request`    | 아이템 판매 | `{ shopId, slot, count? }`   | `{ ok }`           |
| `Shop.GetGold.Request` | 골드 조회   | `{}`                         | `{ gold }`         |

#### 이벤트:

```lua
"Shop.GoldChanged" → { gold }
```

---

## 3. 에러 코드 목록

### 3.1 네트워크 에러

| 코드                    | 설명                 |
| ----------------------- | -------------------- |
| `NET_UNKNOWN_COMMAND`   | 알 수 없는 명령어    |
| `NET_DUPLICATE_REQUEST` | 중복 요청 (10초 TTL) |

### 3.2 요청 에러

| 코드            | 설명             |
| --------------- | ---------------- |
| `BAD_REQUEST`   | 잘못된 요청 형식 |
| `OUT_OF_RANGE`  | 범위 초과        |
| `INVALID_STATE` | 잘못된 상태      |
| `NO_PERMISSION` | 권한 없음        |
| `COOLDOWN`      | 쿨다운 중        |

### 3.3 인벤토리 에러

| 코드             | 설명             |
| ---------------- | ---------------- |
| `INV_FULL`       | 인벤토리 가득 참 |
| `INVALID_SLOT`   | 잘못된 슬롯      |
| `SLOT_EMPTY`     | 빈 슬롯          |
| `INVALID_COUNT`  | 잘못된 수량      |
| `STACK_OVERFLOW` | 스택 초과        |

### 3.4 건설/제작 에러

| 코드               | 설명              |
| ------------------ | ----------------- |
| `COLLISION`        | 배치 충돌         |
| `STRUCTURE_CAP`    | 구조물 한도 초과  |
| `CRAFT_QUEUE_FULL` | 제작 큐 가득 참   |
| `NO_FACILITY`      | 시설 없음/범위 밖 |
| `RECIPE_LOCKED`    | 레시피 미해금     |

### 3.5 포획/팰 에러

| 코드              | 설명             |
| ----------------- | ---------------- |
| `PALBOX_FULL`     | 보관함 가득 참   |
| `PARTY_FULL`      | 파티 가득 참     |
| `NOT_CAPTURABLE`  | 포획 불가 대상   |
| `CAPTURE_FAILED`  | 포획 실패        |
| `NO_CAPTURE_ITEM` | 포획 아이템 없음 |

### 3.6 기술/성장 에러

| 코드                       | 설명             |
| -------------------------- | ---------------- |
| `TECH_ALREADY_UNLOCKED`    | 이미 해금됨      |
| `INSUFFICIENT_TECH_POINTS` | 기술 포인트 부족 |
| `PREREQUISITES_NOT_MET`    | 선행 기술 미해금 |

### 3.7 수확 에러

| 코드             | 설명        |
| ---------------- | ----------- |
| `NO_TOOL`        | 도구 없음   |
| `WRONG_TOOL`     | 잘못된 도구 |
| `NODE_DEPLETED`  | 노드 고갈   |
| `NODE_NOT_FOUND` | 노드 없음   |

### 3.8 퀘스트 에러

| 코드                   | 설명               |
| ---------------------- | ------------------ |
| `QUEST_NOT_FOUND`      | 퀘스트 없음        |
| `QUEST_PREREQ_NOT_MET` | 선행 퀘스트 미완료 |
| `QUEST_ALREADY_ACTIVE` | 이미 진행 중       |
| `QUEST_MAX_ACTIVE`     | 동시 진행 한도     |

### 3.9 상점 에러

| 코드                | 설명               |
| ------------------- | ------------------ |
| `SHOP_NOT_FOUND`    | 상점 없음          |
| `INSUFFICIENT_GOLD` | 골드 부족          |
| `SHOP_OUT_OF_STOCK` | 재고 부족          |
| `ITEM_NOT_IN_SHOP`  | 상점에 아이템 없음 |
| `ITEM_NOT_SELLABLE` | 판매 불가          |
| `GOLD_CAP_REACHED`  | 골드 한도 도달     |

---

## 4. 클라이언트 컨트롤러 API

### 4.1 InventoryController

```lua
InventoryController.getSlots() → { [slot] = { itemId, count } }
InventoryController.getSlot(slot) → { itemId, count }?
InventoryController.onChanged(callback) -- 변경 이벤트 리스너
```

### 4.2 QuestController

```lua
QuestController.getQuestCache() → { [questId] = QuestState }
QuestController.getActiveQuests() → { Quest... }
QuestController.getCompletedQuests() → { Quest... }
QuestController.requestAccept(questId, callback)
QuestController.requestClaim(questId, callback)
QuestController.onUpdated(callback)
QuestController.onCompleted(callback)
```

### 4.3 ShopController

```lua
ShopController.getGold() → number
ShopController.getShopList() → { Shop... }
ShopController.getShopInfo(shopId) → ShopInfo?
ShopController.requestBuy(shopId, itemId, count?, callback)
ShopController.requestSell(shopId, slot, count?, callback)
ShopController.onGoldChanged(callback)
```

### 4.4 TimeController

```lua
TimeController.getPhase() → "DAY"/"NIGHT"
TimeController.getNormalizedTime() → number (0-1)
TimeController.onPhaseChanged(callback)
```

### 4.5 BuildController

```lua
BuildController.getStructures() → { Structure... }
BuildController.requestPlace(facilityId, position, rotation?, callback)
BuildController.requestRemove(structureId, callback)
```

### 4.6 CraftController

```lua
CraftController.getQueue() → { CraftItem... }
CraftController.requestStart(recipeId, structureId?, callback)
CraftController.requestCancel(craftId, callback)
CraftController.requestCollect(craftId, callback)
```

---

_이 문서는 Origin-WILD 프로젝트의 전체 API를 정리한 레퍼런스입니다._
