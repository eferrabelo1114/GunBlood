--!strict
--[[
	Points every drawn revolver arm where its owner is aiming, held straight out.

	- Holstered (countdown, holding Shift): the arm hangs at the side, animations untouched.
	- At the draw: the arm swings up over ARM_DRAW_TIME, then tracks the aim smoothly.
	- The local player's arm follows the camera's crosshair target; it's sent to the server
	  (AimUpdate, ~AIM_SEND_RATE per second), which stores it on the character as AimDirection
	  so every other client points that arm too. Bots get their AimDirection from the server.
	- ArmAim keeps the arm inside a realistic cone: never behind the back or straight sideways.

	Runs on PreSimulation, after animations step, so it can also cancel the walk/idle animation
	on the shoulder, elbow and wrist: the aimed arm stays straight instead of swinging.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ArmAim = require(ReplicatedStorage.Shared.Modules.ArmAim)
local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Hitscan = require(ReplicatedStorage.Shared.Modules.Hitscan)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Rig = require(ReplicatedStorage.Shared.Modules.Rig)

local ArmAimController = {
	Priority = 60,
}

type Arm = {
	Shoulder: Instance,
	UpperTorso: BasePart,
	Base: CFrame,
	Elbow: Instance?,
	Wrist: Instance?,
	-- 0 = hanging at the side, 1 = fully raised.
	Raise: number,
	Direction: Vector3,
	Posed: boolean,
}

local localPlayer = Players.LocalPlayer
local arms: { [Model]: Arm } = setmetatable({} :: any, { __mode = "k" })
local lastSent = 0
local sentDirection: Vector3? = nil

local function getArm(character: Model): Arm?
	local cached = arms[character]
	if cached and cached.Shoulder.Parent and cached.UpperTorso.Parent == character then
		return cached
	end
	local shoulder, upperTorso = Rig.FindJoint(character, "UpperTorso", "RightUpperArm")
	if shoulder == nil or upperTorso == nil then
		return nil
	end
	local base = Rig.GetBaseFrame(shoulder, upperTorso)
	if base == nil then
		return nil
	end
	local arm: Arm = {
		Shoulder = shoulder,
		UpperTorso = upperTorso,
		Base = base,
		Elbow = (Rig.FindJoint(character, "RightUpperArm", "RightLowerArm")),
		Wrist = (Rig.FindJoint(character, "RightLowerArm", "RightHand")),
		Raise = 0,
		Direction = ArmAim.Center(false),
		Posed = false,
	}
	arms[character] = arm
	return arm
end

-- What the crosshair is on: the same camera ray PlayerInputController fires along.
local function crosshairTarget(character: Model): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local origin = camera.CFrame.Position
	local ray = camera.CFrame.LookVector * DuelConfig.MAX_RANGE
	local result = Hitscan.Cast(origin, ray, { character })
	return if result then result.Position else origin + ray
end

local function sendAim(direction: Vector3)
	local now = os.clock()
	if now - lastSent < 1 / DuelConfig.AIM_SEND_RATE then
		return
	end
	local previous = sentDirection
	if previous and previous:Dot(direction) > math.cos(math.rad(0.5)) then
		return
	end
	lastSent = now
	sentDirection = direction
	Net.AimUpdate.send({ direction = direction })
end

local function targetDirection(character: Model, arm: Arm, crawling: boolean): Vector3
	if character == localPlayer.Character then
		local target = crosshairTarget(character)
		if target then
			local shoulderWorld = (arm.UpperTorso.CFrame * arm.Base).Position
			local direction = ArmAim.DirectionTo(arm.UpperTorso, shoulderWorld, target, crawling)
			sendAim(direction)
			return direction
		end
	end
	local stored = character:GetAttribute(DuelConfig.AIM_DIRECTION_ATTRIBUTE)
	return if typeof(stored) == "Vector3"
		then ArmAim.Clamp(stored, crawling)
		else ArmAim.Center(crawling)
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

local function updateArm(character: Model, dt: number)
	local arm = getArm(character)
	if arm == nil then
		return
	end

	local drawn = character:GetAttribute(DuelConfig.ARM_DRAWN_ATTRIBUTE) == true
		and character:GetAttribute(DuelConfig.DISARMED_ATTRIBUTE) ~= true
	local step = dt / DuelConfig.ARM_DRAW_TIME
	arm.Raise = math.clamp(arm.Raise + (if drawn then step else -step), 0, 1)

	if arm.Raise <= 0 then
		if arm.Posed then
			Rig.WriteFrame(arm.Shoulder, arm.UpperTorso, arm.Base)
			arm.Posed = false
		end
		return
	end

	local crawling = character:GetAttribute(DuelConfig.CRAWLING_ATTRIBUTE) == true
	local target = targetDirection(character, arm, crawling)
	if not arm.Posed then
		arm.Direction = target
	else
		local blend = 1 - math.exp(-DuelConfig.ARM_AIM_SMOOTHING * dt)
		arm.Direction = arm.Direction:Lerp(target, blend).Unit
	end
	arm.Posed = true

	local aimed = ArmAim.ShoulderRotation(arm.Direction, crawling)
	local rotation = CFrame.new():Lerp(aimed, easeOut(arm.Raise))
	Rig.WriteFrame(arm.Shoulder, arm.UpperTorso, arm.Base * rotation)
	Rig.ClearAnimation(arm.Shoulder)
	if arm.Elbow then
		Rig.ClearAnimation(arm.Elbow)
	end
	if arm.Wrist then
		Rig.ClearAnimation(arm.Wrist)
	end
end

local function step(dt: number)
	for _, child in Workspace:GetChildren() do
		if
			child:IsA("Model")
			and (child:GetAttribute(DuelConfig.ARM_DRAWN_ATTRIBUTE) ~= nil or arms[child])
			and child:FindFirstChildOfClass("Humanoid")
		then
			updateArm(child, dt)
		end
	end
end

function ArmAimController:Init()
	localPlayer.CharacterAdded:Connect(function()
		sentDirection = nil
	end)
	RunService.PreSimulation:Connect(step)
end

return ArmAimController
