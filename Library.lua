-- MakaraHub Bağımsız TDS Çekirdeği (New Play Button & Matchmaking)
local TDS = {}
TDS.PlacedTowers = {}
TDS.TargetMap = ""
TDS.CurrentMode = "Easy"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local LOBBY_PLACE_ID = 3260590327
local isLobby = (game.PlaceId == LOBBY_PLACE_ID)

local RemoteFunction = ReplicatedStorage:WaitForChild("RemoteFunction", 15)
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent", 15)

---------------------------------------------------------
-- 1. YENİ "PLAY" BUTONU İLE ANINDA MAÇ BAŞLATMA
---------------------------------------------------------
local function fastPlayMatch(targetMap, targetMode)
    print("[MakaraHub] Play menüsü üzerinden maç başlatılıyor: " .. tostring(targetMap))

    -- 1. Yöntem: Yeni Play butonu Matchmaking remote çağrıları
    pcall(function()
        RemoteFunction:InvokeServer("Matchmaking", "Create", {
            ["Map"] = targetMap,
            ["Difficulty"] = targetMode or "Easy"
        })
    end)
    
    pcall(function()
        RemoteFunction:InvokeServer("Matchmaking", "StartMatch")
    end)

    -- 2. Yöntem: Standart Hızlı Oyun / Solo Asansör Remote'u
    pcall(function()
        RemoteFunction:InvokeServer("Elevators", "JoinCustom", {
            ["Map"] = targetMap,
            ["Difficulty"] = targetMode or "Easy",
            ["Solo"] = true
        })
    end)

    -- Maça ışınlanana kadar alt satırlara (kule dizilimine) geçilmesini engelle
    while isLobby do
        task.wait(0.5)
    end
end

---------------------------------------------------------
-- 2. DALGA VE OYUN VERİSİ TAKİPÇİSİ
---------------------------------------------------------
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

function TDS:WaitForWave(targetWave)
    if isLobby then return end
    while getCurrentWave() < targetWave do
        task.wait(0.5)
    end
end

---------------------------------------------------------
-- 3. MAKRO KOMUTLARI
---------------------------------------------------------
function TDS:GameInfo(mapName, modifiers)
    TDS.TargetMap = mapName
    if isLobby then
        fastPlayMatch(mapName, TDS.CurrentMode)
    end
end

function TDS:Loadout(...)
    local towers = {...}
    pcall(function()
        RemoteFunction:InvokeServer("Troops", "Loadout", "Set", towers)
    end)
    task.wait(0.5)
end

function TDS:Mode(modeName, code)
    TDS.CurrentMode = modeName
    if not isLobby then
        pcall(function()
            RemoteFunction:InvokeServer("Difficulty", "Vote", modeName)
        end)
    end
    task.wait(0.5)
end

function TDS:Ready()
    if isLobby then return end
    pcall(function()
        RemoteFunction:InvokeServer("Team", "Ready")
    end)
    task.wait(0.5)
end

function TDS:VoteSkip(startWave, endWave)
    if isLobby then return end
    pcall(function()
        RemoteFunction:InvokeServer("Voting", "Skip")
    end)
    task.wait(0.3)
end

function TDS:Place(towerName, x, y, z, stack)
    if isLobby then return end
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
    if isLobby then return end
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
    if isLobby then return end
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
