--!strict
--[[
	Replicates SharedAtoms to clients with charm-sync. Each client gets the full state once it has
	initialized, then only the changed parts (delta patches), at most once per frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharmSync = require(ReplicatedStorage.Shared.Packages["charm-sync"])
local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local SharedAtoms = require(ReplicatedStorage.Shared.State.SharedAtoms)

local StateSyncService = {
	Priority = 5,
}

function StateSyncService:Init()
	SharedAtoms.ServerInfo({
		PlaceVersion = game.PlaceVersion,
		StartTime = os.time(),
		ShuttingDown = false,
	})

	CharmSync.server.connect(function(player: Player, payloads)
		if player.Parent == Players then
			Net.StateSync.sendTo(payloads, player)
		end
	end)

	GameEvents.PlayerInitialized:Connect(function(player)
		CharmSync.server.addSignalsToClient(player, SharedAtoms :: any)
	end)

	Players.PlayerRemoving:Connect(function(player)
		CharmSync.server.removeClient(player)
	end)
end

return StateSyncService
