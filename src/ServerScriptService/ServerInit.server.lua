-- ServerInit.server.lua
-- 서버 초기화 스크립트

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local Services = Server:WaitForChild("Services")

local PhysicsService = game:GetService("PhysicsService")

--========================================
-- Collision Groups 초기화 (성능 최적화)
--========================================
local function initCollisionGroups()
	-- 그룹 생성
	local groups = {"Players", "Creatures", "Structures", "Resources"}
	for _, group in ipairs(groups) do
		pcall(function() PhysicsService:RegisterCollisionGroup(group) end)
	end
	
	-- 크리처끼리는 충돌하지 않도록 설정 (Physics 부하 절감)
	PhysicsService:CollisionGroupSetCollidable("Creatures", "Creatures", false)
	
	print("[ServerInit] Collision groups initialized (Creatures vs Creatures = false)")
end

initCollisionGroups()

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

-- InventoryService (Init은 나중에 수행)
local InventoryService = require(Services.InventoryService)

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

-- StaminaService 초기화 (Phase 10: 스프린트/구르기) - PlayerStatService 연동을 위해 일찍 초기화
local StaminaService = require(Services.StaminaService)
StaminaService.Init(NetController)

-- PlayerStatService 초기화 (Phase 6) - 다른 서비스에서 XP 보상을 위해 일찍 초기화
local PlayerStatService = require(Services.PlayerStatService)
PlayerStatService.Init(NetController, SaveService, DataService, StaminaService)

-- EquipService 초기화
local EquipService = require(Services.EquipService)
EquipService.Init(DataService)

-- InventoryService 초기화 (SaveService, PlayerStatService, EquipService 주입)
InventoryService.Init(NetController, DataService, SaveService, PlayerStatService, EquipService)

-- PlayerStatService 핸들러 등록
for command, handler in pairs(PlayerStatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- TechService 초기화 (Phase 6) - 제작/건설 잠금 체크를 위해 일찍 초기화
local TechService = require(Services.TechService)
TechService.Init(NetController, DataService, PlayerStatService, SaveService)

-- TechService 핸들러 등록
for command, handler in pairs(TechService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- StorageService 초기화
local StorageService = require(Services.StorageService)
StorageService.Init(NetController, SaveService, InventoryService)

-- StorageService 핸들러 등록
for command, handler in pairs(StorageService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- BuildService 초기화 (+ TechService, PlayerStatService 추가)
local BuildService = require(Services.BuildService)
BuildService.Init(NetController, DataService, InventoryService, SaveService, TechService, PlayerStatService)

-- BuildService 핸들러 등록
for command, handler in pairs(BuildService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CraftingService 초기화 (+ TechService, PlayerStatService 추가)
local CraftingService = require(Services.CraftingService)
CraftingService.Init(NetController, DataService, InventoryService, BuildService, RecipeService, TechService, PlayerStatService)

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

-- BuildService에 FacilityService 주입 (양방향 연동)
BuildService.SetFacilityService(FacilityService)

-- DebuffService 초기화 (Phase 4-4) - CreatureService보다 먼저 초기화
local DebuffService = require(Services.DebuffService)
DebuffService.Init(NetController, TimeService)

-- DebuffService 핸들러 등록
for command, handler in pairs(DebuffService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CreatureService 초기화 (+ PlayerStatService 추가)
local CreatureService = require(Services.CreatureService)
CreatureService.Init(NetController, DataService, WorldDropService, DebuffService, PlayerStatService)

-- CreatureService 핸들러 등록
for command, handler in pairs(CreatureService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CombatService 초기화 (Phase 3-3, + DebuffService 연동)
local CombatService = require(Services.CombatService)
CombatService.Init(NetController, DataService, CreatureService, InventoryService, DurabilityService, DebuffService, WorldDropService, PlayerStatService)

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

-- PalboxService 초기화 (Phase 5-3) - CaptureService보다 먼저
local PalboxService = require(Services.PalboxService)
PalboxService.Init(NetController, DataService, SaveService)

-- PalboxService 핸들러 등록
for command, handler in pairs(PalboxService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- Phase 5-5: FacilityService에 PalboxService 주입 (팰 작업 배치 연동)
FacilityService.SetPalboxService(PalboxService)

-- CaptureService 초기화 (+ PlayerStatService 추가)
local CaptureService = require(Services.CaptureService)
CaptureService.Init(NetController, DataService, CreatureService, InventoryService, PalboxService, PlayerStatService)

-- CaptureService 핸들러 등록
for command, handler in pairs(CaptureService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- PartyService 초기화 (Phase 5-4)
local PartyService = require(Services.PartyService)
PartyService.Init(NetController, PalboxService, CreatureService)

-- PartyService 핸들러 등록
for command, handler in pairs(PartyService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- HarvestService 초기화 (Phase 7-1)
local HarvestService = require(Services.HarvestService)
HarvestService.Init(NetController, DataService, InventoryService, PlayerStatService, DurabilityService, WorldDropService)

-- HarvestService 핸들러 등록
for command, handler in pairs(HarvestService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- BaseClaimService 초기화 (Phase 7-2)
local BaseClaimService = require(Services.BaseClaimService)
BaseClaimService.Init(NetController, SaveService, BuildService)

-- BuildService에 BaseClaimService 주입 (첫 건물 설치 시 베이스 자동 생성용)
BuildService.SetBaseClaimService(BaseClaimService)

-- BaseClaimService 핸들러 등록
for command, handler in pairs(BaseClaimService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- AutoHarvestService 초기화 (Phase 7-3)
local AutoHarvestService = require(Services.AutoHarvestService)
AutoHarvestService.Init(HarvestService, FacilityService, BaseClaimService, PalboxService, DataService)

-- AutoDepositService 초기화 (Phase 7-4)
local AutoDepositService = require(Services.AutoDepositService)
AutoDepositService.Init(FacilityService, StorageService, BaseClaimService, BuildService, DataService)

-- (Quest 시스템 삭제됨)

-- NPCShopService 초기화 (Phase 9)
local NPCShopService = require(Services.NPCShopService)
NPCShopService.Init(NetController, DataService, InventoryService, TimeService)

-- NPCShopService 핸들러 등록
for command, handler in pairs(NPCShopService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- StaminaService 핸들러 등록 (이미 초기화됨)
for command, handler in pairs(StaminaService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CombatService에 StaminaService 연동 (무적 프레임 체크용)
CombatService.SetStaminaService(StaminaService)

-- CharacterSetupService 초기화 (선사시대 캐릭터 스타일)
local CharacterSetupService = require(Services.CharacterSetupService)
CharacterSetupService.Init()

print("[ServerInit] Server initialized (Phase 10)") -- 최종 완료 로그
