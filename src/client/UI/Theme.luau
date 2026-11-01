--!strict

local Theme = {
	Font = Font.fromEnum(Enum.Font.GothamBold),

	Colors = {
		Surface = Color3.fromRGB(24, 24, 32),
		Text = Color3.fromRGB(240, 240, 245),
		Accent = Color3.fromRGB(255, 205, 70),
	},

	TextSize = {
		Body = 18,
		Title = 24,
	},

	CornerRadius = UDim.new(0, 8),
	Padding = UDim.new(0, 8),
}

return Theme
