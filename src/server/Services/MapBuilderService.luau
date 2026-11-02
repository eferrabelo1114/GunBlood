--!strict
--[[
	Procedurally builds the Western showdown street (Workspace.Arena) and the lobby
	(Workspace.Lobby). The lobby holds the only SpawnLocation, so every (re)spawn lands there and
	MatchmakerService moves duelists onto the street.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DuelConfig = require(ReplicatedStorage.Shared.Config.DuelConfig)

local MapBuilderService = {
	Priority = 5,
}

local DESERT_SAND = Color3.fromRGB(237, 201, 175)
local DESERT_GROUND = Color3.fromRGB(205, 160, 110)
local DARK_WOOD = Color3.fromRGB(60, 38, 22)
local MID_WOOD = Color3.fromRGB(110, 70, 40)
local WINDOW = Color3.fromRGB(30, 26, 22)

local FACADE_DEPTH = 10
local BUILDING_WIDTH = 16
local BUILDING_GAP = 2
local PORCH_DEPTH = 4
local PORCH_HEIGHT = 9

type BuildingStyle = { Sign: string, Height: number, Color: Color3 }

local BUILDING_STYLES: { BuildingStyle } = {
	{ Sign = "SALOON", Height = 20, Color = Color3.fromRGB(128, 78, 44) },
	{ Sign = "SHERIFF", Height = 16, Color = Color3.fromRGB(150, 110, 70) },
	{ Sign = "BANK", Height = 22, Color = Color3.fromRGB(105, 66, 46) },
	{ Sign = "HOTEL", Height = 24, Color = Color3.fromRGB(140, 92, 58) },
	{ Sign = "GENERAL STORE", Height = 17, Color = Color3.fromRGB(118, 84, 52) },
}

local function part(parent: Instance, name: string, props: { [string]: any }): Part
	local newPart = Instance.new("Part")
	newPart.Name = name
	newPart.Anchored = true
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		newPart.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "Shape" then
			(newPart :: any)[key] = value
		end
	end
	newPart.Parent = parent
	return newPart
end

local function addSign(signPart: Part, text: string, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = signPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(Enum.Font.Fondamento)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 225, 180)
	label.Text = text
	label.Parent = gui
end

-- side = 1 builds on the +X side of the street, -1 on the -X side.
local function buildFacade(parent: Instance, style: BuildingStyle, side: number, z: number)
	local streetTop = DuelConfig.STREET_CENTER.Y + DuelConfig.STREET_SIZE.Y / 2
	local frontX = side * DuelConfig.STREET_SIZE.X / 2
	local towardStreet = -side
	local streetFace = if side > 0 then Enum.NormalId.Left else Enum.NormalId.Right

	local model = Instance.new("Model")
	model.Name = style.Sign
	model.Parent = parent

	part(model, "Body", {
		Size = Vector3.new(FACADE_DEPTH, style.Height, BUILDING_WIDTH),
		Position = Vector3.new(frontX + side * FACADE_DEPTH / 2, streetTop + style.Height / 2, z),
		Material = Enum.Material.WoodPlanks,
		Color = style.Color,
	})

	part(model, "Door", {
		Size = Vector3.new(0.4, 7, 4),
		Position = Vector3.new(frontX + towardStreet * 0.1, streetTop + 3.5, z),
		Material = Enum.Material.Wood,
		Color = DARK_WOOD,
	})

	for _, offset in { -4.5, 4.5 } do
		part(model, "Window", {
			Size = Vector3.new(0.4, 3.5, 3),
			Position = Vector3.new(
				frontX + towardStreet * 0.1,
				streetTop + PORCH_HEIGHT + 3.5,
				z + offset
			),
			Material = Enum.Material.Glass,
			Color = WINDOW,
			Transparency = 0.2,
		})
	end

	local porchX = frontX + towardStreet * PORCH_DEPTH / 2
	part(model, "PorchDeck", {
		Size = Vector3.new(PORCH_DEPTH, 0.6, BUILDING_WIDTH),
		Position = Vector3.new(porchX, streetTop + 0.3, z),
		Material = Enum.Material.WoodPlanks,
		Color = MID_WOOD,
	})
	part(model, "PorchRoof", {
		Size = Vector3.new(PORCH_DEPTH + 0.5, 0.5, BUILDING_WIDTH),
		Position = Vector3.new(porchX, streetTop + PORCH_HEIGHT, z),
		Material = Enum.Material.WoodPlanks,
		Color = DARK_WOOD,
	})
	for _, offset in { -1, 1 } do
		part(model, "PorchPost", {
			Size = Vector3.new(0.6, PORCH_HEIGHT, 0.6),
			Position = Vector3.new(
				frontX + towardStreet * (PORCH_DEPTH - 0.3),
				streetTop + PORCH_HEIGHT / 2,
				z + offset * (BUILDING_WIDTH / 2 - 0.5)
			),
			Material = Enum.Material.Wood,
			Color = DARK_WOOD,
		})
	end

	local sign = part(model, "Sign", {
		Size = Vector3.new(0.4, 3, BUILDING_WIDTH - 4),
		Position = Vector3.new(frontX + towardStreet * 0.3, streetTop + style.Height - 2.5, z),
		Material = Enum.Material.Wood,
		Color = DARK_WOOD,
	})
	addSign(sign, style.Sign, streetFace)
end

local function buildProps(parent: Instance)
	local streetTop = DuelConfig.STREET_CENTER.Y + DuelConfig.STREET_SIZE.Y / 2
	local halfWidth = DuelConfig.STREET_SIZE.X / 2

	local crates = {
		Vector3.new(-(halfWidth - 5.5), 0, -30),
		Vector3.new(-(halfWidth - 5.5), 0, 14),
		Vector3.new(halfWidth - 5.5, 0, 33),
		Vector3.new(halfWidth - 5.5, 0, -38),
	}
	for _, position in crates do
		part(parent, "Crate", {
			Size = Vector3.new(3, 3, 3),
			Position = position + Vector3.new(0, streetTop + 1.5, 0),
			Material = Enum.Material.WoodPlanks,
			Color = MID_WOOD,
		})
	end

	local barrels = {
		Vector3.new(-(halfWidth - 5), 0, -26),
		Vector3.new(halfWidth - 5, 0, 29),
		Vector3.new(-(halfWidth - 5), 0, 40),
	}
	for _, position in barrels do
		part(parent, "Barrel", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.5, 2.6, 2.6),
			CFrame = CFrame.new(position + Vector3.new(0, streetTop + 1.75, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Wood,
			Color = DARK_WOOD,
		})
	end

	-- Distant mesas so the over-the-shoulder view has a horizon.
	for _, z in { -1, 1 } do
		part(parent, "Mesa", {
			Size = Vector3.new(160, 45, 30),
			Position = Vector3.new(0, 20, z * 220),
			Material = Enum.Material.Sandstone,
			Color = Color3.fromRGB(176, 100, 62),
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Invisible walls behind the building rows and across both street ends, so duelists can't run
-- off through the gaps between buildings. Collidable parts can't disable CanQuery, so shot and
-- aim raycasts exclude this folder instead.
local function buildBounds(parent: Instance)
	local bounds = Instance.new("Folder")
	bounds.Name = DuelConfig.ARENA_BOUNDS_NAME
	bounds.Parent = parent

	local center = DuelConfig.STREET_CENTER
	local streetTop = center.Y + DuelConfig.STREET_SIZE.Y / 2
	local halfWidth = DuelConfig.STREET_SIZE.X / 2 + FACADE_DEPTH + 0.5
	local halfLength = DuelConfig.STREET_SIZE.Z / 2
	local height = 40
	local y = streetTop + height / 2

	for _, side in { -1, 1 } do
		part(bounds, "SideWall", {
			Size = Vector3.new(1, height, DuelConfig.STREET_SIZE.Z + 2),
			Position = Vector3.new(center.X + side * halfWidth, y, center.Z),
			Transparency = 1,
			CastShadow = false,
		})
		part(bounds, "EndWall", {
			Size = Vector3.new(halfWidth * 2 + 1, height, 1),
			Position = Vector3.new(center.X, y, center.Z + side * (halfLength + 0.5)),
			Transparency = 1,
			CastShadow = false,
		})
	end
end

local function buildArena()
	local arena = Instance.new("Model")
	arena.Name = "Arena"

	part(arena, "DesertGround", {
		Size = Vector3.new(600, 2, 600),
		Position = Vector3.new(0, -1.5, 0),
		Material = Enum.Material.Sand,
		Color = DESERT_GROUND,
	})

	part(arena, "Street", {
		Size = DuelConfig.STREET_SIZE,
		Position = DuelConfig.STREET_CENTER,
		Material = Enum.Material.Sand,
		Color = DESERT_SAND,
	})

	local streetTop = DuelConfig.STREET_CENTER.Y + DuelConfig.STREET_SIZE.Y / 2
	for _, spawnCFrame in { DuelConfig.SPAWN_A, DuelConfig.SPAWN_B } do
		part(arena, "DuelMark", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 5, 5),
			CFrame = CFrame.new(spawnCFrame.Position.X, streetTop + 0.05, spawnCFrame.Position.Z)
				* CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(120, 85, 55),
			CanCollide = false,
			CanQuery = false,
		})
	end

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = arena

	local halfLength = DuelConfig.STREET_SIZE.Z / 2
	local step = BUILDING_WIDTH + BUILDING_GAP
	local count = math.floor(DuelConfig.STREET_SIZE.Z / step)
	local firstZ = DuelConfig.STREET_CENTER.Z
		- halfLength
		+ (DuelConfig.STREET_SIZE.Z - count * step) / 2
		+ step / 2

	for sideIndex, side in { -1, 1 } do
		for index = 1, count do
			local style = BUILDING_STYLES[(index + sideIndex * 2) % #BUILDING_STYLES + 1]
			buildFacade(buildings, style, side, firstZ + (index - 1) * step)
		end
	end

	buildProps(arena)
	buildBounds(arena)
	arena.Parent = Workspace
end

local function buildLobby()
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	local center = DuelConfig.LOBBY_CENTER
	local size = DuelConfig.LOBBY_SIZE
	local top = center.Y + size.Y / 2

	part(lobby, "Floor", {
		Size = size,
		Position = center,
		Material = Enum.Material.WoodPlanks,
		Color = MID_WOOD,
	})

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = Vector3.new(center.X, top + 0.5, center.Z)
	spawnLocation.Material = Enum.Material.Slate
	spawnLocation.Color = DARK_WOOD
	spawnLocation.Neutral = true
	-- No spawn ForceField: it would block damage when a respawned duelist is moved to the street.
	spawnLocation.Duration = 0
	spawnLocation.Parent = lobby

	-- Visible fence rails plus tall invisible walls so lobby players can't walk onto the street.
	local wallHeight = 30
	local rails = {
		{ Size = Vector3.new(size.X, 1, 1), Offset = Vector3.new(0, 0, size.Z / 2) },
		{ Size = Vector3.new(size.X, 1, 1), Offset = Vector3.new(0, 0, -size.Z / 2) },
		{ Size = Vector3.new(1, 1, size.Z), Offset = Vector3.new(size.X / 2, 0, 0) },
		{ Size = Vector3.new(1, 1, size.Z), Offset = Vector3.new(-size.X / 2, 0, 0) },
	}
	for _, rail in rails do
		local base = Vector3.new(center.X, top, center.Z) + rail.Offset
		part(lobby, "FenceRail", {
			Size = rail.Size,
			Position = base + Vector3.new(0, 3, 0),
			Material = Enum.Material.Wood,
			Color = DARK_WOOD,
		})
		part(lobby, "Barrier", {
			Size = Vector3.new(rail.Size.X, wallHeight, rail.Size.Z),
			Position = base + Vector3.new(0, wallHeight / 2, 0),
			Transparency = 1,
		})
	end

	lobby.Parent = Workspace
end

local function setupLighting()
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(110, 85, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 130, 95)

	if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.35
		atmosphere.Color = Color3.fromRGB(215, 175, 120)
		atmosphere.Decay = Color3.fromRGB(120, 75, 35)
		atmosphere.Glare = 0.4
		atmosphere.Haze = 1.8
		atmosphere.Parent = Lighting
	end
end

function MapBuilderService:Init()
	buildArena()
	buildLobby()
	setupLighting()
	print("[Skoobi/Server] Western street and lobby built")
end

return MapBuilderService
