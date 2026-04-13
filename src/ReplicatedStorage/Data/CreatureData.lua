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
		level = 1,
		maxHealth = 30,
		maxTorpor = 20,
		walkSpeed = 5,
		runSpeed = 8,
		damage = 5,
		attackRange = 4,
		detectRange = 12,
		attackDelay = 0.4,
		attackCooldown = 2.0,
		behavior = "NEUTRAL",
		modelName = "DODO",
		xpReward = 5,
		-- 도감 시스템
		dnaRequired = 3,
		passiveEffect = { stat = "workSpeed", value = 5 },       -- 작업 속도 +5
		petScale = 5.0,     -- 목표 크기 (스터드)
		petDamage = 3,
		petDefense = 5,
		petHealth = 20,
		palBagSlots = 1,
	},
	{
		id = "COMPY",
		name = "콤프소그나투스",
		description = "아주 작고 빠른 소형 공룡. 호기심이 많다",
		level = 2,
		maxHealth = 12,
		maxTorpor = 10,
		walkSpeed = 7,
		runSpeed = 14,
		damage = 10,
		attackRange = 5,
		detectRange = 30,
		attackDelay = 0.3,
		attackCooldown = 1.8,
		behavior = "AGGRESSIVE",
		modelName = "COMPY",
		groupSize = 2,
		xpReward = 3,
		-- 도감 시스템
		dnaRequired = 3,
		passiveEffect = { stat = "attackMult", value = 0.03 },   -- 공격력 +3%
		petScale = 4.0,     -- 목표 크기 (스터드)
		petDamage = 6,
		petDefense = 8,
		petHealth = 15,
		palBagSlots = 1,
	},
	{
		id = "PARASAUR",
		name = "파라사우롤로푸스",
		description = "평화로운 대형 초식공룡. 빠르게 달린다",
		level = 5,
		maxHealth = 2500,
		maxTorpor = 300,
		walkSpeed = 8,
		runSpeed = 14,
		damage = 20,
		attackRange = 10,
		detectRange = 25,
		attackDelay = 0.6,
		attackCooldown = 6.25,
		behavior = "NEUTRAL",
		modelName = "Parasaur",
		xpReward = 20,
		attacks = {
			{ name = "침뼉기", pattern = "CONE", angle = 90, range = 25, damage = 20, windupTime = 3.6, attackTime = 0.5, anim = "SPIT" },
			{ name = "꼬리치기", pattern = "CIRCLE", radius = 16, damage = 15, windupTime = 5.4, attackTime = 0.5, anim = "ATTACK" },
		},
		-- 도감 시스템
		dnaRequired = 5,
		passiveEffect = { stat = "maxStamina", value = 15 },     -- 최대 기력 +15
		petScale = 7.0,     -- 목표 크기 (스터드)
		petDamage = 10,
		petDefense = 15,
		petHealth = 80,
		mountable = true,
		mountSeatOffset = Vector3.new(0, 4.5, -7.8),
		mountSpeedMultiplier = 1.0,
		mountJumpPower = 46,
		palBagSlots = 8,
	},

	--========================================
	-- 초식 / NEUTRAL (반격형)
	--========================================
	{
		id = "TRICERATOPS",
		name = "트리케라톱스",
		description = "단단한 뿔을 가진 초식공룡. 건드리면 위험하다",
		level = 8,
		maxHealth = 7000,
		maxTorpor = 1000,
		walkSpeed = 6,
		runSpeed = 12,
		damage = 35,
		attackRange = 12,
		detectRange = 18,
		behavior = "NEUTRAL",
		modelName = "Triceratops",
		xpReward = 40,
		attackDelay = 1.3,
		attackCooldown = 8.75,
		attacks = {
			{ name = "박치기", pattern = "CONE", angle = 90, range = 25, damage = 35, windupTime = 3.6, attackTime = 0.7, anim = "ATTACK" },
			{ name = "앞발찍기", pattern = "CIRCLE", radius = 18, damage = 25, windupTime = 6.0, attackTime = 0.5, anim = "STOMP" },
		},
		-- 도감 시스템
		dnaRequired = 5,
		passiveEffect = { stat = "defense", value = 5 },         -- 방어력 +5
		petScale = 7.0,     -- 목표 크기 (스터드)
		petDamage = 20,
		petDefense = 30,
		petHealth = 200,
		palBagSlots = 24,
	},
	{
		id = "BABY_TRICERATOPS",
		name = "아기 트리케라톱스",
		description = "아직 뿔이 다 자라지 않은 어린 트리케라톱스. 겁이 많다.",
		level = 3,
		maxHealth = 150,
		maxTorpor = 100,
		walkSpeed = 8,
		runSpeed = 13,
		damage = 10,
		attackRange = 6,
		detectRange = 15,
		attackDelay = 0.5,
		attackCooldown = 2.0,
		behavior = "NEUTRAL",
		modelName = "BABY_TRICERATOPS",
		scale = 1,
		xpReward = 15,
		-- 도감 시스템
		dnaRequired = 3,
		passiveEffect = { stat = "maxHealth", value = 10 },      -- 최대 체력 +10
		petScale = 5.0,     -- 목표 크기 (스터드)
		petDamage = 5,
		petDefense = 10,
		petHealth = 50,
		palBagSlots = 4,
	},
	{
		id = "STEGOSAURUS",
		name = "스테고사우루스",
		description = "등에 거대한 골판을 가진 초식공룡",
		level = 7,
		maxHealth = 4500,
		maxTorpor = 850,
		walkSpeed = 5,
		runSpeed = 10,
		damage = 20,
		attackRange = 12,
		detectRange = 15,
		attackDelay = 0.8,
		attackCooldown = 7.5,
		behavior = "NEUTRAL",
		modelName = "Stegosaurus",
		xpReward = 35,
		attacks = {
			{ name = "꼬리치기", pattern = "CIRCLE", radius = 18, damage = 20, windupTime = 5.4, attackTime = 0.5, anim = "ATTACK" },
		},
		-- 도감 시스템
		dnaRequired = 5,
		passiveEffect = { stat = "maxHealth", value = 20 },      -- 최대 체력 +20
		petScale = 7.0,     -- 목표 크기 (스터드)
		petDamage = 18,
		petDefense = 25,
		petHealth = 180,
		palBagSlots = 12,
	},
	{
		id = "ANKYLOSAURUS",
		name = "안킬로사우루스",
		description = "갑옷 같은 피부와 꼬리 곤봉을 가진 방어형 공룡",
		level = 10,
		maxHealth = 1500,
		maxTorpor = 1200,
		walkSpeed = 4,
		runSpeed = 8,
		damage = 40,
		attackRange = 10,
		detectRange = 12,
		attackDelay = 1.0,
		attackCooldown = 3.5,
		behavior = "NEUTRAL",
		modelName = "Ankylosaurus",
		xpReward = 50,
		-- 도감 시스템
		dnaRequired = 5,
		passiveEffect = { stat = "defense", value = 8 },         -- 방어력 +8
		petScale = 7.0,     -- 목표 크기 (스터드)
		petDamage = 18,
		petDefense = 40,
		petHealth = 250,
	},

	--========================================
	-- 육식 / AGGRESSIVE (선공형)
	--========================================
	{
		id = "RAPTOR",
		name = "랩터",
		description = "빠르고 민첩한 소형 육식공룡",
		level = 6,
		maxHealth = 1200,
		maxTorpor = 120,
		walkSpeed = 8,
		runSpeed = 16,
		damage = 35,
		attackRange = 8,
		detectRange = 50,
		attackDelay = 0.4,
		attackCooldown = 5.0,
		behavior = "AGGRESSIVE",
		modelName = "Raptor",
		xpReward = 25,
		attacks = {
			{ name = "깨물기", pattern = "CONE", angle = 80, range = 16, damage = 35, windupTime = 2.4, attackTime = 0.45, anim = "ATTACK" },
		},
		-- 도감 시스템
		dnaRequired = 5,
		passiveEffect = { stat = "attackMult", value = 0.05 },   -- 공격력 +5%
		petScale = 6.0,     -- 목표 크기 (스터드)
		petDamage = 12,
		petDefense = 15,
		petHealth = 60,
		mountable = true,
		mountSeatOffset = Vector3.new(0, 3.0, -4.2),
		mountSpeedMultiplier = 1.65,
		mountJumpPower = 58,
		palBagSlots = 6,
	},
	{
		id = "TREX",
		name = "티라노사우루스",
		description = "공포의 폭군. 섬에서 가장 강력한 포식자",
		level = 15,
		maxHealth = 4500,
		maxTorpor = 3500,
		walkSpeed = 7,
		runSpeed = 15,
		damage = 120,
		attackRange = 12,
		detectRange = 80,
		attackDelay = 1.0,
		attackCooldown = 3.5,
		behavior = "AGGRESSIVE",
		modelName = "TRex",
		xpReward = 120,
		-- 도감 시스템
		dnaRequired = 3,
		passiveEffect = { stat = "attackMult", value = 0.08 },   -- 공격력 +8%
		petScale = 8.0,     -- 목표 크기 (스터드)
		petDamage = 40,
		petDefense = 50,
		petHealth = 400,
	},
}

return CreatureData
