-- UIManager.lua
-- UI 관리 모듈 - "더 서바이벌 게임" 스타일
-- 원시/부족 테마 디자인

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Client = script.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)

-- Controllers
local Controllers = Client:WaitForChild("Controllers")
local InventoryController = require(Controllers.InventoryController)
local QuestController = require(Controllers.QuestController)
local ShopController = require(Controllers.ShopController)

local UIManager = {}

--========================================
-- 더 서바이벌 스타일 컬러 팔레트
--========================================
local COLORS = {
	-- 나무/원시 테마
	WOOD_DARK = Color3.fromRGB(61, 43, 31),
	WOOD_MEDIUM = Color3.fromRGB(92, 64, 51),
	WOOD_LIGHT = Color3.fromRGB(139, 90, 43),
	LEATHER = Color3.fromRGB(101, 67, 33),
	STONE = Color3.fromRGB(80, 80, 85),
	
	-- 배경
	BG_DARK = Color3.fromRGB(20, 18, 15),
	BG_PANEL = Color3.fromRGB(35, 30, 25),
	BG_SLOT = Color3.fromRGB(45, 38, 32),
	
	-- 테두리
	BORDER_DARK = Color3.fromRGB(40, 32, 25),
	BORDER_LIGHT = Color3.fromRGB(120, 90, 60),
	
	-- 상태바
	HEALTH = Color3.fromRGB(180, 50, 50),
	HEALTH_BG = Color3.fromRGB(60, 20, 20),
	STAMINA = Color3.fromRGB(220, 180, 50),
	STAMINA_BG = Color3.fromRGB(70, 60, 20),
	HUNGER = Color3.fromRGB(180, 120, 60),
	HUNGER_BG = Color3.fromRGB(60, 40, 20),
	THIRST = Color3.fromRGB(80, 150, 200),
	THIRST_BG = Color3.fromRGB(25, 50, 70),
	XP = Color3.fromRGB(120, 200, 80),
	XP_BG = Color3.fromRGB(35, 60, 25),
	
	-- 텍스트
	TEXT_LIGHT = Color3.fromRGB(230, 220, 200),
	TEXT_DIM = Color3.fromRGB(150, 140, 120),
	TEXT_GOLD = Color3.fromRGB(255, 200, 80),
	TEXT_DAMAGE = Color3.fromRGB(255, 80, 80),
	
	-- 버튼
	BUTTON_NORMAL = Color3.fromRGB(80, 60, 45),
	BUTTON_HOVER = Color3.fromRGB(100, 75, 55),
	BUTTON_PRESSED = Color3.fromRGB(60, 45, 35),
	
	-- 희귀도
	RARITY_COMMON = Color3.fromRGB(180, 180, 180),
	RARITY_UNCOMMON = Color3.fromRGB(80, 200, 80),
	RARITY_RARE = Color3.fromRGB(80, 140, 255),
	RARITY_EPIC = Color3.fromRGB(180, 80, 255),
	RARITY_LEGENDARY = Color3.fromRGB(255, 180, 50),
}

local FONTS = {
	TITLE = Enum.Font.GothamBold,
	NORMAL = Enum.Font.Gotham,
	NUMBER = Enum.Font.GothamMedium,
}

--========================================
-- Private State
--========================================
local initialized = false
local mainGui = nil

local hudFrame = nil
local hotbarFrame = nil
local statusBarsFrame = nil
local inventoryFrame = nil
local craftingFrame = nil
local questFrame = nil
local shopFrame = nil
local interactPrompt = nil

local isInventoryOpen = false
local isCraftingOpen = false
local isQuestOpen = false
local isShopOpen = false

local healthBar = nil
local staminaBar = nil
local hungerBar = nil
local thirstBar = nil
local xpBar = nil
local levelLabel = nil

local hotbarSlots = {}
local selectedHotbarSlot = 1
local inventorySlots = {}

--========================================
-- UI Creation Helpers
--========================================

local function addWoodBorder(frame, thickness)
	thickness = thickness or 3
	
	local top = Instance.new("Frame")
	top.Name = "BorderTop"
	top.Size = UDim2.new(1, thickness * 2, 0, thickness)
	top.Position = UDim2.new(0, -thickness, 0, -thickness)
	top.BackgroundColor3 = COLORS.WOOD_MEDIUM
	top.BorderSizePixel = 0
	top.Parent = frame
	
	local bottom = Instance.new("Frame")
	bottom.Name = "BorderBottom"
	bottom.Size = UDim2.new(1, thickness * 2, 0, thickness)
	bottom.Position = UDim2.new(0, -thickness, 1, 0)
	bottom.BackgroundColor3 = COLORS.WOOD_DARK
	bottom.BorderSizePixel = 0
	bottom.Parent = frame
	
	local left = Instance.new("Frame")
	left.Name = "BorderLeft"
	left.Size = UDim2.new(0, thickness, 1, thickness * 2)
	left.Position = UDim2.new(0, -thickness, 0, -thickness)
	left.BackgroundColor3 = COLORS.WOOD_MEDIUM
	left.BorderSizePixel = 0
	left.Parent = frame
	
	local right = Instance.new("Frame")
	right.Name = "BorderRight"
	right.Size = UDim2.new(0, thickness, 1, thickness * 2)
	right.Position = UDim2.new(1, 0, 0, -thickness)
	right.BackgroundColor3 = COLORS.WOOD_DARK
	right.BorderSizePixel = 0
	right.Parent = frame
end

local function createFrame(props)
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Frame"
	frame.Size = props.size or UDim2.new(0, 100, 0, 100)
	frame.Position = props.position or UDim2.new(0, 0, 0, 0)
	frame.AnchorPoint = props.anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = props.bgColor or COLORS.BG_PANEL
	frame.BackgroundTransparency = props.bgTransparency or 0
	frame.BorderSizePixel = 0
	frame.Visible = props.visible ~= false
	frame.ZIndex = props.zIndex or 1
	frame.Parent = props.parent
	
	if props.cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.cornerRadius)
		corner.Parent = frame
	end
	
	if props.woodBorder then
		addWoodBorder(frame, props.borderThickness)
	end
	
	return frame
end

local function createLabel(props)
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.Size = props.size or UDim2.new(1, 0, 1, 0)
	label.Position = props.position or UDim2.new(0, 0, 0, 0)
	label.AnchorPoint = props.anchor or Vector2.new(0, 0)
	label.BackgroundTransparency = 1
	label.Text = props.text or ""
	label.TextColor3 = props.textColor or COLORS.TEXT_LIGHT
	label.TextSize = props.textSize or 14
	label.Font = props.font or FONTS.NORMAL
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	label.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	label.TextStrokeTransparency = props.strokeTransparency or 0.8
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.ZIndex = props.zIndex or 1
	label.Parent = props.parent
	return label
end

local function createButton(props)
	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size or UDim2.new(0, 100, 0, 36)
	button.Position = props.position or UDim2.new(0, 0, 0, 0)
	button.AnchorPoint = props.anchor or Vector2.new(0, 0)
	button.BackgroundColor3 = props.bgColor or COLORS.BUTTON_NORMAL
	button.BorderSizePixel = 0
	button.Text = props.text or "Button"
	button.TextColor3 = props.textColor or COLORS.TEXT_LIGHT
	button.TextSize = props.textSize or 14
	button.Font = props.font or FONTS.NORMAL
	button.TextStrokeTransparency = 0.8
	button.TextStrokeColor3 = Color3.new(0, 0, 0)
	button.AutoButtonColor = false
	button.ZIndex = props.zIndex or 1
	button.Parent = props.parent
	
	if props.cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.cornerRadius)
		corner.Parent = button
	end
	
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), {
			BackgroundColor3 = COLORS.BUTTON_HOVER
		}):Play()
	end)
	
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), {
			BackgroundColor3 = props.bgColor or COLORS.BUTTON_NORMAL
		}):Play()
	end)
	
	if props.onClick then
		button.MouseButton1Click:Connect(props.onClick)
	end
	
	return button
end

local function createStatusBar(props)
	local container = createFrame({
		name = props.name .. "Bar",
		size = props.size or UDim2.new(0, 200, 0, 20),
		position = props.position,
		anchor = props.anchor,
		bgColor = props.bgColor or COLORS.BG_DARK,
		cornerRadius = 3,
		parent = props.parent,
	})
	
	local bgInner = createFrame({
		name = "BgInner",
		size = UDim2.new(1, -4, 1, -4),
		position = UDim2.new(0, 2, 0, 2),
		bgColor = props.trackColor or COLORS.HEALTH_BG,
		cornerRadius = 2,
		parent = container,
	})
	
	local fill = createFrame({
		name = "Fill",
		size = UDim2.new(1, 0, 1, 0),
		bgColor = props.fillColor or COLORS.HEALTH,
		cornerRadius = 2,
		parent = bgInner,
	})
	
	local valueLabel = createLabel({
		name = "Value",
		size = UDim2.new(1, 0, 1, 0),
		text = props.text or "100/100",
		textSize = 11,
		font = FONTS.NUMBER,
		zIndex = 2,
		parent = container,
	})
	
	return container, fill, valueLabel
end

local function createItemSlot(props)
	local slot = createFrame({
		name = props.name or "Slot",
		size = props.size or UDim2.new(0, 50, 0, 50),
		position = props.position,
		bgColor = COLORS.BG_SLOT,
		cornerRadius = 4,
		zIndex = props.zIndex or 1,
		parent = props.parent,
	})
	
	local innerBorder = createFrame({
		name = "InnerBorder",
		size = UDim2.new(1, -4, 1, -4),
		position = UDim2.new(0, 2, 0, 2),
		bgColor = COLORS.BG_DARK,
		bgTransparency = 0.5,
		cornerRadius = 2,
		zIndex = props.zIndex or 1,
		parent = slot,
	})
	
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, -8, 1, -18)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = (props.zIndex or 1) + 1
	icon.Parent = slot
	
	local countLabel = createLabel({
		name = "Count",
		size = UDim2.new(1, -4, 0, 14),
		position = UDim2.new(0, 2, 1, -16),
		text = "",
		textSize = 11,
		font = FONTS.NUMBER,
		alignX = Enum.TextXAlignment.Right,
		zIndex = (props.zIndex or 1) + 2,
		parent = slot,
	})
	
	local highlight = createFrame({
		name = "Highlight",
		size = UDim2.new(1, 4, 1, 4),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.TEXT_GOLD,
		bgTransparency = 1,
		cornerRadius = 6,
		zIndex = (props.zIndex or 1) - 1,
		parent = slot,
	})
	
	local clickBtn = Instance.new("TextButton")
	clickBtn.Name = "ClickArea"
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.ZIndex = (props.zIndex or 1) + 3
	clickBtn.Parent = slot
	
	return {
		frame = slot,
		icon = icon,
		countLabel = countLabel,
		highlight = highlight,
		clickBtn = clickBtn,
	}
end

--========================================
-- HUD Creation
--========================================

local function createHUD()
	statusBarsFrame = createFrame({
		name = "StatusBars",
		size = UDim2.new(0, 220, 0, 140),
		position = UDim2.new(0, 15, 0.5, -50),
		anchor = Vector2.new(0, 0.5),
		bgTransparency = 1,
		parent = mainGui,
	})
	
	local _, hpFill, hpLabel = createStatusBar({
		name = "Health",
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.new(0, 0, 0, 0),
		fillColor = COLORS.HEALTH,
		trackColor = COLORS.HEALTH_BG,
		text = "100/100",
		parent = statusBarsFrame,
	})
	healthBar = { fill = hpFill, label = hpLabel }
	
	local _, stFill, stLabel = createStatusBar({
		name = "Stamina",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.new(0, 0, 0, 28),
		fillColor = COLORS.STAMINA,
		trackColor = COLORS.STAMINA_BG,
		text = "100/100",
		parent = statusBarsFrame,
	})
	staminaBar = { fill = stFill, label = stLabel }
	
	local _, huFill, huLabel = createStatusBar({
		name = "Hunger",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.new(0, 0, 0, 52),
		fillColor = COLORS.HUNGER,
		trackColor = COLORS.HUNGER_BG,
		text = "100/100",
		parent = statusBarsFrame,
	})
	hungerBar = { fill = huFill, label = huLabel }
	
	local _, thFill, thLabel = createStatusBar({
		name = "Thirst",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.new(0, 0, 0, 76),
		fillColor = COLORS.THIRST,
		trackColor = COLORS.THIRST_BG,
		text = "100/100",
		parent = statusBarsFrame,
	})
	thirstBar = { fill = thFill, label = thLabel }
	
	local _, xpFill, xpLabel = createStatusBar({
		name = "XP",
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.new(0, 0, 0, 105),
		fillColor = COLORS.XP,
		trackColor = COLORS.XP_BG,
		text = "0/100 XP",
		parent = statusBarsFrame,
	})
	xpBar = { fill = xpFill, label = xpLabel }
	
	levelLabel = createLabel({
		name = "Level",
		size = UDim2.new(0, 60, 0, 20),
		position = UDim2.new(0, 0, 0, 122),
		text = "Lv. 1",
		textSize = 14,
		font = FONTS.TITLE,
		textColor = COLORS.TEXT_GOLD,
		alignX = Enum.TextXAlignment.Left,
		parent = statusBarsFrame,
	})
end

--========================================
-- Hotbar Creation
--========================================

local function createHotbar()
	local SLOT_SIZE = 56
	local SLOT_PADDING = 6
	local SLOT_COUNT = 8
	local TOTAL_WIDTH = SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_PADDING
	
	hotbarFrame = createFrame({
		name = "Hotbar",
		size = UDim2.new(0, TOTAL_WIDTH + 16, 0, SLOT_SIZE + 16),
		position = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
		bgColor = COLORS.BG_PANEL,
		bgTransparency = 1,
		cornerRadius = 8,
		woodBorder = false,
		parent = mainGui,
	})
	
	for i = 1, SLOT_COUNT do
		local xPos = 8 + (i - 1) * (SLOT_SIZE + SLOT_PADDING)
		
		local slot = createItemSlot({
			name = "HotbarSlot" .. i,
			size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
			position = UDim2.new(0, xPos, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			zIndex = 2,
			parent = hotbarFrame,
		})
		
		createLabel({
			name = "KeyNum",
			size = UDim2.new(0, 16, 0, 14),
			position = UDim2.new(0, 2, 0, 2),
			text = tostring(i),
			textSize = 10,
			font = FONTS.NUMBER,
			textColor = COLORS.TEXT_DIM,
			alignX = Enum.TextXAlignment.Left,
			alignY = Enum.TextYAlignment.Top,
			zIndex = 5,
			parent = slot.frame,
		})
		
		slot.clickBtn.MouseButton1Click:Connect(function()
			UIManager.selectHotbarSlot(i)
		end)
		
		hotbarSlots[i] = slot
	end
	
	UIManager.selectHotbarSlot(1)
end

--========================================
-- Inventory UI Creation
--========================================

local function createInventoryUI()
	local SLOT_SIZE = 52
	local SLOT_PADDING = 6
	local COLS = 5
	local ROWS = 4
	local PANEL_WIDTH = COLS * SLOT_SIZE + (COLS - 1) * SLOT_PADDING + 40
	local PANEL_HEIGHT = ROWS * SLOT_SIZE + (ROWS - 1) * SLOT_PADDING + 80
	
	inventoryFrame = createFrame({
		name = "Inventory",
		size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.BG_PANEL,
		cornerRadius = 8,
		woodBorder = true,
		borderThickness = 4,
		visible = false,
		zIndex = 10,
		parent = mainGui,
	})
	
	local titleBar = createFrame({
		name = "TitleBar",
		size = UDim2.new(1, 0, 0, 36),
		bgColor = COLORS.WOOD_DARK,
		cornerRadius = 8,
		zIndex = 10,
		parent = inventoryFrame,
	})
	
	createFrame({
		name = "TitleFix",
		size = UDim2.new(1, 0, 0, 10),
		position = UDim2.new(0, 0, 1, -10),
		bgColor = COLORS.WOOD_DARK,
		zIndex = 10,
		parent = titleBar,
	})
	
	createLabel({
		name = "Title",
		size = UDim2.new(1, 0, 1, 0),
		text = "🎒 인벤토리",
		textSize = 16,
		font = FONTS.TITLE,
		zIndex = 11,
		parent = titleBar,
	})
	
	createButton({
		name = "Close",
		size = UDim2.new(0, 28, 0, 28),
		position = UDim2.new(1, -32, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = "X",
		textSize = 16,
		font = FONTS.TITLE,
		bgColor = COLORS.HEALTH,
		cornerRadius = 4,
		zIndex = 12,
		onClick = function()
			UIManager.closeInventory()
		end,
		parent = titleBar,
	})
	
	local slotsContainer = createFrame({
		name = "Slots",
		size = UDim2.new(1, -30, 1, -50),
		position = UDim2.new(0, 15, 0, 45),
		bgTransparency = 1,
		zIndex = 10,
		parent = inventoryFrame,
	})
	
	for row = 1, ROWS do
		for col = 1, COLS do
			local i = (row - 1) * COLS + col
			local xPos = (col - 1) * (SLOT_SIZE + SLOT_PADDING)
			local yPos = (row - 1) * (SLOT_SIZE + SLOT_PADDING)
			
			local slot = createItemSlot({
				name = "InvSlot" .. i,
				size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
				position = UDim2.new(0, xPos, 0, yPos),
				zIndex = 11,
				parent = slotsContainer,
			})
			
			slot.clickBtn.MouseButton1Click:Connect(function()
				UIManager.onInventorySlotClick(i)
			end)
			
			inventorySlots[i] = slot
		end
	end
end

--========================================
-- Quest UI Creation
--========================================

local function createQuestUI()
	questFrame = createFrame({
		name = "Quest",
		size = UDim2.new(0, 320, 0, 420),
		position = UDim2.new(1, -20, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bgColor = COLORS.BG_PANEL,
		cornerRadius = 8,
		woodBorder = true,
		borderThickness = 4,
		visible = false,
		zIndex = 10,
		parent = mainGui,
	})
	
	local titleBar = createFrame({
		name = "TitleBar",
		size = UDim2.new(1, 0, 0, 36),
		bgColor = COLORS.WOOD_DARK,
		cornerRadius = 8,
		zIndex = 10,
		parent = questFrame,
	})
	
	createFrame({
		name = "TitleFix",
		size = UDim2.new(1, 0, 0, 10),
		position = UDim2.new(0, 0, 1, -10),
		bgColor = COLORS.WOOD_DARK,
		zIndex = 10,
		parent = titleBar,
	})
	
	createLabel({
		name = "Title",
		size = UDim2.new(1, 0, 1, 0),
		text = "📜 퀘스트",
		textSize = 16,
		font = FONTS.TITLE,
		zIndex = 11,
		parent = titleBar,
	})
	
	createButton({
		name = "Close",
		size = UDim2.new(0, 28, 0, 28),
		position = UDim2.new(1, -32, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = "X",
		textSize = 16,
		font = FONTS.TITLE,
		bgColor = COLORS.HEALTH,
		cornerRadius = 4,
		zIndex = 12,
		onClick = function()
			UIManager.closeQuest()
		end,
		parent = titleBar,
	})
	
	local questScroll = Instance.new("ScrollingFrame")
	questScroll.Name = "QuestList"
	questScroll.Size = UDim2.new(1, -20, 1, -50)
	questScroll.Position = UDim2.new(0, 10, 0, 45)
	questScroll.BackgroundTransparency = 1
	questScroll.BorderSizePixel = 0
	questScroll.ScrollBarThickness = 6
	questScroll.ScrollBarImageColor3 = COLORS.WOOD_LIGHT
	questScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	questScroll.ZIndex = 10
	questScroll.Parent = questFrame
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = questScroll
end

--========================================
-- Shop UI Creation
--========================================

local function createShopUI()
	shopFrame = createFrame({
		name = "Shop",
		size = UDim2.new(0, 550, 0, 420),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.BG_PANEL,
		cornerRadius = 8,
		woodBorder = true,
		borderThickness = 4,
		visible = false,
		zIndex = 10,
		parent = mainGui,
	})
	
	local titleBar = createFrame({
		name = "TitleBar",
		size = UDim2.new(1, 0, 0, 36),
		bgColor = COLORS.WOOD_DARK,
		cornerRadius = 8,
		zIndex = 10,
		parent = shopFrame,
	})
	
	createFrame({
		name = "TitleFix",
		size = UDim2.new(1, 0, 0, 10),
		position = UDim2.new(0, 0, 1, -10),
		bgColor = COLORS.WOOD_DARK,
		zIndex = 10,
		parent = titleBar,
	})
	
	createLabel({
		name = "Title",
		size = UDim2.new(1, 0, 1, 0),
		text = "🏪 상점",
		textSize = 16,
		font = FONTS.TITLE,
		zIndex = 11,
		parent = titleBar,
	})
	
	createButton({
		name = "Close",
		size = UDim2.new(0, 28, 0, 28),
		position = UDim2.new(1, -32, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = "X",
		textSize = 16,
		font = FONTS.TITLE,
		bgColor = COLORS.HEALTH,
		cornerRadius = 4,
		zIndex = 12,
		onClick = function()
			UIManager.closeShop()
		end,
		parent = titleBar,
	})
	
	createLabel({
		name = "Gold",
		size = UDim2.new(0, 120, 0, 28),
		position = UDim2.new(0, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = "💰 0",
		textSize = 14,
		font = FONTS.NUMBER,
		textColor = COLORS.TEXT_GOLD,
		alignX = Enum.TextXAlignment.Left,
		zIndex = 11,
		parent = titleBar,
	})
end

--========================================
-- Interact Prompt
--========================================

local function createInteractPrompt()
	interactPrompt = createFrame({
		name = "InteractPrompt",
		size = UDim2.new(0, 180, 0, 44),
		position = UDim2.new(0.5, 0, 0.65, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.BG_PANEL,
		bgTransparency = 0.2,
		cornerRadius = 6,
		woodBorder = true,
		borderThickness = 2,
		visible = false,
		zIndex = 5,
		parent = mainGui,
	})
	
	createLabel({
		name = "Text",
		size = UDim2.new(1, 0, 1, 0),
		text = "[E] 상호작용",
		textSize = 14,
		font = FONTS.NORMAL,
		zIndex = 6,
		parent = interactPrompt,
	})
end

--========================================
-- Key Hints
--========================================

local function createKeyHints()
	local hints = createFrame({
		name = "KeyHints",
		size = UDim2.new(0, 160, 0, 70),
		position = UDim2.new(1, -15, 1, -90),
		anchor = Vector2.new(1, 1),
		bgColor = COLORS.BG_PANEL,
		bgTransparency = 0.4,
		cornerRadius = 6,
		parent = mainGui,
	})
	
	createLabel({
		text = "[B] 인벤토리\n[J] 퀘스트\n[E] 상호작용",
		size = UDim2.new(1, -10, 1, -6),
		position = UDim2.new(0, 5, 0, 3),
		textSize = 11,
		textColor = COLORS.TEXT_DIM,
		alignX = Enum.TextXAlignment.Left,
		alignY = Enum.TextYAlignment.Top,
		parent = hints,
	})
end

--========================================
-- Public API: HUD Updates
--========================================

function UIManager.updateHealth(current: number, max: number)
	if not healthBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(healthBar.fill, TweenInfo.new(0.2), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	healthBar.label.Text = string.format("%d/%d", math.floor(current), math.floor(max))
end

function UIManager.updateStamina(current: number, max: number)
	if not staminaBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(staminaBar.fill, TweenInfo.new(0.2), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	staminaBar.label.Text = string.format("%d/%d", math.floor(current), math.floor(max))
end

function UIManager.updateHunger(current: number, max: number)
	if not hungerBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(hungerBar.fill, TweenInfo.new(0.2), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	hungerBar.label.Text = string.format("%d/%d", math.floor(current), math.floor(max))
end

function UIManager.updateThirst(current: number, max: number)
	if not thirstBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(thirstBar.fill, TweenInfo.new(0.2), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	thirstBar.label.Text = string.format("%d/%d", math.floor(current), math.floor(max))
end

function UIManager.updateXP(current: number, max: number)
	if not xpBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(xpBar.fill, TweenInfo.new(0.3), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	xpBar.label.Text = string.format("%d/%d XP", math.floor(current), math.floor(max))
end

function UIManager.updateGold(amount: number)
	if shopFrame then
		local goldLabel = shopFrame:FindFirstChild("TitleBar")
		if goldLabel then
			goldLabel = goldLabel:FindFirstChild("Gold")
			if goldLabel then
				goldLabel.Text = "💰 " .. tostring(amount)
			end
		end
	end
end

function UIManager.updateLevel(level: number)
	if levelLabel then
		levelLabel.Text = "Lv. " .. tostring(level)
	end
end

--========================================
-- Public API: Hotbar
--========================================

function UIManager.selectHotbarSlot(slotIndex: number)
	if hotbarSlots[selectedHotbarSlot] then
		hotbarSlots[selectedHotbarSlot].highlight.BackgroundTransparency = 1
	end
	
	selectedHotbarSlot = slotIndex
	if hotbarSlots[slotIndex] then
		hotbarSlots[slotIndex].highlight.BackgroundTransparency = 0.5
	end
end

function UIManager.refreshHotbar()
	local items = InventoryController.getItems()
	
	for i = 1, 8 do
		local slot = hotbarSlots[i]
		if slot then
			local item = items[i]
			if item and item.itemId then
				slot.countLabel.Text = item.count and ("x" .. item.count) or ""
			else
				slot.icon.Image = ""
				slot.countLabel.Text = ""
			end
		end
	end
end

--========================================
-- Public API: Inventory
--========================================

function UIManager.openInventory()
	if isInventoryOpen then return end
	isInventoryOpen = true
	inventoryFrame.Visible = true
	InputManager.setUIOpen(true)
	UIManager.refreshInventory()
	
	inventoryFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
	TweenService:Create(inventoryFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0.5, 0)
	}):Play()
end

function UIManager.closeInventory()
	if not isInventoryOpen then return end
	
	TweenService:Create(inventoryFrame, TweenInfo.new(0.15), {
		Position = UDim2.new(0.5, 0, 0.55, 0)
	}):Play()
	
	task.delay(0.15, function()
		isInventoryOpen = false
		inventoryFrame.Visible = false
		if not isQuestOpen and not isShopOpen and not isCraftingOpen then
			InputManager.setUIOpen(false)
		end
	end)
end

function UIManager.toggleInventory()
	if isInventoryOpen then
		UIManager.closeInventory()
	else
		UIManager.openInventory()
	end
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	
	for i, slot in pairs(inventorySlots) do
		local item = items[i]
		if item and item.itemId then
			slot.countLabel.Text = item.count and ("x" .. item.count) or ""
			slot.frame.BackgroundColor3 = COLORS.BG_SLOT
		else
			slot.icon.Image = ""
			slot.countLabel.Text = ""
			slot.frame.BackgroundColor3 = COLORS.BG_SLOT
		end
	end
	
	UIManager.refreshHotbar()
end

function UIManager.onInventorySlotClick(slotIndex: number)
	local items = InventoryController.getItems()
	local item = items[slotIndex]
	
	if item and item.itemId then
		print(string.format("[UIManager] Slot %d clicked: %s x%d", slotIndex, item.itemId, item.count or 1))
	end
end

--========================================
-- Public API: Quest
--========================================

function UIManager.openQuest()
	if isQuestOpen then return end
	isQuestOpen = true
	questFrame.Visible = true
	InputManager.setUIOpen(true)
	UIManager.refreshQuest()
	
	questFrame.Position = UDim2.new(1, 20, 0.5, 0)
	TweenService:Create(questFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
		Position = UDim2.new(1, -20, 0.5, 0)
	}):Play()
end

function UIManager.closeQuest()
	if not isQuestOpen then return end
	
	TweenService:Create(questFrame, TweenInfo.new(0.15), {
		Position = UDim2.new(1, 20, 0.5, 0)
	}):Play()
	
	task.delay(0.15, function()
		isQuestOpen = false
		questFrame.Visible = false
		if not isInventoryOpen and not isShopOpen and not isCraftingOpen then
			InputManager.setUIOpen(false)
		end
	end)
end

function UIManager.toggleQuest()
	if isQuestOpen then
		UIManager.closeQuest()
	else
		UIManager.openQuest()
	end
end

function UIManager.refreshQuest()
	local questList = questFrame:FindFirstChild("QuestList")
	if not questList then return end
	
	for _, child in pairs(questList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	local quests = QuestController.getActiveQuests()
	
	for i, quest in ipairs(quests) do
		local questItem = createFrame({
			name = "Quest" .. i,
			size = UDim2.new(1, -10, 0, 70),
			bgColor = COLORS.BG_SLOT,
			cornerRadius = 6,
			zIndex = 11,
			parent = questList,
		})
		questItem.LayoutOrder = i
		
		createLabel({
			name = "Title",
			size = UDim2.new(1, -10, 0, 22),
			position = UDim2.new(0, 8, 0, 5),
			text = quest.questId or "Unknown Quest",
			textSize = 13,
			font = FONTS.TITLE,
			alignX = Enum.TextXAlignment.Left,
			zIndex = 12,
			parent = questItem,
		})
		
		local progressText = ""
		if quest.progress then
			for key, value in pairs(quest.progress) do
				progressText = progressText .. string.format("%s: %d  ", key, value)
			end
		end
		
		createLabel({
			name = "Progress",
			size = UDim2.new(1, -10, 0, 18),
			position = UDim2.new(0, 8, 0, 28),
			text = progressText ~= "" and progressText or "진행 중...",
			textSize = 11,
			textColor = COLORS.TEXT_DIM,
			alignX = Enum.TextXAlignment.Left,
			zIndex = 12,
			parent = questItem,
		})
		
		local progressBar = createFrame({
			name = "ProgressBar",
			size = UDim2.new(1, -16, 0, 8),
			position = UDim2.new(0, 8, 1, -14),
			bgColor = COLORS.BG_DARK,
			cornerRadius = 4,
			zIndex = 12,
			parent = questItem,
		})
		
		createFrame({
			name = "Fill",
			size = UDim2.new(0.5, 0, 1, 0),
			bgColor = COLORS.XP,
			cornerRadius = 4,
			zIndex = 13,
			parent = progressBar,
		})
	end
	
	local listLayout = questList:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		questList.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
	end
end

--========================================
-- Public API: Shop
--========================================

function UIManager.openShop(shopId: string?)
	if isShopOpen then return end
	isShopOpen = true
	shopFrame.Visible = true
	InputManager.setUIOpen(true)
	
	shopFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
	TweenService:Create(shopFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0.5, 0)
	}):Play()
end

function UIManager.closeShop()
	if not isShopOpen then return end
	
	TweenService:Create(shopFrame, TweenInfo.new(0.15), {
		Position = UDim2.new(0.5, 0, 0.55, 0)
	}):Play()
	
	task.delay(0.15, function()
		isShopOpen = false
		shopFrame.Visible = false
		if not isInventoryOpen and not isQuestOpen and not isCraftingOpen then
			InputManager.setUIOpen(false)
		end
	end)
end

--========================================
-- Public API: Interact Prompt
--========================================

function UIManager.showInteractPrompt(text: string?)
	if interactPrompt then
		local label = interactPrompt:FindFirstChild("Text")
		if label then
			label.Text = text or "[E] 상호작용"
		end
		interactPrompt.Visible = true
	end
end

function UIManager.hideInteractPrompt()
	if interactPrompt then
		interactPrompt.Visible = false
	end
end

--========================================
-- Event Connections
--========================================

local function setupEventListeners()
	InventoryController.onChanged(function()
		if isInventoryOpen then
			UIManager.refreshInventory()
		end
		UIManager.refreshHotbar()
	end)
	
	ShopController.onGoldChanged(function(gold)
		UIManager.updateGold(gold)
	end)
	
	QuestController.onQuestUpdated(function()
		if isQuestOpen then
			UIManager.refreshQuest()
		end
	end)
	
	-- 숫자 키 1-8로 핫바 슬롯 선택
	InputManager.bindKey(Enum.KeyCode.One, "Hotbar1", function() UIManager.selectHotbarSlot(1) end)
	InputManager.bindKey(Enum.KeyCode.Two, "Hotbar2", function() UIManager.selectHotbarSlot(2) end)
	InputManager.bindKey(Enum.KeyCode.Three, "Hotbar3", function() UIManager.selectHotbarSlot(3) end)
	InputManager.bindKey(Enum.KeyCode.Four, "Hotbar4", function() UIManager.selectHotbarSlot(4) end)
	InputManager.bindKey(Enum.KeyCode.Five, "Hotbar5", function() UIManager.selectHotbarSlot(5) end)
	InputManager.bindKey(Enum.KeyCode.Six, "Hotbar6", function() UIManager.selectHotbarSlot(6) end)
	InputManager.bindKey(Enum.KeyCode.Seven, "Hotbar7", function() UIManager.selectHotbarSlot(7) end)
	InputManager.bindKey(Enum.KeyCode.Eight, "Hotbar8", function() UIManager.selectHotbarSlot(8) end)
end

--========================================
-- Initialization
--========================================

function UIManager.Init()
	if initialized then
		warn("[UIManager] Already initialized!")
		return
	end
	
	mainGui = Instance.new("ScreenGui")
	mainGui.Name = "GameUI"
	mainGui.ResetOnSpawn = false
	mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainGui.IgnoreGuiInset = false
	mainGui.Parent = playerGui
	
	createHUD()
	createHotbar()
	createInventoryUI()
	createQuestUI()
	createShopUI()
	createInteractPrompt()
	createKeyHints()
	
	setupEventListeners()
	
	UIManager.updateHealth(100, 100)
	UIManager.updateStamina(100, 100)
	UIManager.updateHunger(100, 100)
	UIManager.updateThirst(100, 100)
	UIManager.updateXP(0, 100)
	UIManager.updateLevel(1)
	UIManager.updateGold(0)
	
	initialized = true
	print("[UIManager] Initialized - All UI created")
end

return UIManager
