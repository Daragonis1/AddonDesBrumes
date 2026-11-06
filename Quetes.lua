-- ============================================================================
-- Quetes.lua : suivi quêtes MJ / aspirations joueurs + système de butin (jet 1-100)
--
-- PROTOCOLE (ADB.PREFIX, canal PARTY/RAID/INSTANCE via ADB.Envoyer / ADB.TalEnfiler) :
--   QD;clé;i;n;morceau     données quête/aspiration (titre\tdesc), n morceaux
--                          clé = "G1".."G5" (MJ uniquement)  |  "P:NomJoueur" (le joueur lui-même)
--   QX;clé                 suppression
--   QC;clé;titreEnc        complétion (MJ uniquement) -> flash doré chez tous
--   QQ                     demande de resynchronisation (nouveau membre)
--   LS;id;rareté;nomEnc    MJ  -> joueurs : début de session de butin (popup Oui/Non)
--   LR;id;1|0              joueur -> MJ    : accepte / refuse le jet
--   LW;id;gagnantEnc;jet;nomEnc;rareté   MJ -> joueurs : résultat
-- Les jets sont lus par le MJ dans CHAT_MSG_SYSTEM ("X obtient N (1-100)") : non falsifiables.
-- ============================================================================
local ADB = ADB
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local Encoder, Decoder, Net = ADB.Encoder, ADB.Decoder, ADB.NettoyerNom
local UI = ADB.UI

local MAX_Q, MAX_ASP, T_MAX, D_MAX = 5, 5, 40, 300
ADB.qRecu = { G = {}, P = {} }          -- données reçues (mémoire seulement)
local qBuf, qSrc = {}, nil

-- Enregistrer les nouvelles commandes dans le routeur existant (Pets.lua : ADB.CMD_EXT)
for _, c in ipairs({ "QD", "QX", "QC", "QQ", "LS", "LR", "LW" }) do ADB.CMD_EXT[c] = true end

------------------------------------------------------------------------------
-- OUTILS / ACCES AUX DONNEES
--   Persistance (SavedVariablesPerCharacter, champs ajoutés dynamiquement à ADB.db) :
--     ADB.db.quetes     = { [1..5] = { t = titre, d = desc } }   (MJ ou solo)
--     ADB.db.aspiration = { t = titre, d = desc }                (joueur)
--     ADB.db.qMin       = bool (tracker réduit)
------------------------------------------------------------------------------
local function NetD(s) return strtrim((tostring(s or ""):gsub("[%c|]", " "))):sub(1, D_MAX * 2) end
local function NetT(s) return Net(s):sub(1, T_MAX * 2) end

local function Morceaux(s, taille)          -- découpe UTF-8 safe
    local t, i = {}, 1
    while i <= #s do
        local j = min(i + taille - 1, #s)
        while j < #s and j > i and (s:byte(j + 1) or 0) >= 0x80 and (s:byte(j + 1) or 0) < 0xC0 do j = j - 1 end
        t[#t + 1] = s:sub(i, j)
        i = j + 1
    end
    return t
end

local function Peut(key)                    -- droit d'édition
    if key:match("^G[1-5]$") then return ADB.EstMJ() or not IsInGroup() end
    return key == "P:" .. ADB.playerName and not ADB.EstMJ()
end
local function PeutTerminer() return ADB.EstMJ() or not IsInGroup() end

local function Source()                     -- table des quêtes G affichée
    if ADB.EstMJ() or not IsInGroup() then
        ADB.db.quetes = type(ADB.db.quetes) == "table" and ADB.db.quetes or {}
        return ADB.db.quetes
    end
    return ADB.qRecu.G
end

local function Get(key)
    local g = key:match("^G([1-5])$")
    if g then return Source()[tonumber(g)] end
    local nom = key:match("^P:(.+)$")
    if nom == ADB.playerName then return ADB.db.aspiration end
    return nom and ADB.qRecu.P[nom] or nil
end

local function Liste()
    local res, src = {}, Source()
    for i = 1, MAX_Q do
        if src[i] then res[#res + 1] = { key = "G" .. i, e = src[i] } end
    end
    local noms = {}
    if not ADB.EstMJ() and ADB.db.aspiration then noms[1] = ADB.playerName end
    local autres = {}
    for n in pairs(ADB.qRecu.P) do if n ~= ADB.playerName then autres[#autres + 1] = n end end
    table.sort(autres)
    for _, n in ipairs(autres) do noms[#noms + 1] = n end
    for i = 1, min(#noms, MAX_ASP) do
        local e = Get("P:" .. noms[i])
        if e then res[#res + 1] = { key = "P:" .. noms[i], e = e, nom = noms[i] } end
    end
    return res
end

------------------------------------------------------------------------------
-- ENVOI
------------------------------------------------------------------------------
local function EnvoyerEntree(key, e)
    if not IsInGroup() then return end
    if not e then ADB.TalEnfiler("QX;" .. key) return end
    local ch = Morceaux(e.t .. "\t" .. e.d, 60)
    for i, s in ipairs(ch) do
        ADB.TalEnfiler(format("QD;%s;%d;%d;%s", key, i, #ch, Encoder(s)))
    end
end

local planif
local function Diffuser()                   -- diffuse MES données (MJ : 5 slots ; joueur : aspiration)
    if planif then return end
    planif = true
    C_Timer.After(1.5, function()
        planif = false
        if not (ADB.db and IsInGroup()) then return end
        if ADB.EstMJ() then
            for i = 1, MAX_Q do EnvoyerEntree("G" .. i, type(ADB.db.quetes) == "table" and ADB.db.quetes[i] or nil) end
        elseif ADB.db.aspiration then
            EnvoyerEntree("P:" .. ADB.playerName, ADB.db.aspiration)
        end
    end)
end

------------------------------------------------------------------------------
-- ALERTE DOREE (style "quête terminée")
------------------------------------------------------------------------------
function ADB.QueteAlerte(sous, titre)
    local a = ADB.qAlerte
    if not a then
        a = CreateFrame("Frame", "ADBQuestAlert", UIParent)
        a:SetAllPoints(UIParent)
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a:EnableMouse(false)
        a:Hide()
        a.flash = a:CreateTexture(nil, "BACKGROUND")
        a.flash:SetAllPoints()
        a.flash:SetColorTexture(1, 0.82, 0.2, 1)
        a.bande = a:CreateTexture(nil, "BORDER")
        a.bande:SetPoint("LEFT", a, "LEFT", 0, 130)
        a.bande:SetPoint("RIGHT", a, "RIGHT", 0, 130)
        a.bande:SetHeight(110)
        a.bande:SetColorTexture(1, 0.75, 0.1, 0.22)
        a.t1 = a:CreateFontString(nil, "OVERLAY")
        a.t1:SetFont(STANDARD_TEXT_FONT, 34, "THICKOUTLINE")
        a.t1:SetPoint("CENTER", a, "CENTER", 0, 150)
        a.t1:SetTextColor(1, 0.82, 0.2)
        a.t2 = a:CreateFontString(nil, "OVERLAY")
        a.t2:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
        a.t2:SetPoint("CENTER", a, "CENTER", 0, 108)
        a.t2:SetTextColor(1, 1, 1)
        a:SetScript("OnUpdate", function(s, el)
            s.e = s.e + el
            local e = s.e
            s.flash:SetAlpha(max(0, 0.4 * (1 - e / 1.0)))
            local ta = (e < 0.4) and (e / 0.4) or (e < 4 and 1 or max(0, 1 - (e - 4)))
            s.t1:SetAlpha(ta); s.t2:SetAlpha(ta); s.bande:SetAlpha(ta)
            if e > 5 then s:Hide() end
        end)
        ADB.qAlerte = a
    end
    a.t1:SetText(sous)
    a.t2:SetText(titre)
    a.e = 0
    a:Show()
    pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE)
end

local function TexteAlerte(key, titre)
    local o = key:match("^P:(.+)$")
    if o then return "Aspiration accomplie : " .. ADB.NomAffiche(o), titre end
    return "Quête terminée", titre
end

------------------------------------------------------------------------------
-- ACTIONS (appelées par l'éditeur / le tracker)
------------------------------------------------------------------------------
function ADB.QueteSauver(key, t, d)
    if not Peut(key) then return end
    t = NetT(t)
    if t == "" then ADB.Print("Donnez un titre.") return end
    local e = { t = t, d = NetD(d) }
    local g = key:match("^G([1-5])$")
    if g then Source()[tonumber(g)] = e else ADB.db.aspiration = e end
    EnvoyerEntree(key, e)
    ADB.QueteDessiner()
    ADB.Print("Enregistré : " .. t)
end

function ADB.QueteSupprimer(key)
    if not Peut(key) then return end
    local g = key:match("^G([1-5])$")
    if g then Source()[tonumber(g)] = nil else ADB.db.aspiration = nil end
    EnvoyerEntree(key, nil)
    ADB.QueteDessiner()
end

-- Complétion (MJ ou solo) : retire l'entrée, flash local + diffusion "QC"
function ADB.QueteTerminer(key)
    if not PeutTerminer() then return end
    local e = Get(key)
    if not e then return end
    local g, o = key:match("^G([1-5])$"), key:match("^P:(.+)$")
    if g then
        Source()[tonumber(g)] = nil
    elseif o then
        ADB.qRecu.P[o] = nil
        if o == ADB.playerName then ADB.db.aspiration = nil end
    end
    ADB.QueteAlerte(TexteAlerte(key, e.t))
    if IsInGroup() then ADB.Envoyer(format("QC;%s;%s", key, Encoder(e.t))) end
    ADB.QueteDessiner()
    if ADB.qEditeur and ADB.qEditeur:IsShown() then ADB.QueteOuvrirEditeur(ADB.qEditeur.key) end
end

StaticPopupDialogs["ADB_QUETE_TERMINER"] = {
    text = "Terminer « %s » pour tout le groupe ?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(self, data) if data then ADB.QueteTerminer(data) end end,
}

------------------------------------------------------------------------------
-- TRACKER (style ObjectiveTracker)
------------------------------------------------------------------------------
local function Bloc(f, i)
    local b = f.blocs[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetWidth(226)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.lib = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.tit = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.des = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    for _, s in ipairs({ b.lib, b.tit, b.des }) do
        s:SetWidth(224); s:SetJustifyH("LEFT"); s:SetJustifyV("TOP")
    end
    b.des:SetTextColor(0.8, 0.8, 0.8)
    b:SetScript("OnClick", function(self, bouton)
        if not self.key then return end
        if bouton == "RightButton" and PeutTerminer() then
            local e = Get(self.key)
            if e then StaticPopup_Show("ADB_QUETE_TERMINER", e.t, nil, self.key) end
        elseif bouton == "LeftButton" and Peut(self.key) then
            ADB.QueteOuvrirEditeur(self.key)
        end
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.key and Get(self.key)
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(e.t, 1, 0.82, 0)
        if e.d ~= "" then GameTooltip:AddLine(e.d, 1, 1, 1, true) end
        if Peut(self.key) then GameTooltip:AddLine("Clic gauche : modifier", 0.6, 0.6, 0.6) end
        if PeutTerminer() then GameTooltip:AddLine("Clic droit : terminer", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.blocs[i] = b
    return b
end

function ADB.QueteDessiner()
    local f = ADB.qTracker
    if not f or not ADB.db or not ADB.playerName then return end
    local reduit = ADB.db.qMin and true or false
    f.Min:SetNormalTexture(reduit and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    local liste = reduit and {} or Liste()
    local y = -32
    for i, it in ipairs(liste) do
        local b = Bloc(f, i)
        b.key = it.key
        local off = 0
        if it.nom then
            b.lib:SetText("Aspiration de " .. ADB.NomAffiche(it.nom))
            b.lib:SetTextColor(0.5, 0.8, 1)
            b.lib:ClearAllPoints(); b.lib:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            b.lib:Show()
            off = b.lib:GetStringHeight() + 2
            b.tit:SetTextColor(0.7, 0.9, 1)
        else
            b.lib:Hide()
            b.tit:SetTextColor(1, 0.82, 0)
        end
        b.tit:SetText(it.e.t)
        b.tit:ClearAllPoints(); b.tit:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -off)
        local th = b.tit:GetStringHeight()
        b.des:SetText(it.e.d)
        b.des:ClearAllPoints(); b.des:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(off + th + 2))
        local dh = (it.e.d ~= "") and b.des:GetStringHeight() or 0
        b:SetHeight(off + th + 2 + dh)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
        b:Show()
        y = y - b:GetHeight() - 8
    end
    for i = #liste + 1, #f.blocs do f.blocs[i].key = nil; f.blocs[i]:Hide() end
    f:SetHeight(reduit and 30 or max(30, -y))
end

function ADB.QueteBasculer()
    ADB.db.qMin = not ADB.db.qMin
    ADB.QueteDessiner()
end

local function CreerTracker()
    local f = CreateFrame("Frame", "ADBQuestTracker", UIParent)
    f:SetSize(240, 30)
    f:SetFrameStrata("LOW")
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -240)   -- ajuster la position ici
    f.blocs = {}
    ADB.qTracker = f
    f.Fond = f:CreateTexture(nil, "BACKGROUND")
    f.Fond:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.Fond:SetSize(240, 30)
    f.Fond:SetAtlas("Objective-Header")                       -- atlas natif de l'ObjectiveTracker
    f.Titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Titre:SetPoint("LEFT", f, "TOPLEFT", 12, -15)
    f.Titre:SetText("Quêtes et Aspirations")
    f.Min = CreateFrame("Button", nil, f)
    f.Min:SetSize(16, 16)
    f.Min:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    f.Min:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    f.Min:SetScript("OnClick", ADB.QueteBasculer)
    f.Edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.Edit:SetSize(44, 16)
    f.Edit:SetPoint("RIGHT", f.Min, "LEFT", -4, 0)
    f.Edit:SetText("Éditer")
    f.Edit:SetScript("OnClick", function() ADB.QueteOuvrirEditeur() end)
    ADB.QueteDessiner()
end

------------------------------------------------------------------------------
-- EDITEUR (MJ : 5 slots / joueur : 1 aspiration / solo : les deux)
------------------------------------------------------------------------------
local function ChargerEditeur()
    local f = ADB.qEditeur
    local key = f.key
    local e = Get(key)
    f.Titre:SetText(e and e.t or "")
    f.Desc:SetText(e and e.d or "")
    local mj = ADB.EstMJ()
    local gOK = mj or not IsInGroup()
    for i, b in ipairs(f.slots) do
        local k = (i < 6) and ("G" .. i) or ("P:" .. ADB.playerName)
        b:SetShown((i < 6 and gOK) or (i == 6 and not mj))
        b:SetEnabled(k ~= key)
    end
    local o = key:match("^P:(.+)$")
    f.Info:SetText(o and ("Aspiration de " .. ADB.NomAffiche(o)) or ("Quête n°" .. key:sub(2)))
    f.Sauver:SetEnabled(Peut(key))
    f.Suppr:SetEnabled(Peut(key) and e ~= nil)
    f.Fin:SetShown(PeutTerminer())
    f.Fin:SetEnabled(e ~= nil)
end

function ADB.QueteOuvrirEditeur(key)
    local f = ADB.qEditeur
    if not f then
        f = UI.FenetreBase("ADBQuestEditor", 340, 292, "Quêtes & Aspiration")
        ADB.qEditeur = f
        f:SetPoint("CENTER", -250, 80)
        tinsert(UISpecialFrames, "ADBQuestEditor")
        f.slots = {}
        for i = 1, 6 do
            local k = (i < 6) and ("G" .. i) or nil
            f.slots[i] = UI.Bouton(f, i < 6 and tostring(i) or "Asp.", 16 + (i - 1) * 44, -34, i < 6 and 40 or 52,
                function() ADB.QueteOuvrirEditeur(k or ("P:" .. ADB.playerName)) end)
        end
        f.Info = UI.Etiq(f, "", 16, -64, "GameFontNormalSmall")
        UI.Etiq(f, "Titre", 16, -84)
        f.Titre = UI.Saisie(f, 20, -102, 296, T_MAX)
        UI.Etiq(f, "Description", 16, -130)
        local cadre = CreateFrame("Frame", nil, f, "BackdropTemplate")
        cadre:SetSize(300, 96)
        cadre:SetPoint("TOPLEFT", 16, -148)
        cadre:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        cadre:SetBackdropColor(0, 0, 0, 0.6)
        local eb = CreateFrame("EditBox", nil, cadre)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetPoint("TOPLEFT", 6, -6); eb:SetSize(288, 84)
        eb:SetAutoFocus(false); eb:SetMaxLetters(D_MAX)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        f.Desc = eb
        f.Sauver = UI.Bouton(f, "Enregistrer", 16, -254, 95, function()
            ADB.QueteSauver(f.key, f.Titre:GetText(), f.Desc:GetText()); ChargerEditeur()
        end)
        f.Suppr = UI.Bouton(f, "Supprimer", 116, -254, 95, function()
            ADB.QueteSupprimer(f.key); ChargerEditeur()
        end)
        f.Fin = UI.Bouton(f, "Terminer", 216, -254, 100, function()
            local e = Get(f.key)
            if e then StaticPopup_Show("ADB_QUETE_TERMINER", e.t, nil, f.key) end
        end)
    end
    if not key or not (Peut(key) or PeutTerminer()) then
        key = (ADB.EstMJ() or not IsInGroup()) and "G1" or ("P:" .. ADB.playerName)
    end
    f.key = key
    f:Show()
    ChargerEditeur()
end

------------------------------------------------------------------------------
-- LOOT : côté MJ
------------------------------------------------------------------------------
local function LootFini(L)
    for n in pairs(L.att) do
        if L.rep[n] ~= false and not L.rolls[n] then return false end
    end
    return true
end

local function LootResoudre()
    local L = ADB.loot
    if not L then return end
    ADB.loot = nil
    local best, tops = 0, {}
    for n, r in pairs(L.rolls) do
        if r > best then best, tops = r, { n } elseif r == best then tops[#tops + 1] = n end
    end
    table.sort(tops)
    local label = format("%s (%s)", L.nom, ADB.RARETES[L.rar][1])
    if #tops == 0 then
        ADB.AnnoncerChat(format("Butin %s : personne n'a lancé les dés.", label))
        ADB.Envoyer(format("LW;%d;;0;%s;%d", L.id, Encoder(L.nom), L.rar))
        return
    end
    local w = tops[math.random(#tops)]               -- égalité : tirage aléatoire parmi les meilleurs
    if #tops > 1 then
        local t = {}
        for _, n in ipairs(tops) do t[#t + 1] = ADB.NomAffiche(n) end
        ADB.AnnoncerChat(format("Égalité à %d entre %s : tirage au sort.", best, table.concat(t, ", ")))
    end
    ADB.AnnoncerChat(format("%s remporte %s avec un jet de %d !", ADB.NomAffiche(w), label, best))
    ADB.Envoyer(format("LW;%d;%s;%d;%s;%d", L.id, Encoder(w), best, Encoder(L.nom), L.rar))
    ADB.Banniere(ADB.NomAffiche(w) .. " remporte " .. L.nom)
end

function ADB.LootLancer(rar, nom)
    if not ADB.EstMJ() then ADB.Print("Réservé au MJ.") return end
    if ADB.loot then ADB.Print("Une session de butin est déjà en cours.") return end
    rar = ADB.Borner(floor(tonumber(rar) or 3), 1, #ADB.RARETES)
    nom = Net(nom or ""):sub(1, 30)
    if nom == "" then nom = "Objet" end
    local att, n = {}, 0
    for _, j in ipairs(ADB.JoueursActifs()) do att[j] = true; n = n + 1 end
    if n == 0 then ADB.Print("Aucun joueur avec l'addon dans le groupe.") return end
    ADB.lootId = (ADB.lootId or floor(GetTime())) + 1
    local id = ADB.lootId
    ADB.loot = { id = id, rar = rar, nom = nom, att = att, rep = {}, rolls = {} }
    ADB.Envoyer(format("LS;%d;%d;%s", id, rar, Encoder(nom)))
    ADB.AnnoncerChat(format("[MJ] Butin : %s (%s) - jet de 1 à 100.", nom, ADB.RARETES[rar][1]))
    C_Timer.After(45, function()                       -- délai max
        if ADB.loot and ADB.loot.id == id then LootResoudre() end
    end)
end

-- Lecture des jets publics (MJ) : "X obtient N (1-100)."
local RPAT = (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
    :gsub("([%(%)%.%-%+%[%]%^%$%?%*])", "%%%1")
    :gsub("%%%d%$s", "(.+)"):gsub("%%%d%$d", "(%%d+)")
    :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")

local function LootJet(msg)
    local L = ADB.loot
    if not (L and ADB.EstMJ()) then return end
    local who, r, lo, hi = msg:match(RPAT)
    if not who or tonumber(lo) ~= 1 or tonumber(hi) ~= 100 then return end
    who = Ambiguate(who, "short")
    if L.att[who] and L.rep[who] ~= false and not L.rolls[who] then
        L.rolls[who] = tonumber(r)
        if LootFini(L) then LootResoudre() end
    end
end

------------------------------------------------------------------------------
-- LOOT : côté joueur (popup Oui / Non)
------------------------------------------------------------------------------
StaticPopupDialogs["ADB_LOOT"] = {
    text = "Butin du MJ : %s\nLancer les dés (1-100) ?",
    button1 = YES, button2 = NO, timeout = 40, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(self, data)
        if not data then return end
        ADB.Envoyer(format("LR;%d;1", data.id))
        RandomRoll(1, 100)                              -- /roll 100 public (lu par le MJ)
    end,
    OnCancel = function(self, data, reason)
        if data and (reason == "clicked" or reason == "timeout") then ADB.Envoyer(format("LR;%d;0", data.id)) end
    end,
}

------------------------------------------------------------------------------
-- RECEPTION (routeur) : se branche sur ADB.RecevoirExt (déjà chaîné par Pets/Liens)
------------------------------------------------------------------------------
local function Cle(key, nom)
    local g = key:match("^G([1-5])$")
    if g then
        if ADB.EstNomMJ(nom) and not ADB.EstMJ() then return "G", tonumber(g) end
        return nil
    end
    local o = key:match("^P:(.+)$")
    if o and o == nom and #o < 40 and not ADB.EstNomMJ(nom) then return "P", o end
end

local function Stocker(key, nom, e)
    local kind, ref = Cle(key, nom)
    if not kind then return false end
    if kind == "G" then
        ADB.qRecu.G[ref] = e
    else
        if e and not ADB.qRecu.P[ref] then
            local n = 0
            for _ in pairs(ADB.qRecu.P) do n = n + 1 end
            if n >= 40 then return false end
        end
        ADB.qRecu.P[ref] = e
    end
    return true
end

local function Recevoir(cmd, nom, message)
    local p = { strsplit(";", message) }
    if cmd == "QQ" then
        Diffuser()
    elseif cmd == "QD" then
        local key, i, n = p[2] or "", tonumber(p[3]), tonumber(p[4])
        if not (Cle(key, nom) and i and n and n >= 1 and n <= 20 and i >= 1 and i <= n) then return end
        i, n = floor(i), floor(n)
        local bk = nom .. key
        local b = qBuf[bk]
        if i == 1 or not b or b.n ~= n then b = { n = n, l = {} }; qBuf[bk] = b end
        b.l[i] = Decoder(p[5] or "")
        for j = 1, n do if not b.l[j] then return end end
        qBuf[bk] = nil
        local t, d = table.concat(b.l, "", 1, n):match("^(.-)\t(.*)$")
        if not t then return end
        t = NetT(t)
        if t == "" then return end
        if Stocker(key, nom, { t = t, d = NetD(d) }) then ADB.QueteDessiner() end
    elseif cmd == "QX" then
        if Stocker(p[2] or "", nom, nil) then ADB.QueteDessiner() end
    elseif cmd == "QC" then
        if not ADB.EstNomMJ(nom) or ADB.EstMJ() then return end
        local key, titre = p[2] or "", NetT(Decoder(p[3] or ""))
        local g, o = key:match("^G([1-5])$"), key:match("^P:(.+)$")
        if g then
            ADB.qRecu.G[tonumber(g)] = nil
        elseif o then
            ADB.qRecu.P[o] = nil
            if o == ADB.playerName then ADB.db.aspiration = nil end
        else
            return
        end
        ADB.QueteAlerte(TexteAlerte(key, titre))
        ADB.QueteDessiner()
        if ADB.qEditeur and ADB.qEditeur:IsShown() then ChargerEditeur() end
    elseif cmd == "LS" then
        if not ADB.EstNomMJ(nom) or ADB.EstMJ() then return end
        local id, rar = tonumber(p[2]), tonumber(p[3])
        if not (id and rar and ADB.RARETES[floor(rar)]) then return end
        local R = ADB.RARETES[floor(rar)]
        local nomObj = Net(Decoder(p[4] or "")):sub(1, 30)
        StaticPopup_Show("ADB_LOOT", format("|cff%s%s|r (%s)", R[6], nomObj, R[1]), nil, { id = floor(id) })
    elseif cmd == "LR" then
        local L = ADB.loot
        if not (L and ADB.EstMJ()) or tonumber(p[2]) ~= L.id or not L.att[nom] then return end
        L.rep[nom] = (p[3] == "1")                      -- false = refus
        if LootFini(L) then LootResoudre() end
    elseif cmd == "LW" then
        if not ADB.EstNomMJ(nom) or ADB.EstMJ() then return end
        StaticPopup_Hide("ADB_LOOT")
        local w, jet = Decoder(p[3] or ""), tonumber(p[4]) or 0
        local obj = Net(Decoder(p[5] or "")):sub(1, 30)
        if w == "" then
            ADB.Print("Butin " .. obj .. " : personne n'a lancé les dés.")
        else
            ADB.Print(format("%s remporte %s (jet : %d).", ADB.NomAffiche(w), obj, jet))
            ADB.Banniere(ADB.NomAffiche(w) .. " remporte " .. obj)
        end
    end
end

local oExt = ADB.RecevoirExt
ADB.RecevoirExt = function(cmd, nom, message)
    if cmd == "QD" or cmd == "QX" or cmd == "QC" or cmd == "QQ"
        or cmd == "LS" or cmd == "LR" or cmd == "LW" then
        return Recevoir(cmd, nom, message)
    end
    return oExt(cmd, nom, message)
end

------------------------------------------------------------------------------
-- EVENEMENTS : resync groupe + lecture des jets
------------------------------------------------------------------------------
local rs
local function Resync()
    if rs then return end
    rs = true
    C_Timer.After(2.5, function()
        rs = false
        if not ADB.db or not ADB.playerName then return end
        if not IsInGroup() then
            wipe(ADB.qRecu.G); wipe(ADB.qRecu.P); qSrc = nil
        else
            local present = ADB.NomsGroupe()
            for n in pairs(ADB.qRecu.P) do if not present[n] then ADB.qRecu.P[n] = nil end end
            local mj = ADB.NomMJ()
            if ADB.EstMJ() or qSrc ~= mj then wipe(ADB.qRecu.G); qSrc = mj end
            ADB.Envoyer("QQ")                           -- les autres répondent avec leurs données
            Diffuser()
        end
        ADB.QueteDessiner()
    end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_SYSTEM" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_SYSTEM" then LootJet(msg or "") else Resync() end
end)

------------------------------------------------------------------------------
-- INTEGRATION : login (UI) + boutons MJ + commandes
------------------------------------------------------------------------------
local function CreerLootUI()
    local mj = ADBMJFrame                               -- frame XML existante (Outils MJ)
    mj:SetHeight(260)
    UI.Bouton(mj, "Quêtes", 20, -130, 125, function() ADB.QueteOuvrirEditeur() end)
    UI.Etiq(mj, "Objet", 20, -162)
    mj.LootNom = UI.Saisie(mj, 70, -159, 200, 30)
    mj.LootRar = 3
    local d = CreateFrame("Frame", "ADBLootRarDrop", mj, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", 0, -180)
    UIDropDownMenu_SetWidth(d, 120)
    UIDropDownMenu_Initialize(d, function(self, niveau)
        for i, R in ipairs(ADB.RARETES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = "|cff" .. R[6] .. R[1] .. "|r"
            info.checked = (mj.LootRar == i)
            info.func = function()
                mj.LootRar = i
                UIDropDownMenu_SetText(d, "|cff" .. R[6] .. R[1] .. "|r")
            end
            UIDropDownMenu_AddButton(info, niveau)
        end
    end)
    local R = ADB.RARETES[mj.LootRar]
    UIDropDownMenu_SetText(d, "|cff" .. R[6] .. R[1] .. "|r")
    UI.Bouton(mj, "Lancer le butin", 150, -184, 130, function()
        ADB.LootLancer(mj.LootRar, mj.LootNom:GetText())
    end)
end

local oLogin = ADB.Evenements.PLAYER_LOGIN
ADB.Evenements.PLAYER_LOGIN = function(...)
    oLogin(...)
    -- validation des données sauvegardées
    local q = {}
    if type(ADB.db.quetes) == "table" then
        for i = 1, MAX_Q do
            local e = ADB.db.quetes[i]
            if type(e) == "table" and type(e.t) == "string" then q[i] = { t = NetT(e.t), d = NetD(e.d) } end
        end
    end
    ADB.db.quetes = q
    local a = ADB.db.aspiration
    ADB.db.aspiration = (type(a) == "table" and type(a.t) == "string") and { t = NetT(a.t), d = NetD(a.d) } or nil
    CreerTracker()
    CreerLootUI()
end

local oSlash = SlashCmdList["ADDONDESBRUMES"]
SlashCmdList["ADDONDESBRUMES"] = function(msg)
    local cmd, reste = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "quete" or cmd == "quetes" or cmd == "aspiration" then
        ADB.QueteOuvrirEditeur()
    elseif cmd == "suivi" then
        ADB.QueteBasculer()
    elseif cmd == "butin" then
        ADB.LootLancer(3, reste)                        -- /brumes butin Nom de l'objet (rareté Rare)
    else
        oSlash(msg)
    end
end