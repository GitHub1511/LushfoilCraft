-- dev script: while the game's launch scene (MenuLaunchAnim_C) is on screen, log every text and image in it (text, font, size, colour, brush
-- texture, position) and save a screenshot with the UI. Copy over Scripts/dev.lua to run it.
LC.dumpTries = 0
local function dump()
    local lw = FindFirstOf("MenuLaunchAnim_C")
    if not (lw and lw:IsValid() and lw:IsInViewport()) then return false end
    LC.log("DUMP launch widget found: %s", lw:GetFullName())
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        if t:IsValid() then
            local full = t:GetFullName()
            if full:find("MenuLaunchAnim") then
                local txt, fo, sz, col, vis = "?", "?", 0, "?", -1
                pcall(function() txt = t:GetText():ToString() end)
                pcall(function() fo = t.Font.FontObject:GetFullName() end)
                pcall(function() sz = t.Font.Size end)
                pcall(function() local c = t.ColorAndOpacity.SpecifiedColor; col = string.format("%.2f,%.2f,%.2f,%.2f", c.R, c.G, c.B, c.A) end)
                pcall(function() vis = t:GetVisibility() end)
                local pos = "?"
                pcall(function() local s = t.Slot; local p = s:GetPosition(); local z = s:GetSize(); pos = string.format("pos=%.0f,%.0f size=%.0f,%.0f", p.X, p.Y, z.X, z.Y) end)
                LC.log("DUMP text %s | '%s' | font=%s size=%s color=%s vis=%s %s", full, txt, fo, tostring(sz), col, tostring(vis), pos)
            end
        end
    end
    for _, im in ipairs(FindAllOf("Image") or {}) do
        if im:IsValid() then
            local full = im:GetFullName()
            if full:find("MenuLaunchAnim") then
                local res, isz, vis, op = "?", "?", -1, -1
                pcall(function() local r = im.Brush.ResourceObject; res = (r and r:IsValid()) and r:GetFullName() or "none" end)
                pcall(function() local s = im.Brush.ImageSize; isz = string.format("%.0fx%.0f", s.X, s.Y) end)
                pcall(function() vis = im:GetVisibility() end)
                pcall(function() op = im.RenderOpacity end)
                local pos = "?"
                pcall(function() local s = im.Slot; local p = s:GetPosition(); local z = s:GetSize(); pos = string.format("pos=%.0f,%.0f size=%.0f,%.0f", p.X, p.Y, z.X, z.Y) end)
                LC.log("DUMP image %s | res=%s | brush=%s vis=%s opacity=%s %s", full, res, isz, tostring(vis), tostring(op), pos)
            end
        end
    end
    local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local pc = FindFirstOf("PlayerController")
    KSL:ExecuteConsoleCommand(pc:GetWorld(), "Shot ShowUI", pc)
    LC.log("DUMP screenshot requested")
    return true
end
local function poll()
    LC.dumpTries = LC.dumpTries + 1
    local ok, found = pcall(dump)
    if ok and found then return end
    if not ok then LC.log("DUMP error: %s", tostring(found)) end
    if LC.dumpTries < 400 then LC.after(0.25, poll) end
end
poll()
