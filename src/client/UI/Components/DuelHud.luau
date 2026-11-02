--!strict
--[[
	Duel HUD: countdown / DRAW! / FALSE START banner, holster hint, crosshair, revolver
	cylinder (ammo pips + reloading / disarmed) and round score. Lives in its own ScreenGui with
	IgnoreGuiInset so the crosshair sits on the exact viewport centre the camera aims through.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Types)
local useCharm = require(script.Parent.Parent.useCharm)

local Children = Fusion.Children

export type Banner = { Text: string, Kind: string }

export type Props = {
	Parent: Instance,
	Phase: Types.Getter<string>,
	Banner: Types.Getter<Banner>,
	Ammo: Types.Getter<number>,
	Reloading: Types.Getter<boolean>,
	Disarmed: Types.Getter<boolean>,
	Holstered: Types.Getter<boolean>,
	Round: Types.Getter<number>,
	MyScore: Types.Getter<number>,
	OpponentScore: Types.Getter<number>,
	OpponentName: Types.Getter<string>,
}

local RED = Color3.fromRGB(235, 70, 60)
local BANNER_COLORS: { [string]: Color3 } = {
	Countdown = Theme.Colors.Text,
	Draw = Theme.Colors.Accent,
	Penalty = RED,
	Win = Color3.fromRGB(120, 220, 110),
	Lose = RED,
	Neutral = Theme.Colors.Text,
}
local PIP_EMPTY = Color3.fromRGB(60, 55, 50)

local function Crosshair(scope: Types.Scope, visible: any)
	-- Typed as any: Children accepts nested arrays, but mixed with Instances the literal would be
	-- inferred as { Instance }.
	local ticks: any = {}
	local tickLength, gap = 7, 4
	for _, direction in
		{ Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) }
	do
		local horizontal = direction.Y == 0
		table.insert(
			ticks,
			scope:New("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(
					0.5,
					direction.X * (gap + tickLength / 2),
					0.5,
					direction.Y * (gap + tickLength / 2)
				),
				Size = if horizontal
					then UDim2.fromOffset(tickLength, 2)
					else UDim2.fromOffset(2, tickLength),
				BackgroundColor3 = Theme.Colors.Text,
				BorderSizePixel = 0,

				[Children] = {
					scope:New("UIStroke")({ Thickness = 1, Transparency = 0.4 }),
				},
			})
		)
	end

	return scope:New("Frame")({
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Visible = visible,

		[Children] = {
			ticks,
			scope:New("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(3, 3),
				BackgroundColor3 = Theme.Colors.Accent,
				BorderSizePixel = 0,
			}),
		},
	})
end

local function AmmoDisplay(
	scope: Types.Scope,
	ammo: any,
	reloading: any,
	disarmed: any,
	visible: any
)
	local pips: any = {}
	for index = 1, DuelConfig.MAX_AMMO do
		table.insert(
			pips,
			scope:New("Frame")({
				LayoutOrder = index,
				Size = UDim2.fromOffset(18, 18),
				BackgroundColor3 = scope:Computed(function(use)
					return if not use(disarmed)
							and not use(reloading)
							and use(ammo) >= index
						then Theme.Colors.Accent
						else PIP_EMPTY
				end),

				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
					scope:New("UIStroke")({ Thickness = 1.5, Color = Color3.fromRGB(20, 16, 12) }),
				},
			})
		)
	end

	return scope:New("Frame")({
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(170, 64),
		BackgroundColor3 = Theme.Colors.Surface,
		BackgroundTransparency = 0.2,
		Visible = visible,

		[Children] = {
			scope:New("UICorner")({ CornerRadius = Theme.CornerRadius }),
			scope:New("TextLabel")({
				Position = UDim2.fromOffset(0, 6),
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				FontFace = Theme.Font,
				TextSize = Theme.TextSize.Body,
				TextColor3 = scope:Computed(function(use)
					return if use(disarmed) or use(reloading) then RED else Theme.Colors.Text
				end),
				Text = scope:Computed(function(use)
					return if use(disarmed)
						then "DISARMED"
						elseif use(reloading) then "RELOADING..."
						else `{use(ammo)} / {DuelConfig.MAX_AMMO}`
				end),
			}),
			scope:New("Frame")({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,

				[Children] = {
					scope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					pips,
				},
			}),
		},
	})
end

local function DuelHud(scope: Types.Scope, props: Props)
	local phase = useCharm(scope, props.Phase)
	local banner = useCharm(scope, props.Banner)
	local ammo = useCharm(scope, props.Ammo)
	local reloading = useCharm(scope, props.Reloading)
	local disarmed = useCharm(scope, props.Disarmed)
	local holstered = useCharm(scope, props.Holstered)
	local round = useCharm(scope, props.Round)
	local myScore = useCharm(scope, props.MyScore)
	local opponentScore = useCharm(scope, props.OpponentScore)
	local opponentName = useCharm(scope, props.OpponentName)

	local inDuel = scope:Computed(function(use)
		return use(phase) ~= "Idle"
	end)

	return scope:New("ScreenGui")({
		Name = "DuelHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = props.Parent,

		[Children] = {
			scope:New("TextLabel")({
				Name = "Banner",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.3),
				Size = UDim2.new(1, 0, 0, 96),
				BackgroundTransparency = 1,
				FontFace = Theme.Font,
				TextSize = 80,
				TextStrokeTransparency = 0.2,
				TextColor3 = scope:Computed(function(use)
					return BANNER_COLORS[use(banner).Kind] or Theme.Colors.Text
				end),
				Text = scope:Computed(function(use)
					return use(banner).Text
				end),
			}),

			scope:New("TextLabel")({
				Name = "HolsterHint",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.3, 56),
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				FontFace = Theme.Font,
				TextSize = Theme.TextSize.Title,
				TextStrokeTransparency = 0.3,
				TextColor3 = Theme.Colors.Accent,
				Text = if UserInputService.TouchEnabled
						and not UserInputService.KeyboardEnabled
					then "HOLD READY - don't let go before the DRAW!"
					else "HOLD SHIFT - don't let go before the DRAW!",
				Visible = scope:Computed(function(use)
					return use(phase) == "Countdown"
				end),
			}),

			scope:New("TextLabel")({
				Name = "Score",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 64),
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = Theme.Colors.Surface,
				BackgroundTransparency = 0.2,
				FontFace = Theme.Font,
				TextSize = Theme.TextSize.Title,
				TextColor3 = Theme.Colors.Text,
				Visible = inDuel,
				Text = scope:Computed(function(use)
					return `ROUND {use(round)}   YOU {use(myScore)} - {use(opponentScore)} {use(
						opponentName
					)}`
				end),

				[Children] = {
					scope:New("UICorner")({ CornerRadius = Theme.CornerRadius }),
					scope:New("UIPadding")({
						PaddingTop = Theme.Padding,
						PaddingBottom = Theme.Padding,
						PaddingLeft = UDim.new(0, 14),
						PaddingRight = UDim.new(0, 14),
					}),
				},
			}),

			Crosshair(
				scope,
				scope:Computed(function(use)
					local current = use(phase)
					return (current == "Countdown" or current == "Drawn") and not use(holstered)
				end)
			),

			AmmoDisplay(scope, ammo, reloading, disarmed, inDuel),
		},
	})
end

return DuelHud
