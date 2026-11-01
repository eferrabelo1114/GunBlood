--!strict
--[[
	Server-only configuration. Lives outside ReplicatedStorage so clients never see it.
]]

local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

local ServerConfig = {
	IS_STUDIO = IS_STUDIO,

	-- Studio uses a separate store so testing never touches live player data.
	PROFILE_STORE_NAME = if IS_STUDIO then "PlayerStore_DEV" else "PlayerStore",
	-- Top-level profile keys that are never replicated to the owning client.
	PRIVATE_DATA_KEYS = { PurchaseHistory = true } :: { [string]: boolean },
	-- Recent receipt PurchaseIds kept per profile for ProcessReceipt idempotency.
	PURCHASE_HISTORY_SIZE = 50,

	-- LiveOps backend. Leave LIVEOPS_BASE_URL empty to disable all HTTP calls.
	LIVEOPS_BASE_URL = "",
	-- HttpService secret sent as "Authorization: Bearer <secret>".
	LIVEOPS_SECRET_NAME = "LIVEOPS_API_KEY",
	CONFIG_POLL_INTERVAL = 60,
	TELEMETRY_FLUSH_INTERVAL = 30,
	TELEMETRY_BATCH_SIZE = 250,
	TELEMETRY_MAX_BUFFER = 5000,

	-- Dashboard -> server channels (see CommandService).
	LIVEOPS_BROADCAST_TOPIC = "LiveOps",
	LIVEOPS_QUEUE_NAME = "LiveOpsCommands",
	LIVEOPS_QUEUE_INVISIBILITY = 60,
	LIVEOPS_QUEUE_WAIT = 10,
	SHUTDOWN_KICK_DELAY = 10,

	-- NetGuard kicks a player after this many rejected packets in one session.
	NETGUARD_KICK_THRESHOLD = 100,
}

return ServerConfig
