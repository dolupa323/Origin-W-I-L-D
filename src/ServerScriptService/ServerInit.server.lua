-- ServerInit.server.lua
-- 서버 초기화 스크립트

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local Services = Server:WaitForChild("Services")

-- DataService 초기화 (가장 먼저 - 데이터 검증 실패 시 부팅 중단)
local DataService = require(Services.DataService)
DataService.Init()

-- NetController 초기화
local NetController = require(Controllers.NetController)
NetController.Init()

-- TimeService 초기화
local TimeService = require(Services.TimeService)
TimeService.Init(NetController)

-- TimeService 핸들러 등록
for command, handler in pairs(TimeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- SaveService 초기화
local SaveService = require(Services.SaveService)
SaveService.Init(NetController)

-- SaveService 핸들러 등록
for command, handler in pairs(SaveService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- InventoryService 초기화
local InventoryService = require(Services.InventoryService)
InventoryService.Init(NetController, DataService)

-- InventoryService 핸들러 등록
for command, handler in pairs(InventoryService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- WorldDropService 초기화
local WorldDropService = require(Services.WorldDropService)
WorldDropService.Init(NetController, DataService, InventoryService, TimeService)

-- WorldDropService 핸들러 등록
for command, handler in pairs(WorldDropService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- Studio 전용 디버그 테스트
local RunService = game:GetService("RunService")
if RunService:IsStudio() then
	task.defer(function()
		task.wait(2)  -- 서버 초기화 대기
		
		print("=== WorldDropService DoD Tests ===")
		
		-- Test A: Cap Test (1000개 스폰 → 400개 이하 유지)
		print("[Test A] Spawn 1000 drops...")
		WorldDropService.DebugSpawnMany("STONE", 10, 1000)
		print(string.format("[Test A] Result: dropCount = %d (expected <= 400)", WorldDropService.getDropCount()))
		
		-- Test B: Merge Test
		WorldDropService.clearAllDrops()
		print("[Test B] Merge test at same position...")
		WorldDropService.DebugMergeTest("STONE", 10, 5)
		print(string.format("[Test B] Result: dropCount = %d (expected 1 due to merge)", WorldDropService.getDropCount()))
		
		-- Test C: Despawn Timer (로그 확인용)
		WorldDropService.clearAllDrops()
		print("[Test C] Spawn STONE (600s) and STONE_PICKAXE (300s)...")
		local s1, _, d1 = WorldDropService.spawnDrop(Vector3.new(10, 5, 10), "STONE", 5)
		local s2, _, d2 = WorldDropService.spawnDrop(Vector3.new(20, 5, 20), "STONE_PICKAXE", 1)
		if d1 and d2 then
			local drop1 = WorldDropService.getDrop(d1.dropId)
			local drop2 = WorldDropService.getDrop(d2.dropId)
			if drop1 and drop2 then
				print(string.format("[Test C] STONE despawnAt: %.1f (now+600)", drop1.despawnAt - tick()))
				print(string.format("[Test C] STONE_PICKAXE despawnAt: %.1f (now+300)", drop2.despawnAt - tick()))
			end
		end
		
		print("=== WorldDropService DoD Tests Complete ===")
	end)
end

print("[ServerInit] Server initialized")
