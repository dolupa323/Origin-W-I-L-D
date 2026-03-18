-- TotemUI.lua
-- 거점 토템 상호작용 UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)

local C = Theme.Colors
local F = Theme.Fonts

local TotemUI = {}
TotemUI.Refs = {}

local currentUIManager = nil

local function formatRemaining(seconds)
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	local d = math.floor(s / 86400)
	s = s % 86400
	local h = math.floor(s / 3600)
	s = s % 3600
	local m = math.floor(s / 60)
	if d > 0 then
		return string.format("%d일 %d시간", d, h)
	end
	if h > 0 then
		return string.format("%d시간 %d분", h, m)
	end
	return string.format("%d분", m)
end

function TotemUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager

	local window = Utils.mkWindow({
		name = "TotemWindow",
		size = UDim2.new(0, isMobile and 430 or 470, 0, isMobile and 450 or 500),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.25,
		stroke = 1,
		strokeC = C.BORDER,
		vis = false,
		parent = parent,
	})
	TotemUI.Refs.Frame = window

	local title = Utils.mkLabel({
		text = "거점 토템",
		size = UDim2.new(1, -70, 0, 46),
		pos = UDim2.new(0, 16, 0, 10),
		font = F.TITLE,
		ts = 24,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})
	TotemUI.Refs.Title = title

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 42, 0, 42),
		pos = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(1, 0),
		bg = Color3.fromRGB(60, 60, 70),
		ts = 20,
		fn = function()
			UIManager.closeTotem()
		end,
		parent = window,
	})

	TotemUI.Refs.Status = Utils.mkLabel({
		text = "보호 상태: 확인 중",
		size = UDim2.new(1, -32, 0, 26),
		pos = UDim2.new(0, 16, 0, 64),
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.Remaining = Utils.mkLabel({
		text = "효과 유지 기간: --",
		size = UDim2.new(1, -32, 0, 26),
		pos = UDim2.new(0, 16, 0, 94),
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.Radius = Utils.mkLabel({
		text = "보호 반경: --m",
		size = UDim2.new(1, -32, 0, 26),
		pos = UDim2.new(0, 16, 0, 124),
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.Gold = Utils.mkLabel({
		text = "보유 골드: --",
		size = UDim2.new(1, -32, 0, 26),
		pos = UDim2.new(0, 16, 0, 154),
		ts = 16,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	local warningFrame = Utils.mkFrame({
		name = "RaidWarning",
		size = UDim2.new(1, -32, 0, 46),
		pos = UDim2.new(0, 16, 0, 184),
		bg = Color3.fromRGB(135, 28, 28),
		bgT = 0.2,
		stroke = 1,
		strokeC = Color3.fromRGB(255, 175, 175),
		vis = false,
		parent = window,
	})
	TotemUI.Refs.RaidWarning = warningFrame

	TotemUI.Refs.RaidWarningIcon = Utils.mkLabel({
		text = "⚠",
		size = UDim2.new(0, 30, 1, 0),
		pos = UDim2.new(0, 8, 0, 0),
		font = F.TITLE,
		ts = 24,
		color = Color3.fromRGB(255, 220, 130),
		ax = Enum.TextXAlignment.Center,
		parent = warningFrame,
	})

	TotemUI.Refs.RaidWarningText = Utils.mkLabel({
		text = "유지비 만료: 현재 약탈 가능 상태",
		size = UDim2.new(1, -44, 1, 0),
		pos = UDim2.new(0, 38, 0, 0),
		ts = 15,
		color = Color3.fromRGB(255, 230, 230),
		ax = Enum.TextXAlignment.Left,
		parent = warningFrame,
	})

	Utils.mkBtn({
		text = "영역 확인",
		size = UDim2.new(0.5, -20, 0, 40),
		pos = UDim2.new(0, 16, 0, 236),
		bg = Color3.fromRGB(60, 120, 200),
		font = F.TITLE,
		ts = 16,
		fn = function()
			if currentUIManager and currentUIManager.highlightTotemZone then
				currentUIManager.highlightTotemZone()
			end
		end,
		parent = window,
	})

	Utils.mkBtn({
		text = "새로고침",
		size = UDim2.new(0.5, -20, 0, 40),
		pos = UDim2.new(0.5, 4, 0, 236),
		bg = Color3.fromRGB(90, 90, 110),
		font = F.TITLE,
		ts = 16,
		fn = function()
			if currentUIManager and currentUIManager.refreshTotem then
				currentUIManager.refreshTotem()
			end
		end,
		parent = window,
	})

	TotemUI.Refs.Cost1 = Utils.mkBtn({
		text = "1일 유지 ~ 100 Gold",
		size = UDim2.new(1, -32, 0, 44),
		pos = UDim2.new(0, 16, 0, 290),
		bg = Color3.fromRGB(205, 168, 86),
		color = Color3.fromRGB(30, 30, 30),
		font = F.TITLE,
		ts = 17,
		fn = function()
			if currentUIManager and currentUIManager.requestTotemPay then
				currentUIManager.requestTotemPay(1)
			end
		end,
		parent = window,
	})

	TotemUI.Refs.Cost3 = Utils.mkBtn({
		text = "3일 유지 ~ 280 Gold",
		size = UDim2.new(1, -32, 0, 44),
		pos = UDim2.new(0, 16, 0, 340),
		bg = Color3.fromRGB(185, 152, 76),
		color = Color3.fromRGB(30, 30, 30),
		font = F.TITLE,
		ts = 17,
		fn = function()
			if currentUIManager and currentUIManager.requestTotemPay then
				currentUIManager.requestTotemPay(3)
			end
		end,
		parent = window,
	})

	TotemUI.Refs.Cost7 = Utils.mkBtn({
		text = "7일 유지 ~ 630 Gold",
		size = UDim2.new(1, -32, 0, 44),
		pos = UDim2.new(0, 16, 0, 390),
		bg = Color3.fromRGB(165, 138, 66),
		color = Color3.fromRGB(30, 30, 30),
		font = F.TITLE,
		ts = 17,
		fn = function()
			if currentUIManager and currentUIManager.requestTotemPay then
				currentUIManager.requestTotemPay(7)
			end
		end,
		parent = window,
	})
end

function TotemUI.SetVisible(visible)
	if TotemUI.Refs.Frame then
		TotemUI.Refs.Frame.Visible = visible
	end
end

function TotemUI.Refresh(info)
	if type(info) ~= "table" then
		return
	end

	local upkeep = info.upkeep or {}
	local active = upkeep.active == true
	local remaining = formatRemaining(upkeep.remainingSeconds)
	local radius = tonumber(info.radius) or 0
	local gold = tonumber(info.gold) or 0

	TotemUI.Refs.Status.Text = active and "보호 상태: 활성" or "보호 상태: 비활성"
	TotemUI.Refs.Status.TextColor3 = active and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(255, 130, 130)
	TotemUI.Refs.Remaining.Text = "효과 유지 기간: " .. remaining
	TotemUI.Refs.Radius.Text = string.format("보호 반경: %.0fm", radius)
	TotemUI.Refs.Gold.Text = string.format("보유 골드: %d", gold)
	TotemUI.Refs.RaidWarning.Visible = not active

	local opts = upkeep.options or {}
	local function costFor(days, fallback)
		for _, opt in ipairs(opts) do
			if tonumber(opt.days) == days then
				return tonumber(opt.cost) or fallback
			end
		end
		return fallback
	end

	TotemUI.Refs.Cost1.Text = string.format("1일 유지 ~ %d Gold", costFor(1, 100))
	TotemUI.Refs.Cost3.Text = string.format("3일 유지 ~ %d Gold", costFor(3, 280))
	TotemUI.Refs.Cost7.Text = string.format("7일 유지 ~ %d Gold", costFor(7, 630))

	local canManage = info.canManage == true
	TotemUI.Refs.Cost1.Active = canManage
	TotemUI.Refs.Cost1.AutoButtonColor = canManage
	TotemUI.Refs.Cost3.Active = canManage
	TotemUI.Refs.Cost3.AutoButtonColor = canManage
	TotemUI.Refs.Cost7.Active = canManage
	TotemUI.Refs.Cost7.AutoButtonColor = canManage

	if canManage then
		TotemUI.Refs.Cost1.TextTransparency = 0
		TotemUI.Refs.Cost3.TextTransparency = 0
		TotemUI.Refs.Cost7.TextTransparency = 0
	else
		TotemUI.Refs.Cost1.TextTransparency = 0.35
		TotemUI.Refs.Cost3.TextTransparency = 0.35
		TotemUI.Refs.Cost7.TextTransparency = 0.35
	end
end

return TotemUI
