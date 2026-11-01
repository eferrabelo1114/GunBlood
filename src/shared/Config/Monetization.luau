--!strict
--[[
	Developer product and game pass IDs. Shared so client UI can prompt purchases by name.

	Rewards map a profile path ("Cash" or "Items.Sword") to an amount that is added on purchase.
	Products that need custom logic register a handler with MonetizationService:RegisterProduct.
]]

export type DevProduct = {
	Name: string,
	Rewards: { [string]: number }?,
}

local Monetization = {
	DevProducts = {
		-- [1234567890] = { Name = "Cash100", Rewards = { Cash = 100 } },
	} :: { [number]: DevProduct },

	GamePasses = {
		-- VIP = 1234567890,
	} :: { [string]: number },
}

return Monetization
