--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Types)
local useCharm = require(script.Parent.Parent.useCharm)

local Children = Fusion.Children

export type Announcement = {
	Id: number,
	Text: string,
}

export type Props = {
	Announcements: Types.Getter<{ Announcement }>,
}

local function AnnouncementFeed(scope: Types.Scope, props: Props)
	local announcements = useCharm(scope, props.Announcements)

	-- Typed as any: Children accepts state objects, but mixed with Instances the array literal
	-- would be inferred as { Instance }.
	local labels: any = scope:ForValues(
		announcements,
		function(_, innerScope: Types.Scope, announcement: Announcement)
			return innerScope:New("TextLabel")({
				Name = `Announcement{announcement.Id}`,
				LayoutOrder = announcement.Id,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Theme.Colors.Surface,
				BackgroundTransparency = 0.15,
				FontFace = Theme.Font,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Colors.Text,
				TextWrapped = true,
				Text = announcement.Text,

				[Children] = {
					innerScope:New("UICorner")({ CornerRadius = Theme.CornerRadius }),
					innerScope:New("UIPadding")({
						PaddingTop = Theme.Padding,
						PaddingBottom = Theme.Padding,
						PaddingLeft = Theme.Padding,
						PaddingRight = Theme.Padding,
					}),
				},
			})
		end
	)

	return scope:New("Frame")({
		Name = "AnnouncementFeed",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

		[Children] = {
			scope:New("UIListLayout")({
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
			labels,
		},
	})
end

return AnnouncementFeed
