-- Minimal, strict WoW API mock for headless tests (Lua 5.1), in the style of
-- the sister addons' mocks (Tazu's Addon, The Terminal List). Undefined
-- globals raise an error so typos and unmocked APIs surface here instead of in
-- the client. Optional APIs the addon feature-tests are listed in OPTIONAL and
-- read as nil.
--
-- Forever specifics mocked from wow-ui-source `forever` (c01a87b, 1.60.1):
-- ChatFrameUtil filter registries (skip secret args via canaccessvalue),
-- C_ChatInfo.InChatMessagingLockdown / SendChatMessage, C_RestrictedActions,
-- Enum.AddOnRestrictionType, EventRegistry ("SetItemRef",
-- "ChatFrame.OnHyperlinkClick"), LinkUtil, issecretvalue / canaccessvalue.
local M = {}

M.texts = {}       -- every SetText call, for assertions
M.printed = {}     -- every print() line
M.events = {}      -- frames registered per event
M.timers = {}
M.popups = {}      -- StaticPopup_Show calls
M.sounds = {}
M.sent = {}        -- C_ChatInfo.SendChatMessage / BN whispers: { text, chatType, target }
M.opened = {}      -- ChatFrameUtil.OpenChat(text)
M.left = {}        -- LeaveChannelByName(name)
M.invites = {}     -- C_PartyInfo.InviteUnit(name)
M.flashes = {}     -- FCF_StartAlertFlash(frame)
M.cvars = { showTimestamps = "none" }
M.messageFilters = {} -- event -> { fn, ... }
M.nameFilters = {}
M.callbacks = {}   -- EventRegistry event -> { {fn, owner} }
M.blizzardSetScript = {} -- SetScript calls made on Blizzard-owned objects (taint audit)

M.state = {
    projectId = 18, combat = false, time = 1000, now = 1795536000, -- 2026-11-24
    zone = "Stormwind City", realm = "CAMWOWUS2Realm1PvE",
    instanceType = nil, -- nil = open world
    chatLocked = false,  -- C_ChatInfo.InChatMessagingLockdown()
    restrictions = {},   -- type -> true (C_RestrictedActions.IsAddOnRestrictionActive)
    alt = false,
    group = nil,         -- nil | "party" | "raid" | "instance"
    groupMembers = {},   -- unit -> {name, realm}
    me = { guid = "Player-1-0000000A", name = "Andric", class = "SHAMAN" },
    units = {},
    guids = {},          -- guid -> { class }
    channels = { General = 1, Trade = 2, LocalDefense = 3, Services = 4, ["Trade (City)"] = 5 },
    friends = {},        -- { {name, connected} }
    guild = {},          -- { "Name-Realm" }
    bnet = {},           -- id -> { battleTag }
    lastTell = nil,
    bindings = {},
}
local S = M.state

local function newObject(kind, opts)
    local o = { __kind = kind, __shown = true, __scripts = {}, __hooks = {}, __w = 100, __h = 20, __messages = {} }
    if opts and opts.blizzard then o.__blizzard = true end
    return setmetatable(o, {
        __index = function(t, k)
            if k == "SetText" then
                return function(self, s) self.__text = s table.insert(M.texts, tostring(s or "")) end
            elseif k == "GetText" then
                return function(self) return self.__text end
            elseif k == "SetScript" then
                return function(self, ev, fn)
                    if self.__blizzard then table.insert(M.blizzardSetScript, { obj = self.__kind, ev = ev }) end
                    self.__scripts[ev] = fn
                end
            elseif k == "GetScript" then
                return function(self, ev) return self.__scripts[ev] end
            elseif k == "HookScript" then
                return function(self, ev, fn)
                    self.__hooks[ev] = self.__hooks[ev] or {}
                    table.insert(self.__hooks[ev], fn)
                end
            elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then
                return function(self, ev) M.events[ev] = M.events[ev] or {} table.insert(M.events[ev], self) end
            elseif k == "UnregisterEvent" then
                return function() end
            elseif k == "Show" then
                return function(self) self.__shown = true if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
            elseif k == "Hide" then
                return function(self) self.__shown = false end
            elseif k == "SetShown" then
                return function(self, v) if v then self:Show() else self:Hide() end end
            elseif k == "IsShown" or k == "IsVisible" then
                return function(self) return self.__shown end
            elseif k == "SetWidth" then
                return function(self, w) self.__w = w end
            elseif k == "SetHeight" then
                return function(self, h) self.__h = h end
            elseif k == "SetSize" then
                return function(self, w, h) self.__w, self.__h = w, h end
            elseif k == "GetWidth" then
                return function(self) return self.__w end
            elseif k == "GetHeight" then
                return function(self) return self.__h end
            elseif k == "SetFont" then
                return function(self, f, size, flags) self.__font = { f, size, flags } end
            elseif k == "GetFont" then
                return function(self) if self.__font then return unpack(self.__font) end return "Fonts\\ARIALN.TTF", 14, "" end
            elseif k == "SetPoint" then
                return function(self, ...) self.__points = self.__points or {} table.insert(self.__points, { ... }) end
            elseif k == "ClearAllPoints" then
                return function(self) self.__points = {} end
            elseif k == "GetStringHeight" then
                return function() return 14 end
            elseif k == "GetStringWidth" then
                return function(self) return #(tostring(self.__text or "")) * 6 end
            elseif k == "GetChecked" then
                return function(self) return self.__checked end
            elseif k == "SetChecked" then
                return function(self, v) self.__checked = v end
            elseif k == "SetTexture" then
                return function(self, tex) self.__texture = tex end
            elseif k == "GetFrameLevel" then
                return function() return 1 end
            elseif k == "GetCenter" then
                return function() return 0, 0 end
            elseif k == "GetEffectiveScale" then
                return function() return 1 end
            elseif k == "Disable" then
                return function(self) self.__disabled = true end
            elseif k == "Enable" then
                return function(self) self.__disabled = false end
            elseif k == "AddLine" then
                return function(self, s) self.__lines = self.__lines or {} table.insert(self.__lines, tostring(s)) end
            elseif k == "AddMessage" then
                return function(self, s) table.insert(self.__messages, s) end
            elseif k == "Clear" then
                return function(self) self.__messages = {} end
            elseif k == "GetNumMessages" then
                return function(self) return #self.__messages end
            elseif k == "GetMessageInfo" then
                return function(self, i) return self.__messages[i] end
            elseif k:match("^%l") or k:match("^__") then
                return nil -- plain fields (frame.someField) are nil until set, as in the client
            elseif k:match("^Create") then
                return function() return newObject(k) end
            elseif k:match("^Is") or k:match("^Can") then
                return function() return false end
            else
                return function() return nil end
            end
        end,
    })
end
M.newObject = newObject

-- Run a widget script plus its HookScript hooks (as the client would).
function M.RunScript(obj, ev, ...)
    if obj.__scripts[ev] then obj.__scripts[ev](obj, ...) end
    for _, fn in ipairs(obj.__hooks[ev] or {}) do fn(obj, ...) end
end

function M.Fire(event, ...)
    for _, f in ipairs(M.events[event] or {}) do
        local fn = f.__scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end

function M.RunTimers()
    for _ = 1, 5 do
        local list = M.timers
        if #list == 0 then return end
        M.timers = {}
        for _, t in ipairs(list) do if not t.cancelled then t.fn() end end
    end
end

local function U(u)
    if u == "player" then return S.me end
    return S.units[u]
end
M.U = U

-- Secret values: an opaque sentinel recognised by issecretvalue/canaccessvalue.
M.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function isSecret(v) return v == M.SECRET end
local function canAccessAll(...)
    for i = 1, select("#", ...) do if isSecret((select(i, ...))) then return false end end
    return true
end

local G = {}

G.CreateFrame = function(kind, name) local f = newObject(kind) if name then rawset(_G, name, f) end return f end
G.UIParent = newObject("UIParent", { blizzard = true })
G.ChatFontNormal = newObject("Font")
G.Minimap = newObject("Minimap", { blizzard = true })
G.GameTooltip = newObject("GameTooltip")
G.UISpecialFrames = {}
G.StaticPopupDialogs = {}
G.StaticPopup_Show = function(which, a1, a2, data) table.insert(M.popups, { which = which, a1 = a1, a2 = a2, data = data }) end
G.SlashCmdList = {}
G.CLOSE, G.ADD, G.CANCEL, G.SAVE, G.REMOVE, G.YES, G.NO = "Close", "Add", "Cancel", "Save", "Remove", "Yes", "No"
G.Mixin = function(o, m) for k, v in pairs(m) do o[k] = v end return o end
G.BackdropTemplateMixin = {}
G.Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
G.SettingsPanel = newObject("SettingsPanel")
G.HideUIPanel = function() end
G.Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } }
G.C_Timer = {
    After = function(_, fn) table.insert(M.timers, { fn = fn }) end,
    NewTimer = function(_, fn) local t = { fn = fn, Cancel = function(self) self.cancelled = true end } table.insert(M.timers, t) return t end,
}
G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
G.RAID_CLASS_COLORS = {
    SHAMAN = { r = 0, g = 0.44, b = 0.87, colorStr = "ff0070dd" },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
    MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" },
    ROGUE = { r = 1, g = 0.96, b = 0.41, colorStr = "fffff569" },
}
G.SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, TELL_MESSAGE = 3081, IG_PLAYER_INVITE = 880 }
G.PlaySound = function(id) table.insert(M.sounds, id) end
-- Blizzard's defaults on Forever 1.60.1 (ChatTypeInfoConstants.lua).
G.ChatTypeInfo = {
    SAY = { sticky = 1 }, PARTY = { sticky = 1 }, RAID = { sticky = 1 }, GUILD = { sticky = 1 }, OFFICER = { sticky = 1 },
    YELL = { sticky = 0 }, WHISPER = { sticky = 1 }, BN_WHISPER = { sticky = 1 }, EMOTE = { sticky = 0 },
    CHANNEL = { sticky = 1 }, INSTANCE_CHAT = { sticky = 1 },
}
G.time = function() return S.now end
G.date = os.date
G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
G.GetTime = function() return S.time end
G.GetCursorPosition = function() return 0, 0 end
G.InCombatLockdown = function() return S.combat end
G.IsAltKeyDown = function() return S.alt end
G.hooksecurefunc = function(a, b, c)
    -- hooksecurefunc(table, "method", fn) or hooksecurefunc("global", fn)
    if type(a) == "table" then
        local orig = a[b]
        rawset(a, b, function(...) local r = orig and orig(...) c(...) return r end)
        M.hooked = M.hooked or {}
        table.insert(M.hooked, b)
    else
        local orig = rawget(_G, a)
        rawset(_G, a, function(...) local r = orig and orig(...) b(...) return r end)
    end
end
G.GetNormalizedRealmName = function() return S.realm end
G.GetRealmName = function() return S.realm end
G.GetZoneText = function() return S.zone end
G.GetRealZoneText = function() return S.zone end
G.GetBindingKey = function(name) return S.bindings[name] end

-- Units
G.UnitExists = function(u) return U(u) ~= nil end
G.UnitIsPlayer = function(u) return U(u) and (U(u).player ~= false) or false end
G.UnitName = function(u)
    local x = U(u)
    if not x then return nil end
    if u == "player" then return x.name end
    return x.name, x.realm
end
G.UnitClass = function(u) local x = U(u) if not x then return nil end return x.class, x.class end
G.GetPlayerInfoByGUID = function(guid)
    local x = S.guids[guid]
    if not x then return nil end
    return x.class, x.class, "Human", "Human", 2, x.name, x.realm or ""
end
G.IsInInstance = function() if S.instanceType then return true, S.instanceType end return false, "none" end
G.IsInGroup = function(cat)
    if cat == 2 then return S.group == "instance" end
    return S.group ~= nil
end
G.IsInRaid = function() return S.group == "raid" end
G.GetNumGroupMembers = function() local n = 0 for _ in pairs(S.groupMembers) do n = n + 1 end return n end
G.LE_PARTY_CATEGORY_INSTANCE = 2
G.LE_PARTY_CATEGORY_HOME = 1

-- Chat
G.NUM_CHAT_WINDOWS = 2
G.ChatFrame1 = newObject("ChatFrame1", { blizzard = true })
G.ChatFrame2 = newObject("ChatFrame2", { blizzard = true })
G.ChatFrame1EditBox = newObject("ChatFrame1EditBox", { blizzard = true })
G.ChatFrame2EditBox = newObject("ChatFrame2EditBox", { blizzard = true })
for i, f in ipairs({ G.ChatFrame1, G.ChatFrame2 }) do
    rawset(f, "GetID", function() return i end)
    rawset(f, "GetMaxLines", function() return 128 end)
end
for _, eb in ipairs({ G.ChatFrame1EditBox, G.ChatFrame2EditBox }) do
    eb.__history = {}
    eb.__historyLines = 32
    rawset(eb, "AddHistoryLine", function(self, line) table.insert(self.__history, line) end)
    rawset(eb, "SetAltArrowKeyMode", function(self, v) self.__altArrow = v end)
    rawset(eb, "GetHistoryLines", function(self) return self.__historyLines end)
    rawset(eb, "SetHistoryLines", function(self, n) self.__historyLines = n end)
    rawset(eb, "GetCursorPosition", function(self) return #(self.__text or "") end)
    rawset(eb, "SetCursorPosition", function(self, n) self.__cursor = n end)
end
G.DEFAULT_CHAT_FRAME = G.ChatFrame1
G.SELECTED_CHAT_FRAME = G.ChatFrame1
G.FCF_StartAlertFlash = function(frame) table.insert(M.flashes, frame) end

G.ChatFrameUtil = {
    AddMessageEventFilter = function(ev, fn)
        M.messageFilters[ev] = M.messageFilters[ev] or {}
        table.insert(M.messageFilters[ev], fn)
    end,
    AddSenderNameFilter = function(fn) table.insert(M.nameFilters, fn) end,
    OpenChat = function(text, frame, cursor) table.insert(M.opened, text) M.openedCursor = cursor end,
    GetLastTellTarget = function() return S.lastTell end,
}
G.C_ChatInfo = {
    InChatMessagingLockdown = function() return S.chatLocked end,
    SendChatMessage = function(text, chatType, lang, target)
        table.insert(M.sent, { text = text, chatType = chatType or "SAY", target = target })
    end,
    GetChannelShortcutForChannelID = function(id)
        local names = { [1] = "General", [2] = "Trade", [22] = "LocalDefense", [26] = "LookingForGroup", [42] = "Services", [46] = "Trade (City)" }
        return names[id] or ""
    end,
}
G.C_RestrictedActions = {
    IsAddOnRestrictionActive = function(t) return S.restrictions[t] and true or false end,
}
G.C_CVar = {
    GetCVar = function(k) return M.cvars[k] end,
    SetCVar = function(k, v) M.cvars[k] = v return true end,
}
G.C_PartyInfo = { InviteUnit = function(name) table.insert(M.invites, name) end }
G.C_BattleNet = {
    GetAccountInfoByID = function(id) return S.bnet[id] end,
    SendWhisper = function(id, text) table.insert(M.sent, { text = text, chatType = "BN_WHISPER", target = id }) end,
}
G.C_FriendList = {
    GetNumFriends = function() return #S.friends end,
    GetFriendInfoByIndex = function(i) return S.friends[i] end,
}
G.GetNumGuildMembers = function() return #S.guild end
G.GetGuildRosterInfo = function(i) return S.guild[i] end
G.GetChannelName = function(name)
    local id = S.channels[name]
    if id then return id, name end
    return 0, nil
end
G.LeaveChannelByName = function(name) table.insert(M.left, name) S.channels[name] = nil end
G.LinkUtil = { RegisterLinkHandler = function() error("Comms must not register a second addon link handler") end }
G.EventRegistry = {
    RegisterCallback = function(self, event, fn, owner)
        M.callbacks[event] = M.callbacks[event] or {}
        table.insert(M.callbacks[event], { fn = fn, owner = owner })
    end,
}

-- Fire an EventRegistry event the way CallbackRegistry does (owner first).
function M.Trigger(event, ...)
    for _, cb in ipairs(M.callbacks[event] or {}) do cb.fn(cb.owner, ...) end
end

-- Run every registered message filter like ChatFrameUtil's registry: a filter
-- is skipped when any argument is secret; discard stops; a truthy second
-- return replaces the args. Returns discard, args...
function M.RunFilters(frame, event, ...)
    local args = { ... }
    local n = math.max(select("#", ...), 14)
    for _, fn in ipairs(M.messageFilters[event] or {}) do
        if canAccessAll(unpack(args, 1, n)) then
            local res = { fn(frame, event, unpack(args, 1, n)) }
            if res[1] then return true end
            if res[2] then args = { unpack(res, 2, n + 1) } end
        end
    end
    return false, unpack(args, 1, n)
end

-- Sender-name filters (skipped when the decorated name is secret).
function M.RunNameFilters(event, name, ...)
    if not canAccessAll(name) then return name end
    for _, fn in ipairs(M.nameFilters) do
        local r = fn(event, name, ...)
        if r ~= nil then name = r end
    end
    return name
end

-- Build CHAT_MSG_* args. o: msg, author, channel ("2. Trade - City"), zoneID,
-- channelNum, channelBase, lineID, guid, bnet
function M.ChatArgs(o)
    return o.msg, o.author or "", "", o.channel or "", "", "", o.zoneID or 0, o.channelNum or 0,
        o.channelBase or "", 0, o.lineID or 0, o.guid or "", o.bnet or 0, false
end

function M.InstallSecrets()
    rawset(_G, "issecretvalue", function(v) return isSecret(v) end)
    rawset(_G, "canaccessvalue", function(...) return canAccessAll(...) end)
end
function M.RemoveSecrets()
    rawset(_G, "issecretvalue", nil)
    rawset(_G, "canaccessvalue", nil)
end

local OPTIONAL = {
    issecretvalue = true, canaccessvalue = true, WOW_PROJECT_CAMELOT = true,
    ChatFrame_AddMessageEventFilter = true, ChatFrame_OpenChat = true, SendChatMessage = true,
    BNSendWhisper = true, InviteUnit = true, C_PvP = true, AddonCompartmentFrame = true,
    CommsDB = true, CommsCharDB = true, Comms = true,
    CommsMainFrame = true, CommsMessenger = true, CommsCopyFrame = true, CommsQuickBar = true, CommsMinimapButton = true,
}

function M.Install()
    for k, v in pairs(G) do rawset(_G, k, v) end
    rawset(_G, "WOW_PROJECT_ID", S.projectId)
    rawset(_G, "print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(M.printed, table.concat(parts, " "))
    end)
    setmetatable(_G, {
        __index = function(_, k)
            if OPTIONAL[k] then return nil end
            if type(k) == "string" and (k:match("^ChatFrame%d+$") or k:match("^ChatFrame%d+EditBox$")
                or k:match("^BINDING_") or k:match("^SLASH_")) then return nil end
            error("undefined global: " .. tostring(k), 2)
        end,
        -- Record every global the addon creates (naming test).
        __newindex = function(t, k, v)
            M.newGlobals = M.newGlobals or {}
            M.newGlobals[k] = true
            rawset(t, k, v)
        end,
    })
end

-- Load every file listed in the TOC with (addonName, ns) varargs.
function M.LoadAddon(tocPath, root)
    local ns = {}
    for line in io.lines(tocPath) do
        if not line:match("^##") and line:match("%S") then
            local path = root .. "/" .. line:gsub("\\", "/"):gsub("%s+$", "")
            local chunk = assert(loadfile(path))
            chunk("Comms", ns)
        end
    end
    return ns
end

return M
