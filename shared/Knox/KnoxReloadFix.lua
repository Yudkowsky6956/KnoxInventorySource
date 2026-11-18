-- The game's own bug in loading a gun (the author 2026-11-14: loading the double-barrel from
-- the R menu - errors every frame until Esc). ISReloadWeaponAction.setReloadSpeed reads the ammo
-- strap's name when nothing is worn there: a shoulder holster (worn, its tag
-- RELOAD_FAST_MAGAZINES) and a gun of shells or rounds, no ammo strap - "getClothingItemName of
-- non-table". The action's setup stops there, its count of rounds is never set, and each frame
-- after fails on it ("__sub not defined"). The game's R key the same. Here: with no ammo strap
-- worn the speed is set by Knox, the game's own lines without the strap's read (a failure
-- caught by pcall still lands in the game's error list, so it is not let happen).

require "TimedActions/ISReloadWeaponAction"

KnoxReloadFix = KnoxReloadFix or {}
local F = KnoxReloadFix

--- The game's speed with no ammo strap worn (its own lines, ISReloadWeaponAction.lua).
function F.speed(character, rack)
    local s = 0.8
    if rack then
        s = s + character:getPerkLevel(Perks.Reloading) * 0.04
    else
        s = s + character:getPerkLevel(Perks.Reloading) * 0.10
        s = s - character:getMoodles():getMoodleLevel(MoodleType.PANIC) * 0.05
    end
    local gun = character:getPrimaryHandItem()
    -- (the game looks only with a fast tag in the hands or a magazine one worn - kept so)
    local reloadFast = character:hasEquippedTag(ItemTag.RELOAD_FAST_SHELLS)
        or character:hasEquippedTag(ItemTag.RELOAD_FAST_BULLETS)
        or character:hasEquippedTag(ItemTag.RELOAD_FAST_MAGAZINES)
    if gun and (reloadFast or character:hasWornTag(ItemTag.RELOAD_FAST_MAGAZINES)) then
        local function has(tag) return character:hasEquippedTag(tag) or character:hasWornTag(tag) end
        local fast
        if gun:getAmmoType() == AmmoType.SHOTGUN_SHELLS then
            fast = has(ItemTag.RELOAD_FAST_SHELLS)
        elseif gun:getMagazineType() then
            fast = has(ItemTag.RELOAD_FAST_MAGAZINES)
        else
            fast = has(ItemTag.RELOAD_FAST_BULLETS)
        end
        if fast then s = s * 1.15 end
    end
    if character:getVehicle() and character:getVehicle():getDriver() == character then
        s = s * 0.8
    end
    character:setVariable("ReloadSpeed", s)
end

-- (the game's function kept once - the DEV reloader runs the file again)
ISReloadWeaponAction.knoxSpeedOrig = ISReloadWeaponAction.knoxSpeedOrig or ISReloadWeaponAction.setReloadSpeed
function ISReloadWeaponAction.setReloadSpeed(character, rack)
    if character and not character:getWornItem(ItemBodyLocation.AMMO_STRAP) then
        return F.speed(character, rack)
    end
    return ISReloadWeaponAction.knoxSpeedOrig(character, rack)
end

return KnoxReloadFix
