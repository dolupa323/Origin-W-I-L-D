# 포획 & 길들이기 확률 시스템

> ⚠️ **개발 모드**: 현재 포획/길들이기 확률이 **100%** 로 고정되어 있습니다.
> 릴리스 시 원래 공식으로 복원하세요.

---

## 1. 포획 확률 (CaptureService)

**파일**: `src/ServerScriptService/Server/Services/CaptureService.lua`  
**함수**: `calcCaptureRate(creatureId, tamingBonus)`

### 원래 공식

```
baseRate = clamp(0.50 - level × 0.05, 0.05, 0.50)
finalRate = clamp(baseRate + tamingBonus, 0.03, 0.60)
```

### 레벨별 기본 확률 (스킬 보너스 제외)

| 크리처        | 레벨 | 기본 확률 |
| ------------- | ---- | --------- |
| DODO          | 1    | 45%       |
| COMPY         | 2    | 40%       |
| DILOPHOSAURUS | 4    | 30%       |
| PARASAUR      | 5    | 25%       |
| RAPTOR        | 6    | 20%       |
| STEGOSAURUS   | 7    | 15%       |
| TRICERATOPS   | 8    | 10%       |
| ANKYLOSAURUS  | 10   | 5% (최소) |

### 판정 방식

- `roll = math.random()` → `roll <= captureRate` 이면 성공
- 실패 시 크리처 사망 (재시도 불가)

---

## 2. 길들이기 확률 (InventoryService - CAPTURE_BOX 사용)

**파일**: `src/ServerScriptService/Server/Services/InventoryService.lua`  
**위치**: `handleUse()` → `CAPTURE_BOX` 분기

### 원래 공식 (포획과 동일)

```
baseTameRate = clamp(0.50 - creatureLevel × 0.05, 0.05, 0.50)
finalRate = clamp(baseTameRate + tamingBonus, 0.03, 0.60)
```

### 판정 방식

- `roll = math.random()` → `roll <= finalRate` 이면 성공
- 실패 시 박스 아이템 소모
- 성공 시 PalboxService에 팰 등록

---

## 3. 스킬 보너스 (SkillTreeData)

**파일**: `src/ReplicatedStorage/Data/SkillTreeData.lua`  
**함수**: `GetTamingRateBonus(learnedList)`

| 스킬 ID   | 이름        | 레벨 요구 | 보너스 |
| --------- | ----------- | --------- | ------ |
| TAMING_T1 | 초급 포획   | 10        | +2%    |
| TAMING_T2 | 중급 포획   | 20        | +3%    |
| TAMING_T3 | 고급 포획   | 30        | +4%    |
| TAMING_T4 | 전문 포획   | 40        | +5%    |
| TAMING_T5 | 마스터 포획 | 50        | +6%    |

- **최대 누적**: +20%

---

## 4. 개발 모드 100% 설정 위치

복원 시 아래 위치의 `-- [DEV] 개발용 100%` 주석을 찾아 원래 코드로 복원하세요:

1. **CaptureService.lua** - `calcCaptureRate()` 함수
2. **InventoryService.lua** - `handleUse()` → `CAPTURE_BOX` 분기 내 확률 계산부
