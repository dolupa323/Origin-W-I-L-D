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
		maxHealth = 20,
		walkSpeed = 8,
		runSpeed = 12,
		damage = 0,
		attackRange = 0,
		detectRange = 12,
		behavior = "PASSIVE",
		modelName = "DodoBird",
		xpReward = 5,
	},
	{
		id = "COMPY",
		name = "콤프소그나투스",
		description = "아주 작고 빠른 소형 공룡. 호기심이 많다",
		maxHealth = 15,
		walkSpeed = 10,
		runSpeed = 18,
		damage = 2,
		attackRange = 3,
		detectRange = 8,
		behavior = "PASSIVE",
		modelName = "Compy",
		xpReward = 3,
	},
	{
		id = "PARASAUR",
		name = "파라사우롤로푸스",
		description = "평화로운 대형 초식공룡. 빠르게 달린다",
		maxHealth = 200,
		walkSpeed = 12,
		runSpeed = 22,
		damage = 0,
		attackRange = 0,
		detectRange = 25,
		behavior = "PASSIVE",
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
		maxHealth = 400,
		walkSpeed = 10,
		runSpeed = 18,
		damage = 30,
		attackRange = 6,
		detectRange = 18,
		behavior = "NEUTRAL",
		modelName = "Triceratops",
		xpReward = 40,
	},
	{
		id = "STEGOSAURUS",
		name = "스테고사우루스",
		description = "등에 거대한 골판을 가진 초식공룡",
		maxHealth = 350,
		walkSpeed = 8,
		runSpeed = 14,
		damage = 25,
		attackRange = 7,
		detectRange = 15,
		behavior = "NEUTRAL",
		modelName = "Stegosaurus",
		xpReward = 35,
	},
	{
		id = "ANKYLOSAURUS",
		name = "안킬로사우루스",
		description = "갑옷 같은 피부와 꼬리 곤봉을 가진 방어형 공룡",
		maxHealth = 500,
		walkSpeed = 6,
		runSpeed = 10,
		damage = 35,
		attackRange = 6,
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
		maxHealth = 100,
		walkSpeed = 14,
		runSpeed = 26,
		damage = 12,
		attackRange = 5,
		detectRange = 30,
		behavior = "AGGRESSIVE",
		modelName = "Raptor",
		xpReward = 25,
	},
	{
		id = "TREX",
		name = "티라노사우루스",
		description = "공포의 폭군. 섬에서 가장 강력한 포식자",
		maxHealth = 800,
		walkSpeed = 12,
		runSpeed = 24,
		damage = 60,
		attackRange = 8,
		detectRange = 40,
		behavior = "AGGRESSIVE",
		modelName = "TRex",
		xpReward = 120,
	},
}

return CreatureData
