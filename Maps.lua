-- MakaraHub Kapsamlı TDS Harita Veritabanı (Maps.lua)
local Maps = {
    -- Kolay / Başlangıç Seviyesi Haritalar
    Easy = {
        "Crossroads",
        "Grass Isle",
        "Autumn Falling",
        "Simplicity",
        "Winter Bridges",
        "Four Seasons",
        "Medieval",
        "Honey Valley",
        "Candyland",
        "Toy Board",
        "Sweet Tooth",
        "Dusty Bridges"
    },

    -- Orta Seviye Haritalar
    Medium = {
        "Gilded Path",
        "Abandoned City",
        "Desert",
        "Canyon",
        "Marshlands",
        "Forest Camp",
        "Crystal Cave",
        "Sky Islands",
        "Oasis",
        "Tropical",
        "Harbor",
        "Masonry",
        "Night Station",
        "Cyber City",
        "Retro Zone",
        "Cataclysm",
        "Abyssal Trench",
        "Fallen Kingdom"
    },

    -- Zor Seviye Haritalar
    Hard = {
        "Sandstorm",
        "Nether",
        "Space City",
        "UFO",
        "Steampunk",
        "Dead Ahead",
        "Wrecked Battlefield",
        "Chaos Canyon"
    },

    -- Hardcore, Özel Modlar ve Triumph Haritaları
    Special = {
        "Badlands II",
        "Polluted Wasteland II",
        "Pizza Party",
        "Regal Ruin",
        "Infernal Abyss",
        "Lucid Nightmares",
        "Nuclear Island"
    }
}

-- Yardımcı Arama ve Doğrulama Fonksiyonu
-- Küçük/büyük harf veya boşluk hatalarını tolere eder
function Maps.IsValid(mapName)
    if not mapName then return false, nil end
    local cleanInput = string.lower(string.gsub(mapName, "%s+", ""))
    
    for _, category in pairs(Maps) do
        if type(category) == "table" then
            for _, name in ipairs(category) do
                local cleanTarget = string.lower(string.gsub(name, "%s+", ""))
                if cleanInput == cleanTarget then
                    return true, name
                end
            end
        end
    end
    return false, mapName
end

return Maps
