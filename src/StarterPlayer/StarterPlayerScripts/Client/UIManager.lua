-- UIManager.lua
-- WildForge UI — 듀랑고 스타일 레퍼런스 기반
-- HUD(우측) + 원형슬롯 인벤토리 + 풀스크린 제작 + 채집바(상단)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local UI_SCALE = isMobile and 1.4 or 1.0

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local DataHelper = require(Shared.Util.DataHelper)

local Client = script.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)

local Controllers = Client:WaitForChild("Controllers")
local InventoryController = require(Controllers.InventoryController)
local ShopController = require(Controllers.ShopController)
local BuildController = require(Controllers.BuildController)
local TechController = require(Controllers.TechController)

local UIManager = {}

----------------------------------------------------------------
-- 컬러 팔레트 (어두운 미니멀 톤)
----------------------------------------------------------------
local C = {
	BG_OVERLAY    = Color3.fromRGB(0, 0, 0),
	BG_PANEL      = Color3.fromRGB(22, 22, 28),
	BG_PANEL_L    = Color3.fromRGB(32, 32, 38),
	BG_SLOT       = Color3.fromRGB(42, 42, 50),
	BG_SLOT_HOVER = Color3.fromRGB(58, 58, 66),
	BG_SLOT_SEL   = Color3.fromRGB(70, 70, 78),
	BG_BAR        = Color3.fromRGB(28, 28, 34),

	BORDER        = Color3.fromRGB(72, 72, 80),
	BORDER_SEL    = Color3.fromRGB(210, 210, 215),

	HP            = Color3.fromRGB(210, 48, 48),
	HP_BG         = Color3.fromRGB(58, 16, 16),
	STA           = Color3.fromRGB(230, 178, 42),
	STA_BG        = Color3.fromRGB(62, 52, 14),
	HARVEST       = Color3.fromRGB(60, 200, 60),
	HARVEST_BG    = Color3.fromRGB(18, 52, 18),
	XP            = Color3.fromRGB(72, 168, 230),
	XP_BG         = Color3.fromRGB(18, 42, 62),

	WHITE         = Color3.fromRGB(235, 235, 240),
	GRAY          = Color3.fromRGB(165, 165, 172),
	DIM           = Color3.fromRGB(100, 100, 110),
	GOLD          = Color3.fromRGB(255, 210, 80),
	GREEN         = Color3.fromRGB(100, 220, 100),
	RED           = Color3.fromRGB(255, 72, 72),

	BTN           = Color3.fromRGB(55, 55, 62),
	BTN_H         = Color3.fromRGB(78, 78, 86),
	BTN_CRAFT     = Color3.fromRGB(52, 128, 62),
	BTN_CRAFT_H   = Color3.fromRGB(68, 155, 78),
	BTN_CLOSE     = Color3.fromRGB(178, 42, 42),
	BTN_DIS       = Color3.fromRGB(42, 42, 48),

	NODE          = Color3.fromRGB(36, 36, 44),
	NODE_BD       = Color3.fromRGB(88, 88, 98),
	NODE_SEL      = Color3.fromRGB(180, 140, 58),
	LOCK          = Color3.fromRGB(140, 140, 148),
	
	BG_CRAFT_TOOLTIP = Color3.fromRGB(15, 15, 20),
	PROGRESS_FILL    = Color3.fromRGB(100, 220, 100),
}

local F = {
	TITLE  = Enum.Font.GothamBold,
	NORMAL = Enum.Font.Gotham,
	NUM    = Enum.Font.GothamMedium,
}

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local initialized = false
local mainGui

-- HUD refs
local healthBar, staminaBar, xpBar, levelLabel, statPointAlert

-- Hotbar
local hotbarFrame
local hotbarSlots = {}
local selectedSlot = 1

-- Panels
local inventoryFrame, statusFrame, craftingOverlay, shopFrame, techOverlay, interactPrompt
local actionContainer, hotbarFrame -- Store refs for visibility control
local craftDetailPanel, progFill, craftSpinner
local isInvOpen, isStatusOpen, isCraftOpen, isShopOpen, isTechOpen = false, false, false, false, false

-- 0. UI 관리 헬퍼
local function closeAllWindows(except)
	if isInvOpen and except ~= "INV" then UIManager.closeInventory() end
	if isStatusOpen and except ~= "STATUS" then UIManager.closeStatus() end
	if isCraftOpen and except ~= "CRAFT" then UIManager.closeCrafting() end
	if isShopOpen and except ~= "SHOP" then UIManager.closeShop() end
	if isTechOpen and except ~= "TECH" then UIManager.closeTechTree() end
end

function UIManager._setMainHUDVisible(visible)
	if hotbarFrame then hotbarFrame.Visible = visible end
	if actionContainer then actionContainer.Visible = visible end
	local hud = mainGui:FindFirstChild("HUD")
	if hud then hud.Visible = visible end
	local hP = mainGui:FindFirstChild("Harvest")
	if hP then hP.Visible = (visible and hP.Visible or false) end
end

-- Harvest progress
local harvestFrame, harvestBar, harvestPctLabel, harvestNameLabel

-- Inventory
local invSlots = {}
local invDetailPanel
local selectedInvSlot = nil
local categoryButtons = {}

-- Crafting / Building
local craftNodes = {}
local selectedRecipeId = nil
local selectedFacilityId = nil
local craftDetailPanel
local buildPromptFrame
local blurEffect
local menuMode = "CRAFTING" -- "CRAFTING" or "BUILDING"
local activeStructureId = nil -- 현재 사용 중인 작업대 ID
local activeFacilityId = nil
local cachedStats = {}
local statsPanel
local statLines = {}

-- Tech Tree
local techNodes = {}
local selectedTechId = nil
local techLines = {} -- 연결선용

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function mkFrame(p)
	local f = Instance.new("Frame")
	f.Name = p.name or "F"
	-- Responsive size scaling
	if p.size and not p.noScale then
		f.Size = p.size
	else
		f.Size = p.size or UDim2.new(0, 100 * UI_SCALE, 0, 100 * UI_SCALE)
	end
	f.Position = p.pos or UDim2.new(0,0,0,0)
	f.AnchorPoint = p.anchor or Vector2.zero
	f.BackgroundColor3 = p.bg or C.BG_PANEL
	f.BackgroundTransparency = p.bgT or 0
	f.BorderSizePixel = 0
	f.Visible = p.vis ~= false
	f.ZIndex = p.z or 1
	f.Parent = p.parent
	if p.r then
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, p.r); c.Parent = f
	end
	if p.stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = p.stroke
		s.Color = p.strokeC or C.BORDER
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end
	return f
end

local function mkLabel(p)
	local l = Instance.new("TextLabel")
	l.Name = p.name or "L"
	l.Size = p.size or UDim2.new(1,0,1,0)
	l.Position = p.pos or UDim2.new(0,0,0,0)
	l.AnchorPoint = p.anchor or Vector2.zero
	l.BackgroundTransparency = 1
	l.Text = p.text or ""
	l.TextColor3 = p.color or C.GRAY
	l.TextSize = p.ts or 14
	l.Font = p.font or F.NORMAL
	l.TextXAlignment = p.ax or Enum.TextXAlignment.Center
	l.TextYAlignment = p.ay or Enum.TextYAlignment.Center
	l.TextStrokeTransparency = 0.7
	l.TextStrokeColor3 = Color3.new(0,0,0)
	l.TextWrapped = p.wrap or false
	l.ZIndex = p.z or 1
	l.Parent = p.parent
	return l
end

local function mkBtn(p)
	local b = Instance.new("TextButton")
	b.Name = p.name or "B"
	if p.size and not p.noScale then
		b.Size = p.size
	else
		b.Size = p.size or UDim2.new(0, 100 * UI_SCALE, 0, 36 * UI_SCALE)
	end
	b.Position = p.pos or UDim2.new(0,0,0,0)
	b.AnchorPoint = p.anchor or Vector2.zero
	b.BackgroundColor3 = p.bg or C.BTN
	b.BorderSizePixel = 0
	b.Text = p.text or ""
	b.TextColor3 = p.color or C.WHITE
	b.TextSize = p.ts or 14
	b.Font = p.font or F.NORMAL
	b.AutoButtonColor = false
	b.TextStrokeTransparency = 0.7
	b.TextStrokeColor3 = Color3.new(0,0,0)
	b.ZIndex = p.z or 1
	b.Parent = p.parent
	if p.r then
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, p.r); c.Parent = b
	end
	local nc, hc = p.bg or C.BTN, p.hbg or C.BTN_H
	b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3=hc}):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3=nc}):Play() end)
	if p.fn then b.MouseButton1Click:Connect(p.fn) end
	return b
end

-- 둥근 사각형 아이템 슬롯 (이전 mkCircle)
local function mkSlot(p)
	local sz = p.sz or 50
	local baseR = 6
	local slot = mkFrame({name=p.name or "S", size=(p.sz == 1 and UDim2.new(1,0,1,0) or UDim2.new(0,sz,0,sz)), pos=p.pos, bg=C.BG_SLOT, r=baseR, stroke=1.5, strokeC=C.BORDER, z=p.z or 1, parent=p.parent})
	
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1; ar.Parent = slot

	local icon = Instance.new("ImageLabel")
	icon.Name="Icon"; icon.Size=UDim2.new(0.8,0,0.8,0); icon.Position=UDim2.new(0.5,0,0.5,0); icon.AnchorPoint=Vector2.new(0.5,0.5)
	icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=(p.z or 1)+1; icon.Parent=slot
	local nm = mkLabel({name="Nm", size=UDim2.new(0.9,0,0.3,0), pos=UDim2.new(0.05,0,0.05,0), text="", ts=7, color=C.WHITE, wrap=true, vis=not isMobile, z=(p.z or 1)+2, parent=slot})
	local ct = mkLabel({name="Ct", size=UDim2.new(0.9,0,0.25,0), pos=UDim2.new(0,0,1,-2), anchor=Vector2.new(0,1), text="", ts=11, font=F.NUM, color=C.WHITE, ax=Enum.TextXAlignment.Right, ay=Enum.TextYAlignment.Bottom, z=(p.z or 1)+10, parent=slot})
	local cb = Instance.new("TextButton")
	cb.Name="CB"; cb.Size=UDim2.new(1,0,1,0); cb.BackgroundTransparency=1; cb.Text=""; cb.ZIndex=(p.z or 1)+15; cb.Parent=slot
	local cr = Instance.new("UICorner"); cr.CornerRadius=UDim.new(0,baseR); cr.Parent=cb
	return {frame=slot, icon=icon, nameLabel=nm, countLabel=ct, click=cb}
end

-- 상태바 (HP/STA/XP)
local function mkBar(p)
	local container = mkFrame({name=p.name, size=p.size, pos=p.pos, bg=p.bgC or C.HP_BG, r=p.barR or 4, z=p.z or 1, parent=p.parent})
	if p.stroke then
		local s = Instance.new("UIStroke"); s.Thickness=p.stroke; s.Color=C.BORDER; s.Parent=container
	end
	local fill = mkFrame({name="Fill", size=UDim2.new(1,0,1,0), bg=p.fillC or C.HP, r=p.barR or 4, z=(p.z or 1), parent=container})
	local lbl = mkLabel({name="V", text=p.text or "", ts=p.labelTs or 11, font=F.NUM, z=(p.z or 1)+1, parent=container})
	return {fill=fill, label=lbl, container=container}
end

----------------------------------------------------------------
-- 1. HUD — 우측 상단 (HP / STA / XP / Level)
----------------------------------------------------------------
local function createHUD()
	local hudW = isMobile and 0.22 or 0.15
	local hudH = isMobile and 0.12 or 0.08
	local hud = mkFrame({name="HUD", size=UDim2.new(hudW,0,hudH,0), pos=UDim2.new(1,-10,0,10), anchor=Vector2.new(1,0), bg=C.BG_OVERLAY, bgT=0.55, r=8, parent=mainGui})
	
	-- Use UIAspectRatioConstraint to keep HUD consistent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.1
	aspect.Parent = hud

	-- HP
	healthBar = mkBar({name="HP", size=UDim2.new(1,-16,0.25,0), pos=UDim2.new(0,8,0.1,0), bgC=C.HP_BG, fillC=C.HP, barR=4, stroke=1, text="100/100", labelTs=isMobile and 12 or 10, z=2, parent=hud})
	mkLabel({name="Ic", size=UDim2.new(0,18,0,20), pos=UDim2.new(0,10,0.1,0), text="❤", ts=isMobile and 14 or 11, ax=Enum.TextXAlignment.Left, z=4, parent=hud})
	-- STA
	staminaBar = mkBar({name="STA", size=UDim2.new(1,-16,0.18,0), pos=UDim2.new(0,8,0.4,0), bgC=C.STA_BG, fillC=C.STA, barR=3, text="100/100", labelTs=isMobile and 10 or 9, z=2, parent=hud})
	-- XP
	xpBar = mkBar({name="XP", size=UDim2.new(1,-16,0.14,0), pos=UDim2.new(0,8,0.65,0), bgC=C.XP_BG, fillC=C.XP, barR=3, text="0/100 XP", labelTs=isMobile and 8 or 7, z=2, parent=hud})
	xpBar.fill.Size = UDim2.new(0,0,1,0)
	-- Level
	levelLabel = mkLabel({name="Lv", size=UDim2.new(0.4,0,0.15,0), pos=UDim2.new(0,8,0.82,0), text="Lv. 1", ts=isMobile and 12 or 11, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, z=2, parent=hud})
	statPointAlert = mkLabel({name="SPAlert", size=UDim2.new(0,100,0,14), pos=UDim2.new(0.4,0,0.82,0), text="[+] 포인트 있음", ts=isMobile and 11 or 10, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, vis=false, z=2, parent=hud})
end

----------------------------------------------------------------
-- 2. 채집 진행바 — 상단 중앙 (참조: 초록바 + % + 대상명)
----------------------------------------------------------------
local function createHarvestProgress()
	local HW = isMobile and 0.4 or 0.25
	local HH = isMobile and 0.08 or 0.06
	harvestFrame = mkFrame({name="Harvest", size=UDim2.new(HW,0,HH,0), pos=UDim2.new(0.5,0,0,32), anchor=Vector2.new(0.5,0), bg=C.BG_OVERLAY, bgT=0.45, r=6, vis=false, z=20, parent=mainGui})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 4.5; aspect.Parent = harvestFrame

	local barBg = mkFrame({name="BarBg", size=UDim2.new(0.95,0,0.45,0), pos=UDim2.new(0.5,0,0.2,0), anchor=Vector2.new(0.5,0), bg=C.HARVEST_BG, r=4, stroke=1.2, strokeC=Color3.fromRGB(120,120,128), z=21, parent=harvestFrame})
	harvestBar = mkFrame({name="Bar", size=UDim2.new(0,0,1,0), bg=C.HARVEST, r=4, z=22, parent=barBg})
	harvestPctLabel = mkLabel({name="Pct", text="0%", ts=isMobile and 14 or 12, font=F.TITLE, color=C.WHITE, z=23, parent=barBg})
	harvestNameLabel = mkLabel({name="Name", size=UDim2.new(1,0,0.3,0), pos=UDim2.new(0,0,0.7,0), text="", ts=isMobile and 12 or 10, color=C.GRAY, z=21, parent=harvestFrame})
end

----------------------------------------------------------------
-- 3. 핫바 — 하단 중앙, 원형 슬롯
----------------------------------------------------------------
local function createHotbar()
	local SZ, PAD, N = isMobile and 64 or 52, 7, 8
	local W = N*SZ + (N-1)*PAD
	hotbarFrame = mkFrame({name="Hotbar", size=UDim2.new(0,W+16,0,SZ+16), pos=UDim2.new(0.5,0,1,isMobile and -60 or -8), anchor=Vector2.new(0.5,1), bgT=1, parent=mainGui})
	
	-- Responsive constraints
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(800, 100)
	constraint.Parent = hotbarFrame

	for i=1,N do
		local x = 8+(i-1)*(SZ+PAD)
		local s = mkSlot({name="HB"..i, sz=SZ, pos=UDim2.new(0,x,0.5,0), z=2, parent=hotbarFrame})
		s.frame.AnchorPoint = Vector2.new(0,0.5)
		mkLabel({name="K", size=UDim2.new(0,14,0,12), pos=UDim2.new(0,4,0,3), text=tostring(i), ts=isMobile and 11 or 9, font=F.NUM, color=C.DIM, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, z=5, parent=s.frame})
		s.click.MouseButton1Click:Connect(function() UIManager.selectHotbarSlot(i) end)
		hotbarSlots[i] = s
	end
	UIManager.selectHotbarSlot(1)
end

----------------------------------------------------------------
-- 4. 퀵 액션 버튼 — 우측 하단 원형
----------------------------------------------------------------
local function createActionButtons()
	local btnSize = isMobile and 60 or 44
	
	local acts = {
		{key="Z", label="상호작용", fn=function() 
			local IC = require(Controllers.InteractController)
			if IC.interact then IC.interact() end
		end},
		{key="E", label="상태", fn=function() UIManager.toggleStatus() end},
		{key="C", label="제작", fn=function() UIManager.toggleCrafting() end},
		{key="B", label="가방", fn=function() UIManager.toggleInventory() end},
	}
	
	-- Vertical list container - Use Scale for height to prevent overflow on small devices
	actionContainer = mkFrame({name="Actions", size=UDim2.new(0,btnSize+20,0.4,0), pos=UDim2.new(1,-15,1,-20), anchor=Vector2.new(1,1), bgT=1, parent=mainGui})
	local list = Instance.new("UIListLayout"); list.VerticalAlignment=Enum.VerticalAlignment.Bottom; list.HorizontalAlignment=Enum.HorizontalAlignment.Center; list.Padding=UDim.new(0,isMobile and 12 or 8); list.Parent=actionContainer

	for _, a in ipairs(acts) do
		local rect = mkFrame({name="Act"..a.key, size=UDim2.new(0,btnSize,0,btnSize), bg=C.BG_OVERLAY, bgT=0.4, r=isMobile and 10 or 8, stroke=1.5, strokeC=C.BORDER, z=3, parent=actionContainer})
		local btn = Instance.new("TextButton")
		btn.Name="Btn"; btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=10; btn.Parent=rect
		btn.MouseButton1Click:Connect(a.fn)
		
		mkLabel({text=a.key, ts=isMobile and 15 or 12, font=F.TITLE, color=C.GOLD, pos=UDim2.new(0.5,0,0.3,0), z=4, parent=rect})
		mkLabel({text=a.label, ts=isMobile and 11 or 8, pos=UDim2.new(0.5,0,0.7,0), z=4, parent=rect})
	end
	
	if isMobile then
		local atkSize = 100
		local atkBtn = mkBtn({name="MobileAttack", size=UDim2.new(0,atkSize,0,atkSize), pos=UDim2.new(1,-120,1,-140), anchor=Vector2.new(0.5,0.5), bg=C.BTN_CLOSE, bgT=0.3, r=atkSize/2, stroke=3, strokeC=C.WHITE, z=2, parent=mainGui})
		mkLabel({text="ACTION", ts=20, font=F.TITLE, color=C.WHITE, parent=atkBtn})
		atkBtn.MouseButton1Down:Connect(function()
			local CC = require(Controllers.CombatController)
			if CC.attack then CC.attack() end
		end)
	end
end

----------------------------------------------------------------
-- 5. 인벤토리 — 원형 슬롯 + 카테고리 탭 + 아이템 상세
----------------------------------------------------------------
local function createInventoryUI()
	local isSmallScreen = mainGui.AbsoluteSize.X < 800
	local PW = isMobile and 0.9 or (isSmallScreen and 0.6 or 0.45)
	local PH = isMobile and 0.8 or 0.6
	
	inventoryFrame = mkFrame({name="Inventory", size=UDim2.new(PW,0,PH,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, r=10, stroke=1, strokeC=C.BORDER, vis=false, z=10, parent=mainGui})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.4; aspect.Parent = inventoryFrame
	
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(1000, 700); sizeLimit.Parent = inventoryFrame

	local tbH = isMobile and 44 or 34
	local tb = mkFrame({name="TB", size=UDim2.new(1,0,0,tbH), bg=C.BG_OVERLAY, bgT=0.3, r=10, z=10, parent=inventoryFrame})
	mkLabel({text="가방", ts=isMobile and 18 or 14, font=F.TITLE, color=C.WHITE, pos=UDim2.new(0,15,0,0), ax=Enum.TextXAlignment.Left, z=11, parent=tb})
	mkBtn({name="X", size=UDim2.new(0,tbH-8,0,tbH-8), pos=UDim2.new(1,-10,0.5,0), anchor=Vector2.new(1,0.5), text="X", ts=14, font=F.TITLE, bg=C.BTN_CLOSE, r=4, z=12, fn=function() UIManager.closeInventory() end, parent=tb})

	local content = mkFrame({name="Content", size=UDim2.new(1,0,1,-tbH), pos=UDim2.new(0,0,0,tbH), bgT=1, z=10, parent=inventoryFrame})
	local gridSection = mkFrame({name="GridSection", size=UDim2.new(0.68,0,1,0), bgT=1, z=11, parent=content})
	local detailSection = mkFrame({name="DetailSection", size=UDim2.new(0.32,0,1,0), pos=UDim2.new(0.68,0,0,0), bg=C.BG_PANEL_L, bgT=0.2, z=11, parent=content})

	local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,10); pad.PaddingBottom=UDim.new(0,10); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.Parent=gridSection
	
	local tabH = isMobile and 40 or 30
	local tabContainer = mkFrame({name="Tabs", size=UDim2.new(1,0,0,tabH), bgT=1, z=12, parent=gridSection})
	local bagTab = mkBtn({name="TabBag", size=UDim2.new(0.48,0,1,0), text="소지품", ts=isMobile and 14 or 12, font=F.TITLE, bg=C.NODE_SEL, r=4, z=13, parent=tabContainer})
	local craftTabInner = mkBtn({name="TabCraft", size=UDim2.new(0.48,0,1,0), pos=UDim2.new(1,0,0,0), anchor=Vector2.new(1,0), text="제작", ts=isMobile and 14 or 12, font=F.TITLE, bg=C.BG_PANEL_L, r=4, z=13, parent=tabContainer})

	invItemsContainer = Instance.new("ScrollingFrame")
	invItemsContainer.Name = "ItemsContainer"
	invItemsContainer.Size = UDim2.new(1,0,1,-(tabH+25))
	invItemsContainer.Position = UDim2.new(0,0,0,tabH+5)
	invItemsContainer.BackgroundTransparency = 1
	invItemsContainer.BorderSizePixel = 0
	invItemsContainer.ScrollBarThickness = 2
	invItemsContainer.ZIndex = 12
	invItemsContainer.ClipsDescendants = true
	invItemsContainer.Parent = gridSection

	local gridLayout = Instance.new("UIGridLayout")
	local sSize = isMobile and 64 or 56
	gridLayout.CellSize = UDim2.new(0, sSize, 0, sSize)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = invItemsContainer
	
	for i=1, 30 do -- Increased slot count
		local s = mkSlot({name="IS"..i, sz=1, pos=UDim2.new(0,0,0,0), z=13, parent=invItemsContainer})
		s.click.MouseButton1Click:Connect(function() UIManager._onInvSlotClick(i) end)
		invSlots[i] = s
	end
	invItemsContainer.CanvasSize = UDim2.new(0,0,0, math.ceil(30/4) * (sSize+10) + 10)

	local weightFrame = mkFrame({name="WeightFrame", size=UDim2.new(1,0,0,12), pos=UDim2.new(0,0,1,0), anchor=Vector2.new(0,1), bg=C.BG_SLOT, r=4, z=12, parent=gridSection})
	local weightFill = mkFrame({name="Fill", size=UDim2.new(0,0,1,0), bg=C.GOLD, r=4, z=13, parent=weightFrame})
	mkLabel({name="WeightText", size=UDim2.new(1,0,1,0), text="0 / 300 kg", ts=9, font=F.NUM, color=C.WHITE, z=14, parent=weightFrame})

	invCraftContainer = mkFrame({name="CraftContainer", size=UDim2.new(1,0,1,-(tabH+25)), pos=UDim2.new(0,0,0,tabH+5), bgT=1, vis=false, z=12, parent=gridSection})
	local craftScroll = Instance.new("ScrollingFrame")
	craftScroll.Size = UDim2.new(1,0,1,0); craftScroll.BackgroundTransparency=1; craftScroll.ScrollBarThickness=2; craftScroll.Parent=invCraftContainer
	invPersonalCraftGrid = craftScroll

	invDetailPanel = detailSection
	local dPad = Instance.new("UIPadding"); dPad.PaddingTop=UDim.new(0,12); dPad.PaddingBottom=UDim.new(0,12); dPad.PaddingLeft=UDim.new(0,12); dPad.PaddingRight=UDim.new(0,12); dPad.Parent=invDetailPanel
	
	mkLabel({name="DName", size=UDim2.new(1,0,0,24), text="정보", ts=14, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, z=12, parent=invDetailPanel})
	local previewCircle = mkFrame({name="Preview", size=UDim2.new(0.7,0,0.3,0), pos=UDim2.new(0.5,0,0,35), anchor=Vector2.new(0.5,0), bg=C.BG_SLOT, r=10, stroke=1.5, strokeC=C.BORDER, z=12, parent=invDetailPanel})
	local prevAsp = Instance.new("UIAspectRatioConstraint"); prevAsp.AspectRatio=1; prevAsp.Parent=previewCircle
	mkLabel({name="PName", size=UDim2.new(0.8,0,0.8,0), pos=UDim2.new(0.1,0,0.1,0), text="", ts=10, color=C.GRAY, wrap=true, z=13, parent=previewCircle})
	
	local infoList = mkFrame({size=UDim2.new(1,0,0.3,0), pos=UDim2.new(0,0,0.6,0), bgT=1, z=12, parent=invDetailPanel})
	local il = Instance.new("UIListLayout"); il.Padding=UDim.new(0,5); il.Parent=infoList
	mkLabel({name="DWeight", size=UDim2.new(1,0,0,16), text="", ts=11, color=C.GRAY, ax=Enum.TextXAlignment.Left, z=12, parent=infoList})
	mkLabel({name="DCount", size=UDim2.new(1,0,0,16), text="", ts=11, font=F.NUM, color=C.GRAY, ax=Enum.TextXAlignment.Left, z=12, parent=infoList})

	local footer = mkFrame({name="Footer", size=UDim2.new(1,0,0,isMobile and 60 or 40), pos=UDim2.new(0,0,1,0), anchor=Vector2.new(0,1), bgT=1, z=12, parent=invDetailPanel})
	local btnDrop = mkBtn({name="BtnDrop", size=UDim2.new(0.46,0,0.8,0), pos=UDim2.new(0,0,0.5,0), anchor=Vector2.new(0,0.5), text="버리기", ts=12, bg=C.BTN, r=4, z=13, parent=footer})
	local btnUse = mkBtn({name="BtnUse", size=UDim2.new(0.46,0,0.8,0), pos=UDim2.new(1,0,0.5,0), anchor=Vector2.new(1,0.5), text="사용", ts=12, bg=C.BTN_CRAFT, r=4, z=13, parent=footer})
	UIManager._btnUse = btnUse

	bagTab.MouseButton1Click:Connect(function()
		invItemsContainer.Visible = true; invCraftContainer.Visible = false
		bagTab.BackgroundColor3 = C.NODE_SEL; craftTabInner.BackgroundColor3 = C.BG_PANEL_L
	end)
	craftTabInner.MouseButton1Click:Connect(function()
		invItemsContainer.Visible = false; invCraftContainer.Visible = true
		craftTabInner.BackgroundColor3 = C.NODE_SEL; bagTab.BackgroundColor3 = C.BG_PANEL_L
		UIManager.refreshPersonalCrafting()
	end)

	btnUse.MouseButton1Click:Connect(function()
		if invCraftContainer.Visible then UIManager._doCraft()
		elseif selectedInvSlot then
			NetClient.Request("Inventory.Use.Request", {slot = selectedInvSlot})
		end
	end)
	btnDrop.MouseButton1Click:Connect(function()
		if selectedInvSlot and not invCraftContainer.Visible then
			NetClient.Request("Inventory.Drop.Request", {slot = selectedInvSlot})
		end
	end)
end

----------------------------------------------------------------
-- 5.1 스탯 및 장비창 (독립 UI)
----------------------------------------------------------------
local function createStatusUI()
	local isSmallScreen = mainGui.AbsoluteSize.X < 800
	local PW = isMobile and 0.8 or (isSmallScreen and 0.5 or 0.35)
	local PH = isMobile and 0.7 or 0.6
	statusFrame = mkFrame({name="Status", size=UDim2.new(PW,0,PH,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, r=12, stroke=1, strokeC=C.BORDER, vis=false, z=10, parent=mainGui})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.85; aspect.Parent = statusFrame
	
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(280, 400); sizeLimit.Parent = statusFrame

	local tbH = isMobile and 44 or 34
	local tb = mkFrame({size=UDim2.new(1,0,0,tbH), bg=C.BG_OVERLAY, bgT=0.3, r=12, z=10, parent=statusFrame})
	mkLabel({text="능력치", ts=isMobile and 16 or 14, font=F.TITLE, color=C.WHITE, z=11, parent=tb})
	mkBtn({name="X", size=UDim2.new(0,tbH-8,0,tbH-8), pos=UDim2.new(1,-10,0.5,0), anchor=Vector2.new(1,0.5), text="X", ts=14, font=F.TITLE, bg=C.BTN_CLOSE, r=4, z=12, fn=function() UIManager.closeStatus() end, parent=tb})

	statsPanel = mkFrame({name="StatsPanel", size=UDim2.new(1,0,1,-tbH), pos=UDim2.new(0,0,0,tbH), bgT=1, z=11, parent=statusFrame})
	local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,15); pad.PaddingBottom=UDim.new(0,15); pad.PaddingLeft=UDim.new(0,15); pad.PaddingRight=UDim.new(0,15); pad.Parent=statsPanel
	
	mkLabel({name="StatPoints", size=UDim2.new(1,0,0,24), text="포인트: 0", ts=13, font=F.NUM, color=C.GOLD, ax=Enum.TextXAlignment.Left, z=12, parent=statsPanel})
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name="Scroll"; scroll.Size=UDim2.new(1,0,1,-30); scroll.Position=UDim2.new(0,0,0,30); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=2; scroll.Parent=statsPanel
	
	local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0,8); list.Parent = scroll
	
	local stats = {
		{id=Enums.StatId.MAX_HEALTH, name="최대 체력"},
		{id=Enums.StatId.MAX_STAMINA, name="최대 스테미나"},
		{id=Enums.StatId.WEIGHT, name="최대 무게"},
		{id=Enums.StatId.WORK_SPEED, name="작업 속도"},
		{id=Enums.StatId.ATTACK, name="공격력"},
	}
	
	statLines = {}
	local lineH = isMobile and 44 or 36
	for _, s in ipairs(stats) do
		local line = mkFrame({name=s.id, size=UDim2.new(1,0,0,lineH), bg=C.BG_PANEL_L, r=6, z=12, parent=scroll})
		mkLabel({text=s.name, size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0,10,0,0), ts=isMobile and 12 or 11, font=F.TITLE, ax=Enum.TextXAlignment.Left, z=13, parent=line})
		local v = mkLabel({name="V", size=UDim2.new(0.3,0,1,0), pos=UDim2.new(0.4,0,0,0), text="0", ts=isMobile and 11 or 10, font=F.NUM, ax=Enum.TextXAlignment.Left, z=13, parent=line})
		local b = mkBtn({name="Up", size=UDim2.new(0,lineH-10,0,lineH-10), pos=UDim2.new(1,-5,0.5,0), anchor=Vector2.new(1,0.5), text="+", ts=16, font=F.TITLE, bg=C.BTN_CRAFT, r=4, z=14, parent=line})
		b.MouseButton1Click:Connect(function() NetClient.Request("Player.Stats.Upgrade.Request", {statId = s.id}) end)
		statLines[s.id] = {val=v, btn=b}
	end
end

----------------------------------------------------------------
-- 6. 제작 UI — 풀스크린 블러 + 다이아몬드 그리드
----------------------------------------------------------------
----------------------------------------------------------------
-- 6. 제작 및 건축 UI (개편: 정사각형 노드 + 프리미엄 레이아웃)
----------------------------------------------------------------
local function createCraftingUI()
	craftingOverlay = mkFrame({name="CraftOverlay", size=UDim2.new(1,0,1,0), bg=C.BG_OVERLAY, bgT=0.5, vis=false, z=100, parent=mainGui})
	
	local PW = isMobile and 0.95 or 0.6
	local PH = isMobile and 0.85 or 0.7
	local panel = mkFrame({name="Panel", size=UDim2.new(PW,0,PH,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, r=14, stroke=1.5, strokeC=C.BORDER, z=101, parent=craftingOverlay})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.6; aspect.Parent = panel
	
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(1100, 750); sizeLimit.Parent = panel

	local tbH = isMobile and 48 or 36
	mkLabel({name="Title", size=UDim2.new(1,0,0,tbH), text="제작 창", ts=isMobile and 24 or 20, font=F.TITLE, color=C.WHITE, z=102, parent=panel})
	mkBtn({name="X", size=UDim2.new(0,tbH-10,0,tbH-10), pos=UDim2.new(1,-15,0,tbH/2), anchor=Vector2.new(1,0.5), text="X", ts=18, font=F.TITLE, bg=C.BTN_CLOSE, r=8, z=102, fn=function() UIManager.closeCrafting() end, parent=panel})

	local content = mkFrame({name="Content", size=UDim2.new(1,0,1,-tbH), pos=UDim2.new(0,0,0,tbH), bgT=1, z=102, parent=panel})
	
	-- Split: 70% List, 30% Detail
	local listSection = mkFrame({name="L", size=UDim2.new(0.7,0,1,0), bgT=1, z=102, parent=content})
	local detailSection = mkFrame({name="D", size=UDim2.new(0.3,0,1,0), pos=UDim2.new(0.7,0,0,0), bg=C.BG_PANEL_L, r=10, z=102, parent=content})
	
	local lPad = Instance.new("UIPadding"); lPad.PaddingTop=UDim.new(0,15); lPad.PaddingBottom=UDim.new(0,15); lPad.PaddingLeft=UDim.new(0,15); lPad.PaddingRight=UDim.new(0,15); lPad.Parent=listSection

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1,0,1,0); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=2; scroll.Parent=listSection
	invCraftGrid = scroll

	local dPad = Instance.new("UIPadding"); dPad.PaddingTop=UDim.new(0,15); dPad.PaddingBottom=UDim.new(0,15); dPad.PaddingLeft=UDim.new(0,15); dPad.PaddingRight=UDim.new(0,15); dPad.Parent=detailSection
	craftDetailPanel = detailSection
	
	mkLabel({name="RName", size=UDim2.new(1,0,0,30), text="레시피 선택", ts=16, font=F.TITLE, color=C.WHITE, wrap=true, z=103, parent=detailSection})
	mkLabel({name="RDesc", size=UDim2.new(1,0,0,60), pos=UDim2.new(0,0,0,35), text="", ts=12, color=C.GRAY, ay=Enum.TextYAlignment.Top, wrap=true, z=103, parent=detailSection})
	
	local matList = mkFrame({name="Mats", size=UDim2.new(1,0,0.4,0), pos=UDim2.new(0,0,0,105), bgT=1, z=103, parent=detailSection})
	local ml = Instance.new("UIListLayout"); ml.Padding=UDim.new(0,4); ml.Parent=matList
	
	local craftCircle = mkFrame({name="CraftCircle", size=UDim2.new(0.6,0,0.6,0), pos=UDim2.new(0.5,0,0.85,0), anchor=Vector2.new(0.5,0.5), bg=C.BTN_CRAFT, r=10, stroke=2, strokeC=C.BTN_CRAFT_H, z=104, parent=detailSection})
	local cAsp = Instance.new("UIAspectRatioConstraint"); cAsp.AspectRatio=1; cAsp.Parent=craftCircle
	mkLabel({name="CraftLabel", text="제작", ts=16, font=F.TITLE, color=C.WHITE, z=105, parent=craftCircle})
	local cb = Instance.new("TextButton"); cb.Size=UDim2.new(1,0,1,0); cb.BackgroundTransparency=1; cb.Text=""; cb.ZIndex=110; cb.Parent=craftCircle
	cb.MouseButton1Click:Connect(function() UIManager._doCraft() end)

	local progBg = mkFrame({name="ProgBg", size=UDim2.new(1,0,0,8), pos=UDim2.new(0,0,1,0), anchor=Vector2.new(0,1), bg=C.BG_BAR, r=4, z=103, parent=detailSection})
	progFill = mkFrame({name="ProgFill", size=UDim2.new(0,0,1,0), bg=C.PROGRESS_FILL, r=4, z=104, parent=progBg})
	
	craftSpinner = Instance.new("ImageLabel")
	craftSpinner.Name = "Spinner"; craftSpinner.Size=UDim2.new(1.3,0,1.3,0); craftSpinner.Position=UDim2.new(0.5,0,0.5,0); craftSpinner.AnchorPoint=Vector2.new(0.5,0.5)
	craftSpinner.BackgroundTransparency=1; craftSpinner.Image="rbxassetid://15264878207"; craftSpinner.ImageColor3=C.WHITE; craftSpinner.Visible=false; craftSpinner.ZIndex=110; craftSpinner.Parent=craftCircle
end

local function createShopUI()
	local isSmallScreen = mainGui.AbsoluteSize.X < 800
	local PW = isMobile and 0.85 or (isSmallScreen and 0.6 or 0.45)
	local PH = isMobile and 0.8 or 0.55
	shopFrame = mkFrame({name="Shop", size=UDim2.new(PW,0,PH,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, r=12, stroke=1, strokeC=C.BORDER, vis=false, z=10, parent=mainGui})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = isMobile and 1.4 or 1.25; aspect.Parent = shopFrame

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(300, 250); sizeLimit.Parent = shopFrame

	local tbH = isMobile and 44 or 34
	local tb = mkFrame({name="TB", size=UDim2.new(1,0,0,tbH), bg=C.BG_OVERLAY, bgT=0.3, r=12, z=10, parent=shopFrame})
	mkLabel({text="상점", ts=isMobile and 17 or 15, font=F.TITLE, color=C.WHITE, z=11, parent=tb})
	mkBtn({name="X", size=UDim2.new(0,tbH-8,0,tbH-8), pos=UDim2.new(1,-15,0.5,0), anchor=Vector2.new(1,0.5), text="X", ts=14, font=F.TITLE, bg=C.BTN_CLOSE, r=4, z=12, fn=function() UIManager.closeShop() end, parent=tb})
	mkLabel({name="Gold", size=UDim2.new(0,120,0,24), pos=UDim2.new(0,15,0.5,0), anchor=Vector2.new(0,0.5), text="💰 0", ts=13, font=F.NUM, color=C.GOLD, ax=Enum.TextXAlignment.Left, z=11, parent=tb})

	local content = mkFrame({name="Content", size=UDim2.new(1,0,1,-tbH-10), pos=UDim2.new(0,0,0,tbH+5), bgT=1, z=10, parent=shopFrame})
	local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,10); pad.PaddingBottom=UDim.new(0,10); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.Parent=content

	local tabH = isMobile and 40 or 30
	local tabContainer = mkFrame({name="Tabs", size=UDim2.new(1,0,0,tabH), bgT=1, z=12, parent=content})
	local buyTabBtn = mkBtn({name="TabBuyLink", size=UDim2.new(0.48,0,1,0), text="구매", ts=isMobile and 14 or 12, font=F.TITLE, bg=C.NODE_SEL, r=4, z=13, parent=tabContainer})
	local sellTabBtn = mkBtn({name="TabSellLink", size=UDim2.new(0.48,0,1,0), pos=UDim2.new(1,0,0,0), anchor=Vector2.new(1,0), text="판매", ts=isMobile and 14 or 12, font=F.TITLE, bg=C.BG_PANEL_L, r=4, z=13, parent=tabContainer})

	local scrollBuy = Instance.new("ScrollingFrame")
	scrollBuy.Name = "TabBuyGrid"; scrollBuy.Size = UDim2.new(1,0,1,-tabH-10); scrollBuy.Position = UDim2.new(0,0,0,tabH+5)
	scrollBuy.BackgroundTransparency=1; scrollBuy.BorderSizePixel=0; scrollBuy.ScrollBarThickness=2; scrollBuy.ZIndex=12; scrollBuy.Parent=content
	
	local scrollSell = Instance.new("ScrollingFrame")
	scrollSell.Name = "TabSellGrid"; scrollSell.Size = UDim2.new(1,0,1,-tabH-10); scrollSell.Position = UDim2.new(0,0,0,tabH+5)
	scrollSell.BackgroundTransparency=1; scrollSell.BorderSizePixel=0; scrollSell.ScrollBarThickness=2; scrollSell.ZIndex=12; scrollSell.Visible=false; scrollSell.Parent=content
	
	buyTabBtn.MouseButton1Click:Connect(function()
		scrollBuy.Visible = true; scrollSell.Visible = false
		buyTabBtn.BackgroundColor3 = C.NODE_SEL; sellTabBtn.BackgroundColor3 = C.BG_PANEL_L
	end)
	sellTabBtn.MouseButton1Click:Connect(function()
		scrollBuy.Visible = false; scrollSell.Visible = true
		sellTabBtn.BackgroundColor3 = C.NODE_SEL; buyTabBtn.BackgroundColor3 = C.BG_PANEL_L
	end)
end

----------------------------------------------------------------
-- 7.5. 기술 트리 UI
----------------------------------------------------------------
local function createTechUI()
	techOverlay = mkFrame({name="TechOverlay", size=UDim2.new(1,0,1,0), bg=C.BG_OVERLAY, bgT=0.5, vis=false, z=100, parent=mainGui})
	
	local PW = isMobile and 0.96 or 0.65
	local PH = isMobile and 0.88 or 0.75
	local panel = mkFrame({name="Panel", size=UDim2.new(PW,0,PH,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, r=14, z=101, parent=techOverlay})
	
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = isMobile and 1.8 or 1.6; aspect.Parent = panel

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(1200, 850); sizeLimit.Parent = panel

	local tbH = isMobile and 44 or 40
	mkLabel({text="기술 트리", ts=isMobile and 18 or 24, font=F.TITLE, color=C.WHITE, size=UDim2.new(1,0,0,tbH), z=102, parent=panel})
	
	-- Position TP label better for mobile (Left-aligned)
	mkLabel({name="TP", size=UDim2.new(0,120,0,24), pos=UDim2.new(0,20,0,tbH/2), anchor=Vector2.new(0,0.5), text="TP: 0", ts=isMobile and 12 or 16, font=F.NUM, color=C.GOLD, ax=Enum.TextXAlignment.Left, z=102, parent=panel})
	
	mkBtn({name="X", size=UDim2.new(0,tbH-10,0,tbH-10), pos=UDim2.new(1,-15,0,tbH/2), anchor=Vector2.new(1,0.5), text="X", ts=18, font=F.TITLE, bg=C.BTN_CLOSE, r=8, z=102, fn=function() UIManager.closeTechTree() end, parent=panel})

	local content = mkFrame({name="Content", size=UDim2.new(1,0,1,-tbH-10), pos=UDim2.new(0,0,0,tbH+5), bgT=1, z=102, parent=panel})
	
	local splitRatio = isMobile and 0.62 or 0.7
	local listSection = mkFrame({name="L", size=UDim2.new(splitRatio, 0, 1, 0), bgT=1, z=101, parent=content})
	local diagPad = Instance.new("UIPadding"); diagPad.PaddingTop=UDim.new(0,10); diagPad.PaddingBottom=UDim.new(0,10); diagPad.PaddingLeft=UDim.new(0,10); diagPad.PaddingRight=UDim.new(0,10); diagPad.Parent=listSection

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TreeScroll"; scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 2; scroll.ZIndex = 101; scroll.Parent = listSection

	local detail = mkFrame({name="Detail", size=UDim2.new(1-splitRatio,0,1,0), pos=UDim2.new(splitRatio,0,0,0), bg=C.BG_PANEL_L, r=10, z=102, parent=content})
	local dPad = Instance.new("UIPadding"); dPad.PaddingTop=UDim.new(0,15); dPad.PaddingBottom=UDim.new(0,15); dPad.PaddingLeft=UDim.new(0,15); dPad.PaddingRight=UDim.new(0,15); dPad.Parent=detail

	mkLabel({name="TName", size=UDim2.new(1,0,0,30), text="기술 선택", ts=isMobile and 15 or 16, font=F.TITLE, color=C.WHITE, wrap=true, z=103, parent=detail})
	
	-- Description area with internal scrolling
	local descScroll = Instance.new("ScrollingFrame")
	descScroll.Name = "DescScroll"; descScroll.Size = UDim2.new(1, 0, 0.45, 0); descScroll.Position = UDim2.new(0, 0, 0, 35); descScroll.BackgroundTransparency = 1; descScroll.BorderSizePixel = 0; descScroll.ScrollBarThickness = 2; descScroll.Parent = detail
	mkLabel({name="TDesc", size=UDim2.new(1,0,1,0), text="", ts=isMobile and 11 or 12, color=C.GRAY, ay=Enum.TextYAlignment.Top, ax=Enum.TextXAlignment.Left, wrap=true, z=103, parent=descScroll})
	
	local footer = mkFrame({name="Footer", size=UDim2.new(1,0,0.4,0), pos=UDim2.new(0,0,1,0), anchor=Vector2.new(0,1), bgT=1, z=103, parent=detail})
	mkLabel({name="TCost", size=UDim2.new(1,0,0,40), pos=UDim2.new(0,0,0,0), text="", ts=isMobile and 11 or 12, font=F.NUM, color=C.GOLD, wrap=true, z=103, parent=footer})
	local unlockBtn = mkBtn({name="UnlockBtn", size=UDim2.new(1,0,0,isMobile and 44 or 38), pos=UDim2.new(0.5,0,1,0), anchor=Vector2.new(0.5,1), text="연구", ts=14, font=F.TITLE, bg=C.BTN_CRAFT, r=6, z=104, parent=footer})
	unlockBtn.MouseButton1Click:Connect(function() UIManager._doUnlockTech() end)
end

----------------------------------------------------------------
-- 8. 상호작용 프롬프트
----------------------------------------------------------------
local function createInteractPrompt()
	interactPrompt = mkFrame({name="Prompt", size=UDim2.new(0,isMobile and 200 or 170,0,isMobile and 44 or 38), pos=UDim2.new(0.5,0,0.65,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_OVERLAY, bgT=0.35, r=8, stroke=1, strokeC=C.BORDER, vis=false, z=5, parent=mainGui})
	mkLabel({text=isMobile and "상호작용" or "[E] 상호작용", ts=isMobile and 15 or 13, color=C.WHITE, z=6, parent=interactPrompt})
end

----------------------------------------------------------------
-- Public API: HUD
----------------------------------------------------------------
function UIManager.updateHealth(cur, max)
	if not healthBar then return end
	local r = math.clamp(cur/max,0,1)
	TweenService:Create(healthBar.fill, TweenInfo.new(0.2), {Size=UDim2.new(r,0,1,0)}):Play()
	healthBar.label.Text = string.format("%d/%d", math.floor(cur), math.floor(max))
	healthBar.fill.BackgroundColor3 = r < 0.25 and C.RED or C.HP
end

function UIManager.updateStamina(cur, max)
	if not staminaBar then return end
	local r = math.clamp(cur/max,0,1)
	TweenService:Create(staminaBar.fill, TweenInfo.new(0.2), {Size=UDim2.new(r,0,1,0)}):Play()
	staminaBar.label.Text = string.format("%d/%d", math.floor(cur), math.floor(max))
end

function UIManager.updateXP(cur, max)
	if not xpBar then return end
	local r = math.clamp(cur/max,0,1)
	TweenService:Create(xpBar.fill, TweenInfo.new(0.3), {Size=UDim2.new(r,0,1,0)}):Play()
	xpBar.label.Text = string.format("%d/%d XP", math.floor(cur), math.floor(max))
end

function UIManager.updateLevel(lv)
	if levelLabel then levelLabel.Text = "Lv. "..tostring(lv) end
end

function UIManager.updateStatPoints(available)
	if statPointAlert then
		statPointAlert.Visible = (available > 0)
	end
end

function UIManager.updateGold(amt)
	if shopFrame then
		local g = shopFrame:FindFirstChild("TB")
		if g then g = g:FindFirstChild("Gold"); if g then g.Text = "💰 "..tostring(amt) end end
	end
end

----------------------------------------------------------------
-- Public API: Hotbar
----------------------------------------------------------------
function UIManager.selectHotbarSlot(idx, skipSync)
	if hotbarSlots[selectedSlot] then
		local st = hotbarSlots[selectedSlot].frame:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.BORDER; st.Thickness = 1.5 end
	end
	selectedSlot = idx
	if hotbarSlots[idx] then
		local st = hotbarSlots[idx].frame:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.GOLD; st.Thickness = 2.5 end
	end
	
	if not skipSync then
		task.spawn(function()
			NetClient.Request("Inventory.ActiveSlot.Request", {slot = idx})
		end)
	end
end

function UIManager.getSelectedSlot()
	return selectedSlot
end

-- 아이템 아이콘 가져오기 (폴더 검색 우선, 데이터 폴백)
local function getItemIcon(itemId: string): string
	-- 1. Assets/ItemIcons 폴더에서 검색
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local iconsFolder = assets and assets:FindFirstChild("ItemIcons")
	if iconsFolder then
		local iconObj = iconsFolder:FindFirstChild(itemId)
		if iconObj then
			if iconObj:IsA("Decal") or iconObj:IsA("Texture") then
				return iconObj.Texture
			elseif iconObj:IsA("ImageLabel") or iconObj:IsA("ImageButton") then
				return iconObj.Image
			end
		end
	end

	-- 2. ItemData.lua 필드 확인
	local itemData = DataHelper.GetData("ItemData", itemId)
	return (itemData and itemData.icon) or ""
end

function UIManager.refreshHotbar()
	local items = InventoryController.getItems()
	for i=1,8 do
		local s = hotbarSlots[i]
		if s then
			local item = items[i]
			if item and item.itemId then
				local itemData = DataHelper.GetData("ItemData", item.itemId)
				local icon = getItemIcon(item.itemId)
				s.nameLabel.Text = itemData and itemData.name or item.itemId
				s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
				s.icon.Image = icon
				-- 아이콘이 있으면 텍스트는 숨기거나 아주 작게 표시
				s.nameLabel.Visible = (icon == "")
			else
				s.icon.Image = ""; s.nameLabel.Text = ""; s.countLabel.Text = ""; s.nameLabel.Visible = true
			end
		end
	end
end

----------------------------------------------------------------
-- Public API: Inventory
----------------------------------------------------------------
function UIManager.openInventory()
	if isInvOpen then return end
	closeAllWindows("INV")
	isInvOpen = true; inventoryFrame.Visible = true; InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false) -- Hide HUD when menu is open
	UIManager.refreshInventory()
	inventoryFrame.Position = UDim2.new(0.5,0,0.58,0)
	TweenService:Create(inventoryFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back), {Position=UDim2.new(0.5,0,0.5,0)}):Play()
end

function UIManager.closeInventory()
	if not isInvOpen then return end
	TweenService:Create(inventoryFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isInvOpen = false; inventoryFrame.Visible = false
		if not isShopOpen and not isCraftOpen and not isStatusOpen and not isTechOpen then 
			InputManager.setUIOpen(false) 
			UIManager._setMainHUDVisible(true) -- Restore HUD only when all windows are closed
		end
	end)
end

function UIManager.toggleInventory()
	if isInvOpen then UIManager.closeInventory() else UIManager.openInventory() end
end

----------------------------------------------------------------
-- Public API: Status / Stats
----------------------------------------------------------------
function UIManager.openStatus()
	if isStatusOpen then return end
	closeAllWindows("STATUS")
	isStatusOpen = true; statusFrame.Visible = true; InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	UIManager.refreshStats()
	statusFrame.Position = UDim2.new(0.5,0,0.58,0)
	TweenService:Create(statusFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back), {Position=UDim2.new(0.5,0,0.5,0)}):Play()
end

function UIManager.closeStatus()
	if not isStatusOpen then return end
	TweenService:Create(statusFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isStatusOpen = false; statusFrame.Visible = false
		if not isInvOpen and not isShopOpen and not isCraftOpen and not isTechOpen then 
			InputManager.setUIOpen(false) 
			UIManager._setMainHUDVisible(true)
		end
	end)
end

function UIManager.toggleStatus()
	if isStatusOpen then UIManager.closeStatus() else UIManager.openStatus() end
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	for i, s in pairs(invSlots) do
		local item = items[i]
		if item and item.itemId then
			local itemData = DataHelper.GetData("ItemData", item.itemId)
			local icon = getItemIcon(item.itemId)
			s.nameLabel.Text = itemData and itemData.name or item.itemId
			s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
			s.frame.BackgroundColor3 = C.BG_SLOT
			s.icon.Image = icon
			s.nameLabel.Visible = (icon == "")
		else
			s.icon.Image = ""; s.nameLabel.Text = ""; s.countLabel.Text = ""
			s.frame.BackgroundColor3 = C.BG_SLOT
			s.nameLabel.Visible = true
		end
	end
	UIManager.refreshHotbar()

	-- Update Weight bar
	local totalWeight = 0
	local maxWeight = (cachedStats.calculated and cachedStats.calculated.maxWeight) or 300
	for _, item in pairs(items) do
		local weight = item.weight or 0.1
		totalWeight = totalWeight + (weight * item.count)
	end
	
	local weightFrame = inventoryFrame:FindFirstChild("WeightFrame")
	if weightFrame then
		local fill = weightFrame:FindFirstChild("Fill")
		local lbl = weightFrame:FindFirstChild("WeightText")
		if fill then
			local pct = math.clamp(totalWeight / maxWeight, 0, 1)
			fill.Size = UDim2.new(pct, 0, 1, 0)
			fill.BackgroundColor3 = pct > 0.9 and C.RED or C.GOLD
		end
		if lbl then
			lbl.Text = string.format("무게: %.1f / %.0f kg", totalWeight, maxWeight)
		end
	end
end

function UIManager.refreshStats()
	if not statsPanel or not statsPanel.Visible then return end
	
	local ptLabel = statsPanel:FindFirstChild("StatPoints")
	local available = cachedStats.statPointsAvailable or 0
	if ptLabel then ptLabel.Text = "남은 강화 포인트: "..available end
	
	local calc = cachedStats.calculated or {}
	local invested = cachedStats.statInvested or {}
	
	-- 각 스탯 줄 업데이트
	for statId, line in pairs(statLines) do
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

function UIManager._onInvSlotClick(idx)
	-- 이전 선택 해제
	if selectedInvSlot and invSlots[selectedInvSlot] then
		local st = invSlots[selectedInvSlot].frame:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.BORDER end
	end
	selectedInvSlot = idx
	-- 선택 표시
	if invSlots[idx] then
		local st = invSlots[idx].frame:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.BORDER_SEL end
	end
	-- Detail 업데이트
	local items = InventoryController.getItems()
	local data = items[idx]
	
	if data and data.itemId then
		invDetailPanel.DName.Text = data.name or data.itemId
		invDetailPanel.DCount.Text = "수량: " .. data.count
		invDetailPanel.DWeight.Text = string.format("무게: %.1f kg", (data.weight or 0.1) * data.count)
		invDetailPanel.Preview.PName.Text = data.itemId
		
		-- 버튼 텍스트 업데이트
		if UIManager._btnUse then
			local itemData = DataHelper.GetData("ItemData", data.itemId)
			if itemData then
				if itemData.type == Enums.ItemType.WEAPON or itemData.type == Enums.ItemType.TOOL or itemData.type == Enums.ItemType.ARMOR then
					if idx >= 1 and idx <= 8 then
						UIManager._btnUse.Text = "선택하기"
					else
						UIManager._btnUse.Text = "장착하기"
					end
				else
					UIManager._btnUse.Text = "사용하기"
				end
			else
				UIManager._btnUse.Text = "사용하기"
			end
		end
	else
		invDetailPanel.DName.Text = "빈 슬롯"
		invDetailPanel.DCount.Text = ""
		invDetailPanel.DWeight.Text = ""
		invDetailPanel.Preview.PName.Text = ""
		if UIManager._btnUse then UIManager._btnUse.Text = "사용하기" end
	end
end

function UIManager.onInventorySlotClick(idx)
	UIManager._onInvSlotClick(idx)
end

----------------------------------------------------------------
-- Public API: Crafting
----------------------------------------------------------------
function UIManager.openCrafting(mode)
	if isCraftOpen then return end
	closeAllWindows("CRAFT")
	activeStructureId = nil
	activeFacilityId = nil
	isCraftOpen = true; craftingOverlay.Visible = true; InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	-- Mode reset (User request: Inventory = Craft, C-Key = Building)
	menuMode = mode or "BUILDING"
	local tabMsg = craftingOverlay:FindFirstChild("Tabs")
	if tabMsg then
		local tc = tabMsg:FindFirstChild("TabCraft")
		local tb = tabMsg:FindFirstChild("TabBuild")
		if tc then tc.Visible = false end -- 제작 탭 숨기기
		if tb then tb.BackgroundColor3 = C.NODE_SEL end
	end
	local title = craftingOverlay:FindFirstChild("Title")
	if title then 
		title.Text = menuMode == "CRAFTING" and "제작 벤치" or "건축 및 시설"
	end

	-- Blur
	blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	UIManager.refreshCrafting()
	craftingOverlay.BackgroundTransparency = 1
	TweenService:Create(craftingOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 0.35}):Play()
end

--- 작업대(가구)를 통한 제작 메뉴 열기
function UIManager.openWorkbench(structureId, facilityId)
	if isCraftOpen then return end
	closeAllWindows("CRAFT")
	activeStructureId = structureId
	activeFacilityId = facilityId
	isCraftOpen = true; craftingOverlay.Visible = true; InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	menuMode = "CRAFTING" -- 작업대는 여전히 제작 모드
	
	local title = craftingOverlay:FindFirstChild("Title")
	if title then 
		title.Text = facilityId == "CAMPFIRE" and "요리 하기" or "작업대 제작"
	end

	-- Blur
	blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	UIManager.refreshCrafting()
	craftingOverlay.BackgroundTransparency = 1
	TweenService:Create(craftingOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 0.35}):Play()
end

function UIManager.closeCrafting()
	if not isCraftOpen then return end
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	TweenService:Create(craftingOverlay, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
	task.delay(0.15, function()
		isCraftOpen = false; craftingOverlay.Visible = false; selectedRecipeId = nil
		if not isInvOpen and not isShopOpen and not isStatusOpen and not isTechOpen then 
			InputManager.setUIOpen(false) 
			UIManager._setMainHUDVisible(true)
		end
	end)
end

function UIManager.toggleCrafting()
	if isCraftOpen then UIManager.closeCrafting() else UIManager.openCrafting() end
end

function UIManager.refreshCrafting()
	local grid = craftingOverlay:FindFirstChild("NodeGrid")
	if not grid then return end
	for _, ch in pairs(grid:GetChildren()) do if ch:IsA("Frame") or ch:IsA("ScrollingFrame") then ch:Destroy() end end
	craftNodes = {}; selectedRecipeId = nil; selectedFacilityId = nil
	-- Detail 초기화
	local rn = craftDetailPanel:FindFirstChild("RName"); if rn then rn.Text = menuMode == "CRAFTING" and "제작 대상을 선택하세요" or "건축 대상을 선택하세요" end
	local rm = craftDetailPanel:FindFirstChild("RMats"); if rm then rm.Text = "" end
	local rt = craftDetailPanel:FindFirstChild("RTime"); if rt then rt.Text = "" end

	task.spawn(function()
		local recipes, facilities = {}, {}
		if menuMode == "CRAFTING" then
			-- 만약 activeStructureId가 있으면 해당 시설에 맞는 레시피만 요청할 수 있음
			local ok, data = NetClient.Request("Recipe.List.Request", {
				structureId = activeStructureId,
				facilityId = activeFacilityId
			})
			if ok and data and data.recipes then recipes = data.recipes end
		else
			local ok, data = NetClient.Request("Facility.List.Request", {})
			if ok and data and data.facilities then facilities = data.facilities end
		end

		local itemsToShow = menuMode == "CRAFTING" and recipes or facilities
		
		-- Sort by techLevel (ascending) then name
		table.sort(itemsToShow, function(a, b)
			local lvA = a.techLevel or 0
			local lvB = b.techLevel or 0
			if lvA ~= lvB then return lvA < lvB end
			return (a.name or "") < (b.name or "")
		end)

		local playerItemCounts = InventoryController.getItemCounts()
		
		-- Grid constants (Image 2 style, but Square)
		local SSZ = 64
		local SPACING = 24
		local COLS = 5
		local gridWidth = COLS * (SSZ + SPACING)
		local startX = (grid.AbsoluteSize.X > 0 and grid.AbsoluteSize.X or 600) / 2 - gridWidth / 2 + SSZ/2

		for idx, item in ipairs(itemsToShow) do
			local row = math.floor((idx-1) / COLS)
			local col = (idx-1) % COLS
			local x = startX + col * (SSZ + SPACING)
			local y = 60 + row * (SSZ + SPACING)

			-- Check materials
			local canMake = true
			local matsText = ""
			local inputs = item.inputs or item.requirements
			if inputs then
				for i, inp in ipairs(inputs) do
					local req = inp.count or inp.amount or 0
					local have = playerItemCounts[inp.itemId or inp.id] or 0
					local ok2 = have >= req
					if not ok2 then canMake = false end
					matsText = matsText .. string.format("%s %s %d/%d  ", ok2 and "✓" or "✗", inp.itemId or inp.id, have, req)
				end
			end

			-- Check tech unlock
			local isLocked = false
			if menuMode == "CRAFTING" then
				-- 레시피 해금 여부 확인
				isLocked = not TechController.isRecipeUnlocked(item.id)
			else
				-- 시설 해금 여부 확인
				isLocked = not TechController.isFacilityUnlocked(item.id)
			end
			
			-- 기본 기술 해금은 TechController.isRecipeUnlocked 등에서 알아서 처리됨
			-- 명시적 레벨 기반 예외 처리 제거하여 테크 트리 기반 잠금 보장

			-- Node frame (Square)
			local nf = mkFrame({name="Node"..idx, size=UDim2.new(0,SSZ,0,SSZ), pos=UDim2.new(0,x,0,y), anchor=Vector2.new(0.5,0.5), bg=C.NODE, r=4, stroke=1.5, strokeC=canMake and C.NODE_BD or Color3.fromRGB(60,45,45), z=102, parent=grid})
			
			local icon = Instance.new("ImageLabel")
			icon.Name="Icon"; icon.Size=UDim2.new(1,0,1,0); icon.Position=UDim2.new(0,0,0,0)
			icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Stretch; icon.ZIndex=103; icon.Parent=nf
			local iconId = getItemIcon(item.id)
			-- 만약 레시피(CRAFT_...)인데 아이콘이 없으면 결과물 아이템 ID로 재검색
			if iconId == "" and item.outputs and item.outputs[1] then
				iconId = getItemIcon(item.outputs[1].itemId)
			end
			icon.Image = iconId
			
			local iconLbl = mkLabel({text=item.name or item.id, ts=9, color=canMake and C.WHITE or C.DIM, wrap=true, z=104, parent=nf})
			iconLbl.Visible = (iconId == "")
			
			-- Lock overlay (Re-implementation)
			if isLocked then
				local lockBG = mkFrame({name="LockBG", size=UDim2.new(1,0,1,0), bg=Color3.new(0,0,0), bgT=0.7, r=4, z=110, parent=nf})
				mkLabel({name="Lock", size=UDim2.new(1,0,1,0), text="🔒", ts=24, color=Color3.new(1,1,1), z=111, parent=lockBG})
				iconLbl.TextColor3 = C.DIM -- Dim text if locked
			end

			-- Click
			local btn = Instance.new("TextButton")
			btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=120; btn.Parent=nf
			btn.MouseButton1Click:Connect(function()
				for _, d in pairs(craftNodes) do
					local st = d.frame:FindFirstChildOfClass("UIStroke")
					if st then 
						local strokeColor = d.canCraft and C.NODE_BD or Color3.fromRGB(60,45,45)
						if d.isLocked then strokeColor = Color3.fromRGB(60,45,45) end -- Locked items always have dim border
						st.Color = strokeColor; st.Thickness = 1.5 
					end
				end
				local st = nf:FindFirstChildOfClass("UIStroke")
				if st then st.Color = C.NODE_SEL; st.Thickness = 2.5 end
				
				if menuMode == "CRAFTING" then
					selectedRecipeId = item.id
				else
					selectedFacilityId = item.id
				end
				
				if rn then rn.Text = (isLocked and "🔒 " or "") .. (item.name or item.id) end
				if rm then rm.Text = isLocked and "기술 트리에서 해금해야 합니다." or matsText end
				if rt then rt.Text = isLocked and "잠김" or (menuMode == "CRAFTING" and (item.craftTime and (item.craftTime.."초") or "즉시") or "건축") end
			end)

			craftNodes[item.id] = {frame=nf, canCraft=canMake, data=item, isLocked=isLocked}
		end

		local totalRows = math.ceil(#itemsToShow / COLS)
		grid.CanvasSize = UDim2.new(0,0,0, totalRows * (SSZ + SPACING) + 120)
	end)
end

-- 재료 체크 헬퍼
local function checkMaterials(item)
	local playerItemCounts = InventoryController.getItemCounts()
	local inputs = item.inputs or item.requirements
	if not inputs then return true, "" end
	
	local missing = {}
	for _, inp in ipairs(inputs) do
		local req = inp.count or inp.amount or 0
		local have = playerItemCounts[inp.itemId or inp.id] or 0
		if have < req then
			local itemName = inp.itemId or inp.id
			local itemData = DataHelper.GetData("ItemData", itemName)
			if itemData then itemName = itemData.name end
			table.insert(missing, string.format("%s (%d/%d)", itemName, have, req))
		end
	end
	
	if #missing > 0 then
		return false, "부족한 재료: " .. table.concat(missing, ", ")
	end
	return true, ""
end

----------------------------------------------------------------
-- Personal Crafting (Inventory Tab)
----------------------------------------------------------------
function UIManager.refreshPersonalCrafting()
	if not invPersonalCraftGrid then return end
	for _, ch in pairs(invPersonalCraftGrid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	personalCraftNodes = {}; selectedPersonalRecipeId = nil

	task.spawn(function()
		local ok, data = NetClient.Request("Recipe.List.Request", {facilityId = nil})
		local recipes = (ok and data and data.recipes) or {}

		table.sort(recipes, function(a, b) return (a.techLevel or 0) < (b.techLevel or 0) end)

		local sz = 64; local gap = 12; local cols = 5
		for idx, recipe in ipairs(recipes) do
			local row = math.floor((idx-1) / cols); local col = (idx-1) % cols
			local x = col * (sz + gap) + 2 -- Padding for border
			local y = row * (sz + gap) + 2
			
			local isLocked = not TechController.isRecipeUnlocked(recipe.id)
			-- Use BG_SLOT for consistency, and clear border
			local nf = mkFrame({name="PNode"..idx, size=UDim2.new(0,sz,0,sz), pos=UDim2.new(0,x,0,y), bg=C.BG_SLOT, r=6, stroke=1.5, strokeC=isLocked and C.DIM or C.BORDER, z=12, parent=invPersonalCraftGrid})
			
			local icon = Instance.new("ImageLabel")
			icon.Name="Icon"; icon.Size=UDim2.new(1,0,1,0); icon.Position=UDim2.new(0,0,0,0)
			icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Stretch; icon.ZIndex=13; icon.Parent=nf
			local iconId = getItemIcon(recipe.id)
			-- 레시피 아이콘이 없으면 결과물 아이콘으로 시도
			if iconId == "" and recipe.outputs and recipe.outputs[1] then
				iconId = getItemIcon(recipe.outputs[1].itemId)
			end
			icon.Image = iconId

			-- Center the labels and increase font size for better readability
			local iconLbl = mkLabel({text=recipe.name, size=UDim2.new(1,-10,1,-10), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), ts=10, font=F.BODY, color=isLocked and C.DIM or C.WHITE, wrap=true, z=14, parent=nf})
			iconLbl.Visible = (iconId == "")
			
			if isLocked then
				local lockBG = mkFrame({name="Lock", size=UDim2.new(1,0,1,0), bg=Color3.new(0,0,0), bgT=0.5, r=6, z=14, parent=nf})
			end

			local btn = Instance.new("TextButton")
			btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=15; btn.Parent=nf
			btn.MouseButton1Click:Connect(function()
				for _, d in pairs(personalCraftNodes) do
					local st = d.frame:FindFirstChildOfClass("UIStroke")
					if st then st.Color = d.isLocked and C.DIM or C.BORDER; st.Thickness = 1.5 end
				end
				local st = nf:FindFirstChildOfClass("UIStroke"); if st then st.Color = C.GOLD; st.Thickness = 2.5 end
				selectedPersonalRecipeId = recipe.id
				UIManager._updatePersonalCraftDetail(recipe)
			end)

			personalCraftNodes[recipe.id] = {frame=nf, isLocked=isLocked}
		end
		invPersonalCraftGrid.CanvasSize = UDim2.new(0,0,0, math.ceil(#recipes/cols)*(sz+gap))
	end)
end

function UIManager._updatePersonalCraftDetail(recipe)
	if not invDetailPanel then return end
	local dn = invDetailPanel:FindFirstChild("DName"); if dn then dn.Text = recipe.name end
	local dw = invDetailPanel:FindFirstChild("DWeight"); if dw then dw.Text = "제작 소요: "..(recipe.craftTime or 0).."초" end
	local dc = invDetailPanel:FindFirstChild("DCount"); if dc then 
		local playerItemCounts = InventoryController.getItemCounts()
		local mats = {}
		for _, inp in ipairs(recipe.inputs or {}) do
			local have = playerItemCounts[inp.itemId or inp.id] or 0
			table.insert(mats, string.format("%s %d/%d", inp.itemId, have, inp.count or 0))
		end
		dc.Text = "필요: " .. table.concat(mats, ", ") 
	end
	
	local useBtn = invDetailPanel:FindFirstChild("BtnUse")
	if useBtn then 
		useBtn.Text = "제작하기"
		useBtn.BackgroundColor3 = C.BTN_CRAFT
	end
	
	-- Reset progress bar if recipe changed
	if progFill then progFill.Size = UDim2.new(0,0,1,0) end
end

local isCrafting = false
local craftTween = nil
local spinnerConn = nil

function UIManager.showCraftingProgress(duration)
	if isCrafting then return end
	isCrafting = true
	
	if craftSpinner then
		craftSpinner.Visible = true
		if spinnerConn then spinnerConn:Disconnect() end
		spinnerConn = RunService.RenderStepped:Connect(function(dt)
			craftSpinner.Rotation = craftSpinner.Rotation + 180 * dt
		end)
	end
	
	if progFill then
		progFill.Size = UDim2.new(0,0,1,0)
		craftTween = TweenService:Create(progFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,1,0)})
		craftTween:Play()
	end
	
	-- 버튼 텍스트 변경
	local craftLabel = craftingOverlay:FindFirstChild("CraftLabel", true)
	if craftLabel then craftLabel.Text = "제작 중..." end
end

function UIManager.stopCraftingProgress()
	isCrafting = false
	if spinnerConn then spinnerConn:Disconnect(); spinnerConn = nil end
	if craftSpinner then craftSpinner.Visible = false end
	if craftTween then craftTween:Cancel(); craftTween = nil end
	
	local craftLabel = craftingOverlay:FindFirstChild("CraftLabel", true)
	if craftLabel then craftLabel.Text = "제작" end
	
	if progFill then progFill.Size = UDim2.new(0,0,1,0) end
end
function UIManager._doCraft()
	-- 1. 인벤토리 내 개인 제작 처리
	if isInvOpen and invCraftContainer and invCraftContainer.Visible then
		if not selectedPersonalRecipeId then return end
		
		-- 기술 잠금 체크
		if not TechController.isRecipeUnlocked(selectedPersonalRecipeId) then
			UIManager.notify("레벨 2 달성 및 기술 해금이 필요합니다.", C.RED)
			return
		end

		local recipe = DataHelper.GetData("RecipeData", selectedPersonalRecipeId)
		if recipe then
			local ok, msg = checkMaterials(recipe)
			if not ok then UIManager.notify(msg, C.RED); return end
		end

		task.spawn(function()
			local ok, data = NetClient.Request("Craft.Start.Request", {recipeId = selectedPersonalRecipeId})
			if ok then 
				-- 제작 시작 성공 (NetClient.Request는 response.success가 true일 때만 ok=true 반환)
				UIManager.notify("제작을 시작했습니다.", C.GREEN)
				-- 제작 시간 정보가 있으면 프로그레스바 시작
				if data and data.craftTime and data.craftTime > 0 then
					UIManager.showCraftingProgress(data.craftTime)
				end
				task.delay(0.5, function() UIManager.refreshPersonalCrafting() end)
			else
				local reason = tostring(data or "서버 오류")
				UIManager.notify("제작 실패: " .. reason, C.RED)
			end
		end)
		return
	end

	-- 2. 일반 공방/건축 처리
	if menuMode == "CRAFTING" then
		if not selectedRecipeId then return end
		
		-- 기술 잠금 체크
		if not TechController.isRecipeUnlocked(selectedRecipeId) then
			UIManager.notify("기술이 해금되지 않았습니다.", C.RED)
			return
		end
		
		local recipe = DataHelper.GetData("RecipeData", selectedRecipeId)
		if recipe then
			local ok, msg = checkMaterials(recipe)
			if not ok then UIManager.notify(msg, C.RED); return end
		end

		task.spawn(function()
			local ok, data = NetClient.Request("Craft.Start.Request", {recipeId = selectedRecipeId})
			if ok then
				print("[UIManager] Craft Started:", selectedRecipeId)
				UIManager.notify("제작을 시작했습니다.", C.GREEN)
				-- 제작 시간 정보가 있으면 프로그레스바 시작
				if data and data.craftTime and data.craftTime > 0 then
					UIManager.showCraftingProgress(data.craftTime)
				end
				task.delay(0.5, function() if isCraftOpen then UIManager.refreshCrafting() end end)
			else
				local reason = tostring(data or "서버 오류")
				UIManager.notify("제작 실패: " .. reason, C.RED)
			end
		end)
	else
		-- BUILDING 모드
		if not selectedFacilityId then return end
		
		-- 1. Lock Check
		if not TechController.isFacilityUnlocked(selectedFacilityId) then
			UIManager.notify("기술이 해금되지 않았습니다.", C.RED)
			return
		end
		
		-- 2. Material Check
		local facility = DataHelper.GetData("FacilityData", selectedFacilityId)
		if facility then
			local ok, msg = checkMaterials(facility)
			if not ok then UIManager.notify(msg, C.RED); return end
		end

		print("[UIManager] Start Placement:", selectedFacilityId)
		UIManager.closeCrafting()
		BuildController.startPlacement(selectedFacilityId)
	end
end

----------------------------------------------------------------
-- Public API: Tech Tree
----------------------------------------------------------------
function UIManager.openTechTree()
	if isTechOpen then return end
	closeAllWindows("TECH")
	isTechOpen = true; techOverlay.Visible = true; InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	-- Blur
	if not isCraftOpen then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshTechTree()
	techOverlay.BackgroundTransparency = 1
	TweenService:Create(techOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 0.4}):Play()
end

function UIManager.closeTechTree()
	if not isTechOpen then return end
	if blurEffect and not isCraftOpen then blurEffect:Destroy(); blurEffect = nil end
	TweenService:Create(techOverlay, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
	task.delay(0.15, function()
		isTechOpen = false; techOverlay.Visible = false; selectedTechId = nil
		if not isInvOpen and not isShopOpen and not isStatusOpen and not isCraftOpen then 
			InputManager.setUIOpen(false) 
			UIManager._setMainHUDVisible(true)
		end
	end)
end

function UIManager.toggleTechTree()
	if isTechOpen then UIManager.closeTechTree() else UIManager.openTechTree() end
end

function UIManager.refreshTechTree()
	local scroll = techOverlay:FindFirstChild("TreeScroll")
	if not scroll then return end
	for _, ch in pairs(scroll:GetChildren()) do if ch:IsA("Frame") or ch:IsA("TextButton") or ch:IsA("UIGridLayout") then ch:Destroy() end end
	
	local tpLabel = techOverlay:FindFirstChild("TP")
	if tpLabel then tpLabel.Text = "TP: "..TechController.getTechPoints() end
	
	local tree = TechController.getTechTree()
	local unlocked = TechController.getUnlockedTech()
	
	local techList = {}
	for id, data in pairs(tree) do table.insert(techList, data) end
	table.sort(techList, function(a,b) 
		if a.techLevel ~= b.techLevel then return a.techLevel < b.techLevel end
		return a.id < b.id
	end)

	local grid = Instance.new("UIGridLayout")
	local slotSize = isMobile and 70 or 80
	grid.CellSize = UDim2.new(0, slotSize, 0, slotSize)
	grid.CellPadding = UDim2.new(0, 15, 0, 15)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroll
	
	local playerLevel = (cachedStats and cachedStats.level) or 1
	techNodes = {} -- Reset node references

	for idx, tech in ipairs(techList) do
		local isUnlocked = unlocked[tech.id] == true
		local reqLevel = tech.requireLevel or 1
		local levelMet = playerLevel >= reqLevel
		
		local nf = mkFrame({name="Node"..tech.id, size=UDim2.new(0,slotSize,0,slotSize), bg=isUnlocked and C.BTN_CRAFT or C.BG_PANEL_L, bgT=0.2, r=12, stroke=2.5, strokeC=isUnlocked and C.GOLD or (levelMet and C.BORDER or C.RED), z=102, parent=scroll})
		
		local icon = Instance.new("ImageLabel")
		icon.Name="Icon"; icon.Size=UDim2.new(0.8,0,0.8,0); icon.Position=UDim2.new(0.5,0,0.5,0); icon.AnchorPoint=Vector2.new(0.5,0.5)
		icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=103; icon.Parent=nf
		local iconId = getItemIcon(tech.id)
		icon.Image = iconId
		
		local iconLbl = mkLabel({text=tech.name, ts=isMobile and 9 or 11, font=F.TITLE, color=isUnlocked and C.WHITE or C.GRAY, wrap=true, z=104, parent=nf})
		iconLbl.Visible = (iconId == "")
		
		if not isUnlocked then
			mkLabel({text="TP "..tech.techPointCost, ts=9, font=F.NUM, pos=UDim2.new(0,0,1,-22), color=C.GOLD, z=104, parent=nf})
			mkLabel({text="Lv."..reqLevel, ts=9, font=F.NUM, pos=UDim2.new(0,0,1,-10), color=levelMet and C.GRAY or C.RED, z=104, parent=nf})
		end
		
		local btn = Instance.new("TextButton")
		btn.Name="Click"; btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=105; btn.Parent=nf
		btn.MouseButton1Click:Connect(function()
			selectedTechId = tech.id
			local detail = techOverlay:FindFirstChild("Detail")
			if detail then
				local tn = detail:FindFirstChild("TName"); if tn then tn.Text = tech.name end
				local td = detail:FindFirstChild("TDesc", true); if td then td.Text = tech.description or "" end
				
				local costText = isUnlocked and "연구 완료" or string.format("필요 TP: %d\n(필요 레벨: %d)", tech.techPointCost, reqLevel)
				local tc = detail:FindFirstChild("TCost", true)
				if tc then 
					tc.Text = costText 
					tc.TextColor3 = (isUnlocked or levelMet) and C.GOLD or C.RED
				end
				local ub = detail:FindFirstChild("UnlockBtn", true); if ub then ub.Visible = not isUnlocked end
			end

			-- Reset previous strokes
			for _, node in pairs(techNodes) do
				local st = node.frame:FindFirstChildOfClass("UIStroke")
				if st then 
					local nodeLevelMet = playerLevel >= (node.data.requireLevel or 1)
					st.Color = node.isUnlocked and C.GOLD or (nodeLevelMet and C.BORDER or C.RED)
					st.Thickness = 2.5
				end
			end
			-- Highlight current
			local st = nf:FindFirstChildOfClass("UIStroke")
			if st then st.Color = C.WHITE; st.Thickness = 3.5 end
		end)
		
		techNodes[tech.id] = {frame=nf, isUnlocked=isUnlocked, data=tech}
	end
	
	local cols = isMobile and 3 or 4
	local rows = math.ceil(#techList / cols)
	scroll.CanvasSize = UDim2.new(0, 0, 0, rows * (slotSize + 15) + 30)
end

function UIManager._doUnlockTech()
	if not selectedTechId then return end
	TechController.requestUnlock(selectedTechId, function(success, err)
		if success then
			UIManager.notify("기술 연구 완료!", C.GREEN)
			UIManager.refreshTechTree()
		else
			UIManager.notify("연구 실패: TP가 부족하거나 선행 기술이 필요합니다.", C.RED)
		end
	end)
end

----------------------------------------------------------------
-- Public API: Shop
----------------------------------------------------------------
function UIManager.openShop(shopId)
	if isShopOpen then return end
	closeAllWindows("SHOP")
	isShopOpen = true; shopFrame.Visible = true; InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	shopFrame.Position = UDim2.new(0.5,0,0.58,0)
	TweenService:Create(shopFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back), {Position=UDim2.new(0.5,0,0.5,0)}):Play()
	
	-- 상점 정보 요청 및 새로고침
	ShopController.requestShopInfo(shopId, function(ok, shopInfo)
		if ok then
			UIManager.refreshShop(shopId)
		end
	end)
end

function UIManager.closeShop()
	if not isShopOpen then return end
	TweenService:Create(shopFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isShopOpen = false; shopFrame.Visible = false
		if not isInvOpen and not isCraftOpen and not isTechOpen then InputManager.setUIOpen(false) end
	end)
end

function UIManager.refreshShop(shopId)
	if not isShopOpen then return end
	local shopInfo = ShopController.getShopInfo(shopId)
	if not shopInfo then return end
	
	local tabBuy = shopFrame:FindFirstChild("TabBuyGrid", true)
	local tabSell = shopFrame:FindFirstChild("TabSellGrid", true)
	if not tabBuy or not tabSell then return end
	
	-- Clear existing
	for _, ch in pairs(tabBuy:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	for _, ch in pairs(tabSell:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	
	-- Setup Grid Layouts
	for _, t in pairs({tabBuy, tabSell}) do
		local grid = t:FindFirstChildOfClass("UIGridLayout") or Instance.new("UIGridLayout")
		local sSize = isMobile and 80 or 70
		grid.CellSize = UDim2.new(0, sSize, 0, sSize)
		grid.CellPadding = UDim2.new(0, 10, 0, 10)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = t
	end
	
	-- Refresh Buy List
	local buyItems = shopInfo.buyList or {}
	for i, item in ipairs(buyItems) do
		local slot = mkFrame({name="BuySlot"..i, size=UDim2.new(0,70,0,70), bg=C.NODE, r=4, stroke=1, strokeC=C.BORDER, parent=tabBuy})
		
		local icon = Instance.new("ImageLabel")
		icon.Name="Icon"; icon.Size=UDim2.new(1,0,1,0); icon.Position=UDim2.new(0,0,0,0)
		icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=11; icon.Parent=slot
		local iconId = getItemIcon(item.itemId)
		icon.Image = iconId
		
		local iconLbl = mkLabel({text=item.itemId, ts=9, color=C.WHITE, wrap=true, z=12, parent=slot})
		iconLbl.Visible = (iconId == "")
		mkLabel({text=item.price.."g", ts=10, pos=UDim2.new(0,0,1,-12), color=C.GOLD, z=13, parent=slot})
		
		local btn = Instance.new("TextButton")
		btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=15; btn.Parent=slot
		btn.MouseButton1Click:Connect(function()
			ShopController.requestBuy(shopId, item.itemId, 1, function(success, err)
				if success then
					UIManager.notify("구매 완료: "..item.itemId, C.GREEN)
				else
					UIManager.notify("구매 실패: 골드가 부족합니다.", C.RED)
				end
			end)
		end)
	end
	tabBuy.CanvasSize = UDim2.new(0,0,0, math.ceil(#buyItems/3) * (isMobile and 90 or 80) + 20)
	
	-- Refresh Sell List
	local invItems = InventoryController.getItems()
	local sellableItems = shopInfo.sellList or {}
	local sellCount = 0
	
	for slotIdx, invSlot in pairs(invItems) do
		if invSlot and invSlot.itemId then
			local sellData = nil
			for _, s in ipairs(sellableItems) do
				if s.itemId == invSlot.itemId then sellData = s; break end
			end
			
			if sellData then
				sellCount = sellCount + 1
				local slot = mkFrame({name="SellSlot"..sellCount, size=UDim2.new(0,70,0,70), bg=C.NODE, r=4, stroke=1, strokeC=C.BORDER, parent=tabSell})
				
				local icon = Instance.new("ImageLabel")
				icon.Name="Icon"; icon.Size=UDim2.new(1,0,1,0); icon.Position=UDim2.new(0,0,0,0)
				icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=11; icon.Parent=slot
				local iconId = getItemIcon(invSlot.itemId)
				icon.Image = iconId
				
				local iconLbl = mkLabel({text=invSlot.itemId.."\nx"..invSlot.count, ts=9, color=C.WHITE, wrap=true, z=12, parent=slot})
				iconLbl.Visible = (iconId == "")
				mkLabel({text=sellData.price.."g", ts=10, pos=UDim2.new(0,0,1,-12), color=C.GOLD, z=13, parent=slot})
				
				local btn = Instance.new("TextButton")
				btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=15; btn.Parent=slot
				btn.MouseButton1Click:Connect(function()
					ShopController.requestSell(shopId, slotIdx, 1, function(success, err)
						if success then
							UIManager.notify("판매 완료: "..invSlot.itemId, C.GREEN)
							UIManager.refreshShop(shopId)
						else
							UIManager.notify("판매 실패: "..tostring(err), C.RED)
						end
					end)
				end)
			end
		end
	end
	tabSell.CanvasSize = UDim2.new(0,0,0, math.ceil(sellCount/3) * (isMobile and 90 or 80) + 20)
end

function UIManager.closeStatus()
	if not isStatusOpen then return end
	TweenService:Create(statusFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isStatusOpen = false; statusFrame.Visible = false
		if not isInvOpen and not isShopOpen and not isCraftOpen then InputManager.setUIOpen(false) end
	end)
end

function UIManager.closeShop()
	if not isShopOpen then return end
	TweenService:Create(shopFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isShopOpen = false; shopFrame.Visible = false
		if not isInvOpen and not isStatusOpen and not isCraftOpen and not isTechOpen then 
			InputManager.setUIOpen(false) 
			UIManager._setMainHUDVisible(true)
		end
	end)
end

----------------------------------------------------------------
-- Public API: Interact / Harvest
----------------------------------------------------------------
function UIManager.showInteractPrompt(text)
	if interactPrompt then
		local l = interactPrompt:FindFirstChildOfClass("TextLabel")
		if l then l.Text = text or "[E] 상호작용" end
		interactPrompt.Visible = true
	end
end
function UIManager.hideInteractPrompt()
	if interactPrompt then interactPrompt.Visible = false end
end

function UIManager.showHarvestProgress(totalTime, targetName)
	if harvestFrame then
		harvestFrame.Visible = true
		if harvestBar then harvestBar.Size = UDim2.new(0,0,1,0) end
		if harvestPctLabel then harvestPctLabel.Text = "0%" end
		if harvestNameLabel then harvestNameLabel.Text = targetName or "채집 중..." end
	end
end
function UIManager.hideHarvestProgress()
	if harvestFrame then harvestFrame.Visible = false end
end
function UIManager.updateHarvestProgress(progress)
	local p = math.clamp(progress, 0, 1)
	if harvestBar then harvestBar.Size = UDim2.new(p, 0, 1, 0) end
	if harvestPctLabel then harvestPctLabel.Text = math.floor(p * 100) .. "%" end
end

-- 건축 조작 가이드 표시
function UIManager.showBuildPrompt(visible)
	if buildPromptFrame then buildPromptFrame.Visible = visible end
end

-- 알림 표시 (중앙 하단)
local notifyConn
function UIManager.notify(text, color)
	local label = UIManager._notifyLabel
	if not label then return end
	
	label.Text = text
	if color then label.TextColor3 = color end
	label.Visible = true
	
	if notifyConn then task.cancel(notifyConn) end
	notifyConn = task.delay(2, function()
		label.Visible = false
		notifyConn = nil
	end)
end

----------------------------------------------------------------
-- Event Listeners
----------------------------------------------------------------
local function setupEventListeners()
	InventoryController.onChanged(function()
		if isInvOpen then UIManager.refreshInventory() end
		UIManager.refreshHotbar()
	end)
	ShopController.onGoldChanged(function(g) UIManager.updateGold(g) end)
	TechController.onTechUpdated(function()
		if isTechOpen then UIManager.refreshTechTree() end
		if isCraftOpen then UIManager.refreshCrafting() end
	end)
	TechController.onTechUnlocked(function(data)
		UIManager.notify("기술 해금: " .. (data.name or data.techId), C.GOLD)
	end)

	-- 활성 슬롯 동기화 (서버 -> 클라)
	NetClient.On("Inventory.ActiveSlot.Changed", function(data)
		if data and data.slot then
			UIManager.selectHotbarSlot(data.slot, true) -- 루프 방지 위해 skipSync=true
		end
	end)



	-- Hotbar number keys
	local hotbarKeys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight}
	for i = 1, 8 do
		InputManager.bindKey(hotbarKeys[i], "HB"..i, function() UIManager.selectHotbarSlot(i) end)
	end

	-- Stats event
	if NetClient.On then
		NetClient.On("Player.Stats.Changed", function(d)
			if d then
				for k, v in pairs(d) do cachedStats[k] = v end
				if d.level then UIManager.updateLevel(d.level) end
				if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
				if d.leveledUp then 
					UIManager.notify(" 레벨업! Lv. "..d.level, C.GOLD)
				end
				if d.statPointsAvailable ~= nil then UIManager.updateStatPoints(d.statPointsAvailable) end
				if isStatusOpen then UIManager.refreshStats() end
			end
		end)
		
		NetClient.On("Player.Stats.Upgraded", function(data)
			UIManager.notify(" 💪 능력치 강화 성공!", C.GREEN)
			-- refreshStats는 Stats.Changed에 의해 호출됨
		end)
	end

	-- Crafting Events
	if NetClient.On then
		NetClient.On("Craft.Started", function(data)
			if data and data.craftTime and data.craftTime > 0 then
				UIManager.showCraftingProgress(data.craftTime)
			end
		end)
		
		NetClient.On("Craft.Completed", function(data)
			UIManager.stopCraftingProgress()
			
			local name = "아이템"
			if data and data.recipeId then
				local recipe = DataHelper.GetData("RecipeData", data.recipeId)
				if recipe then name = recipe.name end
			end
			
			UIManager.notify("제작 완료: " .. name, C.GREEN)
			if isInvOpen then UIManager.refreshInventory() end
			if isCraftOpen then UIManager.refreshCrafting() end
		end)
		
		NetClient.On("Craft.Cancelled", function(data)
			UIManager.stopCraftingProgress()
			UIManager.notify("제작 취소됨", C.GRAY)
		end)
	end

	-- Humanoid HP
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid")
		UIManager.updateHealth(hum.Health, hum.MaxHealth)
		hum.HealthChanged:Connect(function(h) UIManager.updateHealth(h, hum.MaxHealth) end)
		player.CharacterAdded:Connect(function(c)
			local h2 = c:WaitForChild("Humanoid")
			UIManager.updateHealth(h2.Health, h2.MaxHealth)
			h2.HealthChanged:Connect(function(h) UIManager.updateHealth(h, h2.MaxHealth) end)
		end)
	end)

	-- Initial stats load
	task.spawn(function()
		task.wait(1)
		local ok, d = NetClient.Request("Player.Stats.Request", {})
		if ok and d then
			cachedStats = d
			if d.level then UIManager.updateLevel(d.level) end
			if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
			if d.statPointsAvailable then UIManager.updateStatPoints(d.statPointsAvailable) end
		end
	end)
end

----------------------------------------------------------------
-- Init
----------------------------------------------------------------
function UIManager.Init()
	if initialized then return end

	mainGui = Instance.new("ScreenGui")
	mainGui.Name = "GameUI"
	mainGui.ResetOnSpawn = false
	mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainGui.IgnoreGuiInset = false
	mainGui.Parent = playerGui

	createHUD()
	createHarvestProgress()
	createHotbar()
	createActionButtons()
	createInventoryUI()
	createStatusUI()
	createCraftingUI()
	createShopUI()
	createTechUI()
	createInteractPrompt()
	
	-- 건축 배치 가이드 UI (Image 3 스타일)
	buildPromptFrame = mkFrame({name="BuildPrompt", size=UDim2.new(0,300,0,44), pos=UDim2.new(0.5,0,0.88,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_OVERLAY, bgT=0.5, r=8, stroke=1.5, strokeC=C.GOLD, vis=false, z=200, parent=mainGui})
	mkLabel({text="[좌클릭] 배치  [R] 회전  [X] 취소", ts=14, font=F.TITLE, color=C.WHITE, z=201, parent=buildPromptFrame})

	setupEventListeners()

	UIManager.updateHealth(100,100)
	UIManager.updateStamina(100,100)
	UIManager.updateXP(0,100)
	UIManager.updateLevel(1)
	
	-- 알림 라벨 생성
	local notifyLabel = mkLabel({name="Notify", size=UDim2.new(0,400,0,40), pos=UDim2.new(0.5,0,0.8,-100), anchor=Vector2.new(0.5,0.5), text="", ts=16, font=F.TITLE, color=Color3.new(1,0.3,0.3), z=100, parent=mainGui})
	notifyLabel.TextStrokeTransparency = 0.5
	notifyLabel.Visible = false
	UIManager._notifyLabel = notifyLabel

	initialized = true
	print("[UIManager] Initialized — Durango-style UI")
end

return UIManager
