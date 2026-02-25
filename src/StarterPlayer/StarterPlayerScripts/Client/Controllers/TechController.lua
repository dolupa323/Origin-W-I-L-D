-- TechController.lua
-- 클라이언트 기술 컨트롤러
-- 서버 Tech 서비스와 연동하여 해금 상태 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local TechController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 상태 캐시
local unlockedTech = {} -- { [techId] = true }
local techTreeData = {}  -- { [techId] = techData }
local techPoints = 0

-- 이벤트 리스너
local listeners = {
	techUpdated = {},
	techUnlocked = {},
}

--========================================
-- Public API: Cache Access
--========================================

function TechController.getUnlockedTech()
	return unlockedTech
end

function TechController.getTechTree()
	return techTreeData
end

function TechController.getTechPoints()
	return techPoints
end

function TechController.isUnlocked(techId: string): boolean
	return unlockedTech[techId] == true
end

function TechController.isRecipeUnlocked(recipeId: string): boolean
	-- 모든 해금된 기술을 순회하여 해당 레시피가 포함되어 있는지 확인
	for techId, _ in pairs(unlockedTech) do
		local tech = techTreeData[techId]
		if tech and tech.unlocks and tech.unlocks.recipes then
			for _, rid in ipairs(tech.unlocks.recipes) do
				if rid == recipeId then return true end
			end
		end
	end
	return false
end

function TechController.isFacilityUnlocked(facilityId: string): boolean
	for techId, _ in pairs(unlockedTech) do
		local tech = techTreeData[techId]
		if tech and tech.unlocks and tech.unlocks.facilities then
			for _, fid in ipairs(tech.unlocks.facilities) do
				if fid == facilityId then return true end
			end
		end
	end
	return false
end

--========================================
-- Public API: Server Requests
--========================================

--- 기술 목록 및 포인트 요청
function TechController.requestTechInfo(callback: ((boolean) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Tech.List.Request", {})
		if ok and data then
			unlockedTech = data.unlocked or {}
			techPoints = data.techPoints or 0
			for _, cb in ipairs(listeners.techUpdated) do pcall(cb) end
		end
		if callback then callback(ok) end
	end)
end

--- 전체 기술 트리 데이터 요청
function TechController.requestTechTree(callback: ((boolean) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Tech.Tree.Request", {})
		if ok and data and data.tree then
			techTreeData = data.tree
		end
		if callback then callback(ok) end
	end)
end

--- 기술 해금 요청
function TechController.requestUnlock(techId: string, callback: ((boolean, string?) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Tech.Unlock.Request", { techId = techId })
		if ok then
			-- 즉시 로컬 캐시 업데이트 가능성 (서버 이벤트가 어차피 올 거지만)
			TechController.requestTechInfo()
		end
		if callback then
			callback(ok, not ok and tostring(data.errorCode or "UNKNOWN_ERROR") or nil)
		end
	end)
end

--========================================
-- Event Listener API
--========================================

function TechController.onTechUpdated(callback: () -> ())
	table.insert(listeners.techUpdated, callback)
end

function TechController.onTechUnlocked(callback: (any) -> ())
	table.insert(listeners.techUnlocked, callback)
end

--========================================
-- Event Handlers
--========================================

local function onTechUnlockedSvr(data)
	if not data then return end
	
	-- 토스트 알림 등을 위해 리스너 호출
	for _, cb in ipairs(listeners.techUnlocked) do
		pcall(cb, data)
	end
	
	-- 전체 정보 갱신
	TechController.requestTechInfo()
end

--========================================
-- Initialization
--========================================

function TechController.Init()
	if initialized then return end
	
	NetClient.On("Tech.Unlocked", onTechUnlockedSvr)
	
	-- 초기 데이터 로드
	TechController.requestTechTree()
	TechController.requestTechInfo()
	
	initialized = true
	print("[TechController] Initialized")
end

return TechController
