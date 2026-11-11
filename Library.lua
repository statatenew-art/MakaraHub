-- MakaraHub Bağımsız TDS Motoru (Library.lua)
local TDS = {}
TDS.PlacedTowers = {}
TDS.TargetMap = ""
TDS.CurrentMode = "Normal"

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
-- LOBİ ASANSÖR YÖNETİMİ
---------------------------------------------------------
local function joinElevator(targetMap)
    local elevators = Workspace:WaitForChild("Elevators", 15)
    if not elevators then return end

    local joined = false
    while not joined do
        for _, el in ipairs(elevators:GetChildren()) do
            local mapVal = el:FindFirstChild("Map") or (el:FindFirstChild("State") and el.State:FindFirstChild("Map"))
            local plrsVal = el:FindFirstChild("Players") or (el:FindFirstChild("State") and el.State:FindFirstChild("Players"))

            if mapVal and plrsVal and string.lower(mapVal.Value) == string.lower(targetMap) and plrsVal.Value < 4 then
                local zone = el:FindFirstChild("Zone") or el:FindFirstChildWhichIsA("BasePart")
                local char = LocalPlayer.Character
                if zone and char and char:FindFirstChild("HumanoidRootPart") then
                    char.HumanoidRootPart.CFrame = zone.CFrame + Vector3.new(0, 3, 0)
                    joined = true
                    break
                end
            end
        end
        if not joined then task.wait(1.5) end
    end
end

---------------------------------------------------------
-- TEMEL MAKRO API METODLARI
---------------------------------------------------------
function TDS:GameInfo(mapName, modifiers)
    TDS.TargetMap = mapName
    if isLobby then
        task.spawn(function() joinElevator(mapName) end)
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
    if isLobby then return end
    TDS.CurrentMode = modeName
    pcall(function()
        RemoteFunction:InvokeServer("Difficulty", "Vote", modeName)
    end)
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

function TDS:Place(towerName, x, y, z, ...)
    if isLobby then return end
    local pos = Vector3.new(x, y, z)
    local rot = CFrame.Angles(0, 0, 0)

    local placedInstance = nil
    pcall(function()
        placedInstance = RemoteFunction:InvokeServer("Troops", "Place", towerName, {
            ["Position"] = pos,
            ["Rotation"] = rot
        })
    end)

    if not placedInstance then
        local towers = Workspace:FindFirstChild("Towers") or Workspace:FindFirstChild("Troops")
        if towers then
            local myT = {}
            for _, tr in ipairs(towers:GetChildren()) do
                local rep = tr:FindFirstChild("TowerReplicator")
                if (rep and rep:GetAttribute("OwnerId") == LocalPlayer.UserId) or (tr:FindFirstChild("Owner") and tr.Owner.Value == LocalPlayer.UserId) then
                    table.insert(myT, tr)
                end
            end
            placedInstance = myT[#myT]
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
    task.wait(0.2)
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

function TDS:SetTarget(index, mode)
    if isLobby then return end
    local tower = TDS.PlacedTowers[index]
    if tower then
        pcall(function()
            RemoteFunction:InvokeServer("Troops", "Target", "Set", {
                ["Troop"] = tower,
                ["Target"] = mode
            })
        end)
    end
    task.wait(0.2)
end

function TDS:Ability(index, abilityName, dataTable, loop)
    if isLobby then return end
    local tower = TDS.PlacedTowers[index]
    if tower then
        local payload = {
            ["Troop"] = tower,
            ["Name"] = abilityName,
            ["Data"] = dataTable or {}
        }
        if loop then
            task.spawn(function()
                while tower and tower.Parent and getgenv().AutoStrat do
                    pcall(function()
                        RemoteFunction:InvokeServer("Troops", "Abilities", "Activate", payload)
                    end)
                    task.wait(1)
                end
            end)
        else
            pcall(function()
                RemoteFunction:InvokeServer("Troops", "Abilities", "Activate", payload)
            end)
        end
    end
end

shared.TDSTable = TDS
return TDS
