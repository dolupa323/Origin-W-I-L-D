-- DurabilityService.lua
-- 아이템 내구도 관리 서비스 (Phase 2-4)
-- 내구도 감소 및 수리(Repair) 담당

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local DurabilityService = {}

-- Dependencies
local NetController
local InventoryService

--========================================
-- Public API
--========================================

function DurabilityService.Init(_NetController, _InventoryService)
	NetController = _NetController
	InventoryService = _InventoryService
	print("[DurabilityService] Initialized")
	
	-- 패시브 내구도 감소 루프 (예: 횃불)
	local Players = game:GetService("Players")
	local DataHelper = require(Shared.Util.DataHelper)
	
	task.spawn(function()
		while true do
			task.wait(1) -- 매 1초마다 동기화 검사
			for _, player in ipairs(Players:GetPlayers()) do
				local userId = player.UserId
				-- 장착 중인 아이템 가져오기
				local activeSlot = InventoryService.getActiveSlot and InventoryService.getActiveSlot(userId)
				if activeSlot then
					local slotData = InventoryService.getSlot and InventoryService.getSlot(userId, activeSlot)
					if slotData and slotData.itemId and slotData.durability then
						local itemData = DataHelper.GetData("ItemData", slotData.itemId)
						if itemData and itemData.passiveDurabilityDrain and itemData.passiveDurabilityDrain > 0 then
							-- 1초마다 정해진 량만큼 내구도 자동 감소
							DurabilityService.reduceDurability(player, activeSlot, itemData.passiveDurabilityDrain)
						end
					end
				end
			end
		end
	end)
end

--- 내구도 감소 요청 (채집, 공격 등에서 호출)
--- @param player Player
--- @param slot number 인벤토리 슬롯
--- @param amount number 감소량 (양수)
--- @return boolean success
function DurabilityService.reduceDurability(player: Player, slot: number, amount: number): boolean
	if not player or not slot or not amount then return false end
	if amount <= 0 then return false end -- 감소량은 양수여야 함
	
	local userId = player.UserId
	
	-- InventoryService에 위임
	local success, errorCode, current = InventoryService.decreaseDurability(userId, slot, amount)
	
	if not success then
		if errorCode ~= Enums.ErrorCode.INVALID_ITEM then
			warn(string.format("[DurabilityService] Failed to reduce durability for player %d slot %d: %s", 
				userId, slot, tostring(errorCode)))
		end
		return false
	end
	
	-- 0 이하 파괴 알림은 InventoryService가 이벤트를 보내므로 여기선 추가 처리 불필요
	-- 필요시 파괴 효과음 등을 위한 별도 패킷 전송 가능
	if current <= 0 then
		-- e.g. NetController.FireClient(player, "Effect.ItemBreak", { slot = slot })
	end
	
	return true
end

--========================================
-- Network Handlers
--========================================

function DurabilityService.GetHandlers()
	return {
		-- 추후 Repair 관련 핸들러 추가
	}
end

return DurabilityService
