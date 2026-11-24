-- Links: URLs and invite words become clickable addon links.
--
-- Link format: |Haddon:Comms:<kind>:<id>|h[text]|h. Blizzard registers the one
-- handler for the "addon" link type itself (ItemRefHandlersShared.lua) and
-- re-broadcasts the click as EventRegistry "SetItemRef" (link, text, button,
-- frame); we listen there instead of hooking SetItemRef or registering a
-- second "addon" handler (Blizzard's link registry refuses duplicates).
local _, ns = ...

local Links = {}
ns.Links = Links

Links.PREFIX = "addon:Comms:"
local URL_HEX = "|cff6fc3ff"
local INV_HEX = "|cff7fe07f"

local store = {}   -- id -> { kind, value }
local nextId = 0
local function put(kind, value)
    nextId = nextId + 1
    store[nextId] = { kind = kind, value = value }
    store[nextId - 600] = nil -- keep the session table small
    return nextId
end
function Links.Get(id) return store[tonumber(id)] end

-- URL patterns: scheme URLs, www. hosts, and bare domain.tld/path.
Links.URL_PATTERNS = {
    "%f[%w]https?://[^%s|]+",
    "%f[%w]www%.[%w%-]+%.[%w%-%.]+[^%s|]*",
    "%f[%w][%w][%w%-%.]*%.%a%a+/[^%s|]*",
}

local function trimTail(url)
    -- Trailing punctuation belongs to the sentence, not the link.
    local core, tail = url:match("^(.-)([%.,;:!%?%)%]'\"]*)$")
    return core, tail
end

-- Find URLs in plain text (no link codes). Returns list of {s, e, url}.
function Links.FindURLs(text)
    local found = {}
    for _, pat in ipairs(Links.URL_PATTERNS) do
        local init = 1
        while true do
            local s, e = text:find(pat, init)
            if not s then break end
            local raw = text:sub(s, e)
            local url, tail = trimTail(raw)
            e = e - #tail
            local overlaps = false
            for _, f in ipairs(found) do
                if s <= f.e and e >= f.s then overlaps = true break end
            end
            if not overlaps and #url > 4 then table.insert(found, { s = s, e = e, url = url }) end
            init = e + #tail + 1
        end
    end
    table.sort(found, function(a, b) return a.s < b.s end)
    return found
end

-- Apply fn to the parts of msg outside existing |H...|h...|h links and |T|t.
local function outsideLinks(msg, fn)
    local out, pos = {}, 1
    while true do
        local s, e = msg:find("|H.-|h.-|h", pos)
        if not s then break end
        table.insert(out, fn(msg:sub(pos, s - 1)))
        table.insert(out, msg:sub(s, e))
        pos = e + 1
    end
    table.insert(out, fn(msg:sub(pos)))
    return table.concat(out)
end

function Links.LinkURLs(msg)
    local changed = false
    local result = outsideLinks(msg, function(part)
        if part == "" then return part end
        local found = Links.FindURLs(part)
        if #found == 0 then return part end
        changed = true
        local buf, pos = {}, 1
        for _, f in ipairs(found) do
            table.insert(buf, part:sub(pos, f.s - 1))
            local id = put("url", f.url)
            table.insert(buf, ("%s|H%surl:%d|h[%s]|h|r"):format(URL_HEX, Links.PREFIX, id, f.url))
            pos = f.e + 1
        end
        table.insert(buf, part:sub(pos))
        return table.concat(buf)
    end)
    return result, changed
end

-- Invite words ("inv", "invite", "+1 inv"): whole word/phrase, any case.
local function escapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end
Links.EscapePattern = escapePattern

function Links.HasInviteWord(msg, words)
    local plain = " " .. ns.Plain(msg):lower() .. " "
    for _, w in ipairs(words or {}) do
        w = ns.Trim(w):lower()
        if w ~= "" then
            local p = "[%s%p]" .. escapePattern(w) .. "[%s%p]"
            if plain:find(p) then return true end
        end
    end
    return false
end

Links.INVITE_TYPES = {
    WHISPER = true, BN_WHISPER = false, PARTY = true, PARTY_LEADER = true, RAID = true, RAID_LEADER = true,
    INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true, GUILD = true, OFFICER = true,
}

function Links.InviteLink(name)
    local id = put("inv", name)
    return ("%s|H%sinv:%d|h[invite]|h|r"):format(INV_HEX, Links.PREFIX, id)
end

-- Filter stage.
function Links.Stage(ctx)
    local s = ns.DB.Settings().links
    if s.urls then
        local out, changed = Links.LinkURLs(ctx.msg)
        if changed then ctx.msg, ctx.changed = out, true end
    end
    if s.invites and Links.INVITE_TYPES[ctx.type] and type(ctx.author) == "string" and ctx.author ~= "" then
        local me = ns.MyName()
        if not (me and ns.SplitName(ctx.author) == me) and Links.HasInviteWord(ctx.msg, s.inviteWords) then
            ctx.msg = ctx.msg .. " " .. Links.InviteLink(ctx.author)
            ctx.changed = true
        end
    end
end

function Links.Invite(name)
    if ns.Secret(name) or type(name) ~= "string" or name == "" then return false end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        ns.Try(C_PartyInfo.InviteUnit, name)
    elseif InviteUnit then
        ns.Try(InviteUnit, name)
    else
        return false
    end
    ns.Print("Invited " .. ns.ShortName(name) .. ".")
    return true
end

-- EventRegistry "SetItemRef" callback (owner first).
function Links.OnSetItemRef(_, link, text, button)
    if ns.Secret(link) or type(link) ~= "string" then return end
    local kind, id = link:match("^addon:Comms:(%a+):(%d+)")
    if not kind then return end
    local entry = Links.Get(id)
    if not entry then return end
    if kind == "url" then
        ns.UI.CopyText(entry.value, "Press Ctrl+C to copy this link.")
    elseif kind == "inv" then
        Links.Invite(entry.value)
    end
end

function Links.Install()
    if Links.installed then return end
    Links.installed = true
    local reg = EventRegistry
    if reg and reg.RegisterCallback then
        pcall(reg.RegisterCallback, reg, "SetItemRef", Links.OnSetItemRef, Links)
    end
end
