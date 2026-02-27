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

-- 지형별 스폰 풀
local GRASS_TERRAIN_NODES = {"TREE_OAK", "TREE_PINE", "BUSH_BERRY", "FIBER_GRASS", "GROUND_BRANCH", "GROUND_BRANCH", "GROUND_STONE", "GROUND_STONE"}
local ROCK_TERRAIN_NODES = {"ROCK_NORMAL", "ORE_COPPER", "ORE_TIN", "ORE_IRON", "ORE_COAL", "GROUND_STONE"}
local SAND_TERRAIN_NODES = {"ROCK_NORMAL", "FIBER_GRASS", "GROUND_STONE", "GROUND_STONE"}
local GROUND_TERRAIN_NODES = {"TREE_OAK", "ROCK_NORMAL", "BUSH_BERRY", "FIBER_GRASS", "GROUND_BRANCH", "GROUND_BRANCH", "GROUND_STONE", "GROUND_STONE"}

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
	
	-- 1. 정확한 이름 매칭
	local template = modelsFolder:FindFirstChild(modelName)
	if template then return template end
	
	-- 2. nodeId로 매칭 (ex: "TREE_OAK" -> "Tree_Oak", "TreeOak")
	template = modelsFolder:FindFirstChild(nodeId)
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
local function setupModelForNode(model: Model, position: Vector3, nodeData: any): Model
	-- Toolbox 모델 정리
	cleanModelForHarvest(model)
	
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
	
	-- 위치 설정 (기존 모델 방향 유지, Y축만 랜덤 회전 추가)
	if primaryPart then
		-- 모델 하단이 지면에 닿도록 조정 (모든 파트 중 가장 낮은 Y값 추적)
		local minY = math.huge
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				-- 특정 이름의 파트(예: 원점에서 멀리 떨어진 헬퍼 가시 등)는 제외할 수 있으나 기본은 전체 포함
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
		
		-- Y축 랜덤 회전 (자연스러운 배치)
		local randomYRot = math.rad(math.random(0, 359))
		-- 지면(position)에서 pivotOffset만큼 위로 띄워야 하단이 지면에 맞음
		local targetCF = CFrame.new(position) * CFrame.Angles(0, randomYRot, 0) * CFrame.new(0, pivotOffset, 0)
		model:PivotTo(targetCF)
	else
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
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(6, 5, 6) -- 넓고 낮은 박스
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = true
	-- 지면 위치에 배치 (yOffset 고려)
	local _, modelSize = model:GetBoundingBox()
	hitbox.CFrame = model.PrimaryPart.CFrame * CFrame.new(0, -modelSize.Y/2 + 2.5, 0)
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
	
	-- Assets/ResourceNodeModels 폴더 찾기
	local modelsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if modelsFolder then
		modelsFolder = modelsFolder:FindFirstChild("ResourceNodeModels")
	end
	
	local modelName = nodeData.modelName or nodeId
	local template = findResourceModel(modelsFolder, modelName, nodeId)
	
	local model
	if template then
		-- 실제 모델 복제
		model = template:Clone()
		model.Name = nodeId
		model.Parent = nodeFolder -- Parent early to avoid joint warnings
		model = setupModelForNode(model, position, nodeData)
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
			return tool:GetAttribute("ToolType") or tool.Name:upper()
		end
	end
	
	-- 3. 아이템 데이터의 optimalTool(타입) 확인
	if toolItem and DataService then
		local itemData = DataService.getItem(toolItem.itemId)
		if itemData then
			return itemData.optimalTool or itemData.id:upper()
		end
	end
	
	return nil
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
	-- nodeData가 nil인 경우 (비정상)
	if not nodeData then return false, Enums.ErrorCode.NOT_FOUND end
	
	local equippedToolType = getToolType(player, toolSlot)
	
	-- 도구 필수 여부 확인
	if nodeData.requiresTool then
		if not equippedToolType then
			-- 맨손인데 도구가 필수인 경우
			return false, Enums.ErrorCode.WRONG_TOOL
		end
		
		-- 최적 도구(optimalTool)가 지정된 경우, 호환되는 도구여야만 함
		if nodeData.optimalTool and nodeData.optimalTool ~= "" then
			if not isCompatible(equippedToolType, nodeData.optimalTool) then
				return false, Enums.ErrorCode.WRONG_TOOL
			end
		end
	end
	
	-- 모든 자원은 도구가 있으면 일단 채집 가능 (효율은 calculateEfficiency에서 처리)
	-- (위의 requiresTool 체크를 통과했다면)
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
		baseEff = 1.0
	elseif isCompatible(toolType, nodeOptimalType) then
		-- 타입 일치: 기본 효율 높음 + 도구 위력(데미지)에 따른 보정
		baseEff = Balance.HARVEST_EFFICIENCY_OPTIMAL or 1.2
		-- 티어 가산: 데미지 10당 +0.1 효율 (청동 = 25뎀 = +0.25)
		baseEff = baseEff + (toolDamage / 100)
	elseif toolType then
		-- 잘못된 도구 (validateTool에서 걸러지지 않은 경우 - requiresTool=false인 대형 노드 등)
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
		
		-- Raycast
		local params = RaycastParams.new()
		local filterList = { workspace.Terrain }
		if workspace:FindFirstChild("Map") then
			table.insert(filterList, workspace.Map)
		end
		params.FilterDescendantsInstances = filterList
		params.FilterType = Enum.RaycastFilterType.Include
		
		local result = workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
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
					for _, existingNode in ipairs(nodeFolder:GetChildren()) do
						local existingPart = existingNode.PrimaryPart or existingNode:FindFirstChildWhichIsA("BasePart")
						if existingPart then
							if (existingPart.Position - result.Position).Magnitude < 8 then
								tooClose = true
								break
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
					-- 지형에 맞는 노드 선택
					local nodeId = selectNodeForTerrain(material)
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
	
	for _, nodeModel in ipairs(nodeFolder:GetChildren()) do
		-- 자동 스폰된 노드만 디스폰 (수동 배치는 유지)
		if nodeModel:GetAttribute("AutoSpawned") then
			local nodeUID = nodeModel:GetAttribute("NodeUID")
			local nodePart = nodeModel.PrimaryPart or nodeModel:FindFirstChildWhichIsA("BasePart")
			
			if nodePart then
				-- 가장 가까운 플레이어와의 거리 체크
				local minDist = math.huge
				for _, player in ipairs(Players:GetPlayers()) do
					local char = player.Character
					if char and char:FindFirstChild("HumanoidRootPart") then
						local dist = (char.HumanoidRootPart.Position - nodePart.Position).Magnitude
						if dist < minDist then
							minDist = dist
						end
					end
				end
				
				-- 너무 멀면 디스폰
				if minDist > DESPAWN_DIST then
					-- activeNodes에서 제거
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
		remainingHits = nodeData.maxHits,
		depletedAt = nil,
		position = position,
		isAutoSpawned = isAutoSpawned,
	}
	
	-- 타입별 카운트 증가 (모든 노드 추적)
	spawnedNodesByType[nodeId] = (spawnedNodesByType[nodeId] or 0) + 1
	if isAutoSpawned then
		spawnedNodeCount = spawnedNodeCount + 1
	end
	
	-- 클라이언트에 노드 스폰 알림 (네트워크 최적화: 400스터드)
	if NetController then
		NetController.FireClientsInRange(position, 400, "Harvest.Node.Spawned", {
			nodeUID = nodeUID,
			nodeId = nodeId,
			position = position,
			maxHits = nodeData.maxHits,
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
	
	-- 2. 노드 존재 확인 (고갈된 노드는 activeNodes에서 제거됨)
	local nodeState = activeNodes[nodeUID]
	if not nodeState then
		return false, Enums.ErrorCode.NODE_NOT_FOUND, nil
	end
	
	-- 3. 노드 데이터 조회
	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 4. 거리 검증
	local character = player.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local distance = (humanoidRootPart.Position - nodeState.position).Magnitude
			local maxRange = Balance.HARVEST_RANGE or 5
			if distance > maxRange then
				return false, Enums.ErrorCode.OUT_OF_RANGE, nil
			end
		end
	end
	
	-- 5. 도구 검증 (특정 자원은 맨손 불가)
	local toolOk, toolError = validateTool(player, nodeData, toolSlot)
	if not toolOk then
		-- 맨손 채집 불가 시 안내 (클라이언트에서 처리하거나 여기서 ErrorCode 전달)
		return false, toolError or Enums.ErrorCode.WRONG_TOOL, nil
	end
	
	-- 6. 효율 계산
	local efficiency = calculateEfficiency(player, nodeData.optimalTool, toolSlot)
	
	-- 7. 타격 처리
	local workSpeedStat = 0
	if PlayerStatService then
		local stats = PlayerStatService.getStats(player.UserId)
		workSpeedStat = (stats and stats.statInvested and stats.statInvested[Enums.StatId.WORK_SPEED]) or 0
	end
	
	local power = 1 + math.floor(workSpeedStat / 10) -- 10점당 타격 횟수 +1 (속도)
	local actualHitCount = math.min(power, nodeState.remainingHits)
	nodeState.remainingHits = nodeState.remainingHits - actualHitCount
	
	-- 도구 내구도 감소
	if toolSlot and DurabilityService then
		DurabilityService.reduceDurability(player, toolSlot, 1)
	end
	
	-- 7.5 XP 보상 (타격당 지급)
	if PlayerStatService then
		local xpPerHit = nodeData.xpPerHit or Balance.XP_HARVEST_XP_PER_HIT or 2
		PlayerStatService.addXP(player.UserId, xpPerHit * actualHitCount, Enums.XPSource.HARVEST_RESOURCE)
	end
	
	-- 타격 브로드캐스트 (네트워크 최적화: 400스터드)
	if NetController then
		NetController.FireClientsInRange(nodeState.position, 400, "Harvest.Node.Hit", {
			nodeUID = nodeUID,
			remainingHits = nodeState.remainingHits,
			maxHits = nodeData.maxHits
		})
	end
	
	-- 8. 노드 고갈 처리 (모델 파괴 + 드롭 생성)
	local drops = {}
	if nodeState.remainingHits <= 0 then
		-- 고갈 시 드롭 계산 (효율 적용)
		drops = calculateDrops(nodeData, efficiency)
		
		print(string.format("[HarvestService] Calculated drops for %s: %d items", nodeUID, #drops))
		
		-- 월드 드롭으로 생성 (인벤토리 직접 추가 X)
		for i, drop in ipairs(drops) do
			print(string.format("[HarvestService] Drop %d: %s x%d", i, drop.itemId, drop.count))
			if WorldDropService then
				-- 랜덤 위치에 드롭 (노드 주변)
				local angle = math.random() * math.pi * 2
				local radius = math.random() * 2 + 1
				local dropPosition = nodeState.position + Vector3.new(
					math.cos(angle) * radius,
					1.5,
					math.sin(angle) * radius
				)
				local success, err, dropData = WorldDropService.spawnDrop(dropPosition, drop.itemId, drop.count)
				if success and dropData then
					print(string.format("[HarvestService] Spawned drop: %s at %s", tostring(dropData.dropId), tostring(dropPosition)))
				else
					warn("[HarvestService] Failed to spawn drop:", err)
				end
			else
				warn("[HarvestService] WorldDropService is nil!")
			end
		end
		
		-- 서버에서 모델 파괴 (원본 데이터 저장)
		local originalPartData = HarvestService._destroyNodeModel(nodeUID)
		
		-- 고갈된 노드 처리
		if nodeState.isAutoSpawned then
			-- 자동 스폰된 노드는 리스폰 시키지 않고 카운트만 감소
			local nodeId = nodeState.nodeId
			spawnedNodesByType[nodeId] = math.max(0, (spawnedNodesByType[nodeId] or 0) - 1)
			spawnedNodeCount = math.max(0, spawnedNodeCount - 1)
			activeNodes[nodeUID] = nil
			-- _respawnNode를 예약하지 않음
		else
			-- 수동 배치된 노드는 리스폰 예약
			depletedNodes[nodeUID] = {
				nodeId = nodeState.nodeId,
				position = nodeState.position,
				respawnAt = os.time() + (nodeData.respawnTime or 300),
				originalPartData = originalPartData,
			}
			activeNodes[nodeUID] = nil
			
			-- 리스폰 예약
			task.delay(nodeData.respawnTime or 300, function()
				HarvestService._respawnNode(nodeUID)
			end)
		end
		
		-- 퀘스트 콜백 (Phase 8)
		if questCallback then
			questCallback(userId, nodeData.nodeType or nodeData.id)
		end
		
		-- 도구 내구도 감소
		if DurabilityService and toolSlot then
			-- 타격 횟수만큼 내구도 감소
			-- 내구도가 있는 아이템인지 확인 (InventoryService가 내부에서 검증하지만 warn 방지용 사전 체크)
			local inv = InventoryService.getInventory(player.UserId)
			local slotData = inv and inv.slots[toolSlot]
			if slotData and slotData.durability then
				DurabilityService.reduceDurability(player, toolSlot, actualHitCount)
			end
		elseif DurabilityService and not toolSlot and nodeData.optimalTool then
			warn(string.format("[HarvestService] No toolSlot provided for node %s", nodeUID))
		end
	end
	
	return true, nil, drops
end

--- 노드 모델 파괴 (내부) - 모델을 완전히 비활성화
function HarvestService._destroyNodeModel(nodeUID: string)
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then return nil end
	
	for _, nodeModel in ipairs(nodeFolder:GetChildren()) do
		if nodeModel:GetAttribute("NodeUID") == nodeUID then
			-- 고갈 표시
			nodeModel:SetAttribute("Depleted", true)
			
			-- 완전히 제거 (투명화 방식보다 확실하고 성능에 좋음)
			nodeModel:Destroy()
			
			return {} -- 성공 표시 (데이터는 필요 없음)
		end
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
	
	-- 서버에 새 모델 스폰 (기존의 복구 방식 대신 새로 생성)
	local newModel = HarvestService.spawnNodeModel(depletedNode.nodeId, depletedNode.position)
	if newModel then
		newModel:SetAttribute("NodeUID", nodeUID)
	end
	
	-- activeNodes로 복귀
	activeNodes[nodeUID] = {
		nodeId = depletedNode.nodeId,
		position = depletedNode.position,
		remainingHits = nodeData.maxHits,
		depletedAt = nil,
		respawnAt = nil,
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

function HarvestService.Init(
	netController: any,
	dataService: any,
	inventoryService: any,
	playerStatService: any,
	durabilityService: any,
	worldDropService: any
)
	if initialized then return end
	
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	PlayerStatService = playerStatService
	DurabilityService = durabilityService
	WorldDropService = worldDropService
	
	-- ResourceNodes 폴더 생성
	task.spawn(function()
		task.wait(1) -- 맵 로드 대기
		ensureResourceNodesFolder()
		
		-- ★ 초기 대량 스폰 (서버 시작 시 즉시)
		HarvestService._initialSpawn()
	end)
	
	-- 보충 스폰 루프 (채집/소멸된 만큼만 보충)
	task.spawn(function()
		task.wait(10) -- 초기 스폰 완료 후 시작
		while true do
			task.wait(NODE_SPAWN_INTERVAL)
			HarvestService._replenishLoop()
		end
	end)
	
	-- 디스폰 체크 루프 (30초마다)
	task.spawn(function()
		task.wait(5)
		while true do
			task.wait(30)
			HarvestService._despawnCheck()
		end
	end)
	
	initialized = true
	print("[HarvestService] Initialized with initial spawn + replenish system")
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
					for _, existing in ipairs(nodeFolder:GetChildren()) do
						local ePart = existing.PrimaryPart or existing:FindFirstChildWhichIsA("BasePart")
						if ePart and (ePart.Position - result.Position).Magnitude < 12 then
							tooClose = true
							break
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
