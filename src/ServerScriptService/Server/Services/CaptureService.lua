-- CaptureService.lua
-- 포획 시도 → 성공 시 박스 아이템 지급 + 크리처 제거
-- 박스 아이템 사용(길들이기)는 InventoryService.handleUse에서 처리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local SkillTreeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("SkillTreeData"))
local CreatureData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("CreatureData"))
local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))

local CaptureService = {}

-- Dependencies (Init에서 주입)
local NetController
local CreatureService
local InventoryService
local SkillService
local PlayerStatService

--========================================
-- 포획 확률 계산
--========================================

local function calcCaptureRate(creatureId: string, tamingBonus: number): number
	-- [DEV] 포획 100% (개발 편의성)
	return 1.0
end

--========================================
-- 박스 아이템 ID 매핑 (ItemData에서 자동 생성)
--========================================
local CREATURE_TO_BOX = {}
for _, item in ipairs(ItemData) do
	if item.type == "CAPTURE_BOX" and item.creatureId then
		CREATURE_TO_BOX[item.creatureId] = item.id
	end
end

--========================================
-- Handler: Capture.Attempt.Request
--========================================
local function handleCaptureAttempt(player: Player, payload: any)
	local userId = player.UserId
	local targetId = payload and payload.targetId

	if not targetId then
		return { success = false, errorCode = "INVALID_TARGET" }
	end

	-- 1. 크리처 존재 + 쓰러짐 상태 확인
	local creature = CreatureService.getCreatureRuntime(targetId)
	if not creature then
		return { success = false, errorCode = "CREATURE_NOT_FOUND" }
	end

	if creature.state ~= "DEAD" or not creature._hasCollapsed then
		return { success = false, errorCode = "NOT_COLLAPSED" }
	end

	-- IsDead(자연사)된 크리처는 포획 불가
	if creature.model and creature.model:GetAttribute("IsDead") then
		return { success = false, errorCode = "ALREADY_DEAD" }
	end

	-- 이미 포획 시도된 크리처는 재시도 불가
	if creature.model and creature.model:GetAttribute("CaptureAttempted") then
		return { success = false, errorCode = "ALREADY_ATTEMPTED" }
	end

	local creatureId = creature.creatureId

	-- 2. 거리 확인
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or not creature.rootPart then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end
	local captureRange = Balance and Balance.CAPTURE_RANGE or 30
	local dist = (hrp.Position - creature.rootPart.Position).Magnitude
	if dist > captureRange + 5 then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end

	-- 3. 스킬 해금 확인
	local unlockedMap = SkillService.getUnlockedSkills(userId)
	local learnedList = {}
	for skillId, _ in pairs(unlockedMap) do
		table.insert(learnedList, skillId)
	end

	local unlockedCreatures = SkillTreeData.GetUnlockedCreatures(learnedList)
	if not unlockedCreatures[creatureId] then
		NetController.FireClient(player, "Notify.Message", {
			text = "이 크리처를 포획할 수 있는 스킬이 없습니다.",
		})
		return { success = false, errorCode = "SKILL_LOCKED" }
	end

	-- 4. 박스 아이템 존재 확인
	local boxItemId = CREATURE_TO_BOX[creatureId]
	if not boxItemId then
		return { success = false, errorCode = "NO_BOX_ITEM" }
	end

	-- 5. 포획 확률 계산 + 굴림
	local tamingBonus = SkillTreeData.GetTamingRateBonus(learnedList)
	local captureRate = calcCaptureRate(creatureId, tamingBonus)
	local roll = math.random()
	local captured = roll <= captureRate

	if creature.model then
		creature.model:SetAttribute("CaptureAttempted", true)
	end

	if not captured then
		CreatureService.killCreature(targetId)
		local creatureName = creature.data and creature.data.name or creatureId
		NetController.FireClient(player, "Notify.Message", {
			text = creatureName .. " 포획에 실패했습니다... (확률: " .. math.floor(captureRate * 100) .. "%)",
		})
		return { success = false, captureRate = captureRate }
	end

	-- 6. 포획 성공 → 박스 아이템 지급 (레벨 및 스탯 전승)
	local model = creature.model
	local attributes = {
		level = creature.level or (model and model:GetAttribute("Level")) or 1,
		baseMaxHealth = creature.maxHealth or (model and model:GetAttribute("MaxHealth")) or (creature.data and creature.data.baseHealth) or 100,
		baseDamage = creature.damage or (creature.data and creature.data.damage) or 10,
		currentHealth = creature.currentHealth or (model and model:GetAttribute("CurrentHealth")),
	}
	
	local added, remaining = InventoryService.addItem(userId, boxItemId, 1, nil, attributes)
	if added == 0 then
		NetController.FireClient(player, "Notify.Message", {
			text = "인벤토리가 가득 차서 포획할 수 없습니다!",
		})
		return { success = false, errorCode = "INVENTORY_FULL" }
	end

	-- 7. 크리처 월드에서 제거
	CreatureService.removeCreature(targetId)

	-- 8. 성공 알림
	local creatureName = creature.data and creature.data.name or creatureId
	NetController.FireClient(player, "Notify.Message", {
		text = creatureName .. " 포획 성공! 포획 상자가 인벤토리에 추가되었습니다.",
	})

	if PlayerStatService then
		PlayerStatService.grantActionXP(userId, Balance.XP_CAPTURE_PAL or 0, {
			source = Enums.XPSource.CAPTURE_PAL,
			actionKey = "CAPTURE:" .. tostring(creatureId),
		})
	end

	print(string.format("[CaptureService] Player %d captured %s (rate: %.0f%%)", userId, creatureId, captureRate * 100))

	return { success = true, captureRate = captureRate }
end

--========================================
-- Public API
--========================================

function CaptureService.GetHandlers()
	return {
		["Capture.Attempt.Request"] = handleCaptureAttempt,
	}
end

function CaptureService.Init(_NetController, _CreatureService, _InventoryService, _SkillService, _PlayerStatService)
	NetController = _NetController
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	SkillService = _SkillService
	PlayerStatService = _PlayerStatService

	print("[CaptureService] Initialized")
end

return CaptureService
