-- DamageUIController.lua
-- 타격 데미지 및 기절 수치 시각화 (Floating Damage Text)
-- Phase 11-5: 전투 피드백 강화

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local DamageUIController = {}

--========================================
-- Constants
--========================================
local COLORS = {
	NORMAL = Color3.fromRGB(255, 255, 255),  -- 흰색: 일반 데미지
	CRITICAL = Color3.fromRGB(255, 200, 0), -- 금색: 크리티컬
	CRIT_STROKE = Color3.fromRGB(180, 60, 0), -- 진한 주황: 크리티컬 외곽선
	TORPOR = Color3.fromRGB(180, 100, 255), -- 보라색: 기절 수치
	HEAL = Color3.fromRGB(100, 255, 100),   -- 초록색: 회복
}

local BASE_TEXT_SIZE = 22
local MAX_TEXT_SIZE = 40
local CRIT_TEXT_MULT = 1.5  -- 치명타 텍스트 크기 배율
local DAMAGE_SCALE_REF = 50 -- 이 수치 이상이면 최대 크기

local initialized = false

--========================================
-- Private Functions
--========================================

--- 대상 모델 찾기 (속성 기반 검색)
local function findTargetModel(targetId: string): Instance?
	local targetModel = nil
	
	-- 1. 월드 내 대상 검색 (속성 기반 검색으로 정확도 향상)
	for _, folderName in ipairs({"ActiveCreatures", "Creatures", "Facilities", "ResourceNodes"}) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			-- 먼저 이름으로 시도
			local found = folder:FindFirstChild(targetId)
			if found then 
				targetModel = found
				break 
			end
			
			-- 이름으로 못 찾으면 속성 전수 조사 (Streaming 대응)
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("InstanceId") == targetId or 
				   child:GetAttribute("NodeUID") == targetId or 
				   child:GetAttribute("StructureId") == targetId then
					targetModel = child
					break
				end
			end
			if targetModel then break end
		end
	end
	
	if not targetModel then 
		-- 마지막 수단: 전체 태그 검색 (ResourceNode 등)
		local CollectionService = game:GetService("CollectionService")
		for _, model in ipairs(CollectionService:GetTagged("ResourceNode")) do
			if model:GetAttribute("NodeUID") == targetId then
				targetModel = model
				break
			end
		end
	end
	
	return targetModel
end

--- 데미지 텍스트 생성 및 애니메이션 (damageValue → 텍스트 크기 스케일링)
local function spawnDamageText(position: Vector3, text: string, color: Color3, damageValue: number?, isCritical: boolean?)
	local dmg = damageValue or 0
	local crit = isCritical == true
	-- 데미지 크기에 따른 텍스트 크기 (높을수록 큼)
	local sizeRatio = math.clamp(dmg / DAMAGE_SCALE_REF, 0, 1)
	local textSize = math.floor(BASE_TEXT_SIZE + (MAX_TEXT_SIZE - BASE_TEXT_SIZE) * sizeRatio)
	-- 치명타: 텍스트 크기 증폭
	if crit then
		textSize = math.floor(textSize * CRIT_TEXT_MULT)
	end
	
	local bbW = crit and 200 or 120
	local bbH = crit and 100 or 60
	
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageIndicator"
	billboard.Size = UDim2.new(0, bbW, 0, bbH)
	billboard.Adornee = nil -- World Position 사용
	billboard.AlwaysOnTop = true
	-- 위치 오프셋 (머리 위쪽으로 살짝 띄움)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	
	-- 월드 위치 고정을 위해 보이지 않는 파트 생성
	local attachment = Instance.new("Part")
	attachment.Size = Vector3.new(0.1, 0.1, 0.1)
	attachment.Transparency = 1
	attachment.CanCollide = false
	attachment.Anchored = true
	attachment.Position = position
	attachment.Parent = workspace.CurrentCamera
	
	billboard.Parent = attachment
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = crit and 0 or 0.3
	label.TextStrokeColor3 = crit and COLORS.CRIT_STROKE or Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = textSize
	label.TextScaled = false
	label.Parent = billboard
	
	-- 팝 스케일 (처음에 크게 → 원래 크기로 돌아옴)
	local popMult = crit and 2.0 or 1.5
	label.TextSize = math.floor(textSize * popMult)
	local popTween = TweenService:Create(label, TweenInfo.new(crit and 0.18 or 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = textSize,
	})
	popTween:Play()
	
	-- 애니메이션: 위로 튀어오르며 페이드아웃
	local riseHeight = crit and 5 or 4
	local targetPos = position + Vector3.new(math.random(-2, 2), riseHeight, math.random(-2, 2))
	local moveTween = TweenService:Create(attachment, TweenInfo.new(crit and 1.0 or 0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = targetPos
	})
	
	local fadeTween = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, crit and 0.6 or 0.4), {
		TextTransparency = 1,
		TextStrokeTransparency = 1
	})
	
	moveTween:Play()
	fadeTween:Play()
	
	task.delay(crit and 1.5 or 1.2, function()
		attachment:Destroy()
	end)
end

--========================================
-- Public API
--========================================

function DamageUIController.Init()
	if initialized then return end
	
	-- 1. 서버로부터 사냥/전투 타격 결과 수신
	NetClient.On("Combat.Hit.Result", function(data)
		-- data: { damage, torporDamage, killed, targetId, hitPosition? }
		
		local targetModel = findTargetModel(data.targetId)
		local spawnPos
		if targetModel then
			spawnPos = targetModel:GetPivot().Position
		elseif data.hitPosition then
			-- 크리처 사망 후 모델 제거됐을 때 서버에서 전송한 위치 사용
			spawnPos = Vector3.new(data.hitPosition.x, data.hitPosition.y, data.hitPosition.z)
		else
			return
		end
		
		-- 데미지 표시 (치명타 분기)
		if data.damage and data.damage > 0 then
			local dmgColor = data.isCritical and COLORS.CRITICAL or COLORS.NORMAL
			spawnDamageText(spawnPos, string.format("%.0f", data.damage), dmgColor, data.damage, data.isCritical)
		end
		
		-- 기절 수치 표시 (보라색)
		if data.torporDamage and data.torporDamage > 0 then
			task.wait(0.1) -- 겹치지 않게 살짝 딜레이
			spawnDamageText(spawnPos + Vector3.new(1, 0.5, 0), string.format("%.0f", data.torporDamage), COLORS.TORPOR, data.torporDamage)
		end
	end)
	
	-- 2. 서버로부터 채집 타격 결과 수신
	NetClient.On("Harvest.Node.Hit", function(data)
		-- data: { nodeUID, remainingHits, maxHits, damage }
		if not data.damage or data.damage <= 0 then return end
		
		local targetModel = findTargetModel(data.nodeUID)
		if not targetModel then return end
		
		local spawnPos = targetModel:GetPivot().Position
		spawnDamageText(spawnPos, string.format("%.0f", data.damage), COLORS.NORMAL, data.damage)
	end)
	
	-- 3. 플레이어 피격 데미지 표시 (빨간색)
	local localPlayer = Players.LocalPlayer
	NetClient.On("Combat.Player.Hit", function(data)
		if not data.damage or data.damage <= 0 then return end
		local char = localPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		spawnDamageText(hrp.Position + Vector3.new(0, 2, 0), string.format("-%.0f", data.damage), Color3.fromRGB(255, 50, 50), data.damage)
	end)
	
	initialized = true
	print("[DamageUIController] Initialized")
end

return DamageUIController
