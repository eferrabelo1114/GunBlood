--!strict
--[[
	Client view of the local player's duel, fed by the duel packets. The HUD reads the Charm
	getters; OTSCameraController and PlayerInputController react to PhaseChanged.

	Movement is locked by the server during the countdown and unlocked at the draw; the local
	Humanoid is updated here as well so the unlock is instant instead of waiting on replication.

	Limb loss arrives as character attributes set by the server: Disarmed (shooting arm gone,
	can't fire) and Crawling (a leg gone, slow and prone). Both reset with the next character.

	Phases: Idle (lobby) -> Countdown -> Drawn -> RoundOver -> Countdown ... -> Idle
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Shared.Packages.charm)
local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Signal = require(ReplicatedStorage.Shared.Packages.signal)

export type Phase = "Idle" | "Countdown" | "Drawn" | "RoundOver"
export type BannerKind = "Countdown" | "Draw" | "Penalty" | "Win" | "Lose" | "Neutral"
-- Kind is a BannerKind; typed as string so UI components can accept it without this module.
export type Banner = { Text: string, Kind: string }

local EMPTY_BANNER: Banner = { Text = "", Kind = "Neutral" }

local getPhase, setPhase = Charm.signal("Idle" :: Phase)
local getBanner, setBanner = Charm.signal(EMPTY_BANNER)
local getAmmo, setAmmo = Charm.signal(DuelConfig.MAX_AMMO)
local getReloading, setReloading = Charm.signal(false)
local getRound, setRound = Charm.signal(0)
local getMyScore, setMyScore = Charm.signal(0)
local getOpponentScore, setOpponentScore = Charm.signal(0)
local getOpponentName, setOpponentName = Charm.signal("")
local getDisarmed, setDisarmed = Charm.signal(false)
local getCrawling, setCrawling = Charm.signal(false)
local getHolstered, setHolstered = Charm.signal(false)

local DuelStateController = {
	Priority = 40,
	-- Charm getters
	Phase = getPhase,
	Banner = getBanner,
	Ammo = getAmmo,
	Reloading = getReloading,
	Round = getRound,
	MyScore = getMyScore,
	OpponentScore = getOpponentScore,
	OpponentName = getOpponentName,
	Disarmed = getDisarmed,
	Crawling = getCrawling,
	-- Holding holster (Shift / READY) during the countdown
	Holstered = getHolstered,
	-- (phase: Phase) after every phase change
	PhaseChanged = Signal.new(),
	-- () when the local revolver becomes usable: at the draw, or when a false-start lock ends
	WeaponReady = Signal.new(),
}

local localPlayer = Players.LocalPlayer
local lockedUntil = 0
local bannerToken = 0
local matchToken = 0
local attributeConnections: { RBXScriptConnection } = {}

local function setLocalMovement(walkSpeed: number, jumpPower: number)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.WalkSpeed = walkSpeed
		humanoid.JumpPower = jumpPower
	end
end

local function enterPhase(phase: Phase)
	if phase ~= "Countdown" then
		setHolstered(false)
	end
	setPhase(phase)
	DuelStateController.PhaseChanged:Fire(phase)
end

local function showBanner(text: string, kind: BannerKind, duration: number?)
	bannerToken += 1
	local token = bannerToken
	setBanner({ Text = text, Kind = kind :: string })
	if duration then
		task.delay(duration, function()
			if bannerToken == token then
				setBanner(EMPTY_BANNER)
			end
		end)
	end
end

local function runCountdown(seconds: number)
	bannerToken += 1
	local token = bannerToken
	task.spawn(function()
		for remaining = seconds, 1, -1 do
			if bannerToken ~= token then
				return
			end
			setBanner({ Text = tostring(remaining), Kind = "Countdown" })
			task.wait(1)
		end
	end)
end

local function roundEndBanner(
	winner: Instance?,
	myScore: number,
	opponentScore: number,
	matchOver: boolean
)
	if matchOver then
		if myScore > opponentScore then
			showBanner("YOU WIN THE DUEL!", "Win")
		elseif myScore < opponentScore then
			showBanner("YOU LOSE THE DUEL", "Lose")
		else
			showBanner("THE DUEL IS A DRAW", "Neutral")
		end
	elseif winner == nil then
		showBanner("TIME'S UP", "Neutral")
	elseif winner == localPlayer then
		showBanner("ROUND WON", "Win")
	else
		showBanner("ROUND LOST", "Lose")
	end
end

local function watchCharacter(character: Model)
	for _, connection in attributeConnections do
		connection:Disconnect()
	end
	table.clear(attributeConnections)

	setDisarmed(character:GetAttribute(DuelConfig.DISARMED_ATTRIBUTE) == true)
	setCrawling(character:GetAttribute(DuelConfig.CRAWLING_ATTRIBUTE) == true)

	table.insert(
		attributeConnections,
		character:GetAttributeChangedSignal(DuelConfig.DISARMED_ATTRIBUTE):Connect(function()
			local disarmed = character:GetAttribute(DuelConfig.DISARMED_ATTRIBUTE) == true
			setDisarmed(disarmed)
			if disarmed then
				showBanner("DISARMED!", "Penalty", 2)
			end
		end)
	)
	table.insert(
		attributeConnections,
		character:GetAttributeChangedSignal(DuelConfig.CRAWLING_ATTRIBUTE):Connect(function()
			local crawling = character:GetAttribute(DuelConfig.CRAWLING_ATTRIBUTE) == true
			setCrawling(crawling)
			if crawling then
				setLocalMovement(DuelConfig.CRAWL_WALK_SPEED, 0)
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.HipHeight = DuelConfig.CRAWL_HIP_HEIGHT
					-- Humanoid states run on the owning client, so these only take effect here.
					humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
				showBanner("LEG SHOT - CRAWL!", "Penalty", 2)
			end
		end)
	)
end

function DuelStateController:GetPhase(): Phase
	return Charm.untracked(getPhase) :: any
end

-- Client-side mirror of the server's fire checks, used to avoid sending pointless shots.
function DuelStateController:CanFire(): boolean
	return Charm.untracked(getPhase) == "Drawn"
		and os.clock() >= lockedUntil
		and Charm.untracked(getAmmo) > 0
		and not Charm.untracked(getReloading)
		and not Charm.untracked(getDisarmed)
end

function DuelStateController:IsCrawling(): boolean
	return Charm.untracked(getCrawling)
end

function DuelStateController:SetHolstered(holding: boolean)
	setHolstered(holding and Charm.untracked(getPhase) == "Countdown")
end

function DuelStateController:IsHolstered(): boolean
	return Charm.untracked(getHolstered)
end

function DuelStateController:Init()
	localPlayer.CharacterAdded:Connect(watchCharacter)
	if localPlayer.Character then
		watchCharacter(localPlayer.Character)
	end

	Net.StartDuelSequence.listen(function(value)
		matchToken += 1
		local opponent = value.opponent
		-- Bots arrive as their character model rather than a Player.
		local opponentName = if opponent and opponent:IsA("Player")
			then opponent.DisplayName
			elseif opponent then opponent.Name
			else "Opponent"
		setOpponentName(opponentName)
		setRound(value.round)
		setMyScore(value.myScore)
		setOpponentScore(value.opponentScore)
		lockedUntil = math.huge
		setLocalMovement(0, 0)
		enterPhase("Countdown")
		runCountdown(value.countdown)
	end)

	Net.DrawSignal.listen(function(value)
		lockedUntil = os.clock() + value.lockSeconds
		setLocalMovement(DuelConfig.DRAW_WALK_SPEED, DuelConfig.DRAW_JUMP_POWER)
		enterPhase("Drawn")
		if value.penalized then
			showBanner("FALSE START!", "Penalty", math.max(value.lockSeconds, 1))
			local token = matchToken
			task.delay(value.lockSeconds, function()
				if matchToken == token and Charm.untracked(getPhase) == "Drawn" then
					self.WeaponReady:Fire()
				end
			end)
		else
			showBanner("DRAW!", "Draw", 1)
			self.WeaponReady:Fire()
		end
	end)

	Net.AmmoChanged.listen(function(value)
		setAmmo(value.ammo)
		setReloading(value.reloading)
	end)

	Net.RoundEnded.listen(function(value)
		setMyScore(value.myScore)
		setOpponentScore(value.opponentScore)
		enterPhase("RoundOver")
		roundEndBanner(value.winner, value.myScore, value.opponentScore, value.matchOver)

		if value.matchOver then
			matchToken += 1
			local token = matchToken
			task.delay(DuelConfig.MATCH_END_DELAY, function()
				if matchToken ~= token then
					return
				end
				setBanner(EMPTY_BANNER)
				enterPhase("Idle")
			end)
		end
	end)
end

return DuelStateController
