-- FacilityUI.lua
-- 요리, 제련 등 생산 시설 전용 UI (리뉴얼: 레시피 선택 기반 제작)
-- Durango Commissioned Crafting 스타일 반영

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local Enums = require(ReplicatedStorage.Shared.Enums.Enums)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local UIManagerRef = nil
local currentSelectedRecipe = nil
local currentCraftCount = 1
local maxCraftCount = 1
local currentCanCraft = false
local currentTab = "WEAPON_TOOL" -- 기본 탭
local currentRawRecipeList = {} -- 전체 레시피 백업

local FacilityUI = {}
FacilityUI.Refs = {
	Frame = nil,
	Title = nil,
	RecipeGrid = nil,
	DetailFrame = nil,
	Detail = {
		Name = nil,
		Icon = nil,
		Time = nil,
		Mats = nil,
		QtyWrap = nil,
		QtyLabel = nil,
		QtyMinus = nil,
		QtyPlus = nil,
		Btn = nil,
		BagCount = nil,
	},
	QueueGrid = nil,
	HealthBar = {
		Frame = nil,
		Fill = nil,
		Label = nil,
	},
	Tabs = {}, -- { [tabId] = { Frame, Label } }
}

local TABS = {
	{ id = "BLOCK", name = "블록가공", categories = { "BLOCK_PROCESS" } },
	{ id = "WEAPON_TOOL", name = "무기, 도구 제작", categories = { "WEAPON", "TOOL", "AMMO" } },
	{ id = "ARMOR", name = "방어구 제작", categories = { "ARMOR" } },
	{ id = "PROCESSING", name = "가공", categories = { "RESOURCE" } },
}

function FacilityUI.Init(parent, UIManager, isMobile)
	UIManagerRef = UIManager
	local isSmall = isMobile
	
	-- 1. Full screen overlay
	FacilityUI.Refs.Frame = Utils.mkFrame({
		name = "FacilityMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent
	})
	
	-- 2. Main Window (Translucent)
	local main = Utils.mkWindow({
		name = "FacilityWindow",
		size = UDim2.new(0.85, 0, 0.88, 0), -- Proportional scale
		maxSize = Vector2.new(1200, 900),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER,
		ratio = 1.4, -- Balanced ratio for crafting
		parent = FacilityUI.Refs.Frame
	})
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	FacilityUI.Refs.Title = Utils.mkLabel({
		text=UILocalizer.Localize("제작"), pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), 
		ts=24, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header
	})
	
	-- [Durability Bar]
	local hpFrame = Utils.mkFrame({
		name="Durability", size=UDim2.new(0, 150, 0, 16), pos=UDim2.new(0.5, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5),
		bg=C.BG_SLOT, r=3, parent=header
	})
	local hpFill = Utils.mkFrame({
		name="Fill", size=UDim2.new(1, 0, 1, 0), bg=C.GREEN, r=3, parent=hpFrame
	})
	local hpLabel = Utils.mkLabel({
		text=UILocalizer.Localize("내구도 100%"), size=UDim2.new(1, 0, 1, 0), ts=12, color=C.WHITE, parent=hpFrame
	})
	FacilityUI.Refs.HealthBar = { Frame = hpFrame, Fill = hpFill, Label = hpLabel }
	
	-- Close Button (Image style)
	local closeBtn = Utils.mkBtn({
		text="X", size=UDim2.new(0, 40, 0, 40), pos=UDim2.new(1, -5, 0, 5), anchor=Vector2.new(1, 0), 
		bgT=1, ts=24, color=C.WHITE, 
		fn=function() UIManager.closeFacility() end, 
		parent=main
	})

	-- [Tabs Bar]
	local tabBar = Utils.mkFrame({
		name = "TabBar", size = UDim2.new(1, -40, 0, 36), pos = UDim2.new(0, 20, 0, 50),
		bgT = 1, parent = main
	})
	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal; tabList.Padding = UDim.new(0, 8); tabList.Parent = tabBar

	for _, tabInfo in ipairs(TABS) do
		local tBtn = Utils.mkBtn({
			text = UILocalizer.Localize(tabInfo.name), size = UDim2.new(0, 150, 1, 0),
			bg = C.BG_SLOT, ts = 15, font = F.TITLE, r = 4,
			parent = tabBar
		})

		FacilityUI.Refs.Tabs[tabInfo.id] = { Frame = tBtn }

		tBtn.MouseButton1Click:Connect(function()
			FacilityUI.SetTab(tabInfo.id)
		end)
	end
	
	

	local function updateTabVisuals()
		for id, ref in pairs(FacilityUI.Refs.Tabs) do
			if id == currentTab then
				ref.Frame.BackgroundColor3 = C.GOLD
				ref.Frame.TextColor3 = C.WHITE -- 검정 글씨 제거, 흰 글씨로 통일
				ref.Frame.BackgroundTransparency = 0.1
			else
				ref.Frame.BackgroundColor3 = C.BG_SLOT
				ref.Frame.TextColor3 = Color3.fromRGB(200, 200, 200) -- 비활성 탭도 밝게 유지
				ref.Frame.BackgroundTransparency = 0.4
			end
		end
	end

	function FacilityUI.SetTab(tabId)
		currentTab = tabId
		updateTabVisuals()
		FacilityUI.Refresh(currentRawRecipeList, nil, UIManagerRef, true) -- 필터링된 리프레시
	end

	-- [Content Layout] - Left (Recipes) / Right (Detail)
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -110), pos=UDim2.new(0, 10, 0, 100), bgT=1, parent=main})
	
	-- 3. Left Side: Recipe List
	local leftPanel = Utils.mkFrame({
		name="Left", size=UDim2.new(0.5, -5, 1, 0), bgT=1, r=4, parent=content
	})
	
	local subTitle = Utils.mkLabel({
		text=UILocalizer.Localize("품목"), size=UDim2.new(1, -20, 0, 30), pos=UDim2.new(0, 10, 0, 5),
		color=C.GRAY, ts=14, ax=Enum.TextXAlignment.Left, parent=leftPanel
	})
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -10, 1, -40); scroll.Position = UDim2.new(0, 5, 0, 35)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = leftPanel
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.18, 0, 0.18, 0)
	grid.CellPadding = UDim2.new(0.015, 0, 0.015, 0)
	grid.Parent = scroll
	
	local gridRatio = Instance.new("UIAspectRatioConstraint", grid)
	gridRatio.AspectRatio = 1

	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop = UDim.new(0, 4); rPad.PaddingLeft = UDim.new(0, 4)
	rPad.PaddingRight = UDim.new(0, 4); rPad.PaddingBottom = UDim.new(0, 4)
	rPad.Parent = scroll

	FacilityUI.Refs.RecipeGrid = scroll
	
	-- 3.5 Left Side Bottom: Queue/Output List
	local queueTitle = Utils.mkLabel({
		text=UILocalizer.Localize("진행 및 완료"), size=UDim2.new(1, -20, 0, 30), pos=UDim2.new(0, 10, 0.65, 5),
		color=C.GRAY, ts=14, ax=Enum.TextXAlignment.Left, parent=leftPanel
	})
	
	-- Adjust recipe scroll height
	scroll.Size = UDim2.new(1, -10, 0.65, -40)
	
	local qScroll = Instance.new("ScrollingFrame")
	qScroll.Size = UDim2.new(1, -10, 0.35, -45); qScroll.Position = UDim2.new(0, 5, 0.65, 35)
	qScroll.BackgroundTransparency=1; qScroll.BorderSizePixel=0; qScroll.ScrollBarThickness=4
	qScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	qScroll.Parent = leftPanel
	
	local qList = Instance.new("UIListLayout")
	qList.Padding = UDim.new(0, 5); qList.Parent = qScroll
	FacilityUI.Refs.QueueGrid = qScroll

	-- 4. Right Side: Detail Panel
	local rightPanel = Utils.mkFrame({
		name="Right", size=UDim2.new(0.5, -5, 1, 0), pos=UDim2.new(0.5, 5, 0, 0), 
		bgT=1, r=4, parent=content
	})
	FacilityUI.Refs.DetailFrame = rightPanel

	-- Result Icon (responsive: top area, centered)
	local iconSize = 0.28
	local iconFrame = Utils.mkFrame({
		name="IconFrame", size=UDim2.new(iconSize, 0, iconSize, 0), pos=UDim2.new(0.5, 0, 0.04, 0), anchor=Vector2.new(0.5, 0),
		bg=C.GOLD, r="full", parent=rightPanel
	})
	local iconRatio = Instance.new("UIAspectRatioConstraint", iconFrame)
	iconRatio.AspectRatio = 1
	
	FacilityUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	FacilityUI.Refs.Detail.Icon.Size = UDim2.new(0.75, 0, 0.75, 0); FacilityUI.Refs.Detail.Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	FacilityUI.Refs.Detail.Icon.AnchorPoint = Vector2.new(0.5, 0.5); FacilityUI.Refs.Detail.Icon.BackgroundTransparency = 1; FacilityUI.Refs.Detail.Icon.Parent = iconFrame

	FacilityUI.Refs.Detail.Name = Utils.mkLabel({
		text=UILocalizer.Localize("아이템 이름"), size=UDim2.new(0.9, 0, 0.1, 0), pos=UDim2.new(0.5, 0, 0.35, 0),
		anchor=Vector2.new(0.5, 0), color=C.GOLD, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Center, parent=rightPanel
	})

	-- Bag Count (inline below name: "보유: N")
	FacilityUI.Refs.Detail.BagCount = Utils.mkLabel({
		text="", pos=UDim2.new(0.5, 0, 0.44, 0), anchor=Vector2.new(0.5, 0), size=UDim2.new(0.9, 0, 0.06, 0),
		color=C.GRAY, ts=13, font=F.BODY, ax=Enum.TextXAlignment.Center, parent=rightPanel
	})

	FacilityUI.Refs.Detail.Time = Utils.mkLabel({
		text=UILocalizer.Localize("맡김 제작 : 0초"), size=UDim2.new(0.9, 0, 0.06, 0), pos=UDim2.new(0.5, 0, 0.50, 0),
		anchor=Vector2.new(0.5, 0), color=C.GRAY, ts=14, ax=Enum.TextXAlignment.Center, parent=rightPanel
	})

	-- Qty controls (anchored to bottom, responsive)
	local qtyWrap = Utils.mkFrame({
		name="QtyWrap", size=UDim2.new(0.6, 0, 0.1, 0), pos=UDim2.new(0.5, 0, 0.82, 0), anchor=Vector2.new(0.5, 1),
		bgT=1, parent=rightPanel
	})
	FacilityUI.Refs.Detail.QtyWrap = qtyWrap

	local qtyMinus = Utils.mkBtn({
		text="-", size=UDim2.new(0.2, 0, 1, 0), pos=UDim2.new(0, 0, 0, 0),
		bg=C.BTN, ts=20, font=F.TITLE, parent=qtyWrap
	})
	FacilityUI.Refs.Detail.QtyMinus = qtyMinus

	local qtyLabel = Utils.mkLabel({
		text=UILocalizer.Localize("수량 x1"), size=UDim2.new(1, -92, 1, 0), pos=UDim2.new(0, 46, 0, 0),
		ts=16, color=C.WHITE, ax=Enum.TextXAlignment.Center, parent=qtyWrap
	})
	FacilityUI.Refs.Detail.QtyLabel = qtyLabel

	local qtyPlus = Utils.mkBtn({
		text="+", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -36, 0, 0),
		bg=C.BTN, ts=20, font=F.TITLE, parent=qtyWrap
	})
	FacilityUI.Refs.Detail.QtyPlus = qtyPlus

	local function syncQtyUI()
		currentCraftCount = math.clamp(currentCraftCount, 1, math.max(1, maxCraftCount))
		if FacilityUI.Refs.Detail.QtyLabel then
			FacilityUI.Refs.Detail.QtyLabel.Text = UILocalizer.Localize(string.format("수량 x%d", currentCraftCount))
		end
		if FacilityUI.Refs.Detail.Time and currentSelectedRecipe then
			local perCraftTime = currentSelectedRecipe.craftTime or 0
			FacilityUI.Refs.Detail.Time.Text = UILocalizer.Localize(string.format("맡김 제작 : %d초 (x%d = %d초)", perCraftTime, currentCraftCount, perCraftTime * currentCraftCount))
		end
		if FacilityUI.Refs.Detail.Btn then
			if currentCanCraft then
				FacilityUI.Refs.Detail.Btn.Text = UILocalizer.Localize(string.format("제작 시작 x%d", currentCraftCount))
			else
				FacilityUI.Refs.Detail.Btn.Text = UILocalizer.Localize("재료 부족")
			end
		end
		if FacilityUI.Refs.Detail.QtyMinus then
			FacilityUI.Refs.Detail.QtyMinus.Active = currentCraftCount > 1
			FacilityUI.Refs.Detail.QtyMinus.AutoButtonColor = currentCraftCount > 1
			FacilityUI.Refs.Detail.QtyMinus.TextTransparency = (currentCraftCount > 1) and 0 or 0.5
		end
		if FacilityUI.Refs.Detail.QtyPlus then
			FacilityUI.Refs.Detail.QtyPlus.Active = currentCraftCount < maxCraftCount
			FacilityUI.Refs.Detail.QtyPlus.AutoButtonColor = currentCraftCount < maxCraftCount
			FacilityUI.Refs.Detail.QtyPlus.TextTransparency = (currentCraftCount < maxCraftCount) and 0 or 0.5
		end
	end

	qtyMinus.MouseButton1Click:Connect(function()
		currentCraftCount = math.max(1, currentCraftCount - 1)
		syncQtyUI()
	end)

	qtyPlus.MouseButton1Click:Connect(function()
		currentCraftCount = math.min(maxCraftCount, currentCraftCount + 1)
		syncQtyUI()
	end)

	-- Materials (flexible-height scroll area between top content and bottom controls)
	local matScroll = Instance.new("ScrollingFrame")
	matScroll.Name = "Mats"
	matScroll.Size = UDim2.new(1, -40, 1, -320)
	matScroll.Position = UDim2.new(0, 20, 0, 192)
	matScroll.BackgroundTransparency = 1; matScroll.BorderSizePixel = 0; matScroll.ScrollBarThickness = 3
	matScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	matScroll.Parent = rightPanel
	FacilityUI.Refs.Detail.Mats = matScroll

	-- Start Button (anchored to bottom)
	local startBtn = Utils.mkBtn({
		text=UILocalizer.Localize("제작 시작"), size=UDim2.new(1, -40, 0, 50), pos=UDim2.new(0.5, 0, 1, -20), anchor=Vector2.new(0.5, 1),
		bg=C.GOLD, color=C.BG_DARK, ts=20, font=F.TITLE, r=4,
		parent=rightPanel
	})
	FacilityUI.Refs.Detail.Btn = startBtn
	
	startBtn.MouseButton1Click:Connect(function()
		if currentSelectedRecipe and UIManagerRef then
			UIManagerRef._onStartFacilityCraft(currentSelectedRecipe, currentCraftCount)
		end
	end)

	syncQtyUI()
	
	-- 초기 시각화 적용 (첫 클릭 전에도 검은색이 나오지 않도록)
	if updateTabVisuals then
		updateTabVisuals()
	end
end

function FacilityUI.Refresh(recipeList, getIcon, UIManager, isTabSwitch)
	local grid = FacilityUI.Refs.RecipeGrid
	if not grid then return end
	
	if not isTabSwitch then
		currentRawRecipeList = recipeList or {}
	end
	
	-- 탭 필터링
	local filtered = {}
	local currentTabInfo = nil
	for _, t in ipairs(TABS) do if t.id == currentTab then currentTabInfo = t; break end end
	
	if currentTabInfo then
		for _, r in ipairs(currentRawRecipeList) do
			local matched = false
			for _, cat in ipairs(currentTabInfo.categories) do
				if r.category == cat then matched = true; break end
			end
			if matched then table.insert(filtered, r) end
		end
	else
		filtered = currentRawRecipeList
	end

	-- Clear (UIGridLayout과 UIPadding 보존)
	for _, ch in ipairs(grid:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end
	
	-- 아이콘 헬퍼 (탭 전환 시에는 외부에서 안 들어오므로 UIManager 참조 활용)
	local iconGetter = getIcon or (UIManager and UIManager.getItemIcon)
	
	for _, recipe in ipairs(filtered) do
		-- 배경색 보더 기법: ScrollingFrame 클리핑 회피
		local borderFrame = Instance.new("Frame")
		borderFrame.Name = recipe.id
		borderFrame.BackgroundColor3 = C.BORDER
		borderFrame.BackgroundTransparency = 0
		borderFrame.BorderSizePixel = 0
		borderFrame.Parent = grid
		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 8)
		bCorner.Parent = borderFrame

		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.Size = UDim2.new(1, -4, 1, -4)
		inner.Position = UDim2.new(0.5, 0, 0.5, 0)
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.BackgroundColor3 = C.BG_SLOT
		inner.BackgroundTransparency = 0.1
		inner.BorderSizePixel = 0
		inner.Parent = borderFrame
		local iCorner = Instance.new("UICorner")
		iCorner.CornerRadius = UDim.new(0, 6)
		iCorner.Parent = inner

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.7, 0, 0.7, 0)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 2
		icon.Parent = inner

		local output = recipe.outputs[1]
		if output and iconGetter then
			icon.Image = iconGetter(output.itemId)
			icon.Visible = true
		end

		local click = Instance.new("TextButton")
		click.Name = "Click"
		click.Size = UDim2.new(1, 0, 1, 0)
		click.BackgroundTransparency = 1
		click.Text = ""
		click.ZIndex = 5
		click.Parent = borderFrame

		-- Hover
		click.MouseEnter:Connect(function()
			borderFrame.BackgroundColor3 = C.GOLD
		end)
		click.MouseLeave:Connect(function()
			borderFrame.BackgroundColor3 = C.BORDER
		end)

		click.MouseButton1Click:Connect(function()
			UIManager._onFacilityRecipeClick(recipe)
		end)
	end
end

function FacilityUI.UpdateDetail(recipe, playerItemCounts, getItemData, getIcon, canCraft)
	local d = FacilityUI.Refs.Detail
	currentSelectedRecipe = recipe
	currentCanCraft = canCraft and true or false
	
	if not recipe then
		FacilityUI.Refs.DetailFrame.Visible = false
		currentCanCraft = false
		return
	end
	FacilityUI.Refs.DetailFrame.Visible = true

	local output = recipe.outputs[1]
	local outData = getItemData(output.itemId)

	d.Name.Text = UILocalizer.Localize(recipe.name or output.itemId)
	d.Icon.Image = getIcon(output.itemId)
	d.BagCount.Text = UILocalizer.Localize(string.format("보유: %d", playerItemCounts[output.itemId] or 0))

	maxCraftCount = 99
	for _, req in ipairs(recipe.inputs) do
		local have = playerItemCounts[req.itemId] or 0
		local possible = (req.count and req.count > 0) and math.floor(have / req.count) or 0
		maxCraftCount = math.min(maxCraftCount, possible)
	end
	maxCraftCount = math.max(1, maxCraftCount)
	currentCraftCount = math.clamp(currentCraftCount, 1, maxCraftCount)

	if d.QtyLabel then
		d.QtyLabel.Text = UILocalizer.Localize(string.format("수량 x%d", currentCraftCount))
	end
	if d.QtyWrap then d.QtyWrap.Visible = true end
	if d.QtyMinus then
		d.QtyMinus.Active = currentCraftCount > 1
		d.QtyMinus.AutoButtonColor = currentCraftCount > 1
		d.QtyMinus.TextTransparency = (currentCraftCount > 1) and 0 or 0.5
	end
	if d.QtyPlus then
		d.QtyPlus.Active = currentCraftCount < maxCraftCount
		d.QtyPlus.AutoButtonColor = currentCraftCount < maxCraftCount
		d.QtyPlus.TextTransparency = (currentCraftCount < maxCraftCount) and 0 or 0.5
	end

	local perCraftTime = recipe.craftTime or 0
	d.Time.Text = UILocalizer.Localize(string.format("맡김 제작 : %d초 (x%d = %d초)", perCraftTime, currentCraftCount, perCraftTime * currentCraftCount))

	-- Clear mats
	for _, ch in ipairs(d.Mats:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end
	
	-- Populate mats (Horizontal list)
	local mList = Instance.new("UIListLayout")
	mList.FillDirection = Enum.FillDirection.Vertical; mList.Padding = UDim.new(0, 5); mList.Parent = d.Mats
	
	for _, req in ipairs(recipe.inputs) do
		local have = playerItemCounts[req.itemId] or 0
		local ok = have >= req.count
		local mData = getItemData(req.itemId)
		
		local row = Utils.mkFrame({size=UDim2.new(1,0,0,40), bgT=1, parent=d.Mats})
		local mIcon = Instance.new("ImageLabel")
		mIcon.Size = UDim2.new(0, 36, 0, 36); mIcon.Position = UDim2.new(0,0,0.5,0); mIcon.AnchorPoint=Vector2.new(0,0.5)
		mIcon.Image = getIcon(req.itemId); mIcon.BackgroundTransparency=1; mIcon.Parent=row
		
		local mName = UILocalizer.LocalizeDataText("ItemData", tostring(req.itemId), "name", (mData and mData.name) or req.itemId)
		local mLabel = Utils.mkLabel({
			text = mName,
			pos = UDim2.new(0, 45, 0.3, 0), anchor=Vector2.new(0,0.5), size=UDim2.new(0.5,0,0.4,0),
			ts=16, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=row
		})
		
		local countStr = string.format("%d / %d", have, req.count)
		local countColor = ok and C.WHITE or C.RED
		Utils.mkLabel({
			text = countStr, pos = UDim2.new(0, 45, 0.7, 0), anchor=Vector2.new(0,0.5), size=UDim2.new(0.5,0,0.4,0),
			ts=18, font=F.TITLE, color=countColor, ax=Enum.TextXAlignment.Left, parent=row
		})
	end

	-- Start Button State
	if canCraft then
		d.Btn.Text = UILocalizer.Localize(string.format("제작 시작 x%d", currentCraftCount))
		d.Btn.BackgroundColor3 = C.GOLD
		d.Btn.AutoButtonColor = true
	else
		d.Btn.Text = UILocalizer.Localize("재료 부족")
		d.Btn.BackgroundColor3 = C.BG_SLOT
		d.Btn.AutoButtonColor = false
	end
end

function FacilityUI.RefreshQueue(fullQueue, structureId, getIcon, UIManager)
	local grid = FacilityUI.Refs.QueueGrid
	if not grid then return end
	
	-- Clear
	for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end
	
	local count = 0
	for _, entry in ipairs(fullQueue) do
		-- 해당 시설의 제작 건만 표시
		if entry.structureId == structureId then
			count = count + 1
			local item = Utils.mkFrame({size=UDim2.new(1, -10, 0, 50), bg=C.BG_SLOT, bgT=0.5, r=4, parent=grid})
			
			local RecipeData = require(game.ReplicatedStorage.Data.RecipeData)
			local recipe = nil
			for _, r in ipairs(RecipeData) do
				if r.id == entry.recipeId then recipe = r; break end
			end
			
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 5, 0.5, 0); icon.AnchorPoint = Vector2.new(0, 0.5)
			local outputItemId = recipe and recipe.outputs and recipe.outputs[1] and recipe.outputs[1].itemId
			icon.Image = outputItemId and getIcon(outputItemId) or getIcon(entry.recipeId); icon.BackgroundTransparency = 1; icon.Parent = item
			
			local batchCount = math.max(1, tonumber(entry.batchCount) or 1)
			local completedCount = math.max(0, math.min(batchCount, tonumber(entry.completedCount) or 0))
			local collectedCount = math.max(0, math.min(batchCount, tonumber(entry.collectedCount) or 0))
			local readyCount = math.max(0, tonumber(entry.readyCount) or (completedCount - collectedCount))
			local inProgressCount = math.max(0, tonumber(entry.inProgressCount) or (batchCount - completedCount))
			local remainingToNext = math.max(0, tonumber(entry.remainingToNext) or tonumber(entry.remaining) or 0)
			local statusText = string.format("완료 %d/%d", completedCount, batchCount)
			if inProgressCount > 0 then
				statusText = string.format("진행 %d | 완료 %d/%d (%ds)", inProgressCount, completedCount, batchCount, remainingToNext)
			end
			
			local lbl = Utils.mkLabel({
				text = string.format("x%d  %s", batchCount, statusText), pos = UDim2.new(0, 55, 0.5, 0), anchor=Vector2.new(0, 0.5), size=UDim2.new(0.62, 0, 0.8, 0),
				ts = 14, color = (readyCount > 0) and C.GOLD or C.WHITE, ax=Enum.TextXAlignment.Left, parent=item
			})
			
			if readyCount > 0 then
				local collectBtn = Utils.mkBtn({
					text = UILocalizer.Localize(string.format("수령 x%d", readyCount)), size = UDim2.new(0, 92, 0, 34), pos = UDim2.new(1, -5, 0.5, 0), anchor = Vector2.new(1, 0.5),
					bg = C.GOLD, ts = 14, color = C.BG_DARK, r = 4,
					fn = function() UIManager._onCollectFacilityCraft(entry.craftId, readyCount) end,
					parent = item
				})
			else
				-- 진행 바 가시성 개선: 두께/대비/퍼센트 표시 강화
				local bar = Utils.mkFrame({
					size = UDim2.new(0, 120, 0, 10), 
					pos = UDim2.new(1, -10, 0.6, 0), 
					anchor = Vector2.new(1, 0.5), 
					bg = C.BG_DARK, 
					r = 4,
					stroke = 1,
					strokeC = C.BORDER_DIM,
					parent = item
				})
				
				local total = tonumber(entry.totalDuration) or (recipe and recipe.craftTime) or 0
				if total > 0 then
					local ratio = tonumber(entry.progressRatio)
					if ratio == nil then
						local remainingTotal = math.max(0, tonumber(entry.remaining) or 0)
						ratio = math.clamp(1 - (remainingTotal / total), 0, 1)
					else
						ratio = math.clamp(ratio, 0, 1)
					end
					local fill = Utils.mkFrame({
						size = UDim2.new(ratio, 0, 1, 0),
						bg = C.GOLD,
						r = 4,
						parent = bar
					})

					Utils.mkLabel({
						text = string.format("%d%%", math.floor(ratio * 100)),
						size = UDim2.new(0, 40, 0, 16),
						pos = UDim2.new(1, -10, 0.2, 0),
						anchor = Vector2.new(1, 0.5),
						ts = 12,
						font = F.TITLE,
						color = C.GOLD,
						ax = Enum.TextXAlignment.Right,
						parent = item
					})
				end
			end
		end
	end
end

function FacilityUI.UpdateHealth(current, max)
	local h = FacilityUI.Refs.HealthBar
	if not h.Frame then return end
	
	local percent = math.clamp(current / (max or 100), 0, 1)
	h.Fill.Size = UDim2.new(percent, 0, 1, 0)
	h.Label.Text = UILocalizer.Localize(string.format("내구도 %d%%", math.floor(percent * 100)))
	
	-- 색상 변경
	if percent < 0.25 then
		h.Fill.BackgroundColor3 = C.RED
	elseif percent < 0.5 then
		h.Fill.BackgroundColor3 = C.ORANGE
	else
		h.Fill.BackgroundColor3 = C.GREEN
	end
end

function FacilityUI.SetVisible(vis)
	if FacilityUI.Refs.Frame then
		FacilityUI.Refs.Frame.Visible = vis
	end
end

return FacilityUI
