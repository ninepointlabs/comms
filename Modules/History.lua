-- History: chat scrollback that survives /reload and logout (Chattynator-lite).
--
-- Stores the last N unlocked lines per chat window, per character
-- (CommsDB.history[charKey][frameID]), and replays them dimmed on login.
-- Secret (locked) lines never get here. Also keeps a session buffer for
-- Search when saving is off.
local _, ns = ...

local History = {}
ns.History = History

History.session = {} -- this session's lines, all frames (capped)
local SESSION_CAP = 2000

local function S() return ns.DB.Settings().history end

function History.Cap()
    local n = tonumber(S().lines) or ns.DB.CAPS.historyDefault
    return math.max(50, math.min(n, ns.DB.CAPS.historyMax))
end

local function charStore()
    local key = ns.DB.CharKey()
    local h = ns.db.global.history
    h[key] = h[key] or {}
    return h[key]
end

function History.Buffer(frameID)
    local store = charStore()
    local k = tostring(frameID or 1)
    store[k] = store[k] or {}
    return store[k]
end

function History.Record(frameID, line)
    if S().enabled then
        local buf = History.Buffer(frameID)
        table.insert(buf, line)
        ns.DB.Cap(buf, History.Cap())
    end
end

-- Filter stage: store the line as received (before Comms' own link codes).
function History.Stage(ctx)
    local line = {
        t = ns.Now(), e = ctx.type, a = type(ctx.author) == "string" and ctx.author or nil,
        m = ns.Plain(ctx.msg),
    }
    if ctx.type == "CHANNEL" then
        local base = ctx.args[9]
        local short = type(base) == "string" and ns.DB.Settings().format.channelMap[base]
        line.c = (short and short ~= "") and short or (type(base) == "string" and base or nil)
    end
    if ctx.first then
        line.cl = ns.Format.ClassOf(ctx.guid, ctx.author)
        table.insert(History.session, line)
        ns.DB.Cap(History.session, SESSION_CAP)
    end
    local id = ctx.frame and ctx.frame.GetID and ns.Try(ctx.frame.GetID, ctx.frame) or 1
    History.Record(id, line)
end

local TAGS = {
    SAY = "Say", YELL = "Yell", PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL",
    RAID_WARNING = "RW", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL", GUILD = "Gu", OFFICER = "O",
    WHISPER = "From", WHISPER_INFORM = "To", BN_WHISPER = "From", BN_WHISPER_INFORM = "To",
}

-- One line as plain-ish display text.
function History.Format(line, dim)
    local when = date("%m-%d %H:%M", line.t or 0)
    local tag = line.c or TAGS[line.e] or ""
    local who = line.a and ns.ShortName(line.a) or ""
    local text
    if line.e == "EMOTE" then
        text = ("%s %s"):format(who, line.m or "")
    else
        text = ("%s%s: %s"):format(tag ~= "" and ("[" .. tag .. "] ") or "", who ~= "" and ("[" .. who .. "]") or "", line.m or "")
    end
    text = ("[%s] %s"):format(when, ns.Escape(text))
    if dim then return "|cff8a8a8a" .. text .. "|r" end
    return text
end

-- Replay this character's stored lines into their chat windows.
function History.Replay()
    if not S().enabled or not S().replay then return 0 end
    local total = 0
    for k, buf in pairs(charStore()) do
        local frame = _G["ChatFrame" .. k]
        if frame and frame.AddMessage and #buf > 0 then
            local max = (frame.GetMaxLines and ns.Try(frame.GetMaxLines, frame)) or 128
            local first = math.max(1, #buf - max + 2)
            frame:AddMessage(("|cff8a8a8a— Comms: %d earlier line%s —|r"):format(#buf - first + 1, #buf - first == 0 and "" or "s"))
            for i = first, #buf do
                frame:AddMessage(History.Format(buf[i], true))
                total = total + 1
            end
            frame:AddMessage("|cff8a8a8a— now —|r")
        end
    end
    return total
end

function History.Clear()
    wipe(ns.db.global.history)
    wipe(History.session)
    ns.Print("Chat history cleared (all characters).")
end

-- Every stored line for this character plus this session's (for Search),
-- oldest first, without duplicates (a line shown in two windows is stored
-- once per window).
function History.All()
    local out, dedup = {}, {}
    local function add(l)
        local key = tostring(l.t) .. "\0" .. (l.a or "") .. "\0" .. (l.m or "")
        if not dedup[key] then
            dedup[key] = true
            table.insert(out, l)
        end
    end
    if S().enabled then
        for _, buf in pairs(charStore()) do
            for _, l in ipairs(buf) do add(l) end
        end
    end
    for _, l in ipairs(History.session) do add(l) end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

function History.Count()
    local n = 0
    for _, store in pairs(ns.db.global.history) do
        for _, buf in pairs(store) do n = n + #buf end
    end
    return n
end
