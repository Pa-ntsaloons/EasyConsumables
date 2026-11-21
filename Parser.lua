-- EasyConsumables: reads item tooltips into what each consumable does.
--
-- ParseItem returns a table like
--   { itemID, name, food = {flat, pct}, drink = ..., hpot = ..., mpot = ..., bandage = amount,
--     healthstone, conjured, buff, zone, unusable, minLevel }
-- false for items that aren't relevant, or nil if the client hasn't loaded the item yet.

local _, ns = ...
local Compat, L = ns.Compat, ns.L

local Parser = {}
ns.Parser = Parser

local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local SUB = (Enum and Enum.ItemConsumableSubclass) or {}
local SUB_FOOD    = SUB.Fooddrink or 5
local SUB_BANDAGE = SUB.Bandage or 7
Parser.CONSUMABLE = CONSUMABLE

local USE_PREFIX = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
local CONJURED_TEXT = ITEM_CONJURED or "Conjured Item"

local cache = {}          -- [itemID] = parsed info (or false = not relevant)
local incomplete = false  -- some item / bag / unit data wasn't loaded yet during the current scan
local noUseTries = {}     -- [itemID] = times we saw it with no "Use:" line (tooltip may still be loading)
local NO_USE_RETRIES = 5
local debugText = {}      -- [itemID] = the "Use:" text the parser saw, for /ec debug

---------------------------------------------------------------------------
-- "Something wasn't loaded yet" flag, shared by the scan and the macro writer.
---------------------------------------------------------------------------

function Parser.ResetIncomplete() incomplete = false end
function Parser.MarkIncomplete() incomplete = true end
function Parser.IsIncomplete() return incomplete end

function Parser.ClearCache()
    wipe(cache)
    wipe(noUseTries)
end

function Parser.Cached(itemID) return cache[itemID] end
function Parser.DebugText(itemID) return debugText[itemID] end

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
-- Text helpers
---------------------------------------------------------------------------

local function ContainsAny(text, words)
    for _, w in ipairs(words) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

-- Rewrite a lowercased "Use:" text from the client's language into English phrasing (Locales.lua).
local function Normalize(text)
    for _, r in ipairs(L.rules) do
        text = text:gsub(r[1], r[2])
    end
    return text
end

-- "61.2", "61,2" (comma decimal), "1,500" / "1.500" (thousands) -> number
local function ToNum(s)
    if not s then return nil end
    s = s:gsub("[%.,]$", "")
    s = s:gsub("[,%.](%d%d%d)%f[^%d]", "%1") -- thousands separator: followed by exactly 3 digits
    s = s:gsub(",", ".")
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
    if not p then
        -- other word orders ("25% eurer maximalen health"): a percentage shortly before the word
        local filler
        p, filler, e = text:match("([%d%.,]+)%%([^%d]-)" .. res .. "()")
        if filler and #filler > 40 then p = nil end
    end
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

---------------------------------------------------------------------------
-- Battleground-only consumables. The tooltip names the battleground ("Requires Warsong Gulch",
-- "Only usable in Alterac Valley", or just the name), red when you're not there.
-- We record the zone instead of caching "unusable", so the item works once you're inside.
-- Names come from the client (so they're in its language), with English as a fallback.
---------------------------------------------------------------------------

local BATTLEGROUNDS = {
    { map = 1460, name = "Warsong Gulch" },
    { map = 1461, name = "Arathi Basin" },
    { map = 1459, name = "Alterac Valley" },
}
local zoneNames -- { { lower = "warsong gulch", key = "warsong gulch" }, ... }

local function ZoneNames()
    if zoneNames then return zoneNames end
    zoneNames = {}
    for _, bg in ipairs(BATTLEGROUNDS) do
        local key = bg.name:lower()
        table.insert(zoneNames, { lower = key, key = key })
        if C_Map and C_Map.GetMapInfo then
            local ok, mi = pcall(C_Map.GetMapInfo, bg.map)
            if ok and mi and mi.name and mi.name ~= "" and mi.name:lower() ~= key then
                table.insert(zoneNames, { lower = mi.name:lower(), key = key })
            end
        end
    end
    return zoneNames
end

-- Returns the battleground a (non-"Use:") tooltip line restricts the item to.
local function ZoneRestriction(lower)
    if lower:find(USE_PREFIX, 1, true) == 1 or #lower > 80 then return nil end
    for _, z in ipairs(ZoneNames()) do
        if lower:find(z.lower, 1, true) then return z.key end
    end
end

-- Whether you're currently in the battleground with this key.
function Parser.InZone(key)
    local here = ((GetInstanceInfo and GetInstanceInfo()) or ""):lower()
    local real = ((GetRealZoneText and GetRealZoneText()) or ""):lower()
    for _, z in ipairs(ZoneNames()) do
        if z.key == key and (z.lower == here or z.lower == real) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------

local function ParseItem(itemID, bag, slot)
    local _, _, _, _, _, classID, subclassID = Compat.GetItemInfoInstant(itemID)
    if not classID then return nil end
    if classID ~= CONSUMABLE then return false end

    -- Right after login the item's data is often not loaded yet, and its tooltip comes back
    -- with only the name. Wait for the data (GET_ITEM_INFO_RECEIVED) instead of caching it.
    if not Compat.ItemDataLoaded(itemID) then
        Compat.RequestItemData(itemID)
        return nil
    end

    local lines = GetTooltipLines(bag, slot)
    if not lines or #lines == 0 or lines[1].text == "" then
        Compat.RequestItemData(itemID)
        return nil
    end

    local info = {
        itemID = itemID,
        name = lines[1].text,
        subclass = subclassID,
        healthstone = ContainsAny(lines[1].text:lower(), L.healthstone),
    }

    local useText
    for i = 2, #lines do
        local l = lines[i]
        local t = l.text
        if t ~= "" then
            local lower = t:lower()
            local zone = ZoneRestriction(lower)
            if zone then
                info.zone = zone
            elseif IsRed(l) then
                info.unusable = true -- unmet level / skill requirement
            end
            if t == CONJURED_TEXT then info.conjured = true end
            -- Buff food: Well Fed (on WoW Forever this is the XP buff), "experience", etc.
            if ContainsAny(lower, L.wellFed) then info.buff = true end
            if lower:find(USE_PREFIX, 1, true) == 1 then
                useText = (useText and (useText .. " ") or "") .. lower
            end
        end
    end

    local minLevel = select(5, Compat.GetItemInfo(itemID))
    info.minLevel = minLevel or 0
    if minLevel and minLevel > UnitLevel("player") then info.unusable = true end

    if not useText then
        -- Could be a tooltip whose spell text hasn't loaded yet; look again a few times
        -- before deciding the item has no use effect.
        local tries = (noUseTries[itemID] or 0) + 1
        noUseTries[itemID] = tries
        if tries < NO_USE_RETRIES then return nil end
        return false
    end
    noUseTries[itemID] = nil

    local seated = ContainsAny(useText, L.seated) or subclassID == SUB_FOOD
    -- Any other effect lasting minutes ("gain 12 Stamina for 15 min") also makes it buff food;
    -- plain food and drink only last seconds.
    if useText:find("%d%s*" .. L.minute) then info.buff = true end
    useText = Normalize(useText)
    debugText[itemID] = useText

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

-- How much a { flat, pct } amount restores for someone with `maxValue` health or mana.
function Parser.Value(amount, maxValue)
    if not amount then return 0 end
    return (amount.flat or 0) + (amount.pct or 0) * (maxValue or 0)
end

-- Iterate bags, parsing (cached) every item. Calls fn(bag, slot, itemID, count, locked, info)
-- for relevant items. Marks the scan incomplete if anything isn't loaded yet.
function Parser.ForEachConsumable(fn)
    -- The backpack always has slots; 0 means bag contents aren't available yet.
    if (Compat.GetNumSlots(0) or 0) == 0 then incomplete = true end
    ns.ForEachBagSlot(function(bag, slot)
        local id, count, locked = Compat.GetSlot(bag, slot)
        if not id then return end
        local info = cache[id]
        if info == nil then
            info = ParseItem(id, bag, slot)
            if info == nil then incomplete = true else cache[id] = info end
        end
        if info then fn(bag, slot, id, count, locked, info) end
    end)
end
