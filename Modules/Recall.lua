-- Recall: typed history that survives /reload and logout.
--
-- Up/Down without Alt (EditBox:SetAltArrowKeyMode(false), feature-detected),
-- the last 100 sent lines account-wide, refilled into Blizzard's boxes with
-- AddHistoryLine on login. New lines are captured with hooksecurefunc on each
-- box's AddHistoryLine (Blizzard calls it when a line is sent), so nothing of
-- Blizzard's is replaced. Nothing is captured or touched in lockdown/combat.
local _, ns = ...

local Recall = {}
ns.Recall = Recall

local replaying = false
local hooked = {}

function Recall.EditBoxes()
    local out = {}
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then table.insert(out, eb) end
    end
    return out
end

function Recall.Add(line)
    if replaying then return false end
    if ns.Secret(line) or type(line) ~= "string" then return false end
    line = ns.Trim(line)
    if line == "" then return false end
    if ns.Lockdown.ChatLocked() then return false end
    local typed = ns.db.global.typed
    if typed[#typed] == line then return false end
    table.insert(typed, line)
    ns.DB.Cap(typed, ns.DB.CAPS.typed)
    return true
end

local function onHistoryLine(_, line)
    if not ns.db then return end
    Recall.Add(line)
end

function Recall.Hook(eb)
    if hooked[eb] or not eb.AddHistoryLine then return end
    hooked[eb] = true
    hooksecurefunc(eb, "AddHistoryLine", onHistoryLine)
end

-- Apply no-Alt arrows and refill history. Not in lockdown/combat.
function Recall.Apply()
    if ns.Lockdown.Busy() then
        Recall.pending = true
        return false
    end
    Recall.pending = false
    local noAlt = ns.DB.Settings().input.noAlt
    for _, eb in ipairs(Recall.EditBoxes()) do
        if eb.SetAltArrowKeyMode then ns.Try(eb.SetAltArrowKeyMode, eb, not noAlt) end
        Recall.Hook(eb)
    end
    return true
end

function Recall.Refill()
    if ns.Lockdown.Busy() then
        Recall.pendingRefill = true
        return 0
    end
    Recall.pendingRefill = false
    local typed = ns.db.global.typed
    local n = 0
    replaying = true
    for _, eb in ipairs(Recall.EditBoxes()) do
        if eb.SetHistoryLines and eb.GetHistoryLines then
            local cur = ns.Try(eb.GetHistoryLines, eb) or 32
            if cur < ns.DB.CAPS.typed then ns.Try(eb.SetHistoryLines, eb, ns.DB.CAPS.typed) end
        end
        if eb.AddHistoryLine then
            for _, line in ipairs(typed) do
                ns.Try(eb.AddHistoryLine, eb, line)
                n = n + 1
            end
        end
    end
    replaying = false
    return n
end
