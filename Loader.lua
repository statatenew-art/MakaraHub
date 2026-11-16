-- JNKIE Bypass ve Keysiz Mod
getgenv().KEYLESS = true
getgenv().SCRIPT_KEY = "KEYLESS"

local WorkerURL = "https://raw.githubusercontent.com/statatenew-art/MakaraHub/main/"
-- (Eğer Cloudflare kullanıyorsan burayı kendi workers linkinle değiştirebilirsin)

print("[MakaraHub] Ana arayüz (Universal) yükleniyor...")
-- 1. ADIM: Her zaman önce ana menüyü (iskeleti) yükle
local success, err = pcall(function()
    loadstring(game:HttpGet(WorkerURL .. "Universal.lua"))()
end)

if not success then
    warn("[MakaraHub] Arayüz yüklenemedi: " .. tostring(err))
end

task.wait(1) -- Arayüzün tam oturması için kısa bir bekleme

-- 2. ADIM: Eğer oyun TDS ise, özel hile modülünü üstüne ekle
local PlaceId = game.PlaceId
if PlaceId == 3260590327 or PlaceId == 5591597781 then
    print("[MakaraHub] TDS algılandı, Gatlify/Auto-Farm modülü enjekte ediliyor...")
    loadstring(game:HttpGet(WorkerURL .. "Modules/TDS.lua"))()
end
