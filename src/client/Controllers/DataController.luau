--!strict
--[[
	Client mirror of the local player's profile data (minus server-only keys), stored in a Charm
	signal. Updates are copy-on-write along the changed path, so unchanged branches keep their
	identity and only selectors that depend on changed keys re-run.

	DataController.Data()                                  -- Charm getter: ProfileData? (tracked)
	DataController:Select("Cash")                          -- memoized Charm getter for one key
	DataController:Observe("Cash", function(cash) end)     -- callback now and on every change
	DataController:OnLoaded(function(data) end)
	DataController.Changed:Connect(function(path, value) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Shared.Packages.charm)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Signal = require(ReplicatedStorage.Shared.Packages.signal)
local Types = require(ReplicatedStorage.Shared.Types)

type ProfileData = Types.ProfileData
type Keys = { string | number }

local getData, setData = Charm.signal(nil :: { [string]: any }?)

local DataController = {
	Priority = 10,
	-- Charm getter for the whole (immutable) data table, nil until loaded.
	Data = function(): ProfileData?
		return getData() :: any
	end,
	-- (path: { string | number }, value: any) after each applied change
	Changed = Signal.new(),
	-- (data: ProfileData) once, when the first snapshot arrives
	Loaded = Signal.new(),
}

local selectors: { [string]: () -> any } = {}
local NOT_LOADED = table.freeze({})

local function setIn(node: any, keys: Keys, index: number, value: any): { [any]: any }
	local copy = if type(node) == "table" then table.clone(node) else {}
	local key = keys[index]
	if index == #keys then
		copy[key] = value
	else
		copy[key] = setIn(copy[key], keys, index + 1, value)
	end
	return copy
end

function DataController:IsLoaded(): boolean
	return Charm.untracked(getData) ~= nil
end

-- Current data without subscribing; treat as read-only.
function DataController:GetData(): ProfileData?
	return Charm.untracked(getData) :: any
end

function DataController:Get(key: string): any
	local data = Charm.untracked(getData)
	return if data then data[key] else nil
end

-- Memoized Charm getter for a top-level key; only notifies when that key's value changes.
function DataController:Select(key: string): () -> any
	local selector = selectors[key]
	if selector == nil then
		selector = Charm.computed(function()
			local data = getData()
			return if data then data[key] else nil
		end)
		selectors[key] = selector
	end
	return selector
end

function DataController:OnLoaded(callback: (data: ProfileData) -> ())
	local data = Charm.untracked(getData)
	if data then
		task.spawn(callback, data :: any)
	else
		self.Loaded:Once(callback)
	end
end

--[[
	Calls `callback` with the value of a top-level key once loaded and again whenever it changes.
	Returns a function that stops observing.
]]
function DataController:Observe(key: string, callback: (value: any) -> ()): () -> ()
	local selector = self:Select(key)
	return Charm.listen(function()
		if getData() == nil then
			return NOT_LOADED
		end
		return selector()
	end, function(value)
		if value ~= NOT_LOADED then
			task.spawn(callback, value)
		end
	end)
end

function DataController:Init()
	Net.PlayerData.listen(function(snapshot: any)
		local firstLoad = Charm.untracked(getData) == nil
		setData(snapshot)
		if firstLoad then
			print("[Skoobi/Client] Player data received")
			self.Loaded:Fire(snapshot)
		end
	end)

	Net.PlayerDataChanged.listen(function(changes: any)
		if Charm.untracked(getData) == nil then
			return
		end

		setData(function(current)
			local nextData = current
			for _, change in changes do
				local keys: Keys = change[1]
				if #keys > 0 then
					nextData = setIn(nextData, keys, 1, change[2])
				end
			end
			return nextData
		end)

		for _, change in changes do
			self.Changed:Fire(change[1], change[2])
		end
	end)
end

return DataController
