-- /tt [msg]: whisper your target (realm-aware). No message: opens the chat box
-- as "/w Target ". In chat lockdown the message is prefilled instead of sent.
local _, ns = ...

local TT = {}
ns.TellTarget = TT

-- "Name" or "Name-Realm" for the target, or nil + reason.
function TT.TargetName(unit)
    unit = unit or "target"
    if not ns.SafeCall(UnitExists, unit) then return nil, "You have no target." end
    local isPlayer = UnitIsPlayer and ns.Try(UnitIsPlayer, unit)
    if ns.Secret(isPlayer) then return nil, "The game hides your target's name here (chat lockdown)." end
    if UnitIsPlayer and not isPlayer then return nil, "Your target isn't a player." end
    local name, realm = UnitName(unit)
    if ns.Secret(name, realm) or type(name) ~= "string" or name == "" then
        return nil, "The game hides your target's name here (chat lockdown)."
    end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Returns "sent" | "prefill" | nil.
function TT.Run(msg)
    msg = ns.Trim(msg)
    local who, err = TT.TargetName("target")
    if not who then
        ns.Print(err)
        return nil
    end
    if msg == "" then
        ns.QuickLines.Prefill("/w " .. who .. " ")
        return "prefill"
    end
    if ns.Lockdown.CanSend() then
        if ns.QuickLines.Send(msg, "WHISPER", who) then return "sent" end
        return nil
    end
    ns.QuickLines.Prefill("/w " .. who .. " " .. msg)
    return "prefill"
end
