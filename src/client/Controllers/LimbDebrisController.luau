--!strict
--[[
	Animates shot-off limbs (Net.LimbSevered) locally. The server has already hidden the severed
	segments; this flies a copy of them along the server's velocity with spin, lays it flat where
	it lands, then fades it out. It's pure CFrame animation on anchored, non-colliding parts, so
	it's smooth and never pushes anyone around.

	Copies sit in a model with a Humanoid of the character's rig type plus copies of its Shirt,
	Pants and BodyColors, which is what makes classic clothing render on body parts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local DuelStateController = require(script.Parent.DuelStateController)

local LimbDebrisController = {
	Priority = 60,
	Dependencies = { "DuelStateController" },
}

-- Floatier than real gravity so the arc reads clearly.
local GRAVITY_SCALE = 0.6
local SETTLE_TIME = 0.12
local FADE_TIME = 1
local MAX_FLIGHT_TIME = 4

type Flight = {
	Model: Model,
	Root: BasePart,
	BaseTransparency: { [BasePart]: number },
	Position: Vector3,
	Rotation: CFrame,
	Velocity: Vector3,
	Spin: Vector3,
	Age: number,
	LandedAt: number?,
	SettleFrom: CFrame,
	SettleTo: CFrame,
	Settled: boolean,
}

local flights: { Flight } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = DuelConfig.LIMB_DEBRIS_FOLDER_NAME
	created.Parent = Workspace
	folder = created
	return created
end

local function clearAll()
	for _, flight in flights do
		flight.Model:Destroy()
	end
	table.clear(flights)
end

local function copyPart(part: BasePart): BasePart?
	part.Archivable = true
	local copy: BasePart? = part:Clone()
	if not copy then
		return nil
	end
	for _, descendant in copy:GetDescendants() do
		if
			descendant:IsA("JointInstance")
			or descendant:IsA("Constraint")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("NoCollisionConstraint")
		then
			descendant:Destroy()
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 0
		end
	end
	local original = part:GetAttribute(DuelConfig.SEVERED_TRANSPARENCY_ATTRIBUTE)
	copy.Transparency = if type(original) == "number" then original else 0
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CFrame = part.CFrame
	return copy
end

local function createModel(character: Instance?): Model
	local model = Instance.new("Model")
	model.Name = "SeveredLimb"

	local source = character and character:FindFirstChildOfClass("Humanoid")
	if character and source then
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = source.RigType
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false
		humanoid.Parent = model

		for _, className in { "Shirt", "Pants", "BodyColors" } do
			local clothing = character:FindFirstChildOfClass(className)
			if clothing then
				clothing.Archivable = true
				local copy = clothing:Clone()
				if copy then
					copy.Parent = model
				end
			end
		end
	end
	return model
end

local function onLimbSevered(value: { parts: { any }, velocity: Vector3, spin: Vector3 })
	local originals: { BasePart } = {}
	for _, instance in value.parts do
		if typeof(instance) == "Instance" and instance:IsA("BasePart") then
			table.insert(originals, instance)
		end
	end
	if #originals == 0 then
		return
	end

	local model = createModel(originals[1].Parent)
	local root: BasePart? = nil
	local baseTransparency: { [BasePart]: number } = {}
	for _, original in originals do
		local copy = copyPart(original)
		if copy then
			copy.Parent = model
			baseTransparency[copy] = copy.Transparency
			root = root or copy
		end
	end
	if root == nil then
		model:Destroy()
		return
	end
	model.PrimaryPart = root
	model.Parent = getFolder()

	local start = root.CFrame
	table.insert(flights, {
		Model = model,
		Root = root,
		BaseTransparency = baseTransparency,
		Position = start.Position,
		Rotation = start.Rotation,
		Velocity = value.velocity,
		Spin = value.spin,
		Age = 0,
		LandedAt = nil,
		SettleFrom = start,
		SettleTo = start,
		Settled = false,
	})
end

local function landingParams(): RaycastParams
	local excluded: { Instance } = { getFolder() }
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			table.insert(excluded, child)
		end
	end
	local arena = Workspace:FindFirstChild("Arena")
	local bounds = arena and arena:FindFirstChild(DuelConfig.ARENA_BOUNDS_NAME)
	if bounds then
		table.insert(excluded, bounds)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	return params
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Flies until the arc hits the ground, then eases the limb down flat with a random yaw.
local function fly(flight: Flight, dt: number, params: RaycastParams)
	flight.Velocity += Vector3.new(0, -Workspace.Gravity * GRAVITY_SCALE * dt, 0)
	local move = flight.Velocity * dt
	local result = Workspace:Raycast(flight.Position, move, params)
	if result then
		flight.LandedAt = flight.Age
		flight.SettleFrom = CFrame.new(flight.Position) * flight.Rotation
		local lift = flight.Root.Size.Z / 2
		flight.SettleTo = CFrame.new(result.Position + result.Normal * lift)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* CFrame.Angles(math.pi / 2, 0, 0)
		return
	end

	flight.Position += move
	local spinAngle = flight.Spin.Magnitude * dt
	if spinAngle > 0 then
		flight.Rotation = CFrame.fromAxisAngle(flight.Spin.Unit, spinAngle) * flight.Rotation
	end
	flight.Model:PivotTo(CFrame.new(flight.Position) * flight.Rotation)
end

local function step(dt: number)
	if #flights == 0 then
		return
	end
	local params: RaycastParams? = nil

	for index = #flights, 1, -1 do
		local flight = flights[index]
		flight.Age += dt

		local landedAt = flight.LandedAt
		if landedAt == nil then
			if flight.Age > MAX_FLIGHT_TIME then
				flight.Model:Destroy()
				table.remove(flights, index)
				continue
			end
			params = params or landingParams()
			fly(flight, dt, params :: RaycastParams)
		elseif not flight.Settled then
			local alpha = math.clamp((flight.Age - landedAt) / SETTLE_TIME, 0, 1)
			flight.Model:PivotTo(flight.SettleFrom:Lerp(flight.SettleTo, easeOut(alpha)))
			flight.Settled = alpha >= 1
		end

		local fadeStart = DuelConfig.SEVERED_LIMB_LIFETIME - FADE_TIME
		if flight.Age > fadeStart then
			local alpha = math.clamp((flight.Age - fadeStart) / FADE_TIME, 0, 1)
			for part, base in flight.BaseTransparency do
				part.Transparency = base + (1 - base) * alpha
			end
			if alpha >= 1 then
				flight.Model:Destroy()
				table.remove(flights, index)
			end
		end
	end
end

function LimbDebrisController:Init()
	Net.LimbSevered.listen(onLimbSevered)

	DuelStateController.PhaseChanged:Connect(function(phase: string)
		if phase == "Countdown" then
			clearAll()
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return LimbDebrisController
