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
	[PORTAL_MAP.GRASSLAND] = {
		Creatures = {
			-- 각 종류가 체감상 균등하게 나오도록 가중치 조정
			-- (콤피는 무리 스폰이므로 가중치를 높여야 발견 빈도가 유사해짐)
			{ id = "DODO", weight = 90 },
			{ id = "BABY_TRICERATOPS", weight = 50 },
			{ id = "COMPY", weight = 80 }
		},
		Harvests = {
			-- 초원섬 전용 자원 노드 구성
			{ id = "TREE_THIN", weight = 50 },     -- 가는 나무
			{ id = "ROCK_SOFT", weight = 40 },     -- 무른 바위
			{ id = "BUSH_BERRY", weight = 45 },    -- 열매 덤불
			{ id = "GROUND_FIBER", weight = 55 },  -- 섬유 (바닥)
			{ id = "GROUND_BRANCH", weight = 80 }, -- 나뭇가지 (바닥)
			{ id = "GROUND_STONE", weight = 90 }   -- 잔돌 (바닥)
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
			{ id = "GROUND_FIBER", weight = 60 },
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

-- [추가] 잔돌, 나뭇가지 등 소형 바닥 자원 전용 랜덤 선택 (자동 스폰용)
function SpawnConfig.GetRandomGroundHarvest()
	local config = SpawnConfig.GetCurrentConfig()
	local groundList = {}
	for _, item in ipairs(config.Harvests) do
		-- GROUND_STONE, GROUND_BRANCH 등 ID에 GROUND가 포함된 것만 추출
		if item.id:find("GROUND") then
			table.insert(groundList, item)
		end
	end
	
	if #groundList == 0 then return nil end
	return getRandomFromWeight(groundList)
end

return SpawnConfig
