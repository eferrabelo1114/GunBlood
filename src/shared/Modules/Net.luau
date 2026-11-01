--!strict
local ByteNet = require(game:GetService("ReplicatedStorage").Shared.Packages.bytenet)

return ByteNet.defineNamespace("SkoobNet", function()
	return {
		-- Client -> server. The server must consume these through NetGuard.Listen, never .listen directly.
		ClientReady = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.bool,
		}),

		ClientError = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				message = ByteNet.string,
				stack = ByteNet.string,
			}),
		}),

		-- Server -> client. Full profile snapshot, sent once when the profile loads.
		-- Uses unknown so ProfileTemplate can evolve without changing the packet shape.
		PlayerData = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.unknown,
		}),

		-- Server -> client. Batched once per frame: { { path, value }, ... } applied in order.
		PlayerDataChanged = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.unknown,
		}),

		-- Server -> client. charm-sync payloads for SharedAtoms.
		StateSync = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.unknown,
		}),

		Announcement = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				text = ByteNet.string,
				duration = ByteNet.uint16,
			}),
		}),
	}
end)
