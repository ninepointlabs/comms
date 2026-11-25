-- Whispers: store and routing for the messenger window (UI/Messenger.lua).
--
-- Captured from our own event frame (CHAT_MSG_WHISPER, _INFORM, BN_WHISPER,
-- BN_WHISPER_INFORM), so it works whatever Tim's chat windows show. In chat
-- lockdown those events are secret: nothing is logged or shown here, Blizzard's
-- chat frame shows them as usual, and the window says so. We don't try to
-- rebuild the hidden lines afterwards (we can't read them either).
--
-- History is account-wide: 200 lines per contact, 50 contacts, oldest pruned.
-- Battle.net whispers get their own tab, keyed by BattleTag (the per-session
-- presence ID changes every login).
local _, ns = ...

local W = {}
ns.Whispers = W

W.EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }
W.bnIDs = {}   -- contact key -> bnetAccountID (this session)
W.lastIncoming = nil

local function S() return ns.DB.Settings().whispers end
local function store() return ns.db.global.whispers end

local function bnInfo(bnetID)
    local bn = C_BattleNet and C_BattleNet.GetAccountInfoByID
    local info = bn and ns.Try(bn, bnetID)
    if type(info) ~= "table" then return nil end
    return info
end

-- Contact key + display for an event.
function W.Contact(event, author, bnetID)
    if event:find("BN_WHISPER", 1, true) then
        local info = type(bnetID) == "number" and bnInfo(bnetID)
        local tag = info and info.battleTag
        if ns.Secret(tag) or type(tag) ~= "string" or tag == "" then return nil end
        local display = tag:match("^([^#]+)") or tag
        return "bn:" .. tag:lower(), display, true
    end
    if type(author) ~= "string" or author == "" then return nil end
    local key = ns.NameKey(author)
    return key and ("w:" .. key), author, false
end

function W.Get(key) return store()[key] end

function W.Count()
    local n = 0
    for _ in pairs(store()) do n = n + 1 end
    return n
end

function W.Unread()
    local n = 0
    for _, c in pairs(store()) do n = n + (c.unread or 0) end
    return n
end

-- Prune to the contact cap, oldest lastSeen first.
function W.Prune()
    local list = {}
    for k, c in pairs(store()) do table.insert(list, { k = k, t = c.lastSeen or 0 }) end
    if #list <= ns.DB.CAPS.whisperContacts then return 0 end
    table.sort(list, function(a, b) return a.t > b.t end)
    local removed = 0
    for i = ns.DB.CAPS.whisperContacts + 1, #list do
        store()[list[i].k] = nil
        removed = removed + 1
    end
    return removed
end

function W.Add(key, display, bnet, dir, text, class)
    local c = store()[key]
    if not c then
        c = { display = display, bnet = bnet or nil, lines = {}, unread = 0 }
        store()[key] = c
    end
    c.display = display or c.display
    c.class = class or c.class
    c.lastSeen = ns.Now()
    table.insert(c.lines, { t = ns.Now(), d = dir, m = text })
    ns.DB.Cap(c.lines, ns.DB.CAPS.whisperLines)
    if dir == "in" then
        c.unread = (c.unread or 0) + 1
        W.lastIncoming = key
    end
    W.Prune()
    ns.Fire("WHISPERS_CHANGED", key, dir)
    return c
end

function W.MarkRead(key)
    local c = store()[key]
    if c and (c.unread or 0) > 0 then
        c.unread = 0
        ns.Fire("WHISPERS_CHANGED", key)
    end
end

function W.Remove(key)
    store()[key] = nil
    ns.Fire("WHISPERS_CHANGED", key)
end

-- Event handler. Returns the contact key on success.
function W.OnEvent(event, ...)
    if not S().enabled then return nil end
    local text, author = ...
    local guid, bnetID = select(12, ...), select(13, ...)
    if ns.Secret(text, author, guid, bnetID) then
        W.lockedSeen = true
        ns.Fire("WHISPERS_LOCKED")
        return nil
    end
    if type(text) ~= "string" then return nil end
    local key, display, bnet = W.Contact(event, author, bnetID)
    if not key then return nil end
    if bnet then W.bnIDs[key] = bnetID end
    local dir = event:find("_INFORM", 1, true) and "out" or "in"
    local class = (not bnet) and ns.Format.ClassOf(guid, author) or nil
    W.Add(key, display, bnet, dir, ns.Plain(text), class)
    if dir == "in" then
        if S().sound and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then ns.Try(PlaySound, SOUNDKIT.TELL_MESSAGE) end
        if S().openOnWhisper and ns.UI.Messenger then ns.UI.Messenger.Open(key, true) end
    end
    return key
end

-- Filter stage: hide whispers from the main chat when the window handles them.
function W.Stage(ctx)
    local s = S()
    if not s.enabled or s.showInMain then return end
    if ctx.type == "WHISPER" or ctx.type == "WHISPER_INFORM" or ctx.type == "BN_WHISPER" or ctx.type == "BN_WHISPER_INFORM" then
        return true
    end
end

-- Reply from the messenger (Enter in our own box = hardware event).
-- Returns "sent" | "prefill" | nil.
function W.Reply(key, text)
    text = ns.Trim(text)
    local c = store()[key]
    if not c or text == "" then return nil end
    if not ns.Lockdown.CanSend() then
        W.ReplyInChat(key, text)
        return "prefill"
    end
    if c.bnet then
        local id = W.bnIDs[key]
        if not id then
            ns.Print(c.display .. " is not online on Battle.net right now.")
            return nil
        end
        return ns.QuickLines.Send(text, "BN_WHISPER", id) and "sent" or nil
    end
    return ns.QuickLines.Send(text, "WHISPER", c.display) and "sent" or nil
end

-- Lockdown fallback: Blizzard's own box as "/w Name ".
function W.ReplyInChat(key, text)
    local c = store()[key]
    if not c then return false end
    -- Battle.net contacts: c.display is the BattleTag name (unverified in game
    -- whether Blizzard's /w resolves it; see STATUS.md).
    return ns.QuickLines.Prefill("/w " .. c.display .. " " .. (text or ""))
end

-- Binding: reply to the last whisper.
function ns.API.ReplyLast()
    if ns.disabled or not ns.db then return end
    local key = W.lastIncoming
    if key and S().enabled and ns.UI.Messenger then
        ns.UI.Messenger.Open(key)
    else
        local who = ns.QuickLines.LastTellTarget()
        if who then ns.QuickLines.Prefill("/w " .. who .. " ") end
    end
end

function ns.API.OpenWhispers()
    if ns.disabled or not ns.db then return end
    if ns.UI.Messenger then ns.UI.Messenger.Toggle() end
end
