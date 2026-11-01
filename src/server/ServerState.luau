--!strict
--[[
	Server readiness gate. Await this instead of polling globals.
]]

local Promise = require(game:GetService("ReplicatedStorage").Shared.Packages.promise)

local resolveReady: (() -> ())?
local isReady = false

local readyPromise = Promise.new(function(resolve)
	if isReady then
		resolve()
	else
		resolveReady = resolve
	end
end)

local ServerState = {}

function ServerState:IsReady(): boolean
	return isReady
end

function ServerState:SetReady()
	if isReady then
		return
	end
	isReady = true
	if resolveReady then
		resolveReady()
		resolveReady = nil
	end
end

function ServerState:AwaitReady()
	return readyPromise:expect()
end

ServerState.Ready = readyPromise

return ServerState
