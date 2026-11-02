--!strict
--[[
	The one set of raycast rules every shot and aim ray uses, so what the crosshair is on, where
	the arm points, the shooter's tracer and the server's hit check all agree.

	- Ignores every character's HumanoidRootPart: it's an invisible box that, on a crawler, stands
	  upright above the body and would soak up shots meant for it.
	- Ignores the invisible arena walls and the clients' flying limb copies.
	- Casts in its own collision group, which collides with everything. Crawling bodies are in a
	  group that doesn't collide with the world, so a Default-group ray would pass straight
	  through them.

	Hitscan.Register()                       -- server, once: creates the collision group
	Hitscan.Cast(origin, vector, exclude)    -- RaycastResult?
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)

local COLLISION_GROUP = "Hitscan"

local Hitscan = {}

function Hitscan.Register()
	if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end
end

local function isRegistered(): boolean
	local ok, registered = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP)
	end)
	return ok and registered == true
end

function Hitscan.Params(exclude: { Instance }): RaycastParams
	local excluded = table.clone(exclude)
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			local root = child:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(excluded, root)
			end
		end
	end
	local arena = Workspace:FindFirstChild("Arena")
	local bounds = arena and arena:FindFirstChild(DuelConfig.ARENA_BOUNDS_NAME)
	if bounds then
		table.insert(excluded, bounds)
	end
	local debris = Workspace:FindFirstChild(DuelConfig.LIMB_DEBRIS_FOLDER_NAME)
	if debris then
		table.insert(excluded, debris)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	if isRegistered() then
		params.CollisionGroup = COLLISION_GROUP
	end
	return params
end

function Hitscan.Cast(origin: Vector3, vector: Vector3, exclude: { Instance }): RaycastResult?
	return Workspace:Raycast(origin, vector, Hitscan.Params(exclude))
end

return Hitscan
