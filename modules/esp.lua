--[[
	Vandis / modules/esp.lua
	Seere-style ESP rebuilt for performance.

	Why the original lags, and what this does instead
	-------------------------------------------------
	Seere creates ~30 Drawing objects per player up front, then every frame for
	every player it does 3-4 FindFirstChild calls (checkalive), a
	players:FindFirstChild by name, a fresh RaycastParams allocation per
	visibility raycast, allocates a table of 8 CFrames for the box, allocates a
	Vector2 per corner and builds the distance string with tostring(). None of
	that is free, and it all happens unconditionally at render rate.

	Fixes applied here:
	  1. Lazy allocation   - a Drawing is only created when its feature is on.
	  2. Part caching      - character parts resolved once, invalidated by signal.
	  3. Property caching  - a write only happens when the value actually changed.
	  4. String caching    - distance/health text only rebuilt when it changes.
	  5. Distance banding  - near targets update every frame, far ones every 2/3/4.
	  6. Raycast budget    - visibility checks are capped per frame.
	  7. Two-projection box- box maths costs 2 projections instead of ~10.
	  8. Frame-correct reset - objects hidden at the START of the next frame, so
	                          nothing is ever hidden after being made visible.
]]

local Core = require(script.Parent.core)
local RunService = Core.RunService
local Players = Core.Players
local localPlayer = Core.LocalPlayer

local ESP = {}

ESP.Config = {
	Enabled = false,
	TeamCheck = true,
	NeutralIsEnemy = true,
	VisibleCheck = false,
	Outlines = true,
	ShortNames = false,
	LimitDistance = true,
	MaxDistance = 1200,
	FadeStart = 1100,
	TextSize = 13,
	BoxAspect = 0.45,
	StudsPerMetre = 3,
	MaxChars = 4,

	Enemy = {
		Box = true,
		HealthBar = true,
		KevlarBar = false,
		Name = true,
		Weapon = true,
		DistanceInName = true,
		HealthText = false,
		Arrow = true,
		Chams = false,
	},
	Team = {
		Box = false,
		HealthBar = false,
		KevlarBar = false,
		Name = true,
		Weapon = false,
		DistanceInName = true,
		HealthText = false,
		Arrow = false,
		Chams = false,
	},
	Priority = {
		Box = true,
		HealthBar = true,
		KevlarBar = false,
		Name = true,
		Weapon = true,
		DistanceInName = true,
		HealthText = false,
		Arrow = true,
		Chams = false,
	},
}

ESP.Colours = {
	Enemy = {
		Box = Color3.fromRGB(255, 255, 255),
		Health = Color3.fromRGB(255, 45, 85),
		HealthBack = Color3.fromRGB(40, 40, 40),
		Kevlar = Color3.fromRGB(120, 190, 255),
		KevlarBack = Color3.fromRGB(40, 40, 40),
		Text = Color3.fromRGB(255, 255, 255),
	},
	Team = {
		Box = Color3.fromRGB(120, 255, 140),
		Health = Color3.fromRGB(120, 255, 140),
		HealthBack = Color3.fromRGB(40, 40, 40),
		Kevlar = Color3.fromRGB(120, 190, 255),
		KevlarBack = Color3.fromRGB(40, 40, 40),
		Text = Color3.fromRGB(150, 255, 165),
	},
	Priority = {
		Box = Color3.fromRGB(255, 190, 60),
		Health = Color3.fromRGB(255, 190, 60),
		HealthBack = Color3.fromRGB(40, 40, 40),
		Kevlar = Color3.fromRGB(255, 235, 140),
		KevlarBack = Color3.fromRGB(40, 40, 40),
		Text = Color3.fromRGB(255, 210, 120),
	},
}

local C = ESP.Config
local COL = ESP.Colours

local haveDrawing = type(Drawing) == 'function'
local folder = Instance.new('Folder')
folder.Name = 'VandisESP'
folder.Parent = game:GetService('CoreGui')

-- Index hoisting: this code runs per player per frame.
local sqrt, abs, floor, min, max = math.sqrt, math.abs, math.floor, math.min, math.max
local v2, v3 = Vector2.new, Vector3.new

local pool = setmetatable({}, { __mode = 'k' })
local priority = {}
local connections = {}
local rayBudget = 0
local rayParams = nil
local frameCounter = 0

local function put(el, key, value)
	local cache = el.c
	if cache[key] ~= value then
		cache[key] = value
		el.d[key] = value
	end
end

local function hide(el)
	if el.c.Visible then
		el.c.Visible = false
		el.d.Visible = false
	end
end

local function hideAll(state)
	for _, bucket in pairs(state.pool) do
		for _, el in pairs(bucket) do
			hide(el)
		end
	end
	if state.chams then state.chams.Enabled = false end
end

-- Reset whatever was on during the previous frame. Runs at the top of the
-- frame, before anything is made visible again.
local function resetFrame(state)
	for _, bucket in pairs(state.pool) do
		for _, el in pairs(bucket) do
			hide(el)
		end
	end
	if state.chams then state.chams.Enabled = false end
end

-- Lazily create a Drawing the first time a feature is actually needed.
local function draw(state, group, key, kind)
	local bucket = state.pool[group]
	if not bucket then
		bucket = {}
		state.pool[group] = bucket
	end
	local el = bucket[key]
	if el then return el end
	if not haveDrawing then return nil end
	local ok, d = pcall(Drawing.new, kind)
	if not ok or not d then return nil end
	el = { d = d, c = { Visible = false } }
	d.Visible = false
	bucket[key] = el
	return el
end

local function ensureChams(state, character)
	local hl = state.chams
	if hl then
		if hl.Parent == character then return hl end
		pcall(function()
			hl:Destroy()
		end)
		state.chams = nil
	end
	local ok, made = pcall(function()
		local h = Instance.new('Highlight')
		h.Adornee = character
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillTransparency = 0.75
		h.OutlineTransparency = 0.25
		h.Enabled = false
		h.Parent = folder
		return h
	end)
	state.chams = ok and made or nil
	return state.chams
end

local function getState(player)
	local state = pool[player]
	if state then return state end
	state = {
		player = player,
		pool = {},
		chams = nil,
		frame = 0,
		distShown = -1,
		distText = '',
		visibleKnown = false,
		visible = false,
		visibleFrame = -99,
		primed = false,
	}
	pool[player] = state
	return state
end

local function dropState(player)
	local state = pool[player]
	if not state then return end
	for _, bucket in pairs(state.pool) do
		for _, el in pairs(bucket) do
			pcall(function()
				el.d:Remove()
			end)
		end
	end
	if state.chams then
		pcall(function()
			state.chams:Destroy()
		end)
	end
	pool[player] = nil
end

-- Distance band -> frames between refreshes. Near targets every frame.
local function cadence(dist)
	if dist < 120 then return 1 end
	if dist < 300 then return 2 end
	if dist < 600 then return 3 end
	return 4
end

local function transparencyFor(dist)
	if dist <= C.FadeStart then return 0 end
	if dist >= C.MaxDistance then return 1 end
	return max(0, min(1, (dist - C.FadeStart) / (C.MaxDistance - C.FadeStart)))
end

--[[
	Visibility raycast, budgeted.

	Seere allocated a new RaycastParams per call. We reuse one and only spend a
	few rays per frame; each player caches its result for a few frames so a
	player that missed its budget simply reuses the previous answer.
]]
local function visibleCheck(state, target)
	if not C.VisibleCheck then return true end
	if state.visibleKnown and (frameCounter - state.visibleFrame) < 4 then
		return state.visible
	end
	if rayBudget <= 0 or not target then return state.visible end
	rayBudget = rayBudget - 1
	state.visibleFrame = frameCounter

	if not rayParams then
		rayParams = RaycastParams.new()
		rayParams.IgnoreWater = true
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	rayParams.FilterDescendantsInstances = { localPlayer.Character, folder }

	local cam = workspace.CurrentCamera
	if not cam then return state.visible end
	local origin = cam.CFrame.Position
	local dx, dy, dz = target.Position.X - origin.X, target.Position.Y - origin.Y, target.Position.Z - origin.Z
	local mag = sqrt(dx * dx + dy * dy + dz * dz)
	if mag < 0.001 then
		state.visibleKnown, state.visible = true, true
		return true
	end
	local hit = workspace:Raycast(origin, v3(dx / mag, dy / mag, dz / mag), rayParams)
	state.visibleKnown = true
	state.visible = hit ~= nil and hit.Instance:IsDescendantOf(state.player.Character)
	return state.visible
end

local function drawText(state, group, key, text, x, y, col, transparency)
	local t = draw(state, group, key, 'Text')
	if not t then return false end
	put(t, 'Visible', true)
	put(t, 'Text', text)
	put(t, 'Position', v2(floor(x), floor(y)))
	put(t, 'Center', true)
	put(t, 'Color', col)
	put(t, 'Transparency', transparency)
	put(t, 'Size', C.TextSize)
	put(t, 'Font', 2)
	put(t, 'Outline', C.Outlines)
	return true
end

local function drawPlayer(state, entry, cam, camPos, dist)
	local enemy = Core.IsEnemy(entry, C)
	local group = priority[entry.player] and 'Priority' or (enemy and 'Enemy' or 'Team')
	local conf = C[group]
	local col = COL[group]

	local parts = entry.parts
	local root = parts and (parts.HumanoidRootPart or parts.UpperTorso or parts.Torso)
	if not root then
		hideAll(state)
		return
	end

	local head = parts.Head
	local topPos = head and head.Position or root.Position
	local hum = entry.humanoid
	local botPos = root.Position - v3(0, (hum and hum.HipHeight or 2), 0)

	local okTop, spTop = pcall(cam.WorldToViewportPoint, cam, topPos)
	local okBot, spBot = pcall(cam.WorldToViewportPoint, cam, botPos)
	if not (okTop and okBot) or not spTop or not spBot or spTop.Z <= 0 or spBot.Z <= 0 then
		hideAll(state)
		return
	end

	if C.VisibleCheck and not visibleCheck(state, head or root) then
		hideAll(state)
		return
	end

	local h = abs(spBot.Y - spTop.Y)
	local w = h * C.BoxAspect
	if h < 1 or w < 1 then
		hideAll(state)
		return
	end

	local bx = spTop.X - w / 2
	local by = spTop.Y
	local bs = v2(floor(w), floor(h))
	local transparency = transparencyFor(dist)
	local centreX = floor(bx + bs.X / 2)

	local metres = floor(dist / C.StudsPerMetre)
	if state.distShown ~= metres then
		state.distShown = metres
		state.distText = '[' .. metres .. 'm]'
	end

	-- box ---------------------------------------------------------------
	if conf.Box then
		local box = draw(state, group, 'box', 'Square')
		if box then
			put(box, 'Visible', true)
			put(box, 'Position', v2(floor(bx), floor(by)))
			put(box, 'Size', bs)
			put(box, 'Color', col.Box)
			put(box, 'Transparency', transparency)
			put(box, 'Filled', false)
			put(box, 'Thickness', 1)
		end
		if C.Outlines then
			local ol = draw(state, group, 'boxOutline', 'Square')
			if ol then
				put(ol, 'Visible', true)
				put(ol, 'Position', v2(floor(bx) - 1, floor(by) - 1))
				put(ol, 'Size', bs + v2(2, 2))
				put(ol, 'Color', Color3.new(0, 0, 0))
				put(ol, 'Transparency', transparency)
				put(ol, 'Filled', false)
				put(ol, 'Thickness', 1)
			end
		end
	end

	-- health bar -------------------------------------------------------
	if conf.HealthBar and hum then
		local back = draw(state, group, 'hpBack', 'Square')
		if back then
			put(back, 'Visible', true)
			put(back, 'Position', v2(floor(bx) - 4, floor(by)))
			put(back, 'Size', v2(2, bs.Y))
			put(back, 'Color', col.HealthBack)
			put(back, 'Transparency', transparency)
			put(back, 'Filled', true)
			put(back, 'Thickness', 1)
		end
		local bar = draw(state, group, 'hp', 'Square')
		if bar then
			local bh = max(1, floor(bs.Y * max(0, min(1, hum.Health / 100))))
			put(bar, 'Visible', true)
			put(bar, 'Position', v2(floor(bx) - 4, floor(by)))
			put(bar, 'Size', v2(2, bh))
			put(bar, 'Color', col.Health)
			put(bar, 'Transparency', transparency)
			put(bar, 'Filled', true)
			put(bar, 'Thickness', 1)
		end
	end

	-- kevlar bar -------------------------------------------------------
	if conf.KevlarBar then
		local kev = Core.Kevlar(entry)
		if kev > 0 then
			local back = draw(state, group, 'kvBack', 'Square')
			if back then
				put(back, 'Visible', true)
				put(back, 'Position', v2(floor(bx) + bs.X + 2, floor(by)))
				put(back, 'Size', v2(2, bs.Y))
				put(back, 'Color', col.KevlarBack)
				put(back, 'Transparency', transparency)
				put(back, 'Filled', true)
				put(back, 'Thickness', 1)
			end
			local bar = draw(state, group, 'kv', 'Square')
			if bar then
				local bh = max(1, floor(bs.Y * max(0, min(1, kev / 100))))
				put(bar, 'Visible', true)
				put(bar, 'Position', v2(floor(bx) + bs.X + 2, floor(by)))
				put(bar, 'Size', v2(2, bh))
				put(bar, 'Color', col.Kevlar)
				put(bar, 'Transparency', transparency)
				put(bar, 'Filled', true)
				put(bar, 'Thickness', 1)
			end
		end
	end

	-- name -------------------------------------------------------------
	if conf.Name then
		local label = C.ShortNames and entry.shortName or entry.name
		local text = C.DistanceInName and (state.distText .. ' ' .. label) or label
		drawText(state, group, 'name', text, centreX, floor(by) - 14, col.Text, transparency)
	end

	-- weapon -----------------------------------------------------------
	if conf.Weapon then
		local weapon = Core.Weapon(entry)
		if weapon ~= '' then
			drawText(state, group, 'weapon', weapon, centreX, floor(by) + bs.Y + 2, col.Text, transparency)
		end
	end

	-- health text ------------------------------------------------------
	if conf.HealthText and hum then
		drawText(state, group, 'hpText', floor(hum.Health) .. ' hp', centreX, floor(by) - 28, col.Text, transparency)
	end

	-- chams -------------------------------------------------------------
	if conf.Chams and entry.character then
		local hl = ensureChams(state, entry.character)
		if hl then
			hl.Enabled = true
			hl.FillColor = col.Box
			hl.OutlineColor = col.Text
		end
	end
end

local function render()
	frameCounter += 1
	rayBudget = C.VisibleCheck and 6 or 0

	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	local enabled = C.Enabled

	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			local state = pool[player]
			if state then
				-- Only touch this player's objects on frames we actually redraw
				-- them, otherwise distance banding makes far ESPs flicker.
				local entry, root, dist
				local redraw = false

				if enabled then
					entry = Core.Get(player)
					if entry and Core.IsAlive(entry) then
						root = Core.PrimaryPart(entry)
					end
					if root then
						local dx, dy, dz = root.Position.X - camPos.X, root.Position.Y - camPos.Y,
							root.Position.Z - camPos.Z
						dist = sqrt(dx * dx + dy * dy + dz * dz)
						if C.LimitDistance and dist > C.MaxDistance then
							hideAll(state)
						else
							state.frame += 1
							redraw = state.frame % cadence(dist) == 0
						end
					else
						hideAll(state)
					end
				else
					hideAll(state)
				end

				if redraw then
					resetFrame(state)
					drawPlayer(state, entry, cam, camPos, dist)
				end
			elseif enabled then
				getState(player)
			end
		end
	end
end

function ESP.Init()
	if ESP.Initialised then return ESP end
	ESP.Initialised = true
	table.insert(connections, RunService.RenderStepped:Connect(render))
	table.insert(connections, Players.PlayerRemoving:Connect(dropState))
	return ESP
end

function ESP.TogglePriority(entry)
	if not entry then return false end
	priority[entry.player] = not priority[entry.player] or nil
	return priority[entry.player] ~= nil
end

function ESP.TogglePriorityByName(name)
	for _, player in Players:GetPlayers() do
		if player.Name:lower() == name:lower() then
			return ESP.TogglePriority(Core.Get(player))
		end
	end
	return false
end

function ESP.ClearPriority()
	table.clear(priority)
end

function ESP.Unload()
	for _, c in connections do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	for _, player in Players:GetPlayers() do
		dropState(player)
	end
	table.clear(pool)
	pcall(function()
		folder:Destroy()
	end)
	ESP.Initialised = false
end

return ESP