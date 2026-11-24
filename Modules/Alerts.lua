-- Alerts: my name and keywords in chat -> sound, tab flash, and an entry in
-- the Alerts list. Case-insensitive; whole-word by default. Locked (secret)
-- lines never reach here (Filters bails out first).
local _, ns = ...

local Alerts = {}
ns.Alerts = Alerts

Alerts.SOUNDS = {
    { key = "RAID_WARNING", label = "Raid warning" },
    { key = "READY_CHECK", label = "Ready check" },
    { key = "TELL_MESSAGE", label = "Whisper" },
    { key = "IG_PLAYER_INVITE", label = "Invite" },
}

-- Event types that can alert (not my own sends, not system).
Alerts.TYPES = {
    SAY = true, YELL = true, EMOTE = true, PARTY = true, PARTY_LEADER = true, RAID = true, RAID_LEADER = true,
    RAID_WARNING = true, INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true, GUILD = true, OFFICER = true,
    CHANNEL = true, WHISPER = true, BN_WHISPER = true,
}

Alerts.unread = 0

local function S() return ns.DB.Settings().alerts end

-- Words to watch: my name (if on) + keywords.
function Alerts.Words()
    local s, out = S(), {}
    if s.myName then
        local me = ns.MyName()
        if me then table.insert(out, me) end
    end
    for _, k in ipairs(s.keywords or {}) do
        k = ns.Trim(k)
        if k ~= "" then table.insert(out, k) end
    end
    return out
end

-- First matching word in text, or nil.
function Alerts.Match(text, words, wholeWord)
    if type(text) ~= "string" then return nil end
    local plain = ns.Plain(text):lower()
    for _, w in ipairs(words) do
        local lw = w:lower()
        if wholeWord then
            local p = "%f[%w]" .. ns.Links.EscapePattern(lw) .. "%f[%W]"
            if plain:find(p) then return w end
        elseif plain:find(lw, 1, true) then
            return w
        end
    end
    return nil
end

function Alerts.Add(entry)
    local list = ns.db.global.alerts
    table.insert(list, entry)
    ns.DB.Cap(list, ns.DB.CAPS.alerts)
    Alerts.unread = Alerts.unread + 1
    ns.Fire("ALERTS_CHANGED")
end

function Alerts.MarkRead()
    Alerts.unread = 0
    ns.Fire("ALERTS_CHANGED")
end

function Alerts.Clear()
    wipe(ns.db.global.alerts)
    Alerts.MarkRead()
end

function Alerts.Notify(frame)
    local s = S()
    if s.sound and PlaySound and SOUNDKIT then
        local id = SOUNDKIT[s.soundKit or "RAID_WARNING"] or SOUNDKIT.RAID_WARNING
        if id then ns.Try(PlaySound, id) end
    end
    if s.flash and frame and FCF_StartAlertFlash and not ns.Lockdown.Busy() then
        ns.Try(FCF_StartAlertFlash, frame)
    end
end

-- Filter stage (first frame only).
function Alerts.Stage(ctx)
    local s = S()
    if not s.enabled or not ctx.first or not Alerts.TYPES[ctx.type] then return end
    local author = ctx.author
    local me = ns.MyName()
    if type(author) == "string" and me and ns.SplitName(author) == me then return end
    local word = Alerts.Match(ctx.msg, Alerts.Words(), s.wholeWord)
    if not word then return end
    local channel = ctx.type
    if channel == "CHANNEL" and type(ctx.args[9]) == "string" and ctx.args[9] ~= "" then channel = ctx.args[9] end
    Alerts.Add({ t = ns.Now(), who = author, text = ns.Plain(ctx.msg), word = word, channel = channel })
    Alerts.Notify(ctx.frame)
end
