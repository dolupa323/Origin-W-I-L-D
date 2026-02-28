-- InventoryUI.lua
-- 듀랑고 레퍼런스 스타일 소지품(가방) UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local InventoryUI = {}

InventoryUI.Refs = {
	Frame = nil,
	BagFrame = nil,
	Slots = {},
	WeightText = nil,
	CurrencyText = nil,
	Detail = {
		Frame = nil,
		Name = nil,
		Icon = nil,
		Desc = nil,
		Stats = nil,
		BtnMain = nil,
		BtnSplit = nil,
		BtnDrop = nil,
	},
	DropModal = {
		Frame = nil,
		Input = nil,
		BtnConfirm = nil,
		BtnCancel = nil,
		MaxLabel = nil,
	},
	TabBag = nil,
	TabCraft = nil,
	CraftFrame = nil,
	CraftGrid = nil,
}

function InventoryUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
	-- Background Shadow Overlay
	InventoryUI.Refs.Frame = Utils.mkFrame({
		name = "InventoryMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.7,
		vis = false,
		parent = parent
	})
	
	-- Main Panel
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isSmall and 0.95 or 0.9, 0, isSmall and 0.95 or 0.85, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 0,
		stroke = 2,
		strokeC = C.BORDER_DIM,
		parent = InventoryUI.Refs.Frame,
		ratio = isSmall and 1.3 or 1.6 -- Durango is very widescreen
	})

	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	
	local titleContainer = Utils.mkFrame({size=UDim2.new(0.4, 0, 1, 0), pos=UDim2.new(0, 15, 0, 0), bgT=1, parent=header})
	local titleList = Instance.new("UIListLayout"); titleList.FillDirection=Enum.FillDirection.Horizontal; titleList.VerticalAlignment=Enum.VerticalAlignment.Center; titleList.Padding=UDim.new(0, 15); titleList.Parent=titleContainer
	
	InventoryUI.Refs.TabBag = Utils.mkBtn({text="소지품", size=UDim2.new(0, 80, 0, 30), bgT=1, font=F.TITLE, ts=24, color=C.GOLD_SEL, parent=titleContainer})
	InventoryUI.Refs.TabCraft = Utils.mkBtn({text="제작", size=UDim2.new(0, 80, 0, 30), bgT=1, font=F.TITLE, ts=24, color=C.GRAY, parent=titleContainer})
	
	InventoryUI.Refs.WeightText = Utils.mkLabel({text="0 / 100", ts=18, color=C.GRAY, font=F.NUM, parent=titleContainer})
	
	local rightHeader = Utils.mkFrame({size=UDim2.new(0.4, 0, 1, 0), pos=UDim2.new(1, -50, 0, 0), anchor=Vector2.new(1, 0), bgT=1, parent=header})
	local hList = Instance.new("UIListLayout"); hList.FillDirection=Enum.FillDirection.Horizontal; hList.HorizontalAlignment=Enum.HorizontalAlignment.Right; hList.VerticalAlignment=Enum.VerticalAlignment.Center; hList.Padding=UDim.new(0, 20); hList.Parent=rightHeader
	
	InventoryUI.Refs.CurrencyText = Utils.mkLabel({text="소지금: 0", ts=18, color=C.GOLD, font=F.NUM, ax=Enum.TextXAlignment.Right, parent=rightHeader})
	
	-- Close Button (Absolute position)
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, -15, 0, 7), anchor=Vector2.new(1, 0), bgT=1, ts=26, color=C.WHITE, fn=function() UIManager.closeInventory() end, parent=main})

	-- Tab Events
	InventoryUI.Refs.TabBag.MouseButton1Click:Connect(function() InventoryUI.SetTab("BAG") end)
	InventoryUI.Refs.TabCraft.MouseButton1Click:Connect(function() 
		InventoryUI.SetTab("CRAFT")
		if UIManager.refreshPersonalCrafting then UIManager.refreshPersonalCrafting(true) end
	end)

	-- [Content Area]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	
	-- Left Side: Item Grid (65%)
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(0.65, -10, 1, 0), bgT=1, parent=content})
	InventoryUI.Refs.BagFrame = gridArea
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 2
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ClipsDescendants = true
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	local cellSize = isSmall and 65 or 75
	grid.CellSize = UDim2.new(0, cellSize, 0, cellSize)
	grid.CellPadding = UDim2.new(0, 4, 0, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = scroll
	
	for i = 1, 60 do -- 듀랑고는 칸이 많음
		local slot = Utils.mkSlot({name="Slot"..i, bgT=0.3, parent=scroll})
		slot.frame.LayoutOrder = i
		
		-- Hover Effect (PC Highlight)
		slot.click.MouseEnter:Connect(function()
			if UIManager.getSelectedInvSlot and UIManager.getSelectedInvSlot() ~= i then
				local st = slot.frame:FindFirstChildOfClass("UIStroke")
				if st then st.Color = C.BORDER end
			end
		end)
		slot.click.MouseLeave:Connect(function()
			if UIManager.getSelectedInvSlot and UIManager.getSelectedInvSlot() ~= i then
				local st = slot.frame:FindFirstChildOfClass("UIStroke")
				if st then st.Color = C.BORDER_DIM end
			end
		end)
		
		slot.click.MouseButton1Click:Connect(function() UIManager._onInvSlotClick(i) end)
		slot.click.MouseButton2Click:Connect(function() 
			if UIManager.onInventorySlotRightClick then UIManager.onInventorySlotRightClick(i) end
		end)
		slot.click.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if UIManager.handleDragStart then UIManager.handleDragStart(i, input) end
			end
		end)
		
		InventoryUI.Refs.Slots[i] = slot
	end
	
	-- Right Side: Detail Panel (35%)
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(0.35, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1, 0),
		bg=C.BG_PANEL_L, stroke=1, parent=content
	})
	InventoryUI.Refs.Detail.Frame = detail
	
	local dHeader = Utils.mkFrame({size=UDim2.new(1,0,0,40), bg=C.GOLD_SEL, bgT=0.3, parent=detail})
	InventoryUI.Refs.Detail.Name = Utils.mkLabel({text="선택된 아이템 없음", ts=18, font=F.TITLE, parent=dHeader})
	
	local dBody = Utils.mkFrame({size=UDim2.new(1,-20,1,-120), pos=UDim2.new(0,10,0,50), bgT=1, parent=detail})
	local dBList = Instance.new("UIListLayout"); dBList.Padding=UDim.new(0, 10); dBList.HorizontalAlignment=Enum.HorizontalAlignment.Center; dBList.Parent=dBody
	
	local iconFrame = Utils.mkFrame({size=UDim2.new(0, 100, 0, 100), bg=C.BG_SLOT, stroke=1, strokeC=C.BORDER_DIM, parent=dBody})
	InventoryUI.Refs.Detail.Icon = Instance.new("ImageLabel"); InventoryUI.Refs.Detail.Icon.Size=UDim2.new(1,-10,1,-10); InventoryUI.Refs.Detail.Icon.Position=UDim2.new(0.5,0,0.5,0); InventoryUI.Refs.Detail.Icon.AnchorPoint=Vector2.new(0.5,0.5); InventoryUI.Refs.Detail.Icon.BackgroundTransparency=1; InventoryUI.Refs.Detail.Icon.Parent=iconFrame
	InventoryUI.Refs.Detail.PreviewIcon = InventoryUI.Refs.Detail.Icon -- Alias for craft compatibility
	
	InventoryUI.Refs.Detail.Mats = Utils.mkLabel({text="", size=UDim2.new(1,0,0,80), ts=14, color=C.GOLD, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=dBody})
	
	InventoryUI.Refs.Detail.Desc = Utils.mkLabel({text="", size=UDim2.new(1,0,0,0), ts=13, color=C.WHITE, vis=false, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=dBody})
	
	InventoryUI.Refs.Detail.Stats = Utils.mkLabel({text="", size=UDim2.new(1,0,0,120), ts=13, color=C.WHITE, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, rich=true, parent=dBody})
	InventoryUI.Refs.Detail.Weight = InventoryUI.Refs.Detail.Stats -- Alias
	
	-- Detail Footer
	local dFoot = Utils.mkFrame({size=UDim2.new(1,-20,0,105), pos=UDim2.new(0.5,0,1,-10), anchor=Vector2.new(0.5,1), bgT=1, parent=detail})
	
	local footList = Instance.new("UIListLayout"); footList.Padding=UDim.new(0, 10); footList.VerticalAlignment=Enum.VerticalAlignment.Bottom; footList.Parent=dFoot
	
	InventoryUI.Refs.Detail.BtnMain = Utils.mkBtn({text="사용 / 장착", size=UDim2.new(1,0,0,45), bg=C.GOLD_SEL, hbg=Color3.fromRGB(120,120,120), font=F.TITLE, ts=20, color=C.BG_PANEL, parent=dFoot})
	InventoryUI.Refs.Detail.BtnUse = InventoryUI.Refs.Detail.BtnMain -- Alias
	
	InventoryUI.Refs.Detail.BtnDrop = Utils.mkBtn({text="버리기", size=UDim2.new(1,0,0,45), bg=Color3.fromRGB(40,40,40), font=F.TITLE, ts=20, color=C.GRAY, parent=dFoot})
	
	-- Events
	InventoryUI.Refs.Detail.BtnMain.MouseButton1Click:Connect(function() 
		if InventoryUI.Refs.CraftFrame and InventoryUI.Refs.CraftFrame.Visible then
			if UIManager._doCraft then UIManager._doCraft() end
		else
			if UIManager.onUseItem then UIManager.onUseItem() end
		end
	end)
	InventoryUI.Refs.Detail.BtnDrop.MouseButton1Click:Connect(function() if UIManager.openDropModal then UIManager.openDropModal() end end)
	
	-- Add Crafting Area Right Side (Same Pos as GridArea)
	local craftArea = Utils.mkFrame({name="CraftFrame", size=UDim2.new(0.65, -10, 1, 0), bgT=1, vis=false, parent=content})
	InventoryUI.Refs.CraftFrame = craftArea
	local craftScroll = Instance.new("ScrollingFrame")
	craftScroll.Name = "GridScroll"
	craftScroll.Size = UDim2.new(1, 0, 1, 0); craftScroll.BackgroundTransparency = 1; craftScroll.BorderSizePixel = 0; craftScroll.ScrollBarThickness = 2
	craftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	craftScroll.ClipsDescendants = true
	craftScroll.Parent = craftArea
	
	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop = UDim.new(0, 4); cPad.PaddingLeft = UDim.new(0, 4)
	cPad.PaddingRight = UDim.new(0, 4); cPad.PaddingBottom = UDim.new(0, 4)
	cPad.Parent = craftScroll
	
	InventoryUI.Refs.CraftGrid = craftScroll
	
	-- Drop/Split Modal Popup
	local dropModalFrame = Utils.mkFrame({name="DropModal", size=UDim2.new(0.3, 0, 0.4, 0), pos=UDim2.new(0.5, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bg=C.BG_PANEL, stroke=2, vis=false, parent=InventoryUI.Refs.Frame, z=100})
	local mRatio = Instance.new("UIAspectRatioConstraint"); mRatio.AspectRatio=1.2; mRatio.Parent=dropModalFrame
	InventoryUI.Refs.DropModal.Frame = dropModalFrame
	
	Utils.mkLabel({text="수량 입력", size=UDim2.new(1,0,0,40), pos=UDim2.new(0,0,0,10), ts=20, font=F.TITLE, parent=dropModalFrame})
	local box = Instance.new("TextBox")
	box.Name = "Input"; box.Size = UDim2.new(0.8,0,0,50); box.Position = UDim2.new(0.5,0,0.4,0); box.AnchorPoint = Vector2.new(0.5,0.5); box.BackgroundColor3 = C.BG_SLOT; box.TextColor3 = C.WHITE; box.Text = "1"; box.ClearTextOnFocus = true; box.Font = F.NUM; box.TextSize = 24
	local bRound = Instance.new("UICorner"); bRound.CornerRadius = UDim.new(0, 4); bRound.Parent = box
	box.Parent = dropModalFrame
	InventoryUI.Refs.DropModal.Input = box
	
	InventoryUI.Refs.DropModal.MaxLabel = Utils.mkLabel({text="(최대: 1)", size=UDim2.new(1,0,0,20), pos=UDim2.new(0,0,0.5,0), ts=14, color=C.GRAY, parent=dropModalFrame})
	
	-- Slider System
	local sliderBack = Utils.mkFrame({name="SliderBack", size=UDim2.new(0.8,0,0,8), pos=UDim2.new(0.5,0,0.65,0), anchor=Vector2.new(0.5,0.5), bg=C.BORDER_DIM, r=4, parent=dropModalFrame})
	local sliderHandle = Utils.mkFrame({name="Handle", size=UDim2.new(0,20,0,20), pos=UDim2.new(0,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.GOLD_SEL, r="full", stroke=1, parent=sliderBack})
	
	local dragging = false
	local function updateSlider(input)
		local x = math.clamp((input.Position.X - sliderBack.AbsolutePosition.X) / sliderBack.AbsoluteSize.X, 0, 1)
		sliderHandle.Position = UDim2.new(x, 0, 0.5, 0)
		
		local max = tonumber(InventoryUI.Refs.DropModal.MaxLabel.Text:match("%d+")) or 1
		local val = math.max(1, math.round(x * max))
		box.Text = tostring(val)
	end
	
	sliderHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	
	game:GetService("UserInputService").InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateSlider(input)
		end
	end)
	
	game:GetService("UserInputService").InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	
	-- Manual input sync
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local val = tonumber(box.Text) or 0
		local max = tonumber(InventoryUI.Refs.DropModal.MaxLabel.Text:match("%d+")) or 1
		if not dragging then
			sliderHandle.Position = UDim2.new(math.clamp(val/max, 0, 1), 0, 0.5, 0)
		end
	end)

	local mBtnArea = Utils.mkFrame({size=UDim2.new(0.9,0,0,45), pos=UDim2.new(0.5,0,1,-10), anchor=Vector2.new(0.5,1), bgT=1, parent=dropModalFrame})
	local mBtnList = Instance.new("UIListLayout"); mBtnList.FillDirection=Enum.FillDirection.Horizontal; mBtnList.HorizontalAlignment=Enum.HorizontalAlignment.Center; mBtnList.Padding=UDim.new(0, 10); mBtnList.Parent=mBtnArea
	
	local confirmBtn = Utils.mkBtn({text="확인", size=UDim2.new(0.45,0,1,0), bg=C.GOLD_SEL, font=F.TITLE, color=C.BG_PANEL, parent=mBtnArea})
	local cancelBtn = Utils.mkBtn({text="취소", size=UDim2.new(0.45,0,1,0), bg=C.BTN, font=F.TITLE, parent=mBtnArea})
	
	confirmBtn.MouseButton1Click:Connect(function()
		local amount = tonumber(box.Text)
		if amount and amount > 0 and UIManager.confirmModalAction then
			UIManager.confirmModalAction(amount)
			dropModalFrame.Visible = false
		end
	end)
	cancelBtn.MouseButton1Click:Connect(function() dropModalFrame.Visible = false end)
end

function InventoryUI.SetVisible(visible)
	if InventoryUI.Refs.Frame then
		InventoryUI.Refs.Frame.Visible = visible
	end
end

function InventoryUI.SetTab(tabId)
	local isBag = (tabId == "BAG")
	if InventoryUI.Refs.BagFrame then InventoryUI.Refs.BagFrame.Visible = isBag end
	if InventoryUI.Refs.CraftFrame then InventoryUI.Refs.CraftFrame.Visible = not isBag end
	
	if InventoryUI.Refs.TabBag then
		InventoryUI.Refs.TabBag.TextColor3 = isBag and C.GOLD_SEL or C.GRAY
	end
	if InventoryUI.Refs.TabCraft then
		InventoryUI.Refs.TabCraft.TextColor3 = (not isBag) and C.GOLD_SEL or C.GRAY
	end
	
	local d = InventoryUI.Refs.Detail
	if d.Frame then
		d.Name.Text = "선택된 대상 없음"
		d.Icon.Image = ""
		d.Icon.Visible = false
		d.Stats.Text = ""
		d.Desc.Text = ""
		d.Mats.Text = ""
		d.BtnMain.Visible = false
		d.BtnDrop.Visible = false
	end
end

function InventoryUI.UpdateSlotSelectionHighlight(selectedIndex, items, DataHelper)
	local RarityColors = {
		COMMON = Color3.fromRGB(180, 180, 180),
		UNCOMMON = Color3.fromRGB(40, 200, 40),
		RARE = Color3.fromRGB(40, 120, 255),
		EPIC = Color3.fromRGB(180, 40, 255),
		LEGENDARY = Color3.fromRGB(255, 180, 0),
	}
	
	for i = 1, 60 do
		local s = InventoryUI.Refs.Slots[i]
		if not s then continue end
		local st = s.frame:FindFirstChildOfClass("UIStroke")
		if st then
			if i == selectedIndex then
				st.Color = C.GOLD_SEL
				st.Thickness = 2
			else
				local item = items and items[i]
				local itemData = item and DataHelper.GetData("ItemData", item.itemId)
				local color = (itemData and itemData.rarity and RarityColors[itemData.rarity]) or C.BORDER_DIM
				st.Color = color
				st.Thickness = (itemData and itemData.rarity and itemData.rarity ~= "COMMON") and 2 or 1
			end
		end
	end
end

function InventoryUI.RefreshSlots(items, getItemIcon, __C, DataHelper)
	local slots = InventoryUI.Refs.Slots
	local RarityColors = {
		COMMON = Color3.fromRGB(180, 180, 180),
		UNCOMMON = Color3.fromRGB(40, 200, 40),
		RARE = Color3.fromRGB(40, 120, 255),
		EPIC = Color3.fromRGB(180, 40, 255),
		LEGENDARY = Color3.fromRGB(255, 180, 0),
	}

	for i = 1, 60 do
		local s = slots[i]
		if not s then continue end
		
		local item = items[i]
		local st = s.frame:FindFirstChildOfClass("UIStroke")
		
		if item and item.itemId then
			s.icon.Image = getItemIcon(item.itemId)
			s.icon.Visible = true
			s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
			
			local itemData = DataHelper.GetData("ItemData", item.itemId)
			if st then
				local color = (itemData and itemData.rarity and RarityColors[itemData.rarity]) or C.BORDER_DIM
				st.Color = color
				st.Thickness = (itemData and itemData.rarity and itemData.rarity ~= "COMMON") and 2 or 1
			end
			
			if item.durability and itemData and itemData.durability then
				local ratio = math.clamp(item.durability / itemData.durability, 0, 1)
				s.durBg.Visible = true
				s.durFill.Size = UDim2.new(ratio, 0, 1, 0)
				
				if ratio > 0.5 then
					s.durFill.BackgroundColor3 = Color3.fromRGB(150, 255, 150)
				elseif ratio > 0.2 then
					s.durFill.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
				else
					s.durFill.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
				end
			else
				if s.durBg then s.durBg.Visible = false end
			end
		else
			s.icon.Image = ""
			s.icon.Visible = false
			s.countLabel.Text = ""
			if s.durBg then s.durBg.Visible = false end
			if st then
				st.Color = C.BORDER_DIM
				st.Thickness = 1
			end
		end
	end
end

function InventoryUI.UpdateWeight(cur, max, __C)
	if InventoryUI.Refs.WeightText then
		InventoryUI.Refs.WeightText.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
	end
end

function InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper)
	local d = InventoryUI.Refs.Detail
	if not d.Frame then return end
	
	if data and data.itemId then
		local itemData = DataHelper.GetData("ItemData", data.itemId)
		d.Name.Text = (itemData and itemData.name) or data.itemId
		d.Icon.Image = getItemIcon(data.itemId)
		d.Icon.Visible = true
		
		local weightStr = string.format("무게: %.1f", (itemData and itemData.weight or 0.1) * (data.count or 1))
		d.Stats.Text = weightStr .. " | 수량: " .. (data.count or 1)
		
		d.Desc.Text = "" -- (Descriptions removed by user request)
		d.Mats.Text = ""
		
		d.BtnMain.Visible = true
		d.BtnDrop.Visible = true
		
		d.BtnMain.Text = (itemData and itemData.type == Enums.ItemType.WEARABLE) and "장착" or "사용"
	else
		d.Name.Text = "선택된 아이템 없음"
		d.Icon.Image = ""
		d.Icon.Visible = false
		d.Stats.Text = ""
		d.Desc.Text = ""
		d.Mats.Text = ""
		d.BtnMain.Visible = false
		d.BtnDrop.Visible = false
	end
end

return InventoryUI
