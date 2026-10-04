--[[
	Vandis - single file build
	==========================

	Everything lives in this file on purpose: no fetching, no require(), no
	ModuleScript, no cache, no dependency on a remote host. If it runs, it runs.

	Layout
	  1. boot + error surface   (so a failure is visible instead of silent)
	  2. ui                     (Vape V4 style window)
	  3. core                   (cached players / body parts)
	  4. esp                    (Seere look, rebuilt hot path)
	  5. silent aim             (selectable hitbox)
	  6. page construction + binding

	Previous multi-file versions kept failing silently at load, so the failure
	handling here is deliberately loud.
]]

local VERSION = '3'

--------------------------------------------------------------------------
-- 1. boot + error surface
--------------------------------------------------------------------------

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')

local lplr = Players.LocalPlayer
local mouse = lplr:GetMouse()
local playerGui = lplr:WaitForChild('PlayerGui')

local boot = Instance.new('ScreenGui')
boot.Name = 'Vandis'
boot.ResetOnSpawn = false
boot.DisplayOrder = 9999
boot.IgnoreGuiInset = true
boot.ZIndexBehavior = Enum.ZIndexBehavior.Global
boot.Parent = playerGui

local ACCENT = Color3.fromRGB(52, 139, 255)
local BG = Color3.fromRGB(17, 17, 20)
local PANEL = Color3.fromRGB(23, 23, 27)
local ROW = Color3.fromRGB(31, 31, 36)
local TXT = Color3.fromRGB(236, 236, 241)
local DIM = Color3.fromRGB(142, 142, 152)
local FONT = Enum.Font.Ubuntu

local function mk(class, props, parent)
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			o[k] = v
		end
	end
	o.Parent = parent
	return o
end

local function round(o, r)
	mk('UICorner', { CornerRadius = UDim.new(0, r or 6) }, o)
end

local function stroke(o, c, t)
	return mk('UIStroke', { Color = c or Color3.fromRGB(0, 0, 0), Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local notice = mk('Frame', {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0, 560, 0, 0),
	BackgroundColor3 = Color3.fromRGB(70, 20, 24),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 60,
}, boot)
round(notice, 8)

local noticeText = mk('TextLabel', {
	Size = UDim2.new(1, -20, 1, -16),
	Position = UDim2.new(0, 10, 0, 8),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(255, 210, 210),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = FONT,
	TextWrapped = true,
	Text = '',
	ZIndex = 61,
}, notice)

local function fail(where, err)
	local msg = ('%s\n%s'):format(where, tostring(err))
	noticeText.Text = msg
	notice.Size = UDim2.new(0, 560, 0, math.min(320, 40 + #tostring(err) * 0.55))
	notice.Visible = true
	print('[Vandis] ' .. msg)
end

-- Run a chunk of setup, and surface any error on screen rather than leaving
-- an empty gui with no explanation.
local function guard(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		fail(name, err)
	end
	return ok
end

--------------------------------------------------------------------------
-- 2. ui
--------------------------------------------------------------------------

local UI = {}
UI.visible = true
UI.values = {}

local window, rail, page, scroll, title
local currentTab = 1
local pages = {}
local dragging = nil

local function setOpen(state)
	UI.visible = state and true or false
	if window then
		window.Visible = UI.visible
	end
end

UI.SetOpen = setOpen
UI.Toggle = function()
	setOpen(not UI.visible)
end

local function valueOf(tab, section, name)
	local t = UI.values[tab]
	local s = t and t[section]
	return s and s[name]
end

UI.Value = valueOf

local function addTab(name, glyph)
	pages[#pages + 1] = { name = name, glyph = glyph, sections = {}, order = {} }
	UI.values[#pages] = {}
	return #pages
end

local function sectionFrame(parent, tabIdx, sectionName)
	local pagesTab = pages[tabIdx]
	local frame = pagesTab.sections[sectionName]
	if frame then return frame end
	frame = mk('Frame', {
		Size = UDim2.new(1, -8, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	pagesTab.sections[sectionName] = frame
	pagesTab.order[#pagesTab.order + 1] = frame
	local heading = mk('TextLabel', {
		Size = UDim2.new(1, -12, 0, 20),
		BackgroundTransparency = 1,
		Text = sectionName,
		TextColor3 = ACCENT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.UbuntuBold,
		ZIndex = 3,
	}, frame)
	local lay = mk('UIListLayout', {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	UI.values[tabIdx][sectionName] = {}
	frame._layout = lay
	return frame
end

local function newRow(parent, height)
	local row = mk('Frame', {
		Size = UDim2.new(1, 0, 0, height or 26),
		BackgroundColor3 = ROW,
		BorderSizePixel = 0,
	}, parent)
	round(row, 6)
	return row
end

local function rowLabel(row, text, right)
	mk('TextLabel', {
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, right and -80 or -20, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = TXT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = FONT,
		ZIndex = 4,
	}, row)
end

-- Toggle --------------------------------------------------------------------
function UI.Toggle(tab, section, name, default)
	local row = newRow(sectionFrame(scroll, tab, section))
	rowLabel(row, name, true)
	UI.values[tab][section][name] = { Toggle = default or false }

	local pill = mk('Frame', {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 32, 0, 16),
		BackgroundColor3 = Color3.fromRGB(58, 58, 66),
		BorderSizePixel = 0,
		ZIndex = 4,
	}, row)
	round(pill, 8)

	local knob = mk('Frame', {
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0, 2, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(210, 210, 216),
		BorderSizePixel = 0,
		ZIndex = 5,
	}, pill)
	round(knob, 6)

	local state = UI.values[tab][section][name]

	local function paint()
		local on = state.Toggle
		TweenService:Create(pill, TweenInfo.new(0.15), {
			BackgroundColor3 = on and ACCENT or Color3.fromRGB(58, 58, 66),
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = UDim2.new(on and 1 or 0, on and -2 or 2, 0.5, 0),
		}):Play()
	end

	mk('TextButton', {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = '',
		ZIndex = 6,
	}, row).MouseButton1Click:Connect(function()
		state.Toggle = not state.Toggle
		paint()
	end)

	paint()
	return state
end

-- Slider --------------------------------------------------------------------
function UI.Slider(tab, section, name, min, max, default)
	local frame = sectionFrame(scroll, tab, section)
	local row = newRow(frame, 34)
	rowLabel(row, name, true)

	local valueLabel = mk('TextLabel', {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 4),
		Size = UDim2.new(0, 60, 0, 14),
		BackgroundTransparency = 1,
		Text = tostring(default or min),
		TextColor3 = ACCENT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = FONT,
		ZIndex = 4,
	}, row)

	local state = { Slider = default or min }
	state.min, state.max = min, max
	UI.values[tab][section][name] = state

	local bar = mk('Frame', {
		Position = UDim2.new(0, 10, 0, 22),
		Size = UDim2.new(1, -20, 0, 4),
		BackgroundColor3 = Color3.fromRGB(52, 52, 58),
		BorderSizePixel = 0,
		ZIndex = 4,
	}, row)
	round(bar, 2)

	local fill = mk('Frame', {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, bar)
	round(fill, 2)

	local function paint()
		local t = (state.Slider - min) / (max - min)
		fill.Size = UDim2.new(math.clamp(t, 0, 1), 0, 1, 0)
		valueLabel.Text = tostring(state.Slider)
	end

	local function apply(input)
		local r = bar.AbsoluteSize.X
		if r <= 0 then return end
		local t = math.clamp((input.Position.X - bar.AbsolutePosition.X) / r, 0, 1)
		state.Slider = min + (max - min) * t
		paint()
	end

	local hit = mk('TextButton', {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -12),
		BackgroundTransparency = 1,
		Text = '',
		ZIndex = 6,
	}, row)

	hit.MouseButton1Down:Connect(function()
		dragging = apply
		apply(mouse)
	end)
	hit.InputEnded:Connect(function()
		dragging = nil
	end)

	UIS.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			dragging(input)
		end
	end)

	paint()
	return state
end

-- Dropdown ------------------------------------------------------------------
function UI.Dropdown(tab, section, name, options, default)
	local row = newRow(sectionFrame(scroll, tab, section))
	rowLabel(row, name, true)

	local state = { Dropdown = default or options[1] }
	UI.values[tab][section][name] = state

	local button = mk('TextButton', {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 18),
		BackgroundColor3 = Color3.fromRGB(46, 46, 52),
		BorderSizePixel = 0,
		Text = state.Dropdown,
		TextColor3 = TXT,
		TextSize = 12,
		Font = FONT,
		ZIndex = 5,
	}, row)
	round(button, 5)

	local list = nil
	local function close()
		if list then
			list:Destroy()
			list = nil
		end
	end

	button.MouseButton1Click:Connect(function()
		if list then
			close()
			return
		end
		list = mk('Frame', {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 1, 4),
			Size = UDim2.new(0, 120, 0, #options * 20),
			BackgroundColor3 = PANEL,
			BorderSizePixel = 0,
			ZIndex = 40,
		}, row)
		round(list, 5)
		stroke(list, Color3.fromRGB(45, 45, 52), 1)
		for i, opt in ipairs(options) do
			local b = mk('TextButton', {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = opt,
				TextColor3 = opt == state.Dropdown and ACCENT or TXT,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = FONT,
				ZIndex = 41,
			}, list)
			mk('UIPadding', { PaddingLeft = UDim.new(0, 8) }, b)
			b.MouseButton1Click:Connect(function()
				state.Dropdown = opt
				button.Text = opt
				close()
			end)
		end
	end)

	UIS.InputBegan:Connect(function(input)
		if list and input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = input.Position
			if p.Y < list.AbsolutePosition.Y or p.Y > list.AbsolutePosition.Y + list.AbsoluteSize.Y then
				close()
			end
		end
	end)

	return state
end

-- Button --------------------------------------------------------------------
function UI.Button(tab, section, name, callback)
	local row = newRow(sectionFrame(scroll, tab, section), 24)
	rowLabel(row, name)
	mk('TextButton', {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = '',
		ZIndex = 6,
	}, row).MouseButton1Click:Connect(callback)
	return row
end

-- Text box ------------------------------------------------------------------
function UI.TextBox(tab, section, name, default, readonly)
	local row = newRow(sectionFrame(scroll, tab, section), 24)
	rowLabel(row, name, true)
	local state = { Text = default or '' }
	UI.values[tab][section][name] = state
	local box = mk('TextBox', {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 130, 0, 18),
		BackgroundColor3 = Color3.fromRGB(46, 46, 52),
		BorderSizePixel = 0,
		Text = state.Text,
		PlaceholderText = 'none',
		TextColor3 = TXT,
		TextSize = 12,
		Font = FONT,
		Editable = not readonly,
		ClearTextOnFocus = false,
		ZIndex = 5,
	}, row)
	round(box, 5)
	if readonly then
		box.TextColor3 = DIM
	end
	box:GetPropertyChangedSignal('Text'):Connect(function()
		state.Text = box.Text
	end)
	return state
end

-- Keybind -------------------------------------------------------------------
function UI.Keybind(tab, section, name, default)
	local row = newRow(sectionFrame(scroll, tab, section), 24)
	rowLabel(row, name, true)
	local state = { Key = default or Enum.KeyCode.Unknown, Active = false, Name = default and default.Name or 'NONE' }
	UI.values[tab][section][name] = state
	local label = state.Name

	local button = mk('TextButton', {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 76, 0, 18),
		BackgroundColor3 = Color3.fromRGB(46, 46, 52),
		BorderSizePixel = 0,
		Text = '[ ' .. label .. ' ]',
		TextColor3 = TXT,
		TextSize = 11,
		Font = FONT,
		ZIndex = 5,
	}, row)
	round(button, 5)

	local listening = false
	button.MouseButton1Click:Connect(function()
		listening = true
		button.Text = '[ ... ]'
	end)
	UIS.InputBegan:Connect(function(input)
		if not listening then return end
		listening = false
		state.Key = input.KeyCode
		state.Name = input.KeyCode.Name
		state.Active = false
		button.Text = '[ ' .. state.Name .. ' ]'
	end)
	return state
end

local TABS = {
	{ name = 'Aimbot', glyph = 'A' },
	{ name = 'Visuals', glyph = 'V' },
	{ name = 'Settings', glyph = 'S' },
}

local function buildWindow()
	window = mk('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(500, 340),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 10,
	}, boot)
	round(window, 10)
	stroke(window, Color3.fromRGB(38, 38, 44), 1)

	title = mk('TextLabel', {
		Size = UDim2.new(1, -70, 0, 30),
		Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1,
		Text = 'Vandis',
		TextColor3 = TXT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.UbuntuBold,
		ZIndex = 12,
	}, window)

	mk('TextButton', {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(20, 16),
		BackgroundColor3 = Color3.fromRGB(48, 48, 54),
		BorderSizePixel = 0,
		Text = 'x',
		TextColor3 = DIM,
		TextSize = 12,
		Font = FONT,
		ZIndex = 12,
	}, window).MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	-- draggable
	local drag, dragStart, startPos
	mk('TextButton', {
		Size = UDim2.new(1, -70, 0, 30),
		BackgroundTransparency = 1,
		Text = '',
		ZIndex = 11,
	}, window).MouseButton1Down:Connect(function(input)
		drag = true
		dragStart = input.Position
		startPos = window.Position
	end)
	UIS.InputChanged:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseMovement then
			local d = input.Position - dragStart
			window.Position = UDim2.new(0, startPos.X.Offset + d.X, 0, startPos.Y.Offset + d.Y)
		end
	end)
	UIS.InputEnded:Connect(function()
		drag = false
	end)

	rail = mk('Frame', {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(0, 46, 1, -30),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, window)

	local railLayout = mk('UIListLayout', {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rail)
	mk('UIPadding', { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 7) }, rail)

	for i, tabDef in ipairs(TABS) do
		local b = mk('TextButton', {
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Color3.fromRGB(36, 36, 41),
			BorderSizePixel = 0,
			Text = tabDef.glyph,
			TextColor3 = DIM,
			TextSize = 14,
			Font = Enum.Font.UbuntuBold,
			ZIndex = 12,
		}, rail)
		round(b, 7)
		b.MouseButton1Click:Connect(function()
			currentTab = i
			showTab(i)
		end)
		tabDef.button = b
	end

	scroll = mk('ScrollingFrame', {
		Position = UDim2.fromOffset(46, 30),
		Size = UDim2.new(1, -46, 1, -30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(70, 70, 78),
		CanvasSize = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 11,
	}, window)
	mk('UIListLayout', {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	mk('UIPadding', { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, scroll)

	page = {}
	for i = 1, #TABS do
		page[i] = mk('Frame', {
			Size = UDim2.new(1, -8, 0, 0),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			ZIndex = 12,
		}, scroll)
	end
end

function showTab(index)
	currentTab = index
	for i = 1, #TABS do
		page[i].Visible = i == index
		TABS[i].button.BackgroundColor3 = i == index and ACCENT or Color3.fromRGB(36, 36, 41)
		TABS[i].button.TextColor3 = i == index and Color3.new(1, 1, 1) or DIM
	end
	scroll.CanvasPosition = Vector2.new(0, 0)
end

-- The window (and therefore `scroll` / `page`) has to exist before any widget
-- is constructed, because every widget parents itself into the active page.
-- Wrapped so a failure shows up on screen instead of leaving an empty gui.
local builtOK = guard('ui/window', function()
	buildWindow()
	showTab(1)
end)

--------------------------------------------------------------------------
-- 3. core
--------------------------------------------------------------------------

local Core = {}
Core.cache = setmetatable({}, { __mode = 'k' })

local PART_ORDER = { 'Head', 'UpperTorso', 'Torso', 'LowerTorso', 'HumanoidRootPart' }

local function collectParts(character)
	local parts = {}
	for _, n in ipairs(PART_ORDER) do
		local p = character:FindFirstChild(n)
		if p and p:IsA('BasePart') then
			parts[n] = p
		end
	end
	return parts
end

local function weaponOf(entry)
	local character = entry.player.Character
	if not character then return '' end
	local tool = character:FindFirstChildWhichIsA('Tool')
	if not tool then
		local backpack = lplr:FindFirstChildOfClass('Backpack')
		tool = backpack and backpack:FindFirstChildWhichIsA('Tool')
	end
	if not tool then return '' end
	local n = tool.Name
	if n == 'Melee' or n == 'Fists' or n == 'Knife' then return '' end
	return n
end

local function kevlarOf(entry)
	local p = entry.player
	local v = p:FindFirstChild('Kevlar') or p:FindFirstChild('Armor')
	local ls = p:FindFirstChild('leaderstats')
	if not v and ls then
		v = ls:FindFirstChild('Kevlar') or ls:FindFirstChild('Armor')
	end
	if v and (v:IsA('NumberValue') or v:IsA('IntValue')) then
		return v.Value
	end
	return 0
end

function Core.Get(player)
	if player == lplr then return nil end
	local entry = Core.cache[player]
	if entry then return entry end

	entry = {
		player = player,
		name = player.Name,
		weaponDirty = true,
		kevlarDirty = true,
	}
	entry.shortName = #entry.name > 4 and (entry.name:sub(1, 4) .. '..') or entry.name
	Core.cache[player] = entry

	local function setup(char)
		entry.character = nil
		entry.humanoid = nil
		entry.parts = nil
		entry.weaponDirty = true
		if not char then return end
		entry.character = char
		entry.humanoid = char:FindFirstChildOfClass('Humanoid')
		entry.parts = collectParts(char)
		entry.weaponDirty = true
	end

	setup(player.Character)
	player.CharacterAdded:Connect(setup)
	player.CharacterRemoving:Connect(function()
		entry.character, entry.humanoid, entry.parts = nil, nil, nil
	end)

	task.spawn(function()
		for _ = 1, 12 do
			if entry.character and (not entry.parts or not next(entry.parts)) then
				entry.parts = collectParts(entry.character)
				entry.humanoid = entry.character:FindFirstChildOfClass('Humanoid')
			else
				return
			end
			task.wait(0.1)
		end
	end)

	local function touch()
		entry.weaponDirty = true
		entry.kevlarDirty = true
	end
	player.ChildAdded:Connect(touch)
	player.ChildRemoved:Connect(touch)

	return entry
end

function Core.IsAlive(entry)
	local h = entry.humanoid
	return h ~= nil and h.Health > 0 and entry.parts ~= nil and entry.parts.Head ~= nil
end

function Core.PrimaryPart(entry)
	local p = entry.parts
	if not p then return nil end
	return p.HumanoidRootPart or p.UpperTorso or p.Torso
end

function Core.IsEnemy(entry, cfg)
	if not cfg.TeamCheck then return true end
	local mine, theirs = lplr.Team, entry.player.Team
	if not mine or not theirs then return true end
	if mine == theirs then return false end
	if not cfg.NeutralIsEnemy then
		if mine.Name == 'Neutral' or theirs.Name == 'Neutral' then
			return false
		end
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

function Core.IsAliveLocal()
	local c = lplr.Character
	if not c then return false end
	local h = c:FindFirstChildOfClass('Humanoid')
	return h ~= nil and h.Health > 0
end

function Core.LocalRoot()
	local c = lplr.Character
	if not c then return nil end
	return c:FindFirstChild('HumanoidRootPart') or c:FindFirstChild('Head')
end

--------------------------------------------------------------------------
-- 4. esp
--------------------------------------------------------------------------

local CFG = {
	esp = {
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
		BoxAspect = 45,
		DistanceInName = true,
	},
	aim = {
		Enabled = false,
		TargetPart = 'Head',
		HeadPriority = true,
		SnapRadius = 40,
		FOV = 180,
		Method = 'Raycast',
		Smoothness = 0,
		HitChance = 100,
		TeamCheck = true,
		NeutralIsEnemy = true,
		RequireAlive = true,
		ShowFOV = true,
		MaxDistance = 900,
	},
}

local COLOURS = {
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

local GROUPS = {
	Enemy = { Box = true, HealthBar = true, KevlarBar = false, Name = true, Weapon = true, HealthText = false, Chams = false },
	Team = { Box = false, HealthBar = false, KevlarBar = false, Name = true, Weapon = false, HealthText = false, Chams = false },
	Priority = { Box = true, HealthBar = true, KevlarBar = false, Name = true, Weapon = true, HealthText = false, Chams = false },
}

local sqrt, abs, floor, min, max = math.sqrt, math.abs, math.floor, math.min, math.max
local v2, v3 = Vector2.new, Vector3.new
local haveDrawing = type(Drawing) == 'function'

local espFolder = mk('Folder', { Name = 'VandisESP' }, game:GetService('CoreGui'))

local espPool = setmetatable({}, { __mode = 'k' })
local priority = {}
local frameCounter = 0
local rayBudget = 0
local rayParams = nil

local function eput(el, key, value)
	local c = el.c
	if c[key] ~= value then
		c[key] = value
		el.d[key] = value
	end
end

local function ehide(el)
	if el.c.Visible then
		el.c.Visible = false
		el.d.Visible = false
	end
end

local function ehideAll(state)
	for _, bucket in pairs(state.pool) do
		for _, el in pairs(bucket) do
			ehide(el)
		end
	end
	if state.chams then state.chams.Enabled = false end
end

local function edraw(state, group, key, kind)
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

local function egetState(player)
	local state = espPool[player]
	if state then return state end
	state = {
		player = player,
		pool = {},
		frame = 0,
		distShown = -1,
		distText = '',
		visibleKnown = false,
		visible = false,
		visibleFrame = -99,
	}
	espPool[player] = state
	return state
end

local function ecadence(dist)
	if dist < 120 then return 1 end
	if dist < 300 then return 2 end
	if dist < 600 then return 3 end
	return 4
end

local function efade(dist)
	local C = CFG.esp
	if dist <= C.FadeStart then return 0 end
	if dist >= C.MaxDistance then return 1 end
	return max(0, min(1, (dist - C.FadeStart) / (C.MaxDistance - C.FadeStart)))
end

local function evisible(state, target)
	local C = CFG.esp
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
	rayParams.FilterDescendantsInstances = { lplr.Character, espFolder }

	local cam = workspace.CurrentCamera
	if not cam then return state.visible end
	local o = cam.CFrame.Position
	local dx, dy, dz = target.Position.X - o.X, target.Position.Y - o.Y, target.Position.Z - o.Z
	local mag = sqrt(dx * dx + dy * dy + dz * dz)
	if mag < 0.001 then
		state.visibleKnown, state.visible = true, true
		return true
	end
	local hit = workspace:Raycast(o, v3(dx / mag, dy / mag, dz / mag), rayParams)
	state.visibleKnown = true
	state.visible = hit ~= nil and hit.Instance:IsDescendantOf(state.player.Character)
	return state.visible
end

local function edrawText(state, group, key, text, x, y, col, transparency)
	local t = edraw(state, group, key, 'Text')
	if not t then return end
	eput(t, 'Visible', true)
	eput(t, 'Text', text)
	eput(t, 'Position', v2(floor(x), floor(y)))
	eput(t, 'Center', true)
	eput(t, 'Color', col)
	eput(t, 'Transparency', transparency)
	eput(t, 'Size', CFG.esp.TextSize)
	eput(t, 'Font', 2)
	eput(t, 'Outline', CFG.esp.Outlines)
end

local function erenderPlayer(state, entry, cam, camPos, dist)
	local C = CFG.esp
	local group = priority[entry.player] and 'Priority' or (Core.IsEnemy(entry, C) and 'Enemy' or 'Team')
	local conf = GROUPS[group]
	local col = COLOURS[group]

	local root = Core.PrimaryPart(entry)
	local parts = entry.parts
	if not root or not parts then
		ehideAll(state)
		return
	end

	local head = parts.Head
	local hum = entry.humanoid
	local topPos = head and head.Position or root.Position
	local botPos = root.Position - v3(0, (hum and hum.HipHeight or 2), 0)

	local okT, spT = pcall(cam.WorldToViewportPoint, cam, topPos)
	local okB, spB = pcall(cam.WorldToViewportPoint, cam, botPos)
	if not (okT and okB) or not spT or not spB or spT.Z <= 0 or spB.Z <= 0 then
		ehideAll(state)
		return
	end
	if C.VisibleCheck and not evisible(state, head or root) then
		ehideAll(state)
		return
	end

	local h = abs(spB.Y - spT.Y)
	local w = h * (C.BoxAspect / 100)
	if h < 1 or w < 1 then
		ehideAll(state)
		return
	end

	local bx, by = spT.X - w / 2, spT.Y
	local bs = v2(floor(w), floor(h))
	local transparency = efade(dist)
	local centreX = floor(bx + bs.X / 2)

	local metres = floor(dist / 3)
	if state.distShown ~= metres then
		state.distShown = metres
		state.distText = '[' .. metres .. 'm]'
	end

	if conf.Box then
		local box = edraw(state, group, 'box', 'Square')
		if box then
			eput(box, 'Visible', true)
			eput(box, 'Position', v2(floor(bx), floor(by)))
			eput(box, 'Size', bs)
			eput(box, 'Color', col.Box)
			eput(box, 'Transparency', transparency)
			eput(box, 'Filled', false)
			eput(box, 'Thickness', 1)
		end
		if C.Outlines then
			local ol = edraw(state, group, 'boxOutline', 'Square')
			if ol then
				eput(ol, 'Visible', true)
				eput(ol, 'Position', v2(floor(bx) - 1, floor(by) - 1))
				eput(ol, 'Size', bs + v2(2, 2))
				eput(ol, 'Color', Color3.new(0, 0, 0))
				eput(ol, 'Transparency', transparency)
				eput(ol, 'Filled', false)
				eput(ol, 'Thickness', 1)
			end
		end
	end

	if conf.HealthBar and hum then
		local back = edraw(state, group, 'hpBack', 'Square')
		if back then
			eput(back, 'Visible', true)
			eput(back, 'Position', v2(floor(bx) - 4, floor(by)))
			eput(back, 'Size', v2(2, bs.Y))
			eput(back, 'Color', col.HealthBack)
			eput(back, 'Transparency', transparency)
			eput(back, 'Filled', true)
			eput(back, 'Thickness', 1)
		end
		local bar = edraw(state, group, 'hp', 'Square')
		if bar then
			eput(bar, 'Visible', true)
			eput(bar, 'Position', v2(floor(bx) - 4, floor(by)))
			eput(bar, 'Size', v2(2, max(1, floor(bs.Y * max(0, min(1, hum.Health / 100))))))
			eput(bar, 'Color', col.Health)
			eput(bar, 'Transparency', transparency)
			eput(bar, 'Filled', true)
			eput(bar, 'Thickness', 1)
		end
	end

	if conf.KevlarBar then
		local kev = Core.Kevlar(entry)
		if kev > 0 then
			local back = edraw(state, group, 'kvBack', 'Square')
			if back then
				eput(back, 'Visible', true)
				eput(back, 'Position', v2(floor(bx) + bs.X + 2, floor(by)))
				eput(back, 'Size', v2(2, bs.Y))
				eput(back, 'Color', col.KevlarBack)
				eput(back, 'Transparency', transparency)
				eput(back, 'Filled', true)
				eput(back, 'Thickness', 1)
			end
			local bar = edraw(state, group, 'kv', 'Square')
			if bar then
				eput(bar, 'Visible', true)
				eput(bar, 'Position', v2(floor(bx) + bs.X + 2, floor(by)))
				eput(bar, 'Size', v2(2, max(1, floor(bs.Y * max(0, min(1, kev / 100))))))
				eput(bar, 'Color', col.Kevlar)
				eput(bar, 'Transparency', transparency)
				eput(bar, 'Filled', true)
				eput(bar, 'Thickness', 1)
			end
		end
	end

	if conf.Name then
		local label = C.ShortNames and entry.shortName or entry.name
		local text = C.DistanceInName and (state.distText .. ' ' .. label) or label
		edrawText(state, group, 'name', text, centreX, floor(by) - 14, col.Text, transparency)
	end

	if conf.Weapon then
		local weapon = Core.Weapon(entry)
		if weapon ~= '' then
			edrawText(state, group, 'weapon', weapon, centreX, floor(by) + bs.Y + 2, col.Text, transparency)
		end
	end

	if conf.HealthText and hum then
		edrawText(state, group, 'hpText', floor(hum.Health) .. ' hp', centreX, floor(by) - 28, col.Text, transparency)
	end

	if conf.Chams and entry.character then
		if not state.chams or state.chams.Parent ~= entry.character then
			if state.chams then pcall(function() state.chams:Destroy() end) end
			local ok, h = pcall(function()
				local hl = Instance.new('Highlight')
				hl.Adornee = entry.character
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.FillTransparency = 0.75
				hl.OutlineTransparency = 0.25
				hl.Enabled = false
				hl.Parent = espFolder
				return hl
			end)
			state.chams = ok and h or nil
		end
		if state.chams then
			state.chams.Enabled = true
			state.chams.FillColor = col.Box
			state.chams.OutlineColor = col.Text
		end
	end
end

local function erender()
	frameCounter += 1
	rayBudget = CFG.esp.VisibleCheck and 6 or 0

	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	local enabled = CFG.esp.Enabled

	for _, player in Players:GetPlayers() do
		if player ~= lplr then
			local state = espPool[player]
			if state then
				local entry, dist, redraw
				if enabled then
					entry = Core.Get(player)
					local root = entry and Core.IsAlive(entry) and Core.PrimaryPart(entry) or nil
					if root then
						local dx, dy, dz = root.Position.X - camPos.X, root.Position.Y - camPos.Y,
							root.Position.Z - camPos.Z
						dist = sqrt(dx * dx + dy * dy + dz * dz)
						if CFG.esp.LimitDistance and dist > CFG.esp.MaxDistance then
							ehideAll(state)
						else
							state.frame += 1
							redraw = state.frame % ecadence(dist) == 0
						end
					else
						ehideAll(state)
					end
				else
					ehideAll(state)
				end

				if redraw then
					-- reset only on frames we redraw, otherwise banding flickers
					for _, bucket in pairs(state.pool) do
						for _, el in pairs(bucket) do
							ehide(el)
						end
					end
					if state.chams then state.chams.Enabled = false end
					erenderPlayer(state, entry, cam, camPos, dist)
				end
			elseif enabled then
				egetState(player)
			end
		end
	end
end

--------------------------------------------------------------------------
-- 5. silent aim
--------------------------------------------------------------------------

local aimPart = nil
local aimEntry = nil
local lastPick = -1
local oldRaycast = nil
local rayHooked = false
local fovCircle = nil

local function ensureFOV()
	if fovCircle or not CFG.aim.ShowFOV or not haveDrawing then return fovCircle end
	local ok, d = pcall(Drawing.new, 'Circle')
	if not ok or not d then return nil end
	d.Thickness = 1
	d.NumSides = 64
	d.Filled = false
	d.Transparency = 0.4
	d.Color = ACCENT
	d.Visible = false
	fovCircle = d
	return d
end

local PART_MAP = {
	['Head'] = { 'Head' },
	['Upper Torso'] = { 'UpperTorso', 'Torso' },
	['Torso'] = { 'Torso', 'UpperTorso' },
	['Root'] = { 'HumanoidRootPart' },
}

local function pickTarget()
	local C = CFG.aim
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	if C.RequireAlive and not Core.IsAliveLocal() then return nil end
	local lroot = Core.LocalRoot()
	if not lroot then return nil end

	local mp = v2(mouse.X, mouse.Y)
	local bestEntry, bestPart, bestScore

	for _, player in Players:GetPlayers() do
		if player ~= lplr then
			local entry = Core.Get(player)
			if entry and Core.IsAlive(entry) and Core.IsEnemy(entry, C) then
				local anchor = Core.PrimaryPart(entry)
				if anchor then
					local dx, dy, dz = anchor.Position.X - lroot.Position.X, anchor.Position.Y - lroot.Position.Y,
						anchor.Position.Z - lroot.Position.Z
					if sqrt(dx * dx + dy * dy + dz * dz) <= C.MaxDistance then
						local order
						if C.TargetPart == 'Closest' or C.TargetPart == 'Auto' then
							order = { 'Head', 'UpperTorso', 'Torso', 'HumanoidRootPart' }
						else
							order = PART_MAP[C.TargetPart] or PART_MAP.Head
						end

						local picked
						for _, name in ipairs(order) do
							local part = entry.parts and entry.parts[name]
							if part and part.Parent then
								local ok, sp = pcall(cam.WorldToViewportPoint, cam, part.Position)
								if ok and sp and sp.Z > 0 then
									local px, py = sp.X - mp.X, sp.Y - mp.Y
									local d = sqrt(px * px + py * py)
									if C.HeadPriority and name == 'Head' and d <= C.SnapRadius then
										picked = { part, d }
										break
									end
									if d <= C.SnapRadius and not picked then
										picked = { part, d }
									elseif d <= C.FOV and (not picked or d < picked[2]) then
										picked = { part, d }
									end
								end
							end
						end

						if picked and picked[1] and (not bestScore or picked[2] < bestScore) then
							bestEntry, bestPart, bestScore = entry, picked[1], picked[2]
						end
					end
				end
			end
		end
	end

	return bestPart and bestEntry or nil, bestPart
end

local function refreshTarget(force)
	local now = os.clock()
	if not force and (now - lastPick) < 0.05 then return end
	lastPick = now
	local entry, part = pickTarget()
	if part ~= aimPart then
		aimPart = part
		aimEntry = entry
	end
end

local function installHook()
	if rayHooked or type(hookfunction) ~= 'function' then return end
	oldRaycast = workspace.Raycast
	hookfunction(workspace, 'Raycast', function(self, origin, direction, params, ...)
		if CFG.aim.Enabled and aimPart and CFG.aim.Method == 'Raycast' and aimPart.Parent then
			local p = aimPart
			local ox, oy, oz = origin.X, origin.Y, origin.Z
			local dx, dy, dz = p.Position.X - ox, p.Position.Y - oy, p.Position.Z - oz
			local mag = sqrt(dx * dx + dy * dy + dz * dz)
			if mag > 0.001 then
				local shot = RaycastParams.new()
				shot.FilterType = Enum.RaycastFilterType.Exclude
				shot.IgnoreWater = true
				shot.FilterDescendantsInstances = { lplr.Character }
				return oldRaycast(self, v3(ox, oy, oz), v3(dx / mag, dy / mag, dz / mag), shot)
			end
		end
		return oldRaycast(self, origin, direction, params, ...)
	end)
	rayHooked = true
end

local function cameraShot()
	if not aimPart or not aimPart.Parent then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local saved = cam.CFrame
	local pos = cam.CFrame.Position
	local dir = aimPart.Position - pos
	if dir.Magnitude < 0.001 then return end
	local goal = CFrame.lookAt(pos, aimPart.Position)
	local s = CFG.aim.Smoothness
	if s > 0 then
		goal = saved:Lerp(goal, math.clamp(s / 100, 0.05, 1))
	end
	cam.CFrame = goal
	task.defer(function()
		if workspace.CurrentCamera then
			workspace.CurrentCamera.CFrame = saved
		end
	end)
end

--------------------------------------------------------------------------
-- 6. pages + wiring
--------------------------------------------------------------------------

local TAB_AIM, TAB_VIS, TAB_SET = addTab('Aimbot', 'A'), addTab('Visuals', 'V'), addTab('Settings', 'S')

-- Aimbot --------------------------------------------------------------------
guard('ui/aimbot', function()
	UI.Keybind(TAB_AIM, 'silent aim', 'key', nil)
	UI.Toggle(TAB_AIM, 'silent aim', 'enabled')
	UI.Dropdown(TAB_AIM, 'silent aim', 'hitbox', { 'Head', 'Upper Torso', 'Torso', 'Root', 'Closest', 'Auto' }, 'Head')
	UI.Toggle(TAB_AIM, 'silent aim', 'head priority', true)
	UI.Slider(TAB_AIM, 'silent aim', 'head snap', 5, 200, 40)
	UI.Slider(TAB_AIM, 'silent aim', 'fov', 20, 600, 180)
	UI.Slider(TAB_AIM, 'silent aim', 'max distance', 50, 3000, 900)
	UI.Dropdown(TAB_AIM, 'silent aim', 'method', { 'Raycast', 'Camera' }, 'Raycast')
	UI.Slider(TAB_AIM, 'silent aim', 'smoothness', 0, 100, 0)
	UI.Slider(TAB_AIM, 'silent aim', 'hit chance', 0, 100, 100)
	UI.Toggle(TAB_AIM, 'silent aim', 'show fov', true)
	UI.Toggle(TAB_AIM, 'silent aim', 'team check', true)
	UI.Toggle(TAB_AIM, 'silent aim', 'neutral is enemy', true)
	UI.Toggle(TAB_AIM, 'silent aim', 'require alive', true)
end)

-- Visuals -------------------------------------------------------------------
guard('ui/visuals', function()
	UI.Keybind(TAB_VIS, 'esp', 'key', nil)
	UI.Toggle(TAB_VIS, 'esp', 'enabled')
	UI.Slider(TAB_VIS, 'esp', 'max distance', 100, 3000, 1200)
	UI.Slider(TAB_VIS, 'esp', 'fade start', 100, 3000, 1100)
	UI.Slider(TAB_VIS, 'esp', 'text size', 8, 24, 13)
	UI.Slider(TAB_VIS, 'esp', 'box aspect', 10, 120, 45)
	UI.Toggle(TAB_VIS, 'esp', 'outlines', true)
	UI.Toggle(TAB_VIS, 'esp', 'short names')
	UI.Toggle(TAB_VIS, 'esp', 'distance in name', true)
	UI.Toggle(TAB_VIS, 'esp', 'enemy box', true)
	UI.Toggle(TAB_VIS, 'esp', 'enemy health bar', true)
	UI.Toggle(TAB_VIS, 'esp', 'enemy kevlar bar')
	UI.Toggle(TAB_VIS, 'esp', 'enemy name', true)
	UI.Toggle(TAB_VIS, 'esp', 'enemy weapon', true)
	UI.Toggle(TAB_VIS, 'esp', 'enemy health text')
	UI.Toggle(TAB_VIS, 'esp', 'enemy chams')
	UI.Toggle(TAB_VIS, 'esp', 'team name', true)
	UI.Toggle(TAB_VIS, 'esp', 'team box')
end)

-- Settings ------------------------------------------------------------------
guard('ui/settings', function()
	UI.Toggle(TAB_SET, 'filters', 'team check', true)
	UI.Toggle(TAB_SET, 'filters', 'neutral is enemy', true)
	UI.Toggle(TAB_SET, 'filters', 'visible check')
	UI.Toggle(TAB_SET, 'filters', 'limit distance', true)
	UI.TextBox(TAB_SET, 'info', 'target', 'none', true)
	UI.TextBox(TAB_SET, 'info', 'version', VERSION, true)
end)

local function bind()
	local A, E = CFG.aim, CFG.esp

	local akey = valueOf(TAB_AIM, 'silent aim', 'key')
	local aen = valueOf(TAB_AIM, 'silent aim', 'enabled')
	A.Enabled = (aen and aen.Toggle) or (akey and akey.Active) or false

	local hitbox = valueOf(TAB_AIM, 'silent aim', 'hitbox')
	if hitbox then A.TargetPart = hitbox.Dropdown end
	local prio = valueOf(TAB_AIM, 'silent aim', 'head priority')
	if prio then A.HeadPriority = prio.Toggle end
	local snap = valueOf(TAB_AIM, 'silent aim', 'head snap')
	if snap then A.SnapRadius = snap.Slider end
	local fov = valueOf(TAB_AIM, 'silent aim', 'fov')
	if fov then A.FOV = fov.Slider end
	local md = valueOf(TAB_AIM, 'silent aim', 'max distance')
	if md then A.MaxDistance = md.Slider end
	local mth = valueOf(TAB_AIM, 'silent aim', 'method')
	if mth then A.Method = mth.Dropdown end
	local sm = valueOf(TAB_AIM, 'silent aim', 'smoothness')
	if sm then A.Smoothness = sm.Slider end
	local hc = valueOf(TAB_AIM, 'silent aim', 'hit chance')
	if hc then A.HitChance = hc.Slider end
	local sf = valueOf(TAB_AIM, 'silent aim', 'show fov')
	if sf then A.ShowFOV = sf.Toggle end
	local at = valueOf(TAB_AIM, 'silent aim', 'team check')
	if at then A.TeamCheck = at.Toggle end
	local an = valueOf(TAB_AIM, 'silent aim', 'neutral is enemy')
	if an then A.NeutralIsEnemy = an.Toggle end
	local aa = valueOf(TAB_AIM, 'silent aim', 'require alive')
	if aa then A.RequireAlive = aa.Toggle end

	local ekey = valueOf(TAB_VIS, 'esp', 'key')
	local een = valueOf(TAB_VIS, 'esp', 'enabled')
	E.Enabled = (een and een.Toggle) or (ekey and ekey.Active) or false

	local function slider(section, name, apply)
		local v = valueOf(TAB_VIS, 'esp', name)
		if v then apply(v.Slider) end
	end
	slider('esp', 'max distance', function(x)
		E.MaxDistance = x
	end)
	slider('esp', 'fade start', function(x)
		E.FadeStart = x
	end)
	slider('esp', 'text size', function(x)
		E.TextSize = x
	end)
	slider('esp', 'box aspect', function(x)
		E.BoxAspect = x
	end)

	local function tog(name, apply)
		local v = valueOf(TAB_VIS, 'esp', name)
		if v then apply(v.Toggle) end
	end
	tog('outlines', function(x)
		E.Outlines = x
	end)
	tog('short names', function(x)
		E.ShortNames = x
	end)
	tog('distance in name', function(x)
		E.DistanceInName = x
	end)

	local ENEMY_MAP = {
		['enemy box'] = 'Box',
		['enemy health bar'] = 'HealthBar',
		['enemy kevlar bar'] = 'KevlarBar',
		['enemy name'] = 'Name',
		['enemy weapon'] = 'Weapon',
		['enemy health text'] = 'HealthText',
		['enemy chams'] = 'Chams',
	}
	for label, key in pairs(ENEMY_MAP) do
		tog(label, function(x)
			GROUPS.Enemy[key] = x
		end)
	end
	tog('team box', function(x)
		GROUPS.Team.Box = x
	end)
	tog('team name', function(x)
		GROUPS.Team.Name = x
	end)

	local ft = valueOf(TAB_SET, 'filters', 'team check')
	if ft then E.TeamCheck = ft.Toggle end
	local fn = valueOf(TAB_SET, 'filters', 'neutral is enemy')
	if fn then E.NeutralIsEnemy = fn.Toggle end
	local fv = valueOf(TAB_SET, 'filters', 'visible check')
	if fv then E.VisibleCheck = fv.Toggle end
	local fl = valueOf(TAB_SET, 'filters', 'limit distance')
	if fl then E.LimitDistance = fl.Toggle end

	local info = valueOf(TAB_SET, 'info', 'target')
	if info then
		info.Text = aimEntry and ('%s (%s)'):format(aimEntry.name, aimPart and aimPart.Name or '?') or 'none'
	end
end

task.spawn(function()
	while true do
		pcall(bind)
		task.wait(0.05)
	end
end)

RunService.RenderStepped:Connect(function()
	erender()

	if CFG.aim.Enabled then
		refreshTarget(false)
		if fovCircle or CFG.aim.ShowFOV then
			ensureFOV()
			if fovCircle then
				fovCircle.Visible = CFG.aim.ShowFOV
				if CFG.aim.ShowFOV then
					fovCircle.Position = v2(mouse.X - CFG.aim.FOV, mouse.Y - CFG.aim.FOV)
					fovCircle.Size = v2(CFG.aim.FOV * 2, CFG.aim.FOV * 2)
				end
			end
		end
	else
		aimPart = nil
		aimEntry = nil
		if fovCircle then fovCircle.Visible = false end
	end
end)

UIS.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Insert
		or input.KeyCode == Enum.KeyCode.Backquote then
		if UIS:GetFocusedTextBox() then return end
		setOpen(not UI.visible)
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if CFG.aim.Enabled and not UIS:GetFocusedTextBox() then
			if (not CFG.aim.RequireAlive or Core.IsAliveLocal()) then
				refreshTarget(true)
				if aimPart then
					if CFG.aim.HitChance >= 100 or math.random(100) <= CFG.aim.HitChance then
						if CFG.aim.Method == 'Camera' then cameraShot() end
					end
				end
			end
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local akey = valueOf(TAB_AIM, 'silent aim', 'key')
		local ekey = valueOf(TAB_VIS, 'esp', 'key')
		if akey and akey.Active then akey.Active = false end
		if ekey and ekey.Active then ekey.Active = false end
	end
end)

local function keyDown(k, state)
	local akey = valueOf(TAB_AIM, 'silent aim', 'key')
	local ekey = valueOf(TAB_VIS, 'esp', 'key')
	if akey and akey.Key == k then akey.Active = state end
	if ekey and ekey.Key == k then ekey.Active = state end
end

UIS.InputBegan:Connect(function(input)
	if UIS:GetFocusedTextBox() then return end
	keyDown(input.KeyCode, true)
end)

installHook()
ensureFOV()

print(('[Vandis] v%s ready - Delete toggles the menu'):format(VERSION))