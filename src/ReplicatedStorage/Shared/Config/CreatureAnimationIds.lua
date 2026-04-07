-- CreatureAnimationIds.lua
-- 크리처 전용 애니메이션 논리적 이름 정의
-- 실제 ID는 Assets/Animations/Creatures/... 경로에 위치해야 함

local CreatureAnimationIds = {
	-- 기본(Fallback) 애니메이션
	-- 현재 에셋이 준비되지 않은 경우 에러 방지를 위해 비워둠
	DEFAULT = {
		-- IDLE = "Creature_Idle",
		-- WALK = "Creature_Walk",
		-- RUN = "Creature_Run",
	},

	-- [공룡별 특수 설정]
	-- CreatureData.lua의 id와 일치해야 함
	
	-- 랩터
	RAPTOR = {
		IDLE = "Raptor_Idle",
		WALK = "Raptor_Walk",
		RUN = "Raptor_Run",
		ATTACK = "Raptor_Attack",
		DEATH = "Raptor_Death",
	},

	-- 트리케라톱스 (성체)
	TRICERATOPS = {
		IDLE = "Triceratops_Idle",
		WALK = "Triceratops_Walk",
		RUN = "Triceratops_Walk", 
		ATTACK = "Triceratops_Attack",
		STOMP = "Triceratops_Stomp",
		DEATH = "Triceratops_Death",
		EAT = "Triceratops_Eat",
		IDLE_VARIANTS = { "Triceratops_Idle", "Triceratops_Walk", "Triceratops_Eat" },
	},
	-- 아기 트리케라톱스 (성체와 동일한 애니메이션 사용 확인됨)
	BABY_TRICERATOPS = {
		IDLE = "Triceratops_Idle",
		WALK = "Triceratops_Walk",
		RUN = "Triceratops_Walk", 
		ATTACK = "Triceratops_Attack",
		DEATH = "Triceratops_Death",
		EAT = "Triceratops_Eat",
		IDLE_VARIANTS = { "Triceratops_Idle", "Triceratops_Walk", "Triceratops_Eat" },
	},
	COMPY = {
		IDLE = "Raptor_Idle",
		WALK = "Raptor_Walk",
		RUN = "Raptor_Run",
		ATTACK = "Raptor_Attack",
		DEATH = "COMPY_Death",
	},

	-- 파라사우롤로푸스
	PARASAUR = {
		IDLE = "Parasaur_Idle",
		WALK = "Parasaur_Walk",
		RUN = "Parasaur_Walk",
		ATTACK = "Parasaur_Attack",
		SPIT = "Parasaur_Spit",
		DEATH = "Parasaur_Death",
		EAT = "Parasaur_Eat",
		IDLE_VARIANTS = { "Parasaur_Idle", "Parasaur_Walk", "Parasaur_Eat" },
	},

	-- 스테고사우루스
	STEGOSAURUS = {
		IDLE = "Stegosaurus_Idle",
		WALK = "Stegosaurus_Walk",
		RUN = "Stegosaurus_Walk",
		ATTACK = "Stegosaurus_Attack",
		DEATH = "Stegosaurus_Death",
		EAT = "Stegosaurus_Eat",
		IDLE_VARIANTS = { "Stegosaurus_Idle", "Stegosaurus_Walk", "Stegosaurus_Eat" },
	},
	
	-- 티라노 등 다른 공룡은 준비되면 아래 주석을 풀고 등록하세요.
	--[[
	TREX = {
		IDLE = "TREX_Idle",
		WALK = "TREX_Walk",
		RUN = "TREX_Run",
		ATTACK = "TREX_Attack",
	},
	]]
}

return CreatureAnimationIds
