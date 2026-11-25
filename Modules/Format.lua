-- Format: class-coloured names, short channel names, timestamps, and the
-- "seen names" table (name -> class) used for colouring and autocomplete.
--
-- How each piece is done without tainting Blizzard's chat code:
--  * Names: ChatFrameUtil.AddSenderNameFilter (Blizzard's registry).
--  * Channels: the message filter rewrites arg4 ("2. Trade - City") to
--    "2. TC". Blizzard parses the leading "N. " itself and requires it, and it
--    matches arg4's length against its channel list, so the short form is
--    padded with harmless "|r" codes to the original length. Party / Guild /
--    Raid tags come from Blizzard's CHAT_*_GET strings; replacing those would
--    taint every chat line in lockdown, so they stay as Blizzard draws them.
--  * Timestamps: Blizzard's own showTimestamps setting (set through
--    C_CVar.SetCVar, outside lockdown and combat only), so they keep working
--    on locked lines too.
local _, ns = ...

local Format = {}
ns.Format = Format

Format.TIMESTAMP_FORMATS = {
    { value = "none", label = "Off" },
    { value = "%H:%M ", label = "15:27" },
    { value = "%H:%M:%S ", label = "15:27:32" },
    { value = "%I:%M ", label = "03:27" },
    { value = "%I:%M %p ", label = "03:27 PM" },
    { value = "[%H:%M] ", label = "[15:27]" },
    { value = "[%H:%M:%S] ", label = "[15:27:32]" },
}

local function S() return ns.DB.Settings().format end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return nil end
    if c.colorStr then return "|c" .. c.colorStr end
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end
Format.ClassHex = classHex

function Format.ClassOf(guid, author)
    if type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
        local _, class = ns.Try(GetPlayerInfoByGUID, guid)
        if not ns.Secret(class) and class then return class end
    end
    if type(author) == "string" then
        local key = ns.NameKey(author)
        local s = key and ns.db.global.seenNames[key]
        if s then return s.class end
    end
    return nil
end

-- Sender-name filter body. Leaves names Blizzard already coloured alone.
function Format.ColorName(decorated, guid, author)
    local s = S()
    if not (s.enabled and s.classColors) then return nil end
    if decorated:find("|c", 1, true) then return nil end
    local hex = classHex(Format.ClassOf(guid, author))
    if not hex then return nil end
    return hex .. decorated .. "|r"
end

-- "2. Trade - City" -> "2. TC" padded to the original length. Returns nil when
-- there's no short name.
function Format.ShortChannel(channelString, baseName)
    if type(channelString) ~= "string" or channelString == "" then return nil end
    local num, name = channelString:match("^(%d+)%. (.+)$")
    if not num then return nil end
    local map = S().channelMap or {}
    local base = (type(baseName) == "string" and baseName ~= "") and baseName or name
    local short = map[base] or map[name]
    if not short then
        -- "General - Elwynn Forest" -> General
        local head = name:match("^(.-) %- ")
        short = head and map[head]
    end
    if not short or short == "" then return nil end
    local out = num .. ". " .. short
    local pad = #channelString - #out
    if pad > 0 then out = out .. string.rep("|r", math.ceil(pad / 2)) end
    return out
end

-- Remember who we've seen (unlocked lines only), for colours and autocomplete.
function Format.NoteSeen(author, guid)
    if type(author) ~= "string" or author == "" then return end
    local key = ns.NameKey(author)
    if not key then return end
    local class = Format.ClassOf(guid, nil)
    local seen = ns.db.global.seenNames
    local e = seen[key]
    if e then
        e.t = ns.Now()
        e.class = class or e.class
    else
        seen[key] = { name = author, class = class, t = ns.Now() }
        Format.seenCount = (Format.seenCount or 0) + 1
        if Format.seenCount > ns.DB.CAPS.seenNames + 100 then Format.PruneSeen() end
    end
end

function Format.PruneSeen()
    local seen = ns.db.global.seenNames
    local list = {}
    local cutoff = ns.Now() - ns.DB.CAPS.seenMaxAge
    for k, v in pairs(seen) do
        if (v.t or 0) < cutoff then seen[k] = nil else table.insert(list, { k = k, t = v.t or 0 }) end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = ns.DB.CAPS.seenNames + 1, #list do seen[list[i].k] = nil end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    Format.seenCount = n
end

-- Filter stage.
function Format.Stage(ctx)
    local s = S()
    if ctx.first and ctx.type ~= "WHISPER_INFORM" and ctx.type ~= "BN_WHISPER_INFORM" and not ctx.type:find("^BN_") then
        Format.NoteSeen(ctx.author, ctx.guid)
    end
    if not s.enabled then return end
    if s.shortChannels and ctx.type == "CHANNEL" then
        local short = Format.ShortChannel(ctx.args[4], ctx.args[9])
        if short then
            ctx.args[4] = short
            ctx.changed = true
        end
    end
end

-- Timestamps through Blizzard's own setting.
function Format.CurrentTimestamp()
    local cv = C_CVar and C_CVar.GetCVar and ns.Try(C_CVar.GetCVar, "showTimestamps")
    return cv
end

function Format.SetTimestamp(fmt)
    S().timestamps = fmt
    return Format.ApplyTimestamp()
end

function Format.ApplyTimestamp()
    local fmt = S().timestamps
    if not fmt then return false end
    if ns.Lockdown.Busy() then
        Format.pendingTimestamp = true
        return false
    end
    if not (C_CVar and C_CVar.SetCVar) then return false end
    if Format.CurrentTimestamp() == fmt then return true end
    Format.pendingTimestamp = false
    ns.Try(C_CVar.SetCVar, "showTimestamps", fmt)
    return true
end

function Format.TimestampLabel(fmt)
    for _, f in ipairs(Format.TIMESTAMP_FORMATS) do
        if f.value == fmt then return f.label end
    end
    if fmt == nil then return "Blizzard's setting" end
    return tostring(fmt)
end
