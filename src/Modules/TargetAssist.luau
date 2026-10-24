--[[
	TargetAssist.luau
	HushScript – Aimlock / Target Assist system.
	Handles: player validation, target selection, velocity prediction, camera steering.
]]

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- TargetAssist creates its own module table so the Loader can call
-- TargetAssist.new(cfg, consts, utils) and get back a stateful object.
local TargetAssist = {}
TargetAssist.__index = TargetAssist

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------
function TargetAssist.new(cfg, consts, utils)
	local self = setmetatable({}, TargetAssist)

	self.cfg    = cfg
	self.consts = consts
	self.utils  = utils

	-- References shared with the frame loop
	self.camera       = Workspace.CurrentCamera
	self.playerList   = Players:GetPlayers()
	self.viewCenter   = Vector2.zero

	-- Aim state
	self.active          = false
	self.currentTarget   = nil
	self.acquiredAt      = 0
	self.engageBlend     = 0
	self.smoothedVelocity = Vector3.zero
	self.velocityValid   = false
	self.aimDefaultFOV   = nil
	self.aimFOVScale     = 1

	-- Raycast
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType    = Enum.RaycastFilterType.Exclude
	self._rayParams.IgnoreWater   = true
	self._ignoreList = {}

	return self
end

--------------------------------------------------------------------------------
-- PLAYER VALIDATION  (shared by Aim and ESP)
--------------------------------------------------------------------------------
function TargetAssist:isTeammate(player)
	local cfg = self.cfg
	if not cfg.TeamCheck then return false end

	if cfg.CustomTeamCheck then
		local ok, result = pcall(cfg.CustomTeamCheck, player)
		if ok then return result == true end
	end

	if cfg.TeamAttribute ~= "" then
		local mine   = LocalPlayer:GetAttribute(cfg.TeamAttribute)
		local theirs = player:GetAttribute(cfg.TeamAttribute)
		if theirs == nil then return not cfg.TargetNeutralPlayers end
		if mine   == nil then return false end
		return mine == theirs
	end

	local theirTeam = player.Team
	if theirTeam == nil then return not cfg.TargetNeutralPlayers end
	local myTeam = LocalPlayer.Team
	if myTeam == nil then return false end
	return myTeam == theirTeam
end

function TargetAssist:getLiveCharacter(player)
	local character = player.Character
	if not character or not character.Parent then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	if self.cfg.AliveCheck then
		if humanoid.Health <= self.cfg.MinHealth
			or humanoid:GetState() == Enum.HumanoidStateType.Dead then
			return nil
		end
	end
	if self.cfg.IgnoreForceField and character:FindFirstChildOfClass("ForceField") then
		return nil
	end
	return character, humanoid
end

-- Returns character, humanoid for a valid non-local, non-teammate, living player.
function TargetAssist:getTargetCharacter(player)
	if player == LocalPlayer then return nil end
	local character, humanoid = self:getLiveCharacter(player)
	if not character or character == LocalPlayer.Character then return nil end
	if self:isTeammate(player) then return nil end
	return character, humanoid
end

--------------------------------------------------------------------------------
-- AIM PART RESOLUTION
--------------------------------------------------------------------------------
function TargetAssist:getAimPart(character)
	local cfg = self.cfg
	local preferred = character:FindFirstChild(cfg.TargetPart)
	if preferred and preferred:IsA("BasePart") then return preferred end
	if cfg.AllowPartFallback then
		for _, name in ipairs(cfg.TargetPartFallbacks) do
			local candidate = character:FindFirstChild(name)
			if candidate and candidate:IsA("BasePart") then return candidate end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- LINE OF SIGHT
--------------------------------------------------------------------------------
function TargetAssist:hasLineOfSight(origin, partPosition, targetCharacter)
	local offset   = partPosition - origin
	local distance = offset.Magnitude
	if not (distance > 1e-3) or distance == math.huge then return false end

	table.clear(self._ignoreList)
	local localCharacter = LocalPlayer.Character
	if localCharacter then table.insert(self._ignoreList, localCharacter) end

	local direction = offset.Unit * (distance + 1.5)
	for _ = 1, self.consts.MAX_RAY_STEPS do
		self._rayParams.FilterDescendantsInstances = self._ignoreList
		local result = Workspace:Raycast(origin, direction, self._rayParams)
		if not result or not result.Instance then return false end
		local hit = result.Instance
		if hit:IsDescendantOf(targetCharacter) then return true end
		if hit.Transparency >= self.cfg.VisibilityIgnoreTransparency then
			table.insert(self._ignoreList, hit)
		else
			return false
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- TARGET EVALUATION
--------------------------------------------------------------------------------
function TargetAssist:evaluate(player, fovRadius)
	local camera = self.camera
	if not camera then return nil end

	local character, humanoid = self:getTargetCharacter(player)
	if not character then return nil end

	local part = self:getAimPart(character)
	if not part or not part.Parent then return nil end

	local camCFrame   = camera.CFrame
	local partPosition = part.Position
	local worldDistance = (partPosition - camCFrame.Position).Magnitude
	if not (worldDistance < self.cfg.MaxDistance) then return nil end

	local projected, onScreen = camera:WorldToViewportPoint(partPosition)
	if not onScreen or projected.Z <= 0 then return nil end

	-- Keep angular selection stable across FOV changes (e.g. ADS).
	local activeFOV    = math.max(camera.FieldOfView, 1)
	local defaultFOV   = math.max(self.aimDefaultFOV or activeFOV, 1)
	local fovScale     = self.aimFOVScale > 0 and self.aimFOVScale or (defaultFOV / activeFOV)
	local effectiveRadius = fovRadius * fovScale
	local screenDist  = (Vector2.new(projected.X, projected.Y) - self.viewCenter).Magnitude
	if not (screenDist <= effectiveRadius) then return nil end

	if self.cfg.VisibilityCheck then
		if not self:hasLineOfSight(camCFrame.Position, partPosition, character) then
			return nil
		end
	end

	local score
	if self.cfg.SelectionPriority == "Distance" then
		score = worldDistance + screenDist * 0.001
	elseif self.cfg.SelectionPriority == "Health" then
		score = humanoid.Health + screenDist * 0.001
	else
		score = screenDist
	end
	return part, score
end

--------------------------------------------------------------------------------
-- PREDICTION
--------------------------------------------------------------------------------
function TargetAssist:resetPrediction()
	self.smoothedVelocity = Vector3.zero
	self.velocityValid    = false
end

function TargetAssist:computeAimPosition(part, dt)
	local position = part.Position
	if not self.cfg.Prediction then return position end

	local velocity = part.AssemblyLinearVelocity
	local speed    = velocity.Magnitude
	if not (speed < self.consts.MAX_VALID_SPEED) then
		self:resetPrediction()
		return position
	end

	if self.velocityValid then
		self.smoothedVelocity = self.smoothedVelocity:Lerp(velocity, 1 - math.exp(-15 * dt))
	else
		self.smoothedVelocity = velocity
		self.velocityValid    = true
	end

	local lead = math.min(self.cfg.PredictionFactor, self.cfg.MaxPredictionTime)
	return position + self.smoothedVelocity * lead
end

--------------------------------------------------------------------------------
-- TARGET MANAGEMENT
--------------------------------------------------------------------------------
function TargetAssist:releaseTarget(reason)
	if self.currentTarget then
		self.utils.debugLog(self.cfg, "Released target", self.currentTarget.Name, reason or "")
	end
	self.currentTarget = nil
	self.engageBlend   = 0
	self:resetPrediction()
end

function TargetAssist:setTarget(player)
	if player ~= self.currentTarget then
		self.utils.debugLog(self.cfg, "Acquired target", player and player.Name or "none")
		self.currentTarget = player
		self.acquiredAt    = os.clock()
		self:resetPrediction()
	end
end

function TargetAssist:updateTarget()
	local now = os.clock()

	if self.currentTarget then
		local radius = self.cfg.FOVRadius
		if self.cfg.TargetLock then radius = radius * self.cfg.LockBreakFOVMultiplier end
		local part = self:evaluate(self.currentTarget, radius)
		if part then
			if self.cfg.TargetLock or (now - self.acquiredAt) < self.cfg.SwitchCooldown then
				return part
			end
		else
			self:releaseTarget("invalid")
		end
	end

	local bestPlayer, bestPart, bestScore = nil, nil, math.huge
	for _, player in ipairs(self.playerList) do
		local part, score = self:evaluate(player, self.cfg.FOVRadius)
		if part and score < bestScore then
			bestPlayer, bestPart, bestScore = player, part, score
		end
	end

	if bestPlayer then
		self:setTarget(bestPlayer)
		return bestPart
	end
	if self.currentTarget then self:releaseTarget("none eligible") end
	return nil
end

--------------------------------------------------------------------------------
-- CAMERA STEERING
--------------------------------------------------------------------------------
function TargetAssist:applyCamera(aimPosition, dt)
	local cam = self.camera
	if not cam then return end
	if cam.CameraType == Enum.CameraType.Scriptable and not self.cfg.ApplyToScriptableCamera then return end

	local camCFrame = cam.CFrame
	local origin    = camCFrame.Position
	local toTarget  = aimPosition - origin
	local distance  = toTarget.Magnitude
	if not (distance > 1e-3) or distance == math.huge then return end

	local desired = toTarget / distance
	if math.abs(desired.Y) > 0.9995 then return end -- degenerate straight up/down

	local dot   = math.clamp(camCFrame.LookVector:Dot(desired), -1, 1)
	local angle = math.acos(dot)
	if angle < 1e-5 or angle < math.rad(self.cfg.DeadzoneDegrees) then return end

	local alpha = 1
	if self.cfg.CameraSmoothing > 0 then
		alpha = 1 - math.exp(-self.cfg.CameraSmoothing * dt)
	end
	alpha = alpha * self.engageBlend
	if self.cfg.MaxTurnRate > 0 then
		alpha = math.min(alpha, math.rad(self.cfg.MaxTurnRate) * dt / angle)
	end
	if not (alpha > 0) then return end

	cam.CFrame = camCFrame:Lerp(CFrame.lookAt(origin, aimPosition), math.min(alpha, 1))
end

--------------------------------------------------------------------------------
-- ACTIVE / ENABLED STATE
--------------------------------------------------------------------------------
function TargetAssist:setActive(value, reason)
	if self.active == value then return end
	self.active = value
	if not value then self:releaseTarget(reason or "deactivated") end
	self.utils.debugLog(self.cfg, "Active:", value, reason or "")
end

function TargetAssist:setEnabled(value, syncUI)
	self.cfg.Enabled = value == true
	if not self.cfg.Enabled then self:setActive(false, "disabled") end
	if syncUI then syncUI() end
end

--------------------------------------------------------------------------------
-- FOV SCALE UPDATE  (call once per frame)
--------------------------------------------------------------------------------
function TargetAssist:updateAimFOVScale(dt)
	local camera = self.camera
	if not camera then return end
	if not self.aimDefaultFOV then self.aimDefaultFOV = camera.FieldOfView end
	local activeFOV   = math.max(camera.FieldOfView, 1)
	local targetScale = math.clamp(self.aimDefaultFOV / activeFOV, 0.25, 4)
	self.aimFOVScale  = self.utils.approach(self.aimFOVScale, targetScale, 16, dt)
end

--------------------------------------------------------------------------------
-- MAIN FRAME STEP  (called from the render-step callback)
--------------------------------------------------------------------------------
-- Returns hasTarget (bool).
function TargetAssist:step(dt)
	self:updateAimFOVScale(dt)

	if self.active and not self.cfg.Enabled then
		self:setActive(false, "disabled")
	end

	-- Guard: hold input released outside window
	if self.active and self.cfg.ActivationMode == "Hold" then
		if self.utils.isBindingDown(self.cfg.ActivationInput) == false then
			self:setActive(false, "input no longer down")
		end
	end

	local hasTarget = false
	if self.active and self.cfg.Enabled and self.camera then
		local part = self:updateTarget()
		if part and self.currentTarget then
			hasTarget = true
			if self.cfg.EngageEaseTime > 0 then
				self.engageBlend = math.min(1, self.engageBlend + dt / self.cfg.EngageEaseTime)
			else
				self.engageBlend = 1
			end
			self:applyCamera(self:computeAimPosition(part, dt), dt)
		end
	elseif self.currentTarget then
		self:releaseTarget("inactive")
	end

	return hasTarget
end

return TargetAssist
