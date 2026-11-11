-- MakaraHub TDS Core Library (v2.1 - Table Safe & Auto Lobby/Island)
local TDS = {}
TDS.PlacedTowers = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local RemoteFunction = ReplicatedStorage:WaitForChild("RemoteFunction", 15)
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent", 15)
local Network = ReplicatedStorage:FindFirstChild("Network")

-- Haritaların Varsayılan Zorluk Eşleştirmesi
local MapDifficulties = {
    ["Gilded Path"] = "Easy",
    ["Grass Isle"] = "Easy",
    ["Crystal Cave"] = "Intermediate",
    ["Crossroads"] = "Molten",
    ["Abandoned City"] = "Fallen"
}

local function isInGame()
    return Workspace:FindFirstChild("Towers") ~= nil or Workspace:FindFirstChild("Troops") ~= nil
end

local function getCurrentWave()
    local stateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
    if stateReplicators then
        local gameState = stateReplicators:FindFirstChild("GameStateReplicator")
        if gameState then
            local wave = gameState:GetAttribute("Wave")
            if wave then return wave end
        end
    end
    local state = ReplicatedStorage:FindFirstChild("State")
    if state and state:FindFirstChild("Wave") then
        return state.Wave.Value
    end
    return 0
end

function TDS:GameInfo(mapData, customDifficulty)
    local mapName = "Gilded Path"
    local difficulty = "Easy"

    -- Gelen veriyi güvenli çözümle (Tablo veya String)
    if type(mapData) == "table" then
        mapName = mapData["Map"] or mapData["map"] or mapData[1] or "Gilded Path"
        difficulty = mapData["Difficulty"] or mapData["difficulty"] or mapData["Mode"] or customDifficulty or MapDifficulties[mapName] or "Easy"
    elseif type(mapData) == "string" then
        mapName = mapData
        difficulty = customDifficulty or MapDifficulties[mapName] or "Easy"
    end

    print(string.format("[MakaraHub] Baslatiliyor -> Harita: %s | Zorluk: %s", tostring(mapName), tostring(difficulty)))

    -- 1. Lobideysek: Doğrudan Tekli Odaya Gir
    if not isInGame() then
        task.spawn(function()
            pcall(function()
                if Network and Network:FindFirstChild("Elevators") then
                    Network.Elevators["RF:Leave"]:InvokeServer()
                end
            end)
            task.wait(0.3)
            pcall(function()
                RemoteFunction:InvokeServer("Multiplayer", "single_create", {
                    ["Difficulty"] = difficulty,
                    ["Mode"] = "Survival",
                    ["Count"] = 1
                })
            end)
        end)
    end

    -- 2. Adadaysak: Haritayı Override Et ve Ready Ver
    task.spawn(function()
        for i = 1, 30 do
            if isInGame() then break end

            local success = pcall(function()
                RemoteFunction:InvokeServer("LobbyVoting", "Override", mapName)
            end)

            if success then
                print("[MakaraHub] Harita Override Yapildi: " .. tostring(mapName))
                task.wait(0.4)
                pcall(function()
                    RemoteEvent:FireServer("LobbyVoting", "Ready")
                end)
                break
            end
            task.wait(1)
        end
    end)

    -- 3. Oyun Haritasının Açılmasını Bekle
    print("[MakaraHub] Oyun haritasina gecis bekleniyor...")
    while not isInGame() do
        task.wait(1)
    end
    print("[MakaraHub] Harita yuklendi! Kule adimlarina geciliyor.")
end

function TDS:Loadout(...)
    local towers = {...}
    pcall(function()
        RemoteFunction:InvokeServer("Troops", "Loadout", "Set", towers)
    end)
    task.wait(0.5)
end

function TDS:Mode(modeName, code)
    if isInGame() then
        pcall(function()
            RemoteFunction:InvokeServer("Difficulty", "Vote", modeName)
        end)
    end
    task.wait(0.5)
end

function TDS:Ready()
    if not isInGame() then return end
    pcall(function()
        RemoteFunction:InvokeServer("Team", "Ready")
    end)
    task.wait(0.5)
end

function TDS:WaitForWave(targetWave)
    while getCurrentWave() < targetWave do
        task.wait(0.5)
    end
end

function TDS:Place(towerName, x, y, z, stack)
    while not isInGame() do
        task.wait(1)
    end

    local pos = Vector3.new(x, y, z)
    local rot = CFrame.Angles(0, 0, 0)
    local placedInstance = nil
    local retries = 0

    while not placedInstance and retries < 25 do
        pcall(function()
            placedInstance = RemoteFunction:InvokeServer("Troops", "Place", towerName, {
                ["Position"] = pos,
                ["Rotation"] = rot
            })
        end)

        if not placedInstance then
            local towers = Workspace:FindFirstChild("Towers") or Workspace:FindFirstChild("Troops")
            if towers then
                for _, tr in ipairs(towers:GetChildren()) do
                    local rep = tr:FindFirstChild("TowerReplicator")
                    local isMine = (rep and rep:GetAttribute("OwnerId") == LocalPlayer.UserId) or (tr:FindFirstChild("Owner") and tr.Owner.Value == LocalPlayer.UserId)
                    if isMine and (tr:GetPivot().Position - pos).Magnitude < 1.5 then
                        placedInstance = tr
                        break
                    end
                end
            end
        end

        if not placedInstance then
            retries = retries + 1
            task.wait(0.5)
        end
    end

    table.insert(TDS.PlacedTowers, placedInstance)
    task.wait(0.3)
    return #TDS.PlacedTowers
end

function TDS:Upgrade(index, path)
    if not isInGame() then return end
    path = path or 1
    local tower = TDS.PlacedTowers[index]
    if tower then
        pcall(function()
            RemoteFunction:InvokeServer("Troops", "Upgrade", "Set", {
                ["Troop"] = tower,
                ["Path"] = path
            })
        end)
    end
    task.wait(0.25)
end

function TDS:Sell(index)
    if not isInGame() then return end
    local tower = TDS.PlacedTowers[index]
    if tower then
        pcall(function()
            RemoteFunction:InvokeServer("Troops", "Sell", {
                ["Troop"] = tower
            })
        end)
    end
    task.wait(0.2)
end

shared.TDSTable = TDS
return TDS
