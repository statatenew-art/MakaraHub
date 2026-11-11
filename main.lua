-- MakaraHub UI Kütüphanesini GitHub'dan Çek
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/statatenew-art/MakaraHub/refs/heads/main/ui_lib.lua?t=" .. tick()))()

-- Pencereyi Başlat (Orijinal Aether Stili)
local Window = Library:Window({
    Title = "MakaraHub",
    Desc = "TDS Edition"
})

-- Sol Menü Sekmeleri
local AnaSekme = Window:Tab({
    Title = "Genel",
    Icon = "house"
})

local SavasSekmesi = Window:Tab({
    Title = "TDS Menü",
    Icon = "gamepad-2"
})

-- Bölümler ve Kontroller
local KarakterBolumu = AnaSekme:Section({ Title = "Karakter Hileleri" })

KarakterBolumu:Toggle({
    Title = "Hızlı Koşma",
    Desc = "Karakterin yürüme hızını 32 yapar",
    Value = false,
    Callback = function(durum)
        local hum = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = durum and 32 or 16 end
    end
})

KarakterBolumu:Slider({
    Title = "Özel Hız Değeri",
    Min = 16,
    Max = 120,
    Value = 16,
    Callback = function(deger)
        local hum = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = deger end
    end
})

local TDSIlemler = SavasSekmesi:Section({ Title = "Otomasyon" })

TDSIlemler:Toggle({
    Title = "Oto Dalga Geç (Auto Skip)",
    Desc = "Dalga geldiğinde otomatik geçer",
    Value = false,
    Callback = function(durum)
        print("Auto Skip durumu:", durum)
    end
})

-- Açılış Bildirimi
Library:Notify({
    Title = "MakaraHub",
    Desc = "Menü sorunsuz aktif edildi!",
    Time = 3.5
})
