-- LushfoilCraft framework.
--
-- Everything runs on the game thread, from one per-frame hook on the game's own player controller. There are deliberately no
-- LoopAsync / ExecuteWithDelay / RegisterKeyBind callbacks: those run Lua on other threads and corrupted UE4SS's Lua state
-- (random crashes inside UE4SS.dll). Key presses are polled from the game's input state each frame instead.
--
-- craft.lua holds the features and is hot-reloaded whenever the file changes; dev.lua is a scratch file that is executed once
-- each time its content changes (used while developing).

LC = LC or { keys = {}, tickFn = nil, loaded = "", devText = "", now = 0, timers = {}, down = {}, heldAt = {} }

local dir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])")) or ""
LC.dir = dir                      -- .../Mods/LushfoilCraft/Scripts/
LC.root = dir:gsub("[/\\]Scripts[/\\]$", "/")
-- worlds and settings belong to the person playing on this device, not to the game folder (copying the folder to another PC brings none of them)
LC.data = (os.getenv("LOCALAPPDATA") or "") .. "\\LushfoilSim\\Saved\\LushfoilCraft-"

function LC.log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print("[LushfoilCraft] " .. (ok and msg or tostring(fmt)) .. "\n")
end

-- one-shot timer, driven by frame time
function LC.after(seconds, fn) LC.timers[#LC.timers + 1] = { at = LC.now + seconds, fn = fn } end

-- ------------------------------------------------------------------ keys (polled)
-- handler name used by craft.lua -> the engine's FKey name
local KEYS = {
    LEFT_MOUSE_BUTTON = "LeftMouseButton", RIGHT_MOUSE_BUTTON = "RightMouseButton", MIDDLE_MOUSE_BUTTON = "MiddleMouseButton",
    W = "W", LEFT_SHIFT = "LeftShift", SLASH = "Slash", MINUS = "Hyphen", PLUS = "Equals", F = "F", R = "R", Q = "Q", E = "E", Z = "Z", X = "X", B = "B", G = "G", V = "V", T = "T",
    PAGE_UP = "PageUp", PAGE_DOWN = "PageDown", SPACE = "SpaceBar", LCTRL = "LeftControl",
    UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right", ENTER = "Enter", ESCAPE = "Escape",
    F1 = "F1", F2 = "F2", F3 = "F3", F4 = "F4", F5 = "F5", F6 = "F6", F7 = "F7", F8 = "F8", F9 = "F9",
    ONE = "One", TWO = "Two", THREE = "Three", FOUR = "Four", FIVE = "Five", SIX = "Six", SEVEN = "Seven", EIGHT = "Eight", NINE = "Nine",
    -- Xbox-style controller (360 / One over USB, XInput layout)
    GP_RT = "Gamepad_RightTrigger", GP_LT = "Gamepad_LeftTrigger", GP_RB = "Gamepad_RightShoulder", GP_LB = "Gamepad_LeftShoulder",
    GP_A = "Gamepad_FaceButton_Bottom", GP_B = "Gamepad_FaceButton_Right", GP_X = "Gamepad_FaceButton_Left", GP_Y = "Gamepad_FaceButton_Top",
    GP_DUP = "Gamepad_DPad_Up", GP_DDOWN = "Gamepad_DPad_Down", GP_DLEFT = "Gamepad_DPad_Left", GP_DRIGHT = "Gamepad_DPad_Right",
    GP_L3 = "Gamepad_LeftThumbstick", GP_R3 = "Gamepad_RightThumbstick", GP_BACK = "Gamepad_Special_Left", GP_START = "Gamepad_Special_Right",
}
-- held keys that repeat like Minecraft (break / place while held)
-- seconds between repeats while held: creative breaking has a 5 tick cooldown, using / placing 4 ticks (Java Edition)
local REPEAT = { LEFT_MOUSE_BUTTON = 0.25, RIGHT_MOUSE_BUTTON = 0.2, F = 0.25, R = 0.2, GP_RT = 0.25, GP_LT = 0.2 }


-- typing while the chat bar is open: every key is polled here and turned into characters; nothing else reacts meanwhile
local CHAT_KEYS = { Slash = "/", Period = ".", Comma = ",", SpaceBar = " ", Hyphen = "-", Semicolon = ";", Equals = "=" }
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do CHAT_KEYS[c:upper()] = c end
for n, name in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do CHAT_KEYS[name] = tostring(n - 1) end
local CHAT_ACTIONS = { Enter = "Enter", BackSpace = "BackSpace", Escape = "Escape", Tab = "Tab" }
local chatDown, chatNext = {}, {}
local function pollChat(pc)
    local function isDown(k) local ok, d = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end); return ok and d end
    local shift = isDown("LeftShift") or isDown("RightShift")
    local function press(k)
        local d = isDown(k)
        local fire = false
        if d and not chatDown[k] then fire = true; chatNext[k] = LC.now + 0.4
        elseif d and k == "BackSpace" and LC.now >= (chatNext[k] or math.huge) then fire = true; chatNext[k] = LC.now + 0.05 end
        chatDown[k] = d
        return fire
    end
    for k, ch in pairs(CHAT_KEYS) do
        if press(k) and LC.chatChar then
            if shift then
                if k == "Hyphen" then ch = "_" elseif k == "Semicolon" then ch = ":" elseif ch:match("%a") then ch = ch:upper() end
            end
            pcall(LC.chatChar, ch)
        end
    end
    for k, name in pairs(CHAT_ACTIONS) do
        if press(k) and LC.chatKey then pcall(LC.chatKey, name) end
    end
end

local function pollKeys(pc)
    if (LC.chat and LC.chat.open) or (LC.inv and LC.inv.open and LC.inv.typing) or (LC.title and LC.title.typing) then pollChat(pc); LC.down = {}; return end
    for name, fkey in pairs(KEYS) do
        local ok, d = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(fkey) }) end)
        d = ok and d or false
        local fire = false
        if d and not LC.down[name] then fire = true; LC.heldAt[name] = LC.now + (REPEAT[name] or 0.25)
        elseif d and REPEAT[name] and LC.now >= (LC.heldAt[name] or math.huge) then fire = true; LC.heldAt[name] = LC.now + REPEAT[name] end
        if fire then
            local h = LC.keys[name]
            if h then local ok2, e = pcall(h); if not ok2 then LC.log("key %s error: %s", name, tostring(e)) end end
        end
        LC.down[name] = d
    end
end

-- ------------------------------------------------------------------ hot reload
local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local t = f:read("*a"); f:close()
    return t
end

local function loadCraft()
    local text = readFile(LC.dir .. "craft.lua")
    if not text or text == LC.loaded then return end
    LC.loaded = text
    LC.keys = {}; LC.tickFn = nil; LC.timers = {}
    if LC.unload then pcall(LC.unload); LC.unload = nil end
    local fn, err = load(text, "craft.lua")
    if not fn then LC.log("craft.lua syntax error: %s", tostring(err)) return end
    local ok, e = pcall(fn)
    if not ok then LC.log("craft.lua error: %s", tostring(e)) else LC.log("craft.lua (re)loaded") end
end

local function runDev()
    local text = readFile(LC.dir .. "dev.lua")
    if not text or text == LC.devText then return end
    LC.devText = text
    local fn, err = load(text, "dev.lua")
    if not fn then LC.log("dev.lua syntax error: %s", tostring(err)) return end
    local ok, e = pcall(fn)
    LC.log("dev.lua %s", ok and "ran" or ("error: " .. tostring(e)))
end

-- ------------------------------------------------------------------ the frame
local TICK = "/Game/FirstPersonBP/Blueprints/FirstPersonPlayerController.FirstPersonPlayerController_C:ReceiveTick"
local sinceFiles, sinceTick, sinceKeys = 0, 0, 0

local function frame(self, dtParam)
    local dt = 0.016
    pcall(function() dt = dtParam:get() end)
    LC.now = LC.now + dt
    sinceFiles, sinceTick, sinceKeys = sinceFiles + dt, sinceTick + dt, sinceKeys + dt

    if sinceFiles > 1.0 then sinceFiles = 0; loadCraft(); runDev() end

    -- timers
    if #LC.timers > 0 then
        local due, keep = {}, {}
        for _, t in ipairs(LC.timers) do if t.at <= LC.now then due[#due + 1] = t else keep[#keep + 1] = t end end
        LC.timers = keep
        for _, t in ipairs(due) do local ok, e = pcall(t.fn); if not ok then LC.log("timer error: %s", tostring(e)) end end
    end

    if sinceKeys > 0.03 then
        sinceKeys = 0
        local ok, pc = pcall(function() return self:get() end)
        if ok and pc and pc:IsValid() then pollKeys(pc) end
    end

    if LC.tickFn and sinceTick > 0.05 then
        sinceTick = 0
        local ok, e = pcall(LC.tickFn)
        if not ok then LC.log("tick error: %s", tostring(e)); LC.tickFn = nil end
    end
end

-- The game's controller Blueprint is not loaded when the mod starts, so install the hook as soon as it exists.
local function tryHook()
    if LC.hooked then return true end
    local ok = pcall(RegisterHook, TICK, frame)
    if ok then LC.hooked = true; LC.log("frame hook installed") end
    return ok
end
if not tryHook() then
    NotifyOnNewObject("/Script/Engine.PlayerController", function() tryHook() end)
    LC.log("frame hook deferred until the player controller exists")
end

LC.log("framework ready, dir=%s", LC.dir)
