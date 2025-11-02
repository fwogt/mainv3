--[[
    demonhub | Bubble Gum Simulator
    + RIFTS: SCAN 0.1s + CLEANUP + HATCH OPTIMIZED
    by sskint | Modified Nov 02, 2025 (updates: rift scan 0.1s, optimized multi-hatch)
--]]

--// Load Rayfield ---------------------------------------------------------
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

--// Services ---------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")
local HttpService       = game:GetService("HttpService")

--// Remotes ---------------------------------------------------------------
local RemoteEvent = ReplicatedStorage:WaitForChild("Shared")
    :WaitForChild("Framework"):WaitForChild("Network")
    :WaitForChild("Remote"):WaitForChild("RemoteEvent")

local RemoteFunction = ReplicatedStorage:WaitForChild("Shared")
    :WaitForChild("Framework"):WaitForChild("Network")
    :WaitForChild("Remote"):WaitForChild("RemoteFunction")

local SpawnPickups     = ReplicatedStorage:WaitForChild("Remotes")
    :WaitForChild("Pickups"):WaitForChild("SpawnPickups")
local CollectPickup    = ReplicatedStorage:WaitForChild("Remotes")
    :WaitForChild("Pickups"):WaitForChild("CollectPickup")

--// Rayfield Window -------------------------------------------------------
local Window = Rayfield:CreateWindow({
    Name = "demonhub",
    LoadingTitle = "demonhub",
    LoadingSubtitle = "sskint",
    ConfigurationSaving = { Enabled = true, FolderName = "demonhub" }
})

-- (omitted unchanged parts...) 
-- keep the rest of your script up until the AUTOMATION tab unchanged

--// AUTO HATCH: MULTI-SELECT (UPDATED / OPTIMIZED)
local selectedHatchEggs = {}
local hatchAmount = 1
local autoHatchEnabled = false

-- New: interval between each single hatch send (seconds)
local hatchSendInterval = 0.1   -- default 0.1s between each single egg send
local hatchBatchDelay = 0.1     -- delay after finishing a full pass of selected eggs

AutoTab:CreateDropdown({
    Name = "Select Eggs to Auto Hatch",
    Options = eggList,
    CurrentOption = {},
    MultipleOptions = true,
    Callback = function(selected)
        selectedHatchEggs = selected
        Rayfield:Notify({Title="Auto Hatch", Content="Selected: "..(#selected>0 and table.concat(selected, ", ") or "None"), Duration=3})
    end
})

AutoTab:CreateSlider({
    Name = "Hatch Amount",
    Range = {1,15},
    Increment = 1,
    CurrentValue = hatchAmount,
    Callback = function(v) hatchAmount = v end
})

-- New UI: configure per-egg send interval in ms
AutoTab:CreateSlider({
    Name = "Per-Egg Send Interval (ms)",
    Range = {10,500},
    Increment = 10,
    CurrentValue = math.floor(hatchSendInterval*1000),
    Callback = function(v) hatchSendInterval = v/1000 end
})

-- New UI: configure batch delay (after one full pass through selected eggs)
AutoTab:CreateSlider({
    Name = "Delay After Full Pass (ms)",
    Range = {0,1000},
    Increment = 10,
    CurrentValue = math.floor(hatchBatchDelay*1000),
    Callback = function(v) hatchBatchDelay = v/1000 end
})

-- Optimized auto-hatch logic:
-- * Sends each egg one-by-one with hatchSendInterval between sends
-- * If hatchAmount > 1, it will send that many single sends per egg (so it's consistent and won't freeze)
-- * Uses pcall around FireServer to avoid breaking loop on unexpected errors
AutoTab:CreateToggle({
    Name = "Auto Hatch (Multi)",
    CurrentValue = false,
    Callback = function(v)
        autoHatchEnabled = v
        if v and #selectedHatchEggs == 0 then
            Rayfield:Notify({Title="Error", Content="Select at least one egg!", Duration=3})
            autoHatchEnabled = false
            return
        end
        if v then
            task.spawn(function()
                -- continuous loop; respects updated selectedHatchEggs, hatchAmount, and intervals
                while autoHatchEnabled do
                    -- iterate over the selected eggs
                    for _, egg in ipairs(selectedHatchEggs) do
                        if not autoHatchEnabled then break end
                        -- send hatchAmount single-hatch requests for this egg
                        for i = 1, hatchAmount do
                            if not autoHatchEnabled then break end
                            -- Use pcall to avoid any FireServer error stopping the loop
                            pcall(function()
                                RemoteEvent:FireServer("HatchEgg", egg, 1) -- send 1 at a time for smoothness
                            end)
                            -- wait the per-egg send interval to avoid spike
                            task.wait(hatchSendInterval)
                        end
                        -- small micro-yield to let UI/higher-priority tasks run
                        task.wait(0)
                    end
                    -- full-pass delay before starting again
                    task.wait(hatchBatchDelay)
                end
            end)
            Rayfield:Notify({Title="Auto Hatch ON", Content="Hatching "..#selectedHatchEggs.." eggs x"..hatchAmount.." (interval "..(hatchSendInterval*1000).."ms)", Duration=4})
        else
            Rayfield:Notify({Title="Auto Hatch OFF", Content="Stopped", Duration=2})
        end
    end
})

-- (rest of Automation tab and other UI remains unchanged until Rifts Tab)

--// ====================== RIFTS TAB – IMPROVED SCAN & CLEANUP ======================
local RiftTab = Window:CreateTab("Rifts")

--// --- SCRIPT VARIABLES ---
local autoTPEnabled = false
local currentTargetRift = nil
local teleportDistanceThreshold = 5
local prioritizedRifts = {}
local RiftLabels = {}
local luckThreshold = 100
local returnOnDisable = true
local originalPosition = nil

--// Rift Name Mapping
local RiftNameMap = {
    ["event-1"] = "Pumpkin Egg",
    ["event-2"] = "Costume Egg",
    ["event-3"] = "Sinister Egg",
    ["event-4"] = "Mutant Egg",
    ["event-5"] = "Puppet Egg"
}

-- Build dropdown options
local priorityOptions = {}
for _, friendlyName in pairs(RiftNameMap) do
    table.insert(priorityOptions, friendlyName)
end

--// --- UI ELEMENTS ---
RiftTab:CreateToggle({
    Name = "Auto TP to Rift",
    CurrentValue = false,
    Flag = "AutoTP",
    Callback = function(val)
        autoTPEnabled = val
        
        if val and LocalPlayer.Character then
            local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                originalPosition = root.CFrame
                Rayfield:Notify({Title="Rift Scanner", Content="Position saved!", Duration=2})
            end
        elseif not val and returnOnDisable and originalPosition then
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = originalPosition
                Rayfield:Notify({Title="Rift Scanner", Content="Returned to start!", Duration=2})
            end
            currentTargetRift = nil
        end
    end
})

-- MIN LUCK THRESHOLD INPUT
local luckInput
luckInput = RiftTab:CreateInput({
    Name = "Min Luck Threshold (x)",
    PlaceholderText = "e.g. 100",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
        local num = tonumber(text)
        if num and num >= 1 then
            luckThreshold = num
            if luckInput then luckInput:Set(tostring(num)) end
            Rayfield:Notify({Title="Luck Threshold", Content="Set to "..num.."x", Duration=2})
        else
            if luckInput then luckInput:Set(tostring(luckThreshold)) end
            Rayfield:Notify({Title="Invalid", Content="Enter number ≥1", Duration=2})
        end
    end
})
luckInput:Set("100")

RiftTab:CreateToggle({
    Name = "Return to Start When Disabled",
    CurrentValue = true,
    Callback = function(v) returnOnDisable = v end
})

RiftTab:CreateDropdown({
    Name = "Prioritize Rifts",
    Options = priorityOptions,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "PriorityDropdownMulti",
    Callback = function(selectedOptions)
        prioritizedRifts = selectedOptions
    end,
})

local CurrentTargetLabel = RiftTab:CreateLabel("Current Target: None")

--// --- FIXED LUCK READER (unchanged) ---
local function getLuckFromRift(rift)
    if not rift or not rift.Parent then return nil end
    local luckObj = rift:FindFirstChild("Display")
                 and rift.Display:FindFirstChild("SurfaceGui")
                 and rift.Display.SurfaceGui:FindFirstChild("Icon")
                 and rift.Display.SurfaceGui.Icon:FindFirstChild("Luck")
    if not luckObj then return nil end

    if luckObj:IsA("TextLabel") then
        local text = luckObj.Text:gsub("[^%d%.]", "")
        return tonumber(text) or 0
    elseif luckObj:IsA("NumberValue") then
        return luckObj.Value
    elseif luckObj:IsA("StringValue") then
        return tonumber(luckObj.Value) or 0
    end
    return 0
end

-- Get Rift Spawn CFrame
local function getRiftSpawnCFrame(rift)
    if not rift or not rift.Parent then return nil end
    local spawn = rift:FindFirstChild("EggPlatformSpawn")
    if not spawn then return nil end

    if spawn:IsA("BasePart") then
        return spawn.CFrame
    elseif spawn:IsA("Model") then
        if spawn.PrimaryPart then
            return spawn.PrimaryPart.CFrame
        else
            local firstPart = spawn:FindFirstChildWhichIsA("BasePart", true)
            if firstPart then return firstPart.CFrame end
        end
    end
    return nil
end

-- Teleport to Rift
local function teleportToRift(rift)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local targetCF = getRiftSpawnCFrame(rift)
    if targetCF then
        root.CFrame = targetCF + Vector3.new(0, 3, 0)
        return true
    end
    return false
end

local function isRiftStillAlive(rift)
    return rift and rift.Parent and rift.Parent.Parent
end

--// --- MAIN REFRESH LOOP (IMPROVED - runs every 0.1s) ---
local function refreshRifts()
    local rendered = Workspace:FindFirstChild("Rendered")
    local riftsFolder = rendered and rendered:FindFirstChild("Rifts")
    
    if not riftsFolder then
        CurrentTargetLabel:Set("Current Target: No Rifts Folder")
        -- cleanup cached labels if any (clear table)
        for k, v in pairs(RiftLabels) do
            -- safe attempt to clear UI text so labels don't show stale data
            pcall(function() if v.label and v.label.Set then v.label:Set("") end end)
            RiftLabels[k] = nil
        end
        return
    end

    -- CLEANUP DEAD RIFTS FIRST (remove missing models from tracking table)
    for name, info in pairs(RiftLabels) do
        if not riftsFolder:FindFirstChild(name) then
            -- clear UI label string if possible
            pcall(function() if info.label and info.label.Set then info.label:Set("") end end)
            RiftLabels[name] = nil
        end
    end

    -- choose best rifts each scan
    local bestLuckOverall   = -math.huge
    local bestRiftOverall   = nil
    local bestPriorityLuck  = -math.huge
    local bestPriorityRift  = nil

    -- SCAN ALL RIFTS
    local children = riftsFolder:GetChildren()
    for _, rift in ipairs(children) do
        local originalName = rift.Name
        local displayName = RiftNameMap[originalName]

        -- ONLY SHOW EVENT RIFTS
        if not displayName then continue end

        local luck = getLuckFromRift(rift) or 0
        local luckNum = luck

        -- CREATE OR UPDATE LABEL (create once; update text each scan)
        if not RiftLabels[originalName] then
            local ok, label = pcall(function()
                return RiftTab:CreateLabel(displayName .. " | Luck: " .. luckNum .. "x")
            end)
            if ok and label then
                RiftLabels[originalName] = {
                    label = label,
                    model = rift
                }
                -- also create a TP button just once
                pcall(function()
                    RiftTab:CreateButton({
                        Name = "TP to " .. displayName,
                        Callback = function() teleportToRift(rift) end
                    })
                end)
            else
                -- fallback: store minimal info
                RiftLabels[originalName] = { label = nil, model = rift }
            end
        else
            -- update label safely (use pcall because UI object might not fully support :Set)
            pcall(function()
                if RiftLabels[originalName].label and RiftLabels[originalName].label.Set then
                    RiftLabels[originalName].label:Set(displayName .. " | Luck: " .. luckNum .. "x")
                end
            end)
            RiftLabels[originalName].model = rift
        end

        -- ONLY TARGET IF ABOVE THRESHOLD
        if luckNum < luckThreshold then continue end

        -- TRACK BEST OVERALL
        if luckNum > bestLuckOverall then
            bestLuckOverall = luckNum
            bestRiftOverall = rift
        end

        -- TRACK BEST PRIORITIZED
        for _, priName in ipairs(prioritizedRifts) do
            if displayName == priName and luckNum > bestPriorityLuck then
                bestPriorityLuck = luckNum
                bestPriorityRift = rift
            end
        end
    end

    -- AUTO TP LOGIC
    if not autoTPEnabled then
        CurrentTargetLabel:Set("Current Target: (Auto TP Disabled)")
        return
    end

    local finalTarget = nil

    if currentTargetRift and isRiftStillAlive(currentTargetRift) then
        local currentLuck = getLuckFromRift(currentTargetRift) or 0
        if currentLuck < luckThreshold then
            currentTargetRift = nil
        else
            local candidateRift = (#prioritizedRifts > 0 and bestPriorityRift) or bestRiftOverall
            local candidateLuck = candidateRift and (getLuckFromRift(candidateRift) or 0) or -math.huge
            if candidateLuck > currentLuck then
                finalTarget = candidateRift
            else
                finalTarget = currentTargetRift
            end
        end
    else
        if #prioritizedRifts > 0 and bestPriorityRift then
            finalTarget = bestPriorityRift
        elseif bestRiftOverall then
            finalTarget = bestRiftOverall
        end
    end

    if not finalTarget or (getLuckFromRift(finalTarget) or 0) < luckThreshold then
        currentTargetRift = nil
        CurrentTargetLabel:Set("Current Target: None (Below Threshold)")
        if returnOnDisable and originalPosition then
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then root.CFrame = originalPosition end
        end
        return
    end

    if currentTargetRift ~= finalTarget then
        currentTargetRift = finalTarget
    end

    local displayName = RiftNameMap[finalTarget.Name] or finalTarget.Name
    local luckVal = getLuckFromRift(finalTarget) or "?"
    CurrentTargetLabel:Set("Current Target: " .. displayName .. " (" .. luckVal .. "x Luck)")

    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local targetCF = getRiftSpawnCFrame(finalTarget)
    if not targetCF then return end

    local distance = (root.Position - targetCF.Position).Magnitude
    if distance > teleportDistanceThreshold then
        teleportToRift(finalTarget)
    end
end

--// Continuous Update Loop (now 0.1s scan)
task.spawn(function()
    while true do
        local ok, err = pcall(refreshRifts)
        if not ok then
            -- if an error occurs, notify once and keep going; avoids loop break
            warn("refreshRifts error:", err)
        end
        task.wait(0.1)
    end
end)

-- Handle respawn
LocalPlayer.CharacterAdded:Connect(function(newChar)
    task.wait(1)
    if autoTPEnabled and originalPosition then
        local root = newChar:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame = originalPosition end
    end
end)

--// Load Notify
Rayfield:Notify({ Title = "Rift Scanner", Content = "RIFTS SCAN 0.1s + HATCH OPTIMIZED!", Duration=6 })

-- (rest of the file remains unchanged)
