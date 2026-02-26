-- StatusUI.lua
-- 캐릭터 능력치 및 포인트 인터페이스 (Original Design)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local StatusUI = {}

StatusUI.Refs = {
	Frame = nil,
	StatPoints = nil,
	StatLines = {}, -- id -> {val, btn}
}

function StatusUI.SetVisible(visible)
	if StatusUI.Refs.Frame then
		StatusUI.Refs.Frame.Visible = visible
	end
end

function StatusUI.Refresh(cachedStats, Enums)
	local refs = StatusUI.Refs
	if not refs.Frame or not refs.Frame.Visible then return end
	
	local available = cachedStats.statPointsAvailable or 0
	if refs.StatPoints then
		refs.StatPoints.Text = "남은 강화 포인트: "..available
	end
	
	local calc = cachedStats.calculated or {}
	local invested = cachedStats.statInvested or {}
	
	for statId, line in pairs(refs.StatLines) do
		local valText = ""
		if statId == Enums.StatId.MAX_HEALTH then
			valText = string.format("%d HP", calc.maxHealth or 100)
		elseif statId == Enums.StatId.MAX_STAMINA then
			valText = string.format("%d STA", calc.maxStamina or 100)
		elseif statId == Enums.StatId.WEIGHT then
			valText = string.format("%.1f kg", calc.maxWeight or 300)
		elseif statId == Enums.StatId.WORK_SPEED then
			valText = string.format("%d%%", calc.workSpeed or 100)
		elseif statId == Enums.StatId.ATTACK then
			valText = string.format("%.0f%%", (calc.attackMult or 1.0) * 100)
		end
		
		line.val.Text = string.format("%s (Lv.%d)", valText, invested[statId] or 0)
		line.btn.Visible = (available > 0)
	end
end

function StatusUI.Init(parent, UIManager, NetClient, Enums)
	StatusUI.Refs.Frame = Utils.mkFrame({
		name = "Status",
		size = UDim2.new(0, 400, 0, 450),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 15,
		stroke = 2,
		vis = false,
		parent = parent
	})
	
	Utils.mkLabel({
		text = "능력치",
		size = UDim2.new(1, 0, 0, 50),
		ts = 22,
		bold = true,
		parent = StatusUI.Refs.Frame
	})

	-- Close Button
	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 30, 0, 30),
		pos = UDim2.new(1, -10, 0, 10),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		color = C.WHITE,
		ts = 20,
		fn = function() UIManager.closeStatus() end,
		parent = StatusUI.Refs.Frame
	})

	StatusUI.Refs.StatPoints = Utils.mkLabel({
		text = "보유 포인트: 0",
		size = UDim2.new(1, 0, 0, 30),
		pos = UDim2.new(0, 0, 0, 50),
		ts = 14,
		color = C.GOLD,
		parent = StatusUI.Refs.Frame
	})

	local list = Utils.mkFrame({
		size = UDim2.new(1, -40, 1, -120),
		pos = UDim2.new(0, 20, 0, 90),
		bgT = 1,
		parent = StatusUI.Refs.Frame
	})
	local vertical = Instance.new("UIListLayout")
	vertical.Padding = UDim.new(0, 10); vertical.Parent = list
	
	local stats = {
		{id = Enums.StatId.MAX_HEALTH, name = "최대 체력"},
		{id = Enums.StatId.MAX_STAMINA, name = "최대 스테미나"},
		{id = Enums.StatId.WEIGHT, name = "최대 무게"},
		{id = Enums.StatId.WORK_SPEED, name = "작업 속도"},
		{id = Enums.StatId.ATTACK, name = "공격력"},
	}
	
	for _, s in ipairs(stats) do
		local line = Utils.mkFrame({
			size = UDim2.new(1, 0, 0, 45),
			bg = C.BG_SLOT,
			bgT = 0.5,
			r = 8,
			parent = list
		})
		
		Utils.mkLabel({text = s.name, size = UDim2.new(0, 100, 1, 0), pos = UDim2.new(0, 15, 0, 0), ts = 14, ax = Enum.TextXAlignment.Left, parent = line})
		local val = Utils.mkLabel({name = "0", size = UDim2.new(0, 180, 1, 0), pos = UDim2.new(1, -220, 0, 0), ax = Enum.TextXAlignment.Right, parent = line})
		
		local btn = Utils.mkBtn({
			text = "+",
			size = UDim2.new(0, 35, 0, 35),
			pos = UDim2.new(1, -5, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			bg = C.GOLD_SEL,
			r = "full",
			ts = 18,
			vis = false,
			fn = function() NetClient.Request("Player.Stats.Upgrade.Request", {statId = s.id}) end,
			parent = line
		})
		
		StatusUI.Refs.StatLines[s.id] = {val = val, btn = btn}
	end
end

return StatusUI
