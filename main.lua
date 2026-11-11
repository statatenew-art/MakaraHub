-- MakaraHub TDS Başlatıcı (main.lua)
local GITHUB_USER = "statatenew-art"
local REPO = "MakaraHub"

-- 1. Anti-AFK Devreye Alma (Roblox 20 dk kick engelleyici)
local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- 2. UI Kütüphanesini ve Core URL'sini Tanımlama
local UILib = loadstring(game:HttpGet(string.format("https://raw.githubusercontent.com/%s/%s/main/UI.lua", GITHUB_USER, REPO)))()
local CoreEngineURL = string.format("https://raw.githubusercontent.com/%s/%s/main/Library.lua", GITHUB_USER, REPO)

-- 3. Arayüz Penceresini Başlatma
local Tabs = UILib:Window({
    Title = "MAKARAHUB",
    Desc = "TDS AUTOMATION",
    Icon = "door-open",
    Theme = "CoreRed"
})

local StratTab = Tabs:Tab({
    Title = "STRATEJI",
    Subtitle = "Auto-Play Kontrolü",
    Icon = "play"
})

local StratSec = StratTab:Section({ Title = "Strateji Yürütücü" })

local MacroCode = ""

StratSec:Textbox({
    Title = "Özel Strateji Kodu",
    Desc = "Easy Solo.txt içeriğini veya raw URL yapıştır",
    Placeholder = "Strateji kodu veya https://raw... linki",
    Callback = function(val)
        MacroCode = val
    end
})

StratSec:Button({
    Title = "Stratejiyi Başlat",
    Desc = "Kodu derler ve kuleleri yerleştirmeye başlar",
    Image = "play",
    Callback = function()
        if MacroCode == "" then
            Tabs:Notify({
                Title = "Hata",
                Desc = "Lütfen bir strateji kodu veya linki girin!",
                Time = 3,
                Type = "error"
            })
            return
        end

        local finalScript = MacroCode
        -- Eğer kullanıcı direkt raw URL yapıştırdıysa indir
        if string.sub(MacroCode, 1, 4) == "http" then
            finalScript = game:HttpGet(MacroCode)
        end

        -- Strateji metnindeki Aether / getaether / pickscripthub bağlantılarını kendi Library.lua ile ez
        local customLoader = string.format('local TDS = loadstring(game:HttpGet("%s"))()', CoreEngineURL)
        finalScript = string.gsub(finalScript, 'local TDS = loadstring%(game:HttpGet%(.-%)%)%(%)', customLoader)

        Tabs:Notify({
            Title = "MakaraHub",
            Desc = "Strateji motoru başlatıldı...",
            Time = 3,
            Type = "normal"
        })

        local execFunc, compileErr = loadstring(finalScript)
        if execFunc then
            task.spawn(execFunc)
        else
            warn("[MakaraHub Hata] Strateji derleme hatası: " .. tostring(compileErr))
        end
    end
})

StratSec:Button({
    Title = "Hızlı Test: Lay-By Solo Scout",
    Desc = "GitHub üzerindeki hazır Lay-By Easy modunu başlatır",
    Image = "zap",
    Callback = function()
        local stratRaw = game:HttpGet("https://raw.githubusercontent.com/8zj/aspoidhasouphsaohoasidjnmasaindoasbpgdas8udgouihassdhsaaiisaggdaghbouudsaktgdiysagdbuiagsigdas0gdpia/refs/heads/main/EasyMode/Lay-By.lua")
        local customLoader = string.format('local TDS = loadstring(game:HttpGet("%s"))()', CoreEngineURL)
        local executable = string.gsub(stratRaw, 'local TDS = loadstring%(game:HttpGet%(.-%)%)%(%)', customLoader)
        
        local run = loadstring(executable)
        if run then
            task.spawn(run)
            Tabs:Notify({
                Title = "MakaraHub",
                Desc = "Lay-By Solo başlatıldı!",
                Time = 3,
                Type = "normal"
            })
        end
    end
})
