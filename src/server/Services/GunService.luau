--!strict
--[[
	Server authority for the duel revolver: holster / false-start tracking, validated shots,
	damage and ammo. MatchmakerService drives the phases:

	GunService:PrepareRound(duelistA, duelistB)  -- countdown starts: holster revolvers, reload
	GunService:OpenFire()                        -- "DRAW!": apply false-start penalties
	GunService:EndRound()                        -- stop accepting shots
	GunService:Clear()                           -- match over: forget duelists, remove revolvers

	Players reach SetHolstered / Fire through NetGuard-validated packets; bots call them directly,
	so both go through the same checks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Hitscan = require(ReplicatedStorage.Shared.Modules.Hitscan)
local Dismemberment = require(script.Parent.Parent.Modules.Dismemberment)
local Duelist = require(script.Parent.Parent.Modules.Duelist)
local NetGuard = require(script.Parent.Parent.Modules.NetGuard)

type Duelist = Duelist.Duelist
export type Phase = "Idle" | "Countdown" | "Drawn"

type GunState = {
	Opponent: Duelist,
	Holstered: boolean,
	FalseStart: boolean,
	LockedUntil: number,
	LastShot: number,
	Ammo: number,
	Reloading: boolean,
	ReloadToken: number,
	Revolver: Part?,
	-- Lost the shooting arm this round; can't draw or fire.
	Disarmed: boolean,
}

local GunService = {
	Priority = 40,
}

-- The revolver's -Z (barrel) is rotated onto the parent part's -Y.
local BARREL_DOWN = CFrame.Angles(math.rad(-90), 0, 0)
local HOLSTER_OFFSET_R15 = CFrame.new(1.05, -0.3, 0) * BARREL_DOWN
local HOLSTER_OFFSET_R6 = CFrame.new(1.1, -0.9, 0) * BARREL_DOWN
local HAND_OFFSET_R15 = CFrame.new(0, -0.55, 0) * BARREL_DOWN
local HAND_OFFSET_R6 = CFrame.new(0, -1.4, 0) * BARREL_DOWN

local phase: Phase = "Idle"
local roundId = 0
local states: { [Duelist]: GunState } = {}

-- Reads the current phase in deferred callbacks, where Luau would keep a stale narrowed type.
local function getPhase(): Phase
	return phase
end

local function isR15(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
end

local function getAliveHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function sendAmmo(duelist: Duelist, state: GunState)
	local player = Duelist.AsPlayer(duelist)
	if player then
		Net.AmmoChanged.sendTo({ ammo = state.Ammo, reloading = state.Reloading }, player)
	end
end

local function startReload(duelist: Duelist, state: GunState)
	state.Reloading = true
	state.ReloadToken += 1
	local token = state.ReloadToken
	sendAmmo(duelist, state)

	task.delay(DuelConfig.RELOAD_TIME, function()
		if states[duelist] ~= state or state.ReloadToken ~= token then
			return
		end
		state.Ammo = DuelConfig.MAX_AMMO
		state.Reloading = false
		sendAmmo(duelist, state)
	end)
end

local function attachRevolver(state: GunState, character: Model, inHand: boolean)
	local revolver = state.Revolver
	if revolver == nil or revolver.Parent ~= character then
		return
	end

	local r15 = isR15(character)
	local anchorName = if inHand
		then (if r15 then "RightHand" else "Right Arm")
		else (if r15 then "LowerTorso" else "Torso")
	local anchor = character:FindFirstChild(anchorName)
	local grip = revolver:FindFirstChild("Grip")
	if not (anchor and anchor:IsA("BasePart") and grip and grip:IsA("Weld")) then
		return
	end

	grip.Part0 = anchor
	grip.C0 = if inHand
		then (if r15 then HAND_OFFSET_R15 else HAND_OFFSET_R6)
		else (if r15 then HOLSTER_OFFSET_R15 else HOLSTER_OFFSET_R6)
end

local function createRevolver(state: GunState, character: Model)
	local revolver = Instance.new("Part")
	revolver.Name = "Revolver"
	revolver.Size = Vector3.new(0.3, 0.45, 1.5)
	revolver.Material = Enum.Material.Metal
	revolver.Color = Color3.fromRGB(45, 45, 50)
	revolver.CanCollide = false
	revolver.CanQuery = false
	revolver.CanTouch = false
	revolver.Massless = true

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.1, -0.75)
	muzzle.Parent = revolver

	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part1 = revolver
	grip.Parent = revolver

	revolver.Parent = character
	state.Revolver = revolver
	attachRevolver(state, character, false)
end

local function drawRevolver(duelist: Duelist, state: GunState)
	local character = Duelist.GetCharacter(duelist)
	if character == nil or state.Disarmed then
		return
	end
	attachRevolver(state, character, true)
	character:SetAttribute(DuelConfig.ARM_DRAWN_ATTRIBUTE, true)
	Dismemberment.RefreshPose(character)
end

-- Shoots off the limb segment a non-lethal shot landed on: any piece of the right arm takes
-- the revolver hand with it, any piece of a leg drops the victim into a crawl.
local function severLimb(victim: Duelist, character: Model, part: BasePart, direction: Vector3)
	local limb = Dismemberment.Sever(character, part, direction)
	if limb == nil then
		return
	end

	if limb == "RightArm" then
		character:SetAttribute(DuelConfig.DISARMED_ATTRIBUTE, true)
		local state = states[victim]
		if state then
			state.Disarmed = true
		end
	elseif limb == "RightLeg" or limb == "LeftLeg" then
		if getAliveHumanoid(character) then
			character:SetAttribute(DuelConfig.CRAWLING_ATTRIBUTE, true)
			Dismemberment.ApplyCrawl(character)
			Dismemberment.RefreshPose(character)
		end
	end
end

local function getMuzzlePosition(character: Model, state: GunState): Vector3?
	local revolver = state.Revolver
	if revolver and revolver.Parent == character then
		local muzzle = revolver:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldPosition
		end
	end
	local head = character:FindFirstChild(DuelConfig.HEAD_PART_NAME)
	return if head and head:IsA("BasePart") then head.Position else nil
end

-- Accessory handles (hats, hair) count as the body part they're attached to.
local function resolveBodyPart(hit: BasePart): BasePart
	local accessory = hit:FindFirstAncestorOfClass("Accessory")
	if accessory == nil then
		return hit
	end
	local handle = accessory:FindFirstChild("Handle")
	local joint = handle and handle:FindFirstChild("AccessoryWeld")
	if joint and joint:IsA("JointInstance") and joint.Part1 then
		return joint.Part1
	elseif joint and joint:IsA("RigidConstraint") then
		local attachment = joint.Attachment1
		local parent = attachment and attachment.Parent
		if parent and parent:IsA("BasePart") then
			return parent
		end
	end
	return hit
end

function GunService:GetPhase(): Phase
	return phase
end

function GunService:SetHolstered(duelist: Duelist, holding: boolean)
	local state = states[duelist]
	if state == nil or phase ~= "Countdown" then
		return
	end
	if state.Holstered and not holding then
		state.FalseStart = true
	end
	state.Holstered = holding
end

--[[
	Fires the duelist's revolver (hitscan) along `direction` if every server-side check passes.
	`claimedOrigin` is the muzzle as the shooter's client shows it; it's used when it's near the
	shooter, otherwise the server's own muzzle position is.
]]
function GunService:Fire(duelist: Duelist, direction: Vector3, claimedOrigin: Vector3?)
	local state = states[duelist]
	if state == nil or state.Disarmed then
		return
	end

	if phase == "Countdown" then
		state.FalseStart = true
		return
	elseif phase ~= "Drawn" then
		return
	end

	local character = Duelist.GetCharacter(duelist)
	if character == nil or getAliveHumanoid(character) == nil then
		return
	end

	local now = os.clock()
	if now < state.LockedUntil or now - state.LastShot < DuelConfig.FIRE_COOLDOWN then
		return
	end
	if state.Reloading or state.Ammo <= 0 then
		return
	end

	local serverOrigin = getMuzzlePosition(character, state)
	if serverOrigin == nil then
		return
	end
	local origin = serverOrigin
	local head = character:FindFirstChild(DuelConfig.HEAD_PART_NAME)
	if
		claimedOrigin
		and head
		and head:IsA("BasePart")
		and (claimedOrigin - head.Position).Magnitude <= DuelConfig.MAX_MUZZLE_OFFSET
	then
		origin = claimedOrigin
	end

	state.Ammo -= 1
	state.LastShot = now
	sendAmmo(duelist, state)

	local ray = direction.Unit * DuelConfig.MAX_RANGE
	local result = Hitscan.Cast(origin, ray, { character })
	local hitPosition = if result then result.Position else origin + ray
	local hit = false
	local headshot = false

	local opponent = state.Opponent
	local opponentCharacter = Duelist.GetCharacter(opponent)
	if result and opponentCharacter and result.Instance:IsDescendantOf(opponentCharacter) then
		local humanoid = getAliveHumanoid(opponentCharacter)
		if humanoid then
			hit = true
			local bodyPart = resolveBodyPart(result.Instance)
			headshot = bodyPart.Name == DuelConfig.HEAD_PART_NAME
			humanoid:TakeDamage(
				if headshot then DuelConfig.HEADSHOT_DAMAGE else DuelConfig.BODY_DAMAGE
			)
			if humanoid.Health > 0 then
				severLimb(opponent, opponentCharacter, bodyPart, direction)
			end
		end
	end

	local recipients: { Player } = {}
	for _, participant in { duelist, opponent } do
		local player = Duelist.AsPlayer(participant)
		if player then
			table.insert(recipients, player)
		end
	end
	Net.ShotFired.sendToList({
		shooter = Duelist.GetInstance(duelist),
		origin = origin,
		hitPosition = hitPosition,
		hit = hit,
		headshot = headshot,
	}, recipients)

	if state.Ammo <= 0 then
		startReload(duelist, state)
	end
end

function GunService:PrepareRound(duelistA: Duelist, duelistB: Duelist)
	roundId += 1
	phase = "Countdown"

	for _, pair in { { duelistA, duelistB }, { duelistB, duelistA } } do
		local duelist, opponent = pair[1], pair[2]
		local previous = states[duelist]
		if previous and previous.Revolver then
			previous.Revolver:Destroy()
		end

		local state: GunState = {
			Opponent = opponent,
			Holstered = false,
			FalseStart = false,
			LockedUntil = math.huge,
			LastShot = 0,
			Ammo = if previous then previous.Ammo else DuelConfig.MAX_AMMO,
			Reloading = false,
			ReloadToken = 0,
			Revolver = nil,
			Disarmed = false,
		}
		states[duelist] = state

		local character = Duelist.GetCharacter(duelist)
		if character then
			createRevolver(state, character)
		end
		-- Every round starts with a full cylinder; the reload plays during the countdown.
		startReload(duelist, state)
	end
end

function GunService:OpenFire()
	if phase ~= "Countdown" then
		return
	end
	phase = "Drawn"

	local now = os.clock()
	local currentRound = roundId
	for duelist, state in states do
		local penalized = state.FalseStart or not state.Holstered
		local lock = if penalized then DuelConfig.FALSE_START_LOCK else 0
		state.LockedUntil = now + lock
		local player = Duelist.AsPlayer(duelist)
		if player then
			Net.DrawSignal.sendTo({ penalized = penalized, lockSeconds = lock }, player)
		end

		if penalized then
			task.delay(lock, function()
				if
					roundId == currentRound
					and getPhase() == "Drawn"
					and states[duelist] == state
				then
					drawRevolver(duelist, state)
				end
			end)
		else
			drawRevolver(duelist, state)
		end
	end
end

function GunService:EndRound()
	phase = "Idle"
end

function GunService:Clear()
	roundId += 1
	phase = "Idle"
	for _, state in states do
		if state.Revolver then
			state.Revolver:Destroy()
		end
	end
	table.clear(states)
end

function GunService:Init()
	Hitscan.Register()

	NetGuard.Listen(Net.HolsterState, "HolsterState", {
		MaxPerWindow = 20,
		Window = 1,
		Validate = function(value)
			return type(value) == "boolean"
		end,
	}, function(holding: boolean, player)
		self:SetHolstered(player, holding)
	end)

	NetGuard.Listen(Net.FireShot, "FireShot", {
		MaxPerWindow = 10,
		Window = 1,
		Validate = function(value)
			if
				type(value) ~= "table"
				or typeof(value.direction) ~= "Vector3"
				or typeof(value.origin) ~= "Vector3"
			then
				return false
			end
			local magnitude = value.direction.Magnitude
			return magnitude > 0.9 and magnitude < 1.1 and value.origin.Magnitude < 1e5
		end,
	}, function(value, player)
		self:Fire(player, value.direction, value.origin)
	end)

	NetGuard.Listen(Net.AimUpdate, "AimUpdate", {
		MaxPerWindow = DuelConfig.AIM_SEND_RATE * 2,
		Window = 1,
		Validate = function(value)
			if type(value) ~= "table" or typeof(value.direction) ~= "Vector3" then
				return false
			end
			local magnitude = value.direction.Magnitude
			return magnitude > 0.9 and magnitude < 1.1
		end,
	}, function(value, player)
		local state = states[player]
		local character = player.Character
		if state == nil or state.Disarmed or phase ~= "Drawn" or character == nil then
			return
		end
		if character:GetAttribute(DuelConfig.ARM_DRAWN_ATTRIBUTE) then
			Dismemberment.SetAim(character, value.direction)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return GunService
