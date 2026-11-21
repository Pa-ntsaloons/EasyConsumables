-- EasyConsumables: picks the best item in your bags for each category.

local _, ns = ...
local EC, Parser = ns.EC, ns.Parser
local Value = Parser.Value

-- Which Consumables-page categories an item belongs to, as letters:
-- f = food, d = drink, b = buff food, h = health potion / Healthstone, m = mana potion / gem, n = bandage
function EC.Categories(info)
    local c = ""
    local buff = info.buff and (info.food or info.drink)
    if info.food and not buff then c = c .. "f" end
    if info.drink and not buff then c = c .. "d" end
    if buff then c = c .. "b" end
    if info.hpot then c = c .. "h" end
    if info.mpot then c = c .. "m" end
    if info.bandage then c = c .. "n" end
    return c
end

-- Remember every consumable you've had, for the Consumables page.
function EC:RememberItem(id, info)
    local c = EC.Categories(info)
    if c ~= "" and self.db.seen[id] ~= c then
        self.db.seen[id] = c
        if self.OnSeenChanged then self:OnSeenChanged() end
    end
end

-- Sort order within one category; the first entry is the pick.
local function Better(cat, db)
    return function(a, b)
        if (cat == "food" or cat == "drink") and db.buffFoodFirst
            and (a.info.buff or false) ~= (b.info.buff or false) then
            return a.info.buff == true -- only reachable when buff food is allowed
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
    end
end

-- Returns { food = entry, drink = entry, health, mana, bandage } where entry = { itemID, value, count, info }.
-- Starts a fresh "incomplete" check; Parser.IsIncomplete() afterwards says whether to scan again.
function EC:Scan()
    local db = self.db
    Parser.ResetIncomplete()

    local items = {} -- [itemID] = { info, count }
    Parser.ForEachConsumable(function(_, _, id, count, _, info)
        self:RememberItem(id, info)
        if db.ignored[id] then return end
        if items[id] then
            items[id].count = items[id].count + count
        else
            items[id] = { info = info, count = count }
        end
    end)

    local maxHP = UnitHealthMax("player") or 0
    local maxMana = UnitPowerMax("player", ns.MANA) or 0
    -- Unit stats can read 0 for a moment after login, which would zero out % based items.
    if maxHP <= 1 then Parser.MarkIncomplete() end

    local candidates = { food = {}, drink = {}, health = {}, mana = {}, bandage = {} }
    for id, it in pairs(items) do
        local info = it.info
        if not info.unusable and (not info.zone or Parser.InZone(info.zone)) then
            local function add(cat, value)
                if value and value > 0 then
                    table.insert(candidates[cat], { itemID = id, value = value, count = it.count, info = info })
                end
            end
            local skipBuff = info.buff and (info.food or info.drink) and not db.useBuffFood
            if info.food and not skipBuff then add("food", Value(info.food, maxHP)) end
            if info.drink and not skipBuff then add("drink", Value(info.drink, maxMana)) end
            if info.hpot then add("health", Value(info.hpot, maxHP)) end
            if info.mpot then add("mana", Value(info.mpot, maxMana)) end
            if info.bandage then add("bandage", info.bandage) end
        end
    end

    local picks = {}
    for cat, list in pairs(candidates) do
        table.sort(list, Better(cat, db))
        picks[cat] = list[1]
    end
    return picks
end
