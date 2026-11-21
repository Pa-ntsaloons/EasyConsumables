-- EasyConsumables: macro list, saved-variable defaults and migrations.

local _, ns = ...
local EC = ns.EC

-- Macro definitions. Names must be <= 16 characters.
--   noPick     no single "best item" (combo / mage), so /ec status skips it
--   hideInList follows another macro's switch (no checkbox of its own)
--   mageOnly   only created for mages
EC.MACROS = {
    { key = "food",     name = "EC Food",      label = "Food" },
    { key = "drink",    name = "EC Drink",     label = "Drink" },
    { key = "health",   name = "EC Health",    label = "Health Potion" },
    { key = "mana",     name = "EC Mana",      label = "Mana Potion" },
    { key = "bandage",  name = "EC Bandage",   label = "Bandage" },
    { key = "combo",    name = "EC Combo",     label = "Combo", noPick = true },
    { key = "comboMP",  name = "EC Combo MP",  label = "Combo: Mana Side", noPick = true, hideInList = true },
    { key = "mage",     name = "EC Mage",      label = "Mage: Conjure for Target", mageOnly = true, noPick = true },
    { key = "mageFood", name = "EC Mage Food", label = "Mage: Conjure Food", mageOnly = true, noPick = true, hideInList = true },
}

local DEFAULTS = {
    macros = { food = true, drink = true, health = true, mana = true, bandage = true, combo = false, mage = true },
    mageTradeStacks = 2,         -- stacks of conjured water and of food to put in the trade window
    comboModifier = "shift",     -- hold this for the mana side: mana potion in combat, drink out of combat
    comboStyle = "split",        -- "single" = one macro + modifier, "split" = EC Combo (health side) + EC Combo MP (mana side)
    comboEatMode = "both",       -- single style, out of combat: "both" = eat + drink at once, "modifier" = food, modifier = drink
    mageStyle = "split",         -- "single" = EC Mage (click water, Shift food), "split" = EC Mage (water) + EC Mage Food
    useBuffFood = false,         -- buff food (Well Fed / XP / stat buffs). Off: never used, so it's saved. On: may be used
    buffFoodFirst = true,        -- with useBuffFood: eat it before other food/drink (off: ranked like any other food)
    seen = {},                   -- [itemID] = category letters: every consumable you've had (Consumables page)
    preferConjured = false,      -- use conjured items first even if weaker
    preferHealthstone = true,    -- healthstones beat potions for the health macro
    bandageSmartTarget = true,   -- mouseover / friendly target, falls back to self
    perCharacter = true,         -- create macros as character-specific
    skipNoManaMacros = true,     -- don't create drink/mana macros on characters without mana
    announce = false,            -- print when a macro's item changes
    showCooldowns = true,        -- cooldown swipe on action buttons: Recently Bandaged, potion/healthstone cooldowns
    comboCooldown = "combat",    -- potion cooldown on the combo buttons: "combat" = only in combat, "always"
    ignored = {},                -- [itemID] = true
    minimap = {
        show = true,             -- show the minimap button
        fade = true,             -- fade it out until the mouse is over the minimap or the button
        angle = 220,             -- position around the minimap, in degrees
    },
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- One-time changes to saved settings from older versions, in order.
local MIGRATIONS = {
    -- v2: two macros became the default for combo and mage; move existing installs over once.
    [2] = function(db)
        db.comboStyle = "split"
        db.mageStyle = "split"
    end,
    -- v3: "ignore buff food" merged into "use Well Fed (XP buff) food first".
    [3] = function(db)
        if db.ignoreBuffFood == false then db.useXpFood = true end
        db.ignoreBuffFood = nil
    end,
    -- v4: "Well Fed (XP buff) food" became "buff food".
    [4] = function(db)
        if db.useXpFood ~= nil then db.useBuffFood = db.useXpFood end
        if db.xpFoodFirst ~= nil then db.buffFoodFirst = db.xpFoodFirst end
        db.useXpFood, db.xpFoodFirst = nil, nil
    end,
    -- v5: the buff food list became the Consumables page; switched-off buff foods are ignored items.
    [5] = function(db)
        for id in pairs(db.buffFoodOff or {}) do db.ignored[id] = true end
        for id in pairs(db.buffFoods or {}) do
            if not db.seen[id] then db.seen[id] = "b" end
        end
        db.buffFoods, db.buffFoodOff = nil, nil
    end,
}

-- Loads (or creates) the saved settings into EC.db. Called once, on ADDON_LOADED.
function EC:LoadSettings()
    EasyConsumablesDB = EasyConsumablesDB or {}
    local db = EasyConsumablesDB
    CopyDefaults(DEFAULTS, db)
    local version = db.settingsVersion or 1
    local latest = version
    for v in pairs(MIGRATIONS) do
        if v > latest then latest = v end
    end
    for v = version + 1, latest do
        if MIGRATIONS[v] then MIGRATIONS[v](db) end
    end
    db.settingsVersion = latest
    self.db = db
end

-- Whether this macro is switched on in the options (and kept up to date if it exists).
function EC:IsEnabled(key)
    local db = self.db
    if key == "comboMP" then return db.macros.combo and db.comboStyle == "split" end
    if key == "mageFood" then return db.macros.mage and db.mageStyle == "split" end
    return db.macros[key]
end
