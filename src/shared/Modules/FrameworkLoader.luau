--!strict
--[[
	Loads Service/Controller ModuleScripts from a folder.

	- Every ModuleScript under the folder that is NOT nested inside another ModuleScript is loaded.
	  Folders can be used for grouping; helpers belong inside their owner module
	  (e.g. DataService/Migrations.luau) and are never loaded as services.
	- Order: Dependencies first, then Priority (lower first, default from Constants), then name.
	- Init runs sequentially and must not yield. OnStart runs in its own thread per module.
	- In Studio every failure errors immediately. Live servers report the failure as an uncaught
	  error (picked up by ScriptContext.Error / telemetry), skip modules whose dependencies failed,
	  and keep running.
]]

local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

type Module = Types.Module
type Entry = { Name: string, Module: Module }

local IS_STUDIO = RunService:IsStudio()
local REALM = if RunService:IsServer() then "Server" else "Client"

local FrameworkLoader = {}

local registry: { [string]: Module } = {}

local function log(message: string)
	print(`[Skoobi/{REALM}] {message}`)
end

local function report(message: string)
	local full = `[FrameworkLoader] {message}`
	if IS_STUDIO then
		error(full, 0)
	end
	task.spawn(error, full, 0)
end

local function collectModuleScripts(root: Instance): { ModuleScript }
	local found: { ModuleScript } = {}

	local function visit(parent: Instance)
		for _, child in parent:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(found, child)
			else
				visit(child)
			end
		end
	end

	visit(root)
	return found
end

local function getPriority(entry: Entry): number
	return entry.Module.Priority or Constants.DEFAULT_PRIORITY
end

local function getDependencies(entry: Entry): { string }
	return entry.Module.Dependencies or {}
end

local function orderEntries(entries: { Entry }): { Entry }
	table.sort(entries, function(a, b)
		local priorityA, priorityB = getPriority(a), getPriority(b)
		if priorityA == priorityB then
			return a.Name < b.Name
		end
		return priorityA < priorityB
	end)

	local byName: { [string]: Entry } = {}
	for _, entry in entries do
		byName[entry.Name] = entry
	end

	local state: { [string]: "visiting" | "done" } = {}
	local ordered: { Entry } = {}
	local chain: { string } = {}

	local function visit(entry: Entry)
		local current = state[entry.Name]
		if current == "done" then
			return
		elseif current == "visiting" then
			report(`Dependency cycle: {table.concat(chain, " -> ")} -> {entry.Name}`)
			return
		end

		state[entry.Name] = "visiting"
		table.insert(chain, entry.Name)
		for _, dependencyName in getDependencies(entry) do
			local dependency = byName[dependencyName]
			if dependency then
				visit(dependency)
			else
				report(`"{entry.Name}" depends on unknown module "{dependencyName}"`)
			end
		end
		table.remove(chain)

		state[entry.Name] = "done"
		table.insert(ordered, entry)
	end

	for _, entry in entries do
		visit(entry)
	end

	return ordered
end

local function findFailedDependency(entry: Entry, failed: { [string]: true }): string?
	for _, dependencyName in getDependencies(entry) do
		if failed[dependencyName] or registry[dependencyName] == nil then
			return dependencyName
		end
	end
	return nil
end

local function runInit(entry: Entry): boolean
	local init = entry.Module.Init
	if init == nil then
		log(`  Init  {entry.Name} (skipped — no Init)`)
		return true
	end

	local thread = coroutine.create(function()
		return xpcall(init, debug.traceback, entry.Module)
	end)
	local _, ok, err = coroutine.resume(thread)

	if coroutine.status(thread) ~= "dead" then
		report(`Init for "{entry.Name}" yielded; move yielding work into OnStart`)
		return true
	elseif not ok then
		report(`Init failed for "{entry.Name}":\n{err}`)
		return false
	end

	log(`  Init  {entry.Name}`)
	return true
end

--[[
	Requires all modules under `folder`, runs Init then OnStart in dependency/Priority order.
	Returns the registry keyed by ModuleScript.Name.
]]
function FrameworkLoader.LoadAll(folder: Instance): { [string]: Module }
	log(`Loading modules from {folder:GetFullName()}...`)
	local entries: { Entry } = {}

	for _, moduleScript in collectModuleScripts(folder) do
		local ok, result = xpcall(function()
			return (require :: any)(moduleScript)
		end, debug.traceback)

		if not ok then
			report(`Failed to require "{moduleScript:GetFullName()}":\n{result}`)
			continue
		end

		if typeof(result) ~= "table" then
			report(`"{moduleScript:GetFullName()}" did not return a table`)
			continue
		end

		if registry[moduleScript.Name] ~= nil then
			report(
				`Duplicate module name "{moduleScript.Name}"; skipping "{moduleScript:GetFullName()}"`
			)
			continue
		end

		registry[moduleScript.Name] = result
		table.insert(entries, { Name = moduleScript.Name, Module = result })
		log(`  Require  {moduleScript.Name}`)
	end

	local ordered = orderEntries(entries)
	local orderNames = table.create(#ordered)
	for index, entry in ordered do
		orderNames[index] = entry.Name
	end
	log(`Boot order: {table.concat(orderNames, " → ")}`)

	local failed: { [string]: true } = {}
	local initCount = 0

	log("Running Init...")
	for _, entry in ordered do
		local failedDependency = findFailedDependency(entry, failed)
		if failedDependency then
			failed[entry.Name] = true
			report(`Skipping "{entry.Name}": dependency "{failedDependency}" failed to load`)
		elseif not runInit(entry) then
			failed[entry.Name] = true
		else
			initCount += 1
		end
	end

	local onStartCount = 0
	log("Starting OnStart...")
	for _, entry in ordered do
		local onStart = entry.Module.OnStart
		if onStart and not failed[entry.Name] then
			onStartCount += 1
			task.spawn(function()
				local ok, err = xpcall(onStart :: any, debug.traceback, entry.Module)
				if not ok then
					report(`OnStart failed for "{entry.Name}":\n{err}`)
				else
					log(`  OnStart  {entry.Name}`)
				end
			end)
		elseif not failed[entry.Name] then
			log(`  OnStart  {entry.Name} (skipped — no OnStart)`)
		end
	end

	local failedCount = 0
	for _ in failed do
		failedCount += 1
	end
	log(
		`Modules loaded: {#entries} | Init ok: {initCount} | OnStart started: {onStartCount} | Failed: {failedCount}`
	)

	return registry
end

--[[
	Runtime lookup of a loaded service/controller by name (this realm only). Prefer requiring
	the module directly inside other modules so the type checker can see its API.
]]
function FrameworkLoader.Get(name: string): any
	local module = registry[name]
	if module == nil then
		error(`[FrameworkLoader] No loaded module named "{name}"`, 2)
	end
	return module
end

return FrameworkLoader
