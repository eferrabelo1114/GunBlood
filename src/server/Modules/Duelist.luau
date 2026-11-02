--!strict
--[[
	A duelist is either a real Player or a server-controlled practice bot (see BotService).
	These helpers hide the difference from GunService and MatchmakerService.
]]

local Players = game:GetService("Players")

export type Bot = {
	IsBot: true,
	Name: string,
	Character: Model?,
	-- False once the bot has been removed; mirrors a Player leaving.
	Active: boolean,
}

export type Duelist = Player | Bot

local Duelist = {}

function Duelist.AsPlayer(duelist: Duelist): Player?
	if typeof(duelist) == "Instance" then
		return duelist :: Player
	end
	return nil
end

function Duelist.AsBot(duelist: Duelist): Bot?
	if type(duelist) == "table" then
		return duelist :: Bot
	end
	return nil
end

function Duelist.GetCharacter(duelist: Duelist): Model?
	local player = Duelist.AsPlayer(duelist)
	if player then
		return player.Character
	end
	return (duelist :: Bot).Character
end

function Duelist.GetName(duelist: Duelist): string
	local player = Duelist.AsPlayer(duelist)
	return if player then player.Name else (duelist :: Bot).Name
end

function Duelist.IsPresent(duelist: Duelist): boolean
	local player = Duelist.AsPlayer(duelist)
	if player then
		return player.Parent == Players
	end
	return (duelist :: Bot).Active
end

-- What clients receive to identify a duelist: the Player, or the bot's character model.
function Duelist.GetInstance(duelist: Duelist): Instance?
	return Duelist.AsPlayer(duelist) or Duelist.GetCharacter(duelist)
end

function Duelist.GetAliveHumanoid(duelist: Duelist): Humanoid?
	local character = Duelist.GetCharacter(duelist)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

return Duelist
