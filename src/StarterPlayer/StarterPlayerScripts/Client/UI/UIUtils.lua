-- UIUtils.lua
-- UI 레이아웃, 액션 버튼 (Hexagon 등), 비율 유지 유틸리티

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local UIUtils = {}

--- 비율 고정된 최상위 윈도우 랩퍼
function UIUtils.mkWindow(p)
	local win = UIUtils.mkFrame({
		name = p.name,
		size = p.size,
		pos = p.pos,
		anchor = p.anchor,
		bg = p.bg,
		bgT = p.bgT,
		r = p.r,
		stroke = p.stroke or 2.5, -- Main windows must have a stroke
		strokeC = p.strokeC or C.BORDER,
		strokeT = p.strokeT,
		useCanvas = p.useCanvas,
		z = p.z,
		vis = p.vis,
		parent = p.parent
	})
	if p.ratio then
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = p.ratio
		ratio.Parent = win
	end
	return win
end

--- 일반 UI용 Frame 또는 CanvasGroup 생성기
--- @param p.useCanvas boolean 팝업이나 페이드 인/아웃(Fade in/out) 애니메이션을 위한 최상위 프레임에만 'true' 입력. 과도하게 사용할 경우 CanvasGroup 렌더링 한계로 인해 모바일 해상도가 깨지고 메모리 누수가 발생합니다. 인벤토리 목록 등엔 반드시 Frame을 유지하세요.
function UIUtils.mkFrame(p)
	local f = p.useCanvas and Instance.new("CanvasGroup") or Instance.new("Frame")
	f.Name = p.name or "Frame"
	f.Size = p.size or UDim2.new(1, 0, 1, 0)
	f.Position = p.pos or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = p.anchor or Vector2.zero
	f.BackgroundColor3 = p.bg or C.BG_PANEL
	f.BackgroundTransparency = p.bgT or T.PANEL
	f.BorderSizePixel = 0
	f.Visible = p.vis ~= false
	f.ZIndex = p.z or 1
	if not p.useCanvas then
		f.ClipsDescendants = p.clips or false
	end
	f.Parent = p.parent
	
	-- Warm Rounded Corners
	if p.r ~= false then
		local c = Instance.new("UICorner")
		local radius = p.r or 8
		c.CornerRadius = (radius == "full") and UDim.new(1, 0) or UDim.new(0, radius)
		c.Parent = f
	end
	
	-- Glassmorphism Edge Highlight (Disabled by default per user request: only outermost border)
	if p.stroke == true or type(p.stroke) == "number" then
		local s = Instance.new("UIStroke")
		s.Thickness = (type(p.stroke) == "number") and p.stroke or 1.2
		s.Color = p.strokeC or C.BORDER
		s.Transparency = p.strokeT or 0.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
	l.Text = UILocalizer.Localize(p.text or "")
	l.TextColor3 = p.ink and C.INK or (p.color or C.WHITE)
	l.TextSize = p.ts or 14
	l.Font = p.ink and F.CLASSIC or (p.font or F.NORMAL)
	l.TextXAlignment = p.ax or Enum.TextXAlignment.Center
	l.TextYAlignment = p.ay or Enum.TextYAlignment.Center
	
	-- Clean Text: No more forced strokes/blurring effects
	l.TextStrokeTransparency = (p.st ~= nil) and (1 - p.st) or 1
	if p.stColor then l.TextStrokeColor3 = p.stColor end
	
	l.TextWrapped = p.wrap or false
	l.RichText = p.rich or false
	l.ZIndex = p.z or 1
	l.Parent = p.parent
	
	if p.autoSize then l.AutomaticSize = Enum.AutomaticSize.XY end
	if p.bold then l.Font = F.TITLE end
	if p.vis == false then l.Visible = false end
	return l
end

function UIUtils.mkBtn(p)
	local b = Instance.new("TextButton")
	b.Name = p.name or "Button"
	b.Size = p.size or UDim2.new(0, 120, 0, 40)
	b.Position = p.pos or UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = p.anchor or Vector2.zero
	local isNeg = p.isNegative == true
	b.BackgroundColor3 = p.bg or (isNeg and C.BTN_GRAY or C.BTN)
	b.BackgroundTransparency = p.bgT or 0.35
	b.BorderSizePixel = 0
	b.Text = UILocalizer.Localize(p.text or "")
	b.TextColor3 = p.color or (isNeg and C.INK or C.BG_PANEL) -- Action buttons use dark text for contrast
	b.TextSize = p.ts or 15
	b.Font = p.font or F.TITLE -- Button text usually better as Title font
	b.AutoButtonColor = false
	b.ZIndex = p.z or 1
	b.Parent = p.parent
	
	if p.r ~= false then
		local c = Instance.new("UICorner")
		local radius = p.r or 8
		c.CornerRadius = (radius == "full") and UDim.new(1, 0) or UDim.new(0, radius)
		c.Parent = b
	end
	
	if p.stroke == true or p.strokeC then
		local s = Instance.new("UIStroke")
		s.Thickness = (type(p.stroke) == "number") and p.stroke or 1.5
		s.Color = p.strokeC or C.BORDER
		s.Transparency = 0.3
		s.Parent = b
	end
	
	-- Normal state storage for hover effects (Fixes hover reverting to wrong state color)
	b:SetAttribute("NormalColor", b.BackgroundColor3)
	b:SetAttribute("NormalTransp", b.BackgroundTransparency)

	local hc = p.hbg or (isNeg and C.BTN_GRAY_H or C.BTN_H)
	
	if p.noHover ~= true then
		b.MouseEnter:Connect(function() 
			TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = hc, BackgroundTransparency = 0.15}):Play() 
		end)
		b.MouseLeave:Connect(function() 
			local nc = b:GetAttribute("NormalColor") or b.BackgroundColor3
			local nt = b:GetAttribute("NormalTransp") or b.BackgroundTransparency
			TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = nc, BackgroundTransparency = nt}):Play() 
		end)
	end
	
	if p.fn then b.MouseButton1Click:Connect(p.fn) end
	return b
end

--- 버튼의 기본 상태 색상/투명도를 업데이트 (사이드바 탭 선택 등에 사용)
function UIUtils.setBtnState(b, color, transp)
	if not b then return end
	if color then b:SetAttribute("NormalColor", color); b.BackgroundColor3 = color end
	if transp ~= nil then b:SetAttribute("NormalTransp", transp); b.BackgroundTransparency = transp end
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
		size = p.size or UDim2.new(1, 0, 1, 0),
		bg = p.bg or C.BG_SLOT,
		bgT = p.bgT or T.SLOT,
		r = p.r or 6,
		stroke = p.stroke or false, -- Slots are border-less by default now
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

	local durBg = UIUtils.mkFrame({
		name = "DurabilityBG",
		size = UDim2.new(0.8, 0, 0, 4),
		pos = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		bg = C.BG_DARK,
		bgT = 0,
		vis = false,
		z = slot.ZIndex + 3,
		parent = slot
	})
	
	local durFill = UIUtils.mkFrame({
		name = "Fill",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = Color3.fromRGB(120, 200, 80),
		bgT = 0,
		z = slot.ZIndex + 4,
		parent = durBg
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
		click = click,
		durBg = durBg,
		durFill = durFill
	}
end

function UIUtils.mkBar(p)
	local container = UIUtils.mkFrame({
		name = p.name or "Bar",
		size = p.size,
		pos = p.pos,
		bg = p.bg or C.BG_DARK,
		bgT = p.bgT or 0.5,
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

--- UI 선 그리기 (두 점 사이 연결)
function UIUtils.mkLine(p)
	local line = UIUtils.mkFrame({
		name = p.name or "Line",
		bg = p.color or C.BORDER_DIM,
		bgT = p.bgT or 0.4,
		z = p.z or -1,
		parent = p.parent
	})
	
	-- 두 포인트(Vector2) 사이의 거리와 회전 계산
	local p1, p2 = p.p1, p.p2
	local diff = p2 - p1
	local dist = diff.Magnitude
	local ang = math.deg(math.atan2(diff.Y, diff.X))
	
	line.Size = UDim2.new(0, dist, 0, p.thick or 2)
	line.Position = UDim2.new(0, p1.X, 0, p1.Y)
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Rotation = ang
	
	return line
end

--- CollectionUI 등에서 사용하는 Legacy 헬퍼들
function UIUtils.CreateFrame(name, size, pos, bg, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = bg or C.BG_PANEL
	f.BorderSizePixel = 0
	if parent then f.Parent = parent end
	return f
end

function UIUtils.CreateTextLabel(name, size, pos, text, parent)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text or ""
	l.TextColor3 = C.WHITE
	l.Font = F.NORMAL
	l.TextSize = 14
	if parent then l.Parent = parent end
	return l
end

function UIUtils.CreateImage(name, size, pos, img, parent)
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.Size = size
	i.Position = pos
	i.BackgroundTransparency = 1
	i.ScaleType = Enum.ScaleType.Fit
	i.Image = img or ""
	if parent then i.Parent = parent end
	return i
end

function UIUtils.AddCorner(guiObject, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = guiObject
	return c
end

function UIUtils.CreateCloseButton(UIManager, winId)
	local btn = UIUtils.mkBtn({
		name = "CloseBtn",
		size = UDim2.new(0, 30, 0, 30),
		text = "X",
		bg = C.RED,
		r = "full"
	})
	btn.MouseButton1Click:Connect(function()
		if UIManager.closeCollection and winId == "COLLECTION" then
			UIManager.closeCollection()
		elseif UIManager.closeInventory and winId == "INV" then
			UIManager.closeInventory()
		else
			-- Fallback
			btn.Parent.Visible = false
		end
	end)
	return btn
end

return UIUtils
