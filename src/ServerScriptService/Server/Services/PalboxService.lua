-- PalboxService.lua
-- Phase 5-3: 팰 보관함 시스템 (Server-Authoritative)
-- 포획한 팰을 저장/관리하는 서비스

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local PalboxService = {}

-- Dependencies
local NetController
local DataService
local SaveService

-- [userId] = { [palUID] = palData, ... }
local playerPalboxes = {}

--========================================
-- Internal Helpers
--========================================

local function getOrCreatePalbox(userId: number)
	if not playerPalboxes[userId] then
		playerPalboxes[userId] = {}
	end
	return playerPalboxes[userId]
end

--========================================
-- Public API
--========================================

function PalboxService.Init(_NetController, _DataService, _SaveService)
	NetController = _NetController
	DataService = _DataService
	SaveService = _SaveService
	
	-- 플레이어 로그인 시 팰 데이터 로드 (SaveService 로드 완료 대기)
	Players.PlayerAdded:Connect(function(player)
		-- SaveService가 DataStore에서 데이터를 로드할 때까지 대기
		if not player:GetAttribute("DataLoaded") then
			player:GetAttributeChangedSignal("DataLoaded"):Wait()
		end
		PalboxService._loadPlayerPals(player)
	end)

	-- 이미 접속해 있는 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			if not player:GetAttribute("DataLoaded") then
				player:GetAttributeChangedSignal("DataLoaded"):Wait()
			end
			if not playerPalboxes[player.UserId] then
				PalboxService._loadPlayerPals(player)
			end
		end)
	end
	
	print("[PalboxService] Initialized")
end

--- 로그아웃 전 정리 (SaveService에서 순차적으로 호출)
function PalboxService.prepareLogout(player: Player)
	PalboxService._savePlayerPals(player)
	playerPalboxes[player.UserId] = nil
	print(string.format("[PalboxService] Prepared logout for player %d", player.UserId))
end

--- 팰 추가 (포획 성공 시 CaptureService에서 호출)
function PalboxService.addPal(userId: number, palData: any): boolean
	local palbox = getOrCreatePalbox(userId)
	
	-- 용량 체크
	local count = 0
	for _ in pairs(palbox) do count = count + 1 end
	if count >= Balance.MAX_PALBOX then
		warn(string.format("[PalboxService] Palbox full for player %d (%d/%d)", userId, count, Balance.MAX_PALBOX))
		return false
	end
	
	-- 등록
	palbox[palData.uid] = palData
	
	-- 즉시 SaveService에 동기화
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.palbox = palbox
			return state
		end)
	end
	
	print(string.format("[PalboxService] Added pal %s (%s) for player %d", palData.uid, palData.creatureId, userId))
	
	-- 클라이언트 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Palbox.Updated", {
			action = "ADD",
			palUID = palData.uid,
			palData = palData,
		})
	end
	
	return true
end

--- 팰 제거 (해방 등)
function PalboxService.removePal(userId: number, palUID: string): boolean
	local palbox = getOrCreatePalbox(userId)
	
	local pal = palbox[palUID]
	if not pal then
		return false
	end
	
	-- 파티 편성 중이거나 작업 중이면 해제 불가
	if pal.state == Enums.PalState.SUMMONED or pal.state == Enums.PalState.WORKING then
		warn("[PalboxService] Cannot remove pal in active state:", pal.state)
		return false
	end
	
	palbox[palUID] = nil
	
	-- 즉시 SaveService에 동기화
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.palbox = palbox
			return state
		end)
	end
	
	print(string.format("[PalboxService] Removed pal %s for player %d", palUID, userId))
	
	-- 클라이언트 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Palbox.Updated", {
			action = "REMOVE",
			palUID = palUID,
		})
	end
	
	return true
end

--- 팰 정보 조회
function PalboxService.getPal(userId: number, palUID: string): any?
	local palbox = getOrCreatePalbox(userId)
	return palbox[palUID]
end

--- 전체 팰 목록 조회
function PalboxService.getPalList(userId: number): {[string]: any}
	return getOrCreatePalbox(userId)
end

--- 보유 팰 수 조회
function PalboxService.getPalCount(userId: number): number
	local palbox = getOrCreatePalbox(userId)
	local count = 0
	for _ in pairs(palbox) do count = count + 1 end
	return count
end

--- 팰 상태 업데이트
function PalboxService.updatePalState(userId: number, palUID: string, newState: string): boolean
	local palbox = getOrCreatePalbox(userId)
	local pal = palbox[palUID]
	if not pal then return false end
	
	pal.state = newState
	return true
end

--- 팰 스탯 수정 (Hunger, SAN 등)
function PalboxService.modifyPalStats(userId: number, palUID: string, statChanges: {[string]: number}): boolean
	local palbox = getOrCreatePalbox(userId)
	local pal = palbox[palUID]
	if not pal or not pal.stats then return false end
	
	for statName, delta in pairs(statChanges) do
		local current = pal.stats[statName] or 0
		local maxVal = 100
		if statName == "hp" then
			local creatureData = DataService and DataService.getCreature(pal.creatureId)
			maxVal = (creatureData and creatureData.maxHealth) or 100
		end
		if statName == "hunger" then maxVal = Balance.PAL_HUNGER_MAX or 100 end
		if statName == "san" then maxVal = Balance.PAL_SAN_MAX or 100 end
		
		pal.stats[statName] = math.clamp(current + delta, 0, maxVal)
	end
	
	-- 클라이언트 알림
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Palbox.Updated", {
			action = "UPDATE_STATS",
			palUID = palUID,
			stats = pal.stats,
		})
	end
	
	return true
end

local TextService = game:GetService("TextService")

--- 팰 닉네임 변경
function PalboxService.renamePal(userId: number, palUID: string, newName: string): boolean
	local palbox = getOrCreatePalbox(userId)
	local pal = palbox[palUID]
	if not pal then return false end
	
	-- 1. 기초 길이 검증 (한글/특수문자 고려 12자 제한)
	local charLen = utf8.len(newName)
	if not charLen or charLen == 0 or charLen > 12 then
		return false
	end
	
	-- 2. 비속어 필터링 (Roblox 필수)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return false end
	
	local success, filterResult = pcall(function()
		return TextService:FilterStringAsync(newName, userId)
	end)
	
	if not success or not filterResult then
		warn("[PalboxService] Text filtering failed:", tostring(filterResult))
		return false
	end
	
	local filteredName = ""
	local success2, err2 = pcall(function()
		filteredName = filterResult:GetChatForUserAsync(userId)
	end)
	
	if not success2 or filteredName == "" then
		warn("[PalboxService] Failed to get filtered string:", tostring(err2))
		return false
	end
	
	-- 비동기 대기 후 재검증: 필터링 중 팰이 삭제/이동되었을 수 있음
	local palboxAfter = getOrCreatePalbox(userId)
	local palAfter = palboxAfter[palUID]
	if not palAfter then
		warn("[PalboxService] Pal removed during rename async:", palUID)
		return false
	end
	local playerAfter = Players:GetPlayerByUserId(userId)
	if not playerAfter then return false end
	
	palAfter.nickname = filteredName
	
	if NetController then
		NetController.FireClient(playerAfter, "Palbox.Updated", {
			action = "RENAME",
			palUID = palUID,
			nickname = filteredName,
		})
	end
	
	return true
end

--- 팰 시설 배치 설정
function PalboxService.setAssignedFacility(userId: number, palUID: string, facilityUID: string?): boolean
	local palbox = getOrCreatePalbox(userId)
	local pal = palbox[palUID]
	if not pal then return false end
	
	pal.assignedFacility = facilityUID
	if facilityUID then
		pal.state = Enums.PalState.WORKING
	else
		pal.state = Enums.PalState.STORED
	end
	
	return true
end

--========================================
-- Persistence (Save/Load)
--========================================

function PalboxService._loadPlayerPals(player: Player)
	local userId = player.UserId
	
	-- SaveService에서 플레이어 상태 읽기
	if SaveService and SaveService.getPlayerState then
		local state = SaveService.getPlayerState(userId)
		if state and state.palbox then
			playerPalboxes[userId] = state.palbox
			print(string.format("[PalboxService] Loaded %d pals for player %d",
				PalboxService.getPalCount(userId), userId))
			return
		end
	end
	
	-- 저장 데이터 없으면 빈 보관함
	playerPalboxes[userId] = {}
end

function PalboxService._savePlayerPals(player: Player)
	local userId = player.UserId
	local palbox = playerPalboxes[userId]
	
	if palbox and SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.palbox = palbox
			return state
		end)
		print(string.format("[PalboxService] Saved %d pals for player %d",
			PalboxService.getPalCount(userId), userId))
	end
end

--========================================
-- Network Handlers
--========================================

local function handleListRequest(player: Player, _payload)
	local userId = player.UserId
	local palbox = PalboxService.getPalList(userId)
	
	-- 클라이언트에 보낼 형태로 변환
	local palList = {}
	for uid, pal in pairs(palbox) do
		table.insert(palList, {
			palUID = uid,
			creatureId = pal.creatureId,
			nickname = pal.nickname,
			level = pal.level,
			stats = pal.stats,
			workTypes = pal.workTypes,
			combatPower = pal.combatPower,
			state = pal.state,
		})
	end
	
	return {
		success = true,
		data = {
			pals = palList,
			maxPals = Balance.MAX_PALBOX,
			count = #palList,
		}
	}
end

local function handleRenameRequest(player: Player, payload)
	local palUID = payload.palUID
	local newName = payload.newName
	
	if not palUID or not newName then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local ok = PalboxService.renamePal(player.UserId, palUID, newName)
	if not ok then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end
	
	return { success = true }
end

local function handleReleaseRequest(player: Player, payload)
	local palUID = payload.palUID
	
	if not palUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local ok = PalboxService.removePal(player.UserId, palUID)
	if not ok then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end
	
	return { success = true }
end

-- 동물 관리 탭 전용: 원클릭 소환 (파티 추가 + 소환 자동 처리)
local function handleQuickSummonRequest(player: Player, payload)
	local palUID = payload.palUID
	if not palUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	local userId = player.UserId
	local pal = PalboxService.getPal(userId, palUID)
	if not pal then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	-- PartyService 참조
	local PartyService = require(game:GetService("ServerScriptService").Server.Services.PartyService)

	-- 이미 소환 중이면 회수
	if pal.state == Enums.PalState.SUMMONED then
		PartyService._recallPal(userId)
		-- 파티에서도 제거
		PartyService.removeFromParty(userId, palUID)
		return { success = true, data = { action = "RECALLED" } }
	end

	-- 기존 소환 중인 팰이 있으면 먼저 회수
	PartyService._recallPal(userId)

	-- 파티에 추가 (이미 있으면 무시)
	if pal.state == Enums.PalState.STORED then
		local addOk, addErr = PartyService.addToParty(userId, palUID)
		if not addOk and addErr ~= Enums.ErrorCode.PAL_IN_PARTY then
			return { success = false, errorCode = addErr or "PARTY_ADD_FAILED" }
		end
	end

	-- 파티에서 슬롯 번호 찾기
	local partySlots = PartyService.getParty(userId)
	if not partySlots then
		return { success = false, errorCode = "NO_PARTY" }
	end

	local targetSlot
	for slot, uid in pairs(partySlots) do
		if uid == palUID then
			targetSlot = slot
			break
		end
	end

	if not targetSlot then
		return { success = false, errorCode = "NOT_IN_PARTY" }
	end

	-- 소환
	local summonOk, summonErr = PartyService.summon(userId, targetSlot)
	if not summonOk then
		return { success = false, errorCode = summonErr or "SUMMON_FAILED" }
	end

	return { success = true, data = { action = "SUMMONED" } }
end

-- 동물 관리 탭 전용: 풀어주기 (소환 중이면 회수 후 릴리즈)
local function handleQuickReleaseRequest(player: Player, payload)
	local palUID = payload.palUID
	if not palUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	local userId = player.UserId
	local pal = PalboxService.getPal(userId, palUID)
	if not pal then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	local PartyService = require(game:GetService("ServerScriptService").Server.Services.PartyService)

	-- 소환 중이면 먼저 회수
	if pal.state == Enums.PalState.SUMMONED then
		PartyService._recallPal(userId)
		task.wait(0.1)
	end

	-- 파티에 있으면 파티에서 제거
	if pal.state == Enums.PalState.IN_PARTY or pal.state == Enums.PalState.STORED then
		PartyService.removeFromParty(userId, palUID)
	end

	-- 상태를 STORED로 강제 복원 후 제거
	PalboxService.updatePalState(userId, palUID, Enums.PalState.STORED)

	local ok = PalboxService.removePal(userId, palUID)
	if not ok then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	return { success = true }
end

function PalboxService.GetHandlers()
	return {
		["Palbox.List.Request"] = handleListRequest,
		["Palbox.Rename.Request"] = handleRenameRequest,
		["Palbox.Release.Request"] = handleReleaseRequest,
		["Palbox.QuickSummon.Request"] = handleQuickSummonRequest,
		["Palbox.QuickRelease.Request"] = handleQuickReleaseRequest,
	}
end

return PalboxService
