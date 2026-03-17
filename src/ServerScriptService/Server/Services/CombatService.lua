-- CombatService.lua
-- 전투 시스템 (Phase 3-3)
-- 플레이어와 크리처 간의 데미지 처리 및 사망 로직, 드롭 아이템 생성

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local CombatService = {}

-- Dependencies
local NetController
local CreatureService
local InventoryService
local DurabilityService
local DataService
local DebuffService
local StaminaService
local WorldDropService
local PlayerStatService
local HungerService -- Cached (Phase 11)
local TechService

-- Constants
local DEFAULT_ATTACK_RANGE = Balance.REACH_BAREHAND or 12 -- 맨손 사거리 (Balance 반영)
local DEFAULT_BAREHAND_DAMAGE = 5
local MIN_ATTACK_COOLDOWN = 0.35 -- 서버 측 최소 공격 쿨다운 보안 검증 (클라이언트 0.4~0.5초 대비 타이트하게)
local PVP_ENABLED = false       -- PvP 비활성화

-- State
local playerAttackCooldowns = {} -- [userId] = lastAttackTime

-- Quest callback (Phase 8)
local questCallback = nil

--========================================
-- StaminaService Integration (Phase 10)
--========================================

function CombatService.SetStaminaService(_StaminaService)
	StaminaService = _StaminaService
end

--- 플레이어가 무적 상태인지 확인 (구르기 중)
function CombatService.isPlayerInvulnerable(userId: number): boolean
	if StaminaService then
		return StaminaService.isInvulnerable(userId)
	end
	return false
end

--========================================
-- Public API
--========================================

function CombatService.Init(_NetController, _DataService, _CreatureService, _InventoryService, _DurabilityService, _DebuffService, _WorldDropService, _PlayerStatService)
	NetController = _NetController
	DataService = _DataService
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	DurabilityService = _DurabilityService
	DebuffService = _DebuffService
	WorldDropService = _WorldDropService
	PlayerStatService = _PlayerStatService
	
	-- HungerService 로드 및 캐싱 (성능 최적화)
	local HSuccess, HService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.HungerService) end)
	if HSuccess then HungerService = HService end

	local TSuccess, TService = pcall(function() return require(game:GetService("ServerScriptService").Server.Services.TechService) end)
	if TSuccess then TechService = TService end
	
	-- 플레이어 퇴장 시 데이터 정리
	Players.PlayerRemoving:Connect(function(player)
		playerAttackCooldowns[player.UserId] = nil
	end)
	
	print("[CombatService] Initialized")
end

--- 플레이어가 대상을 공격 (Client Request)
function CombatService.processPlayerAttack(player: Player, targetId: string)
	if not player or not targetId then 
		return false, Enums.ErrorCode.BAD_REQUEST 
	end

	-- 0. 서버 메모리의 실제 활성 슬롯 데이터 로드 (보안: 클라이언트 요청 슬롯 무시)
	local userId = player.UserId
	local toolSlot = 1
	if InventoryService then
		toolSlot = InventoryService.getActiveSlot(userId) or 1
	end
	
	local baseDamage = DEFAULT_BAREHAND_DAMAGE -- 맨손 기본 데미지
	local range = DEFAULT_ATTACK_RANGE
	local dynamicCooldown = MIN_ATTACK_COOLDOWN -- 기본 0.35초
	local itemData = nil
	local toolItem = nil
	local isBlunt = true -- 맨손은 기본적으로 타격(Blunt) 판정 (기절 수치 부여)
	
	if InventoryService then
		local slotData = InventoryService.getSlot(userId, toolSlot)
		if slotData then
			itemData = DataService.getItem(slotData.itemId)
			if itemData then
				baseDamage = itemData.damage or 5
				range = itemData.range or (itemData.optimalTool == "SPEAR" and Balance.REACH_SPEAR or Balance.REACH_TOOL or 14)
				isBlunt = itemData.isBlunt == true
				toolItem = slotData
				
				-- [보안/기획] 기술 해금 체크 (Relinquish 어뷰징 방지)
				if TechService and not TechService.isRecipeUnlocked(userId, slotData.itemId) then
					return false, Enums.ErrorCode.RECIPE_LOCKED
				end

				-- 내구도 체크: 파손된 도구는 공격 불가능
				if slotData.durability and slotData.durability <= 0 then
					return false, Enums.ErrorCode.INVALID_STATE
				end

				-- 아이템의 attackSpeed를 쿨다운으로 사용
				if itemData.attackSpeed then
					dynamicCooldown = math.max(0.15, itemData.attackSpeed - 0.05)
				end
			end
		end
	end

	-- 1. 서버 측 공격 쿨다운 검증 (Exploit 방지)
	local now = tick()
	if playerAttackCooldowns[userId] and (now - playerAttackCooldowns[userId]) < dynamicCooldown then
		return false, Enums.ErrorCode.COOLDOWN
	end
	playerAttackCooldowns[userId] = now

	local char = player.Character
	if not char then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	-- 2. 대상(크리처 또는 건축물) 확인 및 거리 검증
	local targetObject = nil
	local targetType = "NONE"
	
	-- 3.1 크리처 먼저 체크
	local creature = CreatureService.getCreatureRuntime(targetId)
	if creature and creature.rootPart then
		targetObject = creature.rootPart
		targetType = "CREATURE"
	end
	
	-- 3.2 건축물 체크 (크리처가 아닐 경우)
	local BuildService
	if targetType == "NONE" then
		BuildService = require(game:GetService("ServerScriptService").Server.Services.BuildService)
		local structure = BuildService.get(targetId)
		if structure then
			targetType = "STRUCTURE"
			-- 건축물은 rootPart가 없으므로 Workspace 모델의 PrimaryPart 또는 Position 사용
			local model = workspace.Facilities:FindFirstChild(targetId)
			if model then
				targetObject = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			end
		end
	end
	
	if not targetObject then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	local targetPos = (targetType == "STRUCTURE" and targetObject.Position) or targetObject.Position
	local p1 = Vector2.new(hrp.Position.X, hrp.Position.Z)
	local p2 = Vector2.new(targetPos.X, targetPos.Z)
	local dist = (p1 - p2).Magnitude
	
	-- 서버 측 검증은 클라이언트보다 약간 더 여유를 둡니다
	if dist > range + 50 then 
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	-- 3. 플레이어 공격력 스탯 보너스 적용
	local calculated = PlayerStatService.GetCalculatedStats(player.UserId)
	local attackMult = calculated.attackMult or 1.0

	-- 도끼/곡괭이는 동물/공룡 상대로 맨손 데미지로 고정.
	if targetType == "CREATURE" and itemData and itemData.type == "TOOL" then
		local toolRole = tostring(itemData.optimalTool or ""):upper()
		if toolRole == "AXE" or toolRole == "PICKAXE" then
			baseDamage = DEFAULT_BAREHAND_DAMAGE
			isBlunt = true
		end
	end

	local totalDamage = baseDamage * attackMult

	-- 4. 데미지 및 기절 수치 적용
	local hpDamage = totalDamage
	local torporDamage = 0
	
	if isBlunt then
		hpDamage = totalDamage * 0.5  -- 둔기는 체력 데미지 50%
		torporDamage = totalDamage * 0.5 -- 기절 데미지 50%
	end
	
	local killed = false
	local dropPos = nil
	
	if targetType == "CREATURE" then
		killed, dropPos = CreatureService.processAttack(targetId, hpDamage, torporDamage, player)
	elseif targetType == "STRUCTURE" then
		-- 건축물 데미지 적용
		local destroyed, _ = BuildService.takeDamage(targetId, hpDamage, player)
		killed = destroyed
		if killed then dropPos = targetPos end
	end
	
	-- 4. 도구 내구도 감소
	if toolItem and toolSlot and toolItem.durability then
		DurabilityService.reduceDurability(player, toolSlot, 1)
	end
	
	-- 4.5 전투 시 배고픔 소모 연동 (Phase 11)
	if HungerService then
		HungerService.consumeHunger(player.UserId, Balance.HUNGER_COMBAT_COST)
	end
	
	-- 5. 피냄새 디버프 및 드롭 생성 (크리처를 킬했을 때)
	if killed and dropPos and targetType == "CREATURE" and creature then
		-- 피냄새 적용
		if DebuffService then
			DebuffService.applyDebuff(player.UserId, "BLOOD_SMELL")
		end
		
		-- 드롭 아이템 생성
		if WorldDropService and DataService then
			local dropTable = DataService.getDropTable(creature.creatureId)
			if dropTable then
				for _, entry in ipairs(dropTable) do
					if math.random() <= (entry.chance or 1.0) then
						local count = math.random(entry.min or 1, entry.max or 1)
						-- 랜덤 오프셋
						local angle = math.random() * math.pi * 2
						local radius = math.random() * 2
						local baseSpawnPos = dropPos + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
						
						-- [개선] 지면 인식 레이캐스트 (피격 대상 및 플레이어 제외하여 바닥 찾기)
						local rayParams = RaycastParams.new()
						local excludeList = {char}
						if creature and creature.model then table.insert(excludeList, creature.model) end
						rayParams.FilterDescendantsInstances = excludeList
						rayParams.FilterType = Enum.RaycastFilterType.Exclude
						
						local rayResult = workspace:Raycast(baseSpawnPos, Vector3.new(0, -30, 0), rayParams)
						local finalSpawnPos = rayResult and rayResult.Position or (dropPos + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
						
						WorldDropService.spawnDrop(finalSpawnPos, entry.itemId, count)
					end
				end
			end
		end
	end
	
	-- 5.5 퀘스트 콜백 (Phase 8)
	if killed and targetType == "CREATURE" and questCallback and creature and creature.data then
		questCallback(player.UserId, creature.data.id or creature.data.creatureId)
	end
	
	-- 6. 타격 피드백 (Client Event)
	if NetController then
		NetController.FireClient(player, "Combat.Hit.Result", {
			damage = hpDamage,
			torporDamage = torporDamage,
			killed = killed,
			targetId = targetId,
		})
	end
	
	local targetLabel = targetId
	if targetType == "CREATURE" and creature and creature.data then
		targetLabel = creature.data.name or creature.data.id or targetId
	end

	print(string.format("[CombatService] %s hit %s for %.1f (Torpor: %.1f) dmg%s", 
		player.Name, targetLabel, hpDamage, torporDamage, killed and " (KILLED)" or ""))
	
	return true, nil, { damage = hpDamage, torporDamage = torporDamage, killed = killed }
end

--- 플레이어에게 데미지 적용 (방어력 반영 + 넉백 적용)
function CombatService.damagePlayer(userId: number, rawDamage: number, sourcePos: Vector3?)
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player or not player.Character then return end
	
	local humanoid = player.Character:FindFirstChild("Humanoid")
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid.Health <= 0 then return end
	
	-- 1. 무적 상태 체크 (구르기 등)
	if CombatService.isPlayerInvulnerable(userId) then
		return
	end
	
	-- 2. 방어력 계산
	local defense = 0
	if InventoryService and InventoryService.getTotalDefense then
		defense = InventoryService.getTotalDefense(userId)
	end
	
	-- 데미지 감쇄 공식: final = raw * (100 / (100 + defense))
	local reductionMult = 100 / (100 + defense)
	local finalDamage = math.max(1, rawDamage * reductionMult)
	
	-- 3. 방어구 내구도 감소
	if InventoryService and InventoryService.decreaseEquipmentDurability then
		local armorDamage = math.max(1, math.floor(rawDamage * (Balance.ARMOR_DURABILITY_LOSS_RATIO or 0.1)))
		local equip = InventoryService.getEquipment(userId)
		
		if equip.SUIT then
			InventoryService.decreaseEquipmentDurability(userId, "SUIT", armorDamage)
		else
			if equip.TOP then InventoryService.decreaseEquipmentDurability(userId, "TOP", math.ceil(armorDamage * 0.4)) end
			if equip.BOTTOM then InventoryService.decreaseEquipmentDurability(userId, "BOTTOM", math.ceil(armorDamage * 0.4)) end
			if equip.HEAD then InventoryService.decreaseEquipmentDurability(userId, "HEAD", math.ceil(armorDamage * 0.2)) end
		end
	end
	
	-- 4. 데미지 적용
	humanoid:TakeDamage(finalDamage)
	
	-- 5. ★ 물리적 피격 피드백 (넉백 + 클라이언트 연출)
	if sourcePos then
		-- 반대 방향으로 밀어냄
		local diff = (hrp.Position - sourcePos)
		local dir = Vector3.new(diff.X, 0, diff.Z).Unit
		
		-- 넉백 강도 상향 및 Y축 방향성 추가 (살짝 뜨게 하여 마찰력 무시)
		hrp.AssemblyLinearVelocity = dir * (Balance.KNOCKBACK_FORCE or 25) + Vector3.new(0, 15, 0)
		
		-- [추가] 눕기/넘어짐 방지를 위해 서버에서도 상태 강제 고정
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	
	-- 6. 클라이언트 연출 요청 (화면 흔들림, 피격 효과 등)
	if NetController then
		NetController.FireClient(player, "Combat.Player.Hit", {
			damage = finalDamage,
			sourcePos = sourcePos
		})
	end
	
	print(string.format("[CombatService] Player %s took %.1f damage (Raw: %.1f, Def: %d)", 
		player.Name, finalDamage, rawDamage, defense))
end

--========================================
-- Network Handlers
--========================================

local function handleHitRequest(player, payload)
	local targetId = payload.targetId or payload.targetInstanceId
	
	local success, errorCode, result = CombatService.processPlayerAttack(player, targetId)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = result }
end

function CombatService.GetHandlers()
	return {
		["Combat.Hit.Request"] = handleHitRequest
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function CombatService.SetQuestCallback(callback)
	questCallback = callback
end

return CombatService
