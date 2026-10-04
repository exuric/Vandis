--[[
	Vandis / modules/silentaim.lua
	Silent aim with explicit hitbox selection.

	The "it sometimes hits the torso" problem is a target-part selection bug,
	not a smoothing bug. Two things cause it:
	  * the shot resolves against whatever body part the ray happened to touch
	    first (usually the torso, which is wider), and
	  * selections that pick "nearest part to crosshair" drift onto the torso
	    because it has far more projected area than the head.

	Both are addressed here:
	  * an explicit Target Part dropdown (Head / Upper Torso / Torso / Root /
	    Closest / Auto) so you can hard-lock the head,
	  * a Head Priority bias that keeps the head locked while it stays inside
	    the FOV instead of letting the wider torso steal the shot,
	  * a per-part "snap radius" so the head can be grabbed even when your
	    crosshair is a little off it.
]]

local Core = require(script.Parent.core)
local RunService = Core.RunService
local Players = Core.Players
local UIS = Core.UserInputService
local localPlayer = Core.LocalPlayer
local mouse = localPlayer:GetMouse()

local SA = {}

SA.Config = {
	Enabled = false,
	TargetPart = 'Head', -- Head | Upper Torso | Torso | Root | Closest | Auto
	HeadPriority = true,
	SnapRadius = 40, -- px, how far from the part centre still counts as a hit
	FOV = 180, -- px, selection radius around the crosshair
	Method = 'Raycast', -- Raycast | Camera
	Smoothness = 0, -- 0 = instant, higher = slower camera swing
	TeamCheck = true,
	NeutralIsEnemy = true,
	RequireAlive = true,
	ShowFOV = true,
	MaxDistance = 900,
	HitChance = 100, -- %
}

local C = SA.Config
local sqrt = math.sqrt
local v2, v3 = Vector2.new, Vector3.new

local targetPart = nil
local targetEntry = nil
local lastCheck = -1
local connections = {}
local hooked = false
local oldRaycast = nil

local fovCircle = nil
local function ensureFOV()
	if fovCircle or not C.ShowFOV then return fovCircle end
	if type(Drawing) ~= 'function' then return nil end
	local ok, d = pcall(Drawing.new, 'Circle')
	if not ok or not d then return nil end
	d.Thickness = 1
	d.NumSides = 64
	d.Filled = false
	d.Transparency = 0.5
	d.Color = Color3.fromRGB(255, 255, 255)
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

local function project(part)
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local ok, sp = pcall(cam.WorldToViewportPoint, cam, part.Position)
	if not ok or not sp then return nil end
	if sp.Z <= 0 then return nil end
	return sp
end

--[[
	Pick a target.

	Cheap because Core has already cached every body part, so this is a handful
	of projections - no FindFirstChild, no allocations beyond one vector.
]]
local function pickTarget()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	if C.RequireAlive and not Core.IsAliveLocal() then return nil end

	local mp = v2(mouse.X, mouse.Y)
	local root = Core.LocalRoot()
	if not root then return nil end

	local bestEntry, bestPart, bestScore

	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			local entry = Core.Get(player)
			if entry and Core.IsAlive(entry) and Core.IsEnemy(entry, C) then
				local anchor = Core.PrimaryPart(entry)
				if anchor then
					local dx, dy, dz = anchor.Position.X - root.Position.X, anchor.Position.Y - root.Position.Y,
						anchor.Position.Z - root.Position.Z
					local dist = sqrt(dx * dx + dy * dy + dz * dz)
					if dist <= C.MaxDistance then
						local order
						if C.TargetPart == 'Closest' or C.TargetPart == 'Auto' then
							order = { 'Head', 'UpperTorso', 'Torso', 'HumanoidRootPart' }
						else
							order = PART_MAP[C.TargetPart] or PART_MAP.Head
						end

						local picked
						for _, name in order do
							local part = entry.parts and entry.parts[name]
							if part and part.Parent then
								local sp = project(part)
								if sp then
									local px, py = sp.X - mp.X, sp.Y - mp.Y
									local d = sqrt(px * px + py * py)
									-- Head priority: while the head is within its own
									-- snap radius, nothing else may steal the shot.
									if C.HeadPriority and name == 'Head' and d <= C.SnapRadius then
										picked = { part, d, name }
										break
									end
									if d <= C.SnapRadius and not picked then
										picked = { part, d, name }
									elseif d <= C.FOV and (not picked or d < picked[2]) then
										picked = { part, d, name }
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

	if bestPart then
		return bestEntry, bestPart
	end
	return nil
end

--[[
	Monotonic clock. RenderStepped's GetRenderTime resets every frame, which
	would make a throttle comparison meaningless, so use os.clock instead.
]]
local function frame_now()
	return os.clock()
end

local function refreshTarget(force)
	local now = frame_now()
	if not force and (now - lastCheck) < 0.05 then return end
	lastCheck = now
	local entry, part = pickTarget()
	if part ~= targetPart then
		targetPart = part
		targetEntry = entry
	end
end

--[[
	Raycast redirect.

	Games that validate hits on the client call workspace:Raycast with the
	shooter's camera. We answer with a genuine raycast fired at the target part
	instead, so the result object is a real RaycastResult and the game cannot
	tell it apart from its own.
]]
local function installHook()
	if hooked then return end
	oldRaycast = workspace.Raycast
	if type(hookfunction) ~= 'function' then return end
	hookfunction(workspace, 'Raycast', function(self, origin, direction, params, ...)
		if C.Enabled and targetPart and C.Method == 'Raycast' then
			local part = targetPart
			if part and part.Parent then
				local ox, oy, oz = origin.X, origin.Y, origin.Z
				local dx, dy, dz = part.Position.X - ox, part.Position.Y - oy, part.Position.Z - oz
				local mag = sqrt(dx * dx + dy * dy + dz * dz)
				if mag > 0.001 then
					local shotParams = RaycastParams.new()
					shotParams.FilterType = Enum.RaycastFilterType.Exclude
					shotParams.IgnoreWater = true
					local char = localPlayer.Character
					shotParams.FilterDescendantsInstances = { char }
					return oldRaycast(self, v3(ox, oy, oz), v3(dx / mag, dy / mag, dz / mag), shotParams)
				end
			end
		end
		return oldRaycast(self, origin, direction, params, ...)
	end)
	hooked = true
end

local function uninstallHook()
	if not hooked then return end
	if type(hookfunction) == 'function' and oldRaycast then
		pcall(hookfunction, workspace, 'Raycast', oldRaycast)
	end
	hooked = false
	oldRaycast = nil
end

--[[
	Camera redirect: swing the camera onto the target for the shot frame only,
	then put it straight back. Used when a game validates server side through
	the camera basis rather than a client raycast.
]]
local function cameraShot()
	if not targetPart or not targetPart.Parent then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local saved = cam.CFrame
	local pos = cam.CFrame.Position
	local aim = targetPart.Position
	local dir = (aim - pos)
	if dir.Magnitude < 0.001 then return end
	local goal = CFrame.lookAt(pos, aim)
	if C.Smoothness > 0 then
		goal = saved:Lerp(goal, math.clamp(C.Smoothness / 100, 0.05, 1))
	end
	cam.CFrame = goal
	task.defer(function()
		if workspace.CurrentCamera then
			workspace.CurrentCamera.CFrame = saved
		end
	end)
end

local function onMouseDown()
	if not C.Enabled then return end
	if UIS:GetFocusedTextBox() then return end
	if C.RequireAlive and not Core.IsAliveLocal() then return end
	refreshTarget(true)
	if not targetPart then return end
	if C.HitChance < 100 then
		if math.random(100) > C.HitChance then return end
	end
	if C.Method == 'Camera' then
		cameraShot()
	end
end

local function onRender()
	if not C.Enabled then
		if fovCircle then fovCircle.Visible = false end
		targetPart = nil
		targetEntry = nil
		return
	end

	refreshTarget()

	if fovCircle then
		fovCircle.Visible = C.ShowFOV
		if C.ShowFOV then
			fovCircle.Position = v2(mouse.X - C.FOV, mouse.Y - C.FOV)
			fovCircle.Size = v2(C.FOV * 2, C.FOV * 2)
		end
	end
end

function SA.Init()
	if SA.Initialised then return SA end
	SA.Initialised = true
	ensureFOV()
	installHook()
	table.insert(connections, RunService.RenderStepped:Connect(onRender))
	table.insert(connections, UIS.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onMouseDown()
		end
	end))
	return SA
end

function SA.CurrentTarget()
	return targetEntry, targetPart
end

function SA.Unload()
	for _, c in connections do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	uninstallHook()
	if fovCircle then
		pcall(function()
			fovCircle:Remove()
		end)
		fovCircle = nil
	end
	SA.Initialised = false
end

return SA