--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)
local AnnouncementFeed = require(script.Parent.Components.AnnouncementFeed)
local CurrencyDisplay = require(script.Parent.Components.CurrencyDisplay)
local DuelHud = require(script.Parent.Components.DuelHud)
local Types = require(script.Parent.Types)

local Children = Fusion.Children

export type Props = {
	Parent: Instance,
	Cash: Types.Getter<number?>,
	Announcements: Types.Getter<{ AnnouncementFeed.Announcement }>,
	Duel: {
		Phase: Types.Getter<string>,
		Banner: Types.Getter<DuelHud.Banner>,
		Ammo: Types.Getter<number>,
		Reloading: Types.Getter<boolean>,
		Disarmed: Types.Getter<boolean>,
		Holstered: Types.Getter<boolean>,
		Round: Types.Getter<number>,
		MyScore: Types.Getter<number>,
		OpponentScore: Types.Getter<number>,
		OpponentName: Types.Getter<string>,
	},
}

local function App(scope: Types.Scope, props: Props)
	-- Separate ScreenGui (IgnoreGuiInset) so the crosshair matches the camera's aim point.
	DuelHud(scope, {
		Parent = props.Parent,
		Phase = props.Duel.Phase,
		Banner = props.Duel.Banner,
		Ammo = props.Duel.Ammo,
		Reloading = props.Duel.Reloading,
		Disarmed = props.Duel.Disarmed,
		Holstered = props.Duel.Holstered,
		Round = props.Duel.Round,
		MyScore = props.Duel.MyScore,
		OpponentScore = props.Duel.OpponentScore,
		OpponentName = props.Duel.OpponentName,
	})

	return scope:New("ScreenGui")({
		Name = "App",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = props.Parent,

		[Children] = {
			scope:New("Frame")({
				Name = "Hud",
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,

				[Children] = {
					scope:New("UIListLayout")({
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					CurrencyDisplay(scope, {
						Label = "Cash",
						Amount = props.Cash,
						LayoutOrder = 1,
					}),
				},
			}),
			AnnouncementFeed(scope, {
				Announcements = props.Announcements,
			}),
		},
	})
end

return App
