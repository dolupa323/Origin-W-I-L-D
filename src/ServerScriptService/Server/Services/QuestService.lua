-- QuestService.lua
-- 퀘스트 시스템 서비스 (Phase 8)
-- 퀘스트 상태 관리, 진행 추적, 보상 지급

local QuestService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController
local DataService
local SaveService
local InventoryService
local PlayerStatService
local PalboxService

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

--========================================
-- Internal State
--========================================
local questDataMap = {}     -- [questId] = questData (Init에서 로드)
local playerQuests = {}     -- [userId] = { [questId] = QuestState }

-- QuestState: { status, progress = { [objectiveIndex] = count } }

-- Forward declarations
local _emitQuestUpdated
local _emitQuestCompleted
local _checkAutoGrant
local _checkQuestCompletion

--========================================
-- Internal: Quest Data
--========================================

--- 퀘스트 데이터 로드 (DataService에서)
local function _loadQuestData()
	local questData = DataService.get("QuestData")
	if not questData then
		warn("[QuestService] QuestData not found!")
		return
	end
	
	local count = 0
	for questId, quest in pairs(questData) do
		questDataMap[questId] = quest
		count = count + 1
	end
	
	print(string.format("[QuestService] Loaded %d quests", count))
end

--- 플레이어 퀘스트 상태 초기화/로드
local function _initPlayerQuests(userId: number)
	if playerQuests[userId] then return end
	
	-- SaveService에서 로드
	local state = SaveService and SaveService.getPlayerState(userId)
	local savedQuests = state and state.quests
	
	playerQuests[userId] = savedQuests or {}
	
	-- 자동 부여 퀘스트 확인
	_checkAutoGrant(userId)
end

--- 플레이어 퀘스트 상태 저장
local function _savePlayerQuests(userId: number)
	local quests = playerQuests[userId]
	if not quests then return end
	
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.quests = quests
			return state
		end)
	end
end

--- 자동 부여 퀘스트 확인
_checkAutoGrant = function(userId: number)
	local quests = playerQuests[userId]
	if not quests then return end
	
	local playerLevel = 1
	if PlayerStatService and PlayerStatService.getStats then
		local stats = PlayerStatService.getStats(userId)
		playerLevel = stats and stats.level or 1
	end
	
	for questId, quest in pairs(questDataMap) do
		-- 이미 진행/완료된 퀘스트 스킵
		if quests[questId] then continue end
		
		-- 자동 부여 조건 확인
		if not quest.autoGrant then continue end
		if quest.autoGrantLevel and playerLevel < quest.autoGrantLevel then continue end
		
		-- 선행 조건 확인
		local prereqMet = true
		for _, prereqId in ipairs(quest.prerequisites or {}) do
			local prereqState = quests[prereqId]
			if not prereqState or prereqState.status ~= Enums.QuestStatus.CLAIMED then
				prereqMet = false
				break
			end
		end
		if not prereqMet then continue end
		
		-- 퀘스트 자동 부여
		quests[questId] = {
			status = Enums.QuestStatus.ACTIVE,
			progress = {},
		}
		
		-- 각 objective 초기화
		for i, _ in ipairs(quest.objectives or {}) do
			quests[questId].progress[i] = 0
		end
		
		print(string.format("[QuestService] Auto-granted quest %s to user %d", questId, userId))
		
		-- 이벤트 발행
		_emitQuestUpdated(userId, questId)
	end
end

--========================================
-- Internal: Events
--========================================

--- Quest.Updated 이벤트 발행
_emitQuestUpdated = function(userId: number, questId: string)
	if not NetController then return end
	
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player then return end
	
	local quests = playerQuests[userId]
	local questState = quests and quests[questId]
	local questData = questDataMap[questId]
	
	if not questState or not questData then return end
	
	NetController.FireClient(player, "Quest.Updated", {
		questId = questId,
		name = questData.name,
		description = questData.description,
		category = questData.category,
		status = questState.status,
		progress = questState.progress,
		objectives = questData.objectives,
	})
end

--- Quest.Completed 이벤트 발행
_emitQuestCompleted = function(userId: number, questId: string)
	if not NetController then return end
	
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player then return end
	
	local questData = questDataMap[questId]
	if not questData then return end
	
	NetController.FireClient(player, "Quest.Completed", {
		questId = questId,
		name = questData.name,
		rewards = questData.rewards,
	})
end

--========================================
-- Internal: Progress Check
--========================================

--- 퀘스트 완료 조건 확인
_checkQuestCompletion = function(userId: number, questId: string)
	local quests = playerQuests[userId]
	local questState = quests and quests[questId]
	if not questState or questState.status ~= Enums.QuestStatus.ACTIVE then
		return
	end
	
	local questData = questDataMap[questId]
	if not questData then return end
	
	-- 모든 objective 완료 확인
	local allCompleted = true
	for i, objective in ipairs(questData.objectives or {}) do
		local current = questState.progress[i] or 0
		if current < (objective.count or 1) then
			allCompleted = false
			break
		end
	end
	
	if allCompleted then
		questState.status = Enums.QuestStatus.COMPLETED
		_savePlayerQuests(userId)
		_emitQuestCompleted(userId, questId)
		
		print(string.format("[QuestService] Quest %s completed by user %d", questId, userId))
	end
end

--- 진행 업데이트 (범용)
local function _updateProgress(userId: number, objectiveType: string, targetId: string?, count: number)
	local quests = playerQuests[userId]
	if not quests then
		_initPlayerQuests(userId)
		quests = playerQuests[userId]
	end
	
	for questId, questState in pairs(quests) do
		if questState.status ~= Enums.QuestStatus.ACTIVE then continue end
		
		local questData = questDataMap[questId]
		if not questData then continue end
		
		for i, objective in ipairs(questData.objectives or {}) do
			if objective.type ~= objectiveType then continue end
			
			-- targetId 확인 (nil이면 아무거나 매칭)
			if targetId ~= nil and objective.targetId ~= nil and objective.targetId ~= targetId then
				continue
			end
			
			-- 진행도 증가
			local current = questState.progress[i] or 0
			local newProgress = math.min(current + count, objective.count or 1)
			
			if newProgress ~= current then
				questState.progress[i] = newProgress
				_emitQuestUpdated(userId, questId)
				_checkQuestCompletion(userId, questId)
			end
		end
	end
	
	_savePlayerQuests(userId)
end

--========================================
-- Public API: Quest Management
--========================================

--- 초기화
function QuestService.Init(
	netController,
	dataService,
	saveService,
	inventoryService,
	playerStatService,
	palboxService
)
	if initialized then return end
	
	NetController = netController
	DataService = dataService
	SaveService = saveService
	InventoryService = inventoryService
	PlayerStatService = playerStatService
	PalboxService = palboxService
	
	_loadQuestData()
	
	initialized = true
	print("[QuestService] Initialized")
end

--- 플레이어 퀘스트 목록 가져오기
function QuestService.getPlayerQuests(userId: number): {[string]: any}
	_initPlayerQuests(userId)
	
	local result = {}
	local quests = playerQuests[userId] or {}
	
	for questId, questState in pairs(quests) do
		local questData = questDataMap[questId]
		if questData then
			result[questId] = {
				id = questId,
				name = questData.name,
				description = questData.description,
				category = questData.category,
				status = questState.status,
				progress = questState.progress,
				objectives = questData.objectives,
				rewards = questData.rewards,
			}
		end
	end
	
	return result
end

--- 퀘스트 수락
function QuestService.acceptQuest(player: Player, questId: string): (boolean, string?)
	local userId = player.UserId
	_initPlayerQuests(userId)
	
	-- 퀘스트 데이터 확인
	local questData = questDataMap[questId]
	if not questData then
		return false, Enums.ErrorCode.QUEST_NOT_FOUND
	end
	
	local quests = playerQuests[userId]
	local existing = quests[questId]
	
	-- 이미 진행/완료 확인
	if existing then
		if existing.status == Enums.QuestStatus.ACTIVE then
			return false, Enums.ErrorCode.QUEST_ALREADY_ACTIVE
		end
		if existing.status == Enums.QuestStatus.COMPLETED then
			return false, Enums.ErrorCode.QUEST_ALREADY_ACTIVE
		end
		if existing.status == Enums.QuestStatus.CLAIMED and not questData.repeatable then
			return false, Enums.ErrorCode.QUEST_NOT_REPEATABLE
		end
	end
	
	-- 레벨 확인
	local playerLevel = 1
	if PlayerStatService and PlayerStatService.getStats then
		local stats = PlayerStatService.getStats(userId)
		playerLevel = stats and stats.level or 1
	end
	if questData.requiredLevel and playerLevel < questData.requiredLevel then
		return false, Enums.ErrorCode.QUEST_LEVEL_NOT_MET
	end
	
	-- 선행 조건 확인
	for _, prereqId in ipairs(questData.prerequisites or {}) do
		local prereqState = quests[prereqId]
		if not prereqState or prereqState.status ~= Enums.QuestStatus.CLAIMED then
			return false, Enums.ErrorCode.QUEST_PREREQ_NOT_MET
		end
	end
	
	-- 동시 진행 한도 확인
	local activeCount = 0
	for _, state in pairs(quests) do
		if state.status == Enums.QuestStatus.ACTIVE then
			activeCount = activeCount + 1
		end
	end
	if activeCount >= (Balance.QUEST_MAX_ACTIVE or 10) then
		return false, Enums.ErrorCode.QUEST_MAX_ACTIVE
	end
	
	-- 퀘스트 활성화
	quests[questId] = {
		status = Enums.QuestStatus.ACTIVE,
		progress = {},
	}
	for i, _ in ipairs(questData.objectives or {}) do
		quests[questId].progress[i] = 0
	end
	
	_savePlayerQuests(userId)
	_emitQuestUpdated(userId, questId)
	
	print(string.format("[QuestService] User %d accepted quest %s", userId, questId))
	return true, nil
end

--- 보상 수령
function QuestService.claimReward(player: Player, questId: string): (boolean, string?)
	local userId = player.UserId
	_initPlayerQuests(userId)
	
	local quests = playerQuests[userId]
	local questState = quests[questId]
	
	if not questState then
		return false, Enums.ErrorCode.QUEST_NOT_FOUND
	end
	
	if questState.status ~= Enums.QuestStatus.COMPLETED then
		return false, Enums.ErrorCode.QUEST_NOT_COMPLETED
	end
	
	local questData = questDataMap[questId]
	if not questData then
		return false, Enums.ErrorCode.QUEST_NOT_FOUND
	end
	
	-- 보상 지급
	local rewards = questData.rewards or {}
	
	-- XP 지급
	if rewards.xp and rewards.xp > 0 and PlayerStatService then
		PlayerStatService.addXP(userId, rewards.xp, Enums.XPSource.CRAFT_ITEM)
	end
	
	-- 기술 포인트 지급
	if rewards.techPoints and rewards.techPoints > 0 and PlayerStatService then
		PlayerStatService.addTechPoints(userId, rewards.techPoints)
	end
	
	-- 아이템 지급
	if rewards.items and InventoryService then
		for _, item in ipairs(rewards.items) do
			InventoryService.addItem(userId, item.itemId, item.count)
		end
	end
	
	-- 상태 업데이트
	questState.status = Enums.QuestStatus.CLAIMED
	_savePlayerQuests(userId)
	_emitQuestUpdated(userId, questId)
	
	-- 자동 부여 퀘스트 재확인
	_checkAutoGrant(userId)
	
	print(string.format("[QuestService] User %d claimed reward for quest %s", userId, questId))
	return true, nil
end

--- 퀘스트 포기
function QuestService.abandonQuest(player: Player, questId: string): (boolean, string?)
	local userId = player.UserId
	_initPlayerQuests(userId)
	
	local quests = playerQuests[userId]
	local questState = quests[questId]
	
	if not questState then
		return false, Enums.ErrorCode.QUEST_NOT_FOUND
	end
	
	if questState.status ~= Enums.QuestStatus.ACTIVE then
		return false, Enums.ErrorCode.BAD_REQUEST
	end
	
	-- 퀘스트 포기 (상태 제거)
	quests[questId] = nil
	_savePlayerQuests(userId)
	
	print(string.format("[QuestService] User %d abandoned quest %s", userId, questId))
	return true, nil
end

--========================================
-- Public API: Progress Tracking (다른 서비스에서 호출)
--========================================

--- 수확 시
function QuestService.onHarvest(userId: number, nodeType: string, count: number?)
	_updateProgress(userId, "HARVEST", nodeType, count or 1)
end

--- 처치 시
function QuestService.onKill(userId: number, creatureType: string, count: number?)
	_updateProgress(userId, "KILL", creatureType, count or 1)
end

--- 제작 시
function QuestService.onCraft(userId: number, recipeId: string, count: number?)
	_updateProgress(userId, "CRAFT", recipeId, count or 1)
end

--- 건설 시
function QuestService.onBuild(userId: number, facilityId: string)
	_updateProgress(userId, "BUILD", facilityId, 1)
end

--- 포획 시
function QuestService.onCapture(userId: number, palType: string)
	_updateProgress(userId, "CAPTURE", palType, 1)
	
	-- PAL_COUNT 목표도 업데이트 (현재 보유 팰 수)
	if PalboxService then
		local palCount = #(PalboxService.listPals(userId) or {})
		
		local quests = playerQuests[userId] or {}
		for questId, questState in pairs(quests) do
			if questState.status ~= Enums.QuestStatus.ACTIVE then continue end
			
			local questData = questDataMap[questId]
			if not questData then continue end
			
			for i, objective in ipairs(questData.objectives or {}) do
				if objective.type == "COLLECT" and objective.targetId == "PAL_COUNT" then
					questState.progress[i] = palCount
					_emitQuestUpdated(userId, questId)
					_checkQuestCompletion(userId, questId)
				end
			end
		end
	end
end

--- 레벨업 시
function QuestService.onLevelUp(userId: number, newLevel: number)
	_updateProgress(userId, "REACH_LEVEL", nil, newLevel)
	
	-- 레벨업 시 자동 부여 퀘스트 재확인
	_checkAutoGrant(userId)
end

--- 기술 해금 시
function QuestService.onTechUnlock(userId: number, techId: string)
	_updateProgress(userId, "UNLOCK_TECH", techId, 1)
end

--========================================
-- Network Handlers
--========================================

local function handleList(player: Player, payload: any)
	local quests = QuestService.getPlayerQuests(player.UserId)
	return { success = true, data = { quests = quests } }
end

local function handleAccept(player: Player, payload: any)
	local questId = payload.questId
	if not questId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode = QuestService.acceptQuest(player, questId)
	if success then
		return { success = true, data = { questId = questId } }
	else
		return { success = false, errorCode = errorCode }
	end
end

local function handleClaim(player: Player, payload: any)
	local questId = payload.questId
	if not questId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode = QuestService.claimReward(player, questId)
	if success then
		return { success = true, data = { questId = questId } }
	else
		return { success = false, errorCode = errorCode }
	end
end

local function handleAbandon(player: Player, payload: any)
	local questId = payload.questId
	if not questId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode = QuestService.abandonQuest(player, questId)
	if success then
		return { success = true, data = { questId = questId } }
	else
		return { success = false, errorCode = errorCode }
	end
end

--- 핸들러 테이블 반환
function QuestService.GetHandlers()
	return {
		["Quest.List.Request"] = handleList,
		["Quest.Accept.Request"] = handleAccept,
		["Quest.Claim.Request"] = handleClaim,
		["Quest.Abandon.Request"] = handleAbandon,
	}
end

return QuestService
