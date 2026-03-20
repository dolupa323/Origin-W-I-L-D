-- ArmorSetData.lua
-- 방어구 세트 효과 정의

local ArmorSetData = {
	-- FIBER 세트: FIBER_SHIRT, FIBER_PANTS 아이템 미구현으로 비활성화
	-- FIBER = {
	-- 	name = "초보 생존자 (섬유)",
	-- 	items = {"FIBER_SHIRT", "FIBER_PANTS"},
	-- 	bonusText = "방어력 +5, 최대 체력 +20",
	-- 	bonuses = { defense = 5, maxHealth = 20 }
	-- },
	LEATHER = {
		name = "중급 사냥꾼 (가죽)",
		items = {"FEATHER_HELMET", "LEATHER_ARMOR"},
		bonusText = "방어력 +15, 최대 스태미너 +30",
		bonuses = {
			defense = 15,
			maxStamina = 30,
		}
	},
	BRONZE = {
		name = "청동기 전사",
		items = {"BRONZE_HELMET", "BRONZE_ARMOR"},
		bonusText = "방어력 +30, 공격력 +15%",
		bonuses = {
			defense = 30,
			attackMult = 0.15,
		}
	},
	IRON = {
		name = "철기 정복자",
		items = {"IRON_HELMET", "IRON_ARMOR"},
		bonusText = "방어력 +60, 공격력 +25%",
		bonuses = {
			defense = 60,
			attackMult = 0.25,
		}
	}
}

return ArmorSetData
