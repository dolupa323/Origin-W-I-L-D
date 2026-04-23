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
	
	-- 시조새
	ARCHAEOPTERYX = {
		IDLE = "Archaeopteryx_Idle",
		WALK = "Archaeopteryx_Walk",
		RUN = "Archaeopteryx_Run",
		ATTACK = "Archaeopteryx_Attack",
		DEATH = "Archaeopteryx_Death",
	},
	
	-- 랩터
	RAPTOR = {
		IDLE = "Raptor_Idle",
		WALK = "Raptor_Walk",
		RUN = "Raptor_Run",
		MOUNT_IDLE = "Raptor_Idle",
		MOUNT_RUN = "Raptor_Run",
		MOUNT_TURN_LEFT = "Raptor_MountTurnLeft",
		MOUNT_TURN_RIGHT = "Raptor_MountTurnRight",
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
	-- 올로로티탄
	OLOROTITAN = {
		IDLE = "Olorotitan_Idle",
		WALK = "Olorotitan_Walk",
		RUN = "Olorotitan_Run", 
		ATTACK = "Olorotitan_Attack",
		DEATH = "Olorotitan_Death",
		EAT = "Olorotitan_Idle",
		IDLE_VARIANTS = { "Olorotitan_Idle", "Olorotitan_Walk" },
	},
	-- 트로오돈
	TROODON = {
		IDLE = "Troodon_Idle",
		WALK = "Troodon_Walk",
		RUN = "Troodon_Run",
		ATTACK = "Troodon_Attack",
		DEATH = "Troodon_Death",
	},

	-- 파라사우롤로푸스
	PARASAUR = {
		IDLE = "Parasaur_Idle",
		WALK = "Parasaur_Walk",
		RUN = "Parasaur_Run",
		ATTACK = "Parasaur_Attack",
		DEATH = "Parasaur_Death",
	},

	-- 스테고사우루스
	STEGOSAURUS = {
		IDLE = "Stegosaurus_Idle",
		WALK = "Stegosaurus_Walk",
		RUN = "Stegosaurus_Run",
		ATTACK = "Stegosaurus_Attack",
		DEATH = "Stegosaurus_Death",
	},

	-- 켈렌켄
	KELENKEN = {
		IDLE = "Kelenken_Idle",
		WALK = "Kelenken_Walk",
		RUN = "Kelenken_Run",
		ATTACK = "Kelenken_Attack",
		DEATH = "Kelenken_Death",
		MOUNT_IDLE = "Kelenken_Idle",
		MOUNT_RUN = "Kelenken_Run",
	},

	-- 데이노키루스
	DEINOCHEIRUS = {
		IDLE = "Deinocheirus_Idle",
		WALK = "Deinocheirus_Walk",
		RUN = "Deinocheirus_Run",
		ATTACK = "Deinocheirus_Attack",
		DEATH = "Deinocheirus_Death",
		MOUNT_IDLE = "Deinocheirus_Idle",
		MOUNT_RUN = "Deinocheirus_Run",
	},

	-- 알로사우루스
	ALLOSAURUS = {
		IDLE = "Allosaurus_Idle",
		WALK = "Allosaurus_Walk",
		RUN = "Allosaurus_Run",
		ATTACK = "Allosaurus_Attack",
		DEATH = "Allosaurus_Death",
		MOUNT_IDLE = "Allosaurus_Idle",
		MOUNT_RUN = "Allosaurus_Run",
	},

	-- 기간토랍토르
	GIGANTORAPTOR = {
		IDLE = "Gigantoraptor_Idle",
		WALK = "Gigantoraptor_Walk",
		RUN = "Gigantoraptor_Run",
		ATTACK = "Gigantoraptor_Attack",
		DEATH = "Gigantoraptor_Death",
		MOUNT_IDLE = "Gigantoraptor_Idle",
		MOUNT_RUN = "Gigantoraptor_Run",
	},

	-- 티타노사우루스
	TITANOSAURUS = {
		IDLE = "Titanosaurus_Idle",
		WALK = "Titanosaurus_Walk",
		RUN = "Titanosaurus_Run",
		ATTACK = "Titanosaurus_Attack",
		DEATH = "Titanosaurus_Death",
	},
}

return CreatureAnimationIds
