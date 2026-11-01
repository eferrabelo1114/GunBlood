--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[Skoobi/Server] Booting...")

-- SETTINGS
Players.CharacterAutoLoads = false
print("[Skoobi/Server] CharacterAutoLoads disabled")

-- REQUIRE DEPENDENCIES
require(ReplicatedStorage.Shared.Modules.Net)
print("[Skoobi/Server] Net (ByteNet) ready")

local FrameworkLoader = require(ReplicatedStorage.Shared.Modules.FrameworkLoader)
local ServerState = require(script.ServerState)

FrameworkLoader.LoadAll(script.Services)
ServerState:SetReady()

print("[Skoobi/Server] ✓ Game ready and initialized")
