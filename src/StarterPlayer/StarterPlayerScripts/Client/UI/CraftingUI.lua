-- CraftingUI.lua
-- 듀랑고 레퍼런스 스타일 제작/건축 UI

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
	Detail = {
		Frame = nil,
		Name = nil,
		Icon = nil,
		Desc = nil,
		MatsText = nil,
		BtnCraft = nil,
	}
}

function CraftingUI.Init(parent, UIManager)
	CraftingUI.Refs.Frame = Utils.mkFrame({
		name = "CraftingMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 0.7,
		vis = false,
		parent = parent
	})
	
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(0.9, 0, 0.85, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 0, stroke = 2, strokeC = C.BORDER_DIM,
		ratio = 1.6,
		parent = CraftingUI.Refs.Frame
	})

	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	CraftingUI.Refs.Title = Utils.mkLabel({text="제작 도구", pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, -15, 0, 7), anchor=Vector2.new(1,0), bgT=1, ts=26, color=C.WHITE, fn=function() UIManager.closeCrafting() end, parent=header})

	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	
	-- Left Side: Grid
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(0.65, -10, 1, 0), bgT=1, parent=content})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 2
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ClipsDescendants = true
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 80, 0, 80)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = scroll
	
	CraftingUI.Refs.GridScroll = scroll
	
	-- Right Side: Detail Panel
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(0.35, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1, 0),
		bg=C.BG_PANEL_L, stroke=1, parent=content
	})
	CraftingUI.Refs.Detail.Frame = detail
	
	local dHeader = Utils.mkFrame({size=UDim2.new(1,0,0,40), bg=C.GOLD_SEL, bgT=0.3, parent=detail})
	CraftingUI.Refs.Detail.Name = Utils.mkLabel({text="대상을 선택하세요", ts=18, font=F.TITLE, parent=dHeader})
	
	local dBody = Utils.mkFrame({size=UDim2.new(1,-20,1,-120), pos=UDim2.new(0,10,0,50), bgT=1, parent=detail})
	local dBList = Instance.new("UIListLayout"); dBList.Padding=UDim.new(0, 8); dBList.HorizontalAlignment=Enum.HorizontalAlignment.Center; dBList.Parent=dBody
	
	local iconFrame = Utils.mkFrame({size=UDim2.new(0, 80, 0, 80), bg=C.BG_SLOT, stroke=1, strokeC=C.BORDER_DIM, parent=dBody})
	CraftingUI.Refs.Detail.Icon = Instance.new("ImageLabel"); CraftingUI.Refs.Detail.Icon.Size=UDim2.new(1,-10,1,-10); CraftingUI.Refs.Detail.Icon.Position=UDim2.new(0.5,0,0.5,0); CraftingUI.Refs.Detail.Icon.AnchorPoint=Vector2.new(0.5,0.5); CraftingUI.Refs.Detail.Icon.BackgroundTransparency=1; CraftingUI.Refs.Detail.Icon.Parent=iconFrame
	
	local matLabel = Utils.mkLabel({text="[필요 재료]", size=UDim2.new(1,0,0,20), ts=14, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=dBody})
	CraftingUI.Refs.Detail.MatsText = Utils.mkLabel({text="", size=UDim2.new(1,0,0,80), ts=14, color=C.WHITE, rich=true, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=dBody})
	
	CraftingUI.Refs.Detail.Desc = Utils.mkLabel({text="", size=UDim2.new(1,0,0,0), ts=13, color=C.GRAY, vis=false, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=dBody})
	
	local dFoot = Utils.mkFrame({size=UDim2.new(1,-20,0,50), pos=UDim2.new(0.5,0,1,-15), anchor=Vector2.new(0.5,1), bgT=1, parent=detail})
	CraftingUI.Refs.Detail.BtnCraft = Utils.mkBtn({text="제작 시작", size=UDim2.new(1,0,1,0), bg=C.GOLD_SEL, font=F.TITLE, ts=20, color=C.BG_PANEL, fn=function() UIManager._doCraft() end, parent=dFoot})
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

	for _, item in ipairs(items) do
		local isLocked = item.isLocked
		local canMake, _ = UIManager.checkMaterials(item, playerItemCounts)
		
		local slot = Utils.mkSlot({
			name = item.id, r = 0, bgT = 0.3, 
			strokeC = isLocked and C.LOCK or (canMake and C.BORDER_DIM or C.LOCK),
			parent = scroll
		})

		slot.icon.Image = getItemIcon(item.id)
		
		if isLocked then
			slot.icon.ImageColor3 = Color3.new(0.3, 0.3, 0.3)
			local lockBG = Utils.mkFrame({name="Lock", size=UDim2.new(1,0,1,0), bg=Color3.new(0,0,0), bgT=0.5, z=20, parent=slot.frame})
			local lockIcon = Instance.new("ImageLabel")
			lockIcon.Size = UDim2.new(0,32,0,32); lockIcon.Position = UDim2.new(0.5,0,0.5,0); lockIcon.AnchorPoint = Vector2.new(0.5,0.5)
			lockIcon.BackgroundTransparency = 1; lockIcon.Image = "rbxassetid://6031084651"; lockIcon.Parent = lockBG
			
			slot.click.MouseButton1Click:Connect(function()
				if UIManager.notify then UIManager.notify("기술 탭에서 먼저 해금하세요.", C.RED) end
				UIManager._onCraftSlotClick(item, mode)
			end)
		else
			if not canMake then
				slot.icon.ImageColor3 = Color3.new(0.5, 0.5, 0.5)
			else
				slot.frame.BackgroundColor3 = C.SUCCESS
				slot.frame.BackgroundTransparency = 0.4
			end
			
			slot.click.MouseButton1Click:Connect(function()
				UIManager._onCraftSlotClick(item, mode)
			end)
		end
	end
end

function CraftingUI.UpdateDetail(item, mode, isLocked, canMake, playerItemCounts, DataHelper)
	local d = CraftingUI.Refs.Detail
	if not d.Frame then return end
	
	if not item then
		d.Name.Text = "제작 대상을 선택하세요"
		d.Desc.Text = ""
		d.MatsText.Text = ""
		d.Icon.Image = ""
		d.Icon.Visible = false
		d.BtnCraft.Visible = false
		return
	end

	d.Name.Text = (item.name or item.id)
	d.Icon.Image = item.id -- Needs getItemIcon pass, handled in Controller ideally, but we'll adapt.
	if DataHelper then
		local data = DataHelper.GetData("ItemData", item.id)
		if data then d.Icon.Image = data.icon or d.Icon.Image end
	end
	d.Icon.Visible = true

	if isLocked then
		d.MatsText.Text = "기술 트리에서 해금해야 합니다."
		d.Desc.Text = "잠김 상태"
		d.BtnCraft.Visible = false
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
			
			if ok then
				matsText = matsText .. string.format("<font color=\"#8CDC64\">%s: %d/%d</font>\n", itemName, have, req)
			else
				matsText = matsText .. string.format("<font color=\"#E63232\">%s: %d/%d</font>\n", itemName, have, req)
			end
		end
	end
	
	d.MatsText.RichText = true
	d.MatsText.Text = matsText
	d.Desc.Text = item.desc or "제작 속도: " .. ((mode == "CRAFTING") and "즉시 제작" or "설치 도구")
	
	d.BtnCraft.Text = (mode == "CRAFTING") and "제작 시작" or "건축 시작"
	d.BtnCraft.Visible = true
	d.BtnCraft.BackgroundColor3 = canMake and C.GOLD_SEL or C.BTN_DIS
	d.BtnCraft.AutoButtonColor = canMake
end

return CraftingUI
