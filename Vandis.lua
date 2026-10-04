--[[
	Vandis
	======

	Entry point. Pulls the modules and the UI library from this repository,
	caches them locally, then builds the menu and keeps it wired to the configs.

	Usage
	-----
	  loadstring(game:HttpGet("https://raw.githubusercontent.com/exuric/Vandis/main/Vandis.lua"))()

	The library this UI is based on is the "Universe" library. It is vendored
	here as lib/universe.lua and is exposed as `Vandis.Menu`.
]]

local REPO = 'exuric/Vandis'
local REF = 'main'

--[[
	Bump this whenever any module or the library changes. It namespaces the
	local cache folder, so a stale cached copy can never shadow an update -
	which is exactly what happened when the keybind change appeared not to work.
--]]
local VERSION = '1'

local FOLDER = 'Vandis'
local CACHE = FOLDER .. '/v' .. VERSION .. '/'

local RS = game:GetService('ReplicatedStorage')
local UIS = game:GetService('UserInputService')

-- ---------------------------------------------------------------------------
-- fetch + cache
-- ---------------------------------------------------------------------------

local function readFile(path)
	if type(readfile) ~= 'function' then return nil end
	local ok, res = pcall(readfile, path)
	if ok and type(res) == 'string' and #res > 40 then return res end
	return nil
end

local function writeFile(path, data)
	if type(writefile) ~= 'function' then return end
	pcall(function()
		mkdir(CACHE)
	end)
	pcall(writefile, path, data)
end

local function fetch(path)
	local cached = readFile(CACHE .. path:gsub('\\', '/'))
	if cached then return cached end

	local urls = {
		('https://raw.githubusercontent.com/%s/%s/%s'):format(REPO, REF, path),
		('https://cdn.jsdelivr.net/gh/%s@%s/%s'):format(REPO, REF, path),
	}
	for _, url in ipairs(urls) do
		local ok, body = pcall(function()
			return game:HttpGet(url, true)
		end)
		if ok and type(body) == 'string' and #body > 40 and body ~= '404: Not Found' then
			writeFile(CACHE .. path, body)
			return body
		end
	end
	return nil
end

local function loadSource(path)
	local body = fetch(path)
	if not body then
		error(('[Vandis] failed to fetch %s'):format(path))
	end
	local chunk, err = loadstring(body, '@' .. path)
	if not chunk then
		error(('[Vandis] syntax error in %s: %s'):format(path, tostring(err)))
	end
	return chunk
end

-- ---------------------------------------------------------------------------
-- module bootstrap
-- ---------------------------------------------------------------------------

local container = Instance.new('Folder')
container.Name = 'VandisModules'
container.Parent = RS

local function makeModule(name, source)
	local existing = container:FindFirstChild(name)
	if existing then existing:Destroy() end
	local mod = Instance.new('ModuleScript')
	mod.Name = name
	mod.Source = source
	mod.Parent = container
	return mod
end

local function requireModule(name, path)
	return require(makeModule(name, loadSource(path)))
end

-- UI library first (it is a plain chunk, not a module)
local VUI = loadSource('lib/universe.lua')()

local core = requireModule('core', 'modules/core.lua')
local esp = requireModule('esp', 'modules/esp.lua')
local silentaim = requireModule('silentaim', 'modules/silentaim.lua')

local Vandis = {
	Core = core,
	ESP = esp,
	SilentAim = silentaim,
	Menu = nil,
}

-- ---------------------------------------------------------------------------
-- menu
-- ---------------------------------------------------------------------------

local TABS = {
	'http://www.roblox.com/asset/?id=7300477598', -- aimbot
	'http://www.roblox.com/asset/?id=7300535052', -- visuals
	'http://www.roblox.com/asset/?id=7300480952', -- misc
}

local menu = VUI.new('Vandis', FOLDER .. '/cfg.txt')
Vandis.Menu = menu

local tabs = {}
for i, image in ipairs(TABS) do
	tabs[i] = menu.new_tab(image)
end

-- ---------------------------------------------------------------------------
-- aimbot tab
-- ---------------------------------------------------------------------------

local ECFG, SCFG = esp.Config, silentaim.Config

do
	local section = tabs[1].new_section('silent aim')

	local main = section.new_sector('main')
	main.element('Toggle', 'enabled'):add_keybind()

	local target = section.new_sector('target')
	target.element('Dropdown', 'hitbox', {
		options = { 'Head', 'Upper Torso', 'Torso', 'Root', 'Closest', 'Auto' },
		default = { Dropdown = 'Head' },
	})
	target.element('Toggle', 'head priority')
	target.element('Slider', 'head snap radius', { default = { min = 5, max = 200, default = 40 } })
	target.element('Slider', 'fov', { default = { min = 20, max = 600, default = 180 } })
	target.element('Slider', 'max distance', { default = { min = 50, max = 3000, default = 900 } })

	local method = section.new_sector('method')
	method.element('Dropdown', 'method', {
		options = { 'Raycast', 'Camera' },
		default = { Dropdown = 'Raycast' },
	})
	method.element('Slider', 'smoothness', { default = { min = 0, max = 100, default = 0 } })
	method.element('Slider', 'hit chance', { default = { min = 0, max = 100, default = 100 } })
	method.element('Toggle', 'show fov')

	local checks = section.new_sector('checks', 'Right')
	checks.element('Toggle', 'team check')
	checks.element('Toggle', 'neutral is enemy')
	checks.element('Toggle', 'require alive')
end

-- ---------------------------------------------------------------------------
-- visuals tab
-- ---------------------------------------------------------------------------

do
	local section = tabs[2].new_section('esp')

	local main = section.new_sector('main')
	main.element('Toggle', 'enabled'):add_keybind()

	local global = section.new_sector('global')
	global.element('Slider', 'max distance', { default = { min = 100, max = 3000, default = 1200 } })
	global.element('Slider', 'fade start', { default = { min = 100, max = 3000, default = 1100 } })
	global.element('Slider', 'text size', { default = { min = 8, max = 24, default = 13 } })
	global.element('Slider', 'box aspect', { default = { min = 10, max = 120, default = 45 } })
	global.element('Toggle', 'outlines')
	global.element('Toggle', 'short names')
	global.element('Toggle', 'distance in name')

	local colours = section.new_sector('enemy', 'Right')
	colours.element('Toggle', 'box')
	colours.element('Toggle', 'health bar')
	colours.element('Toggle', 'kevlar bar')
	colours.element('Toggle', 'name')
	colours.element('Toggle', 'weapon')
	colours.element('Toggle', 'health text')
	colours.element('Toggle', 'chams')
end

-- ---------------------------------------------------------------------------
-- misc tab
-- ---------------------------------------------------------------------------

do
	local section = tabs[3].new_section('settings')

	local checks = section.new_sector('filters')
	checks.element('Toggle', 'team check')
	checks.element('Toggle', 'neutral is enemy')
	checks.element('Toggle', 'visible check')
	checks.element('Toggle', 'limit distance')

	local teamSec = section.new_sector('teammates', 'Right')
	teamSec.element('Toggle', 'name')
	teamSec.element('Toggle', 'box')

	local cfg = section.new_sector('config')
	cfg.element('TextBox', 'config name', { default = 'default' })
	cfg.element('Button', 'save')
	cfg.element('Button', 'load')

	local info = section.new_sector('info', 'Right')
	info.element('TextBox', 'target', { default = 'none' })
end

-- ---------------------------------------------------------------------------
-- bind ui -> config
-- ---------------------------------------------------------------------------

local function val(tab, sectionName, sectorName, label)
	local t = menu.values[tab] and menu.values[tab][sectionName]
	local s = t and t[sectorName]
	return s and s[label]
end

local function active(toggle, keybind)
	if toggle and toggle.Toggle then return true end
	if keybind and keybind.Active then return true end
	return false
end

local function bind()
	-- silent aim
	local v = val(1, 'silent aim', 'main', 'enabled')
	local kb = val(1, 'silent aim', 'main', '$enabled')
	SCFG.Enabled = active(v, kb)

	local hitbox = val(1, 'silent aim', 'target', 'hitbox')
	if hitbox then SCFG.TargetPart = hitbox.Dropdown end

	local prio = val(1, 'silent aim', 'target', 'head priority')
	if prio then SCFG.HeadPriority = prio.Toggle end

	local snap = val(1, 'silent aim', 'target', 'head snap radius')
	if snap then SCFG.SnapRadius = snap.Slider end

	local fov = val(1, 'silent aim', 'target', 'fov')
	if fov then SCFG.FOV = fov.Slider end

	local maxd = val(1, 'silent aim', 'target', 'max distance')
	if maxd then SCFG.MaxDistance = maxd.Slider end

	local method = val(1, 'silent aim', 'method', 'method')
	if method then SCFG.Method = method.Dropdown end

	local smooth = val(1, 'silent aim', 'method', 'smoothness')
	if smooth then SCFG.Smoothness = smooth.Slider end

	local chance = val(1, 'silent aim', 'method', 'hit chance')
	if chance then SCFG.HitChance = chance.Slider end

	local showfov = val(1, 'silent aim', 'method', 'show fov')
	if showfov then SCFG.ShowFOV = showfov.Toggle end

	local saTeam = val(1, 'silent aim', 'checks', 'team check')
	if saTeam then SCFG.TeamCheck = saTeam.Toggle end

	local saNeutral = val(1, 'silent aim', 'checks', 'neutral is enemy')
	if saNeutral then SCFG.NeutralIsEnemy = saNeutral.Toggle end

	local saAlive = val(1, 'silent aim', 'checks', 'require alive')
	if saAlive then SCFG.RequireAlive = saAlive.Toggle end

	-- esp
	local e = val(2, 'esp', 'main', 'enabled')
	local eBind = val(2, 'esp', 'main', '$enabled')
	ECFG.Enabled = active(e, eBind)

	local gmax = val(2, 'esp', 'global', 'max distance')
	if gmax then ECFG.MaxDistance = gmax.Slider end

	local gfade = val(2, 'esp', 'global', 'fade start')
	if gfade then ECFG.FadeStart = gfade.Slider end

	local gtext = val(2, 'esp', 'global', 'text size')
	if gtext then ECFG.TextSize = gtext.Slider end

local gaspect = val(2, 'esp', 'global', 'box aspect')
	if gaspect then ECFG.BoxAspect = gaspect.Slider / 100 end

	local outlines = val(2, 'esp', 'global', 'outlines')
	if outlines then ECFG.Outlines = outlines.Toggle end

	local shortnames = val(2, 'esp', 'global', 'short names')
	if shortnames then ECFG.ShortNames = shortnames.Toggle end

	local distName = val(2, 'esp', 'global', 'distance in name')
	if distName then
		ECFG.Enemy.DistanceInName = distName.Toggle
		ECFG.Team.DistanceInName = distName.Toggle
		ECFG.Priority.DistanceInName = distName.Toggle
	end

	local function enemyToggle(label, key)
		local t = val(2, 'esp', 'enemy', label)
		if t then ECFG.Enemy[key] = t.Toggle end
	end
	enemyToggle('box', 'Box')
	enemyToggle('health bar', 'HealthBar')
	enemyToggle('kevlar bar', 'KevlarBar')
	enemyToggle('name', 'Name')
	enemyToggle('weapon', 'Weapon')
	enemyToggle('health text', 'HealthText')
	enemyToggle('chams', 'Chams')

	local function teamToggle(label, key)
		local t = val(2, 'esp', 'teammates', label)
		if t then ECFG.Team[key] = t.Toggle end
	end
	teamToggle('name', 'Name')
	teamToggle('box', 'Box')

	-- filters
	local fTeam = val(3, 'settings', 'filters', 'team check')
	if fTeam then ECFG.TeamCheck = fTeam.Toggle end

	local fNeutral = val(3, 'settings', 'filters', 'neutral is enemy')
	if fNeutral then ECFG.NeutralIsEnemy = fNeutral.Toggle end

	local fVisible = val(3, 'settings', 'filters', 'visible check')
	if fVisible then ECFG.VisibleCheck = fVisible.Toggle end

	local fLimit = val(3, 'settings', 'filters', 'limit distance')
	if fLimit then ECFG.LimitDistance = fLimit.Toggle end
end

local function updateTargetLabel()
	local box = val(3, 'settings', 'info', 'target')
	if not box then return end
	local entry, part = silentaim.CurrentTarget()
	if not entry then
		box.Text = 'none'
	else
		box.Text = ('%s (%s)'):format(entry.name, part and part.Name or '?')
	end
end

-- config save / load
do
	local saveBtn = val(3, 'settings', 'config', 'save')
	local loadBtn = val(3, 'settings', 'config', 'load')
	local nameBox = val(3, 'settings', 'config', 'config name')
	if saveBtn and nameBox then
		pcall(function()
			menu.save_cfg(nameBox.Text)
		end)
	end
	if loadBtn and nameBox then
		pcall(function()
			menu.load_cfg(nameBox.Text)
		end)
	end
end

-- priority toggle on middle click of a name is overkill; use a simple command
UIS.InputBegan:Connect(function(input)
	if UIS:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.P and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
		local _, part = silentaim.CurrentTarget()
		if part then
			local character = part.Parent
			local player = core.Players:GetPlayerFromCharacter(character)
			if player then
				esp.TogglePriority(core.Get(player))
			end
		end
	end
end)

bind()
task.spawn(function()
	while task.wait(0.05) do
		pcall(bind)
		updateTargetLabel()
	end
end)

esp.Init()
silentaim.Init()

print('[Vandis] loaded')