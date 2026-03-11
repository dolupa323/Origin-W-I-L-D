-- DurabilityService.lua
-- 아이템 내구도 관리 서비스 (Phase 2-4)
-- 내구도 감소 및 파괴 담당 (수리 불가 반영)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local DurabilityService = {}

-- Dependencies
local NetController
local InventoryService
local DataService
local Balance

--========================================
-- Public API
--========================================

function DurabilityService.Init(_NetController, _InventoryService, _DataService, _BuildService, _Balance)
	NetController = _NetController
	InventoryService = _InventoryService
	DataService = _DataService
	Balance = _Balance
	
	print("[DurabilityService] Initialized (No-Repair Mode)")
	
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
	
	-- InventoryService에 위임 (내구도 0 시 InventoryService에서 파괴 처리됨)
	local success, errorCode, current = InventoryService.decreaseDurability(userId, slot, amount)
	
	if not success then
		if errorCode ~= Enums.ErrorCode.INVALID_ITEM then
			warn(string.format("[DurabilityService] Failed to reduce durability for player %d slot %d: %s", 
				userId, slot, tostring(errorCode)))
		end
		return false
	end
	
	return true
end

--========================================
-- Network Handlers
--========================================

function DurabilityService.GetHandlers()
	return {
		-- 수리 요청은 이제 무시하거나 실패 응답 반환 (전면 비활성화)
		["Durability.Repair.Request"] = function(player, payload)
			return { success = false, errorCode = Enums.ErrorCode.NOT_SUPPORTED }
		end,
	}
end

return DurabilityService
