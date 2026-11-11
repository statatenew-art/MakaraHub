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

local currentWindowTheme = {
    name = "Default",
    colors = deepCopy(themes.Default),
    cards = {},
    sections = {},
    controls = {},
    tabs = {},
    subTabs = {},
}

-- Dış link yerine doğrudan Roblox Asset ID'leri (Hata vermez)
local FallbackAssetIcons = {
    ["house"] = "rbxassetid://10723407389",
    ["code"] = "rbxassetid://10709790644",
    ["gamepad-2"] = "rbxassetid://10709798000",
    ["settings"] = "rbxassetid://10734950309",
    ["user"] = "rbxassetid://10747373176",
    ["shield"] = "rbxassetid://10734952480",
    ["check"] = "rbxassetid://10709790202",
    ["chevron-right"] = "rbxassetid://10709791437",
    ["zap"] = "rbxassetid://10709819266"
}

local function gl(i)
    local key = string.lower(tostring(i))
    if FallbackAssetIcons[key] then
        return { Image = FallbackAssetIcons[key], ImageRectSize = Vector2.new(0,0), ImageRectPosition = Vector2.new(0,0) }
    end
    return { Image = "rbxassetid://10723407389", ImageRectSize = Vector2.new(0,0), ImageRectPosition = Vector2.new(0,0) }
end

local function tw(info)
    return Tw:Create(info.v, TweenInfo.new(info.t, info.s or Enum.EasingStyle.Quad, Enum.EasingDirection[info.d or "Out"]), info.g)
end

local function lak(t, o)
    local a, b, c, d
    local function u(i)
        local dt = i.Position - c
        tw({v = o, t = 0.04, s = Enum.EasingStyle.Linear, d = "InOut", g = {Position = UDim2.new(d.X.Scale, math.round(d.X.Offset + dt.X), d.Y.Scale, math.round(d.Y.Offset + dt.Y))}}):Play()
    end
    t.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            a = true; c = i.Position; d = o.Position
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
    local Desc = p.Desc or 'TDS Edition'
    local defaultSize = UDim2.new(0, 680, 0, 390)
    local curColors = currentWindowTheme.colors

    local Shadow_1 = Instance.new("Frame")
    local Background_1 = Instance.new("Frame")
    local UICorner_1 = Instance.new("UICorner")
    local UIStroke_Win = Instance.new("UIStroke")

    Shadow_1.Name = "Shadow"
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

    local SidebarHeader = Instance.new("Frame")
    SidebarHeader.Name = "SidebarHeader"
    SidebarHeader.Parent = Sidebar
    SidebarHeader.BackgroundTransparency = 1
    SidebarHeader.Size = UDim2.new(1, 0, 0, 48)
    SidebarHeader.ZIndex = 50
    lak(SidebarHeader, Shadow_1)

    local LogoTitle = Instance.new("TextLabel")
    LogoTitle.Name = "LogoTitle"
    LogoTitle.Parent = SidebarHeader
    LogoTitle.BackgroundTransparency = 1
    LogoTitle.Position = UDim2.new(0, 16, 0.5, -12)
    LogoTitle.Size = UDim2.new(1, -24, 0, 24)
    LogoTitle.Font = Enum.Font.BuilderSansBold
    LogoTitle.Text = tostring(Title) .. " <font color=\"rgb(255,255,255)\">" .. tostring(Desc) .. "</font>"
    LogoTitle.RichText = true
    LogoTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    LogoTitle.TextSize = 17
    LogoTitle.TextXAlignment = Enum.TextXAlignment.Left

    local TabListFrame = Instance.new("ScrollingFrame")
    local TabListLayout = Instance.new("UIListLayout")
    local TabListPadding = Instance.new("UIPadding")

    TabListFrame.Name = "TabList"
    TabListFrame.Parent = Sidebar
    TabListFrame.BackgroundTransparency = 1
    TabListFrame.BorderSizePixel = 0
    TabListFrame.Position = UDim2.new(0, 0, 0, 48)
    TabListFrame.Size = UDim2.new(1, 0, 1, -56)
    TabListFrame.ScrollBarThickness = 0

    TabListLayout.Parent = TabListFrame
    TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    TabListLayout.Padding = UDim.new(0, 5)

    TabListPadding.Parent = TabListFrame
    TabListPadding.PaddingLeft = UDim.new(0, 10)
    TabListPadding.PaddingRight = UDim.new(0, 10)
    TabListPadding.PaddingTop = UDim.new(0, 6)

    local Topbar = Instance.new("Frame")
    Topbar.Name = "Topbar"
    Topbar.Parent = Background_1
    Topbar.BackgroundTransparency = 1
    Topbar.Position = UDim2.new(0, 165, 0, 0)
    Topbar.Size = UDim2.new(1, -165, 0, 48)
    Topbar.ZIndex = 50
    lak(Topbar, Shadow_1)

    local CloseBtn = Instance.new("ImageButton")
    CloseBtn.Name = "Close"
    CloseBtn.Parent = Topbar
    CloseBtn.AnchorPoint = Vector2.new(1, 0.5)
    CloseBtn.BackgroundTransparency = 1
    CloseBtn.Position = UDim2.new(1, -14, 0.5, 0)
    CloseBtn.Size = UDim2.new(0, 18, 0, 18)
    CloseBtn.Image = "rbxassetid://15082305656"
    CloseBtn.ImageColor3 = curColors['SubText']

    CloseBtn.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
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

    local Tabs = { List = {} }

    function Tabs:Tab(tabOptions)
        local TabTitle = tabOptions.Title or 'Tab'
        local Icon = tabOptions.Icon or 'house'

        local TabBtn = Instance.new("Frame")
        local TabCorner = Instance.new("UICorner")
        local TabIcon = Instance.new("ImageLabel")
        local TabTitleLabel = Instance.new("TextLabel")
        local ClickTab = click(TabBtn)

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

        local PageScroll = Instance.new("ScrollingFrame")
        local PageLayout = Instance.new("UIListLayout")
        local PagePadding_1 = Instance.new("UIPadding")

        PageScroll.Name = "ScrollingFrame_" .. TabTitle
        PageScroll.Parent = Page_1
        PageScroll.Active = true
        PageScroll.BackgroundTransparency = 1
        PageScroll.BorderSizePixel = 0
        PageScroll.Size = UDim2.new(1, 0, 1, 0)
        PageScroll.ScrollBarThickness = 3
        PageScroll.Visible = false

        PageLayout.Parent = PageScroll
        PageLayout.Padding = UDim.new(0, 8)
        PageLayout.SortOrder = Enum.SortOrder.LayoutOrder

        PagePadding_1.Parent = PageScroll
        PagePadding_1.PaddingTop = UDim.new(0, 8)
        PagePadding_1.PaddingBottom = UDim.new(0, 12)
        PagePadding_1.PaddingLeft = UDim.new(0, 10)
        PagePadding_1.PaddingRight = UDim.new(0, 10)

        local tabData = { Page = PageScroll, Button = TabBtn, TitleLabel = TabTitleLabel, Icon = TabIcon }
        table.insert(Tabs.List, tabData)

        local function selectThisTab()
            for _, item in ipairs(Tabs.List) do
                item.Page.Visible = false
                tw({v = item.Button, t = 0.16, g = {BackgroundTransparency = 1}}):Play()
                tw({v = item.Icon, t = 0.16, g = {ImageColor3 = curColors['SubText']}}):Play()
                tw({v = item.TitleLabel, t = 0.16, g = {TextColor3 = curColors['SubText']}}):Play()
            end
            PageScroll.Visible = true
            tw({v = TabBtn, t = 0.18, g = {BackgroundTransparency = 0, BackgroundColor3 = curColors['MainDark']}}):Play()
            tw({v = TabIcon, t = 0.18, g = {ImageColor3 = Color3.fromRGB(255, 255, 255)}}):Play()
            tw({v = TabTitleLabel, t = 0.18, g = {TextColor3 = Color3.fromRGB(255, 255, 255)}}):Play()
        end

        ClickTab.MouseButton1Click:Connect(selectThisTab)

        if #Tabs.List == 1 then
            task.defer(selectThisTab)
        end

        local Func = {}

        function Func:Section(secOptions)
            local SectionTitle = (type(secOptions) == "table" and secOptions.Title) or tostring(secOptions or "BÖLÜM")
            local SectionFrame = Instance.new("Frame")
            local SectionCorner = Instance.new("UICorner")
            local SectionStroke = Instance.new("UIStroke")
            local SectionHeader = Instance.new("Frame")
            local SectionTitleLabel = Instance.new("TextLabel")
            local SectionContent = Instance.new("Frame")
            local ContentList = Instance.new("UIListLayout")
            local ContentPadding = Instance.new("UIPadding")

            SectionFrame.Name = "Section_" .. SectionTitle
            SectionFrame.Parent = PageScroll
            SectionFrame.BackgroundColor3 = curColors['Background']:Lerp(curColors['Card'], 0.35)
            SectionFrame.BorderSizePixel = 0
            SectionFrame.Size = UDim2.new(1, 0, 0, 42)
            SectionFrame.AutomaticSize = Enum.AutomaticSize.Y

            SectionCorner.CornerRadius = UDim.new(0, 8)
            SectionCorner.Parent = SectionFrame

            SectionStroke.Color = curColors['CardBorder']
            SectionStroke.Thickness = 1
            SectionStroke.Parent = SectionFrame

            local SectionFrameLayout = Instance.new("UIListLayout")
            SectionFrameLayout.Parent = SectionFrame
            SectionFrameLayout.SortOrder = Enum.SortOrder.LayoutOrder

            SectionHeader.Name = "Header"
            SectionHeader.Parent = SectionFrame
            SectionHeader.BackgroundTransparency = 1
            SectionHeader.Size = UDim2.new(1, 0, 0, 28)

            SectionTitleLabel.Name = "Title"
            SectionTitleLabel.Parent = SectionHeader
            SectionTitleLabel.Position = UDim2.new(0, 10, 0, 0)
            SectionTitleLabel.Size = UDim2.new(1, -10, 1, 0)
            SectionTitleLabel.BackgroundTransparency = 1
            SectionTitleLabel.Font = Enum.Font.BuilderSansBold
            SectionTitleLabel.Text = SectionTitle:upper()
            SectionTitleLabel.TextColor3 = curColors['SubText']
            SectionTitleLabel.TextSize = 12
            SectionTitleLabel.TextXAlignment = Enum.TextXAlignment.Left

            SectionContent.Name = "Content"
            SectionContent.Parent = SectionFrame
            SectionContent.BackgroundTransparency = 1
            SectionContent.Size = UDim2.new(1, 0, 0, 0)
            SectionContent.AutomaticSize = Enum.AutomaticSize.Y

            ContentList.Parent = SectionContent
            ContentList.SortOrder = Enum.SortOrder.LayoutOrder
            ContentList.Padding = UDim.new(0, 5)

            ContentPadding.Parent = SectionContent
            ContentPadding.PaddingBottom = UDim.new(0, 8)
            ContentPadding.PaddingLeft = UDim.new(0, 8)
            ContentPadding.PaddingRight = UDim.new(0, 8)

            local SecObj = {}

            function SecObj:Button(p)
                local BtnTitle = p.Title or 'Buton'
                local Desc = p.Desc or ''
                local Callback = p.Callback or function() end
                local Button, Config = background(SectionContent, BtnTitle, Desc, nil, 'Button')
                Config:SetSizeT(42)

                local ArrowIcon = Instance.new("ImageLabel")
                local arrowData = gl("chevron-right")
                ArrowIcon.Parent = Button
                ArrowIcon.AnchorPoint = Vector2.new(1, 0.5)
                ArrowIcon.BackgroundTransparency = 1
                ArrowIcon.Position = UDim2.new(1, -12, 0.5, 0)
                ArrowIcon.Size = UDim2.new(0, 14, 0, 14)
                ArrowIcon.Image = arrowData.Image
                ArrowIcon.ImageColor3 = curColors['SubText']

                local Click = click(Button)
                Click.MouseButton1Click:Connect(function()
                    tw({v = Button, t = 0.08, g = {BackgroundColor3 = curColors['Card']:Lerp(curColors['Main'], 0.18)}}):Play()
                    task.delay(0.08, function()
                        tw({v = Button, t = 0.15, g = {BackgroundColor3 = curColors['Card']}}):Play()
                    end)
                    pcall(Callback)
                end)
                return { SetTitle = Config.SetTitle, SetDesc = Config.SetDesc }
            end

            function SecObj:Toggle(p)
                local Value = p.Value or false
                local Callback = p.Callback or function() end
                local ToggleTitle = p.Title or 'Seçenek'
                local Desc = p.Desc or ''
                local Toggle, Config = background(SectionContent, ToggleTitle, Desc, nil, 'Toggle')
                Config:SetSizeT(50)

                local Frame_1 = Instance.new("Frame")
                local UICorner_2 = Instance.new("UICorner")
                local Frame_2 = Instance.new("Frame")
                local UICorner_3 = Instance.new("UICorner")

                Frame_1.Name = "SwitchPill"
                Frame_1.Parent = Toggle
                Frame_1.AnchorPoint = Vector2.new(1, 0.5)
                Frame_1.Position = UDim2.new(1, -12, 0.5, 0)
                Frame_1.Size = UDim2.new(0, 40, 0, 22)
                Frame_1.BackgroundColor3 = Value and curColors['Main'] or Color3.fromRGB(36, 36, 46)

                UICorner_2.CornerRadius = UDim.new(1, 0)
                UICorner_2.Parent = Frame_1

                Frame_2.Name = "Knob"
                Frame_2.Parent = Frame_1
                Frame_2.AnchorPoint = Vector2.new(0, 0.5)
                Frame_2.BackgroundColor3 = Value and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(160, 160, 170)
                Frame_2.Position = Value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
                Frame_2.Size = UDim2.new(0, 16, 0, 16)

                UICorner_3.CornerRadius = UDim.new(1, 0)
                UICorner_3.Parent = Frame_2

                local Click = click(Toggle)
                local function setToggleState(state)
                    Value = state
                    if Value then
                        tw({v = Frame_1, t = 0.18, g = {BackgroundColor3 = curColors['Main']}}):Play()
                        tw({v = Frame_2, t = 0.18, g = {BackgroundColor3 = Color3.fromRGB(15, 15, 18), Position = UDim2.new(1, -19, 0.5, 0)}}):Play()
                    else
                        tw({v = Frame_1, t = 0.18, g = {BackgroundColor3 = Color3.fromRGB(36, 36, 46)}}):Play()
                        tw({v = Frame_2, t = 0.18, g = {BackgroundColor3 = Color3.fromRGB(160, 160, 170), Position = UDim2.new(0, 3, 0.5, 0)}}):Play()
                    end
                    pcall(Callback, Value)
                end

                Click.MouseButton1Click:Connect(function() setToggleState(not Value) end)
                return { SetValue = setToggleState, GetValue = function() return Value end }
            end

            function SecObj:Slider(p)
                local SliderTitle = p.Title or 'Kaydırıcı'
                local Min = p.Min or 0
                local Max = p.Max or 100
                local Value = p.Value or Min
                local Callback = p.Callback or function() end

                local Slider, Config = background(SectionContent, SliderTitle, "", nil, 'Slider')
                Config:SetSizeT(180)

                local F = Instance.new("Frame")
                local SliderTrack = Instance.new("Frame")
                local SliderFill = Instance.new("Frame")
                local ValueBox = Instance.new("TextBox")

                F.Parent = Slider
                F.AnchorPoint = Vector2.new(1, 0.5)
                F.BackgroundTransparency = 1
                F.Position = UDim2.new(1, -12, 0.5, 0)
                F.Size = UDim2.new(0, 170, 0, 24)

                SliderTrack.Parent = F
                SliderTrack.AnchorPoint = Vector2.new(0, 0.5)
                SliderTrack.BackgroundColor3 = Color3.fromRGB(54, 54, 68)
                SliderTrack.Position = UDim2.new(0, 0, 0.5, 0)
                SliderTrack.Size = UDim2.new(0, 115, 0, 5)

                SliderFill.Parent = SliderTrack
                SliderFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                SliderFill.Size = UDim2.new((Value - Min) / (Max - Min), 0, 1, 0)

                ValueBox.Parent = F
                ValueBox.AnchorPoint = Vector2.new(1, 0.5)
                ValueBox.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
                ValueBox.Position = UDim2.new(1, 0, 0.5, 0)
                ValueBox.Size = UDim2.new(0, 42, 0, 22)
                ValueBox.Font = Enum.Font.BuilderSansMedium
                ValueBox.Text = tostring(Value)
                ValueBox.TextColor3 = curColors['Text & Icon']
                ValueBox.TextSize = 13

                local function updateSlider(v)
                    v = math.clamp(v, Min, Max)
                    Value = v
                    SliderFill.Size = UDim2.new((Value - Min) / (Max - Min), 0, 1, 0)
                    ValueBox.Text = tostring(v)
                    pcall(Callback, v)
                end

                ValueBox.FocusLost:Connect(function()
                    local n = tonumber(ValueBox.Text) or Min
                    updateSlider(n)
                end)

                return { SetValue = updateSlider, GetValue = function() return Value end }
            end

            return SecObj
        end

        return Func
    end

    function Tabs:Notify(p)
        local NotifTitle = p.Title or 'MakaraHub'
        local Desc = p.Desc or ''
        local Time = p.Time or 3.5

        local NotifCard = Instance.new("Frame")
        local CardCorner = Instance.new("UICorner")
        local TitleLabel = Instance.new("TextLabel")
        local DescLabel = Instance.new("TextLabel")

        NotifCard.Name = "NotifCard"
        NotifCard.Parent = ScreenGui
        NotifCard.AnchorPoint = Vector2.new(1, 1)
        NotifCard.Position = UDim2.new(1, -14, 1, -14)
        NotifCard.Size = UDim2.new(0, 240, 0, 56)
        NotifCard.BackgroundColor3 = curColors['Card']

        CardCorner.CornerRadius = UDim.new(0, 8)
        CardCorner.Parent = NotifCard

        TitleLabel.Parent = NotifCard
        TitleLabel.BackgroundTransparency = 1
        TitleLabel.Position = UDim2.new(0, 12, 0, 8)
        TitleLabel.Size = UDim2.new(1, -24, 0, 18)
        TitleLabel.Font = Enum.Font.BuilderSansBold
        TitleLabel.Text = tostring(NotifTitle)
        TitleLabel.TextColor3 = curColors['Text & Icon']
        TitleLabel.TextSize = 14
        TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

        DescLabel.Parent = NotifCard
        DescLabel.BackgroundTransparency = 1
        DescLabel.Position = UDim2.new(0, 12, 0, 28)
        DescLabel.Size = UDim2.new(1, -24, 0, 16)
        DescLabel.Font = Enum.Font.BuilderSansMedium
        DescLabel.Text = tostring(Desc)
        DescLabel.TextColor3 = curColors['SubText']
        DescLabel.TextSize = 12
        DescLabel.TextXAlignment = Enum.TextXAlignment.Left

        task.delay(Time, function() NotifCard:Destroy() end)
    end

    return Tabs
end

return Library
