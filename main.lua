-- MakaraHub Kararlı Sürüm
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- GUI Parent Belirleme (CoreGui veya PlayerGui)
local function getGuiParent()
    local success, _ = pcall(function() return CoreGui:GetChildren() end)
    if success then return CoreGui end
    return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or game:GetService("StarterGui")
end

local parentGui = getGuiParent()
pcall(function()
    local ex = parentGui:FindFirstChild("MakaraHub")
    if ex then ex:Destroy() end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MakaraHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = parentGui

local function tw(obj, prop, time)
    TweenService:Create(obj, TweenInfo.new(time or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), prop):Play()
end

-- Karakter nesnesini güvenle alma fonksiyonu
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

-- Ana Çerçeve (Window)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.Size = UDim2.new(0, 520, 0, 320)
MainFrame.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Active = true
MainFrame.Draggable = true

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(40, 40, 50)
MainStroke.Thickness = 1.2
MainStroke.Parent = MainFrame

-- Yan Panel (Sidebar)
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Parent = MainFrame
Sidebar.BackgroundColor3 = Color3.fromRGB(17, 17, 22)
Sidebar.BorderSizePixel = 0
Sidebar.Size = UDim2.new(0, 150, 1, 0)

local SidebarCorner = Instance.new("UICorner")
SidebarCorner.CornerRadius = UDim.new(0, 10)
SidebarCorner.Parent = Sidebar

local Logo = Instance.new("TextLabel")
Logo.Parent = Sidebar
Logo.BackgroundTransparency = 1
Logo.Position = UDim2.new(0, 14, 0, 12)
Logo.Size = UDim2.new(1, -20, 0, 24)
Logo.Font = Enum.Font.BuilderSansBold
Logo.Text = "MakaraHub"
Logo.TextColor3 = Color3.fromRGB(255, 255, 255)
Logo.TextSize = 18
Logo.TextXAlignment = Enum.TextXAlignment.Left

-- Sekme Listesi
local TabContainer = Instance.new("Frame")
TabContainer.Parent = Sidebar
TabContainer.BackgroundTransparency = 1
TabContainer.Position = UDim2.new(0, 8, 0, 50)
TabContainer.Size = UDim2.new(1, -16, 1, -60)

local TabLayout = Instance.new("UIListLayout")
TabLayout.Parent = TabContainer
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Padding = UDim.new(0, 6)

-- Sağ Taraf İçerik Alanı
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Parent = MainFrame
ContentArea.BackgroundTransparency = 1
ContentArea.Position = UDim2.new(0, 155, 0, 10)
ContentArea.Size = UDim2.new(1, -165, 1, -20)

-- Kapat Butonu
local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = MainFrame
CloseBtn.AnchorPoint = Vector2.new(1, 0)
CloseBtn.Position = UDim2.new(1, -10, 0, 10)
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.Font = Enum.Font.BuilderSansBold
CloseBtn.TextSize = 13

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Sekme Oluşturma Mantığı
local tabs = {}
local function CreateTab(tabName)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Parent = TabContainer
    TabBtn.Size = UDim2.new(1, 0, 0, 34)
    TabBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    TabBtn.BackgroundTransparency = 1
    TabBtn.Text = tabName
    TabBtn.TextColor3 = Color3.fromRGB(150, 150, 160)
    TabBtn.Font = Enum.Font.BuilderSansBold
    TabBtn.TextSize = 14
    TabBtn.TextXAlignment = Enum.TextXAlignment.Left

    local TabBtnPad = Instance.new("UIPadding")
    TabBtnPad.Parent = TabBtn
    TabBtnPad.PaddingLeft = UDim.new(0, 12)

    local TabBtnCorner = Instance.new("UICorner")
    TabBtnCorner.CornerRadius = UDim.new(0, 6)
    TabBtnCorner.Parent = TabBtn

    local TabPage = Instance.new("ScrollingFrame")
    TabPage.Name = "Page_" .. tabName
    TabPage.Parent = ContentArea
    TabPage.BackgroundTransparency = 1
    TabPage.BorderSizePixel = 0
    TabPage.Position = UDim2.new(0, 0, 0, 30)
    TabPage.Size = UDim2.new(1, 0, 1, -30)
    TabPage.ScrollBarThickness = 3
    TabPage.Visible = false

    local PageLayout = Instance.new("UIListLayout")
    PageLayout.Parent = TabPage
    PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    PageLayout.Padding = UDim.new(0, 8)

    local function selectTab()
        for _, t in ipairs(tabs) do
            t.Page.Visible = false
            t.Btn.BackgroundTransparency = 1
            t.Btn.TextColor3 = Color3.fromRGB(150, 150, 160)
        end
        TabPage.Visible = true
        TabBtn.BackgroundTransparency = 0
        TabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    TabBtn.MouseButton1Click:Connect(selectTab)
    table.insert(tabs, { Btn = TabBtn, Page = TabPage })

    if #tabs == 1 then
        selectTab()
    end

    local TabActions = {}

    function TabActions:AddToggle(title, desc, default, callback)
        local Tog = Instance.new("Frame")
        Tog.Parent = TabPage
        Tog.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        Tog.Size = UDim2.new(1, -6, 0, 48)

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 6)
        Corner.Parent = Tog

        local Stroke = Instance.new("UIStroke")
        Stroke.Color = Color3.fromRGB(36, 36, 46)
        Stroke.Parent = Tog

        local TitleLbl = Instance.new("TextLabel")
        TitleLbl.Parent = Tog
        TitleLbl.BackgroundTransparency = 1
        TitleLbl.Position = UDim2.new(0, 12, 0, 6)
        TitleLbl.Size = UDim2.new(1, -70, 0, 18)
        TitleLbl.Font = Enum.Font.BuilderSansBold
        TitleLbl.Text = title
        TitleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        TitleLbl.TextSize = 14
        TitleLbl.TextXAlignment = Enum.TextXAlignment.Left

        local DescLbl = Instance.new("TextLabel")
        DescLbl.Parent = Tog
        DescLbl.BackgroundTransparency = 1
        DescLbl.Position = UDim2.new(0, 12, 0, 24)
        DescLbl.Size = UDim2.new(1, -70, 0, 16)
        DescLbl.Font = Enum.Font.BuilderSansMedium
        DescLbl.Text = desc
        DescLbl.TextColor3 = Color3.fromRGB(140, 140, 150)
        DescLbl.TextSize = 11
        DescLbl.TextXAlignment = Enum.TextXAlignment.Left

        local Pill = Instance.new("Frame")
        Pill.Parent = Tog
        Pill.AnchorPoint = Vector2.new(1, 0.5)
        Pill.Position = UDim2.new(1, -12, 0.5, 0)
        Pill.Size = UDim2.new(0, 38, 0, 20)
        Pill.BackgroundColor3 = default and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(36, 36, 46)

        local PillCorner = Instance.new("UICorner")
        PillCorner.CornerRadius = UDim.new(1, 0)
        PillCorner.Parent = Pill

        local Knob = Instance.new("Frame")
        Knob.Parent = Pill
        Knob.AnchorPoint = Vector2.new(0, 0.5)
        Knob.Size = UDim2.new(0, 14, 0, 14)
        Knob.Position = default and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        Knob.BackgroundColor3 = default and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(160, 160, 170)

        local KnobCorner = Instance.new("UICorner")
        KnobCorner.CornerRadius = UDim.new(1, 0)
        KnobCorner.Parent = Knob

        local state = default
        local Click = Instance.new("TextButton")
        Click.Parent = Tog
        Click.BackgroundTransparency = 1
        Click.Size = UDim2.new(1, 0, 1, 0)
        Click.Text = ""

        Click.MouseButton1Click:Connect(function()
            state = not state
            tw(Pill, { BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(36, 36, 46) }, 0.15)
            tw(Knob, {
                Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                BackgroundColor3 = state and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(160, 160, 170)
            }, 0.15)
            pcall(callback, state)
        end)
    end

    function TabActions:AddSlider(title, min, max, default, callback)
        local Sld = Instance.new("Frame")
        Sld.Parent = TabPage
        Sld.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        Sld.Size = UDim2.new(1, -6, 0, 48)

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 6)
        Corner.Parent = Sld

        local Stroke = Instance.new("UIStroke")
        Stroke.Color = Color3.fromRGB(36, 36, 46)
        Stroke.Parent = Sld

        local TitleLbl = Instance.new("TextLabel")
        TitleLbl.Parent = Sld
        TitleLbl.BackgroundTransparency = 1
        TitleLbl.Position = UDim2.new(0, 12, 0.5, -9)
        TitleLbl.Size = UDim2.new(1, -170, 0, 18)
        TitleLbl.Font = Enum.Font.BuilderSansBold
        TitleLbl.Text = title
        TitleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        TitleLbl.TextSize = 13
        TitleLbl.TextXAlignment = Enum.TextXAlignment.Left

        local Track = Instance.new("Frame")
        Track.Parent = Sld
        Track.AnchorPoint = Vector2.new(1, 0.5)
        Track.Position = UDim2.new(1, -55, 0.5, 0)
        Track.Size = UDim2.new(0, 95, 0, 5)
        Track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)

        local TrackCorner = Instance.new("UICorner")
        TrackCorner.CornerRadius = UDim.new(1, 0)
        TrackCorner.Parent = Track

        local Fill = Instance.new("Frame")
        Fill.Parent = Track
        Fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
        Fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

        local FillCorner = Instance.new("UICorner")
        FillCorner.CornerRadius = UDim.new(1, 0)
        FillCorner.Parent = Fill

        local ValBox = Instance.new("TextBox")
        ValBox.Parent = Sld
        ValBox.AnchorPoint = Vector2.new(1, 0.5)
        ValBox.Position = UDim2.new(1, -10, 0.5, 0)
        ValBox.Size = UDim2.new(0, 38, 0, 22)
        ValBox.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
        ValBox.Text = tostring(default)
        ValBox.TextColor3 = Color3.fromRGB(255, 255, 255)
        ValBox.Font = Enum.Font.BuilderSansMedium
        ValBox.TextSize = 12

        local ValBoxCorner = Instance.new("UICorner")
        ValBoxCorner.CornerRadius = UDim.new(0, 4)
        ValBoxCorner.Parent = ValBox

        local currentVal = default
        local function update(v)
            v = math.clamp(v, min, max)
            currentVal = v
            Fill.Size = UDim2.new((v - min) / (max - min), 0, 1, 0)
            ValBox.Text = tostring(v)
            pcall(callback, v)
        end

        ValBox.FocusLost:Connect(function()
            local n = tonumber(ValBox.Text) or currentVal
            update(n)
        end)
    end

    return TabActions
end

-- ====================
-- SEKMELER VE BUTONLAR
-- ====================
local GenelTab = CreateTab("Genel")
local TdsTab = CreateTab("TDS Savaş")

-- 1. Genel Sekme
GenelTab:AddToggle("Hızlı Koşma (WalkSpeed)", "Karakteri hızlandırır", false, function(state)
    local char = getCharacter()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = state and 32 or 16
    end
end)

GenelTab:AddSlider("Özel Hız", 16, 120, 16, function(val)
    local char = getCharacter()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = val
    end
end)

GenelTab:AddToggle("Yüksek Zıplama", "Zıplama gücünü arttırır", false, function(state)
    local char = getCharacter()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.JumpPower = state and 90 or 50
    end
end)

-- 2. TDS Sekmesi
local autoSkip = false
TdsTab:AddToggle("Oto Dalga Atlama (Auto Skip)", "Yeni dalga gelince otomatik geçer", false, function(state)
    autoSkip = state
    if state then
        task.spawn(function()
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            while autoSkip do
                pcall(function()
                    local remote = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if remote then
                        remote:FireServer("Waves", "Skip")
                    end
                end)
                task.wait(1.5)
            end
        end)
    end
end)

print("[MakaraHub] Menü hatasız açıldı!")
