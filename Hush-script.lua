--[[
	Hush-script.lua  (Loader)  –  UI v3 PREMIUM (Luxury + Vibrant + Smooth)
	HushScript – Modern entry point with premium design.
	Place in: StarterPlayer > StarterPlayerScripts

	Base system unchanged. Only UI redesigned with luxury colors and animations.
]]

--------------------------------------------------------------------------------
-- 1. SERVICES
--------------------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local StatsService     = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[HushScript] Must run as a LocalScript (client).")
	return
end

--------------------------------------------------------------------------------
-- 2. REMOTE LOADER
--------------------------------------------------------------------------------
local BASE_URL = "https://raw.githubusercontent.com/phisutsin13/HushScript/refs/heads/main/src/"

local function loadModule(relativePath)
	local url     = BASE_URL .. relativePath
	local success, result = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	if not success then
		error("[HushScript] Failed to load module: " .. relativePath .. "\n" .. tostring(result))
	end
	return result
end

-- Load modules (order matters: Config first, then Utilities)
local ConfigDef    = loadModule("Config.luau")
local Utilities    = loadModule("Modules/Utilities.luau")
local TargetAssist = loadModule("Modules/TargetAssist.luau")
local ItemESP      = loadModule("Modules/ItemESP.luau")
local MonsterESP   = loadModule("Modules/MonsterESP.luau")

--------------------------------------------------------------------------------
-- 3. ACTIVE CONFIG
--------------------------------------------------------------------------------
local Config = {}
for k, v in pairs(ConfigDef.Default) do Config[k] = v end
local DEFAULT_CONFIG = table.clone(Config)

-- PREMIUM LUXURY THEME - Vibrant, Rich Colors
local UITheme = setmetatable({
	-- Backgrounds
	Panel           = Color3.fromRGB(11, 12, 18),
	Title           = Color3.fromRGB(8, 10, 16),
	Card            = Color3.fromRGB(18, 21, 35),
	CardHover       = Color3.fromRGB(26, 31, 50),
	
	-- Accents - Vibrant Gradient (Cyan -> Purple)
	Accent          = Color3.fromRGB(0, 200, 255),    -- Cyan
	Accent2         = Color3.fromRGB(138, 43, 226),   -- Vibrant Purple
	Accent3         = Color3.fromRGB(255, 20, 147),   -- Deep Pink
	OnAccent        = Color3.fromRGB(12, 13, 20),
	
	-- Status Colors
	Good            = Color3.fromRGB(0, 255, 136),    -- Bright Cyan-Green
	Warn            = Color3.fromRGB(255, 180, 0),    -- Gold/Orange
	Off             = Color3.fromRGB(70, 80, 110),    -- Muted Blue-Gray
	Danger          = Color3.fromRGB(255, 60, 100),   -- Vibrant Red-Pink
	
	-- Text & UI Elements
	Text            = Color3.fromRGB(240, 245, 255),  -- Almost white
	SubText         = Color3.fromRGB(140, 155, 190),  -- Muted Blue
	Stroke          = Color3.fromRGB(45, 55, 85),     -- Dark Blue Stroke
	SwitchOff       = Color3.fromRGB(35, 42, 65),
	White           = Color3.fromRGB(255, 255, 255),
}, { __index = ConfigDef.Theme })

-- Build consts
local consts = {
	MAX_RAY_STEPS             = ConfigDef.MAX_RAY_STEPS,
	MAX_VALID_SPEED           = ConfigDef.MAX_VALID_SPEED,
	MAX_FRAME_ERRORS          = ConfigDef.MAX_FRAME_ERRORS,
	MAX_LINE_LENGTH           = ConfigDef.MAX_LINE_LENGTH,
	ESP_VIEW_MARGIN           = ConfigDef.ESP_VIEW_MARGIN,
	LOOT_FAR_THROTTLE_DISTANCE = ConfigDef.LOOT_FAR_THROTTLE_DISTANCE,
	LOOT_FAR_THROTTLE_INTERVAL = ConfigDef.LOOT_FAR_THROTTLE_INTERVAL,
	Theme    = UITheme,
	FONT     = Enum.Font.GothamMedium,
	FONT_BOLD = Enum.Font.GothamBold,
	SWATCHES = ConfigDef.SWATCHES,
	R15_BONES = ConfigDef.R15_BONES,
	R6_BONES  = ConfigDef.R6_BONES,
	MAX_BONES = ConfigDef.MAX_BONES,
	LIGHTING_PROPS = ConfigDef.LIGHTING_PROPS,
	TAB_NAMES      = ConfigDef.TAB_NAMES,
	SHARED_KEY         = ConfigDef.SHARED_KEY,
	OVERLAY_GUI_NAME   = ConfigDef.OVERLAY_GUI_NAME,
	PANEL_GUI_NAME     = ConfigDef.PANEL_GUI_NAME,
	ESP_FOLDER_NAME    = ConfigDef.ESP_FOLDER_NAME,
	LOOT_ESP_FOLDER_NAME = ConfigDef.LOOT_ESP_FOLDER_NAME,
	RENDER_NAME        = ConfigDef.RENDER_NAME,
	CONFIG_FILE        = ConfigDef.CONFIG_FILE,
}

local sanRules = {
	BOOL_DEFAULTS  = ConfigDef.BOOL_DEFAULTS,
	NUMBER_RULES   = ConfigDef.NUMBER_RULES,
	COLOR_DEFAULTS = ConfigDef.COLOR_DEFAULTS,
	KEY_FIELDS     = ConfigDef.KEY_FIELDS,
}

--------------------------------------------------------------------------------
-- 4. STATE
--------------------------------------------------------------------------------
local closed       = false
local connections  = {}
local activeTweens = {}
local refreshers   = {}
local frameErrors  = 0
local styleVersion = 0
local playerList   = Players:GetPlayers()

local camera           = Workspace.CurrentCamera
local originalCameraFOV = nil

local savedLighting   = nil
local savedAtmosphere = nil
local lightingTimer   = 0

-- GUI
local ui             = nil
local minimized      = false
local animToken      = 0
local panelPos       = Vector2.new(16, 64)
local panelSize      = Vector2.new(340, 480)
local activeDrag     = nil
local dragScroll     = nil
local listeningBind  = nil
local lastStatusText  = nil
local lastStatusColor = nil
local statsTimer     = 0
local fpsSample      = 60
local setMinimizedFn = nil
local espShown       = 0

local function isClosed() return closed end

--------------------------------------------------------------------------------
-- 5. UTILITIES WRAPPERS
--------------------------------------------------------------------------------
local function track(conn) return Utilities.track(connections, conn) end
local function create(cls, props, parent) return Utilities.create(cls, props, parent) end

-- Premium tween with quad/back easing
local function tw(inst, dur, props, style, dir)
	if closed or not inst then return nil end
	local ok, t = pcall(function()
		return TweenService:Create(inst, TweenInfo.new(dur, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	end)
	if not ok or not t then return nil end
	activeTweens[t] = true
	t.Completed:Once(function() activeTweens[t] = nil end)
	t:Play()
	return t
end

local function markStyleDirty() styleVersion += 1 end
local function schedSave() Utilities.scheduleConfigSave(Config, consts.CONFIG_FILE, isClosed) end
local function saveNow()   Utilities.saveConfigNow(Config, consts.CONFIG_FILE) end

local function sanitizeCfg()
	Utilities.sanitizeConfig(Config, sanRules)
end

local function syncUI()
	markStyleDirty()
	for _, r in ipairs(refreshers) do r() end
	schedSave()
end

local function resetConfig()
	for k, v in pairs(DEFAULT_CONFIG) do Config[k] = v end
	sanitizeCfg()
	saveNow()
end

--------------------------------------------------------------------------------
-- 6. DRAG HELPERS
--------------------------------------------------------------------------------
local function endDrag()
	activeDrag = nil
	if dragScroll then
		if dragScroll.Parent then dragScroll.ScrollingEnabled = true end
		dragScroll = nil
	end
end

local function beginDrag(updateFn, startInput, scrollFrame)
	activeDrag = {
		update = updateFn,
		mouse  = startInput.UserInputType == Enum.UserInputType.MouseButton1,
	}
	if scrollFrame then
		dragScroll = scrollFrame
		scrollFrame.ScrollingEnabled = false
	end
	updateFn(startInput.Position)
end

--------------------------------------------------------------------------------
-- 7. LIGHTING (full-bright)
--------------------------------------------------------------------------------
local function setIfDifferent(inst, prop, value)
	if inst[prop] ~= value then inst[prop] = value end
end

local function applyFullBright()
	if not savedLighting then
		savedLighting = {}
		for _, name in ipairs(consts.LIGHTING_PROPS) do savedLighting[name] = Lighting[name] end
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then savedAtmosphere = { instance = atm, Density = atm.Density, Haze = atm.Haze } end
	end
	pcall(function()
		setIfDifferent(Lighting, "Brightness",     Config.FullBrightLevel)
		setIfDifferent(Lighting, "ClockTime",      14)
		setIfDifferent(Lighting, "GlobalShadows",  false)
		setIfDifferent(Lighting, "FogStart",       99999)
		setIfDifferent(Lighting, "FogEnd",         100000)
		setIfDifferent(Lighting, "Ambient",        Color3.fromRGB(190, 190, 190))
		setIfDifferent(Lighting, "OutdoorAmbient", Color3.fromRGB(190, 190, 190))
		if savedAtmosphere and savedAtmosphere.instance.Parent then
			setIfDifferent(savedAtmosphere.instance, "Density", 0)
			setIfDifferent(savedAtmosphere.instance, "Haze",    0)
		end
	end)
end

local function restoreLighting()
	if savedLighting then
		for _, name in ipairs(consts.LIGHTING_PROPS) do
			local v = savedLighting[name]
			if v ~= nil then pcall(function() Lighting[name] = v end) end
		end
		savedLighting = nil
	end
	if savedAtmosphere then
		local info = savedAtmosphere
		savedAtmosphere = nil
		if info.instance and info.instance.Parent then
			pcall(function()
				info.instance.Density = info.Density
				info.instance.Haze    = info.Haze
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
-- 8. MODULE INSTANCES
--------------------------------------------------------------------------------
local espFolder, lootEspFolder
local targetAssist, itemESP, monsterESP

--------------------------------------------------------------------------------
-- 9. SHUTDOWN
--------------------------------------------------------------------------------
local api = {}

local function shutdown()
	if closed then return end
	closed      = true
	animToken  += 1
	activeDrag  = nil
	dragScroll  = nil
	listeningBind = nil

	pcall(function() RunService:UnbindFromRenderStep(consts.RENDER_NAME) end)

	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)

	for t in pairs(activeTweens) do pcall(function() t:Cancel() end) end
	table.clear(activeTweens)

	restoreLighting()
	saveNow()

	if camera and originalCameraFOV then
		pcall(function() camera.FieldOfView = originalCameraFOV end)
	end
	originalCameraFOV = nil

	if monsterESP then monsterESP:clear() end
	if itemESP    then itemESP:clear()    end

	if espFolder     then pcall(function() espFolder:Destroy()     end); espFolder     = nil end
	if lootEspFolder then pcall(function() lootEspFolder:Destroy() end); lootEspFolder = nil end

	if ui then
		local localUi = ui; ui = nil
		for _, key in ipairs({ "panelGui", "overlayGui" }) do
			local g = localUi[key]
			if g then pcall(function() g:Destroy() end) end
		end
	end

	table.clear(refreshers)
	table.clear(playerList)
	camera        = nil
	setMinimizedFn = nil

	if shared[consts.SHARED_KEY] == api then
		shared[consts.SHARED_KEY] = nil
	end

	if Config.Debug then print("[HushScript] Closed and cleaned up") end
end

--------------------------------------------------------------------------------
-- 10. FOV CIRCLE (Visual)
--------------------------------------------------------------------------------
local visAlpha     = 0
local lockBlend    = 0
local activeBlend  = 0
local enabledBlend = 1
local displayRadius = 150

local function updateVisuals(dt, hasTarget)
	if not ui or not ui.ring then return end
	local ta = targetAssist

	local wantVisible = Config.ShowFOV and (ta.active or not Config.ShowFOVOnlyWhenActive)
	visAlpha     = Utilities.approach(visAlpha,     wantVisible and 1 or 0,      12, dt)
	lockBlend    = Utilities.approach(lockBlend,    hasTarget and 1 or 0,        10, dt)
	activeBlend  = Utilities.approach(activeBlend,  ta.active and 1 or 0,        10, dt)
	enabledBlend = Utilities.approach(enabledBlend, Config.Enabled and 1 or 0.45, 10, dt)

	if visAlpha < 0.01 then ui.ring.Visible = false; return end
	ui.ring.Visible = true

	local radius = Config.FOVRadius * (1 - 0.04 * lockBlend)
	displayRadius = Utilities.approach(displayRadius, radius, 14, dt)

	ui.ring.Size               = UDim2.fromOffset(displayRadius * 2, displayRadius * 2)
	ui.ring.Position           = UDim2.fromOffset(ta.viewCenter.X, ta.viewCenter.Y)
	ui.ringStroke.Thickness    = Config.FOVThickness
	ui.ringStroke.Color        = Config.FOVColor:Lerp(Config.FOVActiveColor, lockBlend)

	local opacity = (1 - Config.FOVTransparency) * visAlpha * enabledBlend * (0.7 + 0.3 * activeBlend)
	ui.ringStroke.Transparency = 1 - math.clamp(opacity, 0, 1)
end

--------------------------------------------------------------------------------
-- 11. STATUS / STATS
--------------------------------------------------------------------------------
local function updateStatus(hasTarget)
	if not ui then return end
	local ta    = targetAssist
	local Theme = consts.Theme
	local text, color
	if not Config.Enabled then
		text, color = "Aim off", Theme.Off
	elseif ta.active and hasTarget and ta.currentTarget then
		text, color = "Locked · " .. string.sub(ta.currentTarget.Name, 1, 18), Theme.Good
	elseif ta.active then
		text, color = "Searching…", Theme.Warn
	else
		local verb = Config.ActivationMode == "Toggle" and "press " or "hold "
		text, color = "Ready · " .. verb .. Utilities.bindingName(Config.ActivationInput), Theme.Accent
	end
	if text ~= lastStatusText then
		lastStatusText = text
		ui.statusLabel.Text = text
	end
	if color ~= lastStatusColor then
		lastStatusColor = color
		tw(ui.statusDot, 0.3, { BackgroundColor3 = color }, Enum.EasingStyle.Quad)
		tw(ui.pillDot,   0.3, { BackgroundColor3 = color }, Enum.EasingStyle.Quad)
		if ui.statusGlow then tw(ui.statusGlow, 0.3, { Color = color }, Enum.EasingStyle.Quad) end
	end
end

local function updateStats(dt)
	if dt > 0 then fpsSample = fpsSample * 0.9 + (1 / dt) * 0.1 end
	statsTimer += dt
	if statsTimer < 0.3 then return end
	statsTimer = 0
	if ui and ui.statsLabel then
		local ping, memory = "n/a", "n/a"
		pcall(function() ping   = StatsService.Network.ServerStatsItem["Data Ping"]:GetValueString() end)
		pcall(function() memory = string.format("%.0f MB", StatsService:GetTotalMemoryUsageMb())    end)
		ui.statsLabel.Text = string.format(
			"FPS: %.0f  ·  Ping: %s  ·  Memory: %s\nPlayers: %d  ·  ESP drawn: %d  ·  Target: %s",
			fpsSample, ping, memory, #playerList, espShown,
			targetAssist.currentTarget and targetAssist.currentTarget.Name or "none"
		)
	end
end

local function updateUtilities()
	if not camera or not ui then return end
	if originalCameraFOV == nil then originalCameraFOV = camera.FieldOfView end
	camera.FieldOfView = Config.FOVChangerEnabled and Config.CustomFOV or originalCameraFOV

	local visible = Config.CrosshairEnabled
	ui.crosshair.Visible = visible
	if visible then
		local size   = Config.CrosshairSize
		local gap    = Config.CrosshairGap
		local thick  = Config.CrosshairThickness
		local color  = Config.CrosshairColor
		local center = camera.ViewportSize * 0.5
		local lines  = ui.crosshairLines
		for _, line in ipairs(lines) do line.BackgroundColor3 = color end
		lines[1].Size     = UDim2.fromOffset(thick, size);  lines[1].Position = UDim2.fromOffset(center.X, center.Y - gap - size*0.5)
		lines[2].Size     = UDim2.fromOffset(thick, size);  lines[2].Position = UDim2.fromOffset(center.X, center.Y + gap + size*0.5)
		lines[3].Size     = UDim2.fromOffset(size, thick);  lines[3].Position = UDim2.fromOffset(center.X - gap - size*0.5, center.Y)
		lines[4].Size     = UDim2.fromOffset(size, thick);  lines[4].Position = UDim2.fromOffset(center.X + gap + size*0.5, center.Y)
	end
end

--------------------------------------------------------------------------------
-- 12. GUI - PREMIUM DESIGN
--------------------------------------------------------------------------------
local TITLE_H  = 56
local STATUS_Y = 62
local TABS_Y   = 110
local PAGES_Y  = 150

local function applyPanelPosition()
	if not ui then return end
	ui.panel.Position = UDim2.fromOffset(panelPos.X, panelPos.Y)
	ui.pill.Position  = UDim2.fromOffset(panelPos.X, panelPos.Y)
end

local function clampPanelPosition()
	if not ui then return end
	local area = ui.panelGui.AbsoluteSize
	local maxX = math.max(8, area.X - panelSize.X - 8)
	local maxY = math.max(8, area.Y - panelSize.Y - 8)
	panelPos   = Vector2.new(math.clamp(panelPos.X, 8, maxX), math.clamp(panelPos.Y, 8, maxY))
end

local function updateLayout()
	if closed or not ui then return end
	local area   = ui.panelGui.AbsoluteSize
	local width  = math.clamp(area.X - 16, 240, 380)
	local height = math.clamp(area.Y - 16, 280, 600)
	panelSize    = Vector2.new(width, height)
	ui.panel.Size = UDim2.fromOffset(width, height)
	clampPanelPosition()
	applyPanelPosition()
end

local function buildGui()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		or LocalPlayer:WaitForChild("PlayerGui", 10)
	if closed or not playerGui then
		if not playerGui then warn("[HushScript] PlayerGui not found; running without GUI.") end
		return
	end

	for _, name in ipairs({ consts.OVERLAY_GUI_NAME, consts.PANEL_GUI_NAME }) do
		local old = playerGui:FindFirstChild(name)
		if old then old:Destroy() end
	end

	local Theme     = consts.Theme
	local FONT      = consts.FONT
	local FONT_BOLD = consts.FONT_BOLD
	local TAB_NAMES = consts.TAB_NAMES
	local SWATCHES  = consts.SWATCHES

	-- Overlay GUI (FOV circle + ESP) ----------------------------------------
	local overlayGui = create("ScreenGui", {
		Name           = consts.OVERLAY_GUI_NAME,
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		DisplayOrder   = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local espRoot = create("Frame", {
		Name                  = "ESPRoot",
		BackgroundTransparency = 1,
		BorderSizePixel       = 0,
		Active                = false,
		Interactable          = false,
		Size                  = UDim2.fromScale(1, 1),
	}, overlayGui)
	local ring = create("Frame", {
		Name                  = "FOVRing",
		AnchorPoint           = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel       = 0,
		Active                = false,
		Interactable          = false,
		Size                  = UDim2.fromOffset(Config.FOVRadius * 2, Config.FOVRadius * 2),
		Position              = UDim2.fromScale(0.5, 0.5),
		Visible               = false,
	}, overlayGui)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local ringStroke = create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness        = Config.FOVThickness,
		Color            = Config.FOVColor,
		Transparency     = 1,
	}, ring)
	displayRadius = Config.FOVRadius

	-- Panel GUI - PREMIUM LOOK --------------------------------------------------
	local panelGui = create("ScreenGui", {
		Name           = consts.PANEL_GUI_NAME,
		ResetOnSpawn   = false,
		IgnoreGuiInset = false,
		DisplayOrder   = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local panel = create("CanvasGroup", {
		Name              = "Panel",
		BackgroundColor3  = Theme.Panel,
		BorderSizePixel   = 0,
		Active            = true,
		Size              = UDim2.fromOffset(panelSize.X, panelSize.Y),
		Position          = UDim2.fromOffset(panelPos.X, panelPos.Y),
		GroupTransparency = 1,
		Visible           = false,
	}, panelGui)
	create("UICorner", { CornerRadius = UDim.new(0, 18) }, panel)
	
	-- Glowing border effect
	local panelStroke = create("UIStroke", {
		Color = Theme.Accent,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = 0.6,
	}, panel)
	
	-- Subtle shadow (dark gradient behind)
	local shadowGrad = create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(
			Color3.fromRGB(0, 0, 0),
			Color3.fromRGB(0, 0, 0),
			Color3.fromRGB(0, 0, 0)
		),
		Transparency = NumberSequence.new(0.7),
	}, panel)

	-- PREMIUM Title Bar with Gradient
	local titleBar = create("Frame", {
		Name             = "TitleBar",
		BackgroundColor3 = Theme.Title,
		BorderSizePixel  = 0,
		Size             = UDim2.new(1, 0, 0, TITLE_H),
	}, panel)
	
	-- Gradient overlay on title
	create("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(
			Color3.fromRGB(20, 25, 45),
			Color3.fromRGB(15, 20, 40)
		),
	}, titleBar)

	local dragHandle = create("Frame", {
		Name                  = "DragHandle",
		BackgroundTransparency = 1,
		BorderSizePixel       = 0,
		Active                = true,
		Size                  = UDim2.new(1, -80, 1, 0),
	}, titleBar)

	-- Premium Logo Mark (Glowing circle with gradient)
	local logo = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, dragHandle)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, logo)
	create("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
	}, logo)
	local logoGlow = create("UIStroke", {
		Color = Theme.Accent,
		Thickness = 1,
		Transparency = 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, logo)

	create("TextLabel", {
		Name                  = "Title",
		BackgroundTransparency = 1,
		Active                = false,
		Position              = UDim2.fromOffset(44, 0),
		Size                  = UDim2.new(1, -44, 1, 0),
		Font                  = FONT_BOLD,
		TextSize              = 16,
		TextColor3            = Theme.Text,
		TextXAlignment        = Enum.TextXAlignment.Left,
		Text                  = "HushScript",
	}, dragHandle)

	-- Premium title buttons with glow on hover
	local function makeTitleButton(name, posX, text, textColor, accentColor)
		local btn = create("TextButton", {
			Name             = name,
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(1, posX, 0.5, 0),
			Size             = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Theme.Card,
			BackgroundTransparency = 0,
			BorderSizePixel  = 0,
			AutoButtonColor  = false,
			Font             = FONT_BOLD,
			TextSize         = 18,
			TextColor3       = textColor,
			Text             = text,
		}, titleBar)
		create("UICorner", { CornerRadius = UDim.new(0, 10) }, btn)
		local btnGlow = create("UIStroke", {
			Color = accentColor or Theme.Accent,
			Thickness = 1.5,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, btn)
		
		track(btn.MouseEnter:Connect(function()
			tw(btn, 0.2, { BackgroundColor3 = Theme.CardHover }, Enum.EasingStyle.Quad)
			tw(btnGlow, 0.25, { Transparency = 0 }, Enum.EasingStyle.Quad)
		end))
		track(btn.MouseLeave:Connect(function()
			tw(btn, 0.25, { BackgroundColor3 = Theme.Card }, Enum.EasingStyle.Quad)
			tw(btnGlow, 0.3, { Transparency = 1 }, Enum.EasingStyle.Quad)
		end))
		
		return btn, btnGlow
	end
	
	local minButton   = makeTitleButton("Minimize", -72, "−", Theme.SubText, Theme.Accent)
	local closeButton = makeTitleButton("Close",    -34, "✕", Theme.Danger, Theme.Danger)

	-- Status card (Glowing with color-coded indicator)
	local statusFrame = create("Frame", {
		Name             = "Status",
		BackgroundColor3 = Theme.Card,
		BorderSizePixel  = 0,
		Position         = UDim2.fromOffset(12, STATUS_Y),
		Size             = UDim2.new(1, -24, 0, 36),
	}, panel)
	create("UICorner", { CornerRadius = UDim.new(0, 12) }, statusFrame)
	
	local statusGlow = create("UIStroke", {
		Color = Theme.Good,
		Thickness = 1.5,
		Transparency = 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, statusFrame)
	
	-- Animated pulsing indicator dot
	local statusDot = create("Frame", {
		AnchorPoint      = Vector2.new(0, 0.5),
		Position         = UDim2.new(0, 14, 0.5, 0),
		Size             = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Good,
		BorderSizePixel  = 0,
	}, statusFrame)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, statusDot)
	
	local dotGlow = create("UIStroke", {
		Color = Theme.Good,
		Thickness = 1,
		Transparency = 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, statusDot)

	local statusLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(34, 0),
		Size                   = UDim2.new(1, -44, 1, 0),
		Font                   = FONT,
		TextSize               = 13,
		TextColor3             = Theme.Text,
		TextXAlignment         = Enum.TextXAlignment.Left,
		TextTruncate           = Enum.TextTruncate.AtEnd,
		Text                   = "Initializing…",
	}, statusFrame)

	-- Minimized pill (floating button)
	local pill = create("CanvasGroup", {
		Name              = "Minimized",
		BackgroundColor3  = Theme.Card,
		BorderSizePixel   = 0,
		Size              = UDim2.fromOffset(120, 40),
		Position          = UDim2.fromOffset(panelPos.X, panelPos.Y),
		GroupTransparency = 1,
		Visible           = false,
	}, panelGui)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	create("UIStroke", {
		Color = Theme.Accent,
		Thickness = 1.5,
		Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, pill)
	
	-- Gradient on pill background
	create("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(Theme.Card, Theme.CardHover),
	}, pill)
	
	local pillDot = create("Frame", {
		AnchorPoint      = Vector2.new(0, 0.5),
		Position         = UDim2.new(0, 14, 0.5, 0),
		Size             = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Good,
		BorderSizePixel  = 0,
	}, pill)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pillDot)
	
	create("UIStroke", {
		Color = Theme.Good,
		Thickness = 1,
		Transparency = 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, pillDot)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(32, 0),
		Size                   = UDim2.new(1, -40, 1, 0),
		Font                   = FONT_BOLD,
		TextSize               = 13,
		TextColor3             = Theme.Accent,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "HushScript",
	}, pill)
	
	local pillButton = create("TextButton", {
		Name                  = "Restore",
		BackgroundTransparency = 1,
		Size                  = UDim2.fromScale(1, 1),
		Text                  = "",
		AutoButtonColor       = false,
	}, pill)

	track(pillButton.MouseEnter:Connect(function()
		tw(pill, 0.2, { BackgroundColor3 = Theme.CardHover }, Enum.EasingStyle.Back)
	end))
	track(pillButton.MouseLeave:Connect(function()
		tw(pill, 0.25, { BackgroundColor3 = Theme.Card }, Enum.EasingStyle.Back)
	end))

	ui = {
		overlayGui    = overlayGui,
		espRoot       = espRoot,
		ring          = ring,
		ringStroke    = ringStroke,
		panelGui      = panelGui,
		panel         = panel,
		pill          = pill,
		statusDot     = statusDot,
		statusLabel   = statusLabel,
		statusGlow    = statusGlow,
		pillDot       = pillDot,
		statsLabel    = nil,
		dotGlow       = dotGlow,
	}

	-- Crosshair
	local crosshair = create("Frame", {
		Name                  = "Crosshair",
		BackgroundTransparency = 1,
		Size                  = UDim2.fromScale(1, 1),
		Visible               = false,
	}, overlayGui)
	local crosshairLines = {}
	for i = 1, 4 do
		crosshairLines[i] = create("Frame", {
			BackgroundColor3 = Config.CrosshairColor,
			BorderSizePixel  = 0,
			AnchorPoint      = Vector2.new(0.5, 0.5),
		}, crosshair)
	end
	ui.crosshair      = crosshair
	ui.crosshairLines = crosshairLines

	if monsterESP then monsterESP.espRoot = espRoot; monsterESP.camera = camera end

	------------------------------------------------------------------------
	-- TAB SYSTEM WITH SLIDING INDICATOR
	------------------------------------------------------------------------
	local pages      = {}
	local tabButtons = {}
	local currentPage = nil
	local selectedTab = nil

	local function selectTab(name, instant)
		endDrag()
		local firstSelect = selectedTab == nil
		selectedTab = name

		for pageName, page in pairs(pages) do
			page.frame.Visible = pageName == name
		end
		for tabName, button in pairs(tabButtons) do
			local sel = tabName == name
			tw(button, 0.25, {
				TextColor3 = sel and Theme.Accent or Theme.SubText,
				BackgroundColor3 = sel and Color3.fromRGB(30, 35, 60) or Theme.Card,
			}, Enum.EasingStyle.Quad)
		end
	end

	-- Modern tab bar with rounded corners
	local tabBar = create("Frame", {
		Name                  = "Tabs",
		BackgroundColor3      = Theme.Card,
		BorderSizePixel       = 0,
		Position              = UDim2.fromOffset(12, TABS_Y),
		Size                  = UDim2.new(1, -24, 0, 38),
	}, panel)
	create("UICorner", { CornerRadius = UDim.new(0, 12) }, tabBar)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.Card, Color3.fromRGB(22, 26, 42)),
	}, tabBar)

	for index, name in ipairs(TAB_NAMES) do
		local button = create("TextButton", {
			Name             = name,
			Position         = UDim2.new((index - 1) / #TAB_NAMES, 6, 0, 6),
			Size             = UDim2.new(1 / #TAB_NAMES, -12, 1, -12),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel  = 0,
			AutoButtonColor  = false,
			Font             = FONT_BOLD,
			TextSize         = 12,
			TextColor3       = Theme.SubText,
			Text             = name,
		}, tabBar)
		create("UICorner", { CornerRadius = UDim.new(0, 10) }, button)
		tabButtons[name] = button
		track(button.Activated:Connect(function() selectTab(name) end))
		
		-- Hover effect
		track(button.MouseEnter:Connect(function()
			if selectedTab ~= name then
				tw(button, 0.2, { BackgroundColor3 = Color3.fromRGB(28, 32, 52) }, Enum.EasingStyle.Quad)
			end
		end))
		track(button.MouseLeave:Connect(function()
			if selectedTab ~= name then
				tw(button, 0.25, { BackgroundColor3 = Theme.Card }, Enum.EasingStyle.Quad)
			end
		end))
	end

	local function newPage(name)
		local frame = create("ScrollingFrame", {
			Name                 = name,
			BackgroundTransparency = 1,
			BorderSizePixel      = 0,
			Position             = UDim2.fromOffset(0, PAGES_Y),
			Size                 = UDim2.new(1, 0, 1, -PAGES_Y),
			CanvasSize           = UDim2.new(),
			AutomaticCanvasSize  = Enum.AutomaticSize.Y,
			ScrollBarThickness   = 3,
			ScrollBarImageColor3 = Theme.Accent,
			ScrollingDirection   = Enum.ScrollingDirection.Y,
			ElasticBehavior      = Enum.ElasticBehavior.Never,
			Visible              = false,
		}, panel)
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, frame)
		create("UIPadding", {
			PaddingLeft   = UDim.new(0, 12),
			PaddingRight  = UDim.new(0, 12),
			PaddingTop    = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 16),
		}, frame)
		local page = { frame = frame, order = 0 }
		pages[name] = page
		currentPage = page
		return page
	end

	local function nextOrder() currentPage.order += 1; return currentPage.order end

	local function makeSection(text)
		local label = create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = nextOrder(),
			Font = FONT_BOLD,
			TextSize = 11,
			TextColor3 = Theme.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "◆ " .. string.upper(text),
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
		create("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
		local rowGlow = create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 1,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, row)
		
		track(row.MouseEnter:Connect(function()
			tw(row, 0.2, { BackgroundColor3 = Theme.CardHover }, Enum.EasingStyle.Quad)
			tw(rowGlow, 0.25, { Transparency = 0.3 }, Enum.EasingStyle.Quad)
		end))
		track(row.MouseLeave:Connect(function()
			tw(row, 0.3, { BackgroundColor3 = Theme.Card }, Enum.EasingStyle.Quad)
			tw(rowGlow, 0.35, { Transparency = 1 }, Enum.EasingStyle.Quad)
		end))
		return row
	end

	local function makeRowLabel(row, text, reserve)
		return create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -(reserve or 100), 0, 40),
			Font = FONT,
			TextSize = 13,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
		}, row)
	end

	local function styleBox(box)
		create("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
	end

	local function makeToggle(text, getter, setter)
		local row = makeRow(40)
		makeRowLabel(row, text)
		local switch = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(44, 24),
			BackgroundColor3 = Theme.SwitchOff,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
		}, row)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, switch)
		
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
		}, switch)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)
		
		local first = true
		local function refresh()
			local on = getter() == true
			local col = on and Theme.Good or Theme.SwitchOff
			local pos = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
			if first then
				first = false
				switch.BackgroundColor3 = col
				knob.Position = pos
			else
				tw(switch, 0.3, { BackgroundColor3 = col }, Enum.EasingStyle.Back)
				tw(knob, 0.4, { Position = pos }, Enum.EasingStyle.Back)
			end
		end
		table.insert(refreshers, refresh)
		track(switch.Activated:Connect(function()
			setter(not(getter() == true))
			syncUI()
		end))
		refresh()
	end

	local function makeConfigToggle(text, key, onChange)
		makeToggle(text, function() return Config[key] end, function(v)
			Config[key] = v
			if onChange then onChange(v) end
		end)
	end

	local function makeAction(text, callback)
		local row = makeRow(44)
		local button = create("TextButton", {
			Size = UDim2.new(1, -24, 0, 32),
			Position = UDim2.fromOffset(12, 6),
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_BOLD,
			TextSize = 13,
			TextColor3 = Theme.OnAccent,
			Text = text,
		}, row)
		create("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
		create("UIGradient", {
			Rotation = 45,
			Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
		}, button)
		
		track(button.MouseEnter:Connect(function()
			tw(button, 0.2, { BackgroundColor3 = Theme.Accent2 }, Enum.EasingStyle.Quad)
		end))
		track(button.MouseLeave:Connect(function()
			tw(button, 0.25, { BackgroundColor3 = Theme.Accent }, Enum.EasingStyle.Quad)
		end))
		track(button.Activated:Connect(callback))
	end

	local function makeCycle(text, key, options)
		local row = makeRow(40)
		makeRowLabel(row, text, 130)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(112, 28),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Accent,
			Text = tostring(Config[key]),
		}, row)
		styleBox(button)
		create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 1,
			Transparency = 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		
		track(button.MouseEnter:Connect(function()
			tw(button, 0.2, { BackgroundColor3 = Color3.fromRGB(28, 32, 52) }, Enum.EasingStyle.Quad)
		end))
		track(button.MouseLeave:Connect(function()
			tw(button, 0.25, { BackgroundColor3 = Theme.Card }, Enum.EasingStyle.Quad)
		end))
		
		table.insert(refreshers, function() button.Text = tostring(Config[key]) end)
		track(button.Activated:Connect(function()
			local idx = table.find(options, Config[key]) or 0
			Config[key] = options[idx % #options + 1]
			syncUI()
		end))
	end

	local function makeBind(text, key, allowClear)
		local row = makeRow(40)
		makeRowLabel(row, text, 130)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(112, 28),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Accent,
			Text = "",
		}, row)
		styleBox(button)
		local bindStroke = create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 1,
			Transparency = 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		
		local function refresh()
			local listening = listeningBind and listeningBind.key == key
			button.Text = listening and "Press key…" or Utilities.bindingName(Config[key])
			tw(bindStroke, 0.25, { Transparency = listening and 0 or 0.7 }, Enum.EasingStyle.Quad)
		end
		table.insert(refreshers, refresh)
		track(button.Activated:Connect(function()
			listeningBind = (listeningBind and listeningBind.key == key) and nil
				or { key = key, allowClear = allowClear }
			syncUI()
		end))
		refresh()
	end

	local function makeSlider(text, key, minValue, maxValue, step, decimals, fineStep)
		local row = makeRow(62)
		makeRowLabel(row, text)
		local format = "%.." .. decimals .. "f"
		local frame = currentPage.frame

		local valueBox = create("TextBox", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 9),
			Size = UDim2.fromOffset(68, 24),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Accent,
			ClearTextOnFocus = false,
			Text = "",
		}, row)
		styleBox(valueBox)
		local boxStroke = create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 1.5,
			Transparency = 0.8,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, valueBox)
		track(valueBox.Focused:Connect(function() tw(boxStroke, 0.2, { Transparency = 0 }, Enum.EasingStyle.Quad) end))
		track(valueBox.FocusLost:Connect(function() tw(boxStroke, 0.25, { Transparency = 0.8 }, Enum.EasingStyle.Quad) end))

		local hit = create("Frame", {
			BackgroundTransparency = 1,
			Active = true,
			Position = UDim2.fromOffset(14, 38),
			Size = UDim2.new(1, -28, 0, 18),
		}, row)
		local bar = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, 4),
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
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
		}, fill)
		
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
		}, hit)
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)
		local knobGlow = create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 2,
			Transparency = 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, knob)
		
		track(hit.MouseEnter:Connect(function()
			tw(knobGlow, 0.2, { Transparency = 0 }, Enum.EasingStyle.Quad)
		end))
		track(hit.MouseLeave:Connect(function()
			tw(knobGlow, 0.25, { Transparency = 0.5 }, Enum.EasingStyle.Quad)
		end))

		local function applyValue(value, snap)
			local v = Utilities.clampNumber(value, minValue, maxValue, Config[key])
			v = math.floor(v / snap + 0.5) * snap
			Config[key] = math.clamp(v, minValue, maxValue)
			markStyleDirty()
			schedSave()
		end
		local function refresh()
			local v = Utilities.clampNumber(Config[key], minValue, maxValue, minValue)
			local fr = (v - minValue) / (maxValue - minValue)
			fill.Size = UDim2.fromScale(fr, 1)
			knob.Position = UDim2.new(fr, 0, 0.5, 0)
			if not valueBox:IsFocused() then valueBox.Text = string.format(format, v) end
		end
		table.insert(refreshers, refresh)
		
		local function fromX(x)
			local w = hit.AbsoluteSize.X
			if w <= 0 then return end
			applyValue(minValue + (maxValue - minValue) * math.clamp((x - hit.AbsolutePosition.X) / w, 0, 1), step)
			refresh()
		end
		
		track(hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				beginDrag(function(pos) fromX(pos.X) end, input, frame)
			end
		end))
		track(valueBox.FocusLost:Connect(function()
			local n = tonumber(valueBox.Text)
			if n then applyValue(n, fineStep or step) end
			refresh()
		end))
		refresh()
	end

	local function makeColorRow(text, key)
		local row = makeRow(88)
		makeRowLabel(row, text)
		local hexBox = create("TextBox", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 9),
			Size = UDim2.fromOffset(68, 24),
			BackgroundColor3 = Theme.Card,
			BorderSizePixel = 0,
			Font = FONT,
			TextSize = 12,
			TextColor3 = Theme.Accent,
			ClearTextOnFocus = false,
			Text = "",
		}, row)
		styleBox(hexBox)
		local hexStroke = create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 1.5,
			Transparency = 0.8,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, hexBox)
		track(hexBox.Focused:Connect(function() tw(hexStroke, 0.2, { Transparency = 0 }, Enum.EasingStyle.Quad) end))
		track(hexBox.FocusLost:Connect(function() tw(hexStroke, 0.25, { Transparency = 0.8 }, Enum.EasingStyle.Quad) end))
		
		local holder = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 48),
			Size = UDim2.new(1, -28, 0, 28),
		}, row)
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}, holder)
		
		local swatchStrokes = {}
		for index, color in ipairs(SWATCHES) do
			local swatch = create("TextButton", {
				LayoutOrder = index,
				Size = UDim2.fromOffset(26, 26),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
			}, holder)
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, swatch)
			swatchStrokes[index] = create("UIStroke", {
				Color = Theme.Accent,
				Thickness = 2,
				Transparency = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, swatch)
			track(swatch.Activated:Connect(function() Config[key] = color; syncUI() end))
		end
		
		local function refresh()
			local hex = Config[key]:ToHex()
			for i, col in ipairs(SWATCHES) do
				tw(swatchStrokes[i], 0.2, { Transparency = col:ToHex() == hex and 0 or 1 }, Enum.EasingStyle.Quad)
			end
			if not hexBox:IsFocused() then hexBox.Text = "#" .. string.upper(hex) end
		end
		table.insert(refreshers, refresh)
		track(hexBox.FocusLost:Connect(function()
			local cleaned = string.gsub(hexBox.Text, "[#%s]", "")
			if #cleaned == 6 and not string.find(cleaned, "%X") then
				local ok, color = pcall(Color3.fromHex, cleaned)
				if ok and typeof(color) == "Color3" then Config[key] = color end
			end
			syncUI()
		end))
		refresh()
	end

	-- -----------------------------------------------------------------------
	-- PAGE CONTENTS
	-- -----------------------------------------------------------------------
	newPage("Aim")
	makeSection("Assist")
	makeToggle("Aim assist enabled", function() return Config.Enabled end, function(v) targetAssist:setEnabled(v, syncUI) end)
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
	makeConfigToggle("Prediction", "Prediction", function() targetAssist:resetPrediction() end)
	makeSlider("Prediction lead (s)", "PredictionFactor", 0, 0.5, 0.01, 2)

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

	newPage("Player")
	makeSection("Filters (Aim and ESP)")
	makeConfigToggle("Skip teammates", "TeamCheck")
	makeConfigToggle("Include neutral players", "TargetNeutralPlayers")
	makeConfigToggle("Skip dead players", "AliveCheck")
	makeConfigToggle("Skip ForceField players", "IgnoreForceField")
	makeSection("Info")
	ui.statsLabel = makeNote("", 36)

	newPage("Keys")
	makeSection("Configuration")
	makeConfigToggle("Auto-save configuration", "AutoSaveEnabled")
	makeAction("Reset configuration", function() resetConfig(); syncUI() end)
	makeAction("Unload script", shutdown)
	makeSection("Key bindings")
	makeBind("Aim activation", "ActivationInput", false)
	makeBind("Toggle aim assist", "SystemToggleKey", true)
	makeBind("Toggle ESP", "ESPToggleKey", true)
	makeBind("Toggle full bright", "FullBrightToggleKey", true)
	makeBind("Minimize panel", "GuiToggleKey", true)
	makeNote("Click a button, then press a key or mouse button. Esc cancels, Backspace clears (not for aim activation).", 44)

	syncUI()
	selectTab("Aim", true)

	-- Minimize / restore with premium animation
	setMinimizedFn = function(value, instant)
		if closed or not ui then return end
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
				tw(ui.pill, 0.35, { GroupTransparency = 0 }, Enum.EasingStyle.Back)
				tw(panelStroke, 0.2, { Transparency = 1 }, Enum.EasingStyle.Quad)
				local t = tw(ui.panel, 0.25, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
				if t then t.Completed:Once(function()
					if not closed and ui and token == animToken then
						ui.panel.Visible = false
					end
				end) end
			end
		else
			ui.panel.Visible = true
			if instant then
				ui.panel.GroupTransparency = 0
				ui.pill.GroupTransparency = 1
				ui.pill.Visible = false
			else
				tw(ui.panel, 0.4, { GroupTransparency = 0 }, Enum.EasingStyle.Back)
				tw(panelStroke, 0.3, { Transparency = 0.6 }, Enum.EasingStyle.Quad)
				local t = tw(ui.pill, 0.2, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
				if t then t.Completed:Once(function()
					if not closed and ui and token == animToken then
						ui.pill.Visible = false
					end
				end) end
			end
		end
	end

	track(minButton.Activated:Connect(function() setMinimizedFn(true, false) end))
	track(pillButton.Activated:Connect(function() setMinimizedFn(false, false) end))
	track(closeButton.Activated:Connect(shutdown))

	-- Panel drag
	track(dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local startPtr = Vector2.new(input.Position.X, input.Position.Y)
			local startPos = panelPos
			beginDrag(function(pos)
				panelPos = startPos + (Vector2.new(pos.X, pos.Y) - startPtr)
				clampPanelPosition()
				applyPanelPosition()
			end, input, nil)
		end
	end))

	track(panelGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout))

	overlayGui.Parent = playerGui
	panelGui.Parent = playerGui
	updateLayout()
	setMinimizedFn(Config.UIStartMinimized, Config.UIStartMinimized == true)
end

--------------------------------------------------------------------------------
-- 13. MAIN LOOP
--------------------------------------------------------------------------------
local function refreshCamera()
	local current = Workspace.CurrentCamera
	if current ~= camera then
		camera = current
		originalCameraFOV = camera and camera.FieldOfView or nil
		targetAssist.camera = camera
		targetAssist.aimDefaultFOV = camera and camera.FieldOfView or nil
		targetAssist.aimFOVScale = 1
		if monsterESP then monsterESP.camera = camera end
		targetAssist:releaseTarget("camera changed")
		Utilities.debugLog(Config, "Camera reference refreshed")
	end
end

local function updateViewCenter()
	if not camera then return end
	if Config.FOVCenter == "Mouse" then
		targetAssist.viewCenter = UserInputService:GetMouseLocation()
	else
		targetAssist.viewCenter = camera.ViewportSize * 0.5
	end
end

local function frameUpdate(deltaTime)
	local dt = math.clamp(deltaTime, 1/1000, 0.1)

	refreshCamera()
	updateViewCenter()

	if activeDrag and activeDrag.mouse
		and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		endDrag()
	end

	local hasTarget = targetAssist:step(dt)

	updateVisuals(dt, hasTarget)
	espShown = monsterESP and monsterESP:update(playerList, styleVersion, targetAssist) or 0
	if itemESP then itemESP:update() end
	updateLighting(dt)
	updateUtilities()
	updateStatus(hasTarget)
	updateStats(dt)
end

local function onRenderStep(deltaTime)
	if closed then return end
	local ok, err = pcall(frameUpdate, deltaTime)
	if not ok then
		frameErrors += 1
		warn("[HushScript] Frame error:", err)
		if frameErrors >= consts.MAX_FRAME_ERRORS then
			warn("[HushScript] Too many errors; shutting down.")
			shutdown()
		end
	end
end

--------------------------------------------------------------------------------
-- 14. PUBLIC API
--------------------------------------------------------------------------------
api.Destroy = shutdown
api.GetConfig = function() return Config end
api.SetConfig = function(overrides)
	if closed or type(overrides) ~= "table" then return end
	for k, v in pairs(overrides) do
		if Config[k] ~= nil then Config[k] = v end
	end
	sanitizeCfg()
	if not Config.Enabled then targetAssist:setActive(false, "disabled") end
	syncUI()
end
api.SetEnabled = function(v) targetAssist:setEnabled(v, syncUI) end
api.Toggle = function() targetAssist:setEnabled(not Config.Enabled, syncUI) end
api.SetMinimized = function(v) if setMinimizedFn then setMinimizedFn(v, false) end end
api.IsActive = function() return targetAssist.active end
api.GetTarget = function() return targetAssist.currentTarget end

--------------------------------------------------------------------------------
-- 15. INIT
--------------------------------------------------------------------------------
local previous = shared[consts.SHARED_KEY]
if type(previous) == "table" and type(previous.Destroy) == "function" then
	pcall(previous.Destroy)
end
shared[consts.SHARED_KEY] = api

Utilities.loadConfig(Config, consts.CONFIG_FILE)
sanitizeCfg()

do
	local old = Workspace:FindFirstChild(consts.ESP_FOLDER_NAME)
	if old then old:Destroy() end
	espFolder = create("Folder", { Name = consts.ESP_FOLDER_NAME }, Workspace)

	local oldLoot = Workspace:FindFirstChild(consts.LOOT_ESP_FOLDER_NAME)
	if oldLoot then oldLoot:Destroy() end
	lootEspFolder = create("Folder", { Name = consts.LOOT_ESP_FOLDER_NAME }, Workspace)
end

targetAssist = TargetAssist.new(Config, consts, Utilities)
targetAssist.playerList = playerList
monsterESP = MonsterESP.new(Config, consts, Utilities, nil, espFolder)
itemESP = ItemESP.new(Config, consts, Utilities, lootEspFolder)

itemESP:registerFolder(Workspace:FindFirstChild("LootBags"), connections)
itemESP:registerFolder(Workspace:FindFirstChild("WorldFinds"), connections)
track(Workspace.ChildAdded:Connect(function(child)
	if child.Name == "LootBags" or child.Name == "WorldFinds" then
		itemESP:registerFolder(child, connections)
	end
end))
for _, descendant in ipairs(Workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		itemESP:registerContainerPrompt(descendant, connections)
	end
end
track(Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("ProximityPrompt") then
		itemESP:registerContainerPrompt(desc, connections)
	end
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
	if closed then return end

	if listeningBind then
		if processed then return end
		local binding, cancel, clear = nil, false, false
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				cancel = true
			elseif input.KeyCode == Enum.KeyCode.Backspace then
				if listeningBind.allowClear then clear = true else cancel = true end
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				binding = input.KeyCode
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3 then
			binding = input.UserInputType
		end
		if binding or cancel or clear then
			if binding then Config[listeningBind.key] = binding
			elseif clear then Config[listeningBind.key] = false end
			listeningBind = nil
			syncUI()
		end
		return
	end

	if processed then return end

	if Config.GuiToggleKey and setMinimizedFn and Utilities.inputMatches(input, Config.GuiToggleKey) then
		setMinimizedFn(not minimized, false); return
	end
	if Config.SystemToggleKey and Utilities.inputMatches(input, Config.SystemToggleKey) then
		targetAssist:setEnabled(not Config.Enabled, syncUI)
		Utilities.debugLog(Config, "Aim assist enabled:", Config.Enabled); return
	end
	if Config.ESPToggleKey and Utilities.inputMatches(input, Config.ESPToggleKey) then
		Config.ESPEnabled = not Config.ESPEnabled; syncUI(); return
	end
	if Config.FullBrightToggleKey and Utilities.inputMatches(input, Config.FullBrightToggleKey) then
		Config.FullBright = not Config.FullBright; syncUI(); return
	end
	if not Config.Enabled then return end
	if Utilities.inputMatches(input, Config.ActivationInput) then
		if Config.ActivationMode == "Toggle" then
			targetAssist:setActive(not targetAssist.active, "toggle")
		else
			targetAssist:setActive(true, "hold")
		end
	end
end))

track(UserInputService.InputChanged:Connect(function(input)
	if closed or not activeDrag then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		activeDrag.update(input.Position)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if closed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then endDrag() end
	if Config.ActivationMode == "Hold" and Utilities.inputMatches(input, Config.ActivationInput) then
		targetAssist:setActive(false, "released")
	end
end))

track(UserInputService.WindowFocusReleased:Connect(function()
	endDrag()
	targetAssist:setActive(false, "focus lost")
end))

track(UserInputService.TextBoxFocused:Connect(function()
	if Config.ActivationMode == "Hold" then targetAssist:setActive(false, "textbox focus") end
end))

track(Players.PlayerAdded:Connect(function(player)
	if not table.find(playerList, player) then table.insert(playerList, player) end
	targetAssist.playerList = playerList
end))
track(Players.PlayerRemoving:Connect(function(player)
	local idx = table.find(playerList, player)
	if idx then table.remove(playerList, idx) end
	targetAssist.playerList = playerList
	if player == targetAssist.currentTarget then targetAssist:releaseTarget("player left") end
	if monsterESP then monsterESP:removePlayer(player) end
end))

track(LocalPlayer.CharacterAdded:Connect(function()
	targetAssist:releaseTarget("respawned")
end))
track(LocalPlayer.CharacterRemoving:Connect(function()
	targetAssist:releaseTarget("character removing")
end))

track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshCamera))

if script then track(script.Destroying:Connect(shutdown)) end

buildGui()
if monsterESP and ui then
	monsterESP.espRoot = ui.espRoot
	monsterESP.camera = camera
end

if not closed then
	RunService:BindToRenderStep(consts.RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRenderStep)
	Utilities.debugLog(Config, "HushScript initialized")
end