# WildForge UI/UX 시스템 명세서 (Refactoring용)

이 문서는 현재 `UIManager.lua`에 구현된 모든 UI/UX 요소와 기능을 문서화한 것입니다. 리팩터링 시 이 명세를 기준으로 모듈화 작업을 진행합니다.

## 1. 전역 테마 및 유틸리티 (UITheme & UIUtils)
현재는 `UIManager.lua` 내부 로컬 테이블 `C`와 `F`, 그리고 `mkFrame`, `mkLabel`, `mkBtn` 등의 로컬 함수로 관리되고 있습니다.

*   **Color Palette (C)**:
    *   `BG_PANEL`: 반투명 블랙 (0.6 - 0.7)
    *   `GOLD`: `Color3.fromRGB(255, 210, 80)` - 포인트 컬러
    *   `BTN_CRAFT`: 제작/강조 버튼용 브라운/골드
    *   `HP/STA/XP`: 각각 레드, 옐로우, 화이트
*   **Fonts (F)**: GothamMedium, GothamBold 중심
*   **Scale**: `UI_SCALE` 변수를 통한 해상도 보정 (기본 1.0)

## 2. HUD (Heads-Up Display)
상시 노출되거나 상황에 따라 나타나는 기본 인터페이스입니다.

| 요소 | 위치 | 기능 | 관련 변수 |
| :--- | :--- | :--- | :--- |
| **Vitals HUD** | 우측 상단 | HP, Stamina, XP, Level 표시 | `healthBar`, `staminaBar`, `xpBar`, `levelLabel` |
| **Hotbar** | 하단 중앙 | 8개 슬롯, 아이템 장착 및 사용 | `hotbarSlots`, `selectedHotbarSlot` |
| **Quick Actions** | 우측 하단 | Z, E, C, B 키에 대응하는 버튼 아이콘 | `actionContainer` |
| **Harvest Bar** | 상단 중앙 | 자원 수집 시 진행도 및 대상명 표시 | `harvestFrame`, `harvestBar`, `harvestPct` |
| **Interact Prompt** | 중앙 하단 | 상호작용 가능 시 대상명과 안내문 노출 | `interactPrompt`, `showInteractPrompt` |
| **Notifications** | 중앙 하단 | 시스템 메시지 (애니메이션 포함) | `_notifyLabel`, `notify()` |

## 3. 메뉴 시스템 (Overlays)
특정 키를 눌러 활성화하는 전체 화면 또는 팝업 메뉴입니다.

### 3.1 인벤토리 (Inventory - 'B' 키)
*   **Bag Grid**: 40개 슬롯 (Balance.INV_SLOTS 기준)
*   **Detail Panel**: 선택한 아이템의 이름, 아이콘, 무게, 수량, 설명 표시.
*   **Weight Bar**: 현재 무게 / 최대 무게 게이지.
*   **Tabs**: '소지품'과 '개인 제작' 탭 전환.

### 3.2 능력치 (Status - 'E' 키)
*   **Stat Points**: 레벨업 시 획득한 포인트 잔량 표시.
*   **Stat List**: 근력, 민첩, 지능, 지구력, 생존력 등 5종 스탯 강화 버튼.

### 3.3 제작 (Crafting - 'C' 키)
*   *참고: 인벤토리 내부 탭과 별도의 제작 창(공방용)이 혼용 중일 수 있음*
*   **Recipe Grid**: 해금된 레시피 목록.
*   **Requirements**: 필요 재료 보유 현황 체크 (`checkMaterials`).
*   **Crafting Progress**: 제작 시간 동안 로딩 스피너 및 진행바 표시.

### 3.4 상점 (Shop)
*   **Buy/Sell Tabs**: 구매 및 판매 모드 전환.
*   **Gold Label**: 현재 보유 골드 표시.

### 3.5 기술 트리 (Tech Tree - 'K' 키)
*   **TP Display**: 보유 기술 포인트 표시.
*   **Tech Graph**: 다이아몬드 형태의 노드 연결 구조.
*   **Unlock**: 조건 만족 시 기술 연구/해금.

## 4. 리팩터링 가이드라인

현재 `UIManager.lua`는 2200라인이 넘는 **God Object**입니다. 다음과 같은 구조로 분리해야 합니다:

1.  **UITheme.lua**: 컬러, 폰트, 공통 트윈 정보 관리.
2.  **UIUtils.lua**: `mkFrame`, `mkSlot`, `mkBar` 등 위젯 생성자 관리.
3.  **개별 모듈화**:
    *   `HUD.lua`: Vitals, Hotbar, Actions.
    *   `InventoryPane.lua`: Bag, Detail, Weight.
    *   `CraftingPane.lua`: Recipe list, Progress.
    *   `StatusPane.lua`: Stats list.
    *   `TechTreePane.lua`: Tech graph.
4.  **UIManager.lua**: 위 모듈들을 제어하고 서버(NetClient)와 통신하며 데이터를 전달하는 **Controller** 역할에 집중.

## 5. 현재 UX 로직 (동작 방식)
*   **Input**: `InputManager`를 통해 키 입력을 받고 `UIManager`의 `toggleX` 함수 호출.
*   **Data Flow**: `InventoryController` 등의 데이터 소스에서 정보를 가져와 UI를 갱신 (`refreshInventory`, `updateHealth` 등).
*   **Feedback**: 성공/실패 시 `notify` 호출, 게이지는 `TweenService`로 부드럽게 갱신.
