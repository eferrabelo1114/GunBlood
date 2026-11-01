--!strict
--[[
	Bridges Charm state into Fusion: returns a Fusion Value that follows `getter` and stops
	following it when `scope` is cleaned up.

	local cash = useCharm(scope, DataController:Select("Cash"))
	scope:New "TextLabel" { Text = scope:Computed(function(use) return tostring(use(cash)) end) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Shared.Packages.charm)
local Types = require(script.Parent.Types)

local function useCharm<T>(scope: Types.Scope, getter: Types.Getter<T>)
	local value = scope:Value(Charm.untracked(getter))
	table.insert(
		scope,
		Charm.subscribe(getter, function(state)
			value:set(state)
		end)
	)
	return value
end

return useCharm
