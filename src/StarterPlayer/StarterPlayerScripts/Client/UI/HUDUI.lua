local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local HUDUI = {}
local Controllers = script.Parent.Parent:WaitForChild("Controllers")

-- [에셋 참조] 하드코딩 방지를 위한 폴더 경로
local Assets = ReplicatedStorage:WaitForChild("Assets")
local StatusIcons = Assets:WaitForChild("StatusIcons")


HUDUI.Refs = {
	harvestPct = nil,
	harvestName = nil,
	interactPrompt = nil,
}

function HUDUI.Init(parent, UIManager, InputManager, isMobile)
	local isSmall = isMobile 
	
	-- [Top Left Area] - HP, Stamina, Status Effects
	local topLeftFrame = Utils.mkFrame({
		name = "TopLeftHUD",
		size = UDim2.new(0, isSmall and 260 or 240, 0, 110), -- 110으로 확장
		pos = UDim2.new(0, isSmall and 60 or 180, 0, isSmall and 40 or 20), -- 로블록스 기본 UI 회피 (우측 이동)
		bgT = 1,
		parent = parent
	})
	HUDUI.Refs.statusPanel = topLeftFrame

	local statusList = Instance.new("UIListLayout")
	statusList.Padding = UDim.new(0, 4)
	statusList.SortOrder = Enum.SortOrder.LayoutOrder
	statusList.Parent = topLeftFrame

	-- HP Bar (LayoutOrder 1)
	HUDUI.Refs.healthBar = Utils.mkBar({
		name = "HP",
		size = UDim2.new(1, 0, 0, 16),
		fillC = C.HP,
		r = 6,
		parent = topLeftFrame
	})
	HUDUI.Refs.healthBar.container.LayoutOrder = 1
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

	-- Stamina Bar (LayoutOrder 2)
	HUDUI.Refs.staminaBar = Utils.mkBar({
		name = "STA",
		size = UDim2.new(1, 0, 0, 16), 
		fillC = C.GOLD,
		r = 6,
		parent = topLeftFrame
	})
	HUDUI.Refs.staminaBar.container.LayoutOrder = 2
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

	-- Hunger Bar (LayoutOrder 3)
	HUDUI.Refs.hungerBar = Utils.mkBar({
		name = "HUNGER",
		size = UDim2.new(1, -20, 0, 14), -- 약간 짧고 얇게 조정
		fillC = C.XP, -- 기본 색상: 초록색
		r = 6,
		parent = topLeftFrame
	})
	HUDUI.Refs.hungerBar.container.LayoutOrder = 3
	local hunDecay = Utils.mkFrame({
		name = "Decay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(1, 1, 1),
		bgT = 0.5,
		r = 6,
		z = HUDUI.Refs.hungerBar.fill.ZIndex - 1,
		parent = HUDUI.Refs.hungerBar.container
	})
	HUDUI.Refs.hunDecay = hunDecay
	HUDUI.Refs.hungerBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.hungerBar.label.Position = UDim2.new(0, 5, 0, 0)
	HUDUI.Refs.hungerBar.label.Text = "100 / 100"

	-- Status Effect Icons Container (LayoutOrder 4)
	local effectList = Utils.mkFrame({name="EffectList", size=UDim2.new(1,0,0,30), bgT=1, parent=topLeftFrame})
	effectList.LayoutOrder = 4
	local eLayout = Instance.new("UIListLayout"); eLayout.FillDirection=Enum.FillDirection.Horizontal; eLayout.Padding=UDim.new(0,5); eLayout.Parent=effectList
	HUDUI.Refs.effectList = effectList
	
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
		size = UDim2.new(0, isSmall and 300 or 240, 0, isSmall and 150 or 120),
		pos = UDim2.new(1, -20, 1, -20),
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = parent
	})
	
	-- Hexagonal Buttons Data: Attack, Dodge, Jump, Sprint (Action Cluster)
	local hScale = isSmall and 1.25 or 1.0
	local hexBtns = {
		{id="Attack", icon="rbxassetid://10452331908", pos=UDim2.new(1, -70 * hScale, 0.5, 30), size=95 * hScale},
		{id="Dodge", icon="rbxassetid://6034346917", pos=UDim2.new(1, -15 * hScale, 0.5, 45), size=65 * hScale}, -- 구르기 (오른쪽 아래)
		{id="Jump", icon="rbxassetid://6034335017", pos=UDim2.new(1, -135 * hScale, 0.5, 95), size=65 * hScale}, -- 점프 (왼쪽 아래)
		{id="Sprint", icon="rbxassetid://6034440026", pos=UDim2.new(1, -75 * hScale, 0.5, 115), size=60 * hScale}, -- 달리기 (중앙 아래)
	}
	
	-- Interact button separated (higher, above hotbar or near interaction area)
	local interactBtn = Utils.mkHexBtn({
		name = "Interact",
		size = UDim2.new(0, 75 * hScale, 0, 75 * hScale),
		pos = UDim2.new(1, -180 * hScale, 0.5, -20),
		anchor = Vector2.new(0.5, 0.5),
		stroke = true,
		parent = actionArea
	})
	local intIcon = Instance.new("ImageLabel")
	intIcon.Size = UDim2.new(0.55, 0, 0.55, 0); intIcon.Position = UDim2.new(0.5, 0, 0.5, 0); intIcon.AnchorPoint = Vector2.new(0.5, 0.5); intIcon.BackgroundTransparency = 1; intIcon.Image = "rbxassetid://6034805332"; intIcon.Parent = interactBtn
	HUDUI.Refs.hex_Interact = interactBtn
	
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
		size = UDim2.new(1, 0, 0, isSmall and 40 or 30),
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
	HUDUI.Refs.bagBtn = Utils.mkBtn({text=isSmall and "🎒" or "소지품(B)", size=UDim2.new(0, isSmall and 60 or 100, 1, 0), bgT=1, ts=isSmall and 24 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleInventory() end, parent=bottomEdge})
	HUDUI.Refs.buildBtn = Utils.mkBtn({text=isSmall and "🏗" or "건축(C)", size=UDim2.new(0, isSmall and 60 or 80, 1, 0), bgT=1, ts=isSmall and 24 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleBuild() end, parent=bottomEdge})
	HUDUI.Refs.equipBtn = Utils.mkBtn({text=isSmall and "👕" or "장비(E)", size=UDim2.new(0, isSmall and 60 or 80, 1, 0), bgT=1, ts=isSmall and 24 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleEquipment() end, parent=bottomEdge})
	HUDUI.Refs.techBtn = Utils.mkBtn({text=isSmall and "📜" or "기술(K)", size=UDim2.new(0, isSmall and 60 or 80, 1, 0), bgT=1, ts=isSmall and 24 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleTechTree() end, parent=bottomEdge})
	HUDUI.Refs.collectionBtn = Utils.mkBtn({text=isSmall and "📖" or "도감(P)", size=UDim2.new(0, isSmall and 60 or 80, 1, 0), bgT=1, ts=isSmall and 24 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleCollection() end, parent=bottomEdge})


	HUDUI.Refs.levelLabel = Utils.mkLabel({text="Lv. 1    0.0%", size=UDim2.new(0, isSmall and 100 or 150, 1, 0), ts=12, color=C.GRAY, parent=bottomEdge})

	-- [Hotbar] (Center Bottom)
	local hotbarSize = isSmall and 480 or 410
	local hotbarFrame = Utils.mkFrame({
		name = "Hotbar",
		size = UDim2.new(0, hotbarSize, 0, isSmall and 60 or 50),
		pos = UDim2.new(0.5, 0, 1, isSmall and -50 or -35),
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
			size = UDim2.new(0, isSmall and 55 or 45, 0, isSmall and 55 or 45),
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
		stroke = 2,
		strokeC = C.BORDER,
		parent = parent
	})
	HUDUI.Refs.minimap = minimap
	
	-- North Indicator
	local north = Utils.mkLabel({
		text = "N",
		size = UDim2.new(0, 20, 0, 20),
		pos = UDim2.new(0.5, 0, 0.1, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 14,
		bold = true,
		color = C.RED,
		parent = minimap
	})
	HUDUI.Refs.northIndicator = north
	
	local coordLabel = Utils.mkLabel({
		text = "X: 0  Z: 0",
		pos = UDim2.new(0.5, 0, 1, 10),
		anchor = Vector2.new(0.5, 0),
		size = UDim2.new(1, 0, 0, 20),
		ts = 12,
		color = C.WHITE,
		parent = minimap
	})
	HUDUI.Refs.coordLabel = coordLabel

	-- Action Bindings Connect to Controller directly
	InputManager.bindAction("Interact", function() 
		local IC = require(Controllers.InteractController)
		if IC.interact then IC.interact() end
	end, false, "상호작용", Enum.KeyCode.Z)
	HUDUI.Refs.hex_Interact.MouseButton1Click:Connect(function() local IC = require(Controllers.InteractController); if IC.interact then IC.interact() end end)
	
	InputManager.bindAction("Attack", function()
		local CC = require(Controllers.CombatController)
		if CC.attack then CC.attack() end
	end, false, "공격", Enum.UserInputType.MouseButton1)
	HUDUI.Refs.hex_Attack.MouseButton1Click:Connect(function() local CC = require(Controllers.CombatController); if CC.attack then CC.attack() end end)

	-- Dodge & Sprint & Jump (Mobile Bindings)
	HUDUI.Refs.hex_Dodge.MouseButton1Click:Connect(function() 
		local MC = require(Controllers.MovementController)
		if MC.performDodge then MC.performDodge() end -- Ensure function exists or use shared trigger
	end)
	
	HUDUI.Refs.hex_Jump.MouseButton1Click:Connect(function()
		local hum = player.Character and player.Character:FindFirstChild("Humanoid")
		if hum then hum.Jump = true end
	end)
	
	HUDUI.Refs.hex_Sprint.MouseButton1Down:Connect(function() 
		local MC = require(Controllers.MovementController)
		if MC.updateSprintState then MC.updateSprintState(true) end
	end)
	HUDUI.Refs.hex_Sprint.MouseButton1Up:Connect(function() 
		local MC = require(Controllers.MovementController)
		if MC.updateSprintState then MC.updateSprintState(false) end
	end)

	InputManager.bindAction("Equipment", function() UIManager.toggleEquipment() end, false, "장비창", Enum.KeyCode.E)
	InputManager.bindAction("Character", function() UIManager.toggleInventory() end, false, "캐릭터", Enum.KeyCode.B, Enum.KeyCode.Tab, Enum.KeyCode.I)
	InputManager.bindAction("Building", function() UIManager.toggleBuild() end, false, "건축", Enum.KeyCode.C)
	-- [수정] K키 직접 진입 폐기. 기술 연구소 시설 상호작용으로 이전.
	-- InputManager.bindAction("TechTree", function() UIManager.toggleTechTree() end, false, "기술", Enum.KeyCode.K)
	InputManager.bindAction("Collection", function() UIManager.toggleCollection() end, false, "도감", Enum.KeyCode.P)
	InputManager.bindAction("CloseUI", function()
		UIManager.closeInventory()
		UIManager.closeCrafting()
		UIManager.closeEquipment()
		UIManager.closeTechTree()
		UIManager.closeBuild()
		UIManager.closeCollection()
	end, false, nil, Enum.KeyCode.Escape)

	-- Harvest Setup
	HUDUI.Refs.harvestFrame = Utils.mkFrame({name="Harvest", size=UDim2.new(0, 300, 0, 60), pos=UDim2.new(0.4, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bgT=1, vis=false, parent=parent})
	local hBar = Utils.mkBar({size=UDim2.new(1, 0, 0, 6), pos=UDim2.new(0.5, 0, 0, 30), anchor=Vector2.new(0.5, 0), fillC=C.WHITE, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestBar = hBar.fill
	HUDUI.Refs.harvestName = Utils.mkLabel({text="채집 중...", size=UDim2.new(1, 0, 0, 25), ts=16, bold=true, rich=true, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestPct = Utils.mkLabel({text="0%", size=UDim2.new(1, 0, 0, 20), pos=UDim2.new(0.5, 0, 0, 45), anchor=Vector2.new(0.5, 0), ts=14, color=C.GOLD, parent=HUDUI.Refs.harvestFrame})

	-- =============================================
	-- HUD 바 툴팁 (마우스 호버 시 설명창)
	-- =============================================
	local tooltip = Instance.new("Frame")
	tooltip.Name = "HUDTooltip"
	tooltip.Size = UDim2.new(0, 210, 0, 80)
	tooltip.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	tooltip.BackgroundTransparency = 0.1
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 9500
	tooltip.Visible = false
	tooltip.Parent = parent

	local tipCorner = Instance.new("UICorner")
	tipCorner.CornerRadius = UDim.new(0, 10)
	tipCorner.Parent = tooltip

	local tipStroke = Instance.new("UIStroke")
	tipStroke.Color = Color3.fromRGB(255, 220, 100)
	tipStroke.Thickness = 1.5
	tipStroke.Transparency = 0.4
	tipStroke.Parent = tooltip

	local tipTitle = Instance.new("TextLabel")
	tipTitle.Name = "Title"
	tipTitle.Size = UDim2.new(1, -20, 0, 30)
	tipTitle.Position = UDim2.new(0, 10, 0, 5)
	tipTitle.BackgroundTransparency = 1
	tipTitle.TextColor3 = Color3.fromRGB(255, 230, 80)
	tipTitle.TextSize = 16
	tipTitle.Font = Enum.Font.GothamBold
	tipTitle.TextXAlignment = Enum.TextXAlignment.Left
	tipTitle.ZIndex = 9501
	tipTitle.Parent = tooltip

	local tipBody = Instance.new("TextLabel")
	tipBody.Name = "Body"
	tipBody.Size = UDim2.new(1, -20, 1, -40)
	tipBody.Position = UDim2.new(0, 10, 0, 35)
	tipBody.BackgroundTransparency = 1
	tipBody.TextColor3 = Color3.fromRGB(220, 220, 220)
	tipBody.TextSize = 13
	tipBody.Font = Enum.Font.Gotham
	tipBody.TextXAlignment = Enum.TextXAlignment.Left
	tipBody.TextYAlignment = Enum.TextYAlignment.Top
	tipBody.TextWrapped = true
	tipBody.ZIndex = 9501
	tipBody.Parent = tooltip

	HUDUI.Refs.tooltip = tooltip
	HUDUI.Refs.tipTitle = tipTitle
	HUDUI.Refs.tipBody = tipBody

	-- 툴팁 데이터
	local barData = {
		[HUDUI.Refs.healthBar.container] = {
			title = "❤️ 생명력 (Health)",
			body  = "캐릭터의 생존력을 나타냅니다.\n0이 되면 사망하여 리스폰됩니다.\n음식이나 치료제로 회복할 수 있습니다.",
		},
		[HUDUI.Refs.staminaBar.container] = {
			title = "⚡ 기력 (Stamina)",
			body  = "구르기, 달리기, 수영 등 활동 시 소모됩니다.\n소모된 기력은 가만히 있으면 자동으로 회복됩니다.",
		},
		[HUDUI.Refs.hungerBar.container] = {
			title = "🍖 허기 (Hunger)",
			body  = "시간이 지남에 따라 점차 감소합니다.\n배고픔이 0이 되면 체력이 서서히 감소합니다.\n다양한 음식을 먹어 채워야 합니다.",
		},
	}

	local UserInputService = game:GetService("UserInputService")
	
	for container, data in pairs(barData) do
		if not container then continue end
		
		-- 투명 버튼을 위에 덮어서 호버 감지 (안정적 렌더링)
		local overlay = Instance.new("TextButton")
		overlay.Name = "TooltipTrigger"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundTransparency = 1
		overlay.Text = ""
		overlay.ZIndex = container.ZIndex + 100
		overlay.Parent = container

		overlay.MouseEnter:Connect(function()
			HUDUI.Refs.tipTitle.Text = data.title
			HUDUI.Refs.tipBody.Text = data.body
			-- 텍스트 길이에 맞춰 높이 조정
			local lines = select(2, data.body:gsub("\n", "\n")) + 1
			HUDUI.Refs.tooltip.Size = UDim2.new(0, 210, 0, 50 + lines * 16)
			HUDUI.Refs.tooltip.Visible = true
		end)

		overlay.MouseLeave:Connect(function()
			HUDUI.Refs.tooltip.Visible = false
		end)
	end

	-- 툴팁이 마우스를 따라다니게 처리
	RunService.RenderStepped:Connect(function()
		if tooltip.Visible then
			local mousePos = UserInputService:GetMouseLocation()
			local uiScale = parent:FindFirstChildOfClass("UIScale")
			local scale = uiScale and uiScale.Scale or 1
			
			-- 마우스 오른쪽 아래에 배치
			tooltip.Position = UDim2.new(0, mousePos.X / scale + 15, 0, (mousePos.Y - 36) / scale + 15)
		end
	end)
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

function HUDUI.UpdateHunger(cur, max)
	local bar = HUDUI.Refs.hungerBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.hunDecay then TweenService:Create(HUDUI.Refs.hunDecay, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
	
	-- 배고픔 수치에 따른 색상 변화 (초록 -> 노랑 -> 빨강)
	if r > 0.5 then
		bar.fill.BackgroundColor3 = C.XP -- 초록
	elseif r > 0.25 then
		bar.fill.BackgroundColor3 = C.GOLD_SEL -- 노랑
	else
		bar.fill.BackgroundColor3 = C.HP -- 빨강
	end
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

function HUDUI.UpdateStatusEffects(debuffList)
	local container = HUDUI.Refs.effectList
	if not container then return end
	
	-- Clear existing (except stat alert)
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("GuiObject") and ch ~= HUDUI.Refs.statPointAlert then
			ch:Destroy()
		end
	end
	
	-- 에셋 타입 호환성 체크 (Decal은 Texture, ImageLabel은 Image 속성 사용)
	local function getIcon(name)
		local asset = StatusIcons:FindFirstChild(name)
		if not asset then return "" end
		if asset:IsA("Decal") then return asset.Texture end
		if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then return asset.Image end
		return ""
	end

	local IconMap = {
		FREEZING    = getIcon("FREEZING"), 
		BLOOD_SMELL = getIcon("BLOOD_SMELL"), 
		BURNING     = getIcon("BURNING"),
		CHILLY      = getIcon("CHILLY"),
		WARMTH      = getIcon("WARMTH"),
	}
	
	for _, debuff in ipairs(debuffList) do
		local iconId = IconMap[debuff.id] or "rbxassetid://6034346917"
		local isBuff = (debuff.id == "WARMTH") -- 굳이 복잡하게 안하고 하드코딩

		local slot = Utils.mkFrame({
			name = debuff.id,
			size = UDim2.new(0, 26, 0, 26),
			bg = isBuff and Color3.fromRGB(0, 40, 0) or Color3.fromRGB(40, 0, 0), 
			bgT = 0.4,
			r = 4,
			stroke = 1,
			strokeC = isBuff and Color3.fromRGB(100, 255, 100) or C.RED,
			parent = container
		})
		
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(0.8, 0, 0.8, 0)
		img.Position = UDim2.new(0.5, 0, 0.5, 0)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.BackgroundTransparency = 1
		img.Image = iconId
		img.ImageColor3 = C.WHITE
		img.Parent = slot
		
		-- Hover Tooltip per Icon
		local btn = Instance.new("TextButton")
		btn.Name = "TipBtn"
		btn.Size = UDim2.new(1,0,1,0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Parent = slot

		btn.MouseEnter:Connect(function()
			if HUDUI.Refs.tooltip then
				HUDUI.Refs.tipTitle.Text = debuff.name or debuff.id
				HUDUI.Refs.tipBody.Text = debuff.description or ""
				local lines = select(2, (debuff.description or ""):gsub("\n", "\n")) + 1
				HUDUI.Refs.tooltip.Size = UDim2.new(0, 210, 0, 50 + lines * 16)
				HUDUI.Refs.tooltip.Visible = true
			end
		end)

		btn.MouseLeave:Connect(function()
			if HUDUI.Refs.tooltip then
				HUDUI.Refs.tooltip.Visible = false
			end
		end)
	end
end

function HUDUI.UpdateCoordinates(x, z)
	if HUDUI.Refs.coordLabel then
		HUDUI.Refs.coordLabel.Text = string.format("X: %.0f  Z: %.0f", x, z)
	end
end

function HUDUI.UpdateCompass(angle)
	local north = HUDUI.Refs.northIndicator
	if north then
		-- HUD UI Rotation (Angle is in radians from Camera)
		local radius = 50 -- Minimap size is 120, radius 60, indicator at 50
		local x = 0.5 + math.sin(angle) * 0.4
		local y = 0.5 + math.cos(angle) * 0.4
		north.Position = UDim2.new(x, 0, y, 0)
	end
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
