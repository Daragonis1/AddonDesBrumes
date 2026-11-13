-- UI/QuestUI.lua : quest/aspiration tracker (ObjectiveTracker style), editor window, gold "quest complete" alert.
local ADB, UI = ADB, ADB.UI
local Quests = ADB.Quests
local floor, max = math.floor, math.max

local QUI = {}
ADB.QuestUI = QUI

------------------------------------------------------------------------------
-- Alert
------------------------------------------------------------------------------
function QUI.Alert(sub, title)
    local a = ADB.qAlert
    if not a then
        a = CreateFrame("Frame", "ADBQuestAlert", UIParent)
        a:SetAllPoints(UIParent)
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a:EnableMouse(false)
        a:Hide()
        a.flash = a:CreateTexture(nil, "BACKGROUND")
        a.flash:SetAllPoints()
        a.flash:SetColorTexture(1, 0.82, 0.2, 1)
        a.band = a:CreateTexture(nil, "BORDER")
        a.band:SetPoint("LEFT", a, "LEFT", 0, 130)
        a.band:SetPoint("RIGHT", a, "RIGHT", 0, 130)
        a.band:SetHeight(110)
        a.band:SetColorTexture(1, 0.75, 0.1, 0.22)
        a.t1 = a:CreateFontString(nil, "OVERLAY")
        a.t1:SetFont(STANDARD_TEXT_FONT, 34, "THICKOUTLINE")
        a.t1:SetPoint("CENTER", a, "CENTER", 0, 150)
        a.t1:SetTextColor(1, 0.82, 0.2)
        a.t2 = a:CreateFontString(nil, "OVERLAY")
        a.t2:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
        a.t2:SetPoint("CENTER", a, "CENTER", 0, 108)
        a.t2:SetTextColor(1, 1, 1)
        a:SetScript("OnUpdate", function(s, elapsed)
            s.e = s.e + elapsed
            local e = s.e
            s.flash:SetAlpha(max(0, 0.4 * (1 - e / 1.0)))
            local ta = (e < 0.4) and (e / 0.4) or (e < 4 and 1 or max(0, 1 - (e - 4)))
            s.t1:SetAlpha(ta)
            s.t2:SetAlpha(ta)
            s.band:SetAlpha(ta)
            if e > 5 then s:Hide() end
        end)
        ADB.qAlert = a
    end
    a.t1:SetText(sub)
    a.t2:SetText(title)
    a.e = 0
    a:Show()
    pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE)
end

------------------------------------------------------------------------------
-- Tracker
------------------------------------------------------------------------------
local function GetBlock(f, i)
    local b = f.blocks[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetWidth(226)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.desc = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    for _, s in ipairs({ b.label, b.title, b.desc }) do
        s:SetWidth(224)
        s:SetJustifyH("LEFT")
        s:SetJustifyV("TOP")
    end
    b.desc:SetTextColor(0.8, 0.8, 0.8)
    b:SetScript("OnClick", function(self, button)
        if not self.key then return end
        if button == "RightButton" and Quests.CanComplete() then
            local e = Quests.Get(self.key)
            if e then StaticPopup_Show("ADB_QUETE_TERMINER", e.title, nil, self.key) end
        elseif button == "LeftButton" and Quests.CanEdit(self.key) then
            QUI.OpenEditor(self.key)
        end
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.key and Quests.Get(self.key)
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(e.title, 1, 0.82, 0)
        if e.desc ~= "" then GameTooltip:AddLine(e.desc, 1, 1, 1, true) end
        if Quests.CanEdit(self.key) then GameTooltip:AddLine("Clic gauche : modifier", 0.6, 0.6, 0.6) end
        if Quests.CanComplete() then GameTooltip:AddLine("Clic droit : terminer", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.blocks[i] = b
    return b
end

local FONT_BASE = { label = GameFontNormalSmall, title = GameFontNormal, desc = GameFontHighlightSmall }
function QUI.StyleBlock(b)
    local s = (ADB.db and ADB.db.settings and ADB.db.settings.questFont) or 1
    for k, fo in pairs(FONT_BASE) do
        local file, size, flags = fo:GetFont()
        b[k]:SetFont(file, max(6, floor(size * s + 0.5)), flags)
    end
end

function QUI.Draw()
    local f = ADB.qTracker
    if not f or not ADB.db or not ADB.playerName then return end
    local minimized = ADB.db.questsMinimized and true or false
    f.Min:SetNormalTexture(minimized and "Interface\\Buttons\\UI-PlusButton-Up" or
    "Interface\\Buttons\\UI-MinusButton-Up")
    local list = minimized and {} or Quests.List()
    local y = -32
    for i, it in ipairs(list) do
        local b = GetBlock(f, i)
        QUI.StyleBlock(b)
        b.key = it.key
        local off = 0
        if it.owner then
            b.label:SetText("Aspiration de " .. ADB.Stats.DisplayName(it.owner))
            b.label:SetTextColor(0.5, 0.8, 1)
            b.label:ClearAllPoints()
            b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            b.label:Show()
            off = b.label:GetStringHeight() + 2
            b.title:SetTextColor(0.7, 0.9, 1)
        else
            b.label:Hide()
            b.title:SetTextColor(1, 0.82, 0)
        end
        b.title:SetText(it.entry.title)
        b.title:ClearAllPoints()
        b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -off)
        local th = b.title:GetStringHeight()
        b.desc:SetText(it.entry.desc)
        b.desc:ClearAllPoints()
        b.desc:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(off + th + 2))
        local dh = (it.entry.desc ~= "") and b.desc:GetStringHeight() or 0
        b:SetHeight(off + th + 2 + dh)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
        b:Show()
        y = y - b:GetHeight() - 8
    end
    for i = #list + 1, #f.blocks do
        f.blocks[i].key = nil
        f.blocks[i]:Hide()
    end
    f:SetHeight(minimized and 30 or max(30, -y))
end

local function CreateTracker()
    local f = CreateFrame("Frame", "ADBQuestTracker", UIParent)
    f:SetSize(240, 30)
    f:SetFrameStrata("LOW")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint(1)
        ADB.db.questsPos = { p, rp, floor(x + 0.5), floor(y + 0.5) }
    end)
    local pos = ADB.db.questsPos
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
        and tonumber(pos[3]) and tonumber(pos[4]) then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -240)
    end
    f.blocks = {}
    ADB.qTracker = f
    f.Background = f:CreateTexture(nil, "BACKGROUND")
    f.Background:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.Background:SetSize(240, 30)
    f.Background:SetAtlas("Objective-Header") -- native ObjectiveTracker atlas
    f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Title:SetPoint("LEFT", f, "TOPLEFT", 12, -15)
    f.Title:SetText("Quêtes et Aspirations")
    f.Min = CreateFrame("Button", nil, f)
    f.Min:SetSize(16, 16)
    f.Min:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    f.Min:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    f.Min:SetScript("OnClick", function() Quests.ToggleMinimized() end)
    f.Edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.Edit:SetSize(44, 16)
    f.Edit:SetPoint("RIGHT", f.Min, "LEFT", -4, 0)
    f.Edit:SetText("Éditer")
    f.Edit:SetScript("OnClick", function() QUI.OpenEditor() end)
    QUI.Draw()
end

function QUI.Create() CreateTracker() end

------------------------------------------------------------------------------
-- Editor (GM: 5 slots · player: 1 aspiration · solo: both)
------------------------------------------------------------------------------
local function LoadEditor()
    local f = ADB.qEditor
    local key = f.key
    local e = Quests.Get(key)
    f.Title:SetText(e and e.title or "")
    f.Desc:SetText(e and e.desc or "")
    local isGM = ADB.IsGM()
    local questsOk = isGM or not IsInGroup()
    for i, b in ipairs(f.slots) do
        local k = (i < 6) and ("G" .. i) or ("P:" .. ADB.playerName)
        b:SetShown((i < 6 and questsOk) or (i == 6 and not isGM))
        b:SetEnabled(k ~= key)
    end
    local owner = key:match("^P:(.+)$")
    f.Info:SetText(owner and ("Aspiration de " .. ADB.Stats.DisplayName(owner)) or ("Quête n°" .. key:sub(2)))
    f.Save:SetEnabled(Quests.CanEdit(key))
    f.Delete:SetEnabled(Quests.CanEdit(key) and e ~= nil)
    f.Complete:SetShown(Quests.CanComplete())
    f.Complete:SetEnabled(e ~= nil)
end

function QUI.RefreshEditor() if ADB.qEditor then LoadEditor() end end

function QUI.OpenEditor(key)
    local f = ADB.qEditor
    if not f then
        f = UI.BaseWindow("ADBQuestEditor", 340, 292, "Quêtes & Aspiration")
        ADB.qEditor = f
        f:SetPoint("CENTER", -250, 80)
        tinsert(UISpecialFrames, "ADBQuestEditor")
        f.slots = {}
        for i = 1, 6 do
            local k = (i < 6) and ("G" .. i) or nil
            f.slots[i] = UI.Button(f, i < 6 and tostring(i) or "Asp.", 16 + (i - 1) * 44, -34, i < 6 and 40 or 52,
                function() QUI.OpenEditor(k or ("P:" .. ADB.playerName)) end)
        end
        f.Info = UI.Label(f, "", 16, -64, "GameFontNormalSmall")
        UI.Label(f, "Titre", 16, -84)
        f.Title = UI.Input(f, 20, -102, 296, Quests.TITLE_MAX)
        UI.Label(f, "Description", 16, -130)
        f.Desc = UI.MultilineInput(f, 16, -148, 300, 96, Quests.DESC_MAX)
        f.Save = UI.Button(f, "Enregistrer", 16, -254, 95, function()
            Quests.Save(f.key, f.Title:GetText(), f.Desc:GetText())
            LoadEditor()
        end)
        f.Delete = UI.Button(f, "Supprimer", 116, -254, 95, function()
            Quests.Delete(f.key)
            LoadEditor()
        end)
        f.Complete = UI.Button(f, "Terminer", 216, -254, 100, function()
            local e = Quests.Get(f.key)
            if e then StaticPopup_Show("ADB_QUETE_TERMINER", e.title, nil, f.key) end
        end)
    end
    if not key or not (Quests.CanEdit(key) or Quests.CanComplete()) then
        key = (ADB.IsGM() or not IsInGroup()) and "G1" or ("P:" .. ADB.playerName)
    end
    f.key = key
    f:Show()
    LoadEditor()
end
