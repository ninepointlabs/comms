-- Messenger: one movable window, a tab per person (Battle.net friends get
-- their own tabs), unread badges, class colours, timestamps, and a reply box.
--
-- Lockdown: whisper events are secret, so the window can't show them. The
-- header says so, and the reply box becomes "Reply in chat" (Blizzard's box
-- as "/w Name ").
local _, ns = ...
local UI = ns.UI

local M = {}
UI.Messenger = M

local W, H, LIST = 560, 380, 150
local frame
M.current = nil

local function contacts()
    local list = {}
    for key, c in pairs(ns.db.global.whispers) do table.insert(list, { key = key, c = c }) end
    table.sort(list, function(a, b) return (a.c.lastSeen or 0) > (b.c.lastSeen or 0) end)
    return list
end
M.Contacts = contacts

local function nameColored(c)
    if c.bnet then return "|cff82c5ff" .. ns.Escape(c.display) .. "|r" end
    local hex = ns.Format.ClassHex(c.class)
    return (hex or "|cffffffff") .. ns.Escape(ns.ShortName(c.display)) .. "|r"
end
M.NameColored = nameColored

function M.FormatLine(c, l)
    local when = date("%H:%M", l.t or 0)
    local who = l.d == "out" and "|cffb0b0b0You|r" or nameColored(c)
    return ("|cff8a8a8a%s|r %s: %s"):format(when, who, ns.Escape(l.m or ""))
end

local function build()
    frame = CreateFrame("Frame", "CommsMessenger", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    UI.RestorePosition(frame, "messenger", "CENTER", 260, 80)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.SavePosition(self, "messenger")
    end)
    UI.Backdrop(frame, UI.C.bg, UI.C.border)
    table.insert(UISpecialFrames, "CommsMessenger")

    frame.title = UI.Text(frame, 14)
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetWordWrap(false)
    frame.title:SetText("Whispers")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    frame.banner = UI.Text(frame, 12, UI.C.warn)
    frame.banner:SetPoint("TOPLEFT", 14, -32)
    frame.banner:SetWidth(W - 28)
    frame.banner:SetText("Chat is locked here; whispers show in main chat.")

    -- Contact list
    frame.list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.list:SetPoint("TOPLEFT", 10, -52)
    frame.list:SetPoint("BOTTOMLEFT", 10, 10)
    frame.list:SetWidth(LIST)
    UI.Backdrop(frame.list, UI.C.side, UI.C.softBorder)
    frame.tabs = {}

    -- Messages
    frame.msgs = CreateFrame("ScrollingMessageFrame", nil, frame)
    frame.msgs:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 10, -4)
    frame.msgs:SetPoint("BOTTOMRIGHT", -12, 46)
    frame.msgs:SetFontObject(ChatFontNormal)
    frame.msgs:SetJustifyH("LEFT")
    frame.msgs:SetFading(false)
    frame.msgs:SetMaxLines(ns.DB.CAPS.whisperLines)
    frame.msgs:EnableMouseWheel(true)
    frame.msgs:SetScript("OnMouseWheel", function(self, d) if d > 0 then self:ScrollUp() else self:ScrollDown() end end)

    -- Reply box (our own EditBox: Enter is a hardware event)
    frame.reply = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    frame.reply:SetPoint("BOTTOMLEFT", frame.list, "BOTTOMRIGHT", 10, 0)
    frame.reply:SetPoint("BOTTOMRIGHT", -12, 10)
    frame.reply:SetHeight(28)
    UI.Backdrop(frame.reply, UI.C.card, UI.C.border)
    frame.reply:SetAutoFocus(false)
    frame.reply:SetFontObject(ChatFontNormal)
    frame.reply:SetTextInsets(8, 8, 0, 0)
    frame.reply:SetMaxLetters(255)
    frame.reply:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.reply:SetScript("OnEnterPressed", function(self) M.SendReply(self:GetText()) end)

    frame.inChat = UI.Button(frame, "Reply in chat", 140, 28, function() M.ReplyInChat() end)
    frame.inChat:SetPoint("BOTTOMLEFT", frame.list, "BOTTOMRIGHT", 10, 0)

    frame.empty = UI.Text(frame, 13, UI.C.dim)
    frame.empty:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 14, -10)
    frame.empty:SetWidth(W - LIST - 50)
    frame.empty:SetText("No whispers yet. They'll show here (and in main chat, unless you turn that off in Settings › Whispers).")

    frame:SetScript("OnShow", function() M.Refresh() end)
    frame:Hide()
    return frame
end

function M.Build() return frame or build() end

function M.IsShown() return frame ~= nil and frame:IsShown() end

local function tabButton(i)
    local t = frame.tabs[i]
    if t then return t end
    t = CreateFrame("Button", nil, frame.list, "BackdropTemplate")
    t:SetSize(LIST - 8, 26)
    t:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 28)
    UI.Backdrop(t, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    t.text = UI.Text(t, 12)
    t.text:SetPoint("LEFT", 8, 0)
    t.text:SetWidth(LIST - 44)
    t.text:SetWordWrap(false)
    t.badge = UI.Text(t, 11, UI.C.bad)
    t.badge:SetPoint("RIGHT", -6, 0)
    t:SetScript("OnClick", function(self) M.Select(self.key) end)
    frame.tabs[i] = t
    return t
end

function M.Refresh()
    if not frame or not frame:IsShown() then return end
    local locked = ns.Lockdown.ChatLocked()
    frame.banner:SetShown(locked)
    frame.reply:SetShown(not locked)
    frame.inChat:SetShown(locked)
    local list = contacts()
    local maxTabs = math.floor((H - 70) / 28)
    for i = 1, math.max(#frame.tabs, math.min(#list, maxTabs)) do
        local t = tabButton(i)
        local e = list[i]
        if e and i <= maxTabs then
            t.key = e.key
            t.text:SetText(nameColored(e.c))
            local u = e.c.unread or 0
            t.badge:SetText(u > 0 and tostring(u) or "")
            t:SetBackdropColor(unpack(M.current == e.key and UI.C.cardHover or { 0, 0, 0, 0 }))
            t:Show()
        else
            t:Hide()
        end
    end
    if not M.current or not ns.db.global.whispers[M.current] then
        M.current = list[1] and list[1].key or nil
    end
    frame.empty:SetShown(M.current == nil)
    frame.msgs:Clear()
    local c = M.current and ns.db.global.whispers[M.current]
    if c then
        frame.title:SetText("Whispers · " .. nameColored(c))
        for _, l in ipairs(c.lines or {}) do frame.msgs:AddMessage(M.FormatLine(c, l)) end
        ns.Whispers.MarkRead(M.current)
    else
        frame.title:SetText("Whispers")
    end
end

function M.Select(key)
    M.current = key
    M.Refresh()
end

function M.Open(key, noFocus)
    M.Build()
    if key then M.current = key end
    frame:Show()
    M.Refresh()
    if not noFocus and frame.reply:IsShown() and not ns.Lockdown.Busy() then frame.reply:SetFocus() end
end

function M.Toggle()
    M.Build()
    if frame:IsShown() then frame:Hide() else M.Open(nil, true) end
end

function M.SendReply(text)
    if not M.current then return nil end
    local r = ns.Whispers.Reply(M.current, text)
    if r and frame then frame.reply:SetText("") end
    return r
end

function M.ReplyInChat()
    if not M.current then return false end
    return ns.Whispers.ReplyInChat(M.current, "")
end

ns.On("WHISPERS_CHANGED", function() M.Refresh() end)
ns.On("LOCKDOWN_CHANGED", function() M.Refresh() end)
