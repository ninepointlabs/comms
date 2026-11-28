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
    -- ...and every addon .lua file is in the TOC.
    local listed = {}
    for _, f in ipairs(files) do listed[f] = true end
    local p = io.popen("find Core Modules UI -name '*.lua' | sort")
    local n = 0
    for f in p:lines() do
        n = n + 1
        truthy(listed[f], "not in the TOC: " .. f)
    end
    p:close()
    truthy(n >= 30 and listed["Modules/QuickSets.lua"], "found the addon files")
    truthy(io.open("Bindings.xml"), "Bindings.xml")
    truthy(io.open("LICENSE"), "LICENSE")
end)

test("Bindings.xml: Comms header, 10 quick lines, 5 combat lines, whisper window, reply; labels defined", function()
    local x = readFile("Bindings.xml")
    truthy(x:find('header="COMMS"', 1, true), "header")
    for i = 1, 10 do
        -- v0.1's binding names unchanged, so keys bound then still work.
        truthy(x:find('<Binding name="COMMS_QUICKLINE_' .. i .. '"[^>]*>Comms%.QuickLine%(' .. i .. '%)</Binding>'), "binding " .. i)
        eq(rawget(_G, "BINDING_NAME_COMMS_QUICKLINE_" .. i), "Quick line " .. i .. " (active set)")
    end
    for i = 1, 5 do
        truthy(x:find('<Binding name="COMMS_COMBATLINE_' .. i .. '">Comms.CombatLine(' .. i .. ')</Binding>', 1, true), "combat binding " .. i)
        eq(rawget(_G, "BINDING_NAME_COMMS_COMBATLINE_" .. i), "Combat line " .. i)
    end
    truthy(not x:find("COMMS_COMBATLINE_6", 1, true), "five combat bindings")
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
    eq(s.quick.lines, nil, "no v0.1 list on a new install")
    eq(#s.quick.sets.world.lines, 8); eq(#s.quick.sets.party.lines, 8)
    eq(#s.quick.sets.raid.lines, 6); eq(#s.quick.sets.combat.lines, 5)
    eq(s.quick.sets.world.lines[1].text, "hi!"); eq(s.quick.sets.world.lines[1].channel, "SAY")
    eq(s.quick.sets.party.lines[3].text, "ty for the group!")
    eq(s.quick.sets.combat.lines[3].text, "peel me")
    eq(s.quick.auto, true); eq(s.quick.combatRow, "always")
    eq(ns.db.global.schema, 2)
    truthy(s.quick.sets.world.lines ~= ns.DB.QUICK_SETS.world, "defaults copied, not shared")
    eq(ns.QuickSets.Active(), "world", "solo in Stormwind: Open World")
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
local function Q() return ns.DB.Settings().quick end
local Bar = ns.UI.QuickBar
-- Put the world back to solo / out of combat / automatic between tests.
local function settle()
    S.group, S.instanceType, S.combat, S.chatLocked = nil, nil, false, false
    rawset(_G, "C_PvP", nil)
    ns.Lockdown.Recompute()
    ns.QuickSets.Pick("auto")
    M.Fire("PLAYER_REGEN_ENABLED")
end
local function labels(row)
    local out = {}
    for i, b in ipairs(row.buttons) do out[i] = (b.__shown and b.label.__text or "-") end
    return table.concat(out, ",")
end
local function deepEq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- Run DB.Init on a scratch table without losing the live DB.
local function initScratch(account)
    local g, c = ns.db.global, ns.db.char
    local a = ns.DB.Init(account, {})
    ns.db = { global = g, char = c }
    ns.DB.global, ns.DB.char = g, c
    return a
end

test("quick lines: auto channel picks INSTANCE > RAID > PARTY > SAY; click sends", function()
    settle()
    M.sent = {}
    eq(ns.QuickLines.Fire(3, "click"), "sent")
    eq(M.sent[1].chatType, "SAY"); eq(M.sent[1].text, "ty!")
    S.group = "party"
    ns.QuickLines.Fire(3, "click")
    eq(M.sent[2].chatType, "PARTY")
    S.group = "raid"
    ns.QuickLines.Fire(3, "click")
    eq(M.sent[3].chatType, "RAID")
    S.group = "instance"
    ns.QuickLines.Fire(3, "key")
    eq(M.sent[4].chatType, "INSTANCE_CHAT")
    S.group = nil
end)

test("quick lines: only click/key/slash can fire; never automatic", function()
    settle()
    M.sent = {}
    eq(ns.QuickLines.Fire(7, nil), nil)
    eq(ns.QuickLines.Fire(7, "timer"), nil)
    eq(ns.QuickLines.Fire(7, "event"), nil)
    eq(ns.QuickLines.Fire(1, "event", "combat"), nil)
    eq(#M.sent, 0)
    eq(Comms.QuickLine(7), "sent", "key binding path")
    eq(M.sent[1].text, "brb")
    eq(SlashCmdList.COMMS("q 4"), nil) -- slash returns nothing to the client
    eq(M.sent[2].text, "thanks for the help!", "/comms q 4 fires slot 4 of the active set")
    M.printed = {}
    eq(Comms.QuickLine(9), nil, "empty slot")
    truthy(printed("Quick line 9 of Open World is empty"))
end)

test("quick lines: whisper to target / last whisperer, else SAY; EMOTE and CHANNEL types", function()
    settle()
    M.sent = {}
    S.units.target = { name = "Bob", realm = "Other Realm" }
    ns.QuickLines.Fire(6, "click")
    eq(M.sent[1].chatType, "WHISPER"); eq(M.sent[1].target, "Bob-Other Realm"); eq(M.sent[1].text, "inv pls")
    S.units.target = nil
    S.lastTell = "Cara"
    ns.QuickLines.Fire(6, "click")
    eq(M.sent[2].target, "Cara", "last whisperer")
    S.lastTell = nil
    ns.QuickLines.Fire(6, "click")
    eq(M.sent[3].chatType, "SAY", "nobody to whisper: SAY")
    ns.QuickLines.Fire(2, "click")
    eq(M.sent[4].chatType, "EMOTE"); eq(M.sent[4].text, "waves.")
    ns.QuickLines.Fire(1, "click")
    eq(M.sent[5].chatType, "SAY"); eq(M.sent[5].text, "hi!")
    S.channels.LookingForGroup = 6
    local line = ns.QuickLines.Lines("world")[8]
    line.text = "LFM BFD need %r"
    ns.QuickLines.Fire(8, "click")
    eq(M.sent[6].chatType, "CHANNEL"); eq(M.sent[6].target, 6); eq(M.sent[6].text, "LFM BFD need DPS")
    line.text = "LFG %d as %r"
end)

test("quick lines: tokens %t %f %z %r; %d always prefills so Tim can type the dungeon", function()
    settle()
    S.units.target = { name = "Bob" }
    S.units.focus = { name = "Cara", realm = "Faraway" }
    ns.db.char.role = "Tank"
    local t = ns.QuickLines.Expand("%t and %f in %z as %r")
    eq(t, "Bob and Cara-Faraway in Stormwind City as Tank")
    local t2, typing, dPos = ns.QuickLines.Expand("LFG %d as %r")
    eq(t2, "LFG  as Tank"); eq(typing, true); eq(dPos, 4)
    eq((ns.QuickLines.Expand("100%% sure %x")), "100%% sure %x", "unknown tokens kept")
    M.sent, M.opened = {}, {}
    S.channels.LookingForGroup = 6
    eq(ns.QuickLines.Fire(8, "click"), "prefill")
    eq(#M.sent, 0, "not sent")
    eq(M.opened[1], "/6 LFG  as Tank")
    eq(M.openedCursor, #"/6 LFG ", "cursor where %d was")
    S.units.target, S.units.focus = nil, nil
    ns.db.char.role = "DPS"
end)

test("quick lines: in chat lockdown no set or Combat line calls SendChatMessage; OpenChat is prefilled", function()
    settle()
    S.chatLocked = true
    S.group, S.instanceType = "instance", "party"
    ns.Lockdown.Recompute()
    M.Fire("ZONE_CHANGED_NEW_AREA")
    eq(ns.QuickSets.Active(), "party")
    M.sent, M.opened = {}, {}
    for _, key in ipairs({ "world", "party", "raid", "combat" }) do
        for i = 1, 10 do ns.QuickLines.Fire(i, "click", key) end
    end
    for i = 1, 10 do Comms.QuickLine(i) end
    for i = 1, 5 do Comms.CombatLine(i) end
    SlashCmdList.COMMS("q 8")
    eq(#M.sent, 0, "no SendChatMessage in lockdown")
    truthy(has(M.opened, "/i ty for the group!"), "prefilled with the slash form")
    truthy(has(M.opened, "/i gg"))
    truthy(has(M.opened, "/e waves."))
    truthy(has(M.opened, "/i oom") and has(M.opened, "/i peel me"), "combat lines prefill")
    truthy(has(M.opened, "/i ready"), "binding fired the active (party) set")
    -- "show" mode: copy box instead.
    Q().lockdownAction = "show"
    M.popups = {}
    eq(ns.QuickLines.Fire(3, "click"), "shown")
    eq(M.popups[#M.popups].data, "/i ty for the group!")
    Q().lockdownAction = "prefill"
    -- Bar clicks in lockdown prefill too.
    M.opened = {}
    local cb = CommsQuickBar.combat.buttons[1]
    cb.__scripts.OnClick(cb, "LeftButton")
    eq(M.opened[1], "/i oom")
    -- Direct send refuses too.
    eq(ns.QuickLines.Send("x", "PARTY"), false)
    eq(#M.sent, 0)
    settle()
end)

test("quick sets: context detection (solo, party, party instance, raid, BG, arena, C_PvP, secret, missing)", function()
    settle()
    local D = ns.QuickSets.Detect
    local cases = {
        { nil, nil, "world", "solo" },
        { "party", nil, "party", "party in the open world" },
        { "instance", "party", "party", "LFG dungeon" },
        { "party", "party", "party", "premade dungeon" },
        { nil, "party", "party", "solo in a dungeon" },
        { "raid", nil, "raid", "raid group" },
        { "raid", "raid", "raid", "raid instance" },
        { nil, "raid", "world", "solo in an old raid: not a group" },
        { "instance", "pvp", "raid", "battleground" },
        { "instance", "arena", "raid", "arena" },
        { nil, "scenario", "world", "solo scenario" },
    }
    for _, c in ipairs(cases) do
        S.group, S.instanceType = c[1], c[2]
        eq(D(), c[3], c[4])
    end
    S.group, S.instanceType = nil, nil
    rawset(_G, "C_PvP", { IsBattleground = function() return true end })
    eq(D(), "raid", "C_PvP.IsBattleground")
    rawset(_G, "C_PvP", { IsBattleground = function() return M.SECRET end })
    eq(D(), "world", "secret C_PvP answer ignored")
    rawset(_G, "C_PvP", nil)
    local realInInstance, realInRaid, realInGroup = IsInInstance, IsInRaid, IsInGroup
    rawset(_G, "IsInInstance", function() return M.SECRET, M.SECRET end)
    eq(D(), nil, "secret instance: unknown")
    S.group = "raid"
    eq(D(), "raid", "raid group still known")
    S.group = nil
    rawset(_G, "IsInInstance", realInInstance)
    rawset(_G, "IsInRaid", function() return M.SECRET end)
    eq(D(), nil, "secret raid: unknown")
    rawset(_G, "IsInRaid", function() error("boom") end)
    eq(D(), nil, "erroring API: unknown")
    rawset(_G, "IsInRaid", realInRaid)
    rawset(_G, "IsInGroup", function() return M.SECRET end)
    eq(D(), nil, "secret group: unknown")
    rawset(_G, "IsInGroup", realInGroup)
    eq(D(), "world")

    -- Events switch the set; unknown keeps the current one.
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.QuickSets.Active(), "party")
    eq(CommsQuickBar.tab.label.__text, "Party")
    eq(CommsQuickBar.main.buttons[1].label.__text, "ready")
    rawset(_G, "IsInInstance", function() return M.SECRET, M.SECRET end)
    S.group = nil
    M.Fire("ZONE_CHANGED_NEW_AREA")
    eq(ns.QuickSets.Active(), "party", "secret context: kept the current set")
    rawset(_G, "IsInInstance", realInInstance)
    S.group, S.instanceType = "instance", "pvp"
    M.Fire("PLAYER_ENTERING_WORLD")
    eq(ns.QuickSets.Active(), "raid")
    eq(CommsQuickBar.main.buttons[1].label.__text, "inc")
    eq(CommsQuickBar.main.buttons[7].__shown, false, "raid set has 6 lines: slot 7 hidden")
    settle()
    eq(ns.QuickSets.Active(), "world")
    eq(labels(CommsQuickBar.main), "hi,wave,ty,thx,group?,inv,brb,LFG,-,-")
end)

test("quick sets: a context change in combat waits for PLAYER_REGEN_ENABLED; no re-layout in combat", function()
    settle()
    local bar = CommsQuickBar
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    local n0, before, beforeC = Bar.layouts, labels(bar.main), labels(bar.combat)
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    S.group, S.instanceType = "instance", "party"
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.Fire("PLAYER_ENTERING_WORLD")
    M.Fire("UPDATE_BINDINGS")
    Bar.Refresh()
    ns.QuickLines.Lines("world")[1].label = "HELLO"   -- an edit in combat
    Bar.Refresh()
    eq(ns.QuickSets.Active(), "world", "still the old set")
    eq(ns.QuickSets.Pending(), "party", "recorded")
    eq(Bar.layouts, n0, "no layout in combat")
    eq(labels(bar.main), before, "buttons untouched")
    eq(labels(bar.combat), beforeC)
    truthy(Bar.dirty, "re-layout owed")
    M.sent = {}
    Comms.QuickLine(1) -- keys fire what the bar shows
    eq(M.sent[1].text, "hi!")
    M.printed = {}
    bar.tab.__scripts.OnClick(bar.tab, "LeftButton")
    truthy(printed("out of combat only"), "tab refuses in combat")
    eq(ns.QuickSets.Pinned(), nil)
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(ns.QuickSets.Active(), "party", "applied after combat")
    eq(ns.QuickSets.Pending(), nil)
    truthy(Bar.layouts > n0, "laid out after combat")
    eq(bar.main.buttons[1].label.__text, "ready")
    ns.QuickLines.Lines("world")[1].label = "hi"
    -- /reload in the middle of a fight: a set and a laid-out bar at once.
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    S.group, S.instanceType = "raid", nil
    ns.QuickSets._Reset()
    ns.QuickSets.Init()
    eq(ns.QuickSets.Active(), "raid", "first pick applies in combat")
    bar.laidOut = false
    local n1 = Bar.layouts
    Bar.Refresh()
    eq(Bar.layouts, n1 + 1, "first layout runs in combat")
    eq(bar.main.buttons[1].label.__text, "inc")
    Bar.Refresh()
    eq(Bar.layouts, n1 + 1, "but only the first")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    S.group = "instance"
    S.instanceType = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.QuickSets.Active(), "party")
    -- Back and forth in combat: nothing pending when it ends where it began.
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    S.group, S.instanceType = nil, nil
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.QuickSets.Pending(), "world")
    S.group, S.instanceType = "instance", "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.QuickSets.Pending(), nil, "back to the active set")
    settle()
end)

test("quick-bar: Combat row always visible in combat (also with hide in combat); row modes apply out of combat", function()
    settle()
    local bar = CommsQuickBar
    truthy(bar, "bar built")
    eq(#bar.main.buttons, 10); eq(#bar.combat.buttons, 10)
    eq(labels(bar.combat), "oom,inc,peel,pull,heal,-,-,-,-,-")
    eq(bar.combat.__shown, true)
    S.bindings.COMMS_QUICKLINE_2 = "CTRL-2"
    S.bindings.COMMS_COMBATLINE_1 = "SHIFT-1"
    M.Fire("UPDATE_BINDINGS")
    truthy(bar.main.buttons[2].tip:find("CTRL-2", 1, true), "binding in tooltip")
    truthy(bar.combat.buttons[1].tip:find("SHIFT-1", 1, true), "combat binding in tooltip")
    truthy(bar.combat.buttons[1].tip:find("In dungeons/raids/BGs this fills the chat box; press Enter.", 1, true), "combat tip")
    truthy(not bar.main.buttons[2].tip:find("fills the chat box", 1, true), "Open World tip has no lockdown note")
    truthy(bar.main.buttons[2].tip:find("active set", 1, true), "binding note")
    M.sent = {}
    bar.main.buttons[7].__scripts.OnClick(bar.main.buttons[7], "LeftButton")
    eq(M.sent[1].text, "brb")
    bar.combat.buttons[3].__scripts.OnClick(bar.combat.buttons[3], "LeftButton")
    eq(M.sent[2].text, "peel me")
    Q().barHideInCombat = true
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    eq(bar.main.__shown, false, "situational row hidden in combat")
    eq(bar.combat.__shown, true, "Combat row stays")
    eq(bar.__shown, true)
    bar.combat.buttons[1].__scripts.OnClick(bar.combat.buttons[1], "LeftButton")
    eq(M.sent[3].text, "oom", "Combat row fires in combat")
    -- As in the client, InCombatLockdown() is still false inside
    -- PLAYER_REGEN_DISABLED: the bar must hide row 1 anyway.
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.main.__shown, true)
    M.Fire("PLAYER_REGEN_DISABLED")
    eq(bar.main.__shown, false, "hidden on PLAYER_REGEN_DISABLED before InCombatLockdown() is true")
    eq(bar.combat.__shown, true)
    S.combat = true
    -- Row mode changed in combat: applied after.
    Q().combatRow = "off"
    Bar.Refresh()
    eq(bar.combat.__shown, true, "not hidden mid-fight")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.main.__shown, true)
    eq(bar.combat.__shown, false, "off after combat")
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    eq(bar.main.__shown, false); eq(bar.combat.__shown, false, "off + hide in combat: nothing")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    Q().barHideInCombat = false
    -- Only in groups.
    Q().combatRow = "groups"
    Bar.Refresh()
    eq(bar.combat.__shown, false, "solo: hidden")
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(bar.combat.__shown, true, "in a group: shown")
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    S.group = nil
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(bar.combat.__shown, true, "left the group mid-fight: stays")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.combat.__shown, false, "hidden after combat")
    Q().combatRow = "always"
    -- Up to 10 Combat lines.
    local cl = Q().sets.combat.lines
    for i = 6, 10 do cl[i] = { label = "c" .. i, text = "c" .. i, channel = "auto" } end
    Bar.Refresh()
    eq(bar.combat.buttons[10].label.__text, "c10")
    for i = 10, 6, -1 do cl[i] = nil end
    Bar.Refresh()
    -- Bar off hides all.
    Q().bar = false
    Bar.Refresh()
    eq(bar.__shown, false)
    Q().bar = true
    Bar.Refresh()
    eq(bar.__shown, true)
    settle()
end)

test("quick sets: bindings fire the active set's slot and Combat slots", function()
    settle()
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    M.sent = {}
    eq(Comms.QuickLine(1), "sent")
    eq(M.sent[1].text, "ready"); eq(M.sent[1].chatType, "PARTY")
    eq(Comms.CombatLine(3), "sent")
    eq(M.sent[2].text, "peel me"); eq(M.sent[2].chatType, "PARTY")
    S.group = "raid"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(Comms.QuickLine(2), "sent")
    eq(M.sent[3].text, "help!"); eq(M.sent[3].chatType, "RAID")
    M.printed = {}
    eq(Comms.CombatLine(6), nil)
    truthy(printed("of Combat is empty"))
    settle()
end)

test("combat row: default and missing/blank/unknown key = on; saved always/groups/off kept", function()
    local a = initScratch(nil)
    eq(a.settings.quick.combatRow, "always", "fresh install")
    a = initScratch({ schema = 2, settings = { quick = { bar = true } } })
    eq(a.settings.quick.combatRow, "always", "missing key")
    for _, bad in ipairs({ "", "bogus", 1, true }) do
        a = initScratch({ schema = 2, settings = { quick = { combatRow = bad } } })
        eq(a.settings.quick.combatRow, "always", "bad value " .. tostring(bad))
    end
    for _, mode in ipairs({ "always", "groups", "off" }) do
        a = initScratch({ schema = 2, settings = { quick = { combatRow = mode } } })
        eq(a.settings.quick.combatRow, mode, "kept " .. mode)
    end
    -- v0.1 table (no combatRow at all) migrates to on.
    a = initScratch({ schema = 1, settings = { quick = { lines = ns.DB.CopyLines(ns.DB.QUICK_DEFAULTS_V1) } } })
    eq(a.settings.quick.combatRow, "always", "v0.1 upgrade")
    eq(a.schema, 2, "no schema bump")
    -- A value broken at runtime reads as on too.
    Q().combatRow = nil
    eq(ns.DB.CombatRow(), "always")
    eq(Q().combatRow, "always")
end)

test("/comms combat on | off | bare (report + toggle) | bad argument", function()
    settle()
    local bar = CommsQuickBar
    Q().combatRow = "always"
    Bar.Refresh()
    eq(bar.combat.__shown, true)
    M.printed = {}
    eq(SlashCmdList.COMMS("combat off"), nil) -- SlashCmdList wrapper drops the return
    eq(Q().combatRow, "off")
    eq(bar.combat.__shown, false, "hidden out of combat")
    truthy(printed("Combat row: off."))
    M.printed = {}
    SlashCmdList.COMMS("combat on")
    eq(Q().combatRow, "always")
    eq(bar.combat.__shown, true)
    truthy(printed("Combat row: on (always)."))
    SlashCmdList.COMMS("COMBAT OFF")
    eq(Q().combatRow, "off", "case-insensitive")
    -- Bare: report + toggle.
    M.printed = {}
    eq(ns.Slash("combat"), "always")
    truthy(printed("Combat row was off; turning it on."))
    truthy(printed("Combat row: on (always)."))
    M.printed = {}
    eq(ns.Slash("combat"), "off")
    truthy(printed("Combat row was on (always); turning it off."))
    Q().combatRow = "groups"
    M.printed = {}
    eq(ns.Slash("combat"), "off", "groups toggles to off")
    truthy(printed("Combat row was on (only in groups); turning it off."))
    -- Bad argument: usage, nothing changes.
    for _, mode in ipairs({ "always", "groups", "off" }) do
        Q().combatRow = mode
        M.printed = {}
        eq(ns.Slash("combat maybe"), nil)
        eq(Q().combatRow, mode, "bad arg leaves " .. mode)
        truthy(printed("Usage: /comms combat on | off"))
    end
    -- In combat: setting recorded, visibility waits for PLAYER_REGEN_ENABLED.
    Q().combatRow = "always"
    Bar.Refresh()
    eq(bar.combat.__shown, true)
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    local before = Bar.layouts
    M.printed = {}
    ns.Slash("combat off")
    eq(Q().combatRow, "off")
    eq(bar.combat.__shown, true, "not hidden mid-fight")
    eq(Bar.layouts, before, "no layout in combat")
    truthy(Bar.dirty, "pending layout")
    truthy(printed("Shows or hides when combat ends."))
    ns.Slash("combat on")
    ns.Slash("combat off")
    eq(bar.combat.__shown, true)
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.combat.__shown, false, "hidden after combat")
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    ns.Slash("combat on")
    eq(bar.combat.__shown, false, "not shown mid-fight")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.combat.__shown, true, "shown after combat")
    -- Other subcommands untouched.
    SlashCmdList.COMMS("set raid")
    eq(ns.QuickSets.Active(), "raid")
    eq(Q().combatRow, "always")
    -- Help and About list it.
    M.printed = {}
    SlashCmdList.COMMS("help")
    truthy(printed("/comms combat on · off"))
    truthy(readFile("UI/Panels/Options.lua"):find("/comms combat on · off", 1, true), "About lists it")
    settle()
end)

test("combat row: Combat line keys are a silent no-op while the row is off or groups+solo", function()
    settle()
    local errs = {}
    local function press(i)
        local ok, r = pcall(Comms.CombatLine, i)
        if not ok then table.insert(errs, r) end
        return r
    end
    for _, case in ipairs({ { mode = "off", group = nil }, { mode = "off", group = "party" }, { mode = "groups", group = nil } }) do
        Q().combatRow = case.mode
        S.group = case.group
        M.Fire("GROUP_ROSTER_UPDATE")
        for _, locked in ipairs({ false, true }) do
            S.chatLocked = locked
            ns.Lockdown.Recompute()
            for _, inCombat in ipairs({ false, true }) do
                S.combat = inCombat
                M.sent, M.opened, M.printed, M.popups = {}, {}, {}, {}
                for i = 1, 6 do eq(press(i), nil, case.mode .. " slot " .. i) end
                eq(#M.sent, 0, "no send"); eq(#M.opened, 0, "no prefill")
                eq(#M.printed, 0, "no print"); eq(#M.popups, 0, "no copy box")
            end
            S.combat = false
        end
        S.chatLocked = false
        ns.Lockdown.Recompute()
    end
    eq(#errs, 0, "no Lua errors: " .. tostring(errs[1]))
    -- Row on: works as in v0.2 (send; lockdown prefill; in combat).
    Q().combatRow = "groups"
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    M.sent = {}
    eq(Comms.CombatLine(1), "sent", "groups + in a group")
    eq(M.sent[1].text, "oom")
    Q().combatRow = "always"
    S.group = nil
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(Comms.CombatLine(2), "sent", "always + solo")
    eq(M.sent[2].text, "inc"); eq(M.sent[2].chatType, "SAY")
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    eq(Comms.CombatLine(3), "sent", "in combat")
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    S.chatLocked = true
    S.group, S.instanceType = "instance", "party"
    ns.Lockdown.Recompute()
    M.sent, M.opened = {}, {}
    eq(Comms.CombatLine(1), "prefill", "lockdown prefill")
    eq(M.opened[1], "/i oom"); eq(#M.sent, 0)
    -- Groups mode with a secret IsInGroup: follows what the bar shows.
    Q().combatRow = "groups"
    local real = IsInGroup
    rawset(_G, "IsInGroup", function() return M.SECRET end)
    local shown = CommsQuickBar.combat.__shown
    M.opened = {}
    local ok, r = pcall(Comms.CombatLine, 1)
    truthy(ok, "no error with a secret IsInGroup")
    eq(r ~= nil, shown and true or false, "follows the bar")
    rawset(_G, "IsInGroup", real)
    -- Situational bindings unaffected by the Combat row.
    S.chatLocked, S.group, S.instanceType = false, nil, nil
    ns.Lockdown.Recompute()
    Q().combatRow = "off"
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.sent = {}
    eq(Comms.QuickLine(1), "sent", "Quick line keys still fire with the Combat row off")
    Q().combatRow = "always"
    settle()
end)

test("combat row: clicks on a still-visible row do nothing once it's off mid-fight or groups+solo", function()
    settle()
    local bar = CommsQuickBar
    local function click(i, mouse)
        local b = bar.combat.buttons[i]
        return pcall(b.__scripts.OnClick, b, mouse or "LeftButton")
    end
    local function quiet(msg)
        eq(#M.sent, 0, msg .. ": no send"); eq(#M.opened, 0, msg .. ": no prefill")
        eq(#M.printed, 0, msg .. ": no print"); eq(#M.popups, 0, msg .. ": no copy box")
    end
    -- Mid-fight off: row stays, clicks ignored, then it hides after combat.
    Q().combatRow = "always"
    Bar.Refresh()
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    M.sent = {}
    truthy(click(1)); eq(M.sent[1].text, "oom", "on: click works in combat")
    ns.Slash("combat off")
    eq(bar.combat.__shown, true, "still visible mid-fight")
    for _, locked in ipairs({ false, true }) do
        S.chatLocked = locked
        ns.Lockdown.Recompute()
        M.sent, M.opened, M.printed, M.popups = {}, {}, {}, {}
        local ui = ns.UI.Current()
        for i = 1, 5 do truthy(click(i), "no error (left)") end
        truthy(click(1, "RightButton"), "no error (right)")
        quiet("off mid-fight, locked=" .. tostring(locked))
        eq(ns.UI.Current(), ui, "right-click doesn't open the editor")
    end
    S.chatLocked = false
    ns.Lockdown.Recompute()
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(bar.combat.__shown, false, "hidden after combat")
    -- Groups, solo, mid-fight (left the group in combat).
    Q().combatRow = "groups"
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(bar.combat.__shown, true)
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    S.group = nil
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(bar.combat.__shown, true, "left the group mid-fight: stays")
    M.sent, M.opened, M.printed, M.popups = {}, {}, {}, {}
    for i = 1, 5 do truthy(click(i)) end
    quiet("groups+solo")
    -- Back in a group: clicks work again.
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    truthy(click(2)); eq(M.sent[1].text, "inc", "groups + in a group: click works")
    -- Secret IsInGroup: follows the bar (shown -> fires).
    local real = IsInGroup
    rawset(_G, "IsInGroup", function() return M.SECRET end)
    M.sent = {}
    truthy(click(1)); eq(M.sent[1] and M.sent[1].text, "oom", "secret: follows the visible bar")
    rawset(_G, "IsInGroup", real)
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    -- Situational row unaffected.
    Q().combatRow = "off"
    Bar.Refresh()
    M.sent = {}
    local b = bar.main.buttons[1]
    b.__scripts.OnClick(b, "LeftButton")
    eq(#M.sent, 1, "row 1 clicks still fire with the Combat row off")
    Q().combatRow = "always"
    settle()
end)

test("quick sets: /comms set pins, auto clears; per-set enable; tab cycles; pin ends at login", function()
    settle()
    M.printed = {}
    SlashCmdList.COMMS("set party")
    eq(ns.QuickSets.Active(), "party"); eq(ns.QuickSets.Pinned(), "party")
    truthy(printed("Party / Dungeon, pinned"))
    eq(CommsQuickBar.tab.label.__text, "Party*")
    S.group = "raid"
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.QuickSets.Active(), "party", "pin holds")
    SlashCmdList.COMMS("set auto")
    eq(ns.QuickSets.Active(), "raid"); eq(ns.QuickSets.Pinned(), nil)
    SlashCmdList.COMMS("set bg")
    eq(ns.QuickSets.Pinned(), "raid", "alias")
    M.printed = {}
    SlashCmdList.COMMS("set nonsense")
    truthy(printed("Usage: /comms set"))
    SlashCmdList.COMMS("set")
    truthy(printed("Quick lines: Raid / BG"))
    -- In combat: recorded, applied after.
    S.combat = true
    M.Fire("PLAYER_REGEN_DISABLED")
    M.printed = {}
    SlashCmdList.COMMS("set world")
    eq(ns.QuickSets.Active(), "raid")
    truthy(printed("switches to Open World when combat ends"))
    S.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    eq(ns.QuickSets.Active(), "world")
    -- A login (or /reload) clears the pin.
    ns.QuickSets.Init()
    eq(ns.QuickSets.Pinned(), nil); eq(ns.QuickSets.Active(), "raid")
    -- Tab: click cycles (pins), right-click back to auto.
    local tab = CommsQuickBar.tab
    tab.__scripts.OnClick(tab, "LeftButton")
    eq(ns.QuickSets.Active(), "world"); eq(ns.QuickSets.Pinned(), "world")
    tab.__scripts.OnClick(tab, "LeftButton")
    eq(ns.QuickSets.Active(), "party")
    tab.__scripts.OnClick(tab, "RightButton")
    eq(ns.QuickSets.Active(), "raid"); eq(ns.QuickSets.Pinned(), nil)
    -- Per-set enable: Raid / BG off falls back to Party / Dungeon.
    Q().sets.raid.enabled = false
    ns.QuickSets.Evaluate()
    eq(ns.QuickSets.Active(), "party")
    tab.__scripts.OnClick(tab, "LeftButton")
    tab.__scripts.OnClick(tab, "LeftButton")
    truthy(ns.QuickSets.Active() ~= "raid", "cycle skips a set that's off")
    Q().sets.raid.enabled = true
    -- Turning auto off keeps what's on the bar.
    SlashCmdList.COMMS("set auto")
    S.group = "party"
    M.Fire("GROUP_ROSTER_UPDATE")
    ns.QuickSets.SetAuto(false)
    eq(ns.QuickSets.Active(), "party"); eq(Q().lastPicked, "party")
    S.group = nil
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.QuickSets.Active(), "party", "manual: no auto switch")
    ns.QuickSets.SetAuto(true)
    eq(ns.QuickSets.Active(), "world")
    -- Auto off: the last pick, kept across logins.
    SlashCmdList.COMMS("set world")
    Q().auto = false
    ns.QuickSets.Init()
    eq(ns.QuickSets.Active(), "world", "manual mode keeps the last pick")
    eq(Q().lastPicked, "world")
    Q().auto = true
    -- Every situational set off: row 1 empty, Combat row still there.
    for _, k in ipairs({ "world", "party", "raid" }) do Q().sets[k].enabled = false end
    ns.QuickSets.Evaluate()
    eq(ns.QuickSets.Active(), nil)
    eq(CommsQuickBar.tab.label.__text, "Off")
    eq(CommsQuickBar.combat.__shown, true)
    M.printed = {}
    eq(Comms.QuickLine(1), nil)
    truthy(printed("of the active set is empty"))
    for _, k in ipairs({ "world", "party", "raid" }) do Q().sets[k].enabled = true end
    settle()
    eq(ns.QuickSets.Active(), "world")
end)

test("quick-lines editor: add, remove, reset a line and a set; edits reach the bar out of combat", function()
    settle()
    local function click(label)
        local pool = CommsMainFrame.views.quick.layout.pools.btn or {}
        for i = #pool, 1, -1 do
            local b = pool[i]
            if b.__shown and b.label.__text == label then b.__scripts.OnClick(b) return true end
        end
        error("no button " .. label)
    end
    ns.UI.Open("quick", "combat")
    local lines = Q().sets.combat.lines
    click("Add a line")
    eq(#lines, 6)
    lines[6].text, lines[6].label = "stun", "stun"
    ns.UI.QuickBar.Refresh()
    eq(CommsQuickBar.combat.buttons[6].label.__text, "stun")
    click("Remove") -- the last line's Remove (pool order = line order)
    eq(#lines, 5)
    lines[1].text = "low mana"
    click("Reset this set")
    eq(#lines, 5); eq(lines[1].text, "oom")
    truthy(lines[1] ~= ns.DB.QUICK_SETS.combat[1], "reset copies the defaults")
    for _ = #lines + 1, 10 do click("Add a line") end
    eq(#lines, 10)
    ns.UI.Refresh()
    local ok = pcall(click, "Add a line")
    eq(ok, false, "no Add past 10 lines")
    click("Reset this set")
    eq(#lines, 5)
    settle()
end)

test("migration v0.1 -> schema 2: untouched defaults, edited lines, idempotent, arrays never merged", function()
    local V1 = ns.DB.QUICK_DEFAULTS_V1
    -- Untouched v0.1 lines (with a stray target on an auto line): new defaults.
    local v1 = ns.DB.CopyLines(V1)
    v1[2].target = "auto"
    local a = initScratch({ schema = 1, settings = { quick = { lines = v1, bar = true, barHideInCombat = true } } })
    eq(a.schema, 2)
    local q = a.settings.quick
    eq(q.migratedV1, "defaults")
    eq(q.sets.world.lines[1].text, "hi!"); eq(q.sets.party.lines[1].text, "ready")
    eq(q.sets.raid.lines[1].text, "inc"); eq(q.sets.combat.lines[1].text, "oom")
    eq(q.lines, v1, "old key kept readable"); eq(#q.lines, 10)
    eq(q.barHideInCombat, true, "other settings kept")
    -- Edited v0.1 lines: copied into Open World and Party / Dungeon.
    local edited = ns.DB.CopyLines(V1)
    edited[2].text = "ty all <3"
    table.remove(edited, 10)
    a = initScratch({ schema = 1, settings = { quick = { lines = edited } } })
    q = a.settings.quick
    eq(q.migratedV1, "edited")
    for _, k in ipairs({ "world", "party" }) do
        eq(#q.sets[k].lines, 9, k .. " has Tim's 9 lines")
        eq(q.sets[k].lines[2].text, "ty all <3", k)
        eq(q.sets[k].lines[1].text, "inv pls", k)
        eq(q.sets[k].enabled, true, k .. " enabled filled in")
    end
    truthy(q.sets.world.lines ~= q.sets.party.lines and q.sets.world.lines ~= q.lines, "separate copies")
    truthy(q.sets.world.lines[1] ~= q.lines[1], "line tables copied")
    eq(q.sets.raid.lines[2].text, "help!", "Raid / BG: new defaults")
    eq(#q.sets.combat.lines, 5, "Combat: new defaults")
    eq(q.lines[2].text, "ty all <3", "old key kept")
    -- Idempotent: running again (next login) changes nothing, even after Tim
    -- edits a set.
    q.sets.world.lines[1].text = "yo"
    local snapshot = ns.DB.CopyLines(q.sets.world.lines)
    local function dump(t)
        local keys = {}
        for k in pairs(t) do table.insert(keys, tostring(k)) end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do
            local v = t[k] == nil and t[tonumber(k)] or t[k]
            table.insert(out, k .. "=" .. (type(v) == "table" and ("{" .. dump(v) .. "}") or tostring(v)))
        end
        return table.concat(out, ",")
    end
    local before = dump(a)
    a = initScratch(a)
    eq(dump(a), before, "second Init changes nothing")
    ns.DB.Migrate(a)
    eq(dump(a), before, "second Migrate changes nothing")
    truthy(deepEq(a.settings.quick.sets.world.lines, snapshot))
    -- No schema but saved settings = v0.1.
    edited = ns.DB.CopyLines(V1)
    edited[1].channel = "SAY"
    a = initScratch({ settings = { quick = { lines = edited } } })
    eq(a.settings.quick.sets.world.lines[1].channel, "SAY")
    eq(a.schema, 2)
    -- Fresh install: nothing to migrate, no v0.1 key.
    a = initScratch({})
    eq(a.settings.quick.lines, nil); eq(a.settings.quick.migratedV1, nil); eq(a.schema, 2)
    -- deepDefaults never merges default lines into an edited (shorter) list.
    a = initScratch({ schema = 2, settings = { quick = { sets = {
        world = { lines = { { label = "x", text = "x", channel = "SAY" } } },
        combat = { lines = {} },
    } } } })
    q = a.settings.quick
    eq(#q.sets.world.lines, 1, "one line stays one line")
    eq(q.sets.world.lines[1].text, "x")
    eq(q.sets.world.lines[2], nil)
    eq(#q.sets.combat.lines, 0, "an emptied list stays empty")
    eq(#q.sets.party.lines, 8, "missing set gets its defaults")
    eq(q.sets.world.enabled, true)
    eq(q.combatRow, "always")
    -- The live DB is unharmed.
    eq(ns.db.global, CommsDB)
    eq(ns.DB.Settings().quick.sets.world.lines[1].text, "hi!")
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
    -- Each quick-line set's editor, in and out of combat.
    for _, inCombat in ipairs({ false, true }) do
        S.combat = inCombat
        for _, k in ipairs(ns.DB.SET_KEYS) do
            M.texts = {}
            ns.UI.Open("quick", k)
            truthy(not textHas("This panel hit an error"), "quick/" .. k .. ": " .. table.concat(M.texts, " | "))
            truthy(textHas(ns.QuickSets.NAMES[k]), "set tab " .. k)
        end
        M.texts = {}
        ns.UI.Open("settings", "Quick lines")
        truthy(not textHas("This panel hit an error"), "settings/Quick lines")
        truthy(textHas("Switch sets automatically") and textHas("the Combat row still shows in combat"), "set options shown")
    end
    S.combat = false
    M.texts = {}
    ns.UI.Open("quick", "combat")
    truthy(textHas("Combat line 1-5"), "combat editor explains its keys")
    truthy(textHas("In dungeons/raids/BGs these fill the chat box; press Enter."), "lockdown note")
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
