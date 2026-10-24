--[[
	ItemESP.luau
	HushScript – World Item / Loot ESP system.
	Tracks LootBags, WorldFinds (Dropped_* models), and container ProximityPrompts.
	Uses BillboardGui labels + Highlight instances for all items.
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local ItemESP = {}
ItemESP.__index = ItemESP

--------------------------------------------------------------------------------
-- FILTER TABLES
--------------------------------------------------------------------------------
local IGNORED_LOOT_ITEMS = {
	dropped_junk         = true,
	dropped_wooden_board = true,
}

local IGNORED_LOOT_FOLDERS = {
	NoiseTraps = true,
	HushGrass  = true,
}

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------
function ItemESP.new(cfg, consts, utils, espFolder)
	local self = setmetatable({}, ItemESP)

	self.cfg     = cfg
	self.consts  = consts
	self.utils   = utils
	self.folder  = espFolder   -- Workspace folder that holds Highlight instances

	self.objects     = {}   -- [Instance] = { highlight, billboard, label, part, … }
	self.lootFolders = {}   -- [Folder] = true  (to avoid double-registering)

	return self
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
function ItemESP:_isIgnored(item)
	local ancestor = item
	while ancestor and ancestor ~= Workspace do
		if IGNORED_LOOT_FOLDERS[ancestor.Name] then return true end
		ancestor = ancestor.Parent
	end
	return false
end

function ItemESP:_getTargetPart(item)
	if item:IsA("BasePart") then return item end
	local anchor = item:FindFirstChild("FindAnchor")
	if anchor and anchor:IsA("BasePart") then return anchor end
	return item:FindFirstChildWhichIsA("BasePart", true)
end

-- Returns displayName, color, category — or nil to skip.
function ItemESP:_analyzeItem(item, isContainer)
	local cfg      = self.cfg
	local rawName  = item.Name
	local lower    = string.lower(rawName)

	if isContainer then
		if string.find(lower, "codefragment", 1, true) or string.find(lower, "redpaper", 1, true)
			or string.find(lower, "bunker_code", 1, true) or string.find(lower, "key", 1, true) then
			return "Important: " .. rawName, cfg.LootESPImportantColor, "Important"
		end
		return rawName, cfg.LootESPContainerColor, "Container"
	end

	if IGNORED_LOOT_ITEMS[lower] then return nil end
	if rawName == "LootBag" or string.find(lower, "lootbag", 1, true) then
		return "Loot Bag", cfg.LootESPLootBagColor, "General"
	end

	local clean = string.gsub(rawName, "^Dropped_", "")

	if string.find(lower, "bunker_code", 1, true) or string.find(lower, "key", 1, true) then
		clean = string.upper(string.gsub(clean, "_", " "))
		return "Important: " .. clean, cfg.LootESPImportantColor, "Important"
	end
	if string.find(lower, "ammo", 1, true) or string.find(lower, "bullet", 1, true)
		or string.find(lower, "magazine", 1, true) or string.find(lower, "mag_", 1, true) then
		return string.gsub(clean, "_", " "), cfg.LootESPAmmoColor, "Ammo"
	end
	if string.find(lower, "gun", 1, true)     or string.find(lower, "rifle",   1, true)
		or string.find(lower, "pistol", 1, true) or string.find(lower, "shotgun", 1, true)
		or string.find(lower, "melee",  1, true) or string.find(lower, "knife",   1, true)
		or string.find(lower, "bat",    1, true) or string.find(lower, "axe",     1, true) then
		return string.gsub(clean, "_", " "), cfg.LootESPWeaponColor, "Weapon"
	end

	-- Title-case general items
	clean = string.gsub(clean, "_", " ")
	clean = string.gsub(clean, "(%a)([%w ]*)", function(first, rest)
		return string.upper(first) .. string.lower(rest)
	end)
	return clean, cfg.LootESPGeneralColor, "General"
end

function ItemESP:_isCategoryEnabled(category)
	local cfg = self.cfg
	if category == "Weapon"    then return cfg.LootESPShowWeapons    end
	if category == "Ammo"      then return cfg.LootESPShowAmmo       end
	if category == "Important" then return cfg.LootESPShowImportant  end
	if category == "Container" then return cfg.LootESPShowContainers end
	return cfg.LootESPShowGeneral
end

local function isContainerName(name)
	name = string.lower(name)
	return string.find(name, "container", 1, true) or string.find(name, "drawer", 1, true)
		or string.find(name, "box",       1, true) or string.find(name, "crate",  1, true)
		or string.find(name, "chest",     1, true) or string.find(name, "locker", 1, true)
		or string.find(name, "safe",      1, true)
end

local function isImportantName(name)
	name = string.lower(name)
	return string.find(name, "codefragment", 1, true) or string.find(name, "redpaper",   1, true)
		or string.find(name, "bunker_code",  1, true) or string.find(name, "key",         1, true)
end

--------------------------------------------------------------------------------
-- OBJECT LIFECYCLE
--------------------------------------------------------------------------------
function ItemESP:createObject(item, isContainer)
	if not item or self.objects[item] then return end
	if self:_isIgnored(item) then return end

	local displayName, color, category = self:_analyzeItem(item, isContainer)
	if not displayName then return end

	local part = self:_getTargetPart(item)
	if not part then return end

	local create = self.utils.create
	local Theme  = self.consts.Theme
	local FONT_BOLD = self.consts.FONT_BOLD

	local highlight = create("Highlight", {
		Name               = "LootHighlight",
		Adornee            = item,
		FillColor          = color,
		FillTransparency   = 0.6,
		OutlineColor       = Theme.White,
		OutlineTransparency = 0.3,
		DepthMode          = Enum.HighlightDepthMode.AlwaysOnTop,
	}, self.folder)

	local billboard = create("BillboardGui", {
		Name         = "LootMarker",
		Adornee      = part,
		Size         = UDim2.fromOffset(160, 34),
		StudsOffset  = Vector3.new(0, 1.2, 0),
		AlwaysOnTop  = true,
		Enabled      = false,
	}, self.folder)

	local label = create("TextLabel", {
		Size                    = UDim2.fromScale(1, 1),
		BackgroundTransparency  = 1,
		Font                    = FONT_BOLD,
		TextSize                = 13,
		TextColor3              = color,
		TextStrokeColor3        = Theme.Black,
		TextStrokeTransparency  = 0.2,
		Text                    = displayName,
	}, billboard)

	self.objects[item] = {
		highlight   = highlight,
		billboard   = billboard,
		label       = label,
		part        = part,
		displayName = displayName,
		category    = category,
		nextFarUpdate = 0,
	}
end

function ItemESP:removeObject(item)
	local obj = self.objects[item]
	if not obj then return end
	self.objects[item] = nil
	if obj.highlight then pcall(function() obj.highlight:Destroy() end) end
	if obj.billboard then pcall(function() obj.billboard:Destroy() end) end
end

function ItemESP:clear()
	for item in pairs(self.objects) do self:removeObject(item) end
	table.clear(self.objects)
	table.clear(self.lootFolders)
end

--------------------------------------------------------------------------------
-- PROXIMITY PROMPT REGISTRATION
--------------------------------------------------------------------------------
function ItemESP:registerContainerPrompt(prompt, connections)
	if not prompt:IsA("ProximityPrompt") then return end
	local candidate = prompt.Parent
	local fallback  = nil
	for _ = 1, 5 do
		if not candidate or candidate == Workspace then return end
		if isContainerName(candidate.Name) or isImportantName(candidate.Name) then
			self:createObject(candidate, true)
			return
		end
		if not fallback and (candidate:IsA("Model") or candidate:IsA("BasePart")) then
			fallback = candidate
		end
		candidate = candidate.Parent
	end
	if fallback then self:createObject(fallback, true) end
end

--------------------------------------------------------------------------------
-- LOOT FOLDER REGISTRATION
--------------------------------------------------------------------------------
function ItemESP:registerFolder(folder, connections)
	if not folder or self.lootFolders[folder] then return end
	self.lootFolders[folder] = true

	for _, item in ipairs(folder:GetChildren()) do
		if folder.Name ~= "WorldFinds" or string.sub(item.Name, 1, 8) == "Dropped_" then
			self:createObject(item, false)
		end
	end

	self.utils.track(connections, folder.ChildAdded:Connect(function(item)
		if folder.Name ~= "WorldFinds" or string.sub(item.Name, 1, 8) == "Dropped_" then
			self:createObject(item, false)
		end
	end))
	self.utils.track(connections, folder.ChildRemoved:Connect(function(item)
		self:removeObject(item)
	end))
	self.utils.track(connections, folder.Destroying:Connect(function()
		self.lootFolders[folder] = nil
	end))
end

--------------------------------------------------------------------------------
-- FRAME UPDATE
--------------------------------------------------------------------------------
function ItemESP:update()
	local character = LocalPlayer.Character
	local root      = character and character:FindFirstChild("HumanoidRootPart")
	local enabled   = self.cfg.LootESPEnabled and root ~= nil
	local origin    = root and root.Position
	local now       = os.clock()
	local far       = self.consts.LOOT_FAR_THROTTLE_DISTANCE
	local interval  = self.consts.LOOT_FAR_THROTTLE_INTERVAL

	for item, obj in pairs(self.objects) do
		local valid = item.Parent ~= nil and obj.part and obj.part.Parent ~= nil
		if not valid then
			self:removeObject(item)
		else
			local distance = enabled and (origin - obj.part.Position).Magnitude or nil

			-- Throttle distant items to save performance
			if distance and distance > far and now < obj.nextFarUpdate then
				continue
			end
			obj.nextFarUpdate = (distance and distance > far) and (now + interval) or 0

			local visible = distance ~= nil
				and distance <= self.cfg.LootESPMaxDistance
				and self:_isCategoryEnabled(obj.category)

			obj.billboard.Enabled = visible
			obj.highlight.Enabled = visible

			if visible then
				if self.cfg.LootESPShowDistance then
					obj.label.Text = string.format("%s\n[%d studs]", obj.displayName, math.floor(distance + 0.5))
				else
					obj.label.Text = obj.displayName
				end
			end
		end
	end
end

return ItemESP
