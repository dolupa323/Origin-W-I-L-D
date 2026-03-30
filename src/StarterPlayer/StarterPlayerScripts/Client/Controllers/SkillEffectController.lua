-- SkillEffectController.lua
-- 액티브 스킬 사용 시 VFX, 사운드, 애니메이션 연출 담당 (클라이언트)
-- 서버 ActiveSkill.Used 브로드캐스트를 수신하여 이펙트 재생

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent.NetClient)
local AnimationManager = require(script.Parent.Parent.Utils.AnimationManager)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared.Config.AnimationIds)

local player = Players.LocalPlayer

local SkillEffectController = {}

--========================================
-- Constants
--========================================
local VFX_CAST_LIFETIME = 3.5    -- 시전 VFX 지속 시간
local VFX_HIT_LIFETIME = 2.5     -- 피격 VFX 지속 시간

-- 스트라이크/돌진 전용 짧은 VFX 지속 시간
local SHORT_VFX_SKILLS = { SWORD_A1 = true, SWORD_A2 = true }
local VFX_CAST_LIFETIME_SHORT = 1.5
local VFX_HIT_LIFETIME_SHORT = 1.2
local VFX_CAST_LIFETIME_FLURRY = 1.2   -- 난무 Cast VFX 지속 시간
local VFX_HIT_LIFETIME_FLURRY = 1.5    -- 난무 Hit VFX 지속 시간

-- 돌진 스킬 설정
local CHARGE_DISTANCE = 16       -- 돌진 거리 (스터드)
local CHARGE_DURATION = 0.25     -- 돌진 소요 시간 (초)

-- 난무 스킬 설정
local FLURRY_DASH_DISTANCE = 12  -- 난무 전진 거리 (스터드)
local FLURRY_DASH_DURATION = 0.3 -- 난무 전진 시간 (초)
local FLURRY_HIT_DELAY = 0.35    -- 난무 VFX/사운드 지연 (애니메이션 첫 타격 시점)

--========================================
-- Asset Folders (lazy init)
--========================================
local assetsFolder = nil
local castVFXFolder = nil
local hitVFXFolder = nil
local castSoundFolder = nil
local hitSoundFolder = nil

local function ensureAssetFolders()
	if assetsFolder then return end
	assetsFolder = ReplicatedStorage:WaitForChild("Assets", 10)
	if not assetsFolder then return end

	local skillVFX = assetsFolder:WaitForChild("SkillVFX", 10)
	if skillVFX then
		castVFXFolder = skillVFX:WaitForChild("Cast", 5)
		hitVFXFolder = skillVFX:WaitForChild("Hit", 5)
	end

	local skillSounds = assetsFolder:WaitForChild("SkillSounds", 5)
	if skillSounds then
		castSoundFolder = skillSounds:FindFirstChild("Cast")
		hitSoundFolder = skillSounds:FindFirstChild("Hit")
	end
end

--========================================
-- Internal Helpers
--========================================

--- 캐릭터 가져오기 (userId로)
local function getCharacterByUserId(userId: number): Model?
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer then return nil end
	return targetPlayer.Character
end

--- 크리처 모델 찾기 (instanceId로 — Attribute "InstanceId" 기반)
local function getCreatureModel(targetId: string): Model?
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if not creaturesFolder then return nil end
	for _, child in creaturesFolder:GetChildren() do
		if child:GetAttribute("InstanceId") == targetId then
			return child
		end
	end
	return nil
end

--- VFX 파트 스폰 및 자동 삭제
local function spawnVFX(template: Instance, parent: BasePart, lifetime: number)
	if not template or not parent then return end

	local vfx = template:Clone()

	-- Weld로 부착 (이동 중에도 따라감)
	if vfx:IsA("BasePart") then
		vfx.CFrame = parent.CFrame
		vfx.Anchored = false
		vfx.CanCollide = false
		vfx.CanQuery = false
		vfx.CanTouch = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = vfx
		weld.Part1 = parent
		weld.Parent = vfx
	elseif vfx:IsA("Model") then
		vfx:PivotTo(parent.CFrame)
	end

	-- 컨테이너 Part만 투명 처리 (ParticleEmitter가 붙은 일반 Part)
	-- MeshPart는 시각 메시이므로 유지
	for _, desc in vfx:GetDescendants() do
		if desc:IsA("Part") and not desc:IsA("MeshPart") then
			desc.Transparency = 1
		end
	end
	if vfx:IsA("Part") and not vfx:IsA("MeshPart") then
		vfx.Transparency = 1
	end

	vfx.Parent = workspace

	-- ParticleEmitter Burst 발사
	for _, desc in vfx:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			local burstCount = desc:GetAttribute("BurstCount")
			if burstCount then
				desc:Emit(burstCount)
			else
				desc.Enabled = true
				task.delay(lifetime * 0.5, function()
					if desc and desc.Parent then
						desc.Enabled = false
					end
				end)
			end
		end
	end

	Debris:AddItem(vfx, lifetime)
end

--- 사운드 재생 (원본 Clone → 파트에 부착 → Play → 자동 정리)
local SOUND_VOLUME_SCALE = 0.3  -- 전체 사운드 볼륨 배율
local function playSound(template: Sound, parent: BasePart)
	if not template or not parent then return end

	local sfx = template:Clone()
	sfx.Volume = (sfx.Volume or 0.5) * SOUND_VOLUME_SCALE
	sfx.Parent = parent
	sfx:Play()
	sfx.Ended:Once(function()
		if sfx and sfx.Parent then
			sfx:Destroy()
		end
	end)
end

--========================================
-- Effect Execution
--========================================

--- 캐릭터에서 장착 무기의 날(Blade) 파트 찾기
local function getWeaponBladePart(character: Model): BasePart?
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return nil end
	local handle = tool:FindFirstChild("Handle")
	if not handle then return nil end

	-- Handle이 아닌 가장 큰 가시적 파트 = 날
	local bestPart = nil
	local bestScore = 0
	for _, p in tool:GetDescendants() do
		if p:IsA("BasePart") and p ~= handle and p.Transparency < 0.85 then
			local dim = math.max(p.Size.X, p.Size.Y, p.Size.Z)
			local score = dim * (p.Size.X * p.Size.Y * p.Size.Z)
			if score > bestScore then
				bestScore = score
				bestPart = p
			end
		end
	end
	return bestPart or handle
end

--- 캐릭터를 전방으로 빠르게 돌진 이동
local function performChargeDash(character: Model, distance: number, duration: number)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	-- 전방 방향 (캐릭터가 바라보는 방향)
	local direction = hrp.CFrame.LookVector
	local startPos = hrp.Position
	local targetPos = startPos + direction * distance

	-- BodyVelocity로 빠르게 이동
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.Velocity = direction * (distance / duration)
	bv.Parent = hrp

	task.delay(duration, function()
		if bv and bv.Parent then
			bv:Destroy()
		end
	end)
end
local function findVFXTemplates(folder: Folder, baseName: string): { Instance }
	local results = {}
	-- 기본 이름 체크 (_Cast 또는 _Hit)
	local exact = folder:FindFirstChild(baseName)
	if exact then
		table.insert(results, exact)
	end
	-- 넘버링 체크 (_Cast01 ~ _Cast99)
	for i = 1, 99 do
		local numbered = folder:FindFirstChild(baseName .. string.format("%02d", i))
		if numbered then
			table.insert(results, numbered)
		else
			break
		end
	end
	return results
end

--- 스킬 이펙트 전체 실행
local function executeSkillEffects(userId: number, skillId: string, targetId: string?)
	ensureAssetFolders()

	local character = getCharacterByUserId(userId)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	-- skillId(SWORD_A1 등) → 에셋 이름(SkillSword_Strike 등) 변환
	local animName = AnimationIds.SKILL_ANIM_MAP[skillId]
	local assetName = animName

	--========================================
	-- SWORD_A3 난무: 전용 연출 (애니메이션 우선 → 전진 → Cast VFX 1회 → 사운드/Hit VFX)
	--========================================
	if skillId == "SWORD_A3" then
		-- 1. 애니메이션 즉시 재생
		if animName then
			local track = AnimationManager.play(humanoid, animName, 0.05)
			if track then
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped = false
			end
		end

		-- 2. Cast VFX 출력 (캐릭터 전방 한 지점에 여러 VFX 중첩)
		if castVFXFolder and assetName then
			local castTemplates = findVFXTemplates(castVFXFolder, assetName .. "_Cast")
			if #castTemplates > 0 then
				local spawnPos = hrp.Position + hrp.CFrame.LookVector * 10
				local castCount = 12
				local baseCF = CFrame.lookAt(spawnPos, spawnPos + hrp.CFrame.LookVector)

				-- 고정 앵커 하나 생성
				local anchor = Instance.new("Part")
				anchor.Size = Vector3.new(1, 1, 1)
				anchor.Transparency = 1
				anchor.Anchored = true
				anchor.CanCollide = false
				anchor.CanQuery = false
				anchor.CanTouch = false
				anchor.CFrame = baseCF
				anchor.Parent = workspace

				for i = 1, castCount do
					task.delay((i - 1) * 0.04, function()
						if not anchor or not anchor.Parent then return end
						local tmpl = castTemplates[math.random(1, #castTemplates)]
						-- 각 VFX마다 약간의 회전 변화만 줘서 중첩 시 풍성한 느낌
						anchor.CFrame = baseCF * CFrame.Angles(
							math.rad(math.random(-20, 20)),
							math.rad(math.random(-20, 20)),
							math.rad(math.random(0, 360))
						)
						spawnVFX(tmpl, anchor, VFX_CAST_LIFETIME_FLURRY)
					end)
				end
				Debris:AddItem(anchor, VFX_CAST_LIFETIME_FLURRY + 0.5)
			end
		end

		-- 4. 딜레이 후 사운드 + 광역 Hit VFX (대상 없어도 출력)
		task.delay(FLURRY_HIT_DELAY, function()
			if not hrp or not hrp.Parent then return end

			-- 시전 사운드
			if castSoundFolder and assetName then
				local castSoundTemplate = castSoundFolder:FindFirstChild(assetName .. "_Cast")
				if castSoundTemplate then
					playSound(castSoundTemplate, hrp)
				end
			end

			-- 피격 사운드
			if hitSoundFolder and assetName then
				local hitSoundTemplate = hitSoundFolder:FindFirstChild(assetName .. "_Hit")
				if hitSoundTemplate then
					playSound(hitSoundTemplate, hrp)
				end
			end

			-- ★ Hit VFX: 타겟이 있을 때만 출력 (캐릭터 전방 한 지점에 여러 VFX 중첩)
			if targetId and hitVFXFolder and assetName then
				local hitTemplates = findVFXTemplates(hitVFXFolder, assetName .. "_Hit")
				if #hitTemplates > 0 then
					local spawnPos = hrp.Position + hrp.CFrame.LookVector * 10
					local hitCount = 12
					local baseCF = CFrame.lookAt(spawnPos, spawnPos + hrp.CFrame.LookVector)

					local anchor = Instance.new("Part")
					anchor.Size = Vector3.new(1, 1, 1)
					anchor.Transparency = 1
					anchor.Anchored = true
					anchor.CanCollide = false
					anchor.CanQuery = false
					anchor.CanTouch = false
					anchor.CFrame = baseCF
					anchor.Parent = workspace

					for i = 1, hitCount do
						task.delay((i - 1) * 0.04, function()
							if not anchor or not anchor.Parent then return end
							local tmpl = hitTemplates[math.random(1, #hitTemplates)]
							anchor.CFrame = baseCF * CFrame.Angles(
								math.rad(math.random(-20, 20)),
								math.rad(math.random(-20, 20)),
								math.rad(math.random(0, 360))
							)
							spawnVFX(tmpl, anchor, VFX_HIT_LIFETIME_FLURRY)
						end)
					end
					Debris:AddItem(anchor, VFX_HIT_LIFETIME_FLURRY + 0.5)
				end
			end
		end)

		return -- 난무는 전용 로직으로 처리 완료
	end

	--========================================
	-- 기본 스킬 연출 (SWORD_A1, SWORD_A2, BOW, AXE 등)
	--========================================

	-- 1. 시전 VFX 먼저 출력 (애니메이션보다 살짝 빠르게)
	local isShortVFX = SHORT_VFX_SKILLS[skillId]
	local castLife = isShortVFX and VFX_CAST_LIFETIME_SHORT or VFX_CAST_LIFETIME
	local hitLife = isShortVFX and VFX_HIT_LIFETIME_SHORT or VFX_HIT_LIFETIME
	
	if castVFXFolder and assetName then
		local castTemplates = findVFXTemplates(castVFXFolder, assetName .. "_Cast")
		if #castTemplates > 0 then
			local bladePart = getWeaponBladePart(character)
			spawnVFX(castTemplates[1], bladePart or hrp, castLife)
		end
	end

	-- 2. 시전 사운드 (VFX와 동시)
	if castSoundFolder and assetName then
		local castSoundTemplate = castSoundFolder:FindFirstChild(assetName .. "_Cast")
		if castSoundTemplate then
			playSound(castSoundTemplate, hrp)
		end
	end

	-- 3. VFX 출력 후 딜레이 → 애니메이션 재생 (스트라이크/돌진은 VFX 선행)
	local animDelay = isShortVFX and 0.25 or 0.05
	task.delay(animDelay, function()
		if not humanoid or not humanoid.Parent then return end
		if animName then
			local track = AnimationManager.play(humanoid, animName, 0.05)
			if track then
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped = false
			end
		end
	end)

	-- ★ SWORD_A2 돌진: 로컬 플레이어면 전방 대시 이동
	if skillId == "SWORD_A2" and userId == player.UserId then
		performChargeDash(character, CHARGE_DISTANCE, CHARGE_DURATION)
	end

	-- 4. 피격 VFX + 사운드 (타겟 기준)
	if targetId then
		local targetModel = getCreatureModel(targetId)
		if targetModel then
			local targetHrp = targetModel:FindFirstChild("HumanoidRootPart")
				or targetModel.PrimaryPart
				or targetModel:FindFirstChildWhichIsA("BasePart")

			if targetHrp and assetName then
				-- 피격 VFX (넘버링 지원: _Hit, _Hit01, _Hit02 ...)
				if hitVFXFolder then
					local hitTemplates = findVFXTemplates(hitVFXFolder, assetName .. "_Hit")
					for _, tmpl in ipairs(hitTemplates) do
						spawnVFX(tmpl, targetHrp, hitLife)
					end
				end

				-- 피격 사운드
				if hitSoundFolder then
					local hitSoundTemplate = hitSoundFolder:FindFirstChild(assetName .. "_Hit")
					if hitSoundTemplate then
						playSound(hitSoundTemplate, targetHrp)
					end
				end
			end
		end
	end
end

--========================================
-- Init
--========================================
local initialized = false

function SkillEffectController.Init()
	if initialized then return end
	initialized = true

	-- 에셋 폴더 미리 로드 (게임 시작 시 대기)
	task.spawn(ensureAssetFolders)

	-- 서버 브로드캐스트 수신: 스킬 사용 이펙트
	NetClient.On("ActiveSkill.Used", function(data)
		if not data then return end
		local userId = data.userId
		local skillId = data.skillId
		local targetId = data.targetId

		if not userId or not skillId then return end

		task.spawn(function()
			executeSkillEffects(userId, skillId, targetId)
		end)
	end)

	print("[SkillEffectController] Initialized")
end

return SkillEffectController
