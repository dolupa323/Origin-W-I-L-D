-- ShopUI.lua
-- Responsive shop UI with buy/sell catalogs and quote preview

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MaterialAttributeData"))

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local ShopUI = {}
ShopUI.IsMobile = false
ShopUI.Refs = {
	Frame = nil,
	Main = nil,
	Title = nil,
	Subtitle = nil,
	GoldLabel = nil,
	BtnBuyTab = nil,
	BtnSellTab = nil,
	TabBuy = nil,
	TabSell = nil,
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

local function buildItemCountMap(playerItems: any): {[string]: number}
	local counts = {}
	for _, item in pairs(playerItems or {}) do
		if item and item.itemId then
			counts[item.itemId] = (counts[item.itemId] or 0) + (item.count or 1)
		end
	end
	return counts
end

local function buildQuoteSummaryMap(sellQuotes: {any}): {[string]: any}
	local summary = {}
	for _, quote in ipairs(sellQuotes or {}) do
		local itemId = quote.itemId
		if itemId then
			local bucket = summary[itemId]
			if not bucket then
				bucket = {
					count = 0,
					totalPrice = 0,
					minUnitPrice = quote.unitPrice or 0,
					maxUnitPrice = quote.unitPrice or 0,
				}
				summary[itemId] = bucket
			end

			local unitPrice = quote.unitPrice or 0
			bucket.count += quote.count or 1
			bucket.totalPrice += quote.totalPrice or unitPrice
			bucket.minUnitPrice = math.min(bucket.minUnitPrice, unitPrice)
			bucket.maxUnitPrice = math.max(bucket.maxUnitPrice, unitPrice)
		end
	end
	return summary
end

local function setActiveTab(showBuy, themeColors)
	if not ShopUI.Refs.TabBuy or not ShopUI.Refs.TabSell or not ShopUI.Refs.BtnBuyTab or not ShopUI.Refs.BtnSellTab then
		return
	end

	ShopUI.Refs.TabBuy.Visible = showBuy
	ShopUI.Refs.TabSell.Visible = not showBuy
	ShopUI.Refs.BtnBuyTab.BackgroundColor3 = showBuy and themeColors.BTN_H or themeColors.BTN
	ShopUI.Refs.BtnSellTab.BackgroundColor3 = showBuy and themeColors.BTN or themeColors.BTN_H
end

local function makeSectionHeader(parent: Instance, title: string, subtitle: string?)
	local header = Utils.mkFrame({
		name = "SectionHeader",
		size = UDim2.new(1, 0, 0, ShopUI.IsMobile and 48 or 52),
		bg = C.BG_DARK,
		bgT = 0.15,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	Utils.mkLabel({
		text = title,
		size = UDim2.new(1, -20, 0, 22),
		pos = UDim2.new(0, 12, 0, 6),
		ts = ShopUI.IsMobile and 16 or 18,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	if subtitle and subtitle ~= "" then
		Utils.mkLabel({
			text = subtitle,
			size = UDim2.new(1, -20, 0, 16),
			pos = UDim2.new(0, 12, 0, 26),
			ts = ShopUI.IsMobile and 11 or 12,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Left,
			parent = header,
		})
	end

	return header
end

local function makeEmptyState(parent: Instance, text: string)
	local frame = Utils.mkFrame({
		name = "EmptyState",
		size = UDim2.new(1, 0, 0, ShopUI.IsMobile and 60 or 68),
		bg = C.BG_DARK,
		bgT = 0.3,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	Utils.mkLabel({
		text = text,
		size = UDim2.new(1, -20, 1, 0),
		pos = UDim2.new(0, 10, 0, 0),
		ts = ShopUI.IsMobile and 13 or 14,
		color = C.GRAY,
		wrap = true,
		parent = frame,
	})
end

local function makeItemRow(parent: Instance, itemId: string, nameText: string, detailText: string, priceText: string, accentText: string?, iconResolver: (string) -> string, actionLabel: string?, actionCallback: (() -> ())?)
	local rowHeight = ShopUI.IsMobile and 86 or 92
	local iconSize = ShopUI.IsMobile and 48 or 56
	local actionWidth = ShopUI.IsMobile and 76 or 92

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
		pos = UDim2.new(0, 14, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_SLOT,
		bgT = 0.1,
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

	local actionReservedWidth = actionCallback and actionWidth or 0
	local priceWidth = ShopUI.IsMobile and 92 or 120
	local textRightPadding = 24 + actionReservedWidth + priceWidth

	Utils.mkLabel({
		text = nameText,
		size = UDim2.new(1, -iconSize - textRightPadding, 0, 24),
		pos = UDim2.new(0, iconSize + 28, 0, 12),
		ts = ShopUI.IsMobile and 15 or 16,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = row,
	})

	Utils.mkLabel({
		text = detailText,
		size = UDim2.new(1, -iconSize - textRightPadding, 0, 18),
		pos = UDim2.new(0, iconSize + 28, 0, 38),
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
			pos = UDim2.new(0, iconSize + 28, 0, 58),
			ts = ShopUI.IsMobile and 11 or 12,
			color = C.GOLD,
			ax = Enum.TextXAlignment.Left,
			wrap = true,
			parent = row,
		})
	end

	Utils.mkLabel({
		text = priceText,
		size = UDim2.new(0, priceWidth, 0, 24),
		pos = UDim2.new(1, -(actionReservedWidth + 18), 0, 12),
		anchor = Vector2.new(1, 0),
		ts = ShopUI.IsMobile and 14 or 16,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Right,
		parent = row,
	})

	if actionCallback then
		Utils.mkBtn({
			text = actionLabel or "선택",
			size = UDim2.new(0, actionWidth, 0, ShopUI.IsMobile and 32 or 34),
			pos = UDim2.new(1, -14, 0.5, 0),
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

local function populateBuyTab(scroll: Instance, buyItems: {any}, iconResolver: (string) -> string, uiManager: any)
	clearContainer(scroll)
	makeSectionHeader(scroll, "판매 품목", "이 상점에서 바로 구매할 수 있는 물품입니다.")

	if #buyItems == 0 then
		makeEmptyState(scroll, "현재 판매 중인 품목이 없습니다.")
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

local function populateSellTab(scroll: Instance, shopInfo: any, playerItems: any, iconResolver: (string) -> string, uiManager: any)
	clearContainer(scroll)

	local sellEntries = (shopInfo and shopInfo.sellList) or {}
	local sellQuotes = (shopInfo and shopInfo.sellQuotes) or {}
	local itemCounts = buildItemCountMap(playerItems)
	local quoteSummaries = buildQuoteSummaryMap(sellQuotes)

	makeSectionHeader(scroll, "매입 품목", "이 상점이 받아주는 부산물과 기본 매입가입니다.")

	if #sellEntries == 0 then
		makeEmptyState(scroll, "이 상점은 현재 매입 품목이 없습니다.")
	else
		for _, entry in ipairs(sellEntries) do
			local summary = quoteSummaries[entry.itemId]
			local ownedCount = itemCounts[entry.itemId] or 0
			local detailText = ownedCount > 0 and string.format("보유 %d개", ownedCount) or "보유 없음"
			local accentText = nil

			if summary then
				if summary.minUnitPrice == summary.maxUnitPrice then
					accentText = string.format("현재 매입가 %d G / 모두 판매 시 %d G", summary.maxUnitPrice, summary.totalPrice)
				else
					accentText = string.format("현재 매입가 %d-%d G / 모두 판매 시 %d G", summary.minUnitPrice, summary.maxUnitPrice, summary.totalPrice)
				end
			end

			makeItemRow(
				scroll,
				entry.itemId,
				resolveItemName(entry.itemId),
				detailText,
				string.format("기준 %d G", tonumber(entry.price) or 0),
				accentText,
				iconResolver
			)
		end
	end

	makeSectionHeader(scroll, "현재 판매 가능", "인벤토리에서 실제로 판매할 수 있는 슬롯별 목록입니다.")

	if #sellQuotes == 0 then
		makeEmptyState(scroll, "지금 이 상점에 팔 수 있는 아이템이 인벤토리에 없습니다.")
		return
	end

	for _, quote in ipairs(sellQuotes) do
		local playerItem = playerItems and playerItems[quote.slot]
		local itemId = (playerItem and playerItem.itemId) or quote.itemId
		local attrText = formatAttributes(playerItem and playerItem.attributes or quote.attributes)
		local detailParts = {
			string.format("슬롯 %d", quote.slot),
			string.format("수량 %d", quote.count or 1),
		}
		if attrText ~= "" then
			table.insert(detailParts, attrText)
		end

		makeItemRow(
			scroll,
			itemId,
			resolveItemName(itemId),
			table.concat(detailParts, " · "),
			string.format("%d G", quote.totalPrice or 0),
			(quote.unitPrice and quote.count and quote.count > 1) and string.format("개당 %d G", quote.unitPrice) or nil,
			iconResolver,
			"판매",
			function()
				uiManager.requestSell(quote.slot)
			end
		)
	end
end

function ShopUI.Refresh(shopInfo, playerItems, getItemIcon, themeColors, uiManager)
	local buyItems = (shopInfo and shopInfo.buyList) or {}
	local isSellOnly = shopInfo and shopInfo.sellOnly == true

	if ShopUI.Refs.Title then
		ShopUI.Refs.Title.Text = (shopInfo and shopInfo.name) or "섬 상점"
	end

	if ShopUI.Refs.Subtitle then
		ShopUI.Refs.Subtitle.Text = (shopInfo and shopInfo.description) or "상점 정보를 확인하세요."
	end

	if ShopUI.Refs.BtnBuyTab and ShopUI.Refs.BtnSellTab then
		ShopUI.Refs.BtnBuyTab.Visible = not isSellOnly
		ShopUI.Refs.BtnSellTab.Text = isSellOnly and "매입 품목" or "매입 / 판매"
	end

	setActiveTab(not isSellOnly, themeColors)
	populateBuyTab(ShopUI.Refs.TabBuy, buyItems, getItemIcon, uiManager)
	populateSellTab(ShopUI.Refs.TabSell, shopInfo, playerItems, getItemIcon, uiManager)
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
		size = ShopUI.IsMobile and UDim2.new(0.96, 0, 0.9, 0) or UDim2.new(0.88, 0, 0.82, 0),
		maxSize = ShopUI.IsMobile and Vector2.new(760, 900) or Vector2.new(1180, 760),
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

	local topBarHeight = ShopUI.IsMobile and 86 or 74
	local topBar = Utils.mkFrame({
		name = "TopBar",
		size = UDim2.new(1, -28, 0, topBarHeight),
		pos = UDim2.new(0, 14, 0, 14),
		bgT = 1,
		parent = main,
	})

	ShopUI.Refs.Title = Utils.mkLabel({
		text = "섬 상점",
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
		size = UDim2.new(1, ShopUI.IsMobile and -48 or -220, 0, 18),
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
		pos = ShopUI.IsMobile and UDim2.new(0, 0, 0, 56) or UDim2.new(1, -54, 0, 2),
		anchor = ShopUI.IsMobile and Vector2.new(0, 0) or Vector2.new(1, 0),
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

	local tabContainer = Utils.mkFrame({
		name = "TabContainer",
		size = UDim2.new(1, -28, 0, ShopUI.IsMobile and 42 or 46),
		pos = UDim2.new(0, 14, 0, 14 + topBarHeight + 6),
		bgT = 1,
		parent = main,
	})

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabContainer

	ShopUI.Refs.BtnBuyTab = Utils.mkBtn({
		text = "판매 품목",
		size = UDim2.new(0.5, -4, 1, 0),
		bg = C.BTN_H,
		ts = ShopUI.IsMobile and 12 or 14,
		bold = true,
		r = 6,
		parent = tabContainer,
	})

	ShopUI.Refs.BtnSellTab = Utils.mkBtn({
		text = "매입 / 판매",
		size = UDim2.new(0.5, -4, 1, 0),
		bg = C.BTN,
		ts = ShopUI.IsMobile and 12 or 14,
		bold = true,
		r = 6,
		parent = tabContainer,
	})

	local content = Utils.mkFrame({
		name = "Content",
		size = UDim2.new(1, -28, 1, -(topBarHeight + 84)),
		pos = UDim2.new(0, 14, 1, -14),
		anchor = Vector2.new(0, 1),
		bgT = 1,
		clips = true,
		parent = main,
	})

	local function makeScroll(name: string): ScrollingFrame
		local s = Instance.new("ScrollingFrame")
		s.Name = name
		s.Size = UDim2.new(1, 0, 1, 0)
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.ScrollBarThickness = ShopUI.IsMobile and 6 or 5
		s.ScrollBarImageColor3 = C.GRAY
		s.AutomaticCanvasSize = Enum.AutomaticSize.Y
		s.CanvasSize = UDim2.new()
		s.Parent = content

		local pad = Instance.new("UIPadding")
		pad.Name = "ContentPadding"
		pad.PaddingLeft = UDim.new(0, ShopUI.IsMobile and 4 or 6)
		pad.PaddingRight = UDim.new(0, ShopUI.IsMobile and 4 or 6)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.Parent = s

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Padding = UDim.new(0, ShopUI.IsMobile and 8 or 10)
		list.Parent = s

		return s
	end

	ShopUI.Refs.TabBuy = makeScroll("BuyScroll")
	ShopUI.Refs.TabSell = makeScroll("SellScroll")
	ShopUI.Refs.TabSell.Visible = false

	ShopUI.Refs.BtnBuyTab.MouseButton1Click:Connect(function()
		setActiveTab(true, C)
	end)

	ShopUI.Refs.BtnSellTab.MouseButton1Click:Connect(function()
		setActiveTab(false, C)
	end)
end

return ShopUI
