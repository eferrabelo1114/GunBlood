--!strict
--[[
	Pairs lobby players (FIFO) and runs best-of-3 duels on the single arena. A player who has
	waited alone for BOT_FILL_DELAY seconds is matched against a practice bot (BotService).

	Each round both duelists are respawned onto the duel spots, frozen, and given a fresh
	revolver. A round ends on the first death, a disconnect, or ROUND_TIMEOUT (no score). The
	match ends when someone reaches ROUNDS_TO_WIN, a duelist leaves (the other wins), or after
	MAX_ROUNDS; then players respawn in the lobby and rejoin the back of the queue.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Shared.Packages.promise)
local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Duelist = require(script.Parent.Parent.Modules.Duelist)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local BotService = require(script.Parent.BotService)
local CharacterService = require(script.Parent.CharacterService)
local GunService = require(script.Parent.GunService)

type Duelist = Duelist.Duelist

local MatchmakerService = {
	Priority = 50,
	Dependencies = { "BotService", "CharacterService", "GunService" },
}

local queue: { Player } = {}
local queuedAt: { [Player]: number } = {}
local matchRunning = false

local function isInDuel(player: Player): boolean
	return player:GetAttribute(DuelConfig.IN_DUEL_ATTRIBUTE) == true
end

local function setInDuel(duelist: Duelist, inDuel: boolean)
	local player = Duelist.AsPlayer(duelist)
	if player then
		player:SetAttribute(DuelConfig.IN_DUEL_ATTRIBUTE, if inDuel then true else nil)
	end
end

local function isAvailable(player: Player): boolean
	return Duelist.IsPresent(player)
		and not isInDuel(player)
		and Duelist.GetAliveHumanoid(player) ~= nil
end

local function removeFromQueue(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
	queuedAt[player] = nil
end

local function standingCFrame(character: Model, spawnCFrame: CFrame): CFrame
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local streetTop = DuelConfig.STREET_CENTER.Y + DuelConfig.STREET_SIZE.Y / 2
	local height = 3
	if humanoid and root and root:IsA("BasePart") then
		local legHeight = if humanoid.RigType == Enum.HumanoidRigType.R15
			then humanoid.HipHeight
			else 2
		height = legHeight + root.Size.Y / 2
	end
	local position = spawnCFrame.Position
	return spawnCFrame.Rotation + Vector3.new(position.X, streetTop + height + 0.1, position.Z)
end

local function placeDuelist(duelist: Duelist, spawnCFrame: CFrame, opponent: Duelist)
	local bot = Duelist.AsBot(duelist)
	local spawnPromise = if bot
		then BotService:SpawnAsync(bot, Duelist.AsPlayer(opponent))
		else CharacterService:SpawnAsync(duelist :: Player)

	return spawnPromise:andThen(function(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.UseJumpPower = true
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			-- Characters face the camera yaw (players) or their target (bots) instead.
			humanoid.AutoRotate = false
		end
		character:PivotTo(standingCFrame(character, spawnCFrame))
	end)
end

local function unlockMovement(duelist: Duelist)
	local humanoid = Duelist.GetAliveHumanoid(duelist)
	if humanoid then
		humanoid.WalkSpeed = DuelConfig.DRAW_WALK_SPEED
		humanoid.JumpPower = DuelConfig.DRAW_JUMP_POWER
	end
end

local function sendRoundStart(
	duelist: Duelist,
	opponent: Duelist,
	round: number,
	scores: { [Duelist]: number }
)
	local player = Duelist.AsPlayer(duelist)
	if player == nil then
		return
	end
	Net.StartDuelSequence.sendTo({
		round = round,
		countdown = DuelConfig.COUNTDOWN,
		myScore = scores[duelist],
		opponentScore = scores[opponent],
		opponent = Duelist.GetInstance(opponent),
	}, player)
end

local function sendRoundEnd(
	duelist: Duelist,
	opponent: Duelist,
	winner: Duelist?,
	scores: { [Duelist]: number },
	matchOver: boolean
)
	local player = Duelist.AsPlayer(duelist)
	if player == nil or not Duelist.IsPresent(player) then
		return
	end
	Net.RoundEnded.sendTo({
		winner = if winner then Duelist.GetInstance(winner) else nil,
		myScore = scores[duelist],
		opponentScore = scores[opponent],
		matchOver = matchOver,
	}, player)
end

-- Resolves with the round winner, or nil if the round timed out.
local function playRound(duelistA: Duelist, duelistB: Duelist): Duelist?
	local humanoidA = Duelist.GetAliveHumanoid(duelistA)
	local humanoidB = Duelist.GetAliveHumanoid(duelistB)
	if humanoidA == nil or humanoidB == nil then
		return if humanoidA then duelistA elseif humanoidB then duelistB else nil
	end

	local outcome = Promise.race({
		Promise.fromEvent(humanoidA.Died):andThenReturn(duelistB),
		Promise.fromEvent(humanoidB.Died):andThenReturn(duelistA),
		Promise.fromEvent(Players.PlayerRemoving, function(player: Player)
			return player == duelistA or player == duelistB
		end):andThen(function(leaver: Player)
			return if leaver == duelistA then duelistB else duelistA
		end),
		Promise.delay(DuelConfig.COUNTDOWN + DuelConfig.ROUND_TIMEOUT):andThenReturn(nil),
	})

	local drawThread = task.delay(DuelConfig.COUNTDOWN, function()
		GunService:OpenFire()
		unlockMovement(duelistA)
		unlockMovement(duelistB)
	end)

	local ok, winner = outcome:await()
	if coroutine.status(drawThread) == "suspended" then
		task.cancel(drawThread)
	end
	GunService:EndRound()

	return if ok then winner else nil
end

local function runMatch(duelistA: Duelist, duelistB: Duelist)
	local nameA, nameB = Duelist.GetName(duelistA), Duelist.GetName(duelistB)
	print(`[Skoobi/Server] Duel starting: {nameA} vs {nameB}`)
	setInDuel(duelistA, true)
	setInDuel(duelistB, true)

	local scores: { [Duelist]: number } = { [duelistA] = 0, [duelistB] = 0 }
	local round = 0

	while round < DuelConfig.MAX_ROUNDS do
		if not (Duelist.IsPresent(duelistA) and Duelist.IsPresent(duelistB)) then
			break
		end

		local spawned = Promise.all({
			placeDuelist(duelistA, DuelConfig.SPAWN_A, duelistB),
			placeDuelist(duelistB, DuelConfig.SPAWN_B, duelistA),
		}):await()
		if not spawned then
			warn("[MatchmakerService] Failed to spawn duelists; ending match")
			break
		end

		round += 1
		GunService:PrepareRound(duelistA, duelistB)
		sendRoundStart(duelistA, duelistB, round, scores)
		sendRoundStart(duelistB, duelistA, round, scores)
		for _, pair in { { duelistA, duelistB }, { duelistB, duelistA } } do
			local bot = Duelist.AsBot(pair[1])
			if bot then
				BotService:RunRound(bot, pair[2])
			end
		end

		local winner = playRound(duelistA, duelistB)
		local forfeited = not (Duelist.IsPresent(duelistA) and Duelist.IsPresent(duelistB))
		if winner then
			scores[winner] += 1
		end

		local matchOver = forfeited
			or round >= DuelConfig.MAX_ROUNDS
			or (winner ~= nil and scores[winner] >= DuelConfig.ROUNDS_TO_WIN)
		sendRoundEnd(duelistA, duelistB, winner, scores, matchOver)
		sendRoundEnd(duelistB, duelistA, winner, scores, matchOver)

		if matchOver then
			task.wait(DuelConfig.MATCH_END_DELAY)
			break
		end
		task.wait(DuelConfig.INTERMISSION)
	end

	print(`[Skoobi/Server] Duel over: {nameA} {scores[duelistA]} - {scores[duelistB]} {nameB}`)
end

local function returnToLobby(duelists: { Duelist })
	GunService:Clear()
	for _, duelist in duelists do
		local bot = Duelist.AsBot(duelist)
		if bot then
			BotService:Remove(bot)
			continue
		end

		local player = duelist :: Player
		if Duelist.IsPresent(player) then
			setInDuel(player, false)
			CharacterService:SpawnAsync(player):catch(function(err)
				warn(`[MatchmakerService] Failed to return {player.Name} to the lobby: {err}`)
			end)
		end
	end
	matchRunning = false
end

local function tryStartMatch()
	if matchRunning then
		return
	end

	local picked: { Player } = {}
	while #picked < 2 and #queue > 0 do
		local player = table.remove(queue, 1) :: Player
		if isAvailable(player) then
			table.insert(picked, player)
		else
			queuedAt[player] = nil
		end
	end

	local duelists: { Duelist } = {}
	if #picked == 2 then
		duelists = { picked[1], picked[2] }
	elseif
		#picked == 1
		and ServerConfig.BOTS_ENABLED
		and os.clock() - (queuedAt[picked[1]] or math.huge) >= ServerConfig.BOT_FILL_DELAY
	then
		duelists = { picked[1], BotService:Create() }
	else
		for index = #picked, 1, -1 do
			table.insert(queue, 1, picked[index])
		end
		return
	end

	for _, player in picked do
		queuedAt[player] = nil
	end

	matchRunning = true
	task.spawn(function()
		local ok, err = pcall(function()
			runMatch(duelists[1], duelists[2])
		end)
		returnToLobby(duelists)
		if not ok then
			task.spawn(error, `[MatchmakerService] Match crashed: {err}`, 0)
		end
		task.delay(DuelConfig.QUEUE_START_DELAY, tryStartMatch)
	end)
end

local function enqueue(player: Player)
	if isInDuel(player) or table.find(queue, player) then
		return
	end
	table.insert(queue, player)
	queuedAt[player] = os.clock()
	task.delay(DuelConfig.QUEUE_START_DELAY, tryStartMatch)
	if ServerConfig.BOTS_ENABLED then
		task.delay(ServerConfig.BOT_FILL_DELAY + 0.1, tryStartMatch)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		enqueue(player)
	end)
	if player.Character then
		enqueue(player)
	end
end

function MatchmakerService:Init()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(removeFromQueue)
end

return MatchmakerService
