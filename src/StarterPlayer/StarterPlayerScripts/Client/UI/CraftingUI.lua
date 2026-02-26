-- CraftingUI.lua
-- Durango Style 제작 및 건축 UI
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local CraftingUI = {}
CraftingUI.Refs = {
	Overlay = nil,
	Title = nil,
	Grid = nil,
	Detail = {
		Frame = nil,
		Name = nil,
		Time = nil,
		Mats = nil,
		BtnCraft = nil,
	}
}

function CraftingUI.SetVisible(visible)
	if CraftingUI.Refs.Overlay then
		CraftingUI.Refs.Overlay.Visible = visible
	end
end

function CraftingUI.UpdateTitle(title)
	if CraftingUI.Refs.Title then
		CraftingUI.Refs.Title.Text = title
	end
end

function CraftingUI.Refresh(items, playerItemCounts, getItemIcon, mode)
	local scroll = CraftingUI.Refs.Grid
	if not scroll then return end

	for _, ch in pairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end

	for _, item in ipairs(items) do
		local isLocked = item.isLocked
		local slot = Utils.mkSlot({
			name = item.id,
			r = 4,
			bgT = 0.3,
			strokeC = isLocked and C.LOCK or C.BORDER_DIM,
			parent = scroll
		})

		slot.icon.Image = getItemIcon(item.id)
		if isLocked then
			slot.icon.ImageColor3 = Color3.new(0.3, 0.3, 0.3)
			Utils.mkLabel({text = "🔒", size = UDim2.new(1, 0, 1, 0), ts = 20, parent = slot.frame})
		end

		slot.click.MouseButton1Click:Connect(function()
			local UIManager = require(script.Parent.Parent.UIManager)
			UIManager._onCraftSlotClick(item, mode)
		end)
	end
end

function CraftingUI.UpdateDetail(item, mode, isLocked, canMake, playerItemCounts)
	local d = CraftingUI.Refs.Detail
	if not d.Frame then return end
	
	if not item then
		d.Name.Text = "제작 대상을 선택하세요"
		d.Time.Text = ""
		d.Mats.Text = ""
		d.BtnCraft.Visible = false
		return
	end

	d.Name.Text = (isLocked and "🔒 " or "") .. (item.name or item.id)
	
	if isLocked then
		d.Mats.Text = "기술 트리에서 해금해야 합니다."
		d.Time.Text = "잠김"
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
			matsText = matsText .. string.format("%s %s %d/%d\n", ok and "✓" or "✗", inp.itemId or inp.id, have, req)
		end
	end
	d.Mats.Text = matsText
	d.Time.Text = (mode == "CRAFTING") and (item.craftTime and ("⏱️ " .. item.craftTime .. "초") or "즉시 제작") or "건축 도구"
	
	d.BtnCraft.Text = (mode == "CRAFTING") and "제작 시작" or "건축 시작"
	d.BtnCraft.Visible = true
	d.BtnCraft.BackgroundColor3 = canMake and C.GOLD_SEL or C.BTN_DIS
end

function CraftingUI.Init(parent, UIManager)
	-- Overlay
	CraftingUI.Refs.Overlay = Utils.mkFrame({
		name = "CraftingOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.6,
		vis = false,
		parent = parent
	})
	
	-- Main Panel
	local main = Utils.mkFrame({
		name = "Main",
		size = UDim2.new(0.9, 0, 0.85, 0),
		maxSize = Vector2.new(1200, 700),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.2,
		r = 4,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = CraftingUI.Refs.Overlay
	})
	
	-- Header
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1, -40, 0, 50), pos=UDim2.new(0, 20, 0, 15), bgT=1, parent=main})
	CraftingUI.Refs.Title = Utils.mkLabel({text = "제작 도구", ts = 24, bold = true, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = header})
	
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1,0), bgT=1, color=C.WHITE, ts=26, fn=function() UIManager.closeCrafting() end, parent=header})

	-- Content (70/30)
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -40, 1, -80), pos=UDim2.new(0, 20, 1, -15), anchor=Vector2.new(0, 1), bgT=1, parent=main})
	
	-- Left: Grid (70%)
	local gridContainer = Utils.mkFrame({name="GridContainer", size=UDim2.new(0.7, -10, 1, 0), bgT=1, clips=true, parent=content})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = C.GRAY; scroll.Parent = gridContainer; scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 85, 0, 85)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.Parent = scroll
	
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll
	scroll.ClipsDescendants = false
	
	CraftingUI.Refs.Grid = scroll

	-- Right: Detail (30%)
	local detail = Utils.mkFrame({
		name = "Detail",
		size = UDim2.new(0.3, 0, 1, 0),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BG_PANEL_L,
		bgT = 0.2,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = content
	})
	CraftingUI.Refs.Detail.Frame = detail
	
	local dHeader = Utils.mkFrame({size=UDim2.new(1, 0, 0, 50), pos=UDim2.new(0, 0, 0, 0), bg=C.GOLD_SEL, bgT=0.1, parent=detail})
	CraftingUI.Refs.Detail.Name = Utils.mkLabel({text="제작 정보", size=UDim2.new(1, -20, 1, 0), pos=UDim2.new(0.5, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), ts=20, bold=true, parent=dHeader})
	
	local infoBody = Utils.mkFrame({size=UDim2.new(1, -30, 1, -120), pos=UDim2.new(0, 15, 0, 60), bgT=1, parent=detail})
	local infoList = Instance.new("UIListLayout"); infoList.Padding = UDim.new(0, 10); infoList.HorizontalAlignment = Enum.HorizontalAlignment.Center; infoList.Parent = infoBody
	
	CraftingUI.Refs.Detail.Time = Utils.mkLabel({text="", size=UDim2.new(1, 0, 0, 20), color=C.GOLD, ts=14, parent=infoBody})
	
	local mScroll = Instance.new("ScrollingFrame")
	mScroll.Size = UDim2.new(1, 0, 1, -50); mScroll.BackgroundTransparency = 1; mScroll.BorderSizePixel = 0; mScroll.ScrollBarThickness = 0; mScroll.Parent = infoBody
	CraftingUI.Refs.Detail.Mats = Utils.mkLabel({text="", size=UDim2.new(1, 0, 0, 0), color=C.WHITE, ts=13, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=mScroll})
	CraftingUI.Refs.Detail.Mats.AutomaticSize = Enum.AutomaticSize.Y

	local footer = Utils.mkFrame({size=UDim2.new(1, -20, 0, 50), pos=UDim2.new(0.5, 0, 1, -10), anchor=Vector2.new(0.5, 1), bgT=1, parent=detail})
	CraftingUI.Refs.Detail.BtnCraft = Utils.mkBtn({text="제작 시작", size=UDim2.new(1, 0, 1, 0), bg=C.GOLD_SEL, r=4, ts=18, bold=true, color=C.BG_PANEL, fn=function() UIManager._doCraft() end, parent=footer})
end

return CraftingUI
