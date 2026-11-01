--!strict
--[[
	Client view of the public remote config, backed by SharedAtoms.PublicConfig (charm-sync).
	Starts from PublicConfigDefaults and updates whenever the server changes a value.

	RemoteConfigController:Get("EventActive")          -- current value
	RemoteConfigController:Select("EventActive")       -- Charm getter for effects / UI
	GameEvents.ConfigChanged:Connect(function(key, value) ... end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Shared.Packages.charm)
local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local PublicConfigDefaults = require(ReplicatedStorage.Shared.Config.PublicConfigDefaults)
local SharedAtoms = require(ReplicatedStorage.Shared.State.SharedAtoms)

local RemoteConfigController = {
	Priority = 10,
	Dependencies = { "StateSyncController" },
}

local selectors: { [string]: () -> any } = {}

local function assertKnown(key: string)
	if PublicConfigDefaults[key] == nil then
		error(`[RemoteConfigController] Unknown config key "{key}"`, 3)
	end
end

-- Falls back to the default when the server sends a value of the wrong type.
local function read(config: { [string]: any }, key: string): any
	local value = config[key]
	local default = PublicConfigDefaults[key]
	return if typeof(value) == typeof(default) then value else default
end

function RemoteConfigController:Get(key: string): any
	assertKnown(key)
	return read(Charm.untracked(SharedAtoms.PublicConfig), key)
end

function RemoteConfigController:Select(key: string): () -> any
	assertKnown(key)
	local selector = selectors[key]
	if selector == nil then
		selector = Charm.computed(function()
			return read(SharedAtoms.PublicConfig(), key)
		end)
		selectors[key] = selector
	end
	return selector
end

function RemoteConfigController:Init()
	Charm.subscribe(SharedAtoms.PublicConfig, function(config, previous)
		for key in PublicConfigDefaults do
			local value = read(config, key)
			if value ~= read(previous, key) then
				GameEvents.ConfigChanged:Fire(key, value)
			end
		end
	end)
end

return RemoteConfigController
