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
	applyPrehistoricStyle(player, character) -- player 인자 추가
	setupCharacterAttributes(player, character)
	
	-- [기존/신규 유저 첫 스폰 위치 설정 (수면 위치 복구)]
	-- HasSpawnedFirstTime 속성으로 처음 1회 접속 시점만 체크 (사망 시에는 PlayerLifeService가 처리)
	if not player:GetAttribute("HasSpawnedFirstTime") then
		player:SetAttribute("HasSpawnedFirstTime", true)
		
		task.spawn(function()
			local ok, SaveService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.SaveService) end)
			if ok and SaveService then
				-- 데이터 로딩 대기
				local hrp = character:WaitForChild("HumanoidRootPart", 5)
				if hrp then
					local state = SaveService.getPlayerState(player.UserId)
					if state and state.lastPosition then
						-- 기존 유저: 마지막 수면 위치 복원
						-- 약간의 대기 후 안전하게 텔레포트
						task.wait(0.2)
						character:PivotTo(CFrame.new(
							state.lastPosition.x,
							state.lastPosition.y + 5, -- 바닥에 끼지 않도록 조금 위쪽
							state.lastPosition.z
						))
						print(string.format("[CharacterSetupService] Existing player %s spawned at previous sleep location", player.Name))
					else
						-- 신규 유저: 기본(첫 게임 시작 스폰 포인트)
						task.wait(0.2)
						local spawnPos = Vector3.new(0, 50, 0)
						-- 개발자가 맵에 올려둔 실제 파트가 있다면 그것을 우선순위로 채택
						local defaultSpawnPart = workspace:FindFirstChild("SpawnLocation")
						if defaultSpawnPart and defaultSpawnPart:IsA("SpawnLocation") then
							spawnPos = defaultSpawnPart.Position + Vector3.new(0, 5, 0)
						else
							-- 없다면 하드코딩된 설정 좌표 사용
							local okConfig, SpawnConfig = pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Config.SpawnConfig) end)
							if okConfig and SpawnConfig and SpawnConfig.DEFAULT_START_SPAWN then
								spawnPos = SpawnConfig.DEFAULT_START_SPAWN
							end
						end
						
						character:PivotTo(CFrame.new(spawnPos))
						print(string.format("[CharacterSetupService] New player %s spawned at starting point %s", player.Name, tostring(spawnPos)))
					end
				end
			end
		end)
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
