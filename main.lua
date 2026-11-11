-- Önbellek kırıcı ekleyerek ( ?t=... ) kütüphaneyi çek
local libUrl = "https://raw.githubusercontent.com/statatenew-art/MakaraHub/refs/heads/main/ui_lib.lua?t=" .. tostring(os.time())

local success, response = pcall(function()
    return game:HttpGet(libUrl)
end)

if not success or not response or #response < 100 then
    warn("[MakaraHub] ui_lib.lua indirilemedi! Yanıt boyutu:", response and #response)
    return
end

local loadSuccess, Library = pcall(function()
    return loadstring(response)()
end)

if not loadSuccess or type(Library) ~= "table" then
    warn("[MakaraHub] UI Kütüphanesi yüklenirken hata oluştu:", tostring(Library))
    return
end

-- Pencereyi Başlat
local Window = Library:Window({
    Title = "MakaraHub",
    Desc = "TDS Edition"
})

-- Genel Sekme
local AnaSekme = Window:Tab({
    Title = "Genel",
    Icon = "house"
})

-- Karakter Ayarları Bölümü
local KarakterBolumu = AnaSekme:Section({ Title = "Karakter Ayarları" })

-- Hız Toggle
KarakterBolumu:Toggle({
    Title = "Hızlı Koşma",
    Desc = "Karakter hızını 32 yapar",
    Value = false,
    Callback = function(durum)
        local hum = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = durum and 32 or 16
        end
    end
})

-- Bildirim Gönder
Library:Notify({
    Title = "MakaraHub",
    Desc = "Menü başarıyla yüklendi!",
    Time = 3
})
