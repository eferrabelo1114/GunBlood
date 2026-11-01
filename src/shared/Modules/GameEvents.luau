--!strict
--[[
	Per-realm in-memory event bus (NOT networked).
	Server and client each have their own GameEvents instance.
	Use Net (ByteNet) for cross-realm communication.

	Every event is declared below with its argument types. Indexing an undeclared event errors,
	so a typo can never silently create a signal nobody listens to.
]]

local Signal = require(game:GetService("ReplicatedStorage").Shared.Packages.signal)

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Event<T...> = {
	Fire: (self: Event<T...>, T...) -> (),
	Connect: (self: Event<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Event<T...>, fn: (T...) -> ()) -> Connection,
	Wait: (self: Event<T...>) -> T...,
}

local function event(): any
	return Signal.new()
end

local GameEvents = {
	-- Server: client finished loading and the server is ready for it. Fires once per player.
	PlayerInitialized = event() :: Event<Player>,
	-- Server: profile is loaded, migrated and replicated.
	PlayerDataLoaded = event() :: Event<Player>,
	-- Server: request a (re)spawn for the player.
	PlayerReadyToSpawn = event() :: Event<Player>,
	-- Server: a developer product was granted (fires once per unique PurchaseId).
	ProductGranted = event() :: Event<Player, number>,
	-- Server: a game pass was bought in this session.
	GamePassPurchased = event() :: Event<Player, number>,
	-- Server: Premium membership changed.
	PremiumChanged = event() :: Event<Player>,
	-- Both realms: a remote config key changed value (key, newValue).
	ConfigChanged = event() :: Event<string, any>,
}

return setmetatable(GameEvents, {
	__index = function(_, eventName)
		error(
			`[GameEvents] Unknown event "{tostring(eventName)}"; declare it in GameEvents.luau`,
			2
		)
	end,
})
