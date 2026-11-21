-- EasyConsumables: /ec slash commands.

local _, ns = ...
local EC, Compat, Parser = ns.EC, ns.Compat, ns.Parser

function EC:PrintStatus()
    ns.Print("current picks:")
    for _, def in ipairs(self.MACROS) do
        if not def.noPick then
            local p = self.picks[def.key]
            local text = p and (Compat.ItemLabel(p.itemID, p.info.name) ..
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

-- What the parser made of one item, e.g. "food 61.2, conjured".
local function Describe(info)
    local function amt(a)
        return ("%s%s"):format(a.flat and ("%g"):format(a.flat) or "", a.pct and (" %g%%"):format(a.pct * 100) or "")
    end
    local parts = {}
    if info.food then table.insert(parts, "food " .. amt(info.food)) end
    if info.drink then table.insert(parts, "drink " .. amt(info.drink)) end
    if info.hpot then table.insert(parts, "health " .. amt(info.hpot)) end
    if info.mpot then table.insert(parts, "mana " .. amt(info.mpot)) end
    if info.bandage then table.insert(parts, "bandage " .. ("%g"):format(info.bandage)) end
    if info.healthstone then table.insert(parts, "healthstone") end
    if info.conjured then table.insert(parts, "conjured") end
    if info.buff then table.insert(parts, "buff food") end
    if info.zone then table.insert(parts, "only in " .. info.zone) end
    if info.unusable then table.insert(parts, "|cffff4040can't use|r") end
    return parts
end

-- Every consumable in your bags and what the parser made of it; for checking translations.
function EC:PrintDebug()
    ns.Print("bag consumables (client " .. tostring(ns.locale) .. "):")
    Parser.ForEachConsumable(function() end) -- make sure everything is parsed
    local shown = {}
    ns.ForEachBagSlot(function(bag, slot)
        local id = Compat.GetSlot(bag, slot)
        if not id or shown[id] or select(6, Compat.GetItemInfoInstant(id)) ~= Parser.CONSUMABLE then return end
        shown[id] = true
        local info = Parser.Cached(id)
        local parts = info and Describe(info) or {}
        local status = info == nil and "|cffffff00still loading|r"
            or (#parts > 0 and table.concat(parts, ", ")) or "|cff888888not recognised|r"
        print(("  %s: %s"):format(Compat.ItemLabel(id), status))
        if not info and Parser.DebugText(id) then
            print("    |cff888888read as: " .. Parser.DebugText(id) .. "|r")
        end
    end)
    if self.PrintCooldownDebug then
        ns.Print("cooldown display:")
        self:PrintCooldownDebug()
    end
end

local function SetIgnored(cmd, rest)
    local id = tonumber(rest:match("item:(%d+)") or rest)
    if not id then
        ns.Print("usage: /ec " .. cmd .. " <shift-click item or item ID>")
        return
    end
    EC.db.ignored[id] = (cmd == "ignore") or nil
    ns.Print((cmd == "ignore" and "ignoring " or "no longer ignoring ") .. Compat.ItemLabel(id))
    EC:RequestUpdate()
end

local function PrintIgnored()
    ns.Print("ignored items:")
    local any
    for id in pairs(EC.db.ignored) do
        any = true
        print("  " .. Compat.ItemLabel(id) .. " (" .. id .. ")")
    end
    if not any then print("  none") end
end

local HELP = {
    "/ec - open options",
    "/ec status - show the current best item for each macro",
    "/ec update - rescan bags and rewrite macros now",
    "/ec list - open the Consumables page (turn items on/off)",
    "/ec minimap - show or hide the minimap button",
    "/ec debug - list bag consumables and how each was read",
    "/ec ignore <item> - never pick this item (shift-click it into chat)",
    "/ec unignore <item> - allow an ignored item again",
    "/ec ignorelist - list ignored items",
}

local COMMANDS = {
    [""]         = function() EC:OpenOptions() end,
    config       = function() EC:OpenOptions() end,
    options      = function() EC:OpenOptions() end,
    status       = function() EC:PrintStatus() end,
    debug        = function() EC:PrintDebug() end,
    list         = function() EC:OpenConsumables() end,
    items        = function() EC:OpenConsumables() end,
    minimap      = function() EC:ToggleMinimapButton() end,
    ignorelist   = PrintIgnored,
    ignore       = SetIgnored,
    unignore     = SetIgnored,
    update       = function()
        EC:ClearCache()
        EC:Update()
        ns.Print(InCombatLockdown() and "will update after combat." or "macros updated.")
    end,
}
COMMANDS.refresh = COMMANDS.update

SLASH_EASYCONSUMABLES1 = "/ec"
SLASH_EASYCONSUMABLES2 = "/easyconsumables"
SlashCmdList.EASYCONSUMABLES = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local fn = COMMANDS[cmd]
    if fn then
        fn(cmd, rest)
    else
        ns.Print("commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end
