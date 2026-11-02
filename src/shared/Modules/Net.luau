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

		-- Duel: server -> client. A round's countdown is starting.
		StartDuelSequence = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				round = ByteNet.uint8,
				countdown = ByteNet.uint8,
				myScore = ByteNet.uint8,
				opponentScore = ByteNet.uint8,
				opponent = ByteNet.optional(ByteNet.inst),
			}),
		}),

		-- Duel: server -> client. "DRAW!"; penalized players can't fire for lockSeconds.
		DrawSignal = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				penalized = ByteNet.bool,
				lockSeconds = ByteNet.float32,
			}),
		}),

		-- Duel: client -> server. Whether the holster key is held.
		HolsterState = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.bool,
		}),

		-- Duel: client -> server. A hitscan shot from the muzzle as the shooter sees it, along a
		-- unit direction toward the crosshair target.
		FireShot = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				origin = ByteNet.vec3,
				direction = ByteNet.vec3,
			}),
		}),

		-- Duel: client -> server. Where the drawn arm points, as a unit vector in UpperTorso space.
		AimUpdate = ByteNet.definePacket({
			reliabilityType = "unreliable",
			value = ByteNet.struct({
				direction = ByteNet.vec3,
			}),
		}),

		-- Duel: server -> both duelists. Result of a shot, for tracers and sounds.
		ShotFired = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				shooter = ByteNet.optional(ByteNet.inst),
				origin = ByteNet.vec3,
				hitPosition = ByteNet.vec3,
				hit = ByteNet.bool,
				headshot = ByteNet.bool,
			}),
		}),

		-- Duel: server -> all clients. Limb segments (plus anything worn on them) were shot off and
		-- hidden; clients animate a non-colliding copy flying along velocity. parts[1] is the root.
		LimbSevered = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				parts = ByteNet.array(ByteNet.inst),
				velocity = ByteNet.vec3,
				spin = ByteNet.vec3,
			}),
		}),

		-- Duel: server -> client. The local player's revolver state.
		AmmoChanged = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				ammo = ByteNet.uint8,
				reloading = ByteNet.bool,
			}),
		}),

		-- Duel: server -> client. A round finished; winner is nil for a timed-out round.
		RoundEnded = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				winner = ByteNet.optional(ByteNet.inst),
				myScore = ByteNet.uint8,
				opponentScore = ByteNet.uint8,
				matchOver = ByteNet.bool,
			}),
		}),
	}
end)
