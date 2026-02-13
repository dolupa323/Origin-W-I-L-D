# WILD 
Roblox 서바이벌 크래프팅 게임 프로젝트

이 프로젝트는 **Rojo + VS Code + GitHub + Team Create** 구조로 개발됩니다.

---

#  개발 방식 

## 역할 분리

###  코드 → GitHub + VS Code + Rojo
- 서버 로직
- 클라이언트 스크립트
- 모듈 / 리모트
- 모든 Lua 코드

###  맵 / UI / 에셋 → Roblox Studio (Team Create)
- Terrain
- Models
- Lighting
- StarterGui (UI)
- 맵 배치

 **코드는 Git 관리 / 맵은 Studio 관리**
 서로 절대 섞지 않음

# WILD 
Roblox 서바이벌 크래프팅 게임 프로젝트

이 프로젝트는 **Rojo + VS Code + GitHub + Team Create** 구조로 개발됩니다.

---

## 역할 분리

###  코드 → GitHub + VS Code + Rojo
- 서버 로직
- 클라이언트 스크립트
- 모듈 / 리모트
- 모든 Lua 코드

###  맵 / UI / 에셋 → Roblox Studio (Team Create)
- Terrain
- Models
- Lighting
- StarterGui (UI)
- 맵 배치

 **코드는 Git 관리 / 맵은 Studio 관리**
 서로 절대 섞지 않음

---

#  프로젝트 구조

WILD/
src/
server/ 서버 코드
client/ 클라이언트 코드
shared/ 공용 모듈/리모트

default.project.json
README.md


---

#  Rojo 동기화 구조 (자동 생성)

Studio 안에서 이렇게 생김:



ServerScriptService
└ Code
└ Server

StarterPlayerScripts
└ Code
└ Client

ReplicatedStorage
└ Code
└ Shared


 Code 폴더 안은 **절대 Studio에서 수정 금지**
→ VS Code가 원본

---
#  실행 방법

## 1️ Rojo 서버 실행
프로젝트 루트에서:

```powershell
.\rojo serve


정상:

Address: localhost
Port: xxxx

2️ Studio 연결

Studio → Plugins → Rojo → Connect → Accept

3️ 확인
VS Code 저장 → Studio 자동 반영
Play → print 로그 나오면 성공

 개발 워크플로우
코드 작업
VS Code에서 수정
Studio 자동 동기화
테스트
git commit + push
맵UI 작업
Studio에서 수정
Team Create 자동 저장
좋습니다.
지금까지 확정된 아키텍처 원칙 + 요구사항 명세 + 개발 계획 + VSCode/Rojo/Studio 분리 워크플로를 모두 통합하여,


 Roblox Pal-Style Survival Game
Production README / 개발 운영 가이드
 프로젝트 개요

본 프로젝트는 Roblox Studio 기반 오픈월드 생존·제작·포획·자동화 게임을 제작한다.

게임 플레이 구조는 다음 코어 루프를 중심으로 설계된다:

탐험 → 자원 채집 → 제작 → 전투 → 팰 포획/육성 → 베이스 자동화 → 기술 해금 → 상위 지역 반복


목표는 Palworld 스타일과 동일한 시스템 밀도와 구조를 Roblox 환경에서 서버 권한(Server Authoritative) + 데이터 기반(Data Driven) 아키텍처로 구현하는 것이다.

 반드시 읽어야 할 핵심 규칙 (중요)
이 규칙을 어기면 프로젝트는 반드시 붕괴한다.

1. 코드와 에셋은 제작 환경이 다르다
 코드 = VSCode (Rojo)
 에셋 = Roblox Studio
 Studio에서 Script 작성 금지
 Explorer에서 서버 코드 수정 금지
2. 서버 권한(Server Authoritative)

클라이언트는 요청만 한다.
모든 계산은 서버가 결정한다.

서버 처리 대상:

전투
포획
인벤토리
제작
드랍
AI
건축
저장

클라이언트는:
입력
UI 표시
연출만 담당

3. Data Driven
하드코딩 금지.
아래는 반드시 DB에서 정의:

아이템
레시피
팰 종
효과(버프/디버프)
스폰 테이블

테크 트리

4. 개발 순서 (절대 변경 금지)
엔진 → 코어 루프 → Pal → 베이스 자동화 → 콘텐츠 확장

 팰 먼저 만들기 금지
 건축 먼저 만들기 금지
 UI 먼저 만들기 금지

 기술 스택
필수 도구

VSCode
Rojo
Roblox Studio

선택

Wally (패키지 매니저)

 프로젝트 구조
project/
 ├ src/                ← 모든 코드 (VSCode ONLY)
 │   ├ shared/
 │   ├ server/
 │   ├ client/
 │   ├ data/
 │   └ bootstrap/
 │
 ├ assets/             ← Studio ONLY (모델/UI/맵)
 │   ├ prefabs/
 │   ├ ui/
 │   ├ animations/
 │   └ maps/
 │
 ├ default.project.json
 └ README.md

 Rojo 매핑
ReplicatedStorage
 ├ Shared   ← src/shared
 ├ Data     ← src/data

ServerScriptService ← src/server
StarterPlayerScripts ← src/client

 아키텍처 요약
공통 원칙
모든 객체는 EntityBase 상속

Player
Pal
Resource
Structure
Drop

모든 상호작용은 InteractSystem
모든 전투는 CombatSystem
모든 상태효과는 EffectSystem
모든 인벤은 InventoryService
 핵심 시스템 목록 (필수 구현)

아래 시스템이 모두 존재해야 게임이 정상 동작한다.

Engine Layer (필수)

Net (Remote 래퍼)
SaveService
EntityService
InventoryService
EquipService
InteractService
DropService
EffectService
CombatSyste
AISystem / SpawnSystem
Core Loop
ResourceNode
Crafting
Tools/Weapons
Enemy
Pal Layer
PalEntity
CaptureSystem
PartySystem
Palbox
Base Layer
Building Snap
Claim
Automation

 역할 분업
 프로그래머 (VSCode)

Services

Systems

DB

네트워크

전투/AI/저장

 디자이너/아티스트 (Studio)

모델

프리팹

UI

애니메이션

맵

주의

Prefab 안에 Script 작성 금지

 개발 시작 방법
1. 저장소 클론
git clone ...
cd project

2. Rojo 실행
rojo serve

3. Roblox Studio → Rojo 연결

자동 동기화 시작

 개발 워크플로
프로그래머

VSCode에서 src 수정

Studio에서 테스트

커밋

디자이너

Studio에서 Prefab/UI 제작

Script 건드리지 않기

커밋

 모듈 개발 규칙
각 시스템은 반드시 제공해야 함

Public API

Remote 계약

Data Schema

완료 기준(Test 가능)

다른 시스템 내부 코드 직접 호출 금지
→ API로만 접근

 개발 단계(Milestone)
M0 — 엔진 부팅

Bootstrap

Net

폴더 구조

M1 — 엔진 완성

인벤/전투/드랍/상태/AI 프레임

M2 — 코어 루프

채집/제작/사냥 가능

M3 — Pal

포획/소환/작업

M4 — 베이스/자동화

건축/운영

M5 — 콘텐츠 확장
 금지 사항 (중요)

 Studio에서 Script 작성
 클라이언트에서 데미지 계산
 하드코딩 아이템
 여러 시스템 동시 개발
 Bootstrap 순서 변경

 완료 기준 (게임 완성 체크)

 채집 → 제작 → 전투 루프 가능

 팰 포획/소환/작업 가능

 베이스 자동화 가능

 서버 재접속 시 데이터 유지

 치트 불가

 핵심 철학 (한 줄 요약)

Script는 VSCode에서만, Studio는 에셋만.
서버가 모든 것을 결정한다.
시스템부터 만들고, 콘텐츠는 나중에 붙인다.
