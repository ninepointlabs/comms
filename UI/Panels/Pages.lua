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
UI.RegisterPanel({
    key = "quick", label = "Quick lines",
    render = function(L)
        local s = ns.DB.Settings().quick
        L:Title("Quick lines", "Fire from the quick-bar or a key binding. In chat lockdown the line is put in Blizzard's chat box: press Enter.")
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
                ns.Print("Bind keys in Esc › Options › Keybindings › AddOns › Comms (Quick line 1-10, Open whisper window, Reply to last whisper).")
            end },
        })
        local channels = {}
        for _, c in ipairs(ns.QuickLines.CHANNELS) do table.insert(channels, { value = c, label = c == "auto" and "auto" or c }) end
        for i, line in ipairs(ns.QuickLines.Lines()) do
            L:Label(("Line %d"):format(i))
            L:Input(nil, line.text, function(t) line.text = t UI.QuickBar.Refresh() end, { hint = "Text", width = 380, maxLetters = 255 })
            L:Input(nil, line.label, function(t) line.label = ns.Trim(t):sub(1, 8) UI.QuickBar.Refresh() end, { hint = "Button label (8 letters)", width = 160, maxLetters = 8 })
            local key = GetBindingKey and ns.Try(GetBindingKey, "COMMS_QUICKLINE_" .. i)
            local needsHW = ns.QuickLines.NEEDS_HW[line.channel or ""]
            L:Choice("Channel", (needsHW and "Needs a click or key press (Forever rule). " or "") ..
                (key and ("Bound to " .. key .. ".") or "No key bound."), channels, line.channel or "auto", function(v)
                line.channel = v
                if v == "WHISPER" and not line.target then line.target = "auto" end
                if v == "CHANNEL" and not line.target then line.target = "LookingForGroup" end
            end)
            if line.channel == "WHISPER" then
                L:Choice("Whisper to", "auto = your target if it's a player, else the last person who whispered you.",
                    { { value = "auto", label = "auto" }, { value = "target", label = "target" }, { value = "last", label = "last whisperer" } },
                    line.target or "auto", function(v) line.target = v end)
            elseif line.channel == "CHANNEL" then
                L:Input("Channel name", line.target, function(t) line.target = ns.Trim(t) end, { width = 200 })
            end
            L:Buttons({
                { label = "Test (fires it)", onClick = function() ns.QuickLines.Fire(i, "click") end },
                { label = "Reset to default", onClick = function()
                    local d = ns.DB.QUICK_DEFAULTS[i]
                    for k in pairs(line) do line[k] = nil end
                    for k, v in pairs(d) do line[k] = v end
                    UI.QuickBar.Refresh()
                    UI.Refresh()
                end },
            })
        end
    end,
})
