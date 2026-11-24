-- Comms: namespace, client guard, tiny event bus, helpers.
--
-- Comms by Nine Point Labs. Not related to Forever Comms Voice / Guild Comms /
-- Group Comms or Quick Comms.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "Comms"
local meta = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
-- An unpackaged checkout still carries the packager token.
ns.VERSION = tostring(meta):find("@", 1, true) and "dev" or meta

-- Forever only. WOW_PROJECT_CAMELOT (= 18) is the Forever project id per the
-- wow-ui-source forever branch; refuse to run anywhere else.
ns.FOREVER_PROJECT_ID = WOW_PROJECT_CAMELOT or 18
ns.disabled = (WOW_PROJECT_ID ~= ns.FOREVER_PROJECT_ID)

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.ICON = ns.MEDIA .. "Icon"
ns.HEX = "|cff4fb3ff"

-- The one global table (key bindings call into it). Everything else lives in ns.
Comms = Comms or {}
ns.API = Comms

local listeners = {}
function ns.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function ns.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok and ns.Debug then ns.Debug("listener error for " .. event .. ": " .. tostring(err)) end
    end
end

function ns.Print(msg)
    print(ns.HEX .. "Comms|r: " .. tostring(msg))
end

function ns.Debug(msg)
    if ns.db and ns.db.global and ns.db.global.settings.debug then
        print("|cff888888[Comms debug]|r " .. tostring(msg))
    end
end

-- Forever hides chat from addons in lockdown ("secret values"): they can be
-- passed around but never compared, concatenated or stored. True if any
-- argument is one (or can't be accessed), so callers back off.
function ns.Secret(...)
    local isSecret, canAccess = issecretvalue, canaccessvalue
    if not isSecret and not canAccess then return false end
    for i = 1, select("#", ...) do
        local v = (select(i, ...))
        if isSecret and isSecret(v) then return true end
        if canAccess and not canAccess(v) then return true end
    end
    return false
end

-- A unit/state query that may come back secret in lockdown: the value, or
-- nil when it's secret (a secret can't even be tested with "if").
function ns.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or ns.Secret(v) then return nil end
    return v
end

-- Call fn safely; returns its results, or nothing when it errors or is missing.
function ns.Try(fn, ...)
    if type(fn) ~= "function" then return end
    local res = { pcall(fn, ...) }
    if not res[1] then return end
    return unpack(res, 2)
end

function ns.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Player-written text must never be read as colour or link codes.
function ns.Escape(s)
    return (tostring(s or ""):gsub("|", "||"))
end

-- Strip colour, texture and hyperlink codes (for copy and search).
function ns.Plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("||", "|")
    return s
end

-- "Name-Realm" -> "Name", realm (realm nil when absent).
function ns.SplitName(full)
    if type(full) ~= "string" then return nil end
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name then return name, realm end
    return full, nil
end

function ns.MyRealm()
    return ns.Try(GetNormalizedRealmName) or ns.Try(GetRealmName) or ""
end

function ns.MyName()
    local n = ns.Try(UnitName, "player")
    if not ns.Secret(n) and type(n) == "string" then return n end
    return nil
end

-- A stable key for a character: "name-realm", lower case.
function ns.NameKey(full)
    local name, realm = ns.SplitName(full)
    if not name or name == "" then return nil end
    realm = (realm and realm ~= "") and realm or ns.MyRealm()
    return (name .. "-" .. realm:gsub("%s", "")):lower()
end

-- Display: drop our own realm.
function ns.ShortName(full)
    local name, realm = ns.SplitName(full)
    if not name then return "" end
    if not realm or realm:gsub("%s", ""):lower() == ns.MyRealm():gsub("%s", ""):lower() then return name end
    return name .. "-" .. realm
end

function ns.Now()
    return (time and time()) or 0
end
