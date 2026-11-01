--!strict
--[[
	Live-tunable values (feature flags, event toggles, balance numbers) from your LiveOps backend.

	GET <LIVEOPS_BASE_URL>/config must return { "Values": { "<Key>": <value>, ... } }.
	Values are polled every CONFIG_POLL_INTERVAL seconds and refreshed immediately when the
	dashboard broadcasts RefreshConfig (see CommandService). Missing or mistyped keys fall back to
	the in-code defaults, so the game always runs even if the backend is down.
	Public keys are published to clients through SharedAtoms.PublicConfig (charm-sync).

	RemoteConfigService:Get("CashMultiplier")
	GameEvents.ConfigChanged:Connect(function(key, value) ... end)
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local PublicConfigDefaults = require(ReplicatedStorage.Shared.Config.PublicConfigDefaults)
local SharedAtoms = require(ReplicatedStorage.Shared.State.SharedAtoms)
local LiveOpsHttp = require(script.Parent.Parent.Modules.LiveOpsHttp)
local RemoteConfigDefaults = require(script.Parent.Parent.RemoteConfigDefaults)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local TelemetryService = require(script.Parent.TelemetryService)

local RemoteConfigService = {
	Priority = 5,
	Dependencies = { "TelemetryService" },
}

local defaults: { [string]: any } = table.clone(PublicConfigDefaults)
local warnedKeys: { [string]: true } = {}

for key, value in RemoteConfigDefaults do
	assert(
		PublicConfigDefaults[key] == nil,
		`[RemoteConfigService] "{key}" is declared as both public and server-only`
	)
	defaults[key] = value
end

local values: { [string]: any } = table.clone(defaults)

local function warnOnce(key: string, message: string)
	if not warnedKeys[key] then
		warnedKeys[key] = true
		warn(`[RemoteConfigService] {message}`)
	end
end

local function sameValue(a: any, b: any): boolean
	if type(a) == "table" and type(b) == "table" then
		return HttpService:JSONEncode(a) == HttpService:JSONEncode(b)
	end
	return a == b
end

local function publicSnapshot(): { [string]: any }
	local snapshot = {}
	for key in PublicConfigDefaults do
		snapshot[key] = values[key]
	end
	return snapshot
end

local function apply(remote: { [string]: any })
	for key in remote do
		if defaults[key] == nil then
			warnOnce(key, `Ignoring unknown remote key "{key}"`)
		end
	end

	local changedKeys: { string } = {}
	local publicChanged = false

	for key, default in defaults do
		local incoming = remote[key]
		local nextValue = default
		if incoming ~= nil then
			if typeof(incoming) == typeof(default) then
				nextValue = incoming
			else
				warnOnce(
					key,
					`Remote key "{key}" is a {typeof(incoming)}, expected {typeof(default)}`
				)
			end
		end

		if not sameValue(values[key], nextValue) then
			values[key] = nextValue
			table.insert(changedKeys, key)
			publicChanged = publicChanged or PublicConfigDefaults[key] ~= nil
		end
	end

	if publicChanged then
		SharedAtoms.PublicConfig(publicSnapshot())
	end
	for _, key in changedKeys do
		GameEvents.ConfigChanged:Fire(key, values[key])
	end
end

function RemoteConfigService:Get(key: string): any
	local value = values[key]
	if value == nil then
		error(`[RemoteConfigService] Unknown config key "{key}"`, 2)
	end
	return value
end

-- Yields. Returns true if fresh values were fetched and applied.
function RemoteConfigService:RefreshAsync(): boolean
	if not LiveOpsHttp.IsEnabled() then
		return false
	end

	local ok, body = LiveOpsHttp.RequestAsync("GET", "/config")
	if not ok or type(body) ~= "table" or type(body.Values) ~= "table" then
		TelemetryService:Track(
			"ConfigFetchFailed",
			{ Error = if ok then "Malformed body" else tostring(body) }
		)
		return false
	end

	apply(body.Values)
	return true
end

function RemoteConfigService:OnStart()
	if not LiveOpsHttp.IsEnabled() then
		return
	end

	self:RefreshAsync()
	while true do
		-- Jitter so thousands of servers do not hit the backend in the same second.
		task.wait(ServerConfig.CONFIG_POLL_INTERVAL * (0.9 + math.random() * 0.2))
		self:RefreshAsync()
	end
end

return RemoteConfigService
