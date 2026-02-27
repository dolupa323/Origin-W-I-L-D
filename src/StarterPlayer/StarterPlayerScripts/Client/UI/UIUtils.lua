-- UIUtils.lua
-- UI 레이아웃, 액션 버튼 (Hexagon 등), 비율 유지 유틸리티

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local UIUtils = {}

--- 비율 고정된 최상위 윈도우 랩퍼
function UIUtils.mkWindow(p)
	local win = UIUtils.mkFrame(p)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = p.ratio or 1.5 -- 가로 세로 비율
	ratio.Parent = win
	return win
end

function UIUtils.mkFrame(p)
	local f = Instance.new("Frame")
	f.Name = p.name or "Frame"
	f.Size = p.size or UDim2.new(1, 0, 1, 0)
	f.Position = p.pos or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = p.anchor or Vector2.zero
	f.BackgroundColor3 = p.bg or C.BG_PANEL
	f.BackgroundTransparency = p.bgT or T.PANEL
	f.BorderSizePixel = 0
	f.Visible = p.vis ~= false
	f.ZIndex = p.z or 1
	f.ClipsDescendants = p.clips or false
	f.Parent = p.parent
	
	if p.r then
		local c = Instance.new("UICorner")
		c.CornerRadius = (p.r == "full") and UDim.new(1, 0) or UDim.new(0, p.r)
		c.Parent = f
	end
	
	if p.stroke or p.strokeC then
		local s = Instance.new("UIStroke")
		s.Thickness = p.stroke or 1
		s.Color = p.strokeC or C.BORDER
		s.Transparency = p.strokeT or 0.2
		s.Parent = f
	end
	
	if p.maxSize then
		local c = Instance.new("UISizeConstraint")
		c.MaxSize = p.maxSize
		c.Parent = f
	end
	
	return f
end

function UIUtils.mkLabel(p)
	local l = Instance.new("TextLabel")
	l.Name = p.name or "Label"
	l.Size = p.size or UDim2.new(1, 0, 1, 0)
	l.Position = p.pos or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = p.anchor or Vector2.zero
	l.BackgroundTransparency = 1
	l.Text = p.text or ""
	l.TextColor3 = p.color or C.WHITE
	l.TextSize = p.ts or 14
	l.Font = p.font or F.NORMAL
	l.TextXAlignment = p.ax or Enum.TextXAlignment.Center
	l.TextYAlignment = p.ay or Enum.TextYAlignment.Center
	l.TextStrokeTransparency = p.st or 0.7
	l.TextWrapped = p.wrap or false
	l.RichText = p.rich or false
	l.ZIndex = p.z or 1
	l.Parent = p.parent
	
	if p.autoSize then l.AutomaticSize = Enum.AutomaticSize.XY end
	if p.bold then l.Font = F.TITLE end
	return l
end

function UIUtils.mkBtn(p)
	local b = Instance.new("TextButton")
	b.Name = p.name or "Button"
	b.Size = p.size or UDim2.new(0, 120, 0, 40)
	b.Position = p.pos or UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = p.anchor or Vector2.zero
	b.BackgroundColor3 = p.bg or C.BTN
	b.BackgroundTransparency = p.bgT or 0.2
	b.BorderSizePixel = 0
	b.Text = p.text or ""
	b.TextColor3 = p.color or C.WHITE
	b.TextSize = p.ts or 16
	b.Font = p.font or F.NORMAL
	b.AutoButtonColor = false
	b.ZIndex = p.z or 1
	b.Parent = p.parent
	
	if p.r then
		local c = Instance.new("UICorner")
		c.CornerRadius = (p.r == "full") and UDim.new(1, 0) or UDim.new(0, p.r)
		c.Parent = b
	end
	
	if p.stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = p.stroke == true and 1.5 or p.stroke
		s.Color = p.strokeC or C.BORDER
		s.Parent = b
	end
	
	local nc, hc = b.BackgroundColor3, p.hbg or C.BTN_H
	b.MouseEnter:Connect(function() 
		TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = hc, BackgroundTransparency = 0}):Play() 
	end)
	b.MouseLeave:Connect(function() 
		TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = nc, BackgroundTransparency = p.bgT or 0.2}):Play() 
	end)
	
	if p.fn then b.MouseButton1Click:Connect(p.fn) end
	return b
end

function UIUtils.mkHexBtn(p)
	-- Hexagon-styled button with dummy image
	local b = Instance.new("ImageButton")
	b.Name = p.name or "HexButton"
	b.Size = p.size or UDim2.new(0, 80, 0, 80)
	b.Position = p.pos or UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = p.anchor or Vector2.zero
	b.BackgroundTransparency = 1
	b.Image = "rbxassetid://3192468761"
	b.ImageColor3 = p.bg or C.BG_PANEL
	b.ImageTransparency = p.bgT or 0.4
	b.ZIndex = p.z or 1
	b.Parent = p.parent
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = b
	
	if p.stroke then
		local s = Instance.new("ImageLabel")
		s.Size = UDim2.new(1.1, 0, 1.1, 0)
		s.Position = UDim2.new(0.5, 0, 0.5, 0)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.BackgroundTransparency = 1
		s.Image = "rbxassetid://3192468761"
		s.ImageColor3 = p.strokeC or C.WHITE
		s.ZIndex = b.ZIndex - 1
		s.Parent = b
	end
	
	if p.fn then b.MouseButton1Click:Connect(p.fn) end
	return b
end

--- 비율 고정된 슬롯 (찌그러짐 방지)
function UIUtils.mkSlot(p)
	local slot = UIUtils.mkFrame({
		name = p.name or "Slot",
		size = p.size or UDim2.new(1, 0, 1, 0), -- Grid Layout에서 제어됨
		bg = p.bg or C.BG_SLOT,
		bgT = p.bgT or T.SLOT,
		r = p.r or 0, -- 듀랑고는 각진 사각형
		stroke = p.stroke or 1,
		strokeC = p.strokeC or C.BORDER_DIM,
		z = p.z or 1,
		parent = p.parent
	})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = slot
	
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0.8, 0, 0.8, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = slot.ZIndex + 1
	icon.Parent = slot
	
	local count = UIUtils.mkLabel({
		name = "Count",
		size = UDim2.new(1, -4, 0, 15),
		pos = UDim2.new(0, 0, 1, -2),
		anchor = Vector2.new(0, 1),
		text = "",
		ts = 13,
		font = F.NUM,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Right,
		z = slot.ZIndex + 2,
		parent = slot
	})

	local click = Instance.new("TextButton")
	click.Name = "Click"
	click.Size = UDim2.new(1, 0, 1, 0)
	click.BackgroundTransparency = 1
	click.Text = ""
	click.ZIndex = slot.ZIndex + 5
	click.Parent = slot
	
	return {
		frame = slot,
		icon = icon,
		countLabel = count,
		click = click
	}
end

function UIUtils.mkBar(p)
	local container = UIUtils.mkFrame({
		name = p.name or "Bar",
		size = p.size,
		pos = p.pos,
		bg = p.bg or Color3.fromRGB(40, 40, 40),
		bgT = p.bgT or 0.4,
		r = p.r or 0,
		parent = p.parent
	})
	
	local fill = UIUtils.mkFrame({
		name = "Fill",
		size = UDim2.new(1, 0, 1, 0),
		bg = p.fillC or C.HP,
		bgT = 0,
		r = p.r or 0,
		parent = container
	})
	
	local label = UIUtils.mkLabel({
		name = "Value",
		text = p.text or "",
		ts = p.ts or 12,
		font = F.NUM,
		z = 10,
		parent = container
	})
	
	return {
		container = container,
		fill = fill,
		label = label
	}
end

return UIUtils
