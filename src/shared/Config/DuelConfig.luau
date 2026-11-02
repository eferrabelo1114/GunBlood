--!strict
--[[
	Tuning values for the quick-draw duel. Replicated to clients; the server is the authority
	for every gameplay number here and clients only use them for presentation.
]]

local SPAWN_A_POSITION = Vector3.new(0, 3, -25)
local SPAWN_B_POSITION = Vector3.new(0, 3, 25)

local DuelConfig = {
	-- Damage
	HEADSHOT_DAMAGE = 100,
	BODY_DAMAGE = 35,
	HEAD_PART_NAME = "Head",

	-- Revolver
	MAX_AMMO = 6,
	RELOAD_TIME = 2,
	FIRE_COOLDOWN = 0.3,
	MAX_RANGE = 300,

	-- Draw
	COUNTDOWN = 3,
	FALSE_START_LOCK = 1.5,
	HOLSTER_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },

	-- Movement after "DRAW!" (locked to 0 during the countdown).
	DRAW_WALK_SPEED = 22,
	DRAW_JUMP_POWER = 55,

	-- Dismemberment: a non-lethal arm/leg hit severs that limb. Losing a leg means crawling;
	-- losing the right (shooting) arm means no more shooting.
	CRAWL_WALK_SPEED = 8,
	CRAWL_HIP_HEIGHT = 0.4,
	SEVERED_LIMB_LIFETIME = 20,
	-- Character attributes set by the server (replicated to every client).
	DISARMED_ATTRIBUTE = "Disarmed",
	CRAWLING_ATTRIBUTE = "Crawling",
	ARM_DRAWN_ATTRIBUTE = "ArmDrawn",
	-- Drawn arm aim: a unit Vector3 in UpperTorso space, set by the server from each player's
	-- AimUpdate (and by bots) so every client can point that arm.
	AIM_DIRECTION_ATTRIBUTE = "AimDirection",
	-- How far the arm may swing from straight ahead; keeps it off the back and out of a T-pose.
	ARM_AIM_MAX_ANGLE = math.rad(70),
	-- Seconds to swing the arm up from the holster at the draw.
	ARM_DRAW_TIME = 0.15,
	-- Higher = the arm tracks the aim more tightly.
	ARM_AIM_SMOOTHING = 25,
	AIM_SEND_RATE = 15,
	-- On parts hidden by a sever: their original transparency, for the clients' flying copies.
	SEVERED_TRANSPARENCY_ATTRIBUTE = "SeveredTransparency",

	-- Match
	ROUNDS_TO_WIN = 2,
	-- Timed-out rounds don't score; the match ends after this many rounds regardless.
	MAX_ROUNDS = 5,
	ROUND_TIMEOUT = 30,
	INTERMISSION = 3,
	MATCH_END_DELAY = 4,
	-- Seconds a player spends in the lobby before the matchmaker may pick them.
	QUEUE_START_DELAY = 3,
	-- Player attribute set by the server while the player is in a match.
	IN_DUEL_ATTRIBUTE = "InDuel",

	-- Map
	STREET_SIZE = Vector3.new(40, 2, 100),
	STREET_CENTER = Vector3.new(0, 0, 0),
	-- Spawn A faces south (+Z) toward Spawn B, Spawn B faces north (-Z) toward Spawn A.
	SPAWN_A = CFrame.lookAt(SPAWN_A_POSITION, SPAWN_B_POSITION),
	SPAWN_B = CFrame.lookAt(SPAWN_B_POSITION, SPAWN_A_POSITION),
	LOBBY_CENTER = Vector3.new(0, 0, 140),
	LOBBY_SIZE = Vector3.new(40, 2, 40),
	-- Name of the folder of invisible arena walls; shots and aim rays ignore it.
	ARENA_BOUNDS_NAME = "Bounds",
	-- Client-side Workspace folder for flying severed-limb copies; shots and aim rays ignore it.
	LIMB_DEBRIS_FOLDER_NAME = "LimbDebris",
	-- How far (studs) a client-reported muzzle may be from the shooter's head on the server
	-- before the server falls back to its own muzzle position.
	MAX_MUZZLE_OFFSET = 8,

	-- Over-the-shoulder camera, relative to the HumanoidRootPart.
	OTS_OFFSET = Vector3.new(2.5, 2, 6),
	OTS_CRAWL_OFFSET = Vector3.new(2, 0.8, 5.5),
	-- While holding holster during the countdown the crosshair hides and the view shakes slightly.
	HOLSTER_SHAKE_ANGLE = math.rad(0.8),
	HOLSTER_SHAKE_FREQUENCY = 6,
	-- Crawling shakes too: CRAWL_SHAKE_IDLE of the holster shake when still, up to
	-- CRAWL_SHAKE_MOVING while dragging along.
	CRAWL_SHAKE_IDLE = 0.4,
	CRAWL_SHAKE_MOVING = 1.2,
	OTS_FOV = 70,
	-- Exponential follow rate; higher is tighter.
	CAMERA_SMOOTHING = 20,
	MOUSE_SENSITIVITY = 0.0035, -- radians per pixel
	TOUCH_SENSITIVITY = 0.006, -- radians per pixel
	PITCH_LIMIT = math.rad(60),
	RECOIL_KICK = math.rad(3),
	-- Exponential decay rate of the recoil kick.
	RECOIL_RECOVERY = 12,

	-- Effects. Empty sound IDs are skipped; set them to rbxassetid://... to enable.
	GUNSHOT_SOUND_ID = "",
	HEADSHOT_SOUND_ID = "",
	DRAW_SOUND_ID = "",
	TRACER_LIFETIME = 0.08,
}

return DuelConfig
