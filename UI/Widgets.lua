-- UI/Widgets.lua : shared widget factories (labels, inputs, buttons, windows).
local ADB = ADB
local UI = {}
ADB.UI = UI

local EDIT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function UI.ApplyBackdrop(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.02, 0.1, 0.85)
    f:SetBackdropBorderColor(0.55, 0.35, 0.85, 1)
end

function UI.Label(parent, text, x, y, font)
    local s = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    s:SetPoint("TOPLEFT", x, y)
    s:SetJustifyH("LEFT")
    s:SetText(text)
    return s
end

function UI.Input(parent, x, y, w, maxLetters, numeric)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters)
    if numeric then e:SetNumeric(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

function UI.Button(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function UI.BaseWindow(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText(title) end
    f:Hide()
    return f
end

-- Framed multiline edit box. Returns the EditBox (frame = editbox:GetParent()).
function UI.MultilineInput(parent, x, y, w, h, maxLetters)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetBackdrop(EDIT_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.6)
    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetPoint("TOPLEFT", 6, -6)
    eb:SetSize(w - 12, h - 12)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    return eb
end

-- Square icon button with grey border; `.icon` is the texture to update.
function UI.IconButton(parent, x, y, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetPoint("TOPLEFT", x, y)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.4, 0.4, 0.4, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    return b
end