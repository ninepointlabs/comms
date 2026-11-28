-- Quick-bar: a small movable bar with two rows of quick-line buttons.
--   Row 1: the active situational set (World / Party / Raid) with a set tab
--          at the left (click: next set, right-click: back to automatic).
--   Row 2: the Combat set, always visible when the bar is shown (also in
--          combat, also with "hide in combat" on) unless the Combat row is off.
-- A click is a hardware event, so SAY / EMOTE / CHANNEL lines can send.
--
-- Plain buttons, not secure ones. Even so the bar never re-lays out in combat
-- (Bar.Layout runs out of combat only; a set change in combat waits for
-- PLAYER_REGEN_ENABLED), so buttons never jump under the mouse mid-fight.
-- The only thing that changes in combat is "hide in combat" hiding row 1.
local _, ns = ...
local UI = ns.UI

local Bar = {}
UI.QuickBar = Bar

local bar
local BTN_W, BTN_H, GAP, TAB_W = 48, 22, 3, 46
local MAX = 10
local LOCKDOWN_TIP = "In dungeons/raids/BGs this fills the chat box; press Enter."

Bar.layouts = 0  -- Layout() calls (tests: none in combat)
Bar.dirty = false -- something changed in combat; lay out when it ends

local function tooltip(self, text)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function makeRow(parent, setKey)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(TAB_W + 8 + MAX * (BTN_W + GAP), BTN_H + 6)
    UI.Backdrop(row, { 0.051, 0.051, 0.078, 0.75 }, UI.C.softBorder)
    row.setKey = setKey
    row.buttons = {}
    for i = 1, MAX do
        local b = UI.Button(row, "", BTN_W, BTN_H)
        b.index = i
        b.setKey = setKey
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then
                UI.Open("quick", self.setKey or ns.QuickSets.Active())
            else
                ns.QuickLines.Fire(self.index, "click", self.setKey)
            end
        end)
        row.buttons[i] = b
    end
    return row
end

local function build()
    bar = CreateFrame("Frame", "CommsQuickBar", UIParent)
    bar:SetSize(16 + TAB_W + 8 + MAX * (BTN_W + GAP), 2 * (BTN_H + 6) + 2)
    UI.RestorePosition(bar, "quickbar", "BOTTOM", 0, 180)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(false)
    local handle = CreateFrame("Frame", nil, bar)
    handle:SetSize(12, 2 * BTN_H + 8)
    handle:SetPoint("TOPLEFT", 0, -3)
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
    handle:SetScript("OnEnter", function(self) tooltip(self, "Comms quick-bar: drag to move") end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Row 1: situational set. Buttons fire the active set (setKey nil).
    bar.main = makeRow(bar, nil)
    bar.main:SetPoint("TOPLEFT", bar, "TOPLEFT", 16, 0)
    local tab = UI.Button(bar.main, "", TAB_W, BTN_H)
    tab:SetPoint("LEFT", 3, 0)
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab:SetScript("OnClick", function(_, mouse)
        if ns.Lockdown.CombatLocked() then
            ns.Print("Quick-line sets switch out of combat only.")
            return
        end
        if mouse == "RightButton" then ns.QuickSets.Pick("auto") else ns.QuickSets.Cycle() end
        ns.Print(ns.QuickSets.Describe())
        UI.Refresh()
    end)
    bar.tab = tab

    -- Row 2: Combat. Fixed position below row 1, so hiding row 1 in combat
    -- never moves it.
    bar.combat = makeRow(bar, "combat")
    bar.combat:SetPoint("TOPLEFT", bar, "TOPLEFT", 16, -(BTN_H + 6 + 2))
    local tag = UI.Text(bar.combat, 11, UI.C.warn)
    tag:SetPoint("LEFT", 6, 0)
    tag:SetWidth(TAB_W - 4)
    tag:SetText("Combat")
    bar.combatTag = tag
    return bar
end

local function channelText(line)
    if line.channel == "auto" or not line.channel then return "auto channel" end
    if line.channel == "WHISPER" then return "whisper " .. tostring(line.target or "auto") end
    if line.channel == "CHANNEL" then return "channel " .. tostring(line.target or "") end
    return tostring(line.channel)
end

-- Fill a row's buttons from a set's lines; empty lines are hidden and the
-- rest packed left. Returns how many are shown.
local function fillRow(row, setKey, bindingPrefix, bindingMax)
    local lines = setKey and ns.QuickLines.Lines(setKey) or {}
    local shown = 0
    for _, b in ipairs(row.buttons) do b:Hide() end
    for i = 1, MAX do
        local line = lines[i]
        local text = line and ns.Trim(line.text or "") or ""
        if text ~= "" then
            shown = shown + 1
            local b = row.buttons[shown]
            b.index = i
            b:ClearAllPoints()
            b:SetPoint("LEFT", TAB_W + 6 + (shown - 1) * (BTN_W + GAP), 0)
            local label = ns.Trim(line.label or "")
            if label == "" then label = text:sub(1, 6) end
            b.label:SetText(label)
            local key = i <= bindingMax and GetBindingKey and ns.Try(GetBindingKey, bindingPrefix .. i)
            local tip = ("%s\n|cff9a9ab0%s%s|r"):format(ns.Escape(line.text or ""), channelText(line),
                key and ("  ·  key: " .. key) or "")
            if setKey ~= "world" then tip = tip .. "\n|cffffc14d" .. LOCKDOWN_TIP .. "|r" end
            if bindingPrefix == "COMMS_QUICKLINE_" and i <= bindingMax then
                tip = tip .. "\n|cff9a9ab0Quick line " .. i .. " key fires this slot of the active set.|r"
            end
            b.tip = tip .. "\nRight-click: edit"
            b:Show()
        end
    end
    row:SetWidth(TAB_W + 8 + math.max(shown, 1) * (BTN_W + GAP))
    return shown
end

local function combatRowWanted()
    local wanted = ns.QuickSets.CombatRowWanted()
    if wanted == nil then return bar and bar.combat:IsShown() end -- can't tell: keep as is
    return wanted
end

-- Labels, slots, row visibility. Out of combat only.
function Bar.Layout()
    -- The first layout (bar just built, e.g. /reload in combat) always runs:
    -- there's nothing on screen yet to move.
    if ns.Lockdown.CombatLocked() and bar.laidOut then
        Bar.dirty = true
        return false
    end
    Bar.layouts = Bar.layouts + 1
    Bar.dirty = false
    bar.laidOut = true
    local Sets = ns.QuickSets
    local active = Sets.Active()
    bar.activeSet = active
    local n = fillRow(bar.main, active, "COMMS_QUICKLINE_", 10)
    local name = active and Sets.SHORT[active] or "Off"
    bar.tab.label:SetText(name .. (Sets.Pinned() and "*" or ""))
    bar.tab.tip = ("Quick lines: %s%s\nClick: next set · Right-click: automatic\nSets switch out of combat only."):format(
        active and Sets.NAMES[active] or "all sets off", Sets.Pinned() and " (pinned)" or "")
    bar.mainWanted = active ~= nil or n > 0
    bar.combatWanted = combatRowWanted() and fillRow(bar.combat, "combat", "COMMS_COMBATLINE_", 5) > 0
    bar.combat:SetShown(bar.combatWanted)
    return true
end

function Bar.Refresh()
    local s = ns.DB.Settings().quick
    if not s.bar then
        if bar then bar:Hide() end
        return
    end
    bar = bar or build()
    Bar.Layout() -- no-op (marks dirty) in combat once laid out
    -- In combat only row 1 may hide ("hide in combat"); the Combat row and
    -- every button stay exactly where they were.
    local hideMain = s.barHideInCombat and ns.Lockdown.CombatLocked()
    bar.main:SetShown(bar.mainWanted and not hideMain)
    bar:Show()
end

function Bar.Get() return bar end

ns.On("COMBAT_CHANGED", function() Bar.Refresh() end)
ns.On("QUICKSET_CHANGED", function() Bar.Refresh() end)
