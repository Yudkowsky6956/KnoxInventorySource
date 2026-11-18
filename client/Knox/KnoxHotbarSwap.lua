-- Swapping through a hotbar slot (the author 2026-11-14: "as in the mod Swap It"): a thing on
-- the back (an axe) and a thing in the hands (a shotgun); the back's hotbar key takes the axe
-- into the hands, as ever, and the shotgun goes onto the back in its place - the same key
-- again swaps them back. Only when what is held fits that slot and has no slot of its own on
-- the hotbar (then the game puts it back there itself). The game's own actions, in its queue:
-- its equip of the slot's thing, then its attach of the held one to the slot just freed.

require "Hotbar/ISHotbar"

KnoxHotbarSwap = KnoxHotbarSwap or {}
local S = KnoxHotbarSwap

--- What the hands hold that goes to slot `index` when its thing is taken: the thing, the
--- slot's attachment name for it; nil when nothing is to be swapped.
function S.swapOf(hb, index)
    -- (the mod Swap It on as well: it swaps by itself - two swaps queued at once put the held
    -- thing on the back twice; the author's game 2026-11-14. Knox steps aside for it)
    if S.swapItOn == nil then S.swapItOn = getActivatedMods():contains("SwapIt") end
    if S.swapItOn then return nil end
    local item = hb.attachedItems and hb.attachedItems[index]
    local chr = hb.chr
    if not item or not chr then return nil end
    -- (a lamp, a radio on the belt: the key switches it on and off, nothing is taken)
    if item:canBeActivated() and not instanceof(item, "HandWeapon") then return nil end
    -- (the main hand's thing: what the left hand holds alone - a torch - stays there)
    local held = chr:getPrimaryHandItem()
    if not held or held == item then return nil end
    if chr:getSecondaryHandItem() == item then return nil end
    if hb:isInHotbar(held) then return nil end   -- (it goes back to its own slot: the game's way)
    if isForceDropHeavyItem and isForceDropHeavyItem(held) then return nil end   -- (a corpse, a generator)
    if held:getContainer() ~= chr:getInventory() then return nil end
    local slot = hb.availableSlot and hb.availableSlot[index]
    local kind = held:getAttachmentType()
    if not slot or not kind or not hb:canBeAttached(slot, held) then return nil end
    local name = slot.def.attachments[kind]
    if not name then return nil end
    return held, name, slot.def
end

--- A thing held in both hands that goes back into the bag when another slot's thing is taken
--- (no slot of its own, not swapped): it leaves the hands at once, no action to wait for (the
--- author 2026-11-14: "убиралась сразу в рюкзак а не тратила время"); nil otherwise.
function S.dropOf(hb, index)
    local item = hb.attachedItems and hb.attachedItems[index]
    local chr = hb.chr
    if not item or not chr then return nil end
    if item:canBeActivated() and not instanceof(item, "HandWeapon") then return nil end
    local held = chr:getPrimaryHandItem()
    if not held or held == item or held ~= chr:getSecondaryHandItem() then return nil end
    if hb:isInHotbar(held) then return nil end
    if isForceDropHeavyItem and isForceDropHeavyItem(held) then return nil end
    if held:getContainer() ~= chr:getInventory() then return nil end
    -- (it fits the slot: a swap hangs it there - Knox's or Swap It's - not into the bag)
    local slot = hb.availableSlot and hb.availableSlot[index]
    local kind = held:getAttachmentType()
    if slot and kind and hb:canBeAttached(slot, held) then return nil end
    return held
end

--- Out of both hands now, as the game's unequip ends (ISUnequipAction:complete).
local function emptyHands(chr, held)
    if instanceof(held, "HandWeapon") and held:canBeActivated() then held:setActivated(false) end
    chr:setPrimaryHandItem(nil)
    chr:setSecondaryHandItem(nil)
    if sendEquip then sendEquip(chr) end
    -- (its bag, if it has one to go back to: at once too - the author 2026-11-14)
    if KnoxHome and KnoxHome.fast then KnoxHome.fast[held] = true end
    triggerEvent("OnClothingUpdated", chr)
    ISInventoryPage.renderDirty = true
end

--- Hung on the slot at once when its action is called off (the author 2026-11-14: the rifle
--- and the bat - the right button held to aim just after the key, the aim stops the game's
--- hanging and the rifle stayed in the pockets). As the game's own end of it
--- (ISAttachItemHotbar:perform), with no animation.
local function hangNow(hb, w)
    local chr, item, index = w.chr, w.item, w.index
    if item:getAttachedSlot() == index then return end
    if item:getContainer() ~= chr:getInventory() then return end
    if chr:getPrimaryHandItem() == item or chr:getSecondaryHandItem() == item then return end
    local was = hb.attachedItems[index]
    -- (taken by something else meanwhile - not the thing it swapped with, now in the hands)
    if was and was ~= chr:getPrimaryHandItem() and was ~= chr:getSecondaryHandItem() then return end
    if was then
        chr:removeAttachedItem(was)
        was:setAttachedSlot(-1)
        was:setAttachedSlotType(nil)
        was:setAttachedToModel(nil)
    end
    hb:attachItem(item, w.name, index, w.def, false)
    if syncItemFields then syncItemFields(chr, item) end
    ISInventoryPage.renderDirty = true
end

S.watch = S.watch or {}
local watchTick
watchTick = function()
    local now = getTimestampMs()
    for i = #S.watch, 1, -1 do
        local w = S.watch[i]
        local q = ISTimedActionQueue.queues and ISTimedActionQueue.queues[w.chr]
        local queued = false
        for _, a in ipairs(q and q.queue or {}) do
            if a == w.action then queued = true break end
        end
        if not queued or now > w.untilMs then
            table.remove(S.watch, i)
            if not queued then
                local hb = getPlayerHotbar(w.chr:getPlayerNum())
                if hb then pcall(hangNow, hb, w) end
            end
        end
    end
    if #S.watch == 0 then Events.OnTick.Remove(watchTick) end
end

--- The game's hanging, queued and watched: called off - by the aim, a run - hung at once.
function S.queueAttach(chr, item, name, index, def)
    local a = ISAttachItemHotbar:new(chr, item, name, index, def)
    ISTimedActionQueue.add(a)
    if #S.watch == 0 then Events.OnTick.Add(watchTick) end
    table.insert(S.watch, {chr = chr, item = item, name = name, index = index, def = def, action = a,
        untilMs = getTimestampMs() + 15000})
end

--- Another slot's key with a thing in both hands that fits a slot of the hotbar - a shotgun,
--- the back (the author 2026-11-14: "класть оружие из рук за спину и только потом
--- переключаться"; the back taken by an axe - "дробовик на спину, топор в сумку"): the slot
--- it hangs in, its attachment name and def; the free one first, else the taken one.
function S.hangOf(hb, index)
    local held = S.dropOf(hb, index)
    if not held then return nil end
    local kind = held:getAttachmentType()
    if not kind or not hb.availableSlot then return nil end
    local best
    for i, slot in pairs(hb.availableSlot) do
        if i ~= index and slot.def and slot.def.attachments[kind] and hb:canBeAttached(slot, held) then
            if not hb.attachedItems[i] then return held, i, slot.def.attachments[kind], slot.def end
            best = best or i
        end
    end
    if not best then return nil end
    local def = hb.availableSlot[best].def
    return held, best, def.attachments[kind], def
end

--- The game's own actions: the thing to its slot (it leaves the hands as it hangs), what was
--- there into the bag at once, then the pressed key's own taking.
local function hang(hb, held, at, name, def)
    local chr = hb.chr
    local was = hb.attachedItems[at]
    S.queueAttach(chr, held, name, at, def)
    local bag = KnoxActions and KnoxActions.activeBag and KnoxActions.activeBag(chr)
    if was and bag and bag ~= chr:getInventory() then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(chr, was, chr:getInventory(), bag, 1))
    end
    -- (the set kept: the back's key takes the shotgun and hangs the axe there again)
    if was then S.memo = { chr = chr, item = was, at = at, gun = held } end
end

--- The set back on the back's key (the author 2026-11-14: "персонаж снимает со спины
--- дробовик, а на его место вешает топор"): the thing put away to hang there again; nil when
--- the set is gone (the axe dropped or hung elsewhere, the shotgun off the back, the hands
--- holding a thing of no slot). Other keys between keep it.
function S.backOf(hb, index)
    local m = S.memo
    local chr = hb.chr
    if not m or m.chr ~= chr then return nil end
    local item = m.item
    local p, q = chr:getPrimaryHandItem(), chr:getSecondaryHandItem()
    if hb.attachedItems[m.at] ~= m.gun or p == item or q == item or hb:isInHotbar(item)
            or item:getOutermostContainer() ~= chr:getInventory()
            or (p and not hb:isInHotbar(p)) or (q and not hb:isInHotbar(q)) then
        S.memo = nil
        return nil
    end
    if index ~= m.at then return nil end
    local slot = hb.availableSlot[index]
    local kind = item:getAttachmentType()
    local name = slot and kind and slot.def.attachments[kind]
    S.memo = nil
    if not name then return nil end
    return item, name, slot.def
end

--- The hotbar key's work: the held thing hung on its slot, the swap or the hands emptied,
--- then the game's own taking.
function S.activate(hb, index, activate)
    local okB, bItem, bName, bDef = pcall(S.backOf, hb, index)
    if not okB then S.memo = nil end
    if okB and bItem then
        activate(hb, index)
        -- (out of the bag at once, no progress bar: the author 2026-11-14 - too long)
        local from = bItem:getContainer()
        if from and from ~= hb.chr:getInventory() then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(hb.chr, bItem, from, hb.chr:getInventory(), 1))
        end
        S.queueAttach(hb.chr, bItem, bName, index, bDef)
        return
    end
    local okH, hHeld, hAt, hName, hDef = pcall(S.hangOf, hb, index)
    if okH and hHeld and pcall(hang, hb, hHeld, hAt, hName, hDef) then
        activate(hb, index)
        return
    end
    local ok, held, name, def = pcall(S.swapOf, hb, index)
    if not (ok and held) then
        local ok2, drop = pcall(S.dropOf, hb, index)
        if ok2 and drop then pcall(emptyHands, hb.chr, drop) end
    end
    activate(hb, index)
    if ok and held then
        -- (after the equip: the hands give it up into the bag, then it hangs in the freed slot)
        S.queueAttach(hb.chr, held, name, index, def)
    end
end

-- (the game's function kept once; the wrapper only calls S.activate, so a file run again -
-- the DEV reloader - takes effect at once)
ISHotbar.knoxSwapOrig = ISHotbar.knoxSwapOrig or ISHotbar.activateSlot
function ISHotbar:activateSlot(index)
    return S.activate(self, index, ISHotbar.knoxSwapOrig)
end

return KnoxHotbarSwap
