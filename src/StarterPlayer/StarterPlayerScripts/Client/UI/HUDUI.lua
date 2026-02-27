-- HUDUI.lua
-- 완전히 재설계된 최상단/우측하단 HUD (Durango 레퍼런스 완벽 대응)

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local HUDUI = {}
local Controllers = script.Parent.Parent:WaitForChild("Controllers")

HUDUI.Refs = {
	harvestPct = nil,
	harvestName = nil,
	interactPrompt = nil,
}

function HUDUI.Init(parent, UIManager, InputManager)
	-- [Top Left Area] - HP, Stamina, Status Effects
	local topLeftFrame = Utils.mkFrame({
		name = "TopLeftHUD",
		size = UDim2.new(0, 240, 0, 100),
		pos = UDim2.new(0, 20, 0, 20),
		bgT = 1,
		parent = parent
	})
	HUDUI.Refs.statusPanel = topLeftFrame

	-- HP Bar
	HUDUI.Refs.healthBar = Utils.mkBar({
		name = "HP",
		size = UDim2.new(1, 0, 0, 16),
		pos = UDim2.new(0, 0, 0, 0),
		fillC = C.HP,
		r = 6,
		parent = topLeftFrame
	})
	local hpDecay = Utils.mkFrame({
		name = "Decay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(1, 1, 1),
		bgT = 0.5,
		r = 6,
		z = HUDUI.Refs.healthBar.fill.ZIndex - 1,
		parent = HUDUI.Refs.healthBar.container
	})
	HUDUI.Refs.hpDecay = hpDecay
	HUDUI.Refs.healthBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.healthBar.label.Position = UDim2.new(0, 5, 0, 0)
	HUDUI.Refs.healthBar.label.Text = "100 / 100"

	-- Stamina Bar
	HUDUI.Refs.staminaBar = Utils.mkBar({
		name = "STA",
		size = UDim2.new(1, 0, 0, 16), 
		pos = UDim2.new(0, 0, 0, 20),
		fillC = C.GOLD,
		r = 6,
		parent = topLeftFrame
	})
	local staDecay = Utils.mkFrame({
		name = "Decay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(1, 1, 1),
		bgT = 0.5,
		r = 6,
		z = HUDUI.Refs.staminaBar.fill.ZIndex - 1,
		parent = HUDUI.Refs.staminaBar.container
	})
	HUDUI.Refs.staDecay = staDecay
	HUDUI.Refs.staminaBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.staminaBar.label.Position = UDim2.new(0, 5, 0, 0)
	HUDUI.Refs.staminaBar.label.Text = "100 / 100"

	-- Status Effect Icons Container (under STA bar)
	local effectList = Utils.mkFrame({name="EffectList", size=UDim2.new(1,0,0,30), pos=UDim2.new(0,0,0,36), bgT=1, parent=topLeftFrame})
	local eLayout = Instance.new("UIListLayout"); eLayout.FillDirection=Enum.FillDirection.Horizontal; eLayout.Padding=UDim.new(0,5); eLayout.Parent=effectList
	
	HUDUI.Refs.statPointAlert = Utils.mkLabel({
		text = "▲ 레벨업 가능",
		size = UDim2.new(0, 120, 1, 0),
		ts = 12,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		vis = false,
		parent = effectList
	})

	-- [Bottom Right Area] - Action / Hexagon Buttons
	local actionArea = Utils.mkFrame({
		name = "ActionArea",
		size = UDim2.new(0, 240, 0, 120),
		pos = UDim2.new(1, -20, 1, -20),
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = parent
	})
	
	-- Hexagonal Buttons Data
	local hexBtns = {
		{id="Attack", icon="rbxassetid://10452331908", pos=UDim2.new(1, -70, 0.5, 20), size=90},
		{id="Interact", icon="rbxassetid://6034805332", pos=UDim2.new(1, -150, 0.5, 45), size=75},
		{id="Jump", icon="rbxassetid://6034335017", pos=UDim2.new(1, -220, 0.5, -5), size=60},
	}
	
	for _, hb in ipairs(hexBtns) do
		local btn = Utils.mkHexBtn({
			name = hb.id,
			size = UDim2.new(0, hb.size, 0, hb.size),
			pos = hb.pos,
			anchor = Vector2.new(0.5, 0.5),
			stroke = true,
			parent = actionArea
		})
		local iconLbl = Instance.new("ImageLabel")
		iconLbl.Size = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.AnchorPoint = Vector2.new(0.5, 0.5)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Image = hb.icon
		iconLbl.ImageColor3 = Color3.new(1,1,1)
		iconLbl.Parent = btn
		HUDUI.Refs["hex_"..hb.id] = btn
	end

	-- Interaction Prompt (Centered)
	HUDUI.Refs.interactPrompt = Utils.mkLabel({
		text = "",
		size = UDim2.new(0, 400, 0, 80),
		pos = UDim2.new(0.5, 0, 0.65, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 18,
		bold = true,
		color = C.WHITE,
		rich = true,
		vis = false,
		parent = parent
	})

	-- [Bottom Edge] - Experience Bar & Menu
	local bottomEdge = Utils.mkFrame({
		name = "BottomEdge",
		size = UDim2.new(1, 0, 0, 30),
		pos = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		bg = Color3.new(0,0,0),
		bgT = 0.3,
		parent = parent
	})
	
	local xpBackground = Utils.mkFrame({
		name = "XPBG", 
		size = UDim2.new(0.8, 0, 0, 4), 
		pos = UDim2.new(0.5, 0, 1, 0), 
		anchor = Vector2.new(0.5, 1), 
		bgT = 0.8, 
		bg = Color3.new(1, 1, 1), 
		maxSize = Vector2.new(1200, 4),
		parent = bottomEdge
	})
	HUDUI.Refs.xpBar = Utils.mkFrame({name = "XPBar", size = UDim2.new(0, 0, 1, 0), bg = C.XP, bgT = 0, parent = xpBackground})

	local bottomList = Instance.new("UIListLayout"); bottomList.FillDirection=Enum.FillDirection.Horizontal; bottomList.Padding=UDim.new(0, 15); bottomList.VerticalAlignment=Enum.VerticalAlignment.Center; bottomList.Parent=bottomEdge
	
	Utils.mkBtn({text="≡", size=UDim2.new(0,40,1,0), bgT=1, ts=24, color=C.WHITE, parent=bottomEdge})
	HUDUI.Refs.bagBtn = Utils.mkBtn({text="소지품(B)", size=UDim2.new(0,100,1,0), bgT=1, ts=14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleInventory() end, parent=bottomEdge})
	HUDUI.Refs.craftBtn = Utils.mkBtn({text="제작(C)", size=UDim2.new(0,80,1,0), bgT=1, ts=14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleCrafting() end, parent=bottomEdge})
	HUDUI.Refs.equipBtn = Utils.mkBtn({text="장비(E)", size=UDim2.new(0,80,1,0), bgT=1, ts=14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleEquipment() end, parent=bottomEdge})
	HUDUI.Refs.techBtn = Utils.mkBtn({text="기술(K)", size=UDim2.new(0,80,1,0), bgT=1, ts=14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleTechTree() end, parent=bottomEdge})

	HUDUI.Refs.levelLabel = Utils.mkLabel({text="Lv. 1    0.0%", size=UDim2.new(0, 150, 1, 0), ts=12, color=C.GRAY, parent=bottomEdge})

	-- [Hotbar] (Center Bottom)
	local hotbarFrame = Utils.mkFrame({
		name = "Hotbar",
		size = UDim2.new(0, 410, 0, 50),
		pos = UDim2.new(0.5, 0, 1, -35),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = parent
	})
	HUDUI.Refs.hotbarSlots = {}
	local hList = Instance.new("UIListLayout")
	hList.FillDirection = Enum.FillDirection.Horizontal; hList.HorizontalAlignment = Enum.HorizontalAlignment.Center; hList.Padding = UDim.new(0, 5); hList.Parent = hotbarFrame

	for i=1, 8 do
		local slot = Utils.mkSlot({
			name = "Slot"..i,
			size = UDim2.new(0, 45, 0, 45),
			bg = C.BG_SLOT,
			bgT = 0.4,
			stroke = 1,
			strokeC = C.BORDER_DIM,
			parent = hotbarFrame
		})
		
		-- Number indicator
		Utils.mkLabel({
			text = tostring(i),
			size = UDim2.new(0, 12, 0, 12),
			pos = UDim2.new(0, 2, 0, 2),
			ts = 10,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Left,
			ay = Enum.TextYAlignment.Top,
			st = 1,
			parent = slot.frame
		})
		
		HUDUI.Refs.hotbarSlots[i] = slot
	end

	-- Top Right: Minimap Placeholder (Not fully implemented, just visual)
	local minimap = Utils.mkFrame({
		name = "Minimap",
		size = UDim2.new(0, 120, 0, 120),
		pos = UDim2.new(1, -20, 0, 20),
		anchor = Vector2.new(1, 0),
		bgT = 0.5,
		r = "full",
		parent = parent
	})
	Utils.mkLabel({text="X: ???  Y: ???", pos=UDim2.new(0.5, 0, 1, 10), anchor=Vector2.new(0.5,0), size=UDim2.new(1,0,0,20), ts=12, color=C.WHITE, parent=minimap})

	-- Action Bindings Connect to Controller directly
	InputManager.bindAction("Interact", function() 
		local IC = require(Controllers.InteractController)
		if IC.interact then IC.interact() end
	end, true, "상호작용", Enum.KeyCode.Z)
	HUDUI.Refs.hex_Interact.MouseButton1Click:Connect(function() local IC = require(Controllers.InteractController); if IC.interact then IC.interact() end end)
	
	InputManager.bindAction("Attack", function()
		local CC = require(Controllers.CombatController)
		if CC.attack then CC.attack() end
	end, true, "공격", Enum.UserInputType.MouseButton1)
	HUDUI.Refs.hex_Attack.MouseButton1Click:Connect(function() local CC = require(Controllers.CombatController); if CC.attack then CC.attack() end end)

	InputManager.bindAction("Equipment", function() UIManager.toggleEquipment() end, true, "장비창", Enum.KeyCode.E)
	InputManager.bindAction("Character", function() UIManager.toggleInventory() end, true, "캐릭터", Enum.KeyCode.B, Enum.KeyCode.Tab, Enum.KeyCode.I)
	InputManager.bindAction("Building", function() UIManager.toggleCrafting("BUILDING") end, true, "건축", Enum.KeyCode.C)
	InputManager.bindAction("TechTree", function() UIManager.toggleTechTree() end, false, "기술", Enum.KeyCode.K)
	InputManager.bindAction("CloseUI", function()
		UIManager.closeInventory()
		UIManager.closeCrafting()
		UIManager.closeEquipment()
		UIManager.closeTechTree()
	end, false, nil, Enum.KeyCode.Escape)

	-- Harvest Setup
	HUDUI.Refs.harvestFrame = Utils.mkFrame({name="Harvest", size=UDim2.new(0, 300, 0, 60), pos=UDim2.new(0.4, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bgT=1, vis=false, parent=parent})
	local hBar = Utils.mkBar({size=UDim2.new(1, 0, 0, 6), pos=UDim2.new(0.5, 0, 0, 30), anchor=Vector2.new(0.5, 0), fillC=C.WHITE, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestBar = hBar.fill
	HUDUI.Refs.harvestName = Utils.mkLabel({text="채집 중...", size=UDim2.new(1, 0, 0, 25), ts=16, bold=true, rich=true, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestPct = Utils.mkLabel({text="0%", size=UDim2.new(1, 0, 0, 20), pos=UDim2.new(0.5, 0, 0, 45), anchor=Vector2.new(0.5, 0), ts=14, color=C.GOLD, parent=HUDUI.Refs.harvestFrame})
end

function HUDUI.SetVisible(visible)
	if HUDUI.Refs.statusPanel then HUDUI.Refs.statusPanel.Visible = visible end
	if HUDUI.Refs.xpBar then HUDUI.Refs.xpBar.Parent.Parent.Visible = visible end
	if HUDUI.Refs.hex_Attack then HUDUI.Refs.hex_Attack.Parent.Visible = visible end
end

function HUDUI.UpdateHealth(cur, max)
	local bar = HUDUI.Refs.healthBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.hpDecay then TweenService:Create(HUDUI.Refs.hpDecay, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
	bar.fill.BackgroundColor3 = r < 0.25 and C.RED or C.HP
end

function HUDUI.UpdateStamina(cur, max)
	local bar = HUDUI.Refs.staminaBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.staDecay then TweenService:Create(HUDUI.Refs.staDecay, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
end

function HUDUI.UpdateXP(cur, max)
	local bar = HUDUI.Refs.xpBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar, TweenInfo.new(0.3), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.levelLabel then 
		HUDUI.Refs.levelLabel.Text = string.format("Lv. %s    %.1f%%", tostring(HUDUI.Refs.currentLevel or 1), r * 100)
	end
end

function HUDUI.UpdateLevel(lv)
	HUDUI.Refs.currentLevel = lv
end

function HUDUI.SetStatPointAlert(available)
	if HUDUI.Refs.statPointAlert then
		HUDUI.Refs.statPointAlert.Visible = (available > 0)
	end
end

local harvestTween = nil
local harvestConn = nil

function HUDUI.ShowHarvestProgress(totalTime, targetName)
	local hf = HUDUI.Refs.harvestFrame
	if hf then
		hf.Visible = true
		if harvestTween then harvestTween:Cancel(); harvestTween = nil end
		if harvestConn then harvestConn:Disconnect(); harvestConn = nil end
		
		if HUDUI.Refs.harvestBar then HUDUI.Refs.harvestBar.Size = UDim2.new(0, 0, 1, 0) end
		if HUDUI.Refs.harvestName then HUDUI.Refs.harvestName.Text = targetName or "채집 중..." end
		if HUDUI.Refs.harvestPct then HUDUI.Refs.harvestPct.Text = "0%" end
		
		if type(totalTime) == "number" and totalTime > 0 then
			harvestTween = TweenService:Create(HUDUI.Refs.harvestBar, TweenInfo.new(totalTime, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)})
			harvestTween:Play()
			
			local start = tick()
			harvestConn = RunService.RenderStepped:Connect(function()
				local p = math.clamp((tick() - start) / totalTime, 0, 1)
				HUDUI.UpdateHarvestProgress(p)
			end)
		end
	end
end

function HUDUI.UpdateHarvestProgress(pct)
	if HUDUI.Refs.harvestBar then HUDUI.Refs.harvestBar.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0) end
	if HUDUI.Refs.harvestPct then HUDUI.Refs.harvestPct.Text = math.floor(pct * 100) .. "%" end
end

function HUDUI.HideHarvestProgress()
	if harvestTween then harvestTween:Cancel(); harvestTween = nil end
	if harvestConn then harvestConn:Disconnect(); harvestConn = nil end
	if HUDUI.Refs.harvestFrame then HUDUI.Refs.harvestFrame.Visible = false end
end

function HUDUI.showInteractPrompt(text)
	if HUDUI.Refs.interactPrompt then
		HUDUI.Refs.interactPrompt.Text = text
		HUDUI.Refs.interactPrompt.Visible = true
	end
end

function HUDUI.hideInteractPrompt()
	if HUDUI.Refs.interactPrompt then HUDUI.Refs.interactPrompt.Visible = false end
end

-- Compatibility wrappers just in case
function HUDUI.SelectHotbarSlot(idx, skipSync, UIManager, C)
	local slots = HUDUI.Refs.hotbarSlots
	if not slots then return end
	
	for i = 1, 8 do
		local s = slots[i]
		if not s then continue end
		local stroke = s.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			if i == idx then
				stroke.Color = C.GOLD_SEL
				stroke.Thickness = 2
			else
				stroke.Color = C.BORDER_DIM
				stroke.Thickness = 1
			end
		end
	end
end 

return HUDUI
