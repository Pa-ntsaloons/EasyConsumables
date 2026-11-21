-- EasyConsumables: keeps a set of macros pointed at the best consumables in your bags.
-- Built for WoW Forever (Interface 16001, Classic rules on the modern client), with
-- fallbacks so it also runs on other clients.
--
-- Items are recognised by their item class (Consumable) and by parsing their "Use:"
-- tooltip text, so there is no item list to keep up to date.
--
-- Files (load order is in the .toc):
--   Init.lua        shared namespace, API compatibility, event dispatch, print helper
--   Locales.lua     tooltip wording per client language
--   Settings.lua    macro list, saved-variable defaults and migrations
--   Parser.lua      reads item tooltips into { food, drink, hpot, mpot, bandage, ... }
--   Picker.lua      picks the best item per category; remembers items for the Consumables page
--   Mage.lua        conjure ranks for your target, Alt-click trading
--   Macros.lua      macro bodies and creating / editing the macros
--   Updater.lua     the update loop and the events that trigger it
--   Commands.lua    /ec slash commands, /ec status, /ec debug
--   Cooldowns.lua   cooldown swipes on action buttons holding EC macros
--   Options.lua     main options page
--   Consumables.lua Consumables page (every item you've had, on/off each)
--   Minimap.lua     minimap button

local ADDON_NAME, ns = ...

local EC = CreateFrame("Frame")
ns.EC = EC
ns.ADDON_NAME = ADDON_NAME
_G.EasyConsumables = EC -- macros call EasyConsumables:TradeConjured()

ns.PREFIX = "|cff33ff99EasyConsumables|r: "

function ns.Print(msg)
    print(ns.PREFIX .. msg)
end

---------------------------------------------------------------------------
-- Events: any file can listen with EC:On(event, handler). Handlers get (event, ...).
---------------------------------------------------------------------------

local handlers = {}

function EC:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        self:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

EC:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

-- Run fn once saved settings are loaded (EC.db exists). Used to build the UI.
local readyFns = {}
function ns.OnReady(fn) table.insert(readyFns, fn) end
function ns.RunReady()
    for _, fn in ipairs(readyFns) do fn() end
    readyFns = {}
end

---------------------------------------------------------------------------
-- API compatibility (modern C_ namespaces with classic-style fallbacks)
---------------------------------------------------------------------------

local Compat = {}
ns.Compat = Compat

Compat.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
Compat.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
Compat.GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
Compat.GetItemName = (C_Item and C_Item.GetItemNameByID) or function(id) return (Compat.GetItemInfo(id)) end
Compat.GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
Compat.GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
Compat.GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
Compat.PickupContainerItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
Compat.LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

function Compat.RequestItemData(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
end

function Compat.ItemDataLoaded(itemID)
    if C_Item and C_Item.IsItemDataCachedByID then
        return C_Item.IsItemDataCachedByID(itemID)
    end
    return Compat.GetItemInfo(itemID) ~= nil
end

-- Item name, asking the client to load it if it isn't cached yet.
function Compat.ItemNameOrLoad(itemID)
    local name = Compat.GetItemName(itemID)
    if not name then Compat.RequestItemData(itemID) end
    return name
end

-- Color escape for an item's quality ("|cff1eff00"), white if unknown.
function Compat.QualityColor(itemID)
    local _, _, quality = Compat.GetItemInfo(itemID)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or "|cffffffff"
end

-- Item link if the client has it, else the name, else "item <id>".
function Compat.ItemLabel(itemID, fallbackName)
    return select(2, Compat.GetItemInfo(itemID)) or fallbackName or ("item " .. itemID)
end

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

ns.MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
ns.NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

function ns.HasMana()
    return (UnitPowerMax("player", ns.MANA) or 0) > 0
end

-- Every bag slot: fn(bag, slot) for bags 0..NUM_BAGS.
function ns.ForEachBagSlot(fn)
    for bag = 0, ns.NUM_BAGS do
        for slot = 1, (Compat.GetNumSlots(bag) or 0) do
            fn(bag, slot)
        end
    end
end
