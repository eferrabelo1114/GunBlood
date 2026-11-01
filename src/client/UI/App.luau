--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)
local AnnouncementFeed = require(script.Parent.Components.AnnouncementFeed)
local CurrencyDisplay = require(script.Parent.Components.CurrencyDisplay)
local Types = require(script.Parent.Types)

local Children = Fusion.Children

export type Props = {
	Parent: Instance,
	Cash: Types.Getter<number?>,
	Announcements: Types.Getter<{ AnnouncementFeed.Announcement }>,
}

local function App(scope: Types.Scope, props: Props)
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
