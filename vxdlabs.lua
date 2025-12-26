-- CLIENT SCRIPT (StarterPlayerScripts/OutfitClient)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 1. Wait for the RemoteEvents to exist
local outfitRemote = ReplicatedStorage:WaitForChild("RequestOutfitChange")
local responseRemote = ReplicatedStorage:WaitForChild("OutfitResponse")

-- 2. Create a Simple GUI for testing
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OutfitChangerGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 150)
frame.Position = UDim2.new(0, 20, 0.5, -75)
frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
frame.Parent = screenGui

local idInput = Instance.new("TextBox")
idInput.Size = UDim2.new(0.9, 0, 0, 40)
idInput.Position = UDim2.new(0.05, 0, 0.1, 0)
idInput.PlaceholderText = "Asset ID (Number)"
idInput.Text = ""
idInput.Parent = frame

local typeInput = Instance.new("TextBox")
typeInput.Size = UDim2.new(0.9, 0, 0, 40)
typeInput.Position = UDim2.new(0.05, 0, 0.4, 0)
typeInput.PlaceholderText = "Type (Shirt/Pants/Face)"
typeInput.Text = ""
typeInput.Parent = frame

local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(0.9, 0, 0, 40)
applyBtn.Position = UDim2.new(0.05, 0, 0.7, 0)
applyBtn.Text = "Send to Server"
applyBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
applyBtn.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel.Position = UDim2.new(0, 0, 1, -20)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.Text = ""
statusLabel.TextScaled = true
statusLabel.Parent = frame

-- Rate limiting variables
local lastRequestTime = 0
local requestCooldown = 1 -- 1 second cooldown

-- 3. Function to Fire the Remote
applyBtn.MouseButton1Click:Connect(function()
    local currentTime = tick()
    if currentTime - lastRequestTime < requestCooldown then
        statusLabel.Text = "Please wait before sending another request"
        return
    end
    
    local id = tonumber(idInput.Text)
    local clothingType = typeInput.Text
    
    -- Validate clothing type
    local validTypes = {Shirt = true, Pants = true, Face = true}
    if not validTypes[clothingType] then
        statusLabel.Text = "Invalid clothing type"
        return
    end

    if id and clothingType then
        print("Sending request to server...")
        statusLabel.Text = "Sending request..."
        lastRequestTime = currentTime
        -- FIRE SERVER: This sends the data across the boundary
        outfitRemote:FireServer(id, clothingType)
    else
        statusLabel.Text = "Please enter valid ID and Type"
    end
end)

-- Handle server responses
responseRemote.OnClientEvent:Connect(function(success, message)
    statusLabel.Text = message
    if success then
        print("Outfit changed successfully: " .. message)
    else
        warn("Failed to change outfit: " .. message)
    end
end)

-- SERVER SCRIPT (ServerScriptService/OutfitHandler)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- 1. Create the RemoteEvents automatically
local remoteName = "RequestOutfitChange"
local responseName = "OutfitResponse"
local outfitRemote = ReplicatedStorage:FindFirstChild(remoteName)
local responseRemote = ReplicatedStorage:FindFirstChild(responseName)

if not outfitRemote then
    outfitRemote = Instance.new("RemoteEvent")
    outfitRemote.Name = remoteName
    outfitRemote.Parent = ReplicatedStorage
end

if not responseRemote then
    responseRemote = Instance.new("RemoteEvent")
    responseRemote.Name = responseName
    responseRemote.Parent = ReplicatedStorage
end

-- Rate limiting storage
local playerRequestTimes = {}
local requestCooldown = 1 -- 1 second cooldown

-- Premium-only items (example IDs)
local premiumOnlyItems = {
    [123456789] = true,  -- Example premium shirt
    [987654321] = true   -- Example premium pants
}

-- Valid clothing types
local validClothingTypes = {
    Shirt = true,  
    Pants = true,  
    Face = true
}

-- 2. Function to handle the request
local function onChangeRequest(player, assetId, assetType)
    -- Rate limiting check
    local currentTime = tick()
    local lastTime = playerRequestTimes[player.UserId] or 0
    if currentTime - lastTime < requestCooldown then
        responseRemote:FireClient(player, false, "Please wait before sending another request")
        return
    end
    playerRequestTimes[player.UserId] = currentTime
    
    -- VALIDATION: Check if data types are correct to prevent errors
    if type(assetId) ~= "number" or type(assetType) ~= "string" then
        warn(player.Name .. " sent invalid data.")
        responseRemote:FireClient(player, false, "Invalid data sent")
        return
    end

    -- Validate clothing type
    if not validClothingTypes[assetType] then
        responseRemote:FireClient(player, false, "Invalid clothing type")
        return
    end

    -- Validate asset ID format
    if assetId <= 0 then
        responseRemote:FireClient(player, false, "Invalid asset ID")
        return
    end

    -- Check if premium-only item
    if premiumOnlyItems[assetId] and not (player.MembershipType == Enum.MembershipType.Premium) then
        responseRemote:FireClient(player, false, "Premium membership required for this item")
        return
    end

    local character = player.Character
    if not character then 
        responseRemote:FireClient(player, false, "Character not found")
        return 
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then 
        responseRemote:FireClient(player, false, "Humanoid not found")
        return 
    end

    -- 3. Apply the Change
    -- We use pcall (Protected Call) in case the Asset ID is invalid or deleted
    local success, err = pcall(function()
        -- Get current description
        local currentDescription = humanoid:GetAppliedDescription()

        -- Modify based on type
        if assetType == "Shirt" then
            currentDescription.Shirt = assetId
        elseif assetType == "Pants" then
            currentDescription.Pants = assetId
        elseif assetType == "Face" then
            currentDescription.Face = assetId
        end

        -- Apply the new description (Server-side, so it replicates to everyone)
        humanoid:ApplyDescription(currentDescription)
    end)

    if success then
        print("Successfully changed outfit for: " .. player.Name)
        responseRemote:FireClient(player, true, "Outfit changed successfully!")
    else
        warn("Failed to apply outfit: " .. tostring(err))
        responseRemote:FireClient(player, false, "Failed to apply outfit: " .. tostring(err))
    end
end

-- 4. Connect the listener
outfitRemote.OnServerEvent:Connect(onChangeRequest)

-- Clean up player data when they leave
Players.PlayerRemoving:Connect(function(player)
    playerRequestTimes[player.UserId] = nil
end)

--[[
    ADVANCED CATALOG POCKET - "THE SPECIAL SCRIPT"
    Features:     
    1. Real-time Catalog Fetching (AvatarEditorService)
    2. Visual Grid Layout
    3. One-Click Try On
    4. Draggable UI
    
    Setup: Put this in StarterPlayerScripts as a LocalScript.
]]

local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- // 1. UI CONSTRUCTION //
-- We build the UI via script so you don't have to manually make it

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpecialCatalogUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 450, 0, 500)
MainFrame.Position = UDim2.new(0.5, -225, 0.5, -250) -- Center
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

-- Header (Draggable Area)
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 50)
Header.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Text = "✨ CATALOG POCKET"
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 20, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBlack
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 20
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Text = "X"
CloseBtn.Size = UDim2.new(0, 50, 1, 0)
CloseBtn.Position = UDim2.new(1, -50, 0, 0)
CloseBtn.BackgroundTransparency = 1
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.Parent = Header

-- Scrolling Grid Area
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -20, 1, -70)
ScrollFrame.Position = UDim2.new(0, 10, 0, 60)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.ScrollBarThickness = 6
ScrollFrame.Parent = MainFrame

local GridLayout = Instance.new("UIGridLayout")
GridLayout.CellSize = UDim2.new(0, 100, 0, 130)
GridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
GridLayout.SortOrder = Enum.SortOrder.LayoutOrder
GridLayout.Parent = ScrollFrame

-- // 2. FUNCTIONALITY: FETCH CATALOG //

local function createItemCard(assetId, name, assetType)
    local Card = Instance.new("TextButton")
    Card.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    Card.Text = ""
    Card.AutoButtonColor = true
    Card.Parent = ScrollFrame
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 8)
    Corner.Parent = Card
    
    -- Image
    local Image = Instance.new("ImageLabel")
    Image.Size = UDim2.new(1, 0, 0, 100)
    Image.BackgroundTransparency = 1
    Image.Image = "rbxthumb://type=Asset&id=" .. assetId .. "&w=150&h=150"
    Image.Parent = Card
    
    -- Name
    local NameLabel = Instance.new("TextLabel")
    NameLabel.Text = name
    NameLabel.Size = UDim2.new(1, -10, 0, 30)
    NameLabel.Position = UDim2.new(0, 5, 0, 100)
    NameLabel.BackgroundTransparency = 1
    NameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    NameLabel.TextScaled = true
    NameLabel.Font = Enum.Font.Gotham
    NameLabel.TextWrapped = true
    NameLabel.Parent = Card
    
    -- Click Event (The "Try On" Logic)
    Card.MouseButton1Click:Connect(function()
        -- Send to server instead of applying locally
        outfitRemote:FireServer(assetId, assetType)
    end)
end

local function loadCatalogItems()
    -- Check if AvatarEditorService is available
    if not AvatarEditorService then
        warn("AvatarEditorService not available in this context")
        local errLabel = Instance.new("TextLabel")
        errLabel.Text = "Catalog not available in this context"
        errLabel.Size = UDim2.new(1, 0, 0, 50)
        errLabel.TextColor3 = Color3.new(1, 0, 0)
        errLabel.BackgroundTransparency = 1
        errLabel.TextWrapped = true
        errLabel.Parent = ScrollFrame
        return
    end
    
    -- Parameters: Searching for "Clothing", specifically "Shirts", Sorted by "BestSelling"
    local searchParams
    local success, result = pcall(function()
        searchParams = CatalogSearchParams.new()
        searchParams.SearchKeyword = ""
        searchParams.MinPrice = 0
        searchParams.MaxPrice = 100
        searchParams.SortType = Enum.CatalogSortType.BestSelling
        searchParams.AssetTypes = {Enum.AvatarAssetType.Shirt} -- Change this to Pants or TShirt to switch
        return AvatarEditorService:SearchCatalog(searchParams)
    end)
    
    if success and result then
        local currentPage
        local pageSuccess, pageError = pcall(function()
            return result:GetCurrentPage()
        end)
        
        if pageSuccess and currentPage then
            for _, item in pairs(currentPage) do
                createItemCard(item.Id, item.Name, "Shirt") -- Adjust based on actual type
            end
            -- Adjust scrolling size
            local rowCount = math.ceil(#currentPage / 3)
            ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, rowCount * 140)
        else
            warn("Failed to get catalog page: " .. tostring(pageError))
            local errLabel = Instance.new("TextLabel")
            errLabel.Text = "Failed to load catalog page"
            errLabel.Size = UDim2.new(1, 0, 0, 50)
            errLabel.TextColor3 = Color3.new(1, 0, 0)
            errLabel.BackgroundTransparency = 1
            errLabel.TextWrapped = true
            errLabel.Parent = ScrollFrame
        end
    else
        warn("Failed to fetch catalog: " .. tostring(result))
        local errLabel = Instance.new("TextLabel")
        errLabel.Text = "Failed to load catalog. API access may be restricted."
        errLabel.Size = UDim2.new(1, 0, 0, 50)
        errLabel.TextColor3 = Color3.new(1, 0, 0)
        errLabel.BackgroundTransparency = 1
        errLabel.TextWrapped = true
        errLabel.Parent = ScrollFrame
    end
end

-- // 3. DRAG LOGIC //
local dragging, dragInput, dragStart, startPos

local function update(input)
    local delta = input.Position - dragStart
    MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        update(input)
    end
end)

-- Toggle Button (Press 'C' to open/close)
UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.C then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- // START //
-- Add a delay to ensure services are ready
spawn(function()
    wait(1)
    loadCatalogItems()
end)
