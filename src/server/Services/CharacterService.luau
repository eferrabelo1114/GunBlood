--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Shared.Packages.promise)
local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local Constants = require(ReplicatedStorage.Shared.Constants)

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

local function spawnCharacter(player: Player)
	local attempts = loadAttempts[player] or 0
	if attempts >= Constants.CHARACTER_LOAD_MAX_RETRIES then
		warn(
			`[CharacterService] Gave up loading character for {player.Name} after {attempts} attempts`
		)
		return
	end

	loadAttempts[player] = attempts + 1

	Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if ok then
			resolve()
		else
			reject(err)
		end
	end)
		:andThen(function()
			loadAttempts[player] = 0
			print(`[Skoobi/Server] Character spawned for {player.Name}`)

			local character = player.Character
			if not character then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end

			disconnectDied(player)
			diedConnections[player] = humanoid.Died:Connect(function()
				task.wait(Constants.RESPAWN_DELAY)
				if player.Parent == Players then
					GameEvents.PlayerReadyToSpawn:Fire(player)
				end
			end)
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
