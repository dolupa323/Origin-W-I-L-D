-- TechUnlockData.lua
-- 상세 기술 해금 데이터 정의 (Lv. 1 ~ 50)
-- 4단계 시대를 유지하되, 세부 기술별 레벨 제한 및 포인트 소모량 적용

local TechUnlockData = {
	--========================================
	-- 🪨 1단계: 원시 시대 (Prehistoric Age, Lv. 1 ~ 9)
	--========================================
	{
		id = "TECH_Lv1_BASICS",
		name = "기초 생존",
		requireLevel = 1,
		techPointCost = 0,
		unlocks = { 
			recipes = { 
				"CRAFT_STONE_PICKAXE", "CRAFT_STONE_AXE", 
				"CRAFT_STONE_SPEAR", "CRAFT_WOODEN_CLUB", 
				"CRAFT_VINE_BOLA", "CRAFT_TORCH" 
			}, 
			facilities = {} 
		},
		category = "SURVIVAL",
	},
	{
		id = "TECH_Lv3_FIRE",
		name = "불의 발견",
		requireLevel = 3,
		techPointCost = 2,
		prerequisites = { "TECH_Lv1_BASICS" },
		unlocks = { recipes = {}, facilities = { "CAMPFIRE" } },
		category = "SURVIVAL",
	},
	{
		id = "TECH_Lv8_REPAIR",
		name = "수리 기술",
		requireLevel = 8,
		techPointCost = 2,
		prerequisites = { "TECH_Lv3_FIRE" },
		unlocks = { recipes = {}, facilities = { "REPAIR_BENCH" } },
		category = "SURVIVAL",
	},

	--========================================
	-- ⛺ 2단계: 목조 정착 시대 (Wood Age, Lv. 10 ~ 19)
	--========================================
	{
		id = "TECH_Lv10_BASE_TOTEM",
		name = "거점 토템 및 공방",
		requireLevel = 10,
		techPointCost = 2,
		prerequisites = { "TECH_Lv8_REPAIR" },
		unlocks = { recipes = {}, facilities = { "CAMP_TOTEM", "STORAGE_BOX", "PRIMITIVE_WORKBENCH" } },
		category = "SETTLEMENT",
	},
	{
		id = "TECH_Lv11_WOOD_BUILD",
		name = "목조 건축",
		requireLevel = 11,
		techPointCost = 3,
		prerequisites = { "TECH_Lv10_BASE_TOTEM" },
		unlocks = { recipes = {}, facilities = { "WOODEN_FOUNDATION", "WOODEN_WALL", "WOODEN_ROOF", "WOODEN_DOOR" } },
		category = "STRUCTURES",
	},
	{
		id = "TECH_Lv13_BOW",
		name = "나무 활",
		requireLevel = 13,
		techPointCost = 3,
		prerequisites = { "TECH_Lv1_BASICS" },
		unlocks = { recipes = { "CRAFT_WOODEN_BOW", "CRAFT_STONE_ARROW" }, facilities = {} },
		category = "WEAPONS",
	},
	{
		id = "TECH_Lv14_BOLA2",
		name = "뼈 볼라",
		requireLevel = 14,
		techPointCost = 3,
		unlocks = { recipes = { "CRAFT_BONE_BOLA" }, facilities = {} },
		category = "PAL",
	},
	{
		id = "TECH_Lv15_HOE",
		name = "돌 괭이",
		requireLevel = 15,
		techPointCost = 3,
		unlocks = { recipes = { "CRAFT_STONE_HOE" }, facilities = {} },
		category = "TOOLS",
	},
	{
		id = "TECH_Lv17_FARMING",
		name = "농경 기술",
		requireLevel = 17,
		techPointCost = 3,
		unlocks = { recipes = {}, facilities = { "BERRY_PLANTATION", "BEAST_FEEDING_TROUGH" } },
		category = "SURVIVAL",
	},

	--========================================
	-- 🥉 3단계: 청동기 시대 (Bronze Age, Lv. 20 ~ 34)
	--========================================
	{
		id = "TECH_Lv20_FURNACE1",
		name = "돌 용광로",
		requireLevel = 20,
		techPointCost = 3,
		unlocks = { recipes = {}, facilities = { "STONE_FURNACE" } },
		category = "FACILITIES",
	},
	{
		id = "TECH_Lv21_BRONZE_SMELT",
		name = "청동 제련",
		requireLevel = 21,
		techPointCost = 3,
		prerequisites = { "TECH_Lv20_FURNACE1" },
		unlocks = { recipes = { "SMELT_BRONZE_INGOT" }, facilities = {} },
		category = "METALLURGY",
	},
	{
		id = "TECH_Lv22_WORKBENCH2",
		name = "청동기 작업대",
		requireLevel = 22,
		techPointCost = 3,
		unlocks = { recipes = {}, facilities = { "BRONZE_WORKBENCH" } },
		category = "FACILITIES",
	},
	{
		id = "TECH_Lv23_BRONZE_TOOLS",
		name = "청동 도구",
		requireLevel = 23,
		techPointCost = 3,
		unlocks = { recipes = { "CRAFT_BRONZE_PICKAXE", "CRAFT_BRONZE_AXE" }, facilities = {} },
		category = "TOOLS",
	},
	{
		id = "TECH_Lv25_BOLA3",
		name = "청동 포획구",
		requireLevel = 25,
		techPointCost = 3,
		unlocks = { recipes = { "CRAFT_BRONZE_BOLA" }, facilities = {} },
		category = "PAL",
	},
	{
		id = "TECH_Lv27_BRONZE_WEAPONS",
		name = "청동 무기",
		requireLevel = 27,
		techPointCost = 3,
		unlocks = { recipes = { "CRAFT_BRONZE_SPEAR", "CRAFT_BRONZE_BOW", "CRAFT_BRONZE_ARROW" }, facilities = {} },
		category = "WEAPONS",
	},
	{
		id = "TECH_Lv30_STRAW_NEST",
		name = "짚 둥지",
		requireLevel = 30,
		techPointCost = 3,
		unlocks = { recipes = {}, facilities = { "STRAW_NEST" } },
		category = "PAL",
	},
	{
		id = "TECH_Lv32_LARGE_BOX",
		name = "대형 보관함",
		requireLevel = 32,
		techPointCost = 3,
		unlocks = { recipes = {}, facilities = { "LARGE_STORAGE_BOX" } },
		category = "SETTLEMENT",
	},

	--========================================
	-- ⚔️ 4단계: 철기 시대 (Iron Age, Lv. 35 ~ 50)
	--========================================
	{
		id = "TECH_Lv35_FURNACE2",
		name = "철 용광로",
		requireLevel = 35,
		techPointCost = 5,
		unlocks = { recipes = { "SMELT_IRON_INGOT" }, facilities = { "IRON_FURNACE" } },
		category = "FACILITIES",
	},
	{
		id = "TECH_Lv36_STONE_BUILD",
		name = "석조 건축",
		requireLevel = 36,
		techPointCost = 5,
		unlocks = { recipes = {}, facilities = { "STONE_FOUNDATION", "STONE_WALL", "STONE_ROOF" } },
		category = "STRUCTURES",
	},
	{
		id = "TECH_Lv38_WORKBENCH3",
		name = "철기 작업대",
		requireLevel = 38,
		techPointCost = 5,
		unlocks = { recipes = {}, facilities = { "IRON_WORKBENCH" } },
		category = "FACILITIES",
	},
	{
		id = "TECH_Lv40_IRON_TOOLS",
		name = "철제 도구",
		requireLevel = 40,
		techPointCost = 5,
		unlocks = { recipes = { "CRAFT_IRON_PICKAXE", "CRAFT_IRON_AXE" }, facilities = {} },
		category = "TOOLS",
	},
	{
		id = "TECH_Lv42_CROSSBOW",
		name = "석궁 세트",
		requireLevel = 42,
		techPointCost = 5,
		unlocks = { recipes = { "CRAFT_CROSSBOW", "CRAFT_IRON_BOLT" }, facilities = {} },
		category = "WEAPONS",
	},
	{
		id = "TECH_Lv45_BOLA4",
		name = "철제 포획구",
		requireLevel = 45,
		techPointCost = 5,
		unlocks = { recipes = { "CRAFT_IRON_BOLA" }, facilities = {} },
		category = "PAL",
	},
	{
		id = "TECH_Lv47_BEAST_BED",
		name = "대형 야수 침대",
		requireLevel = 47,
		techPointCost = 5,
		unlocks = { recipes = {}, facilities = { "LARGE_BEAST_BED" } },
		category = "PAL",
	},
	{
		id = "TECH_Lv50_REINFORCED_GATE",
		name = "강화 성문",
		requireLevel = 50,
		techPointCost = 5,
		unlocks = { recipes = {}, facilities = { "REINFORCED_GATE" } },
		category = "STRUCTURES",
	},
}

return TechUnlockData
