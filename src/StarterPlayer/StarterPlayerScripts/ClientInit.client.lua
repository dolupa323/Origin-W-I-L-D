-- ClientInit.client.lua
-- 클라이언트 초기화 스크립트

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")

local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UIManager = require(Client.UIManager)

-- NetClient 초기화
local success = NetClient.Init()

if success then
	-- InputManager 초기화 (키 바인딩)
	InputManager.Init()
	
	-- WorldDropController 초기화 (이벤트 소비자)
	local WorldDropController = require(Controllers.WorldDropController)
	WorldDropController.Init()
	
	-- InventoryController 초기화 (이벤트 소비자)
	local InventoryController = require(Controllers.InventoryController)
	InventoryController.Init()
	
	-- TimeController 초기화 (이벤트 소비자)
	local TimeController = require(Controllers.TimeController)
	TimeController.Init()
	
	-- StorageController 초기화 (이벤트 소비자)
	local StorageController = require(Controllers.StorageController)
	StorageController.Init()
	
	-- BuildController 초기화 (이벤트 소비자)
	local BuildController = require(Controllers.BuildController)
	BuildController.Init()
	
	-- CraftController 초기화 (이벤트 소비자)
	local CraftController = require(Controllers.CraftController)
	CraftController.Init()
	
	-- FacilityController 초기화 (이벤트 소비자)
	local FacilityController = require(Controllers.FacilityController)
	FacilityController.Init()

	-- ShopController 초기화 (Phase 9)
	local ShopController = require(Controllers.ShopController)
	ShopController.Init()
	
	
	-- CombatController 초기화 (공격 시스템)
	local CombatController = require(Controllers.CombatController)
	CombatController.Init()
	
	-- InteractController 초기화 (채집/상호작용)
	local InteractController = require(Controllers.InteractController)
	InteractController.Init()
	
	-- MovementController 초기화 (스프린트/구르기)
	local MovementController = require(Controllers.MovementController)
	MovementController.Init()
	
	-- ResourceUIController 초기화 (노드 HP 바)
	local ResourceUIController = require(Controllers.ResourceUIController)
	ResourceUIController.Init()
	
	-- VirtualizationController 초기화 (성능 최적화: 가상화)
	local VirtualizationController = require(Controllers.VirtualizationController)
	VirtualizationController.Init()

	-- CreatureAnimationController 초기화 (공룡 애니메이션)
	local CreatureAnimationController = require(Controllers.CreatureAnimationController)
	CreatureAnimationController.Init()

	-- AttackIndicatorController 초기화 (크리처 텔레그래프 범위 표시)
	local AttackIndicatorController = require(Controllers.AttackIndicatorController)
	AttackIndicatorController.Init()
	
	-- [REMOVED] CreatureHealthUIController — 레거시 흰색 이름+초록 HP바 박스 제거
	-- 크리처 HP/Torpor 정보는 별도 UI로 대체됨
	
	-- [추가] HitFeedbackController 초기화 (피격 연출 및 물리 보정)
	local HitFeedbackController = require(Controllers.HitFeedbackController)
	HitFeedbackController.Init()
	
	-- [추가] DamageUIController 초기화 (부동 데미지 텍스트)
	local DamageUIController = require(Controllers.DamageUIController)
	DamageUIController.Init()

	-- SkillController 초기화 (스킬 트리 데이터)
	local SkillController = require(Controllers.SkillController)
	SkillController.Init()

	-- SkillEffectController 초기화 (스킬 VFX/사운드/애니메이션 연출)
	local SkillEffectController = require(Controllers.SkillEffectController)
	SkillEffectController.Init()
	
	-- [추가] PromptUI 초기화 (커스텀 ProximityPrompt)
	local PromptUI = require(Client:WaitForChild("UI"):WaitForChild("PromptUI"))
	PromptUI.Init()
	
	-- UIManager 초기화 (UI 생성 - 컨트롤러들 초기화 후)
	UIManager.Init()

	-- TutorialController 초기화 (첫 진입 튜토리얼)
	local TutorialController = require(Controllers.TutorialController)
	TutorialController.Init()

	-- TotemController 초기화 (거점 토템 유지비/범위 프리뷰)
	local TotemController = require(Controllers.TotemController)
	TotemController.Init()
	
	-- MovementController 스태미나 → UIManager 연동
	MovementController.onStaminaChanged(function(current, max)
		UIManager.updateStamina(current, max)
	end)
	
	-- 배고픔 → UIManager 연동 (Phase 11)
	NetClient.On("Hunger.Update", function(data)
		UIManager.updateHunger(data.current, data.max)
	end)
	
	-- 키 바인딩 설정
	-- [Key Bindings] Tab = 인벤토리, C = 건축, E = 장비창, P = 도감, B = 귀환
	InputManager.bindKey(Enum.KeyCode.Tab, "ToggleInventory_Tab", function() UIManager.toggleInventory() end)
	InputManager.bindKey(Enum.KeyCode.C, "ToggleBuilding", function() UIManager.toggleBuild() end)
	InputManager.bindKey(Enum.KeyCode.E, "ToggleEquipment", function() UIManager.toggleEquipment() end)
	InputManager.bindKey(Enum.KeyCode.P, "ToggleCollection", function() UIManager.toggleCollection() end)
	InputManager.bindKey(Enum.KeyCode.K, "ToggleSkillTree", function() UIManager.toggleSkillTree() end)

	-- [Active Skills] Q / F / V = 액티브 스킬 슬롯 1/2/3
	local ActiveSkillBarUI = require(Client:WaitForChild("UI"):WaitForChild("ActiveSkillBarUI"))
	InputManager.bindKey(Enum.KeyCode.Q, "ActiveSkill1", function() ActiveSkillBarUI.UseSlot(1) end)
	InputManager.bindKey(Enum.KeyCode.F, "ActiveSkill2", function() ActiveSkillBarUI.UseSlot(2) end)
	InputManager.bindKey(Enum.KeyCode.V, "ActiveSkill3", function() ActiveSkillBarUI.UseSlot(3) end)

	-- B = 귀환 (최근 취침 장소로 순간이동, 진행도 바 + 피격/이동 취소)
	local recallCasting = false -- 시전 중 여부
	local recallCancelled = false
	local recallCooldownEnd = 0 -- os.clock 기준 쿨다운 종료 시각

	-- 쿨다운 타이머 UI (HUD 위에 표시)
	local function showRecallCooldownTimer(cooldownSec)
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		local playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return end

		-- 기존 타이머 제거
		local old = playerGui:FindFirstChild("RecallCooldownUI")
		if old then old:Destroy() end

		local cdGui = Instance.new("ScreenGui")
		cdGui.Name = "RecallCooldownUI"
		cdGui.ResetOnSpawn = true
		cdGui.DisplayOrder = 90
		cdGui.Parent = playerGui

		local cdFrame = Instance.new("Frame")
		cdFrame.AnchorPoint = Vector2.new(0.5, 1)
		cdFrame.Position = UDim2.new(0.5, 0, 0.82, 0)
		cdFrame.Size = UDim2.new(0, 160, 0, 36)
		cdFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		cdFrame.BackgroundTransparency = 0.4
		cdFrame.BorderSizePixel = 0
		cdFrame.Parent = cdGui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = cdFrame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(80, 80, 100)
		stroke.Thickness = 1
		stroke.Parent = cdFrame

		local cdLabel = Instance.new("TextLabel")
		cdLabel.Size = UDim2.new(1, 0, 1, 0)
		cdLabel.BackgroundTransparency = 1
		cdLabel.Text = string.format("귀환 [B] %ds", cooldownSec)
		cdLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
		cdLabel.TextSize = 14
		cdLabel.Font = Enum.Font.GothamMedium
		cdLabel.Parent = cdFrame

		task.spawn(function()
			while cdGui.Parent do
				local remain = math.ceil(recallCooldownEnd - os.clock())
				if remain <= 0 then
					cdLabel.Text = "귀환 [B] 준비 완료"
					cdLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
					task.wait(1.5)
					if cdGui.Parent then cdGui:Destroy() end
					return
				end
				cdLabel.Text = string.format("귀환 [B] %ds", remain)
				task.wait(0.5)
			end
		end)
	end

	InputManager.bindKey(Enum.KeyCode.B, "RecallTeleport", function()
		-- 쿨다운 중이면 남은 시간 표시
		if recallCooldownEnd > os.clock() then
			local remain = math.ceil(recallCooldownEnd - os.clock())
			UIManager.sideNotify(string.format("귀환 쿨다운: %d초 남음", remain), Color3.fromRGB(255, 200, 80))
			return
		end
		if recallCasting then return end
		if InputManager.isUIOpen() then return end

		recallCasting = true
		recallCancelled = false

		local Players = game:GetService("Players")
		local Balance = require(game:GetService("ReplicatedStorage").Shared.Config.Balance)
		local castTime = Balance.RECALL_CAST_TIME or 5
		local player = Players.LocalPlayer
		local character = player.Character
		local playerGui = player:FindFirstChild("PlayerGui")

		if not character or not character:FindFirstChild("HumanoidRootPart") then
			recallDebounce = false
			return
		end

		-- 귀환 진행도 바 UI 생성
		local recallGui = Instance.new("ScreenGui")
		recallGui.Name = "RecallCastUI"
		recallGui.ResetOnSpawn = true
		recallGui.DisplayOrder = 100
		recallGui.Parent = playerGui

		local bg = Instance.new("Frame")
		bg.Name = "RecallBG"
		bg.AnchorPoint = Vector2.new(0.5, 0.5)
		bg.Position = UDim2.new(0.5, 0, 0.75, 0)
		bg.Size = UDim2.new(0, 300, 0, 60)
		bg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		bg.BackgroundTransparency = 0.3
		bg.BorderSizePixel = 0
		bg.Parent = recallGui
		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 8)
		bgCorner.Parent = bg
		local bgStroke = Instance.new("UIStroke")
		bgStroke.Color = Color3.fromRGB(100, 180, 255)
		bgStroke.Thickness = 1.5
		bgStroke.Parent = bg

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0, 24)
		titleLbl.Position = UDim2.new(0, 0, 0, 4)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Text = "귀환 시전 중..."
		titleLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
		titleLbl.TextSize = 16
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.Parent = bg

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(0.85, 0, 0, 14)
		barBg.Position = UDim2.new(0.075, 0, 0, 34)
		barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		barBg.BorderSizePixel = 0
		barBg.Parent = bg
		local barBgCorner = Instance.new("UICorner")
		barBgCorner.CornerRadius = UDim.new(0, 4)
		barBgCorner.Parent = barBg

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		local barFillCorner = Instance.new("UICorner")
		barFillCorner.CornerRadius = UDim.new(0, 4)
		barFillCorner.Parent = barFill

		local pctLbl = Instance.new("TextLabel")
		pctLbl.Size = UDim2.new(1, 0, 0, 16)
		pctLbl.Position = UDim2.new(0, 0, 0, 42)
		pctLbl.BackgroundTransparency = 1
		pctLbl.Text = "0%"
		pctLbl.TextColor3 = Color3.fromRGB(200, 220, 240)
		pctLbl.TextSize = 12
		pctLbl.Font = Enum.Font.GothamMedium
		pctLbl.Parent = bg

		-- Highlight 이펙트
		local highlight = Instance.new("Highlight")
		highlight.Name = "RecallGlow"
		highlight.FillColor = Color3.fromRGB(180, 220, 255)
		highlight.FillTransparency = 0.4
		highlight.OutlineColor = Color3.fromRGB(100, 180, 255)
		highlight.OutlineTransparency = 0
		highlight.Adornee = character
		highlight.Parent = character

		-- 피격 감지 (HealthChanged)
		local humanoid = character:FindFirstChild("Humanoid")
		local prevHealth = humanoid and humanoid.Health or 100
		local healthConn = nil
		if humanoid then
			healthConn = humanoid.HealthChanged:Connect(function(newHealth)
				if newHealth < prevHealth then
					recallCancelled = true
				end
				prevHealth = newHealth
			end)
		end

		-- 시전 루프
		local startPos = character.HumanoidRootPart.Position
		local elapsed = 0
		while elapsed < castTime do
			task.wait(0.1)
			elapsed += 0.1

			-- 이동 체크
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then recallCancelled = true end
			if hrp and (hrp.Position - startPos).Magnitude > 3 then recallCancelled = true end

			if recallCancelled then break end

			-- 진행도 업데이트
			local pct = math.clamp(elapsed / castTime, 0, 1)
			barFill.Size = UDim2.new(pct, 0, 1, 0)
			pctLbl.Text = string.format("%d%%", math.floor(pct * 100))
			highlight.FillTransparency = math.max(0, 0.4 - pct * 0.4)

			-- 색상 그라데이션 (파란색 → 밝은 흰색)
			local r = math.floor(100 + pct * 155)
			local g = math.floor(180 + pct * 60)
			local b = 255
			barFill.BackgroundColor3 = Color3.fromRGB(r, g, b)
		end

		if healthConn then healthConn:Disconnect() end

		local function cleanup()
			if highlight and highlight.Parent then highlight:Destroy() end
			if recallGui and recallGui.Parent then recallGui:Destroy() end
		end

		if recallCancelled then
			cleanup()
			UIManager.sideNotify("귀환이 취소되었습니다.", Color3.fromRGB(255, 100, 100))
			task.delay(2, function() recallCasting = false end)
			return
		end

		-- 100% 완료 → 서버 요청
		barFill.Size = UDim2.new(1, 0, 1, 0)
		pctLbl.Text = "100%"
		titleLbl.Text = "귀환!"
		titleLbl.TextColor3 = Color3.fromRGB(100, 255, 150)

		local ok, data = NetClient.Request("Recall.Request", {})
		cleanup()

		if ok then
			UIManager.sideNotify("귀환 완료!", Color3.fromRGB(100, 255, 150))
			local cdTime = Balance.RECALL_COOLDOWN or 60
			recallCooldownEnd = os.clock() + cdTime
			recallCasting = false
			showRecallCooldownTimer(cdTime)
		else
			local errMsg = "귀환 실패"
			if data == "NO_SLEEP_LOCATION" then
				errMsg = "취침한 장소가 없습니다. 간이천막에서 수면 후 사용하세요."
			elseif data == "PLAYER_DEAD" then
				errMsg = "사망 상태에서는 귀환할 수 없습니다."
			elseif data == "COOLDOWN" then
				errMsg = "귀환 쿨다운 중입니다."
			end
			UIManager.sideNotify(errMsg, Color3.fromRGB(255, 100, 100))
			task.delay(2, function() recallCasting = false end)
		end
	end)
	
	-- R = 모든 상호작용 통합 (NPC, 자원, 시설, 무전기, 공룡 메뉴)
	InputManager.bindKey(Enum.KeyCode.R, "InteractFacilityR", function()
		if InteractController.onFacilityInteractPress then
			InteractController.onFacilityInteractPress()
		end
	end)

	-- T = 건물 해체
	InputManager.bindKey(Enum.KeyCode.T, "InteractFacilityRemoveT", function()
		if InteractController.onFacilityRemovePress then
			InteractController.onFacilityRemovePress()
		end
	end)
	
	InputManager.bindKey(Enum.KeyCode.Escape, "CloseUI", function()
		UIManager.closeInventory()
		UIManager.closeCrafting()
		UIManager.closeEquipment()
		UIManager.closeBuild()
		UIManager.closeCollection()
		UIManager.closeShop()
		if UIManager.closeTotem then
			UIManager.closeTotem()
		end
	end)
end

print("[ClientInit] Client initialized")
