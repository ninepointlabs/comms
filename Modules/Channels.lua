-- Channels: auto-leave (or hide) General, Trade, Trade (City), LocalDefense,
-- LookingForGroup and Services, account-wide, with an optional per-character
-- override.
--
-- Leave: LeaveChannelByName(localised name from
-- C_ChatInfo.GetChannelShortcutForChannelID), on PLAYER_ENTERING_WORLD and
-- CHANNEL_UI_UPDATE. Skipped in chat lockdown or inside an instance, and
-- retried when that ends. One chat line per channel left.
-- Hide: the channel stays joined; its lines are dropped by our message filter
-- (no Blizzard chat-window tables are touched).
-- Rejoin: Blizzard's own /join, prefilled in the chat box (Tim presses
-- Enter), because joining from addon code would have to write Blizzard's
-- chat-frame channel list, which taints every channel line in lockdown.
local _, ns = ...

local Channels = {}
ns.Channels = Channels

Channels.pending = false

local function S() return ns.DB.Settings().channels end

-- The active leave list: per-character override, else account.
function Channels.List()
    local o = ns.db.char.channelsOverride
    if type(o) == "table" then return o, true end
    return S().list, false
end

function Channels.SetOverride(on)
    if on then
        local copy = {}
        for k, v in pairs(S().list) do copy[k] = v end
        ns.db.char.channelsOverride = copy
    else
        ns.db.char.channelsOverride = nil
    end
end

function Channels.NameFor(id)
    local ci = C_ChatInfo
    local name = ci and ci.GetChannelShortcutForChannelID and ns.Try(ci.GetChannelShortcutForChannelID, id)
    if not ns.Secret(name) and type(name) == "string" and name ~= "" then return name end
    for _, c in ipairs(ns.DB.CHANNELS) do
        if c.id == id then return c.label end
    end
    return nil
end

function Channels.Selected()
    local list = Channels.List()
    local out = {}
    for _, c in ipairs(ns.DB.CHANNELS) do
        if list[c.key] then table.insert(out, c) end
    end
    return out
end

local function joined(name)
    if not GetChannelName then return false end
    local id = ns.Try(GetChannelName, name)
    if ns.Secret(id) then return false end
    return type(id) == "number" and id > 0
end

function Channels.CanRunNow()
    if ns.Lockdown.ChatLocked() then return false, "chat locked" end
    if ns.Lockdown.InInstance() then return false, "in an instance" end
    return true
end

-- Leave every selected channel we're in. Returns the names left.
function Channels.Run(force)
    local left = {}
    if not ns.db or (S().mode ~= "leave" and not force) then return left end
    local ok = Channels.CanRunNow()
    if not ok then
        Channels.pending = true
        return left
    end
    Channels.pending = false
    if not LeaveChannelByName then return left end
    for _, c in ipairs(Channels.Selected()) do
        local name = Channels.NameFor(c.id)
        if name and joined(name) then
            ns.Try(LeaveChannelByName, name)
            table.insert(left, name)
            if S().announce then ns.Print(("Left %s. (/comms rejoin to get it back)"):format(name)) end
        end
    end
    return left
end

-- Debounced runner for CHANNEL_UI_UPDATE bursts.
local scheduled = false
function Channels.Schedule(delay)
    if scheduled then return end
    scheduled = true
    C_Timer.After(delay or 2, function()
        scheduled = false
        Channels.Run()
    end)
end

function Channels.OnLockdownChanged(locked)
    if not locked and Channels.pending then Channels.Schedule(1) end
end

-- Hide mode: drop lines from selected channels (filter stage).
function Channels.Stage(ctx)
    if ctx.type ~= "CHANNEL" or S().mode ~= "hide" then return end
    local id, base = ctx.args[7], ctx.args[9]
    for _, c in ipairs(Channels.Selected()) do
        if id == c.id then return true end
        local name = Channels.NameFor(c.id)
        if name and type(base) == "string" and base:lower() == name:lower() then return true end
    end
end

-- Rejoin: prefill Blizzard's /join (one channel per press of Enter).
function Channels.Rejoin(id)
    local name = Channels.NameFor(id)
    if not name then return false end
    if joined(name) then
        ns.Print(name .. " is already joined.")
        return false
    end
    return ns.QuickLines.Prefill("/join " .. name)
end

-- Channels selected for leaving that we're not in (rejoin candidates).
function Channels.Rejoinable()
    local out = {}
    for _, c in ipairs(Channels.Selected()) do
        local name = Channels.NameFor(c.id)
        if name and not joined(name) then table.insert(out, { id = c.id, name = name }) end
    end
    return out
end

function Channels.RejoinAll()
    local list = Channels.Rejoinable()
    if #list == 0 then
        ns.Print("Nothing to rejoin: you're in every channel on the list.")
        return false
    end
    ns.Print(("Press Enter to rejoin %s.%s"):format(list[1].name,
        #list > 1 and (" Then /comms rejoin again for the next (" .. (#list - 1) .. " more).") or ""))
    return Channels.Rejoin(list[1].id)
end
