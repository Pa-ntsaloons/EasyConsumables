-- EasyConsumables options panel (Options > AddOns > EasyConsumables, or /ec)
-- Single scrolling column so nothing gets cut off at any window width.

local _, ns = ...
local EC = ns.EC
local Compat = ns.Compat

local panel, category, content
local refreshers = {}

local MODIFIERS = { "shift", "ctrl", "alt" }
local MOD_LABEL = { shift = "Shift", ctrl = "Ctrl", alt = "Alt" }

local function Refresh()
    for _, f in ipairs(refreshers) do f() end
end

local function ModName() return MOD_LABEL[EC.db.comboModifier] or "Shift" end

local function ItemName(entry)
    return entry and (Compat.GetItemName(entry.itemID) or entry.info.name) or nil
end

local function ItemText(entry)
    if not entry then return "|cff888888none in bags|r" end
    local color = Compat.QualityColor(entry.itemID)
    return ("%s%s|r  |cffaaaaaax%d  (%d)|r"):format(color, ItemName(entry), entry.count, math.floor(entry.value))
end

---------------------------------------------------------------------------
-- Layout helpers. Everything is placed top-down in `content` with a y cursor;
-- text is anchored to both edges so it wraps instead of overflowing.
---------------------------------------------------------------------------

local y = 0
local PAD = 16

local function Advance(h) y = y - h end

local function Text(template, str, indent, height)
    local fs = content:CreateFontString(nil, "ARTWORK", template)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + (indent or 0), y)
    fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if height then fs:SetHeight(height) end
    fs:SetText(str)
    Advance(height or (fs:GetStringHeight() + 2))
    return fs
end

local function Header(str)
    Advance(14)
    local fs = Text("GameFontNormalLarge", str, 0, 20)
    Advance(4)
    return fs
end

local function Tooltip(frame, title, tip)
    if not tip then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(type(tip) == "function" and tip() or tip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- A checkbox (or radio-style option when `radio` is true).
-- get() -> bool, set(bool). enabledFn() -> bool greys it out when false.
local function Check(label, tip, get, set, indent, enabledFn)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + (indent or 0), y)
    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -5)
    fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y - 5)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(label)
    cb.label = fs
    cb:SetHitRectInsets(0, -300, 0, 0)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        EC:RequestUpdate()
        Refresh()
    end)
    Tooltip(cb, label, tip)
    table.insert(refreshers, function()
        cb:SetChecked(get() and true or false)
        local on = not enabledFn or enabledFn()
        cb:SetEnabled(on)
        fs:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
    end)
    Advance(26)
    return cb
end

-- Radio group: options = { {value, label, tip}, ... }
local function Radio(getValue, setValue, options, indent, enabledFn)
    for _, o in ipairs(options) do
        local value = o[1]
        Check(o[2], o[3],
            function() return getValue() == value end,
            function() setValue(value) end,
            indent, enabledFn)
    end
end

---------------------------------------------------------------------------
-- Current picks
---------------------------------------------------------------------------

local rows = {}
local picksBlock

local function PickupFor(def)
    if InCombatLockdown() then return end
    if GetMacroIndexByName(def.name) > 0 then
        PickupMacro(def.name)
    else
        ns.Print(def.name .. " doesn't exist yet - turn it on in /ec.")
    end
end

local CHECK_TIPS = {
    mage = "Target a friendly player, then: click = Conjure Water, Shift-click = Conjure Food, "
        .. "at the highest rank they can use for their level (yours with no target). "
        .. "Alt-click opens trade and puts conjured water and food they can use into it.",
    combo = "Food/drink out of combat, potions in combat. Set it up in the Combo section below.",
}

local CHECK_W = 28 -- room for the enable checkbox at the start of each row

local function CreateRow(def)
    local row = CreateFrame("Button", nil, picksBlock)
    row:SetHeight(40)
    row:RegisterForDrag("LeftButton")
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Enable checkbox. Follow-on macros (EC Combo MP, EC Mage Food) are switched with their
    -- main macro, so they get no box, just the same indent.
    if not def.hideInList then
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetScript("OnClick", function(self)
            EC.db.macros[def.key] = self:GetChecked() and true or false
            EC:RequestUpdate()
            Refresh()
        end)
        local tip = (CHECK_TIPS[def.key] and (CHECK_TIPS[def.key] .. "\n\n") or "")
            .. "On: " .. def.name .. " is created and kept up to date.\nOff: it's no longer updated."
        Tooltip(cb, "Enable " .. def.name, tip)
        row.check = cb
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", CHECK_W + 2, 0)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", CHECK_W + 46, -4)
    row.label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.label:SetJustifyH("LEFT")

    row.item = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.item:SetPoint("TOPLEFT", row, "TOPLEFT", CHECK_W + 46, -18)
    row.item:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -18)
    row.item:SetJustifyH("LEFT")
    row.item:SetJustifyV("TOP")
    row.item:SetHeight(24) -- up to two lines

    row:SetScript("OnDragStart", function() PickupFor(def) end)
    row:SetScript("OnClick", function() PickupFor(def) end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local idx = GetMacroIndexByName(def.name)
        if idx > 0 then
            GameTooltip:SetText(def.name, 1, 1, 1)
            GameTooltip:AddLine(GetMacroBody(idx), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Click or drag to place on your action bar.", 0, 1, 0)
        else
            GameTooltip:SetText(def.name .. " (not created)", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

-- which: nil = both (single style), "water" or "food" (split style)
local function MageRankText(which)
    if not Compat.IsMage() then return "|cff888888Mages only|r" end
    local st = EC:ComputeMageState()
    local function rank(r) return r and (Compat.GetSpellSubtext(r.spell) or "?") or "-" end
    local who = ("For |cffffffff%s|r (level %d): "):format(st.targetName or "you", st.level)
    if which == "water" then return who .. "water " .. rank(st.water) .. ".\nAlt = trade." end
    if which == "food" then return who .. "food " .. rank(st.food) .. ".\nAlt = trade." end
    return who .. ("water %s, food %s.\nShift = food, Alt = trade."):format(rank(st.water), rank(st.food))
end

local function RowContent(def, p)
    local db = EC.db
    local mod = ModName()
    if def.key == "combo" then
        if db.comboStyle == "split" then
            return "Combo: Health Side",
                ("Out of combat: %s\nIn combat: %s"):format(ItemName(p.food) or "-", ItemName(p.health) or "-"),
                p.food or p.health
        end
        local food, drink = p.food, p.drink
        if food and drink and food.itemID == drink.itemID then drink = nil end
        local ooc
        if db.comboEatMode == "modifier" and food and drink then
            ooc = ("%s  (%s: %s)"):format(ItemName(food), mod, ItemName(drink))
        else
            local parts = {}
            if food then table.insert(parts, ItemName(food)) end
            if drink then table.insert(parts, ItemName(drink)) end
            ooc = #parts > 0 and table.concat(parts, " + ") or "-"
        end
        local combat = ItemName(p.health) or ItemName(p.mana) or "-"
        if p.health and p.mana then combat = ("%s  (%s: %s)"):format(ItemName(p.health), mod, ItemName(p.mana)) end
        return "Combo", ("Out of combat: %s\nIn combat: %s"):format(ooc, combat), food or drink or p.health or p.mana
    elseif def.key == "comboMP" then
        return "Combo: Mana Side",
            ("Out of combat: %s\nIn combat: %s"):format(ItemName(p.drink) or "-", ItemName(p.mana) or "-"),
            p.drink or p.mana
    elseif def.key == "mage" then
        if db.mageStyle == "split" then
            return "Mage: Conjure Water", MageRankText("water"), nil, Compat.GetSpellTexture(EC.MAGE_WATER_ICON_SPELL)
        end
        return def.label, MageRankText(), nil, Compat.GetSpellTexture(EC.MAGE_WATER_ICON_SPELL)
    elseif def.key == "mageFood" then
        return def.label, MageRankText("food"), nil, Compat.GetSpellTexture(EC.MAGE_FOOD_ICON_SPELL)
    end
    return def.label, ItemText(p[def.key]), p[def.key]
end

local function RefreshPicks()
    local p = EC.picks or {}
    local py = 0
    for _, def in ipairs(EC.MACROS) do
        local row = rows[def.key]
        local visible = not def.hideInList or EC:IsEnabled(def.key)
        if def.mageOnly and not Compat.IsMage() then visible = false end
        if visible then
            local label, text, entry, tex = RowContent(def, p)
            row.label:SetText(("%s  |cff888888%s|r"):format(label, def.name))
            row.item:SetText(text)
            row.icon:SetTexture(tex or (entry and Compat.GetItemIcon(entry.itemID)) or 134400)
            -- Dim the row, not its checkbox, when the macro is off.
            local a = EC:IsEnabled(def.key) and 1 or 0.4
            row.icon:SetAlpha(a)
            row.label:SetAlpha(a)
            row.item:SetAlpha(a)
            if row.check then row.check:SetChecked(EC.db.macros[def.key] and true or false) end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", picksBlock, "TOPLEFT", 0, py)
            row:SetPoint("TOPRIGHT", picksBlock, "TOPRIGHT", 0, py)
            row:Show()
            py = py - 42
        else
            row:Hide()
        end
    end
    picksBlock:SetHeight(-py)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function BuildPanel()
    panel = CreateFrame("Frame")
    panel.name = "EasyConsumables"

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 100)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(math.max(360, w))
    end)

    y = -PAD
    Text("GameFontNormalHuge", "EasyConsumables", 0, 30)
    Text("GameFontHighlightSmall",
        "Keeps macros pointed at the best consumable in your bags. They update whenever your bags change "
        .. "(after combat if you're fighting). Tick a macro to turn it on; click or drag its row onto your action bar.", 0, 40)

    -- Current picks ---------------------------------------------------------
    Header("Macros  |cff888888(click or drag to action bar)|r")
    picksBlock = CreateFrame("Frame", nil, content)
    picksBlock:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
    picksBlock:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
    picksBlock:SetHeight(1)
    for _, def in ipairs(EC.MACROS) do rows[def.key] = CreateRow(def) end
    table.insert(refreshers, RefreshPicks)

    -- Everything below the picks hangs off a second frame so it moves when rows show/hide.
    local settings = CreateFrame("Frame", nil, content)
    settings:SetPoint("TOPLEFT", picksBlock, "BOTTOMLEFT", -PAD, -6)
    settings:SetPoint("TOPRIGHT", picksBlock, "BOTTOMRIGHT", PAD, -6)
    local outer = content
    content = settings -- helpers now place into `settings`
    y = 0

    local rescan = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    rescan:SetSize(130, 22)
    rescan:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
    rescan:SetText("Rescan now")
    rescan:SetScript("OnClick", function() EC:ClearCache(); EC:Update() end)
    local mac = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    mac:SetSize(130, 22)
    mac:SetPoint("LEFT", rescan, "RIGHT", 8, 0)
    mac:SetText("Open Macros")
    mac:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if not MacroFrame then Compat.LoadAddOn("Blizzard_MacroUI") end
        if MacroFrame then ShowUIPanel(MacroFrame) end
    end)
    Advance(26)


    -- Combo -----------------------------------------------------------------
    Header("Combo macro")
    local comboOn = function() return EC.db.macros.combo end
    Radio(function() return EC.db.comboStyle end, function(v) EC:SetComboStyle(v) end, {
        { "split", "Two macros - EC Combo (food / health potion) and EC Combo MP (drink / mana potion)",
          "Health side: food out of combat, health potion in combat.\nMana side: drink out of combat, mana potion in combat." },
        { "single", "One macro - hold the modifier for the mana side",
          "EC Combo does everything. In combat: health potion, or mana potion while holding the modifier." },
    }, 0, comboOn)

    Text("GameFontNormalSmall", "Out of combat (one-macro style):", 4, 16)
    local singleOn = function() return EC.db.macros.combo and EC.db.comboStyle == "single" end
    Radio(function() return EC.db.comboEatMode end, function(v) EC.db.comboEatMode = v end, {
        { "both", "Eat and drink at the same time",
          "One press starts both food and drink." },
        { "modifier", "Food - hold the modifier for drink",
          "Press for food, modifier-press for drink. Press both quickly to eat and drink together." },
    }, 16, singleOn)

    -- Modifier cycle button
    local modBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    modBtn:SetSize(90, 22)
    modBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, y - 2)
    local modLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modLabel:SetPoint("LEFT", modBtn, "RIGHT", 8, 0)
    modLabel:SetJustifyH("LEFT")
    modLabel:SetText("Modifier key (click to change)")
    modBtn:SetScript("OnClick", function()
        local nextIdx = 1
        for i, m in ipairs(MODIFIERS) do if m == EC.db.comboModifier then nextIdx = i % #MODIFIERS + 1 end end
        EC.db.comboModifier = MODIFIERS[nextIdx]
        EC:RequestUpdate()
        Refresh()
    end)
    Tooltip(modBtn, "Modifier key", "One-macro style: hold it in combat for a mana potion, and (if chosen) out of combat for drink.")
    table.insert(refreshers, function()
        if not MOD_LABEL[EC.db.comboModifier] then EC.db.comboModifier = "shift" end
        modBtn:SetText(ModName())
        local on = singleOn()
        modBtn:SetEnabled(on)
        modLabel:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
    end)
    Advance(28)

    Text("GameFontNormalSmall", "Potion cooldown on the combo buttons:", 4, 16)
    local comboCdOn = function() return EC.db.macros.combo and EC.db.showCooldowns end
    Radio(function() return EC.db.comboCooldown end, function(v)
        EC.db.comboCooldown = v
        EC:RefreshCooldowns()
    end, {
        { "combat", "Only in combat",
          "Out of combat the combo buttons are your food and drink, so they show no cooldown." },
        { "always", "Always",
          "Show the potion cooldown even out of combat, so you can see it before a pull." },
    }, 16, comboCdOn)

    -- Mage ------------------------------------------------------------------
    Header("Mage conjure macro")
    local mageOn = function() return EC.db.macros.mage and Compat.IsMage() end
    Radio(function() return EC.db.mageStyle end, function(v) EC:SetMageStyle(v) end, {
        { "split", "Two macros - EC Mage (water) and EC Mage Food (food)",
          "Separate buttons for water and food, each at the right rank for your target. Alt-click either one to trade." },
        { "single", "One macro - EC Mage: click for water, Shift-click for food",
          "Ranks are picked for your targeted friendly player's level. Alt-click trades to them." },
    }, 0, mageOn)

    -- Buff food --------------------------------------------------------------
    Header("Buff food")
    local buffOn = function() return EC.db.useBuffFood end
    Check("Use buff food",
        "Food and drink that also give a buff: Well Fed (the XP buff), stats, and so on.\n"
            .. "Off: it's never used, so it's saved.\nOn: it can be picked. Turn single items off on the Consumables page.",
        function() return EC.db.useBuffFood end, function(v) EC.db.useBuffFood = v end)
    Check("Eat it before other food",
        "On: buff food is eaten before anything else, even if it restores less, to keep the buff up.\n"
            .. "Off: it's only picked when it's the best food you have.",
        function() return EC.db.buffFoodFirst end, function(v) EC.db.buffFoodFirst = v end,
        24, buffOn)

    -- Rules -----------------------------------------------------------------
    Header("Rules")
    local opts = {
        { "preferHealthstone", "Prefer Healthstones over potions", "Healthstones are free and have their own cooldown, so use them first." },
        { "preferConjured", "Use conjured items even when a bought item is better", "Off (recommended): conjured items are used first when they're as good as a bought one, but a bought item that restores more is used instead.\nOn: conjured items are always used first, even if they restore less." },
        { "bandageSmartTarget", "Bandage: mouseover / friendly target, else self", "Unchecked: always bandage yourself." },
        { "skipNoManaMacros", "Don't create Drink/Mana macros on characters without mana" },
        { "perCharacter", "Create macros as character-specific", "Unchecked: create them in the General (account-wide) macro tab. Only affects newly created macros." },
        { "announce", "Announce in chat when a macro's item changes" },
        { "showCooldowns", "Show cooldowns on EC macro buttons", "Shows the Recently Bandaged wait on EC Bandage, and the potion / Healthstone cooldown on EC Health, EC Mana and the combo macros.\nWorks on Blizzard's action bars.", function() EC:RefreshCooldowns(); Refresh() end },
    }
    for _, o in ipairs(opts) do
        local key, after = o[1], o[4]
        Check(o[2], o[3], function() return EC.db[key] end, function(v)
            EC.db[key] = v
            if after then after() end
        end)
    end

    -- Minimap button --------------------------------------------------------
    Header("Minimap button")
    local mmOn = function() return EC.db.minimap.show end
    Check("Show minimap button",
        "Left-click: options. Right-click: Consumables page. Shift-click: rescan bags.\nDrag it to move it around the minimap.",
        function() return EC.db.minimap.show end,
        function(v) EC:SetMinimapButtonShown(v) end)
    Check("Fade out until hovered",
        "On: the button is hidden until you move the mouse over the minimap or the button.\nOff: always visible.",
        function() return EC.db.minimap.fade end,
        function(v) EC:SetMinimapButtonFade(v) end,
        24, mmOn)

    -- Consumables page ------------------------------------------------------
    Header("Consumables")
    Text("GameFontHighlightSmall",
        "Every consumable you've had, sorted into Food, Drink, Buff Food, Health, Mana and Bandages. "
        .. "Turn one off and it's never used (it goes on the ignore list).", 0, 28)
    local listBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    listBtn:SetSize(180, 22)
    listBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
    listBtn:SetText("Open Consumables page")
    listBtn:SetScript("OnClick", function() EC:OpenConsumables() end)
    Advance(26)

    Advance(8)
    Text("GameFontDisableSmall", "Also: /ec list opens that page, /ec ignore [shift-click item] ignores one.     All commands: /ec help", 0, 16)
    Advance(PAD)

    local settingsHeight = -y
    content = outer
    table.insert(refreshers, function()
        settings:SetHeight(settingsHeight)
        -- title/description/header (~ top part) + picks + settings
        local top = select(5, picksBlock:GetPoint(1)) or 0
        content:SetHeight(-top + picksBlock:GetHeight() + 6 + settingsHeight)
    end)

    panel:SetScript("OnShow", Refresh)
end

local function InitOptions()
    BuildPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    EC.optionsPanel, EC.optionsCategory = panel, category
    if EC.InitConsumablesPage then EC:InitConsumablesPage() end
end
ns.OnReady(InitOptions)

function EC:OnPicksChanged()
    if panel and panel:IsVisible() then Refresh() end
end

function EC:OpenOptions()
    if InCombatLockdown() then
        ns.Print("options can't be opened in combat.")
        return
    end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
