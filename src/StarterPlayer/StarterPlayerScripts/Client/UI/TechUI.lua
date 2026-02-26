-- TechUI.lua
-- Durango Style 기술 트리 UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local TechUI = {}
TechUI.Refs = {
	Overlay = nil,
	Title = nil,
	TreeScroll = nil,
	TPLabel = nil,
	Detail = {
		Frame = nil,
		Name = nil,
		DescText = nil,
		Cost = nil,
		BtnUnlock = nil,
	}
}

function TechUI.SetVisible(visible)
	if TechUI.Refs.Overlay then
		TechUI.Refs.Overlay.Visible = visible
	end
end

function TechUI.Refresh(techData, unlockedNodes, currentTP, getItemIcon, UIManager)
	if TechUI.Refs.TPLabel then
		TechUI.Refs.TPLabel.Text = "보유 기술 포인트 (TP): " .. currentTP
	end
	
	local scroll = TechUI.Refs.TreeScroll
	if not scroll then return end
	
	for _, ch in pairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end
	
	for _, node in ipairs(techData) do
		local isUnlocked = unlockedNodes[node.id]
		local slot = Utils.mkSlot({
			name = node.id,
			r = 8,
			bgT = 0.4,
			strokeC = isUnlocked and C.GOLD or C.LOCK,
			parent = scroll
		})
		
		slot.icon.Image = node.icon or getItemIcon(node.id)
		if not isUnlocked then
			slot.icon.ImageColor3 = Color3.new(0.4, 0.4, 0.4)
		end
		
		slot.click.MouseButton1Click:Connect(function()
			UIManager._onTechNodeClick(node)
		end)
	end
end

function TechUI.UpdateDetail(node, isUnlocked, canAfford, UIManager)
	local d = TechUI.Refs.Detail
	if not d.Frame then return end
	
	d.Frame.Visible = true
	d.Name.Text = (isUnlocked and "✓ " or "") .. (node.name or node.id)
	d.DescText.Text = node.desc or "설명이 없습니다."
	d.Cost.Text = isUnlocked and "연구 완료" or ("연구 필요 TP: " .. (node.cost or 0))
	d.Cost.TextColor3 = isUnlocked and C.GREEN or (canAfford and C.GOLD or C.RED)
	
	d.BtnUnlock.Visible = not isUnlocked
	d.BtnUnlock.Text = canAfford and "연구 시작" or "포인트 부족"
	d.BtnUnlock.BackgroundColor3 = canAfford and C.GOLD_SEL or C.BTN_DIS
end

function TechUI.Init(parent, UIManager)
	-- Overlay
	TechUI.Refs.Overlay = Utils.mkFrame({
		name = "TechOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.5,
		vis = false,
		parent = parent
	})
	
	-- Main Panel
	local main = Utils.mkFrame({
		name = "Main",
		size = UDim2.new(0.9, 0, 0.9, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.2,
		r = 4,
		stroke = 1,
		parent = TechUI.Refs.Overlay
	})
	
	-- Top Bar
	local topBar = Utils.mkFrame({size=UDim2.new(1, -40, 0, 60), pos=UDim2.new(0, 20, 0, 15), bgT=1, parent=main})
	TechUI.Refs.Title = Utils.mkLabel({text="기술 트리", ts=26, bold=true, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=topBar})
	TechUI.Refs.TPLabel = Utils.mkLabel({text="TP: 0", pos=UDim2.new(0, 0, 0, 30), ts=18, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=topBar})
	
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, 0, 0, 5), anchor=Vector2.new(1,0), bgT=1, color=C.WHITE, ts=26, fn=function() UIManager.closeTechTree() end, parent=topBar})

	-- Tree Scroll Area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TreeScroll"
	scroll.Size = UDim2.new(1, -40, 1, -250)
	scroll.Position = UDim2.new(0, 20, 0, 100)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = C.GRAY; scroll.Parent = main; scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 100, 0, 100)
	grid.CellPadding = UDim2.new(0, 20, 0, 20)
	grid.Parent = scroll
	TechUI.Refs.TreeScroll = scroll

	-- Bottom Detail Panel
	local detail = Utils.mkFrame({
		name = "Detail",
		size = UDim2.new(1, -40, 0, 130),
		pos = UDim2.new(0, 20, 1, -20),
		anchor = Vector2.new(0, 1),
		bg = C.BG_PANEL_L,
		bgT = 0.2,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		vis = false,
		parent = main
	})
	TechUI.Refs.Detail.Frame = detail
	
	local infoBody = Utils.mkFrame({size=UDim2.new(0.65, 0, 1, -20), pos=UDim2.new(0, 20, 0, 10), bgT=1, parent=detail})
	TechUI.Refs.Detail.Name = Utils.mkLabel({text="기술명", size=UDim2.new(1, 0, 0, 30), ts=22, bold=true, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=infoBody})
	TechUI.Refs.Detail.DescText = Utils.mkLabel({text="설명...", pos=UDim2.new(0, 0, 0, 30), size=UDim2.new(1, 0, 0, 60), ts=14, color=C.GRAY, ax=Enum.TextXAlignment.Left, wrap=true, parent=infoBody})
	
	local rightSide = Utils.mkFrame({size=UDim2.new(0.3, -10, 1, -20), pos=UDim2.new(1, -10, 0, 10), anchor=Vector2.new(1, 0), bgT=1, parent=detail})
	TechUI.Refs.Detail.Cost = Utils.mkLabel({text="포인트", size=UDim2.new(1, 0, 0, 30), ts=16, bold=true, parent=rightSide})
	TechUI.Refs.Detail.BtnUnlock = Utils.mkBtn({text="연구 시작", size=UDim2.new(1, 0, 0, 50), pos=UDim2.new(0, 0, 1, 0), anchor=Vector2.new(0, 1), bg=C.GOLD_SEL, r=4, ts=18, bold=true, color=C.BG_PANEL, fn=function() UIManager._doUnlockTech() end, parent=rightSide})
end

return TechUI
