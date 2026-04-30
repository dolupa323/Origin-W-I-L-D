-- TotemUI.lua
-- 거점 토템 상호작용 UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)

local C = Theme.Colors
local F = Theme.Fonts

local TotemUI = {}
TotemUI.Refs = {}

local currentUIManager = nil
local expandSelectionVisible = false
local latestInfo = nil
local countdownThreadStarted = false

local function setExpandSelectionVisible(visible)
	expandSelectionVisible = visible == true
	if TotemUI.Refs.ExpandCardFrame then
		TotemUI.Refs.ExpandCardFrame.Visible = expandSelectionVisible
	end
	if TotemUI.Refs.ExpandToggle then
		TotemUI.Refs.ExpandToggle.Text = expandSelectionVisible and "확장 방향 닫기" or "영토 확장"
	end
end

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

local function getLiveUpkeepState(info)
	local upkeep = type(info) == "table" and info.upkeep or {}
	local expiresAt = tonumber(upkeep and upkeep.expiresAt) or 0
	if expiresAt > 0 then
		local remainingSeconds = math.max(0, expiresAt - os.time())
		return remainingSeconds > 0, remainingSeconds
	end
	local remainingSeconds = math.max(0, math.floor(tonumber(upkeep and upkeep.remainingSeconds) or 0))
	return remainingSeconds > 0, remainingSeconds
end

local function refreshLiveCountdown()
	if not TotemUI.Refs.Frame or not TotemUI.Refs.Frame.Visible or type(latestInfo) ~= "table" then
		return
	end

	local active, remainingSeconds = getLiveUpkeepState(latestInfo)
	local upkeep = latestInfo.upkeep or {}
	local west = tonumber(latestInfo.westExtent) or tonumber(latestInfo.radius) or 0
	local east = tonumber(latestInfo.eastExtent) or tonumber(latestInfo.radius) or 0
	local north = tonumber(latestInfo.northExtent) or tonumber(latestInfo.radius) or 0
	local south = tonumber(latestInfo.southExtent) or tonumber(latestInfo.radius) or 0
	local gold = tonumber(latestInfo.gold) or 0
	local expand = latestInfo.expansion or {}
	local nextCost = tonumber(expand.nextCost) or 0
	local freePoints = tonumber(expand.availablePoints) or 0

	TotemUI.Refs.Status.Text = active and "보호 상태: 활성" or "보호 상태: 비활성"
	TotemUI.Refs.Status.TextColor3 = active and Color3.fromRGB(120, 200, 80) or Color3.fromRGB(200, 95, 85)
	TotemUI.Refs.Remaining.Text = "효과 유지 기간: " .. formatRemaining(remainingSeconds)
	TotemUI.Refs.Radius.Text = string.format("보호 범위: %.0fm x %.0fm", west + east, north + south)
	TotemUI.Refs.Gold.Text = string.format("보유 골드: %d", gold)
	TotemUI.Refs.ExpandInfo.Text = string.format(
		"확장 상태: 북 %.0f / 남 %.0f / 동 %.0f / 서 %.0f\n다음 확장: %s",
		north,
		south,
		east,
		west,
		freePoints > 0 and ("재배치 포인트 사용 (" .. tostring(freePoints) .. " 남음)") or (tostring(nextCost) .. " Gold")
	)
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

	local canManage = latestInfo.canManage == true
	local canExpand = canManage and active
	TotemUI.Refs.Cost1.Active = canManage
	TotemUI.Refs.Cost1.AutoButtonColor = canManage
	TotemUI.Refs.Cost3.Active = canManage
	TotemUI.Refs.Cost3.AutoButtonColor = canManage
	TotemUI.Refs.Cost7.Active = canManage
	TotemUI.Refs.Cost7.AutoButtonColor = canManage
	TotemUI.Refs.ExpandToggle.Active = canExpand
	TotemUI.Refs.ExpandToggle.AutoButtonColor = canExpand
	TotemUI.Refs.ExpandNorth.Active = canExpand
	TotemUI.Refs.ExpandNorth.AutoButtonColor = canExpand
	TotemUI.Refs.ExpandWest.Active = canExpand
	TotemUI.Refs.ExpandWest.AutoButtonColor = canExpand
	TotemUI.Refs.ExpandEast.Active = canExpand
	TotemUI.Refs.ExpandEast.AutoButtonColor = canExpand
	TotemUI.Refs.ExpandSouth.Active = canExpand
	TotemUI.Refs.ExpandSouth.AutoButtonColor = canExpand

	if canManage then
		TotemUI.Refs.Cost1.TextTransparency = 0
		TotemUI.Refs.Cost3.TextTransparency = 0
		TotemUI.Refs.Cost7.TextTransparency = 0
	else
		TotemUI.Refs.Cost1.TextTransparency = 0.35
		TotemUI.Refs.Cost3.TextTransparency = 0.35
		TotemUI.Refs.Cost7.TextTransparency = 0.35
	end

	local expandTransparency = canExpand and 0 or 0.35
	TotemUI.Refs.ExpandToggle.TextTransparency = expandTransparency
	TotemUI.Refs.ExpandNorth.TextTransparency = expandTransparency
	TotemUI.Refs.ExpandWest.TextTransparency = expandTransparency
	TotemUI.Refs.ExpandEast.TextTransparency = expandTransparency
	TotemUI.Refs.ExpandSouth.TextTransparency = expandTransparency
	if not canExpand then
		setExpandSelectionVisible(false)
	end
end

local function ensureCountdownThread()
	if countdownThreadStarted then
		return
	end
	countdownThreadStarted = true
	task.spawn(function()
		while true do
			refreshLiveCountdown()
			task.wait(1)
		end
	end)
end

function TotemUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager
	local windowWidth = isMobile and 430 or 470
	local cardWidth = isMobile and 210 or 220
	local cardInnerPad = 10
	local cardGap = 6
	local cardButtonHeight = isMobile and 34 or 38
	local cardTitleHeight = 20
	local cardTopOffset = 30
	local cardBottomPad = 10
	local cardHeight = cardTopOffset + (cardButtonHeight * 3) + (cardGap * 2) + cardBottomPad

	local window = Utils.mkWindow({
		name = "TotemWindow",
		size = isMobile and UDim2.new(0.75, 0, 0.8, 0) or UDim2.new(0.35, 0, 0.75, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.25,
		stroke = 1,
		strokeC = C.BORDER,
		ratio = 0.8, -- Totem is vertical
		vis = false,
		parent = parent,
	})
	TotemUI.Refs.Frame = window

	local title = Utils.mkLabel({
		name = "Title",
		text = "거점 토템",
		size = UDim2.new(0.8, 0, 0.08, 0),
		pos = UDim2.new(0.05, 0, 0.02, 0),
		font = F.TITLE,
		ts = isMobile and 20 or 24,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})
	TotemUI.Refs.Title = title

	Utils.mkBtn({
		name = "CloseBtn",
		text = "X",
		size = UDim2.new(0.12, 0, 0.07, 0),
		pos = UDim2.new(0.96, 0, 0.02, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		ts = 20,
		fn = function()
			UIManager.closeTotem()
		end,
		parent = window,
	})

	-- Info Group (Y: 0.11 ~ 0.45)
	local infoY = 0.11
	local infoGap = 0.055

	TotemUI.Refs.Status = Utils.mkLabel({
		text = "보호 상태: 확인 중",
		size = UDim2.new(0.9, 0, 0.05, 0),
		pos = UDim2.new(0.05, 0, infoY, 0),
		ts = 15,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.Remaining = Utils.mkLabel({
		text = "효과 유지 기간: --",
		size = UDim2.new(0.9, 0, 0.05, 0),
		pos = UDim2.new(0.05, 0, infoY + infoGap, 0),
		ts = 15,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.Radius = Utils.mkLabel({
		text = "보호 범위: -- x --",
		size = UDim2.new(0.9, 0, 0.05, 0),
		pos = UDim2.new(0.05, 0, infoY + infoGap*2, 0),
		ts = 15,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.Gold = Utils.mkLabel({
		text = "보유 골드: --",
		size = UDim2.new(0.9, 0, 0.05, 0),
		pos = UDim2.new(0.05, 0, infoY + infoGap*3, 0),
		ts = 15,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TotemUI.Refs.ExpandInfo = Utils.mkLabel({
		text = "확장 정보: 확인 중",
		size = UDim2.new(0.9, 0, 0.08, 0),
		pos = UDim2.new(0.05, 0, infoY + infoGap*4 + 0.01, 0),
		ts = 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})
	-- Raid Warning (Y: 0.46)
	local warningFrame = Utils.mkFrame({
		name = "RaidWarning",
		size = UDim2.new(0.9, 0, 0.08, 0),
		pos = UDim2.new(0.05, 0, 0.46, 0),
		bg = Color3.fromRGB(100, 25, 28),
		bgT = 0.2,
		stroke = 1,
		strokeC = Color3.fromRGB(210, 145, 140),
		vis = false,
		parent = window,
	})
	TotemUI.Refs.RaidWarning = warningFrame

	TotemUI.Refs.RaidWarningIcon = Utils.mkLabel({
		text = "⚠",
		size = UDim2.new(0, 30, 1, 0),
		pos = UDim2.new(0, 8, 0, 0),
		font = F.TITLE,
		ts = 20,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Center,
		parent = warningFrame,
	})

	TotemUI.Refs.RaidWarningText = Utils.mkLabel({
		text = "유지비 만료: 현재 약탈 가능 상태",
		size = UDim2.new(1, -44, 1, 0),
		pos = UDim2.new(0, 38, 0, 0),
		ts = 14,
		color = Color3.fromRGB(220, 215, 210),
		ax = Enum.TextXAlignment.Left,
		parent = warningFrame,
	})

	-- Action Buttons (Y: 0.58)
	local btnH = 0.075
	local btnY = 0.58

	Utils.mkBtn({
		text = "영역 확인",
		size = UDim2.new(0.44, 0, btnH, 0),
		pos = UDim2.new(0.05, 0, btnY, 0),
		bg = Color3.fromRGB(50, 90, 155),
		font = F.TITLE,
		ts = 15,
		fn = function()
			if currentUIManager and currentUIManager.highlightTotemZone then
				currentUIManager.highlightTotemZone()
			end
		end,
		parent = window,
	})

	Utils.mkBtn({
		text = "새로고침",
		size = UDim2.new(0.44, 0, btnH, 0),
		pos = UDim2.new(0.51, 0, btnY, 0),
		bg = C.BG_SLOT,
		font = F.TITLE,
		ts = 15,
		fn = function()
			if currentUIManager and currentUIManager.refreshTotem then
				currentUIManager.refreshTotem()
			end
		end,
		parent = window,
	})

	TotemUI.Refs.ExpandToggle = Utils.mkBtn({
		text = "영토 확장",
		size = UDim2.new(0.9, 0, btnH, 0),
		pos = UDim2.new(0.05, 0, btnY + btnH + 0.02, 0),
		bg = Color3.fromRGB(90, 120, 165),
		font = F.TITLE,
		ts = 15,
		fn = function()
			setExpandSelectionVisible(not expandSelectionVisible)
		end,
		parent = window,
	})

	local expandCards = Utils.mkFrame({
		name = "ExpandCardFrame",
		size = UDim2.new(0.6, 0, 0.6, 0),
		pos = UDim2.new(1.05, 0, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = Color3.fromRGB(30, 34, 42),
		bgT = 0.05,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER,
		vis = false,
		parent = window,
	})
	TotemUI.Refs.ExpandCardFrame = expandCards

	Utils.mkLabel({
		text = "확장 방향 선택",
		size = UDim2.new(0.9, 0, 0.1, 0),
		pos = UDim2.new(0.05, 0, 0.02, 0),
		ts = isMobile and 13 or 15,
		font = F.TITLE,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = expandCards,
	})

	TotemUI.Refs.ExpandNorth = Utils.mkBtn({
		text = "북쪽 확장",
		size = UDim2.new(0.9, 0, 0.18, 0),
		pos = UDim2.new(0.05, 0, 0.15, 0),
		bg = Color3.fromRGB(90, 120, 165),
		font = F.TITLE,
		ts = isMobile and 13 or 15,
		fn = function()
			setExpandSelectionVisible(false)
			if currentUIManager and currentUIManager.requestTotemExpand then
				currentUIManager.requestTotemExpand("NORTH")
			end
		end,
		parent = expandCards,
	})

	TotemUI.Refs.ExpandWest = Utils.mkBtn({
		text = "서쪽 확장",
		size = UDim2.new(0.44, 0, 0.18, 0),
		pos = UDim2.new(0.05, 0, 0.35, 0),
		bg = Color3.fromRGB(90, 120, 165),
		font = F.TITLE,
		ts = isMobile and 13 or 15,
		fn = function()
			setExpandSelectionVisible(false)
			if currentUIManager and currentUIManager.requestTotemExpand then
				currentUIManager.requestTotemExpand("WEST")
			end
		end,
		parent = expandCards,
	})

	TotemUI.Refs.ExpandEast = Utils.mkBtn({
		text = "동쪽 확장",
		size = UDim2.new(0.44, 0, 0.18, 0),
		pos = UDim2.new(0.51, 0, 0.35, 0),
		bg = Color3.fromRGB(90, 120, 165),
		font = F.TITLE,
		ts = isMobile and 13 or 15,
		fn = function()
			setExpandSelectionVisible(false)
			if currentUIManager and currentUIManager.requestTotemExpand then
				currentUIManager.requestTotemExpand("EAST")
			end
		end,
		parent = expandCards,
	})

	TotemUI.Refs.ExpandSouth = Utils.mkBtn({
		text = "남쪽 확장",
		size = UDim2.new(0.9, 0, 0.18, 0),
		pos = UDim2.new(0.05, 0, 0.55, 0),
		bg = Color3.fromRGB(90, 120, 165),
		font = F.TITLE,
		ts = isMobile and 13 or 15,
		fn = function()
			setExpandSelectionVisible(false)
			if currentUIManager and currentUIManager.requestTotemExpand then
				currentUIManager.requestTotemExpand("SOUTH")
			end
		end,
		parent = expandCards,
	})

	-- Upkeep Buttons (Y: 0.76 ~ 0.98)
	local costH = 0.07
	local costY = 0.76

	TotemUI.Refs.Cost1 = Utils.mkBtn({
		text = "1일 유지 ~ 100 Gold",
		size = UDim2.new(0.9, 0, costH, 0),
		pos = UDim2.new(0.05, 0, costY, 0),
		bg = C.GOLD,
		color = C.BG_DARK,
		font = F.TITLE,
		ts = 15,
		fn = function()
			if currentUIManager and currentUIManager.requestTotemPay then
				currentUIManager.requestTotemPay(1)
			end
		end,
		parent = window,
	})

	TotemUI.Refs.Cost3 = Utils.mkBtn({
		text = "3일 유지 ~ 280 Gold",
		size = UDim2.new(0.9, 0, costH, 0),
		pos = UDim2.new(0.05, 0, costY + costH + 0.01, 0),
		bg = C.GOLD,
		color = C.BG_DARK,
		font = F.TITLE,
		ts = 15,
		fn = function()
			if currentUIManager and currentUIManager.requestTotemPay then
				currentUIManager.requestTotemPay(3)
			end
		end,
		parent = window,
	})

	TotemUI.Refs.Cost7 = Utils.mkBtn({
		text = "7일 유지 ~ 630 Gold",
		size = UDim2.new(0.9, 0, costH, 0),
		pos = UDim2.new(0.05, 0, costY + (costH + 0.01) * 2, 0),
		bg = C.GOLD,
		color = C.BG_DARK,
		font = F.TITLE,
		ts = 15,
		fn = function()
			if currentUIManager and currentUIManager.requestTotemPay then
				currentUIManager.requestTotemPay(7)
			end
		end,
		parent = window,
	})

	ensureCountdownThread()
end

function TotemUI.SetVisible(visible)
	if TotemUI.Refs.Frame then
		TotemUI.Refs.Frame.Visible = visible
	end
	if not visible then
		setExpandSelectionVisible(false)
	end
end

function TotemUI.Refresh(info)
	if type(info) ~= "table" then
		return
	end
	latestInfo = info
	refreshLiveCountdown()
end

return TotemUI
