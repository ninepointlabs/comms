-- Copy: open a copy window with a chat window's visible lines (select, Ctrl+C).
--
-- A small copy button sits on each chat window (our own button, parented to
-- the chat frame; nothing of Blizzard's is changed). Locked (secret) lines
-- are skipped. Line-level actions (copy one line, put it in the chat box) are
-- on each Search result, because Blizzard's own timestamps aren't clickable.
local _, ns = ...

local Copy = {}
ns.Copy = Copy

-- Plain text of a chat frame's lines, oldest first. Secret lines skipped.
function Copy.Lines(frame)
    local out, skipped = {}, 0
    if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return out, 0 end
    local n = ns.Try(frame.GetNumMessages, frame) or 0
    for i = 1, n do
        local text = ns.Try(frame.GetMessageInfo, frame, i)
        if text == nil then
            -- nothing
        elseif ns.Secret(text) or type(text) ~= "string" then
            skipped = skipped + 1
        else
            table.insert(out, ns.Plain(text))
        end
    end
    return out, skipped
end

function Copy.Open(frame)
    frame = frame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    local lines, skipped = Copy.Lines(frame)
    local title = ("Copy chat (%d lines)"):format(#lines)
    if skipped > 0 then title = title .. (" · %d locked line%s not copyable"):format(skipped, skipped == 1 and "" or "s") end
    ns.UI.CopyBox(table.concat(lines, "\n"), title)
    return #lines, skipped
end

-- A small button in the top-right corner of each chat window.
function Copy.InstallButtons()
    if Copy.installed then return end
    Copy.installed = true
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local cf = _G["ChatFrame" .. i]
        if cf then
            local b = CreateFrame("Button", nil, cf)
            b:SetSize(18, 18)
            b:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 2, 2)
            b:SetFrameStrata("MEDIUM")
            b:SetAlpha(0.35)
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetTexture(ns.ICON)
            b:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText("Comms: copy this chat", 1, 1, 1)
                GameTooltip:AddLine("Click: copy window · Right-click: Comms", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function(self) self:SetAlpha(0.35) GameTooltip:Hide() end)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", function(_, mouse)
                if mouse == "RightButton" then ns.UI.Toggle() else Copy.Open(cf) end
            end)
            Copy[i] = b
        end
    end
end
