-- SpawnConfig.lua
-- 섬별 스폰 밸런싱 및 다양성을 관리하는 설정 파일
local PORTAL_MAP = {
	GRASSLAND = 000000000, -- 나중에 초원 섬의 PlaceId 입력
	TROPICAL = 107341024431610, -- 트로피컬 섬
}

local SpawnConfig = {}

-- 신규 유저가 처음 게임에 접속했을 때 스폰될 기본 절대 좌표 (Island/Place 에 따라 분리 가능)
SpawnConfig.DEFAULT_START_SPAWN = Vector3.new(0, 50, 0) -- 임시로 x:0, y:50, z:0으로 설정. 추후 디자인하시는 스폰포인트 좌표로 수정하시면 됩니다!

local ISLAND_CONFIGS = {
	-- [기본] 초원 섬 생태계 설정
	[PORTAL_MAP.GRASSLAND] = {
		Creatures = {
			-- 초기 초식공룡 위주 설계
			{ id = "TRICERATOPS", weight = 100 },
			{ id = "RAPTOR", weight = 30 }
		},
		Harvests = {
			-- 전형적인 숲 생태계 자원 노드
			{ id = "TREE_OAK", weight = 50 },
			{ id = "TREE_PINE", weight = 30 },
			{ id = "BUSH_BERRY", weight = 40 },
			{ id = "FIBER_GRASS", weight = 50 },
			{ id = "GROUND_BRANCH", weight = 80 },
			{ id = "ROCK_NORMAL", weight = 40 },
			{ id = "GROUND_STONE", weight = 90 }
		}
	},
	
	-- [확장] 열대 섬 생태계 설정
	[PORTAL_MAP.TROPICAL] = {
		Creatures = {
			-- 조금 더 거친 생태계 테마
			{ id = "RAPTOR", weight = 80 },
			{ id = "TREX", weight = 20 },
			{ id = "TRICERATOPS", weight = 40 }
		},
		Harvests = {
			-- 열대 느낌에 맞춘 자원 비중 변화 (예: 야자수, 희귀식물 중심)
			{ id = "TREE_OAK", weight = 80 }, -- 차후 열대 나무 모델 생기면 TREE_PALM 등으로 교체 가능
			{ id = "BUSH_BERRY", weight = 70 },
			{ id = "FIBER_GRASS", weight = 60 },
			{ id = "GROUND_BRANCH", weight = 60 },
			{ id = "ROCK_NORMAL", weight = 50 },
			{ id = "GROUND_STONE", weight = 60 }
		}
	}
}

-- 가중치 기반 랜덤 선택 헬퍼
local function getRandomFromWeight(list)
	local totalWeight = 0
	for _, item in ipairs(list) do
		totalWeight = totalWeight + item.weight
	end
	
	local randomVal = math.random() * totalWeight
	local currentWeight = 0
	
	for _, item in ipairs(list) do
		currentWeight = currentWeight + item.weight
		if randomVal <= currentWeight then
			return item.id
		end
	end
	return list[1].id
end


function SpawnConfig.GetCurrentConfig()
	local currentPlaceId = game.PlaceId
	local config = ISLAND_CONFIGS[currentPlaceId] or ISLAND_CONFIGS[PORTAL_MAP.GRASSLAND]
	return config
end

function SpawnConfig.GetRandomCreature()
	local config = SpawnConfig.GetCurrentConfig()
	return getRandomFromWeight(config.Creatures)
end

function SpawnConfig.GetRandomHarvest()
	local config = SpawnConfig.GetCurrentConfig()
	return getRandomFromWeight(config.Harvests)
end

return SpawnConfig
