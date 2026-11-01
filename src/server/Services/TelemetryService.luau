--!strict
--[[
	Event pipeline for your LiveOps backend plus Roblox AnalyticsService.

	- Track(name, fields, player?) buffers an event; batches are POSTed to <LIVEOPS_BASE_URL>/events
	  every TELEMETRY_FLUSH_INTERVAL seconds and on shutdown. Batching keeps well under the
	  HttpService limit of 500 requests per minute per server.
	- LogEconomy / LogFunnelStep / LogCustom also forward to AnalyticsService (Creator Dashboard).
	- Server errors (ScriptContext.Error), client errors (Net.ClientError) and NetGuard violations
	  are captured automatically and de-duplicated per flush window.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local LiveOpsHttp = require(script.Parent.Parent.Modules.LiveOpsHttp)
local NetGuard = require(script.Parent.Parent.Modules.NetGuard)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

type TelemetryEvent = {
	Name: string,
	Time: number,
	UserId: number?,
	Fields: { [string]: any }?,
}

local TelemetryService = {
	Priority = 0,
}

local MAX_REQUESTS_PER_FLUSH = 4

local SERVER_INFO = {
	PlaceId = game.PlaceId,
	PlaceVersion = game.PlaceVersion,
	JobId = game.JobId,
	IsStudio = ServerConfig.IS_STUDIO,
	IsPrivate = game.PrivateServerId ~= "",
}

local eventBuffer: { TelemetryEvent } = {}
local droppedCount = 0
local errorEvents: { [string]: TelemetryEvent } = {}

local function push(event: TelemetryEvent)
	if #eventBuffer >= ServerConfig.TELEMETRY_MAX_BUFFER then
		droppedCount += 1
		return
	end
	table.insert(eventBuffer, event)
end

function TelemetryService:Track(eventName: string, fields: { [string]: any }?, player: Player?)
	push({
		Name = eventName,
		Time = DateTime.now().UnixTimestampMillis,
		UserId = if player then player.UserId else nil,
		Fields = fields,
	})
end

-- Collapses repeats of the same error into one event with a Count until the next flush.
local function trackError(eventName: string, message: string, stack: string, player: Player?)
	local key = `{eventName}|{message}`
	local existing = errorEvents[key]
	if existing and existing.Fields then
		existing.Fields.Count += 1
		return
	end

	local event: TelemetryEvent = {
		Name = eventName,
		Time = DateTime.now().UnixTimestampMillis,
		UserId = if player then player.UserId else nil,
		Fields = { Message = message, Stack = stack, Count = 1 },
	}
	errorEvents[key] = event
	push(event)
end

function TelemetryService:LogEconomy(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?
)
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currency,
			amount,
			endingBalance,
			transactionType,
			itemSku
		)
	end)
	TelemetryService:Track("Economy", {
		Flow = flowType.Name,
		Currency = currency,
		Amount = amount,
		Balance = endingBalance,
		Transaction = transactionType,
		Sku = itemSku,
	}, player)
end

function TelemetryService:LogFunnelStep(
	player: Player,
	funnelName: string,
	step: number,
	stepName: string?,
	funnelSessionId: string?
)
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName)
	end)
	TelemetryService:Track(
		"Funnel",
		{ Funnel = funnelName, Step = step, StepName = stepName, Session = funnelSessionId },
		player
	)
end

function TelemetryService:LogCustom(player: Player, eventName: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value)
	end)
	TelemetryService:Track("Custom", { Event = eventName, Value = value }, player)
end

function TelemetryService:FlushAsync()
	table.clear(errorEvents)

	if not LiveOpsHttp.IsEnabled() then
		table.clear(eventBuffer)
		droppedCount = 0
		return
	end

	for _ = 1, MAX_REQUESTS_PER_FLUSH do
		if #eventBuffer == 0 then
			return
		end

		local count = math.min(#eventBuffer, ServerConfig.TELEMETRY_BATCH_SIZE)
		local batch = table.move(eventBuffer, 1, count, 1, {})
		local remaining = table.move(eventBuffer, count + 1, #eventBuffer, 1, {})
		eventBuffer = remaining

		local ok, err = LiveOpsHttp.RequestAsync("POST", "/events", {
			Server = SERVER_INFO,
			Dropped = droppedCount,
			Events = batch,
		})

		if ok then
			droppedCount = 0
		else
			warn(`[TelemetryService] Flush failed: {err}`)
			-- Put the batch back in front so it is retried next flush; overflow is counted as dropped.
			local space = ServerConfig.TELEMETRY_MAX_BUFFER - #eventBuffer
			local keep = math.min(space, #batch)
			droppedCount += #batch - keep
			eventBuffer = table.move(
				eventBuffer,
				1,
				#eventBuffer,
				keep + 1,
				table.move(batch, 1, keep, 1, {})
			)
			return
		end
	end
end

function TelemetryService:Init()
	ScriptContext.Error:Connect(function(message, stackTrace)
		trackError("ServerError", message, stackTrace)
	end)

	NetGuard.Listen(Net.ClientError, "ClientError", {
		MaxPerWindow = 5,
		Window = 60,
		Validate = function(value)
			return #value.message <= Constants.CLIENT_ERROR_MAX_MESSAGE
				and #value.stack <= Constants.CLIENT_ERROR_MAX_STACK
		end,
	}, function(value, player)
		trackError("ClientError", value.message, value.stack, player)
	end)

	NetGuard.Violation:Connect(function(player: Player, packetName: string, reason: string)
		trackError("NetViolation", `{packetName}:{reason}`, "", player)
	end)

	Players.PlayerAdded:Connect(function(player)
		TelemetryService:Track("PlayerJoined", { AccountAge = player.AccountAge }, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		TelemetryService:Track("PlayerLeft", nil, player)
	end)

	game:BindToClose(function()
		TelemetryService:Track("ServerShutdown", { PlayerCount = #Players:GetPlayers() })
		self:FlushAsync()
	end)
end

function TelemetryService:OnStart()
	TelemetryService:Track("ServerStarted")
	while true do
		task.wait(ServerConfig.TELEMETRY_FLUSH_INTERVAL)
		self:FlushAsync()
	end
end

return TelemetryService
