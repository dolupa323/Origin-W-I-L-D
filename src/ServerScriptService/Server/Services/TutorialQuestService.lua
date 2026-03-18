-- TutorialQuestService.lua
-- 첫 진입 유저용 튜토리얼 퀘스트 라인

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local TutorialQuestService = {}

local initialized = false
local NetController = nil
local SaveService = nil
local PlayerStatService = nil
local InventoryService = nil
local NPCShopService = nil

local VERSION = 2
local PROGRESS_WAIT_TIMEOUT = 15
local PROGRESS_WAIT_INTERVAL = 0.2
local ADMIN_USER_IDS = {
	[10311679477] = true,
}

local STEPS = {
	{
		key = "COLLECT_BASICS",
		text = "잔돌 1개, 나뭇가지 1개부터 챙기기",
		command = "주변에서 SMALL_STONE 1개 + BRANCH 1개 줍기",
		tip = "Z 키로 주변 자원을 수집하십시오. 시작 지점 인근에서 우선 확보하십시오.",
		voiceIntro = "맨손으로는 하루도 못 버틴다. 바닥을 뒤져서 잔돌이랑 나뭇가지부터 챙겨.",
		voiceHint = "아직 부족하다. 잔해 근처를 조금만 더 뒤져봐.",
		voiceReady = "좋아, 그 정도면 됐다. 일단 도구부터 하나 만들자.",
		kind = "MULTI_ITEM",
		needs = {
			SMALL_STONE = 1,
			BRANCH = 1,
		},
		reward = {
			xp = 15,
			gold = 10,
			items = {},
		},
	},
	{
		key = "CRAFT_AXE",
		text = "조잡한 돌도끼 제작",
		command = "B 키 인벤토리의 간이제작 탭에서 CRAFT_CRUDE_STONE_AXE 1회 제작",
		tip = "제작 재료가 부족하면 주변 자원을 추가 수집한 뒤 다시 제작하십시오.",
		voiceIntro = "좋아, 재료는 모았군. 그걸로 대충이라도 돌도끼를 만들어라. 여기선 무기 없으면 바로 끝장이다.",
		voiceHint = "서두르지 말고 돌도끼부터 확실하게 만들어 둬.",
		voiceReady = "잘했다. 이제 장작을 좀 구하러 가자.",
		kind = "RECIPE",
		target = "CRAFT_CRUDE_STONE_AXE",
		reward = {
			xp = 15,
			gold = 15,
			items = {},
		},
	},
	{
		key = "GET_WOOD",
		text = "나무 자원 확보",
		command = "WOOD 또는 LOG 1개 이상 확보",
		tip = "도끼를 사용해 접근 가능한 나무 자원부터 최소 수량을 확보하십시오.",
		voiceIntro = "도끼는 들었나? 그럼 주변 나무부터 베어라. 오늘 밤을 버티려면 장작이 우선이다.",
		voiceHint = "장작이든 통나무든 하나만 먼저 가져와. 빨리.",
		voiceReady = "좋아, 나무 됐다. 이제 먹을 거 잡으러 간다.",
		kind = "ITEM_ANY",
		targets = { "WOOD", "LOG" },
		count = 1,
		reward = {
			xp = 15,
			gold = 20,
			items = {},
		},
	},
	{
		key = "KILL_DODO",
		text = "식량 확보를 위한 사냥",
		command = "DODO 1마리 처치",
		tip = "근접 공격 후 거리를 유지하며 안전하게 목표를 처치하십시오.",
		voiceIntro = "슬슬 배가 고플 거다. 근처에 보이는 '도도'를 한 마리 잡아. 그게 네 첫 끼니다.",
		voiceHint = "도도 한 마리만 잡으면 돼. 무리하지 마.",
		voiceReady = "좋아, 잡았군. 바로 불 피울 준비 해.",
		kind = "KILL",
		target = "DODO",
		reward = {
			xp = 15,
			gold = 20,
			items = {},
		},
	},
	{
		key = "BUILD_CAMPFIRE",
		text = "밤 대비 온기 수단 준비",
		command = "C 키 건축으로 CAMPFIRE 1개 설치 + B 키 인벤토리 간이제작 탭에서 CRAFT_TORCH 1회 제작",
		tip = "모닥불은 평지에 설치하고, 횃불 제작까지 완료해야 단계가 완료됩니다.",
		voiceIntro = "설마 생고기를 그냥 뜯어먹을 생각은 아니겠지? 모은 나무로 모닥불부터 피워라. 추위랑 짐승을 막으려면 불이 필수야.",
		voiceHint = "모닥불 세우고 횃불까지 하나 챙겨. 밤엔 그게 생명줄이다.",
		voiceReady = "좋아, 불 붙었다. 이제 고기 굽자.",
		kind = "BUILD_AND_RECIPE",
		buildTarget = "CAMPFIRE",
		recipeTarget = "CRAFT_TORCH",
		reward = {
			xp = 15,
			gold = 20,
			items = {},
		},
	},
	{
		key = "COOK_MEAT",
		text = "고기 1개 조리",
		command = "CRAFT_COOKED_MEAT 제작",
		tip = "모닥불이 활성 상태인지 확인한 뒤 조리 1회를 완료하십시오.",
		voiceIntro = "불은 잘 타오르고 있나? 고기를 올려서 구워라. 체력이 떨어지면 도망도 못 친다.",
		voiceHint = "익힌 고기 하나만 만들면 된다. 금방 끝난다.",
		voiceReady = "오케이, 배는 채웠군. 이제 거점을 표시할 차례다.",
		kind = "RECIPE",
		target = "CRAFT_COOKED_MEAT",
		reward = {
			xp = 15,
			gold = 20,
			items = {
				{ itemId = "COOKED_MEAT", count = 1 },
			},
		},
	},
	{
		key = "PLACE_TOTEM",
		text = "거점 중심점 확보",
		command = "CAMP_TOTEM 1개 설치",
		tip = "이동 동선의 중심 지점을 고려해 토템 설치 위치를 선정하십시오.",
		voiceIntro = "이런 숲에서 길을 잃으면 그걸로 끝이다. 토템을 세워서 네 거점을 표시해 둬.",
		voiceHint = "토템 하나만 박으면 돼. 위치를 신중하게 골라.",
		voiceReady = "좋아, 거점 잡혔다. 마지막으로 잠자리 만든다.",
		kind = "BUILD",
		target = "CAMP_TOTEM",
		reward = {
			xp = 15,
			gold = 20,
			items = {},
		},
	},
	{
		key = "BUILD_LEAN_TO",
		text = "수면/복귀 지점 확보",
		command = "LEAN_TO 1개 설치",
		tip = "모닥불 온기 범위 인근에 설치하되 이동 경로를 방해하지 않도록 배치하십시오.",
		voiceIntro = "거의 다 왔다. 밤추위가 오기 전에 임시 대피소(린투)를 세워. 거기서 잠을 자고 위치를 기억해 둬야, 쓰러져도 다시 일어날 수 있다.",
		voiceHint = "대피소 하나만 세우면 끝이다. 조금만 더 버텨.",
		voiceReady = "좋아. 이제 기초 작업대를 세워 더 강한 물품 제작을 준비해라.",
		kind = "BUILD",
		target = "LEAN_TO",
		reward = {
			xp = 15,
			gold = 25,
			items = {
				{ itemId = "COOKED_MEAT", count = 2 },
			},
		},
	},
	{
		key = "BUILD_WORKBENCH",
		text = "기초 작업대 구축",
		command = "BASIC_WORKBENCH 1개 설치",
		tip = "기초 작업대를 설치하면 더 강한 도구, 무기, 방어구 제작이 가능합니다.",
		voiceIntro = "지금부터 생존 단계가 달라진다. 기초 작업대를 세워서 상위 제작을 열어라.",
		voiceHint = "작업대 하나면 된다. 평평한 곳에 설치해.",
		voiceReady = "좋아, 이제 더 강한 물품을 만들 준비가 끝났다. 이제부터가 진짜 생존의 시작이다.",
		kind = "BUILD",
		target = "BASIC_WORKBENCH",
		reward = {
			xp = 20,
			gold = 30,
			items = {},
		},
	},
}

local function cloneReward(reward)
	if type(reward) ~= "table" then
		return {
			xp = 0,
			gold = 0,
			currency = 0,
			items = {},
		}
	end

	local copy = {
		xp = tonumber(reward.xp) or 0,
		gold = tonumber(reward.gold) or 0,
		items = {},
	}

	if type(reward.items) == "table" then
		for _, item in ipairs(reward.items) do
			if type(item) == "table" and item.itemId and (tonumber(item.count) or 0) > 0 then
				table.insert(copy.items, {
					itemId = tostring(item.itemId),
					count = tonumber(item.count) or 0,
				})
			end
		end
	end

	copy.currency = copy.gold
	return copy
end

local function getCurrentStep(progress)
	if not progress or progress.completed then
		return nil
	end
	return STEPS[progress.stepIndex]
end

local function isAdminUser(userId)
	if userId == game.CreatorId then
		return true
	end
	return ADMIN_USER_IDS[userId] == true
end

local function makeFreshProgress()
	return {
		version = VERSION,
		active = true,
		completed = false,
		stepIndex = 1,
		stepData = {},
		stepReady = false,
		assigned = false,
		assignedAt = 0,
		rewardClaimed = false,
	}
end

local function getOrCreateProgress(userId)
	local state = SaveService and SaveService.getPlayerState(userId)
	if type(state) ~= "table" then
		return nil
	end

	if isAdminUser(userId) then
		if type(state.tutorialQuest) ~= "table" then
			state.tutorialQuest = makeFreshProgress()
		else
			state.tutorialQuest.version = VERSION
			state.tutorialQuest.active = true
			if state.tutorialQuest.stepIndex == nil or state.tutorialQuest.stepIndex < 1 or state.tutorialQuest.stepIndex > (#STEPS + 1) then
				state.tutorialQuest.stepIndex = 1
			end
			if state.tutorialQuest.stepIndex <= #STEPS then
				state.tutorialQuest.completed = false
			else
				state.tutorialQuest.completed = true
			end
			state.tutorialQuest.stepData = type(state.tutorialQuest.stepData) == "table" and state.tutorialQuest.stepData or {}
			state.tutorialQuest.stepReady = state.tutorialQuest.stepReady == true
			state.tutorialQuest.assigned = state.tutorialQuest.assigned == true
			state.tutorialQuest.assignedAt = tonumber(state.tutorialQuest.assignedAt) or 0
			state.tutorialQuest.rewardClaimed = state.tutorialQuest.rewardClaimed == true
		end
		return state.tutorialQuest
	end

	if type(state.tutorialQuest) ~= "table" then
		state.tutorialQuest = makeFreshProgress()
	else
		state.tutorialQuest.version = VERSION
		state.tutorialQuest.stepData = type(state.tutorialQuest.stepData) == "table" and state.tutorialQuest.stepData or {}
		state.tutorialQuest.stepReady = state.tutorialQuest.stepReady == true
		state.tutorialQuest.assigned = state.tutorialQuest.assigned == true
		state.tutorialQuest.assignedAt = tonumber(state.tutorialQuest.assignedAt) or 0
		state.tutorialQuest.rewardClaimed = state.tutorialQuest.rewardClaimed == true

		if state.tutorialQuest.completed == true or state.tutorialQuest.stepIndex == nil then
			state.tutorialQuest.stepIndex = 1
			state.tutorialQuest.stepData = {}
			state.tutorialQuest.stepReady = false
			state.tutorialQuest.assigned = false
			state.tutorialQuest.assignedAt = 0
			state.tutorialQuest.rewardClaimed = false
		end

		if state.tutorialQuest.stepIndex < 1 then
			state.tutorialQuest.stepIndex = 1
		end
		if state.tutorialQuest.stepIndex > #STEPS then
			state.tutorialQuest.stepIndex = 1
			state.tutorialQuest.stepData = {}
			state.tutorialQuest.stepReady = false
			state.tutorialQuest.assigned = false
			state.tutorialQuest.assignedAt = 0
			state.tutorialQuest.rewardClaimed = false
		end

		state.tutorialQuest.active = true
		state.tutorialQuest.completed = false
	end

	return state.tutorialQuest
end

local function waitForProgress(userId, timeoutSec)
	local deadline = os.clock() + (timeoutSec or PROGRESS_WAIT_TIMEOUT)
	local progress = getOrCreateProgress(userId)
	while not progress and os.clock() < deadline do
		task.wait(PROGRESS_WAIT_INTERVAL)
		progress = getOrCreateProgress(userId)
	end
	return progress
end

local function serializeStatus(userId)
	local progress = getOrCreateProgress(userId)
	if not progress then
		return {
			active = false,
			completed = false,
			stepIndex = 0,
			totalSteps = #STEPS,
		}
	end

	local step = getCurrentStep(progress)
	local rewardPreview = cloneReward(step and step.reward)

	local status = {
		active = progress.active == true and progress.completed ~= true,
		completed = progress.completed == true,
		stepIndex = progress.stepIndex,
		totalSteps = #STEPS,
		stepKey = step and step.key or nil,
		stepKind = step and step.kind or nil,
		stepTarget = step and step.target or nil,
		stepTargets = step and step.targets or nil,
		stepCount = step and step.count or nil,
		stepCommand = step and step.command or nil,
		stepTip = step and step.tip or nil,
		stepVoiceIntro = step and step.voiceIntro or nil,
		stepVoiceHint = step and step.voiceHint or nil,
		stepVoiceReady = step and step.voiceReady or nil,
		needs = step and step.needs or nil,
		stepReady = progress.stepReady == true,
		assigned = progress.assigned == true,
		rewardPreview = rewardPreview,
		currentStepText = step and step.text or nil,
		progress = progress.stepData,
	}

	return status
end

local function fireStatus(userId, eventName, extra)
	if not NetController then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local payload = serializeStatus(userId)
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	NetController.FireClient(player, eventName, payload)
end

local function grantReward(userId, reward, reason)
	if type(reward) ~= "table" then
		return nil
	end

	local normalized = cloneReward(reward)

	if PlayerStatService and normalized.xp > 0 then
		PlayerStatService.addXP(userId, normalized.xp, reason or "TutorialStep")
	end

	if NPCShopService and normalized.gold > 0 then
		NPCShopService.addGold(userId, normalized.gold)
	end

	if InventoryService and type(normalized.items) == "table" then
		for _, rewardItem in ipairs(normalized.items) do
			if rewardItem.itemId and (rewardItem.count or 0) > 0 then
				InventoryService.addItem(userId, rewardItem.itemId, rewardItem.count)
			end
		end
	end

	return normalized
end

local function completeStep(userId)
	local progress = getOrCreateProgress(userId)
	if not progress or progress.completed then
		return nil
	end

	local step = getCurrentStep(progress)
	local grantedReward = grantReward(userId, step and step.reward, "TutorialStepComplete")

	progress.stepIndex = progress.stepIndex + 1
	progress.stepData = {}
	progress.stepReady = false

	if progress.stepIndex > #STEPS then
		progress.completed = true
		progress.active = false
		progress.rewardClaimed = true
		fireStatus(userId, "Tutorial.Completed", { reward = grantedReward, grantedReward = grantedReward })
	else
		fireStatus(userId, "Tutorial.Step.Updated", { grantedReward = grantedReward })
	end

	return grantedReward
end

local function handleMultiItemStep(userId, progress, step, itemId, count)
	if type(step.needs) ~= "table" then
		return
	end
	if not step.needs[itemId] then
		return
	end

	local stepData = progress.stepData or {}
	stepData[itemId] = math.max(stepData[itemId] or 0, count or 0)
	progress.stepData = stepData

	local done = true
	for needItem, needCount in pairs(step.needs) do
		if (stepData[needItem] or 0) < needCount then
			done = false
			break
		end
	end

	if done then
		if not progress.stepReady then
			progress.stepReady = true
			fireStatus(userId, "Tutorial.Step.Updated")
		end
	else
		fireStatus(userId, "Tutorial.Step.Updated")
	end
end

local function handleItemAnyStep(userId, progress, step, itemId, count)
	local matched = false
	for _, candidate in ipairs(step.targets or {}) do
		if candidate == itemId then
			matched = true
			break
		end
	end
	if not matched then
		return
	end

	local stepData = progress.stepData or {}
	stepData.count = (stepData.count or 0) + (count or 0)
	progress.stepData = stepData

	if (stepData.count or 0) >= (step.count or 1) then
		if not progress.stepReady then
			progress.stepReady = true
			fireStatus(userId, "Tutorial.Step.Updated")
		end
	else
		fireStatus(userId, "Tutorial.Step.Updated")
	end
end

local function markReady(userId, progress)
	if progress.stepReady then
		return
	end
	progress.stepReady = true
	fireStatus(userId, "Tutorial.Step.Updated")
end

local function updateByEvent(userId, eventKind, target, count)
	local progress = getOrCreateProgress(userId)
	if not progress or not progress.active or progress.completed then
		return
	end

	local step = getCurrentStep(progress)
	if not step then
		return
	end

	if step.kind == "MULTI_ITEM" and eventKind == "ITEM" then
		handleMultiItemStep(userId, progress, step, target, count)
		return
	end

	if step.kind == "ITEM_ANY" and eventKind == "ITEM" then
		handleItemAnyStep(userId, progress, step, target, count)
		return
	end

	if step.kind == "RECIPE" and eventKind == "RECIPE" and step.target == target then
		markReady(userId, progress)
		return
	end

	if step.kind == "BUILD" and eventKind == "BUILD" and step.target == target then
		markReady(userId, progress)
		return
	end

	if step.kind == "BUILD_AND_RECIPE" then
		local stepData = progress.stepData or {}
		if eventKind == "BUILD" and step.buildTarget == target then
			stepData.buildDone = true
		elseif eventKind == "RECIPE" and step.recipeTarget == target then
			stepData.recipeDone = true
		end
		progress.stepData = stepData

		if stepData.buildDone == true and stepData.recipeDone == true then
			markReady(userId, progress)
		else
			fireStatus(userId, "Tutorial.Step.Updated")
		end
		return
	end

	if step.kind == "KILL" and eventKind == "KILL" and step.target == target then
		markReady(userId, progress)
		return
	end
end

function TutorialQuestService.onItemAdded(userId, itemId, count)
	updateByEvent(userId, "ITEM", itemId, count)
end

function TutorialQuestService.onCrafted(userId, recipeId)
	updateByEvent(userId, "RECIPE", recipeId, 1)
end

function TutorialQuestService.onBuilt(userId, facilityId)
	updateByEvent(userId, "BUILD", facilityId, 1)
end

function TutorialQuestService.onKilled(userId, creatureId)
	updateByEvent(userId, "KILL", creatureId, 1)
end

function TutorialQuestService.onHarvest(_userId, _nodeType)
	-- 현재 튜토리얼은 실제 획득 아이템 기반으로 진행 처리.
end

local function handleGetStatus(player, _payload)
	waitForProgress(player.UserId, 6)
	return {
		success = true,
		data = serializeStatus(player.UserId),
	}
end

local function handleStepComplete(player, _payload)
	local progress = waitForProgress(player.UserId, 6)
	if not progress then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NOT_FOUND,
		}
	end

	if progress.completed then
		return {
			success = true,
			data = serializeStatus(player.UserId),
		}
	end

	if not progress.stepReady then
		return {
			success = false,
			errorCode = Enums.ErrorCode.BAD_REQUEST,
		}
	end

	local grantedReward = completeStep(player.UserId)
	local latest = serializeStatus(player.UserId)
	latest.grantedReward = grantedReward
	return {
		success = true,
		data = latest,
	}
end

local function handleAdminReset(player, _payload)
	if not isAdminUser(player.UserId) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NO_PERMISSION,
		}
	end

	local state = SaveService and SaveService.getPlayerState(player.UserId)
	if type(state) ~= "table" then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NOT_FOUND,
		}
	end

	state.tutorialQuest = makeFreshProgress()
	state.tutorialQuest.assigned = true
	state.tutorialQuest.assignedAt = os.time()
	fireStatus(player.UserId, "Tutorial.Step.Updated")

	return {
		success = true,
		data = serializeStatus(player.UserId),
	}
end

local function handleAdminSetStep(player, payload)
	if not isAdminUser(player.UserId) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NO_PERMISSION,
		}
	end

	local stepIndex = payload and payload.stepIndex
	if type(stepIndex) ~= "number" then
		return {
			success = false,
			errorCode = Enums.ErrorCode.BAD_REQUEST,
		}
	end

	stepIndex = math.floor(stepIndex)
	if stepIndex < 1 or stepIndex > (#STEPS + 1) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.OUT_OF_RANGE,
		}
	end

	local state = SaveService and SaveService.getPlayerState(player.UserId)
	if type(state) ~= "table" then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NOT_FOUND,
		}
	end

	state.tutorialQuest = state.tutorialQuest or makeFreshProgress()
	state.tutorialQuest.version = VERSION
	state.tutorialQuest.stepIndex = stepIndex
	state.tutorialQuest.stepData = {}
	state.tutorialQuest.completed = stepIndex > #STEPS
	state.tutorialQuest.active = not state.tutorialQuest.completed
	state.tutorialQuest.stepReady = false
	state.tutorialQuest.assigned = true
	state.tutorialQuest.assignedAt = os.time()
	state.tutorialQuest.rewardClaimed = state.tutorialQuest.completed

	if state.tutorialQuest.completed then
		fireStatus(player.UserId, "Tutorial.Completed")
	else
		fireStatus(player.UserId, "Tutorial.Step.Updated")
	end

	return {
		success = true,
		data = serializeStatus(player.UserId),
	}
end

function TutorialQuestService.GetHandlers()
	return {
		["Tutorial.GetStatus.Request"] = handleGetStatus,
		["Tutorial.Step.Complete.Request"] = handleStepComplete,
		["Tutorial.Admin.Reset.Request"] = handleAdminReset,
		["Tutorial.Admin.SetStep.Request"] = handleAdminSetStep,
	}
end

function TutorialQuestService.SetRewardDependencies(_PlayerStatService, _InventoryService, _NPCShopService)
	PlayerStatService = _PlayerStatService or PlayerStatService
	InventoryService = _InventoryService or InventoryService
	NPCShopService = _NPCShopService or NPCShopService
end

function TutorialQuestService.Init(_NetController, _SaveService, _PlayerStatService, _InventoryService, _NPCShopService)
	if initialized then
		warn("[TutorialQuestService] Already initialized")
		return
	end

	NetController = _NetController
	SaveService = _SaveService
	PlayerStatService = _PlayerStatService
	InventoryService = _InventoryService
	NPCShopService = _NPCShopService

	local function scheduleInitialPush(player)
		local userId = player.UserId
		task.spawn(function()
			local progress = waitForProgress(userId, PROGRESS_WAIT_TIMEOUT)
			if isAdminUser(userId) then
				local state = SaveService and SaveService.getPlayerState(userId)
				if type(state) == "table" then
					state.tutorialQuest = makeFreshProgress()
					state.tutorialQuest.assigned = true
					state.tutorialQuest.assignedAt = os.time()
					progress = state.tutorialQuest
				end
			end

			if progress and progress.assigned ~= true then
				progress.assigned = true
				progress.assignedAt = os.time()
				progress.stepData = {}
				progress.stepReady = false
			end

			if player.Parent and progress and progress.active and not progress.completed then
				fireStatus(userId, "Tutorial.Step.Updated")
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		scheduleInitialPush(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		scheduleInitialPush(player)
	end

	initialized = true
	print("[TutorialQuestService] Initialized")
end

return TutorialQuestService
