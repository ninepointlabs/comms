-- Quick lines: editable lines (up to 10 per set) fired from the quick-bar
-- (click) or a key binding (key). Lines live in situational sets
-- (QuickSets.lua): COMMS_QUICKLINE_n fires slot n of the active set,
-- COMMS_COMBATLINE_n slot n of the Combat set. Both are hardware events, which SAY / YELL / EMOTE / CHANNEL
-- need on Forever. Nothing here ever sends on a timer or an event.
--
-- In chat lockdown addons can't send at all, so the line is prefilled into
-- Blizzard's chat box (ChatFrameUtil.OpenChat) and Tim presses Enter.
--
-- Tokens: %t target, %f focus, %z zone, %r my role (Settings), %d dungeon:
-- a line with %d is always prefilled so Tim can type the dungeon name there.
local _, ns = ...

local Q = {}
ns.QuickLines = Q

Q.COUNT = 10
-- Chat types that need a hardware event (click or key) outside lockdown.
Q.NEEDS_HW = { SAY = true, YELL = true, EMOTE = true, CHANNEL = true }
-- Sources that are hardware events.
Q.HW_SOURCES = { click = true, key = true, slash = true }
Q.CHANNELS = { "auto", "SAY", "PARTY", "RAID", "INSTANCE_CHAT", "GUILD", "OFFICER", "WHISPER", "YELL", "EMOTE", "CHANNEL" }
Q.SLASH = {
    SAY = "/s", YELL = "/y", EMOTE = "/e", PARTY = "/p", RAID = "/raid", INSTANCE_CHAT = "/i",
    GUILD = "/g", OFFICER = "/o", RAID_WARNING = "/rw",
}

local function S() return ns.DB.Settings().quick end

-- Lines of a set (default: the active situational set).
function Q.Lines(setKey) return ns.QuickSets.Lines(setKey) end

-- auto = INSTANCE_CHAT > RAID > PARTY > SAY
function Q.AutoChannel()
    local instanceCat = LE_PARTY_CATEGORY_INSTANCE or 2
    if ns.SafeCall(IsInGroup, instanceCat) then return "INSTANCE_CHAT" end
    if ns.SafeCall(IsInRaid) then return "RAID" end
    if ns.SafeCall(IsInGroup) then return "PARTY" end
    return "SAY"
end

local function unitName(unit)
    if not ns.SafeCall(UnitExists, unit) then return nil end
    local n, r = ns.Try(UnitName, unit)
    if ns.Secret(n, r) or type(n) ~= "string" then return nil end
    if type(r) == "string" and r ~= "" then return n .. "-" .. r end
    return n
end

function Q.LastTellTarget()
    local u = ChatFrameUtil
    local name = u and u.GetLastTellTarget and ns.Try(u.GetLastTellTarget)
    if not ns.Secret(name) and type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Replace tokens. Returns text, needsTyping (a %d was present), and the byte
-- position of the first %d in the result (where the cursor should go).
function Q.Expand(text)
    local needsTyping, dPos = false, nil
    text = tostring(text or "")
    local out, pos = {}, 1
    while true do
        local s, e, c = text:find("%%(%a)", pos)
        if not s then break end
        table.insert(out, text:sub(pos, s - 1))
        local rep
        if c == "t" then rep = unitName("target") or "%t"
        elseif c == "f" then rep = unitName("focus") or "%f"
        elseif c == "z" then rep = (ns.Try(GetRealZoneText) or ns.Try(GetZoneText) or "")
        elseif c == "r" then rep = ns.db.char.role or "DPS"
        elseif c == "d" then
            needsTyping = true
            rep = ""
            if not dPos then dPos = #table.concat(out) end
        else rep = "%" .. c end
        table.insert(out, rep)
        pos = e + 1
    end
    table.insert(out, text:sub(pos))
    return table.concat(out), needsTyping, dPos
end

-- Where a quick line goes: chatType, target (whisper name or channel number).
function Q.Resolve(line)
    local ch = line.channel or "auto"
    if ch == "auto" then return Q.AutoChannel(), nil end
    if ch == "WHISPER" then
        local t = line.target or "auto"
        local who
        if t == "target" then who = unitName("target")
        elseif t == "last" then who = Q.LastTellTarget()
        elseif t == "auto" or t == "" then
            who = (ns.SafeCall(UnitExists, "target") and ns.SafeCall(UnitIsPlayer, "target")) and unitName("target") or Q.LastTellTarget()
        else who = t end
        if who then return "WHISPER", who end
        return "SAY", nil -- brief: whisper target/last whisperer, or SAY
    end
    if ch == "CHANNEL" then
        local name = line.target or "LookingForGroup"
        local num = GetChannelName and ns.Try(GetChannelName, name)
        if type(num) == "number" and num > 0 then return "CHANNEL", num end
        -- Not in that channel: fall back to General if joined.
        local gen = ns.Channels and ns.Channels.NameFor(1)
        num = gen and GetChannelName and ns.Try(GetChannelName, gen)
        if type(num) == "number" and num > 0 then return "CHANNEL", num end
        return nil, nil
    end
    return ch, nil
end

-- The raw send. Only callers: Fire (click/key/slash), /tt, the messenger's
-- reply box (Enter). Refuses in chat lockdown.
function Q.Send(text, chatType, target)
    if not ns.Lockdown.CanSend() then return false end
    if type(text) ~= "string" or text == "" then return false end
    if chatType == "BN_WHISPER" then
        local bn = C_BattleNet and C_BattleNet.SendWhisper
        if bn and target then ns.Try(bn, target, text) return true end
        if BNSendWhisper and target then ns.Try(BNSendWhisper, target, text) return true end
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    if chatType == "WHISPER" or chatType == "CHANNEL" then
        ns.Try(send, text, chatType, nil, target)
    else
        ns.Try(send, text, chatType)
    end
    return true
end

-- Put text into Blizzard's chat box (Tim presses Enter). cursor: optional
-- byte position for the cursor.
function Q.Prefill(text, cursor)
    local u = ChatFrameUtil
    if u and u.OpenChat then
        ns.Try(u.OpenChat, text, nil, cursor)
        return true
    elseif ChatFrame_OpenChat then
        ns.Try(ChatFrame_OpenChat, text)
        return true
    end
    return false
end

-- Slash-form of a line ("/p ty for the group!") for prefill.
function Q.SlashForm(text, chatType, target)
    if chatType == "WHISPER" and target then return "/w " .. target .. " " .. text end
    if chatType == "CHANNEL" and target then return "/" .. tostring(target) .. " " .. text end
    local s = Q.SLASH[chatType or "SAY"] or "/s"
    return s .. " " .. text
end

-- Fire quick line n of a set (default: the active situational set). source:
-- "click" | "key" | "slash". Returns "sent" | "prefill" | "shown" | nil.
function Q.Fire(n, source, setKey)
    if not Q.HW_SOURCES[source or ""] then return nil end -- never automatic
    setKey = setKey or ns.QuickSets.Active()
    local line = setKey and Q.Lines(setKey)[tonumber(n) or 0]
    if not line or ns.Trim(line.text) == "" then
        local name = setKey and ns.QuickSets.NAMES[setKey] or "the active set"
        ns.Print(("Quick line %s of %s is empty. Edit it in /comms quick."):format(tostring(n), name))
        return nil
    end
    local text, needsTyping, dPos = Q.Expand(line.text)
    local chatType, target = Q.Resolve(line)
    if not chatType then
        ns.Print("You're not in that channel.")
        return nil
    end
    local slash = Q.SlashForm(text, chatType, target)
    if not ns.Lockdown.CanSend() then
        if S().lockdownAction == "show" then
            ns.UI.CopyText(slash, "Chat is locked here. Copy the line, or type it.")
            return "shown"
        end
        Q.Prefill(slash)
        return "prefill"
    end
    if needsTyping then
        local cursor = dPos and (#slash - #text + dPos) or nil
        Q.Prefill(slash, cursor)
        return "prefill"
    end
    if Q.Send(text, chatType, target) then return "sent" end
    return nil
end

-- Key bindings (Bindings.xml) call these through the global Comms table.
function ns.API.QuickLine(n)
    if ns.disabled or not ns.db then return end
    return Q.Fire(n, "key")
end

function ns.API.CombatLine(n)
    if ns.disabled or not ns.db then return end
    return Q.Fire(n, "key", "combat")
end
