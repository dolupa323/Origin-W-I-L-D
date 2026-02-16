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
	
	-- 플레이어 로그인 시 팰 데이터 로드
	Players.PlayerAdded:Connect(function(player)
		PalboxService._loadPlayerPals(player)
	end)
	
	-- 플레이어 로그아웃 시 정리
	Players.PlayerRemoving:Connect(function(player)
		PalboxService._savePlayerPals(player)
		playerPalboxes[player.UserId] = nil
	end)
	
	print("[PalboxService] Initialized")
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

--- 팰 닉네임 변경
function PalboxService.renamePal(userId: number, palUID: string, newName: string): boolean
	local palbox = getOrCreatePalbox(userId)
	local pal = palbox[palUID]
	if not pal then return false end
	
	-- 닉네임 길이 제한
	if #newName == 0 or #newName > 20 then
		return false
	end
	
	pal.nickname = newName
	
	local player = Players:GetPlayerByUserId(userId)
	if player and NetController then
		NetController.FireClient(player, "Palbox.Updated", {
			action = "RENAME",
			palUID = palUID,
			nickname = newName,
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
			uid = uid,
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

function PalboxService.GetHandlers()
	return {
		["Palbox.List.Request"] = handleListRequest,
		["Palbox.Rename.Request"] = handleRenameRequest,
		["Palbox.Release.Request"] = handleReleaseRequest,
	}
end

return PalboxService
