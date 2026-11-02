--!strict
--[[
	Character joint helpers shared by the server's poses (Dismemberment) and the client's arm aim.

	Joints are found by the parts they link rather than by class or name, so this works with
	classic Motor6D rigs and Avatar Joint Upgrade rigs (AnimationConstraint) alike. A pose is
	written as the joint's original frame (on the parent-part side) times an offset; the original
	is stored on the joint as an attribute the first time it's read, so every machine agrees on it
	even after the server has posed the joint.
]]

local BASE_FRAME_ATTRIBUTE = "RigBaseFrame"

local Rig = {}

local function attachmentPart(attachment: Attachment?): BasePart?
	local parent = attachment and attachment.Parent
	return if parent and parent:IsA("BasePart") then parent else nil
end

-- The two parts a joint or constraint links (Motor6D / Weld, WeldConstraint, attachment-based
-- constraints). Anything else returns nil.
function Rig.GetLinkedParts(instance: Instance): (BasePart?, BasePart?)
	if instance:IsA("JointInstance") then
		return instance.Part0, instance.Part1
	elseif instance:IsA("WeldConstraint") then
		return instance.Part0, instance.Part1
	elseif instance:IsA("Constraint") then
		return attachmentPart(instance.Attachment0), attachmentPart(instance.Attachment1)
	end
	return nil, nil
end

-- The animatable joint (Motor6D or AnimationConstraint) linking `parentName` to `childName`,
-- and the parent part.
function Rig.FindJoint(
	character: Model,
	parentName: string,
	childName: string
): (Instance?, BasePart?)
	local parent = character:FindFirstChild(parentName)
	local child = character:FindFirstChild(childName)
	if not (parent and parent:IsA("BasePart") and child) then
		return nil, nil
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			local part0, part1 = Rig.GetLinkedParts(descendant)
			if (part0 == parent and part1 == child) or (part0 == child and part1 == parent) then
				return descendant, parent
			end
		end
	end
	return nil, nil
end

-- The joint's frame on the parent-part side. Rotating it rotates the child about the joint,
-- whichever of the joint's two ends the parent happens to be.
local function getParentAttachment(joint: Instance, parent: BasePart): Attachment?
	if joint:IsA("AnimationConstraint") then
		local attachment0 = joint.Attachment0
		return if attachment0 and attachment0.Parent == parent
			then attachment0
			else joint.Attachment1
	end
	return nil
end

function Rig.ReadFrame(joint: Instance, parent: BasePart): CFrame?
	if joint:IsA("Motor6D") then
		return if joint.Part0 == parent then joint.C0 else joint.C1
	end
	local attachment = getParentAttachment(joint, parent)
	return attachment and attachment.CFrame
end

function Rig.WriteFrame(joint: Instance, parent: BasePart, frame: CFrame)
	if joint:IsA("Motor6D") then
		if joint.Part0 == parent then
			joint.C0 = frame
		else
			joint.C1 = frame
		end
		return
	end
	local attachment = getParentAttachment(joint, parent)
	if attachment then
		attachment.CFrame = frame
	end
end

-- The joint's unposed frame (see the header).
function Rig.GetBaseFrame(joint: Instance, parent: BasePart): CFrame?
	local stored = joint:GetAttribute(BASE_FRAME_ATTRIBUTE)
	if typeof(stored) == "CFrame" then
		return stored
	end
	local frame = Rig.ReadFrame(joint, parent)
	if frame then
		joint:SetAttribute(BASE_FRAME_ATTRIBUTE, frame)
	end
	return frame
end

-- Drops this frame's animation on the joint, so a posed limb holds still instead of swinging.
function Rig.ClearAnimation(joint: Instance)
	if joint:IsA("Motor6D") or joint:IsA("AnimationConstraint") then
		(joint :: any).Transform = CFrame.identity
	end
end

-- Ball-socket limits (Avatar Joint Upgrade rigs) would fight a pose outside their cone.
function Rig.ReleaseBallSockets(character: Model, partA: BasePart, partB: BasePart)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BallSocketConstraint") then
			local part0, part1 = Rig.GetLinkedParts(descendant)
			if (part0 == partA and part1 == partB) or (part0 == partB and part1 == partA) then
				descendant.Enabled = false
			end
		end
	end
end

return Rig
