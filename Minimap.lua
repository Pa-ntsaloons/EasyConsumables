-- EasyConsumables: minimap button.
--   Left-click: options. Right-click: Consumables page. Shift-click: rescan bags.
--   Drag to move it around the minimap edge (works for round and square minimaps).
-- Settings (db.minimap): show, fade (hidden until the mouse is over the minimap or the button), angle.

local _, ns = ...
local EC = ns.EC

local ICON = "Interface\\Icons\\INV_Misc_Food_15"
local FADE_SPEED = 4 -- alpha per second
local HIDDEN_ALPHA = 0

local button, fader

-- Which quadrants of each minimap shape are round (true) or square (false), as LibDBIcon does.
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local atan2 = math.atan2 or atan2

local function Settings() return EC.db.minimap end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------

local function UpdatePosition()
    local angle = math.rad(Settings().angle or 220)
    local x, y = math.cos(angle), math.sin(angle)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    local round = (SHAPES[shape] or SHAPES.ROUND)[q]
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    if round then
        x, y = x * w, y * h
    else
        local dw = math.sqrt(2 * w * w) - 10
        local dh = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    Settings().angle = math.deg(atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

---------------------------------------------------------------------------
-- Fading: fully visible while the mouse is over the minimap or the button (or while dragging).
---------------------------------------------------------------------------

local function Hovered()
    return button.dragging or button:IsMouseOver() or Minimap:IsMouseOver()
end

local function FadeStep(_, elapsed)
    local target = Hovered() and 1 or HIDDEN_ALPHA
    local a = button:GetAlpha()
    if a == target then return end
    local step = FADE_SPEED * elapsed
    if a < target then a = math.min(target, a + step) else a = math.max(target, a - step) end
    button:SetAlpha(a)
end

local function ApplyFade()
    if Settings().show and Settings().fade then
        fader:SetScript("OnUpdate", FadeStep)
        button:SetAlpha(Hovered() and 1 or HIDDEN_ALPHA)
    else
        fader:SetScript("OnUpdate", nil)
        button:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- Tooltip and clicks
---------------------------------------------------------------------------

local PICK_LINES = {
    { "food", "Food" }, { "drink", "Drink" }, { "health", "Health" }, { "mana", "Mana" }, { "bandage", "Bandage" },
}

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("EasyConsumables", 1, 1, 1)
    local picks = EC.picks or {}
    for _, l in ipairs(PICK_LINES) do
        local p = picks[l[1]]
        if EC.db.macros[l[1]] then
            GameTooltip:AddDoubleLine(l[2], p and ns.Compat.ItemLabel(p.itemID, p.info.name) or "|cff888888none|r",
                1, 0.82, 0, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: options", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Consumables page", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Shift-click: rescan bags", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnClick(_, mouseButton)
    if mouseButton == "RightButton" then
        EC:OpenConsumables()
    elseif IsShiftKeyDown() then
        EC:ClearCache()
        EC:Update()
        ns.Print(InCombatLockdown() and "will update after combat." or "macros updated.")
    else
        EC:OpenOptions()
    end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function Create()
    button = CreateFrame("Button", "EasyConsumablesMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:LockHighlight()
        GameTooltip:Hide()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    fader = CreateFrame("Frame")
end

local function Apply()
    if not button then return end
    button:SetShown(Settings().show)
    UpdatePosition()
    ApplyFade()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

function EC:SetMinimapButtonShown(show)
    Settings().show = show and true or false
    Apply()
end

function EC:SetMinimapButtonFade(fade)
    Settings().fade = fade and true or false
    Apply()
end

function EC:ToggleMinimapButton()
    self:SetMinimapButtonShown(not Settings().show)
    ns.Print("minimap button " .. (Settings().show and "shown." or "hidden. /ec minimap shows it again."))
    if self.OnPicksChanged then self:OnPicksChanged() end -- refresh the options page checkbox
end

ns.OnReady(function()
    Create()
    Apply()
end)

-- Minimap size and shape can change after load (other addons square it, resize it).
EC:On("PLAYER_ENTERING_WORLD", Apply)
