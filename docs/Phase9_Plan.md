# Phase 9: NPC 상점 시스템 (NPC Shop System)

> **작성일**: 2026-02-16  
> **목표**: NPC 상점 시스템 구현 - 구매/판매, 통화, 상점 인터랙션

---

## 1. 개요

### 1.1 핵심 목표

- NPC 상점 정의 및 상품 목록 관리
- 통화(골드) 시스템
- 아이템 구매/판매 처리
- 상점 인벤토리 재고 시스템 (선택사항)

### 1.2 시스템 구성

```
NPCShopData.lua       - 상점 및 상품 데이터
NPCShopService.lua    - 상점 거래 처리 (서버)
ShopController.lua    - 클라이언트 UI 연동
```

---

## 2. 데이터 구조

### 2.1 NPCShopData.lua

```lua
NPCShopData.GENERAL_STORE = {
  id = "GENERAL_STORE",
  name = "잡화점",
  description = "기본 물품을 판매하는 상점입니다.",
  npcName = "상인 톰",

  -- 판매 상품
  buyList = {
    { itemId = "WOOD", price = 5, stock = -1 },          -- -1 = 무한 재고
    { itemId = "STONE", price = 3, stock = -1 },
    { itemId = "PAL_SPHERE", price = 50, stock = 10 },   -- 제한 재고
  },

  -- 구매 가격 (판매가 = 구매가 × sellMultiplier)
  sellMultiplier = 0.5,  -- 판매시 50% 가격

  -- 특수 구매 (플레이어가 상점에 팔 수 있는 아이템)
  sellList = {
    { itemId = "RAW_MEAT", price = 8 },
    { itemId = "LEATHER", price = 15 },
  },

  -- 상점 위치 (월드 좌표 또는 NPC 참조)
  position = nil,  -- 런타임에 설정
}
```

### 2.2 Currency (통화)

```lua
-- PlayerState에 gold 필드 추가
playerState.gold = 0  -- 시작 골드
```

---

## 3. 서비스 API

### 3.1 NPCShopService

```lua
-- 초기화
NPCShopService.Init(NetController, DataService, InventoryService, SaveService)

-- 상점 관리
NPCShopService.getShopInfo(shopId)                    -- 상점 정보 조회
NPCShopService.buyItem(player, shopId, itemId, count) -- 아이템 구매
NPCShopService.sellItem(player, shopId, slot, count)  -- 아이템 판매 (인벤 슬롯)
NPCShopService.getPlayerGold(userId)                  -- 골드 조회
NPCShopService.addGold(userId, amount)                -- 골드 추가
NPCShopService.removeGold(userId, amount)             -- 골드 차감

-- 핸들러
NPCShopService.GetHandlers()
```

### 3.2 Protocol 명령어

```lua
["Shop.GetInfo.Request"] = true,      -- 상점 정보 요청
["Shop.Buy.Request"] = true,          -- 아이템 구매
["Shop.Sell.Request"] = true,         -- 아이템 판매
["Shop.GetGold.Request"] = true,      -- 골드 조회
```

### 3.3 이벤트

```lua
"Shop.Gold.Changed"    -- 골드 변경 알림
"Shop.Buy.Result"      -- 구매 결과
"Shop.Sell.Result"     -- 판매 결과
```

---

## 4. Balance 상수

```lua
Balance.SHOP_SELL_MULTIPLIER = 0.5     -- 기본 판매 배율 (50%)
Balance.SHOP_INTERACT_RANGE = 5        -- 상점 인터랙션 거리 (스터드)
Balance.STARTING_GOLD = 100            -- 시작 골드
Balance.GOLD_CAP = 999999              -- 최대 골드
```

---

## 5. 구현 순서

### 9-1: 데이터 레이어

- [ ] NPCShopData.lua 상점 정의 (3개 상점)
- [ ] Enums 확장 (ShopType, ShopError 등)
- [ ] Balance 확장 (SHOP\_\* 상수)
- [ ] Protocol 확장 (Shop.\* 명령어)

### 9-2: NPCShopService 코어

- [ ] 골드 시스템 (SaveService 연동)
- [ ] buyItem (가격 검증, 재고 확인, 인벤토리 추가)
- [ ] sellItem (아이템 검증, 골드 추가, 인벤토리 제거)
- [ ] 이벤트 발행

### 9-3: 클라이언트 컨트롤러

- [ ] ShopController.lua (이벤트 수신, 캐시 관리)

---

## 6. 상점 목록

### 기본 상점

| ID            | 이름    | 설명         | 주요 상품              |
| ------------- | ------- | ------------ | ---------------------- |
| GENERAL_STORE | 잡화점  | 기본 물품    | 나무, 돌, 섬유, 부싯돌 |
| TOOL_SHOP     | 도구점  | 도구 판매    | 곡괭이, 도끼, 검       |
| PAL_SHOP      | 팰 상점 | 포획/팰 용품 | 팰 구슬, 팰 먹이       |

---

## 7. 검증 항목

| 검증        | ErrorCode         | 조건                          |
| ----------- | ----------------- | ----------------------------- |
| 상점 존재   | SHOP_NOT_FOUND    | 상점 데이터 없음              |
| 상품 존재   | ITEM_NOT_IN_SHOP  | 상점에 없는 아이템            |
| 골드 부족   | INSUFFICIENT_GOLD | 구매 금액 부족                |
| 재고 부족   | SHOP_OUT_OF_STOCK | 재고 소진                     |
| 인벤 가득   | INV_FULL          | 구매 시 인벤토리 가득         |
| 아이템 없음 | SLOT_EMPTY        | 판매 시 슬롯 비어있음         |
| 판매 불가   | ITEM_NOT_SELLABLE | 상점에서 구매하지 않는 아이템 |

---

_Phase 9 완료 기준: 상점 열기 → 아이템 구매/판매 → 골드 변동 전체 플로우 동작_
