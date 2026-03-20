-- PetService.lua
-- 도감 펫 시스템 (소환/전투/추적/슬롯 관리)
-- 도감 완성 시 해당 크리처를 미니어처 펫으로 소환 가능

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)
local DataHelper = require(Shared.Util.DataHelper)

local PetService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController
local DataService
local PlayerStatService
local SaveService
local CreatureService

--========================================
-- Internal State
--========================================
-- petSlots[userId] = { [1] = "COMPY", [2] = nil, [3] = nil }
local petSlots = {}
-- maxUnlockedSlots[userId] = 1 (기본), BM으로 확장 가능
local maxUnlockedSlots = {}
-- activePets[userId] = { [1] = { model, creatureId, health, lastAttack }, ... }
local activePets = {}
-- 펫 모델 캐시
local modelCache = {}

--========================================
-- Model Cache
--========================================
local function indexPetModels()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	local folders = {
		assets:FindFirstChild("CreatureModels"),
		assets:FindFirstChild("Creatures"),
		assets:FindFirstChild("Models"),
		assets,
	}
	for _, folder in ipairs(folders) do
		if not folder then continue end
		for _, child in ipairs(folder:GetDescendants()) do
			if child:IsA("Model") then
				if not modelCache[child.Name] then
					modelCache[child.Name] = child
				end
				local norm = child.Name:lower():gsub("_", "")
				if not modelCache[norm] then
					modelCache[norm] = child
				end
			end
		end
	end
end

local function findCreatureModel(modelName: string)
	return modelCache[modelName]
		or modelCache[modelName:lower():gsub("_", "")]
end

--========================================
-- Helpers
--========================================

local function _getCreatureData(creatureId: string)
	return DataHelper.GetData("CreatureData", creatureId)
end

--- 도감 완성 여부 확인
function PetService.isCodexComplete(userId: number, creatureId: string): boolean
	if not PlayerStatService then return false end
	local stats = PlayerStatService.getStats(userId)
	if not stats or not stats.dnaData then return false end
	local cData = _getCreatureData(creatureId)
	if not cData then return false end
	local required = cData.dnaRequired or 5
	local current = stats.dnaData[string.upper(creatureId)] or 0
	return current >= required
end

--- 플레이어 펫 슬롯 로드
local function _initPetSlots(userId: number)
	if petSlots[userId] then return end

	local state = nil
	if SaveService and SaveService.getPlayerState then
		state = SaveService.getPlayerState(userId)
		local deadline = os.clock() + 10
		while not state and os.clock() < deadline do
			task.wait(0.1)
			state = SaveService.getPlayerState(userId)
		end
	end

	local saved = state and state.petSlots
	petSlots[userId] = saved and table.clone(saved) or {}
	maxUnlockedSlots[userId] = (state and state.petMaxSlots) or Balance.PET_DEFAULT_SLOTS
	activePets[userId] = {}
end

--- 펫 슬롯 저장
local function _savePetSlots(userId: number)
	if not SaveService or not SaveService.updatePlayerState then return end
	local slots = petSlots[userId]
	local maxSlots = maxUnlockedSlots[userId]
	SaveService.updatePlayerState(userId, function(state)
		state.petSlots = slots
		state.petMaxSlots = maxSlots
		return state
	end)
end

--- 펫 슬롯 클라이언트 동기화
local function _syncPetSlots(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player or not NetController then return end
	NetController.FireClient(player, "Pet.Sync", {
		slots = petSlots[userId] or {},
		maxSlots = maxUnlockedSlots[userId] or Balance.PET_DEFAULT_SLOTS,
		completed = PetService.getCompletedCreatures(userId),
	})
end

--========================================
-- Pet Spawning
--========================================

local PET_FOLDER_NAME = "ActivePets"

local function _getPetFolder()
	local folder = workspace:FindFirstChild(PET_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PET_FOLDER_NAME
		folder.Parent = workspace
	end
	return folder
end

--- 모델 바운딩박스 기준 중심 좌표
local function _getModelCenter(model)
	local cf, size = model:GetBoundingBox()
	return cf.Position
end

--- 모델 바운딩박스 높이
local function _getModelHeight(model)
	local _, size = model:GetBoundingBox()
	return size.Y
end

--- 모델을 목표 최대 치수(스터드)로 수동 스케일링
local function _scaleModelToSize(model, targetMaxSize)
	local _, bbox = model:GetBoundingBox()
	local maxDim = math.max(bbox.X, bbox.Y, bbox.Z)
	if maxDim < 0.01 then return end

	local scaleFactor = targetMaxSize / maxDim
	local pivot = model:GetPivot()

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Size = desc.Size * scaleFactor
			local relCF = pivot:ToObjectSpace(desc.CFrame)
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = relCF:GetComponents()
			local px, py, pz = relCF.X * scaleFactor, relCF.Y * scaleFactor, relCF.Z * scaleFactor
			desc.CFrame = pivot:ToWorldSpace(CFrame.new(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22))
		elseif desc:IsA("SpecialMesh") then
			desc.Scale = desc.Scale * scaleFactor
			if desc.Offset ~= Vector3.zero then
				desc.Offset = desc.Offset * scaleFactor
			end
		elseif desc:IsA("Attachment") then
			desc.Position = desc.Position * scaleFactor
		end
	end
end

--- 크리처 모델과 동일한 방식으로 펫 모델 셋업 (Humanoid + HRP + Weld)
local function _setupPetModel(petModel, position, data)
	-- 1. 기존 스크립트/사운드/GUI 제거
	for _, child in ipairs(petModel:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript")
			or child:IsA("Sound") or child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end

	-- 2. HumanoidRootPart 찾기 또는 생성
	local rootPart = petModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		local center = _getModelCenter(petModel)
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(1, 1, 1)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.CanQuery = true
		rootPart.Position = center
		rootPart.Parent = petModel

		-- 모든 BasePart를 HumanoidRootPart에 Weld
		for _, part in ipairs(petModel:GetDescendants()) do
			if part:IsA("BasePart") and part ~= rootPart then
				part.Anchored = false
				local hasWeld = false
				for _, c in ipairs(part:GetChildren()) do
					if c:IsA("WeldConstraint") or c:IsA("Weld") or c:IsA("Motor6D") then
						hasWeld = true
						break
					end
				end
				if not hasWeld then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = rootPart
					weld.Part1 = part
					weld.Parent = rootPart
				end
			end
		end
	end

	-- 3. 모든 파트 Anchored=false, 충돌 그룹 설정
	for _, part in ipairs(petModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CollisionGroup = "Creatures"
		end
	end

	-- 4. PrimaryPart
	petModel.PrimaryPart = rootPart

	-- 5. 위치 이동
	local modelHeight = _getModelHeight(petModel)
	local offset = Vector3.new(0, modelHeight / 2 + 1, 0)
	petModel:PivotTo(CFrame.new(position + offset))

	-- 6. Humanoid 찾기 또는 생성
	local humanoid = petModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = petModel
	end

	-- 7. Humanoid 설정 (크리처와 동일한 패턴)
	humanoid.WalkSpeed = data.walkSpeed or Balance.PET_FOLLOW_SPEED
	humanoid.MaxHealth = data.petHealth or 50
	humanoid.Health = data.petHealth or 50
	humanoid.MaxSlopeAngle = 89
	humanoid.AutoJumpEnabled = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 40

	-- HipHeight 계산 (지면에 서기 위한 높이)
	local modelCF, modelSize = petModel:GetBoundingBox()
	local bottomToCenter = rootPart.Position.Y - (modelCF.Position.Y - modelSize.Y / 2)
	humanoid.HipHeight = math.max(0.5, bottomToCenter - (rootPart.Size.Y / 2) + 0.3)

	return petModel, rootPart, humanoid
end

local function _despawnPet(userId: number, slotIndex: number)
	local pets = activePets[userId]
	if not pets or not pets[slotIndex] then return end
	local petInfo = pets[slotIndex]
	if petInfo.model and petInfo.model.Parent then
		petInfo.model:Destroy()
	end
	pets[slotIndex] = nil
end

local function _spawnPet(userId: number, slotIndex: number, creatureId: string)
	local player = Players:GetPlayerByUserId(userId)
	if not player or not player.Character then return end

	local cData = _getCreatureData(creatureId)
	if not cData then return end

	local template = findCreatureModel(cData.modelName)
	if not template then
		warn("[PetService] Model not found:", cData.modelName)
		return
	end

	-- 기존 펫 제거
	_despawnPet(userId, slotIndex)

	local petModel = template:Clone()
	petModel.Name = string.format("Pet_%d_%d_%s", userId, slotIndex, creatureId)

	-- 1. 수동 스케일링 (petScale = 목표 최대 치수, 스터드 단위)
	local targetSize = cData.petScale or 2.5
	_scaleModelToSize(petModel, targetSize)

	-- 2. 크리처와 동일한 모델 셋업 (HRP + Weld + Humanoid)
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	local spawnPos = rootPart and rootPart.Position or player.Character:GetPivot().Position
	local angle = math.rad(120 * (slotIndex - 1))
	local spawnOffset = Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4)

	petModel, _, _ = _setupPetModel(petModel, spawnPos + spawnOffset, cData)

	-- 3. 속성 설정 (애니메이션 컨트롤러가 자동으로 인식)
	petModel:SetAttribute("CreatureId", string.upper(creatureId))
	petModel:SetAttribute("State", "WANDER")
	petModel:SetAttribute("IsPet", true)

	-- 4. 월드에 배치
	petModel.Parent = _getPetFolder()

	-- 5. 사망 시 재소환
	local hum = petModel:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			_despawnPet(userId, slotIndex)
			if NetController then
				NetController.FireClient(player, "Pet.Died", { slotIndex = slotIndex, creatureId = creatureId })
			end
			task.delay(Balance.PET_RESPAWN_TIME, function()
				local slots = petSlots[userId]
				if slots and slots[slotIndex] == creatureId and Players:GetPlayerByUserId(userId) then
					_spawnPet(userId, slotIndex, creatureId)
					if NetController then
						NetController.FireClient(player, "Pet.Respawned", { slotIndex = slotIndex, creatureId = creatureId })
					end
				end
			end)
		end)
	end

	activePets[userId] = activePets[userId] or {}
	activePets[userId][slotIndex] = {
		model = petModel,
		creatureId = creatureId,
		health = cData.petHealth or 50,
		maxHealth = cData.petHealth or 50,
		lastAttack = 0,
		damage = cData.petDamage or 5,
	}
end

--========================================
-- Public API: Slot Management
--========================================

function PetService.equipPet(userId: number, slotIndex: number, creatureId: string): (boolean, string?)
	_initPetSlots(userId)

	-- 슬롯 범위 검증
	if slotIndex < 1 or slotIndex > Balance.PET_MAX_SLOTS then
		return false, "INVALID_SLOT"
	end

	-- 해금된 슬롯 검증
	local maxSlots = maxUnlockedSlots[userId] or Balance.PET_DEFAULT_SLOTS
	if slotIndex > maxSlots then
		return false, "SLOT_LOCKED"
	end

	-- 도감 완성 확인
	if not PetService.isCodexComplete(userId, creatureId) then
		return false, "CODEX_INCOMPLETE"
	end

	-- 이미 다른 슬롯에 같은 펫이 장착되어 있으면 제거
	for i, cid in pairs(petSlots[userId]) do
		if cid == creatureId and i ~= slotIndex then
			_despawnPet(userId, i)
			petSlots[userId][i] = nil
		end
	end

	-- 기존 슬롯의 펫 교체
	_despawnPet(userId, slotIndex)
	petSlots[userId][slotIndex] = creatureId

	_savePetSlots(userId)
	_syncPetSlots(userId)

	-- 소환
	_spawnPet(userId, slotIndex, creatureId)

	return true
end

function PetService.unequipPet(userId: number, slotIndex: number): (boolean, string?)
	_initPetSlots(userId)

	if slotIndex < 1 or slotIndex > Balance.PET_MAX_SLOTS then
		return false, "INVALID_SLOT"
	end

	_despawnPet(userId, slotIndex)
	petSlots[userId][slotIndex] = nil

	_savePetSlots(userId)
	_syncPetSlots(userId)

	return true
end

function PetService.getEquippedPets(userId: number)
	_initPetSlots(userId)
	return petSlots[userId] or {}
end

function PetService.getMaxSlots(userId: number): number
	_initPetSlots(userId)
	return maxUnlockedSlots[userId] or Balance.PET_DEFAULT_SLOTS
end

--- 도감 완성 크리처 목록 반환
function PetService.getCompletedCreatures(userId: number): {string}
	local result = {}
	local tbl = DataHelper.GetTable("CreatureData") or {}
	for _, cData in pairs(tbl) do
		if PetService.isCodexComplete(userId, cData.id) then
			table.insert(result, cData.id)
		end
	end
	return result
end

--========================================
-- Pet AI Loop (Humanoid:MoveTo 기반 자연스러운 이동 + 상태 속성 동기화)
--========================================

local AI_TICK = 0.3

local function _petAITick()
	for userId, pets in pairs(activePets) do
		local player = Players:GetPlayerByUserId(userId)
		if not player or not player.Character then continue end

		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end

		for slotIndex, petInfo in pairs(pets) do
			if not petInfo.model or not petInfo.model.Parent then continue end

			local petHum = petInfo.model:FindFirstChildOfClass("Humanoid")
			if not petHum or petHum.Health <= 0 then continue end

			local petRoot = petInfo.model.PrimaryPart
			if not petRoot then continue end

			local petPos = petRoot.Position
			local playerPos = rootPart.Position
			local distToPlayer = (Vector3.new(petPos.X, 0, petPos.Z) - Vector3.new(playerPos.X, 0, playerPos.Z)).Magnitude

			-- 텔레포트 (너무 멀리 떨어졌을 때)
			if distToPlayer > Balance.PET_LEASH_DIST then
				local angle = math.rad(120 * (slotIndex - 1))
				local offset = Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4)
				petInfo.model:PivotTo(CFrame.new(playerPos + offset + Vector3.new(0, 2, 0)))
				continue
			end

			-- 적 탐색
			local nearestEnemy = nil
			local nearestDist = Balance.PET_DETECT_RANGE
			local nearestInstanceId = nil

			local creaturesFolder = workspace:FindFirstChild("Creatures")
			if creaturesFolder then
				for _, creatureModel in ipairs(creaturesFolder:GetChildren()) do
					if creatureModel:IsA("Model") then
						local iid = creatureModel:GetAttribute("InstanceId")
						if iid then
							local cHum = creatureModel:FindFirstChildOfClass("Humanoid")
							if cHum and cHum.Health > 0 then
								local cRoot = creatureModel.PrimaryPart
									or creatureModel:FindFirstChild("HumanoidRootPart")
									or creatureModel:FindFirstChildWhichIsA("BasePart", true)
								if cRoot then
									local dist = (petPos - cRoot.Position).Magnitude
									if dist < nearestDist then
										nearestDist = dist
										nearestEnemy = creatureModel
										nearestInstanceId = iid
									end
								end
							end
						end
					end
				end
			end

			local now = os.clock()

			-- 플레이어 이동 감지 (속도 체크)
			local playerVelocity = rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
			local playerMoving = playerVelocity.Magnitude > 1.5

			-- 정지 반경: 이 거리 이내면 멈춤 (비비기 방지)
			local STOP_RADIUS = 8
			-- 따라가기 시작 거리: 이 거리 이상 벌어지면 다시 따라감
			local FOLLOW_RADIUS = 12

			-- 전투: 공격 범위 내 적
			if nearestEnemy and nearestDist <= Balance.PET_ATTACK_RANGE then
				petInfo.model:SetAttribute("State", "CHASE")
				petHum.WalkSpeed = Balance.PET_FOLLOW_SPEED * 1.2

				if now - (petInfo.lastAttack or 0) >= Balance.PET_ATTACK_COOLDOWN then
					petInfo.lastAttack = now
					if CreatureService and CreatureService.processAttack and nearestInstanceId then
						CreatureService.processAttack(nearestInstanceId, petInfo.damage, 0, player)
					end
				end

				local eRoot = nearestEnemy.PrimaryPart
					or nearestEnemy:FindFirstChild("HumanoidRootPart")
					or nearestEnemy:FindFirstChildWhichIsA("BasePart", true)
				if eRoot then
					petHum:MoveTo(eRoot.Position)
				end

			-- 추적: 감지 범위 내 적
			elseif nearestEnemy and nearestDist <= Balance.PET_DETECT_RANGE then
				petInfo.model:SetAttribute("State", "CHASE")
				petHum.WalkSpeed = Balance.PET_FOLLOW_SPEED * 1.2

				local eRoot = nearestEnemy.PrimaryPart
					or nearestEnemy:FindFirstChild("HumanoidRootPart")
					or nearestEnemy:FindFirstChildWhichIsA("BasePart", true)
				if eRoot then
					petHum:MoveTo(eRoot.Position)
				end

			-- 멀리 떨어졌으면 → 플레이어 근처로 이동 (정확한 좌표가 아니라 옆쪽 오프셋)
			elseif distToPlayer > FOLLOW_RADIUS then
				petInfo.model:SetAttribute("State", "WANDER")
				petHum.WalkSpeed = Balance.PET_FOLLOW_SPEED
				-- 플레이어 정확한 위치가 아니라 STOP_RADIUS 거리의 옆쪽 지점으로 이동
				local dirToPet = (petPos - playerPos) * Vector3.new(1, 0, 1)
				local stopTarget
				if dirToPet.Magnitude > 0.1 then
					stopTarget = playerPos + dirToPet.Unit * STOP_RADIUS
				else
					local angle = math.rad(120 * (slotIndex - 1))
					stopTarget = playerPos + Vector3.new(math.cos(angle) * STOP_RADIUS, 0, math.sin(angle) * STOP_RADIUS)
				end
				petHum:MoveTo(stopTarget)

			-- 정지 반경 밖 + 플레이어 움직이는 중 → 따라가기
			elseif playerMoving and distToPlayer > STOP_RADIUS then
				petInfo.model:SetAttribute("State", "WANDER")
				petHum.WalkSpeed = Balance.PET_FOLLOW_SPEED
				local dirToPet = (petPos - playerPos) * Vector3.new(1, 0, 1)
				local stopTarget
				if dirToPet.Magnitude > 0.1 then
					stopTarget = playerPos + dirToPet.Unit * STOP_RADIUS
				else
					local angle = math.rad(120 * (slotIndex - 1))
					stopTarget = playerPos + Vector3.new(math.cos(angle) * STOP_RADIUS, 0, math.sin(angle) * STOP_RADIUS)
				end
				petHum:MoveTo(stopTarget)

			-- 정지 반경 이내 → 완전 정지
			else
				if petInfo.model:GetAttribute("State") ~= "IDLE" then
					petInfo.model:SetAttribute("State", "IDLE")
					petHum:MoveTo(petRoot.Position)
				end
			end
		end
	end
end

--========================================
-- Handlers
--========================================

local function handleEquipPet(player, payload)
	if not payload or not payload.slotIndex or not payload.creatureId then
		return { success = false, errorCode = "BAD_REQUEST" }
	end
	local ok, err = PetService.equipPet(player.UserId, payload.slotIndex, payload.creatureId)
	return { success = ok, errorCode = err }
end

local function handleUnequipPet(player, payload)
	if not payload or not payload.slotIndex then
		return { success = false, errorCode = "BAD_REQUEST" }
	end
	local ok, err = PetService.unequipPet(player.UserId, payload.slotIndex)
	return { success = ok, errorCode = err }
end

local function handleGetPetSlots(player, _)
	_initPetSlots(player.UserId)
	return {
		success = true,
		data = {
			slots = petSlots[player.UserId] or {},
			maxSlots = maxUnlockedSlots[player.UserId] or Balance.PET_DEFAULT_SLOTS,
			completed = PetService.getCompletedCreatures(player.UserId),
		}
	}
end

function PetService.GetHandlers()
	return {
		["Pet.Equip.Request"] = handleEquipPet,
		["Pet.Unequip.Request"] = handleUnequipPet,
		["Pet.Slots.Request"] = handleGetPetSlots,
	}
end

--========================================
-- Init
--========================================

function PetService.Init(netController, dataService, playerStatService, saveService, creatureService)
	if initialized then return end
	initialized = true

	NetController = netController
	DataService = dataService
	PlayerStatService = playerStatService
	SaveService = saveService
	CreatureService = creatureService

	indexPetModels()

	-- 플레이어 접속 시 펫 슬롯 로드 및 소환
	Players.PlayerAdded:Connect(function(player)
		_initPetSlots(player.UserId)
		player.CharacterAdded:Connect(function()
			task.wait(2) -- 캐릭터 완전 로드 대기
			local slots = petSlots[player.UserId]
			if slots then
				for slotIdx, creatureId in pairs(slots) do
					if creatureId then
						_spawnPet(player.UserId, slotIdx, creatureId)
					end
				end
			end
			_syncPetSlots(player.UserId)
		end)
	end)

	-- 플레이어 퇴장 시 정리
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if activePets[userId] then
			for slotIdx in pairs(activePets[userId]) do
				_despawnPet(userId, slotIdx)
			end
		end
		activePets[userId] = nil
		petSlots[userId] = nil
		maxUnlockedSlots[userId] = nil
	end)

	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		_initPetSlots(player.UserId)
	end

	-- AI 루프
	task.spawn(function()
		while true do
			_petAITick()
			task.wait(AI_TICK)
		end
	end)

	print("[PetService] Initialized")
end

return PetService
