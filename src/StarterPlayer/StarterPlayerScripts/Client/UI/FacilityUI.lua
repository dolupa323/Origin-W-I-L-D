-- FacilityUI.lua
-- 요리, 제련 등 생산 시설 전용 UI
-- 연료 기반 상태 표시 및 인벤토리 상호작용

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local Enums = require(ReplicatedStorage.Shared.Enums.Enums)
local C = Theme.Colors
local F = Theme.Fonts

local FacilityUI = {}
FacilityUI.Refs = {
	Frame = nil,
	Title = nil,
	StateLabel = nil,
	FuelLabel = nil,
	ProgressBar = nil,
	
	FuelSlot = nil,
	InputSlot = nil,
	OutputSlot = nil,
	
	InventoryGrid = nil,
	InventorySlots = {},
}

local function mkSlot(parent, name, UIManager)
	local slot = Utils.mkSlot({
		name = name,
		size = UDim2.new(0, 70, 0, 70),
		parent = parent
	})
	return slot
end

function FacilityUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
	
	-- 1. Full screen overlay
	FacilityUI.Refs.Frame = Utils.mkFrame({
		name = "FacilityMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.6,
		vis = false,
		parent = parent
	})
	
	-- 2. Main Window
	local main = Utils.mkWindow({
		name = "FacilityWindow",
		size = UDim2.new(0, 800, 0, 520),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = Color3.fromRGB(15, 15, 18),
		bgT = 0.2,
		r = 0,
		stroke = 1,
		strokeC = Color3.fromRGB(80, 80, 80),
		parent = FacilityUI.Refs.Frame
	})
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	FacilityUI.Refs.Title = Utils.mkLabel({
		text="생산 시설", pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), 
		ts=22, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=header
	})
	
	Utils.mkBtn({
		text="X", size=UDim2.new(0, 40, 0, 40), pos=UDim2.new(1, -5, 0, 5), anchor=Vector2.new(1, 0), 
		bgT=1, ts=24, color=C.WHITE, 
		fn=function() UIManager.closeFacility() end, 
		parent=main
	})

	-- [Content Layout]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -30, 1, -70), pos=UDim2.new(0, 15, 0, 55), bgT=1, parent=main})
	
	-- Left Panel: Facility (400px)
	local facilityPanel = Utils.mkFrame({name="Facility", size=UDim2.new(0, 420, 1, 0), bgT=1, parent=content})
	
	-- Status Box
	local statusBox = Utils.mkFrame({
		name="Status", size=UDim2.new(1, 0, 0, 140), bg=Color3.fromRGB(30, 30, 35), bgT=0.4, r=4, stroke=1, parent=facilityPanel
	})
	
	FacilityUI.Refs.StateLabel = Utils.mkLabel({
		text="상태: 대기 중", size=UDim2.new(1, -40, 0, 30), pos=UDim2.new(0, 20, 0, 15),
		color=C.WHITE, ts=18, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=statusBox
	})
	
	FacilityUI.Refs.FuelLabel = Utils.mkLabel({
		text="남은 연료: 0s", size=UDim2.new(1, -40, 0, 20), pos=UDim2.new(0, 20, 0, 45),
		color=Color3.fromRGB(255, 180, 80), ts=14, ax=Enum.TextXAlignment.Left, parent=statusBox
	})
	
	-- Progress Section
	Utils.mkLabel({text="진행률", size=UDim2.new(1, -40, 0, 20), pos=UDim2.new(0, 20, 0, 80), color=C.GRAY, ts=12, ax=Enum.TextXAlignment.Left, parent=statusBox})
	local barData = Utils.mkBar({
		name="Progress", size=UDim2.new(1, -40, 0, 12), pos=UDim2.new(0.5, 0, 0, 110), anchor=Vector2.new(0.5, 0),
		fillC=C.GOLD, r=2, parent=statusBox
	})
	FacilityUI.Refs.ProgressBar = barData.fill
	barData.label.Visible = false

	-- Production Grid (Input -> Arrow -> Output)
	local prodGrid = Utils.mkFrame({name="Grid", size=UDim2.new(1, 0, 1, -155), pos=UDim2.new(0, 0, 0, 155), bgT=1, parent=facilityPanel})
	
	local slotSize = 80
	
	-- 연료 슬롯
	Utils.mkLabel({text="연료", pos=UDim2.new(0, 10, 0, 10), size=UDim2.new(0, slotSize, 0, 20), color=Color3.fromRGB(255, 150, 50), ts=14, parent=prodGrid})
	FacilityUI.Refs.FuelSlot = mkSlot(prodGrid, "FuelSlot", UIManager)
	FacilityUI.Refs.FuelSlot.frame.Position = UDim2.new(0, 10, 0, 35)
	FacilityUI.Refs.FuelSlot.frame.Size = UDim2.new(0, slotSize, 0, slotSize)
	FacilityUI.Refs.FuelSlot.frame.BackgroundColor3 = Color3.fromRGB(45, 30, 20)
	FacilityUI.Refs.FuelSlot.click.MouseButton1Click:Connect(function()
		UIManager._onFacilityFuelClick()
	end)

	-- 재료 슬롯
	Utils.mkLabel({text="재료", pos=UDim2.new(0, 120, 0, 10), size=UDim2.new(0, slotSize, 0, 20), color=C.GOLD, ts=14, parent=prodGrid})
	FacilityUI.Refs.InputSlot = mkSlot(prodGrid, "InputSlot", UIManager)
	FacilityUI.Refs.InputSlot.frame.Position = UDim2.new(0, 120, 0, 35)
	FacilityUI.Refs.InputSlot.frame.Size = UDim2.new(0, slotSize, 0, slotSize)
	FacilityUI.Refs.InputSlot.frame.BackgroundColor3 = Color3.fromRGB(40, 45, 40)
	FacilityUI.Refs.InputSlot.click.MouseButton1Click:Connect(function()
		UIManager._onFacilityInputClick()
	end)

	-- 화살표
	Utils.mkLabel({text="→", pos=UDim2.new(0, 210, 0, 60), size=UDim2.new(0, 30, 0, 30), color=C.GRAY, ts=30, parent=prodGrid})

	-- 결과물 슬롯
	Utils.mkLabel({text="결과물", pos=UDim2.new(0, 250, 0, 10), size=UDim2.new(0, slotSize, 0, 20), color=Color3.fromRGB(150, 255, 150), ts=14, parent=prodGrid})
	FacilityUI.Refs.OutputSlot = mkSlot(prodGrid, "OutputSlot", UIManager)
	FacilityUI.Refs.OutputSlot.frame.Position = UDim2.new(0, 250, 0, 35)
	FacilityUI.Refs.OutputSlot.frame.Size = UDim2.new(0, slotSize, 0, slotSize)
	FacilityUI.Refs.OutputSlot.frame.BackgroundColor3 = Color3.fromRGB(30, 40, 30)
	FacilityUI.Refs.OutputSlot.click.MouseButton1Click:Connect(function()
		UIManager._onCollectFacility()
	end)
	
	-- 수거 버튼

	local collectBtn = Utils.mkBtn({
		text="일괄 수거", size=UDim2.new(0, 120, 0, 40), pos=UDim2.new(0.5, 0, 1, -10), anchor=Vector2.new(0.5, 1),
		bg=C.GOLD, color=Color3.fromRGB(20, 20, 20), ts=16, font=F.TITLE,
		fn=function() UIManager._onCollectFacility() end,
		parent=facilityPanel
	})

	-- Right Panel: Inventory (350px)
	local invPanel = Utils.mkFrame({name="Inventory", size=UDim2.new(0, 330, 1, 0), pos=UDim2.new(1, -330, 0, 0), bgT=1, parent=content})
	Utils.mkLabel({text="내 소지품", size=UDim2.new(1, 0, 0, 30), color=C.WHITE, ts=14, ax=Enum.TextXAlignment.Left, parent=invPanel})
	
	local iScroll = Instance.new("ScrollingFrame")
	iScroll.Size = UDim2.new(1, 0, 1, -35); iScroll.Position = UDim2.new(0, 0, 0, 30)
	iScroll.BackgroundTransparency=1; iScroll.BorderSizePixel=0; iScroll.ScrollBarThickness=4
	iScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	iScroll.Parent = invPanel
	
	local iGrid = Instance.new("UIGridLayout")
	iGrid.CellSize = UDim2.new(0, 60, 0, 60); iGrid.CellPadding = UDim2.new(0, 6, 0, 6); iGrid.Parent = iScroll
	FacilityUI.Refs.InventoryGrid = iScroll

	-- Inventory Slots (Init)
	for i=1, 40 do
		local slot = Utils.mkSlot({
			name = "Inv_" .. i,
			size = UDim2.new(0, 60, 0, 60),
			parent = iScroll
		})
		FacilityUI.Refs.InventorySlots[i] = slot
		slot.click.MouseButton1Click:Connect(function()
			UIManager._onInventoryToFacility(i)
		end)
	end
end

function FacilityUI.Refresh(fData, invItems, getItemIcon, getItemData, UIManager)
	if not FacilityUI.Refs.Frame then return end
	
	-- 1. Facility State Update
	local stateName = "대기 중"
	local stateColor = C.WHITE
	if fData.state == Enums.FacilityState.ACTIVE then
		stateName = "가동 중"
		stateColor = C.GREEN
	elseif fData.state == Enums.FacilityState.NO_POWER then
		stateName = "연료 없음"
		stateColor = C.RED
	elseif fData.state == Enums.FacilityState.FULL then
		stateName = "결과물 가득 참"
		stateColor = C.YELLOW
	end
	FacilityUI.Refs.StateLabel.Text = "상태: " .. stateName
	FacilityUI.Refs.StateLabel.TextColor3 = stateColor
	
	FacilityUI.Refs.FuelLabel.Text = string.format("남은 연료: %.0fs", fData.currentFuel or 0)
	
	-- Progress Bar
	local progress = 0
	if fData.effectiveCraftTime and fData.effectiveCraftTime > 0 then
		progress = math.clamp(fData.processProgress / fData.effectiveCraftTime, 0, 1)
	end
	FacilityUI.Refs.ProgressBar.Size = UDim2.new(progress, 0, 1, 0)

	-- Slots
	local function updateSlot(slot, item, isFuel)
		slot.icon.Visible = false
		slot.countLabel.Visible = false
		if item then
			slot.icon.Image = getItemIcon(item.itemId)
			slot.icon.Visible = true
			if item.count > 1 then
				slot.countLabel.Text = tostring(item.count)
				slot.countLabel.Visible = true
			end
		end
	end

	updateSlot(FacilityUI.Refs.FuelSlot, fData.fuelSlot)
	updateSlot(FacilityUI.Refs.InputSlot, fData.inputSlot)
	
	-- Output (멀티 출력물이지만 UI상으로는 첫번째만 혹은 요약 표시)
	local outputItem = nil
	if fData.outputSlot then
		for id, count in pairs(fData.outputSlot) do
			outputItem = { itemId = id, count = count }
			break
		end
	end
	updateSlot(FacilityUI.Refs.OutputSlot, outputItem)

	-- 2. Inventory Refresh
	for i=1, 40 do
		local slot = FacilityUI.Refs.InventorySlots[i]
		local item = invItems[i]
		slot.icon.Visible = false
		slot.countLabel.Visible = false
		if item then
			slot.icon.Image = getItemIcon(item.itemId)
			slot.icon.Visible = true
			if item.count > 1 then
				slot.countLabel.Text = tostring(item.count)
				slot.countLabel.Visible = true
			end
		end
	end
end

return FacilityUI
