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

-- RecipeService 초기화 (BuildService 등에서 참조하므로 미리 초기화)
local RecipeService = require(Services.RecipeService)
RecipeService.Init(DataService)

-- RecipeService 핸들러 등록
for command, handler in pairs(RecipeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

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

-- DurabilityService 초기화 (Phase 2-4)
local DurabilityService = require(Services.DurabilityService)
DurabilityService.Init(NetController, InventoryService)

-- DurabilityService 핸들러 등록
for command, handler in pairs(DurabilityService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- WorldDropService 초기화
local WorldDropService = require(Services.WorldDropService)
WorldDropService.Init(NetController, DataService, InventoryService, TimeService)

-- WorldDropService 핸들러 등록
for command, handler in pairs(WorldDropService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- Inventory.Drop.Request 핸들러 오버라이드 (월드 드롭 생성 연결)
local function handleInventoryDropWithWorldDrop(player, payload)
	local slot = payload.slot
	local count = payload.count  -- optional
	
	local success, errorCode, data = InventoryService.drop(player, slot, count)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	
	-- 인벤 드롭 성공 시 월드 드롭 생성
	local dropped = data.dropped
	if dropped then
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				-- 플레이어 앞 2스터드 위치에 드롭
				local dropPos = hrp.Position + hrp.CFrame.LookVector * 2 + Vector3.new(0, -1, 0)
				local spawnOk, spawnErr, spawnData = WorldDropService.spawnDrop(dropPos, dropped.itemId, dropped.count)
				
				if spawnOk then
					print(string.format("[ServerInit] Inventory.Drop -> WorldDrop: %s x%d at (%.1f,%.1f,%.1f)", 
						dropped.itemId, dropped.count, dropPos.X, dropPos.Y, dropPos.Z))
					data.worldDrop = spawnData
				else
					warn("[ServerInit] Failed to spawn world drop:", spawnErr)
				end
			end
		end
	end
	
	return { success = true, data = data }
end
NetController.RegisterHandler("Inventory.Drop.Request", handleInventoryDropWithWorldDrop)

-- StorageService 초기화
local StorageService = require(Services.StorageService)
StorageService.Init(NetController, SaveService, InventoryService)

-- StorageService 핸들러 등록
for command, handler in pairs(StorageService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- BuildService 초기화
local BuildService = require(Services.BuildService)
BuildService.Init(NetController, DataService, InventoryService, SaveService)

-- BuildService 핸들러 등록
for command, handler in pairs(BuildService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CraftingService 초기화
local CraftingService = require(Services.CraftingService)
CraftingService.Init(NetController, DataService, InventoryService, BuildService, RecipeService)

-- CraftingService 핸들러 등록
for command, handler in pairs(CraftingService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- FacilityService 초기화
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local FacilityService = require(Services.FacilityService)
FacilityService.Init(NetController, DataService, InventoryService, BuildService, Balance, RecipeService, WorldDropService)

-- FacilityService 핸들러 등록
for command, handler in pairs(FacilityService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- DebuffService 초기화 (Phase 4-4) - CreatureService보다 먼저 초기화
local DebuffService = require(Services.DebuffService)
DebuffService.Init(NetController, TimeService)

-- DebuffService 핸들러 등록
for command, handler in pairs(DebuffService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CreatureService 초기화 (Phase 3-1, + DebuffService 연동)
local CreatureService = require(Services.CreatureService)
CreatureService.Init(NetController, DataService, WorldDropService, DebuffService)

-- CreatureService 핸들러 등록
for command, handler in pairs(CreatureService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CombatService 초기화 (Phase 3-3, + DebuffService 연동)
local CombatService = require(Services.CombatService)
CombatService.Init(NetController, DataService, CreatureService, InventoryService, DurabilityService, DebuffService)

-- CombatService 핸들러 등록
for command, handler in pairs(CombatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- PlayerLifeService 초기화 (Phase 4-2)
local PlayerLifeService = require(Services.PlayerLifeService)
PlayerLifeService.Init(NetController, DataService, InventoryService, BuildService)

-- PlayerLifeService 핸들러 등록
for command, handler in pairs(PlayerLifeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

print("[ServerInit] Server initialized (Phase 4)") -- 최종 완료 로그
