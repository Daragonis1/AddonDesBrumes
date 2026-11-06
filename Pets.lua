-- Pets.lua  (remplace Pet.lua)
local ADB = ADB
local floor, max = math.floor, math.max
local format = string.format
local Borner, Encoder, Decoder = ADB.Borner, ADB.Encoder, ADB.Decoder
local IconeTex = ADB.IconeTex

ADB.CMD_EXT = { PQ = true, PR = true, PY = true, PM = true, PD = true, BA = true, BF = true }

-- stat : 2 Force, 3 Agilité, 4 Intelligence (stat du MAITRE)
ADB.PET_TYPES = {
    Serge = {
        icon = "Ability_Hunter_Pet_Boar",
        stat = 3,
        base = 1,
        skills = {
            {
                nom = "Charge",
                icon = "Ability_Warrior_Charge",
                stat = 3,
                prec = 60,
                base = 1,
                mana = 3,
                stun = 1,
                tags = {},
                desc = "Inflige [1] dégât et étourdit la cible 1 tour."
            },
        }
    },
    Imp = { icon = "Spell_Shadow_SummonImp", stat = 4, base = 1, skills = {} },
    Felhound = { icon = "Spell_Shadow_SummonFelHunter", stat = 4, base = 3, skills = {} },
}

local DEF_TYPE = { icon = "INV_Sword_04", stat = 3, base = 1, skills = {} }
local cacheSkills = {}

-- Liste des compétences d'un familier : Attaque de base (tous) + spécifiques au type
function ADB.PetSkills(p)
    local k = p and p.petType or ""
    if not cacheSkills[k] then
        local T = ADB.PET_TYPES[k] or DEF_TYPE
        local l = { {
            nom = "Attaque de base",
            icon = T.icon,
            stat = T.stat,
            prec = 60,
            base = T.base,
            mana = 0,
            tags = { "hitfam" },
            desc = format("Inflige [%d] dégât%s.", T.base, T.base > 1 and "s" or "")
        } }
        for _, s in ipairs(T.skills) do l[#l + 1] = s end
        cacheSkills[k] = l
    end
    return cacheSkills[k]
end

ADB.petUsed = {}

local function TypeDe(s)
    for k in pairs(ADB.PET_TYPES) do
        if k:lower() == (s or ""):lower() then return k end
    end
end

local function PNJ(id)
    for _, p in ipairs(ADB.db.pnjs) do if p.id == id then return p end end
end
local function PetDe(nom)
    for _, p in ipairs(ADB.db.pnjs) do if p.owner == nom then return p end end
end
local function JoueurRoster(s)
    s = (s or ""):lower()
    for nom in pairs(ADB.roster) do
        if nom:lower() == s then return nom end
    end
end

-- Familier du joueur local (live depuis la liste PNJ, sinon cache), live?
function ADB.GetPet()
    if not ADB.db or not ADB.playerName then return nil end
    for _, p in ipairs(ADB.ListerPNJ()) do
        if p.owner == ADB.playerName then return p, true end
    end
    local c = ADB.db.pet
    if type(c) == "table" and tonumber(c.id) and not ADB.EstMJ() then return c, false end
end

------------------------------------------------------------------------------
-- Demandes / validation / retrait
------------------------------------------------------------------------------
function ADB.PetDemander(nom)
    if ADB.EstMJ() or not IsInGroup() then
        ADB.Print("Réservé aux joueurs d'un groupe.")
        return
    end
    nom = strtrim(nom or "")
    if nom == "" then
        ADB.Print("Usage : /brumes pet add [NOM DU PNJ]")
        return
    end
    local p
    for _, x in ipairs(ADB.ListerPNJ()) do
        if x.nom:lower() == nom:lower() then
            p = x
            break
        end
    end
    if not p or not p.ally then
        ADB.Print("PNJ allié introuvable dans le groupe : " .. nom)
        return
    end
    if p.owner then
        ADB.Print(p.nom .. " est déjà un familier.")
        return
    end
    ADB.Envoyer(format("PQ;%d;%s", p.id, Encoder(p.nom)))
    ADB.Print("Demande envoyée au MJ pour contrôler " .. p.nom .. ".")
end

function ADB.PetAttribuer(joueur, id)
    if not ADB.EstMJ() then return end
    local p = PNJ(id)
    if not p or p.owner then return end
    local ancien = PetDe(joueur)
    if ancien then
        ancien.owner = nil
        ADB.PlanifierPNJ(ancien.id)
    end
    p.owner = joueur
    ADB.PlanifierPNJ(id)
    ADB.Envoyer(format("PR;%s;1", joueur))
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
end

function ADB.PetRetirer(joueur)
    if not ADB.EstMJ() then return end
    local p = PetDe(joueur)
    if not p then return end
    p.owner = nil
    ADB.PlanifierPNJ(p.id)
    ADB.Envoyer(format("PR;%s;2", joueur))
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
    ADB.Print(format("%s n'a plus de familier.", ADB.NomAffiche(joueur)))
end

StaticPopupDialogs["ADB_PET_VALID"] = {
    text = "%s demande à contrôler « %s » comme familier.\nValider ?",
    button1 = "Valider",
    button2 = "Refuser",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) if data then ADB.PetAttribuer(data.joueur, data.id) end end,
    OnCancel = function(self, data, reason)
        if data and reason == "clicked" and ADB.EstMJ() then ADB.Envoyer(format("PR;%s;0", data.joueur)) end
    end,
}

function ADB.PetCommande(reste)
    local sub, arg = strtrim(reste or ""):match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    local mj = ADB.EstMJ()
    if sub == "add" then
        if not mj then return ADB.PetDemander(arg) end
        local joueur, nomPNJ
        for nom in pairs(ADB.roster) do
            local suf = " " .. nom:lower()
            if arg:lower():sub(- #suf) == suf then
                joueur, nomPNJ = nom, strtrim(arg:sub(1, #arg - #suf))
            end
        end
        local pn
        for _, p in ipairs(ADB.db.pnjs) do
            if nomPNJ and p.nom:lower() == nomPNJ:lower() then pn = p end
        end
        if not (joueur and pn and pn.ally) then
            ADB.Print("Usage MJ : /brumes pet add [PNJ allié] [Joueur]")
            return
        end
        ADB.PetAttribuer(joueur, pn.id)
    elseif sub == "remove" then
        if mj then
            local j = JoueurRoster(arg)
            if not j then
                ADB.Print("Usage MJ : /brumes pet remove [Joueur]")
                return
            end
            ADB.PetRetirer(j)
        elseif IsInGroup() and ADB.GetPet() then
            ADB.Envoyer("PD")
            ADB.db.pet = nil
            ADB.Print("Retrait du familier demandé au MJ.")
        else
            ADB.Print("Vous n'avez pas de familier.")
        end
    elseif sub == "set" then
        if mj then
            local ts, js = arg:match("^(%S+)%s+(.+)$")
            local t, j = TypeDe(ts), JoueurRoster(js)
            local pn = j and PetDe(j)
            if not (t and pn) then
                ADB.Print("Usage MJ : /brumes pet set [Serge|Imp|Felhound] [Joueur]")
                return
            end
            pn.petType = t
            ADB.PlanifierPNJ(pn.id)
            ADB.RafraichirNPC()
            ADB.Print(format("%s : type %s.", pn.nom, t))
        else
            local t = TypeDe(arg)
            if not t then
                ADB.Print("Types de familier : Serge, Imp, Felhound.")
                return
            end
            if IsInGroup() and ADB.GetPet() then
                ADB.Envoyer("PY;" .. t)
                ADB.Print("Type " .. t .. " demandé au MJ.")
            else
                ADB.Print("Vous n'avez pas de familier.")
            end
        end
    else
        ADB.Print("/brumes pet add [PNJ] | remove | set [Serge|Imp|Felhound]")
    end
    ADB.PetRafraichir()
end

function ADB.RecevoirExt(cmd, nom, message)
    local p = { strsplit(";", message) }
    if cmd == "BA" or cmd == "BF" then return ADB.BufRecevoir(cmd, nom, p) end
    if cmd == "PQ" then
        if not ADB.EstMJ() or not ADB.roster[nom] then return end
        local id = tonumber(p[2])
        local pn = id and PNJ(floor(id))
        if pn and pn.ally and not pn.owner then
            StaticPopup_Show("ADB_PET_VALID", ADB.NomAffiche(nom), pn.nom, { joueur = nom, id = pn.id })
        end
    elseif cmd == "PD" then
        if ADB.EstMJ() and ADB.roster[nom] then ADB.PetRetirer(nom) end
    elseif cmd == "PR" then
        if ADB.EstNomMJ(nom) and p[2] == ADB.playerName then
            if p[3] == "1" then
                ADB.Print("Le MJ a validé : vous contrôlez désormais votre familier.")
            elseif p[3] == "2" then
                ADB.db.pet = nil
                ADB.Print("Vous n'avez plus de familier.")
            else
                ADB.Print("Le MJ a refusé la demande de familier.")
            end
            ADB.PetRafraichir()
        end
    elseif cmd == "PY" then
        if ADB.EstMJ() and ADB.PET_TYPES[p[2] or ""] then
            local pn = PetDe(nom)
            if pn then
                pn.petType = p[2]
                ADB.PlanifierPNJ(pn.id)
                ADB.RafraichirNPC()
            end
        end
    elseif cmd == "PM" then
        if ADB.EstMJ() then
            local pn, c = PetDe(nom), tonumber(p[2])
            if pn and c then ADB.AppliquerValeurPNJ(pn.id, "pm", pn.pm - Borner(floor(c), 0, 99)) end
        end
    end
end

local oSuppr = ADB.SupprimerPNJ
ADB.SupprimerPNJ = function(id)
    if ADB.EstMJ() then
        local p = PNJ(id)
        if p and p.owner then ADB.Envoyer(format("PR;%s;2", p.owner)) end
    end
    oSuppr(id)
end

------------------------------------------------------------------------------
-- Actions du familier (actions bonus, une utilisation par compétence et par tour)
------------------------------------------------------------------------------
local function Mult(sk)
    local d = ADB.GetStatBlock(ADB.playerName)
    return ({ d.multForce, d.multAgi, d.multInt })[sk.stat - 1]
end

function ADB.PetEtat(p, sk, i)
    if ADB.phase ~= "PLAYER_TURN" then return false, "Ce n'est pas le tour des joueurs." end
    if i and ADB.petUsed[i] then return false, "Compétence déjà utilisée ce tour." end
    if ADB.BufA("N:" .. p.id, 4) then return false, "Votre familier est étourdi." end
    if (p.pm or 0) < sk.mana then return false, "Mana du familier insuffisant." end
    return true
end

function ADB.PetUtiliser(i)
    local p = ADB.GetPet()
    local sk = p and ADB.PetSkills(p)[i]
    if not sk then return end
    local ok, raison = ADB.PetEtat(p, sk, i)
    if not ok then
        UIErrorsFrame:AddMessage(raison, 1, 0.3, 0.3)
        return
    end
    if not UnitExists("target") then
        ADB.Print("Cible requise.")
        return
    end

    local key = "N:" .. p.id
    local e = ADB.EntreeUnite("target")
    local cible = ADB.TalCibleNom() or UnitName("target")
    local bp, bc, bd = ADB.BufBonus(key)
    local r, lib, c, m, echec = ADB.Jet(sk.prec, bp, bc)
    local val = max(1, floor(sk.base * Mult(sk) * bd + 0.5)) * m

    if sk.mana > 0 then
        p.pm = max(0, (p.pm or 0) - sk.mana)
        ADB.Envoyer("PM;" .. sk.mana)
    end
    ADB.petUsed[i] = true

    local msg = format("%s (familier de %s) a utilisé %s sur %s. Jet de précision : %d (%s).",
        p.nom, ADB.NomAffiche(ADB.playerName), sk.nom, cible, r, lib)
    UIErrorsFrame:AddMessage(format("%d - %s", r, lib), c[1], c[2], c[3])
    if echec then
        msg = msg .. " La compétence échoue."
    else
        msg = msg .. format(" La compétence inflige %d dégâts.", val) .. (m > 1 and " (effet doublé)" or "")
        if e then
            ADB.EnvoyerEffets({ e }, 1, val)
            if sk.stun then
                ADB.BufDemander(-1, sk.stun, 1, ADB.CleDepuisEntree(e))
                msg = msg .. format(" La cible est étourdie (%d tour).", sk.stun)
            end
        end
        if ADB.FxFamilierTouche then ADB.FxFamilierTouche(p) end
    end
    ADB.AnnoncerChat(msg)
    ADB.PetRafraichir()
end

------------------------------------------------------------------------------
-- Portraits réduits (ancrés en bas à droite du portrait, visibles par tout le groupe)
------------------------------------------------------------------------------
ADB.petMinis = {}

local function CreerMini(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(92, 28)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)
    ADB.AppliquerFond(f)
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetSize(22, 22)
    f.Icon:SetPoint("LEFT", 4, 0)
    f.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.HP = CreateFrame("StatusBar", nil, f, "ADBBarTemplate")
    f.HP:SetSize(58, 11)
    f.HP:SetPoint("TOPLEFT", 30, -4)
    f.HP.kind = "pv"
    f.MP = CreateFrame("StatusBar", nil, f, "ADBBarTemplate")
    f.MP:SetSize(58, 9)
    f.MP:SetPoint("TOPLEFT", 30, -16)
    f.MP.kind = "pm"
    return f
end

function ADB.PetMinis()
    local cibles = {}
    if ADB.db.uiRemplacee then
        cibles[1] = { ADBPlayerFrame, ADB.playerName, false }
        for _, b in ipairs(ADB.membres) do
            if b:IsShown() and b.charName then cibles[#cibles + 1] = { b, b.charName, true } end
        end
    end
    local vus = {}
    for _, c in ipairs(cibles) do
        local parent, nom, membre = c[1], c[2], c[3]
        local p
        if nom == ADB.playerName then
            p = ADB.GetPet()
        else
            for _, x in ipairs(ADB.ListerPNJ()) do
                if x.owner == nom then
                    p = x
                    break
                end
            end
        end
        if p then
            local m = ADB.petMinis[parent]
            if not m then
                m = CreerMini(parent)
                ADB.petMinis[parent] = m
            end
            m:ClearAllPoints()
            if membre then
                m:SetScale(0.85)
                m:SetPoint("LEFT", parent, "RIGHT", 2, 0)
            else
                m:SetScale(1.25)
                m:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 8, -2)
            end
            local T = ADB.PET_TYPES[p.petType or ""]
            m.npcId = p.id
            m.Icon:SetTexture(IconeTex(T and T.icon or "INV_Misc_QuestionMark"))
            ADB.MajBarre(m.HP, p.pv, p.pvMax, p.sh)
            ADB.MajBarre(m.MP, p.pm, p.pmMax)
            m:Show()
            vus[m] = true
        end
    end
    for _, m in pairs(ADB.petMinis) do
        if not vus[m] then
            m.npcId = nil
            m:Hide()
        end
    end
end

local function CreerBtn(i)
    local b = CreateFrame("Button", nil, ADB.petBar)
    b:SetSize(28, 28)
    b:SetPoint("TOPLEFT", 8 + (i - 1) * 31, -8)
    b.i = i
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.noir = b:CreateTexture(nil, "OVERLAY")
    b.noir:SetAllPoints()
    b.noir:SetColorTexture(0, 0, 0, 0.55)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self) ADB.PetUtiliser(self.i) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnEnter", function(self)
        local p = ADB.GetPet()
        local sk = p and ADB.PetSkills(p)[self.i]
        if not sk then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(sk.nom, 1, 0.82, 0)
        GameTooltip:AddLine("Action bonus", 1, 0.5, 0.1)
        GameTooltip:AddLine("Précision : " .. sk.prec, 1, 1, 1)
        if sk.mana > 0 then GameTooltip:AddLine("Coût : " .. sk.mana .. " Mana (familier)", 0.3, 0.55, 1) end
        GameTooltip:AddLine((ADB.TalTexte(sk.desc, true, Mult(sk), 0)), 1, 0.9, 0.6, true)
        local ok, raison = ADB.PetEtat(p, sk, self.i)
        if not ok then GameTooltip:AddLine(raison, 1, 0.2, 0.2, true) end
        GameTooltip:Show()
    end)
    ADB.petBar.btns[i] = b
    return b
end

function ADB.PetRafraichir()
    local bar = ADB.petBar
    if not bar or not ADB.db or not ADB.playerName then return end
    local p, live = ADB.GetPet()
    if p and live then
        ADB.db.pet = {
            id = p.id,
            nom = p.nom,
            pv = p.pv,
            pm = p.pm,
            pvMax = p.pvMax,
            pmMax = p.pmMax,
            sh = p.sh or 0,
            petType = p.petType,
            owner = p.owner
        }
    end
    ADB.PetMinis()
    if not p or ADB.EstMJ() or ADB.phase == "IDLE" then
        bar:Hide()
        return
    end
    local liste = ADB.PetSkills(p)
    bar:ClearAllPoints()
    if ADB.barre then
        bar:SetPoint("BOTTOM", ADB.barre, "TOP", 0, 6)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 210)
    end
    bar:SetSize(#liste * 31 + 13, 44)
    for i, sk in ipairs(liste) do
        local b = bar.btns[i] or CreerBtn(i)
        local ok = ADB.PetEtat(p, sk, i)
        b.tex:SetTexture(IconeTex(sk.icon))
        b.tex:SetDesaturated(not ok)
        b.noir:SetShown(not ok)
        b:Show()
    end
    for i = #liste + 1, #bar.btns do bar.btns[i]:Hide() end
    bar:Show()
end

function ADB.PetInit()
    local bar = CreateFrame("Frame", "ADBPetBar", UIParent, "BackdropTemplate")
    bar:SetSize(100, 44)
    bar:SetFrameStrata("MEDIUM")
    ADB.AppliquerFond(bar)
    bar.btns = {}
    bar:Hide()
    ADB.petBar = bar
    ADB.PetRafraichir()
end

------------------------------------------------------------------------------
-- Rafraîchissements automatiques
------------------------------------------------------------------------------
-- PNJ reçus / modifiés, rafraîchissement global : met à jour minis + barre
hooksecurefunc(ADB, "RafraichirNPC", function() ADB.PetRafraichir() end)

local dernierePhase = "IDLE"
hooksecurefunc(ADB, "PhaseCombat", function()
    local ph = ADB.phase
    if ph == dernierePhase then return end
    dernierePhase = ph
    if ph == "PLAYER_TURN" or ph == "IDLE" then wipe(ADB.petUsed) end
    ADB.PetRafraichir()
end)
------------------------------------------------------------------------------
-- Intégration : login + commandes
------------------------------------------------------------------------------
local oLogin = ADB.Evenements.PLAYER_LOGIN
ADB.Evenements.PLAYER_LOGIN = function(...)
    oLogin(...)
    ADB.BufInit()
    ADB.PetInit()
end

local oSlash = SlashCmdList["ADDONDESBRUMES"]
SlashCmdList["ADDONDESBRUMES"] = function(msg)
    local cmd, reste = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "pet" then
        ADB.PetCommande(reste)
    elseif cmd == "buff" or cmd == "debuff" then
        ADB.BufCommande(reste)
    else
        oSlash(msg)
    end
end
