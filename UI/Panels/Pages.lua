-- Main window pages: Whispers · Alerts · Search · Quick lines.
local _, ns = ...
local UI = ns.UI

local function dim(text) return UI.Hex(UI.C.dim) .. text .. "|r" end

local function ago(t)
    local d = ns.Now() - (t or 0)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    return date("%Y-%m-%d", t)
end
UI.Ago = ago

-- Whispers ------------------------------------------------------------------
UI.RegisterPanel({
    key = "whispers", label = "Whispers",
    badge = function() return ns.Whispers.Unread() end,
    render = function(L)
        L:Title("Whispers", "One window, a tab per person. History is kept for every character on the account.")
        if ns.Lockdown.ChatLocked() then
            L:Flag("Chat is locked here; whispers show in main chat. Replies open Blizzard's chat box.")
        end
        L:Buttons({
            { label = "Open whisper window", onClick = function() UI.Messenger.Open(nil, true) end },
            { label = "Whisper settings", onClick = function() UI.Open("settings", "Whispers") end },
        })
        local list = UI.Messenger.Contacts()
        if #list == 0 then
            L:Text(dim("No whispers yet."))
            return
        end
        L:Label(("Contacts (%d of max %d)"):format(#list, ns.DB.CAPS.whisperContacts))
        for _, e in ipairs(list) do
            local last = e.c.lines and e.c.lines[#e.c.lines]
            local u = e.c.unread or 0
            L:Row({
                title = UI.Messenger.NameColored(e.c) .. (e.c.bnet and dim("  Battle.net") or ""),
                sub = last and ((last.d == "out" and "You: " or "") .. ns.Escape(last.m or "")) or "",
                chip = u > 0 and { text = u .. " new", kind = "bad" } or nil,
                right = ago(e.c.lastSeen),
                buttons = {
                    { label = "Open", onClick = function() UI.Messenger.Open(e.key) end },
                    { label = "Forget", tip = "Delete this contact's saved whispers.", onClick = function()
                        ns.Whispers.Remove(e.key)
                        UI.Refresh()
                    end },
                },
            })
        end
    end,
})

-- Alerts --------------------------------------------------------------------
UI.RegisterPanel({
    key = "alerts", label = "Alerts",
    badge = function() return ns.Alerts.unread end,
    render = function(L)
        local s = ns.DB.Settings().alerts
        local words = ns.Alerts.Words()
        L:Title("Alerts", "Lines that mention your name or a keyword: " ..
            (#words > 0 and ns.Escape(table.concat(words, ", ")) or "none set") .. ".")
        ns.Alerts.MarkRead()
        L:Buttons({
            { label = s.enabled and "Alerts on" or "Alerts off", active = s.enabled, onClick = function() s.enabled = not s.enabled UI.Refresh() end },
            { label = "Keywords and sound", onClick = function() UI.Open("settings", "Alerts") end },
            { label = "Clear list", onClick = function() ns.Alerts.Clear() UI.Refresh() end },
        })
        local list = ns.db.global.alerts
        if #list == 0 then
            L:Text(dim("Nothing yet. Locked lines (dungeons, battlegrounds) can't be read by addons, so they never alert."))
            return
        end
        for i = #list, 1, -1 do
            local a = list[i]
            L:Row({
                chip = { text = ns.Escape(a.word or "?"), kind = "info" },
                title = (a.who and ("[" .. ns.Escape(ns.ShortName(a.who)) .. "] ") or "") .. ns.Escape(a.text or ""),
                sub = ns.Escape(tostring(a.channel or "")) .. " · " .. date("%m-%d %H:%M", a.t or 0),
                button = { label = "Copy", onClick = function() UI.CopyText(a.text or "") end },
            })
        end
    end,
})

-- Search --------------------------------------------------------------------
UI.RegisterPanel({
    key = "search", label = "Search",
    render = function(L)
        L:Title("Search", "Stored chat history, this session and whispers. Type in the box at the top left.")
        L:Input(nil, UI.filterText, function(t) if ns.Trim(t) ~= UI.filterText then UI.SetFilter(t) end end,
            { hint = "Search text or a name...", width = 420 })
        local q = UI.filterText or ""
        if q == "" then
            L:Text(dim(("%d lines stored. Locked lines are never stored."):format(ns.History.Count())))
            return
        end
        local results = ns.Search.Run(q)
        L:Text(("%d match%s for \"%s\"%s"):format(#results, #results == 1 and "" or "es", ns.Escape(q),
            #results >= ns.Search.LIMIT and (" (first " .. ns.Search.LIMIT .. ")") or ""), { color = UI.C.dim })
        for _, r in ipairs(results) do
            local text = ns.History.Format(r.line, false)
            L:Row({
                chip = r.source == "whisper" and { text = "whisper", kind = "info" } or nil,
                title = text,
                buttons = {
                    { label = "Copy", onClick = function() UI.CopyText(r.line.m or "") end },
                    { label = "To chat", tip = "Put this line in the chat box (not while chat is locked).", onClick = function()
                        if ns.Lockdown.Busy() then
                            ns.Print("Not while chat is locked or in combat. Use Copy instead.")
                        else
                            ns.QuickLines.Prefill(r.line.m or "")
                        end
                    end },
                },
            })
        end
    end,
})

-- Quick lines -----------------------------------------------------------------
local editSet -- set shown in the editor (nil = the active one)

local function setLine(line, d)
    for k in pairs(line) do line[k] = nil end
    for k, v in pairs(d) do line[k] = v end
end

UI.RegisterPanel({
    key = "quick", label = "Quick lines",
    setSub = function(sub)
        if ns.QuickSets.NAMES[sub or ""] then editSet = sub end
    end,
    render = function(L)
        local s = ns.DB.Settings().quick
        local Sets = ns.QuickSets
        local key = editSet or Sets.Active() or "world"
        L:Title("Quick lines", "Fire from the quick-bar or a key binding. In chat lockdown the line is put in Blizzard's chat box: press Enter.")
        L:Text(dim(Sets.Describe()), { size = 12 })
        local tabs = {}
        for _, k in ipairs(ns.DB.SET_KEYS) do
            local label = Sets.NAMES[k]
            if k == Sets.Active() then label = label .. " (active)" end
            table.insert(tabs, { label = label, active = k == key, onClick = function() editSet = k UI.Refresh() end })
        end
        L:Tabs(tabs)
        if key == "combat" then
            L:Text(dim("The Combat row sits under the bar and stays visible in combat, even with \"Hide the quick-bar in combat\" on. Keys: Combat line 1-5."), { size = 12 })
        else
            L:Text(dim(("Shown automatically: %s. Keys Quick line 1-10 fire these slots while this set is active."):format(
                key == "world" and "solo / not in a group instance" or key == "party" and "in a group or a dungeon" or "in a raid group, battleground or arena")), { size = 12 })
        end
        if key ~= "world" then L:Text(dim("In dungeons/raids/BGs these fill the chat box; press Enter."), { size = 12 }) end
        L:Text(dim("Tokens: %t target · %f focus · %z zone · %r your role (" .. tostring(ns.db.char.role) .. ") · %d dungeon (opens the chat box so you can type it)."), { size = 12 })
        L:Buttons({
            { label = s.bar and "Quick-bar shown" or "Quick-bar hidden", active = s.bar, onClick = function()
                s.bar = not s.bar
                UI.QuickBar.Refresh()
                UI.Refresh()
            end },
            { label = "Role: " .. tostring(ns.db.char.role), tip = "Used by %r. Per character.", onClick = function()
                local roles = { "Tank", "Heal", "DPS" }
                local cur = ns.db.char.role
                local nextR = roles[1]
                for i, r in ipairs(roles) do if r == cur then nextR = roles[i % #roles + 1] end end
                ns.db.char.role = nextR
                UI.Refresh()
            end },
            { label = "Key bindings", tip = "Esc › Options › Keybindings › AddOns › Comms", onClick = function()
                ns.Print("Bind keys in Esc › Options › Keybindings › AddOns › Comms (Quick line 1-10 fire the active set, Combat line 1-5 the Combat row).")
            end },
            { label = "Set options", onClick = function() UI.Open("settings", "Quick lines") end },
        })
        local channels = {}
        for _, c in ipairs(ns.QuickLines.CHANNELS) do table.insert(channels, { value = c, label = c == "auto" and "auto" or c }) end
        local lines = ns.QuickLines.Lines(key)
        local defaults = ns.DB.QUICK_SETS[key] or {}
        local prefix = key == "combat" and "COMMS_COMBATLINE_" or "COMMS_QUICKLINE_"
        local bindMax = key == "combat" and 5 or 10
        if #lines == 0 then L:Text(dim("No lines in this set.")) end
        for i, line in ipairs(lines) do
            L:Label(("Line %d"):format(i))
            L:Input(nil, line.text, function(t) line.text = t UI.QuickBar.Refresh() end, { hint = "Text", width = 380, maxLetters = 255 })
            L:Input(nil, line.label, function(t) line.label = ns.Trim(t):sub(1, 8) UI.QuickBar.Refresh() end, { hint = "Button label (8 letters)", width = 160, maxLetters = 8 })
            local bkey = i <= bindMax and GetBindingKey and ns.Try(GetBindingKey, prefix .. i)
            local needsHW = ns.QuickLines.NEEDS_HW[line.channel or ""]
            L:Choice("Channel", (needsHW and "Needs a click or key press (Forever rule). " or "") ..
                (bkey and ("Bound to " .. bkey .. ".") or (i <= bindMax and "No key bound." or "No key binding for this slot.")),
                channels, line.channel or "auto", function(v)
                line.channel = v
                if v == "WHISPER" and not line.target then line.target = "auto" end
                if v == "CHANNEL" and not line.target then line.target = "LookingForGroup" end
                UI.QuickBar.Refresh()
            end)
            if line.channel == "WHISPER" then
                L:Choice("Whisper to", "auto = your target if it's a player, else the last person who whispered you.",
                    { { value = "auto", label = "auto" }, { value = "target", label = "target" }, { value = "last", label = "last whisperer" } },
                    line.target or "auto", function(v) line.target = v end)
            elseif line.channel == "CHANNEL" then
                L:Input("Channel name", line.target, function(t) line.target = ns.Trim(t) UI.QuickBar.Refresh() end, { width = 200 })
            end
            local buttons = {
                { label = "Test (fires it)", onClick = function() ns.QuickLines.Fire(i, "click", key) end },
                { label = "Remove", onClick = function()
                    table.remove(lines, i)
                    UI.QuickBar.Refresh()
                    UI.Refresh()
                end },
            }
            if defaults[i] then
                table.insert(buttons, 2, { label = "Reset to default", onClick = function()
                    setLine(line, defaults[i])
                    UI.QuickBar.Refresh()
                    UI.Refresh()
                end })
            end
            L:Buttons(buttons)
        end
        local more = {}
        if #lines < ns.QuickLines.COUNT then
            table.insert(more, { label = "Add a line", onClick = function()
                table.insert(lines, { label = "", text = "", channel = "auto" })
                UI.Refresh()
            end })
        end
        table.insert(more, { label = "Reset this set", tip = "Back to the default lines for " .. Sets.NAMES[key] .. ".", onClick = function()
            local fresh = ns.DB.CopyLines(defaults)
            for j = #lines, 1, -1 do lines[j] = nil end
            for j, l in ipairs(fresh) do lines[j] = l end
            UI.QuickBar.Refresh()
            UI.Refresh()
        end })
        L:Buttons(more)
    end,
})
