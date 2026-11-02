--!strict
--[[
	Where the drawn right arm points. An aim direction is a unit vector in the UpperTorso's space
	(from the shoulder); the arm is held straight along it, limited to a cone around the arm's
	natural reach so it never swings behind the back or straight out sideways.

	Standing, the cone is centred on the torso's front. Crawling (torso face down), it's centred
	on the torso's up axis, which then points forward along the ground.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)

local STANDING_CENTER = Vector3.new(0, 0, -1)
local CRAWLING_CENTER = Vector3.new(0, 1, 0)
-- Shoulder rotations taking the hanging arm (pointing down the arm's -Y) onto each centre.
local STANDING_REST = CFrame.Angles(math.rad(90), 0, 0)
local CRAWLING_REST = CFrame.Angles(math.pi, 0, 0)

local ArmAim = {}

function ArmAim.Center(crawling: boolean): Vector3
	return if crawling then CRAWLING_CENTER else STANDING_CENTER
end

-- Keeps `direction` within ARM_AIM_MAX_ANGLE of the reach centre.
function ArmAim.Clamp(direction: Vector3, crawling: boolean): Vector3
	local center = ArmAim.Center(crawling)
	if direction.Magnitude < 1e-4 then
		return center
	end
	local unit = direction.Unit
	local angle = math.acos(math.clamp(center:Dot(unit), -1, 1))
	if angle <= DuelConfig.ARM_AIM_MAX_ANGLE then
		return unit
	end
	local axis = center:Cross(unit)
	if axis.Magnitude < 1e-4 then
		return center
	end
	return CFrame.fromAxisAngle(axis.Unit, DuelConfig.ARM_AIM_MAX_ANGLE) * center
end

-- The aim direction toward `worldTarget` from a shoulder at `shoulderWorld`.
function ArmAim.DirectionTo(
	upperTorso: BasePart,
	shoulderWorld: Vector3,
	worldTarget: Vector3,
	crawling: boolean
): Vector3
	local offset = worldTarget - shoulderWorld
	if offset.Magnitude < 1e-3 then
		return ArmAim.Center(crawling)
	end
	return ArmAim.Clamp(upperTorso.CFrame:VectorToObjectSpace(offset.Unit), crawling)
end

-- The shoulder rotation (applied to its unposed frame) that holds the arm straight along
-- `direction`, rolled as little as possible from the rest pose so the revolver stays upright.
function ArmAim.ShoulderRotation(direction: Vector3, crawling: boolean): CFrame
	local center = ArmAim.Center(crawling)
	local rest = if crawling then CRAWLING_REST else STANDING_REST
	local target = ArmAim.Clamp(direction, crawling)
	local axis = center:Cross(target)
	if axis.Magnitude < 1e-4 then
		return rest
	end
	local angle = math.acos(math.clamp(center:Dot(target), -1, 1))
	return CFrame.fromAxisAngle(axis.Unit, angle) * rest
end

return ArmAim
