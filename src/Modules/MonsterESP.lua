--[[
	MonsterESP.luau
	HushScript – Player (and monster) 2D ESP system.
	Draws name labels, distance / health info, head circle,
	look-direction line, skeleton, and optional Highlight glow.
	All visuals live in a ScreenGui; Highlights go in an espFolder in Workspace.
]]

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local MonsterESP = {}
MonsterESP.__index = MonsterESP

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------
function MonsterESP.new(cfg, consts, utils, espRoot, espFolder)
	local self = setmetatable({}, MonsterESP)

	self.cfg       = cfg
	self.consts    = consts
	self.utils     = utils
	self.espRoot   = espRoot    -- Frame in the overlay ScreenGui
	self.espFolder = espFolder  -- Workspace folder for Highlight instances

	self.objects   = {}  -- [player] = espObject
	self.shown     = 0   -- count drawn last frame

	-- Live ref shared with TargetAssist
	self.camera    = Workspace.CurrentCamera

	return self
end

--------------------------------------------------------------------------------
-- LINE PRIMITIVES
--------------------------------------------------------------------------------
local MAX_LINE_LENGTH

function MonsterESP:_makeLine(parent)
	MAX_LINE_LENGTH = self.consts.MAX_LINE_LENGTH
	return self.utils.create("Frame", {
		AnchorPoint         = Vector2.new(0.5, 0.5),
		BackgroundColor3    = self.cfg.ESPColor,
		BorderSizePixel     = 0,
		Size                = UDim2.fromOffset(0, 1),
		Visible             = false,
	}, parent)
end

function MonsterESP:_setLine(line, ax, ay, bx, by, thickness)
	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	if not (length >= 0.5) or length > MAX_LINE_LENGTH then
		line.Visible = false
		return
	end
	line.Size     = UDim2.fromOffset(length, thickness)
	line.Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5)
	line.Rotation = math.deg(math.atan2(dy, dx))
	line.Visible  = true
end

--------------------------------------------------------------------------------
-- ESP OBJECT CREATION
--------------------------------------------------------------------------------
function MonsterESP:_createObject(player)
	if not self.espRoot then return nil end

	local cfg       = self.cfg
	local consts    = self.consts
	local create    = self.utils.create
	local Theme     = consts.Theme
	local FONT      = consts.FONT
	local FONT_BOLD = consts.FONT_BOLD
	local MAX_BONES = consts.MAX_BONES

	local root = create("Frame", {
		Name                  = "ESP_" .. tostring(player.UserId),
		BackgroundTransparency = 1,
		BorderSizePixel       = 0,
		Size                  = UDim2.fromScale(1, 1),
		Visible               = false,
	}, self.espRoot)

	local nameLabel = create("TextLabel", {
		Name                    = "Name",
		AnchorPoint             = Vector2.new(0.5, 1),
		BackgroundTransparency  = 1,
		Size                    = UDim2.fromOffset(240, 16),
		Font                    = FONT_BOLD,
		TextSize                = 13,
		TextColor3              = cfg.ESPColor,
		TextStrokeColor3        = Theme.Black,
		TextStrokeTransparency  = 0.4,
		Text                    = "",
		Visible                 = false,
	}, root)

	local infoLabel = create("TextLabel", {
		Name                    = "Info",
		AnchorPoint             = Vector2.new(0.5, 1),
		BackgroundTransparency  = 1,
		Size                    = UDim2.fromOffset(240, 16),
		Font                    = FONT,
		TextSize                = 12,
		TextColor3              = Theme.Text,
		TextStrokeColor3        = Theme.Black,
		TextStrokeTransparency  = 0.4,
		Text                    = "",
		Visible                 = false,
	}, root)

	local headFrame = create("Frame", {
		Name                  = "Head",
		AnchorPoint           = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel       = 0,
		Size                  = UDim2.fromOffset(8, 8),
		Visible               = false,
	}, root)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, headFrame)
	local headStroke = create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness       = 1.5,
		Color           = cfg.ESPColor,
	}, headFrame)

	local look  = self:_makeLine(root)
	local bones = {}
	for i = 1, MAX_BONES do bones[i] = self:_makeLine(root) end

	local obj = {
		root       = root,
		nameLabel  = nameLabel,
		infoLabel  = infoLabel,
		headFrame  = headFrame,
		headStroke = headStroke,
		look       = look,
		bones      = bones,
		highlight  = nil,
		parts      = {},
		screen     = {},
		character  = nil,
		rigR15     = false,
		shown      = false,
		lastStyle  = -1,
		lastColor  = nil,
		infoDist   = -1,
		infoHp     = -1,
		nameText   = nil,
		boneUsed   = -1,
	}
	self.objects[player] = obj
	return obj
end

--------------------------------------------------------------------------------
-- STYLE APPLICATION
--------------------------------------------------------------------------------
function MonsterESP:_applyStyle(obj, color, styleVersion)
	local cfg      = self.cfg
	local textSize = cfg.ESPTextSize
	local lineH    = textSize + 3

	obj.nameLabel.TextColor3   = color
	obj.nameLabel.TextSize     = textSize
	obj.nameLabel.Size         = UDim2.fromOffset(240, lineH)
	obj.infoLabel.TextSize     = math.max(9, textSize - 1)
	obj.infoLabel.Size         = UDim2.fromOffset(240, lineH)

	obj.headStroke.Color       = color
	obj.headStroke.Thickness   = cfg.ESPThickness
	obj.headStroke.Transparency = cfg.ESPTransparency

	obj.look.BackgroundColor3  = color
	obj.look.BackgroundTransparency = cfg.ESPTransparency

	for _, line in ipairs(obj.bones) do
		line.BackgroundColor3        = color
		line.BackgroundTransparency  = cfg.ESPTransparency
	end

	if obj.highlight then
		obj.highlight.FillColor    = color
		obj.highlight.OutlineColor = color
	end

	obj.lastStyle = styleVersion
	obj.lastColor = color
end

--------------------------------------------------------------------------------
-- PER-PART SCREEN PROJECTION (cached per frame)
--------------------------------------------------------------------------------
function MonsterESP:_getEspPart(obj, name)
	local part = obj.parts[name]
	if part and part.Parent then return part end
	local found = obj.character and obj.character:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		obj.parts[name] = found
		return found
	end
	obj.parts[name] = nil
	return nil
end

function MonsterESP:_getEspScreen(obj, name)
	local cached = obj.screen[name]
	if cached ~= nil then return cached or nil end
	local part = self:_getEspPart(obj, name)
	if part then
		local v = self.camera:WorldToViewportPoint(part.Position)
		if v.Z > 0 then
			local point = Vector2.new(v.X, v.Y)
			obj.screen[name] = point
			return point
		end
	end
	obj.screen[name] = false
	return nil
end

--------------------------------------------------------------------------------
-- HIDE / REMOVE
--------------------------------------------------------------------------------
function MonsterESP:_hideObject(obj)
	if obj.shown then
		obj.shown       = false
		obj.root.Visible = false
	end
	if obj.highlight and obj.highlight.Enabled then
		obj.highlight.Enabled = false
	end
end

function MonsterESP:removePlayer(player)
	local obj = self.objects[player]
	if not obj then return end
	self.objects[player] = nil
	pcall(function() obj.root:Destroy() end)
	if obj.highlight then pcall(function() obj.highlight:Destroy() end) end
end

function MonsterESP:clear()
	for player in pairs(self.objects) do self:removePlayer(player) end
	table.clear(self.objects)
end

--------------------------------------------------------------------------------
-- RENDER ONE PLAYER
--------------------------------------------------------------------------------
function MonsterESP:_renderPlayer(player, camPos, styleVersion, targetAssist)
	local character, humanoid = targetAssist:getTargetCharacter(player)
	if not character then return false end

	local camera  = self.camera
	local cfg     = self.cfg
	local consts  = self.consts

	local head = character:FindFirstChild("Head")
	if head and not head:IsA("BasePart") then head = nil end
	local focus = head or character:FindFirstChild("HumanoidRootPart")
	if not (focus and focus:IsA("BasePart")) then return false end

	local focusPos = focus.Position
	local distance = (focusPos - camPos).Magnitude
	if not (distance <= cfg.ESPMaxDistance) then return false end

	local projected = camera:WorldToViewportPoint(focusPos)
	if projected.Z <= 0 then return false end

	local viewport = camera.ViewportSize
	local margin   = consts.ESP_VIEW_MARGIN
	if projected.X < -margin or projected.X > viewport.X + margin
		or projected.Y < -margin or projected.Y > viewport.Y + margin then
		return false
	end

	local obj = self.objects[player] or self:_createObject(player)
	if not obj then return false end

	-- Update character ref
	if obj.character ~= character then
		obj.character = character
		table.clear(obj.parts)
		obj.rigR15     = humanoid.RigType == Enum.HumanoidRigType.R15
		obj.lastStyle  = -1
		obj.boneUsed   = -1
	end
	table.clear(obj.screen)

	-- Style / color
	local color = cfg.ESPTeamColors and player.Team and player.TeamColor.Color or cfg.ESPColor
	if obj.lastStyle ~= styleVersion or obj.lastColor ~= color then
		self:_applyStyle(obj, color, styleVersion)
	end

	local thickness  = cfg.ESPThickness
	local textSize   = cfg.ESPTextSize
	local lineHeight = textSize + 3

	-- Labels (above head)
	local showInfo = cfg.ESPShowDistance or cfg.ESPShowHealth
	local topV     = camera:WorldToViewportPoint(focusPos + Vector3.new(0, head and 1.6 or 3.2, 0))
	local tx, ty   = topV.X, topV.Y

	if showInfo then
		local dist = math.floor(distance + 0.5)
		local hp   = math.floor(humanoid.Health + 0.5)
		if hp ~= hp then hp = 0 end
		if obj.infoDist ~= dist or obj.infoHp ~= hp then
			obj.infoDist, obj.infoHp = dist, hp
			if cfg.ESPShowDistance and cfg.ESPShowHealth then
				obj.infoLabel.Text = string.format("%d studs  |  %d HP", dist, hp)
			elseif cfg.ESPShowDistance then
				obj.infoLabel.Text = string.format("%d studs", dist)
			else
				obj.infoLabel.Text = string.format("%d HP", hp)
			end
		end
		obj.infoLabel.Position = UDim2.fromOffset(tx, ty)
		obj.infoLabel.Visible  = true
	else
		obj.infoLabel.Visible = false
	end

	if cfg.ESPShowName then
		local name = cfg.ESPUseDisplayName and player.DisplayName or player.Name
		if obj.nameText ~= name then
			obj.nameText      = name
			obj.nameLabel.Text = name
		end
		obj.nameLabel.Position = UDim2.fromOffset(tx, ty - (showInfo and lineHeight or 0))
		obj.nameLabel.Visible  = true
	else
		obj.nameLabel.Visible = false
	end

	-- Head circle
	if cfg.ESPShowHeadCircle and head then
		local edge = camera:WorldToViewportPoint(focusPos + camera.CFrame.UpVector * (head.Size.Y * 0.5))
		local ex, ey = edge.X - projected.X, edge.Y - projected.Y
		local radius = math.clamp(math.sqrt(ex*ex + ey*ey), 3, 300)
		obj.headFrame.Size     = UDim2.fromOffset(radius * 2, radius * 2)
		obj.headFrame.Position = UDim2.fromOffset(projected.X, projected.Y)
		obj.headFrame.Visible  = true
	else
		obj.headFrame.Visible = false
	end

	-- Look direction
	if cfg.ESPShowLookLine and head then
		local b = camera:WorldToViewportPoint(focusPos + head.CFrame.LookVector * cfg.ESPLookLength)
		if b.Z > 0 then
			self:_setLine(obj.look, projected.X, projected.Y, b.X, b.Y, thickness)
		else
			obj.look.Visible = false
		end
	else
		obj.look.Visible = false
	end

	-- Skeleton
	local bones = obj.bones
	local used  = 0
	if cfg.ESPShowSkeleton then
		local list = obj.rigR15 and consts.R15_BONES or consts.R6_BONES
		used = #list
		for i = 1, used do
			local pair = list[i]
			local a    = self:_getEspScreen(obj, pair[1])
			local b    = self:_getEspScreen(obj, pair[2])
			if a and b then
				self:_setLine(bones[i], a.X, a.Y, b.X, b.Y, thickness)
			else
				bones[i].Visible = false
			end
		end
	end
	if obj.boneUsed ~= used then
		obj.boneUsed = used
		for i = used + 1, #bones do bones[i].Visible = false end
	end

	-- Highlight glow
	if cfg.ESPHighlight and self.espFolder then
		local hl = obj.highlight
		if not hl or not hl.Parent then
			hl = self.utils.create("Highlight", {
				Name                 = "Glow",
				FillTransparency     = 0.8,
				OutlineTransparency  = 0,
				DepthMode            = Enum.HighlightDepthMode.AlwaysOnTop,
				FillColor            = color,
				OutlineColor         = color,
			}, self.espFolder)
			obj.highlight = hl
		end
		if hl.Adornee ~= character then hl.Adornee = character end
		if not hl.Enabled then hl.Enabled = true end
	elseif obj.highlight and obj.highlight.Enabled then
		obj.highlight.Enabled = false
	end

	if not obj.shown then
		obj.shown        = true
		obj.root.Visible = true
	end
	return true
end

--------------------------------------------------------------------------------
-- FRAME UPDATE
--------------------------------------------------------------------------------
-- targetAssist: TargetAssist instance (provides getTargetCharacter)
-- playerList:   current player list
-- styleVersion: incrementing int from syncUI
-- Returns number of players drawn.
function MonsterESP:update(playerList, styleVersion, targetAssist)
	if not self.camera or not self.espRoot then return 0 end

	local count  = 0
	local camPos = self.camera.CFrame.Position
	local enabled = self.cfg.ESPEnabled

	for _, player in ipairs(playerList) do
		local shown = false
		if enabled and player ~= LocalPlayer then
			local ok, result = pcall(self._renderPlayer, self, player, camPos, styleVersion, targetAssist)
			if ok then
				shown = result == true
			elseif self.cfg.Debug then
				warn("[SmoothTargetAssist] ESP error:", result)
			end
		end
		if shown then
			count += 1
		else
			local obj = self.objects[player]
			if obj then self:_hideObject(obj) end
		end
	end

	self.shown = count
	return count
end

return MonsterESP
