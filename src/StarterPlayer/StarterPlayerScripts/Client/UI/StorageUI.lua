-- StorageUI.lua
-- Storage / pal-bag UI with drag-and-drop, hover tooltip, and gold controls

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))
local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MaterialAttributeData"))

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local StorageUI = {}
StorageUI.IsMobile = false
local MAX_STORAGE_DISPLAY_SLOTS = 40
StorageUI.Refs = {
	Frame = nil,
	StorageGrid = nil,
	InventoryGrid = nil,
	StorageSlots = {},
	InventorySlots = {},
	Title = nil,
	CloseBtn = nil,
	StorageGoldLabel = nil,
	PlayerGoldLabel = nil,
	TooltipFrame = nil,
	TooltipTitle = nil,
	TooltipBody = nil,
	StorageGoldBtn = nil,
	PlayerGoldBtn = nil,
}

local function formatAttributes(attributes)
	if type(attributes) ~= "table" then
		return ""
	end

	local parts = {}
	for attrId, level in pairs(attributes) do
		local attrInfo = MaterialAttributeData.getAttribute(attrId)
		if attrInfo then
			table.insert(parts, string.format("%s Lv.%d", attrInfo.name, tonumber(level) or 1))
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function describeItem(itemData, item)
	if not item or not item.itemId then
		return "빈 슬롯"
	end

	local name = (itemData and itemData.name) or item.itemId
	local count = tonumber(item.count) or 1
	local lines = {
		string.format("%s", name),
		string.format("수량: %d", count),
	}

	local attrText = formatAttributes(item.attributes)
	if attrText ~= "" then
		table.insert(lines, "속성: " .. attrText)
	end

	if item.durability and itemData and itemData.durability then
		table.insert(lines, string.format("내구도: %d / %d", math.floor(item.durability), math.floor(itemData.durability)))
	end

	if itemData and itemData.description then
		table.insert(lines, itemData.description)
	end

	return table.concat(lines, "\n")
end

local function updateTooltip(title, body)
	if StorageUI.Refs.TooltipTitle then
		StorageUI.Refs.TooltipTitle.Text = title or "아이템 정보"
	end
	if StorageUI.Refs.TooltipBody then
		StorageUI.Refs.TooltipBody.Text = body or "슬롯 위에 마우스를 올리면 정보를 볼 수 있습니다."
	end
end

local function connectSlotInteractions(slot, index, slotType, UIManager)
	local fromType = (slotType == "Storage") and "storage" or "player"
	local pressStart = 0

	slot.click.Active = false

	slot.click.MouseEnter:Connect(function()
		if UIManager.onStorageSlotHover then
			UIManager.onStorageSlotHover(index, fromType, true)
		end
	end)

	slot.click.MouseLeave:Connect(function()
		if UIManager.onStorageSlotHover then
			UIManager.onStorageSlotHover(index, fromType, false)
		end
	end)

	slot.click.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressStart = tick()
			if UIManager.handleStorageDragStart then
				UIManager.handleStorageDragStart(index, fromType)
			end
		end
	end)

	slot.click.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local duration = tick() - pressStart
			if UIManager.isDragging and (not UIManager.isDragging()) and duration < 0.25 then
				UIManager._onStorageSlotClick(index, fromType)
			end
			pressStart = 0
		end
	end)
end

local function mkSlot(parent, index, slotType, UIManager)
	local slot = Utils.mkSlot({
		name = slotType .. "_" .. index,
		size = UDim2.new(0, 64, 0, 64),
		parent = parent,
	})
	connectSlotInteractions(slot, index, slotType, UIManager)
	return slot
end

local function buildPanel(parent, panelName, title, titleColor, isSmall)
	local panel = Utils.mkFrame({
		name = panelName,
		size = UDim2.new(0.5, -10, 1, 0), -- Always side-by-side
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		parent = parent,
	})
	panel.LayoutOrder = (panelName == "Left") and 1 or 2

	Utils.mkLabel({
		text = title,
		size = UDim2.new(1, -16, 0, 26),
		pos = UDim2.new(0, 10, 0, 6),
		color = titleColor,
		ts = 16,
		font = F.TITLE,
		ax = Enum.TextXAlignment.Left,
		parent = panel,
	})

	local goldWrap = Utils.mkFrame({
		name = "GoldWrap",
		size = UDim2.new(1, -16, 0, 62),
		pos = UDim2.new(0, 8, 0, 34),
		bg = C.BG_DARK,
		bgT = 0.18,
		r = 6,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = panel,
	})

	local goldLabel = Utils.mkLabel({
		text = "골드: 0",
		size = UDim2.new(1, -110, 0, 22),
		pos = UDim2.new(0, 10, 0, 8),
		ts = 14,
		color = C.GOLD,
		font = F.NUM,
		ax = Enum.TextXAlignment.Left,
		parent = goldWrap,
	})

	local goldDesc = Utils.mkLabel({
		text = "아이템과 별도로 보관되는 골드입니다.",
		size = UDim2.new(1, -20, 0, 16),
		pos = UDim2.new(0, 10, 0, 30),
		ts = 11,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		parent = goldWrap,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = panelName .. "Scroll"
	scroll.Size = UDim2.new(1, -8, 1, -104)
	scroll.Position = UDim2.new(0, 4, 0, 100)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ClipsDescendants = true
	scroll.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 60, 0, 60)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.Parent = scroll

	return panel, scroll, goldWrap, goldLabel, goldDesc
end

local function applyDurability(slot, item)
	if not slot or not slot.durBg then
		return
	end

	local itemData = item and item.itemId and DataHelper.GetData("ItemData", item.itemId) or nil
	if item and item.durability and itemData and itemData.durability then
		local ratio = math.clamp(item.durability / itemData.durability, 0, 1)
		slot.durBg.Visible = true
		slot.durFill.Size = UDim2.new(ratio, 0, 1, 0)
		if ratio > 0.5 then
			slot.durFill.BackgroundColor3 = Color3.fromRGB(120, 200, 80)
		elseif ratio > 0.2 then
			slot.durFill.BackgroundColor3 = Color3.fromRGB(230, 180, 60)
		else
			slot.durFill.BackgroundColor3 = Color3.fromRGB(200, 70, 50)
		end
	else
		slot.durBg.Visible = false
	end
end

function StorageUI.ShowTooltip(entry)
	if not entry then
		updateTooltip("아이템 정보", "슬롯 위에 마우스를 올리면 정보를 볼 수 있습니다.")
		return
	end

	if entry.kind == "gold" then
		updateTooltip(entry.title or "골드", string.format("보유 골드: %d\n상점, 토템 유지비, 거래에 사용하는 화폐입니다.", tonumber(entry.amount) or 0))
		return
	end

	local itemData = DataHelper.GetData("ItemData", entry.itemId)
	local name = (itemData and itemData.name) or tostring(entry.itemId)
	updateTooltip(name, describeItem(itemData, entry))
end

function StorageUI.HideTooltip()
	updateTooltip("아이템 정보", "슬롯 위에 마우스를 올리면 정보를 볼 수 있습니다.")
end

function StorageUI.Init(parent, UIManager, isMobile)
	StorageUI.IsMobile = isMobile == true
	local isSmall = StorageUI.IsMobile

	StorageUI.Refs.Frame = Utils.mkFrame({
		name = "StorageMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent,
	})

	local main = Utils.mkWindow({
		name = "StorageWindow",
		size = UDim2.new(0.85, 0, 0.88, 0), -- Proportional scale
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER,
		ratio = 1.38, -- Maintain storage aspect ratio
		parent = StorageUI.Refs.Frame,
	})

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(980, 760)
	sizeConstraint.Parent = main

	local header = Utils.mkFrame({ name = "Header", size = UDim2.new(1, 0, 0, 45), bgT = 1, parent = main })
	StorageUI.Refs.Title = Utils.mkLabel({
		text = "보관함",
		pos = UDim2.new(0, 20, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		ts = 20,
		font = F.TITLE,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	local closeBtnSize = isSmall and 44 or 36
	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, closeBtnSize, 0, closeBtnSize),
		pos = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = C.BTN,
		bgT = 0.5,
		ts = 20,
		color = C.WHITE,
		fn = function()
			UIManager.closeStorage()
		end,
		parent = header,
	})

	local tooltipHeight = isSmall and 86 or 94
	local content = Utils.mkFrame({
		name = "Content",
		size = UDim2.new(1, -20, 1, -(55 + tooltipHeight)),
		pos = UDim2.new(0, 10, 0, 45),
		bgT = 1,
		parent = main,
	})

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	if isSmall then
		list.FillDirection = Enum.FillDirection.Vertical
		list.VerticalAlignment = Enum.VerticalAlignment.Top
	else
		list.FillDirection = Enum.FillDirection.Horizontal
	end
	list.Parent = content

	local leftPanel, sScroll, storageGoldWrap, storageGoldLabel = buildPanel(content, "Left", "보관함 아이템", C.GOLD, isSmall)
	local rightPanel, iScroll, playerGoldWrap, playerGoldLabel = buildPanel(content, "Right", "내 소지품", C.WHITE, isSmall)
	StorageUI.Refs.StorageGrid = sScroll
	StorageUI.Refs.InventoryGrid = iScroll
	StorageUI.Refs.StorageGoldLabel = storageGoldLabel
	StorageUI.Refs.PlayerGoldLabel = playerGoldLabel

	StorageUI.Refs.StorageGoldBtn = Utils.mkBtn({
		text = "골드 인출",
		size = UDim2.new(0, isSmall and 82 or 94, 0, isSmall and 28 or 30),
		pos = UDim2.new(1, -10, 0, 8),
		anchor = Vector2.new(1, 0),
		bg = C.BTN,
		hbg = C.BTN_H,
		ts = isSmall and 11 or 12,
		r = 6,
		parent = storageGoldWrap,
		fn = function()
			UIManager.openStorageGoldModal("storage")
		end,
	})

	StorageUI.Refs.PlayerGoldBtn = Utils.mkBtn({
		text = "골드 보관",
		size = UDim2.new(0, isSmall and 82 or 94, 0, isSmall and 28 or 30),
		pos = UDim2.new(1, -10, 0, 8),
		anchor = Vector2.new(1, 0),
		bg = C.BTN,
		hbg = C.BTN_H,
		ts = isSmall and 11 or 12,
		r = 6,
		parent = playerGoldWrap,
		fn = function()
			UIManager.openStorageGoldModal("player")
		end,
	})

	for i = 1, MAX_STORAGE_DISPLAY_SLOTS do
		local slot = mkSlot(sScroll, i, "Storage", UIManager)
		StorageUI.Refs.StorageSlots[i] = slot
		slot.frame.Visible = false
	end

	for i = 1, Balance.MAX_INV_SLOTS do
		local slot = mkSlot(iScroll, i, "Inventory", UIManager)
		StorageUI.Refs.InventorySlots[i] = slot
	end

	local tooltip = Utils.mkFrame({
		name = "HoverTooltip",
		size = UDim2.new(1, -20, 0, tooltipHeight - 8),
		pos = UDim2.new(0, 10, 1, -10),
		anchor = Vector2.new(0, 1),
		bg = C.BG_DARK,
		bgT = 0.12,
		r = 6,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = main,
	})
	StorageUI.Refs.TooltipFrame = tooltip
	StorageUI.Refs.TooltipTitle = Utils.mkLabel({
		text = "아이템 정보",
		size = UDim2.new(1, -20, 0, 22),
		pos = UDim2.new(0, 10, 0, 8),
		ts = isSmall and 14 or 15,
		color = C.GOLD,
		font = F.TITLE,
		ax = Enum.TextXAlignment.Left,
		parent = tooltip,
	})
	StorageUI.Refs.TooltipBody = Utils.mkLabel({
		text = "슬롯 위에 마우스를 올리면 정보를 볼 수 있습니다.",
		size = UDim2.new(1, -20, 1, -34),
		pos = UDim2.new(0, 10, 0, 30),
		ts = isSmall and 11 or 12,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		ay = Enum.TextYAlignment.Top,
		wrap = true,
		parent = tooltip,
	})
end

function StorageUI.Refresh(storageData, inventoryData, playerGold, getItemIcon, UIManager, inventoryMaxSlots)
	if not StorageUI.Refs.Frame or not storageData then
		return
	end

	if StorageUI.Refs.StorageGoldLabel then
		StorageUI.Refs.StorageGoldLabel.Text = string.format("보관 골드: %d", tonumber(storageData.gold) or 0)
	end
	if StorageUI.Refs.PlayerGoldLabel then
		StorageUI.Refs.PlayerGoldLabel.Text = string.format("소지 골드: %d", tonumber(playerGold) or 0)
	end

	local maxSlots = storageData.maxSlots or Balance.STORAGE_SLOTS
	for i = 1, MAX_STORAGE_DISPLAY_SLOTS do
		local slot = StorageUI.Refs.StorageSlots[i]
		if i <= maxSlots then
			slot.frame.Visible = true
			slot.icon.Image = ""
			slot.icon.Visible = false
			slot.countLabel.Text = ""
			slot.countLabel.Visible = false
			slot.itemId = nil
			slot.durBg.Visible = false

			local item = nil
			for _, si in ipairs(storageData.slots or {}) do
				if si.slot == i then
					item = si
					break
				end
			end

			if item then
				slot.itemId = item.itemId
				slot.icon.Image = getItemIcon(item.itemId)
				slot.icon.Visible = true
				if (item.count or 1) > 1 then
					slot.countLabel.Text = "x" .. tostring(item.count)
					slot.countLabel.Visible = true
				end
				applyDurability(slot, item)
			end
		else
			slot.frame.Visible = false
		end
	end

	local activeInventorySlots = inventoryMaxSlots or Balance.BASE_INV_SLOTS
	for i = 1, Balance.MAX_INV_SLOTS do
		local slot = StorageUI.Refs.InventorySlots[i]
		slot.frame.Visible = i <= activeInventorySlots
		slot.icon.Image = ""
		slot.icon.Visible = false
		slot.countLabel.Text = ""
		slot.countLabel.Visible = false
		slot.itemId = nil
		slot.durBg.Visible = false

		local item = inventoryData[i]
		if item then
			slot.itemId = item.itemId
			slot.icon.Image = getItemIcon(item.itemId)
			slot.icon.Visible = true
			if (item.count or 1) > 1 then
				slot.countLabel.Text = "x" .. tostring(item.count)
				slot.countLabel.Visible = true
			end
			applyDurability(slot, item)
		end
	end

	if UIManager and UIManager.getHoveredStorageSlotInfo then
		local hoverInfo = UIManager.getHoveredStorageSlotInfo()
		if hoverInfo then
			StorageUI.ShowTooltip(hoverInfo)
		end
	end
end

return StorageUI
