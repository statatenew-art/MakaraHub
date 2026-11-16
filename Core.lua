local genv = (typeof(getgenv) == "function" and getgenv()) or _G

local KNOWN_GUIS = {
    Aether = true,
    AetherKeySystem = true,
    AetherDropdownSelect = true,
    AetherColorpickBar = true,
    AetherNotification = true,
}
local KNOWN_SOUNDS = { AetherClickSound = true, AetherBackgroundMusic = true }

local Runtime = {}
function Runtime.new()
    local S = {
        Id = tick(),
        _alive = true,
        _conns = {},
        _threads = setmetatable({}, { __mode = "k" }),
        _instances = {},
        _cleanups = {},
        _globals = {},
    }

    function S:Alive() return self._alive end

    function S:Track(x)
        if not self._alive then
            local t = typeof(x)
            if t == "RBXScriptConnection" then pcall(function() x:Disconnect() end)
            elseif t == "thread" then pcall(task.cancel, x)
            elseif t == "Instance" then pcall(function() x:Destroy() end) end
            return x
        end
        local t = typeof(x)
        if t == "RBXScriptConnection" then table.insert(self._conns, x)
        elseif t == "thread" then self._threads[x] = true
        elseif t == "Instance" then table.insert(self._instances, x)
        elseif t == "function" then table.insert(self._cleanups, x) end
        return x
    end

    function S:OnCleanup(fn) return self:Track(fn) end
    function S:Spawn(fn, ...) return self:Track(task.spawn(fn, ...)) end
    function S:Defer(fn, ...) return self:Track(task.defer(fn, ...)) end
    function S:Delay(t, fn, ...) return self:Track(task.delay(t, fn, ...)) end

    function S:Global(name, value)
        self._globals[name] = true
        genv[name] = value
        if typeof(_G) == "table" then _G[name] = value end
        if typeof(shared) == "table" then shared[name] = value end
        return value
    end

    local function wrapSignal(sig)
        return setmetatable({}, {
            __index = function(_, k)
                if k == "Connect" or k == "ConnectParallel" or k == "Once" then return function(_, fn) return S:Track(sig[k](sig, fn)) end end
                local v = sig[k]
                if type(v) == "function" then return function(_, ...) return v(sig, ...) end end
                return v
            end,
        })
    end

    local proxies = {}
    function S:Service(name)
        if proxies[name] then return proxies[name] end
        local svc = game:GetService(name)
        local proxy = setmetatable({}, {
            __index = function(_, k)
                local v = svc[k]
                if typeof(v) == "RBXScriptSignal" then return wrapSignal(v)
                elseif type(v) == "function" then
                    return function(_, ...)
                        local r = table.pack(v(svc, ...))
                        if typeof(r[1]) == "RBXScriptSignal" then r[1] = wrapSignal(r[1]) end
                        return table.unpack(r, 1, r.n)
                    end
                end
                return v
            end,
            __newindex = function(_, k, v) svc[k] = v end,
        })
        proxies[name] = proxy
        return proxy
    end

    S.task = setmetatable({
        spawn = function(fn, ...) return S:Track(task.spawn(fn, ...)) end,
        defer = function(fn, ...) return S:Track(task.defer(fn, ...)) end,
        delay = function(t, fn, ...) return S:Track(task.delay(t, fn, ...)) end,
    }, { __index = task })

    function S:Destroy()
        if not self._alive then return end
        self._alive = false
        for i = #self._cleanups, 1, -1 do pcall(self._cleanups[i]) end
        table.clear(self._cleanups)
        for _, c in ipairs(self._conns) do pcall(function() if c.Connected then c:Disconnect() end end) end
        table.clear(self._conns)
        local current = coroutine.running()
        for th in pairs(self._threads) do
            if th ~= current and coroutine.status(th) ~= "dead" then pcall(task.cancel, th) end
        end
        table.clear(self._threads)
        for _, inst in ipairs(self._instances) do pcall(function() inst:Destroy() end) end
        table.clear(self._instances)
        for name in pairs(self._globals) do
            genv[name] = nil
            if typeof(_G) == "table" then _G[name] = nil end
            if typeof(shared) == "table" then shared[name] = nil end
        end
        table.clear(self._globals)
    end
    return S
end

genv.AetherRuntime = Runtime
local old = genv.AetherSession
if type(old) == "table" and type(old.Destroy) == "function" then pcall(old.Destroy, old) end
genv.AetherSession = nil

pcall(function()
    if genv._OriginalHttpGet then
        if typeof(restorefunction) == "function" then pcall(restorefunction, game.HttpGet) end
        genv._OriginalHttpGet = nil
    end
    if type(genv._AetherCleanup) == "function" then pcall(genv._AetherCleanup) end
    genv._AetherCleanup = nil
    genv._AetherUnloaded, genv._AetherUnloading, genv._AetherSession = nil, nil, nil
end)

for _, key in ipairs({ "_AetherConnections", "_AetherThreads" }) do
    local list = genv[key]
    if type(list) == "table" then
        for _, x in pairs(list) do
            pcall(function()
                if typeof(x) == "RBXScriptConnection" then x:Disconnect()
                elseif typeof(x) == "thread" then task.cancel(x) end
            end)
        end
    end
    genv[key] = nil
end

pcall(function()
    local parents = {}
    local function add(p) if p and not table.find(parents, p) then table.insert(parents, p) end end
    pcall(function() add(game:GetService("CoreGui")) end)
    pcall(function() if typeof(gethui) == "function" then add(gethui()) end end)
    pcall(function()
        local lp = game:GetService("Players").LocalPlayer
        add(lp and lp:FindFirstChildOfClass("PlayerGui"))
    end)
    for _, parent in ipairs(parents) do
        pcall(function()
            for _, child in ipairs(parent:GetChildren()) do
                if KNOWN_GUIS[child.Name] or child:GetAttribute("AetherUI") == true then
                    pcall(function() child:Destroy() end)
                end
            end
        end)
    end
end)

pcall(function()
    for _, s in ipairs(game:GetService("SoundService"):GetChildren()) do
        if KNOWN_SOUNDS[s.Name] then pcall(function() s:Stop(); s:Destroy() end) end
    end
end)

if typeof(_G) == "table" then _G.SCRIPT_KEY = nil; _G.KEYLESS = nil end
if typeof(shared) == "table" then shared.SCRIPT_KEY = nil; shared.KEYLESS = nil end
genv.AetherSession = Runtime.new()

-- Asıl Hile Kodları Buradan Sonra Çalışır:
local GetEnv = getgenv()
local Previous = GetEnv.UniversalAether
if type(Previous) == "table" and type(Previous.Shutdown) == "function" then
	pcall(Previous.Shutdown)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Config = {
	InterfaceNames = { "Aether" },
	InterfaceGlobals = { "Library", "Aether", "AetherUI", "AetherLibrary", "SaveTheme", "CurrentWindow" },
	GuiName = "UniversalAetherOverlay",
	EspUpdateInterval = 0.05,
	EspMaxHighlights = 31,
	EspBoxSize = Vector2.new(4, 5.6),
	WaitForCharacter = 10,
	FlyTweenStep = 0.1,
	WalkTweenStep = 0.08,
	ServerPageLimit = 100,
	ServerMaxPages = 6,
	ServerFetchRetries = 3,
	ServerRetryDelay = 1.5,
	JumpRequestGap = 0.05,
	AntiVoidMargin = 60,
	TeleportHeight = 3,
	ClickTeleportKey = Enum.KeyCode.LeftAlt,
	HitboxTransparency = 0.7,
	CosmeticsRetry = 12,
	CosmeticsRetryGap = 0.3,
	SearchLimit = 30,
}

local App = {
	Stopped = false,
	Connections = {},
	Modules = {},
	Cleanups = {},
	Library = nil,
	Window = nil,
	Gui = nil,
	IsTouch = UserInputService.TouchEnabled,
	Elements = {},
}

GetEnv.UniversalAether = App

local function IsRunning()
	return GetEnv.UniversalAether == App and not App.Stopped
end

local function Track(Connection)
	table.insert(App.Connections, Connection)
	return Connection
end

local function OnCleanup(Function)
	table.insert(App.Cleanups, Function)
end

local function Notify(Title, Text, Kind)
	local Library = App.Library
	if Library and type(Library.Notify) == "function" then
		pcall(Library.Notify, Library, { Title = Title, Desc = tostring(Text), Time = 4, Type = Kind or "normal", Force = true })
	end
end

local function Guard(Name, Function)
	return function(...)
		if not IsRunning() then
			return
		end
		local Ok, Failure = pcall(Function, ...)
		if not Ok then
			Notify(Name, tostring(Failure), "error")
		end
	end
end

local Capabilities = {
	Clipboard = type(setclipboard) == "function" or type(toclipboard) == "function",
	Request = type(request) == "function" or type(http_request) == "function",
	FpsCap = type(setfpscap) == "function",
	MouseMove = type(mousemoverel) == "function",
	GetConnections = type(getconnections) == "function",
	GetHui = type(gethui) == "function",
	QueueOnTeleport = type(queue_on_teleport) == "function",
}

local function GetCamera()
	return Workspace.CurrentCamera
end

local function GetCharacter()
	return LocalPlayer.Character
end

local function GetHumanoid(Character)
	Character = Character or LocalPlayer.Character
	return Character and Character:FindFirstChildOfClass("Humanoid")
end

local function GetRoot(Character)
	Character = Character or LocalPlayer.Character
	return Character and (Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("Torso") or Character:FindFirstChild("UpperTorso"))
end

local function IsLiving(Character)
	local Humanoid = GetHumanoid(Character)
	return Humanoid ~= nil and Humanoid.Health > 0 and GetRoot(Character) ~= nil
end

local function Clamp(Value, Low, High)
	return math.clamp(tonumber(Value) or Low, Low, High)
end

local function CopyText(Text, Label)
	local Copier = setclipboard or toclipboard
	if type(Copier) ~= "function" then
		Notify("Clipboard", "This executor has no clipboard function: " .. tostring(Text), "warning")
		return false
	end
	local Ok = pcall(Copier, tostring(Text))
	if Ok then
		Notify("Copied", (Label or "Value") .. ": " .. tostring(Text), "normal")
	end
	return Ok
end

local function HttpGetText(Url)
	local Ok, Body = pcall(function()
		return game:HttpGet(Url)
	end)
	if Ok and type(Body) == "string" and Body ~= "" then
		return Body
	end
	local Requester = request or http_request
	if type(Requester) == "function" then
		local RequestOk, Response = pcall(Requester, { Url = Url, Method = "GET" })
		if RequestOk and type(Response) == "table" and type(Response.Body) == "string" and Response.StatusCode ~= 429 then
			return Response.Body
		end
	end
	return nil
end

local function GetGuiParent()
	if Capabilities.GetHui then
		local Ok, Hui = pcall(gethui)
		if Ok and typeof(Hui) == "Instance" then
			return Hui
		end
	end
	local Ok = pcall(function()
		return CoreGui:GetChildren()
	end)
	if Ok then
		return CoreGui
	end
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function BuildOverlay()
	local Parent = GetGuiParent()
	if Parent then
		local Old = Parent:FindFirstChild(Config.GuiName)
		if Old then
			pcall(Old.Destroy, Old)
		end
	end
	local Gui = Instance.new("ScreenGui")
	Gui.Name = Config.GuiName
	Gui.ResetOnSpawn = false
	Gui.IgnoreGuiInset = true
	Gui.DisplayOrder = 998
	Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	Gui.Parent = Parent
	App.Gui = Gui
	OnCleanup(function()
		pcall(Gui.Destroy, Gui)
	end)
	return Gui
end

local function CharacterOrWait()
	local Character = LocalPlayer.Character
	if Character and GetRoot(Character) and GetHumanoid(Character) then
		return Character
	end
	local Started = os.clock()
	while IsRunning() and os.clock() - Started < Config.WaitForCharacter do
		task.wait(0.2)
		Character = LocalPlayer.Character
		if Character and GetRoot(Character) and GetHumanoid(Character) then
			return Character
		end
	end
	return nil
end

local function TeleportCharacter(Target)
	local Root = GetRoot()
	if not Root then
		return false
	end
	local Frame = typeof(Target) == "Vector3" and CFrame.new(Target) or Target
	Root.AssemblyLinearVelocity = Vector3.zero
	Root.CFrame = Frame
	return true
end

local function IsEnemy(Player)
	local Mine, Theirs = LocalPlayer.Team, Player.Team
	if Mine == nil or Theirs == nil then
		return true
	end
	return Mine ~= Theirs
end

local function OtherPlayers()
	local List = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= LocalPlayer then
			table.insert(List, Player)
		end
	end
	return List
end

local function PlayerNames()
	local Names = {}
	for _, Player in ipairs(OtherPlayers()) do
		table.insert(Names, Player.Name)
	end
	table.sort(Names)
	return Names
end

local function FindPlayer(Query)
	if type(Query) ~= "string" or Query == "" then
		return nil
	end
	local Lower = string.lower(Query)
	for _, Player in ipairs(Players:GetPlayers()) do
		if string.lower(Player.Name) == Lower or string.lower(Player.DisplayName) == Lower then
			return Player
		end
	end
	for _, Player in ipairs(Players:GetPlayers()) do
		if string.find(string.lower(Player.Name), Lower, 1, true) or string.find(string.lower(Player.DisplayName), Lower, 1, true) then
			return Player
		end
	end
	return nil
end

local CharacterListeners = {}

local function OnCharacter(Callback)
	table.insert(CharacterListeners, Callback)
	if LocalPlayer.Character then
		task.spawn(Callback, LocalPlayer.Character)
	end
end

Track(LocalPlayer.CharacterAdded:Connect(function(Character)
	for _, Callback in ipairs(CharacterListeners) do
		task.spawn(function()
			pcall(Callback, Character)
		end)
	end
end))

local function DisconnectAll(List)
	for _, Connection in ipairs(List) do
		pcall(Connection.Disconnect, Connection)
	end
	table.clear(List)
end

local Settings = {
	WalkSpeed = { Enabled = false, Mode = "Property", Value = 50 },
	JumpPower = { Enabled = false, Mode = "Property", Value = 100 },
	InfiniteJump = { Enabled = false },
	Fly = { Enabled = false, Mode = "Velocity", Speed = 60, VerticalSpeed = 50, Smoothing = 8, Noclip = true, FaceCamera = true },
	Noclip = { Enabled = false },
	ClickTeleport = { Enabled = false, RequireKey = true },
	AntiVoid = { Enabled = false },
	AntiAfk = { Enabled = true },
	AutoRejoin = { Enabled = false },
	Esp = {
		Enabled = false, TeamCheck = false, Chams = true, Boxes = true, Names = true, Health = true, Distance = true,
		Tracers = false, MaxDistance = 1500, FillTransparency = 0.6, TeamColors = false,
		EnemyColor = Color3.fromRGB(255, 70, 70), AllyColor = Color3.fromRGB(80, 200, 120),
	},
	Aim = {
		Enabled = false, Mode = "Hold", HoldInput = "Right Mouse", Method = "Camera", Part = "Head", Priority = "Cursor",
		Fov = 150, Smoothing = 4, Prediction = 0, MaxDistance = 1200, TeamCheck = true, WallCheck = true, Sticky = true,
		ShowFov = true, FovOrigin = "Mouse", ShowButton = true, FovColor = Color3.fromRGB(255, 255, 255),
	},
	Hitbox = { Enabled = false, Size = 8, TeamCheck = true },
	World = {
		Fullbright = false, NoFog = false, NoShadows = false, LockTime = false, TimeOfDay = 14, Gravity = Workspace.Gravity,
		LockFov = false, Fov = 70, MaxZoom = 128, XRay = false,
	},
}
App.Settings = Settings

local Movement = { ControlsModule = nil }
App.Modules.Movement = Movement

function Movement.GetControls()
	if Movement.ControlsModule ~= nil then
		return Movement.ControlsModule or nil
	end
	local Scripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local Module = Scripts and Scripts:FindFirstChild("PlayerModule")
	local Controls = false
	if Module then
		local Ok, Loaded = pcall(require, Module)
		if Ok and type(Loaded) == "table" and type(Loaded.GetControls) == "function" then
			local ControlsOk, Result = pcall(Loaded.GetControls, Loaded)
			if ControlsOk and Result then
				Controls = Result
			end
		end
	end
	Movement.ControlsModule = Controls
	return Controls or nil
end

function Movement.GetSteering()
	local Camera = GetCamera()
	if not Camera then
		return Vector3.zero
	end
	local Controls = Movement.GetControls()
	if Controls then
		local Ok, Vector = pcall(Controls.GetMoveVector, Controls)
		if Ok and typeof(Vector) == "Vector3" then
			if Vector.Magnitude > 1 then
				Vector = Vector.Unit
			end
			return Camera.CFrame:VectorToWorldSpace(Vector3.new(Vector.X, 0, Vector.Z))
		end
	end
	local Humanoid = GetHumanoid()
	return Humanoid and Humanoid.MoveDirection or Vector3.zero
end

local Noclip = { Connection = nil, Sources = {}, Original = {}, Parts = {}, Character = nil, NextScan = 0 }
App.Modules.Noclip = Noclip

function Noclip.Scan(Character)
	table.clear(Noclip.Parts)
	for _, Part in ipairs(Character:GetDescendants()) do
		if Part:IsA("BasePart") then
			table.insert(Noclip.Parts, Part)
		end
	end
	Noclip.Character = Character
	Noclip.NextScan = os.clock() + 1
end

function Noclip.Refresh()
	local Wanted = Settings.Noclip.Enabled
	for _, Active in pairs(Noclip.Sources) do
		if Active then
			Wanted = true
		end
	end
	if Wanted and not Noclip.Connection then
		Noclip.Connection = RunService.Stepped:Connect(function()
			local Character = GetCharacter()
			if not Character then
				return
			end
			if Noclip.Character ~= Character or os.clock() > Noclip.NextScan then
				Noclip.Scan(Character)
			end
			for _, Part in ipairs(Noclip.Parts) do
				if Part.CanCollide then
					if Noclip.Original[Part] == nil then
						Noclip.Original[Part] = true
					end
					Part.CanCollide = false
				end
			end
		end)
	elseif not Wanted and Noclip.Connection then
		Noclip.Connection:Disconnect()
		Noclip.Connection = nil
		for Part, Original in pairs(Noclip.Original) do
			if Part.Parent then
				Part.CanCollide = Original
			end
		end
		table.clear(Noclip.Original)
		table.clear(Noclip.Parts)
		Noclip.Character = nil
	end
end

function Noclip.Stop()
	Settings.Noclip.Enabled = false
	table.clear(Noclip.Sources)
	Noclip.Refresh()
end

local WalkSpeed = { Connection = nil, Original = nil, TweenAt = 0 }
App.Modules.WalkSpeed = WalkSpeed

function WalkSpeed.Stop()
	if WalkSpeed.Connection then
		WalkSpeed.Connection:Disconnect()
		WalkSpeed.Connection = nil
	end
	local Humanoid = GetHumanoid()
	if Humanoid and WalkSpeed.Original then
		Humanoid.WalkSpeed = WalkSpeed.Original
	end
	WalkSpeed.Original = nil
end

function WalkSpeed.Start()
	WalkSpeed.Stop()
	if not Settings.WalkSpeed.Enabled then
		return
	end
	local Humanoid = GetHumanoid()
	if Humanoid then
		WalkSpeed.Original = Humanoid.WalkSpeed
	end
	WalkSpeed.Connection = RunService.Heartbeat:Connect(function(Delta)
		local Character = GetCharacter()
		local CurrentHumanoid, Root = GetHumanoid(Character), GetRoot(Character)
		if not (CurrentHumanoid and Root) or CurrentHumanoid.Health <= 0 then
			return
		end
		local Mode, Speed = Settings.WalkSpeed.Mode, Settings.WalkSpeed.Value
		if Mode == "Property" then
			if CurrentHumanoid.WalkSpeed ~= Speed then
				CurrentHumanoid.WalkSpeed = Speed
			end
			return
		end
		local Direction = CurrentHumanoid.MoveDirection
		if Direction.Magnitude < 0.01 then
			return
		end
		if Mode == "CFrame" then

			local Extra = math.max(Speed - CurrentHumanoid.WalkSpeed, 0)
			Root.CFrame = Root.CFrame + Direction * (Extra * Delta)
		elseif Mode == "Velocity" then
			local Current = Root.AssemblyLinearVelocity
			Root.AssemblyLinearVelocity = Vector3.new(Direction.X * Speed, Current.Y, Direction.Z * Speed)
		elseif Mode == "Tween" then
			if os.clock() >= WalkSpeed.TweenAt then
				WalkSpeed.TweenAt = os.clock() + Config.WalkTweenStep
				local Extra = math.max(Speed - CurrentHumanoid.WalkSpeed, 0)
				local Goal = Root.CFrame + Direction * (Extra * Config.WalkTweenStep)
				TweenService:Create(Root, TweenInfo.new(Config.WalkTweenStep, Enum.EasingStyle.Linear), { CFrame = Goal }):Play()
			end
		end
	end)
end

local JumpPower = { Connection = nil, OriginalPower = nil, OriginalUse = nil, Jumped = false }
App.Modules.JumpPower = JumpPower

function JumpPower.Stop()
	if JumpPower.Connection then
		JumpPower.Connection:Disconnect()
		JumpPower.Connection = nil
	end
	local Humanoid = GetHumanoid()
	if Humanoid and JumpPower.OriginalPower then
		Humanoid.UseJumpPower = JumpPower.OriginalUse
		Humanoid.JumpPower = JumpPower.OriginalPower
	end
	JumpPower.OriginalPower, JumpPower.OriginalUse = nil, nil
end

function JumpPower.Start()
	JumpPower.Stop()
	if not Settings.JumpPower.Enabled then
		return
	end
	local Humanoid = GetHumanoid()
	if Humanoid then
		JumpPower.OriginalPower, JumpPower.OriginalUse = Humanoid.JumpPower, Humanoid.UseJumpPower
	end
	JumpPower.Connection = RunService.Heartbeat:Connect(function()
		local CurrentHumanoid, Root = GetHumanoid(), GetRoot()
		if not (CurrentHumanoid and Root) then
			return
		end
		local Power = Settings.JumpPower.Value
		if Settings.JumpPower.Mode == "Property" then
			if not CurrentHumanoid.UseJumpPower then
				CurrentHumanoid.UseJumpPower = true
			end
			if CurrentHumanoid.JumpPower ~= Power then
				CurrentHumanoid.JumpPower = Power
			end
		else
			local State = CurrentHumanoid:GetState()
			if State == Enum.HumanoidStateType.Jumping then
				if not JumpPower.Jumped then
					JumpPower.Jumped = true
					local Current = Root.AssemblyLinearVelocity
					Root.AssemblyLinearVelocity = Vector3.new(Current.X, Power, Current.Z)
				end
			elseif State ~= Enum.HumanoidStateType.Freefall then
				JumpPower.Jumped = false
			end
		end
	end)
end

local InfiniteJump = { Connection = nil, Last = 0 }
App.Modules.InfiniteJump = InfiniteJump

function InfiniteJump.Stop()
	if InfiniteJump.Connection then
		InfiniteJump.Connection:Disconnect()
		InfiniteJump.Connection = nil
	end
end

function InfiniteJump.Start()
	InfiniteJump.Stop()
	if not Settings.InfiniteJump.Enabled then
		return
	end
	InfiniteJump.Connection = UserInputService.JumpRequest:Connect(function()
		if os.clock() - InfiniteJump.Last < Config.JumpRequestGap then
			return
		end
		InfiniteJump.Last = os.clock()
		local Humanoid = GetHumanoid()
		if Humanoid and Humanoid.Health > 0 then
			Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

local Fly = {
	Connection = nil, Active = false, Velocity = Vector3.zero, Linear = nil, Align = nil, Attachment = nil,
	PreviousPlatformStand = false, TweenAt = 0, TouchUp = false, TouchDown = false, Buttons = nil,
}
App.Modules.Fly = Fly

function Fly.Vertical()
	local Axis = 0
	if UserInputService:GetFocusedTextBox() == nil then
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
			Axis = Axis + 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			Axis = Axis - 1
		end
	end
	if Fly.TouchUp then
		Axis = Axis + 1
	end
	if Fly.TouchDown then
		Axis = Axis - 1
	end
	return Axis
end

function Fly.EnsureButtons()
	if Fly.Buttons or not App.Gui then
		return
	end
	local Holder = Instance.new("Frame")
	Holder.Name = "FlyButtons"
	Holder.BackgroundTransparency = 1
	Holder.AnchorPoint = Vector2.new(1, 1)
	Holder.Position = UDim2.new(1, -24, 1, -150)
	Holder.Size = UDim2.fromOffset(70, 150)
	Holder.Visible = false
	Holder.Parent = App.Gui
	local function MakeButton(Text, Order, Flag)
		local Button = Instance.new("TextButton")
		Button.Size = UDim2.fromOffset(70, 70)
		Button.Position = UDim2.fromOffset(0, (Order - 1) * 80)
		Button.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
		Button.BackgroundTransparency = 0.25
		Button.Text = Text
		Button.Font = Enum.Font.BuilderSansBold
		Button.TextSize = 18
		Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		Button.AutoButtonColor = true
		Button.Parent = Holder
		Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 12)
		local Outline = Instance.new("UIStroke", Button)
		Outline.Color = Color3.fromRGB(255, 255, 255)
		Outline.Transparency = 0.6
		Button.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
				Fly[Flag] = true
			end
		end)
		Button.InputEnded:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
				Fly[Flag] = false
			end
		end)
	end
	MakeButton("UP", 1, "TouchUp")
	MakeButton("DOWN", 2, "TouchDown")
	Fly.Buttons = Holder
end

function Fly.ShowButtons(Visible)
	Fly.EnsureButtons()
	if Fly.Buttons then
		Fly.Buttons.Visible = Visible and App.IsTouch
	end
	if not Visible then
		Fly.TouchUp, Fly.TouchDown = false, false
	end
end

function Fly.Destroy()
	if Fly.Linear then
		Fly.Linear:Destroy()
	end
	if Fly.Align then
		Fly.Align:Destroy()
	end
	if Fly.Attachment then
		Fly.Attachment:Destroy()
	end
	Fly.Linear, Fly.Align, Fly.Attachment = nil, nil, nil
end

function Fly.Stop()
	if Fly.Connection then
		Fly.Connection:Disconnect()
		Fly.Connection = nil
	end
	Fly.Destroy()
	if Fly.Active then
		local Humanoid, Root = GetHumanoid(), GetRoot()
		if Humanoid then
			Humanoid.PlatformStand = Fly.PreviousPlatformStand
		end
		if Root then
			Root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	Fly.Active = false
	Fly.Velocity = Vector3.zero
	Noclip.Sources.Fly = nil
	Noclip.Refresh()
	Fly.ShowButtons(false)
end

function Fly.Build(Root)
	Fly.Attachment = Instance.new("Attachment")
	Fly.Attachment.Name = "UniversalFlyAttachment"
	Fly.Attachment.Parent = Root
	Fly.Linear = Instance.new("LinearVelocity")
	Fly.Linear.Name = "UniversalFlyVelocity"
	Fly.Linear.Attachment0 = Fly.Attachment
	Fly.Linear.MaxForce = math.huge
	Fly.Linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	Fly.Linear.RelativeTo = Enum.ActuatorRelativeTo.World
	Fly.Linear.VectorVelocity = Vector3.zero
	Fly.Linear.Parent = Root
	Fly.Align = Instance.new("AlignOrientation")
	Fly.Align.Name = "UniversalFlyAlign"
	Fly.Align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	Fly.Align.Attachment0 = Fly.Attachment
	Fly.Align.MaxTorque = math.huge
	Fly.Align.Responsiveness = 40
	Fly.Align.CFrame = Root.CFrame.Rotation
	Fly.Align.Parent = Root
end

function Fly.Step(Delta)
	local Root = GetRoot()
	local Camera = GetCamera()
	local Humanoid = GetHumanoid()
	if not (Root and Camera and Humanoid) or Humanoid.Health <= 0 then
		return
	end
	local FlySettings = Settings.Fly
	local Target = Movement.GetSteering() * FlySettings.Speed + Vector3.yAxis * (Fly.Vertical() * FlySettings.VerticalSpeed)
	local Look = Camera.CFrame.LookVector
	local Facing = CFrame.lookAt(Vector3.zero, Vector3.new(Look.X, 0, Look.Z).Magnitude > 0.01 and Vector3.new(Look.X, 0, Look.Z) or Root.CFrame.LookVector)
	local Mode = FlySettings.Mode

	if Mode == "Velocity" or Mode == "Smooth" then
		if not (Fly.Linear and Fly.Linear.Parent) then
			Fly.Destroy()
			Fly.Build(Root)
		end
		if Mode == "Smooth" then
			Fly.Velocity = Fly.Velocity:Lerp(Target, math.clamp(Delta * FlySettings.Smoothing, 0, 1))
			Fly.Linear.VectorVelocity = Fly.Velocity
		else
			Fly.Linear.VectorVelocity = Target
		end
		if FlySettings.FaceCamera then
			Fly.Align.CFrame = Facing
		end
	else
		Fly.Destroy()
		local Rotation = FlySettings.FaceCamera and Facing.Rotation or Root.CFrame.Rotation
		Root.AssemblyLinearVelocity = Vector3.zero
		Root.AssemblyAngularVelocity = Vector3.zero
		if Mode == "CFrame" then
			Root.CFrame = CFrame.new(Root.Position + Target * Delta) * Rotation
		elseif Mode == "Tween" and os.clock() >= Fly.TweenAt then
			Fly.TweenAt = os.clock() + Config.FlyTweenStep
			local Goal = CFrame.new(Root.Position + Target * Config.FlyTweenStep) * Rotation
			TweenService:Create(Root, TweenInfo.new(Config.FlyTweenStep, Enum.EasingStyle.Linear), { CFrame = Goal }):Play()
		end
	end
end

function Fly.Start()
	Fly.Stop()
	if not Settings.Fly.Enabled then
		return
	end
	local Character = CharacterOrWait()
	if not Character or not Settings.Fly.Enabled then
		return
	end
	local Humanoid = GetHumanoid(Character)
	Fly.Active = true
	Fly.PreviousPlatformStand = Humanoid.PlatformStand
	Humanoid.PlatformStand = true
	Noclip.Sources.Fly = Settings.Fly.Noclip
	Noclip.Refresh()
	Fly.ShowButtons(true)
	Fly.Connection = RunService.RenderStepped:Connect(Fly.Step)
end

local Teleports = { Waypoints = {}, WaypointOrder = {}, ClickConnections = {}, Spectating = nil, VoidConnection = nil, LastSafe = nil, NextSafe = 0 }
App.Modules.Teleports = Teleports

function Teleports.ToPlayer(Name)
	local Player = FindPlayer(Name)
	local Root = Player and Player.Character and GetRoot(Player.Character)
	if not Root then
		Notify("Teleport", "That player has no character right now", "warning")
		return false
	end
	return TeleportCharacter(Root.CFrame * CFrame.new(0, 0, 3))
end

function Teleports.AddWaypoint(Name)
	local Root = GetRoot()
	if not Root then
		return false
	end
	Name = (Name and Name ~= "") and Name or ("Waypoint " .. (#Teleports.WaypointOrder + 1))
	if not Teleports.Waypoints[Name] then
		table.insert(Teleports.WaypointOrder, Name)
	end
	Teleports.Waypoints[Name] = Root.CFrame
	return Name
end

function Teleports.RemoveWaypoint(Name)
	if not Teleports.Waypoints[Name] then
		return false
	end
	Teleports.Waypoints[Name] = nil
	table.remove(Teleports.WaypointOrder, table.find(Teleports.WaypointOrder, Name))
	return true
end

function Teleports.GoToWaypoint(Name)
	local Frame = Teleports.Waypoints[Name]
	if not Frame then
		return false
	end
	return TeleportCharacter(Frame)
end

function Teleports.ClickTarget(Position)
	local Camera = GetCamera()
	if not Camera then
		return
	end
	local Ray = Camera:ViewportPointToRay(Position.X, Position.Y)
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = { GetCharacter() }
	local Result = Workspace:Raycast(Ray.Origin, Ray.Direction * 5000, Params)
	if Result then
		TeleportCharacter(Result.Position + Vector3.new(0, Config.TeleportHeight, 0))
	end
end

function Teleports.StopClick()
	DisconnectAll(Teleports.ClickConnections)
end

function Teleports.StartClick()
	Teleports.StopClick()
	if not Settings.ClickTeleport.Enabled then
		return
	end
	table.insert(Teleports.ClickConnections, UserInputService.InputBegan:Connect(function(Input, Processed)
		if Processed or Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if Settings.ClickTeleport.RequireKey and not UserInputService:IsKeyDown(Config.ClickTeleportKey) then
			return
		end
		Teleports.ClickTarget(UserInputService:GetMouseLocation())
	end))
	table.insert(Teleports.ClickConnections, UserInputService.TouchTapInWorld:Connect(function(Position, Processed)
		if not Processed then
			Teleports.ClickTarget(Position)
		end
	end))
end

function Teleports.Spectate(Name)
	local Player = FindPlayer(Name)
	local Humanoid = Player and Player.Character and GetHumanoid(Player.Character)
	local Camera = GetCamera()
	if not (Humanoid and Camera) then
		Notify("Spectate", "That player has no character right now", "warning")
		return false
	end
	Teleports.Spectating = Player
	Camera.CameraSubject = Humanoid
	return true
end

function Teleports.StopSpectate()
	Teleports.Spectating = nil
	local Camera, Humanoid = GetCamera(), GetHumanoid()
	if Camera and Humanoid then
		Camera.CameraSubject = Humanoid
	end
end

function Teleports.StopVoid()
	if Teleports.VoidConnection then
		Teleports.VoidConnection:Disconnect()
		Teleports.VoidConnection = nil
	end
end

function Teleports.StartVoid()
	Teleports.StopVoid()
	if not Settings.AntiVoid.Enabled then
		return
	end
	Teleports.VoidConnection = RunService.Heartbeat:Connect(function()
		local Root, Humanoid = GetRoot(), GetHumanoid()
		if not (Root and Humanoid) or Humanoid.Health <= 0 then
			return
		end
		local Floor = Workspace.FallenPartsDestroyHeight + Config.AntiVoidMargin
		if Root.Position.Y > Floor + Config.AntiVoidMargin and Humanoid.FloorMaterial ~= Enum.Material.Air and os.clock() >= Teleports.NextSafe then
			Teleports.NextSafe = os.clock() + 0.5
			Teleports.LastSafe = Root.CFrame
		elseif Root.Position.Y < Floor and Teleports.LastSafe then
			TeleportCharacter(Teleports.LastSafe + Vector3.new(0, 4, 0))
		end
	end)
end

OnCleanup(function()
	Teleports.StopClick()
	Teleports.StopVoid()
	Teleports.StopSpectate()
	Fly.Stop()
	if Fly.Buttons then
		Fly.Buttons:Destroy()
	end
	WalkSpeed.Stop()
	JumpPower.Stop()
	InfiniteJump.Stop()
	Noclip.Stop()
end)

OnCharacter(function()
	task.wait(0.3)
	if Settings.WalkSpeed.Enabled then
		WalkSpeed.Start()
	end
	if Settings.JumpPower.Enabled then
		JumpPower.Start()
	end
	if Settings.Fly.Enabled then
		Fly.Start()
	end
	if Teleports.Spectating then
		Teleports.StopSpectate()
	end
end)

local Esp = { Objects = {}, Folder = nil, Connection = nil, NextText = 0, RemovingConnection = nil }
App.Modules.Esp = Esp

function Esp.GetColor(Player)
	local EspSettings = Settings.Esp
	if EspSettings.TeamColors and Player.Team then
		return Player.TeamColor.Color
	end
	return IsEnemy(Player) and EspSettings.EnemyColor or EspSettings.AllyColor
end

function Esp.Create(Player)
	local Object = {}
	Object.Highlight = Instance.new("Highlight")
	Object.Highlight.Name = "Chams_" .. Player.UserId
	Object.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	Object.Highlight.Enabled = false
	Object.Highlight.Parent = Esp.Folder

	Object.Box = Instance.new("BillboardGui")
	Object.Box.Name = "Box_" .. Player.UserId
	Object.Box.AlwaysOnTop = true
	Object.Box.LightInfluence = 0
	Object.Box.Size = UDim2.fromScale(Config.EspBoxSize.X, Config.EspBoxSize.Y)
	Object.Box.Enabled = false
	Object.Box.Parent = Esp.Folder
	local Outline = Instance.new("Frame")
	Outline.BackgroundTransparency = 1
	Outline.Size = UDim2.fromScale(1, 1)
	Outline.Parent = Object.Box
	Object.BoxStroke = Instance.new("UIStroke")
	Object.BoxStroke.Thickness = 1.5
	Object.BoxStroke.Parent = Outline

	Object.Tag = Instance.new("BillboardGui")
	Object.Tag.Name = "Tag_" .. Player.UserId
	Object.Tag.AlwaysOnTop = true
	Object.Tag.LightInfluence = 0
	Object.Tag.Size = UDim2.fromOffset(140, 46)
	Object.Tag.StudsOffset = Vector3.new(0, 3.9, 0)
	Object.Tag.Enabled = false
	Object.Tag.Parent = Esp.Folder
	Object.NameLabel = Instance.new("TextLabel")
	Object.NameLabel.BackgroundTransparency = 1
	Object.NameLabel.Size = UDim2.new(1, 0, 0, 16)
	Object.NameLabel.Font = Enum.Font.BuilderSansBold
	Object.NameLabel.TextSize = 15
	Object.NameLabel.TextStrokeTransparency = 0.4
	Object.NameLabel.Parent = Object.Tag
	Object.BarBack = Instance.new("Frame")
	Object.BarBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	Object.BarBack.BorderSizePixel = 0
	Object.BarBack.Position = UDim2.new(0.15, 0, 0, 19)
	Object.BarBack.Size = UDim2.new(0.7, 0, 0, 5)
	Object.BarBack.Parent = Object.Tag
	Object.BarFill = Instance.new("Frame")
	Object.BarFill.BorderSizePixel = 0
	Object.BarFill.Size = UDim2.fromScale(1, 1)
	Object.BarFill.Parent = Object.BarBack
	Object.InfoLabel = Instance.new("TextLabel")
	Object.InfoLabel.BackgroundTransparency = 1
	Object.InfoLabel.Position = UDim2.new(0, 0, 0, 26)
	Object.InfoLabel.Size = UDim2.new(1, 0, 0, 14)
	Object.InfoLabel.Font = Enum.Font.BuilderSans
	Object.InfoLabel.TextSize = 13
	Object.InfoLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	Object.InfoLabel.TextStrokeTransparency = 0.5
	Object.InfoLabel.Parent = Object.Tag

	if App.Gui then
		Object.Tracer = Instance.new("Frame")
		Object.Tracer.AnchorPoint = Vector2.new(0.5, 0.5)
		Object.Tracer.BorderSizePixel = 0
		Object.Tracer.Visible = false
		Object.Tracer.Parent = App.Gui
	end
	Esp.Objects[Player] = Object
	return Object
end

function Esp.Remove(Player)
	local Object = Esp.Objects[Player]
	if not Object then
		return
	end
	for _, Key in ipairs({ "Highlight", "Box", "Tag", "Tracer" }) do
		if Object[Key] then
			pcall(Object[Key].Destroy, Object[Key])
		end
	end
	Esp.Objects[Player] = nil
end

function Esp.Hide(Object)
	Object.Highlight.Enabled = false
	Object.Box.Enabled = false
	Object.Tag.Enabled = false
	if Object.Tracer then
		Object.Tracer.Visible = false
	end
end

function Esp.Update()
	local EspSettings = Settings.Esp
	local Camera = GetCamera()
	local MyRoot = GetRoot()
	if not Camera then
		return
	end
	local UpdateText = os.clock() >= Esp.NextText
	if UpdateText then
		Esp.NextText = os.clock() + Config.EspUpdateInterval
	end
	local Viewport = Camera.ViewportSize
	local Candidates = {}

	for _, Player in ipairs(OtherPlayers()) do
		local Object = Esp.Objects[Player] or Esp.Create(Player)
		local Character = Player.Character
		local Root = Character and GetRoot(Character)
		local Humanoid = Character and GetHumanoid(Character)
		local Distance = (Root and MyRoot) and (Root.Position - MyRoot.Position).Magnitude or (Root and (Root.Position - Camera.CFrame.Position).Magnitude) or math.huge
		local Visible = Root ~= nil and Humanoid ~= nil and Humanoid.Health > 0 and Distance <= EspSettings.MaxDistance
		if Visible and EspSettings.TeamCheck and not IsEnemy(Player) then
			Visible = false
		end
		if not Visible then
			Esp.Hide(Object)
		else
			local Color = Esp.GetColor(Player)
			table.insert(Candidates, { Object = Object, Distance = Distance })
			Object.Box.Adornee = Root
			Object.Tag.Adornee = Root
			Object.Highlight.Adornee = Character
			Object.Box.Enabled = EspSettings.Boxes
			Object.BoxStroke.Color = Color
			Object.Tag.Enabled = EspSettings.Names or EspSettings.Health or EspSettings.Distance
			if UpdateText then
				Object.NameLabel.Visible = EspSettings.Names
				Object.NameLabel.Text = Player.DisplayName
				Object.NameLabel.TextColor3 = Color
				Object.BarBack.Visible = EspSettings.Health
				local Ratio = math.clamp(Humanoid.Health / math.max(Humanoid.MaxHealth, 1), 0, 1)
				Object.BarFill.Size = UDim2.fromScale(Ratio, 1)
				Object.BarFill.BackgroundColor3 = Color3.fromHSV(Ratio * 0.33, 0.85, 1)
				Object.InfoLabel.Visible = EspSettings.Distance
				Object.InfoLabel.Text = string.format("%d studs", math.floor(Distance + 0.5))
			end
			Object.Highlight.FillColor = Color
			Object.Highlight.OutlineColor = Color
			Object.Highlight.FillTransparency = EspSettings.FillTransparency
			if Object.Tracer then
				local Screen = Camera:WorldToViewportPoint(Root.Position)
				if EspSettings.Tracers and Screen.Z > 0 then
					local From = Vector2.new(Viewport.X / 2, Viewport.Y)
					local To = Vector2.new(Screen.X, Screen.Y)
					local Delta = To - From
					Object.Tracer.BackgroundColor3 = Color
					Object.Tracer.Size = UDim2.fromOffset(Delta.Magnitude, 1.5)
					Object.Tracer.Position = UDim2.fromOffset((From.X + To.X) / 2, (From.Y + To.Y) / 2)
					Object.Tracer.Rotation = math.deg(math.atan2(Delta.Y, Delta.X))
					Object.Tracer.Visible = true
				else
					Object.Tracer.Visible = false
				end
			end
		end
	end

	table.sort(Candidates, function(Left, Right)
		return Left.Distance < Right.Distance
	end)
	for Index, Candidate in ipairs(Candidates) do
		Candidate.Object.Highlight.Enabled = EspSettings.Chams and Index <= Config.EspMaxHighlights
	end
end

function Esp.Stop()
	if Esp.Connection then
		Esp.Connection:Disconnect()
		Esp.Connection = nil
	end
	if Esp.RemovingConnection then
		Esp.RemovingConnection:Disconnect()
		Esp.RemovingConnection = nil
	end
	for Player in pairs(Esp.Objects) do
		Esp.Remove(Player)
	end
	if Esp.Folder then
		Esp.Folder:Destroy()
		Esp.Folder = nil
	end
end

function Esp.Start()
	Esp.Stop()
	if not Settings.Esp.Enabled then
		return
	end
	Esp.Folder = Instance.new("Folder")
	Esp.Folder.Name = "UniversalEsp"
	Esp.Folder.Parent = GetGuiParent()
	Esp.RemovingConnection = Players.PlayerRemoving:Connect(Esp.Remove)
	Esp.Connection = RunService.RenderStepped:Connect(function()
		pcall(Esp.Update)
	end)
end

OnCleanup(Esp.Stop)

local Aim = {
	Connection = nil, InputConnections = {}, Holding = false, Toggled = false, Target = nil, Circle = nil, Button = nil,
	Inputs = {
		["Right Mouse"] = { Type = Enum.UserInputType.MouseButton2 },
		["Left Mouse"] = { Type = Enum.UserInputType.MouseButton1 },
		["Left Shift"] = { Key = Enum.KeyCode.LeftShift },
		["Q"] = { Key = Enum.KeyCode.Q },
		["E"] = { Key = Enum.KeyCode.E },
		["F"] = { Key = Enum.KeyCode.F },
		["Z"] = { Key = Enum.KeyCode.Z },
		["X"] = { Key = Enum.KeyCode.X },
	},
}
App.Modules.Aim = Aim

function Aim.Matches(Input)
	local Wanted = Aim.Inputs[Settings.Aim.HoldInput]
	if not Wanted then
		return false
	end
	if Wanted.Type then
		return Input.UserInputType == Wanted.Type
	end
	return Input.KeyCode == Wanted.Key
end

function Aim.IsActive()
	local Mode = Settings.Aim.Mode
	if Mode == "Always" then
		return true
	elseif Mode == "Hold" then
		return Aim.Holding
	end
	return Aim.Toggled
end

function Aim.Press()
	if Settings.Aim.Mode == "Toggle" then
		Aim.Toggled = not Aim.Toggled
	else
		Aim.Holding = true
	end
end

function Aim.Release()
	Aim.Holding = false
end

function Aim.EnsureOverlay()
	if not App.Gui then
		return
	end
	if not Aim.Circle then
		Aim.Circle = Instance.new("Frame")
		Aim.Circle.Name = "AimFov"
		Aim.Circle.AnchorPoint = Vector2.new(0.5, 0.5)
		Aim.Circle.BackgroundTransparency = 1
		Aim.Circle.Visible = false
		Aim.Circle.Parent = App.Gui
		Instance.new("UICorner", Aim.Circle).CornerRadius = UDim.new(1, 0)
		Aim.CircleStroke = Instance.new("UIStroke")
		Aim.CircleStroke.Thickness = 1.5
		Aim.CircleStroke.Parent = Aim.Circle
	end
	if not Aim.Button then
		local Button = Instance.new("TextButton")
		Button.Name = "AimButton"
		Button.AnchorPoint = Vector2.new(1, 0.5)
		Button.Position = UDim2.new(1, -24, 0.5, -10)
		Button.Size = UDim2.fromOffset(72, 72)
		Button.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
		Button.BackgroundTransparency = 0.25
		Button.Text = "AIM"
		Button.Font = Enum.Font.BuilderSansBold
		Button.TextSize = 20
		Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		Button.Visible = false
		Button.Parent = App.Gui
		Instance.new("UICorner", Button).CornerRadius = UDim.new(1, 0)
		local Outline = Instance.new("UIStroke", Button)
		Outline.Color = Color3.fromRGB(255, 255, 255)
		Outline.Transparency = 0.5
		Button.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
				Aim.Press()
			end
		end)
		Button.InputEnded:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
				if Settings.Aim.Mode ~= "Toggle" then
					Aim.Release()
				end
			end
		end)
		Aim.Button = Button
	end
end

function Aim.GetOrigin()
	local Camera = GetCamera()
	local Size = Camera.ViewportSize
	if Settings.Aim.FovOrigin == "Mouse" and not App.IsTouch and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return UserInputService:GetMouseLocation()
	end
	return Size / 2
end

function Aim.GetPart(Character, Origin)
	local Choice = Settings.Aim.Part
	local Head = Character:FindFirstChild("Head")
	local Torso = Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("Torso") or GetRoot(Character)
	if Choice == "Head" then
		return Head or Torso
	elseif Choice == "Torso" then
		return Torso
	elseif Choice == "Root" then
		return GetRoot(Character)
	end

	local Camera = GetCamera()
	local Best, BestDistance
	for _, Part in ipairs(Character:GetChildren()) do
		if Part:IsA("BasePart") and Part.Name ~= "HumanoidRootPart" and Part.Transparency < 1 then
			local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)
			if OnScreen then
				local Distance = (Vector2.new(Screen.X, Screen.Y) - Origin).Magnitude
				if not BestDistance or Distance < BestDistance then
					Best, BestDistance = Part, Distance
				end
			end
		end
	end
	return Best or Torso
end

function Aim.IsVisible(Part, Character)
	local Camera = GetCamera()
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = { GetCharacter(), Character }
	Params.RespectCanCollide = true
	local From = Camera.CFrame.Position
	return Workspace:Raycast(From, Part.Position - From, Params) == nil
end

function Aim.Evaluate(Player, Origin)
	local AimSettings = Settings.Aim
	local Character = Player.Character
	if not Character or not IsLiving(Character) then
		return nil
	end
	if AimSettings.TeamCheck and not IsEnemy(Player) then
		return nil
	end
	local Camera = GetCamera()
	local Part = Aim.GetPart(Character, Origin)
	if not Part then
		return nil
	end
	local Distance = (Part.Position - Camera.CFrame.Position).Magnitude
	if Distance > AimSettings.MaxDistance then
		return nil
	end
	local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)
	if not OnScreen then
		return nil
	end
	local Offset = (Vector2.new(Screen.X, Screen.Y) - Origin).Magnitude
	if Offset > AimSettings.Fov then
		return nil
	end
	if AimSettings.WallCheck and not Aim.IsVisible(Part, Character) then
		return nil
	end
	local Humanoid = GetHumanoid(Character)
	local Score = Offset
	if AimSettings.Priority == "Distance" then
		Score = Distance
	elseif AimSettings.Priority == "Health" then
		Score = Humanoid.Health
	end
	return { Player = Player, Part = Part, Score = Score }
end

function Aim.FindTarget(Origin)
	local Best
	if Settings.Aim.Sticky and Aim.Target and Aim.Target.Parent then
		local Current = Aim.Evaluate(Aim.Target, Origin)
		if Current then
			return Current
		end
	end
	for _, Player in ipairs(OtherPlayers()) do
		local Candidate = Aim.Evaluate(Player, Origin)
		if Candidate and (not Best or Candidate.Score < Best.Score) then
			Best = Candidate
		end
	end
	return Best
end

function Aim.Step(Delta)
	local AimSettings = Settings.Aim
	local Camera = GetCamera()
	if not Camera then
		return
	end
	Aim.EnsureOverlay()
	local Origin = Aim.GetOrigin()
	if Aim.Circle then
		Aim.Circle.Visible = AimSettings.ShowFov
		Aim.Circle.Size = UDim2.fromOffset(AimSettings.Fov * 2, AimSettings.Fov * 2)
		Aim.Circle.Position = UDim2.fromOffset(Origin.X, Origin.Y)
		Aim.CircleStroke.Color = Aim.Target and Color3.fromRGB(255, 80, 80) or AimSettings.FovColor
	end
	if Aim.Button then
		Aim.Button.Visible = AimSettings.ShowButton and App.IsTouch
		Aim.Button.BackgroundColor3 = Aim.IsActive() and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(24, 24, 30)
	end
	if not Aim.IsActive() or not IsLiving(GetCharacter()) then
		Aim.Target = nil
		return
	end
	local Found = Aim.FindTarget(Origin)
	if not Found then
		Aim.Target = nil
		return
	end
	Aim.Target = Found.Player
	local Point = Found.Part.Position + Found.Part.AssemblyLinearVelocity * AimSettings.Prediction
	local Smoothing = math.max(AimSettings.Smoothing, 1)
	if AimSettings.Method == "Mouse" and Capabilities.MouseMove and not App.IsTouch then
		local Screen = Camera:WorldToViewportPoint(Point)
		local Current = UserInputService:GetMouseLocation()
		mousemoverel((Screen.X - Current.X) / Smoothing, (Screen.Y - Current.Y) / Smoothing)
	else
		local Alpha = Smoothing <= 1 and 1 or (1 - (1 - 1 / Smoothing) ^ (Delta * 60))
		Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, Point), math.clamp(Alpha, 0, 1))
	end
end

function Aim.Stop()
	pcall(RunService.UnbindFromRenderStep, RunService, "UniversalAim")
	DisconnectAll(Aim.InputConnections)
	Aim.Holding, Aim.Toggled, Aim.Target = false, false, nil
	if Aim.Circle then
		Aim.Circle.Visible = false
	end
	if Aim.Button then
		Aim.Button.Visible = false
	end
end

function Aim.Start()
	Aim.Stop()
	if not Settings.Aim.Enabled then
		return
	end
	table.insert(Aim.InputConnections, UserInputService.InputBegan:Connect(function(Input, Processed)
		if not Processed and Aim.Matches(Input) then
			Aim.Press()
		end
	end))
	table.insert(Aim.InputConnections, UserInputService.InputEnded:Connect(function(Input)
		if Aim.Matches(Input) and Settings.Aim.Mode ~= "Toggle" then
			Aim.Release()
		end
	end))
	RunService:BindToRenderStep("UniversalAim", Enum.RenderPriority.Camera.Value + 1, function(Delta)
		pcall(Aim.Step, Delta)
	end)
end

OnCleanup(Aim.Stop)

local Hitbox = { Connection = nil, Original = {}, NextScan = 0 }
App.Modules.Hitbox = Hitbox

function Hitbox.Restore(Player)
	local Saved = Hitbox.Original[Player]
	if not Saved then
		return
	end
	local Root = Saved.Root
	if Root and Root.Parent then
		Root.Size, Root.Transparency, Root.CanCollide = Saved.Size, Saved.Transparency, Saved.CanCollide
	end
	Hitbox.Original[Player] = nil
end

function Hitbox.Stop()
	if Hitbox.Connection then
		Hitbox.Connection:Disconnect()
		Hitbox.Connection = nil
	end
	for Player in pairs(Hitbox.Original) do
		Hitbox.Restore(Player)
	end
end

function Hitbox.Start()
	Hitbox.Stop()
	if not Settings.Hitbox.Enabled then
		return
	end
	Hitbox.Connection = RunService.Heartbeat:Connect(function()
		if os.clock() < Hitbox.NextScan then
			return
		end
		Hitbox.NextScan = os.clock() + 0.25
		local Size = Settings.Hitbox.Size
		for _, Player in ipairs(OtherPlayers()) do
			local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
			if Root and IsLiving(Player.Character) and (not Settings.Hitbox.TeamCheck or IsEnemy(Player)) then
				if not Hitbox.Original[Player] or Hitbox.Original[Player].Root ~= Root then
					Hitbox.Original[Player] = { Root = Root, Size = Root.Size, Transparency = Root.Transparency, CanCollide = Root.CanCollide }
				end
				Root.Size = Vector3.new(Size, Size, Size)
				Root.Transparency = Config.HitboxTransparency
				Root.CanCollide = false
			else
				Hitbox.Restore(Player)
			end
		end
	end)
end

OnCleanup(Hitbox.Stop)

local World = { Backup = nil, Connection = nil, XRay = {}, XRayConnection = nil, OriginalGravity = Workspace.Gravity, OriginalZoom = nil }
App.Modules.World = World

function World.Capture()
	if World.Backup then
		return
	end
	local Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	World.Backup = {
		Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows, FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd,
		Density = Atmosphere and Atmosphere.Density, Haze = Atmosphere and Atmosphere.Haze, ClockTime = Lighting.ClockTime,
	}
end

function World.RestoreLighting()
	local Backup = World.Backup
	if not Backup then
		return
	end
	Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient = Backup.Brightness, Backup.Ambient, Backup.OutdoorAmbient
	Lighting.GlobalShadows, Lighting.FogStart, Lighting.FogEnd = Backup.GlobalShadows, Backup.FogStart, Backup.FogEnd
	local Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if Atmosphere and Backup.Density then
		Atmosphere.Density, Atmosphere.Haze = Backup.Density, Backup.Haze
	end
	World.Backup = nil
end

function World.Wanted()
	local WorldSettings = Settings.World
	return WorldSettings.Fullbright or WorldSettings.NoFog or WorldSettings.NoShadows or WorldSettings.LockTime or WorldSettings.LockFov
end

function World.Step()
	local WorldSettings = Settings.World
	if WorldSettings.Fullbright then
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.fromRGB(180, 180, 180)
		Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
	end
	if WorldSettings.NoFog then
		Lighting.FogStart = 1e6
		Lighting.FogEnd = 1e6
		local Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if Atmosphere then
			Atmosphere.Density, Atmosphere.Haze = 0, 0
		end
	end
	if WorldSettings.NoShadows then
		Lighting.GlobalShadows = false
	end
	if WorldSettings.LockTime then
		Lighting.ClockTime = WorldSettings.TimeOfDay
	end
	if WorldSettings.LockFov then
		local Camera = GetCamera()
		if Camera then
			Camera.FieldOfView = WorldSettings.Fov
		end
	end
end

function World.Refresh()
	if World.Wanted() then
		World.Capture()
		if not World.Connection then
			World.Connection = RunService.RenderStepped:Connect(World.Step)
		end
	else
		if World.Connection then
			World.Connection:Disconnect()
			World.Connection = nil
		end
		World.RestoreLighting()
	end
end

function World.SetGravity(Value)
	Settings.World.Gravity = Value
	Workspace.Gravity = Value
end

function World.SetMaxZoom(Value)
	Settings.World.MaxZoom = Value
	if not World.OriginalZoom then
		World.OriginalZoom = LocalPlayer.CameraMaxZoomDistance
	end
	LocalPlayer.CameraMaxZoomDistance = Value
	LocalPlayer.CameraMinZoomDistance = 0.5
end

function World.XRayApply(Part)
	if Part:IsA("BasePart") and not Part:IsDescendantOf(LocalPlayer.Character or Workspace) and World.XRay[Part] == nil then
		local Character = Part:FindFirstAncestorOfClass("Model")
		if Character and Character:FindFirstChildOfClass("Humanoid") then
			return
		end
		World.XRay[Part] = Part.Transparency
		Part.Transparency = math.max(Part.Transparency, 0.6)
	end
end

function World.SetXRay(Value)
	Settings.World.XRay = Value
	if World.XRayConnection then
		World.XRayConnection:Disconnect()
		World.XRayConnection = nil
	end
	if Value then
		task.spawn(function()
			local Count = 0
			for _, Part in ipairs(Workspace:GetDescendants()) do
				if not Settings.World.XRay or not IsRunning() then
					return
				end
				World.XRayApply(Part)
				Count = Count + 1
				if Count % 400 == 0 then
					task.wait()
				end
			end
		end)
		World.XRayConnection = Workspace.DescendantAdded:Connect(World.XRayApply)
	else
		for Part, Transparency in pairs(World.XRay) do
			if Part.Parent then
				Part.Transparency = Transparency
			end
		end
		table.clear(World.XRay)
	end
end

function World.BoostFps()
	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	Lighting.GlobalShadows = false
	for _, Effect in ipairs(Lighting:GetChildren()) do
		if Effect:IsA("PostEffect") or Effect:IsA("Atmosphere") then
			pcall(function()
				Effect.Enabled = false
			end)
		end
	end
	task.spawn(function()
		local Count = 0
		for _, Item in ipairs(Workspace:GetDescendants()) do
			if not IsRunning() then
				return
			end
			if Item:IsA("ParticleEmitter") or Item:IsA("Trail") or Item:IsA("Smoke") or Item:IsA("Fire") or Item:IsA("Sparkles") then
				Item.Enabled = false
			elseif Item:IsA("Decal") or Item:IsA("Texture") then
				Item.Transparency = 1
			elseif Item:IsA("BasePart") then
				Item.Material = Enum.Material.Plastic
				Item.Reflectance = 0
				Item.CastShadow = false
			end
			Count = Count + 1
			if Count % 500 == 0 then
				task.wait()
			end
		end
		Notify("World", "FPS boost applied", "normal")
	end)
end

function World.SetFpsCap(Value)
	if Capabilities.FpsCap then
		setfpscap(Value)
	end
end

function World.ApplySavedFlags()
	Workspace.Gravity = Settings.World.Gravity
	World.Refresh()
end

OnCleanup(function()
	if World.Connection then
		World.Connection:Disconnect()
		World.Connection = nil
	end
	World.RestoreLighting()
	World.SetXRay(false)
	Workspace.Gravity = World.OriginalGravity
	if World.OriginalZoom then
		LocalPlayer.CameraMaxZoomDistance = World.OriginalZoom
	end
end)

local Server = { Visited = {}, Busy = false, AfkConnection = nil, RejoinConnections = {}, Frames = 0, Fps = 60 }
App.Modules.Server = Server
Server.Visited[game.JobId] = true

function Server.Rejoin()
	if #Players:GetPlayers() <= 1 then
		LocalPlayer:Kick("\nRejoining...")
		task.wait(0.5)
		TeleportService:Teleport(game.PlaceId, LocalPlayer)
	else
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
	end
end

function Server.JoinJob(JobId, PlaceId)
	JobId = tostring(JobId or "")
	if JobId == "" then
		Notify("Server", "Enter a JobId first", "warning")
		return
	end
	TeleportService:TeleportToPlaceInstance(tonumber(PlaceId) or game.PlaceId, JobId, LocalPlayer)
end

function Server.TeleportPlace(PlaceId)
	local Id = tonumber(PlaceId)
	if not Id then
		Notify("Server", "That is not a place id", "warning")
		return
	end
	TeleportService:Teleport(Id, LocalPlayer)
end

function Server.Collect(Mode)
	local Order = Mode == "Largest" and "Desc" or "Asc"
	local Found = {}
	local Cursor = ""
	for _ = 1, Config.ServerMaxPages do
		local Url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&excludeFullGames=true&limit=%d", game.PlaceId, Order, Config.ServerPageLimit)
		if Cursor ~= "" then
			Url = Url .. "&cursor=" .. HttpService:UrlEncode(Cursor)
		end
		local Body
		for Attempt = 1, Config.ServerFetchRetries do
			Body = HttpGetText(Url)
			if Body then
				break
			end
			task.wait(Config.ServerRetryDelay * Attempt)
		end
		if not Body then
			break
		end
		local Ok, Data = pcall(HttpService.JSONDecode, HttpService, Body)
		if not Ok or type(Data) ~= "table" or type(Data.data) ~= "table" then
			break
		end
		for _, Entry in ipairs(Data.data) do
			if type(Entry.id) == "string" and not Server.Visited[Entry.id] and (Entry.playing or 0) < (Entry.maxPlayers or 0) then
				table.insert(Found, Entry)
			end
		end

		if (Mode == "Smallest" or Mode == "Largest") and #Found > 0 then
			break
		end
		Cursor = Data.nextPageCursor
		if type(Cursor) ~= "string" or Cursor == "" then
			break
		end
	end
	return Found
end

function Server.Hop(Mode)
	if Server.Busy then
		Notify("Server Hop", "Already searching for a server", "warning")
		return
	end
	Server.Busy = true
	Notify("Server Hop", "Searching servers...", "normal")
	task.spawn(function()
		local Ok, Failure = pcall(function()
			local Found = Server.Collect(Mode)
			if #Found == 0 then
				Notify("Server Hop", "No other server found, trying a plain rejoin", "warning")
				TeleportService:Teleport(game.PlaceId, LocalPlayer)
				return
			end
			local Pick
			if Mode == "Random" then
				Pick = Found[math.random(1, #Found)]
			elseif Mode == "Best Ping" then
				table.sort(Found, function(Left, Right)
					return (Left.ping or 9999) < (Right.ping or 9999)
				end)
				Pick = Found[1]
			else
				Pick = Found[1]
			end
			Server.Visited[Pick.id] = true
			Notify("Server Hop", string.format("Joining %d/%d players", Pick.playing or 0, Pick.maxPlayers or 0), "normal")
			TeleportService:TeleportToPlaceInstance(game.PlaceId, Pick.id, LocalPlayer)
		end)
		if not Ok then
			Notify("Server Hop", tostring(Failure), "error")
		end
		Server.Busy = false
	end)
end

function Server.StopAfk()
	if Server.AfkConnection then
		Server.AfkConnection:Disconnect()
		Server.AfkConnection = nil
	end
end

function Server.StartAfk()
	Server.StopAfk()
	if not Settings.AntiAfk.Enabled then
		return
	end
	local VirtualUser = game:GetService("VirtualUser")
	Server.AfkConnection = LocalPlayer.Idled:Connect(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
end

function Server.StopAutoRejoin()
	DisconnectAll(Server.RejoinConnections)
end

function Server.StartAutoRejoin()
	Server.StopAutoRejoin()
	if not Settings.AutoRejoin.Enabled then
		return
	end
	local function OnError(Message)
		if Settings.AutoRejoin.Enabled and type(Message) == "string" and Message ~= "" then
			Notify("Auto Rejoin", "Disconnected, rejoining...", "warning")
			task.delay(2, function()
				pcall(Server.Rejoin)
			end)
		end
	end
	table.insert(Server.RejoinConnections, GuiService.ErrorMessageChanged:Connect(OnError))
	local Ok, Overlay = pcall(function()
		return CoreGui:WaitForChild("RobloxPromptGui", 2):WaitForChild("promptOverlay", 2)
	end)
	if Ok and Overlay then
		table.insert(Server.RejoinConnections, Overlay.ChildAdded:Connect(function(Child)
			if Child.Name == "ErrorPrompt" then
				OnError("prompt")
			end
		end))
	end
end

Track(RunService.RenderStepped:Connect(function()
	Server.Frames = Server.Frames + 1
end))
task.spawn(function()
	local Last = os.clock()
	while IsRunning() do
		task.wait(1)
		local Now = os.clock()
		Server.Fps = math.floor(Server.Frames / math.max(Now - Last, 0.001) + 0.5)
		Server.Frames, Last = 0, Now
	end
end)

function Server.GetPing()
	local Ok, Value = pcall(function()
		return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return Ok and math.floor(Value + 0.5) or 0
end

function Server.GetGameName()
	local Ok, Info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
	if Ok and type(Info) == "table" then
		return Info.Name
	end
	return game.Name
end

OnCleanup(function()
	Server.StopAfk()
	Server.StopAutoRejoin()
end)

local Misc = {}
App.Modules.Misc = Misc

function Misc.Reset()
	local Humanoid = GetHumanoid()
	if Humanoid then
		Humanoid.Health = 0
	end
end

function Misc.RespawnHere()
	local Root = GetRoot()
	if not Root then
		return
	end
	local Frame = Root.CFrame
	Misc.Reset()
	local Character = LocalPlayer.CharacterAdded:Wait()
	local NewRoot = Character:WaitForChild("HumanoidRootPart", Config.WaitForCharacter)
	if NewRoot then
		task.wait(0.4)
		NewRoot.CFrame = Frame
	end
end

function Misc.Sit()
	local Humanoid = GetHumanoid()
	if Humanoid then
		Humanoid.Sit = true
	end
end

function Misc.CopyPosition()
	local Root = GetRoot()
	if Root then
		local Position = Root.Position
		CopyText(string.format("%.2f, %.2f, %.2f", Position.X, Position.Y, Position.Z), "Position")
	end
end

function Misc.CopyCFrame()
	local Root = GetRoot()
	if Root then
		CopyText("CFrame.new(" .. table.concat({ Root.CFrame:GetComponents() }, ", ") .. ")", "CFrame")
	end
end

local Cosmetics = {
	FaceId = 494291269,
	AccessoryItems = {
		{ Id = 1365767, Name = "Valkyrie Helm", Category = "Head" },
		{ Id = 1125510, Name = "The Void Star", Category = "Head" },
		{ Id = 1285307, Name = "Sparkle Time Fedora", Category = "Head" },
		{ Id = 1323384, Name = "The Ice Crown", Category = "Head" },
		{ Id = 193696233, Name = "Green Ice Crown", Category = "Head" },
		{ Id = 13241836994, Name = "Verdant Crown", Category = "Head" },
		{ Id = 119916949, Name = "Midnight Blue STF", Category = "Head" },
		{ Id = 215751161, Name = "Orange STF", Category = "Head" },
		{ Id = 332772333, Name = "Korblox Ice Crown", Category = "Head" },
		{ Id = 102887469225690, Name = "Blue Inferno Skull", Category = "Head" },
		{ Id = 17756304457, Name = "Flaming Pink Horned", Category = "Head" },
		{ Id = 1272714, Name = "Wanwood Antlers", Category = "Head" },
		{ Id = 215718515, Name = "Fiery Horns", Category = "Head" },
		{ Id = 74891470, Name = "Frozen Horns", Category = "Head" },
		{ Id = 19027209, Name = "Legit Business Hat", Category = "Head" },
		{ Id = 10159600649, Name = "8-Bit Royal Crown", Category = "Head" },
		{ Id = 10159610478, Name = "8-Bit HP Bar", Category = "Head" },
		{ Id = 63690008, Name = "Pal Hair", Category = "Head" },
		{ Id = 451221329, Name = "True Blue Hair", Category = "Head" },
		{ Id = 1028859, Name = "Pirate Captain's Hat", Category = "Head" },
		{ Id = 1029025, Name = "Classic ROBLOX Fedora", Category = "Head" },
		{ Id = 1567446, Name = "Verified Sign", Category = "Head" },
		{ Id = 104768408817732, Name = "The Biggest Head", Category = "Head" },
		{ Id = 111865906859195, Name = "LOOL Head", Category = "Head" },
		{ Id = 11748356, Name = "Clockwork's Shades", Category = "Face" },
		{ Id = 141742418, Name = "Winter Fairy", Category = "Other" },
		{ Id = 10159622004, Name = "8-Bit Roblox Coin", Category = "Other" },
		{ Id = 10159606132, Name = "8-Bit Extra Life", Category = "Other" },
		{ Id = 10159617728, Name = "8-Bit Tabby Cat", Category = "Other" },
	},
	AnimationPacks = {
		Toy = { Idle = 782841498, Idle2 = 782845736, Walk = 782843345, Run = 782842708, Jump = 782847020, Fall = 782846423, Climb = 782843869, Swim = 782844582, SwimIdle = 782845186 },
		Zombie = { Idle = 616158929, Idle2 = 616160636, Walk = 616168032, Run = 616163682, Jump = 616161997, Fall = 616157476, Climb = 616156119, Swim = 616165109, SwimIdle = 616166655 },
		Ninja = { Idle = 656117400, Idle2 = 656118341, Walk = 656121766, Run = 656118852, Jump = 656117878, Fall = 656115606, Climb = 656114359, Swim = 656119721, SwimIdle = 656121397 },
		Robot = { Idle = 616088211, Idle2 = 616089559, Walk = 616095330, Run = 616091570, Jump = 616090535, Fall = 616087089, Climb = 616086039, Swim = 616092998, SwimIdle = 616094091 },
		Astronaut = { Idle = 891621366, Idle2 = 891633237, Walk = 891636393, Run = 891636393, Jump = 891627522, Fall = 891617961, Climb = 891609353, Swim = 891639666, SwimIdle = 891663592 },
		Superhero = { Idle = 616111295, Idle2 = 616113536, Walk = 616122287, Run = 616117076, Jump = 616115533, Fall = 616108001, Climb = 616104706, Swim = 616119360, SwimIdle = 616120861 },
		Bubbly = { Idle = 910004836, Idle2 = 910009958, Walk = 910034870, Run = 910025107, Jump = 910016857, Fall = 910001910, Climb = 909997997, Swim = 910028158, SwimIdle = 910030921 },
		Cartoony = { Idle = 742637544, Idle2 = 742638445, Walk = 742640026, Run = 742638842, Jump = 742637942, Fall = 742637151, Climb = 742636889, Swim = 742639220, SwimIdle = 742639812 },
		Pirate = { Idle = 750781874, Idle2 = 750782770, Walk = 750785693, Run = 750783738, Jump = 750782230, Fall = 750780242, Climb = 750779899, Swim = 750784579, SwimIdle = 750785176 },
		Knight = { Idle = 657595757, Idle2 = 657568135, Walk = 657552124, Run = 657564596, Jump = 658409194, Fall = 657600338, Climb = 658360781, Swim = 657560551, SwimIdle = 657557095 },
		Mage = { Idle = 707742142, Idle2 = 707855907, Walk = 707897309, Run = 707861613, Jump = 707853694, Fall = 707829716, Climb = 707826056, Swim = 707876443, SwimIdle = 707894699 },
	},
	AnimationSlots = {
		{ "idle", "Animation1", "Idle" }, { "idle", "Animation2", "Idle2" }, { "walk", "WalkAnim", "Walk" },
		{ "run", "RunAnim", "Run" }, { "jump", "JumpAnim", "Jump" }, { "fall", "FallAnim", "Fall" },
		{ "climb", "ClimbAnim", "Climb" }, { "swim", "SwimAnim", "Swim" }, { "swimidle", "SwimIdleAnim", "SwimIdle" },
	},
	Emotes = {
		{ Name = "Wave", Id = 128777973 }, { Name = "Hello", Id = 3576686446 }, { Name = "Point", Id = 128853357 },
		{ Name = "Cheer", Id = 129423030 }, { Name = "Laugh", Id = 129423131 }, { Name = "Shrug", Id = 3576968026 },
		{ Name = "Salute", Id = 3360689775 },
	},
	Dances = {
		{ Name = "Dance", Id = 507771019 }, { Name = "Dance 2", Id = 507776043 }, { Name = "Dance 3", Id = 507777268 },
	},
	Materials = {
		Neon = { Material = Enum.Material.Neon },
		Glass = { Material = Enum.Material.Glass },
		Gold = { Material = Enum.Material.Metal, Color = Color3.fromRGB(255, 180, 40) },
		Ice = { Material = Enum.Material.Ice },
		ForceField = { Material = Enum.Material.ForceField },
		Diamond = { Material = Enum.Material.DiamondPlate },
	},
	BodyColors = { "White", "Light stone grey", "Black", "Really red", "Bright orange", "Bright yellow", "Bright green", "Teal", "Bright blue", "Bright violet", "Magenta", "Reddish brown" },
	WearableAssetTypes = { [8] = true, [41] = true, [42] = true, [43] = true, [44] = true, [45] = true, [46] = true, [47] = true },
	State = {
		Korblox = false, Headless = false, Face = false, Accessories = {}, ClearFace = false, ClearClothes = false, ClearAccessories = false,
		Effects = { Trail = false, Fire = false, Lightning = false, Sparkles = false, Smoke = false },
		MaterialMode = nil, Scales = { Height = 1, Width = 1, Head = 1, Proportion = 0, BodyType = 0 }, ScalesTouched = false,
		BodyColorName = nil, AnimationPack = "Default",
	},
	Restore = {}, Adjust = {}, AdjustBase = {}, FaceBackup = setmetatable({}, { __mode = "k" }), ClearStash = setmetatable({}, { __mode = "k" }),
	AnimateStash = setmetatable({}, { __mode = "k" }), OriginalAnimationIds = nil, OriginalAnimationCharacter = nil, CustomTrack = nil,
	SearchResults = {}, Busy = false,
}
App.Modules.Cosmetics = Cosmetics

for _, Item in ipairs(Cosmetics.AccessoryItems) do
	Cosmetics.State.Accessories[Item.Id] = false
end

function Cosmetics.GetRootPart(Character)
	return Character and (Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("Torso"))
end

function Cosmetics.LockTransparency(Part)
	local Handle = { Part = Part, Original = Part.Transparency, OriginalModifier = Part.LocalTransparencyModifier }
	pcall(function()
		Handle.Connection = Part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			if Part.LocalTransparencyModifier ~= 1 then
				Part.LocalTransparencyModifier = 1
			end
		end)
	end)
	Part.Transparency = 1
	Part.LocalTransparencyModifier = 1
	return Handle
end

function Cosmetics.UnlockTransparency(Handle)
	if not Handle or not Handle.Part or not Handle.Part.Parent then
		return
	end
	if Handle.Connection then
		pcall(Handle.Connection.Disconnect, Handle.Connection)
	end
	Handle.Part.Transparency = Handle.Original
	Handle.Part.LocalTransparencyModifier = Handle.OriginalModifier
end

function Cosmetics.ApplyKorblox(Character)
	local Humanoid = GetHumanoid(Character)
	local IsR15 = Humanoid and Humanoid.RigType == Enum.HumanoidRigType.R15
	local Data = { Rig = IsR15 and "R15" or "R6", Locks = {}, Wraps = {}, Extras = {} }
	if IsR15 then
		local Upper = Character:WaitForChild("RightUpperLeg", 8)
		local Lower = Character:WaitForChild("RightLowerLeg", 8)
		local Foot = Character:WaitForChild("RightFoot", 8)
		if not (Upper and Lower and Foot) then
			return nil
		end
		for _, Part in ipairs({ Upper, Lower, Foot }) do
			table.insert(Data.Locks, Cosmetics.LockTransparency(Part))
			for _, Child in ipairs(Part:GetChildren()) do
				if Child:IsA("SurfaceAppearance") or Child:IsA("WrapTarget") then
					Child:Destroy()
				elseif Child:IsA("WrapLayer") then
					table.insert(Data.Wraps, Child)
					Child.Enabled = false
				end
			end
		end
		local Old = Upper:FindFirstChild("KorbloxVisualPart")
		if Old then
			Old:Destroy()
		end
		local Visual = Instance.new("Part")
		Visual.Name = "KorbloxVisualPart"
		Visual.CanCollide, Visual.CanTouch, Visual.CanQuery, Visual.Massless = false, false, false, true
		Visual.Size = Vector3.new(1, 1, 1)
		Visual.CFrame = Upper.CFrame
		local Mesh = Instance.new("SpecialMesh")
		Mesh.MeshType = Enum.MeshType.FileMesh
		Mesh.MeshId = "rbxassetid://902942096"
		Mesh.TextureId = "rbxassetid://902843398"
		Mesh.Parent = Visual
		local Weld = Instance.new("Weld")
		Weld.Part0, Weld.Part1 = Upper, Visual
		Weld.Parent = Visual
		Visual.Parent = Upper
		table.insert(Data.Extras, Visual)
	else
		local Leg = Character:WaitForChild("Right Leg", 8)
		if not Leg then
			return nil
		end
		for _, Child in ipairs(Character:GetChildren()) do
			if Child:IsA("CharacterMesh") and Child.BodyPart == Enum.BodyPart.RightLeg then
				Child:Destroy()
			end
		end
		for _, Child in ipairs(Leg:GetChildren()) do
			if Child:IsA("SpecialMesh") or Child:IsA("CharacterMesh") or Child:IsA("SurfaceAppearance") or Child:IsA("WrapTarget") then
				Child:Destroy()
			end
		end
		pcall(function()
			local Mesh = Instance.new("CharacterMesh")
			Mesh.MeshId = 101851696
			Mesh.BodyPart = Enum.BodyPart.RightLeg
			Mesh.Parent = Character
			table.insert(Data.Extras, Mesh)
		end)
		pcall(function()
			local Mesh = Instance.new("SpecialMesh")
			Mesh.MeshType = Enum.MeshType.FileMesh
			Mesh.MeshId = "http://www.roblox.com/asset/?id=101851696"
			Mesh.TextureId = "http://www.roblox.com/asset/?id=101851254"
			Mesh.Parent = Leg
			table.insert(Data.Extras, Mesh)
		end)
	end
	return Data
end

function Cosmetics.RemoveKorblox(Character, Data)
	if not Data then
		return
	end
	for _, Extra in ipairs(Data.Extras) do
		if Extra and Extra.Parent then
			Extra:Destroy()
		end
	end
	for _, Handle in ipairs(Data.Locks) do
		Cosmetics.UnlockTransparency(Handle)
	end
	for _, Wrap in ipairs(Data.Wraps) do
		if Wrap and Wrap.Parent then
			Wrap.Enabled = true
		end
	end
	if Data.Rig == "R6" and Character and Character.Parent then
		pcall(function()
			local Mesh = Instance.new("CharacterMesh")
			Mesh.BodyPart = Enum.BodyPart.RightLeg
			Mesh.Parent = Character
		end)
	end
end

function Cosmetics.ApplyHeadless(Character)
	local Head = Character:WaitForChild("Head", 8)
	if not Head then
		return nil
	end
	local Data = { Locks = { Cosmetics.LockTransparency(Head) }, Decals = {}, Meshes = {}, Wraps = {} }
	for _, Child in ipairs(Head:GetChildren()) do
		if Child:IsA("Decal") then
			table.insert(Data.Decals, { Object = Child, Original = Child.Transparency })
			Child.Transparency = 1
		elseif Child:IsA("SpecialMesh") then
			table.insert(Data.Meshes, { Object = Child, Original = Child.Scale })
			Child.Scale = Vector3.zero
		elseif Child:IsA("SurfaceAppearance") or Child:IsA("WrapTarget") then
			Child:Destroy()
		elseif Child:IsA("WrapLayer") then
			table.insert(Data.Wraps, Child)
			Child.Enabled = false
		end
	end
	return Data
end

function Cosmetics.RemoveHeadless(Data)
	if not Data then
		return
	end
	for _, Handle in ipairs(Data.Locks) do
		Cosmetics.UnlockTransparency(Handle)
	end
	for _, Entry in ipairs(Data.Decals) do
		if Entry.Object.Parent then
			Entry.Object.Transparency = Entry.Original
		end
	end
	for _, Entry in ipairs(Data.Meshes) do
		if Entry.Object.Parent then
			Entry.Object.Scale = Entry.Original
		end
	end
	for _, Wrap in ipairs(Data.Wraps) do
		if Wrap.Parent then
			Wrap.Enabled = true
		end
	end
end

local FaceTag = "CustomFace_SSHF"

function Cosmetics.AttachFace(Character)
	local Head = Character:WaitForChild("Head", 8)
	if not Head then
		return
	end
	local Old = Head:FindFirstChild(FaceTag)
	if Old then
		Old:Destroy()
	end
	local Ok, Asset = pcall(function()
		return game:GetObjects("rbxassetid://" .. tostring(Cosmetics.FaceId))[1]
	end)
	if not Ok or not Asset then
		return
	end
	for _, Child in ipairs(Head:GetChildren()) do
		if Child:IsA("Decal") then
			Child.Transparency = 1
		end
	end
	if Asset:IsA("Decal") then
		Asset.Name = FaceTag
		Asset.Face = Enum.NormalId.Front
		Asset.Transparency = 0
		Asset.Parent = Head
	else
		Asset.Name = FaceTag
		Asset.Parent = Character
		local Humanoid = GetHumanoid(Character)
		if Humanoid then
			pcall(Humanoid.AddAccessory, Humanoid, Asset)
		end
	end
end

function Cosmetics.DetachFace(Character)
	local Head = Character:FindFirstChild("Head")
	if Head then
		local Object = Head:FindFirstChild(FaceTag)
		if Object then
			Object:Destroy()
		end
		for _, Child in ipairs(Head:GetChildren()) do
			if Child:IsA("Decal") then
				Child.Transparency = Cosmetics.State.Headless and 1 or 0
			end
		end
	end
	local Tagged = Character:FindFirstChild(FaceTag)
	if Tagged then
		Tagged:Destroy()
	end
end

function Cosmetics.GetStash(Character)
	local Stash = Cosmetics.ClearStash[Character]
	if not Stash then
		Stash = { Clothes = {}, Accessories = {} }
		Cosmetics.ClearStash[Character] = Stash
	end
	return Stash
end

function Cosmetics.ApplyClearFace(Character, On)
	local Head = Character and Character:FindFirstChild("Head")
	if not Head then
		return
	end
	local Backup = Cosmetics.FaceBackup[Character]
	if not Backup then
		Backup = { Decals = {}, Wraps = {}, Meshes = {} }
		Cosmetics.FaceBackup[Character] = Backup
	end
	if On then
		for _, Child in ipairs(Head:GetChildren()) do
			if Child:IsA("Decal") then
				if Backup.Decals[Child] == nil then
					Backup.Decals[Child] = Child.Transparency
				end
				Child.Transparency = 1
			elseif Child:IsA("WrapLayer") then
				if Backup.Wraps[Child] == nil then
					Backup.Wraps[Child] = Child.Enabled
				end
				Child.Enabled = false
			elseif Child:IsA("SpecialMesh") then
				if Backup.Meshes[Child] == nil then
					Backup.Meshes[Child] = Child.TextureId
				end
				Child.TextureId = ""
			end
		end
		local Controls = Head:FindFirstChildOfClass("FaceControls")
		if Controls and not Backup.FaceControls then
			Backup.FaceControls = Controls
			Controls.Parent = nil
		end
		local FaceAccessory = Character:FindFirstChild("Face")
		if FaceAccessory and FaceAccessory:IsA("Accessory") and not Backup.FaceAccessory then
			Backup.FaceAccessory = FaceAccessory
			FaceAccessory.Parent = nil
		end
	else
		for Child, Original in pairs(Backup.Decals) do
			if Child.Parent then
				Child.Transparency = Original
			end
		end
		for Child, Original in pairs(Backup.Wraps) do
			if Child.Parent then
				Child.Enabled = Original
			end
		end
		for Child, Original in pairs(Backup.Meshes) do
			if Child.Parent then
				Child.TextureId = Original
			end
		end
		Backup.Decals, Backup.Wraps, Backup.Meshes = {}, {}, {}
		if Backup.FaceControls and not Head:FindFirstChildOfClass("FaceControls") then
			Backup.FaceControls.Parent = Head
		end
		Backup.FaceControls = nil
		if Backup.FaceAccessory and not Character:FindFirstChild("Face") then
			local Humanoid = GetHumanoid(Character)
			if Humanoid then
				pcall(Humanoid.AddAccessory, Humanoid, Backup.FaceAccessory)
			else
				Backup.FaceAccessory.Parent = Character
			end
		end
		Backup.FaceAccessory = nil
	end
end

function Cosmetics.ApplyClearClothes(Character, On)
	if not Character then
		return
	end
	local Stash = Cosmetics.GetStash(Character)
	if On then
		for _, ClassName in ipairs({ "Shirt", "Pants", "ShirtGraphic" }) do
			local Item = Character:FindFirstChildOfClass(ClassName)
			if Item then
				Item.Parent = nil
				table.insert(Stash.Clothes, Item)
			end
		end
	else
		local List = Stash.Clothes
		Stash.Clothes = {}
		for _, Item in ipairs(List) do
			Item.Parent = Character
		end
	end
end

function Cosmetics.ApplyClearAccessories(Character, On)
	if not Character then
		return
	end
	local Stash = Cosmetics.GetStash(Character)
	if On then
		for _, Item in ipairs(Character:GetChildren()) do
			if Item:IsA("Accessory") and not Item.Name:find("CustomAcc_") then
				Item.Parent = nil
				table.insert(Stash.Accessories, Item)
			end
		end
	else
		local List = Stash.Accessories
		Stash.Accessories = {}
		local Humanoid = GetHumanoid(Character)
		for _, Item in ipairs(List) do
			if Humanoid then
				pcall(Humanoid.AddAccessory, Humanoid, Item)
			else
				Item.Parent = Character
			end
		end
	end
end

function Cosmetics.ApplyAllClears(Character)
	local State = Cosmetics.State
	if State.ClearFace then
		Cosmetics.ApplyClearFace(Character, true)
	end
	if State.ClearClothes then
		Cosmetics.ApplyClearClothes(Character, true)
	end
	if State.ClearAccessories then
		Cosmetics.ApplyClearAccessories(Character, true)
	end
end

function Cosmetics.RemoveEffect(Character, Name)
	if not Character then
		return
	end
	local function Sweep(Parent)
		if not Parent then
			return
		end
		for _, Object in ipairs(Parent:GetChildren()) do
			if Object.Name:sub(1, #Name) == Name then
				pcall(Object.Destroy, Object)
			end
		end
	end
	Sweep(Cosmetics.GetRootPart(Character))
	Sweep(Character)
end

function Cosmetics.ApplyTrail(Character, On)
	local Root = Cosmetics.GetRootPart(Character)
	if not Root then
		return
	end
	Cosmetics.RemoveEffect(Character, "UniRainbowTrail")
	if not On then
		return
	end
	local First = Instance.new("Attachment")
	First.Name = "UniRainbowTrail_a0"
	First.Position = Vector3.new(0, 1, 0)
	First.Parent = Root
	local Second = Instance.new("Attachment")
	Second.Name = "UniRainbowTrail_a1"
	Second.Position = Vector3.new(0, -1, 0)
	Second.Parent = Root
	local Trail = Instance.new("Trail")
	Trail.Name = "UniRainbowTrail"
	Trail.Attachment0, Trail.Attachment1 = First, Second
	Trail.Lifetime, Trail.LightEmission, Trail.LightInfluence = 1, 1, 0
	Trail.WidthScale = NumberSequence.new(1, 0.3)
	pcall(function()
		Trail.FaceCamera = true
	end)
	local Keypoints = {}
	for Index = 0, 6 do
		table.insert(Keypoints, ColorSequenceKeypoint.new(Index / 6, Color3.fromHSV((Index % 6) / 6, 0.9, 1)))
	end
	Trail.Color = ColorSequence.new(Keypoints)
	Trail.Parent = Root
	local Glow = Instance.new("ParticleEmitter")
	Glow.Name = "UniRainbowTrail_glow"
	Glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	Glow.Rate = 24
	Glow.Lifetime = NumberRange.new(0.6, 1.2)
	Glow.Size = NumberSequence.new(0.3, 0.05)
	Glow.Speed = NumberRange.new(1.5, 3)
	Glow.SpreadAngle = Vector2.new(180, 180)
	Glow.LightEmission, Glow.LightInfluence = 1, 0
	Glow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.9, 1)), ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 0.9, 1)),
		ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.66, 0.9, 1)), ColorSequenceKeypoint.new(1, Color3.fromHSV(0.95, 0.9, 1)),
	})
	Glow.Parent = Root
end

function Cosmetics.MakeEmitter(Name, Properties)
	local Emitter = Instance.new("ParticleEmitter")
	Emitter.Name = Name
	for Key, Value in pairs(Properties) do
		pcall(function()
			Emitter[Key] = Value
		end)
	end
	return Emitter
end

function Cosmetics.ApplyAura(Character, Kind, On)
	local Root = Cosmetics.GetRootPart(Character)
	if not Root then
		return
	end
	local Tag = "UniFX_" .. Kind
	Cosmetics.RemoveEffect(Character, Tag)
	if not On then
		return
	end
	if Kind == "Sparkles" then
		local Sparkles = Instance.new("Sparkles")
		Sparkles.Name = Tag
		Sparkles.SparkleColor = Color3.fromRGB(255, 210, 80)
		Sparkles.Parent = Root
		return
	end
	local function AddLight(Color, Brightness, Range)
		local Light = Instance.new("PointLight")
		Light.Name = Tag .. "_light"
		Light.Color, Light.Brightness, Light.Range = Color, Brightness, Range
		Light.Parent = Root
	end
	local Emitter
	if Kind == "Fire" then
		Emitter = Cosmetics.MakeEmitter(Tag, {
			Texture = "rbxasset://textures/particles/fire_main.dds", Rate = 70, Lifetime = NumberRange.new(0.7, 1.2),
			Size = NumberSequence.new(0.8, 2), Speed = NumberRange.new(4, 8), EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 60, 20)),
			LightEmission = 1, LightInfluence = 0, Transparency = NumberSequence.new(0.15, 1),
		})
		AddLight(Color3.fromRGB(255, 140, 40), 1.6, 12)
	elseif Kind == "Smoke" then
		Emitter = Cosmetics.MakeEmitter(Tag, {
			Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 40, Lifetime = NumberRange.new(1.2, 2),
			Size = NumberSequence.new(1, 2.6), Speed = NumberRange.new(3, 5), EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(Color3.fromRGB(140, 140, 148)), Transparency = NumberSequence.new(0.25, 1),
		})
	elseif Kind == "Lightning" then
		Emitter = Cosmetics.MakeEmitter(Tag, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 110, Lifetime = NumberRange.new(0.25, 0.55),
			Size = NumberSequence.new(0.35, 0.05), Speed = NumberRange.new(7, 12), SpreadAngle = Vector2.new(180, 180),
			Color = ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(255, 255, 255)), LightEmission = 1, LightInfluence = 0,
		})
		AddLight(Color3.fromRGB(140, 230, 255), 1.4, 10)
	end
	if Emitter then
		Emitter.Parent = Root
		pcall(Emitter.Emit, Emitter, 25)
	end
end

function Cosmetics.GetBodyParts(Character)
	local Parts = {}
	for _, Part in ipairs(Character:GetChildren()) do
		if Part:IsA("BasePart") and Part.Name ~= "KorbloxVisualPart" and not Part.Name:find("CustomAcc_") then
			table.insert(Parts, Part)
		end
	end
	return Parts
end

function Cosmetics.ApplyMaterial(Character, Mode)
	if not Character then
		return
	end
	local Spec = Mode and Cosmetics.Materials[Mode] or nil
	for _, Part in ipairs(Cosmetics.GetBodyParts(Character)) do
		pcall(function()
			if Spec then
				if not Part:GetAttribute("UniOriginalMaterial") then
					Part:SetAttribute("UniOriginalMaterial", Part.Material.Name)
					Part:SetAttribute("UniOriginalColor", Part.Color)
				end
				Part.Material = Spec.Material
				if Spec.Color then
					Part.Color = Spec.Color
				end
			else
				local Name = Part:GetAttribute("UniOriginalMaterial")
				local Color = Part:GetAttribute("UniOriginalColor")
				if Name then
					Part.Material = Enum.Material[Name] or Part.Material
					if typeof(Color) == "Color3" then
						Part.Color = Color
					end
					Part:SetAttribute("UniOriginalMaterial", nil)
					Part:SetAttribute("UniOriginalColor", nil)
				end
			end
		end)
	end
end

function Cosmetics.ApplyAllEffects(Character)
	local State = Cosmetics.State
	if not Character then
		return
	end
	if State.Effects.Trail then
		Cosmetics.ApplyTrail(Character, true)
	end
	for _, Kind in ipairs({ "Fire", "Smoke", "Lightning", "Sparkles" }) do
		if State.Effects[Kind] then
			Cosmetics.ApplyAura(Character, Kind, true)
		end
	end
	if State.MaterialMode then
		Cosmetics.ApplyMaterial(Character, State.MaterialMode)
	end
end

function Cosmetics.SetEffect(Kind, On)
	Cosmetics.State.Effects[Kind] = On
	task.spawn(function()
		for _ = 1, Config.CosmeticsRetry do
			local Character = GetCharacter()
			if Character and Cosmetics.GetRootPart(Character) then
				if Kind == "Trail" then
					Cosmetics.ApplyTrail(Character, On)
				else
					Cosmetics.ApplyAura(Character, Kind, On)
				end
				return
			end
			task.wait(Config.CosmeticsRetryGap)
		end
	end)
end

function Cosmetics.SetMaterial(Mode)
	Cosmetics.State.MaterialMode = Mode
	task.spawn(function()
		for _ = 1, Config.CosmeticsRetry do
			local Character = GetCharacter()
			if Character and GetHumanoid(Character) then
				Cosmetics.ApplyMaterial(Character, Mode)
				return
			end
			task.wait(Config.CosmeticsRetryGap)
		end
	end)
end

function Cosmetics.ApplyScales(Character)
	local State = Cosmetics.State
	local Humanoid = Character and GetHumanoid(Character)
	if not Humanoid or not State.ScalesTouched then
		return
	end

	for ValueName, Key in pairs({
		BodyHeightScale = "Height", BodyWidthScale = "Width", HeadScale = "Head",
		BodyProportionScale = "Proportion", BodyTypeScale = "BodyType",
	}) do
		local Value = Humanoid:FindFirstChild(ValueName)
		if Value and Value:IsA("NumberValue") then
			Value.Value = State.Scales[Key]
		end
	end
end

function Cosmetics.SetScale(Key, Value)
	Cosmetics.State.Scales[Key] = Value
	Cosmetics.State.ScalesTouched = true
	Cosmetics.ApplyScales(GetCharacter())
end

function Cosmetics.ApplyBodyColor(Character)
	local Colors = Character and Character:FindFirstChildOfClass("BodyColors")
	if not Colors or not Cosmetics.State.BodyColorName then
		return
	end
	local Brick = BrickColor.new(Cosmetics.State.BodyColorName)
	for _, Property in ipairs({ "HeadColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor", "TorsoColor" }) do
		pcall(function()
			Colors[Property] = Brick
		end)
	end
end

function Cosmetics.ApplyTPose(Character)
	if not Character then
		return
	end
	local Animate = Character:FindFirstChild("Animate")
	if Animate then
		if not Cosmetics.AnimateStash[Character] then
			pcall(function()
				Cosmetics.AnimateStash[Character] = Animate:Clone()
			end)
		end
		pcall(Animate.Destroy, Animate)
	end
	local Humanoid = GetHumanoid(Character)
	if Humanoid then
		for _, Track in ipairs(Humanoid:GetPlayingAnimationTracks()) do
			pcall(Track.Stop, Track, 0)
		end
	end
end

function Cosmetics.StopTPose(Character)
	local Stash = Character and Cosmetics.AnimateStash[Character]
	if Stash and not Character:FindFirstChild("Animate") then
		pcall(function()
			Stash.Parent = Character
		end)
	end
	if Character then
		Cosmetics.AnimateStash[Character] = nil
	end
end

function Cosmetics.StopAllTracks(Character)
	local Humanoid = Character and GetHumanoid(Character)
	if Humanoid then
		for _, Track in ipairs(Humanoid:GetPlayingAnimationTracks()) do
			pcall(Track.Stop, Track, 0)
		end
	end
end

function Cosmetics.GetAnimationSlot(Animate, Group, Child)
	local Folder = Animate and Animate:FindFirstChild(Group)
	return Folder and Folder:FindFirstChild(Child)
end

function Cosmetics.ApplyAnimationPack(Name)
	local Character = GetCharacter()
	local Animate = Character and Character:FindFirstChild("Animate")
	if not Animate then
		return false
	end
	Cosmetics.StopAllTracks(Character)
	if Cosmetics.OriginalAnimationCharacter ~= Character then
		local Map = {}
		for _, Slot in ipairs(Cosmetics.AnimationSlots) do
			local Object = Cosmetics.GetAnimationSlot(Animate, Slot[1], Slot[2])
			if Object then
				pcall(function()
					Map[Slot[1] .. "." .. Slot[2]] = Object.AnimationId
				end)
			end
		end
		Cosmetics.OriginalAnimationIds = Map
		Cosmetics.OriginalAnimationCharacter = Character
	end
	for _, Slot in ipairs(Cosmetics.AnimationSlots) do
		local Object = Cosmetics.GetAnimationSlot(Animate, Slot[1], Slot[2])
		if Object then
			local Target
			if Name and Name ~= "Default" then
				local Pack = Cosmetics.AnimationPacks[Name]
				if Pack and Pack[Slot[3]] then
					Target = "rbxassetid://" .. Pack[Slot[3]]
				end
			else
				Target = Cosmetics.OriginalAnimationIds and Cosmetics.OriginalAnimationIds[Slot[1] .. "." .. Slot[2]]
			end
			if Target then
				pcall(function()
					Object.AnimationId = Target
				end)
			end
		end
	end
	pcall(function()
		Animate.Disabled = true
	end)
	task.delay(0.15, function()
		pcall(function()
			if Animate and Animate.Parent then
				Animate.Disabled = false
			end
		end)
	end)
	Cosmetics.State.AnimationPack = Name or "Default"
	return true
end

function Cosmetics.StopCustomAnimation()
	if Cosmetics.CustomTrack then
		pcall(Cosmetics.CustomTrack.Stop, Cosmetics.CustomTrack, 0.15)
		Cosmetics.CustomTrack = nil
	end
end

function Cosmetics.PlayAnimation(AssetId, Looped)
	local Humanoid = GetHumanoid()
	if not Humanoid then
		return false
	end
	Cosmetics.StopCustomAnimation()
	local Animation = Instance.new("Animation")
	Animation.AnimationId = "rbxassetid://" .. tostring(AssetId)
	local Ok, Track = pcall(Humanoid.LoadAnimation, Humanoid, Animation)
	if Ok and Track then
		Track.Looped = Looped and true or false
		pcall(function()
			Track.Priority = Enum.AnimationPriority.Action
		end)
		pcall(Track.Play, Track)
		Cosmetics.CustomTrack = Track
		return true
	end
	return false
end

function Cosmetics.PlayEmote(Name, Id)
	local Humanoid = GetHumanoid()
	if not Humanoid then
		return false
	end
	Cosmetics.StopCustomAnimation()
	local Played = false
	if Name then
		pcall(function()
			Played = Humanoid:PlayEmote(Name, 0.1)
		end)
	end
	if Played then
		return true
	end
	return Id ~= nil and Cosmetics.PlayAnimation(Id, false)
end

function Cosmetics.GetAdjust(Id)
	local Adjust = Cosmetics.Adjust[Id]
	if not Adjust then
		Adjust = { X = 0, Y = 0, Z = 0, Scale = 1 }
		Cosmetics.Adjust[Id] = Adjust
	end
	return Adjust
end

function Cosmetics.ApplyAdjust(Character, Id)
	local Object = Character and Character:FindFirstChild("CustomAcc_" .. tostring(Id))
	if not Object then
		return
	end
	local Handle = Object:FindFirstChild("Handle") or Object
	local Adjust = Cosmetics.GetAdjust(Id)
	local Base = Cosmetics.AdjustBase[Id]
	if not Base then
		Base = {}
		Cosmetics.AdjustBase[Id] = Base
	end
	local Weld = Handle:FindFirstChildOfClass("Weld")
	if Weld then
		Base.Offset = Base.Offset or Weld.C0
		pcall(function()
			Weld.C0 = Base.Offset * CFrame.new(Adjust.X, Adjust.Y, Adjust.Z)
		end)
	end
	local Mesh = Handle:FindFirstChildOfClass("SpecialMesh")
	if Mesh then
		Base.Scale = Base.Scale or Mesh.Scale
		pcall(function()
			Mesh.Scale = Base.Scale * Adjust.Scale
		end)
	end
end

function Cosmetics.ResetAdjust(Id)
	Cosmetics.Adjust[Id] = { X = 0, Y = 0, Z = 0, Scale = 1 }
	Cosmetics.ApplyAdjust(GetCharacter(), Id)
end

function Cosmetics.AttachAccessory(Character, AssetId)
	local Tag = "CustomAcc_" .. tostring(AssetId)
	local Old = Character:FindFirstChild(Tag)
	if Old then
		Old:Destroy()
	end
	local Ok, Asset = pcall(function()
		return game:GetObjects("rbxassetid://" .. tostring(AssetId))[1]
	end)
	if not Ok or not Asset then
		return false
	end
	Asset.Name = Tag
	local Handle = Asset:FindFirstChild("Handle")
	local Head = Character:WaitForChild("Head", 8)
	if not Handle or not Head then
		return false
	end
	Handle.CanCollide = false
	Handle.Massless = true
	Asset.Parent = Character
	local Humanoid = GetHumanoid(Character)
	if Humanoid then
		pcall(Humanoid.AddAccessory, Humanoid, Asset)
	end
	local Existing = Handle:FindFirstChildOfClass("Weld") or Handle:FindFirstChildOfClass("WeldConstraint")
	if not Existing then
		local HandleAttachment = Handle:FindFirstChildOfClass("Attachment")
		local TargetPart, TargetAttachment = Head, nil
		if HandleAttachment then
			local Found = Character:FindFirstChild(HandleAttachment.Name, true)
			if Found and Found:IsA("Attachment") and Found.Parent and Found.Parent:IsA("BasePart") then
				TargetPart, TargetAttachment = Found.Parent, Found
			end
		end
		local Weld = Instance.new("Weld")
		Weld.Name = "AccessoryWeld"
		Weld.Part0, Weld.Part1 = TargetPart, Handle
		if HandleAttachment and TargetAttachment then
			Weld.C0, Weld.C1 = TargetAttachment.CFrame, HandleAttachment.CFrame
		else
			Weld.C0 = CFrame.new(0, 0.6, 0)
		end
		Weld.Parent = Handle
	end
	task.delay(0.25, function()
		if Asset and Asset.Parent then
			Cosmetics.ApplyAdjust(Character, AssetId)
		end
	end)
	return true
end

function Cosmetics.DetachAccessory(Character, AssetId)
	local Object = Character:FindFirstChild("CustomAcc_" .. tostring(AssetId))
	if Object then
		Object:Destroy()
	end
end

function Cosmetics.WearAccessory(Id)
	local Character = GetCharacter()
	if not Character or not Id then
		return
	end
	Cosmetics.State.Accessories[Id] = true
	task.spawn(Cosmetics.AttachAccessory, Character, Id)
end

function Cosmetics.RemoveAllAccessories()
	local Character = GetCharacter()
	local Removed = 0
	if Character then
		for _, Object in ipairs(Character:GetChildren()) do
			if Object:IsA("Accessory") and Object.Name:sub(1, 10) == "CustomAcc_" then
				pcall(Object.Destroy, Object)
				Removed = Removed + 1
			end
		end
	end
	for Id in pairs(Cosmetics.State.Accessories) do
		Cosmetics.State.Accessories[Id] = false
	end
	return Removed
end

function Cosmetics.GetWornAccessories()
	local List = {}
	local Character = GetCharacter()
	if Character then
		for _, Object in ipairs(Character:GetChildren()) do
			if Object:IsA("Accessory") and Object.Name:sub(1, 10) == "CustomAcc_" then
				table.insert(List, Object.Name:sub(11))
			end
		end
	end
	return List
end

function Cosmetics.Search(Keyword, Mode, Done)
	if Keyword == "" or Cosmetics.Busy then
		return
	end
	Cosmetics.Busy = true
	task.spawn(function()
		local Url = "https://catalog.roblox.com/v1/search/items/details?Keyword=" .. HttpService:UrlEncode(Keyword) .. "&Limit=" .. Config.SearchLimit
		local Body = HttpGetText(Url)
		local Out = {}
		local Reason
		if Body then
			local Ok, Data = pcall(HttpService.JSONDecode, HttpService, Body)
			if Ok and type(Data) == "table" and type(Data.errors) == "table" and Data.errors[1] then
				Reason = tostring(Data.errors[1].message or "request denied")
			end
			if Ok and type(Data) == "table" and type(Data.data) == "table" then
				for _, Item in ipairs(Data.data) do
					local AssetType = Item.assetType
					if Mode == "Accessory" then
						if Cosmetics.WearableAssetTypes[AssetType or 0] then
							table.insert(Out, Item)
						end
					elseif AssetType == 61 or AssetType == 24 then
						table.insert(Out, Item)
					end
				end
			end
		end
		Cosmetics.SearchResults = Out
		Cosmetics.Busy = false
		if Done then
			Done(Out, Body ~= nil, Reason)
		end
	end)
end

function Cosmetics.SetFeature(Key, On)
	local Character = GetCharacter()
	local State = Cosmetics.State
	if Key == "Korblox" then
		State.Korblox = On
		if Character then
			if Cosmetics.Restore.Korblox then
				Cosmetics.RemoveKorblox(Character, Cosmetics.Restore.Korblox)
			end
			Cosmetics.Restore.Korblox = On and Cosmetics.ApplyKorblox(Character) or nil
		end
	elseif Key == "Headless" then
		State.Headless = On
		if Character then
			if Cosmetics.Restore.Headless then
				Cosmetics.RemoveHeadless(Cosmetics.Restore.Headless)
			end
			Cosmetics.Restore.Headless = On and Cosmetics.ApplyHeadless(Character) or nil
		end
	elseif Key == "Face" then
		State.Face = On
		if Character then
			if On then
				task.spawn(Cosmetics.AttachFace, Character)
			else
				Cosmetics.DetachFace(Character)
			end
		end
	elseif Key == "ClearFace" then
		State.ClearFace = On
		Cosmetics.ApplyClearFace(Character, On)
	elseif Key == "ClearClothes" then
		State.ClearClothes = On
		Cosmetics.ApplyClearClothes(Character, On)
	elseif Key == "ClearAccessories" then
		State.ClearAccessories = On
		Cosmetics.ApplyClearAccessories(Character, On)
	elseif State.Effects[Key] ~= nil then
		Cosmetics.SetEffect(Key, On)
	elseif type(Key) == "number" then
		State.Accessories[Key] = On
		if Character then
			if On then
				task.spawn(Cosmetics.AttachAccessory, Character, Key)
			else
				Cosmetics.DetachAccessory(Character, Key)
			end
		end
	end
end

function Cosmetics.ReapplyAll(Character)
	local State = Cosmetics.State
	Cosmetics.Restore.Korblox, Cosmetics.Restore.Headless = nil, nil
	if not Character:WaitForChild("Humanoid", Config.WaitForCharacter) then
		return
	end
	task.wait(0.2)
	if State.Headless then
		Cosmetics.Restore.Headless = Cosmetics.ApplyHeadless(Character)
	end
	if State.Korblox then
		Cosmetics.Restore.Korblox = Cosmetics.ApplyKorblox(Character)
	end
	if State.Face then
		task.spawn(Cosmetics.AttachFace, Character)
	end
	for Id, On in pairs(State.Accessories) do
		if On then
			task.spawn(Cosmetics.AttachAccessory, Character, Id)
		end
	end
	if State.AnimationPack ~= "Default" then
		local Pack = State.AnimationPack
		task.spawn(function()
			for _ = 1, 8 do
				task.wait(0.5)
				if Cosmetics.ApplyAnimationPack(Pack) then
					break
				end
			end
		end)
	end
	if State.ClearFace or State.ClearClothes or State.ClearAccessories then
		for _, Delay in ipairs({ 1.2, 3 }) do
			task.delay(Delay, function()
				if Character and Character.Parent then
					Cosmetics.ApplyAllClears(Character)
				end
			end)
		end
	end
	task.delay(0.8, function()
		if Character and Character.Parent then
			Cosmetics.ApplyAllEffects(Character)
			Cosmetics.ApplyScales(Character)
			Cosmetics.ApplyBodyColor(Character)
		end
	end)
end

OnCharacter(Cosmetics.ReapplyAll)

Track(RunService.Heartbeat:Connect((function()
	local NextCheck = 0
	return function()
		if os.clock() < NextCheck then
			return
		end
		NextCheck = os.clock() + 2
		local Character = GetCharacter()
		local Root = Cosmetics.GetRootPart(Character)
		if not Root then
			return
		end
		local State = Cosmetics.State
		if State.Effects.Trail and not Root:FindFirstChild("UniRainbowTrail") then
			Cosmetics.ApplyTrail(Character, true)
		end
		for _, Kind in ipairs({ "Fire", "Smoke", "Lightning", "Sparkles" }) do
			if State.Effects[Kind] and not Root:FindFirstChild("UniFX_" .. Kind) then
				Cosmetics.ApplyAura(Character, Kind, true)
			end
		end
		if State.MaterialMode then
			Cosmetics.ApplyMaterial(Character, State.MaterialMode)
		end
	end
end)()))

OnCleanup(function()
	local Character = GetCharacter()
	Cosmetics.StopCustomAnimation()
	if Character then
		if Cosmetics.Restore.Korblox then
			Cosmetics.RemoveKorblox(Character, Cosmetics.Restore.Korblox)
		end
		if Cosmetics.Restore.Headless then
			Cosmetics.RemoveHeadless(Cosmetics.Restore.Headless)
		end
		Cosmetics.DetachFace(Character)
		Cosmetics.ApplyClearFace(Character, false)
		Cosmetics.ApplyClearClothes(Character, false)
		Cosmetics.ApplyClearAccessories(Character, false)
		Cosmetics.ApplyTrail(Character, false)
		for _, Kind in ipairs({ "Fire", "Smoke", "Lightning", "Sparkles" }) do
			Cosmetics.ApplyAura(Character, Kind, false)
		end
		Cosmetics.ApplyMaterial(Character, nil)
		Cosmetics.RemoveAllAccessories()
		Cosmetics.StopTPose(Character)
	end
end)

local function DestroyInterfaces()
	local Roots = { CoreGui, LocalPlayer:FindFirstChildOfClass("PlayerGui") }
	if Capabilities.GetHui then
		local Ok, Hui = pcall(gethui)
		if Ok and typeof(Hui) == "Instance" then
			table.insert(Roots, Hui)
		end
	end
	for _, Root in ipairs(Roots) do
		local Ok, Children = pcall(Root.GetChildren, Root)
		if Ok then
			for _, Child in ipairs(Children) do
				if Child:IsA("ScreenGui") and (table.find(Config.InterfaceNames, Child.Name) or Child:GetAttribute("AetherUI")) then
					pcall(Child.Destroy, Child)
				end
			end
		end
	end
	for _, Name in ipairs(Config.InterfaceGlobals) do
		GetEnv[Name] = nil
	end
end

local function IsLibrary(Candidate)
	return type(Candidate) == "table" and type(Candidate.Window) == "function"
end

local function FindPublishedLibrary()
	local Sources = { GetEnv }
	if typeof(_G) == "table" then
		table.insert(Sources, _G)
	end
	if typeof(shared) == "table" then
		table.insert(Sources, shared)
	end
	for _, Source in ipairs(Sources) do
		for _, Name in ipairs({ "Library", "Aether", "AetherUI", "AetherLibrary" }) do
			if IsLibrary(Source[Name]) then
				return Source[Name]
			end
		end
	end
	return nil
end

local function LoadInterface()
	local genv = (typeof(getgenv) == "function" and getgenv()) or _G
	local Session = genv.AetherSession
	if type(Session) ~= "table" then
		Session = genv.AetherRuntime and genv.AetherRuntime.new()
		if not Session then
			Session = { task = task }
			function Session:Track(x) return x end
			function Session:Service(n) return game:GetService(n) end
		end
		genv.AetherSession = Session
	end
	local task = Session.task

	if Session.OnCleanup then
		Session:OnCleanup(function()
			for _, n in ipairs({ "Library", "Aether", "AetherUI", "AetherLibrary", "SaveTheme", "CurrentWindow" }) do
				genv[n] = nil
				if typeof(_G) == "table" then _G[n] = nil end
				if typeof(shared) == "table" then shared[n] = nil end
			end
		end)
	end

	local Library = Library or {}
	local SaveTheme = SaveTheme or {}

	local function exportGlobals(lib)
		if typeof(getgenv) == "function" then
			local genv = getgenv()
			genv.Library = lib
			genv.Aether = lib
			genv.AetherUI = lib
			genv.AetherLibrary = lib
			genv.SaveTheme = SaveTheme
		end
		if typeof(_G) == "table" then
			_G.Library = lib
			_G.Aether = lib
			_G.AetherUI = lib
			_G.AetherLibrary = lib
			_G.SaveTheme = SaveTheme
		end
		if typeof(shared) == "table" then
			shared.Library = lib
			shared.Aether = lib
			shared.AetherUI = lib
			shared.AetherLibrary = lib
			shared.SaveTheme = SaveTheme
		end
		pcall(function()
			local env = (getfenv and (getfenv(0) or getfenv(1)))
			if env then
				env.Library = lib
				env.Aether = lib
				env.AetherUI = lib
				env.AetherLibrary = lib
				env.SaveTheme = SaveTheme
			end
		end)
		Library = lib
		Aether = lib
		AetherUI = lib
		AetherLibrary = lib
	end

	exportGlobals(Library)

	local themes = {
		index = {'Default', 'Halloween'},
		Default = {
			['Shadow'] = Color3.fromRGB(0, 0, 0),
			['Background'] = Color3.fromRGB(12, 12, 14),
			['Page'] = Color3.fromRGB(12, 12, 14),
			['Sidebar'] = Color3.fromRGB(14, 14, 17),
			['Card'] = Color3.fromRGB(19, 19, 23),
			['CardBorder'] = Color3.fromRGB(36, 36, 44),
			['Main'] = Color3.fromRGB(255, 255, 255),
			['MainDark'] = Color3.fromRGB(30, 30, 38),
			['MainLight'] = Color3.fromRGB(230, 230, 235),
			['Text & Icon'] = Color3.fromRGB(255, 255, 255),
			['SubText'] = Color3.fromRGB(140, 140, 150),
			['Success'] = Color3.fromRGB(34, 197, 94),
			['Function'] = {
				['Toggle'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['True'] = {
						['Toggle Background'] = Color3.fromRGB(255, 255, 255),
						['Toggle Value'] = Color3.fromRGB(14, 14, 17),
					},
					['False'] = {
						['Toggle Background'] = Color3.fromRGB(36, 36, 46),
						['Toggle Value'] = Color3.fromRGB(150, 150, 160),
					}
				},
				['Label'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
				},
				['Dropdown'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['Value Background'] = Color3.fromRGB(15, 15, 18),
					['Value Stroke'] = Color3.fromRGB(44, 44, 54),
					['Dropdown Select'] = {
						['Background'] = Color3.fromRGB(15, 15, 18),
						['Search'] = Color3.fromRGB(24, 24, 30),
						['Item Background'] = Color3.fromRGB(24, 24, 30),
					}
				},
				['Slider'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['Value Background'] = Color3.fromRGB(15, 15, 18),
					['Value Stroke'] = Color3.fromRGB(44, 44, 54),
					['Slider Bar'] = Color3.fromRGB(36, 36, 46),
					['Slider Bar Value'] = Color3.fromRGB(255, 255, 255),
					['Circle Value'] = Color3.fromRGB(255, 255, 255)
				},
				['Code'] = {
					['Background'] = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 19, 23)), ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 19, 23))},
					['Background Code'] = Color3.fromRGB(24, 24, 30),
					['Background Code Value'] = Color3.fromRGB(15, 15, 18),
					['ScrollingFrame Code'] = Color3.fromRGB(255, 255, 255)
				},
				['Button'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['Border'] = Color3.fromRGB(255, 255, 255),
					['Click'] = Color3.fromRGB(255, 255, 255)
				},
				['Textbox'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['Value Background'] = Color3.fromRGB(15, 15, 18),
					['Value Stroke'] = Color3.fromRGB(44, 44, 54),
				},
				['Keybind'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['Value Background'] = Color3.fromRGB(15, 15, 18),
					['Value Stroke'] = Color3.fromRGB(44, 44, 54),
					['True'] = {
						['Toggle Background'] = Color3.fromRGB(255, 255, 255),
						['Toggle Value'] = Color3.fromRGB(14, 14, 17),
					},
					['False'] = {
						['Toggle Background'] = Color3.fromRGB(36, 36, 46),
						['Toggle Value'] = Color3.fromRGB(150, 150, 160),
					}
				},
				['Color Picker'] = {
					['Background'] = Color3.fromRGB(19, 19, 23),
					['Color Select'] = {
						['Background'] = Color3.fromRGB(15, 15, 18),
						['UIStroke'] = Color3.fromRGB(44, 44, 54),
					}
				}
			}
		},
		Halloween = {
			['Shadow'] = Color3.fromRGB(200, 70, 0),
			['Background'] = Color3.fromRGB(13, 11, 12),
			['Page'] = Color3.fromRGB(13, 11, 12),
			['Sidebar'] = Color3.fromRGB(16, 13, 15),
			['Card'] = Color3.fromRGB(22, 18, 20),
			['CardBorder'] = Color3.fromRGB(56, 38, 30),
			['Main'] = Color3.fromRGB(255, 115, 20),
			['MainDark'] = Color3.fromRGB(58, 28, 12),
			['MainLight'] = Color3.fromRGB(255, 145, 45),
			['Text & Icon'] = Color3.fromRGB(255, 245, 235),
			['SubText'] = Color3.fromRGB(175, 150, 140),
			['Success'] = Color3.fromRGB(255, 140, 0),
			['Function'] = {
				['Toggle'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['True'] = {
						['Toggle Background'] = Color3.fromRGB(255, 115, 20),
						['Toggle Value'] = Color3.fromRGB(255, 255, 255),
					},
					['False'] = {
						['Toggle Background'] = Color3.fromRGB(40, 32, 35),
						['Toggle Value'] = Color3.fromRGB(150, 130, 120),
					}
				},
				['Label'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
				},
				['Dropdown'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['Value Background'] = Color3.fromRGB(18, 14, 16),
					['Value Stroke'] = Color3.fromRGB(56, 40, 34),
					['Dropdown Select'] = {
						['Background'] = Color3.fromRGB(18, 14, 16),
						['Search'] = Color3.fromRGB(28, 22, 25),
						['Item Background'] = Color3.fromRGB(28, 22, 25),
					}
				},
				['Slider'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['Value Background'] = Color3.fromRGB(18, 14, 16),
					['Value Stroke'] = Color3.fromRGB(56, 40, 34),
					['Slider Bar'] = Color3.fromRGB(45, 34, 30),
					['Slider Bar Value'] = Color3.fromRGB(255, 115, 20),
					['Circle Value'] = Color3.fromRGB(255, 255, 255)
				},
				['Code'] = {
					['Background'] = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 18, 20)), ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 18, 20))},
					['Background Code'] = Color3.fromRGB(28, 22, 25),
					['Background Code Value'] = Color3.fromRGB(18, 14, 16),
					['ScrollingFrame Code'] = Color3.fromRGB(255, 115, 20)
				},
				['Button'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['Border'] = Color3.fromRGB(255, 115, 20),
					['Click'] = Color3.fromRGB(255, 255, 255)
				},
				['Textbox'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['Value Background'] = Color3.fromRGB(18, 14, 16),
					['Value Stroke'] = Color3.fromRGB(56, 40, 34),
				},
				['Keybind'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['Value Background'] = Color3.fromRGB(18, 14, 16),
					['Value Stroke'] = Color3.fromRGB(56, 40, 34),
					['True'] = {
						['Toggle Background'] = Color3.fromRGB(255, 115, 20),
						['Toggle Value'] = Color3.fromRGB(255, 255, 255),
					},
					['False'] = {
						['Toggle Background'] = Color3.fromRGB(40, 32, 35),
						['Toggle Value'] = Color3.fromRGB(150, 130, 120),
					}
				},
				['Color Picker'] = {
					['Background'] = Color3.fromRGB(22, 18, 20),
					['Color Select'] = {
						['Background'] = Color3.fromRGB(18, 14, 16),
						['UIStroke'] = Color3.fromRGB(56, 40, 34),
					}
				}
			}
		}
	}

	local function deepCopy(orig)
		local orig_type = type(orig)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in next, orig, nil do
				copy[deepCopy(orig_key)] = deepCopy(orig_value)
			end
		else
			copy = orig
		end
		return copy
	end

	local CoreGui = game:GetService("CoreGui")
	local Players = game:GetService("Players")
	local HttpService = game:GetService("HttpService")
	local U, Tw = Session:Service("UserInputService"), game:GetService("TweenService")
	local SoundService = game:GetService("SoundService")
	local LocalPlayer = Players.LocalPlayer

	local function attachAutoScale(frame, baseW, baseH, fill)
		fill = fill or 0.9
		local scale = Instance.new("UIScale")
		scale.Name = "AutoScale"
		scale.Parent = frame
		local cam
		local camConn
		local function update()
			local c = workspace.CurrentCamera
			local vp = c and c.ViewportSize or Vector2.new(1920, 1080)
			if vp.X < 2 or vp.Y < 2 then return end
			scale.Scale = math.clamp(math.min((vp.X * fill) / baseW, (vp.Y * fill) / baseH, 1), 0.35, 1)
		end
		local function bindCamera()
			if camConn then camConn:Disconnect() end
			cam = workspace.CurrentCamera
			if cam then
				camConn = Session:Track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(update))
			end
			update()
		end
		Session:Track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
		frame.Destroying:Connect(function() if camConn then camConn:Disconnect() end end)
		bindCamera()
		return scale
	end

	local function getGuiParent()
		local success, _ = pcall(function() return CoreGui:GetChildren() end)
		if success then return CoreGui end
		return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or game:GetService("StarterGui")
	end

	local parentGui = getGuiParent()
	pcall(function()
		local parentsToSearch = {parentGui}
		if CoreGui and not table.find(parentsToSearch, CoreGui) then table.insert(parentsToSearch, CoreGui) end
		if typeof(gethui) == "function" then
			local h = gethui()
			if h and not table.find(parentsToSearch, h) then table.insert(parentsToSearch, h) end
		end
		local lp = Players.LocalPlayer
		local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
		if pg and not table.find(parentsToSearch, pg) then table.insert(parentsToSearch, pg) end

		for _, p in ipairs(parentsToSearch) do
			for _, name in ipairs({"Aether", "Core"}) do
				local ex = p:FindFirstChild(name)
				if ex then
					pcall(function() ex:Destroy() end)
				end
			end
		end
	end)

	local ScreenGui = Instance.new("ScreenGui")
	Session:Track(ScreenGui)
	ScreenGui.Name = "Aether"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.DisplayOrder = 999
	ScreenGui:SetAttribute("AetherUI", true)
	ScreenGui.Parent = parentGui

	local FileSystem = {
		HasFS = (type(writefile) == "function" and type(readfile) == "function"),
		MemStore = { Configs = {}, Themes = {}, Wallpapers = {}, Autoload = "", WindowSize = nil }
	}

	function FileSystem:Init()
		if not self.HasFS then return end
		pcall(function()
			if type(isfolder) == "function" and type(makefolder) == "function" then
				if not isfolder("Aether") then makefolder("Aether") end
				if not isfolder("Aether/Configs") then makefolder("Aether/Configs") end
				if not isfolder("Aether/Themes") then makefolder("Aether/Themes") end
				if not isfolder("Aether/Themes/Wallpaper") then makefolder("Aether/Themes/Wallpaper") end
				if not isfolder("Aether/Themes/Sounds") then makefolder("Aether/Themes/Sounds") end
				if not isfolder("Aether/Themes/Cursors") then makefolder("Aether/Themes/Cursors") end
			end
		end)
	end

	function FileSystem:ListWallpapers()
		local list = {}
		if self.HasFS then
			pcall(function()
				self:Init()
				local dirs = { "Aether/Themes/Wallpaper", "Aether/Themes/Wallpapers", "Aether/Wallpaper" }
				if type(listfiles) == "function" and type(isfolder) == "function" then
					for _, dir in ipairs(dirs) do
						if isfolder(dir) then
							for _, path in ipairs(listfiles(dir)) do
								local fileName = path:match("([^/\\]+%.[pP][nN][gG])$")
									or path:match("([^/\\]+%.[jJ][pP][gG])$")
									or path:match("([^/\\]+%.[jJ][pP][eE][gG])$")
									or path:match("([^/\\]+%.[wW][eE][bB][pP])$")
									or path:match("([^/\\]+%.[bB][mM][pP])$")
								if fileName and not table.find(list, fileName) then
									table.insert(list, fileName)
								end
							end
						end
					end
				end
			end)
		else
			for k, _ in pairs(self.MemStore.Wallpapers or {}) do
				table.insert(list, k)
			end
		end
		return list
	end

	function FileSystem:GetWallpaperAsset(val)
		if not val or val == "" then return "" end
		local sVal = tostring(val)
		if sVal:match("^%d+$") then
			return "rbxassetid://" .. sVal
		elseif sVal:match("^rbxassetid://") or sVal:match("^rbxasset://") or sVal:match("^https?://") then
			return sVal
		end

		if self.MemStore and self.MemStore.Wallpapers and self.MemStore.Wallpapers[sVal] then
			return self.MemStore.Wallpapers[sVal]
		end

		local getAsset = (type(getcustomasset) == "function" and getcustomasset)
			or (type(getsynasset) == "function" and getsynasset)

		if getAsset and self.HasFS then
			local dirs = { "Aether/Themes/Wallpaper/", "Aether/Themes/Wallpapers/", "Aether/Wallpaper/" }
			for _, dir in ipairs(dirs) do
				local p = dir .. sVal
				if type(isfile) == "function" and isfile(p) then
					local s, res = pcall(function() return getAsset(p) end)
					if s and res then return res end
				end
			end
			if type(isfile) == "function" and isfile(sVal) then
				local s, res = pcall(function() return getAsset(sVal) end)
				if s and res then return res end
			end
		end

		return sVal
	end

	function FileSystem:ListSounds()
		local list = {}
		if self.HasFS then
			pcall(function()
				self:Init()
				local dirs = { "Aether/Themes/Sounds", "Aether/Sounds" }
				if type(listfiles) == "function" and type(isfolder) == "function" then
					for _, dir in ipairs(dirs) do
						if isfolder(dir) then
							for _, path in ipairs(listfiles(dir)) do
								local fileName = path:match("([^/\\]+%.[mM][pP]3)$")
									or path:match("([^/\\]+%.[oO][gG][gG])$")
									or path:match("([^/\\]+%.[wW][aA][vV])$")
								if fileName and not table.find(list, fileName) then
									table.insert(list, fileName)
								end
							end
						end
					end
				end
			end)
		end
		return list
	end

	function FileSystem:GetAudioAsset(val)
		if not val or val == "" then return "" end
		local sVal = tostring(val)
		if sVal:match("^%d+$") then
			return "rbxassetid://" .. sVal
		elseif sVal:match("^rbxassetid://") or sVal:match("^rbxasset://") or sVal:match("^https?://") then
			return sVal
		end

		local getAsset = (type(getcustomasset) == "function" and getcustomasset)
			or (type(getsynasset) == "function" and getsynasset)

		if getAsset and self.HasFS then
			local dirs = { "Aether/Themes/Sounds/", "Aether/Sounds/" }
			for _, dir in ipairs(dirs) do
				local p = dir .. sVal
				if type(isfile) == "function" and isfile(p) then
					local s, res = pcall(function() return getAsset(p) end)
					if s and res then return res end
				end
			end
			if type(isfile) == "function" and isfile(sVal) then
				local s, res = pcall(function() return getAsset(sVal) end)
				if s and res then return res end
			end
		end

		return sVal
	end

	function FileSystem:ListCursors()
		local list = {}
		if self.HasFS then
			pcall(function()
				self:Init()
				local dirs = { "Aether/Themes/Cursors", "Aether/Cursors" }
				if type(listfiles) == "function" and type(isfolder) == "function" then
					for _, dir in ipairs(dirs) do
						if isfolder(dir) then
							for _, path in ipairs(listfiles(dir)) do
								local fileName = path:match("([^/\\]+%.[pP][nN][gG])$")
									or path:match("([^/\\]+%.[jJ][pP][gG])$")
									or path:match("([^/\\]+%.[iI][cC][oO])$")
								if fileName and not table.find(list, fileName) then
									table.insert(list, fileName)
								end
							end
						end
					end
				end
			end)
		end
		return list
	end

	function FileSystem:GetCursorAsset(val)
		if not val or val == "" or val == "None" or val == "Default" or val == "Default (Roblox)" then return "" end
		local sVal = tostring(val)
		if sVal:match("^%d+$") then
			return "rbxassetid://" .. sVal
		elseif sVal:match("^rbxassetid://") or sVal:match("^rbxasset://") or sVal:match("^https?://") then
			return sVal
		end

		local getAsset = (type(getcustomasset) == "function" and getcustomasset)
			or (type(getsynasset) == "function" and getsynasset)

		if getAsset and self.HasFS then
			local dirs = { "Aether/Themes/Cursors/", "Aether/Cursors/" }
			for _, dir in ipairs(dirs) do
				local p = dir .. sVal
				if type(isfile) == "function" and isfile(p) then
					local s, res = pcall(function() return getAsset(p) end)
					if s and res then return res end
				end
			end
			if type(isfile) == "function" and isfile(sVal) then
				local s, res = pcall(function() return getAsset(sVal) end)
				if s and res then return res end
			end
		end

		return sVal
	end

	function FileSystem:SaveConfig(name, data)
		local encoded = HttpService:JSONEncode(data)
		if self.HasFS then
			pcall(function()
				self:Init()
				writefile("Aether/Configs/" .. name .. ".json", encoded)
			end)
		else
			self.MemStore.Configs[name] = encoded
		end
	end

	function FileSystem:LoadConfig(name)
		local content = nil
		if self.HasFS then
			pcall(function()
				if type(isfile) == "function" and isfile("Aether/Configs/" .. name .. ".json") then
					content = readfile("Aether/Configs/" .. name .. ".json")
				end
			end)
		else
			content = self.MemStore.Configs[name]
		end
		if content then
			local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
			if s and type(decoded) == "table" then return decoded end
		end
		return nil
	end

	function FileSystem:DeleteConfig(name)
		if self.HasFS then
			pcall(function()
				if type(delfile) == "function" and type(isfile) == "function" and isfile("Aether/Configs/" .. name .. ".json") then
					delfile("Aether/Configs/" .. name .. ".json")
				end
			end)
		else
			self.MemStore.Configs[name] = nil
		end
	end

	function FileSystem:ListConfigs()
		local list = {}
		if self.HasFS then
			pcall(function()
				self:Init()
				if type(listfiles) == "function" then
					for _, path in ipairs(listfiles("Aether/Configs")) do
						local fileName = path:match("([^/\\]+)%.json$")
						if fileName then table.insert(list, fileName) end
					end
				end
			end)
		else
			for name, _ in pairs(self.MemStore.Configs) do table.insert(list, name) end
		end
		return list
	end

	function FileSystem:SaveWindowSize(width, height)
		local data = { Width = math.round(width), Height = math.round(height) }
		local encoded = HttpService:JSONEncode(data)
		if self.HasFS then
			pcall(function()
				self:Init()
				writefile("Aether/WindowSize.json", encoded)
			end)
		else
			self.MemStore.WindowSize = encoded
		end
	end

	function FileSystem:LoadWindowSize()
		local content = nil
		if self.HasFS then
			pcall(function()
				if type(isfile) == "function" and isfile("Aether/WindowSize.json") then
					content = readfile("Aether/WindowSize.json")
				end
			end)
		else
			content = self.MemStore.WindowSize
		end
		if content then
			local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
			if s and type(decoded) == "table" and decoded.Width and decoded.Height then
				return decoded.Width, decoded.Height
			end
		end
		return nil, nil
	end

	function FileSystem:ResetWindowSize()
		if self.HasFS then
			pcall(function()
				if type(delfile) == "function" and type(isfile) == "function" and isfile("Aether/WindowSize.json") then
					delfile("Aether/WindowSize.json")
				end
			end)
		else
			self.MemStore.WindowSize = nil
		end
	end

	function FileSystem:SaveTheme(name, data)
		local encoded = HttpService:JSONEncode(data)
		if self.HasFS then
			pcall(function()
				self:Init()
				writefile("Aether/Themes/" .. name .. ".json", encoded)
			end)
		else
			self.MemStore.Themes[name] = encoded
		end
	end

	function FileSystem:LoadTheme(name)
		local content = nil
		if self.HasFS then
			pcall(function()
				if type(isfile) == "function" and isfile("Aether/Themes/" .. name .. ".json") then
					content = readfile("Aether/Themes/" .. name .. ".json")
				end
			end)
		else
			content = self.MemStore.Themes[name]
		end
		if content then
			local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
			if s and type(decoded) == "table" then return decoded end
		end
		return nil
	end

	function FileSystem:ListThemes()
		local list = {}
		if self.HasFS then
			pcall(function()
				if type(listfiles) == "function" and type(isfolder) == "function" and isfolder("Aether/Themes") then
					for _, path in ipairs(listfiles("Aether/Themes")) do
						local name = path:match("([^/\\]+)%.json$")
						if name then table.insert(list, name) end
					end
				end
			end)
		else
			for k, _ in pairs(self.MemStore.Themes) do table.insert(list, k) end
		end
		return list
	end

	function FileSystem:SetAutoload(name)
		if self.HasFS then
			pcall(function()
				self:Init()
				writefile("Aether/autoload.txt", name or "")
			end)
		else
			self.MemStore.Autoload = name or ""
		end
	end

	function FileSystem:GetAutoload()
		local name = ""
		if self.HasFS then
			pcall(function()
				if type(isfile) == "function" and isfile("Aether/autoload.txt") then
					name = readfile("Aether/autoload.txt")
				end
			end)
		else
			name = self.MemStore.Autoload
		end
		return (name and name ~= "") and name or nil
	end

	FileSystem:Init()

	local currentWindowTheme = {
		name = "Default",
		colors = deepCopy(themes.Default),
		cards = {},
		sections = {},
		controls = {},
		tabs = {},
		topTabs = {},
		subTabs = {},
	}

	do
		function addToTheme(name, obj)
			if not SaveTheme[name] then
				SaveTheme[name] = {}
			end
			table.insert(SaveTheme[name], obj)
		end

		function getColorFromPath(tbl, path)
			local result = tbl
			for _, part in ipairs(string.split(path, ".")) do
				result = result and result[part]
			end
			return result
		end

		local IconList = nil
		pcall(function()
			IconList = loadstring(game:HttpGet('https://raw.githubusercontent.com/DuxiiT/Aether/refs/heads/main/Icons.lua'))()
		end)

		local IconAliases = {
			["home"] = "house",
			["scripts"] = "code",
			["script"] = "code",
			["games"] = "gamepad-2",
			["game"] = "gamepad-2",
			["executor"] = "package",
			["modules"] = "layout-grid",
			["module"] = "layout-grid",
			["settings"] = "settings",
			["gear"] = "settings",
			["profile"] = "user",
			["pulse"] = "activity",
			["timer"] = "clock",
			["lightning"] = "zap",
			["bolt"] = "zap",
			["tuning"] = "sliders",
		}

		local FallbackAssetIcons = {
			["house"] = "rbxassetid://10723407389",
			["code"] = "rbxassetid://10709790644",
			["gamepad-2"] = "rbxassetid://10709798000",
			["package"] = "rbxassetid://10709819149",
			["layout-grid"] = "rbxassetid://10709810948",
			["settings"] = "rbxassetid://10734950309",
			["zap"] = "rbxassetid://10709819266",
			["user"] = "rbxassetid://10747373176",
			["clock"] = "rbxassetid://10709789965",
			["activity"] = "rbxassetid://10709788052",
			["shield"] = "rbxassetid://10734952480",
			["file-text"] = "rbxassetid://10723387563",
			["link"] = "rbxassetid://10709810817",
			["play"] = "rbxassetid://10734942127",
			["bell"] = "rbxassetid://10709790100",
			["monitor"] = "rbxassetid://10709811124",
			["search"] = "rbxassetid://10734943902",
			["copy"] = "rbxassetid://10709790387",
			["check"] = "rbxassetid://10709790202",
			["chevron-right"] = "rbxassetid://10709791437",
			["discord"] = "rbxassetid://119690296342461",
		}

		function gl(i)
			if type(i) == "string" then
				local key = string.lower(i)
				if IconAliases[key] then key = IconAliases[key] end
				if key == "discord" then
					return { Image = "rbxassetid://119690296342461", ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
				end
				if IconList and IconList.Icons and IconList.Icons[key] then
					local iconData = IconList.Icons[key]
					local spriteSheet = IconList.Spritesheets and IconList.Spritesheets[tostring(iconData.Image)]
					if spriteSheet then
						return { Image = spriteSheet, ImageRectSize = iconData.ImageRectSize, ImageRectPosition = iconData.ImageRectPosition }
					end
				end
				if FallbackAssetIcons[key] then
					return { Image = FallbackAssetIcons[key], ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
				end
			end
			if type(i) == 'string' and not i:find('rbxassetid://') and tonumber(i) then
				return { Image = "rbxassetid://".. i, ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
			elseif type(i) == 'number' then
				return { Image = "rbxassetid://".. i, ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
			else
				return { Image = (type(i) == 'string' and i ~= '') and i or "rbxassetid://10723407389", ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
			end
		end

		function tw(info)
			return Tw:Create(info.v, TweenInfo.new(info.t, info.s or Enum.EasingStyle.Quad, Enum.EasingDirection[info.d or "Out"]), info.g)
		end

		function changecanvas(ScrollingFrame, UIListLayout, Plus)
			UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + (Plus or 10))
			end)
		end

		function lak(t, o)
			local a, b, c, d
			local function u(i)
				local dt = i.Position - c
				tw({v = o, t = 0.04, s = Enum.EasingStyle.Linear, d = "InOut", g = {Position = UDim2.new(d.X.Scale, d.X.Offset + dt.X, d.Y.Scale, d.Y.Offset + dt.Y)}}):Play()
			end
			t.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					a = true
					c = i.Position
					d = o.Position
					i.Changed:Connect(function()
						if i.UserInputState == Enum.UserInputState.End then a = false end
					end)
				end
			end)
			t.InputChanged:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then b = i end
			end)
			U.InputChanged:Connect(function(i)
				if i == b and a then u(i) end
			end)
		end

		local playClickSound = function() end

		function click(p)
			local Click = Instance.new("TextButton")
			Click.Name = "Click"
			Click.Parent = p
			Click.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			Click.BackgroundTransparency = 1
			Click.BorderSizePixel = 0
			Click.Size = UDim2.new(1, 0, 1, 0)
			Click.Font = Enum.Font.SourceSans
			Click.Text = ""
			Click.ZIndex = 5
			Click.MouseButton1Click:Connect(function()
				pcall(playClickSound)
			end)
			return Click
		end

		function jc(c, p)
			local Mouse = LocalPlayer:GetMouse()
			local relativeX = Mouse.X - c.AbsolutePosition.X
			local relativeY = Mouse.Y - c.AbsolutePosition.Y
			if relativeX < 0 or relativeY < 0 or relativeX > c.AbsoluteSize.X or relativeY > c.AbsoluteSize.Y then return end

			local Ripple = Instance.new("Frame")
			Ripple.Parent = p
			Ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			Ripple.BackgroundTransparency = 0.7
			Ripple.BorderSizePixel = 0
			Ripple.AnchorPoint = Vector2.new(0.5, 0.5)
			Ripple.Position = UDim2.new(0, relativeX, 0, relativeY)
			Ripple.Size = UDim2.new(0, 0, 0, 0)
			Ripple.ZIndex = 8

			local UICorner = Instance.new("UICorner")
			UICorner.CornerRadius = UDim.new(1, 0)
			UICorner.Parent = Ripple

			local expandTween = Tw:Create(Ripple, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, c.AbsoluteSize.X * 1.5, 0, c.AbsoluteSize.X * 1.5),
				BackgroundTransparency = 1
			})
			expandTween.Completed:Connect(function() Ripple:Destroy() end)
			expandTween:Play()
		end

		function background(pl, t, d, i, ty)
			local Background = Instance.new("Frame")
			local UICorner_1 = Instance.new("UICorner")
			local UIStroke_1 = Instance.new("UIStroke")
			local T_1 = Instance.new("Frame")
			local UIListLayout_2 = Instance.new("UIListLayout")
			local UIPadding_3 = Instance.new("UIPadding")
			local TextLabel_1 = Instance.new("TextLabel")
			local TextLabel_2 = Instance.new("TextLabel")

			local curColors = (currentWindowTheme and currentWindowTheme.colors) or themes.Default
			local curTrans = (currentWindowTheme and currentWindowTheme.transparency) or {}

			Background.Name = "Background"
			Background.Parent = pl
			Background.BackgroundColor3 = curColors['Card']
			Background.BackgroundTransparency = (curTrans.Card or 0) / 100
			Background.BorderSizePixel = 0
			Background.Size = UDim2.new(1, 0, 0, (ty == "Label" or not (d and d ~= "")) and 48 or 54)
			Background.ClipsDescendants = true

			UICorner_1.CornerRadius = UDim.new(0, 6)
			UICorner_1.Parent = Background

			UIStroke_1.Color = curColors['CardBorder']
			UIStroke_1.Thickness = 1
			UIStroke_1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			UIStroke_1.Parent = Background

			T_1.Name = "T"
			T_1.Parent = Background
			T_1.AnchorPoint = Vector2.new(0, 0.5)
			T_1.BackgroundTransparency = 1
			T_1.BorderSizePixel = 0
			T_1.Position = UDim2.new(0, 0, 0.5, 0)
			T_1.Size = UDim2.new(1, 0, 1, 0)

			UIListLayout_2.Parent = T_1
			UIListLayout_2.SortOrder = Enum.SortOrder.LayoutOrder
			UIListLayout_2.VerticalAlignment = Enum.VerticalAlignment.Center
			UIListLayout_2.Padding = UDim.new(0, 4)

			UIPadding_3.Parent = T_1
			UIPadding_3.PaddingLeft = UDim.new(0, 12)
			UIPadding_3.PaddingRight = UDim.new(0, 80)

			TextLabel_2.Name = 'Title'
			TextLabel_2.Parent = T_1
			TextLabel_2.BackgroundTransparency = 1
			TextLabel_2.BorderSizePixel = 0
			TextLabel_2.Size = UDim2.new(1, 0, 0, 20)
			TextLabel_2.Font = Enum.Font.BuilderSansBold
			TextLabel_2.RichText = true
			TextLabel_2.Text = tostring(t)
			TextLabel_2.TextColor3 = curColors['Text & Icon']
			TextLabel_2.TextSize = 16
			TextLabel_2.TextWrapped = true
			TextLabel_2.TextXAlignment = Enum.TextXAlignment.Left
			TextLabel_2.AutomaticSize = Enum.AutomaticSize.Y

			TextLabel_1.Name = 'Desc'
			TextLabel_1.Parent = (ty == "Label") and Background or T_1
			TextLabel_1.BackgroundTransparency = 1
			TextLabel_1.BorderSizePixel = 0
			TextLabel_1.LayoutOrder = 1
			TextLabel_1.Font = (ty == "Label") and Enum.Font.BuilderSansBold or Enum.Font.BuilderSansMedium
			TextLabel_1.RichText = false
			TextLabel_1.Text = tostring(d)
			TextLabel_1.TextColor3 = (ty == "Label") and curColors['Main'] or curColors['SubText']
			TextLabel_1.TextSize = (ty == "Label") and 18 or 14
			TextLabel_1.TextWrapped = (ty ~= "Label")
			TextLabel_1.TextXAlignment = (ty == "Label") and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
			TextLabel_1.Visible = (d and d ~= "")

			if ty == "Label" then
				TextLabel_1.AnchorPoint = Vector2.new(1, 0.5)
				TextLabel_1.Position = UDim2.new(1, -16, 0.5, 0)
				TextLabel_1.Size = UDim2.new(0, 140, 0, 28)
				UIPadding_3.PaddingRight = UDim.new(0, 150)
			else
				TextLabel_1.Size = UDim2.new(1, 0, 0, 18)
				TextLabel_1.AutomaticSize = Enum.AutomaticSize.Y
			end

			local cardObj = {
				Background = Background,
				UIStroke = UIStroke_1,
				Title = TextLabel_2,
				Desc = TextLabel_1,
			}
			table.insert(currentWindowTheme.cards, cardObj)

			if i and i ~= "" then
				UIPadding_3.PaddingLeft = UDim.new(0, 42)
				local Icon_1 = Instance.new("ImageLabel")
				Icon_1.Name = "Icon"
				Icon_1.Parent = Background
				Icon_1.AnchorPoint = Vector2.new(0, 0.5)
				Icon_1.BackgroundTransparency = 1
				Icon_1.Position = UDim2.new(0, 12, 0.5, 0)
				Icon_1.Size = UDim2.new(0, 20, 0, 20)
				local iconData = gl(i)
				Icon_1.Image = iconData.Image
				Icon_1.ImageRectSize = iconData.ImageRectSize
				Icon_1.ImageRectOffset = iconData.ImageRectPosition
				Icon_1.ImageColor3 = curColors['Main']
				cardObj.Icon = Icon_1
			end

			local function updateSize()
				task.defer(function()
					local newSize = math.max(48, UIListLayout_2.AbsoluteContentSize.Y + 22)
					if Background.Size.Y.Offset ~= newSize then
						Background.Size = UDim2.new(1, 0, 0, newSize)
					end
				end)
			end

			task.delay(0.05, updateSize)
			UIListLayout_2:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSize)

			Background.MouseEnter:Connect(function()
				local c = currentWindowTheme.colors or curColors
				tw({v = Background, t = 0.15, g = {BackgroundColor3 = c['Card']:Lerp(c['Main'], 0.08)}}):Play()
				tw({v = UIStroke_1, t = 0.15, g = {Color = c['CardBorder']:Lerp(c['Main'], 0.4)}}):Play()
			end)
			Background.MouseLeave:Connect(function()
				local c = currentWindowTheme.colors or curColors
				tw({v = Background, t = 0.2, g = {BackgroundColor3 = c['Card']}}):Play()
				tw({v = UIStroke_1, t = 0.2, g = {Color = c['CardBorder']}}):Play()
			end)

			local f = {}
			function f:SetTextTransparencyTitle(vs)
				tw({v = TextLabel_2, t = 0.15, g = {TextTransparency = vs}}):Play()
				local icon = Background:FindFirstChild("Icon")
				if icon then tw({v = icon, t = 0.15, g = {ImageTransparency = vs}}):Play() end
			end
			function f:SetSizeT(vs) UIPadding_3.PaddingRight = UDim.new(0, vs) end
			function f:SetTitle(vs) TextLabel_2.Text = tostring(vs) end
			function f:SetDesc(vs)
				TextLabel_1.Text = tostring(vs)
				TextLabel_1.Visible = (vs and vs ~= "")
				updateSize()
			end
			return Background, f
		end

		function addDropdownSelect(p, p2, Multi, Callback, Value, List)
			local F = Instance.new("Frame")
			local UIListLayout_1 = Instance.new("UIListLayout")
			local UIPadding_1 = Instance.new("UIPadding")
			local DropdownValue = Instance.new("Frame")
			local UICorner_1 = Instance.new("UICorner")
			local UIStroke_1 = Instance.new("UIStroke")
			local TextLabelValue_1 = Instance.new("TextLabel")
			local UIPadding_2 = Instance.new("UIPadding")
			local ImageLabel_1 = Instance.new("ImageLabel")

			F.Name = "F"
			F.Parent = p
			F.AnchorPoint = Vector2.new(1, 0.5)
			F.BackgroundTransparency = 1
			F.BorderSizePixel = 0
			F.Position = UDim2.new(1, 0, 0.5, 0)
			F.Size = UDim2.new(0, 140, 0.85, 0)

			UIListLayout_1.Parent = F
			UIListLayout_1.HorizontalAlignment = Enum.HorizontalAlignment.Right
			UIListLayout_1.SortOrder = Enum.SortOrder.LayoutOrder
			UIListLayout_1.VerticalAlignment = Enum.VerticalAlignment.Center

			UIPadding_1.Parent = F
			UIPadding_1.PaddingRight = UDim.new(0, 12)

			local curColors = currentWindowTheme.colors
			DropdownValue.Parent = F
			DropdownValue.BackgroundColor3 = curColors['Function']['Dropdown']['Value Background']
			DropdownValue.BorderSizePixel = 0
			DropdownValue.Size = UDim2.new(0, 120, 0, 22)

			UICorner_1.CornerRadius = UDim.new(0, 4)
			UICorner_1.Parent = DropdownValue

			UIStroke_1.Color = curColors['Function']['Dropdown']['Value Stroke']
			UIStroke_1.Thickness = 1
			UIStroke_1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			UIStroke_1.Parent = DropdownValue

			TextLabelValue_1.Parent = DropdownValue
			TextLabelValue_1.BackgroundTransparency = 1
			TextLabelValue_1.BorderSizePixel = 0
			TextLabelValue_1.Size = UDim2.new(0.8, 0, 1, 0)
			TextLabelValue_1.Font = Enum.Font.BuilderSansMedium
			TextLabelValue_1.Text = "--"
			TextLabelValue_1.TextColor3 = curColors['Text & Icon']
			TextLabelValue_1.TextSize = 13
			TextLabelValue_1.TextXAlignment = Enum.TextXAlignment.Left
			TextLabelValue_1.TextTruncate = Enum.TextTruncate.AtEnd

			UIPadding_2.Parent = DropdownValue
			UIPadding_2.PaddingLeft = UDim.new(0, 8)
			UIPadding_2.PaddingRight = UDim.new(0, 5)

			ImageLabel_1.Parent = DropdownValue
			ImageLabel_1.AnchorPoint = Vector2.new(1, 0.5)
			ImageLabel_1.BackgroundTransparency = 1
			ImageLabel_1.BorderSizePixel = 0
			ImageLabel_1.Position = UDim2.new(1, 0, 0.5, 0)
			ImageLabel_1.Size = UDim2.new(0, 16, 0, 16)
			ImageLabel_1.Image = "rbxassetid://10709791437"
			ImageLabel_1.ImageColor3 = curColors['SubText']

			local DropdownSelect = Instance.new("Frame")
			local UICorner_2 = Instance.new("UICorner")
			local UIStrokeDropdown_1 = Instance.new("UIStroke")
			local UIPadding_3 = Instance.new("UIPadding")
			local Search_1 = Instance.new("Frame")
			local UICorner_3 = Instance.new("UICorner")
			local UIStrokeSearch = Instance.new("UIStroke")
			local TextBox_1 = Instance.new("TextBox")
			local ScrollingFrame_1 = Instance.new("ScrollingFrame")
			local UIListLayout_SF = Instance.new("UIListLayout")
			local UIPadding_SF = Instance.new("UIPadding")

			DropdownSelect.Parent = ScreenGui
			DropdownSelect.BackgroundColor3 = curColors['Card']
			DropdownSelect.BorderSizePixel = 0
			DropdownSelect.Size = UDim2.new(0, 150, 0, 0)
			DropdownSelect.ClipsDescendants = true
			DropdownSelect.Visible = false
			DropdownSelect.ZIndex = 60

			UICorner_2.CornerRadius = UDim.new(0, 6)
			UICorner_2.Parent = DropdownSelect

			UIStrokeDropdown_1.Color = Color3.fromRGB(70, 70, 80)
			UIStrokeDropdown_1.Thickness = 1
			UIStrokeDropdown_1.Parent = DropdownSelect

			UIPadding_3.Parent = DropdownSelect
			UIPadding_3.PaddingBottom = UDim.new(0, 6)
			UIPadding_3.PaddingLeft = UDim.new(0, 6)
			UIPadding_3.PaddingRight = UDim.new(0, 6)
			UIPadding_3.PaddingTop = UDim.new(0, 6)

			Search_1.Name = "Search"
			Search_1.Parent = DropdownSelect
			Search_1.BackgroundColor3 = curColors['Function']['Dropdown']['Dropdown Select']['Search']
			Search_1.BorderSizePixel = 0
			Search_1.Size = UDim2.new(1, 0, 0, 22)

			UICorner_3.CornerRadius = UDim.new(0, 4)
			UICorner_3.Parent = Search_1

			UIStrokeSearch.Color = curColors['CardBorder']
			UIStrokeSearch.Thickness = 1
			UIStrokeSearch.Parent = Search_1

			TextBox_1.Parent = Search_1
			TextBox_1.BackgroundTransparency = 1
			TextBox_1.BorderSizePixel = 0
			TextBox_1.Size = UDim2.new(1, -8, 1, 0)
			TextBox_1.Position = UDim2.new(0, 6, 0, 0)
			TextBox_1.Font = Enum.Font.BuilderSansMedium
			TextBox_1.PlaceholderColor3 = curColors['SubText']
			TextBox_1.PlaceholderText = "Search..."
			TextBox_1.Text = ""
			TextBox_1.TextColor3 = curColors['Text & Icon']
			TextBox_1.TextSize = 12
			TextBox_1.TextXAlignment = Enum.TextXAlignment.Left

			table.insert(currentWindowTheme.controls, {
				type = "dropdown",
				ValueBox = DropdownValue,
				Stroke = UIStroke_1,
				Text = TextLabelValue_1,
				Arrow = ImageLabel_1,
				Popup = DropdownSelect,
				Search = Search_1,
				SearchStroke = UIStrokeSearch,
				SearchInput = TextBox_1,
			})

			ScrollingFrame_1.Name = "ScrollingFrame"
			ScrollingFrame_1.Parent = DropdownSelect
			ScrollingFrame_1.Active = true
			ScrollingFrame_1.BackgroundTransparency = 1
			ScrollingFrame_1.BorderSizePixel = 0
			ScrollingFrame_1.Position = UDim2.new(0, 0, 0, 28)
			ScrollingFrame_1.Size = UDim2.new(1, 0, 1, -28)
			ScrollingFrame_1.ClipsDescendants = true
			ScrollingFrame_1.ScrollBarThickness = 2
			ScrollingFrame_1.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 200)

			UIListLayout_SF.Parent = ScrollingFrame_1
			UIListLayout_SF.SortOrder = Enum.SortOrder.LayoutOrder
			UIListLayout_SF.Padding = UDim.new(0, 3)

			UIPadding_SF.Parent = ScrollingFrame_1
			UIPadding_SF.PaddingRight = UDim.new(0, 4)

			local Click = click(p2)
			local isopen = false

			local function updateDropdownSize()
				if not isopen then return end
				local contentHeight = math.clamp(UIListLayout_SF.AbsoluteContentSize.Y + 40, 50, 180)
				tw({v = DropdownSelect, t = 0.15, g = {Size = UDim2.new(0, 150, 0, contentHeight)}}):Play()
			end

			TextBox_1.Changed:Connect(function()
				local search = string.lower(TextBox_1.Text)
				local hasSearch = (search ~= "")
				for _, v in ipairs(ScrollingFrame_1:GetChildren()) do
					if v:IsA("Frame") then
						local tl = v:FindFirstChild("TextLabel")
						if tl then
							v.Visible = not hasSearch or (string.find(string.lower(tl.Text), search, 1, true) ~= nil)
						end
					end
				end
				updateDropdownSize()
			end)

			local function open()
				if isopen then return end
				DropdownSelect.Visible = true
				local targetX = DropdownValue.AbsolutePosition.X - DropdownSelect.Parent.AbsolutePosition.X + DropdownValue.Size.X.Offset - 150
				local targetY = DropdownValue.AbsolutePosition.Y - DropdownSelect.Parent.AbsolutePosition.Y + DropdownValue.Size.Y.Offset + 4
				DropdownSelect.Position = UDim2.new(0, targetX, 0, targetY)

				local contentHeight = math.clamp(UIListLayout_SF.AbsoluteContentSize.Y + 40, 50, 180)
				tw({v = DropdownSelect, t = 0.15, g = {Size = UDim2.new(0, 150, 0, contentHeight)}}):Play()
				tw({v = ImageLabel_1, t = 0.15, g = {Rotation = 90}}):Play()
				isopen = true
			end

			local function close()
				if not isopen then return end
				tw({v = ImageLabel_1, t = 0.15, g = {Rotation = 0}}):Play()
				local gf = tw({v = DropdownSelect, t = 0.15, g = {Size = UDim2.new(0, 150, 0, 0)}})
				gf:Play()
				gf.Completed:Connect(function()
					DropdownSelect.Visible = false
					isopen = false
				end)
			end

			U.InputBegan:Connect(function(A)
				if (A.UserInputType == Enum.UserInputType.MouseButton1 or A.UserInputType == Enum.UserInputType.Touch) and isopen then
					local B, C = DropdownSelect.AbsolutePosition, DropdownSelect.AbsoluteSize
					local MousePos = LocalPlayer:GetMouse()
					if MousePos.X < B.X or MousePos.X > B.X + C.X or MousePos.Y < (DropdownValue.AbsolutePosition.Y) or MousePos.Y > B.Y + C.Y then
						close()
					end
				end
			end)

			Click.MouseButton1Click:Connect(function()
				if not isopen then open() else close() end
			end)

			local itemslist = {}
			local selectedValues = {}

			function itemslist:Clear()
				for _, v in ipairs(ScrollingFrame_1:GetChildren()) do
					if v:IsA("Frame") then v:Destroy() end
				end
				TextLabelValue_1.Text = "--"
				Value = nil
			end

			function itemslist:Add(text)
				local Item_1 = Instance.new("Frame")
				local TextLabel_1 = Instance.new("TextLabel")
				local ItemCorner = Instance.new("UICorner")

				Item_1.Name = "Item"
				Item_1.Parent = ScrollingFrame_1
				Item_1.BackgroundColor3 = curColors['Function']['Dropdown']['Dropdown Select']['Item Background']
				Item_1.BorderSizePixel = 0
				Item_1.Size = UDim2.new(1, 0, 0, 22)

				ItemCorner.CornerRadius = UDim.new(0, 4)
				ItemCorner.Parent = Item_1

				TextLabel_1.Parent = Item_1
				TextLabel_1.BackgroundTransparency = 1
				TextLabel_1.BorderSizePixel = 0
				TextLabel_1.Size = UDim2.new(1, -8, 1, 0)
				TextLabel_1.Position = UDim2.new(0, 6, 0, 0)
				TextLabel_1.Font = Enum.Font.BuilderSansMedium
				TextLabel_1.Text = tostring(text)
				TextLabel_1.TextColor3 = curColors['SubText']
				TextLabel_1.TextSize = 12
				TextLabel_1.TextXAlignment = Enum.TextXAlignment.Left

				local ClickItem = click(Item_1)

				local function unselect()
					tw({v = TextLabel_1, t = 0.12, g = {TextColor3 = curColors['SubText']}}):Play()
					tw({v = Item_1, t = 0.12, g = {BackgroundColor3 = curColors['Function']['Dropdown']['Dropdown Select']['Item Background']}}):Play()
				end

				local function hasselect()
					local c = currentWindowTheme.colors or curColors
					tw({v = TextLabel_1, t = 0.12, g = {TextColor3 = c['Background']}}):Play()
					tw({v = Item_1, t = 0.12, g = {BackgroundColor3 = c['Main']}}):Play()
				end

				ClickItem.MouseEnter:Connect(function()
					if (Multi and not selectedValues[text]) or (not Multi and Value ~= text) then
						local c = currentWindowTheme.colors or curColors
						local itemBg = (c['Function'] and c['Function']['Dropdown'] and c['Function']['Dropdown']['Dropdown Select'] and c['Function']['Dropdown']['Dropdown Select']['Item Background']) or c['Card']
						tw({v = Item_1, t = 0.12, g = {BackgroundColor3 = itemBg:Lerp(c['Main'], 0.1)}}):Play()
						tw({v = TextLabel_1, t = 0.12, g = {TextColor3 = c['Text & Icon']}}):Play()
					end
				end)

				ClickItem.MouseLeave:Connect(function()
					if (Multi and not selectedValues[text]) or (not Multi and Value ~= text) then
						local c = currentWindowTheme.colors or curColors
						local itemBg = (c['Function'] and c['Function']['Dropdown'] and c['Function']['Dropdown']['Dropdown Select'] and c['Function']['Dropdown']['Dropdown Select']['Item Background']) or c['Card']
						tw({v = Item_1, t = 0.15, g = {BackgroundColor3 = itemBg}}):Play()
						tw({v = TextLabel_1, t = 0.15, g = {TextColor3 = c['SubText']}}):Play()
					end
				end)

				ClickItem.MouseButton1Click:Connect(function()
					if Multi then
						if selectedValues[text] then
							selectedValues[text] = nil
							unselect()
						else
							selectedValues[text] = true
							hasselect()
						end
						local selectedList = {}
						for i, _ in pairs(selectedValues) do table.insert(selectedList, i) end
						TextLabelValue_1.Text = (#selectedList > 0) and table.concat(selectedList, ", ") or "--"
						pcall(Callback, selectedList)
					else
						local c = currentWindowTheme.colors or curColors
						local itemBg = (c['Function'] and c['Function']['Dropdown'] and c['Function']['Dropdown']['Dropdown Select'] and c['Function']['Dropdown']['Dropdown Select']['Item Background']) or c['Card']
						for _, v in pairs(ScrollingFrame_1:GetChildren()) do
							if v:IsA("Frame") then
								local tl = v:FindFirstChild("TextLabel")
								if tl then
									tw({v = tl, t = 0.12, g = {TextColor3 = c['SubText']}}):Play()
									tw({v = v, t = 0.12, g = {BackgroundColor3 = itemBg}}):Play()
								end
							end
						end
						hasselect()
						Value = text
						TextLabelValue_1.Text = text
						pcall(Callback, TextLabelValue_1.Text)
						close()
					end
				end)

				if not Multi and text == Value then
					hasselect()
					TextLabelValue_1.Text = text
				end
			end

			function itemslist:SetValue(value, skipCallback)
				if Multi then
					selectedValues = {}
					if type(value) == "table" then
						for _, val in ipairs(value) do selectedValues[val] = true end
					else
						selectedValues[value] = true
					end
					local selectedList = {}
					for k, _ in pairs(selectedValues) do table.insert(selectedList, k) end
					TextLabelValue_1.Text = (#selectedList > 0) and table.concat(selectedList, ", ") or "--"
					if not skipCallback then
						pcall(Callback, selectedList)
					end
				else
					Value = value
					TextLabelValue_1.Text = tostring(value)
					if not skipCallback then
						pcall(Callback, value)
					end
				end
			end

			function itemslist:GetValue()
				if Multi then
					local selectedList = {}
					for k, _ in pairs(selectedValues) do table.insert(selectedList, k) end
					return selectedList
				end
				return Value
			end

			for _, v in ipairs(List) do itemslist:Add(v) end
			changecanvas(ScrollingFrame_1, UIListLayout_SF, 5)
			return itemslist
		end
	end

	function Library:Window(p)
		if self ~= Library and type(p) ~= "table" and type(self) == "table" and (self.Title or self.Config or self.Theme) then
			p = self
		end
		p = p or {}
		local Title = p.Title or 'Aether'
		local Desc = p.Desc or 'Studios'
		local Theme = p.Theme or 'Default'
		local Keybind = (p.Config and p.Config.Keybind) or Enum.KeyCode.LeftControl
		local defaultSize = (p.Config and p.Config.Size) or UDim2.new(0, 840, 0, 480)
		local Size = defaultSize
		local savedW, savedH = FileSystem:LoadWindowSize()
		if savedW and savedH and not (p.Config and p.Config.IgnoreSavedSize) then
			Size = UDim2.new(0, savedW, 0, savedH)
		end
		local DiscordLink = p.DiscordLink or "https://discord.gg/getaether"

		currentWindowTheme.name = (themes[Theme] and Theme) or 'Default'
		currentWindowTheme.colors = deepCopy(themes[currentWindowTheme.name])
		currentWindowTheme.cards = {}
		currentWindowTheme.sections = {}
		currentWindowTheme.controls = {}
		currentWindowTheme.tabs = {}
		currentWindowTheme.topTabs = {}
		currentWindowTheme.subTabs = {}
		currentWindowTheme.transparency = {
			Window = 0,
			Sidebar = 0,
			Section = 0,
			Card = 0,
			RealBackground = 100
		}

		local curColors = currentWindowTheme.colors

		local Shadow_1 = Instance.new("ImageLabel")
		local Background_1 = Instance.new("Frame")
		local UICorner_1 = Instance.new("UICorner")
		local UIStroke_Win = Instance.new("UIStroke")

		Shadow_1.Name = "Shadow"
		Shadow_1.Image = "rbxassetid://1316045217"
		Shadow_1.ImageColor3 = Color3.fromRGB(0, 0, 0)
		Shadow_1.ScaleType = Enum.ScaleType.Slice
		Shadow_1.SliceCenter = Rect.new(10, 10, 118, 118)
		Shadow_1.ImageTransparency = 1
		Shadow_1.Parent = ScreenGui
		Shadow_1.AnchorPoint = Vector2.new(0.5, 0.5)
		Shadow_1.BackgroundColor3 = curColors['Background']
		Shadow_1.BackgroundTransparency = 1
		Shadow_1.Position = UDim2.new(0.5, 0, 0.5, 0)
		Shadow_1.Size = Size
		Shadow_1.Visible = true
		local WindowScale = attachAutoScale(Shadow_1, defaultSize.X.Offset, defaultSize.Y.Offset)

		local UIPadding_Shadow = Instance.new("UIPadding")
		UIPadding_Shadow.Parent = Shadow_1
		UIPadding_Shadow.PaddingBottom = UDim.new(0, 8)
		UIPadding_Shadow.PaddingLeft = UDim.new(0, 8)
		UIPadding_Shadow.PaddingRight = UDim.new(0, 8)
		UIPadding_Shadow.PaddingTop = UDim.new(0, 8)

		Background_1.Name = "Background"
		Background_1.Parent = Shadow_1
		Background_1.AnchorPoint = Vector2.new(0.5, 0.5)
		Background_1.BackgroundColor3 = curColors['Background']
		Background_1.BorderSizePixel = 0
		Background_1.Position = UDim2.new(0.5, 0, 0.5, 0)
		Background_1.Size = UDim2.new(1, 0, 1, 0)
		Background_1.ClipsDescendants = true

		UICorner_1.CornerRadius = UDim.new(0, 10)
		UICorner_1.Parent = Background_1

		UIStroke_Win.Color = curColors['CardBorder']
		UIStroke_Win.Thickness = 1.2
		UIStroke_Win.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		UIStroke_Win.Transparency = 1
		UIStroke_Win.Parent = Background_1

		local WindowBackgroundImg = Instance.new("ImageLabel")
		WindowBackgroundImg.Name = "WindowBackgroundImg"
		WindowBackgroundImg.Parent = Background_1
		WindowBackgroundImg.BackgroundTransparency = 1
		WindowBackgroundImg.Size = UDim2.new(1, 0, 1, 0)
		WindowBackgroundImg.ScaleType = Enum.ScaleType.Crop
		WindowBackgroundImg.ImageTransparency = 1
		WindowBackgroundImg.ZIndex = 1

		local WinBgCorner = Instance.new("UICorner")
		WinBgCorner.CornerRadius = UDim.new(0, 10)
		WinBgCorner.Parent = WindowBackgroundImg

		local WindowBackgroundDim = Instance.new("Frame")
		WindowBackgroundDim.Name = "WindowBackgroundDim"
		WindowBackgroundDim.Parent = Background_1
		WindowBackgroundDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		WindowBackgroundDim.BackgroundTransparency = 1
		WindowBackgroundDim.Size = UDim2.new(1, 0, 1, 0)
		WindowBackgroundDim.BorderSizePixel = 0
		WindowBackgroundDim.ZIndex = 2

		local WinDimCorner = Instance.new("UICorner")
		WinDimCorner.CornerRadius = UDim.new(0, 10)
		WinDimCorner.Parent = WindowBackgroundDim

		local ResizeHandle = Instance.new("ImageButton")
		local ResizeVisual = Instance.new("ImageLabel")

		ResizeHandle.Name = "ResizeHandle"
		ResizeHandle.Parent = Shadow_1
		ResizeHandle.AnchorPoint = Vector2.new(0.5, 0.5)
		ResizeHandle.Position = UDim2.new(1, 0, 1, 0)
		ResizeHandle.Size = UDim2.new(0, 32, 0, 32)
		ResizeHandle.BackgroundTransparency = 1
		ResizeHandle.BorderSizePixel = 0
		ResizeHandle.ZIndex = 80
		ResizeHandle.AutoButtonColor = false

		ResizeVisual.Name = "Visual"
		ResizeVisual.Parent = ResizeHandle
		ResizeVisual.AnchorPoint = Vector2.new(0.5, 0.5)
		ResizeVisual.Position = UDim2.new(0.5, 0, 0.5, 0)
		ResizeVisual.Size = UDim2.new(0, 16, 0, 16)
		ResizeVisual.BackgroundTransparency = 1
		ResizeVisual.BorderSizePixel = 0
		ResizeVisual.ZIndex = 81
		ResizeVisual.Rotation = 45

		local chevronIconData = gl("chevron-right")
		if chevronIconData then
			ResizeVisual.Image = chevronIconData.Image
			ResizeVisual.ImageRectSize = chevronIconData.ImageRectSize
			ResizeVisual.ImageRectOffset = chevronIconData.ImageRectPosition
		else
			ResizeVisual.Image = "rbxassetid://10709791437"
		end
		ResizeVisual.ImageColor3 = Color3.fromRGB(255, 255, 255)
		ResizeVisual.ImageTransparency = 0.4

		local Sidebar = nil
		local currentActiveWallpaper = ""
		local WallDropdown = nil
		local WallAssetInput = nil
		local WallTransSlider = nil
		local WallDimSlider = nil
		local ConfigElements = {}

		local BackgroundMusic = Instance.new("Sound")
		BackgroundMusic.Name = "AetherBackgroundMusic"
		BackgroundMusic.Parent = game:GetService("SoundService")
		BackgroundMusic.Volume = 0.5
		BackgroundMusic.Looped = true

		local ClickSound = Instance.new("Sound")
		ClickSound.Name = "AetherClickSound"
		ClickSound.Parent = game:GetService("SoundService")
		ClickSound.Volume = 0.6
		ClickSound.SoundId = "rbxassetid://6895079853"

		local currentSoundConfig = {
			BGMEnabled = false,
			BGMTrack = "None",
			BGMAsset = "",
			BGMVolume = 50,
			BGMLooped = true,
			ClickEnabled = true,
			ClickSound = "Modern Click",
			ClickAsset = "rbxassetid://6895079853",
			ClickVolume = 60
		}

		playClickSound = function()
			if currentSoundConfig and currentSoundConfig.ClickEnabled and ClickSound and ClickSound.SoundId ~= "" then
				pcall(function()
					SoundService:PlayLocalSound(ClickSound)
				end)
			end
		end

		local BGMToggle = nil
		local BGMTrackDropdown = nil
		local BGMAssetInput = nil
		local BGMVolumeSlider = nil
		local BGMLoopToggle = nil

		local function applySoundConfig(cfg)
			if not cfg or type(cfg) ~= "table" then return end
			if cfg.BGMEnabled ~= nil then
				currentSoundConfig.BGMEnabled = cfg.BGMEnabled
				if BGMToggle then BGMToggle:SetValue(cfg.BGMEnabled, true) end
			end

			local curAsset = cfg.BGMAsset or ""
			local curTrack = cfg.BGMTrack or "None"
			local isAssetId = tostring(curAsset):match("^%d+$") or tostring(curAsset):match("^rbxassetid://") or tostring(curAsset):match("^rbxasset://") or tostring(curAsset):match("^https?://")

			if curAsset ~= "" and isAssetId then
				if not curAsset:find("rbxassetid://") and tonumber(curAsset) then
					curAsset = "rbxassetid://" .. curAsset
				end
				currentSoundConfig.BGMAsset = curAsset
				currentSoundConfig.BGMTrack = "None"
				if BGMTrackDropdown then BGMTrackDropdown:SetValue("None", true) end
				if BGMAssetInput then BGMAssetInput:SetValue(curAsset, true) end
			elseif curTrack and curTrack ~= "" and curTrack ~= "None" then
				currentSoundConfig.BGMTrack = curTrack
				currentSoundConfig.BGMAsset = ""
				if BGMTrackDropdown then BGMTrackDropdown:SetValue(curTrack, true) end
				if BGMAssetInput then BGMAssetInput:SetValue("", true) end
			else
				currentSoundConfig.BGMTrack = curTrack
				currentSoundConfig.BGMAsset = curAsset
				if BGMTrackDropdown then BGMTrackDropdown:SetValue(curTrack, true) end
				if BGMAssetInput then BGMAssetInput:SetValue(curAsset, true) end
			end

			if cfg.BGMVolume ~= nil then
				currentSoundConfig.BGMVolume = math.clamp(tonumber(cfg.BGMVolume) or 50, 0, 100)
				BackgroundMusic.Volume = currentSoundConfig.BGMVolume / 100
				if BGMVolumeSlider then BGMVolumeSlider:SetValue(currentSoundConfig.BGMVolume, true) end
			end
			if cfg.BGMLooped ~= nil then
				currentSoundConfig.BGMLooped = cfg.BGMLooped
				BackgroundMusic.Looped = cfg.BGMLooped
				if BGMLoopToggle then BGMLoopToggle:SetValue(cfg.BGMLooped, true) end
			end

			local bgmAssetToPlay = ""
			if currentSoundConfig.BGMAsset and currentSoundConfig.BGMAsset ~= "" then
				bgmAssetToPlay = FileSystem:GetAudioAsset(currentSoundConfig.BGMAsset)
			elseif currentSoundConfig.BGMTrack and currentSoundConfig.BGMTrack ~= "None" then
				local presetMap = {
					["Lofi Chill"] = "rbxassetid://9043887091",
					["Ambient Dream"] = "rbxassetid://1843404009"
				}
				bgmAssetToPlay = presetMap[currentSoundConfig.BGMTrack] or FileSystem:GetAudioAsset(currentSoundConfig.BGMTrack)
			end

			if bgmAssetToPlay and bgmAssetToPlay ~= "" then
				if BackgroundMusic.SoundId ~= bgmAssetToPlay then
					BackgroundMusic.SoundId = bgmAssetToPlay
				end
				if currentSoundConfig.BGMEnabled then
					pcall(function() BackgroundMusic:Play() end)
				else
					pcall(function() BackgroundMusic:Stop() end)
				end
			else
				pcall(function() BackgroundMusic:Stop() end)
			end
		end

		local currentCursorConfig = {
			Enabled = false,
			Preset = "Default (Roblox)",
			CustomAsset = ""
		}

		local CursorToggle = nil
		local CursorPresetDropdown = nil
		local CursorAssetInput = nil

		local isUpdatingCursorUI = false
		local function applyCursorConfig(cfg)
			if not cfg or type(cfg) ~= "table" then return end
			if isUpdatingCursorUI then return end
			isUpdatingCursorUI = true

			if cfg.Enabled ~= nil then
				currentCursorConfig.Enabled = cfg.Enabled
				if CursorToggle then CursorToggle:SetValue(cfg.Enabled, true) end
			end

			local curAsset = cfg.CustomAsset or ""
			local curPreset = cfg.Preset or "Default (Roblox)"
			local isAssetId = tostring(curAsset):match("^%d+$") or tostring(curAsset):match("^rbxassetid://") or tostring(curAsset):match("^rbxasset://") or tostring(curAsset):match("^https?://")

			if curAsset ~= "" and isAssetId then
				if not curAsset:find("rbxassetid://") and tonumber(curAsset) then
					curAsset = "rbxassetid://" .. curAsset
				end
				currentCursorConfig.CustomAsset = curAsset
				currentCursorConfig.Preset = "None"
				if CursorPresetDropdown then CursorPresetDropdown:SetValue("None", true) end
				if CursorAssetInput then CursorAssetInput:SetValue(curAsset, true) end
			elseif curPreset and curPreset ~= "" and curPreset ~= "None" and curPreset ~= "Default (Roblox)" then
				currentCursorConfig.Preset = curPreset
				currentCursorConfig.CustomAsset = ""
				if CursorPresetDropdown then CursorPresetDropdown:SetValue(curPreset, true) end
				if CursorAssetInput then CursorAssetInput:SetValue("", true) end
			else
				currentCursorConfig.Preset = curPreset
				currentCursorConfig.CustomAsset = curAsset
				if CursorPresetDropdown then CursorPresetDropdown:SetValue(curPreset, true) end
				if CursorAssetInput then CursorAssetInput:SetValue(curAsset, true) end
			end

			local mouse = LocalPlayer and LocalPlayer:GetMouse()
			if mouse then
				if not currentCursorConfig.Enabled then
					pcall(function() mouse.Icon = "" end)
				else
					local assetToApply = ""
					if currentCursorConfig.CustomAsset and currentCursorConfig.CustomAsset ~= "" then
						assetToApply = FileSystem:GetCursorAsset(currentCursorConfig.CustomAsset)
					elseif currentCursorConfig.Preset and currentCursorConfig.Preset ~= "Default (Roblox)" and currentCursorConfig.Preset ~= "None" then
						local presetMap = {
							["Crosshair (Clean)"] = "rbxasset://textures/Cursors/CrossKeyboard.png",
							["Arrow (Far)"] = "rbxasset://textures/ArrowFarCursor.png",
							["Pointer (Sleek)"] = "rbxasset://textures/ArrowCursor.png",
						}
						assetToApply = presetMap[currentCursorConfig.Preset] or FileSystem:GetCursorAsset(currentCursorConfig.Preset)
					end

					pcall(function()
						mouse.Icon = assetToApply or ""
					end)
				end
			end

			isUpdatingCursorUI = false
		end

		local TransPresetDropdown = nil
		local SidebarTransSlider = nil
		local SectionTransSlider = nil
		local CardTransSlider = nil
		local WindowTransSlider = nil
		local skipPresetReset = false

		local function getPresetNameForValues(w, s, sec, c)
			if w == 0 and s == 0 and sec == 0 and c == 0 then
				return "Solid (Default)"
			elseif w == 15 and s == 20 and sec == 25 and c == 20 then
				return "Frosted Glass"
			elseif w == 35 and s == 40 and sec == 45 and c == 35 then
				return "Translucent"
			elseif w == 60 and s == 65 and sec == 70 and c == 55 then
				return "Ultra Clear"
			else
				return "Custom"
			end
		end

		local function setSidebarTransparency(val)
			val = math.clamp(tonumber(val) or 0, 0, 100)
			currentWindowTheme.transparency.Sidebar = val
			if Sidebar and Sidebar.Parent then
				Sidebar.BackgroundTransparency = val / 100
			end
		end

		local function setSectionTransparency(val)
			val = math.clamp(tonumber(val) or 0, 0, 100)
			currentWindowTheme.transparency.Section = val
			for _, sec in ipairs(currentWindowTheme.sections or {}) do
				if sec.Frame and sec.Frame.Parent then
					sec.Frame.BackgroundTransparency = val / 100
				end
			end
		end

		local function setCardTransparency(val)
			val = math.clamp(tonumber(val) or 0, 0, 100)
			currentWindowTheme.transparency.Card = val
			for _, card in ipairs(currentWindowTheme.cards or {}) do
				if card.Background and card.Background.Parent then
					card.Background.BackgroundTransparency = val / 100
				end
			end
		end

		local function setWindowTransparency(val)
			val = math.clamp(tonumber(val) or 0, 0, 100)
			currentWindowTheme.transparency.Window = val
			if Background_1 and Background_1.Parent then
				Background_1.BackgroundTransparency = val / 100
			end
		end

		local function applyAllTransparencies(windowT, sidebarT, sectionT, cardT)
			local w, s, sec, c
			if type(windowT) == "table" then
				w = windowT.Window or 0
				s = windowT.Sidebar or 0
				sec = windowT.Section or 0
				c = windowT.Card or 0
			else
				w = windowT or 0
				s = sidebarT or 0
				sec = sectionT or 0
				c = cardT or 0
			end

			skipPresetReset = true
			setWindowTransparency(w)
			setSidebarTransparency(s)
			setSectionTransparency(sec)
			setCardTransparency(c)

			if WindowTransSlider then WindowTransSlider:SetValue(w, true) end
			if SidebarTransSlider then SidebarTransSlider:SetValue(s, true) end
			if SectionTransSlider then SectionTransSlider:SetValue(sec, true) end
			if CardTransSlider then CardTransSlider:SetValue(c, true) end

			if TransPresetDropdown then
				local matchedPreset = getPresetNameForValues(w, s, sec, c)
				TransPresetDropdown:SetValue(matchedPreset, true)
			end
			skipPresetReset = false
		end

		local ReopenBtn = Instance.new("CanvasGroup")
		local ReopenCorner = Instance.new("UICorner")
		local ReopenStroke = Instance.new("UIStroke")
		local ReopenContent = Instance.new("Frame")
		local ReopenLayout = Instance.new("UIListLayout")
		local ReopenPadding = Instance.new("UIPadding")

		local ReopenOnlineDot = Instance.new("Frame")
		local ReopenOnlineDotCorner = Instance.new("UICorner")

		local ReopenPlayerLabel = Instance.new("TextLabel")
		local ReopenDiv1 = Instance.new("Frame")
		local ReopenStats = Instance.new("TextLabel")
		local ReopenDiv2 = Instance.new("Frame")

		local ReopenKeyBadge = Instance.new("Frame")
		local ReopenKeyCorner = Instance.new("UICorner")
		local ReopenKeyStroke = Instance.new("UIStroke")
		local ReopenKeybind = Instance.new("TextLabel")

		local ReopenClick = Instance.new("TextButton")

		ReopenBtn.Name = "ReopenButton"
		ReopenBtn.Parent = ScreenGui
		ReopenBtn.AnchorPoint = Vector2.new(0.5, 0)
		ReopenBtn.Position = UDim2.new(0.5, 0, 0, 14)
		ReopenBtn.Size = UDim2.new(0, 0, 0, 32)
		ReopenBtn.AutomaticSize = Enum.AutomaticSize.X
		ReopenBtn.BackgroundColor3 = curColors['Card']
		ReopenBtn.BorderSizePixel = 0
		ReopenBtn.GroupTransparency = 1
		ReopenBtn.Visible = false
		ReopenBtn.ZIndex = 100
		ReopenBtn.ClipsDescendants = true

		ReopenCorner.CornerRadius = UDim.new(0, 8)
		ReopenCorner.Parent = ReopenBtn

		ReopenStroke.Color = curColors['CardBorder']
		ReopenStroke.Thickness = 1.2
		ReopenStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ReopenStroke.Transparency = 1
		ReopenStroke.Parent = ReopenBtn

		ReopenContent.Name = "Content"
		ReopenContent.Parent = ReopenBtn
		ReopenContent.BackgroundTransparency = 1
		ReopenContent.Size = UDim2.new(0, 0, 1, 0)
		ReopenContent.AutomaticSize = Enum.AutomaticSize.X

		ReopenLayout.Parent = ReopenContent
		ReopenLayout.FillDirection = Enum.FillDirection.Horizontal
		ReopenLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ReopenLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		ReopenLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ReopenLayout.Padding = UDim.new(0, 9)

		ReopenPadding.Parent = ReopenContent
		ReopenPadding.PaddingLeft = UDim.new(0, 12)
		ReopenPadding.PaddingRight = UDim.new(0, 12)

		ReopenOnlineDot.Name = "StatusDot"
		ReopenOnlineDot.Parent = ReopenContent
		ReopenOnlineDot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		ReopenOnlineDot.BorderSizePixel = 0
		ReopenOnlineDot.Size = UDim2.new(0, 7, 0, 7)
		ReopenOnlineDot.LayoutOrder = 1

		ReopenOnlineDotCorner.CornerRadius = UDim.new(1, 0)
		ReopenOnlineDotCorner.Parent = ReopenOnlineDot

		local initialPlayerName = (LocalPlayer and (LocalPlayer.DisplayName or LocalPlayer.Name)) or "Player"
		ReopenPlayerLabel.Name = "PlayerName"
		ReopenPlayerLabel.Parent = ReopenContent
		ReopenPlayerLabel.BackgroundTransparency = 1
		ReopenPlayerLabel.Size = UDim2.new(0, 0, 0, 18)
		ReopenPlayerLabel.AutomaticSize = Enum.AutomaticSize.X
		ReopenPlayerLabel.Font = Enum.Font.BuilderSansBold
		ReopenPlayerLabel.Text = initialPlayerName
		ReopenPlayerLabel.TextColor3 = curColors['Text & Icon']
		ReopenPlayerLabel.TextSize = 13
		ReopenPlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
		ReopenPlayerLabel.TextTruncate = Enum.TextTruncate.None
		ReopenPlayerLabel.LayoutOrder = 2

		ReopenDiv1.Name = "Div1"
		ReopenDiv1.Parent = ReopenContent
		ReopenDiv1.BackgroundColor3 = curColors['CardBorder']
		ReopenDiv1.BorderSizePixel = 0
		ReopenDiv1.Size = UDim2.new(0, 1, 0, 13)
		ReopenDiv1.LayoutOrder = 3

		ReopenStats.Name = "Stats"
		ReopenStats.Parent = ReopenContent
		ReopenStats.BackgroundTransparency = 1
		ReopenStats.Size = UDim2.new(0, 0, 0, 18)
		ReopenStats.AutomaticSize = Enum.AutomaticSize.X
		ReopenStats.Font = Enum.Font.BuilderSansMedium
		ReopenStats.RichText = true
		ReopenStats.Text = '<font color="rgb(34,197,94)"><b>60</b></font> <font color="rgb(150,150,165)">FPS</font> <font color="rgb(70,70,85)">•</font> <font color="rgb(255,255,255)"><b>0</b></font> <font color="rgb(150,150,165)">ms</font>'
		ReopenStats.TextSize = 12
		ReopenStats.TextXAlignment = Enum.TextXAlignment.Center
		ReopenStats.LayoutOrder = 4

		ReopenDiv2.Name = "Div2"
		ReopenDiv2.Parent = ReopenContent
		ReopenDiv2.BackgroundColor3 = curColors['CardBorder']
		ReopenDiv2.BorderSizePixel = 0
		ReopenDiv2.Size = UDim2.new(0, 1, 0, 13)
		ReopenDiv2.LayoutOrder = 5

		local initKeyName = (Keybind and Keybind.Name) or "LeftCtrl"
		if initKeyName == "LeftControl" then initKeyName = "LeftCtrl" end
		if initKeyName == "RightControl" then initKeyName = "RightCtrl" end

		ReopenKeyBadge.Name = "KeyBadge"
		ReopenKeyBadge.Parent = ReopenContent
		ReopenKeyBadge.BackgroundColor3 = curColors['Background']:Lerp(curColors['Card'], 0.5)
		ReopenKeyBadge.BorderSizePixel = 0
		ReopenKeyBadge.Size = UDim2.new(0, 0, 0, 20)
		ReopenKeyBadge.AutomaticSize = Enum.AutomaticSize.X
		ReopenKeyBadge.LayoutOrder = 6

		ReopenKeyCorner.CornerRadius = UDim.new(0, 5)
		ReopenKeyCorner.Parent = ReopenKeyBadge

		ReopenKeyStroke.Color = curColors['CardBorder']
		ReopenKeyStroke.Thickness = 1
		ReopenKeyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ReopenKeyStroke.Parent = ReopenKeyBadge

		local ReopenKeyPadding = Instance.new("UIPadding")
		ReopenKeyPadding.Parent = ReopenKeyBadge
		ReopenKeyPadding.PaddingLeft = UDim.new(0, 6)
		ReopenKeyPadding.PaddingRight = UDim.new(0, 6)

		ReopenKeybind.Name = "KeyHint"
		ReopenKeybind.Parent = ReopenKeyBadge
		ReopenKeybind.BackgroundTransparency = 1
		ReopenKeybind.Size = UDim2.new(0, 0, 1, 0)
		ReopenKeybind.AutomaticSize = Enum.AutomaticSize.X
		ReopenKeybind.Font = Enum.Font.BuilderSansBold
		ReopenKeybind.Text = "[" .. initKeyName .. "]"
		ReopenKeybind.TextColor3 = curColors['Main']
		ReopenKeybind.TextSize = 11
		ReopenKeybind.TextXAlignment = Enum.TextXAlignment.Center

		ReopenClick.Name = "Click"
		ReopenClick.Parent = ReopenBtn
		ReopenClick.BackgroundTransparency = 1
		ReopenClick.Size = UDim2.new(1, 0, 1, 0)
		ReopenClick.Text = ""
		ReopenClick.ZIndex = 25

		local isHidden = false
		local function setUIVisibility(visible)
			isHidden = not visible
			if isHidden then
				tw({v = UIStroke_Win, t = 0.12, g = {Transparency = 1}}):Play()
				tw({v = Shadow_1, t = 0.12, g = {ImageTransparency = 1}}):Play()
				if ResizeVisual then
					tw({v = ResizeVisual, t = 0.12, g = {ImageTransparency = 1}}):Play()
				end
				tw({v = Background_1, t = 0.12, s = Enum.EasingStyle.Quad, d = "In", g = {Size = UDim2.new(1, -12, 1, -12)}}):Play()
				task.delay(0.12, function()
					if isHidden then
						Shadow_1.Visible = false
						Background_1.Visible = false
						Background_1.Size = UDim2.new(1, 0, 1, 0)
					end
				end)
				ReopenBtn.Visible = true
				ReopenBtn.GroupTransparency = 1
				ReopenStroke.Transparency = 1
				tw({v = ReopenBtn, t = 0.22, s = Enum.EasingStyle.Back, d = "Out", g = {GroupTransparency = 0}}):Play()
				tw({v = ReopenStroke, t = 0.22, s = Enum.EasingStyle.Back, d = "Out", g = {Transparency = 0}}):Play()
			else
				tw({v = ReopenBtn, t = 0.12, g = {GroupTransparency = 1}}):Play()
				tw({v = ReopenStroke, t = 0.12, g = {Transparency = 1}}):Play()
				task.delay(0.12, function()
					if not isHidden then
						ReopenBtn.Visible = false
						ReopenStroke.Transparency = 1
					end
				end)
				Shadow_1.Visible = true
				Background_1.Visible = true
				Background_1.Size = UDim2.new(1, -12, 1, -12)
				UIStroke_Win.Transparency = 1
				Shadow_1.ImageTransparency = 1
				tw({v = Background_1, t = 0.16, s = Enum.EasingStyle.Back, d = "Out", g = {Size = UDim2.new(1, 0, 1, 0)}}):Play()
				tw({v = UIStroke_Win, t = 0.16, g = {Transparency = 0}}):Play()
				tw({v = Shadow_1, t = 0.16, g = {ImageTransparency = 0.5}}):Play()
				if ResizeVisual then
					tw({v = ResizeVisual, t = 0.16, g = {ImageTransparency = 0.4}}):Play()
				end
			end
		end

		ReopenClick.MouseEnter:Connect(function()
			local c = currentWindowTheme.colors or curColors
			tw({v = ReopenStroke, t = 0.15, g = {Color = c['Main']}}):Play()
			tw({v = ReopenBtn, t = 0.15, g = {BackgroundColor3 = c['Card']:Lerp(c['Main'], 0.08)}}):Play()
			tw({v = ReopenKeyStroke, t = 0.15, g = {Color = c['Main']}}):Play()
		end)
		ReopenClick.MouseLeave:Connect(function()
			local c = currentWindowTheme.colors or curColors
			tw({v = ReopenStroke, t = 0.15, g = {Color = c['CardBorder']}}):Play()
			tw({v = ReopenBtn, t = 0.15, g = {BackgroundColor3 = c['Card']}}):Play()
			tw({v = ReopenKeyStroke, t = 0.15, g = {Color = c['CardBorder']}}):Play()
		end)

		local fpsVal = 60
		local pingVal = 0
		local fpsFrames = 0
		local fpsLastTime = tick()

		local RunService = Session:Service("RunService")
		local StatsService = game:GetService("Stats")

		RunService.RenderStepped:Connect(function()
			fpsFrames = fpsFrames + 1
			local curTime = tick()
			if curTime - fpsLastTime >= 0.5 then
				fpsVal = math.round(fpsFrames / (curTime - fpsLastTime))
				fpsFrames = 0
				fpsLastTime = curTime
			end
		end)

		task.spawn(function()
			while ScreenGui and ScreenGui.Parent do
				pcall(function()
					local netItem = StatsService and StatsService.Network and StatsService.Network.ServerStatsItem and StatsService.Network.ServerStatsItem["Data Ping"]
					if netItem then
						pingVal = math.round(netItem:GetValue())
					end
				end)
				if ReopenStats and ReopenStats.Parent then
					local fpsColor = (fpsVal >= 50 and "rgb(34,197,94)") or (fpsVal >= 30 and "rgb(234,179,8)") or "rgb(239,68,68)"
					ReopenStats.Text = string.format(
						'<font color="%s"><b>%d</b></font> <font color="rgb(150,150,165)">FPS</font> <font color="rgb(70,70,85)">•</font> <font color="rgb(255,255,255)"><b>%d</b></font> <font color="rgb(150,150,165)">ms</font>',
						fpsColor,
						fpsVal,
						pingVal
					)
				end
				task.wait(0.5)
			end
		end)

		do
			local isDragging = false
			local dragStart = nil
			local startPos = nil
			local hasMoved = false

			local function startDrag(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					isDragging = true
					hasMoved = false
					dragStart = input.Position
					startPos = ReopenBtn.Position
				end
			end

			ReopenBtn.InputBegan:Connect(startDrag)
			ReopenClick.InputBegan:Connect(startDrag)

			U.InputChanged:Connect(function(input)
				if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					local delta = input.Position - dragStart
					if math.abs(delta.X) > 3 or math.abs(delta.Y) > 3 then
						hasMoved = true
					end
					ReopenBtn.Position = UDim2.new(
						startPos.X.Scale,
						startPos.X.Offset + delta.X,
						startPos.Y.Scale,
						startPos.Y.Offset + delta.Y
					)
				end
			end)

			U.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					isDragging = false
				end
			end)

			ReopenClick.MouseButton1Click:Connect(function()
				if not hasMoved then
					playClickSound()
					setUIVisibility(true)
				end
			end)
		end

		local org = Background_1.Size
		Background_1.Size = org - UDim2.fromOffset(6, 6)
		tw({
			v = Background_1,
			t = 0.22,
			s = Enum.EasingStyle.Quad,
			d = "Out",
			g = { Size = org }
		}):Play()
		tw({
			v = UIStroke_Win,
			t = 0.22,
			s = Enum.EasingStyle.Quad,
			d = "Out",
			g = { Transparency = 0 }
		}):Play()
		tw({
			v = Shadow_1,
			t = 0.22,
			s = Enum.EasingStyle.Quad,
			d = "Out",
			g = { ImageTransparency = 0.5 }
		}):Play()

		Sidebar = Instance.new("Frame")
		local SidebarBorder = Instance.new("Frame")
		local SidebarCorner = Instance.new("UICorner")
		local SidebarSquareFiller = Instance.new("Frame")

		Sidebar.Name = "Sidebar"
		Sidebar.Parent = Background_1
		Sidebar.BackgroundColor3 = curColors['Sidebar']
		Sidebar.BackgroundTransparency = (currentWindowTheme.transparency and currentWindowTheme.transparency.Sidebar or 0) / 100
		Sidebar.BorderSizePixel = 0
		Sidebar.Size = UDim2.new(0, 165, 1, 0)
		Sidebar.ZIndex = 5

		SidebarCorner.CornerRadius = UDim.new(0, 10)
		SidebarCorner.Parent = Sidebar

		SidebarSquareFiller.Name = "SquareFiller"
		SidebarSquareFiller.Parent = Sidebar
		SidebarSquareFiller.BackgroundColor3 = curColors['Sidebar']
		SidebarSquareFiller.BackgroundTransparency = (currentWindowTheme.transparency and currentWindowTheme.transparency.Sidebar or 0) / 100
		SidebarSquareFiller.BorderSizePixel = 0
		SidebarSquareFiller.Position = UDim2.new(1, -12, 0, 0)
		SidebarSquareFiller.Size = UDim2.new(0, 12, 1, 0)
		SidebarSquareFiller.ZIndex = 5

		SidebarBorder.Name = "SidebarBorder"
		SidebarBorder.Parent = Background_1
		SidebarBorder.BackgroundColor3 = curColors['CardBorder']
		SidebarBorder.BorderSizePixel = 0
		SidebarBorder.Position = UDim2.new(0, 165, 0, 0)
		SidebarBorder.Size = UDim2.new(0, 1, 1, 0)
		SidebarBorder.ZIndex = 6

		local LogoFrame = Instance.new("Frame")
		local LogoLayout = Instance.new("UIListLayout")
		local LogoTitle = Instance.new("TextLabel")
		local LogoSub = Instance.new("TextLabel")

		LogoFrame.Name = "LogoFrame"
		LogoFrame.Parent = Sidebar
		LogoFrame.BackgroundTransparency = 1
		LogoFrame.Position = UDim2.new(0, 16, 0, 14)
		LogoFrame.Size = UDim2.new(1, -24, 0, 24)

		LogoLayout.Parent = LogoFrame
		LogoLayout.FillDirection = Enum.FillDirection.Horizontal
		LogoLayout.SortOrder = Enum.SortOrder.LayoutOrder
		LogoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		LogoLayout.Padding = UDim.new(0, 5)

		LogoTitle.Name = "LogoTitle"
		LogoTitle.Parent = LogoFrame
		LogoTitle.BackgroundTransparency = 1
		LogoTitle.Size = UDim2.new(0, 0, 1, 0)
		LogoTitle.AutomaticSize = Enum.AutomaticSize.X
		LogoTitle.Font = Enum.Font.BuilderSansBold
		LogoTitle.Text = tostring(Title)
		LogoTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		LogoTitle.TextSize = 17
		LogoTitle.TextXAlignment = Enum.TextXAlignment.Left
		LogoTitle.LayoutOrder = 1

		LogoSub.Name = "LogoSub"
		LogoSub.Parent = LogoFrame
		LogoSub.BackgroundTransparency = 1
		LogoSub.Size = UDim2.new(0, 0, 1, 0)
		LogoSub.AutomaticSize = Enum.AutomaticSize.X
		LogoSub.Font = Enum.Font.BuilderSansBold
		LogoSub.Text = tostring(Desc)
		LogoSub.TextColor3 = (currentWindowTheme.name == "Default") and Color3.fromRGB(255, 255, 255) or curColors['Main']
		LogoSub.TextSize = 17
		LogoSub.TextXAlignment = Enum.TextXAlignment.Left
		LogoSub.LayoutOrder = 2

		local TabListFrame = Instance.new("ScrollingFrame")
		local TabListLayout = Instance.new("UIListLayout")
		local TabListPadding = Instance.new("UIPadding")

		TabListFrame.Name = "TabList"
		TabListFrame.Parent = Sidebar
		TabListFrame.BackgroundTransparency = 1
		TabListFrame.BorderSizePixel = 0
		TabListFrame.Position = UDim2.new(0, 0, 0, 48)
		TabListFrame.Size = UDim2.new(1, 0, 1, -96)
		TabListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		TabListFrame.ScrollBarThickness = 0
		TabListFrame.ClipsDescendants = true

		TabListLayout.Parent = TabListFrame
		TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		TabListLayout.Padding = UDim.new(0, 5)

		TabListPadding.Parent = TabListFrame
		TabListPadding.PaddingLeft = UDim.new(0, 10)
		TabListPadding.PaddingRight = UDim.new(0, 10)
		TabListPadding.PaddingTop = UDim.new(0, 4)

		changecanvas(TabListFrame, TabListLayout, 5)

		local SubInfoFrame = Instance.new("Frame")
		local SubInfoLayout = Instance.new("UIListLayout")
		local SubTierLabelSidebar = Instance.new("TextLabel")
		local SubExpiresLabelSidebar = Instance.new("TextLabel")

		SubInfoFrame.Name = "SubscriptionInfo"
		SubInfoFrame.Parent = Sidebar
		SubInfoFrame.BackgroundTransparency = 1
		SubInfoFrame.Position = UDim2.new(0, 16, 1, -56)
		SubInfoFrame.Size = UDim2.new(1, -24, 0, 48)

		SubInfoLayout.Parent = SubInfoFrame
		SubInfoLayout.SortOrder = Enum.SortOrder.LayoutOrder
		SubInfoLayout.Padding = UDim.new(0, 4)
		SubInfoLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

		SubTierLabelSidebar.Name = "SubscriptionTier"
		SubTierLabelSidebar.Parent = SubInfoFrame
		SubTierLabelSidebar.BackgroundTransparency = 1
		SubTierLabelSidebar.Size = UDim2.new(1, 0, 0, 18)
		SubTierLabelSidebar.Font = Enum.Font.BuilderSansMedium
		SubTierLabelSidebar.RichText = true
		SubTierLabelSidebar.Text = '<font color="rgb(180,180,195)">Subscription: </font><font color="rgb(255,255,255)"><b>Free</b></font>'
		SubTierLabelSidebar.TextSize = 13
		SubTierLabelSidebar.TextXAlignment = Enum.TextXAlignment.Left
		SubTierLabelSidebar.LayoutOrder = 1

		SubExpiresLabelSidebar.Name = "SubscriptionExpires"
		SubExpiresLabelSidebar.Parent = SubInfoFrame
		SubExpiresLabelSidebar.BackgroundTransparency = 1
		SubExpiresLabelSidebar.Size = UDim2.new(1, 0, 0, 18)
		SubExpiresLabelSidebar.Font = Enum.Font.BuilderSansMedium
		SubExpiresLabelSidebar.RichText = true
		SubExpiresLabelSidebar.Text = '<font color="rgb(180,180,195)">Expires at: </font><font color="rgb(255,255,255)">0 seconds</font>'
		SubExpiresLabelSidebar.TextSize = 13
		SubExpiresLabelSidebar.TextXAlignment = Enum.TextXAlignment.Left
		SubExpiresLabelSidebar.LayoutOrder = 2

		local Topbar = Instance.new("Frame")
		Topbar.Name = "Topbar"
		Topbar.Parent = Background_1
		Topbar.BackgroundTransparency = 1
		Topbar.Position = UDim2.new(0, 165, 0, 0)
		Topbar.Size = UDim2.new(1, -165, 0, 48)
		Topbar.ZIndex = 50

		lak(Topbar, Shadow_1)

		local isResizingWindow = false
		local resizeDragStart = nil
		local resizeStartSize = nil
		local resizeStartPos = nil
		local resizeActiveInput = nil
		local autoSaveSize = true

		ResizeHandle.MouseEnter:Connect(function()
			if not isResizingWindow then
				tw({v = ResizeVisual, t = 0.15, g = {ImageTransparency = 0.15}}):Play()
			end
		end)

		ResizeHandle.MouseLeave:Connect(function()
			if not isResizingWindow then
				tw({v = ResizeVisual, t = 0.15, g = {ImageTransparency = 0.4}}):Play()
			end
		end)

		local function startResizeWindow(input)
			isResizingWindow = true
			resizeActiveInput = input
			resizeDragStart = input.Position
			resizeStartSize = Vector2.new(Shadow_1.Size.X.Offset, Shadow_1.Size.Y.Offset)
			resizeStartPos = Shadow_1.Position
			tw({v = ResizeVisual, t = 0.12, g = {ImageTransparency = 0, Size = UDim2.new(0, 19, 0, 19)}}):Play()
		end

		ResizeHandle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				startResizeWindow(input)
			end
		end)

		local resizeInputChangedConn = U.InputChanged:Connect(function(input)
			if isResizingWindow then
				if input.UserInputType == Enum.UserInputType.MouseMovement or (input.UserInputType == Enum.UserInputType.Touch and (resizeActiveInput == nil or input == resizeActiveInput)) then
					local k = WindowScale.Scale
					local delta = (input.Position - resizeDragStart) / k
					local camera = workspace.CurrentCamera
					local vp = (camera and camera.ViewportSize or Vector2.new(1920, 1080)) / k
					local minW, minH = 460, 280
					local maxW = math.max(minW, vp.X - 16)
					local maxH = math.max(minH, vp.Y - 16)

					local newW = math.clamp(math.round(resizeStartSize.X + delta.X), minW, maxW)
					local newH = math.clamp(math.round(resizeStartSize.Y + delta.Y), minH, maxH)

					local deltaW = newW - resizeStartSize.X
					local deltaH = newH - resizeStartSize.Y

					Shadow_1.Size = UDim2.new(0, newW, 0, newH)
					Shadow_1.Position = UDim2.new(
						resizeStartPos.X.Scale,
						resizeStartPos.X.Offset + (deltaW * k / 2),
						resizeStartPos.Y.Scale,
						resizeStartPos.Y.Offset + (deltaH * k / 2)
					)
				end
			end
		end)

		local resizeInputEndedConn = U.InputEnded:Connect(function(input)
			if isResizingWindow then
				if input.UserInputType == Enum.UserInputType.MouseButton1 or (input.UserInputType == Enum.UserInputType.Touch and (resizeActiveInput == nil or input == resizeActiveInput)) then
					isResizingWindow = false
					resizeActiveInput = nil
					tw({v = ResizeVisual, t = 0.18, g = {ImageTransparency = 0.4, Size = UDim2.new(0, 16, 0, 16)}}):Play()
					if autoSaveSize then
						local curW = Shadow_1.Size.X.Offset
						local curH = Shadow_1.Size.Y.Offset
						FileSystem:SaveWindowSize(curW, curH)
					end
				end
			end
		end)

		local WindowControls = Instance.new("Frame")
		local WinLayout = Instance.new("UIListLayout")
		local Minisize_1 = Instance.new("ImageButton")
		local Close_1 = Instance.new("ImageButton")

		WindowControls.Name = "WindowControls"
		WindowControls.Parent = Topbar
		WindowControls.AnchorPoint = Vector2.new(1, 0.5)
		WindowControls.BackgroundTransparency = 1
		WindowControls.Position = UDim2.new(1, -12, 0.5, 0)
		WindowControls.Size = UDim2.new(0, 56, 0, 26)

		WinLayout.Parent = WindowControls
		WinLayout.FillDirection = Enum.FillDirection.Horizontal
		WinLayout.SortOrder = Enum.SortOrder.LayoutOrder
		WinLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		WinLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		WinLayout.Padding = UDim.new(0, 12)

		Minisize_1.Name = "Minimize"
		Minisize_1.Parent = WindowControls
		Minisize_1.BackgroundTransparency = 1
		Minisize_1.Size = UDim2.new(0, 18, 0, 18)
		Minisize_1.Image = "rbxassetid://10734896206"
		Minisize_1.ImageColor3 = curColors['SubText']

		Close_1.Name = "Close"
		Close_1.Parent = WindowControls
		Close_1.BackgroundTransparency = 1
		Close_1.Size = UDim2.new(0, 18, 0, 18)
		Close_1.Image = "rbxassetid://15082305656"
		Close_1.ImageColor3 = curColors['SubText']

		Minisize_1.MouseEnter:Connect(function() tw({v = Minisize_1, t = 0.15, g = {ImageColor3 = Color3.fromRGB(255, 255, 255)}}):Play() end)
		Minisize_1.MouseLeave:Connect(function()
			local c = currentWindowTheme.colors or curColors
			tw({v = Minisize_1, t = 0.15, g = {ImageColor3 = c['SubText']}}):Play()
		end)

		Close_1.MouseEnter:Connect(function() tw({v = Close_1, t = 0.15, g = {ImageColor3 = Color3.fromRGB(255, 70, 70)}}):Play() end)
		Close_1.MouseLeave:Connect(function()
			local c = currentWindowTheme.colors or curColors
			tw({v = Close_1, t = 0.15, g = {ImageColor3 = c['SubText']}}):Play()
		end)

		local FeaturesRegistry = {}

		local function registerFeature(title, cType, frame, meta)
			if not title or title == "" then return end
			table.insert(FeaturesRegistry, {
				Title = tostring(title),
				Type = cType or "Feature",
				Frame = frame,
				TabTitle = (meta and meta.TabTitle) or "Home",
				SubTabTitle = meta and meta.SubTabTitle,
				SelectTab = meta and meta.SelectTab,
				SelectSubTab = meta and meta.SelectSubTab,
				Scroll = meta and meta.Scroll
			})
		end

		local SearchFrame = Instance.new("Frame")
		local SearchCorner = Instance.new("UICorner")
		local SearchStroke = Instance.new("UIStroke")
		local SearchIcon = Instance.new("ImageLabel")
		local SearchBox = Instance.new("TextBox")
		local ClearSearchBtn = Instance.new("ImageButton")

		SearchFrame.Name = "SearchFrame"
		SearchFrame.Parent = Topbar
		SearchFrame.AnchorPoint = Vector2.new(1, 0.5)
		SearchFrame.Position = UDim2.new(1, -78, 0.5, 0)
		SearchFrame.Size = UDim2.new(0, 195, 0, 28)
		SearchFrame.BackgroundColor3 = curColors['Card']
		SearchFrame.BorderSizePixel = 0

		SearchCorner.CornerRadius = UDim.new(0, 6)
		SearchCorner.Parent = SearchFrame

		SearchStroke.Color = curColors['CardBorder']
		SearchStroke.Thickness = 1
		SearchStroke.Parent = SearchFrame

		SearchIcon.Name = "Icon"
		SearchIcon.Parent = SearchFrame
		SearchIcon.AnchorPoint = Vector2.new(0, 0.5)
		SearchIcon.BackgroundTransparency = 1
		SearchIcon.Position = UDim2.new(0, 8, 0.5, 0)
		SearchIcon.Size = UDim2.new(0, 14, 0, 14)
		SearchIcon.Image = "rbxassetid://10734883986"
		SearchIcon.ImageColor3 = curColors['SubText']

		SearchBox.Name = "Box"
		SearchBox.Parent = SearchFrame
		SearchBox.BackgroundTransparency = 1
		SearchBox.Position = UDim2.new(0, 28, 0, 0)
		SearchBox.Size = UDim2.new(1, -50, 1, 0)
		SearchBox.Font = Enum.Font.BuilderSansMedium
		SearchBox.PlaceholderText = "Search features..."
		SearchBox.PlaceholderColor3 = curColors['SubText']
		SearchBox.Text = ""
		SearchBox.TextColor3 = curColors['Text & Icon']
		SearchBox.TextSize = 13
		SearchBox.TextXAlignment = Enum.TextXAlignment.Left
		SearchBox.ClearTextOnFocus = false

		ClearSearchBtn.Name = "Clear"
		ClearSearchBtn.Parent = SearchFrame
		ClearSearchBtn.AnchorPoint = Vector2.new(1, 0.5)
		ClearSearchBtn.BackgroundTransparency = 1
		ClearSearchBtn.Position = UDim2.new(1, -7, 0.5, 0)
		ClearSearchBtn.Size = UDim2.new(0, 12, 0, 12)
		ClearSearchBtn.Image = "rbxassetid://15082305656"
		ClearSearchBtn.ImageColor3 = curColors['SubText']
		ClearSearchBtn.Visible = false

		local SearchDropdown = Instance.new("Frame")
		local DropCorner = Instance.new("UICorner")
		local DropStroke = Instance.new("UIStroke")
		local DropScroll = Instance.new("ScrollingFrame")
		local DropLayout = Instance.new("UIListLayout")
		local DropPadding = Instance.new("UIPadding")

		SearchDropdown.Name = "SearchDropdown"
		SearchDropdown.Parent = Topbar
		SearchDropdown.AnchorPoint = Vector2.new(1, 0)
		SearchDropdown.Position = UDim2.new(1, -66, 0.5, 18)
		SearchDropdown.Size = UDim2.new(0, 245, 0, 0)
		SearchDropdown.BackgroundColor3 = curColors['Card']
		SearchDropdown.BorderSizePixel = 0
		SearchDropdown.Visible = false
		SearchDropdown.ZIndex = 150
		SearchDropdown.ClipsDescendants = true

		DropCorner.CornerRadius = UDim.new(0, 8)
		DropCorner.Parent = SearchDropdown

		DropStroke.Color = curColors['CardBorder']
		DropStroke.Thickness = 1
		DropStroke.Parent = SearchDropdown

		DropScroll.Name = "Scroll"
		DropScroll.Parent = SearchDropdown
		DropScroll.BackgroundTransparency = 1
		DropScroll.BorderSizePixel = 0
		DropScroll.Size = UDim2.new(1, 0, 1, 0)
		DropScroll.ScrollBarThickness = 2
		DropScroll.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 160)
		DropScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		DropScroll.ZIndex = 151

		DropLayout.Parent = DropScroll
		DropLayout.SortOrder = Enum.SortOrder.LayoutOrder
		DropLayout.Padding = UDim.new(0, 3)

		DropPadding.Parent = DropScroll
		DropPadding.PaddingTop = UDim.new(0, 4)
		DropPadding.PaddingBottom = UDim.new(0, 4)
		DropPadding.PaddingLeft = UDim.new(0, 4)
		DropPadding.PaddingRight = UDim.new(0, 4)

		local function updateSearch(queryText)
			local q = queryText:lower():match("^%s*(.-)%s*$")
			for _, child in ipairs(DropScroll:GetChildren()) do
				if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
					child:Destroy()
				end
			end

			if not q or q == "" then
				SearchDropdown.Visible = false
				ClearSearchBtn.Visible = false
				return
			end

			ClearSearchBtn.Visible = true

			local qClean = q:gsub("[%s%-%_]", "")
			local matches = {}
			for _, feat in ipairs(FeaturesRegistry) do
				local tLower = feat.Title:lower()
				local tClean = tLower:gsub("[%s%-%_]", "")
				local typeLower = feat.Type:lower()
				local tabLower = feat.TabTitle:lower()
				local subLower = feat.SubTabTitle and feat.SubTabTitle:lower() or ""

				if tLower:find(q, 1, true) or (qClean ~= "" and tClean:find(qClean, 1, true)) then
					local isPrefix = (tLower:sub(1, #q) == q) or (qClean ~= "" and tClean:sub(1, #qClean) == qClean)
					table.insert(matches, { feat = feat, score = (isPrefix and 1 or 2) })
				elseif subLower:find(q, 1, true) or tabLower:find(q, 1, true) or typeLower:find(q, 1, true) then
					table.insert(matches, { feat = feat, score = 3 })
				end
			end

			table.sort(matches, function(a, b) return a.score < b.score end)

			if #matches == 0 then
				local emptyLabel = Instance.new("TextLabel")
				emptyLabel.Name = "Empty"
				emptyLabel.Parent = DropScroll
				emptyLabel.BackgroundTransparency = 1
				emptyLabel.Size = UDim2.new(1, 0, 0, 36)
				emptyLabel.Font = Enum.Font.BuilderSansMedium
				emptyLabel.Text = "No features found for '" .. queryText .. "'"
				emptyLabel.TextColor3 = curColors['SubText']
				emptyLabel.TextSize = 13
				emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
				emptyLabel.ZIndex = 152

				SearchDropdown.Size = UDim2.new(0, 245, 0, 44)
				SearchDropdown.Visible = true
				DropScroll.CanvasSize = UDim2.new(0, 0, 0, 44)
				return
			end

			local maxVisible = math.min(#matches, 6)
			SearchDropdown.Size = UDim2.new(0, 245, 0, maxVisible * 42 + 8)
			SearchDropdown.Visible = true
			DropScroll.CanvasSize = UDim2.new(0, 0, 0, #matches * 42 + 8)

			for i, m in ipairs(matches) do
				local feat = m.feat
				local itemBtn = Instance.new("TextButton")
				local itemCorner = Instance.new("UICorner")
				local itemPadding = Instance.new("UIPadding")
				local itemTitle = Instance.new("TextLabel")
				local itemLoc = Instance.new("TextLabel")
				local itemBadge = Instance.new("Frame")
				local badgeCorner = Instance.new("UICorner")
				local badgeStroke = Instance.new("UIStroke")
				local badgeLabel = Instance.new("TextLabel")

				itemBtn.Name = "Result_" .. i
				itemBtn.Parent = DropScroll
				itemBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
				itemBtn.BackgroundTransparency = 1
				itemBtn.BorderSizePixel = 0
				itemBtn.Size = UDim2.new(1, 0, 0, 38)
				itemBtn.AutoButtonColor = false
				itemBtn.Text = ""
				itemBtn.ZIndex = 152

				itemCorner.CornerRadius = UDim.new(0, 6)
				itemCorner.Parent = itemBtn

				itemPadding.Parent = itemBtn
				itemPadding.PaddingLeft = UDim.new(0, 8)
				itemPadding.PaddingRight = UDim.new(0, 8)

				itemTitle.Name = "Title"
				itemTitle.Parent = itemBtn
				itemTitle.BackgroundTransparency = 1
				itemTitle.Position = UDim2.new(0, 0, 0, 4)
				itemTitle.Size = UDim2.new(1, -65, 0, 16)
				itemTitle.Font = Enum.Font.BuilderSansBold
				itemTitle.Text = feat.Title
				itemTitle.TextColor3 = curColors['Text & Icon']
				itemTitle.TextSize = 13
				itemTitle.TextXAlignment = Enum.TextXAlignment.Left
				itemTitle.TextTruncate = Enum.TextTruncate.AtEnd
				itemTitle.ZIndex = 153

				local locStr = feat.TabTitle .. (feat.SubTabTitle and (" › " .. feat.SubTabTitle) or "")
				itemLoc.Name = "Loc"
				itemLoc.Parent = itemBtn
				itemLoc.BackgroundTransparency = 1
				itemLoc.Position = UDim2.new(0, 0, 0, 20)
				itemLoc.Size = UDim2.new(1, -65, 0, 14)
				itemLoc.Font = Enum.Font.BuilderSansMedium
				itemLoc.Text = locStr
				itemLoc.TextColor3 = curColors['SubText']
				itemLoc.TextSize = 12
				itemLoc.TextXAlignment = Enum.TextXAlignment.Left
				itemLoc.ZIndex = 153

				itemBadge.Name = "Badge"
				itemBadge.Parent = itemBtn
				itemBadge.AnchorPoint = Vector2.new(1, 0.5)
				itemBadge.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
				itemBadge.BorderSizePixel = 0
				itemBadge.Position = UDim2.new(1, 0, 0.5, 0)
				itemBadge.Size = UDim2.new(0, 58, 0, 18)
				itemBadge.ZIndex = 153

				badgeCorner.CornerRadius = UDim.new(0, 4)
				badgeCorner.Parent = itemBadge

				badgeStroke.Color = curColors['CardBorder']
				badgeStroke.Thickness = 1
				badgeStroke.Parent = itemBadge

				badgeLabel.Name = "Label"
				badgeLabel.Parent = itemBadge
				badgeLabel.BackgroundTransparency = 1
				badgeLabel.Size = UDim2.new(1, 0, 1, 0)
				badgeLabel.Font = Enum.Font.BuilderSansBold
				badgeLabel.Text = feat.Type:upper()
				badgeLabel.TextColor3 = curColors['SubText']
				badgeLabel.TextSize = 11
				badgeLabel.ZIndex = 154

				itemBtn.MouseEnter:Connect(function()
					local c = currentWindowTheme.colors or curColors
					tw({v = itemBtn, t = 0.12, g = {BackgroundTransparency = 0, BackgroundColor3 = c['Card']:Lerp(c['Main'], 0.08)}}):Play()
					tw({v = badgeLabel, t = 0.12, g = {TextColor3 = c['Main']}}):Play()
				end)
				itemBtn.MouseLeave:Connect(function()
					local c = currentWindowTheme.colors or curColors
					tw({v = itemBtn, t = 0.12, g = {BackgroundTransparency = 1}}):Play()
					tw({v = badgeLabel, t = 0.12, g = {TextColor3 = c['SubText']}}):Play()
				end)

				itemBtn.MouseButton1Click:Connect(function()
					SearchDropdown.Visible = false
					SearchBox.Text = ""
					ClearSearchBtn.Visible = false
					SearchBox:ReleaseFocus()

					if feat.SelectTab then feat.SelectTab() end
					if feat.SelectSubTab then feat.SelectSubTab() end

					if feat.Frame then
						local p = feat.Frame
						while p and p ~= feat.Scroll and p ~= game do
							if p:IsA("Frame") and p.Name:sub(1, 8) == "Section_" then
								for _, sec in ipairs(currentWindowTheme.sections or {}) do
									if sec.Frame == p and sec.IsMinimized and sec.IsMinimized() then
										sec.SetMinimized(false)
									end
								end
								break
							end
							p = p.Parent
						end
					end

					if feat.Scroll and feat.Frame then
						task.defer(function()
							pcall(function()
								local targetY = feat.Frame.AbsolutePosition.Y - feat.Scroll.AbsolutePosition.Y + feat.Scroll.CanvasPosition.Y - 20
								feat.Scroll.CanvasPosition = Vector2.new(0, math.clamp(targetY, 0, feat.Scroll.AbsoluteCanvasSize.Y))
								local stroke = feat.Frame:FindFirstChildOfClass("UIStroke")
								if stroke then
									local prevCol = stroke.Color
									tw({v = stroke, t = 0.2, g = {Color = Color3.fromRGB(255, 255, 255)}}):Play()
									task.delay(0.7, function()
										tw({v = stroke, t = 0.4, g = {Color = prevCol}}):Play()
									end)
								end
							end)
						end)
					end
				end)
			end
		end

		SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
			updateSearch(SearchBox.Text)
		end)

		ClearSearchBtn.MouseButton1Click:Connect(function()
			SearchBox.Text = ""
			updateSearch("")
		end)

		U.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if SearchDropdown.Visible then
					local mPos = input.Position
					local sfPos = SearchFrame.AbsolutePosition
					local sfSize = SearchFrame.AbsoluteSize
					local sdPos = SearchDropdown.AbsolutePosition
					local sdSize = SearchDropdown.AbsoluteSize

					local inSF = (mPos.X >= sfPos.X and mPos.X <= sfPos.X + sfSize.X and mPos.Y >= sfPos.Y and mPos.Y <= sfPos.Y + sfSize.Y)
					local inSD = (mPos.X >= sdPos.X and mPos.X <= sdPos.X + sdSize.X and mPos.Y >= sdPos.Y and mPos.Y <= sdPos.Y + sdSize.Y)

					if not inSF and not inSD then
						SearchDropdown.Visible = false
					end
				end
			end
		end)

		local Page_1 = Instance.new("Frame")
		Page_1.Name = "Page"
		Page_1.Parent = Background_1
		Page_1.BackgroundColor3 = curColors['Page']
		Page_1.BackgroundTransparency = 1
		Page_1.BorderSizePixel = 0
		Page_1.Position = UDim2.new(0, 165, 0, 48)
		Page_1.Size = UDim2.new(1, -165, 1, -48)
		Page_1.ZIndex = 5

		local PagePadding = Instance.new("UIPadding")
		PagePadding.Parent = Page_1
		PagePadding.PaddingBottom = UDim.new(0, 8)
		PagePadding.PaddingLeft = UDim.new(0, 14)
		PagePadding.PaddingRight = UDim.new(0, 14)
		PagePadding.PaddingTop = UDim.new(0, 2)

		local Tabs = {
			List = {},
			DefaultIndex = 1,
			UIToggleKeybind = Keybind,
			ShowReopenPill = true,
			ActiveTabName = "Home",
			StreamerMode = false,
			SubscriptionTier = "Free",
			SubscriptionExpires = "0 seconds",
		}

		function Tabs:SaveWindowSize()
			local curW = Shadow_1.Size.X.Offset
			local curH = Shadow_1.Size.Y.Offset
			FileSystem:SaveWindowSize(curW, curH)
			Tabs:Notify({
				Title = "Window Size Saved",
				Desc = string.format("Default size locked to %d x %d", curW, curH),
				Time = 2.5
			})
		end

		function Tabs:ResetWindowSize()
			FileSystem:ResetWindowSize()
			local defW = defaultSize.X.Offset
			local defH = defaultSize.Y.Offset
			local curW = Shadow_1.Size.X.Offset
			local curH = Shadow_1.Size.Y.Offset
			local deltaW = defW - curW
			local deltaH = defH - curH
			local curPos = Shadow_1.Position

			tw({
				v = Shadow_1,
				t = 0.25,
				s = Enum.EasingStyle.Quad,
				d = "Out",
				g = {
					Size = defaultSize,
					Position = UDim2.new(
						curPos.X.Scale,
						curPos.X.Offset + (deltaW / 2),
						curPos.Y.Scale,
						curPos.Y.Offset + (deltaH / 2)
					)
				}
			}):Play()

			Tabs:Notify({
				Title = "Window Size Reset",
				Desc = string.format("Restored default size (%d x %d)", defW, defH),
				Time = 2.5
			})
		end

		function Tabs:SetWindowSize(w, h, save)
			local curW = Shadow_1.Size.X.Offset
			local curH = Shadow_1.Size.Y.Offset
			local deltaW = w - curW
			local deltaH = h - curH
			local curPos = Shadow_1.Position

			Shadow_1.Size = UDim2.new(0, w, 0, h)
			Shadow_1.Position = UDim2.new(
				curPos.X.Scale,
				curPos.X.Offset + (deltaW / 2),
				curPos.Y.Scale,
				curPos.Y.Offset + (deltaH / 2)
			)

			if save then
				FileSystem:SaveWindowSize(w, h)
			end
		end

		function Tabs:GetWindowSize()
			return Shadow_1.Size.X.Offset, Shadow_1.Size.Y.Offset
		end

		function Tabs:ApplyTheme(themeNameOrColors)
			local tCols
			if type(themeNameOrColors) == "string" and themes[themeNameOrColors] then
				currentWindowTheme.name = themeNameOrColors
				currentWindowTheme.colors = deepCopy(themes[themeNameOrColors])
				tCols = currentWindowTheme.colors
			elseif type(themeNameOrColors) == "table" then
				currentWindowTheme.name = "Custom"
				local newCols = deepCopy(currentWindowTheme.colors or themes.Default)
				for k, v in pairs(themeNameOrColors) do
					newCols[k] = v
				end
				if themeNameOrColors.Background then
					newCols.Page = themeNameOrColors.Background
					newCols.Sidebar = themeNameOrColors.Background
				end
				if themeNameOrColors.Main then
					local m = themeNameOrColors.Main
					newCols.MainDark = Color3.fromRGB(math.floor(m.R * 40), math.floor(m.G * 40), math.floor(m.B * 40))
					newCols.MainLight = Color3.fromRGB(math.min(255, math.floor(m.R * 255 + 25)), math.min(255, math.floor(m.G * 255 + 25)), math.min(255, math.floor(m.G * 255 + 25)))
				end
				currentWindowTheme.colors = newCols
				tCols = currentWindowTheme.colors
			else
				tCols = currentWindowTheme.colors
			end

			curColors = tCols

			tw({v = Background_1, t = 0.2, g = {BackgroundColor3 = tCols['Background']}}):Play()
			tw({v = UIStroke_Win, t = 0.2, g = {Color = tCols['CardBorder']}}):Play()
			tw({v = Sidebar, t = 0.2, g = {BackgroundColor3 = tCols['Sidebar']}}):Play()
			tw({v = SidebarBorder, t = 0.2, g = {BackgroundColor3 = tCols['CardBorder']}}):Play()
			tw({v = ReopenBtn, t = 0.2, g = {BackgroundColor3 = tCols['Card']}}):Play()
			tw({v = ReopenStroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play()
			if ReopenPlayerLabel and ReopenPlayerLabel.Parent then tw({v = ReopenPlayerLabel, t = 0.2, g = {TextColor3 = tCols['Text & Icon']}}):Play() end
			if ReopenDiv1 and ReopenDiv1.Parent then tw({v = ReopenDiv1, t = 0.2, g = {BackgroundColor3 = tCols['CardBorder']}}):Play() end
			if ReopenDiv2 and ReopenDiv2.Parent then tw({v = ReopenDiv2, t = 0.2, g = {BackgroundColor3 = tCols['CardBorder']}}):Play() end
			if ReopenKeyBadge and ReopenKeyBadge.Parent then tw({v = ReopenKeyBadge, t = 0.2, g = {BackgroundColor3 = tCols['Background']:Lerp(tCols['Card'], 0.5)}}):Play() end
			if ReopenKeyStroke and ReopenKeyStroke.Parent then tw({v = ReopenKeyStroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play() end
			if ReopenKeybind and ReopenKeybind.Parent then tw({v = ReopenKeybind, t = 0.2, g = {TextColor3 = tCols['Main']}}):Play() end

			if LogoSub and LogoSub.Parent then
				local subColor = (currentWindowTheme.name == "Default") and Color3.fromRGB(255, 255, 255) or tCols['Main']
				tw({v = LogoSub, t = 0.2, g = {TextColor3 = subColor}}):Play()
			end

			for _, item in ipairs(self.List) do
				local isActive = (item.Page and item.Page.Visible)
				if isActive then
					tw({v = item.Button, t = 0.18, g = {BackgroundColor3 = tCols['MainDark'], BackgroundTransparency = 0}}):Play()
					tw({v = item.Icon, t = 0.18, g = {ImageColor3 = tCols['Main']}}):Play()
					tw({v = item.TitleLabel, t = 0.18, g = {TextColor3 = tCols['Text & Icon']}}):Play()
				else
					tw({v = item.Button, t = 0.18, g = {BackgroundTransparency = 1}}):Play()
					tw({v = item.Icon, t = 0.18, g = {ImageColor3 = tCols['SubText']}}):Play()
					tw({v = item.TitleLabel, t = 0.18, g = {TextColor3 = tCols['SubText']}}):Play()
				end
			end

			for _, card in ipairs(currentWindowTheme.cards) do
				if card.Background and card.Background.Parent then
					tw({v = card.Background, t = 0.2, g = {BackgroundColor3 = tCols['Card']}}):Play()
					tw({v = card.UIStroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play()
					if card.Title then tw({v = card.Title, t = 0.2, g = {TextColor3 = tCols['Text & Icon']}}):Play() end
					if card.Desc then tw({v = card.Desc, t = 0.2, g = {TextColor3 = tCols['SubText']}}):Play() end
					if card.Icon then tw({v = card.Icon, t = 0.2, g = {ImageColor3 = tCols['Main']}}):Play() end
				end
			end

			for _, sec in ipairs(currentWindowTheme.sections or {}) do
				if sec.Frame and sec.Frame.Parent then
					tw({v = sec.Frame, t = 0.2, g = {BackgroundColor3 = tCols['Background']:Lerp(tCols['Card'], 0.35)}}):Play()
					if sec.Stroke then tw({v = sec.Stroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play() end
					if sec.Title then tw({v = sec.Title, t = 0.2, g = {TextColor3 = tCols['SubText']}}):Play() end
					if sec.Indicator then tw({v = sec.Indicator, t = 0.2, g = {BackgroundColor3 = tCols['Main']}}):Play() end
					if sec.MinBtn then tw({v = sec.MinBtn, t = 0.2, g = {ImageColor3 = tCols['SubText']}}):Play() end
				end
			end

			for _, st in ipairs(currentWindowTheme.subTabs or {}) do
				if st.Button and st.Button.Parent then
					if st.IsActive then
						tw({v = st.Button, t = 0.2, g = {BackgroundColor3 = tCols['Main']}}):Play()
						tw({v = st.Label, t = 0.2, g = {TextColor3 = tCols['Background']}}):Play()
						tw({v = st.Stroke, t = 0.2, g = {Color = tCols['Main']}}):Play()
					else
						tw({v = st.Button, t = 0.2, g = {BackgroundColor3 = tCols['Card']}}):Play()
						tw({v = st.Label, t = 0.2, g = {TextColor3 = tCols['SubText']}}):Play()
						tw({v = st.Stroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play()
					end
				end
			end

			for _, ctrl in ipairs(currentWindowTheme.controls or {}) do
				if ctrl.type == "dropdown" then
					if ctrl.ValueBox and ctrl.ValueBox.Parent then
						local bgCol = tCols['Function'] and tCols['Function']['Dropdown'] and tCols['Function']['Dropdown']['Value Background'] or tCols['Card']
						tw({v = ctrl.ValueBox, t = 0.2, g = {BackgroundColor3 = bgCol}}):Play()
					end
					if ctrl.Stroke and ctrl.Stroke.Parent then
						local strokeCol = tCols['Function'] and tCols['Function']['Dropdown'] and tCols['Function']['Dropdown']['Value Stroke'] or tCols['CardBorder']
						tw({v = ctrl.Stroke, t = 0.2, g = {Color = strokeCol}}):Play()
					end
					if ctrl.Popup and ctrl.Popup.Parent then
						tw({v = ctrl.Popup, t = 0.2, g = {BackgroundColor3 = tCols['Card']}}):Play()
					end
					if ctrl.Search and ctrl.Search.Parent then
						tw({v = ctrl.Search, t = 0.2, g = {BackgroundColor3 = tCols['Background']}}):Play()
					end
				elseif ctrl.type == "toggle" then
					if ctrl.GetValue and ctrl.GetValue() then
						if ctrl.Frame_1 and ctrl.Frame_1.Parent then
							tw({v = ctrl.Frame_1, t = 0.2, g = {BackgroundColor3 = tCols['Main']}}):Play()
						end
					end
				elseif ctrl.type == "textbox" or ctrl.type == "keybind" or ctrl.type == "slider_value" then
					if ctrl.Box and ctrl.Box.Parent then
						local bgCol = tCols['Function'] and tCols['Function']['Dropdown'] and tCols['Function']['Dropdown']['Value Background'] or tCols['Card']
						tw({v = ctrl.Box, t = 0.2, g = {BackgroundColor3 = bgCol}}):Play()
					end
					if ctrl.Stroke and ctrl.Stroke.Parent then
						local strokeCol = tCols['Function'] and tCols['Function']['Dropdown'] and tCols['Function']['Dropdown']['Value Stroke'] or tCols['CardBorder']
						tw({v = ctrl.Stroke, t = 0.2, g = {Color = strokeCol}}):Play()
					end
				end
			end

			if SearchFrame and SearchFrame.Parent then
				tw({v = SearchFrame, t = 0.2, g = {BackgroundColor3 = tCols['Card']}}):Play()
				tw({v = SearchStroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play()
				tw({v = SearchIcon, t = 0.2, g = {ImageColor3 = tCols['SubText']}}):Play()
				tw({v = ClearSearchBtn, t = 0.2, g = {ImageColor3 = tCols['SubText']}}):Play()
				tw({v = SearchBox, t = 0.2, g = {TextColor3 = tCols['Text & Icon'], PlaceholderColor3 = tCols['SubText']}}):Play()
				tw({v = SearchDropdown, t = 0.2, g = {BackgroundColor3 = tCols['Card']}}):Play()
				tw({v = DropStroke, t = 0.2, g = {Color = tCols['CardBorder']}}):Play()
			end
		end

		function Tabs:SetSubscription(tier, expires)
			tier = tier or Tabs.SubscriptionTier or "Free"
			expires = expires or Tabs.SubscriptionExpires or "0 seconds"
			Tabs.SubscriptionTier = tier
			Tabs.SubscriptionExpires = expires

			local tierText = string.format('<font color="rgb(180,180,195)">Subscription: </font><font color="rgb(255,255,255)"><b>%s</b></font>', tostring(tier))
			local expText = string.format('<font color="rgb(180,180,195)">Expires at: </font><font color="rgb(255,255,255)">%s</font>', tostring(expires))

			if SubTierLabelSidebar and SubTierLabelSidebar.Parent then SubTierLabelSidebar.Text = tierText end
			if SubExpiresLabelSidebar and SubExpiresLabelSidebar.Parent then SubExpiresLabelSidebar.Text = expText end
			if Tabs._subTierHero and Tabs._subTierHero.Parent then Tabs._subTierHero.Text = tierText end
			if Tabs._subExpiresHero and Tabs._subExpiresHero.Parent then Tabs._subExpiresHero.Text = expText end
		end

		Tabs._reopenPlayerLabel = ReopenPlayerLabel
		Tabs._reopenKeybind = ReopenKeybind
		Tabs._streamerToggles = {}

		function Tabs:SetStreamerMode(enabled)
			Tabs.StreamerMode = enabled
			local displayName = (LocalPlayer and LocalPlayer.DisplayName) or "Player"
			local realName = (LocalPlayer and LocalPlayer.Name) or "Player"
			local uid = (LocalPlayer and tostring(LocalPlayer.UserId)) or "78439201"

			if enabled then
				if Tabs._playerTitle and Tabs._playerTitle.Parent then Tabs._playerTitle.Text = "Welcome 👋" end
				if Tabs._profileName and Tabs._profileName.Parent then Tabs._profileName.Text = "Protected" end
				if Tabs._reopenPlayerLabel and Tabs._reopenPlayerLabel.Parent then Tabs._reopenPlayerLabel.Text = "Protected" end
				if Tabs._avatarImg and Tabs._avatarImg.Parent then Tabs._avatarImg.Image = "rbxassetid://10747373176" end
			else
				if Tabs._playerTitle and Tabs._playerTitle.Parent then Tabs._playerTitle.Text = displayName .. " 👋" end
				if Tabs._profileName and Tabs._profileName.Parent then Tabs._profileName.Text = realName end
				if Tabs._reopenPlayerLabel and Tabs._reopenPlayerLabel.Parent then Tabs._reopenPlayerLabel.Text = displayName end
				if Tabs._avatarImg and Tabs._avatarImg.Parent then
					Tabs._avatarImg.Image = (LocalPlayer and "rbxthumb://type=AvatarHeadShot&id=" .. uid .. "&w=150&h=150") or "rbxassetid://10747373176"
				end
			end

			for _, tog in ipairs(Tabs._streamerToggles) do
				if tog and tog.GetValue and tog:GetValue() ~= enabled then
					pcall(function() tog:SetValue(enabled) end)
				end
			end
		end

		local function createControlBuilder(targetScroll, meta)
			local currentSection = nil
			local sectionOrder = 1
			local B = {}

			function B:Section(secOptions)
				secOptions = (type(secOptions) == "table" and secOptions) or { Title = tostring(secOptions or "SECTION") }
				local SectionTitle = secOptions.Title or 'SECTION'
				local isMinimized = (secOptions.Minimized == true or secOptions.Minized == true or secOptions.DefaultMinimized == true) or false
				local SectionFrame = Instance.new("Frame")
				local SectionCorner = Instance.new("UICorner")
				local SectionStroke = Instance.new("UIStroke")
				local SectionHeader = Instance.new("Frame")
				local SectionTitleLabel = Instance.new("TextLabel")
				local SectionContent = Instance.new("Frame")
				local ContentList = Instance.new("UIListLayout")
				local ContentPadding = Instance.new("UIPadding")

				SectionFrame.Name = "Section_" .. SectionTitle
				SectionFrame.Parent = secOptions.Parent or targetScroll
				sectionOrder = sectionOrder + 1
				local curTrans = (currentWindowTheme and currentWindowTheme.transparency) or {}
				SectionFrame.LayoutOrder = secOptions.LayoutOrder or sectionOrder
				SectionFrame.BackgroundColor3 = curColors['Background']:Lerp(curColors['Card'], 0.35)
				SectionFrame.BackgroundTransparency = (curTrans.Section or 0) / 100
				SectionFrame.BorderSizePixel = 0
				SectionFrame.Size = isMinimized and UDim2.new(1, 0, 0, 32) or UDim2.new(1, 0, 0, 74)
				SectionFrame.ClipsDescendants = isMinimized
				if not isMinimized then
					pcall(function() SectionFrame.AutomaticSize = Enum.AutomaticSize.Y end)
				end
				registerFeature(SectionTitle, "Section", SectionFrame, meta)

				SectionCorner.CornerRadius = UDim.new(0, 8)
				SectionCorner.Parent = SectionFrame

				SectionStroke.Color = curColors['CardBorder']
				SectionStroke.Thickness = 1
				SectionStroke.Parent = SectionFrame

				SectionHeader.Name = "Header"
				SectionHeader.Parent = SectionFrame
				SectionHeader.BackgroundTransparency = 1
				SectionHeader.Size = UDim2.new(1, 0, 0, 32)

				local SectionIndicator = Instance.new("Frame")
				local SectionIndicatorCorner = Instance.new("UICorner")

				SectionIndicator.Name = "Indicator"
				SectionIndicator.Parent = SectionHeader
				SectionIndicator.AnchorPoint = Vector2.new(0, 0.5)
				SectionIndicator.BackgroundColor3 = curColors['Main']
				SectionIndicator.BorderSizePixel = 0
				SectionIndicator.Position = UDim2.new(0, 10, 0.5, 0)
				SectionIndicator.Size = UDim2.new(0, 3, 0, 10)

				SectionIndicatorCorner.CornerRadius = UDim.new(0, 2)
				SectionIndicatorCorner.Parent = SectionIndicator

				SectionTitleLabel.Name = "Title"
				SectionTitleLabel.Parent = SectionHeader
				SectionTitleLabel.AnchorPoint = Vector2.new(0, 0.5)
				SectionTitleLabel.BackgroundTransparency = 1
				SectionTitleLabel.Position = UDim2.new(0, 22, 0.5, -1)
				SectionTitleLabel.Size = UDim2.new(1, -50, 0, 18)
				SectionTitleLabel.Font = Enum.Font.BuilderSansBold
				SectionTitleLabel.Text = SectionTitle:upper()
				SectionTitleLabel.TextColor3 = curColors['SubText']
				SectionTitleLabel.TextSize = 13.5
				SectionTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
				SectionTitleLabel.TextYAlignment = Enum.TextYAlignment.Center

				local MinBtn = Instance.new("ImageLabel")
				MinBtn.Name = "Minimize"
				MinBtn.Parent = SectionHeader
				MinBtn.AnchorPoint = Vector2.new(1, 0.5)
				MinBtn.BackgroundTransparency = 1
				MinBtn.Position = UDim2.new(1, -12, 0.5, 0)
				MinBtn.Size = UDim2.new(0, 14, 0, 14)
				MinBtn.Image = "rbxassetid://10709791437"
				MinBtn.ImageColor3 = curColors['SubText']
				MinBtn.Rotation = isMinimized and 0 or 90
				MinBtn.ZIndex = 6
				if secOptions.HideMinimize then
					MinBtn.Visible = false
				end

				SectionContent.Name = "Content"
				SectionContent.Parent = SectionFrame
				SectionContent.BackgroundTransparency = 1
				SectionContent.Position = UDim2.new(0, 0, 0, 32)
				SectionContent.Size = isMinimized and UDim2.new(1, 0, 0, 0) or UDim2.new(1, 0, 0, 42)
				SectionContent.ClipsDescendants = isMinimized
				SectionContent.Visible = not isMinimized
				if not isMinimized then
					pcall(function() SectionContent.AutomaticSize = Enum.AutomaticSize.Y end)
				end

				ContentList.Parent = SectionContent
				ContentList.SortOrder = Enum.SortOrder.LayoutOrder
				ContentList.Padding = UDim.new(0, 5)

				ContentPadding.Parent = SectionContent
				ContentPadding.PaddingBottom = UDim.new(0, 8)
				ContentPadding.PaddingLeft = UDim.new(0, 8)
				ContentPadding.PaddingRight = UDim.new(0, 8)
				ContentPadding.PaddingTop = UDim.new(0, 2)

				local function getContentHeight()
					local acs = ContentList.AbsoluteContentSize.Y
					if acs and acs > 0 then
						return acs + 14
					end
					local total = 0
					local count = 0
					for _, child in ipairs(SectionContent:GetChildren()) do
						if child:IsA("GuiObject") and child.Visible ~= false then
							local h = child.Size.Y.Offset
							if h <= 0 then
								local bg = child:FindFirstChild("Background")
								if bg and bg:IsA("GuiObject") and bg.Size.Y.Offset > 0 then
									h = bg.Size.Y.Offset
								else
									h = 40
								end
							end
							total = total + h
							count = count + 1
						end
					end
					if count > 0 then
						total = total + (count - 1) * 5 + 14
					end
					return math.max(42, total)
				end

				local function updateSectionHeight()
					if isMinimized then
						pcall(function() SectionFrame.AutomaticSize = Enum.AutomaticSize.None end)
						pcall(function() SectionContent.AutomaticSize = Enum.AutomaticSize.None end)
						SectionFrame.ClipsDescendants = true
						SectionContent.Visible = false
						SectionFrame.Size = UDim2.new(1, 0, 0, 32)
					else
						SectionContent.Visible = true
						SectionFrame.ClipsDescendants = false
						SectionContent.ClipsDescendants = false
						local ch = getContentHeight()
						SectionContent.Size = UDim2.new(1, 0, 0, ch)
						SectionFrame.Size = UDim2.new(1, 0, 0, 32 + ch)
						pcall(function() SectionContent.AutomaticSize = Enum.AutomaticSize.Y end)
						pcall(function() SectionFrame.AutomaticSize = Enum.AutomaticSize.Y end)
					end
				end

				local function toggleMinimize()
					isMinimized = not isMinimized
					tw({v = MinBtn, t = 0.2, s = Enum.EasingStyle.Cubic, d = "Out", g = {Rotation = isMinimized and 0 or 90}}):Play()
					if isMinimized then
						pcall(function() SectionFrame.AutomaticSize = Enum.AutomaticSize.None end)
						pcall(function() SectionContent.AutomaticSize = Enum.AutomaticSize.None end)
						SectionFrame.ClipsDescendants = true
						local twClose = tw({v = SectionFrame, t = 0.22, s = Enum.EasingStyle.Cubic, d = "Out", g = {Size = UDim2.new(1, 0, 0, 32)}})
						twClose.Completed:Connect(function()
							if isMinimized then
								SectionContent.Visible = false
							end
						end)
						twClose:Play()
					else
						SectionContent.Visible = true
						SectionFrame.ClipsDescendants = false
						SectionContent.ClipsDescendants = false
						local ch = getContentHeight()
						SectionContent.Size = UDim2.new(1, 0, 0, ch)
						local twOpen = tw({v = SectionFrame, t = 0.22, s = Enum.EasingStyle.Cubic, d = "Out", g = {Size = UDim2.new(1, 0, 0, 32 + ch)}})
						twOpen.Completed:Connect(function()
							if not isMinimized then
								pcall(function() SectionContent.AutomaticSize = Enum.AutomaticSize.Y end)
								pcall(function() SectionFrame.AutomaticSize = Enum.AutomaticSize.Y end)
							end
						end)
						twOpen:Play()
					end
				end

				local function getSharedMinBtn()
					if type(secOptions.SharedMinBtn) == "function" then
						return secOptions.SharedMinBtn()
					end
					return secOptions.SharedMinBtn
				end

				local HeaderClick = click(SectionHeader)
				HeaderClick.MouseButton1Click:Connect(function()
					if secOptions.CustomToggle then
						secOptions.CustomToggle()
					else
						toggleMinimize()
					end
				end)
				HeaderClick.MouseEnter:Connect(function()
					local c = currentWindowTheme.colors or curColors
					if MinBtn.Visible then
						tw({v = MinBtn, t = 0.15, g = {ImageColor3 = c['Main']}}):Play()
					end
					local sharedBtn = getSharedMinBtn()
					if sharedBtn and sharedBtn.Parent and sharedBtn.Visible then
						tw({v = sharedBtn, t = 0.15, g = {ImageColor3 = c['Main']}}):Play()
					end
					tw({v = SectionTitleLabel, t = 0.15, g = {TextColor3 = c['Text & Icon']}}):Play()
				end)
				HeaderClick.MouseLeave:Connect(function()
					local c = currentWindowTheme.colors or curColors
					if MinBtn.Visible then
						tw({v = MinBtn, t = 0.15, g = {ImageColor3 = isMinimized and c['SubText'] or c['Text & Icon']}}):Play()
					end
					local sharedBtn = getSharedMinBtn()
					if sharedBtn and sharedBtn.Parent and sharedBtn.Visible then
						tw({v = sharedBtn, t = 0.15, g = {ImageColor3 = isMinimized and c['SubText'] or c['Text & Icon']}}):Play()
					end
					tw({v = SectionTitleLabel, t = 0.15, g = {TextColor3 = c['SubText']}}):Play()
				end)

				ContentList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
					if not isMinimized then updateSectionHeight() end
				end)

				SectionContent.ChildAdded:Connect(function(child)
					if child:IsA("GuiObject") then
						child:GetPropertyChangedSignal("Size"):Connect(function()
							if not isMinimized then updateSectionHeight() end
						end)
						child:GetPropertyChangedSignal("Visible"):Connect(function()
							if not isMinimized then updateSectionHeight() end
						end)
					end
					if not isMinimized then updateSectionHeight() end
				end)

				SectionContent.ChildRemoved:Connect(function()
					if not isMinimized then updateSectionHeight() end
				end)

				targetScroll:GetPropertyChangedSignal("Visible"):Connect(function()
					if targetScroll.Visible and not isMinimized then
						updateSectionHeight()
						task.defer(updateSectionHeight)
						task.delay(0.08, updateSectionHeight)
					end
				end)

				if targetScroll.Parent and targetScroll.Parent:IsA("GuiObject") then
					targetScroll.Parent:GetPropertyChangedSignal("Visible"):Connect(function()
						if targetScroll.Parent.Visible and not isMinimized then
							updateSectionHeight()
							task.defer(updateSectionHeight)
							task.delay(0.08, updateSectionHeight)
						end
					end)
				end

				updateSectionHeight()
				task.delay(0.05, updateSectionHeight)
				task.delay(0.15, updateSectionHeight)
				task.delay(0.35, updateSectionHeight)

				currentSection = SectionContent

				local secData = {
					Frame = SectionFrame,
					Stroke = SectionStroke,
					Title = SectionTitleLabel,
					Indicator = SectionIndicator,
					MinBtn = MinBtn,
					TitleText = SectionTitle,
					Scroll = targetScroll,
					UpdateHeight = updateSectionHeight,
					IsMinimized = function() return isMinimized end,
					SetMinimized = function(state)
						if state and not isMinimized then
							toggleMinimize()
						elseif not state and isMinimized then
							toggleMinimize()
						end
					end
				}
				table.insert(currentWindowTheme.sections, secData)

				local SecObj = setmetatable({}, {
					__index = function(_, k)
						if B[k] then
							return function(self, ...)
								currentSection = SectionContent
								return B[k](B, ...)
							end
						end
					end
				})
				SecObj.Frame = SectionFrame
				SecObj.MinBtn = MinBtn
				SecObj.ToggleMinimize = toggleMinimize
				function SecObj:SetTitle(t) SectionTitleLabel.Text = tostring(t):upper() end
				function SecObj:Minimize() if not isMinimized then toggleMinimize() end end
				function SecObj:Expand() if isMinimized then toggleMinimize() end end
				function SecObj:IsMinimized() return isMinimized end
				return SecObj
			end

			function B:DualSection(leftOptions, rightOptions)
				leftOptions = (type(leftOptions) == "table" and leftOptions) or { Title = tostring(leftOptions or "Left") }
				rightOptions = (type(rightOptions) == "table" and rightOptions) or { Title = tostring(rightOptions or "Right") }

				local isDualMinimized = (leftOptions.Minimized == true or leftOptions.Minized == true or leftOptions.DefaultMinimized == true
					or rightOptions.Minimized == true or rightOptions.Minized == true or rightOptions.DefaultMinimized == true) or false

				local RowFrame = Instance.new("Frame")
				RowFrame.Name = "DualSectionRow_" .. (leftOptions.Title or "Left") .. "_" .. (rightOptions.Title or "Right")
				RowFrame.Parent = targetScroll
				sectionOrder = sectionOrder + 1
				RowFrame.LayoutOrder = leftOptions.LayoutOrder or rightOptions.LayoutOrder or sectionOrder
				RowFrame.BackgroundTransparency = 1
				RowFrame.BorderSizePixel = 0
				RowFrame.Size = UDim2.new(1, 0, 0, 0)
				RowFrame.ClipsDescendants = false
				pcall(function() RowFrame.AutomaticSize = Enum.AutomaticSize.Y end)

				local RowList = Instance.new("UIListLayout")
				RowList.Parent = RowFrame
				RowList.FillDirection = Enum.FillDirection.Horizontal
				RowList.HorizontalAlignment = Enum.HorizontalAlignment.Left
				RowList.VerticalAlignment = Enum.VerticalAlignment.Top
				RowList.SortOrder = Enum.SortOrder.LayoutOrder
				RowList.Padding = UDim.new(0, 8)

				local LeftCol = Instance.new("Frame")
				LeftCol.Name = "LeftColumn"
				LeftCol.Parent = RowFrame
				LeftCol.LayoutOrder = 1
				LeftCol.BackgroundTransparency = 1
				LeftCol.BorderSizePixel = 0
				LeftCol.Size = UDim2.new(0.5, -4, 0, 0)
				LeftCol.ClipsDescendants = false
				pcall(function() LeftCol.AutomaticSize = Enum.AutomaticSize.Y end)

				local RightCol = Instance.new("Frame")
				RightCol.Name = "RightColumn"
				RightCol.Parent = RowFrame
				RightCol.LayoutOrder = 2
				RightCol.BackgroundTransparency = 1
				RightCol.BorderSizePixel = 0
				RightCol.Size = UDim2.new(0.5, -4, 0, 0)
				RightCol.ClipsDescendants = false
				pcall(function() RightCol.AutomaticSize = Enum.AutomaticSize.Y end)

				local LeftSec = nil
				local RightSec = nil

				local function toggleDual()
					isDualMinimized = not isDualMinimized
					if LeftSec then
						if isDualMinimized then LeftSec:Minimize() else LeftSec:Expand() end
					end
					if RightSec then
						if isDualMinimized then RightSec:Minimize() else RightSec:Expand() end
					end
				end

				local leftOpts = {}
				for k, v in pairs(leftOptions) do leftOpts[k] = v end
				leftOpts.Parent = LeftCol
				leftOpts.Minimized = isDualMinimized
				leftOpts.HideMinimize = true
				leftOpts.CustomToggle = toggleDual
				leftOpts.SharedMinBtn = function() return RightSec and RightSec.MinBtn end

				local rightOpts = {}
				for k, v in pairs(rightOptions) do rightOpts[k] = v end
				rightOpts.Parent = RightCol
				rightOpts.Minimized = isDualMinimized
				rightOpts.HideMinimize = false
				rightOpts.CustomToggle = toggleDual

				LeftSec = B:Section(leftOpts)
				RightSec = B:Section(rightOpts)

				return LeftSec, RightSec
			end

			function B:Toggle(p)
				local Value = p.Value or false
				local Image = p.Image or ''
				local Callback = p.Callback or function() end
				local ToggleTitle = p.Title or 'Toggle'
				local Desc = p.Desc or ''

				local parent = currentSection or targetScroll
				local Toggle, Config = background(parent, ToggleTitle, Desc, Image, 'Toggle')
				registerFeature(ToggleTitle, "Toggle", Toggle, meta)

				local F_1 = Instance.new("Frame")
				local Frame_1 = Instance.new("Frame")
				local UICorner_2 = Instance.new("UICorner")
				local Frame_2 = Instance.new("Frame")
				local UICorner_3 = Instance.new("UICorner")

				F_1.Name = "F"
				F_1.Parent = Toggle
				F_1.AnchorPoint = Vector2.new(1, 0.5)
				F_1.BackgroundTransparency = 1
				F_1.Position = UDim2.new(1, -12, 0.5, 0)
				F_1.Size = UDim2.new(0, 40, 0, 22)

				Frame_1.Name = "SwitchPill"
				Frame_1.Parent = F_1
				Frame_1.AnchorPoint = Vector2.new(0.5, 0.5)
				Frame_1.Position = UDim2.new(0.5, 0, 0.5, 0)
				Frame_1.BackgroundColor3 = Value and curColors['Main'] or Color3.fromRGB(36, 36, 46)
				Frame_1.BorderSizePixel = 0
				Frame_1.Size = UDim2.new(1, 0, 0, 22)

				UICorner_2.CornerRadius = UDim.new(1, 0)
				UICorner_2.Parent = Frame_1

				Frame_2.Name = "Knob"
				Frame_2.Parent = Frame_1
				Frame_2.AnchorPoint = Vector2.new(0, 0.5)
				Frame_2.BackgroundColor3 = Value and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(160, 160, 170)
				Frame_2.BorderSizePixel = 0
				Frame_2.Position = Value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
				Frame_2.Size = UDim2.new(0, 16, 0, 16)
				Frame_2.ZIndex = 3

				UICorner_3.CornerRadius = UDim.new(1, 0)
				UICorner_3.Parent = Frame_2

				table.insert(currentWindowTheme.controls, {
					type = "toggle",
					Frame_1 = Frame_1,
					Frame_2 = Frame_2,
					GetValue = function() return Value end
				})

				local Click = click(Toggle)

				local function setToggleState(state, skipCallback)
					Value = state
					if Value then
						Config:SetTextTransparencyTitle(0)
						local c = currentWindowTheme.colors or curColors
						tw({v = Frame_1, t = 0.18, g = {BackgroundColor3 = c['Main']}}):Play()
						tw({v = Frame_2, t = 0.18, g = {BackgroundColor3 = Color3.fromRGB(15, 15, 18), Position = UDim2.new(1, -19, 0.5, 0)}}):Play()
					else
						Config:SetTextTransparencyTitle(0.3)
						tw({v = Frame_1, t = 0.18, g = {BackgroundColor3 = Color3.fromRGB(36, 36, 46)}}):Play()
						tw({v = Frame_2, t = 0.18, g = {BackgroundColor3 = Color3.fromRGB(160, 160, 170), Position = UDim2.new(0, 3, 0.5, 0)}}):Play()
					end
					if not skipCallback then
						pcall(Callback, Value)
					end
				end

				Click.MouseButton1Click:Connect(function() setToggleState(not Value) end)
				task.delay(0.05, function() setToggleState(Value, true) end)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Toggle.Visible = t end
				function New:SetValue(t, skip) setToggleState(t, skip) end
				function New:GetValue() return Value end

				if not p.IgnoreConfig then
					local flagKey = p.Flag or ToggleTitle
					table.insert(ConfigElements, {
						Type = "Toggle",
						Title = ToggleTitle,
						Flag = flagKey,
						Default = (p.Value ~= nil and p.Value or false),
						Get = function() return New:GetValue() end,
						Set = function(v) New:SetValue(v) end
					})
				end

				return New
			end

			function B:Button(p)
				local BtnTitle = p.Title or 'Button'
				local Desc = p.Desc or ''
				local Image = p.Image or ''
				local Callback = p.Callback or function() end

				local parent = currentSection or targetScroll
				local Button, Config = background(parent, BtnTitle, Desc, Image, 'Button')
				registerFeature(BtnTitle, "Button", Button, meta)
				Config:SetTextTransparencyTitle(0)
				Config:SetSizeT(42)

				local ArrowIcon = Instance.new("ImageLabel")
				ArrowIcon.Name = "Arrow"
				ArrowIcon.Parent = Button
				ArrowIcon.AnchorPoint = Vector2.new(1, 0.5)
				ArrowIcon.BackgroundTransparency = 1
				ArrowIcon.Position = UDim2.new(1, -12, 0.5, 0)
				ArrowIcon.Size = UDim2.new(0, 18, 0, 18)
				ArrowIcon.Image = "rbxassetid://10709791437"
				ArrowIcon.ImageColor3 = curColors['SubText']

				local Click = click(Button)
				Click.MouseEnter:Connect(function()
					local c = currentWindowTheme.colors or curColors
					tw({v = ArrowIcon, t = 0.15, g = {Position = UDim2.new(1, -8, 0.5, 0), ImageColor3 = c['Main']}}):Play()
					tw({v = Button, t = 0.15, g = {BackgroundColor3 = c['Card']:Lerp(c['Main'], 0.08)}}):Play()
				end)
				Click.MouseLeave:Connect(function()
					local c = currentWindowTheme.colors or curColors
					tw({v = ArrowIcon, t = 0.15, g = {Position = UDim2.new(1, -12, 0.5, 0), ImageColor3 = c['SubText']}}):Play()
					tw({v = Button, t = 0.15, g = {BackgroundColor3 = c['Card']}}):Play()
				end)
				Click.MouseButton1Click:Connect(function()
					jc(Click, Button)
					local c = currentWindowTheme.colors or curColors
					tw({v = Button, t = 0.08, g = {BackgroundColor3 = c['Card']:Lerp(c['Main'], 0.18)}}):Play()
					task.delay(0.08, function()
						local cNow = currentWindowTheme.colors or curColors
						tw({v = Button, t = 0.15, g = {BackgroundColor3 = cNow['Card']}}):Play()
					end)
					pcall(Callback)
				end)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Button.Visible = t end
				return New
			end

			function B:Slider(p)
				local SliderTitle = p.Title or 'Slider'
				local Desc = p.Desc or ''
				local Image = p.Image or ''
				local Min = p.Min or 0
				local Max = p.Max or 100
				local Value = p.Value or Min
				local Rounding = p.Rounding or 0
				local Callback = p.Callback or function() end

				local parent = currentSection or targetScroll
				local Slider, Config = background(parent, SliderTitle, Desc, Image, 'Slider')
				registerFeature(SliderTitle, "Slider", Slider, meta)
				Config:SetTextTransparencyTitle(0)
				Config:SetSizeT(185)

				local F = Instance.new("Frame")
				local SliderTrack = Instance.new("Frame")
				local TrackCorner = Instance.new("UICorner")
				local SliderFill = Instance.new("Frame")
				local FillCorner = Instance.new("UICorner")
				local Knob = Instance.new("Frame")
				local KnobCorner = Instance.new("UICorner")
				local ValueBox = Instance.new("TextBox")
				local ValueBoxCorner = Instance.new("UICorner")
				local ValueBoxStroke = Instance.new("UIStroke")

				F.Name = "SliderControls"
				F.Parent = Slider
				F.AnchorPoint = Vector2.new(1, 0.5)
				F.BackgroundTransparency = 1
				F.Position = UDim2.new(1, -12, 0.5, 0)
				F.Size = UDim2.new(0, 168, 0, 24)

				SliderTrack.Name = "Track"
				SliderTrack.Parent = F
				SliderTrack.AnchorPoint = Vector2.new(0, 0.5)
				SliderTrack.BackgroundColor3 = Color3.fromRGB(54, 54, 68)
				SliderTrack.BorderSizePixel = 0
				SliderTrack.Position = UDim2.new(0, 0, 0.5, 0)
				SliderTrack.Size = UDim2.new(0, 114, 0, 5)

				TrackCorner.CornerRadius = UDim.new(1, 0)
				TrackCorner.Parent = SliderTrack

				local TrackStroke = Instance.new("UIStroke")
				TrackStroke.Color = Color3.fromRGB(68, 68, 86)
				TrackStroke.Thickness = 1
				TrackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				TrackStroke.Parent = SliderTrack

				Slider.MouseEnter:Connect(function()
					tw({v = SliderTrack, t = 0.15, g = {BackgroundColor3 = Color3.fromRGB(66, 66, 82)}}):Play()
					tw({v = TrackStroke, t = 0.15, g = {Color = Color3.fromRGB(82, 82, 102)}}):Play()
				end)
				Slider.MouseLeave:Connect(function()
					tw({v = SliderTrack, t = 0.2, g = {BackgroundColor3 = Color3.fromRGB(54, 54, 68)}}):Play()
					tw({v = TrackStroke, t = 0.2, g = {Color = Color3.fromRGB(68, 68, 86)}}):Play()
				end)

				SliderFill.Name = "Fill"
				SliderFill.Parent = SliderTrack
				SliderFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				SliderFill.BorderSizePixel = 0
				SliderFill.Size = UDim2.new(0, 0, 1, 0)
				SliderFill.Active = false

				FillCorner.CornerRadius = UDim.new(1, 0)
				FillCorner.Parent = SliderFill

				Knob.Name = "Knob"
				Knob.Parent = SliderFill
				Knob.AnchorPoint = Vector2.new(0.5, 0.5)
				Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				Knob.BorderSizePixel = 0
				Knob.Position = UDim2.new(1, 0, 0.5, 0)
				Knob.Size = UDim2.new(0, 15, 0, 15)
				Knob.ZIndex = 4
				Knob.Active = false

				KnobCorner.CornerRadius = UDim.new(1, 0)
				KnobCorner.Parent = Knob

				ValueBox.Name = "ValueBox"
				ValueBox.Parent = F
				ValueBox.AnchorPoint = Vector2.new(1, 0.5)
				ValueBox.BackgroundColor3 = curColors['Function']['Dropdown']['Value Background'] or Color3.fromRGB(15, 15, 18)
				ValueBox.BorderSizePixel = 0
				ValueBox.Position = UDim2.new(1, 0, 0.5, 0)
				ValueBox.Size = UDim2.new(0, 42, 0, 22)
				ValueBox.Font = Enum.Font.BuilderSansMedium
				ValueBox.Text = tostring(Value)
				ValueBox.TextColor3 = curColors['Text & Icon']
				ValueBox.TextSize = 13

				ValueBoxCorner.CornerRadius = UDim.new(0, 4)
				ValueBoxCorner.Parent = ValueBox

				ValueBoxStroke.Color = curColors['Function']['Dropdown']['Value Stroke'] or Color3.fromRGB(44, 44, 54)
				ValueBoxStroke.Thickness = 1
				ValueBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				ValueBoxStroke.Parent = ValueBox

				table.insert(currentWindowTheme.controls, {
					type = "slider_value",
					Box = ValueBox,
					Stroke = ValueBoxStroke,
				})

				local function roundVal(v, r)
					local factor = 10 ^ r
					return math.floor(v * factor + 0.5) / factor
				end

				local function updateSlider(v, skipCallback)
					v = math.clamp(v, Min, Max)
					v = roundVal(v, Rounding)
					Value = v
					local progress = (Max > Min) and ((v - Min) / (Max - Min)) or 0
					tw({v = SliderFill, t = 0.08, g = {Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)}}):Play()
					ValueBox.Text = tostring(v)
					if not skipCallback then
						pcall(Callback, v)
					end
				end

				updateSlider(Value, true)

				ValueBox.FocusLost:Connect(function()
					local n = tonumber(ValueBox.Text) or Min
					updateSlider(n)
				end)

				local dragging = false
				local SliderHitbox = Instance.new("TextButton")
				SliderHitbox.Name = "SliderHitbox"
				SliderHitbox.Parent = F
				SliderHitbox.AnchorPoint = Vector2.new(0, 0.5)
				SliderHitbox.BackgroundTransparency = 1
				SliderHitbox.BorderSizePixel = 0
				SliderHitbox.Position = UDim2.new(0, -10, 0.5, 0)
				SliderHitbox.Size = UDim2.new(0, 134, 0, 24)
				SliderHitbox.ZIndex = 15
				SliderHitbox.Text = ""
				SliderHitbox.AutoButtonColor = false

				local function move(input)
					local rel = math.clamp((input.Position.X - SliderTrack.AbsolutePosition.X) / SliderTrack.AbsoluteSize.X, 0, 1)
					local n = rel * (Max - Min) + Min
					updateSlider(n)
				end

				SliderHitbox.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = true
						move(input)
					end
				end)

				U.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = false
					end
				end)

				U.InputChanged:Connect(function(input)
					if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						move(input)
					end
				end)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Slider.Visible = t end
				function New:SetValue(t, skip) updateSlider(t, skip) end
				function New:SetMin(t)
					Min = tonumber(t) or Min
					if Value < Min then updateSlider(Min) else updateSlider(Value, true) end
				end
				function New:SetMax(t)
					Max = tonumber(t) or Max
					if Value > Max then updateSlider(Max) else updateSlider(Value, true) end
				end
				function New:GetMin() return Min end
				function New:GetMax() return Max end
				function New:GetValue() return Value end

				if not p.IgnoreConfig then
					local flagKey = p.Flag or SliderTitle
					table.insert(ConfigElements, {
						Type = "Slider",
						Title = SliderTitle,
						Flag = flagKey,
						Default = (p.Value ~= nil and p.Value or Min),
						Get = function() return New:GetValue() end,
						Set = function(v) New:SetValue(tonumber(v) or v) end
					})
				end

				return New
			end

			function B:Dropdown(p)
				local DropdownTitle = p.Title or 'Dropdown'
				local Desc = p.Desc or ''
				local Image = p.Image or ''
				local List = p.List or {}
				local Value = p.Value or List[1]
				local Multi = p.Multi or false
				local Callback = p.Callback or function() end

				local parent = currentSection or targetScroll
				local Dropdown, Config = background(parent, DropdownTitle, Desc, Image, 'Dropdown')
				registerFeature(DropdownTitle, "Dropdown", Dropdown, meta)
				Config:SetTextTransparencyTitle(0)
				Config:SetSizeT(140)

				local DropdownSelect = addDropdownSelect(Dropdown, Dropdown, Multi, Callback, Value, List)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Dropdown.Visible = t end
				function New:SetValue(t, skip) DropdownSelect:SetValue(t, skip) end
				function New:GetValue() return DropdownSelect:GetValue() end
				function New:Add(t) DropdownSelect:Add(t) end
				function New:Clear(t) DropdownSelect:Clear(t) end
				function New:Refresh(newList, defaultVal)
					DropdownSelect:Clear()
					if type(newList) == "table" then
						for _, item in ipairs(newList) do
							DropdownSelect:Add(item)
						end
						if defaultVal ~= nil then
							DropdownSelect:SetValue(defaultVal, true)
						end
					end
				end

				if not p.IgnoreConfig then
					local flagKey = p.Flag or DropdownTitle
					table.insert(ConfigElements, {
						Type = "Dropdown",
						Title = DropdownTitle,
						Flag = flagKey,
						Default = (p.Value ~= nil and p.Value or (List and List[1]) or ""),
						Get = function() return New:GetValue() end,
						Set = function(v) New:SetValue(v) end
					})
				end

				return New
			end

			function B:Textbox(p)
				local TextboxTitle = p.Title or 'Textbox'
				local Desc = p.Desc or ''
				local Image = p.Image or ''
				local Value = p.Value or ''
				local Placeholder = p.Placeholder or 'Input text...'
				local ClearText = (p.ClearText ~= nil and p.ClearText) or (p.ClearTextOnFocus ~= nil and p.ClearTextOnFocus) or false
				local Callback = p.Callback or function() end

				local parent = currentSection or targetScroll
				local Textbox, Config = background(parent, TextboxTitle, Desc, Image, 'Textbox')
				registerFeature(TextboxTitle, "Input", Textbox, meta)
				Config:SetTextTransparencyTitle(0)
				Config:SetSizeT(140)

				local F = Instance.new("Frame")
				local InputBox = Instance.new("TextBox")
				local BoxCorner = Instance.new("UICorner")
				local BoxStroke = Instance.new("UIStroke")

				F.Name = "F"
				F.Parent = Textbox
				F.AnchorPoint = Vector2.new(1, 0.5)
				F.BackgroundTransparency = 1
				F.Position = UDim2.new(1, -12, 0.5, 0)
				F.Size = UDim2.new(0, 120, 0, 22)
				F.ClipsDescendants = false

				InputBox.Name = "Input"
				InputBox.Parent = F
				InputBox.BackgroundColor3 = curColors['Function']['Dropdown']['Value Background'] or Color3.fromRGB(15, 15, 18)
				InputBox.BorderSizePixel = 0
				InputBox.Size = UDim2.new(1, 0, 1, 0)
				InputBox.Font = Enum.Font.BuilderSansMedium
				InputBox.PlaceholderColor3 = curColors['SubText']
				InputBox.PlaceholderText = Placeholder
				InputBox.Text = Value
				InputBox.TextColor3 = curColors['Text & Icon']
				InputBox.TextSize = 13
				InputBox.ClearTextOnFocus = ClearText
				InputBox.TextXAlignment = Enum.TextXAlignment.Left
				InputBox.TextYAlignment = Enum.TextYAlignment.Center

				local BoxPadding = Instance.new("UIPadding")
				BoxPadding.Parent = InputBox
				BoxPadding.PaddingLeft = UDim.new(0, 8)
				BoxPadding.PaddingRight = UDim.new(0, 8)

				BoxCorner.CornerRadius = UDim.new(0, 4)
				BoxCorner.Parent = InputBox

				BoxStroke.Color = curColors['Function']['Dropdown']['Value Stroke'] or Color3.fromRGB(44, 44, 54)
				BoxStroke.Thickness = 1
				BoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				BoxStroke.Parent = InputBox

				table.insert(currentWindowTheme.controls, {
					type = "textbox",
					Box = InputBox,
					Stroke = BoxStroke,
				})

				InputBox.FocusLost:Connect(function() pcall(Callback, InputBox.Text) end)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Textbox.Visible = t end
				function New:SetValue(t, skip)
					InputBox.Text = tostring(t or "")
					if not skip then
						pcall(Callback, InputBox.Text)
					end
				end
				function New:SetClearTextOnFocus(t) InputBox.ClearTextOnFocus = not not t end
				function New:SetPlaceholderText(t) InputBox.PlaceholderText = tostring(t) end
				function New:GetValue() return InputBox.Text end

				if not p.IgnoreConfig then
					local flagKey = p.Flag or TextboxTitle
					table.insert(ConfigElements, {
						Type = "Textbox",
						Title = TextboxTitle,
						Flag = flagKey,
						Default = (p.Value ~= nil and tostring(p.Value) or ""),
						Get = function() return New:GetValue() end,
						Set = function(v) New:SetValue(v) end
					})
				end

				return New
			end

			function B:Keybind(p)
				local KeyTitle = p.Title or 'Keybind'
				local Desc = p.Desc or ''
				local Image = p.Image or ''
				local Key = p.Key or Enum.KeyCode.E
				local Callback = p.Callback or function() end

				local parent = currentSection or targetScroll
				local Keybind, Config = background(parent, KeyTitle, Desc, Image, 'Keybind')
				registerFeature(KeyTitle, "Keybind", Keybind, meta)
				Config:SetSizeT(115)

				local KeyButton = Instance.new("TextButton")
				local KeyCorner = Instance.new("UICorner")
				local KeyStroke = Instance.new("UIStroke")
				local KeyPadding = Instance.new("UIPadding")
				local KeyConstraint = Instance.new("UISizeConstraint")

				KeyButton.Name = "KeyBtn"
				KeyButton.Parent = Keybind
				KeyButton.AnchorPoint = Vector2.new(1, 0.5)
				KeyButton.BackgroundColor3 = curColors['Function']['Dropdown']['Value Background'] or Color3.fromRGB(15, 15, 18)
				KeyButton.BorderSizePixel = 0
				KeyButton.Position = UDim2.new(1, -12, 0.5, 0)
				KeyButton.AutomaticSize = Enum.AutomaticSize.X
				KeyButton.Size = UDim2.new(0, 0, 0, 22)
				KeyButton.Font = Enum.Font.BuilderSansMedium
				KeyButton.Text = tostring(Key):gsub("Enum.KeyCode.", "")
				KeyButton.TextColor3 = curColors['Text & Icon']
				KeyButton.TextSize = 13

				KeyConstraint.Parent = KeyButton
				KeyConstraint.MinSize = Vector2.new(38, 22)

				KeyPadding.Parent = KeyButton
				KeyPadding.PaddingLeft = UDim.new(0, 8)
				KeyPadding.PaddingRight = UDim.new(0, 8)

				KeyCorner.CornerRadius = UDim.new(0, 4)
				KeyCorner.Parent = KeyButton

				KeyStroke.Color = curColors['Function']['Dropdown']['Value Stroke'] or Color3.fromRGB(44, 44, 54)
				KeyStroke.Thickness = 1
				KeyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				KeyStroke.Parent = KeyButton

				table.insert(currentWindowTheme.controls, {
					type = "keybind",
					Box = KeyButton,
					Stroke = KeyStroke,
				})

				local listening = false
				KeyButton.MouseButton1Click:Connect(function()
					listening = true
					KeyButton.Text = "..."
					tw({v = KeyStroke, t = 0.15, g = {Color = Color3.fromRGB(255, 255, 255)}}):Play()
					local conn
					conn = U.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.Keyboard then
							Key = input.KeyCode
							KeyButton.Text = tostring(Key):gsub("Enum.KeyCode.", "")
							tw({v = KeyStroke, t = 0.15, g = {Color = curColors['Function']['Dropdown']['Value Stroke'] or Color3.fromRGB(44, 44, 54)}}):Play()
							conn:Disconnect()
							listening = false
							pcall(Callback, Key)
						end
					end)
				end)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Keybind.Visible = t end
				function New:SetKey(t)
					if typeof(t) == "EnumItem" then
						Key = t
					elseif type(t) == "string" then
						local kname = t:gsub("Enum.KeyCode.", "")
						if Enum.KeyCode[kname] then
							Key = Enum.KeyCode[kname]
						end
					end
					KeyButton.Text = tostring(Key):gsub("Enum.KeyCode.", "")
					pcall(Callback, Key)
				end
				function New:GetKey() return Key end
				function New:SetValue(t) New:SetKey(t) end
				function New:GetValue() return tostring(Key):gsub("Enum.KeyCode.", "") end

				if not p.IgnoreConfig then
					local flagKey = p.Flag or KeyTitle
					table.insert(ConfigElements, {
						Type = "Keybind",
						Title = KeyTitle,
						Flag = flagKey,
						Default = (p.Key ~= nil and tostring(p.Key):gsub("Enum.KeyCode.", "") or "E"),
						Get = function() return New:GetValue() end,
						Set = function(v) New:SetValue(v) end
					})
				end

				return New
			end

			function B:ColorPicker(p)
				local CPTitle = p.Title or 'Color'
				local Desc = p.Desc or ''
				local Image = p.Image or ''
				local Value = p.Value or Color3.fromRGB(255, 255, 255)
				local Callback = p.Callback or function() end

				local parent = currentSection or targetScroll
				local ColorPicker, Config = background(parent, CPTitle, Desc, Image, 'Color Picker')
				registerFeature(CPTitle, "Color", ColorPicker, meta)
				Config:SetTextTransparencyTitle(0)
				Config:SetSizeT(50)

				local Preview = Instance.new("Frame")
				local PrevCorner = Instance.new("UICorner")
				local PrevStroke = Instance.new("UIStroke")

				Preview.Name = "ColorPreview"
				Preview.Parent = ColorPicker
				Preview.AnchorPoint = Vector2.new(1, 0.5)
				Preview.BackgroundColor3 = Value
				Preview.BorderSizePixel = 0
				Preview.Position = UDim2.new(1, -12, 0.5, 0)
				Preview.Size = UDim2.new(0, 24, 0, 20)

				PrevCorner.CornerRadius = UDim.new(0, 4)
				PrevCorner.Parent = Preview

				PrevStroke.Color = curColors['CardBorder']
				PrevStroke.Thickness = 1
				PrevStroke.Parent = Preview

				local ColorpickBar = Instance.new("Frame")
				local CPBarCorner = Instance.new("UICorner")
				local CPBarStroke = Instance.new("UIStroke")
				local Color_1 = Instance.new("ImageLabel")
				local ColorSelection_1 = Instance.new("ImageLabel")
				local Hue_1 = Instance.new("ImageLabel")
				local HueSelection_1 = Instance.new("ImageLabel")

				ColorpickBar.Name = "ColorpickBar"
				ColorpickBar.Parent = ScreenGui
				ColorpickBar.BackgroundColor3 = curColors['Card']
				ColorpickBar.BorderSizePixel = 0
				ColorpickBar.Size = UDim2.new(0, 185, 0, 110)
				ColorpickBar.Visible = false
				ColorpickBar.ZIndex = 90

				CPBarCorner.CornerRadius = UDim.new(0, 6)
				CPBarCorner.Parent = ColorpickBar

				CPBarStroke.Color = Color3.fromRGB(70, 70, 80)
				CPBarStroke.Thickness = 1
				CPBarStroke.Parent = ColorpickBar

				Color_1.Name = "Color"
				Color_1.Parent = ColorpickBar
				Color_1.Position = UDim2.new(0, 8, 0, 8)
				Color_1.Size = UDim2.new(0, 115, 0, 94)
				Color_1.Image = "rbxassetid://4155801252"
				Color_1.ZIndex = 91

				local ColorCorner = Instance.new("UICorner")
				ColorCorner.CornerRadius = UDim.new(0, 4)
				ColorCorner.Parent = Color_1

				ColorSelection_1.Name = "ColorSelection"
				ColorSelection_1.Parent = Color_1
				ColorSelection_1.AnchorPoint = Vector2.new(0.5, 0.5)
				ColorSelection_1.BackgroundTransparency = 1
				ColorSelection_1.Size = UDim2.new(0, 10, 0, 10)
				ColorSelection_1.Image = "rbxassetid://4805639000"
				ColorSelection_1.ZIndex = 92

				Hue_1.Name = "Hue"
				Hue_1.Parent = ColorpickBar
				Hue_1.Position = UDim2.new(0, 130, 0, 8)
				Hue_1.Size = UDim2.new(0, 16, 0, 94)
				Hue_1.ZIndex = 91

				local HueCorner = Instance.new("UICorner")
				HueCorner.CornerRadius = UDim.new(0, 4)
				HueCorner.Parent = Hue_1

				local HueGrad = Instance.new("UIGradient")
				HueGrad.Color = ColorSequence.new{
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
					ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
					ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
					ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
				}
				HueGrad.Rotation = 90
				HueGrad.Parent = Hue_1

				HueSelection_1.Name = "HueSelection"
				HueSelection_1.Parent = Hue_1
				HueSelection_1.AnchorPoint = Vector2.new(0.5, 0.5)
				HueSelection_1.BackgroundTransparency = 1
				HueSelection_1.Position = UDim2.new(0.5, 0, 0, 0)
				HueSelection_1.Size = UDim2.new(1, 4, 0, 4)
				HueSelection_1.Image = "rbxassetid://4805639000"
				HueSelection_1.ZIndex = 92

				local ColorH, ColorS, ColorV = Color3.toHSV(Value)
				Color_1.BackgroundColor3 = Color3.fromHSV(ColorH, 1, 1)
				ColorSelection_1.Position = UDim2.new(ColorS, 0, 1 - ColorV, 0)
				HueSelection_1.Position = UDim2.new(0.5, 0, ColorH, 0)

				local isOpen = false
				local draggingColor = false
				local draggingHue = false

				local function updateColor()
					local c = Color3.fromHSV(ColorH, ColorS, ColorV)
					Value = c
					Preview.BackgroundColor3 = c
					Color_1.BackgroundColor3 = Color3.fromHSV(ColorH, 1, 1)
					pcall(Callback, c)
				end

				local ClickCP = click(ColorPicker)
				ClickCP.MouseButton1Click:Connect(function()
					isOpen = not isOpen
					if isOpen then
						local targetX = Preview.AbsolutePosition.X - ColorpickBar.Parent.AbsolutePosition.X - 160
						local targetY = Preview.AbsolutePosition.Y - ColorpickBar.Parent.AbsolutePosition.Y + 26
						ColorpickBar.Position = UDim2.new(0, math.max(10, targetX), 0, math.max(10, targetY))
						ColorpickBar.Visible = true
					else
						ColorpickBar.Visible = false
					end
				end)

				Color_1.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						draggingColor = true
						local relX = math.clamp((input.Position.X - Color_1.AbsolutePosition.X) / Color_1.AbsoluteSize.X, 0, 1)
						local relY = math.clamp((input.Position.Y - Color_1.AbsolutePosition.Y) / Color_1.AbsoluteSize.Y, 0, 1)
						ColorSelection_1.Position = UDim2.new(relX, 0, relY, 0)
						ColorS = relX
						ColorV = 1 - relY
						updateColor()
					end
				end)

				Hue_1.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						draggingHue = true
						local relY = math.clamp((input.Position.Y - Hue_1.AbsolutePosition.Y) / Hue_1.AbsoluteSize.Y, 0, 1)
						HueSelection_1.Position = UDim2.new(0.5, 0, relY, 0)
						ColorH = relY
						updateColor()
					end
				end)

				U.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						draggingColor = false
						draggingHue = false
					end
				end)

				U.InputChanged:Connect(function(input)
					if draggingColor and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						local relX = math.clamp((input.Position.X - Color_1.AbsolutePosition.X) / Color_1.AbsoluteSize.X, 0, 1)
						local relY = math.clamp((input.Position.Y - Color_1.AbsolutePosition.Y) / Color_1.AbsoluteSize.Y, 0, 1)
						ColorSelection_1.Position = UDim2.new(relX, 0, relY, 0)
						ColorS = relX
						ColorV = 1 - relY
						updateColor()
					elseif draggingHue and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						local relY = math.clamp((input.Position.Y - Hue_1.AbsolutePosition.Y) / Hue_1.AbsoluteSize.Y, 0, 1)
						HueSelection_1.Position = UDim2.new(0.5, 0, relY, 0)
						ColorH = relY
						updateColor()
					end
				end)

				U.InputBegan:Connect(function(input)
					if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and isOpen then
						local bPos = ColorpickBar.AbsolutePosition
						local bSize = ColorpickBar.AbsoluteSize
						local mX, mY = input.Position.X, input.Position.Y
						if mX < bPos.X or mX > bPos.X + bSize.X or mY < bPos.Y - 24 or mY > bPos.Y + bSize.Y then
							ColorpickBar.Visible = false
							isOpen = false
						end
					end
				end)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) ColorPicker.Visible = t end
				function New:SetValue(c)
					if typeof(c) == "Color3" then
						Value = c
						ColorH, ColorS, ColorV = Color3.toHSV(Value)
						ColorSelection_1.Position = UDim2.new(ColorS, 0, 1 - ColorV, 0)
						HueSelection_1.Position = UDim2.new(0.5, 0, ColorH, 0)
						updateColor()
					elseif type(c) == "table" then
						local r = c.R or c[1]
						local g = c.G or c[2]
						local b = c.B or c[3]
						if r and g and b then
							if r > 1 or g > 1 or b > 1 then
								Value = Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
							else
								Value = Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
							end
							ColorH, ColorS, ColorV = Color3.toHSV(Value)
							ColorSelection_1.Position = UDim2.new(ColorS, 0, 1 - ColorV, 0)
							HueSelection_1.Position = UDim2.new(0.5, 0, ColorH, 0)
							updateColor()
						end
					end
				end
				function New:GetValue()
					return { R = math.floor(Value.R * 255), G = math.floor(Value.G * 255), B = math.floor(Value.B * 255) }
				end

				if not p.IgnoreConfig then
					local flagKey = p.Flag or CPTitle
					table.insert(ConfigElements, {
						Type = "ColorPicker",
						Title = CPTitle,
						Flag = flagKey,
						Default = (p.Value and (p.Value.R and Color3.new(p.Value.R, p.Value.G, p.Value.B) or p.Value) or Color3.fromRGB(255, 255, 255)),
						Get = function() return New:GetValue() end,
						Set = function(v) New:SetValue(v) end
					})
				end

				return New
			end

			function B:Label(p)
				local LabelTitle = p.Title or 'Label'
				local Desc = p.Desc or ''
				local Image = p.Image or ''

				local parent = currentSection or targetScroll
				local Label, Config = background(parent, LabelTitle, Desc, Image, 'Label')
				registerFeature(LabelTitle, "Label", Label, meta)
				Config:SetTextTransparencyTitle(0)
				Config:SetSizeT(0)

				local New = {}
				function New:SetTitle(t) Config:SetTitle(t) end
				function New:SetDesc(t) Config:SetDesc(t) end
				function New:SetVisible(t) Label.Visible = t end
				return New
			end

			function B:Code(p)
				local Title = p.Title or 'Script / Code'
				local CodeText = p.Code or '-- print("Aether Studios")'
				local parent = currentSection or targetScroll

				local CodeFrame = Instance.new("Frame")
				local UICorner_1 = Instance.new("UICorner")
				local Stroke = Instance.new("UIStroke")
				local Top_1 = Instance.new("Frame")
				local Title_L = Instance.new("TextLabel")
				local CopyBtn = Instance.new("TextButton")
				local CodeScroll = Instance.new("ScrollingFrame")
				local CodeLabel = Instance.new("TextLabel")

				CodeFrame.Name = "CodeBox"
				CodeFrame.Parent = parent
				CodeFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
				CodeFrame.Size = UDim2.new(1, 0, 0, 110)
				CodeFrame.ClipsDescendants = true
				registerFeature(Title or "Code", "Code", CodeFrame, meta)

				UICorner_1.CornerRadius = UDim.new(0, 6)
				UICorner_1.Parent = CodeFrame

				Stroke.Color = curColors['CardBorder']
				Stroke.Thickness = 1
				Stroke.Parent = CodeFrame

				Top_1.Parent = CodeFrame
				Top_1.BackgroundColor3 = curColors['Card']
				Top_1.Size = UDim2.new(1, 0, 0, 24)

				Title_L.Parent = Top_1
				Title_L.BackgroundTransparency = 1
				Title_L.Position = UDim2.new(0, 8, 0, 0)
				Title_L.Size = UDim2.new(0.5, 0, 1, 0)
				Title_L.Font = Enum.Font.BuilderSansBold
				Title_L.Text = tostring(Title)
				Title_L.TextColor3 = curColors['Text & Icon']
				Title_L.TextSize = 12
				Title_L.TextXAlignment = Enum.TextXAlignment.Left

				CopyBtn.Parent = Top_1
				CopyBtn.AnchorPoint = Vector2.new(1, 0.5)
				CopyBtn.BackgroundTransparency = 1
				CopyBtn.Position = UDim2.new(1, -8, 0.5, 0)
				CopyBtn.Size = UDim2.new(0, 42, 1, 0)
				CopyBtn.Font = Enum.Font.BuilderSansBold
				CopyBtn.Text = "COPY"
				CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				CopyBtn.TextSize = 11

				CodeScroll.Parent = CodeFrame
				CodeScroll.BackgroundTransparency = 1
				CodeScroll.Position = UDim2.new(0, 8, 0, 28)
				CodeScroll.Size = UDim2.new(1, -16, 1, -32)
				CodeScroll.ScrollBarThickness = 2
				CodeScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)

				CodeLabel.Parent = CodeScroll
				CodeLabel.BackgroundTransparency = 1
				CodeLabel.Font = Enum.Font.RobotoMono
				CodeLabel.Text = CodeText
				CodeLabel.TextColor3 = curColors['SubText']
				CodeLabel.TextSize = 10.5
				CodeLabel.TextXAlignment = Enum.TextXAlignment.Left
				CodeLabel.TextYAlignment = Enum.TextYAlignment.Top
				CodeLabel.AutomaticSize = Enum.AutomaticSize.XY

				CopyBtn.MouseButton1Click:Connect(function()
					if setclipboard then setclipboard(CodeText) end
					CopyBtn.Text = "COPIED"
					task.wait(1)
					CopyBtn.Text = "COPY"
				end)

				local New = {}
				function New:SetTitle(t) Title_L.Text = tostring(t) end
				function New:SetCode(t)
					CodeText = t
					CodeLabel.Text = t
				end
				return New
			end

			function B:CreateLogger(p)
				local TitleText = p.Title or "SYSTEM LOGS"
				local BoxSize = p.Size or UDim2.new(1, 0, 0, 160)
				local parent = currentSection or targetScroll

				local Background = Instance.new("Frame")
				local LogCorner = Instance.new("UICorner")
				local LogStroke = Instance.new("UIStroke")
				local TopBar = Instance.new("Frame")
				local TitleLabel = Instance.new("TextLabel")
				local ActionButtons = Instance.new("Frame")
				local UIListLayout_Actions = Instance.new("UIListLayout")
				local ClearBtn = Instance.new("TextButton")
				local CopyBtn = Instance.new("TextButton")
				local LogContainer = Instance.new("ScrollingFrame")
				local UIListLayout_Logs = Instance.new("UIListLayout")
				local UIPadding_Logs = Instance.new("UIPadding")

				Background.Name = "LoggerBox"
				Background.Parent = parent
				Background.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
				Background.Size = BoxSize
				Background.ClipsDescendants = true
				registerFeature(TitleText, "Logger", Background, meta)

				LogCorner.CornerRadius = UDim.new(0, 6)
				LogCorner.Parent = Background

				LogStroke.Color = curColors['CardBorder']
				LogStroke.Thickness = 1
				LogStroke.Parent = Background

				TopBar.Name = "TopBar"
				TopBar.Parent = Background
				TopBar.BackgroundColor3 = curColors['Card']
				TopBar.Size = UDim2.new(1, 0, 0, 24)

				TitleLabel.Parent = TopBar
				TitleLabel.BackgroundTransparency = 1
				TitleLabel.Position = UDim2.new(0, 8, 0, 0)
				TitleLabel.Size = UDim2.new(0.5, 0, 1, 0)
				TitleLabel.Font = Enum.Font.BuilderSansBold
				TitleLabel.Text = TitleText:upper()
				TitleLabel.TextColor3 = curColors['Text & Icon']
				TitleLabel.TextSize = 12
				TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

				ActionButtons.Parent = TopBar
				ActionButtons.BackgroundTransparency = 1
				ActionButtons.Size = UDim2.new(0.5, -8, 1, 0)
				ActionButtons.Position = UDim2.new(0.5, 0, 0, 0)

				UIListLayout_Actions.Parent = ActionButtons
				UIListLayout_Actions.FillDirection = Enum.FillDirection.Horizontal
				UIListLayout_Actions.HorizontalAlignment = Enum.HorizontalAlignment.Right
				UIListLayout_Actions.VerticalAlignment = Enum.VerticalAlignment.Center
				UIListLayout_Actions.Padding = UDim.new(0, 8)

				local function makeActionBtn(btn, text)
					btn.Parent = ActionButtons
					btn.BackgroundTransparency = 1
					btn.Size = UDim2.new(0, 36, 1, 0)
					btn.Font = Enum.Font.BuilderSansBold
					btn.Text = text
					btn.TextColor3 = curColors['SubText']
					btn.TextSize = 11
					return btn
				end

				makeActionBtn(ClearBtn, "CLEAR")
				makeActionBtn(CopyBtn, "COPY")

				LogContainer.Name = "LogContainer"
				LogContainer.Parent = Background
				LogContainer.BackgroundTransparency = 1
				LogContainer.Position = UDim2.new(0, 0, 0, 25)
				LogContainer.Size = UDim2.new(1, 0, 1, -25)
				LogContainer.ScrollBarThickness = 2
				LogContainer.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
				LogContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y

				UIListLayout_Logs.Parent = LogContainer
				UIListLayout_Logs.SortOrder = Enum.SortOrder.LayoutOrder
				UIListLayout_Logs.Padding = UDim.new(0, 2)

				UIPadding_Logs.Parent = LogContainer
				UIPadding_Logs.PaddingLeft = UDim.new(0, 8)
				UIPadding_Logs.PaddingTop = UDim.new(0, 4)

				local Logger = {}
				function Logger:Log(message, color)
					local LogLabel = Instance.new("TextLabel")
					LogLabel.Parent = LogContainer
					LogLabel.BackgroundTransparency = 1
					LogLabel.Size = UDim2.new(1, -10, 0, 14)
					LogLabel.Font = Enum.Font.RobotoMono
					LogLabel.Text = string.format("[%s] %s", os.date("%X"), tostring(message))
					LogLabel.TextColor3 = color or curColors['SubText']
					LogLabel.TextSize = 9.5
					LogLabel.TextXAlignment = Enum.TextXAlignment.Left
					LogLabel.RichText = true

					task.defer(function()
						local contentHeight = UIListLayout_Logs.AbsoluteContentSize.Y + 8
						local windowHeight = LogContainer.AbsoluteWindowSize.Y
						if contentHeight > windowHeight then
							LogContainer.CanvasPosition = Vector2.new(0, contentHeight - windowHeight)
						else
							LogContainer.CanvasPosition = Vector2.new(0, 0)
						end
					end)
				end

				function Logger:Clear()
					for _, item in pairs(LogContainer:GetChildren()) do
						if item:IsA("TextLabel") then item:Destroy() end
					end
					LogContainer.CanvasPosition = Vector2.new(0, 0)
				end

				ClearBtn.MouseButton1Click:Connect(function() Logger:Clear() end)
				CopyBtn.MouseButton1Click:Connect(function()
					local fullLog = ""
					for _, item in pairs(LogContainer:GetChildren()) do
						if item:IsA("TextLabel") then fullLog = fullLog .. item.Text .. "\n" end
					end
					if setclipboard then setclipboard(fullLog) end
					CopyBtn.Text = "DONE"
					task.wait(1)
					CopyBtn.Text = "COPY"
				end)

				return Logger
			end

			function B:Image(p)
				local ImageId = (type(p) == "table" and (p.Image or p.Id)) or (type(p) == "string" and p) or 'rbxassetid://111362591084511'
				local ImageHeight = (type(p) == "table" and p.Height) or 130
				local parent = currentSection or targetScroll

				local ImageLogo = Instance.new("ImageLabel")
				local UICorner_1 = Instance.new("UICorner")
				ImageLogo.Name = "ImageBanner"
				ImageLogo.Parent = parent
				ImageLogo.BackgroundTransparency = 1
				ImageLogo.Size = UDim2.new(1, 0, 0, ImageHeight)
				ImageLogo.Image = ImageId
				ImageLogo.ScaleType = Enum.ScaleType.Crop
				UICorner_1.CornerRadius = UDim.new(0, 6)
				UICorner_1.Parent = ImageLogo
				return ImageLogo
			end

			function B:PricingCards(cardsData)
				local parent = currentSection or targetScroll
				local Container = Instance.new("Frame")
				local RowLayout = Instance.new("UIListLayout")
				local RowPadding = Instance.new("UIPadding")

				Container.Name = "PricingCardsRow"
				Container.Parent = parent
				Container.BackgroundTransparency = 1
				Container.BorderSizePixel = 0
				Container.Size = UDim2.new(1, 0, 0, 235)
				Container.ClipsDescendants = false

				RowLayout.Parent = Container
				RowLayout.FillDirection = Enum.FillDirection.Horizontal
				RowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				RowLayout.SortOrder = Enum.SortOrder.LayoutOrder
				RowLayout.Padding = UDim.new(0, 8)

				RowPadding.Parent = Container
				RowPadding.PaddingLeft = UDim.new(0, 2)
				RowPadding.PaddingRight = UDim.new(0, 2)
				RowPadding.PaddingTop = UDim.new(0, 2)
				RowPadding.PaddingBottom = UDim.new(0, 4)

				local totalCards = #cardsData
				for idx, cData in ipairs(cardsData) do
					local CardWrapper = Instance.new("Frame")
					CardWrapper.Name = "CardWrapper_" .. (cData.Title or idx)
					CardWrapper.Parent = Container
					CardWrapper.LayoutOrder = idx
					CardWrapper.BackgroundTransparency = 1
					CardWrapper.BorderSizePixel = 0
					CardWrapper.Size = UDim2.new(1 / totalCards, - math.floor((totalCards - 1) * 8 / totalCards), 1, 0)
					CardWrapper.ClipsDescendants = false

					local Card = Instance.new("Frame")
					local CardCorner = Instance.new("UICorner")
					local CardStroke = Instance.new("UIStroke")
					local CardPadding = Instance.new("UIPadding")
					local CardLayout = Instance.new("UIListLayout")

					Card.Name = "PricingCard_" .. (cData.Title or idx)
					Card.Parent = CardWrapper
					Card.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
					Card.BorderSizePixel = 0
					Card.Size = UDim2.new(1, 0, 1, 0)
					Card.ZIndex = 2
					Card.ClipsDescendants = true

					CardCorner.CornerRadius = UDim.new(0, 8)
					CardCorner.Parent = Card

					CardStroke.Thickness = 1
					CardStroke.Color = cData.BorderColor or curColors['CardBorder']
					CardStroke.Parent = Card

					if cData.Glow then
						CardStroke.Thickness = 1.5
						CardStroke.Color = Color3.fromRGB(255, 215, 0)

						local StrokeGrad = Instance.new("UIGradient")
						StrokeGrad.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 235)),
							ColorSequenceKeypoint.new(0.2, Color3.fromRGB(250, 204, 21)),
							ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 115, 10)),
							ColorSequenceKeypoint.new(0.8, Color3.fromRGB(250, 204, 21)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 235)),
						})
						StrokeGrad.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0),
							NumberSequenceKeypoint.new(0.22, 0.35),
							NumberSequenceKeypoint.new(0.5, 0.7),
							NumberSequenceKeypoint.new(0.78, 0.35),
							NumberSequenceKeypoint.new(1, 0),
						})
						StrokeGrad.Parent = CardStroke

						task.spawn(function()
							while Card and Card.Parent do
								StrokeGrad.Rotation = (StrokeGrad.Rotation + 2.5) % 360
								task.wait(0.03)
							end
						end)
					end

					CardPadding.Parent = Card
					CardPadding.PaddingTop = UDim.new(0, 10)
					CardPadding.PaddingBottom = UDim.new(0, 10)
					CardPadding.PaddingLeft = UDim.new(0, 10)
					CardPadding.PaddingRight = UDim.new(0, 10)

					CardLayout.Parent = Card
					CardLayout.FillDirection = Enum.FillDirection.Vertical
					CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
					CardLayout.Padding = UDim.new(0, 6)

					local HeaderFrame = Instance.new("Frame")
					local HeaderLayout = Instance.new("UIListLayout")
					local TitleLabel = Instance.new("TextLabel")

					HeaderFrame.Name = "Header"
					HeaderFrame.Parent = Card
					HeaderFrame.LayoutOrder = 1
					HeaderFrame.BackgroundTransparency = 1
					HeaderFrame.Size = UDim2.new(1, 0, 0, 22)

					HeaderLayout.Parent = HeaderFrame
					HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
					HeaderLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
					HeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
					HeaderLayout.SortOrder = Enum.SortOrder.LayoutOrder
					HeaderLayout.Padding = UDim.new(0, 8)

					TitleLabel.Name = "Title"
					TitleLabel.Parent = HeaderFrame
					TitleLabel.LayoutOrder = 1
					TitleLabel.BackgroundTransparency = 1
					TitleLabel.Size = UDim2.new(0, 0, 0, 20)
					TitleLabel.AutomaticSize = Enum.AutomaticSize.X
					TitleLabel.Font = Enum.Font.BuilderSansBold
					TitleLabel.Text = (cData.Title or "TIER"):upper()
					TitleLabel.TextColor3 = cData.TextColor or curColors['Text & Icon']
					TitleLabel.TextSize = 16
					TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
					TitleLabel.TextYAlignment = Enum.TextYAlignment.Center

					if cData.Badge then
						local BadgeFrame = Instance.new("Frame")
						local BadgeCorner = Instance.new("UICorner")
						local BadgePad = Instance.new("UIPadding")
						local BadgeText = Instance.new("TextLabel")

						BadgeFrame.Name = "Badge"
						BadgeFrame.Parent = HeaderFrame
						BadgeFrame.LayoutOrder = 2
						BadgeFrame.BackgroundColor3 = (cData.AccentColor or curColors['Main']):Lerp(Color3.fromRGB(0, 0, 0), 0.65)
						BadgeFrame.BorderSizePixel = 0
						BadgeFrame.Size = UDim2.new(0, 0, 0, 20)
						BadgeFrame.AutomaticSize = Enum.AutomaticSize.X

						BadgeCorner.CornerRadius = UDim.new(0, 5)
						BadgeCorner.Parent = BadgeFrame

						BadgePad.Parent = BadgeFrame
						BadgePad.PaddingLeft = UDim.new(0, 7)
						BadgePad.PaddingRight = UDim.new(0, 7)

						BadgeText.Name = "BadgeText"
						BadgeText.Parent = BadgeFrame
						BadgeText.BackgroundTransparency = 1
						BadgeText.Size = UDim2.new(1, 0, 1, 0)
						BadgeText.Font = Enum.Font.BuilderSansBold
						BadgeText.Text = tostring(cData.Badge):upper()
						BadgeText.TextColor3 = cData.AccentColor or curColors['Main']
						BadgeText.TextSize = 11.5
						BadgeText.TextYAlignment = Enum.TextYAlignment.Center
					end

					if type(cData.Subtitle) == "table" or (type(cData.Subtitle) == "string" and string.find(cData.Subtitle, "/")) then
						local SubFrame = Instance.new("Frame")
						local SubLayout = Instance.new("UIListLayout")

						SubFrame.Name = "SubtitleRow"
						SubFrame.Parent = Card
						SubFrame.LayoutOrder = 2
						SubFrame.BackgroundTransparency = 1
						SubFrame.Size = UDim2.new(1, 0, 0, 18)

						SubLayout.Parent = SubFrame
						SubLayout.FillDirection = Enum.FillDirection.Horizontal
						SubLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
						SubLayout.VerticalAlignment = Enum.VerticalAlignment.Center
						SubLayout.SortOrder = Enum.SortOrder.LayoutOrder
						SubLayout.Padding = UDim.new(0, 7)

						local items = if type(cData.Subtitle) == "table" then cData.Subtitle else {}
						if type(cData.Subtitle) == "string" then
							for part in string.gmatch(cData.Subtitle, "[^/]+") do
								table.insert(items, (part:gsub("^%s*(.-)%s*$", "%1")))
							end
						end

						for sIdx, sText in ipairs(items) do
							local itemLabel = Instance.new("TextLabel")
							itemLabel.Name = "Item_" .. sIdx
							itemLabel.Parent = SubFrame
							itemLabel.LayoutOrder = sIdx * 2 - 1
							itemLabel.BackgroundTransparency = 1
							itemLabel.Size = UDim2.new(0, 0, 1, 0)
							itemLabel.AutomaticSize = Enum.AutomaticSize.X
							itemLabel.Font = Enum.Font.BuilderSansBold
							itemLabel.Text = sText
							itemLabel.TextColor3 = cData.SubtitleColor or cData.TextColor or curColors['SubText']
							itemLabel.TextSize = 13
							itemLabel.TextYAlignment = Enum.TextYAlignment.Center

							if sIdx < #items then
								local vDiv = Instance.new("Frame")
								vDiv.Name = "VDivider_" .. sIdx
								vDiv.Parent = SubFrame
								vDiv.LayoutOrder = sIdx * 2
								vDiv.BackgroundColor3 = Color3.fromRGB(55, 55, 68)
								vDiv.BorderSizePixel = 0
								vDiv.Size = UDim2.new(0, 1, 0, 10)
							end
						end
					else
						local SubLabel = Instance.new("TextLabel")
						SubLabel.Name = "Subtitle"
						SubLabel.Parent = Card
						SubLabel.LayoutOrder = 2
						SubLabel.BackgroundTransparency = 1
						SubLabel.Size = UDim2.new(1, 0, 0, 18)
						SubLabel.Font = Enum.Font.BuilderSansMedium
						SubLabel.Text = cData.Subtitle or ""
						SubLabel.TextColor3 = cData.SubtitleColor or cData.TextColor or curColors['SubText']
						SubLabel.TextSize = 13
						SubLabel.TextXAlignment = Enum.TextXAlignment.Center
						SubLabel.TextYAlignment = Enum.TextYAlignment.Center
					end

					local Divider = Instance.new("Frame")
					Divider.Name = "Divider"
					Divider.Parent = Card
					Divider.LayoutOrder = 3
					Divider.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
					Divider.BorderSizePixel = 0
					Divider.Size = UDim2.new(1, 0, 0, 1)

					local FeaturesFrame = Instance.new("Frame")
					local FeaturesLayout = Instance.new("UIListLayout")

					FeaturesFrame.Name = "Features"
					FeaturesFrame.Parent = Card
					FeaturesFrame.LayoutOrder = 4
					FeaturesFrame.BackgroundTransparency = 1
					FeaturesFrame.Size = UDim2.new(1, 0, 0, cData.ButtonText and 115 or 145)

					FeaturesLayout.Parent = FeaturesFrame
					FeaturesLayout.SortOrder = Enum.SortOrder.LayoutOrder
					FeaturesLayout.Padding = UDim.new(0, 4)

					if type(cData.Features) == "table" then
						for fIdx, fText in ipairs(cData.Features) do
							local featRow = Instance.new("Frame")
							local featCheck = Instance.new("ImageLabel")
							local featLabel = Instance.new("TextLabel")

							featRow.Name = "Feat_" .. fIdx
							featRow.Parent = FeaturesFrame
							featRow.BackgroundTransparency = 1
							featRow.Size = UDim2.new(1, 0, 0, 20)
							featRow.LayoutOrder = fIdx

							local checkData = gl("check")
							featCheck.Name = "Check"
							featCheck.Parent = featRow
							featCheck.BackgroundTransparency = 1
							featCheck.AnchorPoint = Vector2.new(0, 0.5)
							featCheck.Position = UDim2.new(0, 0, 0.5, 0)
							featCheck.Size = UDim2.new(0, 16, 0, 16)
							featCheck.Image = checkData.Image
							featCheck.ImageRectSize = checkData.ImageRectSize
							featCheck.ImageRectOffset = checkData.ImageRectPosition
							featCheck.ImageColor3 = Color3.fromRGB(255, 255, 255)

							local cleanText = tostring(fText):gsub("^✔️%s*", "")
							featLabel.Name = "Label"
							featLabel.Parent = featRow
							featLabel.BackgroundTransparency = 1
							featLabel.Position = UDim2.new(0, 22, 0, 0)
							featLabel.Size = UDim2.new(1, -22, 1, 0)
							featLabel.Font = Enum.Font.BuilderSansMedium
							featLabel.Text = cleanText
							featLabel.TextColor3 = cData.TextColor or curColors['Text & Icon']
							featLabel.TextSize = 13.5
							featLabel.TextTruncate = Enum.TextTruncate.AtEnd
							featLabel.TextXAlignment = Enum.TextXAlignment.Left
						end
					else
						local DescLabel = Instance.new("TextLabel")
						DescLabel.Name = "Description"
						DescLabel.Parent = FeaturesFrame
						DescLabel.BackgroundTransparency = 1
						DescLabel.Size = UDim2.new(1, 0, 1, 0)
						DescLabel.Font = Enum.Font.BuilderSansMedium
						DescLabel.Text = cData.Desc or ""
						DescLabel.TextColor3 = cData.TextColor or curColors['Text & Icon']
						DescLabel.TextSize = 13
						DescLabel.TextWrapped = true
						DescLabel.TextXAlignment = Enum.TextXAlignment.Left
						DescLabel.TextYAlignment = Enum.TextYAlignment.Top
					end

					if cData.ButtonText then
						local ActionBtn = Instance.new("Frame")
						local ActionBtnCorner = Instance.new("UICorner")
						local ActionBtnStroke = Instance.new("UIStroke")
						local ActionBtnLabel = Instance.new("TextLabel")
						local ActionBtnClick = click(ActionBtn)

						ActionBtn.Name = "ActionButton"
						ActionBtn.Parent = Card
						ActionBtn.LayoutOrder = 5
						ActionBtn.BackgroundColor3 = cData.ButtonBg or Color3.fromRGB(24, 24, 30)
						ActionBtn.BorderSizePixel = 0
						ActionBtn.Size = UDim2.new(1, 0, 0, 30)

						ActionBtnCorner.CornerRadius = UDim.new(0, 6)
						ActionBtnCorner.Parent = ActionBtn

						ActionBtnStroke.Thickness = 1
						ActionBtnStroke.Color = cData.ButtonStroke or cData.AccentColor or curColors['CardBorder']
						ActionBtnStroke.Parent = ActionBtn

						ActionBtnLabel.Name = "Label"
						ActionBtnLabel.Parent = ActionBtn
						ActionBtnLabel.BackgroundTransparency = 1
						ActionBtnLabel.Size = UDim2.new(1, 0, 1, 0)
						ActionBtnLabel.Font = Enum.Font.BuilderSansBold
						ActionBtnLabel.Text = cData.ButtonText
						ActionBtnLabel.TextColor3 = cData.ButtonTextColor or cData.TextColor or curColors['Text & Icon']
						ActionBtnLabel.TextSize = 13

						ActionBtnClick.MouseEnter:Connect(function()
							tw({v = ActionBtn, t = 0.15, g = {BackgroundColor3 = (cData.ButtonBg or Color3.fromRGB(24, 24, 30)):Lerp(Color3.fromRGB(255, 255, 255), 0.15)}}):Play()
						end)
						ActionBtnClick.MouseLeave:Connect(function()
							tw({v = ActionBtn, t = 0.15, g = {BackgroundColor3 = cData.ButtonBg or Color3.fromRGB(24, 24, 30)}}):Play()
						end)
						ActionBtnClick.MouseButton1Click:Connect(function()
							jc(ActionBtn, ActionBtn)
							if cData.Callback then cData.Callback() end
						end)
					end

					table.insert(currentWindowTheme.cards, {
						Background = Card,
						UIStroke = CardStroke,
						Title = nil,
						Desc = nil,
					})
				end

				return Container
			end

			return B
		end

		function Tabs:Line()
			local Line = Instance.new("Frame")
			Line.Name = "TabDivider"
			Line.Parent = TabListFrame
			Line.BackgroundColor3 = curColors['CardBorder']
			Line.BackgroundTransparency = 0.5
			Line.BorderSizePixel = 0
			Line.Size = UDim2.new(1, -12, 0, 1)
			Line.Position = UDim2.new(0, 6, 0, 0)
			return Line
		end

		function Tabs:SelectTab(nameOrIndex)
			if type(nameOrIndex) == "number" then
				if currentWindowTheme.tabs[nameOrIndex] and currentWindowTheme.tabs[nameOrIndex].Select then
					currentWindowTheme.tabs[nameOrIndex].Select()
				end
			else
				for _, t in ipairs(currentWindowTheme.tabs or {}) do
					if t.TabTitle and string.lower(t.TabTitle) == string.lower(tostring(nameOrIndex)) and t.Select then
						t.Select()
						break
					end
				end
			end
		end

		function Tabs:Tab(tabOptions)
			local TabTitle = tabOptions.Title or 'Tab'
			local Icon = tabOptions.Icon or 'house'

			local TabBtn = Instance.new("Frame")
			local TabCorner = Instance.new("UICorner")
			local TabIcon = Instance.new("ImageLabel")
			local TabTitleLabel = Instance.new("TextLabel")

			TabBtn.Name = "Tab_" .. TabTitle
			TabBtn.Parent = TabListFrame
			TabBtn.BackgroundColor3 = curColors['MainDark']
			TabBtn.BackgroundTransparency = 1
			TabBtn.BorderSizePixel = 0
			TabBtn.Size = UDim2.new(1, 0, 0, 40)

			TabCorner.CornerRadius = UDim.new(0, 6)
			TabCorner.Parent = TabBtn

			TabIcon.Name = "TabIcon"
			TabIcon.Parent = TabBtn
			TabIcon.AnchorPoint = Vector2.new(0, 0.5)
			TabIcon.BackgroundTransparency = 1
			TabIcon.Position = UDim2.new(0, 12, 0.5, 0)
			TabIcon.Size = UDim2.new(0, 20, 0, 20)
			local ic = gl(Icon)
			TabIcon.Image = ic.Image
			TabIcon.ImageRectSize = ic.ImageRectSize
			TabIcon.ImageRectOffset = ic.ImageRectPosition
			TabIcon.ImageColor3 = curColors['SubText']

			TabTitleLabel.Name = "Title"
			TabTitleLabel.Parent = TabBtn
			TabTitleLabel.AnchorPoint = Vector2.new(0, 0.5)
			TabTitleLabel.BackgroundTransparency = 1
			TabTitleLabel.Position = UDim2.new(0, 42, 0.5, 0)
			TabTitleLabel.Size = UDim2.new(1, -48, 0, 20)
			TabTitleLabel.Font = Enum.Font.BuilderSansBold
			TabTitleLabel.Text = TabTitle
			TabTitleLabel.TextColor3 = curColors['SubText']
			TabTitleLabel.TextSize = 15
			TabTitleLabel.TextXAlignment = Enum.TextXAlignment.Left

			local InPage_1 = Instance.new("Frame")
			InPage_1.Name = "InPage_" .. TabTitle
			InPage_1.Parent = Page_1
			InPage_1.BackgroundTransparency = 1
			InPage_1.Size = UDim2.new(1, 0, 1, 0)
			InPage_1.Visible = false

			local SubTabsBar = Instance.new("Frame")
			local SubTabsLayout = Instance.new("UIListLayout")
			SubTabsBar.Name = "SubTabsBar"
			SubTabsBar.Parent = InPage_1
			SubTabsBar.BackgroundTransparency = 1
			SubTabsBar.Position = UDim2.new(0, 6, 0, 0)
			SubTabsBar.Size = UDim2.new(1, -12, 0, 34)
			SubTabsBar.Visible = false

			SubTabsLayout.Parent = SubTabsBar
			SubTabsLayout.FillDirection = Enum.FillDirection.Horizontal
			SubTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
			SubTabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			SubTabsLayout.Padding = UDim.new(0, 8)

			local PageScroll = Instance.new("ScrollingFrame")
			local PageLayout = Instance.new("UIListLayout")
			local PagePadding_1 = Instance.new("UIPadding")

			PageScroll.Name = "ScrollingFrame"
			PageScroll.Parent = InPage_1
			PageScroll.Active = true
			PageScroll.BackgroundTransparency = 1
			PageScroll.BorderSizePixel = 0
			PageScroll.Position = UDim2.new(0, 0, 0, 0)
			PageScroll.Size = UDim2.new(1, 0, 1, 0)
			PageScroll.ScrollBarThickness = 3
			PageScroll.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 200)
			PageScroll.ClipsDescendants = true
			pcall(function() PageScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

			PageLayout.Parent = PageScroll
			PageLayout.Padding = UDim.new(0, 8)
			PageLayout.SortOrder = Enum.SortOrder.LayoutOrder

			PagePadding_1.Parent = PageScroll
			PagePadding_1.PaddingTop = UDim.new(0, 2)
			PagePadding_1.PaddingBottom = UDim.new(0, 12)
			PagePadding_1.PaddingLeft = UDim.new(0, 6)
			PagePadding_1.PaddingRight = UDim.new(0, 6)

			changecanvas(PageScroll, PageLayout, 10)

			local ClickTab = click(TabBtn)

			local tabData = {
				Page = InPage_1,
				Scroll = PageScroll,
				Button = TabBtn,
				Title = TabTitle,
				Icon = TabIcon,
				TitleLabel = TabTitleLabel
			}

			table.insert(self.List, tabData)
			local MyIndex = #self.List

			local function selectThisTab()
				Tabs.ActiveTabName = TabTitle
				for _, item in ipairs(self.List) do
					if item.Page then item.Page.Visible = false end
					tw({v = item.Button, t = 0.16, g = {BackgroundTransparency = 1}}):Play()
					tw({v = item.Icon, t = 0.16, g = {ImageColor3 = curColors['SubText']}}):Play()
					tw({v = item.TitleLabel, t = 0.16, g = {TextColor3 = curColors['SubText']}}):Play()
				end

				InPage_1.Position = UDim2.new(0, 4, 0, 0)
				InPage_1.Visible = true
				tw({v = InPage_1, t = 0.18, s = Enum.EasingStyle.Cubic, d = "Out", g = {Position = UDim2.new(0, 0, 0, 0)}}):Play()

				tw({v = TabBtn, t = 0.18, g = {BackgroundTransparency = 0, BackgroundColor3 = curColors['MainDark']}}):Play()
				tw({v = TabIcon, t = 0.18, g = {ImageColor3 = Color3.fromRGB(255, 255, 255)}}):Play()
				tw({v = TabTitleLabel, t = 0.18, g = {TextColor3 = Color3.fromRGB(255, 255, 255)}}):Play()
			end

			tabData.Select = selectThisTab
			ClickTab.MouseButton1Click:Connect(selectThisTab)

			TabBtn.MouseEnter:Connect(function()
				if not InPage_1.Visible then
					local c = currentWindowTheme.colors or curColors
					tw({v = TabBtn, t = 0.15, g = {BackgroundTransparency = 0.7, BackgroundColor3 = c['MainDark']}}):Play()
					tw({v = TabTitleLabel, t = 0.15, g = {TextColor3 = Color3.fromRGB(255, 255, 255)}}):Play()
				end
			end)
			TabBtn.MouseLeave:Connect(function()
				if not InPage_1.Visible then
					local c = currentWindowTheme.colors or curColors
					tw({v = TabBtn, t = 0.15, g = {BackgroundTransparency = 1}}):Play()
					tw({v = TabTitleLabel, t = 0.15, g = {TextColor3 = c['SubText']}}):Play()
				end
			end)

			if MyIndex == 1 then
				task.spawn(function()
					task.wait(0.05)
					selectThisTab()
				end)
			end

			local tabMeta = {
				TabTitle = TabTitle,
				SelectTab = selectThisTab,
				Scroll = PageScroll
			}
			local BaseBuilder = createControlBuilder(PageScroll, tabMeta)

			local Func = {
				Scroll = PageScroll,
				Page = InPage_1,
				Select = selectThisTab,
				SubTabsList = {}
			}

			for k, v in pairs(BaseBuilder) do
				Func[k] = function(self, ...) return v(BaseBuilder, ...) end
			end

			function Func:SubTab(subTitleOrOptions)
				local sTitle = (type(subTitleOrOptions) == "table" and subTitleOrOptions.Title) or tostring(subTitleOrOptions)
				SubTabsBar.Visible = true
				PageScroll.Position = UDim2.new(0, 0, 0, 38)
				PageScroll.Size = UDim2.new(1, 0, 1, -38)

				local subBtn = Instance.new("Frame")
				local subBtnCorner = Instance.new("UICorner")
				local subBtnStroke = Instance.new("UIStroke")
				local subBtnLabel = Instance.new("TextLabel")
				local subBtnClick = click(subBtn)

				subBtn.Name = "SubTab_" .. sTitle
				subBtn.Parent = SubTabsBar
				subBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
				subBtn.BorderSizePixel = 0
				subBtn.Size = UDim2.new(0, 85, 0, 32)
				subBtn.AutomaticSize = Enum.AutomaticSize.X

				subBtnCorner.CornerRadius = UDim.new(0, 6)
				subBtnCorner.Parent = subBtn

				subBtnStroke.Color = curColors['CardBorder']
				subBtnStroke.Thickness = 1
				subBtnStroke.Parent = subBtn

				subBtnLabel.Name = "Label"
				subBtnLabel.Parent = subBtn
				subBtnLabel.BackgroundTransparency = 1
				subBtnLabel.Size = UDim2.new(1, 0, 1, 0)
				subBtnLabel.Font = Enum.Font.BuilderSansBold
				subBtnLabel.Text = sTitle
				subBtnLabel.TextColor3 = curColors['SubText']
				subBtnLabel.TextSize = 15

				local subPad = Instance.new("UIPadding")
				subPad.Parent = subBtn
				subPad.PaddingLeft = UDim.new(0, 16)
				subPad.PaddingRight = UDim.new(0, 16)

				local SubScroll = Instance.new("ScrollingFrame")
				local SubLayout = Instance.new("UIListLayout")
				local SubPadding = Instance.new("UIPadding")

				SubScroll.Name = "SubScroll_" .. sTitle
				SubScroll.Parent = InPage_1
				SubScroll.Active = true
				SubScroll.BackgroundTransparency = 1
				SubScroll.BorderSizePixel = 0
				SubScroll.Position = UDim2.new(0, 0, 0, 38)
				SubScroll.Size = UDim2.new(1, 0, 1, -38)
				SubScroll.ScrollBarThickness = 3
				SubScroll.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 200)
				SubScroll.Visible = false
				SubScroll.ClipsDescendants = true
			pcall(function() SubScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

				SubLayout.Parent = SubScroll
				SubLayout.Padding = UDim.new(0, 8)
				SubLayout.SortOrder = Enum.SortOrder.LayoutOrder

				SubPadding.Parent = SubScroll
				SubPadding.PaddingTop = UDim.new(0, 2)
				SubPadding.PaddingBottom = UDim.new(0, 12)
				SubPadding.PaddingLeft = UDim.new(0, 6)
				SubPadding.PaddingRight = UDim.new(0, 6)

				changecanvas(SubScroll, SubLayout, 10)

				local subObj
				local function selectSub()
					PageScroll.Visible = false
					local c = currentWindowTheme.colors or curColors
					for _, st in ipairs(Func.SubTabsList) do
						st.Scroll.Visible = false
						st.IsActive = false
						tw({v = st.Button, t = 0.15, g = {BackgroundColor3 = c['Card']}}):Play()
						tw({v = st.Label, t = 0.15, g = {TextColor3 = c['SubText']}}):Play()
						tw({v = st.Stroke, t = 0.15, g = {Color = c['CardBorder']}}):Play()
					end
					SubScroll.Visible = true
					if subObj then subObj.IsActive = true end
					tw({v = subBtn, t = 0.15, g = {BackgroundColor3 = c['Main']}}):Play()
					tw({v = subBtnLabel, t = 0.15, g = {TextColor3 = c['Background']}}):Play()
					tw({v = subBtnStroke, t = 0.15, g = {Color = c['Main']}}):Play()

					task.defer(function()
						for _, sec in ipairs(currentWindowTheme.sections or {}) do
							if sec.Scroll == SubScroll and sec.UpdateHeight then
								sec.UpdateHeight()
							end
						end
					end)
					task.delay(0.06, function()
						for _, sec in ipairs(currentWindowTheme.sections or {}) do
							if sec.Scroll == SubScroll and sec.UpdateHeight then
								sec.UpdateHeight()
							end
						end
					end)
					task.delay(0.18, function()
						for _, sec in ipairs(currentWindowTheme.sections or {}) do
							if sec.Scroll == SubScroll and sec.UpdateHeight then
								sec.UpdateHeight()
							end
						end
					end)
				end

				local subMeta = {
					TabTitle = TabTitle,
					SubTabTitle = sTitle,
					SelectTab = selectThisTab,
					SelectSubTab = selectSub,
					Scroll = SubScroll
				}
				local subBuilder = createControlBuilder(SubScroll, subMeta)

				subObj = {
					Scroll = SubScroll,
					Button = subBtn,
					Label = subBtnLabel,
					Stroke = subBtnStroke,
					IsActive = false,
					Select = selectSub
				}
				table.insert(Func.SubTabsList, subObj)
				table.insert(currentWindowTheme.subTabs, subObj)

				subBtnClick.MouseButton1Click:Connect(selectSub)

				if #Func.SubTabsList == 1 then
					task.defer(selectSub)
				end

				local ReturnSub = {
					Scroll = SubScroll,
					Select = selectSub
				}
				for k, v in pairs(subBuilder) do
					ReturnSub[k] = function(self, ...) return v(subBuilder, ...) end
				end
				return ReturnSub
			end

			return Func
		end

		local Notification = Instance.new("Frame")
		local UIPaddingNotif = Instance.new("UIPadding")
		local UIListLayoutNotif = Instance.new("UIListLayout")

		Notification.Name = "Notification"
		Notification.Parent = ScreenGui
		Notification.AnchorPoint = Vector2.new(1, 1)
		Notification.BackgroundTransparency = 1
		Notification.BorderSizePixel = 0
		Notification.Position = UDim2.new(1, -14, 1, -14)
		Notification.Size = UDim2.new(0, 310, 0, 360)
		Notification.ZIndex = 120

		UIPaddingNotif.Parent = Notification
		UIPaddingNotif.PaddingBottom = UDim.new(0, 8)

		UIListLayoutNotif.Parent = Notification
		UIListLayoutNotif.HorizontalAlignment = Enum.HorizontalAlignment.Right
		UIListLayoutNotif.SortOrder = Enum.SortOrder.LayoutOrder
		UIListLayoutNotif.VerticalAlignment = Enum.VerticalAlignment.Bottom
		UIListLayoutNotif.Padding = UDim.new(0, 6)

		local uiInitTime = tick()
		Tabs._suppressNotifications = false

		function Tabs:ClearNotifications()
			pcall(function()
				for _, child in ipairs(Notification:GetChildren()) do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
			end)
		end

		function Tabs:Notify(p)
			if Tabs._suppressNotifications then
				return
			end
			if (tick() - uiInitTime) < 1.0 and not (p and p.Force) then
				return
			end
			local NotifTitle = p.Title or 'Aether'
			local Desc = p.Desc or ''
			local Time = p.Time or 3.5
			local Type = p.Type or 'normal'

			local colorMap = {
				error = Color3.fromRGB(255, 60, 70),
				warning = Color3.fromRGB(255, 175, 40),
				normal = Color3.fromRGB(255, 255, 255)
			}
			local accent = colorMap[Type] or Color3.fromRGB(255, 255, 255)

			local NotifCard = Instance.new("CanvasGroup")
			local CardCorner = Instance.new("UICorner")
			local CardStroke = Instance.new("UIStroke")
			local Indicator = Instance.new("Frame")
			local IndicatorCorner = Instance.new("UICorner")
			local TextContainer = Instance.new("Frame")
			local TextPadding = Instance.new("UIPadding")
			local TextLayout = Instance.new("UIListLayout")
			local TitleLabel = Instance.new("TextLabel")
			local DescLabel = Instance.new("TextLabel")

			NotifCard.Name = "NotifCard"
			NotifCard.Parent = Notification
			NotifCard.BackgroundColor3 = curColors['Card']
			NotifCard.BorderSizePixel = 0
			NotifCard.Size = UDim2.new(1, 0, 0, 0)
			NotifCard.AutomaticSize = Enum.AutomaticSize.Y
			NotifCard.ClipsDescendants = true
			NotifCard.GroupTransparency = 1

			CardCorner.CornerRadius = UDim.new(0, 7)
			CardCorner.Parent = NotifCard

			CardStroke.Color = curColors['CardBorder']
			CardStroke.Thickness = 1.2
			CardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			CardStroke.Transparency = 1
			CardStroke.Parent = NotifCard

			Indicator.Name = "Indicator"
			Indicator.Parent = NotifCard
			Indicator.BackgroundColor3 = accent
			Indicator.BorderSizePixel = 0
			Indicator.Position = UDim2.new(0, 0, 0, 0)
			Indicator.Size = UDim2.new(0, 3.5, 1, 0)

			IndicatorCorner.CornerRadius = UDim.new(0, 2)
			IndicatorCorner.Parent = Indicator

			TextContainer.Name = "TextContainer"
			TextContainer.Parent = NotifCard
			TextContainer.BackgroundTransparency = 1
			TextContainer.Position = UDim2.new(0, 14, 0, 0)
			TextContainer.Size = UDim2.new(1, -26, 0, 0)
			TextContainer.AutomaticSize = Enum.AutomaticSize.Y

			TextPadding.Parent = TextContainer
			TextPadding.PaddingTop = UDim.new(0, 9)
			TextPadding.PaddingBottom = UDim.new(0, 11)

			TextLayout.Parent = TextContainer
			TextLayout.SortOrder = Enum.SortOrder.LayoutOrder
			TextLayout.Padding = UDim.new(0, 3)

			TitleLabel.Name = "Title"
			TitleLabel.Parent = TextContainer
			TitleLabel.BackgroundTransparency = 1
			TitleLabel.Size = UDim2.new(1, 0, 0, 0)
			TitleLabel.AutomaticSize = Enum.AutomaticSize.Y
			TitleLabel.Font = Enum.Font.BuilderSansBold
			TitleLabel.Text = tostring(NotifTitle)
			TitleLabel.TextColor3 = curColors['Text & Icon']
			TitleLabel.TextSize = 14
			TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
			TitleLabel.TextWrapped = true
			TitleLabel.LayoutOrder = 1

			if Desc ~= '' then
				DescLabel.Name = "Desc"
				DescLabel.Parent = TextContainer
				DescLabel.BackgroundTransparency = 1
				DescLabel.Size = UDim2.new(1, 0, 0, 0)
				DescLabel.AutomaticSize = Enum.AutomaticSize.Y
				DescLabel.Font = Enum.Font.BuilderSansMedium
				DescLabel.Text = tostring(Desc)
				DescLabel.TextColor3 = curColors['SubText']
				DescLabel.TextSize = 12.5
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				DescLabel.TextWrapped = true
				DescLabel.LayoutOrder = 2
			end

			local ProgressBar = Instance.new("Frame")
			ProgressBar.Name = "ProgressBar"
			ProgressBar.Parent = NotifCard
			ProgressBar.BackgroundColor3 = accent
			ProgressBar.BorderSizePixel = 0
			ProgressBar.Position = UDim2.new(0, 0, 1, -2)
			ProgressBar.Size = UDim2.new(1, 0, 0, 2)
			tw({v = ProgressBar, t = Time, s = Enum.EasingStyle.Linear, d = "Out", g = {Size = UDim2.new(0, 0, 0, 2)}}):Play()

			NotifCard.Position = UDim2.new(1, 30, 0, 0)
			tw({v = NotifCard, t = 0.25, s = Enum.EasingStyle.Cubic, d = "Out", g = {GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0)}}):Play()
			tw({v = CardStroke, t = 0.25, s = Enum.EasingStyle.Cubic, d = "Out", g = {Transparency = 0}}):Play()

			task.delay(Time, function()
				local close = tw({v = NotifCard, t = 0.22, s = Enum.EasingStyle.Quad, d = "In", g = {GroupTransparency = 1, Position = UDim2.new(1, 30, 0, 0)}})
				local closeStroke = tw({v = CardStroke, t = 0.22, s = Enum.EasingStyle.Quad, d = "In", g = {Transparency = 1}})
				close:Play()
				closeStroke:Play()
				close.Completed:Connect(function() NotifCard:Destroy() end)
			end)
		end

		function Tabs:Dialog(p)
			local Button1 = (p.Button1 and p.Button1.Callback) or function() end
			local Button2 = (p.Button2 and p.Button2.Callback) or function() end
			local DialogTitle = p.Title or 'Notice'
			local TitleButton1 = (p.Button1 and p.Button1.Title) or 'Confirm'
			local TitleButton2 = (p.Button2 and p.Button2.Title) or 'Cancel'

			local Dialog = Instance.new("Frame")
			local DialogCorner = Instance.new("UICorner")
			local DialogCard = Instance.new("Frame")
			local CardCorner = Instance.new("UICorner")
			local CardStroke = Instance.new("UIStroke")
			local TitleLabel = Instance.new("TextLabel")
			local BtnFrame = Instance.new("Frame")
			local BtnLayout = Instance.new("UIListLayout")
			local B1 = Instance.new("TextButton")
			local B1Corner = Instance.new("UICorner")
			local B2 = Instance.new("TextButton")
			local B2Corner = Instance.new("UICorner")

			Dialog.Name = "Dialog"
			Dialog.Parent = Background_1
			Dialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			Dialog.BackgroundTransparency = 0.5
			Dialog.BorderSizePixel = 0
			Dialog.Size = UDim2.new(1, 0, 1, 0)
			Dialog.ZIndex = 80

			DialogCorner.CornerRadius = UDim.new(0, 10)
			DialogCorner.Parent = Dialog

			DialogCard.Name = "Card"
			DialogCard.Parent = Dialog
			DialogCard.AnchorPoint = Vector2.new(0.5, 0.5)
			DialogCard.BackgroundColor3 = curColors['Card']
			DialogCard.BorderSizePixel = 0
			DialogCard.Position = UDim2.new(0.5, 0, 0.5, 0)
			DialogCard.Size = UDim2.new(0, 280, 0, 115)

			CardCorner.CornerRadius = UDim.new(0, 8)
			CardCorner.Parent = DialogCard

			CardStroke.Color = curColors['CardBorder']
			CardStroke.Thickness = 1
			CardStroke.Parent = DialogCard

			TitleLabel.Parent = DialogCard
			TitleLabel.BackgroundTransparency = 1
			TitleLabel.Position = UDim2.new(0, 16, 0, 14)
			TitleLabel.Size = UDim2.new(1, -32, 0, 36)
			TitleLabel.Font = Enum.Font.BuilderSansBold
			TitleLabel.RichText = true
			TitleLabel.Text = DialogTitle
			TitleLabel.TextColor3 = curColors['Text & Icon']
			TitleLabel.TextSize = 14
			TitleLabel.TextWrapped = true

			BtnFrame.Parent = DialogCard
			BtnFrame.AnchorPoint = Vector2.new(0.5, 1)
			BtnFrame.BackgroundTransparency = 1
			BtnFrame.Position = UDim2.new(0.5, 0, 1, -12)
			BtnFrame.Size = UDim2.new(1, -32, 0, 30)

			BtnLayout.Parent = BtnFrame
			BtnLayout.FillDirection = Enum.FillDirection.Horizontal
			BtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			BtnLayout.Padding = UDim.new(0, 12)

			B1.Parent = BtnFrame
			B1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			B1.BorderSizePixel = 0
			B1.Size = UDim2.new(0.48, 0, 1, 0)
			B1.Font = Enum.Font.BuilderSansBold
			B1.Text = TitleButton1
			B1.TextColor3 = Color3.fromRGB(15, 15, 18)
			B1.TextSize = 13

			B1Corner.CornerRadius = UDim.new(0, 4)
			B1Corner.Parent = B1

			B2.Parent = BtnFrame
			B2.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
			B2.BorderSizePixel = 0
			B2.Size = UDim2.new(0.48, 0, 1, 0)
			B2.Font = Enum.Font.BuilderSansBold
			B2.Text = TitleButton2
			B2.TextColor3 = curColors['SubText']
			B2.TextSize = 13

			B2Corner.CornerRadius = UDim.new(0, 4)
			B2Corner.Parent = B2

			B1.MouseButton1Click:Connect(function()
				pcall(Button1)
				Dialog:Destroy()
			end)

			B2.MouseButton1Click:Connect(function()
				pcall(Button2)
				Dialog:Destroy()
			end)
		end

		do
			Close_1.MouseButton1Click:Connect(function()
				Tabs:Dialog({
					Title = "Close Aether interface?",
					Button1 = {
						Title = 'Close',
						Callback = function() ScreenGui:Destroy() end,
					},
					Button2 = { Title = 'Cancel' }
				})
			end)

			Minisize_1.MouseButton1Click:Connect(function()
				playClickSound()
				setUIVisibility(false)
			end)

			local toggleConn
			toggleConn = U.InputBegan:Connect(function(input)
				if (input.KeyCode == Enum.KeyCode.LeftControl or (Tabs.UIToggleKeybind and input.KeyCode == Tabs.UIToggleKeybind)) then
					if not U:GetFocusedTextBox() then setUIVisibility(isHidden) end
				end
			end)

			function Tabs:Toggle() setUIVisibility(isHidden) end
			function Tabs:SetVisible(vis) setUIVisibility(vis) end

			ScreenGui.Destroying:Connect(function()
				pcall(function()
					if toggleConn and toggleConn.Connected then
						toggleConn:Disconnect()
					end
				end)
				pcall(function()
					if resizeInputChangedConn and resizeInputChangedConn.Connected then
						resizeInputChangedConn:Disconnect()
					end
				end)
				pcall(function()
					if resizeInputEndedConn and resizeInputEndedConn.Connected then
						resizeInputEndedConn:Disconnect()
					end
				end)
				pcall(function()
					if LocalPlayer then
						LocalPlayer:GetMouse().Icon = ""
					end
				end)
				pcall(function()
					if BackgroundMusic then
						BackgroundMusic:Stop()
						BackgroundMusic:Destroy()
					end
					if ClickSound then
						ClickSound:Destroy()
					end
				end)
			end)
		end

		local HomeTab = Tabs:Tab({
			Title = "Home",
			Icon = "house"
		})

		local MainSub = HomeTab:SubTab("Main")
		local SettingsSub = HomeTab:SubTab("Settings")
		local ThemesSub = HomeTab:SubTab("Themes")

		Tabs.HomeTab = HomeTab
		Tabs.MainSub = MainSub
		Tabs.PricingSub = MainSub
		Tabs.SettingsSub = SettingsSub
		Tabs.ThemesSub = ThemesSub

		local mainScroll = MainSub.Scroll
		mainScroll.ScrollBarThickness = 2
		pcall(function() mainScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

		local HeroCard = Instance.new("Frame")
		local HeroCorner = Instance.new("UICorner")
		local HeroStroke = Instance.new("UIStroke")
		local HeroPadding = Instance.new("UIPadding")

		HeroCard.Name = "HeroCard"
		HeroCard.Parent = mainScroll
		HeroCard.BackgroundColor3 = curColors['Card']
		HeroCard.BorderSizePixel = 0
		HeroCard.Size = UDim2.new(1, 0, 0, 115)
		HeroCard.ClipsDescendants = true
		HeroCard.LayoutOrder = 1

		HeroCorner.CornerRadius = UDim.new(0, 10)
		HeroCorner.Parent = HeroCard

		HeroStroke.Color = curColors['CardBorder']
		HeroStroke.Thickness = 1
		HeroStroke.Parent = HeroCard

		HeroPadding.Parent = HeroCard
		HeroPadding.PaddingBottom = UDim.new(0, 14)
		HeroPadding.PaddingLeft = UDim.new(0, 16)
		HeroPadding.PaddingRight = UDim.new(0, 16)
		HeroPadding.PaddingTop = UDim.new(0, 14)

		table.insert(currentWindowTheme.cards, {
			Background = HeroCard,
			UIStroke = HeroStroke,
			Title = nil,
			Desc = nil,
		})

		local HeroLeft = Instance.new("Frame")
		HeroLeft.Name = "HeroLeft"
		HeroLeft.Parent = HeroCard
		HeroLeft.AnchorPoint = Vector2.new(0, 0.5)
		HeroLeft.BackgroundTransparency = 1
		HeroLeft.Position = UDim2.new(0, 0, 0.5, 0)
		HeroLeft.Size = UDim2.new(0.6, 0, 0, 84)

		local WelcomeBack = Instance.new("TextLabel")
		WelcomeBack.Name = "WelcomeBack"
		WelcomeBack.Parent = HeroLeft
		WelcomeBack.BackgroundTransparency = 1
		WelcomeBack.Position = UDim2.new(0, 0, 0, 0)
		WelcomeBack.Size = UDim2.new(1, 0, 0, 16)
		WelcomeBack.Font = Enum.Font.BuilderSansMedium
		WelcomeBack.Text = "Welcome back,"
		WelcomeBack.TextColor3 = curColors['SubText']
		WelcomeBack.TextSize = 13
		WelcomeBack.TextXAlignment = Enum.TextXAlignment.Left

		local PlayerTitle = Instance.new("TextLabel")
		PlayerTitle.Name = "PlayerTitle"
		PlayerTitle.Parent = HeroLeft
		PlayerTitle.BackgroundTransparency = 1
		PlayerTitle.Position = UDim2.new(0, 0, 0, 16)
		PlayerTitle.Size = UDim2.new(1, 0, 0, 26)
		PlayerTitle.Font = Enum.Font.BuilderSansBold
		PlayerTitle.RichText = true
		local displayName = (LocalPlayer and LocalPlayer.DisplayName) or "Player"
		PlayerTitle.Text = displayName .. ' 👋'
		PlayerTitle.TextColor3 = curColors['Text & Icon']
		PlayerTitle.TextSize = 22
		PlayerTitle.TextXAlignment = Enum.TextXAlignment.Left

		Tabs._playerTitle = PlayerTitle

		local ReadyLabel = Instance.new("TextLabel")
		ReadyLabel.Name = "ReadyLabel"
		ReadyLabel.Parent = HeroLeft
		ReadyLabel.BackgroundTransparency = 1
		ReadyLabel.Position = UDim2.new(0, 0, 0, 48)
		ReadyLabel.Size = UDim2.new(1, 0, 0, 18)
		ReadyLabel.Font = Enum.Font.BuilderSansBold
		ReadyLabel.Text = "Aether Studios is ready."
		ReadyLabel.TextColor3 = curColors['Text & Icon']
		ReadyLabel.TextSize = 14
		ReadyLabel.TextXAlignment = Enum.TextXAlignment.Left

		local ReadyDesc = Instance.new("TextLabel")
		ReadyDesc.Name = "ReadyDesc"
		ReadyDesc.Parent = HeroLeft
		ReadyDesc.BackgroundTransparency = 1
		ReadyDesc.Position = UDim2.new(0, 0, 0, 68)
		ReadyDesc.Size = UDim2.new(1, 0, 0, 16)
		ReadyDesc.Font = Enum.Font.BuilderSansMedium
		ReadyDesc.Text = "Thank you for using Aether!"
		ReadyDesc.TextColor3 = curColors['SubText']
		ReadyDesc.TextSize = 13
		ReadyDesc.TextXAlignment = Enum.TextXAlignment.Left

		local HeroRight = Instance.new("Frame")
		HeroRight.Name = "HeroRight"
		HeroRight.Parent = HeroCard
		HeroRight.AnchorPoint = Vector2.new(1, 0.5)
		HeroRight.BackgroundTransparency = 1
		HeroRight.Position = UDim2.new(1, 0, 0.5, 0)
		HeroRight.Size = UDim2.new(0.4, 0, 0, 56)

		local AvatarCircle = Instance.new("Frame")
		local AvatarCorner = Instance.new("UICorner")
		local AvatarStroke = Instance.new("UIStroke")
		local AvatarImg = Instance.new("ImageLabel")
		local AvatarImgCorner = Instance.new("UICorner")
		local OnlineDot = Instance.new("Frame")
		local OnlineDotCorner = Instance.new("UICorner")

		AvatarCircle.Name = "AvatarCircle"
		AvatarCircle.Parent = HeroRight
		AvatarCircle.AnchorPoint = Vector2.new(0, 0.5)
		AvatarCircle.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
		AvatarCircle.BorderSizePixel = 0
		AvatarCircle.Position = UDim2.new(0, 0, 0.5, 0)
		AvatarCircle.Size = UDim2.new(0, 56, 0, 56)

		AvatarCorner.CornerRadius = UDim.new(1, 0)
		AvatarCorner.Parent = AvatarCircle

		AvatarStroke.Color = Color3.fromRGB(60, 60, 70)
		AvatarStroke.Thickness = 1.5
		AvatarStroke.Parent = AvatarCircle

		AvatarImg.Name = "AvatarImg"
		AvatarImg.Parent = AvatarCircle
		AvatarImg.BackgroundTransparency = 1
		AvatarImg.Size = UDim2.new(1, 0, 1, 0)
		AvatarImg.Image = (LocalPlayer and "rbxthumb://type=AvatarHeadShot&id="..LocalPlayer.UserId.."&w=150&h=150") or "rbxassetid://10747373176"

		AvatarImgCorner.CornerRadius = UDim.new(1, 0)
		AvatarImgCorner.Parent = AvatarImg

		Tabs._avatarImg = AvatarImg

		OnlineDot.Name = "OnlineDot"
		OnlineDot.Parent = AvatarCircle
		OnlineDot.AnchorPoint = Vector2.new(1, 1)
		OnlineDot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		OnlineDot.BorderSizePixel = 0
		OnlineDot.Position = UDim2.new(1, 2, 1, 2)
		OnlineDot.Size = UDim2.new(0, 12, 0, 12)
		OnlineDot.ZIndex = 5

		OnlineDotCorner.CornerRadius = UDim.new(1, 0)
		OnlineDotCorner.Parent = OnlineDot

		local ProfileInfo = Instance.new("Frame")
		ProfileInfo.Name = "ProfileInfo"
		ProfileInfo.Parent = HeroRight
		ProfileInfo.AnchorPoint = Vector2.new(0, 0.5)
		ProfileInfo.BackgroundTransparency = 1
		ProfileInfo.Position = UDim2.new(0, 68, 0.5, 0)
		ProfileInfo.Size = UDim2.new(1, -68, 0, 56)

		local ProfileName = Instance.new("TextLabel")
		ProfileName.Name = "Name"
		ProfileName.Parent = ProfileInfo
		ProfileName.BackgroundTransparency = 1
		ProfileName.Position = UDim2.new(0, 0, 0, 0)
		ProfileName.Size = UDim2.new(1, 0, 0, 18)
		ProfileName.Font = Enum.Font.BuilderSansBold
		ProfileName.Text = (LocalPlayer and LocalPlayer.Name) or "Player"
		ProfileName.TextColor3 = curColors['Text & Icon']
		ProfileName.TextSize = 15
		ProfileName.TextXAlignment = Enum.TextXAlignment.Left

		Tabs._profileName = ProfileName

		local SubRowHero = Instance.new("Frame")
		local SubTierLabelHero = Instance.new("TextLabel")
		local SubExpiresLabelHero = Instance.new("TextLabel")

		SubRowHero.Name = "SubscriptionRow"
		SubRowHero.Parent = ProfileInfo
		SubRowHero.BackgroundTransparency = 1
		SubRowHero.Position = UDim2.new(0, 0, 0, 20)
		SubRowHero.Size = UDim2.new(1, 0, 0, 36)

		SubTierLabelHero.Name = "SubTierLabel"
		SubTierLabelHero.Parent = SubRowHero
		SubTierLabelHero.BackgroundTransparency = 1
		SubTierLabelHero.Position = UDim2.new(0, 0, 0, 0)
		SubTierLabelHero.Size = UDim2.new(1, 0, 0, 18)
		SubTierLabelHero.Font = Enum.Font.BuilderSansMedium
		SubTierLabelHero.RichText = true
		SubTierLabelHero.Text = '<font color="rgb(180,180,195)">Subscription: </font><font color="rgb(255,255,255)"><b>Free</b></font>'
		SubTierLabelHero.TextSize = 13
		SubTierLabelHero.TextXAlignment = Enum.TextXAlignment.Left

		SubExpiresLabelHero.Name = "SubExpiresLabel"
		SubExpiresLabelHero.Parent = SubRowHero
		SubExpiresLabelHero.BackgroundTransparency = 1
		SubExpiresLabelHero.Position = UDim2.new(0, 0, 0, 18)
		SubExpiresLabelHero.Size = UDim2.new(1, 0, 0, 18)
		SubExpiresLabelHero.Font = Enum.Font.BuilderSansMedium
		SubExpiresLabelHero.RichText = true
		SubExpiresLabelHero.Text = '<font color="rgb(180,180,195)">Expires at: </font><font color="rgb(255,255,255)">0 seconds</font>'
		SubExpiresLabelHero.TextSize = 13
		SubExpiresLabelHero.TextXAlignment = Enum.TextXAlignment.Left

		Tabs._subTierHero = SubTierLabelHero
		Tabs._subExpiresHero = SubExpiresLabelHero

		local PricingSec = MainSub:Section({ Title = "Available Key Tiers & Subscriptions", LayoutOrder = 2 })

		PricingSec:PricingCards({
			{
				Title = "Free",
				Badge = "12-24H",
				Subtitle = "Free Key Checkpoint",
				TextColor = Color3.fromRGB(255, 255, 255),
				AccentColor = Color3.fromRGB(255, 255, 255),
				BorderColor = Color3.fromRGB(65, 65, 75),
				Features = {
					"Free features",
					"12-24h Key checkpoint",
					"Minimal support",
					"Renew anytime"
				}
			},
			{
				Title = "Premium",
				Badge = "EXCLUSIVE",
				Subtitle = { "Weekly", "Monthly", "Lifetime" },
				TextColor = Color3.fromRGB(250, 204, 21),
				SubtitleColor = Color3.fromRGB(253, 224, 71),
				AccentColor = Color3.fromRGB(250, 204, 21),
				BorderColor = Color3.fromRGB(250, 204, 21),
				Glow = true,
				ButtonBg = Color3.fromRGB(42, 34, 12),
				ButtonStroke = Color3.fromRGB(190, 150, 25),
				ButtonTextColor = Color3.fromRGB(250, 204, 21),
				ButtonText = "Purchase Key",
				Features = {
					"All Free features",
					"Priority support",
					"Helps the developers",
					"Keyless & instant"
				},
				Callback = function()
					if setclipboard then setclipboard("https://getaether.mysellauth.com/") end
					Tabs:Notify({ Title = "Store Link Copied", Desc = "Aether store link copied! Visit store to purchase your license.", Time = 3.5 })
				end
			},
			{
				Title = "Booster",
				Badge = "DISCORD",
				Subtitle = "Server Boosts",
				TextColor = Color3.fromRGB(192, 132, 252),
				SubtitleColor = Color3.fromRGB(216, 180, 254),
				AccentColor = Color3.fromRGB(192, 132, 252),
				BorderColor = Color3.fromRGB(115, 65, 160),
				ButtonBg = Color3.fromRGB(38, 20, 52),
				ButtonStroke = Color3.fromRGB(160, 85, 220),
				ButtonTextColor = Color3.fromRGB(192, 132, 252),
				ButtonText = "Boost Discord",
				Features = {
					"All Premium features",
					"Cool Discord role",
					"Priority support",
					"Free with 2x Boosts"
				},
				Callback = function()
					if setclipboard then setclipboard(DiscordLink) end
					Tabs:Notify({ Title = "Discord Link Copied", Desc = "Discord invite copied to clipboard! Boost our server to unlock perks.", Time = 3.5 })
				end
			}
		})

		local PrivSec = SettingsSub:Section({ Title = "Streamer Mode", LayoutOrder = 1 })

		local StreamerToggleObj = PrivSec:Toggle({
			Title = "Streamer Mode",
			Desc = "Hides your username, display name, user ID, and avatar across the entire interface",
			Image = "shield",
			Value = Tabs.StreamerMode,
			IgnoreConfig = true,
			Callback = function(enabled)
				Tabs:SetStreamerMode(enabled)
				Tabs:Notify({
					Title = "Streamer Mode",
					Desc = enabled and "Identity hidden for streaming/recording" or "Identity visible",
					Time = 2.5
				})
			end
		})
		table.insert(Tabs._streamerToggles, StreamerToggleObj)

		local FPSToggleObj = PrivSec:Toggle({
			Title = "FPS Unlocker",
			Desc = "Remove standard 60 FPS frame rate limit (unlocks up to 240+ FPS)",
			Image = "zap",
			Value = false,
			Callback = function(state)
				local setcap = (type(setfpscap) == "function" and setfpscap)
					or (type(set_fps_cap) == "function" and set_fps_cap)
				if setcap then
					pcall(function() setcap(state and 240 or 60) end)
				end
				Tabs:Notify({
					Title = "FPS Unlocker",
					Desc = state and "Frame rate unlocked (240 FPS cap)" or "Frame rate capped at 60 FPS",
					Time = 2
				})
			end
		})

		local ControlsSec = SettingsSub:Section({ Title = "Interface Controls", LayoutOrder = 3 })

		ControlsSec:Keybind({
			Title = "UI Toggle Keybind",
			Desc = "Key used to open and minimize the interface",
			Key = Keybind,
			IgnoreConfig = true,
			Callback = function(newKey)
				Tabs.UIToggleKeybind = newKey
				local kname = newKey.Name
				if kname == "LeftControl" then kname = "LeftCtrl" end
				if kname == "RightControl" then kname = "RightCtrl" end
				ReopenKeybind.Text = "[" .. kname .. "]"
				Tabs:Notify({ Title = "Keybind Set", Desc = "Rebound to " .. kname, Time = 2 })
			end
		})

		ControlsSec:Toggle({
			Title = "Auto-Save Window Size",
			Desc = "Automatically remember your window size whenever you finish resizing",
			Value = true,
			IgnoreConfig = true,
			Callback = function(val)
				autoSaveSize = val
			end
		})

		ControlsSec:Button({
			Title = "Save Current Window Size",
			Desc = "Lock in the current window dimensions so it always opens at this size",
			Image = "save",
			Callback = function()
				Tabs:SaveWindowSize()
			end
		})

		ControlsSec:Button({
			Title = "Reset Window Size",
			Desc = "Restore default window dimensions",
			Image = "refresh-cw",
			Callback = function()
				Tabs:ResetWindowSize()
			end
		})

		local ConfigSec = SettingsSub:Section({ Title = "Configuration Manager", LayoutOrder = 4 })
		local currentConfigName = "Default"

		ConfigSec:Textbox({
			Title = "Config File Name",
			Desc = "Name used when saving to Aether/Configs",
			Placeholder = "Enter config name...",
			Value = "Default",
			IgnoreConfig = true,
			Callback = function(val)
				if val and val ~= "" then currentConfigName = val end
			end
		})

		local ConfigDropdown = ConfigSec:Dropdown({
			Title = "Select Config",
			Desc = "Saved configs found in Aether/Configs",
			List = FileSystem:ListConfigs(),
			Value = currentConfigName,
			IgnoreConfig = true,
			Callback = function(val) currentConfigName = val end
		})

		ConfigSec:Button({
			Title = "Save Config",
			Desc = "Save all settings, toggles and appearance to Aether/Configs",
			Image = "save",
			Callback = function()
				Tabs._suppressNotifications = true

				local sectionsState = {}
				for _, sec in ipairs(currentWindowTheme.sections or {}) do
					if sec.TitleText and sec.IsMinimized then
						sectionsState[sec.TitleText] = sec.IsMinimized()
					end
				end

				local elementsState = {}
				for _, elem in ipairs(ConfigElements) do
					local ok, val = pcall(elem.Get)
					if ok and val ~= nil then
						elementsState[elem.Flag] = val
					end
				end

				local curTrans = (WallTransSlider and WallTransSlider:GetValue()) or math.floor(WindowBackgroundImg.ImageTransparency * 100)
				local curDim = (WallDimSlider and WallDimSlider:GetValue()) or math.floor((1 - WindowBackgroundDim.BackgroundTransparency) * 100)

				local cfgData = {
					ThemeName = currentWindowTheme.name,
					AccentColor = { R = math.floor(curColors['Main'].R * 255), G = math.floor(curColors['Main'].G * 255), B = math.floor(curColors['Main'].B * 255) },
					BackgroundColor = { R = math.floor(curColors['Background'].R * 255), G = math.floor(curColors['Background'].G * 255), B = math.floor(curColors['Background'].B * 255) },
					CardColor = { R = math.floor(curColors['Card'].R * 255), G = math.floor(curColors['Card'].G * 255), B = math.floor(curColors['Card'].B * 255) },
					TextColor = { R = math.floor(curColors['Text & Icon'].R * 255), G = math.floor(curColors['Text & Icon'].R * 255), B = math.floor(curColors['Text & Icon'].B * 255) },
					SubTextColor = { R = math.floor(curColors['SubText'].R * 255), G = math.floor(curColors['SubText'].G * 255), B = math.floor(curColors['SubText'].B * 255) },
					BorderColor = { R = math.floor(curColors['CardBorder'].R * 255), G = math.floor(curColors['CardBorder'].G * 255), B = math.floor(curColors['CardBorder'].B * 255) },
					Transparency = deepCopy(currentWindowTheme.transparency),
					Wallpaper = currentActiveWallpaper,
					BackgroundImage = WindowBackgroundImg.Image,
					BackgroundTransparency = curTrans,
					BackgroundDim = curDim,
					Sounds = deepCopy(currentSoundConfig),
					Cursor = deepCopy(currentCursorConfig),
					ToggleKeybind = tostring(Tabs.UIToggleKeybind),
					StreamerMode = Tabs.StreamerMode,
					Sections = sectionsState,
					Elements = elementsState,
					WindowSize = { Width = Shadow_1.Size.X.Offset, Height = Shadow_1.Size.Y.Offset }
				}
				FileSystem:SaveConfig(currentConfigName, cfgData)
				ConfigDropdown:Clear()
				for _, c in ipairs(FileSystem:ListConfigs()) do ConfigDropdown:Add(c) end
				ConfigDropdown:SetValue(currentConfigName, true)

				task.delay(0.2, function()
					Tabs._suppressNotifications = false
				end)
			end
		})

		ConfigSec:Button({
			Title = "Load Config",
			Desc = "Apply selected config file from Aether/Configs",
			Image = "folder",
			Callback = function()
				local cfgData = FileSystem:LoadConfig(currentConfigName)
				if cfgData then
					Tabs._suppressNotifications = true
					if Tabs.ClearNotifications then Tabs:ClearNotifications() end

					if cfgData.ThemeName and themes[cfgData.ThemeName] then Tabs:ApplyTheme(cfgData.ThemeName) end
					if cfgData.AccentColor then
						Tabs:ApplyTheme({
							Main = Color3.fromRGB(cfgData.AccentColor.R, cfgData.AccentColor.G, cfgData.AccentColor.B),
							Background = cfgData.BackgroundColor and Color3.fromRGB(cfgData.BackgroundColor.R, cfgData.BackgroundColor.G, cfgData.BackgroundColor.B) or curColors['Background'],
							Card = cfgData.CardColor and Color3.fromRGB(cfgData.CardColor.R, cfgData.CardColor.G, cfgData.CardColor.B) or curColors['Card'],
							['Text & Icon'] = cfgData.TextColor and Color3.fromRGB(cfgData.TextColor.R, cfgData.TextColor.G, cfgData.TextColor.B) or curColors['Text & Icon'],
							SubText = cfgData.SubTextColor and Color3.fromRGB(cfgData.SubTextColor.R, cfgData.SubTextColor.G, cfgData.SubTextColor.B) or curColors['SubText'],
							CardBorder = cfgData.BorderColor and Color3.fromRGB(cfgData.BorderColor.R, cfgData.BorderColor.G, cfgData.BorderColor.B) or curColors['CardBorder']
						})
					end

					if cfgData.Transparency and type(cfgData.Transparency) == "table" then
						applyAllTransparencies(cfgData.Transparency)
					end

					if cfgData.WindowSize and type(cfgData.WindowSize) == "table" and cfgData.WindowSize.Width and cfgData.WindowSize.Height then
						Tabs:SetWindowSize(cfgData.WindowSize.Width, cfgData.WindowSize.Height, true)
					end

					if cfgData.Sounds and type(cfgData.Sounds) == "table" then
						applySoundConfig(cfgData.Sounds)
					end

					if cfgData.Cursor and type(cfgData.Cursor) == "table" then
						applyCursorConfig(cfgData.Cursor)
					end

					local wp = cfgData.Wallpaper or cfgData.BackgroundImage
					if wp and wp ~= "" then
						currentActiveWallpaper = wp
						local asset = FileSystem:GetWallpaperAsset(wp)
						WindowBackgroundImg.Image = asset

						local isAssetId = tostring(wp):match("^%d+$") or tostring(wp):match("^rbxassetid://") or tostring(wp):match("^rbxasset://") or tostring(wp):match("^https?://")

						if isAssetId then
							if WallDropdown then WallDropdown:SetValue("None", true) end
							if WallAssetInput then WallAssetInput:SetValue(wp, true) end
						else
							if WallDropdown then WallDropdown:SetValue(wp, true) end
							if WallAssetInput then WallAssetInput:SetValue("", true) end
						end

						local trans = cfgData.BackgroundTransparency
						if trans == nil then trans = 30 end
						if trans > 0 and trans <= 1 then trans = math.floor(trans * 100) end
						if WallTransSlider then
							WallTransSlider:SetValue(trans, true)
						else
							WindowBackgroundImg.ImageTransparency = trans / 100
						end

						local dim = cfgData.BackgroundDim
						if dim == nil then dim = 50 end
						if dim > 0 and dim <= 1 then dim = math.floor((1 - dim) * 100) end
						if WallDimSlider then
							WallDimSlider:SetValue(dim, true)
						else
							WindowBackgroundDim.BackgroundTransparency = 1 - (dim / 100)
						end
					else
						currentActiveWallpaper = ""
						WindowBackgroundImg.Image = ""
						WindowBackgroundImg.ImageTransparency = 1
						WindowBackgroundDim.BackgroundTransparency = 1
						if WallDropdown then WallDropdown:SetValue("None", true) end
						if WallAssetInput then WallAssetInput:SetValue("", true) end
						if WallTransSlider then WallTransSlider:SetValue(30, true) end
						if WallDimSlider then WallDimSlider:SetValue(50, true) end
					end

					if cfgData.StreamerMode ~= nil then
						Tabs:SetStreamerMode(cfgData.StreamerMode)
					end
					if cfgData.Sections and type(cfgData.Sections) == "table" then
						for _, sec in ipairs(currentWindowTheme.sections or {}) do
							if sec.TitleText and cfgData.Sections[sec.TitleText] ~= nil then
								sec.SetMinimized(cfgData.Sections[sec.TitleText])
							else
								sec.SetMinimized(false)
							end
						end
					else
						for _, sec in ipairs(currentWindowTheme.sections or {}) do
							if sec.SetMinimized then
								sec.SetMinimized(false)
							end
						end
					end

					if cfgData.Elements and type(cfgData.Elements) == "table" then
						for _, elem in ipairs(ConfigElements) do
							local savedVal = cfgData.Elements[elem.Flag]
							if savedVal == nil then savedVal = cfgData.Elements[elem.Title] end
							if savedVal == nil and cfgData[elem.Flag] ~= nil then savedVal = cfgData[elem.Flag] end
							if savedVal ~= nil then
								pcall(function() elem.Set(savedVal) end)
							end
						end
					end

					task.delay(0.25, function()
						Tabs._suppressNotifications = false
					end)
				end
			end
		})

		ConfigSec:Button({
			Title = "Delete Config",
			Desc = "Remove selected config from Aether/Configs",
			Image = "trash-2",
			Callback = function()
				FileSystem:DeleteConfig(currentConfigName)
				ConfigDropdown:Clear()
				for _, c in ipairs(FileSystem:ListConfigs()) do ConfigDropdown:Add(c) end
				Tabs:Notify({ Title = "Config Deleted", Desc = "Deleted '" .. currentConfigName .. "'", Time = 2 })
			end
		})

		ConfigSec:Button({
			Title = "Reset to Default Config",
			Desc = "Reset all controls, toggles, appearance, and audio to defaults",
			Image = "rotate-ccw",
			Callback = function()
				Tabs._suppressNotifications = true
				if Tabs.ClearNotifications then Tabs:ClearNotifications() end

				for _, elem in ipairs(ConfigElements) do
					if elem.Default ~= nil and elem.Set then
						pcall(function() elem.Set(elem.Default) end)
					end
				end

				Tabs:ApplyTheme("Default")
				if ThemeDropdown then ThemeDropdown:SetValue("Default", true) end
				applyAllTransparencies(0, 0, 0, 0, 100)
				if TransPresetDropdown then TransPresetDropdown:SetValue("Solid (Default)", true) end

				currentActiveWallpaper = ""
				WindowBackgroundImg.Image = ""
				WindowBackgroundImg.ImageTransparency = 1
				WindowBackgroundDim.BackgroundTransparency = 1
				if WallDropdown then WallDropdown:SetValue("None", true) end
				if WallAssetInput then WallAssetInput:SetValue("", true) end
				if WallTransSlider then WallTransSlider:SetValue(30, true) end
				if WallDimSlider then WallDimSlider:SetValue(50, true) end

				for _, sec in ipairs(currentWindowTheme.sections or {}) do
					if sec.SetMinimized then sec.SetMinimized(false) end
				end

				Tabs:SetStreamerMode(false)

				applySoundConfig({
					BGMEnabled = false,
					BGMTrack = "None",
					BGMAsset = "",
					BGMVolume = 50,
					BGMLooped = true
				})

				applyCursorConfig({
					Enabled = false,
					Preset = "Default (Roblox)",
					CustomAsset = ""
				})

				task.delay(0.25, function()
					Tabs._suppressNotifications = false
				end)
			end
		})

		local ThemePresetSec = ThemesSub:Section({ Title = "Theme Presets" })

		local ThemeDropdown = ThemePresetSec:Dropdown({
			Title = "Theme Preset",
			Desc = "Select Default or Halloween",
			List = { "Default", "Halloween" },
			Value = currentWindowTheme.name,
			IgnoreConfig = true,
			Callback = function(themeName)
				if themeName and themeName ~= "Custom" then
					Tabs:ApplyTheme(themeName)
					Tabs:Notify({ Title = "Theme Changed", Desc = "Applied " .. themeName .. " theme", Time = 2 })
				end
			end
		})

		local ThemeColorSec = ThemesSub:Section({ Title = "Theme Colors Customizer" })

		ThemeColorSec:ColorPicker({
			Title = "Accent / Highlights Color",
			Desc = "Changes active toggles, highlights, and borders",
			Value = curColors['Main'],
			IgnoreConfig = true,
			Callback = function(col)
				Tabs:ApplyTheme({ Main = col })
				ThemeDropdown:SetValue("Custom", true)
			end
		})

		ThemeColorSec:ColorPicker({
			Title = "Window Background Color",
			Desc = "Base background color of Aether",
			Value = curColors['Background'],
			IgnoreConfig = true,
			Callback = function(col)
				Tabs:ApplyTheme({ Background = col, Page = col, Sidebar = col })
				ThemeDropdown:SetValue("Custom", true)
			end
		})

		ThemeColorSec:ColorPicker({
			Title = "Card Background Color",
			Desc = "Background of content boxes and sections",
			Value = curColors['Card'],
			IgnoreConfig = true,
			Callback = function(col)
				Tabs:ApplyTheme({ Card = col })
				ThemeDropdown:SetValue("Custom", true)
			end
		})

		ThemeColorSec:ColorPicker({
			Title = "Text & Icon Color",
			Desc = "Primary font and icon color",
			Value = curColors['Text & Icon'],
			IgnoreConfig = true,
			Callback = function(col)
				Tabs:ApplyTheme({ ['Text & Icon'] = col })
				ThemeDropdown:SetValue("Custom", true)
			end
		})

		ThemeColorSec:ColorPicker({
			Title = "SubText Color",
			Desc = "Descriptions, hints, and muted texts",
			Value = curColors['SubText'],
			IgnoreConfig = true,
			Callback = function(col)
				Tabs:ApplyTheme({ SubText = col })
				ThemeDropdown:SetValue("Custom", true)
			end
		})

		ThemeColorSec:ColorPicker({
			Title = "Card Border Color",
			Desc = "Border outline color",
			Value = curColors['CardBorder'],
			IgnoreConfig = true,
			Callback = function(col)
				Tabs:ApplyTheme({ CardBorder = col })
				ThemeDropdown:SetValue("Custom", true)
			end
		})

		local TransSec, WallSec = ThemesSub:DualSection(
			{ Title = "Interface Transparency & Glass" },
			{ Title = "Wallpaper Customization" }
		)

		local transPresets = {
			["Solid (Default)"] = { Window = 0, Sidebar = 0, Section = 0, Card = 0 },
			["Frosted Glass"] = { Window = 15, Sidebar = 20, Section = 25, Card = 20 },
			["Translucent"] = { Window = 35, Sidebar = 40, Section = 45, Card = 35 },
			["Ultra Clear"] = { Window = 60, Sidebar = 65, Section = 70, Card = 55 },
		}

		local initialPreset = getPresetNameForValues(
			currentWindowTheme.transparency.Window or 0,
			currentWindowTheme.transparency.Sidebar or 0,
			currentWindowTheme.transparency.Section or 0,
			currentWindowTheme.transparency.Card or 0
		)

		TransPresetDropdown = TransSec:Dropdown({
			Title = "Transparency Mode",
			Desc = "Quick presets for glass & transparency styling",
			List = { "Solid (Default)", "Frosted Glass", "Translucent", "Ultra Clear", "Custom" },
			Value = initialPreset,
			IgnoreConfig = true,
			Callback = function(presetName)
				if transPresets[presetName] then
					applyAllTransparencies(transPresets[presetName])
				end
			end
		})

		WindowTransSlider = TransSec:Slider({
			Title = "Window Base Transparency",
			Desc = "Main window canvas background (0% = solid, 100% = clear)",
			Min = 0,
			Max = 100,
			Value = currentWindowTheme.transparency.Window or 0,
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				setWindowTransparency(val)
				if not skipPresetReset and TransPresetDropdown then
					TransPresetDropdown:SetValue("Custom", true)
				end
			end
		})

		SidebarTransSlider = TransSec:Slider({
			Title = "Sidebar Transparency",
			Desc = "Left navigation tab bar (0% = solid, 100% = clear)",
			Min = 0,
			Max = 100,
			Value = currentWindowTheme.transparency.Sidebar or 0,
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				setSidebarTransparency(val)
				if not skipPresetReset and TransPresetDropdown then
					TransPresetDropdown:SetValue("Custom", true)
				end
			end
		})

		SectionTransSlider = TransSec:Slider({
			Title = "Section Frames Transparency",
			Desc = "Container frames around card groups (0% = solid, 100% = clear)",
			Min = 0,
			Max = 100,
			Value = currentWindowTheme.transparency.Section or 0,
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				setSectionTransparency(val)
				if not skipPresetReset and TransPresetDropdown then
					TransPresetDropdown:SetValue("Custom", true)
				end
			end
		})

		CardTransSlider = TransSec:Slider({
			Title = "Card Background Transparency",
			Desc = "Element cards background (0% = solid, 100% = clear)",
			Min = 0,
			Max = 100,
			Value = currentWindowTheme.transparency.Card or 0,
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				setCardTransparency(val)
				if not skipPresetReset and TransPresetDropdown then
					TransPresetDropdown:SetValue("Custom", true)
				end
			end
		})

		local initialWallpapers = FileSystem:ListWallpapers()
		local wallList = { "None" }
		for _, w in ipairs(initialWallpapers) do table.insert(wallList, w) end

		local initialWallVal = "None"
		if currentActiveWallpaper ~= "" and not currentActiveWallpaper:match("^%d+$") and not currentActiveWallpaper:match("^rbxassetid://") and not currentActiveWallpaper:match("^rbxasset://") and not currentActiveWallpaper:match("^https?://") then
			initialWallVal = currentActiveWallpaper
		end

		WallDropdown = WallSec:Dropdown({
			Title = "Custom Wallpaper (Themes/Wallpaper)",
			Desc = "Select image from Aether/Themes/Wallpaper folder",
			List = wallList,
			Value = initialWallVal,
			IgnoreConfig = true,
			Callback = function(val)
				if val and val ~= "None" and val ~= "--" and val ~= "" then
					currentActiveWallpaper = val
					local asset = FileSystem:GetWallpaperAsset(val)
					WindowBackgroundImg.Image = asset
					if WallAssetInput then WallAssetInput:SetValue("") end

					local curTrans = (WallTransSlider and WallTransSlider:GetValue()) or 30
					if curTrans >= 100 then
						curTrans = 30
						if WallTransSlider then WallTransSlider:SetValue(30) end
					end
					WindowBackgroundImg.ImageTransparency = curTrans / 100

					local curDim = (WallDimSlider and WallDimSlider:GetValue()) or 50
					WindowBackgroundDim.BackgroundTransparency = 1 - (curDim / 100)

					Tabs:Notify({ Title = "Wallpaper Applied", Desc = "Loaded '" .. tostring(val) .. "'", Time = 2 })
				elseif val == "None" then
					currentActiveWallpaper = ""
					WindowBackgroundImg.Image = ""
					WindowBackgroundImg.ImageTransparency = 1
					WindowBackgroundDim.BackgroundTransparency = 1
					Tabs:Notify({ Title = "Wallpaper Cleared", Desc = "Solid background restored", Time = 2 })
				end
			end
		})

		WallSec:Button({
			Title = "Refresh Wallpaper Folder",
			Desc = "Re-scan Aether/Themes/Wallpaper for newly placed images",
			Image = "refresh-cw",
			Callback = function()
				local refreshed = FileSystem:ListWallpapers()
				WallDropdown:Clear()
				WallDropdown:Add("None")
				for _, w in ipairs(refreshed) do
					WallDropdown:Add(w)
				end
				if currentActiveWallpaper ~= "" and table.find(refreshed, currentActiveWallpaper) then
					WallDropdown:SetValue(currentActiveWallpaper, true)
				else
					WallDropdown:SetValue("None", true)
				end
				Tabs:Notify({ Title = "Wallpapers Scanned", Desc = "Found " .. #refreshed .. " file(s) in folder", Time = 2.5 })
			end
		})

		WallAssetInput = WallSec:Textbox({
			Title = "Or Roblox Image Asset ID",
			Desc = "Roblox Image Asset ID (e.g. 12345678 or rbxassetid://...)",
			Placeholder = "rbxassetid://...",
			IgnoreConfig = true,
			Callback = function(val)
				if val and val ~= "" then
					local id = val
					if not id:find("rbxassetid://") and tonumber(id) then id = "rbxassetid://" .. id end
					currentActiveWallpaper = id
					WindowBackgroundImg.Image = id
					if WallDropdown then WallDropdown:SetValue("None", true) end

					local curTrans = (WallTransSlider and WallTransSlider:GetValue()) or 30
					if curTrans >= 100 then
						curTrans = 30
						if WallTransSlider then WallTransSlider:SetValue(30) end
					end
					WindowBackgroundImg.ImageTransparency = curTrans / 100

					local curDim = (WallDimSlider and WallDimSlider:GetValue()) or 50
					WindowBackgroundDim.BackgroundTransparency = 1 - (curDim / 100)

					Tabs:Notify({ Title = "Wallpaper Applied", Desc = "Custom asset ID loaded", Time = 2 })
				end
			end
		})

		WallTransSlider = WallSec:Slider({
			Title = "Wallpaper Transparency",
			Desc = "Adjust visibility of the custom background image",
			Min = 0,
			Max = 100,
			Value = 30,
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				WindowBackgroundImg.ImageTransparency = val / 100
			end
		})

		WallDimSlider = WallSec:Slider({
			Title = "Wallpaper Dim Level",
			Desc = "Darken the wallpaper so UI text stays clear and readable",
			Min = 0,
			Max = 100,
			Value = 50,
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				WindowBackgroundDim.BackgroundTransparency = 1 - (val / 100)
			end
		})

		WallSec:Button({
			Title = "Clear Wallpaper",
			Desc = "Removes custom wallpaper and resets to solid theme",
			Image = "trash-2",
			Callback = function()
				currentActiveWallpaper = ""
				WindowBackgroundImg.Image = ""
				WindowBackgroundImg.ImageTransparency = 1
				WindowBackgroundDim.BackgroundTransparency = 1
				if WallDropdown then WallDropdown:SetValue("None", true) end
				if WallAssetInput then WallAssetInput:SetValue("") end
				if WallTransSlider then WallTransSlider:SetValue(30) end
				if WallDimSlider then WallDimSlider:SetValue(50) end
				Tabs:Notify({ Title = "Wallpaper Cleared", Desc = "Solid background restored", Time = 2 })
			end
		})

		local SoundSec, CursorSec = ThemesSub:DualSection(
			{ Title = "Interface Background Music", Minimized = true },
			{ Title = "Custom Cursor Customization", Minimized = true }
		)

		local initialSounds = FileSystem:ListSounds()
		local bgmList = { "None", "Lofi Chill", "Ambient Dream" }
		for _, s in ipairs(initialSounds) do if not table.find(bgmList, s) then table.insert(bgmList, s) end end

		BGMToggle = SoundSec:Toggle({
			Title = "Enable Background Music",
			Desc = "Play continuous audio track or song in the background",
			Value = currentSoundConfig.BGMEnabled,
			IgnoreConfig = true,
			Callback = function(state)
				currentSoundConfig.BGMEnabled = state
				if state then
					local assetToPlay = ""
					if currentSoundConfig.BGMAsset and currentSoundConfig.BGMAsset ~= "" then
						assetToPlay = FileSystem:GetAudioAsset(currentSoundConfig.BGMAsset)
					elseif currentSoundConfig.BGMTrack and currentSoundConfig.BGMTrack ~= "None" then
						local presets = {
							["Lofi Chill"] = "rbxassetid://9043887091",
							["Ambient Dream"] = "rbxassetid://1843404009"
						}
						assetToPlay = presets[currentSoundConfig.BGMTrack] or FileSystem:GetAudioAsset(currentSoundConfig.BGMTrack)
					end
					if assetToPlay and assetToPlay ~= "" then
						BackgroundMusic.SoundId = assetToPlay
						pcall(function() BackgroundMusic:Play() end)
					end
				else
					pcall(function() BackgroundMusic:Stop() end)
				end
			end
		})

		BGMTrackDropdown = SoundSec:Dropdown({
			Title = "BGM Track Preset",
			Desc = "Choose from curated music loops or local files in Themes/Sounds",
			List = bgmList,
			Value = currentSoundConfig.BGMTrack or "None",
			IgnoreConfig = true,
			Callback = function(track)
				currentSoundConfig.BGMTrack = track
				if track and track ~= "None" and track ~= "" then
					currentSoundConfig.BGMAsset = ""
					if BGMAssetInput then BGMAssetInput:SetValue("", true) end
					local presets = {
						["Lofi Chill"] = "rbxassetid://9043887091",
						["Ambient Dream"] = "rbxassetid://1843404009"
					}
					local assetToPlay = presets[track] or FileSystem:GetAudioAsset(track)
					BackgroundMusic.SoundId = assetToPlay
					if currentSoundConfig.BGMEnabled then
						pcall(function() BackgroundMusic:Play() end)
					end
				else
					pcall(function() BackgroundMusic:Stop() end)
				end
			end
		})

		SoundSec:Button({
			Title = "Refresh Sounds List",
			Desc = "Re-scan Aether/Themes/Sounds for newly placed audio files",
			Image = "refresh-cw",
			Callback = function()
				local refreshed = FileSystem:ListSounds()
				local defaultBGM = { "None", "Lofi Chill", "Ambient Dream" }
				BGMTrackDropdown:Clear()
				for _, b in ipairs(defaultBGM) do
					BGMTrackDropdown:Add(b)
				end
				for _, s in ipairs(refreshed) do
					if not table.find(defaultBGM, s) then
						BGMTrackDropdown:Add(s)
					end
				end
				if currentSoundConfig.BGMTrack and currentSoundConfig.BGMTrack ~= "" then
					BGMTrackDropdown:SetValue(currentSoundConfig.BGMTrack, true)
				else
					BGMTrackDropdown:SetValue("None", true)
				end
				Tabs:Notify({ Title = "Sounds Scanned", Desc = "Found " .. #refreshed .. " file(s) in folder", Time = 2.5 })
			end
		})

		BGMAssetInput = SoundSec:Textbox({
			Title = "Or Custom BGM Sound ID / File",
			Desc = "Enter Roblox Sound ID (e.g. 9043887091) or audio file name",
			Placeholder = "rbxassetid://...",
			Value = currentSoundConfig.BGMAsset,
			IgnoreConfig = true,
			Callback = function(val)
				if val and val ~= "" then
					local id = val
					if not id:find("rbxassetid://") and tonumber(id) then id = "rbxassetid://" .. id end
					currentSoundConfig.BGMAsset = id
					currentSoundConfig.BGMTrack = "None"
					local asset = FileSystem:GetAudioAsset(id)
					BackgroundMusic.SoundId = asset
					if BGMTrackDropdown then BGMTrackDropdown:SetValue("None", true) end
					if currentSoundConfig.BGMEnabled then
						pcall(function() BackgroundMusic:Play() end)
					end
					Tabs:Notify({ Title = "BGM Updated", Desc = "Custom audio track loaded", Time = 2 })
				else
					currentSoundConfig.BGMAsset = ""
				end
			end
		})

		BGMVolumeSlider = SoundSec:Slider({
			Title = "BGM Volume",
			Desc = "Adjust background music volume level",
			Min = 0,
			Max = 100,
			Value = currentSoundConfig.BGMVolume,
			Suffix = "%",
			Rounding = 0,
			IgnoreConfig = true,
			Callback = function(val)
				currentSoundConfig.BGMVolume = val
				BackgroundMusic.Volume = val / 100
			end
		})

		BGMLoopToggle = SoundSec:Toggle({
			Title = "Loop Background Music",
			Desc = "Keep background music running continuously in a loop",
			Value = currentSoundConfig.BGMLooped,
			IgnoreConfig = true,
			Callback = function(state)
				currentSoundConfig.BGMLooped = state
				BackgroundMusic.Looped = state
			end
		})

		local initialCursors = FileSystem:ListCursors()
		local cursorList = { "Default (Roblox)", "Crosshair (Clean)", "Arrow (Far)", "Pointer (Sleek)" }
		for _, c in ipairs(initialCursors) do
			if not table.find(cursorList, c) then
				table.insert(cursorList, c)
			end
		end

		CursorToggle = CursorSec:Toggle({
			Title = "Enable Custom Cursor",
			Desc = "Replace default Roblox cursor with custom crosshair or image",
			Value = currentCursorConfig.Enabled,
			IgnoreConfig = true,
			Callback = function(state)
				if isUpdatingCursorUI then return end
				currentCursorConfig.Enabled = state
				if state and (currentCursorConfig.Preset == "Default (Roblox)" or currentCursorConfig.Preset == "None" or currentCursorConfig.Preset == "") and (currentCursorConfig.CustomAsset == "") then
					currentCursorConfig.Preset = "Crosshair (Clean)"
					if CursorPresetDropdown then CursorPresetDropdown:SetValue("Crosshair (Clean)", true) end
				end
				applyCursorConfig(currentCursorConfig)
			end
		})

		CursorPresetDropdown = CursorSec:Dropdown({
			Title = "Cursor Style Preset",
			Desc = "Select built-in cursor preset or local file from Themes/Cursors",
			List = cursorList,
			Value = currentCursorConfig.Preset or "Default (Roblox)",
			IgnoreConfig = true,
			Callback = function(val)
				if isUpdatingCursorUI then return end
				currentCursorConfig.Preset = val
				if val and val ~= "None" and val ~= "Default (Roblox)" and val ~= "" then
					currentCursorConfig.CustomAsset = ""
					currentCursorConfig.Enabled = true
					if CursorToggle then CursorToggle:SetValue(true, true) end
					if CursorAssetInput then CursorAssetInput:SetValue("", true) end
					applyCursorConfig(currentCursorConfig)
					Tabs:Notify({ Title = "Cursor Applied", Desc = "Loaded '" .. tostring(val) .. "'", Time = 2 })
				elseif val == "Default (Roblox)" or val == "None" then
					currentCursorConfig.Enabled = false
					currentCursorConfig.CustomAsset = ""
					if CursorToggle then CursorToggle:SetValue(false, true) end
					if CursorAssetInput then CursorAssetInput:SetValue("", true) end
					applyCursorConfig(currentCursorConfig)
				end
			end
		})

		CursorSec:Button({
			Title = "Refresh Cursors List",
			Desc = "Re-scan Aether/Themes/Cursors for newly placed cursor images",
			Image = "refresh-cw",
			Callback = function()
				local refreshed = FileSystem:ListCursors()
				local defaultPresets = { "Default (Roblox)", "Crosshair (Clean)", "Arrow (Far)", "Pointer (Sleek)" }
				CursorPresetDropdown:Clear()
				for _, p in ipairs(defaultPresets) do
					CursorPresetDropdown:Add(p)
				end
				for _, c in ipairs(refreshed) do
					if not table.find(defaultPresets, c) then
						CursorPresetDropdown:Add(c)
					end
				end
				if currentCursorConfig.Preset and currentCursorConfig.Preset ~= "" then
					CursorPresetDropdown:SetValue(currentCursorConfig.Preset, true)
				else
					CursorPresetDropdown:SetValue("Default (Roblox)", true)
				end
				Tabs:Notify({ Title = "Cursors Scanned", Desc = "Found " .. #refreshed .. " file(s) in folder", Time = 2.5 })
			end
		})

		CursorAssetInput = CursorSec:Textbox({
			Title = "Or Roblox Cursor Asset ID",
			Desc = "Roblox Image Asset ID (e.g. 12345678 or rbxassetid://...)",
			Placeholder = "rbxassetid://...",
			Value = currentCursorConfig.CustomAsset,
			IgnoreConfig = true,
			Callback = function(val)
				if isUpdatingCursorUI then return end
				if val and val ~= "" then
					local id = val
					if not id:find("rbxassetid://") and tonumber(id) then id = "rbxassetid://" .. id end
					currentCursorConfig.CustomAsset = id
					currentCursorConfig.Preset = "None"
					currentCursorConfig.Enabled = true
					if CursorToggle then CursorToggle:SetValue(true, true) end
					if CursorPresetDropdown then CursorPresetDropdown:SetValue("None", true) end
					applyCursorConfig(currentCursorConfig)
					Tabs:Notify({ Title = "Cursor Applied", Desc = "Custom cursor asset loaded", Time = 2 })
				else
					currentCursorConfig.CustomAsset = ""
					applyCursorConfig(currentCursorConfig)
				end
			end
		})

		CursorSec:Button({
			Title = "Reset Cursor to Default",
			Desc = "Restore original Roblox mouse pointer",
			Image = "rotate-ccw",
			Callback = function()
				applyCursorConfig({
					Enabled = false,
					Preset = "Default (Roblox)",
					CustomAsset = ""
				})
				Tabs:Notify({ Title = "Cursor Reset", Desc = "Default Roblox mouse cursor restored", Time = 2 })
			end
		})

		local ThemeFileSec = ThemesSub:Section({ Title = "Save / Load Custom Themes" })
		local currentCustomThemeName = "MyTheme"

		ThemeFileSec:Textbox({
			Title = "Custom Theme Name",
			Desc = "Name to save/load in Aether/Themes",
			Placeholder = "Theme name...",
			Value = "MyTheme",
			IgnoreConfig = true,
			Callback = function(val)
				if val and val ~= "" then currentCustomThemeName = val end
			end
		})

		local ThemeFileDropdown = ThemeFileSec:Dropdown({
			Title = "Saved Custom Themes",
			Desc = "Saved themes found in Aether/Themes",
			List = FileSystem:ListThemes(),
			Value = "Select Theme",
			IgnoreConfig = true,
			Callback = function(val) currentCustomThemeName = val end
		})

		ThemeFileSec:Button({
			Title = "Save Current Theme",
			Desc = "Saves active colors and wallpaper to Aether/Themes/",
			Image = "save",
			Callback = function()
				local curTrans = (WallTransSlider and WallTransSlider:GetValue()) or math.floor(WindowBackgroundImg.ImageTransparency * 100)
				local curDim = (WallDimSlider and WallDimSlider:GetValue()) or math.floor((1 - WindowBackgroundDim.BackgroundTransparency) * 100)

				local thmData = {
					Main = { math.floor(curColors['Main'].R * 255), math.floor(curColors['Main'].G * 255), math.floor(curColors['Main'].B * 255) },
					Background = { math.floor(curColors['Background'].R * 255), math.floor(curColors['Background'].G * 255), math.floor(curColors['Background'].B * 255) },
					Card = { math.floor(curColors['Card'].R * 255), math.floor(curColors['Card'].G * 255), math.floor(curColors['Card'].B * 255) },
					['Text & Icon'] = { math.floor(curColors['Text & Icon'].R * 255), math.floor(curColors['Text & Icon'].G * 255), math.floor(curColors['Text & Icon'].B * 255) },
					SubText = { math.floor(curColors['SubText'].R * 255), math.floor(curColors['SubText'].G * 255), math.floor(curColors['SubText'].B * 255) },
					CardBorder = { math.floor(curColors['CardBorder'].R * 255), math.floor(curColors['CardBorder'].G * 255), math.floor(curColors['CardBorder'].B * 255) },
					Transparency = deepCopy(currentWindowTheme.transparency),
					Wallpaper = currentActiveWallpaper,
					WallpaperImage = WindowBackgroundImg.Image,
					WallpaperTransparency = curTrans,
					WallpaperDim = curDim,
					Sounds = deepCopy(currentSoundConfig),
					Cursor = deepCopy(currentCursorConfig)
				}
				FileSystem:SaveTheme(currentCustomThemeName, thmData)
				ThemeFileDropdown:Clear()
				for _, t in ipairs(FileSystem:ListThemes()) do ThemeFileDropdown:Add(t) end
				ThemeFileDropdown:SetValue(currentCustomThemeName, true)
				Tabs:Notify({ Title = "Theme Saved", Desc = "Saved '" .. currentCustomThemeName .. "' with wallpaper & audio to Aether/Themes/", Time = 2.5 })
			end
		})

		ThemeFileSec:Button({
			Title = "Load Saved Theme",
			Desc = "Applies chosen theme from Aether/Themes/",
			Image = "folder",
			Callback = function()
				local thmData = FileSystem:LoadTheme(currentCustomThemeName)
				if thmData then
					Tabs._suppressNotifications = true
					if Tabs.ClearNotifications then Tabs:ClearNotifications() end

					local parsed = {}
					for k, v in pairs(thmData) do
						if type(v) == "table" and #v >= 3 then
							local r, g, b = v[1], v[2], v[3]
							if r > 1 or g > 1 or b > 1 then
								parsed[k] = Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
							else
								parsed[k] = Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
							end
						end
					end
					Tabs:ApplyTheme(parsed)
					ThemeDropdown:SetValue("Custom", true)

					if thmData.Transparency and type(thmData.Transparency) == "table" then
						applyAllTransparencies(thmData.Transparency)
					else
						applyAllTransparencies(0, 0, 0, 0)
					end

					if thmData.Sounds and type(thmData.Sounds) == "table" then
						applySoundConfig(thmData.Sounds)
					else
						applySoundConfig({
							BGMEnabled = false,
							BGMTrack = "None",
							BGMAsset = "",
							BGMVolume = 50,
							BGMLooped = true
						})
					end

					if thmData.Cursor and type(thmData.Cursor) == "table" then
						applyCursorConfig(thmData.Cursor)
					else
						applyCursorConfig({
							Enabled = false,
							Preset = "Default (Roblox)",
							CustomAsset = ""
						})
					end

					local wp = thmData.Wallpaper or thmData.WallpaperImage
					if wp and wp ~= "" then
						currentActiveWallpaper = wp
						local asset = FileSystem:GetWallpaperAsset(wp)
						WindowBackgroundImg.Image = asset

						local isAssetId = tostring(wp):match("^%d+$") or tostring(wp):match("^rbxassetid://") or tostring(wp):match("^rbxasset://") or tostring(wp):match("^https?://")

						if isAssetId then
							if WallDropdown then WallDropdown:SetValue("None", true) end
							if WallAssetInput then WallAssetInput:SetValue(wp, true) end
						else
							if WallDropdown then WallDropdown:SetValue(wp, true) end
							if WallAssetInput then WallAssetInput:SetValue("", true) end
						end

						local trans = thmData.WallpaperTransparency
						if trans == nil then trans = 30 end
						if trans > 0 and trans <= 1 then trans = math.floor(trans * 100) end
						if WallTransSlider then
							WallTransSlider:SetValue(trans, true)
						else
							WindowBackgroundImg.ImageTransparency = trans / 100
						end

						local dim = thmData.WallpaperDim
						if dim == nil then dim = 50 end
						if dim > 0 and dim <= 1 then
							dim = math.floor((1 - dim) * 100)
						end
						if WallDimSlider then
							WallDimSlider:SetValue(dim, true)
						else
							WindowBackgroundDim.BackgroundTransparency = 1 - (dim / 100)
						end
					else
						currentActiveWallpaper = ""
						WindowBackgroundImg.Image = ""
						WindowBackgroundImg.ImageTransparency = 1
						WindowBackgroundDim.BackgroundTransparency = 1
						if WallDropdown then WallDropdown:SetValue("None", true) end
						if WallAssetInput then WallAssetInput:SetValue("", true) end
						if WallTransSlider then WallTransSlider:SetValue(30, true) end
						if WallDimSlider then WallDimSlider:SetValue(50, true) end
					end

					Tabs._suppressNotifications = false
					Tabs:Notify({ Title = "Theme Loaded", Desc = "Loaded '" .. currentCustomThemeName .. "'", Time = 2.5 })
				else
					Tabs:Notify({ Title = "Theme Error", Desc = "Could not find theme file", Time = 2.5, Type = "error" })
				end
			end
		})

		ThemeFileSec:Button({
			Title = "Reset to Default Theme",
			Desc = "Restores pure black & white colors, solid glass, clears wallpapers & audio",
			Image = "rotate-ccw",
			Callback = function()
				Tabs._suppressNotifications = true
				if Tabs.ClearNotifications then Tabs:ClearNotifications() end

				Tabs:ApplyTheme("Default")
				if ThemeDropdown then ThemeDropdown:SetValue("Default", true) end

				applyAllTransparencies(0, 0, 0, 0)
				if TransPresetDropdown then TransPresetDropdown:SetValue("Solid (Default)", true) end

				currentActiveWallpaper = ""
				WindowBackgroundImg.Image = ""
				WindowBackgroundImg.ImageTransparency = 1
				WindowBackgroundDim.BackgroundTransparency = 1
				if WallDropdown then WallDropdown:SetValue("None", true) end
				if WallAssetInput then WallAssetInput:SetValue("", true) end
				if WallTransSlider then WallTransSlider:SetValue(30, true) end
				if WallDimSlider then WallDimSlider:SetValue(50, true) end

				applySoundConfig({
					BGMEnabled = false,
					BGMTrack = "None",
					BGMAsset = "",
					BGMVolume = 50,
					BGMLooped = true
				})

				applyCursorConfig({
					Enabled = false,
					Preset = "Default (Roblox)",
					CustomAsset = ""
				})

				Tabs._suppressNotifications = false
				Tabs:Notify({ Title = "Theme Reset", Desc = "Restored default theme settings", Time = 2.5 })
			end
		})

		task.spawn(function()
			task.wait(0.2)
			local autoName = FileSystem:GetAutoload()
			if autoName and autoName ~= "" then
				local cfgData = FileSystem:LoadConfig(autoName)
				if cfgData then
					Tabs._suppressNotifications = true
					if cfgData.ThemeName and themes[cfgData.ThemeName] then
						Tabs:ApplyTheme(cfgData.ThemeName)
					end
					if cfgData.Transparency and type(cfgData.Transparency) == "table" then
						applyAllTransparencies(cfgData.Transparency)
					end
					if cfgData.WindowSize and type(cfgData.WindowSize) == "table" and cfgData.WindowSize.Width and cfgData.WindowSize.Height then
						Tabs:SetWindowSize(cfgData.WindowSize.Width, cfgData.WindowSize.Height, false)
					end
					if cfgData.Sounds and type(cfgData.Sounds) == "table" then
						applySoundConfig(cfgData.Sounds)
					end
					if cfgData.Cursor and type(cfgData.Cursor) == "table" then
						applyCursorConfig(cfgData.Cursor)
					end
					if cfgData.StreamerMode ~= nil then
						Tabs:SetStreamerMode(cfgData.StreamerMode)
					end
					local wp = cfgData.Wallpaper or cfgData.BackgroundImage
					if wp and wp ~= "" then
						currentActiveWallpaper = wp
						local asset = FileSystem:GetWallpaperAsset(wp)
						WindowBackgroundImg.Image = asset

						local isAssetId = tostring(wp):match("^%d+$") or tostring(wp):match("^rbxassetid://") or tostring(wp):match("^rbxasset://") or tostring(wp):match("^https?://")

						if isAssetId then
							if WallDropdown then WallDropdown:SetValue("None", true) end
							if WallAssetInput then WallAssetInput:SetValue(wp, true) end
						else
							if WallDropdown then WallDropdown:SetValue(wp, true) end
							if WallAssetInput then WallAssetInput:SetValue("", true) end
						end

						local trans = cfgData.BackgroundTransparency
						if trans == nil then trans = 30 end
						if trans > 0 and trans <= 1 then trans = math.floor(trans * 100) end
						if WallTransSlider then
							WallTransSlider:SetValue(trans, true)
						else
							WindowBackgroundImg.ImageTransparency = trans / 100
						end

						local dim = cfgData.BackgroundDim
						if dim == nil then dim = 50 end
						if dim > 0 and dim <= 1 then dim = math.floor((1 - dim) * 100) end
						if WallDimSlider then
							WallDimSlider:SetValue(dim, true)
						else
							WindowBackgroundDim.BackgroundTransparency = 1 - (dim / 100)
						end
					end

					if cfgData.Elements and type(cfgData.Elements) == "table" then
						for _, elem in ipairs(ConfigElements) do
							local savedVal = cfgData.Elements[elem.Flag]
							if savedVal == nil then savedVal = cfgData.Elements[elem.Title] end
							if savedVal == nil and cfgData[elem.Flag] ~= nil then savedVal = cfgData[elem.Flag] end
							if savedVal ~= nil then
								pcall(function() elem.Set(savedVal) end)
							end
						end
					end
					task.delay(0.3, function()
						Tabs._suppressNotifications = false
					end)
				end
			end
		end)

		Library.CurrentWindow = Tabs
		if typeof(getgenv) == "function" then
			getgenv().CurrentWindow = Tabs
		end
		if typeof(_G) == "table" then
			_G.CurrentWindow = Tabs
		end
		if typeof(shared) == "table" then
			shared.CurrentWindow = Tabs
		end

		return Tabs
	end

	function Library:Notify(p)
		if Library.CurrentWindow and Library.CurrentWindow.Notify then
			return Library.CurrentWindow:Notify(p)
		end
	end

	exportGlobals(Library)

	return Library
end

function App.Shutdown(Force)
	if App.Stopped then
		return
	end
	App.Stopped = true
	for Index = #App.Cleanups, 1, -1 do
		pcall(App.Cleanups[Index])
	end
	for _, Connection in ipairs(App.Connections) do
		pcall(Connection.Disconnect, Connection)
	end
	table.clear(App.Connections)
	if App.OwnsInterface or Force == true then
		DestroyInterfaces()
	end
	if GetEnv.UniversalAether == App then
		GetEnv.UniversalAether = nil
	end
end

local function InterfaceExists()
	local Roots = { CoreGui, LocalPlayer:FindFirstChildOfClass("PlayerGui") }
	if Capabilities.GetHui then
		local Ok, Hui = pcall(gethui)
		if Ok and typeof(Hui) == "Instance" then
			table.insert(Roots, Hui)
		end
	end
	for _, Root in ipairs(Roots) do
		local Ok, Children = pcall(Root.GetChildren, Root)
		if Ok then
			for _, Child in ipairs(Children) do
				if Child:IsA("ScreenGui") and (table.find(Config.InterfaceNames, Child.Name) or Child:GetAttribute("AetherUI")) then
					return true
				end
			end
		end
	end
	return false
end

BuildOverlay()
App.Library = InterfaceExists() and FindPublishedLibrary() or nil
if not App.Library then

	DestroyInterfaces()
	local Loaded, Result = pcall(LoadInterface)
	App.Library = (Loaded and IsLibrary(Result)) and Result or nil
	App.OwnsInterface = App.Library ~= nil
end
if not App.Library then
	App.Shutdown()
	return
end

local Window = App.Library:Window({ Title = "Universal", Desc = "Aether", Theme = "Default" })
App.Window = Window
if not Window then
	App.Shutdown()
	return
end

local function AddToggle(Section, Title, Desc, Owner, Key, OnChange)
	local Element = Section:Toggle({
		Title = Title, Desc = Desc, Value = Owner[Key], IgnoreConfig = true,
		Callback = Guard(Title, function(Value)
			Owner[Key] = Value == true
			if OnChange then
				OnChange(Owner[Key])
			end
		end),
	})
	App.Elements[Title] = Element
	return Element
end

local function AddSlider(Section, Title, Desc, Min, Max, Owner, Key, Rounding, OnChange)
	return Section:Slider({
		Title = Title, Desc = Desc, Min = Min, Max = Max, Value = Owner[Key], Rounding = Rounding or 0,
		Callback = Guard(Title, function(Value)
			Owner[Key] = Clamp(Value, Min, Max)
			if OnChange then
				OnChange(Owner[Key])
			end
		end),
	})
end

local function AddDropdown(Section, Title, Desc, List, Owner, Key, OnChange)
	return Section:Dropdown({
		Title = Title, Desc = Desc, List = List, Value = Owner[Key],
		Callback = Guard(Title, function(Value)
			if type(Value) == "string" then
				Owner[Key] = Value
				if OnChange then
					OnChange(Value)
				end
			end
		end),
	})
end

local function AddButton(Section, Title, Desc, Function)
	return Section:Button({ Title = Title, Desc = Desc, Callback = Guard(Title, Function) })
end

local Hotkeys = { Fly = Enum.KeyCode.F, Noclip = Enum.KeyCode.N, WalkSpeed = Enum.KeyCode.G }
local HotkeyToggles = { Fly = "Fly", Noclip = "Noclip", WalkSpeed = "WalkSpeed" }

Track(UserInputService.InputBegan:Connect(function(Input, Processed)
	if Processed or UserInputService:GetFocusedTextBox() or Input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	for Name, Key in pairs(Hotkeys) do
		if Input.KeyCode == Key then
			local Element = App.Elements[HotkeyToggles[Name] .. " Enabled"]
			if Element and Element.SetValue then
				Element:SetValue(not Element:GetValue())
			end
		end
	end
end))

local function AddHotkey(Section, Name, Description)
	Section:Keybind({
		Title = Name .. " Hotkey", Desc = Description, Key = Hotkeys[Name], IgnoreConfig = true,
		Callback = function(Key)
			if typeof(Key) == "EnumItem" then
				Hotkeys[Name] = Key
			end
		end,
	})
end

local PlayerTab = Window:Tab({ Title = "Player", Icon = "user" })
local MovementSub = PlayerTab:SubTab("Movement")

local WalkSection = MovementSub:Section({ Title = "WalkSpeed" })
AddToggle(WalkSection, "WalkSpeed Enabled", "Property sets Humanoid.WalkSpeed; CFrame, Velocity and Tween move the root instead", Settings.WalkSpeed, "Enabled", function()
	WalkSpeed.Start()
end)
AddDropdown(WalkSection, "WalkSpeed Mode", "How the speed is applied", { "Property", "CFrame", "Velocity", "Tween" }, Settings.WalkSpeed, "Mode", function()
	WalkSpeed.Start()
end)
AddSlider(WalkSection, "WalkSpeed Value", "Studs per second", 1, 500, Settings.WalkSpeed, "Value", 0)
AddHotkey(WalkSection, "WalkSpeed", "Press to toggle WalkSpeed")

local JumpSection = MovementSub:Section({ Title = "Jump" })
AddToggle(JumpSection, "JumpPower Enabled", "Property sets JumpPower; Velocity launches the root upward", Settings.JumpPower, "Enabled", function()
	JumpPower.Start()
end)
AddDropdown(JumpSection, "JumpPower Mode", "How the jump is applied", { "Property", "Velocity" }, Settings.JumpPower, "Mode", function()
	JumpPower.Start()
end)
AddSlider(JumpSection, "JumpPower Value", "Jump strength", 10, 500, Settings.JumpPower, "Value", 0)
AddToggle(JumpSection, "Infinite Jump", "Jump again in mid air", Settings.InfiniteJump, "Enabled", function()
	InfiniteJump.Start()
end)

local FlySection = MovementSub:Section({ Title = "Fly" })
AddToggle(FlySection, "Fly Enabled", "Steer with your movement keys / thumbstick, Space or E up, Shift or Q down (UP / DOWN buttons on touch)", Settings.Fly, "Enabled", function()
	Fly.Start()
end)
AddDropdown(FlySection, "Fly Mode", "Velocity = physics, Smooth = eased physics, CFrame = direct move, Tween = stepped tweens", { "Velocity", "Smooth", "CFrame", "Tween" }, Settings.Fly, "Mode", function()
	if Settings.Fly.Enabled then
		Fly.Start()
	end
end)
AddSlider(FlySection, "Fly Speed", "Horizontal speed", 5, 500, Settings.Fly, "Speed", 0)
AddSlider(FlySection, "Fly Vertical Speed", "Up / down speed", 5, 500, Settings.Fly, "VerticalSpeed", 0)
AddSlider(FlySection, "Fly Smoothing", "Only used by Smooth mode (higher = snappier)", 1, 20, Settings.Fly, "Smoothing", 0)
AddToggle(FlySection, "Fly Noclip", "Pass through walls while flying", Settings.Fly, "Noclip", function(Value)
	if Settings.Fly.Enabled then
		Noclip.Sources.Fly = Value
		Noclip.Refresh()
	end
end)
AddToggle(FlySection, "Fly Face Camera", "Turn the character toward where the camera looks", Settings.Fly, "FaceCamera")
AddHotkey(FlySection, "Fly", "Press to toggle Fly")

local NoclipSection = MovementSub:Section({ Title = "Noclip" })
AddToggle(NoclipSection, "Noclip Enabled", "Walk through walls and parts", Settings.Noclip, "Enabled", function()
	Noclip.Refresh()
end)
AddHotkey(NoclipSection, "Noclip", "Press to toggle Noclip")

local TeleportSub = PlayerTab:SubTab("Teleport")
local ClickSection = TeleportSub:Section({ Title = "Click Teleport" })
AddToggle(ClickSection, "Click Teleport Enabled", "Click (or tap on mobile) the world to teleport there", Settings.ClickTeleport, "Enabled", function()
	Teleports.StartClick()
end)
AddToggle(ClickSection, "Click Teleport Needs Alt", "Hold Left Alt while clicking (PC only, taps always teleport)", Settings.ClickTeleport, "RequireKey")

local PlayerTeleportSection = TeleportSub:Section({ Title = "Players" })
local SelectedPlayer = ""
local PlayerDropdown = PlayerTeleportSection:Dropdown({
	Title = "Player", Desc = "Pick someone in the server", List = PlayerNames(), IgnoreConfig = true,
	Callback = function(Value)
		SelectedPlayer = type(Value) == "string" and Value or ""
	end,
})
local function RefreshPlayers()
	local Names = PlayerNames()
	if not table.find(Names, SelectedPlayer) then
		SelectedPlayer = Names[1] or ""
	end
	pcall(PlayerDropdown.Refresh, PlayerDropdown, Names, SelectedPlayer)
end
Track(Players.PlayerAdded:Connect(RefreshPlayers))
Track(Players.PlayerRemoving:Connect(function()
	task.defer(RefreshPlayers)
end))
AddButton(PlayerTeleportSection, "Teleport To Player", "Go next to the selected player", function()
	Teleports.ToPlayer(SelectedPlayer)
end)
AddButton(PlayerTeleportSection, "Spectate Player", "Move the camera onto the selected player", function()
	Teleports.Spectate(SelectedPlayer)
end)
AddButton(PlayerTeleportSection, "Stop Spectating", "Camera back to you", Teleports.StopSpectate)

local WaypointSection = TeleportSub:Section({ Title = "Waypoints" })
local WaypointName, SelectedWaypoint = "", ""
local WaypointDropdown = WaypointSection:Dropdown({
	Title = "Saved Waypoints", Desc = "Positions you saved this session", List = {}, IgnoreConfig = true,
	Callback = function(Value)
		SelectedWaypoint = type(Value) == "string" and Value or ""
	end,
})
local function RefreshWaypoints()
	if not table.find(Teleports.WaypointOrder, SelectedWaypoint) then
		SelectedWaypoint = Teleports.WaypointOrder[1] or ""
	end
	pcall(WaypointDropdown.Refresh, WaypointDropdown, Teleports.WaypointOrder, SelectedWaypoint)
end
WaypointSection:Textbox({
	Title = "Waypoint Name", Desc = "Leave empty for an automatic name", Placeholder = "Spawn", IgnoreConfig = true,
	Callback = function(Text)
		WaypointName = tostring(Text or "")
	end,
})
AddButton(WaypointSection, "Save Waypoint", "Store your current position", function()
	local Name = Teleports.AddWaypoint(WaypointName)
	if Name then
		SelectedWaypoint = Name
		RefreshWaypoints()
		Notify("Waypoint", "Saved " .. Name, "normal")
	end
end)
AddButton(WaypointSection, "Teleport To Waypoint", "Go to the selected waypoint", function()
	if not Teleports.GoToWaypoint(SelectedWaypoint) then
		Notify("Waypoint", "Pick a saved waypoint first", "warning")
	end
end)
AddButton(WaypointSection, "Delete Waypoint", "Remove the selected waypoint", function()
	if Teleports.RemoveWaypoint(SelectedWaypoint) then
		RefreshWaypoints()
	end
end)

local SafetySection = TeleportSub:Section({ Title = "Safety" })
AddToggle(SafetySection, "Anti Void", "Teleport back to your last safe spot when you fall out of the map", Settings.AntiVoid, "Enabled", function()
	Teleports.StartVoid()
end)

local CharacterSub = PlayerTab:SubTab("Character")
local ActionSection = CharacterSub:Section({ Title = "Actions" })
AddButton(ActionSection, "Reset Character", "Kill your character so it respawns", Misc.Reset)
AddButton(ActionSection, "Respawn Here", "Reset and return to the same spot", Misc.RespawnHere)
AddButton(ActionSection, "Sit", "Sit down where you stand", Misc.Sit)
AddButton(ActionSection, "Copy Position", "Copies X, Y, Z to the clipboard", Misc.CopyPosition)
AddButton(ActionSection, "Copy CFrame", "Copies a CFrame.new(...) line to the clipboard", Misc.CopyCFrame)

local CombatTab = Window:Tab({ Title = "Combat", Icon = "crosshair" })
local AimSub = CombatTab:SubTab("Aimbot")
local AimMain = AimSub:Section({ Title = "Aimbot" })
AddToggle(AimMain, "Aimbot Enabled", "Aims the camera (or mouse) at the best target", Settings.Aim, "Enabled", function()
	Aim.Start()
end)
AddDropdown(AimMain, "Aim Mode", "Hold = while the input is down, Toggle = press to switch, Always = constant", { "Hold", "Toggle", "Always" }, Settings.Aim, "Mode", function()
	Aim.Holding, Aim.Toggled = false, false
end)
AddDropdown(AimMain, "Aim Input", "PC input used for Hold / Toggle (touch uses the AIM button)", { "Right Mouse", "Left Mouse", "Left Shift", "Q", "E", "F", "Z", "X" }, Settings.Aim, "HoldInput")
AddDropdown(AimMain, "Aim Method", "Camera rotates the view, Mouse moves the cursor (PC executors with mousemoverel)", { "Camera", "Mouse" }, Settings.Aim, "Method")
AddDropdown(AimMain, "Aim Part", "Where to aim", { "Head", "Torso", "Root", "Closest" }, Settings.Aim, "Part")
AddDropdown(AimMain, "Aim Priority", "How the target is chosen inside the FOV", { "Cursor", "Distance", "Health" }, Settings.Aim, "Priority")

local AimTuning = AimSub:Section({ Title = "Tuning" })
AddSlider(AimTuning, "Aim FOV", "Radius of the target circle in pixels", 20, 800, Settings.Aim, "Fov", 0)
AddSlider(AimTuning, "Aim Smoothing", "1 = snap, higher = slower and more human", 1, 30, Settings.Aim, "Smoothing", 0)
AddSlider(AimTuning, "Aim Prediction", "Seconds of target velocity to lead by", 0, 1, Settings.Aim, "Prediction", 2)
AddSlider(AimTuning, "Aim Max Distance", "Ignore players farther than this", 50, 5000, Settings.Aim, "MaxDistance", 0)
AddToggle(AimTuning, "Aim Team Check", "Do not aim at teammates", Settings.Aim, "TeamCheck")
AddToggle(AimTuning, "Aim Wall Check", "Only aim at visible targets", Settings.Aim, "WallCheck")
AddToggle(AimTuning, "Aim Sticky Target", "Keep the current target while it stays inside the FOV", Settings.Aim, "Sticky")

local AimVisuals = AimSub:Section({ Title = "Display" })
AddToggle(AimVisuals, "Aim Show FOV", "Draw the FOV circle", Settings.Aim, "ShowFov")
AddDropdown(AimVisuals, "Aim FOV Origin", "Circle follows the mouse or stays centered (always centered on touch)", { "Mouse", "Center" }, Settings.Aim, "FovOrigin")
AddToggle(AimVisuals, "Aim Show Button", "Show the on-screen AIM button on touch devices", Settings.Aim, "ShowButton")
AimVisuals:ColorPicker({
	Title = "Aim FOV Color", Desc = "Circle color", Value = Settings.Aim.FovColor,
	Callback = function(Color)
		if typeof(Color) == "Color3" then
			Settings.Aim.FovColor = Color
		end
	end,
})

local EspSub = CombatTab:SubTab("ESP")
local EspMain = EspSub:Section({ Title = "ESP / Chams" })
AddToggle(EspMain, "ESP Enabled", "Highlights players through walls", Settings.Esp, "Enabled", function()
	Esp.Start()
end)
AddToggle(EspMain, "ESP Chams", "Colored outline and fill (closest 31 players)", Settings.Esp, "Chams")
AddToggle(EspMain, "ESP Boxes", "Box around each player", Settings.Esp, "Boxes")
AddToggle(EspMain, "ESP Names", "Display name above players", Settings.Esp, "Names")
AddToggle(EspMain, "ESP Health", "Health bar", Settings.Esp, "Health")
AddToggle(EspMain, "ESP Distance", "Distance in studs", Settings.Esp, "Distance")
AddToggle(EspMain, "ESP Tracers", "Line from the bottom of the screen to each player", Settings.Esp, "Tracers")
AddToggle(EspMain, "ESP Team Check", "Hide teammates", Settings.Esp, "TeamCheck")
AddToggle(EspMain, "ESP Team Colors", "Use each player's team color", Settings.Esp, "TeamColors")
AddSlider(EspMain, "ESP Max Distance", "Hide players farther than this", 50, 10000, Settings.Esp, "MaxDistance", 0)
AddSlider(EspMain, "ESP Fill Transparency", "0 = solid fill, 1 = outline only", 0, 1, Settings.Esp, "FillTransparency", 2)
EspMain:ColorPicker({
	Title = "ESP Enemy Color", Desc = "Color for enemies", Value = Settings.Esp.EnemyColor,
	Callback = function(Color)
		if typeof(Color) == "Color3" then
			Settings.Esp.EnemyColor = Color
		end
	end,
})
EspMain:ColorPicker({
	Title = "ESP Ally Color", Desc = "Color for teammates", Value = Settings.Esp.AllyColor,
	Callback = function(Color)
		if typeof(Color) == "Color3" then
			Settings.Esp.AllyColor = Color
		end
	end,
})

local HitboxSub = CombatTab:SubTab("Hitbox")
local HitboxSection = HitboxSub:Section({ Title = "Hitbox Expander" })
AddToggle(HitboxSection, "Hitbox Enabled", "Enlarges other players' root parts (client side only)", Settings.Hitbox, "Enabled", function()
	Hitbox.Start()
end)
AddSlider(HitboxSection, "Hitbox Size", "Studs per side", 2, 40, Settings.Hitbox, "Size", 0)
AddToggle(HitboxSection, "Hitbox Team Check", "Leave teammates alone", Settings.Hitbox, "TeamCheck")

local WorldTab = Window:Tab({ Title = "World", Icon = "globe" })
local LightingSub = WorldTab:SubTab("Lighting")
local LightingSection = LightingSub:Section({ Title = "Lighting" })
AddToggle(LightingSection, "Fullbright", "Bright ambient light everywhere", Settings.World, "Fullbright", World.Refresh)
AddToggle(LightingSection, "No Fog", "Remove fog and haze", Settings.World, "NoFog", World.Refresh)
AddToggle(LightingSection, "No Shadows", "Turn global shadows off", Settings.World, "NoShadows", World.Refresh)
AddToggle(LightingSection, "Lock Time", "Keep the clock on the time below", Settings.World, "LockTime", World.Refresh)
AddSlider(LightingSection, "Time Of Day", "Clock hour (0-24)", 0, 24, Settings.World, "TimeOfDay", 1, function(Value)
	Lighting.ClockTime = Value
end)
for _, Preset in ipairs({ { "Day", 14 }, { "Sunset", 17.5 }, { "Night", 0 } }) do
	AddButton(LightingSection, "Time: " .. Preset[1], "Set the clock to " .. Preset[1]:lower(), function()
		Settings.World.TimeOfDay = Preset[2]
		Lighting.ClockTime = Preset[2]
	end)
end

local CameraSub = WorldTab:SubTab("Camera & Physics")
local CameraSection = CameraSub:Section({ Title = "Camera" })
AddToggle(CameraSection, "Lock FOV", "Keep the field of view on the value below", Settings.World, "LockFov", World.Refresh)
AddSlider(CameraSection, "Field Of View", "Camera FOV", 30, 120, Settings.World, "Fov", 0)
AddSlider(CameraSection, "Max Zoom", "How far the camera can zoom out", 10, 1000, Settings.World, "MaxZoom", 0, World.SetMaxZoom)
local PhysicsSection = CameraSub:Section({ Title = "Physics" })
AddSlider(PhysicsSection, "Gravity", "Workspace gravity (196.2 is normal)", 0, 400, Settings.World, "Gravity", 1, World.SetGravity)
AddButton(PhysicsSection, "Reset Gravity", "Back to the game's gravity", function()
	World.SetGravity(World.OriginalGravity)
end)

local VisionSub = WorldTab:SubTab("Performance")
local VisionSection = VisionSub:Section({ Title = "Visibility" })
AddToggle(VisionSection, "X-Ray", "See through world parts", Settings.World, "XRay", World.SetXRay)
local PerformanceSection = VisionSub:Section({ Title = "Performance" })
AddSlider(PerformanceSection, "FPS Cap", "Needs setfpscap support", 15, 360, { Value = 60 }, "Value", 0, World.SetFpsCap)
AddButton(PerformanceSection, "Boost FPS", "Lower quality, drop effects and textures (cannot be undone until you rejoin)", World.BoostFps)

local ServerTab = Window:Tab({ Title = "Server", Icon = "server" })
local InfoSub = ServerTab:SubTab("Info")
local InfoSection = InfoSub:Section({ Title = "Game" })
local GameNameLabel = InfoSection:Label({ Title = "Experience", Desc = game.Name })
InfoSection:Label({ Title = "PlaceId", Desc = tostring(game.PlaceId) })
InfoSection:Label({ Title = "ExperienceId (UniverseId)", Desc = tostring(game.GameId) })
InfoSection:Label({ Title = "JobId", Desc = tostring(game.JobId) })
local LiveSection = InfoSub:Section({ Title = "Live" })
local PlayersLabel = LiveSection:Label({ Title = "Players", Desc = "..." })
local PerformanceLabel = LiveSection:Label({ Title = "Ping / FPS", Desc = "..." })
local UptimeLabel = LiveSection:Label({ Title = "Server Uptime", Desc = "..." })
local CopySection = InfoSub:Section({ Title = "Copy" })
AddButton(CopySection, "Copy PlaceId", "PlaceId of this place", function()
	CopyText(game.PlaceId, "PlaceId")
end)
AddButton(CopySection, "Copy ExperienceId", "UniverseId (game.GameId) of this experience", function()
	CopyText(game.GameId, "ExperienceId")
end)
AddButton(CopySection, "Copy JobId", "Id of this server instance", function()
	CopyText(game.JobId, "JobId")
end)
AddButton(CopySection, "Copy Game Link", "roblox.com link to this place", function()
	CopyText("https://www.roblox.com/games/" .. game.PlaceId, "Game link")
end)
AddButton(CopySection, "Copy Join Script", "Lua line that rejoins this exact server", function()
	CopyText(string.format("game:GetService('TeleportService'):TeleportToPlaceInstance(%d, '%s', game.Players.LocalPlayer)", game.PlaceId, game.JobId), "Join script")
end)
AddButton(CopySection, "Copy My UserId", "Your account id", function()
	CopyText(LocalPlayer.UserId, "UserId")
end)
AddButton(CopySection, "Copy My Username", "Your account name", function()
	CopyText(LocalPlayer.Name, "Username")
end)

task.spawn(function()
	local Name = Server.GetGameName()
	if IsRunning() and GameNameLabel and GameNameLabel.SetDesc then
		pcall(GameNameLabel.SetDesc, GameNameLabel, Name)
	end
	while IsRunning() do
		pcall(function()
			PlayersLabel:SetDesc(string.format("%d / %d", #Players:GetPlayers(), Players.MaxPlayers))
			PerformanceLabel:SetDesc(string.format("%d ms  /  %d fps", Server.GetPing(), Server.Fps))
			local Seconds = math.floor(Workspace.DistributedGameTime)
			UptimeLabel:SetDesc(string.format("%02d:%02d:%02d", Seconds // 3600, (Seconds % 3600) // 60, Seconds % 60))
		end)
		task.wait(1)
	end
end)

local HopSub = ServerTab:SubTab("Teleport")
local HopSection = HopSub:Section({ Title = "Server" })
local HopSettings = { Mode = "Smallest" }
AddButton(HopSection, "Rejoin", "Rejoin this server (or the place when you are alone)", Server.Rejoin)
AddDropdown(HopSection, "Hop Mode", "Smallest = fewest players, Largest = most, Best Ping = lowest ping", { "Smallest", "Largest", "Random", "Best Ping" }, HopSettings, "Mode")
AddButton(HopSection, "Server Hop", "Join a different public server", function()
	Server.Hop(HopSettings.Mode)
end)
local JoinSection = HopSub:Section({ Title = "Join" })
local JoinState = { JobId = "", PlaceId = "" }
JoinSection:Textbox({
	Title = "JobId", Desc = "Join a specific server of this place", Placeholder = "paste a JobId", IgnoreConfig = true,
	Callback = function(Text)
		JoinState.JobId = tostring(Text or "")
	end,
})
AddButton(JoinSection, "Join JobId", "Teleport to that server", function()
	Server.JoinJob(JoinState.JobId)
end)
JoinSection:Textbox({
	Title = "PlaceId", Desc = "Teleport to another place", Placeholder = "paste a PlaceId", IgnoreConfig = true,
	Callback = function(Text)
		JoinState.PlaceId = tostring(Text or "")
	end,
})
AddButton(JoinSection, "Teleport To Place", "Go to that place", function()
	Server.TeleportPlace(JoinState.PlaceId)
end)
local ConnectionSection = HopSub:Section({ Title = "Connection" })
AddToggle(ConnectionSection, "Anti AFK", "Stops the 20 minute idle kick", Settings.AntiAfk, "Enabled", function()
	Server.StartAfk()
end)
AddToggle(ConnectionSection, "Auto Rejoin", "Rejoin automatically when you get disconnected", Settings.AutoRejoin, "Enabled", function()
	Server.StartAutoRejoin()
end)
AddButton(ConnectionSection, "Unload Script", "Turn every feature off and remove this interface", function()
	App.Shutdown(true)
end)

local CosmeticsTab = Window:Tab({ Title = "Cosmetics", Icon = "sparkles" })
local CosmeticsState = Cosmetics.State

local function AddFeatureToggle(Section, Title, Desc, Key)
	return Section:Toggle({
		Title = Title, Desc = Desc, Value = false, IgnoreConfig = true,
		Callback = Guard(Title, function(Value)
			Cosmetics.SetFeature(Key, Value == true)
		end),
	})
end

local AvatarSub = CosmeticsTab:SubTab("Avatar")
local BodySection = AvatarSub:Section({ Title = "Body" })
AddFeatureToggle(BodySection, "Korblox Leg", "Crystal right leg (R6 / R15)", "Korblox")
AddFeatureToggle(BodySection, "Headless", "Hide head and face", "Headless")
AddFeatureToggle(BodySection, "Super Super Happy Face", "Face decal 494291269", "Face")
AddFeatureToggle(BodySection, "Hide Face", "Hide your face", "ClearFace")
AddFeatureToggle(BodySection, "Hide Clothes", "Remove shirt, pants and t-shirt", "ClearClothes")
AddFeatureToggle(BodySection, "Hide Accessories", "Remove avatar hair and hats (items added here stay)", "ClearAccessories")
AddButton(BodySection, "T-Pose", "Freeze the character without animations", function()
	Cosmetics.ApplyTPose(GetCharacter())
end)
AddButton(BodySection, "Restore Animations", "Back from T-Pose", function()
	Cosmetics.StopTPose(GetCharacter())
end)

local LookSection = AvatarSub:Section({ Title = "Look & Size" })
LookSection:Dropdown({
	Title = "Body Color", Desc = "Skin / body color", List = Cosmetics.BodyColors, Value = Cosmetics.BodyColors[1], IgnoreConfig = true,
	Callback = Guard("Body Color", function(Value)
		if type(Value) == "string" then
			CosmeticsState.BodyColorName = Value
			Cosmetics.ApplyBodyColor(GetCharacter())
		end
	end),
})
local MaterialNames = { "None" }
for Name in pairs(Cosmetics.Materials) do
	table.insert(MaterialNames, Name)
end
table.sort(MaterialNames, function(Left, Right)
	if Left == "None" or Right == "None" then
		return Left == "None"
	end
	return Left < Right
end)
LookSection:Dropdown({
	Title = "Body Material", Desc = "Neon, glass, gold, ice, forcefield or diamond", List = MaterialNames, Value = "None", IgnoreConfig = true,
	Callback = Guard("Body Material", function(Value)
		if type(Value) ~= "string" then
			return
		end
		if Value == "None" then
			Cosmetics.ApplyMaterial(GetCharacter(), nil)
			CosmeticsState.MaterialMode = nil
		else
			Cosmetics.SetMaterial(Value)
		end
	end),
})
for _, Entry in ipairs({
	{ "Body Height", "Height", 0.6, 1.4, 2 }, { "Body Width", "Width", 0.6, 1.4, 2 }, { "Head Size", "Head", 0.5, 1.5, 2 },
	{ "Proportions", "Proportion", 0, 1, 1 }, { "Body Type", "BodyType", 0, 1, 1 },
}) do
	LookSection:Slider({
		Title = Entry[1], Desc = "Humanoid scale (R15)", Min = Entry[3], Max = Entry[4], Value = CosmeticsState.Scales[Entry[2]], Rounding = Entry[5], IgnoreConfig = true,
		Callback = Guard(Entry[1], function(Value)
			Cosmetics.SetScale(Entry[2], Clamp(Value, Entry[3], Entry[4]))
		end),
	})
end

local EffectSection = AvatarSub:Section({ Title = "Effects" })
AddFeatureToggle(EffectSection, "Rainbow Trail", "Rainbow trail while you move", "Trail")
AddFeatureToggle(EffectSection, "Fire Aura", "Rising flames", "Fire")
AddFeatureToggle(EffectSection, "Lightning Aura", "Electric sparks and light", "Lightning")
AddFeatureToggle(EffectSection, "Golden Sparkles", "Gold twinkles", "Sparkles")
AddFeatureToggle(EffectSection, "Smoke Aura", "Rolling smoke", "Smoke")

local AccessorySub = CosmeticsTab:SubTab("Accessories")
for _, Category in ipairs({ { "Head", "Head Items" }, { "Face", "Face Items" }, { "Other", "Other Items" } }) do
	local Section = AccessorySub:Section({ Title = Category[2] })
	for _, Item in ipairs(Cosmetics.AccessoryItems) do
		if Item.Category == Category[1] then
			AddFeatureToggle(Section, Item.Name, "Asset " .. Item.Id, Item.Id)
		end
	end
end

local AdjustSection = AccessorySub:Section({ Title = "Adjust & Manage" })
local AdjustTarget = ""
local AdjustDropdown = AdjustSection:Dropdown({
	Title = "Worn Accessory", Desc = "Pick one of the accessories you added (press Refresh)", List = {}, IgnoreConfig = true,
	Callback = function(Value)
		AdjustTarget = type(Value) == "string" and Value or ""
	end,
})
AddButton(AdjustSection, "Refresh Worn List", "Reload the list of added accessories", function()
	local Worn = Cosmetics.GetWornAccessories()
	if not table.find(Worn, AdjustTarget) then
		AdjustTarget = Worn[1] or ""
	end
	pcall(AdjustDropdown.Refresh, AdjustDropdown, Worn, AdjustTarget)
end)
for _, Entry in ipairs({ { "Offset X", "X", -3, 3 }, { "Offset Y", "Y", -3, 3 }, { "Offset Z", "Z", -3, 3 }, { "Scale", "Scale", 0.2, 3 } }) do
	AdjustSection:Slider({
		Title = "Adjust " .. Entry[1], Desc = "Applies to the selected accessory", Min = Entry[3], Max = Entry[4],
		Value = Entry[2] == "Scale" and 1 or 0, Rounding = 2, IgnoreConfig = true,
		Callback = Guard("Adjust " .. Entry[1], function(Value)
			local Id = tonumber(AdjustTarget)
			if Id then
				Cosmetics.GetAdjust(Id)[Entry[2]] = Clamp(Value, Entry[3], Entry[4])
				Cosmetics.ApplyAdjust(GetCharacter(), Id)
			end
		end),
	})
end
AddButton(AdjustSection, "Reset Adjust", "Put the selected accessory back", function()
	local Id = tonumber(AdjustTarget)
	if Id then
		Cosmetics.ResetAdjust(Id)
	end
end)
AddButton(AdjustSection, "Remove All Added Accessories", "Take off everything added by this script", function()
	local Count = Cosmetics.RemoveAllAccessories()
	Notify("Cosmetics", Count .. " accessories removed", "normal")
end)

local SearchSection = AccessorySub:Section({ Title = "Catalog Search" })
local SearchState = { Query = "", Mode = "Accessory", Selected = "" }
SearchSection:Textbox({
	Title = "Search Name", Desc = "Searches the Roblox catalog by name", Placeholder = "e.g. dominus", IgnoreConfig = true,
	Callback = function(Text)
		SearchState.Query = tostring(Text or "")
	end,
})
AddDropdown(SearchSection, "Search Type", "Accessories to wear, or animations / emotes to play", { "Accessory", "Animation" }, SearchState, "Mode")
local ResultDropdown
local ResultLookup = {}
AddButton(SearchSection, "Search", "Run the search", function()
	Cosmetics.Search(SearchState.Query, SearchState.Mode, function(Results, Reached, Reason)
		table.clear(ResultLookup)
		local Names = {}
		for _, Item in ipairs(Results) do
			local Label = string.format("%s [%s]", tostring(Item.name or "?"), tostring(Item.id))
			ResultLookup[Label] = Item
			table.insert(Names, Label)
		end
		SearchState.Selected = Names[1] or ""
		if ResultDropdown then
			pcall(ResultDropdown.Refresh, ResultDropdown, Names, SearchState.Selected)
		end
		if Reason then
			Notify("Catalog", Reason, "warning")
		else
			Notify("Catalog", Reached and (#Names .. " results") or "HTTP failed, this executor cannot reach the catalog", Reached and "normal" or "warning")
		end
	end)
end)
ResultDropdown = SearchSection:Dropdown({
	Title = "Results", Desc = "Pick an item", List = {}, IgnoreConfig = true,
	Callback = function(Value)
		SearchState.Selected = type(Value) == "string" and Value or ""
	end,
})
AddButton(SearchSection, "Wear / Play Selected", "Accessories are worn, animations are played", function()
	local Item = ResultLookup[SearchState.Selected]
	if not Item then
		Notify("Catalog", "Search and pick a result first", "warning")
		return
	end
	if SearchState.Mode == "Accessory" then
		Cosmetics.WearAccessory(tonumber(Item.id))
	elseif not Cosmetics.PlayEmote(Item.name, tonumber(Item.id)) then
		Notify("Catalog", "That animation could not be played", "warning")
	end
end)

local AnimationSub = CosmeticsTab:SubTab("Animation")
local PackSection = AnimationSub:Section({ Title = "Animation Packs" })
local PackNames = { "Default" }
for Name in pairs(Cosmetics.AnimationPacks) do
	table.insert(PackNames, Name)
end
table.sort(PackNames, function(Left, Right)
	if Left == "Default" or Right == "Default" then
		return Left == "Default"
	end
	return Left < Right
end)
PackSection:Dropdown({
	Title = "Animation Pack", Desc = "Idle, walk, run, jump and more", List = PackNames, Value = "Default", IgnoreConfig = true,
	Callback = Guard("Animation Pack", function(Value)
		if type(Value) == "string" and not Cosmetics.ApplyAnimationPack(Value) then
			Notify("Animation", "Your character has no Animate script yet", "warning")
		end
	end),
})
local DanceSection = AnimationSub:Section({ Title = "Dances & Emotes" })
for _, Dance in ipairs(Cosmetics.Dances) do
	AddButton(DanceSection, Dance.Name, "Looped dance", function()
		Cosmetics.PlayAnimation(Dance.Id, true)
	end)
end
for _, Emote in ipairs(Cosmetics.Emotes) do
	AddButton(DanceSection, "Emote: " .. Emote.Name, "Plays the emote", function()
		if not Cosmetics.PlayEmote(Emote.Name, Emote.Id) then
			Notify("Emote", "Could not play " .. Emote.Name, "warning")
		end
	end)
end
local CustomAnimation = AnimationSub:Section({ Title = "Custom Animation" })
local CustomState = { Id = "", Loop = false }
CustomAnimation:Textbox({
	Title = "Animation Id", Desc = "Any animation or emote asset id", Placeholder = "paste an id", IgnoreConfig = true,
	Callback = function(Text)
		CustomState.Id = tostring(Text or "")
	end,
})
AddToggle(CustomAnimation, "Loop Custom Animation", "Repeat the animation", CustomState, "Loop")
AddButton(CustomAnimation, "Play Custom Animation", "Play the id above", function()
	local Id = tonumber(CustomState.Id)
	if not Id or not Cosmetics.PlayAnimation(Id, CustomState.Loop) then
		Notify("Animation", "That id could not be played", "warning")
	end
end)
AddButton(CustomAnimation, "Stop Animation", "Stop dances and custom animations", Cosmetics.StopCustomAnimation)

Server.StartAfk()
RefreshPlayers()
Notify("Aether", "This game isn't supported yet, but you can use our Universal script instead. If this is an error, please report it to us.", "normal")
end;n();return end;local KeySystem = {
    _version = "2.1.0",
    _title = "Aether",
    _subtitle = "Studios",
    _tag = "KEY SYSTEM",
    _service = "Aether Studios",
    _identifier = "1001263",
    _provider = "Free Key",
    _buyLink = "https://discord.gg/getaether",
    _discordLink = "https://discord.gg/getaether",
    _saveKey = true,
    _keyFile = nil,
    _keyless = false,
    _callback = nil,
    _isVerifying = false,
}

local genv = (typeof(getgenv) == "function" and getgenv()) or _G
local Session = genv.AetherSession
if type(Session) ~= "table" then
    Session = genv.AetherRuntime and genv.AetherRuntime.new()
    if not Session then
        Session = { task = task }
        function Session:Track(x) return x end
        function Session:Service(n) return game:GetService(n) end
    end
    genv.AetherSession = Session
end
local task = Session.task

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = Session:Service("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = Session:Service("RunService")
local StatsService = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

local Theme = {
    Shadow = Color3.fromRGB(0, 0, 0),
    Background = Color3.fromRGB(12, 12, 14),
    Header = Color3.fromRGB(14, 14, 17),
    Card = Color3.fromRGB(19, 19, 23),
    CardBorder = Color3.fromRGB(36, 36, 44),
    CardHover = Color3.fromRGB(26, 26, 32),
    InputBackground = Color3.fromRGB(15, 15, 18),
    InputBorder = Color3.fromRGB(44, 44, 54),
    Main = Color3.fromRGB(255, 255, 255),
    MainDark = Color3.fromRGB(14, 14, 17),
    MainLight = Color3.fromRGB(230, 230, 235),
    Text = Color3.fromRGB(255, 255, 255),
    SubText = Color3.fromRGB(140, 140, 150),
    Placeholder = Color3.fromRGB(100, 100, 115),
    Success = Color3.fromRGB(34, 197, 94),
    Error = Color3.fromRGB(255, 60, 70),
    Warning = Color3.fromRGB(255, 175, 40),
}

local function tw(info)
    if type(info) ~= "table" then
        return { Play = function() end, Cancel = function() end, Completed = { Connect = function() end } }
    end

    local target = info.v
    if not target or typeof(target) ~= "Instance" then
        return { Play = function() end, Cancel = function() end, Completed = { Connect = function() end } }
    end

    local t = tonumber(info.t) or 0.2

    local s = Enum.EasingStyle.Quad
    if typeof(info.s) == "EnumItem" then
        s = info.s
    elseif type(info.s) == "string" then
        local styleName = info.s:sub(1, 1):upper() .. info.s:sub(2)
        local ok, res = pcall(function() return Enum.EasingStyle[styleName] end)
        if ok and res then
            s = res
        else
            local ok2, res2 = pcall(function() return Enum.EasingStyle[info.s] end)
            if ok2 and res2 then s = res2 end
        end
    end

    local d = Enum.EasingDirection.Out
    if typeof(info.d) == "EnumItem" then
        d = info.d
    elseif type(info.d) == "string" then
        local dirLower = info.d:lower()
        if dirLower == "in" then
            d = Enum.EasingDirection.In
        elseif dirLower == "out" then
            d = Enum.EasingDirection.Out
        elseif dirLower == "inout" then
            d = Enum.EasingDirection.InOut
        else
            local ok, res = pcall(function() return Enum.EasingDirection[info.d] end)
            if ok and res then d = res end
        end
    end

    local g = (type(info.g) == "table") and info.g or {}

    local success, tween = pcall(function()
        return TweenService:Create(
            target,
            TweenInfo.new(t, s, d, info.repeatCount or 0, info.reverses or false, info.delayTime or 0),
            g
        )
    end)

    if success and tween then
        return tween
    end

    return { Play = function() end, Cancel = function() end, Completed = { Connect = function() end } }
end

local function attachAutoScale(frame, baseW, baseH, fill)
    fill = fill or 0.9
    local scale = Instance.new("UIScale")
    scale.Name = "AutoScale"
    scale.Parent = frame
    local cam
    local camConn
    local function update()
        local c = workspace.CurrentCamera
        local vp = c and c.ViewportSize or Vector2.new(1920, 1080)
        if vp.X < 2 or vp.Y < 2 then return end
        scale.Scale = math.clamp(math.min((vp.X * fill) / baseW, (vp.Y * fill) / baseH, 1), 0.35, 1)
    end
    local function bindCamera()
        if camConn then camConn:Disconnect() end
        cam = workspace.CurrentCamera
        if cam then
            camConn = Session:Track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(update))
        end
        update()
    end
    Session:Track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
    frame.Destroying:Connect(function() if camConn then camConn:Disconnect() end end)
    bindCamera()
    return scale
end

local function getGuiParent()
    local success, _ = pcall(function() return CoreGui:GetChildren() end)
    if success then return CoreGui end
    return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or game:GetService("StarterGui")
end

local ClickSound = Instance.new("Sound")
ClickSound.Name = "AetherClickSound"
ClickSound.Parent = SoundService
ClickSound.Volume = 0.55
ClickSound.SoundId = "rbxassetid://6895079853"

local function playClickSound()
    pcall(function()
        SoundService:PlayLocalSound(ClickSound)
    end)
end

local IconList = nil
pcall(function()
    IconList = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/Aether/refs/heads/main/Icons.lua"))()
end)

local FallbackAssetIcons = {
    ["key"] = "rbxassetid://10709790387",
    ["key-round"] = "rbxassetid://10709790387",
    ["shield-check"] = "rbxassetid://10734952480",
    ["shield"] = "rbxassetid://10734952480",
    ["copy"] = "rbxassetid://10709790387",
    ["check"] = "rbxassetid://10709790202",
    ["external-link"] = "rbxassetid://10709810817",
    ["shopping-cart"] = "rbxassetid://10747373176",
    ["shopping-bag"] = "rbxassetid://10747373176",
    ["sparkles"] = "rbxassetid://10709819266",
    ["lock"] = "rbxassetid://10709790387",
    ["discord"] = "rbxassetid://119690296342461",
    ["user"] = "rbxassetid://10747373176",
    ["clock"] = "rbxassetid://10709789965",
    ["arrow-right"] = "rbxassetid://10709791437",
    ["x"] = "rbxassetid://15082305656",
    ["minus"] = "rbxassetid://10734896206",
}

local function gl(name)
    if type(name) == "string" then
        local key = string.lower(name)
        if key == "discord" then
            return { Image = "rbxassetid://119690296342461", ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
        end
        if IconList and IconList.Icons and IconList.Icons[key] then
            local iconData = IconList.Icons[key]
            local spriteSheet = IconList.Spritesheets and IconList.Spritesheets[tostring(iconData.Image)]
            if spriteSheet then
                return { Image = spriteSheet, ImageRectSize = iconData.ImageRectSize, ImageRectPosition = iconData.ImageRectPosition }
            end
        end
        if FallbackAssetIcons[key] then
            return { Image = FallbackAssetIcons[key], ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
        end
    end
    if type(name) == "number" or (type(name) == "string" and tonumber(name)) then
        return { Image = "rbxassetid://" .. tostring(name), ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
    end
    return { Image = (type(name) == "string" and name ~= "") and name or "rbxassetid://10709790387", ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
end

local function makeDraggable(dragHandle, targetFrame)
    local isDragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            dragStart = input.Position
            startPos = targetFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    isDragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and isDragging then
            local delta = input.Position - dragStart
            tw({
                v = targetFrame,
                t = 0.04,
                s = Enum.EasingStyle.Linear,
                d = "InOut",
                g = { Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y) }
            }):Play()
        end
    end)
end

local function createRipple(container, targetFrame)
    pcall(function()
        local mouse = LocalPlayer and LocalPlayer:GetMouse()
        local relativeX = container.AbsoluteSize.X / 2
        local relativeY = container.AbsoluteSize.Y / 2
        if mouse then
            local mx = mouse.X - container.AbsolutePosition.X
            local my = mouse.Y - container.AbsolutePosition.Y
            if mx >= 0 and my >= 0 and mx <= container.AbsoluteSize.X and my <= container.AbsoluteSize.Y then
                relativeX = mx
                relativeY = my
            end
        end

        local ripple = Instance.new("Frame")
        ripple.Parent = targetFrame or container
        ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        ripple.BackgroundTransparency = 0.72
        ripple.BorderSizePixel = 0
        ripple.AnchorPoint = Vector2.new(0.5, 0.5)
        ripple.Position = UDim2.new(0, relativeX, 0, relativeY)
        ripple.Size = UDim2.new(0, 0, 0, 0)
        ripple.ZIndex = 25

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = ripple

        local tween = TweenService:Create(
            ripple,
            TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Size = UDim2.new(0, container.AbsoluteSize.X * 1.5, 0, container.AbsoluteSize.X * 1.5),
                BackgroundTransparency = 1
            }
        )
        tween.Completed:Connect(function() ripple:Destroy() end)
        tween:Play()
    end)
end

local function setClip(text)
    if setclipboard then
        setclipboard(text)
        return true
    elseif toclipboard then
        toclipboard(text)
        return true
    end
    return false
end

local function saveKeyToFile(path, key)
    pcall(function()
        if type(writefile) == "function" then
            local folder = string.match(path, "^(.-)/")
            if folder and type(makefolder) == "function" and type(isfolder) == "function" then
                if not isfolder(folder) then makefolder(folder) end
            end
            writefile(path, key)
        end
    end)
end

local function loadKeyFromFile(path)
    local key = nil
    pcall(function()
        if type(readfile) == "function" and type(isfile) == "function" then
            if isfile(path) then
                key = readfile(path)
            end
        end
    end)
    return key
end

local function getExecutorName()
    local name = nil
    pcall(function()
        if type(identifyexecutor) == "function" then
            name = identifyexecutor()
        elseif type(getexecutorname) == "function" then
            name = getexecutorname()
        end
    end)
    return name or "Universal"
end

local Jnkie = {
    SDK = nil,
    Loaded = true
}

function Jnkie:Init(service, identifier, provider)
    if self.SDK then return self.SDK end
    
    -- Sahte SDK oluşturuyoruz, dış bağlantı tamamen silindi.
    local sdk = {
        service = service or "Aether Studios",
        identifier = identifier or "1001263",
        provider = provider or "Free Key",
        check_key = function(key) return {valid = true, message = "KEYLESS"} end,
        get_key_link = function() return "" end
    }
    
    self.SDK = sdk
    return sdk
end

function Jnkie:CheckKey(key)
    -- Asla dışarıya bağlanma, direkt KEYLESS onayı ver.
    return true, "KEYLESS"
end

function Jnkie:GetKeyLink()
    return ""
end

local NotificationContainer = nil

local function showNotification(params)
    params = params or {}
    local title = params.Title or "Aether"
    local desc = params.Desc or ""
    local duration = params.Time or 3.5
    local nType = params.Type or "normal"

    if not NotificationContainer or not NotificationContainer.Parent then return end

    local accentColor = Theme.Main
    if nType == "success" then
        accentColor = Theme.Success
    elseif nType == "error" then
        accentColor = Theme.Error
    elseif nType == "warning" then
        accentColor = Theme.Warning
    end

    local notifCard = Instance.new("Frame")
    local cardCorner = Instance.new("UICorner")
    local cardStroke = Instance.new("UIStroke")
    local indicator = Instance.new("Frame")
    local indicatorCorner = Instance.new("UICorner")
    local titleLabel = Instance.new("TextLabel")
    local descLabel = Instance.new("TextLabel")
    local progressBar = Instance.new("Frame")

    notifCard.Name = "NotifCard"
    notifCard.Parent = NotificationContainer
    notifCard.BackgroundColor3 = Theme.Card
    notifCard.BorderSizePixel = 0
    notifCard.Size = UDim2.new(1, 0, 0, (desc ~= "" and 54 or 38))
    notifCard.ClipsDescendants = true
    notifCard.BackgroundTransparency = 1

    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = notifCard

    cardStroke.Color = Theme.CardBorder
    cardStroke.Thickness = 1.2
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = notifCard

    indicator.Name = "Indicator"
    indicator.Parent = notifCard
    indicator.BackgroundColor3 = accentColor
    indicator.BorderSizePixel = 0
    indicator.Position = UDim2.new(0, 0, 0, 0)
    indicator.Size = UDim2.new(0, 3, 1, 0)

    indicatorCorner.CornerRadius = UDim.new(0, 2)
    indicatorCorner.Parent = indicator

    titleLabel.Name = "Title"
    titleLabel.Parent = notifCard
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.new(0, 12, 0, 8)
    titleLabel.Size = UDim2.new(1, -20, 0, 15)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = tostring(title)
    titleLabel.TextColor3 = Theme.Text
    titleLabel.TextSize = 12
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left

    if desc ~= "" then
        descLabel.Name = "Desc"
        descLabel.Parent = notifCard
        descLabel.BackgroundTransparency = 1
        descLabel.Position = UDim2.new(0, 12, 0, 26)
        descLabel.Size = UDim2.new(1, -20, 0, 20)
        descLabel.Font = Enum.Font.Gotham
        descLabel.Text = tostring(desc)
        descLabel.TextColor3 = Theme.SubText
        descLabel.TextSize = 10.5
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextWrapped = true
    end

    progressBar.Name = "ProgressBar"
    progressBar.Parent = notifCard
    progressBar.BackgroundColor3 = accentColor
    progressBar.BorderSizePixel = 0
    progressBar.Position = UDim2.new(0, 0, 1, -2)
    progressBar.Size = UDim2.new(1, 0, 0, 2)

    tw({
        v = progressBar,
        t = duration,
        s = Enum.EasingStyle.Linear,
        d = "Out",
        g = { Size = UDim2.new(0, 0, 0, 2) }
    }):Play()

    notifCard.Position = UDim2.new(1, 30, 0, 0)
    tw({
        v = notifCard,
        t = 0.25,
        s = Enum.EasingStyle.Cubic,
        d = "Out",
        g = { BackgroundTransparency = 0, Position = UDim2.new(0, 0, 0, 0) }
    }):Play()

    task.delay(duration, function()
        if notifCard and notifCard.Parent then
            local close = tw({
                v = notifCard,
                t = 0.25,
                s = Enum.EasingStyle.Quad,
                d = "In",
                g = { BackgroundTransparency = 1, Position = UDim2.new(1, 30, 0, 0) }
            })
            close:Play()
            close.Completed:Connect(function()
                if notifCard then notifCard:Destroy() end
            end)
        end
    end)
end

function KeySystem:Init(config)
    config = config or {}
    self._title = config.Title or self._title
    self._subtitle = config.SubTitle or self._subtitle
    self._tag = config.Tag or self._tag
    self._service = config.Service or self._service
    self._identifier = config.Identifier or self._identifier
    self._provider = config.Provider or self._provider
    self._buyLink = config.BuyLink or self._buyLink
    self._discordLink = config.DiscordLink or self._discordLink
    self._saveKey = (config.SaveKey ~= nil) and config.SaveKey or self._saveKey
    self._keyFile = config.KeyFile or self._keyFile
        or ("Aether/Key_" .. tostring(self._service):gsub("[^%w]", "") .. ".txt")
    self._keyless = (config.Keyless ~= nil) and config.Keyless or self._keyless
    self._callback = config.Callback or self._callback

    local isKeyVerified = false
    local isCancelled = false
    getgenv().UI_CLOSED = false

    local isExplicitKeyless = (self._keyless == true) or (config.Keyless == true)

    if isExplicitKeyless then
        getgenv().SCRIPT_KEY = "KEYLESS"
        if self._callback and type(self._callback) == "function" then
            task.spawn(self._callback, "KEYLESS")
        end
        return {
            ScreenGui = nil,
            Success = true,
            Key = "KEYLESS",
            IsKeyless = true
        }
    end

    local isJnkieKeyless = false
    pcall(function()
        Jnkie:Init(self._service, self._identifier, self._provider)
        local validKeyless, msgKeyless = Jnkie:CheckKey("KEYLESS")
        if validKeyless and (msgKeyless == "KEYLESS" or msgKeyless == "KEY_VALID") then
            isJnkieKeyless = true
        end
    end)

    if isJnkieKeyless then
        getgenv().SCRIPT_KEY = "KEYLESS"
        if self._callback and type(self._callback) == "function" then
            task.spawn(self._callback, "KEYLESS")
        end
        return {
            ScreenGui = nil,
            Success = true,
            Key = "KEYLESS",
            IsKeyless = true
        }
    end

    if getgenv().SCRIPT_KEY and type(getgenv().SCRIPT_KEY) == "string" and getgenv().SCRIPT_KEY ~= "" then
        Jnkie:Init(self._service, self._identifier, self._provider)
        local isValid, message = Jnkie:CheckKey(getgenv().SCRIPT_KEY)
        if isValid then
            if self._saveKey and getgenv().SCRIPT_KEY ~= "KEYLESS" then
                saveKeyToFile(self._keyFile, getgenv().SCRIPT_KEY)
            end
            if self._callback and type(self._callback) == "function" then
                task.spawn(self._callback, getgenv().SCRIPT_KEY)
            end
            return {
                ScreenGui = nil,
                Success = true,
                Key = getgenv().SCRIPT_KEY,
                IsKeyless = (message == "KEYLESS" or getgenv().SCRIPT_KEY == "KEYLESS")
            }
        else
            getgenv().SCRIPT_KEY = nil
        end
    end

    local savedKey = loadKeyFromFile(self._keyFile)
    if savedKey and type(savedKey) == "string" and savedKey ~= "" then
        Jnkie:Init(self._service, self._identifier, self._provider)
        local isValid, message = Jnkie:CheckKey(savedKey)
        if isValid then
            getgenv().SCRIPT_KEY = savedKey
            if self._callback and type(self._callback) == "function" then
                task.spawn(self._callback, savedKey)
            end
            return {
                ScreenGui = nil,
                Success = true,
                Key = savedKey,
                IsKeyless = (message == "KEYLESS")
            }
        end
    end

    local parentGui = getGuiParent()
    pcall(function()
        local parentsToSearch = {parentGui}
        if CoreGui and not table.find(parentsToSearch, CoreGui) then table.insert(parentsToSearch, CoreGui) end
        if typeof(gethui) == "function" then
            local h = gethui()
            if h and not table.find(parentsToSearch, h) then table.insert(parentsToSearch, h) end
        end
        local lp = Players.LocalPlayer
        local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
        if pg and not table.find(parentsToSearch, pg) then table.insert(parentsToSearch, pg) end

        for _, p in ipairs(parentsToSearch) do
            local existing = p:FindFirstChild("AetherKeySystem")
            if existing then
                pcall(function() existing:Destroy() end)
            end
        end
    end)

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "AetherKeySystem"
    Session:Track(ScreenGui)
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 1000
    ScreenGui:SetAttribute("AetherUI", true)
    ScreenGui.Parent = parentGui

    NotificationContainer = Instance.new("Frame")
    local notifLayout = Instance.new("UIListLayout")
    local notifPadding = Instance.new("UIPadding")

    NotificationContainer.Name = "Notifications"
    NotificationContainer.Parent = ScreenGui
    NotificationContainer.AnchorPoint = Vector2.new(1, 0)
    NotificationContainer.Position = UDim2.new(1, -20, 0, 20)
    NotificationContainer.Size = UDim2.new(0, 270, 1, -40)
    NotificationContainer.BackgroundTransparency = 1
    NotificationContainer.BorderSizePixel = 0
    NotificationContainer.ZIndex = 200

    notifLayout.Parent = NotificationContainer
    notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notifLayout.Padding = UDim.new(0, 8)

    notifPadding.Parent = NotificationContainer
    notifPadding.PaddingRight = UDim.new(0, 4)
    notifPadding.PaddingTop = UDim.new(0, 4)

    local Shadow = Instance.new("ImageLabel")
    Shadow.Name = "Shadow"
    Shadow.Image = "rbxassetid://1316045217"
    Shadow.ImageColor3 = Theme.Shadow
    Shadow.ScaleType = Enum.ScaleType.Slice
    Shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    Shadow.ImageTransparency = 0.5
    Shadow.Parent = ScreenGui
    Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    Shadow.BackgroundTransparency = 1
    Shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    Shadow.Size = UDim2.new(0, 460, 0, 360)
    Shadow.Visible = true
    attachAutoScale(Shadow, 460, 360)

    local shadowPadding = Instance.new("UIPadding")
    shadowPadding.Parent = Shadow
    shadowPadding.PaddingBottom = UDim.new(0, 8)
    shadowPadding.PaddingLeft = UDim.new(0, 8)
    shadowPadding.PaddingRight = UDim.new(0, 8)
    shadowPadding.PaddingTop = UDim.new(0, 8)

    local MainFrame = Instance.new("CanvasGroup")
    local mainCorner = Instance.new("UICorner")
    local mainStroke = Instance.new("UIStroke")

    MainFrame.Name = "MainFrame"
    MainFrame.Parent = Shadow
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.BackgroundColor3 = Theme.Background
    MainFrame.BorderSizePixel = 0
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainFrame.Size = UDim2.new(1, 0, 1, 0)
    MainFrame.ClipsDescendants = true
    MainFrame.GroupTransparency = 1

    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = MainFrame

    mainStroke.Color = Theme.CardBorder
    mainStroke.Thickness = 1.2
    mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainStroke.Parent = MainFrame

    local Topbar = Instance.new("Frame")
    Topbar.Name = "Topbar"
    Topbar.Parent = MainFrame
    Topbar.BackgroundColor3 = Theme.Header
    Topbar.BorderSizePixel = 0
    Topbar.Position = UDim2.new(0, 0, 0, 0)
    Topbar.Size = UDim2.new(1, 0, 0, 46)
    Topbar.ZIndex = 10

    local topbarBorder = Instance.new("Frame")
    topbarBorder.Name = "Border"
    topbarBorder.Parent = Topbar
    topbarBorder.BackgroundColor3 = Theme.CardBorder
    topbarBorder.BorderSizePixel = 0
    topbarBorder.Position = UDim2.new(0, 0, 1, -1)
    topbarBorder.Size = UDim2.new(1, 0, 0, 1)

    makeDraggable(Topbar, Shadow)

    local LogoContainer = Instance.new("Frame")
    local logoLayout = Instance.new("UIListLayout")
    local LogoTitle = Instance.new("TextLabel")
    local LogoSub = Instance.new("TextLabel")
    local TagBadge = Instance.new("Frame")
    local tagCorner = Instance.new("UICorner")
    local tagStroke = Instance.new("UIStroke")
    local TagLabel = Instance.new("TextLabel")

    LogoContainer.Name = "LogoContainer"
    LogoContainer.Parent = Topbar
    LogoContainer.BackgroundTransparency = 1
    LogoContainer.Position = UDim2.new(0, 16, 0, 0)
    LogoContainer.Size = UDim2.new(1, -80, 1, 0)

    logoLayout.Parent = LogoContainer
    logoLayout.FillDirection = Enum.FillDirection.Horizontal
    logoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    logoLayout.SortOrder = Enum.SortOrder.LayoutOrder
    logoLayout.Padding = UDim.new(0, 6)

    LogoTitle.Name = "Title"
    LogoTitle.Parent = LogoContainer
    LogoTitle.BackgroundTransparency = 1
    LogoTitle.Size = UDim2.new(0, 0, 1, 0)
    LogoTitle.AutomaticSize = Enum.AutomaticSize.X
    LogoTitle.Font = Enum.Font.GothamBold
    LogoTitle.Text = tostring(self._title)
    LogoTitle.TextColor3 = Theme.Text
    LogoTitle.TextSize = 16
    LogoTitle.TextXAlignment = Enum.TextXAlignment.Left
    LogoTitle.LayoutOrder = 1

    LogoSub.Name = "SubTitle"
    LogoSub.Parent = LogoContainer
    LogoSub.BackgroundTransparency = 1
    LogoSub.Size = UDim2.new(0, 0, 1, 0)
    LogoSub.AutomaticSize = Enum.AutomaticSize.X
    LogoSub.Font = Enum.Font.GothamBold
    LogoSub.Text = tostring(self._subtitle)
    LogoSub.TextColor3 = Color3.fromRGB(180, 180, 195)
    LogoSub.TextSize = 16
    LogoSub.TextXAlignment = Enum.TextXAlignment.Left
    LogoSub.LayoutOrder = 2

    TagBadge.Name = "TagBadge"
    TagBadge.Parent = LogoContainer
    TagBadge.BackgroundColor3 = Theme.Card
    TagBadge.BorderSizePixel = 0
    TagBadge.Size = UDim2.new(0, 78, 0, 19)
    TagBadge.LayoutOrder = 3

    tagCorner.CornerRadius = UDim.new(0, 4)
    tagCorner.Parent = TagBadge

    tagStroke.Color = Theme.CardBorder
    tagStroke.Thickness = 1
    tagStroke.Parent = TagBadge

    TagLabel.Name = "Label"
    TagLabel.Parent = TagBadge
    TagLabel.BackgroundTransparency = 1
    TagLabel.Size = UDim2.new(1, 0, 1, 0)
    TagLabel.Font = Enum.Font.GothamBold
    TagLabel.Text = tostring(self._tag)
    TagLabel.TextColor3 = Theme.SubText
    TagLabel.TextSize = 8.5
    TagLabel.TextXAlignment = Enum.TextXAlignment.Center

    local WindowControls = Instance.new("Frame")
    local winControlsLayout = Instance.new("UIListLayout")
    local MinButton = Instance.new("ImageButton")
    local CloseButton = Instance.new("ImageButton")

    WindowControls.Name = "Controls"
    WindowControls.Parent = Topbar
    WindowControls.AnchorPoint = Vector2.new(1, 0.5)
    WindowControls.BackgroundTransparency = 1
    WindowControls.Position = UDim2.new(1, -14, 0.5, 0)
    WindowControls.Size = UDim2.new(0, 44, 0, 24)

    winControlsLayout.Parent = WindowControls
    winControlsLayout.FillDirection = Enum.FillDirection.Horizontal
    winControlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    winControlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    winControlsLayout.Padding = UDim.new(0, 12)

    MinButton.Name = "Minimize"
    MinButton.Parent = WindowControls
    MinButton.BackgroundTransparency = 1
    MinButton.Size = UDim2.new(0, 14, 0, 14)
    MinButton.Image = "rbxassetid://10734896206"
    MinButton.ImageColor3 = Theme.SubText

    CloseButton.Name = "Close"
    CloseButton.Parent = WindowControls
    CloseButton.BackgroundTransparency = 1
    CloseButton.Size = UDim2.new(0, 14, 0, 14)
    CloseButton.Image = "rbxassetid://15082305656"
    CloseButton.ImageColor3 = Theme.SubText

    MinButton.MouseEnter:Connect(function()
        tw({ v = MinButton, t = 0.15, g = { ImageColor3 = Theme.Text } }):Play()
    end)
    MinButton.MouseLeave:Connect(function()
        tw({ v = MinButton, t = 0.15, g = { ImageColor3 = Theme.SubText } }):Play()
    end)

    CloseButton.MouseEnter:Connect(function()
        tw({ v = CloseButton, t = 0.15, g = { ImageColor3 = Theme.Error } }):Play()
    end)
    CloseButton.MouseLeave:Connect(function()
        tw({ v = CloseButton, t = 0.15, g = { ImageColor3 = Theme.SubText } }):Play()
    end)

    local ReopenPill = Instance.new("CanvasGroup")
    local reopenCorner = Instance.new("UICorner")
    local reopenStroke = Instance.new("UIStroke")
    local reopenContent = Instance.new("Frame")
    local reopenLayout = Instance.new("UIListLayout")
    local reopenPadding = Instance.new("UIPadding")

    local statusDot = Instance.new("Frame")
    local statusDotCorner = Instance.new("UICorner")
    local reopenPlayerLabel = Instance.new("TextLabel")
    local reopenDiv1 = Instance.new("Frame")
    local reopenStats = Instance.new("TextLabel")
    local reopenDiv2 = Instance.new("Frame")

    local reopenBadge = Instance.new("Frame")
    local reopenBadgeCorner = Instance.new("UICorner")
    local reopenBadgeStroke = Instance.new("UIStroke")
    local reopenBadgeText = Instance.new("TextLabel")
    local reopenClick = Instance.new("TextButton")

    ReopenPill.Name = "ReopenPill"
    ReopenPill.Parent = ScreenGui
    ReopenPill.AnchorPoint = Vector2.new(0.5, 0)
    ReopenPill.Position = UDim2.new(0.5, 0, 0, 14)
    ReopenPill.Size = UDim2.new(0, 270, 0, 28)
    ReopenPill.BackgroundColor3 = Theme.Card
    ReopenPill.BorderSizePixel = 0
    ReopenPill.GroupTransparency = 1
    ReopenPill.Visible = false
    ReopenPill.ZIndex = 150
    ReopenPill.ClipsDescendants = true

    reopenCorner.CornerRadius = UDim.new(0, 8)
    reopenCorner.Parent = ReopenPill

    reopenStroke.Color = Theme.CardBorder
    reopenStroke.Thickness = 1.2
    reopenStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    reopenStroke.Parent = ReopenPill

    reopenContent.Name = "Content"
    reopenContent.Parent = ReopenPill
    reopenContent.BackgroundTransparency = 1
    reopenContent.Size = UDim2.new(1, 0, 1, 0)

    reopenLayout.Parent = reopenContent
    reopenLayout.FillDirection = Enum.FillDirection.Horizontal
    reopenLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    reopenLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    reopenLayout.SortOrder = Enum.SortOrder.LayoutOrder
    reopenLayout.Padding = UDim.new(0, 8)

    reopenPadding.Parent = reopenContent
    reopenPadding.PaddingLeft = UDim.new(0, 10)
    reopenPadding.PaddingRight = UDim.new(0, 10)

    statusDot.Name = "StatusDot"
    statusDot.Parent = reopenContent
    statusDot.BackgroundColor3 = Theme.Success
    statusDot.BorderSizePixel = 0
    statusDot.Size = UDim2.new(0, 6, 0, 6)
    statusDot.LayoutOrder = 1
    statusDotCorner.CornerRadius = UDim.new(1, 0)
    statusDotCorner.Parent = statusDot

    local playerNameStr = (LocalPlayer and (LocalPlayer.DisplayName or LocalPlayer.Name)) or "Player"
    reopenPlayerLabel.Name = "PlayerLabel"
    reopenPlayerLabel.Parent = reopenContent
    reopenPlayerLabel.BackgroundTransparency = 1
    reopenPlayerLabel.Size = UDim2.new(0, 54, 0, 16)
    reopenPlayerLabel.Font = Enum.Font.GothamBold
    reopenPlayerLabel.Text = playerNameStr
    reopenPlayerLabel.TextColor3 = Theme.Text
    reopenPlayerLabel.TextSize = 10.5
    reopenPlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
    reopenPlayerLabel.TextTruncate = Enum.TextTruncate.AtEnd
    reopenPlayerLabel.LayoutOrder = 2

    reopenDiv1.Name = "Div1"
    reopenDiv1.Parent = reopenContent
    reopenDiv1.BackgroundColor3 = Theme.CardBorder
    reopenDiv1.BorderSizePixel = 0
    reopenDiv1.Size = UDim2.new(0, 1, 0, 12)
    reopenDiv1.LayoutOrder = 3

    reopenStats.Name = "Stats"
    reopenStats.Parent = reopenContent
    reopenStats.BackgroundTransparency = 1
    reopenStats.Size = UDim2.new(0, 92, 0, 16)
    reopenStats.Font = Enum.Font.GothamMedium
    reopenStats.RichText = true
    reopenStats.Text = '<font color="rgb(34,197,94)"><b>60</b></font> <font color="rgb(150,150,165)">FPS</font> <font color="rgb(70,70,85)">•</font> <font color="rgb(255,255,255)"><b>0</b></font><font color="rgb(150,150,165)">ms</font>'
    reopenStats.TextSize = 10
    reopenStats.TextXAlignment = Enum.TextXAlignment.Center
    reopenStats.LayoutOrder = 4

    reopenDiv2.Name = "Div2"
    reopenDiv2.Parent = reopenContent
    reopenDiv2.BackgroundColor3 = Theme.CardBorder
    reopenDiv2.BorderSizePixel = 0
    reopenDiv2.Size = UDim2.new(0, 1, 0, 12)
    reopenDiv2.LayoutOrder = 5

    reopenBadge.Name = "KeyBadge"
    reopenBadge.Parent = reopenContent
    reopenBadge.BackgroundColor3 = Theme.InputBackground
    reopenBadge.BorderSizePixel = 0
    reopenBadge.Size = UDim2.new(0, 44, 0, 18)
    reopenBadge.LayoutOrder = 6

    reopenBadgeCorner.CornerRadius = UDim.new(0, 4)
    reopenBadgeCorner.Parent = reopenBadge

    reopenBadgeStroke.Color = Theme.CardBorder
    reopenBadgeStroke.Thickness = 1
    reopenBadgeStroke.Parent = reopenBadge

    reopenBadgeText.Name = "Text"
    reopenBadgeText.Parent = reopenBadge
    reopenBadgeText.BackgroundTransparency = 1
    reopenBadgeText.Size = UDim2.new(1, 0, 1, 0)
    reopenBadgeText.Font = Enum.Font.GothamBold
    reopenBadgeText.Text = "[Key]"
    reopenBadgeText.TextColor3 = Theme.Main
    reopenBadgeText.TextSize = 9.5
    reopenBadgeText.TextXAlignment = Enum.TextXAlignment.Center

    reopenClick.Name = "Click"
    reopenClick.Parent = ReopenPill
    reopenClick.BackgroundTransparency = 1
    reopenClick.Size = UDim2.new(1, 0, 1, 0)
    reopenClick.Text = ""
    reopenClick.ZIndex = 25

    local fpsVal, fpsFrames, fpsLastTime = 60, 0, tick()
    local pingVal = 0

    local statsConn
    statsConn = RunService.RenderStepped:Connect(function()
        fpsFrames = fpsFrames + 1
        local now = tick()
        if now - fpsLastTime >= 0.5 then
            fpsVal = math.round(fpsFrames / (now - fpsLastTime))
            fpsFrames = 0
            fpsLastTime = now
        end
    end)
    ScreenGui.Destroying:Connect(function()
        pcall(function()
            if statsConn and statsConn.Connected then
                statsConn:Disconnect()
            end
        end)
    end)

    task.spawn(function()
        while ScreenGui and ScreenGui.Parent do
            pcall(function()
                local netItem = StatsService and StatsService.Network and StatsService.Network.ServerStatsItem and StatsService.Network.ServerStatsItem["Data Ping"]
                if netItem then pingVal = math.round(netItem:GetValue()) end
            end)
            if reopenStats and reopenStats.Parent then
                local fpsColor = (fpsVal >= 50 and "rgb(34,197,94)") or (fpsVal >= 30 and "rgb(234,179,8)") or "rgb(239,68,68)"
                reopenStats.Text = string.format(
                    '<font color="%s"><b>%d</b></font> <font color="rgb(150,150,165)">FPS</font> <font color="rgb(70,70,85)">•</font> <font color="rgb(255,255,255)"><b>%d</b></font><font color="rgb(150,150,165)">ms</font>',
                    fpsColor, fpsVal, pingVal
                )
            end
            task.wait(0.5)
        end
    end)

    local function setWindowMinimized(minimized)
        if minimized then
            tw({ v = MainFrame, t = 0.16, g = { GroupTransparency = 1 } }):Play()
            task.delay(0.16, function() Shadow.Visible = false end)
            ReopenPill.Visible = true
            tw({ v = ReopenPill, t = 0.22, s = Enum.EasingStyle.Back, d = "Out", g = { GroupTransparency = 0 } }):Play()
        else
            tw({ v = ReopenPill, t = 0.14, g = { GroupTransparency = 1 } }):Play()
            task.delay(0.14, function() ReopenPill.Visible = false end)
            Shadow.Visible = true
            tw({ v = MainFrame, t = 0.18, g = { GroupTransparency = 0 } }):Play()
        end
    end

    do
        local isPillDragging = false
        local pDragStart, pStartPos = nil, nil
        local hasPillMoved = false

        reopenClick.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isPillDragging = true
                hasPillMoved = false
                pDragStart = input.Position
                pStartPos = ReopenPill.Position
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if isPillDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - pDragStart
                if math.abs(delta.X) > 3 or math.abs(delta.Y) > 3 then hasPillMoved = true end
                ReopenPill.Position = UDim2.new(pStartPos.X.Scale, pStartPos.X.Offset + delta.X, pStartPos.Y.Scale, pStartPos.Y.Offset + delta.Y)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isPillDragging = false
            end
        end)

        local function onReopenClick()
            if not hasPillMoved then
                playClickSound()
                setWindowMinimized(false)
            end
        end

        reopenClick.MouseButton1Click:Connect(onReopenClick)
        reopenClick.Activated:Connect(onReopenClick)
    end

    local function onMinimizeClicked()
        playClickSound()
        setWindowMinimized(true)
    end
    MinButton.MouseButton1Click:Connect(onMinimizeClicked)
    MinButton.Activated:Connect(onMinimizeClicked)

    local function onCloseClicked()
        playClickSound()
        local closeTween = tw({ v = MainFrame, t = 0.18, g = { GroupTransparency = 1 } })
        closeTween:Play()
        closeTween.Completed:Connect(function()
            isCancelled = true
            getgenv().UI_CLOSED = true
            pcall(function() ScreenGui:Destroy() end)
        end)
    end
    CloseButton.MouseButton1Click:Connect(onCloseClicked)
    CloseButton.Activated:Connect(onCloseClicked)

    local Body = Instance.new("Frame")
    local bodyLayout = Instance.new("UIListLayout")
    local bodyPadding = Instance.new("UIPadding")

    Body.Name = "Body"
    Body.Parent = MainFrame
    Body.BackgroundTransparency = 1
    Body.BorderSizePixel = 0
    Body.Position = UDim2.new(0, 0, 0, 46)
    Body.Size = UDim2.new(1, 0, 1, -46)

    bodyLayout.Parent = Body
    bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    bodyLayout.Padding = UDim.new(0, 12)

    bodyPadding.Parent = Body
    bodyPadding.PaddingLeft = UDim.new(0, 16)
    bodyPadding.PaddingRight = UDim.new(0, 16)
    bodyPadding.PaddingTop = UDim.new(0, 14)
    bodyPadding.PaddingBottom = UDim.new(0, 14)

    local ProfileCard = Instance.new("Frame")
    local profCorner = Instance.new("UICorner")
    local profStroke = Instance.new("UIStroke")
    local profAvatarCircle = Instance.new("Frame")
    local profAvatarCorner = Instance.new("UICorner")
    local profAvatarStroke = Instance.new("UIStroke")
    local profAvatarImg = Instance.new("ImageLabel")
    local profAvatarImgCorner = Instance.new("UICorner")
    local profOnlineDot = Instance.new("Frame")
    local profOnlineDotCorner = Instance.new("UICorner")

    local profInfo = Instance.new("Frame")
    local profInfoLayout = Instance.new("UIListLayout")
    local profDisplayName = Instance.new("TextLabel")
    local profUsername = Instance.new("TextLabel")

    local execBadge = Instance.new("Frame")
    local execCorner = Instance.new("UICorner")
    local execStroke = Instance.new("UIStroke")
    local execLayout = Instance.new("UIListLayout")
    local execPadding = Instance.new("UIPadding")
    local execIcon = Instance.new("ImageLabel")
    local execLabel = Instance.new("TextLabel")

    ProfileCard.Name = "ProfileCard"
    ProfileCard.Parent = Body
    ProfileCard.BackgroundColor3 = Theme.Card
    ProfileCard.BorderSizePixel = 0
    ProfileCard.Size = UDim2.new(1, 0, 0, 60)
    ProfileCard.LayoutOrder = 1

    profCorner.CornerRadius = UDim.new(0, 8)
    profCorner.Parent = ProfileCard

    profStroke.Color = Theme.CardBorder
    profStroke.Thickness = 1
    profStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    profStroke.Parent = ProfileCard

    profAvatarCircle.Name = "AvatarCircle"
    profAvatarCircle.Parent = ProfileCard
    profAvatarCircle.BackgroundColor3 = Theme.InputBackground
    profAvatarCircle.BorderSizePixel = 0
    profAvatarCircle.Position = UDim2.new(0, 12, 0.5, -20)
    profAvatarCircle.Size = UDim2.new(0, 40, 0, 40)

    profAvatarCorner.CornerRadius = UDim.new(1, 0)
    profAvatarCorner.Parent = profAvatarCircle

    profAvatarStroke.Color = Theme.CardBorder
    profAvatarStroke.Thickness = 1.2
    profAvatarStroke.Parent = profAvatarCircle

    profAvatarImg.Name = "Avatar"
    profAvatarImg.Parent = profAvatarCircle
    profAvatarImg.BackgroundTransparency = 1
    profAvatarImg.Size = UDim2.new(1, 0, 1, 0)
    local userId = LocalPlayer and LocalPlayer.UserId or 1
    profAvatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"

    profAvatarImgCorner.CornerRadius = UDim.new(1, 0)
    profAvatarImgCorner.Parent = profAvatarImg

    profOnlineDot.Name = "OnlineDot"
    profOnlineDot.Parent = profAvatarCircle
    profOnlineDot.AnchorPoint = Vector2.new(1, 1)
    profOnlineDot.BackgroundColor3 = Theme.Success
    profOnlineDot.BorderSizePixel = 0
    profOnlineDot.Position = UDim2.new(1, 1, 1, 1)
    profOnlineDot.Size = UDim2.new(0, 10, 0, 10)
    profOnlineDot.ZIndex = 5

    profOnlineDotCorner.CornerRadius = UDim.new(1, 0)
    profOnlineDotCorner.Parent = profOnlineDot

    profInfo.Name = "Info"
    profInfo.Parent = ProfileCard
    profInfo.BackgroundTransparency = 1
    profInfo.Position = UDim2.new(0, 60, 0.5, -18)
    profInfo.Size = UDim2.new(1, -190, 0, 36)

    profInfoLayout.Parent = profInfo
    profInfoLayout.SortOrder = Enum.SortOrder.LayoutOrder
    profInfoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    profInfoLayout.Padding = UDim.new(0, 2)

    profDisplayName.Name = "DisplayName"
    profDisplayName.Parent = profInfo
    profDisplayName.BackgroundTransparency = 1
    profDisplayName.Size = UDim2.new(1, 0, 0, 16)
    profDisplayName.Font = Enum.Font.GothamBold
    profDisplayName.Text = (LocalPlayer and LocalPlayer.DisplayName) or "Player"
    profDisplayName.TextColor3 = Theme.Text
    profDisplayName.TextSize = 13.5
    profDisplayName.TextXAlignment = Enum.TextXAlignment.Left
    profDisplayName.TextTruncate = Enum.TextTruncate.AtEnd
    profDisplayName.LayoutOrder = 1

    profUsername.Name = "Username"
    profUsername.Parent = profInfo
    profUsername.BackgroundTransparency = 1
    profUsername.Size = UDim2.new(1, 0, 0, 14)
    profUsername.Font = Enum.Font.Gotham
    profUsername.Text = "@" .. ((LocalPlayer and LocalPlayer.Name) or "Player")
    profUsername.TextColor3 = Theme.SubText
    profUsername.TextSize = 10.5
    profUsername.TextXAlignment = Enum.TextXAlignment.Left
    profUsername.TextTruncate = Enum.TextTruncate.AtEnd
    profUsername.LayoutOrder = 2

    execBadge.Name = "ExecutorBadge"
    execBadge.Parent = ProfileCard
    execBadge.AnchorPoint = Vector2.new(1, 0.5)
    execBadge.Position = UDim2.new(1, -12, 0.5, 0)
    execBadge.BackgroundColor3 = Theme.InputBackground
    execBadge.BorderSizePixel = 0
    execBadge.Size = UDim2.new(0, 0, 0, 24)
    execBadge.AutomaticSize = Enum.AutomaticSize.X

    execCorner.CornerRadius = UDim.new(0, 5)
    execCorner.Parent = execBadge

    execStroke.Color = Theme.CardBorder
    execStroke.Thickness = 1
    execStroke.Parent = execBadge

    execLayout.Parent = execBadge
    execLayout.FillDirection = Enum.FillDirection.Horizontal
    execLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    execLayout.SortOrder = Enum.SortOrder.LayoutOrder
    execLayout.Padding = UDim.new(0, 5)

    execPadding.Parent = execBadge
    execPadding.PaddingLeft = UDim.new(0, 8)
    execPadding.PaddingRight = UDim.new(0, 8)

    execIcon.Name = "Icon"
    execIcon.Parent = execBadge
    execIcon.BackgroundTransparency = 1
    execIcon.Size = UDim2.new(0, 12, 0, 12)
    local shieldData = gl("shield")
    execIcon.Image = shieldData.Image
    execIcon.ImageRectSize = shieldData.ImageRectSize
    execIcon.ImageRectOffset = shieldData.ImageRectPosition
    execIcon.ImageColor3 = Theme.SubText
    execIcon.LayoutOrder = 1

    execLabel.Name = "Label"
    execLabel.Parent = execBadge
    execLabel.BackgroundTransparency = 1
    execLabel.Size = UDim2.new(0, 0, 1, 0)
    execLabel.AutomaticSize = Enum.AutomaticSize.X
    execLabel.Font = Enum.Font.GothamMedium
    execLabel.Text = getExecutorName()
    execLabel.TextColor3 = Theme.Text
    execLabel.TextSize = 10.5
    execLabel.TextXAlignment = Enum.TextXAlignment.Center
    execLabel.LayoutOrder = 2

    ProfileCard.MouseEnter:Connect(function()
        tw({ v = ProfileCard, t = 0.15, g = { BackgroundColor3 = Theme.CardHover } }):Play()
        tw({ v = profStroke, t = 0.15, g = { Color = Theme.CardBorder:Lerp(Theme.Main, 0.25) } }):Play()
    end)
    ProfileCard.MouseLeave:Connect(function()
        tw({ v = ProfileCard, t = 0.2, g = { BackgroundColor3 = Theme.Card } }):Play()
        tw({ v = profStroke, t = 0.2, g = { Color = Theme.CardBorder } }):Play()
    end)

    local InputCard = Instance.new("Frame")
    local inputCorner = Instance.new("UICorner")
    local inputStroke = Instance.new("UIStroke")
    local inputCardLayout = Instance.new("UIListLayout")
    local inputCardPadding = Instance.new("UIPadding")

    local inputHeader = Instance.new("Frame")
    local inputHeaderLayout = Instance.new("UIListLayout")
    local inputHeaderTitle = Instance.new("TextLabel")
    local inputHeaderSub = Instance.new("TextLabel")

    InputCard.Name = "InputCard"
    InputCard.Parent = Body
    InputCard.BackgroundColor3 = Theme.Card
    InputCard.BorderSizePixel = 0
    InputCard.Size = UDim2.new(1, 0, 0, 102)
    InputCard.LayoutOrder = 2

    inputCorner.CornerRadius = UDim.new(0, 8)
    inputCorner.Parent = InputCard

    inputStroke.Color = Theme.CardBorder
    inputStroke.Thickness = 1
    inputStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    inputStroke.Parent = InputCard

    inputCardLayout.Parent = InputCard
    inputCardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    inputCardLayout.Padding = UDim.new(0, 8)

    inputCardPadding.Parent = InputCard
    inputCardPadding.PaddingLeft = UDim.new(0, 14)
    inputCardPadding.PaddingRight = UDim.new(0, 14)
    inputCardPadding.PaddingTop = UDim.new(0, 11)
    inputCardPadding.PaddingBottom = UDim.new(0, 11)

    inputHeader.Name = "Header"
    inputHeader.Parent = InputCard
    inputHeader.BackgroundTransparency = 1
    inputHeader.Size = UDim2.new(1, 0, 0, 28)
    inputHeader.LayoutOrder = 1

    inputHeaderLayout.Parent = inputHeader
    inputHeaderLayout.SortOrder = Enum.SortOrder.LayoutOrder
    inputHeaderLayout.Padding = UDim.new(0, 2)

    inputHeaderTitle.Name = "Title"
    inputHeaderTitle.Parent = inputHeader
    inputHeaderTitle.BackgroundTransparency = 1
    inputHeaderTitle.Size = UDim2.new(1, 0, 0, 15)
    inputHeaderTitle.Font = Enum.Font.GothamBold
    inputHeaderTitle.Text = "Authentication Key"
    inputHeaderTitle.TextColor3 = Theme.Text
    inputHeaderTitle.TextSize = 12
    inputHeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
    inputHeaderTitle.LayoutOrder = 1

    inputHeaderSub.Name = "Desc"
    inputHeaderSub.Parent = inputHeader
    inputHeaderSub.BackgroundTransparency = 1
    inputHeaderSub.Size = UDim2.new(1, 0, 0, 13)
    inputHeaderSub.Font = Enum.Font.Gotham
    inputHeaderSub.Text = "Enter your key below to authenticate and continue"
    inputHeaderSub.TextColor3 = Theme.SubText
    inputHeaderSub.TextSize = 10
    inputHeaderSub.TextXAlignment = Enum.TextXAlignment.Left
    inputHeaderSub.LayoutOrder = 2

    local TextBoxFrame = Instance.new("Frame")
    local tbCorner = Instance.new("UICorner")
    local tbStroke = Instance.new("UIStroke")
    local keyIcon = Instance.new("ImageLabel")
    local KeyTextBox = Instance.new("TextBox")
    local ClearBtn = Instance.new("ImageButton")

    TextBoxFrame.Name = "TextBoxFrame"
    TextBoxFrame.Parent = InputCard
    TextBoxFrame.BackgroundColor3 = Theme.InputBackground
    TextBoxFrame.BorderSizePixel = 0
    TextBoxFrame.Size = UDim2.new(1, 0, 0, 38)
    TextBoxFrame.LayoutOrder = 2

    tbCorner.CornerRadius = UDim.new(0, 6)
    tbCorner.Parent = TextBoxFrame

    tbStroke.Color = Theme.InputBorder
    tbStroke.Thickness = 1
    tbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    tbStroke.Parent = TextBoxFrame

    keyIcon.Name = "KeyIcon"
    keyIcon.Parent = TextBoxFrame
    keyIcon.AnchorPoint = Vector2.new(0, 0.5)
    keyIcon.BackgroundTransparency = 1
    keyIcon.Position = UDim2.new(0, 10, 0.5, 0)
    keyIcon.Size = UDim2.new(0, 16, 0, 16)
    local kIconData = gl("key")
    keyIcon.Image = kIconData.Image
    keyIcon.ImageRectSize = kIconData.ImageRectSize
    keyIcon.ImageRectOffset = kIconData.ImageRectPosition
    keyIcon.ImageColor3 = Theme.SubText

    ClearBtn.Name = "Clear"
    ClearBtn.Parent = TextBoxFrame
    ClearBtn.AnchorPoint = Vector2.new(1, 0.5)
    ClearBtn.Position = UDim2.new(1, -10, 0.5, 0)
    ClearBtn.BackgroundTransparency = 1
    ClearBtn.Size = UDim2.new(0, 15, 0, 15)
    ClearBtn.Image = "rbxassetid://15082305656"
    ClearBtn.ImageColor3 = Theme.SubText
    ClearBtn.Visible = false
    ClearBtn.ZIndex = 15

    KeyTextBox.Name = "KeyInput"
    KeyTextBox.Parent = TextBoxFrame
    KeyTextBox.BackgroundTransparency = 1
    KeyTextBox.Position = UDim2.new(0, 34, 0, 0)
    KeyTextBox.Size = UDim2.new(1, -68, 1, 0)
    KeyTextBox.Font = Enum.Font.Gotham
    KeyTextBox.Text = ""
    KeyTextBox.PlaceholderText = "Enter your key..."
    KeyTextBox.PlaceholderColor3 = Theme.Placeholder
    KeyTextBox.TextColor3 = Theme.Text
    KeyTextBox.TextSize = 12
    KeyTextBox.TextXAlignment = Enum.TextXAlignment.Left
    KeyTextBox.ClearTextOnFocus = false

    KeyTextBox:GetPropertyChangedSignal("Text"):Connect(function()
        ClearBtn.Visible = (KeyTextBox.Text ~= "")
    end)

    local function onClearClicked()
        playClickSound()
        KeyTextBox.Text = ""
    end
    ClearBtn.MouseButton1Click:Connect(onClearClicked)
    ClearBtn.Activated:Connect(onClearClicked)

    ClearBtn.MouseEnter:Connect(function()
        tw({ v = ClearBtn, t = 0.15, g = { ImageColor3 = Theme.Text } }):Play()
    end)
    ClearBtn.MouseLeave:Connect(function()
        tw({ v = ClearBtn, t = 0.15, g = { ImageColor3 = Theme.SubText } }):Play()
    end)

    KeyTextBox.Focused:Connect(function()
        tw({ v = tbStroke, t = 0.15, g = { Color = Theme.Main } }):Play()
        tw({ v = keyIcon, t = 0.15, g = { ImageColor3 = Theme.Main } }):Play()
    end)
    KeyTextBox.FocusLost:Connect(function()
        tw({ v = tbStroke, t = 0.15, g = { Color = Theme.InputBorder } }):Play()
        tw({ v = keyIcon, t = 0.15, g = { ImageColor3 = Theme.SubText } }):Play()
    end)

    local savedKey = loadKeyFromFile(self._keyFile)
    if savedKey and savedKey ~= "" then
        KeyTextBox.Text = savedKey
    end

    local VerifyButton = Instance.new("Frame")
    local verifyCorner = Instance.new("UICorner")
    local verifyStroke = Instance.new("UIStroke")
    local verifyContent = Instance.new("Frame")
    local verifyLayout = Instance.new("UIListLayout")
    local verifyIcon = Instance.new("ImageLabel")
    local verifyLabel = Instance.new("TextLabel")
    local verifyClick = Instance.new("TextButton")

    VerifyButton.Name = "VerifyButton"
    VerifyButton.Parent = Body
    VerifyButton.BackgroundColor3 = Theme.Main
    VerifyButton.BorderSizePixel = 0
    VerifyButton.Size = UDim2.new(1, 0, 0, 42)
    VerifyButton.LayoutOrder = 3
    VerifyButton.ClipsDescendants = true

    verifyCorner.CornerRadius = UDim.new(0, 8)
    verifyCorner.Parent = VerifyButton

    verifyStroke.Color = Color3.fromRGB(255, 255, 255)
    verifyStroke.Thickness = 1
    verifyStroke.Parent = VerifyButton

    verifyContent.Name = "Content"
    verifyContent.Parent = VerifyButton
    verifyContent.BackgroundTransparency = 1
    verifyContent.Size = UDim2.new(1, 0, 1, 0)

    verifyLayout.Parent = verifyContent
    verifyLayout.FillDirection = Enum.FillDirection.Horizontal
    verifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    verifyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    verifyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    verifyLayout.Padding = UDim.new(0, 8)

    verifyIcon.Name = "Icon"
    verifyIcon.Parent = verifyContent
    verifyIcon.BackgroundTransparency = 1
    verifyIcon.Size = UDim2.new(0, 16, 0, 16)
    local sIcon = gl("shield-check")
    verifyIcon.Image = sIcon.Image
    verifyIcon.ImageRectSize = sIcon.ImageRectSize
    verifyIcon.ImageRectOffset = sIcon.ImageRectPosition
    verifyIcon.ImageColor3 = Theme.MainDark

    verifyLabel.Name = "Label"
    verifyLabel.Parent = verifyContent
    verifyLabel.BackgroundTransparency = 1
    verifyLabel.Size = UDim2.new(0, 0, 1, 0)
    verifyLabel.AutomaticSize = Enum.AutomaticSize.X
    verifyLabel.Font = Enum.Font.GothamBold
    verifyLabel.Text = "Verify Key"
    verifyLabel.TextColor3 = Theme.MainDark
    verifyLabel.TextSize = 13
    verifyLabel.TextXAlignment = Enum.TextXAlignment.Center

    verifyClick.Name = "Click"
    verifyClick.Parent = VerifyButton
    verifyClick.BackgroundTransparency = 1
    verifyClick.Size = UDim2.new(1, 0, 1, 0)
    verifyClick.Text = ""
    verifyClick.ZIndex = 20

    verifyClick.MouseEnter:Connect(function()
        if not self._isVerifying then
            tw({ v = VerifyButton, t = 0.15, g = { BackgroundColor3 = Theme.MainLight } }):Play()
        end
    end)
    verifyClick.MouseLeave:Connect(function()
        if not self._isVerifying then
            tw({ v = VerifyButton, t = 0.2, g = { BackgroundColor3 = Theme.Main } }):Play()
        end
    end)

    local function shakeCard(target)
        task.spawn(function()
            local originalPos = target.Position
            for i = 1, 4 do
                tw({ v = target, t = 0.04, g = { Position = originalPos + UDim2.new(0, (i % 2 == 0 and 6 or -6), 0, 0) } }):Play()
                task.wait(0.04)
            end
            tw({ v = target, t = 0.05, g = { Position = originalPos } }):Play()
        end)
    end

    local SecondaryRow = Instance.new("Frame")
    local secLayout = Instance.new("UIListLayout")

    SecondaryRow.Name = "SecondaryRow"
    SecondaryRow.Parent = Body
    SecondaryRow.BackgroundTransparency = 1
    SecondaryRow.Size = UDim2.new(1, 0, 0, 38)
    SecondaryRow.LayoutOrder = 4

    secLayout.Parent = SecondaryRow
    secLayout.FillDirection = Enum.FillDirection.Horizontal
    secLayout.SortOrder = Enum.SortOrder.LayoutOrder
    secLayout.Padding = UDim.new(0, 8)

    local function createSecondaryButton(title, iconName, layoutOrder, onClick)
        local btnFrame = Instance.new("Frame")
        local btnCorner = Instance.new("UICorner")
        local btnStroke = Instance.new("UIStroke")
        local content = Instance.new("Frame")
        local cLayout = Instance.new("UIListLayout")
        local icon = Instance.new("ImageLabel")
        local label = Instance.new("TextLabel")
        local clickBtn = Instance.new("TextButton")

        btnFrame.Name = "Btn_" .. title
        btnFrame.Parent = SecondaryRow
        btnFrame.BackgroundColor3 = Theme.Card
        btnFrame.BorderSizePixel = 0
        btnFrame.Size = UDim2.new(0.333, -5, 1, 0)
        btnFrame.LayoutOrder = layoutOrder
        btnFrame.ClipsDescendants = true

        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btnFrame

        btnStroke.Color = Theme.CardBorder
        btnStroke.Thickness = 1
        btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        btnStroke.Parent = btnFrame

        content.Name = "Content"
        content.Parent = btnFrame
        content.BackgroundTransparency = 1
        content.Size = UDim2.new(1, 0, 1, 0)

        cLayout.Parent = content
        cLayout.FillDirection = Enum.FillDirection.Horizontal
        cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        cLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        cLayout.SortOrder = Enum.SortOrder.LayoutOrder
        cLayout.Padding = UDim.new(0, 6)

        icon.Name = "Icon"
        icon.Parent = content
        icon.BackgroundTransparency = 1
        icon.Size = UDim2.new(0, 14, 0, 14)
        local icData = gl(iconName)
        icon.Image = icData.Image
        icon.ImageRectSize = icData.ImageRectSize
        icon.ImageRectOffset = icData.ImageRectPosition
        icon.ImageColor3 = Theme.Text

        label.Name = "Label"
        label.Parent = content
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0, 0, 1, 0)
        label.AutomaticSize = Enum.AutomaticSize.X
        label.Font = Enum.Font.GothamMedium
        label.Text = tostring(title)
        label.TextColor3 = Theme.Text
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Center

        clickBtn.Name = "Click"
        clickBtn.Parent = btnFrame
        clickBtn.BackgroundTransparency = 1
        clickBtn.Size = UDim2.new(1, 0, 1, 0)
        clickBtn.Text = ""
        clickBtn.ZIndex = 15

        clickBtn.MouseEnter:Connect(function()
            tw({ v = btnFrame, t = 0.15, g = { BackgroundColor3 = Theme.CardHover } }):Play()
            tw({ v = btnStroke, t = 0.15, g = { Color = Theme.CardBorder:Lerp(Theme.Main, 0.4) } }):Play()
        end)
        clickBtn.MouseLeave:Connect(function()
            tw({ v = btnFrame, t = 0.2, g = { BackgroundColor3 = Theme.Card } }):Play()
            tw({ v = btnStroke, t = 0.2, g = { Color = Theme.CardBorder } }):Play()
        end)

        local lastClickTime = 0
        local function onBtnClicked()
            local now = tick()
            if now - lastClickTime < 0.25 then return end
            lastClickTime = now
            playClickSound()
            createRipple(btnFrame)
            if onClick then onClick() end
        end

        clickBtn.MouseButton1Click:Connect(onBtnClicked)
        clickBtn.Activated:Connect(onBtnClicked)

        return btnFrame
    end

    createSecondaryButton("Get Key", "key-round", 1, function()
        showNotification({
            Title = "Retrieving Link...",
            Desc = "Connecting to Jnkie service...",
            Time = 2,
            Type = "normal"
        })

        task.spawn(function()
            Jnkie:Init(self._service, self._identifier, self._provider)
            local keyLink = Jnkie:GetKeyLink()
            if keyLink and keyLink ~= "" then
                setClip(keyLink)
                showNotification({
                    Title = "Key Link Copied",
                    Desc = "Checkpoint URL copied to clipboard! Complete it to get your key.",
                    Time = 4,
                    Type = "success"
                })
            else
                showNotification({
                    Title = "Failed to Get Link",
                    Desc = "Could not fetch key link from Jnkie. Please check connection.",
                    Time = 3.5,
                    Type = "error"
                })
            end
        end)
    end)

    createSecondaryButton("Buy Key", "shopping-cart", 2, function()
        local buyUrl = self._buyLink or self._discordLink
        setClip(buyUrl)
        showNotification({
            Title = "Store Link Copied",
            Desc = "Premium purchase link copied to clipboard!",
            Time = 3.5,
            Type = "success"
        })
    end)

    createSecondaryButton("Discord", "discord", 3, function()
        setClip(self._discordLink)
        showNotification({
            Title = "Discord Copied",
            Desc = "Discord invite copied to clipboard! Join our community for updates.",
            Time = 3.5,
            Type = "normal"
        })
    end)

    local function performVerification()
        if self._isVerifying then return end
        local inputKey = KeyTextBox.Text:gsub("^%s*(.-)%s*$", "%1")

        if inputKey == "" then
            showNotification({
                Title = "Missing Key",
                Desc = "Please enter your key to continue.",
                Time = 2.5,
                Type = "warning"
            })
            shakeCard(InputCard)
            return
        end

        self._isVerifying = true
        verifyLabel.Text = "Verifying..."
        tw({ v = VerifyButton, t = 0.15, g = { BackgroundColor3 = Theme.MainDark } }):Play()
        tw({ v = verifyStroke, t = 0.15, g = { Color = Theme.Main } }):Play()
        tw({ v = verifyLabel, t = 0.15, g = { TextColor3 = Theme.Main } }):Play()
        tw({ v = verifyIcon, t = 0.15, g = { ImageColor3 = Theme.Main } }):Play()

        task.spawn(function()
            Jnkie:Init(self._service, self._identifier, self._provider)
            local isValid, message = Jnkie:CheckKey(inputKey)

            if isValid then
                if message == "KEYLESS" then
                    getgenv().SCRIPT_KEY = "KEYLESS"
                else
                    getgenv().SCRIPT_KEY = inputKey
                end

                if self._saveKey then
                    saveKeyToFile(self._keyFile, inputKey)
                end

                verifyLabel.Text = "Verified!"
                tw({ v = VerifyButton, t = 0.2, g = { BackgroundColor3 = Theme.Success } }):Play()
                tw({ v = verifyStroke, t = 0.2, g = { Color = Theme.Success } }):Play()
                tw({ v = verifyLabel, t = 0.2, g = { TextColor3 = Theme.MainDark } }):Play()
                tw({ v = verifyIcon, t = 0.2, g = { ImageColor3 = Theme.MainDark } }):Play()

                showNotification({
                    Title = "Access Granted",
                    Desc = "Key authenticated successfully! Welcome to " .. tostring(self._title) .. ".",
                    Time = 3,
                    Type = "success"
                })

                task.wait(0.6)
                local fadeOut = tw({ v = MainFrame, t = 0.25, s = Enum.EasingStyle.Quad, d = "In", g = { GroupTransparency = 1 } })
                fadeOut:Play()
                fadeOut.Completed:Connect(function()
                    pcall(function() ScreenGui:Destroy() end)
                    if self._callback and type(self._callback) == "function" then
                        task.spawn(self._callback, inputKey)
                    end
                    isKeyVerified = true
                end)
                task.delay(0.8, function()
                    isKeyVerified = true
                end)
            else
                self._isVerifying = false
                verifyLabel.Text = "Verify Key"
                tw({ v = VerifyButton, t = 0.2, g = { BackgroundColor3 = Theme.Main } }):Play()
                tw({ v = verifyStroke, t = 0.2, g = { Color = Theme.Main } }):Play()
                tw({ v = verifyLabel, t = 0.2, g = { TextColor3 = Theme.MainDark } }):Play()
                tw({ v = verifyIcon, t = 0.2, g = { ImageColor3 = Theme.MainDark } }):Play()

                tw({ v = inputStroke, t = 0.1, g = { Color = Theme.Error } }):Play()
                shakeCard(InputCard)
                task.delay(0.6, function()
                    tw({ v = inputStroke, t = 0.3, g = { Color = Theme.CardBorder } }):Play()
                end)

                showNotification({
                    Title = "Authentication Failed",
                    Desc = tostring(message or "The key entered is invalid or expired."),
                    Time = 3.5,
                    Type = "error"
                })
            end
        end)
    end

    local lastVerifyClick = 0
    local function onVerifyTriggered()
        local now = tick()
        if now - lastVerifyClick < 0.25 then return end
        lastVerifyClick = now
        playClickSound()
        createRipple(VerifyButton)
        performVerification()
    end

    verifyClick.MouseButton1Click:Connect(onVerifyTriggered)
    verifyClick.Activated:Connect(onVerifyTriggered)

    KeyTextBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            performVerification()
        end
    end)

    local savedKey = loadKeyFromFile(self._keyFile)
    if savedKey and savedKey ~= "" then
        task.spawn(function()
            task.wait(0.3)
            if not isKeyVerified and not isCancelled then
                performVerification()
            end
        end)
    end

    local targetSize = Shadow.Size
    Shadow.Size = targetSize - UDim2.fromOffset(10, 10)
    MainFrame.GroupTransparency = 1
    tw({
        v = Shadow,
        t = 0.24,
        s = Enum.EasingStyle.Quad,
        d = "Out",
        g = { Size = targetSize }
    }):Play()
    tw({
        v = MainFrame,
        t = 0.22,
        s = Enum.EasingStyle.Quad,
        d = "Out",
        g = { GroupTransparency = 0 }
    }):Play()

    local controller = {
        ScreenGui = ScreenGui,
        Notify = showNotification,
        Verify = performVerification,
        Close = function()
            isCancelled = true
            getgenv().UI_CLOSED = true
            pcall(function() ScreenGui:Destroy() end)
        end
    }

    local shouldWait = (config.WaitForKey ~= false)
    if shouldWait then
        while not isKeyVerified and not isCancelled do
            if not ScreenGui or not ScreenGui.Parent then
                isCancelled = true
                break
            end
            task.wait(0.1)
        end

        if isCancelled then
            pcall(function() ScreenGui:Destroy() end)
            coroutine.yield()
            return controller
        end
    end

    return controller
end

local defaultInstance = KeySystem:Init({
    Title = "Aether",
    SubTitle = "Studios",
    Tag = "KEY SYSTEM",
    Service = "Aether Studios",
    Identifier = "1001263",
    Provider = "Free Key",
    BuyLink = "https://discord.gg/getaether",
    DiscordLink = "https://discord.gg/getaether",
    SaveKey = true,
    WaitForKey = true,
    Callback = function(key)
        print("Authenticated, enjoy the script!")
        getgenv().SCRIPT_KEY = key
    end
})
