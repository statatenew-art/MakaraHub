local genv = (typeof(getgenv) == "function" and getgenv()) or _G
local Session = genv.MakaraSession
if type(Session) ~= "table" then
    Session = genv.MakaraRuntime and genv.MakaraRuntime.new()
    if not Session then
        Session = { task = task }
        function Session:Track(x) return x end
        function Session:Service(n) return game:GetService(n) end
    end
    genv.MakaraSession = Session
end
local task = Session.task

local Library = Library or {}
local SaveTheme = SaveTheme or {}

local function exportGlobals(lib)
    if typeof(getgenv) == "function" then
        local g = getgenv()
        g.Library = lib
        g.MakaraHub = lib
        g.MakaraUI = lib
        g.MakaraLibrary = lib
        g.SaveTheme = SaveTheme
    end
    if typeof(_G) == "table" then
        _G.Library = lib
        _G.MakaraHub = lib
        _G.MakaraUI = lib
        _G.MakaraLibrary = lib
        _G.SaveTheme = SaveTheme
    end
    if typeof(shared) == "table" then
        shared.Library = lib
        shared.MakaraHub = lib
        shared.MakaraUI = lib
        shared.MakaraLibrary = lib
        shared.SaveTheme = SaveTheme
    end
    Library = lib
    MakaraHub = lib
    MakaraUI = lib
    MakaraLibrary = lib
end
exportGlobals(Library)

local themes = {
    index = {'Default', 'Christmas', 'Halloween'},
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
                ['True'] = { ['Toggle Background'] = Color3.fromRGB(255, 255, 255), ['Toggle Value'] = Color3.fromRGB(14, 14, 17) },
                ['False'] = { ['Toggle Background'] = Color3.fromRGB(36, 36, 46), ['Toggle Value'] = Color3.fromRGB(150, 150, 160) }
            },
            ['Label'] = { ['Background'] = Color3.fromRGB(19, 19, 23) },
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

local function getGuiParent()
    local success, _ = pcall(function() return CoreGui:GetChildren() end)
    if success then return CoreGui end
    return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or game:GetService("StarterGui")
end

local parentGui = getGuiParent()
pcall(function()
    for _, name in ipairs({"MakaraHub", "Aether"}) do
        local ex = parentGui:FindFirstChild(name)
        if ex then ex:Destroy() end
    end
end)

local ScreenGui = Instance.new("ScreenGui")
Session:Track(ScreenGui)
ScreenGui.Name = "MakaraHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = parentGui

local FileSystem = {
    HasFS = (type(writefile) == "function" and type(readfile) == "function"),
    MemStore = { Configs = {}, Themes = {}, Wallpapers = {}, Autoload = "", WindowSize = nil }
}

function FileSystem:Init()
    if not self.HasFS then return end
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            if not isfolder("MakaraHub") then makefolder("MakaraHub") end
            if not isfolder("MakaraHub/Configs") then makefolder("MakaraHub/Configs") end
            if not isfolder("MakaraHub/Themes") then makefolder("MakaraHub/Themes") end
        end
    end)
end

function FileSystem:SaveConfig(name, data)
    local encoded = HttpService:JSONEncode(data)
    if self.HasFS then
        pcall(function()
            self:Init()
            writefile("MakaraHub/Configs/" .. name .. ".json", encoded)
        end)
    else
        self.MemStore.Configs[name] = encoded
    end
end

function FileSystem:LoadConfig(name)
    local content = nil
    if self.HasFS then
        pcall(function()
            if isfile("MakaraHub/Configs/" .. name .. ".json") then
                content = readfile("MakaraHub/Configs/" .. name .. ".json")
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

FileSystem:Init()

local currentWindowTheme = {
    name = "Default",
    colors = deepCopy(themes.Default),
    cards = {},
    sections = {},
    controls = {},
    tabs = {},
    subTabs = {},
}

local function gl(i)
    local FallbackAssetIcons = {
        ["house"] = "rbxassetid://10723407389",
        ["code"] = "rbxassetid://10709790644",
        ["gamepad-2"] = "rbxassetid://10709798000",
        ["settings"] = "rbxassetid://10734950309",
        ["user"] = "rbxassetid://10747373176",
        ["shield"] = "rbxassetid://10734952480",
        ["check"] = "rbxassetid://10709790202",
        ["chevron-right"] = "rbxassetid://10709791437",
    }
    local key = string.lower(tostring(i))
    if FallbackAssetIcons[key] then
        return { Image = FallbackAssetIcons[key], ImageRectSize = Vector2.new(0,0), ImageRectPosition = Vector2.new(0,0) }
    end
    return { Image = "rbxassetid://10723407389", ImageRectSize = Vector2.new(0,0), ImageRectPosition = Vector2.new(0,0) }
end

local function tw(info)
    return Tw:Create(info.v, TweenInfo.new(info.t, info.s or Enum.EasingStyle.Quad, Enum.EasingDirection[info.d or "Out"]), info.g)
end

local function click(p)
    local Click = Instance.new("TextButton")
    Click.Name = "Click"
    Click.Parent = p
    Click.BackgroundTransparency = 1
    Click.BorderSizePixel = 0
    Click.Size = UDim2.new(1, 0, 1, 0)
    Click.Text = ""
    Click.ZIndex = 5
    return Click
end

local function background(pl, t, d, i, ty)
    local curColors = currentWindowTheme.colors or themes.Default
    local Background = Instance.new("Frame")
    local UICorner = Instance.new("UICorner")
    local UIStroke = Instance.new("UIStroke")
    local T_1 = Instance.new("Frame")
    local UIListLayout = Instance.new("UIListLayout")
    local UIPadding = Instance.new("UIPadding")
    local TitleLabel = Instance.new("TextLabel")
    local DescLabel = Instance.new("TextLabel")

    Background.Name = "Background"
    Background.Parent = pl
    Background.BackgroundColor3 = curColors['Card']
    Background.BorderSizePixel = 0
    Background.Size = UDim2.new(1, 0, 0, (ty == "Label" or not (d and d ~= "")) and 48 or 54)
    Background.ClipsDescendants = true

    UICorner.CornerRadius = UDim.new(0, 6)
    UICorner.Parent = Background

    UIStroke.Color = curColors['CardBorder']
    UIStroke.Thickness = 1
    UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    UIStroke.Parent = Background

    T_1.Name = "T"
    T_1.Parent = Background
    T_1.AnchorPoint = Vector2.new(0, 0.5)
    T_1.BackgroundTransparency = 1
    T_1.Position = UDim2.new(0, 0, 0.5, 0)
    T_1.Size = UDim2.new(1, 0, 1, 0)

    UIListLayout.Parent = T_1
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    UIListLayout.Padding = UDim.new(0, 4)

    UIPadding.Parent = T_1
    UIPadding.PaddingLeft = UDim.new(0, 12)
    UIPadding.PaddingRight = UDim.new(0, 80)

    TitleLabel.Name = 'Title'
    TitleLabel.Parent = T_1
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Size = UDim2.new(1, 0, 0, 20)
    TitleLabel.Font = Enum.Font.BuilderSansBold
    TitleLabel.Text = tostring(t)
    TitleLabel.TextColor3 = curColors['Text & Icon']
    TitleLabel.TextSize = 15.5
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

    DescLabel.Name = 'Desc'
    DescLabel.Parent = T_1
    DescLabel.BackgroundTransparency = 1
    DescLabel.LayoutOrder = 1
    DescLabel.Font = Enum.Font.BuilderSansMedium
    DescLabel.Text = tostring(d or "")
    DescLabel.TextColor3 = curColors['SubText']
    DescLabel.TextSize = 13
    DescLabel.TextXAlignment = Enum.TextXAlignment.Left
    DescLabel.Visible = (d and d ~= "")

    local f = {}
    function f:SetTitle(vs) TitleLabel.Text = tostring(vs) end
    function f:SetDesc(vs) 
        DescLabel.Text = tostring(vs)
        DescLabel.Visible = (vs and vs ~= "")
    end
    function f:SetTextTransparencyTitle(vs)
        tw({v = TitleLabel, t = 0.15, g = {TextTransparency = vs}}):Play()
    end
    function f:SetSizeT(vs)
        UIPadding.PaddingRight = UDim.new(0, vs)
    end
    return Background, f
end

function Library:Window(p)
    p = p or {}
    local Title = p.Title or 'MakaraHub'
    local Desc = p.Desc or 'V1.0'
    local defaultSize = UDim2.new(0, 780, 0, 450)
    local curColors = currentWindowTheme.colors

    local Shadow_1 = Instance.new("Frame")
    local Background_1 = Instance.new("Frame")
    local UICorner_1 = Instance.new("UICorner")
    local UIStroke_Win = Instance.new("UIStroke")

    Shadow_1.Name = "WindowRoot"
    Shadow_1.Parent = ScreenGui
    Shadow_1.AnchorPoint = Vector2.new(0.5, 0.5)
    Shadow_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    Shadow_1.Size = defaultSize
    Shadow_1.BackgroundTransparency = 1

    Background_1.Name = "Background"
    Background_1.Parent = Shadow_1
    Background_1.BackgroundColor3 = curColors['Background']
    Background_1.BorderSizePixel = 0
    Background_1.Size = UDim2.new(1, 0, 1, 0)
    Background_1.ClipsDescendants = true

    UICorner_1.CornerRadius = UDim.new(0, 10)
    UICorner_1.Parent = Background_1

    UIStroke_Win.Color = curColors['CardBorder']
    UIStroke_Win.Thickness = 1.2
    UIStroke_Win.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    UIStroke_Win.Parent = Background_1

    local Sidebar = Instance.new("Frame")
    local SidebarCorner = Instance.new("UICorner")
    Sidebar.Name = "Sidebar"
    Sidebar.Parent = Background_1
    Sidebar.BackgroundColor3 = curColors['Sidebar']
    Sidebar.BorderSizePixel = 0
    Sidebar.Size = UDim2.new(0, 165, 1, 0)
    Sidebar.ZIndex = 5

    SidebarCorner.CornerRadius = UDim.new(0, 10)
    SidebarCorner.Parent = Sidebar

    local LogoTitle = Instance.new("TextLabel")
    LogoTitle.Name = "LogoTitle"
    LogoTitle.Parent = Sidebar
    LogoTitle.BackgroundTransparency = 1
    LogoTitle.Position = UDim2.new(0, 16, 0, 12)
    LogoTitle.Size = UDim2.new(1, -24, 0, 24)
    LogoTitle.Font = Enum.Font.BuilderSansBold
    LogoTitle.Text = tostring(Title) .. " <font color=\"rgb(200,200,200)\">" .. tostring(Desc) .. "</font>"
    LogoTitle.RichText = true
    LogoTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    LogoTitle.TextSize = 18
    LogoTitle.TextXAlignment = Enum.TextXAlignment.Left

    local TabList = Instance.new("ScrollingFrame")
    local TabListLayout = Instance.new("UIListLayout")
    TabList.Name = "TabList"
    TabList.Parent = Sidebar
    TabList.BackgroundTransparency = 1
    TabList.BorderSizePixel = 0
    TabList.Position = UDim2.new(0, 0, 0, 48)
    TabList.Size = UDim2.new(1, 0, 1, -56)
    TabList.ScrollBarThickness = 0

    TabListLayout.Parent = TabList
    TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    TabListLayout.Padding = UDim.new(0, 5)

    local PageContainer = Instance.new("Frame")
    PageContainer.Name = "PageContainer"
    PageContainer.Parent = Background_1
    PageContainer.BackgroundTransparency = 1
    PageContainer.Position = UDim2.new(0, 165, 0, 12)
    PageContainer.Size = UDim2.new(1, -165, 1, -12)

    local Tabs = { List = {} }

    function Tabs:Tab(options)
        local TabTitle = options.Title or 'Sekme'
        local Icon = options.Icon or 'house'

        local TabBtn = Instance.new("Frame")
        local TabCorner = Instance.new("UICorner")
        local TabTitleLabel = Instance.new("TextLabel")
        local ClickTab = click(TabBtn)

        TabBtn.Name = "Tab_" .. TabTitle
        TabBtn.Parent = TabList
        TabBtn.BackgroundColor3 = curColors['MainDark']
        TabBtn.BackgroundTransparency = 1
        TabBtn.Size = UDim2.new(1, -16, 0, 36)
        TabBtn.Position = UDim2.new(0, 8, 0, 0)

        TabCorner.CornerRadius = UDim.new(0, 6)
        TabCorner.Parent = TabBtn

        TabTitleLabel.Parent = TabBtn
        TabTitleLabel.BackgroundTransparency = 1
        TabTitleLabel.Position = UDim2.new(0, 12, 0, 0)
        TabTitleLabel.Size = UDim2.new(1, -12, 1, 0)
        TabTitleLabel.Font = Enum.Font.BuilderSansBold
        TabTitleLabel.Text = TabTitle
        TabTitleLabel.TextColor3 = curColors['SubText']
        TabTitleLabel.TextSize = 14
        TabTitleLabel.TextXAlignment = Enum.TextXAlignment.Left

        local PageScroll = Instance.new("ScrollingFrame")
        local PageLayout = Instance.new("UIListLayout")
        local PagePad = Instance.new("UIPadding")

        PageScroll.Name = "Page_" .. TabTitle
        PageScroll.Parent = PageContainer
        PageScroll.BackgroundTransparency = 1
        PageScroll.BorderSizePixel = 0
        PageScroll.Size = UDim2.new(1, 0, 1, 0)
        PageScroll.ScrollBarThickness = 3
        PageScroll.Visible = false

        PageLayout.Parent = PageScroll
        PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        PageLayout.Padding = UDim.new(0, 8)

        PagePad.Parent = PageScroll
        PagePad.PaddingLeft = UDim.new(0, 12)
        PagePad.PaddingRight = UDim.new(0, 12)
        PagePad.PaddingTop = UDim.new(0, 4)

        local function selectTab()
            for _, item in ipairs(Tabs.List) do
                item.Page.Visible = false
                item.Btn.BackgroundTransparency = 1
                item.Label.TextColor3 = curColors['SubText']
            end
            PageScroll.Visible = true
            TabBtn.BackgroundTransparency = 0
            TabTitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end

        ClickTab.MouseButton1Click:Connect(selectTab)
        table.insert(Tabs.List, { Page = PageScroll, Btn = TabBtn, Label = TabTitleLabel })

        if #Tabs.List == 1 then
            task.defer(selectTab)
        end

        local Builder = {}

        function Builder:Section(secOptions)
            local SecTitle = (type(secOptions) == "table" and secOptions.Title) or tostring(secOptions)
            local SecFrame = Instance.new("Frame")
            local SecCorner = Instance.new("UICorner")
            local SecLayout = Instance.new("UIListLayout")
            local SecPad = Instance.new("UIPadding")
            local SecLabel = Instance.new("TextLabel")

            SecFrame.Name = "Section_" .. SecTitle
            SecFrame.Parent = PageScroll
            SecFrame.BackgroundColor3 = curColors['Background']:Lerp(curColors['Card'], 0.35)
            SecFrame.Size = UDim2.new(1, 0, 0, 32)
            SecFrame.AutomaticSize = Enum.AutomaticSize.Y

            SecCorner.CornerRadius = UDim.new(0, 8)
            SecCorner.Parent = SecFrame

            SecLayout.Parent = SecFrame
            SecLayout.SortOrder = Enum.SortOrder.LayoutOrder
            SecLayout.Padding = UDim.new(0, 6)

            SecPad.Parent = SecFrame
            SecPad.PaddingLeft = UDim.new(0, 8)
            SecPad.PaddingRight = UDim.new(0, 8)
            SecPad.PaddingTop = UDim.new(0, 8)
            SecPad.PaddingBottom = UDim.new(0, 8)

            SecLabel.Name = "Header"
            SecLabel.Parent = SecFrame
            SecLabel.BackgroundTransparency = 1
            SecLabel.Size = UDim2.new(1, 0, 0, 18)
            SecLabel.Font = Enum.Font.BuilderSansBold
            SecLabel.Text = SecTitle:upper()
            SecLabel.TextColor3 = curColors['SubText']
            SecLabel.TextSize = 12
            SecLabel.TextXAlignment = Enum.TextXAlignment.Left

            local SecBuilder = {}

            function SecBuilder:Button(btnOpt)
                local BTitle = btnOpt.Title or "Button"
                local BDesc = btnOpt.Desc or ""
                local BCallback = btnOpt.Callback or function() end
                local BtnBg, Config = background(SecFrame, BTitle, BDesc, nil, 'Button')
                Config:SetSizeT(42)
                local Click = click(BtnBg)
                Click.MouseButton1Click:Connect(function() pcall(BCallback) end)
                return { SetTitle = Config.SetTitle, SetDesc = Config.SetDesc }
            end

            function SecBuilder:Toggle(togOpt)
                local TTitle = togOpt.Title or "Toggle"
                local TDesc = togOpt.Desc or ""
                local TVal = togOpt.Value or false
                local TCallback = togOpt.Callback or function() end
                local TogBg, Config = background(SecFrame, TTitle, TDesc, nil, 'Toggle')
                Config:SetSizeT(50)

                local Pill = Instance.new("Frame")
                local PillCorner = Instance.new("UICorner")
                local Knob = Instance.new("Frame")
                local KnobCorner = Instance.new("UICorner")

                Pill.Parent = TogBg
                Pill.AnchorPoint = Vector2.new(1, 0.5)
                Pill.Position = UDim2.new(1, -12, 0.5, 0)
                Pill.Size = UDim2.new(0, 38, 0, 20)
                Pill.BackgroundColor3 = TVal and curColors['Main'] or Color3.fromRGB(36, 36, 46)

                PillCorner.CornerRadius = UDim.new(1, 0)
                PillCorner.Parent = Pill

                Knob.Parent = Pill
                Knob.AnchorPoint = Vector2.new(0, 0.5)
                Knob.Size = UDim2.new(0, 14, 0, 14)
                Knob.Position = TVal and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
                Knob.BackgroundColor3 = TVal and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(160, 160, 170)

                KnobCorner.CornerRadius = UDim.new(1, 0)
                KnobCorner.Parent = Knob

                local Click = click(TogBg)
                local function setState(st)
                    TVal = st
                    tw({v = Pill, t = 0.15, g = {BackgroundColor3 = TVal and curColors['Main'] or Color3.fromRGB(36, 36, 46)}}):Play()
                    tw({v = Knob, t = 0.15, g = {
                        Position = TVal and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                        BackgroundColor3 = TVal and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(160, 160, 170)
                    }}):Play()
                    pcall(TCallback, TVal)
                end

                Click.MouseButton1Click:Connect(function() setState(not TVal) end)
                return { SetValue = setState, GetValue = function() return TVal end }
            end

            function SecBuilder:Slider(sldOpt)
                local STitle = sldOpt.Title or "Slider"
                local Min = sldOpt.Min or 0
                local Max = sldOpt.Max or 100
                local Val = sldOpt.Value or Min
                local SCallback = sldOpt.Callback or function() end

                local SldBg, Config = background(SecFrame, STitle, "", nil, 'Slider')
                Config:SetSizeT(170)

                local Track = Instance.new("Frame")
                local Fill = Instance.new("Frame")
                local Box = Instance.new("TextBox")

                Track.Parent = SldBg
                Track.AnchorPoint = Vector2.new(1, 0.5)
                Track.Position = UDim2.new(1, -55, 0.5, 0)
                Track.Size = UDim2.new(0, 100, 0, 4)
                Track.BackgroundColor3 = Color3.fromRGB(50, 50, 60)

                Fill.Parent = Track
                Fill.Size = UDim2.new((Val - Min) / (Max - Min), 0, 1, 0)
                Fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

                Box.Parent = SldBg
                Box.AnchorPoint = Vector2.new(1, 0.5)
                Box.Position = UDim2.new(1, -10, 0.5, 0)
                Box.Size = UDim2.new(0, 38, 0, 20)
                Box.Text = tostring(Val)
                Box.TextColor3 = Color3.fromRGB(255, 255, 255)
                Box.BackgroundColor3 = Color3.fromRGB(25, 25, 30)

                local function updateVal(v)
                    v = math.clamp(v, Min, Max)
                    Val = v
                    Fill.Size = UDim2.new((Val - Min) / (Max - Min), 0, 1, 0)
                    Box.Text = tostring(v)
                    pcall(SCallback, Val)
                end

                Box.FocusLost:Connect(function()
                    local n = tonumber(Box.Text) or Val
                    updateVal(n)
                end)

                return { SetValue = updateVal, GetValue = function() return Val end }
            end

            return SecBuilder
        end

        return Builder
    end

    function Tabs:Notify(notifOpt)
        local nTitle = notifOpt.Title or "MakaraHub"
        local nDesc = notifOpt.Desc or ""
        local nTime = notifOpt.Time or 3

        local NotifCard = Instance.new("Frame")
        local Corner = Instance.new("UICorner")
        local LblTitle = Instance.new("TextLabel")
        local LblDesc = Instance.new("TextLabel")

        NotifCard.Parent = ScreenGui
        NotifCard.AnchorPoint = Vector2.new(1, 1)
        NotifCard.Position = UDim2.new(1, -20, 1, -20)
        NotifCard.Size = UDim2.new(0, 240, 0, 50)
        NotifCard.BackgroundColor3 = Color3.fromRGB(20, 20, 25)

        Corner.CornerRadius = UDim.new(0, 6)
        Corner.Parent = NotifCard

        LblTitle.Parent = NotifCard
        LblTitle.Position = UDim2.new(0, 10, 0, 6)
        LblTitle.Size = UDim2.new(1, -20, 0, 18)
        LblTitle.Font = Enum.Font.BuilderSansBold
        LblTitle.Text = nTitle
        LblTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        LblTitle.TextXAlignment = Enum.TextXAlignment.Left

        LblDesc.Parent = NotifCard
        LblDesc.Position = UDim2.new(0, 10, 0, 24)
        LblDesc.Size = UDim2.new(1, -20, 0, 18)
        LblDesc.Font = Enum.Font.BuilderSansMedium
        LblDesc.Text = nDesc
        LblDesc.TextColor3 = Color3.fromRGB(160, 160, 170)
        LblDesc.TextXAlignment = Enum.TextXAlignment.Left

        task.delay(nTime, function() NotifCard:Destroy() end)
    end

    return Tabs
end

return Library
