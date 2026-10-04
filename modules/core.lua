--[[
	Vandis / core.lua
	Shared services, per-player cache and game helpers.

	The whole point of this file is to keep the per-frame hot path free of
	FindFirstChild / GetDescendants / table allocation. Everything that can be
	cached is cached here and invalidated by signals, not by polling.
]]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local localPlayer = Players.LocalPlayer

local Core = {}

Core.Players = Players
Core.RunService = RunService
Core.UserInputService = UserInputService
Core.LocalPlayer = localPlayer

Core.Config = {
	MaxDistance = 1200, -- studs, hard cull
	FadeStart = 1100, -- studs, start fading ESP out
	StudsPerMetre = 3, -- Roblox studs are roughly 3 per metre
}

Core.IsArsenal = (function()
	local ok, name = pcall(function()
		return game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId).Name
	end)
	return ok and type(name) == 'string' and name:lower():find('arsenal') ~= nil
end)()

-- Character part names we care about, probed once per rig.
Core.PartOrder = {
	'Head',
	'UpperTorso',
	'Torso',
	'LowerTorso',
	'HumanoidRootPart',
}

local function collectParts(character)
	local parts = {}
	for _, name in Core.PartOrder do
		local found = character:FindFirstChild(name)
		if found and found:IsA('BasePart') then
			parts[name] = found
		end
	end
	return parts
end

--[[
	Player cache

	entry = {
		player      Player
		name        string  (cached, never changes)
		shortName   string
		character   Model
		humanoid    Humanoid
		parts       table   name -> BasePart
		weapon      string  (cached, invalidated on tool events)
		weaponDirty boolean
		kevlar      number
		kevlarDirty boolean
		team        Team
	}
]]
Core.cache = setmetatable({}, { __mode = 'k' })

local function weaponOf(entry)
	local character = entry.character
	if not character then return '' end
	local tool = character:FindFirstChildWhichIsA('Tool')
	if not tool then
		local backpack = localPlayer:FindFirstChildOfClass('Backpack')
		tool = backpack and backpack:FindFirstChildWhichIsA('Tool')
	end
	if not tool then return '' end
	local n = tool.Name
	if n == 'Melee' or n == 'Fists' or n == 'Knife' then return '' end
	return n
end

local function kevlarOf(entry)
	-- Arsenal keeps armour on the Player as a NumberValue; other games tend to
	-- put it in a leaderstats folder. Probe both, cache, invalidate on change.
	local p = entry.player
	local v = p:FindFirstChild('Kevlar') or p:FindFirstChild('Armor') or p:FindFirstChild('Health')
	local ls = p:FindFirstChild('leaderstats')
	if not v and ls then
		v = ls:FindFirstChild('Kevlar') or ls:FindFirstChild('Armor')
	end
	if v and (v:IsA('NumberValue') or v:IsA('IntValue')) then
		return v.Value
	end
	local hum = entry.humanoid
	if hum then
		local sh = hum:FindFirstChild('Shield') or hum:FindFirstChild('Armor')
		if sh and (sh:IsA('NumberValue') or sh:IsA('IntValue')) then
			return sh.Value
		end
	end
	return 0
end

local function newEntry(player)
	local entry = {
		player = player,
		name = player.Name,
		weaponDirty = true,
		kevlarDirty = true,
	}
	if #entry.name > 4 then
		entry.shortName = entry.name:sub(1, 4) .. '..'
	else
		entry.shortName = entry.name
	end
	return entry
end

local function bindCharacter(entry)
	local character = entry.player.Character

	local function clear()
		entry.character = nil
		entry.humanoid = nil
		entry.parts = nil
		entry.weaponDirty = true
	end

	local function setup(char)
		clear()
		if not char then return end
		entry.character = char
		entry.humanoid = char:FindFirstChildOfClass('Humanoid')
		entry.parts = collectParts(char)
		entry.weaponDirty = true
	end

	setup(character)
	entry.player.CharacterAdded:Connect(setup)
	entry.player.CharacterRemoving:Connect(clear)

	-- Parts appear a frame or two after the character for some games, so make
	-- sure a late spawn still gets picked up without polling every frame.
	task.spawn(function()
		for _ = 1, 10 do
			if not entry.parts or not next(entry.parts) then
				if entry.character then
					entry.parts = collectParts(entry.character)
					entry.humanoid = entry.character:FindFirstChildOfClass('Humanoid')
				end
			else
				return
			end
			task.wait(0.1)
		end
	end)

	-- Weapon / armour invalidation instead of a polling loop.
	local function touch()
		entry.weaponDirty = true
		entry.kevlarDirty = true
	end
	entry.player.ChildAdded:Connect(touch)
	entry.player.ChildRemoved:Connect(touch)
end

function Core.Get(player)
	if player == localPlayer then return nil end
	local entry = Core.cache[player]
	if entry then return entry end
	entry = newEntry(player)
	Core.cache[player] = entry
	bindCharacter(entry)
	return entry
end

function Core.GetAll()
	local out = {}
	for _, player in Players:GetPlayers() do
		local entry = Core.Get(player)
		if entry then table.insert(out, entry) end
	end
	return out
end

function Core.IsAlive(entry)
	local hum = entry.humanoid
	return hum ~= nil and hum.Health > 0 and entry.parts ~= nil and entry.parts.Head ~= nil
end

function Core.Team(entry)
	return entry.player.Team
end

--[[
	Enemy test.

	Arsenal (and most military shooters) have a Neutral team. Whether neutral
	counts as an enemy is an option so the user can pick.
]]
function Core.IsEnemy(entry, opts)
	if not opts.TeamCheck then return true end
	local mine = localPlayer.Team
	local theirs = entry.player.Team
	if not mine or not theirs then return true end
	if mine == theirs then return false end
	if not opts.NeutralIsEnemy then
		local neutral = theirs.Name == 'Neutral' or mine.Name == 'Neutral'
		if neutral then return false end
	end
	return true
end

function Core.Weapon(entry)
	if entry.weaponDirty then
		entry.weapon = weaponOf(entry)
		entry.weaponDirty = false
	end
	return entry.weapon
end

function Core.Kevlar(entry)
	if entry.kevlarDirty then
		entry.kevlar = kevlarOf(entry)
		entry.kevlarDirty = false
	end
	return entry.kevlar
end

--[[
	Closest / best part selection.

	`order` lets callers bias the choice. "head" mode (the default for silent
	aim) walks head first and falls back down the body, which is what stops the
	shot from silently landing on the torso when the head is what you aimed at.
]]
function Core.BestPart(entry, mode)
	local parts = entry.parts
	if not parts then return nil, nil end

	if mode == 'closest' then
		local cam = workspace.CurrentCamera
		local mouse = localPlayer:GetMouse()
		local mp = Vector3.new(mouse.X, mouse.Y, 0)
		local bestPart, bestDist
		for _, p in pairs(parts) do
			local ok, sp = pcall(function()
				return cam:WorldToViewportPoint(p.Position)
			end)
			if ok and sp and sp.Z > 0 then
				local d = (sp - mp).Magnitude
				if not bestDist or d < bestDist then
					bestDist = d
					bestPart = p
				end
			end
		end
		return bestPart, bestDist
	end

	local order = mode == 'head' and { 'Head', 'UpperTorso', 'Torso', 'LowerTorso', 'HumanoidRootPart' }
		or Core.PartOrder
	for _, name in order do
		local p = parts[name]
		if p and p.Parent then
			return p, name
		end
	end
	return nil, nil
end

function Core.PrimaryPart(entry)
	local parts = entry.parts
	if not parts then return nil end
	return parts.HumanoidRootPart or parts.UpperTorso or parts.Torso or entry.character and entry.character.PrimaryPart
end

function Core.Character(entry)
	return entry.character
end

function Core.LocalCharacter()
	return localPlayer.Character
end

function Core.LocalRoot()
	local c = localPlayer.Character
	if not c then return nil end
	return c:FindFirstChild('HumanoidRootPart') or c:FindFirstChild('Head')
end

function Core.IsAliveLocal()
	local c = localPlayer.Character
	if not c then return false end
	local hum = c:FindFirstChildOfClass('Humanoid')
	return hum ~= nil and hum.Health > 0
end

return Core