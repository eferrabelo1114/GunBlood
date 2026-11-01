--!strict
--[[
	Developer products (ProcessReceipt), game pass ownership, and Premium.

	ProcessReceipt is idempotent: each PurchaseId is recorded in the profile together with the
	granted rewards, and PurchaseGranted is only returned once that save has reached the DataStore.
	If anything fails, NotProcessedYet is returned and Roblox retries later (even in a new session);
	the recorded PurchaseId prevents a double grant.

	Custom products: MonetizationService:RegisterProduct(productId, function(player, receipt) ... end)
	during Init. Handlers must validate before mutating (an error after a partial grant is retried).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameEvents = require(ReplicatedStorage.Shared.Modules.GameEvents)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local DataService = require(script.Parent.DataService)
local TelemetryService = require(script.Parent.TelemetryService)

type Profile = DataService.Profile
type ProductHandler = (player: Player, receipt: { [string]: any }) -> ()

local MonetizationService = {
	Priority = 30,
	Dependencies = { "DataService", "TelemetryService" },
}

local Decision = Enum.ProductPurchaseDecision

local productHandlers: { [number]: ProductHandler } = {}
local passCache: { [Player]: { [number]: boolean } } = {}

local function splitPath(path: string): { string }
	return string.split(path, ".")
end

local function grantProduct(player: Player, receipt: { [string]: any })
	local productId = receipt.ProductId
	local handler = productHandlers[productId]
	if handler then
		handler(player, receipt)
		return
	end

	local product = Monetization.DevProducts[productId]
	if product == nil or product.Rewards == nil then
		error(`No handler or rewards configured for product {productId}`)
	end

	for path, amount in product.Rewards do
		local keys = splitPath(path)
		local balance = DataService:Increment(player, keys, amount)
		if balance == nil then
			error(`Could not grant {path} for product {productId}`)
		end
		if #keys == 1 then
			TelemetryService:LogEconomy(
				player,
				Enum.AnalyticsEconomyFlowType.Source,
				path,
				amount,
				balance,
				Enum.AnalyticsEconomyTransactionType.IAP.Name,
				product.Name
			)
		end
	end
end

local function isSaved(savedData: any, purchaseId: string): boolean
	local history = savedData and savedData.PurchaseHistory
	return type(history) == "table" and table.find(history, purchaseId) ~= nil
end

-- Yields until the purchase is confirmed saved (PurchaseGranted) or the session ends (NotProcessedYet).
local function waitForSave(profile: Profile, purchaseId: string): Enum.ProductPurchaseDecision
	if isSaved(profile.LastSavedData, purchaseId) then
		return Decision.PurchaseGranted
	end

	local thread = coroutine.running()
	local finished = false
	local connections: { { Disconnect: (self: any) -> () } } = {}

	local function finish(decision: Enum.ProductPurchaseDecision)
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		task.spawn(thread, decision)
	end

	table.insert(
		connections,
		profile.OnAfterSave:Connect(function(lastSavedData)
			if isSaved(lastSavedData, purchaseId) then
				finish(Decision.PurchaseGranted)
			end
		end)
	)
	table.insert(
		connections,
		profile.OnSessionEnd:Connect(function()
			finish(Decision.NotProcessedYet)
		end)
	)

	profile:Save()
	return coroutine.yield()
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Decision.NotProcessedYet
	end

	local profile = DataService:GetProfileAsync(player)
	if profile == nil or not profile:IsActive() then
		return Decision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	local history = profile.Data.PurchaseHistory

	if table.find(history, purchaseId) == nil then
		local ok, err = pcall(grantProduct :: any, player, receipt)
		if not ok then
			warn(`[MonetizationService] Grant failed for product {receipt.ProductId}: {err}`)
			TelemetryService:Track(
				"PurchaseGrantFailed",
				{ ProductId = receipt.ProductId, Error = tostring(err) },
				player
			)
			return Decision.NotProcessedYet
		end

		while #history >= ServerConfig.PURCHASE_HISTORY_SIZE do
			table.remove(history, 1)
		end
		table.insert(history, purchaseId)

		TelemetryService:Track("ProductPurchased", {
			ProductId = receipt.ProductId,
			PurchaseId = purchaseId,
			Robux = receipt.CurrencySpent,
		}, player)
		GameEvents.ProductGranted:Fire(player, receipt.ProductId)
	end

	return waitForSave(profile, purchaseId)
end

function MonetizationService:RegisterProduct(productId: number, handler: ProductHandler)
	assert(
		productHandlers[productId] == nil,
		`[MonetizationService] Duplicate handler for product {productId}`
	)
	productHandlers[productId] = handler
end

-- Yields on first check per pass per session; cached afterwards. Returns false if the check fails.
function MonetizationService:OwnsGamePass(player: Player, passId: number): boolean
	local cache = passCache[player]
	if cache == nil then
		cache = {}
		passCache[player] = cache
	end

	local cached = cache[passId]
	if cached ~= nil then
		return cached
	end

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		return false
	end

	if player.Parent == Players then
		cache[passId] = owns
	end
	return owns
end

function MonetizationService:OwnsGamePassNamed(player: Player, passName: string): boolean
	local passId = Monetization.GamePasses[passName]
	assert(passId ~= nil, `[MonetizationService] Unknown game pass "{passName}"`)
	return self:OwnsGamePass(player, passId)
end

function MonetizationService:IsPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

function MonetizationService:Init()
	MarketplaceService.ProcessReceipt = processReceipt :: any

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local cache = passCache[player]
		if cache then
			cache[passId] = true
		end
		TelemetryService:Track("GamePassPurchased", { PassId = passId }, player)
		GameEvents.GamePassPurchased:Fire(player, passId)
	end)

	Players.PlayerMembershipChanged:Connect(function(player)
		GameEvents.PremiumChanged:Fire(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return MonetizationService
