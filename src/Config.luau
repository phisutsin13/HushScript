--[[
	Config.luau
	HushScript – Central configuration, constants, theme, and bone definitions.
	Loaded once by the Loader and passed into every module.
]]

local Config = {}

--------------------------------------------------------------------------------
-- SERVICES (referenced for default values only — modules import their own)
--------------------------------------------------------------------------------
local Enum = Enum -- luau global

--------------------------------------------------------------------------------
-- USER CONFIG  (all values are validated by Utilities.sanitizeConfig)
--------------------------------------------------------------------------------
Config.Default = {
	-- General ---------------------------------------------------------------
	Enabled                    = true,
	SystemToggleKey            = Enum.KeyCode.RightControl,
	GuiToggleKey               = Enum.KeyCode.RightShift,
	ESPToggleKey               = false,
	FullBrightToggleKey        = false,
	UIStartMinimized           = false,
	Debug                      = false,

	-- Aim: input ------------------------------------------------------------
	ActivationInput            = Enum.UserInputType.MouseButton2,
	ActivationMode             = "Hold",      -- "Hold" | "Toggle"
	TargetLock                 = true,
	LockBreakFOVMultiplier     = 1.35,
	SwitchCooldown             = 0.25,

	-- Aim: selection --------------------------------------------------------
	TargetPart                 = "Head",
	AllowPartFallback          = true,
	TargetPartFallbacks        = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
	SelectionPriority          = "Crosshair", -- "Crosshair" | "Distance" | "Health"
	MaxDistance                = 800,
	FOVRadius                  = 150,
	FOVCenter                  = "Viewport",  -- "Viewport" | "Mouse"

	-- Aim: camera motion ----------------------------------------------------
	CameraSmoothing            = 10,
	MaxTurnRate                = 540,
	EngageEaseTime             = 0.15,
	DeadzoneDegrees            = 0.15,
	ApplyToScriptableCamera    = false,

	-- Aim: prediction -------------------------------------------------------
	Prediction                 = false,
	PredictionFactor           = 0.10,
	MaxPredictionTime          = 0.35,

	-- Player filters (shared by Aim AND ESP) --------------------------------
	TeamCheck                  = true,
	TargetNeutralPlayers       = true,
	TeamAttribute              = "",
	CustomTeamCheck            = false,
	AliveCheck                 = true,
	MinHealth                  = 0,
	IgnoreForceField           = false,

	-- Aim: visibility -------------------------------------------------------
	VisibilityCheck            = true,
	VisibilityIgnoreTransparency = 0.9,

	-- Visual: FOV circle ----------------------------------------------------
	ShowFOV                    = true,
	ShowFOVOnlyWhenActive      = false,
	FOVColor                   = Color3.fromRGB(255, 255, 255),
	FOVActiveColor             = Color3.fromRGB(120, 220, 160),
	FOVThickness               = 1.5,
	FOVTransparency            = 0.45,

	-- Visual: lighting ------------------------------------------------------
	FullBright                 = false,
	FullBrightLevel            = 2,

	-- Player ESP -------------------------------------------------------------
	ESPEnabled                 = true,
	ESPMaxDistance             = 2000,
	ESPShowName                = true,
	ESPShowDistance            = true,
	ESPShowHealth              = false,
	ESPShowSkeleton            = true,
	ESPShowLookLine            = true,
	ESPShowHeadCircle          = true,
	ESPHighlight               = false,
	ESPColor                   = Color3.fromRGB(255, 110, 110),
	ESPTeamColors              = false,
	ESPUseDisplayName          = false,
	ESPThickness               = 1.5,
	ESPTransparency            = 0.1,
	ESPTextSize                = 13,
	ESPLookLength              = 10,

	-- Loot / world item ESP -------------------------------------------------
	LootESPEnabled             = true,
	LootESPMaxDistance         = 400,
	LootESPShowDistance        = true,
	LootESPShowContainers      = true,
	LootESPShowWeapons         = true,
	LootESPShowAmmo            = true,
	LootESPShowImportant       = true,
	LootESPShowGeneral         = true,
	LootESPLootBagColor        = Color3.fromRGB(255, 215, 0),
	LootESPWeaponColor         = Color3.fromRGB(255, 100, 100),
	LootESPAmmoColor           = Color3.fromRGB(255, 210, 80),
	LootESPImportantColor      = Color3.fromRGB(255, 50, 255),
	LootESPGeneralColor        = Color3.fromRGB(0, 230, 255),
	LootESPContainerColor      = Color3.fromRGB(120, 220, 160),

	-- Persistence / utility -------------------------------------------------
	AutoSaveEnabled            = true,
	ThemePreset                = "Obsidian Gold",
	CrosshairEnabled           = false,
	CrosshairColor             = Color3.fromRGB(255, 255, 255),
	CrosshairSize              = 16,
	CrosshairGap               = 5,
	CrosshairThickness         = 2,
	FOVChangerEnabled          = false,
	CustomFOV                  = 90,
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
Config.SHARED_KEY            = "SmoothTargetAssist"
Config.OVERLAY_GUI_NAME      = "SmoothTargetAssist_Overlay"
Config.PANEL_GUI_NAME        = "SmoothTargetAssist_Panel"
Config.ESP_FOLDER_NAME       = "SmoothTargetAssist_ESP"
Config.LOOT_ESP_FOLDER_NAME  = "SmoothTargetAssist_LootESP"
Config.RENDER_NAME           = "SmoothTargetAssist_Render"
Config.CONFIG_FILE           = "HushScript_Config.json"
Config.MAX_RAY_STEPS         = 6
Config.MAX_VALID_SPEED       = 2000
Config.MAX_FRAME_ERRORS      = 5
Config.MAX_LINE_LENGTH       = 6000
Config.ESP_VIEW_MARGIN       = 600
Config.LOOT_FAR_THROTTLE_DISTANCE  = 1000
Config.LOOT_FAR_THROTTLE_INTERVAL  = 0.25
Config.TAB_NAMES = { "Aim", "ESP", "Visual", "Loot & Items", "Player", "Keys" }

--------------------------------------------------------------------------------
-- THEME
--------------------------------------------------------------------------------
Config.Theme = {
	Panel      = Color3.fromRGB(24,  26,  32),
	Title      = Color3.fromRGB(32,  35,  43),
	Card       = Color3.fromRGB(36,  39,  48),
	Stroke     = Color3.fromRGB(58,  62,  74),
	Text       = Color3.fromRGB(232, 235, 242),
	SubText    = Color3.fromRGB(140, 146, 160),
	Accent     = Color3.fromRGB(110, 160, 255),
	OnAccent   = Color3.fromRGB(16,  20,  30),
	Good       = Color3.fromRGB(120, 220, 160),
	Warn       = Color3.fromRGB(255, 205, 100),
	Off        = Color3.fromRGB(110, 114, 128),
	Danger     = Color3.fromRGB(235, 90,  90),
	SwitchOff  = Color3.fromRGB(70,  74,  88),
	White      = Color3.fromRGB(255, 255, 255),
	Black      = Color3.fromRGB(0,   0,   0),
}

Config.FONT      = Enum.Font.GothamMedium
Config.FONT_BOLD = Enum.Font.GothamBold

Config.SWATCHES = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(90,  200, 255),
	Color3.fromRGB(120, 220, 160),
	Color3.fromRGB(255, 214, 102),
	Color3.fromRGB(255, 110, 110),
	Color3.fromRGB(180, 140, 255),
}

--------------------------------------------------------------------------------
-- SKELETON BONE PAIRS
--------------------------------------------------------------------------------
Config.R15_BONES = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm"  }, { "LeftUpperArm",  "LeftLowerArm"  }, { "LeftLowerArm",  "LeftHand"  },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg"  }, { "LeftUpperLeg",  "LeftLowerLeg"  }, { "LeftLowerLeg",  "LeftFoot"  },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
Config.R6_BONES = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
Config.MAX_BONES = #Config.R15_BONES

--------------------------------------------------------------------------------
-- LIGHTING PROPERTY LIST  (restored when FullBright is turned off)
--------------------------------------------------------------------------------
Config.LIGHTING_PROPS = {
	"Brightness", "ClockTime", "FogStart", "FogEnd",
	"GlobalShadows", "Ambient", "OutdoorAmbient",
}

--------------------------------------------------------------------------------
-- SANITIZATION RULES
--------------------------------------------------------------------------------
Config.BOOL_DEFAULTS = {
	Enabled = true, Debug = false, UIStartMinimized = false,
	TargetLock = true, AllowPartFallback = true, Prediction = false,
	ApplyToScriptableCamera = false, TeamCheck = true,
	TargetNeutralPlayers = true, AliveCheck = true, IgnoreForceField = false,
	VisibilityCheck = true, ShowFOV = true, ShowFOVOnlyWhenActive = false,
	FullBright = false, ESPEnabled = true, ESPShowName = true,
	ESPShowDistance = true, ESPShowHealth = false, ESPShowSkeleton = true,
	ESPShowLookLine = true, ESPShowHeadCircle = true, ESPHighlight = false,
	ESPTeamColors = false, ESPUseDisplayName = false, LootESPEnabled = true,
	LootESPShowDistance = true, LootESPShowContainers = true,
	LootESPShowWeapons = true, LootESPShowAmmo = true,
	LootESPShowImportant = true, LootESPShowGeneral = true,
	AutoSaveEnabled = true, CrosshairEnabled = false, FOVChangerEnabled = false,
}

-- { key, min, max, default }
Config.NUMBER_RULES = {
	{ "LockBreakFOVMultiplier", 1, 5, 1.35 }, { "SwitchCooldown", 0, 5, 0.25 },
	{ "MaxDistance", 1, 20000, 800 },           { "FOVRadius", 5, 2000, 150 },
	{ "CameraSmoothing", 0, 200, 10 },          { "MaxTurnRate", 0, 20000, 540 },
	{ "EngageEaseTime", 0, 5, 0.15 },           { "DeadzoneDegrees", 0, 45, 0.15 },
	{ "PredictionFactor", 0, 2, 0.10 },         { "MaxPredictionTime", 0, 2, 0.35 },
	{ "MinHealth", 0, 1e6, 0 },                 { "VisibilityIgnoreTransparency", 0, 1, 0.9 },
	{ "FOVThickness", 0.5, 10, 1.5 },           { "FOVTransparency", 0, 1, 0.45 },
	{ "FullBrightLevel", 0.5, 5, 2 },
	{ "ESPMaxDistance", 0, 20000, 2000 },        { "ESPLookLength", 1, 100, 10 },
	{ "ESPThickness", 0.5, 6, 1.5 },            { "ESPTransparency", 0, 0.9, 0.1 },
	{ "ESPTextSize", 9, 28, 13 },
	{ "LootESPMaxDistance", 50, 20000, 400 },
	{ "CrosshairSize", 4, 64, 16 },             { "CrosshairGap", 0, 32, 5 },
	{ "CrosshairThickness", 1, 8, 2 },          { "CustomFOV", 60, 120, 90 },
}

Config.COLOR_DEFAULTS = {
	FOVColor              = Color3.fromRGB(255, 255, 255),
	FOVActiveColor        = Color3.fromRGB(120, 220, 160),
	ESPColor              = Color3.fromRGB(255, 110, 110),
	LootESPLootBagColor   = Color3.fromRGB(255, 215, 0),
	LootESPWeaponColor    = Color3.fromRGB(255, 100, 100),
	LootESPAmmoColor      = Color3.fromRGB(255, 210, 80),
	LootESPImportantColor = Color3.fromRGB(255, 50, 255),
	LootESPGeneralColor   = Color3.fromRGB(0, 230, 255),
	LootESPContainerColor = Color3.fromRGB(120, 220, 160),
	CrosshairColor        = Color3.fromRGB(255, 255, 255),
}

Config.KEY_FIELDS = { "SystemToggleKey", "GuiToggleKey", "ESPToggleKey", "FullBrightToggleKey" }

return Config
