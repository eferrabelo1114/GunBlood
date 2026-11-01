--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[Skoobi/Client] Booting...")

-- LOAD DEPENDENCIES
local Net = require(ReplicatedStorage.Shared.Modules.Net)
print("[Skoobi/Client] Net (ByteNet) ready")

local FrameworkLoader = require(ReplicatedStorage.Shared.Modules.FrameworkLoader)

FrameworkLoader.LoadAll(script.Controllers)
Net.ClientReady.send(true)
print("[Skoobi/Client] ClientReady sent to server")

print("[Skoobi/Client] ✓ Game ready and initialized")
