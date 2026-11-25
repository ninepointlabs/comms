-- First-run setup (3 steps): channels to leave, timestamps, whisper window.
-- Shown once per account (not per character), and from Settings › About.
local _, ns = ...
local UI = ns.UI

local step = 1
UI.SetupStep = function() return step end

local function dim(text) return UI.Hex(UI.C.dim) .. text .. "|r" end

local function finish()
    ns.db.global.firstRunDone = true
    step = 1
    ns.Channels.Run()
    ns.Format.ApplyTimestamp()
    ns.Print("Setup done. /comms opens the window any time.")
    UI.Open("whispers")
end
UI.FinishSetup = finish

local function nav(L, last)
    local items = {}
    if step > 1 then table.insert(items, { label = "Back", onClick = function() step = step - 1 UI.Refresh() end }) end
    if last then
        table.insert(items, { label = "Done", active = true, onClick = finish })
    else
        table.insert(items, { label = "Next", active = true, onClick = function() step = step + 1 UI.Refresh() end })
    end
    table.insert(items, { label = "Skip setup", onClick = function()
        ns.db.global.firstRunDone = true
        step = 1
        UI.Open("whispers")
    end })
    L:Space(6)
    L:Buttons(items)
end

UI.RegisterPanel({
    key = "setup", label = "Setup",
    render = function(L)
        L:Title("Welcome to Comms", ("Step %d of 3 · these settings apply to all your characters."):format(step))
        if step == 1 then
            L:Label("Which channels should Comms leave for you?")
            local list = ns.DB.Settings().channels.list
            for _, ch in ipairs(ns.DB.CHANNELS) do
                L:Check(ns.Channels.NameFor(ch.id) or ch.label, list[ch.key], function(v) list[ch.key] = v end)
            end
            L:Text(dim("Comms leaves them when you log in or change zone, never inside a dungeon or battleground. Settings › Channels can hide them instead, or rejoin them."), { size = 12 })
            nav(L)
        elseif step == 2 then
            local f = ns.DB.Settings().format
            L:Label("Timestamps on chat lines?")
            local items = {}
            for _, c in ipairs(ns.Format.TIMESTAMP_FORMATS) do
                table.insert(items, { label = c.label, active = f.timestamps == c.value, onClick = function()
                    f.timestamps = c.value
                    UI.Refresh()
                end })
            end
            table.insert(items, { label = "Leave as is", active = f.timestamps == nil, onClick = function() f.timestamps = nil UI.Refresh() end })
            L:Buttons(items)
            L:Text(dim("Uses Blizzard's own timestamp option, so it works on every line, locked ones too."), { size = 12 })
            nav(L)
        else
            local w = ns.DB.Settings().whispers
            L:Label("Whisper window?")
            L:Check("Use the whisper window (a tab per person, history kept)", w.enabled, function(v) w.enabled = v UI.Refresh() end)
            if w.enabled then
                L:Check("Also show whispers in main chat", w.showInMain, function(v) w.showInMain = v end)
            end
            L:Text(dim("In dungeons and battlegrounds whispers always show in main chat; the game hides them from addons there."), { size = 12 })
            nav(L, true)
        end
    end,
})
