local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local BlockBuildService = {}

local initialized = false
local NetController = nil
local DataService = nil
local InventoryService = nil
local SaveService = nil
local PlayerStatService = nil
local DurabilityService = nil
local BaseClaimService = nil
local TotemService = nil
local WorldDropService = nil
local questCallback = nil

local blocksFolder = nil
local blocks = {}
local cellToBlockId = {}
local blockCount = 0

local GRID_SIZE = Balance.BLOCK_GRID_SIZE or 4
local BLOCK_CAP = Balance.BLOCK_STRUCTURE_CAP or 3000
local BLOCK_RANGE = Balance.BLOCK_BUILD_RANGE or 35

local function ensureBlocksFolder(): Folder
	local folder = workspace:FindFirstChild("BlockStructures")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BlockStructures"
		folder.Parent = workspace
	end
	return folder
end

local function makeBlockId(): string
	return "block_" .. HttpService:GenerateGUID(false)
end

local function makeCellKey(x: number, y: number, z: number): string
	return string.format("%d:%d:%d", x, y, z)
end

local function cellHasAnyBlock(key: string): boolean
	local v = cellToBlockId[key]
	if v == nil then
		return false
	end
	if type(v) == "string" then
		return true
	end
	if type(v) == "table" then
		return #v > 0
	end
	return false
end

local function appendBlockIdToCell(key: string, blockId: string)
	if not cellToBlockId[key] then
		cellToBlockId[key] = { blockId }
		return
	end
	if type(cellToBlockId[key]) == "string" then
		cellToBlockId[key] = { cellToBlockId[key], blockId }
		return
	end
	table.insert(cellToBlockId[key], blockId)
end

local function removeBlockIdFromCell(key: string, blockId: string)
	local v = cellToBlockId[key]
	if not v then
		return
	end
	if type(v) == "string" then
		if v == blockId then
			cellToBlockId[key] = nil
		end
		return
	end
	for i = #v, 1, -1 do
		if v[i] == blockId then
			table.remove(v, i)
		end
	end
	if #v == 0 then
		cellToBlockId[key] = nil
	end
end

local function parseCell(cell: any): (number?, number?, number?)
	if typeof(cell) == "Vector3" then
		return math.floor(cell.X), math.floor(cell.Y), math.floor(cell.Z)
	end
	if typeof(cell) == "Vector3int16" then
		return cell.X, cell.Y, cell.Z
	end
	if type(cell) ~= "table" then
		return nil, nil, nil
	end

	local x = tonumber(cell.x or cell.X)
	local y = tonumber(cell.y or cell.Y)
	local z = tonumber(cell.z or cell.Z)
	if not x or not y or not z then
		return nil, nil, nil
	end

	return math.floor(x), math.floor(y), math.floor(z)
end

local function parsePosition(rawPosition: any): Vector3?
	if typeof(rawPosition) == "Vector3" then
		return rawPosition
	end
	if type(rawPosition) ~= "table" then
		return nil
	end

	local x = tonumber(rawPosition.x or rawPosition.X)
	local y = tonumber(rawPosition.y or rawPosition.Y)
	local z = tonumber(rawPosition.z or rawPosition.Z)
	if x == nil or y == nil or z == nil then
		return nil
	end

	return Vector3.new(x, y, z)
end

local function cellToWorld(x: number, y: number, z: number): Vector3
	return Vector3.new(
		(x + 0.5) * GRID_SIZE,
		(y + 0.5) * GRID_SIZE,
		(z + 0.5) * GRID_SIZE
	)
end

local function getBlockData(blockTypeId: string): any?
	local data = DataService and DataService.getFacility(blockTypeId)
	if data and data.buildMode == "BLOCK" then
		return data
	end
	return nil
end

local function getActiveItemData(userId: number): (any?, any?, number)
	if not InventoryService then
		return nil, nil, 1
	end

	local activeSlot = InventoryService.getActiveSlot(userId) or 1
	local slotData = InventoryService.getSlot(userId, activeSlot)
	local itemData = slotData and DataService and DataService.getItem and DataService.getItem(slotData.itemId) or nil
	return slotData, itemData, activeSlot
end

local function canBreakBlocksWithItem(itemData: any): boolean
	if type(itemData) ~= "table" then
		return false
	end

	local itemType = tostring(itemData.type or "")
	if itemType == "TOOL" then
		return true
	end
	if itemType ~= "WEAPON" then
		return false
	end

	local toolKind = string.upper(tostring(itemData.optimalTool or ""))
	return toolKind ~= "BOW" and toolKind ~= "CROSSBOW"
end

local function scatterDropPosition(basePos: Vector3, index: number): Vector3
	local angle = (index * 2.39996323) % (math.pi * 2)
	local radius = 1.1 + ((index % 3) * 0.45)
	return basePos + Vector3.new(math.cos(angle) * radius, 2, math.sin(angle) * radius)
end

local function spawnBlockPart(block: any)
	local blockData = getBlockData(block.blockTypeId)
	if not blockData then
		return nil
	end

	local part = Instance.new("Part")
	part.Name = block.id
	part.Size = Vector3.new(GRID_SIZE, GRID_SIZE, GRID_SIZE)
	part.CFrame = CFrame.new(block.position)
	part.Anchored = true
	part.Material = blockData.blockMaterial or Enum.Material.SmoothPlastic
	part.Color = blockData.blockColor or Color3.fromRGB(160, 160, 160)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = blocksFolder

	part:SetAttribute("BlockId", block.id)
	part:SetAttribute("BlockTypeId", block.blockTypeId)
	part:SetAttribute("OwnerId", block.ownerId)
	part:SetAttribute("Health", block.health)
	part:SetAttribute("CellX", block.cell.x)
	part:SetAttribute("CellY", block.cell.y)
	part:SetAttribute("CellZ", block.cell.z)
	part:SetAttribute("PosX", block.position.X)
	part:SetAttribute("PosY", block.position.Y)
	part:SetAttribute("PosZ", block.position.Z)

	block.instance = part
	return part
end

local function isGroundSupportValid(position: Vector3): boolean
	local bottomY = position.Y - (GRID_SIZE * 0.5)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { blocksFolder }

	local origin = position + Vector3.new(0, GRID_SIZE * 2, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -(GRID_SIZE * 4), 0), params)
	if not result or not result.Instance then
		return false
	end

	if result.Material == Enum.Material.Water then
		return false
	end

	local foldersToReject = {
		workspace:FindFirstChild("Facilities"),
		workspace:FindFirstChild("ResourceNodes"),
		workspace:FindFirstChild("NPCs"),
		workspace:FindFirstChild("Creatures"),
		workspace:FindFirstChild("Characters"),
	}

	for _, folder in ipairs(foldersToReject) do
		if folder and result.Instance:IsDescendantOf(folder) then
			return false
		end
	end

	local model = result.Instance:FindFirstAncestorWhichIsA("Model")
	if model and (model:GetAttribute("StructureId") or model:GetAttribute("NodeId") or model:GetAttribute("NPCId")) then
		return false
	end

	return math.abs(bottomY - result.Position.Y) <= math.max(1.1, GRID_SIZE * 0.75)
end

local NEIGHBOR_OFFSETS = {
	{ x = 1, y = 0, z = 0 },
	{ x = -1, y = 0, z = 0 },
	{ x = 0, y = 1, z = 0 },
	{ x = 0, y = -1, z = 0 },
	{ x = 0, y = 0, z = 1 },
	{ x = 0, y = 0, z = -1 },
}

local function hasAdjacentSupport(x: number, y: number, z: number): boolean
	for _, offset in ipairs(NEIGHBOR_OFFSETS) do
		local key = makeCellKey(x + offset.x, y + offset.y, z + offset.z)
		if cellHasAnyBlock(key) then
			return true
		end
	end
	return false
end

local function saveBlock(block: any)
	if not SaveService then
		return
	end

	SaveService.updateWorldState(function(state)
		state.blockStructures = type(state.blockStructures) == "table" and state.blockStructures or {}
		state.blockStructures[block.id] = {
			id = block.id,
			blockTypeId = block.blockTypeId,
			ownerId = block.ownerId,
			health = block.health,
			placedAt = block.placedAt,
			position = {
				x = block.position.X,
				y = block.position.Y,
				z = block.position.Z,
			},
			cell = {
				x = block.cell.x,
				y = block.cell.y,
				z = block.cell.z,
			},
		}
		return state
	end)
end

local function deleteSavedBlock(blockId: string)
	if not SaveService then
		return
	end

	SaveService.updateWorldState(function(state)
		if type(state.blockStructures) == "table" then
			state.blockStructures[blockId] = nil
		end
		return state
	end)
end

local function loadBlockRecord(rawBlock: any)
	if type(rawBlock) ~= "table" or type(rawBlock.id) ~= "string" then
		return
	end

	local x, y, z = parseCell(rawBlock.cell)
	if x == nil then
		return
	end

	local blockData = getBlockData(rawBlock.blockTypeId)
	if not blockData then
		return
	end

	local key = makeCellKey(x, y, z)

	local block = {
		id = rawBlock.id,
		blockTypeId = rawBlock.blockTypeId,
		ownerId = tonumber(rawBlock.ownerId) or 0,
		health = tonumber(rawBlock.health) or blockData.maxHealth or 100,
		placedAt = tonumber(rawBlock.placedAt) or os.time(),
		cell = { x = x, y = y, z = z },
		position = parsePosition(rawBlock.position) or cellToWorld(x, y, z),
	}

	blocks[block.id] = block
	appendBlockIdToCell(key, block.id)
	blockCount += 1
	spawnBlockPart(block)
end

local function isBlockFullyInsideOwnerBase(userId: number, position: Vector3): boolean
	if not BaseClaimService then
		return false
	end

	if BaseClaimService.getBase and BaseClaimService.isInBase then
		local baseClaim = BaseClaimService.getBase(userId)
		if baseClaim and baseClaim.centerPosition and baseClaim.radius then
			local half = GRID_SIZE * 0.5
			local corners = {
				position + Vector3.new(half, 0, half),
				position + Vector3.new(half, 0, -half),
				position + Vector3.new(-half, 0, half),
				position + Vector3.new(-half, 0, -half),
			}
			for _, corner in ipairs(corners) do
				if not BaseClaimService.isInBase(userId, corner) then
					return false
				end
			end
			return true
		end
	end

	-- Prefer using explicit area check if available
	if BaseClaimService.isInBase then
		return BaseClaimService.isInBase(userId, position)
	end

	-- Fallback: check owner at the position
	if BaseClaimService.getOwnerAt then
		local ownerAt = BaseClaimService.getOwnerAt(position)
		return ownerAt == userId
	end

	return false
end

local function canBuildAt(userId: number, blockTypeId: string, position: Vector3): (boolean, string?)
	if TotemService and TotemService.isBuildAllowed then
		local allowed, err = TotemService.isBuildAllowed(userId, blockTypeId, position)
		if not allowed then
			return false, err or Enums.ErrorCode.NO_PERMISSION
		end
	elseif BaseClaimService and BaseClaimService.getBase and not BaseClaimService.getBase(userId) then
		return false, Enums.ErrorCode.TOTEM_REQUIRED
	end

	-- 블록 건축은 반드시 자신의 토템/베이스 반경 내부에서만 허용한다.
	if BaseClaimService and BaseClaimService.getOwnerAt then
		local ownerAt = BaseClaimService.getOwnerAt(position)
		if ownerAt ~= userId then
			return false, Enums.ErrorCode.NO_PERMISSION
		end
	end

	if not isBlockFullyInsideOwnerBase(userId, position) then
		return false, Enums.ErrorCode.NO_PERMISSION
	end

	if BaseClaimService and BaseClaimService.getOwnerAt then
		local ownerAt = BaseClaimService.getOwnerAt(position)
		if ownerAt and ownerAt ~= userId then
			local zoneProtected = true
			if TotemService and TotemService.isProtectionActiveForOwner then
				zoneProtected = TotemService.isProtectionActiveForOwner(ownerAt)
			end
			if zoneProtected then
				return false, Enums.ErrorCode.NO_PERMISSION
			end
		end
	end

	return true, nil
end

function BlockBuildService.place(player: Player, blockTypeId: string, cell: any, requestedPosition: any?): (boolean, string?, any?)
	local blockData = getBlockData(blockTypeId)
	if not blockData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	local x, y, z = parseCell(cell)
	if x == nil then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end

	local position = parsePosition(requestedPosition) or cellToWorld(x, y, z)
	local userId = player.UserId
	local character = player.Character

	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - position).Magnitude > BLOCK_RANGE then
			return false, Enums.ErrorCode.OUT_OF_RANGE, nil
		end
	end

	if blockCount >= BLOCK_CAP then
		return false, Enums.ErrorCode.STRUCTURE_CAP, nil
	end

	local allowed, buildErr = canBuildAt(userId, blockTypeId, position)
	if not allowed then
		return false, buildErr, nil
	end

	local key = makeCellKey(x, y, z)
	local existing = cellToBlockId[key]
	if existing then
		if type(existing) == "string" then
			local exBlock = blocks[existing]
			if exBlock and exBlock.blockTypeId ~= blockTypeId then
				return false, Enums.ErrorCode.COLLISION, nil
			end
		elseif type(existing) == "table" then
			for _, id in ipairs(existing) do
				local exBlock = blocks[id]
				if exBlock and exBlock.blockTypeId ~= blockTypeId then
					return false, Enums.ErrorCode.COLLISION, nil
				end
			end
		end
	end

	if not hasAdjacentSupport(x, y, z) and not isGroundSupportValid(position) then
		return false, Enums.ErrorCode.INVALID_POSITION, nil
	end

	local slotData, _, activeSlot = getActiveItemData(userId)
	if type(slotData) ~= "table" or slotData.itemId ~= blockTypeId then
		return false, Enums.ErrorCode.INVALID_ITEM, nil
	end

	if not InventoryService or (slotData.count or 0) < 1 then
		return false, Enums.ErrorCode.MISSING_REQUIREMENTS, nil
	end

	if InventoryService.removeItemFromSlot(userId, activeSlot, 1) < 1 then
		return false, Enums.ErrorCode.MISSING_REQUIREMENTS, nil
	end

	local block = {
		id = makeBlockId(),
		blockTypeId = blockTypeId,
		ownerId = userId,
		health = blockData.maxHealth or 100,
		placedAt = os.time(),
		cell = { x = x, y = y, z = z },
		position = position,
	}

	blocks[block.id] = block
	appendBlockIdToCell(key, block.id)
	blockCount += 1
	spawnBlockPart(block)
	saveBlock(block)

	if PlayerStatService then
		PlayerStatService.addXP(userId, Balance.XP_BUILD or 30, "BUILD")
	end
	if questCallback then
		questCallback(userId, blockTypeId)
	end

	return true, nil, {
		blockId = block.id,
		blockTypeId = block.blockTypeId,
		cell = block.cell,
		position = block.position,
	}
end

function BlockBuildService.remove(player: Player, blockId: string): (boolean, string?, any?)
	local block = blocks[blockId]
	if not block then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	local userId = player.UserId
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - block.position).Magnitude > BLOCK_RANGE then
			return false, Enums.ErrorCode.OUT_OF_RANGE, nil
		end
	end

	if block.ownerId ~= userId then
		local canRaid = false
		if TotemService and TotemService.canRaidStructure then
			canRaid = TotemService.canRaidStructure(userId, {
				ownerId = block.ownerId,
				position = block.position,
				health = block.health,
			})
		end
		if not canRaid then
			return false, Enums.ErrorCode.NO_PERMISSION, nil
		end
	end

	local slotData, itemData, activeSlot = getActiveItemData(userId)
	if not canBreakBlocksWithItem(itemData) then
		return false, Enums.ErrorCode.NO_TOOL, nil
	end

	if block.instance and block.instance.Parent then
		block.instance:Destroy()
	end

	blocks[blockId] = nil
	removeBlockIdFromCell(makeCellKey(block.cell.x, block.cell.y, block.cell.z), blockId)
	blockCount = math.max(0, blockCount - 1)
	deleteSavedBlock(blockId)

	if slotData and slotData.durability and DurabilityService and DurabilityService.reduceDurability then
		DurabilityService.reduceDurability(player, activeSlot, 1)
	end

	if WorldDropService then
		WorldDropService.spawnDrop(scatterDropPosition(block.position, 1), block.blockTypeId, 1)
	else
		InventoryService.addItem(block.ownerId, block.blockTypeId, 1)
	end

	return true, nil, { blockId = blockId }
end

local function handlePlace(player: Player, payload: any)
	local success, errorCode, data = BlockBuildService.place(player, payload.blockTypeId, payload.cell, payload.position)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleRemove(player: Player, payload: any)
	local success, errorCode, data = BlockBuildService.remove(player, payload.blockId)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

function BlockBuildService.Init(netController: any, dataService: any, inventoryService: any, saveService: any, playerStatService: any)
	if initialized then
		return
	end

	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	SaveService = saveService
	PlayerStatService = playerStatService

	blocksFolder = ensureBlocksFolder()

	local worldState = SaveService and SaveService.getWorldState and SaveService.getWorldState()
	if worldState and type(worldState.blockStructures) == "table" then
		for _, rawBlock in pairs(worldState.blockStructures) do
			loadBlockRecord(rawBlock)
		end
	end

	initialized = true
end

function BlockBuildService.SetBaseClaimService(baseClaimService: any)
	BaseClaimService = baseClaimService
end

function BlockBuildService.SetTotemService(totemService: any)
	TotemService = totemService
end

function BlockBuildService.SetWorldDropService(worldDropService: any)
	WorldDropService = worldDropService
end

function BlockBuildService.SetDurabilityService(durabilityService: any)
	DurabilityService = durabilityService
end

function BlockBuildService.SetQuestCallback(callback: any)
	questCallback = callback
end

function BlockBuildService.GetHandlers()
	return {
		["BlockBuild.Place.Request"] = handlePlace,
		["BlockBuild.Remove.Request"] = handleRemove,
	}
end

return BlockBuildService
