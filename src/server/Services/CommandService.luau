--!strict
--[[
	Channels your LiveOps dashboard uses to control live servers. Both are reachable from outside
	Roblox with an Open Cloud API key.

	Broadcast: MessagingService topic ServerConfig.LIVEOPS_BROADCAST_TOPIC (Open Cloud Messaging API).
	Every server runs the command; add "JobId" or "PlaceVersion" to target a subset.
		{ "Type": "Announce", "Text": "Double XP is live!", "Duration": 10 }
		{ "Type": "Kick", "UserId": 123, "Reason": "..." }
		{ "Type": "Shutdown", "Reason": "Emergency maintenance" }
		{ "Type": "RefreshConfig" }

	Queue: MemoryStore queue ServerConfig.LIVEOPS_QUEUE_NAME (Open Cloud MemoryStore API).
	Each item is handled by exactly one server, so use it for anything that must happen once.
	A failing item is retried after LIVEOPS_QUEUE_INVISIBILITY seconds; give items an expiration
	when adding them so a permanently failing command eventually drops.
		{ "Type": "ProfileMessage", "UserId": 123, "Message": { "Type": "Increment", "Path": ["Cash"], "Amount": 500 } }
		{ "Type": "Ban", "UserIds": [123], "Duration": -1, "DisplayReason": "...", "PrivateReason": "..." }
		{ "Type": "Unban", "UserIds": [123] }
]]

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Modules.Net)
local SharedAtoms = require(ReplicatedStorage.Shared.State.SharedAtoms)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local DataService = require(script.Parent.DataService)
local RemoteConfigService = require(script.Parent.RemoteConfigService)
local TelemetryService = require(script.Parent.TelemetryService)

type Command = { [string]: any }
type Handler = (command: Command) -> ()

local CommandService = {
	Priority = 40,
	Dependencies = { "DataService", "RemoteConfigService", "TelemetryService" },
}

local MAX_ANNOUNCEMENT_LENGTH = 500
local SUBSCRIBE_RETRY_DELAY = 10

local broadcastHandlers: { [string]: Handler } = {}
local queueHandlers: { [string]: Handler } = {}
local shuttingDown = false

local function decode(raw: any): Command?
	if type(raw) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		raw = if ok then decoded else nil
	end
	if type(raw) == "table" and type(raw.Type) == "string" then
		return raw
	end
	return nil
end

local function isTargeted(command: Command): boolean
	if command.JobId ~= nil and command.JobId ~= game.JobId then
		return false
	end
	if command.PlaceVersion ~= nil and command.PlaceVersion ~= game.PlaceVersion then
		return false
	end
	return true
end

function CommandService:Announce(text: string, duration: number?)
	Net.Announcement.sendToAll({
		text = string.sub(text, 1, MAX_ANNOUNCEMENT_LENGTH),
		duration = math.clamp(math.floor(duration or 8), 1, 600),
	})
end

-- Warns everyone, then kicks all players and refuses new joins. Yields.
function CommandService:ShutdownAsync(reason: string?)
	if shuttingDown then
		return
	end
	shuttingDown = true
	SharedAtoms.ServerInfo(function(info)
		local nextInfo = table.clone(info)
		nextInfo.ShuttingDown = true
		return nextInfo
	end)

	local message = reason or "This server is shutting down for maintenance"
	TelemetryService:Track("ShutdownCommand", { Reason = message })
	self:Announce(message, ServerConfig.SHUTDOWN_KICK_DELAY)
	task.wait(ServerConfig.SHUTDOWN_KICK_DELAY)

	for _, player in Players:GetPlayers() do
		player:Kick(message)
	end
end

broadcastHandlers.Announce = function(command)
	assert(type(command.Text) == "string", "Announce needs Text")
	CommandService:Announce(
		command.Text,
		if type(command.Duration) == "number" then command.Duration else nil
	)
end

broadcastHandlers.Kick = function(command)
	assert(type(command.UserId) == "number", "Kick needs UserId")
	local player = Players:GetPlayerByUserId(command.UserId)
	if player then
		player:Kick(
			if type(command.Reason) == "string" then command.Reason else "Removed from the server"
		)
	end
end

broadcastHandlers.Shutdown = function(command)
	CommandService:ShutdownAsync(if type(command.Reason) == "string" then command.Reason else nil)
end

broadcastHandlers.RefreshConfig = function()
	-- Spread the backend load when every server receives this at once.
	task.wait(math.random() * 5)
	RemoteConfigService:RefreshAsync()
end

queueHandlers.ProfileMessage = function(command)
	assert(type(command.UserId) == "number", "ProfileMessage needs UserId")
	assert(
		type(command.Message) == "table" and type(command.Message.Type) == "string",
		"ProfileMessage needs Message.Type"
	)
	assert(DataService:SendMessageAsync(command.UserId, command.Message), "MessageAsync failed")
end

queueHandlers.Ban = function(command)
	assert(type(command.UserIds) == "table", "Ban needs UserIds")
	assert(type(command.Duration) == "number", "Ban needs Duration (-1 for permanent)")
	Players:BanAsync({
		UserIds = command.UserIds,
		Duration = command.Duration,
		DisplayReason = if type(command.DisplayReason) == "string"
			then command.DisplayReason
			else "Banned",
		PrivateReason = if type(command.PrivateReason) == "string"
			then command.PrivateReason
			else "",
		ExcludeAltAccounts = command.ExcludeAltAccounts == true,
		ApplyToUniverse = true,
	})
end

queueHandlers.Unban = function(command)
	assert(type(command.UserIds) == "table", "Unban needs UserIds")
	Players:UnbanAsync({
		UserIds = command.UserIds,
		ApplyToUniverse = true,
	})
end

local function runHandler(
	channel: string,
	handlers: { [string]: Handler },
	command: Command
): boolean
	local handler = handlers[command.Type]
	if handler == nil then
		TelemetryService:Track("LiveOpsCommandUnknown", { Channel = channel, Type = command.Type })
		return true
	end

	local ok, err = pcall(handler :: any, command)
	if not ok then
		warn(`[CommandService] {channel} command "{command.Type}" failed: {err}`)
		TelemetryService:Track(
			"LiveOpsCommandFailed",
			{ Channel = channel, Type = command.Type, Error = tostring(err) }
		)
	end
	return ok
end

local function subscribeBroadcasts()
	while true do
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(ServerConfig.LIVEOPS_BROADCAST_TOPIC, function(message)
				local command = decode(message.Data)
				if command and isTargeted(command) then
					runHandler("Broadcast", broadcastHandlers, command)
				end
			end)
		end)
		if ok then
			return
		end
		warn(`[CommandService] Broadcast subscribe failed, retrying: {err}`)
		task.wait(SUBSCRIBE_RETRY_DELAY)
	end
end

local function pollQueue()
	local queue = MemoryStoreService:GetQueue(
		ServerConfig.LIVEOPS_QUEUE_NAME,
		ServerConfig.LIVEOPS_QUEUE_INVISIBILITY
	)

	local failing = false

	while true do
		local ok, items, readId = pcall(function()
			return queue:ReadAsync(1, false, ServerConfig.LIVEOPS_QUEUE_WAIT)
		end)

		if not ok then
			if not failing then
				failing = true
				warn(`[CommandService] Queue read failing (retrying quietly): {items}`)
			end
			task.wait(ServerConfig.LIVEOPS_QUEUE_WAIT)
			continue
		end
		failing = false

		if items ~= nil and #items > 0 then
			local command = decode(items[1])
			local done = true
			if command == nil then
				TelemetryService:Track("LiveOpsCommandMalformed", { Channel = "Queue" })
			else
				done = runHandler("Queue", queueHandlers, command)
			end

			if done then
				pcall(function()
					queue:RemoveAsync(readId)
				end)
			end
		end
	end
end

function CommandService:IsShuttingDown(): boolean
	return shuttingDown
end

function CommandService:Init()
	Players.PlayerAdded:Connect(function(player)
		if shuttingDown then
			player:Kick("This server is shutting down - Please rejoin")
		end
	end)

	game:BindToClose(function()
		if not shuttingDown then
			self:Announce("This server is restarting for an update", 30)
		end
	end)
end

function CommandService:OnStart()
	task.spawn(subscribeBroadcasts)
	pollQueue()
end

return CommandService
