-- Sticky channels: the last used of SAY/PARTY/RAID/GUILD/OFFICER/INSTANCE/
-- WHISPER/CHANNEL stays selected in the chat box.
--
-- On Forever 1.60.1 Blizzard already makes all of those sticky
-- (ChatTypeInfoConstants.lua: sticky = 1), so by default Comms writes nothing.
-- ChatTypeInfo is read by Blizzard's send path, so a value written by an addon
-- is "tainted" and could, in theory, follow Tim's Enter press into a dungeon.
-- That's why only types Tim changes are written, only outside lockdown and
-- combat, and the Settings page says so.
local _, ns = ...

local Sticky = {}
ns.Sticky = Sticky

Sticky.TYPES = {
    { key = "SAY", label = "Say" }, { key = "PARTY", label = "Party" }, { key = "RAID", label = "Raid" },
    { key = "INSTANCE_CHAT", label = "Instance" }, { key = "GUILD", label = "Guild" },
    { key = "OFFICER", label = "Officer" }, { key = "WHISPER", label = "Whisper" },
    { key = "BN_WHISPER", label = "Battle.net whisper" }, { key = "CHANNEL", label = "Channels (/1, /2...)" },
    { key = "YELL", label = "Yell" }, { key = "EMOTE", label = "Emote" },
}

-- Blizzard's defaults, captured before we ever write.
Sticky.defaults = {}

local function info(key) return ChatTypeInfo and ChatTypeInfo[key] end

function Sticky.Capture()
    for _, t in ipairs(Sticky.TYPES) do
        local i = info(t.key)
        if i and Sticky.defaults[t.key] == nil then Sticky.defaults[t.key] = i.sticky end
    end
end

function Sticky.IsSticky(key)
    local o = ns.DB.Settings().sticky.overrides[key]
    if o ~= nil then return o == 1 end
    local i = info(key)
    return i and i.sticky == 1 or false
end

-- Write only overrides that differ from what's there. Returns number written.
function Sticky.Apply()
    if ns.Lockdown.Busy() then
        Sticky.pending = true
        return 0
    end
    Sticky.pending = false
    local n = 0
    for key, v in pairs(ns.DB.Settings().sticky.overrides) do
        local i = info(key)
        if i and i.sticky ~= v then
            i.sticky = v
            n = n + 1
        end
    end
    return n
end

function Sticky.Set(key, on)
    local v = on and 1 or 0
    local o = ns.DB.Settings().sticky.overrides
    if Sticky.defaults[key] == v then o[key] = nil else o[key] = v end
    -- Turning an override off puts Blizzard's value back (if we wrote one).
    if o[key] == nil and not ns.Lockdown.Busy() then
        local i = info(key)
        if i and Sticky.defaults[key] ~= nil and i.sticky ~= Sticky.defaults[key] then i.sticky = Sticky.defaults[key] end
    end
    return Sticky.Apply()
end
