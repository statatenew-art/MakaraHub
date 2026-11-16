-- JNKIE HTTP İsteklerini Yakalama ve Sahte Onay Verme
local function hookJNKIE()
    local reqFunc = request or http_request or (syn and syn.request)
    if reqFunc then
        local OldRequest
        OldRequest = hookfunction(reqFunc, function(options)
            if options and type(options.Url) == "string" then
                local lowerUrl = string.lower(options.Url)
                if string.find(lowerUrl, "jnkie") or string.find(lowerUrl, "api.jnkie.com") then
                    -- Sunucuya gitmeden sahte "başarılı" onayı döndür
                    return {
                        StatusCode = 200,
                        Success = true,
                        Body = '{"valid": true, "message": "KEY_VALID", "premium": true}',
                        Headers = {["Content-Type"] = "application/json"}
                    }
                end
            end
            return OldRequest(options)
        end)
    end

    local OldHttpGet
    if type(hookfunction) == "function" and game.HttpGet then
        OldHttpGet = hookfunction(game.HttpGet, function(self, url, ...)
            if type(url) == "string" then
                local lowerUrl = string.lower(url)
                if string.find(lowerUrl, "jnkie") then
                    return '{"valid": true, "message": "KEY_VALID", "premium": true}'
                end
            end
            return OldHttpGet(self, url, ...)
        end)
    end
end

-- Hook'u çalıştır
hookJNKIE()

-- Mevcut KEYLESS ayarlarını koruyalım
getgenv().KEYLESS = true
getgenv().SCRIPT_KEY = "KEYLESS"
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
