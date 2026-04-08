-- StorageUI.lua
-- 창고(보관함) UI
-- 인벤토리와 유사한 디자인, 창고 슬롯과 플레이어 인벤토리를 동시에 보여줌

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local StorageUI = {}
StorageUI.Refs = {
	Frame = nil,
	StorageGrid = nil,
	InventoryGrid = nil,
	StorageSlots = {},
	InventorySlots = {},
	Title = nil,
	CloseBtn = nil,
}

local function mkSlot(parent, index, type, UIManager)
	local slot = Utils.mkSlot({
		name = type .. "_" .. index,
		size = UDim2.new(0, 64, 0, 64),
		parent = parent
	})
	
	-- 클릭 이벤트 연결 (최초 1회)
	slot.click.MouseButton1Click:Connect(function()
		local fromType = (type == "Storage") and "storage" or "player"
		UIManager._onStorageSlotClick(index, fromType)
	end)
	
	return slot
end

function StorageUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
	
	-- 1. Full screen overlay
	StorageUI.Refs.Frame = Utils.mkFrame({
		name = "StorageMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent
	})
	
	-- 반응형 사이즈: 모바일은 거의 전체화면, 데스크톱은 적당 크기
	local mainSize, mainPos
	if isSmall then
		mainSize = UDim2.new(0.96, 0, 0.88, 0)
		mainPos = UDim2.new(0.5, 0, 0.5, 0)
	else
		mainSize = UDim2.new(0, 750, 0, 500)
		mainPos = UDim2.new(0.5, 0, 0.5, 0)
	end

	-- 2. Main Window
	local main = Utils.mkWindow({
		name = "StorageWindow",
		size = mainSize,
		pos = mainPos,
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER,
		parent = StorageUI.Refs.Frame
	})

	-- 최대 크기 제한 (모바일에서 너무 커지지 않도록)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(800, 600)
	sizeConstraint.Parent = main
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	StorageUI.Refs.Title = Utils.mkLabel({
		text="보관함", pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), 
		ts=20, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=header
	})
	
	local closeBtnSize = isSmall and 44 or 36
	Utils.mkBtn({
		text="X", size=UDim2.new(0, closeBtnSize, 0, closeBtnSize), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1, 0.5),
		bg=C.BTN, bgT=0.5, ts=20, color=C.WHITE,
		fn=function() UIManager.closeStorage() end,
		parent=header
	})

	-- [Content] — 모바일: 세로 배치, 데스크톱: 가로 배치
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
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

	-- 패널/셀 크기: 반응형
	local panelSize, cellSize, cellPad
	if isSmall then
		panelSize = UDim2.new(1, 0, 0.48, 0)
		cellSize = UDim2.new(0, 54, 0, 54)
		cellPad = UDim2.new(0, 5, 0, 5)
	else
		panelSize = UDim2.new(0.5, -10, 1, 0)
		cellSize = UDim2.new(0, 60, 0, 60)
		cellPad = UDim2.new(0, 6, 0, 6)
	end

	-- Left: Storage
	local leftPanel = Utils.mkFrame({name="Left", size=panelSize, bg=C.BG_PANEL, bgT=T.PANEL, r=6, parent=content})
	Utils.mkLabel({text="보관함 아이템", size=UDim2.new(1,0,0,30), color=C.GOLD, ts=16, parent=leftPanel})
	
	local sScroll = Instance.new("ScrollingFrame")
	sScroll.Size = UDim2.new(1, 0, 1, -35); sScroll.Position = UDim2.new(0,0,0,30)
	sScroll.BackgroundTransparency=1; sScroll.BorderSizePixel=0; sScroll.ScrollBarThickness=4
	sScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sScroll.ClipsDescendants = true
	sScroll.Parent = leftPanel

	-- 패딩 추가: 슬롯 테두리가 잘리지 않도록
	local sPad = Instance.new("UIPadding")
	sPad.PaddingLeft = UDim.new(0, 4)
	sPad.PaddingRight = UDim.new(0, 4)
	sPad.PaddingTop = UDim.new(0, 4)
	sPad.PaddingBottom = UDim.new(0, 4)
	sPad.Parent = sScroll
	
	local sGrid = Instance.new("UIGridLayout")
	sGrid.CellSize = cellSize; sGrid.CellPadding = cellPad; sGrid.Parent = sScroll
	StorageUI.Refs.StorageGrid = sScroll

	-- Right: Player Inventory
	local rightPanel = Utils.mkFrame({name="Right", size=panelSize, bg=C.BG_PANEL, bgT=T.PANEL, r=6, parent=content})
	Utils.mkLabel({text="내 소지품", size=UDim2.new(1,0,0,30), color=C.WHITE, ts=16, parent=rightPanel})
	
	local iScroll = Instance.new("ScrollingFrame")
	iScroll.Size = UDim2.new(1, 0, 1, -35); iScroll.Position = UDim2.new(0,0,0,30)
	iScroll.BackgroundTransparency=1; iScroll.BorderSizePixel=0; iScroll.ScrollBarThickness=4
	iScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	iScroll.ClipsDescendants = true
	iScroll.Parent = rightPanel

	-- 패딩 추가: 슬롯 테두리가 잘리지 않도록
	local iPad = Instance.new("UIPadding")
	iPad.PaddingLeft = UDim.new(0, 4)
	iPad.PaddingRight = UDim.new(0, 4)
	iPad.PaddingTop = UDim.new(0, 4)
	iPad.PaddingBottom = UDim.new(0, 4)
	iPad.Parent = iScroll
	
	local iGrid = Instance.new("UIGridLayout")
	iGrid.CellSize = cellSize; iGrid.CellPadding = cellPad; iGrid.Parent = iScroll
	StorageUI.Refs.InventoryGrid = iScroll

	-- Build Slots (Cap: 40)
	for i=1, 40 do
		local slot = mkSlot(sScroll, i, "Storage", UIManager)
		StorageUI.Refs.StorageSlots[i] = slot
		slot.frame.Visible = false 
	end

	for i=1, 40 do
		local slot = mkSlot(iScroll, i, "Inventory", UIManager)
		StorageUI.Refs.InventorySlots[i] = slot
	end
end

function StorageUI.Refresh(storageData, inventoryData, getItemIcon, UIManager)
	if not StorageUI.Refs.Frame then return end
	
	-- 1. Storage Refresh
	local maxSlots = storageData.maxSlots or 20
	for i=1, 40 do
		local slot = StorageUI.Refs.StorageSlots[i]
		if i <= maxSlots then
			slot.frame.Visible = true
			slot.icon.Visible = false
			slot.countLabel.Visible = false
			slot.itemId = nil
			
			-- 현재 아이템 찾기
			local item = nil
			for _, si in ipairs(storageData.slots or {}) do
				if si.slot == i then item = si; break end
			end
			
			if item then
				slot.itemId = item.itemId
				slot.icon.Image = getItemIcon(item.itemId)
				slot.icon.Visible = true
				if item.count > 1 then
					slot.countLabel.Text = tostring(item.count)
					slot.countLabel.Visible = true
				end
			end
		else
			slot.frame.Visible = false
		end
	end
	
	-- 2. Inventory Refresh
	for i=1, 40 do
		local slot = StorageUI.Refs.InventorySlots[i]
		slot.icon.Visible = false
		slot.countLabel.Visible = false
		slot.itemId = nil
		
		local item = inventoryData[i]
		if item then
			slot.itemId = item.itemId
			slot.icon.Image = getItemIcon(item.itemId)
			slot.icon.Visible = true
			if item.count > 1 then
				slot.countLabel.Text = tostring(item.count)
				slot.countLabel.Visible = true
			end
		end
	end
end

return StorageUI
