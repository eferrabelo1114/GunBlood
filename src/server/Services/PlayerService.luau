--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local NetGuard = require(script.Parent.Parent.Modules.NetGuard)
local ServerState = require(script.Parent.Parent.ServerState)

local PlayerService = {
	Priority = 10,
}

local initialized: { [Player]: true } = {}

function PlayerService:Init()
	NetGuard.Listen(
		Net.ClientReady,
		"ClientReady",
		{ MaxPerWindow = 2, Window = 5 },
		function(_isReady, player)
			if initialized[player] then
				return
			end
			initialized[player] = true
			print(`[Skoobi/Server] ClientReady from {player.Name}`)

			ServerState:AwaitReady()
			if player.Parent ~= Players then
				return
			end

			print(`[Skoobi/Server] Initializing player {player.Name}`)
			GameEvents.PlayerInitialized:Fire(player)
		end
	)

	Players.PlayerRemoving:Connect(function(player)
		initialized[player] = nil
	end)
end

return PlayerService
