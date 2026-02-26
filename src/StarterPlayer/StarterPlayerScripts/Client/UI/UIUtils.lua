-- UIUtils.lua
-- UI 생성 및 레이아웃 자동화를 위한 유틸리티 클래스 (Original Design Support)

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local UIUtils = {}

--- 기본 프레임 생성 (반응형 + 오리지널 스타일)
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
	
	-- 원형 또는 라운드 처리
	if p.r then
		local c = Instance.new("UICorner")
		c.CornerRadius = (p.r == "full") and UDim.new(1, 0) or UDim.new(0, p.r)
		c.Parent = f
	end
	
	-- 테두리 (Original: Thin White Border)
	if p.stroke or p.strokeC then
		local s = Instance.new("UIStroke")
		s.Thickness = p.stroke or 1
		s.Color = p.strokeC or C.BORDER
		s.Transparency = p.strokeT or 0.2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end
	
	-- Constraints
	if p.maxSize then
		local c = Instance.new("UISizeConstraint")
		c.MaxSize = p.maxSize
		c.Parent = f
	end
	if p.aspect then
		local c = Instance.new("UIAspectRatioConstraint")
		c.AspectRatio = p.aspect
		c.Parent = f
	end
	
	return f
end

--- 원형 프레임 헬퍼
function UIUtils.mkCircle(p)
	p.r = "full"
	p.aspect = 1
	return UIUtils.mkFrame(p)
end

--- 텍스트 라벨 생성
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
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextWrapped = p.wrap or false
	l.ZIndex = p.z or 1
	l.Parent = p.parent
	
	if p.autoSize then
		l.AutomaticSize = Enum.AutomaticSize.XY
	end
	if p.bold then l.Font = F.TITLE end
	
	return l
end

--- 버튼 생성 (애니메이션 개선)
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
		s.Thickness = 1.5
		s.Color = C.BORDER
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

--- 오리지널 스타일 슬롯 (Diamond/Circle 지원)
function UIUtils.mkSlot(p)
	local slot = UIUtils.mkFrame({
		name = p.name or "Slot",
		size = p.size or UDim2.new(0, 64, 0, 64),
		pos = p.pos,
		bg = p.bg or C.BG_SLOT,
		bgT = p.bgT or T.SLOT,
		r = p.r or 8,
		stroke = p.stroke or 1,
		strokeC = p.strokeC or C.BORDER_DIM,
		z = p.z or 1,
		parent = p.parent
	})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = slot
	
	-- Diamond 효과 (Rotation)
	if p.diamond then
		slot.Rotation = 45
	end
	
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0.75, 0, 0.75, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = slot.ZIndex + 1
	icon.Rotation = p.diamond and -45 or 0 -- 아이콘은 정방향
	icon.Parent = slot
	
	local count = UIUtils.mkLabel({
		name = "Count",
		size = UDim2.new(1, -5, 0, 15),
		pos = UDim2.new(0, 0, 1, -2),
		anchor = Vector2.new(0, 1),
		text = "",
		ts = 12,
		font = F.NUM,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Right,
		z = slot.ZIndex + 2,
		parent = slot
	})
	if p.diamond then count.Rotation = -45 end

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

--- 진행도 바 (Thin/Circular/Standard)
function UIUtils.mkBar(p)
	local container = UIUtils.mkFrame({
		name = p.name or "Bar",
		size = p.size,
		pos = p.pos,
		bg = p.bgC or C.BG_BAR,
		bgT = p.bgT or 0.5,
		r = p.r or 2,
		stroke = p.stroke,
		strokeC = p.strokeC,
		z = p.z or 1,
		parent = p.parent
	})
	
	local fill = UIUtils.mkFrame({
		name = "Fill",
		size = UDim2.new(1, 0, 1, 0),
		bg = p.fillC or C.HP,
		bgT = 0,
		r = p.r or 2,
		z = container.ZIndex,
		parent = container
	})
	
	local label = UIUtils.mkLabel({
		name = "Value",
		text = p.text or "",
		ts = p.ts or 10,
		font = F.NUM,
		z = container.ZIndex + 1,
		parent = container
	})
	
	return {
		container = container,
		fill = fill,
		label = label
	}
end

return UIUtils
