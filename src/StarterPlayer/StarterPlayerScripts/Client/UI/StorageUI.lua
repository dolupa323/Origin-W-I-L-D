-- StorageUI.lua
-- 창고(보관함) UI
-- 인벤토리와 유사한 디자인, 창고 슬롯과 플레이어 인벤토리를 동시에 보여줌

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

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
		bg = Color3.new(0,0,0),
		bgT = 0.6,
		vis = false,
		parent = parent
	})
	
	-- 2. Main Window
	local main = Utils.mkWindow({
		name = "StorageWindow",
		size = UDim2.new(0, 750, 0, 500),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = Color3.fromRGB(15, 15, 18),
		bgT = 0.3,
		r = 0,
		stroke = 1,
		strokeC = Color3.fromRGB(60, 60, 60),
		parent = StorageUI.Refs.Frame
	})
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	StorageUI.Refs.Title = Utils.mkLabel({
		text="보관함", pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), 
		ts=20, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=header
	})
	
	Utils.mkBtn({
		text="X", size=UDim2.new(0, 40, 0, 40), pos=UDim2.new(1, -5, 0, 5), anchor=Vector2.new(1, 0), 
		bgT=1, ts=24, color=C.WHITE, 
		fn=function() UIManager.closeStorage() end, 
		parent=main
	})

	-- [Content]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 20)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = content

	-- Left: Storage (20 slots default)
	local leftPanel = Utils.mkFrame({name="Left", size=UDim2.new(0, 340, 1, 0), bgT=1, parent=content})
	Utils.mkLabel({text="보관함 아이템", size=UDim2.new(1,0,0,30), color=C.GOLD, ts=16, parent=leftPanel})
	
	local sScroll = Instance.new("ScrollingFrame")
	sScroll.Size = UDim2.new(1, 0, 1, -35); sScroll.Position = UDim2.new(0,0,0,30)
	sScroll.BackgroundTransparency=1; sScroll.BorderSizePixel=0; sScroll.ScrollBarThickness=4
	sScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sScroll.Parent = leftPanel
	
	local sGrid = Instance.new("UIGridLayout")
	sGrid.CellSize = UDim2.new(0, 60, 0, 60); sGrid.CellPadding = UDim2.new(0, 6, 0, 6); sGrid.Parent = sScroll
	StorageUI.Refs.StorageGrid = sScroll

	-- Right: Player Inventory (For transferring)
	local rightPanel = Utils.mkFrame({name="Right", size=UDim2.new(0, 340, 1, 0), bgT=1, parent=content})
	Utils.mkLabel({text="내 소지품", size=UDim2.new(1,0,0,30), color=C.WHITE, ts=16, parent=rightPanel})
	
	local iScroll = Instance.new("ScrollingFrame")
	iScroll.Size = UDim2.new(1, 0, 1, -35); iScroll.Position = UDim2.new(0,0,0,30)
	iScroll.BackgroundTransparency=1; iScroll.BorderSizePixel=0; iScroll.ScrollBarThickness=4
	iScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	iScroll.Parent = rightPanel
	
	local iGrid = Instance.new("UIGridLayout")
	iGrid.CellSize = UDim2.new(0, 60, 0, 60); iGrid.CellPadding = UDim2.new(0, 6, 0, 6); iGrid.Parent = iScroll
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
