-- ResourceUIController.lua
-- 자원 노드 상단 HP 바 관리
-- Phase 7: 채집 시스템 연동

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectionService = game:GetService("CollectionService")
local NetClient = require(script.Parent.Parent.NetClient)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

local ResourceUIController = {}

--========================================
-- Constants
--========================================
local BAR_SIZE = UDim2.new(0, 90, 0, 4) -- HP바를 아주 얇은 선 형태로 축소 (10 -> 4)
local HIT_LABEL_VISIBLE_DURATION = 5
local NODE_HINT_MAX_DISTANCE = 10
local NODE_HINT_CREATE_DISTANCE = 12
local NODE_HINT_DESTROY_DISTANCE = 16
local MAX_ACTIVE_HINTS = 8
local DEBUG_RESOURCE_HINT = false

--========================================
-- Internal State
--========================================
local initialized = false
local activeBars = {} -- [nodeUID] = BillboardGui
local barVisibleUntil = {} -- [nodeUID] = tick()
local nodeHints = {} -- [Instance] = Highlight
local nodeFolderConnAdded = nil
local nodeFolderConnRemoving = nil
local workspaceConnChildAdded = nil
local workspaceConnDescAdded = nil
local workspaceConnDescRemoving = nil
local debugGui = nil
local debugLabel = nil
local trackedNodes = {} -- [Instance] = true

local DEBUG_FORCE_NODE_IDS = {
	GROUND_BRANCH = true,
	GROUND_FIBER = true,
	GROUND_STONE = true,
	TREE_THIN = true,
}

--========================================
-- Private Functions
--========================================

--- HP 바 생성 — [REMOVED] 레거시 흰색 이름+초록 HP바 박스 제거
local function createHPBar(nodeModel, nodeUID, maxHits)
	return nil -- 레거시 UI 비활성화: Highlight 힌트 마커만 유지
end

local function getNodeAnchorPart(nodeInstance)
	if not nodeInstance then
		return nil
	end
	if nodeInstance:IsA("Model") then
		return nodeInstance.PrimaryPart or nodeInstance:FindFirstChildWhichIsA("BasePart", true)
	end
	if nodeInstance:IsA("BasePart") then
		return nodeInstance
	end
	return nil
end

local function getHorizontalDistanceToNode(nodeInstance, hrp)
	if not nodeInstance or not hrp then
		return math.huge
	end

	local hrpPos2 = Vector2.new(hrp.Position.X, hrp.Position.Z)

	if nodeInstance:IsA("BasePart") then
		local p2 = Vector2.new(nodeInstance.Position.X, nodeInstance.Position.Z)
		return (p2 - hrpPos2).Magnitude
	end

	if nodeInstance:IsA("Model") then
		local minDist = math.huge
		for _, d in ipairs(nodeInstance:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Hitbox" then
				local p2 = Vector2.new(d.Position.X, d.Position.Z)
				local dist = (p2 - hrpPos2).Magnitude
				if dist < minDist then
					minDist = dist
				end
			end
		end
		if minDist < math.huge then
			return minDist
		end

		local anchor = getNodeAnchorPart(nodeInstance)
		if anchor then
			local p2 = Vector2.new(anchor.Position.X, anchor.Position.Z)
			return (p2 - hrpPos2).Magnitude
		end
	end

	return math.huge
end

local function isNodeCandidate(nodeInstance, resourceRoot)
	if not nodeInstance then
		return false
	end

	if nodeInstance:IsA("Model") then
		return getNodeAnchorPart(nodeInstance) ~= nil
	end

	if nodeInstance:IsA("BasePart") then
		if nodeInstance.Name == "Hitbox" then
			return false
		end
		if nodeInstance:FindFirstAncestorOfClass("Model") then
			return false
		end
		return resourceRoot and nodeInstance:IsDescendantOf(resourceRoot) or false
	end

	return false
end

local function isDebugForcedNode(nodeInstance)
	if not nodeInstance then
		return false
	end

	local nodeId = tostring(nodeInstance:GetAttribute("NodeId") or "")
	if nodeId ~= "" and DEBUG_FORCE_NODE_IDS[nodeId] then
		return true
	end

	return false
end

local function ensureDebugOverlay()
	if not DEBUG_RESOURCE_HINT then
		return
	end

	if debugLabel and debugLabel.Parent then
		return
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	if debugGui and debugGui.Parent then
		return
	end

	debugGui = Instance.new("ScreenGui")
	debugGui.Name = "ResourceHintDebug"
	debugGui.ResetOnSpawn = false
	debugGui.IgnoreGuiInset = true
	debugGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	debugGui.Parent = playerGui

	debugLabel = Instance.new("TextLabel")
	debugLabel.Name = "HintDebugLabel"
	debugLabel.Size = UDim2.new(0, 420, 0, 72)
	debugLabel.Position = UDim2.new(0, 12, 0, 12)
	debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	debugLabel.BackgroundTransparency = 0.35
	debugLabel.TextColor3 = Color3.fromRGB(255, 255, 210)
	debugLabel.TextStrokeTransparency = 0.75
	debugLabel.Font = Enum.Font.Code
	debugLabel.TextSize = 14
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextYAlignment = Enum.TextYAlignment.Top
	debugLabel.TextWrapped = true
	debugLabel.Text = "ResourceHint DEBUG initializing..."
	debugLabel.Parent = debugGui
end

local function isAnyNodeCandidate(nodeInstance, resourceRoot)
	if not nodeInstance then
		return false
	end

	local inResourceNodes = resourceRoot and nodeInstance:IsDescendantOf(resourceRoot) or false
	local isTagged = false
	local ok, tagged = pcall(function()
		return CollectionService:HasTag(nodeInstance, "ResourceNode")
	end)
	if ok and tagged then
		isTagged = true
	end

	local hasNodeAttrs = nodeInstance:GetAttribute("NodeUID") ~= nil
		or nodeInstance:GetAttribute("NodeId") ~= nil
		or nodeInstance:GetAttribute("ResourceNode") == true

	if not (inResourceNodes or isTagged or hasNodeAttrs) then
		return false
	end

	if hasNodeAttrs then
		if nodeInstance:IsA("Model") then
			return getNodeAnchorPart(nodeInstance) ~= nil
		end
		if nodeInstance:IsA("BasePart") then
			if nodeInstance.Name == "Hitbox" then
				return false
			end
			if nodeInstance:FindFirstAncestorOfClass("Model") then
				return false
			end
			return true
		end
	end

	return isNodeCandidate(nodeInstance, resourceRoot)
end

local function createHintMarker(nodeInstance)
	if not nodeInstance then
		return nil
	end

	if nodeHints[nodeInstance] then
		return nodeHints[nodeInstance]
	end

	local marker = Instance.new("Highlight")
	marker.Name = "ResourceHint"
	marker.Adornee = nodeInstance
	marker.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	marker.FillTransparency = 1
	marker.OutlineColor = Color3.fromRGB(255, 232, 155)
	marker.OutlineTransparency = 0.38
	marker.Enabled = true
	marker.Parent = nodeInstance

	nodeHints[nodeInstance] = marker
	return marker
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
		bg.Enabled = true
		barVisibleUntil[nodeUID] = tick() + HIT_LABEL_VISIBLE_DURATION
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

	-- 타격 후 일정 시간 지나면 자동 숨김
	task.spawn(function()
		while true do
			task.wait(0.2)
			ensureDebugOverlay()
			local now = tick()
			local localPlayer = Players.LocalPlayer
			local char = localPlayer and localPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hintCandidates = {}
			local forcedCandidates = {}
			local forcedCount = 0
			local rangeCount = 0
			local enabledCount = 0
			for nodeUID, untilTs in pairs(barVisibleUntil) do
				if untilTs <= now then
					local bar = activeBars[nodeUID]
					if bar then
						bar.Enabled = false
					end
					barVisibleUntil[nodeUID] = nil
				end
			end

			if hrp then
				for nodeInstance in pairs(trackedNodes) do
					if not nodeInstance or not nodeInstance.Parent then
						trackedNodes[nodeInstance] = nil
						if nodeHints[nodeInstance] then
							nodeHints[nodeInstance]:Destroy()
							nodeHints[nodeInstance] = nil
						end
						continue
					end

					local dist = getHorizontalDistanceToNode(nodeInstance, hrp)
					local marker = nodeHints[nodeInstance]

					if marker then
						if dist > NODE_HINT_DESTROY_DISTANCE then
							marker:Destroy()
							nodeHints[nodeInstance] = nil
						end
					else
						if dist <= NODE_HINT_CREATE_DISTANCE then
							createHintMarker(nodeInstance)
						end
					end
				end
			end

			for nodeInstance, marker in pairs(nodeHints) do
				if not marker or not marker.Parent then
					nodeHints[nodeInstance] = nil
					continue
				end

				local forcedDebug = DEBUG_RESOURCE_HINT and isDebugForcedNode(nodeInstance)
				if forcedDebug then
					forcedCount = forcedCount + 1
				end

				local showHint = true
				local uid = nodeInstance and nodeInstance:GetAttribute("NodeUID")
				if uid and uid ~= "" then
					local bar = activeBars[uid]
					if bar and bar.Enabled then
						showHint = false
					end
				end

				if showHint and hrp then
					local dist = getHorizontalDistanceToNode(marker.Adornee, hrp)
					if dist <= NODE_HINT_MAX_DISTANCE then
						rangeCount = rangeCount + 1
						if forcedDebug then
							table.insert(forcedCandidates, { marker = marker, dist = dist })
						else
							table.insert(hintCandidates, { marker = marker, dist = dist })
						end
					end
					showHint = false
				end

				if not hrp then
					showHint = true
				end

				marker.Enabled = showHint
				if showHint then
					enabledCount = enabledCount + 1
				end
			end

			if hrp and (#forcedCandidates > 0 or #hintCandidates > 0) then
				table.sort(forcedCandidates, function(a, b)
					return a.dist < b.dist
				end)
				table.sort(hintCandidates, function(a, b)
					return a.dist < b.dist
				end)

				local slot = 0
				for _, entry in ipairs(forcedCandidates) do
					slot = slot + 1
					local on = (slot <= MAX_ACTIVE_HINTS)
					entry.marker.Enabled = on
					if on then
						enabledCount = enabledCount + 1
					end
				end

				for _, entry in ipairs(hintCandidates) do
					slot = slot + 1
					local on = (slot <= MAX_ACTIVE_HINTS)
					entry.marker.Enabled = on
					if on then
						enabledCount = enabledCount + 1
					end
				end
			end

			if DEBUG_RESOURCE_HINT and debugLabel then
				debugLabel.Text = string.format(
					"ResourceHint DEBUG ON\\nTotalHints=%d  Enabled=%d\\nForced(4types)=%d  InRange=%d  MaxActive=%d",
					#(function()
						local t = {}
						for _ in pairs(nodeHints) do table.insert(t, true) end
						return t
					end)(),
					enabledCount,
					forcedCount,
					rangeCount,
					MAX_ACTIVE_HINTS
				)
			end
		end
	end)
	
	-- [UX 개선] StreamingEnabled 대응을 위한 CollectionService 기반 구조로 변경
	local function onNodeAdded(nodeInstance)
		if not nodeInstance or (not nodeInstance:IsA("Model") and not nodeInstance:IsA("BasePart")) then
			return
		end
		task.spawn(function()
			-- StreamingEnabled로 인해 파트 로드 지연 가능성 대기
			local primary = getNodeAnchorPart(nodeInstance)
			if not primary then
				-- BasePart가 들어올 때까지 최대 3초 대기
				local t = 0
				while not primary and t < 3 do
					task.wait(0.2)
					t = t + 0.2
					primary = getNodeAnchorPart(nodeInstance)
				end
			end
			
			local nodeUID = nodeInstance:GetAttribute("NodeUID")
			-- 파트가 확인되었을 때만 생성 시도
			if primary then
				trackedNodes[nodeInstance] = true
				if nodeUID and nodeUID ~= "" then
					if nodeInstance:IsA("Model") then
						createHPBar(nodeInstance, nodeUID, 10) -- 기본 최대 타격 10 (Hit 이벤트 시 업데이트됨)
					end
				end
			end
		end)
	end
	
	local function onNodeRemoved(nodeInstance)
		if not nodeInstance then
			return
		end
		trackedNodes[nodeInstance] = nil
		local nodeUID = nodeInstance:GetAttribute("NodeUID")
		if nodeUID and activeBars[nodeUID] then
			activeBars[nodeUID]:Destroy()
			activeBars[nodeUID] = nil
			barVisibleUntil[nodeUID] = nil
		end
		if nodeHints[nodeInstance] then
			nodeHints[nodeInstance]:Destroy()
			nodeHints[nodeInstance] = nil
		end
	end

	local function hookNodeFolder(nodeFolder)
		if not nodeFolder then
			return
		end

		if nodeFolderConnAdded then
			nodeFolderConnAdded:Disconnect()
			nodeFolderConnAdded = nil
		end
		if nodeFolderConnRemoving then
			nodeFolderConnRemoving:Disconnect()
			nodeFolderConnRemoving = nil
		end

		for _, descendant in ipairs(nodeFolder:GetDescendants()) do
			if isAnyNodeCandidate(descendant, nodeFolder) then
				task.spawn(onNodeAdded, descendant)
			end
		end

		nodeFolderConnAdded = nodeFolder.DescendantAdded:Connect(function(descendant)
			if isAnyNodeCandidate(descendant, nodeFolder) then
				onNodeAdded(descendant)
			end
		end)

		nodeFolderConnRemoving = nodeFolder.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("Model") or descendant:IsA("BasePart") then
				onNodeRemoved(descendant)
			end
		end)
	end
	
	-- 1. 기존 노드 처리 및 태그 리스너 연결
	for _, node in ipairs(CollectionService:GetTagged("ResourceNode")) do
		task.spawn(onNodeAdded, node)
	end

	-- 1-1. 태그 누락 케이스를 위해 ResourceNodes 폴더 전체 스캔 + 동적 생성 대응
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if nodeFolder then
		hookNodeFolder(nodeFolder)
	else
		-- 클라이언트 초기화 후 ResourceNodes 폴더가 늦게 생기는 경우 대응
		workspaceConnChildAdded = workspace.ChildAdded:Connect(function(child)
			if child.Name == "ResourceNodes" then
				hookNodeFolder(child)
			end
		end)
	end

	-- 폴더/태그가 누락된 맵 배치 자원도 감지하는 전역 폴백
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if isAnyNodeCandidate(descendant, nodeFolder) then
			task.spawn(onNodeAdded, descendant)
		end
	end

	workspaceConnDescAdded = workspace.DescendantAdded:Connect(function(descendant)
		if isAnyNodeCandidate(descendant, workspace:FindFirstChild("ResourceNodes")) then
			onNodeAdded(descendant)
		end
	end)

	workspaceConnDescRemoving = workspace.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("Model") or descendant:IsA("BasePart") then
			onNodeRemoved(descendant)
		end
	end)
	
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
			barVisibleUntil[data.nodeUID] = nil
		end
		for nodeInstance, marker in pairs(nodeHints) do
			if nodeInstance and nodeInstance:GetAttribute("NodeUID") == data.nodeUID then
				if marker then marker:Destroy() end
				nodeHints[nodeInstance] = nil
				break
			end
		end
	end)
	
	initialized = true
	print("[ResourceUIController] Initialized")
end

return ResourceUIController
