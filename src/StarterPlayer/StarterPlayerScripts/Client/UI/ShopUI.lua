-- ShopUI.lua
-- Durango Style 상점 UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local ShopUI = {}
ShopUI.Refs = {
	Frame = nil,
	Title = nil,
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
		ShopUI.Refs.GoldLabel.Text = "💰 " .. string.format("%d", gold)
	end
end

function ShopUI.Refresh(shopItems, playerItems, getItemIcon, C, UIManager)
	-- Buy Tab
	local buyScroll = ShopUI.Refs.TabBuy
	for _, ch in pairs(buyScroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end
	for _, item in ipairs(shopItems) do
		local slot = Utils.mkSlot({name = item.itemId, r = 2, bgT = 0.3, strokeC = C.BORDER_DIM, parent = buyScroll})
		slot.icon.Image = getItemIcon(item.itemId)
		Utils.mkLabel({text = item.price .. " G", size = UDim2.new(1, 0, 0, 20), pos = UDim2.new(0, 0, 1, 0), anchor = Vector2.new(0, 1), ts = 10, color = C.GOLD, parent = slot.frame})
		slot.click.MouseButton1Click:Connect(function() UIManager.requestBuy(item.itemId) end)
	end

	-- Sell Tab
	local sellScroll = ShopUI.Refs.TabSell
	for _, ch in pairs(sellScroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end
	for i, item in pairs(playerItems) do
		if item and item.itemId then
			local slot = Utils.mkSlot({name = "Sell"..i, r = 2, bgT = 0.3, strokeC = C.BORDER_DIM, parent = sellScroll})
			slot.icon.Image = getItemIcon(item.itemId)
			slot.countLabel.Text = (item.count > 1) and ("x"..item.count) or ""
			slot.click.MouseButton1Click:Connect(function() UIManager.requestSell(i) end)
		end
	end
end

function ShopUI.Init(parent, UIManager)
	-- Background Dim
	ShopUI.Refs.Frame = Utils.mkFrame({
		name = "ShopMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.6,
		vis = false,
		parent = parent
	})
	
	-- Main Panel
	local main = Utils.mkFrame({
		name = "Main",
		size = UDim2.new(0.85, 0, 0.8, 0),
		maxSize = Vector2.new(1150, 650),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.2,
		r = 4,
		stroke = 1,
		parent = ShopUI.Refs.Frame
	})

	-- Header
	local topBar = Utils.mkFrame({name="TopBar", size=UDim2.new(1, -40, 0, 50), pos=UDim2.new(0, 20, 0, 15), bgT=1, parent=main})
	ShopUI.Refs.Title = Utils.mkLabel({text="섬 상점", ts=24, bold=true, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=topBar})
	ShopUI.Refs.GoldLabel = Utils.mkLabel({text="💰 0", pos=UDim2.new(0, 100, 0, 0), size=UDim2.new(0, 200, 1, 0), ts=18, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=topBar})
	
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1,0), bgT=1, color=C.WHITE, ts=26, fn=function() UIManager.closeShop() end, parent=topBar})

	-- Tab Switchers (Durango Style Tabs)
	local tabContainer = Utils.mkFrame({size=UDim2.new(0, 300, 0, 40), pos=UDim2.new(0, 20, 0, 70), bgT=1, parent=main})
	local tabList = Instance.new("UIListLayout"); tabList.FillDirection = Enum.FillDirection.Horizontal; tabList.Padding = UDim.new(0, 10); tabList.Parent = tabContainer
	
	ShopUI.Refs.BtnBuyTab = Utils.mkBtn({text="구매", size=UDim2.new(0, 140, 0, 40), bg=C.GOLD_SEL, ts=14, bold=true, r=4, parent=tabContainer})
	ShopUI.Refs.BtnSellTab = Utils.mkBtn({text="판매", size=UDim2.new(0, 140, 0, 40), bg=C.BTN, ts=14, bold=true, r=4, parent=tabContainer})

	-- Content area
	local content = Utils.mkFrame({size=UDim2.new(1, -40, 1, -130), pos=UDim2.new(0, 20, 1, -20), anchor=Vector2.new(0, 1), bgT=1, clips=true, parent=main})
	
	local function mkScroll(name)
		local s = Instance.new("ScrollingFrame")
		s.Name = name; s.Size = UDim2.new(1, 0, 1, 0); s.BackgroundTransparency = 1; s.BorderSizePixel = 0; s.ScrollBarThickness = 4; s.ScrollBarImageColor3 = C.GRAY; s.Parent = content; s.AutomaticCanvasSize = Enum.AutomaticSize.Y
		local g = Instance.new("UIGridLayout"); g.CellSize = UDim2.new(0, 85, 0, 85); g.CellPadding = UDim2.new(0, 10, 0, 10); g.Parent = s
		local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,8); pad.PaddingTop = UDim.new(0,8); pad.PaddingRight = UDim.new(0,8); pad.PaddingBottom = UDim.new(0,8); pad.Parent = s
		s.ClipsDescendants = false
		return s
	end
	
	ShopUI.Refs.TabBuy = mkScroll("BuyScroll")
	ShopUI.Refs.TabSell = mkScroll("SellScroll")
	ShopUI.Refs.TabSell.Visible = false
	
	-- Tab Logic
	ShopUI.Refs.BtnBuyTab.MouseButton1Click:Connect(function()
		ShopUI.Refs.BtnBuyTab.BackgroundColor3 = C.GOLD_SEL
		ShopUI.Refs.BtnSellTab.BackgroundColor3 = C.BTN
		ShopUI.Refs.TabBuy.Visible = true; ShopUI.Refs.TabSell.Visible = false
	end)
	ShopUI.Refs.BtnSellTab.MouseButton1Click:Connect(function()
		ShopUI.Refs.BtnSellTab.BackgroundColor3 = C.GOLD_SEL
		ShopUI.Refs.BtnBuyTab.BackgroundColor3 = C.BTN
		ShopUI.Refs.TabSell.Visible = true; ShopUI.Refs.TabBuy.Visible = false
	end)
end

return ShopUI
