-- UI/CombatUI.lua : combat banners, turn indicator, GM combat panel, player "end turn" panel, HP/shield input.
local ADB, UI = ADB, ADB.UI
local format = string.format

local CUI = {}
ADB.CombatUI = CUI

------------------------------------------------------------------------------
-- Banner
------------------------------------------------------------------------------
function CUI.Banner(text)
    local b = ADB.banner
    if not b then
        b = CreateFrame("Frame", "ADBBanner", UIParent)
        b:SetFrameStrata("FULLSCREEN_DIALOG")
        b:SetSize(1200, 80)
        b:SetPoint("TOP", UIParent, "TOP", 0, -180)
        b.t = b:CreateFontString(nil, "OVERLAY")
        b.t:SetFont(STANDARD_TEXT_FONT, 44, "THICKOUTLINE")
        b.t:SetPoint("CENTER")
        b.t:SetTextColor(1, 0.82, 0.3)
        b:SetScript("OnUpdate", function(s, elapsed)
            s.e = s.e + elapsed
            if s.e > 3.5 then s:Hide() elseif s.e > 2.5 then s:SetAlpha(3.5 - s.e) end
        end)
        ADB.banner = b
    end
    b.t:SetText(text)
    b.e = 0
    b:SetAlpha(1)
    b:Show()
end

------------------------------------------------------------------------------
-- Turn indicator
------------------------------------------------------------------------------
local TURN_NAME = { STARTING = "Préparation", PLAYER_TURN = "Joueurs", ALLY_TURN = "Alliés", ENEMY_TURN = "Ennemis" }
local TURN_COLOR = {
    STARTING = { 1, 0.82, 0.3 },
    PLAYER_TURN = { 0.4, 1, 0.4 },
    ALLY_TURN = { 0.4, 0.7, 1 },
    ENEMY_TURN = { 1, 0.4, 0.3 },
}
local GM_BUTTON_TEXT = {
    STARTING = "Passer la préparation",
    PLAYER_TURN = "Forcer la fin du tour",
    ALLY_TURN = "Fin du Tour Allié",
    ENEMY_TURN = "Fin du Tour Ennemi"
}

local function UpdateTurnIndicator()
    local t = ADB.turnIndicator
    if not t then
        t = CreateFrame("Frame", "ADBTurnIndicator", UIParent)
        t:SetFrameStrata("HIGH")
        t:SetSize(600, 30)
        t:SetPoint("TOP", UIParent, "TOP", 0, -50)
        t.t = t:CreateFontString(nil, "OVERLAY")
        t.t:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
        t.t:SetPoint("CENTER")
        t:Hide()
        ADB.turnIndicator = t
    end
    local phase = ADB.phase
    local name = TURN_NAME[phase]
    if phase == "IDLE" or not name then
        t:Hide()
        return
    end
    local text = "Tour de : " .. name
    if phase == "PLAYER_TURN" and ADB.turnPassed and not ADB.IsGM() then
        text = text .. " |cff999999(vous avez passé)|r"
    end
    local c = TURN_COLOR[phase]
    t.t:SetTextColor(c[1], c[2], c[3])
    t.t:SetText(text)
    t:Show()
end

function CUI.Refresh()
    UpdateTurnIndicator()
    local d, p = ADB.cbDM, ADB.cbJ
    if not d then return end
    local phase, isGM = ADB.phase, ADB.IsGM()
    d:SetShown(isGM and phase ~= "IDLE")
    p:SetShown((not isGM) and phase == "PLAYER_TURN")
    if isGM and phase ~= "IDLE" then
        local extra = ""
        if phase == "PLAYER_TURN" then
            local active, done = ADB.Combat.ActivePlayers(), 0
            for _, n in ipairs(active) do
                if ADB.finishedPlayers[n] then done = done + 1 end
            end
            extra = format(" (%d/%d)", done, #active)
        end
        d.State:SetText(ADB.PHASE_BANNER[phase] .. extra)
        d.Next:SetShown(GM_BUTTON_TEXT[phase] ~= nil)
        if GM_BUTTON_TEXT[phase] then d.Next:SetText(GM_BUTTON_TEXT[phase]) end
    end
end

function CUI.SetEndTurnEnabled(on)
    if ADB.cbJ then ADB.cbJ.Btn:SetEnabled(on) end
end

-- Movement counter under the "end turn" button (called by Measure's ticker).
function CUI.SetMovementText(text)
    local cb = ADB.cbJ
    if not (cb and cb:IsShown()) then return end
    if not cb.Move then
        cb:SetHeight(64)
        cb.Move = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.Move:SetPoint("BOTTOM", 0, 8)
    end
    cb.Move:SetText(text)
end

------------------------------------------------------------------------------
-- HP / shield input window
------------------------------------------------------------------------------
function CUI.OpenHpInput(name, npcId)
    local f = ADB.pvFrame
    local d
    if npcId then d = ADB.NPC.FindById(ADB.db.npcs, npcId) elseif name then d = ADB.Stats.GetBlock(name) end
    if not d then return end
    f.name, f.npcId = name, npcId
    f.Title:SetText(npcId and ADB.NPC.DisplayName(d) or ADB.Stats.DisplayName(name))
    f.Hp:SetText(d.hp)
    f.Shield:SetText(d.shield or 0)
    f:Show()
    f.Hp:SetFocus()
    f.Hp:HighlightText()
end

function CUI.ValidateHpInput()
    local f = ADB.pvFrame
    local hp, shield = tonumber(f.Hp:GetText()), tonumber(f.Shield:GetText())
    if f.npcId then
        if ADB.IsGM() then
            if shield then ADB.NPC.ApplyValue(f.npcId, "shield", shield) end
            if hp then ADB.NPC.ApplyValue(f.npcId, "hp", hp, true) end
        end
    elseif f.name and ADB.Group.CanEdit(f.name) then
        if shield then ADB.Stats.ApplyValue(f.name, "shield", shield) end
        if hp then ADB.Stats.ApplyValue(f.name, "hp", hp, nil, true) end
    end
    f:Hide()
end

------------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------------
function CUI.Create()
    local d = UI.BaseWindow("ADBCombatDMFrame", 220, 124, "Combat (MJ)")
    ADB.cbDM = d
    d:SetPoint("TOP", UIParent, "TOP", 0, -260)
    d.State = UI.Label(d, "", 16, -34)
    d.State:SetWidth(190)
    d.Next = UI.Button(d, "", 20, -62, 180, function() ADB.Combat.GmEndTurn() end)
    d.End = UI.Button(d, "Fin du Combat", 20, -90, 180, function() ADB.Combat.End() end)

    local p = CreateFrame("Frame", "ADBCombatPlayerFrame", UIParent, "BackdropTemplate")
    ADB.cbJ = p
    p:SetSize(150, 44)
    p:SetFrameStrata("MEDIUM")
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    local function DragStart() p:StartMoving() end
    local function DragStop()
        p:StopMovingOrSizing()
        local pt, _, rp, x, y = p:GetPoint(1)
        ADB.db.cbPos = { pt, rp, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
    p:SetScript("OnDragStart", DragStart)
    p:SetScript("OnDragStop", DragStop)
    local pos = ADB.db.cbPos
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
        and tonumber(pos[3]) and tonumber(pos[4]) then
        p:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        p:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -12, 110)
    end
    UI.ApplyBackdrop(p)
    p.Btn = UI.Button(p, "Fin de Tour", 12, -11, 126, function() ADB.Combat.PlayerEndTurn() end)
    p.Btn:RegisterForDrag("LeftButton")
    p.Btn:SetScript("OnDragStart", DragStart)
    p.Btn:SetScript("OnDragStop", DragStop)
    p:Hide()

    local g = UI.BaseWindow("ADBPVFrame", 240, 130, "PV / Bouclier")
    ADB.pvFrame = g
    g:SetPoint("CENTER", 0, 100)
    g.Title = UI.Label(g, "", 16, -34, "GameFontNormal")
    UI.Label(g, "PV", 16, -60)
    g.Hp = UI.Input(g, 76, -57, 60, 4, true)
    UI.Label(g, "Bouclier", 16, -86)
    g.Shield = UI.Input(g, 76, -83, 60, 3, true)
    g.Hp:SetScript("OnEnterPressed", CUI.ValidateHpInput)
    g.Shield:SetScript("OnEnterPressed", CUI.ValidateHpInput)
    UI.Button(g, "OK", 150, -70, 70, CUI.ValidateHpInput)
    tinsert(UISpecialFrames, "ADBPVFrame")
end
