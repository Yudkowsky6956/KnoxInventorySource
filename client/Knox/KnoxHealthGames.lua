-- The health tab's steps as they go (the author's mockup health_v3, 2026-11-10: "a mini-game for
-- every treatment, its result changes only the speed"). A step is the game's own timed action
-- (KnoxHealthCare.doStep); while it runs, its mini-game is played on the wound's picture on the
-- table (Java KnoxWoundGame on the table's canvas):
--   * played well, the action ends at once (forceComplete) - sooner than its normal time; not
--     played, the character finishes in that time by itself (the game's own action timer);
--   * the normal time with the mini-games on: the mockup's (VAN), a little shorter with every
--     level of First Aid, as the game's own times are; off - the game's own time, no mini-game;
--   * moodles shake the hand (pain .9, stress and panic .5 a level - the mockup's tremor),
--     First Aid widens the targets (KnoxWoundGame.tolK);
--   * in a game with others the server keeps the action's time: no stretching, no early end -
--     the mini-game is only played along (and ends with the action);
--   * Esc stops the action (and the game); a click elsewhere on the tab does nothing meanwhile.
-- A quick treatment is the steps one after another (the mockup's quick(pid)).

require "Knox/KnoxTheme"
require "Knox/KnoxHealthCare"
require "Knox/KnoxHealthWounds"

KnoxHealthGames = KnoxHealthGames or {}
local G = KnoxHealthGames
local T = KnoxTheme
local Care = KnoxHealthCare
local W = KnoxHealthWounds

G.CANVAS = 1          -- the table's picture (KnoxWoundCanvas id)
G.TICKS_A_SECOND = 60 -- a timed action's ticks at 1x
G.SKILL_K = 0.03      -- a level of First Aid takes this much off the normal time (the game: 4 of 120)

-- (the session of each player's tab, kept over a reload of this file)
G.cur = G.cur or {}

--- Are the mini-games on (the module's setting, Java there, not on a Mac)?
function G.on()
    return T.switch("health.games") and knoxWoundGameStart ~= nil and (knoxWoundOk == nil or knoxWoundOk())
end

local function current(player)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    return q and q.queue and q.queue[1] or nil
end

local function queued(player, action)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    if not (q and q.queue) then return false end
    for _, a in ipairs(q.queue) do
        if a == action then return true end
    end
    return false
end

-- the hand's tremor from the moodles (the mockup's tremor()): its strength and the moodles' names
local SHAKE = {PAIN = 0.9, STRESS = 0.5, PANIC = 0.5}
function G.tremor(player, names)
    local m = player:getMoodles()
    local a = 0
    for id, k in pairs(SHAKE) do
        local t = MoodleType[id]
        local ok, lvl = pcall(m.getMoodleLevel, m, t)
        if ok and lvl and lvl > 0 then
            a = a + k * lvl
            if names then names[#names + 1] = string.lower(m:getMoodleDisplayString(t)) end
        end
    end
    return a
end

-- the mockup's item names for its games (a suture needle: fewer stitches, a rag: more turns)
local function gameItem(item)
    if not item then return "" end
    local t = item:getType() or ""
    if t == "SutureNeedle" then return "suture" end
    if t == "RippedSheets" or t == "AlcoholRippedSheets" or string.find(t, "Strips") then return "rag" end
    return ""
end

--- Starts a step of the part's record: its action, and its mini-game with the games on. Returns
--- true when it started. then: what to do once it is over (the quick treatment's next step).
function G.start(panel, player, rec, stepId, prefer, then_)
    if G.cur[player] then return false end
    local action = Care.doStep(player, rec.bp, stepId, prefer)
    if not action then return false end
    local kindN = rec.kindN
    if stepId == "xsplint" then
        W.force[player] = {index = rec.index, kind = "fracture"}
        kindN = W.KIND.fracture
    end
    local s = {player = player, index = rec.index, step = stepId, action = action, then_ = then_,
               panel = panel, ms = getTimestampMs(), item = action.item}
    s.mp = isClient() == true
    s.games = G.on()
    local lvl = player:getPerkLevel(Perks.Doctor)
    s.skill = lvl
    if s.games then
        s.van = (W.VAN[stepId] or 10) * math.max(0.5, 1 - G.SKILL_K * lvl)
        local cleaned = (math.floor(rec.flags / 16) % 2) == 1
        -- (a bandage taken back is a clean one: the bandage-off game draws it so)
        local item = stepId == "xbandage" and "band" or gameItem(prefer or action.item)
        local ok = pcall(knoxWoundGameStart, G.CANVAS, W.GAME[stepId] or 0, kindN, cleaned, item, lvl, s.van)
        s.games = ok
    end
    G.cur[player] = s
    getSoundManager():playUISound("UIActivateButton")
    return true
end

--- The session of the player's tab now (nil: no step going).
function G.session(player)
    return G.cur[player]
end

local function finish(s, done)
    G.cur[s.player] = nil
    W.force[s.player] = nil
    if s.games then pcall(knoxWoundGameStop, G.CANVAS) end
    if s.panel and s.panel.stepOver then s.panel:stepOver(s, done) end
end

--- Esc: the action stopped, the game with it.
function G.cancel(player)
    local s = G.cur[player]
    if not s then return false end
    if queued(player, s.action) then ISTimedActionQueue.clear(player) end
    s.then_ = nil
    finish(s, false)
    return true
end

--- Every frame of the tab while a step goes: the action's time, the game's input, the end.
--- mx, my: the mouse on the picture (its pixels), down / pressed: the left button.
function G.tick(player, mx, my, down, pressed, dt)
    local s = G.cur[player]
    if not s then return end
    local a = s.action
    local cur = current(player)
    local running = cur == a and a.action ~= nil
    if running and not s.timed then
        -- the action has begun: its normal time set (the mini-games on, alone in the game)
        s.timed = true
        local own = a.maxTime or 0
        s.ownTicks = own
        if s.games and not s.mp and s.van and knoxActionMaxTime then
            local ticks = math.max(1, math.floor(s.van * G.TICKS_A_SECOND + 0.5))
            a.maxTime = ticks
            pcall(knoxActionMaxTime, a.action, ticks)
        elseif s.games then
            -- (in a game with others: the game's own time is the normal one)
            pcall(knoxWoundGameVan, G.CANVAS, math.max(0.5, own / G.TICKS_A_SECOND))
        end
    end
    if s.games then
        local shake = G.tremor(player)
        pcall(knoxWoundGameTick, G.CANVAS, mx or -1000, my or -1000, down == true, pressed == true, dt or 0, shake)
        -- played to the end: the action done now (alone in the game)
        if running and not s.forced and knoxWoundGameGet(G.CANVAS, "won") == 1 then
            s.forced = true
            if not s.mp then pcall(function() a:forceComplete() end) end
        end
    end
    if not s.gone and not queued(player, a) then
        -- the action is over: done (its step is), or stopped by something else
        s.gone = true
        s.goneMs = getTimestampMs()
        if s.games and knoxWoundGameGet(G.CANVAS, "end") ~= 1 then pcall(knoxWoundGameAuto, G.CANVAS) end
    end
    if s.gone then
        -- (the game's box shows how it went for a moment; without the games: at once)
        local over = not s.games or knoxWoundGameGet(G.CANVAS, "done") == 1
            or getTimestampMs() - s.goneMs > 2500
        if over then
            local rec = W.record(player, s.index, player:getBodyDamage():getBodyParts():get(s.index))
            local done = rec == nil
            if rec then
                for _, st in ipairs(rec.steps) do
                    if st.id == s.step then done = st.done break end
                end
            end
            local then_ = s.then_
            finish(s, done)
            if done and then_ then then_() end
        end
    end
end

return KnoxHealthGames
