-- Situational quick-line sets: Open World, Party / Dungeon, Raid / BG swap
-- with the context; Combat is a separate, always-visible row (QuickBar).
--
-- The context is read on PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA,
-- GROUP_ROSTER_UPDATE and PLAYER_REGEN_ENABLED (Boot wires them). A change
-- while InCombatLockdown() is only recorded (pending) and applied when combat
-- ends: the bar never re-lays out under the mouse mid-fight. Unreadable or
-- secret values keep the current set; Comms never guesses.
--
-- Pin: clicking the bar's set tab or /comms set world|party|raid pins a set
-- until /comms set auto (or the tab's right-click), or the next login or
-- /reload. With "Switch sets automatically" off, the last set picked is used
-- and remembered across logins.
local _, ns = ...

local Sets = {}
ns.QuickSets = Sets

Sets.SITUATIONAL = { "world", "party", "raid" }
Sets.NAMES = { world = "Open World", party = "Party / Dungeon", raid = "Raid / BG", combat = "Combat" }
Sets.SHORT = { world = "World", party = "Party", raid = "Raid", combat = "Combat" }
-- Where to go when the detected set is turned off.
local FALLBACK = {
    world = { "world", "party", "raid" },
    party = { "party", "world", "raid" },
    raid = { "raid", "party", "world" },
}
Sets.ALIASES = {
    world = "world", open = "world", solo = "world", ow = "world",
    party = "party", dungeon = "party", group = "party",
    raid = "raid", bg = "raid", pvp = "raid", battleground = "raid",
}

local active      -- set key laid out on the bar (what clicks and keys fire)
local pending     -- set waiting for combat to end
local pinned      -- session pin (cleared at login / reload)

local function S() return ns.DB.Settings().quick end

-- known, a, b: known is false when the API is missing, errors or answers
-- with a secret.
local function read(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b = pcall(fn, ...)
    if not ok or ns.Secret(a, b) then return false end
    return true, a, b
end

-- "world" | "party" | "raid", or nil when the client won't say.
function Sets.Detect()
    local kRaid, raid = read(IsInRaid)
    if kRaid and raid then return "raid" end
    local kIn, inInstance, kind = read(IsInInstance)
    if kIn and inInstance and (kind == "pvp" or kind == "arena") then return "raid" end
    local pvp = C_PvP and C_PvP.IsBattleground
    if pvp then
        local kBg, bg = read(pvp)
        if kBg and bg then return "raid" end
    end
    -- Anything below needs to know we're not in a raid or a BG.
    if not kRaid or not kIn then return nil end
    if inInstance and kind == "party" then return "party" end
    local kGroup, group = read(IsInGroup)
    if not kGroup then return nil end
    if group then return "party" end
    return "world"
end

-- Should the Combat row be shown right now (by the setting alone)?
-- true / false, or nil when "only in groups" can't tell (IsInGroup errored
-- or returned a secret): callers keep whatever is on screen.
function Sets.CombatRowWanted()
    local mode = ns.DB.CombatRow()
    if mode == "off" then return false end
    if mode == "groups" then
        local ok, inGroup = pcall(IsInGroup)
        if not ok or ns.Secret(inGroup) then return nil end
        return inGroup and true or false
    end
    return true
end

-- "on (always)" / "on (only in groups)" / "off"
Sets.COMBAT_ROW_TEXT = { always = "on (always)", groups = "on (only in groups)", off = "off" }
function Sets.DescribeCombatRow()
    local text = "Combat row: " .. Sets.COMBAT_ROW_TEXT[ns.DB.CombatRow()] .. "."
    if ns.Lockdown.CombatLocked() then text = text .. " Shows or hides when combat ends." end
    return text
end

function Sets.Enabled(key)
    if key == "combat" then return ns.DB.CombatRow() ~= "off" end
    local set = S().sets[key]
    return set ~= nil and set.enabled ~= false
end

-- First enabled set for key (the set itself if it's on). nil if all are off.
function Sets.Resolve(key)
    for _, k in ipairs(FALLBACK[key] or FALLBACK.world) do
        if Sets.Enabled(k) then return k end
    end
    return nil
end

-- The set Comms wants right now; nil = keep the current one.
function Sets.Wanted()
    local s = S()
    local want
    if pinned then want = pinned
    elseif s.auto then
        want = Sets.Detect()
        if not want then return nil end
    else
        want = s.lastPicked or "world"
    end
    return Sets.Resolve(want)
end

function Sets.Active() return active end
function Sets.Pending() return pending end
function Sets.Pinned() return pinned end

function Sets.Lines(key)
    local set = S().sets[key or active or "world"]
    return set and set.lines or {}
end

-- Re-read the context. Returns "changed" | "pending" | nil (no change).
function Sets.Evaluate()
    local want = Sets.Wanted()
    if want == nil then
        -- Unknown context (or every set off): keep the current set while it's on.
        if active and Sets.Enabled(active) then return nil end
        want = Sets.Resolve(active or S().lastPicked or "world") -- nil: all off
        if want == nil and active == nil then return nil end
    end
    if want == active then
        pending = nil
        return nil
    end
    -- In combat only the very first pick (login or /reload mid-fight) is
    -- applied at once: there's nothing on the bar yet to move.
    if ns.Lockdown.CombatLocked() and active ~= nil then
        if want == nil then return nil end -- re-checked on PLAYER_REGEN_ENABLED
        pending = want
        return "pending"
    end
    pending = nil
    active = want
    ns.Fire("QUICKSET_CHANGED", want)
    return "changed"
end

-- Pick a set by hand (bar tab, /comms set, Settings). "auto" clears the pin
-- and turns auto switching back on.
function Sets.Pick(key)
    local s = S()
    if key == "auto" then
        pinned = nil
        s.auto = true
    else
        key = Sets.ALIASES[key or ""] or key
        if not FALLBACK[key] then return nil end
        pinned = key
        s.lastPicked = key
    end
    return Sets.Evaluate() or "same"
end

-- "Switch sets automatically" on/off. Turning it off keeps the set that's
-- on the bar now (it becomes the manual pick).
function Sets.SetAuto(on)
    local s = S()
    if on then return Sets.Pick("auto") end
    s.auto = false
    if active then s.lastPicked = active end
    return Sets.Evaluate()
end

-- Bar tab: next enabled situational set after the active one.
function Sets.Cycle()
    local list = {}
    for _, k in ipairs(Sets.SITUATIONAL) do if Sets.Enabled(k) then table.insert(list, k) end end
    if #list == 0 then return nil end
    local cur = pending or active
    local nextK = list[1]
    for i, k in ipairs(list) do if k == cur then nextK = list[i % #list + 1] end end
    return Sets.Pick(nextK)
end

-- Short line for /comms set and the Settings page.
function Sets.Describe()
    local name = active and Sets.NAMES[active] or "none (all sets off)"
    local how = pinned and "pinned (until /comms set auto or next login)"
        or (S().auto and "automatic" or "manual (auto switching off)")
    local tail = pending and ("; switches to " .. Sets.NAMES[pending] .. " when combat ends") or ""
    return ("Quick lines: %s, %s%s."):format(name, how, tail)
end

function Sets.Init()
    active, pending, pinned = nil, nil, nil
    Sets.Evaluate()
end

-- Tests only.
function Sets._Reset() active, pending, pinned = nil, nil, nil end
