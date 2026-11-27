-- Lockdown: the single source of truth for "can Comms touch chat right now?".
--
-- Forever (Midnight's addon restrictions) locks chat in instances: chat events
-- arrive as secret values and addons can't send any chat. The client says so
-- three ways, all used here:
--   C_ChatInfo.InChatMessagingLockdown()
--   C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat)
--   ADDON_RESTRICTION_STATE_CHANGED (type, state), which fires *before* a
--   restriction becomes active (state Activating), so we stop first.
-- Combat lockdown (InCombatLockdown) is tracked separately: it doesn't stop
-- chat, but Comms never touches Blizzard's edit box during it.
--
-- Every module asks here; nobody polls. Fires "LOCKDOWN_CHANGED" (locked, reason).
local _, ns = ...

local L = {}
ns.Lockdown = L

-- Enum.AddOnRestrictionType values from the forever branch, used when the Enum
-- itself isn't there.
L.TYPES = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
L.REASONS = { [0] = "combat", [1] = "encounter", [2] = "keystone", [3] = "PvP match", [4] = "map", [5] = "chat" }

local active = {}   -- restriction type -> true while Activating/Active
local wasLocked = false
-- Between PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED. InCombatLockdown()
-- still answers false inside PLAYER_REGEN_DISABLED handlers, so this covers
-- the first moment of a fight.
local regenDisabled = false

local function restrictionType(name)
    local e = Enum and Enum.AddOnRestrictionType
    return (e and e[name]) or L.TYPES[name]
end

local function apiChatLocked()
    local ci = C_ChatInfo
    if ci and ci.InChatMessagingLockdown then
        local v = ns.Try(ci.InChatMessagingLockdown)
        if not ns.Secret(v) and v then return true end
    end
    local ra = C_RestrictedActions
    if ra and ra.IsAddOnRestrictionActive then
        local v = ns.Try(ra.IsAddOnRestrictionActive, restrictionType("Chat"))
        if not ns.Secret(v) and v then return true end
    end
    return false
end

-- Chat lockdown: no sending, chat events secret.
function L.ChatLocked()
    if active[restrictionType("Chat")] then return true end
    return apiChatLocked()
end

function L.CombatLocked()
    return regenDisabled or (ns.Try(InCombatLockdown) and true or false)
end

-- True when Comms must keep its hands off Blizzard's edit box.
function L.Busy()
    return L.ChatLocked() or L.CombatLocked()
end

function L.CanSend()
    return not L.ChatLocked()
end

function L.InInstance()
    local inInstance, kind = ns.Try(IsInInstance)
    if ns.Secret(inInstance, kind) then return true end
    return inInstance and true or false, kind
end

-- Short human reason for the About panel and banners.
function L.Reason()
    if L.ChatLocked() then
        for t, on in pairs(active) do
            if on and t ~= restrictionType("Chat") and L.REASONS[t] then return L.REASONS[t] end
        end
        if L.InInstance() then return "instance" end
        return "chat"
    end
    if L.CombatLocked() then return "combat" end
    return nil
end

function L.Status()
    local reason = L.Reason()
    if L.ChatLocked() then return ("Chat locked: yes (%s)"):format(reason or "chat") end
    if reason == "combat" then return "Chat locked: no (in combat: input left alone)" end
    return "Chat locked: no"
end

function L.Recompute()
    local now = L.ChatLocked()
    if now ~= wasLocked then
        wasLocked = now
        ns.Fire("LOCKDOWN_CHANGED", now, L.Reason())
    end
    return now
end

function L.OnRestrictionChanged(rtype, state)
    if ns.Secret(rtype, state) then return end
    -- 0 Inactive, 1 Activating, 2 Active.
    active[rtype] = (state ~= nil and state ~= 0) or nil
    L.Recompute()
end

function L.OnEvent(event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        L.OnRestrictionChanged(...)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        regenDisabled = event == "PLAYER_REGEN_DISABLED"
        ns.Fire("COMBAT_CHANGED", event == "PLAYER_REGEN_DISABLED")
        L.Recompute()
    else
        L.Recompute()
    end
end

L.EVENTS = { "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

-- Seed from the client's current state (login inside a dungeon).
function L.Init()
    local ra = C_RestrictedActions
    if ra and ra.IsAddOnRestrictionActive then
        for _, t in pairs(L.TYPES) do
            local v = ns.Try(ra.IsAddOnRestrictionActive, t)
            if not ns.Secret(v) and v then active[t] = true end
        end
    end
    wasLocked = L.ChatLocked()
end

-- Tests only.
function L._Reset()
    active = {}
    wasLocked = false
    regenDisabled = false
end
