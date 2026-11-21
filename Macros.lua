-- EasyConsumables: macro bodies, and creating / editing the macros.

local _, ns = ...
local EC, Compat, Parser = ns.EC, ns.Compat, ns.Parser

local ICON_DYNAMIC = 134400 -- question mark icon; with #showtooltip it shows the item/spell being used

---------------------------------------------------------------------------
-- Bodies: BODY[key](picks, db) -> macro text
---------------------------------------------------------------------------

local function Empty(what)
    return ("#showtooltip\n/run print(\"EasyConsumables: no %s in your bags\")"):format(what)
end

local function ItemRef(entry) return "item:" .. entry.itemID end

local function UseBest(entry, what)
    return entry and ("#showtooltip\n/use " .. ItemRef(entry)) or Empty(what)
end

local BODY = {}
EC.BODY = BODY

function BODY.food(p)   return UseBest(p.food, "food") end
function BODY.drink(p)  return UseBest(p.drink, "drink") end
function BODY.health(p) return UseBest(p.health, "health potion") end
function BODY.mana(p)   return UseBest(p.mana, "mana potion") end

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
-- Writing
---------------------------------------------------------------------------

local function Trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local warnedFull = false
local macrosReady = false -- the game has loaded the macro list (until then lookups by name return 0)

function EC:MacrosReady() return macrosReady end
function EC:SetMacrosReady() macrosReady = true end

-- Whether a missing macro should be created for this character.
function EC:ShouldCreate(key)
    if not self:IsEnabled(key) then return false end
    if (key == "mage" or key == "mageFood") and not Compat.IsMage() then return false end
    if self.db.skipNoManaMacros and (key == "drink" or key == "mana" or key == "comboMP") and not ns.HasMana() then
        return false
    end
    return true
end

function EC:WriteMacro(def, body)
    local idx = GetMacroIndexByName(def.name)
    if idx == 0 then
        if not self:ShouldCreate(def.key) then return end
        -- Creating before the macro list loads would duplicate macros that already exist.
        if not macrosReady then
            Parser.MarkIncomplete()
            return
        end
        local numAccount, numChar = GetNumMacros()
        local perChar = self.db.perCharacter
        if (perChar and numChar >= (MAX_CHARACTER_MACROS or 18))
            or (not perChar and numAccount >= (MAX_ACCOUNT_MACROS or 120)) then
            if not warnedFull then
                ns.Print("your " .. (perChar and "character" or "general") ..
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

-- Write every macro (keys = nil) or just the listed ones ({ mage = true, ... }).
function EC:WriteMacros(picks, keys)
    for _, def in ipairs(self.MACROS) do
        if not keys or keys[def.key] then
            self:WriteMacro(def, BODY[def.key](picks, self.db))
        end
    end
end

---------------------------------------------------------------------------
-- Style switches (one macro vs two)
---------------------------------------------------------------------------

local function DeleteIfPresent(name, message)
    if not InCombatLockdown() and GetMacroIndexByName(name) > 0 then
        DeleteMacro(name)
        ns.Print(message)
    end
end

function EC:SetComboStyle(style)
    self.db.comboStyle = style
    -- Going back to one macro: remove the now-unused mana-side macro.
    if style == "single" then
        DeleteIfPresent("EC Combo MP", "removed EC Combo MP (EC Combo now handles both sides).")
    end
    self:RequestUpdate()
end

function EC:SetMageStyle(style)
    self.db.mageStyle = style
    -- Going back to one macro: remove the now-unused food macro.
    if style == "single" then
        DeleteIfPresent("EC Mage Food", "removed EC Mage Food (EC Mage now does water, Shift for food).")
    end
    self:RequestUpdate()
end
