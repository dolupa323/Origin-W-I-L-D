-- InventoryUI.lua
-- 상세 정보창 오버플로우 해결 & 수량 입력 모달 추가 버전

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local InventoryUI = {}

InventoryUI.Refs = {
	Frame = nil,
	Tabs = {}, 
	MainFrame = nil,
	
	BagFrame = nil,
	GridScroll = nil,
	Slots = {},
	WeightFill = nil,
	WeightText = nil,
	
	StatusFrame = nil,
	StatPoints = nil,
	StatLines = {},
	
	CraftFrame = nil,
	CraftGrid = nil,
	
	Detail = {
		Frame = nil,
		Name = nil,
		PreviewIcon = nil,
		Weight = nil,
		Count = nil,
		Mats = nil,
		BtnUse = nil,
		BtnDrop = nil,
		BtnCraft = nil,
	},
	
	-- Drop Modal
	DropModal = {
		Frame = nil,
		Input = nil,
		BtnConfirm = nil,
		BtnCancel = nil,
		MaxLabel = nil,
	}
}

function InventoryUI.Init(parent, UIManager)
	-- Background Dim
	InventoryUI.Refs.Frame = Utils.mkFrame({
		name = "CharacterMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.6,
		vis = false,
		parent = parent
	})
	
	-- Main Panel
	local main = Utils.mkFrame({
		name = "Main",
		size = UDim2.new(0.9, 0, 0.85, 0),
		maxSize = Vector2.new(1200, 700),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.3, -- Durango는 매우 어둡고 투명함
		r = 4,
		stroke = 1.5,
		parent = InventoryUI.Refs.Frame
	})
	InventoryUI.Refs.MainFrame = main

	-- [TOP] Header: Bag Name & Currency
	local topBar = Utils.mkFrame({name="TopBar", size=UDim2.new(1, -40, 0, 50), pos=UDim2.new(0, 20, 0, 15), bgT=1, parent=main})
	
	local bagTitleContainer = Utils.mkFrame({size=UDim2.new(0.4, 0, 1, 0), bgT=1, parent=topBar})
	local bagList = Instance.new("UIListLayout"); bagList.FillDirection = Enum.FillDirection.Horizontal; bagList.VerticalAlignment = Enum.VerticalAlignment.Center; bagList.Padding = UDim.new(0, 10); bagList.Parent = bagTitleContainer
	
	Utils.mkLabel({text="가방", ts=24, bold=true, color=C.WHITE, parent=bagTitleContainer})
	InventoryUI.Refs.WeightText = Utils.mkLabel({text="0 / 100", ts=18, color=C.GRAY, parent=bagTitleContainer})
	
	-- Currency (Top Right)
	local currencyContainer = Utils.mkFrame({size=UDim2.new(0, 300, 1, 0), pos=UDim2.new(1, -50, 0, 0), anchor=Vector2.new(1,0), bgT=1, parent=topBar})
	local currList = Instance.new("UIListLayout"); currList.FillDirection = Enum.FillDirection.Horizontal; currList.HorizontalAlignment = Enum.HorizontalAlignment.Right; currList.VerticalAlignment = Enum.VerticalAlignment.Center; currList.Padding = UDim.new(0, 20); currList.Parent = currencyContainer
	
	local closeBtn = Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), bgT=1, color=C.WHITE, ts=26, fn=function() UIManager.closeInventory() end, parent=currencyContainer})
	closeBtn.LayoutOrder = 10
	
	-- Content Area
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -40, 1, -80), pos=UDim2.new(0, 20, 1, -15), anchor=Vector2.new(0, 1), bgT=1, parent=main})
	
	------------------------------------------------------------
	-- LEFT: Item Grid (70%)
	------------------------------------------------------------
	local bagFrame = Utils.mkFrame({name="BagTab", size=UDim2.new(0.7, -10, 1, 0), bgT=1, clips=true, parent=content})
	InventoryUI.Refs.BagFrame = bagFrame
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = C.GRAY
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = bagFrame
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 80, 0, 80)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	-- Padding for borders (UIStroke)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll
	scroll.ClipsDescendants = false -- Allow UIStroke to render outside the scroll boundary into bagFrame
	
	for i=1, 40 do
		local slot = Utils.mkSlot({name="Slot"..i, r=2, bgT=0.3, stroke=1, strokeC=C.BORDER_DIM, parent=scroll})
		slot.frame.LayoutOrder = i
		
		-- Click Handler
		slot.click.MouseButton1Click:Connect(function() UIManager._onInvSlotClick(i) end)
		
		-- Drag Handler Connection
		slot.click.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if UIManager.handleDragStart then UIManager.handleDragStart(i, input) end
			end
		end)
		
		InventoryUI.Refs.Slots[i] = slot
	end

	------------------------------------------------------------
	-- RIGHT: Item Detail Panel (30%)
	------------------------------------------------------------
	local detail = Utils.mkFrame({
		name = "Detail", 
		size = UDim2.new(0.3, 0, 1, 0), 
		pos = UDim2.new(1, 0, 0, 0), 
		anchor = Vector2.new(1, 0), 
		bg = C.BG_PANEL_L, 
		bgT = 0.2, 
		stroke = 1, 
		strokeC = C.BORDER_DIM,
		parent = content
	})
	InventoryUI.Refs.Detail.Frame = detail
	
	-- Item Name Header
	local dHeader = Utils.mkFrame({size=UDim2.new(1, 0, 0, 50), pos=UDim2.new(0, 0, 0, 0), bg=C.GOLD_SEL, bgT=0.1, parent=detail})
	InventoryUI.Refs.Detail.Name = Utils.mkLabel({text="아이템 정보", size=UDim2.new(1, -20, 1, 0), pos=UDim2.new(0.5, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), ts=20, bold=true, parent=dHeader})
	
	-- Info Body (Scrollable if needed)
	local infoBody = Utils.mkFrame({size=UDim2.new(1, -30, 1, -120), pos=UDim2.new(0, 15, 0, 60), bgT=1, parent=detail})
	local infoList = Instance.new("UIListLayout"); infoList.Padding = UDim.new(0, 10); infoList.HorizontalAlignment = Enum.HorizontalAlignment.Center; infoList.Parent = infoBody
	
	local previewFrame = Utils.mkFrame({size=UDim2.new(0, 150, 0, 150), bg=C.BG_SLOT, bgT=0.5, r=5, parent=infoBody})
	local img = Instance.new("ImageLabel"); img.Size = UDim2.new(0.8, 0, 0.8, 0); img.Position = UDim2.new(0.5, 0, 0.5, 0); img.AnchorPoint = Vector2.new(0.5, 0.5); img.BackgroundTransparency = 1; img.ScaleType = Enum.ScaleType.Fit; img.Parent = previewFrame
	InventoryUI.Refs.Detail.PreviewIcon = img
	
	InventoryUI.Refs.Detail.Weight = Utils.mkLabel({text="", size=UDim2.new(1, 0, 0, 20), ts=14, color=C.GRAY, parent=infoBody})
	InventoryUI.Refs.Detail.Count = Utils.mkLabel({text="", size=UDim2.new(1, 0, 0, 20), ts=14, color=C.GRAY, parent=infoBody})
	local matsLabel = Utils.mkLabel({text="", size=UDim2.new(1, 0, 0, 0), ts=14, wrap=true, ax=Enum.TextXAlignment.Left, parent=infoBody})
	matsLabel.TextYAlignment = Enum.TextYAlignment.Top
	matsLabel.AutomaticSize = Enum.AutomaticSize.Y
	InventoryUI.Refs.Detail.Mats = matsLabel
	
	-- Action Footer
	local footer = Utils.mkFrame({size=UDim2.new(1, -20, 0, 50), pos=UDim2.new(0.5, 0, 1, -10), anchor=Vector2.new(0.5, 1), bgT=1, parent=detail})
	local useBtn = Utils.mkBtn({text="사용하기", size=UDim2.new(1, 0, 1, 0), bg=C.GOLD_SEL, r=4, ts=18, bold=true, color=C.BG_PANEL, parent=footer})
	InventoryUI.Refs.Detail.BtnUse = useBtn
	
	-- Mini Buttons for Drop
	InventoryUI.Refs.Detail.BtnDrop = Utils.mkBtn({text="🗑️", size=UDim2.new(0, 35, 0, 35), pos=UDim2.new(1, -5, 0, -50), anchor=Vector2.new(1, 1), bg=C.BTN, r=4, ts=14, parent=footer})

	-- Button Connections
	useBtn.MouseButton1Click:Connect(function()
		if UIManager.onUseItem then UIManager.onUseItem() end
	end)
	InventoryUI.Refs.Detail.BtnDrop.MouseButton1Click:Connect(function()
		if UIManager.openDropModal then UIManager.openDropModal() end
	end)

	------------------------------------------------------------
	-- DROP MODAL (수량 입력창 - 반응형 최적화)
	------------------------------------------------------------
	local dropModalFrame = Utils.mkFrame({
		name = "DropModal",
		size = UDim2.new(0.35, 0, 0.35, 0), -- Screen % size
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		r = 15,
		stroke = 2,
		vis = false,
		parent = InventoryUI.Refs.Frame
	})
	dropModalFrame.ZIndex = 100
	InventoryUI.Refs.DropModal.Frame = dropModalFrame
	
	local modalRatio = Instance.new("UIAspectRatioConstraint")
	modalRatio.AspectRatio = 1.3
	modalRatio.Parent = dropModalFrame
	
	Utils.mkLabel({text="버릴 수량 입력", size=UDim2.new(1, 0, 0, 40), pos=UDim2.new(0, 0, 0.05, 0), ts=20, bold=true, parent=dropModalFrame})
	
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.Size = UDim2.new(0.6, 0, 0, 45)
	box.Position = UDim2.new(0.5, 0, 0.4, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = C.BG_SLOT
	box.TextColor3 = C.WHITE
	box.Text = "1"
	box.ClearTextOnFocus = true
	box.PlaceholderText = "수량"
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 22
	box.Active = true
	box.Selectable = true
	local bRound = Instance.new("UICorner"); bRound.CornerRadius = UDim.new(0, 10); bRound.Parent = box
	local bStroke = Instance.new("UIStroke"); bStroke.Color = C.GOLD; bStroke.Thickness = 1.2; bStroke.Parent = box
	box.Parent = dropModalFrame
	InventoryUI.Refs.DropModal.Input = box
	
	InventoryUI.Refs.DropModal.MaxLabel = Utils.mkLabel({text="(최대: 1)", size=UDim2.new(1, 0, 0, 20), pos=UDim2.new(0, 0, 0.55, 0), ts=14, color=C.GRAY, parent=dropModalFrame})
	
	local mBtnArea = Utils.mkFrame({size=UDim2.new(0.8, 0, 0, 45), pos=UDim2.new(0.5, 0, 0.85, 0), anchor=Vector2.new(0.5, 1), bgT=1, parent=dropModalFrame})
	local mList = Instance.new("UIListLayout"); mList.FillDirection = Enum.FillDirection.Horizontal; mList.Padding = UDim.new(0.05, 0); mList.Parent = mBtnArea
	
	local confirmBtn = Utils.mkBtn({text="확인", size=UDim2.new(0.47, 0, 1, 0), bg=C.GOLD_SEL, r=10, parent=mBtnArea})
	local cancelBtn = Utils.mkBtn({text="취소", size=UDim2.new(0.47, 0, 1, 0), bg=C.BTN, r=10, parent=mBtnArea})
	InventoryUI.Refs.DropModal.BtnConfirm = confirmBtn
	InventoryUI.Refs.DropModal.BtnCancel = cancelBtn

	confirmBtn.MouseButton1Click:Connect(function()
		local amount = tonumber(box.Text)
		if amount and amount > 0 then
			-- Ensure we don't drop more than max count
			local currentItem = nil
			if UIManager.getSelectedInvSlot then
				local slotId = UIManager.getSelectedInvSlot()
				if slotId then
					local Controllers = require(script.Parent.Parent.Controllers.InventoryController)
					local item = Controllers.getSlot(slotId)
					if item then
						amount = math.min(amount, item.count or 1)
					end
				end
			end
			-- Fallback to modal max label extraction if needed, but best if UIManager checks it
			-- UIManager.confirmDrop will handle the request
			if UIManager.confirmDrop then UIManager.confirmDrop(amount) end
		end
	end)
	cancelBtn.MouseButton1Click:Connect(function()
		dropModalFrame.Visible = false
	end)

	------------------------------------------------------------
	-- STATUS & CRAFT (기존 유지)
	------------------------------------------------------------
	local statusFrame = Utils.mkFrame({name="StatusTab", size=UDim2.new(0.68, 0, 1, 0), bgT=1, vis=false, parent=content})
	InventoryUI.Refs.StatusFrame = statusFrame
	InventoryUI.Refs.StatPoints = Utils.mkLabel({text="보유 포인트: 0", size=UDim2.new(1, 0, 0, 40), ts=22, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=statusFrame})
	local sListScroll = Instance.new("ScrollingFrame"); sListScroll.Size = UDim2.new(1, 0, 1, -50); sListScroll.Position = UDim2.new(0, 0, 0, 50); sListScroll.BackgroundTransparency = 1; sListScroll.BorderSizePixel = 0; sListScroll.ScrollBarThickness = 0; sListScroll.Parent = statusFrame
	local sList = Instance.new("UIListLayout"); sList.Padding = UDim.new(0, 12); sList.Parent = sListScroll
	local stats = {{id="strength", name="가공력"}, {id="agility", name="기동성"}, {id="intelligence", name="통찰력"}, {id="stamina", name="지구력"}, {id="health", name="생존력"}}
	for _, s in ipairs(stats) do
		local line = Utils.mkFrame({size=UDim2.new(1, -15, 0, 55), bg=C.BG_SLOT, bgT=0.5, r=12, parent=sListScroll})
		Utils.mkLabel({text=s.name, size=UDim2.new(0.4, 0, 1, 0), pos=UDim2.new(0, 20, 0, 0), ts=18, ax=Enum.TextXAlignment.Left, parent=line})
		local val = Utils.mkLabel({text="0", size=UDim2.new(0.2, 0, 1, 0), pos=UDim2.new(0.65, 0, 0, 0), ts=22, bold=true, parent=line})
		local btn = Utils.mkBtn({text="+", size=UDim2.new(0, 42, 0, 42), pos=UDim2.new(0.95, 0, 0.5, 0), anchor=Vector2.new(1, 0.5), bg=C.GOLD_SEL, r="full", fn=function() UIManager.upgradeStat(s.id) end, parent=line})
		InventoryUI.Refs.StatLines[s.id] = {val=val, btn=btn}
	end

	local craftFrame = Utils.mkFrame({name="CraftTab", size=UDim2.new(0.68, 0, 1, 0), bgT=1, vis=false, parent=content})
	InventoryUI.Refs.CraftFrame = craftFrame
	local cScroll = Instance.new("ScrollingFrame"); cScroll.Size = UDim2.new(1, 0, 1, 0); cScroll.BackgroundTransparency = 1; cScroll.BorderSizePixel = 0; cScroll.ScrollBarThickness = 2; cScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; cScroll.ClipsDescendants = true; cScroll.Parent = craftFrame
	local cGrid = Instance.new("UIGridLayout"); cGrid.CellSize = UDim2.new(0, 80, 0, 80); cGrid.CellPadding = UDim2.new(0, 10, 0, 10); cGrid.Parent = cScroll
	InventoryUI.Refs.CraftGrid = cScroll
end

function InventoryUI.SetVisible(visible)
	if InventoryUI.Refs.Frame then
		InventoryUI.Refs.Frame.Visible = visible
	end
end

function InventoryUI.SetTab(tabId)
	local refs = InventoryUI.Refs
	refs.BagFrame.Visible = (tabId == "BAG")
	refs.StatusFrame.Visible = (tabId == "STATUS")
	refs.CraftFrame.Visible = (tabId == "CRAFT")
	
	for id, btn in pairs(refs.Tabs) do
		btn.BackgroundColor3 = (id == tabId) and C.GOLD_SEL or C.BTN
	end
end

function InventoryUI.RefreshSlots(items, getItemIcon, C, DataHelper)
	local slots = InventoryUI.Refs.Slots
	for i = 1, 40 do
		local s = slots[i]
		if not s then continue end
		
		local item = items[i]
		if item and item.itemId then
			local icon = getItemIcon(item.itemId)
			s.icon.Image = icon
			s.icon.Visible = true
			s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
			-- (Optional) If it's a specific slot, we could color it, but keep it dark for Durango
			s.frame.BackgroundColor3 = C.BG_SLOT
		else
			s.icon.Image = ""
			s.icon.Visible = false
			s.countLabel.Text = ""
			s.frame.BackgroundColor3 = C.BG_SLOT
		end
	end
end

function InventoryUI.UpdateWeight(cur, max, C)
	local fill = InventoryUI.Refs.WeightFill
	local text = InventoryUI.Refs.WeightText
	if fill then
		local pct = math.clamp(cur / max, 0, 1)
		fill.Size = UDim2.new(pct, 0, 1, 0)
		fill.BackgroundColor3 = (pct > 0.9) and C.RED or C.WHITE
	end
	if text then
		text.Text = string.format("%.1f / %.1f kg", cur, max)
	end
end

function InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper)
	local d = InventoryUI.Refs.Detail
	if not d.Frame then return end
	
	if data and data.itemId then
		local itemData = DataHelper.GetData("ItemData", data.itemId)
		
		d.Name.Text = (itemData and itemData.name) or data.itemId
		d.Count.Text = "보유 수량: " .. (data.count or 1)
		d.Weight.Text = string.format("개당 무게: %.1f kg (총 %.1f kg)", (itemData and itemData.weight or 0.1), (itemData and itemData.weight or 0.1) * (data.count or 1))
		d.PreviewIcon.Image = getItemIcon(data.itemId)
		d.PreviewIcon.Visible = true
		
		local itemData = DataHelper.GetData("ItemData", data.itemId)
		if itemData and itemData.desc then
			d.Mats.Text = itemData.desc
		else
			d.Mats.Text = "아이템에 대한 정보가 없습니다."
		end
		
		d.BtnUse.Visible = true
		d.BtnDrop.Visible = true
		
		-- Wearable check for Durango aesthetic button text
		if itemData and itemData.type == Enums.ItemType.WEARABLE then
			d.BtnUse.Text = "착용하기"
		else
			d.BtnUse.Text = "사용하기"
		end
	else
		d.Name.Text = "대상을 선택하세요"
		d.Count.Text = ""
		d.Weight.Text = ""
		d.Mats.Text = ""
		d.PreviewIcon.Image = ""
		d.BtnUse.Visible = false
		d.BtnDrop.Visible = false
	end
end

return InventoryUI
