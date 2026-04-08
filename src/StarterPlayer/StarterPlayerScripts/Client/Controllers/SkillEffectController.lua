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
	local assetName = AnimationIds.SKILL_ASSET_MAP and AnimationIds.SKILL_ASSET_MAP[skillId] or animName

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

	local isBowSkill = skillId:sub(1, 4) == "BOW_"
	local isAxeSkill = skillId:sub(1, 4) == "AXE_"

	-- 1. 시전 VFX 먼저 출력 (애니메이션보다 살짝 빠르게)
	local isShortVFX = SHORT_VFX_SKILLS[skillId]
	local castLife = isShortVFX and VFX_CAST_LIFETIME_SHORT or VFX_CAST_LIFETIME
	local hitLife = isShortVFX and VFX_HIT_LIFETIME_SHORT or VFX_HIT_LIFETIME

	if isBowSkill and castVFXFolder and assetName then
		-- ★ BOW 스킬: Cast VFX가 화살 경로를 따라 날아감
		local castTemplates = findVFXTemplates(castVFXFolder, assetName .. "_Cast")
		if #castTemplates > 0 then
			-- 타겟 위치 결정
			local targetPos: Vector3?
			if targetId then
				local targetModel = getCreatureModel(targetId)
				if targetModel then
					local tHrp = targetModel:FindFirstChild("HumanoidRootPart")
						or targetModel.PrimaryPart
						or targetModel:FindFirstChildWhichIsA("BasePart")
					if tHrp then
						targetPos = tHrp.Position
					end
				end
			end
			if not targetPos then
				-- 타겟 없으면 캐릭터 정면으로 발사
				targetPos = hrp.Position + hrp.CFrame.LookVector * 80
			end

			local startPos = hrp.Position + Vector3.new(0, 1.5, 0)
			local direction = (targetPos - startPos)
			if direction.Magnitude < 1 then direction = hrp.CFrame.LookVector end
			direction = direction.Unit

			-- ★ 화살 모델 발사 (로컬 플레이어만, BOW_A2는 속사 루프에서 개별 발사)
			if userId == player.UserId and skillId ~= "BOW_A2" then
				local ok, CombatCtrl = pcall(function()
					return require(script.Parent.CombatController)
				end)
				if ok and CombatCtrl and CombatCtrl.fireArrowTracer then
					CombatCtrl.fireArrowTracer(targetPos, startPos, direction)
				end
			end
			local distance = (targetPos - startPos).Magnitude
			local travelTime = math.clamp(distance / 60, 0.4, 1.5)

			-- 스킬별 CFrame 보정
			local rotationOffset = CFrame.new()
			if skillId == "BOW_A1" then
				-- 강사: 뾰족한 끝(X축)이 전방을 향하도록 Y축 회전
				rotationOffset = CFrame.Angles(0, math.rad(-90), 0)
			elseif skillId == "BOW_A2" then
				rotationOffset = CFrame.Angles(math.rad(-90), 0, math.rad(90))
			elseif skillId == "BOW_A3" then
				rotationOffset = CFrame.Angles(math.rad(180), 0, 0)
			end

			-- ★ BOW_A2 속사: Cast VFX를 순차적으로 5발 발사
			if skillId == "BOW_A2" then
				local rapidCount = 5
				local rapidInterval = 0.12
				for shotIdx = 1, rapidCount do
					task.delay((shotIdx - 1) * rapidInterval, function()
						if not hrp or not hrp.Parent then return end
						-- 각 화살마다 약간의 랜덤 방향 산란
						local spread = Vector3.new(
							(math.random() - 0.5) * 0.08,
							(math.random() - 0.5) * 0.04,
							(math.random() - 0.5) * 0.08
						)
						local shotDir = (direction + spread).Unit
						local shotTarget = startPos + shotDir * distance
						local shotTravelTime = math.clamp(distance / 65, 0.35, 1.3)
					-- ★ 속사 화살 모델 트레이서 (로컬 플레이어만)
					if userId == player.UserId then
						local ok2, CombatCtrl2 = pcall(function()
							return require(script.Parent.CombatController)
						end)
						if ok2 and CombatCtrl2 and CombatCtrl2.fireArrowTracer then
							CombatCtrl2.fireArrowTracer(shotTarget, startPos, shotDir)
						end
					end
						local tmpl = castTemplates[(shotIdx - 1) % #castTemplates + 1]
						local shotVfx = tmpl:Clone()
						local forwardCF = CFrame.lookAt(startPos, startPos + shotDir)
						if shotVfx:IsA("BasePart") then
							shotVfx.CFrame = forwardCF * rotationOffset
							shotVfx.Anchored = true
							shotVfx.CanCollide = false
							shotVfx.CanQuery = false
							shotVfx.CanTouch = false
							if shotVfx:IsA("Part") and not shotVfx:IsA("MeshPart") then
								shotVfx.Transparency = 1
							end
						elseif shotVfx:IsA("Model") then
							shotVfx:PivotTo(forwardCF * rotationOffset)
						end
						shotVfx.Parent = workspace

						for _, desc in shotVfx:GetDescendants() do
							if desc:IsA("ParticleEmitter") then
								local bc = desc:GetAttribute("BurstCount")
								if bc then desc:Emit(bc)
								else desc.Enabled = true end
							end
						end

						-- 화살 경로 추종
						task.spawn(function()
							local t0 = tick()
							while true do
								local alpha = math.min((tick() - t0) / shotTravelTime, 1)
								local pos = startPos:Lerp(shotTarget, alpha)
								local cf = CFrame.lookAt(pos, pos + shotDir)
								if shotVfx:IsA("BasePart") and shotVfx.Parent then
									shotVfx.CFrame = cf * rotationOffset
								elseif shotVfx:IsA("Model") and shotVfx.Parent then
									shotVfx:PivotTo(cf * rotationOffset)
								end
								if alpha >= 1 then break end
								task.wait()
							end
							for _, desc in shotVfx:GetDescendants() do
								if desc:IsA("ParticleEmitter") then desc.Enabled = false end
							end
							-- 개별 화살 도착 시 Hit VFX + 사운드
							local arrivalPos = shotTarget
							if hitVFXFolder then
								local hitTemplates = findVFXTemplates(hitVFXFolder, assetName .. "_Hit")
								for _, htmpl in ipairs(hitTemplates) do
									local hitVfx = htmpl:Clone()
									if hitVfx:IsA("BasePart") then
										hitVfx.Anchored = true
										hitVfx.CanCollide = false
										hitVfx.CanQuery = false
										hitVfx.CanTouch = false
										hitVfx.CFrame = CFrame.new(arrivalPos)
										if hitVfx:IsA("Part") and not hitVfx:IsA("MeshPart") then
											hitVfx.Transparency = 1
										end
									end
									hitVfx.Parent = workspace
									for _, d in hitVfx:GetDescendants() do
										if d:IsA("ParticleEmitter") then
											local bc2 = d:GetAttribute("BurstCount")
											if bc2 then d:Emit(bc2)
											else d.Enabled = true
												task.delay(1.5, function()
													if d and d.Parent then d.Enabled = false end
												end)
											end
										end
									end
									Debris:AddItem(hitVfx, hitLife)
								end
							end
							if hitSoundFolder then
								local hitSndTmpl = hitSoundFolder:FindFirstChild(assetName .. "_Hit")
								if hitSndTmpl then
									local sndPart = Instance.new("Part")
									sndPart.Size = Vector3.one
									sndPart.Transparency = 1
									sndPart.Anchored = true
									sndPart.CanCollide = false
									sndPart.CanQuery = false
									sndPart.CanTouch = false
									sndPart.Position = arrivalPos
									sndPart.Parent = workspace
									local sfx = hitSndTmpl:Clone()
									sfx.Parent = sndPart
									sfx:Play()
									Debris:AddItem(sndPart, 3)
								end
							end
						end)
						Debris:AddItem(shotVfx, castLife)
					end)
				end
				-- BOW_A2는 여기서 처리 완료 — 아래 공통 로직 스킵
				Debris:AddItem(vfx, 0.1) -- 빈 원본 즉시 정리
			else
			-- ★ BOW_A1, BOW_A3 등 기존 단일 VFX 로직
			local vfx = castTemplates[1]:Clone()
			if vfx:IsA("BasePart") then
				local forwardCF = CFrame.lookAt(startPos, startPos + direction)
				vfx.CFrame = forwardCF * rotationOffset
				vfx.Anchored = true
				vfx.CanCollide = false
				vfx.CanQuery = false
				vfx.CanTouch = false
				if vfx:IsA("Part") and not vfx:IsA("MeshPart") then
					vfx.Transparency = 1
				end
			elseif vfx:IsA("Model") then
				local forwardCF = CFrame.lookAt(startPos, startPos + direction)
				vfx:PivotTo(forwardCF * rotationOffset)
			end
			vfx.Parent = workspace

			-- ParticleEmitter 활성화
			for _, desc in vfx:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					local burstCount = desc:GetAttribute("BurstCount")
					if burstCount then
						desc:Emit(burstCount)
					else
						desc.Enabled = true
					end
				end
			end

			-- 화살 경로 추종 이동
			task.spawn(function()
				local t0 = tick()
				while true do
					local elapsed = tick() - t0
					local alpha = math.min(elapsed / travelTime, 1)
					local pos = startPos:Lerp(targetPos, alpha)
					local cf = CFrame.lookAt(pos, pos + direction)
					if vfx:IsA("BasePart") and vfx.Parent then
						vfx.CFrame = cf * rotationOffset
					elseif vfx:IsA("Model") and vfx.Parent then
						vfx:PivotTo(cf * rotationOffset)
					end
					if alpha >= 1 then break end
					task.wait()
				end
				-- 도착 후 파티클 비활성화
				for _, desc in vfx:GetDescendants() do
					if desc:IsA("ParticleEmitter") then
						desc.Enabled = false
					end
				end

				-- ★ 모든 BOW 스킬: 도착 지점에서 Hit VFX + Hit 사운드 재생
				do
					local arrivalPos = targetPos
					local isAOE = (skillId == "BOW_A3")
					local isRapid = (skillId == "BOW_A2")
					local sizeScale = isAOE and 3 or 1
					local hitCount = isRapid and 5 or 1
					local hitInterval = 0.15  -- 속사 화살 간격

					for hitIdx = 1, hitCount do
						local delay = isRapid and ((hitIdx - 1) * hitInterval) or 0
						task.delay(delay, function()
							-- 속사: 화살마다 랜덤 오프셋 (반경 3스터드 내)
							local spawnPos = arrivalPos
							if isRapid then
								local rx = (math.random() - 0.5) * 6
								local ry = (math.random() - 0.5) * 3
								local rz = (math.random() - 0.5) * 6
								spawnPos = arrivalPos + Vector3.new(rx, ry, rz)
							end

							if hitVFXFolder then
								local hitTemplates = findVFXTemplates(hitVFXFolder, assetName .. "_Hit")
								for _, tmpl in ipairs(hitTemplates) do
									local hitVfx = tmpl:Clone()
									if hitVfx:IsA("BasePart") then
										hitVfx.Anchored = true
										hitVfx.CanCollide = false
										hitVfx.CanQuery = false
										hitVfx.CanTouch = false
										hitVfx.CFrame = CFrame.new(spawnPos)
										if hitVfx:IsA("Part") and not hitVfx:IsA("MeshPart") then
											hitVfx.Transparency = 1
										end
									end
									hitVfx.Parent = workspace
									if sizeScale > 1 then
										if hitVfx:IsA("BasePart") then
											hitVfx.Size = hitVfx.Size * sizeScale
										end
									end
									for _, d in hitVfx:GetDescendants() do
										if sizeScale > 1 and d:IsA("BasePart") then
											d.Size = d.Size * sizeScale
										end
										if d:IsA("ParticleEmitter") then
											if sizeScale > 1 then
												d.Size = NumberSequence.new({
													NumberSequenceKeypoint.new(0, (d.Size.Keypoints[1].Value) * sizeScale),
													NumberSequenceKeypoint.new(1, (d.Size.Keypoints[#d.Size.Keypoints].Value) * sizeScale),
												})
											end
											local bc = d:GetAttribute("BurstCount")
											if bc then d:Emit(bc)
											else d.Enabled = true
												task.delay(1.5, function()
													if d and d.Parent then d.Enabled = false end
												end)
											end
										end
									end
									Debris:AddItem(hitVfx, hitLife)
								end
							end
							if hitSoundFolder then
								local hitSndTmpl = hitSoundFolder:FindFirstChild(assetName .. "_Hit")
								if hitSndTmpl then
									local sndPart = Instance.new("Part")
									sndPart.Size = Vector3.one
									sndPart.Transparency = 1
									sndPart.Anchored = true
									sndPart.CanCollide = false
									sndPart.CanQuery = false
									sndPart.CanTouch = false
									sndPart.Position = spawnPos
									sndPart.Parent = workspace
									local sfx = hitSndTmpl:Clone()
									sfx.Parent = sndPart
									sfx:Play()
									Debris:AddItem(sndPart, 3)
								end
							end
						end)
					end
				end
			end)

			Debris:AddItem(vfx, castLife)
			end -- BOW_A2 else 종료
		end
	elseif isAxeSkill and castVFXFolder and assetName then
		--========================================
		-- ★ AXE 스킬 전용 Cast VFX 처리
		--========================================
		local castTemplates = findVFXTemplates(castVFXFolder, assetName .. "_Cast")

		if skillId == "AXE_A1" then
			-- ★ 내려찍기: Cast VFX → 캐릭터 머리 위에 Anchored (내려치기 전 기운 모으기)
			if #castTemplates > 0 then
				local abovePos = hrp.Position + Vector3.new(0, 3, 0) + hrp.CFrame.LookVector * 1
				local anchor = Instance.new("Part")
				anchor.Size = Vector3.new(1, 1, 1)
				anchor.Transparency = 1
				anchor.Anchored = true
				anchor.CanCollide = false
				anchor.CanQuery = false
				anchor.CanTouch = false
				anchor.CFrame = CFrame.new(abovePos)
				anchor.Parent = workspace
				spawnVFX(castTemplates[1], anchor, castLife)
				Debris:AddItem(anchor, castLife + 0.5)
			end

		elseif skillId == "AXE_A2" then
			-- ★ 회전베기: Cast VFX를 캐릭터 위치에 Anchored (회전 안 따라감)
			if #castTemplates > 0 then
				local anchor = Instance.new("Part")
				anchor.Size = Vector3.new(1, 1, 1)
				anchor.Transparency = 1
				anchor.Anchored = true
				anchor.CanCollide = false
				anchor.CanQuery = false
				anchor.CanTouch = false
				anchor.CFrame = hrp.CFrame
				anchor.Parent = workspace
				spawnVFX(castTemplates[1], anchor, castLife)
				Debris:AddItem(anchor, castLife + 0.5)
			end

		elseif skillId == "AXE_A3" then
			-- ★ 도끼 폭풍: Storm VFX 난도질 + Slam Cast VFX 3~4회 출력
			if #castTemplates > 0 then
				local stormCount = 14
				local stormDuration = 1.8  -- Spin 재생 시간 동안 퍼부음
				local spawnPos = hrp.Position + hrp.CFrame.LookVector * 5

				local anchor = Instance.new("Part")
				anchor.Size = Vector3.new(1, 1, 1)
				anchor.Transparency = 1
				anchor.Anchored = true
				anchor.CanCollide = false
				anchor.CanQuery = false
				anchor.CanTouch = false
				anchor.CFrame = CFrame.lookAt(spawnPos, spawnPos + hrp.CFrame.LookVector)
				anchor.Parent = workspace

				-- Slam Cast VFX (내려찍기 이펙트) 3~4회 섞어서 출력
				local slamTemplates = findVFXTemplates(castVFXFolder, "SkillAxe_Slam_Cast")
				if #slamTemplates > 0 then
					local slamCount = math.random(3, 4)
					for i = 1, slamCount do
						task.delay((i - 1) * (stormDuration / slamCount), function()
							if not anchor or not anchor.Parent then return end
							local rx = (math.random() - 0.5) * 5
							local ry = (math.random() - 0.5) * 3
							local rz = (math.random() - 0.5) * 5
							local slamAnchor = Instance.new("Part")
							slamAnchor.Size = Vector3.one
							slamAnchor.Transparency = 1
							slamAnchor.Anchored = true
							slamAnchor.CanCollide = false
							slamAnchor.CanQuery = false
							slamAnchor.CanTouch = false
							slamAnchor.CFrame = CFrame.new(spawnPos + Vector3.new(rx, ry, rz))
								* CFrame.Angles(0, math.rad(math.random(-30, 30)), 0)
							slamAnchor.Parent = workspace
							spawnVFX(slamTemplates[math.random(1, #slamTemplates)], slamAnchor, VFX_CAST_LIFETIME_FLURRY)
							Debris:AddItem(slamAnchor, VFX_CAST_LIFETIME_FLURRY + 0.5)
						end)
					end
				end

				for i = 1, stormCount do
					task.delay((i - 1) * (stormDuration / stormCount), function()
						if not anchor or not anchor.Parent then return end
						local tmpl = castTemplates[math.random(1, #castTemplates)]
						-- 랜덤 위치 오프셋 (반경 3스터드) + 랜덤 회전
						local rx = (math.random() - 0.5) * 6
						local ry = (math.random() - 0.5) * 4
						local rz = (math.random() - 0.5) * 6
						local offsetCF = CFrame.new(spawnPos + Vector3.new(rx, ry, rz))
							* CFrame.Angles(
								math.rad(math.random(-30, 30)),
								math.rad(math.random(-180, 180)),
								math.rad(math.random(-30, 30))
							)
						anchor.CFrame = offsetCF
						spawnVFX(tmpl, anchor, VFX_CAST_LIFETIME_FLURRY)
					end)
				end
				Debris:AddItem(anchor, stormDuration + VFX_CAST_LIFETIME_FLURRY + 0.5)
			end
		end
	elseif castVFXFolder and assetName then
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
			if skillId == "BOW_A2" then
				-- 속사: 짧게 5회 반복 재생
				task.spawn(function()
					for i = 1, 5 do
						playSound(castSoundTemplate, hrp)
						task.wait(0.18)
					end
				end)
			else
				playSound(castSoundTemplate, hrp)
			end
		end
	end

	-- 3. VFX 출력 후 딜레이 → 애니메이션 재생 (스트라이크/돌진은 VFX 선행)
	local animDelay = isShortVFX and 0.25 or 0.05
	task.delay(animDelay, function()
		if not humanoid or not humanoid.Parent then return end

		if skillId == "AXE_A3" then
			-- ★ 도끼 폭풍: Spin 재생 → 완료 후 Slam 재생 (별도 애니메이션 없음)
			local spinTrack = AnimationManager.play(humanoid, "SkillAxe_Spin", 0.05)
			if spinTrack then
				spinTrack.Priority = Enum.AnimationPriority.Action4
				spinTrack.Looped = false
				spinTrack.Stopped:Once(function()
					if not humanoid or not humanoid.Parent then return end
					local slamTrack = AnimationManager.play(humanoid, "SkillAxe_Slam", 0.05)
					if slamTrack then
						slamTrack.Priority = Enum.AnimationPriority.Action4
						slamTrack.Looped = false
					end
				end)
			end
		elseif animName then
			local track = AnimationManager.play(humanoid, animName, 0.05)
			if track then
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped = false
			end
		end
	end)

	-- ★ SWORD_A2 돌진: 위치 이동 제거 (애니메이션만 유지)
	-- if skillId == "SWORD_A2" and userId == player.UserId then
	-- 	performChargeDash(character, CHARGE_DISTANCE, CHARGE_DURATION)
	-- end

	-- 4. 피격 VFX + 사운드 (타겟 기준)
	if isAxeSkill and targetId then
		-- ★ AXE 스킬: 대상 유무와 관계없이 캐릭터 전방에 Hit VFX/Sound 출력
		-- A1 내려찍기: 애니메이션 진행 후 바닥 충격 (0.7초)
		-- A2 회전베기: 회전 중간 (0.4초)
		-- A3 도끼폭풍: Spin→Slam 후 찍기 타이밍 (Spin길이 + 0.5초)
		local hitDelay
		if skillId == "AXE_A1" then
			hitDelay = 0.7
		elseif skillId == "AXE_A3" then
			hitDelay = 2.0
		else
			hitDelay = 0.4
		end
		task.delay(hitDelay, function()
			if not hrp or not hrp.Parent then return end
			local hitPos = hrp.Position + hrp.CFrame.LookVector * 4
			local isAOE = (skillId == "AXE_A2" or skillId == "AXE_A3")
			local sizeScale = isAOE and 2 or 1

			if hitVFXFolder and assetName then
				local hitTemplates = findVFXTemplates(hitVFXFolder, assetName .. "_Hit")
				for _, tmpl in ipairs(hitTemplates) do
					local hitVfx = tmpl:Clone()
					if hitVfx:IsA("BasePart") then
						hitVfx.Anchored = true
						hitVfx.CanCollide = false
						hitVfx.CanQuery = false
						hitVfx.CanTouch = false
						hitVfx.CFrame = CFrame.new(hitPos)
						if hitVfx:IsA("Part") and not hitVfx:IsA("MeshPart") then
							hitVfx.Transparency = 1
						end
					end
					hitVfx.Parent = workspace
					if sizeScale > 1 then
						if hitVfx:IsA("BasePart") then
							hitVfx.Size = hitVfx.Size * sizeScale
						end
					end
					for _, d in hitVfx:GetDescendants() do
						if sizeScale > 1 and d:IsA("BasePart") then
							d.Size = d.Size * sizeScale
						end
						if d:IsA("ParticleEmitter") then
							if sizeScale > 1 then
								d.Size = NumberSequence.new({
									NumberSequenceKeypoint.new(0, (d.Size.Keypoints[1].Value) * sizeScale),
									NumberSequenceKeypoint.new(1, (d.Size.Keypoints[#d.Size.Keypoints].Value) * sizeScale),
								})
							end
							local bc = d:GetAttribute("BurstCount")
							if bc then d:Emit(bc)
							else d.Enabled = true
								task.delay(1.5, function()
									if d and d.Parent then d.Enabled = false end
								end)
							end
						end
					end
					Debris:AddItem(hitVfx, hitLife)
				end
			end
			if hitSoundFolder and assetName then
				local hitSndTmpl = hitSoundFolder:FindFirstChild(assetName .. "_Hit")
				if hitSndTmpl then
					local sndPart = Instance.new("Part")
					sndPart.Size = Vector3.one
					sndPart.Transparency = 1
					sndPart.Anchored = true
					sndPart.CanCollide = false
					sndPart.CanQuery = false
					sndPart.CanTouch = false
					sndPart.Position = hitPos
					sndPart.Parent = workspace
					local sfx = hitSndTmpl:Clone()
					sfx.Parent = sndPart
					sfx:Play()
					Debris:AddItem(sndPart, 3)
				end
			end
		end)
	elseif targetId then
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
