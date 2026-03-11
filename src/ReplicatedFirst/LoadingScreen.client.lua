-- LoadingScreen.client.lua
-- 로딩 스크린 및 메인 타이틀 스크린 구현

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

-- 로블록스 기본 로딩 스크린 비활성화
ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=========================================
-- UI 생성 헬퍼 함수
--=========================================
local function create(className, properties)
	local inst = Instance.new(className)
	for k, v in pairs(properties) do
		inst[k] = v
	end
	return inst
end

--=========================================
-- ScreenGui 초기화
--=========================================
local screenGui = create("ScreenGui", {
	Name = "CustomLoadingTitle",
	Parent = playerGui,
	IgnoreGuiInset = true,
	DisplayOrder = 9999, -- 가장 위에 렌더링
	ResetOnSpawn = false
})

--=========================================
local loadingFrame = create("Frame", {
	Name = "LoadingFrame",
	Parent = screenGui,
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0), -- 맵 배경용 살짝 어두운 오버레이
	BackgroundTransparency = 0.3,
	ZIndex = 10,
	Visible = true
})

-- 로고 이미지 (일단 비워두거나 Placeholder 처리)
local loadingLogo = create("ImageLabel", {
	Name = "Logo",
	Parent = loadingFrame,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.4, 0),
	Size = UDim2.new(0, 400, 0, 200),
	BackgroundTransparency = 1,
	Image = "rbxassetid://13192801438", -- 임시 로고
	ZIndex = 11
})

-- 안내 문구 (주의 사항)
local warningIcon = create("ImageLabel", {
	Name = "WarningIcon",
	Parent = loadingFrame,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(0.5, -170, 0.7, 0),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundTransparency = 1,
	Image = "rbxassetid://6031280882", -- 경고 아이콘
	ImageColor3 = Color3.fromRGB(255, 204, 0),
	ZIndex = 11
})

local warningText = create("TextLabel", {
	Name = "WarningText",
	Parent = loadingFrame,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0.5, -130, 0.7, 0),
	Size = UDim2.new(0, 300, 0, 40),
	BackgroundTransparency = 1,
	Text = "타인의 권리 침해 등 운영정책 위반 아바타 상품을 구매하지 않도록 유의해주세요.\n적발 시 이용 제한 및 상품이 임의 변경될 수 있습니다.",
	TextColor3 = Color3.fromRGB(150, 150, 150),
	TextSize = 12,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 11
})

-- 상태 텍스트
local statusText = create("TextLabel", {
	Name = "StatusText",
	Parent = loadingFrame,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.85, -20),
	Size = UDim2.new(0, 300, 0, 20),
	BackgroundTransparency = 1,
	Text = "월드를 불러오고 있습니다...",
	TextColor3 = Color3.fromRGB(150, 150, 150),
	TextSize = 12,
	Font = Enum.Font.Gotham,
	ZIndex = 11
})

local progressBarBG = create("Frame", {
	Name = "ProgressBarBG",
	Parent = loadingFrame,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.85, 0),
	Size = UDim2.new(0.6, 0, 0, 4),
	BackgroundColor3 = Color3.fromRGB(200, 200, 200),
	BorderSizePixel = 0,
	ZIndex = 11
})

local progressBarFill = create("Frame", {
	Name = "ProgressBarFill",
	Parent = progressBarBG,
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(160, 140, 90),
	BorderSizePixel = 0,
	ZIndex = 12
})

local percentText = create("TextLabel", {
	Name = "PercentText",
	Parent = progressBarBG,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(1, 10, 0.5, 0),
	Size = UDim2.new(0, 40, 0, 20),
	BackgroundTransparency = 1,
	Text = "0%",
	TextColor3 = Color3.fromRGB(120, 120, 120),
	TextSize = 12,
	Font = Enum.Font.GothamMedium,
	ZIndex = 11
})

--=========================================
-- 2. 타이틀 스크린 메인 메뉴 (Title Frame)
--=========================================
local titleFrame = create("Frame", {
	Name = "TitleFrame",
	Parent = screenGui,
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Visible = false
})

-- 타이틀 배경 오버레이 (배경 이미지 대신 3D 월드가 보이도록 透明하게 설정)
local titleBackground = create("Frame", {
	Name = "Background",
	Parent = titleFrame,
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 2
})

-- 새로 주신 동그란 로고 이미지
local originLogo = create("ImageLabel", {
	Name = "TitleLogo",
	Parent = titleBackground,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.4, 0), -- 배치를 적절하게 약간 내림
	Size = UDim2.new(0.6, 0, 0.6, 0),      -- 반응형으로 더 크게 (어차피 Fit이라 비율 유지됨)
	BackgroundTransparency = 1,
	Image = "rbxassetid://109740374827329",
	ScaleType = Enum.ScaleType.Fit,
	ImageTransparency = 1, -- 효과를 위해 전부 투명하게 시작
	ZIndex = 3,
	Visible = true
})

local startButton = create("TextButton", {
	Name = "StartButton",
	Parent = titleFrame,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.75, 0), -- 로고 바로 아래로 버튼 위치 위로 수정
	Size = UDim2.new(0.12, 0, 0.05, 0), -- 가로 길이를 줄여서 더 아담하고 정돈된 비율로 조정
	BackgroundColor3 = Color3.fromRGB(245, 185, 50),
	BackgroundTransparency = 0.25, -- 게임 시작 버튼 약간 투명하게 조정 (글씨 가림 방지)
	Text = "START",
	TextColor3 = Color3.fromRGB(30, 30, 30),
	TextScaled = true, -- 크기가 변하면 안의 글자도 같이 반응형으로 커짐
	Font = Enum.Font.GothamBold,
	AutoButtonColor = false,
	ZIndex = 4
})

-- Credits 버튼 추가
local creditsButton = create("TextButton", {
	Name = "CreditsButton",
	Parent = titleFrame,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.new(0, 100, 0, 35),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	BackgroundTransparency = 0.5,
	Text = "Credits",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	TextSize = 14,
	Font = Enum.Font.GothamMedium,
	ZIndex = 4
})

create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = creditsButton })

-- Credits GUI (Frame) 생성
local creditsFrame = create("Frame", {
	Name = "CreditsFrame",
	Parent = screenGui,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 400, 0, 300),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 20
})

create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = creditsFrame })
create("UIStroke", { Color = Color3.fromRGB(245, 185, 50), Thickness = 2, Parent = creditsFrame })

local creditsTitle = create("TextLabel", {
	Name = "Title",
	Parent = creditsFrame,
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 1,
	Text = "CREDITS",
	TextColor3 = Color3.fromRGB(245, 185, 50),
	TextSize = 24,
	Font = Enum.Font.GothamBold,
	ZIndex = 21
})

local creditsContent = create("TextLabel", {
	Name = "Content",
	Parent = creditsFrame,
	Position = UDim2.new(0.05, 0, 0.2, 0),
	Size = UDim2.new(0.9, 0, 0.65, 0),
	BackgroundTransparency = 1,
	Text = "WildForge Development Team\n\n[Assets & Tools]\nTree by Poly by Google [CC-BY] via Poly Pizza\nTree-2 by Marc Solà [CC-BY] (https://poly.pizza/m/cRipmFHCEVU)\nBush with Berries by Quaternius (https://poly.pizza/m/TSbIxkDtxF)\nROBLOX Studio / ROJO\n\n(추후 출처 내용이 업데이트될 예정입니다.)",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	TextSize = 14, -- 늘어나는 텍스트를 고려해 16에서 14로 약간 조정
	Font = Enum.Font.Gotham,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 21
})

local closeCredits = create("TextButton", {
	Name = "CloseButton",
	Parent = creditsFrame,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -15),
	Size = UDim2.new(0, 100, 0, 30),
	BackgroundColor3 = Color3.fromRGB(80, 80, 80),
	Text = "CLOSE",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	ZIndex = 21
})
create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = closeCredits })

-- 글자가 너무 커지거나 너무 작아지지 않게 한계값 설정
local btnTextConstraint = create("UITextSizeConstraint", {
	MaxTextSize = 28,
	MinTextSize = 14,
	Parent = startButton
})

-- 버튼 라운딩 처리
local btnUICorner = create("UICorner", {
	CornerRadius = UDim.new(0, 8),
	Parent = startButton
})

local btnUIStroke = create("UIStroke", {
	Parent = startButton,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Color = Color3.fromRGB(80, 50, 10),
	Thickness = 3
})
--=========================================
-- 로직 & 애니메이션
--=========================================

-- 플레이어 조작 비활성화 루프 (Title에 있는 동안)
local function setMovementEnabled(enabled)
	local controls = nil
	pcall(function()
		local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
		controls = PlayerModule:GetControls()
	end)
	
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
	
	-- 임시 블러 효과
	if enabled then
		local blur = game.Lighting:FindFirstChild("TitleBlur")
		if blur then blur:Destroy() end
	else
		local blur = game.Lighting:FindFirstChild("TitleBlur") or Instance.new("BlurEffect", game.Lighting)
		blur.Name = "TitleBlur"
		blur.Size = 15
	end
end

setMovementEnabled(false) -- 조작 비활성화

-- [일시정지 형태 뷰 연출] : 캐릭터 공중 유배 및 카메라 고정
local camera = workspace.CurrentCamera
local initCFrame = CFrame.new(0, 50, 0)
local hrp = nil

task.spawn(function()
	local char = player.Character or player.CharacterAdded:Wait()
	hrp = char:WaitForChild("HumanoidRootPart")
	task.wait(0.2) -- 스폰 후 위치 확정을 위한 짧은 대기
	
	if hrp then
		initCFrame = hrp.CFrame
		
		-- 플레이어를 아주 높은 하늘로 이동 & 고정하여 공룡 타겟팅(공격) 방지
		hrp.Anchored = true
		hrp.CFrame = initCFrame + Vector3.new(0, 5000, 0)
		
		-- 카메라는 플레이어 스폰 지역 근처의 풍경을 조용히 바라보게 셋팅 (일시정지된 듯한 화면)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = initCFrame * CFrame.new(0, 15, 25) * CFrame.Angles(math.rad(-10), 0, 0)
	end
end)

-- 가짜 로딩 프로그래스 애니메이션 (게임이 빠르게 로드될 수도 있으므로 최소 보여주기 용)
local progress = 0
local isLoading = true

task.spawn(function()
	while isLoading do
		if progress < 90 then
			progress = progress + math.random(2, 6)
			if progress > 90 then progress = 90 end
		end
		
		TweenService:Create(progressBarFill, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
			Size = UDim2.new(progress/100, 0, 1, 0)
		}):Play()
		percentText.Text = progress .. "%"
		
		task.wait(0.1 + (math.random() * 0.2))
	end
end)

-- 실제 게임 로딩 대기
if not game:IsLoaded() then
	game.Loaded:Wait()
end

statusText.Text = "에셋을 로딩 중입니다..."
local assetsFolder = game.ReplicatedStorage:WaitForChild("Assets", 30)
if assetsFolder then
	assetsFolder:WaitForChild("ItemIcons", 15)
end

statusText.Text = "게임 정보를 동기화 중입니다..."
local t = 0
while not player:GetAttribute("InventoryLoaded") and t < 60 do
	task.wait(0.2)
	t = t + 0.2
end

-- 로딩 완료
isLoading = false
progress = 100
statusText.Text = "동기화 완료!"
TweenService:Create(progressBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Linear), {
	Size = UDim2.new(1, 0, 1, 0)
}):Play()
percentText.Text = "100%"
task.wait(0.6)

-- 페이드 아웃 & 타이틀 씬 전환
statusText.Text = "환영합니다!"
task.wait(0.5)

-- 페이드 아웃 트윈
local fadeTween = TweenService:Create(loadingFrame, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {
	BackgroundTransparency = 1
})
TweenService:Create(loadingLogo, TweenInfo.new(0.6), {ImageTransparency = 1}):Play()
TweenService:Create(warningIcon, TweenInfo.new(0.6), {ImageTransparency = 1}):Play()
TweenService:Create(warningText, TweenInfo.new(0.6), {TextTransparency = 1}):Play()
TweenService:Create(statusText, TweenInfo.new(0.6), {TextTransparency = 1}):Play()
TweenService:Create(progressBarBG, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play()
TweenService:Create(progressBarFill, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play()
TweenService:Create(percentText, TweenInfo.new(0.6), {TextTransparency = 1}):Play()

fadeTween:Play()
fadeTween.Completed:Wait()

loadingFrame.Visible = false

-- 타이블 메뉴 표시
titleFrame.Visible = true

-- 로고 이미지 페이드 인
TweenService:Create(originLogo, TweenInfo.new(1.0, Enum.EasingStyle.Sine), {
	ImageTransparency = 0
}):Play()

-- 배경은 약간 어둡게 (맵이 잘 보이도록 0.4 투명도)
TweenService:Create(titleBackground, TweenInfo.new(1.0, Enum.EasingStyle.Sine), {
	BackgroundTransparency = 0.4
}):Play()

-- 메인 메뉴 버튼 이벤트
local function applyHoverEffect(button, defaultColor, hoverColor, defaultTrans, hoverTrans)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), {
			BackgroundColor3 = hoverColor,
			BackgroundTransparency = hoverTrans
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2), {
			BackgroundColor3 = defaultColor,
			BackgroundTransparency = defaultTrans
		}):Play()
	end)
end

-- 마우스 올렸을 때 조금 덜 투명하게 (0.15) 밝게 표시
applyHoverEffect(startButton, Color3.fromRGB(245, 185, 50), Color3.fromRGB(255, 215, 100), 0.25, 0.15)
applyHoverEffect(creditsButton, Color3.fromRGB(50, 50, 50), Color3.fromRGB(80, 80, 80), 0.5, 0.3)

creditsButton.MouseButton1Click:Connect(function()
	creditsFrame.Visible = true
end)

closeCredits.MouseButton1Click:Connect(function()
	creditsFrame.Visible = false
end)

-- 게임 시작 버튼 클릭 이벤트
startButton.MouseButton1Click:Connect(function()
	-- 버튼 누르는 효과 (가로축에 맞춰서 작아지는 효과 조절)
	TweenService:Create(startButton, TweenInfo.new(0.1), {Size = UDim2.new(0.11, 0, 0.045, 0)}):Play()
	task.wait(0.1)
	
	-- 화면 암전 혹은 페이드 아웃
	local blackFrame = create("Frame", {
		Name = "FadeFrame",
		Parent = screenGui,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 15
	})
	
	local startFade = TweenService:Create(blackFrame, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	})
	startFade:Play()
	startFade.Completed:Wait()
	
	-- 게임 조작 복구 및 UI 제거
	titleFrame.Visible = false
	
	-- 플레이어 위치 원상복구 및 공룡 공격 회피 해제, 카메라 정상화
	if hrp then
		hrp.CFrame = initCFrame
		hrp.Anchored = false
	end
	camera.CameraType = Enum.CameraType.Custom
	
	setMovementEnabled(true)
	
	-- 다시 페이드 인
	local endFade = TweenService:Create(blackFrame, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})
	endFade:Play()
	endFade.Completed:Wait()
	
	screenGui:Destroy()
end)

print("[LoadingScreen] Title Screen Sequence Initiated")
