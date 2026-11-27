-- Settings: Chat look · Input · Alerts · Channels · Whispers · Quick lines ·
-- History · About (the sister addons' Options style).
local _, ns = ...
local UI = ns.UI

UI.SettingsSections = UI.SettingsSections or {}
local S = UI.SettingsSections

local TABS = { "Chat look", "Input", "Alerts", "Channels", "Whispers", "Quick lines", "History", "About" }
UI.SETTINGS_TABS = TABS
local tab = TABS[1]

local function dim(text) return UI.Hex(UI.C.dim) .. text .. "|r" end
local function set() return ns.DB.Settings() end

local function splitList(text)
    local out = {}
    for part in tostring(text or ""):gmatch("[^,]+") do
        part = ns.Trim(part)
        if part ~= "" then table.insert(out, part) end
    end
    return out
end

S["Chat look"] = function(L)
    local f = set().format
    L:Check("Comms formatting on", f.enabled, function(v) f.enabled = v UI.Refresh() end)
    L:Check("Class-coloured names", f.classColors, function(v) f.classColors = v end,
        "Names whose class is known (from the sender, or seen before) take their class colour.")
    L:Check("Short channel names", f.shortChannels, function(v) f.shortChannels = v UI.Refresh() end,
        "[2. Trade] becomes [2. T].")
    L:Text(dim("Blizzard's chat code always shows the channel number, so short names read [2. T]. Party, Guild and Raid tags stay as Blizzard draws them: changing them would mean replacing Blizzard's chat strings, which breaks chat in dungeons."), { size = 12, indent = 30 })
    if f.shortChannels then
        L:Label("Channel short names")
        local keys = {}
        for k in pairs(f.channelMap) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            L:Input(k, f.channelMap[k], function(t) f.channelMap[k] = ns.Trim(t):sub(1, 6) end, { width = 120, maxLetters = 6, hint = "(full name)" })
        end
    end
    L:Label("Timestamps")
    local choices = { { value = false, label = "Blizzard's setting" } }
    for _, c in ipairs(ns.Format.TIMESTAMP_FORMATS) do table.insert(choices, c) end
    L:Choice("Timestamp format", "Uses Blizzard's own timestamp option, so it also works on locked lines. Current: " ..
        tostring(ns.Format.CurrentTimestamp() or "?"), choices, f.timestamps or false, function(v)
        if v == false then f.timestamps = nil else ns.Format.SetTimestamp(v) end
    end)
    L:Label("Links")
    local k = set().links
    L:Check("Make URLs clickable (click to copy)", k.urls, function(v) k.urls = v end)
    L:Check("Add an [invite] link to lines asking for an invite", k.invites, function(v) k.invites = v UI.Refresh() end,
        "Whispers, party, raid, instance and guild lines containing one of the words below.")
    if k.invites then
        L:Input("Invite words (comma separated)", table.concat(k.inviteWords, ", "), function(t) k.inviteWords = splitList(t) end, { width = 380 })
    end
    L:Check("Alt-click a name in chat to invite", k.altInvite, function(v) k.altInvite = v end)
    L:Label("Sticky channels")
    L:Text(dim("Last used chat type stays selected. Blizzard already does this for all of these; Comms only changes a type you change here (outside combat and dungeons)."), { size = 12 })
    for _, t in ipairs(ns.Sticky.TYPES) do
        L:Check(t.label, ns.Sticky.IsSticky(t.key), function(v) ns.Sticky.Set(t.key, v) UI.Refresh() end)
    end
end

S.Input = function(L)
    local s = set().input
    L:Check("Bigger chat box (restyles Blizzard's box; no replacement)", s.enabled, function(v) s.enabled = v ns.Input.Apply() UI.Refresh() end)
    local heights = { { value = 24, label = "24" }, { value = 28, label = "28" }, { value = 32, label = "32" }, { value = 38, label = "38" }, { value = 44, label = "44" } }
    L:Choice("Height", nil, heights, s.height, function(v) s.height = v ns.Input.Apply() end)
    local sizes = { { value = 13, label = "13" }, { value = 14, label = "14" }, { value = 15, label = "15" }, { value = 16, label = "16" }, { value = 18, label = "18" }, { value = 20, label = "20" } }
    L:Choice("Font size", nil, sizes, s.fontSize, function(v) s.fontSize = v ns.Input.Apply() end)
    L:Choice("Position", nil, { { value = "below", label = "Below chat" }, { value = "above", label = "Above chat" } }, s.position,
        function(v) s.position = v ns.Input.Apply() end)
    L:Check("Up/Down recall without Alt", s.noAlt, function(v) s.noAlt = v ns.Recall.Apply() end,
        "Your last 100 sent lines, kept across /reload and logout for every character.")
    if ns.Lockdown.Busy() then L:Flag("In combat or chat lockdown: changes apply when it ends.") end
    L:Label("Autocomplete (Tab)")
    local a = set().autocomplete
    L:Check("Tab completes names, commands and channels", a.enabled, function(v) a.enabled = v UI.Refresh() end)
    L:Check("Friends", a.friends, function(v) a.friends = v end)
    L:Check("Guild", a.guild, function(v) a.guild = v end)
    L:Check("Group", a.group, function(v) a.group = v end)
    L:Check("Recent whisper partners", a.whispers, function(v) a.whispers = v end)
    L:Check("People seen in chat", a.seen, function(v) a.seen = v end)
    L:Check("Channel names after /join and /leave", a.channels, function(v) a.channels = v end)
    L:Check("Slash commands (/tt, /inv, /comms ...)", a.commands, function(v) a.commands = v end)
    L:Text(dim("Blizzard already completes names after /w; Comms doesn't touch chat-type commands (/p, /g, /w) so your box can't be blocked in dungeons."), { size = 12 })
end

S.Alerts = function(L)
    local s = set().alerts
    L:Check("Alerts on", s.enabled, function(v) s.enabled = v end)
    L:Check("My character's name", s.myName, function(v) s.myName = v end)
    L:Input("Keywords (comma separated)", table.concat(s.keywords, ", "), function(t) s.keywords = splitList(t) end, { width = 420, hint = "e.g. tank, summon, wts" })
    L:Check("Whole words only", s.wholeWord, function(v) s.wholeWord = v end, "\"tank\" won't match \"tanks\" or \"tankard\".")
    L:Check("Play a sound", s.sound, function(v) s.sound = v UI.Refresh() end)
    if s.sound then
        local choices = {}
        for _, x in ipairs(ns.Alerts.SOUNDS) do table.insert(choices, { value = x.key, label = x.label }) end
        L:Choice("Sound", nil, choices, s.soundKit, function(v)
            s.soundKit = v
            ns.Alerts.Notify(nil)
        end)
    end
    L:Check("Flash the chat tab", s.flash, function(v) s.flash = v end)
    L:Text(dim("Locked lines (dungeons, battlegrounds) can't be read by addons, so they never alert."), { size = 12 })
end

S.Channels = function(L)
    local c = set().channels
    local list, override = ns.Channels.List()
    L:Choice("Mode", "Leave: you leave the channel. Hide: you stay in it but its lines don't show.",
        { { value = "leave", label = "Leave" }, { value = "hide", label = "Hide" } }, c.mode, function(v) c.mode = v end)
    L:Check("Different list on this character", override, function(v) ns.Channels.SetOverride(v) UI.Refresh() end,
        "Off: every character uses the account list (default).")
    L:Label(override and "This character" or "All characters")
    for _, ch in ipairs(ns.DB.CHANNELS) do
        local name = ns.Channels.NameFor(ch.id) or ch.label
        L:Check(name, list[ch.key], function(v) list[ch.key] = v end)
    end
    L:Check("Print a line when a channel is left", c.announce, function(v) c.announce = v end)
    L:Buttons({
        { label = "Leave now", onClick = function()
            local ok, why = ns.Channels.CanRunNow()
            if not ok then ns.Print("Not now (" .. why .. "); Comms will do it afterwards.") end
            ns.Channels.Run(true)
        end },
    })
    L:Label("Rejoin")
    L:Text(dim("Rejoining puts /join <channel> in the chat box; press Enter. Untick the channel above too, or it's left again next time you log in."), { size = 12 })
    local rj = ns.Channels.Rejoinable()
    if #rj == 0 then L:Text(dim("You're in every channel on the list.")) end
    for _, r in ipairs(rj) do
        L:Row({ title = r.name, button = { label = "Rejoin", onClick = function() ns.Channels.Rejoin(r.id) end } })
    end
end

S.Whispers = function(L)
    local s = set().whispers
    L:Check("Whisper window (a tab per person)", s.enabled, function(v) s.enabled = v UI.Refresh() end)
    L:Check("Also show whispers in main chat", s.showInMain, function(v) s.showInMain = v end,
        "In chat lockdown they always show in main chat (the window can't read them there).")
    L:Check("Open the window when a whisper arrives", s.openOnWhisper, function(v) s.openOnWhisper = v end)
    L:Check("Whisper sound from Comms too", s.sound, function(v) s.sound = v end, "Blizzard already plays one; this adds Comms' own.")
    L:Text(dim(("Kept for all characters: %d lines per contact, %d contacts, oldest pruned."):format(ns.DB.CAPS.whisperLines, ns.DB.CAPS.whisperContacts)), { size = 12 })
    L:Buttons({ { label = "Open whisper window", onClick = function() UI.Messenger.Open(nil, true) end } })
end

S["Quick lines"] = function(L)
    local s = set().quick
    local Sets = ns.QuickSets
    L:Check("Show the quick-bar", s.bar, function(v) s.bar = v UI.QuickBar.Refresh() end)
    L:Check("Hide the quick-bar in combat", s.barHideInCombat, function(v) s.barHideInCombat = v UI.QuickBar.Refresh() end,
        "Hides the situational row only. The Combat row stays visible in combat (that's its job) unless you turn it off below.")
    L:Text(dim("With this on, the Combat row still shows in combat; turn the Combat row off below to hide everything."), { size = 12, indent = 30 })
    L:Choice("In chat lockdown", "Addons can't send chat in dungeons and battlegrounds.",
        { { value = "prefill", label = "Put it in the chat box" }, { value = "show", label = "Show it to copy" } },
        s.lockdownAction, function(v) s.lockdownAction = v end)
    L:Label("Situational sets")
    L:Text(dim(Sets.Describe()), { size = 12 })
    L:Check("Switch sets automatically", s.auto, function(v)
        Sets.SetAuto(v)
        UI.Refresh()
    end, "Open World solo, Party / Dungeon in a group or dungeon, Raid / BG in a raid, battleground or arena. Only out of combat: a change in combat waits until it ends.")
    for _, k in ipairs(Sets.SITUATIONAL) do
        L:Check("Use " .. Sets.NAMES[k], Sets.Enabled(k), function(v)
            s.sets[k].enabled = v
            Sets.Evaluate()
            UI.QuickBar.Refresh()
        end, "Off: the next set that's on is used instead.")
    end
    local pickButtons = {}
    for _, k in ipairs(Sets.SITUATIONAL) do
        table.insert(pickButtons, { label = "Pin " .. Sets.SHORT[k], active = Sets.Pinned() == k, onClick = function()
            Sets.Pick(k)
            UI.Refresh()
        end })
    end
    table.insert(pickButtons, { label = "Automatic", active = s.auto and not Sets.Pinned(), onClick = function()
        Sets.Pick("auto")
        UI.Refresh()
    end })
    L:Buttons(pickButtons)
    L:Text(dim("A pin holds until you pick Automatic (or /comms set auto, or right-click the bar's set tab), or until the next login or /reload. /comms set world | party | raid | auto does the same."), { size = 12 })
    L:Label("Combat row")
    L:Choice("Show the Combat row", "Its own row of lines (oom, inc, peel me...) that never swaps in combat. Changes apply out of combat.",
        { { value = "always", label = "Always" }, { value = "groups", label = "Only in groups" }, { value = "off", label = "Off" } },
        s.combatRow, function(v) s.combatRow = v UI.QuickBar.Refresh() end)
    L:Buttons({
        { label = "Edit quick lines", onClick = function() UI.Open("quick") end },
        { label = "Edit Combat lines", onClick = function() UI.Open("quick", "combat") end },
    })
end

S.History = function(L)
    local s = set().history
    L:Check("Keep chat history across /reload and logout", s.enabled, function(v) s.enabled = v UI.Refresh() end)
    L:Check("Show it (dimmed) when you log in", s.replay, function(v) s.replay = v end)
    local sizes = { { value = 200, label = "200" }, { value = 500, label = "500" }, { value = 1000, label = "1,000" }, { value = 2000, label = "2,000" } }
    L:Choice("Lines per chat window", "Per character. Locked lines are never stored.", sizes, s.lines, function(v) s.lines = v end)
    L:Text(dim(("%d lines stored now (all characters)."):format(ns.History.Count())), { size = 12 })
    L:Buttons({
        { label = "Clear chat history", onClick = function() ns.History.Clear() UI.Refresh() end },
        { label = "Clear typed history", onClick = function() wipe(ns.db.global.typed) ns.Print("Typed history cleared.") end },
    })
end

S.About = function(L)
    local version = tostring(ns.VERSION)
    if not version:match("^v") then version = "v" .. version end
    L:Row({ icon = ns.ICON, title = ns.TITLE .. " " .. version, sub = "All-in-one text chat for WoW Forever." })
    L:Text("Comms by Nine Point Labs, not related to Forever Comms Voice / Guild Comms / Group Comms or Quick Comms.", { size = 12 })
    L:Label("Lockdown")
    L:Text(ns.Lockdown.Status(), { color = ns.Lockdown.ChatLocked() and UI.C.warn or UI.C.text })
    L:Text(dim("In dungeons, raids and battlegrounds WoW Forever hides chat from addons and lets you, not addons, send. Comms steps back there: Blizzard shows the lines plain, quick lines go into the chat box for you to send, and the whisper window points you to main chat."), { size = 12 })
    L:Label("Commands")
    L:Text("/comms  open or close the window\n/comms whispers · quick · settings · channels · search <text>\n/comms q <n>  fire quick line n of the active set\n/comms set world · party · raid · auto  pick a quick-line set\n/comms leave · /comms rejoin  channels\n/comms history clear · /comms setup · /comms help\n/tt [message]  whisper your target", { size = 12 })
    L:Label("Window")
    local g = ns.db.global
    L:Check("Show minimap button", not g.minimap.hide, function(v) g.minimap.hide = not v ns.Fire("MINIMAP_TOGGLE") end)
    L:Check("Same window positions on all characters", set().sameLayout, function(v) set().sameLayout = v end)
    L:Check("Debug messages", set().debug, function(v) set().debug = v end)
    L:Buttons({ { label = "Run first-time setup again", onClick = function() UI.Open("setup") end } })
    L:Label("Known conflicts")
    L:Text(dim("Prat, WIM, Chattynator, BigChatBox, Block Blizzard Chat Channels and Better Forever Chat do the same jobs; run only one of them alongside Comms if you must, and turn the overlapping Comms feature off."), { size = 12 })
    L:Label("Links")
    L:Link("Source and issues", "https://github.com/ninepointlabs/comms", "github.com/ninepointlabs/comms")
    L:Label("Credits")
    L:Row({ title = "Made by Nine Point Labs", sub = "Free and open source, MIT licence." })
    L:Text(dim("Comms is an unofficial fan project, not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc."), { size = 11 })
end

UI.RegisterPanel({
    key = "settings", label = "Settings",
    setSub = function(sub) for _, t in ipairs(TABS) do if t == sub then tab = sub end end end,
    render = function(L)
        L:Title("Settings", "Shared by all your characters.")
        local items = {}
        for _, t in ipairs(TABS) do
            table.insert(items, { label = t, active = tab == t, onClick = function() tab = t UI.Refresh() end })
        end
        L:Tabs(items)
        local fn = S[tab] or S["Chat look"]
        fn(L)
    end,
})
