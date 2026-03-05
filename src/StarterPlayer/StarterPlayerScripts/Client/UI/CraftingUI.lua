local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local CraftingUI = {}

CraftingUI.Refs = {
	Frame = nil,
	Title = nil,
	GridScroll = nil,
	Slots = {}, -- 슬롯 참조 저장용
	Detail = {
		Frame = nil,
		Name = nil,
		Icon = nil,
		Desc = nil,
		MatsText = nil,
		BtnCraft = nil,
	}
}

local selectedRecipeId = nil

----------------------------------------------------------------
-- 선택 하이라이트 업데이트
----------------------------------------------------------------
local function updateSelectionHighlight()
	for id, slot in pairs(CraftingUI.Refs.Slots) do
		local st = slot.frame:FindFirstChildOfClass("UIStroke")
		if id == selectedRecipeId then
			if st then st.Color = C.GOLD; st.Thickness = 2.5 end
		else
			if st then
				st.Color = Color3.fromRGB(60, 60, 60)
				st.Thickness = 1
			end
		end
	end
end

function CraftingUI.Init(parent, UIManager)
	CraftingUI.Refs.Frame = Utils.mkFrame({
		name = "CraftingMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 0.85,
		vis = false,
		parent = parent
	})
	
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(0.7, 0, 0.85, 0),
		maxSize = Vector2.new(950, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = Color3.fromRGB(15, 15, 18),
		bgT = 0.5,
		r = 0, stroke = 1, strokeC = Color3.fromRGB(60, 60, 60),
		parent = CraftingUI.Refs.Frame
	})

	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bg=Color3.fromRGB(10,10,12), parent=main})
	CraftingUI.Refs.Title = Utils.mkLabel({text="제작 도구", pos=UDim2.new(0, 15, 0, 0), ts=20, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 40, 0, 40), pos=UDim2.new(1, -6, 0.5, 0), anchor=Vector2.new(1,0.5), bg=Color3.fromRGB(40,40,40), bgT=0.5, ts=20, color=C.WHITE, r=5, fn=function() UIManager.closeCrafting() end, parent=header})

	local canvasWrapper = Utils.mkFrame({
		name="CanvasWrap", size=UDim2.new(1, 0, 1, -45),
		pos=UDim2.new(0,0,0,45), bgT=1, parent=main
	})
	
	-- Left Side: Grid
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(1, -320, 1, 0), bgT=1, parent=canvasWrapper})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 75, 0, 75)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 15); pad.PaddingLeft = UDim.new(0, 15)
	pad.Parent = scroll
	
	CraftingUI.Refs.GridScroll = scroll
	
	-- Right Side: Detail Panel (320px Fixed)
	local detailSize = 320
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(0, detailSize, 1, -16),
		pos=UDim2.new(1, -detailSize - 8, 0, 8),
		bg=Color3.fromRGB(12,12,15), bgT=0.4, r=6, stroke=1, strokeC=Color3.fromRGB(60,60,60),
		parent=canvasWrapper
	})
	CraftingUI.Refs.Detail.Frame = detail
	detail.Visible = false
	
	local dtHead = Utils.mkLabel({
		text="제작 상세 정보", size=UDim2.new(1,0,0,40),
		bg=Color3.fromRGB(30,30,30), bgT=0.2, color=C.GOLD, ts=16, font=F.TITLE,
		parent=detail
	})
	
	CraftingUI.Refs.Detail.Name = Utils.mkLabel({
		text="이름", size=UDim2.new(1,-20,0,40), pos=UDim2.new(0,15,0,50),
		color=C.WHITE, ts=20, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	CraftingUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	CraftingUI.Refs.Detail.Icon.Size = UDim2.new(0, 80, 0, 80); CraftingUI.Refs.Detail.Icon.Position = UDim2.new(0,15,0,95)
	CraftingUI.Refs.Detail.Icon.BackgroundTransparency = 1; CraftingUI.Refs.Detail.Icon.Parent = detail
	
	CraftingUI.Refs.Detail.Desc = Utils.mkLabel({
		text="설명", size=UDim2.new(1,-110,0,100), pos=UDim2.new(0,105,0,95),
		color=Color3.fromRGB(200,200,200), ts=16, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detail
	})

	-- 재료 영역
	local matLabel = Utils.mkLabel({
		text="[ 필요 재료 ]", size=UDim2.new(1,-30,0,25), pos=UDim2.new(0,15,0,200),
		ts=15, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	CraftingUI.Refs.Detail.MatsText = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,0,150), pos=UDim2.new(0,15,0,230),
		ts=16, color=C.WHITE, rich=true, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=detail
	})

	-- [제작 진행표시] 로딩 스피너 및 프로그레스바 추가
	local progWrap = Utils.mkFrame({name="ProgWrap", size=UDim2.new(0, 80, 0, 80), pos=UDim2.new(0,15,0,95), bgT=1, vis=false, parent=detail})
	CraftingUI.Refs.Detail.ProgWrap = progWrap
	
	local spinner = Instance.new("ImageLabel")
	spinner.Name = "Spinner"; spinner.Size = UDim2.new(1.2, 0, 1.2, 0); spinner.Position = UDim2.new(0.5, 0, 0.5, 0); spinner.AnchorPoint = Vector2.new(0.5,0.5)
	spinner.BackgroundTransparency = 1; spinner.Image = "rbxassetid://6034445544"; spinner.ImageColor3 = C.GOLD; spinner.ZIndex = 15; spinner.Parent = progWrap
	CraftingUI.Refs.Detail.Spinner = spinner

	local barBack = Utils.mkFrame({name="BarBack", size=UDim2.new(1, -24, 0, 6), pos=UDim2.new(0.5, 0, 0, 185), anchor=Vector2.new(0.5, 0), bg=Color3.fromRGB(40,40,40), r=3, vis=false, parent=detail})
	local barFill = Utils.mkFrame({name="Fill", size=UDim2.new(0, 0, 1, 0), bg=C.GOLD, r=3, parent=barBack})
	CraftingUI.Refs.Detail.ProgBar = barBack
	CraftingUI.Refs.Detail.ProgFill = barFill
	
	CraftingUI.Refs.Detail.BtnCraft = Utils.mkBtn({
		text="제작 시작", size=UDim2.new(1, -24, 0, 50), pos=UDim2.new(0, 12, 1, -62),
		bg=C.GOLD, color=Color3.fromRGB(20,20,20), ts=18, font=F.TITLE, r=5,
		fn=function() UIManager._doCraft() end, parent=detail
	})
end

function CraftingUI.SetVisible(visible)
	if CraftingUI.Refs.Frame then
		CraftingUI.Refs.Frame.Visible = visible
	end
end

function CraftingUI.UpdateTitle(title)
	if CraftingUI.Refs.Title then CraftingUI.Refs.Title.Text = title end
end

function CraftingUI.Refresh(items, playerItemCounts, getItemIcon, mode, UIManager)
	local scroll = CraftingUI.Refs.GridScroll
	if not scroll then return end

	for _, ch in pairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end
	
	CraftingUI.Refs.Slots = {}

	for _, item in ipairs(items) do
		local isLocked = item.isLocked
		local canMake, _ = UIManager.checkMaterials(item, playerItemCounts)
		
		local slot = Utils.mkSlot({
			name = item.id, r = 8, bg = Color3.fromRGB(40, 40, 45), bgT = 0.2, 
			strokeC = Color3.fromRGB(60, 60, 60),
			parent = scroll
		})
		
		-- 듀랑고 스타일 둥근 사각 테두리
		local stk = slot.frame:FindFirstChildOfClass("UIStroke")
		if stk then stk.Thickness = 1 end

		slot.icon.Image = getItemIcon(item.id)
		slot.icon.ImageColor3 = Color3.new(1, 1, 1)
		
		if isLocked then
			slot.frame.BackgroundColor3 = Color3.fromRGB(40, 25, 25)
			slot.icon.ImageColor3 = Color3.new(0.4, 0.4, 0.4)
			local lockIcon = Instance.new("ImageLabel")
			lockIcon.Size = UDim2.new(0,24,0,24); lockIcon.Position = UDim2.new(1,0,0,0); lockIcon.AnchorPoint = Vector2.new(1,0)
			lockIcon.BackgroundTransparency = 1; lockIcon.Image = "rbxassetid://6031084651"; lockIcon.ZIndex = 50; lockIcon.Parent = slot.frame
		elseif not canMake then
			slot.frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		else
			-- 제작 가능시 살짝 밝은 연출
			slot.frame.BackgroundColor3 = Color3.fromRGB(45, 55, 45)
		end
		
		CraftingUI.Refs.Slots[item.id] = slot

		slot.click.MouseButton1Click:Connect(function()
			selectedRecipeId = item.id
			updateSelectionHighlight()
			UIManager._onCraftSlotClick(item, mode)
		end)
	end
	
	updateSelectionHighlight()
end

function CraftingUI.UpdateDetail(item, mode, isLocked, canMake, playerItemCounts, DataHelper, getItemIcon)
	local d = CraftingUI.Refs.Detail
	if not d.Frame then return end
	
	if not item then
		d.Frame.Visible = false
		return
	end

	d.Frame.Visible = true
	d.Name.Text = (item.name or item.id)
	d.Icon.Image = getItemIcon and getItemIcon(item.id) or item.id
	
	if DataHelper then
		-- 레시피인 경우 결과물 아이템 아이디를 가져옴
		local targetId = item.id
		if item.outputs and #item.outputs > 0 then
			targetId = item.outputs[1].itemId or item.outputs[1].id
		end
		
		local data = DataHelper.GetData("ItemData", targetId)
		if data and data.description then
			d.Desc.Text = data.description
		elseif data and data.name then
			d.Desc.Text = data.name .. " 을(를) 제작합니다."
		else
			d.Desc.Text = "선택한 대상을 제작합니다."
		end
	end

	if isLocked then
		d.MatsText.Text = "<font color=\"#E63232\">✗ 기술 트리에서 해금 필요</font>"
		d.BtnCraft.Visible = true
		d.BtnCraft.Text = "잠김"
		d.BtnCraft.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		d.BtnCraft.TextColor3 = Color3.fromRGB(120, 120, 120)
		d.BtnCraft.AutoButtonColor = false
		return
	end

	local matsText = ""
	local mats = item.inputs or item.requirements
	if mats then
		for _, inp in ipairs(mats) do
			local req = inp.count or inp.amount or 0
			local have = playerItemCounts[inp.itemId or inp.id] or 0
			local ok = have >= req
			
			local itemName = inp.itemId or inp.id
			if DataHelper then
				local itemData = DataHelper.GetData("ItemData", itemName)
				if itemData then itemName = itemData.name end
			end
			
			local colorStr = ok and "#8CDC64" or "#E63232"
			local prefix = ok and "✓ " or "✗ "
			matsText = matsText .. string.format("<font color=\"%s\">%s%s: %d / %d</font>\n", colorStr, prefix, itemName, have, req)
		end
	end
	
	d.MatsText.Text = matsText
	
	d.BtnCraft.Visible = true
	d.BtnCraft.Text = (mode == "CRAFTING") and "제작 시작" or "건축 시작"
	
	if canMake then
		d.BtnCraft.BackgroundColor3 = C.GOLD
		d.BtnCraft.TextColor3 = Color3.fromRGB(20,20,20)
		d.BtnCraft.AutoButtonColor = true
	else
		d.BtnCraft.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		d.BtnCraft.TextColor3 = Color3.fromRGB(120, 120, 120)
		d.BtnCraft.AutoButtonColor = false
	end
end

return CraftingUI
