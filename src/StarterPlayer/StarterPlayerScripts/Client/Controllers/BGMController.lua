local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnConfig = require(Shared.Config.SpawnConfig)

local BGMController = {}

local initialized = false
local combatSound = nil
local zoneSound = nil
local combatActive = false
local currentZoneName = nil
local zonePollAccumulator = 0

local COMBAT_SOUND_NAME = "COMBAT_BGM"
local COMBAT_CHANNEL_NAME = "CombatBGMChannel"
local ZONE_CHANNEL_NAME = "ZoneBGMChannel"
local COMBAT_VOLUME = 0.14
local ZONE_VOLUME = 0.1
local FADE_TIME = 0.6
local ZONE_POLL_INTERVAL = 1.0

local ZONE_SOUND_NAMES = {
	GRASSLAND = "GRASSLAND_BGM",
	TROPICAL = "TROPICAL_BGM",
	DESERT = "DESERT_BGM",
	SNOW = "SNOW_BGM",
	SNOWFIELD = "SNOW_BGM",
	SNOWLAND = "SNOW_BGM",
}

local function findSoundSourceByName(soundName: string): Sound?
	local direct = SoundService:FindFirstChild(soundName)
	if direct and direct:IsA("Sound") then
		return direct
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local found = assets:FindFirstChild(soundName, true)
		if found and found:IsA("Sound") then
			return found
		end
	end

	return nil
end

local function findCombatSource(): Sound?
	return findSoundSourceByName(COMBAT_SOUND_NAME)
end

local function ensureCombatChannel(): Sound?
	if combatSound and combatSound.Parent then
		return combatSound
	end

	local source = findCombatSource()
	if not source then
		return nil
	end

	combatSound = SoundService:FindFirstChild(COMBAT_CHANNEL_NAME)
	if not combatSound or not combatSound:IsA("Sound") then
		combatSound = Instance.new("Sound")
		combatSound.Name = COMBAT_CHANNEL_NAME
		combatSound.Parent = SoundService
	end

	combatSound.SoundId = source.SoundId
	combatSound.Volume = 0
	combatSound.Looped = true
	combatSound.RollOffMaxDistance = 10000
	return combatSound
end

local function ensureZoneChannel(): Sound?
	if zoneSound and zoneSound.Parent then
		return zoneSound
	end

	zoneSound = SoundService:FindFirstChild(ZONE_CHANNEL_NAME)
	if not zoneSound or not zoneSound:IsA("Sound") then
		zoneSound = Instance.new("Sound")
		zoneSound.Name = ZONE_CHANNEL_NAME
		zoneSound.Parent = SoundService
	end

	zoneSound.Volume = 0
	zoneSound.Looped = true
	zoneSound.RollOffMaxDistance = 10000
	return zoneSound
end

local function tweenVolume(sound: Sound, volume: number)
	local tween = TweenService:Create(sound, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = volume,
	})
	tween:Play()
	return tween
end

local function startCombatBGM()
	local sound = ensureCombatChannel()
	if not sound then
		return
	end
	if not sound.IsPlaying then
		sound:Play()
	end
	tweenVolume(sound, COMBAT_VOLUME)
end

local function stopCombatBGM()
	local sound = combatSound
	if not sound or not sound.Parent then
		return
	end
	local tween = tweenVolume(sound, 0)
	task.delay(FADE_TIME + 0.05, function()
		if sound.Parent and not combatActive then
			sound:Stop()
		end
	end)
	return tween
end

local function stopZoneBGM()
	local sound = zoneSound
	if not sound or not sound.Parent then
		return
	end
	tweenVolume(sound, 0)
	task.delay(FADE_TIME + 0.05, function()
		if sound.Parent and (combatActive or not currentZoneName) then
			sound:Stop()
		end
	end)
end

local function playZoneBGM(zoneName: string?)
	currentZoneName = zoneName
	if combatActive then
		return
	end

	if not zoneName then
		stopZoneBGM()
		return
	end

	local soundName = ZONE_SOUND_NAMES[string.upper(zoneName)] or (string.upper(zoneName) .. "_BGM")
	local source = findSoundSourceByName(soundName)
	if not source then
		stopZoneBGM()
		return
	end

	local sound = ensureZoneChannel()
	if not sound then
		return
	end

	local nextSoundId = source.SoundId
	if sound.SoundId ~= nextSoundId then
		sound.SoundId = nextSoundId
		if sound.IsPlaying then
			sound:Stop()
		end
	end

	if not sound.IsPlaying then
		sound:Play()
	end
	tweenVolume(sound, ZONE_VOLUME)
end

local function refreshZoneBGM()
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local nextZone = SpawnConfig.GetZoneAtPosition(hrp.Position)
	if nextZone == currentZoneName then
		return
	end

	playZoneBGM(nextZone)
end

function BGMController.Init()
	if initialized then
		return
	end
	initialized = true

	NetClient.On("Combat.PlayerState.Changed", function(data)
		local nextState = type(data) == "table" and data.inCombat == true or false
		if combatActive == nextState then
			return
		end
		combatActive = nextState
		if combatActive then
			stopZoneBGM()
			startCombatBGM()
		else
			stopCombatBGM()
			playZoneBGM(currentZoneName)
		end
	end)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		combatActive = false
		stopCombatBGM()
		task.defer(function()
			refreshZoneBGM()
		end)
	end)

	RunService.Heartbeat:Connect(function(dt)
		zonePollAccumulator += dt
		if zonePollAccumulator < ZONE_POLL_INTERVAL then
			return
		end
		zonePollAccumulator = 0
		refreshZoneBGM()
	end)

	task.defer(function()
		refreshZoneBGM()
	end)
end

return BGMController
