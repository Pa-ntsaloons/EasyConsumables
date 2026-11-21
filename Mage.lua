-- EasyConsumables: mage conjuring (Classic ranks) for your target, and Alt-click trading.

local _, ns = ...
local EC, Compat, Parser = ns.EC, ns.Compat, ns.Parser

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

EC.MAGE_WATER_ICON_SPELL = 5504
EC.MAGE_FOOD_ICON_SPELL = 587

local function RankReq(r)
    if r.item then
        local lvl = select(5, Compat.GetItemInfo(r.item))
        if lvl then return lvl end
        Compat.RequestItemData(r.item)
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

---------------------------------------------------------------------------
-- Trading (Alt-click of the mage macros)
---------------------------------------------------------------------------

local tradePending = 0

-- Open trade with the target and fill it with conjured water + food they can use.
function EC:TradeConjured()
    if not FriendlyPlayerTarget() or not UnitIsConnected("target") then
        ns.Print("target a friendly player to trade them food and water.")
        return
    end
    if CheckInteractDistance then
        local ok, inRange = pcall(CheckInteractDistance, "target", 2)
        if ok and inRange == false then
            ns.Print((UnitName("target") or "target") .. " is too far away to trade.")
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
    Parser.ForEachConsumable(function(_, _, id, _, _, info)
        if not info.conjured or (info.minLevel or 0) > level then return end
        for _, cat in ipairs({ "drink", "food" }) do
            if info[cat] then
                local v = Parser.Value(info[cat], 0)
                if not best[cat] or v > best[cat].value then best[cat] = { itemID = id, value = v } end
            end
        end
    end)

    local wanted = {}
    if best.drink then wanted[best.drink.itemID] = self.db.mageTradeStacks end
    if best.food and not wanted[best.food.itemID] then wanted[best.food.itemID] = self.db.mageTradeStacks end
    if not next(wanted) then
        ns.Print("you have no conjured food or water that " .. (UnitName("target") or "they") ..
            " can use. Press EC Mage to conjure some for them first.")
        return
    end

    local tradeSlot, maxSlots = 1, (MAX_TRADABLE_ITEMS or 6)
    ns.ForEachBagSlot(function(bag, slot)
        if tradeSlot > maxSlots then return end
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
    end)
end

---------------------------------------------------------------------------
-- Events (mages only)
---------------------------------------------------------------------------

EC:On("PLAYER_LOGIN", function()
    if not Compat.IsMage() then return end
    -- Ranks depend on your target and the spells you know; rewrite just the mage macros.
    EC:On("PLAYER_TARGET_CHANGED", function() EC:UpdateMageMacro() end)
    EC:On("SPELLS_CHANGED", function() EC:UpdateMageMacro() end)
    EC:On("TRADE_SHOW", function()
        if tradePending > 0 then C_Timer.After(0.2, function() EC:FillTrade() end) end
    end)
end)
