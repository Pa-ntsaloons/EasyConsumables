-- EasyConsumables: "Consumables" options page.
-- Lists every consumable you've had, sorted into categories, with an on/off switch each.
-- Off = on the ignore list (the same list /ec ignore uses), so it's never picked.

local _, ns = ...
local EC = ns.EC
local Compat = ns.Compat

local CATEGORIES = {
    { key = "f", label = "Food" },
    { key = "d", label = "Drink" },
    { key = "b", label = "Buff Food", note = "Also needs \"Use buff food\" on the main page." },
    { key = "h", label = "Health Potions & Healthstones" },
    { key = "m", label = "Mana Potions & Gems" },
    { key = "n", label = "Bandages" },
    { key = "?", label = "Other ignored items", note = "Ignored with /ec ignore but not seen in your bags yet." },
}

local PAD = 16
local ROW_H = 22
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local page, sub, content
local rows, headers = {}, {}
local onlyInBags = false

local function ItemName(id)
    local name = Compat.GetItemName(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name
end

---------------------------------------------------------------------------
-- Pooled widgets
---------------------------------------------------------------------------

local function Header(i)
    if headers[i] then return headers[i] end
    local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetJustifyH("LEFT")
    h.note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    h.note:SetJustifyH("LEFT")
    h.note:SetPoint("LEFT", h, "RIGHT", 8, 0)
    headers[i] = h
    return h
end

local Refresh

local function Row(i)
    if rows[i] then return rows[i] end
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetSize(ROW_H, ROW_H)
    cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cb.icon = cb:CreateTexture(nil, "ARTWORK")
    cb.icon:SetSize(18, 18)
    cb.icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb.icon, "RIGHT", 6, 0)
    cb.text:SetJustifyH("LEFT")
    cb:SetHitRectInsets(0, -320, 0, 0)
    cb:SetScript("OnClick", function(self, button)
        local id = self.itemID
        if button == "RightButton" then
            -- Remove it from this page and turn it back on. It returns if it's in your bags again.
            EC.db.seen[id] = nil
            EC.db.ignored[id] = nil
        else
            EC.db.ignored[id] = (not self:GetChecked()) or nil
        end
        EC:RequestUpdate()
        Refresh()
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("On: can be used. Off: never used (ignored).", 0, 1, 0, true)
        GameTooltip:AddLine("Right-click to remove it from this page.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = cb
    return cb
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

Refresh = function()
    if not page or not EC.db then return end
    local db = EC.db

    -- Group item IDs by category letter.
    local groups = {}
    for _, c in ipairs(CATEGORIES) do groups[c.key] = {} end
    for id, cats in pairs(db.seen) do
        for letter in cats:gmatch(".") do
            if groups[letter] then table.insert(groups[letter], id) end
        end
    end
    for id in pairs(db.ignored) do
        if not db.seen[id] then table.insert(groups["?"], id) end
    end

    local y = -108 -- below the title, description and filter checkbox
    local hi, ri = 0, 0
    local total = 0
    for _, c in ipairs(CATEGORIES) do
        local ids = {}
        for _, id in ipairs(groups[c.key]) do
            local count = GetCount and GetCount(id) or 0
            if not onlyInBags or count > 0 then table.insert(ids, id) end
        end
        if #ids > 0 then
            local names = {}
            for _, id in ipairs(ids) do names[id] = ItemName(id) end
            table.sort(ids, function(a, b) return (names[a] or ("~" .. a)) < (names[b] or ("~" .. b)) end)

            hi = hi + 1
            local h = Header(hi)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y - 8)
            h:SetText(("%s  |cff888888(%d)|r"):format(c.label, #ids))
            h.note:SetText(c.note or "")
            h:Show()
            h.note:Show()
            y = y - 30

            for _, id in ipairs(ids) do
                ri = ri + 1
                total = total + 1
                local cb = Row(ri)
                cb.itemID = id
                cb:ClearAllPoints()
                cb:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, y)
                local on = not db.ignored[id]
                cb:SetChecked(on)
                cb.icon:SetTexture(Compat.GetItemIcon(id) or 134400)
                cb.icon:SetDesaturated(not on)
                cb.icon:SetAlpha(on and 1 or 0.5)
                local _, _, quality = Compat.GetItemInfo(id)
                local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                    and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
                if not on then color = "|cff808080" end
                local count = GetCount and GetCount(id) or 0
                cb.text:SetText(("%s%s|r  |cff888888%s|r"):format(color, names[id] or ("item " .. id),
                    count > 0 and ("x" .. count) or "not in bags"))
                cb:Show()
                y = y - ROW_H
            end
        end
    end
    for i = hi + 1, #headers do headers[i]:Hide(); headers[i].note:Hide() end
    for i = ri + 1, #rows do rows[i]:Hide() end

    page.empty:SetShown(total == 0)
    content:SetHeight(-y + PAD)
end

---------------------------------------------------------------------------
-- Build / register / open
---------------------------------------------------------------------------

local function Build()
    page = CreateFrame("Frame")
    page.name = "Consumables"
    page.parent = "EasyConsumables"

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 100)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(math.max(360, w)) end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("Consumables")

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", PAD, -PAD - 32)
    desc:SetPoint("TOPRIGHT", -PAD, -PAD - 32)
    desc:SetJustifyH("LEFT")
    desc:SetText("Every consumable you've had. Turn one off and it's never used; it goes on the ignore list "
        .. "(the same as /ec ignore). Items appear here once they've been in your bags.")

    local filter = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    filter:SetSize(22, 22)
    filter:SetPoint("TOPLEFT", PAD, -PAD - 66)
    filter.text = filter:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    filter.text:SetPoint("LEFT", filter, "RIGHT", 4, 0)
    filter.text:SetText("Only show items in my bags")
    filter:SetHitRectInsets(0, -180, 0, 0)
    filter:SetScript("OnClick", function(self)
        onlyInBags = self:GetChecked() and true or false
        Refresh()
    end)

    page.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    page.empty:SetPoint("TOPLEFT", PAD, -116)
    page.empty:SetText("Nothing here yet. Consumables show up once they've been in your bags.")

    page:SetScript("OnShow", Refresh)
end

function EC:InitConsumablesPage()
    Build()
    if Settings and Settings.RegisterCanvasLayoutSubcategory and self.optionsCategory then
        sub = Settings.RegisterCanvasLayoutSubcategory(self.optionsCategory, page, page.name)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
end

function EC:OpenConsumables()
    if InCombatLockdown() then
        print("|cff33ff99EasyConsumables|r: options can't be opened in combat.")
        return
    end
    if sub and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(sub:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(page)
        InterfaceOptionsFrame_OpenToCategory(page)
    end
end

-- New items seen, or names finished loading: redraw if the page is open.
local pending = false
local function RefreshSoon()
    if pending or not (page and page:IsVisible()) then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        Refresh()
    end)
end

function EC:OnSeenChanged() RefreshSoon() end

local f = CreateFrame("Frame")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", RefreshSoon)
