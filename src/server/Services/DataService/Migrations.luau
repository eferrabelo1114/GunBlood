--!strict
--[[
	Ordered profile migrations. steps[n] upgrades data from DataVersion n - 1 to n.

	Rules:
	- Append only. Never edit, reorder, or remove a step that has shipped.
	- ProfileTemplate.DataVersion must always equal #steps (checked at startup).
	- Steps run on a copy before Reconcile, so new template keys may not exist yet.
	- A step that errors aborts the load; the player's stored data is left untouched.
]]

type Migration = (data: { [string]: any }) -> ()

local steps: { Migration } = {
	-- 1: Baseline for profiles saved before DataVersion existed; Reconcile fills the new keys.
	function(_data) end,
}

export type Status = "Current" | "Migrated" | "Newer" | "Failed"

local Migrations = {
	Latest = #steps,
}

function Migrations.GetVersion(data: { [string]: any }): number
	local version = data.DataVersion
	return if type(version) == "number" then version else 0
end

--[[
	Upgrades `data` in place. Callers pass a copy so a failure cannot corrupt the live profile.
	"Newer" means the data was written by a newer server build and must not be loaded here.
]]
function Migrations.Apply(data: { [string]: any }): (Status, string?)
	local version = Migrations.GetVersion(data)
	if version > Migrations.Latest then
		return "Newer",
			`DataVersion {version} is newer than this server supports ({Migrations.Latest})`
	elseif version == Migrations.Latest then
		return "Current", nil
	end

	for target = version + 1, Migrations.Latest do
		local ok, err = pcall(steps[target] :: any, data)
		if not ok then
			return "Failed", `Migration {target} failed: {err}`
		end
		data.DataVersion = target
	end

	return "Migrated", nil
end

return Migrations
