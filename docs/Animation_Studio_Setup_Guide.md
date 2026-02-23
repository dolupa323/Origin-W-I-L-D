# 🎮 WildForge 애니메이션 스튜디오 삽입 완전 가이드
> 소스코드 분석 결과 기반 | 2026-02-23 작성

---

## 📌 핵심 원리 (먼저 이해하기)

코드는 `AnimationManager.lua`가 아래 경로에서 애니메이션 객체를 **이름으로 찾습니다**:

```
ReplicatedStorage
  └── Assets
        └── Animations
              ├── [AnimationObject 이름 = 코드가 부르는 이름]
              └── ...
```

따라서 **객체 이름을 정확히 맞춰야** 코드가 찾을 수 있습니다.

---

## 🗂️ 스튜디오 폴더 구조 세팅 (최초 1회)

로블록스 스튜디오에서 아래 폴더를 생성하세요:

```
ReplicatedStorage
  └── Assets          ← Folder 생성
        └── Animations ← Folder 생성 (이 안에 모든 Animation 객체를 넣음)
```

**생성 방법:**
1. Explorer 패널에서 `ReplicatedStorage` 우클릭
2. `Insert Object` → `Folder` 선택
3. 이름을 `Assets`로 변경
4. `Assets` 우클릭 → `Insert Object` → `Folder`
5. 이름을 `Animations`로 변경

---

## 🎬 삽입해야 할 Animation 객체 전체 목록

> 각 항목은 `Animations` 폴더 안에 넣을 **Animation 객체**입니다.
> **객체 이름 = AnimationId 속성에 넣을 rbxassetid 주소**

---

### 1️⃣ 이동 애니메이션 (MovementController 사용)

| Animation 객체 이름 | 언제 재생됨 | 트리거 조건 |
|---|---|---|
| `RollForward` | 구르기 | Ctrl 키 누름 (앞 방향) |

> ⚠️ 현재 `MovementController.lua` 95번째 줄에서 `AnimationIds.ROLL.FORWARD` = `"RollForward"` 만 사용 중.
> 나머지 방향(RollBackward, RollLeft, RollRight)은 AnimationIds에 정의되어 있으나 아직 코드에서 호출하지 않음.

**스튜디오 삽입:**
```
Animations
  └── RollForward    ← Animation 객체, AnimationId = rbxassetid://[구르기 앞 애니메이션 ID]
```

---

### 2️⃣ 전투 - 맨손 콤보 (CombatController 사용)

| Animation 객체 이름 | 언제 재생됨 | 트리거 조건 |
|---|---|---|
| `AttackUnarmed_1` | 맨손 1타 | 좌클릭 (도구 없음) |
| `AttackUnarmed_2` | 맨손 2타 | 0.5초 내 두 번째 클릭 |
| `AttackUnarmed_3` | 맨손 3타 | 0.5초 내 세 번째 클릭 |

**스튜디오 삽입:**
```
Animations
  ├── AttackUnarmed_1    ← Animation 객체
  ├── AttackUnarmed_2    ← Animation 객체
  └── AttackUnarmed_3    ← Animation 객체
```

---

### 3️⃣ 전투 - 도구/도끼/곡괭이 콤보 (CombatController 사용)

> ToolType이 `AXE` 또는 `PICKAXE`인 Tool을 장착했을 때 사용됩니다.

| Animation 객체 이름 | 언제 재생됨 | 트리거 조건 |
|---|---|---|
| `AttackTool_Swing` | 도구 1타 | 좌클릭 (도끼/곡괭이 장착) |
| `AttackTool_Overhead` | 도구 2타 | 두 번째 클릭 |

**스튜디오 삽입:**
```
Animations
  ├── AttackTool_Swing     ← Animation 객체
  └── AttackTool_Overhead  ← Animation 객체
```

---

### 4️⃣ 전투 - 창 (CombatController 사용)

> Tool의 ToolType 속성 = `"SPEAR"` 일 때 사용됩니다.

| Animation 객체 이름 | 언제 재생됨 | 트리거 조건 |
|---|---|---|
| `AttackSpear_Thrust` | 찌르기 1타 | 좌클릭 (창 장착) |
| `AttackSpear_Swing`  | 휘두르기 2타 | 두 번째 클릭 |

**스튜디오 삽입:**
```
Animations
  ├── AttackSpear_Thrust   ← Animation 객체
  └── AttackSpear_Swing    ← Animation 객체
```

---

### 5️⃣ 전투 - 곤봉 (CombatController 사용)

> Tool의 ToolType 속성 = `"CLUB"` 일 때 사용됩니다.

| Animation 객체 이름 | 언제 재생됨 | 트리거 조건 |
|---|---|---|
| `AttackClub_Smash` | 내리찍기 1타 | 좌클릭 (곤봉 장착) |
| `AttackClub_Swing` | 옆 스윙 2타 | 두 번째 클릭 |

**스튜디오 삽입:**
```
Animations
  ├── AttackClub_Smash     ← Animation 객체
  └── AttackClub_Swing     ← Animation 객체
```

---

### 6️⃣ 채집 애니메이션 (InteractController 사용)

> E키를 꾹 눌러 채집할 때 재생됩니다. `NodeType` 속성과 장착 도구에 따라 다르게 재생됩니다.

| Animation 객체 이름 | 언제 재생됨 | 트리거 조건 |
|---|---|---|
| `HarvestChop` | 나무 벌목 | NodeType=`TREE` + AXE 장착 |
| `HarvestMine` | 광석 채굴 | NodeType=`ROCK`/`ORE` + PICKAXE 장착 |
| `HarvestGather` | 기본 손 채집 | 맨손 또는 기타 노드 |

**스튜디오 삽입:**
```
Animations
  ├── HarvestChop      ← Animation 객체 (도끼로 나무 찍기 모션)
  ├── HarvestMine      ← Animation 객체 (곡괭이로 광석 캐기 모션)
  └── HarvestGather    ← Animation 객체 (손으로 모으기 모션)
```

---

### 7️⃣ 기타 애니메이션 (AnimationIds.MISC)

> 현재 코드에서 직접 호출되지는 않지만 AnimationIds에 정의되어 있어 향후 사용될 애니메이션들입니다.

| Animation 객체 이름 | 용도 |
|---|---|
| `InteractHit` | 피격 반응 모션 |
| `InteractDeath` | 사망 모션 |
| `MovementJump` | 점프 모션 |

**스튜디오 삽입 (선택사항, 미리 준비):**
```
Animations
  ├── InteractHit      ← Animation 객체
  ├── InteractDeath    ← Animation 객체
  └── MovementJump     ← Animation 객체
```

---

## 🛠️ Animation 객체 삽입 방법 (단계별)

### Step 1: Animation 객체 만들기
1. `Animations` 폴더 우클릭
2. `Insert Object` → `Animation` 선택
3. 이름을 **위 표의 정확한 이름**으로 변경 (대소문자 정확히!)

### Step 2: AnimationId 설정
1. Animation 객체 클릭
2. Properties 패널에서 `AnimationId` 항목 찾기
3. `rbxassetid://[숫자ID]` 형식으로 입력

### Step 3: 애니메이션 ID 얻는 방법
#### 방법 A - 직접 제작 (Animation Editor)
1. 플러그인 탭 → `Animation Editor` 열기
2. 캐릭터 리그 선택
3. 키프레임 편집
4. `File` → `Publish to Roblox` → 게시
5. 게시 완료 후 URL에서 ID 복사

#### 방법 B - Toolbox에서 무료 애니메이션 사용
1. View → Toolbox → 검색
2. 예: `"roll animation"`, `"attack animation"` 검색
3. Category를 `Animations`으로 설정
4. 마음에 드는 것 선택 → AnimationId 복사

---

## 📋 최종 체크리스트

| 우선순위 | Animation 이름 | 비고 |
|---|---|---|
| 🔴 **필수** | `RollForward` | 구르기 (현재 코드에서 즉시 사용) |
| 🔴 **필수** | `AttackUnarmed_1` | 맨손 1콤보 |
| 🔴 **필수** | `AttackUnarmed_2` | 맨손 2콤보 |
| 🔴 **필수** | `AttackUnarmed_3` | 맨손 3콤보 |
| 🔴 **필수** | `HarvestGather` | 기본 채집 |
| 🔴 **필수** | `HarvestChop` | 도끼 채집 |
| 🔴 **필수** | `HarvestMine` | 곡괭이 채집 |
| 🟡 **권장** | `AttackTool_Swing` | 도끼/곡괭이 1콤보 |
| 🟡 **권장** | `AttackTool_Overhead` | 도끼/곡괭이 2콤보 |
| 🟡 **권장** | `AttackSpear_Thrust` | 창 1콤보 |
| 🟡 **권장** | `AttackSpear_Swing` | 창 2콤보 |
| 🟡 **권장** | `AttackClub_Smash` | 곤봉 1콤보 |
| 🟡 **권장** | `AttackClub_Swing` | 곤봉 2콤보 |
| 🟢 **선택** | `InteractHit` | 피격 (미구현) |
| 🟢 **선택** | `InteractDeath` | 사망 (미구현) |
| 🟢 **선택** | `MovementJump` | 점프 (미구현) |

---

## ⚠️ 주의사항

1. **이름 대소문자 정확히** - `HarvestChop`과 `harvestchop`은 다름!
2. **AnimationId가 없으면 경고만 나오고 무시됨** - 게임이 중단되지는 않지만 모션이 없어 어색함
3. **리그 타입 일치** - R6 캐릭터면 R6용 애니메이션, R15면 R15용으로 제작
4. **Priority는 코드에서 자동 설정** - `Action` 우선순위로 자동 설정되므로 별도 조정 불필요

---

## 🗺️ 최종 Explorer 구조 예시

```
ReplicatedStorage
  └── Assets
        └── Animations
              ├── RollForward        ← [rbxassetid://...]
              ├── AttackUnarmed_1    ← [rbxassetid://...]
              ├── AttackUnarmed_2    ← [rbxassetid://...]
              ├── AttackUnarmed_3    ← [rbxassetid://...]
              ├── AttackTool_Swing   ← [rbxassetid://...]
              ├── AttackTool_Overhead← [rbxassetid://...]
              ├── AttackSpear_Thrust ← [rbxassetid://...]
              ├── AttackSpear_Swing  ← [rbxassetid://...]
              ├── AttackClub_Smash   ← [rbxassetid://...]
              ├── AttackClub_Swing   ← [rbxassetid://...]
              ├── HarvestGather      ← [rbxassetid://...]
              ├── HarvestChop        ← [rbxassetid://...]
              ├── HarvestMine        ← [rbxassetid://...]
              ├── InteractHit        ← [rbxassetid://...]
              ├── InteractDeath      ← [rbxassetid://...]
              └── MovementJump       ← [rbxassetid://...]
```
