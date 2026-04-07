-- ServerInit.server.lua
-- 서버 초기화 스크립트

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- [핵심] 캐릭터 자동 로드 비활성화
-- 데이터 로드 완료 후 수동으로 LoadCharacter 호출하여 정확한 위치에 스폰
Players.CharacterAutoLoads = false

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local Services = Server:WaitForChild("Services")

local PhysicsService = game:GetService("PhysicsService")

-- Balance: DurabilityService.Init 등에서 필요하므로 최상단에서 require
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

--========================================
-- Collision Groups 초기화 (성능 최적화)
--========================================
local function initCollisionGroups()
	-- 그룹 생성
	local groups = {"Players", "Creatures", "CombatCreatures", "Structures", "Resources"}
	for _, group in ipairs(groups) do
		pcall(function() PhysicsService:RegisterCollisionGroup(group) end)
	end
	
	-- 크리처끼리는 충돌하지 않도록 설정 (Physics 부하 절감)
	PhysicsService:CollisionGroupSetCollidable("Creatures", "Creatures", false)
	-- ★ 크리처 vs 플레이어: 충돌 OFF
	-- Humanoid 엔진이 HumanoidRootPart.CanCollide를 매 물리 프레임 true로 강제하기 때문에
	-- GetPropertyChangedSignal로 복원해도 해당 프레임의 충돌은 이미 발생함
	-- 대형 공룡 아래에서 전투 시 플레이어가 지형 아래로 밀리는 버그 방지
	-- 접촉 판정은 CombatService 거리 기반 체크로 처리
	PhysicsService:CollisionGroupSetCollidable("Creatures", "Players", false)
	-- ★ [FIX] 전투 중 크리처-플레이어 물리 충돌 비활성화
	-- Humanoid 엔진이 HumanoidRootPart.CanCollide를 매 프레임 강제 true로 설정하므로,
	-- CombatCreatures-Players 충돌이 true면 크리처 추격 시 플레이어가 물리 발사됨
	-- 전투 접촉 판정은 CombatService의 거리 기반 체크로 처리
	PhysicsService:CollisionGroupSetCollidable("CombatCreatures", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("CombatCreatures", "Creatures", false)
	PhysicsService:CollisionGroupSetCollidable("CombatCreatures", "CombatCreatures", false)
	
	print("[ServerInit] Collision groups initialized")
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

-- DurabilityService require + 핸들러 등록 (Init은 BuildService 초기화 후 수행)
local DurabilityService = require(Services.DurabilityService)

-- DurabilityService 핸들러 등록
for command, handler in pairs(DurabilityService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- WorldDropService register (Init called later after PlayerStatService)
local WorldDropService = require(Services.WorldDropService)

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
				local spawnOk, spawnErr, spawnData = WorldDropService.spawnDrop(dropPos, dropped.itemId, dropped.count, dropped.durability)
				
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

-- Inventory.DropByItemId.Request 핸들러 (동일 아이템 다중 슬롯 벌크 드랍)
local function handleInventoryDropByItemId(player, payload)
	local itemId = payload.itemId
	local count = payload.count
	
	if type(itemId) ~= "string" or itemId == "" then
		return { success = false, errorCode = "INVALID_ITEM" }
	end
	if type(count) ~= "number" or count < 1 then
		return { success = false, errorCode = "INVALID_COUNT" }
	end
	count = math.floor(count)
	
	-- removeItem으로 다중 슬롯에서 제거
	local removed = InventoryService.removeItem(player.UserId, itemId, count)
	
	if removed <= 0 then
		return { success = false, errorCode = "SLOT_EMPTY" }
	end
	
	-- 월드 드롭 생성
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dropPos = hrp.Position + hrp.CFrame.LookVector * 2 + Vector3.new(0, -1, 0)
			WorldDropService.spawnDrop(dropPos, itemId, removed)
			print(string.format("[ServerInit] DropByItemId -> WorldDrop: %s x%d", itemId, removed))
		end
	end
	
	return { success = true, data = { itemId = itemId, dropped = removed } }
end
NetController.RegisterHandler("Inventory.DropByItemId.Request", handleInventoryDropByItemId)

-- StaminaService 초기화 (Phase 10: 스프린트/구르기) - PlayerStatService 연동을 위해 일찍 초기화
local StaminaService = require(Services.StaminaService)
StaminaService.Init(NetController)

-- HungerService 초기화 (Phase 11: 생존/배고픔 로그 루프)
local HungerService = require(Services.HungerService)
HungerService.Init(NetController)

-- PlayerStatService 초기화 (Phase 6) - 다른 서비스에서 XP 보상을 위해 일찍 초기화
local PlayerStatService = require(Services.PlayerStatService)
PlayerStatService.Init(NetController, SaveService, DataService, StaminaService)

-- PlayerStatService 핸들러 등록
for command, handler in pairs(PlayerStatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- WorldDropService 최종 초기화 (PlayerStatService 의존성 주입)
WorldDropService.Init(NetController, DataService, InventoryService, TimeService, PlayerStatService)

-- TechService 초기화 (Phase 6) - 제작/건설 잠금 체크를 위해 일찍 초기화
local TechService = require(Services.TechService)
TechService.Init(NetController, DataService, PlayerStatService, SaveService, InventoryService)

-- TechService 핸들러 등록
for command, handler in pairs(TechService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- EquipService 초기화
local EquipService = require(Services.EquipService)
EquipService.Init(DataService, TechService)

-- InventoryService 초기화 (SaveService, PlayerStatService, EquipService 주입)
InventoryService.Init(NetController, DataService, SaveService, PlayerStatService, EquipService)

-- StorageService (Init moved after BaseClaimService)
local StorageService = require(Services.StorageService)

-- StorageService 핸들러 등록
for command, handler in pairs(StorageService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- FacilityService 초기화 (BuildService가 필요하므로 먼저)
local FacilityService = require(Services.FacilityService)
FacilityService.Init(NetController, DataService, InventoryService, nil, Balance, RecipeService, WorldDropService, TechService)

-- FacilityService 핸들러 등록
for command, handler in pairs(FacilityService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- BuildService 초기화 (+ TechService, PlayerStatService 추가, FacilityService 이제 주입 가능)
local BuildService = require(Services.BuildService)
BuildService.Init(NetController, DataService, InventoryService, SaveService, TechService, PlayerStatService)

-- BuildService에 FacilityService 주입 (양방향 연동)
-- [안정화] nil 체크 추가
if BuildService and BuildService.SetFacilityService and FacilityService then
	BuildService.SetFacilityService(FacilityService)
else
	warn("[ServerInit] BuildService/SetFacilityService or FacilityService not available")
end

if BuildService and BuildService.SetWorldDropService and WorldDropService then
	BuildService.SetWorldDropService(WorldDropService)
else
	warn("[ServerInit] BuildService/SetWorldDropService or WorldDropService not available")
end

-- BuildService 핸들러 등록
for command, handler in pairs(BuildService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- DurabilityService 초기화 (BuildService & Balance 준비 완료 후 호출)
DurabilityService.Init(NetController, InventoryService, DataService, BuildService, Balance)

-- CraftingService 초기화 (+ TechService, PlayerStatService 추가)
local CraftingService = require(Services.CraftingService)
CraftingService.Init(NetController, DataService, InventoryService, BuildService, RecipeService, TechService, PlayerStatService, WorldDropService, TimeService)

-- CraftingService 핸들러 등록
for command, handler in pairs(CraftingService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- FacilityService에 BuildService 나중 주입 (순환 방지)
-- [안정화] nil 체크 추가 (require 실패 등 방지)
if FacilityService and FacilityService.SetBuildService then
	FacilityService.SetBuildService(BuildService)
else
	warn("[ServerInit] FacilityService or SetBuildService not available, skipping injection")
end

-- DebuffService 초기화 (Phase 4-4) - CreatureService보다 먼저 초기화
local DebuffService = require(Services.DebuffService)
if DebuffService and DebuffService.Init then
	DebuffService.Init(NetController, TimeService, DataService, StaminaService, FacilityService, InventoryService)
else
	warn("[ServerInit] DebuffService or Init not available")
end

-- DebuffService 핸들러 등록
if DebuffService and DebuffService.GetHandlers then
	for command, handler in pairs(DebuffService.GetHandlers()) do
		NetController.RegisterHandler(command, handler)
	end
end

-- CreatureService 초기화 (+ PlayerStatService 추가, HarvestService는 후순위 주입)
local CreatureService = require(Services.CreatureService)
CreatureService.Init(NetController, DataService, WorldDropService, DebuffService, PlayerStatService)

-- CreatureService 핸들러 등록
for command, handler in pairs(CreatureService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CombatService 초기화 (Phase 3-3, + DebuffService 연동)
local CombatService = require(Services.CombatService)
CombatService.Init(NetController, DataService, CreatureService, InventoryService, DurabilityService, DebuffService, WorldDropService, PlayerStatService, HungerService, TechService)

-- CombatService 핸들러 등록
for command, handler in pairs(CombatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- SkillService 초기화 (스킬 트리: 전투 택1 + 건축 자동해금)
local SkillService = require(Services.SkillService)
SkillService.Init(NetController, PlayerStatService, SaveService)

-- SkillService 핸들러 등록
for command, handler in pairs(SkillService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CombatService에 SkillService 연동 (패시브 보너스)
CombatService.SetSkillService(SkillService)

-- ActiveSkillService 초기화 (액티브 스킬 실행)
local ActiveSkillService = require(Services.ActiveSkillService)
ActiveSkillService.Init(NetController, SkillService, CombatService, CreatureService, InventoryService, DataService, PlayerStatService, DebuffService, StaminaService, HungerService)

-- ActiveSkillService 핸들러 등록
for command, handler in pairs(ActiveSkillService.GetHandlers()) do
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

-- Phase 7-5: PalAIService 초기화 (팰 AI 및 시각화)
local PalAIService = require(Services.PalAIService)
PalAIService.Init(NetController, CreatureService, DataService, PalboxService, BuildService)
FacilityService.SetPalAIService(PalAIService)


-- PartyService 초기화 (Phase 5-4)
local PartyService = require(Services.PartyService)
PartyService.Init(NetController, PalboxService, CreatureService, SaveService)

-- PartyService 핸들러 등록
for command, handler in pairs(PartyService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- HarvestService 초기화 (Phase 7-1)
local HarvestService = require(Services.HarvestService)
HarvestService.Init(NetController, DataService, InventoryService, PlayerStatService, DurabilityService, WorldDropService, TechService)

-- HarvestService 핸들러 등록
for command, handler in pairs(HarvestService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CreatureService에 HarvestService 후순위 주입 (시체 채집 연동)
CreatureService.SetHarvestService(HarvestService)

-- BaseClaimService 초기화 (Phase 7-2)
local BaseClaimService = require(Services.BaseClaimService)
BaseClaimService.Init(NetController, SaveService, BuildService)

-- BuildService에 BaseClaimService 주입 (첫 건물 설치 시 베이스 자동 생성용)
BuildService.SetBaseClaimService(BaseClaimService)

-- BaseClaimService 핸들러 등록
for command, handler in pairs(BaseClaimService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- StorageService 초기화 (BuildService, BaseClaimService 주입 필요)
StorageService.Init(NetController, SaveService, InventoryService, BuildService, BaseClaimService)

-- AutoHarvestService 초기화 (Phase 7-3)
local AutoHarvestService = require(Services.AutoHarvestService)
AutoHarvestService.Init(HarvestService, FacilityService, BaseClaimService, PalboxService, DataService, BuildService, PalAIService)

-- AutoDepositService 초기화 (Phase 7-4)
local AutoDepositService = require(Services.AutoDepositService)
AutoDepositService.Init(FacilityService, StorageService, BaseClaimService, BuildService, DataService, PalboxService, PalAIService)

-- TutorialQuestService 초기화 (초원섬 전용 - 등록된 콘텐츠 Place에서만 활성화)
-- 튜토리얼 퀸스트 초기화 (모든 Zone에서 활성화)
local SpawnConfig = require(ReplicatedStorage.Shared.Config.SpawnConfig)
local TutorialQuestService = require(Services.TutorialQuestService)

TutorialQuestService.Init(NetController, SaveService, PlayerStatService, InventoryService, nil)

-- TutorialQuestService 핸들러 등록
for command, handler in pairs(TutorialQuestService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- 액션 콜백 연결 (기존 서비스 훅 재사용)
InventoryService.SetQuestItemCallback(function(userId, itemId, count)
	TutorialQuestService.onItemAdded(userId, itemId, count)
end)

HarvestService.SetQuestCallback(function(userId, nodeType)
	TutorialQuestService.onHarvest(userId, nodeType)
end)

CraftingService.SetQuestCallback(function(userId, recipeId)
	TutorialQuestService.onCrafted(userId, recipeId)
end)

BuildService.SetQuestCallback(function(userId, facilityId)
	TutorialQuestService.onBuilt(userId, facilityId)
end)

CombatService.SetQuestCallback(function(userId, creatureId)
	TutorialQuestService.onKilled(userId, creatureId)
end)

InventoryService.SetQuestFoodEatenCallback(function(userId, itemId)
	TutorialQuestService.onFoodEaten(userId, itemId)
end)

-- NPCShopService 초기화 (Phase 9)
local NPCShopService = require(Services.NPCShopService)
NPCShopService.Init(NetController, DataService, InventoryService, TimeService)
TutorialQuestService.SetRewardDependencies(PlayerStatService, InventoryService, NPCShopService)

-- NPCShopService 핸들러 등록
for command, handler in pairs(NPCShopService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- TotemService 초기화 (거점 토템 유지비/영역 보호)
local TotemService = require(Services.TotemService)
TotemService.Init(NetController, SaveService, BaseClaimService, BuildService, NPCShopService)

for command, handler in pairs(TotemService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

BuildService.SetTotemService(TotemService)
StorageService.SetTotemService(TotemService)
FacilityService.SetTotemService(TotemService)
CreatureService.SetProtectedZoneChecker(function(position)
	return TotemService.getProtectionInfoAt(position)
end)

-- StaminaService 핸들러 등록 (이미 초기화됨)
for command, handler in pairs(StaminaService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CombatService에 StaminaService 연동 (무적 프레임 체크용)
CombatService.SetStaminaService(StaminaService)

-- PetService 초기화 (도감 펫 시스템)
local PetService = require(Services.PetService)
PetService.Init(NetController, DataService, PlayerStatService, SaveService, CreatureService, CombatService)

-- PetService 핸들러 등록
for command, handler in pairs(PetService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- CharacterSetupService 초기화 (선사시대 캐릭터 스타일)
local CharacterSetupService = require(Services.CharacterSetupService)
CharacterSetupService.Init()

-- PortalService 초기화 (고대 포탈 - 수리 + 텔레포트)
local PortalService = require(Services.PortalService)
PortalService.Init(NetController, SaveService, InventoryService, HarvestService, CreatureService)

-- PortalService 핸들러 등록
for command, handler in pairs(PortalService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

print("[ServerInit] Server initialized (Phase 10)") -- 최종 완료 로그
