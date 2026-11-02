--!strict
--[[
	Shared type definitions for WesternDuel services and controllers.
]]

local ProfileTemplate = require(script.Parent.Data.ProfileTemplate)

export type Module = {
	Priority: number?,
	-- Names of modules whose Init must run before this one's.
	Dependencies: { string }?,
	Init: ((self: any) -> ())?,
	OnStart: ((self: any) -> ())?,
	[string]: any,
}

export type Service = Module
export type Controller = Module

export type ProfileData = ProfileTemplate.Data

-- A top-level key ("Cash") or a key path ({ "Items", "Sword" }) into ProfileData.
export type DataPath = string | { string | number }

-- Wire format for PlayerDataChanged: { path, value }. A nil value means the key was removed.
export type DataChange = { any }

return {}
