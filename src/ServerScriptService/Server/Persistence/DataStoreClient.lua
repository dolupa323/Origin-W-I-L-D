-- DataStoreClient.lua
-- DataStore 래퍼 (pcall + retry)

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataStoreClient = {}

--========================================
-- Configuration
--========================================
local RETRY_COUNT = 3
local RETRY_DELAY = 1

-- DataStore 인스턴스 (스튜디오에서는 nil)
local mainStore = nil
local isStudio = RunService:IsStudio()

-- 스튜디오 모킹 데이터 (테스트용)
local mockData = {}

--========================================
-- Key Rules
--========================================
DataStoreClient.Keys = {
	PLAYER_PREFIX = "PLAYER_",
	WORLD_MAIN = "WORLD_MAIN",
}

--- 플레이어 키 생성
function DataStoreClient.GetPlayerKey(userId: number): string
	return DataStoreClient.Keys.PLAYER_PREFIX .. tostring(userId)
end

--========================================
-- Internal Functions
--========================================

--- pcall + retry 래퍼
local function withRetry(operation: () -> any, operationName: string): (boolean, any)
	for attempt = 1, RETRY_COUNT do
		local success, result = pcall(operation)
		
		if success then
			return true, result
		end
		
		warn(string.format("[DataStoreClient] %s failed (attempt %d/%d): %s", 
			operationName, attempt, RETRY_COUNT, tostring(result)))
		
		if attempt < RETRY_COUNT then
			task.wait(RETRY_DELAY)
		end
	end
	
	return false, "MAX_RETRIES_EXCEEDED"
end

--========================================
-- Public API
--========================================

--- 데이터 읽기
--- @param key string 키
--- @return boolean, any (success, data or error)
function DataStoreClient.get(key: string): (boolean, any)
	if isStudio and not mainStore then
		-- 스튜디오 모킹
		local data = mockData[key]
		print(string.format("[DataStoreClient] GET (mock) %s: %s", key, data and "found" or "nil"))
		return true, data
	end
	
	if not mainStore then
		return false, "DATASTORE_NOT_INITIALIZED"
	end
	
	return withRetry(function()
		return mainStore:GetAsync(key)
	end, "GET " .. key)
end

--- 데이터 쓰기
--- @param key string 키
--- @param value any 값
--- @return boolean, string? (success, error)
function DataStoreClient.set(key: string, value: any): (boolean, string?)
	if isStudio and not mainStore then
		-- 스튜디오 모킹
		mockData[key] = value
		print(string.format("[DataStoreClient] SET (mock) %s", key))
		return true, nil
	end
	
	if not mainStore then
		return false, "DATASTORE_NOT_INITIALIZED"
	end
	
	return withRetry(function()
		mainStore:SetAsync(key, value)
		return nil
	end, "SET " .. key)
end

--- 데이터 업데이트 (원자적)
--- @param key string 키
--- @param updateFn function 업데이트 함수 (oldValue) -> newValue
--- @return boolean, any (success, newValue or error)
function DataStoreClient.update(key: string, updateFn: (any) -> any): (boolean, any)
	if isStudio and not mainStore then
		-- 스튜디오 모킹
		local oldValue = mockData[key]
		local newValue = updateFn(oldValue)
		mockData[key] = newValue
		print(string.format("[DataStoreClient] UPDATE (mock) %s", key))
		return true, newValue
	end
	
	if not mainStore then
		return false, "DATASTORE_NOT_INITIALIZED"
	end
	
	return withRetry(function()
		return mainStore:UpdateAsync(key, updateFn)
	end, "UPDATE " .. key)
end

--- 데이터 삭제
--- @param key string 키
--- @return boolean, string? (success, error)
function DataStoreClient.remove(key: string): (boolean, string?)
	if isStudio and not mainStore then
		mockData[key] = nil
		print(string.format("[DataStoreClient] REMOVE (mock) %s", key))
		return true, nil
	end
	
	if not mainStore then
		return false, "DATASTORE_NOT_INITIALIZED"
	end
	
	return withRetry(function()
		mainStore:RemoveAsync(key)
		return nil
	end, "REMOVE " .. key)
end

--========================================
-- Initialization
--========================================

function DataStoreClient.Init()
	-- 스튜디오에서 API 서비스 접근 활성화 필요
	local success, store = pcall(function()
		return DataStoreService:GetDataStore("DinoTribeSurvival_Main")
	end)
	
	if success then
		mainStore = store
		print("[DataStoreClient] Initialized with DataStore")
	else
		warn("[DataStoreClient] DataStore not available, using mock:", store)
		print("[DataStoreClient] Initialized with mock data (Studio mode)")
	end
end

return DataStoreClient
