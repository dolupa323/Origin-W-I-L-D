-- InteractUI.lua
-- 상호작용 및 건축 가이드 프롬프트 (Original Minimal Style)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local InteractUI = {}

InteractUI.Refs = {
	PromptFrame = nil,
	PromptNameLabel = nil,
	PromptKeyLabel = nil,
	PromptDurabilityFrame = nil,
	PromptDurabilityFill = nil,
	PromptDurabilityLabel = nil,
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

function InteractUI.UpdatePrompt(nameText, keyText)
	if InteractUI.Refs.PromptNameLabel then
		InteractUI.Refs.PromptNameLabel.Text = nameText or ""
	end
	if InteractUI.Refs.PromptKeyLabel then
		InteractUI.Refs.PromptKeyLabel.Text = keyText or ""
	end
end

function InteractUI.SetDurabilityVisible(visible)
	if InteractUI.Refs.PromptDurabilityFrame then
		InteractUI.Refs.PromptDurabilityFrame.Visible = visible
	end
end

function InteractUI.UpdateDurability(current, max)
	local frame = InteractUI.Refs.PromptDurabilityFrame
	local fill = InteractUI.Refs.PromptDurabilityFill
	local label = InteractUI.Refs.PromptDurabilityLabel
	if not frame or not fill or not label then return end

	local maxValue = math.max(max or 1, 1)
	local ratio = math.clamp((current or 0) / maxValue, 0, 1)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	label.Text = UILocalizer.Localize(string.format("내구도 %d%%", math.floor(ratio * 100)))

	if ratio < 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(200, 70, 50)
	elseif ratio < 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(230, 180, 60)
	else
		fill.BackgroundColor3 = Color3.fromRGB(90, 175, 75)
	end
end

function InteractUI.Init(parent, isMobile)
	local isSmall = isMobile
	
	-- Interaction Prompt — 투명 미니말 (알림창/경고창 컨벤션)
	local prompt = Utils.mkFrame({
		name = "InteractPrompt",
		size = UDim2.new(0, 0, 0, 0),
		pos = UDim2.new(0.5, 0, isSmall and 0.52 or 0.55, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.85,
		r = 4,
		stroke = false,
		vis = false,
		parent = parent
	})
	prompt.AutomaticSize = Enum.AutomaticSize.XY

	local sizeC = Instance.new("UISizeConstraint")
	sizeC.MinSize = Vector2.new(120, 40)
	sizeC.MaxSize = Vector2.new(400, 180)
	sizeC.Parent = prompt

	local promptLayout = Instance.new("UIListLayout")
	promptLayout.Padding = UDim.new(0, 2)
	promptLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	promptLayout.SortOrder = Enum.SortOrder.LayoutOrder
	promptLayout.Parent = prompt

	local promptPad = Instance.new("UIPadding")
	promptPad.PaddingTop = UDim.new(0, 10)
	promptPad.PaddingBottom = UDim.new(0, 10)
	promptPad.PaddingLeft = UDim.new(0, 24)
	promptPad.PaddingRight = UDim.new(0, 24)
	promptPad.Parent = prompt

	InteractUI.Refs.PromptFrame = prompt

	-- 1) 건물 이름 (큰 글씨)
	local nameLabel = Utils.mkLabel({
		text = "",
		size = UDim2.new(0, 0, 0, 0),
		ts = 20,
		font = F.TITLE,
		color = C.GOLD,
		parent = prompt
	})
	nameLabel.AutomaticSize = Enum.AutomaticSize.XY
	nameLabel.LayoutOrder = 1
	nameLabel.TextWrapped = false
	InteractUI.Refs.PromptNameLabel = nameLabel

	-- 2) 빈 공간 (한탭 띄우기)
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.Size = UDim2.new(0, 1, 0, 4)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 2
	spacer.Parent = prompt

	-- 3) 키 안내 (작은 글씨)
	local keyLabel = Utils.mkLabel({
		text = "",
		size = UDim2.new(0, 0, 0, 0),
		ts = 14,
		font = F.NORMAL,
		color = C.INK,
		parent = prompt
	})
	keyLabel.AutomaticSize = Enum.AutomaticSize.XY
	keyLabel.LayoutOrder = 3
	keyLabel.TextWrapped = false
	InteractUI.Refs.PromptKeyLabel = keyLabel

	-- 4) 내구도 바
	local hpWrap = Utils.mkFrame({
		name = "PromptDurability",
		size = UDim2.new(1, 0, 0, 10),
		bg = C.BG_SLOT,
		r = 3,
		vis = false,
		parent = prompt
	})
	hpWrap.LayoutOrder = 4

	local hpFill = Utils.mkFrame({
		name = "Fill",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(90, 175, 75),
		r = 5,
		parent = hpWrap
	})

	local hpLabel = Utils.mkLabel({
		text = UILocalizer.Localize("내구도 100%"),
		size = UDim2.new(1, 0, 1, 0),
		ts = 11,
		font = F.BODY,
		color = C.WHITE,
		parent = hpWrap
	})

	InteractUI.Refs.PromptDurabilityFrame = hpWrap
	InteractUI.Refs.PromptDurabilityFill = hpFill
	InteractUI.Refs.PromptDurabilityLabel = hpLabel

	-- Build Controls Guide (Bottom Left)
	-- Higher ZIndex to stay above HUD but subtle
	local build = Utils.mkFrame({
		name = "BuildPrompt",
		size = UDim2.new(0, 200, 0, 110),
		pos = UDim2.new(0.02, 0, isSmall and 0.55 or 0.6, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 8,
		stroke = false,
		vis = false,
		parent = parent
	})
	InteractUI.Refs.BuildPrompt = build
	
	local listLayer = Instance.new("UIListLayout")
	listLayer.Padding = UDim.new(0, 4); listLayer.HorizontalAlignment = Enum.HorizontalAlignment.Left; listLayer.Parent = build
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 15); p.PaddingTop = UDim.new(0, 12); p.Parent = build

	Utils.mkLabel({text = UILocalizer.Localize("🛠️ 건축 컨트롤"), ts = 16, font=F.TITLE, color = C.GOLD_SEL, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = UILocalizer.Localize("LMB : 배치 확정"), ts = 14, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = UILocalizer.Localize("R : 시설 회전"), ts = 14, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = UILocalizer.Localize("X : 건축 취소"), ts = 14, color = Color3.fromRGB(200, 90, 70), ax = Enum.TextXAlignment.Left, parent = build})
end

return InteractUI
