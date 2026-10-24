--[[
	SmoothTargetAssist  (LocalScript)
	Place in: StarterPlayer > StarterPlayerScripts
	Use only in an experience you own or are authorized to modify.

	Client-side camera assistance, ESP overlay, and full-bright lighting, with a control panel.
	The script is split into labelled sections:

	  1. SERVICES            6. PLAYER   (player list, team / alive validation)
	  2. CONFIG              7. AIM      (target selection, prediction, camera)
	  3. CONSTANTS           8. VISUAL   (FOV circle)
	  4. STATE               9. ESP      (name, distance, health, skeleton, look line, head circle, glow)
	  5. UTILITIES          10. LIGHTING (full bright)
	                        11. SHUTDOWN (permanent close + cleanup)
	                        12. GUI      (tabs: Aim / ESP / Visual / Player / Keys)
	                        13. MAIN LOOP, 14. PUBLIC API, 15. INIT

	Panel: drag the title bar, "–" minimizes to a small pill, "×" permanently shuts the script
	down (render callback unbound, connections disconnected, tweens cancelled, GUI and ESP
	destroyed, lighting restored).

	Hotkeys (rebindable in the Keys tab): SystemToggleKey toggles the aim assist, GuiToggleKey
	minimizes or restores the panel, ESPToggleKey and FullBrightToggleKey are off by default.

	Public API on shared.SmoothTargetAssist: Destroy, SetConfig, GetConfig, Toggle, SetEnabled,
	SetMinimized, IsActive, GetTarget.

	Not run in Roblox Studio by the author; test it in your own place before shipping.
]]

--------------------------------------------------------------------------------
-- 1. SERVICES
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local StatsService = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[SmoothTargetAssist] Must run as a LocalScript (client).")
	return
end

--------------------------------------------------------------------------------
-- 2. CONFIG  (all values are validated by sanitizeConfig)
--------------------------------------------------------------------------------
local Config = {
	-- General ---------------------------------------------------------------
	Enabled = true,                                -- Aim assist master switch.
	SystemToggleKey = Enum.KeyCode.RightControl,   -- Toggles aim assist. false = none.
	GuiToggleKey = Enum.KeyCode.RightShift,        -- Minimize / restore panel. false = none.
	ESPToggleKey = false,                          -- Toggles ESP. false = none.
	FullBrightToggleKey = false,                   -- Toggles full bright. false = none.
	UIStartMinimized = false,
	Debug = false,

	-- Aim: input ------------------------------------------------------------
	ActivationInput = Enum.UserInputType.MouseButton2, -- Enum.UserInputType or Enum.KeyCode.
	ActivationMode = "Hold",                       -- "Hold" or "Toggle".
	TargetLock = true,
	LockBreakFOVMultiplier = 1.35,                 -- Locked target released beyond FOVRadius * this.
	SwitchCooldown = 0.25,                         -- Seconds before switching when TargetLock is off.

	-- Aim: selection --------------------------------------------------------
	TargetPart = "Head",                           -- "Head", "UpperTorso", "HumanoidRootPart", ...
	AllowPartFallback = true,
	TargetPartFallbacks = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
	SelectionPriority = "Crosshair",               -- "Crosshair", "Distance", "Health".
	MaxDistance = 800,                             -- Aim range in studs.
	FOVRadius = 150,                               -- Pixels.
	FOVCenter = "Viewport",                        -- "Viewport" or "Mouse".

	-- Aim: camera motion ----------------------------------------------------
	-- CameraSmoothing = responsiveness in 1/second. ~5 soft, ~10 balanced, ~20+ firm, 0 = instant.
	CameraSmoothing = 10,
	MaxTurnRate = 540,                             -- Degrees/second cap (0 = no cap).
	EngageEaseTime = 0.15,
	DeadzoneDegrees = 0.15,
	ApplyToScriptableCamera = false,

	-- Aim: prediction -------------------------------------------------------
	Prediction = false,
	PredictionFactor = 0.10,                       -- Seconds of lead.
	MaxPredictionTime = 0.35,

	-- Player filters (used by Aim AND ESP) ----------------------------------
	TeamCheck = true,                              -- Skip teammates.
	TargetNeutralPlayers = true,                   -- Neutral / unassigned players: true = included.
	TeamAttribute = "",                            -- Optional player attribute for custom teams.
	CustomTeamCheck = false,                       -- Optional function(player) -> true if teammate.
	AliveCheck = true,
	MinHealth = 0,
	IgnoreForceField = false,

	-- Aim: visibility -------------------------------------------------------
	VisibilityCheck = true,
	VisibilityIgnoreTransparency = 0.9,

	-- Visual: FOV circle ----------------------------------------------------
	ShowFOV = true,
	ShowFOVOnlyWhenActive = false,
	FOVColor = Color3.fromRGB(255, 255, 255),
	FOVActiveColor = Color3.fromRGB(120, 220, 160),
	FOVThickness = 1.5,
	FOVTransparency = 0.45,

	-- Visual: lighting ------------------------------------------------------
	FullBright = false,
	FullBrightLevel = 2,                           -- Lighting.Brightness while full bright is on.

	-- ESP -------------------------------------------------------------------
	ESPEnabled = true,
	ESPMaxDistance = 2000,                         -- Studs, 0 - 20000 (0 shows nothing).
	ESPShowName = true,
	ESPShowDistance = true,
	ESPShowHealth = false,
	ESPShowSkeleton = true,
	ESPShowLookLine = true,                        -- Line showing where the player is facing.
	ESPShowHeadCircle = true,
	ESPHighlight = false,                          -- Outline glow (Roblox limits visible Highlights).
	ESPColor = Color3.fromRGB(255, 110, 110),
	ESPTeamColors = false,                         -- Use each player's team color instead of ESPColor.
	ESPUseDisplayName = false,
	ESPThickness = 1.5,
	ESPTransparency = 0.1,                         -- 0 = opaque.
	ESPTextSize = 13,
	ESPLookLength = 10,                            -- Studs.

	-- Loot / world item ESP -------------------------------------------------
	LootESPEnabled = true,
	LootESPMaxDistance = 400,                      -- Studs.
	LootESPShowDistance = true,
	LootESPShowContainers = true,
	LootESPShowWeapons = true,
	LootESPShowAmmo = true,
	LootESPShowImportant = true,
	LootESPShowGeneral = true,
	LootESPLootBagColor = Color3.fromRGB(255, 215, 0),
	LootESPWeaponColor = Color3.fromRGB(255, 100, 100),
	LootESPAmmoColor = Color3.fromRGB(255, 210, 80),
	LootESPImportantColor = Color3.fromRGB(255, 50, 255),
	LootESPGeneralColor = Color3.fromRGB(0, 230, 255),
	LootESPContainerColor = Color3.fromRGB(120, 220, 160),
	-- Persistence / utility -------------------------------------------------
	AutoSaveEnabled = true,
	ThemePreset = "Obsidian Gold",
	CrosshairEnabled = false,
	CrosshairColor = Color3.fromRGB(255, 255, 255),
	CrosshairSize = 16,
	CrosshairGap = 5,
	CrosshairThickness = 2,
	FOVChangerEnabled = false,
	CustomFOV = 90,
}
local DEFAULT_CONFIG = table.clone(Config)

--------------------------------------------------------------------------------
-- 3. CONSTANTS
--------------------------------------------------------------------------------
local SHARED_KEY = "SmoothTargetAssist"
local OVERLAY_GUI_NAME = "SmoothTargetAssist_Overlay"
local PANEL_GUI_NAME = "SmoothTargetAssist_Panel"
local ESP_FOLDER_NAME = "SmoothTargetAssist_ESP"
local LOOT_ESP_FOLDER_NAME = "SmoothTargetAssist_LootESP"
local RENDER_NAME = "SmoothTargetAssist_Render"
local CONFIG_FILE = "HushScript_Config.json"
local MAX_RAY_STEPS = 6
local MAX_VALID_SPEED = 2000
local MAX_FRAME_ERRORS = 5
local MAX_LINE_LENGTH = 6000
local ESP_VIEW_MARGIN = 600
local LOOT_FAR_THROTTLE_DISTANCE = 1000
local LOOT_FAR_THROTTLE_INTERVAL = 0.25
local TAB_NAMES = { "Aim", "ESP", "Visual", "Loot & Items", "Player", "Keys" }

local Theme = {
	Panel = Color3.fromRGB(24, 26, 32),
	Title = Color3.fromRGB(32, 35, 43),
	Card = Color3.fromRGB(36, 39, 48),
	Stroke = Color3.fromRGB(58, 62, 74),
	Text = Color3.fromRGB(232, 235, 242),
	SubText = Color3.fromRGB(140, 146, 160),
	Accent = Color3.fromRGB(110, 160, 255),
	OnAccent = Color3.fromRGB(16, 20, 30),
	Good = Color3.fromRGB(120, 220, 160),
	Warn = Color3.fromRGB(255, 205, 100),
	Off = Color3.fromRGB(110, 114, 128),
	Danger = Color3.fromRGB(235, 90, 90),
	SwitchOff = Color3.fromRGB(70, 74, 88),
	White = Color3.fromRGB(255, 255, 255),
	Black = Color3.fromRGB(0, 0, 0),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local SWATCHES = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(120, 220, 160),
	Color3.fromRGB(255, 214, 102),
	Color3.fromRGB(255, 110, 110),
	Color3.fromRGB(180, 140, 255),
}

local R15_BONES = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local MAX_BONES = #R15_BONES

local LIGHTING_PROPS = {
	"Brightness", "ClockTime", "FogStart", "FogEnd", "GlobalShadows", "Ambient", "OutdoorAmbient",
}

local BOOL_DEFAULTS = {
	Enabled = true, Debug = false, UIStartMinimized = false,
	TargetLock = true, AllowPartFallback = true, Prediction = false, ApplyToScriptableCamera = false,
	TeamCheck = true, TargetNeutralPlayers = true, AliveCheck = true, IgnoreForceField = false,
	VisibilityCheck = true, ShowFOV = true, ShowFOVOnlyWhenActive = false, FullBright = false,
	ESPEnabled = true, ESPShowName = true, ESPShowDistance = true, ESPShowHealth = false,
	ESPShowSkeleton = true, ESPShowLookLine = true, ESPShowHeadCircle = true, ESPHighlight = false,
	ESPTeamColors = false, ESPUseDisplayName = false,
	LootESPEnabled = true, LootESPShowDistance = true, LootESPShowContainers = true,
	LootESPShowWeapons = true, LootESPShowAmmo = true, LootESPShowImportant = true, LootESPShowGeneral = true,
	AutoSaveEnabled = true, CrosshairEnabled = false, FOVChangerEnabled = false,
}
-- { key, min, max, default }
local NUMBER_RULES = {
	{ "LockBreakFOVMultiplier", 1, 5, 1.35 }, { "SwitchCooldown", 0, 5, 0.25 },
	{ "MaxDistance", 1, 20000, 800 }, { "FOVRadius", 5, 2000, 150 },
	{ "CameraSmoothing", 0, 200, 10 }, { "MaxTurnRate", 0, 20000, 540 },
	{ "EngageEaseTime", 0, 5, 0.15 }, { "DeadzoneDegrees", 0, 45, 0.15 },
	{ "PredictionFactor", 0, 2, 0.10 }, { "MaxPredictionTime", 0, 2, 0.35 },
	{ "MinHealth", 0, 1e6, 0 }, { "VisibilityIgnoreTransparency", 0, 1, 0.9 },
	{ "FOVThickness", 0.5, 10, 1.5 }, { "FOVTransparency", 0, 1, 0.45 },
	{ "FullBrightLevel", 0.5, 5, 2 },
	{ "ESPMaxDistance", 0, 20000, 2000 }, { "ESPLookLength", 1, 100, 10 },
	{ "ESPThickness", 0.5, 6, 1.5 }, { "ESPTransparency", 0, 0.9, 0.1 },
	{ "ESPTextSize", 9, 28, 13 },
	{ "LootESPMaxDistance", 50, 20000, 400 },
	{ "CrosshairSize", 4, 64, 16 }, { "CrosshairGap", 0, 32, 5 },
	{ "CrosshairThickness", 1, 8, 2 }, { "CustomFOV", 60, 120, 90 },
}
local COLOR_DEFAULTS = {
	FOVColor = Color3.fromRGB(255, 255, 255),
	FOVActiveColor = Color3.fromRGB(120, 220, 160),
	ESPColor = Color3.fromRGB(255, 110, 110),
	LootESPLootBagColor = Color3.fromRGB(255, 215, 0),
	LootESPWeaponColor = Color3.fromRGB(255, 100, 100),
	LootESPAmmoColor = Color3.fromRGB(255, 210, 80),
	LootESPImportantColor = Color3.fromRGB(255, 50, 255),
	LootESPGeneralColor = Color3.fromRGB(0, 230, 255),
	LootESPContainerColor = Color3.fromRGB(120, 220, 160),
	CrosshairColor = Color3.fromRGB(255, 255, 255),
}
local KEY_FIELDS = { "SystemToggleKey", "GuiToggleKey", "ESPToggleKey", "FullBrightToggleKey" }

--------------------------------------------------------------------------------
-- 4. STATE
--------------------------------------------------------------------------------
local closed = false
local camera = Workspace.CurrentCamera
local connections = {}
local activeTweens = {}
local refreshers = {}
local playerList = Players:GetPlayers()
local frameErrors = 0
local styleVersion = 0

-- Aim
local active = false
local currentTarget = nil
local acquiredAt = 0
local engageBlend = 0
local smoothedVelocity = Vector3.zero
local velocityValid = false
local viewCenter = Vector2.zero
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local ignoreList = {}

-- Visual
local visAlpha = 0
local lockBlend = 0
local activeBlend = 0
local enabledBlend = 1
local displayRadius = 150
local originalCameraFOV = nil
local aimDefaultFOV = nil
local aimFOVScale = 1

-- ESP
local espObjects = {}
local espFolder = nil
local espShown = 0

-- Loot / world item ESP
local lootEspObjects = {}
local lootEspFolder = nil
local lootFolders = {}

-- Lighting
local savedLighting = nil
local savedAtmosphere = nil
local lightingTimer = 0

-- GUI
local ui = nil
local minimized = false
local animToken = 0
local panelPos = Vector2.new(16, 64)
local panelSize = Vector2.new(320, 460)
local activeDrag = nil
local dragScroll = nil
local listeningBind = nil
local lastStatusText = nil
local lastStatusColor = nil
local statsTimer = 0
local fpsSample = 60
local setMinimized = nil -- assigned when the GUI is built

--------------------------------------------------------------------------------
-- 5. UTILITIES
--------------------------------------------------------------------------------
local function debugLog(...)
	if Config.Debug then
		print("[SmoothTargetAssist]", ...)
	end
end

local function track(connection)
	table.insert(connections, connection)
	return connection
end

local function approach(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function toBool(value, default)
	if type(value) == "boolean" then
		return value
	end
	return default
end

local function clampNumber(value, minValue, maxValue, default)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	return math.clamp(value, minValue, maxValue)
end

local function pickString(value, valid, default)
	for _, option in ipairs(valid) do
		if value == option then
			return value
		end
	end
	return default
end

local saveToken = 0
local function persistenceAvailable()
	return type(writefile) == "function" and type(readfile) == "function"
end

local function encodeConfig()
	local result = {}
	for key, value in pairs(Config) do
		local kind = typeof(value)
		if kind == "boolean" or kind == "number" or type(value) == "string" then
			result[key] = value
		elseif kind == "Color3" then
			result[key] = { __color = value:ToHex() }
		end
	end
	return result
end

local function saveConfigNow()
	if not Config.AutoSaveEnabled or not persistenceAvailable() then
		return
	end
	pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(encodeConfig()))
	end)
end

local function scheduleConfigSave()
	if not Config.AutoSaveEnabled or not persistenceAvailable() then
		return
	end
	saveToken += 1
	local token = saveToken
	task.delay(0.5, function()
		if not closed and token == saveToken then
			saveConfigNow()
		end
	end)
end

local function loadConfig()
	if not persistenceAvailable() then
		return
	end
	pcall(function()
		local decoded = HttpService:JSONDecode(readfile(CONFIG_FILE))
		if type(decoded) ~= "table" then
			return
		end
		for key, value in pairs(decoded) do
			if Config[key] ~= nil then
				if type(value) == "table" and value.__color then
					local ok, color = pcall(Color3.fromHex, value.__color)
					if ok then Config[key] = color end
				elseif type(value) == typeof(Config[key]) then
					Config[key] = value
				end
			end
		end
	end)
end

local function isValidBinding(value)
	return typeof(value) == "EnumItem"
		and (value.EnumType == Enum.KeyCode or value.EnumType == Enum.UserInputType)
end

local function bindingName(binding)
	if typeof(binding) ~= "EnumItem" then
		return "None"
	end
	if binding == Enum.UserInputType.MouseButton1 then
		return "LMB"
	elseif binding == Enum.UserInputType.MouseButton2 then
		return "RMB"
	elseif binding == Enum.UserInputType.MouseButton3 then
		return "MMB"
	end
	return binding.Name
end

local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function tween(instance, duration, props)
	if closed or not instance then
		return nil
	end
	local t = TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	activeTweens[t] = true
	t.Completed:Once(function()
		activeTweens[t] = nil
	end)
	t:Play()
	return t
end

local function sanitizeConfig()
	local c = Config

	for key, default in pairs(BOOL_DEFAULTS) do
		c[key] = toBool(c[key], default)
	end
	for _, rule in ipairs(NUMBER_RULES) do
		c[rule[1]] = clampNumber(c[rule[1]], rule[2], rule[3], rule[4])
	end
	for key, default in pairs(COLOR_DEFAULTS) do
		if typeof(c[key]) ~= "Color3" then
			c[key] = default
		end
	end
	for _, key in ipairs(KEY_FIELDS) do
		if c[key] ~= false and not isValidBinding(c[key]) then
			c[key] = false
		end
	end
	c.ESPTextSize = math.floor(c.ESPTextSize + 0.5)

	if not isValidBinding(c.ActivationInput) then
		c.ActivationInput = Enum.UserInputType.MouseButton2
	end
	c.ActivationMode = pickString(c.ActivationMode, { "Hold", "Toggle" }, "Hold")
	c.SelectionPriority = pickString(c.SelectionPriority, { "Crosshair", "Distance", "Health" }, "Crosshair")
	c.FOVCenter = pickString(c.FOVCenter, { "Viewport", "Mouse" }, "Viewport")

	if type(c.TargetPart) ~= "string" or c.TargetPart == "" then
		c.TargetPart = "Head"
	end
	local fallbacks = {}
	if type(c.TargetPartFallbacks) == "table" then
		for _, name in ipairs(c.TargetPartFallbacks) do
			if type(name) == "string" and name ~= "" then
				table.insert(fallbacks, name)
			end
		end
	end
	if #fallbacks == 0 then
		fallbacks = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
	end
	c.TargetPartFallbacks = fallbacks

	if type(c.TeamAttribute) ~= "string" then
		c.TeamAttribute = ""
	end
	if type(c.CustomTeamCheck) ~= "function" then
		c.CustomTeamCheck = false
	end
end

local function resetConfig()
	for key, value in pairs(DEFAULT_CONFIG) do
		Config[key] = value
	end
	sanitizeConfig()
	saveToken += 1
	saveConfigNow()
end

local function inputMatches(input, binding)
	if typeof(binding) ~= "EnumItem" then
		return false
	end
	if binding.EnumType == Enum.KeyCode then
		return input.KeyCode == binding
	end
	return input.UserInputType == binding
end

-- Returns true/false when the physical state can be polled, or nil when it cannot.
local function isBindingDown(binding)
	if typeof(binding) ~= "EnumItem" then
		return nil
	end
	if binding.EnumType == Enum.KeyCode then
		local down = false
		pcall(function()
			down = UserInputService:IsKeyDown(binding)
				or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, binding)
		end)
		return down
	end
	if binding == Enum.UserInputType.MouseButton1
		or binding == Enum.UserInputType.MouseButton2
		or binding == Enum.UserInputType.MouseButton3 then
		return UserInputService:IsMouseButtonPressed(binding)
	end
	return nil
end

local function markStyleDirty()
	styleVersion += 1
end

local function syncUI()
	markStyleDirty()
	for _, refresh in ipairs(refreshers) do
		refresh()
	end
	scheduleConfigSave()
end

local function endDrag()
	activeDrag = nil
	if dragScroll then
		if dragScroll.Parent then
			dragScroll.ScrollingEnabled = true
		end
		dragScroll = nil
	end
end

local function beginDrag(updateFn, startInput, scrollFrame)
	activeDrag = {
		update = updateFn,
		mouse = startInput.UserInputType == Enum.UserInputType.MouseButton1,
	}
	if scrollFrame then
		dragScroll = scrollFrame
		scrollFrame.ScrollingEnabled = false
	end
	updateFn(startInput.Position)
end

--------------------------------------------------------------------------------
-- 6. PLAYER  (shared validation for Aim and ESP)
--------------------------------------------------------------------------------
local function isTeammate(player)
	if not Config.TeamCheck then
		return false
	end

	if Config.CustomTeamCheck then
		local ok, result = pcall(Config.CustomTeamCheck, player)
		if ok then
			return result == true
		end
	end

	if Config.TeamAttribute ~= "" then
		local mine = LocalPlayer:GetAttribute(Config.TeamAttribute)
		local theirs = player:GetAttribute(Config.TeamAttribute)
		if theirs == nil then
			return not Config.TargetNeutralPlayers
		end
		if mine == nil then
			return false
		end
		return mine == theirs
	end

	local theirTeam = player.Team
	if theirTeam == nil then
		return not Config.TargetNeutralPlayers
	end
	local myTeam = LocalPlayer.Team
	if myTeam == nil then
		return false
	end
	return myTeam == theirTeam
end

local function getLiveCharacter(player)
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	if Config.AliveCheck then
		if humanoid.Health <= Config.MinHealth or humanoid:GetState() == Enum.HumanoidStateType.Dead then
			return nil
		end
	end
	if Config.IgnoreForceField and character:FindFirstChildOfClass("ForceField") then
		return nil
	end
	return character, humanoid
end

-- Returns character, humanoid for a valid non-local, non-teammate, living player.
local function getTargetCharacter(player)
	if player == LocalPlayer then
		return nil
	end
	local character, humanoid = getLiveCharacter(player)
	if not character or character == LocalPlayer.Character then
		return nil
	end
	if isTeammate(player) then
		return nil
	end
	return character, humanoid
end

--------------------------------------------------------------------------------
-- 7. AIM  (target selection, prediction, camera)
--------------------------------------------------------------------------------
local function getAimPart(character)
	local preferred = character:FindFirstChild(Config.TargetPart)
	if preferred and preferred:IsA("BasePart") then
		return preferred
	end
	if Config.AllowPartFallback then
		for _, name in ipairs(Config.TargetPartFallbacks) do
			local candidate = character:FindFirstChild(name)
			if candidate and candidate:IsA("BasePart") then
				return candidate
			end
		end
	end
	return nil
end

local function hasLineOfSight(origin, partPosition, targetCharacter)
	local offset = partPosition - origin
	local distance = offset.Magnitude
	if not (distance > 1e-3) or distance == math.huge then
		return false
	end

	table.clear(ignoreList)
	local localCharacter = LocalPlayer.Character
	if localCharacter then
		table.insert(ignoreList, localCharacter)
	end

	local direction = offset.Unit * (distance + 1.5)
	for _ = 1, MAX_RAY_STEPS do
		rayParams.FilterDescendantsInstances = ignoreList
		local result = Workspace:Raycast(origin, direction, rayParams)
		if not result or not result.Instance then
			return false -- Nothing hit: visibility is not guaranteed.
		end
		local hit = result.Instance
		if hit:IsDescendantOf(targetCharacter) then
			return true
		end
		if hit.Transparency >= Config.VisibilityIgnoreTransparency then
			table.insert(ignoreList, hit)
		else
			return false
		end
	end
	return false
end

-- Returns aimPart, score when the player is an eligible target, otherwise nil.
local function evaluate(player, fovRadius)
	if not camera then
		return nil
	end
	local character, humanoid = getTargetCharacter(player)
	if not character then
		return nil
	end

	local part = getAimPart(character)
	if not part or not part.Parent then
		return nil
	end

	local camCFrame = camera.CFrame
	local partPosition = part.Position
	local worldDistance = (partPosition - camCFrame.Position).Magnitude
	if not (worldDistance < Config.MaxDistance) then
		return nil
	end

	local projected, onScreen = camera:WorldToViewportPoint(partPosition)
	if not onScreen or projected.Z <= 0 then
		return nil
	end
	-- Keep the selection cone angularly stable while ADS changes projection
	-- size.  Lower active FOV means the same angular error occupies more pixels.
	local activeFOV = math.max(camera.FieldOfView, 1)
	local defaultFOV = math.max(aimDefaultFOV or activeFOV, 1)
	local fovScale = aimFOVScale > 0 and aimFOVScale or (defaultFOV / activeFOV)
	local effectiveFOVRadius = fovRadius * fovScale
	local screenDistance = (Vector2.new(projected.X, projected.Y) - viewCenter).Magnitude
	if not (screenDistance <= effectiveFOVRadius) then
		return nil
	end

	if Config.VisibilityCheck then
		if not hasLineOfSight(camCFrame.Position, partPosition, character) then
			return nil
		end
	end

	local score
	if Config.SelectionPriority == "Distance" then
		score = worldDistance + screenDistance * 0.001
	elseif Config.SelectionPriority == "Health" then
		score = humanoid.Health + screenDistance * 0.001
	else
		score = screenDistance
	end
	return part, score
end

local function resetPrediction()
	smoothedVelocity = Vector3.zero
	velocityValid = false
end

local function releaseTarget(reason)
	if currentTarget then
		debugLog("Released target", currentTarget.Name, reason or "")
	end
	currentTarget = nil
	engageBlend = 0
	resetPrediction()
end

local function setTarget(player)
	if player ~= currentTarget then
		debugLog("Acquired target", player and player.Name or "none")
		currentTarget = player
		acquiredAt = os.clock()
		resetPrediction()
	end
end

local function updateTarget()
	local now = os.clock()

	if currentTarget then
		local radius = Config.FOVRadius
		if Config.TargetLock then
			radius = radius * Config.LockBreakFOVMultiplier
		end
		local part = evaluate(currentTarget, radius)
		if part then
			if Config.TargetLock or (now - acquiredAt) < Config.SwitchCooldown then
				return part
			end
		else
			releaseTarget("invalid")
		end
	end

	local bestPlayer, bestPart, bestScore = nil, nil, math.huge
	for _, player in ipairs(playerList) do
		local part, score = evaluate(player, Config.FOVRadius)
		if part and score < bestScore then
			bestPlayer, bestPart, bestScore = player, part, score
		end
	end

	if bestPlayer then
		setTarget(bestPlayer)
		return bestPart
	end
	if currentTarget then
		releaseTarget("none eligible")
	end
	return nil
end

local function computeAimPosition(part, dt)
	local position = part.Position
	if not Config.Prediction then
		return position
	end

	local velocity = part.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	if not (speed < MAX_VALID_SPEED) then
		resetPrediction()
		return position
	end

	if velocityValid then
		smoothedVelocity = smoothedVelocity:Lerp(velocity, 1 - math.exp(-15 * dt))
	else
		smoothedVelocity = velocity
		velocityValid = true
	end

	local lead = math.min(Config.PredictionFactor, Config.MaxPredictionTime)
	return position + smoothedVelocity * lead
end

local function applyCamera(aimPosition, dt)
	local cam = camera
	if not cam then
		return
	end
	if cam.CameraType == Enum.CameraType.Scriptable and not Config.ApplyToScriptableCamera then
		return
	end

	local camCFrame = cam.CFrame
	local origin = camCFrame.Position
	local toTarget = aimPosition - origin
	local distance = toTarget.Magnitude
	if not (distance > 1e-3) or distance == math.huge then
		return
	end

	local desired = toTarget / distance
	if math.abs(desired.Y) > 0.9995 then
		return -- Straight up/down would make CFrame.lookAt degenerate.
	end

	local dot = math.clamp(camCFrame.LookVector:Dot(desired), -1, 1)
	local angle = math.acos(dot)
	if angle < 1e-5 or angle < math.rad(Config.DeadzoneDegrees) then
		return
	end

	local alpha = 1
	if Config.CameraSmoothing > 0 then
		alpha = 1 - math.exp(-Config.CameraSmoothing * dt)
	end
	alpha = alpha * engageBlend
	if Config.MaxTurnRate > 0 then
		alpha = math.min(alpha, math.rad(Config.MaxTurnRate) * dt / angle)
	end
	if not (alpha > 0) then
		return
	end

	cam.CFrame = camCFrame:Lerp(CFrame.lookAt(origin, aimPosition), math.min(alpha, 1))
end

local function setActive(value, reason)
	if active == value then
		return
	end
	active = value
	if not value then
		releaseTarget(reason or "deactivated")
	end
	debugLog("Active:", value, reason or "")
end

local function setEnabled(value)
	if closed then
		return
	end
	Config.Enabled = value == true
	if not Config.Enabled then
		setActive(false, "disabled")
	end
	syncUI()
end

--------------------------------------------------------------------------------
-- 8. VISUAL  (FOV circle)
--------------------------------------------------------------------------------
local function updateVisuals(dt, hasTarget)
	if not ui or not ui.ring then
		return
	end

	local wantVisible = Config.ShowFOV and (active or not Config.ShowFOVOnlyWhenActive)
	visAlpha = approach(visAlpha, wantVisible and 1 or 0, 12, dt)
	lockBlend = approach(lockBlend, hasTarget and 1 or 0, 10, dt)
	activeBlend = approach(activeBlend, active and 1 or 0, 10, dt)
	enabledBlend = approach(enabledBlend, Config.Enabled and 1 or 0.45, 10, dt)

	if visAlpha < 0.01 then
		ui.ring.Visible = false
		return
	end
	ui.ring.Visible = true

	local radius = Config.FOVRadius * (1 - 0.04 * lockBlend)
	displayRadius = approach(displayRadius, radius, 14, dt)

	ui.ring.Size = UDim2.fromOffset(displayRadius * 2, displayRadius * 2)
	ui.ring.Position = UDim2.fromOffset(viewCenter.X, viewCenter.Y)
	ui.ringStroke.Thickness = Config.FOVThickness
	ui.ringStroke.Color = Config.FOVColor:Lerp(Config.FOVActiveColor, lockBlend)

	local opacity = (1 - Config.FOVTransparency) * visAlpha * enabledBlend * (0.7 + 0.3 * activeBlend)
	ui.ringStroke.Transparency = 1 - math.clamp(opacity, 0, 1)
end

--------------------------------------------------------------------------------
-- 9. ESP  (2D overlay built from Frames / TextLabels, plus optional Highlight)
--------------------------------------------------------------------------------
local function makeLine(parent)
	return create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Config.ESPColor,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 1),
		Visible = false,
	}, parent)
end

local function setLine(line, ax, ay, bx, by, thickness)
	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	if not (length >= 0.5) or length > MAX_LINE_LENGTH then
		line.Visible = false
		return
	end
	line.Size = UDim2.fromOffset(length, thickness)
	line.Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5)
	line.Rotation = math.deg(math.atan2(dy, dx))
	line.Visible = true
end

local function createEspObject(player)
	if closed or not ui or not ui.espRoot then
		return nil
	end

	local root = create("Frame", {
		Name = "ESP_" .. tostring(player.UserId),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, ui.espRoot)

	local nameLabel = create("TextLabel", {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 16),
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = Config.ESPColor,
		TextStrokeColor3 = Theme.Black,
		TextStrokeTransparency = 0.4,
		Text = "",
		Visible = false,
	}, root)

	local infoLabel = create("TextLabel", {
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 16),
		Font = FONT,
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextStrokeColor3 = Theme.Black,
		TextStrokeTransparency = 0.4,
		Text = "",
		Visible = false,
	}, root)

	local headFrame = create("Frame", {
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(8, 8),
		Visible = false,
	}, root)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, headFrame)
	local headStroke = create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = 1.5,
		Color = Config.ESPColor,
	}, headFrame)

	local look = makeLine(root)
	local bones = {}
	for i = 1, MAX_BONES do
		bones[i] = makeLine(root)
	end

	local obj = {
		root = root,
		nameLabel = nameLabel,
		infoLabel = infoLabel,
		headFrame = headFrame,
		headStroke = headStroke,
		look = look,
		bones = bones,
		highlight = nil,
		parts = {},
		screen = {},
		character = nil,
		rigR15 = false,
		shown = false,
		lastStyle = -1,
		lastColor = nil,
		infoDist = -1,
		infoHp = -1,
		nameText = nil,
		boneUsed = -1,
	}
	espObjects[player] = obj
	return obj
end

local function applyEspStyle(obj, color)
	local textSize = Config.ESPTextSize
	local lineHeight = textSize + 3
	obj.nameLabel.TextColor3 = color
	obj.nameLabel.TextSize = textSize
	obj.nameLabel.Size = UDim2.fromOffset(240, lineHeight)
	obj.infoLabel.TextSize = math.max(9, textSize - 1)
	obj.infoLabel.Size = UDim2.fromOffset(240, lineHeight)

	obj.headStroke.Color = color
	obj.headStroke.Thickness = Config.ESPThickness
	obj.headStroke.Transparency = Config.ESPTransparency

	obj.look.BackgroundColor3 = color
	obj.look.BackgroundTransparency = Config.ESPTransparency
	for _, line in ipairs(obj.bones) do
		line.BackgroundColor3 = color
		line.BackgroundTransparency = Config.ESPTransparency
	end

	if obj.highlight then
		obj.highlight.FillColor = color
		obj.highlight.OutlineColor = color
	end
end

local function getEspPart(obj, name)
	local part = obj.parts[name]
	if part and part.Parent then
		return part
	end
	local found = obj.character and obj.character:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		obj.parts[name] = found
		return found
	end
	obj.parts[name] = nil
	return nil
end

local function getEspScreen(obj, name)
	local cached = obj.screen[name]
	if cached ~= nil then
		return cached or nil
	end
	local part = getEspPart(obj, name)
	if part then
		local v = camera:WorldToViewportPoint(part.Position)
		if v.Z > 0 then
			local point = Vector2.new(v.X, v.Y)
			obj.screen[name] = point
			return point
		end
	end
	obj.screen[name] = false
	return nil
end

local function hideEspObject(obj)
	if obj.shown then
		obj.shown = false
		obj.root.Visible = false
	end
	if obj.highlight and obj.highlight.Enabled then
		obj.highlight.Enabled = false
	end
end

-- Draws one player. Returns true when anything is shown for them.
local function renderEsp(player, camPos)
	local character, humanoid = getTargetCharacter(player)
	if not character then
		return false
	end

	local head = character:FindFirstChild("Head")
	if head and not head:IsA("BasePart") then
		head = nil
	end
	local focus = head
	if not focus then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			focus = rootPart
		end
	end
	if not focus then
		return false
	end

	local focusPos = focus.Position
	local distance = (focusPos - camPos).Magnitude
	if not (distance <= Config.ESPMaxDistance) then
		return false
	end

	local projected = camera:WorldToViewportPoint(focusPos)
	if projected.Z <= 0 then
		return false
	end
	local viewport = camera.ViewportSize
	if projected.X < -ESP_VIEW_MARGIN or projected.X > viewport.X + ESP_VIEW_MARGIN
		or projected.Y < -ESP_VIEW_MARGIN or projected.Y > viewport.Y + ESP_VIEW_MARGIN then
		return false
	end

	local obj = espObjects[player] or createEspObject(player)
	if not obj then
		return false
	end

	if obj.character ~= character then
		obj.character = character
		table.clear(obj.parts)
		obj.rigR15 = humanoid.RigType == Enum.HumanoidRigType.R15
		obj.lastStyle = -1
		obj.boneUsed = -1
	end
	table.clear(obj.screen)

	local color = Config.ESPColor
	if Config.ESPTeamColors and player.Team then
		color = player.TeamColor.Color
	end
	local styleChanged = obj.lastStyle ~= styleVersion
	if styleChanged or obj.lastColor ~= color then
		applyEspStyle(obj, color)
		obj.lastStyle = styleVersion
		obj.lastColor = color
	end

	local thickness = Config.ESPThickness
	local textSize = Config.ESPTextSize
	local lineHeight = textSize + 3

	-- Name and info labels above the head ---------------------------------------
	local showInfo = Config.ESPShowDistance or Config.ESPShowHealth
	local top = camera:WorldToViewportPoint(focusPos + Vector3.new(0, head and 1.6 or 3.2, 0))
	local tx, ty = top.X, top.Y

	if showInfo then
		local dist = math.floor(distance + 0.5)
		local hp = math.floor(humanoid.Health + 0.5)
		if hp ~= hp then
			hp = 0
		end
		if styleChanged or obj.infoDist ~= dist or obj.infoHp ~= hp then
			obj.infoDist, obj.infoHp = dist, hp
			if Config.ESPShowDistance and Config.ESPShowHealth then
				obj.infoLabel.Text = string.format("%d studs  |  %d HP", dist, hp)
			elseif Config.ESPShowDistance then
				obj.infoLabel.Text = string.format("%d studs", dist)
			else
				obj.infoLabel.Text = string.format("%d HP", hp)
			end
		end
		obj.infoLabel.Position = UDim2.fromOffset(tx, ty)
		obj.infoLabel.Visible = true
	else
		obj.infoLabel.Visible = false
	end

	if Config.ESPShowName then
		local name = Config.ESPUseDisplayName and player.DisplayName or player.Name
		if obj.nameText ~= name then
			obj.nameText = name
			obj.nameLabel.Text = name
		end
		obj.nameLabel.Position = UDim2.fromOffset(tx, ty - (showInfo and lineHeight or 0))
		obj.nameLabel.Visible = true
	else
		obj.nameLabel.Visible = false
	end

	-- Circle around the head -----------------------------------------------------
	if Config.ESPShowHeadCircle and head then
		local edge = camera:WorldToViewportPoint(focusPos + camera.CFrame.UpVector * (head.Size.Y * 0.5))
		local ex, ey = edge.X - projected.X, edge.Y - projected.Y
		local radius = math.clamp(math.sqrt(ex * ex + ey * ey), 3, 300)
		obj.headFrame.Size = UDim2.fromOffset(radius * 2, radius * 2)
		obj.headFrame.Position = UDim2.fromOffset(projected.X, projected.Y)
		obj.headFrame.Visible = true
	else
		obj.headFrame.Visible = false
	end

	-- Look direction line ----------------------------------------------------------
	if Config.ESPShowLookLine and head then
		local b = camera:WorldToViewportPoint(focusPos + head.CFrame.LookVector * Config.ESPLookLength)
		if b.Z > 0 then
			setLine(obj.look, projected.X, projected.Y, b.X, b.Y, thickness)
		else
			obj.look.Visible = false
		end
	else
		obj.look.Visible = false
	end

	-- Skeleton -------------------------------------------------------------------------
	local bones = obj.bones
	local used = 0
	if Config.ESPShowSkeleton then
		local list = obj.rigR15 and R15_BONES or R6_BONES
		used = #list
		for i = 1, used do
			local pair = list[i]
			local a = getEspScreen(obj, pair[1])
			local b = getEspScreen(obj, pair[2])
			if a and b then
				setLine(bones[i], a.X, a.Y, b.X, b.Y, thickness)
			else
				bones[i].Visible = false
			end
		end
	end
	if obj.boneUsed ~= used then
		obj.boneUsed = used
		for i = used + 1, #bones do
			bones[i].Visible = false
		end
	end

	-- Outline glow -------------------------------------------------------------------------
	if Config.ESPHighlight and espFolder then
		local highlight = obj.highlight
		if not highlight or not highlight.Parent then
			highlight = create("Highlight", {
				Name = "Glow",
				FillTransparency = 0.8,
				OutlineTransparency = 0,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				FillColor = color,
				OutlineColor = color,
			}, espFolder)
			obj.highlight = highlight
		end
		if highlight.Adornee ~= character then
			highlight.Adornee = character
		end
		if not highlight.Enabled then
			highlight.Enabled = true
		end
	elseif obj.highlight and obj.highlight.Enabled then
		obj.highlight.Enabled = false
	end

	if not obj.shown then
		obj.shown = true
		obj.root.Visible = true
	end
	return true
end

local function removeEsp(player)
	local obj = espObjects[player]
	if not obj then
		return
	end
	espObjects[player] = nil
	pcall(function()
		obj.root:Destroy()
	end)
	if obj.highlight then
		pcall(function()
			obj.highlight:Destroy()
		end)
	end
end

local function clearEsp()
	for player in pairs(espObjects) do
		removeEsp(player)
	end
	table.clear(espObjects)
end

-- Returns the number of players drawn this frame.
local function updateEsp()
	if not camera or not ui or not ui.espRoot then
		return 0
	end
	local count = 0
	local camPos = camera.CFrame.Position
	local enabled = Config.ESPEnabled

	for _, player in ipairs(playerList) do
		local shown = false
		if enabled and player ~= LocalPlayer then
			local ok, result = pcall(renderEsp, player, camPos)
			if ok then
				shown = result == true
			elseif Config.Debug then
				warn("[SmoothTargetAssist] ESP error:", result)
			end
		end
		if shown then
			count += 1
		else
			local obj = espObjects[player]
			if obj then
				hideEspObject(obj)
			end
		end
	end
	return count
end

-- Loot and world-item ESP -------------------------------------------------------
-- Workspace.LootBags contains LootBag parts/models; Workspace.WorldFinds contains
-- Dropped_* models whose FindAnchor is the preferred marker position.
local IGNORED_LOOT_ITEMS = {
	dropped_junk = true,
	dropped_wooden_board = true,
}
local IGNORED_LOOT_FOLDERS = {
	NoiseTraps = true,
	HushGrass = true,
}

local function isIgnoredLootInstance(item)
	local ancestor = item
	while ancestor and ancestor ~= Workspace do
		if IGNORED_LOOT_FOLDERS[ancestor.Name] then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function getLootTargetPart(item)
	if item:IsA("BasePart") then
		return item
	end
	local anchor = item:FindFirstChild("FindAnchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor
	end
	return item:FindFirstChildWhichIsA("BasePart", true)
end

-- Returns the label and color for a supported loot instance, or nil to ignore it.
local function AnalyzeItem(item, isContainer)
	local rawName = item.Name
	local lowerName = string.lower(rawName)
	if isContainer then
		if string.find(lowerName, "codefragment", 1, true) or string.find(lowerName, "redpaper", 1, true)
			or string.find(lowerName, "bunker_code", 1, true) or string.find(lowerName, "key", 1, true) then
			return "Important: " .. rawName, Config.LootESPImportantColor, "Important"
		end
		return rawName, Config.LootESPContainerColor, "Container"
	end
	if IGNORED_LOOT_ITEMS[lowerName] then
		return nil
	end
	if rawName == "LootBag" or string.find(lowerName, "lootbag", 1, true) then
		return "Loot Bag", Config.LootESPLootBagColor, "General"
	end

	local cleanName = string.gsub(rawName, "^Dropped_", "")
	if string.find(lowerName, "bunker_code", 1, true) or string.find(lowerName, "key", 1, true) then
		cleanName = string.upper(string.gsub(cleanName, "_", " "))
		return "Important: " .. cleanName, Config.LootESPImportantColor, "Important"
	end
	if string.find(lowerName, "ammo", 1, true) or string.find(lowerName, "bullet", 1, true)
		or string.find(lowerName, "magazine", 1, true) or string.find(lowerName, "mag_", 1, true) then
		cleanName = string.gsub(cleanName, "_", " ")
		return cleanName, Config.LootESPAmmoColor, "Ammo"
	end
	if string.find(lowerName, "gun", 1, true) or string.find(lowerName, "rifle", 1, true)
		or string.find(lowerName, "pistol", 1, true) or string.find(lowerName, "shotgun", 1, true)
		or string.find(lowerName, "melee", 1, true) or string.find(lowerName, "knife", 1, true)
		or string.find(lowerName, "bat", 1, true) or string.find(lowerName, "axe", 1, true) then
		cleanName = string.gsub(cleanName, "_", " ")
		return cleanName, Config.LootESPWeaponColor, "Weapon"
	end
	cleanName = string.gsub(cleanName, "_", " ")
	cleanName = string.gsub(cleanName, "(%a)([%w ]*)", function(first, rest)
		return string.upper(first) .. string.lower(rest)
	end)
	return cleanName, Config.LootESPGeneralColor, "General"
end

local function RemoveLootESP(item)
	local object = lootEspObjects[item]
	if not object then
		return
	end
	lootEspObjects[item] = nil
	if object.highlight then
		pcall(function() object.highlight:Destroy() end)
	end
	if object.billboard then
		pcall(function() object.billboard:Destroy() end)
	end
end

local function CreateLootESP(item, isContainer)
	if closed or not item or lootEspObjects[item] then
		return
	end
	if isIgnoredLootInstance(item) then
		return
	end
	local displayName, color, category = AnalyzeItem(item, isContainer)
	if not displayName then
		return
	end
	local part = getLootTargetPart(item)
	if not part then
		return
	end

	local highlight = create("Highlight", {
		Name = "LootHighlight",
		Adornee = item,
		FillColor = color,
		FillTransparency = 0.6,
		OutlineColor = Theme.White,
		OutlineTransparency = 0.3,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	}, lootEspFolder)
	local billboard = create("BillboardGui", {
		Name = "LootMarker",
		Adornee = part,
		Size = UDim2.fromOffset(160, 34),
		StudsOffset = Vector3.new(0, 1.2, 0),
		AlwaysOnTop = true,
		Enabled = false,
	}, lootEspFolder)
	local label = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = color,
		TextStrokeColor3 = Theme.Black,
		TextStrokeTransparency = 0.2,
		Text = displayName,
	}, billboard)
	lootEspObjects[item] = {
		highlight = highlight,
		billboard = billboard,
		label = label,
		part = part,
		displayName = displayName,
		category = category,
		nextFarUpdate = 0,
	}
end

local function isContainerName(name)
	name = string.lower(name)
	return string.find(name, "container", 1, true) or string.find(name, "drawer", 1, true)
		or string.find(name, "box", 1, true) or string.find(name, "crate", 1, true)
		or string.find(name, "chest", 1, true) or string.find(name, "locker", 1, true)
		or string.find(name, "safe", 1, true)
end

local function isImportantInteractableName(name)
	name = string.lower(name)
	return string.find(name, "codefragment", 1, true) or string.find(name, "redpaper", 1, true)
		or string.find(name, "bunker_code", 1, true) or string.find(name, "key", 1, true)
end

local function registerContainerPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local candidate = prompt.Parent
	local fallback = nil
	for _ = 1, 5 do
		if not candidate or candidate == Workspace then
			return
		end
		if isContainerName(candidate.Name) or isImportantInteractableName(candidate.Name) then
			CreateLootESP(candidate, true)
			return
		end
		if not fallback and (candidate:IsA("Model") or candidate:IsA("BasePart")) then
			fallback = candidate
		end
		candidate = candidate.Parent
	end
	if fallback then
		CreateLootESP(fallback, true)
	end
end

local function isLootCategoryEnabled(category)
	if category == "Weapon" then
		return Config.LootESPShowWeapons
	elseif category == "Ammo" then
		return Config.LootESPShowAmmo
	elseif category == "Important" then
		return Config.LootESPShowImportant
	elseif category == "Container" then
		return Config.LootESPShowContainers
	end
	return Config.LootESPShowGeneral
end

local function registerLootFolder(folder)
	if not folder or lootFolders[folder] then
		return
	end
	lootFolders[folder] = true
	for _, item in ipairs(folder:GetChildren()) do
		if folder.Name ~= "WorldFinds" or string.sub(item.Name, 1, 8) == "Dropped_" then
			CreateLootESP(item)
		end
	end
	track(folder.ChildAdded:Connect(function(item)
		if folder.Name ~= "WorldFinds" or string.sub(item.Name, 1, 8) == "Dropped_" then
			CreateLootESP(item)
		end
	end))
	track(folder.ChildRemoved:Connect(RemoveLootESP))
	track(folder.Destroying:Connect(function()
		lootFolders[folder] = nil
	end))
end

local function updateLootEsp()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local enabled = Config.LootESPEnabled and root ~= nil
	local origin = root and root.Position
	local now = os.clock()
	for item, object in pairs(lootEspObjects) do
		local valid = item.Parent ~= nil and object.part and object.part.Parent ~= nil
		if not valid then
			RemoveLootESP(item)
		else
			local distance = enabled and (origin - object.part.Position).Magnitude or nil
			if distance and distance > LOOT_FAR_THROTTLE_DISTANCE and now < object.nextFarUpdate then
				continue
			end
			if distance and distance > LOOT_FAR_THROTTLE_DISTANCE then
				object.nextFarUpdate = now + LOOT_FAR_THROTTLE_INTERVAL
			else
				object.nextFarUpdate = 0
			end
			local visible = distance ~= nil and distance <= Config.LootESPMaxDistance
				and isLootCategoryEnabled(object.category)
			object.billboard.Enabled = visible
			object.highlight.Enabled = visible
			if visible then
				if Config.LootESPShowDistance then
					object.label.Text = string.format("%s\n[%d studs]", object.displayName, math.floor(distance + 0.5))
				else
					object.label.Text = object.displayName
				end
			end
		end
	end
end

local function clearLootEsp()
	for item in pairs(lootEspObjects) do
		RemoveLootESP(item)
	end
	table.clear(lootEspObjects)
	table.clear(lootFolders)
end

--------------------------------------------------------------------------------
-- 10. LIGHTING  (full bright, original values are restored when turned off)
--------------------------------------------------------------------------------
local function setIfDifferent(instance, property, value)
	if instance[property] ~= value then
		instance[property] = value
	end
end

local function applyFullBright()
	if not savedLighting then
		savedLighting = {}
		for _, name in ipairs(LIGHTING_PROPS) do
			savedLighting[name] = Lighting[name]
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			savedAtmosphere = { instance = atmosphere, Density = atmosphere.Density, Haze = atmosphere.Haze }
		end
	end

	pcall(function()
		setIfDifferent(Lighting, "Brightness", Config.FullBrightLevel)
		setIfDifferent(Lighting, "ClockTime", 14)
		setIfDifferent(Lighting, "GlobalShadows", false)
		setIfDifferent(Lighting, "FogStart", 99999)
		setIfDifferent(Lighting, "FogEnd", 100000)
		setIfDifferent(Lighting, "Ambient", Color3.fromRGB(190, 190, 190))
		setIfDifferent(Lighting, "OutdoorAmbient", Color3.fromRGB(190, 190, 190))
		if savedAtmosphere and savedAtmosphere.instance.Parent then
			setIfDifferent(savedAtmosphere.instance, "Density", 0)
			setIfDifferent(savedAtmosphere.instance, "Haze", 0)
		end
	end)
end

local function restoreLighting()
	if savedLighting then
		for _, name in ipairs(LIGHTING_PROPS) do
			local value = savedLighting[name]
			if value ~= nil then
				pcall(function()
					Lighting[name] = value
				end)
			end
		end
		savedLighting = nil
	end
	if savedAtmosphere then
		local info = savedAtmosphere
		savedAtmosphere = nil
		if info.instance and info.instance.Parent then
			pcall(function()
				info.instance.Density = info.Density
				info.instance.Haze = info.Haze
			end)
		end
	end
	lightingTimer = 0
end

local function updateLighting(dt)
	if Config.FullBright then
		lightingTimer -= dt
		if lightingTimer <= 0 then
			lightingTimer = 0.25
			applyFullBright()
		end
	elseif savedLighting then
		restoreLighting()
	end
end

--------------------------------------------------------------------------------
-- 11. SHUTDOWN  (idempotent, permanent)
--------------------------------------------------------------------------------
local api = {}

local function shutdown()
	if closed then
		return
	end
	closed = true
	active = false
	currentTarget = nil
	activeDrag = nil
	dragScroll = nil
	listeningBind = nil
	animToken += 1

	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)

	for _, connection in ipairs(connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(connections)

	for t in pairs(activeTweens) do
		pcall(function()
			t:Cancel()
		end)
	end
	table.clear(activeTweens)

	restoreLighting()
	saveToken += 1
	pcall(saveConfigNow)
	if camera and originalCameraFOV then
		pcall(function() camera.FieldOfView = originalCameraFOV end)
	end
	originalCameraFOV = nil
	clearEsp()
	clearLootEsp()
	if espFolder then
		pcall(function()
			espFolder:Destroy()
		end)
		espFolder = nil
	end
	if lootEspFolder then
		pcall(function()
			lootEspFolder:Destroy()
		end)
		lootEspFolder = nil
	end

	if ui then
		local localUi = ui
		ui = nil
		for _, key in ipairs({ "panelGui", "overlayGui" }) do
			local gui = localUi[key]
			if gui then
				pcall(function()
					gui:Destroy()
				end)
			end
		end
	end

	table.clear(refreshers)
	table.clear(playerList)
	table.clear(ignoreList)
	rayParams.FilterDescendantsInstances = {}
	camera = nil
	setMinimized = nil

	if shared[SHARED_KEY] == api then
		shared[SHARED_KEY] = nil
	end
	if Config.Debug then
		print("[SmoothTargetAssist] Closed and cleaned up")
	end
end

--------------------------------------------------------------------------------
-- 12. GUI
--------------------------------------------------------------------------------
local function applyPanelPosition()
	if not ui then
		return
	end
	local position = UDim2.fromOffset(panelPos.X, panelPos.Y)
	ui.panel.Position = position
	ui.pill.Position = position
end

local function clampPanelPosition()
	if not ui then
		return
	end
	local area = ui.panelGui.AbsoluteSize
	local maxX = math.max(8, area.X - panelSize.X - 8)
	local maxY = math.max(8, area.Y - panelSize.Y - 8)
	panelPos = Vector2.new(math.clamp(panelPos.X, 8, maxX), math.clamp(panelPos.Y, 8, maxY))
end

local function updateLayout()
	if closed or not ui then
		return
	end
	local area = ui.panelGui.AbsoluteSize
	local width = math.clamp(area.X - 16, 220, 330)
	local height = math.clamp(area.Y - 16, 240, 480)
	panelSize = Vector2.new(width, height)
	ui.panel.Size = UDim2.fromOffset(width, height)
	clampPanelPosition()
	applyPanelPosition()
end

local function updateStatus(hasTarget)
	if not ui then
		return
	end
	local text, color
	if not Config.Enabled then
		text, color = "Aim off", Theme.Off
	elseif active and hasTarget and currentTarget then
		text, color = "Locked · " .. string.sub(currentTarget.Name, 1, 18), Theme.Good
	elseif active then
		text, color = "Searching…", Theme.Warn
	else
		local verb = Config.ActivationMode == "Toggle" and "press " or "hold "
		text, color = "Ready · " .. verb .. bindingName(Config.ActivationInput), Theme.Accent
	end

	if text ~= lastStatusText then
		lastStatusText = text
		ui.statusLabel.Text = text
	end
	if color ~= lastStatusColor then
		lastStatusColor = color
		tween(ui.statusDot, 0.15, { BackgroundColor3 = color })
		tween(ui.pillDot, 0.15, { BackgroundColor3 = color })
	end
end

local function updateStats(dt)
	if dt > 0 then
		fpsSample = fpsSample * 0.9 + (1 / dt) * 0.1
	end
	statsTimer += dt
	if statsTimer < 0.3 then
		return
	end
	statsTimer = 0
	if ui and ui.statsLabel then
		local ping = "n/a"
		local memory = "n/a"
		pcall(function()
			ping = StatsService.Network.ServerStatsItem["Data Ping"]:GetValueString()
		end)
		pcall(function()
			memory = string.format("%.0f MB", StatsService:GetTotalMemoryUsageMb())
		end)
		ui.statsLabel.Text = string.format(
			"FPS: %.0f  ·  Ping: %s  ·  Memory: %s\nPlayers: %d  ·  ESP drawn: %d  ·  Target: %s",
			fpsSample, ping, memory,
			#playerList,
			espShown,
			currentTarget and currentTarget.Name or "none"
		)
	end
end

local function hover(button, normal, over)
	track(button.MouseEnter:Connect(function()
		tween(button, 0.12, { BackgroundColor3 = over })
	end))
	track(button.MouseLeave:Connect(function()
		tween(button, 0.12, { BackgroundColor3 = normal })
	end))
end

local function buildGui()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
	if closed then
		return
	end
	if not playerGui then
		warn("[SmoothTargetAssist] PlayerGui not found; running without GUI.")
		return
	end

	for _, name in ipairs({ OVERLAY_GUI_NAME, PANEL_GUI_NAME }) do
		local old = playerGui:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	-- Overlay: FOV circle + ESP (full screen, ignores the top-bar inset) ---------------
	local overlayGui = create("ScreenGui", {
		Name = OVERLAY_GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local espRoot = create("Frame", {
		Name = "ESPRoot",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Interactable = false,
		Size = UDim2.fromScale(1, 1),
	}, overlayGui)
	local ring = create("Frame", {
		Name = "FOVRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Interactable = false,
		Size = UDim2.fromOffset(Config.FOVRadius * 2, Config.FOVRadius * 2),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
	}, overlayGui)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local ringStroke = create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = Config.FOVThickness,
		Color = Config.FOVColor,
		Transparency = 1,
	}, ring)
	displayRadius = Config.FOVRadius

	-- Panel ScreenGui ----------------------------------------------------------------------
	local panelGui = create("ScreenGui", {
		Name = PANEL_GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local panel = create("CanvasGroup", {
		Name = "Panel",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Active = true, -- Only the panel area sinks input; the rest of the screen is untouched.
		Size = UDim2.fromOffset(panelSize.X, panelSize.Y),
		Position = UDim2.fromOffset(panelPos.X, panelPos.Y),
		GroupTransparency = 1,
		Visible = false,
	}, panelGui)
	create("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
	create("UIStroke", { Color = Theme.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)

	-- Title bar: drag handle on the left, buttons on the right (no overlap) ---------------
	local titleBar = create("Frame", {
		Name = "TitleBar",
		BackgroundColor3 = Theme.Title,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 38),
	}, panel)

	local dragHandle = create("Frame", {
		Name = "DragHandle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		Size = UDim2.new(1, -80, 1, 0),
	}, titleBar)
	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Active = false,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -14, 1, 0),
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Smooth Target Assist",
	}, dragHandle)

	local minButton = create("TextButton", {
		Name = "Minimize",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, -68, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = Theme.Text,
		Text = "–",
	}, titleBar)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, minButton)
	hover(minButton, Theme.Card, Theme.Stroke)

	local closeButton = create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, -34, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = Theme.Danger,
		Text = "×",
	}, titleBar)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, closeButton)
	hover(closeButton, Theme.Card, Color3.fromRGB(70, 38, 42))

	-- Status card -------------------------------------------------------------------------------
	local statusFrame = create("Frame", {
		Name = "Status",
		BackgroundColor3 = Theme.Card,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 46),
		Size = UDim2.new(1, -24, 0, 30),
	}, panel)
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, statusFrame)
	local statusDot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
	}, statusFrame)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, statusDot)
	local statusLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Font = FONT,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Starting…",
	}, statusFrame)

	-- Minimized pill ------------------------------------------------------------------------------
	local pill = create("CanvasGroup", {
		Name = "Minimized",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(112, 32),
		Position = UDim2.fromOffset(panelPos.X, panelPos.Y),
		GroupTransparency = 1,
		Visible = false,
	}, panelGui)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	create("UIStroke", { Color = Theme.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	local pillDot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
	}, pill)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pillDot)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Assist",
	}, pill)
	local pillButton = create("TextButton", {
		Name = "Restore",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
	}, pill)

	ui = {
		overlayGui = overlayGui,
		espRoot = espRoot,
		ring = ring,
		ringStroke = ringStroke,
		panelGui = panelGui,
		panel = panel,
		pill = pill,
		statusDot = statusDot,
		statusLabel = statusLabel,
		pillDot = pillDot,
		statsLabel = nil,
	}
	local crosshair = create("Frame", {
		Name = "Crosshair",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, overlayGui)
	local crosshairLines = {}
	for i = 1, 4 do
		crosshairLines[i] = create("Frame", {
			BackgroundColor3 = Config.CrosshairColor,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
		}, crosshair)
	end
	ui.crosshair = crosshair
	ui.crosshairLines = crosshairLines

	-- Tabs and pages ------------------------------------------------------------------------------
	local pages = {}
	local tabButtons = {}
	local currentPage = nil
	local selectedTab = nil

	local function selectTab(name)
		endDrag()
		selectedTab = name
		for pageName, page in pairs(pages) do
			page.frame.Visible = pageName == name
		end
		for tabName, button in pairs(tabButtons) do
			local selected = tabName == name
			tween(button, 0.15, {
				BackgroundColor3 = selected and Theme.Accent or Theme.Card,
				TextColor3 = selected and Theme.OnAccent or Theme.SubText,
			})
		end
	end

	local tabBar = create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 82),
		Size = UDim2.new(1, -24, 0, 28),
	}, panel)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)
	for index, name in ipairs(TAB_NAMES) do
		local button = create("TextButton", {
			Name = name,
			LayoutOrder = index,
			Size = UDim2.new(1 / #TAB_NAMES, -4, 1, 0),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = Theme.SubText,
			Text = name,
		}, tabBar)
		create("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
		tabButtons[name] = button
		track(button.Activated:Connect(function()
			selectTab(name)
		end))
	end

	local function newPage(name)
		local frame = create("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 118),
			Size = UDim2.new(1, 0, 1, -118),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Stroke,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			Visible = false,
		}, panel)
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, frame)
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 12),
		}, frame)
		local page = { frame = frame, order = 0 }
		pages[name] = page
		currentPage = page
		return page
	end

	-- Row builders (always append to the current page) -------------------------------------
	local function nextOrder()
		currentPage.order += 1
		return currentPage.order
	end

	local function makeSection(text)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = nextOrder(),
			Font = FONT_BOLD,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.upper(text),
		}, currentPage.frame)
	end

	local function makeNote(text, height)
		return create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = nextOrder(),
			Font = FONT,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = text,
		}, currentPage.frame)
	end

	local function makeRow(height)
		local row = create("Frame", {
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = nextOrder(),
		}, currentPage.frame)
		create("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
		return row
	end

	local function makeRowLabel(row, text, reserve)
		return create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -(reserve or 90), 0, 36),
			Font = FONT,
			TextSize = 13,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
		}, row)
	end

	local function styleBox(box)
		create("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
	end

	local function makeToggle(text, getter, setter)
		local row = makeRow(36)
		makeRowLabel(row, text)
		local switch = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(40, 22),
			BackgroundColor3 = Theme.SwitchOff,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
		}, row)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, switch)
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
		}, switch)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)

		local first = true
		local function refresh()
			local on = getter() == true
			local color = on and Theme.Accent or Theme.SwitchOff
			local position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
			if first then
				first = false
				switch.BackgroundColor3 = color
				knob.Position = position
			else
				tween(switch, 0.15, { BackgroundColor3 = color })
				tween(knob, 0.15, { Position = position })
			end
		end
		table.insert(refreshers, refresh)
		track(switch.Activated:Connect(function()
			setter(not (getter() == true))
			syncUI()
		end))
		refresh()
	end

	local function makeConfigToggle(text, key, onChange)
		makeToggle(text, function()
			return Config[key]
		end, function(value)
			Config[key] = value
			if onChange then
				onChange(value)
			end
		end)
	end

	local function makeAction(text, callback)
		local row = makeRow(40)
		local button = create("TextButton", {
			Size = UDim2.new(1, -24, 0, 28),
			Position = UDim2.fromOffset(12, 6),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = Theme.Text,
			Text = text,
		}, row)
		styleBox(button)
		hover(button, Theme.Panel, Theme.Stroke)
		track(button.Activated:Connect(callback))
	end

	local function makeCycle(text, key, options)
		local row = makeRow(36)
		makeRowLabel(row, text, 124)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(108, 24),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Text,
			Text = tostring(Config[key]),
		}, row)
		styleBox(button)
		hover(button, Theme.Panel, Theme.Stroke)
		table.insert(refreshers, function()
			button.Text = tostring(Config[key])
		end)
		track(button.Activated:Connect(function()
			local index = table.find(options, Config[key]) or 0
			Config[key] = options[index % #options + 1]
			syncUI()
		end))
	end

	local function makeBind(text, key, allowClear)
		local row = makeRow(36)
		makeRowLabel(row, text, 124)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(108, 24),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Text,
			Text = "",
		}, row)
		styleBox(button)
		hover(button, Theme.Panel, Theme.Stroke)
		local function refresh()
			if listeningBind and listeningBind.key == key then
				button.Text = "Press a key…"
			else
				button.Text = bindingName(Config[key])
			end
		end
		table.insert(refreshers, refresh)
		track(button.Activated:Connect(function()
			if listeningBind and listeningBind.key == key then
				listeningBind = nil
			else
				listeningBind = { key = key, allowClear = allowClear }
			end
			syncUI()
		end))
		refresh()
	end

	-- step = slider drag snapping, fineStep = snapping for typed values (defaults to step).
	local function makeSlider(text, key, minValue, maxValue, step, decimals, fineStep)
		local row = makeRow(58)
		makeRowLabel(row, text)
		local format = "%." .. decimals .. "f"
		local frame = currentPage.frame

		local valueBox = create("TextBox", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 7),
			Size = UDim2.fromOffset(62, 22),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Text,
			ClearTextOnFocus = false,
			Text = "",
		}, row)
		styleBox(valueBox)

		local hit = create("Frame", {
			BackgroundTransparency = 1,
			Active = true,
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -28, 0, 18),
		}, row)
		local bar = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = Theme.SwitchOff,
			BorderSizePixel = 0,
		}, hit)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
		local fill = create("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
		}, bar)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
		}, hit)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)

		local function applyValue(value, snap)
			local v = clampNumber(value, minValue, maxValue, Config[key])
			v = math.floor(v / snap + 0.5) * snap
			Config[key] = math.clamp(v, minValue, maxValue)
			markStyleDirty()
			scheduleConfigSave()
		end

		local function refresh()
			local v = clampNumber(Config[key], minValue, maxValue, minValue)
			local fraction = (v - minValue) / (maxValue - minValue)
			fill.Size = UDim2.fromScale(fraction, 1)
			knob.Position = UDim2.new(fraction, 0, 0.5, 0)
			if not valueBox:IsFocused() then
				valueBox.Text = string.format(format, v)
			end
		end
		table.insert(refreshers, refresh)

		local function fromX(x)
			local width = hit.AbsoluteSize.X
			if width <= 0 then
				return
			end
			local fraction = math.clamp((x - hit.AbsolutePosition.X) / width, 0, 1)
			applyValue(minValue + (maxValue - minValue) * fraction, step)
			refresh()
		end

		track(hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				beginDrag(function(position)
					fromX(position.X)
				end, input, frame)
			end
		end))
		track(valueBox.FocusLost:Connect(function()
			local number = tonumber(valueBox.Text)
			if number then
				applyValue(number, fineStep or step)
			end
			refresh()
		end))
		refresh()
	end

	local function makeColorRow(text, key)
		local row = makeRow(84)
		makeRowLabel(row, text)

		local hexBox = create("TextBox", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 7),
			Size = UDim2.fromOffset(78, 22),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Text,
			ClearTextOnFocus = false,
			Text = "",
		}, row)
		styleBox(hexBox)

		local holder = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 44),
			Size = UDim2.new(1, -24, 0, 28),
		}, row)
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}, holder)

		local swatchStrokes = {}
		for index, color in ipairs(SWATCHES) do
			local swatch = create("TextButton", {
				LayoutOrder = index,
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
			}, holder)
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, swatch)
			swatchStrokes[index] = create("UIStroke", {
				Color = Theme.White,
				Thickness = 2,
				Transparency = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, swatch)
			track(swatch.Activated:Connect(function()
				Config[key] = color
				syncUI()
			end))
		end

		local function refresh()
			local hex = Config[key]:ToHex()
			for index, color in ipairs(SWATCHES) do
				local selected = color:ToHex() == hex
				tween(swatchStrokes[index], 0.12, { Transparency = selected and 0 or 1 })
			end
			if not hexBox:IsFocused() then
				hexBox.Text = "#" .. string.upper(hex)
			end
		end
		table.insert(refreshers, refresh)

		track(hexBox.FocusLost:Connect(function()
			local cleaned = string.gsub(hexBox.Text, "[#%s]", "")
			if #cleaned == 6 and not string.find(cleaned, "%X") then
				local ok, color = pcall(Color3.fromHex, cleaned)
				if ok and typeof(color) == "Color3" then
					Config[key] = color
				end
			end
			syncUI()
		end))
		refresh()
	end

	-- PAGE: Aim -------------------------------------------------------------------------------------
	newPage("Aim")
	makeSection("Assist")
	makeToggle("Aim assist enabled", function()
		return Config.Enabled
	end, setEnabled)
	makeCycle("Activation mode", "ActivationMode", { "Hold", "Toggle" })
	makeCycle("Target part", "TargetPart", { "Head", "UpperTorso", "HumanoidRootPart" })
	makeCycle("Priority", "SelectionPriority", { "Crosshair", "Distance", "Health" })
	makeSection("Range and motion")
	makeSlider("FOV radius (px)", "FOVRadius", 30, 400, 5, 0, 1)
	makeSlider("Smoothing (higher = faster)", "CameraSmoothing", 0, 30, 0.5, 1)
	makeSlider("Aim distance (studs)", "MaxDistance", 50, 5000, 50, 0, 1)
	makeSection("Behaviour")
	makeConfigToggle("Target lock", "TargetLock")
	makeConfigToggle("Visibility check", "VisibilityCheck")
	makeConfigToggle("Prediction", "Prediction", resetPrediction)
	makeSlider("Prediction lead (s)", "PredictionFactor", 0, 0.5, 0.01, 2)

	-- PAGE: ESP --------------------------------------------------------------------------------------
	newPage("ESP")
	makeSection("ESP")
	makeConfigToggle("ESP enabled", "ESPEnabled")
	makeSlider("Max distance (0 - 20000)", "ESPMaxDistance", 0, 20000, 100, 0, 1)
	makeSection("Show")
	makeConfigToggle("Name", "ESPShowName")
	makeConfigToggle("Distance", "ESPShowDistance")
	makeConfigToggle("Health", "ESPShowHealth")
	makeConfigToggle("Skeleton", "ESPShowSkeleton")
	makeConfigToggle("Look direction line", "ESPShowLookLine")
	makeConfigToggle("Head circle", "ESPShowHeadCircle")
	makeConfigToggle("Outline glow", "ESPHighlight")
	makeSection("Style")
	makeColorRow("ESP color", "ESPColor")
	makeConfigToggle("Use team colors", "ESPTeamColors")
	makeConfigToggle("Use display names", "ESPUseDisplayName")
	makeSlider("Line thickness", "ESPThickness", 0.5, 4, 0.5, 1)
	makeSlider("Text size", "ESPTextSize", 10, 22, 1, 0)
	makeSlider("Look line length", "ESPLookLength", 2, 50, 1, 0)

	-- PAGE: Visual -----------------------------------------------------------------------------------
	newPage("Visual")
	makeSection("FOV circle")
	makeConfigToggle("Show FOV circle", "ShowFOV")
	makeConfigToggle("Only while aiming", "ShowFOVOnlyWhenActive")
	makeColorRow("FOV color", "FOVColor")
	makeSlider("Circle thickness", "FOVThickness", 0.5, 5, 0.5, 1)
	makeSection("Lighting")
	makeConfigToggle("Full bright", "FullBright")
	makeSlider("Brightness level", "FullBrightLevel", 1, 5, 0.5, 1)
	makeNote("Full bright restores the original lighting when switched off or closed.", 28)
	makeSection("Utilities")
	makeConfigToggle("Custom FOV", "FOVChangerEnabled")
	makeSlider("Field of view", "CustomFOV", 60, 120, 1, 0)
	makeConfigToggle("Center crosshair", "CrosshairEnabled")
	makeSlider("Crosshair size", "CrosshairSize", 4, 64, 1, 0)
	makeSlider("Crosshair gap", "CrosshairGap", 0, 32, 1, 0)
	makeSlider("Crosshair thickness", "CrosshairThickness", 1, 8, 1, 0)
	makeCycle("Theme preset", "ThemePreset", { "Cyberpunk Neon", "Midnight Purple", "Emerald Dark", "Obsidian Gold" })
	-- PAGE: Loot & Container ESP -------------------------------------------------------------------
	newPage("Loot & Items")
	makeSection("Loot & Container ESP")
	makeConfigToggle("Item ESP enabled", "LootESPEnabled")
	makeSlider("Max scan distance (studs)", "LootESPMaxDistance", 50, 20000, 50, 0, 1)
	makeConfigToggle("Show distance text", "LootESPShowDistance")
	makeConfigToggle("Show containers / drawers / boxes", "LootESPShowContainers")
	makeSection("Item categories")
	makeConfigToggle("Weapons", "LootESPShowWeapons")
	makeConfigToggle("Ammo", "LootESPShowAmmo")
	makeConfigToggle("Key and quest items", "LootESPShowImportant")
	makeConfigToggle("General materials", "LootESPShowGeneral")

	-- PAGE: Player -----------------------------------------------------------------------------------
	newPage("Player")
	makeSection("Filters (Aim and ESP)")
	makeConfigToggle("Skip teammates", "TeamCheck")
	makeConfigToggle("Include neutral players", "TargetNeutralPlayers")
	makeConfigToggle("Skip dead players", "AliveCheck")
	makeConfigToggle("Skip ForceField players", "IgnoreForceField")
	makeSection("Info")
	ui.statsLabel = makeNote("", 34)

	-- PAGE: Keys -------------------------------------------------------------------------------------
	newPage("Keys")
	makeSection("Configuration")
	makeConfigToggle("Auto-save configuration", "AutoSaveEnabled")
	makeAction("Reset configuration", function()
		resetConfig()
		syncUI()
	end)
	makeAction("Unload script", shutdown)
	makeSection("Key bindings")
	makeBind("Aim activation", "ActivationInput", false)
	makeBind("Toggle aim assist", "SystemToggleKey", true)
	makeBind("Toggle ESP", "ESPToggleKey", true)
	makeBind("Toggle full bright", "FullBrightToggleKey", true)
	makeBind("Minimize panel", "GuiToggleKey", true)
	makeNote("Click a button, then press a key or mouse button. Esc cancels, Backspace clears (not for aim activation).", 44)

	syncUI()
	selectTab("Aim")

	-- Minimize / restore ----------------------------------------------------------------------------
	setMinimized = function(value, instant)
		if closed or not ui then
			return
		end
		value = value == true
		minimized = value
		animToken += 1
		local token = animToken
		endDrag()
		clampPanelPosition()
		applyPanelPosition()

		if value then
			ui.pill.Visible = true
			if instant then
				ui.pill.GroupTransparency = 0
				ui.panel.GroupTransparency = 1
				ui.panel.Visible = false
			else
				tween(ui.pill, 0.18, { GroupTransparency = 0 })
				local t = tween(ui.panel, 0.15, { GroupTransparency = 1 })
				if t then
					t.Completed:Once(function()
						if not closed and ui and token == animToken then
							ui.panel.Visible = false
						end
					end)
				end
			end
		else
			ui.panel.Visible = true
			if instant then
				ui.panel.GroupTransparency = 0
				ui.pill.GroupTransparency = 1
				ui.pill.Visible = false
			else
				tween(ui.panel, 0.18, { GroupTransparency = 0 })
				local t = tween(ui.pill, 0.12, { GroupTransparency = 1 })
				if t then
					t.Completed:Once(function()
						if not closed and ui and token == animToken then
							ui.pill.Visible = false
						end
					end)
				end
			end
		end
	end

	track(minButton.Activated:Connect(function()
		setMinimized(true, false)
	end))
	track(pillButton.Activated:Connect(function()
		setMinimized(false, false)
	end))
	track(closeButton.Activated:Connect(shutdown))

	-- Dragging the panel by its title bar --------------------------------------------------------------
	track(dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local startPointer = Vector2.new(input.Position.X, input.Position.Y)
			local startPosition = panelPos
			beginDrag(function(position)
				panelPos = startPosition + (Vector2.new(position.X, position.Y) - startPointer)
				clampPanelPosition()
				applyPanelPosition()
			end, input, nil)
		end
	end))

	-- Responsive layout
	track(panelGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout))

	overlayGui.Parent = playerGui
	panelGui.Parent = playerGui
	updateLayout()
	setMinimized(Config.UIStartMinimized, false)
end

--------------------------------------------------------------------------------
-- 13. MAIN LOOP
--------------------------------------------------------------------------------
local function refreshCamera()
	local current = Workspace.CurrentCamera
	if current ~= camera then
		camera = current
		originalCameraFOV = camera and camera.FieldOfView or nil
		aimDefaultFOV = camera and camera.FieldOfView or nil
		aimFOVScale = 1
		releaseTarget("camera changed")
		debugLog("Camera reference refreshed")
	end
end

local function updateViewCenter()
	if not camera then
		return
	end
	if Config.FOVCenter == "Mouse" then
		viewCenter = UserInputService:GetMouseLocation()
	else
		viewCenter = camera.ViewportSize * 0.5
	end
end

local function updateAimFOVScale(dt)
	if not camera then
		return
	end
	if not aimDefaultFOV then
		aimDefaultFOV = camera.FieldOfView
	end
	local activeFOV = math.max(camera.FieldOfView, 1)
	local targetScale = math.clamp(aimDefaultFOV / activeFOV, 0.25, 4)
	-- Smooth the scale so entering/leaving ADS cannot cause a target-lock jump.
	aimFOVScale = approach(aimFOVScale, targetScale, 16, dt)
end

local function updateUtilities()
	if not camera or not ui then
		return
	end
	if originalCameraFOV == nil then
		originalCameraFOV = camera.FieldOfView
	end
	camera.FieldOfView = Config.FOVChangerEnabled and Config.CustomFOV or originalCameraFOV
	local visible = Config.CrosshairEnabled
	ui.crosshair.Visible = visible
	if visible then
		local size = Config.CrosshairSize
		local gap = Config.CrosshairGap
		local thickness = Config.CrosshairThickness
		local color = Config.CrosshairColor
		local center = camera.ViewportSize * 0.5
		local lines = ui.crosshairLines
		for _, line in ipairs(lines) do
			line.BackgroundColor3 = color
		end
		lines[1].Size = UDim2.fromOffset(thickness, size)
		lines[1].Position = UDim2.fromOffset(center.X, center.Y - gap - size * 0.5)
		lines[2].Size = UDim2.fromOffset(thickness, size)
		lines[2].Position = UDim2.fromOffset(center.X, center.Y + gap + size * 0.5)
		lines[3].Size = UDim2.fromOffset(size, thickness)
		lines[3].Position = UDim2.fromOffset(center.X - gap - size * 0.5, center.Y)
		lines[4].Size = UDim2.fromOffset(size, thickness)
		lines[4].Position = UDim2.fromOffset(center.X + gap + size * 0.5, center.Y)
	end
end

local function frameUpdate(deltaTime)
	local dt = math.clamp(deltaTime, 1 / 1000, 0.1)

	refreshCamera()
	updateViewCenter()
	updateAimFOVScale(dt)

	if active and not Config.Enabled then
		setActive(false, "disabled")
	end

	-- Guard against stuck hold input (button released outside the window, etc.).
	if active and Config.ActivationMode == "Hold" then
		if isBindingDown(Config.ActivationInput) == false then
			setActive(false, "input no longer down")
		end
	end
	if activeDrag and activeDrag.mouse and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		endDrag()
	end

	-- Aim
	local hasTarget = false
	if active and Config.Enabled and camera then
		local part = updateTarget()
		if part and currentTarget then
			hasTarget = true
			if Config.EngageEaseTime > 0 then
				engageBlend = math.min(1, engageBlend + dt / Config.EngageEaseTime)
			else
				engageBlend = 1
			end
			applyCamera(computeAimPosition(part, dt), dt)
		end
	elseif currentTarget then
		releaseTarget("inactive")
	end

	-- Visual, ESP, Lighting, GUI status
	updateVisuals(dt, hasTarget)
	espShown = updateEsp()
	updateLootEsp()
	updateLighting(dt)
	updateUtilities()
	updateStatus(hasTarget)
	updateStats(dt)
end

local function onRenderStep(deltaTime)
	if closed then
		return
	end
	local ok, err = pcall(frameUpdate, deltaTime)
	if not ok then
		frameErrors += 1
		warn("[SmoothTargetAssist] Frame error:", err)
		if frameErrors >= MAX_FRAME_ERRORS then
			warn("[SmoothTargetAssist] Too many errors; shutting down.")
			shutdown()
		end
	end
end

--------------------------------------------------------------------------------
-- 14. PUBLIC API
--------------------------------------------------------------------------------
api.Destroy = shutdown
api.GetConfig = function()
	return Config
end
api.SetConfig = function(overrides)
	if closed or type(overrides) ~= "table" then
		return
	end
	for key, value in pairs(overrides) do
		if Config[key] ~= nil then
			Config[key] = value
		end
	end
	sanitizeConfig()
	if not Config.Enabled then
		setActive(false, "disabled")
	end
	syncUI()
end
api.SetEnabled = setEnabled
api.Toggle = function()
	setEnabled(not Config.Enabled)
end
api.SetMinimized = function(value)
	if setMinimized then
		setMinimized(value, false)
	end
end
api.IsActive = function()
	return active
end
api.GetTarget = function()
	return currentTarget
end

--------------------------------------------------------------------------------
-- 15. INIT
--------------------------------------------------------------------------------
-- Tear down any previous instance so re-running never duplicates connections or UI.
local previous = shared[SHARED_KEY]
if type(previous) == "table" and type(previous.Destroy) == "function" then
	pcall(previous.Destroy)
end
shared[SHARED_KEY] = api

loadConfig()
sanitizeConfig()

-- Folder that holds optional Highlight instances (client-only, never replicated).
do
	local oldFolder = Workspace:FindFirstChild(ESP_FOLDER_NAME)
	if oldFolder then
		oldFolder:Destroy()
	end
	espFolder = create("Folder", { Name = ESP_FOLDER_NAME }, Workspace)
	local oldLootFolder = Workspace:FindFirstChild(LOOT_ESP_FOLDER_NAME)
	if oldLootFolder then
		oldLootFolder:Destroy()
	end
	lootEspFolder = create("Folder", { Name = LOOT_ESP_FOLDER_NAME }, Workspace)
end

-- Loot containers can be present before this LocalScript starts or stream in later.
registerLootFolder(Workspace:FindFirstChild("LootBags"))
registerLootFolder(Workspace:FindFirstChild("WorldFinds"))
track(Workspace.ChildAdded:Connect(function(child)
	if child.Name == "LootBags" or child.Name == "WorldFinds" then
		registerLootFolder(child)
	end
end))
for _, descendant in ipairs(Workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		registerContainerPrompt(descendant)
	end
end
track(Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		registerContainerPrompt(descendant)
	end
end))

-- Input -------------------------------------------------------------------------
track(UserInputService.InputBegan:Connect(function(input, processed)
	if closed then
		return
	end

	-- Key rebinding (started from the Keys tab).
	if listeningBind then
		if processed then
			return
		end
		local binding = nil
		local cancel = false
		local clear = false
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				cancel = true
			elseif input.KeyCode == Enum.KeyCode.Backspace then
				if listeningBind.allowClear then
					clear = true
				else
					cancel = true
				end
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				binding = input.KeyCode
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3 then
			binding = input.UserInputType
		end
		if binding or cancel or clear then
			if binding then
				Config[listeningBind.key] = binding
			elseif clear then
				Config[listeningBind.key] = false
			end
			listeningBind = nil
			syncUI()
		end
		return
	end

	if processed then
		return
	end

	if Config.GuiToggleKey and setMinimized and inputMatches(input, Config.GuiToggleKey) then
		setMinimized(not minimized, false)
		return
	end

	if Config.SystemToggleKey and inputMatches(input, Config.SystemToggleKey) then
		setEnabled(not Config.Enabled)
		debugLog("Aim assist enabled:", Config.Enabled)
		return
	end

	if Config.ESPToggleKey and inputMatches(input, Config.ESPToggleKey) then
		Config.ESPEnabled = not Config.ESPEnabled
		syncUI()
		return
	end

	if Config.FullBrightToggleKey and inputMatches(input, Config.FullBrightToggleKey) then
		Config.FullBright = not Config.FullBright
		syncUI()
		return
	end

	if not Config.Enabled then
		return
	end

	if inputMatches(input, Config.ActivationInput) then
		if Config.ActivationMode == "Toggle" then
			setActive(not active, "toggle")
		else
			setActive(true, "hold")
		end
	end
end))

track(UserInputService.InputChanged:Connect(function(input)
	if closed or not activeDrag then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		activeDrag.update(input.Position)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if closed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		endDrag()
	end
	if Config.ActivationMode == "Hold" and inputMatches(input, Config.ActivationInput) then
		setActive(false, "released")
	end
end))

track(UserInputService.WindowFocusReleased:Connect(function()
	endDrag()
	setActive(false, "focus lost")
end))

track(UserInputService.TextBoxFocused:Connect(function()
	if Config.ActivationMode == "Hold" then
		setActive(false, "textbox focus")
	end
end))

-- Players / character lifecycle ---------------------------------------------------
track(Players.PlayerAdded:Connect(function(player)
	if not table.find(playerList, player) then
		table.insert(playerList, player)
	end
end))

track(Players.PlayerRemoving:Connect(function(player)
	local index = table.find(playerList, player)
	if index then
		table.remove(playerList, index)
	end
	if player == currentTarget then
		releaseTarget("player left")
	end
	removeEsp(player)
end))

track(LocalPlayer.CharacterAdded:Connect(function()
	releaseTarget("respawned")
end))

track(LocalPlayer.CharacterRemoving:Connect(function()
	releaseTarget("character removing")
end))

-- Camera replacement ----------------------------------------------------------------
track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshCamera))

-- Close if this script instance is destroyed ----------------------------------------------
if script then
	track(script.Destroying:Connect(shutdown))
end

-- Build GUI, then start the frame loop (runs just after the default camera update) --------
buildGui()

if not closed then
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRenderStep)
	debugLog("Initialized")
end
