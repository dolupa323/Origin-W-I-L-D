-- CreatureData.lua
-- Phase 3-1: 크리처 데이터 정의

local CreatureData = {
	{
		id = "RAPTOR",
		name = "랩터",
		description = "빠르고 민첩한 소형 육식공룡",
		maxHealth = 100,
		walkSpeed = 16,
		runSpeed = 24,
		damage = 10,
		attackRange = 5,
		detectRange = 30,
		behavior = "AGGRESSIVE", -- 선공
		modelName = "Raptor",
	},
	{
		id = "TRICERATOPS",
		name = "트리케라톱스",
		description = "단단한 뿔을 가진 초식공룡",
		maxHealth = 300,
		walkSpeed = 12,
		runSpeed = 20,
		damage = 25,
		attackRange = 8,
		detectRange = 20,
		behavior = "NEUTRAL", -- 중립 (공격받으면 반격)
		modelName = "Triceratops",
	},
    {
		id = "DODO",
		name = "도도새",
		description = "약하고 멍청하지만 맛있는 새",
		maxHealth = 20,
		walkSpeed = 8,
		runSpeed = 12,
		damage = 0,
		attackRange = 0,
		detectRange = 15,
		behavior = "PASSIVE", -- 도망
		modelName = "Dodo",
	},
}

return CreatureData
