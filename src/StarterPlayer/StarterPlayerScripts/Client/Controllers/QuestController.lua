-- QuestController.lua
-- 클라이언트 퀘스트 컨트롤러 (Phase 8)
-- 서버 Quest 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local QuestController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 퀘스트 캐시 [questId] = QuestState
local questCache = {}

-- 제한된 이벤트 리스너들
local listeners = {
	updated = {},
	completed = {},
	newAvailable = {},
}

--========================================
-- Public API: Cache Access
--========================================

--- 퀘스트 캐시 전체 조회
function QuestController.getQuestCache()
	return questCache
end

--- 특정 퀘스트 조회
function QuestController.getQuest(questId: string)
	return questCache[questId]
end

--- 활성 퀘스트 목록 조회
function QuestController.getActiveQuests(): { any }
	local result = {}
	for questId, quest in pairs(questCache) do
		if quest.status == "ACTIVE" then
			table.insert(result, quest)
		end
	end
	return result
end

--- 완료 가능한 퀘스트 목록 조회
function QuestController.getCompletedQuests(): { any }
	local result = {}
	for questId, quest in pairs(questCache) do
		if quest.status == "COMPLETED" then
			table.insert(result, quest)
		end
	end
	return result
end

--========================================
-- Public API: Server Requests
--========================================

--- 퀘스트 목록 요청
function QuestController.requestList(callback: (boolean, any?) -> ()?)
	NetClient.Request("Quest.List.Request", {}, function(response)
		if response.success and response.data and response.data.quests then
			-- 캐시 업데이트
			for questId, quest in pairs(response.data.quests) do
				questCache[questId] = quest
			end
		end
		if callback then
			callback(response.success, response.data)
		end
	end)
end

--- 퀘스트 수락 요청
function QuestController.requestAccept(questId: string, callback: (boolean, string?) -> ()?)
	NetClient.Request("Quest.Accept.Request", { questId = questId }, function(response)
		if callback then
			callback(response.success, response.errorCode)
		end
	end)
end

--- 보상 수령 요청
function QuestController.requestClaim(questId: string, callback: (boolean, string?) -> ()?)
	NetClient.Request("Quest.Claim.Request", { questId = questId }, function(response)
		if callback then
			callback(response.success, response.errorCode)
		end
	end)
end

--- 퀘스트 포기 요청
function QuestController.requestAbandon(questId: string, callback: (boolean, string?) -> ()?)
	NetClient.Request("Quest.Abandon.Request", { questId = questId }, function(response)
		if callback then
			callback(response.success, response.errorCode)
		end
	end)
end

--========================================
-- Event Listener API
--========================================

--- 퀘스트 업데이트 이벤트 리스너 등록
function QuestController.onUpdated(callback: (any) -> ())
	table.insert(listeners.updated, callback)
end

--- 퀘스트 완료 이벤트 리스너 등록
function QuestController.onCompleted(callback: (any) -> ())
	table.insert(listeners.completed, callback)
end

--- 새 퀘스트 수락 가능 이벤트 리스너 등록
function QuestController.onNewAvailable(callback: (any) -> ())
	table.insert(listeners.newAvailable, callback)
end

--========================================
-- Event Handlers
--========================================

local function onQuestUpdated(data)
	if not data or not data.questId then return end
	
	-- 캐시 업데이트
	questCache[data.questId] = {
		id = data.questId,
		name = data.name,
		description = data.description,
		category = data.category,
		status = data.status,
		progress = data.progress,
		objectives = data.objectives,
	}
	
	-- 리스너 호출
	for _, callback in ipairs(listeners.updated) do
		pcall(callback, data)
	end
	
	print(string.format("[QuestController] Quest updated: %s (status: %s)", data.questId, data.status))
end

local function onQuestCompleted(data)
	if not data or not data.questId then return end
	
	-- 캐시 업데이트
	if questCache[data.questId] then
		questCache[data.questId].status = "COMPLETED"
	end
	
	-- 리스너 호출
	for _, callback in ipairs(listeners.completed) do
		pcall(callback, data)
	end
	
	print(string.format("[QuestController] Quest completed: %s (rewards: %dxp)", 
		data.questId, data.rewards and data.rewards.xp or 0))
end

local function onQuestNewAvailable(data)
	if not data or not data.questId then return end
	
	-- 리스너 호출
	for _, callback in ipairs(listeners.newAvailable) do
		pcall(callback, data)
	end
	
	print(string.format("[QuestController] New quest available: %s", data.questId))
end

--========================================
-- Initialization
--========================================

function QuestController.Init()
	if initialized then
		warn("[QuestController] Already initialized")
		return
	end
	
	-- 이벤트 리스너 등록
	NetClient.On("Quest.Updated", onQuestUpdated)
	NetClient.On("Quest.Completed", onQuestCompleted)
	NetClient.On("Quest.NewAvailable", onQuestNewAvailable)
	
	-- 초기 퀘스트 목록 로드
	QuestController.requestList(function(success, data)
		if success then
			print(string.format("[QuestController] Loaded %d quests", 
				data and data.quests and #data.quests or 0))
		end
	end)
	
	initialized = true
	print("[QuestController] Initialized - listening for Quest events")
end

return QuestController
