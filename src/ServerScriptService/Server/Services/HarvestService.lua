-- HarvestService.lua
-- 자원 수확 시스템 (Phase 7-1)
-- 플레이어가 자원 노드(나무, 돌, 풀)에서 아이템 획득
-- 유연한 모델 로딩: Toolbox에서 가져온 어떤 구조의 모델도 지원
-- 자동 스폰: 플레이어 주변에 자동으로 자원 노드 생성

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local CreatureAnimationIds = require(Shared.Config.CreatureAnimationIds)

local Data = ReplicatedStorage:WaitForChild("Data")
local MaterialAttributeData = require(Data.MaterialAttributeData)

local HarvestService = {}

--========================================
-- 스폰 상수
--========================================
local NODE_SPAWN_INTERVAL = Balance.NODE_SPAWN_INTERVAL or 10
local NODE_CAP = Balance.RESOURCE_NODE_CAP or 400
local MIN_SPAWN_DIST = 20
local MAX_SPAWN_DIST = 60
local DESPAWN_DIST = Balance.NODE_DESPAWN_DIST or 300
local NODE_DESPAWN_GRACE_AFTER_INTERACT = 120
local SEA_LEVEL = Balance.SEA_LEVEL or 2
local STARTER_NODE_TARGET_PER_TYPE = 2
local STARTER_NODE_CHECK_RADIUS = 45
local STARTER_NODE_MIN_DIST = 8
local STARTER_NODE_MAX_DIST = 24
local STARTER_NODE_TYPES = { "GROUND_BRANCH", "GROUND_FIBER" }

-- 섬별 스폰 밸런싱 데이터
local SpawnConfig = require(ReplicatedStorage.Shared.Config.SpawnConfig)

-- Zone별 스폰 완료 여부 추적 (허브가 아닌 섬은 포탈 이동 시까지 지연)
local spawnedZones = {}

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

-- 지형별 초기 스폰 노드 풀
local GRASS_TERRAIN_NODES = { "TREE_THIN", "BUSH_BERRY", "GROUND_FIBER", "GROUND_BRANCH" }
local ROCK_TERRAIN_NODES = { "ROCK_SOFT" }
local SAND_TERRAIN_NODES = { "GROUND_BRANCH" }
local GROUND_TERRAIN_NODES = { "GROUND_FIBER", "GROUND_BRANCH" }

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

-- R키 채집 시스템: 진행 중인 단건 채집 상태 { [userId] = { nodeUID, itemId, startTime, gatherTime, count } }
local activeGathers = {}

local questCallback = nil
-- 스폰된 노드 수 추적 (자동스폰된 노드만)
local spawnedNodeCount = 0
local spawnedNodesByType = {} -- { [nodeId] = count }
local starterNodesSeededUsers = {} -- [userId] = true
local templateCache = {} -- { [nodeId] = Model } 첫 성공 시 캐시
local getNodeSceneRoot
local applyNodeIdentity
local ensureHiddenNodeFolder
local cachedBaseClaimService = nil
--========================================
-- Internal Functions
--========================================

--- 고유 노드 ID 생성
local function generateNodeUID(): string
	nodeCount = nodeCount + 1
	return string.format("node_%d_%d", os.time(), nodeCount)
end

local function calculateDamagePerGather(totalHealth: number, totalGathers: number): number
	return math.max(1, math.ceil(totalHealth / math.max(1, totalGathers)))
end

local function calculateRemainingGatherCount(remainingHits: number, damagePerGather: number): number
	if remainingHits <= 0 then
		return 0
	end

	return math.ceil(remainingHits / math.max(1, damagePerGather))
end

local function getInitialGatherTotal(nodeState: any, nodeData: any): number
	if nodeState and nodeState.resolvedResources then
		return math.max(1, tonumber(nodeState.resolvedTotalGathers) or tonumber(nodeState.resolvedMaxHealth) or 1)
	end

	local total = 0
	for _, res in ipairs((nodeData and nodeData.resources) or {}) do
		total = total + (res.max or res.count or 1)
	end
	return math.max(1, total)
end

local function getCurrentResolvedGatherTotal(nodeState: any): number
	local total = 0
	for _, res in ipairs((nodeState and nodeState.resolvedResources) or {}) do
		total = total + math.max(0, tonumber(res.count) or 0)
	end
	return total
end

local function getBaseClaimService()
	if cachedBaseClaimService ~= nil then
		return cachedBaseClaimService
	end

	local ok, service = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.BaseClaimService)
	end)
	cachedBaseClaimService = ok and service or false
	return cachedBaseClaimService
end

local function isInsideAnyTotemBase(position: Vector3?): boolean
	if not position then
		return false
	end

	local baseClaimService = getBaseClaimService()
	if not baseClaimService or baseClaimService == false or not baseClaimService.getOwnerAt then
		return false
	end

	return baseClaimService.getOwnerAt(position) ~= nil
end

--========================================
-- 유연한 모델 로딩 시스템 (Toolbox 모델 지원)
--========================================

--- 자원 모델 찾기 (정확 매칭 우선, 부분 매칭은 후순위)
--- ★ Pass 1: 정확한 modelName/nodeId 매칭만 시도
--- ★ Pass 2: 부분 문자열 매칭 (fallback)
local function findResourceModel(modelsFolder, modelName, nodeId)
	if not modelsFolder then return nil end
	
	local lowerModelName = modelName:lower()
	local lowerNodeId = nodeId:lower()
	local lastPart = lowerNodeId:match("_([^_]+)$") or lowerNodeId
	local nodeType = lowerNodeId:match("^([^_]+)")
	
	-- 정확 매칭 (modelName 또는 nodeId 완전 일치)
	local function exactMatch(name)
		local lower = name:lower()
		return lower == lowerModelName or lower == lowerNodeId
	end
	
	-- 부분 매칭 (lastPart 또는 nodeType 포함)
	local function partialMatch(name)
		local lower = name:lower()
		if lower:find(lowerModelName, 1, true) or lowerModelName:find(lower, 1, true) then return true end
		if lower:find(lastPart, 1, true) then return true end
		if nodeType and lower:find(nodeType, 1, true) then return true end
		return false
	end
	
	local function cloneFolderAsModel(folder)
		local wrapper = Instance.new("Model")
		wrapper.Name = folder.Name
		for attrName, attrValue in pairs(folder:GetAttributes()) do
			wrapper:SetAttribute(attrName, attrValue)
		end
		for _, child in ipairs(folder:GetChildren()) do
			child:Clone().Parent = wrapper
		end
		return wrapper
	end

	-- Folder 내부에서 구조 보존형 템플릿 생성 헬퍼
	local function getModelFromFolder(folder)
		local children = folder:GetChildren()
		if #children == 0 then
			return nil
		end
		if #children == 1 and (children[1]:IsA("Model") or children[1]:IsA("BasePart")) then
			return children[1]
		end
		return cloneFolderAsModel(folder)
	end
	
	-- ====== Pass 1: 정확 매칭만 시도 ======
	-- 1-A: Folder 내부 (정확)
	for _, child in ipairs(modelsFolder:GetChildren()) do
		if child:IsA("Folder") and exactMatch(child.Name) then
			local found = getModelFromFolder(child)
			if found then
				return found
			end
		end
	end
	-- 1-B: 직접 Model/BasePart (정확)
	for _, child in ipairs(modelsFolder:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and exactMatch(child.Name) then
			return child
		end
	end
	
	-- ====== Pass 2: 부분 매칭 (fallback) ======
	-- 2-A: Folder 내부 (부분)
	for _, child in ipairs(modelsFolder:GetChildren()) do
		if child:IsA("Folder") and partialMatch(child.Name) then
			local found = getModelFromFolder(child)
			if found then
				return found
			end
		end
	end
	-- 2-B: 직접 Model/BasePart (부분)
	for _, child in ipairs(modelsFolder:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and partialMatch(child.Name) then
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
end

--- 모델을 자원 노드로 설정 (어떤 구조든 지원)
local function setupModelForNode(model: Model, position: Vector3, nodeData: any, isAutoSpawn: boolean): Model
	-- Toolbox 모델 정리
	cleanModelForHarvest(model)

	-- 나뭇가지는 식별성을 위해 시각 크기를 소폭 상향
	if nodeData and nodeData.id == "GROUND_BRANCH" then
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
	-- ★ CanCollide = false: R키 상호작용이므로 물리 충돌 불필요 (이동 방해 제거)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
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
	
	-- 캐시된 템플릿 우선 사용
	local template = templateCache[nodeId]
	if not template then
		-- 캐시 미스 시 Assets 등 외부 폴더에서만 검색
		for _, folder in ipairs(searchFolders) do
			if folder and folder ~= nodeFolder then
				template = findResourceModel(folder, modelName, nodeId)
				if template then
					templateCache[nodeId] = template
					break
				end
			end
		end
	end
	
	local model
	if template then
		-- 실제 모델 복제
		model = template:Clone()
		model.Name = nodeId
		model.Parent = nodeFolder -- Parent early to avoid joint warnings
		model = setupModelForNode(model, position, nodeData, true)
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
				if isInsideAnyTotemBase(candidatePos) then
					continue
				end
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
				if isInsideAnyTotemBase(result.Position) then
					continue
				end
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

	if STARTER_NODE_TYPES and table.find(STARTER_NODE_TYPES, nodeId) and isInsideAnyTotemBase(position) then
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
	
	-- [수정] 플레이어 밀집도 기반 스폰 제한 로직
	local players = Players:GetPlayers()
	local spawnRepresentativeParts = {}
	local GROUP_RADIUS = 120 -- 이 반경 내 플레이어들은 하나의 그룹으로 간주
	
	for _, player in ipairs(players) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local isNearGroup = false
			for _, repPart in ipairs(spawnRepresentativeParts) do
				if (hrp.Position - repPart.Position).Magnitude < GROUP_RADIUS then
					isNearGroup = true
					break
				end
			end
			
			if not isNearGroup then
				table.insert(spawnRepresentativeParts, hrp)
			end
		end
	end
	
	-- 그룹화된 대표 플레이어 걸처에서만 스폰 시도
	for _, repHRP in ipairs(spawnRepresentativeParts) do
		-- [수정] 스폰 확률 하향 (20%%)
		if math.random() <= 0.2 then
			local pos, material = HarvestService._findSpawnPosition(repHRP)
			if pos and material then
				local zoneName = SpawnConfig.GetZoneAtPosition(repHRP.Position)
				local nodeId
				if zoneName then
					nodeId = SpawnConfig.GetRandomGroundHarvestForZone(zoneName)
				else
					nodeId = SpawnConfig.GetRandomGroundHarvest()
				end
				if nodeId then
					HarvestService._spawnAutoNode(nodeId, pos)
					
					totalActiveNodes = totalActiveNodes + 1
					if totalActiveNodes >= NODE_CAP then break end
				end
			end
		end
	end
end



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

	local protectedGatherNodes = {}
	for _, gatherState in pairs(activeGathers) do
		if gatherState and gatherState.nodeUID then
			protectedGatherNodes[gatherState.nodeUID] = true
		end
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
			local nodeState = nodeUID and activeNodes[nodeUID]
			local nodeData = nodeState and DataService.getResourceNode(nodeState.nodeId)
			local wasInteractedRecently = nodeState
				and nodeState.lastInteractedAt
				and ((tick() - nodeState.lastInteractedAt) < NODE_DESPAWN_GRACE_AFTER_INTERACT)
			local isDamagedNode = nodeState and nodeData and nodeState.remainingHits < nodeData.maxHealth
			if (nodeUID and protectedGatherNodes[nodeUID]) or wasInteractedRecently or isDamagedNode then
				continue
			end
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
	
	if nodeId == "GROUND_STONE" then
		return nodeUID -- 블랙리스트는 조용히 무시
	end

	if not nodeData then
		warn(string.format("[HarvestService] Unknown node: %s", nodeId))
		return nodeUID
	end
	
	activeNodes[nodeUID] = {
		nodeId = nodeId,
		remainingHits = nodeData.maxHealth, -- maxHits 대신 maxHealth 사용 (호환성을 위해 변수명은 유지 가능하나 내부 값은 Health)
		initialTotalGathers = getInitialGatherTotal(nil, nodeData),
		depletedAt = nil,
		position = position,
		lastInteractedAt = nil,
		isAutoSpawned = isAutoSpawned,
		nodeModel = nil, -- 노드 모델 참조 (숨김 복원용)
		nodeRoot = nil, -- 래퍼 폴더/모델 포함 실제 장면 루트
		nodeOriginalParent = nil,
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

-- 시체 디스폰 시간 (초)
local CORPSE_DESPAWN_TIME = 60
local CORPSE_BLINK_START = 10   -- 사라지기 n초 전부터 깜빡임

--- 시체 노드 등록 (크리처 사망 시 호출)
--- creature 모델을 ResourceNodes 폴더로 이전하고 채집 가능하도록 설정
function HarvestService.registerCorpseNode(creatureId: string, position: Vector3, model: Model): string?
	local nodeId = "CORPSE_" .. creatureId
	local nodeData = DataService.getResourceNode(nodeId)
	if not nodeData then
		warn(string.format("[HarvestService] Unknown corpse node: %s", nodeId))
		return nil
	end

	local nodeUID = generateNodeUID()

	-- ResourceNodes 폴더 확보
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then
		nodeFolder = Instance.new("Folder")
		nodeFolder.Name = "ResourceNodes"
		nodeFolder.Parent = workspace
	end

	-- 기존 크리처 모델 정리: 스크립트/사운드/BillboardGui 제거
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript")
			or desc:IsA("Sound") or desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			desc:Destroy()
		end
	end

	-- Humanoid 외부 AnimationController 제거
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("AnimationController") then
			desc:Destroy()
		end
	end

	-- 속성 설정 (InteractController 인식용) — 폴더 이동 전에 설정
	model:SetAttribute("NodeId", nodeId)
	model:SetAttribute("NodeUID", nodeUID)
	model:SetAttribute("AutoSpawned", false)
	model:SetAttribute("Depleted", false)
	CollectionService:AddTag(model, "ResourceNode")

	-- ★ 모델을 ResourceNodes로 먼저 이동 (클라이언트 AnimController 추적 해제)
	model.Name = nodeId
	model.Parent = nodeFolder

	-- 클라이언트 ChildRemoved 처리 대기 → 클라이언트 애니메이션 루프 정지
	task.wait(0.3)

	-- ★ 이미 쓰러진(HasCollapsed) 크리처는 사망 포즈가 이미 고정되어 있으므로 데스 애니 재생 스킵
	local hasCollapsed = model:GetAttribute("HasCollapsed") == true

	-- 사망 애니메이션 재생 (Humanoid + Animator 유지)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local deathTrack = nil
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		-- ★ PlatformStand 제거: Motor6D 관절 비활성화로 애니메이션 불가 방지
		humanoid.PlatformStand = false
		
		-- ★ Dead 상태 방지 + Health 복원 (애니메이션 재생 위해)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		humanoid.MaxHealth = 100
		humanoid.Health = 1

		if hasCollapsed then
			-- ★ 쓰러진 크리처: 클라이언트 애니메이션은 모델 이동으로 소실되므로
			-- 서버에서 데스 애니를 다시 로드 → 95% 지점으로 즉시 점프 → 프리즈
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end

			-- 데스 애니메이션 로드 (기존 트랙은 아직 유지 — 포즈 보존)
			local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT or {}
			local deathAnimName = animSet.DEATH or (creatureId .. "_Death")
			local animObj = nil
			local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
			if assetsFolder then
				local animFolder = assetsFolder:FindFirstChild("Animations")
				if animFolder then
					animObj = animFolder:FindFirstChild(deathAnimName, true)
				end
			end
			if not animObj then
				animObj = ReplicatedStorage:FindFirstChild(deathAnimName, true)
			end

			if animObj and animObj:IsA("Animation") then
				local collapseTrack = animator:LoadAnimation(animObj)
				collapseTrack.Looped = false
				collapseTrack.Priority = Enum.AnimationPriority.Action4

				-- ★ Length 로딩 대기 (Play 전 — 기존 트랙이 포즈를 유지하는 동안)
				local waited = 0
				while collapseTrack.Length <= 0 and waited < 2 do
					task.wait(0.1)
					waited = waited + 0.1
				end

				-- ★ 기존 트랙 정지 + 새 트랙 Play + 95% 점프 + 프리즈를 한 프레임에 수행
				-- → 일어서는 모션 없이 즉시 눕기 포즈 적용
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
				collapseTrack:Play(0)
				if collapseTrack.Length > 0 then
					collapseTrack.TimePosition = collapseTrack.Length * 0.95
				end
				collapseTrack:AdjustSpeed(0)
				deathTrack = collapseTrack
			else
				-- 애니메이션 못 찾을 경우 기존 트랙만 정지
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
			end
			-- PlatformStand 설정하여 물리 간섭 제거
			humanoid.PlatformStand = true
		else
			-- 기존 애니메이션 전부 중지 (fade 적용)
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0.2)
			end

		-- 데스 애니메이션 검색 (CreatureAnimationIds 우선, 폴백으로 creatureId_Death)
		local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT or {}
		local deathAnimName = animSet.DEATH or (creatureId .. "_Death")
		local animObj = nil
		local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
		if assetsFolder then
			local animFolder = assetsFolder:FindFirstChild("Animations")
			if animFolder then
				animObj = animFolder:FindFirstChild(deathAnimName, true)
			end
		end
		if not animObj then
			animObj = ReplicatedStorage:FindFirstChild(deathAnimName, true)
		end

		if animObj and animObj:IsA("Animation") then
			deathTrack = animator:LoadAnimation(animObj)
			deathTrack.Looped = false
			deathTrack.Priority = Enum.AnimationPriority.Action4
			deathTrack:Play(0.2)
		else
			warn(string.format("[HarvestService] Death anim FAILED for %s: animObj=%s, class=%s", 
				deathAnimName, 
				tostring(animObj), 
				animObj and animObj.ClassName or "nil"))
		end
		end -- hasCollapsed else end
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if rootPart then
		rootPart.Anchored = true
		rootPart.CanCollide = false
		rootPart.CanQuery = true
		rootPart.CanTouch = true
	end

	-- 크리처별 지면 오프셋 (체형에 따라 다름)
	local CORPSE_GROUND_OFFSETS = {
		COMPY = 2.5,
		BABY_TRICERATOPS = 2,
		DODO = 0,
		PARASAUR = 10,
		STEGOSAURUS = 7,
		TRICERATOPS = 7.5,
		RAPTOR = 4,
	}
	local groundOffset = CORPSE_GROUND_OFFSETS[creatureId] or 2

	-- 지면 스냅 헬퍼 (최종 포즈 상태에서 호출)
	local function snapToGround()
		if not rootPart or not model or not model.Parent then return end
		-- 최종 포즈의 시각적 최하단 Y 계산 (투명 파트 제외)
		local lowestY = math.huge
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 0.9 then
				local bottomY = part.Position.Y - part.Size.Y / 2
				if bottomY < lowestY then lowestY = bottomY end
			end
		end
		if lowestY == math.huge then
			lowestY = rootPart.Position.Y - rootPart.Size.Y / 2
		end
		-- 모델/ResourceNodes 제외, 레이캐스트로 실제 지형 검색
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = {workspace.Terrain}
		local rayOrigin = Vector3.new(rootPart.Position.X, rootPart.Position.Y + 10, rootPart.Position.Z)
		local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -60, 0), rayParams)
		if rayResult then
			local groundY = rayResult.Position.Y
			-- 최하단보다 추가로 내려서 지면에 확실히 밀착
			local dropDist = (lowestY + groundOffset) - groundY
			if math.abs(dropDist) > 0.1 then
				rootPart.CFrame = rootPart.CFrame - Vector3.new(0, dropDist, 0)
			end
		end
	end

	-- ★ 위치 먼저 잡기: 지면 스냅 (애니메이션 전)
	snapToGround()

	-- 데스 애니메이션: 재생 → 프리즈
	if hasCollapsed and deathTrack then
		-- ★ 쓰러진 크리처: 이미 95%에서 프리즈 완료 → 포즈 반영 후 지면 재스냅만 수행
		task.wait(0.1) -- Motor6D 위치 반영 대기
		snapToGround()
	elseif deathTrack then
		task.spawn(function()
			-- Length가 비동기 로딩일 수 있으므로 0이면 대기
			local waited = 0
			while deathTrack.Length <= 0 and waited < 2 do
				task.wait(0.1)
				waited = waited + 0.1
			end
			local trackLength = deathTrack.Length

			-- Heartbeat 폴링으로 정확하게 95% 지점 감지
			if trackLength > 0 then
				local targetTime = trackLength * 0.95
				while deathTrack.IsPlaying and deathTrack.TimePosition < targetTime do
					task.wait()
				end
			else
				task.wait(2.0)
			end

			if not model or not model.Parent then return end
			if deathTrack.IsPlaying then
				deathTrack:AdjustSpeed(0) -- 마지막 프레임에서 프리즈
			end

			-- ★ 사망 애니메이션 완료 후 지면 재스냅 (포즈 변환 후 정확한 위치)
			task.wait(0.1) -- Motor6D 위치 반영 대기
			snapToGround()

			-- Humanoid 비활성화 (파괴하지 않아 포즈 유지)
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = 0
				humanoid.JumpPower = 0
				humanoid.PlatformStand = true
			end
		end)
	else
		-- 데스 애니메이션 없으면 앵커 + Humanoid 제거
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = true
				part.CanTouch = true
			end
		end
		if humanoid and humanoid.Parent then
			humanoid:Destroy()
		end
	end

	-- ★ 드롭 확률(weight) 적용: 각 자원을 확률 롤하여 실제 출현 자원 결정
	local resolvedResources = {}
	for _, res in ipairs(nodeData.resources or {}) do
		if math.random() <= (res.weight or 1.0) then
			local count = math.random(res.min or 1, res.max or 1)
			table.insert(resolvedResources, {
				itemId = res.itemId,
				count = count,      -- 이 자원에서 얻을 실제 수량
				min = res.min,
				max = res.max,
				weight = 1.0,       -- 이미 확률 통과
			})
		end
	end
	-- 최소 1개 보장 (아무것도 안 뜨면 첫 번째 자원 강제)
	if #resolvedResources == 0 and #(nodeData.resources or {}) > 0 then
		local fallback = nodeData.resources[1]
		table.insert(resolvedResources, {
			itemId = fallback.itemId,
			count = math.random(fallback.min or 1, fallback.max or 1),
			min = fallback.min,
			max = fallback.max,
			weight = 1.0,
		})
	end

	-- resolvedResources 기반으로 총 채집 횟수(=HP) 결정
	local totalGathers = 0
	for _, res in ipairs(resolvedResources) do
		totalGathers = totalGathers + res.count
	end

	-- 활성 노드 등록 (resolvedResources 포함)
	activeNodes[nodeUID] = {
		nodeId = nodeId,
		remainingHits = totalGathers,    -- 총 채집 횟수 = HP
		initialTotalGathers = totalGathers,
		depletedAt = nil,
		position = position,
		isAutoSpawned = false,
		nodeModel = model,
		nodeRoot = model,
		nodeOriginalParent = model.Parent,
		isCorpse = true,
		resolvedResources = resolvedResources,  -- 확률 적용 완료된 자원 목록
		resolvedMaxHealth = totalGathers,        -- 확률 적용 후 HP
		resolvedTotalGathers = totalGathers,
	}

	-- 클라이언트 알림
	if NetController then
		NetController.FireClientsInRange(position, 400, "Harvest.Node.Spawned", {
			nodeUID = nodeUID,
			nodeId = nodeId,
			position = position,
			maxHits = totalGathers,
		})
	end

	-- 시체 자동 디스폰: 마지막 n초간 깜빡임 후 제거
	task.delay(CORPSE_DESPAWN_TIME - CORPSE_BLINK_START, function()
		if not activeNodes[nodeUID] or not model or not model.Parent then return end

		-- 깜빡임 효과: 투명도를 토글하며 점점 빠르게
		local blinkParts = {}
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(blinkParts, { part = part, origTransparency = part.Transparency })
			end
		end

		local elapsed = 0
		local blinkOn = false
		while elapsed < CORPSE_BLINK_START do
			if not activeNodes[nodeUID] or not model or not model.Parent then return end
			-- 간격: 0.5초에서 시작 → 0.1초까지 점점 빠르게
			local progress = elapsed / CORPSE_BLINK_START
			local interval = 0.5 - 0.4 * progress  -- 0.5 → 0.1
			blinkOn = not blinkOn
			for _, info in ipairs(blinkParts) do
				if info.part and info.part.Parent then
					info.part.Transparency = blinkOn and math.min(info.origTransparency + 0.6, 1) or info.origTransparency
				end
			end
			task.wait(interval)
			elapsed = elapsed + interval
		end

		-- 디스폰
		if activeNodes[nodeUID] then
			HarvestService._destroyNodeModel(nodeUID)
			activeNodes[nodeUID] = nil
			if model and model.Parent then
				model:Destroy()
			end
		end
	end)

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

	-- ★ 도구 속성 효과 적용 (다중 속성 합산)
	if toolSlot and InventoryService then
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData and slotData.attributes then
			for attrId, level in pairs(slotData.attributes) do
				local fx = MaterialAttributeData.getEffectValues(attrId, level)
				if fx and fx.damageMult ~= 0 then
					power = power * (1 + fx.damageMult)
				end
			end
		end
	end
	power = math.max(1, power)
	
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
	nodeState.lastInteractedAt = tick()
	
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
		PlayerStatService.grantActionXP(sourceUserId, xpPerHit * actualDamage, {
			source = Enums.XPSource.HARVEST_RESOURCE,
			actionKey = "HIT:" .. tostring(nodeData.id or nodeState.nodeId or "NODE"),
		})
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
				
				WorldDropService.spawnDrop(finalDropPos, drop.itemId, drop.count, nil, nodeData.level)
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
				nodeRoot = nodeState.nodeRoot,
				nodeOriginalParent = nodeState.nodeOriginalParent,
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
	local nodeRoot = nodeState.nodeRoot
	
	-- 미리 배치된 모델이 없다면 (혹은 AutoSpawned 등) 폴더 스캔
	if not nodeModel then
		local nodeFolder = workspace:FindFirstChild("ResourceNodes")
		if nodeFolder then
			-- [수정] 하위 폴더까지 뒤져서 해당 UID를 가진 인스턴스 검색
			for _, inst in ipairs(nodeFolder:GetDescendants()) do
				if inst:GetAttribute("NodeUID") == nodeUID then
					nodeModel = getNodeSceneRoot(inst)
					nodeRoot = nodeModel
					break
				end
			end
		end
	end

	if not nodeRoot then
		nodeRoot = nodeModel
	end
	
	if nodeModel or nodeRoot then
		nodeState.nodeModel = nodeModel
		nodeState.nodeRoot = nodeRoot
		if nodeModel then
			nodeModel:SetAttribute("Depleted", true)
		end
		if nodeRoot and nodeRoot ~= nodeModel then
			nodeRoot:SetAttribute("Depleted", true)
		end

		-- 자동 스폰 노드만 실제 인스턴스를 제거하고 필요 시 새로 스폰한다.
		-- 워크스페이스에 미리 배치된 노드는 같은 인스턴스를 숨겼다가 제자리에서 복구해야 한다.
		if nodeState.isAutoSpawned then
			local destroyTarget = nodeRoot or nodeModel
			if destroyTarget and destroyTarget.Parent then
				destroyTarget:Destroy()
			end
			nodeState.nodeModel = nil
			nodeState.nodeRoot = nil
			return {}
		end
		
		-- 프리배치 노드/시체 노드는 삭제 대신 투명화 + 상호작용 비활성화 (리스폰시 원래 상태 복구)
		local targetRoot = nodeRoot or nodeModel
		for _, descendant in ipairs(targetRoot:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if descendant:GetAttribute("HarvestOriginalTransparency") == nil then
					descendant:SetAttribute("HarvestOriginalTransparency", descendant.Transparency)
				end
				if descendant:GetAttribute("HarvestOriginalCanCollide") == nil then
					descendant:SetAttribute("HarvestOriginalCanCollide", descendant.CanCollide)
				end
				if descendant:GetAttribute("HarvestOriginalCanQuery") == nil then
					descendant:SetAttribute("HarvestOriginalCanQuery", descendant.CanQuery)
				end
				if descendant:GetAttribute("HarvestOriginalCanTouch") == nil then
					descendant:SetAttribute("HarvestOriginalCanTouch", descendant.CanTouch)
				end
				
				if descendant.Name ~= "Hitbox" then
					descendant.Transparency = 1
				end
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				if descendant:GetAttribute("HarvestOriginalTransparency") == nil then
					descendant:SetAttribute("HarvestOriginalTransparency", descendant.Transparency)
				end
				descendant.Transparency = 1
			elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
				if descendant:GetAttribute("HarvestOriginalEnabled") == nil then
					descendant:SetAttribute("HarvestOriginalEnabled", descendant.Enabled)
				end
				descendant.Enabled = false
			elseif descendant:IsA("Highlight") then
				if descendant:GetAttribute("HarvestOriginalEnabled") == nil then
					descendant:SetAttribute("HarvestOriginalEnabled", descendant.Enabled)
				end
				descendant.Enabled = false
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
		local nodeRoot = depletedNode.nodeRoot or getNodeSceneRoot(nodeModel)
		depletedNode.nodeRoot = nodeRoot
		if nodeRoot and depletedNode.nodeOriginalParent and nodeRoot.Parent ~= depletedNode.nodeOriginalParent then
			local ok, err = pcall(function()
				nodeRoot.Parent = depletedNode.nodeOriginalParent
			end)
			if not ok then
				warn(string.format(
					"[HarvestService] Failed to restore depleted node root for %s (%s): %s",
					tostring(nodeUID),
					tostring(depletedNode.nodeId),
					tostring(err)
				))
				depletedNode.nodeModel = nil
				depletedNode.nodeRoot = nil
				nodeModel = nil
				nodeRoot = nil
			end
		end
		if nodeModel then
			nodeModel:SetAttribute("Depleted", false)
		end
		if nodeRoot and nodeRoot ~= nodeModel then
			nodeRoot:SetAttribute("Depleted", false)
		end
		local targetRoot = nodeRoot or nodeModel
		for _, descendant in ipairs((targetRoot and targetRoot:GetDescendants()) or {}) do
			if descendant:IsA("BasePart") then
				local originalTransparency = descendant:GetAttribute("HarvestOriginalTransparency")
				local originalCanCollide = descendant:GetAttribute("HarvestOriginalCanCollide")
				local originalCanQuery = descendant:GetAttribute("HarvestOriginalCanQuery")
				local originalCanTouch = descendant:GetAttribute("HarvestOriginalCanTouch")
				
				if typeof(originalTransparency) == "number" then
					descendant.Transparency = originalTransparency
				end
				if typeof(originalCanCollide) == "boolean" then
					descendant.CanCollide = originalCanCollide
				else
					descendant.CanCollide = false
				end
				if typeof(originalCanQuery) == "boolean" then
					descendant.CanQuery = originalCanQuery
				else
					descendant.CanQuery = true
				end
				if typeof(originalCanTouch) == "boolean" then
					descendant.CanTouch = originalCanTouch
				else
					descendant.CanTouch = true
				end
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				local originalTransparency = descendant:GetAttribute("HarvestOriginalTransparency")
				if typeof(originalTransparency) == "number" then
					descendant.Transparency = originalTransparency
				else
					descendant.Transparency = 0
				end
			elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
				local originalEnabled = descendant:GetAttribute("HarvestOriginalEnabled")
				if typeof(originalEnabled) == "boolean" then
					descendant.Enabled = originalEnabled
				else
					descendant.Enabled = true
				end
			elseif descendant:IsA("Highlight") then
				local originalEnabled = descendant:GetAttribute("HarvestOriginalEnabled")
				if typeof(originalEnabled) == "boolean" then
					descendant.Enabled = originalEnabled
				else
					descendant.Enabled = true
				end
			end
		end
	end

	if not depletedNode.nodeModel then
		-- 도저히 모델이 없으면 재생성 시도
		local newModel = HarvestService.spawnNodeModel(depletedNode.nodeId, depletedNode.position, nodeUID)
		depletedNode.nodeModel = newModel
		depletedNode.nodeRoot = getNodeSceneRoot(newModel)
	end
	
	activeNodes[nodeUID] = {
		nodeId = depletedNode.nodeId,
		position = depletedNode.position,
		remainingHits = nodeData.maxHealth, -- 다시 maxHealth 풀로
		depletedAt = nil,
		respawnAt = nil,
		isAutoSpawned = depletedNode.isAutoSpawned,
		nodeModel = depletedNode.nodeModel,
		nodeRoot = depletedNode.nodeRoot,
		nodeOriginalParent = depletedNode.nodeOriginalParent,
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

getNodeSceneRoot = function(nodeInstance: Instance?): Instance?
	if not nodeInstance then
		return nil
	end

	if nodeInstance:IsA("Model") then
		return nodeInstance
	end

	return nodeInstance:FindFirstAncestorOfClass("Model") or nodeInstance
end

applyNodeIdentity = function(nodeInstance: Instance?, nodeId: string, nodeUID: string, depleted: boolean)
	if not nodeInstance then
		return
	end

	nodeInstance:SetAttribute("NodeId", nodeId)
	nodeInstance:SetAttribute("NodeUID", nodeUID)
	nodeInstance:SetAttribute("Depleted", depleted)
	nodeInstance:SetAttribute("ResourceNode", true)
	CollectionService:AddTag(nodeInstance, "ResourceNode")
end

ensureHiddenNodeFolder = function(): Folder
	local folder = ServerStorage:FindFirstChild("HarvestHiddenNodes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "HarvestHiddenNodes"
		folder.Parent = ServerStorage
	end
	return folder
end

--- workspace.ResourceNodes 내 카테고리 폴더에서 템플릿 Clone 캐시
--- _setupPrePlacedNodes 전에 호출하여 순수 원본 보존
function HarvestService._cacheTemplatesFromFolders()
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then return end

	-- 폴더 이름 → nodeId 해석 헬퍼
	local resourceTable = DataService and DataService.get("ResourceNodeData") or {}
	local function resolveToNodeId(name)
		-- 1) 정확 매칭
		if DataService and DataService.getResourceNode(name) then
			return name
		end
		-- 2) 정규화 매칭 + 부분 포함
		local norm = tostring(name):lower():gsub("[%s_%-]", "")
		for nodeId, nodeData in pairs(resourceTable) do
			local nodeIdNorm = tostring(nodeId):lower():gsub("[%s_%-]", "")
			local modelNameNorm = tostring(nodeData.modelName or ""):lower():gsub("[%s_%-]", "")
			if norm == nodeIdNorm or norm == modelNameNorm then
				return nodeId
			end
		end
		-- 3) 부분 포함 (BRANCH → GROUND_BRANCH)
		for nodeId, nodeData in pairs(resourceTable) do
			local nodeIdNorm = tostring(nodeId):lower():gsub("[%s_%-]", "")
			local modelNameNorm = tostring(nodeData.modelName or ""):lower():gsub("[%s_%-]", "")
			if #norm >= 3 and (nodeIdNorm:find(norm, 1, true) or modelNameNorm:find(norm, 1, true)) then
				return nodeId
			end
		end
		return nil
	end

	local cached = 0
	-- GetDescendants로 2단계 이상 하위 폴더(GRASSLAND/TREE_THIN 등)도 탐색
	-- ★ Folder뿐 아니라 Model 컨테이너도 탐색 (FARM_TREE가 Model로 배치된 경우 대응)
	for _, child in ipairs(nodeFolder:GetDescendants()) do
		if child:IsA("Folder") then
			local folderTemplate = nil
			local folderChildren = child:GetChildren()
			if #folderChildren == 1 and (folderChildren[1]:IsA("Model") or folderChildren[1]:IsA("BasePart")) then
				folderTemplate = folderChildren[1]:Clone()
			elseif #folderChildren > 0 then
				folderTemplate = Instance.new("Model")
				folderTemplate.Name = child.Name
				for attrName, attrValue in pairs(child:GetAttributes()) do
					folderTemplate:SetAttribute(attrName, attrValue)
				end
				for _, folderChild in ipairs(folderChildren) do
					folderChild:Clone().Parent = folderTemplate
				end
			end
			if folderTemplate then
				local resolvedId = resolveToNodeId(child.Name) or child.Name
				if not templateCache[resolvedId] then
					folderTemplate.Parent = nil
					templateCache[resolvedId] = folderTemplate
					cached = cached + 1
				end
			end
		elseif child:IsA("Model") and child:FindFirstChildWhichIsA("Model") then
			local firstModel = child:FindFirstChildWhichIsA("Model")
			if firstModel then
				local resolvedId = resolveToNodeId(child.Name) or child.Name
				if not templateCache[resolvedId] then
					local clone = firstModel:Clone()
					clone.Parent = nil
					templateCache[resolvedId] = clone
					cached = cached + 1
				end
			end
		end
	end
	
	if cached > 0 then
		print(string.format("[HarvestService] Cached %d model templates from ResourceNodes folders", cached))
	end
end

--- 맵에 미리 배치된 노드(ResourceNodes 폴더 안)를 태깅/활성화
function HarvestService._setupPrePlacedNodes()
	local nodeFolder = ensureResourceNodesFolder()
	local count = 0
	local unmappedCount = 0
	local unmappedSamples = {}
	local processedRoots = {}

	local function getTopLevelNodeRoot(inst: Instance): Model?
		if not inst then
			return nil
		end

		local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
		if not model then
			return nil
		end

		local current = model
		while current do
			local parent = current.Parent
			if not parent or parent == nodeFolder then
				break
			end
			if parent:IsA("Model") then
				current = parent
			else
				break
			end
		end
		return current
	end

	local function normalizeNodeName(name)
		return tostring(name or ""):lower():gsub("[%s_%-]", "")
	end

	local function resolveNodeId(nodeModel)
		if not nodeModel then
			return nil, nil
		end

		-- [수정] GROUND_STONE은 더 이상 스폰되지 않아야 하므로 블랙리스트 처리 (확장 매칭 대응)
		local nameNorm = normalizeNodeName(nodeModel.Name)
		if nameNorm == "groundstone" or nameNorm == "smallstone" or nameNorm == "stone" then
			return nil, nil
		end

		local candidates = { nodeModel.Name }
		-- ★ 부모/조부모 이름도 후보에 포함 (Folder뿐 아니라 Model 컨테이너도 대응)
		local parent = nodeModel.Parent
		if parent and parent.Name ~= "ResourceNodes" then
			table.insert(candidates, parent.Name)
			-- 조부모도 체크 (ResourceNodes/TROPICAL/FARM_TREE/모델 구조 대응)
			local grandparent = parent.Parent
			if grandparent and grandparent.Name ~= "ResourceNodes" then
				table.insert(candidates, grandparent.Name)
			end
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
		-- Pass 2: 정규화 완전 일치
		for nodeId, nodeData in pairs(resourceTable) do
			local nodeIdNorm = normalizeNodeName(nodeId)
			local modelNameNorm = normalizeNodeName(nodeData.modelName)
			for candidateNorm in pairs(normalizedCandidates) do
				if candidateNorm == nodeIdNorm or candidateNorm == modelNameNorm then
					return nodeId, nodeData
				end
			end
		end

		-- Pass 3: 부분 포함 매칭 (BRANCH → GROUND_BRANCH, STONE → GROUND_STONE 등)
		for nodeId, nodeData in pairs(resourceTable) do
			local nodeIdNorm = normalizeNodeName(nodeId)
			local modelNameNorm = normalizeNodeName(nodeData.modelName)
			for candidateNorm in pairs(normalizedCandidates) do
				if #candidateNorm >= 3 and (nodeIdNorm:find(candidateNorm, 1, true) or modelNameNorm:find(candidateNorm, 1, true)) then
					return nodeId, nodeData
				end
			end
		end

		return nil, nil
	end
	
	-- [수정] GetChildren 대신 GetDescendants를 사용하여 하위 폴더(TREE_THIN 등) 안의 모델도 모두 등록
	for _, nodeModel in ipairs(nodeFolder:GetDescendants()) do
		if nodeModel:IsA("Model") then
			local sceneRoot = getTopLevelNodeRoot(nodeModel)
			if not sceneRoot or processedRoots[sceneRoot] then
				continue
			end
			processedRoots[sceneRoot] = true

			local nodeId, nodeData = resolveNodeId(sceneRoot)
			
			if nodeData then
				local primaryPart = sceneRoot.PrimaryPart or sceneRoot:FindFirstChildWhichIsA("BasePart", true)
				if primaryPart then
					-- [수정] 미리 배치된 모델도 셋업 로직을 거치게 함 (히트박스, 태그, 앵커링 등)
					setupModelForNode(sceneRoot, primaryPart.Position, nodeData, false)
					
					-- 등록 진행 (수동 배치 노드는 isAutoSpawned = false)
					local uid = HarvestService.registerNode(nodeId, primaryPart.Position, false)
					local nodeRoot = sceneRoot
					
					-- ActiveNode의 모델 포인터 설정
					if activeNodes[uid] then
						activeNodes[uid].nodeModel = sceneRoot
						activeNodes[uid].nodeRoot = nodeRoot
						activeNodes[uid].nodeOriginalParent = nodeRoot and nodeRoot.Parent or sceneRoot.Parent
					end
					
					-- 속성 설정 (래퍼 루트까지 동일하게 부여)
					applyNodeIdentity(sceneRoot, nodeId, uid, false)
					
					count = count + 1
				end
			else
				local isExplicitResourceNode = sceneRoot:GetAttribute("ResourceNode") == true
					or sceneRoot:GetAttribute("NodeId") ~= nil
				if isExplicitResourceNode then
					unmappedCount += 1
					if #unmappedSamples < 5 then
						table.insert(unmappedSamples, sceneRoot.Name)
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
		HarvestService._cacheTemplatesFromFolders()
		HarvestService._setupPrePlacedNodes()

		-- 일반 자원 노드는 워크스페이스 선행 배치만 사용한다.
		-- 자동 스폰은 잔돌/나뭇가지/섬유 등 바닥 자원만 별도 루프에서 보충한다.
		local hubZone = SpawnConfig.HUB_ZONE or "GRASSLAND"
		spawnedZones[hubZone] = true
	end)
	
	-- [수정] 자동스폰 루프 (등록된 섬에서만)
	if SpawnConfig.IsContentPlace() then
		task.spawn(function()
			while true do
				task.wait(NODE_SPAWN_INTERVAL)
				HarvestService._spawnLoop()
				end
		end)
	else
		warn("[HarvestService] 미등록 PlaceId — 자원 노드 자동 스폰 비활성화")
	end

	-- 디스폰 체크 (플레이어와 너무 멀면 제거하여 성능 확보)
	task.spawn(function()
		while true do
			task.wait(NODE_SPAWN_INTERVAL * 2)
			HarvestService._despawnCheck()
		end
	end)

	-- activeGathers 타임아웃 정리 (60초 초과 시 만료 제거)
	task.spawn(function()
		while true do
			task.wait(30)
			local now = tick()
			for key, state in pairs(activeGathers) do
				if now - state.startTime > 60 then
					activeGathers[key] = nil
				end
			end
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
		-- 복합 키(userId_itemId) 기반 activeGathers 정리
		local prefix = tostring(player.UserId) .. "_"
		for key, _ in pairs(activeGathers) do
			if string.sub(key, 1, #prefix) == prefix then
				activeGathers[key] = nil
			end
		end
	end)

	print("[HarvestService] Initialized — PRE-PLACED + AUTO-SPAWN MIXED system")
end

--- 레거시 호환용: 일반 자원 초기 대량 스폰은 더 이상 사용하지 않는다.
function HarvestService._initialSpawn()
	local hubZone = SpawnConfig.HUB_ZONE or "GRASSLAND"
	spawnedZones[hubZone] = true
end

--- 레거시 호환용: 일반 자원 Zone 스폰은 더 이상 사용하지 않는다.
function HarvestService.SpawnZone(zoneName)
	if not zoneName or spawnedZones[zoneName] then
		return
	end
	spawnedZones[zoneName] = true
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
	
		-- [수정] 그룹화 기반 보충 로직
	local players = Players:GetPlayers()
	local spawnRepresentativeParts = {}
	local GROUP_RADIUS = 120
	
	for _, player in ipairs(players) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local isNearGroup = false
			for _, repPart in ipairs(spawnRepresentativeParts) do
				if (hrp.Position - repPart.Position).Magnitude < GROUP_RADIUS then
					isNearGroup = true
					break
				end
			end
			if not isNearGroup then
				table.insert(spawnRepresentativeParts, hrp)
			end
		end
	end
	
	for _, repHRP in ipairs(spawnRepresentativeParts) do
		if toSpawn <= 0 then break end
		
		local pos, material = HarvestService._findSpawnPosition(repHRP)
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

--========================================
-- R키 채집 시스템: Gather Handlers
--========================================

--- 채집 시간 계산 (서버 권위)
local GATHER_TIME_OPTIMAL = 3   -- 최적 도구
local GATHER_TIME_WRONG   = 15  -- 부적합 도구
local GATHER_TIME_BARE    = 30  -- 맨손

local function calculateGatherTime(player: Player, nodeData: any): number
	local toolType = getToolType(player, nil)
	local optimal = nodeData.optimalTool

	local baseTime = GATHER_TIME_BARE -- 맨손 기본

	if not optimal or optimal == "" then
		-- 도구 불필요 노드 (나뭇가지, 잔돌 등)
		baseTime = GATHER_TIME_OPTIMAL
	elseif toolType and isCompatible(toolType, optimal) then
		baseTime = GATHER_TIME_OPTIMAL
	elseif toolType then
		baseTime = GATHER_TIME_WRONG
	end

	-- Work Speed 보너스 (스탯 1포인트당 고정 시간 차감)
	if PlayerStatService then
		local stats = PlayerStatService.getStats(player.UserId)
		local workSpeedPoints = (stats and stats.statInvested and stats.statInvested[Enums.StatId.WORK_SPEED]) or 0
		
		-- 최종 시간 = 기본 시간 - (투자 포인트 * 포인트당 단축 시간)
		local reduction = workSpeedPoints * (Balance.WORKSPEED_REDUCTION_PER_POINT or 0.05)
		baseTime = math.max(0.2, baseTime - reduction) -- 최소 0.2초 캡
	end

	return baseTime
end

--- Harvest.Gather.Request: 채집 시작 (클라이언트가 슬롯 클릭 시)
local function handleGatherRequest(player: Player, payload: any)
	local nodeUID = payload.nodeUID
	local itemId = payload.itemId
	local userId = player.UserId

	if not nodeUID or not itemId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- 노드 존재 확인
	local nodeState = activeNodes[nodeUID]
	if not nodeState then
		return { success = false, errorCode = Enums.ErrorCode.NODE_NOT_FOUND }
	end

	-- 노드 데이터
	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	-- 거리 검증
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p1 = Vector2.new(hrp.Position.X, hrp.Position.Z)
			local p2 = Vector2.new(nodeState.position.X, nodeState.position.Z)
			local distance = (p1 - p2).Magnitude
			local maxRange = (Balance.HARVEST_RANGE or 25) + 10
			if distance > maxRange then
				return { success = false, errorCode = Enums.ErrorCode.OUT_OF_RANGE }
			end
		end
	end

	-- 해당 아이템이 이 노드의 resources에 있는지 확인 (resolvedResources 우선)
	local resList = nodeState.resolvedResources or nodeData.resources
	local foundResource = nil
	for _, resource in ipairs(resList) do
		if resource.itemId == itemId then
			foundResource = resource
			break
		end
	end
	if not foundResource then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- ★ resolvedResources의 남은 수량이 0이면 채집 불가 (중복 채집 방지)
	if nodeState.resolvedResources and foundResource.count <= 0 then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- 복합 키 (같은 유저+같은 아이템 진행 중이면 자동 취소)
	local gatherKey = tostring(userId) .. "_" .. itemId
	if activeGathers[gatherKey] then
		activeGathers[gatherKey] = nil
	end

	-- 채집 시간 계산
	local gatherTime = calculateGatherTime(player, nodeData)

	-- 1클릭 = 1개 (이미 확률 적용된 resolvedResources면 항상 1개, 일반 노드는 weight 확률)
	local count = 0
	if nodeState.resolvedResources then
		-- 확률은 등록 시 이미 적용됨
		count = 1
	else
		if math.random() <= (foundResource.weight or 1.0) then
			count = 1
		end
	end

	-- 진행 중 상태 저장
	activeGathers[gatherKey] = {
		nodeUID = nodeUID,
		itemId = itemId,
		startTime = tick(),
		gatherTime = gatherTime,
		count = count,
	}

	-- 남은 채집 가능 횟수 계산 (resolvedResources 우선)
	local reqResList = nodeState.resolvedResources or nodeData.resources or {}
	local reqEffectiveMaxHealth = nodeState.resolvedMaxHealth or nodeData.maxHealth or 50
	local totalMaxGathers = nodeState.initialTotalGathers or getInitialGatherTotal(nodeState, nodeData)
	local damagePerGather = calculateDamagePerGather(reqEffectiveMaxHealth, totalMaxGathers)
	local remainingGathers = calculateRemainingGatherCount(nodeState.remainingHits, damagePerGather)

	return {
		success = true,
		data = {
			gatherTime = gatherTime,
			count = count,
			itemId = itemId,
			remainingGathers = remainingGathers,
		}
	}
end

--- Harvest.Gather.Complete: 채집 완료 (클라이언트가 진행바 끝나면 호출)
local function handleGatherComplete(player: Player, payload: any)
	local nodeUID = payload.nodeUID
	local itemId = payload.itemId
	local userId = player.UserId

	if not nodeUID or not itemId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- 진행 중인 채집 확인 (복합 키)
	local gatherKey = tostring(userId) .. "_" .. itemId
	local gatherState = activeGathers[gatherKey]
	if not gatherState then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	-- 일치 확인
	if gatherState.nodeUID ~= nodeUID or gatherState.itemId ~= itemId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- 시간 검증 (서버 기준 채집 시간의 90% 이상 경과해야 유효 — 안티치트)
	local elapsed = tick() - gatherState.startTime
	if elapsed < gatherState.gatherTime * 0.9 then
		return { success = false, errorCode = Enums.ErrorCode.COOLDOWN }
	end

	-- 노드 존재 재확인
	local nodeState = activeNodes[nodeUID]
	if not nodeState then
		activeGathers[gatherKey] = nil
		return { success = false, errorCode = Enums.ErrorCode.NODE_NOT_FOUND }
	end

	local nodeData = DataService.getResourceNode(nodeState.nodeId)

	-- 진행 상태 제거
	local count = gatherState.count
	activeGathers[gatherKey] = nil

	-- count가 0이면 (확률 실패) 아이템은 없지만 HP는 감소시켜야 함 (노드 정상 고갈)
	if count <= 0 then
		-- HP 감소 (weight 실패해도 채집 시도는 소모)
		local zeroEffMaxHP = nodeState.resolvedMaxHealth or (nodeData and nodeData.maxHealth) or 50
		local zeroTotalMax = nodeState.initialTotalGathers or getInitialGatherTotal(nodeState, nodeData)
		local zeroDmgPerGather = calculateDamagePerGather(zeroEffMaxHP, zeroTotalMax)
		nodeState.remainingHits = math.max(0, nodeState.remainingHits - zeroDmgPerGather)

		-- 고갈 시 노드 제거
		if nodeState.remainingHits <= 0 then
			HarvestService._destroyNodeModel(nodeUID)
			if nodeState.isCorpse then
				local nodeModel = nodeState.nodeModel
				activeNodes[nodeUID] = nil
				if nodeModel and nodeModel.Parent then
					nodeModel:Destroy()
				end
			elseif nodeState.isAutoSpawned then
				local nodeId2 = nodeState.nodeId
				spawnedNodesByType[nodeId2] = math.max(0, (spawnedNodesByType[nodeId2] or 0) - 1)
				spawnedNodeCount = math.max(0, spawnedNodeCount - 1)
				activeNodes[nodeUID] = nil
			else
				depletedNodes[nodeUID] = {
					nodeId = nodeState.nodeId,
					position = nodeState.position,
					respawnAt = os.time() + (nodeData.respawnTime or 300),
					isAutoSpawned = nodeState.isAutoSpawned,
					nodeModel = nodeState.nodeModel,
					nodeRoot = nodeState.nodeRoot,
					nodeOriginalParent = nodeState.nodeOriginalParent,
				}
				activeNodes[nodeUID] = nil
				task.delay(nodeData.respawnTime or 300, function()
					HarvestService._respawnNode(nodeUID)
				end)
			end
		end

		return { success = true, data = { itemId = itemId, count = 0 } }
	end

	-- ★ resolvedResources 수량 차감 (중복 채집 방지)
	if nodeState.resolvedResources then
		for _, res in ipairs(nodeState.resolvedResources) do
			if res.itemId == itemId then
				res.count = math.max(0, res.count - count)
				break
			end
		end
	end

	-- 인벤토리에 직접 추가 (재료 속성 롤링 포함)
	local inventoryFull = false
	if InventoryService then
		local sourceLevel = nodeData and nodeData.level or 1
		local rolledAttr, rolledLv = MaterialAttributeData.rollAttribute(itemId, sourceLevel)
		local attributes = nil
		if rolledAttr and rolledLv then
			attributes = { [rolledAttr] = rolledLv }
		end
		local added, remaining = InventoryService.addItem(userId, itemId, count, nil, attributes)
		if remaining > 0 then
			inventoryFull = true
			-- 남은 아이템은 월드 드롭으로 발 밑에 생성 (유실 방지)
			if WorldDropService then
				local character = player.Character
				local dropPos = character and character:FindFirstChild("HumanoidRootPart")
					and character.HumanoidRootPart.Position + Vector3.new(0, 2, 0)
					or nodeState.position
				WorldDropService.spawnDrop(dropPos, itemId, remaining, nil, sourceLevel)
			end
		end
	end

	-- XP 보상
	if nodeData and PlayerStatService then
		local xpPerHit = nodeData.xpPerHit or 2
		PlayerStatService.grantActionXP(userId, xpPerHit * count, {
			source = Enums.XPSource.HARVEST_RESOURCE,
			actionKey = "GATHER:" .. tostring(nodeData.id or nodeState.nodeId or "NODE"),
		})
	end

	-- 배고픔 소모
	local HSuccess, HungerService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
	if HSuccess and HungerService then
		HungerService.consumeHunger(userId, (Balance.HUNGER_HARVEST_COST or 0.5) * 3)
	end

	-- 퀘스트 콜백
	if questCallback and nodeData then
		questCallback(userId, nodeData.nodeType or nodeData.id)
	end

	-- 노드 내구도 감소 (resolvedResources 우선)
	local complEffMaxHP = nodeState.resolvedMaxHealth or (nodeData and nodeData.maxHealth) or 50
	local totalMaxGathers = nodeState.initialTotalGathers or getInitialGatherTotal(nodeState, nodeData)
	local damagePerGather = calculateDamagePerGather(complEffMaxHP, totalMaxGathers)
	nodeState.remainingHits = math.max(0, nodeState.remainingHits - damagePerGather)

	-- 남은 채집 가능 횟수 응답에 포함
	local remainingGathers = calculateRemainingGatherCount(nodeState.remainingHits, damagePerGather)

	-- HP 브로드캐스트
	if NetController then
		NetController.FireClientsInRange(nodeState.position, 400, "Harvest.Node.Hit", {
			nodeUID = nodeUID,
			remainingHits = nodeState.remainingHits,
			maxHits = complEffMaxHP,
		})
	end

	-- 고갈 시 노드 제거 (월드 드롭 없이)
	if nodeState.remainingHits <= 0 then
		HarvestService._destroyNodeModel(nodeUID)

		if nodeState.isCorpse then
			-- 시체 노드: 리스폰 없이 즉시 완전 제거
			local nodeModel = nodeState.nodeModel
			activeNodes[nodeUID] = nil
			if nodeModel and nodeModel.Parent then
				nodeModel:Destroy()
			end
		elseif nodeState.isAutoSpawned then
			local nodeId2 = nodeState.nodeId
			spawnedNodesByType[nodeId2] = math.max(0, (spawnedNodesByType[nodeId2] or 0) - 1)
			spawnedNodeCount = math.max(0, spawnedNodeCount - 1)
			activeNodes[nodeUID] = nil
		else
			depletedNodes[nodeUID] = {
				nodeId = nodeState.nodeId,
				position = nodeState.position,
				respawnAt = os.time() + (nodeData.respawnTime or 300),
				isAutoSpawned = nodeState.isAutoSpawned,
				nodeModel = nodeState.nodeModel,
				nodeRoot = nodeState.nodeRoot,
				nodeOriginalParent = nodeState.nodeOriginalParent,
			}
			activeNodes[nodeUID] = nil
			task.delay(nodeData.respawnTime or 300, function()
				HarvestService._respawnNode(nodeUID)
			end)
		end
	end

	return { success = true, data = { itemId = itemId, count = count, remainingGathers = remainingGathers, inventoryFull = inventoryFull } }
end

--- Harvest.Gather.Info: 노드의 아이템별 채집 가능 횟수 반환
local function handleGatherInfo(player: Player, payload: any)
	local nodeUID = payload.nodeUID
	if not nodeUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	local nodeState = activeNodes[nodeUID]
	if not nodeState then
		return { success = false, errorCode = Enums.ErrorCode.NODE_NOT_FOUND }
	end

	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	-- 아이템별 채집 가능 횟수 계산
	-- resolvedResources가 있으면 실제 남은 수량을 그대로 보여준다.
	local resList = nodeState.resolvedResources or nodeData.resources or {}
	local resourceCounts = {}
	local remainingTotal = 0

	if nodeState.resolvedResources then
		for _, res in ipairs(resList) do
			local count = math.max(0, tonumber(res.count) or 0)
			resourceCounts[res.itemId] = count
			remainingTotal = remainingTotal + count
		end
	else
		local effectiveMaxHealth = nodeData.maxHealth or 50
		local totalMaxGathers = nodeState.initialTotalGathers or getInitialGatherTotal(nodeState, nodeData)
		local damagePerGather = calculateDamagePerGather(effectiveMaxHealth, totalMaxGathers)
		remainingTotal = calculateRemainingGatherCount(nodeState.remainingHits, damagePerGather)

		local distributed = 0
		for i, res in ipairs(resList) do
			local resMax = res.max or res.count or 1
			local ratio = resMax / math.max(1, totalMaxGathers)
			local count = math.max(0, math.floor(remainingTotal * ratio))
			resourceCounts[res.itemId] = count
			distributed = distributed + count
		end

		local deficit = remainingTotal - distributed
		if deficit > 0 then
			local sortedIdx = {}
			for i, res in ipairs(resList) do
				table.insert(sortedIdx, { idx = i, maxVal = res.max or res.count or 1 })
			end
			table.sort(sortedIdx, function(a, b) return a.maxVal > b.maxVal end)
			for _, entry in ipairs(sortedIdx) do
				if deficit <= 0 then break end
				local res = resList[entry.idx]
				resourceCounts[res.itemId] = (resourceCounts[res.itemId] or 0) + 1
				deficit = deficit - 1
			end
		end
	end

	return {
		success = true,
		data = {
			remaining = resourceCounts,
			remainingTotal = remainingTotal,
			gatherTime = calculateGatherTime(player, nodeData),
		}
	}
end

function HarvestService.GetHandlers()
	return {
		["Harvest.Hit.Request"] = handleHitRequest,
		["Harvest.GetNodes.Request"] = handleGetNodesRequest,
		["Harvest.Gather.Request"] = handleGatherRequest,
		["Harvest.Gather.Complete"] = handleGatherComplete,
		["Harvest.Gather.Info"] = handleGatherInfo,
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function HarvestService.SetQuestCallback(callback)
	questCallback = callback
end

return HarvestService
