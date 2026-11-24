-- Search: /comms search <text> and the Search panel, over stored chat history,
-- this session's lines and whisper history. Case-insensitive, plain text.
local _, ns = ...

local Search = {}
ns.Search = Search

Search.query = ""
Search.LIMIT = 200

-- Returns newest-first list of { line, source } (source "chat" | "whisper").
function Search.Run(query)
    query = ns.Trim(query):lower()
    Search.query = query
    local out = {}
    if query == "" then return out end
    local function hit(text, who)
        return (text and text:lower():find(query, 1, true)) or (who and who:lower():find(query, 1, true))
    end
    for _, l in ipairs(ns.History.All()) do
        if hit(l.m, l.a) then table.insert(out, { line = l, source = "chat" }) end
    end
    for _, c in pairs(ns.db.global.whispers) do
        for _, l in ipairs(c.lines or {}) do
            if hit(l.m, c.display) then
                table.insert(out, { line = { t = l.t, e = l.d == "out" and "WHISPER_INFORM" or "WHISPER", a = c.display, m = l.m }, source = "whisper" })
            end
        end
    end
    table.sort(out, function(a, b) return (a.line.t or 0) > (b.line.t or 0) end)
    while #out > Search.LIMIT do table.remove(out) end
    return out
end
