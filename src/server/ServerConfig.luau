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

	-- Practice bot: duels a player who has waited alone in the queue for BOT_FILL_DELAY seconds.
	BOTS_ENABLED = true,
	BOT_FILL_DELAY = 6,
	BOT_NAME = "Bandit",
	-- Target-practice mode: the bot holsters properly but then just stands there, never moving
	-- or shooting. Rounds end when you kill it or on ROUND_TIMEOUT.
	BOT_PASSIVE = true,
	-- Seconds between "DRAW!" and the bot's first shot.
	BOT_REACTION_TIME = NumberRange.new(0.45, 0.8),
	BOT_FIRE_INTERVAL = NumberRange.new(0.55, 0.9),
	BOT_HEADSHOT_CHANCE = 0.25,
	-- Max random aim error per axis, in radians.
	BOT_AIM_SPREAD = math.rad(2),
	BOT_FALSE_START_CHANCE = 0.1,
	-- After the draw the bot picks a new strafe (left / right / stand) this often.
	BOT_STRAFE_INTERVAL = NumberRange.new(0.6, 1.2),
	-- Chance to jump each time it picks a new strafe.
	BOT_JUMP_CHANCE = 0.2,
}

return ServerConfig
