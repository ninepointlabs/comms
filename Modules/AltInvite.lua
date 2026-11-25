-- Alt-click a player name in chat to invite them.
--
-- Blizzard's chat frame broadcasts every link click as EventRegistry
-- "ChatFrame.OnHyperlinkClick" (chatFrame, link, text, button); we listen
-- there, so nothing of Blizzard's is replaced or hooked. Secret names (chat
-- lockdown) are ignored. Blizzard still runs its own plain-click action (it
-- opens a whisper to that player); press Escape to close it.
local _, ns = ...

local AltInvite = {}
ns.AltInvite = AltInvite

-- EventRegistry callback (owner first).
function AltInvite.OnHyperlinkClick(_, chatFrame, link, text, button)
    if not ns.db or not ns.DB.Settings().links.altInvite then return end
    if ns.Secret(link) or type(link) ~= "string" then return end
    if not (IsAltKeyDown and IsAltKeyDown()) then return end
    local name = link:match("^player:([^:]+)")
    if not name or name == "" then return end
    return ns.Links.Invite(name)
end

function AltInvite.Install()
    if AltInvite.installed then return end
    AltInvite.installed = true
    local reg = EventRegistry
    if reg and reg.RegisterCallback then
        pcall(reg.RegisterCallback, reg, "ChatFrame.OnHyperlinkClick", AltInvite.OnHyperlinkClick, AltInvite)
    end
end
