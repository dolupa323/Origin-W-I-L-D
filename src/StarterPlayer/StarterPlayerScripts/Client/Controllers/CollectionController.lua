-- CollectionController.lua
-- 생존 도감(DNA) 데이터 관리 (Phase 11+)
-- PlayerStatService에서 가져온 도감 정보를 클라이언트 UI에 제공

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

local CollectionController = {}
local initialized = false

local localDnaData = {}

-- CreatureData에서 전체 크리처 ID를 로드하여 초기값 설정
local CURRENT_GRASSLAND_CREATURES = {}
do
	local tbl = DataHelper.GetTable("CreatureData") or {}
	for _, data in pairs(tbl) do
		local cid = tostring(data.id or "")
		if cid ~= "" then
			localDnaData[cid] = 0
			CURRENT_GRASSLAND_CREATURES[cid] = true
		end
	end
end

local onDnaUpdatedCallbacks = {}
local onPetUpdatedCallbacks = {}

-- 펫 슬롯 상태
local petSlots = {}
local petMaxSlots = 1
local completedCreatures = {}

--========================================
-- Public API
--========================================

function CollectionController.getDnaCount(creatureId: string): number
	return localDnaData[tostring(creatureId or "")] or 0
end

-- 전체 동물 리스트 반환 (도감에 등록 가능한 모든 크리처)
function CollectionController.getCreatureList()
	local tbl = DataHelper.GetTable("CreatureData") or {}
	local list = {}
	for _, data in pairs(tbl) do
		table.insert(list, data)
	end
	table.sort(list, function(a, b)
		return tostring(a.id or "") < tostring(b.id or "")
	end)
	return list
end

function CollectionController.getCreatureData(creatureId: string)
	return DataHelper.GetData("CreatureData", creatureId)
end

function CollectionController.updateLocalDna(statsData)
	if not statsData then return end
	
	local changed = false
	if type(statsData.dnaData) == "table" then
		for cid, amount in pairs(statsData.dnaData) do
			local key = string.upper(tostring(cid))
			local value = tonumber(amount) or 0
			if localDnaData[key] ~= value then
				localDnaData[key] = value
				changed = true
			end
		end
	end

	if changed then
		for _, cb in ipairs(onDnaUpdatedCallbacks) do
			pcall(cb)
		end
	end
end

function CollectionController.onDnaUpdated(callback)
	table.insert(onDnaUpdatedCallbacks, callback)
end

--========================================
-- Pet API
--========================================

function CollectionController.getPetSlots()
	return petSlots
end

function CollectionController.getPetMaxSlots()
	return petMaxSlots
end

function CollectionController.getCompletedCreatures()
	return completedCreatures
end

function CollectionController.isCodexComplete(creatureId: string): boolean
	local cData = DataHelper.GetData("CreatureData", creatureId)
	if not cData then return false end
	local required = cData.dnaRequired or 5
	local current = localDnaData[string.upper(tostring(creatureId))] or 0
	return current >= required
end

function CollectionController.requestEquipPet(slotIndex: number, creatureId: string)
	local ok, result = NetClient.Request("Pet.Equip.Request", { slotIndex = slotIndex, creatureId = creatureId })
	return ok and result
end

function CollectionController.requestUnequipPet(slotIndex: number)
	local ok, result = NetClient.Request("Pet.Unequip.Request", { slotIndex = slotIndex })
	return ok and result
end

function CollectionController.requestPetSlots()
	local ok, result = NetClient.Request("Pet.Slots.Request", {})
	if ok and result and result.success and result.data then
		petSlots = result.data.slots or {}
		petMaxSlots = result.data.maxSlots or 1
		completedCreatures = result.data.completed or {}
	end
	return ok and result
end

function CollectionController.onPetUpdated(callback)
	table.insert(onPetUpdatedCallbacks, callback)
end

--========================================
-- Init
--========================================

function CollectionController.Init()
	if initialized then return end
	
	-- 서버로부터 С탯 업데이트 패킷을 받을 때마다 DNA 수치도 동기화 (UIManager나 여기서 갱신)
	NetClient.On("Player.Stats.Changed", function(data)
		if data then
			CollectionController.updateLocalDna(data)
		end
	end)
	
	-- 펫 슬롯 동기화 이벤트
	NetClient.On("Pet.Sync", function(data)
		if data then
			petSlots = data.slots or {}
			petMaxSlots = data.maxSlots or 1
			completedCreatures = data.completed or {}
			for _, cb in ipairs(onPetUpdatedCallbacks) do
				pcall(cb)
			end
		end
	end)
	
	initialized = true
	print("[CollectionController] Initialized")
end

return CollectionController
