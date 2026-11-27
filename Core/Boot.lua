-- Events, slash commands, startup. Loaded last.
local ADDON, ns = ...

-- Key binding labels (Esc › Options › Keybindings › AddOns › Comms).
BINDING_HEADER_COMMS = "Comms"
-- Quick line n fires slot n of the active situational set (World / Party /
-- Raid); the binding names are v0.1's, so keys bound then still work.
for i = 1, 10 do _G["BINDING_NAME_COMMS_QUICKLINE_" .. i] = "Quick line " .. i .. " (active set)" end
for i = 1, 5 do _G["BINDING_NAME_COMMS_COMBATLINE_" .. i] = "Combat line " .. i end
BINDING_NAME_COMMS_OPEN_WHISPERS = "Open whisper window"
BINDING_NAME_COMMS_REPLY_LAST = "Reply to last whisper"

local f = CreateFrame("Frame")
ns.EventFrame = f

local refreshPending
local function SoftRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = false
        ns.UI.Refresh()
    end)
end
ns.SoftRefresh = SoftRefresh

-- Things deferred while chat was locked or in combat.
local function RunDeferred()
    if ns.Lockdown.Busy() then return end
    if ns.Input.pending then ns.Input.Apply() end
    if ns.Recall.pending then ns.Recall.Apply() end
    if ns.Recall.pendingRefill then ns.Recall.Refill() end
    if ns.Sticky.pending then ns.Sticky.Apply() end
    if ns.Format.pendingTimestamp then ns.Format.ApplyTimestamp() end
end
ns.RunDeferred = RunDeferred

local function AddStages()
    local add = ns.Filters.Add
    add("channels", ns.Channels.Stage)   -- hide mode: drop the line
    add("whispers", ns.Whispers.Stage)   -- whisper window owns whispers: drop from main
    add("alerts", ns.Alerts.Stage)
    add("history", ns.History.Stage)     -- store as received
    add("format", ns.Format.Stage)       -- short channel names, seen names
    add("links", ns.Links.Stage)         -- URLs and [invite]
end

ns.Events = {}

local function OnLogin()
    if ns.disabled then
        ns.Print(("Comms is for WoW Forever only (needs WOW_PROJECT_ID %d, this client reports %s). It will stay off."):format(
            ns.FOREVER_PROJECT_ID, tostring(WOW_PROJECT_ID)))
        return
    end
    CommsDB, CommsCharDB = ns.DB.Init(CommsDB, CommsCharDB)
    ns.Lockdown.Init()
    ns.Sticky.Capture()
    AddStages()
    ns.Filters.Install()
    ns.Links.Install()
    ns.AltInvite.Install()
    ns.Autocomplete.Install()
    ns.Copy.InstallButtons()
    ns.Input.Apply()
    ns.Recall.Apply()
    ns.Recall.Refill()
    ns.Sticky.Apply()
    ns.Format.ApplyTimestamp()
    ns.History.Replay()
    ns.UI.MinimapButton()
    ns.UI.RegisterCompartment()
    ns.UI.RegisterSettings()
    ns.QuickSets.Init()
    ns.UI.QuickBar.Refresh()

    for _, ev in ipairs(ns.Lockdown.EVENTS) do pcall(f.RegisterEvent, f, ev) end
    for _, ev in ipairs(ns.Whispers.EVENTS) do pcall(f.RegisterEvent, f, ev) end
    for _, ev in ipairs({ "CHANNEL_UI_UPDATE", "UPDATE_BINDINGS", "GROUP_ROSTER_UPDATE" }) do pcall(f.RegisterEvent, f, ev) end

    if not ns.db.global.firstRunDone and not ns.Lockdown.Busy() then
        C_Timer.After(3, function()
            if not ns.db.global.firstRunDone and not ns.Lockdown.Busy() then ns.UI.Open("setup") end
        end)
    end
end

function ns.Events.Dispatch(event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON then f:UnregisterEvent("ADDON_LOADED") end
        return
    end
    if event == "PLAYER_LOGIN" then
        OnLogin()
        return
    end
    if ns.disabled or not ns.db then return end
    if event:find("^CHAT_MSG_") then
        ns.Whispers.OnEvent(event, ...)
        return
    end
    for _, ev in ipairs(ns.Lockdown.EVENTS) do
        if ev == event then ns.Lockdown.OnEvent(event, ...) end
    end
    if event == "PLAYER_ENTERING_WORLD" then
        ns.Channels.Schedule(3)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if ns.Channels.pending then ns.Channels.Schedule(2) end
    elseif event == "CHANNEL_UI_UPDATE" then
        ns.Channels.Schedule(1)
    elseif event == "UPDATE_BINDINGS" then
        ns.UI.QuickBar.Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        RunDeferred()
    end
    -- Situational quick-line sets: re-read the context (deferred in combat,
    -- applied here on PLAYER_REGEN_ENABLED).
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_REGEN_ENABLED" then
        ns.QuickSets.Evaluate()
        if event == "GROUP_ROSTER_UPDATE" then ns.UI.QuickBar.Refresh() end -- Combat row "only in groups"
    end
end

f:SetScript("OnEvent", function(_, event, ...) ns.Events.Dispatch(event, ...) end)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

ns.On("LOCKDOWN_CHANGED", function(locked)
    ns.Channels.OnLockdownChanged(locked)
    if not locked then RunDeferred() end
    SoftRefresh()
end)
ns.On("WHISPERS_CHANGED", SoftRefresh)
ns.On("ALERTS_CHANGED", SoftRefresh)
ns.On("MINIMAP_TOGGLE", function() ns.UI.MinimapButton() end)

----------------------------------------------------------------------------
-- /comms and /tt
----------------------------------------------------------------------------
local Cmd = {}
ns.Commands = Cmd

function Cmd.Help()
    ns.Print("/comms  open or close the window")
    ns.Print("/comms whispers · quick · settings · channels · search <text>")
    ns.Print("/comms q <n>  fire quick line n of the active set (in chat lockdown: press Enter after)")
    ns.Print("/comms set world · party · raid · auto  pick (pin) a quick-line set, or back to automatic")
    ns.Print("/comms leave · /comms rejoin  auto-leave channels now / rejoin them")
    ns.Print("/comms history clear · /comms setup · /comms help")
    ns.Print("/tt [message]  whisper your target")
end

function ns.Slash(msg)
    if ns.disabled then
        ns.Print("Disabled: WoW Forever only.")
        return
    end
    if not ns.db then return end
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        ns.UI.Toggle()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        ns.UI.Open("settings", rest ~= "" and rest or nil)
    elseif cmd == "whispers" or cmd == "w" then
        ns.UI.Messenger.Open(nil, true)
    elseif cmd == "quick" then
        ns.UI.Open("quick")
    elseif cmd == "channels" then
        ns.UI.Open("settings", "Channels")
    elseif cmd == "alerts" then
        ns.UI.Open("alerts")
    elseif cmd == "search" or cmd == "find" then
        ns.UI.SetFilter(rest)
        ns.UI.Open("search")
        local n = #ns.Search.Run(rest)
        if rest ~= "" then ns.Print(("%d match%s for \"%s\"."):format(n, n == 1 and "" or "es", ns.Escape(rest))) end
        return n
    elseif cmd == "q" or cmd == "quickline" then
        return ns.QuickLines.Fire(tonumber(rest), "slash")
    elseif cmd == "set" then
        local key = rest:lower()
        if key == "" then
            ns.Print(ns.QuickSets.Describe())
            return
        end
        local r = ns.QuickSets.Pick(key)
        if not r then
            ns.Print("Usage: /comms set world | party | raid | auto")
            return
        end
        ns.UI.Refresh()
        ns.Print(ns.QuickSets.Describe())
        return r
    elseif cmd == "leave" then
        local ok, why = ns.Channels.CanRunNow()
        if not ok then ns.Print("Not now (" .. why .. "); Comms will leave them afterwards.") end
        local left = ns.Channels.Run(true)
        if ok and #left == 0 then ns.Print("Nothing to leave.") end
        return left
    elseif cmd == "rejoin" then
        return ns.Channels.RejoinAll()
    elseif cmd == "history" then
        if rest:lower() == "clear" then ns.History.Clear() else ns.UI.Open("settings", "History") end
    elseif cmd == "setup" then
        ns.UI.Open("setup")
    elseif cmd == "about" then
        ns.UI.Open("settings", "About")
    else
        Cmd.Help()
    end
end

SLASH_COMMS1 = "/comms"
SlashCmdList.COMMS = function(msg) ns.Slash(msg) end

SLASH_COMMSTELLTARGET1 = "/tt"
SlashCmdList.COMMSTELLTARGET = function(msg)
    if ns.disabled then
        ns.Print("Disabled: WoW Forever only.")
        return
    end
    if not ns.db then return end
    return ns.TellTarget.Run(msg)
end
