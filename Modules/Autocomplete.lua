-- Autocomplete: Tab completes the word before the cursor in Blizzard's chat box.
--   * names: friends, guild, group, recent whisper partners, people seen in chat
--     (in plain text and after /tt, /inv; Blizzard already completes /w names)
--   * "/" commands: /tt, /inv, /comms ...; channel names after /join, /leave
-- Blizzard re-parses the box on every text change (ParseText). Completing a
-- chat-type command (/p, /w Name) from addon code would set the box's chat
-- type from tainted code, which could follow Tim into a locked dungeon; so
-- Comms only completes commands that aren't chat types, and never names after
-- /w, /r or other chat-type commands.
-- Hooked with HookScript("OnTabPressed") (runs after Blizzard's own Tab
-- handling). If Blizzard already changed the text on this key press (it cycles
-- whisper targets and completes chat types), we leave it. Never touches the box
-- in chat lockdown or combat.
local _, ns = ...

local AC = {}
ns.Autocomplete = AC

-- Not chat types (safe to complete; see above).
AC.COMMANDS = { "/tt", "/inv", "/invite", "/join", "/leave", "/who", "/comms" }
AC.CHANNEL_COMMANDS = { ["/join"] = true, ["/leave"] = true }
AC.NAME_COMMANDS = { ["/tt"] = true, ["/inv"] = true, ["/invite"] = true, ["/who"] = true }

local function S() return ns.DB.Settings().autocomplete end

local function addName(out, seen, name)
    if ns.Secret(name) or type(name) ~= "string" or name == "" then return end
    local short = ns.ShortName(name)
    local k = short:lower()
    if seen[k] then return end
    seen[k] = true
    table.insert(out, short)
end

-- Candidate names, in source priority order, de-duplicated.
function AC.Names()
    local s, out, seen = S(), {}, {}
    if s.whispers then
        local list = {}
        for _, c in pairs(ns.db.global.whispers) do
            if not c.bnet then table.insert(list, c) end
        end
        table.sort(list, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
        for _, c in ipairs(list) do addName(out, seen, c.display) end
    end
    if s.group then
        local n = ns.SafeCall(GetNumGroupMembers) or 0
        local raid = ns.SafeCall(IsInRaid)
        for i = 1, math.min(n, 40) do
            local unit = raid and ("raid" .. i) or ("party" .. i)
            if ns.SafeCall(UnitExists, unit) then
                local nm, realm = ns.Try(UnitName, unit)
                if ns.Secret(nm, realm) then nm = nil
                elseif type(realm) == "string" and realm ~= "" and type(nm) == "string" then nm = nm .. "-" .. realm end
                addName(out, seen, nm)
            end
        end
    end
    if s.friends and C_FriendList and C_FriendList.GetNumFriends then
        local n = ns.Try(C_FriendList.GetNumFriends) or 0
        for i = 1, n do
            local info = ns.Try(C_FriendList.GetFriendInfoByIndex, i)
            if type(info) == "table" then addName(out, seen, info.name) end
        end
    end
    if s.guild and GetNumGuildMembers and GetGuildRosterInfo then
        local n = ns.Try(GetNumGuildMembers) or 0
        for i = 1, math.min(n, 1000) do
            local nm = ns.Try(GetGuildRosterInfo, i)
            addName(out, seen, nm)
        end
    end
    if s.seen then
        local list = {}
        for _, e in pairs(ns.db.global.seenNames) do table.insert(list, e) end
        table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
        for _, e in ipairs(list) do addName(out, seen, e.name) end
    end
    return out
end

function AC.ChannelNames()
    local out = {}
    for _, c in ipairs(ns.DB.CHANNELS) do
        local n = ns.Channels.NameFor(c.id)
        if n then table.insert(out, n) end
    end
    return out
end

local function startsWith(s, prefix)
    return s:sub(1, #prefix):lower() == prefix:lower()
end

-- Pure completion: text, cursor (byte position after the cursor, default end)
-- -> newText, newCursor, or nil when nothing to complete. `cycle` = index of
-- the match to use (repeated Tab steps through matches).
function AC.Complete(text, cursor, cycle)
    if type(text) ~= "string" then return nil end
    cursor = cursor or #text
    local before, after = text:sub(1, cursor), text:sub(cursor + 1)
    local word = before:match("(%S+)$")
    if not word then return nil end
    local head = before:sub(1, #before - #word)
    local s = S()
    local candidates = {}
    if word:sub(1, 1) == "/" and head:match("^%s*$") then
        if not s.commands then return nil end
        for _, c in ipairs(AC.COMMANDS) do
            if startsWith(c, word) and c:lower() ~= word:lower() then table.insert(candidates, c) end
        end
    else
        local cmd = head:match("^%s*(/%S+)")
        if cmd and not (AC.CHANNEL_COMMANDS[cmd:lower()] or AC.NAME_COMMANDS[cmd:lower()]) then return nil end
        local onlyArg = head:match("^%s*/%S+%s+$")
        if cmd and AC.CHANNEL_COMMANDS[cmd:lower()] then
            if not onlyArg then return nil end
            if not s.channels then return nil end
            for _, c in ipairs(AC.ChannelNames()) do
                if startsWith(c, word) and c:lower() ~= word:lower() then table.insert(candidates, c) end
            end
        else
            if #word < 2 then return nil end
            for _, n in ipairs(AC.Names()) do
                if startsWith(n, word) and n:lower() ~= word:lower() then table.insert(candidates, n) end
            end
        end
    end
    if #candidates == 0 then return nil end
    local pick = candidates[((cycle or 1) - 1) % #candidates + 1]
    local newBefore = head .. pick .. " "
    return newBefore .. after, #newBefore, #candidates
end

-- Hook state per box: what the text looked like before this Tab press.
local state = {}

local function onTextChanged(eb, userInput)
    local st = state[eb]
    if not st then return end
    if userInput then
        st.typed = eb:GetText()
        st.cycle = 0
        st.lastCompleted = nil
    end
end

local function onTabPressed(eb)
    if not ns.db or not S().enabled then return end
    if ns.Lockdown.Busy() then return end
    local st = state[eb]
    local text = eb:GetText()
    if ns.Secret(text) or type(text) ~= "string" then return end
    -- Blizzard changed the text on this press (whisper-target cycling or its
    -- own slash completion): leave it.
    if st.lastCompleted ~= text and st.typed ~= text then return end
    local base = st.typed or text
    st.cycle = (st.cycle or 0) + 1
    local cursor = (eb.GetCursorPosition and eb:GetCursorPosition()) or #base
    if st.lastCompleted == text then cursor = #base end
    local newText, newCursor = AC.Complete(base, math.min(cursor, #base), st.cycle)
    if not newText then return end
    st.lastCompleted = newText
    eb:SetText(newText)
    if eb.SetCursorPosition then eb:SetCursorPosition(newCursor) end
end
AC.OnTabPressed = onTabPressed
AC.OnTextChanged = onTextChanged

function AC.Install()
    if AC.installed then return end
    AC.installed = true
    for _, eb in ipairs(ns.Recall.EditBoxes()) do
        if eb.HookScript then
            state[eb] = {}
            eb:HookScript("OnTextChanged", onTextChanged)
            eb:HookScript("OnTabPressed", onTabPressed)
        end
    end
end
