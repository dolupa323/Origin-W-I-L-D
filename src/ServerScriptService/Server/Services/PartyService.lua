-- PartyService.lua
-- Phase 5-4: 파티 & 소환 시스템 (Server-Authoritative)
-- 보관함의 팰을 파티에 편성하고 월드에 소환

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

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
local PAL_FOLLOW_DIST = Balance.PAL_FOLLOW_DIST or 4
local PAL_COMBAT_RANGE = Balance.PAL_COMBAT_RANGE or 15
local PAL_ATTACK_RANGE = 5
local PAL_ATTACK_COOLDOWN = 2

-- 소환된 팰 목록 (모델 관리)
local activeSummons = {} -- [userId] = { model, humanoid, rootPart, palData, state, lastAttackTime }

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
		-- 저장된 데이터가 있으면 캐시로 복사 (slots가 array/map 섞일 수 있으므로 주의)
		local party = getOrCreateParty(userId)
		party.slots = state.party.slots or {}
		party.summonedSlot = nil -- 접속 시엔 무조건 미소환 상태로 초기화
		
		print(string.format("[PartyService] Loaded party for player %d", userId))
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

--- 팰 소환
function PartyService.summon(userId: number, partySlot: number): (boolean, string?)
	local party = getOrCreateParty(userId)
	
	local player = Players:GetPlayerByUserId(userId)
	if not player or not player.Character then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	-- 슬롯 검증
	local palUID = party.slots[partySlot]
	if not palUID then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 이미 소환 중이면 먼저 회수
	if party.summonedSlot then
		PartyService._recallPal(userId)
	end
	
	-- 팰 데이터
	local pal = PalboxService.getPal(userId, palUID)
	if not pal then return false, Enums.ErrorCode.NOT_FOUND end
	
	-- 시설 배치 중이면 소환 불가
	if pal.state == Enums.PalState.WORKING then
		return false, Enums.ErrorCode.PAL_ALREADY_ASSIGNED
	end
	
	-- 모델 생성 (플레이어 근처)
	local spawnPos = hrp.Position + hrp.CFrame.LookVector * PAL_FOLLOW_DIST
	local model, rootPart, humanoid = PartyService._createPalModel(pal, spawnPos, userId)
	
	if not model then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	-- 소환 정보 기록
	party.summonedSlot = partySlot
	activeSummons[userId] = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		palData = pal,
		palUID = palUID,
		state = "FOLLOW", -- FOLLOW, COMBAT, IDLE
		lastAttackTime = 0,
		ownerUserId = userId,
	}
	
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

--- 팰 모델 생성
function PartyService._createPalModel(palData, position: Vector3, ownerUserId: number)
	local creatureFolder = workspace:FindFirstChild("Creatures") or Instance.new("Folder", workspace)
	creatureFolder.Name = "Creatures"
	
	local PalDataModule = require(ReplicatedStorage.Data.PalData)
	local palDef = PalDataModule[palData.creatureId]
	if not palDef then return nil end
	
	local model = Instance.new("Model")
	model.Name = "Pal_" .. palData.creatureId
	
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 2)
	rootPart.Position = position + Vector3.new(0, 2, 0)
	rootPart.BrickColor = BrickColor.new("Bright green") -- 소환된 팰은 초록
	rootPart.Transparency = 0.3
	rootPart.Anchored = false
	rootPart.Parent = model
	model.PrimaryPart = rootPart
	
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = palData.stats.speed or 16
	humanoid.MaxHealth = palData.stats.hp
	humanoid.Health = palData.stats.hp
	humanoid.Parent = model
	
	-- 이름표 (팰 닉네임 표시)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 120, 0, 40)
	bg.StudsOffset = Vector3.new(0, 3, 0)
	bg.AlwaysOnTop = true -- 파트 몸체에 안 묻히게 수정
	bg.MaxDistance = 60
	bg.Parent = rootPart
	
	-- 배경 (이름표 전체 테마 레이아웃)
	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 0.4, 0)
	mainFrame.Position = UDim2.new(0, 0, 0.3, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.95 -- 유리 수준으로 매우 투명하게 변경
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = bg
	
	local cornerMain = Instance.new("UICorner")
	cornerMain.CornerRadius = UDim.new(0, 4)
	cornerMain.Parent = mainFrame
	
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Text = string.format("🐾 %s (Lv.%d)", palData.nickname, palData.level)
	txt.TextColor3 = Color3.fromRGB(150, 255, 150) -- 부드러운 파스텔 연두색 유지
	txt.TextTransparency = 0.2
	txt.TextStrokeTransparency = 0.8
	txt.Font = Enum.Font.GothamMedium
	txt.TextSize = 10
	txt.Parent = mainFrame
	
	-- 팰임을 표시하는 속성
	rootPart:SetAttribute("IsPal", true)
	rootPart:SetAttribute("OwnerUserId", ownerUserId)
	
	model.Parent = creatureFolder
	
	return model, rootPart, humanoid
end

--========================================
-- Pal AI Loop
--========================================

function PartyService._updateSummonedPalAI()
	local now = os.time()
	
	for userId, summon in pairs(activeSummons) do
		if not summon.model or not summon.model.Parent or (summon.humanoid and summon.humanoid.Health <= 0) then
			-- 모델 사라짐 또는 사망 → 정리
			local palUID = summon.palUID
			if palUID then
				PalboxService.updatePalState(userId, palUID, Enums.PalState.IN_PARTY)
			end
			
			if summon.model and summon.humanoid and summon.humanoid.Health <= 0 then
				task.delay(1, function() if summon.model then summon.model:Destroy() end end)
			end
			
			activeSummons[userId] = nil
			local party = playerParties[userId]
			if party then party.summonedSlot = nil end
			continue
		end
		
		-- 팰의 HRP
		local palHrp = summon.rootPart
		if not palHrp then continue end
		local humanoid = summon.humanoid
		
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
					local childRoot = model:FindFirstChild("HumanoidRootPart")
					local childHum = model:FindFirstChild("Humanoid")
					if childRoot and childHum and childHum.Health > 0 then
						local d = (palHrp.Position - childRoot.Position).Magnitude
						if d < enemyDist then
							enemyDist = d
							closestEnemy = childRoot
						end
					end
				end
			end
		end
		
		-- 2. 주인 부재/사망 시 대응
		if not ownerHrp or not ownerIsAlive then
			if closestEnemy and enemyDist <= PAL_COMBAT_RANGE then
				-- 주인은 없지만 근처에 적이 있으면 자기방어 수행
				summon.state = "COMBAT"
				humanoid:MoveTo(closestEnemy.Position)
				humanoid.WalkSpeed = (summon.palData.stats.speed or 16) * 1.2
				
				-- 공격 범위 내면 공격
				if enemyDist <= PAL_ATTACK_RANGE then
					if not summon.lastAttackTime or (now - summon.lastAttackTime >= PAL_ATTACK_COOLDOWN) then
						summon.lastAttackTime = now
						local targetModel = closestEnemy.Parent
						if targetModel and targetModel:GetAttribute("InstanceId") and CreatureService.applyDamage then
							local damage = summon.palData.stats.attack or 10
							CreatureService.applyDamage(targetModel:GetAttribute("InstanceId"), damage, player)
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
		
		-- 주인이 너무 멀리 가면 텔레포트
		if distToOwner > 60 then
			palHrp.CFrame = CFrame.new(ownerHrp.Position + ownerHrp.CFrame.LookVector * -PAL_FOLLOW_DIST)
			summon.state = "FOLLOW"
		-- 적이 전투 범위 내에 있으면 전투
		elseif closestEnemy and enemyDist <= PAL_COMBAT_RANGE then
			summon.state = "COMBAT"
			humanoid:MoveTo(closestEnemy.Position)
			humanoid.WalkSpeed = (summon.palData.stats.speed or 16) * 1.2
			
			-- 공격 범위 내면 공격
			if enemyDist <= PAL_ATTACK_RANGE then
				if not summon.lastAttackTime or (now - summon.lastAttackTime >= PAL_ATTACK_COOLDOWN) then
					summon.lastAttackTime = now
					
					local targetModel = closestEnemy.Parent
					if targetModel then
						local targetId = targetModel:GetAttribute("InstanceId")
						if targetId and CreatureService.applyDamage then
							local damage = summon.palData.stats.attack or 10
							local killed = CreatureService.applyDamage(targetId, damage, player)
							
							print(string.format("[PartyService] Pal %s attacked %s for %d dmg (Killed: %s)", 
								summon.palData.nickname, targetModel.Name, damage, tostring(killed)))
						end
					end
				end
			end
		-- 주인 따라가기
		elseif distToOwner > PAL_FOLLOW_DIST + 2 then
			summon.state = "FOLLOW"
			local behindOwner = ownerHrp.Position - ownerHrp.CFrame.LookVector * PAL_FOLLOW_DIST
			humanoid:MoveTo(behindOwner)
			humanoid.WalkSpeed = summon.palData.stats.speed or 16
		else
			-- 주인 근처 → IDLE
			summon.state = "IDLE"
			humanoid:MoveTo(palHrp.Position)
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

function PartyService.GetHandlers()
	return {
		["Party.List.Request"] = handlePartyListRequest,
		["Party.Add.Request"] = handleAddToPartyRequest,
		["Party.Remove.Request"] = handleRemoveFromPartyRequest,
		["Party.Summon.Request"] = handleSummonRequest,
		["Party.Recall.Request"] = handleRecallRequest,
	}
end

return PartyService
