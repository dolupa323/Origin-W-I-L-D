-- AnimationManager.lua
-- 자산(Assets) 폴더의 애니메이션 개체를 관리하는 중앙 관리자
-- 하드코딩된 ID 대신 애니메이션 이름을 사용하여 재생하며, 트랙을 캐싱하여 64개 한계 초과를 방지

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationManager = {}

--========================================
-- Constants
--========================================
local ASSETS_PATH = "Assets/Animations"

--========================================
-- Internal Cache
--========================================
-- [humanoid] = { [animName] = AnimationTrack }
local trackCache = {}

--========================================
-- Internal Helpers
--========================================

--- 애니메이션 개체 찾기
local function findAnimation(animName: string): Animation?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	
	local animFolder = assets:FindFirstChild("Animations")
	if not animFolder then return nil end
	
	return animFolder:FindFirstChild(animName, true) -- 재귀적으로 찾기
end

--========================================
-- Public API
--========================================

--- 애니메이션 로드 및 트랙 반환 (캐싱 포함)
function AnimationManager.load(humanoid: Humanoid, animName: string): AnimationTrack?
	if not humanoid or humanoid.Health <= 0 then return nil end
	
	-- 1. 캐시 확인
	if not trackCache[humanoid] then
		trackCache[humanoid] = {}
		-- Humanoid가 제거될 때 캐시 정리
		humanoid.AncestryChanged:Connect(function(_, parent)
			if not parent then
				trackCache[humanoid] = nil
			end
		end)
	end
	
	if trackCache[humanoid][animName] then
		return trackCache[humanoid][animName]
	end

	-- 2. 애니메이션 객체 찾기
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	
	local animObject = findAnimation(animName)
	if not animObject then
		-- 너무 잦은 경고 방지를 위해 캐시에 nil 기록 (한 번만 경고)
		trackCache[humanoid][animName] = false
		warn(string.format("[AnimationManager] Animation '%s' not found", animName))
		return nil
	elseif trackCache[humanoid][animName] == false then
		return nil
	end
	
	-- 3. 로드 및 캐시 저장
	local success, track = pcall(function()
		return animator:LoadAnimation(animObject)
	end)
	
	if success and track then
		trackCache[humanoid][animName] = track
		return track
	else
		warn(string.format("[AnimationManager] Failed to load animation '%s' for '%s'", animName, humanoid.Parent and humanoid.Parent.Name or "Unknown"))
		return nil
	end
end

--- 애니메이션 즉시 재생
function AnimationManager.play(humanoid: Humanoid, animName: string, fadeTime: number?, weight: number?, speed: number?): AnimationTrack?
	local track = AnimationManager.load(humanoid, animName)
	if track then
		if not track.IsPlaying then
			track:Play(fadeTime or 0.1, weight, speed)
		end
		return track
	end
	return nil
end

--- 애니메이션 중지
function AnimationManager.stop(humanoid: Humanoid, animName: string, fadeTime: number?)
	if trackCache[humanoid] and trackCache[humanoid][animName] then
		local track = trackCache[humanoid][animName]
		if track and track.IsPlaying then
			track:Stop(fadeTime or 0.1)
		end
	end
end

return AnimationManager
