-- CharacterSetupService.lua
-- 플레이어 캐릭터 외형 설정 (선사시대 스타일)
-- 원시/부족 테마 의상 및 액세서리 적용

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Appearance = require(Shared.Config.Appearance)

local CharacterSetupService = {}

--========================================
-- Dependencies
--========================================
local initialized = false

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
	-- Humanoid Description 가져오기 (동기적 대기)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	
	-- 랜덤 피부톤 선택
	local skinTone = randomChoice(Appearance.SKIN_TONES)
	local clothingColor = randomChoice(Appearance.CLOTHING_COLORS)
	
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
	-- 가죽 조끼 느낌의 텍스처
	shirt.ShirtTemplate = Appearance.CLOTHING_IDS.DEFAULT_SHIRT
	
	local pants = character:FindFirstChild("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Name = "Pants"
		pants.Parent = character
	end
	-- 가죽 반바지/치마 느낌
	pants.PantsTemplate = Appearance.CLOTHING_IDS.DEFAULT_PANTS
	
	-- Body Part 색상 적용 (HumanoidDescription 방식, 동기화)
	-- 주의: ApplyDescription은 캐릭터가 DataModel(Workspace)에 소속되어 있어야만 호출 가능합니다.
	if not character:IsDescendantOf(game) then
		character.AncestryChanged:Wait()
	end
	if not character.Parent then return end -- 도중에 파괴된 경우 중단
	
	local success, err = pcall(function()
		local desc = humanoid:GetAppliedDescription()
		if desc then
			desc.HeadColor = skinTone
			desc.LeftArmColor = skinTone
			desc.RightArmColor = skinTone
			desc.LeftLegColor = clothingColor
			desc.RightLegColor = clothingColor
			desc.TorsoColor = clothingColor
			
			-- HairColor는 별도 처리
			-- desc.HairColor = randomChoice(Appearance.HAIR_COLORS)
			
			humanoid:ApplyDescription(desc)
		end
	end)
	
	if not success then
		warn(string.format("[CharacterSetupService] Failed to ApplyDescription to %s: %s", character.Name, tostring(err)))
	end
	
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

local function onCharacterAdded(player: Player, character)
	applyPrehistoricStyle(character)
	setupCharacterAttributes(player, character)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	
	-- 이 시점에 이미 캐릭터가 존재하는 경우 즉시 처리
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function CharacterSetupService.Init()
	if initialized then return end
	
	-- 기존 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	
	-- 새 플레이어 처리
	Players.PlayerAdded:Connect(onPlayerAdded)
	
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
