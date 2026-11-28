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

-- 1: v0.1 (one list of 10 quick lines in settings.quick.lines)
-- 2: v0.2 (situational quick-line sets + Combat row, settings.quick.sets)
DB.SCHEMA = 2

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

-- Quick lines. channel: auto = INSTANCE_CHAT > RAID > PARTY > SAY.
-- target: for WHISPER, "auto" = my target if it's a player, else the last
-- person who whispered me; for CHANNEL, the channel name.
--
-- v0.1's single list. Kept only to tell an untouched v0.1 list from one Tim
-- edited when migrating to schema 2 (see DB.Migrate).
DB.QUICK_DEFAULTS_V1 = {
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

-- Situational sets (schema 2). world / party / raid swap automatically with
-- the context (out of combat only); combat is the always-visible second row.
DB.SET_KEYS = { "world", "party", "raid", "combat" }
DB.QUICK_SETS = {
    world = {
        { label = "hi", text = "hi!", channel = "SAY" },
        { label = "wave", text = "waves.", channel = "EMOTE" },
        { label = "ty", text = "ty!", channel = "auto" },
        { label = "thx", text = "thanks for the help!", channel = "auto" },
        { label = "group?", text = "group up for this quest?", channel = "SAY" },
        { label = "inv", text = "inv pls", channel = "WHISPER", target = "auto" },
        { label = "brb", text = "brb", channel = "auto" },
        { label = "LFG", text = "LFG %d as %r", channel = "CHANNEL", target = "LookingForGroup" },
    },
    party = {
        { label = "ready", text = "ready", channel = "auto" },
        { label = "omw", text = "on my way", channel = "auto" },
        { label = "ty", text = "ty for the group!", channel = "auto" },
        { label = "quest?", text = "need quest?", channel = "auto" },
        { label = "wait", text = "wait up", channel = "auto" },
        { label = "brb", text = "brb", channel = "auto" },
        { label = "back", text = "back", channel = "auto" },
        { label = "gg", text = "gg", channel = "auto" },
    },
    raid = {
        { label = "inc", text = "inc", channel = "auto" },
        { label = "help", text = "help!", channel = "auto" },
        { label = "clear", text = "clear", channel = "auto" },
        { label = "omw", text = "omw", channel = "auto" },
        { label = "ready", text = "ready", channel = "auto" },
        { label = "ty", text = "ty all", channel = "auto" },
    },
    combat = {
        { label = "oom", text = "oom", channel = "auto" },
        { label = "inc", text = "inc", channel = "auto" },
        { label = "peel", text = "peel me", channel = "auto" },
        { label = "pull", text = "pulling", channel = "auto" },
        { label = "heal", text = "heal me", channel = "auto" },
    },
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
        -- Arrays (the lines) are copied whole on first use only, never merged
        -- into a list Tim edited (deepDefaults).
        sets = {
            world = { enabled = true, lines = DB.QUICK_SETS.world },
            party = { enabled = true, lines = DB.QUICK_SETS.party },
            raid = { enabled = true, lines = DB.QUICK_SETS.raid },
            combat = { lines = DB.QUICK_SETS.combat },
        },
        auto = true,            -- switch world/party/raid with the context
        lastPicked = "world",   -- the set used when auto is off
        combatRow = "always",   -- "always" | "groups" | "off"
        bar = true, barHideInCombat = false, lockdownAction = "prefill", -- "prefill" | "show"
        -- lines: v0.1's list, left in place (read-only) for one version after
        -- the schema 2 migration. Not created on new installs.
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

local function copyLines(list)
    local out = {}
    for i, line in ipairs(list) do
        local c = {}
        for k, v in pairs(line) do c[k] = v end
        out[i] = c
    end
    return out
end
DB.CopyLines = copyLines

-- True when a v0.1 list is still exactly v0.1's defaults. target only counts
-- for WHISPER and CHANNEL lines (v0.1's editor could leave a stray target on
-- other lines when the channel was cycled).
function DB.IsV1Default(lines)
    local d = DB.QUICK_DEFAULTS_V1
    if type(lines) ~= "table" or #lines ~= #d then return false end
    for i, def in ipairs(d) do
        local l = lines[i]
        if type(l) ~= "table" then return false end
        if (l.label or "") ~= def.label or (l.text or "") ~= def.text or (l.channel or "auto") ~= def.channel then return false end
        if (def.channel == "WHISPER" or def.channel == "CHANNEL") and (l.target or "") ~= (def.target or "") then return false end
    end
    return true
end

-- Runs before defaults are filled in, so it sees exactly what was saved.
-- Idempotent: a second run (or a run on an up-to-date table) changes nothing.
function DB.Migrate(account)
    local from = tonumber(account.schema)
    if not from then
        -- No schema: a fresh install (nothing to migrate), or a v0.1 table
        -- that somehow lost it (has settings).
        from = type(account.settings) == "table" and 1 or DB.SCHEMA
    end
    if from < 2 then
        local q = type(account.settings) == "table" and account.settings.quick
        if type(q) == "table" and type(q.lines) == "table" and #q.lines > 0 and not DB.IsV1Default(q.lines) then
            -- Tim edited his v0.1 lines: they become Open World and Party /
            -- Dungeon. Raid / BG and Combat take the new defaults. q.lines
            -- itself stays as it was for one version.
            q.sets = type(q.sets) == "table" and q.sets or {}
            for _, key in ipairs({ "world", "party" }) do
                q.sets[key] = type(q.sets[key]) == "table" and q.sets[key] or {}
                if type(q.sets[key].lines) ~= "table" then q.sets[key].lines = copyLines(q.lines) end
            end
            q.migratedV1 = "edited"
        elseif type(q) == "table" then
            q.migratedV1 = "defaults"
        end
    end
    account.schema = DB.SCHEMA
end

-- Wire up (or create) the saved tables. Pure function of its inputs so tests
-- can drive it without a client.
function DB.Init(account, char)
    account = account or {}
    DB.Migrate(account)
    account = deepDefaults(account, DB.accountDefaults)
    account.settings.quick.combatRow = DB.NormalizeCombatRow(account.settings.quick.combatRow)
    char = deepDefaults(char or {}, DB.charDefaults)
    char.schema = DB.SCHEMA
    DB.global, DB.char = account, char
    ns.db = { global = account, char = char }
    return account, char
end

function DB.Settings()
    return ns.db.global.settings
end

-- Combat row mode. nil, "", or anything unknown counts as "always" (the row
-- is on by default); "groups" and "off" stay as saved.
DB.COMBAT_ROW_MODES = { always = true, groups = true, off = true }
function DB.NormalizeCombatRow(mode)
    if type(mode) == "string" and DB.COMBAT_ROW_MODES[mode] then return mode end
    return "always"
end

-- Current Combat row mode (and write the normalized value back).
function DB.CombatRow()
    local q = ns.db.global.settings.quick
    q.combatRow = DB.NormalizeCombatRow(q.combatRow)
    return q.combatRow
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
