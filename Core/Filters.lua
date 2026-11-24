-- Filters: one Blizzard chat message filter per event, running Comms' stages
-- in order. Registered through ChatFrameUtil.AddMessageEventFilter (the
-- forever-branch registry) or the older global as a fallback, never both.
--
-- Rules (BRIEF "Chat lockdown and secret values"):
--  * Blizzard skips an addon filter when the args are secret. We also check
--    ourselves: any secret arg -> return false untouched (Blizzard shows the
--    plain line). Secrets are never compared, concatenated or stored.
--  * Any error -> return false untouched.
--  * A filter runs once per chat frame that shows the event; stages with side
--    effects (alerts, seen names) run only for the first frame (ctx.first).
local _, ns = ...

local F = {}
ns.Filters = F

F.EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}

local stages = {} -- { name, fn(ctx) -> discard? }
F.stages = stages

-- Stages run in the order added (Boot adds them: channels, whispers, links,
-- format, alerts, history).
function F.Add(name, fn)
    table.insert(stages, { name = name, fn = fn })
end

-- Lines already seen (per lineID), so side effects happen once per line.
local seen, seenCount = {}, 0
local function firstTime(event, lineID, msg)
    local key = tostring(event) .. ":" .. tostring(lineID or "") .. ":" .. tostring(msg)
    if seen[key] then return false end
    if seenCount > 400 then seen, seenCount = {}, 0 end
    seen[key] = true
    seenCount = seenCount + 1
    return true
end

local function anySecret(...)
    return ns.Secret(...)
end

-- The ChatFrame message filter: return true to drop the line, or
-- false, newArgs... to change it, or false to leave it.
function F.Filter(chatFrame, event, ...)
    if ns.disabled or not ns.db then return false end
    if anySecret(event, ...) then return false end
    local n = select("#", ...)
    local args = { ... }
    if type(args[1]) ~= "string" then return false end
    local ctx = {
        frame = chatFrame, event = event, type = event:sub(10), args = args,
        msg = args[1], author = args[2], lineID = args[11], guid = args[12],
        changed = false,
    }
    ctx.first = firstTime(event, ctx.lineID, ctx.msg)
    for _, st in ipairs(stages) do
        local ok, discard = pcall(st.fn, ctx)
        if not ok then
            ns.Debug("filter stage " .. st.name .. " failed: " .. tostring(discard))
            return false
        end
        if discard then return true end
    end
    if not ctx.changed then return false end
    args[1] = ctx.msg
    return false, unpack(args, 1, math.max(n, 14))
end

-- Class-coloured sender names (Blizzard's sender-name filter registry). The
-- callback gets (event, decoratedName, arg1..arg14); senderGUID is arg12.
function F.NameFilter(event, decorated, ...)
    if ns.disabled or not ns.db then return nil end
    if ns.Secret(decorated) or type(decorated) ~= "string" then return nil end
    local guid = select(12, ...)
    if ns.Secret(guid) then return nil end
    local ok, out = pcall(ns.Format.ColorName, decorated, guid, select(2, ...))
    if ok and out then return out end
    return nil
end

function F.Install()
    if F.installed then return end
    F.installed = true
    local util = ChatFrameUtil
    local add = (util and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        for _, ev in ipairs(F.EVENTS) do pcall(add, ev, F.Filter) end
    end
    if util and util.AddSenderNameFilter then pcall(util.AddSenderNameFilter, F.NameFilter) end
end

function F._ResetSeen()
    seen, seenCount = {}, 0
end
