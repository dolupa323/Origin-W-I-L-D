-- CreatureData.lua
-- 크리처/공룡/동물 데이터 정의
-- behavior: AGGRESSIVE(선공), NEUTRAL(맞으면 반격), PASSIVE(도망)
-- ※ 실제 모델이 있는 크리처만 등록

local CreatureData = {
	--========================================
	-- 초식 / PASSIVE (도망형)
	--========================================
	{
		id = "DODO",
		name = "도도새",
		description = "약하고 느리지만 포획하기 쉬운 새",
		maxHealth = 30,
		maxTorpor = 20,
		walkSpeed = 8,
		runSpeed = 12,
		damage = 5,
		attackRange = 4,
		detectRange = 12,
		behavior = "NEUTRAL",
		modelName = "DODO", -- 폴더 이름과 일치
		xpReward = 5,
		icon = "rbxassetid://0", -- 실제 아이콘 ID 추가 필요
	},
	{
		id = "COMPY",
		name = "콤프소그나투스",
		description = "아주 작고 빠른 소형 공룡. 호기심이 많다",
		maxHealth = 12, -- 체력 대폭 하향 (무리 스폰 대응)
		maxTorpor = 10, -- 기절 수치도 함께 하향
		walkSpeed = 10,
		runSpeed = 22, -- 더 기민하게 추격
		damage = 10,
		attackRange = 5,
		detectRange = 30, -- 탐지 범위 확대
		behavior = "AGGRESSIVE", -- 선공형으로 변경
		modelName = "COMPY", -- 폴더 이름과 일치
		groupSize = 3, -- 3마리씩 무리지어 스폰
		xpReward = 3,
		icon = "rbxassetid://0",
	},
	{
		id = "PARASAUR",
		name = "파라사우롤로푸스",
		description = "평화로운 대형 초식공룡. 빠르게 달린다",
		maxHealth = 400,
		maxTorpor = 300,
		walkSpeed = 12,
		runSpeed = 22,
		damage = 20,
		attackRange = 10,
		detectRange = 25,
		behavior = "NEUTRAL",
		modelName = "Parasaur",
		xpReward = 20,
	},

	--========================================
	-- 초식 / NEUTRAL (반격형)
	--========================================
	{
		id = "TRICERATOPS",
		name = "트리케라톱스",
		description = "단단한 뿔을 가진 초식공룡. 건드리면 위험하다",
		maxHealth = 1200,
		maxTorpor = 1000,
		walkSpeed = 10,
		runSpeed = 18,
		damage = 45,
		attackRange = 12,
		detectRange = 18,
		behavior = "NEUTRAL",
		modelName = "Triceratops",
		xpReward = 40,
		attackDelay = 1.3, -- 공격 애니메이션 종료 후 타격 판정 (Prep 0.6s + Charge 0.6s + 여유 0.1s)
	},
	{
		id = "BABY_TRICERATOPS",
		name = "아기 트리케라톱스",
		description = "아직 뿔이 다 자라지 않은 어린 트리케라톱스. 겁이 많다.",
		maxHealth = 150,
		maxTorpor = 100,
		walkSpeed = 12,
		runSpeed = 20,
		damage = 10,
		attackRange = 6,
		detectRange = 15,
		behavior = "NEUTRAL", -- 아기도 성체처럼 반격함
		modelName = "BABY_TRICERATOPS", -- 전용 모델 사용
		scale = 1, -- 전용 모델이므로 스케일은 1 (필요 시 조절 가능)
		xpReward = 15,
	},
	{
		id = "STEGOSAURUS",
		name = "스테고사우루스",
		description = "등에 거대한 골판을 가진 초식공룡",
		maxHealth = 1000,
		maxTorpor = 850,
		walkSpeed = 8,
		runSpeed = 14,
		damage = 40,
		attackRange = 12,
		detectRange = 15,
		behavior = "NEUTRAL",
		modelName = "Stegosaurus",
		xpReward = 35,
	},
	{
		id = "ANKYLOSAURUS",
		name = "안킬로사우루스",
		description = "갑옷 같은 피부와 꼬리 곤봉을 가진 방어형 공룡",
		maxHealth = 1500,
		maxTorpor = 1200,
		walkSpeed = 6,
		runSpeed = 10,
		damage = 40,
		attackRange = 10,
		detectRange = 12,
		behavior = "NEUTRAL",
		modelName = "Ankylosaurus",
		xpReward = 50,
	},

	--========================================
	-- 육식 / AGGRESSIVE (선공형)
	--========================================
	{
		id = "RAPTOR",
		name = "랩터",
		description = "빠르고 민첩한 소형 육식공룡",
		maxHealth = 150,
		maxTorpor = 120,
		walkSpeed = 12,
		runSpeed = 24,
		damage = 15,
		attackRange = 8, -- 5 -> 8 상향
		detectRange = 50, -- 22 -> 50 상향
		behavior = "AGGRESSIVE",
		modelName = "Raptor",
		xpReward = 25,
	},
	{
		id = "TREX",
		name = "티라노사우루스",
		description = "공포의 폭군. 섬에서 가장 강력한 포식자",
		maxHealth = 4500,
		maxTorpor = 3500,
		walkSpeed = 10,
		runSpeed = 22,
		damage = 120,
		attackRange = 12, -- 8 -> 12 상향
		detectRange = 80, -- 30 -> 80 상향
		behavior = "AGGRESSIVE",
		modelName = "TRex",
		xpReward = 120,
	},
}

return CreatureData
