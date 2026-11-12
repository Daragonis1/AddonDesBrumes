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
-- "Action PNJ" (panel added to the GM combat window)
------------------------------------------------------------------------------
function GT.NpcAction()
    if not ADB.IsGM() then return end
    local d = ADB.cbDM
    local attacker = CleanName(d.Attacker:GetText())
    local dmg = floor(tonumber(d.Damage:GetText()) or 0)
    local accuracy = tonumber(d.Accuracy:GetText())
    local desc = CleanName(d.Desc:GetText())
    if attacker == "" then
        ADB.Print("Donnez un attaquant.")
        return
    end
    if dmg == 0 then
        ADB.Print("Dégâts invalides (négatif = soin).")
        return
    end
    if not UnitExists("target") then
        ADB.Print("Ciblez d'abord quelqu'un.")
        return
    end
    local target = ADB.Talents.TargetName()
    local head = attacker .. " " .. (desc ~= "" and desc or ((dmg < 0 and "soigne " or "attaque ") .. target))
    local rollText, ok, mult = nil, true, 1
    if accuracy and accuracy >= 1 and accuracy <= 99 then
        local r = math.random(1, 100)
        local t
        if r <= 5 then t, mult = "c'est une réussite critique!", 2
        elseif r >= 96 then t, ok = "c'est un échec critique!", false
        elseif r <= accuracy then t = "c'est une réussite,"
        else t, ok = "c'est un échec,", false end
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
    local cb = ADB.cbDM
    cb:SetHeight(262)
    UI.Button(cb, "Action PNJ", 20, -118, 180, GT.NpcAction)
    UI.Label(cb, "Attaquant", 16, -150, "GameFontNormalSmall")
    cb.Attacker = UI.Input(cb, 88, -147, 116, 30)
    UI.Label(cb, "Précision", 16, -176, "GameFontNormalSmall")
    cb.Accuracy = UI.Input(cb, 88, -173, 50, 3, true)
    UI.Label(cb, "Dégâts", 16, -202, "GameFontNormalSmall")
    cb.Damage = UI.Input(cb, 88, -199, 50, 5)
    UI.Label(cb, "Description", 16, -228, "GameFontNormalSmall")
    cb.Desc = UI.Input(cb, 88, -225, 116, 80)
end
ADB.Events.Register("PLAYER_LOGIN", GT.Setup)