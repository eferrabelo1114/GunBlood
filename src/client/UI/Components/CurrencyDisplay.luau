--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Types)
local useCharm = require(script.Parent.Parent.useCharm)

local Children = Fusion.Children

export type Props = {
	Label: string,
	Amount: Types.Getter<number?>,
	LayoutOrder: number?,
}

-- 1234567 -> "1,234,567"
local function formatNumber(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	grouped = string.gsub(grouped, "^,", "")
	return if amount < 0 then `-{grouped}` else grouped
end

local function CurrencyDisplay(scope: Types.Scope, props: Props)
	local amount = useCharm(scope, props.Amount)

	return scope:New("Frame")({
		Name = props.Label,
		LayoutOrder = props.LayoutOrder or 0,
		Size = UDim2.fromOffset(220, 44),
		BackgroundColor3 = Theme.Colors.Surface,
		BackgroundTransparency = 0.1,

		[Children] = {
			scope:New("UICorner")({ CornerRadius = Theme.CornerRadius }),
			scope:New("UIPadding")({
				PaddingLeft = Theme.Padding,
				PaddingRight = Theme.Padding,
			}),
			scope:New("TextLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Theme.Font,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Colors.Accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = scope:Computed(function(use)
					return `{props.Label}: {formatNumber(use(amount) or 0)}`
				end),
			}),
		},
	})
end

return CurrencyDisplay
