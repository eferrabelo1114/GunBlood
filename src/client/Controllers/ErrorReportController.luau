--!strict
--[[
	Forwards client script errors to the server (TelemetryService). Each unique message is sent
	once per session and the total is capped, staying well inside the server's NetGuard limit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Modules.Net)

local ErrorReportController = {
	Priority = 0,
}

local MAX_REPORTS_PER_SESSION = 20
-- Must stay below the server's ClientError NetGuard limit (5 per 60 seconds).
local MAX_REPORTS_PER_MINUTE = 4

local reported: { [string]: true } = {}
local reportCount = 0
local windowStart = 0
local windowCount = 0

function ErrorReportController:Init()
	ScriptContext.Error:Connect(function(message, stackTrace)
		if reported[message] or reportCount >= MAX_REPORTS_PER_SESSION then
			return
		end

		local now = os.clock()
		if now - windowStart >= 60 then
			windowStart = now
			windowCount = 0
		end
		if windowCount >= MAX_REPORTS_PER_MINUTE then
			return
		end

		windowCount += 1
		reported[message] = true
		reportCount += 1

		Net.ClientError.send({
			message = string.sub(message, 1, Constants.CLIENT_ERROR_MAX_MESSAGE),
			stack = string.sub(stackTrace, 1, Constants.CLIENT_ERROR_MAX_STACK),
		})
	end)
end

return ErrorReportController
