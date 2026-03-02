-- ResourceUIController.lua
-- 자원 노드 상단 HP 바 관리
-- Phase 7: 채집 시스템 연동

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectionService = game:GetService("CollectionService")
local NetClient = require(script.Parent.Parent.NetClient)

local ResourceUIController = {}

--========================================
-- Constants
--========================================
local BAR_SIZE = UDim2.new(0, 90, 0, 4) -- HP바를 아주 얇은 선 형태로 축소 (10 -> 4)

--========================================
-- Internal State
--========================================
local initialized = false
local activeBars = {} -- [nodeUID] = BillboardGui

--========================================
-- Private Functions
--========================================

--- HP 바 생성
local function createHPBar(nodeModel, nodeUID, maxHits)
	if activeBars[nodeUID] then return activeBars[nodeUID] end
	
	local primary = nodeModel.PrimaryPart or nodeModel:FindFirstChildWhichIsA("BasePart")
	if not primary then return nil end
	
	-- 나무처럼 위치가 높은 오브젝트에 대한 확실한 높이 고정 로직 (바운딩 박스 최하단 기준 + 3~4 떨어짐)
	local bg = Instance.new("BillboardGui")
	bg.Name = "ResourceHPBar"
	bg.Size = UDim2.new(0, 120, 0, 40)
	bg.Adornee = primary
	
	-- 전체 모델의 바운딩 크기를 기반으로 하단부터 계산하여 눈높이로 강제 고정
	local cframe, size = nodeModel:GetBoundingBox()
	local targetY = cframe.Y -- 모델의 실질적인 정중앙 높이
	local groundY = targetY - (size.Y/2)
	
	-- 크기가 10 스터드를 넘으면 4.5(시선 조금 위), 아니면 3
	local eyeLevelY = groundY + (size.Y > 10 and 4.5 or 3)
	
	-- ExtentsOffsetWorldSpace은 Adornee 파트의 바운딩박스와 영향을 주고받으므로
	-- 절대좌표 오프셋인 StudsOffsetWorldSpace를 사용하여 파트 중심점과 상관없이 무조건 바닥 높이로 맞춥니다.
	local offsetFromPrimary = eyeLevelY - primary.Position.Y
	bg.StudsOffsetWorldSpace = Vector3.new(0, offsetFromPrimary, 0)
	
	bg.AlwaysOnTop = true -- 모델 파트에 피묻히거나 가려지지 않고 항상 렌더링되게 변경
	bg.MaxDistance = 60
	
	-- 배경 (이름 + 바 전체를 덮는 테마형 레이아웃)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "BG"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.95 -- 유리 수준으로 매우 투명하게 변경
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = bg
	
	local cornerMain = Instance.new("UICorner")
	cornerMain.CornerRadius = UDim.new(0, 4)
	cornerMain.Parent = mainFrame
	
	-- 이름 텍스트
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.4, 0)
	label.BackgroundTransparency = 1
	label.Text = nodeModel.Name
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextTransparency = 0.5
	label.TextSize = 8 -- 글씨 아주 작게 축소 (10 -> 8)
	label.Font = Enum.Font.GothamMedium
	label.TextStrokeTransparency = 1 -- 텍스트 외곽선도 완전 투명화(제거)
	label.Parent = mainFrame
	
	-- HP 바 배경
	local frame = Instance.new("Frame")
	frame.Name = "HealthBG"
	frame.Size = BAR_SIZE
	frame.Position = UDim2.new(0.5, 0, 0.6, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 1 -- 부모(mainFrame) 배경만 보이게 투명 처리
	frame.BorderSizePixel = 0
	frame.Parent = mainFrame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	
	-- 채우기
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.Parent = frame
	
	local corner2 = cornerMain:Clone()
	corner2.Parent = fill
	
	bg.Parent = nodeModel
	activeBars[nodeUID] = bg
	
	return bg
end

--- HP 바 업데이트
local function updateHPBar(nodeUID, remainingHits, maxHits)
	local bg = activeBars[nodeUID]
	if not bg then
		-- 만약 없는 경우, 스트리밍 등으로 레이스가 발생했을 수 있음.
		-- CollectionService 태그된 것 중 매칭되는 UID 찾기 시도
		for _, model in ipairs(CollectionService:GetTagged("ResourceNode")) do
			if model:GetAttribute("NodeUID") == nodeUID then
				bg = createHPBar(model, nodeUID, maxHits)
				break
			end
		end
	end
	
	if bg then
		local bgFrame = bg:FindFirstChild("BG")
		if bgFrame then
			local healthBG = bgFrame:FindFirstChild("HealthBG")
			if healthBG then
				local fill = healthBG:FindFirstChild("Fill")
				if fill then
					local ratio = math.clamp(remainingHits / maxHits, 0, 1)
					TweenService:Create(fill, TweenInfo.new(0.2), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
				end
			end
		end
	end
end

--========================================
-- Public API
--========================================

function ResourceUIController.Init()
	if initialized then return end
	
	-- [UX 개선] StreamingEnabled 대응을 위한 CollectionService 기반 구조로 변경
	local function onNodeAdded(model)
		local nodeUID = model:GetAttribute("NodeUID")
		if nodeUID then
			createHPBar(model, nodeUID, 10) -- 기본 최대 타격 10 (Hit 이벤트 시 업데이트됨)
		end
	end
	
	local function onNodeRemoved(model)
		local nodeUID = model:GetAttribute("NodeUID")
		if nodeUID and activeBars[nodeUID] then
			activeBars[nodeUID]:Destroy()
			activeBars[nodeUID] = nil
		end
	end
	
	-- 1. 기존 노드 처리 및 태그 리스너 연결
	for _, node in ipairs(CollectionService:GetTagged("ResourceNode")) do
		task.spawn(onNodeAdded, node)
	end
	
	CollectionService:GetInstanceAddedSignal("ResourceNode"):Connect(onNodeAdded)
	CollectionService:GetInstanceRemovedSignal("ResourceNode"):Connect(onNodeRemoved)
	
	-- 서버로부터 노드 타격 알림 수신
	NetClient.On("Harvest.Node.Hit", function(data)
		updateHPBar(data.nodeUID, data.remainingHits, data.maxHits)
	end)
	
	-- 서버로부터 노드 고갈 알림 수신 (모델 제거 전 UI 즉시 제거용)
	NetClient.On("Harvest.Node.Depleted", function(data)
		if activeBars[data.nodeUID] then
			activeBars[data.nodeUID]:Destroy()
			activeBars[data.nodeUID] = nil
		end
	end)
	
	initialized = true
	print("[ResourceUIController] Initialized")
end

return ResourceUIController
