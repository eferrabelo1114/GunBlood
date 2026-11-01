--!strict
--[[
	Server-only remote config keys (never replicated), with their fallback values.
	Client-visible keys live in ReplicatedStorage.Shared.Config.PublicConfigDefaults.
]]

return {
	CashMultiplier = 1,
	MaxPartySize = 4,
} :: { [string]: any }
