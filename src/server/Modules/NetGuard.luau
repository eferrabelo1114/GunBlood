--!strict
--[[
	Server-side gate for every client -> server packet: per-player rate limiting and payload
	validation. Rejected packets are dropped, reported through NetGuard.Violation, and players
	who keep sending bad traffic are kicked.

	NetGuard.Listen(Net.SomePacket, "SomePacket", {
		MaxPerWindow = 5,
		Window = 1,
		Validate = function(value) return type(value) == "string" and #value < 100 end,
	}, function(value, player) ... end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Packages.signal)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

export type Options = {
	MaxPerWindow: number,
	Window: number?, -- Seconds, defaults to 1
	Validate: ((value: any) -> boolean)?,
}

type Bucket = { Count: number, WindowStart: number }

local NetGuard = {
	-- (player: Player, packetName: string, reason: "RateLimit" | "Invalid")
	Violation = Signal.new(),
}

local buckets: { [Player]: { [string]: Bucket } } = {}
local violations: { [Player]: number } = {}

local function consume(
	player: Player,
	packetName: string,
	maxPerWindow: number,
	window: number
): boolean
	local playerBuckets = buckets[player]
	if playerBuckets == nil then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local now = os.clock()
	local bucket = playerBuckets[packetName]
	if bucket == nil or now - bucket.WindowStart >= window then
		playerBuckets[packetName] = { Count = 1, WindowStart = now }
		return true
	end

	bucket.Count += 1
	return bucket.Count <= maxPerWindow
end

local function reject(player: Player, packetName: string, reason: string)
	local count = (violations[player] or 0) + 1
	violations[player] = count
	NetGuard.Violation:Fire(player, packetName, reason)

	if count == ServerConfig.NETGUARD_KICK_THRESHOLD then
		player:Kick("Too many invalid requests")
	end
end

function NetGuard.Listen(
	packet: any,
	packetName: string,
	options: Options,
	handler: (value: any, player: Player) -> ()
)
	local window = options.Window or 1
	local validate = options.Validate

	packet.listen(function(value: any, player: Player?)
		if player == nil or player.Parent ~= Players then
			return
		end

		if not consume(player, packetName, options.MaxPerWindow, window) then
			reject(player, packetName, "RateLimit")
			return
		end

		if validate then
			local ok, valid = pcall(validate, value)
			if not ok or valid ~= true then
				reject(player, packetName, "Invalid")
				return
			end
		end

		handler(value, player)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	violations[player] = nil
end)

return NetGuard
