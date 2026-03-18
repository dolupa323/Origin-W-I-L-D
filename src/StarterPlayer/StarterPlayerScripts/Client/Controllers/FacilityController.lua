-- FacilityController.lua
-- 생산 시설(요리, 제련) 클라이언트 컨트롤러

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)
local InventoryController = require(script.Parent.Parent.Controllers.InventoryController)

local FacilityController = {}

--========================================
-- Private State
--========================================
local initialized = false
local currentStructureId = nil
local currentFacilityData = nil -- 서버에서 받은 런타임 데이터

--========================================
-- Public API
--========================================

--- 시설 UI 열기
function FacilityController.openFacility(structureId: string)
	local success, data = NetClient.Request("Facility.GetInfo.Request", {
		structureId = structureId
	})
	
	if success and data then
		currentStructureId = structureId
		currentFacilityData = data
		
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.openFacility(structureId, data)
	else
		local UIManager = require(script.Parent.Parent.UIManager)
		if tostring(data) == "NO_PERMISSION" then
			UIManager.notify("토템 보호가 활성화된 시설입니다. 유지비 만료 후 약탈 가능합니다.", Color3.fromRGB(255, 120, 120))
		else
			UIManager.notify("시설 접근 실패: " .. tostring(data), Color3.fromRGB(255, 120, 120))
		end
		warn("[FacilityController] Failed to get facility info:", structureId, data)
	end
end

--- 시설 UI 닫기
function FacilityController.closeFacility()
	currentStructureId = nil
	currentFacilityData = nil
end

--- 연료 추가
function FacilityController.addFuel(invSlot: number)
	if not currentStructureId then return end
	
	local success, data = NetClient.Request("Facility.AddFuel.Request", {
		structureId = currentStructureId,
		invSlot = invSlot
	})
	
	if success then
		-- 데이터 로컬 갱신 (StateChanged 이벤트로도 오지만 즉각 피드백)
		currentFacilityData.currentFuel = data.currentFuel
		currentFacilityData.state = data.state
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.refreshFacility()
	end
end

--- 연료 회수
function FacilityController.removeFuel()
	if not currentStructureId then return end
	local success, data = NetClient.Request("Facility.RemoveFuel.Request", {
		structureId = currentStructureId
	})
	if success then
		FacilityController.refreshInfo()
	end
end

--- 재료 추가
function FacilityController.addInput(invSlot: number, count: number?)
	if not currentStructureId then return end
	
	local success, data = NetClient.Request("Facility.AddInput.Request", {
		structureId = currentStructureId,
		invSlot = invSlot,
		count = count
	})
	
	if success then
		currentFacilityData.inputSlot = data.inputSlot
		currentFacilityData.state = data.state
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.refreshFacility()
	end
end

--- 재료 회수
function FacilityController.removeInput()
	if not currentStructureId then return end
	local success, data = NetClient.Request("Facility.RemoveInput.Request", {
		structureId = currentStructureId
	})
	if success then
		FacilityController.refreshInfo()
	end
end

--- 결과물 수거
function FacilityController.collectOutput()
	if not currentStructureId then return end
	
	local success, data = NetClient.Request("Facility.CollectOutput.Request", {
		structureId = currentStructureId
	})
	
	if success then
		-- 데이터 갱신을 위해 정보 다시 요청하거나 이벤트를 기다림
		FacilityController.refreshInfo()
	end
end

--- 정보 강제 갱신
function FacilityController.refreshInfo()
	if not currentStructureId then return end
	
	local success, data = NetClient.Request("Facility.GetInfo.Request", {
		structureId = currentStructureId
	})
	
	if success and data then
		currentFacilityData = data
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.refreshFacility()
	end
end

--========================================
-- Event Handlers
--========================================

local function onFacilityStateChanged(data)
	if not currentStructureId or data.structureId ~= currentStructureId then return end
	
	-- 실시간 상태 동기화
	if data.state then currentFacilityData.state = data.state end
	if data.currentFuel then currentFacilityData.currentFuel = data.currentFuel end
	if data.inputSlot ~= nil then currentFacilityData.inputSlot = data.inputSlot end
	if data.fuelSlot ~= nil then currentFacilityData.fuelSlot = data.fuelSlot end
	if data.outputSlot ~= nil then currentFacilityData.outputSlot = data.outputSlot end
	if data.processProgress then currentFacilityData.processProgress = data.processProgress end
	if data.lastUpdateAt then currentFacilityData.lastUpdateAt = data.lastUpdateAt end
	
	local UIManager = require(script.Parent.Parent.UIManager)
	UIManager.refreshFacility()
end

local function onBuildChanged(data)
	if not currentStructureId or not data or data.id ~= currentStructureId then return end
	if not currentFacilityData then return end

	if data.changes and data.changes.health ~= nil then
		currentFacilityData.health = data.changes.health
		local UIManager = require(script.Parent.Parent.UIManager)
		if UIManager and UIManager.refreshFacility then
			UIManager.refreshFacility()
		end
	end
end

--========================================
-- Initialization
--========================================

function FacilityController.Init()
	if initialized then return end
	
	NetClient.On("Facility.StateChanged", onFacilityStateChanged)
	NetClient.On("Build.Changed", onBuildChanged)
	
	initialized = true
	print("[FacilityController] Initialized")
end

return FacilityController
