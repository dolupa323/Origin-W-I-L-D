-- UIManager.lua
-- UI 관리 모듈 (모든 UI 생성 및 제어)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
-- Constants
--========================================
local COLORS = {
	PRIMARY = Color3.fromRGB(45, 45, 55),
	SECONDARY = Color3.fromRGB(35, 35, 45),
	ACCENT = Color3.fromRGB(80, 180, 120),
	DANGER = Color3.fromRGB(220, 80, 80),
	WARNING = Color3.fromRGB(220, 180, 80),
	TEXT = Color3.fromRGB(240, 240, 240),
	TEXT_DIM = Color3.fromRGB(180, 180, 180),
	HEALTH = Color3.fromRGB(220, 80, 80),
	STAMINA = Color3.fromRGB(80, 180, 220),
	HUNGER = Color3.fromRGB(220, 160, 80),
	GOLD = Color3.fromRGB(255, 215, 0),
}

--========================================
-- Private State
--========================================
local initialized = false
local mainGui = nil

-- UI 요소들
local hudFrame = nil
local inventoryFrame = nil
local questFrame = nil
local shopFrame = nil
local interactPrompt = nil

-- 상태
local isInventoryOpen = false
local isQuestOpen = false
local isShopOpen = false

-- HUD 바 참조
local healthBar = nil
local staminaBar = nil
local hungerBar = nil
local goldLabel = nil
local levelLabel = nil

-- 인벤토리 슬롯 참조
local inventorySlots = {}

--========================================
-- UI Creation Helpers
--========================================

local function createFrame(props)
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Frame"
	frame.Size = props.size or UDim2.new(0, 100, 0, 100)
	frame.Position = props.position or UDim2.new(0, 0, 0, 0)
	frame.AnchorPoint = props.anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = props.bgColor or COLORS.PRIMARY
	frame.BackgroundTransparency = props.bgTransparency or 0
	frame.BorderSizePixel = 0
	frame.Visible = props.visible ~= false
	frame.Parent = props.parent
	
	if props.cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.cornerRadius)
		corner.Parent = frame
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
	label.TextColor3 = props.textColor or COLORS.TEXT
	label.TextSize = props.textSize or 14
	label.Font = props.font or Enum.Font.GothamMedium
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	label.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	label.Parent = props.parent
	return label
end

local function createButton(props)
	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size or UDim2.new(0, 100, 0, 30)
	button.Position = props.position or UDim2.new(0, 0, 0, 0)
	button.AnchorPoint = props.anchor or Vector2.new(0, 0)
	button.BackgroundColor3 = props.bgColor or COLORS.ACCENT
	button.BorderSizePixel = 0
	button.Text = props.text or "Button"
	button.TextColor3 = props.textColor or COLORS.TEXT
	button.TextSize = props.textSize or 14
	button.Font = props.font or Enum.Font.GothamMedium
	button.Parent = props.parent
	
	if props.cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.cornerRadius)
		corner.Parent = button
	end
	
	if props.onClick then
		button.MouseButton1Click:Connect(props.onClick)
	end
	
	return button
end

local function createBar(props)
	local container = createFrame({
		name = props.name .. "Container",
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		bgColor = COLORS.SECONDARY,
		cornerRadius = 4,
		parent = props.parent,
	})
	
	local fill = createFrame({
		name = "Fill",
		size = UDim2.new(1, -4, 1, -4),
		position = UDim2.new(0, 2, 0, 2),
		bgColor = props.fillColor,
		cornerRadius = 2,
		parent = container,
	})
	
	local label = createLabel({
		name = "Label",
		size = UDim2.new(1, 0, 1, 0),
		text = props.text or "",
		textSize = 12,
		parent = container,
	})
	
	return container, fill, label
end

--========================================
-- HUD Creation
--========================================

local function createHUD()
	-- HUD 컨테이너 (화면 하단 좌측)
	hudFrame = createFrame({
		name = "HUD",
		size = UDim2.new(0, 250, 0, 120),
		position = UDim2.new(0, 20, 1, -20),
		anchor = Vector2.new(0, 1),
		bgColor = COLORS.PRIMARY,
		bgTransparency = 0.3,
		cornerRadius = 8,
		parent = mainGui,
	})
	
	-- 레벨/골드 표시 (상단)
	local topBar = createFrame({
		name = "TopBar",
		size = UDim2.new(1, -16, 0, 24),
		position = UDim2.new(0, 8, 0, 8),
		bgTransparency = 1,
		parent = hudFrame,
	})
	
	levelLabel = createLabel({
		name = "Level",
		size = UDim2.new(0.5, 0, 1, 0),
		text = "Lv. 1",
		textSize = 16,
		alignX = Enum.TextXAlignment.Left,
		parent = topBar,
	})
	
	goldLabel = createLabel({
		name = "Gold",
		size = UDim2.new(0.5, 0, 1, 0),
		position = UDim2.new(0.5, 0, 0, 0),
		text = "💰 0",
		textSize = 14,
		textColor = COLORS.GOLD,
		alignX = Enum.TextXAlignment.Right,
		parent = topBar,
	})
	
	-- 체력 바
	local _, hpFill, hpLabel = createBar({
		name = "Health",
		size = UDim2.new(1, -16, 0, 20),
		position = UDim2.new(0, 8, 0, 38),
		fillColor = COLORS.HEALTH,
		text = "100 / 100",
		parent = hudFrame,
	})
	healthBar = { fill = hpFill, label = hpLabel }
	
	-- 스태미나 바
	local _, stFill, stLabel = createBar({
		name = "Stamina",
		size = UDim2.new(1, -16, 0, 20),
		position = UDim2.new(0, 8, 0, 64),
		fillColor = COLORS.STAMINA,
		text = "100 / 100",
		parent = hudFrame,
	})
	staminaBar = { fill = stFill, label = stLabel }
	
	-- 배고픔 바
	local _, huFill, huLabel = createBar({
		name = "Hunger",
		size = UDim2.new(1, -16, 0, 20),
		position = UDim2.new(0, 8, 0, 90),
		fillColor = COLORS.HUNGER,
		text = "100 / 100",
		parent = hudFrame,
	})
	hungerBar = { fill = huFill, label = huLabel }
	
	-- 단축키 힌트 (우측 하단)
	local hints = createFrame({
		name = "Hints",
		size = UDim2.new(0, 200, 0, 80),
		position = UDim2.new(1, -20, 1, -20),
		anchor = Vector2.new(1, 1),
		bgColor = COLORS.PRIMARY,
		bgTransparency = 0.5,
		cornerRadius = 6,
		parent = mainGui,
	})
	
	createLabel({
		text = "[B] 인벤토리  [J] 퀘스트\n[E] 상호작용  [LMB] 공격",
		size = UDim2.new(1, -10, 1, -10),
		position = UDim2.new(0, 5, 0, 5),
		textSize = 12,
		textColor = COLORS.TEXT_DIM,
		parent = hints,
	})
end

--========================================
-- Inventory UI Creation
--========================================

local function createInventoryUI()
	-- 인벤토리 배경 (화면 중앙)
	inventoryFrame = createFrame({
		name = "Inventory",
		size = UDim2.new(0, 500, 0, 400),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.PRIMARY,
		bgTransparency = 0.1,
		cornerRadius = 12,
		visible = false,
		parent = mainGui,
	})
	
	-- 타이틀
	createLabel({
		name = "Title",
		size = UDim2.new(1, 0, 0, 40),
		text = "인벤토리",
		textSize = 20,
		parent = inventoryFrame,
	})
	
	-- 닫기 버튼
	createButton({
		name = "Close",
		size = UDim2.new(0, 30, 0, 30),
		position = UDim2.new(1, -35, 0, 5),
		text = "X",
		bgColor = COLORS.DANGER,
		cornerRadius = 4,
		onClick = function()
			UIManager.closeInventory()
		end,
		parent = inventoryFrame,
	})
	
	-- 슬롯 그리드 (5x4 = 20 슬롯)
	local slotsContainer = createFrame({
		name = "Slots",
		size = UDim2.new(1, -20, 1, -60),
		position = UDim2.new(0, 10, 0, 50),
		bgTransparency = 1,
		parent = inventoryFrame,
	})
	
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 80, 0, 80)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = slotsContainer
	
	for i = 1, 20 do
		local slot = createFrame({
			name = "Slot" .. i,
			bgColor = COLORS.SECONDARY,
			cornerRadius = 6,
			parent = slotsContainer,
		})
		slot.LayoutOrder = i
		
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(1, -10, 1, -25)
		icon.Position = UDim2.new(0, 5, 0, 5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = slot
		
		local countLabel = createLabel({
			name = "Count",
			size = UDim2.new(1, -4, 0, 18),
			position = UDim2.new(0, 2, 1, -20),
			text = "",
			textSize = 12,
			alignX = Enum.TextXAlignment.Right,
			parent = slot,
		})
		
		local nameLabel = createLabel({
			name = "Name",
			size = UDim2.new(1, 0, 0, 15),
			position = UDim2.new(0, 0, 1, -15),
			text = "",
			textSize = 10,
			textColor = COLORS.TEXT_DIM,
			parent = slot,
		})
		
		-- 클릭 버튼 (투명)
		local clickBtn = Instance.new("TextButton")
		clickBtn.Name = "ClickArea"
		clickBtn.Size = UDim2.new(1, 0, 1, 0)
		clickBtn.BackgroundTransparency = 1
		clickBtn.Text = ""
		clickBtn.Parent = slot
		
		clickBtn.MouseButton1Click:Connect(function()
			UIManager.onInventorySlotClick(i)
		end)
		
		inventorySlots[i] = {
			frame = slot,
			icon = icon,
			countLabel = countLabel,
			nameLabel = nameLabel,
		}
	end
end

--========================================
-- Quest UI Creation
--========================================

local function createQuestUI()
	questFrame = createFrame({
		name = "Quest",
		size = UDim2.new(0, 300, 0, 400),
		position = UDim2.new(1, -20, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bgColor = COLORS.PRIMARY,
		bgTransparency = 0.1,
		cornerRadius = 12,
		visible = false,
		parent = mainGui,
	})
	
	createLabel({
		name = "Title",
		size = UDim2.new(1, 0, 0, 40),
		text = "퀘스트",
		textSize = 20,
		parent = questFrame,
	})
	
	createButton({
		name = "Close",
		size = UDim2.new(0, 30, 0, 30),
		position = UDim2.new(1, -35, 0, 5),
		text = "X",
		bgColor = COLORS.DANGER,
		cornerRadius = 4,
		onClick = function()
			UIManager.closeQuest()
		end,
		parent = questFrame,
	})
	
	-- 퀘스트 목록 영역
	local questList = createFrame({
		name = "QuestList",
		size = UDim2.new(1, -20, 1, -60),
		position = UDim2.new(0, 10, 0, 50),
		bgTransparency = 1,
		parent = questFrame,
	})
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = questList
end

--========================================
-- Shop UI Creation
--========================================

local function createShopUI()
	shopFrame = createFrame({
		name = "Shop",
		size = UDim2.new(0, 600, 0, 450),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.PRIMARY,
		bgTransparency = 0.1,
		cornerRadius = 12,
		visible = false,
		parent = mainGui,
	})
	
	createLabel({
		name = "Title",
		size = UDim2.new(1, 0, 0, 40),
		text = "상점",
		textSize = 20,
		parent = shopFrame,
	})
	
	createButton({
		name = "Close",
		size = UDim2.new(0, 30, 0, 30),
		position = UDim2.new(1, -35, 0, 5),
		text = "X",
		bgColor = COLORS.DANGER,
		cornerRadius = 4,
		onClick = function()
			UIManager.closeShop()
		end,
		parent = shopFrame,
	})
end

--========================================
-- Interact Prompt
--========================================

local function createInteractPrompt()
	interactPrompt = createFrame({
		name = "InteractPrompt",
		size = UDim2.new(0, 200, 0, 50),
		position = UDim2.new(0.5, 0, 0.7, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgColor = COLORS.PRIMARY,
		bgTransparency = 0.3,
		cornerRadius = 8,
		visible = false,
		parent = mainGui,
	})
	
	createLabel({
		name = "Text",
		size = UDim2.new(1, 0, 1, 0),
		text = "[E] 상호작용",
		textSize = 16,
		parent = interactPrompt,
	})
end

--========================================
-- Public API: HUD Updates
--========================================

function UIManager.updateHealth(current: number, max: number)
	if not healthBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	healthBar.fill.Size = UDim2.new(ratio, -4, 1, -4)
	healthBar.label.Text = string.format("%d / %d", current, max)
end

function UIManager.updateStamina(current: number, max: number)
	if not staminaBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	staminaBar.fill.Size = UDim2.new(ratio, -4, 1, -4)
	staminaBar.label.Text = string.format("%d / %d", current, max)
end

function UIManager.updateHunger(current: number, max: number)
	if not hungerBar then return end
	local ratio = math.clamp(current / max, 0, 1)
	hungerBar.fill.Size = UDim2.new(ratio, -4, 1, -4)
	hungerBar.label.Text = string.format("%d / %d", current, max)
end

function UIManager.updateGold(amount: number)
	if goldLabel then
		goldLabel.Text = "💰 " .. tostring(amount)
	end
end

function UIManager.updateLevel(level: number)
	if levelLabel then
		levelLabel.Text = "Lv. " .. tostring(level)
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
end

function UIManager.closeInventory()
	isInventoryOpen = false
	inventoryFrame.Visible = false
	if not isQuestOpen and not isShopOpen then
		InputManager.setUIOpen(false)
	end
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
			slot.nameLabel.Text = item.itemId
			slot.countLabel.Text = item.count and ("x" .. item.count) or ""
			slot.frame.BackgroundColor3 = COLORS.SECONDARY
		else
			slot.nameLabel.Text = ""
			slot.countLabel.Text = ""
			slot.icon.Image = ""
			slot.frame.BackgroundColor3 = COLORS.SECONDARY
		end
	end
end

function UIManager.onInventorySlotClick(slotIndex: number)
	local items = InventoryController.getItems()
	local item = items[slotIndex]
	
	if item and item.itemId then
		print(string.format("[UIManager] Slot %d clicked: %s x%d", slotIndex, item.itemId, item.count or 1))
		-- TODO: 아이템 사용/장착/드롭 컨텍스트 메뉴
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
end

function UIManager.closeQuest()
	isQuestOpen = false
	questFrame.Visible = false
	if not isInventoryOpen and not isShopOpen then
		InputManager.setUIOpen(false)
	end
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
	
	-- 기존 퀘스트 항목 제거
	for _, child in pairs(questList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	local quests = QuestController.getActiveQuests()
	
	for i, quest in ipairs(quests) do
		local questItem = createFrame({
			name = "Quest" .. i,
			size = UDim2.new(1, 0, 0, 60),
			bgColor = COLORS.SECONDARY,
			cornerRadius = 6,
			parent = questList,
		})
		questItem.LayoutOrder = i
		
		createLabel({
			name = "Title",
			size = UDim2.new(1, -10, 0, 20),
			position = UDim2.new(0, 5, 0, 5),
			text = quest.questId or "Unknown Quest",
			textSize = 14,
			alignX = Enum.TextXAlignment.Left,
			parent = questItem,
		})
		
		-- 진행도 표시
		local progressText = ""
		if quest.progress then
			for key, value in pairs(quest.progress) do
				progressText = progressText .. string.format("%s: %d  ", key, value)
			end
		end
		
		createLabel({
			name = "Progress",
			size = UDim2.new(1, -10, 0, 20),
			position = UDim2.new(0, 5, 0, 30),
			text = progressText ~= "" and progressText or "진행 중...",
			textSize = 12,
			textColor = COLORS.TEXT_DIM,
			alignX = Enum.TextXAlignment.Left,
			parent = questItem,
		})
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
	-- TODO: 상점 데이터 로드 및 표시
end

function UIManager.closeShop()
	isShopOpen = false
	shopFrame.Visible = false
	if not isInventoryOpen and not isQuestOpen then
		InputManager.setUIOpen(false)
	end
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
	-- 인벤토리 변경 이벤트
	InventoryController.onChanged(function()
		if isInventoryOpen then
			UIManager.refreshInventory()
		end
	end)
	
	-- 골드 변경 이벤트
	ShopController.onGoldChanged(function(gold)
		UIManager.updateGold(gold)
	end)
	
	-- 퀘스트 변경 이벤트
	QuestController.onQuestUpdated(function()
		if isQuestOpen then
			UIManager.refreshQuest()
		end
	end)
end

--========================================
-- Initialization
--========================================

function UIManager.Init()
	if initialized then
		warn("[UIManager] Already initialized!")
		return
	end
	
	-- 메인 ScreenGui 생성
	mainGui = Instance.new("ScreenGui")
	mainGui.Name = "MainGui"
	mainGui.ResetOnSpawn = false
	mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainGui.Parent = playerGui
	
	-- UI 생성
	createHUD()
	createInventoryUI()
	createQuestUI()
	createShopUI()
	createInteractPrompt()
	
	-- 이벤트 연결
	setupEventListeners()
	
	-- 초기값 설정
	UIManager.updateHealth(100, 100)
	UIManager.updateStamina(100, 100)
	UIManager.updateHunger(100, 100)
	UIManager.updateGold(0)
	UIManager.updateLevel(1)
	
	initialized = true
	print("[UIManager] Initialized - All UI created")
end

return UIManager
