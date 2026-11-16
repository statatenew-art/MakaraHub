-- MakaraHub - Aether Yonlendirici Loader (TDS ve Universal)

-- 1. Eger Executor destekliyorsa (synapse vb.) mevcut HTTP isteklerini dinleyip engelleme
local reqFunc = request or http_request or (syn and syn.request)
if reqFunc then
    local OldRequest
    OldRequest = hookfunction(reqFunc, function(options)
        if options and type(options.Url) == "string" then
            local lowerUrl = string.lower(options.Url)
            if string.find(lowerUrl, "jnkie") or string.find(lowerUrl, "api.jnkie.com") then
                -- Sunucuya hic gitmeden sahte "basarili" JSON onayi dondur
                return {
                    StatusCode = 200,
                    Success = true,
                    Body = '{"valid": true, "message": "KEYLESS", "premium": true}',
                    Headers = {["Content-Type"] = "application/json"}
                }
            end
        end
        return OldRequest(options)
    end)
end

-- Basit HttpGet icin de guvenlik onlemi
local OldHttpGet
if type(hookfunction) == "function" and game.HttpGet then
    OldHttpGet = hookfunction(game.HttpGet, function(self, url, ...)
        if type(url) == "string" then
            local lowerUrl = string.lower(url)
            if string.find(lowerUrl, "jnkie") then
                return '{"valid": true, "message": "KEYLESS", "premium": true}'
            end
        end
        return OldHttpGet(self, url, ...)
    end)
end

-- SCRIPT_KEY sistemini bypass et
getgenv().KEYLESS = true
if typeof(_G) == "table" then _G.KEYLESS = true end
if typeof(shared) == "table" then shared.KEYLESS = true end

-- 2. Hangi oyunda oldugumuzu kontrol edip ona gore script cekme
local PlaceId = game.PlaceId

-- Tower Defense Simulator ID'leri
if PlaceId == 3260590327 or PlaceId == 5591597781 then
    print("[MakaraHub] TDS algilandi, ozel hile (Dosya 5) yukleniyor...")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/statatenew-art/MakaraHub/refs/heads/main/TDS.lua"))()
else
    print("[MakaraHub] Desteklenmeyen oyun, Universal Aether (Temizlenmis Dosya 1/4) yukleniyor...")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/statatenew-art/MakaraHub/refs/heads/main/Universal.lua"))()
end
