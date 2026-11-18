-- The Knox screen's Health tab, 1.0 (the author's mockup .claude/mockups/health/health_v3.html,
-- 2026-11-10: "a new Health tab after the mockup"; the mockup stays the design's source - which of
-- its functions is which part of this file: .claude/mockups/health/SYNC.md):
--   STATE  the overall health - the number, the cardiogram, how it goes, what each wound took -,
--          the moodles in the game's icons in Knox's frames, the body's needs;
--   BODY   the 3D character lit where it is hurt (KnoxHealthModel, the look's colour); the part
--          under the mouse: its card beside the body on a leader line;
--   TABLE  what matters now (a row per hurt part, the most urgent first), or the part put on the
--          table: its wound seen from above (KnoxWoundArt), its steps of treatment in medical order,
--          the quick treatment and the game's own menu;
--   KIT    what the character carries that treats, by group: under the mouse the parts it would
--          treat light up, the box beside says what it is for.
-- A step is the game's own timed action, played as a mini-game on the wound's picture while it
-- runs (KnoxHealthGames). Nothing is dragged onto the body any more (the author, 2026-11-10): a
-- click on the kit's thing does the step of the part on the table, a double click takes a pill.
-- The mouse: a click puts a part on the table, Shift + click treats it quickly, the right button
-- opens the game's menu (a part's, a thing's), held and dragged on the body it turns the character.
-- The data: KnoxHealthData, KnoxHealthWounds; treating: KnoxHealthCare, KnoxHealthGames; the
-- model: KnoxHealthModel; the pictures: Java KnoxWoundCanvas.

require "ISUI/ISPanel"
require "Knox/KnoxTheme"
require "Knox/KnoxHealthCU"
require "Knox/KnoxHealthData"
require "Knox/KnoxHealthCare"
require "Knox/KnoxHealthModel"
require "Knox/KnoxHealthWounds"
require "Knox/KnoxHealthGames"

KnoxHealthPanel = KnoxHealthPanel or ISPanel:derive("KnoxHealthPanel")
local P = KnoxHealthPanel
local T = KnoxTheme
local H = KnoxHealthData
local Care = KnoxHealthCare
local Model = KnoxHealthModel
local W = KnoxHealthWounds
local G = KnoxHealthGames

local DOT = " " .. string.char(183) .. " "
local DEG = string.char(176)
local TIMES = string.char(215)
local MINUS = "-"            -- (the Knox fonts' own minus is the hyphen)
local LSAQUO, RSAQUO = string.char(8249), string.char(8250)   -- ‹ ›
local REFRESH_MS = 250       -- the data read anew (the frame draws what was read)
local DBL_MS = 400           -- a double click on the kit
local ROT_PX = 40            -- the mouse's way for an eighth of a turn of the character
local WF = 9                 -- KnoxWoundCanvas.WORD_FIELDS

-- the pictures (KnoxWoundCanvas ids and views)
local PIC_TABLE, PIC_CARD, PIC_ECG, PIC_ROW = G.CANVAS, 2, 3, 100
local VIEW_TABLE, VIEW_MINI, VIEW_THUMB = 0, 1, 2

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function tx(key, ...) return getText("IGUI_KnoxHP_" .. key, ...) end

local function hexc(h)
    return {r = math.floor(h / 65536) / 255, g = (math.floor(h / 256) % 256) / 255, b = (h % 256) / 255}
end
-- the mockup's colours that are not Knox's own (T.color has the rest)
local X = {
    med = hexc(0x3b2427), mint = hexc(0x8fd0b0), grid = hexc(0x141717), ecg = hexc(0x070808),
    pip = hexc(0x232727), litBg = hexc(0x17170f), rowLit = hexc(0x141512), fitBg = hexc(0x4a3a2c),
    now = hexc(0xf1e3b2), mainHot = hexc(0xe2d3a0), timeBar = hexc(0x6e7370), black = hexc(0x000000),
}

-- the character turned by the right button: the directions in order
local DIRS = {IsoDirections.S, IsoDirections.SW, IsoDirections.W, IsoDirections.NW,
              IsoDirections.N, IsoDirections.NE, IsoDirections.E, IsoDirections.SE}

-- a step's picture when no thing of it is to hand (done, or none carried)
local STEP_TEX = {unb = "Item_BandageDirty", tw = "Item_Tweezers", bullet = "Item_Tweezers", burn = "Item_Rag",
    clean = "Item_AlcoholWipes", stitch = "Item_SutureNeedle", bandage = "Item_Bandage", splint = "Item_Splint"}
local stepTexCache = {}
local function stepTex(id)
    local t = stepTexCache[id]
    if t == nil then
        t = getTexture(STEP_TEX[id] or "Item_Bandage") or false
        stepTexCache[id] = t
    end
    return t or nil
end

-- Sizes: the mockup's pixels at 1080p (a 48 px cell) times the screen's cell -----------------

local K = 1
local function px(v) return math.floor(v * K + 0.5) end

local F = {}   -- the fonts, by the mockup's style and size
local function font(style, size)
    local s = size * K
    if T.javaFonts then
        if s > 44 then return T.makeBigFont(style, s) end
        return T.makeFont(style, s)
    end
    -- (a language Knox's atlases can't write: the game's fonts)
    if size >= 40 then return UIFont.Large end
    if size >= 19 then return T.fontHeader end
    if style == "body" then return size >= 15 and T.fontText or T.fontTile end
    return size >= 14 and T.fontCaps or T.fontTile
end

local wordFonts = {}   -- the pictures' words' fonts, by weight and size

--- The tab's places and fonts (made again when the screen's cell or the panel's size changes).
function P:metrics()
    K = T.cell / 48
    local w, h = self:getWidth(), self:getHeight()
    local m = self.m
    if m and m.w == w and m.h == h and m.cell == T.cell and m.fonts == T.fontText and F.big then return m end
    m = {w = w, h = h, cell = T.cell, fonts = T.fontText}
    m.sw = px(372)                -- the state's width
    m.bx, m.bw = px(384), px(468) -- the body's
    m.rx = px(864)                -- the table and the kit
    m.rw = w - m.rx
    m.kh = px(276)
    m.ky = h - m.kh
    m.th = m.ky - px(12)
    m.midH = h
    F.ptitle = font("title", 24)
    F.t26, F.t24, F.t22, F.t21, F.t20 = font("title", 26), font("title", 24), font("title", 22), font("title", 21), font("title", 20)
    F.t18, F.t16, F.t13, F.t12 = font("title", 18), font("title", 16), font("title", 13), font("title", 12)
    F.h18, F.h16, F.h15, F.h14, F.h13, F.h12 = font("head", 18), font("head", 16), font("head", 15), font("head", 14),
        font("head", 13), font("head", 12)
    F.b19, F.b17, F.b16, F.b15, F.b14, F.b13 = font("body", 19), font("body", 17), font("body", 16), font("body", 15),
        font("body", 14), font("body", 13)
    F.big = font("title", 78)
    F.bigS = font("title", 50)   -- (100: three digits do not fit beside the cardiogram at 78)
    wordFonts = {}
    self.pics = knoxWoundTex ~= nil and knoxWoundScene ~= nil and (knoxWoundOk == nil or knoxWoundOk() == true)
    self.m = m
    self.dirty = true
    return m
end

-- Drawing helpers (the layout kit's, with their bands and options filled in, not made anew) ----

local R4 = {0, 0, 0, 0}
local LO, SO = {}, {}

--- Text in the band x, y, w, h (T.label): align "left" (default), "right", "centre".
local function label(ui, s, x, y, w, h, c, f, align, a)
    R4[1], R4[2], R4[3], R4[4] = x, y, w, h
    LO.font, LO.align, LO.a = f, align, a
    return T.label(ui, s, R4, c, LO)
end

--- Letter-spaced text (the mockup's caps with letter-spacing): align "left" or "centre".
local function spaced(ui, s, x, y, w, h, c, f, ls, align, a)
    R4[1], R4[2], R4[3], R4[4] = x, y, w, h
    SO.font, SO.ls, SO.align, SO.a = f, ls, align, a
    return T.spaced(ui, s, R4, c, SO)
end

local function panel(ui, x, y, w, h)
    T.rect(ui, x, y, w, h, T.color.window, T.bgAlpha())
    T.border(ui, x, y, w, h, T.color.border)
end

-- a 2 px dashed frame (an empty step's slot)
local function dashed(ui, x, y, w, h, c, a)
    local d, g = px(6), px(4)
    local t = math.max(1, px(2))
    for xx = x, x + w - 1, d + g do
        local dw = math.min(d, x + w - xx)
        T.rect(ui, xx, y, dw, t, c, a)
        T.rect(ui, xx, y + h - t, dw, t, c, a)
    end
    for yy = y, y + h - 1, d + g do
        local dh = math.min(d, y + h - yy)
        T.rect(ui, x, yy, t, dh, c, a)
        T.rect(ui, x + w - t, yy, t, dh, c, a)
    end
end

-- a 2 px frame of any width (T.tileFrame is 2 px)
local function frame2(ui, x, y, w, h, c, a)
    T.tileFrame(ui, x, y, w, h, c, a)
end

-- an angle ">" of 2 px dots, its tip at cx, cy (the steps' arrows)
local function chevron(ui, cx, cy, s, c, a)
    for i = 0, s do
        T.rect(ui, cx - s + i, cy - s + i, 2, 2, c, a)
        T.rect(ui, cx - s + i, cy + s - i, 2, 2, c, a)
    end
end

-- a tick on a square of side s (a done step's mark)
local function tick(ui, x, y, s, c)
    local u = s / 18
    local x0, y0 = x + math.floor(4 * u + 0.5), y + math.floor(8 * u + 0.5)
    local a, b = math.floor(3 * u + 0.5), math.floor(7 * u + 0.5)
    for i = 0, a do T.rect(ui, x0 + i, y0 + i, 2, 2, c) end
    for i = 0, b do T.rect(ui, x0 + a + i, y0 + a - i, 2, 2, c) end
end

-- a cross on a square of side s (a done step's mark under the mouse: a click undoes it)
local function cross(ui, x, y, s, c)
    local u = s / 18
    local x0, y0 = x + math.floor(4 * u + 0.5), y + math.floor(4 * u + 0.5)
    local n = math.floor(8 * u + 0.5)
    for i = 0, n do
        T.rect(ui, x0 + i, y0 + i, 2, 2, c)
        T.rect(ui, x0 + n - i, y0 + i, 2, 2, c)
    end
end

-- a triangle (the trend's: Knox's fonts have no arrows), its box x, y, s wide
local function triangle(ui, x, y, s, up, c)
    local hgt = math.max(2, math.floor(s * 0.6 + 0.5))
    for i = 0, hgt - 1 do
        local k = up and (i + 1) / hgt or (1 - i / hgt)
        local rw = math.max(1, math.floor(s * k + 0.5))
        T.rect(ui, x + math.floor((s - rw) / 2), y + i, rw, 1, c)
    end
end

-- The places the mouse can be on (a pool: filled each frame, no tables made) -----------------

local function hit(self, kind, x, y, w, h, a, b)
    local n = self.nHits + 1
    self.nHits = n
    local r = self.hitPool[n]
    if not r then
        r = {}
        self.hitPool[n] = r
    end
    r.kind, r.x, r.y, r.w, r.h, r.a, r.b = kind, x, y, w, h, a, b
    return r
end

local function hitAt(self, x, y)
    for i = self.nHits, 1, -1 do
        local r = self.hitPool[i]
        if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h then return r end
    end
    return nil
end

-- The panel ---------------------------------------------------------------------------------

function P:new(x, y, w, h, playerNum, screen)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.playerNum = playerNum
    o.screen = screen
    o.anim = {}
    o.hitPool, o.nHits = {}, 0
    o.listScroll = 0
    o.view = {}
    o.dirty = true
    return o
end

function P:player()
    return getSpecificPlayer(self.playerNum)
end

function P:createChildren()
    self.model = Model.create(self)
end

--- Shown again (the tab chosen): read anew, nothing under the mouse yet.
function P:shown()
    self.dirty = true
    self.pressKind, self.rmbOn = nil, nil
    self.hvKind = nil
end

--- A value on its way to `target`: it moves over a moment instead of jumping.
function P:ease(key, target, ms)
    local now = getTimestampMs()
    local s = self.anim[key]
    if not s then
        s = {v = target, ms = now}
        self.anim[key] = s
        return target
    end
    local dt = math.min(100, now - s.ms)
    s.ms = now
    s.v = s.v + (target - s.v) * T.anim(math.min(1, dt / (ms or 90)))
    if math.abs(target - s.v) < 0.002 then s.v = target end
    return s.v
end

-- The data (read every quarter of a second; the frame only draws it) ----------------------------

local function itemName(item)
    return item:getDisplayName() or item:getName() or ""
end

-- the bag a thing lies in (nil: in the pockets), and the chain of bags' names
local function bagOf(item)
    local c = item:getContainer()
    return c and c:getContainingItem() or nil
end

local function bagChain(item)
    local names = {}
    local bag = bagOf(item)
    local n = 0
    while bag and n < 4 do
        names[#names + 1] = itemName(bag)
        bag = bagOf(bag)
        n = n + 1
    end
    if #names == 0 then return tx("InPockets") end
    return tx("InChain", table.concat(names, ", "))
end

-- the moodles' levels (the pulse is made from them)
local function moodLevel(player, id)
    local t = MoodleType[id]
    if not t then return 0 end
    local m = player:getMoodles()
    local ok, v = pcall(m.getMoodleLevel, m, t)
    return ok and tonumber(v) or 0
end

local function decimal(s)
    return (string.gsub(s, "%.", tx("Decimal")))
end

-- does a step want a thing (unb is by hand; glass by hand too, a tool better)?
local function needsItem(id)
    return id ~= "unb"
end

--- Reads what the tab shows (now and then, or at once after a change).
function P:refresh(player, force)
    local now = getTimestampMs()
    if not force and not self.dirty and self.D and now - (self.dataMs or 0) < REFRESH_MS then return self.D end
    self.dirty = false
    self.dataMs = now
    local m = self.m
    local D = {}
    D.recs, D.byIndex = W.parts(player)
    local items = Care.reachable(player)
    local counts = {}
    for _, it in ipairs(items) do
        local ft = it:getFullType()
        counts[ft] = (counts[ft] or 0) + 1
    end
    D.items = items

    -- the words that stay
    D.tState, D.tBody, D.tKit = T.upper(tx("State")), T.upper(tx("Body")), T.upper(tx("Kit"))
    D.tHealth, D.tOf, D.tPulse = T.upper(tx("Health")), tx("OfHundred"), T.upper(tx("Pulse"))
    D.tEffects, D.tOrganism = T.upper(tx("Effects")), T.upper(tx("Organism"))
    D.tList, D.tListNote, D.tKitNote = T.upper(tx("ListTitle")), tx("ListNote"), tx("KitNote")
    D.tNext, D.tNothingToDo, D.tStepNone = tx("Next"), tx("NothingToDo"), tx("StepNone")
    D.tToTableGo, D.tNoWounds, D.tNoWoundsSub = T.upper(tx("ToTableGo")), T.upper(tx("NoWoundsTitle")), tx("NoWoundsSub")
    D.tBack = LSAQUO .. " " .. T.upper(tx("AllWounds"))
    D.tPartHp, D.tOfShort = T.upper(tx("PartHp")), " " .. tx("OfHundred")
    D.tQuick, D.tAll, D.tNothing = T.upper(tx("QuickTreat")), T.upper(tx("BtnAll")), T.upper(tx("BtnNothing"))
    D.tPlaying, D.tDoing = tx("StepPlaying"), tx("StepDoing")
    D.tHoverPart, D.tOnTable = tx("HoverPart"), tx("OnTable") .. " "
    D.tCardNone, D.tOneWound = tx("CardNone"), tx("OneWound")
    D.tKeyLmb, D.tKeyShift, D.tToTable, D.tQuickShort = tx("KeyLmb"), tx("KeyShiftLmb"), tx("ToTable"), tx("QuickShort")
    D.tGameReady, D.tGameTime = T.upper(tx("GameReady")), T.upper(tx("GameTime"))
    D.tIdle = tx(isClient() and "GameIdleMp" or "GameIdle")
    D.tHowTitle = T.upper(tx("HowTitle"))
    if not self.howLines or self.howW ~= m.rw then
        self.howW = m.rw
        local lines = {}
        local ww = m.rw - px(628) - px(16) - px(32)
        for i = 1, 4 do
            for _, l in ipairs(T.wrap(tx("HowText" .. i), F.b15, ww)) do lines[#lines + 1] = l end
        end
        self.howLines = lines
    end
    -- (the parts' names, for the card of a part with nothing wrong)
    if not self.partNames then
        local names = {}
        local bps = player:getBodyDamage():getBodyParts()
        for i = 0, bps:size() - 1 do names[i] = T.upper(H.partName(bps:get(i))) end
        self.partNames = names
    end

    -- the overall health, its pulse, how it goes, what each wound took
    local hp = math.floor(player:getBodyDamage():getHealth() + 0.5)
    D.hp, D.hpText = hp, tostring(hp)
    local bleeding, infected, open = false, false, false
    for _, r in ipairs(D.recs) do
        if r.look.style == "bleed" or r.bleeding then bleeding = true end
        if r.look.style == "infect" or r.infected then infected = true end
        if not r.look.heal and not r.look.calm then open = true end
    end
    -- (the pulse: the mockup's 104 bleeding, 86 calm - made from the moodles in the game)
    local bpm = 72 + (bleeding and 22 or 0) + 5 * moodLevel(player, "PANIC") + 3 * moodLevel(player, "PAIN")
        + 2 * moodLevel(player, "STRESS") + math.floor((100 - hp) * 0.2)
    D.bpm = clamp(bpm, 60, 160)
    D.bpmText = tostring(D.bpm)
    D.ecgRgb = bleeding and W.rgbInt(W.COL.bleed) or W.rgbInt(W.COL.sand)
    local pace = H.healthPace(player)
    if bleeding then
        D.trendArrow, D.trendUp, D.trendC = true, false, W.COL.bleed
        D.trendMain = T.upper(tx("TrendWorse"))
        D.trendRest = (pace and pace > 0.05) and (DOT .. tx("TrendBleed", MINUS .. math.max(1, math.floor(pace + 0.5)))) or nil
    elseif infected then
        D.trendArrow, D.trendUp, D.trendC = true, false, W.COL.infect
        D.trendMain, D.trendRest = T.upper(tx("TrendSlow")), DOT .. tx("TrendInfect")
    elseif #D.recs > 0 or hp < 100 then
        D.trendArrow, D.trendUp, D.trendC = true, true, W.COL.mint
        D.trendMain = T.upper(tx("TrendBetter"))
        D.trendRest = #D.recs > 0 and (DOT .. tx(open and "TrendOpen" or "TrendClosed")) or nil
    else
        D.trendArrow, D.trendUp, D.trendC = false, true, W.COL.mint
        D.trendMain, D.trendRest = T.upper(tx("TrendFine")), DOT .. tx("TrendNoWounds")
    end
    -- the loss bar: the health lost shared by how much each part lost
    local lost = math.max(0, 100 - hp)
    local sum = 0
    for _, r in ipairs(D.recs) do sum = sum + math.max(0, 100 - r.hp) end
    D.loss = {}
    if lost > 0 and sum > 0 then
        for _, r in ipairs(D.recs) do
            local part = lost * math.max(0, 100 - r.hp) / sum
            if part > 0 then
                D.loss[#D.loss + 1] = {index = r.index, frac = part / 100, c = r.look.c}
                r.lossText = " " .. tx("LossPart", math.floor(part + 0.5), lost)
            end
        end
        table.sort(D.loss, function(a, b) return a.frac > b.frac end)
    end
    D.lossAll = lost > 0 and tx("LossAll", lost) or tx("LossNone")

    -- the looks for the model's light; the rows' words
    D.looks = {}
    for _, r in ipairs(D.recs) do
        D.looks[r.index] = r.look
        r.hpText = tostring(r.hp)
        r.cardSub = D.tOneWound .. DOT .. tx("DepthIs", r.depth)
        local row = {}
        r.row = row
        local rowW = m.rw - px(32) - px(262) - px(24) - T.measure(F.t13, r.look.tagText) - px(30)
        row.pw = T.fit(r.title .. DOT .. r.look.words, F.b16, rowW)
        local c = r.cur
        if c then
            row.next = string.lower(tx("Step_" .. c.id))
            local it = needsItem(c.id) and Care.stepItem(items, c.id) or nil
            local wants = needsItem(c.id) and not (c.id == "tw" and not it)
            row.item = it
            row.have = it and tx("HaveIt", string.lower(itemName(it))) or nil
            row.none = wants and not it and not (c.id == "splint" and Care.stepCan(items, r.bp, "splint"))
        end
    end

    -- the part on the table
    local sel = self.sel
    local rec = sel and D.byIndex[sel] or nil
    local session = G.session(player)
    if sel and not rec then
        if session and self.selRec then rec = self.selRec
        else self.sel, sel = nil, nil end
    end
    self.selRec = rec
    if rec then
        local S = {}
        D.sel = S
        S.tsub = T.fit(rec.title .. DOT .. rec.look.words, F.b15, m.rw - px(150) - px(140))
        S.wn = T.upper(rec.title)
        S.ws = T.wrap(rec.look.words, F.b16, px(280))
        if rec.look.heal then S.wt = T.wrap(rec.healLine or "", F.b15, px(270))
        else
            S.wt = T.wrap(rec.depthLine or "", F.b15, px(270))
            for _, l in ipairs(T.wrap(rec.healLine or "", F.b15, px(270))) do S.wt[#S.wt + 1] = l end
        end
        local steps, can, left = {}, 0, 0
        for i, s in ipairs(rec.steps) do
            local v = {id = s.id, i = i}
            local it = needsItem(s.id) and Care.stepItem(items, s.id) or nil
            local wants = needsItem(s.id) and not (s.id == "tw" and not it)
            local have = (not wants) or it ~= nil or (s.id == "splint" and Care.stepCan(items, rec.bp, "splint"))
            if s.done then
                v.state = "done"
                v.undo = Care.undoable(rec.bp, s.id)
                v.xid = "x" .. s.id
            elseif s.skipped then v.state = "skip"
            elseif s == rec.cur then v.state = Care.stepCan(items, rec.bp, s.id) and "cur" or "none"
            -- (the author 2026-11-11: the order is advice, not a lock - "in the game cleaning is not
            -- a must before a bandage": a later step the game allows now can be done now)
            elseif Care.stepCan(items, rec.bp, s.id) then v.state = "free"
            else v.state = "future" end
            if not s.done and not s.skipped then
                left = left + 1
                if have then can = can + 1 end
            end
            v.name = T.upper(tx((s.done and "StepDone_" or "Step_") .. s.id))
            v.item = (not s.done) and it or nil
            v.tex = stepTex(s.id)
            if s.done then v.sub = tx("StepReady")
            elseif s.skipped then v.sub = tx("StepSkipped")
            elseif not wants then v.sub = tx("StepHands")
            elseif it then
                local n = counts[it:getFullType()] or 1
                v.sub = string.lower(itemName(it)) .. (n > 1 and (" " .. TIMES .. n) or "")
            elseif have then v.sub = tx("StepReady")
            else v.sub = D.tStepNone end
            v.sub = T.fit(v.sub, F.b14, px(132))
            v.bad = v.state == "none"
            steps[i] = v
        end
        S.steps, S.can, S.left = steps, can, left
        local note
        if left == 0 then note = nil
        elseif can == left then note = tx(G.on() and "QuickGames" or "QuickAll")
        elseif can > 0 then note = tx("QuickSome", can, left)
        else note = tx("QuickNone") end
        S.note = note and T.wrap(note, F.b14, px(230)) or {}
        -- the mini-game's lines: how the hand is, the first aid
        local names = {}
        local shake = G.tremor(player, names)
        S.shakeOn = shake > 0
        S.shake = shake > 0 and tx("ShakeYes", table.concat(names, ", ")) or tx("ShakeNo")
        S.aid = DOT .. tx("FirstAidLvl", player:getPerkLevel(Perks.Doctor))
    end

    -- the moodles (the five that matter most) and what lights with each
    D.moods = {}
    local ml = H.moodles(player)
    for i = 1, math.min(5, #ml) do
        local mo = ml[i]
        local c = mo.good == 1 and T.color.ok or (mo.level >= 2 and T.color.bad or T.color.warn)
        local v = {id = mo.id, name = T.fit(mo.name or "", F.b19, px(210)), desc = T.fit(mo.desc or "", F.b14, px(262)),
                   level = mo.level, c = c, icon = H.moodleIcon(mo.icon, px(40)), parts = {}}
        for _, r in ipairs(D.recs) do
            if (mo.id == "BLEEDING" and r.bleeding) or (mo.id == "PAIN" and not r.look.heal)
                    or (mo.id == "INJURED") then
                v.parts[r.index] = true
            end
        end
        D.moods[i] = v
    end
    -- the body's needs
    D.org = {}
    for _, s in ipairs(H.stats(player)) do
        if s.id == "hunger" or s.id == "thirst" or s.id == "fatigue" then
            D.org[#D.org + 1] = {name = s.name, frac = s.frac, value = s.value .. "%", warn = s.frac > 0.5}
        end
    end
    local temp = H.temperature(player)
    if temp then D.org[#D.org + 1] = {name = tx("Stat_temperature"), value = decimal(temp) .. DEG} end
    D.org[#D.org + 1] = {name = tx("FirstAid"), value = tx("Level", player:getPerkLevel(Perks.Doctor))}
    -- who and which day
    local desc = player:getDescriptor()
    D.who = tx("WhoDay", (desc:getForename() or "") .. " " .. (desc:getSurname() or ""),
        math.floor(player:getHoursSurvived() / 24) + 1)

    -- the kit, by group, laid out (the mockup's flex rows of 590 px)
    D.kit = {}
    local groups = {}
    for _, gid in ipairs(W.GROUPS) do groups[gid] = {id = gid, title = T.upper(tx("G_" .. gid)), tiles = {}} end
    for _, g in ipairs(Care.kit(player)) do
        local gid = W.groupOf(g.item)
        local list = groups[gid].tiles
        local t = {key = g.type, g = g, item = g.item, countText = g.count > 1 and tostring(g.count) or nil,
                   count = g.count, bag = bagOf(g.item), whole = W.whole(g.item), mood = W.pillMood(g.item),
                   wrap = gid == "wrap", fit = {}, now = {}}
        local anti = g.item:getType() == "Antibiotics"
        for _, r in ipairs(D.recs) do
            for _, s in ipairs(r.steps) do
                if not s.done and not s.skipped and W.stepTakes(s.id, g.item) then
                    t.fit[r.index] = true
                    if s == r.cur then t.now[r.index] = true end
                end
            end
            if anti and r.infected then t.fit[r.index] = true end
        end
        list[#list + 1] = t
    end
    local gx, gy = 0, 0
    local maxW = 590
    for _, gid in ipairs(W.GROUPS) do
        local gr = groups[gid]
        local n = math.min(#gr.tiles, math.floor((maxW - 1) / 63))
        if n > 0 then
            local gw = math.max(n * 63 + 1, math.ceil(T.measure(F.h13, gr.title) / K))
            if gx > 0 and gx + gw > maxW then gx, gy = 0, gy + 102 end
            if gy <= 102 then
                gr.x, gr.y, gr.n = gx, gy, n
                D.kit[#D.kit + 1] = gr
            end
            gx = gx + gw + 26
        end
    end
    D.kitEmpty = #D.kit == 0 and tx("KitEmpty") or nil

    self.D = D
    self.hintFor = nil   -- (the kit's box made anew for the thing under the mouse)
    return D
end

-- the kit's box for the thing under the mouse (made when it changes)
function P:itemHint(t)
    if self.hintFor == t.key and self.hint then return self.hint end
    local D, m = self.D, self.m
    local ww = m.rw - px(628) - px(16) - px(32)
    local h = {}
    h.name = T.upper(itemName(t.item))
    h.count = t.count > 1 and (" " .. TIMES .. t.count) or nil
    h.where = T.fit(bagChain(t.item), F.b14, ww)
    h.desc = T.wrap(tx(W.descKey(t.item)), F.b16, ww)
    if t.whole then
        h.use, h.useC = T.wrap(tx("Take"), F.b15, ww), T.color.accent
    else
        local names = {}
        for _, r in ipairs(D.recs) do
            if t.fit[r.index] then names[#names + 1] = r.partLower .. (t.now[r.index] and "" or (" " .. tx("Later"))) end
        end
        if #names > 0 then h.use, h.useC = T.wrap(tx("Helps", table.concat(names, ", ")), F.b15, ww), T.color.accent
        else h.use, h.useC = T.wrap(tx("NothingNow"), F.b15, ww), T.color.dim end
    end
    self.hint, self.hintFor = h, t.key
    return h
end

-- The pictures' words (KnoxWoundCanvas: their places in the picture's pixels) --------------------

local WC = {r = 1, g = 1, b = 1}

local function wordFont(weight, size)
    local wk = (weight >= 700 and 3) or (weight >= 600 and 2) or 1
    local key = wk * 1000 + math.floor(size + 0.5)
    local f = wordFonts[key]
    if not f then
        if T.javaFonts then
            f = T.makeFont((wk == 3 and "title") or (wk == 2 and "head") or "body", size)
        else
            f = T.fontTile
        end
        wordFonts[key] = f
    end
    return f
end

function P:drawWords(id, ox, oy, a)
    local t = knoxWoundTexts and knoxWoundTexts(id)
    if not t then return end
    local n = t.n or 0
    for i = 0, n - 1 do
        local b = i * WF
        local s = t[b + 1]
        if s and s ~= "" then
            local x, y, rgbv, wa = t[b + 2] or 0, t[b + 3] or 0, t[b + 4] or 0, t[b + 5] or 1
            local size, anchor, weight, ls = t[b + 6] or 10, t[b + 7] or 1, t[b + 8] or 400, t[b + 9] or 0
            local f = wordFont(weight, size)
            WC.r = math.floor(rgbv / 65536) / 255
            WC.g = (math.floor(rgbv / 256) % 256) / 255
            WC.b = (rgbv % 256) / 255
            local capH = T.capH(f)
            local top = oy + y - capH
            local wa2 = wa * (a or 1)
            if ls > 0.05 then
                if anchor == 0 then
                    spaced(self, s, ox + x - 1000, top, 2000, capH, WC, f, ls, "centre", wa2)
                else
                    local sx = ox + x
                    if anchor < 0 then sx = sx - (T.measure(f, s) + ls * (string.len(s) - 1)) end
                    spaced(self, s, sx, top, 0, capH, WC, f, ls, "left", wa2)
                end
            elseif anchor == 0 then
                label(self, s, ox + x - 1000, top, 2000, capH, WC, f, "centre", wa2)
            elseif anchor < 0 then
                label(self, s, ox + x - 2000, top, 2000, capH, WC, f, "right", wa2)
            else
                label(self, s, ox + x, top, 0, capH, WC, f, "left", wa2)
            end
        end
    end
end

-- a wound's picture in the box x, y, w, h (its frame and dark ground; the picture inside)
function P:drawPicture(id, view, rec, x, y, w, h, a)
    T.rect(self, x, y, w, h, T.color.screen, a)
    if self.pics and rec then
        knoxWoundScene(id, w - 2, h - 2, view, rec.kindN, rec.flags, rec.progress, rec.look.rgb)
        local tex = knoxWoundTex(id)
        if tex then
            self:drawTextureScaled(tex, x + 1, y + 1, w - 2, h - 2, a or 1, 1, 1, 1)
            self:drawWords(id, x + 1, y + 1, a)
        end
    end
    T.border(self, x, y, w, h, T.color.line, a)
end

-- STATE ------------------------------------------------------------------------------------------

function P:drawState(m, D)
    local w = m.sw
    panel(self, 0, 0, w, m.h)
    local C = T.color
    spaced(self, D.tState, px(16), px(14), 0, px(28), C.bright, F.ptitle, px(1.2), "left")
    label(self, D.who, 0, px(18), w - px(16), px(22), C.dim, F.b15, "right")

    -- the health
    local hx, hy, hw, hh = px(16), px(56), px(340), px(176)
    T.rect(self, hx, hy, hw, hh, C.screen)
    T.border(self, hx, hy, hw, hh, C.border)
    label(self, D.tHealth, hx + px(14), hy + px(12), 0, px(14), C.dim, F.h13)
    -- (the mockup's 64 at 78 px; three digits and "/ 100" would run under the cardiogram)
    local big = F.big
    if T.measure(big, D.hpText) + px(6) + T.measure(F.h18, D.tOf) > px(118) then big = F.bigS end
    local nw = label(self, D.hpText, hx + px(12), hy + px(28), 0, px(70), C.bright, big)
    label(self, D.tOf, hx + px(12) + nw + px(6), hy + px(70), 0, px(22), C.dim, F.h18)
    -- the cardiogram on its grid
    local ex, ey, ew, eh = hx + px(136), hy + px(12), px(192), px(84)
    T.rect(self, ex, ey, ew, eh, X.ecg)
    local step = math.max(4, px(12))
    for gx = ex + step, ex + ew - 1, step do T.rect(self, gx, ey, 1, eh, X.grid) end
    for gy = ey + step, ey + eh - 1, step do T.rect(self, ex, gy, ew, 1, X.grid) end
    if self.pics and knoxWoundEcg then
        knoxWoundEcg(PIC_ECG, ew - 2, eh - 2, D.bpm, D.ecgRgb)
        local tex = knoxWoundTex(PIC_ECG)
        if tex then self:drawTextureScaled(tex, ex + 1, ey + 1, ew - 2, eh - 2, 1, 1, 1, 1) end
    elseif knoxWoundBpm then
        knoxWoundBpm(D.bpm)
    end
    T.border(self, ex, ey, ew, eh, C.line)
    local pr = hx + hw - px(18)
    local bw = label(self, D.bpmText, 0, hy + px(16), pr, px(14), C.bright, F.t12, "right")
    label(self, D.tPulse, 0, hy + px(16), pr - bw - px(4), px(14), C.dim, F.h12, "right")
    -- how it goes
    local ty = hy + px(108)
    local tx0 = hx + px(14)
    if D.trendArrow then
        triangle(self, tx0, ty + px(4), px(9), D.trendUp, D.trendC)
        tx0 = tx0 + px(14)
    end
    local w1 = label(self, D.trendMain, tx0, ty, 0, px(16), D.trendC, F.h14)
    if D.trendRest then label(self, D.trendRest, tx0 + w1, ty, 0, px(16), C.dim, F.b14) end
    -- what each wound took
    local lx, ly, lw, lh = hx + px(14), hy + px(134), px(312), px(10)
    T.rect(self, lx, ly, lw, lh, X.ecg)
    local x = lx + math.floor(lw * D.hp / 100 + 0.5)
    T.rect(self, lx, ly, x - lx, lh, C.bright)
    local focus = self.lossPart
    for _, sg in ipairs(D.loss) do
        local sw = math.min(lx + lw - x, math.max(1, math.floor(lw * sg.frac + 0.5)))
        if sw > 0 then
            T.rect(self, x, ly, sw, lh, sg.c, (focus == nil or focus == sg.index) and 1 or 0.35)
            T.rect(self, x, ly, 1, lh, X.ecg)
            hit(self, "loss", x, ly - px(4), sw, lh + px(8), sg.index)
            x = x + sw
        end
    end
    local capPart = self.lossPart or self.hoverPart
    local cr = capPart and D.byIndex[capPart]
    if cr and cr.lossText then
        local pw = label(self, cr.part, hx + px(14), hy + px(150), 0, px(16), cr.look.c, F.b13)
        label(self, cr.lossText, hx + px(14) + pw, hy + px(150), 0, px(16), C.dim, F.b13)
    else
        label(self, D.lossAll, hx + px(14), hy + px(150), 0, px(16), C.dim, F.b13)
    end

    -- the moodles
    label(self, D.tEffects, px(16), px(252), 0, px(16), C.dim, F.h13)
    local hp = self.hoverPart or self.extPart
    local tile = self.tileHover
    for i, mo in ipairs(D.moods) do
        local y = px(276 + (i - 1) * 70)
        local lit = (self.moodHover == mo) or (tile ~= nil and tile.mood == mo.id)
            or (hp ~= nil and mo.parts[hp] == true and mo.id ~= "INJURED")
        T.rect(self, px(16), y, px(340), px(64), lit and X.litBg or C.cell)
        T.border(self, px(16), y, px(340), px(64), lit and C.accent or C.line)
        local sx, sy = px(21), y + px(5)
        T.rect(self, sx, sy, px(52), px(52), C.screen)
        frame2(self, sx, sy, px(52), px(52), mo.c)
        if mo.icon then self:drawTextureScaledAspect(mo.icon, sx + px(6), sy + px(6), px(40), px(40), 1, 1, 1, 1) end
        label(self, mo.name, px(86), y + px(9), 0, px(22), C.bright, F.b19)
        label(self, mo.desc, px(86), y + px(34), 0, px(18), C.dim, F.b14)
        for p = 1, 4 do
            T.rect(self, px(16 + 340 - 10 - 9 - (4 - p) * 12), y + px(14), px(9), px(9), p <= mo.level and mo.c or X.pip)
        end
        hit(self, "mood", px(16), y, px(340), px(64), i)
    end

    -- the body's needs
    label(self, D.tOrganism, px(16), px(640), 0, px(16), C.dim, F.h13)
    for i, st in ipairs(D.org) do
        local y = px(664 + (i - 1) * 30)
        T.rect(self, px(16), y, px(340), 1, C.line)
        label(self, st.name, px(16), y, 0, px(30), C.text, F.b15)
        if st.frac then
            local bx, by = px(16 + 118), y + px(14)
            T.rect(self, bx, by, px(150), math.max(1, px(2)), X.pip)
            T.rect(self, bx, by, math.floor(px(150) * st.frac + 0.5), math.max(1, px(2)), st.warn and C.warn or C.accent)
        end
        label(self, st.value, 0, y, px(356), px(30), C.bright, F.h15, "right")
    end
end

-- BODY -------------------------------------------------------------------------------------------

function P:drawBody(m, D, player)
    local bx, bw = m.bx, m.bw
    local C = T.color
    panel(self, bx, 0, bw, m.h)
    for y = 100, 860, 40 do T.rect(self, bx, px(y), px(7), 1, C.border) end
    spaced(self, D.tBody, bx + px(16), px(14), 0, px(28), C.bright, F.ptitle, px(1.2), "left")
    if not self.model then return end
    -- the model, nearer to the part on the table (the mockup's renderBodyPose)
    local zT, oxT, oyT = 1, 0, 0
    local sel = self.sel
    if sel then
        local s, fx, fy = Model.frame(0, 0, px(350), px(800))
        local cx, cy = Model.partPoint(sel, s, fx, fy)
        if cx then
            local z = 1.12
            local tx_ = cx + (px(175) - cx) * 0.35
            local ty_ = cy + (px(400) - cy) * 0.12
            zT, oxT, oyT = z, tx_ - cx * z, clamp(ty_ - cy * z, -px(44), 0)
        end
    end
    local z, ox, oy = self:ease("bz", zT, 500), self:ease("box", oxT, 500), self:ease("boy", oyT, 500)
    local mx, my = math.floor(bx + px(59) + ox + 0.5), math.floor(px(64) + oy + 0.5)
    local mw, mh = math.floor(px(350) * z + 0.5), math.floor(px(800) * z + 0.5)
    -- what the light follows: the part under the mouse (or a row's, a loss's), the one on the
    -- table, the parts the thing (or the moodle) under the mouse helps
    local v = self.view
    v.looks = D.looks
    v.hoverPart = self.hoverPart or self.extPart
    v.selectedPart = sel
    v.glow = (self.tileHover and self.tileHover.fit) or (self.moodHover and self.moodHover.parts) or nil
    local ok, err = pcall(Model.update, self.model, player, mx, my, mw, mh, v)
    if not ok and not self.modelErr then
        self.modelErr = true
        print("[Knox] health model: " .. tostring(err))
    end
    self.bodyCx = mx + mw / 2
    -- the part under the mouse (the hit map knows the character from the front only)
    self.hoverPart = nil
    local dir = self.model.knoxDir
    if self.mouseIn and not self.menuOpen and (dir == nil or dir == IsoDirections.S)
            and self.mx >= bx and self.mx < bx + bw and self.my >= 0 and self.my < m.h then
        local s, fx, fy = Model.frame(mx, my, mw, mh)
        local idx = Model.partAt((self.mx - fx) / s, (self.my - fy) / s)
        if idx and not H.missing(player, idx) then
            self.hoverPart = idx
            self.cardPx, self.cardPy = Model.partPoint(idx, s, fx, fy)
        end
    end
end

-- over the model: the line under it (what is on the table) and the hovered part's card
function P:drawBodyOver(m, D)
    local bx, bw = m.bx, m.bw
    local C = T.color
    -- (the line's ground: the panel's colour coming up over the feet)
    local gh = px(56)
    local n = 7
    for i = 0, n - 1 do
        local y0 = m.h - 1 - gh + math.floor(gh * i / n)
        local y1 = m.h - 1 - gh + math.floor(gh * (i + 1) / n)
        local a = math.min(1, (i + 0.5) / n / 0.45)
        T.rect(self, bx + 1, y0, bw - 2, y1 - y0, C.window, a * T.bgAlpha())
    end
    local ly, lh = m.h - px(16) - px(18), px(18)
    local rec = self.sel and self.selRec
    if rec then
        local w1 = T.measure(F.b15, D.tOnTable)
        local w2 = T.measure(F.b15, rec.partLower)
        local x0 = bx + math.floor((bw - w1 - w2) / 2)
        label(self, D.tOnTable, x0, ly, 0, lh, C.dim, F.b15)
        label(self, rec.partLower, x0 + w1, ly, 0, lh, rec.look.c, F.b15)
    else
        label(self, D.tHoverPart, bx, ly, bw, lh, C.dim, F.b15, "centre")
    end
end

function P:drawCard(m, D)
    local idx = self.hoverPart
    local want = idx ~= nil and idx ~= self.sel and not self.rmbMoved
    if want then
        self.cardIdx, self.cardX, self.cardY = idx, self.cardPx, self.cardPy
    end
    local a = self:ease("card", want and 1 or 0, 140)
    idx = self.cardIdx
    if a <= 0.02 or idx == nil or not self.cardX then return end
    local C = T.color
    local rec = D.byIndex[idx]
    local cw = px(372)
    local hgt = rec and (px(54) + px(10) + px(124) + px(6) + px(46) + px(2) + px(40) + 2) or (px(54) + 2)
    local right = self.cardX >= (self.bodyCx or 0) - px(4)
    local x = right and (m.bx + px(432)) or px(42)
    local y = clamp(math.floor(self.cardY - px(70)), px(12), m.h - hgt - px(8))
    local col = rec and rec.look.c or C.accent
    -- the leader line from the part to the card
    local ex, ey = right and x or (x + cw), y + px(27)
    local pxp, pyp = math.floor(self.cardX + 0.5), math.floor(self.cardY + 0.5)
    local lw = math.max(1, math.floor(1.5 * K + 0.5))
    local mid = math.floor(pxp + (ex - pxp) * 0.55 + 0.5)
    T.rect(self, math.min(pxp, mid), pyp, math.abs(mid - pxp) + lw, lw, col, a)
    T.rect(self, mid, math.min(pyp, ey), lw, math.abs(ey - pyp) + lw, col, a)
    T.rect(self, math.min(mid, ex), ey, math.abs(ex - mid) + lw, lw, col, a)
    T.rect(self, pxp - px(4), pyp - px(4), px(8), px(8), C.screen, a)
    frame2(self, pxp - px(4), pyp - px(4), px(8), px(8), col, a)
    T.rect(self, ex - px(3), ey - px(3), px(6), px(6), col, a)
    -- the card
    T.rect(self, x + px(4), y + px(10), cw, hgt, X.black, 0.35 * a)
    T.rect(self, x, y, cw, hgt, C.window, a)
    T.rect(self, x + 1, y + 1, cw - 2, px(54), C.header, a)
    T.rect(self, x + 1, y + 1 + px(54), cw - 2, 1, C.border, a)
    spaced(self, self.partNames[idx] or "", x + px(14), y + px(8), 0, px(22), rec and col or C.bright, F.t20, px(1), "left", a)
    label(self, rec and rec.cardSub or D.tCardNone, x + px(14), y + px(31), 0, px(16), C.dim, F.b14, nil, a)
    label(self, D.tPartHp, x, y + px(13), cw - px(14), px(14), C.dim, F.h13, "right", a)
    label(self, rec and rec.hpText or "100", x, y + px(29), cw - px(14), px(18), C.bright, F.t18, "right", a)
    if rec then
        local py0 = y + 1 + px(54) + px(10)
        self:drawPicture(PIC_CARD, VIEW_MINI, rec, x + px(10), py0, cw - px(20), px(124), a)
        -- its wound's row
        local ry = py0 + px(124) + px(6)
        local qx, qy = x + px(12), ry + px(9)
        T.rect(self, qx, qy, px(28), px(28), C.screen, a)
        frame2(self, qx, qy, px(28), px(28), col, a)
        local done = 0
        for _, s in ipairs(rec.steps) do if s.done then done = done + 1 end end
        local f = rec.look.heal and math.max(0.12, rec.progress or 0) or (#rec.steps > 0 and done / #rec.steps * 0.5 or 0)
        local fh = math.floor(px(18) * f + 0.5)
        if fh > 0 then T.rect(self, qx + px(5), qy + px(28) - px(5) - fh, px(18), fh, col, a) end
        label(self, rec.title, x + px(52), ry + px(5), 0, px(20), C.bright, F.b17, nil, a)
        label(self, rec.look.words, x + px(52), ry + px(25), 0, px(16), col, F.b14, nil, a)
        -- its keys
        local fy = ry + px(46) + px(2)
        T.rect(self, x + 1, fy, cw - 2, 1, C.border, a)
        local kx = T.keyHint(self, x + px(12), fy + px(9), D.tKeyLmb, D.tToTable, px(22), a)
        T.keyHint(self, kx + px(14), fy + px(9), D.tKeyShift, D.tQuickShort, px(22), a)
    end
    T.border(self, x, y, cw, hgt, C.accent, a)
end

-- TABLE ------------------------------------------------------------------------------------------

function P:drawRow(D, r, i, x, y, w, h, clipY0, clipY1)
    local C = T.color
    -- (lit as the mockup's .imp.lit: the row under the mouse or its part under the mouse on the body)
    local lit = (self.hoverPart or self.extPart) == r.index
    T.rect(self, x, y, w, h, lit and X.rowLit or C.cell)
    T.border(self, x, y, w, h, lit and C.accent or C.line)
    self:drawPicture(PIC_ROW + i, VIEW_THUMB, r, x + px(8), y + px(8), px(236), px(86))
    local lx = x + px(262)
    spaced(self, r.partUpper, lx, y + px(12), 0, px(24), C.bright, F.t21, px(0.8), "left")
    label(self, r.row.pw, lx, y + px(40), 0, px(20), r.look.c, F.b16)
    local ny, nh = y + px(68), px(22)
    if r.cur then
        local wx = lx + label(self, D.tNext, lx, ny, 0, nh, C.dim, F.b15) + px(6)
        wx = wx + label(self, r.row.next, wx, ny, 0, nh, C.text, F.b15) + px(6)
        if r.row.item then
            T.itemIcon(self, r.row.item, wx, ny, px(22), 1)
            label(self, r.row.have, wx + px(28), ny, 0, nh, C.dim, F.b15)
        elseif r.row.none then
            label(self, D.tStepNone, wx, ny, 0, nh, C.bad, F.b15)
        end
    else
        label(self, D.tNothingToDo, lx, ny, 0, nh, C.dim, F.b15)
    end
    -- the tag
    local tag = r.look.tagText
    local ls = px(0.9)
    local tw = T.measure(F.t13, tag) + ls * (string.len(tag) - 1) + px(18)
    local tgx = x + w - px(14) - tw
    T.rect(self, tgx, y + px(14), tw, px(24), r.look.c)
    spaced(self, tag, tgx, y + px(14), tw, px(24), C.ink, F.t13, ls)
    if r.look.heal then
        local hx, hy = x + w - px(14) - px(150), y + h - px(34) - px(4)
        T.rect(self, hx, hy, px(150), px(4), X.pip)
        T.rect(self, hx, hy, math.floor(px(150) * math.max(0.03, r.progress or 0) + 0.5), px(4), X.mint)
    end
    label(self, D.tToTableGo, x, y + h - px(12) - px(17), w - px(14), px(17), C.dim, F.h14, "right")
    local hy0, hy1 = math.max(y, clipY0), math.min(y + h, clipY1)
    if hy1 > hy0 then hit(self, "imp", x, hy0, w, hy1 - hy0, r.index) end
end

function P:drawList(m, D)
    local x0, w, h = m.rx, m.rw, m.th
    local C = T.color
    spaced(self, D.tList, x0 + px(16), px(14), 0, px(28), C.bright, F.ptitle, px(1.2), "left")
    label(self, D.tListNote, x0, px(18), w - px(16), px(22), C.dim, F.b15, "right")
    if #D.recs == 0 then
        label(self, D.tNoWounds, x0, math.floor(h * 0.42), w, px(30), C.bright, F.t22, "centre")
        label(self, D.tNoWoundsSub, x0, math.floor(h * 0.42) + px(36), w, px(20), C.dim, F.b15, "centre")
        self.listMax = 0
        return
    end
    local top = px(58)
    local listH = h - top - px(8)
    local pitch, rowH = px(112), px(104)
    self.listMax = math.max(0, #D.recs * pitch - px(8) - listH)
    self.listScroll = clamp(self.listScroll or 0, 0, self.listMax)
    local scroll = math.floor(self:ease("ls", self.listScroll, 120) + 0.5)
    self.listRect1, self.listRect2, self.listRect3, self.listRect4 = x0, top, w, listH
    self:setStencilRect(x0 + 1, top, w - 2, listH)
    for i, r in ipairs(D.recs) do
        local y = top + (i - 1) * pitch - scroll
        if y + rowH > top and y < top + listH then
            self:drawRow(D, r, i, x0 + px(16), y, w - px(32), rowH, top, top + listH)
        end
    end
    self:clearStencilRect()
end

-- a step's slot and its words (the mockup's stepHtml)
function P:drawStep(v, sx, sy, playing, delta, now)
    local C = T.color
    local ss = px(72)
    local x, y = sx + px(22), sy
    local st = v.state
    if playing then
        local p = 0.5 - 0.5 * math.cos(now / 1000 * 2 * math.pi)
        T.rect(self, x - px(5), y - px(5), ss + px(10), ss + px(10), C.accent, 0.22 * p)
    elseif st == "cur" then
        T.rect(self, x - px(4), y - px(4), ss + px(8), ss + px(8), C.accent, 0.10)
    end
    T.rect(self, x, y, ss, ss, st == "done" and X.med or C.cell)
    -- its thing's picture: in colour when done, half when it is next, grey before
    local ix, iy, is = x + px(12), y + px(12), px(48)
    if v.item and st ~= "done" then
        if st == "cur" or st == "none" or st == "free" or playing then
            T.itemIcon(self, v.item, ix, iy, is, 0.6)
        else
            local tex = v.item:getTex()
            local grey = tex and T.greyIcon(tex)
            if grey then self:drawTextureScaledAspect(grey, ix, iy, is, is, 0.28, 1, 1, 1)
            else T.itemIcon(self, v.item, ix, iy, is, 0.28) end
        end
    elseif v.tex then
        if st == "done" then
            self:drawTextureScaledAspect(v.tex, ix, iy, is, is, 1, 1, 1, 1)
        elseif st == "cur" or st == "none" or st == "free" or playing then
            self:drawTextureScaledAspect(v.tex, ix, iy, is, is, 0.6, 1, 1, 1)
        else
            local grey = T.greyIcon(v.tex)
            self:drawTextureScaledAspect(grey or v.tex, ix, iy, is, is, 0.28, 1, 1, 1)
        end
    end
    -- the action's progress, from below
    if delta and delta > 0 then
        local fh = math.floor((ss - px(4)) * math.min(1, delta) + 0.5)
        T.rect(self, x + px(2), y + ss - px(2) - fh, ss - px(4), fh, C.accent, 0.35)
    end
    if playing then frame2(self, x, y, ss, ss, X.now)
    elseif st == "done" then frame2(self, x, y, ss, ss, C.tileFrame)
    elseif st == "cur" then frame2(self, x, y, ss, ss, C.accent)
    elseif st == "none" then frame2(self, x, y, ss, ss, C.bad)
    elseif st == "free" then frame2(self, x, y, ss, ss, C.tileFrame)
    else dashed(self, x, y, ss, ss, C.tileEdge) end
    if st == "done" then
        local cs = px(18)
        -- (the author 2026-11-11: under the mouse a step that can be taken back shows a red cross)
        if v.undo and self.hvKind == "step" and self.hvA == v.i and not playing then
            T.rect(self, x + ss - cs + px(5), y - px(5), cs, cs, C.bad)
            cross(self, x + ss - cs + px(5), y - px(5), cs, C.ink)
        else
            T.rect(self, x + ss - cs + px(5), y - px(5), cs, cs, X.mint)
            tick(self, x + ss - cs + px(5), y - px(5), cs, C.ink)
        end
    end
    local bright = st == "done" or st == "cur" or st == "none" or st == "free" or playing
    label(self, v.name, sx, y + ss + px(9), px(116), px(16), bright and C.bright or C.dim, F.h14, "centre")
    local sub = v.sub
    if playing then sub = self.subPlaying end
    label(self, sub, sx - px(10), y + ss + px(27), px(136), px(17), v.bad and C.bad or C.dim, F.b14, "centre")
end

function P:drawSelected(m, D, rec, player, now)
    local x0, w = m.rx, m.rw
    local C = T.color
    local S = D.sel
    if not S then return end
    local session = G.session(player)
    -- back to the list
    local bx, by, bh = x0 + px(16), px(14), px(30)
    local bw = T.measure(F.h14, D.tBack) + px(20)
    local hot = self.hvKind == "back"
    T.rect(self, bx, by, bw, bh, C.buttonBg)
    T.border(self, bx, by, bw, bh, hot and C.accent or C.tileEdge)
    label(self, D.tBack, bx + px(8), by, 0, bh, hot and C.bright or C.text, F.h14)
    hit(self, "back", bx, by, bw, bh)
    -- the part's name and its health
    spaced(self, rec.partUpper, x0 + px(150), px(10), 0, px(30), rec.look.c, F.t26, px(1.3), "left")
    label(self, S.tsub, x0 + px(150), px(40), 0, px(18), C.dim, F.b15)
    label(self, D.tPartHp, x0, px(14), w - px(18), px(14), C.dim, F.h13, "right")
    local ow = label(self, D.tOfShort, x0, px(31), w - px(18), px(26), C.dim, F.h15, "right")
    label(self, rec.hpText, x0, px(29), w - px(18) - ow, px(26), C.bright, F.t24, "right")
    -- the wound seen from above (the mini-game over it while a step is played)
    local px0, py0, pw, ph = x0 + px(16), px(70), w - px(32), px(348)
    self.picX, self.picY, self.picW, self.picH = px0 + 1, py0 + 1, pw - 2, ph - 2
    self:drawPicture(PIC_TABLE, VIEW_TABLE, rec, px0, py0, pw, ph)
    hit(self, "pic", px0, py0, pw, ph)
    local playingId = session and session.index == rec.index and session.step or nil
    if session and session.games and playingId then self:drawGameHud(S, px0, py0, pw, ph, session) end

    -- the wound: what it is, how it is
    local wy = px(430)
    local ix = x0 + px(16)
    spaced(self, S.wn, ix, wy, 0, px(26), rec.look.c, F.t22, px(0.9), "left")
    local ly = wy + px(30)
    for _, l in ipairs(S.ws) do
        label(self, l, ix, ly, 0, px(20), C.text, F.b16)
        ly = ly + px(20)
    end
    ly = ly + px(10)
    for _, l in ipairs(S.wt) do
        label(self, l, ix, ly, 0, px(19), C.dim, F.b15)
        ly = ly + px(19)
    end
    if rec.look.heal then
        T.rect(self, ix, ly + px(10), px(250), px(4), X.pip)
        T.rect(self, ix, ly + px(10), math.floor(px(250) * math.max(0.03, rec.progress or 0) + 0.5), px(4), X.mint)
    end

    -- the steps, in order (as many as fit; the next one always among them)
    local steps = S.steps
    local n = #steps
    local sx0, sy = ix + px(300), wy + px(2)
    local room = (x0 + w - px(16) - px(230) - px(16)) - sx0
    local fit = math.max(1, math.floor((room + px(22)) / px(138)))
    local first = 1
    if n > fit then
        local curI = n
        for i, v in ipairs(steps) do
            if v.state == "cur" or v.state == "none" then curI = i break end
        end
        first = clamp(curI - 1, 1, n - fit + 1)
    end
    local last = math.min(n, first + fit - 1)
    local delta
    if playingId and session.action and session.action.action then
        local ok, d = pcall(session.action.getJobDelta, session.action)
        delta = ok and d or nil
    end
    if first > 1 then label(self, LSAQUO, sx0 - px(16), sy, px(14), px(72), C.dim, F.h18, "centre") end
    for i = first, last do
        local v = steps[i]
        local sx = sx0 + (i - first) * px(138)
        if i > first then chevron(self, sx - px(22) + px(13), sy + px(36), px(4), C.tileEdge) end
        local playing = playingId == v.id or (v.xid ~= nil and playingId == v.xid)
        self:drawStep(v, sx, sy, playing, playing and delta or nil, now)
        hit(self, "step", sx, sy, px(116), px(120), i)
    end
    if last < n then
        label(self, RSAQUO, sx0 + (last - first + 1) * px(138) - px(22), sy, px(14), px(72), C.dim, F.h18, "centre")
    end

    -- the buttons
    local qx, qy, qw, qh = x0 + w - px(16) - px(230), wy + px(2), px(230), px(44)
    if S.left > 0 then
        local hotQ = self.hvKind == "quick" and not session
        T.rect(self, qx, qy, qw, qh, hotQ and X.mainHot or C.accent, session and 0.5 or 1)
        label(self, D.tQuick, qx, qy, qw, qh, C.ink, F.t16, "centre")
        hit(self, "quick", qx, qy, qw, qh)
    else
        T.rect(self, qx, qy, qw, qh, C.buttonBg)
        T.border(self, qx, qy, qw, qh, C.line)
        label(self, D.tNothing, qx, qy, qw, qh, C.dim, F.h16, "centre")
    end
    local hotM = self.hvKind == "menu"
    T.rect(self, qx, qy + px(52), qw, qh, C.buttonBg)
    T.border(self, qx, qy + px(52), qw, qh, hotM and C.accent or C.tileEdge)
    label(self, D.tAll, qx, qy + px(52), qw, qh, hotM and C.bright or C.text, F.h16, "centre")
    hit(self, "menu", qx, qy + px(52), qw, qh)
    for i, l in ipairs(S.note) do
        label(self, l, x0, qy + px(106) + (i - 1) * px(17), w - px(16), px(17), C.dim, F.b14, "right")
    end
end

-- the mini-game's lines over the picture: how to play, the hand, how far, how long
function P:drawGameHud(S, x, y, w, h, s)
    local C = T.color
    local id = PIC_TABLE
    local stage = knoxWoundGameGet(id, "stage")
    if self.howStage ~= stage or self.howFor ~= s then
        self.howStage, self.howFor = stage, s
        local key = knoxWoundGameHow(id)
        self.howText = key and T.upper(getText("IGUI_KnoxHP_" .. key)) or ""
    end
    label(self, self.howText, x + px(14), y + px(9), 0, px(18), C.bright, F.h15)
    local aw = label(self, S.aid, x, y + px(9), w - px(14), px(18), C.dim, F.b14, "right")
    label(self, S.shake, x, y + px(9), w - px(14) - aw, px(18), S.shakeOn and C.warn or X.mint, F.b14, "right")
    -- the bottom band
    local bh = px(30)
    local by = y + h - bh
    T.rect(self, x + 1, by, w - 2, bh - 1, C.screen, 0.9)
    T.rect(self, x + 1, by, w - 2, 1, C.line)
    local cx = x + px(14)
    cx = cx + label(self, S and self.D.tGameReady or "", cx, by, 0, bh, C.dim, F.h13) + px(10)
    local prog = math.max(0, knoxWoundGameGet(id, "prog"))
    T.rect(self, cx, by + math.floor(bh / 2) - px(2), px(200), px(4), X.pip)
    T.rect(self, cx, by + math.floor(bh / 2) - px(2), math.floor(px(200) * math.min(1, prog) + 0.5), px(4), C.accent)
    cx = cx + px(200) + px(32)
    cx = cx + label(self, self.D.tGameTime, cx, by, 0, bh, C.dim, F.h13) + px(10)
    local t = math.max(0, knoxWoundGameGet(id, "t"))
    local van = math.max(0.5, knoxWoundGameGet(id, "van"))
    T.rect(self, cx, by + math.floor(bh / 2) - px(2), px(200), px(4), X.pip)
    T.rect(self, cx, by + math.floor(bh / 2) - px(2), math.floor(px(200) * math.min(1, t / van) + 0.5), px(4), X.timeBar)
    cx = cx + px(200) + px(10)
    -- (the seconds' words made anew a tenth of a second at a time, not each frame)
    local slips = knoxWoundGameGet(id, "slips")
    local tenth = math.floor(t * 10)
    if self.hudTenth ~= tenth or self.hudSlips ~= slips or self.hudVan ~= van then
        self.hudTenth, self.hudSlips, self.hudVan = tenth, slips, van
        local secs = decimal(string.format("%.1f", tenth / 10))
        local vs = van == math.floor(van) and tostring(math.floor(van)) or decimal(string.format("%.1f", van))
        self.hudText = tx("GameTimeOf", secs, vs) .. (slips > 0 and (DOT .. tx("GameSlips", math.floor(slips))) or "")
    end
    local tw = label(self, self.hudText, cx, by, 0, bh, C.bright, F.h13)
    local idleX = cx + tw + px(16)
    local idleW = x + w - px(14) - idleX
    if idleW > px(60) then
        if self.idleW ~= idleW then
            self.idleW = idleW
            self.idleText = T.fit(self.D.tIdle, F.b13, idleW)
        end
        label(self, self.idleText, idleX, by, idleW, bh, C.dim, F.b13, "right")
    end
end

-- KIT --------------------------------------------------------------------------------------------

local NOW_C = {r = 1, g = 1, b = 1}   -- (the pulsing frame's colour, worked out each frame)

function P:drawTile(t, x, y, s, focusPart, focusMood, now)
    local C = T.color
    local fit, nowFit, unfit = false, false, false
    if focusMood then
        fit = (focusMood.id == "BLEEDING" and t.wrap) or (t.mood ~= nil and (t.mood == focusMood.id
            or (focusMood.id == "STRESS" and t.mood == "PANIC")))
        unfit = not fit
    elseif focusPart then
        fit = t.fit[focusPart] == true
        nowFit = t.now[focusPart] == true
        unfit = not fit
    end
    local a = unfit and 0.3 or 1
    T.rect(self, x, y, s, s, C.cell, a)
    T.border(self, x, y, s, s, C.line, a)
    T.rect(self, x + 1, y + 1, s - 2, s - 2, fit and X.fitBg or X.med, a)
    if fit then T.rect(self, x + px(3), y + px(3), s - px(6), s - px(6), C.accent, 0.12 * a) end
    local fc = C.tileFrame
    if nowFit then
        local p = 0.5 - 0.5 * math.cos(now / 1100 * 2 * math.pi)
        fc = T.mixInto(NOW_C, C.accent, X.now, p)
    elseif fit then
        fc = C.accent
    end
    frame2(self, x + 1, y + 1, s - 2, s - 2, fc, a)
    T.itemIcon(self, t.item, x + px(8), y + px(8), px(48), a)
    if t.bag then T.itemIcon(self, t.bag, x + px(4), y + px(4), px(18), a) end
    if t.countText then
        T.outlinedRight(self, t.countText, x + s - px(6), y + s - px(3) - T.fontH(F.h15), C.bright, F.h15, a)
    end
end

function P:drawKit(m, D, now)
    local x0, y0, w, h = m.rx, m.ky, m.rw, m.kh
    local C = T.color
    panel(self, x0, y0, w, h)
    spaced(self, D.tKit, x0 + px(16), y0 + px(14), 0, px(28), C.bright, F.ptitle, px(1.2), "left")
    label(self, D.tKitNote, x0, y0 + px(18), w - px(16), px(22), C.dim, F.b15, "right")
    if D.kitEmpty then label(self, D.kitEmpty, x0 + px(16), y0 + px(54), 0, px(20), C.dim, F.b15) end
    local focusMood = self.moodHover
    local focusPart = nil
    if not focusMood then
        focusPart = self.hoverPart or self.extPart or self.sel
        if focusPart and not D.byIndex[focusPart] then focusPart = nil end
    end
    local s = px(64)
    for _, gr in ipairs(D.kit) do
        local gx, gy = x0 + px(16 + gr.x), y0 + px(54 + gr.y)
        label(self, gr.title, gx, gy, 0, px(16), C.dim, F.h13)
        for j = 1, gr.n do
            local t = gr.tiles[j]
            local tx_, ty_ = gx + (j - 1) * px(63), gy + px(24)
            self:drawTile(t, tx_, ty_, s, focusPart, focusMood, now)
            hit(self, "kit", tx_, ty_, s, s, t.key, t)
        end
    end
    -- the box beside: the thing under the mouse, or how to treat
    local ix, iy, iw, ih = x0 + px(628), y0 + px(54), w - px(628) - px(16), px(206)
    T.rect(self, ix, iy, iw, ih, C.screen)
    T.border(self, ix, iy, iw, ih, C.line)
    local cx, cy = ix + px(16), iy + px(14)
    local t = self.tileHover
    if t then
        local hn = self:itemHint(t)
        local nw = label(self, hn.name, cx, cy, 0, px(24), C.bright, F.t20)
        if hn.count then label(self, hn.count, cx + nw, cy, 0, px(24), C.dim, F.h18) end
        cy = cy + px(26)
        label(self, hn.where, cx, cy, 0, px(18), C.dim, F.b14)
        cy = cy + px(28)
        for _, l in ipairs(hn.desc) do
            label(self, l, cx, cy, 0, px(21), C.text, F.b16)
            cy = cy + px(21)
        end
        cy = cy + px(10)
        for _, l in ipairs(hn.use) do
            label(self, l, cx, cy, 0, px(20), hn.useC, F.b15)
            cy = cy + px(20)
        end
    else
        spaced(self, D.tHowTitle, cx, cy, 0, px(22), C.dim, F.h15, px(0.6), "left")
        cy = cy + px(30)
        for _, l in ipairs(self.howLines or {}) do
            label(self, l, cx, cy, 0, px(20), C.dim, F.b15)
            cy = cy + px(20)
        end
    end
end

-- The frame ------------------------------------------------------------------------------------

function P:prerender()
    local player = self:player()
    if not player then return end
    -- (a panel made by an older copy of this file, kept over the DEV reloader: its new parts)
    if not self.hitPool then self.hitPool, self.nHits, self.view, self.anim = {}, 0, {}, self.anim or {} end
    local m = self:metrics()
    local now = getTimestampMs()
    self.mx, self.my = self:getMouseX(), self:getMouseY()
    self.mouseIn = self:isMouseOver() or (self.model ~= nil and self.model:isMouseOver())
    local menu = getPlayerContextMenu(self.playerNum)
    self.menuOpen = menu ~= nil and menu:isAnyVisible()
    -- what is under the mouse (by last frame's places; kept while a menu is open)
    if not self.menuOpen then
        local h = self.mouseIn and hitAt(self, self.mx, self.my) or nil
        if h then self.hvKind, self.hvA, self.hvB = h.kind, h.a, h.b
        else self.hvKind, self.hvA, self.hvB = nil, nil, nil end
    end
    self.nHits = 0
    -- the step being played: its frame (the mouse on the picture, its button)
    local s = G.session(player)
    if s then
        local dt = math.min(0.1, math.max(0, (now - (self.tickMs or now)) / 1000))
        local down = self.gameDown == true and isMouseButtonDown(0)
        G.tick(player, self.mx - (self.picX or 0), self.my - (self.picY or 0), down, self.gamePressed == true, dt)
        self.gamePressed = false
    end
    self.tickMs = now
    -- the character turned by the right button held on the body
    if self.rmbOn then
        if isMouseButtonDown(1) and self.model then
            local steps = math.floor((self.mx - self.rmbX) / px(ROT_PX) + 0.5)
            if steps ~= 0 then self.rmbMoved = true end
            local i = ((self.rmbDir - 1 + steps) % 8) + 1
            if self.rmbI ~= i then
                self.rmbI = i
                self.model.knoxDir = DIRS[i] ~= IsoDirections.S and DIRS[i] or nil
                self.model:setDirection(DIRS[i])
            end
        else
            self.rmbOn = nil
        end
    end
    local D = self:refresh(player)
    -- what the mouse is on, as the panels light it
    local kind = self.hvKind
    self.extPart = (kind == "imp" or kind == "loss") and self.hvA or nil
    self.lossPart = kind == "loss" and self.hvA or nil
    self.moodHover = kind == "mood" and D.moods[self.hvA] or nil
    self.tileHover = kind == "kit" and self.hvB or nil
    local sub = (s and s.games) and D.tPlaying or D.tDoing
    self.subPlaying = sub

    self:drawState(m, D)
    self:drawBody(m, D, player)
    panel(self, m.rx, 0, m.rw, m.th)
    local rec = self.sel and self.selRec
    if rec then self:drawSelected(m, D, rec, player, now) else self:drawList(m, D) end
    self:drawKit(m, D, now)
end

function P:render()
    local m, D = self.m, self.D
    if not (m and D and self:player()) then return end
    self:drawBodyOver(m, D)
    self:drawCard(m, D)
end

-- Doing ------------------------------------------------------------------------------------------

--- Puts a part on the table (nil: none; one with nothing wrong: none either).
function P:select(index)
    local rec = index and self.D and self.D.byIndex[index] or nil
    local was = self.sel
    self.sel = rec and index or nil
    self.selRec = rec
    self.dirty = true
    if self.sel ~= was then getSoundManager():playUISound("UIActivateButton") end
end

--- A step of the part on the table, started (its mini-game with it).
function P:doStep(player, i, prefer)
    local rec = self.selRec
    local s = rec and rec.steps[i]
    if not s or s.skipped then return end
    if s.done then
        -- (the author 2026-11-11: a done step clicked is taken back - the bandage comes off)
        -- (the author 2026-11-11: with its mini-game too, as every step)
        if not Care.undoable(rec.bp, s.id) then return end
        if G.start(self, player, rec, "x" .. s.id, nil) then
            if s.id == "stitch" then W.forgetStitch(player, rec.index) end
            self.dirty = true
        end
        return
    end
    if not Care.stepCan(Care.reachable(player), rec.bp, s.id) then return end
    if G.start(self, player, rec, s.id, prefer) then self.dirty = true end
end

--- The quick treatment of a part: its steps one after another, each with its mini-game.
function P:quick(player, index)
    if G.session(player) then return end
    local bps = player:getBodyDamage():getBodyParts()
    local bp = bps:get(index)
    local rec = W.record(player, index, bp)
    if not (rec and rec.cur) then return end
    if not Care.stepCan(Care.reachable(player), bp, rec.cur.id) then
        if HaloTextHelper and HaloTextHelper.addBadText then HaloTextHelper.addBadText(player, tx("NothingToQuick")) end
        return
    end
    local panel = self
    G.start(self, player, rec, rec.cur.id, nil, function()
        local p = panel:player()
        if p then panel:quick(p, index) end
    end)
    self.dirty = true
end

--- A step over (KnoxHealthGames): the tab reads anew.
function P:stepOver(s, done)
    self.dirty = true
    self.gameDown = false
end

--- Esc: the step being played stops; else the part goes off the table. False: nothing to do here.
function P:escape()
    local player = self:player()
    if player and G.cancel(player) then
        self.dirty = true
        return true
    end
    if self.sel then
        self:select(nil)
        return true
    end
    return false
end

-- a click on the kit's thing: the step of the part on the table with it; twice on a pill: taken
function P:kitClick(player, t)
    local now = getTimestampMs()
    if t.whole then
        if self.lastKit == t.key and now - (self.lastKitMs or 0) < DBL_MS then
            self.lastKit = nil
            Care.take(player, t.item)
            self.dirty = true
            getSoundManager():playUISound("UIActivateButton")
        else
            self.lastKit, self.lastKitMs = t.key, now
        end
        return
    end
    self.lastKit = nil
    local rec = self.selRec
    if not (self.sel and rec) then return end
    local pick
    for i, s in ipairs(rec.steps) do
        if not s.done and not s.skipped and W.stepTakes(s.id, t.item) then
            if s == rec.cur then pick = i break end
            pick = pick or i
        end
    end
    if pick then self:doStep(player, pick, t.g.items[1] or t.item) end
end

-- The bottom bar's hints (KnoxScreen.drawHints) ------------------------------------------------

function P:hintsStamp()
    local player = self:player()
    return (player and G.session(player)) and "health+esc" or "health"
end

function P:hints()
    local list = {
        {key = tx("KeyLmb"), label = tx("HintTable")},
        {key = tx("KeyShiftLmb"), label = tx("QuickShort")},
        {key = tx("KeyRmb"), label = tx("HintActions")},
        {key = tx("KeyRmbDrag"), label = tx("HintRotate")},
    }
    local player = self:player()
    if player and G.session(player) then table.insert(list, {key = tx("KeyEsc"), label = tx("HintCancel")}) end
    return list
end

-- The mouse ------------------------------------------------------------------------------------

function P:onMouseDown(x, y)
    local h = hitAt(self, x, y)
    self.pressKind, self.pressA = h and h.kind or nil, h and h.a or nil
    self.pressPart = self.hoverPart
    self.pressBody = self.m ~= nil and x >= self.m.bx and x < self.m.bx + self.m.bw
    local player = self:player()
    if player and G.session(player) and h and h.kind == "pic" then
        self.gameDown, self.gamePressed = true, true
    end
    return true
end

function P:onMouseUpOutside(x, y)
    self.pressKind = nil
    self.gameDown = false
end

function P:onMouseUp(x, y)
    self.gameDown = false
    local player = self:player()
    local kind, a = self.pressKind, self.pressA
    self.pressKind = nil
    if not (player and self.D) then return true end
    local h = hitAt(self, x, y)
    local session = G.session(player)
    if kind and h and h.kind == kind and h.a == a then
        if kind == "back" then
            if session then G.cancel(player) end
            self:select(nil)
        elseif session then
            -- (a step going: the rest of the tab waits)
            return true
        elseif kind == "imp" then
            if isShiftKeyDown() then
                self:select(a)
                self:quick(player, a)
            else
                self:select(a)
            end
        elseif kind == "step" then
            self:doStep(player, a)
        elseif kind == "quick" and self.sel then
            self:quick(player, self.sel)
        elseif kind == "menu" and self.selRec then
            Care.openMenu(player, self.selRec.bp, getMouseX(), getMouseY(), nil)
        elseif kind == "kit" then
            self:kitClick(player, h.b)
        end
        return true
    end
    if kind or h or session then return true end
    -- on the body: a part to the table (with Shift: treated at once), beside it: none
    if self.pressBody then
        local part = self.hoverPart
        if part and part == self.pressPart then
            if isShiftKeyDown() and self.D.byIndex[part] then
                self:select(part)
                self:quick(player, part)
            else
                self:select(part)
            end
        elseif not part and not self.pressPart then
            self:select(nil)
        end
    end
    return true
end

function P:onRightMouseDown(x, y)
    local m = self.m
    self.rmbOn, self.rmbMoved = nil, false
    if m and x >= m.bx and x < m.bx + m.bw and not hitAt(self, x, y) and self.model then
        local d = self.model.knoxDir or IsoDirections.S
        local di = 1
        for i, v in ipairs(DIRS) do if v == d then di = i break end end
        self.rmbOn, self.rmbX, self.rmbDir, self.rmbI = true, x, di, di
    end
    return true
end

function P:onRightMouseUp(x, y)
    local moved = self.rmbMoved
    self.rmbOn, self.rmbMoved = nil, false
    if moved then return true end
    local player = self:player()
    if not (player and self.D) then return true end
    local h = hitAt(self, x, y)
    local k = h and h.kind
    local bps = player:getBodyDamage():getBodyParts()
    if k == "kit" then
        local item = h.b.g.items[1] or h.b.item
        if KnoxContextMenu and KnoxContextMenu.setTarget then KnoxContextMenu.setTarget({item}, self.playerNum) end
        ISInventoryPaneContextMenu.createMenu(self.playerNum, true, {item}, getMouseX(), getMouseY())
    elseif k == "imp" or k == "loss" then
        Care.openMenu(player, bps:get(h.a), getMouseX(), getMouseY(), nil)
    elseif (k == "pic" or k == "step" or k == "quick" or k == "menu") and self.selRec then
        Care.openMenu(player, self.selRec.bp, getMouseX(), getMouseY(), nil)
    elseif not k and self.hoverPart then
        Care.openMenu(player, bps:get(self.hoverPart), getMouseX(), getMouseY(), nil)
    end
    return true
end

function P:onMouseWheel(del)
    local m = self.m
    if not (m and not self.sel and (self.listMax or 0) > 0) then return true end
    local x, y = self:getMouseX(), self:getMouseY()
    if x >= m.rx and y < m.th then
        self.listScroll = clamp((self.listScroll or 0) + del * px(56), 0, self.listMax)
    end
    return true
end

-- The health key ----------------------------------------------------------------------------
-- The game's health window (its key, its other ways there) opens the Knox screen on
-- this tab instead; again on it, the screen closes. Not with a gamepad, in split
-- screen, in the tutorial, nor with the module or the inventory screen off
-- (Knox.forPlayer): there it stays the game's.

--- The Knox screen on the Health tab (closed when it already is).
function KnoxHealthPanel.openTab(playerNum)
    local s = KnoxScreen.instance
    if s and s.tab == "Health" then
        s:close()
        return
    end
    if not s then
        Knox.open(playerNum)
        s = KnoxScreen.instance
    end
    if s then s:setTab("Health") end
end

require "XpSystem/ISUI/ISCharacterInfoWindow"
if ISCharacterInfoWindow and not ISCharacterInfoWindow.knoxHealthHooked then
    ISCharacterInfoWindow.knoxHealthHooked = true
    local toggleView = ISCharacterInfoWindow.toggleView
    function ISCharacterInfoWindow:toggleView(view)
        local n = self.playerNum or 0
        if view == xpSystemText.health and Knox and Knox.forPlayer and Knox.forPlayer(n, "health")
                and Knox.forPlayer(n, "inventory") then
            local ok, err = pcall(KnoxHealthPanel.openTab, n)
            if ok then return end
            print("[Knox] health tab: " .. tostring(err))
        end
        return toggleView(self, view)
    end
end

return KnoxHealthPanel
