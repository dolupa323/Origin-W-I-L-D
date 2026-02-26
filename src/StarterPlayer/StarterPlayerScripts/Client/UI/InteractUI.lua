-- InteractUI.lua
-- 상호작용 및 건축 가이드 프롬프트 (Original Minimal Style)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors

local InteractUI = {}

InteractUI.Refs = {
	PromptFrame = nil,
	PromptLabel = nil,
	BuildPrompt = nil,
}

function InteractUI.SetVisible(visible)
	if InteractUI.Refs.PromptFrame then
		InteractUI.Refs.PromptFrame.Visible = visible
	end
end

function InteractUI.SetBuildVisible(visible)
	if InteractUI.Refs.BuildPrompt then
		InteractUI.Refs.BuildPrompt.Visible = visible
	end
end

function InteractUI.UpdatePrompt(text)
	if InteractUI.Refs.PromptLabel then
		InteractUI.Refs.PromptLabel.Text = text
		InteractUI.Refs.PromptLabel.RichText = true
	end
end

function InteractUI.Init(parent)
	-- Interaction Prompt (Center Bottom)
	local prompt = Utils.mkFrame({
		name = "InteractPrompt",
		size = UDim2.new(0, 220, 0, 55),
		pos = UDim2.new(0.5, 0, 0.75, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.8,
		r = 27, -- Pill shape
		stroke = 2,
		vis = false,
		parent = parent
	})
	InteractUI.Refs.PromptFrame = prompt
	InteractUI.Refs.PromptLabel = Utils.mkLabel({
		text = "[Z] 상호작용",
		ts = 16,
		bold = true,
		parent = prompt
	})

	-- Build Controls (Bottom Left)
	local build = Utils.mkFrame({
		name = "BuildPrompt",
		size = UDim2.new(0, 220, 0, 100), -- Slightly larger
		pos = UDim2.new(0, 20, 1, -20),
		anchor = Vector2.new(0, 1),
		bg = C.BG_PANEL,
		bgT = 0.8,
		r = 12,
		stroke = 2,
		vis = false,
		parent = parent
	})
	InteractUI.Refs.BuildPrompt = build
	
	local listLayer = Instance.new("UIListLayout")
	listLayer.Padding = UDim.new(0, 8); listLayer.HorizontalAlignment = Enum.HorizontalAlignment.Left; listLayer.Parent = build
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 20); p.PaddingTop = UDim.new(0, 15); p.Parent = build

	Utils.mkLabel({text = "🛠️ 건축 컨트롤", ts = 14, bold = true, color = C.GOLD, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = " LMB : 배치 확정", ts = 12, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = " R  : 회전", ts = 12, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = " X  : 취소", ts = 12, color = Color3.fromRGB(255, 100, 100), ax = Enum.TextXAlignment.Left, parent = build})
end

return InteractUI
