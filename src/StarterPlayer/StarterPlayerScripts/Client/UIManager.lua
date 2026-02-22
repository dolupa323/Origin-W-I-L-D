-- UIManager.lua
-- WildForge UI — 듀랑고 스타일 레퍼런스 기반
-- HUD(우측) + 원형슬롯 인벤토리 + 풀스크린 제작 + 채집바(상단)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Client = script.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)

local Controllers = Client:WaitForChild("Controllers")
local InventoryController = require(Controllers.InventoryController)
local ShopController = require(Controllers.ShopController)

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

	DIAMOND       = Color3.fromRGB(36, 36, 44),
	DIAMOND_BD    = Color3.fromRGB(88, 88, 98),
	DIAMOND_SEL   = Color3.fromRGB(180, 140, 58),
	LOCK          = Color3.fromRGB(140, 140, 148),
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
local healthBar, staminaBar, xpBar, levelLabel

-- Hotbar
local hotbarFrame
local hotbarSlots = {}
local selectedSlot = 1

-- Panels
local inventoryFrame, craftingOverlay, shopFrame, interactPrompt
local isInvOpen, isCraftOpen, isShopOpen = false, false, false

-- Harvest progress
local harvestFrame, harvestBar, harvestPctLabel, harvestNameLabel

-- Inventory
local invSlots = {}
local invDetailPanel
local selectedInvSlot = nil
local categoryButtons = {}

-- Crafting
local craftDiamonds = {}
local selectedRecipeId = nil
local craftDetailPanel
local blurEffect

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function mkFrame(p)
	local f = Instance.new("Frame")
	f.Name = p.name or "F"
	f.Size = p.size or UDim2.new(0,100,0,100)
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
	b.Size = p.size or UDim2.new(0,100,0,36)
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
	local baseR = 6 -- 둥근 사각형 반경
	local slot = mkFrame({name=p.name or "S", size=UDim2.new(0,sz,0,sz), pos=p.pos, bg=C.BG_SLOT, r=baseR, stroke=1.5, strokeC=C.BORDER, z=p.z or 1, parent=p.parent})
	local icon = Instance.new("ImageLabel")
	icon.Name="Icon"; icon.Size=UDim2.new(0.65,0,0.65,0); icon.Position=UDim2.new(0.175,0,0.08,0)
	icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=(p.z or 1)+1; icon.Parent=slot
	local nm = mkLabel({name="Nm", size=UDim2.new(0.9,0,0.45,0), pos=UDim2.new(0.05,0,0.12,0), text="", ts=8, color=C.GRAY, wrap=true, z=(p.z or 1)+1, parent=slot})
	local ct = mkLabel({name="Ct", size=UDim2.new(0.55,0,0,13), pos=UDim2.new(0.42,0,1,-15), text="", ts=11, font=F.NUM, color=C.WHITE, ax=Enum.TextXAlignment.Right, z=(p.z or 1)+2, parent=slot})
	local cb = Instance.new("TextButton")
	cb.Name="CB"; cb.Size=UDim2.new(1,0,1,0); cb.BackgroundTransparency=1; cb.Text=""; cb.ZIndex=(p.z or 1)+3; cb.Parent=slot
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
	local hud = mkFrame({name="HUD", size=UDim2.new(0,175,0,82), pos=UDim2.new(1,-14,0,14), anchor=Vector2.new(1,0), bg=C.BG_OVERLAY, bgT=0.55, r=8, parent=mainGui})
	-- HP
	healthBar = mkBar({name="HP", size=UDim2.new(1,-16,0,20), pos=UDim2.new(0,8,0,8), bgC=C.HP_BG, fillC=C.HP, barR=4, stroke=1, text="100/100", labelTs=10, z=2, parent=hud})
	mkLabel({name="Ic", size=UDim2.new(0,18,0,20), pos=UDim2.new(0,10,0,8), text="❤", ts=11, ax=Enum.TextXAlignment.Left, z=4, parent=hud})
	-- STA
	staminaBar = mkBar({name="STA", size=UDim2.new(1,-16,0,14), pos=UDim2.new(0,8,0,33), bgC=C.STA_BG, fillC=C.STA, barR=3, text="100/100", labelTs=9, z=2, parent=hud})
	-- XP
	xpBar = mkBar({name="XP", size=UDim2.new(1,-16,0,10), pos=UDim2.new(0,8,0,52), bgC=C.XP_BG, fillC=C.XP, barR=3, text="0/100 XP", labelTs=7, z=2, parent=hud})
	xpBar.fill.Size = UDim2.new(0,0,1,0)
	-- Level
	levelLabel = mkLabel({name="Lv", size=UDim2.new(0,60,0,14), pos=UDim2.new(0,8,0,65), text="Lv. 1", ts=11, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, z=2, parent=hud})
end

----------------------------------------------------------------
-- 2. 채집 진행바 — 상단 중앙 (참조: 초록바 + % + 대상명)
----------------------------------------------------------------
local function createHarvestProgress()
	harvestFrame = mkFrame({name="Harvest", size=UDim2.new(0,320,0,52), pos=UDim2.new(0.5,0,0,28), anchor=Vector2.new(0.5,0), bg=C.BG_OVERLAY, bgT=0.45, r=6, vis=false, z=20, parent=mainGui})
	local barBg = mkFrame({name="BarBg", size=UDim2.new(1,-20,0,22), pos=UDim2.new(0,10,0,6), bg=C.HARVEST_BG, r=4, stroke=1.2, strokeC=Color3.fromRGB(120,120,128), z=21, parent=harvestFrame})
	harvestBar = mkFrame({name="Bar", size=UDim2.new(0,0,1,0), bg=C.HARVEST, r=4, z=22, parent=barBg})
	harvestPctLabel = mkLabel({name="Pct", text="0%", ts=13, font=F.TITLE, color=C.WHITE, z=23, parent=barBg})
	harvestNameLabel = mkLabel({name="Name", size=UDim2.new(1,0,0,18), pos=UDim2.new(0,0,0,30), text="", ts=12, color=C.GRAY, z=21, parent=harvestFrame})
end

----------------------------------------------------------------
-- 3. 핫바 — 하단 중앙, 원형 슬롯
----------------------------------------------------------------
local function createHotbar()
	local SZ, PAD, N = 52, 7, 8
	local W = N*SZ + (N-1)*PAD
	hotbarFrame = mkFrame({name="Hotbar", size=UDim2.new(0,W+16,0,SZ+16), pos=UDim2.new(0.5,0,1,-8), anchor=Vector2.new(0.5,1), bgT=1, parent=mainGui})
	for i=1,N do
		local x = 8+(i-1)*(SZ+PAD)
		local s = mkSlot({name="HB"..i, sz=SZ, pos=UDim2.new(0,x,0.5,0), z=2, parent=hotbarFrame})
		s.frame.AnchorPoint = Vector2.new(0,0.5)
		mkLabel({name="K", size=UDim2.new(0,14,0,12), pos=UDim2.new(0,4,0,3), text=tostring(i), ts=9, font=F.NUM, color=C.DIM, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, z=5, parent=s.frame})
		s.click.MouseButton1Click:Connect(function() UIManager.selectHotbarSlot(i) end)
		hotbarSlots[i] = s
	end
	UIManager.selectHotbarSlot(1)
end

----------------------------------------------------------------
-- 4. 퀵 액션 버튼 — 우측 하단 원형
----------------------------------------------------------------
local function createActionButtons()
	local acts = {
		{key="E", label="상호작용", y=-140},
		{key="C", label="제작", y=-85, fn=function() UIManager.toggleCrafting() end},
		{key="B", label="인벤토리", y=-30, fn=function() UIManager.toggleInventory() end},
	}
	for _, a in ipairs(acts) do
		local rect = mkFrame({name="Act"..a.key, size=UDim2.new(0,44,0,44), pos=UDim2.new(1,-18,1,a.y), anchor=Vector2.new(1,1), bg=C.BG_OVERLAY, bgT=0.4, r=8, stroke=1.5, strokeC=C.BORDER, z=3, parent=mainGui})
		mkLabel({text=a.key, ts=16, font=F.TITLE, color=C.GOLD, z=4, parent=rect})
		mkLabel({name="Tip", size=UDim2.new(0,60,0,12), pos=UDim2.new(0.5,0,1,2), anchor=Vector2.new(0.5,0), text=a.label, ts=8, color=C.DIM, z=4, parent=rect})
		if a.fn then
			local b = Instance.new("TextButton"); b.Size=UDim2.new(1,0,1,0); b.BackgroundTransparency=1; b.Text=""; b.ZIndex=5; b.Parent=rect
			local cr = Instance.new("UICorner"); cr.CornerRadius=UDim.new(0,8); cr.Parent=b
			b.MouseButton1Click:Connect(a.fn)
		end
	end
end

----------------------------------------------------------------
-- 5. 인벤토리 — 원형 슬롯 + 카테고리 탭 + 아이템 상세
----------------------------------------------------------------
local function createInventoryUI()
	local COLS, ROWS, SZ, GAP = 5, 4, 48, 8
	local gridW = COLS*SZ+(COLS-1)*GAP
	local TAB_W, DETAIL_W = 52, 160
	local PW = TAB_W + gridW + DETAIL_W + 50
	local PH = ROWS*SZ+(ROWS-1)*GAP + 80

	inventoryFrame = mkFrame({name="Inv", size=UDim2.new(0,PW,0,PH), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, bgT=0.06, r=10, stroke=1, strokeC=C.BORDER, vis=false, z=10, parent=mainGui})

	-- Title bar
	local tb = mkFrame({name="TB", size=UDim2.new(1,0,0,34), bg=C.BG_OVERLAY, bgT=0.3, r=10, z=10, parent=inventoryFrame})
	mkFrame({name="Fix", size=UDim2.new(1,0,0,10), pos=UDim2.new(0,0,1,-10), bg=C.BG_OVERLAY, bgT=0.3, z=10, parent=tb})
	mkLabel({text="인벤토리", ts=15, font=F.TITLE, color=C.WHITE, z=11, parent=tb})
	mkBtn({name="X", size=UDim2.new(0,26,0,26), pos=UDim2.new(1,-30,0.5,0), anchor=Vector2.new(0,0.5), text="X", ts=14, font=F.TITLE, bg=C.BTN_CLOSE, hbg=C.RED, r=4, z=12, fn=function() UIManager.closeInventory() end, parent=tb})

	-- Category tabs (left)
	local cats = {"전체","도구","재료","소모"}
	for ci, cat in ipairs(cats) do
		local btn = mkBtn({name="Cat"..ci, size=UDim2.new(0,TAB_W,0,28), pos=UDim2.new(0,6,0,40+(ci-1)*34), text=cat, ts=10, font=F.NORMAL, bg=ci==1 and C.BG_SLOT_SEL or C.BTN, hbg=C.BTN_H, r=4, z=11, parent=inventoryFrame})
		btn.MouseButton1Click:Connect(function()
			for _, cb in pairs(categoryButtons) do cb.BackgroundColor3 = C.BTN end
			btn.BackgroundColor3 = C.BG_SLOT_SEL
		end)
		categoryButtons[ci] = btn
	end

	-- Grid (center)
	local gridX = TAB_W + 18
	for row=0, ROWS-1 do
		for col=0, COLS-1 do
			local i = row*COLS+col+1
			local x = gridX + col*(SZ+GAP)
			local y = 44 + row*(SZ+GAP)
			local s = mkSlot({name="IS"..i, sz=SZ, pos=UDim2.new(0,x,0,y), z=11, parent=inventoryFrame})
			s.click.MouseButton1Click:Connect(function() UIManager._onInvSlotClick(i) end)
			invSlots[i] = s
		end
	end

	-- Detail panel (right)
	local dx = gridX + gridW + 14
	invDetailPanel = mkFrame({name="Detail", size=UDim2.new(0,DETAIL_W,0,PH-50), pos=UDim2.new(0,dx,0,40), bg=C.BG_PANEL_L, bgT=0.2, r=8, z=11, parent=inventoryFrame})
	mkLabel({name="DName", size=UDim2.new(1,-10,0,20), pos=UDim2.new(0,5,0,8), text="아이템 선택", ts=13, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, z=12, parent=invDetailPanel})
	local previewCircle = mkFrame({name="Preview", size=UDim2.new(0,70,0,70), pos=UDim2.new(0.5,0,0,38), anchor=Vector2.new(0.5,0), bg=C.BG_SLOT, r=35, stroke=1.5, strokeC=C.BORDER, z=12, parent=invDetailPanel})
	mkLabel({name="PName", size=UDim2.new(0.8,0,0.6,0), pos=UDim2.new(0.1,0,0.15,0), text="", ts=9, color=C.GRAY, wrap=true, z=13, parent=previewCircle})
	mkLabel({name="DCount", size=UDim2.new(1,-10,0,16), pos=UDim2.new(0,5,0,116), text="", ts=11, font=F.NUM, color=C.GRAY, ax=Enum.TextXAlignment.Left, z=12, parent=invDetailPanel})

	-- Action buttons
	mkBtn({name="BtnDrop", size=UDim2.new(0.45,0,0,28), pos=UDim2.new(0.02,0,1,-38), text="버리기", ts=11, bg=C.BTN, hbg=C.BTN_H, r=4, z=12, parent=invDetailPanel})
	mkBtn({name="BtnUse", size=UDim2.new(0.45,0,0,28), pos=UDim2.new(0.53,0,1,-38), text="사용", ts=11, bg=C.BTN_CRAFT, hbg=C.BTN_CRAFT_H, r=4, z=12, parent=invDetailPanel})
end

----------------------------------------------------------------
-- 6. 제작 UI — 풀스크린 블러 + 다이아몬드 그리드
----------------------------------------------------------------
local function createCraftingUI()
	-- Full-screen overlay
	craftingOverlay = mkFrame({name="CraftOverlay", size=UDim2.new(1,0,1,0), bg=C.BG_OVERLAY, bgT=0.35, vis=false, z=50, parent=mainGui})

	-- Top bar
	mkBtn({name="Back", size=UDim2.new(0,80,0,30), pos=UDim2.new(0,24,0,18), text="< 뒤로", ts=13, font=F.NORMAL, bg=C.BTN, hbg=C.BTN_H, r=6, z=52, fn=function() UIManager.closeCrafting() end, parent=craftingOverlay})
	mkLabel({name="Title", size=UDim2.new(0,200,0,30), pos=UDim2.new(0.5,0,0,18), anchor=Vector2.new(0.5,0), text="제작 메뉴", ts=20, font=F.TITLE, color=C.WHITE, z=52, parent=craftingOverlay})
	mkBtn({name="X", size=UDim2.new(0,32,0,32), pos=UDim2.new(1,-24,0,16), anchor=Vector2.new(1,0), text="X", ts=18, font=F.TITLE, bg=C.BTN_CLOSE, hbg=C.RED, r=6, z=52, fn=function() UIManager.closeCrafting() end, parent=craftingOverlay})

	-- Diamond grid container (ScrollingFrame)
	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Name = "DiamondGrid"
	gridScroll.Size = UDim2.new(0.7, 0, 0.55, 0)
	gridScroll.Position = UDim2.new(0.15, 0, 0.1, 0)
	gridScroll.BackgroundTransparency = 1
	gridScroll.BorderSizePixel = 0
	gridScroll.ScrollBarThickness = 4
	gridScroll.ScrollBarImageColor3 = C.BORDER
	gridScroll.CanvasSize = UDim2.new(0,0,0,0)
	gridScroll.ZIndex = 51
	gridScroll.Parent = craftingOverlay

	-- Craft button (right, large circle)
	local craftCircle = mkFrame({name="CraftBtn", size=UDim2.new(0,64,0,64), pos=UDim2.new(0.88,0,0.35,0), anchor=Vector2.new(0.5,0.5), bg=C.BTN_CRAFT, r=32, stroke=2, strokeC=C.GREEN, z=52, parent=craftingOverlay})
	mkLabel({text="⚒", ts=24, z=53, parent=craftCircle})
	mkLabel({name="CraftLabel", size=UDim2.new(0,50,0,16), pos=UDim2.new(0.5,0,1,6), anchor=Vector2.new(0.5,0), text="제작", ts=12, font=F.TITLE, color=C.WHITE, z=53, parent=craftCircle})
	local craftClickBtn = Instance.new("TextButton")
	craftClickBtn.Size=UDim2.new(1,10,1,10); craftClickBtn.Position=UDim2.new(0.5,0,0.5,0); craftClickBtn.AnchorPoint=Vector2.new(0.5,0.5)
	craftClickBtn.BackgroundTransparency=1; craftClickBtn.Text=""; craftClickBtn.ZIndex=54; craftClickBtn.Parent=craftCircle
	local cr = Instance.new("UICorner"); cr.CornerRadius=UDim.new(0.5,0); cr.Parent=craftClickBtn
	craftClickBtn.MouseButton1Click:Connect(function() UIManager._doCraft() end)

	-- Detail panel (bottom)
	craftDetailPanel = mkFrame({name="CraftDetail", size=UDim2.new(0.65,0,0,100), pos=UDim2.new(0.17,0,1,-20), anchor=Vector2.new(0,1), bg=C.BG_PANEL, bgT=0.15, r=8, stroke=1, strokeC=C.BORDER, z=52, parent=craftingOverlay})
	mkLabel({name="RName", size=UDim2.new(1,-16,0,22), pos=UDim2.new(0,8,0,6), text="레시피를 선택하세요", ts=14, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, z=53, parent=craftDetailPanel})
	mkLabel({name="RMats", size=UDim2.new(1,-16,0,50), pos=UDim2.new(0,8,0,30), text="", ts=11, color=C.GRAY, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, z=53, parent=craftDetailPanel})
	mkLabel({name="RTime", size=UDim2.new(0,100,0,18), pos=UDim2.new(1,-10,0,8), anchor=Vector2.new(1,0), text="", ts=11, font=F.NUM, color=C.DIM, ax=Enum.TextXAlignment.Right, z=53, parent=craftDetailPanel})
end

----------------------------------------------------------------
-- 7. 상점 UI (간소화)
----------------------------------------------------------------
local function createShopUI()
	shopFrame = mkFrame({name="Shop", size=UDim2.new(0,380,0,340), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_PANEL, r=10, stroke=1, strokeC=C.BORDER, vis=false, z=10, parent=mainGui})
	local tb = mkFrame({name="TB", size=UDim2.new(1,0,0,34), bg=C.BG_OVERLAY, bgT=0.3, r=10, z=10, parent=shopFrame})
	mkFrame({size=UDim2.new(1,0,0,10), pos=UDim2.new(0,0,1,-10), bg=C.BG_OVERLAY, bgT=0.3, z=10, parent=tb})
	mkLabel({text="🏪 상점", ts=15, font=F.TITLE, color=C.WHITE, z=11, parent=tb})
	mkBtn({name="X", size=UDim2.new(0,26,0,26), pos=UDim2.new(1,-30,0.5,0), anchor=Vector2.new(0,0.5), text="X", ts=14, font=F.TITLE, bg=C.BTN_CLOSE, hbg=C.RED, r=4, z=12, fn=function() UIManager.closeShop() end, parent=tb})
	mkLabel({name="Gold", size=UDim2.new(0,100,0,24), pos=UDim2.new(0,10,0.5,0), anchor=Vector2.new(0,0.5), text="💰 0", ts=13, font=F.NUM, color=C.GOLD, ax=Enum.TextXAlignment.Left, z=11, parent=tb})
end

----------------------------------------------------------------
-- 8. 상호작용 프롬프트
----------------------------------------------------------------
local function createInteractPrompt()
	interactPrompt = mkFrame({name="Prompt", size=UDim2.new(0,170,0,38), pos=UDim2.new(0.5,0,0.65,0), anchor=Vector2.new(0.5,0.5), bg=C.BG_OVERLAY, bgT=0.35, r=8, stroke=1, strokeC=C.BORDER, vis=false, z=5, parent=mainGui})
	mkLabel({text="[E] 상호작용", ts=13, color=C.WHITE, z=6, parent=interactPrompt})
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

function UIManager.updateGold(amt)
	if shopFrame then
		local g = shopFrame:FindFirstChild("TB")
		if g then g = g:FindFirstChild("Gold"); if g then g.Text = "💰 "..tostring(amt) end end
	end
end

----------------------------------------------------------------
-- Public API: Hotbar
----------------------------------------------------------------
function UIManager.selectHotbarSlot(idx)
	if hotbarSlots[selectedSlot] then
		local st = hotbarSlots[selectedSlot].frame:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.BORDER; st.Thickness = 1.5 end
	end
	selectedSlot = idx
	if hotbarSlots[idx] then
		local st = hotbarSlots[idx].frame:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.GOLD; st.Thickness = 2.5 end
	end
end

function UIManager.refreshHotbar()
	local items = InventoryController.getItems()
	for i=1,8 do
		local s = hotbarSlots[i]
		if s then
			local item = items[i]
			if item and item.itemId then
				s.nameLabel.Text = item.itemId
				s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
			else
				s.icon.Image = ""; s.nameLabel.Text = ""; s.countLabel.Text = ""
			end
		end
	end
end

----------------------------------------------------------------
-- Public API: Inventory
----------------------------------------------------------------
function UIManager.openInventory()
	if isInvOpen then return end
	isInvOpen = true; inventoryFrame.Visible = true; InputManager.setUIOpen(true)
	UIManager.refreshInventory()
	inventoryFrame.Position = UDim2.new(0.5,0,0.58,0)
	TweenService:Create(inventoryFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back), {Position=UDim2.new(0.5,0,0.5,0)}):Play()
end

function UIManager.closeInventory()
	if not isInvOpen then return end
	TweenService:Create(inventoryFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isInvOpen = false; inventoryFrame.Visible = false
		if not isShopOpen and not isCraftOpen then InputManager.setUIOpen(false) end
	end)
end

function UIManager.toggleInventory()
	if isInvOpen then UIManager.closeInventory() else UIManager.openInventory() end
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	for i, s in pairs(invSlots) do
		local item = items[i]
		if item and item.itemId then
			s.nameLabel.Text = item.itemId
			s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
			s.frame.BackgroundColor3 = C.BG_SLOT
		else
			s.icon.Image = ""; s.nameLabel.Text = ""; s.countLabel.Text = ""
			s.frame.BackgroundColor3 = C.BG_SLOT
		end
	end
	UIManager.refreshHotbar()
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
	local item = items[idx]
	local dName = invDetailPanel:FindFirstChild("DName")
	local pName = invDetailPanel:FindFirstChild("Preview") and invDetailPanel.Preview:FindFirstChild("PName")
	local dCount = invDetailPanel:FindFirstChild("DCount")
	if item and item.itemId then
		if dName then dName.Text = item.itemId end
		if pName then pName.Text = item.itemId end
		if dCount then dCount.Text = "수량: "..(item.count or 1) end
	else
		if dName then dName.Text = "빈 슬롯" end
		if pName then pName.Text = "" end
		if dCount then dCount.Text = "" end
	end
end

function UIManager.onInventorySlotClick(idx)
	UIManager._onInvSlotClick(idx)
end

----------------------------------------------------------------
-- Public API: Crafting
----------------------------------------------------------------
function UIManager.openCrafting()
	if isCraftOpen then return end
	isCraftOpen = true; craftingOverlay.Visible = true; InputManager.setUIOpen(true)
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
		if not isInvOpen and not isShopOpen then InputManager.setUIOpen(false) end
	end)
end

function UIManager.toggleCrafting()
	if isCraftOpen then UIManager.closeCrafting() else UIManager.openCrafting() end
end

function UIManager.refreshCrafting()
	local grid = craftingOverlay:FindFirstChild("DiamondGrid")
	if not grid then return end
	for _, ch in pairs(grid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	craftDiamonds = {}; selectedRecipeId = nil
	-- Detail 초기화
	local rn = craftDetailPanel:FindFirstChild("RName"); if rn then rn.Text = "레시피를 선택하세요" end
	local rm = craftDetailPanel:FindFirstChild("RMats"); if rm then rm.Text = "" end
	local rt = craftDetailPanel:FindFirstChild("RTime"); if rt then rt.Text = "" end

	task.spawn(function()
		local ok, data = NetClient.Request("Recipe.List.Request", {})
		if not ok or not data or not data.data or not data.data.recipes then return end
		local recipes = data.data.recipes
		local playerItems = InventoryController.getItems()

		-- Diamond layout constants
		local DSZ = 58
		local DSPACE = 30
		local BOUND = DSZ * 1.42
		local STEP_X = BOUND + DSPACE
		local STEP_Y = BOUND * 0.8 + DSPACE * 0.5
		local COLS = 4
		local startX = (grid.AbsoluteSize.X > 0 and grid.AbsoluteSize.X or 500) / 2 - (COLS * STEP_X) / 2 + STEP_X/2

		for idx, recipe in ipairs(recipes) do
			local row = math.floor((idx-1) / COLS)
			local col = (idx-1) % COLS
			local x = startX + col * STEP_X + (row % 2 == 1 and STEP_X/2 or 0)
			local y = 50 + row * STEP_Y

			-- Check materials
			local canCraft = true
			local matsText = ""
			if recipe.inputs then
				for _, inp in ipairs(recipe.inputs) do
					local have = 0
					for _, slot in pairs(playerItems) do
						if slot and slot.itemId == inp.itemId then have = have + (slot.count or 0) end
					end
					local ok2 = have >= inp.count
					if not ok2 then canCraft = false end
					matsText = matsText .. string.format("%s%s x%d(%d)  ", ok2 and "✓" or "✗", inp.itemId, inp.count, have)
				end
			end

			-- Diamond frame
			local df = mkFrame({name="D"..idx, size=UDim2.new(0,DSZ,0,DSZ), pos=UDim2.new(0,x,0,y), anchor=Vector2.new(0.5,0.5), bg=C.DIAMOND, r=6, stroke=1.5, strokeC=canCraft and C.DIAMOND_BD or Color3.fromRGB(60,40,40), z=52, parent=grid})
			df.Rotation = 45

			-- Inner (counter-rotate)
			local inner = mkFrame({name="In", size=UDim2.new(0.82,0,0.82,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), bgT=1, z=53, parent=df})
			inner.Rotation = -45
			mkLabel({text=recipe.name or recipe.id, ts=8, color=canCraft and C.WHITE or C.DIM, wrap=true, z=54, parent=inner})

			-- Lock overlay
			if not canCraft and (recipe.techLevel or 0) > 0 then
				local lockLbl = mkLabel({name="Lock", size=UDim2.new(1,0,1,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), text="🔒", ts=18, z=55, parent=df})
				lockLbl.Rotation = -45
				df.BackgroundTransparency = 0.4
			end

			-- Click
			local btn = Instance.new("TextButton")
			btn.Size=UDim2.new(1.2,0,1.2,0); btn.Position=UDim2.new(0.5,0,0.5,0); btn.AnchorPoint=Vector2.new(0.5,0.5)
			btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=56; btn.Parent=df
			btn.MouseButton1Click:Connect(function()
				-- Deselect previous
				for _, d in pairs(craftDiamonds) do
					local st = d.frame:FindFirstChildOfClass("UIStroke")
					if st then st.Color = d.canCraft and C.DIAMOND_BD or Color3.fromRGB(60,40,40) end
				end
				-- Select
				local st = df:FindFirstChildOfClass("UIStroke")
				if st then st.Color = C.DIAMOND_SEL; st.Thickness = 2.5 end
				selectedRecipeId = recipe.id
				-- Update detail
				if rn then rn.Text = recipe.name or recipe.id end
				if rm then rm.Text = matsText end
				if rt then rt.Text = recipe.craftTime and (recipe.craftTime.."초") or "즉시" end
			end)

			craftDiamonds[recipe.id] = {frame=df, canCraft=canCraft, recipe=recipe}
		end

		-- Canvas size
		local totalRows = math.ceil(#recipes / COLS)
		grid.CanvasSize = UDim2.new(0,0,0, totalRows * STEP_Y + 100)
	end)
end

function UIManager._doCraft()
	if not selectedRecipeId then return end
	task.spawn(function()
		local ok, data = NetClient.Request("Craft.Start.Request", {recipeId = selectedRecipeId})
		if ok then
			print("[UIManager] Craft:", selectedRecipeId)
			task.delay(0.5, function() if isCraftOpen then UIManager.refreshCrafting() end end)
		else
			warn("[UIManager] Craft fail:", tostring(data))
		end
	end)
end

----------------------------------------------------------------
-- Public API: Shop
----------------------------------------------------------------
function UIManager.openShop(shopId)
	if isShopOpen then return end
	isShopOpen = true; shopFrame.Visible = true; InputManager.setUIOpen(true)
	shopFrame.Position = UDim2.new(0.5,0,0.58,0)
	TweenService:Create(shopFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back), {Position=UDim2.new(0.5,0,0.5,0)}):Play()
end

function UIManager.closeShop()
	if not isShopOpen then return end
	TweenService:Create(shopFrame, TweenInfo.new(0.12), {Position=UDim2.new(0.5,0,0.54,0)}):Play()
	task.delay(0.12, function()
		isShopOpen = false; shopFrame.Visible = false
		if not isInvOpen and not isCraftOpen then InputManager.setUIOpen(false) end
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

----------------------------------------------------------------
-- Event Listeners
----------------------------------------------------------------
local function setupEventListeners()
	InventoryController.onChanged(function()
		if isInvOpen then UIManager.refreshInventory() end
		UIManager.refreshHotbar()
	end)
	ShopController.onGoldChanged(function(g) UIManager.updateGold(g) end)

	-- Hotbar number keys
	local hotbarKeys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight}
	for i = 1, 8 do
		InputManager.bindKey(hotbarKeys[i], "HB"..i, function() UIManager.selectHotbarSlot(i) end)
	end

	-- Stats event
	if NetClient.On then
		NetClient.On("Player.Stats.Changed", function(d)
			if d then
				if d.level then UIManager.updateLevel(d.level) end
				if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
				if d.leveledUp then print(string.format("[UIManager] 🎉 Level Up! Lv. %d", d.level)) end
			end
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
		if ok and d and d.data then
			if d.data.level then UIManager.updateLevel(d.data.level) end
			if d.data.currentXP and d.data.requiredXP then UIManager.updateXP(d.data.currentXP, d.data.requiredXP) end
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
	createCraftingUI()
	createShopUI()
	createInteractPrompt()

	setupEventListeners()

	UIManager.updateHealth(100,100)
	UIManager.updateStamina(100,100)
	UIManager.updateXP(0,100)
	UIManager.updateLevel(1)

	initialized = true
	print("[UIManager] Initialized — Durango-style UI")
end

return UIManager
