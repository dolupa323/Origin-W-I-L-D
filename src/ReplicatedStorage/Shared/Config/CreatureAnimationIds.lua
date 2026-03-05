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
	
	-- 랩터 (현재 유일하게 애니메이션이 준비된 공룡)
	RAPTOR = {
		IDLE = "Raptor_Idle",
		WALK = "Raptor_Walk",
		RUN = "Raptor_Run",
		ATTACK = "Raptor_Attack",
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
