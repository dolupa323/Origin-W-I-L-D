-- RadioStoryController.lua
-- 난파/조난 컨셉 무전기 튜토리얼 진행 컨트롤러

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Theme = require(script.Parent.Parent.UI.UITheme)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local LocaleService = require(script.Parent.Parent.Localization.LocaleService)

local RadioStoryController = {}
local C = Theme.Colors

local RADIO_MODEL_NAME = "Motorola DP4800"
local RADIO_SOUND_NAME = "RadioRingingLoop"
local RADIO_SOUND_FALLBACK = "rbxasset://sounds/electronicpingshort.wav"
local RADIO_STATIC_SOUND_NAME = "RadioDialogueStatic"
local RADIO_STATIC_SOUND_FALLBACK = ""
local RADIO_STATIC_VOLUME = 0.03

local initialized = false
local tutorialCompleted = false
local introCompleted = false
local completionPlayed = false
local dialogueActive = false
local dialogueMode = nil -- "intro" | "briefing" | "finale"
local dialogueIndex = 1
local sequence = {}

local ringingRequested = false
local pendingStatus = nil
local pendingBriefingStepKey = nil
local claimHandler = nil
local briefedStepKeys = {}
local stepInteractCounts = {}
local questGateChangedHandler = nil
local HINT_REPEAT_THRESHOLD = 2

local player = Players.LocalPlayer
local radioModel = nil
local dialogueGui = nil
local dialogueFrame = nil
local portraitImage = nil
local speakerLabel = nil
local lineLabel = nil
local hintLabel = nil
local blurEffect = nil
local radioMarker = nil
local markerPulseConn = nil
local dialogueViewportConn = nil
local dialogueCameraConn = nil
local dialogueLayoutConn = nil
local dialogueStaticSound = nil
local staticPulseEnabled = false

local INTRO_LINES = {
	{ speaker = "이안", speakerEn = "Ian", line = "치지직... 아, 아. 내 말 들리나?", lineEn = "Krrzz... Ah, ah. Can you hear me?" },
	{ speaker = "이안", speakerEn = "Ian", line = "응답해라.", lineEn = "Respond." },
	{ speaker = "이안", speakerEn = "Ian", line = "나는 1차 조사 파견대의 생존자, 이안이다.", lineEn = "I am Ian, a survivor from the first survey team." },
	{ speaker = "이안", speakerEn = "Ian", line = "방금 해안가에 수송선이 추락하는 걸 봤다.", lineEn = "I just saw a transport ship crash on the coast." },
	{ speaker = "이안", speakerEn = "Ian", line = "거기... 누구 살아남은 사람 있나?!", lineEn = "Over there... anyone alive?!" },
	{ speaker = "이안", speakerEn = "Ian", line = "다행히 살아남았군...! 하지만 기뻐할 때가 아니다.", lineEn = "Good, you survived... but this is no time to celebrate." },
	{ speaker = "이안", speakerEn = "Ian", line = "이곳은 우리가 알던 평범한 섬이 아니다. 괴물 같은 놈들이 우글거리는 곳이지.", lineEn = "This is not a normal island. It's crawling with monsters." },
	{ speaker = "이안", speakerEn = "Ian", line = "정신 똑바로 차려! 지금부터 내가 거기서 살아남는 법을 알려줄 테니, 무조건 내 말대로 움직여.", lineEn = "Stay sharp. I will tell you how to survive there, so follow my instructions." },
	{ speaker = "이안", speakerEn = "Ian", line = "무전이 울리면 즉시 확인해서 지시를 따라라. 알겠나?", lineEn = "When the radio rings, check it immediately and follow orders. Understood?" },
}

local FINALE_LINES = {
	{ speaker = "이안", speakerEn = "Ian", line = "기본적인 생존 준비는 끝났군. 제법인데.", lineEn = "You've finished the basic survival prep. Not bad." },
	{ speaker = "이안", speakerEn = "Ian", line = "이제야 정식으로 인사를 하겠군. 고대 생물들이 살아 숨 쉬는 이 미쳐버린 섬에 온 걸 환영한다, 후배.", lineEn = "Now a proper greeting. Welcome to this insane island where ancient creatures still roam, rookie." },
	{ speaker = "이안", speakerEn = "Ian", line = "어떻게든 살아남아서 나를 찾아와. 기다리겠다. 통신 끝.", lineEn = "Survive somehow and find me. I'll be waiting. Over and out." },
}

local TUTORIAL_STEP_EN = {
	COLLECT_BASICS = {
		currentStepText = "Gather 1 Small Stone and 1 Branch first",
		stepTip = "Grab anything useful first, but don't wander too far from the crash site.",
		stepVoiceIntro = "You won't survive a day barehanded. Search the ground and grab a small stone and a branch first.",
		stepVoiceHint = "Still not enough. Search around the wreckage a little more.",
		stepVoiceReady = "Good. That's enough. Let's craft a tool first.",
	},
	CRAFT_AXE = {
		currentStepText = "Craft a Crude Stone Axe",
		stepTip = "Open your bag and craft a tool. If you're short on materials, gather a little more nearby.",
		stepVoiceIntro = "Good, you've got materials. Make a crude stone axe with them. You die fast here without a weapon.",
		stepVoiceHint = "No rush, but secure that stone axe first.",
		stepVoiceReady = "Well done. Now go get some wood.",
	},
	GET_WOOD = {
		currentStepText = "Secure wood resources",
		stepTip = "Don't get greedy with huge trees. Start with an easy one.",
		stepVoiceIntro = "Axe ready? Then chop nearby trees first. Firewood comes first if you want to survive tonight.",
		stepVoiceHint = "Bring back one piece of wood or one log. Fast.",
		stepVoiceReady = "Good, wood secured. Next, food.",
	},
	KILL_DODO = {
		currentStepText = "Hunt for food",
		stepTip = "Hit once or twice then back off. Don't stand still and trade hits.",
		stepVoiceIntro = "You're getting hungry. Kill one nearby dodo. That's your first meal.",
		stepVoiceHint = "Just one dodo is enough. Don't overcommit.",
		stepVoiceReady = "Good kill. Prepare to light a fire now.",
	},
	BUILD_CAMPFIRE = {
		currentStepText = "Build a warmth point before night",
		stepTip = "Place it on flat open ground so you can escape quickly later.",
		stepVoiceIntro = "Don't tell me you'll eat raw meat. Use the wood and place a campfire. Fire is essential against cold and predators.",
		stepVoiceHint = "Just place one campfire. Choose the spot well.",
		stepVoiceReady = "Good. Fire is up. Now cook.",
	},
	COOK_MEAT = {
		currentStepText = "Cook 1 meat",
		stepTip = "Keep the fire fed with wood and eat before your condition drops.",
		stepVoiceIntro = "Is the fire burning? Put meat on it and cook. If your health drops, you can't even run.",
		stepVoiceHint = "Just one cooked meat. Quick and easy.",
		stepVoiceReady = "Okay, stomach filled. Time to mark your base.",
	},
	PLACE_TOTEM = {
		currentStepText = "Secure a base center point",
		stepTip = "Place it near a midpoint so future routes stay efficient.",
		stepVoiceIntro = "If you lose your way in this forest, you're done. Place a totem to mark your base.",
		stepVoiceHint = "One totem is enough. Pick the location carefully.",
		stepVoiceReady = "Good, base established. Last step: shelter.",
	},
	BUILD_LEAN_TO = {
		currentStepText = "Secure a sleep/respawn point",
		stepTip = "Keep it close enough to the campfire warmth, but don't block movement paths.",
		stepVoiceIntro = "Almost done. Build a lean-to before the night cold hits. Sleep there and lock your position so you can recover if you go down.",
		stepVoiceHint = "One shelter and you're done. Just a little more.",
		stepVoiceReady = "Done. Real survival starts now.",
	},
}

local questTokenNameCache = {}

local function buildIdLookup(tableModule)
	local out = {}
	if type(tableModule) ~= "table" then
		return out
	end
	for key, value in pairs(tableModule) do
		if type(value) == "table" and value.id then
			out[tostring(value.id)] = value
		elseif type(key) == "string" and type(value) == "table" and value.id == nil then
			out[key] = value
		end
	end
	return out
end

local itemLookup = {}
local facilityLookup = {}
local recipeLookup = {}
local creatureLookup = {}

do
	local dataFolder = ReplicatedStorage:FindFirstChild("Data")
	if dataFolder then
		local okItem, itemData = pcall(function()
			return require(dataFolder:WaitForChild("ItemData"))
		end)
		if okItem then
			itemLookup = buildIdLookup(itemData)
		end

		local okFacility, facilityData = pcall(function()
			return require(dataFolder:WaitForChild("FacilityData"))
		end)
		if okFacility then
			facilityLookup = buildIdLookup(facilityData)
		end

		local okRecipe, recipeData = pcall(function()
			return require(dataFolder:WaitForChild("RecipeData"))
		end)
		if okRecipe then
			recipeLookup = buildIdLookup(recipeData)
		end

		local okCreature, creatureData = pcall(function()
			return require(dataFolder:WaitForChild("CreatureData"))
		end)
		if okCreature then
			creatureLookup = buildIdLookup(creatureData)
		end
	end
end

local function resolveQuestTokenName(token: string): string
	local normalizedToken = tostring(token or "")
	local upperToken = string.upper(normalizedToken)
	local cached = questTokenNameCache[token]
	if cached ~= nil then
		return cached
	end

	local item = itemLookup[normalizedToken] or itemLookup[upperToken]
	if item and item.name then
		cached = UILocalizer.LocalizeDataText("ItemData", tostring(item.id or upperToken), "name", tostring(item.name))
		questTokenNameCache[token] = cached
		return cached
	end

	local facility = facilityLookup[normalizedToken] or facilityLookup[upperToken]
	if facility and facility.name then
		cached = UILocalizer.LocalizeDataText("FacilityData", tostring(facility.id or upperToken), "name", tostring(facility.name))
		questTokenNameCache[token] = cached
		return cached
	end

	local recipe = recipeLookup[normalizedToken] or recipeLookup[upperToken]
	if recipe and recipe.name then
		cached = UILocalizer.LocalizeDataText("RecipeData", tostring(recipe.id or upperToken), "name", tostring(recipe.name))
		questTokenNameCache[token] = cached
		return cached
	end

	local creature = creatureLookup[normalizedToken] or creatureLookup[upperToken]
	if creature and creature.name then
		cached = UILocalizer.LocalizeDataText("CreatureData", tostring(creature.id or upperToken), "name", tostring(creature.name))
		questTokenNameCache[token] = cached
		return cached
	end

	questTokenNameCache[token] = token
	return token
end

local function localizeDialogueRuntimeText(text: string?): string
	if type(text) ~= "string" or text == "" then
		return ""
	end

	local replaced = string.gsub(text, "([%a][%w_]+)", function(token)
		return resolveQuestTokenName(token)
	end)

	return UILocalizer.Localize(replaced)
end

local function localizeTutorialStepField(status, fieldName: string): string
	local base = status and status[fieldName]
	if type(base) ~= "string" then
		return ""
	end

	if LocaleService.GetLanguage() ~= "en" then
		return base
	end

	local stepKey = tostring(status and status.stepKey or "")
	local stepMap = TUTORIAL_STEP_EN[stepKey]
	if stepMap and type(stepMap[fieldName]) == "string" and stepMap[fieldName] ~= "" then
		return stepMap[fieldName]
	end

	return base
end

local function splitSpokenLines(text: string): {string}
	local out = {}
	if type(text) ~= "string" or text == "" then
		return out
	end

	local normalized = text
		:gsub("\r\n", "\n")
		:gsub("\n", " ")
		:gsub("%s+", " ")
		:gsub("([%.%!%?])%s*", "%1\n")

	for chunk in normalized:gmatch("[^\n]+") do
		local line = chunk:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			table.insert(out, line)
		end
	end

	if #out == 0 then
		table.insert(out, text)
	end

	return out
end

local function appendSpokenLines(lines: {any}, speaker: string, text: string)
	for _, line in ipairs(splitSpokenLines(text)) do
		table.insert(lines, { speaker = speaker, line = line })
	end
end

local function resolvePortraitImage(): string
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return "rbxassetid://0" end
	local story = assets:FindFirstChild("Story")
	if not story then return "rbxassetid://0" end
	local portrait = story:FindFirstChild("RadioSeniorPortrait")
	if not portrait then return "rbxassetid://0" end

	if portrait:IsA("Decal") then return portrait.Texture end
	if portrait:IsA("ImageLabel") or portrait:IsA("ImageButton") then return portrait.Image end
	if portrait:IsA("StringValue") then return portrait.Value end
	return "rbxassetid://0"
end

local function getRadioModel(): Instance?
	if radioModel and radioModel.Parent then
		return radioModel
	end
	radioModel = workspace:FindFirstChild(RADIO_MODEL_NAME, true)
	return radioModel
end

local function getRadioSoundParent(inst: Instance?): BasePart?
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart end
		return inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function findModelSound(model: Instance?, names: {string}): Sound?
	if not model then
		return nil
	end
	for _, name in ipairs(names) do
		local s = model:FindFirstChild(name, true)
		if s and s:IsA("Sound") then
			return s
		end
	end
	return nil
end

local function resolveStaticSoundId(model: Instance?): string
	if model then
		local custom = model:GetAttribute("RadioStaticSoundId")
		if type(custom) == "string" and custom ~= "" then
			return custom
		end
	end
	return RADIO_STATIC_SOUND_FALLBACK
end

local function resolveAlertSoundId(model: Instance?): string
	local modelSound = findModelSound(model, { "Radio Alert Sound", "Radio Loop Sound" })
	if modelSound and modelSound.SoundId ~= "" then
		return modelSound.SoundId
	end

	if model then
		local custom = model:GetAttribute("RadioLoopSoundId")
		if type(custom) == "string" and custom ~= "" then
			return custom
		end
	end
	return RADIO_SOUND_FALLBACK
end

local function ensureRingingSound(): Sound?
	if tutorialCompleted then return nil end

	local model = getRadioModel()
	local parentPart = getRadioSoundParent(model)
	if not parentPart then return nil end

	local sound = parentPart:FindFirstChild(RADIO_SOUND_NAME)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = RADIO_SOUND_NAME
		sound.Volume = 0.35
		sound.RollOffMaxDistance = 40
		sound.RollOffMinDistance = 8
		sound.Looped = true
		sound.Parent = parentPart
	end

	-- 호출 상태에서는 알림음을 사용한다.
	sound.SoundId = resolveAlertSoundId(model)

	local shouldPlay = ringingRequested and (not dialogueActive)

	if shouldPlay and not sound.IsPlaying then
		sound:Play()
	elseif (not shouldPlay) and sound.IsPlaying then
		sound:Stop()
	end

	return sound
end

local function ensureDialogueStaticSound(): Sound
	local model = getRadioModel()
	local modelStatic = findModelSound(model, { "Radio Static Sound", "RadioStaticSound", "Radio Noise Sound" })
	if modelStatic then
		dialogueStaticSound = modelStatic
		dialogueStaticSound.Looped = true
		dialogueStaticSound.Volume = math.min(dialogueStaticSound.Volume, RADIO_STATIC_VOLUME)
		return dialogueStaticSound
	end

	if dialogueStaticSound and dialogueStaticSound.Parent then
		dialogueStaticSound.SoundId = resolveStaticSoundId(model)
		return dialogueStaticSound
	end

	dialogueStaticSound = SoundService:FindFirstChild(RADIO_STATIC_SOUND_NAME)
	if not dialogueStaticSound then
		dialogueStaticSound = Instance.new("Sound")
		dialogueStaticSound.Name = RADIO_STATIC_SOUND_NAME
		dialogueStaticSound.Volume = RADIO_STATIC_VOLUME
		dialogueStaticSound.Looped = true
		dialogueStaticSound.Parent = SoundService
	end

	dialogueStaticSound.Volume = math.min(dialogueStaticSound.Volume, RADIO_STATIC_VOLUME)

	dialogueStaticSound.SoundId = resolveStaticSoundId(model)

	return dialogueStaticSound
end

local function setDialogueStaticPlaying(playing: boolean)
	if playing then
		if staticPulseEnabled then
			return
		end
		staticPulseEnabled = true

		task.spawn(function()
			while staticPulseEnabled do
				local sound = ensureDialogueStaticSound()
				if sound.SoundId == nil or sound.SoundId == "" then
					if sound.IsPlaying then
						sound:Stop()
					end
					break
				end

				if not sound.IsPlaying then
					sound:Play()
				end
				task.wait(1)

				if not staticPulseEnabled then
					break
				end

				if sound.IsPlaying then
					sound:Stop()
				end
				task.wait(1)
			end

			local sound = ensureDialogueStaticSound()
			if sound.IsPlaying then
				sound:Stop()
			end
		end)
	else
		staticPulseEnabled = false
		local sound = ensureDialogueStaticSound()
		if sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function ensureRadioMarker()
	local model = getRadioModel()
	if not model then
		return
	end

	if not radioMarker or not radioMarker.Parent then
		radioMarker = model:FindFirstChild("RadioBeaconHighlight")
		if not radioMarker then
			radioMarker = Instance.new("Highlight")
			radioMarker.Name = "RadioBeaconHighlight"
			radioMarker.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			radioMarker.FillColor = Color3.fromRGB(255, 90, 90)
			radioMarker.OutlineColor = Color3.fromRGB(255, 220, 120)
			radioMarker.FillTransparency = 0.7
			radioMarker.OutlineTransparency = 0.2
			radioMarker.Parent = model
		end
		radioMarker.Adornee = model
	end

	-- 과한 안내 간판은 제거하고 Highlight만 유지한다.
	local legacyBeacon = model:FindFirstChild("RadioBeaconBillboard")
	if legacyBeacon then
		legacyBeacon:Destroy()
	end

	if not markerPulseConn then
		markerPulseConn = RunService.Heartbeat:Connect(function()
			if not radioMarker or not radioMarker.Parent then
				return
			end
			local alpha = (math.sin(os.clock() * 4) + 1) * 0.5
			radioMarker.FillTransparency = 0.72 - (alpha * 0.22)
			radioMarker.OutlineTransparency = 0.25 - (alpha * 0.18)
		end)
	end
end

local function updateRadioMarkerVisibility()
	ensureRadioMarker()
	local show = ringingRequested and (not tutorialCompleted) and (not dialogueActive)
	if radioMarker then
		radioMarker.Enabled = show
	end
end

local function ensureBlur()
	if blurEffect and blurEffect.Parent then
		return
	end
	blurEffect = Lighting:FindFirstChild("RadioDialogueBlur")
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect")
		blurEffect.Name = "RadioDialogueBlur"
		blurEffect.Size = 0
		blurEffect.Parent = Lighting
	end
end

local function updateDialogueLayout()
	if not dialogueFrame or not dialogueFrame.Parent then
		return
	end

	local function safeClamp(value: number, minValue: number, maxValue: number): number
		if maxValue < minValue then
			maxValue = minValue
		end
		return math.clamp(value, minValue, maxValue)
	end

	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local panelHeight = safeClamp(
		math.floor(vp.Y * (vp.X < 900 and 0.22 or 0.24)),
		110,
		math.min(360, math.floor(vp.Y * 0.34))
	)
	local left = math.max(8, math.floor(vp.X * 0.01))
	local top = vp.Y - panelHeight - math.max(86, math.floor(vp.Y * 0.14))
	local portraitSize = safeClamp(
		math.floor(panelHeight * 1.34),
		110,
		math.min(420, math.floor(vp.Y * 0.42))
	)
	local portraitGap = math.max(4, math.floor(vp.X * 0.006))

	-- Keep both dialogue panel and portrait fully inside the viewport on mobile/pc.
	local maxPanelWidth = vp.X - (left * 2) - portraitSize - portraitGap
	local panelWidth = math.clamp(math.floor(vp.X * 0.78), 280, math.max(280, maxPanelWidth))

	dialogueFrame.Size = UDim2.new(0, panelWidth, 0, panelHeight)
	dialogueFrame.Position = UDim2.new(0, left, 0, top)

	if portraitImage then
		portraitImage.Size = UDim2.new(0, portraitSize, 0, portraitSize)
		portraitImage.Position = UDim2.new(0, left + panelWidth + portraitGap, 0, top + panelHeight)
		portraitImage.ZIndex = 10010
		portraitImage.Visible = dialogueActive
	end

	if speakerLabel then
		speakerLabel.Size = UDim2.new(1, -32, 0, math.floor(panelHeight * 0.24))
		speakerLabel.Position = UDim2.new(0, 16, 0, 10)
		speakerLabel.TextSize = math.clamp(math.floor(panelHeight * 0.21), 22, 34)
	end

	if lineLabel then
		lineLabel.Size = UDim2.new(1, -32, 0, math.floor(panelHeight * 0.44))
		lineLabel.Position = UDim2.new(0, 16, 0, math.floor(panelHeight * 0.26))
		lineLabel.TextSize = math.clamp(math.floor(panelHeight * 0.20), 24, 36)
	end

	if hintLabel then
		hintLabel.Size = UDim2.new(1, -32, 0, math.floor(panelHeight * 0.18))
		hintLabel.Position = UDim2.new(0, 16, 1, -math.floor(panelHeight * 0.2))
		hintLabel.TextSize = math.clamp(math.floor(panelHeight * 0.11), 14, 18)
	end
end

local function ensureDialogueUI()
	if dialogueGui and dialogueGui.Parent then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	dialogueGui = Instance.new("ScreenGui")
	dialogueGui.Name = "RadioDialogueGui"
	dialogueGui.ResetOnSpawn = false
	dialogueGui.IgnoreGuiInset = true
	dialogueGui.DisplayOrder = 10000
	dialogueGui.Parent = playerGui

	dialogueFrame = Instance.new("Frame")
	dialogueFrame.Name = "DialogueFrame"
	dialogueFrame.Size = UDim2.new(1, 0, 0.26, 0)
	dialogueFrame.Position = UDim2.new(0, 0, 0.66, 0)
	dialogueFrame.BackgroundColor3 = C.BG_PANEL
	dialogueFrame.BackgroundTransparency = 0.94
	dialogueFrame.BorderSizePixel = 0
	dialogueFrame.Visible = false
	dialogueFrame.ZIndex = 10000
	dialogueFrame.Parent = dialogueGui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 14)
	frameCorner.Parent = dialogueFrame

	local frameGradient = Instance.new("UIGradient")
	frameGradient.Rotation = 90
	frameGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.35, 0.3),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	frameGradient.Parent = dialogueFrame

	portraitImage = Instance.new("ImageLabel")
	portraitImage.Name = "Portrait"
	portraitImage.Size = UDim2.new(0, 220, 0, 220)
	portraitImage.AnchorPoint = Vector2.new(1, 1)
	portraitImage.Position = UDim2.new(1, -30, 1, -14)
	portraitImage.BackgroundTransparency = 1
	portraitImage.Image = resolvePortraitImage()
	portraitImage.ScaleType = Enum.ScaleType.Fit
	portraitImage.ImageTransparency = 0.06
	portraitImage.Visible = false
	portraitImage.Parent = dialogueGui

	speakerLabel = Instance.new("TextLabel")
	speakerLabel.Name = "Speaker"
	speakerLabel.Size = UDim2.new(1, -300, 0, 34)
	speakerLabel.Position = UDim2.new(0, 42, 0, 24)
	speakerLabel.BackgroundTransparency = 1
	speakerLabel.TextColor3 = Color3.fromRGB(210, 230, 255)
	speakerLabel.Font = Enum.Font.Highway
	speakerLabel.TextSize = 30
	speakerLabel.TextXAlignment = Enum.TextXAlignment.Left
	speakerLabel.Text = ""
	speakerLabel.ZIndex = 10001
	speakerLabel.Parent = dialogueFrame

	lineLabel = Instance.new("TextLabel")
	lineLabel.Name = "Line"
	lineLabel.Size = UDim2.new(1, -300, 0, 72)
	lineLabel.Position = UDim2.new(0, 42, 0, 64)
	lineLabel.BackgroundTransparency = 1
	lineLabel.TextColor3 = Color3.fromRGB(255, 236, 168)
	lineLabel.Font = Enum.Font.Gotham
	lineLabel.TextWrapped = true
	lineLabel.TextXAlignment = Enum.TextXAlignment.Left
	lineLabel.TextYAlignment = Enum.TextYAlignment.Top
	lineLabel.TextSize = 32
	lineLabel.Text = ""
	lineLabel.ZIndex = 10001
	lineLabel.Parent = dialogueFrame

	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.Size = UDim2.new(1, -300, 0, 24)
	hintLabel.Position = UDim2.new(0, 42, 1, -34)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextColor3 = Color3.fromRGB(220, 230, 240)
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = 16
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.Text = UILocalizer.Localize("R 또는 클릭으로 다음")
	hintLabel.ZIndex = 10001
	hintLabel.Parent = dialogueFrame

	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "ClickCatcher"
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.Text = ""
	clickCatcher.AutoButtonColor = false
	clickCatcher.ZIndex = 10002
	clickCatcher.Parent = dialogueFrame

	if not dialogueCameraConn then
		dialogueCameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			if dialogueViewportConn then
				dialogueViewportConn:Disconnect()
				dialogueViewportConn = nil
			end
			local cam = workspace.CurrentCamera
			if cam then
				dialogueViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateDialogueLayout)
			end
			updateDialogueLayout()
		end)
	end

	local cam = workspace.CurrentCamera
	if cam and not dialogueViewportConn then
		dialogueViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateDialogueLayout)
	end
	updateDialogueLayout()
	clickCatcher.MouseButton1Click:Connect(function()
		RadioStoryController.interact()
	end)
end

local function startSequence(modeName: string, lines: {any})
	if tutorialCompleted or dialogueActive or #lines == 0 then
		return
	end

	ensureDialogueUI()
	ensureBlur()
	if blurEffect then
		TweenService:Create(blurEffect, TweenInfo.new(0.2), { Size = 12 }):Play()
	end

	portraitImage.Image = resolvePortraitImage()
	portraitImage.Visible = true
	dialogueMode = modeName
	dialogueActive = true
	dialogueIndex = 1
	sequence = lines
	dialogueFrame.Visible = true
	if not dialogueLayoutConn then
		dialogueLayoutConn = RunService.RenderStepped:Connect(function()
			if dialogueActive then
				updateDialogueLayout()
			end
		end)
	end
	updateDialogueLayout()
	setDialogueStaticPlaying(true)
end

local function showCurrentLine()
	if not dialogueActive then return end
	local data = sequence[dialogueIndex]
	if not data then return end
	local speakerText = data.speaker or "선배 무전"
	local lineText = data.line or ""
	if LocaleService.GetLanguage() == "en" then
		speakerText = data.speakerEn or speakerText
		lineText = data.lineEn or lineText
	end

	speakerLabel.Text = localizeDialogueRuntimeText(speakerText)
	lineLabel.Text = localizeDialogueRuntimeText(lineText)
	hintLabel.Text = localizeDialogueRuntimeText(data.hint or "R 또는 클릭으로 다음")

	lineLabel.TextTransparency = 1
	TweenService:Create(lineLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
end

local function closeDialogue()
	dialogueActive = false
	dialogueMode = nil
	sequence = {}
	setDialogueStaticPlaying(false)
	if blurEffect then
		TweenService:Create(blurEffect, TweenInfo.new(0.2), { Size = 0 }):Play()
	end
	if dialogueFrame then
		dialogueFrame.Visible = false
	end
	if portraitImage then
		portraitImage.Visible = false
	end
	if dialogueLayoutConn then
		dialogueLayoutConn:Disconnect()
		dialogueLayoutConn = nil
	end
end

function RadioStoryController.Init()
	if initialized then return end
	ringingRequested = true -- 첫 진입 시 무전기 호출음
	ensureRingingSound()
	updateRadioMarkerVisibility()
	initialized = true
	print("[RadioStoryController] Initialized")
end

function RadioStoryController.setClaimHandler(fn)
	claimHandler = fn
end

function RadioStoryController.setQuestGateChangedHandler(fn)
	questGateChangedHandler = fn
end

function RadioStoryController.syncTutorialStatus(status)
	pendingStatus = status

	if type(status) ~= "table" then
		return
	end

	if status.completed then
		if not completionPlayed then
			ringingRequested = true
		else
			tutorialCompleted = true
			ringingRequested = false
		end
		pendingBriefingStepKey = nil
		stepInteractCounts = {}
		ensureRingingSound()
		updateRadioMarkerVisibility()
		return
	end

	if not introCompleted then
		ringingRequested = true
		ensureRingingSound()
		updateRadioMarkerVisibility()
		return
	end

	if status.active then
		if pendingBriefingStepKey ~= status.stepKey then
			pendingBriefingStepKey = status.stepKey
			if status.stepKey then
				stepInteractCounts[status.stepKey] = 0
			end
			ringingRequested = briefedStepKeys[status.stepKey] ~= true
		end
	end

	ensureRingingSound()
	updateRadioMarkerVisibility()
end

function RadioStoryController.isCompleted(): boolean
	return tutorialCompleted
end

function RadioStoryController.isIntroDone(): boolean
	return introCompleted
end

function RadioStoryController.isDialogueActive(): boolean
	return dialogueActive
end

function RadioStoryController.shouldConsumeInteractKey(): boolean
	return dialogueActive
end

function RadioStoryController.shouldShowQuestUI(status): boolean
	if tutorialCompleted then
		return false
	end

	if not introCompleted then
		return false
	end

	if type(status) ~= "table" or status.active ~= true then
		return false
	end

	return true
end

function RadioStoryController.ensureRinging()
	ensureRingingSound()
	updateRadioMarkerVisibility()
end

function RadioStoryController.interact()
	if tutorialCompleted and completionPlayed then
		return
	end

	if not dialogueActive then
		if pendingStatus and pendingStatus.completed == true and not completionPlayed then
			ringingRequested = false
			ensureRingingSound()
			updateRadioMarkerVisibility()
			startSequence("finale", FINALE_LINES)
			showCurrentLine()
			return
		end

		if not introCompleted then
			ringingRequested = false
			ensureRingingSound()
			updateRadioMarkerVisibility()
			startSequence("intro", INTRO_LINES)
			showCurrentLine()
			return
		end

		if pendingStatus and pendingStatus.active and pendingStatus.stepKey and pendingBriefingStepKey == pendingStatus.stepKey then
			ringingRequested = false
			ensureRingingSound()
			updateRadioMarkerVisibility()
			local lines = {}
			local stepKey = pendingStatus.stepKey
			local wasBriefed = briefedStepKeys[stepKey] == true

			if not wasBriefed then
				local stepVoiceIntro = localizeTutorialStepField(pendingStatus, "stepVoiceIntro")
				if stepVoiceIntro ~= "" then
					appendSpokenLines(lines, "이안", stepVoiceIntro)
				end
				local stepTip = localizeTutorialStepField(pendingStatus, "stepTip")
				if stepTip ~= "" then
					appendSpokenLines(lines, "이안", stepTip)
				end
				local currentStepText = localizeTutorialStepField(pendingStatus, "currentStepText")
				if #lines == 0 and currentStepText ~= "" then
					appendSpokenLines(lines, "이안", currentStepText)
				end
				stepInteractCounts[stepKey] = 0
			else
				local tries = (stepInteractCounts[stepKey] or 0) + 1
				stepInteractCounts[stepKey] = tries

				if pendingStatus.stepReady == true then
					local stepVoiceReady = localizeTutorialStepField(pendingStatus, "stepVoiceReady")
					if stepVoiceReady ~= "" then
						appendSpokenLines(lines, "이안", stepVoiceReady)
					else
						local stepTip = localizeTutorialStepField(pendingStatus, "stepTip")
						if stepTip ~= "" then
							appendSpokenLines(lines, "이안", stepTip)
						end
					end
					stepInteractCounts[stepKey] = 0
				elseif tries >= HINT_REPEAT_THRESHOLD then
					local stepVoiceHint = localizeTutorialStepField(pendingStatus, "stepVoiceHint")
					if stepVoiceHint ~= "" then
						appendSpokenLines(lines, "이안", stepVoiceHint)
					else
						local stepTip = localizeTutorialStepField(pendingStatus, "stepTip")
						local currentStepText = localizeTutorialStepField(pendingStatus, "currentStepText")
						if stepTip ~= "" then
							appendSpokenLines(lines, "이안", stepTip)
						elseif currentStepText ~= "" then
							appendSpokenLines(lines, "이안", currentStepText)
						end
					end
					stepInteractCounts[stepKey] = 0
				else
					local stepTip = localizeTutorialStepField(pendingStatus, "stepTip")
					local currentStepText = localizeTutorialStepField(pendingStatus, "currentStepText")
					if stepTip ~= "" then
						appendSpokenLines(lines, "이안", stepTip)
					elseif currentStepText ~= "" then
						appendSpokenLines(lines, "이안", currentStepText)
					end
				end
			end

			if #lines == 0 then
				return
			end
			startSequence("briefing", lines)
			showCurrentLine()
			return
		end

		return
	end

	dialogueIndex += 1
	if dialogueIndex <= #sequence then
		showCurrentLine()
		return
	end

	local finishedMode = dialogueMode
	closeDialogue()
	setDialogueStaticPlaying(false)

	if finishedMode == "intro" then
		introCompleted = true
		if pendingStatus and pendingStatus.active and pendingStatus.stepKey then
			pendingBriefingStepKey = pendingStatus.stepKey
			ringingRequested = true
			ensureRingingSound()
			updateRadioMarkerVisibility()
		end
		if questGateChangedHandler then
			questGateChangedHandler()
		end
	elseif finishedMode == "finale" then
		completionPlayed = true
		tutorialCompleted = true
		ringingRequested = false
		ensureRingingSound()
		updateRadioMarkerVisibility()
		if questGateChangedHandler then
			questGateChangedHandler()
		end
	elseif finishedMode == "briefing" then
		if pendingStatus and pendingStatus.stepKey then
			briefedStepKeys[pendingStatus.stepKey] = true
		end
		ringingRequested = false
		ensureRingingSound()
		updateRadioMarkerVisibility()
		if questGateChangedHandler then
			questGateChangedHandler()
		end
	end
end

return RadioStoryController
