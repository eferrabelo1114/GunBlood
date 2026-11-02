--!strict
--[[
	Server-controlled practice opponent. MatchmakerService creates a bot when a player has waited
	alone in the queue, spawns it like a character each round, and calls RunRound once the
	round's countdown starts. The bot holsters (occasionally false-starting), waits a human-ish
	reaction time after "DRAW!", then fires with some aim spread through GunService:Fire, so it
	gets no shortcuts past the server's checks.

	local bot = BotService:Create()
	BotService:SpawnAsync(bot):andThen(function(character) ... end)
	BotService:RunRound(bot, opponent)
	BotService:Remove(bot)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Promise = require(ReplicatedStorage.Shared.Packages.promise)
local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Dismemberment = require(script.Parent.Parent.Modules.Dismemberment)
local Duelist = require(script.Parent.Parent.Modules.Duelist)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local GunService = require(script.Parent.GunService)

type Bot = Duelist.Bot

local BotService = {
	Priority = 45,
	Dependencies = { "GunService" },
}

local SKIN = Color3.fromRGB(196, 140, 100)
local SHIRT = Color3.fromRGB(110, 40, 35)
local PANTS = Color3.fromRGB(55, 45, 40)

local rng = Random.new()
-- Each player's last loaded look, so a bot can copy it while that player is mid-respawn.
local appearances: { [Player]: HumanoidDescription } = {}

local function randomIn(range: NumberRange): number
	return rng:NextNumber(range.Min, range.Max)
end

local function getPart(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function isAlive(character: Model?): boolean
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function buildDefaultDescription(): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.LeftArmColor = SKIN
	description.RightArmColor = SKIN
	description.TorsoColor = SHIRT
	description.LeftLegColor = PANTS
	description.RightLegColor = PANTS
	return description
end

local function readAppearance(player: Player): HumanoidDescription?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	return if ok then description else nil
end

-- `lookLike`'s avatar if it can be read (their current character, the last one they loaded, then
-- their saved outfit), otherwise a plain cowboy palette.
local function buildDescription(lookLike: Player?): HumanoidDescription
	if lookLike then
		local current = readAppearance(lookLike)
		if current then
			appearances[lookLike] = current:Clone()
			return current
		end
		local cached = appearances[lookLike]
		if cached then
			return cached:Clone()
		end
		if lookLike.UserId > 0 then
			local ok, description = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(lookLike.UserId)
			end)
			if ok and description then
				return description
			end
		end
	end
	return buildDefaultDescription()
end

local function getMuzzlePosition(character: Model): Vector3?
	local revolver = character:FindFirstChild("Revolver")
	local muzzle = revolver and revolver:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	local head = getPart(character, { DuelConfig.HEAD_PART_NAME })
	return if head then head.Position else nil
end

local function shootAt(bot: Bot, character: Model, target: Model)
	local root = getPart(character, { "HumanoidRootPart" })
	local wantsHeadshot = rng:NextNumber() < ServerConfig.BOT_HEADSHOT_CHANCE
	local aimPart = if wantsHeadshot
		then getPart(target, { DuelConfig.HEAD_PART_NAME })
		else getPart(target, { "UpperTorso", "Torso", "HumanoidRootPart" })
	if root == nil or aimPart == nil then
		return
	end

	local aimPoint = aimPart.Position
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(aimPoint.X, root.Position.Y, aimPoint.Z))

	local upperTorso = getPart(character, { "UpperTorso" })
	if upperTorso and character:GetAttribute(DuelConfig.ARM_DRAWN_ATTRIBUTE) then
		local toTarget = aimPoint - upperTorso.Position
		if toTarget.Magnitude > 0.01 then
			Dismemberment.SetAim(character, upperTorso.CFrame:VectorToObjectSpace(toTarget.Unit))
		end
	end

	local origin = getMuzzlePosition(character)
	if origin == nil then
		return
	end

	local spread = ServerConfig.BOT_AIM_SPREAD
	local aim = CFrame.lookAt(origin, aimPoint)
		* CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)
	GunService:Fire(bot, aim.LookVector)
end

function BotService:Create(): Bot
	return {
		IsBot = true,
		Name = ServerConfig.BOT_NAME,
		Character = nil,
		Active = true,
	}
end

-- Replaces the bot's character with a fresh R15 rig in Workspace, dressed like `lookLike` when
-- given; the caller positions it.
function BotService:SpawnAsync(bot: Bot, lookLike: Player?)
	return Promise.new(function(resolve, reject)
		if bot.Character then
			bot.Character:Destroy()
			bot.Character = nil
		end

		local description = buildDescription(lookLike)
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if not ok then
			ok, result = pcall(function()
				return Players:CreateHumanoidModelFromDescription(
					buildDefaultDescription(),
					Enum.HumanoidRigType.R15
				)
			end)
		end
		if not ok or result == nil then
			reject(result)
			return
		end
		if not bot.Active then
			result:Destroy()
			reject("Bot was removed while spawning")
			return
		end

		local character = result :: Model
		character.Name = bot.Name
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayName = bot.Name
		end
		character.Parent = Workspace

		local root = getPart(character, { "HumanoidRootPart" })
		if root then
			root:SetNetworkOwner(nil)
		end

		bot.Character = character
		resolve(character)
	end)
end

-- Strafes left/right relative to its facing (and sometimes jumps) until `isPlaying` fails.
local function strafe(character: Model, isPlaying: () -> boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = getPart(character, { "HumanoidRootPart" })
	if humanoid == nil or root == nil then
		return
	end

	while GunService:GetPhase() == "Drawn" and isPlaying() do
		local direction = rng:NextInteger(-1, 1)
		humanoid:Move(root.CFrame.RightVector * direction, false)
		if rng:NextNumber() < ServerConfig.BOT_JUMP_CHANCE then
			humanoid.Jump = true
		end
		task.wait(randomIn(ServerConfig.BOT_STRAFE_INTERVAL))
	end
	if humanoid.Parent then
		humanoid:Move(Vector3.zero, false)
	end
end

-- Plays one round. Stops on its own once the round ends or the bot is respawned/removed.
function BotService:RunRound(bot: Bot, opponent: Duelist.Duelist)
	local character = bot.Character
	if character == nil then
		return
	end

	local function stillPlaying(): boolean
		return bot.Active and bot.Character == character and isAlive(character)
	end

	task.spawn(function()
		task.wait(rng:NextNumber(0.1, 0.4))
		if not stillPlaying() then
			return
		end
		GunService:SetHolstered(bot, true)
		if ServerConfig.BOT_PASSIVE then
			return
		end

		if rng:NextNumber() < ServerConfig.BOT_FALSE_START_CHANCE then
			task.wait(rng:NextNumber(0.3, DuelConfig.COUNTDOWN - 0.5))
			GunService:SetHolstered(bot, false)
		end

		while GunService:GetPhase() == "Countdown" and stillPlaying() do
			task.wait()
		end
		if GunService:GetPhase() ~= "Drawn" then
			return
		end

		task.spawn(strafe, character, stillPlaying)
		task.wait(randomIn(ServerConfig.BOT_REACTION_TIME))
		while GunService:GetPhase() == "Drawn" and stillPlaying() do
			local target = Duelist.GetCharacter(opponent)
			if target == nil or not isAlive(target) then
				return
			end
			-- Lost its shooting arm: nothing left to do but keep strafing.
			if character:GetAttribute(DuelConfig.DISARMED_ATTRIBUTE) then
				return
			end
			shootAt(bot, character, target)
			task.wait(randomIn(ServerConfig.BOT_FIRE_INTERVAL))
		end
	end)
end

function BotService:Init()
	local function track(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			local description = readAppearance(player)
			if description then
				appearances[player] = description
			end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		appearances[player] = nil
	end)
end

function BotService:Remove(bot: Bot)
	bot.Active = false
	if bot.Character then
		bot.Character:Destroy()
		bot.Character = nil
	end
end

return BotService
