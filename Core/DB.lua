-- SavedVariables.
--
-- CommsDB      (account)    every setting, typed history, whisper history,
--                            chat scrollback, seen names, alerts. One setup
--                            carries over to all 23 characters.
-- CommsCharDB  (character)  channel override (nil = account list), role for
--                            %r, last tab, and window positions only when
--                            "same layout on all characters" is off.
local _, ns = ...

local DB = {}
ns.DB = DB

DB.SCHEMA = 1

-- Caps (keep the SavedVariables file well under 2 MB).
DB.CAPS = {
    typed = 100,
    whisperLines = 200,
    whisperContacts = 50,
    historyDefault = 500,
    historyMax = 2000,
    seenNames = 2000,
    seenMaxAge = 60 * 60 * 24 * 60, -- 60 days
    alerts = 100,
}

-- Forever channel IDs (C_ChatInfo.GetChannelShortcutForChannelID gives the
-- localised name). Order is the order shown in Settings.
DB.CHANNELS = {
    { id = 1, key = "General", label = "General" },
    { id = 2, key = "Trade", label = "Trade" },
    { id = 46, key = "TradeCity", label = "Trade (City)" },
    { id = 22, key = "LocalDefense", label = "LocalDefense" },
    { id = 26, key = "LookingForGroup", label = "LookingForGroup" },
    { id = 42, key = "Services", label = "Services" },
}

local function deepDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
                -- Lists (array defaults) are copied whole on first use only.
                if #v > 0 then
                    for i, item in ipairs(v) do
                        if type(item) == "table" then
                            local c = {}
                            for a, b in pairs(item) do c[a] = b end
                            target[k][i] = c
                        else
                            target[k][i] = item
                        end
                    end
                end
            end
            if #v == 0 then deepDefaults(target[k], v) end
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end
DB.deepDefaults = deepDefaults

-- Quick lines (brief table). channel: auto = INSTANCE_CHAT > RAID > PARTY > SAY.
-- target: for WHISPER, "auto" = my target if it's a player, else the last
-- person who whispered me; for CHANNEL, the channel name.
DB.QUICK_DEFAULTS = {
    { label = "inv", text = "inv pls", channel = "WHISPER", target = "auto" },
    { label = "ty", text = "ty for the group!", channel = "auto" },
    { label = "brb", text = "brb", channel = "auto" },
    { label = "back", text = "back", channel = "auto" },
    { label = "tank?", text = "need a tank", channel = "auto" },
    { label = "heals?", text = "need heals", channel = "auto" },
    { label = "LFG", text = "LFG %d as %r", channel = "CHANNEL", target = "LookingForGroup" },
    { label = "omw", text = "on my way", channel = "auto" },
    { label = "gg", text = "gg", channel = "auto" },
    { label = "wave", text = "waves.", channel = "EMOTE" },
}

DB.settingsDefaults = {
    format = {
        enabled = true,
        classColors = true,
        shortChannels = true,
        -- Channel base name (as the game sends it) -> short tag.
        channelMap = {
            General = "G", Trade = "T", ["Trade - City"] = "TC", LocalDefense = "LD",
            LookingForGroup = "LFG", Services = "S", WorldDefense = "WD", GuildRecruitment = "GR",
        },
        -- nil = leave Blizzard's timestamp setting alone; otherwise a format
        -- for the showTimestamps CVar ("none" turns them off).
        timestamps = nil,
    },
    links = { urls = true, invites = true, inviteWords = { "inv", "invite", "+1 inv" }, altInvite = true },
    alerts = {
        enabled = true, myName = true, keywords = {}, wholeWord = true,
        sound = true, soundKit = "RAID_WARNING", flash = true,
    },
    -- Only types Tim changed from Blizzard's default are written (see Sticky.lua).
    sticky = { overrides = {} },
    input = {
        enabled = true, height = 32, fontSize = 15, position = "below", noAlt = true,
    },
    autocomplete = {
        enabled = true, friends = true, guild = true, group = true, whispers = true, seen = true,
        channels = true, commands = true,
    },
    channels = {
        mode = "leave", -- "leave" | "hide"
        list = { General = false, Trade = false, TradeCity = true, LocalDefense = false, LookingForGroup = false, Services = true },
        announce = true,
    },
    whispers = { enabled = true, showInMain = true, openOnWhisper = false, sound = false },
    quick = {
        lines = DB.QUICK_DEFAULTS,
        bar = true, barHideInCombat = false, lockdownAction = "prefill", -- "prefill" | "show"
    },
    history = { enabled = true, lines = 500, replay = true },
    sameLayout = true,
    debug = false,
}

DB.accountDefaults = {
    schema = DB.SCHEMA,
    settings = DB.settingsDefaults,
    typed = {},          -- last sent lines, oldest first
    whispers = {},       -- contactKey -> { name, display, bnet, class, lastSeen, unread, lines = {{t, dir, text}} }
    history = {},        -- charKey -> frameID -> { lines = {...}, head }
    seenNames = {},      -- "name-realm" -> { name, class, t }
    alerts = {},         -- newest last: { t, who, text, word, channel }
    minimap = { angle = 215, hide = false },
    layout = {},         -- shared window positions (sameLayout on)
    firstRunDone = false,
}

DB.charDefaults = {
    schema = DB.SCHEMA,
    channelsOverride = nil, -- nil = use account list; table = per-character list
    role = "DPS",
    window = { tab = "whispers" },
    layout = {},
}

function DB.Migrate(account)
    account.schema = DB.SCHEMA
end

-- Wire up (or create) the saved tables. Pure function of its inputs so tests
-- can drive it without a client.
function DB.Init(account, char)
    account = deepDefaults(account or {}, DB.accountDefaults)
    char = deepDefaults(char or {}, DB.charDefaults)
    DB.Migrate(account)
    DB.global, DB.char = account, char
    ns.db = { global = account, char = char }
    return account, char
end

function DB.Settings()
    return ns.db.global.settings
end

-- Window positions: account-wide or per character.
function DB.Layout()
    if ns.db.global.settings.sameLayout then return ns.db.global.layout end
    return ns.db.char.layout
end

function DB.CharKey()
    return (ns.MyName() or "?") .. "-" .. ns.MyRealm()
end

-- Trim an array to its newest n entries.
function DB.Cap(list, n)
    local extra = #list - n
    if extra > 0 then
        for _ = 1, extra do table.remove(list, 1) end
    end
    return list
end
