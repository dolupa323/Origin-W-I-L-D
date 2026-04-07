-- CharacterSetupService.lua
-- 플레이어 캐릭터 외형 설정 (선사시대 스타일)
-- 원시/부족 테마 의상 및 액세서리 적용

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

--- 선사시대 스타일 적용
local function applyPrehistoricStyle(player, character)
	-- 한 프레임 양보: 캐릭터가 Workspace에 완전히 parent된 후 작업
	task.wait()

	local humanoid = character:WaitForChild("Humanoid", 15)
	if not humanoid then return end
	
	-- 1. 플레이어 UserId 기반 랜덤 시드
	local rng = Random.new(player.UserId)
	local skinTone = Appearance.SKIN_TONES[rng:NextInteger(1, #Appearance.SKIN_TONES)]
	local clothingColor = Appearance.CLOTHING_COLORS[rng:NextInteger(1, #Appearance.CLOTHING_COLORS)]
	
	-- 2. 기존 액세서리, 의상, 패키지 파트 삭제
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("ShirtGraphic") or child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end
	
	-- 3. 신체 부위별 색상 적용 (피부 VS 의상 구분)
	-- 피부 영역: Head, 양팔
	local skinParts = {
		"Head",
		"Left Arm", "Right Arm",
		"LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand",
	}
	-- 의상 영역: 몸통, 다리 (가죽 의상이 덮는 부분)
	local clothingParts = {
		"Torso", "UpperTorso", "LowerTorso",
		"Left Leg", "Right Leg",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	}
	
	for _, name in ipairs(skinParts) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = skinTone
		end
	end
	
	for _, name in ipairs(clothingParts) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = clothingColor
		end
	end
	
	-- 4. 클래식 의상 강제 주입 (Shirt/Pants Instance 직접 수정)
	-- 기존 Shirt/Pants가 있으면 재사용, 없으면 새로 생성
	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Name = "Shirt"
		shirt.Parent = character
	end
	shirt.ShirtTemplate = Appearance.CLOTHING_IDS.DEFAULT_SHIRT
	
	local pants = character:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Name = "Pants"
		pants.Parent = character
	end
	pants.PantsTemplate = Appearance.CLOTHING_IDS.DEFAULT_PANTS
	
	-- 5. ChildAdded 감시: 로블록스 엔진이 나중에 유저 액세서리를 다시 끼우려 하면 즉시 삭제
	local conn
	conn = character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") then
			child:Destroy()
		end
	end)
	-- 5초 후 감시 해제 (무한 감시 방지)
	task.delay(5, function()
		if conn then conn:Disconnect() end
	end)
	
	-- 4. 물리적 보정 및 직립 유지 설정
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	
	-- [강력 차단] 캐릭터가 바닥에 눕거나 뒤집히는 것을 방지하기 위해 BodyGyro 강화
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		local gyro = hrp:FindFirstChild("UprightForce") or Instance.new("BodyGyro")
		gyro.Name = "UprightForce"
		gyro.MaxTorque = Vector3.new(1, 0, 1) * 2e6 -- X, Z축 회전 강력 차단
		gyro.P = 20000 -- 회전 복원력 대폭 상향
		gyro.D = 500  -- 감쇄
		gyro.CFrame = hrp.CFrame
		gyro.Parent = hrp
		
		-- 인체공학적 서기 (HipHeight 조정)
		humanoid.HipHeight = 2.0
	end

	-- [체력 재생 비활성화] Roblox 기본 Health 스크립트 제거 + 커스텀 재생 설정
	local defaultHealthScript = character:FindFirstChild("Health")
	if defaultHealthScript then
		defaultHealthScript:Destroy()
	end
	-- Roblox 기본 재생 비활성화 후, 커스텀 극미량 재생 적용
	task.spawn(function()
		local okBal, Bal = pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Config.Balance) end)
		local regenRate = (okBal and Bal and Bal.HEALTH_REGEN_RATE) or 0.001
		while character.Parent and humanoid and humanoid.Health > 0 do
			if humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + (humanoid.MaxHealth * regenRate))
			end
			task.wait(1)
		end
	end)
	
	print(string.format("[CharacterSetupService] Applied prehistoric style & Upright Physics to %s", character.Name))
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
	-- [통합 스폰 처리] 접속/재접속/사망 리스폰 모두 동일하게 SpawnPos attribute로 즉시 PivotTo
	-- SaveService(접속) 또는 PlayerLifeService(사망)에서 LoadCharacter 전에 SpawnPos를 설정함
	local spawnX = player:GetAttribute("SpawnPosX")
	local spawnY = player:GetAttribute("SpawnPosY")
	local spawnZ = player:GetAttribute("SpawnPosZ")

	if spawnX and spawnY and spawnZ then
		local targetPos = Vector3.new(spawnX, spawnY, spawnZ)
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			-- ★ [FIX] Y좌표 강제 보정: 항상 최소 15 이상 보장 (respawn 팅김 방지)
			if targetPos.Y < 15 then
				print(string.format("[CharacterSetupService] Y=%.1f is unsafe, enforcing Y=%.1f", targetPos.Y, targetPos.Y + 20))
				targetPos = Vector3.new(targetPos.X, targetPos.Y + 20, targetPos.Z)
			end
			
			-- Anchor로 Roblox 엔진의 위치 덮어쓰기를 차단한 뒤 즉시 PivotTo
			hrp.Anchored = true
			character:PivotTo(CFrame.new(targetPos))
			print(string.format("[CharacterSetupService] Spawned %s at position: %.1f, %.1f, %.1f (death=%s)",
				player.Name, targetPos.X, targetPos.Y, targetPos.Z,
				tostring(player:GetAttribute("PendingDeathRespawn") or false)))
		end
	else
		print(string.format("[CharacterSetupService] %s: No spawn attributes set (new player or data not loaded)", player.Name))
	end

	-- 외형 + 속성 적용 (위치가 이미 확정된 후, Anchor 상태에서 안전하게 처리)
	applyPrehistoricStyle(player, character)
	setupCharacterAttributes(player, character)

	-- applyPrehistoricStyle 완료 후 Anchor 해제 (applyPrehistoricStyle 내부에 task.wait()이 있음)
	local hrpFinal = character:FindFirstChild("HumanoidRootPart")
	if hrpFinal and hrpFinal.Anchored then
		-- 최종 위치 재확인 후 해제
		if spawnX and spawnY and spawnZ then
			local finalPos = Vector3.new(spawnX, spawnY, spawnZ)
			-- 최종 보정도 적용
			if finalPos.Y < 15 then
				finalPos = Vector3.new(finalPos.X, finalPos.Y + 20, finalPos.Z)
			end
			character:PivotTo(CFrame.new(finalPos))
		end
		hrpFinal.Anchored = false
		print(string.format("[CharacterSetupService] Anchor released for %s", player.Name))
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	
	-- [FIX] 로블록스 기본 외형 로딩 후 우리 스타일로 덮어쓰기
	player.CharacterAppearanceLoaded:Connect(function(character)
		applyPrehistoricStyle(player, character)
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
		applyPrehistoricStyle(player, player.Character)
	end
end

return CharacterSetupService
