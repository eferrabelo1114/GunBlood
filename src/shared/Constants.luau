--!strict
--[[
	Shared configuration values for WesternDuel. Replicated to clients: never put
	secrets or server-only settings here (use ServerScriptService.Server.ServerConfig).
]]

local Constants = {
	-- Character spawn / respawn
	RESPAWN_DELAY = 5,
	CHARACTER_LOAD_MAX_RETRIES = 3,
	CHARACTER_LOAD_RETRY_DELAY = 1,

	-- Default service/controller Priority when unset
	DEFAULT_PRIORITY = 100,

	-- Client error reports are truncated to these lengths before sending
	CLIENT_ERROR_MAX_MESSAGE = 300,
	CLIENT_ERROR_MAX_STACK = 1000,
}

return Constants
