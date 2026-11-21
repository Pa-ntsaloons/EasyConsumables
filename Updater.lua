-- EasyConsumables: the update loop (scan bags -> write macros) and the events that trigger it.
--
-- Macros can't be edited in combat or while Blizzard's macro window is open, so updates wait
-- until then. If anything wasn't loaded yet (item data, bags, macro list, unit stats), the
-- update is retried a few times.

local _, ns = ...
local EC, Compat, Parser = ns.EC, ns.Compat, ns.Parser

EC.picks = {}

local pendingUpdate = false -- an update was skipped (combat / macro window) and should run later
local scheduled = false
local retries = 0
local MAX_RETRIES = 20

local function CanEditMacros()
    -- Macros can't be edited in combat, and Blizzard's macro UI saves over our edits when it closes.
    return not InCombatLockdown() and not (MacroFrame and MacroFrame:IsShown())
end

local function AnnounceChanges(old, picks)
    for _, def in ipairs(EC.MACROS) do
        local o, n = old[def.key], picks[def.key]
        if n and EC.db.macros[def.key] and (o and o.itemID) ~= n.itemID then
            ns.Print(def.label .. " -> " .. Compat.ItemLabel(n.itemID, n.info.name))
        end
    end
end

-- Something wasn't loaded yet: look again shortly (capped so a broken item can't loop forever).
local function RetryIfIncomplete()
    if Parser.IsIncomplete() then
        retries = retries + 1
        if retries <= MAX_RETRIES then
            C_Timer.After(retries <= 5 and 1 or 3, function() EC:RequestUpdate() end)
        end
    else
        retries = 0
    end
end

function EC:Update()
    if not self.db then return end
    if not CanEditMacros() then
        pendingUpdate = true
        return
    end
    pendingUpdate = false

    local old = self.picks
    local picks = self:Scan()
    self.picks = picks

    if self.db.announce then AnnounceChanges(old, picks) end
    self:WriteMacros(picks)
    RetryIfIncomplete()

    if self.OnPicksChanged then self:OnPicksChanged() end
    if self.RefreshCooldowns then self:RefreshCooldowns() end
end

-- Cheap update of just the mage macros (target changes, spells learned).
local MAGE_KEYS = { mage = true, mageFood = true }
function EC:UpdateMageMacro()
    if not self.db or not Compat.IsMage() or not self.db.macros.mage then return end
    if not CanEditMacros() then
        pendingUpdate = true
        return
    end
    self:WriteMacros(self.picks, MAGE_KEYS)
    if self.OnPicksChanged then self:OnPicksChanged() end
end

-- Batch bursts of events into one update shortly after.
function EC:RequestUpdate()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.25, function()
        scheduled = false
        EC:Update()
    end)
end

-- Forget parsed items (e.g. after a level-up, requirements may now be met) and retry counts.
function EC:ClearCache()
    Parser.ClearCache()
    retries = 0
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function Request() EC:RequestUpdate() end

local function HookMacroFrame()
    if MacroFrame and not EC.hookedMacroFrame then
        EC.hookedMacroFrame = true
        MacroFrame:HookScript("OnHide", function() if pendingUpdate then EC:RequestUpdate() end end)
    end
end

EC:On("ADDON_LOADED", function(_, name)
    if name == ns.ADDON_NAME then
        EC:LoadSettings()
        ns.RunReady()
    end
    HookMacroFrame() -- Blizzard_MacroUI is load-on-demand
end)

EC:On("PLAYER_LOGIN", function()
    EC:On("BAG_UPDATE_DELAYED", Request)
    EC:On("PLAYER_EQUIPMENT_CHANGED", Request)
    EC:On("ZONE_CHANGED_NEW_AREA", Request) -- battleground-only items
    EC:On("PLAYER_REGEN_ENABLED", function()
        if pendingUpdate then EC:RequestUpdate() end
    end)
    local function RequirementsChanged() -- level/skill requirements may now be met
        EC:ClearCache()
        EC:RequestUpdate()
    end
    EC:On("PLAYER_LEVEL_UP", RequirementsChanged)
    EC:On("SKILL_LINES_CHANGED", RequirementsChanged)
    EC:On("GET_ITEM_INFO_RECEIVED", function()
        if Parser.IsIncomplete() then EC:RequestUpdate() end
    end)

    EC:RequestUpdate()
    if not ns.localeSupported then
        ns.Print("your client language (" .. tostring(ns.locale) .. ") isn't supported yet, so " ..
            "some items may not be recognised. /ec debug shows what was read.")
    end
    -- Bags, item data and unit stats trickle in over the first few seconds after login,
    -- often without an event we'd notice; rescan a few times to be safe.
    for _, delay in ipairs({ 3, 8, 15 }) do
        C_Timer.After(delay, Request)
    end
end)

-- The macro list is loaded once either of these has fired. UPDATE_MACROS also fires for our
-- own edits, so only the first one matters; loading screens always rescan (battlegrounds).
local function MacrosMaybeReady(event)
    if not EC:MacrosReady() then
        EC:SetMacrosReady()
        if EC.db then EC:RequestUpdate() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        EC:RequestUpdate()
    end
end
EC:On("UPDATE_MACROS", MacrosMaybeReady)
EC:On("PLAYER_ENTERING_WORLD", MacrosMaybeReady)
