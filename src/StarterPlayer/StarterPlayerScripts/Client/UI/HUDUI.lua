-- HUDUI.lua
-- HUD, Hotbar, Harvest Progress 및 전역 액션 바인딩 관리 (Original Design)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local HUDUI = {}
local Controllers = script.Parent.Parent:WaitForChild("Controllers")

-- State refs
HUDUI.Refs = {
	harvestPct = nil,
	harvestName = nil,
	interactPrompt = nil,
}

function HUDUI.Init(parent, UIManager, InputManager)
	-- Top Left: HP / Stamina (Durango Style - Shorter & Numerical)
	local statusPanel = Utils.mkFrame({
		name = "StatusPanel",
		size = UDim2.new(0, 240, 0, 80), 
		pos = UDim2.new(0, 20, 0, 20),
		bgT = 1,
		parent = parent
	})
	HUDUI.Refs.statusPanel = statusPanel
	
	HUDUI.Refs.healthBar = Utils.mkBar({
		name = "HP",
		size = UDim2.new(1, 0, 0, 14),
		pos = UDim2.new(0, 0, 0, 5),
		fillC = C.HP,
		parent = statusPanel
	})
	-- Decay bar (behind)
	local hpDecay = Instance.new("Frame")
	hpDecay.Name = "Decay"; hpDecay.Size = UDim2.new(1, 0, 1, 0); hpDecay.BackgroundColor3 = Color3.new(1, 1, 1); hpDecay.BackgroundTransparency = 0.5; hpDecay.BorderSizePixel = 0; hpDecay.ZIndex = HUDUI.Refs.healthBar.fill.ZIndex - 1; hpDecay.Parent = HUDUI.Refs.healthBar.container
	HUDUI.Refs.hpDecay = hpDecay

	HUDUI.Refs.healthBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.healthBar.label.Position = UDim2.new(0, 5, 0, 0)
	HUDUI.Refs.healthBar.label.Text = "100/100"
	
	HUDUI.Refs.staminaBar = Utils.mkBar({
		name = "STA",
		size = UDim2.new(1, 0, 0, 14), 
		pos = UDim2.new(0, 0, 0, 25),
		fillC = C.STA, -- Now Yellow
		parent = statusPanel
	})
	local staDecay = Instance.new("Frame")
	staDecay.Name = "Decay"; staDecay.Size = UDim2.new(1, 0, 1, 0); staDecay.BackgroundColor3 = Color3.new(1, 1, 1); staDecay.BackgroundTransparency = 0.5; staDecay.BorderSizePixel = 0; staDecay.ZIndex = HUDUI.Refs.staminaBar.fill.ZIndex - 1; staDecay.Parent = HUDUI.Refs.staminaBar.container
	HUDUI.Refs.staDecay = staDecay

	HUDUI.Refs.staminaBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.staminaBar.label.Position = UDim2.new(0, 5, 0, 0)
	HUDUI.Refs.staminaBar.label.Text = "100/100"

	HUDUI.Refs.statPointAlert = Utils.mkLabel({
		text = "[+] 스탯 포인트",
		size = UDim2.new(0, 120, 0, 20),
		pos = UDim2.new(0, 0, 0, 45),
		ts = 12,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		vis = false,
		parent = statusPanel
	})

	-- Bottom Experience Bar: Full width (Left to Right)
	local xpContainer = Utils.mkFrame({
		name = "XPContainer",
		size = UDim2.new(1, 0, 0, 6),
		pos = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		bg = Color3.new(0, 0, 0),
		bgT = 0.5,
		parent = parent
	})
	HUDUI.Refs.xpContainer = xpContainer
	
	HUDUI.Refs.xpBar = Utils.mkBar({
		name = "XP",
		size = UDim2.new(1, 0, 1, 0),
		bgT = 1,
		fillC = C.XP,
		parent = xpContainer
	})
	if HUDUI.Refs.xpBar.label then HUDUI.Refs.xpBar.label.Visible = false end

	HUDUI.Refs.levelLabel = Utils.mkLabel({
		text = "Lv. 1",
		size = UDim2.new(0, 100, 0, 20),
		pos = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		font = F.NUM,
		color = C.WHITE,
		ts = 13,
		parent = parent
	})

	-- Harvest Progress
	HUDUI.Refs.harvestFrame = Utils.mkFrame({
		name = "Harvest",
		size = UDim2.new(0.4, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0.45, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgT = 1,
		vis = false,
		parent = parent
	})
	local hBar = Utils.mkBar({
		size = UDim2.new(0.6, 0, 0, 4),
		pos = UDim2.new(0.5, 0, 0, 25),
		anchor = Vector2.new(0.5, 0),
		fillC = C.WHITE,
		parent = HUDUI.Refs.harvestFrame
	})
	HUDUI.Refs.harvestBar = hBar.fill
	HUDUI.Refs.harvestName = Utils.mkLabel({text = "채집 중...", size = UDim2.new(1, 0, 0, 20), ts = 14, parent = HUDUI.Refs.harvestFrame})

	-- Interaction Prompt
	HUDUI.Refs.interactPrompt = Utils.mkLabel({
		text = "",
		size = UDim2.new(0, 400, 0, 60),
		pos = UDim2.new(0.5, 0, 0.65, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 18,
		bold = true,
		color = C.WHITE,
		vis = false,
		parent = parent
	})

	-- Hotbar: Centered Bottom
	local hbContainer = Utils.mkFrame({
		name = "Hotbar",
		size = UDim2.new(0, 480, 0, 65),
		pos = UDim2.new(0.5, 0, 1, -45),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = parent
	})
	local hbList = Instance.new("UIListLayout")
	hbList.FillDirection = Enum.FillDirection.Horizontal; hbList.HorizontalAlignment = Enum.HorizontalAlignment.Center; hbList.Padding = UDim.new(0, 8); hbList.Parent = hbContainer
	
	HUDUI.Refs.hotbarSlots = {}
	for i=1, 8 do
		local slot = Utils.mkSlot({
			name = "HB"..i,
			size = UDim2.new(0, 50, 0, 50),
			r = 6,
			stroke = 1.2,
			bgT = 0.4,
			parent = hbContainer
		})
		Utils.mkLabel({text = tostring(i), size = UDim2.new(0, 15, 0, 15), pos = UDim2.new(0, 4, 0, 4), ts = 9, font = F.NUM, ax = Enum.TextXAlignment.Left, parent = slot.frame})
		slot.click.MouseButton1Click:Connect(function() UIManager.selectHotbarSlot(i) end)
		HUDUI.Refs.hotbarSlots[i] = slot
	end
	
	-- Bottom Left: Utilities (Hamburger, Chat, etc.)
	local utilMenu = Utils.mkFrame({
		name = "UtilMenu",
		size = UDim2.new(0, 300, 0, 40),
		pos = UDim2.new(0, 20, 1, -20),
		anchor = Vector2.new(0, 1),
		bgT = 1,
		parent = parent
	})
	local utilList = Instance.new("UIListLayout"); utilList.FillDirection = Enum.FillDirection.Horizontal; utilList.Padding = UDim.new(0, 15); utilList.VerticalAlignment = Enum.VerticalAlignment.Center; utilList.Parent = utilMenu
	
	local utils = {
		{name="Menu", icon="rbxassetid://6031068426"}, -- Hamburger
		{name="Social", icon="rbxassetid://6034335017"}, 
		{name="Chat", icon="rbxassetid://6034290209"},
		{name="Keyboard", icon="rbxassetid://6031234604"}
	}
	for _, u in ipairs(utils) do
		local ub = Utils.mkBtn({size=UDim2.new(0, 32, 0, 32), bgT=1, parent=utilMenu})
		local ui = Instance.new("ImageLabel"); ui.Size=UDim2.new(0.8,0,0.8,0); ui.Position=UDim2.new(0.5,0,0.5,0); ui.AnchorPoint=Vector2.new(0.5,0.5); ui.BackgroundTransparency=1; ui.Image=u.icon; ui.ImageColor3=C.WHITE; ui.Parent=ub
	end

	-- Right-side Action Buttons (Hexagonal placeholders)
	local actionBar = Utils.mkFrame({
		name = "ActionBar",
		size = UDim2.new(0, 200, 0, 200),
		pos = UDim2.new(1, -20, 1, -120),
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = parent
	})
	
	local quickActions = {
		{name = "Equipment", text = "E 장비창", pos = UDim2.new(0, 0, 0.5, 0), fn = function() UIManager.toggleEquipment() end},
		{name = "Build", text = "C 건축", pos = UDim2.new(0.5, 0, 0.8, 0), fn = function() UIManager.toggleCrafting("BUILDING") end},
		{name = "Tech", text = "K 기술", pos = UDim2.new(0.5, 0, 0.2, 0), fn = function() UIManager.toggleTechTree() end}
	}

	for _, cfg in ipairs(quickActions) do
		local b = Utils.mkBtn({
			name = cfg.name,
			size = UDim2.new(0, 70, 0, 70),
			pos = cfg.pos,
			bg = C.BG_PANEL,
			bgT = 0.4,
			r = "full", -- Hexagon replacement with clean circles
			stroke = 2,
			strokeC = C.WHITE,
			fn = cfg.fn,
			parent = actionBar
		})
		Utils.mkLabel({text = cfg.text, size = UDim2.new(1, 0, 1, 0), ts = 12, bold = true, parent = b})
	end

	-- Action Bindings
	InputManager.bindAction("Interact", function() 
		local IC = require(Controllers.InteractController)
		if IC.interact then IC.interact() end
	end, true, "상호작용", Enum.KeyCode.Z) -- Remove E from here to use for Character
	
	InputManager.bindAction("Attack", function()
		local CC = require(Controllers.CombatController)
		if CC.attack then CC.attack() end
	end, true, "공격", Enum.UserInputType.MouseButton1)

	InputManager.bindAction("Equipment", function() UIManager.toggleEquipment() end, true, "장비창", Enum.KeyCode.E)
	InputManager.bindAction("Character", function() UIManager.toggleInventory() end, true, "캐릭터", Enum.KeyCode.I, Enum.KeyCode.Tab, Enum.KeyCode.B)
	InputManager.bindAction("Building", function() UIManager.toggleCrafting("BUILDING") end, true, "건축", Enum.KeyCode.C)
	InputManager.bindAction("TechTree", function() UIManager.toggleTechTree() end, false, "기술", Enum.KeyCode.K)
	
	InputManager.bindAction("CloseUI", function()
		UIManager.closeInventory()
		UIManager.closeCrafting()
		UIManager.closeShop()
		UIManager.closeTechTree()
		UIManager.closeStatus()
	end, false, nil, Enum.KeyCode.Escape)

	-- 1-8 Hotkeys
	local keys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight}
	for i, key in ipairs(keys) do
		InputManager.bindAction("SelectSlot"..i, function() UIManager.selectHotbarSlot(i) end, false, nil, key)
	end
end

function HUDUI.SetVisible(visible)
	if HUDUI.Refs.hotbarSlots[1] then
		HUDUI.Refs.hotbarSlots[1].frame.Parent.Visible = visible
	end
	if HUDUI.Refs.statusPanel then HUDUI.Refs.statusPanel.Visible = visible end
	if HUDUI.Refs.xpContainer then HUDUI.Refs.xpContainer.Visible = visible end
	if HUDUI.Refs.levelLabel then HUDUI.Refs.levelLabel.Visible = visible end
	if HUDUI.Refs.infoPanel then HUDUI.Refs.infoPanel.Visible = visible end
end

function HUDUI.UpdateHealth(cur, max)
	local bar = HUDUI.Refs.healthBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	
	-- 메인 바 애니메이션
	TweenService:Create(bar.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	-- 감쇠 바 (하얀색) 애니메이션 (약간 늦게 따라옴)
	if HUDUI.Refs.hpDecay then
		TweenService:Create(HUDUI.Refs.hpDecay, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	end
	
	bar.label.Text = string.format("%d/%d", math.floor(cur), math.floor(max))
	bar.fill.BackgroundColor3 = r < 0.25 and C.RED or C.HP
end

function HUDUI.UpdateStamina(cur, max)
	local bar = HUDUI.Refs.staminaBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	
	TweenService:Create(bar.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.staDecay then
		TweenService:Create(HUDUI.Refs.staDecay, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	end
	
	bar.label.Text = string.format("%d/%d", math.floor(cur), math.floor(max))
end

function HUDUI.UpdateXP(cur, max)
	local bar = HUDUI.Refs.xpBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.3), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	bar.label.Text = string.format("%d/%d XP", math.floor(cur), math.floor(max))
end

function HUDUI.UpdateLevel(lv)
	if HUDUI.Refs.levelLabel then 
		HUDUI.Refs.levelLabel.Text = "Lv. " .. tostring(lv) 
	end
end

function HUDUI.SetStatPointAlert(available)
	if HUDUI.Refs.statPointAlert then
		HUDUI.Refs.statPointAlert.Visible = (available > 0)
	end
end

function HUDUI.SelectHotbarSlot(idx, skipSync, UIManager, C)
	for i, slot in ipairs(HUDUI.Refs.hotbarSlots) do
		local stroke = slot.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			if i == idx then
				stroke.Color = C.GOLD
				stroke.Thickness = 2.5
			else
				stroke.Color = C.BORDER or Color3.new(1,1,1)
				stroke.Thickness = 1.5
			end
		end
	end
end

function HUDUI.ShowHarvestProgress(totalTime, targetName)
	local hf = HUDUI.Refs.harvestFrame
	if hf then
		hf.Visible = true
		if HUDUI.Refs.harvestBar then HUDUI.Refs.harvestBar.Size = UDim2.new(0, 0, 1, 0) end
		if HUDUI.Refs.harvestName then HUDUI.Refs.harvestName.Text = targetName or "채집 중..." end
		if HUDUI.Refs.harvestPct then HUDUI.Refs.harvestPct.Text = "0%" end
	end
end

function HUDUI.UpdateHarvestProgress(pct)
	if HUDUI.Refs.harvestBar then
		HUDUI.Refs.harvestBar.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
	end
	if HUDUI.Refs.harvestPct then
		HUDUI.Refs.harvestPct.Text = math.floor(pct * 100) .. "%"
	end
end

function HUDUI.HideHarvestProgress()
	if HUDUI.Refs.harvestFrame then
		HUDUI.Refs.harvestFrame.Visible = false
	end
end

function HUDUI.showInteractPrompt(text)
	if HUDUI.Refs.interactPrompt then
		HUDUI.Refs.interactPrompt.Text = text
		HUDUI.Refs.interactPrompt.Visible = true
	end
end

function HUDUI.hideInteractPrompt()
	if HUDUI.Refs.interactPrompt then
		HUDUI.Refs.interactPrompt.Visible = false
	end
end

return HUDUI
