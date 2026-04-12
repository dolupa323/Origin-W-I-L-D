# Origin-WILD 작업 요약

## 1. 개요

현재까지 수행된 주요 수정 작업을 정리한 문서입니다. 이 문서는 최신 버그 수정 내역과 관련 파일, 현재 상태를 한눈에 파악할 수 있도록 구성되었습니다.

## 2. 수정된 주요 버그

### 2.1. 파티 슬롯 3개 제한 문제

- **문제**: UI가 5마리를 지원하도록 설계되어 있으나, 펫 슬롯 렌더링이 `for i = 1, 3 do`로 하드코딩되어 3개만 표시됨.
- **수정 파일**: `src/StarterPlayer/StarterPlayerScripts/Client/UI/CollectionUI.lua`
- **수정 내용**:
  - 슬롯 렌더링 루프를 `for i = 1, maxSlots do`로 변경
  - `maxSlots`는 서버에서 전달되는 `Balance.MAX_PARTY` 값을 기반으로 정상 동작

### 2.2. 공룡 특성 레벨 미표시

- **문제**: `InventoryUI`에서 특성 효과치는 계산되었으나 레벨 정보가 UI에 표시되지 않음.
- **수정 파일**: `src/StarterPlayer/StarterPlayerScripts/Client/UI/InventoryUI.lua`
- **수정 내용**:
  - `traitValue` 문자열에 `Lv.%d` 형식으로 레벨 추가
  - 결과: `▲8% (Lv.3)` 형태로 표시

### 2.3. 랩터 공격 시 IDLE 애니메이션 재생

- **문제**: `CreatureAnimationController`가 `State == "ATTACK"`일 때 `animKey = "IDLE"`로 맵핑되어 공격 직전 IDLE 애니메이션이 재생됨.
- **수정 파일**: `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CreatureAnimationController.lua`
- **수정 내용**:
  - ATTACK 상태에서는 현재 재생 중인 애니메이션(`info.lastAnim`)을 유지하도록 변경
  - 공격 애니메이션은 `isAttacking` 플래그가 설정될 때 별도로 재생

### 2.4. 고대 포탈 텔레포트 위치 문제

- **문제**: `Portal_Return_Tropical` 위치 대신 엉뚱한 지점으로 텔레포트되며, 물/위험 지형에서 사망이 발생.
- **수정 파일**: `src/ServerScriptService/Server/Services/PortalService.lua`
- **수정 내용**:
  - 도착 좌표를 포탈 위치가 아닌 `SpawnConfig.GetZoneInfo(targetZoneName).spawnPoint` 기반으로 기본 설정
  - Raycast에서 도착 포탈 오브젝트를 제외하여 포탈 표면이 지면으로 인식되는 문제 방지
  - Water 지형을 감지하면 안전한 스폰포인트 높이 그대로 사용
  - ForceField 무적 시간을 3초에서 5초로 연장하여 도착 직후 충돌 시간을 확보

### 2.5. ForceField 중 환경 디버프 적용 차단

- **문제**: 포탈 도착 직후 ForceField가 있어도 `DebuffService`에서 CHILLY/WARMTH/FREEZING 디버프를 적용할 가능성이 있음.
- **수정 파일**: `src/ServerScriptService/Server/Services/DebuffService.lua`
- **수정 내용**:
  - 캐릭터에 `ForceField`가 있을 경우 환경 디버프를 일시적으로 제거하고 적용하지 않도록 수정

## 3. 관련 코드 경로

- `src/ServerScriptService/Server/Services/PortalService.lua`
- `src/ServerScriptService/Server/Services/DebuffService.lua`
- `src/StarterPlayer/StarterPlayerScripts/Client/UI/CollectionUI.lua`
- `src/StarterPlayer/StarterPlayerScripts/Client/UI/InventoryUI.lua`
- `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CreatureAnimationController.lua`
- `src/ReplicatedStorage/Shared/Config/SpawnConfig.lua`

## 4. 현재 상태

- 파티 슬롯 5개 렌더링은 클라이언트 UI 수정으로 해결됨.
- 특성 레벨 표시 문제는 UI 문자열 수정으로 해결됨.
- 랩터 공격 애니메이션 문제는 클라이언트 상태 매핑 수정으로 해결됨.
- 포탈 텔레포트 문제는 서버 측 도착 좌표 로직과 디버프 면역 처리로 개선됨.

## 5. 남은 확인 사항

- 포탈에 실제 워크스페이스 상에서 `Portal_Return_Tropical` 위치가 올바른지 직접 확인 필요
- TROPICAL 존의 `spawnPoint` 주변에 위험 지형이나 즉시 공격하는 생물이 없는지 검증 필요
- 수정 이후 실제 플레이 테스트를 통해 5초 무적, CHILLY 적용 여부, 포탈 도착 위치 로그를 확인해야 함

## 6. 권장 추가 개선

- `PortalService`가 `workspace:FindFirstChild` 대신 포탈 검색을 재귀로 처리하거나, 포탈이 항상 최상위에 존재하는지 설계 명확화
- 포탈 오브젝트 자체의 위치 설정을 맵 에디터에서 직접 조정
- `SpawnConfig`의 `TROPICAL.spawnPoint` 값과 실제 맵 내 귀환 포탈 위치 동기화
