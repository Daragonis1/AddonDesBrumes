local ADB = ADB
local floor, abs = math.floor, math.abs
local format = string.format
local Encoder, Decoder, Net, UI = ADB.Encoder, ADB.Decoder, ADB.NettoyerNom, ADB.UI
ADB.CMD_EXT.CR, ADB.CMD_EXT.TY = true, true

------------------------------------------------------------------------------
-- Annonces de critiques
------------------------------------------------------------------------------
local function TxtCrit(t) return t == "1" and "Réussite critique" or "Échec critique" end

local oJet = ADB.Jet
ADB.Jet = function(...)
    local r, lib, c, m, e, ce = oJet(...)
    local t = ce and "0" or ((m > 1 and not e) and "1" or nil)
    if t then
        local nom = ADB.NomAffiche(ADB.playerName)
        ADB.Banniere(format("%s : %s !", nom, TxtCrit(t)))
        ADB.Envoyer(format("CR;%s;%s", t, Encoder(nom)))
    end
    return r, lib, c, m, e, ce
end

------------------------------------------------------------------------------
-- "est en train d'écrire"
------------------------------------------------------------------------------
local ty, typing, last = {}, false, 0

local function Envoi(on)
    if ADB.EstMJ() or not IsInGroup() then return end
    ADB.Envoyer("TY;" .. (on and 1 or 0))
end

local function MajTy()
    local f = ADB.tyFrame
    if not f then return end
    local now, g, noms = GetTime(), ADB.NomsGroupe(), {}
    for n, e in pairs(ty) do
        if e < now or not g[n] or n == ADB.playerName then ty[n] = nil else noms[#noms + 1] = ADB.NomAffiche(n) end
    end
    if #noms == 0 then
        f:Hide()
        return
    end
    table.sort(noms)
    f.T:SetText(#noms == 1 and (noms[1] .. " est en train d'écrire.")
        or (table.concat(noms, ", ", 1, #noms - 1) .. " et " .. noms[#noms] .. " sont en train d'écrire."))
    f:SetWidth(f.T:GetStringWidth() + 20)
    f:Show()
end

local function CreerTy()
    local f = CreateFrame("Frame", "ADBTypingFrame", UIParent, "BackdropTemplate")
    ADB.tyFrame = f
    f:SetSize(200, 22)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint(1)
        ADB.db.tyPos = { p, rp, floor(x + 0.5), floor(y + 0.5) }
    end)
    ADB.AppliquerFond(f)
    f.T = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.T:SetPoint("CENTER")
    local pos = ADB.db.tyPos
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
        and tonumber(pos[3]) and tonumber(pos[4]) then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
    end
    f:Hide()
    local function Debut() if not typing then
            typing, last = true, GetTime()
            Envoi(true)
        end end
    local function Fin() if typing then
            typing = false
            Envoi(false)
        end end
    for i = 1, NUM_CHAT_WINDOWS do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:HookScript("OnEditFocusGained", Debut)
            eb:HookScript("OnEditFocusLost", Fin)
            eb:HookScript("OnShow", Debut)
            eb:HookScript("OnHide", Fin)
        end
    end
    C_Timer.NewTicker(1, function()
        if typing and GetTime() - last > 8 then
            last = GetTime()
            Envoi(true)
        end
        MajTy()
    end)
end

------------------------------------------------------------------------------
-- Réception CR / TY
------------------------------------------------------------------------------
local oExt = ADB.RecevoirExt
ADB.RecevoirExt = function(cmd, nom, message)
    if cmd == "CR" then
        if not (ADB.roster[nom] or ADB.EstNomMJ(nom)) then return end
        local p = { strsplit(";", message) }
        local n = Net(Decoder(p[3] or "")):sub(1, 40)
        if n ~= "" then ADB.Banniere(format("%s : %s !", n, TxtCrit(p[2]))) end
    elseif cmd == "TY" then
        if not ADB.NomsGroupe()[nom] or ADB.EstNomMJ(nom) then return end
        local p = { strsplit(";", message) }
        ty[nom] = (p[2] == "1") and (GetTime() + 20) or nil
        MajTy()
    else
        return oExt(cmd, nom, message)
    end
end

local oLogin = ADB.Evenements.PLAYER_LOGIN
ADB.Evenements.PLAYER_LOGIN = function(...)
    oLogin(...)
    CreerTy()
end

------------------------------------------------------------------------------
-- MJ : Action PNJ
------------------------------------------------------------------------------
function ADB.ActionPNJ()
    if not ADB.EstMJ() then return end
    local d = ADB.cbDM
    local att = Net(d.Att:GetText())
    local dmg = floor(tonumber(d.Deg:GetText()) or 0)
    local prec = tonumber(d.Prec:GetText())
    local desc = Net(d.Desc:GetText())
    if att == "" then
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
    local cible = ADB.TalCibleNom()
    local head = att .. " " .. (desc ~= "" and desc or ((dmg < 0 and "soigne " or "attaque ") .. cible))
    local roll, ok, mult = nil, true, 1
    if prec and prec >= 1 and prec <= 99 then
        local r = math.random(1, 100)
        local t
        if r <= 5 then
            t, mult = "c'est une réussite critique!", 2
        elseif r >= 96 then
            t, ok = "c'est un échec critique!", false
        elseif r <= prec then
            t = "c'est une réussite,"
        else
            t, ok = "c'est un échec,", false
        end
        roll = format(", il fait %d, %s", r, t)
    end
    local v = abs(dmg) * mult
    local cons
    if not ok then
        cons = dmg < 0 and (cible .. " ne reçoit aucun soin.") or (cible .. " est indemne.")
    elseif dmg > 0 then
        cons = format("%s subit %d point%s de dégâts.", cible, v, v > 1 and "s" or "")
    else
        cons = format("%s récupère %d point%s de vie.", cible, v, v > 1 and "s" or "")
    end
    ADB.AnnoncerChat(head .. (roll and (roll .. " ") or ", ") .. cons)
    if ok then
        local e = ADB.EntreeUnite("target")
        if e then ADB.EnvoyerEffets({ e }, dmg > 0 and 1 or 2, v) end
    end
end

hooksecurefunc(ADB, "CreerCombat", function()
    local d = ADB.cbDM
    d:SetHeight(262)
    UI.Bouton(d, "Action PNJ", 20, -118, 180, ADB.ActionPNJ)
    UI.Etiq(d, "Attaquant", 16, -150, "GameFontNormalSmall")
    d.Att = UI.Saisie(d, 88, -147, 116, 30)
    UI.Etiq(d, "Précision", 16, -176, "GameFontNormalSmall")
    d.Prec = UI.Saisie(d, 88, -173, 50, 3, true)
    UI.Etiq(d, "Dégâts", 16, -202, "GameFontNormalSmall")
    d.Deg = UI.Saisie(d, 88, -199, 50, 5)
    UI.Etiq(d, "Description", 16, -228, "GameFontNormalSmall")
    d.Desc = UI.Saisie(d, 88, -225, 116, 80)
end)

------------------------------------------------------------------------------
-- MJ : fiche du secondaire (depuis la fiche du joueur)
------------------------------------------------------------------------------
local function TexteAlt(pn)
    local lvl, xp = pn.level or 1, pn.xp or 0
    local fo, ag, it = pn.force or 0, pn.agilite or 0, pn.intelligence or 0
    return format("|cff9d6bff%s|r\n\n|cffffd100Race|r : %s\n|cffffd100Classe|r : %s\n" ..
        "|cffffd100Niveau|r : %d    |cffffd100XP|r : %s\n|cffffd100Or|r : %s\n\n" ..
        "Force : %d   Agilité : %d   Intelligence : %d\n\n|cffff5050PV|r : %d / %d\n|cff5080ffPM|r : %d / %d\n\n" ..
        "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f",
        ADB.PNJNom(pn), pn.race or "?", pn.classe or "?", lvl,
        lvl >= ADB.NIVEAU_MAX and (xp .. " (max)") or (xp .. " / " .. ADB.XP_SEUILS[lvl + 1]),
        ADB.FormatOr(pn.pc or 0), fo, ag, it, pn.pv, pn.pvMax, pn.pm, pn.pmMax, fo / 40, ag / 40, it / 40)
end

local function MajVueAlt()
    local f = ADB.altVueFiche
    if not (f and f:IsShown()) then return end
    local pn = ADB.AltDe(f.nom)
    if pn then f.Body:SetText(TexteAlt(pn)) else f:Hide() end
end

function ADB.VueFicheAlt(nom)
    if not (ADB.EstMJ() and nom and ADB.AltDe(nom)) then return end
    local f = ADB.altVueFiche
    if not f then
        f = UI.FenetreBase("ADBAltVueFrame", 300, 420, "Personnage secondaire")
        ADB.altVueFiche = f
        f:SetPoint("CENTER", 300, 40)
        tinsert(UISpecialFrames, "ADBAltVueFrame")
        f.Body = UI.Etiq(f, "", 20, -40)
        f.Body:SetWidth(260)
        f.Body:SetJustifyV("TOP")
        f.Body:SetSpacing(4)
        UI.Bouton(f, "Inventaire", 90, -382, 120, function() ADB.VueDemander(f.nom, true) end)
    end
    f.nom = nom
    f:Show()
    MajVueAlt()
end

hooksecurefunc(ADB, "RafraichirNPC", MajVueAlt)

local function MajBtnAlt()
    local f = ADBFicheFrame
    if not f then return end
    if not f.BtnAlt then
        f:SetHeight(360)
        f.BtnAlt = UI.Bouton(f, "Secondaire", 90, -326, 100, function() ADB.VueFicheAlt(f.nomAffiche) end)
    end
    f.BtnAlt:SetShown(ADB.EstMJ() and f.nomAffiche ~= nil and ADB.AltDe(f.nomAffiche) ~= nil)
end
hooksecurefunc(ADB, "OuvrirFiche", MajBtnAlt)
hooksecurefunc(ADB, "RafraichirFiche", MajBtnAlt)
hooksecurefunc(ADB, "CreerFenetreItem", function()
    local f = ADB.itemFrame
    f:SetHeight(570)
    UI.Etiq(f, "Tags (ex: dreadsteed, AddClassMage)", 20, -512, "GameFontNormalSmall")
    f.TagsEdit = UI.Saisie(f, 24, -530, 268, 600)
end)