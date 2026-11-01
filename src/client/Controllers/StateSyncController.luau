--!strict
--[[
	Applies charm-sync patches from the server to the local copies of SharedAtoms.
	Read shared state anywhere on the client by calling the atom: SharedAtoms.ServerInfo().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharmSync = require(ReplicatedStorage.Shared.Packages["charm-sync"])
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local SharedAtoms = require(ReplicatedStorage.Shared.State.SharedAtoms)

local StateSyncController = {
	Priority = 0,
}

function StateSyncController:Init()
	CharmSync.client.addSignals(SharedAtoms :: any)

	Net.StateSync.listen(function(payloads: any)
		CharmSync.client.patch(payloads)
	end)
end

return StateSyncController
