-- EquipmentUI.lua
-- 듀랑고 스타일 장비창 UI (E키)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local EquipmentUI = {}
EquipmentUI.Refs = {
	Frame = nil,
	Slots = {},
	Preview = nil,
	StatPanel = nil,
}

function EquipmentUI.SetVisible(visible)
	if EquipmentUI.Refs.Frame then
		EquipmentUI.Refs.Frame.Visible = visible
	end
end

function EquipmentUI.Init(parent, UIManager)
	EquipmentUI.Refs.Frame = Utils.mkFrame({
		name = "EquipmentMenu",
		size = UDim2.new(0.5, 0, 0.6, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.4,
		r = 8,
		stroke = 2,
		parent = parent
	})

	local slotPanel = Utils.mkFrame({name="SlotPanel", size=UDim2.new(0.6,0,0.7,0), bgT=1, parent=EquipmentUI.Refs.Frame})
	local previewPanel = Utils.mkFrame({name="PreviewPanel", size=UDim2.new(0.4,0,0.7,0), pos=UDim2.new(0.6,0,0,0), anchor=Vector2.new(0,0), bgT=1, parent=EquipmentUI.Refs.Frame})
	EquipmentUI.Refs.Preview = previewPanel

	-- 장비 슬롯 생성 (예: 머리, 몸, 손, 발, 악세서리)
	local slotNames = {"Head", "Body", "Hand", "Feet", "Accessory"}
	for i, name in ipairs(slotNames) do
		local slot = Utils.mkSlot({name=name, r=4, bgT=0.3, stroke=1, strokeC=C.BORDER_DIM, parent=slotPanel})
		slot.frame.LayoutOrder = i
		EquipmentUI.Refs.Slots[name] = slot
	end

	-- 하단 스탯 투자 UI
	EquipmentUI.Refs.StatPanel = Utils.mkFrame({name="StatPanel", size=UDim2.new(1,0,0.3,0), pos=UDim2.new(0,0,0.7,0), anchor=Vector2.new(0,0), bgT=1, parent=EquipmentUI.Refs.Frame})
	Utils.mkLabel({text="스탯 업그레이드", ts=18, bold=true, color=C.GOLD, parent=EquipmentUI.Refs.StatPanel})
	local statList = Instance.new("UIListLayout"); statList.Padding = UDim.new(0, 10); statList.Parent = EquipmentUI.Refs.StatPanel
	local stats = {{id="strength", name="가공력"}, {id="agility", name="기동성"}, {id="intelligence", name="통찰력"}, {id="stamina", name="지구력"}, {id="health", name="생존력"}}
	EquipmentUI.Refs.StatLines = {}
	for _, s in ipairs(stats) do
		local line = Utils.mkFrame({size=UDim2.new(1, -15, 0, 40), bg=C.BG_SLOT, bgT=0.5, r=8, parent=EquipmentUI.Refs.StatPanel})
		Utils.mkLabel({text=s.name, size=UDim2.new(0.4, 0, 1, 0), pos=UDim2.new(0, 10, 0, 0), ts=16, ax=Enum.TextXAlignment.Left, parent=line})
		local val = Utils.mkLabel({text="0", size=UDim2.new(0.2, 0, 1, 0), pos=UDim2.new(0.65, 0, 0, 0), ts=18, bold=true, parent=line})
		local btn = Utils.mkBtn({text="+", size=UDim2.new(0, 32, 0, 32), pos=UDim2.new(0.95, 0, 0.5, 0), anchor=Vector2.new(1, 0.5), bg=C.GOLD_SEL, r="full", fn=function() UIManager.upgradeStat(s.id) end, parent=line})
		EquipmentUI.Refs.StatLines[s.id] = {val=val, btn=btn}
	end
end

-- 실제 장비/스탯 데이터 연동
function EquipmentUI.Refresh(equipmentData, statData, getItemIcon)
	-- 장비 슬롯 표시
	local slots = EquipmentUI.Refs.Slots
	for name, slot in pairs(slots) do
		local item = equipmentData and equipmentData[name]
		if item then
			slot.icon.Image = getItemIcon(item.itemId)
			slot.icon.Visible = true
			slot.countLabel.Text = ""
		else
			slot.icon.Image = ""
			slot.icon.Visible = false
			slot.countLabel.Text = ""
		end
	end
	-- 스탯 값 표시
	if statData and EquipmentUI.Refs.StatLines then
		for statId, line in pairs(EquipmentUI.Refs.StatLines) do
			local val = statData[statId] or 0
			line.val.Text = tostring(val)
		end
	end
end

return EquipmentUI
