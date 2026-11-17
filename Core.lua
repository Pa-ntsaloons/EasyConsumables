-- EasyConsumables: keeps a set of macros pointed at the best consumables in your bags.
-- Built for WoW Forever (Interface 16001, Classic rules on the modern client), with
-- fallbacks so it also runs on other clients.
--
-- Items are recognised by their item class (Consumable) and by parsing their "Use:"
-- tooltip text, so there is no item list to keep up to date.

local ADDON_NAME, ns = ...

local EC = CreateFrame("Frame")
ns.EC = EC
_G.EasyConsumables = EC

local PREFIX = "|cff33ff99EasyConsumables|r: "
local ICON_DYNAMIC = 134400 -- question mark icon; with #showtooltip it shows the item/spell being used

---------------------------------------------------------------------------
-- API compatibility (modern C_ namespaces with classic-style fallbacks)
---------------------------------------------------------------------------

local Compat = {}
ns.Compat = Compat

Compat.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
Compat.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
Compat.GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
Compat.GetItemName = (C_Item and C_Item.GetItemNameByID) or function(id) return (Compat.GetItemInfo(id)) end
Compat.GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
Compat.PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
Compat.LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

function Compat.GetSlot(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.stackCount or 1, i.isLocked end
    elseif GetContainerItemInfo then
        local _, count, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count or 1, locked
    end
end

function Compat.GetSpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

function Compat.GetSpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id)
end

function Compat.GetSpellSubtext(id)
    local f = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    if not f then return nil end
    local ok, sub = pcall(f, id)
    return ok and sub or nil
end

function Compat.IsSpellKnown(id)
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

function Compat.IsMage()
    return select(2, UnitClass("player")) == "MAGE"
end

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- Macro definitions. Names must be <= 16 characters.
EC.MACROS = {
    { key = "food",    name = "EC Food",    label = "Food" },
    { key = "drink",   name = "EC Drink",   label = "Drink" },
    { key = "health",  name = "EC Health",  label = "Health Potion" },
    { key = "mana",    name = "EC Mana",    label = "Mana Potion" },
    { key = "bandage", name = "EC Bandage", label = "Bandage" },
    { key = "combo",   name = "EC Combo",   label = "Combo", noPick = true },
    { key = "comboMP", name = "EC Combo MP", label = "Combo: Mana Side", noPick = true, hideInList = true },
    { key = "mage",    name = "EC Mage",    label = "Mage: Conjure for Target", mageOnly = true, noPick = true },
    { key = "mageFood", name = "EC Mage Food", label = "Mage: Conjure Food", mageOnly = true, noPick = true, hideInList = true },
}

local DEFAULTS = {
    macros = { food = true, drink = true, health = true, mana = true, bandage = true, combo = false, mage = true },
    mageTradeStacks = 2,         -- stacks of conjured water and of food to put in the trade window
    comboModifier = "shift",     -- hold this for the mana side: mana potion in combat, drink out of combat
    comboStyle = "split",        -- "single" = one macro + modifier, "split" = EC Combo (health side) + EC Combo MP (mana side)
    comboEatMode = "both",
    mageStyle = "split",         -- "single" = EC Mage (click water, Shift food), "split" = EC Mage (water) + EC Mage Food       -- single style, out of combat: "both" = eat + drink at once, "modifier" = food, modifier = drink
    useXpFood = false,           -- Well Fed (XP buff) food. Off: never used, so it's saved. On: used before other food/drink
    preferConjured = false,      -- use conjured items first even if weaker
    preferHealthstone = true,    -- healthstones beat potions for the health macro
    bandageSmartTarget = true,   -- mouseover / friendly target, falls back to self
    perCharacter = true,         -- create macros as character-specific
    skipNoManaMacros = true,     -- don't create drink/mana macros on characters without mana
    announce = false,            -- print when a macro's item changes
    ignored = {},                -- [itemID] = true
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

---------------------------------------------------------------------------
-- Tooltip reading
---------------------------------------------------------------------------

local scanTip
local function GetTooltipLines(bag, slot)
    local out = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if not data or not data.lines then return nil end
        for i, line in ipairs(data.lines) do
            if not line.leftText and TooltipUtil and TooltipUtil.SurfaceArgs then
                TooltipUtil.SurfaceArgs(line)
            end
            local c = line.leftColor
            out[i] = { text = line.leftText or "", r = c and c.r or 1, g = c and c.g or 1, b = c and c.b or 1 }
        end
        return out
    end

    -- Fallback: hidden GameTooltip
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EasyConsumablesScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
        local fs = _G["EasyConsumablesScanTipTextLeft" .. i]
        if fs then
            local r, g, b = fs:GetTextColor()
            out[i] = { text = fs:GetText() or "", r = r or 1, g = g or 1, b = b or 1 }
        end
    end
    scanTip:Hide()
    return out
end

---------------------------------------------------------------------------
-- Item parsing
---------------------------------------------------------------------------

local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local SUB = (Enum and Enum.ItemConsumableSubclass) or {}
local SUB_FOOD    = SUB.Fooddrink or 5
local SUB_BANDAGE = SUB.Bandage or 7

local USE_PREFIX = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
local CONJURED_TEXT = ITEM_CONJURED or "Conjured Item"

local cache = {}          -- [itemID] = parsed info (or false = not relevant)
local incomplete = false  -- some tooltip data wasn't loaded yet

local function ToNum(s)
    if not s then return nil end
    s = s:gsub(",", ""):gsub("%.$", "")
    return tonumber(s)
end

-- How many times an "every N sec for M sec" / "per second for M sec" effect ticks,
-- looking only at the text right after the amount.
local function TickMultiplier(rest)
    local dur = rest:match("^[^%.]-every second for ([%d%.]+) sec") or rest:match("^[^%.]-per second for ([%d%.]+) sec")
    if dur then return ToNum(dur) or 1 end
    local interval, total = rest:match("^[^%.]-every ([%d%.]+) sec%a* for ([%d%.]+) sec")
    if interval then
        interval, total = ToNum(interval), ToNum(total)
        if interval and total and interval > 0 then return total / interval end
    end
    return 1
end

-- Returns flat, pct (0-1) for a resource word mentioned in a lowercased line.
local function ParseAmountWord(text, res)
    -- "140 to 180 health"
    local a, b, e = text:match("([%d,%.]+) to ([%d,%.]+) " .. res .. "()")
    if a then
        a, b = ToNum(a), ToNum(b)
        if a and b then return (a + b) / 2 * TickMultiplier(text:sub(e)), nil end
    end
    -- "25% of your maximum health", "7% health"
    local p
    p, e = text:match("([%d%.]+)%% of your maximum " .. res .. "()")
    if not p then p, e = text:match("([%d%.]+)%% of your " .. res .. "()") end
    if not p then p, e = text:match("([%d%.]+)%% " .. res .. "()") end
    if p then
        p = ToNum(p)
        if p then return nil, p / 100 * TickMultiplier(text:sub(e)) end
    end
    -- "61.2 health"
    local v
    v, e = text:match("([%d,%.]+) " .. res .. "()")
    v = ToNum(v)
    if v then return v * TickMultiplier(text:sub(e)), nil end
end

local function ParseAmount(text, res)
    local flat, pct = ParseAmountWord(text, res)
    if not flat and not pct and res == "health" then
        flat, pct = ParseAmountWord(text, "life") -- classic healthstones: "restores 500 life"
    end
    return flat, pct
end

local function IsRed(l)
    return l.r > 0.9 and l.g < 0.25 and l.b < 0.25
end

-- Returns info table, false if not a relevant consumable, or nil if data isn't loaded yet.
local function ParseItem(itemID, bag, slot)
    local _, _, _, _, _, classID, subclassID = Compat.GetItemInfoInstant(itemID)
    if classID ~= CONSUMABLE then return false end

    local lines = GetTooltipLines(bag, slot)
    if not lines or #lines == 0 or lines[1].text == "" then return nil end

    local info = {
        itemID = itemID,
        name = lines[1].text,
        subclass = subclassID,
        healthstone = lines[1].text:lower():find("healthstone", 1, true) ~= nil,
    }

    local useText
    for i = 2, #lines do
        local l = lines[i]
        local t = l.text
        if t ~= "" then
            if IsRed(l) then info.unusable = true end -- unmet level / skill requirement
            if t == CONJURED_TEXT then info.conjured = true end
            local lower = t:lower()
            -- Well Fed food (on WoW Forever this is the XP buff); "experience" catches other wordings.
            if lower:find("well fed", 1, true) or lower:find("experience", 1, true) then info.wellFed = true end
            if lower:find(USE_PREFIX, 1, true) == 1 then
                useText = (useText and (useText .. " ") or "") .. lower
            end
        end
    end

    local minLevel = select(5, Compat.GetItemInfo(itemID))
    info.minLevel = minLevel or 0
    if minLevel and minLevel > UnitLevel("player") then info.unusable = true end

    if not useText then return false end

    -- Bandages
    if subclassID == SUB_BANDAGE or useText:find("heals [%d,%.]+ damage") then
        local amt = ToNum(useText:match("heals ([%d,%.]+) damage")) or ParseAmount(useText, "health")
        if amt then info.bandage = amt end
        return info.bandage and info or false
    end

    local hFlat, hPct = ParseAmount(useText, "health")
    local mFlat, mPct = ParseAmount(useText, "mana")
    if not (mFlat or mPct) and useText:find("health and mana", 1, true) then
        mFlat, mPct = hFlat, hPct
    end

    local seated = useText:find("seated", 1, true) or useText:find("while eating", 1, true)
        or useText:find("while drinking", 1, true) or subclassID == SUB_FOOD

    if seated then
        if hFlat or hPct then info.food = { flat = hFlat, pct = hPct } end
        if mFlat or mPct then info.drink = { flat = mFlat, pct = mPct } end
    else
        if hFlat or hPct then info.hpot = { flat = hFlat, pct = hPct } end
        if mFlat or mPct then info.mpot = { flat = mFlat, pct = mPct } end
    end

    if not (info.food or info.drink or info.hpot or info.mpot) then return false end
    return info
end

local function Value(amount, maxValue)
    if not amount then return 0 end
    return (amount.flat or 0) + (amount.pct or 0) * (maxValue or 0)
end
EC.Value = Value

-- Iterate bags, parsing (cached) every item. Calls fn(bag, slot, itemID, count, locked, info) for relevant items.
local function ForEachConsumable(fn)
    for bag = 0, NUM_BAGS do
        for slot = 1, (Compat.GetNumSlots(bag) or 0) do
            local id, count, locked = Compat.GetSlot(bag, slot)
            if id then
                local info = cache[id]
                if info == nil then
                    info = ParseItem(id, bag, slot)
                    if info == nil then incomplete = true else cache[id] = info end
                end
                if info then fn(bag, slot, id, count, locked, info) end
            end
        end
    end
end

-- Returns { food = entry, drink = entry, ... } where entry = { itemID, value, count, info }
function EC:Scan()
    local db = self.db
    incomplete = false
    local items = {} -- [itemID] = { info, count }

    ForEachConsumable(function(_, _, id, count, _, info)
        if db.ignored[id] then return end
        if items[id] then
            items[id].count = items[id].count + count
        else
            items[id] = { info = info, count = count }
        end
    end)

    local maxHP = UnitHealthMax("player")
    local maxMana = UnitPowerMax("player", MANA)

    local candidates = { food = {}, drink = {}, health = {}, mana = {}, bandage = {} }
    for id, it in pairs(items) do
        local info = it.info
        if not info.unusable then
            local function add(cat, value)
                if value and value > 0 then
                    table.insert(candidates[cat], { itemID = id, value = value, count = it.count, info = info })
                end
            end
            local skipBuff = info.wellFed and not db.useXpFood
            if info.food and not skipBuff then add("food", Value(info.food, maxHP)) end
            if info.drink and not skipBuff then add("drink", Value(info.drink, maxMana)) end
            if info.hpot then add("health", Value(info.hpot, maxHP)) end
            if info.mpot then add("mana", Value(info.mpot, maxMana)) end
            if info.bandage then add("bandage", info.bandage) end
        end
    end

    local picks = {}
    for cat, list in pairs(candidates) do
        table.sort(list, function(a, b)
            if (cat == "food" or cat == "drink") and (a.info.wellFed or false) ~= (b.info.wellFed or false) then
                return a.info.wellFed == true -- only reachable when useXpFood is on
            end
            if db.preferConjured and (a.info.conjured or false) ~= (b.info.conjured or false) then
                return a.info.conjured == true
            end
            if cat == "health" and db.preferHealthstone and a.info.healthstone ~= b.info.healthstone then
                return a.info.healthstone == true
            end
            -- Better item wins; on a tie (rounded, so "61.2" vs "61" counts as equal) conjured wins.
            local av, bv = math.floor(a.value + 0.5), math.floor(b.value + 0.5)
            if av ~= bv then return av > bv end
            if (a.info.conjured or false) ~= (b.info.conjured or false) then return a.info.conjured == true end
            if a.count ~= b.count then return a.count < b.count end -- finish small stacks first
            return a.itemID < b.itemID
        end)
        picks[cat] = list[1]
    end
    return picks
end

---------------------------------------------------------------------------
-- Mage conjuring (Classic ranks)
---------------------------------------------------------------------------

-- spell = rank spell ID, item = item it conjures, req = fallback required level of that item.
-- The real required level is read from the item when the client has it cached.
local MAGE_WATER = {
    { spell = 5504,   item = 5350, req = 0 },   -- Rank 1: Conjured Water
    { spell = 5505,   item = 2288, req = 5 },   -- Rank 2: Conjured Fresh Water
    { spell = 5506,   item = 2136, req = 15 },  -- Rank 3: Conjured Purified Water
    { spell = 6127,   item = 3772, req = 25 },  -- Rank 4: Conjured Spring Water
    { spell = 10138,  item = 8077, req = 35 },  -- Rank 5: Conjured Mineral Water
    { spell = 10139,  item = 8078, req = 45 },  -- Rank 6: Conjured Sparkling Water
    { spell = 10140,  item = 8079, req = 55 },  -- Rank 7: Conjured Crystal Water
    { spell = 468766, req = 60 },               -- Rank 8 (WoW Forever)
}
local MAGE_FOOD = {
    { spell = 587,   item = 5349,  req = 0 },   -- Rank 1: Conjured Muffin
    { spell = 597,   item = 1113,  req = 5 },   -- Rank 2: Conjured Bread
    { spell = 990,   item = 1114,  req = 15 },  -- Rank 3: Conjured Rye
    { spell = 6129,  item = 1487,  req = 25 },  -- Rank 4: Conjured Pumpernickel
    { spell = 10144, item = 8075,  req = 35 },  -- Rank 5: Conjured Sourdough
    { spell = 10145, item = 8076,  req = 45 },  -- Rank 6: Conjured Sweet Roll
    { spell = 28612, item = 22895, req = 55 },  -- Rank 7: Conjured Cinnamon Roll
}
local SPELL_REFRESHMENT = 190336 -- modern Conjure Refreshment, if the client ever has it

local function RankReq(r)
    if r.item then
        local lvl = select(5, Compat.GetItemInfo(r.item))
        if lvl then return lvl end
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(r.item) end
    end
    return r.req
end

-- Highest known rank whose conjured item someone of `level` can use.
local function BestRank(list, level)
    local best, lowest
    for _, r in ipairs(list) do
        if Compat.IsSpellKnown(r.spell) then
            lowest = lowest or r
            if RankReq(r) <= level then best = r end
        end
    end
    return best or lowest
end

local function CastName(spellID)
    local name = Compat.GetSpellName(spellID)
    if not name then return nil end
    local sub = Compat.GetSpellSubtext(spellID)
    if sub and sub ~= "" then return ("%s(%s)"):format(name, sub) end
    return name
end

local function FriendlyPlayerTarget()
    return UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
        and UnitIsFriend("player", "target")
end

-- Who we're conjuring for and which ranks fit them.
function EC:ComputeMageState()
    local st = {}
    if FriendlyPlayerTarget() then
        st.level = UnitLevel("target")
        st.targetName = UnitName("target")
    end
    if not st.level or st.level <= 0 then
        st.level = UnitLevel("player")
        st.targetName = nil
    end
    st.water = BestRank(MAGE_WATER, st.level)
    st.food = BestRank(MAGE_FOOD, st.level)
    st.waterCast = st.water and CastName(st.water.spell)
    st.foodCast = st.food and CastName(st.food.spell)
    if not st.waterCast and not st.foodCast and Compat.IsSpellKnown(SPELL_REFRESHMENT) then
        st.waterCast = Compat.GetSpellName(SPELL_REFRESHMENT)
    end
    self.mageState = st
    return st
end

local tradePending = 0

-- Alt-click of the mage macro: open trade with the target and fill it with conjured
-- water + food they can use.
function EC:TradeConjured()
    if not FriendlyPlayerTarget() or not UnitIsConnected("target") then
        print(PREFIX .. "target a friendly player to trade them food and water.")
        return
    end
    if CheckInteractDistance then
        local ok, inRange = pcall(CheckInteractDistance, "target", 2)
        if ok and inRange == false then
            print(PREFIX .. (UnitName("target") or "target") .. " is too far away to trade.")
            return
        end
    end
    tradePending = GetTime()
    if TradeFrame and TradeFrame:IsShown() then
        self:FillTrade()
    else
        InitiateTrade("target")
    end
end

function EC:FillTrade()
    if tradePending == 0 or GetTime() - tradePending > 15 then return end
    tradePending = 0

    local level = UnitLevel("NPC")
    if not level or level <= 0 then level = UnitLevel("target") end
    if not level or level <= 0 then level = UnitLevel("player") end

    -- Best conjured drink and food the trade partner can use.
    local best = {}
    ForEachConsumable(function(_, _, id, _, _, info)
        if not info.conjured or (info.minLevel or 0) > level then return end
        for _, cat in ipairs({ "drink", "food" }) do
            if info[cat] then
                local v = Value(info[cat], 0)
                if not best[cat] or v > best[cat].value then best[cat] = { itemID = id, value = v } end
            end
        end
    end)

    local wanted = {}
    if best.drink then wanted[best.drink.itemID] = self.db.mageTradeStacks end
    if best.food and not wanted[best.food.itemID] then wanted[best.food.itemID] = self.db.mageTradeStacks end
    if not next(wanted) then
        print(PREFIX .. "you have no conjured food or water that " .. (UnitName("target") or "they") ..
            " can use. Press EC Mage to conjure some for them first.")
        return
    end

    local tradeSlot, maxSlots = 1, (MAX_TRADABLE_ITEMS or 6)
    for bag = 0, NUM_BAGS do
        for slot = 1, (Compat.GetNumSlots(bag) or 0) do
            local id, _, locked = Compat.GetSlot(bag, slot)
            if id and (wanted[id] or 0) > 0 and not locked then
                while tradeSlot <= maxSlots and GetTradePlayerItemLink(tradeSlot) do tradeSlot = tradeSlot + 1 end
                if tradeSlot > maxSlots then return end
                ClearCursor()
                Compat.PickupContainerItem(bag, slot)
                ClickTradeButton(tradeSlot)
                wanted[id] = wanted[id] - 1
                tradeSlot = tradeSlot + 1
            end
        end
    end
end

---------------------------------------------------------------------------
-- Macro bodies
---------------------------------------------------------------------------

local function Empty(what)
    return ("#showtooltip\n/run print(\"EasyConsumables: no %s in your bags\")"):format(what)
end

local function ItemRef(entry) return "item:" .. entry.itemID end

local BODY = {}

function BODY.food(p)   return p.food and ("#showtooltip\n/use " .. ItemRef(p.food)) or Empty("food") end
function BODY.drink(p)  return p.drink and ("#showtooltip\n/use " .. ItemRef(p.drink)) or Empty("drink") end
function BODY.health(p) return p.health and ("#showtooltip\n/use " .. ItemRef(p.health)) or Empty("health potion") end
function BODY.mana(p)   return p.mana and ("#showtooltip\n/use " .. ItemRef(p.mana)) or Empty("mana potion") end

function BODY.bandage(p, db)
    if not p.bandage then return Empty("bandage") end
    local target = db.bandageSmartTarget and "[@mouseover,help,nodead][help,nodead][@player] " or "[@player] "
    return "#showtooltip\n/use " .. target .. ItemRef(p.bandage)
end

-- One-sided combo used by the "split" style: [combat] potion; [nocombat] food-or-drink
local function SideBody(pot, eat, what)
    local clauses = {}
    if pot then table.insert(clauses, "[combat] " .. ItemRef(pot)) end
    if eat then table.insert(clauses, "[nocombat] " .. ItemRef(eat)) end
    if #clauses == 0 then return Empty(what) end
    return "#showtooltip\n/use " .. table.concat(clauses, "; ")
end

-- Single style: in combat health potion (modifier = mana potion); out of combat eat + drink
-- together, or food with modifier = drink.
-- Split style: this is the health side (health potion / food); EC Combo MP is the mana side.
function BODY.combo(p, db)
    if db.comboStyle == "split" then
        return SideBody(p.health, p.food, "health potion or food")
    end

    local clauses = {}
    local hp, mp = p.health, p.mana
    local mod = db.comboModifier
    local hasMod = mod and mod ~= "none"
    if hp and mp and hasMod then
        table.insert(clauses, ("[combat,mod:%s] %s"):format(mod, ItemRef(mp)))
        table.insert(clauses, "[combat] " .. ItemRef(hp))
    elseif hp or mp then
        table.insert(clauses, "[combat] " .. ItemRef(hp or mp))
    end

    local food, drink = p.food, p.drink
    if food and drink and food.itemID == drink.itemID then drink = nil end
    local both = false
    if food and drink and hasMod and db.comboEatMode == "modifier" then
        table.insert(clauses, ("[nocombat,mod:%s] %s"):format(mod, ItemRef(drink)))
        table.insert(clauses, "[nocombat] " .. ItemRef(food))
    elseif food or drink then
        table.insert(clauses, "[nocombat] " .. ItemRef(food or drink))
        both = food and drink
    end

    if #clauses == 0 then return Empty("food, drink or potions") end

    local body = "#showtooltip\n/use " .. table.concat(clauses, "; ")
    if both then
        body = body .. "\n/use [nocombat] " .. ItemRef(drink)
    end
    return body
end

function BODY.comboMP(p)
    return SideBody(p.mana, p.drink, "mana potion or drink")
end

-- Mage: ranks are chosen for your friendly player target's level (or yours), and the macros
-- are rewritten when your target changes, since addons can't cast spells themselves.
-- Single style: click = water, Shift = food. Split style: EC Mage = water, EC Mage Food = food.
-- Alt-click always trades conjured food/water to your target.
local MAGE_TRADE_LINE = "\n/run if IsAltKeyDown() then EasyConsumables:TradeConjured() end"

local function MageBody(parts, what)
    if #parts == 0 then
        return ("#showtooltip\n/run print(\"EasyConsumables: you don't know any %s spells yet\")"):format(what)
    end
    return "#showtooltip\n/cast " .. table.concat(parts, "; ") .. MAGE_TRADE_LINE
end

function BODY.mage(_, db)
    local st = EC:ComputeMageState()
    local parts = {}
    if db.mageStyle == "split" then
        if st.waterCast then table.insert(parts, "[nomod:alt] " .. st.waterCast) end
        return MageBody(parts, "conjure water")
    end
    if st.foodCast then table.insert(parts, "[mod:shift] " .. st.foodCast) end
    if st.waterCast then table.insert(parts, "[nomod] " .. st.waterCast) end
    return MageBody(parts, "conjure food/water")
end

function BODY.mageFood()
    local st = EC:ComputeMageState()
    local parts = {}
    if st.foodCast then table.insert(parts, "[nomod:alt] " .. st.foodCast) end
    return MageBody(parts, "conjure food")
end

---------------------------------------------------------------------------
-- Macro writing
---------------------------------------------------------------------------

local function Trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function HasMana()
    return (UnitPowerMax("player", MANA) or 0) > 0
end

-- Whether this macro is switched on in the options (and kept up to date if it exists).
function EC:IsEnabled(key)
    local db = self.db
    if key == "comboMP" then return db.macros.combo and db.comboStyle == "split" end
    if key == "mageFood" then return db.macros.mage and db.mageStyle == "split" end
    return db.macros[key]
end

-- Whether a missing macro should be created for this character.
function EC:ShouldCreate(key)
    if not self:IsEnabled(key) then return false end
    if (key == "mage" or key == "mageFood") and not Compat.IsMage() then return false end
    if self.db.skipNoManaMacros and (key == "drink" or key == "mana" or key == "comboMP") and not HasMana() then
        return false
    end
    return true
end

function EC:SetComboStyle(style)
    self.db.comboStyle = style
    -- Going back to one macro: remove the now-unused mana-side macro.
    if style == "single" and not InCombatLockdown() and GetMacroIndexByName("EC Combo MP") > 0 then
        DeleteMacro("EC Combo MP")
        print(PREFIX .. "removed EC Combo MP (EC Combo now handles both sides).")
    end
    self:RequestUpdate()
end

function EC:SetMageStyle(style)
    self.db.mageStyle = style
    -- Going back to one macro: remove the now-unused food macro.
    if style == "single" and not InCombatLockdown() and GetMacroIndexByName("EC Mage Food") > 0 then
        DeleteMacro("EC Mage Food")
        print(PREFIX .. "removed EC Mage Food (EC Mage now does water, Shift for food).")
    end
    self:RequestUpdate()
end

local warnedFull = false

function EC:WriteMacro(def, body)
    local idx = GetMacroIndexByName(def.name)
    if idx == 0 then
        if not self:ShouldCreate(def.key) then return end
        local numAccount, numChar = GetNumMacros()
        local perChar = self.db.perCharacter
        if (perChar and numChar >= (MAX_CHARACTER_MACROS or 18))
            or (not perChar and numAccount >= (MAX_ACCOUNT_MACROS or 120)) then
            if not warnedFull then
                print(PREFIX .. "your " .. (perChar and "character" or "general") ..
                    " macro slots are full; free one up so " .. def.name .. " can be created.")
                warnedFull = true
            end
            return
        end
        CreateMacro(def.name, ICON_DYNAMIC, body, perChar)
    elseif self:IsEnabled(def.key) then
        if Trim(GetMacroBody(idx)) ~= Trim(body) then
            EditMacro(idx, def.name, ICON_DYNAMIC, body)
        end
    end
end

---------------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------------

EC.picks = {}
local pendingUpdate = false
local scheduled = false

local function MacroFrameOpen()
    return MacroFrame and MacroFrame:IsShown()
end

local function CanEditMacros()
    -- Macros can't be edited in combat, and Blizzard's macro UI saves over our edits when it closes.
    return not InCombatLockdown() and not MacroFrameOpen()
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

    if self.db.announce then
        for _, def in ipairs(self.MACROS) do
            local o, n = old[def.key], picks[def.key]
            if n and self.db.macros[def.key] and (o and o.itemID) ~= n.itemID then
                print(PREFIX .. def.label .. " -> " .. (select(2, Compat.GetItemInfo(n.itemID)) or n.info.name))
            end
        end
    end

    for _, def in ipairs(self.MACROS) do
        self:WriteMacro(def, BODY[def.key](picks, self.db))
    end

    if incomplete then
        C_Timer.After(2, function() EC:RequestUpdate() end)
    end

    if self.OnPicksChanged then self:OnPicksChanged() end
end

-- Cheap update of just the mage macro (target changes, spells learned).
function EC:UpdateMageMacro()
    if not self.db or not Compat.IsMage() or not self.db.macros.mage then return end
    if not CanEditMacros() then
        pendingUpdate = true
        return
    end
    for _, def in ipairs(self.MACROS) do
        if def.key == "mage" or def.key == "mageFood" then
            self:WriteMacro(def, BODY[def.key](self.picks, self.db))
        end
    end
    if self.OnPicksChanged then self:OnPicksChanged() end
end

function EC:RequestUpdate()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.25, function()
        scheduled = false
        EC:Update()
    end)
end

function EC:ClearCache()
    wipe(cache)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

EC:RegisterEvent("ADDON_LOADED")
EC:RegisterEvent("PLAYER_LOGIN")

local function HookMacroFrame()
    if MacroFrame and not EC.hookedMacroFrame then
        EC.hookedMacroFrame = true
        MacroFrame:HookScript("OnHide", function() if pendingUpdate then EC:RequestUpdate() end end)
    end
end

EC:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            EasyConsumablesDB = EasyConsumablesDB or {}
            CopyDefaults(DEFAULTS, EasyConsumablesDB)
            self.db = EasyConsumablesDB
            -- v2: two macros became the default for combo and mage; move existing installs over once.
            if (self.db.settingsVersion or 1) < 2 then
                self.db.comboStyle = "split"
                self.db.mageStyle = "split"
                self.db.settingsVersion = 2
            end
            -- v3: "ignore buff food" merged into "use Well Fed (XP buff) food first".
            if self.db.settingsVersion < 3 then
                if self.db.ignoreBuffFood == false then self.db.useXpFood = true end
                self.db.ignoreBuffFood = nil
                self.db.settingsVersion = 3
            end
            if self.InitOptions then self:InitOptions() end
        end
        HookMacroFrame() -- Blizzard_MacroUI is load-on-demand
    elseif event == "PLAYER_LOGIN" then
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("SKILL_LINES_CHANGED")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        if Compat.IsMage() then
            self:RegisterEvent("PLAYER_TARGET_CHANGED")
            self:RegisterEvent("SPELLS_CHANGED")
            self:RegisterEvent("TRADE_SHOW")
        end
        self:RequestUpdate()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "SPELLS_CHANGED" then
        self:UpdateMageMacro()
    elseif event == "TRADE_SHOW" then
        if tradePending > 0 then C_Timer.After(0.2, function() EC:FillTrade() end) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then self:RequestUpdate() end
    elseif event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" then
        self:ClearCache() -- level/skill requirements may now be met
        self:RequestUpdate()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if incomplete then self:RequestUpdate() end
    else
        self:RequestUpdate()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

function EC:PrintStatus()
    print(PREFIX .. "current picks:")
    for _, def in ipairs(self.MACROS) do
        if not def.noPick then
            local p = self.picks[def.key]
            local text = p and ((select(2, Compat.GetItemInfo(p.itemID)) or p.info.name) ..
                (" x%d (%d)"):format(p.count, math.floor(p.value))) or "|cff888888none|r"
            print(("  %s: %s"):format(def.label, text))
        end
    end
    if Compat.IsMage() then
        local st = self:ComputeMageState()
        print(("  Mage (for %s, level %d): water %s, food %s"):format(st.targetName or "you", st.level,
            st.waterCast or "-", st.foodCast or "-"))
    end
end

SLASH_EASYCONSUMABLES1 = "/ec"
SLASH_EASYCONSUMABLES2 = "/easyconsumables"
SlashCmdList.EASYCONSUMABLES = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "config" or cmd == "options" then
        EC:OpenOptions()
    elseif cmd == "status" then
        EC:PrintStatus()
    elseif cmd == "update" or cmd == "refresh" then
        EC:ClearCache()
        EC:Update()
        print(PREFIX .. (InCombatLockdown() and "will update after combat." or "macros updated."))
    elseif cmd == "ignore" or cmd == "unignore" then
        local id = tonumber(rest:match("item:(%d+)") or rest)
        if not id then
            print(PREFIX .. "usage: /ec " .. cmd .. " <shift-click item or item ID>")
            return
        end
        EC.db.ignored[id] = (cmd == "ignore") or nil
        print(PREFIX .. (cmd == "ignore" and "ignoring " or "no longer ignoring ") ..
            (select(2, Compat.GetItemInfo(id)) or ("item " .. id)))
        EC:RequestUpdate()
    elseif cmd == "ignorelist" then
        print(PREFIX .. "ignored items:")
        local any
        for id in pairs(EC.db.ignored) do
            any = true
            print("  " .. (select(2, Compat.GetItemInfo(id)) or ("item " .. id)) .. " (" .. id .. ")")
        end
        if not any then print("  none") end
    else
        print(PREFIX .. "commands:")
        print("  /ec - open options")
        print("  /ec status - show the current best item for each macro")
        print("  /ec update - rescan bags and rewrite macros now")
        print("  /ec ignore <item> - never pick this item (shift-click it into chat)")
        print("  /ec unignore <item> - allow an ignored item again")
        print("  /ec ignorelist - list ignored items")
    end
end
