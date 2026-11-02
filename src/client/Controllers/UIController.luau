--!strict
--[[
	Mounts the Fusion UI tree (UI/App.luau) into PlayerGui.

	Conventions:
	- State lives in Charm (controllers expose getters such as DataController:Select("Cash")).
	- Components are functions (scope, props) -> Instance that receive Charm getters in props and
	  turn them into Fusion state with useCharm, so subscriptions die with the component's scope.
	- Components never write game state directly; they call controller methods.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)
local App = require(script.Parent.Parent.UI.App)
local DataController = require(script.Parent.DataController)
local DuelStateController = require(script.Parent.DuelStateController)
local NotificationController = require(script.Parent.NotificationController)

local UIController = {
	Priority = 60,
	Dependencies = { "DataController", "DuelStateController", "NotificationController" },
}

local scope = Fusion.scoped(Fusion)

-- Root scope; derive child scopes from it (scope:innerScope()) for UI created at runtime.
function UIController:GetScope()
	return scope
end

function UIController:OnStart()
	App(scope, {
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		Cash = DataController:Select("Cash"),
		Announcements = NotificationController.Announcements,
		Duel = {
			Phase = DuelStateController.Phase,
			Banner = DuelStateController.Banner,
			Ammo = DuelStateController.Ammo,
			Reloading = DuelStateController.Reloading,
			Disarmed = DuelStateController.Disarmed,
			Holstered = DuelStateController.Holstered,
			Round = DuelStateController.Round,
			MyScore = DuelStateController.MyScore,
			OpponentScore = DuelStateController.OpponentScore,
			OpponentName = DuelStateController.OpponentName,
		},
	})
	print("[Skoobi/Client] UI mounted")
end

return UIController
