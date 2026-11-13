-- UI/GmTools.lua : GM tools: XP window (ADBMJFrame), rest window, NPC creation, "Action PNJ", alt sheet viewer,
-- loot launcher. Frames themselves are declared in Templates.xml; extra widgets are added in GmTools.Setup.
local ADB, UI = ADB, ADB.UI
local floor, abs = math.floor, math.abs
local format = string.format
local Clamp, CleanName = ADB.Clamp, ADB.CleanName

local GT = {}
ADB.GmTools = GT

------------------------------------------------------------------------------
-- XP
------------------------------------------------------------------------------
function GT.OpenXp()
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ (chef de groupe) peut utiliser cet outil.")
        return
    end
    ADBMJFrame:Show()
end

local function ReadXp()
    local v = tonumber(ADBMJFrame.XPEdit:GetText())
    if not v or floor(v) == 0 then
        ADB.Print("Montant d'XP invalide (1 à " .. ADB.XP_SEND_MAX .. ").")
        return nil
    end
    return Clamp(floor(v), -ADB.XP_SEND_MAX, ADB.XP_SEND_MAX)
end

function GT.XpTarget()
    if not ADB.IsGM() then return end
    if not UnitExists("target") or not UnitIsPlayer("target") then
        ADB.Print("Ciblez d'abord un joueur.")
        return
    end
    local m = ReadXp()
    if not m then return end
    local name = UnitName("target")
    if name == ADB.playerName then
        ADB.Stats.ReceiveXP(m)
    elseif ADB.roster[name] then
        ADB.Net.Send(format("XP;%s;%d", name, m))
        ADB.Print(format("%d XP envoyés à %s.", m, ADB.Stats.DisplayName(name)))
    else
        ADB.Print(name .. " n'a pas l'addon (aucune fiche reçue).")
    end
end

function GT.XpGroup()
    if not ADB.IsGM() then return end
    local m = ReadXp()
    if not m then return end
    ADB.Net.Send(format("XPALL;%d", m))
    ADB.Print(format("%d XP envoyés au groupe.", m))
end

------------------------------------------------------------------------------
-- Rest
------------------------------------------------------------------------------
function GT.RestPercent()
    local f = ADBRestFrame
    local n = 0
    for _, cb in ipairs({ f.Securise, f.Confortable }) do
        if cb:GetChecked() then n = n + 1 end
    end
    return 10 + 10 * n
end

function GT.RefreshRest()
    local f = ADBRestFrame
    if not f then return end
    f.Pct:SetText(format("Restauration : |cffffd100%d%%|r (+%d%% si Ration)", GT.RestPercent(), ADB.RATION_BONUS))
end

function GT.InitRest()
    ADBRestSecuriseText:SetText("Lieu sécurisé ?")
    ADBRestConfortableText:SetText("Lieu confortable ?")
    GT.RefreshRest()
end

function GT.OpenRest()
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ (chef de groupe) peut lancer un repos.")
        return
    end
    ADBRestFrame:Show()
    GT.RefreshRest()
end

function GT.LaunchRest()
    if not ADB.IsGM() then return end
    local pct = GT.RestPercent()
    ADB.Net.Send(format("REST;%d", pct))
    for _, p in ipairs(ADB.db.npcs) do
        if p.owner then
            ADB.NPC.ApplyValue(p.id, "hp", math.min(p.maxHp, p.hp + floor(p.maxHp * pct / 100 + 0.5)))
            ADB.NPC.ApplyValue(p.id, "mp", math.min(p.maxMp, p.mp + floor(p.maxMp * pct / 100 + 0.5)))
        end
    end
    ADB.Print(format("Repos lancé : %d%% des PV et PM restaurés (+%d%% avec Ration).", pct, ADB.RATION_BONUS))
    ADBRestFrame:Hide()
end

------------------------------------------------------------------------------
-- NPC creation
------------------------------------------------------------------------------
function GT.OpenNpcCreate()
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ (chef de groupe) peut créer des PNJ.")
        return
    end
    ADBNpcCreateFrame:Show()
end

function GT.InitNpcCreate()
    local f = ADBNpcCreateFrame
    f.NameEdit:SetText("")
    f.HpEdit:SetText("10")
    f.MpEdit:SetText("10")
    ADBNpcAllyCheckText:SetText("PNJ allié")
    f.AllyCheck:SetChecked(false)
    f.NameEdit:SetFocus()
    if not f.RpEdit then
        f:SetHeight(240)
        UI.Label(f, "Nom RP", 20, -172)
        f.RpEdit = UI.Input(f, 100, -169, 170, 40)
        UI.Label(f, "Nom = nom réel en jeu (ciblage)", 20, -196, "GameFontDisableSmall")
    end
    f.RpEdit:SetText("")
end

function GT.ValidateNpcCreate()
    local f = ADBNpcCreateFrame
    local name = CleanName(f.NameEdit:GetText())
    if name == "" then name = "PNJ" end
    local hp = tonumber(f.HpEdit:GetText())
    local mp = tonumber(f.MpEdit:GetText()) or 0
    if not hp or hp < 1 then
        ADB.Print("PV max invalide (1 à " .. ADB.NPC_STAT_MAX .. ").")
        return
    end
    local rp = f.RpEdit and CleanName(f.RpEdit:GetText()):sub(1, 40) or ""
    if ADB.NPC.Create(name, hp, mp, f.AllyCheck:GetChecked(), rp) then f:Hide() end
end

------------------------------------------------------------------------------
-- Combat panel : frise, combattants de la phase, actions PNJ enregistrées
------------------------------------------------------------------------------
local ROWS, MAX_ACTIONS = 8, 8
local ROSTER_Y, ACTIONS_Y = -114, -404
local GREY = { 0.2, 0.2, 0.2, 0.8 }
local ROSTER_TITLE = {
    PLAYER_TURN = "Joueurs (vert : n'a pas joué)",
    ALLY_TURN = "Alliés (cliquer pour jouer)",
    ENEMY_TURN = "Ennemis (cliquer pour jouer)"
}

function GT.SelectActor(key)
    if not (ADB.IsGM() and key) or (ADB.phase ~= "ALLY_TURN" and ADB.phase ~= "ENEMY_TURN") then return end
    for _, r in ipairs(ADB.Combat.Roster(ADB.phase)) do
        if r.key == key and not r.done then
            ADB.cbSelected = (ADB.cbSelected ~= key) and key or nil
            break
        end
    end
    ADB.CombatUI.Refresh()
end

function GT.AddEnemy()
    if not ADB.IsGM() then return end
    if ADB.phase == "IDLE" then
        ADB.Print("Aucun combat en cours.")
        return
    end
    if not UnitExists("target") then
        ADB.Print("Ciblez d'abord quelqu'un.")
        return
    end
    if UnitIsPlayer("target") then
        ADB.Print("Un joueur ne peut pas être un ennemi.")
        return
    end
    local guid, name = UnitGUID("target"), UnitName("target")
    local p = ADB.NPC.FindByName(name)
    if p and p.ally then
        ADB.Print("Cette cible est déjà un allié.")
        return
    end
    for _, e in ipairs(ADB.combatEnemies) do
        if e.guid == guid then
            ADB.Print("Cette cible est déjà un ennemi du combat.")
            return
        end
    end
    if #ADB.combatEnemies >= ADB.NPC_MAX then
        ADB.Print("Nombre maximum d'ennemis atteint.")
        return
    end
    local label = p and ADB.NPC.DisplayName(p) or name
    ADB.combatEnemies[#ADB.combatEnemies + 1] = { key = "E:" .. guid, guid = guid, name = label }
    ADB.Print(label .. " ajouté aux ennemis.")
    ADB.CombatUI.Refresh()
end

function GT.RemoveEnemy(key)
    if not ADB.IsGM() then return end
    for i, e in ipairs(ADB.combatEnemies) do
        if e.key == key then
            tremove(ADB.combatEnemies, i)
            ADB.npcPlayed[key] = nil
            if ADB.cbSelected == key then ADB.cbSelected = nil end
            ADB.CombatUI.Refresh()
            ADB.Combat.CheckPlayersDone()
            return
        end
    end
end

function GT.SaveAction()
    if not ADB.IsGM() then return end
    local d = ADB.cbDM
    local value = floor(tonumber(d.Effect:GetText()) or 0)
    if value == 0 or abs(value) > 1000 then
        ADB.Print("Effet invalide (-1000 à 1000, négatif = soin).")
        return
    end
    local list = ADB.db.npcActions
    if #list >= MAX_ACTIONS then
        ADB.Print("Maximum " .. MAX_ACTIONS .. " actions enregistrées.")
        return
    end
    local acc = tonumber(d.Accuracy:GetText())
    list[#list + 1] = {
        value = value,
        accuracy = (acc and acc >= 1 and acc <= 99) and floor(acc) or nil,
        desc = CleanName(d.Desc:GetText()):sub(1, 80)
    }
    d.Desc:SetText("")
    GT.RefreshCombat()
end

function GT.RemoveAction(i)
    if not ADB.IsGM() then return end
    tremove(ADB.db.npcActions, i)
    GT.RefreshCombat()
end

-- Lance l'action enregistrée i avec le PNJ sélectionné sur la cible actuelle.
function GT.RunAction(i)
    if not ADB.IsGM() then return end
    local a, key, actor = ADB.db.npcActions[i], ADB.cbSelected, nil
    for _, r in ipairs(ADB.Combat.Roster(ADB.phase)) do
        if r.key == key and not r.done then actor = r end
    end
    if not (a and actor) then
        ADB.Print("Sélectionnez d'abord un PNJ dont c'est le tour.")
        return
    end
    if not UnitExists("target") then
        ADB.Print("Ciblez d'abord quelqu'un.")
        return
    end
    local target = ADB.Talents.TargetName()
    local dmg = a.value
    local head = actor.name .. " " .. (a.desc ~= "" and a.desc or ((dmg < 0 and "soigne " or "attaque ") .. target))
    local rollText, ok, mult = nil, true, 1
    if a.accuracy then
        local r = math.random(1, 100)
        local t
        if r <= 5 then
            t, mult = "c'est une réussite critique!", 2
        elseif r >= 96 then
            t, ok = "c'est un échec critique!", false
        elseif r <= a.accuracy then
            t = "c'est une réussite,"
        else
            t, ok = "c'est un échec,", false
        end
        rollText = format(", il fait %d, %s", r, t)
    end
    local v = abs(dmg) * mult
    local outcome
    if not ok then
        outcome = dmg < 0 and (target .. " ne reçoit aucun soin.") or (target .. " est indemne.")
    elseif dmg > 0 then
        outcome = format("%s subit %d point%s de dégâts.", target, v, v > 1 and "s" or "")
    else
        outcome = format("%s récupère %d point%s de vie.", target, v, v > 1 and "s" or "")
    end
    ADB.Net.Announce(head .. (rollText and (rollText .. " ") or ", ") .. outcome)
    if ok then
        local e = ADB.Measure.UnitEntry("target")
        if e then ADB.Measure.SendEffects({ e }, dmg > 0 and 1 or 2, v) end
    end
    ADB.npcPlayed[key], ADB.cbSelected = true, nil
    ADB.CombatUI.Refresh()
    ADB.Combat.CheckPlayersDone()
end

function GT.RefreshCombat()
    local d = ADB.cbDM
    if not (d and d.Rows and ADB.IsGM()) then return end
    local phase = ADB.phase
    for _, f in ipairs(d.Phases) do
        local on = f.phase == phase
        f.bg:SetColorTexture(unpack(on and f.color or GREY))
        local c = on and 1 or 0.5
        f.text:SetTextColor(c, c, c)
    end
    d.RosterTitle:SetText(ROSTER_TITLE[phase] or "")
    local list = ADB.Combat.Roster(phase)
    for i, b in ipairs(d.Rows) do
        local r = list[i]
        if r then
            local sel = ADB.cbSelected == r.key
            b.key = r.key
            b.bg:SetColorTexture(sel and 0.35 or 0, sel and 0.28 or 0, sel and 0.05 or 0, sel and 0.9 or 0.35)
            b.text:SetText((r.done and "|cff808080" or "|cff40ff40") .. r.name .. "|r")
            b:Show()
            b.del:SetShown(phase == "ENEMY_TURN")
        else
            b.key = nil
            b:Hide()
            b.del:Hide()
        end
    end
    local acts = ADB.db.npcActions
    for i, b in ipairs(d.ActRows) do
        local a = acts[i]
        b:SetShown(a ~= nil)
        b.del:SetShown(a ~= nil)
        if a then
            b.text:SetText(format("%s %d  |  Préc. %s", a.value < 0 and "Soin" or "Dégâts", abs(a.value),
                a.accuracy or "-"))
        end
    end
end

hooksecurefunc(ADB.CombatUI, "Refresh", function() GT.RefreshCombat() end)

local function MakeRow(parent, y, onClick, onDel)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(242, 20)
    b:SetPoint("TOPLEFT", 16, y)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.35)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    b.del = UI.Button(parent, "X", 262, y, 24, function() onDel(b) end)
    b.del:SetHeight(20)
    b:Hide()
    b.del:Hide()
    return b
end

function GT.SetupCombatPanel()
    local cb = ADB.cbDM
    cb:SetSize(300, 580)
    cb:ClearAllPoints()
    cb:SetPoint("TOP", UIParent, "TOP", 0, -100)

    -- frise Joueurs > Alliés > Ennemis
    cb.Phases = {}
    local FR = { { "PLAYER_TURN", "Joueurs", { 0.15, 0.5, 0.15, 0.9 } },
        { "ALLY_TURN",   "Alliés",  { 0.15, 0.35, 0.65, 0.9 } },
        { "ENEMY_TURN",  "Ennemis", { 0.65, 0.2, 0.15, 0.9 } } }
    for i, p in ipairs(FR) do
        local f = CreateFrame("Frame", nil, cb)
        f:SetSize(80, 18)
        f:SetPoint("TOPLEFT", 16 + (i - 1) * 92, -32)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("CENTER")
        f.text:SetText(p[2])
        f.phase, f.color = p[1], p[3]
        cb.Phases[i] = f
        if i < 3 then
            local a = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            a:SetPoint("TOPLEFT", 16 + (i - 1) * 92 + 83, -35)
            a:SetText(">")
        end
    end

    cb.State:ClearAllPoints()
    cb.State:SetPoint("TOPLEFT", 16, -56)
    cb.State:SetWidth(268)
    cb.Next:ClearAllPoints()
    cb.Next:SetPoint("TOPLEFT", 16, -72)
    cb.Next:SetWidth(134)
    cb.End:ClearAllPoints()
    cb.End:SetPoint("TOPLEFT", 154, -72)
    cb.End:SetWidth(134)

    -- combattants de la phase
    cb.RosterTitle = UI.Label(cb, "", 16, -100, "GameFontNormalSmall")
    cb.Rows = {}
    for i = 1, ROWS do
        cb.Rows[i] = MakeRow(cb, ROSTER_Y - (i - 1) * 20, function(self) GT.SelectActor(self.key) end,
            function(b) GT.RemoveEnemy(b.key) end)
    end
    UI.Button(cb, "Ajouter la cible en ennemi", 16, ROSTER_Y - ROWS * 20 - 4, 268, GT.AddEnemy)

    -- création d'action
    UI.Label(cb, "Actions PNJ", 16, -306, "GameFontNormalSmall")
    UI.Label(cb, "Préc.", 16, -329, "GameFontNormalSmall")
    cb.Accuracy = UI.Input(cb, 56, -326, 40, 2, true)
    UI.Label(cb, "Effet (-1000/1000, <0 soin)", 110, -329, "GameFontNormalSmall")
    cb.Effect = UI.Input(cb, 238, -326, 46, 5)
    UI.Label(cb, "Texte", 16, -353, "GameFontNormalSmall")
    cb.Desc = UI.Input(cb, 56, -350, 228, 80)
    UI.Button(cb, "Enregistrer l'action", 16, -376, 268, GT.SaveAction)

    -- actions enregistrées : clic = lancer sur la cible avec le PNJ sélectionné
    cb.ActRows = {}
    for i = 1, MAX_ACTIONS do
        local b = MakeRow(cb, ACTIONS_Y - (i - 1) * 20, function(self) GT.RunAction(self.index) end,
            function(self) GT.RemoveAction(self.index) end)
        b.index = i
        b:SetScript("OnEnter", function(s)
            local a = ADB.db.npcActions[s.index]
            if a and a.desc ~= "" then
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:AddLine(a.desc, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cb.ActRows[i] = b
    end

    -- validation des actions sauvegardées
    local acts, src = {}, ADB.db.npcActions
    for _, a in ipairs(type(src) == "table" and src or {}) do
        local v = type(a) == "table" and floor(tonumber(a.value) or 0) or 0
        if v ~= 0 and abs(v) <= 1000 and #acts < MAX_ACTIONS then
            local acc = tonumber(a.accuracy)
            acts[#acts + 1] = {
                value = v,
                accuracy = (acc and acc >= 1 and acc <= 99) and floor(acc) or nil,
                desc = CleanName(a.desc or ""):sub(1, 80)
            }
        end
    end
    ADB.db.npcActions = acts
    GT.RefreshCombat()
end

------------------------------------------------------------------------------
-- Alt character sheet (GM view)
------------------------------------------------------------------------------
local function AltSheetText(pn)
    local lvl, xp = pn.level or 1, pn.xp or 0
    local str, agi, int = pn.strength or 0, pn.agility or 0, pn.intellect or 0
    return format("|cff9d6bff%s|r\n\n|cffffd100Race|r : %s\n|cffffd100Classe|r : %s\n" ..
        "|cffffd100Niveau|r : %d    |cffffd100XP|r : %s\n|cffffd100Or|r : %s\n\n" ..
        "Force : %d   Agilité : %d   Intelligence : %d\n\n|cffff5050PV|r : %d / %d\n|cff5080ffPM|r : %d / %d\n\n" ..
        "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f",
        ADB.NPC.DisplayName(pn), pn.race or "?", pn.class or "?", lvl,
        lvl >= ADB.MAX_LEVEL and (xp .. " (max)") or (xp .. " / " .. ADB.XP_THRESHOLDS[lvl + 1]),
        ADB.FormatMoney(pn.copper or 0), str, agi, int, pn.hp, pn.maxHp, pn.mp, pn.maxMp, str / 40, agi / 40, int / 40)
end

local function UpdateAltSheet()
    local f = ADB.altSheetView
    if not (f and f:IsShown()) then return end
    local pn = ADB.Pets.FindAlt(f.player)
    if pn then f.Body:SetText(AltSheetText(pn)) else f:Hide() end
end

function GT.ShowAltSheet(player)
    if not (ADB.IsGM() and player and ADB.Pets.FindAlt(player)) then return end
    local f = ADB.altSheetView
    if not f then
        f = UI.BaseWindow("ADBAltVueFrame", 300, 420, "Personnage secondaire")
        ADB.altSheetView = f
        f:SetPoint("CENTER", 300, 40)
        tinsert(UISpecialFrames, "ADBAltVueFrame")
        f.Body = UI.Label(f, "", 20, -40)
        f.Body:SetWidth(260)
        f.Body:SetJustifyV("TOP")
        f.Body:SetSpacing(4)
        UI.Button(f, "Inventaire", 90, -382, 120, function() ADB.Inspect.Request(f.player, true) end)
    end
    f.player = player
    f:Show()
    UpdateAltSheet()
end

hooksecurefunc(ADB.UnitFrames, "RefreshNpcs", UpdateAltSheet)

local function UpdateAltButton()
    local f = ADBFicheFrame
    if not f then return end
    if not f.BtnAltSheet then
        f:SetHeight(360)
        f.BtnAltSheet = UI.Button(f, "Secondaire", 90, -326, 100, function() GT.ShowAltSheet(f.displayName) end)
    end
    f.BtnAltSheet:SetShown(ADB.IsGM() and f.displayName ~= nil and ADB.Pets.FindAlt(f.displayName) ~= nil)
end
hooksecurefunc(ADB.ConfigWindow, "OpenSheet", UpdateAltButton)
hooksecurefunc(ADB.ConfigWindow, "RefreshSheet", UpdateAltButton)

------------------------------------------------------------------------------
-- Extra widgets (created once at login, after CombatUI.Create)
------------------------------------------------------------------------------
function GT.Setup()
    local mj = ADBMJFrame
    mj:SetHeight(260)
    mj.RestButton:ClearAllPoints()
    mj.RestButton:SetPoint("BOTTOMLEFT", 20, 16)
    mj.RestButton:SetWidth(125)
    UI.Button(mj, "Combat", 155, -130, 125, function() ADB.Combat.Start() end)
    UI.Button(mj, "Quêtes", 20, -130, 125, function() ADB.QuestUI.OpenEditor() end)

    -- loot launcher
    UI.Label(mj, "Objet", 20, -162)
    mj.LootName = UI.Input(mj, 70, -159, 200, 30)
    mj.LootRarity = 3
    local d = CreateFrame("Frame", "ADBLootRarDrop", mj, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", 0, -180)
    UIDropDownMenu_SetWidth(d, 120)
    local function RarityText(i) return "|cff" .. ADB.RARITIES[i].hex .. ADB.RARITIES[i].name .. "|r" end
    UIDropDownMenu_Initialize(d, function(_, level)
        for i = 1, #ADB.RARITIES do
            local info = UIDropDownMenu_CreateInfo()
            info.text = RarityText(i)
            info.checked = (mj.LootRarity == i)
            info.func = function()
                mj.LootRarity = i
                UIDropDownMenu_SetText(d, RarityText(i))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(d, RarityText(mj.LootRarity))
    UI.Button(mj, "Lancer le butin", 150, -184, 130, function()
        ADB.Loot.Start(mj.LootRarity, mj.LootName:GetText())
    end)

    -- ally checkbox of the NPC creation window
    local c = CreateFrame("CheckButton", "ADBNpcAllyCheck", ADBNpcCreateFrame, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", 94, -136)
    ADBNpcCreateFrame.AllyCheck = c

    -- "Action PNJ" panel in the GM combat window
    GT.SetupCombatPanel()
end

ADB.Events.Register("PLAYER_LOGIN", GT.Setup)
