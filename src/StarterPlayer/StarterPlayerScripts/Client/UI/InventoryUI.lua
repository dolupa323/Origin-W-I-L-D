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

local Data = game:GetService("ReplicatedStorage"):WaitForChild("Data")
local MaterialAttributeData = require(Data.MaterialAttributeData)

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
	-- 반응형 텍스트 크기 변수
	local TS_TITLE = isSmall and 18 or 20
	local TS_BODY = isSmall and 16 or 18
	local TS_SMALL = isSmall and 14 or 16
	local TS_DETAIL_NAME = isSmall and 20 or 24
	local TS_DETAIL_DESC = isSmall and 14 or 16
	local TS_DETAIL_STAT = isSmall and 15 or 17
	local TS_BADGE = isSmall and 12 or 14
	local TS_BTN = isSmall and 16 or 18
	local TS_BTN_SUB = isSmall and 14 or 16
	local TS_DUR = isSmall and 10 or 12
	local TS_TAB = isSmall and 16 or 18
	local TS_SLOT_COUNT = isSmall and 12 or 14
	local TS_HOTBAR = isSmall and 11 or 13
	local TS_HOTBAR_TAG = isSmall and 7 or 8
	
	-- 반응형 수치 보관
	InventoryUI._ts = {
		detailStat = TS_DETAIL_STAT,
		detailDesc = TS_DETAIL_DESC,
		badge = TS_BADGE,
		dur = TS_DUR,
	}
	
	-- Background Shadow Overlay
	InventoryUI.Refs.Frame = Utils.mkFrame({
		name = "InventoryMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent
	})
	
	-- Main Panel (Modern Sleek Panel)
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isSmall and 0.98 or 0.8, 0, isSmall and 0.93 or 0.85, 0),
		maxSize = Vector2.new(1100, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = InventoryUI.Refs.Frame
	})

	-- [Header] - Split into Left / Right with safe padding
	local headerH = isSmall and 46 or 50
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,headerH), bgT=1, parent=main})
	
	local leftHeader = Utils.mkFrame({size=UDim2.new(0.65, -10, 1, 0), pos=UDim2.new(0, 10, 0, 0), bgT=1, parent=header})
	local titleList = Instance.new("UIListLayout"); titleList.FillDirection=Enum.FillDirection.Horizontal; titleList.VerticalAlignment=Enum.VerticalAlignment.Center; titleList.Padding=UDim.new(0, isSmall and 10 or 20); titleList.Parent=leftHeader
	
	InventoryUI.Refs.TabBag = Utils.mkBtn({text="INVENTORY [B]", size=UDim2.new(0, isSmall and 110 or 140, 0, isSmall and 32 or 35), bgT=1, font=F.TITLE, ts=TS_TAB, color=C.GOLD_SEL, parent=leftHeader})
	InventoryUI.Refs.TabCraft = Utils.mkBtn({text="간이제작", size=UDim2.new(0, isSmall and 80 or 140, 0, isSmall and 32 or 35), bgT=1, font=F.TITLE, ts=TS_TAB, color=C.GRAY, parent=leftHeader})
	
	InventoryUI.Refs.WeightText = Utils.mkLabel({text="0 / 60", size=UDim2.new(0, isSmall and 60 or 80, 1, 0), ts=TS_SMALL, color=C.GRAY, parent=leftHeader})
	
	local rightHeader = Utils.mkFrame({size=UDim2.new(0.3, 0, 1, 0), pos=UDim2.new(1, -140, 0, 0), anchor=Vector2.new(1, 0), bgT=1, parent=header})
	local hList = Instance.new("UIListLayout"); hList.FillDirection=Enum.FillDirection.Horizontal; hList.HorizontalAlignment=Enum.HorizontalAlignment.Right; hList.VerticalAlignment=Enum.VerticalAlignment.Center; hList.Padding=UDim.new(0, 15); hList.Parent=rightHeader
	
	InventoryUI.Refs.CurrencyText = Utils.mkLabel({text="골드: 0", ts=TS_BODY, color=C.GOLD, font=F.NUM, ax=Enum.TextXAlignment.Right, parent=rightHeader})
	
	-- Close Button
	local closeBtnSize = isSmall and 34 or 36
	Utils.mkBtn({text="X", size=UDim2.new(0, closeBtnSize, 0, closeBtnSize), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1, 0.5), bg=C.BTN, bgT=0.5, ts=TS_BODY, color=C.WHITE, r=4, fn=function() UIManager.closeInventory() end, parent=header})

	-- Tab Events
	InventoryUI.Refs.TabBag.MouseButton1Click:Connect(function() InventoryUI.SetTab("BAG") end)
	InventoryUI.Refs.TabCraft.MouseButton1Click:Connect(function() 
		InventoryUI.SetTab("CRAFT")
		if UIManager.refreshPersonalCrafting then UIManager.refreshPersonalCrafting(true) end
	end)

	-- [Content Area]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -(headerH + 5)), pos=UDim2.new(0, 10, 0, headerH - 5), bgT=1, parent=main})
	
	-- Left Side: Item Grid (반응형 - 모바일은 전체 너비)
	local gridArea = Utils.mkFrame({name="GridArea", size=isSmall and UDim2.new(1, 0, 1, 0) or UDim2.new(1, -330, 1, 0), bgT=1, parent=content})
	InventoryUI.Refs.BagFrame = gridArea
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, -8, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = C.GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	local cellSize = isSmall and 70 or 75
	grid.CellSize = UDim2.new(0, cellSize, 0, cellSize)
	grid.CellPadding = UDim2.new(0, isSmall and 8 or 10, 0, isSmall and 8 or 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = scroll

	for i = 1, Balance.MAX_INV_SLOTS do
		local slot = Utils.mkSlot({name="Slot"..i, bgT=0.3, parent=scroll})
		slot.frame.LayoutOrder = i
		
		-- 핫바 배지 추가 (HOTBAR 전용 디자인)
		if i <= 8 then
			local vividHotbarYellow = C.GOLD
			local badgeSize = isSmall and 16 or 18
			local badge = Utils.mkFrame({
				name = "HotbarBadge",
				size = UDim2.new(0, badgeSize, 0, badgeSize),
				pos = UDim2.new(0, 3, 0, 3),
				bg = vividHotbarYellow,
				bgT = 0,
				r = 4,
				z = slot.frame.ZIndex + 9,
				parent = slot.frame
			})
			local badgeStroke = Instance.new("UIStroke")
			badgeStroke.Thickness = 2
			badgeStroke.Color = C.WOOD_DARK
			badgeStroke.Parent = badge
			Utils.mkLabel({
				text = tostring(i),
				ts = TS_HOTBAR,
				bold = true,
				color = C.BG_DARK,
				z = slot.frame.ZIndex + 10,
				parent = badge
			})
			local hotbarTag = Utils.mkLabel({
				text = "HOT",
				size = UDim2.new(0, isSmall and 20 or 24, 0, isSmall and 9 or 10),
				pos = UDim2.new(1, -2, 0, 2),
				anchor = Vector2.new(1, 0),
				ts = TS_HOTBAR_TAG,
				bold = true,
				color = vividHotbarYellow,
				ax = Enum.TextXAlignment.Right,
				z = slot.frame.ZIndex + 10,
				parent = slot.frame
			})
			hotbarTag.TextStrokeTransparency = 0.35
			hotbarTag.TextStrokeColor3 = C.BG_DARK
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
		-- 반응형 카운트 텍스트 크기
		if slot.countLabel then
			slot.countLabel.TextSize = TS_SLOT_COUNT
		end
	end
	
	-- Right Side: Detail Panel (Responsive)
	local detailSize = isSmall and 280 or 320
	local detail = Utils.mkFrame({
		name="Detail", 
		size = isSmall and UDim2.new(1, -16, 0.82, 0) or UDim2.new(0, detailSize, 1, -16),
		pos = isSmall and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(1, -detailSize - 12, 0, 8),
		anchor = isSmall and Vector2.new(0.5, 0.5) or Vector2.new(0, 0),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = false,
		vis = false,
		z = 10,
		parent = content
	})
	InventoryUI.Refs.Detail.Frame = detail
	
	local dtHeadH = isSmall and 40 or 45
	local dtHead = Utils.mkLabel({
		text="아이템 상세", size=UDim2.new(1,0,0,dtHeadH),
		bg=C.BG_DARK, bgT=0.3, color=C.GOLD, ts=TS_TITLE, font=F.TITLE,
		parent=detail
	})
	
	-- 스크롤 가능한 콘텐츠 영역 (헤더와 푸터 사이)
	local footH = isSmall and 95 or 105
	local detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "DetailScroll"
	detailScroll.Size = UDim2.new(1, 0, 1, -(dtHeadH + footH))
	detailScroll.Position = UDim2.new(0, 0, 0, dtHeadH)
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.ScrollBarThickness = 3
	detailScroll.ScrollBarImageColor3 = C.GOLD
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	detailScroll.Parent = detail
	
	local PAD = isSmall and 10 or 15
	local iconSize = isSmall and 80 or 90
	
	InventoryUI.Refs.Detail.Name = Utils.mkLabel({
		text="SELECT ITEM", size=UDim2.new(1,-PAD*2,0,36), pos=UDim2.new(0,PAD,0,8),
		color=C.WHITE, ts=TS_DETAIL_NAME, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detailScroll
	})
	
	InventoryUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	InventoryUI.Refs.Detail.Icon.Size = UDim2.new(0, iconSize, 0, iconSize)
	InventoryUI.Refs.Detail.Icon.Position = UDim2.new(0, PAD, 0, 52)
	InventoryUI.Refs.Detail.Icon.BackgroundTransparency = 1; InventoryUI.Refs.Detail.Icon.Parent = detailScroll
	InventoryUI.Refs.Detail.PreviewIcon = InventoryUI.Refs.Detail.Icon
	
	InventoryUI.Refs.Detail.Desc = Utils.mkLabel({
		text="Description", size=UDim2.new(1,-(iconSize + PAD + 10),0,iconSize + 10),
		pos=UDim2.new(0, iconSize + PAD + 10, 0, 52),
		color=C.GRAY, ts=TS_DETAIL_DESC, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detailScroll
	})
	
	-- 내구도바 위치: 아이콘 아래
	local durY = 52 + iconSize + 6
	-- Durability Bar (Detail Panel)
	local durWrap = Utils.mkFrame({name="DurWrap", size=UDim2.new(1, -PAD*2, 0, isSmall and 14 or 16), pos=UDim2.new(0, PAD, 0, durY), bgT=1, vis=false, parent=detailScroll})
	local durBarBack = Utils.mkFrame({name="Back", size=UDim2.new(1, 0, 1, 0), bg=C.BG_SLOT, r=3, parent=durWrap})
	local durBarFill = Utils.mkFrame({name="Fill", size=UDim2.new(1, 0, 1, 0), bg=C.GOLD, r=3, parent=durBarBack})
	local durText = Utils.mkLabel({text="100/100", size=UDim2.new(1, 0, 1, 0), ts=TS_DUR, bold=true, color=C.WHITE, parent=durBarBack})
	
	InventoryUI.Refs.Detail.DurWrap = durWrap
	InventoryUI.Refs.Detail.DurFill = durBarFill
	InventoryUI.Refs.Detail.DurText = durText

	-- Attribute Badge (재료 속성 표시)
	local attrY = durY + (isSmall and 18 or 20)
	InventoryUI.Refs.Detail.AttrBadge = Utils.mkLabel({
		text="", size=UDim2.new(1,-PAD*2,0, isSmall and 22 or 24), pos=UDim2.new(0,PAD,0,attrY),
		color=C.GOLD, ts=TS_BADGE, font=F.TITLE, ax=Enum.TextXAlignment.Left, rich=true, vis=false, wrap=true, parent=detailScroll
	})

	-- Stats / StatsGrid 위치: 뱃지 아래
	local statsY = attrY + (isSmall and 26 or 28)
	
	InventoryUI.Refs.Detail.Stats = Utils.mkLabel({
		text="", size=UDim2.new(1,-PAD*2,0,180), pos=UDim2.new(0,PAD,0,statsY),
		color=C.WHITE, ts=TS_DETAIL_STAT, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, rich=true, parent=detailScroll
	})
	InventoryUI.Refs.Detail.Mats = InventoryUI.Refs.Detail.Stats -- Alias for crafting
	InventoryUI.Refs.Detail.Weight = InventoryUI.Refs.Detail.Stats

	-- Stats Grid (무기/도구/방어구 2칼럼 스펙 표시)
	local statsGrid = Utils.mkFrame({
		name="StatsGrid", size=UDim2.new(1,-PAD*2,0,0), pos=UDim2.new(0,PAD,0,statsY),
		bgT=1, vis=false, parent=detailScroll
	})
	statsGrid.AutomaticSize = Enum.AutomaticSize.Y
	local gridLayout = Instance.new("UIListLayout")
	gridLayout.Padding = UDim.new(0, isSmall and 3 or 5)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = statsGrid
	InventoryUI.Refs.Detail.StatsGrid = statsGrid

	-- [제작 진행표시] 로딩 스피너 및 프로그레스바 추가
	local progWrap = Utils.mkFrame({name="ProgWrap", size=UDim2.new(0, iconSize, 0, iconSize), pos=UDim2.new(0,PAD,0,50), bgT=1, vis=false, parent=detailScroll})
	InventoryUI.Refs.Detail.ProgWrap = progWrap
	
	local spinner = Instance.new("ImageLabel")
	spinner.Name = "Spinner"; spinner.Size = UDim2.new(1.2, 0, 1.2, 0); spinner.Position = UDim2.new(0.5, 0, 0.5, 0); spinner.AnchorPoint = Vector2.new(0.5,0.5)
	spinner.BackgroundTransparency = 1; spinner.Image = "rbxassetid://6034445544"; spinner.ImageColor3 = C.GOLD; spinner.ZIndex = 15; spinner.Parent = progWrap
	InventoryUI.Refs.Detail.Spinner = spinner

	local barBack = Utils.mkFrame({name="BarBack", size=UDim2.new(1, -PAD*2, 0, 6), pos=UDim2.new(0.5, 0, 0, durY - 5), anchor=Vector2.new(0.5, 0), bg=C.BG_SLOT, r=3, vis=false, parent=detailScroll})
	local barFill = Utils.mkFrame({name="Fill", size=UDim2.new(0, 0, 1, 0), bg=C.GOLD, r=3, parent=barBack})
	InventoryUI.Refs.Detail.ProgBar = barBack
	InventoryUI.Refs.Detail.ProgFill = barFill
	
	-- Detail Footer
	local dFoot = Utils.mkFrame({size=UDim2.new(1,-20,0,footH), pos=UDim2.new(0.5,0,1,-8), anchor=Vector2.new(0.5,1), bgT=1, parent=detail})
	
	local footList = Instance.new("UIListLayout"); footList.Padding=UDim.new(0, 6); footList.VerticalAlignment=Enum.VerticalAlignment.Bottom; footList.Parent=dFoot
	
	InventoryUI.Refs.Detail.BtnMain = Utils.mkBtn({
		text="[ EQUIP / USE ]", size=UDim2.new(1,0,0, isSmall and 42 or 48), bg=C.GOLD, r=4, font=F.TITLE, ts=TS_BTN, color=C.BG_DARK, parent=dFoot
	})
	InventoryUI.Refs.Detail.BtnUse = InventoryUI.Refs.Detail.BtnMain -- Alias
	
	InventoryUI.Refs.Detail.BtnDrop = Utils.mkBtn({
		text="[ DROP ]", size=UDim2.new(1,0,0, isSmall and 36 or 42), bg=C.BTN, r=4, font=F.TITLE, ts=TS_BTN_SUB, color=C.WHITE, parent=dFoot
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
	local craftArea = Utils.mkFrame({name="CraftFrame", size=isSmall and UDim2.new(1, 0, 1, 0) or UDim2.new(1, -300, 1, 0), bgT=1, vis=false, parent=content})
	InventoryUI.Refs.CraftFrame = craftArea
	local craftScroll = Instance.new("ScrollingFrame")
	craftScroll.Name = "CraftGrid"
	craftScroll.Size = UDim2.new(1, 0, 1, 0); craftScroll.BackgroundTransparency = 1; craftScroll.BorderSizePixel = 0; craftScroll.ScrollBarThickness = 4
	craftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	craftScroll.Parent = craftArea
	InventoryUI.Refs.CraftGrid = craftScroll
	
	local craftCellSize = isSmall and 68 or 75
	local cGrid = Instance.new("UIGridLayout")
	cGrid.CellSize = UDim2.new(0, craftCellSize, 0, craftCellSize)
	cGrid.CellPadding = UDim2.new(0, isSmall and 6 or 8, 0, isSmall and 6 or 8)
	cGrid.SortOrder = Enum.SortOrder.LayoutOrder; cGrid.Parent = craftScroll

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop = UDim.new(0, isSmall and 10 or 15); cPad.PaddingLeft = UDim.new(0, isSmall and 10 or 15)
	cPad.Parent = craftScroll
	
	InventoryUI.Refs.CraftGrid = craftScroll
	
	-- Drop/Split Modal Popup (반응형)
	local dropModalFrame = Utils.mkFrame({name="DropModal", size=UDim2.new(isSmall and 0.7 or 0.3, 0, isSmall and 0.45 or 0.4, 0), pos=UDim2.new(0.5, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bg=C.BG_PANEL, stroke=2, vis=false, parent=InventoryUI.Refs.Frame, z=100})
	local mRatio = Instance.new("UIAspectRatioConstraint"); mRatio.AspectRatio=1.2; mRatio.Parent=dropModalFrame
	InventoryUI.Refs.DropModal.Frame = dropModalFrame
	
	Utils.mkLabel({text="수량 입력", size=UDim2.new(1,0,0,40), pos=UDim2.new(0,0,0,10), ts=TS_TITLE, font=F.TITLE, parent=dropModalFrame})
	local box = Instance.new("TextBox")
	box.Name = "Input"; box.Size = UDim2.new(0.8,0,0, isSmall and 44 or 50); box.Position = UDim2.new(0.5,0,0.4,0); box.AnchorPoint = Vector2.new(0.5,0.5); box.BackgroundColor3 = C.BG_SLOT; box.TextColor3 = C.WHITE; box.Text = "1"; box.ClearTextOnFocus = true; box.Font = F.NUM; box.TextSize = isSmall and 22 or 24
	local bRound = Instance.new("UICorner"); bRound.CornerRadius = UDim.new(0, 4); bRound.Parent = box
	box.Parent = dropModalFrame
	InventoryUI.Refs.DropModal.Input = box
	
	InventoryUI.Refs.DropModal.MaxLabel = Utils.mkLabel({text="(최대: 1)", size=UDim2.new(1,0,0,20), pos=UDim2.new(0,0,0.5,0), ts=TS_SMALL, color=C.GRAY, parent=dropModalFrame})
	
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
	
	local confirmBtn = Utils.mkBtn({text="확인", size=UDim2.new(0.45,0,1,0), bg=C.GOLD_SEL, font=F.TITLE, ts=TS_BTN, color=C.BG_PANEL, parent=mBtnArea})
	local cancelBtn = Utils.mkBtn({text="취소", size=UDim2.new(0.45,0,1,0), bg=C.BTN, font=F.TITLE, ts=TS_BTN_SUB, parent=mBtnArea})
	
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

local function clearStatsGrid(grid)
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
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
		d.StatsGrid.Visible = false
		clearStatsGrid(d.StatsGrid)
		d.Desc.Text = ""
		d.Mats.Text = ""
		d.BtnMain.Visible = false
		d.BtnDrop.Visible = false
	end
end

function InventoryUI.UpdateSlotSelectionHighlight(selectedIndex, items, DataHelper)
	for i = 1, Balance.MAX_INV_SLOTS do
		local s = InventoryUI.Refs.Slots[i]
		if not s then continue end
		local st = s.frame:FindFirstChildOfClass("UIStroke")
		if st then
			if i == selectedIndex then
				st.Color = C.GOLD_SEL
				st.Thickness = 2.5
			else
				st.Color = C.BORDER_DIM
				st.Thickness = 1
			end
		end
	end
end

function InventoryUI.RefreshSlots(items, getItemIcon, __C, DataHelper, maxSlots)
	local slots = InventoryUI.Refs.Slots
	local activeSlots = maxSlots or Balance.BASE_INV_SLOTS

	for i = 1, Balance.MAX_INV_SLOTS do
		local s = slots[i]
		if not s then continue end
		
		-- 활성 칸 초과 슬롯은 숨김
		s.frame.Visible = (i <= activeSlots)
		
		local item = items[i]
		local st = s.frame:FindFirstChildOfClass("UIStroke")
		
		if item and item.itemId then
			s.icon.Image = getItemIcon(item.itemId)
			s.icon.Visible = true
			s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
			
			local itemData = DataHelper.GetData("ItemData", item.itemId)
			if st then
				st.Color = C.BORDER_DIM
				st.Thickness = 1
			end
			
			if item.durability and itemData and itemData.durability then
				local ratio = math.clamp(item.durability / itemData.durability, 0, 1)
				s.durBg.Visible = true
				s.durFill.Size = UDim2.new(ratio, 0, 1, 0)
				
				if ratio > 0.5 then
					s.durFill.BackgroundColor3 = Color3.fromRGB(120, 200, 80)
				elseif ratio > 0.2 then
					s.durFill.BackgroundColor3 = Color3.fromRGB(230, 180, 60)
				else
					s.durFill.BackgroundColor3 = Color3.fromRGB(200, 70, 50)
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

function InventoryUI.UpdateSlotInfo(cur, max, __C)
	if InventoryUI.Refs.WeightText then
		InventoryUI.Refs.WeightText.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
	end
end

function InventoryUI.UpdateCurrency(amount)
	if InventoryUI.Refs.CurrencyText then
		InventoryUI.Refs.CurrencyText.Text = string.format("골드: %d", math.floor(tonumber(amount) or 0))
	end
end

local function createStatRow(parent, label, value, hexColor, order)
	local ts = (InventoryUI._ts and InventoryUI._ts.detailStat) or 16
	local rowH = ts + 8
	local row = Instance.new("Frame")
	row.Name = "StatRow_" .. order
	row.Size = UDim2.new(1, 0, 0, rowH)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local nameL = Instance.new("TextLabel")
	nameL.Size = UDim2.new(0.55, 0, 1, 0)
	nameL.BackgroundTransparency = 1
	nameL.Text = label
	nameL.TextColor3 = Color3.fromHex("#AAAAAA")
	nameL.TextSize = ts
	nameL.Font = F.NORMAL
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.TextTruncate = Enum.TextTruncate.AtEnd
	nameL.Parent = row

	local valL = Instance.new("TextLabel")
	valL.Size = UDim2.new(0.45, 0, 1, 0)
	valL.Position = UDim2.new(0.55, 0, 0, 0)
	valL.BackgroundTransparency = 1
	valL.Text = value
	valL.TextColor3 = Color3.fromHex(hexColor)
	valL.TextSize = ts
	valL.Font = F.TITLE
	valL.TextXAlignment = Enum.TextXAlignment.Left
	valL.TextTruncate = Enum.TextTruncate.AtEnd
	valL.Parent = row
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
		
		local weightStr = string.format("수량: %d", (data.count or 1))
		d.Stats.Text = UILocalizer.Localize(weightStr)
		d.Stats.Visible = true
		d.StatsGrid.Visible = false
		clearStatsGrid(d.StatsGrid)
		
		-- 무기/도구/방어구 스펙 표시 (속성 효과 반영, 2칼럼 정렬)
		if itemData and not (data.inputs or data.requirements) then
			local iType = itemData.type
			if iType == "WEAPON" or iType == "TOOL" then
				-- 속성 효과 합산
				local bonusDmg, bonusCrit, bonusCritDmg, bonusDur = 0, 0, 0, 0
				if data.attributes then
					for attrId, level in pairs(data.attributes) do
						local fx = MaterialAttributeData.getEffectValues(attrId, level)
						if fx then
							bonusDmg = bonusDmg + (fx.damageMult or 0)
							bonusCrit = bonusCrit + (fx.critChance or 0)
							bonusCritDmg = bonusCritDmg + (fx.critDamageMult or 0)
							bonusDur = bonusDur + (fx.durabilityMult or 0)
						end
					end
				end
				
				local baseDmg = itemData.damage or 0
				local finalDmg = math.floor(baseDmg * (1 + bonusDmg) + 0.5)
				local finalCrit = math.floor(bonusCrit * 100 + 0.5)
				local finalCritDmg = math.floor((1.5 + bonusCritDmg) * 100 + 0.5)
				local baseDur = itemData.durability or 0
				local curDur = data.durability or baseDur
				local maxDur = math.floor(baseDur * (1 + bonusDur) + 0.5)
				
				local dmgColor = bonusDmg > 0 and "#8CDC64" or "#FFFFFF"
				local critColor = bonusCrit > 0 and "#8CDC64" or "#FFFFFF"
				local critDmgColor = bonusCritDmg > 0 and "#8CDC64" or "#FFFFFF"
				local durColor = bonusDur > 0 and "#8CDC64" or "#FFFFFF"
				
				d.Stats.Visible = false
				d.StatsGrid.Visible = true
				createStatRow(d.StatsGrid, "공격력", tostring(finalDmg), dmgColor, 1)
				createStatRow(d.StatsGrid, "치명타 확률", finalCrit .. "%", critColor, 2)
				createStatRow(d.StatsGrid, "치명타 피해량", finalCritDmg .. "%", critDmgColor, 3)
				createStatRow(d.StatsGrid, "내구도", math.floor(curDur) .. " / " .. maxDur, durColor, 4)
				
			elseif iType == "ARMOR" then
				-- 방어구 속성 효과 합산
				local bonusDef, bonusHp, bonusDur = 0, 0, 0
				local bonusHeat, bonusCold, bonusHumid = 0, 0, 0
				if data.attributes then
					for attrId, level in pairs(data.attributes) do
						local fx = MaterialAttributeData.getEffectValues(attrId, level)
						if fx then
							bonusDef = bonusDef + (fx.defenseMult or 0)
							bonusHp = bonusHp + (fx.maxHealthMult or 0)
							bonusDur = bonusDur + (fx.durabilityMult or 0)
							bonusHeat = bonusHeat + (fx.heatResist or 0)
							bonusCold = bonusCold + (fx.coldResist or 0)
							bonusHumid = bonusHumid + (fx.humidResist or 0)
						end
					end
				end
				
				local baseDef = itemData.defense or 0
				local finalDef = math.floor(baseDef * (1 + bonusDef) + 0.5)
				local finalHp = math.floor(bonusHp * 100 + 0.5)
				local baseDur = itemData.durability or 0
				local curDur = data.durability or baseDur
				local maxDur = math.floor(baseDur * (1 + bonusDur) + 0.5)
				
				local defColor = bonusDef > 0 and "#8CDC64" or "#FFFFFF"
				local hpColor = bonusHp > 0 and "#8CDC64" or "#FFFFFF"
				local durColor = bonusDur > 0 and "#8CDC64" or "#FFFFFF"
				
				d.Stats.Visible = false
				d.StatsGrid.Visible = true
				local order = 0
				order = order + 1; createStatRow(d.StatsGrid, "방어력", tostring(finalDef), defColor, order)
				order = order + 1; createStatRow(d.StatsGrid, "추가 체력", "+" .. finalHp .. "%", hpColor, order)
				order = order + 1; createStatRow(d.StatsGrid, "내구도", math.floor(curDur) .. " / " .. maxDur, durColor, order)
				
				local heatPct = math.floor(bonusHeat * 100 + 0.5)
				local coldPct = math.floor(bonusCold * 100 + 0.5)
				local humidPct = math.floor(bonusHumid * 100 + 0.5)
				if heatPct ~= 0 then
					order = order + 1; createStatRow(d.StatsGrid, "더위 내성", "+" .. heatPct .. "%", "#8CDC64", order)
				end
				if coldPct ~= 0 then
					order = order + 1; createStatRow(d.StatsGrid, "추위 내성", "+" .. coldPct .. "%", "#8CDC64", order)
				end
				if humidPct ~= 0 then
					order = order + 1; createStatRow(d.StatsGrid, "습기 내성", "+" .. humidPct .. "%", "#8CDC64", order)
				end
			end
		end
		
		-- 속성/효과 뱃지 표시 (재료=속성명, 도구·무기·방어구=효과 설명)
		if d.AttrBadge then
			if data.attributes and next(data.attributes) then
				local isProduct = itemData and (itemData.type == "TOOL" or itemData.type == "WEAPON" or itemData.type == "ARMOR")
				local parts = {}
				for attrId, level in pairs(data.attributes) do
					local attrInfo = MaterialAttributeData.getAttribute(attrId)
					if attrInfo then
						local color = attrInfo.positive and "#8CDC64" or "#E63232"
						local symbol = attrInfo.positive and "▲" or "▼"
						local displayName = isProduct and attrInfo.effect or attrInfo.name
						table.insert(parts, string.format(
							'<font color="%s">%s %s Lv.%d</font>',
							color, symbol, displayName, level
						))
					end
				end
				if #parts > 0 then
					d.AttrBadge.Text = table.concat(parts, "  ")
					d.AttrBadge.Visible = true
				else
					d.AttrBadge.Visible = false
				end
			else
				d.AttrBadge.Visible = false
			end
		end
		
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
				d.BtnMain.BackgroundColor3 = C.BG_SLOT
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
					d.BtnMain.BackgroundColor3 = C.BG_SLOT
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
				d.DurFill.BackgroundColor3 = Color3.fromRGB(120, 200, 80)
			elseif ratio > 0.2 then
				d.DurFill.BackgroundColor3 = Color3.fromRGB(230, 180, 60)
			else
				d.DurFill.BackgroundColor3 = Color3.fromRGB(200, 70, 50)
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
		d.StatsGrid.Visible = false
		clearStatsGrid(d.StatsGrid)
		d.Desc.Text = ""
		d.Mats.Text = ""
		d.BtnMain.Visible = false
		d.BtnDrop.Visible = false
		if d.AttrBadge then d.AttrBadge.Visible = false end
	end
end

return InventoryUI
