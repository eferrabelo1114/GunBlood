--!strict
--[[
	Owns player profiles (ProfileStore session locking) and replicates them to their owners.

	Writing data:
		DataService:Increment(player, "Cash", 100)
		DataService:Set(player, { "Items", "Sword" }, 1)
		DataService:Update(player, "Items", function(items) items.Shield = 1; return items end)

	All writes go through Set / Increment / Update so they are replicated. Writing to
	GetData() / profile.Data directly does NOT replicate unless you call MarkChanged afterwards.
	Replication is batched: each frame the owner receives only the changed paths.

	LiveOps: other servers and the dashboard (through CommandService) deliver profile messages with
	DataService:SendMessageAsync(userId, { Type = "Increment", Path = { "Cash" }, Amount = 500 }).
	Messages reach the player even while they are offline or in another server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Promise = require(ReplicatedStorage.Shared.Packages.promise)
local ProfileTemplate = require(ReplicatedStorage.Shared.Data.ProfileTemplate)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)
local Types = require(ReplicatedStorage.Shared.Types)
local Migrations = require(script.Migrations)
local ProfileStore = require(script.Parent.Parent.Modules.ProfileStore)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local TelemetryService = require(script.Parent.TelemetryService)

type ProfileData = Types.ProfileData
type DataPath = Types.DataPath
type Keys = { string | number }
type ProfileSignal<T...> = {
	Connect: (self: any, listener: (T...) -> ()) -> { Disconnect: (self: any) -> () },
}

-- The subset of ProfileStore's Profile used by the framework. ProfileStore.Profile<T> intersects
-- T with a recursive JSON type that the Luau solver cannot unify, so it is restated here.
export type Profile = {
	Data: ProfileData,
	LastSavedData: ProfileData,
	Key: string,
	OnSave: ProfileSignal<>,
	OnAfterSave: ProfileSignal<ProfileData>,
	OnSessionEnd: ProfileSignal<>,
	IsActive: (self: any) -> boolean,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
	MessageHandler: (self: any, handler: (message: any, processed: () -> ()) -> ()) -> (),
	Save: (self: any) -> (),
}

type PlayerStoreType = {
	StartSessionAsync: (self: any, profileKey: string, params: any) -> Profile?,
	MessageAsync: (self: any, profileKey: string, message: any) -> boolean,
}

-- Return false to leave the message queued (e.g. a newer server should handle it).
export type MessageHandler = (player: Player, message: { [string]: any }) -> boolean

assert(
	ProfileTemplate.DataVersion == Migrations.Latest,
	`[DataService] ProfileTemplate.DataVersion ({ProfileTemplate.DataVersion}) must equal the latest migration ({Migrations.Latest})`
)

local DataService = {
	Priority = 20,
	Dependencies = { "TelemetryService" },
}

local PlayerStore: PlayerStoreType =
	ProfileStore.New(ServerConfig.PROFILE_STORE_NAME, ProfileTemplate) :: any

local Profiles: { [Player]: Profile } = {}
local ProfilePromises: { [Player]: any } = {}
local ProfileResolvers: { [Player]: (Profile?) -> () } = {}
local PendingChanges: { [Player]: { Keys } } = {}
local MessageHandlers: { [string]: MessageHandler } = {}

local function getOrCreateProfilePromise(player: Player)
	local existing = ProfilePromises[player]
	if existing then
		return existing
	end

	local promise = Promise.new(function(resolve)
		local profile = Profiles[player]
		if profile ~= nil then
			resolve(profile)
		else
			ProfileResolvers[player] = resolve :: any
		end
	end)

	ProfilePromises[player] = promise
	return promise
end

local function resolveProfilePromise(player: Player, profile: Profile?)
	local resolve = ProfileResolvers[player]
	if resolve then
		ProfileResolvers[player] = nil
		resolve(profile)
	elseif ProfilePromises[player] == nil then
		ProfilePromises[player] = Promise.resolve(profile)
	end
end

local function clearPlayer(player: Player)
	local resolve = ProfileResolvers[player]
	if resolve then
		ProfileResolvers[player] = nil
		resolve(nil)
	end
	Profiles[player] = nil
	ProfilePromises[player] = nil
	PendingChanges[player] = nil
end

local function toKeys(path: DataPath): Keys
	if type(path) == "string" then
		return { path }
	end
	return path
end

local function isPrefix(prefix: Keys, keys: Keys): boolean
	if #prefix > #keys then
		return false
	end
	for index, key in prefix do
		if keys[index] ~= key then
			return false
		end
	end
	return true
end

-- Returns the table holding the final key, or nil if an intermediate key is missing / not a table.
local function resolveParent(data: any, keys: Keys): (any, (string | number)?)
	local node = data
	for index = 1, #keys - 1 do
		node = node[keys[index]]
		if type(node) ~= "table" then
			return nil, nil
		end
	end
	return node, keys[#keys]
end

local function readPath(data: any, keys: Keys): any
	local node = data
	for _, key in keys do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

local function queueChange(player: Player, keys: Keys)
	if ServerConfig.PRIVATE_DATA_KEYS[keys[1] :: any] then
		return
	end

	local pending = PendingChanges[player]
	if pending == nil then
		pending = {}
		PendingChanges[player] = pending
	end

	-- Values are read at flush time, so a pending ancestor already covers this path,
	-- and this path supersedes any pending descendants.
	for index = #pending, 1, -1 do
		local queued = pending[index]
		if isPrefix(queued, keys) then
			return
		elseif isPrefix(keys, queued) then
			table.remove(pending, index)
		end
	end
	table.insert(pending, table.clone(keys))
end

local function flushChanges()
	if next(PendingChanges) == nil then
		return
	end

	for player, pending in PendingChanges do
		local profile = Profiles[player]
		if profile then
			local changes: { Types.DataChange } = table.create(#pending)
			for index, keys in pending do
				changes[index] = { keys, readPath(profile.Data, keys) }
			end
			Net.PlayerDataChanged.sendTo(changes, player)
		end
	end
	table.clear(PendingChanges)
end

local function buildSnapshot(data: ProfileData): { [string]: any }
	local snapshot = {}
	for key, value in data :: any do
		if not ServerConfig.PRIVATE_DATA_KEYS[key] then
			snapshot[key] = value
		end
	end
	return snapshot
end

local function migrateProfile(profile: Profile): (Migrations.Status, string?)
	local data = profile.Data :: any
	if Migrations.GetVersion(data) == Migrations.Latest then
		return "Current", nil
	end

	local copy = TableUtil.DeepCopy(data)
	local status, err = Migrations.Apply(copy)
	if status == "Migrated" then
		profile.Data = copy
	end
	return status :: Migrations.Status, err
end

local function recordSessionStart(profile: Profile)
	local meta = profile.Data.Meta
	local now = os.time()
	if meta.FirstJoin == 0 then
		meta.FirstJoin = now
	end
	meta.LastJoin = now
	meta.JoinCount += 1

	local lastTick = os.clock()
	profile.OnSave:Connect(function()
		local whole = math.floor(os.clock() - lastTick)
		profile.Data.Meta.TotalPlaytime += whole
		lastTick += whole
	end)
end

local function handleMessage(player: Player, message: any, processed: () -> ())
	if type(message) ~= "table" or type(message.Type) ~= "string" then
		warn(`[DataService] Dropping malformed profile message for {player.UserId}`)
		processed()
		return
	end

	local handler = MessageHandlers[message.Type]
	if handler == nil then
		-- Left queued: a newer server build may know this message type.
		return
	end

	local ok, result = pcall(handler, player, message)
	if not ok then
		warn(`[DataService] Profile message "{message.Type}" failed for {player.UserId}: {result}`)
		TelemetryService:Track(
			"ProfileMessageFailed",
			{ Type = message.Type, Error = tostring(result) },
			player
		)
	elseif result ~= false then
		processed()
	end
end

local function kick(player: Player, reason: string)
	if player.Parent == Players then
		player:Kick(reason)
	end
end

local function loadProfile(player: Player)
	getOrCreateProfilePromise(player)

	local profile = PlayerStore:StartSessionAsync(
		tostring(player.UserId),
		{
			Cancel = function()
				return player.Parent ~= Players
			end,
		} :: any
	)

	if profile == nil then
		resolveProfilePromise(player, nil)
		clearPlayer(player)
		kick(player, "Profile load failed - Please rejoin")
		return
	end

	local status, migrationError = migrateProfile(profile)
	if status == "Newer" or status == "Failed" then
		TelemetryService:Track(
			"ProfileMigrationRejected",
			{ Status = status, Error = migrationError },
			player
		)
		warn(`[DataService] {player.UserId}: {migrationError}`)
		profile:EndSession()
		resolveProfilePromise(player, nil)
		clearPlayer(player)
		kick(
			player,
			if status == "Newer"
				then "This server is running an older version - Please rejoin"
				else "Profile update failed - Please rejoin"
		)
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		clearPlayer(player)
		kick(player, "Profile session ended - Please rejoin")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		resolveProfilePromise(player, nil)
		clearPlayer(player)
		return
	end

	recordSessionStart(profile)
	Profiles[player] = profile
	resolveProfilePromise(player, profile)

	Net.PlayerData.sendTo(buildSnapshot(profile.Data), player)
	profile:MessageHandler(function(message, processed)
		handleMessage(player, message, processed)
	end)

	print(`[Skoobi/Server] Profile loaded for {player.Name}`)
	GameEvents.PlayerDataLoaded:Fire(player)
	GameEvents.PlayerReadyToSpawn:Fire(player)
end

local function validKeys(value: any): boolean
	if type(value) ~= "table" or #value == 0 then
		return false
	end
	for _, key in value do
		if type(key) ~= "string" and type(key) ~= "number" then
			return false
		end
	end
	return true
end

--[[
	Returns the loaded profile, or nil if not yet available. Direct writes to profile.Data are
	saved but not replicated; prefer Set / Increment / Update.
]]
function DataService:GetProfile(player: Player): Profile?
	return Profiles[player]
end

--[[
	Yields until the player's profile session is ready (or fails / player left).
	Returns the profile, or nil on failure.
]]
function DataService:GetProfileAsync(player: Player): Profile?
	local existing = Profiles[player]
	if existing then
		return existing
	end

	if player.Parent ~= Players then
		return nil
	end

	return getOrCreateProfilePromise(player):expect()
end

function DataService:IsLoaded(player: Player): boolean
	return Profiles[player] ~= nil
end

-- Live data table; treat as read-only.
function DataService:GetData(player: Player): ProfileData?
	local profile = Profiles[player]
	return if profile then profile.Data else nil
end

function DataService:Get(player: Player, path: DataPath): any
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end
	return readPath(profile.Data, toKeys(path))
end

-- Sets the value at `path` (nil removes it). Returns false if the profile or parent path is missing.
function DataService:Set(player: Player, path: DataPath, value: any): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	local keys = toKeys(path)
	local parent, key = resolveParent(profile.Data, keys)
	if parent == nil or key == nil then
		warn(
			`[DataService] Set: invalid path {table.concat(keys :: any, ".")}\n{debug.traceback()}`
		)
		return false
	end

	parent[key] = value
	queueChange(player, keys)
	return true
end

-- Adds `delta` to a number (missing counts as 0). Returns the new value, or nil on failure.
function DataService:Increment(player: Player, path: DataPath, delta: number): number?
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end

	local keys = toKeys(path)
	local parent, key = resolveParent(profile.Data, keys)
	if parent == nil or key == nil then
		warn(
			`[DataService] Increment: invalid path {table.concat(keys :: any, ".")}\n{debug.traceback()}`
		)
		return nil
	end

	local current = parent[key]
	if current ~= nil and type(current) ~= "number" then
		warn(
			`[DataService] Increment: {table.concat(keys :: any, ".")} is not a number\n{debug.traceback()}`
		)
		return nil
	end

	local newValue = (current or 0) + delta
	parent[key] = newValue
	queueChange(player, keys)
	return newValue
end

--[[
	Calls `updater` with a copy of the value at `path` and stores whatever it returns.
	If the updater errors, the stored data is left unchanged and false is returned.
]]
function DataService:Update(player: Player, path: DataPath, updater: (current: any) -> any): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	local keys = toKeys(path)
	local parent, key = resolveParent(profile.Data, keys)
	if parent == nil or key == nil then
		warn(
			`[DataService] Update: invalid path {table.concat(keys :: any, ".")}\n{debug.traceback()}`
		)
		return false
	end

	local ok, result = pcall(updater, TableUtil.DeepCopy(parent[key]))
	if not ok then
		warn(`[DataService] Update failed for {table.concat(keys :: any, ".")}: {result}`)
		TelemetryService:Track(
			"DataUpdateFailed",
			{ Path = keys, Error = tostring(result) },
			player
		)
		return false
	end

	parent[key] = result
	queueChange(player, keys)
	return true
end

-- Replicates `path` after code mutated profile.Data directly.
function DataService:MarkChanged(player: Player, path: DataPath)
	if Profiles[player] then
		queueChange(player, toKeys(path))
	end
end

--[[
	Registers the handler for profile messages of `messageType`. Must be called during Init,
	before any profile loads. Handlers must be idempotent per message and should only mutate data
	through DataService so changes replicate.
]]
function DataService:RegisterMessageHandler(messageType: string, handler: MessageHandler)
	assert(
		MessageHandlers[messageType] == nil,
		`[DataService] Duplicate message handler "{messageType}"`
	)
	MessageHandlers[messageType] = handler
end

-- Delivers a message to a profile whether the player is online anywhere or offline. Yields.
function DataService:SendMessageAsync(userId: number, message: { [string]: any }): boolean
	assert(type(message.Type) == "string", "[DataService] Profile messages need a string Type")
	return PlayerStore:MessageAsync(tostring(userId), message :: any)
end

function DataService:Init()
	self:RegisterMessageHandler("Increment", function(player, message)
		assert(
			validKeys(message.Path) and type(message.Amount) == "number",
			"Increment needs Path and Amount"
		)
		return DataService:Increment(player, message.Path, message.Amount) ~= nil
	end)

	self:RegisterMessageHandler("Set", function(player, message)
		assert(validKeys(message.Path), "Set needs Path")
		return DataService:Set(player, message.Path, message.Value)
	end)

	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		TelemetryService:Track(
			"DataStoreError",
			{ Message = message, Store = storeName, Key = profileKey }
		)
	end)

	ProfileStore.OnOverwrite:Connect(function(storeName, profileKey)
		TelemetryService:Track("DataStoreOverwrite", { Store = storeName, Key = profileKey })
	end)

	ProfileStore.OnCriticalToggle:Connect(function(isCritical)
		warn(`[DataService] ProfileStore critical state: {isCritical}`)
		TelemetryService:Track("DataStoreCritical", { Critical = isCritical })
	end)

	GameEvents.PlayerInitialized:Connect(loadProfile)

	Players.PlayerRemoving:Connect(function(player)
		local profile = Profiles[player]
		if profile ~= nil then
			profile:EndSession()
		end
		clearPlayer(player)
	end)

	RunService.Heartbeat:Connect(flushChanges)
end

return DataService
