--!strict
--[[
	Limb loss and the poses that go with it. No blood: severed limbs just fly off and fall.

	Dismemberment.Sever(character, hitPart, push) -- limb ("RightArm" | ...) or nil
	Dismemberment.ApplyCrawl(character)           -- crawl speed, no jumping, body can lie on the ground
	Dismemberment.RefreshPose(character)          -- arm / prone pose from character attributes
	Dismemberment.SetAim(character, direction)    -- point the drawn arm (UpperTorso space)

	Every segment can be shot off: hitting a hand takes the hand, a lower arm takes the lower arm and
	hand, an upper arm takes the whole arm (legs likewise). The character's rig is never cut: the
	severed segments, and anything welded to them (hats, a revolver in hand), are hidden on the
	character and LimbSevered tells every client to animate a non-colliding copy flying off
	(LimbDebrisController). Client-side animation keeps it smooth and keeps the character stable.

	Poses go through the shared Rig helpers (any rig type, never stacking) and the drawn arm points
	along the character's AimDirection attribute (see ArmAim and ArmAimController).
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local ArmAim = require(ReplicatedStorage.Shared.Modules.ArmAim)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Rig = require(ReplicatedStorage.Shared.Modules.Rig)

-- "RightArm" | "LeftArm" | "RightLeg" | "LeftLeg" (plain string: the type solver widens the
-- literal union after nil checks).
export type Limb = string

-- Each limb's segments from the body outwards.
local R15_LIMBS: { [Limb]: { string } } = {
	RightArm = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LeftArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RightLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
	LeftLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
}

local R6_LIMBS: { [Limb]: { string } } = {
	RightArm = { "Right Arm" },
	LeftArm = { "Left Arm" },
	RightLeg = { "Right Leg" },
	LeftLeg = { "Left Leg" },
}

local CORE_PARTS = {
	HumanoidRootPart = true,
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	Torso = true,
}

local SEVERED_ATTRIBUTE = "Severed"
local CRAWL_COLLISION_GROUP = "Crawling"

-- Flung limbs: speed along the shot, upward pop, and random spin (radians per second).
local FLING_SPEED = 18
local FLING_UP = 20
local FLING_SPIN = 12

-- Prone: torso tipped face down, head forward, dropped from hip height to the ground.
local PRONE_ANGLE = math.rad(-85)
local TORSO_HALF_THICKNESS = 0.5

local Dismemberment = {}

local rng = Random.new()

local function isR15(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
end

local function getSpecs(character: Model): { [Limb]: { string } }
	return if isR15(character) then R15_LIMBS else R6_LIMBS
end

-- The limb `part` belongs to and its position along that limb, or nil for non-limb parts.
local function findSegment(character: Model, part: BasePart): (Limb?, { string }?, number?)
	if part.Parent ~= character then
		return nil, nil, nil
	end
	for limb, chain in getSpecs(character) do
		local index = table.find(chain, part.Name)
		if index then
			return limb, chain, index
		end
	end
	return nil, nil, nil
end

local function isBodyPart(character: Model, part: BasePart): boolean
	return part.Parent == character
		and (CORE_PARTS[part.Name] or findSegment(character, part) ~= nil)
end

local function isRigidWeld(instance: Instance): boolean
	return instance:IsA("Weld") or instance:IsA("WeldConstraint") or instance:IsA("RigidConstraint")
end

-- The character's direct child that `instance` lives under (an Accessory, the revolver, ...).
local function topLevelChild(character: Model, instance: Instance): Instance?
	local current: Instance? = instance
	while current and current.Parent ~= character do
		current = current.Parent
	end
	return current
end

local function hidePart(part: BasePart)
	part:SetAttribute(SEVERED_ATTRIBUTE, true)
	part:SetAttribute(DuelConfig.SEVERED_TRANSPARENCY_ATTRIBUTE, part.Transparency)
	part.Transparency = 1
	part.CanQuery = false
	part.CanCollide = false
	part.CanTouch = false
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("Decal") then
			descendant.Transparency = 1
		end
	end
end

--[[
	Sets the joint between `parentName` and `childName` to its original frame times `offset`.
	`offset` may instead be a function of that original frame (in the parent part's space), for
	poses that depend on where the joint sits.
]]
local function pose(
	character: Model,
	parentName: string,
	childName: string,
	getOffset: CFrame | (base: CFrame) -> CFrame
)
	local joint, parent = Rig.FindJoint(character, parentName, childName)
	if joint == nil or parent == nil then
		return
	end
	local base = Rig.GetBaseFrame(joint, parent)
	if not base then
		return
	end
	local offset = if typeof(getOffset) == "function" then getOffset(base) else getOffset
	local child = character:FindFirstChild(childName)
	if child and child:IsA("BasePart") and offset ~= CFrame.identity then
		Rig.ReleaseBallSockets(character, parent, child)
	end
	Rig.WriteFrame(joint, parent, base * offset)
end

local function ensureCrawlCollisionGroup()
	if PhysicsService:IsCollisionGroupRegistered(CRAWL_COLLISION_GROUP) then
		return
	end
	PhysicsService:RegisterCollisionGroup(CRAWL_COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(CRAWL_COLLISION_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(CRAWL_COLLISION_GROUP, CRAWL_COLLISION_GROUP, false)
end

--[[
	Shoots off `hitPart` and every segment below it on the same limb: hides them (and anything
	welded to them) and tells every client to fling a copy along `push`. Returns the limb it
	belonged to, or nil if `hitPart` isn't a limb segment that's still attached.
]]
function Dismemberment.Sever(character: Model, hitPart: BasePart, push: Vector3?): Limb?
	local limb, chain, index = findSegment(character, hitPart)
	if limb == nil or chain == nil or index == nil then
		return nil
	end

	local severed: { [BasePart]: true } = {}
	local parts: { BasePart } = {}
	for i = index, #chain do
		local segment = character:FindFirstChild(chain[i])
		if segment and segment:IsA("BasePart") and not segment:GetAttribute(SEVERED_ATTRIBUTE) then
			severed[segment] = true
			table.insert(parts, segment)
		end
	end
	if #parts == 0 then
		return nil
	end

	-- Hats, a revolver in hand, etc. welded to a severed segment go with it.
	for _, descendant in character:GetDescendants() do
		if isRigidWeld(descendant) then
			local part0, part1 = Rig.GetLinkedParts(descendant)
			local other = if part0 and severed[part0]
				then part1
				elseif part1 and severed[part1] then part0
				else nil
			if other and not severed[other] and not isBodyPart(character, other) then
				local carried = topLevelChild(character, other)
				if carried then
					local carriedParts: { Instance } = carried:GetDescendants()
					table.insert(carriedParts, carried)
					for _, instance in carriedParts do
						if instance:IsA("BasePart") and not severed[instance] then
							severed[instance] = true
							table.insert(parts, instance)
						end
					end
				end
			end
		end
	end

	-- Each hidden part keeps its real transparency in an attribute for the clients' copies.
	for _, part in parts do
		hidePart(part)
	end

	local direction = if push and push.Magnitude > 0 then push.Unit else Vector3.zero
	Net.LimbSevered.sendToAll({
		parts = parts :: { any },
		velocity = direction * FLING_SPEED + Vector3.new(0, FLING_UP, 0),
		spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
			* FLING_SPIN,
	})
	return limb
end

--[[
	Crawl movement. The body stops colliding with the world (the Humanoid forces the torso and
	head collidable, so this uses a collision group) and goes massless, letting the prone pose lie
	on the ground without fighting it; the root part keeps colliding so walls still block.
]]
function Dismemberment.ApplyCrawl(character: Model)
	ensureCrawlCollisionGroup()
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == "HumanoidRootPart" and descendant.Parent == character then
				descendant.CanCollide = true
			else
				descendant.CollisionGroup = CRAWL_COLLISION_GROUP
				descendant.Massless = true
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.WalkSpeed = DuelConfig.CRAWL_WALK_SPEED
		humanoid.JumpPower = 0
		humanoid.HipHeight = DuelConfig.CRAWL_HIP_HEIGHT
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
end

-- Applies the right-arm and prone poses implied by the ArmDrawn / Crawling attributes.
function Dismemberment.RefreshPose(character: Model)
	if not isR15(character) then
		return
	end

	local crawling = character:GetAttribute(DuelConfig.CRAWLING_ATTRIBUTE) == true
	local drawn = character:GetAttribute(DuelConfig.ARM_DRAWN_ATTRIBUTE) == true

	if crawling then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local rootHalfHeight = if rootPart and rootPart:IsA("BasePart")
			then rootPart.Size.Y / 2
			else 1
		local thickness = TORSO_HALF_THICKNESS
		for _, name in { "UpperTorso", "LowerTorso" } do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				thickness = math.max(thickness, part.Size.Z / 2)
			end
		end
		pose(character, "HumanoidRootPart", "LowerTorso", function(base: CFrame): CFrame
			-- The hip pivot sits base.Y from the root part's centre (near its bottom on R15),
			-- so lower it to one torso half-thickness above the ground, then tip forward.
			local pivotHeight = DuelConfig.CRAWL_HIP_HEIGHT + rootHalfHeight + base.Position.Y
			local drop = pivotHeight - thickness
			return CFrame.new(0, -drop, 0) * CFrame.Angles(PRONE_ANGLE, 0, 0)
		end)
	else
		pose(character, "HumanoidRootPart", "LowerTorso", CFrame.identity)
	end

	if drawn then
		-- Clients animate the arm smoothly themselves; this keeps the server's muzzle (the shot
		-- origin) where they show it.
		local aim = character:GetAttribute(DuelConfig.AIM_DIRECTION_ATTRIBUTE)
		local direction = if typeof(aim) == "Vector3" then aim else ArmAim.Center(crawling)
		pose(character, "UpperTorso", "RightUpperArm", ArmAim.ShoulderRotation(direction, crawling))
	else
		pose(character, "UpperTorso", "RightUpperArm", CFrame.identity)
	end
end

-- Records where `character`'s drawn arm points (UpperTorso space) and re-poses it.
function Dismemberment.SetAim(character: Model, direction: Vector3)
	local crawling = character:GetAttribute(DuelConfig.CRAWLING_ATTRIBUTE) == true
	character:SetAttribute(DuelConfig.AIM_DIRECTION_ATTRIBUTE, ArmAim.Clamp(direction, crawling))
	Dismemberment.RefreshPose(character)
end

return Dismemberment
