-- WorldDropController.lua
-- 클라이언트 월드 드롭 컨트롤러
-- 서버 WorldDrop 이벤트 수신 및 로컬 캐시 관리 + 3D 시각화

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NetClient = require(script.Parent.Parent.NetClient)
local ItemData = require(ReplicatedStorage.Data.ItemData)

local WorldDropController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 드롭 캐시 [dropId] = { dropId, pos, itemId, count, despawnAt, inactive }
local dropsCache = {}
local dropCount = 0

-- 드롭 모델 캐시 [dropId] = Model
local dropModels = {}

-- 드롭 모델 폴더
local dropFolder = nil

--========================================
-- Drop Model Configuration
--========================================
local DROP_COLORS = {
	STONE = Color3.fromRGB(128, 128, 128),
	WOOD = Color3.fromRGB(139, 90, 43),
	FIBER = Color3.fromRGB(76, 153, 0),
	BERRY = Color3.fromRGB(204, 51, 102),
	BERRIES = Color3.fromRGB(204, 51, 102),
	FLINT = Color3.fromRGB(64, 64, 64),
	THATCH = Color3.fromRGB(204, 178, 102),
	HIDE = Color3.fromRGB(139, 69, 19),
	LEATHER = Color3.fromRGB(139, 69, 19),
	MEAT = Color3.fromRGB(178, 102, 102),
	RESIN = Color3.fromRGB(230, 180, 80),
	IRON_ORE = Color3.fromRGB(100, 80, 70),
	DEFAULT = Color3.fromRGB(200, 200, 200),
}

local DROP_SIZE = Vector3.new(0.8, 0.8, 0.8)
local BILLBOARD_OFFSET = Vector3.new(0, 2, 0)

--========================================
-- Helper Functions
--========================================

local function getDropColor(itemId: string): Color3
	local upperItemId = itemId:upper()
	return DROP_COLORS[upperItemId] or DROP_COLORS.DEFAULT
end

local function getItemDisplayName(itemId: string): string
	local upperItemId = itemId:upper()
	for _, item in ipairs(ItemData) do
		if item.id == upperItemId then
			return item.name or itemId
		end
	end
	return itemId
end

local function createDropModel(dropData)
	if not dropData or not dropData.pos then return nil end
	
	-- 메인 파트 생성
	local part = Instance.new("Part")
	part.Name = "DropPart"
	part.Size = DROP_SIZE
	part.Shape = Enum.PartType.Ball
	part.Color = getDropColor(dropData.itemId)
	part.Material = Enum.Material.SmoothPlastic
	part.Position = dropData.pos
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	
	-- 속성 설정 (InteractController 인식용)
	part:SetAttribute("DropId", dropData.dropId)
	part:SetAttribute("ItemId", dropData.itemId)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = part.Color
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0.5
	highlight.Parent = part
	
	-- 빌보드 GUI (아이템 이름 + 개수)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DropLabel"
	billboard.Size = UDim2.new(0, 100, 0, 40)
	billboard.StudsOffset = BILLBOARD_OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 30
	billboard.Parent = part
	
	-- 배경 프레임
	local frame = Instance.new("Frame")
	frame.Name = "BG"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	frame.BackgroundTransparency = 0.4
	frame.BorderSizePixel = 0
	frame.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	
	-- 아이템 이름 텍스트
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = getItemDisplayName(dropData.itemId)
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = frame
	
	-- 개수 텍스트
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, 0, 0.4, 0)
	countLabel.Position = UDim2.new(0, 0, 0.6, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "x" .. tostring(dropData.count)
	countLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	countLabel.TextScaled = true
	countLabel.Font = Enum.Font.GothamMedium
	countLabel.Parent = frame
	
	-- ProximityPrompt (줍기)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "줍기"
	prompt.ObjectText = getItemDisplayName(dropData.itemId)
	prompt.MaxActivationDistance = 8  -- 6 -> 8 로 상향
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.Z
	prompt.Parent = part
	
	-- 줍기 이벤트
	prompt.Triggered:Connect(function(player)
		if player == game.Players.LocalPlayer then
			NetClient.Request("WorldDrop.Loot.Request", {
				dropId = dropData.dropId,
			})
		end
	end)
	
	-- 부유 애니메이션
	task.spawn(function()
		local startY = dropData.pos.Y
		local t = 0
		while part and part.Parent do
			t = t + 0.05
			local newY = startY + math.sin(t * 2) * 0.3
			part.Position = Vector3.new(dropData.pos.X, newY, dropData.pos.Z)
			
			-- 회전 효과
			part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(1), 0)
			
			task.wait(0.03)
		end
	end)
	
	return part
end

local function updateDropModel(dropId, newCount)
	local model = dropModels[dropId]
	if not model then return end
	
	local billboard = model:FindFirstChild("DropLabel")
	if billboard then
		local frame = billboard:FindFirstChild("BG")
		if frame then
			local countLabel = frame:FindFirstChild("Count")
			if countLabel then
				countLabel.Text = "x" .. tostring(newCount)
			end
		end
	end
	
	-- ProximityPrompt 업데이트
	local prompt = model:FindFirstChild("PickupPrompt")
	if prompt then
		prompt.ObjectText = getItemDisplayName(dropsCache[dropId].itemId) .. " x" .. tostring(newCount)
	end
end

local function removeDropModel(dropId)
	local model = dropModels[dropId]
	if model then
		-- 페이드아웃 효과
		local tween = TweenService:Create(model, TweenInfo.new(0.3), {
			Transparency = 1
		})
		tween:Play()
		tween.Completed:Connect(function()
			model:Destroy()
		end)
		
		dropModels[dropId] = nil
	end
end

--========================================
-- Public API: Cache Access
--========================================

function WorldDropController.getDropsCache()
	return dropsCache
end

function WorldDropController.getDrop(dropId: string)
	return dropsCache[dropId]
end

function WorldDropController.getDropCount(): number
	return dropCount
end

--========================================
-- Event Handlers
--========================================

local function onSpawned(data)
	if not data or not data.dropId then return end
	
	dropsCache[data.dropId] = {
		dropId = data.dropId,
		pos = data.pos,
		itemId = data.itemId,
		count = data.count,
		despawnAt = data.despawnAt,
		inactive = data.inactive,
	}
	dropCount = dropCount + 1
	
	-- 3D 모델 생성
	local model = createDropModel(dropsCache[data.dropId])
	if model then
		model.Parent = dropFolder
		dropModels[data.dropId] = model
	end
	
	-- 디버그 로그 (Studio에서만)
	-- print(string.format("[WorldDropController] Spawned: %s (%s x%d)", data.dropId, data.itemId, data.count))
end

local function onChanged(data)
	if not data or not data.dropId then return end
	
	local drop = dropsCache[data.dropId]
	if drop then
		drop.count = data.count
		updateDropModel(data.dropId, data.count)
		-- print(string.format("[WorldDropController] Changed: %s -> %d", data.dropId, data.count))
	end
end

local function onDespawned(data)
	if not data or not data.dropId then return end
	
	if dropsCache[data.dropId] then
		dropsCache[data.dropId] = nil
		dropCount = dropCount - 1
		removeDropModel(data.dropId)
		-- print(string.format("[WorldDropController] Despawned: %s (%s)", data.dropId, data.reason))
	end
end

--========================================
-- Initialization
--========================================

function WorldDropController.Init()
	if initialized then
		warn("[WorldDropController] Already initialized")
		return
	end
	
	-- 드롭 모델 폴더 생성
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "WorldDrops"
	dropFolder.Parent = Workspace
	
	-- 이벤트 리스너 등록
	NetClient.On("WorldDrop.Spawned", onSpawned)
	NetClient.On("WorldDrop.Changed", onChanged)
	NetClient.On("WorldDrop.Despawned", onDespawned)
	
	initialized = true
	print("[WorldDropController] Initialized - listening for WorldDrop events")
end

return WorldDropController
