-- Main window: header (live lockdown status), sidebar (search + Whispers ·
-- Alerts · Search · Quick lines · Settings), scrolling content. The sister
-- addons' window chrome.
local _, ns = ...
local UI = ns.UI

ns.Panels = {}
ns.PanelOrder = {}

-- Panels register themselves: { key, label, render(layout), badge(), setSub(sub) }
function UI.RegisterPanel(p)
    ns.Panels[p.key] = p
    table.insert(ns.PanelOrder, p.key)
end

UI.NAV = { "whispers", "alerts", "search", "quick", "settings" }
UI.DEFAULT = "whispers"
UI.ALIASES = {
    options = { "settings" }, config = { "settings" }, about = { "settings", "About" },
    channels = { "settings", "Channels" }, history = { "settings", "History" },
    input = { "settings", "Input" }, look = { "settings", "Chat look" }, setup = { "setup" },
}

local W, H, SIDE, HEAD = 900, 620, 200, 56
-- Fixed content width: GetWidth() on an anchored frame can be 0 before the first layout pass.
local CONTENT_W = W - SIDE - 2 - 28 - 34 - 6
UI.CONTENT_W = CONTENT_W
local frame

UI.filterText = ""

local function UpdateNav()
    local a = UI.Accent()
    for key, b in pairs(frame.navButtons) do
        local p = ns.Panels[key]
        local selected = frame.current == key
        b.bg:SetColorTexture(1, 1, 1, selected and 0.07 or 0)
        b.bar:SetColorTexture(a[1], a[2], a[3], selected and 1 or 0)
        b.text:SetTextColor(unpack(selected and { 1, 1, 1 } or { 0.84, 0.84, 0.886 }))
        local n = p and p.badge and p.badge() or 0
        if n and n > 0 then
            b.badge.text:SetText(n > 999 and "999+" or tostring(n))
            b.badge:SetWidth(math.max(20, b.badge.text:GetStringWidth() + 12))
            b.badge:Show()
        else
            b.badge:Hide()
        end
    end
    frame.foot:SetText("Settings are shared by all your characters.")
    frame.status:SetText(ns.Lockdown.Status())
    frame.status:SetTextColor(unpack(ns.Lockdown.ChatLocked() and UI.C.warn or UI.C.dim))
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    UpdateNav()
    local key = frame.current
    local p = ns.Panels[key]
    local view = key and frame.views[key]
    if not view then return end
    view.layout:Reset(CONTENT_W)
    local ok, err = pcall(p.render, view.layout)
    if not ok then
        view.layout:Text(UI.Hex(UI.C.bad) .. "This panel hit an error: " .. tostring(err) .. "|r")
        ns.Debug(err)
    end
    view.layout:Finish()
end

function UI.Select(key, sub)
    local alias = UI.ALIASES[key or ""]
    if alias then key, sub = alias[1], sub or alias[2] end
    if not ns.Panels[key] then key = UI.DEFAULT end
    UI.Build()
    if sub and ns.Panels[key].setSub then ns.Panels[key].setSub(sub) end
    if frame.current and frame.views[frame.current] then frame.views[frame.current].content:Hide() end
    frame.current = key
    ns.db.char.window.tab = key
    local view = frame.views[key]
    if not view then
        local content = CreateFrame("Frame", nil, frame.scroll)
        content:SetSize(CONTENT_W + 20, 1)
        view = { content = content, layout = UI.NewLayout(content, CONTENT_W) }
        frame.views[key] = view
    end
    frame.scroll:SetScrollChild(view.content)
    view.content:Show()
    frame.scroll:SetVerticalScroll(0)
    UI.Refresh()
end

-- The sidebar search runs Search over stored chat and whispers.
function UI.SetFilter(text)
    UI.filterText = ns.Trim(text)
    if frame and frame.search and (frame.search:GetText() or "") ~= UI.filterText then
        frame.search:SetText(UI.filterText)
    end
    if frame and frame:IsShown() and frame.current == "search" then UI.Refresh() end
end

local function BuildSearch(parent)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(SIDE - 24, 30)
    box:SetPoint("TOPLEFT", 12, -12)
    UI.Backdrop(box, UI.C.card, UI.C.border)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(10, 8, 0, 0)
    box.hint = UI.Text(box, 12, UI.C.dim)
    box.hint:SetPoint("LEFT", 10, 0)
    box.hint:SetText("Search chat history...")
    box:SetScript("OnTextChanged", function(self, userInput)
        local t = self:GetText() or ""
        self.hint:SetShown(t == "")
        if userInput and ns.Trim(t) ~= UI.filterText then
            UI.filterText = ns.Trim(t)
            if frame.current ~= "search" then UI.Select("search") else UI.Refresh() end
        end
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

function UI.Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "CommsMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    UI.RestorePosition(frame, "main", "CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.SavePosition(self, "main")
    end)
    UI.Backdrop(frame, UI.C.bg, UI.C.border)
    table.insert(UISpecialFrames, "CommsMainFrame")
    frame.views, frame.navButtons = {}, {}

    -- Header
    local head = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEAD)
    UI.Backdrop(head, UI.C.head, { 0, 0, 0, 0 })
    local rule = head:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(unpack(UI.C.softBorder))
    frame.logo = head:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(26, 26)
    frame.logo:SetPoint("LEFT", 18, 0)
    frame.logo:SetTexture(ns.ICON)
    local title = UI.Text(head, 16)
    title:SetPoint("LEFT", frame.logo, "RIGHT", 12, 0)
    title:SetText(ns.TITLE)
    local tag = UI.Text(head, 11, UI.C.dim)
    tag:SetPoint("LEFT", title, "RIGHT", 10, -1)
    tag:SetText("WoW Forever · " .. (tostring(ns.VERSION):match("^v") and ns.VERSION or ("v" .. ns.VERSION)))
    local close = CreateFrame("Button", nil, head, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -8, 0)
    frame.status = UI.Text(head, 12, UI.C.dim)
    frame.status:SetPoint("RIGHT", close, "LEFT", -12, 0)
    frame.status:SetJustifyH("RIGHT")
    frame.status:SetWordWrap(false)

    -- Sidebar
    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 1, -(HEAD + 1))
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDE)
    UI.Backdrop(side, UI.C.side, { 0, 0, 0, 0 })
    local sideRule = side:CreateTexture(nil, "ARTWORK")
    sideRule:SetPoint("TOPRIGHT")
    sideRule:SetPoint("BOTTOMRIGHT")
    sideRule:SetWidth(1)
    sideRule:SetColorTexture(unpack(UI.C.softBorder))
    frame.side = side
    frame.search = BuildSearch(side)

    local y = -60
    for _, key in ipairs(UI.NAV) do
        local p = ns.Panels[key]
        if p then
            local t = CreateFrame("Button", nil, side)
            t:SetSize(SIDE - 24, 34)
            t:SetPoint("TOPLEFT", 12, y)
            t.bg = t:CreateTexture(nil, "BACKGROUND")
            t.bg:SetAllPoints()
            t.bar = t:CreateTexture(nil, "ARTWORK")
            t.bar:SetPoint("TOPLEFT")
            t.bar:SetPoint("BOTTOMLEFT")
            t.bar:SetWidth(3)
            t.text = UI.Text(t, 14)
            t.text:SetPoint("LEFT", 14, 0)
            t.text:SetWordWrap(false)
            t.text:SetText(p.label)
            t.badge = CreateFrame("Frame", nil, t, "BackdropTemplate")
            t.badge:SetSize(22, 18)
            t.badge:SetPoint("RIGHT", -8, 0)
            UI.Backdrop(t.badge, UI.C.neutralBg, { 0, 0, 0, 0 })
            t.badge.text = UI.Text(t.badge, 11)
            t.badge.text:SetPoint("CENTER")
            t.badge.text:SetJustifyH("CENTER")
            t.badge:Hide()
            t:SetScript("OnEnter", function(s) if frame.current ~= key then s.bg:SetColorTexture(1, 1, 1, 0.04) end end)
            t:SetScript("OnLeave", function(s) if frame.current ~= key then s.bg:SetColorTexture(1, 1, 1, 0) end end)
            t:SetScript("OnClick", function() UI.Select(key) end)
            frame.navButtons[key] = t
            y = y - 36
        end
    end
    frame.foot = UI.Text(side, 10, UI.C.dim)
    frame.foot:SetPoint("BOTTOMLEFT", 16, 14)
    frame.foot:SetWidth(SIDE - 28)

    -- Body / scroll
    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    frame.body:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame.body, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 28, -22)
    frame.scroll:SetPoint("BOTTOMRIGHT", -34, 14)

    frame:SetScript("OnShow", function() UI.Refresh() end)
    frame:Hide()
    return frame
end

function UI.IsShown()
    return frame ~= nil and frame:IsShown()
end

function UI.Toggle(key)
    UI.Build()
    if frame:IsShown() and (not key or key == frame.current) then
        frame:Hide()
        return
    end
    frame:Show()
    UI.Select(key or frame.current or ns.db.char.window.tab or UI.DEFAULT)
end

function UI.Open(key, sub)
    UI.Build()
    frame:Show()
    UI.Select(key or frame.current or ns.db.char.window.tab or UI.DEFAULT, sub)
end

function UI.Current()
    return frame and frame.current
end

-- Window positions (account-wide or per character, see DB.Layout).
function UI.SavePosition(f, key)
    local point, _, rel, x, y = f:GetPoint(1)
    if not point then return end
    ns.DB.Layout()[key] = { point = point, rel = rel or point, x = x or 0, y = y or 0 }
end

function UI.RestorePosition(f, key, default, dx, dy)
    local p = ns.DB.Layout()[key]
    f:ClearAllPoints()
    if p and p.point then
        f:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        f:SetPoint(default or "CENTER", UIParent, default or "CENTER", dx or 0, dy or 0)
    end
end
