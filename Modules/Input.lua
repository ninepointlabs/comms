-- Input: a bigger chat box. Restyles Blizzard's own edit boxes (height, font
-- size, above/below the chat window); there is no replacement frame, so Tim
-- always types into Blizzard's box and Blizzard sends it.
--
-- Only widget setters are called (SetHeight, SetFont, SetPoint) and never in
-- chat lockdown or combat; the style is static, so it simply stays in place
-- while locked. Turning it off restores the sizes captured before the first
-- change.
local _, ns = ...

local Input = {}
ns.Input = Input

local original = {} -- editBox -> { h, font, size, flags, points }

local function S() return ns.DB.Settings().input end

local function capture(eb)
    if original[eb] then return end
    local o = { h = eb.GetHeight and eb:GetHeight(), points = {} }
    if eb.GetFont then o.font, o.size, o.flags = eb:GetFont() end
    if eb.GetNumPoints and eb.GetPoint then
        for i = 1, (eb:GetNumPoints() or 0) do o.points[i] = { eb:GetPoint(i) } end
    end
    original[eb] = o
end

function Input.Style(eb, chatFrame)
    local s = S()
    capture(eb)
    eb:SetHeight(s.height)
    local font, _, flags
    if eb.GetFont then font, _, flags = eb:GetFont() end
    if font and eb.SetFont then eb:SetFont(font, s.fontSize, flags or "") end
    if chatFrame and eb.ClearAllPoints then
        eb:ClearAllPoints()
        if s.position == "above" then
            eb:SetPoint("BOTTOMLEFT", chatFrame, "TOPLEFT", -5, 22)
            eb:SetPoint("BOTTOMRIGHT", chatFrame, "TOPRIGHT", 5, 22)
        else
            eb:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", -5, -2)
            eb:SetPoint("TOPRIGHT", chatFrame, "BOTTOMRIGHT", 5, -2)
        end
    end
end

function Input.Restore(eb)
    local o = original[eb]
    if not o then return end
    if o.h then eb:SetHeight(o.h) end
    if o.font and eb.SetFont then eb:SetFont(o.font, o.size, o.flags or "") end
    if #o.points > 0 and eb.ClearAllPoints then
        eb:ClearAllPoints()
        for _, p in ipairs(o.points) do eb:SetPoint(unpack(p)) end
    end
    original[eb] = nil
end

-- Returns number of boxes styled (0 when deferred or off).
function Input.Apply()
    if ns.Lockdown.Busy() then
        Input.pending = true
        return 0
    end
    Input.pending = false
    local n = NUM_CHAT_WINDOWS or 10
    local count = 0
    for i = 1, n do
        local eb, cf = _G["ChatFrame" .. i .. "EditBox"], _G["ChatFrame" .. i]
        if eb then
            if S().enabled then
                Input.Style(eb, cf)
                count = count + 1
            else
                Input.Restore(eb)
            end
        end
    end
    return count
end
