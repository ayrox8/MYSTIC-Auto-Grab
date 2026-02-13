local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local function getInternalTable()
    local Packages = ReplicatedStorage:FindFirstChild("Packages")
    if not Packages then return nil end
    
    local SynchronizerModule = Packages:FindFirstChild("Synchronizer")
    if not SynchronizerModule then return nil end
    
    local success, synchronizer = pcall(require, SynchronizerModule)
    if not success or not synchronizer then return nil end
    
    local GetMethod = synchronizer.Get
    if type(GetMethod) ~= "function" then
        return nil
    end
    
    for i = 1, 5 do
        local success, upvalue = pcall(getupvalue, GetMethod, i)
        if success and type(upvalue) == "table" then
            if upvalue.___private or upvalue.___channels or upvalue.___data then
                return upvalue
            end
            
            for k, v in pairs(upvalue) do
                if type(k) == "string" and k:match("^Plot_") or type(v) == "table" then
                    return upvalue
                end
            end
        end
    end
    
    local success, env = pcall(getfenv, GetMethod)
    if success and env and env.self then
        return env.self
    end
    
    return nil
end

local SynchronizerInternal = {
    _cache = {},
    _dataTable = nil
}

task.spawn(function()
    local attempts = 0
    while attempts < 10 and not SynchronizerInternal._dataTable do
        SynchronizerInternal._dataTable = getInternalTable()
        if not SynchronizerInternal._dataTable then
            task.wait(1)
            attempts = attempts + 1
        end
    end
end)

local function stealthGet(plotName)
    if not plotName or type(plotName) ~= "string" then
        return nil
    end
    
    if SynchronizerInternal._cache[plotName] == false then
        return nil
    end
    
    if SynchronizerInternal._dataTable then
        local keys = {
            plotName,
            "Plot_" .. plotName,
            "Plot" .. plotName,
            plotName .. "_Channel",
            "Channel_" .. plotName
        }
        
        for _, key in ipairs(keys) do
            if SynchronizerInternal._dataTable[key] then
                SynchronizerInternal._cache[plotName] = SynchronizerInternal._dataTable[key]
                return SynchronizerInternal._dataTable[key]
            end
        end
        
        for k, v in pairs(SynchronizerInternal._dataTable) do
            if type(k) == "string" and (k == plotName or k:find(plotName, 1, true)) then
                if type(v) == "table" then
                    SynchronizerInternal._cache[plotName] = v
                    return v
                end
            end
        end
    end
    
    SynchronizerInternal._cache[plotName] = false
    return nil
end

local function stealthGetProperty(channel, property)
    if not channel or type(channel) ~= "table" then
        return nil
    end
    
    if channel[property] then
        return channel[property]
    end
    
    if type(channel.Get) == "function" then
        local success, result = pcall(channel.Get, channel, property)
        if success then
            return result
        end
    end
    
    local altNames = {
        Owner = {"owner", "Owner", "plotOwner", "PlotOwner"},
        AnimalList = {"animalList", "AnimalList", "animals", "Animals", "pets"}
    }
    
    if altNames[property] then
        for _, alt in ipairs(altNames[property]) do
            if channel[alt] then
                return channel[alt]
            end
        end
    end
    
    return nil
end

local autoStealEnabled = true
local selectedTargetIndex = 1
local currentStealProgress = 0
local isCurrentlyStealing = false

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Datas = ReplicatedStorage:WaitForChild("Datas")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Utils = ReplicatedStorage:WaitForChild("Utils")

local AnimalsData, AnimalsShared, NumberUtils
task.spawn(function()
    for i = 1, 10 do
        local success1, data = pcall(require, Datas:WaitForChild("Animals"))
        local success2, shared = pcall(require, Shared:WaitForChild("Animals"))
        local success3, utils = pcall(require, Utils:WaitForChild("NumberUtils"))
        
        if success1 and data then
            AnimalsData = data
        end
        if success2 and shared then
            AnimalsShared = shared
        end
        if success3 and utils then
            NumberUtils = utils
        end
        
        if AnimalsData and AnimalsShared and NumberUtils then
            break
        end
        task.wait(0.5)
    end
end)

local allAnimalsCache = {}
local InternalStealCache = {}
local PromptMemoryCache = {}

local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then
        return false
    end
    
    local plots = workspace:FindFirstChild("Plots")
    if not plots then
        return false
    end
    
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then
        return false
    end
    
    local channel = stealthGet(plot.Name)
    if channel then
        local owner = stealthGetProperty(channel, "Owner")
        if owner then
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "table" and owner.UserId then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "Instance" then
                return owner == LocalPlayer
            end
        end
    end
    
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") then
            return yourBase.Enabled == true
        end
    end
    
    return false
end

local function get_top_3_pets()
    local topPets = {}
    
    for _, animalData in ipairs(allAnimalsCache) do
        if not isMyBaseAnimal(animalData) then
            table.insert(topPets, {
                petName = animalData.name or "Unknown",
                mpsText = animalData.genText or "$0/s",
                mpsValue = animalData.genValue or 0,
                owner = animalData.owner or "Unknown",
                plot = animalData.plot or "Unknown",
                slot = animalData.slot or "1",
                uid = animalData.uid or "",
                mutation = animalData.mutation or "None",
                animalData = animalData
            })
        end
        
        if #topPets >= 3 then
            break
        end
    end
    
    return topPets
end

local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    
    local cachedPrompt = PromptMemoryCache[animalData.uid]
    if cachedPrompt and cachedPrompt.Parent then
        return cachedPrompt
    end
    
    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    
    local base = podium:FindFirstChild("Base")
    if not base then return nil end
    
    local spawn = base:FindFirstChild("Spawn")
    if not spawn then return nil end
    
    local attach = spawn:FindFirstChild("PromptAttachment")
    if not attach then return nil end
    
    for _, p in ipairs(attach:GetChildren()) do
        if p:IsA("ProximityPrompt") then
            PromptMemoryCache[animalData.uid] = p
            return p
        end
    end
    
    return nil
end

local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then return end
    
    local data = {
        holdCallbacks = {},
        triggerCallbacks = {},
        ready = true,
    }
    
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1) == "table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function) == "function" then
                table.insert(data.holdCallbacks, conn.Function)
            end
        end
    end
    
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2) == "table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function) == "function" then
                table.insert(data.triggerCallbacks, conn.Function)
            end
        end
    end
    
    if (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0) then
        InternalStealCache[prompt] = data
    end
end

local function runCallbackList(list)
    for _, fn in ipairs(list) do
        task.spawn(fn)
    end
end

local function executeInternalStealAsync(prompt)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then return false end
    
    data.ready = false
    
    isCurrentlyStealing = true
    local startTime = tick()
    local stealDuration = 1.42
    
    task.spawn(function()
        if #data.holdCallbacks > 0 then
            runCallbackList(data.holdCallbacks)
        end
        
        while tick() - startTime < stealDuration do
            local progress = (tick() - startTime) / stealDuration
            currentStealProgress = math.clamp(progress * 100, 0, 100)
            task.wait(0.05)
        end
        
        if #data.triggerCallbacks > 0 then
            runCallbackList(data.triggerCallbacks)
        end
        
        task.wait()
        data.ready = true
        
        isCurrentlyStealing = false
        currentStealProgress = 0
    end)
    
    return true
end

local function attemptSteal(prompt)
    if not prompt or not prompt.Parent then
        return false
    end
    
    buildStealCallbacks(prompt)
    if not InternalStealCache[prompt] then
        return false
    end
    
    return executeInternalStealAsync(prompt)
end

local function prebuildStealCallbacks()
    for uid, prompt in pairs(PromptMemoryCache) do
        if prompt and prompt.Parent then
            buildStealCallbacks(prompt)
        end
    end
end

task.spawn(function()
    while task.wait(2) do
        if autoStealEnabled then
            prebuildStealCallbacks()
        end
    end
end)

local plotChannels = {}
local lastAnimalData = {}
local scannerConnections = {}

local function getAnimalHash(animalList)
    if not animalList then return "" end
    local hash = ""
    for slot, data in pairs(animalList) do
        if type(data) == "table" then
            hash = hash .. tostring(slot) .. tostring(data.Index) .. tostring(data.Mutation)
        end
    end
    return hash
end

local function scanSinglePlot(plot)
    pcall(function()        
        local plotUID = plot.Name
        local channel = stealthGet(plotUID)
        if not channel then return end
        
        local animalList = stealthGetProperty(channel, "AnimalList")
        local currentHash = getAnimalHash(animalList)
        if lastAnimalData[plotUID] == currentHash then
            return
        end
        lastAnimalData[plotUID] = currentHash
        
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == plot.Name then
                table.remove(allAnimalsCache, i)
            end
        end
        
        local owner = stealthGetProperty(channel, "Owner")
        if not owner or not Players:FindFirstChild(owner.Name) then
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                end
            end
            return
        end
        
        local ownerName = owner and owner.Name or "Unknown"
        if not animalList then return end
        
        for slot, animalData in pairs(animalList) do
            if type(animalData) == "table" then
                local animalName = animalData.Index
                local animalInfo = AnimalsData[animalName]
                if not animalInfo then continue end
                
                local mutation = animalData.Mutation or "None"
                local traits = (animalData.Traits and #animalData.Traits > 0) and table.concat(animalData.Traits, ", ") or "None"
                
                local genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
                local genText = "$" .. NumberUtils:ToString(genValue) .. "/s"
                
                table.insert(allAnimalsCache, {
                    name = animalInfo.DisplayName or animalName,
                    genText = genText,
                    genValue = genValue,
                    mutation = mutation,
                    traits = traits,
                    owner = ownerName,
                    plot = plot.Name,
                    slot = tostring(slot),
                    uid = plot.Name .. "_" .. tostring(slot),
                })
            end
        end
        
        table.sort(allAnimalsCache, function(a, b)
            return a.genValue > b.genValue
        end)
    end)
end

local function setupPlotListener(plot)
    if plotChannels[plot.Name] then return end
    
    local channel
    local retries = 0
    local maxRetries = 3
    
    while not channel and retries < maxRetries do
        channel = stealthGet(plot.Name)
        if channel then
            break
        else
            retries = retries + 1
            if retries < maxRetries then
                task.wait(0.3)
            end
        end
    end
    
    if not channel then return end
    plotChannels[plot.Name] = true
    
    scanSinglePlot(plot)
    
    local c1 = plot.DescendantAdded:Connect(function()
        task.wait(0.05)
        scanSinglePlot(plot)
    end)
    table.insert(scannerConnections, c1)
    
    local c2 = plot.DescendantRemoving:Connect(function()
        task.wait(0.05)
        scanSinglePlot(plot)
    end)
    table.insert(scannerConnections, c2)
    
    local c3 = task.spawn(function()
        while plot.Parent and plotChannels[plot.Name] do
            task.wait(3)
            scanSinglePlot(plot)
        end
    end)
    table.insert(scannerConnections, c3)
end

local function initializePlotScanner()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then
        for i = 1, 30 do
            plots = workspace:FindFirstChild("Plots")
            if plots then break end
            task.wait(0.5)
        end
        if not plots then
            return
        end
    end
    
    for _, plot in ipairs(plots:GetChildren()) do
        task.spawn(setupPlotListener, plot)
    end
    
    local newPlotConnection = plots.ChildAdded:Connect(function(plot)
        task.wait(0.2)
        task.spawn(setupPlotListener, plot)
    end)
    table.insert(scannerConnections, newPlotConnection)
    
    local removedPlotConnection = plots.ChildRemoved:Connect(function(plot)
        plotChannels[plot.Name] = nil
        lastAnimalData[plot.Name] = nil
        
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == plot.Name then
                table.remove(allAnimalsCache, i)
            end
        end
    end)
    table.insert(scannerConnections, removedPlotConnection)
end

-- GUI MYSTIC - Interface Violette Élégante
local screenGui, frame, statusLabel, targetLabel, petButtons, toggleButton, stealStatusLabel, progressBar, progressFill, progressText

local function createMysticGUI()
    if not PlayerGui then
        warn("PlayerGui non trouvé! Attente...")
        for i = 1, 30 do
            PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
            if PlayerGui then break end
            task.wait(0.5)
        end
        if not PlayerGui then
            warn("PlayerGui introuvable!")
            return false
        end
    end
    
    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end
    
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MysticAutoStealUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 100
    screenGui.IgnoreGuiInset = true
    
    local isMobile = UserInputService.TouchEnabled
    local frameWidth = isMobile and 280 or 300
    local frameHeight = isMobile and 240 or 260
    
    -- Frame principale avec effet de verre violet
    frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, frameWidth, 0, frameHeight)
    frame.Position = UDim2.new(0.5, -frameWidth/2, 0.05, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.BackgroundColor3 = Color3.fromRGB(15, 5, 25)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.ZIndex = 100
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    -- Bordure violette animée
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(138, 43, 226)
    stroke.Thickness = 3
    stroke.Transparency = 0
    stroke.Parent = frame
    
    

    -- Animation de la bordure
    task.spawn(function()
        while frame and frame.Parent do
            TweenService:Create(stroke, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                Color = Color3.fromRGB(186, 85, 211)
            }):Play()
            task.wait(2)
        end
    end)

    -- Permetaskre de glisser (PC seulement)
    if not isMobile then
        local dragging = false
        local dragInput, mousePos, framePos

        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                mousePos = input.Position
                framePos = frame.Position
                
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        frame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                dragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - mousePos
                frame.Position = UDim2.new(
                    framePos.X.Scale,
                    framePos.X.Offset + delta.X,
                    framePos.Y.Scale,
                    framePos.Y.Offset + delta.Y
                )
            end
        end)
    end

    -- En-tête avec logo MYSTIC
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 45)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundColor3 = Color3.fromRGB(25, 10, 40)
    header.BackgroundTransparency = 0.3
    header.BorderSizePixel = 0
    header.ZIndex = 101
    header.Parent = frame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header

    -- Titre MYSTIC avec effet brillant
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0.7, 0, 1, 0)
    titleLabel.Position = UDim2.new(0, 15, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "✨ MYSTIC"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = isMobile and 18 or 20
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 102
    titleLabel.Parent = header

    local titleGradient = Instance.new("UIGradient")
    titleGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(186, 85, 211)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(138, 43, 226)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(147, 112, 219))
    }
    titleGradient.Parent = titleLabel

    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.Size = UDim2.new(0.7, 0, 0, 15)
    subtitleLabel.Position = UDim2.new(0, 15, 0, 24)
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Text = "Auto Steal"
    subtitleLabel.Font = Enum.Font.Gotham
    subtitleLabel.TextSize = isMobile and 10 or 11
    subtitleLabel.TextColor3 = Color3.fromRGB(186, 85, 211)
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLabel.ZIndex = 102
    subtitleLabel.Parent = header

    -- Statut ON/OFF
    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0, 70, 0, 25)
    statusLabel.Position = UDim2.new(1, -85, 0, 10)
    statusLabel.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
    statusLabel.BackgroundTransparency = 0.2
    statusLabel.BorderSizePixel = 0
    statusLabel.Text = "ACTIF"
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = isMobile and 12 or 14
    statusLabel.TextColor3 = Color3.fromRGB(144, 238, 144)
    statusLabel.ZIndex = 102
    statusLabel.Parent = header
    
    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 6)
    statusCorner.Parent = statusLabel

    -- Cible actuelle
    targetLabel = Instance.new("TextLabel")
    targetLabel.Size = UDim2.new(1, -20, 0, 22)
    targetLabel.Position = UDim2.new(0, 10, 0, 55)
    targetLabel.BackgroundTransparency = 1
    targetLabel.Text = "🎯 Cible: Recherche..."
    targetLabel.Font = Enum.Font.GothamBold
    targetLabel.TextSize = isMobile and 11 or 12
    targetLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    targetLabel.TextXAlignment = Enum.TextXAlignment.Left
    targetLabel.TextTruncate = Enum.TextTruncate.AtEnd
    targetLabel.ZIndex = 101
    targetLabel.Parent = frame

    -- Statut de vol
    stealStatusLabel = Instance.new("TextLabel")
    stealStatusLabel.Size = UDim2.new(1, -20, 0, 18)
    stealStatusLabel.Position = UDim2.new(0, 10, 0, 80)
    stealStatusLabel.BackgroundTransparency = 1
    stealStatusLabel.Text = "⚡ Statut: Prêt"
    stealStatusLabel.Font = Enum.Font.GothamBold
    stealStatusLabel.TextSize = isMobile and 10 or 11
    stealStatusLabel.TextColor3 = Color3.fromRGB(144, 238, 144)
    stealStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    stealStatusLabel.ZIndex = 101
    stealStatusLabel.Parent = frame

    -- Barre de progression mystique
    progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(1, -20, 0, 14)
    progressBar.Position = UDim2.new(0, 10, 0, 102)
    progressBar.BackgroundColor3 = Color3.fromRGB(20, 10, 30)
    progressBar.BorderSizePixel = 0
    progressBar.ZIndex = 101
    progressBar.Parent = frame
    
    local progressBarCorner = Instance.new("UICorner")
    progressBarCorner.CornerRadius = UDim.new(0, 7)
    progressBarCorner.Parent = progressBar
    
    local progressBarStroke = Instance.new("UIStroke")
    progressBarStroke.Color = Color3.fromRGB(138, 43, 226)
    progressBarStroke.Thickness = 1
    progressBarStroke.Transparency = 0.5
    progressBarStroke.Parent = progressBar
    
    progressFill = Instance.new("Frame")
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.Position = UDim2.new(0, 0, 0, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
    progressFill.BorderSizePixel = 0
    progressFill.ZIndex = 102
    progressFill.Parent = progressBar
    
    local progressFillCorner = Instance.new("UICorner")
    progressFillCorner.CornerRadius = UDim.new(0, 7)
    progressFillCorner.Parent = progressFill
    
    -- Gradient animé pour la progression
    local progressGradient = Instance.new("UIGradient")
    progressGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(138, 43, 226)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(186, 85, 211)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(147, 112, 219))
    }
    progressGradient.Parent = progressFill
    
    progressText = Instance.new("TextLabel")
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.Position = UDim2.new(0, 0, 0, 0)
    progressText.BackgroundTransparency = 1
    progressText.Text = "0%"
    progressText.Font = Enum.Font.GothamBold
    progressText.TextSize = isMobile and 9 or 10
    progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressText.ZIndex = 103
    progressText.Parent = progressBar

    -- Séparateur
    local separator = Instance.new("Frame")
    separator.Size = UDim2.new(1, -20, 0, 1)
    separator.Position = UDim2.new(0, 10, 0, 125)
    separator.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
    separator.BackgroundTransparency = 0.5
    separator.BorderSizePixel = 0
    separator.ZIndex = 101
    separator.Parent = frame

    local top3Label = Instance.new("TextLabel")
    top3Label.Size = UDim2.new(1, -20, 0, 18)
    top3Label.Position = UDim2.new(0, 10, 0, 132)
    top3Label.BackgroundTransparency = 1
    top3Label.Text = "🔮 Sélection:"
    top3Label.Font = Enum.Font.GothamBold
    top3Label.TextSize = isMobile and 10 or 11
    top3Label.TextColor3 = Color3.fromRGB(186, 85, 211)
    top3Label.TextXAlignment = Enum.TextXAlignment.Left
    top3Label.ZIndex = 101
    top3Label.Parent = frame
    
    petButtons = {}
    
    local buttonHeight = isMobile and 28 or 30
    local buttonSpacing = isMobile and 32 or 34
    local startY = 155

    for i = 1, 3 do
        local petButton = Instance.new("TextButton")
        petButton.Size = UDim2.new(0, frameWidth - 20, 0, buttonHeight)
        petButton.Position = UDim2.new(0, 10, 0, startY + (i - 1) * buttonSpacing)
        petButton.BackgroundColor3 = Color3.fromRGB(25, 10, 40)
        petButton.BackgroundTransparency = 0.3
        petButton.BorderSizePixel = 0
        petButton.Text = string.format("🌟 #%d: En attente...", i)
        petButton.Font = Enum.Font.GothamBold
        petButton.TextSize = isMobile and 10 or 11
        petButton.TextColor3 = Color3.fromRGB(200, 180, 220)
        petButton.AutoButtonColor = false
        petButton.TextXAlignment = Enum.TextXAlignment.Left
        petButton.ZIndex = 101
        petButton.Parent = frame
        
        local petCorner = Instance.new("UICorner")
        petCorner.CornerRadius = UDim.new(0, 8)
        petCorner.Parent = petButton
        
        local petStroke = Instance.new("UIStroke")
        petStroke.Color = Color3.fromRGB(100, 50, 150)
        petStroke.Thickness = 1.5
        petStroke.Transparency = 0.5
        petStroke.Parent = petButton
        
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 8)
        padding.Parent = petButton
        
        -- Effet de brillance
        local shine = Instance.new("Frame")
        shine.Size = UDim2.new(0, 0, 1, 0)
        shine.Position = UDim2.new(0, 0, 0, 0)
        shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        shine.BackgroundTransparency = 0.9
        shine.BorderSizePixel = 0
        shine.ZIndex = 102
        shine.Parent = petButton
        
        local shineCorner = Instance.new("UICorner")
        shineCorner.CornerRadius = UDim.new(0, 8)
        shineCorner.Parent = shine
        
        petButtons[i] = {
            button = petButton,
            stroke = petStroke,
            shine = shine,
            index = i
        }
        
        if not isMobile then
            petButton.MouseEnter:Connect(function()
                if selectedTargetIndex ~= i then
                    TweenService:Create(petButton, TweenInfo.new(0.2), {
                        BackgroundTransparency = 0.1
                    }):Play()
                    TweenService:Create(petStroke, TweenInfo.new(0.2), {
                        Transparency = 0.3
                    }):Play()
                end
            end)
            
            petButton.MouseLeave:Connect(function()
                if selectedTargetIndex ~= i then
                    TweenService:Create(petButton, TweenInfo.new(0.2), {
                        BackgroundTransparency = 0.3
                    }):Play()
                    TweenService:Create(petStroke, TweenInfo.new(0.2), {
                        Transparency = 0.5
                    }):Play()
                end
            end)
        end
        
        petButton.MouseButton1Click:Connect(function()
            selectedTargetIndex = i
            
            for j, btn in ipairs(petButtons) do
                if j == selectedTargetIndex then
                    TweenService:Create(btn.button, TweenInfo.new(0.3), {
                        BackgroundColor3 = Color3.fromRGB(45, 20, 70)
                    }):Play()
                    btn.button.TextColor3 = Color3.fromRGB(144, 238, 144)
                    btn.stroke.Color = Color3.fromRGB(144, 238, 144)
                    btn.stroke.Transparency = 0.2
                    
                    -- Animation de brillance
                    TweenService:Create(btn.shine, TweenInfo.new(0.5), {
                        Size = UDim2.new(1, 0, 1, 0)
                    }):Play()
                else
                    TweenService:Create(btn.button, TweenInfo.new(0.3), {
                        BackgroundColor3 = Color3.fromRGB(25, 10, 40)
                    }):Play()
                    btn.button.TextColor3 = Color3.fromRGB(200, 180, 220)
                    btn.stroke.Color = Color3.fromRGB(100, 50, 150)
                    btn.stroke.Transparency = 0.5
                    
                    btn.shine.Size = UDim2.new(0, 0, 1, 0)
                end
            end
            
            local topPets = get_top_3_pets()
            if topPets[selectedTargetIndex] then
                local currentPet = topPets[selectedTargetIndex]
                targetLabel.Text = string.format("🎯 Cible: %s", currentPet.petName)
            else
                targetLabel.Text = "🎯 Cible: Aucune"
            end
        end)
    end

    -- Bouton Toggle élégant
    toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, frameWidth - 20, 0, 35)
    toggleButton.Position = UDim2.new(0, 10, 0, startY + 3 * buttonSpacing + 5)
    toggleButton.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
    toggleButton.BackgroundTransparency = 0.2
    toggleButton.BorderSizePixel = 0
    toggleButton.Text = "🚫 DÉSACTIVER"
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.TextSize = isMobile and 13 or 14
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.AutoButtonColor = false
    toggleButton.ZIndex = 101
    toggleButton.Parent = frame

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 10)
    buttonCorner.Parent = toggleButton

    local buttonGradient = Instance.new("UIGradient")
    buttonGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(138, 43, 226)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(186, 85, 211)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(147, 112, 219))
    }
    buttonGradient.Parent = toggleButton

    local buttonStroke = Instance.new("UIStroke")
    buttonStroke.Color = Color3.fromRGB(186, 85, 211)
    buttonStroke.Thickness = 2
    buttonStroke.Transparency = 0.3
    buttonStroke.Parent = toggleButton
    
    -- Initialisation des styles
    for i, btn in ipairs(petButtons) do
        if i == selectedTargetIndex then
            btn.button.BackgroundColor3 = Color3.fromRGB(45, 20, 70)
            btn.button.TextColor3 = Color3.fromRGB(144, 238, 144)
            btn.stroke.Color = Color3.fromRGB(144, 238, 144)
            btn.stroke.Transparency = 0.2
            btn.shine.Size = UDim2.new(1, 0, 1, 0)
        else
            btn.button.TextColor3 = Color3.fromRGB(200, 180, 220)
            btn.stroke.Color = Color3.fromRGB(100, 50, 150)
            btn.stroke.Transparency = 0.5
            btn.shine.Size = UDim2.new(0, 0, 1, 0)
        end
    end
    
    screenGui.Parent = PlayerGui
    
    -- Bouton de fermeture pour mobile
    if isMobile then
        local closeButton = Instance.new("TextButton")
        closeButton.Size = UDim2.new(0, 30, 0, 30)
        closeButton.Position = UDim2.new(1, -35, 0, 5)
        closeButton.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
        closeButton.BackgroundTransparency = 0.3
        closeButton.BorderSizePixel = 0
        closeButton.Text = "✕"
        closeButton.Font = Enum.Font.GothamBold
        closeButton.TextSize = 16
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.ZIndex = 103
        closeButton.Parent = header
        
        local closeCorner = Instance.new("UICorner")
        closeCorner.CornerRadius = UDim.new(0, 8)
        closeCorner.Parent = closeButton
        
        closeButton.MouseButton1Click:Connect(function()
            frame.Visible = not frame.Visible
            closeButton.Text = frame.Visible and "✕" or "◯"
        end)
    end
    
    return true
end

local function updateUI(enabled, topPets)
    if not statusLabel or not targetLabel or not toggleButton then
        return
    end
    
    autoStealEnabled = enabled
    
    if enabled then
        statusLabel.Text = "ACTIF"
        statusLabel.TextColor3 = Color3.fromRGB(144, 238, 144)
        statusLabel.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
        
        if frame and frame:FindFirstChild("UIStroke") then
            TweenService:Create(frame.UIStroke, TweenInfo.new(0.5), {
                Color = Color3.fromRGB(144, 238, 144)
            }):Play()
        end
        
        toggleButton.Text = "🚫 DÉSACTIVER"
        
        if topPets and type(topPets) == "table" and petButtons then
            for i = 1, 3 do
                if petButtons[i] and petButtons[i].button then
                    if topPets[i] then
                        local pet = topPets[i]
                        petButtons[i].button.Text = string.format("🌟 #%d: %s", i, pet.petName or "?")
                    else
                        petButtons[i].button.Text = string.format("🌟 #%d: Vide", i)
                    end
                end
            end
            
            if topPets[selectedTargetIndex] then
                local currentPet = topPets[selectedTargetIndex]
                targetLabel.Text = string.format("🎯 Cible: %s", currentPet.petName or "?")
            else
                targetLabel.Text = "🎯 Cible: Aucune"
            end
        else
            targetLabel.Text = "🎯 Cible: Recherche..."
            if petButtons then
                for i = 1, 3 do
                    if petButtons[i] and petButtons[i].button then
                        petButtons[i].button.Text = string.format("🌟 #%d: ...", i)
                    end
                end
            end
        end
    else
        statusLabel.Text = "INACTIF"
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        statusLabel.BackgroundColor3 = Color3.fromRGB(100, 30, 50)
        
        if frame and frame:FindFirstChild("UIStroke") then
            TweenService:Create(frame.UIStroke, TweenInfo.new(0.5), {
                Color = Color3.fromRGB(138, 43, 226)
            }):Play()
        end
        
        toggleButton.Text = "▶️ ACTIVER"
        targetLabel.Text = "🎯 Cible: Désactivé"
        
        if petButtons then
            for i = 1, 3 do
                if petButtons[i] and petButtons[i].button then
                    petButtons[i].button.Text = string.format("🌟 #%d: Off", i)
                    petButtons[i].button.TextColor3 = Color3.fromRGB(150, 130, 160)
                end
            end
        end
    end
end

local function updateStealStatus()
    if not stealStatusLabel or not progressFill or not progressText then
        return
    end
    
    if isCurrentlyStealing then
        stealStatusLabel.Text = "⚡ Statut: En cours..."
        stealStatusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        
        local fillWidth = math.clamp(currentStealProgress, 0, 100)
        TweenService:Create(progressFill, TweenInfo.new(0.1), {
            Size = UDim2.new(fillWidth / 100, 0, 1, 0)
        }):Play()
        progressText.Text = string.format("%.0f%%", fillWidth)
        
        if fillWidth < 30 then
            progressFill.BackgroundColor3 = Color3.fromRGB(186, 85, 211)
        elseif fillWidth < 70 then
            progressFill.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
        else
            progressFill.BackgroundColor3 = Color3.fromRGB(144, 238, 144)
        end
    else
        stealStatusLabel.Text = "⚡ Statut: Prêt"
        stealStatusLabel.TextColor3 = Color3.fromRGB(144, 238, 144)
        
        TweenService:Create(progressFill, TweenInfo.new(0.3), {
            Size = UDim2.new(0, 0, 1, 0)
        }):Play()
        progressText.Text = "0%"
        progressFill.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
    end
end

local stealConnection = nil

local function autoStealLoop()
    if stealConnection then
        stealConnection:Disconnect()
    end
    
    stealConnection = RunService.Heartbeat:Connect(function()
        if not autoStealEnabled then
            return
        end
        
        local topPets = get_top_3_pets()
        
        local targetAnimal = nil
        if topPets[selectedTargetIndex] then
            targetAnimal = topPets[selectedTargetIndex].animalData
        end
        
        if not targetAnimal or isMyBaseAnimal(targetAnimal) then
            return
        end
        
        local prompt = PromptMemoryCache[targetAnimal.uid]
        if not prompt or not prompt.Parent then
            prompt = findProximityPromptForAnimal(targetAnimal)
        end
        
        if prompt then
            attemptSteal(prompt)
        end
        
        updateStealStatus()
    end)
end

-- Initialisation principale
task.spawn(function()
    print("🔮 MYSTIC Auto Steal - Chargement...")
    
    while not AnimalsData or not AnimalsShared or not NumberUtils do
        task.wait(0.5)
    end
    
    print("✨ Modules chargés, création de l'interface MYSTIC...")
    
    task.wait(2)
    
    local guiCreated = createMysticGUI()
    if not guiCreated then
        warn("❌ Échec de création du GUI MYSTIC!")
        return
    end
    
    print("💜 Interface MYSTIC créée avec succès!")
    
    if toggleButton then
        local isMobile = UserInputService.TouchEnabled
        
        if not isMobile then
            toggleButton.MouseEnter:Connect(function()
                TweenService:Create(toggleButton, TweenInfo.new(0.2), {
                    BackgroundTransparency = 0
                }):Play()
            end)

            toggleButton.MouseLeave:Connect(function()
                TweenService:Create(toggleButton, TweenInfo.new(0.2), {
                    BackgroundTransparency = 0.2
                }):Play()
            end)
        end

        toggleButton.MouseButton1Click:Connect(function()
            autoStealEnabled = not autoStealEnabled
            
            if autoStealEnabled then
                local topPets = get_top_3_pets()
                updateUI(true, topPets)
                autoStealLoop()
            else
                updateUI(false)
                isCurrentlyStealing = false
                currentStealProgress = 0
                updateStealStatus()
            end
        end)
    end
    
    print("🔍 Initialisation du scanner...")
    initializePlotScanner()
    
    task.wait(1)
    autoStealLoop()
    
    local topPets = get_top_3_pets()
    updateUI(true, topPets)
    
    print("🎯 MYSTIC Auto Steal actif!")
    
    while task.wait(0.1) do
        if autoStealEnabled then
            local topPets = get_top_3_pets()
            updateUI(true, topPets)
            updateStealStatus()
        end
    end
end)

print("🔮✨ MYSTIC Auto Steal chargé - Interface violette mystique activée! ✨🔮")
