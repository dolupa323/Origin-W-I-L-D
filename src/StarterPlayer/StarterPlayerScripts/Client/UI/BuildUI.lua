-- BuildUI.lua
-- 듀랑고 스타일 건축 UI (별도 창)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local BuildUI = {}
BuildUI.Refs = {
	Frame = nil,
	Grid = nil,
	Preview = nil,
}

function BuildUI.SetVisible(visible)
	if BuildUI.Refs.Frame then
		BuildUI.Refs.Frame.Visible = visible
	end
end

function BuildUI.Init(parent, UIManager)
	BuildUI.Refs.Frame = Utils.mkFrame({
		name = "BuildMenu",
		size = UDim2.new(0.5, 0, 0.6, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.4,
		r = 8,
		stroke = 2,
		parent = parent
	})

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "BuildGrid"
	grid.Size = UDim2.new(1, 0, 0.7, 0)
	grid.Position = UDim2.new(0, 0, 0, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.Parent = BuildUI.Refs.Frame
	BuildUI.Refs.Grid = grid

	local preview = Utils.mkFrame({name="PreviewPanel", size=UDim2.new(1,0,0,120), pos=UDim2.new(0,0,0.7,0), anchor=Vector2.new(0,0), bgT=1, parent=BuildUI.Refs.Frame})
	BuildUI.Refs.Preview = preview

	Utils.mkLabel({text="건축 미리보기", ts=18, bold=true, color=C.GOLD, parent=preview})
end

return BuildUI
