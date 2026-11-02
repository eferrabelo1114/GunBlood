--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Shared.Packages.promise)
local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local Constants = require(ReplicatedStorage.Shared.Constants)
local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)

local CharacterService = {
	Priority = 30,
}

local loadAttempts: { [Player]: number } = {}
local diedConnections: { [Player]: RBXScriptConnection } = {}

local function disconnectDied(player: Player)
	local connection = diedConnections[player]
	if connection then
		connection:Disconnect()
		diedConnections[player] = nil
	end
end

local function clearPlayer(player: Player)
	disconnectDied(player)
	loadAttempts[player] = nil
end

local function isInDuel(player: Player): boolean
	return player:GetAttribute(DuelConfig.IN_DUEL_ATTRIBUTE) == true
end

local function watchDeath(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	disconnectDied(player)
	diedConnections[player] = humanoid.Died:Connect(function()
		-- MatchmakerService owns respawns while a duel is running.
		if isInDuel(player) then
			return
		end
		task.wait(Constants.RESPAWN_DELAY)
		if player.Parent == Players and not isInDuel(player) and player.Character == character then
			GameEvents.PlayerReadyToSpawn:Fire(player)
		end
	end)
end

--[[
	Loads a fresh character at the lobby SpawnLocation. Resolves with the character, rejects if
	LoadCharacterAsync fails. Does not retry; callers decide how to handle failure.
]]
function CharacterService:SpawnAsync(player: Player)
	return Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			reject(err)
			return
		end

		local character = player.Character
		if character == nil then
			reject("Character missing after LoadCharacterAsync")
			return
		end

		print(`[Skoobi/Server] Character spawned for {player.Name}`)
		watchDeath(player, character)
		resolve(character)
	end)
end

local function spawnCharacter(player: Player)
	local attempts = loadAttempts[player] or 0
	if attempts >= Constants.CHARACTER_LOAD_MAX_RETRIES then
		warn(
			`[CharacterService] Gave up loading character for {player.Name} after {attempts} attempts`
		)
		return
	end

	loadAttempts[player] = attempts + 1

	CharacterService:SpawnAsync(player)
		:andThen(function()
			loadAttempts[player] = 0
		end)
		:catch(function(err)
			warn(`[CharacterService] Failed to load character for {player.Name}: {err}`)
			warn(
				`[CharacterService] Retrying ({loadAttempts[player]}/{Constants.CHARACTER_LOAD_MAX_RETRIES})...`
			)
			task.wait(Constants.CHARACTER_LOAD_RETRY_DELAY)
			if player.Parent == Players then
				GameEvents.PlayerReadyToSpawn:Fire(player)
			end
		end)
end

function CharacterService:Init()
	GameEvents.PlayerReadyToSpawn:Connect(spawnCharacter)

	Players.PlayerRemoving:Connect(function(player)
		clearPlayer(player)
	end)
end

return CharacterService
