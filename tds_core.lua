-- MakaraHub TDS Core Strat Interpreter
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local RemoteFunction = ReplicatedStorage:WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local TDS = {}
local placedTowers = {}

-- 1. Loadout & Hazırlık
function TDS:Loadout(...)
    local towers = {...}
    print("[MakaraHub] Loadout ayarlandı:", table.concat(towers, ", "))
    pcall(function()
        RemoteFunction:InvokeServer("Inventory", "Equip", "Troops", towers)
    end)
end

function TDS:Mode(modeName)
    print("[MakaraHub] Zorluk Modu Seçildi:", modeName)
    pcall(function()
        RemoteFunction:InvokeServer("Difficulty", "Vote", modeName)
    end)
end

function TDS:GameInfo(mapName, options)
    print("[MakaraHub] Harita Bilgisi:", mapName)
end

-- 2. Kule Yerleştirme
function TDS:Place(towerName, x, y, z)
    local pos = Vector3.new(x, y, z)
    local args = {
        [1] = "Troops",
        [2] = "Place",
        [3] = towerName,
        [4] = {
            ["Rotation"] = CFrame.new(),
            ["Position"] = pos
        }
    }
    
    local success, result = pcall(function()
        return RemoteFunction:InvokeServer(unpack(args))
    end)
    
    task.wait(0.3)
    local towersFolder = Workspace:FindFirstChild("Towers")
    if towersFolder then
        local children = towersFolder:GetChildren()
        table.insert(placedTowers, children[#children])
    end
    print(string.format("[MakaraHub] %s yerleştirildi -> (%.2f, %.2f, %.2f)", towerName, x, y, z))
end

-- 3. Kule Yükseltme
function TDS:Upgrade(towerIndex)
    local target = placedTowers[towerIndex]
    if not target then
        local towersFolder = Workspace:FindFirstChild("Towers")
        if towersFolder then
            target = towersFolder:GetChildren()[towerIndex]
        end
    end
    
    if target then
        local args = {
            [1] = "Troops",
            [2] = "Upgrade",
            [3] = "Set",
            [4] = {
                ["Troop"] = target
            }
        }
        pcall(function()
            RemoteFunction:InvokeServer(unpack(args))
        end)
        print("[MakaraHub] Kule geliştirildi: #" .. tostring(towerIndex))
    else
        warn("[MakaraHub] Geliştirilecek kule bulunamadı: #" .. tostring(towerIndex))
    end
end

-- 4. Kule Satma
function TDS:Sell(towerIndex)
    local target = placedTowers[towerIndex]
    if target then
        pcall(function()
            RemoteFunction:InvokeServer("Troops", "Sell", { ["Troop"] = target })
        end)
        print("[MakaraHub] Kule satıldı: #" .. tostring(towerIndex))
    end
end

-- 5. Yetenek / Dalga Atlama (Ready & Abilities)
function TDS:Ready()
    pcall(function()
        RemoteFunction:InvokeServer("Waves", "Skip")
    end)
end

function TDS:Ability(towerIndex, abilityName)
    local target = placedTowers[towerIndex]
    if target then
        pcall(function()
            RemoteFunction:InvokeServer("Troops", "Abilities", "Execute", {
                ["Troop"] = target,
                ["Name"] = abilityName
            })
        end)
    end
end

-- Settings kontrolleri için arka plan izleyicileri (Commander Zinciri, Auto Skip vs.)
task.spawn(function()
    while task.wait(1) do
        -- AutoChain aktifse
        if getgenv().AutoChain then
            local towersFolder = Workspace:FindFirstChild("Towers")
            if towersFolder then
                for _, t in ipairs(towersFolder:GetChildren()) do
                    local owner = t:FindFirstChild("Owner")
                    if owner and owner.Value == LocalPlayer.UserId and string.find(t.Name:lower(), "commander") then
                        pcall(function()
                            RemoteFunction:InvokeServer("Troops", "Abilities", "Execute", {
                                ["Troop"] = t,
                                ["Name"] = "Call to Arms"
                            })
                        end)
                        task.wait(10.1)
                    end
                end
            end
        end
    end
end)

print("[MakaraHub] TDS Strateji Motoru Devrede!")
return TDS
