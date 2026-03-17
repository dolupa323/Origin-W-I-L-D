-- TutorialController.lua
-- 튜토리얼 상태 수신 및 목표 안내 표시

local NetClient = require(script.Parent.Parent.NetClient)
local UIManager = require(script.Parent.Parent.UIManager)
local RadioStoryController = require(script.Parent.RadioStoryController)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialController = {}

local initialized = false
local lastStatusSignature = nil
local lastStatus = nil
local STATUS_RETRY_MAX = 12
local STATUS_RETRY_INTERVAL = 0.5
local WARMUP_POLL_COUNT = 4
local WARMUP_POLL_INTERVAL = 3
local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
local itemNameById = {}

for _, item in ipairs(ItemData) do
	if type(item) == "table" and item.id then
		itemNameById[tostring(item.id)] = tostring(item.name or item.id)
	end
end

local function buildProgressSignature(progress)
	if type(progress) ~= "table" then
		return ""
	end
	local keys = {}
	for key in pairs(progress) do
		table.insert(keys, key)
	end
	table.sort(keys)

	local chunks = {}
	for _, key in ipairs(keys) do
		table.insert(chunks, tostring(key) .. ":" .. tostring(progress[key]))
	end
	return table.concat(chunks, "|")
end

local function buildStatusSignature(status)
	if type(status) ~= "table" then
		return ""
	end
	return table.concat({
		tostring(status.completed == true),
		tostring(status.active == true),
		tostring(status.stepKey or ""),
		tostring(status.stepIndex or 0),
		tostring(status.stepReady == true),
		buildProgressSignature(status.progress),
	}, "#")
end

local function rewardSummary(reward)
	if type(reward) ~= "table" then
		return nil
	end
	local chunks = {}
	if (reward.xp or 0) > 0 then
		table.insert(chunks, string.format("XP +%d", reward.xp))
	end
	if (reward.gold or 0) > 0 then
		table.insert(chunks, string.format("골드 +%d", reward.gold))
	end
	if type(reward.items) == "table" then
		for _, item in ipairs(reward.items) do
			if type(item) == "table" and item.itemId and item.count then
				local itemId = tostring(item.itemId)
				local fallbackName = itemNameById[itemId] or itemId
				local itemName = UILocalizer.LocalizeDataText("ItemData", itemId, "name", fallbackName)
				table.insert(chunks, string.format("%s x%d", itemName, tonumber(item.count) or 1))
			end
		end
	end
	if #chunks == 0 then
		return nil
	end
	return table.concat(chunks, ", ")
end

local function buildDisplayStatus(status)
	return status
end

local function showStatus(status, force, allowCompletionToast)
	if type(status) ~= "table" then
		return
	end

	local signature = buildStatusSignature(status)
	if not force and signature == lastStatusSignature then
		return
	end
	lastStatusSignature = signature
	lastStatus = status

	RadioStoryController.syncTutorialStatus(status)

	local displayStatus = buildDisplayStatus(status)
	UIManager.updateTutorialStatus(displayStatus)

	if status.completed then
		UIManager.setTutorialVisible(false)
		if allowCompletionToast then
			local summary = rewardSummary(status.reward)
			if summary then
				UIManager.notify("튜토리얼 완료! 보상: " .. summary)
			else
				UIManager.notify("튜토리얼 완료! 이제 자유롭게 생존해보세요.")
			end
		end
		return
	end

	if not status.active then
		UIManager.setTutorialVisible(false)
		return
	end

	UIManager.setTutorialVisible(RadioStoryController.shouldShowQuestUI(status))
end

function TutorialController.Init()
	if initialized then
		warn("[TutorialController] Already initialized")
		return
	end

	RadioStoryController.setClaimHandler(nil)

	RadioStoryController.setQuestGateChangedHandler(function()
		if type(lastStatus) == "table" then
			UIManager.setTutorialVisible(RadioStoryController.shouldShowQuestUI(lastStatus))
		end
	end)

	NetClient.On("Tutorial.Step.Updated", function(data)
		showStatus(data, false, false)
	end)

	NetClient.On("Tutorial.Completed", function(data)
		showStatus(data, true, true)
	end)

	task.spawn(function()
		for poll = 1, WARMUP_POLL_COUNT do
			local fetched = false
			for _ = 1, STATUS_RETRY_MAX do
				local ok, data = NetClient.Request("Tutorial.GetStatus.Request", {})
				if ok then
					-- Force true: 부팅 직후 오버레이에 가려진 안내를 다시 노출
					showStatus(data, true, false)
					fetched = true
					break
				end

				if data ~= "NET_UNKNOWN_COMMAND" then
					break
				end

				task.wait(STATUS_RETRY_INTERVAL)
			end

			if poll == WARMUP_POLL_COUNT and not fetched then
				warn("[TutorialController] Tutorial.GetStatus.Request failed after retries")
			end

			if poll < WARMUP_POLL_COUNT then
				task.wait(WARMUP_POLL_INTERVAL)
			end
		end
	end)

	initialized = true
	print("[TutorialController] Initialized")
end

return TutorialController
