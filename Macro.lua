-- ============================================================
-- PRODIGY MACRO — Standalone Build v6
-- Remote-fire ONLY. Cobalt-dump shape from real Blox Fruits.
-- Channel priority: Humanoid[""] (ability) > tool remote.
-- Payload priority: (key, true) first.
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

local player = Players.LocalPlayer
local CONFIG_FILE = "ProdigyMacro_Config.json"
local INTER_BLOCK_DELAY = 0.05

-- ============================================================
-- DATA
-- ============================================================
local ABILITY_MAP = {
    Fruit = {"Z", "X", "C", "V", "F"},
    Melee = {"Z", "X", "C", "V"},
    Gun   = {"Z", "X"},
    Sword = {"Z", "X"},
}
local WEAPONS = {"Fruit", "Melee", "Gun", "Sword"}
local MODES   = {"Tap", "Hold"}
local KEY_MAP = {
    Z = Enum.KeyCode.Z, X = Enum.KeyCode.X, C = Enum.KeyCode.C,
    V = Enum.KeyCode.V, F = Enum.KeyCode.F,
}

local MacroEnabled = false
local MacroRunning = false
local MacroThread = nil
local CompatibilityMode = false

local Blocks = {}
for i = 1, 8 do
    Blocks[i] = {
        enabled = false,
        mode = "Tap",
        weapon = "Fruit",
        ability = "Z",
        holdTime = 0.30,
    }
end

-- ============================================================
-- PERSISTENCE
-- ============================================================
local function saveConfig()
    local data = { enabled = MacroEnabled, compat = CompatibilityMode, blocks = {} }
    for i, b in ipairs(Blocks) do data.blocks[i] = b end
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function loadConfig()
    pcall(function()
        if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(data) ~= "table" then return end
        if data.enabled ~= nil then MacroEnabled = data.enabled == true end
        if data.compat ~= nil then CompatibilityMode = data.compat == true end
        if type(data.blocks) ~= "table" then return end
        for i = 1, math.min(8, #data.blocks) do
            local b = data.blocks[i]
            if type(b) == "table" then
                Blocks[i].enabled = b.enabled == true
                Blocks[i].mode = (b.mode == "Hold") and "Hold" or "Tap"
                if ABILITY_MAP[b.weapon] then Blocks[i].weapon = b.weapon end
                local allowed = ABILITY_MAP[Blocks[i].weapon]
                for _, a in ipairs(allowed) do
                    if a == b.ability then Blocks[i].ability = b.ability end
                end
                if tonumber(b.holdTime) then
                    Blocks[i].holdTime = math.clamp(tonumber(b.holdTime), 0.05, 5.0)
                end
            end
        end
    end)
end
loadConfig()

-- ============================================================
-- ABILITY FIRING — REMOTE ONLY
-- ============================================================
local function sendKeyRaw(keyCode, down)
    if not VirtualInputManager then return end
    pcall(function()
        VirtualInputManager:SendKeyEvent(down, keyCode, false, game)
    end)
end

local function releaseAllKeys()
    if not CompatibilityMode then return end
    for _, kc in pairs(KEY_MAP) do sendKeyRaw(kc, false) end
end

-- Try a payload shape against a remote (auto-routes InvokeServer vs FireServer).
local function attempt(remote, args)
    if not remote then return false end
    -- strip trailing nils
    local clean = {}
    for i = 1, #args do
        if args[i] ~= nil then clean[#clean + 1] = args[i] end
    end
    local ok = pcall(function()
        if remote:IsA("RemoteFunction") then
            remote:InvokeServer(table.unpack(clean))
        else
            remote:FireServer(table.unpack(clean))
        end
    end)
    return ok
end

-- Blox Fruits ability channel: Humanoid[""] RemoteFunction (or RemoteEvent).
-- Signature from Cobalt dump: (abilityKey, true)
local function fireOnHumanoid(abilityKey, holdSeconds)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    local remote = hum:FindFirstChild("")
    if not remote then
        for _, c in ipairs(hum:GetChildren()) do
            if c.Name == "" and (c:IsA("RemoteFunction") or c:IsA("RemoteEvent")) then
                remote = c
                break
            end
        end
    end
    if not remote then return false end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local pos = myRoot and myRoot.Position or Vector3.zero
    local targetPart = _G.currentSilentAimTarget
    local targetRoot = targetPart and targetPart.Parent
        and targetPart.Parent:FindFirstChild("HumanoidRootPart")

    -- Shape priority from real dumps:
    --  1. (key, true)                        -- fruit / combat primary
    --  2. (key)                              -- some melee
    --  3. (key, pos, targetRoot)             -- Buddy Sword / positional
    --  4. (key, true, targetRoot)            -- alt variant
    --  5. (key, pos)
    --  6. (key, targetRoot)
    local payloads = {
        {abilityKey, true},
        {abilityKey},
        {abilityKey, pos, targetRoot},
        {abilityKey, true, targetRoot},
        {abilityKey, pos},
        {abilityKey, targetRoot},
    }

    for _, args in ipairs(payloads) do
        if attempt(remote, args) then
            if holdSeconds and holdSeconds > 0 then
                task.wait(holdSeconds)
                pcall(function()
                    if remote:IsA("RemoteFunction") then
                        remote:InvokeServer(abilityKey, false)
                    else
                        remote:FireServer(abilityKey, false)
                    end
                end)
            end
            return true
        end
    end
    return false
end

-- Fallback: some tools carry their ability remote directly.
local REMOTE_NAMES = {
    "RemoteEvent", "", "Remote", "AbilityRemote", "CommE",
    "Skill", "Attack", "Use", "Server", "Event", "Fire"
}

local function findRemoteIn(container)
    if not container then return nil end
    for _, name in ipairs(REMOTE_NAMES) do
        local child = container:FindFirstChild(name)
        if child and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
            return child
        end
    end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            return child
        end
    end
    return nil
end

local function fireOnTool(abilityKey, holdSeconds)
    local char = player.Character
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return false end

    local remote = findRemoteIn(tool)
    if not remote then return false end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local pos = myRoot and myRoot.Position or Vector3.zero
    local targetPart = _G.currentSilentAimTarget
    local targetRoot = targetPart and targetPart.Parent
        and targetPart.Parent:FindFirstChild("HumanoidRootPart")

    -- The tool's "RemoteEvent" is the equip/unequip channel for fruits.
    -- Firing (true) equips — that path is separate.
    -- For tool-specific abilities, try the common ability shapes.
    local payloads = {
        {abilityKey, true},
        {abilityKey},
        {abilityKey, pos, targetRoot},
        {abilityKey, pos},
    }

    for _, args in ipairs(payloads) do
        if attempt(remote, args) then
            if holdSeconds and holdSeconds > 0 then
                task.wait(holdSeconds)
                pcall(function() remote:FireServer(abilityKey, false) end)
            end
            return true
        end
    end
    return false
end

local function fireAbilityRemote(abilityKey, holdSeconds)
    -- Humanoid "" channel is primary for Blox Fruits abilities.
    if fireOnHumanoid(abilityKey, holdSeconds) then return true end
    -- Tool remote as fallback.
    if fireOnTool(abilityKey, holdSeconds) then return true end
    return false
end

-- Manual single-fire test (exposed as _G.ProdigyMacroTestFire(key))
local function testFire(abilityKey)
    print("[ProdigyMacro] test fire ->", abilityKey)
    local ok = fireAbilityRemote(abilityKey, 0)
    print("[ProdigyMacro] result:", ok)
    return ok
end

-- Diagnostics
local function probeCurrentTool()
    local char = player.Character
    if not char then print("[Probe] no character"); return end
    local tool = char:FindFirstChildOfClass("Tool")
    local hum  = char:FindFirstChildOfClass("Humanoid")
    print("===== PROBE =====")
    print("Equipped:", tool and tool.Name or "(none)")
    if tool then
        for _, c in ipairs(tool:GetChildren()) do
            print("  tool ->", c.ClassName, "[" .. c.Name .. "]")
        end
    end
    if hum then
        for _, c in ipairs(hum:GetChildren()) do
            print("  hum  ->", c.ClassName, "[" .. c.Name .. "]")
        end
    end
    print("==================")
end

-- ============================================================
-- TOOL CATEGORY DETECTION + AUTO EQUIP
-- ============================================================
local FRUIT_KEYWORDS = {
    "blade-blade","bladeblade","portal","dough","dragon","leopard","kitsune",
    "buddha","t-rex","trex","mammoth","sound","blizzard","spirit","venom",
    "shadow","control","gravity","rumble","paw","spider","love","quake",
    "magma","light","ice","flame","dark","sand","falcon","diamond","rubber",
    "barrier","ghost","spin","chop","spring","bomb","smoke","rocket","creation",
    "eagle","gas","lightning","tiger"
}
local SWORD_KEYWORDS = {
    "blade","sword","katana","yoru","cursed","scythe","saber","pole","bisento",
    "trident","dagger","cutlass","rapier","koko","shark","kabucha","iron",
    "wando","twin","hook","longsword","broom","buddy"
}
local GUN_KEYWORDS = {
    "gun","rifle","flintlock","slingshot","bazooka","cannon","guitar","bow",
    "revolver","pistol"
}
local MELEE_KEYWORDS = {
    "combat","black leg","electro","fishman karate","dragon talon","superhuman",
    "death step","sharkman karate","electric claw","godhuman","sanguine art"
}

local function matchesAny(name, list)
    for _, kw in ipairs(list) do
        if name:find(kw, 1, true) then return true end
    end
    return false
end

local function detectToolCategory(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local name = string.lower(tool.Name)
    local tip = ""
    pcall(function() tip = string.lower(tool.ToolTip or "") end)
    local hasFruitChild = tool:FindFirstChild("Fruit") ~= nil
    local hasSwordChild = tool:FindFirstChild("Sword") ~= nil
    local hasGunChild   = tool:FindFirstChild("Gun")   ~= nil

    if hasFruitChild or tip:find("blox fruit") or tip:find("fruit") then return "Fruit" end
    if name:find("-") then
        local a, b = name:match("^([%w%s]+)%-(%w+)$")
        if a and b and (a:find(b) or b:find(a)) then return "Fruit" end
    end
    for _, kw in ipairs(FRUIT_KEYWORDS) do
        if name:find(kw, 1, true) then
            if not matchesAny(name, SWORD_KEYWORDS) and not matchesAny(name, GUN_KEYWORDS) then
                return "Fruit"
            end
            break
        end
    end
    if hasSwordChild or tip:find("sword") or matchesAny(name, SWORD_KEYWORDS) then return "Sword" end
    if hasGunChild or tip:find("gun") or matchesAny(name, GUN_KEYWORDS) then return "Gun" end
    if matchesAny(name, MELEE_KEYWORDS) then return "Melee" end
    if not hasFruitChild and not hasSwordChild and not hasGunChild then return "Melee" end
    return nil
end

local function findToolForWeapon(weapon)
    local char = player.Character
    if not char then return nil end
    local backpack = player:FindFirstChild("Backpack")
    for _, cont in ipairs({char, backpack}) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") and detectToolCategory(tool) == weapon then
                    return tool
                end
            end
        end
    end
    return nil
end

local function equipWeapon(weapon)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local current = char:FindFirstChildOfClass("Tool")
    if current and detectToolCategory(current) == weapon then return true end
    local tool = findToolForWeapon(weapon)
    if not tool then return false end
    pcall(function() hum:EquipTool(tool) end)
    task.wait(0.10)
    return true
end

-- ============================================================
-- MACRO LOOP
-- ============================================================
local function runMacroLoop()
    while MacroRunning do
        for i = 1, 8 do
            if not MacroRunning then break end
            local b = Blocks[i]
            if b.enabled then
                local kc = KEY_MAP[b.ability]
                if kc then
                    local ok = equipWeapon(b.weapon)
                    if ok then
                        local holdSec = (b.mode == "Hold") and b.holdTime or 0
                        local fired = fireAbilityRemote(b.ability, holdSec)
                        if not fired and CompatibilityMode then
                            sendKeyRaw(kc, true)
                            task.wait(b.mode == "Hold" and b.holdTime or 0.03)
                            sendKeyRaw(kc, false)
                        end
                    end
                end
                task.wait(INTER_BLOCK_DELAY)
            end
        end
        task.wait(INTER_BLOCK_DELAY)
    end
    MacroThread = nil
end

local function startMacro()
    if MacroRunning then return end
    if not MacroEnabled then return end
    MacroRunning = true
    MacroThread = task.spawn(runMacroLoop)
end

local function stopMacro()
    MacroRunning = false
    MacroThread = nil
    releaseAllKeys()
end

-- ============================================================
-- UI ROOT
-- ============================================================
local uiParent
pcall(function()
    if type(gethui) == "function" then uiParent = gethui() end
end)
uiParent = uiParent or CoreGui

pcall(function()
    local old = uiParent:FindFirstChild("ProdigyMacro")
    if old then old:Destroy() end
end)

local Screen = Instance.new("ScreenGui")
Screen.Name = "ProdigyMacro"
Screen.ResetOnSpawn = false
Screen.IgnoreGuiInset = true
Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Screen.Parent = uiParent

local C_BG     = Color3.fromRGB(4, 6, 14)
local C_PANEL  = Color3.fromRGB(8, 10, 20)
local C_CARD   = Color3.fromRGB(10, 13, 22)
local C_INPUT  = Color3.fromRGB(2, 8, 16)
local C_ACCENT = Color3.fromRGB(0, 220, 255)
local C_TEXT   = Color3.fromRGB(230, 240, 255)
local C_MUTED  = Color3.fromRGB(130, 150, 170)
local C_GREEN  = Color3.fromRGB(0, 255, 160)
local C_RED    = Color3.fromRGB(255, 80, 80)
local C_ORANGE = Color3.fromRGB(255, 160, 60)

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = obj
    return c
end
local function stroke(obj, col, trans)
    local s = Instance.new("UIStroke")
    s.Color = col or C_ACCENT
    s.Transparency = trans or 0.75
    s.Thickness = 1
    s.Parent = obj
    return s
end

-- FLOATING
local Floating = Instance.new("TextButton")
Floating.Name = "Floating"
Floating.AnchorPoint = Vector2.new(1, 0)
Floating.Position = UDim2.new(1, -20, 0, 100)
Floating.Size = UDim2.new(0, 58, 0, 58)
Floating.BackgroundColor3 = C_BG
Floating.Text = ""
Floating.AutoButtonColor = false
Floating.Parent = Screen
corner(Floating, 999)
local floatStroke = stroke(Floating, C_ACCENT, 0.2)
floatStroke.Thickness = 2

local FloatingIcon = Instance.new("TextLabel")
FloatingIcon.BackgroundTransparency = 1
FloatingIcon.Text = "▶"
FloatingIcon.TextColor3 = C_ACCENT
FloatingIcon.Font = Enum.Font.GothamBold
FloatingIcon.TextSize = 20
FloatingIcon.Size = UDim2.new(1, 0, 1, 0)
FloatingIcon.Parent = Floating

local GearBtn = Instance.new("TextButton")
GearBtn.AutoButtonColor = false
GearBtn.Text = "⚙"
GearBtn.TextColor3 = C_ACCENT
GearBtn.Font = Enum.Font.GothamBold
GearBtn.TextSize = 12
GearBtn.BackgroundColor3 = C_BG
GearBtn.AnchorPoint = Vector2.new(0.5, 0.5)
GearBtn.Position = UDim2.new(0.85, 0, 0.15, 0)
GearBtn.Size = UDim2.new(0, 20, 0, 20)
GearBtn.Parent = Floating
corner(GearBtn, 999)
stroke(GearBtn, C_ACCENT, 0.35)

local updateFloatingVisual
updateFloatingVisual = function()
    if MacroRunning then
        FloatingIcon.Text = "■"
        FloatingIcon.TextColor3 = C_RED
        floatStroke.Color = C_RED
    elseif not MacroEnabled then
        FloatingIcon.Text = "▶"
        FloatingIcon.TextColor3 = C_MUTED
        floatStroke.Color = C_MUTED
    else
        FloatingIcon.Text = "▶"
        FloatingIcon.TextColor3 = C_GREEN
        floatStroke.Color = C_GREEN
    end
end

-- PANEL
local Panel = Instance.new("Frame")
Panel.Name = "Panel"
Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.Position = UDim2.new(0.5, 0, 0.5, 0)
Panel.Size = UDim2.new(0, 460, 0, 660)
Panel.BackgroundColor3 = C_BG
Panel.BorderSizePixel = 0
Panel.Visible = false
Panel.Parent = Screen
corner(Panel, 14)
stroke(Panel, C_ACCENT, 0.5)

local scale = Instance.new("UIScale")
scale.Parent = Panel
local function resizeUI()
    local cam = workspace.CurrentCamera
    if not cam then return end
    scale.Scale = math.clamp(math.min((cam.ViewportSize.X - 20) / 460, (cam.ViewportSize.Y - 30) / 660), 0.6, 1)
end
resizeUI()
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeUI)
end

local Header = Instance.new("Frame")
Header.BackgroundTransparency = 1
Header.Size = UDim2.new(1, 0, 0, 54)
Header.Parent = Panel

local HTitle = Instance.new("TextLabel")
HTitle.BackgroundTransparency = 1
HTitle.Text = "MACRO"
HTitle.TextColor3 = C_ACCENT
HTitle.Font = Enum.Font.GothamBold
HTitle.TextSize = 16
HTitle.TextXAlignment = Enum.TextXAlignment.Left
HTitle.Position = UDim2.new(0, 18, 0, 10)
HTitle.Size = UDim2.new(0, 220, 0, 18)
HTitle.Parent = Header

local HSub = Instance.new("TextLabel")
HSub.BackgroundTransparency = 1
HSub.Text = "REMOTE-FIRE v6"
HSub.TextColor3 = C_MUTED
HSub.Font = Enum.Font.GothamBold
HSub.TextSize = 8
HSub.TextXAlignment = Enum.TextXAlignment.Left
HSub.Position = UDim2.new(0, 18, 0, 30)
HSub.Size = UDim2.new(0, 220, 0, 12)
HSub.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.AutoButtonColor = false
CloseBtn.Text = "×"
CloseBtn.TextColor3 = C_TEXT
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.BackgroundColor3 = Color3.fromRGB(22, 15, 25)
CloseBtn.Position = UDim2.new(1, -46, 0, 16)
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Parent = Header
corner(CloseBtn, 8)
CloseBtn.MouseButton1Click:Connect(function() Panel.Visible = false end)

-- Enable row
local EnableRow = Instance.new("Frame")
EnableRow.BackgroundColor3 = C_PANEL
EnableRow.BorderSizePixel = 0
EnableRow.Position = UDim2.new(0, 14, 0, 62)
EnableRow.Size = UDim2.new(1, -28, 0, 46)
EnableRow.Parent = Panel
corner(EnableRow, 10)
stroke(EnableRow, C_ACCENT, 0.85)

local EnableLabel = Instance.new("TextLabel")
EnableLabel.BackgroundTransparency = 1
EnableLabel.Text = "Macro Enable"
EnableLabel.TextColor3 = C_TEXT
EnableLabel.Font = Enum.Font.GothamBold
EnableLabel.TextSize = 11
EnableLabel.TextXAlignment = Enum.TextXAlignment.Left
EnableLabel.Position = UDim2.new(0, 14, 0, 0)
EnableLabel.Size = UDim2.new(1, -90, 1, 0)
EnableLabel.Parent = EnableRow

local EnableToggle = Instance.new("TextButton")
EnableToggle.AutoButtonColor = false
EnableToggle.Text = MacroEnabled and "ON" or "OFF"
EnableToggle.TextColor3 = MacroEnabled and C_GREEN or C_MUTED
EnableToggle.Font = Enum.Font.GothamBold
EnableToggle.TextSize = 10
EnableToggle.BackgroundColor3 = MacroEnabled and Color3.fromRGB(4, 30, 20) or Color3.fromRGB(20, 20, 30)
EnableToggle.Position = UDim2.new(1, -62, 0.5, -11)
EnableToggle.Size = UDim2.new(0, 48, 0, 22)
EnableToggle.Parent = EnableRow
corner(EnableToggle, 6)

EnableToggle.MouseButton1Click:Connect(function()
    MacroEnabled = not MacroEnabled
    EnableToggle.Text = MacroEnabled and "ON" or "OFF"
    EnableToggle.TextColor3 = MacroEnabled and C_GREEN or C_MUTED
    EnableToggle.BackgroundColor3 = MacroEnabled and Color3.fromRGB(4, 30, 20) or Color3.fromRGB(20, 20, 30)
    if not MacroEnabled then stopMacro() end
    updateFloatingVisual()
    saveConfig()
end)

-- Compat row
local CompatRow = Instance.new("Frame")
CompatRow.BackgroundColor3 = C_PANEL
CompatRow.BorderSizePixel = 0
CompatRow.Position = UDim2.new(0, 14, 0, 114)
CompatRow.Size = UDim2.new(1, -28, 0, 46)
CompatRow.Parent = Panel
corner(CompatRow, 10)
stroke(CompatRow, C_ORANGE, 0.85)

local CompatLabel = Instance.new("TextLabel")
CompatLabel.BackgroundTransparency = 1
CompatLabel.Text = "Compatibility Mode (shifts UI)"
CompatLabel.TextColor3 = C_ORANGE
CompatLabel.Font = Enum.Font.GothamBold
CompatLabel.TextSize = 10
CompatLabel.TextXAlignment = Enum.TextXAlignment.Left
CompatLabel.Position = UDim2.new(0, 14, 0, 0)
CompatLabel.Size = UDim2.new(1, -90, 1, 0)
CompatLabel.Parent = CompatRow

local CompatToggle = Instance.new("TextButton")
CompatToggle.AutoButtonColor = false
CompatToggle.Text = CompatibilityMode and "ON" or "OFF"
CompatToggle.TextColor3 = CompatibilityMode and C_ORANGE or C_MUTED
CompatToggle.Font = Enum.Font.GothamBold
CompatToggle.TextSize = 10
CompatToggle.BackgroundColor3 = CompatibilityMode and Color3.fromRGB(40, 24, 4) or Color3.fromRGB(20, 20, 30)
CompatToggle.Position = UDim2.new(1, -62, 0.5, -11)
CompatToggle.Size = UDim2.new(0, 48, 0, 22)
CompatToggle.Parent = CompatRow
corner(CompatToggle, 6)

CompatToggle.MouseButton1Click:Connect(function()
    CompatibilityMode = not CompatibilityMode
    CompatToggle.Text = CompatibilityMode and "ON" or "OFF"
    CompatToggle.TextColor3 = CompatibilityMode and C_ORANGE or C_MUTED
    CompatToggle.BackgroundColor3 = CompatibilityMode and Color3.fromRGB(40, 24, 4) or Color3.fromRGB(20, 20, 30)
    saveConfig()
end)

-- Test Fire button
local TestRow = Instance.new("Frame")
TestRow.BackgroundColor3 = C_PANEL
TestRow.BorderSizePixel = 0
TestRow.Position = UDim2.new(0, 14, 0, 166)
TestRow.Size = UDim2.new(1, -28, 0, 40)
TestRow.Parent = Panel
corner(TestRow, 10)
stroke(TestRow, C_ACCENT, 0.55)

local TestBtn = Instance.new("TextButton")
TestBtn.AutoButtonColor = false
TestBtn.Text = "TEST FIRE (current block abilities)"
TestBtn.TextColor3 = C_TEXT
TestBtn.Font = Enum.Font.GothamBold
TestBtn.TextSize = 10
TestBtn.BackgroundTransparency = 1
TestBtn.Size = UDim2.new(1, 0, 1, 0)
TestBtn.Parent = TestRow
TestBtn.MouseButton1Click:Connect(function()
    local fired = 0
    for i = 1, 8 do
        local b = Blocks[i]
        if b.enabled then
            task.spawn(function()
                equipWeapon(b.weapon)
                testFire(b.ability)
            end)
            fired = fired + 1
        end
    end
    print("[ProdigyMacro] test fired on", fired, "blocks")
end)

local BlockScroll = Instance.new("ScrollingFrame")
BlockScroll.BackgroundTransparency = 1
BlockScroll.BorderSizePixel = 0
BlockScroll.Position = UDim2.new(0, 14, 0, 216)
BlockScroll.Size = UDim2.new(1, -28, 1, -230)
BlockScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
BlockScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
BlockScroll.ScrollBarThickness = 4
BlockScroll.ScrollBarImageColor3 = C_ACCENT
BlockScroll.Parent = Panel

local BlockLayout = Instance.new("UIListLayout")
BlockLayout.Padding = UDim.new(0, 10)
BlockLayout.SortOrder = Enum.SortOrder.LayoutOrder
BlockLayout.Parent = BlockScroll

-- ============================================================
-- BLOCK CARD BUILDER
-- ============================================================
local function buildBlockCard(parent, index)
    local block = Blocks[index]

    local card = Instance.new("Frame")
    card.BackgroundColor3 = C_CARD
    card.BorderSizePixel = 0
    card.Size = UDim2.new(1, 0, 0, 172)
    card.LayoutOrder = index
    card.Parent = parent
    corner(card, 10)
    stroke(card, C_ACCENT, 0.75)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Text = "Macro Block " .. index
    title.TextColor3 = C_TEXT
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Position = UDim2.new(0, 14, 0, 10)
    title.Size = UDim2.new(1, -100, 0, 18)
    title.Parent = card

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.AutoButtonColor = false
    toggleBtn.Text = block.enabled and "ON" or "OFF"
    toggleBtn.TextColor3 = block.enabled and C_GREEN or C_MUTED
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 10
    toggleBtn.BackgroundColor3 = block.enabled and Color3.fromRGB(4, 30, 20) or Color3.fromRGB(22, 22, 32)
    toggleBtn.Position = UDim2.new(1, -68, 0, 8)
    toggleBtn.Size = UDim2.new(0, 54, 0, 22)
    toggleBtn.Parent = card
    corner(toggleBtn, 6)

    toggleBtn.MouseButton1Click:Connect(function()
        block.enabled = not block.enabled
        toggleBtn.Text = block.enabled and "ON" or "OFF"
        toggleBtn.TextColor3 = block.enabled and C_GREEN or C_MUTED
        toggleBtn.BackgroundColor3 = block.enabled and Color3.fromRGB(4, 30, 20) or Color3.fromRGB(22, 22, 32)
        saveConfig()
    end)

    local div = Instance.new("Frame")
    div.BackgroundColor3 = C_ACCENT
    div.BackgroundTransparency = 0.85
    div.BorderSizePixel = 0
    div.Position = UDim2.new(0, 12, 0, 34)
    div.Size = UDim2.new(1, -24, 0, 1)
    div.Parent = card

    local function makeRow(y, labelText)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = C_MUTED
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 9
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Position = UDim2.new(0, 16, 0, y + 8)
        lbl.Size = UDim2.new(0, 66, 0, 16)
        lbl.Parent = card

        local valueBox = Instance.new("Frame")
        valueBox.BackgroundColor3 = C_INPUT
        valueBox.BorderSizePixel = 0
        valueBox.Position = UDim2.new(0, 84, 0, y)
        valueBox.Size = UDim2.new(1, -100, 0, 28)
        valueBox.Parent = card
        corner(valueBox, 6)
        stroke(valueBox, C_ACCENT, 0.75)
        return valueBox
    end

    local function makeArrow(parent, side)
        local btn = Instance.new("TextButton")
        btn.AutoButtonColor = false
        btn.Text = (side == "left") and "◀" or "▶"
        btn.TextColor3 = C_ACCENT
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10
        btn.BackgroundTransparency = 1
        btn.Position = (side == "left") and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -22, 0, 0)
        btn.Size = UDim2.new(0, 22, 1, 0)
        btn.Parent = parent
        return btn
    end

    local function makeValueLabel(parent)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = ""
        lbl.TextColor3 = C_TEXT
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.Size = UDim2.new(1, -46, 1, 0)
        lbl.Position = UDim2.new(0, 23, 0, 0)
        lbl.Parent = parent
        return lbl
    end

    -- Mode
    local modeBox = makeRow(44, "Mode")
    local modeLabel = makeValueLabel(modeBox)
    local modeIndex = (block.mode == "Hold") and 2 or 1
    modeLabel.Text = MODES[modeIndex]
    local mLeft = makeArrow(modeBox, "left")
    local mRight = makeArrow(modeBox, "right")
    local function applyMode()
        block.mode = MODES[modeIndex]
        modeLabel.Text = block.mode
        saveConfig()
    end
    mLeft.MouseButton1Click:Connect(function()
        modeIndex -= 1
        if modeIndex < 1 then modeIndex = #MODES end
        applyMode()
    end)
    mRight.MouseButton1Click:Connect(function()
        modeIndex += 1
        if modeIndex > #MODES then modeIndex = 1 end
        applyMode()
    end)

    -- Weapon
    local weaponBox = makeRow(76, "Weapon")
    local weaponLabel = makeValueLabel(weaponBox)
    local weaponIndex = table.find(WEAPONS, block.weapon) or 1
    weaponLabel.Text = WEAPONS[weaponIndex]
    local wLeft = makeArrow(weaponBox, "left")
    local wRight = makeArrow(weaponBox, "right")

    -- Ability
    local abilityBox = makeRow(108, "Ability")
    local abilityLabel = makeValueLabel(abilityBox)
    local abilityIndex = 1
    local function currentList() return ABILITY_MAP[block.weapon] or {"Z"} end
    do
        local list = currentList()
        for i, a in ipairs(list) do if a == block.ability then abilityIndex = i end end
        block.ability = list[abilityIndex]
        abilityLabel.Text = block.ability
    end

    local function resetAbility()
        local list = currentList()
        abilityIndex = 1
        block.ability = list[1]
        abilityLabel.Text = block.ability
    end

    wLeft.MouseButton1Click:Connect(function()
        weaponIndex -= 1
        if weaponIndex < 1 then weaponIndex = #WEAPONS end
        block.weapon = WEAPONS[weaponIndex]
        weaponLabel.Text = block.weapon
        resetAbility()
        saveConfig()
    end)
    wRight.MouseButton1Click:Connect(function()
        weaponIndex += 1
        if weaponIndex > #WEAPONS then weaponIndex = 1 end
        block.weapon = WEAPONS[weaponIndex]
        weaponLabel.Text = block.weapon
        resetAbility()
        saveConfig()
    end)

    local aLeft = makeArrow(abilityBox, "left")
    local aRight = makeArrow(abilityBox, "right")
    aLeft.MouseButton1Click:Connect(function()
        local list = currentList()
        abilityIndex -= 1
        if abilityIndex < 1 then abilityIndex = #list end
        block.ability = list[abilityIndex]
        abilityLabel.Text = block.ability
        saveConfig()
    end)
    aRight.MouseButton1Click:Connect(function()
        local list = currentList()
        abilityIndex += 1
        if abilityIndex > #list then abilityIndex = 1 end
        block.ability = list[abilityIndex]
        abilityLabel.Text = block.ability
        saveConfig()
    end)

    -- Hold Time
    local holdBox = makeRow(140, "Hold Time")
    local holdInput = Instance.new("TextBox")
    holdInput.ClearTextOnFocus = false
    holdInput.Text = string.format("%.2fs", block.holdTime)
    holdInput.TextColor3 = C_TEXT
    holdInput.Font = Enum.Font.GothamBold
    holdInput.TextSize = 10
    holdInput.BackgroundTransparency = 1
    holdInput.Size = UDim2.new(1, 0, 1, 0)
    holdInput.Parent = holdBox
    holdInput.FocusLost:Connect(function()
        local cleaned = holdInput.Text:gsub("s", "")
        local n = tonumber(cleaned)
        if n then
            block.holdTime = math.clamp(n, 0.05, 5.0)
            holdInput.Text = string.format("%.2fs", block.holdTime)
            saveConfig()
        else
            holdInput.Text = string.format("%.2fs", block.holdTime)
        end
    end)
end

for i = 1, 8 do
    buildBlockCard(BlockScroll, i)
end

-- ============================================================
-- FLOATING BUTTON INTERACTION
-- ============================================================
Floating.MouseButton1Click:Connect(function()
    if not MacroEnabled then
        Panel.Visible = true
        return
    end
    if MacroRunning then
        stopMacro()
    else
        startMacro()
    end
    updateFloatingVisual()
end)

GearBtn.MouseButton1Click:Connect(function()
    Panel.Visible = not Panel.Visible
end)

do
    local dragging = false
    local dragStart, startPos, activeInput
    Floating.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Floating.Position
            activeInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or input ~= activeInput then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        Floating.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)
end

do
    local dragging = false
    local dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Panel.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        Panel.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

_G.ProdigyMacroProbe = probeCurrentTool
_G.ProdigyMacroTestFire = testFire

updateFloatingVisual()
print("[ProdigyMacro] v6 loaded — Cobalt-shape remote fire")
print("[ProdigyMacro] _G.ProdigyMacroProbe() to dump remotes")
print("[ProdigyMacro] _G.ProdigyMacroTestFire('Z') to test single ability")
