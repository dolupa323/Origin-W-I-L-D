local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local DataHelper = require(Shared.Util.DataHelper)

local NetClient = require(script.Parent.Parent.NetClient)
local InputManager = require(script.Parent.Parent.InputManager)
local InventoryController = require(script.Parent.InventoryController)

local BlockBuildController = {}

local player = Players.LocalPlayer
local initialized = false

local GRID_SIZE = Balance.BLOCK_GRID_SIZE or 4
local PLACE_RANGE = Balance.BLOCK_BUILD_RANGE or 35

local isPlacing = false
local currentBlockTypeId = nil
local currentGhost = nil
local currentTargetCell = nil
local currentIsPlaceable = false
local heartbeatConn = nil

local function worldYToCellY(worldY: number): number
	return math.floor((worldY - (GRID_SIZE * 0.5)) / GRID_SIZE)
end

local function getBlocksFolder(): Folder?
	return workspace:FindFirstChild("BlockStructures")
end

local function getCurrentUIManager()
	return require(script.Parent.Parent.UIManager)
end

local function getBlockData(blockTypeId: string): any?
	local data = DataHelper.GetData("FacilityData", blockTypeId)
	if data and data.buildMode == "BLOCK" then
		return data
	end
	return nil
end

local function worldToCell(worldPos: Vector3): { x: number, y: number, z: number }
	return {
		x = math.floor(worldPos.X / GRID_SIZE),
		y = worldYToCellY(worldPos.Y),
		z = math.floor(worldPos.Z / GRID_SIZE),
	}
end

local function cellToWorld(cell: any): Vector3
	return Vector3.new(
		(cell.x + 0.5) * GRID_SIZE,
		(cell.y + 0.5) * GRID_SIZE,
		(cell.z + 0.5) * GRID_SIZE
	)
end

local function dominantNormalAxis(normal: Vector3): { x: number, y: number, z: number }
	local absX = math.abs(normal.X)
	local absY = math.abs(normal.Y)
	local absZ = math.abs(normal.Z)

	if absX >= absY and absX >= absZ then
		return { x = normal.X >= 0 and 1 or -1, y = 0, z = 0 }
	elseif absY >= absX and absY >= absZ then
		return { x = 0, y = normal.Y >= 0 and 1 or -1, z = 0 }
	end

	return { x = 0, y = 0, z = normal.Z >= 0 and 1 or -1 }
end

local function isWorldSurfaceAllowed(result: RaycastResult): boolean
	if not result or not result.Instance then
		return false
	end

	if result.Material == Enum.Material.Water then
		return false
	end

	local hit = result.Instance
	local disallowedFolders = {
		workspace:FindFirstChild("Facilities"),
		workspace:FindFirstChild("ResourceNodes"),
		workspace:FindFirstChild("NPCs"),
		workspace:FindFirstChild("Creatures"),
		workspace:FindFirstChild("Characters"),
	}

	for _, folder in ipairs(disallowedFolders) do
		if folder and hit:IsDescendantOf(folder) then
			return false
		end
	end

	local model = hit:FindFirstAncestorWhichIsA("Model")
	if model and (model:GetAttribute("StructureId") or model:GetAttribute("NodeId") or model:GetAttribute("NPCId")) then
		return false
	end

	return true
end

local function getMouseResult(): RaycastResult?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local exclude = {}
	if currentGhost then
		table.insert(exclude, currentGhost)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude

	return workspace:Raycast(ray.Origin, ray.Direction * 160, params)
end

local function sampleGroundBottomY(centerX: number, centerZ: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local exclude = {}
	local blocksFolder = getBlocksFolder()
	if blocksFolder then
		table.insert(exclude, blocksFolder)
	end
	if currentGhost then
		table.insert(exclude, currentGhost)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude

	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(GRID_SIZE * 0.45, 0, GRID_SIZE * 0.45),
		Vector3.new(GRID_SIZE * 0.45, 0, -GRID_SIZE * 0.45),
		Vector3.new(-GRID_SIZE * 0.45, 0, GRID_SIZE * 0.45),
		Vector3.new(-GRID_SIZE * 0.45, 0, -GRID_SIZE * 0.45),
	}

	local sampledY = nil
	for _, offset in ipairs(offsets) do
		local origin = Vector3.new(centerX + offset.X, 512, centerZ + offset.Z)
		local result = workspace:Raycast(origin, Vector3.new(0, -1024, 0), params)
		if result and result.Instance and isWorldSurfaceAllowed(result) then
			local hitY = result.Position.Y
			if sampledY == nil or hitY < sampledY then
				sampledY = hitY
			end
		end
	end

	return sampledY
end

local function getTargetPlacementFromResult(result: RaycastResult): any?
	if not result or not result.Instance then
		return nil
	end

	local blocksFolder = getBlocksFolder()
	if blocksFolder and result.Instance:IsDescendantOf(blocksFolder) then
		local cx = tonumber(result.Instance:GetAttribute("CellX"))
		local cy = tonumber(result.Instance:GetAttribute("CellY"))
		local cz = tonumber(result.Instance:GetAttribute("CellZ"))
		if cx ~= nil and cy ~= nil and cz ~= nil then
			local axis = dominantNormalAxis(result.Normal)
			local sourcePos = Vector3.new(
				tonumber(result.Instance:GetAttribute("PosX")) or result.Instance.Position.X,
				tonumber(result.Instance:GetAttribute("PosY")) or result.Instance.Position.Y,
				tonumber(result.Instance:GetAttribute("PosZ")) or result.Instance.Position.Z
			)
			local worldPos = sourcePos + Vector3.new(axis.x * GRID_SIZE, axis.y * GRID_SIZE, axis.z * GRID_SIZE)
			return {
				x = cx + axis.x,
				y = cy + axis.y,
				z = cz + axis.z,
				position = worldPos,
			}
		end
	end

	if not isWorldSurfaceAllowed(result) then
		return nil
	end

	local probe = result.Position + (result.Normal * (GRID_SIZE * 0.5))
	local snappedX = (math.floor(probe.X / GRID_SIZE) + 0.5) * GRID_SIZE
	local snappedZ = (math.floor(probe.Z / GRID_SIZE) + 0.5) * GRID_SIZE
	local bottomY = sampleGroundBottomY(snappedX, snappedZ) or result.Position.Y
	local worldPos = Vector3.new(snappedX, bottomY + (GRID_SIZE * 0.5), snappedZ)
	local cell = worldToCell(worldPos)
	cell.position = worldPos
	return cell
end

local function isCellOccupied(cell: any): boolean
	local blocksFolder = getBlocksFolder()
	if not blocksFolder or not cell then
		return false
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { blocksFolder }

	local parts = workspace:GetPartBoundsInBox(
		CFrame.new(cell.position or cellToWorld(cell)),
		Vector3.new(GRID_SIZE * 0.8, GRID_SIZE * 0.8, GRID_SIZE * 0.8),
		params
	)

	return #parts > 0
end

local function createGhost(blockTypeId: string): BasePart?
	local data = getBlockData(blockTypeId)
	if not data then
		return nil
	end

	local ghost = Instance.new("Part")
	ghost.Name = "BLOCK_BUILD_GHOST"
	ghost.Size = Vector3.new(GRID_SIZE, GRID_SIZE, GRID_SIZE)
	ghost.Anchored = true
	ghost.Material = data.blockMaterial or Enum.Material.SmoothPlastic
	ghost.Color = data.blockColor or Color3.fromRGB(150, 150, 150)
	ghost.Transparency = 0.5
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.TopSurface = Enum.SurfaceType.Smooth
	ghost.BottomSurface = Enum.SurfaceType.Smooth
	ghost.Parent = workspace
	return ghost
end

local function setGhostColor(placeable: boolean)
	if not currentGhost then
		return
	end

	if placeable then
		currentGhost.Color = Color3.fromRGB(100, 255, 100)
	else
		currentGhost.Color = Color3.fromRGB(255, 100, 100)
	end
	currentGhost.Transparency = 0.55
end

function BlockBuildController.getFriendlyError(code: any): string
	local map = {
		TOTEM_REQUIRED = "토템이 필요합니다. 먼저 거점 토템을 설치하세요.",
		TOTEM_UPKEEP_EXPIRED = "토템 유지비가 만료되었습니다. 토템에서 연장 결제를 해주세요.",
		NO_PERMISSION = "이 영역에서는 건설 권한이 없습니다.",
		COLLISION = "이미 다른 블록이 있는 칸입니다.",
		OUT_OF_RANGE = "건축 가능 거리 밖입니다.",
		INVALID_POSITION = "지지대가 없거나 설치할 수 없는 칸입니다.",
		INVALID_ITEM = "핫바에서 선택한 블록만 배치할 수 있습니다.",
		MISSING_REQUIREMENTS = "블록 아이템이 부족합니다.",
		STRUCTURE_CAP = "블록 한도에 도달했습니다.",
		NOT_FOUND = "대상을 찾을 수 없습니다.",
		NO_TOOL = "블록을 부수려면 무기나 도구를 들어야 합니다.",
	}

	return map[tostring(code)] or "블록 작업에 실패했습니다."
end

local function notifyBlockError(code: any)
	getCurrentUIManager().notify(BlockBuildController.getFriendlyError(code), Color3.fromRGB(255, 100, 100))
end

local function getSelectedSlotBlockTypeId(): string?
	local uiManager = getCurrentUIManager()
	local selectedSlot = uiManager.getSelectedSlot and uiManager.getSelectedSlot() or nil
	if not selectedSlot then
		return nil
	end

	local slotData = InventoryController.getSlot(selectedSlot)
	if not slotData or not slotData.itemId then
		return nil
	end

	return getBlockData(slotData.itemId) and slotData.itemId or nil
end

local function beginPlacement(blockTypeId: string)
	if isPlacing and currentBlockTypeId == blockTypeId and currentGhost and heartbeatConn then
		return
	end

	BlockBuildController.cancelPlacement()

	currentBlockTypeId = blockTypeId
	currentGhost = createGhost(blockTypeId)
	if not currentGhost then
		currentBlockTypeId = nil
		return
	end

	isPlacing = true
	currentTargetCell = nil
	currentIsPlaceable = false

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not currentGhost then
			return
		end

		local activeBlockTypeId = getSelectedSlotBlockTypeId()
		if activeBlockTypeId ~= currentBlockTypeId then
			BlockBuildController.syncActiveSlot()
			return
		end

		local result = getMouseResult()
		local targetCell = getTargetPlacementFromResult(result)
		local placeable = false

		if targetCell then
			local worldPos = targetCell.position or cellToWorld(targetCell)
			currentGhost.CFrame = CFrame.new(worldPos)

			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - worldPos).Magnitude <= PLACE_RANGE and not isCellOccupied(targetCell) then
				placeable = true
			end
		end

		currentTargetCell = targetCell
		currentIsPlaceable = placeable
		setGhostColor(placeable)
	end)

	InputManager.onLeftClick("BlockBuildPlace", function()
		if not isPlacing or not currentTargetCell or not currentIsPlaceable then
			return
		end

		local ok, response = NetClient.Request("BlockBuild.Place.Request", {
			blockTypeId = currentBlockTypeId,
			cell = currentTargetCell,
			position = currentTargetCell.position,
		})

		if not ok then
			notifyBlockError(response)
		end
	end)

	getCurrentUIManager().showBuildPrompt(true, "BLOCK")
end

function BlockBuildController.startPlacement(blockTypeId: string)
	if not getBlockData(blockTypeId) then
		return
	end
	beginPlacement(blockTypeId)
end

function BlockBuildController.cancelPlacement()
	local wasPlacing = isPlacing or currentGhost ~= nil or heartbeatConn ~= nil

	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if currentGhost then
		currentGhost:Destroy()
		currentGhost = nil
	end

	InputManager.unbindLeftClick("BlockBuildPlace")

	isPlacing = false
	currentBlockTypeId = nil
	currentTargetCell = nil
	currentIsPlaceable = false

	if wasPlacing then
		getCurrentUIManager().showBuildPrompt(false)
	end
end

function BlockBuildController.syncActiveSlot()
	local blockTypeId = getSelectedSlotBlockTypeId()
	if blockTypeId then
		beginPlacement(blockTypeId)
	else
		BlockBuildController.cancelPlacement()
	end
end

function BlockBuildController.getHoveredBlockId(): string?
	local result = getMouseResult()
	local blocksFolder = getBlocksFolder()
	if not result or not result.Instance or not blocksFolder or not result.Instance:IsDescendantOf(blocksFolder) then
		return nil
	end
	return result.Instance:GetAttribute("BlockId")
end

function BlockBuildController.Init()
	if initialized then
		return
	end
	initialized = true

	InventoryController.onChanged(function()
		BlockBuildController.syncActiveSlot()
	end)

	NetClient.On("Inventory.ActiveSlot.Changed", function()
		BlockBuildController.syncActiveSlot()
	end)

	task.defer(function()
		BlockBuildController.syncActiveSlot()
	end)
end

return BlockBuildController
