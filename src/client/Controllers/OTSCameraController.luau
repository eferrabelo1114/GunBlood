--!strict
--[[
	Over-the-shoulder duel camera, active for the whole duel (Countdown, Drawn, RoundOver); the
	lobby (Idle) uses the default Roblox camera.

	- Aim: mouse delta (mouse locked to the screen centre) or touch drags that no GUI/button
	  consumed. Pitch is clamped.
	- The character always faces the camera yaw, so players can pre-aim during the countdown and
	  strafe after the draw. Default movement stays camera-relative with a Scriptable camera.
	- The camera eases toward its target, is pulled in when a wall is in the way, and
	  OTSCameraController:Kick() adds a decaying recoil pitch.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local DuelStateController = require(script.Parent.DuelStateController)

local OTSCameraController = {
	Priority = 60,
	Dependencies = { "DuelStateController" },
}

local RENDER_STEP_NAME = "DuelOverShoulderCamera"
local DEFAULT_FOV = 70
local MIN_CAMERA_DISTANCE = 0.5

local localPlayer = Players.LocalPlayer
local active = false
local snapNextFrame = false
local yaw = 0
local pitch = 0
local recoil = 0
-- Smoothed camera CFrame before shake, so the shake never feeds back into the smoothing.
local smoothed: CFrame? = nil
local shakeAmount = 0
local shakeTime = 0

local function getCamera(): Camera
	return Workspace.CurrentCamera :: Camera
end

local function getRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isAlive(): boolean
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function addAimDelta(delta: Vector2, sensitivity: number)
	yaw -= delta.X * sensitivity
	pitch =
		math.clamp(pitch - delta.Y * sensitivity, -DuelConfig.PITCH_LIMIT, DuelConfig.PITCH_LIMIT)
end

local function collisionExclusions(): { Instance }
	local excluded: { Instance } = {}
	local character = localPlayer.Character
	if character then
		table.insert(excluded, character)
	end
	local arena = Workspace:FindFirstChild("Arena")
	local bounds = arena and arena:FindFirstChild(DuelConfig.ARENA_BOUNDS_NAME)
	if bounds then
		table.insert(excluded, bounds)
	end
	return excluded
end

-- Pulls the camera toward the pivot if geometry sits between them.
local function resolveCollision(pivot: Vector3, desired: CFrame): CFrame
	local offset = desired.Position - pivot
	local distance = offset.Magnitude
	if distance < MIN_CAMERA_DISTANCE then
		return desired
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = collisionExclusions()

	local result = Workspace:Raycast(pivot, offset, params)
	if result == nil then
		return desired
	end
	local safeDistance = math.max(result.Distance - 0.3, MIN_CAMERA_DISTANCE)
	return desired.Rotation + (pivot + offset.Unit * safeDistance)
end

-- Smooth noise wobble: eases in while holstered or crawling and back out afterwards.
local function updateShake(dt: number, root: BasePart): CFrame
	local goal = 0
	if DuelStateController:IsHolstered() then
		goal = 1
	elseif DuelStateController:IsCrawling() then
		local velocity = root.AssemblyLinearVelocity
		local moving = math.clamp(
			Vector2.new(velocity.X, velocity.Z).Magnitude / DuelConfig.CRAWL_WALK_SPEED,
			0,
			1
		)
		goal = DuelConfig.CRAWL_SHAKE_IDLE
			+ (DuelConfig.CRAWL_SHAKE_MOVING - DuelConfig.CRAWL_SHAKE_IDLE) * moving
	end
	shakeAmount += (goal - shakeAmount) * (1 - math.exp(-10 * dt))
	shakeTime += dt
	if shakeAmount < 0.001 then
		return CFrame.identity
	end
	local t = shakeTime * DuelConfig.HOLSTER_SHAKE_FREQUENCY
	local angle = DuelConfig.HOLSTER_SHAKE_ANGLE * shakeAmount * 2
	return CFrame.Angles(
		math.noise(t, 0.31) * angle,
		math.noise(0.73, t) * angle,
		math.noise(t, t + 1.9) * angle * 0.5
	)
end

local function update(dt: number)
	-- The default camera scripts reset MouseBehavior, so it's re-applied every frame.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	addAimDelta(UserInputService:GetMouseDelta(), DuelConfig.MOUSE_SENSITIVITY)
	recoil *= math.exp(-DuelConfig.RECOIL_RECOVERY * dt)

	local root = getRoot()
	if root == nil then
		return
	end

	local facing = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	if isAlive() then
		root.CFrame = facing
	end

	local offset = if DuelStateController:IsCrawling()
		then DuelConfig.OTS_CRAWL_OFFSET
		else DuelConfig.OTS_OFFSET
	local aim = facing * CFrame.Angles(math.min(pitch + recoil, DuelConfig.PITCH_LIMIT), 0, 0)
	local pivot = (aim * CFrame.new(offset.X, offset.Y, 0)).Position
	local target = resolveCollision(pivot, aim * CFrame.new(offset))

	local previous = smoothed
	local current: CFrame = target
	if previous and not snapNextFrame then
		current = previous:Lerp(target, 1 - math.exp(-DuelConfig.CAMERA_SMOOTHING * dt))
	end
	snapNextFrame = false
	smoothed = current
	getCamera().CFrame = current * updateShake(dt, root)
end

local function start(resetAim: boolean)
	if resetAim then
		local root = getRoot()
		if root then
			local look = root.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end
		pitch = 0
		recoil = 0
		snapNextFrame = true
	end

	local camera = getCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = DuelConfig.OTS_FOV
	UserInputService.MouseIconEnabled = false

	if not active then
		active = true
		snapNextFrame = true
		RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, update)
	end
end

local function stop()
	if active then
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		active = false
	end
	smoothed = nil
	shakeAmount = 0
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	local camera = getCamera()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = DEFAULT_FOV
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Recoil: kicks the view up; it settles back over RECOIL_RECOVERY.
function OTSCameraController:Kick()
	recoil += DuelConfig.RECOIL_KICK
end

function OTSCameraController:Init()
	DuelStateController.PhaseChanged:Connect(function(phase: string)
		if phase == "Idle" then
			stop()
		else
			-- Each round respawns the character facing the opponent; re-centre aim on it.
			start(phase == "Countdown")
		end
	end)

	UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
		if active and not gameProcessed then
			addAimDelta(Vector2.new(touch.Delta.X, touch.Delta.Y), DuelConfig.TOUCH_SENSITIVITY)
		end
	end)
end

return OTSCameraController
