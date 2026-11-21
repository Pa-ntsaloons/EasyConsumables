-- EasyConsumables: cooldown swipes on action buttons that hold EC macros.
--
-- Potions and Healthstones have a real item cooldown, which the game usually shows on a macro
-- button already; this makes sure it does. Bandages have no item cooldown: the 60 sec wait
-- is the "Recently Bandaged" debuff, so the game never shows it. We draw it ourselves.
--
-- This only touches the cooldown animation (display only, fine in combat). It covers
-- Blizzard's action bars; other bar addons draw their own buttons.

local _, ns = ...
local EC = ns.EC

local RECENTLY_BANDAGED = 11196
local GCD_MAX = 1.6 -- ignore anything this short (the global cooldown)

-- Which pick's cooldown to show for each macro.
local SOURCE = {
    bandage = "bandage",
    health = "health",
    mana = "mana",
    combo = "health",   -- in-combat side is the health potion
    comboMP = "mana",
}

local GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown

local function ItemCooldown(itemID)
    if not GetItemCooldown then return 0, 0 end
    local start, duration = GetItemCooldown(itemID)
    return start or 0, duration or 0
end

local bandagedName -- localized "Recently Bandaged", in case the client uses a different spell ID

local function IsBandagedAura(name, spellID)
    if spellID == RECENTLY_BANDAGED then return true end
    if not bandagedName then bandagedName = ns.Compat.GetSpellName(RECENTLY_BANDAGED) or "Recently Bandaged" end
    return name == bandagedName
end

local function BandageDebuff()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local a = C_UnitAuras.GetPlayerAuraBySpellID(RECENTLY_BANDAGED)
        if a and a.duration and a.duration > 0 and a.expirationTime then return a.expirationTime - a.duration, a.duration end
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
            if not a then break end
            if IsBandagedAura(a.name, a.spellId) and a.duration and a.expirationTime then
                return a.expirationTime - a.duration, a.duration
            end
        end
    elseif UnitDebuff then
        for i = 1, 40 do
            local name, _, _, _, duration, expires, _, _, _, spellID = UnitDebuff("player", i)
            if not name then break end
            if IsBandagedAura(name, spellID) and duration and expires then return expires - duration, duration end
        end
    end
    return 0, 0
end

local function Wanted(key)
    local src = SOURCE[key]
    if src == "bandage" then
        -- Show the debuff even with no bandage in your bags; your next one still has to wait.
        return BandageDebuff()
    end
    -- Combo macros only use the potion in combat; out of combat they're food/drink. The
    -- potion cooldown shows there only in combat unless the "Always" option is chosen.
    if (key == "combo" or key == "comboMP") and EC.db.comboCooldown ~= "always"
        and not UnitAffectingCombat("player") then
        return 0, 0
    end
    local pick = src and EC.picks and EC.picks[src]
    if pick then return ItemCooldown(pick.itemID) end
    return 0, 0
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local BAR_PREFIXES = {
    "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local buttons = {}
local hooked = {}
local macroKeys = {} -- [macro name] = EC macro key

local function ButtonSlot(button)
    local slot = button.action
    if not slot and button.GetPagedID then slot = button:GetPagedID() end
    if not slot and ActionButton_GetPagedID then slot = ActionButton_GetPagedID(button) end
    return slot
end

-- The EC macro on this action slot, if any. Matched by name: on newer clients GetActionInfo
-- returns the macro's current spell/item ID instead of its macro index.
local function MacroKey(slot)
    local kind = GetActionInfo(slot)
    if kind ~= "macro" then return nil end
    local name = GetActionText and GetActionText(slot)
    return name and macroKeys[name]
end

-- The macro name ("EC Bandage") sits under the countdown numbers and gets cut off, so hide it
-- while a cooldown runs and show it again afterwards.
local hiddenNames = {} -- [button] = true
local expiryTimers = {} -- [rounded end time] = true

local function NameText(button)
    if button.Name then return button.Name end
    local n = button.GetName and button:GetName()
    return n and _G[n .. "Name"]
end

-- The countdown numbers are big and centred, so they run into the stack count in the corner.
-- Shrink them and lift them a little on EC buttons; undo it when the cooldown ends.
local COUNTDOWN_SCALE, COUNTDOWN_LIFT = 0.7, 1
local restyled = {} -- [cooldown] = { fs, font, size, flags, points }

local function CountdownText(cd)
    if cd.GetCountdownFontString then
        local fs = cd:GetCountdownFontString()
        if fs then return fs end
    end
    for i = 1, select("#", cd:GetRegions()) do
        local r = select(i, cd:GetRegions())
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
    end
end

local function StyleCountdown(cd, on)
    local saved = restyled[cd]
    if on then
        if saved then return end
        local fs = CountdownText(cd) -- may not exist until the first cooldown has been shown
        if not fs then return end
        local font, size, flags = fs:GetFont()
        if not font or not size then return end
        local points = {}
        for i = 1, fs:GetNumPoints() do points[i] = { fs:GetPoint(i) } end
        restyled[cd] = { fs = fs, font = font, size = size, flags = flags, points = points }
        fs:SetFont(font, math.floor(size * COUNTDOWN_SCALE + 0.5), flags)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", cd, "CENTER", 0, COUNTDOWN_LIFT)
    elseif saved then
        restyled[cd] = nil
        local fs = saved.fs
        fs:SetFont(saved.font, saved.size, saved.flags)
        fs:ClearAllPoints()
        if #saved.points > 0 then
            for _, p in ipairs(saved.points) do fs:SetPoint(unpack(p)) end
        else
            fs:SetPoint("CENTER", cd, "CENTER")
        end
    end
end

local function SetNameHidden(button, hide)
    if button.cooldown then StyleCountdown(button.cooldown, hide) end
    local fs = NameText(button)
    if not fs then return end
    if hide and not hiddenNames[button] then
        fs:SetAlpha(0)
        hiddenNames[button] = true
    elseif not hide and hiddenNames[button] then
        fs:SetAlpha(1)
        hiddenNames[button] = nil
    end
end

-- Refresh once a cooldown ends, so the name comes back.
local function RefreshAt(endTime)
    local key = math.floor(endTime)
    if expiryTimers[key] then return end
    expiryTimers[key] = true
    C_Timer.After(math.max(0.1, endTime - GetTime() + 0.1), function()
        expiryTimers[key] = nil
        EC:RefreshCooldowns()
    end)
end

local applied = {} -- [cooldown frame] = true while it shows a cooldown we set

-- Take our cooldown off a button, leaving whatever the game itself wants to show.
local function ClearOurs(cd, slot)
    if not applied[cd] then return end
    applied[cd] = nil
    local s, d = 0, 0
    if slot and slot ~= 0 and GetActionCooldown then s, d = GetActionCooldown(slot) end
    if d and d > 0 then
        cd:SetCooldown(s, d)
    elseif cd.Clear then
        cd:Clear()
    else
        cd:SetCooldown(0, 0)
    end
end

local function Apply(button)
    if not button then return end
    local cd = button.cooldown
    local slot = ButtonSlot(button)
    if not EC.db or not EC.db.showCooldowns then
        SetNameHidden(button, false)
        if cd then ClearOurs(cd, slot) end
        return
    end
    if not cd then return end
    local key = slot and slot ~= 0 and HasAction(slot) and MacroKey(slot)
    if not key then
        SetNameHidden(button, false)
        ClearOurs(cd, slot)
        return
    end

    local start, duration = Wanted(key)
    local active = duration > GCD_MAX and start + duration > GetTime()
    SetNameHidden(button, active)
    if not active then
        ClearOurs(cd, slot)
        return
    end
    RefreshAt(start + duration)

    -- Leave it alone if the game is already showing this (or a longer) cooldown.
    if cd.GetCooldownTimes then
        local cs, cdur = cd:GetCooldownTimes()
        if cs and cdur and cdur > 0 and (cs + cdur) / 1000 >= start + duration - 0.1 then return end
    end
    cd:SetCooldown(start, duration)
    applied[cd] = true
    StyleCountdown(cd, true) -- the countdown text may only exist now
end

local function Hook(button)
    if hooked[button] then return end
    hooked[button] = true
    table.insert(buttons, button)
    -- Re-apply after Blizzard redraws the button's cooldown (it would clear ours).
    if button.UpdateCooldown then hooksecurefunc(button, "UpdateCooldown", Apply) end
end

local function CollectButtons()
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then Hook(b) end
        end
    end
end

if ActionButton_UpdateCooldown then hooksecurefunc("ActionButton_UpdateCooldown", Apply) end

function EC:RefreshCooldowns()
    if not self.db then return end
    if not self.db.showCooldowns then
        for _, b in ipairs(buttons) do Apply(b) end -- clears what we added
        return
    end
    wipe(macroKeys)
    for _, def in ipairs(self.MACROS) do
        if SOURCE[def.key] then
            if GetMacroIndexByName(def.name) > 0 then macroKeys[def.name] = def.key end
        end
    end
    CollectButtons()
    for _, b in ipairs(buttons) do Apply(b) end
end

-- /ec debug: what the cooldown display can see.
function EC:PrintCooldownDebug()
    local start, duration = BandageDebuff()
    local left = start + duration - GetTime()
    print(("  Recently Bandaged on you: %s"):format(duration > 0 and left > 0 and ("%.0fs left"):format(left) or "no"))
    CollectButtons()
    local found = 0
    for _, b in ipairs(buttons) do
        local slot = ButtonSlot(b)
        local key = slot and slot > 0 and HasAction(slot) and MacroKey(slot)
        if key then
            found = found + 1
            print(("  %s (slot %d): %s, cooldown frame %s"):format(b:GetName() or "?", slot, key,
                b.cooldown and "ok" or "missing"))
        end
    end
    if found == 0 then print("  no EC bandage/potion macros found on Blizzard action bars") end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
f:RegisterEvent("BAG_UPDATE_COOLDOWN")
f:RegisterEvent("UPDATE_MACROS")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:RegisterEvent("PLAYER_REGEN_DISABLED") -- combo macros switch between food/drink and potions
f:RegisterEvent("PLAYER_REGEN_ENABLED")

local queued = false
f:SetScript("OnEvent", function()
    -- Many of these fire in bursts and before Blizzard redraws its buttons; refresh once, just after.
    if queued then return end
    queued = true
    C_Timer.After(0.05, function()
        queued = false
        EC:RefreshCooldowns()
    end)
end)
