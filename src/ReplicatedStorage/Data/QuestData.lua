-- QuestData.lua
-- 퀘스트 데이터 정의

local QuestData = {}

--========================================
-- 튜토리얼 퀘스트
--========================================
QuestData.QUEST_TUTORIAL_HARVEST = {
	id = "QUEST_TUTORIAL_HARVEST",
	name = "첫 수확",
	description = "나무를 3번 수확하세요.",
	category = "TUTORIAL",
	prerequisites = {},
	requiredLevel = 1,
	objectives = {
		{
			type = "HARVEST",
			targetId = "TREE",
			count = 3,
		}
	},
	rewards = {
		xp = 50,
		techPoints = 0,
		items = {
			{ itemId = "WOOD", count = 10 },
		}
	},
	autoGrant = true,
	autoGrantLevel = 1,
	repeatable = false,
}

QuestData.QUEST_TUTORIAL_CRAFT = {
	id = "QUEST_TUTORIAL_CRAFT",
	name = "첫 제작",
	description = "나무 도끼를 제작하세요.",
	category = "TUTORIAL",
	prerequisites = { "QUEST_TUTORIAL_HARVEST" },
	requiredLevel = 1,
	objectives = {
		{
			type = "CRAFT",
			targetId = "WOODEN_AXE",
			count = 1,
		}
	},
	rewards = {
		xp = 100,
		techPoints = 0,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 1,
	repeatable = false,
}

QuestData.QUEST_TUTORIAL_BUILD = {
	id = "QUEST_TUTORIAL_BUILD",
	name = "첫 건설",
	description = "모닥불을 설치하세요.",
	category = "TUTORIAL",
	prerequisites = { "QUEST_TUTORIAL_CRAFT" },
	requiredLevel = 1,
	objectives = {
		{
			type = "BUILD",
			targetId = "CAMPFIRE",
			count = 1,
		}
	},
	rewards = {
		xp = 100,
		techPoints = 0,
		items = {
			{ itemId = "STONE", count = 20 },
		}
	},
	autoGrant = true,
	autoGrantLevel = 1,
	repeatable = false,
}

QuestData.QUEST_TUTORIAL_HUNT = {
	id = "QUEST_TUTORIAL_HUNT",
	name = "첫 사냥",
	description = "도도를 1마리 처치하세요.",
	category = "TUTORIAL",
	prerequisites = { "QUEST_TUTORIAL_BUILD" },
	requiredLevel = 1,
	objectives = {
		{
			type = "KILL",
			targetId = "DODO",
			count = 1,
		}
	},
	rewards = {
		xp = 150,
		techPoints = 0,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 1,
	repeatable = false,
}

QuestData.QUEST_TUTORIAL_CAPTURE = {
	id = "QUEST_TUTORIAL_CAPTURE",
	name = "첫 포획",
	description = "팰을 1마리 포획하세요.",
	category = "TUTORIAL",
	prerequisites = { "QUEST_TUTORIAL_HUNT" },
	requiredLevel = 2,
	objectives = {
		{
			type = "CAPTURE",
			targetId = nil,  -- 아무 팰이나
			count = 1,
		}
	},
	rewards = {
		xp = 200,
		techPoints = 1,
		items = {
			{ itemId = "PAL_SPHERE", count = 5 },
		}
	},
	autoGrant = true,
	autoGrantLevel = 2,
	repeatable = false,
}

--========================================
-- 메인 퀘스트
--========================================
QuestData.QUEST_MAIN_BASE = {
	id = "QUEST_MAIN_BASE",
	name = "거점 구축",
	description = "창고를 1개 건설하세요.",
	category = "MAIN",
	prerequisites = { "QUEST_TUTORIAL_BUILD" },
	requiredLevel = 3,
	objectives = {
		{
			type = "BUILD",
			targetId = "STORAGE_BOX",
			count = 1,
		}
	},
	rewards = {
		xp = 300,
		techPoints = 1,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 3,
	repeatable = false,
}

QuestData.QUEST_MAIN_PARTY = {
	id = "QUEST_MAIN_PARTY",
	name = "동료 모으기",
	description = "팰을 3마리 보유하세요.",
	category = "MAIN",
	prerequisites = { "QUEST_TUTORIAL_CAPTURE" },
	requiredLevel = 5,
	objectives = {
		{
			type = "COLLECT",
			targetId = "PAL_COUNT",
			count = 3,
		}
	},
	rewards = {
		xp = 500,
		techPoints = 2,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 5,
	repeatable = false,
}

QuestData.QUEST_MAIN_TECH = {
	id = "QUEST_MAIN_TECH",
	name = "기술 연구",
	description = "기술을 5개 해금하세요.",
	category = "MAIN",
	prerequisites = { "QUEST_MAIN_BASE" },
	requiredLevel = 5,
	objectives = {
		{
			type = "UNLOCK_TECH",
			targetId = nil,
			count = 5,
		}
	},
	rewards = {
		xp = 500,
		techPoints = 0,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 5,
	repeatable = false,
}

QuestData.QUEST_MAIN_LEVEL10 = {
	id = "QUEST_MAIN_LEVEL10",
	name = "성장의 첫걸음",
	description = "레벨 10에 도달하세요.",
	category = "MAIN",
	prerequisites = {},
	requiredLevel = 1,
	objectives = {
		{
			type = "REACH_LEVEL",
			targetId = nil,
			count = 10,
		}
	},
	rewards = {
		xp = 1000,
		techPoints = 3,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 1,
	repeatable = false,
}

QuestData.QUEST_MAIN_AUTOMATION = {
	id = "QUEST_MAIN_AUTOMATION",
	name = "자동화 시작",
	description = "채집 기지를 건설하세요.",
	category = "MAIN",
	prerequisites = { "QUEST_MAIN_BASE", "QUEST_MAIN_PARTY" },
	requiredLevel = 8,
	objectives = {
		{
			type = "BUILD",
			targetId = "GATHERING_POST",
			count = 1,
		}
	},
	rewards = {
		xp = 800,
		techPoints = 2,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 8,
	repeatable = false,
}

--========================================
-- 사이드 퀘스트
--========================================
QuestData.QUEST_SIDE_GATHERER = {
	id = "QUEST_SIDE_GATHERER",
	name = "수집가",
	description = "자원을 50회 수확하세요.",
	category = "SIDE",
	prerequisites = { "QUEST_TUTORIAL_HARVEST" },
	requiredLevel = 2,
	objectives = {
		{
			type = "HARVEST",
			targetId = nil,  -- 아무 자원이나
			count = 50,
		}
	},
	rewards = {
		xp = 300,
		techPoints = 0,
		items = {
			{ itemId = "WOOD", count = 50 },
			{ itemId = "STONE", count = 50 },
		}
	},
	autoGrant = true,
	autoGrantLevel = 2,
	repeatable = false,
}

QuestData.QUEST_SIDE_HUNTER = {
	id = "QUEST_SIDE_HUNTER",
	name = "사냥꾼",
	description = "크리처를 10마리 처치하세요.",
	category = "SIDE",
	prerequisites = { "QUEST_TUTORIAL_HUNT" },
	requiredLevel = 3,
	objectives = {
		{
			type = "KILL",
			targetId = nil,
			count = 10,
		}
	},
	rewards = {
		xp = 500,
		techPoints = 1,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 3,
	repeatable = false,
}

QuestData.QUEST_SIDE_CRAFTER = {
	id = "QUEST_SIDE_CRAFTER",
	name = "장인",
	description = "아이템을 20개 제작하세요.",
	category = "SIDE",
	prerequisites = { "QUEST_TUTORIAL_CRAFT" },
	requiredLevel = 4,
	objectives = {
		{
			type = "CRAFT",
			targetId = nil,
			count = 20,
		}
	},
	rewards = {
		xp = 400,
		techPoints = 0,
		items = {}
	},
	autoGrant = true,
	autoGrantLevel = 4,
	repeatable = false,
}

--========================================
-- 일일 퀘스트
--========================================
QuestData.QUEST_DAILY_HARVEST = {
	id = "QUEST_DAILY_HARVEST",
	name = "일일 수확",
	description = "자원을 10회 수확하세요.",
	category = "DAILY",
	prerequisites = { "QUEST_TUTORIAL_HARVEST" },
	requiredLevel = 1,
	objectives = {
		{
			type = "HARVEST",
			targetId = nil,
			count = 10,
		}
	},
	rewards = {
		xp = 100,
		techPoints = 0,
		items = {}
	},
	autoGrant = false,
	repeatable = true,
	repeatCooldown = 86400,  -- 24시간
}

QuestData.QUEST_DAILY_HUNT = {
	id = "QUEST_DAILY_HUNT",
	name = "일일 사냥",
	description = "크리처를 3마리 처치하세요.",
	category = "DAILY",
	prerequisites = { "QUEST_TUTORIAL_HUNT" },
	requiredLevel = 2,
	objectives = {
		{
			type = "KILL",
			targetId = nil,
			count = 3,
		}
	},
	rewards = {
		xp = 150,
		techPoints = 0,
		items = {}
	},
	autoGrant = false,
	repeatable = true,
	repeatCooldown = 86400,
}

return QuestData
