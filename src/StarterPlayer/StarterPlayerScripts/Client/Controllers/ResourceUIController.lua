-- ResourceUIController.lua
-- 자원 노드 상단 HP 바 관리
-- Phase 7: 채집 시스템 연동

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(script.Parent.Parent.NetClient)

local ResourceUIController = {}

--========================================
-- Constants
--========================================
local UI_OFFSET = Vector3.new(0, 3, 0) -- 위치 하향 (5 -> 3)
local BAR_SIZE = UDim2.new(0, 90, 0, 10) -- 크기 소폭 축소

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
	
	-- BillboardGui 생성
	local bg = Instance.new("BillboardGui")
	bg.Name = "ResourceHPBar"
	bg.Size = UDim2.new(0, 120, 0, 40)
	bg.Adornee = primary
	bg.StudsOffset = UI_OFFSET
	bg.AlwaysOnTop = false
	bg.MaxDistance = 60
	
	-- 배경
	local frame = Instance.new("Frame")
	frame.Name = "BG"
	frame.Size = BAR_SIZE
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.7 -- 투명도 상향 (0.5 -> 0.7)
	frame.BorderSizePixel = 0
	frame.Parent = bg
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	
	-- 채우기
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
	fill.BackgroundTransparency = 0.6 -- 투명도 상향 (0.4 -> 0.6)
	fill.BorderSizePixel = 0
	fill.Parent = frame
	
	local corner2 = corner:Clone()
	corner2.Parent = fill
	
	-- 텍스트 (아이템 이름 등)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Position = UDim2.new(0, 0, -1, 0)
	label.BackgroundTransparency = 1
	label.Text = nodeModel.Name
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextTransparency = 0.5 -- 투명도 상향 (0.3 -> 0.5)
	label.TextSize = 10
	label.Font = Enum.Font.GothamMedium
	label.TextStrokeTransparency = 0.8
	label.Parent = frame
	
	bg.Parent = nodeModel
	activeBars[nodeUID] = bg
	
	return bg
end

--- HP 바 업데이트
local function updateHPBar(nodeUID, remainingHits, maxHits)
	local bg = activeBars[nodeUID]
	if not bg then
		-- 만약 없는 경우, 마침 타겟 근처면 생성 시도
		local nodeFolder = workspace:FindFirstChild("ResourceNodes")
		if nodeFolder then
			for _, model in ipairs(nodeFolder:GetChildren()) do
				if model:GetAttribute("NodeUID") == nodeUID then
					bg = createHPBar(model, nodeUID, maxHits)
					break
				end
			end
		end
	end
	
	if bg then
		local fill = bg.BG:FindFirstChild("Fill")
		if fill then
			local ratio = math.clamp(remainingHits / maxHits, 0, 1)
			TweenService:Create(fill, TweenInfo.new(0.2), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
		end
	end
end

--========================================
-- Public API
--========================================

function ResourceUIController.Init()
	if initialized then return end
	
	-- 서버로부터 노드 스폰 알림 수신
	NetClient.On("Harvest.Node.Spawned", function(data)
		-- 이미 존재하는 노드인지 확인 후 GUI 부착
		task.delay(0.5, function() -- 모델 복제 완료 대기
			local nodeFolder = workspace:FindFirstChild("ResourceNodes")
			if nodeFolder then
				for _, model in ipairs(nodeFolder:GetChildren()) do
					if model:GetAttribute("NodeUID") == data.nodeUID then
						createHPBar(model, data.nodeUID, data.maxHits)
						break
					end
				end
			end
		end)
	end)
	
	-- 서버로부터 노드 타격 알림 수신
	NetClient.On("Harvest.Node.Hit", function(data)
		updateHPBar(data.nodeUID, data.remainingHits, data.maxHits)
	end)
	
	-- 서버로부터 노드 고갈 알림 수신
	NetClient.On("Harvest.Node.Depleted", function(data)
		if activeBars[data.nodeUID] then
			activeBars[data.nodeUID]:Destroy()
			activeBars[data.nodeUID] = nil
		end
	end)
	
	-- 기존 노드들 전수 조사 (재접속/초기화 대응)
	task.spawn(function()
		task.wait(2)
		local nodeFolder = workspace:FindFirstChild("ResourceNodes")
		if nodeFolder then
			for _, model in ipairs(nodeFolder:GetChildren()) do
				local uid = model:GetAttribute("NodeUID")
				if uid then
					createHPBar(model, uid, 10) -- 기본값 10
				end
			end
		end
	end)
	
	initialized = true
	print("[ResourceUIController] Initialized")
end

return ResourceUIController
