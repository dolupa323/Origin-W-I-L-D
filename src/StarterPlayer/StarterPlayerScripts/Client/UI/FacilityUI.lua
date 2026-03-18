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
		Btn = nil,
		BagCount = nil,
	},
	QueueGrid = nil,
	HealthBar = {
		Frame = nil,
		Fill = nil,
		Label = nil,
	},
}

function FacilityUI.Init(parent, UIManager, isMobile)
	UIManagerRef = UIManager
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
	
	-- 2. Main Window (Translucent)
	local main = Utils.mkWindow({
		name = "FacilityWindow",
		size = UDim2.new(isSmall and 0.95 or 0.75, 0, isSmall and 0.9 or 0.85, 0),
		maxSize = Vector2.new(1000, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER,
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
		bg=Color3.fromRGB(40, 40, 40), r=3, parent=header
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

	-- [Content Layout] - Left (Recipes) / Right (Detail)
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -70), pos=UDim2.new(0, 10, 0, 60), bgT=1, parent=main})
	
	-- 3. Left Side: Recipe List
	local leftPanel = Utils.mkFrame({
		name="Left", size=UDim2.new(0.5, -5, 1, 0), bg=C.BG_SLOT, bgT=0.35, r=4, stroke=1, strokeC=C.BORDER_DIM, parent=content
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
	grid.CellSize = UDim2.new(0, 80, 0, 80); grid.CellPadding = UDim2.new(0, 10, 0, 10); grid.Parent = scroll
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
		bg=C.BG_PANEL_L, bgT=0.15, r=4, stroke=1, strokeC=C.BORDER, parent=content
	})
	FacilityUI.Refs.DetailFrame = rightPanel

	-- Result Icon (Hexagon or Rounded Square)
	local iconFrame = Utils.mkFrame({
		name="IconFrame", size=UDim2.new(0, 100, 0, 100), pos=UDim2.new(0.5, 0, 0, 50), anchor=Vector2.new(0.5, 0.5),
		bg=C.GOLD, r=50, parent=rightPanel
	})
	FacilityUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	FacilityUI.Refs.Detail.Icon.Size = UDim2.new(0, 80, 0, 80); FacilityUI.Refs.Detail.Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	FacilityUI.Refs.Detail.Icon.AnchorPoint = Vector2.new(0.5, 0.5); FacilityUI.Refs.Detail.Icon.BackgroundTransparency = 1; FacilityUI.Refs.Detail.Icon.Parent = iconFrame

	-- Bag Count (How many you have)
	local bagFrame = Utils.mkFrame({
		name="Bag", size=UDim2.new(0, 45, 0, 25), pos=UDim2.new(0, 0, 0, 0), bgT=1, parent=rightPanel
	})
	local bagIcon = Instance.new("ImageLabel")
	bagIcon.Size = UDim2.new(0, 20, 0, 20); bagIcon.Position = UDim2.new(0, 5, 0, 2)
	bagIcon.Image = "rbxassetid://13515082103"; bagIcon.BackgroundTransparency = 1; bagIcon.Parent = bagFrame
	FacilityUI.Refs.Detail.BagCount = Utils.mkLabel({
		text="0", pos=UDim2.new(0, 28, 0.5, 0), anchor=Vector2.new(0, 0.5), size=UDim2.new(0, 20, 0, 20),
		color=C.WHITE, ts=14, font=F.BODY, parent=bagFrame
	})

	FacilityUI.Refs.Detail.Name = Utils.mkLabel({
		text=UILocalizer.Localize("아이템 이름"), size=UDim2.new(1, -20, 0, 30), pos=UDim2.new(0, 10, 0, 100),
		color=C.GOLD, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Center, parent=rightPanel
	})

	FacilityUI.Refs.Detail.Time = Utils.mkLabel({
		text=UILocalizer.Localize("맡김 제작 : 0초"), size=UDim2.new(1, -20, 0, 20), pos=UDim2.new(0, 10, 0, 130),
		color=C.GRAY, ts=14, ax=Enum.TextXAlignment.Center, parent=rightPanel
	})

	-- Materials
	local matArea = Utils.mkFrame({
		name="Mats", size=UDim2.new(1, -40, 0, 150), pos=UDim2.new(0, 20, 0, 160), bgT=1, parent=rightPanel
	})
	FacilityUI.Refs.Detail.Mats = matArea -- We will populate this dynamically

	-- Start Button
	local startBtn = Utils.mkBtn({
		text=UILocalizer.Localize("제작 시작"), size=UDim2.new(1, -40, 0, 50), pos=UDim2.new(0.5, 0, 1, -15), anchor=Vector2.new(0.5, 1),
		bg=C.GOLD, color=Color3.fromRGB(20, 20, 20), ts=20, font=F.TITLE, r=4,
		parent=rightPanel
	})
	FacilityUI.Refs.Detail.Btn = startBtn
	
	startBtn.MouseButton1Click:Connect(function()
		if currentSelectedRecipe and UIManagerRef then
			UIManagerRef._onStartFacilityCraft(currentSelectedRecipe)
		end
	end)
end

function FacilityUI.Refresh(recipeList, getIcon, UIManager)
	local grid = FacilityUI.Refs.RecipeGrid
	if not grid then return end
	
	-- Clear
	for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end
	
	for _, recipe in ipairs(recipeList) do
		local slot = Utils.mkSlot({name=recipe.id, size=UDim2.new(0,80,0,80), parent=grid})
		local output = recipe.outputs[1]
		if output then
			slot.icon.Image = getIcon(output.itemId)
			slot.icon.Visible = true
		end
		
		slot.click.MouseButton1Click:Connect(function()
			UIManager._onFacilityRecipeClick(recipe)
		end)
	end
end

function FacilityUI.UpdateDetail(recipe, playerItemCounts, getItemData, getIcon, canCraft)
	local d = FacilityUI.Refs.Detail
	currentSelectedRecipe = recipe
	
	if not recipe then
		FacilityUI.Refs.DetailFrame.Visible = false
		return
	end
	FacilityUI.Refs.DetailFrame.Visible = true

	local output = recipe.outputs[1]
	local outData = getItemData(output.itemId)

	d.Name.Text = UILocalizer.Localize(recipe.name or output.itemId)
	d.Icon.Image = getIcon(output.itemId)
	d.Time.Text = UILocalizer.Localize(string.format("맡김 제작 : %d초", recipe.craftTime or 0))
	d.BagCount.Text = tostring(playerItemCounts[output.itemId] or 0)

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
		d.Btn.Text = UILocalizer.Localize("제작 시작")
		d.Btn.BackgroundColor3 = C.GOLD
		d.Btn.AutoButtonColor = true
	else
		d.Btn.Text = UILocalizer.Localize("재료 부족")
		d.Btn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
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
			local item = Utils.mkFrame({size=UDim2.new(1, -10, 0, 50), bg=Color3.fromRGB(45, 45, 50), bgT=0.5, r=4, parent=grid})
			
			local RecipeData = require(game.ReplicatedStorage.Data.RecipeData)
			local recipe = nil
			for _, r in ipairs(RecipeData) do
				if r.id == entry.recipeId then recipe = r; break end
			end
			
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 5, 0.5, 0); icon.AnchorPoint = Vector2.new(0, 0.5)
			local outputItemId = recipe and recipe.outputs and recipe.outputs[1] and recipe.outputs[1].itemId
			icon.Image = outputItemId and getIcon(outputItemId) or getIcon(entry.recipeId); icon.BackgroundTransparency = 1; icon.Parent = item
			
			local isDone = (entry.remaining <= 0)
			local statusText = isDone and UILocalizer.Localize("완료") or UILocalizer.Localize(string.format("제작 중 (%ds)", entry.remaining))
			
			local lbl = Utils.mkLabel({
				text = statusText, pos = UDim2.new(0, 55, 0.5, 0), anchor=Vector2.new(0, 0.5), size=UDim2.new(0.5, 0, 0.8, 0),
				ts = 14, color = isDone and C.GOLD or C.WHITE, ax=Enum.TextXAlignment.Left, parent=item
			})
			
			if isDone then
				local collectBtn = Utils.mkBtn({
					text = UILocalizer.Localize("수령"), size = UDim2.new(0, 60, 0, 34), pos = UDim2.new(1, -5, 0.5, 0), anchor = Vector2.new(1, 0.5),
					bg = C.GOLD, ts = 14, color = Color3.fromRGB(20, 20, 20), r = 4,
					fn = function() UIManager._onCollectFacilityCraft(entry.craftId) end,
					parent = item
				})
			else
				-- 진행 바 가시성 개선: 두께/대비/퍼센트 표시 강화
				local bar = Utils.mkFrame({
					size = UDim2.new(0, 120, 0, 10), 
					pos = UDim2.new(1, -10, 0.6, 0), 
					anchor = Vector2.new(1, 0.5), 
					bg = Color3.fromRGB(20, 20, 20), 
					r = 4,
					stroke = 1,
					strokeC = Color3.fromRGB(120, 120, 120),
					parent = item
				})
				
				if recipe and recipe.craftTime and recipe.craftTime > 0 then
					local total = recipe.craftTime
					local ratio = math.clamp(1 - (entry.remaining / total), 0, 1)
					local fill = Utils.mkFrame({
						size = UDim2.new(ratio, 0, 1, 0),
						bg = Color3.fromRGB(210, 190, 90),
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
