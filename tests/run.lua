-- Headless tests. Run from the repo root:  lua5.1 tests/run.lua  (or luajit)
package.path = "./tests/?.lua;" .. package.path
local M = require("wow_mock")
M.Install()
local S = M.state

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n")
    end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end
local function has(list, pattern)
    for _, t in ipairs(list) do if tostring(t):find(pattern, 1, true) then return true end end
    return false
end
local function textHas(pattern) return has(M.texts, pattern) end
local function printed(pattern) return has(M.printed, pattern) end
local function readFile(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local function tocFiles(path)
    local out = {}
    for line in io.lines(path) do
        if not line:match("^##") and line:match("%S") then table.insert(out, (line:gsub("\\", "/"):gsub("%s+$", ""))) end
    end
    return out
end

-- A CHAT_MSG_* line through every registered filter (frame 1).
local function chat(event, o, frame)
    return M.RunFilters(frame or ChatFrame1, event, M.ChatArgs(o))
end

----------------------------------------------------------------------------
-- Forever-only guard: load once as a non-Forever client.
----------------------------------------------------------------------------
do
    rawset(_G, "WOW_PROJECT_ID", 2)
    local ns2 = M.LoadAddon("Comms_Forever.toc", ".")
    M.Fire("ADDON_LOADED", "Comms")
    M.Fire("PLAYER_LOGIN")
    test("Forever-only guard: nothing wired when WOW_PROJECT_ID is not 18", function()
        eq(ns2.disabled, true)
        eq(ns2.db, nil, "no saved variables wired")
        eq(CommsDB, nil, "no account DB created")
        truthy(printed("WoW Forever only"), "explains why")
        eq(next(M.messageFilters), nil, "no message filters")
        eq(#M.nameFilters, 0, "no sender-name filters")
        eq(next(M.callbacks), nil, "no EventRegistry callbacks")
        eq(M.hooked, nil, "no hooks")
        for _, eb in ipairs({ ChatFrame1EditBox, ChatFrame2EditBox }) do
            eq(next(eb.__hooks), nil, "no edit box hooks")
            eq(eb.__altArrow, nil, "edit box untouched")
        end
        M.printed = {}
        SlashCmdList.COMMS("")
        truthy(printed("Disabled: WoW Forever only"), "slash refuses")
        M.printed = {}
        SlashCmdList.COMMSTELLTARGET("hi")
        truthy(printed("Disabled: WoW Forever only"), "/tt refuses")
        eq(#M.sent, 0)
    end)
    M.events, M.printed, M.texts, M.timers = {}, {}, {}, {}
    rawset(_G, "WOW_PROJECT_ID", 18)
    rawset(_G, "Comms", nil)
end

M.InstallSecrets()
local ns = M.LoadAddon("Comms_Forever.toc", ".")

test("TOCs identical: Interface 16001, names, SavedVariables, every file exists", function()
    local a, b = readFile("Comms.toc"), readFile("Comms_Forever.toc")
    eq(a, b)
    truthy(a:find("## Interface: 16001\n", 1, true), "interface")
    truthy(a:find("## Title: Comms\n", 1, true), "title")
    truthy(a:find("## Author: Nine Point Labs", 1, true), "author")
    truthy(a:find("## Version: @project-version@", 1, true), "version token")
    truthy(a:find("## X-Website: https://github.com/ninepointlabs/comms", 1, true), "website")
    truthy(a:find("## IconTexture: Interface\\AddOns\\Comms\\Media\\Icon", 1, true), "icon")
    truthy(a:find("## SavedVariables: CommsDB\n", 1, true), "account saved variables")
    truthy(a:find("## SavedVariablesPerCharacter: CommsCharDB\n", 1, true), "character saved variables")
    truthy(a:find("not related to Forever Comms Voice", 1, true), "disclaimer in notes")
    truthy(not a:find("AddonCompartmentFunc", 1, true), "no extra global compartment function")
    local files = tocFiles("Comms.toc")
    eq(files[#files], "Core/Boot.lua", "Boot loads last")
    for _, f in ipairs(files) do truthy(io.open(f), "missing " .. f) end
    truthy(io.open("Bindings.xml"), "Bindings.xml")
    truthy(io.open("LICENSE"), "LICENSE")
end)

test("Bindings.xml: Comms header, 10 quick lines, whisper window, reply; labels defined", function()
    local x = readFile("Bindings.xml")
    truthy(x:find('header="COMMS"', 1, true), "header")
    for i = 1, 10 do
        truthy(x:find('name="COMMS_QUICKLINE_' .. i .. '"', 1, true), "binding " .. i)
        truthy(x:find("Comms.QuickLine(" .. i .. ")", 1, true), "calls quick line " .. i)
        eq(rawget(_G, "BINDING_NAME_COMMS_QUICKLINE_" .. i), "Quick line " .. i)
    end
    truthy(x:find("Comms.OpenWhispers()", 1, true) and x:find("Comms.ReplyLast()", 1, true), "whisper bindings")
    eq(BINDING_HEADER_COMMS, "Comms")
    eq(BINDING_NAME_COMMS_OPEN_WHISPERS, "Open whisper window")
    eq(BINDING_NAME_COMMS_REPLY_LAST, "Reply to last whisper")
    -- Binding names must not collide with Forever Comms bundle globals.
    truthy(not x:find("FGC_", 1, true) and not x:find("FGROUP_", 1, true) and not x:find("FOREVER", 1, true))
end)

test("icon is a 64x64 32-bit TGA with alpha", function()
    local d = readFile("Media/Icon.tga")
    eq(d:byte(3), 2, "uncompressed true colour")
    eq(d:byte(13) + d:byte(14) * 256, 64, "width")
    eq(d:byte(15) + d:byte(16) * 256, 64, "height")
    eq(d:byte(17), 32, "bpp")
    eq(#d, 18 + 64 * 64 * 4, "size")
end)

test("naming: no Forever Comms bundle / Quick Comms globals or slashes anywhere", function()
    for _, f in ipairs(tocFiles("Comms.toc")) do
        local s = readFile(f)
        for _, bad in ipairs({ "ForeverComms", "ForeverGuildComms", "ForeverGroupComms", "QuickComms", "SLASH_FC", "SLASH_QC",
            '"/fc"', '"/qc"', '"/gc"', '"/commsvoice"', '"/fcv"', '"/fgc"', '"/fgp"' }) do
            truthy(not s:find(bad, 1, true), f .. " uses " .. bad)
        end
        -- Every global assignment at file scope is Comms-prefixed or a binding/slash label.
        for name in s:gmatch("\n([%a_][%w_]*)%s*=[^=]") do
            truthy(name == "Comms" or name:match("^SLASH_COMMS") or name:match("^BINDING_") or name:match("^Comms"),
                f .. " assigns global " .. name)
        end
    end
end)

----------------------------------------------------------------------------
-- Taint audit (static): no module replaces Blizzard scripts or functions.
----------------------------------------------------------------------------
test("taint audit (source): only HookScript / hooksecurefunc / EventRegistry on Blizzard code", function()
    for _, f in ipairs(tocFiles("Comms.toc")) do
        local s = readFile(f)
        -- Blizzard objects' scripts are never replaced.
        for obj in s:gmatch("([%w_%.%[%]\"]+):SetScript%(") do
            truthy(not obj:find("EditBox", 1, true) and not obj:find("ChatFrame", 1, true) and obj ~= "eb" and obj ~= "cf",
                f .. ": SetScript on " .. obj)
        end
        -- No assignments to Blizzard functions, chat strings or tables.
        for _, pat in ipairs({ "ChatFrameUtil%.[%w_]+%s*=[^=]", "ChatEdit_[%w_]+%s*=[^=]", "SetItemRef%s*=[^=]",
            "CHAT_[%u_]+_GET%s*=[^=]", "ChatFrame_[%w_]+%s*=[^=]", "%.channelList", "%.zoneChannelList",
            "LinkUtil%.RegisterLinkHandler", "SendText%(", "SetAttribute%(", "AddChatWindowChannel", "RemoveChatWindowChannel",
            "SendAddonMessage" }) do
            truthy(not s:find(pat), f .. " matches forbidden pattern " .. pat)
        end
        -- Chat is only ever sent from QuickLines.Send.
        if f ~= "Modules/QuickLines.lua" then
            truthy(not s:find("SendChatMessage", 1, true), f .. " sends chat directly")
            truthy(not s:find("SendWhisper", 1, true) or f == "Modules/Whispers.lua" and not s:find("SendWhisper%(", 1), f .. " sends BN whispers directly")
        end
        -- Never a timer around sending.
        truthy(not s:find("C_Timer%.[%a]+%([^)]*Send"), f .. " sends from a timer")
    end
end)

----------------------------------------------------------------------------
-- Login
----------------------------------------------------------------------------
S.chatLocked = false
M.Fire("ADDON_LOADED", "Comms")
M.Fire("PLAYER_LOGIN")
M.RunTimers()

test("login wires DB, slash commands, filters, link and click callbacks, hooks", function()
    truthy(ns.db and CommsDB and CommsCharDB, "saved variables")
    eq(ns.db.global, CommsDB)
    eq(SLASH_COMMS1, "/comms")
    eq(SLASH_COMMSTELLTARGET1, "/tt")
    truthy(SlashCmdList.COMMS and SlashCmdList.COMMSTELLTARGET)
    for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_GUILD", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY" }) do
        eq(#(M.messageFilters[ev] or {}), 1, "one filter for " .. ev)
    end
    eq(#M.nameFilters, 1, "one sender-name filter")
    eq(#(M.callbacks.SetItemRef or {}), 1, "addon-link clicks via EventRegistry")
    eq(#(M.callbacks["ChatFrame.OnHyperlinkClick"] or {}), 1, "alt-click via EventRegistry")
    truthy(M.events.ADDON_RESTRICTION_STATE_CHANGED, "listens for restriction changes")
    truthy(M.events.CHAT_MSG_WHISPER and M.events.CHAT_MSG_BN_WHISPER, "whisper events")
    truthy(M.events.CHANNEL_UI_UPDATE and M.events.PLAYER_ENTERING_WORLD, "channel events")
    eq(ns.VERSION, "dev", "packager token reads as dev")
    eq(type(Comms), "table", "global Comms table")
    truthy(Comms.QuickLine and Comms.OpenWhispers and Comms.ReplyLast, "binding entry points")
end)

test("taint audit (runtime): Blizzard edit boxes/chat frames only hooked, never re-scripted", function()
    eq(#M.blizzardSetScript, 0, "SetScript on a Blizzard object: " .. (M.blizzardSetScript[1] and (M.blizzardSetScript[1].obj .. " " .. M.blizzardSetScript[1].ev) or ""))
    truthy(ChatFrame1EditBox.__hooks.OnTabPressed and ChatFrame1EditBox.__hooks.OnTextChanged, "HookScript used")
    truthy(has(M.hooked or {}, "AddHistoryLine"), "hooksecurefunc on AddHistoryLine")
    -- Blizzard's sticky defaults untouched (all already sticky on Forever).
    for _, k in ipairs({ "SAY", "PARTY", "RAID", "GUILD", "OFFICER", "INSTANCE_CHAT", "WHISPER", "CHANNEL" }) do
        eq(ChatTypeInfo[k].sticky, 1, k .. " sticky")
    end
    eq(ChatTypeInfo.YELL.sticky, 0, "yell untouched")
    eq(next(ns.DB.Settings().sticky.overrides), nil, "no sticky writes by default")
end)

test("defaults: account-wide settings, Services and Trade (City) leave on, others off", function()
    local s = ns.DB.Settings()
    eq(s.channels.list.Services, true); eq(s.channels.list.TradeCity, true)
    eq(s.channels.list.General, false); eq(s.channels.list.Trade, false)
    eq(s.channels.list.LocalDefense, false); eq(s.channels.list.LookingForGroup, false)
    eq(s.channels.mode, "leave")
    eq(s.history.lines, 500); eq(s.whispers.showInMain, true)
    eq(#s.quick.lines, 10, "10 quick lines")
    eq(s.quick.lines[1].text, "inv pls"); eq(s.quick.lines[2].text, "ty for the group!")
    eq(s.format.timestamps, nil, "timestamps left to Blizzard until Tim picks")
    eq(M.cvars.showTimestamps, "none", "CVar untouched")
    eq(ns.db.char.channelsOverride, nil, "no per-character override")
end)

test("first-run setup opens once, 3 steps, then never again on any character", function()
    truthy(ns.UI.IsShown(), "setup opened after login")
    eq(ns.UI.Current(), "setup")
    M.texts = {}
    ns.UI.Refresh()
    truthy(textHas("Step 1 of 3"), "step 1")
    truthy(textHas("WHICH CHANNELS SHOULD COMMS LEAVE"), "channels step")
    M.left = {}
    ns.UI.FinishSetup()
    eq(ns.db.global.firstRunDone, true)
    eq(ns.UI.Current(), "whispers")
end)

----------------------------------------------------------------------------
-- Lockdown
----------------------------------------------------------------------------
test("lockdown: API + ADDON_RESTRICTION_STATE_CHANGED (Activating counts) fire LOCKDOWN_CHANGED", function()
    local seen = {}
    ns.On("LOCKDOWN_CHANGED", function(locked, reason) table.insert(seen, { locked, reason }) end)
    eq(ns.Lockdown.ChatLocked(), false)
    M.Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 1) -- Chat, Activating
    eq(ns.Lockdown.ChatLocked(), true, "activating counts as locked")
    eq(seen[#seen][1], true)
    M.Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    eq(ns.Lockdown.ChatLocked(), false)
    eq(seen[#seen][1], false)
    S.chatLocked = true
    S.instanceType = "party"
    eq(ns.Lockdown.ChatLocked(), true, "InChatMessagingLockdown")
    truthy(ns.Lockdown.Status():find("Chat locked: yes (instance)", 1, true), ns.Lockdown.Status())
    S.chatLocked = false
    S.instanceType = nil
    S.restrictions[5] = true
    eq(ns.Lockdown.ChatLocked(), true, "IsAddOnRestrictionActive(Chat)")
    S.restrictions[5] = nil
    S.combat = true
    eq(ns.Lockdown.Busy(), true, "combat = busy")
    eq(ns.Lockdown.CanSend(), true, "combat alone doesn't stop chat")
    S.combat = false
    ns.Lockdown.Recompute()
end)

----------------------------------------------------------------------------
-- Format
----------------------------------------------------------------------------
S.guids["Player-1-00000B0B"] = { class = "WARRIOR" }

test("format: class-coloured names via the sender-name filter; already coloured left alone", function()
    local out = M.RunNameFilters("CHAT_MSG_SAY", "Bob", M.ChatArgs({ msg = "hi", author = "Bob", guid = "Player-1-00000B0B" }))
    eq(out, "|cffc79c6eBob|r")
    eq(M.RunNameFilters("CHAT_MSG_SAY", "|cff112233Bob|r", M.ChatArgs({ msg = "hi", author = "Bob", guid = "Player-1-00000B0B" })),
        "|cff112233Bob|r", "already coloured")
    eq(M.RunNameFilters("CHAT_MSG_SAY", "Nobody", M.ChatArgs({ msg = "hi", author = "Nobody", guid = "Player-1-0000FFFF" })),
        "Nobody", "unknown class unchanged")
    ns.DB.Settings().format.classColors = false
    eq(M.RunNameFilters("CHAT_MSG_SAY", "Bob", M.ChatArgs({ msg = "hi", author = "Bob", guid = "Player-1-00000B0B" })), "Bob", "off")
    ns.DB.Settings().format.classColors = true
    -- Secret guid: untouched.
    eq(ns.Filters.NameFilter("CHAT_MSG_SAY", "Bob", M.ChatArgs({ msg = "hi", author = "Bob", guid = M.SECRET })), nil)
end)

test("format: short channel names keep Blizzard's 'N. ' prefix and the original length", function()
    local discard, msg, author, lang, channel = chat("CHAT_MSG_CHANNEL", { msg = "WTS stuff", author = "Bob", channel = "2. Trade - City",
        zoneID = 46, channelNum = 2, channelBase = "Trade - City", lineID = 101, guid = "Player-1-00000B0B" })
    eq(discard, false)
    truthy(channel:match("^2%. TC"), "short: " .. channel)
    truthy(#channel >= #"2. Trade - City", "length kept for Blizzard's channel match")
    eq(ns.Plain(channel), "2. TC", "padding is invisible")
    -- General with zone suffix
    local _, _, _, _, ch2 = chat("CHAT_MSG_CHANNEL", { msg = "hello", author = "Bob", channel = "1. General - Stormwind City",
        zoneID = 1, channelNum = 1, channelBase = "General", lineID = 102 })
    eq(ns.Plain(ch2), "1. G")
    -- Unknown channel left alone
    local _, _, _, _, ch3 = chat("CHAT_MSG_CHANNEL", { msg = "x", author = "Bob", channel = "5. MyGuildAlts",
        channelNum = 5, channelBase = "MyGuildAlts", lineID = 103 })
    eq(ch3, "5. MyGuildAlts")
    ns.DB.Settings().format.shortChannels = false
    local _, _, _, _, ch4 = chat("CHAT_MSG_CHANNEL", { msg = "y", author = "Bob", channel = "2. Trade - City",
        channelNum = 2, channelBase = "Trade - City", lineID = 104 })
    eq(ch4, "2. Trade - City", "off")
    ns.DB.Settings().format.shortChannels = true
end)

test("format: timestamps through Blizzard's CVar, on/off, deferred in lockdown", function()
    ns.Format.SetTimestamp("%H:%M ")
    eq(M.cvars.showTimestamps, "%H:%M ")
    ns.Format.SetTimestamp("none")
    eq(M.cvars.showTimestamps, "none", "off")
    S.chatLocked = true
    ns.Lockdown.Recompute()
    ns.Format.SetTimestamp("[%H:%M] ")
    eq(M.cvars.showTimestamps, "none", "not while locked")
    S.chatLocked = false
    ns.Lockdown.Recompute()
    eq(M.cvars.showTimestamps, "[%H:%M] ", "applied when unlocked")
end)

test("filters: any secret arg -> line untouched (registry skip and our own check)", function()
    -- Through Blizzard-like registry: skipped entirely.
    local discard, msg = chat("CHAT_MSG_GUILD", { msg = M.SECRET, author = M.SECRET, lineID = 201 })
    eq(discard, false); eq(msg, M.SECRET)
    -- Called directly: returns false, no new args.
    local r = { ns.Filters.Filter(ChatFrame1, "CHAT_MSG_GUILD", M.ChatArgs({ msg = "Andric www.example.com", author = M.SECRET, lineID = 202 })) }
    eq(r[1], false); eq(r[2], nil, "no replacement args")
    -- A stage error also leaves the line alone.
    ns.Filters.Add("boom", function() error("boom") end)
    local r2 = { ns.Filters.Filter(ChatFrame1, "CHAT_MSG_SAY", M.ChatArgs({ msg = "www.example.com", author = "Bob", lineID = 203 })) }
    eq(r2[1], false); eq(r2[2], nil, "error -> untouched")
    table.remove(ns.Filters.stages)
end)

----------------------------------------------------------------------------
-- Links
----------------------------------------------------------------------------
test("links: URL patterns (http, https, www., domain.tld/path), punctuation, no false hits", function()
    local function urls(t)
        local out = {}
        for _, f in ipairs(ns.Links.FindURLs(t)) do table.insert(out, f.url) end
        return table.concat(out, " ")
    end
    eq(urls("see https://wowforevertierlist.com/addons/restrictions."), "https://wowforevertierlist.com/addons/restrictions")
    eq(urls("http://x.io/a?b=1&c=2, ok"), "http://x.io/a?b=1&c=2")
    eq(urls("go to www.myazerothlife.com now"), "www.myazerothlife.com")
    eq(urls("myazerothlife.com/comms is up"), "myazerothlife.com/comms")
    eq(urls("lol.no idea, 3.5 dps, Mr.Smith"), "", "no false positives")
    eq(urls("two: www.a-b.com and https://c.org/x"), "www.a-b.com https://c.org/x")
    local out, changed = ns.Links.LinkURLs("look www.example.com/x ok")
    truthy(changed)
    truthy(out:find("|Haddon:Comms:url:%d+|h%[www.example.com/x%]|h"), out)
    -- Existing links are never rewritten.
    local item = "|cff1eff00|Hitem:1234::::::::60:::::|h[www.fake.com/sword]|h|r"
    local out2 = ns.Links.LinkURLs("buy " .. item)
    eq(out2, "buy " .. item)
end)

test("links: clicking a URL link opens the copy box; [invite] link invites", function()
    local _, msg = chat("CHAT_MSG_SAY", { msg = "guide at https://example.com/guide", author = "Bob", lineID = 301 })
    local link = msg:match("|H(addon:Comms:url:%d+)|h")
    truthy(link, msg)
    M.popups = {}
    M.Trigger("SetItemRef", link, "[x]", "LeftButton", ChatFrame1)
    eq(M.popups[#M.popups].which, "COMMS_COPY_TEXT")
    eq(M.popups[#M.popups].data, "https://example.com/guide")
    -- Invite words in a whisper.
    M.invites = {}
    local _, wmsg = chat("CHAT_MSG_WHISPER", { msg = "can I get an inv?", author = "Bob-OtherRealm", lineID = 302 })
    local inv = wmsg:match("|H(addon:Comms:inv:%d+)|h%[invite%]|h")
    truthy(inv, wmsg)
    M.Trigger("SetItemRef", inv, "[invite]", "LeftButton", ChatFrame1)
    eq(M.invites[1], "Bob-OtherRealm", "C_PartyInfo.InviteUnit with the sender")
    -- +1 inv phrase in party, case-insensitive
    local _, pmsg = chat("CHAT_MSG_PARTY", { msg = "+1 INV please", author = "Cara", lineID = 303 })
    truthy(pmsg:find("[invite]", 1, true), "phrase")
    -- Not for "invitation", not in SAY, not my own lines
    local _, m1 = chat("CHAT_MSG_WHISPER", { msg = "invitation sent", author = "Bob", lineID = 304 })
    truthy(not m1:find("[invite]", 1, true), "whole word")
    local _, m2 = chat("CHAT_MSG_SAY", { msg = "inv", author = "Bob", lineID = 305 })
    truthy(not m2:find("[invite]", 1, true), "say isn't an invite channel")
    local _, m3 = chat("CHAT_MSG_PARTY", { msg = "inv", author = "Andric", lineID = 306 })
    truthy(not m3:find("[invite]", 1, true), "my own line")
    -- Unknown / foreign addon links ignored.
    M.Trigger("SetItemRef", "addon:OtherAddon:thing", "[x]", "LeftButton", ChatFrame1)
end)

test("alt-click a name invites; plain click and secret names don't", function()
    M.invites = {}
    S.alt = true
    M.Trigger("ChatFrame.OnHyperlinkClick", ChatFrame1, "player:Bob-OtherRealm:12:GUILD", "[Bob]", "LeftButton")
    eq(M.invites[1], "Bob-OtherRealm")
    M.Trigger("ChatFrame.OnHyperlinkClick", ChatFrame1, M.SECRET, "[?]", "LeftButton")
    eq(#M.invites, 1, "secret link ignored")
    M.Trigger("ChatFrame.OnHyperlinkClick", ChatFrame1, "item:1234", "[x]", "LeftButton")
    eq(#M.invites, 1, "not a player link")
    S.alt = false
    M.Trigger("ChatFrame.OnHyperlinkClick", ChatFrame1, "player:Cara", "[Cara]", "LeftButton")
    eq(#M.invites, 1, "no Alt, no invite")
    ns.DB.Settings().links.altInvite = false
    S.alt = true
    M.Trigger("ChatFrame.OnHyperlinkClick", ChatFrame1, "player:Cara", "[Cara]", "LeftButton")
    eq(#M.invites, 1, "setting off")
    S.alt = false
    ns.DB.Settings().links.altInvite = true
end)

----------------------------------------------------------------------------
-- /tt
----------------------------------------------------------------------------
test("/tt: whisper target (same realm, cross-realm), no message prefills, no target explains", function()
    M.sent, M.opened, M.printed = {}, {}, {}
    SlashCmdList.COMMSTELLTARGET("hi")
    truthy(printed("You have no target."))
    eq(#M.sent, 0)
    S.units.target = { guid = "Player-1-00000B0B", name = "Bob", class = "WARRIOR" }
    SlashCmdList.COMMSTELLTARGET("hello there")
    eq(M.sent[1].text, "hello there"); eq(M.sent[1].chatType, "WHISPER"); eq(M.sent[1].target, "Bob")
    S.units.target.realm = "Other Realm"
    SlashCmdList.COMMSTELLTARGET("hey")
    eq(M.sent[2].target, "Bob-Other Realm", "realm-aware")
    SlashCmdList.COMMSTELLTARGET("")
    eq(M.opened[1], "/w Bob-Other Realm ", "no message: opens the box")
    -- Lockdown: prefill, never send.
    S.chatLocked = true
    SlashCmdList.COMMSTELLTARGET("lfg?")
    eq(#M.sent, 2, "nothing sent in lockdown")
    eq(M.opened[2], "/w Bob-Other Realm lfg?")
    -- Secret target name.
    S.units.target = { name = M.SECRET, realm = nil }
    M.printed = {}
    SlashCmdList.COMMSTELLTARGET("x")
    truthy(printed("hides your target's name"))
    S.chatLocked = false
    S.units.target = { name = "Npc", player = false }
    M.printed = {}
    SlashCmdList.COMMSTELLTARGET("x")
    truthy(printed("isn't a player"))
    S.units.target = nil
end)

----------------------------------------------------------------------------
-- Alerts
----------------------------------------------------------------------------
test("alerts: my name and keywords, whole word, any case; sound + flash + list; once per line", function()
    M.sounds, M.flashes = {}, {}
    local before = #ns.db.global.alerts
    chat("CHAT_MSG_GUILD", { msg = "anyone seen ANDRIC?", author = "Bob", lineID = 401 })
    eq(#ns.db.global.alerts, before + 1, "name alert")
    eq(ns.db.global.alerts[#ns.db.global.alerts].word, "Andric")
    eq(M.sounds[#M.sounds], SOUNDKIT.RAID_WARNING)
    eq(M.flashes[#M.flashes], ChatFrame1, "tab flash")
    -- Same line shown in a second window: no second alert.
    chat("CHAT_MSG_GUILD", { msg = "anyone seen ANDRIC?", author = "Bob", lineID = 401 }, ChatFrame2)
    eq(#ns.db.global.alerts, before + 1, "once per line")
    ns.DB.Settings().alerts.keywords = { "tank" }
    chat("CHAT_MSG_CHANNEL", { msg = "LF1M Tank for Deadmines", author = "Cara", channel = "4. LookingForGroup",
        channelBase = "LookingForGroup", channelNum = 4, lineID = 402 })
    eq(#ns.db.global.alerts, before + 2, "keyword")
    eq(ns.db.global.alerts[#ns.db.global.alerts].channel, "LookingForGroup")
    chat("CHAT_MSG_SAY", { msg = "tanks are great", author = "Cara", lineID = 403 })
    eq(#ns.db.global.alerts, before + 2, "whole word: tanks doesn't match")
    ns.DB.Settings().alerts.wholeWord = false
    chat("CHAT_MSG_SAY", { msg = "tanks are great", author = "Cara", lineID = 404 })
    eq(#ns.db.global.alerts, before + 3, "substring when whole-word off")
    ns.DB.Settings().alerts.wholeWord = true
    chat("CHAT_MSG_SAY", { msg = "I am Andric", author = "Andric", lineID = 405 })
    eq(#ns.db.global.alerts, before + 3, "my own line")
    chat("CHAT_MSG_GUILD", { msg = M.SECRET, author = M.SECRET, lineID = 406 })
    ns.Filters.Filter(ChatFrame1, "CHAT_MSG_GUILD", M.ChatArgs({ msg = "Andric!", author = M.SECRET, lineID = 407 }))
    eq(#ns.db.global.alerts, before + 3, "no alert on secret lines")
    truthy(ns.Alerts.unread >= 3, "unread badge")
    M.texts = {}
    ns.UI.Open("alerts")
    truthy(textHas("LF1M Tank for Deadmines"), "listed")
    eq(ns.Alerts.unread, 0, "read when viewed")
end)

----------------------------------------------------------------------------
-- Typed history (Recall)
----------------------------------------------------------------------------
test("typed history: Up/Down without Alt, survives a simulated reload, capped at 100", function()
    eq(ChatFrame1EditBox.__altArrow, false, "SetAltArrowKeyMode(false)")
    eq(ChatFrame2EditBox.__altArrow, false)
    eq(ChatFrame1EditBox.__historyLines, 100, "history lines raised to 100")
    ChatFrame1EditBox:AddHistoryLine("/p ty all")
    ChatFrame1EditBox:AddHistoryLine("/g hello guild")
    ChatFrame1EditBox:AddHistoryLine("/g hello guild") -- consecutive duplicate
    local typed = ns.db.global.typed
    eq(typed[#typed], "/g hello guild")
    eq(typed[#typed - 1], "/p ty all")
    for i = 1, 150 do ChatFrame1EditBox:AddHistoryLine("line " .. i) end
    eq(#typed, 100, "cap 100")
    eq(typed[100], "line 150")
    -- Reload: a fresh edit box gets the saved lines back, oldest first.
    ChatFrame2EditBox.__history = {}
    local n = ns.Recall.Refill()
    truthy(n >= 200, "refilled both boxes")
    eq(ChatFrame2EditBox.__history[100], "line 150")
    eq(ChatFrame2EditBox.__history[1], "line 51")
    eq(#typed, 100, "refill isn't re-recorded")
    -- Lockdown: nothing recorded, no refill.
    S.chatLocked = true
    ns.Lockdown.Recompute()
    ChatFrame1EditBox:AddHistoryLine("/i secret plan")
    eq(typed[#typed], "line 150", "not recorded in lockdown")
    eq(ns.Recall.Refill(), 0, "deferred")
    S.chatLocked = false
    ns.Lockdown.Recompute()
    -- Option off: Alt mode back on.
    ns.DB.Settings().input.noAlt = false
    ns.Recall.Apply()
    eq(ChatFrame1EditBox.__altArrow, true)
    ns.DB.Settings().input.noAlt = true
    ns.Recall.Apply()
end)

test("input: bigger box restyles Blizzard's box only outside lockdown/combat; restore on off", function()
    eq(ChatFrame1EditBox.__h, 32, "height")
    eq(select(2, ChatFrame1EditBox:GetFont()), 15, "font size")
    S.combat = true
    ns.DB.Settings().input.height = 44
    eq(ns.Input.Apply(), 0, "deferred in combat")
    eq(ChatFrame1EditBox.__h, 32)
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(ChatFrame1EditBox.__h, 44, "applied after combat")
    ns.DB.Settings().input.enabled = false
    ns.Input.Apply()
    eq(ChatFrame1EditBox.__h, 20, "restored")
    ns.DB.Settings().input.enabled = true
    ns.DB.Settings().input.height = 32
    ns.Input.Apply()
end)

----------------------------------------------------------------------------
-- Autocomplete
----------------------------------------------------------------------------
test("autocomplete: names from each source, de-dup, realms, commands, channels", function()
    S.friends = { { name = "Fiona", connected = true } }
    S.guild = { "Gordo-CAMWOWUS2Realm1PvE", "Gwen-Faraway" }
    S.group = "party"
    S.units.party1 = { name = "Pip", realm = nil }
    S.groupMembers = { party1 = true }
    ns.db.global.seenNames["sam-camwowus2realm1pve"] = { name = "Sam", t = S.now }
    ns.db.global.seenNames["fiona-camwowus2realm1pve"] = { name = "Fiona", t = S.now }
    local names = table.concat(ns.Autocomplete.Names(), ",")
    truthy(names:find("Fiona"), names); truthy(names:find("Gordo"), "own realm dropped: " .. names)
    truthy(names:find("Gwen-Faraway", 1, true), "other realm kept"); truthy(names:find("Pip")); truthy(names:find("Sam"))
    local count = 0
    for _ in names:gmatch("Fiona") do count = count + 1 end
    eq(count, 1, "de-duplicated")
    eq((ns.Autocomplete.Complete("hey fi")), "hey Fiona ")
    eq((ns.Autocomplete.Complete("hey gw")), "hey Gwen-Faraway ")
    eq((ns.Autocomplete.Complete("/tt pi")), "/tt Pip ", "after /tt")
    eq((ns.Autocomplete.Complete("/co")), "/comms ", "own command")
    eq((ns.Autocomplete.Complete("/join Tr")), "/join Trade ", "channel after /join")
    eq(ns.Autocomplete.Complete("/p"), nil, "chat-type commands never completed")
    eq(ns.Autocomplete.Complete("/w fi"), nil, "Blizzard completes /w names")
    eq(ns.Autocomplete.Complete("/p hey fi"), nil, "nothing inside chat-type commands")
    eq(ns.Autocomplete.Complete("x"), nil, "one letter isn't enough")
    -- Cycling through matches.
    eq((ns.Autocomplete.Complete("g", nil, 1)), nil)
    local a = ns.Autocomplete.Complete("go gw", nil, 1)
    eq(a, "go Gwen-Faraway ")
    -- Source switches.
    ns.DB.Settings().autocomplete.friends = false
    ns.db.global.seenNames["fiona-camwowus2realm1pve"] = nil
    eq(ns.Autocomplete.Complete("hey fi"), nil, "friends off")
    ns.DB.Settings().autocomplete.friends = true
    S.group = nil
    S.groupMembers = {}
    S.units.party1 = nil
end)

test("autocomplete: Tab hook completes, leaves Blizzard's own changes and lockdown alone", function()
    local eb = ChatFrame1EditBox
    eb.__text = "hey fi"
    M.RunScript(eb, "OnTextChanged", true)
    M.RunScript(eb, "OnTabPressed")
    eq(eb.__text, "hey Fiona ")
    -- Blizzard changed text itself on this Tab (e.g. whisper target cycling).
    eb.__text = "hey fi"
    M.RunScript(eb, "OnTextChanged", true)
    eb.__text = "/w Fiona "
    M.RunScript(eb, "OnTabPressed")
    eq(eb.__text, "/w Fiona ", "left alone")
    -- Lockdown: hook does nothing.
    eb.__text = "hey fi"
    M.RunScript(eb, "OnTextChanged", true)
    S.chatLocked = true
    M.RunScript(eb, "OnTabPressed")
    eq(eb.__text, "hey fi", "untouched in lockdown")
    S.chatLocked = false
    S.combat = true
    M.RunScript(eb, "OnTabPressed")
    eq(eb.__text, "hey fi", "untouched in combat")
    S.combat = false
    eb.__text = ""
end)

----------------------------------------------------------------------------
-- Channels
----------------------------------------------------------------------------
test("channels: leaves the selected IDs on PLAYER_ENTERING_WORLD, one line each", function()
    M.left, M.printed = {}, {}
    S.channels = { General = 1, Trade = 2, Services = 4, ["Trade (City)"] = 5, LocalDefense = 3 }
    M.Fire("PLAYER_ENTERING_WORLD")
    M.RunTimers()
    table.sort(M.left)
    eq(table.concat(M.left, ","), "Services,Trade (City)")
    truthy(printed("Left Services."), "one line per leave")
    truthy(printed("Left Trade (City)."))
    M.left = {}
    M.Fire("CHANNEL_UI_UPDATE")
    M.RunTimers()
    eq(#M.left, 0, "nothing left to leave")
end)

test("channels: skipped in lockdown/instance, retried when the restriction ends", function()
    M.left = {}
    S.channels.Services = 4
    S.instanceType = "party"
    M.Fire("PLAYER_ENTERING_WORLD")
    M.RunTimers()
    eq(#M.left, 0, "not in an instance")
    eq(ns.Channels.pending, true)
    S.instanceType = nil
    S.chatLocked = true
    ns.Lockdown.Recompute()
    M.Fire("CHANNEL_UI_UPDATE")
    M.RunTimers()
    eq(#M.left, 0, "not in lockdown")
    S.chatLocked = false
    M.Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    M.RunTimers()
    eq(M.left[1], "Services", "retried after lockdown")
end)

test("channels: per-character override; account list applies to every other character", function()
    ns.Channels.SetOverride(true)
    local list, override = ns.Channels.List()
    eq(override, true)
    list.General = true
    M.left = {}
    ns.Channels.Run()
    eq(M.left[1], "General", "this character leaves General too")
    eq(ns.DB.Settings().channels.list.General, false, "account list unchanged")
    ns.Channels.SetOverride(false)
    eq(ns.db.char.channelsOverride, nil)
    S.channels.General = 1
end)

test("channels: hide mode drops the channel's lines instead of leaving; rejoin prefills /join", function()
    local c = ns.DB.Settings().channels
    c.mode = "hide"
    S.channels.Services = 4
    M.left = {}
    ns.Channels.Run()
    eq(#M.left, 0, "hide mode doesn't leave")
    local discard = chat("CHAT_MSG_CHANNEL", { msg = "boost 10g", author = "Spam", channel = "4. Services", zoneID = 42,
        channelNum = 4, channelBase = "Services", lineID = 501 })
    eq(discard, true, "hidden")
    local d2 = chat("CHAT_MSG_CHANNEL", { msg = "wts", author = "Spam", channel = "2. Trade", zoneID = 2,
        channelNum = 2, channelBase = "Trade", lineID = 502 })
    eq(d2, false, "Trade not on the list")
    c.mode = "leave"
    S.channels.Services = nil
    M.opened = {}
    ns.Channels.Rejoin(42)
    eq(M.opened[1], "/join Services", "Blizzard's /join, Tim presses Enter")
    M.opened, M.printed = {}, {}
    SlashCmdList.COMMS("rejoin")
    eq(M.opened[1], "/join Trade (City)", "first channel on the list that we're not in")
    truthy(printed("1 more"), "says how many are left")
end)

----------------------------------------------------------------------------
-- Whispers
----------------------------------------------------------------------------
test("whispers: a tab per contact, Battle.net separate, unread, replies sent from Enter", function()
    M.Fire("CHAT_MSG_WHISPER", M.ChatArgs({ msg = "hey!", author = "Bob-OtherRealm", guid = "Player-1-00000B0B", lineID = 601 }))
    M.Fire("CHAT_MSG_WHISPER_INFORM", M.ChatArgs({ msg = "hi Bob", author = "Bob-OtherRealm", lineID = 602 }))
    S.bnet[77] = { battleTag = "Friendo#1234" }
    M.Fire("CHAT_MSG_BN_WHISPER", M.ChatArgs({ msg = "yo", author = "|Kq12|k", bnet = 77, lineID = 603 }))
    local w = ns.db.global.whispers
    local bob = w["w:bob-otherrealm"]
    truthy(bob, "contact by name-realm")
    eq(#bob.lines, 2); eq(bob.lines[1].d, "in"); eq(bob.lines[2].d, "out")
    eq(bob.class, "WARRIOR")
    eq(bob.unread, 1)
    local bn = w["bn:friendo#1234"]
    truthy(bn and bn.bnet, "Battle.net tab keyed by BattleTag")
    eq(bn.display, "Friendo")
    eq(ns.Whispers.Unread(), 2)
    ns.UI.Messenger.Open("w:bob-otherrealm")
    eq(bob.unread, 0, "read when opened")
    M.sent = {}
    ns.UI.Messenger.SendReply("see you at the inn")
    eq(M.sent[1].chatType, "WHISPER"); eq(M.sent[1].target, "Bob-OtherRealm")
    ns.UI.Messenger.Open("bn:friendo#1234")
    ns.UI.Messenger.SendReply("hi friend")
    eq(M.sent[2].chatType, "BN_WHISPER"); eq(M.sent[2].target, 77)
end)

test("whispers: 'also show in main chat' off drops them from Blizzard's frame; on keeps them", function()
    eq(chat("CHAT_MSG_WHISPER", { msg = "x", author = "Bob", lineID = 610 }), false, "default: shown in main")
    ns.DB.Settings().whispers.showInMain = false
    eq(chat("CHAT_MSG_WHISPER", { msg = "x", author = "Bob", lineID = 611 }), true, "hidden from main")
    -- Locked whispers: filters never run, so they always show in main chat.
    eq(chat("CHAT_MSG_WHISPER", { msg = M.SECRET, author = M.SECRET, lineID = 612 }), false, "locked: Blizzard shows it")
    ns.DB.Settings().whispers.showInMain = true
end)

test("whispers: secret events store nothing; window shows the lockdown banner and 'Reply in chat'", function()
    local before = #ns.db.global.whispers["w:bob-otherrealm"].lines
    M.Fire("CHAT_MSG_WHISPER", M.ChatArgs({ msg = M.SECRET, author = M.SECRET, lineID = 620 }))
    M.Fire("CHAT_MSG_WHISPER", M.ChatArgs({ msg = "visible text", author = M.SECRET, lineID = 621 }))
    eq(#ns.db.global.whispers["w:bob-otherrealm"].lines, before, "nothing stored")
    for k in pairs(ns.db.global.whispers) do truthy(k ~= "w:<secret>", "no secret key") end
    S.chatLocked = true
    ns.Lockdown.Recompute()
    ns.UI.Messenger.Open("w:bob-otherrealm")
    local f = CommsMessenger
    eq(f.banner.__shown, true, "banner")
    eq(f.banner.__text, "Chat is locked here; whispers show in main chat.")
    eq(f.reply.__shown, false, "reply box hidden")
    eq(f.inChat.__shown, true, "Reply in chat shown")
    M.sent, M.opened = {}, {}
    ns.UI.Messenger.SendReply("typed before lock")
    eq(#M.sent, 0, "never sends in lockdown")
    eq(M.opened[1], "/w Bob-OtherRealm typed before lock")
    ns.UI.Messenger.ReplyInChat()
    eq(M.opened[2], "/w Bob-OtherRealm ")
    S.chatLocked = false
    ns.Lockdown.Recompute()
    eq(f.banner.__shown, false, "banner gone after lockdown")
end)

test("whispers: caps (200 lines/contact, 50 contacts, oldest pruned), account-wide", function()
    for i = 1, 230 do ns.Whispers.Add("w:bob-otherrealm", "Bob-OtherRealm", false, "in", "msg " .. i) end
    local bob = ns.db.global.whispers["w:bob-otherrealm"]
    eq(#bob.lines, 200, "200 lines")
    eq(bob.lines[200].m, "msg 230")
    for i = 1, 60 do
        S.now = S.now + 1
        ns.Whispers.Add("w:p" .. i, "P" .. i, false, "in", "hi")
    end
    eq(ns.Whispers.Count(), 50, "50 contacts")
    eq(ns.db.global.whispers["w:p1"], nil, "oldest pruned")
    truthy(ns.db.global.whispers["w:p60"], "newest kept")
    -- Another character on the account sees the same whispers.
    local acc2 = ns.DB.Init(CommsDB, nil)
    truthy(acc2.whispers["w:p60"], "account-wide")
    CommsDB, CommsCharDB = ns.DB.Init(CommsDB, CommsCharDB)
end)

----------------------------------------------------------------------------
-- Quick lines
----------------------------------------------------------------------------
test("quick lines: auto channel picks INSTANCE > RAID > PARTY > SAY; click sends", function()
    M.sent = {}
    S.group = nil
    eq(ns.QuickLines.Fire(2, "click"), "sent")
    eq(M.sent[1].chatType, "SAY")
    S.group = "party"
    ns.QuickLines.Fire(2, "click")
    eq(M.sent[2].chatType, "PARTY")
    S.group = "raid"
    ns.QuickLines.Fire(2, "click")
    eq(M.sent[3].chatType, "RAID")
    S.group = "instance"
    ns.QuickLines.Fire(9, "key")
    eq(M.sent[4].chatType, "INSTANCE_CHAT")
    eq(M.sent[4].text, "gg")
    S.group = nil
end)

test("quick lines: only click/key/slash can fire; never automatic", function()
    M.sent = {}
    eq(ns.QuickLines.Fire(3, nil), nil)
    eq(ns.QuickLines.Fire(3, "timer"), nil)
    eq(ns.QuickLines.Fire(3, "event"), nil)
    eq(#M.sent, 0)
    eq(Comms.QuickLine(3), "sent", "key binding path")
    eq(M.sent[1].text, "brb")
    eq(SlashCmdList.COMMS("q 4"), nil) -- slash returns nothing to the client
    eq(M.sent[2].text, "back", "/comms q 4")
end)

test("quick lines: whisper to target / last whisperer, else SAY; EMOTE and CHANNEL types", function()
    M.sent = {}
    S.units.target = { name = "Bob", realm = "Other Realm" }
    ns.QuickLines.Fire(1, "click")
    eq(M.sent[1].chatType, "WHISPER"); eq(M.sent[1].target, "Bob-Other Realm"); eq(M.sent[1].text, "inv pls")
    S.units.target = nil
    S.lastTell = "Cara"
    ns.QuickLines.Fire(1, "click")
    eq(M.sent[2].target, "Cara", "last whisperer")
    S.lastTell = nil
    ns.QuickLines.Fire(1, "click")
    eq(M.sent[3].chatType, "SAY", "nobody to whisper: SAY")
    ns.QuickLines.Fire(10, "click")
    eq(M.sent[4].chatType, "EMOTE"); eq(M.sent[4].text, "waves.")
    S.channels.LookingForGroup = 6
    local line = ns.QuickLines.Lines()[7]
    line.text = "LFM BFD need %r"
    ns.QuickLines.Fire(7, "click")
    eq(M.sent[5].chatType, "CHANNEL"); eq(M.sent[5].target, 6); eq(M.sent[5].text, "LFM BFD need DPS")
    line.text = "LFG %d as %r"
end)

test("quick lines: tokens %t %f %z %r; %d always prefills so Tim can type the dungeon", function()
    S.units.target = { name = "Bob" }
    S.units.focus = { name = "Cara", realm = "Faraway" }
    ns.db.char.role = "Tank"
    local t = ns.QuickLines.Expand("%t and %f in %z as %r")
    eq(t, "Bob and Cara-Faraway in Stormwind City as Tank")
    local t2, typing = ns.QuickLines.Expand("LFG %d as %r")
    eq(t2, "LFG as Tank"); eq(typing, true)
    M.sent, M.opened = {}, {}
    S.channels.LookingForGroup = 6
    eq(ns.QuickLines.Fire(7, "click"), "prefill")
    eq(#M.sent, 0, "not sent")
    eq(M.opened[1], "/6 LFG as Tank")
    S.units.target, S.units.focus = nil, nil
    ns.db.char.role = "DPS"
end)

test("quick lines: in chat lockdown nothing calls SendChatMessage; OpenChat is prefilled", function()
    S.chatLocked = true
    S.group = "instance"
    ns.Lockdown.Recompute()
    M.sent, M.opened = {}, {}
    for i = 1, 10 do ns.QuickLines.Fire(i, "click") end
    Comms.QuickLine(2)
    SlashCmdList.COMMS("q 9")
    eq(#M.sent, 0, "no SendChatMessage in lockdown")
    truthy(has(M.opened, "/i ty for the group!"), "prefilled with the slash form")
    truthy(has(M.opened, "/i gg"))
    truthy(has(M.opened, "/e waves."))
    -- "show" mode: copy box instead.
    ns.DB.Settings().quick.lockdownAction = "show"
    M.popups = {}
    eq(ns.QuickLines.Fire(2, "click"), "shown")
    eq(M.popups[#M.popups].data, "/i ty for the group!")
    ns.DB.Settings().quick.lockdownAction = "prefill"
    -- Direct send refuses too.
    eq(ns.QuickLines.Send("x", "PARTY"), false)
    eq(#M.sent, 0)
    S.chatLocked = false
    S.group = nil
    ns.Lockdown.Recompute()
end)

test("quick-bar: 10 buttons, click fires its line, labels and key bindings shown", function()
    local bar = CommsQuickBar
    truthy(bar, "bar built")
    eq(#bar.buttons, 10)
    eq(bar.buttons[1].label.__text, "inv")
    S.bindings.COMMS_QUICKLINE_2 = "CTRL-2"
    M.Fire("UPDATE_BINDINGS")
    truthy(bar.buttons[2].tip:find("CTRL-2", 1, true), "binding in tooltip")
    M.sent = {}
    bar.buttons[3].__scripts.OnClick(bar.buttons[3], "LeftButton")
    eq(M.sent[1].text, "brb")
    ns.DB.Settings().quick.barHideInCombat = true
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    eq(bar.__shown, false, "hidden in combat")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.__shown, true)
    ns.DB.Settings().quick.barHideInCombat = false
end)

----------------------------------------------------------------------------
-- History
----------------------------------------------------------------------------
test("history: stores unlocked lines per window, never secret ones, capped", function()
    local buf = ns.History.Buffer(1)
    local before = #buf
    chat("CHAT_MSG_GUILD", { msg = "raid at 8 www.example.com", author = "Bob", lineID = 701 })
    eq(#buf, before + 1)
    eq(buf[#buf].m, "raid at 8 www.example.com", "stored as received, without link codes")
    eq(buf[#buf].e, "GUILD")
    chat("CHAT_MSG_GUILD", { msg = M.SECRET, author = M.SECRET, lineID = 702 })
    ns.Filters.Filter(ChatFrame1, "CHAT_MSG_GUILD", M.ChatArgs({ msg = "half secret", author = M.SECRET, lineID = 703 }))
    eq(#buf, before + 1, "secret lines never stored")
    ns.DB.Settings().history.lines = 50
    for i = 1, 80 do chat("CHAT_MSG_SAY", { msg = "spam " .. i, author = "Bob", lineID = 800 + i }) end
    eq(#buf, 50, "ring buffer capped")
    eq(buf[50].m, "spam 80")
    ns.DB.Settings().history.lines = 500
    ns.DB.Settings().history.lines = 99999
    eq(ns.History.Cap(), 2000, "max 2,000")
    ns.DB.Settings().history.lines = 500
end)

test("history: replay on login adds dimmed lines to the right window; off = nothing", function()
    ChatFrame1.__messages = {}
    local n = ns.History.Replay()
    truthy(n >= 50, "replayed " .. n)
    truthy(ChatFrame1.__messages[1]:find("Comms: ", 1, true), "header")
    truthy(ChatFrame1.__messages[#ChatFrame1.__messages - 1]:find("spam 80", 1, true), "newest last")
    truthy(ChatFrame1.__messages[2]:find("^|cff8a8a8a"), "dimmed")
    ns.DB.Settings().history.replay = false
    eq(ns.History.Replay(), 0)
    ns.DB.Settings().history.replay = true
end)

test("search: /comms search over history, session and whispers", function()
    M.printed = {}
    local n = SlashCmdList.COMMS("search raid at 8")
    truthy(printed("1 match for \"raid at 8\""), table.concat(M.printed, "|"))
    local r = ns.Search.Run("P60")
    eq(#r, 1); eq(r[1].source, "whisper")
    eq(#ns.Search.Run("bob") > 0, true, "by name")
    M.texts = {}
    ns.UI.Open("search")
    truthy(textHas("match"), "search page")
end)

test("history clear wipes every character's store", function()
    SlashCmdList.COMMS("history clear")
    eq(ns.History.Count(), 0)
    truthy(printed("Chat history cleared"))
end)

----------------------------------------------------------------------------
-- Copy
----------------------------------------------------------------------------
test("copy: chat window lines into the copy box, secret lines skipped", function()
    ChatFrame1.__messages = { "|cffffffffhello|r", M.SECRET, "|Hplayer:Bob|h[Bob]|h: hi" }
    local lines, skipped = ns.Copy.Lines(ChatFrame1)
    eq(#lines, 2); eq(skipped, 1)
    eq(lines[1], "hello"); eq(lines[2], "[Bob]: hi")
    ns.Copy.Open(ChatFrame1)
    eq(CommsCopyFrame.edit.__text, "hello\n[Bob]: hi")
    truthy(CommsCopyFrame.title.__text:find("1 locked line", 1, true))
    truthy(ns.Copy[1], "copy button on chat window 1")
end)

----------------------------------------------------------------------------
-- Sticky
----------------------------------------------------------------------------
test("sticky: writes only what Tim changes, never in lockdown; turning off restores Blizzard's", function()
    ns.Sticky.Set("YELL", true)
    eq(ChatTypeInfo.YELL.sticky, 1)
    eq(ns.DB.Settings().sticky.overrides.YELL, 1)
    ns.Sticky.Set("YELL", false)
    eq(ChatTypeInfo.YELL.sticky, 0, "restored")
    eq(ns.DB.Settings().sticky.overrides.YELL, nil)
    S.chatLocked = true
    ns.Lockdown.Recompute()
    ns.Sticky.Set("EMOTE", true)
    eq(ChatTypeInfo.EMOTE.sticky, 0, "not in lockdown")
    S.chatLocked = false
    M.Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    eq(ChatTypeInfo.EMOTE.sticky, 1, "applied after")
    ns.Sticky.Set("EMOTE", false)
end)

----------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------
local function renderAll(label)
    for _, key in ipairs(ns.PanelOrder) do
        M.texts = {}
        ns.UI.Open(key)
        truthy(not textHas("This panel hit an error"), label .. "/" .. key .. ": " .. table.concat(M.texts, " | "))
    end
    for _, sub in ipairs(ns.UI.SETTINGS_TABS) do
        M.texts = {}
        ns.UI.Open("settings", sub)
        truthy(not textHas("This panel hit an error"), label .. "/settings/" .. sub .. ": " .. table.concat(M.texts, " | "))
    end
end

test("every page and settings tab renders without errors (unlocked, locked, in combat)", function()
    renderAll("unlocked")
    S.chatLocked = true
    ns.Lockdown.Recompute()
    renderAll("locked")
    M.texts = {}
    ns.UI.Open("settings", "About")
    truthy(textHas("Chat locked: yes"), "About shows live lockdown status")
    S.chatLocked = false
    ns.Lockdown.Recompute()
    S.combat = true
    renderAll("combat")
    S.combat = false
    M.texts = {}
    ns.UI.Open("settings", "About")
    truthy(textHas("not related to Forever Comms Voice / Guild Comms / Group Comms or Quick Comms"), "disclaimer")
    truthy(textHas("Chat locked: no"))
end)

test("/comms subcommands and help", function()
    SlashCmdList.COMMS("")
    SlashCmdList.COMMS("settings")
    eq(ns.UI.Current(), "settings")
    SlashCmdList.COMMS("quick")
    eq(ns.UI.Current(), "quick")
    SlashCmdList.COMMS("whispers")
    truthy(ns.UI.Messenger.IsShown())
    SlashCmdList.COMMS("channels")
    eq(ns.UI.Current(), "settings")
    M.printed = {}
    SlashCmdList.COMMS("help")
    truthy(printed("/comms q <n>"))
    truthy(printed("/tt [message]"))
    M.printed = {}
    S.channels.Services = 4
    SlashCmdList.COMMS("leave")
    truthy(printed("Left Services."))
end)

test("naming (runtime): every global Comms creates is Comms-named or a slash/binding label", function()
    for k in pairs(M.newGlobals or {}) do
        local ok = k == "Comms" or k == "CommsDB" or k == "CommsCharDB" or k:match("^Comms%u")
            or k:match("^SLASH_COMMS") or k:match("^BINDING_HEADER_COMMS$") or k:match("^BINDING_NAME_COMMS_")
            or k == "WOW_PROJECT_ID" -- set by the test itself
        truthy(ok, "unexpected global: " .. tostring(k))
    end
    truthy(M.newGlobals.CommsDB and M.newGlobals.SLASH_COMMS1, "saw the expected ones")
end)

test("SavedVariables stay small: caps on every list", function()
    eq(ns.DB.CAPS.typed, 100); eq(ns.DB.CAPS.whisperLines, 200); eq(ns.DB.CAPS.whisperContacts, 50)
    eq(ns.DB.CAPS.historyMax, 2000); eq(ns.DB.CAPS.seenNames, 2000)
    for i = 1, 2300 do ns.Format.NoteSeen("Name" .. i, nil) end
    local n = 0
    for _ in pairs(ns.db.global.seenNames) do n = n + 1 end
    truthy(n <= 2000 + 100, "seen names pruned: " .. n)
    ns.Format.PruneSeen()
    n = 0
    for _ in pairs(ns.db.global.seenNames) do n = n + 1 end
    truthy(n <= 2000, "seen names capped")
end)

io.write(("%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
