-- LushfoilCraft v2: creative building inside Lushfoil. Blocks are real meshes with Minecraft textures on Lushfoil's own
-- material, so they are lit, shadowed and graded by the game exactly like the scenery.
--
--   Left mouse / F      break the block you look at          Right mouse / R   place the selected block
--   Q / E               previous / next block                PAGE_UP / PAGE_DOWN   jump 9 blocks
--   1-9                 hotbar slot                          F2   creative flight (Space up, Ctrl down)
--   F5                  third person: Steve, the Minecraft player model
--   F7                  graphics: tuned (faster, same look, 60 fps cap) / the game's own settings
--
-- Controller (Xbox 360 / One, wired or wireless via XInput):
--   RT break   LT place   RB / LB hotbar slot   D-pad left/right block -/+   D-pad up/down block +/-9
--   Y third person   X creative flight   (flying) A up, L3 down   Back graphics tuned/default
local UEHelpers = require("UEHelpers")
local log = LC.log

LC.tex = LC.tex or {}
LC.mat = LC.mat or {}
LC.world = LC.world or {}      -- "i,j,k" grid cell -> { actors = {...}, name = block }
LC.hot = LC.hot or {}          -- hotbar: slot -> index into blocks
LC.slot = LC.slot or 1
LC.flying = LC.flying or false
LC.surv = LC.surv or {}        -- survival state: health, food, inventory (9 slots of { kind, name, count })

local blocks = (loadfile(LC.dir .. "blocks.lua") or function() return {} end)()
local models = (loadfile(LC.dir .. "models.lua") or function() return {} end)()
local itemList = (loadfile(LC.dir .. "items.lua") or function() return {} end)()
local ITEMSET = {}
for _, n in ipairs(itemList) do ITEMSET[n] = true end
LC.hotItem = LC.hotItem or {}   -- creative hotbar slot -> item id (instead of a block)
for name in pairs(models) do blocks[#blocks + 1] = { name, "@model" } end     -- non-cube blocks: built from face slabs
table.sort(blocks, function(x, y) return x[1] < y[1] end)
local function byName(n) for i, d in ipairs(blocks) do if d[1] == n then return i end end end
if #LC.hot == 0 then
    for s, n in ipairs({ "stone", "grass_block", "dirt", "cobblestone", "oak_planks", "oak_log", "bricks", "sand", "glowstone" }) do LC.hot[s] = byName(n) or s end
end

local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
local KSL = UEHelpers.GetKismetSystemLibrary()
local KMATH = UEHelpers.GetKismetMathLibrary()
local cubeMesh = LoadAsset("/Engine/BasicShapes/Cube.Cube")
local planeMesh = LoadAsset("/Engine/BasicShapes/Plane.Plane")
local baseMat = LoadAsset("/Game/masters/surfacefullyrough.surfacefullyrough")
local smaClass = StaticFindObject("/Script/Engine.StaticMeshActor")
local cameraClass = StaticFindObject("/Script/Engine.CameraComponent")

-- UEHelpers.GetPlayerController / GetWorld scan every game object (FindAllOf); cache them and refresh at most once a second
local function getPC()
    local pc = LC.pc
    if pc and pc:IsValid() then return pc end
    if os.clock() - (LC.pcT or -10) < 1 then return nil end
    LC.pcT = os.clock()
    pc = UEHelpers.GetPlayerController()
    LC.pc = pc
    return pc
end
local function world()
    local w = LC.worldObj
    if w and w:IsValid() then return w end
    w = UEHelpers.GetWorld()
    LC.worldObj = w
    return w
end
local function pcpawn()
    local pc = getPC()
    if pc and pc:IsValid() and pc.Pawn and pc.Pawn:IsValid() then return pc, pc.Pawn end
end
local function cell(v) return math.floor(v / 100) end
local function keyOf(i, j, k) return i .. "," .. j .. "," .. k end

-- ------------------------------------------------------------------ textures, materials, meshes
local function texture(file)
    local t = LC.tex[file]
    if t and t:IsValid() then return t end
    t = KRL:ImportFileAsTexture2D(world(), LC.root .. "textures/" .. file .. ".png")
    if t and t:IsValid() then LC.tex[file] = t return t end
    log("could not load texture %s", file)
end

local function material(file)
    local m = LC.mat[file]
    if m and m:IsValid() then return m end
    local t = texture(file)
    if not t then return nil end
    m = KML:CreateDynamicMaterialInstance(world(), baseMat, FName("lc_" .. file), 0)
    m:SetTextureParameterValue(FName("Albedo"), t)
    m:SetScalarParameterValue(FName("overall scale"), 1)      -- the cube's own UVs: one texture tile per face
    m:SetScalarParameterValue(FName("normal strength"), 0)
    m:SetScalarParameterValue(FName("detail normal strength"), 0)
    LC.mat[file] = m
    return m
end

local function spawnMesh(mesh, mat, x, y, z, roll, collide)
    local a = world():SpawnActor(smaClass, { X = x, Y = y, Z = z }, { Pitch = 0, Yaw = 0, Roll = roll or 0 })
    if not (a and a:IsValid()) then log("SpawnActor failed") return nil end
    local c = a.StaticMeshComponent
    c:SetMobility(2)
    if mesh then c:SetStaticMesh(mesh) end
    if mat then c:SetMaterial(0, mat) end
    if not collide then c:SetCollisionEnabled(0) end
    return a
end

local function faceFiles(def)
    local name, kinds = def[1], def[2]
    if kinds == "all" then return name .. "_all", name .. "_all", name .. "_all" end
    return name .. "_top", name .. "_bottom", name .. "_side"
end

-- ------------------------------------------------------------------ the block world
local placeModel
local function place(idx, i, j, k)
    local key = keyOf(i, j, k)
    if LC.world[key] then return false end
    local def = blocks[idx]
    if def[2] == "@model" then
        local actors = placeModel(def[1], i, j, k)
        if not actors or #actors == 0 then return false end
        LC.world[key] = { actors = actors, name = def[1] }
        LC.dirty = true
        return true
    end
    local top, bottom, side = faceFiles(def)
    local x, y, z = (i + 0.5) * 100, (j + 0.5) * 100, (k + 0.5) * 100
    local actors = {}
    local cube = spawnMesh(cubeMesh, material(side), x, y, z, 0, true)
    if not cube then return false end
    actors[1] = cube
    if top ~= side then actors[#actors + 1] = spawnMesh(planeMesh, material(top), x, y, z + 50.3, 0, false) end
    if bottom ~= side then actors[#actors + 1] = spawnMesh(planeMesh, material(bottom), x, y, z - 50.3, 180, false) end
    LC.world[key] = { actors = actors, name = def[1] }
    LC.dirty = true
    return true
end

-- alpha-cut material (plants, panes, torches...) from Lushfoil's own two-sided foliage master, with the wind sway switched off
local foliageMat = LoadAsset("/Game/masters/foliage.foliage")
local function maskedMaterial(img)
    local key = img .. "@m"
    local m = LC.mat[key]
    if m and m:IsValid() then return m end
    local t, o = texture(img), texture(img .. "_m")
    if not (t and o) then return nil end
    m = KML:CreateDynamicMaterialInstance(world(), foliageMat, FName("lcm_" .. img), 0)
    m:SetTextureParameterValue(FName("Albedo"), t)
    m:SetTextureParameterValue(FName("Opacity"), o)
    for _, p in ipairs({ "sway multiplier", "flutter amount", "normal strength", "1.SwayHeight_power", "secondary multipl" }) do m:SetScalarParameterValue(FName(p), 0) end
    LC.mat[key] = m
    return m
end

-- a Minecraft model is a list of face slabs in block pixels (x east, y up, z south). One pixel = 6.25 cm; UE: X north, Y east, Z up.
local PXCM = 6.25
placeModel = function(name, i, j, k)
    local def = models[name]
    if not def then return nil end
    local actors = {}
    local cx, cy, cz = (i + 0.5) * 100, (j + 0.5) * 100, k * 100
    for _, sl in ipairs(def) do
        local mat = sl.m and maskedMaterial(sl.i) or material(sl.i)
        local x = cx + (8 - sl.c[3]) * PXCM
        local y = cy + (sl.c[1] - 8) * PXCM
        local z = cz + sl.c[2] * PXCM
        local a = world():SpawnActor(smaClass, { X = x, Y = y, Z = z }, { Pitch = 0, Yaw = sl.yaw or 0, Roll = 0 })
        if a and a:IsValid() then
            local c = a.StaticMeshComponent
            c:SetMobility(2)
            c:SetStaticMesh(cubeMesh)
            if mat then c:SetMaterial(0, mat) end
            local sx, sy, sz = sl.s[3], sl.s[1], sl.s[2]
            if sl.m then
                -- cut-out slabs: make the thin axis a hair so the edge faces (which would show a squashed copy of the texture) vanish
                local thin = math.min(sx, sy, sz)
                if thin < 1 then
                    if sx == thin then sx = 0.02 elseif sy == thin then sy = 0.02 else sz = 0.02 end
                end
            end
            c:SetWorldScale3D({ X = math.max(sx, 0.02) * PXCM / 100, Y = math.max(sy, 0.02) * PXCM / 100, Z = math.max(sz, 0.02) * PXCM / 100 })
            if sl.m then
                c:SetCollisionResponseToChannel(3, 0)       -- the player walks through plants and panes, but they can still be aimed at
            end
            actors[#actors + 1] = a
        end
    end
    return actors
end

local function remove(i, j, k)
    local key = keyOf(i, j, k)
    local b = LC.world[key]
    if not b then return false end
    for _, a in ipairs(b.actors) do if a and a:IsValid() then a:K2_DestroyActor() end end
    LC.world[key] = nil
    LC.dirty = true
    return true
end

-- ------------------------------------------------------------------ aiming
local function viewRay()
    local pc = getPC()
    local cm = pc.PlayerCameraManager
    local loc, rot = cm:GetCameraLocation(), cm:GetCameraRotation()
    return loc, KMATH:GetForwardVector(rot)
end

-- returns hit point, surface normal (tables with X,Y,Z) or nil
local function aim(maxDist)
    local pc, pawn = pcpawn()
    if not pawn then return end
    local loc, fwd = viewRay()
    local e = { X = loc.X + fwd.X * maxDist, Y = loc.Y + fwd.Y * maxDist, Z = loc.Z + fwd.Z * maxDist }
    local hit = {}
    local ignore = { pawn }
    if LC.held and LC.held:IsValid() then ignore[2] = LC.held end
    local ok = KSL:LineTraceSingle(world(), loc, e, 0, false, ignore, 0, hit, true, { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    if ok and hit.bBlockingHit then return hit.ImpactPoint, hit.ImpactNormal end
end

local REACH = 500          -- creative reach is 5 blocks
-- inside: the block you are looking at (only when it is one of ours); outside: the grid cell a new block would go into
local function target()
    local p, n = aim(REACH)
    if not p then return end
    local inside = { cell(p.X - n.X * 5), cell(p.Y - n.Y * 5), cell(p.Z - n.Z * 5) }
    if LC.world[keyOf(inside[1], inside[2], inside[3])] then
        return inside, { cell(p.X + n.X * 5), cell(p.Y + n.Y * 5), cell(p.Z + n.Z * 5) }, true
    end
    -- scenery (ground, rocks...) is not on our grid: build into the cell just in front of the surface
    return nil, { cell(p.X + n.X * 45), cell(p.Y + n.Y * 45), cell(p.Z + n.Z * 45) }, false
end

local function breakTarget()
    if LC.menuUp or LC.camUp or (LC.inv and LC.inv.open) then return end
    if LC.fxPlace then LC.fxPlace() end
    if LC.mode == "survival" then return end                 -- survival mining takes time: see mineTick
    local inside, _, isBlock = target()
    if isBlock and inside then
        local b0 = LC.world[keyOf(inside[1], inside[2], inside[3])]
        local name = b0 and b0.name
        if remove(inside[1], inside[2], inside[3]) then
            log("broke block at %d,%d,%d", inside[1], inside[2], inside[3])
            if LC.fxBurst and name then LC.fxBurst(name, inside[1], inside[2], inside[3]) end
            if LC.afterRemove then LC.afterRemove(inside[1], inside[2], inside[3]) end
        end
    end
end

local function placeTarget()
    local pc, pawn = pcpawn()
    if not pawn or LC.menuUp or LC.camUp or (LC.inv and LC.inv.open) then return end
    local surv = LC.mode == "survival"
    local st = LC.stackAt and LC.stackAt(LC.slot)
    if not st or (surv and st.kind ~= "block") then return end
    if surv and LC.surv.dead then return end
    if st.kind ~= "block" then return end
    local idx = surv and byName(st.name) or LC.hot[LC.slot]
    if not idx then return end
    local _, outside = target()
    if not outside then return end
    -- never build inside the player
    local l = pawn:K2_GetActorLocation()
    if cell(l.X) == outside[1] and cell(l.Y) == outside[2] and (outside[3] == cell(l.Z) or outside[3] == cell(l.Z - 60) or outside[3] == cell(l.Z + 40)) then return end
    if place(idx, outside[1], outside[2], outside[3]) then
        log("placed %s at %d,%d,%d", blocks[idx][1], outside[1], outside[2], outside[3])
        if LC.fxPlace then LC.fxPlace() end
        if surv and LC.survPlaceConsume then LC.survPlaceConsume() end
        if LC.afterPlace then LC.afterPlace(outside[1], outside[2], outside[3]) end
    end
end

-- ------------------------------------------------------------------ held item (shows what is selected)
-- the stack in a hotbar slot: creative = any block, survival = the real inventory ({ kind = "block"|"item", name, count } or nil)
local function stackAt(slot)
    if LC.mode == "survival" then return LC.surv.inv[slot] end
    if LC.hotItem[slot] then return { kind = "item", name = LC.hotItem[slot], count = 1 } end
    local idx = LC.hot[slot]
    return idx and { kind = "block", name = blocks[idx][1], count = 1 } or nil
end
LC.stackAt = stackAt
LC.flatHeldRot = LC.flatHeldRot or { Pitch = 90, Yaw = 0, Roll = 0 }

local function updateHeld()
    local pc, pawn = pcpawn()
    if not pawn then return end
    local st = stackAt(LC.slot)
    local key = st and (st.kind .. ":" .. st.name) or "none"
    if LC.heldKey == key and (key == "none" or (LC.held and LC.held:IsValid())) then return end
    if LC.held and LC.held:IsValid() then LC.held:K2_DestroyActor() end
    LC.held, LC.heldKey = nil, key
    if not st then return end
    local heldMat, kind
    if st.kind == "item" then heldMat, kind = maskedMaterial("item_" .. st.name), "flat" else heldMat, kind = LC.blockLook(st.name) end
    if not heldMat then return end
    local a = spawnMesh(kind == "flat" and planeMesh or cubeMesh, heldMat, 0, 0, 0, 0, false)
    if not a then return end
    local c = a.StaticMeshComponent
    c:SetCastShadow(false)
    local cam = pawn:GetComponentByClass(cameraClass)
    if cam and cam:IsValid() then
        c:K2_AttachToComponent(cam, FName("None"), 0, 0, 0, false)
        if kind == "flat" then
            -- one single-sided quad: a thin slab would show its mirrored back face through the cut-out parts of the sprite
            c:K2_SetRelativeLocation({ X = 38, Y = 16, Z = -13 }, false, {}, false)
            c:K2_SetRelativeRotation(LC.flatHeldRot, false, {}, false)
            c:SetRelativeScale3D({ X = 0.19, Y = 0.19, Z = 0.19 })
        else
            c:K2_SetRelativeLocation({ X = 34, Y = 17, Z = -16 }, false, {}, false)
            c:K2_SetRelativeRotation({ Pitch = 10, Yaw = 35, Roll = 8 }, false, {}, false)
            c:SetRelativeScale3D({ X = 0.085, Y = 0.085, Z = 0.085 })
        end
    else
        log("pawn has no camera component; held item not attached")
    end
    LC.held = a
    LC.equipT = LC.now
end

local function select(slot, idx)
    if slot then LC.slot = slot end
    if idx and LC.mode ~= "survival" then LC.hot[LC.slot] = (idx - 1) % #blocks + 1; LC.hotItem[LC.slot] = nil end
    local st = stackAt(LC.slot)
    log("slot %d: %s", LC.slot, st and st.name or "empty")
    updateHeld()
    if LC.hudRefresh then LC.hudRefresh() end
    if LC.hudNote then LC.hudNote() end
end

-- ------------------------------------------------------------------ creative flight
local function setFlight(on)
    local pc, pawn = pcpawn()
    if not pawn then return end
    local cm = pawn.CharacterMovement
    LC.flying = on
    if on then
        cm.MaxFlySpeed = 1090                     -- creative flight: 10.9 blocks/s (double with a sprint)
        cm.BrakingDecelerationFlying = 2400
        cm:SetMovementMode(5, 0)
    else
        cm:SetMovementMode(3, 0)
    end
    log("flight %s", on and "on" or "off")
end

-- key state polled once per frame by the framework (keyboard and controller)
local function down(name) return LC.down[name] == true end

local function realTick()
    local pc, pawn = pcpawn()
    if not pawn then return end
    if LC.hudFn and not LC.skip.hud then LC.hudFn() end
    if LC.updateArm and not LC.skip.arm then LC.updateArm() end
    if LC.modeTick and not LC.skip.mode then LC.modeTick() end
    if LC.flying then
        if not down("W") then LC.sprintLatch = false end
        local fs = LC.sprintLatch and 2180 or 1090
        if pawn.CharacterMovement.MaxFlySpeed ~= fs then pawn.CharacterMovement.MaxFlySpeed = fs end
    end
    if not (LC.held and LC.held:IsValid()) and not LC.third then updateHeld() end
    if LC.updateSteve then LC.updateSteve() end
end
local lastErr
LC.skip = LC.skip or {}      -- debugging switches: LC.skip.tick / frame / hud / arm / mode / extras turn parts of the mod off
LC.tickFn = function()
    if LC.skip.tick then return end
    if (LC.suspendFrames or 0) > 0 or (LC.calm or 0) < 240 or (LC.travelAt and os.time() - LC.travelAt < 24) then return end        -- a level is loading: the old level's objects must not be touched
    if LC.levelReset and LC.levelReset() then return end
    local ok, e = xpcall(realTick, debug.traceback)
    if not ok and e ~= lastErr then lastErr = e; log("tick error: %s", tostring(e)) end
end

local setThirdPerson, destroySteve
do   -- (own scope: Lua allows 200 local variables per function)
-- ------------------------------------------------------------------ Steve (the Minecraft player model) and third person
-- Built from thin textured cube slabs on pivots. Faces the +X direction; 1 skin pixel = 5.625 cm, so he is 1.8 m tall.
local PX = 5.625
local parts = {
    -- name, pivot (x,y,z), box centre relative to the pivot, box size (x depth, y width, z height) in skin pixels
    head = { { 0, 0, 24 * PX }, { 0, 0, 4 * PX }, { 8, 8, 8 } },
    body = { { 0, 0, 18 * PX }, { 0, 0, 0 }, { 4, 8, 12 } },
    rarm = { { 0, 6 * PX, 24 * PX }, { 0, 0, -6 * PX }, { 4, 4, 12 } },
    larm = { { 0, -6 * PX, 24 * PX }, { 0, 0, -6 * PX }, { 4, 4, 12 } },
    rleg = { { 0, 2 * PX, 12 * PX }, { 0, 0, -6 * PX }, { 4, 4, 12 } },
    lleg = { { 0, -2 * PX, 12 * PX }, { 0, 0, -6 * PX }, { 4, 4, 12 } },
}
local THICK = 0.5

function destroySteve()
    if LC.steve then
        for _, a in ipairs(LC.steve.all) do if a and a:IsValid() then a:K2_DestroyActor() end end
        LC.steve = nil
    end
end

local function buildSteve(at, yaw)
    destroySteve()
    local all, pivots = {}, {}
    local root = spawnMesh(nil, nil, at.X, at.Y, at.Z, 0, false)
    root.StaticMeshComponent:SetVisibility(false, false)
    all[#all + 1] = root
    for name, def in pairs(parts) do
        local pv, off, size = def[1], def[2], def[3]
        local px, py, pz = at.X + pv[1], at.Y + pv[2], at.Z + pv[3]
        local pivot = spawnMesh(nil, nil, px, py, pz, 0, false)
        pivot.StaticMeshComponent:SetVisibility(false, false)
        all[#all + 1] = pivot
        pivot:K2_AttachToActor(root, FName("None"), 1, 1, 1, false)
        pivots[name] = pivot
        local sx, sy, sz = size[1] * PX, size[2] * PX, size[3] * PX
        local cx, cy, cz = px + off[1], py + off[2], pz + off[3]
        local function slab(face, ox, oy, oz, scx, scy, scz)
            local mat = material("steve_" .. name .. "_" .. face)
            local a = spawnMesh(cubeMesh, mat, cx + ox, cy + oy, cz + oz, 0, false)
            if not a then return end
            a.StaticMeshComponent:SetWorldScale3D({ X = scx / 100, Y = scy / 100, Z = scz / 100 })
            a:K2_AttachToActor(pivot, FName("None"), 1, 1, 1, false)
            all[#all + 1] = a
        end
        slab("front", sx / 2 - THICK / 2, 0, 0, THICK, sy, sz)
        slab("back", -sx / 2 + THICK / 2, 0, 0, THICK, sy, sz)
        slab("right", 0, sy / 2 - THICK / 2, 0, sx, THICK, sz)
        slab("left", 0, -sy / 2 + THICK / 2, 0, sx, THICK, sz)
        slab("top", 0, 0, sz / 2 - THICK / 2, sx, sy, THICK)
        slab("bottom", 0, 0, -sz / 2 + THICK / 2, sx, sy, THICK)
    end
    root:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false)
    LC.steve = { root = root, pivots = pivots, all = all, phase = 0 }
    log("Steve built (%d actors)", #all)
end
LC.unload = destroySteve

function setThirdPerson(on)
    local pc, pawn = pcpawn()
    if not pawn then return end
    local cam = pawn:GetComponentByClass(cameraClass)
    if not (cam and cam:IsValid()) then log("no camera component") return end
    if on then
        if not LC.camHome then local r = cam.RelativeLocation; LC.camHome = { X = r.X, Y = r.Y, Z = r.Z } end
        cam:K2_SetRelativeLocation({ X = LC.camHome.X - 260, Y = LC.camHome.Y + 40, Z = LC.camHome.Z + 30 }, false, {}, false)
        if not LC.steve then
            local l = pawn:K2_GetActorLocation()
            local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            buildSteve({ X = l.X, Y = l.Y, Z = l.Z - half }, pawn:K2_GetActorRotation().Yaw)
        end
        if LC.held and LC.held:IsValid() then LC.held:SetActorHiddenInGame(true) end
    else
        if LC.camHome then cam:K2_SetRelativeLocation(LC.camHome, false, {}, false) end
        destroySteve()
        if LC.held and LC.held:IsValid() then LC.held:SetActorHiddenInGame(false) end
    end
    LC.third = on
    -- the first-person arms belong to the camera view only
    local ok = pcall(function()
        local meshes = pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))
        for i = 1, #meshes do meshes[i]:SetVisibility(not on, true) end
    end)
    log("third person %s", on and "on" or "off")
end

local function updateSteve()
    if not (LC.third and LC.steve) then return end
    local pc, pawn = pcpawn()
    if not pawn then return end
    local st = LC.steve
    local l = pawn:K2_GetActorLocation()
    local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    st.root:K2_SetActorLocationAndRotation({ X = l.X, Y = l.Y, Z = l.Z - half }, { Pitch = 0, Yaw = pawn:K2_GetActorRotation().Yaw, Roll = 0 }, false, {}, true)
    local v = pawn:GetVelocity()
    local speed = math.sqrt(v.X * v.X + v.Y * v.Y)
    st.phase = st.phase + speed * 0.0016
    local swing = (speed > 20) and math.sin(st.phase) * 40 or 0
    st.pivots.rleg:K2_SetActorRelativeRotation({ Pitch = swing, Yaw = 0, Roll = 0 }, false, {}, true)
    st.pivots.lleg:K2_SetActorRelativeRotation({ Pitch = -swing, Yaw = 0, Roll = 0 }, false, {}, true)
    -- right arm: raised a little while holding something, a full attack swing (Java Edition's curve) on every hit
    local stk = LC.stackAt(LC.slot)
    local armPitch = -swing + (stk and 18 or 0)
    local sw = LC.swingT and (LC.now - LC.swingT) / 0.3
    if sw and sw < 1 then armPitch = 18 + 100 * math.sin(math.sqrt(sw) * math.pi) end
    st.pivots.rarm:K2_SetActorRelativeRotation({ Pitch = armPitch, Yaw = 0, Roll = 0 }, false, {}, true)
    st.pivots.larm:K2_SetActorRelativeRotation({ Pitch = swing, Yaw = 0, Roll = 0 }, false, {}, true)
    -- what Steve holds
    local key = stk and (stk.kind .. ":" .. stk.name) or "none"
    if st.itemKey ~= key then
        if st.item and st.item:IsValid() then st.item:K2_DestroyActor() end
        st.item, st.itemKey = nil, key
        if stk then
            local mat, kind
            if stk.kind == "item" then mat, kind = maskedMaterial("item_" .. stk.name), "flat" else mat, kind = LC.blockLook(stk.name) end
            if mat then
                local a = spawnMesh(kind == "flat" and planeMesh or cubeMesh, mat, 0, 0, 0, 0, false)
                if a then
                    a.StaticMeshComponent:SetCastShadow(false)
                    a:K2_AttachToActor(st.pivots.rarm, FName("None"), 0, 0, 0, false)
                    if kind == "flat" then
                        a:K2_SetActorRelativeLocation({ X = 11, Y = 0, Z = -64 }, false, {}, true)
                        a:K2_SetActorRelativeRotation({ Pitch = 0, Yaw = 90, Roll = 90 }, false, {}, true)
                        a.StaticMeshComponent:SetWorldScale3D({ X = 0.42, Y = 0.42, Z = 0.42 })
                    else
                        a:K2_SetActorRelativeLocation({ X = 12, Y = 0, Z = -64 }, false, {}, true)
                        a.StaticMeshComponent:SetWorldScale3D({ X = 0.28, Y = 0.28, Z = 0.28 })
                    end
                    st.item = a
                    st.all[#st.all + 1] = a
                end
            end
        end
    end
end

LC.updateSteve = updateSteve

-- Steve's right arm in first person (the skin's own arm crops), at the bottom right of the view like Minecraft's
local ARM_PX = 2.8
local ARM_BASE_LOC = { X = 0, Y = 24, Z = -38 }
local ARM_BASE_ROT = { Pitch = 130, Yaw = -12, Roll = 0 }
local function destroyArm()
    if LC.fpArm then
        for _, a in ipairs(LC.fpArm.all) do if a and a:IsValid() then a:K2_DestroyActor() end end
        LC.fpArm = nil
    end
end
local function buildArm(cam)
    destroyArm()
    local all = {}
    local pivot = spawnMesh(nil, nil, 0, 0, 0, 0, false)
    if not pivot then return end
    pivot.StaticMeshComponent:SetVisibility(false, false)
    pivot.StaticMeshComponent:K2_AttachToComponent(cam, FName("None"), 0, 0, 0, false)
    pivot.StaticMeshComponent:K2_SetRelativeLocation(ARM_BASE_LOC, false, {}, false)
    pivot.StaticMeshComponent:K2_SetRelativeRotation(ARM_BASE_ROT, false, {}, false)
    all[1] = pivot
    local sx, sy, sz = 4 * ARM_PX, 4 * ARM_PX, 12 * ARM_PX
    local th = 0.5
    local function slab(face, ox, oy, oz, scx, scy, scz)
        local mat = material("steve_rarm_" .. face)
        local a = spawnMesh(cubeMesh, mat, 0, 0, 0, 0, false)
        if not a then return end
        a.StaticMeshComponent:SetCastShadow(false)
        a.StaticMeshComponent:SetWorldScale3D({ X = scx / 100, Y = scy / 100, Z = scz / 100 })
        a:K2_AttachToActor(pivot, FName("None"), 0, 0, 0, false)
        a:K2_SetActorRelativeLocation({ X = ox, Y = oy, Z = oz - sz / 2 }, false, {}, true)
        all[#all + 1] = a
    end
    slab("front", sx / 2 - th / 2, 0, 0, th, sy, sz)
    slab("back", -sx / 2 + th / 2, 0, 0, th, sy, sz)
    slab("right", 0, sy / 2 - th / 2, 0, sx, th, sz)
    slab("left", 0, -sy / 2 + th / 2, 0, sx, th, sz)
    slab("top", 0, 0, sz / 2 - th / 2, sx, sy, th)
    slab("bottom", 0, 0, -sz / 2 + th / 2, sx, sy, th)
    LC.fpArm = { pivot = pivot, all = all, cam = cam }
end
LC.updateArm = function()
    local pc, pawn = pcpawn()
    if not pawn then return end
    local want = (not LC.third) and (LC.hudOn or LC.forceArm) and not LC.camUp
    if not want then
        if LC.fpArm then for _, a in ipairs(LC.fpArm.all) do if a:IsValid() then a:SetActorHiddenInGame(true) end end; LC.fpArmHidden = true end
        return
    end
    local cam = pawn:GetComponentByClass(cameraClass)
    if not (cam and cam:IsValid()) then return end
    if not (LC.fpArm and LC.fpArm.pivot:IsValid()) or LC.fpArm.cam ~= cam then buildArm(cam); LC.fpArmHidden = false end
    if LC.fpArmHidden and LC.fpArm then for _, a in ipairs(LC.fpArm.all) do if a:IsValid() then a:SetActorHiddenInGame(false) end end; LC.fpArmHidden = false end
end
LC.armBase = function() return ARM_BASE_LOC, ARM_BASE_ROT end

end

local applyGfx
do
-- ------------------------------------------------------------------ graphics and performance
-- Measured on this PC (RTX 3050, 1600x900, Lake Braies, fixed camera, uncapped): game defaults 31.2 fps -> tuned 37.9 fps, no visible
-- difference in the image. Lushfoil also caps itself at 30 fps (it re-issues "t.maxfps 30" about twice a second unless its own
-- "60 fps" menu option is on), which is the biggest single cost on a fast GPU, so the cap is re-set right after the game's command.
local GFX_CAP = 60                       -- fps cap while tuned (0 = uncapped)
LC.gfxOn = LC.gfxOn ~= false

local function cvar(name) local ok, v = pcall(function() return KSL:GetConsoleVariableFloatValue(name) end); return ok and v or nil end
local function exec(c) pcall(function() KSL:ExecuteConsoleCommand(world(), c, getPC()) end) end

-- the game's own values, remembered the first time so "off" restores exactly what the player had
local function rememberGame()
    if LC.gfxGame then return end
    LC.gfxGame = {
        vd = cvar("r.ViewDistanceScale"), fol = cvar("foliage.LODDistanceScale"), tsr = cvar("r.TSR.History.ScreenPercentage"),
        aniso = cvar("r.MaxAnisotropy"), pool = cvar("r.Streaming.PoolSize"), dofFg = cvar("r.DOF.Kernel.MaxForegroundRadius"),
    }
end

function applyGfx(on)
    rememberGame()
    local g = LC.gfxGame
    if not g.vd then return end
    LC.gfxOn = on
    if on then
        exec("r.ViewDistanceScale " .. math.max(0.3, g.vd * 0.63 * (LC.rdist or 12) / 12))                -- distant detail past the haze costs a lot, shows little
        exec("foliage.LODDistanceScale " .. math.max(0.3, g.fol * 0.66 * (LC.rdist or 12) / 12))
        exec("r.TSR.History.ScreenPercentage " .. math.min(g.tsr, 100))            -- 200% history was the heaviest invisible cost
        exec("r.MaxAnisotropy " .. math.max(g.aniso, 16))                          -- sharper ground at grazing angles, free
        exec("r.Streaming.PoolSize " .. math.max(g.pool, 2500))                    -- the 6 GB card was using under 2 GB
        exec("r.DOF.Kernel.MaxForegroundRadius 0")                                 -- the item in your hand stays sharp (the lens still blurs the distance)
    else
        exec("r.ViewDistanceScale " .. g.vd); exec("foliage.LODDistanceScale " .. g.fol); exec("r.TSR.History.ScreenPercentage " .. g.tsr)
        exec("r.MaxAnisotropy " .. g.aniso); exec("r.Streaming.PoolSize " .. g.pool); if g.dofFg then exec("r.DOF.Kernel.MaxForegroundRadius " .. g.dofFg) end
    end
    log("graphics %s (fps cap %s)", on and "tuned" or "game defaults", on and tostring(GFX_CAP) or "30 (game)")
end

-- replace the game's 30 fps cap; the hook is installed once per session and consults LC.gfxOn / GFX_CAP live
LC.gfxCap = GFX_CAP
LC.capFn = function(self, w, command, who)
    if LC.idle or not LC.gfxOn or LC.travelFlag or (LC.suspendFrames or 0) > 0 then return end      -- never act on a level that is being replaced
    local ok2, c = pcall(function() return command:get():ToString() end)
    if ok2 and c and c:lower() == "t.maxfps 30" then
        pcall(function()
            local wo, pl = w:get(), who and who:get()                  -- the objects of the call being answered, not remembered ones
            if wo and wo:IsValid() then KSL:ExecuteConsoleCommand(wo, "t.MaxFPS " .. tostring(LC.gfxCap), (pl and pl:IsValid()) and pl or nil) end
        end)
    end
end
if not LC.capHook then
    LC.capHook = true
    local ok, e = pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:ExecuteConsoleCommand", function() end, function(self, w, command, who)
        if LC.capFn then LC.capFn(self, w, command, who) end
    end)
    log("fps-cap hook %s", ok and "installed" or ("FAILED: " .. tostring(e)))
end

-- Level changes: the old level's objects can still look valid while the engine tears them down, and calling into them crashes the game, so every
-- travel (the menu's OpenLevel, or an "open" command) pauses all mod work for a few seconds of frames; the first tick afterwards clears the old references.
if not LC.travelHook then
    LC.travelHook = true
    local function go()
        if LC.idle then return end
        if LC.preTravel then pcall(LC.preTravel) end                       -- take down everything attached to the old level's camera/viewport before the engine tears the level down
        LC.suspendFrames = 240; LC.travelFlag = true; LC.travelAt = os.time()
    end       -- ~25 s of rendered frames, counted once the new level runs: attaching things to the camera while the game is still doing its own start-up crashes it
    for _, fn in ipairs({ "/Script/Engine.GameplayStatics:OpenLevel", "/Script/Engine.GameplayStatics:OpenLevelBySoftObjectPtr", "/Script/Engine.PlayerController:ClientTravel" }) do
        pcall(RegisterHook, fn, go)
    end
    pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:ExecuteConsoleCommand", function(self, w, command)
        local ok, c = pcall(function() return command:get():ToString():lower() end)
        if ok and c and (c:find("^open ") or c:find("^servertravel") or c:find("^travel ")) then go() end
    end)
end

-- apply once the player exists (a few seconds after the level starts), then again only on request
LC.after(4.0, function() if getPC() then applyGfx(LC.gfxOn) end end)

end

-- ------------------------------------------------------------------ Minecraft HUD (UMG): crosshair, hotbar, item name, survival bars, menu panel
-- Layout follows Minecraft's "Auto" GUI scale: the largest whole number s with width/s >= 320 and height/s >= 240. Positions are in pixels;
-- Slate wants them divided by the viewport's DPI scale.
local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
local UW = StaticFindObject("/Script/UMG.UserWidget")
local canvasClass = StaticFindObject("/Script/UMG.CanvasPanel")
local imageClass = StaticFindObject("/Script/UMG.Image")
local textClass = StaticFindObject("/Script/UMG.TextBlock")

local function displayName(n)
    local s = n:gsub("_", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
    return s
end

local hud
local function hudKill()
    if LC.hudW and LC.hudW:IsValid() then pcall(function() LC.hudW:RemoveFromParent() end) end
    LC.hudW, hud = nil, nil
end

local function iconFor(st)
    if not st then return "icon_empty" end
    return (st.kind == "item" and "icon_item_" or "icon_") .. st.name
end
local function iconTexture(st) return texture(iconFor(st)) or texture("icon_empty") end

-- menu panel rows: label function + action (also reachable from the keyboard / controller outside menus)
-- Credits. The game's own credits stay exactly as it shows them ("Created by Matt Newell", "published by" + the publisher's logo); these
-- lines are added next to them on the launch scene and in the menu.
local CREDITS = {
    "LushfoilCraft  -  created by Shivin Singh",
    "Built from Lushfoil Photography Sim (created by Matt Newell, published by Annapurna Interactive) and Minecraft Java Edition 1.21.1 (Mojang Studios, created by Markus \"Notch\" Persson).",
    "An unofficial fan mod. Not affiliated with or endorsed by Matt Newell, Annapurna Interactive, Mojang Studios or Microsoft. All rights to the original games, art and music belong to their creators.",
}
LC.CREDITS = CREDITS
local PANEL = { x = 24, y = 24, w = 330, rowH = 36, gap = 7 }
local NROWS = 12
local MOBILE_ASPECT = 9 / 16        -- the portrait phone shape at the slider's far end; change here for another ratio
local MOBILE_ZOOMOUT = 12            -- degrees of extra vertical field of view at full portrait: the view zooms out a little
local function panelRows()
    local wi = LC.worldInfo and LC.worldInfo() or { name = "World 1", count = 0 }
    local r = {
        { text = "Maps and worlds  (" .. wi.name .. ")", act = function() if LC.saveNow then LC.saveNow() end; if LC.title and LC.title.open then LC.title.open("main") end end },
        { text = "Save world", act = function() LC.saveNow() end },
        { text = "Game mode:  " .. (LC.mode == "survival" and "Survival" or "Creative"), act = function() LC.setMode(LC.mode == "survival" and "creative" or "survival") end },
        { text = "Flying:  " .. (LC.flying and "ON" or "OFF"), act = function() LC.setFlight(not LC.flying) end },
        { text = "Walking:  " .. (LC.walkStyle == "lushfoil" and "LushfoilCraft" or "Minecraft"), act = function() LC.setWalkStyle(LC.walkStyle == "lushfoil" and "minecraft" or "lushfoil") end },
    }
    if LC.walkStyle == "lushfoil" then
        r[#r + 1] = { text = "LushfoilCraft fast walking:  " .. (LC.fast and "ON" or "OFF"), act = function() LC.setFast(not LC.fast) end }
    end
    r[#r + 1] = { text = "Survival starter kit:  " .. (LC.kit and "ON" or "OFF"), act = function() LC.kit = not LC.kit; LC.saveCfg() end }
    r[#r + 1] = { text = "Field of view:  " .. math.floor(LC.fovV + 0.5), slider = { 30, 110, 1, function() return LC.fovV end, function(v) LC.fovV = v end } }
    r[#r + 1] = { text = "Screen shape:  " .. (LC.shape > 0.97 and "full window" or LC.shape < 0.03 and "phone 9:16" or math.floor(LC.shape * 100) .. "% wide"), slider = { 0, 1, 0.01, function() return LC.shape end, function(v) LC.shape = v end } }
    r[#r + 1] = { text = "Render distance:  " .. math.floor(LC.rdist + 0.5) .. " chunks", slider = { 2, 32, 1, function() return LC.rdist end, function(v) LC.rdist = v; LC.gfxDirty = true end } }
    return r
end

local function hudBuild()
    hudKill()
    local pc = getPC()
    if not pc then return end
    local w = WBL:Create(world(), UW, pc)
    if not (w and w:IsValid()) then return end
    local tree = w.WidgetTree
    local canvas = StaticConstructObject(canvasClass, tree, FName("lc_canvas"))
    tree.RootWidget = canvas
    local function add(widget) local s = canvas:AddChildToCanvas(widget); s:SetAutoSize(false); return s end
    local function image(tex)
        local i = StaticConstructObject(imageClass, tree)
        i:SetBrushFromTexture(tex, false)
        return i, add(i)
    end
    local function text(just)
        local t = StaticConstructObject(textClass, tree)
        t:SetJustification(just or 1)
        t:SetShadowOffset({ X = 1, Y = 1 })
        t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 })
        return t, add(t)
    end
    local white = texture("white")
    hud = { w = w, icons = {}, iconS = {}, counts = {}, countS = {}, hc = {}, hcS = {}, hf = {}, hfS = {}, fc = {}, fcS = {}, ff = {}, ffS = {}, rows = {}, rowT = {}, rowS = {}, rowTS = {}, fill = {}, fillS = {} }
    hud.flash, hud.flashS = image(white); hud.flash:SetColorAndOpacity({ R = 0.9, G = 0, B = 0, A = 0 })
    hud.bar, hud.barS = image(texture("gui_hotbar"))
    for s = 1, 9 do hud.icons[s], hud.iconS[s] = image(iconTexture(LC.stackAt(s))) end
    for s = 1, 9 do hud.counts[s], hud.countS[s] = text(2) end
    hud.sel, hud.selS = image(texture("gui_hotbar_selection"))
    hud.cross, hud.crossS = image(texture("gui_crosshair"))
    for i = 1, 10 do
        hud.hc[i], hud.hcS[i] = image(texture("gui_heart_container"))
        hud.hf[i], hud.hfS[i] = image(texture("gui_heart_full"))
        hud.fc[i], hud.fcS[i] = image(texture("gui_food_empty"))
        hud.ff[i], hud.ffS[i] = image(texture("gui_food_full"))
    end
    hud.xp, hud.xpS = image(texture("gui_experience_bar_background"))
    hud.chatBg, hud.chatBgS = image(white); hud.chatBg:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.6 })
    hud.chatT, hud.chatTS = text(0)
    hud.sug, hud.sugS, hud.clog, hud.clogS = {}, {}, {}, {}
    for i = 1, 6 do hud.sug[i], hud.sugS[i] = text(0); hud.clog[i], hud.clogS[i] = text(0) end
    hud.name, hud.nameS = text(1)
    hud.msg, hud.msgS = text(1)
    -- main-menu panel
    hud.pbg, hud.pbgS = image(white); hud.pbg:SetColorAndOpacity({ R = 0.05, G = 0.07, B = 0.06, A = 0.72 })
    hud.ptitle, hud.ptitleS = text(0)
    hud.ptitle:SetText(FText("LUSHFOILCRAFT"))
    for r = 1, NROWS do
        hud.rows[r], hud.rowS[r] = image(white)
        hud.fill[r], hud.fillS[r] = image(white); hud.fill[r]:SetColorAndOpacity({ R = 0.3, G = 0.58, B = 0.36, A = 0.9 })
        hud.rowT[r], hud.rowTS[r] = text(0)
    end
    hud.phint, hud.phintS = text(0)
    hud.phint:SetText(FText("F4 mode  F2 fly  F8 walking  F3 fast  F6 shape  (pad: LB mode, RB walking, X fly)"))
    hud.credBg, hud.credBgS = image(white); hud.credBg:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.55 })
    hud.cred, hud.credS = {}, {}
    for n = 1, 3 do
        hud.cred[n], hud.credS[n] = text(0)
        hud.cred[n]:SetText(FText(CREDITS[n]))
        hud.cred[n].AutoWrapText = true
    end
    w:AddToViewport(50)
    LC.hudW = w
    hud.size = nil          -- forces a layout
    hud.vis = {}
end

local function hudRefresh()
    if not hud then return end
    for s = 1, 9 do
        local st = LC.stackAt(s)
        hud.icons[s]:SetBrushFromTexture(iconTexture(st), false)
        local n = (st and st.count > 1 and LC.mode == "survival") and tostring(st.count) or ""
        hud.counts[s]:SetText(FText(n))
    end
    hud.statKey = nil
end

local function setVis(widget, key, v)
    if hud.vis[key] ~= v then hud.vis[key] = v; widget:SetVisibility(v and 3 or 1) end
end

local function hudLayout(vs, dpi)
    local W, H = vs.X, vs.Y
    local XO = 0
    local asp = MOBILE_ASPECT + (vs.X / vs.Y - MOBILE_ASPECT) * LC.shape
    local constrained = LC.shape < 0.999
    if constrained then local pw = math.min(W, math.floor(H * asp)); XO = math.floor((W - pw) / 2); W = pw end
    local gs = math.max(1, math.min(math.floor(W / 320), math.floor(H / 240)))
    if constrained then gs = math.max(1, math.min(math.floor(W / 240), math.floor(H / 240))) end
    hud.XO = XO
    local function put(slot, x, y, w, h)
        slot:SetPosition({ X = (x + XO) / dpi, Y = y / dpi })
        slot:SetSize({ X = w / dpi, Y = h / dpi })
    end
    local function font(t, size) local f = t.Font; f.Size = size; t:SetFont(f) end
    local x0, y0 = math.floor(W / 2 - 91 * gs), H - 22 * gs
    hud.gs, hud.x0, hud.y0, hud.W, hud.H = gs, x0, y0, W, H
    hud.flashS:SetPosition({ X = 0, Y = 0 }); hud.flashS:SetSize({ X = vs.X / dpi, Y = vs.Y / dpi })
    put(hud.barS, x0, y0, 182 * gs, 22 * gs)
    for s = 1, 9 do
        local ix = x0 + (3 + 20 * (s - 1)) * gs
        put(hud.iconS[s], ix, y0 + 3 * gs, 16 * gs, 16 * gs)
        put(hud.countS[s], ix - 4 * gs, y0 + 8 * gs, 21 * gs, 10 * gs)
        font(hud.counts[s], math.floor(5.6 * gs / dpi * 1.33))
    end
    put(hud.selS, x0 + (20 * (LC.slot - 1) - 1) * gs, y0 - 1 * gs, 24 * gs, 23 * gs)
    put(hud.crossS, math.floor((W - 15 * gs) / 2), math.floor((H - 15 * gs) / 2), 15 * gs, 15 * gs)
    for i = 1, 10 do
        local hx = x0 + 8 * gs * (i - 1)
        local fx_ = x0 + 182 * gs - 9 * gs - 8 * gs * (i - 1)
        put(hud.hcS[i], hx, H - 39 * gs, 9 * gs, 9 * gs); put(hud.hfS[i], hx, H - 39 * gs, 9 * gs, 9 * gs)
        put(hud.fcS[i], fx_, H - 39 * gs, 9 * gs, 9 * gs); put(hud.ffS[i], fx_, H - 39 * gs, 9 * gs, 9 * gs)
    end
    put(hud.xpS, x0, H - 29 * gs, 182 * gs, 5 * gs)
    -- chat: input bar above the hotbar, suggestions above it, command feedback at the bottom left
    local cw = math.min(W - 8 * gs, 330 * gs)
    put(hud.chatBgS, 4 * gs, H - 66 * gs, cw, 12 * gs)
    put(hud.chatTS, 6 * gs, H - 65 * gs, cw - 4 * gs, 10 * gs); font(hud.chatT, math.floor(6.4 * gs / dpi * 1.33))
    for i = 1, 6 do
        put(hud.sugS[i], 6 * gs, H - 66 * gs - 11 * gs * i, cw, 10 * gs); font(hud.sug[i], math.floor(6 * gs / dpi * 1.33))
        put(hud.clogS[i], 4 * gs, H - 80 * gs - 11 * gs * i, math.min(W - 8 * gs, 360 * gs), 10 * gs); font(hud.clog[i], math.floor(6.2 * gs / dpi * 1.33))
    end
    -- the item name sits 59 GUI pixels above the bottom in survival (above the bars), 45 in creative
    local ny = LC.mode == "survival" and 59 or 45
    local nw = math.min(400 * gs, W)
    put(hud.nameS, W / 2 - nw / 2, H - ny * gs - 8 * gs, nw, 14 * gs)
    font(hud.name, math.floor(6.4 * gs / dpi * 1.33))
    local mw = math.min(600 * gs, W)
    put(hud.msgS, W / 2 - mw / 2, H / 2 - 60 * gs, mw, 30 * gs)
    font(hud.msg, math.floor(14 * gs / dpi * 1.33))
    -- panel (slate units, not scaled by the GUI scale)
    local px, py = PANEL.x, PANEL.y
    local function putU(slot, x, y, w, h) slot:SetPosition({ X = x, Y = y }); slot:SetSize({ X = w, Y = h }) end
    putU(hud.pbgS, px, py, PANEL.w, 44 + NROWS * (PANEL.rowH + PANEL.gap) + 28)
    putU(hud.ptitleS, px + 14, py + 8, PANEL.w, 28)
    font(hud.ptitle, 20)
    for r = 1, NROWS do
        local ry = py + 40 + (r - 1) * (PANEL.rowH + PANEL.gap)
        putU(hud.rowS[r], px + 10, ry, PANEL.w - 20, PANEL.rowH)
        putU(hud.fillS[r], px + 10, ry, 1, PANEL.rowH)
        putU(hud.rowTS[r], px + 22, ry + 8, PANEL.w - 40, PANEL.rowH)
        font(hud.rowT[r], 16)
    end
    putU(hud.phintS, px + 12, py + 40 + NROWS * (PANEL.rowH + PANEL.gap) + 2, PANEL.w - 20, 20)
    font(hud.phint, 11)
    -- credits: bottom-left, in slate units
    local cw, cx, cy = math.min(760, W / dpi - 48), 24, H / dpi - 128
    putU(hud.credBgS, cx - 10, cy - 8, cw + 20, 124)
    putU(hud.credS[1], cx, cy, cw, 22); font(hud.cred[1], 17)
    putU(hud.credS[2], cx, cy + 26, cw, 44); font(hud.cred[2], 11)
    putU(hud.credS[3], cx, cy + 74, cw, 40); font(hud.cred[3], 10)
end

-- hearts / hunger bars (survival only)
local function hudStats()
    local S = LC.surv
    local surv = LC.mode == "survival"
    local airN = 0
    local key = (surv and "s" or "c") .. math.floor(S.health * 2) .. "," .. math.floor(S.food) .. "," .. airN
    if hud.statKey == key then return end
    hud.statKey = key
    for i = 1, 10 do
        setVis(hud.hc[i], "hc" .. i, surv); setVis(hud.fc[i], "fc" .. i, surv)
        local hp, fd = S.health, math.floor(S.food)
        local hfull, hhalf = hp >= 2 * i, hp == 2 * i - 1 or (hp > 2 * i - 2 and hp < 2 * i)
        setVis(hud.hf[i], "hf" .. i, surv and (hfull or hhalf))
        if surv and (hfull or hhalf) then hud.hf[i]:SetBrushFromTexture(texture(hfull and "gui_heart_full" or "gui_heart_half"), false) end
        local ffull, fhalf = fd >= 2 * i, fd == 2 * i - 1
        setVis(hud.ff[i], "ff" .. i, surv and (ffull or fhalf))
        if surv and (ffull or fhalf) then hud.ff[i]:SetBrushFromTexture(texture(ffull and "gui_food_full" or "gui_food_half"), false) end
    end
    setVis(hud.xp, "xp", surv)
end

local lastSlot, lastMode
local function hudTick()
    local pc = getPC()
    if not (pc and pc:IsValid()) then return end
    if not hud or not (LC.hudW and LC.hudW:IsValid()) then hudBuild(); if not hud then return end; hudRefresh() end
    local vs = WLL:GetViewportSize(world())
    local dpi = WLL:GetViewportScale(world())
    if dpi <= 0 then dpi = 1 end
    -- a menu is up while the game shows the mouse cursor or is cycling its cinematic cameras
    local vt = pc:GetViewTarget()
    local cine = vt and vt:IsValid() and vt:GetClass():GetFName():ToString() == "CineCameraActor"
    local menu = ((pc.bShowMouseCursor and not (LC.inv and LC.inv.open) and not (LC.title and LC.title.active)) and true) or cine or false
    LC.menuUp = menu
    local key = vs.X .. "x" .. vs.Y .. "@" .. dpi .. LC.mode .. string.format("s%.2f f%.0f", LC.shape, LC.fovV)
    if hud.size ~= key then hud.size = key; hudLayout(vs, dpi); LC.fovSize = nil; hud.statKey = nil; lastSlot = nil end
    if lastSlot ~= LC.slot then
        lastSlot = LC.slot
        local gs = hud.gs
        hud.selS:SetPosition({ X = ((hud.XO or 0) + hud.x0 + (20 * (LC.slot - 1) - 1) * gs) / dpi, Y = (hud.y0 - gs) / dpi })
    end
    -- the game has started when the launch scene is over and no menu is up. The launch widget is only looked at in the first level of a session:
    -- after a level change FindFirstOf returns the previous level's dead copy, and asking it anything crashes the game.
    local launchUp = false
    if not LC.levelChanged then
        if not LC.launchW or not LC.launchW:IsValid() then
            if LC.now - (LC.launchFind or -10) > 5 then LC.launchFind = LC.now; LC.launchW = FindFirstOf("MenuLaunchAnim_C") end
        end
        launchUp = LC.launchW and LC.launchW:IsValid() and LC.launchW:IsInViewport() or false
    end
    LC.launchUp = launchUp
    local show = not LC.hudHidden and not menu and not launchUp and not (LC.inv and LC.inv.open) and not (LC.title and LC.title.active)
    LC.hudOn = show
    setVis(hud.bar, "bar", show); setVis(hud.sel, "sel", show); setVis(hud.cross, "cross", show)
    for s = 1, 9 do setVis(hud.icons[s], "i" .. s, show); setVis(hud.counts[s], "n" .. s, show) end
    setVis(hud.name, "name", show); setVis(hud.msg, "msg", show); setVis(hud.flash, "flash", show)
    hudStats()
    if not show then
        for i = 1, 10 do setVis(hud.hc[i], "hc" .. i, false); setVis(hud.hf[i], "hf" .. i, false); setVis(hud.fc[i], "fc" .. i, false); setVis(hud.ff[i], "ff" .. i, false) end
        setVis(hud.xp, "xp", false)
        hud.statKey = nil
    end
    -- item name: shown for 2 s after the held item changes, fading over the last half second
    local age = LC.now - (LC.nameT or -10)
    local a = age < 2.0 and math.min(1, (2.0 - age) / 0.5) or 0
    if a ~= hud.nameA then
        hud.nameA = a
        if a > 0 then local st = LC.stackAt(LC.slot); hud.name:SetText(FText(st and displayName(st.name) or "")) end
        hud.name:SetRenderOpacity(a)
    end
    local ch = LC.chat
    local chatShow = show and ch and ch.open
    setVis(hud.chatBg, "chatbg", chatShow and true or false); setVis(hud.chatT, "chatt", chatShow and true or false)
    if ch then
        local caret = (math.floor(LC.now * 2) % 2 == 0) and "_" or " "
        local line = ch.open and ("> " .. ch.text .. caret) or ""
        if hud.chatLine ~= line then hud.chatLine = line; hud.chatT:SetText(FText(line)) end
        local sugs = ch.open and (ch.sugs or {}) or {}
        for i = 1, 6 do
            local v = sugs[i]
            setVis(hud.sug[i], "sug" .. i, show and v ~= nil)
            if v and hud.sugShown ~= nil and hud.sugShown[i] ~= v or v and hud.sugShown == nil then hud.sug[i]:SetText(FText(v)) end
            hud.sug[i]:SetColorAndOpacity({ SpecifiedColor = { R = i == 1 and 1 or 0.75, G = i == 1 and 1 or 0.75, B = i == 1 and 0.4 or 0.75, A = 1 }, ColorUseRule = 0 })
        end
        hud.sugShown = { table.unpack(sugs) }
        -- feedback lines fade six seconds after they appear (all stay while the chat is open)
        local lines = LC.chatLines or {}
        for i = 1, 6 do
            local e = lines[#lines - i + 1]
            local visible = show and e ~= nil and (ch.open or LC.now - e.t < 6)
            setVis(hud.clog[i], "clog" .. i, visible and true or false)
            if e and hud.clogShown and hud.clogShown[i] ~= e.text or e and not hud.clogShown then hud.clog[i]:SetText(FText(e.text)) end
        end
        hud.clogShown = {}
        for i = 1, 6 do local e = lines[#lines - i + 1]; hud.clogShown[i] = e and e.text end
    end
    -- centre message ("You died!") and the red hurt flash
    local ma = LC.msgT and math.max(0, 1 - (LC.now - LC.msgT) / (LC.msgDur or 2)) or 0
    if ma ~= hud.msgA then
        hud.msgA = ma
        if ma > 0 and LC.msgText ~= hud.msgShown then hud.msgShown = LC.msgText; hud.msg:SetText(FText(LC.msgText or "")) end
        hud.msg:SetRenderOpacity(math.min(1, ma * 3))
    end
    local fa = LC.hurtT and math.max(0, 0.38 - (LC.now - LC.hurtT) * 1.1) or 0
    if fa ~= hud.flashA then hud.flashA = fa; hud.flash:SetColorAndOpacity({ R = 0.85, G = 0, B = 0, A = fa }) end
    -- credits show on the launch scene and in menus
    local credShow = false                                     -- the credits have their own screens now
    setVis(hud.credBg, "credbg", credShow)
    for n = 1, 3 do setVis(hud.cred[n], "cred" .. n, credShow) end
    if LC.brandTick then LC.brandTick(launchUp) end
    -- the menu panel
    for _, w_ in ipairs({ hud.pbg, hud.ptitle, hud.phint }) do setVis(w_, w_ == hud.pbg and "pbg" or w_ == hud.ptitle and "ptitle" or "phint", menu) end
    local rows = panelRows()
    local mp = menu and WLL:GetMousePositionOnViewport(world()) or nil
    LC.mouseU = mp
    if hud.nRows ~= #rows then
        hud.nRows = #rows; hud.rowLabel = nil
        hud.pbgS:SetSize({ X = PANEL.w, Y = 44 + #rows * (PANEL.rowH + PANEL.gap) + 28 })
        hud.phintS:SetPosition({ X = PANEL.x + 12, Y = PANEL.y + 40 + #rows * (PANEL.rowH + PANEL.gap) + 2 })
    end
    for r = 1, NROWS do
        local present = rows[r] ~= nil
        setVis(hud.rows[r], "row" .. r, menu and present); setVis(hud.rowT[r], "rowt" .. r, menu and present)
        if not present then setVis(hud.fill[r], "fill" .. r, false) end
        if menu and present then
            local ry = PANEL.y + 40 + (r - 1) * (PANEL.rowH + PANEL.gap)
            local hover = mp and mp.X >= PANEL.x + 10 and mp.X <= PANEL.x + PANEL.w - 10 and mp.Y >= ry and mp.Y <= ry + PANEL.rowH
            local label = rows[r].text
            if hud.rowLabel == nil then hud.rowLabel = {} end
            if hud.rowLabel[r] ~= label then hud.rowLabel[r] = label; hud.rowT[r]:SetText(FText(label)) end
            local c = hover and { R = 0.36, G = 0.5, B = 0.38, A = 0.95 } or { R = 0.2, G = 0.27, B = 0.22, A = 0.9 }
            if hud.rowHover == nil then hud.rowHover = {} end
            if hud.rowHover[r] ~= hover then hud.rowHover[r] = hover; hud.rows[r]:SetColorAndOpacity(c) end
            local sl = rows[r].slider
            setVis(hud.fill[r], "fill" .. r, sl ~= nil)
            if sl then
                local lmb = LC.down and LC.down.LEFT_MOUSE_BUTTON
                if lmb and mp and (LC.sliderActive == r or (not LC.sliderActive and hover)) then
                    LC.sliderActive = r
                    local f = math.max(0, math.min(1, (mp.X - (PANEL.x + 10)) / (PANEL.w - 20)))
                    local v = sl[1] + f * (sl[2] - sl[1])
                    v = math.floor(v / sl[3] + 0.5) * sl[3]
                    if v ~= sl[4]() then sl[5](v); LC.saveCfg(); LC.fovSize = nil; hud.size = nil end
                end
                local frac = (sl[4]() - sl[1]) / (sl[2] - sl[1])
                if hud.fillFrac == nil then hud.fillFrac = {} end
                if hud.fillFrac[r] ~= frac or hud.fillShown ~= hud.nRows then hud.fillFrac[r] = frac; hud.fillS[r]:SetSize({ X = math.max(1, (PANEL.w - 20) * frac), Y = PANEL.rowH }) end
            end
        end
    end
    hud.fillShown = hud.nRows
    if not (LC.down and LC.down.LEFT_MOUSE_BUTTON) and LC.sliderActive then
        LC.sliderActive = nil
        if LC.gfxDirty then LC.gfxDirty = false; if LC.gfxOn then LC.applyGfx(true) end end
    end
    -- Minecraft's FOV 70 is vertical; convert to the horizontal angle Unreal's camera expects for this aspect ratio
    if LC.fovSize ~= key then
        LC.fovSize = key
        local _, pawn = pcpawn()
        local cam = pawn and pawn:GetComponentByClass(cameraClass)
        if cam and cam:IsValid() then
            local aspect = MOBILE_ASPECT + (vs.X / vs.Y - MOBILE_ASPECT) * LC.shape
            local constrained = LC.shape < 0.999
            local vfov = LC.fovV + MOBILE_ZOOMOUT * (1 - LC.shape)
            local hf = math.deg(2 * math.atan(math.tan(math.rad(vfov / 2)) * aspect))
            pcall(function()
                cam.bConstrainAspectRatio = constrained
                if constrained then cam.AspectRatio = aspect end
            end)
            cam:SetFieldOfView(hf)
            LC.fovApplied = hf; LC.fovNow = hf; LC.fovSet = hf
        end
    end
end

-- the game's title logo (HomeMenu, launch scene, in-game menu overlay) becomes the LushfoilCraft logo; credits text is left as the game has it
LC.brandTick = function(launchUp)
    if LC.now - (LC.brandT or -100) < (launchUp and 2 or 12) then return end
    LC.brandT = LC.now
    local logo = texture("lc_logo")
    if not logo then return end
    local n = 0
    for _, im in ipairs(FindAllOf("Image") or {}) do
        if im:IsValid() and not (LC.levelChanged and im:GetFullName():find("MenuLaunchAnim")) then
            local ok, name = pcall(function() local r = im.Brush.ResourceObject; return r and r:IsValid() and r:GetFName():ToString() or "" end)
            if ok and name == "logo_final_1" then im:SetBrushFromTexture(logo, false); n = n + 1 end
        end
    end
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        if t:IsValid() then
            local full = t:GetFullName()
            if not LC.levelChanged and full:find("MenuLaunchAnim") and full:find("adjustinggraphicstext") then
                local ok, cur = pcall(function() return t:GetText():ToString() end)
                if ok and cur ~= "loading LushfoilCraft ..." then t:SetText(FText("loading LushfoilCraft ...")); n = n + 1 end
            end
        end
    end
    if n > 0 then log("branding applied to %d widgets", n) end
end

-- a click while the menu panel is up: toggle the row under the mouse
LC.applyGfx = function(on) applyGfx(on) end
LC.menuClick = function()
    local mp = LC.mouseU
    if not (LC.menuUp and mp) then return false end
    if LC.now - (LC.menuClickT or -1) < 0.3 then return true end
    local rows = panelRows()
    for r = 1, #rows do
        local ry = PANEL.y + 40 + (r - 1) * (PANEL.rowH + PANEL.gap)
        if mp.X >= PANEL.x + 10 and mp.X <= PANEL.x + PANEL.w - 10 and mp.Y >= ry and mp.Y <= ry + PANEL.rowH then
            LC.menuClickT = LC.now
            if rows[r].act then rows[r].act() end
            if hud then hud.rowLabel = nil end
            return true
        end
    end
    return false
end

-- ------------------------------------------------------------------ block break particles, item drops, hand swing, selection outline
-- All of it advances in Minecraft ticks (20 per second) with the same constants as Java Edition, rendered every frame between ticks.
local MCTICK = 0.05
local fx = { acc = 0, parts = {}, drops = {}, pool = {}, outline = {}, inv = LC.inv or {} }
LC.inv = fx.inv
LC.fx = fx

local function acquire(mesh, mat, sx, sy, sz)
    local a = table.remove(fx.pool)
    if not (a and a:IsValid()) then
        a = spawnMesh(mesh, mat, 0, 0, -100000, 0, false)
        if not a then return nil end
        a.StaticMeshComponent:SetCastShadow(false)
    else
        a:SetActorHiddenInGame(false)
        a.StaticMeshComponent:SetMaterial(0, mat)
    end
    local c = a.StaticMeshComponent
    if c.StaticMesh ~= mesh then c:SetStaticMesh(mesh) end
    c:K2_SetRelativeRotation(mesh == planeMesh and { Pitch = 90, Yaw = 0, Roll = 0 } or { Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, false)
    c:SetWorldScale3D({ X = sx, Y = sy, Z = sz })
    return a
end
local function release(a)
    if a and a:IsValid() then a:SetActorHiddenInGame(true); a:K2_SetActorLocation({ X = 0, Y = 0, Z = -100000 }, false, {}, true); fx.pool[#fx.pool + 1] = a end
end

local function groundZ(x, y, z, up, down)
    local pc, pawn = pcpawn()
    local hit = {}
    local ok = KSL:LineTraceSingle(world(), { X = x, Y = y, Z = z + (up or 30) }, { X = x, Y = y, Z = z - (down or 400) }, 0, false, { pawn }, 0, hit, true,
        { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    if ok and hit.bBlockingHit then return hit.ImpactPoint.Z end
end

-- what a block turns into when mined (survival rules as if with the right tool; there is no inventory yet, so pickups only count up in LC.inv)
local NO_DROP = { "glass", "^ice$", "^bedrock$", "spawner", "budding_amethyst", "^barrier$", "^light$", "reinforced_deepslate", "command_block", "^fire$", "^soul_fire$", "sculk", "monster_egg", "infested", "^frosted_ice$", "_wall_hanging_sign$" }
local AS_BLOCK = { stone = "cobblestone", grass_block = "dirt", podzol = "dirt", mycelium = "dirt", dirt_path = "dirt", farmland = "dirt", deepslate = "cobbled_deepslate", rooted_dirt = "dirt", coarse_dirt = "coarse_dirt" }
-- item, min, max, chance
local AS_ITEM = {
    coal_ore = { "coal", 1, 1 }, deepslate_coal_ore = { "coal", 1, 1 }, iron_ore = { "raw_iron", 1, 1 }, deepslate_iron_ore = { "raw_iron", 1, 1 },
    copper_ore = { "raw_copper", 2, 5 }, deepslate_copper_ore = { "raw_copper", 2, 5 }, gold_ore = { "raw_gold", 1, 1 }, deepslate_gold_ore = { "raw_gold", 1, 1 },
    diamond_ore = { "diamond", 1, 1 }, deepslate_diamond_ore = { "diamond", 1, 1 }, emerald_ore = { "emerald", 1, 1 }, deepslate_emerald_ore = { "emerald", 1, 1 },
    lapis_ore = { "lapis_lazuli", 4, 9 }, deepslate_lapis_ore = { "lapis_lazuli", 4, 9 }, redstone_ore = { "redstone", 4, 5 }, deepslate_redstone_ore = { "redstone", 4, 5 },
    nether_gold_ore = { "gold_nugget", 2, 6 }, nether_quartz_ore = { "quartz", 1, 1 }, clay = { "clay_ball", 4, 4 }, snow_block = { "snowball", 4, 4 },
    glowstone = { "glowstone_dust", 2, 4 }, sea_lantern = { "prismarine_crystals", 2, 3 }, gravel = { "flint", 1, 1, 0.1 },
    short_grass = { "wheat_seeds", 1, 1, 0.125 }, tall_grass = { "wheat_seeds", 1, 1, 0.125 }, fern = { "wheat_seeds", 1, 1, 0.125 },
}

local function dropsFor(name, can, tool)
    if can == false then return nil end
    if tool == "shears" and name:find("_leaves$") then return { kind = "block", name = name, count = 1 } end
    for _, pat in ipairs(NO_DROP) do if name:find(pat) then return nil end end
    if name:find("_leaves$") then
        local sap = name:gsub("_leaves$", "_sapling")
        if byName(sap) and math.random() < 0.05 then return { kind = "block", name = sap, count = 1 } end
        if math.random() < 0.02 then return { kind = "item", name = "stick", count = math.random(1, 2) } end
        return nil
    end
    local it = AS_ITEM[name]
    if it then
        if it[4] and math.random() >= it[4] then
            if name == "gravel" then return { kind = "block", name = "gravel", count = 1 } end
            return nil
        end
        return { kind = "item", name = it[1], count = math.random(it[2], it[3]) }
    end
    local b = AS_BLOCK[name]
    if b and byName(b) then return { kind = "block", name = b, count = 1 } end
    return { kind = "block", name = name, count = 1 }
end

-- the material of a block's "item" appearance
local function blockLook(name)
    local idx = byName(name)
    if not idx then return nil end
    local def = blocks[idx]
    if def[2] == "@model" then
        local sl = models[name]
        local pick = sl[1]
        for _, x in ipairs(sl) do if not x.m then pick = x break end end
        for _, x in ipairs(sl) do if x.m and x.s[1] >= 12 or x.m and x.s[3] >= 12 then pick = x break end end
        return pick.m and maskedMaterial(pick.i) or material(pick.i), pick.m and "flat" or "cube"
    end
    local _, _, side = faceFiles(def)
    return material(side), "cube"
end

-- particles -----------------------------------------------------------------------------------
local MAX_PARTS = 420
local function burst(name, i, j, k, limit)
    local mat = blockLook(name)
    if not mat then return end
    local cx, cy, cz = (i + 0.5) * 100, (j + 0.5) * 100, (k + 0.5) * 100
    local floorZ = groundZ(cx, cy, cz, 0, 1200)
    for a = 0, 3 do for b = 0, 3 do for c = 0, 3 do
        if limit and math.random() * 64 >= limit then goto skip end
        if #fx.parts >= MAX_PARTS then release(fx.parts[1].a); table.remove(fx.parts, 1) end
        local ox, oy, oz = (a + 0.5) / 4 - 0.5, (b + 0.5) / 4 - 0.5, (c + 0.5) / 4 - 0.5
        -- Minecraft's Particle constructor: random jitter, then normalised to a speed of 0.06..0.18 blocks/tick, +0.1 upward
        local vx, vy, vz = ox + (math.random() * 2 - 1) * 0.4, oy + (math.random() * 2 - 1) * 0.4, oz + (math.random() * 2 - 1) * 0.4
        local sp = (math.random() + math.random() + 1) * 0.15
        local len = math.sqrt(vx * vx + vy * vy + vz * vz); if len < 1e-6 then len = 1 end
        vx, vy, vz = vx / len * sp * 0.4, vy / len * sp * 0.4 + 0.1, vz / len * sp * 0.4
        local size = (0.5 + math.random() * 0.5) * 0.17
        local act = acquire(cubeMesh, mat, size, size, size)
        if act then
            fx.parts[#fx.parts + 1] = {
                a = act, x = cx + ox * 100, y = cy + oy * 100, z = cz + oz * 100, px = 0, py = 0, pz = 0, vx = vx, vy = vy, vz = vz,
                life = math.floor(4 / (math.random() * 0.9 + 0.1)), age = 0, half = size * 50, floor = floorZ, ground = false,
            }
            local p = fx.parts[#fx.parts]; p.px, p.py, p.pz = p.x, p.y, p.z
        end
        ::skip::
    end end end
end
local function burstSmall(name, i, j, k) burst(name, i, j, k, 4) end

-- item drops ----------------------------------------------------------------------------------
local MAX_DROPS = 60
local function spawnDrop(def, i, j, k, opts)
    local mat, kind, side, w
    if def.kind == "item" then
        mat = maskedMaterial("item_" .. def.name); kind = "flat"
    else
        mat, kind = blockLook(def.name)
    end
    if not mat then return end
    if #fx.drops >= MAX_DROPS then local old = table.remove(fx.drops, 1); for _, a in ipairs(old.actors) do release(a) end end
    local n = def.count == 1 and 1 or (def.count <= 16 and 2 or 3)
    local actors, offs = {}, {}
    for m = 1, n do
        local a
        if kind == "flat" then a = acquire(planeMesh, mat, 0.25, 0.25, 0.25) else a = acquire(cubeMesh, mat, 0.25, 0.25, 0.25) end
        if a then actors[#actors + 1] = a; offs[#offs + 1] = { (math.random() - 0.5) * 0.3 * 100 * (m > 1 and 1 or 0), (math.random() - 0.5) * 0.3 * 100 * (m > 1 and 1 or 0), (m - 1) * 3 } end
    end
    if #actors == 0 then return end
    local d = {
        def = def, actors = actors, offs = offs, kind = kind,
        x = (i + 0.5) * 100 + (math.random() - 0.5) * 25, y = (j + 0.5) * 100 + (math.random() - 0.5) * 25, z = (k + 0.5) * 100 - 3,
        vx = (math.random() * 0.2 - 0.1), vy = (math.random() * 0.2 - 0.1), vz = 0.2,
        age = 0, delay = 10, bob = math.random() * math.pi * 2, ground = false, gz = nil, nextGround = 0,
    }
    if opts then d.x, d.y, d.z = opts.x or d.x, opts.y or d.y, opts.z or d.z; d.vx, d.vy, d.vz = opts.vx or d.vx, opts.vy or d.vy, opts.vz or d.vz; d.delay = opts.delay or d.delay end
    d.px, d.py, d.pz = d.x, d.y, d.z
    fx.drops[#fx.drops + 1] = d
end

local function removeDrop(d)
    for _, a in ipairs(d.actors) do release(a) end
    for n, x in ipairs(fx.drops) do if x == d then table.remove(fx.drops, n) break end end
end

-- one Minecraft tick
local function stepTick()
    local _, pawn = pcpawn()
    if LC.fallStep then LC.fallStep() end
    for n = #fx.parts, 1, -1 do
        local p = fx.parts[n]
        p.age = p.age + 1
        if p.age >= p.life then release(p.a); table.remove(fx.parts, n)
        else
            p.px, p.py, p.pz = p.x, p.y, p.z
            p.vz = p.vz - 0.04
            p.x, p.y, p.z = p.x + p.vx * 100, p.y + p.vy * 100, p.z + p.vz * 100
            if p.floor and p.z - p.half <= p.floor then p.z = p.floor + p.half; p.vz = 0; p.ground = true else p.ground = false end
            p.vx, p.vy, p.vz = p.vx * 0.98, p.vy * 0.98, p.vz * 0.98
            if p.ground then p.vx, p.vy = p.vx * 0.7, p.vy * 0.7 end
        end
    end
    local pl = pawn and pawn:K2_GetActorLocation()
    if LC.mode == "survival" and pawn and pl and LC.survStep then local ok, e = pcall(LC.survStep, pawn, pl); if not ok and e ~= LC.survErr then LC.survErr = e; log("survival error: %s", tostring(e)) end end
    for n = #fx.drops, 1, -1 do
        local d = fx.drops[n]
        d.age = d.age + 1
        d.px, d.py, d.pz = d.x, d.y, d.z
        if d.pick then
            d.pick = d.pick + 1
            if d.pick > 3 or not pl then
                local left = LC.takeDrop and LC.takeDrop(d.def) or d.def.count
                if left and left > 0 then d.def.count = left; d.pick = nil; d.delay = d.age + 20 else removeDrop(d) end
            else
                local t = d.pick / 4
                d.x, d.y, d.z = d.x + (pl.X - d.x) * t, d.y + (pl.Y - d.y) * t, d.z + (pl.Z - 40 - d.z) * t
            end
        else
            d.vz = d.vz - 0.04
            if d.age >= d.nextGround or not d.ground then
                d.gz = groundZ(d.x, d.y, d.z + 10, 20, 500)
                d.nextGround = d.age + (d.ground and 10 or 1)
            end
            d.x, d.y, d.z = d.x + d.vx * 100, d.y + d.vy * 100, d.z + d.vz * 100
            local rest = d.gz and (d.gz + 12.5) or nil
            d.ground = false
            if rest and d.z <= rest then
                d.z = rest; d.ground = true
                if d.vz < 0 then d.vz = d.vz * -0.5 end
                if math.abs(d.vz) < 0.02 then d.vz = 0 end
            end
            local f = d.ground and 0.588 or 0.98
            d.vx, d.vy, d.vz = d.vx * f, d.vy * f, d.vz * 0.98
            if d.age >= d.delay and pl and LC.canTake and LC.canTake(d.def) then
                local dx, dy, dz = pl.X - d.x, pl.Y - d.y, pl.Z - d.z
                if dx * dx + dy * dy < 100 * 100 and dz > -140 and dz < 110 then d.pick = 0 end
            end
            if d.age > 6000 then removeDrop(d) end
        end
    end
end

-- hand swing (attack / use animation, 6 ticks like Minecraft)
local function swing() fx.swingT = LC.now; LC.swingT = LC.now end

local function renderHeld()
    if LC.third then return end
    local flat = LC.heldKey and LC.heldKey:sub(1, 5) == "item:"
    local bx, by, bz = 34, 17, -16
    local br = { Pitch = 10, Yaw = 35, Roll = 8 }
    if flat then bx, by, bz = 38, 16, -13; br = LC.flatHeldRot end
    local t = fx.swingT and (LC.now - fx.swingT) / 0.3
    local animating = t and t < 1
    -- motion of the hand besides the swing: walking bob, sway while turning, the lift when a new item is taken out
    local hb, sw = LC.handBob or {}, LC.handSway or {}
    local eq = 0
    if LC.equipT then
        local e = (LC.now - LC.equipT) / 0.22
        if e >= 1 then LC.equipT = nil else eq = -16 * (1 - e * e * (3 - 2 * e)) end
    end
    local oy, oz = (hb.y or 0) + (sw.y or 0), (hb.z or 0) + (sw.z or 0) + eq
    if LC.flying then oy, oz = 0, 0 end               -- the hand stays still while flying
    local moving = math.abs(oy) + math.abs(oz) > 0.05
    if not animating and not moving and not fx.posed then return end
    local f1, f2, f3 = 0, 0, 0
    if animating then
        f1 = math.sin(math.sqrt(t) * math.pi)              -- Java Edition's swing curve
        f2 = math.sin(2 * math.sqrt(t) * math.pi)
        f3 = math.sin(t * math.pi)
    elseif fx.swingT then fx.swingT = nil end
    fx.posed = (animating or moving) and true or false
    -- the held item
    if LC.held and LC.held:IsValid() then
        local c = LC.held.StaticMeshComponent
        c:K2_SetRelativeLocation({ X = bx + 16 * f3, Y = by - 20 * f1 + oy, Z = bz - 12 * f1 + 7 * f2 + oz }, false, {}, false)
        if flat then c:K2_SetRelativeRotation({ Pitch = br.Pitch, Yaw = br.Yaw - 40 * f1, Roll = br.Roll + 25 * f3 }, false, {}, false)
        else c:K2_SetRelativeRotation({ Pitch = br.Pitch - 70 * f1, Yaw = br.Yaw - 25 * f1, Roll = br.Roll + 20 * f3 }, false, {}, false) end
    end
    -- the arm
    if LC.fpArm and LC.fpArm.pivot:IsValid() then
        local al, ar = LC.armBase()
        local c = LC.fpArm.pivot.StaticMeshComponent
        c:K2_SetRelativeLocation({ X = al.X + 16 * f3, Y = al.Y - 20 * f1 + oy, Z = al.Z - 12 * f1 + 7 * f2 + oz }, false, {}, false)
        c:K2_SetRelativeRotation({ Pitch = ar.Pitch + 28 * f1, Yaw = ar.Yaw - 30 * f1, Roll = ar.Roll }, false, {}, false)
    end
end

-- selection outline: the black wireframe Minecraft draws around the block you are aiming at
local function outlineBox(cellKey)
    local b = LC.world[cellKey]
    if not b then return nil end
    local lo, hi = { 0, 0, 0 }, { 16, 16, 16 }          -- block pixels: x east, y up, z south
    local sl = models[b.name]
    if sl then
        lo, hi = { 99, 99, 99 }, { -99, -99, -99 }
        for _, s in ipairs(sl) do for ax = 1, 3 do
            lo[ax] = math.min(lo[ax], s.c[ax] - s.s[ax] / 2); hi[ax] = math.max(hi[ax], s.c[ax] + s.s[ax] / 2)
        end end
    end
    return lo, hi
end

local function updateOutline()
    local pc, pawn = pcpawn()
    local show = pawn and LC.hudOn
    local inside
    if show then local ins, _, isBlock = target(); if isBlock then inside = ins end end
    if not inside then
        for _, a in ipairs(fx.outline) do a:SetActorHiddenInGame(true) end
        fx.outCell = nil
        return
    end
    local ck = keyOf(inside[1], inside[2], inside[3])
    local lo, hi = outlineBox(ck)
    if not lo then return end
    local mat = material("outline")
    local eps = 0.12
    -- UE: X north = -(z south), Y east = x, Z up = y
    local bx = (inside[1] + 0.5) * 100
    local by = (inside[2] + 0.5) * 100
    local bz = inside[3] * 100
    local nx0, nx1 = bx + (8 - hi[3]) * 6.25 - eps, bx + (8 - lo[3]) * 6.25 + eps
    local ny0, ny1 = by + (lo[1] - 8) * 6.25 - eps, by + (hi[1] - 8) * 6.25 + eps
    local nz0, nz1 = bz + lo[2] * 6.25 - eps, bz + hi[2] * 6.25 + eps
    local loc, _ = viewRay()
    local dist = math.sqrt((loc.X - bx) ^ 2 + (loc.Y - by) ^ 2 + (loc.Z - (nz0 + nz1) / 2) ^ 2)
    local th = math.max(0.45, dist * 0.0022)
    local bars = {}
    for _, yy in ipairs({ ny0, ny1 }) do for _, zz in ipairs({ nz0, nz1 }) do bars[#bars + 1] = { (nx0 + nx1) / 2, yy, zz, nx1 - nx0 + th, th, th } end end
    for _, xx in ipairs({ nx0, nx1 }) do for _, zz in ipairs({ nz0, nz1 }) do bars[#bars + 1] = { xx, (ny0 + ny1) / 2, zz, th, ny1 - ny0 + th, th } end end
    for _, xx in ipairs({ nx0, nx1 }) do for _, yy in ipairs({ ny0, ny1 }) do bars[#bars + 1] = { xx, yy, (nz0 + nz1) / 2, th, th, nz1 - nz0 + th } end end
    for n, bar in ipairs(bars) do
        local a = fx.outline[n]
        if not (a and a:IsValid()) then
            a = spawnMesh(cubeMesh, mat, 0, 0, -100000, 0, false)
            a.StaticMeshComponent:SetCastShadow(false)
            fx.outline[n] = a
        end
        a:SetActorHiddenInGame(false)
        a.StaticMeshComponent:SetWorldScale3D({ X = bar[4] / 100, Y = bar[5] / 100, Z = bar[6] / 100 })
        a:K2_SetActorLocation({ X = bar[1], Y = bar[2], Z = bar[3] }, false, {}, true)
    end
end

local function renderFx(alpha)
    for _, p in ipairs(fx.parts) do
        p.a:K2_SetActorLocation({ X = p.px + (p.x - p.px) * alpha, Y = p.py + (p.y - p.py) * alpha, Z = p.pz + (p.z - p.pz) * alpha }, false, {}, true)
    end
    for _, d in ipairs(fx.drops) do
        local age = d.age + alpha
        local bob = d.pick and 0 or (math.sin(age / 10 + d.bob) * 0.1 + 0.1) * 100
        local x, y, z = d.px + (d.x - d.px) * alpha, d.py + (d.y - d.py) * alpha, d.pz + (d.z - d.pz) * alpha + bob
        local yaw = math.deg(age / 20 + d.bob)
        for n, a in ipairs(d.actors) do
            local o = d.offs[n]
            a:K2_SetActorLocationAndRotation({ X = x + o[1], Y = y + o[2], Z = z + o[3] }, { Pitch = 0, Yaw = yaw, Roll = 0 }, false, {}, true)
        end
    end
end

local fxErrors = 0
local BOB_RATE, BOB_AMP = 0.28, 0.45       -- Java Edition is 0.6 and 1.0; this is a much slower, calmer bob with the same U shape
local bobD, bobB, bobApplied = 0, 0, false
local function bobFrame(dt)
    local cam, base = LC.moveCam, LC.camHome
    if not (cam and base and cam:IsValid()) then return end
    local active = LC.walkStyle == "minecraft" and not LC.third and LC.hudOn and not LC.flying and LC.moveMode == 1
    local hs = active and (LC.moveSpeed or 0) or 0
    -- Java Edition: amount = min(0.1, speed per tick), eased 0.4 per tick; the view sways sin and dips |cos| of the distance walked (x0.6)
    local target = math.min(0.1, hs / 100 / 20)
    bobB = bobB + (target - bobB) * math.min(1, dt * 20 * 0.4)
    if hs > 5 then bobD = bobD + hs * dt / 100 * BOB_RATE end
    -- Java Edition (GameRenderer.bobView) shifts the whole screen, hand included, by
    --   x = sin(walked * pi) * amount * 0.5     y = -|cos(walked * pi)| * amount        (blocks; walked = distance * 0.6)
    -- so every step traces a small U: sway to a side while rising, a dip in the middle of the step.
    local sx, sy = 0, 0
    if bobB >= 0.0008 then sx, sy = math.sin(bobD * math.pi) * bobB * 50 * BOB_AMP, -math.abs(math.cos(bobD * math.pi)) * bobB * 100 * BOB_AMP end   -- screen shift, cm
    if bobB >= 0.0008 then
        bobApplied = true
        -- the camera moves the opposite way (eye height kept on average: |cos| has a mean of 0.64)
        cam:K2_SetRelativeLocation({ X = base.X, Y = base.Y - sx, Z = base.Z - sy - 0.64 * bobB * 100 * BOB_AMP }, false, {}, false)
    elseif bobApplied then bobApplied = false; cam:K2_SetRelativeLocation(base, false, {}, false) end
    -- the hand takes the very same screen shift as the view (the camera carries it, so it is moved by hand), and lags a little when you turn
    local hb = LC.handBob or {}; LC.handBob = hb
    if LC.flying then sx, sy = 0, 0 end                 -- no bob while flying
    hb.y, hb.z = sx, sy
    local sw = LC.handSway or { y = 0, z = 0 }; LC.handSway = sw
    local pcc = getPC()
    if pcc and LC.hudOn and not LC.third then
        local ok, rot = pcall(function() return pcc:GetControlRotation() end)
        if ok then
            local yaw, pitch = rot.Yaw, rot.Pitch
            if pitch > 180 then pitch = pitch - 360 end
            if LC.lastYaw then
                local dy = ((yaw - LC.lastYaw + 540) % 360) - 180
                local dp = pitch - LC.lastPitch
                sw.y = math.max(-4, math.min(4, sw.y - dy * 0.2))
                sw.z = math.max(-3, math.min(3, sw.z + dp * 0.2))
            end
            LC.lastYaw, LC.lastPitch = yaw, pitch
        end
    else LC.lastYaw = nil end
    local decay = math.min(1, dt * 16)                -- settles fast: little momentum
    if LC.flying then decay = 1 end                   -- no sway while flying
    sw.y, sw.z = sw.y * (1 - decay), sw.z * (1 - decay)
end
local function fxFrame(dt)
    bobFrame(dt)
    -- creative flight: Space rises, Ctrl / Shift / left-stick click descends (about 5.4 blocks/s), moved every frame so it is smooth
    if LC.flying and LC.moveP and LC.moveP:IsValid() and not LC.menuUp and not (LC.inv and LC.inv.open) and not (LC.chat and LC.chat.open) then
        local dz = 0
        if down("SPACE") or down("GP_A") then dz = dz + 1 end
        if down("LCTRL") or down("LEFT_SHIFT") or down("GP_L3") then dz = dz - 1 end
        if dz ~= 0 then LC.moveP:K2_AddActorWorldOffset({ X = 0, Y = 0, Z = dz * 540 * math.min(dt, 0.05) }, true, {}, false) end
    end
    if LC.invTick then LC.invTick() end
    fx.acc = fx.acc + math.min(dt, 0.1)
    while fx.acc >= MCTICK do fx.acc = fx.acc - MCTICK; stepTick() end
    renderFx(fx.acc / MCTICK)
    if LC.fallRender then LC.fallRender(fx.acc / MCTICK) end
    renderHeld()
end
LC.frameFn = function(dtp)
    local dt0 = 0.016
    pcall(function() dt0 = dtp:get() end)
    LC.calm = (dt0 < 0.12) and ((LC.calm or 0) + 1) or 0                  -- consecutive smooth frames: level streaming shows up as hitches
    if LC.titleTick and not LC.idle then
        if not LC.travelFlag and (LC.suspendFrames or 0) <= 0 and (LC.calm or 0) >= 30 and LC.title and not LC.title.shown and LC.titleBoot then pcall(LC.titleBoot) end
        if LC.title and LC.title.active and (LC.suspendFrames or 0) <= 0 then
            local ok, e = pcall(LC.titleTick); if not ok and e ~= LC.titleErr then LC.titleErr = e; log("title error: %s", tostring(e)) end
        end
    end
    if (LC.suspendFrames or 0) > 0 then LC.suspendFrames = LC.suspendFrames - 1; return end
    if (LC.calm or 0) < 240 or (LC.travelAt and os.time() - LC.travelAt < 24) then return end
    LC.travelAt = nil      -- counted in frames: the first frame after a load carries the whole load time as its delta
    if fxErrors > 5 or LC.skip.frame then return end
    local dt = 0.016
    pcall(function() dt = dtp:get() end)
    local ok, e = pcall(fxFrame, dt)
    if not ok then fxErrors = fxErrors + 1; log("fx error: %s", tostring(e)) end
end
LC.hudFn = function()
    local ok, e = pcall(hudTick)
    if not ok and e ~= LC.hudErr then LC.hudErr = e; log("hud error: %s", tostring(e)) end
    local ok2, e2 = pcall(updateOutline)
    if not ok2 and e2 ~= LC.outErr then LC.outErr = e2; log("outline error: %s", tostring(e2)) end
end
if not LC.fxHook then
    local ok = pcall(RegisterHook, "/Game/FirstPersonBP/Blueprints/FirstPersonPlayerController.FirstPersonPlayerController_C:ReceiveTick", function(self, dtp)
        if LC.frameFn then LC.frameFn(dtp) end
    end)
    LC.fxHook = ok
    log("per-frame fx hook %s", ok and "installed" or "FAILED")
end

LC.fxBreak = function() swing() end
LC.fxBurst = burst
LC.blockLook = blockLook
LC.fxPlace = swing
LC.hudRefresh = hudRefresh
LC.hudNote = function() LC.nameT = LC.now end


LC.preTravel = function()
    -- the game's own values go back for the load (the tuned streaming pool / view scale / FOV lock while a level streams in made it crash)
    if LC.gfxOn then LC.gfxResume = true; pcall(applyGfx, false) end
    pcall(function() KSL:ExecuteConsoleCommand(world(), "fov 0", getPC()) end)
    LC.fovCmd = nil
    if LC.titleKill then pcall(LC.titleKill) end
    destroySteve(); hudKill()
    for _, p in ipairs(fx.parts) do if p.a and p.a:IsValid() then p.a:K2_DestroyActor() end end
    for _, d in ipairs(fx.drops) do for _, a in ipairs(d.actors) do if a and a:IsValid() then a:K2_DestroyActor() end end end
    for _, a in ipairs(fx.pool) do if a and a:IsValid() then a:K2_DestroyActor() end end
    for _, a in ipairs(fx.outline) do if a and a:IsValid() then a:K2_DestroyActor() end end
    for _, f in ipairs(fx.falling or {}) do if f.a and f.a:IsValid() then f.a:K2_DestroyActor() end end
    fx.parts, fx.drops, fx.pool, fx.outline, fx.falling = {}, {}, {}, {}, {}
    if LC.inv.open then LC.invClose() end
    if LC.invUI and LC.invUI.w and LC.invUI.w:IsValid() then pcall(function() LC.invUI.w:RemoveFromParent() end) end
    LC.invUI = nil
    if LC.fpArm then for _, a in ipairs(LC.fpArm.all) do if a and a:IsValid() then a:K2_DestroyActor() end end; LC.fpArm = nil end
    if LC.held and LC.held:IsValid() then pcall(function() LC.held:K2_DestroyActor() end) end
    LC.held, LC.heldKey = nil, nil
    if LC.dirty and LC.saveNow then pcall(LC.saveNow) end
end
LC.unload = function()
    destroySteve(); hudKill()
    for _, p in ipairs(fx.parts) do if p.a and p.a:IsValid() then p.a:K2_DestroyActor() end end
    for _, d in ipairs(fx.drops) do for _, a in ipairs(d.actors) do if a and a:IsValid() then a:K2_DestroyActor() end end end
    for _, a in ipairs(fx.pool) do if a and a:IsValid() then a:K2_DestroyActor() end end
    for _, a in ipairs(fx.outline) do if a and a:IsValid() then a:K2_DestroyActor() end end
    LC.frameFn = nil; LC.hudFn = nil; LC.updateArm = nil
    if LC.inv.open then LC.invClose() end
    if LC.invUI and LC.invUI.w and LC.invUI.w:IsValid() then pcall(function() LC.invUI.w:RemoveFromParent() end) end
    LC.invUI = nil
    if LC.fpArm then for _, a in ipairs(LC.fpArm.all) do if a and a:IsValid() then a:K2_DestroyActor() end end; LC.fpArm = nil end
end
LC.keys.F1 = function() LC.hudHidden = not LC.hudHidden end

-- ------------------------------------------------------------------ game modes: creative / survival, flight, fast walking, free roaming, unlocks
local CFG = LC.data .. "config.txt"
local function loadCfg()
    local t = {}
    local f = io.open(CFG, "r")
    if f then for l in f:lines() do local k, v = l:match("^(%w+)=(.*)$"); if k then t[k] = v end end f:close() end
    return t
end
function LC.saveCfg()
    local f = io.open(CFG, "w")
    if f then f:write(("mode=%s\nfast=%d\nkit=%d\nfov=%.1f\nshape=%.3f\nrdist=%d\nwalk=%s\n"):format(LC.mode, LC.fast and 1 or 0, LC.kit and 1 or 0, LC.fovV, LC.shape, LC.rdist, LC.walkStyle)); f:close() end
end
do
    local c = loadCfg()
    if LC.mode == nil then LC.mode = c.mode == "survival" and "survival" or "creative" end
    if LC.fast == nil then LC.fast = c.fast == "1" end
    if LC.kit == nil then LC.kit = c.kit ~= "0" end
    LC.walkStyle = LC.walkStyle or (c.walk == "lushfoil" and "lushfoil" or "minecraft")   -- Minecraft walking (default) or LushfoilCraft walking
    LC.fovV = LC.fovV or tonumber(c.fov) or 70                       -- vertical field of view, Minecraft's slider (30-110, default 70)
    LC.shape = LC.shape or tonumber(c.shape) or (c.mobile == "1" and 0 or 1)    -- 1 = the window's own shape, 0 = portrait phone
    LC.rdist = LC.rdist or tonumber(c.rdist) or 12                   -- render distance in "chunks", Minecraft's slider (2-32, default 12)
end
local S = LC.surv
S.health = S.health or 20; S.food = S.food or 20; S.sat = S.sat or 5; S.exh = S.exh or 0
S.inv = S.inv or {}; S.invul = S.invul or 0; S.regen = S.regen or 0; S.starve = S.starve or 0

-- ---- items: tools, food, stacks
local TIERS = { wooden = { 2, 0 }, stone = { 4, 1 }, iron = { 6, 2 }, golden = { 12, 0 }, diamond = { 8, 3 }, netherite = { 9, 4 } }
local KINDS = { "pickaxe", "axe", "shovel", "hoe", "sword" }
local function toolOf(name)         -- -> class, speed, level
    if name == "shears" then return "shears", 1, 0 end
    for _, k in ipairs(KINDS) do
        local tier = name:match("^(%a+)_" .. k .. "$")
        if tier and TIERS[tier] then return k, TIERS[tier][1], TIERS[tier][2] end
    end
end
local FOOD = { apple = { 4, 2.4 }, bread = { 5, 6 }, cooked_beef = { 8, 12.8 } }
local function maxStack(st) return (st.kind == "item" and toolOf(st.name)) and 1 or 64 end

local function addToInv(kind, name, count)         -- returns what did not fit
    local inv = S.inv
    local cap = maxStack({ kind = kind, name = name })
    for s = 1, 36 do
        local st = inv[s]
        if st and st.kind == kind and st.name == name and st.count < cap then
            local n = math.min(cap - st.count, count); st.count = st.count + n; count = count - n
            if count == 0 then return 0 end
        end
    end
    for s = 1, 36 do
        if not inv[s] then
            local n = math.min(cap, count); inv[s] = { kind = kind, name = name, count = n }; count = count - n
            if count == 0 then return 0 end
        end
    end
    return count
end
local function fits(kind, name, count)
    local inv, cap = S.inv, maxStack({ kind = kind, name = name })
    for s = 1, 36 do
        local st = inv[s]
        if not st or (st.kind == kind and st.name == name and st.count < cap) then return true end
    end
    return false
end
local function afterInvChange()
    if LC.hudRefresh then LC.hudRefresh() end
    updateHeld()
end
LC.giveInv = function(kind, name, count) local left = addToInv(kind, name, count); afterInvChange(); return left end
LC.canTake = function(def) return LC.mode == "survival" and fits(def.kind, def.name, def.count) end
LC.takeDrop = function(def)
    local left = addToInv(def.kind, def.name, def.count)
    afterInvChange()
    return left
end

-- ---- how hard blocks are to break (Java Edition values); {name pattern, hardness, tool class, minimum tier needed to get a drop}
local miningStats
do
local P, A, SH, H, SW, SS = "pickaxe", "axe", "shovel", "hoe", "sword", "shears"
local RULES = {
    { "^bedrock$", -1 }, { "^barrier$", -1 }, { "reinforced_deepslate", -1 }, { "^end_portal", -1 }, { "^command_block", -1 },
    { "^obsidian$", 50, P, 3 }, { "crying_obsidian", 50, P, 3 }, { "ancient_debris", 30, P, 3 }, { "netherite_block", 50, P, 3 }, { "respawn_anchor", 50, P, 3 },
    { "deepslate_diamond_ore", 4.5, P, 2 }, { "deepslate_emerald_ore", 4.5, P, 2 }, { "deepslate_gold_ore", 4.5, P, 2 }, { "deepslate_redstone_ore", 4.5, P, 2 },
    { "deepslate_lapis_ore", 4.5, P, 1 }, { "deepslate_iron_ore", 4.5, P, 1 }, { "deepslate_copper_ore", 4.5, P, 1 }, { "deepslate_coal_ore", 4.5, P, 0 },
    { "diamond_ore", 3, P, 2 }, { "emerald_ore", 3, P, 2 }, { "gold_ore", 3, P, 2 }, { "redstone_ore", 3, P, 2 }, { "lapis_ore", 3, P, 1 },
    { "iron_ore", 3, P, 1 }, { "copper_ore", 3, P, 1 }, { "coal_ore", 3, P, 0 }, { "nether_gold_ore", 3, P, 0 }, { "quartz_ore", 3, P, 0 },
    { "^iron_block$", 5, P, 1 }, { "^diamond_block$", 5, P, 2 }, { "^emerald_block$", 5, P, 2 }, { "^gold_block$", 3, P, 2 }, { "^lapis_block$", 3, P, 1 },
    { "^redstone_block$", 5, P, 0 }, { "^coal_block$", 5, P, 0 }, { "copper", 3, P, 1 }, { "^anvil$", 5, P, 0 }, { "iron_bars", 5, P, 0 }, { "^chain$", 5, P, 0 },
    { "lantern", 3.5, P, 0 }, { "iron_door", 5, P, 0 }, { "iron_trapdoor", 5, P, 0 },
    -- things that break instantly
    { "torch", 0 }, { "_sapling$", 0 }, { "^poppy$", 0 }, { "^dandelion$", 0 }, { "tulip", 0 }, { "orchid", 0 }, { "allium", 0 }, { "azure_bluet", 0 },
    { "oxeye_daisy", 0 }, { "cornflower", 0 }, { "lily_of_the_valley", 0 }, { "^wither_rose$", 0 }, { "^rose_bush$", 0 }, { "^peony$", 0 }, { "^lilac$", 0 }, { "^sunflower$", 0 },
    { "short_grass", 0 }, { "tall_grass", 0 }, { "^fern$", 0 }, { "large_fern", 0 }, { "dead_bush", 0 }, { "mushroom$", 0 }, { "sugar_cane", 0 }, { "redstone_wire", 0 },
    { "repeater", 0 }, { "comparator", 0 }, { "tripwire", 0 }, { "^tnt$", 0 }, { "slime_block", 0 }, { "honey_block", 0 }, { "scaffolding", 0 }, { "sweet_berry", 0 },
    { "^moss_carpet$", 0.1, H }, { "carpet", 0.1 }, { "^snow$", 0.1, SH, 0 }, { "^vine$", 0.2, A }, { "glow_lichen", 0.2 }, { "^lever$", 0.5 }, { "button", 0.5 },
    -- earth
    { "^sand$", 0.5, SH }, { "red_sand", 0.5, SH }, { "gravel", 0.6, SH }, { "^clay$", 0.6, SH }, { "^dirt$", 0.5, SH }, { "coarse_dirt", 0.5, SH }, { "podzol", 0.5, SH },
    { "mycelium", 0.6, SH }, { "grass_block", 0.6, SH }, { "farmland", 0.6, SH }, { "dirt_path", 0.65, SH }, { "rooted_dirt", 0.5, SH }, { "^mud$", 0.5, SH },
    { "soul_sand", 0.5, SH }, { "soul_soil", 0.5, SH }, { "snow_block", 0.2, SH, 0 }, { "concrete_powder", 0.5, SH }, { "moss_block", 0.1, H },
    -- stone family
    { "deepslate", 3.5, P, 0 }, { "^stone$", 1.5, P, 0 }, { "cobblestone", 2, P, 0 }, { "stone_brick", 1.5, P, 0 }, { "granite", 1.5, P, 0 }, { "diorite", 1.5, P, 0 },
    { "andesite", 1.5, P, 0 }, { "tuff", 1.5, P, 0 }, { "calcite", 0.75, P, 0 }, { "brick", 2, P, 0 }, { "sandstone", 0.8, P, 0 }, { "basalt", 1.25, P, 0 },
    { "blackstone", 1.5, P, 0 }, { "netherrack", 0.4, P, 0 }, { "end_stone", 3, P, 0 }, { "prismarine", 1.5, P, 0 }, { "purpur", 1.5, P, 0 }, { "quartz", 0.8, P, 0 },
    { "glazed_terracotta", 1.4, P, 0 }, { "terracotta", 1.25, P, 0 }, { "concrete", 1.8, P, 0 }, { "magma_block", 0.5, P, 0 }, { "furnace", 3.5, P, 0 },
    { "dripstone", 1.5, P, 0 }, { "amethyst", 1.5, P, 0 }, { "bone_block", 2, P, 0 }, { "smooth_stone", 2, P, 0 }, { "stone", 1.5, P, 0 }, { "coral_block", 1.5, P, 0 },
    { "ice", 0.5, P }, { "glass", 0.3 }, { "glowstone", 0.3 }, { "sea_lantern", 0.3 }, { "redstone_lamp", 0.3 },
    -- wood and plants
    { "_leaves$", 0.2, H }, { "log$", 2, A }, { "wood$", 2, A }, { "stem$", 2, A }, { "hyphae", 2, A }, { "planks", 2, A }, { "fence", 2, A }, { "door", 3, A },
    { "trapdoor", 3, A }, { "sign", 1, A }, { "crafting_table", 2.5, A }, { "bookshelf", 1.5, A }, { "barrel", 2.5, A }, { "chest", 2.5, A }, { "pumpkin", 1, A },
    { "melon", 1, A }, { "bamboo", 1, SW }, { "hay_block", 0.5, H }, { "cactus", 0.4 }, { "sponge", 0.6, H }, { "wool", 0.8, SS }, { "shroomlight", 1, H },
    { "sculk", 0.6, H }, { "cobweb", 4, SW }, { "ladder", 0.4, A }, { "note_block", 0.8, A }, { "jukebox", 2, A }, { "beehive", 0.6, A }, { "bee_nest", 0.3 },
}
local ruleCache = {}
local function ruleFor(name)
    local r = ruleCache[name]
    if r then return r end
    for _, x in ipairs(RULES) do if name:find(x[1]) then r = x break end end
    r = r or { ".", 1 }
    ruleCache[name] = r
    return r
end

-- mining time for a block with the tool in hand -> hardness, speed, canHarvest
function miningStats(name)
    local rule = ruleFor(name)
    local hardness, class, level = rule[2], rule[3], rule[4]
    local st = S.inv[LC.slot]
    local tc, tspeed, tlevel
    if st and st.kind == "item" then tc, tspeed, tlevel = toolOf(st.name) end
    local speed = 1
    if class and tc == class then speed = tspeed
    elseif class == H and tc == SS then speed = 15                    -- shears on leaves
    elseif class == SS and tc == SS then speed = 5                    -- shears on wool
    elseif class == SW and tc == SW then speed = 15
    elseif tc == SW then speed = 1.5 end
    if tc == SS and name:find("_leaves$") then speed = 15 end
    local can = true
    if level then can = (tc == class and class == P and tlevel >= level) or (class == SH and level == 0 and tc == SH) end
    if hardness > 0 and name:find("_leaves$") then can = true end
    return hardness, speed, can, tc
end
LC.miningStats = miningStats
LC.act_mining = function(name) return miningStats(name) end

-- ---- gravity blocks, blocks that need support
end

local GRAV = { "^sand$", "^red_sand$", "^gravel$", "concrete_powder$", "^anvil$" }
local NEEDS = { "torch", "_sapling$", "^poppy$", "^dandelion$", "tulip", "orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley",
    "^rose_bush$", "^peony$", "^lilac$", "^sunflower$", "short_grass", "tall_grass", "^fern$", "large_fern", "dead_bush", "mushroom$", "^rail$", "_rail$", "carpet",
    "pressure_plate", "sweet_berry", "redstone_wire", "repeater", "comparator", "^snow$" }
local function matchAny(list, name) for _, p in ipairs(list) do if name:find(p) then return true end end return false end

local function supported(i, j, k)
    if LC.world[keyOf(i, j, k - 1)] then return true end
    local z = groundZ((i + 0.5) * 100, (j + 0.5) * 100, k * 100 + 3, 0, 40)
    return z ~= nil
end

fx.falling = fx.falling or {}
local function startFall(i, j, k)
    local b = LC.world[keyOf(i, j, k)]
    if not b then return end
    local name = b.name
    remove(i, j, k)
    local mat = blockLook(name)
    local a = mat and acquire(cubeMesh, mat, 1, 1, 1)
    if not a then return end
    fx.falling[#fx.falling + 1] = { a = a, name = name, x = (i + 0.5) * 100, y = (j + 0.5) * 100, z = (k + 0.5) * 100, vz = 0, i = i, j = j }
    a:K2_SetActorLocation({ X = (i + 0.5) * 100, Y = (j + 0.5) * 100, Z = (k + 0.5) * 100 }, false, {}, true)
    LC.afterRemove(i, j, k)
end

LC.dropItem = function(def, l) spawnDrop(def, cell(l.X), cell(l.Y), cell(l.Z)) end
local function dropAt(def, i, j, k, opts)
    if def then spawnDrop(def, i, j, k, opts) end
end

-- what happens around a cell that just lost its block
LC.afterRemove = function(i, j, k)
    local up = LC.world[keyOf(i, j, k + 1)]
    if not up then return end
    if matchAny(GRAV, up.name) then startFall(i, j, k + 1)
    elseif matchAny(NEEDS, up.name) then
        local name = up.name
        remove(i, j, k + 1)
        if LC.mode == "survival" then burst(name, i, j, k + 1); dropAt(dropsFor(name, true), i, j, k + 1) end
        LC.afterRemove(i, j, k + 1)
    end
end
LC.afterPlace = function(i, j, k)
    local b = LC.world[keyOf(i, j, k)]
    if b and matchAny(GRAV, b.name) and not supported(i, j, k) then startFall(i, j, k) end
end

-- falling blocks advance with the other entities (called from stepTick)
LC.fallStep = function()
    for n = #fx.falling, 1, -1 do
        local f = fx.falling[n]
        f.pz = f.z
        f.vz = f.vz - 0.04
        f.z = f.z + f.vz * 100
        f.vz = f.vz * 0.98
        local hz = groundZ(f.x, f.y, f.z + 50, 0, 160)
        if hz and f.z - 50 <= hz + 1 then
            local k = math.floor((hz + 45) / 100)
            local idx = byName(f.name)
            release(f.a)
            table.remove(fx.falling, n)
            if idx and not LC.world[keyOf(f.i, f.j, k)] and place(idx, f.i, f.j, k) then LC.afterPlace(f.i, f.j, k)
            elseif LC.mode == "survival" then dropAt({ kind = "block", name = f.name, count = 1 }, f.i, f.j, k) end
        elseif f.z < -30000 then release(f.a); table.remove(fx.falling, n) end
    end
end
LC.fallRender = function(alpha)
    for _, f in ipairs(fx.falling) do
        local z = (f.pz or f.z) + (f.z - (f.pz or f.z)) * alpha
        f.a:K2_SetActorLocation({ X = f.x, Y = f.y, Z = z }, false, {}, true)
    end
end

-- ---- mining (survival): hold the break key; progress and cracks as in Java Edition
local mine
local crackActor
local function crackHide() if crackActor and crackActor:IsValid() then crackActor:SetActorHiddenInGame(true) end end
local function crackShow(i, j, k, stage, name)
    local lo, hi = outlineBox(keyOf(i, j, k))
    if not lo then return end
    local mat = maskedMaterial("crack_" .. stage)
    if not mat then return end
    if not (crackActor and crackActor:IsValid()) then
        crackActor = spawnMesh(cubeMesh, mat, 0, 0, -100000, 0, false)
        crackActor.StaticMeshComponent:SetCastShadow(false)
    end
    crackActor:SetActorHiddenInGame(false)
    crackActor.StaticMeshComponent:SetMaterial(0, mat)
    local bx, by, bz = (i + 0.5) * 100, (j + 0.5) * 100, k * 100
    local e = 0.2
    local x0, x1 = bx + (8 - hi[3]) * 6.25 - e, bx + (8 - lo[3]) * 6.25 + e
    local y0, y1 = by + (lo[1] - 8) * 6.25 - e, by + (hi[1] - 8) * 6.25 + e
    local z0, z1 = bz + lo[2] * 6.25 - e, bz + hi[2] * 6.25 + e
    crackActor.StaticMeshComponent:SetWorldScale3D({ X = (x1 - x0) / 100, Y = (y1 - y0) / 100, Z = (z1 - z0) / 100 })
    crackActor:K2_SetActorLocation({ X = (x0 + x1) / 2, Y = (y0 + y1) / 2, Z = (z0 + z1) / 2 }, false, {}, true)
end

local function exhaust(v) S.exh = S.exh + v end

local function survBreak(m)
    local name = m.name
    local hardness, speed, can = miningStats(name)
    local i, j, k = m.i, m.j, m.k
    remove(i, j, k)
    burst(name, i, j, k)
    local d = dropsFor(name, can, S.inv[LC.slot] and S.inv[LC.slot].kind == "item" and S.inv[LC.slot].name or nil)
    if d then dropAt(d, i, j, k) end
    exhaust(0.005)
    LC.afterRemove(i, j, k)
end

local function mineTick()
    if LC.mode ~= "survival" or LC.menuUp or S.dead then if mine then mine = nil; crackHide() end return end
    local pc = getPC()
    local held = down("LEFT_MOUSE_BUTTON") or down("F") or down("GP_RT")
    if not held then if mine then mine = nil; crackHide() end return end
    local inside, _, isBlock = target()
    if not (isBlock and inside) then
        if mine then mine = nil; crackHide() end
        if LC.now - (LC.lastSwing or -1) > 0.25 then LC.lastSwing = LC.now; if LC.fxPlace then LC.fxPlace() end end
        return
    end
    local key = keyOf(inside[1], inside[2], inside[3])
    local b = LC.world[key]
    if not b then return end
    local st = S.inv[LC.slot]
    local toolName = st and st.kind == "item" and st.name or ""
    if not mine or mine.key ~= key or mine.tool ~= toolName then
        crackHide()
        mine = { key = key, i = inside[1], j = inside[2], k = inside[3], name = b.name, progress = 0, last = os.clock(), tool = toolName, cool = mine and mine.cool or 0, stage = -1 }
    end
    local now = os.clock()
    local dt = math.min(now - mine.last, 0.2); mine.last = now
    if now < (mine.cool or 0) then return end
    local hardness, speed, can = miningStats(b.name)
    if hardness < 0 then return end
    local perTick = hardness == 0 and 1 or speed / hardness / (can and 30 or 100)
    mine.progress = mine.progress + perTick * dt / 0.05
    if LC.now - (LC.lastSwing or -1) > 0.25 then
        LC.lastSwing = LC.now
        if LC.fxPlace then LC.fxPlace() end
        burstSmall(b.name, mine.i, mine.j, mine.k)
    end
    local stage = math.min(9, math.floor(mine.progress * 10))
    if mine.progress >= 1 then
        survBreak(mine)
        mine.cool = now + 0.25
        mine = { cool = mine.cool, last = now }
        crackHide()
    elseif stage ~= mine.stage and mine.progress > 0.04 then
        mine.stage = stage
        crackShow(mine.i, mine.j, mine.k, stage, b.name)
    end
end

-- ---- survival placing, eating, dropping
LC.survPlaceConsume = function()
    local st = S.inv[LC.slot]
    if not st then return end
    st.count = st.count - 1
    if st.count <= 0 then S.inv[LC.slot] = nil end
    afterInvChange()
end

local eating
local function useTick()
    if LC.mode ~= "survival" or LC.menuUp or S.dead then eating = nil return end
    local st = S.inv[LC.slot]
    local using = down("RIGHT_MOUSE_BUTTON") or down("R") or down("GP_LT")
    if not (using and st and st.kind == "item" and FOOD[st.name] and S.food < 20) then eating = nil return end
    eating = (eating or 0) + 1
    if eating % 5 == 1 and LC.fxPlace then LC.fxPlace() end
    if eating >= 32 then
        local f = FOOD[st.name]
        S.food = math.min(20, S.food + f[1]); S.sat = math.min(S.food, S.sat + f[2])
        eating = nil
        LC.survPlaceConsume()
        LC.msgText, LC.msgT, LC.msgDur = "", nil, 0
    end
end

LC.keys.Q = function()
    if LC.mode ~= "survival" then select(nil, LC.hot[LC.slot] - 1) return end
    local st = S.inv[LC.slot]
    if not st then return end
    local pc, pawn = pcpawn()
    if not pawn then return end
    local l, f = pawn:K2_GetActorLocation(), pawn:GetActorForwardVector()
    local cm = pc.PlayerCameraManager
    local fw = KMATH:GetForwardVector(cm:GetCameraRotation())
    spawnDrop({ kind = st.kind, name = st.name, count = 1 }, cell(l.X), cell(l.Y), cell(l.Z),
        { x = l.X + fw.X * 30, y = l.Y + fw.Y * 30, z = l.Z + 20, vx = fw.X * 0.3, vy = fw.Y * 0.3, vz = fw.Z * 0.3 + 0.1, delay = 40 })
    LC.survPlaceConsume()
end

-- ---- health, hunger, fall damage (20 ticks per second, Java Edition rules)
local function die()
    if S.dead then return end
    S.dead = true
    LC.msgText, LC.msgT, LC.msgDur = "You died!", LC.now, 2.5
    local pc, pawn = pcpawn()
    local l = pawn and pawn:K2_GetActorLocation()
    for s = 1, 36 do
        local st = S.inv[s]
        if st and l then spawnDrop({ kind = st.kind, name = st.name, count = st.count }, cell(l.X), cell(l.Y), cell(l.Z)) end
        S.inv[s] = nil
    end
    afterInvChange()
    LC.after(2.5, function()
        local pc2, pawn2 = pcpawn()
        local ps = FindFirstOf("PlayerStart")
        if pawn2 and ps and ps:IsValid() then pawn2:K2_SetActorLocation(ps:K2_GetActorLocation(), false, {}, true) end
        S.health, S.food, S.sat, S.exh, S.invul, S.dead, S.peak, S.air = 20, 20, 5, 0, 20, false, nil, 300
        S.regen, S.starve = 0, 0
        if LC.flying then LC.setFlight(false) end
        hud = hud
    end)
end
local function damage(n, why)
    if LC.mode ~= "survival" or S.dead or n <= 0 then return end
    if S.invul > 0 then return end
    S.health = math.max(0, S.health - n); S.invul = 10; LC.hurtT = LC.now
    exhaust(0.1)
    log("damage %.1f (%s) -> %.1f", n, why, S.health)
    if S.health <= 0 then die() end
end
LC.damage = damage

LC.survStep = function(pawn, pl)
    if S.dead then return end
    if S.invul > 0 then S.invul = S.invul - 1 end
    local cm = pawn.CharacterMovement
    local mode = cm.MovementMode
    local z = pl.Z - pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    -- fall damage: distance fallen above 3 blocks, not into flight or water
    if mode == 3 then
        if not S.airborne then S.airborne = true; S.peak = z end
        S.peak = math.max(S.peak or z, z)
    else
        if S.airborne and (mode == 1 or mode == 2) and not LC.flying then
            local fall = ((S.peak or z) - z) / 100
            if fall > 3 then damage(math.ceil(fall - 3), "fall") end
        end
        S.airborne = false; S.peak = z
    end
    -- exhaustion from movement
    local v = pawn:GetVelocity()
    local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
    if mode == 1 then exhaust((pawn.sprinting and 0.1 or 0) * hs * 0.05 / 100) end
    if mode == 3 and v.Z > 250 and not S.jumped then S.jumped = true; exhaust(pawn.sprinting and 0.2 or 0.05) end
    if mode ~= 3 then S.jumped = false end
    -- hunger and natural regeneration
    if S.exh >= 4 then S.exh = S.exh - 4; if S.sat > 0 then S.sat = math.max(0, S.sat - 1) else S.food = math.max(0, S.food - 1) end end
    if S.health < 20 and S.food >= 20 and S.sat > 0 then
        S.regen = S.regen + 1
        if S.regen >= 10 then S.regen = 0; local a = math.min(S.sat, 6); S.health = math.min(20, S.health + a / 6); exhaust(a) end
    elseif S.health < 20 and S.food >= 18 then
        S.regen = S.regen + 1
        if S.regen >= 80 then S.regen = 0; S.health = math.min(20, S.health + 1); exhaust(6) end
    elseif S.food <= 0 then
        S.starve = S.starve + 1
        if S.starve >= 80 then S.starve = 0; if S.health > 1 then S.invul = 0; damage(1, "starvation") end end
    else S.regen = 0; S.starve = 0 end
    -- contact damage: cactus beside you, magma under your feet
    if S.invul <= 0 and not LC.flying then
        local hit
        for dx = -1, 1 do for dy = -1, 1 do
            local px, py = pl.X + dx * 38, pl.Y + dy * 38
            local ci, cj = cell(px), cell(py)
            for dz = 0, 1 do
                local b = LC.world[keyOf(ci, cj, cell(z + 10) + dz)]
                if b and b.name == "cactus" then hit = "cactus" end
            end
        end end
        local below = LC.world[keyOf(cell(pl.X), cell(pl.Y), cell(z - 5))]
        if below and below.name == "magma_block" then hit = "magma" end
        if hit then damage(1, hit) end
    end
    S.health = math.floor(S.health * 2 + 0.0001) / 2
end

-- ---- survival starter kit and mode switching
local function giveKit()
    for s = 1, 9 do S.inv[s] = nil end
    local kit = { { "item", "iron_pickaxe", 1 }, { "item", "iron_axe", 1 }, { "item", "iron_shovel", 1 }, { "item", "iron_sword", 1 }, { "item", "shears", 1 }, { "item", "bread", 16 } }
    for _, e in ipairs(kit) do addToInv(e[1], e[2], e[3]) end
end

-- the saved mode may already be survival when the game starts: set it up once
if LC.mode == "survival" and not S.started then S.started = true; S.health, S.food, S.sat, S.exh = 20, 20, 5, 0; if LC.kit then giveKit() end end

function LC.setMode(m)
    if m == LC.mode then return end
    LC.mode = m
    if mine then mine = nil; crackHide() end
    if m == "survival" then
        if not S.started then S.started = true; S.health, S.food, S.sat, S.exh = 20, 20, 5, 0; if LC.kit then giveKit() end end
        if LC.flying then LC.setFlight(false) end
    end
    LC.saveCfg()
    if LC.hudRefresh then LC.hudRefresh() end
    updateHeld()
    LC.hudNote()
    if hud then hud.size = nil end
    log("game mode: %s", m)
end
LC.setFlight = setFlight

-- ---- movement as in Java Edition: walking 4.317 and sprinting 5.612 blocks/s, a 1.25 block jump under 32 blocks/s^2 gravity, 0.6 block steps,
-- double-tap W / Ctrl (left stick click on a pad) to sprint, held Space keeps jumping. The game's Blueprint rewrites MaxWalkSpeed every frame from its own
-- "walk speed" / "sprint speed" variables, so those are servoed until the real speed matches. "Fast walking" multiplies the targets by 3.
local FASTMUL = 3
local MC_WALK, MC_SPRINT = 431.7, 561.2
function LC.setMobile(on)
    LC.shape = on and 0 or 1
    LC.saveCfg()
    LC.fovSize = nil
    if hud then hud.size = nil end
    log("mobile view %s", on and "on" or "off")
end
LC.keys.F6 = function() LC.setMobile(LC.shape > 0.5) end
LC.keys.MINUS = function() if LC.hudOn then LC.fovV = math.max(30, LC.fovV - 5); LC.saveCfg(); LC.fovSize = nil end end
LC.keys.PLUS = function() if LC.hudOn then LC.fovV = math.min(110, LC.fovV + 5); LC.saveCfg(); LC.fovSize = nil end end
function LC.setFast(on)
    LC.fast = on
    LC.saveCfg()
    log("fast walking %s", on and "on" or "off")
end
LC.keys.W = function()
    if LC.now - (LC.lastW or -9) < 0.3 then LC.sprintLatch = true end
    LC.lastW = LC.now
end
-- creative: double-tap jump starts flying, double-tap again stops it and you fall (Java Edition)
local function jumpPressed()
    LC.lastJump = LC.now
    if LC.menuUp or (LC.inv and LC.inv.open) or (LC.chat and LC.chat.open) or LC.camUp then return end
    local t = LC.jumpTapT
    LC.jumpTapT = LC.now
    if LC.mode == "creative" and t and LC.now - t < 0.3 then
        LC.jumpTapT = nil
        LC.lastJump = LC.now + 0.7                 -- the second tap is not another jump
        LC.setFlight(not LC.flying)
    end
end
LC.keys.SPACE = jumpPressed
LC.jumpPressed = jumpPressed
LC.keys.GP_L3 = function() if not LC.flying then LC.padSprint = true; LC.padSprintT = LC.now end end
local mySprint = false
function LC.setWalkStyle(style)
    LC.walkStyle = style
    LC.saveCfg()
    if hud then hud.nRows = nil end
    log("walking: %s", style == "lushfoil" and "LushfoilCraft" or "Minecraft")
end
LC.keys.F9 = function() if LC.title and LC.title.open and not LC.title.active and (LC.hudOn or LC.menuUp) then if LC.saveNow then LC.saveNow() end; LC.title.open("main") end end
LC.keys.F8 = function() LC.setWalkStyle(LC.walkStyle == "lushfoil" and "minecraft" or "lushfoil") end
local function moveTick(pawn)
    local cm = pawn.CharacterMovement
    -- the game's own values, remembered once, so LushfoilCraft walking can give them back exactly
    if not LC.native then
        local w, sp = pawn["walk speed"], pawn["sprint speed"]
        if w < 100 or w > 700 then w = 236.16 end
        if sp < 100 or sp > 1100 then sp = 492 end
        local air, step = cm.AirControl, cm.MaxStepHeight
        if air >= 0.35 then air = 0.05 end
        if step >= 59 then step = 45 end
        LC.native = { walk = w, sprint = sp, air = air, step = step }
        -- the game's own ground / air handling (UE defaults if an earlier build had already changed them)
        local gf = cm.GroundFriction
        local modified = math.abs(gf - 12) < 0.01
        LC.nativeMove = {
            GroundFriction = modified and 8 or gf, BrakingFriction = modified and 0 or cm.BrakingFriction, bUseSeparateBrakingFriction = modified and false or cm.bUseSeparateBrakingFriction,
            BrakingFrictionFactor = modified and 2 or cm.BrakingFrictionFactor, BrakingDecelerationWalking = modified and 1000 or cm.BrakingDecelerationWalking,
            MaxAcceleration = modified and 2048 or cm.MaxAcceleration, FallingLateralFriction = modified and 0 or cm.FallingLateralFriction,
            BrakingDecelerationFalling = modified and 0 or cm.BrakingDecelerationFalling,
        }
    end
    local function setMove(t) for k, v in pairs(t) do local cur = cm[k]; if type(v) == "boolean" then if cur ~= v then cm[k] = v end elseif math.abs(cur - v) > 0.01 then cm[k] = v end end end
    local mode = cm.MovementMode
    local v = pawn:GetVelocity()
    local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
    LC.moveP, LC.moveMode, LC.moveSpeed = pawn, mode, hs
    LC.camUp = (pawn["camera raised"] or pawn["camera being raised"]) and true or false
    local cam = pawn:GetComponentByClass(cameraClass)
    LC.moveCam = cam
    if cam and cam:IsValid() and not LC.camHome then local r = cam.RelativeLocation; LC.camHome = { X = r.X, Y = r.Y, Z = r.Z } end
    if LC.flying then mySprint = false; return end
    local spr
    if LC.walkStyle == "minecraft" then
        -- jump and gravity of Java Edition, 0.6 block steps, held Space keeps jumping
        if math.abs(cm.JumpZVelocity - 895) > 1 then cm.JumpZVelocity = 895 end
        if math.abs(cm.GravityScale - 3.265) > 0.01 then cm.GravityScale = 3.265 end
        if cm.MaxStepHeight < 59 then cm.MaxStepHeight = 60 end
        if (down("SPACE") or down("GP_A")) and mode == 1 and LC.now - (LC.lastJump or -9) > 0.5 and not LC.menuUp and not (LC.inv and LC.inv.open) then
            pcall(function() pawn:Jump() end); LC.lastJump = LC.now
            -- a sprinting jump carries extra forward speed, as in Java Edition
            if pawn.sprinting and hs > 100 then
                local f = pawn:GetActorForwardVector()
                pcall(function() pawn:LaunchCharacter({ X = f.X * 140, Y = f.Y * 140, Z = 0 }, false, false) end)
            end
        end
        -- sprint: double-tap W, Ctrl, or the left stick
        local wDown = down("W")
        if not wDown then LC.sprintLatch = false end
        if LC.sprintLatch and LC.now - (LC.lastW or 0) > 0.5 and hs < 40 then LC.sprintLatch = false end      -- ran into something
        if LC.padSprint and LC.now - (LC.padSprintT or 0) > 0.5 and hs < 40 then LC.padSprint = false end
        local want = ((LC.sprintLatch or down("LCTRL")) and wDown) or LC.padSprint or false
        if LC.mode == "survival" and LC.surv.food <= 6 then want = false end
        if want then pawn.sprinting = true; mySprint = true
        elseif mySprint then pawn.sprinting = false; mySprint = false end
        -- speeds: the Blueprint recomputes MaxWalkSpeed every frame as a fixed fraction of its "walk speed" / "sprint speed" variables, so the fraction is
        -- measured and those variables are set to give the Java Edition speed (4.317 / 5.612 blocks per second)
        spr = pawn.sprinting
        local prop = spr and "sprint speed" or "walk speed"
        local target = spr and MC_SPRINT or MC_WALK
        -- Minecraft-style momentum: friction gives the short run-up and the slide to a stop; the air keeps part of its speed and steers weakly
        -- Minecraft-style momentum: friction gives the short run-up and the slide to a stop; the air keeps part of its speed and steers weakly
        setMove({ GroundFriction = 12, BrakingFriction = 12, bUseSeparateBrakingFriction = true, BrakingFrictionFactor = 1, BrakingDecelerationWalking = 0,
                  MaxAcceleration = target * 12 * 1.08, FallingLateralFriction = 1.9, BrakingDecelerationFalling = 0 })
        if math.abs(cm.AirControl - 0.2) > 0.01 then cm.AirControl = 0.2 end
        local P, M = pawn[prop], cm.MaxWalkSpeed
        if P > 1 and M > 1 then
            local k = M / P
            if k > 0.2 and k < 3 then
                local P2 = math.max(100, math.min(1800, target / k))
                if math.abs(P2 - P) > 2 then pawn[prop] = P2 end
            end
        end
    else
        -- LushfoilCraft walking: the game's own gentle walk and its own sprint key; the optional fast-walking toggle multiplies them
        if math.abs(cm.GravityScale - 1) > 0.01 then cm.GravityScale = 1 end
        setMove(LC.nativeMove)
        if math.abs(cm.AirControl - LC.native.air) > 0.01 then cm.AirControl = LC.native.air end
        if cm.MaxStepHeight > 55 then cm.MaxStepHeight = LC.native.step end
        if mySprint then pawn.sprinting = false; mySprint = false end
        local m = LC.fast and FASTMUL or 1
        if math.abs(pawn["walk speed"] - LC.native.walk * m) > 0.5 then pawn["walk speed"] = LC.native.walk * m end
        if math.abs(pawn["sprint speed"] - LC.native.sprint * m) > 0.5 then pawn["sprint speed"] = LC.native.sprint * m end
        spr = false
    end
    -- field of view. The game keeps the camera manager's FOV locked at 86 degrees, so setting the camera component's own FOV changes nothing you can see:
    -- ours goes in through the same lock (the "fov" command), except while the game's camera is raised (it zooms with its own FOV then).
    if LC.fovApplied then
        local pcc = getPC()
        local tgt = LC.fovApplied * ((spr and LC.walkStyle == "minecraft") and 1.12 or 1)      -- sprinting widens the view a little, as in Minecraft
        LC.fovNow = (LC.fovNow or tgt) + (tgt - (LC.fovNow or tgt)) * 0.35
        if pcc and pcc:IsValid() then
            if LC.camUp then LC.fovCmd = nil
            else
                local q = math.floor(LC.fovNow * 2 + 0.5) / 2
                local ok, cur = pcall(function() return pcc.PlayerCameraManager:GetFOVAngle() end)
                if q ~= LC.fovCmd or (ok and math.abs(cur - q) > 0.7) then LC.fovCmd = q; KSL:ExecuteConsoleCommand(world(), "fov " .. q, pcc) end
            end
        end
    end
end
local function fastTick(pawn) moveTick(pawn) end

-- ---- go anywhere: the game's invisible boundary walls (hundreds of hidden "boundaryblock" colliders) are switched off per level
local function freeRoam()
    local w = world()
    if not (w and w:IsValid()) then return end
    local key = w:GetFullName()
    if LC.roamKey == key and LC.now < (LC.roamNext or 0) then return end
    LC.roamNext = LC.now + 120
    local n = 0
    for _, a in ipairs(FindAllOf("StaticMeshActor") or {}) do
        if a:IsValid() then
            local c = a.StaticMeshComponent
            -- a destroyed actor can still be listed, with no component: touching it crashes the game
            if c and c:IsValid() and c:GetCollisionEnabled() ~= 0 then
                local nm = a:GetFName():ToString():lower()
                local wall = nm:find("boundary") ~= nil
                if not wall and (nm:find("^collision") or nm:find("^cube") or nm:find("wall") or nm:find("border") or nm:find("barrier") or nm:find("limit")) then
                    -- Chamonix, Iceland and the other maps keep their limits as hidden, very tall, solid slabs
                    local hid = false
                    pcall(function() hid = a.bHidden or c.bHiddenInGame end)
                    wall = (hid or not c:IsVisible()) and a:GetActorScale3D().Z >= 20
                end
                if wall then c:SetCollisionEnabled(0); n = n + 1 end
            end
        end
    end
    if LC.roamKey ~= key or n > 0 then log("free roaming: %d boundary colliders disabled in %s", n, key) end
    LC.roamKey = key
    local _, pawn = pcpawn()
    if pawn then pcall(function() pawn["Boundary is visible"] = false end) end
end

LC.freeRoam = freeRoam

-- ---- unlock everything in the game's own save (levels, portals, photo boards, unlockables, totems, animals, tutorials)
local function unlockAll()
    -- every live copy of the save object (the game keeps several and shows locks from whichever it read last); each is checked right before it is written
    local list = FindAllOf("Saved_C") or {}
    for _, s in ipairs(list) do
        if s and s:IsValid() then pcall(LC.unlockOne, s) end
    end
end
LC.unlockOne = function(s)
    local function allTrue(name)
        local arr = s[name]
        if not arr then return 0 end
        local n = arr:GetArrayNum()
        for i = 1, n do arr[i] = true end
        return n
    end
    local n = 0
    n = n + allTrue("Home Menu Unlocked Levels") + allTrue("Portals Found") + allTrue("Tutorials Seen")
    for lv = 0, 8 do
        n = n + allTrue("Photo Board Progress Level " .. lv) + allTrue("Unlocked Item Progress Level " .. lv) + allTrue("Totem Progress Level " .. lv) + allTrue("Animals Seen Level " .. lv)
    end
    local function copyInts(dst, src)
        local d, sr = s[dst], s[src]
        if not (d and sr) then return end
        for i = 1, math.min(d:GetArrayNum(), sr:GetArrayNum()) do d[i] = sr[i] end
    end
    copyInts("Saved Objective Photos", "Total Objective Photos")
    copyInts("Saved Totems", "Total Totems")
    local u = s["Saved Unlockables"]
    if u then for i = 1, u:GetArrayNum() do u[i] = 4 end end        -- 4 per level is the game's own total (14 overshot it: "14/4" and an out-of-range read when a level loads)
    pcall(function() s["camera obtained"] = true; s["GPS unlocked"] = true; s["Boundary Assistance"] = false end)
    LC.unlockedN = n
end

-- ---- worlds, saved like Minecraft's: blocks, player, mode, survival state and inventory per world, autosaved every minute and whenever a menu opens
local SAVES = LC.data
LC.jobs = LC.jobs or {}
local function levelName() local w = world(); return (w and w:IsValid()) and w:GetFName():ToString() or "?" end
local function stamp() return os.date("%Y-%m-%d %H:%M") end
local function nBlocks() local n = 0; for _ in pairs(LC.world) do n = n + 1 end return n end

local function readIndex()
    local list, last = {}, nil
    local f = io.open(SAVES .. "index.txt", "r")
    if f then
        for l in f:lines() do
            local lw = l:match("^last=(%d+)$")
            if lw then last = tonumber(lw)
            else
                local id, name, level, count, st = l:match("^(%d+)|([^|]*)|([^|]*)|(%d+)|(.*)$")
                if id then list[#list + 1] = { id = tonumber(id), name = name, level = level, count = tonumber(count), stamp = st } end
            end
        end
        f:close()
    end
    LC.worlds, LC.lastWorld = list, last
end
local function writeIndex()
    local f = io.open(SAVES .. "index.txt", "w")
    if not f then log("cannot write %sindex.txt (is the saves folder there?)", SAVES) return end
    f:write("last=" .. (LC.worldId or 0) .. "\n")
    for _, w in ipairs(LC.worlds) do f:write(("%d|%s|%s|%d|%s\n"):format(w.id, w.name, w.level, w.count, w.stamp)) end
    f:close()
end
local function entry(id) for _, w in ipairs(LC.worlds or {}) do if w.id == id then return w end end end

function LC.worldInfo()
    local e = LC.worldId and entry(LC.worldId)
    return { name = e and e.name or "World 1", count = LC.worldId and nBlocks() or 0 }
end

local function say(text, dur) LC.msgText, LC.msgT, LC.msgDur = text, LC.now, dur or 2 end

local function saveWorld(quiet)
    if not LC.worldId then return false end
    local pc, pawn = pcpawn()
    local out = { "LCW1", "level=" .. levelName(), "mode=" .. LC.mode, "slot=" .. LC.slot }
    if pawn then
        local l = pawn:K2_GetActorLocation()
        local ok, r = pcall(function() return pc:GetControlRotation() end)
        out[#out + 1] = ("pos=%.1f,%.1f,%.1f,%.1f,%.1f"):format(l.X, l.Y, l.Z, ok and r.Yaw or 0, ok and r.Pitch or 0)
    end
    out[#out + 1] = ("stats=%.1f,%.1f,%.1f"):format(S.health, S.food, S.sat)
    local hot = {}
    for sl = 1, 9 do hot[sl] = blocks[LC.hot[sl]] and blocks[LC.hot[sl]][1] or "stone" end
    out[#out + 1] = "hot=" .. table.concat(hot, ",")
    local inv = {}
    for sl = 1, 36 do local st = S.inv[sl]; if st then inv[#inv + 1] = ("%d:%s:%s:%d"):format(sl, st.kind, st.name, st.count) end end
    out[#out + 1] = "inv=" .. table.concat(inv, ";")
    out[#out + 1] = "blocks"
    local n = 0
    for key, b in pairs(LC.world) do
        local i, j, k = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
        if i then out[#out + 1] = i .. " " .. j .. " " .. k .. " " .. b.name; n = n + 1 end
    end
    local f = io.open(SAVES .. "world" .. LC.worldId .. ".lcw", "w")
    if not f then log("cannot save world %d", LC.worldId) return false end
    f:write(table.concat(out, "\n")); f:write("\n"); f:close()
    local e = entry(LC.worldId)
    if e then e.count, e.stamp, e.level = n, stamp(), levelName() end
    writeIndex()
    LC.dirty = false
    LC.lastSave = LC.now
    if not quiet then say("Saved " .. (e and e.name or "world") .. " (" .. n .. " blocks)", 2) end
    log("saved world %d: %d blocks", LC.worldId, n)
    return true
end
LC.saveNow = function() saveWorld(false) end

-- block work is spread over frames (a big world has thousands of actors to spawn)
local function queueRemoveAll()
    local keys = {}
    for key in pairs(LC.world) do keys[#keys + 1] = key end
    local n = 1
    LC.jobs[#LC.jobs + 1] = function()
        local c = 0
        while n <= #keys and c < 60 do
            local i, j, k = keys[n]:match("^(-?%d+),(-?%d+),(-?%d+)$")
            if i then remove(tonumber(i), tonumber(j), tonumber(k)) end
            n = n + 1; c = c + 1
        end
        return n > #keys
    end
end
local function queuePlace(list, label)
    local n = 1
    LC.jobs[#LC.jobs + 1] = function()
        local c = 0
        while n <= #list and c < 30 do
            local e = list[n]
            local idx = byName(e[4])
            if idx then place(idx, e[1], e[2], e[3]) end
            n = n + 1; c = c + 1
        end
        if n > #list then say(label .. " loaded", 1.5); LC.dirty = false; return true end
        say(label .. ": " .. math.floor(100 * n / #list) .. "%", 0.6)
        return false
    end
end

local function teleportTo(x, y, z, yaw, pitch)
    local pc, pawn = pcpawn()
    if not pawn then return end
    pawn:K2_SetActorLocation({ X = x, Y = y, Z = z }, false, {}, true)
    if yaw then pcall(function() pc:SetControlRotation({ Pitch = pitch or 0, Yaw = yaw, Roll = 0 }) end) end
    S.airborne, S.peak = false, nil
end

local function resetSurvival()
    S.health, S.food, S.sat, S.exh, S.invul, S.dead, S.regen, S.starve, S.peak, S.airborne, S.air = 20, 20, 5, 0, 0, false, 0, 0, nil, false, 300
    for sl = 1, 36 do S.inv[sl] = nil end
    S.started = false
end

local function loadWorld(id)
    local e = entry(id)
    local f = io.open(SAVES .. "world" .. id .. ".lcw", "r")
    if not (e and f) then log("world %d has no save file", id); if f then f:close() end return false end
    local hdr = f:read("*l")
    if hdr ~= "LCW1" then f:close(); log("world %d: unknown save format", id) return false end
    local kv, list, inBlocks = {}, {}, false
    for l in f:lines() do
        if inBlocks then
            local i, j, k, name = l:match("^(-?%d+) (-?%d+) (-?%d+) (%S+)$")
            if i then list[#list + 1] = { tonumber(i), tonumber(j), tonumber(k), name } end
        elseif l == "blocks" then inBlocks = true
        else local a, b = l:match("^(%w+)=(.*)$"); if a then kv[a] = b end end
    end
    f:close()
    if kv.level and kv.level ~= levelName() then say("That world was saved in " .. kv.level, 3) log("world %d belongs to level %s", id, kv.level) return false end
    saveWorld(true)                                   -- the world we are leaving
    LC.worldId = id
    queueRemoveAll()
    queuePlace(list, e.name)
    -- state
    resetSurvival()
    if kv.stats then local h, fd, st = kv.stats:match("([%d.]+),([%d.]+),([%d.]+)"); if h then S.health, S.food, S.sat = tonumber(h), tonumber(fd), tonumber(st) end end
    if kv.hot then
        local sl = 1
        for name in kv.hot:gmatch("[^,]+") do local idx = byName(name); if idx and sl <= 9 then LC.hot[sl] = idx end; sl = sl + 1 end
    end
    if kv.inv and kv.inv ~= "" then
        for item in kv.inv:gmatch("[^;]+") do
            local sl, kind, name, count = item:match("^(%d+):(%a+):([^:]+):(%d+)$")
            if sl then S.inv[tonumber(sl)] = { kind = kind, name = name, count = tonumber(count) } end
        end
    end
    S.started = true
    if kv.mode and kv.mode ~= LC.mode then LC.setMode(kv.mode) end
    LC.slot = tonumber(kv.slot) or 1
    if kv.pos then
        local x, y, z, yaw, pitch = kv.pos:match("(-?[%d.]+),(-?[%d.]+),(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)")
        if x then teleportTo(tonumber(x), tonumber(y), tonumber(z) + 20, tonumber(yaw), tonumber(pitch)) end
    end
    LC.hudRefresh(); updateHeld(); LC.hudNote()
    writeIndex()
    say("Loading " .. e.name .. " ...", 2)
    log("loading world %d (%d blocks)", id, #list)
    return true
end

function LC.newWorld()
    saveWorld(true)
    local id = 1
    for _, w in ipairs(LC.worlds) do id = math.max(id, w.id + 1) end
    LC.worlds[#LC.worlds + 1] = { id = id, name = "World " .. id, level = levelName(), count = 0, stamp = stamp() }
    LC.worldId = id
    queueRemoveAll()
    resetSurvival()
    local ps = FindFirstOf("PlayerStart")
    if ps and ps:IsValid() then local l = ps:K2_GetActorLocation(); teleportTo(l.X, l.Y, l.Z + 20, ps:K2_GetActorRotation().Yaw, 0) end
    if LC.mode == "survival" then S.started = true; if LC.kit then giveKit() end end
    LC.hudRefresh(); updateHeld(); LC.hudNote()
    LC.dirty = true
    writeIndex()
    say("New world: World " .. id, 2)
    log("new world %d", id)
end

function LC.switchWorld()
    local list, lvl = {}, levelName()
    for _, w in ipairs(LC.worlds or {}) do if w.level == lvl then list[#list + 1] = w end end        -- only the worlds of this map
    if #list < 2 then say("No other worlds on this map yet - use New world", 2) return end
    local pos = 1
    for n, w in ipairs(list) do if w.id == LC.worldId then pos = n end end
    local nxt = list[pos % #list + 1]
    loadWorld(nxt.id)
end

-- first start: reopen the last world (or begin World 1) once the launch scene is over
-- a new level: everything spawned for the old one is gone, and each level keeps its own worlds
local function levelReset()
    local w = world()
    if not (w and w:IsValid()) then return false end
    local key = w:GetFullName()
    if LC.lastWorldKey == nil then LC.lastWorldKey = key return false end
    if LC.lastWorldKey == key then return false end
    LC.lastWorldKey = key
    -- a level change we were not told about (no OpenLevel hook fired): let the level settle before touching anything
    if not LC.travelFlag then LC.suspendFrames = 240 end
    LC.travelFlag = false
    LC.world = {}
    local f = LC.fx
    if f then f.parts, f.drops, f.pool, f.outline, f.falling = {}, {}, {}, {}, {} end
    LC.held, LC.heldKey, LC.fpArm, LC.steve = nil, nil, nil, nil
    LC.third, LC.flying = false, false
    LC.worldInit, LC.worldId, LC.jobs, LC.dirty = false, nil, {}, false
    LC.camHome, LC.moveCam, LC.moveP = nil, nil, nil
    LC.hudW, LC.launchW, LC.pc, LC.worldObj = nil, nil, nil, nil          -- widgets of the old level are gone; the controller and world are looked up again
    if LC.invReset then LC.invReset() end
    if LC.title and LC.title.reset then LC.title.reset() end
    LC.levelT = LC.now
    LC.tex, LC.mat = {}, {}                                  -- textures and materials made in the old level are re-imported fresh, never reused across the change
    LC.levelChanged = true; LC.launchW = nil
    log("new level: %s", key)
    return true
end
LC.levelReset = levelReset

LC.readIndex = readIndex
LC.loadWorldId = loadWorld
local function createWorld(name, lvl)
    local id = 1
    for _, w in ipairs(LC.worlds) do id = math.max(id, w.id + 1) end
    LC.worlds[#LC.worlds + 1] = { id = id, name = name or ("World " .. id), level = lvl, count = 0, stamp = stamp() }
    LC.worldId = id
    writeIndex()
    LC.dirty = true
    return id
end
-- the world picked on the title screen: opened once the map it belongs to is running
function LC.applyPending()
    local pend = LC.pending
    if not pend or pend.level ~= levelName() then return false end
    LC.pending = nil
    readIndex()
    if LC.worldId and LC.worldInit then saveWorld(true) end
    if LC.worldInit then queueRemoveAll() end
    resetSurvival()
    if pend.id and entry(pend.id) then loadWorld(pend.id)
    else
        createWorld(pend.name, pend.level)
        local ps = FindFirstOf("PlayerStart")
        if ps and ps:IsValid() then local l = ps:K2_GetActorLocation(); teleportTo(l.X, l.Y, l.Z + 20, ps:K2_GetActorRotation().Yaw, 0) end
        if LC.mode == "survival" then S.started = true; if LC.kit then giveKit() end end
        LC.hudRefresh(); updateHeld(); LC.hudNote()
        say("New world: " .. (pend.name or "World"), 2)
    end
    LC.worldInit = true
    LC.lastSave = LC.now
    return true
end

local function worldTick()
    if LC.title and LC.title.active then return end
    if not LC.worldInit then
        if LC.launchUp or LC.menuUp or not LC.hudOn then return end
        if LC.pending and LC.pending.level == levelName() then LC.applyPending() return end
        LC.worldInit = true
        readIndex()
        local lvl = levelName()
        local last = LC.lastWorld and entry(LC.lastWorld)
        if not (last and last.level == lvl) then
            last = nil
            for _, w in ipairs(LC.worlds) do if w.level == lvl and (not last or w.stamp >= last.stamp) then last = w end end      -- the world of this map saved most recently
        end
        if last then loadWorld(last.id)
        else
            local id = 1
            for _, w in ipairs(LC.worlds) do id = math.max(id, w.id + 1) end
            LC.worlds[#LC.worlds + 1] = { id = id, name = "World " .. id, level = lvl, count = 0, stamp = stamp() }
            LC.worldId = id
            writeIndex()
            LC.dirty = true
        end
        LC.lastSave = LC.now
        return
    end
    -- jobs run one at a time, a slice per tick
    local job = LC.jobs[1]
    if job then local ok, done = pcall(job); if not ok then log("world job error: %s", tostring(done)); table.remove(LC.jobs, 1) elseif done then table.remove(LC.jobs, 1) end return end
    -- autosave
    local menuNow = LC.menuUp and true or false
    if menuNow and not LC.menuPrev and LC.worldId and LC.hudOn ~= nil and LC.dirty then saveWorld(true) end
    LC.menuPrev = menuNow
    if LC.worldId and LC.hudOn and LC.now - (LC.lastSave or 0) > 60 then saveWorld(true) end
end

-- ---- the game's own water handling: lakes are solid for the player and Lushfoil's respawner (it returns you to your last dry spot when you drop
-- below a set height) is in charge. An earlier build changed both; this puts them back, once, even in a session that already had them changed.
local waterRestored = false
local function restoreWater(pawn)
    if pawn["z Reposition Level"] < -1e6 then pawn["z Reposition Level"] = -120 end
    if waterRestored then return end
    waterRestored = true
    for _, a in ipairs(FindAllOf("StaticMeshActor") or {}) do
        if a:IsValid() then
            local c = a.StaticMeshComponent
            if c and c:IsValid() and c:GetCollisionEnabled() == 0 then
                local mesh = (c.StaticMesh and c.StaticMesh:IsValid()) and c.StaticMesh:GetFName():ToString() or ""
                local mat = ""
                pcall(function() local m = c:GetMaterial(0); mat = (m and m:IsValid()) and m:GetFName():ToString():lower() or "" end)
                if mesh == "Plane" and (mat:find("lake") or mat:find("water") or mat:find("river")) then c:SetCollisionEnabled(3) end
            end
        end
    end
end

-- ---- chat and commands (/give)
LC.chat = LC.chat or { open = false, text = "", sugs = {} }
LC.chatLines = LC.chatLines or {}
local function chatSay(text) LC.chatLines[#LC.chatLines + 1] = { text = text, t = LC.now }; if #LC.chatLines > 30 then table.remove(LC.chatLines, 1) end end
local function setIgnore(on)
    local pc = getPC()
    if pc then pcall(function() pc:SetIgnoreMoveInput(on); pc:SetIgnoreLookInput(on) end) end
end
local function resolveItem(id)
    id = id:gsub("^minecraft:", ""):lower()
    local idx = byName(id)
    if idx then return "block", blocks[idx][1] end
    if ITEMSET[id] then return "item", id end
end
local function suggestions(text)
    local out = {}
    local cmd, rest = text:match("^/(%S*)%s+(.*)$")
    if not cmd then
        local c = text:match("^/(%S*)$")
        if c and ("give"):find("^" .. c) then out[1] = "/give" end
        return out
    end
    if cmd ~= "give" then return out end
    local toks = {}
    for t in rest:gmatch("%S+") do toks[#toks + 1] = t end
    local typing = rest:sub(-1) ~= " " and toks[#toks] or ""
    local pos = #toks + (rest:sub(-1) == " " and 1 or 0)
    if typing:sub(1, 1) == "@" then
        for _, t in ipairs({ "@s", "@p", "@a" }) do if t:find(typing, 1, true) == 1 then out[#out + 1] = t end end
        return out
    end
    if pos <= 2 then
        local want = typing:gsub("^minecraft:", "")
        local seen = {}
        for _, d in ipairs(blocks) do
            if #out >= 6 then break end
            if d[1]:find(want, 1, true) == 1 then out[#out + 1] = d[1]; seen[d[1]] = true end
        end
        for _, n in ipairs(itemList) do
            if #out >= 6 then break end
            if not seen[n] and n:find(want, 1, true) == 1 then out[#out + 1] = n end
        end
    end
    return out
end
LC.suggest = suggestions
local function chatUpdate() LC.chat.sugs = suggestions(LC.chat.text) end

local function runCommand(text)
    local cmd, rest = text:match("^/(%S+)%s*(.*)$")
    if not cmd then return end
    if cmd ~= "give" then chatSay("Unknown or incomplete command: /" .. cmd) return end
    local toks = {}
    for t in rest:gmatch("%S+") do toks[#toks + 1] = t end
    if toks[1] and toks[1]:sub(1, 1) == "@" then table.remove(toks, 1)
    elseif toks[2] and not tonumber(toks[2]) and resolveItem(toks[2]) and not resolveItem(toks[1]) then table.remove(toks, 1) end     -- /give <player> <item>
    if not toks[1] then chatSay("Usage: /give <item> [count]") return end
    local kind, name = resolveItem(toks[1])
    if not kind then chatSay("Unknown item '" .. (toks[1]:find(":") and toks[1] or "minecraft:" .. toks[1]) .. "'") return end
    local count = 1
    if toks[2] then
        count = tonumber(toks[2])
        if not count or count < 1 then chatSay("Integer must not be less than one: " .. toks[2]) return end
        count = math.floor(count)
    end
    local label = displayName(name)
    if LC.mode == "survival" then
        local left = LC.giveInv(kind, name, count)
        if left > 0 then
            local pc, pawn = pcpawn()
            local l = pawn and pawn:K2_GetActorLocation()
            while left > 0 and l do
                local n = math.min(64, left); left = left - n
                LC.dropItem({ kind = kind, name = name, count = n }, l)
            end
        end
    else
        if kind == "block" then LC.hot[LC.slot] = byName(name); LC.hotItem[LC.slot] = nil else LC.hotItem[LC.slot] = name end
        LC.hudRefresh(); updateHeld(); LC.hudNote()
    end
    chatSay(("Gave %d [%s] to Player"):format(count, label))
    log("/give %s x%d", name, count)
end

function LC.chatOpen(prefill)
    LC.chat.open = true; LC.chat.text = prefill or ""; chatUpdate()
    setIgnore(true)
end
local function chatClose()
    LC.chat.open = false; LC.chat.text = ""; LC.chat.sugs = {}
    setIgnore(false)
end
function LC.chatChar(ch)
    if LC.title and LC.title.typing then LC.title.char(ch) return end
    if LC.inv.open and LC.inv.typing then LC.invType(ch) return end
    if #LC.chat.text < 120 then LC.chat.text = LC.chat.text .. ch; chatUpdate() end
end
function LC.chatKey(k)
    if LC.title and LC.title.typing then LC.title.key(k) return end
    if LC.inv.open and LC.inv.typing then
        if k == "BackSpace" then LC.invBack() elseif k == "Enter" or k == "Escape" then LC.inv.typing = false end
        return
    end
    if k == "BackSpace" then LC.chat.text = LC.chat.text:sub(1, -2); chatUpdate()
    elseif k == "Enter" then
        local t = LC.chat.text
        chatClose()
        if t ~= "" then chatSay(t); local ok, e = pcall(runCommand, t); if not ok then chatSay("Command failed: " .. tostring(e)); log("command error: %s", tostring(e)) end end
    elseif k == "Escape" then chatClose()
    elseif k == "Tab" then
        local sug = LC.chat.sugs[1]
        if sug then
            local t = LC.chat.text
            if t:match("^/%S*$") then LC.chat.text = sug .. " "
            else LC.chat.text = t:gsub("%S*$", sug) .. " " end
            chatUpdate()
        end
    end
end
LC.keys.T = function() if not LC.menuUp and LC.hudOn then LC.chatOpen("") end end
LC.keys.SLASH = function() if not LC.menuUp and LC.hudOn then LC.chatOpen("/") end end

-- ---- Lushfoil's camera key: Space becomes jump, the camera moves to P
local function rebindKeys()
    if LC.keysRebound then return end
    local IS = StaticFindObject("/Script/Engine.Default__InputSettings")
    if not (IS and IS:IsValid()) then return end
    local am = IS.ActionMappings
    local moves = {}
    for i = 1, am:GetArrayNum() do
        local m = am[i]
        local a, k = m.ActionName:ToString(), m.Key.KeyName:ToString()
        if a == "Camera" and k == "SpaceBar" then moves[#moves + 1] = { a, k, "P" }
        elseif a == "Photos Quick Access" and k == "P" then moves[#moves + 1] = { a, k, "O" } end
    end
    local function map(a, k) return { ActionName = FName(a), Key = { KeyName = FName(k) }, bShift = false, bCtrl = false, bAlt = false, bCmd = false } end
    for _, mv in ipairs(moves) do
        IS:RemoveActionMapping(map(mv[1], mv[2]), false)
        IS:AddActionMapping(map(mv[1], mv[3]), true)
    end
    LC.keysRebound = true
    if #moves > 0 then log("keys: camera is on P now (Space jumps)") end
    local pad = {}
    local am2 = IS.ActionMappings
    for i = 1, am2:GetArrayNum() do
        local m = am2[i]
        if m.ActionName:ToString() == "Camera" and m.Key.KeyName:ToString() == "Gamepad_FaceButton_Bottom" then pad[#pad + 1] = true end
    end
    for _ in ipairs(pad) do IS:RemoveActionMapping(map("Camera", "Gamepad_FaceButton_Bottom"), true) end
    if #pad > 0 then log("keys: pad A no longer raises the camera (A jumps, LB+RB is the camera)") end
end

-- the inventory screen lives in inv.lua (separate scope); it is loaded here
do
    local f, err = loadfile(LC.dir .. "inv.lua")
    if f then
        local ok, e = pcall(f, { log = log, texture = texture, getPC = getPC, world = world, pcpawn = pcpawn, WBL = WBL, WLL = WLL, UW = UW,
            canvasClass = canvasClass, imageClass = imageClass, textClass = textClass, blocks = blocks, itemList = itemList, byName = byName,
            maxStack = maxStack, iconTexture = iconTexture, displayName = displayName, updateHeld = updateHeld })
        if not ok then log("inv.lua error: %s", tostring(e)) end
    else log("inv.lua not loaded: %s", tostring(err)) end
end

do
    local f, err = loadfile(LC.dir .. "title.lua")
    if f then
        local ok, e = pcall(f, { log = log, texture = texture, getPC = getPC, world = world, WBL = WBL, WLL = WLL, UW = UW,
            canvasClass = canvasClass, imageClass = imageClass, textClass = textClass })
        if not ok then log("title.lua error: %s", tostring(e)) end
    else log("title.lua not loaded: %s", tostring(err)) end
end

-- ---- per-tick glue
local lastExtra = 0
LC.modeTick = function()
    local pc, pawn = pcpawn()
    if not pawn then return end
    local ok, e = pcall(rebindKeys)
    ok, e = pcall(restoreWater, pawn)
    ok, e = pcall(mineTick); if not ok and e ~= LC.mineErr then LC.mineErr = e; log("mine error: %s", tostring(e)) end
    ok, e = pcall(useTick); if not ok and e ~= LC.useErr then LC.useErr = e; log("use error: %s", tostring(e)) end
    ok, e = pcall(worldTick); if not ok and e ~= LC.worldErr then LC.worldErr = e; log("world error: %s", tostring(e)) end
    ok, e = pcall(fastTick, pawn); if not ok and e ~= LC.fastErr then LC.fastErr = e; log("fast error: %s", tostring(e)) end
    -- every time the game's menu opens, run its own "unlock all levels" so every location card in the slider is there and unlocked
    if LC.menuUp and not LC.menuPrevU and not LC.skip.extras and LC.now - (LC.levelT or -100) > 8 then
        pcall(unlockAll)                                  -- the menu loads a fresh copy of the save each time it opens
        local hm = FindFirstOf("HomeMenu_C")
        if hm and hm:IsValid() then pcall(function() hm["unlock all hack"] = true; hm["Unlock All Levels"](hm) end) end
    end
    LC.menuPrevU = LC.menuUp
    if LC.now - lastExtra > 15 and not LC.skip.extras and LC.now - (LC.levelT or -100) > 8 then          -- never in the first seconds of a level: the game's save object and level objects are still being set up
        lastExtra = LC.now
        if LC.gfxResume then LC.gfxResume = false; pcall(applyGfx, true) end
        ok, e = pcall(freeRoam); if not ok and e ~= LC.roamErr then LC.roamErr = e; log("roam error: %s", tostring(e)) end
        ok, e = pcall(unlockAll); if not ok and e ~= LC.unlockErr then LC.unlockErr = e; log("unlock error: %s", tostring(e)) end
    end
end


do
    local prevUnload = LC.unload
    LC.unload = function()
        if prevUnload then prevUnload() end
        if crackActor and crackActor:IsValid() then crackActor:K2_DestroyActor() end
        for _, f in ipairs(fx.falling or {}) do if f.a and f.a:IsValid() then f.a:K2_DestroyActor() end end
        LC.modeTick = nil
    end
end

-- ------------------------------------------------------------------ input
LC.keys.LEFT_MOUSE_BUTTON = function() if LC.title and LC.title.active then LC.title.click() elseif LC.inv.open then LC.invClick(0) elseif LC.menuUp then LC.menuClick() else breakTarget() end end
LC.keys.RIGHT_MOUSE_BUTTON = function() if LC.inv.open then LC.invClick(1) else placeTarget() end end
LC.keys.F = breakTarget
do
    local function T() return LC.title and LC.title.active and LC.title end
    LC.keys.ENTER = function() local t = T(); if t then t.confirm() end end
    LC.keys.ESCAPE = function() local t = T(); if t then t.back() end end
    LC.keys.UP = function() local t = T(); if t then t.move(-1) end end
    LC.keys.DOWN = function() local t = T(); if t then t.move(1) end end
end
LC.keys.R = placeTarget
LC.keys.E = function() if LC.hudOn or LC.inv.open then LC.invToggle() end end
LC.keys.PAGE_UP = function() if LC.inv.open then LC.invScroll(-1) elseif LC.mode ~= "survival" then select(nil, LC.hot[LC.slot] + 9) end end
LC.keys.PAGE_DOWN = function() if LC.inv.open then LC.invScroll(1) elseif LC.mode ~= "survival" then select(nil, LC.hot[LC.slot] - 9) end end
LC.keys.F2 = function() setFlight(not LC.flying) end
LC.keys.F3 = function() if LC.walkStyle == "lushfoil" then LC.setFast(not LC.fast) end end
LC.keys.F4 = function() LC.setMode(LC.mode == "survival" and "creative" or "survival") end
LC.keys.F5 = function() setThirdPerson(not LC.third) end
LC.keys.F7 = function() applyGfx(not LC.gfxOn) end
-- controller. In a menu: LB switches the game mode, RB the walking style. In the inventory: D-pad moves, A = click, X = right click, B / Y closes,
-- LB / RB switch tab. In the game: A jumps, Y opens the inventory, D-pad left/right = hotbar, up = third person, down = drop, LB + RB together = camera.
LC.keys.GP_RT = function() if LC.menuUp or LC.inv.open then return end breakTarget() end
LC.keys.GP_LT = function() if LC.inv.open then return end placeTarget() end
local function cameraToggle()
    local _, pawn = pcpawn()
    if not pawn or LC.menuUp or LC.inv.open then return end
    if pawn["camera raised"] then pawn["lower camera"](pawn) else pawn["raise camera"](pawn) end
    log("camera %s", pawn["camera raised"] and "lowered" or "raised")
end
local function shoulder(which)
    if LC.inv.open then LC.invTab(1) return end
    if LC.menuUp then
        if which == "RB" then LC.setWalkStyle(LC.walkStyle == "lushfoil" and "minecraft" or "lushfoil") else LC.setMode(LC.mode == "survival" and "creative" or "survival") end
        return
    end
    LC.after(0.12, function()
        if down("GP_LB") and down("GP_RB") then
            if not LC.chordT or LC.now - LC.chordT > 0.6 then LC.chordT = LC.now; cameraToggle() end
        elseif not (LC.chordT and LC.now - LC.chordT < 0.6) then
            if which == "RB" then select(LC.slot % 9 + 1) else select((LC.slot - 2) % 9 + 1) end
        end
    end)
end
LC.keys.GP_RB = function() shoulder("RB") end
LC.keys.GP_LB = function() shoulder("LB") end
LC.keys.GP_DRIGHT = function() if LC.inv.open then LC.invNav(1, 0) else select(LC.slot % 9 + 1) end end
LC.keys.GP_DLEFT = function() if LC.inv.open then LC.invNav(-1, 0) else select((LC.slot - 2) % 9 + 1) end end
LC.keys.GP_DUP = function() if LC.title and LC.title.active then LC.title.move(-1) elseif LC.inv.open then LC.invNav(0, -1) else setThirdPerson(not LC.third) end end
LC.keys.GP_DDOWN = function() if LC.title and LC.title.active then LC.title.move(1) elseif LC.inv.open then LC.invNav(0, 1) elseif LC.mode == "survival" then LC.keys.Q() end end
LC.keys.GP_Y = function() if LC.hudOn or LC.inv.open then LC.invToggle() end end
LC.keys.GP_B = function() if LC.title and LC.title.active then LC.title.back() elseif LC.inv.open then LC.invClose() end end
LC.keys.GP_A = function() if LC.title and LC.title.active then LC.title.confirm() elseif LC.inv.open then LC.invClick(0) else LC.jumpPressed() end end
LC.keys.GP_BACK = function() applyGfx(not LC.gfxOn) end
LC.keys.GP_X = function() if LC.inv.open then LC.invClick(1) else setFlight(not LC.flying) end end
LC.keys.GP_R3 = function() if LC.walkStyle == "lushfoil" then LC.setFast(not LC.fast) end end
for s_, name in ipairs({ "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }) do LC.keys[name] = function() if LC.inv.open then return end select(s_) end end

-- exposed so the dev channel can drive the same actions without key presses
LC.act = { survBreak = function(i, j, k) local b = LC.world[keyOf(i, j, k)]; if b then survBreak({ name = b.name, i = i, j = j, k = k }) end end, damage = function(n) if LC.damage then LC.damage(n, "test") end end, gfx = applyGfx, third = setThirdPerson, place = placeTarget, breakBlock = breakTarget, select = select, fly = setFlight, placeAt = place, removeAt = remove, target = target, blocks = blocks }

log("v2 ready: %d blocks. LMB/F break, RMB/R place, Q/E change block, 1-9 hotbar, F2 fly", #blocks)
if LC.held and LC.held:IsValid() then LC.held:K2_DestroyActor(); LC.held = nil end
updateHeld()
