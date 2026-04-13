-- ShopUI.lua
-- Responsive split-layout shop UI: trader inventory on the left, player sell list on the right

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MaterialAttributeData"))

local C = Theme.Colors
local T = Theme.Transp

local ShopUI = {}
ShopUI.IsMobile = false
ShopUI.Refs = {
	Frame = nil,
	Main = nil,
	Title = nil,
	Subtitle = nil,
	GoldLabel = nil,
	TraderPanel = nil,
	PlayerPanel = nil,
	TraderScroll = nil,
	PlayerScroll = nil,
}

function ShopUI.SetVisible(visible)
	if ShopUI.Refs.Frame then
		ShopUI.Refs.Frame.Visible = visible
	end
end

function ShopUI.UpdateGold(gold)
	if ShopUI.Refs.GoldLabel then
		ShopUI.Refs.GoldLabel.Text = string.format("%d G", gold or 0)
	end
end

local function clearContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "ContentPadding" then
			child:Destroy()
		end
	end
end

local function resolveItemName(itemId: string): string
	local itemData = DataHelper.GetData("ItemData", itemId)
	return (itemData and itemData.name) or tostring(itemId)
end

local function formatAttributes(attributes: any): string
	if type(attributes) ~= "table" then
		return ""
	end

	local chunks = {}
	for attrId, attrLevel in pairs(attributes) do
		local attrInfo = MaterialAttributeData.getAttribute(attrId)
		if attrInfo then
			table.insert(chunks, string.format("%s Lv.%d", attrInfo.name, tonumber(attrLevel) or 1))
		end
	end

	table.sort(chunks)
	return table.concat(chunks, ", ")
end

local function makeSectionHeader(parent: Instance, title: string, subtitle: string?)
	local header = Utils.mkFrame({
		name = "SectionHeader",
		size = UDim2.new(1, 0, 0, ShopUI.IsMobile and 52 or 58),
		bg = C.BG_DARK,
		bgT = 0.14,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	Utils.mkLabel({
		text = title,
		size = UDim2.new(1, -18, 0, 24),
		pos = UDim2.new(0, 10, 0, 6),
		ts = ShopUI.IsMobile and 15 or 17,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	if subtitle and subtitle ~= "" then
		Utils.mkLabel({
			text = subtitle,
			size = UDim2.new(1, -18, 0, 18),
			pos = UDim2.new(0, 10, 0, 30),
			ts = ShopUI.IsMobile and 11 or 12,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Left,
			wrap = true,
			parent = header,
		})
	end

	return header
end

local function makeEmptyState(parent: Instance, text: string)
	local frame = Utils.mkFrame({
		name = "EmptyState",
		size = UDim2.new(1, 0, 0, ShopUI.IsMobile and 64 or 72),
		bg = C.BG_DARK,
		bgT = 0.26,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	Utils.mkLabel({
		text = text,
		size = UDim2.new(1, -20, 1, 0),
		pos = UDim2.new(0, 10, 0, 0),
		ts = ShopUI.IsMobile and 12 or 13,
		color = C.GRAY,
		wrap = true,
		parent = frame,
	})
end

local function makeItemRow(parent: Instance, itemId: string, nameText: string, detailText: string, priceText: string, accentText: string?, iconResolver: (string) -> string, actionLabel: string?, actionCallback: (() -> ())?)
	local rowHeight = ShopUI.IsMobile and 92 or 98
	local iconSize = ShopUI.IsMobile and 48 or 54
	local actionWidth = ShopUI.IsMobile and 72 or 88
	local priceWidth = ShopUI.IsMobile and 86 or 110
	local actionReservedWidth = actionCallback and actionWidth or 0
	local textRightPadding = 26 + actionReservedWidth + priceWidth

	local row = Utils.mkFrame({
		name = "ItemRow_" .. tostring(itemId),
		size = UDim2.new(1, 0, 0, rowHeight),
		bg = C.BG_PANEL_L,
		bgT = 0.12,
		r = 10,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	local iconWrap = Utils.mkFrame({
		name = "IconWrap",
		size = UDim2.new(0, iconSize, 0, iconSize),
		pos = UDim2.new(0, 12, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_SLOT,
		bgT = 0.08,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = row,
	})

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0.78, 0, 0.78, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconResolver and iconResolver(itemId) or ""
	icon.Parent = iconWrap

	Utils.mkLabel({
		text = nameText,
		size = UDim2.new(1, -iconSize - textRightPadding, 0, 24),
		pos = UDim2.new(0, iconSize + 24, 0, 10),
		ts = ShopUI.IsMobile and 14 or 16,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = row,
	})

	Utils.mkLabel({
		text = detailText,
		size = UDim2.new(1, -iconSize - textRightPadding, 0, 18),
		pos = UDim2.new(0, iconSize + 24, 0, 38),
		ts = ShopUI.IsMobile and 11 or 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = row,
	})

	if accentText and accentText ~= "" then
		Utils.mkLabel({
			text = accentText,
			size = UDim2.new(1, -iconSize - textRightPadding, 0, 18),
			pos = UDim2.new(0, iconSize + 24, 0, 60),
			ts = ShopUI.IsMobile and 11 or 12,
			color = C.GOLD,
			ax = Enum.TextXAlignment.Left,
			wrap = true,
			parent = row,
		})
	end

	Utils.mkLabel({
		text = priceText,
		size = UDim2.new(0, priceWidth, 0, 22),
		pos = UDim2.new(1, -(actionReservedWidth + 12), 0, 12),
		anchor = Vector2.new(1, 0),
		ts = ShopUI.IsMobile and 13 or 15,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Right,
		parent = row,
	})

	if actionCallback then
		Utils.mkBtn({
			text = actionLabel or "선택",
			size = UDim2.new(0, actionWidth, 0, ShopUI.IsMobile and 32 or 34),
			pos = UDim2.new(1, -12, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			bg = C.BTN,
			hbg = C.BTN_H,
			ts = ShopUI.IsMobile and 12 or 13,
			r = 8,
			parent = row,
			fn = actionCallback,
		})
	end

	return row
end

local function makeColumnPanel(parent: Instance, name: string, size: UDim2, layoutOrder: number): (Frame, ScrollingFrame)
	local panel = Utils.mkFrame({
		name = name,
		size = size,
		bg = C.BG_DARK,
		bgT = 0.1,
		r = 10,
		stroke = 1,
		strokeC = C.BORDER,
		parent = parent,
	})
	panel.LayoutOrder = layoutOrder

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, -16, 1, -16)
	scroll.Position = UDim2.new(0, 8, 0, 8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = ShopUI.IsMobile and 6 or 5
	scroll.ScrollBarImageColor3 = C.GRAY
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.Name = "ContentPadding"
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 2)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, ShopUI.IsMobile and 8 or 10)
	list.Parent = scroll

	return panel, scroll
end

local function populateTraderPane(scroll: Instance, shopInfo: any, iconResolver: (string) -> string, uiManager: any)
	clearContainer(scroll)

	local buyItems = (shopInfo and shopInfo.buyList) or {}
	local sellOnly = shopInfo and shopInfo.sellOnly == true
	makeSectionHeader(scroll, "교역상 판매 물품", sellOnly and "이 교역상은 판매보다 매입 중심입니다." or "교역상이 직접 판매하는 물품입니다.")

	if #buyItems == 0 then
		makeEmptyState(scroll, sellOnly and "이 교역상은 판매 물품이 없습니다." or "현재 구매할 수 있는 물품이 없습니다.")
		return
	end

	for _, item in ipairs(buyItems) do
		local stockText = (item.stock and item.stock >= 0) and string.format("재고 %d", item.stock) or "재고 무제한"
		makeItemRow(
			scroll,
			item.itemId,
			resolveItemName(item.itemId),
			stockText,
			string.format("%d G", tonumber(item.price) or 0),
			nil,
			iconResolver,
			"구매",
			function()
				uiManager.requestBuy(item.itemId)
			end
		)
	end
end

local function populatePlayerPane(scroll: Instance, shopInfo: any, playerItems: any, iconResolver: (string) -> string, uiManager: any)
	clearContainer(scroll)

	local sellQuotes = (shopInfo and shopInfo.sellQuotes) or {}
	local acceptAllItems = shopInfo and shopInfo.acceptAllItems == true
	local subtitle = acceptAllItems and "보유 중인 거의 모든 아이템을 현재 가격으로 판매할 수 있습니다." or "현재 상점이 받아주는 아이템과 판매 가격입니다."
	makeSectionHeader(scroll, "내 아이템 판매", subtitle)

	if #sellQuotes == 0 then
		makeEmptyState(scroll, "지금 판매 가능한 아이템이 없습니다.")
		return
	end

	for _, quote in ipairs(sellQuotes) do
		local playerItem = playerItems and playerItems[quote.slot]
		local itemId = (playerItem and playerItem.itemId) or quote.itemId
		local attrText = formatAttributes((playerItem and playerItem.attributes) or quote.attributes)
		local detailParts = {
			string.format("보유 %d개", quote.count or 1),
			string.format("슬롯 %d", quote.slot or 0),
		}

		if attrText ~= "" then
			table.insert(detailParts, attrText)
		end

		local accentText = nil
		if quote.unitPrice and quote.count and quote.count > 1 then
			accentText = string.format("개당 %d G", quote.unitPrice)
		elseif attrText ~= "" and quote.unitPrice then
			accentText = string.format("현재 매입가 %d G", quote.unitPrice)
		end

		makeItemRow(
			scroll,
			itemId,
			resolveItemName(itemId),
			table.concat(detailParts, " · "),
			string.format("%d G", quote.totalPrice or 0),
			accentText,
			iconResolver,
			"판매",
			function()
				uiManager.requestSell(quote.slot)
			end
		)
	end
end

function ShopUI.Refresh(shopInfo, playerItems, getItemIcon, _themeColors, uiManager)
	if ShopUI.Refs.Title then
		ShopUI.Refs.Title.Text = (shopInfo and shopInfo.name) or "교역상"
	end

	if ShopUI.Refs.Subtitle then
		local zoneName = shopInfo and shopInfo.zoneName
		local subtitle = (shopInfo and shopInfo.description) or "상점 정보를 확인하세요."
		if zoneName and zoneName ~= "" then
			subtitle = string.format("%s  |  지역: %s", subtitle, zoneName)
		end
		ShopUI.Refs.Subtitle.Text = subtitle
	end

	populateTraderPane(ShopUI.Refs.TraderScroll, shopInfo, getItemIcon, uiManager)
	populatePlayerPane(ShopUI.Refs.PlayerScroll, shopInfo, playerItems, getItemIcon, uiManager)
end

function ShopUI.Init(parent, UIManager, isMobile)
	ShopUI.IsMobile = isMobile == true

	ShopUI.Refs.Frame = Utils.mkFrame({
		name = "ShopMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.42,
		vis = false,
		parent = parent,
	})

	local main = Utils.mkWindow({
		name = "Main",
		size = ShopUI.IsMobile and UDim2.new(0.96, 0, 0.92, 0) or UDim2.new(0.9, 0, 0.84, 0),
		maxSize = ShopUI.IsMobile and Vector2.new(760, 980) or Vector2.new(1220, 780),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 8,
		stroke = 1.5,
		strokeC = C.BORDER,
		parent = ShopUI.Refs.Frame,
	})
	ShopUI.Refs.Main = main

	local topBarHeight = ShopUI.IsMobile and 88 or 78
	local topBar = Utils.mkFrame({
		name = "TopBar",
		size = UDim2.new(1, -28, 0, topBarHeight),
		pos = UDim2.new(0, 14, 0, 14),
		bgT = 1,
		parent = main,
	})

	ShopUI.Refs.Title = Utils.mkLabel({
		text = "교역상",
		size = UDim2.new(1, ShopUI.IsMobile and -48 or -220, 0, 28),
		pos = UDim2.new(0, 0, 0, 0),
		ts = ShopUI.IsMobile and 21 or 24,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = topBar,
	})

	ShopUI.Refs.Subtitle = Utils.mkLabel({
		text = "상점 정보를 확인하세요.",
		size = UDim2.new(1, ShopUI.IsMobile and -48 or -220, 0, 36),
		pos = UDim2.new(0, 0, 0, 30),
		ts = ShopUI.IsMobile and 11 or 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = topBar,
	})

	ShopUI.Refs.GoldLabel = Utils.mkLabel({
		text = "0 G",
		size = ShopUI.IsMobile and UDim2.new(1, -48, 0, 20) or UDim2.new(0, 180, 0, 24),
		pos = ShopUI.IsMobile and UDim2.new(0, 0, 1, -20) or UDim2.new(1, -54, 0, 2),
		anchor = ShopUI.IsMobile and Vector2.new(0, 1) or Vector2.new(1, 0),
		ts = ShopUI.IsMobile and 14 or 18,
		color = C.GOLD,
		ax = ShopUI.IsMobile and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		parent = topBar,
	})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		color = C.WHITE,
		ts = 22,
		fn = function()
			UIManager.closeShop()
		end,
		parent = topBar,
	})

	local content = Utils.mkFrame({
		name = "Content",
		size = UDim2.new(1, -28, 1, -(topBarHeight + 42)),
		pos = UDim2.new(0, 14, 1, -14),
		anchor = Vector2.new(0, 1),
		bgT = 1,
		parent = main,
	})

	local columns = Utils.mkFrame({
		name = "Columns",
		size = UDim2.new(1, 0, 1, 0),
		bgT = 1,
		parent = content,
	})

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = ShopUI.IsMobile and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, ShopUI.IsMobile and 10 or 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = columns

	local traderSize = ShopUI.IsMobile and UDim2.new(1, 0, 0.34, -5) or UDim2.new(0.42, -6, 1, 0)
	local playerSize = ShopUI.IsMobile and UDim2.new(1, 0, 0.66, -5) or UDim2.new(0.58, -6, 1, 0)

	ShopUI.Refs.TraderPanel, ShopUI.Refs.TraderScroll = makeColumnPanel(columns, "TraderPanel", traderSize, 1)
	ShopUI.Refs.PlayerPanel, ShopUI.Refs.PlayerScroll = makeColumnPanel(columns, "PlayerPanel", playerSize, 2)
end

return ShopUI
