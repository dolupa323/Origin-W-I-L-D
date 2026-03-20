-- HarvestService.lua
-- 자원 수확 시스템 (Phase 7-1)
-- 플레이어가 자원 노드(나무, 돌, 풀)에서 아이템 획득
-- 유연한 모델 로딩: Toolbox에서 가져온 어떤 구조의 모델도 지원
-- 자동 스폰: 플레이어 주변에 자동으로 자원 노드 생성

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local HarvestService = {}

--========================================
-- 스폰 상수
--========================================
local NODE_SPAWN_INTERVAL = Balance.NODE_SPAWN_INTERVAL or 10
local NODE_CAP = Balance.RESOURCE_NODE_CAP or 400
local MIN_SPAWN_DIST = 20
local MAX_SPAWN_DIST = 60
local DESPAWN_DIST = Balance.NODE_DESPAWN_DIST or 300
local SEA_LEVEL = Balance.SEA_LEVEL or 10
local STARTER_NODE_TARGET_PER_TYPE = 2
local STARTER_NODE_CHECK_RADIUS = 45
local STARTER_NODE_MIN_DIST = 8
local STARTER_NODE_MAX_DIST = 24
local STARTER_NODE_TYPES = { "GROUND_BRANCH", "GROUND_STONE", "GROUND_FIBER" }

-- 섬별 스폰 밸런싱 데이터
local SpawnConfig = require(ReplicatedStorage.Shared.Config.SpawnConfig)

-- 풀밑 (Grass) 지형 Material
local GRASS_MATERIALS = {
	Enum.Material.Grass,
	Enum.Material.LeafyGrass,
}

-- 바위/돌 (Rock) 지형 Material
local ROCK_MATERIALS = {
	Enum.Material.Rock,
	Enum.Material.Slate,
	Enum.Material.Basalt,
	Enum.Material.Limestone,
	Enum.Material.Granite,
}

-- 모래 (Sand) 지형 Material
local SAND_MATERIALS = {
	Enum.Material.Sand,
	Enum.Material.Sandstone,
}

-- 흔 (Ground) 지형 Material
local GROUND_MATERIALS = {
	Enum.Material.Ground,
	Enum.Material.Mud,
}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController = nil
local DataService = nil
local InventoryService = nil
local PlayerStatService = nil
local DurabilityService = nil
local WorldDropService = nil
local TechService = nil -- Phase 6: 기술 해금 검증 (Relinquish 어뷰징 방지)

--========================================
-- Internal State
--========================================
-- 활성 노드 상태 { [nodeUID] = { nodeId, remainingHits, depletedAt, position } }
local activeNodes = {}
local nodeCount = 0

-- 고갈된 노드 상태 (리스폰 대기) { [nodeUID] = { nodeId, position, respawnAt, originalPartData } }
local depletedNodes = {}

-- 플레이어 쿨다운 { [userId] = lastHitTime }
local playerCooldowns = {}

local questCallback = nil
-- 스폰된 노드 수 추적 (자동스폰된 노드만)
local spawnedNodeCount = 0
local spawnedNodesByType = {} -- { [nodeId] = count }
local starterNodesSeededUsers = {} -- [userId] = true
--========================================
-- Internal Functions
--========================================

--- 고유 노드 ID 생성
local function generateNodeUID(): string
	nodeCount = nodeCount + 1
	return string.format("node_%d_%d", os.time(), nodeCount)
end

--========================================
-- 유연한 모델 로딩 시스템 (Toolbox 모델 지원)
--========================================

--- 자원 모델 찾기 (유연한 이름 매칭)
local function findResourceModel(modelsFolder, modelName, nodeId)
	if not modelsFolder then return nil end
	
	-- 1. 정확한 이름 매칭 (하위 폴더 포함 탐색)
	local template = modelsFolder:FindFirstChild(modelName, true)
	if template then return template end
	
	-- 2. nodeId로 매칭
	template = modelsFolder:FindFirstChild(nodeId, true)
	if template then return template end
	
	-- 3. 대소문자 무시 매칭
	local lowerModelName = modelName:lower()
	local lowerNodeId = nodeId:lower()
	
	for _, child in ipairs(modelsFolder:GetChildren()) do
		local childNameLower = child.Name:lower()
		
		-- modelName 또는 nodeId와 대소문자 무시 매칭
		if childNameLower == lowerModelName or childNameLower == lowerNodeId then
			return child
		end
		
		-- 부분 문자열 매칭 (ex: "OakTreeModel"에서 "oak" 찾기)
		-- nodeId에서 마지막 부분 추출 (TREE_OAK -> oak)
		local lastPart = lowerNodeId:match("_([^_]+)$") or lowerNodeId
		if childNameLower:find(lastPart) then
			return child
		end
		
		-- nodeType 매칭 (ex: "tree", "rock", "ore")
		local nodeType = lowerNodeId:match("^([^_]+)")
		if nodeType and childNameLower:find(nodeType) then
			return child
		end
	end
	
	return nil
end

--- Toolbox 모델 정리 (스크립트, 사운드, GUI 제거)
local function cleanModelForHarvest(model: Model)
	local removed = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") 
			or descendant:IsA("LocalScript") 
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Sound")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("ScreenGui") then
			descendant:Destroy()
			removed = removed + 1
		end
	end
	if removed > 0 then
		print(string.format("[HarvestService] Cleaned %d scripts/sounds from model", removed))
	end
end

--- 모델을 자원 노드로 설정 (어떤 구조든 지원)
local function setupModelForNode(model: Model, position: Vector3, nodeData: any, isAutoSpawn: boolean): Model
	-- Toolbox 모델 정리
	cleanModelForHarvest(model)

	-- 잔돌/나뭇가지는 식별성을 위해 시각 크기를 아주 소폭 상향
	if nodeData and (nodeData.id == "GROUND_BRANCH" or nodeData.id == "GROUND_STONE") then
		local scaleMul = 1.15
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				part.Size = part.Size * scaleMul
			end
		end
	end
	
	-- PrimaryPart 찾기/설정
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		-- 후보 1: HumanoidRootPart
		primaryPart = model:FindFirstChild("HumanoidRootPart")
		if not primaryPart then
			-- 후보 2: 아무 BasePart
			primaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		end
		if primaryPart then
			model.PrimaryPart = primaryPart
		end
	end
	
	-- 위치 설정 (자동 스폰일 때만 Y축 하단 정렬 및 위치 지정)
	if primaryPart and isAutoSpawn then
		-- 모델 하단이 지면에 닿도록 조정 (모든 파트 중 가장 낮은 Y값 추적)
		local minY = math.huge
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				local pMinY = p.Position.Y - (p.Size.Y / 2)
				if pMinY < minY then minY = pMinY end
			end
		end
		
		if minY == math.huge then
			local modelCF, modelSize = model:GetBoundingBox()
			minY = modelCF.Position.Y - (modelSize.Y / 2)
		end
		
		local currentPivot = model:GetPivot()
		local pivotOffset = currentPivot.Position.Y - minY
		
		-- [수정] 누락된 randomYRot 선언 복구
		local randomYRot = math.rad(math.random(0, 359))
		
		-- 지면(position)에서 pivotOffset만큼 위로 띄워야 하단이 지면에 맞음
		local targetCF = CFrame.new(position) * CFrame.Angles(0, randomYRot, 0) * CFrame.new(0, pivotOffset, 0)
		model:PivotTo(targetCF)
		
		-- [수정] 0.5 유격 제거 (물리 낙하 효과 제거 및 지면 밀착)
		if primaryPart.Anchored == false then
			model:PivotTo(targetCF)
		end
	elseif not primaryPart and isAutoSpawn then
		-- PrimaryPart가 없으면 모든 파트 이동
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Position = position
				break
			end
		end
	end
	
	-- 모든 파트를 Anchored로 (AI 없음, 자원 노드는 고정)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = true
		end
	end
	
	-- 7. 하단 상호작용 판정 강화 (Hitbox 추가)
	-- 특히 오크나무처럼 하단이 비어있는 경우를 위해 지면 부근에 투명 박스 생성
	-- [수정] 부쉬 베리(BUSH_BERRY)의 경우 지면에 묻혀도 상호작용 가능하도록 머리 부분에 히트박스 배치
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(6, 5, 6) -- 넓고 낮은 박스
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = true
	
	local _, modelSize = model:GetBoundingBox()
	local yOffset = -modelSize.Y/2 + 2.5
	if nodeData and nodeData.id == "BUSH_BERRY" then
		-- 부쉬 베리는 상단(머리) 부분에 히트박스 배치
		yOffset = modelSize.Y/2 - 2.5
	end
	
	hitbox.CFrame = model:GetPivot() * CFrame.new(0, yOffset, 0)
	hitbox.Parent = model
	
	-- Humanoid 제거 (자원 노드는 필요 없음)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	
	-- CollectionService 태그 추가 (Raycast 필터링용)
	CollectionService:AddTag(model, "ResourceNode")
	
	return model
end

--- 자원 모델 스폰 (Assets 폴더에서)
function HarvestService.spawnNodeModel(nodeId: string, position: Vector3, nodeUID: string?): Model?
	local nodeData = DataService.getResourceNode(nodeId)
	if not nodeData then
		warn(string.format("[HarvestService] Unknown nodeId: %s", nodeId))
		return nil
	end
	
	-- ResourceNodes 폴더 확보
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then
		nodeFolder = Instance.new("Folder")
		nodeFolder.Name = "ResourceNodes"
		nodeFolder.Parent = workspace
	end
	
	-- Assets 내 여러 폴더에서 템플릿 탐색 (사용자 폴더링 대응)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	
	local searchFolders = {
		assets and assets:FindFirstChild("ResourceNodeModels"),
		assets and assets:FindFirstChild("ItemModels"),
		assets and assets:FindFirstChild("Models"),
		assets,
		nodeFolder -- 워크스페이스 내 ResourceNodes 폴더도 탐색 범위에 포함
	}
	
	local modelName = nodeData.modelName or nodeId
	local template = nil
	for _, folder in ipairs(searchFolders) do
		if folder then
			template = findResourceModel(folder, modelName, nodeId)
			if template then break end
		end
	end
	
	local model
	if template then
		-- 실제 모델 복제
		model = template:Clone()
		model.Name = nodeId
		model.Parent = nodeFolder -- Parent early to avoid joint warnings
		model = setupModelForNode(model, position, nodeData, true)
		print(string.format("[HarvestService] Loaded model '%s' for %s", template.Name, nodeId))
	else
		-- 폴백: 간단한 플레이스홀더 생성
		warn(string.format("[HarvestService] Model '%s' not found in ResourceNodeModels, using placeholder", modelName))
		
		model = Instance.new("Model")
		model.Name = nodeId
		model.Parent = nodeFolder -- Parent early
		
		local part = Instance.new("Part")
		part.Name = "MainPart"
		part.Anchored = true
		
		-- nodeType에 따라 모양/색상 결정
		local nodeType = nodeData.nodeType or "ROCK"
		if nodeType == "TREE" then
			-- 나무: 세로로 세운 Block (눕지 않도록!)
			part.Size = Vector3.new(3, 12, 3)
			part.BrickColor = BrickColor.new("Brown")
			part.Shape = Enum.PartType.Block
			-- 나뭇잎 파트 추가
			local leaves = Instance.new("Part")
			leaves.Name = "Leaves"
			leaves.Size = Vector3.new(6, 6, 6)
			leaves.Shape = Enum.PartType.Ball
			leaves.BrickColor = BrickColor.new("Bright green")
			leaves.Anchored = true
			leaves.Position = position + Vector3.new(0, 12, 0)
			leaves.Parent = model
		elseif nodeType == "ROCK" or nodeType == "ORE" then
			part.Size = Vector3.new(4, 3, 4)
			part.BrickColor = BrickColor.Gray()
			part.Shape = Enum.PartType.Ball
		elseif nodeType == "BUSH" or nodeType == "FIBER" then
			part.Size = Vector3.new(2, 1.5, 2)
			part.BrickColor = BrickColor.new("Bright green")
		else
			part.Size = Vector3.new(3, 3, 3)
			part.BrickColor = BrickColor.Random()
		end
		
		part.Position = position + Vector3.new(0, part.Size.Y / 2, 0)
		part.Parent = model
		model.PrimaryPart = part
		
		CollectionService:AddTag(model, "ResourceNode")
	end
	
	-- 속성 설정
	model:SetAttribute("NodeId", nodeId)
	model:SetAttribute("NodeUID", nodeUID or "") -- 필수: 상호작용 UID
	model:SetAttribute("NodeType", nodeData.nodeType or "UNKNOWN")
	model:SetAttribute("OptimalTool", nodeData.optimalTool or "")
	model:SetAttribute("Depleted", false)
	
	return model
end

--- 도구 타입 가져오기 (인벤토리 슬롯 우선, 캐릭터 폴백)
local function getToolType(player: Player, toolSlot: number?): string?
	local userId = player.UserId
	local toolItem = nil
	
	-- 1. 제공된 슬롯에서 아이템 데이터 조회
	if toolSlot and InventoryService then
		toolItem = InventoryService.getSlot(userId, toolSlot)
	end
	
	-- 2. 슬롯 정보가 없으면 캐릭터에 들고있는 도구 확인
	if not toolItem then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if tool then
			-- 고유 속성이 있으면 그것을 반환
			local attr = tool:GetAttribute("ToolType")
			if attr and attr ~= "" then return attr end
			
			-- 아이템 데이터에서 타입 확인
			if DataService then
				local itm = DataService.getItem(tool.Name)
				if itm and itm.type == "TOOL" then
					return itm.optimalTool or itm.id:upper()
				end
			end
			return nil -- 툴이 아니면 맨손 판정
		end
	end
	
	-- 3. 아이템 데이터의 타입 확인
	if toolItem and DataService then
		local itemData = DataService.getItem(toolItem.itemId)
		if itemData then
			if itemData.type == "TOOL" or itemData.id == "BOLA" then
				return itemData.optimalTool or itemData.id:upper()
			else
				return itemData.type -- "WEAPON", "FOOD" 등 반환
			end
		end
	end
	
	return nil -- 완전 맨손
end

--- 도구와 노드 타입 호환성 확인
local function isCompatible(toolType: string?, optimalType: string?): boolean
	if not optimalType or optimalType == "" then return true end
	if not toolType then return false end
	
	local t = toolType:upper()
	local o = optimalType:upper()
	-- "PICKAXE"가 "AXE"를 포함하므로 정확한 비교 사용
	return t == o
end

local function validateTool(player: Player, nodeData: any, toolSlot: number?): (boolean, string?)
	if not nodeData then return false, Enums.ErrorCode.NOT_FOUND end
	
	-- 인벤토리에서 직접 데이터 조회 (서버 신뢰)
	local toolItem = nil
	if toolSlot and InventoryService then
		toolItem = InventoryService.getSlot(player.UserId, toolSlot)
	end
	
	-- 내구도 체크: 장착된 아이템의 내구도가 0 이하면 사용 불가
	if toolItem and toolItem.durability and toolItem.durability <= 0 then
		-- [UX] 내구도 0인 도구는 맨손 취급하거나 사용 불가 메시지
		return false, Enums.ErrorCode.INVALID_STATE -- "도구가 파손되었습니다"
	end

	local equippedToolType = getToolType(player, toolSlot)
	
	-- [설계 변경] 도구 필수 여부 확인 (강제 적용)
	if nodeData.requiresTool then
		-- 도구가 아예 없으면 (맨손) 불가
		if not equippedToolType then
			return false, Enums.ErrorCode.WRONG_TOOL
		end
		
		-- 최적 도구(optimalTool)가 지정된 경우, 호환되는 도구여야만 함
		if nodeData.optimalTool and nodeData.optimalTool ~= "" then
			if not isCompatible(equippedToolType, nodeData.optimalTool) then
				return false, Enums.ErrorCode.WRONG_TOOL
			end
		end
	end
	
	return true, nil
end

--- 채집 효율 계산
local function calculateEfficiency(player: Player, nodeOptimalType: string?, toolSlot: number?): number
	local toolType = getToolType(player, toolSlot)
	local baseEff = 1.0
	local toolDamage = 5 -- 맨손 기본
	
	if toolSlot and InventoryService and DataService then
		local slotData = InventoryService.getSlot(player.UserId, toolSlot)
		if slotData then
			local itemData = DataService.getItem(slotData.itemId)
			if itemData then
				toolDamage = itemData.damage or 5
			end
		end
	end
	
	-- 1. 도구 타입 일치 여부에 따른 보너스
	if not nodeOptimalType or nodeOptimalType == "" then
		-- 상호작용 노드 (requiresTool = false)
		if toolType == "SICKLE" then -- 낫은 풀 채집 시 보너스
			baseEff = 1.5
		else
			baseEff = 1.0
		end
	elseif isCompatible(toolType, nodeOptimalType) then
		-- 타입 일치: 기본 효율 높음 + 도구 위력(데미지)에 따른 보정
		baseEff = Balance.HARVEST_EFFICIENCY_OPTIMAL or 1.2
		-- 티어 가산: 데미지 10당 +0.1 효율 (청동 = 25뎀 = +0.25)
		baseEff = baseEff + (toolDamage / 100)
	elseif toolType == "WEAPON" then
		-- [기획] 도구가 필요한 노드를 무기로 때리면 효율 0 (체력 안 깎임)
		baseEff = 0
	elseif toolType then
		-- 잘못된 도구
		baseEff = Balance.HARVEST_EFFICIENCY_WRONG_TOOL or 0.7
	else
		-- 맨손
		baseEff = Balance.HARVEST_EFFICIENCY_BAREHAND or 0.5
	end
	
	-- 2. Work Speed 보너스 (10점당 +5%)
	local workSpeedBonus = 0
	if PlayerStatService then
		local stats = PlayerStatService.getStats(player.UserId)
		local workSpeedStat = (stats and stats.statInvested and stats.statInvested[Enums.StatId.WORK_SPEED]) or 0
		workSpeedBonus = math.floor(workSpeedStat / 10) * 0.05
	end
	
	return baseEff + workSpeedBonus
end

--- 드롭 아이템 계산 (효율 적용)
local function calculateDrops(nodeData: any, efficiency: number?): { {itemId: string, count: number} }
	local drops = {}
	local eff = efficiency or 1.0
	
	for _, resource in ipairs(nodeData.resources) do
		-- 가중치 기반 확률 체크 (효율은 확률에 영향을 주지 않음, 수량에만 영향)
		if math.random() <= resource.weight then
			-- 효율에 따라 수량 조절
			local baseCount = math.random(resource.min, resource.max)
			local count = math.floor(baseCount * eff + 0.5)  -- 반올림
			
			-- 가중치가 1.0인 핵심 아이템은 효율이 낮아도 무조건 최소 1개 보장
			if resource.weight >= 1.0 then
				count = math.max(count, 1)
			end
			
			if count > 0 then
				table.insert(drops, {
					itemId = resource.itemId,
					count = count,
				})
			end
		end
	end
	
	return drops
end

--========================================
-- 자동 스폰 시스템 (지형 기반)
--========================================

--- Material이 특정 목록에 포함되는지 확인
local function isMaterialInList(material, materialList)
	for _, mat in ipairs(materialList) do
		if material == mat then
			return true
		end
	end
	return false
end

local function findSpawnPositionNearPlayer(playerRootPart: Part, minDist: number, maxDist: number): Vector3?
	if not playerRootPart then return nil end

	for _ = 1, 16 do
		local angle = math.rad(math.random(1, 360))
		local distance = math.random(minDist, maxDist)

		local offset = Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
		local origin = playerRootPart.Position + offset + Vector3.new(0, 150, 0)

		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		local map = workspace:FindFirstChild("Map")
		if map then table.insert(filterList, map) end

		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include

		local result = workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
		if result then
			local isWater = result.Material == Enum.Material.Water
				or result.Material == Enum.Material.CrackedLava
			local belowSeaLevel = result.Position.Y < SEA_LEVEL

			if not isWater and not belowSeaLevel then
				local candidatePos = result.Position + Vector3.new(0, 0.5, 0)
				local tooClose = false
				local nodeFolder = workspace:FindFirstChild("ResourceNodes")
				if nodeFolder then
					for _, descendant in ipairs(nodeFolder:GetDescendants()) do
						if descendant:IsA("Model") then
							local p = descendant.PrimaryPart or descendant:FindFirstChildWhichIsA("BasePart")
							if p and (p.Position - candidatePos).Magnitude < 8 then
								tooClose = true
								break
							end
						end
					end
				end

				if not tooClose then
					return candidatePos
				end
			end
		end
	end

	return nil
end

function HarvestService._ensureStarterGroundNodes(player: Player)
	if not player then return end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then
		nodeFolder = Instance.new("Folder")
		nodeFolder.Name = "ResourceNodes"
		nodeFolder.Parent = workspace
	end

	local nearbyCounts = {}
	for _, nodeId in ipairs(STARTER_NODE_TYPES) do
		nearbyCounts[nodeId] = 0
	end

	for _, descendant in ipairs(nodeFolder:GetDescendants()) do
		if descendant:IsA("Model") then
			local nodeId = descendant:GetAttribute("NodeId")
			if nodeId and nearbyCounts[nodeId] ~= nil then
				local p = descendant.PrimaryPart or descendant:FindFirstChildWhichIsA("BasePart")
				if p then
					local p1 = Vector2.new(p.Position.X, p.Position.Z)
					local p2 = Vector2.new(hrp.Position.X, hrp.Position.Z)
					if (p1 - p2).Magnitude <= STARTER_NODE_CHECK_RADIUS then
						nearbyCounts[nodeId] += 1
					end
				end
			end
		end
	end

	for _, nodeId in ipairs(STARTER_NODE_TYPES) do
		local deficit = STARTER_NODE_TARGET_PER_TYPE - (nearbyCounts[nodeId] or 0)
		for _ = 1, math.max(0, deficit) do
			local spawnPos = findSpawnPositionNearPlayer(hrp, STARTER_NODE_MIN_DIST, STARTER_NODE_MAX_DIST)
			if spawnPos then
				HarvestService._spawnAutoNode(nodeId, spawnPos)
			end
		end
	end
end

--- 지형에 따른 자원 노드 ID 선택 (균형 잡힌 스폰)
local function selectNodeForTerrain(material: Enum.Material): string?
	local pool
	if isMaterialInList(material, GRASS_MATERIALS) then
		pool = GRASS_TERRAIN_NODES
	elseif isMaterialInList(material, ROCK_MATERIALS) then
		pool = ROCK_TERRAIN_NODES
	elseif isMaterialInList(material, SAND_MATERIALS) then
		pool = SAND_TERRAIN_NODES
	elseif isMaterialInList(material, GROUND_MATERIALS) then
		pool = GROUND_TERRAIN_NODES
	else
		pool = GROUND_TERRAIN_NODES
	end
	
	if not pool then return nil end
	
	-- 섞기 (Shuffle)
	local shuffled = {}
	for _, id in ipairs(pool) do table.insert(shuffled, id) end
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	
	-- 개별 타입별 캡 (전체 캡의 25%, 최소 5)
	local typeCap = math.max(5, math.floor(NODE_CAP * 0.25))
	
	for _, id in ipairs(shuffled) do
		if (spawnedNodesByType[id] or 0) < typeCap then
			return id
		end
	end
	
	-- 모두 다 찼다면 가장 적은 것 중 하나 (옵션) 혹은 nil
	return nil
end

--- 유효한 스폰 위치 및 지형 찾기 (플레이어 주변)
function HarvestService._findSpawnPosition(playerRootPart: Part): (Vector3?, Enum.Material?)
	if not playerRootPart then return nil, nil end
	
	for i = 1, 10 do -- 10회 시도
		local angle = math.rad(math.random(1, 360))
		local distance = math.random(MIN_SPAWN_DIST, MAX_SPAWN_DIST)
		
		local offset = Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
		local origin = playerRootPart.Position + offset + Vector3.new(0, 200, 0)
		
		-- Raycast (지형과 맵만 확실히 감지)
		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		local map = workspace:FindFirstChild("Map")
		if map then table.insert(filterList, map) end
		
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		-- 더 높은 곳에서 더 깊게 쏨 (맵 밖이나 겹친 파트 무시)
		local result = workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
		if result then
			-- 물/바다 Material 체크 (육지만 허용)
			local isWater = result.Material == Enum.Material.Water
				or result.Material == Enum.Material.CrackedLava
			
			-- 해수면 아래 체크
			local belowSeaLevel = result.Position.Y < SEA_LEVEL
			
			-- 물이 아니고 해수면 위인 경우만 허용
			if not isWater and not belowSeaLevel then
				-- 기존 노드와 너무 가까운지 체크 (최소 8 studs 간격)
				local tooClose = false
				local nodeFolder = workspace:FindFirstChild("ResourceNodes")
				if nodeFolder then
					-- [수정] 폴더 구조가 있어도 모델만 골라내어 거리 체크
					for _, descendant in ipairs(nodeFolder:GetDescendants()) do
						if descendant:IsA("Model") then
							local existingPart = descendant.PrimaryPart or descendant:FindFirstChildWhichIsA("BasePart")
							if existingPart then
								if (existingPart.Position - result.Position).Magnitude < 8 then
									tooClose = true
									break
								end
							end
						end
					end
				end
				
				if not tooClose then
					return result.Position + Vector3.new(0, 0.5, 0), result.Material
				end
			end
		end
	end
	return nil, nil
end

--- 자동 스폰된 노드 생성
function HarvestService._spawnAutoNode(nodeId: string, position: Vector3): string?
	if spawnedNodeCount >= NODE_CAP then
		return nil
	end
	
	-- 모델 생성 (NodeUID 미리 생성하여 전달)
	local nodeUID = HarvestService.registerNode(nodeId, position, true)
	local model = HarvestService.spawnNodeModel(nodeId, position, nodeUID)
	
	if not model then
		return nil
	end

	if activeNodes[nodeUID] then
		activeNodes[nodeUID].nodeModel = model
	end
	
	model:SetAttribute("AutoSpawned", true) -- 자동 스폰 표시 (디스폰 대상)
	
	return nodeUID
end

--- 스폰 루프 (플레이어 주변에 자원 스폰)
function HarvestService._spawnLoop()
	-- 활성 노드 수 체크 (자동 스폰 + 수동 배치 모두 포함)
	local totalActiveNodes = 0
	for _ in pairs(activeNodes) do
		totalActiveNodes = totalActiveNodes + 1
	end
	
	if totalActiveNodes >= NODE_CAP then return end
	
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			-- 스폰 확률: 50%
			if math.random() <= 0.5 then
				local pos, material = HarvestService._findSpawnPosition(char.HumanoidRootPart)
				if pos and material then
					-- [수정] 잔돌, 나뭇가지 등 소형 바닥 자원 위주로 플레이어 주변 자동 스폰
					local nodeId = SpawnConfig.GetRandomGroundHarvest()
					if nodeId then
						HarvestService._spawnAutoNode(nodeId, pos)
						
						totalActiveNodes = totalActiveNodes + 1
						if totalActiveNodes >= NODE_CAP then break end
					end
				end
			end
		end
	end
end

--- 디스폰 체크 (플레이어와 너무 멀면 제거)
function HarvestService._despawnCheck()
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then return end
	
	local nodes = nodeFolder:GetChildren()
	if #nodes == 0 then return end
	
	local players = Players:GetPlayers()
	if #players == 0 then
		-- 플레이어 없으면 모든 자동 노드 즉시 제거
		for _, nodeModel in ipairs(nodes) do
			if nodeModel:GetAttribute("AutoSpawned") then
				local nodeUID = nodeModel:GetAttribute("NodeUID")
				if nodeUID and activeNodes[nodeUID] then
					local nodeId = activeNodes[nodeUID].nodeId
					activeNodes[nodeUID] = nil
					spawnedNodesByType[nodeId] = math.max(0, (spawnedNodesByType[nodeId] or 0) - 1)
					spawnedNodeCount = math.max(0, spawnedNodeCount - 1)
				end
				nodeModel:Destroy()
			end
		end
		return
	end

	-- 1. 보존할 노드 식별 (플레이어 주변 DESPAWN_DIST 이내)
	local keepNodes = {}
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { nodeFolder }
	params.FilterType = Enum.RaycastFilterType.Include
	
	for _, player in ipairs(players) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- 공간 분할 색인(GetPartBoundsInRadius) 활용하여 근처 노드만 추출
			local nearbyParts = workspace:GetPartBoundsInRadius(hrp.Position, DESPAWN_DIST, params)
			for _, part in ipairs(nearbyParts) do
				local model = part:FindFirstAncestorOfClass("Model")
				if model and model.Parent == nodeFolder then
					keepNodes[model] = true
				end
			end
		end
	end
	
	-- 2. 보존 목록에 없는 자동 스폰 노드 제거
	for _, nodeModel in ipairs(nodes) do
		if nodeModel:GetAttribute("AutoSpawned") and not keepNodes[nodeModel] then
			local nodeUID = nodeModel:GetAttribute("NodeUID")
			if nodeUID and activeNodes[nodeUID] then
				local nodeId = activeNodes[nodeUID].nodeId
				activeNodes[nodeUID] = nil
				
				-- 카운트 감소
				spawnedNodesByType[nodeId] = math.max(0, (spawnedNodesByType[nodeId] or 0) - 1)
				spawnedNodeCount = math.max(0, spawnedNodeCount - 1)
			end
			
			-- 모델 제거
			nodeModel:Destroy()
		end
	end
end

--========================================
-- Public API: Node Management
--========================================

--- 자원 노드 등록 (맵 로드 시 호출)
function HarvestService.registerNode(nodeId: string, position: Vector3, isAutoSpawned: boolean?): string
	local nodeUID = generateNodeUID()
	local nodeData = DataService.getResourceNode(nodeId)
	
	if not nodeData then
		warn(string.format("[HarvestService] Unknown node: %s", nodeId))
		return nodeUID
	end
	
	activeNodes[nodeUID] = {
		nodeId = nodeId,
		remainingHits = nodeData.maxHealth, -- maxHits 대신 maxHealth 사용 (호환성을 위해 변수명은 유지 가능하나 내부 값은 Health)
		depletedAt = nil,
		position = position,
		isAutoSpawned = isAutoSpawned,
		nodeModel = nil, -- 노드 모델 참조 (숨김 복원용)
	}
	
	-- 타입별 카운트 증가 (자동 스폰 노드만 추적 — 수동 배치 노드는 Cap 잠식 방지)
	if isAutoSpawned then
		spawnedNodesByType[nodeId] = (spawnedNodesByType[nodeId] or 0) + 1
		spawnedNodeCount = spawnedNodeCount + 1
	end
	
	-- 클라이언트에 노드 스폰 알림 (네트워크 최적화: 400스터드)
	if NetController then
		NetController.FireClientsInRange(position, 400, "Harvest.Node.Spawned", {
			nodeUID = nodeUID,
			nodeId = nodeId,
			position = position,
			maxHits = nodeData.maxHealth, -- 클라이언트 UI에서도 maxHealth 수치로 쓰게 함
		})
	end
	
	return nodeUID
end

--- 노드 상태 조회
function HarvestService.getNodeState(nodeUID: string): any?
	local state = activeNodes[nodeUID]
	if not state then return nil end
	
	return {
		nodeId = state.nodeId,
		remainingHits = state.remainingHits,
		isActive = state.depletedAt == nil,
		position = state.position,
	}
end

--- 모든 활성 노드 조회
function HarvestService.getAllNodes(): {any}
	local result = {}
	for nodeUID, state in pairs(activeNodes) do
		if state.depletedAt == nil then
			table.insert(result, {
				nodeUID = nodeUID,
				nodeId = state.nodeId,
				position = state.position,
				remainingHits = state.remainingHits,
			})
		end
	end
	return result
end

--========================================
-- Public API: Harvesting
--========================================

--- 자원 노드 타격 (플레이어 수동 채집)
function HarvestService.hit(player: Player, nodeUID: string, toolSlot: number?, hitCount: number?): (boolean, string?, {any}?)
	local userId = player.UserId
	
	-- 1. 쿨다운 체크
	local now = tick()
	local cooldown = Balance.HARVEST_COOLDOWN or 0.5
	if playerCooldowns[userId] and (now - playerCooldowns[userId]) < cooldown then
		return false, Enums.ErrorCode.COOLDOWN, nil
	end
	playerCooldowns[userId] = now
	
	-- 2. 노드 존재 확인
	local nodeState = activeNodes[nodeUID]
	if not nodeState then
		return false, Enums.ErrorCode.NODE_NOT_FOUND, nil
	end
	
	-- 3. 노드 데이터 조회
	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 4. 거리 검증 (Y축 무시 평면 거리 계산)
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p1 = Vector2.new(hrp.Position.X, hrp.Position.Z)
			local p2 = Vector2.new(nodeState.position.X, nodeState.position.Z)
			local distance = (p1 - p2).Magnitude
			
			local maxRange = Balance.HARVEST_RANGE or 25
			-- 서버 측 검증은 클라이언트보다 더 여유를 둡니다 (네트워크 레이턴시 고려)
			if distance > maxRange + 10 then
				warn(string.format("[HarvestService] Out of range (2D): %.1f > %.1f", distance, maxRange))
				return false, Enums.ErrorCode.OUT_OF_RANGE, nil
			end
		end
	end
	
	-- 5. 도구 검증
	local toolOk, toolError = validateTool(player, nodeData, toolSlot)
	if not toolOk then
		return false, toolError or Enums.ErrorCode.WRONG_TOOL, nil
	end

	-- [보안/기획] 기술 해금 체크 (Relinquish 어뷰징 방지)
	if toolSlot and TechService then
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData and not TechService.isRecipeUnlocked(userId, slotData.itemId) then
			return false, Enums.ErrorCode.RECIPE_LOCKED, nil
		end
	end
	
	-- 6. 효율 계산
	local efficiency = calculateEfficiency(player, nodeData.optimalTool, toolSlot)
	
	-- 7. 타격 처리 (Power 계산) - "데미지 공식: 현재 채집 스탯 + 도구의 데미지"
	local power = 5 -- 맨손 기본 데미지
	if toolSlot and InventoryService and DataService then
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData then
			local itemData = DataService.getItem(slotData.itemId)
			if itemData and itemData.damage then
				power = itemData.damage
			end
		end
	end
	
	-- 레벨업(스탯) 등에서 오는 채집스탯 추가 (예: WORK_SPEED 등 투자 스탯을 그대로 데미지에 더함)
	if PlayerStatService then
		local stats = PlayerStatService.getStats(player.UserId)
		local workSpeedStat = (stats and stats.statInvested and stats.statInvested[Enums.StatId.WORK_SPEED]) or 0
		power = power + workSpeedStat
	end
	
	-- 8. 실제 데미지 적용
	-- 효율 0(예: 무기로 도구필수 노드 타격)일 때는 실제 데미지를 0으로 고정.
	local finalDamage = (efficiency <= 0) and 0 or power
	local success, err, drops = HarvestService.damageNode(nodeUID, finalDamage, efficiency, userId)
	
	-- 9. (Player-specific) 도구 내구도 감소
	if success and toolSlot and DurabilityService and InventoryService then
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData and slotData.durability then
			DurabilityService.reduceDurability(player, toolSlot, 1)
		end
	end
	
	-- 10. (Player-specific) 배고픔 소모
	if success then
		local HSuccess, HungerService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
		if HSuccess and HungerService then
			HungerService.consumeHunger(userId, Balance.HUNGER_HARVEST_COST * power)
		end
	end
	
	return success, err, drops
end

--- 자원 노드에 데미지 적용 (플레이어/팰 공용)
function HarvestService.damageNode(nodeUID: string, damage: number, efficiency: number, sourceUserId: number?): (boolean, string?, {any}?)
	local nodeState = activeNodes[nodeUID]
	if not nodeState then return false, Enums.ErrorCode.NODE_NOT_FOUND, nil end
	
	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then return false, Enums.ErrorCode.NOT_FOUND, nil end
	
	local actualDamage = math.min(damage, nodeState.remainingHits)
	
	-- 데미지가 0인 경우 (무기로 도구 필수 노드 타격 등)
	if actualDamage <= 0 and damage <= 0 then
		-- 브로드캐스트만 하여 효과(이펙트/사운드)는 나게 함
		if NetController then
			NetController.FireClientsInRange(nodeState.position, 400, "Harvest.Node.Hit", {
				nodeUID = nodeUID,
				remainingHits = nodeState.remainingHits,
				maxHits = nodeData.maxHits
			})
		end
		return true, nil, {}
	end
	
	nodeState.remainingHits = nodeState.remainingHits - actualDamage
	
	-- 타격 브로드캐스트
	if NetController then
		NetController.FireClientsInRange(nodeState.position, 400, "Harvest.Node.Hit", {
			nodeUID = nodeUID,
			remainingHits = nodeState.remainingHits,
			maxHits = nodeData.maxHealth
		})
	end
	
	-- XP 보상 (있을 때만)
	if sourceUserId and PlayerStatService then
		local xpPerHit = nodeData.xpPerHit or Balance.XP_HARVEST_XP_PER_HIT or 2
		PlayerStatService.addXP(sourceUserId, xpPerHit * actualDamage, Enums.XPSource.HARVEST_RESOURCE)
	end
	
	local drops = {}
	if nodeState.remainingHits <= 0 then
		-- 고갈 시 드롭 계산
		drops = calculateDrops(nodeData, efficiency)
		
		-- 월드 드롭 생성
		for _, drop in ipairs(drops) do
			if WorldDropService then
				local angle = math.random() * math.pi * 2
				local radius = math.random() * 2 + 1
				local baseDropPos = nodeState.position + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
				
				-- [개선] 지면 인식 레이캐스트 (노드 자체를 제외하여 정확히 바닥 찾기)
				local rayParams = RaycastParams.new()
				local filterTargets = {}
				if nodeState.nodeModel then
					table.insert(filterTargets, nodeState.nodeModel)
				end
				rayParams.FilterDescendantsInstances = filterTargets
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				
				local rayResult = workspace:Raycast(baseDropPos, Vector3.new(0, -30, 0), rayParams)
				local finalDropPos = rayResult and rayResult.Position or (nodeState.position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
				
				WorldDropService.spawnDrop(finalDropPos, drop.itemId, drop.count)
			end
		end
		
		-- 모델 제거
		HarvestService._destroyNodeModel(nodeUID)
		
		-- 고갈 처리
		if nodeState.isAutoSpawned then
			local nodeId = nodeState.nodeId
			spawnedNodesByType[nodeId] = math.max(0, (spawnedNodesByType[nodeId] or 0) - 1)
			spawnedNodeCount = math.max(0, spawnedNodeCount - 1)
			activeNodes[nodeUID] = nil
		else
			depletedNodes[nodeUID] = {
				nodeId = nodeState.nodeId,
				position = nodeState.position,
				respawnAt = os.time() + (nodeData.respawnTime or 300),
				isAutoSpawned = nodeState.isAutoSpawned,
				nodeModel = nodeState.nodeModel,
			}
			activeNodes[nodeUID] = nil
			task.delay(nodeData.respawnTime or 300, function()
				HarvestService._respawnNode(nodeUID)
			end)
		end
		
		-- 퀘스트 콜백
		if sourceUserId and questCallback then
			questCallback(sourceUserId, nodeData.nodeType or nodeData.id)
		end
	end
	
	return true, nil, drops
end

--- 노드 모델 파괴 (내부) - 파괴 대신 숨김 처리
function HarvestService._destroyNodeModel(nodeUID: string)
	local nodeState = activeNodes[nodeUID] or depletedNodes[nodeUID]
	if not nodeState then return nil end
	
	local nodeModel = nodeState.nodeModel
	
	-- 미리 배치된 모델이 없다면 (혹은 AutoSpawned 등) 폴더 스캔
	if not nodeModel then
		local nodeFolder = workspace:FindFirstChild("ResourceNodes")
		if nodeFolder then
			-- [수정] 하위 폴더까지 뒤져서 해당 UID를 가진 모델 검색
			for _, m in ipairs(nodeFolder:GetDescendants()) do
				if m:IsA("Model") and m:GetAttribute("NodeUID") == nodeUID then
					nodeModel = m
					break
				end
			end
		end
	end
	
	if nodeModel then
		nodeState.nodeModel = nodeModel
		nodeModel:SetAttribute("Depleted", true)
		
		-- 삭제 대신 투명화/콜리전 비활성화 (리스폰시 복구 위해)
		for _, part in ipairs(nodeModel:GetDescendants()) do
			if part:IsA("BasePart") then
				if part.Name ~= "Hitbox" then
					part.Transparency = 1
					if part:IsA("Texture") or part:IsA("Decal") then
						part.Transparency = 1
					end
				end
				-- Hitbox 포함 콜리전은 전부 Off
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			elseif part:IsA("ParticleEmitter") or part:IsA("Trail") then
				part.Enabled = false
			end
		end
		
		return {}
	end
	return nil
end



--- 노드 리스폰 (내부)
function HarvestService._respawnNode(nodeUID: string)
	-- 고갈된 노드 목록에서 가져오기
	local depletedNode = depletedNodes[nodeUID]
	if not depletedNode then return end
	
	local nodeData = DataService.getResourceNode(depletedNode.nodeId)
	if not nodeData then return end
	
	-- activeNodes로 복귀 (기존 숨겼던 모델 복구)
	if depletedNode.nodeModel then
		-- 다시 보이게 하고 콜리전 복구
		local nodeModel = depletedNode.nodeModel
		nodeModel:SetAttribute("Depleted", false)
		-- 투명도 복원 (원래 값 저장/복원을 완벽히 안 하더라도 0으로 통일하거나 기본값)
		for _, part in ipairs(nodeModel:GetDescendants()) do
			if part:IsA("BasePart") then
				if part.Name ~= "Hitbox" then
					part.Transparency = 0
				end
				-- 콜리전 복원
				part.CanCollide = (part.Name ~= "Hitbox")
				part.CanQuery = true
				part.CanTouch = true
			elseif part:IsA("ParticleEmitter") or part:IsA("Trail") then
				part.Enabled = true
			end
		end
	else
		-- 도저히 모델이 없으면 재생성 시도
		local newModel = HarvestService.spawnNodeModel(depletedNode.nodeId, depletedNode.position, nodeUID)
		depletedNode.nodeModel = newModel
	end
	
	activeNodes[nodeUID] = {
		nodeId = depletedNode.nodeId,
		position = depletedNode.position,
		remainingHits = nodeData.maxHealth, -- 다시 maxHealth 풀로
		depletedAt = nil,
		respawnAt = nil,
		isAutoSpawned = depletedNode.isAutoSpawned,
		nodeModel = depletedNode.nodeModel,
	}
	
	-- 고갈된 노드 목록에서 제거
	depletedNodes[nodeUID] = nil
	
	-- 리스폰 이벤트
	if NetController then
		NetController.FireAllClients("Harvest.Node.Spawned", {
			nodeUID = nodeUID,
			nodeId = depletedNode.nodeId,
			position = depletedNode.position,
		})
	end
	
	print(string.format("[HarvestService] Node respawned: %s (%s)", nodeUID, depletedNode.nodeId))
end

--- 맨손 타격 가능 여부
function HarvestService.canHarvestBareHanded(nodeId: string): boolean
	local nodeData = DataService.getResourceNode(nodeId)
	if not nodeData then return false end
	-- requiresTool이 true인 경우 맨손 채집 불가
	return not nodeData.requiresTool
end

--========================================
-- Network Handlers
--========================================

local function handleHitRequest(player: Player, payload: any)
	local nodeUID = payload.nodeUID
	local hitCount = payload.hitCount -- Optional (Interact 시 전량 채집용)
	
	if not nodeUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- 보안/기획: 클라이언트가 보낸 toolSlot 대신, 서버의 현재 활성 슬롯(Active Slot)을 사용
	local activeSlot = 1
	if InventoryService then
		activeSlot = InventoryService.getActiveSlot(player.UserId)
	end
	
	local success, errorCode, drops = HarvestService.hit(player, nodeUID, activeSlot, hitCount)
	
	if success then
		return { success = true, data = { drops = drops } }
	else
		return { success = false, errorCode = errorCode }
	end
end

local function handleGetNodesRequest(player: Player, payload: any)
	local nodes = HarvestService.getAllNodes()
	return { success = true, data = { nodes = nodes } }
end

--========================================
-- Initialization
--========================================

--- workspace.ResourceNodes 스캔하여 노드 등록
--- ResourceNodes 폴더 생성 (자동 스폰용)
local function ensureResourceNodesFolder()
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then
		nodeFolder = Instance.new("Folder")
		nodeFolder.Name = "ResourceNodes"
		nodeFolder.Parent = workspace
		print("[HarvestService] Created ResourceNodes folder in workspace")
	end
	return nodeFolder
end

--- 맵에 미리 배치된 노드(ResourceNodes 폴더 안)를 태깅/활성화
function HarvestService._setupPrePlacedNodes()
	local nodeFolder = ensureResourceNodesFolder()
	local count = 0
	local unmappedCount = 0
	local unmappedSamples = {}

	local function normalizeNodeName(name)
		return tostring(name or ""):lower():gsub("[%s_%-]", "")
	end

	local function resolveNodeId(nodeModel)
		if not nodeModel then
			return nil, nil
		end

		local candidates = { nodeModel.Name }
		if nodeModel.Parent and nodeModel.Parent:IsA("Folder") then
			table.insert(candidates, nodeModel.Parent.Name)
		end

		for _, candidate in ipairs(candidates) do
			local nodeData = DataService.getResourceNode(candidate)
			if nodeData then
				return candidate, nodeData
			end
		end

		local normalizedCandidates = {}
		for _, candidate in ipairs(candidates) do
			normalizedCandidates[normalizeNodeName(candidate)] = true
		end

		local resourceTable = DataService.get("ResourceNodeData") or {}
		for nodeId, nodeData in pairs(resourceTable) do
			local nodeIdNorm = normalizeNodeName(nodeId)
			local modelNameNorm = normalizeNodeName(nodeData.modelName)
			for candidateNorm in pairs(normalizedCandidates) do
				if candidateNorm == nodeIdNorm or candidateNorm == modelNameNorm then
					return nodeId, nodeData
				end
			end
		end

		return nil, nil
	end
	
	-- [수정] GetChildren 대신 GetDescendants를 사용하여 하위 폴더(TREE_THIN 등) 안의 모델도 모두 등록
	for _, nodeModel in ipairs(nodeFolder:GetDescendants()) do
		if nodeModel:IsA("Model") then
			local nodeId, nodeData = resolveNodeId(nodeModel)
			
			if nodeData then
				local primaryPart = nodeModel.PrimaryPart or nodeModel:FindFirstChildWhichIsA("BasePart", true)
				if primaryPart then
					-- [수정] 미리 배치된 모델도 셋업 로직을 거치게 함 (히트박스, 태그, 앵커링 등)
					setupModelForNode(nodeModel, primaryPart.Position, nodeData, false)
					
					-- 등록 진행 (수동 배치 노드는 isAutoSpawned = false)
					local uid = HarvestService.registerNode(nodeId, primaryPart.Position, false)
					
					-- ActiveNode의 모델 포인터 설정
					if activeNodes[uid] then
						activeNodes[uid].nodeModel = nodeModel
					end
					
					-- 속성 설정 (setupModelForNode에서 일부 수행하지만 UID 등 명시적 설정)
					nodeModel:SetAttribute("NodeId", nodeId)
					nodeModel:SetAttribute("NodeUID", uid)
					nodeModel:SetAttribute("Depleted", false)
					
					count = count + 1
				end
			else
				local isExplicitResourceNode = nodeModel:GetAttribute("ResourceNode") == true
					or nodeModel:GetAttribute("NodeId") ~= nil
				if isExplicitResourceNode then
					unmappedCount += 1
					if #unmappedSamples < 5 then
						table.insert(unmappedSamples, nodeModel.Name)
					end
				end
			end
		end
	end

	if unmappedCount > 0 then
		warn(string.format(
			"[HarvestService] %d pre-placed models were not mapped to ResourceNodeData (sample: %s)",
			unmappedCount,
			table.concat(unmappedSamples, ", ")
		))
	end
	print("[HarvestService] Pre-placed nodes setup complete. Total:", count)
end

function HarvestService.Init(
	netController: any,
	dataService: any,
	inventoryService: any,
	playerStatService: any,
	durabilityService: any,
	worldDropService: any,
	techService: any
)
	if initialized then return end
	
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	PlayerStatService = playerStatService
	DurabilityService = durabilityService
	WorldDropService = worldDropService
	TechService = techService
	
	-- ResourceNodes 폴더 사전 배치 노드 초기화
	task.spawn(function()
		task.wait(1) -- 맵 로드 대기
		HarvestService._setupPrePlacedNodes()
		
		-- [추가] 초기 맵 전체 분포 스폰 (바닥 자원 풍부화)
		HarvestService._initialSpawn()
	end)
	
	-- [수정] 자동스폰 루프 다시 활성화 (잔돌/나뭇가지 전용)
	task.spawn(function()
		while true do
			task.wait(NODE_SPAWN_INTERVAL)
			HarvestService._spawnLoop()
		end
	end)

	-- 디스폰 체크 (플레이어와 너무 멀면 제거하여 성능 확보)
	task.spawn(function()
		while true do
			task.wait(NODE_SPAWN_INTERVAL * 2)
			HarvestService._despawnCheck()
		end
	end)
	
	initialized = true

	local function seedForPlayer(player: Player)
		if not player then return end
		if starterNodesSeededUsers[player.UserId] then return end
		starterNodesSeededUsers[player.UserId] = true

		task.spawn(function()
			local character = player.Character or player.CharacterAdded:Wait()
			local hrp = character and character:WaitForChild("HumanoidRootPart", 10)
			if hrp then
				task.wait(0.3)
				HarvestService._ensureStarterGroundNodes(player)
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		seedForPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		seedForPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		starterNodesSeededUsers[player.UserId] = nil
	end)

	print("[HarvestService] Initialized — PRE-PLACED + AUTO-SPAWN MIXED system")
end

--- ★ 초기 대량 스폰 (서버 시작 시 맵 전체에 자원 노드 배치)
function HarvestService._initialSpawn()
	local INITIAL_COUNT = Balance.INITIAL_NODE_COUNT or 150
	local SPAWN_RADIUS = Balance.MAP_EXTENT or 1500
	local MAP_CENTER = Vector3.new(0, 0, 0) -- 맵 중심
	
	-- 맵 중심 찾기 (SpawnLocation이 있으면 그 위치 사용)
	local spawnLoc = workspace:FindFirstChild("SpawnLocation", true)
	if spawnLoc and spawnLoc:IsA("BasePart") then
		MAP_CENTER = spawnLoc.Position
	end
	
	print(string.format("[HarvestService] Starting initial spawn: %d nodes across radius %.0f", 
		INITIAL_COUNT, SPAWN_RADIUS))
	
	local spawned = 0
	local attempts = 0
	local MAX_ATTEMPTS = INITIAL_COUNT * 10 -- 성공률을 위해 시도 횟수 증가
	
	-- Exclude 리스트 (지형만 감지)
	local excludeList = {}
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if nodeFolder then table.insert(excludeList, nodeFolder) end
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if creaturesFolder then table.insert(excludeList, creaturesFolder) end
	
	while spawned < INITIAL_COUNT and attempts < MAX_ATTEMPTS do
		attempts = attempts + 1
		
		-- 사각형 맵 전역 분포 (Corners 포함)
		local xOffset = (math.random() * 2 - 1) * SPAWN_RADIUS
		local zOffset = (math.random() * 2 - 1) * SPAWN_RADIUS
		local x = MAP_CENTER.X + xOffset
		local z = MAP_CENTER.Z + zOffset
		local origin = Vector3.new(x, MAP_CENTER.Y + 400, z) -- 더 높은 곳에서 발사
		
		-- 지형/맵만 감지하도록 필터링 강화
		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		if workspace:FindFirstChild("Map") then
			table.insert(filterList, workspace.Map)
		end
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		local result = workspace:Raycast(origin, Vector3.new(0, -800, 0), params)
		if result then
			local isWater = result.Material == Enum.Material.Water
				or result.Material == Enum.Material.CrackedLava
			-- Balance.SEA_LEVEL 또는 로컬 SEA_LEVEL 사용
			local currentSeaLevel = Balance.SEA_LEVEL or SEA_LEVEL or 10
			local belowSeaLevel = result.Position.Y < currentSeaLevel
			
			if not isWater and not belowSeaLevel then
				-- 기존 노드와 거리 체크 (최소 12 studs 간격)
				local tooClose = false
				if nodeFolder then
					for _, existing in ipairs(nodeFolder:GetDescendants()) do
						if existing:IsA("Model") then
							local ePart = existing.PrimaryPart or existing:FindFirstChildWhichIsA("BasePart")
							if ePart and (ePart.Position - result.Position).Magnitude < 12 then
								tooClose = true
								break
							end
						end
					end
				end
				
				if not tooClose then
					local pos = result.Position + Vector3.new(0, 0.5, 0)
					local nodeId = selectNodeForTerrain(result.Material)
					if nodeId then
						-- ★ 초기 스폰은 isAutoSpawned = false로 설정하여 "Map" 노드화 (해당 자리 리젠)
						local uid = HarvestService.registerNode(nodeId, pos, false)
						
						-- 모델 생성 (uid 전달하여 속성 설정)
						HarvestService.spawnNodeModel(nodeId, pos, uid)
						
						spawned = spawned + 1
					end
				end
			end
		end
	end
	
	print(string.format("[HarvestService] Initial spawn complete: %d/%d nodes spawned (%d attempts)", 
		spawned, INITIAL_COUNT, attempts))
end

--- 보충 스폰 루프 (CAP까지 부족한 수만큼만 보충)
function HarvestService._replenishLoop()
	-- 현재 활성 노드 수 계산
	local totalActiveNodes = 0
	for _ in pairs(activeNodes) do
		totalActiveNodes = totalActiveNodes + 1
	end
	
	-- CAP 미만이면 보충
	if totalActiveNodes >= NODE_CAP then return end
	
	local deficit = NODE_CAP - totalActiveNodes
	local toSpawn = math.min(deficit, 3) -- 한 번에 최대 3개씩 보충 (급격한 변화 방지)
	
	for _, player in ipairs(Players:GetPlayers()) do
		if toSpawn <= 0 then break end
		
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local pos, material = HarvestService._findSpawnPosition(char.HumanoidRootPart)
			if pos and material then
				local nodeId = selectNodeForTerrain(material)
				if nodeId then
					local uid = HarvestService._spawnAutoNode(nodeId, pos)
					if uid then
						toSpawn = toSpawn - 1
					end
				end
			end
		end
	end
end

function HarvestService.GetHandlers()
	return {
		["Harvest.Hit.Request"] = handleHitRequest,
		["Harvest.GetNodes.Request"] = handleGetNodesRequest,
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function HarvestService.SetQuestCallback(callback)
	questCallback = callback
end

return HarvestService
