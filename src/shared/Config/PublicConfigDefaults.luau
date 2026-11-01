--!strict
--[[
	Remote config keys visible to clients, with the values used when the backend is unreachable.
	The backend can only override keys declared here (or in the server-only RemoteConfigDefaults),
	and only with a value of the same type.
]]

return {
	MaintenanceMessage = "",
	EventActive = false,
	ShopRotation = "Default",
} :: { [string]: any }
