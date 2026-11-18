-- The health tab's table (the author's mockup health_v3, 2026-11-10; .claude/mockups/health,
-- its PARTS and look()): a record per hurt body part - what is wrong with it, how its wound
-- looks now (the light on the model, the colour, the tag, the words), the steps of its
-- treatment in medical order with what is done, and its picture's scene (KnoxWoundArt).
--   steps  unb (a dirty bandage, or one over what needs seeing to) > tw (glass) > bullet >
--          burn (cleaned) > clean (disinfected) > stitch (a deep wound) > bandage > splint;
--          a step stays on the list once it was there, done or not, until the part is well
--          (which ones were there and what was done: in the player's mod data, KnoxTable);
--   look   the mockup's look(w): bleed / infect / fracture / glass / open / heal, by what is
--          not done yet;
--   kind   the picture's wound (KnoxWoundArt.KIND_*): the step being done decides it (glass
--          out - the glass, a splint - the fracture), else the worst open wound.
-- Read every quarter of a second by the tab (W.parts), not each frame.

require "Knox/KnoxTheme"
require "Knox/KnoxHealthData"
require "Knox/KnoxHealthCare"

KnoxHealthWounds = KnoxHealthWounds or {}
local W = KnoxHealthWounds
local H = KnoxHealthData
local Care = KnoxHealthCare

local function tx(key, ...) return getText("IGUI_KnoxHP_" .. key, ...) end

-- KnoxWoundArt.KIND_*
W.KIND = {deep = 1, lacer = 2, scratch = 3, glass = 4, fracture = 5, burn = 6, bite = 7, bullet = 8}
-- the steps in medical order; the game's menu key of each (unb takes nothing)
W.STEPS = {"unb", "tw", "bullet", "burn", "clean", "stitch", "bandage", "splint"}
W.STEP_KEY = {tw = "ContextMenu_Remove_Glass", bullet = "ContextMenu_Remove_Bullet", burn = "ContextMenu_Clean_Burn",
    clean = "ContextMenu_Disinfect", stitch = "ContextMenu_Stitch", bandage = "ContextMenu_Bandage",
    splint = "ContextMenu_Splint"}
-- each step's mini-game (KnoxWoundGame: CLEAN 0, STITCH 1, BANDAGE 2, UNB 3, TW 4, SPLINT 5) - a
-- bullet is pulled as glass is, a burn wiped as a wound is cleaned (the mockup has neither)
-- (x...: a done step taken back - the author 2026-11-11: a bandage off with the bandage-off game)
W.GAME = {clean = 0, stitch = 1, bandage = 2, unb = 3, tw = 4, splint = 5, bullet = 4, burn = 0,
    xbandage = 3, xstitch = 6, xsplint = 7}
-- the mockup's VAN: a step's normal time, seconds (bullet and burn: not in the mockup)
W.VAN = {clean = 8, stitch = 12, bandage = 14, unb = 6, tw = 9, splint = 14, bullet = 12, burn = 10,
    xbandage = 6, xstitch = 8, xsplint = 9}

-- the mockup's COL (0..1) and the list's order of the looks
local function rgb(r, g, b) return {r = r / 255, g = g / 255, b = b / 255} end
W.COL = {bleed = rgb(224, 72, 60), infect = rgb(185, 194, 74), fracture = rgb(142, 197, 224), glass = rgb(176, 58, 74),
    open = rgb(190, 66, 56), sand = rgb(212, 195, 138), mint = rgb(143, 208, 176)}
W.ORDER = {bleed = 0, infect = 1, fracture = 2, glass = 3, open = 4, heal = 6}
-- KnoxHealthPaint's styles (mode 10 + style)
W.STYLE = {heal = 0, bleed = 1, infect = 2, fracture = 3, glass = 4, open = 5}

-- the open wounds, worst first (the picture's and the title's)
local OPEN = {"deep", "bite", "lacer", "burn", "bullet", "glass", "scratch"}
local WOUNDISH = {deep = true, bite = true, lacer = true, scratch = true}

local function rgbInt(c)
    return math.floor(c.r * 255 + 0.5) * 65536 + math.floor(c.g * 255 + 0.5) * 256 + math.floor(c.b * 255 + 0.5)
end
W.rgbInt = rgbInt

local function mix(a, b, t)
    return {r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t}
end

local function splintable(bp)
    local t = bp:getType()
    return t ~= BodyPartType.Head and t ~= BodyPartType.Torso_Upper and t ~= BodyPartType.Torso_Lower
        and t ~= BodyPartType.Neck and t ~= BodyPartType.Groin
end

-- what is wrong with the part now: {deep, bite, lacer, ...} = true
local function kindsNow(bp, out)
    out.deep = bp:isDeepWounded() or nil
    out.bite = bp:bitten() or nil
    out.lacer = bp:isCut() or nil
    out.scratch = bp:scratched() or nil
    out.glass = bp:haveGlass() or nil
    out.bullet = bp:haveBullet() or nil
    out.burn = bp:getBurnTime() > 0 or nil
    out.fracture = bp:getFractureTime() > 0 or nil
    return out
end

local function anyOf(t)
    for _, k in ipairs(OPEN) do if t[k] then return true end end
    return t.fracture == true
end

-- the part's memory in the player's mod data: {k = "deep,glass,", cl = cleaned, st = stitched,
-- ub = a bandage to come off was on the list, uo = it came off}
local function memory(player)
    local md = player:getModData()
    md.KnoxTable = md.KnoxTable or {}
    return md.KnoxTable
end

-- the picture's wound pinned while a done step is taken back: [player] = {index, kind}
W.force = W.force or {}

--- Stitches taken out by hand (the tab's undo, the author 2026-11-11): the stitch step is to do again.
function W.forgetStitch(player, index)
    local m = memory(player)[index]
    if m then m.st = nil end
end

local function alcohol(bp)
    local ok, v = pcall(function() return bp:getAlcoholLevel() end)
    return ok and (tonumber(v) or 0) > 0
end

--- The record of one body part, or nil when it is well (and its memory let go).
function W.record(player, index, bp)
    if H.missing(player, index) then return nil end
    local mem = memory(player)
    local m = mem[index]
    local now = kindsNow(bp, {})
    local bandaged, splinted, stitched = bp:bandaged(), bp:getSplintFactor() > 0, bp:stitched()
    local bleeding = bp:getBleedingTime() > 0
    local infected = bp:isInfectedWound()
    if not (anyOf(now) or bandaged or splinted or stitched or bleeding or infected) then
        mem[index] = nil
        return nil
    end
    if not m then
        m = {k = ""}
        mem[index] = m
    end
    -- the kinds seen in this round of treatment
    local seen = {}
    for k in string.gmatch(m.k, "(%w+),") do seen[k] = true end
    local added = false
    for k in pairs(now) do
        if not seen[k] then
            seen[k] = true
            added = true
        end
    end
    if bleeding and not (seen.deep or seen.lacer or seen.scratch or seen.bite or seen.burn or seen.glass or seen.bullet) then
        seen.lacer, added = true, true   -- (a bleeding with no wound named: a cut)
    end
    if added then
        local s = ""
        for _, k in ipairs({"deep", "bite", "lacer", "scratch", "glass", "bullet", "burn", "fracture"}) do
            if seen[k] then s = s .. k .. "," end
        end
        m.k = s
    end
    local dirtyBand = bandaged and bp:getBandageLife() <= 0
    if alcohol(bp) then m.cl = true end
    if stitched then m.st = true end
    -- a bandage to come off: dirty, or over what has to be seen to under it
    if bandaged and (dirtyBand or now.glass or now.bullet or (now.deep and not stitched)
            or (now.burn and bp:isNeedBurnWash()) or (infected and not m.cl)) then
        if not m.ub then m.ub, m.uo = true, nil end
    end
    if m.ub and not bandaged then m.uo = true end

    local open = seen.deep or seen.bite or seen.lacer or seen.scratch or infected
    local list = {}
    local function step(id, on, done)
        if on then list[#list + 1] = {id = id, done = done == true, key = W.STEP_KEY[id]} end
    end
    step("unb", m.ub, m.uo)
    step("tw", seen.glass, not now.glass)
    step("bullet", seen.bullet, not now.bullet)
    step("burn", seen.burn, not bp:isNeedBurnWash())
    step("clean", open, m.cl)
    step("stitch", seen.deep, m.st or stitched)
    step("bandage", open or seen.glass or seen.bullet or seen.burn, bandaged and not dirtyBand and (not m.ub or m.uo))
    step("splint", seen.fracture and splintable(bp), splinted or not now.fracture)
    -- a step left behind a later one done (cleaning under a fresh bandage): passed over
    local laterDone = false
    for i = #list, 1, -1 do
        local s = list[i]
        if s.done then laterDone = true
        elseif laterDone and (s.id == "clean" or s.id == "stitch") then s.skipped = true end
    end
    local cur
    for _, s in ipairs(list) do
        if not s.done and not s.skipped then cur = s break end
    end

    local function done(id)
        for _, s in ipairs(list) do if s.id == id then return s.done end end
        return true
    end
    -- the picture's wound: the step being done, else the worst open one, else the fracture
    local main
    -- (a splint taken off with its game: the picture shows the fracture meanwhile)
    local force = W.force[player]
    if force and force.index == index then main = force.kind
    elseif cur and cur.id == "tw" then main = "glass"
    elseif cur and cur.id == "bullet" then main = "bullet"
    elseif cur and cur.id == "burn" then main = "burn"
    elseif cur and cur.id == "splint" then main = "fracture" end
    if not main then
        for _, k in ipairs(OPEN) do
            if seen[k] and (now[k] or k ~= "glass") then main = k break end
        end
    end
    main = main or (seen.fracture and "fracture") or "lacer"

    -- the look (the mockup's look(w))
    local band = done("bandage") and done("unb")
    local L = {}
    local progress = 0
    if main == "fracture" and not open then
        if splinted then
            L.style, L.c, L.k, L.tag, L.words, L.calm = "fracture", W.COL.fracture, 0.55, "Tag_splint", tx("Lw_splinted"), true
        else
            L.style, L.c, L.k, L.tag, L.words = "fracture", W.COL.fracture, 0.95, "Tag_fracture", tx("Lw_noSplint")
        end
    elseif bleeding and not band then
        L.style, L.c, L.k, L.tag = "bleed", W.COL.bleed, 1, "Tag_bleed"
        L.words = stitched and tx("Lw_bleedStitched")
            or (tx("Lw_bleed") .. " " .. string.char(183) .. " " .. tx(m.cl and "Lw_cleaned" or "Lw_notCleaned"))
    elseif dirtyBand and not done("unb") then
        L.style, L.c, L.k, L.tag = "infect", W.COL.infect, 0.95, "Tag_infect"
        L.words = tx(infected and "Lw_dirtyBand" or "Lw_dirtyBandOnly")
    elseif infected and not m.cl then
        L.style, L.c, L.k, L.tag, L.words = "infect", W.COL.infect, 0.9, "Tag_infect", tx("Lw_infected")
    elseif now.glass and not done("tw") then
        L.style, L.c, L.k, L.tag, L.words = "glass", W.COL.glass, 0.7, "Tag_glass", tx("Lw_glass")
    elseif now.bullet then
        L.style, L.c, L.k, L.tag, L.words = "glass", W.COL.glass, 0.7, "Tag_open", tx("Lw_bullet")
    elseif not band then
        L.style, L.c, L.k, L.tag = "open", W.COL.open, 0.75, "Tag_open"
        if now.burn and bp:isNeedBurnWash() then L.words = tx("Lw_burn")
        else L.words = (stitched and (tx("Lw_stitched") .. " " .. string.char(183) .. " ") or "") .. tx("Lw_notBandaged") end
    else
        local kindH = splinted and "splinted" or "bandaged"
        progress = H.healProgress(player, bp, kindH) or 0.03
        local left = H.healEstimate(player, bp, kindH)
        L.style, L.c, L.k, L.tag, L.heal = "heal", mix(W.COL.sand, W.COL.mint, progress), 0.5, "Tag_heal", true
        L.words = tx("Lw_healing")
        if H.healed(bp, "bandaged") and (not seen.fracture or H.healed(bp, "splinted")) then
            L.words = getText("IGUI_KnoxHP_St_CanRemove")
            progress = 1
        elseif left ~= nil then
            L.left = H.healText(left)
            if left ~= false then L.words = L.words .. " " .. string.char(183) .. " " .. tx("Lw_left", L.left) end
        end
    end
    L.rgb = rgbInt(L.c)
    L.tagText = KnoxTheme.upper(tx(L.tag))

    -- the picture's scene flags (KnoxWoundCanvas.knoxWoundScene)
    local flags = 0
    if bleeding and not bandaged then flags = flags + 1 end
    if bleeding and bandaged then flags = flags + 2 end
    if open and not m.cl and not bandaged and WOUNDISH[main] then flags = flags + 4 end
    if infected then flags = flags + 8 end
    if m.cl then flags = flags + 16 end
    if stitched or m.st then flags = flags + 32 end
    if bandaged then flags = flags + 64 end
    if dirtyBand then flags = flags + 128 end
    if splinted then flags = flags + 256 end
    if seen.glass and not now.glass then flags = flags + 512 end
    if now.bullet then flags = flags + 1024 end

    local title = tx("W_" .. main)
    if main ~= "fracture" and seen.fracture then title = title .. ", " .. string.lower(tx("W_fracture")) end
    local depth = tx("D_" .. ((main == "bite") and "deep" or main))
    local hp = math.max(0, math.floor(bp:getHealth() + 0.5))
    local r = {index = index, bp = bp, part = H.partName(bp), hp = hp, kind = main, kindN = W.KIND[main] or 2,
        title = title, depth = depth, steps = list, cur = cur, look = L, flags = flags, progress = progress,
        bleeding = bleeding, infected = infected, stitched = stitched, bandaged = bandaged}
    r.partUpper = KnoxTheme.upper(r.part)
    r.partLower = string.lower(r.part)
    -- the rows' words, made here once (the tab draws them every frame)
    local left = 0
    for _, s in ipairs(list) do if not s.done and not s.skipped then left = left + 1 end end
    r.left = left
    if L.heal then
        if L.left and L.left ~= "" and progress < 1 then r.healLine = tx("HealIn", L.left)
        else r.healLine = tx("HealClosed", L.left or tx("HealUnknown")) end
    else
        r.depthLine = tx("DepthLine", depth)
        -- (a fracture is not open: the mockup's "in a splint ~5 weeks, without much longer", the time not known)
        r.healLine = tx("HealLine", tx(main == "fracture" and "HealFracture" or "HealUnknown"))
    end
    -- what changed, for the tab (a new step, a done one, a new look)
    local sig = main .. "|" .. L.style .. "|" .. flags .. "|" .. hp
    for _, s in ipairs(list) do sig = sig .. (s.done and "+" or (s.skipped and "~" or "-")) .. s.id end
    r.sig = sig
    return r
end

local function byOrder(a, b)
    local oa, ob = W.ORDER[a.look.style] or 5, W.ORDER[b.look.style] or 5
    if oa ~= ob then return oa < ob end
    if a.hp ~= b.hp then return a.hp < b.hp end
    return a.index < b.index
end

--- Every hurt part's record, the most urgent first (the mockup's ORDER).
function W.parts(player)
    local out, byIndex = {}, {}
    local bps = player:getBodyDamage():getBodyParts()
    for i = 0, bps:size() - 1 do
        local ok, r = pcall(W.record, player, i, bps:get(i))
        if ok and r then
            out[#out + 1] = r
            byIndex[i] = r
        elseif not ok then
            print("[Knox] health table, part " .. i .. ": " .. tostring(r))
        end
    end
    table.sort(out, byOrder)
    return out, byIndex
end

-- The kit (the mockup's ITEMS and GROUPS) ------------------------------------------------------

W.GROUPS = {"wrap", "clean", "stitch", "bone", "pills"}

local function check(key, item)
    local f = Care.CHECK[key]
    if not f then return false end
    local ok, res = pcall(f, item)
    return ok and res == true
end

--- The kit's group of a thing.
function W.groupOf(item)
    if check("ContextMenu_Bandage", item) then return "wrap" end
    if check("ContextMenu_Disinfect", item) then return "clean" end
    if check("ContextMenu_Stitch", item) or check("ContextMenu_Remove_Glass", item) or check("ContextMenu_Remove_Bullet", item) then
        return "stitch"
    end
    if item:getType() == "Splint" then return "bone" end
    return "pills"
end

-- what a pill is for: the moodle it helps (the mockup's ITEMS .mood)
local function pillMood(item)
    local t = item:getType() or ""
    if t == "Pills" then return "PAIN" end
    if t == "PillsBeta" then return "PANIC" end
    if t == "PillsAntiDep" then return "UNHAPPY" end
    if t == "PillsSleepingTablets" then return "TIRED" end
    if string.find(t, "Cigar") or string.find(t, "Tobacco") then return "STRESS" end
    return nil
end
W.pillMood = pillMood

--- Is it taken whole (pills, a smoke): a double click takes it.
function W.whole(item)
    local t = item:getType() or ""
    return string.find(t, "Pills") ~= nil or t == "Antibiotics" or pillMood(item) ~= nil
end

-- its description's key (the mockup's ITEMS .desc)
function W.descKey(item)
    local t = item:getType() or ""
    if t == "Bandaid" then return "Desc_Bandaid" end
    if t == "RippedSheets" or t == "AlcoholRippedSheets" or string.find(t, "Strips") then return "Desc_Rag" end
    if check("ContextMenu_Bandage", item) then return "Desc_Bandage" end
    if check("ContextMenu_Disinfect", item) then return "Desc_Disinfect" end
    if t == "SutureNeedle" then return "Desc_SutureNeedle" end
    if t == "Needle" then return "Desc_Needle" end
    if t == "Thread" then return "Desc_Thread" end
    if t == "Tweezers" or t == "SutureNeedleHolder" then return "Desc_Tweezers" end
    if t == "Splint" then return "Desc_Splint" end
    if t == "Pills" then return "Desc_Painkillers" end
    if t == "Antibiotics" then return "Desc_Antibiotics" end
    if t == "PillsBeta" then return "Desc_Beta" end
    if pillMood(item) == "STRESS" then return "Desc_Smoke" end
    if string.find(t, "Cataplasm") then return "Desc_Poultice" end
    if string.find(t, "Pills") then return "Desc_Pills" end
    return "Desc_Other"
end

--- Does a step take this thing (the step's own check, the way the game's handlers pick)?
function W.stepTakes(stepId, item)
    local key = W.STEP_KEY[stepId]
    if not key then return false end
    if stepId == "bandage" or stepId == "burn" then
        if string.find(string.lower(item:getType() or ""), "dirty") then return false end
    end
    if stepId == "splint" then
        -- (a ready splint is the kit's; planks and sheets go by the quick treatment)
        return item:getType() == "Splint"
    end
    return check(key, item)
end

return KnoxHealthWounds
