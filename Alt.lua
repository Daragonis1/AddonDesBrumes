-- Alt.lua : "Personnage joueur" secondaire.
-- Principe : contexte alternatif (ADB.db / playerName / barre / tour) échangé par ADB.Ctx ;
-- tout le code existant (talents, inventaire, effets...) tourne tel quel sur le secondaire.
-- PV/PM/bouclier : synchronisés avec un PNJ allié MJ (owner = "+NomJoueur"), le MJ fait autorité.
local ADB = ADB
local floor, max = math.floor, math.max
local format = string.format
local Borner, Encoder, Decoder, Net, UI = ADB.Borner, ADB.Encoder, ADB.Decoder, ADB.NettoyerNom, ADB.UI
local ALT = ADB.ALT_TYPE
ADB.CMD_EXT.AS, ADB.CMD_EXT.AD = true, true
ADB.talAlt, ADB.invAlt, ADB.popAlt = false, false, {}

------------------------------------------------------------------------------
-- Contexte
------------------------------------------------------------------------------
local rec = { [false] = {}, [true] = {} }
local sig, sigT = nil, 0

local function Swap(to)
    local r = rec[not to]
    r.db, r.name, r.barre, r.tp, r.saut = ADB.db, ADB.playerName, ADB.barre, ADB.tourPasse, ADB.saut
    r = rec[to]
    ADB.db, ADB.playerName, ADB.barre, ADB.tourPasse, ADB.saut = r.db, r.name, r.barre, r.tp, r.saut
    ADB.ctxAlt = to or nil
    if to then ADB.db.talents.arbres = rec[false].db.talents.arbres end
end

function ADB.Ctx(to, fn, ...)
    to = (to and ADB.alt) and true or false
    local cur = ADB.ctxAlt and true or false
    if to == cur then return fn(...) end
    Swap(to)
    local ok, a, b, c = pcall(fn, ...)
    Swap(cur)
    if not ok then error(a, 0) end
    return a, b, c
end

local function AltPNJ() return ADB.mainName and ADB.AltDe(ADB.mainName) end

-- Contexte secondaire : pousse l'état vers le MJ (+ copie locale du PNJ reçu)
local function Envoyer(force)
    local a, d = ADB.db, ADB.GetStatBlock(ADB.playerName)
    local p = AltPNJ()
    if p then p.pv, p.pm, p.sh = a.pv, a.pm, a.sh or 0 end
    if ADB.EstMJ() or not IsInGroup() or not ADB.NomMJ() then return end
    local s = format("%s;%s;%d;%d;%d;%d;%d;%s;%s;%d;%d;%d;%d;%d;%d", Encoder(a.nom), Encoder(a.rp or ""), d.pvMax,
        d.pmMax,
        a.pv, a.pm, a.sh or 0, Encoder(a.race or ""), Encoder(a.classe or ""), a.xp or 0, a.pc or 0,
        d.force, d.agilite, d.intelligence, d.level)
    local t = GetTime()
    if not force and s == sig and (p or t < sigT + 10) then return end
    sig, sigT = s, t
    ADB.Envoyer("AS;" .. s)
end

------------------------------------------------------------------------------
-- Barre d'action (au-dessus du familier s'il existe, sinon de la barre du joueur)
------------------------------------------------------------------------------
local function BarreFix()
    local b = ADB.altBarre
    if not b then return end
    for _, btn in ipairs(b.btns) do
        if not btn.adbW then
            btn.adbW = true
            for _, s in ipairs({ "OnEnter", "OnClick" }) do
                local o = btn:GetScript(s)
                btn:SetScript(s, function(...) return ADB.Ctx(true, o, ...) end)
            end
        end
    end
    local pb = ADB.petBar
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", (pb and pb:IsShown()) and pb or ADB.barreMain, "TOP", 0, 6)
end

------------------------------------------------------------------------------
-- Portrait : cible le PNJ homonyme, portrait dynamique sinon "?"
------------------------------------------------------------------------------
local function MajMinis()
    for parent, m in pairs(ADB.altMinis) do
        if m:IsShown() and m.alt then
            if not InCombatLockdown() then
                local b = m.cible
                if not b then
                    b = CreateFrame("Button", nil, m, "SecureActionButtonTemplate")
                    b:SetSize(44, 44)
                    b:SetPoint("TOPLEFT")
                    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    b:SetAttribute("type1", "macro")
                    b:SetFrameLevel(m:GetFrameLevel() + 10)
                    b:HookScript("OnClick", function(_, btn)
                        if btn == "RightButton" and parent == ADBPlayerFrame then ADB.AltBasculerFiche() end
                    end)
                    m.cible = b
                end
                b:SetAttribute("macrotext1", "/target " .. m.alt)
            end
            local u = ADB.UnitePNJ(m.alt)
            if u then
                SetPortraitTexture(m.Icon, u)
                m.Icon:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
end
hooksecurefunc(ADB, "PetMinis", MajMinis)
C_Timer.NewTicker(1, MajMinis)

------------------------------------------------------------------------------
-- Fiche du secondaire
------------------------------------------------------------------------------
function ADB.AltMajFiche()
    local f = ADB.altFiche
    if not (f and f:IsShown() and ADB.alt) then return end
    ADB.Ctx(true, function()
        local d = ADB.GetStatBlock(ADB.playerName)
        local xp = d.level >= ADB.NIVEAU_MAX and (d.xp .. " (max)") or (d.xp .. " / " .. ADB.XP_SEUILS[d.level + 1])
        f.Body:SetText(format("|cff9d6bff%s|r\n\n|cffffd100Race|r : %s\n|cffffd100Classe|r : %s\n" ..
            "|cffffd100Niveau|r : %d    |cffffd100XP|r : %s\n|cffffd100Or|r : %s\n\n" ..
            "Force : %d   Agilité : %d   Intelligence : %d\n\n|cffff5050PV|r : %d / %d\n|cff5080ffPM|r : %d / %d\n\n" ..
            "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f\n\nPoints de talent restants : %d",
            ADB.NomAffiche(ADB.playerName), d.race, d.classe, d.level, xp, ADB.FormatOr(d.pc),
            d.force, d.agilite, d.intelligence, d.pv, d.pvMax, d.pm, d.pmMax,
            d.multForce, d.multAgi, d.multInt, ADB.TalPointsRestants()))
        if f.Niv and not f.Niv:HasFocus() then f.Niv:SetText(d.level) end
    end)
end

function ADB.AltOuvrirTalents()
    if not ADB.talFrame then ADB.TalCreer() end
    ADB.talAlt, ADB.talVue = true, nil
    ADB.talFrame.sel, ADB.talFrame.mode = nil, nil
    ADB.talFrame:Show()
    ADB.TalDessiner()
end

function ADB.AltOuvrirInv()
    ADB.invAlt, ADB.sel = true, nil
    ADB.invFrame:Show()
    ADB.RafraichirInv()
end

function ADB.AltBasculerFiche()
    if not ADB.alt then
        ADB.Print("Aucun personnage joueur secondaire.")
        return
    end
    local f = ADB.altFiche
    if not f then
        f = UI.FenetreBase("ADBAltFrame", 300, 450, "Personnage secondaire")
        ADB.altFiche = f
        f:SetPoint("CENTER", 260, 40)
        tinsert(UISpecialFrames, "ADBAltFrame")
        f.Body = UI.Etiq(f, "", 20, -40)
        f.Body:SetWidth(260)
        f.Body:SetJustifyV("TOP")
        f.Body:SetSpacing(4)
        UI.Bouton(f, "Talents", 50, -384, 200, ADB.AltOuvrirTalents)
        UI.Bouton(f, "Inventaire", 50, -412, 200, ADB.AltOuvrirInv)
        f:SetHeight(480)
        UI.Etiq(f, "Niveau (1-20)", 20, -446)
        f.Niv = UI.Saisie(f, 120, -443, 40, 2, true)
        UI.Bouton(f, "Appliquer", 170, -443, 100, function() ADB.AltDefinirNiveau(tonumber(f.Niv:GetText())) end)
        f:SetScript("OnShow", function() ADB.AltMajFiche() end)
    end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- Contexte secondaire : après toute modification locale
function ADB.AltApres()
    Envoyer()
    ADB.TalRafraichirBarre()
    BarreFix()
    ADB.AltMajFiche()
    ADB.RafraichirInv()
    ADB.Ctx(false, ADB.PetMinis)
end

------------------------------------------------------------------------------
-- Données
------------------------------------------------------------------------------
local function Valider(s)
    s.race = ADB.RACE_MAP[s.race] and s.race or "Humain"
    s.classe = (ADB.CLASSE_MAP[s.classe] and not ADB.ClasseSpeciale(s.classe)) and s.classe or "Guerrier"
    s.nom, s.rp = Net(s.nom):sub(1, 30), Net(s.rp or ""):sub(1, 40)
    s.xp = max(0, floor(tonumber(s.xp) or 0))
    s.level = ADB.NiveauPourXP(s.xp)
    s.base = type(s.base) == "table" and s.base or { force = 0, agilite = 0, intelligence = 0 }
    s.pc = Borner(floor(tonumber(s.pc) or 0), 0, ADB.OR_MAX)
    s.sh = Borner(floor(tonumber(s.sh) or 0), 0, ADB.SHIELD_MAX)
    local inv, eq = {}, {}
    if type(s.inv) == "table" then
        for i = 1, ADB.INV_SLOTS do inv[i] = ADB.ValiderItem(s.inv[i]) end
    end
    if type(s.equip) == "table" then
        for _, sl in ipairs(ADB.SLOTS) do
            local it = ADB.ValiderItem(s.equip[sl[1]])
            if it and it.kind == "equip" and it.slot == sl[1] then eq[sl[1]] = it end
        end
    end
    s.inv, s.equip = inv, eq
    local t = { talents = { arbres = {}, appris = s.appris, cd = s.cd, extras = s.extras } }
    ADB.TalInitDB(t)
    s.appris, s.cd, s.extras = t.talents.appris, t.talents.cd, t.talents.extras
end

local function Prep()
    local D, a = ADB.db, ADB.db.sec
    ADB.alt = (type(a) == "table" and a.type == ALT) and a or nil
    if not ADB.alt then return end
    local P = setmetatable({}, {
        __index = function(_, k)
            if k == "nomRP" then return a.rp end
            local v = a[k]
            if v == nil then v = D[k] end
            return v
        end,
        __newindex = function(_, k, v) a[k] = v end,
    })
    rawset(P, "talents", { arbres = D.talents.arbres, appris = a.appris, cd = a.cd, extras = a.extras })
    if not ADB.altBarre then
        local m = ADB.barre
        ADB.TalCreerBarre()
        ADB.altBarre, ADB.barre = ADB.barre, m
    end
    ADB.barreMain = ADB.barre
    rec[true].db, rec[true].name, rec[true].barre = P, a.nom, ADB.altBarre
end

function ADB.AltInit()
    local s = ADB.db.sec
    if type(s) == "table" and s.type == ALT then
        Valider(s)
        Prep()
        ADB.Ctx(true, function()
            local d = ADB.GetStatBlock(ADB.playerName)
            s.pv = Borner(floor(tonumber(s.pv) or d.pvMax), 0, d.pvMax)
            s.pm = Borner(floor(tonumber(s.pm) or d.pmMax), 0, d.pmMax)
        end)
    else
        ADB.alt = nil
    end
end

function ADB.AltSauver(nom, rp, race, classe)
    local s = ADB.db.sec
    if not (type(s) == "table" and s.type == ALT) then
        if IsInGroup() and ADB.GetPet() then ADB.Envoyer("PD") end
        s = { type = ALT, xp = ADB.db.xp, pc = 0 }
        ADB.db.sec = s
    end
    s.nom, s.rp, s.race, s.classe = nom, rp, race or "Humain", classe or "Guerrier"
    ADB.AltInit()
    sig = nil
    ADB.Ctx(true, ADB.AltApres)
    ADB.petMenu:Hide()
    ADB.Print("Personnage joueur secondaire enregistré.")
end

function ADB.AltSupprimer(silencieux)
    if IsInGroup() then ADB.Envoyer("AD") end
    for i = #ADB.pnjRecus, 1, -1 do
        if ADB.pnjRecus[i].owner == "+" .. ADB.mainName then tremove(ADB.pnjRecus, i) end
    end
    ADB.db.sec, ADB.alt, sig = nil, nil, nil
    ADB.talAlt, ADB.invAlt, ADB.sel = false, false, nil
    for _, f in ipairs({ ADB.altFiche, ADB.altBarre }) do if f then f:Hide() end end
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
    ADB.RafraichirInv()
    ADB.TalDessiner()
    if not silencieux then ADB.Print("Personnage secondaire supprimé.") end
end

------------------------------------------------------------------------------
-- Menu "Personnage secondaire" : Race / Classe
------------------------------------------------------------------------------
local function DropEx(f, nom, y, liste, cle)
    local d = CreateFrame("Frame", nom, f, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", 90, y)
    UIDropDownMenu_SetWidth(d, 150)
    UIDropDownMenu_Initialize(d, function(_, niv)
        for _, e in ipairs(liste) do
            if not ADB.ClasseSpeciale(e[1]) then
                local i = UIDropDownMenu_CreateInfo()
                i.text, i.checked = e[1], (f[cle] == e[1])
                i.func = function()
                    f[cle] = e[1]
                    UIDropDownMenu_SetText(d, e[1])
                end
                UIDropDownMenu_AddButton(i, niv)
            end
        end
    end)
    return d
end

hooksecurefunc(ADB, "PetMajMenu", function()
    local f = ADB.petMenu
    if not f then return end
    if not f.DRace then
        f.LRace = UI.Etiq(f, "Race", 16, -151)
        f.DRace = DropEx(f, "ADBAltRaceDrop", -144, ADB.RACES, "aRace")
        f.LClasse = UI.Etiq(f, "Classe", 16, -181)
        f.DClasseA = DropEx(f, "ADBAltClasseDrop", -174, ADB.CLASSES, "aClasse")
    end
    local on = f.type == ALT
    for _, w in ipairs({ f.LRace, f.DRace, f.LClasse, f.DClasseA }) do w:SetShown(on) end
    if on then
        f.aRace, f.aClasse = f.aRace or "Humain", f.aClasse or "Guerrier"
        UIDropDownMenu_SetText(f.DRace, f.aRace)
        UIDropDownMenu_SetText(f.DClasseA, f.aClasse)
    end
end)

hooksecurefunc(ADB, "PetBasculerMenu", function()
    local f, s = ADB.petMenu, ADB.db and ADB.db.sec
    if f and f:IsShown() then
        f.aRace, f.aClasse = s and s.race, s and s.classe
        ADB.PetMajMenu()
    end
end)

------------------------------------------------------------------------------
-- Fenêtres talents / inventaire : bascule principal <-> secondaire
------------------------------------------------------------------------------
local function Flag(nom, cle)
    local o = ADB[nom]
    ADB[nom] = function(...) return ADB.Ctx(ADB[cle], o, ...) end
end
for _, n in ipairs({ "TalDessiner", "TalClicNoeud", "TalClicCase", "TalSurvol", "TalSupprimer" }) do Flag(n, "talAlt") end
for _, n in ipairs({ "RafraichirInv", "OnSlotClick", "SlotInfobulle", "ClicDetruire", "ClicOr" }) do Flag(n, "invAlt") end

local oBT, oBI = ADB.BasculerTalents, ADB.BasculerInv
ADB.BasculerTalents = function()
    if not (ADB.talFrame and ADB.talFrame:IsShown()) then ADB.talAlt, ADB.talVue = false, nil end
    return oBT()
end
ADB.BasculerInv = function()
    if not ADB.invFrame:IsShown() then ADB.invAlt, ADB.sel = false, nil end
    return oBI()
end

hooksecurefunc(ADB, "TalDessiner", function()
    local f = ADB.talFrame
    if f and f.TitleText then
        f.TitleText:SetText(ADB.talAlt and ADB.alt and ("Arbre de talents - " .. ADB.alt.nom) or "Arbre de talents")
    end
end)

hooksecurefunc(ADB, "TalCreer", function()
    local f = ADB.talFrame
    f.BtnAlt = UI.Bouton(f, "Secondaire", 798, -660, 120, function()
        ADB.talAlt, ADB.talVue = not ADB.talAlt, nil
        f.sel, f.mode = nil, nil
        ADB.TalDessiner()
    end)
end)
hooksecurefunc(ADB, "TalMajPanneau", function()
    local b = ADB.talFrame and ADB.talFrame.BtnAlt
    if b then
        b:SetShown(ADB.alt ~= nil)
        b:SetText(ADB.talAlt and "Principal" or "Secondaire")
    end
end)

function ADB.AltDeplacer()
    local s, fl = ADB.sel, ADB.invAlt
    if not (ADB.alt and s and s.zone == "inv") then return end
    local it = ADB.Ctx(fl, ADB.ObjetEn, "inv", s.key)
    if not it then return end
    if (ADB.Ctx(not fl, ADB.AjouterObjet, it, 1) or 0) >= 1 then
        ADB.Ctx(fl, ADB.RetirerDe, s.key)
        ADB.sel = nil
    else
        ADB.Print("Inventaire de destination plein !")
    end
    ADB.RafraichirInv()
end

hooksecurefunc(ADB, "CreerInv", function()
    local f = ADB.invFrame
    f.AltBtn = UI.Bouton(f, "Secondaire", 120, -410, 100, function()
        ADB.invAlt, ADB.sel = not ADB.invAlt, nil
        ADB.RafraichirInv()
    end)
    f.MoveBtn = UI.Bouton(f, "Vers l'autre", 224, -410, 100, ADB.AltDeplacer)
end)
hooksecurefunc(ADB, "RafraichirInv", function()
    local f = ADB.invFrame
    if not (f and f.AltBtn) then return end
    f.AltBtn:SetShown(ADB.alt ~= nil)
    f.MoveBtn:SetShown(ADB.alt ~= nil)
    f.AltBtn:SetText(ADB.invAlt and "Principal" or "Secondaire")
    f.TitleText:SetText(ADB.invAlt and ADB.alt and ("Inventaire - " .. ADB.alt.nom) or "Inventaire")
end)

-- Bouton dans la fiche principale (non-MJ)
hooksecurefunc(ADB, "RafraichirConfig", function()
    local f = ADBConfigFrame
    if not (f and f:IsShown() and ADB.db) then return end
    if not f.AltBtn then
        f.AltBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.AltBtn:SetSize(200, 24)
        f.AltBtn:SetText("Fiche du secondaire")
        f.AltBtn:SetScript("OnClick", ADB.AltBasculerFiche)
    end
    local on = ADB.alt ~= nil and not ADB.EstMJ()
    f.AltBtn:SetShown(on)
    if on then
        f.AltBtn:ClearAllPoints()
        f.AltBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 104)
        f:SetHeight(f:GetHeight() + 28)
    end
end)

------------------------------------------------------------------------------
-- Popups : exécutés dans le contexte où ils ont été ouverts
------------------------------------------------------------------------------
hooksecurefunc("StaticPopup_Show", function(n) ADB.popAlt[n] = ADB.ctxAlt and true or nil end)
for _, n in ipairs({ "ADB_DETRUIRE", "ADB_POTION", "ADB_DON", "ADB_TAL_UTILISER", "ADB_TAL_HORSTOUR", "ADB_TAL_FORCE" }) do
    local d = StaticPopupDialogs[n]
    local o = d.OnAccept
    d.OnAccept = function(...) return ADB.Ctx(ADB.popAlt[n], o, ...) end
end
do
    local d = StaticPopupDialogs["ADB_TAL_RESET"]
    local o = d.OnAccept
    d.OnAccept = function(...) return ADB.Ctx(ADB.talAlt, o, ...) end
end

-- Demandes de validation MJ : marquer l'origine, et rejouer la réponse dans le bon contexte
for _, n in ipairs({ "TalDemanderMJ", "PotionDemanderMJ" }) do
    local o = ADB[n]
    ADB[n] = function(...)
        local j = ADB.talJeton
        o(...)
        if ADB.ctxAlt and ADB.talJeton ~= j and ADB.talAttente[ADB.talJeton] then
            ADB.talAttente[ADB.talJeton].alt = true
        end
    end
end

local oRT = ADB.RecevoirTalent
ADB.RecevoirTalent = function(cmd, nom, msg)
    if ADB.ctxAlt or not ADB.alt then return oRT(cmd, nom, msg) end
    if cmd == "HR" then
        local _, w, j = strsplit(";", msg)
        local att = w == ADB.playerName and ADB.talAttente[tonumber(j) or 0]
        if att and att.alt then
            return ADB.Ctx(true, oRT, cmd, nom, (msg:gsub("^HR;[^;]*", "HR;" .. ADB.alt.nom)))
        end
    elseif cmd ~= "TQ" and cmd ~= "HQ" and ADB.alt.classe ~= ADB.db.classe then
        ADB.Ctx(true, oRT, cmd, nom, msg) -- arbre de la classe du secondaire
    end
    return oRT(cmd, nom, msg)
end

------------------------------------------------------------------------------
-- Adaptations du moteur
------------------------------------------------------------------------------
local oAC = ADB.ApresChangementLocal
ADB.ApresChangementLocal = function()
    if ADB.ctxAlt then return ADB.AltApres() end
    return oAC()
end

local oFT = ADB.FinTourJoueur
ADB.FinTourJoueur = function()
    if ADB.ctxAlt then
        ADB.tourPasse = true
        ADB.TalRafraichirBarre()
        return
    end
    return oFT()
end

local oP = ADB.Print
ADB.Print = function(m)
    if ADB.ctxAlt and ADB.alt then m = "|cffaaaaaa(" .. ADB.alt.nom .. ")|r " .. m end
    return oP(m)
end

for _, n in ipairs({ "RecevoirXP", "RecevoirRepos" }) do
    local o = ADB[n]
    ADB[n] = function(v)
        o(v)
        if ADB.alt and not ADB.ctxAlt then ADB.Ctx(true, o, v) end
    end
end

-- Buffs du secondaire : portés par son PNJ ("N:id") côté MJ
local function K(k)
    if ADB.ctxAlt and k == "P:" .. ADB.playerName then
        local p = AltPNJ()
        if p then return "N:" .. p.id end
    end
    return k
end
local oBA, oBB = ADB.BufA, ADB.BufBonus
ADB.BufA = function(k, t) return oBA(K(k), t) end
ADB.BufBonus = function(k) return oBB(K(k)) end

-- Effets : le secondaire est un PNJ pour le MJ ; le personnage principal reste un joueur
local oEnv = ADB.EnvoyerEffets
ADB.EnvoyerEffets = function(liste, inter, val)
    if ADB.ctxAlt and IsInGroup() then
        local l = {}
        for i, e in ipairs(liste) do
            l[i] = (e.k == "P" and e.id == ADB.playerName) and { k = "N", id = e.id, nom = e.id } or e
        end
        liste = l
    end
    return oEnv(liste, inter, val)
end

local oEU = ADB.EntreeUnite
ADB.EntreeUnite = function(u)
    if ADB.ctxAlt and UnitExists(u) and UnitIsPlayer(u) and UnitName(u) == ADB.mainName then
        return { k = "P", id = ADB.mainName, nom = ADB.Ctx(false, ADB.NomAffiche, ADB.mainName) }
    end
    return oEU(u)
end

------------------------------------------------------------------------------
-- Synchronisation / hooks
------------------------------------------------------------------------------
hooksecurefunc(ADB, "TalRafraichirBarre", function()
    if ADB.ctxAlt or not ADB.alt then return end
    ADB.Ctx(true, ADB.TalRafraichirBarre)
    BarreFix()
end)
hooksecurefunc(ADB, "PetRafraichir", function() if ADB.alt then BarreFix() end end)

hooksecurefunc(ADB, "PhaseCombat", function(ph)
    if ADB.ctxAlt or not ADB.alt then return end
    ADB.Ctx(true, function()
        if ph == "PLAYER_TURN" then ADB.tourPasse = false end
        ADB.TalPhase(ph)
    end)
    BarreFix()
end)

-- PV/PM/bouclier : miroir du PNJ MJ
hooksecurefunc(ADB, "RafraichirNPC", function()
    if ADB.ctxAlt or not ADB.alt then return end
    local p = AltPNJ()
    if p then
        ADB.Ctx(true, function()
            local a, d = ADB.db, ADB.GetStatBlock(ADB.playerName)
            a.pv, a.pm, a.sh = Borner(p.pv, 0, d.pvMax), Borner(p.pm, 0, d.pmMax), p.sh or 0
            ADB.TalRafraichirBarre()
        end)
        BarreFix()
        ADB.AltMajFiche()
    end
end)

hooksecurefunc(ADB, "RafraichirTout", function()
    if ADB.ctxAlt or not ADB.alt then return end
    ADB.Ctx(true, function()
        ADB.TalDemanderArbre()
        if not AltPNJ() then Envoyer() end
    end)
    ADB.AltMajFiche()
end)

-- MJ : réception AS (état) / AD (suppression)
local oExt = ADB.RecevoirExt
ADB.RecevoirExt = function(cmd, nom, message)
    if cmd ~= "AS" and cmd ~= "AD" then return oExt(cmd, nom, message) end
    if not (ADB.EstMJ() and ADB.roster[nom]) then return end
    local p, o, pn = { strsplit(";", message) }, "+" .. nom, nil
    for _, x in ipairs(ADB.db.pnjs) do
        if x.owner == o then
            pn = x
            break
        end
    end
    if cmd == "AD" then
        if pn then ADB.SupprimerPNJ(pn.id) end
        return
    end
    local an, rp = Net(Decoder(p[2] or "")):sub(1, 30), Net(Decoder(p[3] or "")):sub(1, 40)
    if an == "" then return end
    local mx = Borner(floor(tonumber(p[4]) or 1), 1, ADB.PNJ_STAT_MAX)
    local mm = Borner(floor(tonumber(p[5]) or 0), 0, ADB.PNJ_STAT_MAX)
    if not pn then
        if #ADB.db.pnjs >= ADB.PNJ_MAX then return end
        local id = ADB.db.pnjProchainId
        ADB.db.pnjProchainId = id + 1
        pn = { id = id, ally = true, owner = o }
        table.insert(ADB.db.pnjs, pn)
    end
    pn.nom, pn.rp, pn.pvMax, pn.pmMax = an, rp ~= "" and rp or nil, mx, mm
    pn.pv = Borner(floor(tonumber(p[6]) or mx), 0, mx)
    pn.pm = Borner(floor(tonumber(p[7]) or 0), 0, mm)
    pn.sh = Borner(floor(tonumber(p[8]) or 0), 0, ADB.SHIELD_MAX)
    local rc, cl = Decoder(p[9] or ""), Decoder(p[10] or "")
    pn.race, pn.classe = ADB.RACE_MAP[rc] and rc or "?", ADB.CLASSE_MAP[cl] and cl or "?"
    pn.xp = math.max(0, floor(tonumber(p[11]) or 0))
    pn.level = ADB.NiveauPourXP(pn.xp)
    pn.pc = Borner(floor(tonumber(p[12]) or 0), 0, ADB.OR_MAX)
    pn.force, pn.agilite, pn.intelligence = floor(tonumber(p[13]) or 0), floor(tonumber(p[14]) or 0),
        floor(tonumber(p[15]) or 0)
    ADB.PlanifierPNJ(pn.id)
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
end

local oLogin = ADB.Evenements.PLAYER_LOGIN
ADB.Evenements.PLAYER_LOGIN = function(...)
    oLogin(...)
    ADB.mainName = ADB.playerName
    ADB.AltInit()
    ADB.RafraichirTout()
end

function ADB.AltDefinirNiveau(n)
    if not (ADB.alt and n) then return end
    n = Borner(floor(n), 1, ADB.NIVEAU_MAX)
    local avant = ADB.Ctx(true, function() return ADB.GetStatBlock(ADB.playerName) end)
    ADB.alt.xp, ADB.alt.level = ADB.XP_SEUILS[n], n
    ADB.Ctx(true, function()
        local d, db = ADB.GetStatBlock(ADB.playerName), ADB.db
        if db.pv >= avant.pvMax then db.pv = d.pvMax end
        if db.pm >= avant.pmMax then db.pm = d.pmMax end
        db.pv, db.pm = Borner(db.pv, 0, d.pvMax), Borner(db.pm, 0, d.pmMax)
        ADB.TalNettoyerPoints()
        ADB.ApresChangementLocal()
    end)
end