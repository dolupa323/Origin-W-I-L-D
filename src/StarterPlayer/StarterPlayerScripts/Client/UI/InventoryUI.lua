-- InventoryUI.lua
-- 듀랑고 레퍼런스 스타일 소지품(가방) UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

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
	
	-- Main Panel (Modern Sleek Panel)
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isSmall and 0.95 or 0.8, 0, isSmall and 0.9 or 0.85, 0),
		maxSize = Vector2.new(1100, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = InventoryUI.Refs.Frame
	})

	-- [Header] - Split into Left / Right with safe padding
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	
	local leftHeader = Utils.mkFrame({size=UDim2.new(0.6, -20, 1, 0), pos=UDim2.new(0, 15, 0, 0), bgT=1, parent=header})
	local titleList = Instance.new("UIListLayout"); titleList.FillDirection=Enum.FillDirection.Horizontal; titleList.VerticalAlignment=Enum.VerticalAlignment.Center; titleList.Padding=UDim.new(0, 20); titleList.Parent=leftHeader
	
	InventoryUI.Refs.TabBag = Utils.mkBtn({text="INVENTORY [B]", size=UDim2.new(0, 140, 0, 35), bgT=1, font=F.TITLE, ts=18, color=C.GOLD_SEL, parent=leftHeader})
	InventoryUI.Refs.TabCraft = Utils.mkBtn({text="CRAFTING", size=UDim2.new(0, 140, 0, 35), bgT=1, font=F.TITLE, ts=18, color=C.GRAY, parent=leftHeader})
	
	InventoryUI.Refs.WeightText = Utils.mkLabel({text="0 / 100 kg", size=UDim2.new(0, 80, 1, 0), ts=14, color=C.GRAY, parent=leftHeader})
	
	local rightHeader = Utils.mkFrame({size=UDim2.new(0.3, 0, 1, 0), pos=UDim2.new(1, -140, 0, 0), anchor=Vector2.new(1, 0), bgT=1, parent=header})
	local hList = Instance.new("UIListLayout"); hList.FillDirection=Enum.FillDirection.Horizontal; hList.HorizontalAlignment=Enum.HorizontalAlignment.Right; hList.VerticalAlignment=Enum.VerticalAlignment.Center; hList.Padding=UDim.new(0, 15); hList.Parent=rightHeader
	
	InventoryUI.Refs.CurrencyText = Utils.mkLabel({text="골드: 0", ts=18, color=C.GOLD, font=F.NUM, ax=Enum.TextXAlignment.Right, parent=rightHeader})
	
	-- Close Button (Fixed Text rendering)
	Utils.mkBtn({text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1, 0.5), bg=C.BTN, bgT=0.5, ts=20, color=C.WHITE, r=4, fn=function() UIManager.closeInventory() end, parent=header})

	-- Tab Events
	InventoryUI.Refs.TabBag.MouseButton1Click:Connect(function() InventoryUI.SetTab("BAG") end)
	InventoryUI.Refs.TabCraft.MouseButton1Click:Connect(function() 
		InventoryUI.SetTab("CRAFT")
		if UIManager.refreshPersonalCrafting then UIManager.refreshPersonalCrafting(true) end
	end)

	-- [Content Area]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	
	-- Left Side: Item Grid (최근 트렌드 전용 여백 확보)
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(1, -330, 1, 0), bgT=1, parent=content})
	InventoryUI.Refs.BagFrame = gridArea
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, -8, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = C.GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	local cellSize = isSmall and 65 or 75
	grid.CellSize = UDim2.new(0, cellSize, 0, cellSize)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = scroll

	for i = 1, Balance.INV_SLOTS do
		local slot = Utils.mkSlot({name="Slot"..i, bgT=0.3, parent=scroll})
		slot.frame.LayoutOrder = i
		
		-- 핫바 배지 추가 (HOTBAR 전용 디자인)
		if i <= 8 then
			local vividHotbarYellow = Color3.fromRGB(255, 232, 35)
			local badge = Utils.mkFrame({
				name = "HotbarBadge",
				size = UDim2.new(0, 18, 0, 18),
				pos = UDim2.new(0, 3, 0, 3),
				bg = vividHotbarYellow,
				bgT = 0,
				r = 3,
				z = slot.frame.ZIndex + 9,
				parent = slot.frame
			})
			local badgeStroke = Instance.new("UIStroke")
			badgeStroke.Thickness = 2
			badgeStroke.Color = Color3.fromRGB(20, 20, 20)
			badgeStroke.Parent = badge
			Utils.mkLabel({
				text = tostring(i),
				ts = 13,
				bold = true,
				color = Color3.new(0,0,0),
				z = slot.frame.ZIndex + 10,
				parent = badge
			})
			local hotbarTag = Utils.mkLabel({
				text = "HOT",
				size = UDim2.new(0, 24, 0, 10),
				pos = UDim2.new(1, -2, 0, 2),
				anchor = Vector2.new(1, 0),
				ts = 8,
				bold = true,
				color = vividHotbarYellow,
				ax = Enum.TextXAlignment.Right,
				z = slot.frame.ZIndex + 10,
				parent = slot.frame
			})
			hotbarTag.TextStrokeTransparency = 0.35
			hotbarTag.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			local stk = slot.frame:FindFirstChildOfClass("UIStroke")
			if stk then stk.Color = vividHotbarYellow; stk.Thickness = 1.8 end -- 핫바 슬롯은 상시 강조
		end
		
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
		
		-- Custom Tap & Hold logic for Mobile/PC
		slot.click.Active = false -- Event blocking prevention
		local pressStartTime = 0
		
		slot.click.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressStartTime = tick()
				if UIManager.handleDragStart then UIManager.handleDragStart(i, input) end
			end
		end)
		
		local lastClickTime = 0
		local lastClickIdx = 0
		
		slot.click.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local duration = tick() - pressStartTime
				-- If NOT dragging and released quickly (< 0.25s) -> Click
				if not UIManager.isDragging() and duration < 0.25 then
					local now = tick()
					if now - lastClickTime < 0.35 and lastClickIdx == i then
						-- Double Click
						if UIManager._onInvSlotDoubleClick then
							UIManager._onInvSlotDoubleClick(i)
						end
						lastClickTime = 0
					else
						-- Single Click
						UIManager._onInvSlotClick(i)
						lastClickTime = now
						lastClickIdx = i
					end
				end
				pressStartTime = 0
			end
		end)

		slot.click.MouseButton2Click:Connect(function() 
			if UIManager.onInventorySlotRightClick then UIManager.onInventorySlotRightClick(i) end
		end)
		
		InventoryUI.Refs.Slots[i] = slot
	end
	
	-- Right Side: Detail Panel (Responsive)
	local detailSize = isSmall and 280 or 320
	local detail = Utils.mkFrame({
		name="Detail", 
		size = isSmall and UDim2.new(1, -20, 0, 320) or UDim2.new(0, detailSize, 1, -16),
		pos = isSmall and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(1, -detailSize - 12, 0, 8),
		anchor = isSmall and Vector2.new(0.5, 0.5) or Vector2.new(0, 0),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = false,
		vis = false,
		z = 10,
		parent = content
	})
	InventoryUI.Refs.Detail.Frame = detail
	
	local dtHead = Utils.mkLabel({
		text="ITEM DETAILS", size=UDim2.new(1,0,0,45),
		bg=C.BG_DARK, bgT=0.3, color=C.GOLD, ts=16, font=F.TITLE,
		parent=detail
	})
	
	InventoryUI.Refs.Detail.Name = Utils.mkLabel({
		text="SELECT ITEM", size=UDim2.new(1,-30,0,40), pos=UDim2.new(0,15,0,55),
		color=C.WHITE, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	InventoryUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	InventoryUI.Refs.Detail.Icon.Size = UDim2.new(0, 90, 0, 90); InventoryUI.Refs.Detail.Icon.Position = UDim2.new(0,15,0,105)
	InventoryUI.Refs.Detail.Icon.BackgroundTransparency = 1; InventoryUI.Refs.Detail.Icon.Parent = detail
	InventoryUI.Refs.Detail.PreviewIcon = InventoryUI.Refs.Detail.Icon
	
	InventoryUI.Refs.Detail.Desc = Utils.mkLabel({
		text="Description", size=UDim2.new(1,-120,0,110), pos=UDim2.new(0,115,0,105),
		color=C.GRAY, ts=15, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detail
	})
	
	InventoryUI.Refs.Detail.Stats = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,0,180), pos=UDim2.new(0,15,0,240),
		color=C.WHITE, ts=16, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, rich=true, parent=detail
	})
	InventoryUI.Refs.Detail.Mats = InventoryUI.Refs.Detail.Stats -- Alias for crafting
	InventoryUI.Refs.Detail.Weight = InventoryUI.Refs.Detail.Stats

	-- Durability Bar (Detail Panel)
	local durWrap = Utils.mkFrame({name="DurWrap", size=UDim2.new(1, -30, 0, 15), pos=UDim2.new(0, 15, 0, 195), bgT=1, vis=false, parent=detail})
	local durBarBack = Utils.mkFrame({name="Back", size=UDim2.new(1, 0, 1, 0), bg=Color3.fromRGB(40, 40, 40), r=3, parent=durWrap})
	local durBarFill = Utils.mkFrame({name="Fill", size=UDim2.new(1, 0, 1, 0), bg=C.GOLD, r=3, parent=durBarBack})
	local durText = Utils.mkLabel({text="100/100", size=UDim2.new(1, 0, 1, 0), ts=10, bold=true, color=C.WHITE, parent=durBarBack})
	
	InventoryUI.Refs.Detail.DurWrap = durWrap
	InventoryUI.Refs.Detail.DurFill = durBarFill
	InventoryUI.Refs.Detail.DurText = durText

	-- [제작 진행표시] 로딩 스피너 및 프로그레스바 추가
	local progWrap = Utils.mkFrame({name="ProgWrap", size=UDim2.new(0, 80, 0, 80), pos=UDim2.new(0,15,0,95), bgT=1, vis=false, parent=detail})
	InventoryUI.Refs.Detail.ProgWrap = progWrap
	
	local spinner = Instance.new("ImageLabel")
	spinner.Name = "Spinner"; spinner.Size = UDim2.new(1.2, 0, 1.2, 0); spinner.Position = UDim2.new(0.5, 0, 0.5, 0); spinner.AnchorPoint = Vector2.new(0.5,0.5)
	spinner.BackgroundTransparency = 1; spinner.Image = "rbxassetid://6034445544"; spinner.ImageColor3 = C.GOLD; spinner.ZIndex = 15; spinner.Parent = progWrap
	InventoryUI.Refs.Detail.Spinner = spinner

	local barBack = Utils.mkFrame({name="BarBack", size=UDim2.new(1, -24, 0, 6), pos=UDim2.new(0.5, 0, 0, 185), anchor=Vector2.new(0.5, 0), bg=Color3.fromRGB(40,40,40), r=3, vis=false, parent=detail})
	local barFill = Utils.mkFrame({name="Fill", size=UDim2.new(0, 0, 1, 0), bg=C.GOLD, r=3, parent=barBack})
	InventoryUI.Refs.Detail.ProgBar = barBack
	InventoryUI.Refs.Detail.ProgFill = barFill
	
	-- Detail Footer
	local dFoot = Utils.mkFrame({size=UDim2.new(1,-24,0,105), pos=UDim2.new(0.5,0,1,-10), anchor=Vector2.new(0.5,1), bgT=1, parent=detail})
	
	local footList = Instance.new("UIListLayout"); footList.Padding=UDim.new(0, 8); footList.VerticalAlignment=Enum.VerticalAlignment.Bottom; footList.Parent=dFoot
	
	InventoryUI.Refs.Detail.BtnMain = Utils.mkBtn({
		text="[ EQUIP / USE ]", size=UDim2.new(1,0,0, isSmall and 40 or 45), bg=C.GOLD, r=4, font=F.TITLE, ts=16, color=C.BG_DARK, parent=dFoot
	})
	InventoryUI.Refs.Detail.BtnUse = InventoryUI.Refs.Detail.BtnMain -- Alias
	
	InventoryUI.Refs.Detail.BtnDrop = Utils.mkBtn({
		text="[ DROP ]", size=UDim2.new(1,0,0, isSmall and 35 or 40), bg=C.BTN, r=4, font=F.TITLE, ts=14, color=C.WHITE, parent=dFoot
	})
	
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
	local craftArea = Utils.mkFrame({name="CraftFrame", size=UDim2.new(1, -300, 1, 0), bgT=1, vis=false, parent=content})
	InventoryUI.Refs.CraftFrame = craftArea
	local craftScroll = Instance.new("ScrollingFrame")
	craftScroll.Name = "CraftGrid"
	craftScroll.Size = UDim2.new(1, 0, 1, 0); craftScroll.BackgroundTransparency = 1; craftScroll.BorderSizePixel = 0; craftScroll.ScrollBarThickness = 4
	craftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	craftScroll.Parent = craftArea
	InventoryUI.Refs.CraftGrid = craftScroll
	
	local cGrid = Instance.new("UIGridLayout")
	cGrid.CellSize = UDim2.new(0, 75, 0, 75); cGrid.CellPadding = UDim2.new(0, 8, 0, 8)
	cGrid.SortOrder = Enum.SortOrder.LayoutOrder; cGrid.Parent = craftScroll

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop = UDim.new(0, 15); cPad.PaddingLeft = UDim.new(0, 15)
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
		d.Frame.Visible = false -- 탭 전환 시 정보창 숨김
		d.Name.Text = ""
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
	
	for i = 1, Balance.INV_SLOTS do
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

	for i = 1, Balance.INV_SLOTS do
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

function InventoryUI.UpdateCurrency(amount)
	if InventoryUI.Refs.CurrencyText then
		InventoryUI.Refs.CurrencyText.Text = string.format("골드: %d", math.floor(tonumber(amount) or 0))
	end
end

function InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper, itemCounts, isLocked)
	local d = InventoryUI.Refs.Detail
	if not d.Frame then return end
	
	if data and (data.itemId or data.id) then
		d.Frame.Visible = true -- 아이템/레시피가 있으면 표시
		local itemId = data.itemId or data.id
		local displayItemId = itemId
		local itemData = DataHelper.GetData("ItemData", itemId)
		
		-- [수정] 레시피인 경우 결과물 아이템의 정보를 참조하여 이름/설명을 표시
		if not itemData and data.outputs and data.outputs[1] then
			displayItemId = data.outputs[1].itemId or data.outputs[1].id or displayItemId
			itemData = DataHelper.GetData("ItemData", displayItemId)
		elseif itemData and itemData.id then
			displayItemId = itemData.id
		end
		
		d.Name.Text = UILocalizer.LocalizeDataText("ItemData", tostring(displayItemId), "name", data.name or (itemData and itemData.name) or itemId)
		d.Icon.Image = getItemIcon(itemData and itemData.id or itemId)
		d.Icon.Visible = true
		
		local weightValue = (itemData and itemData.weight or 0.1) * (data.count or 1)
		local weightStr = string.format("무게: %.1f", weightValue)
		d.Stats.Text = UILocalizer.Localize(weightStr .. " | 수량: " .. (data.count or 1))
		
		if itemData and itemData.description then
			d.Desc.Text = UILocalizer.LocalizeDataText("ItemData", tostring(displayItemId), "description", itemData.description)
		else
			d.Desc.Text = UILocalizer.Localize((itemData and (itemData.name .. " 입니다.")) or "")
		end
		
		-- [제작 탭 대응] 재료 정보 표시 (실시간 보유량 체크 및 색상 적용)
		local recipe = data
		local mats = recipe.inputs or recipe.requirements
		if mats and #mats > 0 then
			if isLocked then
				d.Stats.Text = string.format("<font color=\"#E63232\">%s</font>", UILocalizer.Localize("기술 트리(K)에서 해금이 필요합니다."))
				d.BtnMain.Text = UILocalizer.Localize("잠김 (해금 필요)")
				d.BtnMain.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
				d.BtnMain.Visible = true
				d.BtnDrop.Visible = false
			else
				local matsText = string.format("<b>%s</b>\n", UILocalizer.Localize("[ 필요 재료 ]"))
				local allMet = true
				for _, m in ipairs(mats) do
					local matId = m.itemId or m.id
					local mName = matId
					if DataHelper then
						local md = DataHelper.GetData("ItemData", matId)
						if md then mName = md.name end
					end
					mName = UILocalizer.LocalizeDataText("ItemData", tostring(matId), "name", mName)
					
					local req = m.count or m.amount or 1
					local have = (itemCounts and itemCounts[matId]) or 0
					local color = (have >= req) and "#8CDC64" or "#E63232"
					if have < req then allMet = false end
					
					matsText = matsText .. string.format("- %s : <font color=\"%s\">%d / %d</font>\n", mName, color, have, req)
				end
				d.Stats.Text = matsText
				
				if allMet then
					d.BtnMain.Text = UILocalizer.Localize("제작 시작")
					d.BtnMain.BackgroundColor3 = C.GOLD_SEL
				else
					d.BtnMain.Text = UILocalizer.Localize("재료 부족")
					d.BtnMain.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
				end
				d.BtnMain.Visible = true
				d.BtnDrop.Visible = false
			end
		else
			-- 일반 아이템
			d.BtnMain.Visible = true
			d.BtnDrop.Visible = true
			d.BtnMain.BackgroundColor3 = C.GOLD_SEL
			local isEquippable = (itemData and (itemData.type == Enums.ItemType.ARMOR or itemData.type == Enums.ItemType.WEAPON or itemData.type == Enums.ItemType.TOOL))
			d.BtnMain.Text = UILocalizer.Localize(isEquippable and "장착" or "사용")
		end
		
		-- Durability Display
		if data.durability and itemData and itemData.durability then
			local maxDur = itemData.durability
			local curDur = data.durability
			local ratio = math.clamp(curDur / maxDur, 0, 1)
			
			d.DurWrap.Visible = true
			d.DurFill.Size = UDim2.new(ratio, 0, 1, 0)
			d.DurText.Text = string.format("내구도: %d / %d", math.floor(curDur), math.floor(maxDur))
			
			if ratio > 0.5 then
				d.DurFill.BackgroundColor3 = Color3.fromRGB(150, 255, 150)
			elseif ratio > 0.2 then
				d.DurFill.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
			else
				d.DurFill.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
			end
		else
			d.DurWrap.Visible = false
		end
	else
		d.Frame.Visible = false -- 아이템이 없으면 숨김
		d.Name.Text = ""
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
