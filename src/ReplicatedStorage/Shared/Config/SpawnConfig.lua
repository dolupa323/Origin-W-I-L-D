-- SpawnConfig.lua
-- Zone 기반 섬별 스폰 밸런싱 및 다양성을 관리하는 설정 파일
-- 하나의 Place 내에서 좌표 영역(Zone)별로 섬을 구분한다.

local SpawnConfig = {}

--========================================
-- Zone 정의 (center + radius)
-- ★ center, radius, spawnPoint는 실제 맵 레이아웃에 맞춰 수정하세요.
--========================================
local HUB_ZONE = "GRASSLAND" -- 모든 포탈의 출발/귀환 중심지

local ZONES = {
	GRASSLAND = {
		center = Vector3.new(-128, 0, -278),      -- 초원 섬 중심 좌표 (Studio SpawnLocation 기준)
		radius = 2500,                             -- 영역 반경 (studs)
		spawnPoint = Vector3.new(-128, 20, -278),  -- 초원 섬 기본 스폰 지점
		creatureSpawnRadius = 300,                 -- 크리처 스폰용 실제 육지 반경
	},
	TROPICAL = {
		center = Vector3.new(-184, 10, 2788),            -- 열대 섬 중심 좌표 (귀환 포탈 기준)
		radius = 2500,                                  -- 영역 반경 (studs)
		spawnPoint = Vector3.new(-184, 45, 2788),       -- 열대 섬 기본 스폰 지점 (귀환 포탈 근처)
		creatureSpawnRadius = 180,                      -- 열대섬은 육지 폭이 좁아서 스폰 반경을 별도로 줄인다
	},
	DESERT = {
		center = Vector3.new(2694, 10, 56),           -- 사막 섬 중심 좌표
		radius = 2500,
		spawnPoint = Vector3.new(2694, 45, 56),
		creatureSpawnRadius = 300,
	},
	SNOWY = {
		center = Vector3.new(-6000, 10, -6000),          -- 설원 섬 중심 좌표
		radius = 2500,
		spawnPoint = Vector3.new(-6000, 45, -6000),
		creatureSpawnRadius = 300,
	},
}

SpawnConfig.HUB_ZONE = HUB_ZONE

-- 신규 유저가 처음 게임에 접속했을 때 스폰될 기본 절대 좌표
SpawnConfig.DEFAULT_START_SPAWN = ZONES.GRASSLAND.spawnPoint

--========================================
-- Zone별 생태계 설정
--========================================
local ZONE_CONFIGS = {
	GRASSLAND = {
		Creatures = {
			{ id = "ARCHAEOPTERYX", weight = 100 },
			{ id = "TROODON", weight = 85 },
			{ id = "OLOROTITAN", weight = 10 },
		},
		Harvests = {
			{ id = "TREE_THIN", weight = 50 },
			{ id = "ROCK_SOFT", weight = 40 },
			{ id = "BUSH_BERRY", weight = 45 },
			{ id = "GROUND_FIBER", weight = 90 },
			{ id = "GROUND_BRANCH", weight = 120 },
		},
	},
	TROPICAL = {
		Creatures = {
			{ id = "PARASAUR", weight = 70 },
			{ id = "STEGOSAURUS", weight = 50 },
			{ id = "KELENKEN", weight = 50 },
			{ id = "DEINOCHEIRUS", weight = 30 },
		},
		Harvests = {
			{ id = "BUSH_BERRY", weight = 70 },
			{ id = "GROUND_FIBER", weight = 100 },
			{ id = "GROUND_BRANCH", weight = 100 },
			{ id = "ROCK_SOFT", weight = 50 },
			{ id = "FALM_TREE", weight = 55 },
			{ id = "OBSIDIAN_NODE", weight = 25 },
			{ id = "REED_BUSH", weight = 50 },
		},
	},
	DESERT = {
		Creatures = {
			{ id = "UTAH_RAPTOR", weight = 50 },
			{ id = "TRICERATOPS", weight = 35 },
			{ id = "TITANOSAURUS", weight = 10 },
			{ id = "ALLOSAURUS", weight = 5 },
		},
		Harvests = {
			{ id = "ROCK_SOFT", weight = 50 },
		},
	},
	SNOWY = {
		Creatures = {
			{ id = "RAPTOR", weight = 40 },
			{ id = "STEGOSAURUS", weight = 60 },
		},
		Harvests = {
			{ id = "ROCK_SOFT", weight = 50 },
		},
	},
}

--========================================
-- 헬퍼 함수
--========================================

-- 가중치 기반 랜덤 선택
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

--========================================
-- Zone 판정
--========================================

--- XZ 평면 거리 기반으로 위치가 속한 Zone 이름을 반환
--- @param position Vector3 월드 좌표
--- @return string? Zone 이름 ("GRASSLAND" | "TROPICAL" | "DESERT" | "SNOWY" | nil)
function SpawnConfig.GetZoneAtPosition(position: Vector3): string?
	if not position then return nil end
	local bestZone = nil
	local bestDist = math.huge
	for zoneName, zone in pairs(ZONES) do
		local dx = position.X - zone.center.X
		local dz = position.Z - zone.center.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist <= zone.radius and dist < bestDist then
			bestDist = dist
			bestZone = zoneName
		end
	end
	return bestZone
end

--- 모든 Zone 이름 목록 반환
function SpawnConfig.GetAllZoneNames(): {string}
	local names = {}
	for zoneName in pairs(ZONES) do
		table.insert(names, zoneName)
	end
	return names
end

--- Zone 정보 조회 (center, radius, spawnPoint)
function SpawnConfig.GetZoneInfo(zoneName: string): any?
	return ZONES[zoneName]
end

--- Zone의 생태계 설정 조회
function SpawnConfig.GetZoneConfig(zoneName: string): any?
	return ZONE_CONFIGS[zoneName]
end

--========================================
-- 하위 호환 (IsContentPlace / GetCurrentConfig)
-- → 단일 Place이므로 항상 true / 기본 Zone 반환
--========================================

--- 현재 Place가 콘텐츠 스폰이 등록된 섬인지 확인.
--- 단일 Place 구조에서는 항상 true.
function SpawnConfig.IsContentPlace(): boolean
	return true
end

--- GetCurrentConfig는 더 이상 PlaceId를 보지 않는다.
--- 레거시 호출을 위해 기본 Zone(GRASSLAND) 설정을 반환.
function SpawnConfig.GetCurrentConfig()
	return ZONE_CONFIGS.GRASSLAND
end

--========================================
-- Zone별 랜덤 선택 함수
--========================================

--- Zone에 맞는 랜덤 크리처 ID 반환
function SpawnConfig.GetRandomCreatureForZone(zoneName: string): string?
	local config = ZONE_CONFIGS[zoneName]
	if not config or not config.Creatures then return nil end
	return getRandomFromWeight(config.Creatures)
end

--- Zone에 맞는 랜덤 자원 노드 ID 반환
function SpawnConfig.GetRandomHarvestForZone(zoneName: string): string?
	local config = ZONE_CONFIGS[zoneName]
	if not config or not config.Harvests then return nil end
	return getRandomFromWeight(config.Harvests)
end

--- Zone에 맞는 랜덤 바닥 자원(GROUND_*) ID 반환
function SpawnConfig.GetRandomGroundHarvestForZone(zoneName: string): string?
	local config = ZONE_CONFIGS[zoneName]
	if not config or not config.Harvests then return nil end
	local groundList = {}
	for _, item in ipairs(config.Harvests) do
		if item.id:find("GROUND") then
			table.insert(groundList, item)
		end
	end
	if #groundList == 0 then return nil end
	return getRandomFromWeight(groundList)
end

--========================================
-- 레거시 호환 함수 (위치 없이 호출 시 GRASSLAND 기본값)
--========================================

function SpawnConfig.GetRandomCreature()
	return SpawnConfig.GetRandomCreatureForZone("GRASSLAND")
end

function SpawnConfig.GetRandomHarvest()
	return SpawnConfig.GetRandomHarvestForZone("GRASSLAND")
end

function SpawnConfig.GetRandomGroundHarvest()
	return SpawnConfig.GetRandomGroundHarvestForZone("GRASSLAND")
end

return SpawnConfig
