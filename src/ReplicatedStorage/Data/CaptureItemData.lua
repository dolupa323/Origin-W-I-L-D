-- CaptureItemData.lua
-- Phase 5-1: 포획 도구 데이터 정의
-- Bola 시스템으로 개편

local CaptureItemData = {
	VINE_BOLA = {
		id = "VINE_BOLA",
		name = "넝쿨 볼라",
		description = "소형 크리처에게 던져 묶고 길들이는 기초 투척 도구.",
		captureMultiplier = 1.0,   -- 포획률 배율
		maxRange = 30,             -- 투척 사거리 (스터드)
		rarity = "COMMON",
	},
	BONE_BOLA = {
		id = "BONE_BOLA",
		name = "뼈 볼라",
		description = "포획 확률을 높인 강화된 투척 도구.",
		captureMultiplier = 1.5,   -- 1.5배 포획률
		maxRange = 35,
		rarity = "UNCOMMON",
	},
	BRONZE_BOLA = {
		id = "BRONZE_BOLA",
		name = "청동 볼라",
		description = "중형 공룡을 제압하는 강력한 투척 도구.",
		captureMultiplier = 2.0,   -- 2.0배 포획률
		maxRange = 40,
		rarity = "RARE",
	},
	IRON_BOLA = {
		id = "IRON_BOLA",
		name = "철제 볼라",
		description = "대형 포식자 공룡을 포획하기 위한 최강의 도구.",
		captureMultiplier = 3.5,   -- 3.5배 포획률
		maxRange = 50,
		rarity = "EPIC",
	},
}

return CaptureItemData
