--[[
	Hush-script.lua  (FINAL VERSION)
	Premium Modern UI - VIBRANT COLORS & SMOOTH ANIMATIONS
	Place in: StarterPlayer > StarterPlayerScripts
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

local ConfigDef    = loadModule("Config.luau")
local Utilities    = loadModule("Modules/Utilities.luau")
local TargetAssist = loadModule("Modules/TargetAssist.luau")
local ItemESP      = loadModule("Modules/ItemESP.luau")
local MonsterESP   = loadModule("Modules/MonsterESP.luau")

--------------------------------------------------------------------------------
-- 3. CONFIG & PREMIUM THEME
--------------------------------------------------------------------------------
local Config = {}
for k, v in pairs(ConfigDef.Default) do Config[k] = v end
local DEFAULT_CONFIG = table.clone(Config)

-- ⚡ PREMIUM VIBRANT THEME - APPLIES FORCEFULLY
local PREMIUM_THEME = {
	-- Dark Rich Backgrounds
	Panel           = Color3.fromRGB(8, 10, 16),
	Title           = Color3.fromRGB(5, 7, 14),
	Card            = Color3.fromRGB(15, 18, 32),
	CardHover       = Color3.fromRGB(22, 28, 48),
	
	-- Vibrant Accent Colors (Cyan -> Purple -> Pink)
	Accent          = Color3.fromRGB(0, 220, 255),    -- Cyan Electric
	Accent2         = Color3.fromRGB(147, 51, 234),   -- Purple Royal
	Accent3         = Color3.fromRGB(236, 72, 153),   -- Pink Vibrant
	OnAccent        = Color3.fromRGB(8, 8, 12),
	
	-- Status Colors - VIBRANT
	Good            = Color3.fromRGB(16, 255, 150),   -- Mint Green BRIGHT
	Warn            = Color3.fromRGB(255, 200, 0),    -- Gold BRIGHT
	Off             = Color3.fromRGB(65, 75, 110),    -- Dim Blue
	Danger          = Color3.fromRGB(255, 80, 120),   -- Hot Pink
	
	-- Text
	Text            = Color3.fromRGB(245, 248, 255),
	SubText         = Color3.fromRGB(130, 150, 190),
	Stroke          = Color3.fromRGB(40, 50, 80),
	SwitchOff       = Color3.fromRGB(30, 38, 60),
	White           = Color3.fromRGB(255, 255, 255),
}

local consts = {
	MAX_RAY_STEPS             = ConfigDef.MAX_RAY_STEPS,
	MAX_VALID_SPEED           = ConfigDef.MAX_VALID_SPEED,
	MAX_FRAME_ERRORS          = ConfigDef.MAX_FRAME_ERRORS,
	MAX_LINE_LENGTH           = ConfigDef.MAX_LINE_LENGTH,
	ESP_VIEW_MARGIN           = ConfigDef.ESP_VIEW_MARGIN,
	LOOT_FAR_THROTTLE_DISTANCE = ConfigDef.LOOT_FAR_THROTTLE_DISTANCE,
	LOOT_FAR_THROTTLE_INTERVAL = ConfigDef.LOOT_FAR_THROTTLE_INTERVAL,
	Theme    = PREMIUM_THEME,  -- ✓ Force use premium theme
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

local ui             = nil
local minimized      = false
local animToken      = 0
local panelPos       = Vector2.new(20, 80)
local panelSize      = Vector2.new(360, 500)
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
-- 5. UTILITIES
--------------------------------------------------------------------------------
local function track(conn) return Utilities.track(connections, conn) end
local function create(cls, props, parent) return Utilities.create(cls, props, parent) end

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
-- 6. DRAG
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
-- 7. LIGHTING
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
-- 8. MODULES
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
-- 10. FOV VISUAL
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
-- 11. STATUS & STATS
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
		tw(ui.statusDot, 0.35, { BackgroundColor3 = color }, Enum.EasingStyle.Quad)
		tw(ui.pillDot,   0.35, { BackgroundColor3 = color }, Enum.EasingStyle.Quad)
		if ui.statusGlow then tw(ui.statusGlow, 0.35, { Color = color }, Enum.EasingStyle.Quad) end
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
-- 12. GUI BUILD
--------------------------------------------------------------------------------

        BackgroundTransparency = 1,
        ZIndex = 5,
    }, Button)
    setText(Icon, tab.icon, 11, Theme.Muted, FONT_BOLD)
    Icon.TextXAlignment = Enum.TextXAlignment.Center
    local Label = make("TextLabel", {
        Position = UDim2.fromOffset(43, 0),
        Size = UDim2.new(1, -49, 1, 0),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, Button)
    setText(Label, tab.label, 11, Theme.Muted, FONT_MEDIUM)
    Button.MouseEnter:Connect(function()
        if activeTab ~= tab.id then tween(Button, { BackgroundColor3 = Theme.Surface }, TWEEN_FAST) end
    end)
    Button.MouseLeave:Connect(function()
        if activeTab ~= tab.id then tween(Button, { BackgroundColor3 = Theme.Panel }, TWEEN_FAST) end
    end)
    Button.Activated:Connect(function() setActiveTab(tab.id) end)
    navWidgets[tab.id] = { Button = Button, Indicator = Indicator, Icon = Icon, Label = Label }

    local Page, Scroll = makePage(tab)
    pageWidgets[tab.id] = Page
    if specs[tab.id] then
        for order, spec in ipairs(specs[tab.id]) do
            local row = createRow(Scroll, spec)
            row.LayoutOrder = order
        end
    elseif tab.id == "Keys" then
        local keysInfo = make("TextLabel", {
            Size = UDim2.new(1, 0, 0, 46),
            BackgroundTransparency = 1,
            TextWrapped = true,
            LayoutOrder = 1,
            ZIndex = 4,
        }, Scroll)
        setText(keysInfo, "Click a key field, then press the key you want to use.", 10, Theme.Muted, FONT)
        keysInfo.TextWrapped = true
        keysInfo.TextYAlignment = Enum.TextYAlignment.Top
        local uiKeyRow = createKeybindRow(Scroll, "Toggle interface", "Show or hide this window", "ToggleUI", Enum.KeyCode.RightShift)
        uiKeyRow.Button.Parent.LayoutOrder = 2
        local aimKeyRow = createKeybindRow(Scroll, "Action key", "Available to your connected feature logic", "ActionKey", Enum.KeyCode.Q)
        aimKeyRow.Button.Parent.LayoutOrder = 3
        HushUI.Keybinds = {
            ToggleUI = Enum.KeyCode.RightShift,
            ActionKey = Enum.KeyCode.Q,
        }
        HushUI.KeybindRows = { uiKeyRow, aimKeyRow }
    end
end

-- Responsive layout: compact sidebar on narrow screens, and size/position clamping.
local function applyLayout()
    viewport = viewportSize()
    local maxW = math.max(1, math.min(MAX_SIZE.X, viewport.X - 20))
    local maxH = math.max(1, math.min(MAX_SIZE.Y, viewport.Y - 20))
    local minW = math.min(MIN_SIZE.X, maxW)
    local minH = math.min(MIN_SIZE.Y, maxH)
    windowSize = Vector2.new(
        math.clamp(windowSize.X, minW, maxW),
        math.clamp(windowSize.Y, minH, maxH)
    )
    local shownSize = isMinimized and Vector2.new(math.min(270, maxW), math.min(64, maxH)) or windowSize
    windowPos = Vector2.new(
        math.clamp(windowPos.X, 8, math.max(8, viewport.X - shownSize.X - 8)),
        math.clamp(windowPos.Y, 8, math.max(8, viewport.Y - shownSize.Y - 8))
    )
    Window.Position = UDim2.fromOffset(windowPos.X, windowPos.Y)
    Window.Size = UDim2.fromOffset(shownSize.X, shownSize.Y)

    compactNav = windowSize.X < 570
    local navWidth = compactNav and 60 or 158
    Sidebar.Size = UDim2.new(0, navWidth, 1, -89)
    Content.Position = UDim2.new(0, navWidth + 10, 0, 65)
    Content.Size = UDim2.new(1, -(navWidth + 20), 1, -89)
    SidebarCaption.Visible = not compactNav
    SidebarCaption.Size = UDim2.new(1, 0, 0, compactNav and 5 or 20)
    for _, info in pairs(navWidgets) do
        info.Label.Visible = not compactNav
        info.Icon.Position = compactNav and UDim2.new(0.5, -13, 0, 0) or UDim2.fromOffset(12, 0)
        info.Icon.Size = UDim2.fromOffset(26, 39)
        info.Button.Size = UDim2.new(1, 0, 0, 39)
    end
    for _, page in pairs(pageWidgets) do
        page.Size = UDim2.fromScale(1, 1)
    end
    StatusText.Visible = windowSize.X > 470 and not isMinimized
    StatusDot.Visible = windowSize.X > 470 and not isMinimized

    local headerVisible = not isMinimized
    Sidebar.Visible = headerVisible
    Content.Visible = headerVisible
    BottomLine.Visible = headerVisible
    Footer.Visible = headerVisible
    ResizeHandle.Visible = headerVisible
    Logo.Visible = true
    Brand.Visible = true
    Credit.Visible = not isMinimized
    CloseButton.Visible = true
    MinButton.Visible = true
    if isMinimized then
        Brand.Size = UDim2.new(1, -100, 0, 24)
        Brand.Position = UDim2.fromOffset(60, 7)
        Credit.Visible = false
        Logo.Position = UDim2.fromOffset(14, 16)
        CloseButton.Position = UDim2.new(1, -9, 0.5, 0)
        MinButton.Position = UDim2.new(1, -42, 0.5, 0)
        MinButton.Text = "+"
    else
        Brand.Size = UDim2.fromOffset(180, 24)
        Brand.Position = UDim2.fromOffset(60, 12)
        Logo.Position = UDim2.fromOffset(18, 16)
        CloseButton.Position = UDim2.new(1, -13, 0.5, 0)
        MinButton.Position = UDim2.new(1, -46, 0.5, 0)
        MinButton.Text = "−"
    end
end

MinButton.Activated:Connect(function()
    isMinimized = not isMinimized
    applyLayout()
end)
CloseButton.Activated:Connect(function()
    ScreenGui:Destroy()
end)

-- Drag from the open area of the header; leave the right-side buttons clickable.
Header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if input.Position.X >= Header.AbsolutePosition.X + Header.AbsoluteSize.X - 94 then return end
    isDragging = true
    dragStartPointer = Vector2.new(input.Position.X, input.Position.Y)
    dragStartPos = windowPos
end)

ResizeHandle.InputBegan:Connect(function(input)
    if isMinimized then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    isResizing = true
    resizeStartPointer = Vector2.new(input.Position.X, input.Position.Y)
    resizeStartSize = windowSize
end)

UserInputService.InputChanged:Connect(function(input)
    if isDragging and dragStartPointer and dragStartPos and
       (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPointer
        windowPos = dragStartPos + delta
        applyLayout()
    elseif isResizing and resizeStartPointer and resizeStartSize and
       (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - resizeStartPointer
        windowSize = resizeStartSize + delta
        applyLayout()
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = false
        isResizing = false
    end
end)

-- Recalculate when the device rotates or the viewport changes size.
local viewportConnection
local function connectViewport()
    if viewportConnection then viewportConnection:Disconnect() end
    Camera = workspace.CurrentCamera or Camera
    if Camera then
        viewportConnection = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
    end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    connectViewport()
    applyLayout()
end)
connectViewport()

-- Keybind capture and global UI visibility shortcut.
local currentWaitingKeybind
for _, tab in ipairs(tabDefinitions) do
    if tab.id == "Keys" then
        local rows = HushUI.KeybindRows or {}
        for _, row in ipairs(rows) do
            row.Button.Activated:Connect(function()
                currentWaitingKeybind = row
            end)
        end
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)


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