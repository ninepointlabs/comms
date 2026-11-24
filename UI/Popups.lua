-- Copy boxes: a one-line popup (URLs, single lines) and a multi-line window
-- (chat copy). Both select their text so Ctrl+C copies it.
local _, ns = ...
local UI = ns.UI

local function editBox(self)
    return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
end

local function hide(self) self:GetParent():Hide() end

StaticPopupDialogs.COMMS_COPY_TEXT = {
    text = "%s",
    button1 = CLOSE or "Close",
    hasEditBox = true, editBoxWidth = 420,
    OnShow = function(self, data)
        local eb = editBox(self)
        if eb then eb:SetText(data or "") eb:HighlightText() eb:SetFocus() end
    end,
    EditBoxOnEscapePressed = hide, EditBoxOnEnterPressed = hide,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function UI.CopyText(text, prompt)
    if not text or text == "" then return end
    StaticPopup_Show("COMMS_COPY_TEXT", "Comms: " .. (prompt or "Press Ctrl+C to copy."), nil, text)
end
UI.CopyURL = function(url) UI.CopyText(url, "Press Ctrl+C to copy this link.") end

-- Multi-line copy window --------------------------------------------------
local box

local function buildBox()
    local f = CreateFrame("Frame", "CommsCopyFrame", UIParent, "BackdropTemplate")
    f:SetSize(640, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Backdrop(f, UI.C.bg, UI.C.border)
    table.insert(UISpecialFrames, "CommsCopyFrame")
    f.title = UI.Text(f, 14)
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetWordWrap(false)
    f.hint = UI.Text(f, 11, UI.C.dim)
    f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.hint:SetText("Drag to select, Ctrl+A for all, Ctrl+C to copy. Escape closes.")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 16, -52)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    f.edit = CreateFrame("EditBox", nil, f.scroll)
    f.edit:SetMultiLine(true)
    f.edit:SetAutoFocus(false)
    f.edit:SetFontObject(ChatFontNormal)
    f.edit:SetWidth(580)
    f.edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f.scroll:SetScrollChild(f.edit)
    f:Hide()
    return f
end

function UI.CopyBox(text, title)
    box = box or buildBox()
    box.title:SetText(title or "Copy")
    box.edit:SetText(text or "")
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
    return box
end
