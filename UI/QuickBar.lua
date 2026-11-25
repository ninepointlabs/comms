-- Quick-bar: a small movable row of quick-line buttons (short labels).
-- A click is a hardware event, so SAY / EMOTE / CHANNEL lines can send.
-- Drag the handle to move; optional hide in combat. Plain buttons, not
-- secure ones, so showing/hiding works in combat too.
local _, ns = ...
local UI = ns.UI

local Bar = {}
UI.QuickBar = Bar

local bar
local BTN_W, BTN_H, GAP = 48, 22, 3

local function build()
    bar = CreateFrame("Frame", "CommsQuickBar", UIParent, "BackdropTemplate")
    bar:SetSize(16 + ns.QuickLines.COUNT * (BTN_W + GAP), BTN_H + 8)
    UI.RestorePosition(bar, "quickbar", "BOTTOM", 0, 180)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    UI.Backdrop(bar, { 0.051, 0.051, 0.078, 0.75 }, UI.C.softBorder)
    local handle = CreateFrame("Frame", nil, bar)
    handle:SetSize(12, BTN_H)
    handle:SetPoint("LEFT", 3, 0)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() bar:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        UI.SavePosition(bar, "quickbar")
    end)
    local grip = handle:CreateTexture(nil, "ARTWORK")
    grip:SetAllPoints()
    grip:SetColorTexture(unpack(UI.C.border))
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Comms quick-bar: drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.buttons = {}
    for i = 1, ns.QuickLines.COUNT do
        local b = UI.Button(bar, "", BTN_W, BTN_H)
        b:SetPoint("LEFT", 18 + (i - 1) * (BTN_W + GAP), 0)
        b.index = i
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then
                UI.Open("quick")
            else
                ns.QuickLines.Fire(self.index, "click")
            end
        end)
        bar.buttons[i] = b
    end
    return bar
end

function Bar.Refresh()
    local s = ns.DB.Settings().quick
    if not s.bar then
        if bar then bar:Hide() end
        return
    end
    bar = bar or build()
    for i, b in ipairs(bar.buttons) do
        local line = ns.QuickLines.Lines()[i]
        local label = line and ns.Trim(line.label or "") or ""
        if label == "" and line then label = (line.text or ""):sub(1, 6) end
        b.label:SetText(label ~= "" and label or tostring(i))
        local key = GetBindingKey and ns.Try(GetBindingKey, "COMMS_QUICKLINE_" .. i)
        b.tip = line and ("%s\n|cff9a9ab0%s%s|r\nRight-click: edit"):format(ns.Escape(line.text or ""),
            line.channel == "auto" and "auto channel" or tostring(line.channel),
            key and ("  ·  key: " .. key) or "") or nil
    end
    local hide = s.barHideInCombat and ns.Lockdown.CombatLocked()
    bar:SetShown(not hide)
end

function Bar.Get() return bar end

ns.On("COMBAT_CHANGED", function() Bar.Refresh() end)
