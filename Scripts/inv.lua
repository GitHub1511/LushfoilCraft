-- The inventory screen (E, or Y on a controller). Its own file because craft.lua is at Lua's limit of 200 local variables in one function;
-- craft.lua loads this and hands over the pieces it needs.
local C = ...
local log, texture, getPC, world, pcpawn = C.log, C.texture, C.getPC, C.world, C.pcpawn
local WBL, WLL, UW, canvasClass, imageClass, textClass = C.WBL, C.WLL, C.UW, C.canvasClass, C.imageClass, C.textClass
local blocks, itemList, byName, maxStack, iconTexture, displayName, updateHeld = C.blocks, C.itemList, C.byName, C.maxStack, C.iconTexture, C.displayName, C.updateHeld

-- ---- the inventory screen (E, or Y on a controller): the survival inventory with your 36 slots and Steve, or the creative item browser
-- with search, scrolling, a trash slot and an inventory tab. Layouts are in Minecraft's own GUI pixels, drawn at the HUD's GUI scale.
LC.inv = LC.inv or { open = false, view = "survival", cursor = nil, scroll = 0, search = "", sel = 1, typing = false }
LC.cinv = LC.cinv or {}                         -- creative inventory tab: 27 storage slots (stacks); the creative hotbar is LC.hot / LC.hotItem
local INV = LC.inv
local invAllCache
local function invAll()
    if invAllCache then return invAllCache end
    local list, seen = {}, {}
    for _, d in ipairs(blocks) do list[#list + 1] = { kind = "block", name = d[1] }; seen[d[1]] = true end
    for _, n in ipairs(itemList) do if not seen[n] then list[#list + 1] = { kind = "item", name = n } end end
    invAllCache = list
    return list
end
local function invFiltered()
    local all, q = invAll(), INV.search:lower()
    if q == "" then return all end
    if INV.filterQ == q and INV.filtered then return INV.filtered end
    local out = {}
    for _, e in ipairs(all) do if e.name:find(q, 1, true) then out[#out + 1] = e end end
    INV.filterQ, INV.filtered = q, out
    return out
end

-- layouts: slots are { kind, index, x, y } in GUI pixels from the panel's top-left
local function layoutFor(view)
    local s = {}
    if view == "survival" then
        for c = 0, 8 do s[#s + 1] = { "inv", c + 1, 8 + 18 * c, 142 } end
        for r = 0, 2 do for c = 0, 8 do s[#s + 1] = { "inv", 10 + r * 9 + c, 8 + 18 * c, 84 + 18 * r } end end
        for i = 0, 3 do s[#s + 1] = { "dead", 0, 8, 8 + 18 * i } end                        -- armour: no armour items yet
        s[#s + 1] = { "dead", 0, 77, 62 }
        for r = 0, 1 do for c = 0, 1 do s[#s + 1] = { "dead", 0, 98 + 18 * c, 18 + 18 * r } end end
        s[#s + 1] = { "dead", 0, 154, 28 }                                                 -- crafting is not implemented
        return s, 176, 166
    elseif view == "items" then
        for r = 0, 4 do for c = 0, 8 do s[#s + 1] = { "grid", r * 9 + c + 1, 9 + 18 * c, 18 + 18 * r } end end
        for c = 0, 8 do s[#s + 1] = { "hot", c + 1, 9 + 18 * c, 112 } end
        return s, 195, 136
    else
        for r = 0, 2 do for c = 0, 8 do s[#s + 1] = { "cmain", r * 9 + c + 1, 9 + 18 * c, 54 + 18 * r } end end
        for c = 0, 8 do s[#s + 1] = { "hot", c + 1, 9 + 18 * c, 112 } end
        s[#s + 1] = { "trash", 0, 173, 112 }
        for _, p in ipairs({ { 54, 6 }, { 54, 33 }, { 108, 6 }, { 108, 33 }, { 35, 20 } }) do s[#s + 1] = { "dead", 0, p[1], p[2] } end
        return s, 195, 136
    end
end

local invUI
local function invBuild()
    local pc = getPC()
    if not pc then return end
    local w = WBL:Create(world(), UW, pc)
    if not (w and w:IsValid()) then return end
    local tree = w.WidgetTree
    local canvas = StaticConstructObject(canvasClass, tree, FName("lc_inv_canvas"))
    tree.RootWidget = canvas
    local function add(widget) local sl = canvas:AddChildToCanvas(widget); sl:SetAutoSize(false); return sl end
    local function image(tex) local i = StaticConstructObject(imageClass, tree); i:SetBrushFromTexture(tex, false); return i, add(i) end
    local function text(just) local t = StaticConstructObject(textClass, tree); t:SetJustification(just or 0); t:SetShadowOffset({ X = 1, Y = 1 }); t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.9 }); return t, add(t) end
    local white = texture("white")
    local ui = { w = w, vis = {}, slotImg = {}, slotImgS = {}, slotTxt = {}, slotTxtS = {}, slotKey = {} }
    ui.dim, ui.dimS = image(white); ui.dim:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.62 })
    ui.panel = {}
    ui.panelS = {}
    for _, v in ipairs({ "survival", "items", "cinv" }) do
        local tn = v == "survival" and "inv_survival" or (v == "items" and "inv_search" or "inv_creative_inv")
        ui.panel[v], ui.panelS[v] = image(texture(tn))
    end
    ui.tabItems, ui.tabItemsS = image(texture("inv_tab_top_unselected_1")); ui.tabItemsSel, ui.tabItemsSelS = image(texture("inv_tab_top_selected_1"))
    ui.tabInv, ui.tabInvS = image(texture("inv_tab_bottom_unselected_7")); ui.tabInvSel, ui.tabInvSelS = image(texture("inv_tab_bottom_selected_7"))
    ui.tabItemsIcon, ui.tabItemsIconS = image(texture("icon_bricks") or texture("icon_empty"))
    ui.tabInvIcon, ui.tabInvIconS = image(texture("icon_chest") or texture("icon_empty"))
    ui.steve, ui.steveS = image(texture("gui_steve"))
    ui.scroll, ui.scrollS = image(texture("inv_scroller")); ui.scrollOff, ui.scrollOffS = image(texture("inv_scroller_disabled"))
    for i = 1, 54 do
        ui.slotImg[i], ui.slotImgS[i] = image(texture("icon_empty"))
        ui.slotTxt[i], ui.slotTxtS[i] = text(2)
    end
    ui.hl, ui.hlS = image(white); ui.hl:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.5 })
    ui.curImg, ui.curImgS = image(texture("icon_empty")); ui.curTxt, ui.curTxtS = text(2)
    ui.tipBg, ui.tipBgS = image(white); ui.tipBg:SetColorAndOpacity({ R = 0.06, G = 0.0, B = 0.1, A = 0.92 })
    ui.tip, ui.tipS = text(0)
    ui.search, ui.searchS = text(0)
    ui.title, ui.titleS = text(0)
    w:AddToViewport(60)
    ui.w:SetVisibility(1)
    invUI = ui
    LC.invUI = ui
end

local function ivis(widget, key, v)
    if invUI.vis[key] ~= v then invUI.vis[key] = v; widget:SetVisibility(v and 3 or 1) end
end

-- the stack shown in a slot
local function slotStack(kind, idx)
    if kind == "inv" then return LC.surv.inv[idx]
    elseif kind == "cmain" then return LC.cinv[idx]
    elseif kind == "hot" then return LC.stackAt(idx)
    elseif kind == "grid" then
        local list = invFiltered()
        local e = list[INV.scroll * 9 + idx]
        return e and { kind = e.kind, name = e.name, count = 1 } or nil
    end
end

local function invMouse()
    local mp = WLL:GetMousePositionOnViewport(world())
    local dpi = WLL:GetViewportScale(world())
    return mp.X * dpi, mp.Y * dpi
end

local function invGeometry(vs)
    local slots, pw, ph = layoutFor(INV.view)
    local gs = math.max(1, math.min(math.floor(vs.X / (pw + 40)), math.floor(vs.Y / (ph + 50))))
    local ox, oy = math.floor((vs.X - pw * gs) / 2), math.floor((vs.Y - ph * gs) / 2)
    return slots, pw, ph, gs, ox, oy
end

local function invSlotAt(slots, gs, ox, oy, mx, my)
    for n, sl in ipairs(slots) do
        local x, y = ox + (sl[3] - 1) * gs, oy + (sl[4] - 1) * gs
        if mx >= x and mx < x + 18 * gs and my >= y and my < y + 18 * gs then return n end
    end
end

local function invDropCursor()
    local cur = INV.cursor
    INV.cursor = nil
    if cur and LC.mode == "survival" then
        local pc, pawn = pcpawn()
        local l = pawn and pawn:K2_GetActorLocation()
        if l then LC.dropItem({ kind = cur.kind, name = cur.name, count = cur.count }, l) end
    end
end

local function invRefreshAll()
    if LC.hudRefresh then LC.hudRefresh() end
    if updateHeld then updateHeld() end
end

-- one click on a slot: button 0 = left, 1 = right
local function invClickSlot(sl, button, shift)
    local kind, idx = sl[1], sl[2]
    if kind == "dead" then return end
    local cur = INV.cursor
    if kind == "trash" then INV.cursor = nil return end
    if kind == "grid" then
        local st = slotStack("grid", idx)
        if cur then INV.cursor = nil return end                                 -- a held stack dropped on the browser disappears
        if st then
            local cap = maxStack(st)
            INV.cursor = { kind = st.kind, name = st.name, count = (button == 0) and cap or 1 }
        end
        return
    end
    if kind == "hot" and LC.mode ~= "survival" then
        -- creative hotbar slots hold "any block or item": put what the cursor carries there, or copy what is there onto the cursor
        if cur then
            if cur.kind == "block" then LC.hot[idx] = byName(cur.name) or LC.hot[idx]; LC.hotItem[idx] = nil else LC.hotItem[idx] = cur.name end
            INV.cursor = nil
        else
            local st = LC.stackAt(idx)
            if st then INV.cursor = { kind = st.kind, name = st.name, count = maxStack(st) } end
        end
        invRefreshAll()
        return
    end
    local store = (kind == "cmain") and LC.cinv or LC.surv.inv
    local st = store[idx]
    if shift and st and kind == "inv" then                                         -- shift-click: hotbar <-> storage
        local from9 = idx <= 9
        local lo, hi = from9 and 10 or 1, from9 and 36 or 9
        local inv = LC.surv.inv
        for pass = 1, 2 do
            for t = lo, hi do
                local o = inv[t]
                if pass == 1 and o and o.kind == st.kind and o.name == st.name and o.count < maxStack(st) then
                    local n = math.min(maxStack(st) - o.count, st.count); o.count = o.count + n; st.count = st.count - n
                    if st.count == 0 then inv[idx] = nil; invRefreshAll() return end
                elseif pass == 2 and not o then inv[t] = st; inv[idx] = nil; invRefreshAll() return end
            end
        end
        invRefreshAll()
        return
    end
    if not cur then
        if st then
            if button == 1 and st.count > 1 then
                local take = math.ceil(st.count / 2)
                INV.cursor = { kind = st.kind, name = st.name, count = take }; st.count = st.count - take
            else INV.cursor = st; store[idx] = nil end
        end
    else
        if not st then
            if button == 1 and cur.count > 1 then store[idx] = { kind = cur.kind, name = cur.name, count = 1 }; cur.count = cur.count - 1
            else store[idx] = cur; INV.cursor = nil end
        elseif st.kind == cur.kind and st.name == cur.name then
            local room = maxStack(st) - st.count
            local n = (button == 1) and math.min(1, room) or math.min(room, cur.count)
            st.count = st.count + n; cur.count = cur.count - n
            if cur.count <= 0 then INV.cursor = nil end
        else store[idx] = cur; INV.cursor = st end
    end
    invRefreshAll()
end

function LC.invClick(button)
    if not (INV.open and invUI) then return end
    if LC.now - (INV.clickT or -1) < 0.15 then return end
    INV.clickT = LC.now
    local vs = WLL:GetViewportSize(world())
    local slots, pw, ph, gs, ox, oy = invGeometry(vs)
    local shift = LC.down and (LC.down.LEFT_SHIFT or false)
    local n
    if INV.useMouse ~= false then
        local mx, my = invMouse()
        n = invSlotAt(slots, gs, ox, oy, mx, my)
        -- tabs (creative) and the scroll bar
        if not n and INV.view ~= "survival" then
            local tx, ty = ox + 0 * gs, oy - 28 * gs
            if mx >= tx and mx < tx + 26 * gs and my >= ty and my < ty + 32 * gs then INV.view = "items"; INV.useMouse = true return end
            local bx, by = ox + (195 - 26) * gs, oy + (ph - 4) * gs
            if mx >= bx and mx < bx + 26 * gs and my >= by and my < by + 32 * gs then INV.view = "cinv" return end
            if INV.view == "items" and mx >= ox + 82 * gs and mx < ox + 172 * gs and my >= oy + 5 * gs and my < oy + 17 * gs then INV.typing = true end
            if INV.view == "items" and mx >= ox + 174 * gs and mx < ox + 188 * gs and my >= oy + 17 * gs and my < oy + 131 * gs then INV.dragScroll = true end
        end
    else n = INV.sel end
    if n and slots[n] then invClickSlot(slots[n], button, shift) end
end

local function invShow(on)
    if not invUI then return end
    ivis(invUI.dim, "dim", on)
    if not on then
        for _, v in ipairs({ "survival", "items", "cinv" }) do ivis(invUI.panel[v], "p" .. v, false) end
        for i = 1, 54 do ivis(invUI.slotImg[i], "si" .. i, false); ivis(invUI.slotTxt[i], "st" .. i, false) end
        for _, k in ipairs({ "tabItems", "tabItemsSel", "tabInv", "tabInvSel", "tabItemsIcon", "tabInvIcon", "steve", "scroll", "scrollOff", "hl", "curImg", "curTxt", "tipBg", "tip", "search", "title" }) do ivis(invUI[k], k, false) end
    end
end

function LC.invOpen()
    if LC.camUp then return end
    if INV.open or not LC.hudOn or (LC.chat and LC.chat.open) then return end
    if not invUI or not (invUI.w and invUI.w:IsValid()) then invUI = nil; invBuild() end
    if not invUI then return end
    INV.open = true
    INV.view = (LC.mode == "survival") and "survival" or "items"
    INV.cursor, INV.scroll, INV.search, INV.sel, INV.filterQ, INV.typing = nil, 0, "", 1, nil, false
    INV.useMouse = true; INV.gkey = nil
    invUI.w:SetVisibility(3)
    local pc = getPC()
    if pc then
        pc.bShowMouseCursor = true
        pcall(function() WBL:SetInputMode_GameAndUIEx(pc, nil, 0, false, false) end)
        pcall(function() pc:SetIgnoreMoveInput(true); pc:SetIgnoreLookInput(true) end)
    end
    log("inventory opened (%s)", INV.view)
end

function LC.invReset() invUI = nil; LC.invUI = nil; INV.open = false; INV.cursor = nil end   -- a new level destroyed the widget

function LC.invClose()
    if not INV.open then return end
    INV.open = false
    invDropCursor()
    invShow(false)
    local pc = getPC()
    if pc then
        pc.bShowMouseCursor = false
        pcall(function() WBL:SetInputMode_GameOnly(pc, false) end)
        pcall(function() pc:SetIgnoreMoveInput(false); pc:SetIgnoreLookInput(false) end)
    end
    invRefreshAll()
    log("inventory closed")
end
function LC.invToggle() if INV.open then LC.invClose() else LC.invOpen() end end

-- controller: move the highlighted slot to the nearest slot in a direction
function LC.invNav(dx, dy)
    if not INV.open then return end
    local slots = layoutFor(INV.view)
    local cur = slots[INV.sel] or slots[1]
    local best, bd
    for n, sl in ipairs(slots) do
        if sl[1] ~= "dead" and n ~= INV.sel then
            local ddx, ddy = sl[3] - cur[3], sl[4] - cur[4]
            if (dx ~= 0 and ddx * dx > 0 and math.abs(ddy) < 14) or (dy ~= 0 and ddy * dy > 0 and math.abs(ddx) < 14) then
                local d = ddx * ddx + ddy * ddy
                if not bd or d < bd then best, bd = n, d end
            end
        end
    end
    if best then INV.sel = best elseif dy ~= 0 and INV.view == "items" then LC.invScroll(dy > 0 and 1 or -1) end
    INV.useMouse = false
end
function LC.invTab(delta)
    if not INV.open or INV.view == "survival" then return end
    INV.view = (INV.view == "items") and "cinv" or "items"
    INV.sel = 1; INV.typing = false
end
function LC.invScroll(delta)
    if INV.open and INV.view == "items" then
        local rows = math.ceil(#invFiltered() / 9)
        INV.scroll = math.max(0, math.min(math.max(0, rows - 5), INV.scroll + delta))
    end
end
-- typing in the creative search box (any letter while the item browser is open)
function LC.invType(ch) if INV.open and INV.view == "items" then INV.search = INV.search .. ch; INV.scroll = 0 end end
function LC.invBack() if INV.open and INV.view == "items" then INV.search = INV.search:sub(1, -2); INV.scroll = 0 end end

-- per-tick drawing
local invDragAdjust
LC.invTick = function()
    if not INV.open then return end
    if not invUI or not (invUI.w and invUI.w:IsValid()) then INV.open = false return end
    -- leaving the game (a menu came up) closes the screen
    if not LC.hudOn and not INV.open then return end
    local vs = WLL:GetViewportSize(world())
    local dpi = WLL:GetViewportScale(world())
    if dpi <= 0 then dpi = 1 end
    local slots, pw, ph, gs, ox, oy = invGeometry(vs)
    local function put(slot, x, y, w, h) slot:SetPosition({ X = x / dpi, Y = y / dpi }); slot:SetSize({ X = w / dpi, Y = h / dpi }) end
    local function font(t, size) local f = t.Font; f.Size = size; t:SetFont(f) end
    local gkey = vs.X .. "x" .. vs.Y .. INV.view .. INV.scroll .. dpi
    local relayout = INV.gkey ~= gkey
    INV.gkey = gkey
    local function putL(slot, x, y, w, h) if relayout then put(slot, x, y, w, h) end end
    local function fontL(t, size) if relayout then font(t, size) end end
    ivis(invUI.dim, "dim", true)
    putL(invUI.dimS, 0, 0, vs.X, vs.Y)
    for _, v in ipairs({ "survival", "items", "cinv" }) do
        local show = INV.view == v
        ivis(invUI.panel[v], "p" .. v, show)
        if show then putL(invUI.panelS[v], ox, oy, pw * gs, ph * gs) end
    end
    local creative = INV.view ~= "survival"
    -- tabs (creative)
    ivis(invUI.tabItems, "tabItems", creative and INV.view ~= "items"); ivis(invUI.tabItemsSel, "tabItemsSel", creative and INV.view == "items")
    ivis(invUI.tabInv, "tabInv", creative and INV.view ~= "cinv"); ivis(invUI.tabInvSel, "tabInvSel", creative and INV.view == "cinv")
    ivis(invUI.tabItemsIcon, "tabItemsIcon", creative); ivis(invUI.tabInvIcon, "tabInvIcon", creative)
    if creative then
        local ty = oy - 28 * gs
        putL(invUI.tabItemsS, ox, ty, 26 * gs, 32 * gs); putL(invUI.tabItemsSelS, ox, ty, 26 * gs, 32 * gs)
        putL(invUI.tabItemsIconS, ox + 5 * gs, ty + 9 * gs, 16 * gs, 16 * gs)
        local by = oy + (ph - 4) * gs
        putL(invUI.tabInvS, ox + (195 - 26) * gs, by, 26 * gs, 32 * gs); putL(invUI.tabInvSelS, ox + (195 - 26) * gs, by, 26 * gs, 32 * gs)
        putL(invUI.tabInvIconS, ox + (195 - 26) * gs + 5 * gs, by + 7 * gs, 16 * gs, 16 * gs)
    end
    -- Steve
    ivis(invUI.steve, "steve", INV.view ~= "items")
    if INV.view == "survival" then putL(invUI.steveS, ox + 35 * gs, oy + 11 * gs, 32 * gs, 64 * gs)
    elseif INV.view == "cinv" then putL(invUI.steveS, ox + 77 * gs, oy + 5 * gs, 22 * gs, 44 * gs) end
    -- titles and the search box
    ivis(invUI.search, "search", INV.view == "items"); ivis(invUI.title, "title", true)
    fontL(invUI.search, math.floor(6 * gs / dpi * 1.33)); fontL(invUI.title, math.floor(6 * gs / dpi * 1.33))
    if INV.view == "items" then
        local q = INV.search .. ((math.floor(LC.now * 2) % 2 == 0) and "_" or "")
        if INV.searchShown ~= q then INV.searchShown = q; invUI.search:SetText(FText(q)) end
        putL(invUI.searchS, ox + 83 * gs, oy + 6 * gs, 88 * gs, 10 * gs)
        invUI.title:SetText(FText("Search Items"))
        putL(invUI.titleS, ox + 8 * gs, oy + 6 * gs, 80 * gs, 10 * gs)
    elseif INV.view == "survival" then
        invUI.title:SetText(FText("Crafting")); putL(invUI.titleS, ox + 97 * gs, oy + 6 * gs, 60 * gs, 10 * gs)
    else
        invUI.title:SetText(FText("Inventory")); putL(invUI.titleS, ox + 8 * gs, oy + 6 * gs, 50 * gs, 10 * gs)
    end
    invUI.title:SetColorAndOpacity({ SpecifiedColor = { R = 0.25, G = 0.25, B = 0.25, A = 1 }, ColorUseRule = 0 })
    invUI.search:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 })
    -- scroll bar
    local rows = math.ceil(#invFiltered() / 9)
    local canScroll = INV.view == "items" and rows > 5
    ivis(invUI.scroll, "scroll", INV.view == "items" and canScroll); ivis(invUI.scrollOff, "scrollOff", INV.view == "items" and not canScroll)
    if INV.view == "items" then
        local frac = canScroll and INV.scroll / (rows - 5) or 0
        local sy = oy + (18 + frac * (112 - 15)) * gs
        putL(invUI.scrollS, ox + 175 * gs, sy, 12 * gs, 15 * gs); putL(invUI.scrollOffS, ox + 175 * gs, oy + 18 * gs, 12 * gs, 15 * gs)
        if INV.dragScroll and canScroll then
            if LC.down and LC.down.LEFT_MOUSE_BUTTON then
                local _, my = invMouse()
                local f = math.max(0, math.min(1, (my - oy - 18 * gs - 7 * gs) / (97 * gs)))
                INV.scroll = math.floor(f * (rows - 5) + 0.5)
            else INV.dragScroll = false end
        end
    end
    -- slots
    local mx, my = invMouse()
    if INV.lastMx and (math.abs(mx - INV.lastMx) + math.abs(my - INV.lastMy) > 3) then INV.useMouse = true end
    INV.lastMx, INV.lastMy = mx, my
    local hover = (INV.useMouse ~= false) and invSlotAt(slots, gs, ox, oy, mx, my) or ((INV.useMouse == false) and INV.sel or nil)
    local nImg = 0
    for n, sl in ipairs(slots) do
        local kind = sl[1]
        local st = slotStack(kind, sl[2])
        nImg = nImg + 1
        local img = invUI.slotImg[nImg]
        if nImg <= 54 and kind ~= "dead" and kind ~= "trash" then
            local key = st and (st.kind .. st.name .. st.count) or "-"
            if invUI.slotKey[nImg] ~= key then
                invUI.slotKey[nImg] = key
                img:SetBrushFromTexture(st and iconTexture(st) or texture("icon_empty"), false)
                local c = (st and st.count > 1) and tostring(st.count) or ""
                invUI.slotTxt[nImg]:SetText(FText(c))
            end
            putL(invUI.slotImgS[nImg], ox + sl[3] * gs, oy + sl[4] * gs, 16 * gs, 16 * gs)
            putL(invUI.slotTxtS[nImg], ox + (sl[3] - 4) * gs, oy + (sl[4] + 8) * gs, 21 * gs, 10 * gs)
            fontL(invUI.slotTxt[nImg], math.floor(5.6 * gs / dpi * 1.33))
            ivis(img, "si" .. nImg, st ~= nil); ivis(invUI.slotTxt[nImg], "st" .. nImg, st ~= nil and st.count > 1)
        elseif nImg <= 54 then ivis(img, "si" .. nImg, false); ivis(invUI.slotTxt[nImg], "st" .. nImg, false) end
    end
    for k = nImg + 1, 54 do ivis(invUI.slotImg[k], "si" .. k, false); ivis(invUI.slotTxt[k], "st" .. k, false) end
    -- hover highlight and tooltip
    local hs = hover and slots[hover]
    ivis(invUI.hl, "hl", hs ~= nil and hs[1] ~= "dead")
    if hs then put(invUI.hlS, ox + hs[3] * gs, oy + hs[4] * gs, 16 * gs, 16 * gs) end
    local tipSt = hs and slotStack(hs[1], hs[2]) or nil
    local showTip = tipSt ~= nil and INV.cursor == nil
    ivis(invUI.tip, "tip", showTip); ivis(invUI.tipBg, "tipBg", showTip)
    if showTip then
        local label = displayName(tipSt.name)
        if INV.tipShown ~= label then INV.tipShown = label; invUI.tip:SetText(FText(label)) end
        local tx, ty = (INV.useMouse == false and (ox + hs[3] * gs + 10 * gs) or mx + 12 * gs), (INV.useMouse == false and (oy + hs[4] * gs) or my - 12 * gs)
        local tw = (#label * 3.6 + 8) * gs
        put(invUI.tipBgS, tx, ty, tw, 13 * gs); put(invUI.tipS, tx + 4 * gs, ty + 2 * gs, tw, 10 * gs)
        font(invUI.tip, math.floor(6 * gs / dpi * 1.33))
    end
    -- the stack on the cursor
    local cur = INV.cursor
    ivis(invUI.curImg, "curImg", cur ~= nil); ivis(invUI.curTxt, "curTxt", cur ~= nil and cur.count > 1)
    if cur then
        local key = cur.kind .. cur.name .. cur.count
        if INV.curKey ~= key then INV.curKey = key; invUI.curImg:SetBrushFromTexture(iconTexture(cur), false); invUI.curTxt:SetText(FText(cur.count > 1 and tostring(cur.count) or "")) end
        local cx, cy
        if INV.useMouse == false and hs then cx, cy = ox + (hs[3] + 8) * gs, oy + (hs[4] + 8) * gs else cx, cy = mx, my end
        put(invUI.curImgS, cx - 8 * gs, cy - 8 * gs, 16 * gs, 16 * gs)
        put(invUI.curTxtS, cx - 12 * gs, cy, 21 * gs, 10 * gs); font(invUI.curTxt, math.floor(5.6 * gs / dpi * 1.33))
    end
end
