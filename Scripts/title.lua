-- The start flow: the credits screen (split between Lushfoil / Annapurna and Minecraft / Mojang), then the LushfoilCraft screen where you pick a
-- map and a world (or name a new one). Its own file because craft.lua is at Lua's limit of 200 local variables in one function.
local C = ...
local log, texture, getPC, world = C.log, C.texture, C.getPC, C.world
local WBL, WLL, UW, canvasClass, imageClass, textClass = C.WBL, C.WLL, C.UW, C.canvasClass, C.imageClass, C.textClass
local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")

LC.title = LC.title or { active = false, stage = "credits", shown = false }
local T = LC.title

-- the nine places in the game, each with its own worlds
local MAPS = {
    { level = "Lagodibraies", name = "lake braies", sub = "dolomites, italy" },
    { level = "Chamonix", name = "chamonix", sub = "french alps" },
    { level = "iceland", name = "iceland", sub = "south coast" },
    { level = "FushimiInari", name = "fushimi inari", sub = "kyoto, japan" },
    { level = "CastleRockBeach", name = "castle rock beach", sub = "pacific coast" },
    { level = "MardiHimalTrail", name = "mardi himal trail", sub = "himalaya, nepal" },
    { level = "ShengshanIsland", name = "shengshan island", sub = "zhoushan, china" },
    { level = "SyonPark", name = "syon park", sub = "london, england" },
    { level = "Yamadera", name = "yamadera", sub = "yamagata, japan" },
}
T.maps = MAPS
local CREDITS_SECONDS = 7

local ui = LC.titleUI
local function worldsOfMap(m)
    local out = {}
    for _, w in ipairs(LC.worlds or {}) do if w.level == m.level then out[#out + 1] = w end end
    table.sort(out, function(a, b) return a.stamp > b.stamp end)
    return out
end

local function gameFont()
    local f = StaticFindObject("/Game/FirstPersonBP/menu/MenuStyle1.MenuStyle1")
    if f and f:IsValid() then return f end
end
local function annapurna()
    local t = StaticFindObject("/Game/FirstPersonBP/HomeMenu/annapurna-og-image.annapurna-og-image")
    if t and t:IsValid() then return t end
end

local function curLevel() local w = world(); return (w and w:IsValid()) and w:GetFName():ToString() or "?" end

local function build()
    local pc = getPC()
    if not pc then return end
    local w = WBL:Create(world(), UW, pc)
    if not (w and w:IsValid()) then return end
    local tree = w.WidgetTree
    local canvas = StaticConstructObject(canvasClass, tree, FName("lc_title_canvas"))
    tree.RootWidget = canvas
    local function add(widget) local s = canvas:AddChildToCanvas(widget); s:SetAutoSize(false); return s end
    local function image(tex) local i = StaticConstructObject(imageClass, tree); if tex then i:SetBrushFromTexture(tex, false) end; return i, add(i) end
    local function text(just) local t = StaticConstructObject(textClass, tree); t:SetJustification(just or 0); t:SetShadowOffset({ X = 1, Y = 1 }); t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 }); return t, add(t) end
    local white = texture("white")
    ui = { w = w, vis = {}, mapRow = {}, worldRow = {} }
    ui.dim, ui.dimS = image(white)
    ui.logo, ui.logoS = image(texture("lc_logo"))
    ui.hMaps, ui.hMapsS = text(0); ui.hWorlds, ui.hWorldsS = text(0)
    ui.hMaps:SetText(FText("choose a map")); ui.hWorlds:SetText(FText("choose a world"))
    local function row()
        local r = {}
        r.out, r.outS = image(white); r.out:SetColorAndOpacity({ R = 0.27, G = 0.75, B = 0.84, A = 1 })
        r.box, r.boxS = image(white); r.box:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.9 })
        r.txt, r.txtS = text(0); r.cnt, r.cntS = text(2)
        return r
    end
    for i = 1, #MAPS do ui.mapRow[i] = row() end
    for i = 1, 10 do ui.worldRow[i] = row() end
    ui.footer, ui.footerS = text(1)
    ui.hint, ui.hintS = text(1)
    ui.credits, ui.creditsS = image(texture("lc_credits"))
    -- the left half of the credits is the game's own launch scene text: its font, its words, its publisher logo
    ui.cDim, ui.cDimS = image(white); ui.cDim:SetColorAndOpacity({ R = 0.01, G = 0.02, B = 0.015, A = 0.97 })
    ui.cLabelBox, ui.cLabelBoxS = image(white); ui.cLabelBox:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.92 })
    ui.cLabel, ui.cLabelS = text(1); ui.cLabel:SetText(FText("lushfoil photography sim"))
    ui.cTxt1, ui.cTxt1S = text(1); ui.cTxt1:SetText(FText("Created by Matt Newell"))
    ui.cTxt2, ui.cTxt2S = text(1); ui.cTxt2:SetText(FText("published by"))
    ui.cLogo, ui.cLogoS = image(annapurna() or white)
    ui.veil, ui.veilS = image(white); ui.veil:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 1 })
    w:AddToViewport(1000)
    ui.w:SetVisibility(3)
    LC.titleUI = ui
end

local function vis(widget, key, v)
    if ui.vis[key] ~= v then ui.vis[key] = v; widget:SetVisibility(v and 3 or 1) end
end

local function setInput(on)
    local pc = getPC()
    if not pc then return end
    if on then
        pc.bShowMouseCursor = true
        pcall(function() WBL:SetInputMode_GameAndUIEx(pc, nil, 0, false, false) end)
        pcall(function() pc:SetIgnoreMoveInput(true); pc:SetIgnoreLookInput(true) end)
    else
        pc.bShowMouseCursor = false
        pcall(function() WBL:SetInputMode_GameOnly(pc, false) end)
        pcall(function() pc:SetIgnoreMoveInput(false); pc:SetIgnoreLookInput(false) end)
    end
end

function T.reset() ui = nil; LC.titleUI = nil end          -- a new level destroyed the widget

-- ---- opening and closing
function T.open(stage)
    if LC.readIndex then LC.readIndex() end
    T.stage = stage or "main"
    T.hadMenu = LC.menuUp and true or false          -- opened from the game's pause menu: that menu keeps the mouse when this closes
    T.stageT = LC.now
    T.active = true; T.typing = false; T.focus = "maps"; T.name = ""
    local lvl = curLevel()
    T.mapSel = 1
    for i, m in ipairs(MAPS) do if m.level == lvl then T.mapSel = i end end
    T.worldSel = 1
    T.fade = nil
    if not (ui and ui.w and ui.w:IsValid()) then ui = nil; build() end
    setInput(true)
    log("title: %s screen", T.stage)
end

local function close()
    T.active = false; T.typing = false
    if ui and ui.w and ui.w:IsValid() then ui.w:SetVisibility(1) end
    if T.hadMenu then
        local pc = getPC()
        if pc then pcall(function() pc:SetIgnoreMoveInput(false); pc:SetIgnoreLookInput(false) end) end
    else setInput(false) end
end

-- start playing: the chosen world of the chosen map (a new one when worldId is nil)
local function play(mi, worldId, newName)
    local m = MAPS[mi]
    LC.pending = { level = m.level, id = worldId, name = newName }
    close()
    log("title: play %s world=%s name=%s", m.level, tostring(worldId), tostring(newName))
    if curLevel() == m.level then
        if LC.applyPending then LC.applyPending() end
    else
        local pc = getPC()
        pcall(function() KSL:ExecuteConsoleCommand(world(), "open /Game/" .. m.level, pc) end)
    end
end

-- ---- selection (shared by mouse, keyboard and controller)
local function worldRows()
    local m = MAPS[T.mapSel]
    local list = worldsOfMap(m)
    return list, #list + 1                      -- the last row is "new world"
end

local function activateWorld(j)
    local list, n = worldRows()
    if j < n then play(T.mapSel, list[j].id)
    else T.focus = "name"; T.typing = true; T.name = ""; T.worldSel = n end
end

local function activateMap(i)
    T.mapSel = i; T.focus = "worlds"; T.worldSel = 1
end

function T.confirm()
    if T.stage == "credits" then T.advance() return end
    if T.focus == "maps" then activateMap(T.mapSel)
    elseif T.focus == "worlds" then activateWorld(T.worldSel)
    elseif T.focus == "name" then
        local nm = (T.name:gsub("^%s+", ""):gsub("%s+$", ""))
        if nm == "" then local _, n = worldRows(); nm = MAPS[T.mapSel].name .. " " .. n end
        play(T.mapSel, nil, nm)
    end
end
function T.back()
    if T.stage == "credits" then T.advance() return end
    if T.focus == "name" then T.focus = "worlds"; T.typing = false
    elseif T.focus == "worlds" then T.focus = "maps"
    elseif LC.worldId then close() end          -- reopened from the pause menu: back to the game
end
function T.move(d)
    if T.stage == "credits" then return end
    if T.focus == "maps" then T.mapSel = (T.mapSel - 1 + d) % #MAPS + 1; T.worldSel = 1
    elseif T.focus == "worlds" then local _, n = worldRows(); T.worldSel = (T.worldSel - 1 + d) % n + 1 end
end
function T.advance()
    if T.stage == "credits" then T.stage = "main"; T.stageT = LC.now; T.fade = LC.now end
end

function T.char(ch) if T.typing and #T.name < 28 then T.name = T.name .. ch end end
function T.key(k)
    if k == "BackSpace" then T.name = T.name:sub(1, -2)
    elseif k == "Enter" then T.confirm()
    elseif k == "Escape" then T.back() end
end

-- ---- layout (reference 1920 x 1080, scaled to fit, positions in Slate units)
local function geometry()
    local vs = WLL:GetViewportSize(world())
    local dpi = WLL:GetViewportScale(world())
    if dpi <= 0 then dpi = 1 end
    local W, H = vs.X / dpi, vs.Y / dpi
    local k = math.min(W / 1920, H / 1080)
    return W, H, k, (W - 1920 * k) / 2, (H - 1080 * k) / 2
end

local ROWH, ROWGAP, LISTY = 48, 7, 486
local function rowRect(col, i, k, ox, oy)
    local x = col == 1 and 300 or 1080
    return ox + x * k, oy + (LISTY + (i - 1) * (ROWH + ROWGAP)) * k, 540 * k, ROWH * k
end

local function font(t, size) local f = t.Font; f.Size = size; local gf = gameFont(); if gf then f.FontObject = gf end; t:SetFont(f) end

local function setRow(r, key, x, y, w, h, label, count, selected, hot, dim, k)
    local show = label ~= nil
    vis(r.box, key .. "b", show); vis(r.txt, key .. "t", show); vis(r.cnt, key .. "c", show and count ~= "")
    vis(r.out, key .. "o", show and (selected or hot))
    if not show then return end
    r.outS:SetPosition({ X = x - 3, Y = y - 3 }); r.outS:SetSize({ X = w + 6, Y = h + 6 })
    r.boxS:SetPosition({ X = x, Y = y }); r.boxS:SetSize({ X = w, Y = h })
    r.txtS:SetPosition({ X = x + 18 * k, Y = y + h * 0.2 }); r.txtS:SetSize({ X = w * 0.7, Y = h })
    r.cntS:SetPosition({ X = x + w * 0.55, Y = y + h * 0.28 }); r.cntS:SetSize({ X = w * 0.42, Y = h })
    if r.label ~= label then r.label = label; r.txt:SetText(FText(label)) end
    if r.count ~= count then r.count = count; r.cnt:SetText(FText(count)) end
    local fs = math.floor(h * 0.42)
    if r.fs ~= fs then r.fs = fs; font(r.txt, fs); font(r.cnt, math.floor(fs * 0.72)) end
    r.box:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = hot and 0.97 or 0.88 })
    r.txt:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = dim and 0.55 or 1 }, ColorUseRule = 0 })
    r.cnt:SetColorAndOpacity({ SpecifiedColor = { R = 0.7, G = 0.74, B = 0.76, A = 1 }, ColorUseRule = 0 })
end

local lastClick = -1
function T.click()
    if not (T.active and ui) then return false end
    if T.stage == "credits" then T.advance() return true end
    if LC.now - lastClick < 0.25 then return true end
    local mp = WLL:GetMousePositionOnViewport(world())
    local W, H, k, ox, oy = geometry()
    for i = 1, #MAPS do
        local x, y, w, h = rowRect(1, i, k, ox, oy)
        if mp.X >= x and mp.X <= x + w and mp.Y >= y and mp.Y <= y + h then lastClick = LC.now; activateMap(i); return true end
    end
    local _, n = worldRows()
    for j = 1, n do
        local x, y, w, h = rowRect(2, j, k, ox, oy)
        if mp.X >= x and mp.X <= x + w and mp.Y >= y and mp.Y <= y + h then
            lastClick = LC.now; T.worldSel = j; T.focus = "worlds"; activateWorld(j); return true
        end
    end
    return true
end

-- ---- per-frame drawing
function T.tick()
    if not T.active then return end
    if LC.now - (T.inputT or -10) > 0.3 then
        T.inputT = LC.now
        local pc = getPC()
        if pc and pc:IsValid() and not pc.bShowMouseCursor then setInput(true) end
    end
    if not (ui and ui.w and ui.w:IsValid()) then ui = nil; build(); if not ui then return end end
    local W, H, k, ox, oy = geometry()
    local credits = T.stage == "credits"
    if credits and LC.now - (T.stageT or LC.now) > CREDITS_SECONDS then T.advance(); credits = false end
    -- fades between the two screens
    local fade = 0
    local ft = LC.now - (T.stageT or LC.now)
    if credits then fade = ft < 0.5 and 1 - ft / 0.5 or (ft > CREDITS_SECONDS - 0.5 and 1 - (CREDITS_SECONDS - ft) / 0.5 or 0)
    else fade = ft < 0.5 and 1 - ft / 0.5 or 0 end
    local key = W .. "x" .. H .. T.stage
    local relayout = ui.key ~= key
    ui.key = key
    vis(ui.credits, "credits", credits)
    for _, k_ in ipairs({ "cDim", "cLabelBox", "cLabel", "cTxt1", "cTxt2", "cLogo" }) do vis(ui[k_], k_, credits) end
    if relayout then
        -- cover the whole viewport with the credits picture
        local s = math.max(W / 1920, H / 1080)
        ui.creditsS:SetSize({ X = 1920 * s, Y = 1080 * s }); ui.creditsS:SetPosition({ X = (W - 1920 * s) / 2, Y = (H - 1080 * s) / 2 })
        ui.cDimS:SetPosition({ X = 0, Y = 0 }); ui.cDimS:SetSize({ X = W / 2, Y = H })
        local cx = W / 4                                              -- centre of the left half
        local function centre(slot, y, h, w) slot:SetPosition({ X = cx - w / 2, Y = y }); slot:SetSize({ X = w, Y = h }) end
        centre(ui.cLabelBoxS, oy + 236 * k, 62 * k, 520 * k); centre(ui.cLabelS, oy + 248 * k, 46 * k, 520 * k); font(ui.cLabel, math.floor(30 * k))
        centre(ui.cTxt1S, oy + 400 * k, 80 * k, 900 * k); font(ui.cTxt1, math.floor(54 * k))
        centre(ui.cTxt2S, oy + 580 * k, 60 * k, 600 * k); font(ui.cTxt2, math.floor(34 * k))
        centre(ui.cLogoS, oy + 650 * k, 260 * k, 260 * k)
        ui.dimS:SetPosition({ X = 0, Y = 0 }); ui.dimS:SetSize({ X = W, Y = H })
        ui.veilS:SetPosition({ X = 0, Y = 0 }); ui.veilS:SetSize({ X = W, Y = H })
        local lw = 980 * k
        ui.logoS:SetSize({ X = lw, Y = lw * 992 / 1920 }); ui.logoS:SetPosition({ X = ox + 960 * k - lw / 2, Y = oy + 10 * k })
        ui.hMapsS:SetPosition({ X = ox + 300 * k, Y = oy + (LISTY - 50) * k }); ui.hMapsS:SetSize({ X = 540 * k, Y = 40 * k })
        ui.hWorldsS:SetPosition({ X = ox + 1080 * k, Y = oy + (LISTY - 50) * k }); ui.hWorldsS:SetSize({ X = 540 * k, Y = 40 * k })
        font(ui.hMaps, math.floor(26 * k)); font(ui.hWorlds, math.floor(26 * k))
        ui.footerS:SetPosition({ X = 0, Y = oy + 1030 * k }); ui.footerS:SetSize({ X = W, Y = 40 * k }); font(ui.footer, math.floor(21 * k))
        ui.hintS:SetPosition({ X = 0, Y = oy + 994 * k }); ui.hintS:SetSize({ X = W, Y = 36 * k }); font(ui.hint, math.floor(22 * k))
        for _, r in ipairs(ui.mapRow) do r.fs = nil end
        for _, r in ipairs(ui.worldRow) do r.fs = nil end
    end
    if credits then
        vis(ui.dim, "dim", false); vis(ui.logo, "logo", false); vis(ui.hMaps, "hm", false); vis(ui.hWorlds, "hw", false)
        vis(ui.footer, "foot", false); vis(ui.hint, "hint", false)
        for i = 1, #MAPS do setRow(ui.mapRow[i], "m" .. i, 0, 0, 0, 0, nil, "", false, false, false, k) end
        for j = 1, 10 do setRow(ui.worldRow[j], "w" .. j, 0, 0, 0, 0, nil, "", false, false, false, k) end
    else
        vis(ui.dim, "dim", true); ui.dim:SetColorAndOpacity({ R = 0.02, G = 0.04, B = 0.03, A = 0.84 })
        vis(ui.logo, "logo", true); vis(ui.hMaps, "hm", true); vis(ui.hWorlds, "hw", T.focus ~= "maps")
        vis(ui.footer, "foot", true); vis(ui.hint, "hint", true)
        if not ui.footerSet then
            ui.footerSet = true
            ui.footer:SetText(FText("an unofficial fan mod - not affiliated with Matt Newell, Annapurna Interactive, Mojang Studios or Microsoft"))
            ui.footer:SetColorAndOpacity({ SpecifiedColor = { R = 0.85, G = 0.88, B = 0.86, A = 1 }, ColorUseRule = 0 })
            ui.hMaps:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 })
            ui.hWorlds:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 })
            ui.hint:SetColorAndOpacity({ SpecifiedColor = { R = 0.7, G = 0.8, B = 0.84, A = 1 }, ColorUseRule = 0 })
        end
        local hintText = T.focus == "maps" and "click or press enter on a map     arrows move     (pad: d-pad, a)"
            or (T.focus == "name" and "type a name for the new world, then enter     escape goes back" or "click a world to play it, or make a new one     escape goes back")
        if ui.hintText ~= hintText then ui.hintText = hintText; ui.hint:SetText(FText(hintText)) end
        local mp = WLL:GetMousePositionOnViewport(world())
        -- the mouse only moves the selection when it actually moves
        local moved = ui.lastMx == nil or math.abs(mp.X - ui.lastMx) + math.abs(mp.Y - ui.lastMy) > 2
        ui.lastMx, ui.lastMy = mp.X, mp.Y
        for i, m in ipairs(MAPS) do
            local x, y, w, h = rowRect(1, i, k, ox, oy)
            local hover = moved and mp.X >= x and mp.X <= x + w and mp.Y >= y and mp.Y <= y + h
            if hover and T.focus == "maps" then T.mapSel = i end
            local n = #worldsOfMap(m)
            setRow(ui.mapRow[i], "m" .. i, x, y, w, h, m.name, n == 0 and "" or (n .. (n == 1 and " world" or " worlds")), T.mapSel == i, hover, false, k)
        end
        local list, n = worldRows()
        for j = 1, 10 do
            if T.focus ~= "maps" and j <= n then
                local x, y, w, h = rowRect(2, j, k, ox, oy)
                local hover = moved and mp.X >= x and mp.X <= x + w and mp.Y >= y and mp.Y <= y + h
                if hover and T.focus ~= "name" then T.worldSel = j; T.focus = "worlds" end
                local label, count
                if j < n then label, count = list[j].name, list[j].count .. " blocks"
                elseif T.focus == "name" then label = "name:  " .. T.name .. ((math.floor(LC.now * 2) % 2 == 0) and "_" or " "); count = ""
                else label, count = "+  new world", "" end
                setRow(ui.worldRow[j], "w" .. j, x, y, w, h, label, count, T.worldSel == j, hover, false, k)
            else
                setRow(ui.worldRow[j], "w" .. j, 0, 0, 0, 0, nil, "", false, false, false, k)
            end
        end
    end
    vis(ui.veil, "veil", fade > 0.01)
    if fade > 0.01 then ui.veil:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = fade }) end
end

-- the very first thing after the game starts: once the game's own launch scene is over, the credits, then the LushfoilCraft screen
local function launchUp()
    if LC.now - (T.lt or -10) < 0.5 then return T.lu end
    T.lt = LC.now
    local lw = FindFirstOf("MenuLaunchAnim_C")
    T.lu = (lw and lw:IsValid() and lw:IsInViewport()) and true or false
    return T.lu
end
function LC.titleBoot()
    -- the game's own launch scene and credits stay exactly as they are; the map / world screen opens on request (pause menu, or F9)
    T.shown = true
end

LC.titleTick = T.tick
LC.titleKill = function()
    if ui and ui.w and ui.w:IsValid() then pcall(function() ui.w:RemoveFromParent() end) end
    ui = nil; LC.titleUI = nil
end
