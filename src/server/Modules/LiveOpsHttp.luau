--!strict
--[[
	JSON requests to your LiveOps backend (ServerConfig.LIVEOPS_BASE_URL).
	Requires "Allow HTTP Requests" in Game Settings. The API key is read from the HttpService
	secret named ServerConfig.LIVEOPS_SECRET_NAME, so it never appears in code or place files.
]]

local HttpService = game:GetService("HttpService")

local ServerConfig = require(script.Parent.Parent.ServerConfig)

local LiveOpsHttp = {}

local authorization: any = nil
local secretLoaded = false

local function getAuthorization(): any
	if not secretLoaded then
		secretLoaded = true
		local ok, secret = pcall(function()
			return HttpService:GetSecret(ServerConfig.LIVEOPS_SECRET_NAME)
		end)
		if ok then
			authorization = secret:AddPrefix("Bearer ")
		else
			warn(
				`[LiveOpsHttp] Secret "{ServerConfig.LIVEOPS_SECRET_NAME}" unavailable; sending unauthenticated requests`
			)
		end
	end
	return authorization
end

function LiveOpsHttp.IsEnabled(): boolean
	return ServerConfig.LIVEOPS_BASE_URL ~= ""
end

--[[
	Yields. Returns (true, decodedBody?) on a 2xx response, otherwise (false, errorMessage).
]]
function LiveOpsHttp.RequestAsync(method: string, path: string, body: any?): (boolean, any)
	if not LiveOpsHttp.IsEnabled() then
		return false, "LiveOps HTTP is disabled"
	end

	local headers: { [string]: any } = { ["Content-Type"] = "application/json" }
	local auth = getAuthorization()
	if auth ~= nil then
		headers.Authorization = auth
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = ServerConfig.LIVEOPS_BASE_URL .. path,
			Method = method,
			Headers = headers :: any,
			Body = if body ~= nil then HttpService:JSONEncode(body) else nil,
		})
	end)

	if not ok then
		return false, tostring(response)
	elseif not response.Success then
		return false, `HTTP {response.StatusCode} {response.StatusMessage}`
	elseif response.Body == "" then
		return true, nil
	end

	local decoded, result = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	return decoded, result
end

return LiveOpsHttp
