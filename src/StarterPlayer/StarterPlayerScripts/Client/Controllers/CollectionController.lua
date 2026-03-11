-- CollectionController.lua
-- 생존 도감(DNA) 데이터 관리 (Phase 11+)
-- PlayerStatService에서 가져온 도감 정보를 클라이언트 UI에 제공

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)
local CreatureData = require(ReplicatedStorage.Data.CreatureData)

local CollectionController = {}
local initialized = false

local localDnaData = {
	COMPY = 0,
}

local onDnaUpdatedCallbacks = {}

--========================================
-- Public API
--========================================

function CollectionController.getDnaCount(creatureId: string): number
	if creatureId == "COMPY" then
		return localDnaData.COMPY or 0
	end
	return 0
end

-- 전체 동물 리스트 반환 (분류별 필터링을 위함)
function CollectionController.getCreatureList()
	return CreatureData
end

function CollectionController.getCreatureData(creatureId: string)
	for _, data in ipairs(CreatureData) do
		if data.id == creatureId then
			return data
		end
	end
	return nil
end

function CollectionController.updateLocalDna(statsData)
	if not statsData then return end
	
	local changed = false
	if statsData.dnaCompy and localDnaData.COMPY ~= statsData.dnaCompy then
		localDnaData.COMPY = statsData.dnaCompy
		changed = true
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
	
	initialized = true
	print("[CollectionController] Initialized")
end

return CollectionController
