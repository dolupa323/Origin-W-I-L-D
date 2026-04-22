-- PartyService.lua
-- Phase 5-4: 파티 & 소환 시스템 (Server-Authoritative)
-- 보관함의 팰을 파티에 편성하고 월드에 소환

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local PalTraitData = require(ReplicatedStorage.Data.PalTraitData)

local PartyService = {}

-- Dependencies
local NetController
local PalboxService
local CreatureService
local SaveService

-- [userId] = { slots = { [1..5] = palUID }, summonedSlot = nil, summonedModel = nil }
local playerParties = {}

-- AI Constants
local PAL_AI_UPDATE_INTERVAL = 0.5
local PAL_FOLLOW_DIST = Balance.PAL_FOLLOW_DIST or 8
local PAL_MIN_DIST = Balance.PAL_MIN_DIST or 5
local PAL_COMBAT_RANGE = Balance.PAL_COMBAT_RANGE or 15
local PAL_ATTACK_RANGE = 5
local PAL_ATTACK_COOLDOWN = 2
local SEA_LEVEL = Balance.SEA_LEVEL or 2
local MOUNT_INTERACT_DISTANCE = 12
local MOUNT_TURN_RATE = math.rad(140)
local MOUNT_TURN_LEAD_TIME = 0.22
local MOUNT_REVERSE_SPEED_MULTIPLIER = 0.55

-- 소환된 팰 목록 (모델 관리)
local activeSummons = {} -- [userId] = { model, humanoid, rootPart, palData, state, lastAttackTime }

-- ★ 주인의 전투 대상 (활 원거리 전투 시 팰에게 적 위치 공유)
local ownerCombatTargets = {} -- [userId] = instanceId (CreatureService의 크리처 ID)
local setPalState

--========================================
-- Internal Helpers
--========================================

local function getOrCreateParty(userId: number)
	if not playerParties[userId] then
		playerParties[userId] = {
			slots = {},
			summonedSlot = nil,
		}
	end
	return playerParties[userId]
end

local function getPartySize(party): number
	local count = 0
	for _ in pairs(party.slots) do count = count + 1 end
	return count
end

local function getCreatureData(creatureId: string)
	local CreatureDataModule = require(ReplicatedStorage.Data.CreatureData)
	for _, entry in ipairs(CreatureDataModule) do
		if entry.id == creatureId then
			return entry
		end
	end
	return nil
end

local function resolveMountSpeed(palData, creatureData, fallbackSpeed: number?): number
	-- 1. 베이스 속도 결정 (종족의 달리기 속도를 우선, 없을 시 걷기)
	-- 기존 팰들의 stale 데이터(16 고정) 방지를 위해 creatureData를 우선 참조하거나 보정
	local baseSpeed = tonumber(
		creatureData and creatureData.runSpeed
		or creatureData and creatureData.walkSpeed
		or palData and palData.stats and palData.stats.speed
		or (fallbackSpeed and fallbackSpeed > 0 and fallbackSpeed)
		or 16
	) or 16

	-- 2. 특성(Traits)에 의한 보정 (속도 증가/감소 특성 반영)
	local traitMultiplier = PalTraitData.GetStatMultiplier(palData and palData.traits, "speed")

	-- 3. 탑승 전용 배율 적용
	local mountMultiplier = tonumber(creatureData and creatureData.mountSpeedMultiplier) or 1
	
	return baseSpeed * traitMultiplier * mountMultiplier
end

local function resolveCurrentMountMoveSpeed(summon, throttle: number): number
	local baseSpeed = summon.mountBaseSpeed or resolveMountSpeed(summon.palData, summon.creatureData, summon.baseSpeed)
	local moveSpeed = baseSpeed
	if throttle < 0 then
		local reverseMultiplier = tonumber(summon.creatureData and summon.creatureData.mountReverseSpeedMultiplier)
			or MOUNT_REVERSE_SPEED_MULTIPLIER
		moveSpeed *= reverseMultiplier
	end
	return moveSpeed
end

local function isPositionInWater(position: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.FilterType = Enum.RaycastFilterType.Include

	local result = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), params)
	if result and result.Material == Enum.Material.Water then
		return true
	end

	return position.Y < SEA_LEVEL
end

--- 외부에서 파티 풀 여부 확인 (길들이기 차단용)
function PartyService.isPartyFull(userId: number): boolean
	local party = getOrCreateParty(userId)
	return getPartySize(party) >= Balance.MAX_PARTY
end

--- ★ 주인의 전투 대상 설정 (CombatService에서 호출)
function PartyService.setOwnerCombatTarget(userId: number, instanceId: string?)
	ownerCombatTargets[userId] = instanceId
end

local function createMountSeat(model: Model, rootPart: BasePart, creatureData)
	if not creatureData or not creatureData.mountable then
		return nil
	end

	local seat = Instance.new("Part")
	seat.Name = "MountSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false
	seat.Massless = true
	seat.CollisionGroup = "Creatures"
	seat.Parent = model

	local offset = creatureData.mountSeatOffset or Vector3.new(0, 2.5, 0)
	seat.CFrame = rootPart.CFrame * CFrame.new(offset)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = seat
	weld.Parent = seat

	return seat
end

local function endMountState(summon, notifyClient: boolean?)
	if not summon or not summon.isMounted then
		return
	end

	local riderUserId = summon.riderUserId
	summon.isMounted = false
	summon.riderUserId = nil
	summon.isDismounting = false
	summon.ignoreSeatExitUntil = 0
	summon.model:SetAttribute("MountedByUserId", nil)
	summon.model:SetAttribute("MountedTurnDirection", nil)
	summon.model:SetAttribute("MountedAnimState", nil)
	summon.humanoid.WalkSpeed = summon.baseSpeed
	summon.humanoid.JumpPower = summon.baseJumpPower or 5
	summon.humanoid.AutoRotate = true
	setPalState(summon, "IDLE")

	local riderPlayer = riderUserId and Players:GetPlayerByUserId(riderUserId)
	if riderPlayer then
		riderPlayer:SetAttribute("MountedPalUID", nil)
	end
	local riderCharacter = riderPlayer and riderPlayer.Character
	if summon.mountWeld then
		summon.mountWeld:Destroy()
		summon.mountWeld = nil
	end
	if summon.riderCollisionStates and riderCharacter then
		for part, canCollide in pairs(summon.riderCollisionStates) do
			if part and part.Parent then
				part.CanCollide = canCollide
			end
		end
	end
	summon.riderCollisionStates = nil
	local riderHumanoid = riderCharacter and riderCharacter:FindFirstChildOfClass("Humanoid")
	if riderHumanoid then
		riderHumanoid.AutoRotate = true
		if summon.riderState then
			riderHumanoid.WalkSpeed = summon.riderState.walkSpeed
			riderHumanoid.JumpPower = summon.riderState.jumpPower
			riderHumanoid.AutoJumpEnabled = summon.riderState.autoJumpEnabled
		end
		riderHumanoid.Sit = false
		riderHumanoid.Jump = false
		riderHumanoid:ChangeState(Enum.HumanoidStateType.Landed)
		riderHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	summon.riderState = nil
	if summon.rootPart and riderPlayer then
		pcall(function()
			summon.rootPart:SetNetworkOwner(riderPlayer)
		end)
	end

	if notifyClient and riderPlayer and NetController then
		NetController.FireClient(riderPlayer, "Party.Dismounted", {
			palUID = summon.palUID,
			palName = summon.palData and summon.palData.nickname,
		})
	end
end

local function beginMountState(summon, riderPlayer: Player)
	if not summon or not riderPlayer then
		return
	end

	summon.isMounted = true
	summon.riderUserId = riderPlayer.UserId
	summon.isDismounting = false
	summon.model:SetAttribute("MountedByUserId", riderPlayer.UserId)
	summon.model:SetAttribute("MountedAnimState", "IDLE")
	-- 속도 및 조작 설정 초기화
	summon.mountThrottle = 0
	summon.mountSteer = 0
	summon.mountBaseSpeed = resolveMountSpeed(summon.palData, summon.creatureData, summon.baseSpeed)
	-- [FIX] 초기 속도 동기화 강제: -1로 설정하여 첫 프레임 업데이트 시 서버가 WalkSpeed를 강제로 쓰게 함
	summon.mountSpeed = -1 
	summon.mountSyncCount = 10 -- [FIX] 소유권 이전 시점의 속도 패킷 유실 방지를 위해 10프레임 동안 강제 동기화
	summon.humanoid.WalkSpeed = summon.mountBaseSpeed
	summon.humanoid.JumpPower = (summon.creatureData and summon.creatureData.mountJumpPower) or 48
	summon.humanoid.AutoRotate = false
	setPalState(summon, "MOUNTED")
	riderPlayer:SetAttribute("MountedPalUID", summon.palUID)
	if summon.rootPart then
		pcall(function()
			summon.rootPart:SetNetworkOwner(riderPlayer)
		end)
	end

	local riderCharacter = riderPlayer.Character
	local riderHumanoid = riderCharacter and riderCharacter:FindFirstChildOfClass("Humanoid")
	local riderRoot = riderCharacter and riderCharacter:FindFirstChild("HumanoidRootPart")
	if riderHumanoid then
		summon.riderState = {
			walkSpeed = riderHumanoid.WalkSpeed,
			jumpPower = riderHumanoid.JumpPower,
			autoJumpEnabled = riderHumanoid.AutoJumpEnabled,
		}
		riderHumanoid.AutoRotate = false
		riderHumanoid.Jump = false
		riderHumanoid.Sit = true
		riderHumanoid.WalkSpeed = 0
		riderHumanoid.JumpPower = 0
		riderHumanoid.AutoJumpEnabled = false
		riderHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		riderHumanoid:ChangeState(Enum.HumanoidStateType.Seated)
	end
	if riderCharacter and riderRoot and summon.mountSeat then
		riderCharacter:PivotTo(summon.mountSeat.CFrame)
		summon.riderCollisionStates = {}
		for _, descendant in ipairs(riderCharacter:GetDescendants()) do
			if descendant:IsA("BasePart") then
				summon.riderCollisionStates[descendant] = descendant.CanCollide
				descendant.CanCollide = false
			end
		end
		local weld = Instance.new("WeldConstraint")
		weld.Name = "MountWeld"
		weld.Part0 = summon.mountSeat
		weld.Part1 = riderRoot
		weld.Parent = summon.mountSeat
		summon.mountWeld = weld
	end

	if NetController then
		NetController.FireClient(riderPlayer, "Party.Mounted", {
			palUID = summon.palUID,
			palName = summon.palData and summon.palData.nickname,
		})
	end
end

local function bindMountSeat(summon)
	return
end

local function updateMountedSummons(dt)
	local now = os.clock()
	for userId, summon in pairs(activeSummons) do
		if not summon.isMounted then
			continue
		end
		if not summon.model or not summon.model.Parent or not summon.mountSeat or not summon.mountWeld then
			endMountState(summon, true)
			continue
		end

		local riderPlayer = Players:GetPlayerByUserId(userId)
		local riderCharacter = riderPlayer and riderPlayer.Character
		local riderHumanoid = riderCharacter and riderCharacter:FindFirstChildOfClass("Humanoid")
		local riderRoot = riderCharacter and riderCharacter:FindFirstChild("HumanoidRootPart")
		if not riderHumanoid or not riderRoot or riderHumanoid.Health <= 0 then
			endMountState(summon, true)
			continue
		end
		if isPositionInWater(summon.rootPart.Position) or isPositionInWater(riderRoot.Position) then
			PartyService._recallPal(userId)
			continue
		end

		local throttle = summon.mountThrottle or 0
		local steer = summon.mountSteer or 0
		local camLook = summon.mountLookDir or Vector3.new(0, 0, -1)
		
		local hasThrottle = math.abs(throttle) > 0.01
		local hasSteer = math.abs(steer) > 0.01

		-- [UX 개선] 클라이언트가 네트워크 소유권을 가진 상태에서 서버가 직접 CFrame을 조작하면 화면 흔들림(抖動)이 발생함.
		-- 서버에서는 조작 상태(Attributes)만 갱신하고, 실제 물리 이동과 회전은 클라이언트(InteractController)에서 처리하도록 이관함.
		
		if hasThrottle or hasSteer then
			-- 애니메이션 상태 업데이트 (클라이언트 UI와 연동)
			summon.model:SetAttribute("MountedAnimState", "RUN")
		else
			summon.model:SetAttribute("MountedAnimState", "IDLE")
		end

		-- 서버 물리 엔진 영향 최소화 (클라이언트 조작 방해 금지)
		-- [FIX] 탑승 초기 또는 속도 변화 시 강제 동기화
		local newMountSpeed = resolveCurrentMountMoveSpeed(summon, throttle)
		local needsSync = math.abs((summon.mountSpeed or 0) - newMountSpeed) > 0.1
		if summon.mountSyncCount and summon.mountSyncCount > 0 then
			needsSync = true
			summon.mountSyncCount -= 1
		end

		if needsSync then
			-- [FIX] 로블록스 엔진은 값이 동일하면 패킷을 보내지 않으므로, 
			-- 초기 동기화 프레임(mountSyncCount > 0) 동안은 미세한 오차(0.01)를 주어 강제로 패킷 전송을 유도함.
			local flicker = 0
			if summon.mountSyncCount and summon.mountSyncCount > 0 then
				flicker = (summon.mountSyncCount % 2 == 0) and 0.01 or 0
			end
			
			summon.mountSpeed = newMountSpeed
			summon.humanoid.WalkSpeed = newMountSpeed + flicker
		end
	end
end

--========================================
-- Public API
--========================================

function PartyService.Init(_NetController, _PalboxService, _CreatureService, _SaveService)
	NetController = _NetController
	PalboxService = _PalboxService
	CreatureService = _CreatureService
	SaveService = _SaveService
	
	-- 플레이어 로그인 시 파티 로드
	Players.PlayerAdded:Connect(function(player)
		PartyService._loadPlayerParty(player)
	end)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function() PartyService._loadPlayerParty(player) end)
	end
	
	-- 팰 AI 루프 시작
	task.spawn(function()
		while true do
			task.wait(PAL_AI_UPDATE_INTERVAL)
			PartyService._updateSummonedPalAI()
		end
	end)
	RunService.Heartbeat:Connect(updateMountedSummons)
	
	print("[PartyService] Initialized")
end

--- 로그아웃 전 정리 (SaveService에서 순차적으로 호출)
function PartyService.prepareLogout(userId: number)
	PartyService._recallPal(userId) -- 소환 해제
	PartyService._savePlayerParty(userId) -- 파티 정보 저장
	playerParties[userId] = nil
	print(string.format("[PartyService] Prepared logout for player %d", userId))
end

function PartyService._loadPlayerParty(player: Player)
	local userId = player.UserId
	if not SaveService or not SaveService.getPlayerState then return end
	
	local state = SaveService.getPlayerState(userId)
	if state and state.party then
		-- 저장된 데이터가 있으면 캐시로 복사
		local party = getOrCreateParty(userId)
		-- ★ DataStore에서 로드 시 숫자 키가 문자열로 변환되므로 정규화
		local rawSlots = state.party.slots or {}
		local normalizedSlots = {}
		for k, v in pairs(rawSlots) do
			local numKey = tonumber(k)
			if numKey and v then
				normalizedSlots[numKey] = v
			end
		end
		party.slots = normalizedSlots
		party.summonedSlot = nil -- 접속 시엔 무조건 미소환 상태로 초기화
		
		print(string.format("[PartyService] Loaded party for player %d (%d pals in party)", userId, getPartySize(party)))
	end
end

function PartyService._savePlayerParty(userId: number)
	local party = playerParties[userId]
	if not party or not SaveService or not SaveService.updatePlayerState then return end
	
	SaveService.updatePlayerState(userId, function(state)
		state.party = {
			slots = party.slots,
			summonedSlot = party.summonedSlot
		}
		return state
	end)
end

--- 파티에 팰 편성
function PartyService.addToParty(userId: number, palUID: string): (boolean, string?)
	local party = getOrCreateParty(userId)
	
	-- 파티 용량 체크
	if getPartySize(party) >= Balance.MAX_PARTY then
		return false, Enums.ErrorCode.PARTY_FULL
	end
	
	-- 팰 존재 확인
	local pal = PalboxService.getPal(userId, palUID)
	if not pal then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 팰 상태 확인 (보관함에 있어야 편성 가능)
	if pal.state ~= Enums.PalState.STORED then
		return false, Enums.ErrorCode.PAL_ALREADY_ASSIGNED
	end
	
	-- 이미 파티에 있는지 확인
	for _, uid in pairs(party.slots) do
		if uid == palUID then
			return false, Enums.ErrorCode.PAL_IN_PARTY
		end
	end
	
	-- 빈 슬롯 찾기
	local emptySlot = nil
	for i = 1, Balance.MAX_PARTY do
		if not party.slots[i] then
			emptySlot = i
			break
		end
	end
	
	if not emptySlot then
		return false, Enums.ErrorCode.PARTY_FULL
	end
	
	-- 편성
	party.slots[emptySlot] = palUID
	PalboxService.updatePalState(userId, palUID, Enums.PalState.IN_PARTY)
	
	print(string.format("[PartyService] Player %d added pal %s to party slot %d", userId, palUID, emptySlot))
	
	-- 클라이언트 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Party.Updated", {
			action = "ADD",
			slot = emptySlot,
			palUID = palUID,
			palData = pal,
		})
	end
	
	return true
end

--- 파티에서 팰 해제
function PartyService.removeFromParty(userId: number, palUID: string): (boolean, string?)
	local party = getOrCreateParty(userId)
	
	-- 소환 중인 팰이면 먼저 회수
	if party.summonedSlot then
		local summonedUID = party.slots[party.summonedSlot]
		if summonedUID == palUID then
			PartyService._recallPal(userId)
		end
	end
	
	-- 파티에서 제거
	local found = false
	for slot, uid in pairs(party.slots) do
		if uid == palUID then
			party.slots[slot] = nil
			found = true
			break
		end
	end
	
	if not found then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 상태 원복
	PalboxService.updatePalState(userId, palUID, Enums.PalState.STORED)
	
	print(string.format("[PartyService] Player %d removed pal %s from party", userId, palUID))
	
	return true
end

--- 파티 목록 조회
function PartyService.getParty(userId: number): {[number]: string}
	local party = getOrCreateParty(userId)
	return party.slots
end

-- 소환 처리 중 락 (중복 스폰 방지)
local summoningLocks = {} -- [userId] = tick()

--- 팰 소환
function PartyService.summon(userId: number, partySlot: number): (boolean, string?)
	local party = getOrCreateParty(userId)
	
	-- 0. 소환 쿨다운 및 중복 요청 방지 (Debounce)
	local now = tick()
	if summoningLocks[userId] and (now - summoningLocks[userId]) < 2.0 then
		return false, Enums.ErrorCode.COOLDOWN
	end
	summoningLocks[userId] = now
	
	local player = Players:GetPlayerByUserId(userId)
	if not player or not player.Character then
		summoningLocks[userId] = nil
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then 
		summoningLocks[userId] = nil
		return false, Enums.ErrorCode.INTERNAL_ERROR 
	end
	
	-- 슬롯 검증
	local palUID = party.slots[partySlot]
	if not palUID then
		summoningLocks[userId] = nil
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 이미 소환 중이면 먼저 회수
	if party.summonedSlot or activeSummons[userId] then
		PartyService._recallPal(userId)
		-- 회수 후 즉시 소환 시 물리적 충돌 방지를 위해 미세 딜레이
		task.wait(0.1)
	end
	
	-- 팰 데이터
	local pal = PalboxService.getPal(userId, palUID)
	if not pal then 
		summoningLocks[userId] = nil
		return false, Enums.ErrorCode.NOT_FOUND 
	end

	local creatureData = getCreatureData(pal.creatureId)
	
	-- 시설 배치 중이면 소환 불가
	if pal.state == Enums.PalState.WORKING then
		summoningLocks[userId] = nil
		return false, Enums.ErrorCode.PAL_ALREADY_ASSIGNED
	end
	
	-- 기절 상태면 소환 불가
	if pal.state == Enums.PalState.FAINTED then
		summoningLocks[userId] = nil
		return false, "FAINTED"
	end
	
	-- 모델 생성 (플레이어 근처)
	local spawnPos = hrp.Position + hrp.CFrame.LookVector * PAL_FOLLOW_DIST
	local model, rootPart, humanoid = PartyService._createPalModel(pal, spawnPos, userId)
	
	if not model then
		summoningLocks[userId] = nil
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	-- 네트워크 소유권을 플레이어에게 설정 (클라이언트 보간으로 부드러운 이동)
	pcall(function()
		rootPart:SetNetworkOwner(player)
	end)

	-- 소환 정보 기록
	party.summonedSlot = partySlot
	
	-- 팰에 고유 InstanceId 부여 (공격 애니메이션 이벤트용)
	local HttpService = game:GetService("HttpService")
	local palInstanceId = "pal_" .. HttpService:GenerateGUID(false)
	model:SetAttribute("InstanceId", palInstanceId)
	
	-- 팰 HP: palData.stats.currentHp가 있으면 사용, 없으면 maxHP
	local maxHP = humanoid.MaxHealth
	local currentHP = (pal.stats and pal.stats.currentHp) or maxHP
	currentHP = math.clamp(currentHP, 1, maxHP)
	humanoid.Health = currentHP
	
	-- 클라이언트 HP바 표시용 Attribute
	model:SetAttribute("MaxHealth", maxHP)
	model:SetAttribute("CurrentHealth", currentHP)
	model:SetAttribute("IsPal", true)
	model:SetAttribute("OwnerUserId", userId)
	
	activeSummons[userId] = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		palData = pal,
		creatureData = creatureData,
		palUID = palUID,
		state = "IDLE",
		lastAttackTime = 0,
		ownerUserId = userId,
		lastMoveTarget = nil, -- MoveTo 중복 호출 방지
		maxHP = maxHP,
		currentHP = currentHP,
		baseSpeed = pal.stats and pal.stats.speed or (creatureData and creatureData.walkSpeed) or 16,
		baseJumpPower = humanoid.JumpPower,
		mountSpeed = resolveMountSpeed(pal, creatureData, humanoid.WalkSpeed),
		canMount = creatureData and creatureData.mountable == true or false,
		mountSeat = model:FindFirstChild("MountSeat"),
		isMounted = false,
		riderUserId = nil,
		isDismounting = false,
		mountWeld = nil,
		riderState = nil,
		riderCollisionStates = nil,
		mountThrottle = 0,
		mountSteer = 0,
		turnLeadUntil = 0,
		lastTurnDirection = nil,
		mountTurnRate = MOUNT_TURN_RATE,
		ignoreSeatExitUntil = 0,
	}

	bindMountSeat(activeSummons[userId])
	
	-- 상태 업데이트
	PalboxService.updatePalState(userId, palUID, Enums.PalState.SUMMONED)
	
	print(string.format("[PartyService] Player %d summoned pal %s (%s)", userId, palUID, pal.creatureId))
	
	-- 클라이언트 알림
	if NetController then
		NetController.FireClient(player, "Party.Summoned", {
			slot = partySlot,
			palUID = palUID,
			palName = pal.nickname,
		})
	end
	
	return true
end

--- 팰 회수
function PartyService._recallPal(userId: number)
	local party = playerParties[userId]
	local summon = activeSummons[userId]
	
	if not summon then return end

	endMountState(summon, true)
	if summon.mountSeatConn then
		summon.mountSeatConn:Disconnect()
		summon.mountSeatConn = nil
	end
	
	-- ★ 회수 시 현재 HP 저장
	if summon.palUID then
		local palData = PalboxService.getPal(userId, summon.palUID)
		if palData and palData.stats and summon.model then
			local humanoid = summon.model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				palData.stats.currentHp = math.floor(humanoid.Health)
			end
		end
	end

	-- 모델 제거
	if summon.model then
		summon.model:Destroy()
	end
	
	-- 상태 원복
	if summon.palUID then
		PalboxService.updatePalState(userId, summon.palUID, Enums.PalState.IN_PARTY)
	end
	
	-- 정리
	activeSummons[userId] = nil
	if party then
		party.summonedSlot = nil
	end
	
	print(string.format("[PartyService] Player %d recalled pal", userId))
	
	-- 클라이언트 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Party.Recalled", {})
	end
end

--- 팰 모델 생성 (CreatureData 기반 + 실제 모델 Clone)
function PartyService._createPalModel(palData, position: Vector3, ownerUserId: number)
	local creatureFolder = workspace:FindFirstChild("Creatures")
	if not creatureFolder then
		creatureFolder = Instance.new("Folder")
		creatureFolder.Name = "Creatures"
		creatureFolder.Parent = workspace
	end

	-- CreatureData에서 크리처 정의 조회
	local cData = getCreatureData(palData.creatureId)
	if not cData then
		warn("[PartyService] CreatureData not found:", palData.creatureId)
		return nil
	end

	-- 모델 템플릿 검색 (Assets 폴더에서)
	local modelName = cData.modelName or palData.creatureId
	local template = nil
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local searchFolders = {
			assets:FindFirstChild("CreatureModels"),
			assets:FindFirstChild("Creatures"),
			assets:FindFirstChild("Models"),
			assets,
		}
		for _, folder in ipairs(searchFolders) do
			if folder then
				local found = folder:FindFirstChild(modelName, true)
				if found and found:IsA("Model") then
					template = found
					break
				end
			end
		end
	end

	local model
	local rootPart
	local humanoid

	if template then
		model = template:Clone()
		model.Name = "Pal_" .. palData.creatureId

		-- 불필요한 스크립트/사운드/GUI 제거
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript")
				or child:IsA("Sound") or child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
				child:Destroy()
			end
		end

		-- HumanoidRootPart 확인/생성
		rootPart = model:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			local cf = model:GetBoundingBox()
			rootPart = Instance.new("Part")
			rootPart.Name = "HumanoidRootPart"
			rootPart.Size = Vector3.new(2, 2, 2)
			rootPart.Transparency = 1
			rootPart.CanCollide = false
			rootPart.Position = cf.Position
			rootPart.Parent = model

			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and part ~= rootPart then
					part.Anchored = false
					local hasConstraint = false
					for _, c in ipairs(part:GetChildren()) do
						if c:IsA("WeldConstraint") or c:IsA("Weld") or c:IsA("Motor6D") then
							hasConstraint = true
							break
						end
					end
					if not hasConstraint then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = rootPart
						weld.Part1 = part
						weld.Parent = rootPart
					end
				end
			end
		end

		-- 모든 파트 설정 (Anchored=true 먼저 → workspace 배치 후 지면 감지 → unanchor)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true -- workspace 배치 전 고정
				part.CollisionGroup = "Creatures"
				part.CanCollide = false
				if part ~= rootPart then
					part.Massless = true
				end
			end
		end

		model.PrimaryPart = rootPart
		-- 임시로 높은 곳에 배치 (이후 raycast로 정확한 지면에 내림)
		model:PivotTo(CFrame.new(position + Vector3.new(0, 10, 0)))

		-- Humanoid 설정
		humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			humanoid = Instance.new("Humanoid")
			humanoid.Parent = model
		end
		humanoid.WalkSpeed = palData.stats and palData.stats.speed or cData.walkSpeed or 16
		humanoid.MaxHealth = palData.stats and palData.stats.hp or cData.maxHealth or 100
		humanoid.Health = humanoid.MaxHealth
		humanoid.MaxSlopeAngle = 89
		humanoid.AutoJumpEnabled = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 5

		-- 물리 안정화: 탄성 0 + 높은 마찰 (튕김/날아감 방지)
		rootPart.CustomPhysicalProperties = PhysicalProperties.new(1.0, 2, 0, 1, 0)
		rootPart.RootPriority = 127

		-- HipHeight 계산 (모델 바닥 ~ HRP 바닥 거리)
		local lowestY = math.huge
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 0.9 then
				local bottomY = part.Position.Y - part.Size.Y / 2
				if bottomY < lowestY then lowestY = bottomY end
			end
		end
		if lowestY == math.huge then
			local modelCF, modelSize = model:GetBoundingBox()
			lowestY = modelCF.Position.Y - modelSize.Y / 2
		end
		local hrpBottom = rootPart.Position.Y - rootPart.Size.Y / 2
		humanoid.HipHeight = math.max(0, hrpBottom - lowestY)

		-- Humanoid가 CanCollide를 매 프레임 true로 강제하므로 감시하여 되돌림
		rootPart:GetPropertyChangedSignal("CanCollide"):Connect(function()
			if rootPart.CanCollide then
				rootPart.CanCollide = false
			end
		end)

		-- 런타임 중 추가되는 파트도 동일 설정 적용
		model.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				desc.CollisionGroup = "Creatures"
				desc.CanCollide = false
				if desc ~= rootPart then
					desc.Massless = true
				end
			end
		end)
	else
		-- 폴백: 모델 템플릿 없을 경우 임시 모델
		warn("[PartyService] Model template not found:", modelName, "- using fallback")
		model = Instance.new("Model")
		model.Name = "Pal_" .. palData.creatureId

		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 2)
		rootPart.Position = position + Vector3.new(0, 2, 0)
		rootPart.BrickColor = BrickColor.new("Bright green")
		rootPart.Transparency = 0.3
		rootPart.Anchored = false
		rootPart.CanCollide = false
		rootPart.Parent = model
		model.PrimaryPart = rootPart

		humanoid = Instance.new("Humanoid")
		humanoid.WalkSpeed = palData.stats and palData.stats.speed or 16
		humanoid.MaxHealth = palData.stats and palData.stats.hp or 100
		humanoid.Health = humanoid.MaxHealth
		humanoid.Parent = model
	end

	-- 팰 속성 설정
	rootPart:SetAttribute("IsPal", true)
	rootPart:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("CreatureId", string.upper(palData.creatureId))
	model:SetAttribute("PalUID", palData.uid)
	model:SetAttribute("State", "IDLE")
	model:SetAttribute("CanMount", cData.mountable == true)

	-- 이름표 (팰 닉네임 + HP바 표시)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 120, 0, 50)
	bg.StudsOffset = Vector3.new(0, 3, 0)
	bg.AlwaysOnTop = true
	bg.MaxDistance = 60
	bg.Parent = rootPart

	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 0.35, 0)
	mainFrame.Position = UDim2.new(0, 0, 0.15, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.95
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = bg

	local cornerMain = Instance.new("UICorner")
	cornerMain.CornerRadius = UDim.new(0, 4)
	cornerMain.Parent = mainFrame

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Text = string.format("🐾 %s (Lv.%d)", palData.nickname or palData.creatureId, palData.level or 1)
	txt.TextColor3 = Color3.fromRGB(150, 255, 150)
	txt.TextTransparency = 0.2
	txt.TextStrokeTransparency = 0.8
	txt.Font = Enum.Font.GothamMedium
	txt.TextSize = 10
	txt.Parent = mainFrame

	-- HP바 (이름 아래)
	local hpBarBg = Instance.new("Frame")
	hpBarBg.Name = "PalHPBarBg"
	hpBarBg.Size = UDim2.new(0.7, 0, 0.14, 0)
	hpBarBg.Position = UDim2.new(0.15, 0, 0.55, 0)
	hpBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBarBg.BackgroundTransparency = 0.3
	hpBarBg.BorderSizePixel = 0
	hpBarBg.Parent = bg

	local hpBarCorner = Instance.new("UICorner")
	hpBarCorner.CornerRadius = UDim.new(0, 3)
	hpBarCorner.Parent = hpBarBg

	local hpBarFill = Instance.new("Frame")
	hpBarFill.Name = "PalHPBarFill"
	hpBarFill.Size = UDim2.new(1, 0, 1, 0)
	hpBarFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
	hpBarFill.BackgroundTransparency = 0.1
	hpBarFill.BorderSizePixel = 0
	hpBarFill.Parent = hpBarBg

	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 3)
	hpFillCorner.Parent = hpBarFill

	local hpText = Instance.new("TextLabel")
	hpText.Name = "PalHPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text = string.format("%d / %d", humanoid.Health, humanoid.MaxHealth)
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.TextTransparency = 0.1
	hpText.TextStrokeTransparency = 0.5
	hpText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 8
	hpText.ZIndex = 2
	hpText.Parent = hpBarBg

	model.Parent = creatureFolder

	if cData.mountable then
		createMountSeat(model, rootPart, cData)
	end

	-- Raycast로 정확한 지면 높이를 찾아 배치한 뒤 Anchored 해제
	do
		local rayOrigin = rootPart.Position
		local rayDirection = Vector3.new(0, -100, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {model}
		local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)
		if rayResult then
			local groundY = rayResult.Position.Y
			local hipHeight = humanoid.HipHeight
			local hrpHalfHeight = rootPart.Size.Y / 2
			local targetY = groundY + hrpHalfHeight + hipHeight + 0.5
			model:PivotTo(CFrame.new(rootPart.Position.X, targetY, rootPart.Position.Z))
		else
			-- raycast 실패 시 원래 위치 유지
			model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
		end

		-- 모든 파트 Anchored 해제 (지면에 안전하게 배치된 후)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
	end

	return model, rootPart, humanoid
end

--========================================
-- Pal AI Loop
--========================================

-- MoveTo를 목표가 크게 변했을 때만 호출 (중복 호출로 인한 경로 끊김 방지)
local MOVE_RETHRESHOLD = 3 -- 이전 목표 대비 3스터드 이상 변해야 재호출

local function smartMoveTo(humanoid, targetPos, summon)
	if summon.lastMoveTarget then
		local delta = (targetPos - summon.lastMoveTarget).Magnitude
		if delta < MOVE_RETHRESHOLD then
			return -- 목표가 거의 같으면 재호출하지 않음
		end
	end
	summon.lastMoveTarget = targetPos
	humanoid:MoveTo(targetPos)
end

-- 팰 상태 변경 + 클라이언트 동기화 (애니메이션 트리거)
setPalState = function(summon, newState)
	if summon.state == newState then return end
	summon.state = newState
	if summon.model then
		summon.model:SetAttribute("State", newState)
	end
end

-- 팰 공격 애니메이션 이벤트 전송
local function firePalAttackAnim(summon)
	if not summon.model then return end
	-- model에 InstanceId가 없으므로 모든 클라이언트에게 모델 기반으로 전달
	-- CreatureAnimationController는 InstanceId로 모델을 찾으므로, 임시 InstanceId 설정
	local instanceId = summon.model:GetAttribute("InstanceId")
	if instanceId and NetController then
		NetController.FireAllClients("Creature.Attack.Play", {
			instanceId = instanceId, 
		})
	end
end

--========================================
-- Pal Damage & Faint System
--========================================

--- 소환된 팰에게 데미지 적용
--- @return killed: boolean
function PartyService.damagePal(userId: number, damage: number, sourcePos: Vector3?)
	local summon = activeSummons[userId]
	if not summon or not summon.model or not summon.humanoid then return false end
	if summon.currentHP <= 0 then return false end
	
	-- 데미지 적용
	local actualDamage = math.max(0, damage)
	summon.currentHP = math.max(0, summon.currentHP - actualDamage)
	summon.humanoid.Health = summon.currentHP
	
	-- Attribute 갱신 (클라이언트 HP바 반영)
	if summon.model then
		summon.model:SetAttribute("CurrentHealth", summon.currentHP)
		
		-- 머리 위 HP바 갱신
		if summon.rootPart then
			local bbGui = summon.rootPart:FindFirstChildOfClass("BillboardGui")
			if bbGui then
				local hpBarBg = bbGui:FindFirstChild("PalHPBarBg")
				if hpBarBg then
					local hpRatio = math.clamp(summon.currentHP / summon.maxHP, 0, 1)
					local fill = hpBarBg:FindFirstChild("PalHPBarFill")
					if fill then
						fill.Size = UDim2.new(hpRatio, 0, 1, 0)
						-- HP 비율에 따라 색상 변경
						if hpRatio > 0.5 then
							fill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
						elseif hpRatio > 0.25 then
							fill.BackgroundColor3 = Color3.fromRGB(240, 200, 50)
						else
							fill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
						end
					end
					local hpTxt = hpBarBg:FindFirstChild("PalHPText")
					if hpTxt then
						hpTxt.Text = string.format("%d / %d", math.ceil(summon.currentHP), summon.maxHP)
					end
				end
			end
		end
	end
	
	-- 클라이언트에게 팰 피격 알림 (데미지 텍스트 표시)
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Combat.Pal.Damaged", {
			damage = actualDamage,
			currentHP = summon.currentHP,
			maxHP = summon.maxHP,
			palUID = summon.palUID,
		})
	end
	
	-- HP 0 → 기절 처리
	if summon.currentHP <= 0 then
		PartyService._faintPal(userId)
		return true
	end
	
	return false
end

--- 팰 기절 처리 (HP 0 → FAINTED 상태 → 자동 소환 해제)
function PartyService._faintPal(userId: number)
	local summon = activeSummons[userId]
	if not summon then return end

	endMountState(summon, true)
	if summon.mountSeatConn then
		summon.mountSeatConn:Disconnect()
		summon.mountSeatConn = nil
	end
	
	local palUID = summon.palUID
	local palData = summon.palData
	
	-- palData에 currentHp = 0 저장
	if palData and palData.stats then
		palData.stats.currentHp = 0
	end
	
	-- 상태를 FAINTED로 설정
	if palUID then
		PalboxService.updatePalState(userId, palUID, Enums.PalState.FAINTED)
	end
	
	-- 클라이언트에 기절 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Party.Pal.Fainted", {
			palUID = palUID,
			palName = palData and (palData.nickname or palData.creatureId) or "?",
		})
	end
	
	-- 모델 제거 (1초 딜레이로 사망 연출)
	local model = summon.model
	if model then
		-- 즉시 AI 중지 (humanoid 멈춤)
		if summon.humanoid then
			summon.humanoid.WalkSpeed = 0
			summon.humanoid:MoveTo(summon.rootPart.Position)
		end
		task.delay(1.5, function()
			if model and model.Parent then
				model:Destroy()
			end
		end)
	end
	
	-- 소환 정보 정리
	activeSummons[userId] = nil
	local party = playerParties[userId]
	if party then
		party.summonedSlot = nil
	end
	
	print(string.format("[PartyService] Pal %s fainted for player %d", palUID or "?", userId))
end

--- 소환된 팰 조회 (CreatureService에서 사용)
function PartyService.getActiveSummons()
	return activeSummons
end

--- 특정 유저의 소환 팰 조회
function PartyService.getSummon(userId: number)
	return activeSummons[userId]
end

function PartyService.mount(player: Player): (boolean, string?)
	local summon = activeSummons[player.UserId]
	if not summon or not summon.model or not summon.model.Parent then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	if not summon.canMount or not summon.mountSeat then
		return false, Enums.ErrorCode.NOT_SUPPORTED
	end
	if summon.riderUserId and summon.riderUserId ~= player.UserId then
		return false, Enums.ErrorCode.INVALID_STATE
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return false, Enums.ErrorCode.INVALID_STATE
	end
	if humanoid.Health <= 0 then
		return false, Enums.ErrorCode.INVALID_STATE
	end
	if (hrp.Position - summon.rootPart.Position).Magnitude > MOUNT_INTERACT_DISTANCE then
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end

	beginMountState(summon, player)
	return true, nil
end

function PartyService.dismount(userId: number, shouldReposition: boolean?): (boolean, string?)
	local summon = activeSummons[userId]
	if not summon or not summon.isMounted then
		return false, Enums.ErrorCode.INVALID_STATE
	end

	local riderPlayer = Players:GetPlayerByUserId(userId)
	local character = riderPlayer and riderPlayer.Character
	summon.isDismounting = true
	summon.ignoreSeatExitUntil = 0

	if shouldReposition ~= false and character and summon.rootPart then
		local dismountPos = summon.rootPart.Position + summon.rootPart.CFrame.RightVector * 4 + Vector3.new(0, 2, 0)
		character:PivotTo(CFrame.new(dismountPos, dismountPos + summon.rootPart.CFrame.LookVector))
	end

	endMountState(summon, true)
	return true, nil
end

function PartyService._updateSummonedPalAI()
	local now = os.clock()
	
	for userId, summon in pairs(activeSummons) do
		if not summon.model or not summon.model.Parent then
			-- 모델 사라짐 → 정리
			if summon.mountSeatConn then
				summon.mountSeatConn:Disconnect()
				summon.mountSeatConn = nil
			end
			local palUID = summon.palUID
			if palUID then
				PalboxService.updatePalState(userId, palUID, Enums.PalState.IN_PARTY)
			end
			activeSummons[userId] = nil
			local party = playerParties[userId]
			if party then party.summonedSlot = nil end
			continue
		end
		
		-- HP 0 → 기절 처리 (_faintPal이 정리를 담당)
		if summon.currentHP <= 0 or (summon.humanoid and summon.humanoid.Health <= 0) then
			PartyService._faintPal(userId)
			continue
		end
		
		-- 팰의 HRP
		local palHrp = summon.rootPart
		if not palHrp then continue end
		local humanoid = summon.humanoid

		if summon.isMounted then
			continue
		end
		
		-- 주인 상태 체크
		local player = Players:GetPlayerByUserId(userId)
		local char = player and player.Character
		local ownerHrp = char and char:FindFirstChild("HumanoidRootPart")
		local ownerHum = char and char:FindFirstChild("Humanoid")
		local ownerIsAlive = ownerHum and ownerHum.Health > 0
		
		-- 1. 적 탐색 (근처의 적대 크리처)
		local closestEnemy, enemyDist = nil, 9999
		local creaturesFolder = workspace:FindFirstChild("Creatures")
		if creaturesFolder then
			-- [OPTIMIZATION] 모든 크리처 순회(O(N)) 대신 공간 쿼리(GetPartBoundsInRadius) 사용
			local spatialParams = OverlapParams.new()
			spatialParams.FilterDescendantsInstances = { creaturesFolder }
			spatialParams.FilterType = Enum.RaycastFilterType.Include
			
			local nearbyParts = workspace:GetPartBoundsInRadius(palHrp.Position, PAL_COMBAT_RANGE, spatialParams)
			local processedModels = {}
			
			for _, part in ipairs(nearbyParts) do
				local model = part:FindFirstAncestorOfClass("Model")
				if model and not processedModels[model] and not model.Name:match("^Pal_") then
					processedModels[model] = true
					-- 사망 또는 쓰러진(Collapsed) 크리처는 전투 대상에서 제외
					-- 쓰러진 이후는 플레이어가 직접 처리하는 영역 (포획/사냥)
					if model:GetAttribute("IsDead") or model:GetAttribute("HasCollapsed") then
						continue
					end
					local childRoot = model:FindFirstChild("HumanoidRootPart")
					local childHum = model:FindFirstChild("Humanoid")
					if childRoot and childHum and childHum.Health > 0 then
						-- 수평 거리(XZ)로 계산: 쓰러진 크리처의 Y 좌표 차이 무시
						local delta = palHrp.Position - childRoot.Position
						local d = Vector3.new(delta.X, 0, delta.Z).Magnitude
						if d < enemyDist then
							enemyDist = d
							closestEnemy = childRoot
						end
					end
				end
			end
		end

		-- ★ 주인의 전투 대상이 있으면 팰 근처 적보다 우선 타겟팅 (활 원거리 전투 지원)
		local ownerTargetId = ownerCombatTargets[userId]
		if ownerTargetId and CreatureService and CreatureService.getCreatureRuntime then
			local targetCreature = CreatureService.getCreatureRuntime(ownerTargetId)
			if targetCreature and targetCreature.rootPart and targetCreature.rootPart.Parent then
				local isDead = targetCreature.model and (targetCreature.model:GetAttribute("IsDead") or targetCreature.model:GetAttribute("HasCollapsed"))
				if not isDead and targetCreature.currentHealth and targetCreature.currentHealth > 0 then
					closestEnemy = targetCreature.rootPart
					local delta = palHrp.Position - targetCreature.rootPart.Position
					enemyDist = Vector3.new(delta.X, 0, delta.Z).Magnitude
				end
			end
		end
		
		-- 2. 주인 부재/사망 시 대응
		if not ownerHrp or not ownerIsAlive then
			if closestEnemy and enemyDist <= PAL_COMBAT_RANGE then
				-- 주인은 없지만 근처에 적이 있으면 자기방어 수행
				setPalState(summon, "COMBAT")
				humanoid:MoveTo(closestEnemy.Position)
				humanoid.WalkSpeed = (summon.palData.stats.speed or 16) * 1.2
				
				-- 공격 범위 내면 공격
				if enemyDist <= PAL_ATTACK_RANGE then
					if not summon.lastAttackTime or (now - summon.lastAttackTime >= PAL_ATTACK_COOLDOWN) then
						summon.lastAttackTime = now
						firePalAttackAnim(summon)
						local targetModel = closestEnemy.Parent
						if targetModel and targetModel:GetAttribute("InstanceId") and CreatureService.processAttack then
							local damage = summon.palData.stats.attack or 10
							local targetId = targetModel:GetAttribute("InstanceId")
							local killed = CreatureService.processAttack(targetId, damage, 0, player)
							-- 팰 데미지 플로팅 텍스트 이벤트 (주인에게 전송)
							if player and NetController then
								local creatureRT = CreatureService.getCreatureRuntime(targetId)
								NetController.FireClient(player, "Combat.Pal.Hit.Result", {
									damage = damage,
									targetId = targetId,
									killed = killed or false,
									currentHP = creatureRT and creatureRT.currentHealth or 0,
									maxHP = creatureRT and (creatureRT.maxHealth or (creatureRT.data and creatureRT.data.maxHealth)) or 100,
								})
							end
						end
					end
				end
			else
				-- 주인도 없고 적도 없으면 안전하게 회수 (공중에 떠있거나 무방비 방치 방지)
				print(string.format("[PartyService] Owner missing or dead, recalling pal %s", summon.palData.nickname))
				PartyService._recallPal(userId)
				continue
			end
			continue
		end
		
		-- 3. 정상 상태 (주인이 살아있을 때)
		local distToOwner = (palHrp.Position - ownerHrp.Position).Magnitude
		local baseSpeed = summon.palData.stats.speed or 16
		
		-- 주인 이동 중인지 감지
		local ownerVelocity = ownerHrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		local ownerMoving = ownerVelocity.Magnitude > 2
		
		-- 히스테리시스 거리 (상태에 따라 다른 임계값으로 진동 방지)
		local followStartDist = PAL_FOLLOW_DIST + 4  -- 8스터드: 따라가기 시작
		local followStopDist = PAL_FOLLOW_DIST + 1   -- 5스터드: 따라가기 중지
		
		-- ★ 주인의 전투 대상이면 원거리까지 추적 (최대 텔레포트 거리 직전)
		local isOwnerTarget = ownerTargetId and closestEnemy and closestEnemy.Parent and closestEnemy.Parent:GetAttribute("InstanceId") == ownerTargetId
		local effectiveCombatRange = isOwnerTarget and 45 or PAL_COMBAT_RANGE

		-- 주인이 너무 멀리 가면 텔레포트 (부드러운 재배치)
		-- ★ 전투 중이면 텔레포트 거리를 넓게 (주인 전투 대상 추적 중 텔레포트 진동 방지)
		local teleportDist = (isOwnerTarget and summon.state == "COMBAT") and 80 or 50
		if distToOwner > teleportDist then
			local teleportTarget = ownerHrp.Position - ownerHrp.CFrame.LookVector * PAL_FOLLOW_DIST
			palHrp.CFrame = CFrame.new(teleportTarget + Vector3.new(0, 2, 0))
			setPalState(summon, "FOLLOW")
			summon.lastMoveTarget = nil
		-- 적이 전투 범위 내에 있으면 전투
		elseif closestEnemy and enemyDist <= effectiveCombatRange then
			setPalState(summon, "COMBAT")
			humanoid.WalkSpeed = baseSpeed * 1.2
			smartMoveTo(humanoid, closestEnemy.Position, summon)
			
			-- 공격 범위 내면 공격
			if enemyDist <= PAL_ATTACK_RANGE then
				if not summon.lastAttackTime or (now - summon.lastAttackTime >= PAL_ATTACK_COOLDOWN) then
					summon.lastAttackTime = now
					firePalAttackAnim(summon)
					
					local targetModel = closestEnemy.Parent
					if targetModel then
						local targetId = targetModel:GetAttribute("InstanceId")
						if targetId and CreatureService.processAttack then
							local damage = summon.palData.stats.attack or 10
							local killed = CreatureService.processAttack(targetId, damage, 0, player)
							-- 팰 데미지 플로팅 텍스트 이벤트 (주인에게 전송)
							if player and NetController then
								local creatureRT = CreatureService.getCreatureRuntime(targetId)
								NetController.FireClient(player, "Combat.Pal.Hit.Result", {
									damage = damage,
									targetId = targetId,
									killed = killed or false,
									currentHP = creatureRT and creatureRT.currentHealth or 0,
									maxHP = creatureRT and (creatureRT.maxHealth or (creatureRT.data and creatureRT.data.maxHealth)) or 100,
								})
							end
						end
					end
				end
			end
		-- 주인 따라가기 (히스테리시스 적용)
		elseif distToOwner > followStartDist or (summon.state == "FOLLOW" and distToOwner > followStopDist) then
			setPalState(summon, "FOLLOW")
			-- 주인 뒤쪽 + 이동 방향 예측
			local followTarget
			if ownerMoving then
				followTarget = ownerHrp.Position - ownerHrp.CFrame.LookVector * PAL_FOLLOW_DIST
			else
				followTarget = ownerHrp.Position - ownerHrp.CFrame.LookVector * PAL_FOLLOW_DIST
			end
			-- 주인과의 거리에 비례한 속도 (멀수록 빠르게)
			local speedMult = math.clamp(distToOwner / followStartDist, 1, 1.8)
			humanoid.WalkSpeed = baseSpeed * speedMult
			smartMoveTo(humanoid, followTarget, summon)
		-- 주인에게 너무 가까우면 뒤로 밀어냄
		elseif distToOwner < PAL_MIN_DIST then
			setPalState(summon, "BACK_OFF")
			local awayDir = (palHrp.Position - ownerHrp.Position)
			awayDir = (awayDir * Vector3.new(1, 0, 1))
			if awayDir.Magnitude < 0.1 then
				awayDir = -ownerHrp.CFrame.LookVector
			end
			awayDir = awayDir.Unit
			local retreatTarget = ownerHrp.Position + awayDir * PAL_FOLLOW_DIST
			humanoid.WalkSpeed = baseSpeed * 1.3
			smartMoveTo(humanoid, retreatTarget, summon)
		else
			-- 주인 근처 → IDLE (한 번만 정지 명령)
			if summon.state ~= "IDLE" then
				setPalState(summon, "IDLE")
				humanoid.WalkSpeed = baseSpeed
				summon.lastMoveTarget = nil
			end
			-- IDLE 상태에서는 MoveTo를 호출하지 않음 (자연스러운 정지)
		end
	end
end

--========================================
-- Network Handlers
--========================================

local function handlePartyListRequest(player, _payload)
	local party = getOrCreateParty(player.UserId)
	local partySlots = {}
	
	for slot, palUID in pairs(party.slots) do
		local pal = PalboxService.getPal(player.UserId, palUID)
		partySlots[slot] = {
			palUID = palUID,
			palData = pal,
		}
	end
	
	return {
		success = true,
		data = {
			slots = partySlots,
			maxSlots = Balance.MAX_PARTY,
			summonedSlot = party.summonedSlot,
		}
	}
end

local function handleAddToPartyRequest(player, payload)
	local palUID = payload.palUID
	if not palUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local ok, err = PartyService.addToParty(player.UserId, palUID)
	if not ok then
		return { success = false, errorCode = err }
	end
	return { success = true }
end

local function handleRemoveFromPartyRequest(player, payload)
	local palUID = payload.palUID
	if not palUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local ok, err = PartyService.removeFromParty(player.UserId, palUID)
	if not ok then
		return { success = false, errorCode = err }
	end
	return { success = true }
end

local function handleSummonRequest(player, payload)
	local partySlot = payload.slot
	if not partySlot then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local ok, err = PartyService.summon(player.UserId, partySlot)
	if not ok then
		return { success = false, errorCode = err }
	end
	return { success = true }
end

local function handleRecallRequest(player, _payload)
	PartyService._recallPal(player.UserId)
	return { success = true }
end

local function handleMountRequest(player, _payload)
	local ok, err = PartyService.mount(player)
	if not ok then
		return { success = false, errorCode = err }
	end
	return { success = true }
end

local function handleDismountRequest(player, _payload)
	local ok, err = PartyService.dismount(player.UserId)
	if not ok then
		return { success = false, errorCode = err }
	end
	return { success = true }
end

local function handleMountJumpRequest(player, _payload)
	local summon = activeSummons[player.UserId]
	if not summon or not summon.isMounted or not summon.humanoid then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end
	return { success = false, errorCode = Enums.ErrorCode.NOT_SUPPORTED }
end

local function handleMountControlRequest(player, payload)
	local summon = activeSummons[player.UserId]
	if not summon or not summon.isMounted then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	summon.mountThrottle = math.clamp(tonumber(payload and payload.throttle) or 0, -1, 1)
	summon.mountSteer = math.clamp(tonumber(payload and payload.steer) or 0, -1, 1)
	summon.mountLookDir = payload and payload.lookDir or Vector3.new(0, 0, -1)
	return { success = true }
end

function PartyService.GetHandlers()
	return {
		["Party.List.Request"] = handlePartyListRequest,
		["Party.Add.Request"] = handleAddToPartyRequest,
		["Party.Remove.Request"] = handleRemoveFromPartyRequest,
		["Party.Summon.Request"] = handleSummonRequest,
		["Party.Recall.Request"] = handleRecallRequest,
		["Party.Mount.Request"] = handleMountRequest,
		["Party.Dismount.Request"] = handleDismountRequest,
		["Party.Mount.Jump.Request"] = handleMountJumpRequest,
		["Party.Mount.Control.Request"] = handleMountControlRequest,
	}
end

return PartyService
