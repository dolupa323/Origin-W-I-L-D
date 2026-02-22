-- CharacterSetupService.lua
-- 플레이어 캐릭터 외형 설정 (선사시대 스타일)
-- 원시/부족 테마 의상 및 액세서리 적용

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local CharacterSetupService = {}

--========================================
-- Dependencies
--========================================
local initialized = false

--========================================
-- 선사시대 스타일 설정
--========================================
-- 피부 톤 (황갈색 계열)
local SKIN_TONES = {
	Color3.fromRGB(180, 140, 100),  -- 황갈색
	Color3.fromRGB(160, 120, 85),   -- 진한 황갈색
	Color3.fromRGB(200, 160, 120),  -- 밝은 황갈색
	Color3.fromRGB(140, 100, 70),   -- 어두운 갈색
}

-- 머리카락 색상 (짙은 갈색/검정)
local HAIR_COLORS = {
	Color3.fromRGB(35, 25, 20),   -- 검정
	Color3.fromRGB(60, 40, 30),   -- 짙은 갈색
	Color3.fromRGB(80, 55, 40),   -- 갈색
}

-- 원시 의상 색상 (가죽/모피)
local CLOTHING_COLORS = {
	Color3.fromRGB(101, 67, 33),   -- 가죽 갈색
	Color3.fromRGB(85, 60, 42),    -- 어두운 가죽
	Color3.fromRGB(139, 90, 43),   -- 밝은 가죽
	Color3.fromRGB(110, 80, 50),   -- 모피 색
}

--========================================
-- Internal Functions
--========================================

--- 랜덤 색상 선택
local function randomChoice(tbl)
	return tbl[math.random(1, #tbl)]
end

--- 신체 부위 색상 설정
local function setBodyPartColor(character, partName: string, color: Color3)
	local part = character:FindFirstChild(partName)
	if part and part:IsA("BasePart") then
		part.Color = color
	end
end

--- 선사시대 스타일 적용
local function applyPrehistoricStyle(character)
	-- Humanoid Description 가져오기
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- 랜덤 피부톤 선택
	local skinTone = randomChoice(SKIN_TONES)
	local clothingColor = randomChoice(CLOTHING_COLORS)
	
	-- 신체 색상 설정
	local bodyParts = {
		"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
		"UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg",
		"LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"
	}
	
	for _, partName in ipairs(bodyParts) do
		-- 몸통과 팔다리 일부는 의상 색상
		if partName == "Torso" or partName == "UpperTorso" or partName == "LowerTorso" then
			setBodyPartColor(character, partName, clothingColor)
		elseif partName:find("Leg") or partName:find("Foot") then
			-- 하반신: 가죽 치마처럼 의상 색
			setBodyPartColor(character, partName, clothingColor)
		else
			-- 나머지: 피부색
			setBodyPartColor(character, partName, skinTone)
		end
	end
	
	-- 머리 색상 (얼굴)
	local head = character:FindFirstChild("Head")
	if head then
		head.Color = skinTone
	end
	
	-- 기존 의상/액세서리 제거 (현대적 요소)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			-- 기존 현대 의상 유지 안함 (필요시 제거)
			-- child:Destroy()
		end
	end
	
	-- 선사시대 의상 생성 (클래식 셔츠/바지로 가죽 느낌)
	local shirt = character:FindFirstChild("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Name = "Shirt"
		shirt.Parent = character
	end
	-- 가죽 조끼 느낌의 텍스처 (기본 ID - 실제 에셋 교체 권장)
	shirt.ShirtTemplate = "rbxassetid://398633812"  -- 기본 갈색 셔츠
	
	local pants = character:FindFirstChild("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Name = "Pants"
		pants.Parent = character
	end
	-- 가죽 반바지/치마 느낌
	pants.PantsTemplate = "rbxassetid://398633812"  -- 기본 갈색 바지
	
	-- Body Part 색상 적용 (HumanoidDescription 방식)
	task.spawn(function()
		pcall(function()
			local desc = humanoid:GetAppliedDescription()
			if desc then
				desc.HeadColor = skinTone
				desc.LeftArmColor = skinTone
				desc.RightArmColor = skinTone
				desc.LeftLegColor = clothingColor
				desc.RightLegColor = clothingColor
				desc.TorsoColor = clothingColor
				
				-- HairColor는 별도 처리
				-- desc.HairColor = randomChoice(HAIR_COLORS)
				
				humanoid:ApplyDescription(desc)
			end
		end)
	end)
	
	print(string.format("[CharacterSetupService] Applied prehistoric style to %s", character.Name))
end

--========================================
-- 캐릭터 설정 속성 추가
--========================================

local function setupCharacterAttributes(player: Player, character)
	-- 플레이어 데이터 연동 시 여기에 속성 설정
	-- 예: 부족, 레벨 등에 따른 외형 변화
	
	character:SetAttribute("SetupComplete", true)
	character:SetAttribute("CharacterStyle", "PREHISTORIC")
end

--========================================
-- Public API
--========================================

function CharacterSetupService.Init()
	if initialized then return end
	
	-- 기존 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			applyPrehistoricStyle(player.Character)
			setupCharacterAttributes(player, player.Character)
		end
		
		player.CharacterAdded:Connect(function(character)
			-- 잠시 대기 (Humanoid 로딩)
			task.wait(0.5)
			applyPrehistoricStyle(character)
			setupCharacterAttributes(player, character)
		end)
	end
	
	-- 새 플레이어 처리
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.wait(0.5)
			applyPrehistoricStyle(character)
			setupCharacterAttributes(player, character)
		end)
	end)
	
	initialized = true
	print("[CharacterSetupService] Initialized")
end

--- 수동으로 스타일 재적용
function CharacterSetupService.refreshStyle(player: Player)
	if player.Character then
		applyPrehistoricStyle(player.Character)
	end
end

return CharacterSetupService
