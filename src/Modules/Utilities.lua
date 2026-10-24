--[[
	Utilities.luau
	HushScript – Shared helper functions used across all modules.
	Returns a table of pure utility functions; does NOT hold mutable state.
]]

local TweenService = game:GetService("TweenService")
local HttpService  = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local Utilities = {}

--------------------------------------------------------------------------------
-- LOGGING
--------------------------------------------------------------------------------
function Utilities.debugLog(cfg, ...)
	if cfg.Debug then
		print("[SmoothTargetAssist]", ...)
	end
end

--------------------------------------------------------------------------------
-- MATH / TYPE HELPERS
--------------------------------------------------------------------------------
-- Exponential-decay lerp — frame-rate independent smoothing.
function Utilities.approach(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

function Utilities.toBool(value, default)
	if type(value) == "boolean" then return value end
	return default
end

function Utilities.clampNumber(value, minValue, maxValue, default)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	return math.clamp(value, minValue, maxValue)
end

function Utilities.pickString(value, valid, default)
	for _, option in ipairs(valid) do
		if value == option then return value end
	end
	return default
end

--------------------------------------------------------------------------------
-- INPUT HELPERS
--------------------------------------------------------------------------------
function Utilities.isValidBinding(value)
	return typeof(value) == "EnumItem"
		and (value.EnumType == Enum.KeyCode or value.EnumType == Enum.UserInputType)
end

function Utilities.bindingName(binding)
	if typeof(binding) ~= "EnumItem" then return "None" end
	if binding == Enum.UserInputType.MouseButton1 then return "LMB" end
	if binding == Enum.UserInputType.MouseButton2 then return "RMB" end
	if binding == Enum.UserInputType.MouseButton3 then return "MMB" end
	return binding.Name
end

function Utilities.inputMatches(input, binding)
	if typeof(binding) ~= "EnumItem" then return false end
	if binding.EnumType == Enum.KeyCode then
		return input.KeyCode == binding
	end
	return input.UserInputType == binding
end

-- Returns true/false when pollable, or nil when not.
function Utilities.isBindingDown(binding)
	if typeof(binding) ~= "EnumItem" then return nil end
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

--------------------------------------------------------------------------------
-- INSTANCE HELPERS
--------------------------------------------------------------------------------
function Utilities.create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then instance.Parent = parent end
	return instance
end

function Utilities.tween(closed, activeTweens, instance, duration, props)
	if closed or not instance then return nil end
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

function Utilities.track(connections, connection)
	table.insert(connections, connection)
	return connection
end

--------------------------------------------------------------------------------
-- CONFIG PERSISTENCE
--------------------------------------------------------------------------------
function Utilities.persistenceAvailable()
	return type(writefile) == "function" and type(readfile) == "function"
end

function Utilities.encodeConfig(cfg)
	local result = {}
	for key, value in pairs(cfg) do
		local kind = typeof(value)
		if kind == "boolean" or kind == "number" or type(value) == "string" then
			result[key] = value
		elseif kind == "Color3" then
			result[key] = { __color = value:ToHex() }
		end
	end
	return result
end

function Utilities.saveConfigNow(cfg, configFile)
	if not cfg.AutoSaveEnabled or not Utilities.persistenceAvailable() then return end
	pcall(function()
		writefile(configFile, HttpService:JSONEncode(Utilities.encodeConfig(cfg)))
	end)
end

-- Debounced save: coalesces rapid changes into one write 0.5 s later.
local saveToken = 0
function Utilities.scheduleConfigSave(cfg, configFile, closedRef)
	if not cfg.AutoSaveEnabled or not Utilities.persistenceAvailable() then return end
	saveToken += 1
	local token = saveToken
	task.delay(0.5, function()
		if not closedRef() and token == saveToken then
			Utilities.saveConfigNow(cfg, configFile)
		end
	end)
end

function Utilities.loadConfig(cfg, configFile)
	if not Utilities.persistenceAvailable() then return end
	pcall(function()
		local decoded = HttpService:JSONDecode(readfile(configFile))
		if type(decoded) ~= "table" then return end
		for key, value in pairs(decoded) do
			if cfg[key] ~= nil then
				if type(value) == "table" and value.__color then
					local ok, color = pcall(Color3.fromHex, value.__color)
					if ok then cfg[key] = color end
				elseif type(value) == typeof(cfg[key]) then
					cfg[key] = value
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- CONFIG SANITIZATION
--------------------------------------------------------------------------------
function Utilities.sanitizeConfig(cfg, rules)
	-- Booleans
	for key, default in pairs(rules.BOOL_DEFAULTS) do
		cfg[key] = Utilities.toBool(cfg[key], default)
	end
	-- Numbers
	for _, rule in ipairs(rules.NUMBER_RULES) do
		cfg[rule[1]] = Utilities.clampNumber(cfg[rule[1]], rule[2], rule[3], rule[4])
	end
	-- Colors
	for key, default in pairs(rules.COLOR_DEFAULTS) do
		if typeof(cfg[key]) ~= "Color3" then cfg[key] = default end
	end
	-- Key bindings
	for _, key in ipairs(rules.KEY_FIELDS) do
		if cfg[key] ~= false and not Utilities.isValidBinding(cfg[key]) then
			cfg[key] = false
		end
	end

	cfg.ESPTextSize = math.floor(cfg.ESPTextSize + 0.5)
	if not Utilities.isValidBinding(cfg.ActivationInput) then
		cfg.ActivationInput = Enum.UserInputType.MouseButton2
	end
	cfg.ActivationMode     = Utilities.pickString(cfg.ActivationMode,     { "Hold", "Toggle" },                 "Hold")
	cfg.SelectionPriority  = Utilities.pickString(cfg.SelectionPriority,  { "Crosshair", "Distance", "Health" }, "Crosshair")
	cfg.FOVCenter          = Utilities.pickString(cfg.FOVCenter,          { "Viewport", "Mouse" },               "Viewport")

	if type(cfg.TargetPart) ~= "string" or cfg.TargetPart == "" then cfg.TargetPart = "Head" end
	local fallbacks = {}
	if type(cfg.TargetPartFallbacks) == "table" then
		for _, name in ipairs(cfg.TargetPartFallbacks) do
			if type(name) == "string" and name ~= "" then table.insert(fallbacks, name) end
		end
	end
	if #fallbacks == 0 then fallbacks = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" } end
	cfg.TargetPartFallbacks = fallbacks

	if type(cfg.TeamAttribute)   ~= "string"   then cfg.TeamAttribute   = ""    end
	if type(cfg.CustomTeamCheck) ~= "function"  then cfg.CustomTeamCheck = false end
end

return Utilities
