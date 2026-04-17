-- PortalUI.lua
-- 고대 포탈 골드 투입 UI (PortalRadialUI에서 호출)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)

local C = Theme.Colors
local F = Theme.Fonts

local PortalUI = {}
PortalUI.Refs = {}

local currentUIManager = nil
local statusData = nil

----------------------------------------------------------------
-- Init
----------------------------------------------------------------
function PortalUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager

	local window = Utils.mkWindow({
		name = "PortalGoldWindow",
		size = UDim2.new(0, 360, 0, 240),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.5,
		stroke = 1,
		strokeC = C.BORDER,
		vis = false,
		parent = parent,
	})
	PortalUI.Refs.Frame = window

	-- 제목
	PortalUI.Refs.Title = Utils.mkLabel({
		text = "포탈 활성화",
		size = UDim2.new(1, -70, 0, 40),
		pos = UDim2.new(0, 16, 0, 10),
		font = F.TITLE,
		ts = 20,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	-- 닫기 버튼
	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, -8, 0, 8),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		ts = 16,
		fn = function()
			PortalUI.SetVisible(false)
		end,
		parent = window,
	})

	-- 본문 영역
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(1, -32, 1, -80),
		pos = UDim2.new(0, 16, 0, 60),
		bgT = 1,
		parent = window,
	})
	PortalUI.Refs.Body = body

	-- 설명
	PortalUI.Refs.Desc = Utils.mkLabel({
		text = "포탈을 활성화하기 위해 골드가 필요합니다.",
		size = UDim2.new(1, 0, 0, 30),
		pos = UDim2.new(0, 0, 0, 0),
		ax = Enum.TextXAlignment.Left,
		ts = 14,
		color = C.INK,
		parent = body,
	})

	-- 골드 현황
	local goldProgressFrame = Utils.mkFrame({
		name = "GoldProgress",
		size = UDim2.new(1, 0, 0, 50),
		pos = UDim2.new(0, 0, 0, 40),
		bg = C.BG_DARK,
		bgT = 0.3,
		r = 4,
		parent = body,
	})
	
	PortalUI.Refs.GoldText = Utils.mkLabel({
		text = "0 / 0 Gold",
		size = UDim2.new(1, -20, 1, 0),
		pos = UDim2.new(0, 10, 0, 0),
		font = F.TITLE,
		ts = 18,
		color = C.GOLD,
		parent = goldProgressFrame,
	})

	-- 활성화 버튼
	PortalUI.Refs.BtnActivate = Utils.mkBtn({
		text = "골드 기부하기",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0, 0, 1, -40),
		bg = C.GOLD,
		color = C.BG_DARK,
		font = F.TITLE,
		ts = 16,
		fn = function()
			if statusData then
				local need = statusData.requiredGold - statusData.currentGold
				if need > 0 then
					currentUIManager.requestPortalDeposit(nil, need) -- itemId=nil은 골드 의미
				end
			end
		end,
		parent = body,
	})
end

----------------------------------------------------------------
-- Visibility
----------------------------------------------------------------
function PortalUI.SetVisible(visible)
	if PortalUI.Refs.Frame then
		 PortalUI.Refs.Frame.Visible = visible
	end
end

----------------------------------------------------------------
-- SetData
----------------------------------------------------------------
function PortalUI.SetData(data)
	statusData = data
	PortalUI.Refresh()
end

----------------------------------------------------------------
-- Refresh
----------------------------------------------------------------
function PortalUI.Refresh(newData)
	if newData then statusData = newData end
	if not statusData then return end

	if PortalUI.Refs.Title then
		PortalUI.Refs.Title.Text = statusData.displayName or "포탈 활성화"
	end

	if PortalUI.Refs.GoldText then
		PortalUI.Refs.GoldText.Text = string.format("%d / %d Gold", statusData.currentGold or 0, statusData.requiredGold or 0)
	end
	
	-- 이미 활성화된 경우 UI 닫기
	if statusData.repaired then
		PortalUI.SetVisible(false)
	end
end

return PortalUI
