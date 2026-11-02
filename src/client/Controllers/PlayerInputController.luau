--!strict
--[[
	Duel input and shot effects. Actions are bound through ContextActionService while a duel runs,
	which also creates on-screen FIRE / READY buttons on touch devices.
	- Ready (holster): hold Shift or the READY button during the countdown; every change is
	  reported to the server, which decides whether it was a false start.
	- Fire: left click or the FIRE button. Hitscan from the revolver's muzzle to whatever the
	  screen-centre crosshair is on (see fire). Firing during the countdown is sent too and counts
	  as a false start.
	- Effects: recoil kick, draw sound when the revolver unlocks, an instant tracer and gunshot
	  for your own shots, and tracers / sounds for the opponent's ShotFired.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Hitscan = require(ReplicatedStorage.Shared.Modules.Hitscan)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local DuelStateController = require(script.Parent.DuelStateController)
local OTSCameraController = require(script.Parent.OTSCameraController)

local PlayerInputController = {
	Priority = 60,
	Dependencies = { "DuelStateController", "OTSCameraController" },
}

local FIRE_ACTION = "DuelFire"
local READY_ACTION = "DuelReady"

local localPlayer = Players.LocalPlayer
local actionsBound = false
local lastFire = 0
local sentHolster: boolean? = nil
-- Inputs currently holding READY: key codes for keyboard, InputObjects for touches.
local heldReady: { [any]: true } = {}
local gunshotSound: Sound? = nil
local headshotSound: Sound? = nil
local drawSound: Sound? = nil

local function isHolsterHeld(): boolean
	if next(heldReady) ~= nil then
		return true
	end
	for _, keyCode in DuelConfig.HOLSTER_KEYS do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

local function reportHolster()
	if DuelStateController:GetPhase() ~= "Countdown" then
		return
	end
	local holding = isHolsterHeld()
	DuelStateController:SetHolstered(holding)
	if holding ~= sentHolster then
		sentHolster = holding
		Net.HolsterState.send(holding)
	end
end

local function getMuzzlePosition(character: Model): Vector3?
	local revolver = character:FindFirstChild("Revolver")
	local muzzle = revolver and revolver:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	local head = character:FindFirstChild(DuelConfig.HEAD_PART_NAME)
	return if head and head:IsA("BasePart") then head.Position else nil
end

local function playSound(sound: Sound?)
	if sound then
		SoundService:PlayLocalSound(sound)
	end
end

local function drawTracer(origin: Vector3, hitPosition: Vector3)
	local length = (hitPosition - origin).Magnitude
	if length < 0.05 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 220, 140)
	tracer.Size = Vector3.new(0.08, 0.08, length)
	tracer.CFrame = CFrame.lookAt(origin, hitPosition) * CFrame.new(0, 0, -length / 2)
	tracer.Parent = Workspace

	task.delay(DuelConfig.TRACER_LIFETIME, function()
		tracer:Destroy()
	end)
end

--[[
	Hitscan: find what the crosshair is on (camera ray), then shoot from the revolver's muzzle
	straight at that point. The server re-casts the same ray from the same muzzle to decide hits;
	the tracer is drawn here immediately along the locally predicted path.
]]
local function fire()
	local phase = DuelStateController:GetPhase()
	local canFire = DuelStateController:CanFire()
	if phase ~= "Countdown" and not canFire then
		return
	end

	local now = os.clock()
	if now - lastFire < DuelConfig.FIRE_COOLDOWN then
		return
	end

	local character = localPlayer.Character
	local camera = Workspace.CurrentCamera
	if character == nil or camera == nil then
		return
	end
	local muzzle = getMuzzlePosition(character)
	if muzzle == nil then
		return
	end
	lastFire = now

	local cameraCFrame = camera.CFrame
	local look = cameraCFrame.LookVector
	local aimResult =
		Hitscan.Cast(cameraCFrame.Position, look * DuelConfig.MAX_RANGE, { character })
	local aimPoint = if aimResult
		then aimResult.Position
		else cameraCFrame.Position + look * DuelConfig.MAX_RANGE

	local toAim = aimPoint - muzzle
	local direction = if toAim.Magnitude > 0.01 then toAim.Unit else look
	Net.FireShot.send({ origin = muzzle, direction = direction })

	if canFire then
		local ray = direction * DuelConfig.MAX_RANGE
		local shot = Hitscan.Cast(muzzle, ray, { character })
		drawTracer(muzzle, if shot then shot.Position else muzzle + ray)
		playSound(gunshotSound)
		OTSCameraController:Kick()
	end
end

local function onFireAction(_actionName: string, state: Enum.UserInputState, _input: InputObject)
	if state == Enum.UserInputState.Begin then
		fire()
	end
	return Enum.ContextActionResult.Sink
end

local function onReadyAction(_actionName: string, state: Enum.UserInputState, input: InputObject)
	local key: any = if input.UserInputType == Enum.UserInputType.Keyboard
		then input.KeyCode
		else input
	if state == Enum.UserInputState.Begin then
		heldReady[key] = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		heldReady[key] = nil
	end
	reportHolster()
	return Enum.ContextActionResult.Sink
end

local function bindActions()
	if actionsBound then
		return
	end
	actionsBound = true

	ContextActionService:BindAction(
		FIRE_ACTION,
		onFireAction,
		true,
		Enum.UserInputType.MouseButton1
	)
	ContextActionService:SetTitle(FIRE_ACTION, "FIRE")

	ContextActionService:BindAction(
		READY_ACTION,
		onReadyAction,
		true,
		table.unpack(DuelConfig.HOLSTER_KEYS)
	)
	ContextActionService:SetTitle(READY_ACTION, "READY")
end

local function unbindActions()
	if not actionsBound then
		return
	end
	actionsBound = false
	ContextActionService:UnbindAction(FIRE_ACTION)
	ContextActionService:UnbindAction(READY_ACTION)
	table.clear(heldReady)
end

local function makeSound(soundId: string, volume: number): Sound?
	if soundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local function onShotFired(value)
	-- The shooter already drew its own shot the instant it fired.
	if value.shooter ~= localPlayer then
		drawTracer(value.origin, value.hitPosition)
		playSound(gunshotSound)
	end
	if value.headshot then
		playSound(headshotSound)
	end
end

function PlayerInputController:Init()
	gunshotSound = makeSound(DuelConfig.GUNSHOT_SOUND_ID, 0.8)
	headshotSound = makeSound(DuelConfig.HEADSHOT_SOUND_ID, 1)
	drawSound = makeSound(DuelConfig.DRAW_SOUND_ID, 0.9)

	DuelStateController.PhaseChanged:Connect(function(phase: string)
		if phase == "Idle" then
			unbindActions()
		elseif phase == "Countdown" then
			bindActions()
			-- Report the current state so a key already held when the countdown starts counts.
			sentHolster = nil
			reportHolster()
		end
	end)

	DuelStateController.WeaponReady:Connect(function()
		playSound(drawSound)
	end)

	Net.ShotFired.listen(onShotFired)
end

return PlayerInputController
