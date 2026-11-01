--!strict
--[[
	Server-owned Charm atoms that charm-sync replicates to every client (see StateSyncService /
	StateSyncController). Only the server writes these; client copies are overwritten by patches.

	Every key here is synced, so only add state that all players may see. Values must be
	immutable: always write a new table instead of mutating the current one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Shared.Packages.charm)
local PublicConfigDefaults = require(ReplicatedStorage.Shared.Config.PublicConfigDefaults)

export type ServerInfo = {
	PlaceVersion: number,
	StartTime: number,
	ShuttingDown: boolean,
}

local SharedAtoms = {
	-- Public remote config values (written by RemoteConfigService).
	PublicConfig = Charm.atom(table.clone(PublicConfigDefaults) :: { [string]: any }),

	ServerInfo = Charm.atom({
		PlaceVersion = 0,
		StartTime = 0,
		ShuttingDown = false,
	} :: ServerInfo),
}

return SharedAtoms
