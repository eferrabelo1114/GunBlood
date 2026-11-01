--!strict
--[[
	Single source of truth for player save data. The ProfileData type is derived from this table.

	When changing the shape of existing data: bump DataVersion and append a matching migration
	in ServerScriptService.Server.Services.DataService.Migrations. Adding a new key only needs
	the key here (Reconcile fills it in for existing profiles).

	Store IDs and counts, never Instances, userdata (Vector3, Color3...), or functions.
]]

local ProfileTemplate = {
	DataVersion = 1,

	Cash = 0,
	Items = {} :: { [string]: number }, -- ItemId -> count
	Flags = {} :: { [string]: boolean }, -- Tutorial progress, LiveOps flags, etc.

	-- Recent receipt PurchaseIds; server only and capped (see ServerConfig.PURCHASE_HISTORY_SIZE).
	PurchaseHistory = {} :: { string },

	Meta = {
		FirstJoin = 0, -- Unix seconds
		LastJoin = 0, -- Unix seconds
		JoinCount = 0,
		TotalPlaytime = 0, -- Seconds
	},
}

export type Data = typeof(ProfileTemplate)

return ProfileTemplate
