-- PalData.lua
-- Phase 5-1: 포획 가능 크리처의 팰(Pal) 데이터 정의
-- CreatureData와 1:1 매핑 (creatureId 기준)

local PalData = {
	RAPTOR = {
		creatureId = "RAPTOR",
		palName = "랩터",
		captureRate = 0.25,          -- 기본 포획률 (HP 100%일 때)
		workTypes = {"TRANSPORT", "COMBAT"},
		workPower = 2,               -- 작업 효율 (배율)
		combatPower = 50,            -- 전투력 지표
		baseStats = {
			hp = 100,
			attack = 15,
			defense = 5,
			speed = 24,
		},
		passiveSkill = "SPEED_BOOST", -- 소환 시 플레이어 이동속도 +10%
		isBoss = false,               -- 보스 여부 (포획 불가)
	},
	TRICERATOPS = {
		creatureId = "TRICERATOPS",
		palName = "트리케라톱스",
		captureRate = 0.15,          -- 큰 몸집 → 포획 어려움
		workTypes = {"MINING", "TRANSPORT"},
		workPower = 4,               -- 높은 작업 효율
		combatPower = 80,
		baseStats = {
			hp = 300,
			attack = 25,
			defense = 15,
			speed = 20,
		},
		passiveSkill = "DEFENSE_BOOST", -- 소환 시 플레이어 방어력 +15%
		isBoss = false,
	},
	DODO = {
		creatureId = "DODO",
		palName = "도도새",
		captureRate = 0.60,          -- 약하고 쉬움
		workTypes = {"FARMING"},
		workPower = 1,
		combatPower = 5,
		baseStats = {
			hp = 20,
			attack = 2,
			defense = 1,
			speed = 12,
		},
		passiveSkill = "GATHER_BOOST", -- 소환 시 채집 수량 +20%
		isBoss = false,
	},
}

return PalData
