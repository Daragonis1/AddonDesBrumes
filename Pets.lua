-- Pets.lua : personnage secondaire (familier) lié au joueur, stocké côté MJ comme PNJ allié "owner"
local ADB = ADB
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local Borner, Encoder, Decoder, Net = ADB.Borner, ADB.Encoder, ADB.Decoder, ADB.NettoyerNom
local UI, IconeTex = ADB.UI, ADB.IconeTex
local TEX = "Interface\\TargetingFrame\\"

ADB.CMD_EXT = { PS = true, PD = true, PM = true, BA = true, BF = true, BT = true }

-- stat : 3 Agilité, 4 Intelligence (stat du MAITRE) ; boost = tag de spécialisation (+25%)
local function Atk(nom, icon, base, mana, stun)
    return { nom = nom, icon = icon, base = base, prec = 60, mana = mana, stun = stun,
        desc = format("Inflige [%d] dégât%s%s.", base, base > 1 and "s" or "",
            stun and (" et étourdit la cible " .. stun .. " tour") or "") }
end
ADB.PET_ORDER = { "Diablotin", "Traqueur Corrompu", "Sanglier", "Machine" }
ADB.ALT_TYPE = "Personnage joueur"
ADB.PET_ORDER[#ADB.PET_ORDER + 1] = ADB.ALT_TYPE
ADB.PET_TYPES = {
    ["Diablotin"] = { icon = "Spell_Shadow_SummonImp", stat = 4, boost = "boostwarlockpet", pv = 7, pm = 0,
        skills = { Atk("Trait de Feu", "Spell_Fire_FlameBolt", 1, 0) } },
    ["Traqueur Corrompu"] = { icon = "Spell_Shadow_SummonFelHunter", stat = 4, boost = "boostwarlockpet", pv = 14, pm = 0,
        skills = { Atk("Morsure de traqueur", "Ability_Hunter_Pet_Wolf", 3, 0) } },
    ["Sanglier"] = { icon = "Ability_Hunter_Pet_Boar", stat = 3, boost = "boosthunterpet", pv = 18, pm = 10, pv0 = 15,
        skills = { Atk("Attaque de base", "INV_Sword_04", 1, 0),
            Atk("Charge de sanglier", "Ability_Warrior_Charge", 1, 3, 1) } },
    ["Machine"] = { icon = "INV_Misc_Gear_01", stat = 3, boost = "boosthunterpet", pv = 18, pm = 10, pv0 = 15,
        skills = { Atk("Attaque de base", "INV_Sword_04", 1, 0), Atk("Déchiquetage", "INV_Misc_Gear_03", 3, 3) } },
}

local function PetDe(nom)
    for _, x in ipairs(ADB.ListerPNJ()) do if x.owner == nom then return x end end
end
local function AltDe(nom)
    for _, x in ipairs(ADB.ListerPNJ()) do if x.owner == "+" .. nom then return x end end
end
ADB.AltDe = AltDe
function ADB.GetPet() return ADB.db and ADB.playerName and PetDe(ADB.playerName) or nil end
function ADB.PetSkills(p)
    local T = ADB.PET_TYPES[p and p.petType or ""]
    return T and T.skills or {}
end

function ADB.PetMult(T)
    local d = ADB.GetStatBlock(ADB.playerName)
    local m = ({ d.multForce, d.multAgi, d.multInt })[T.stat - 1]
    local s = ADB.TalSpeActive()
    if s and ADB.TalATag(s, T.boost) then m = m * 1.25 end
    return m
end

function ADB.PetMax(t)
    local T = ADB.PET_TYPES[t or ""]
    if not T then return 1, 0 end
    local m = ADB.PetMult(T)
    return max(1, floor((T.pv0 or 0) + T.pv * m + 0.5)), floor(T.pm * m + 0.5)
end

------------------------------------------------------------------------------
-- Synchronisation joueur -> MJ ("PS;type;nom;rp;pvMax;pmMax" / "PD")
------------------------------------------------------------------------------
local petSig, petT = nil, 0
function ADB.PetSync(force)
    local s = ADB.db.sec
    if not s or s.type == ADB.ALT_TYPE or ADB.EstMJ() or not IsInGroup() or not ADB.NomMJ() then return end
    local pv, pm = ADB.PetMax(s.type)
    local sig = format("%s;%s;%s;%d;%d", s.type, Encoder(s.nom), Encoder(s.rp or ""), pv, pm)
    local t = GetTime()
    if not force and sig == petSig and (ADB.GetPet() or t < petT + 10) then return end
    petSig, petT = sig, t
    ADB.Envoyer("PS;" .. sig)
end
hooksecurefunc(ADB, "EnvoyerEtat", function() ADB.PetSync() end)

function ADB.PetDefinir(joueur, t, nom, rp, pv, pm)
    local pn = PetDe(joueur)
    if not pn then
        if #ADB.db.pnjs >= ADB.PNJ_MAX then return end
        local id = ADB.db.pnjProchainId
        ADB.db.pnjProchainId = id + 1
        pn = { id = id, pvMax = pv, pmMax = pm, pv = pv, pm = pm, sh = 0, ally = true, owner = joueur }
        table.insert(ADB.db.pnjs, pn)
    else
        if pn.pv >= pn.pvMax then pn.pv = pv end
        if pn.pm >= pn.pmMax then pn.pm = pm end
        pn.pvMax, pn.pmMax = pv, pm
        pn.pv, pn.pm = min(pn.pv, pv), min(pn.pm, pm)
    end
    pn.nom, pn.rp, pn.petType = nom, rp ~= "" and rp or nil, t
    ADB.PlanifierPNJ(pn.id)
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
end

function ADB.RecevoirExt(cmd, nom, message)
    local p = { strsplit(";", message) }
    if cmd == "BA" or cmd == "BF" or cmd == "BT" then return ADB.BufRecevoir(cmd, nom, p) end
    if not (ADB.EstMJ() and ADB.roster[nom]) then return end
    if cmd == "PS" then
        local pnom, rp = Net(Decoder(p[3] or "")):sub(1, 30), Net(Decoder(p[4] or "")):sub(1, 40)
        if not ADB.PET_TYPES[p[2] or ""] or pnom == "" then return end
        ADB.PetDefinir(nom, p[2], pnom, rp,
            Borner(floor(tonumber(p[5]) or 1), 1, ADB.PNJ_STAT_MAX), Borner(floor(tonumber(p[6]) or 0), 0, ADB.PNJ_STAT_MAX))
    elseif cmd == "PD" then
        local pn = PetDe(nom)
        if pn then ADB.SupprimerPNJ(pn.id) end
    elseif cmd == "PM" then
        local pn, c = PetDe(nom), tonumber(p[2])
        if pn and c then ADB.AppliquerValeurPNJ(pn.id, "pm", pn.pm - Borner(floor(c), 0, 99)) end
    end
end

------------------------------------------------------------------------------
-- Menu "Personnage secondaire"
------------------------------------------------------------------------------
function ADB.PetMajMenu()
    local f = ADB.petMenu
    if not f then return end
    if f.type == ADB.ALT_TYPE then UIDropDownMenu_SetText(f.Drop, f.type) f.Info:SetText("") return end
    local T = ADB.PET_TYPES[f.type]
    UIDropDownMenu_SetText(f.Drop, f.type)
    local pv, pm = ADB.PetMax(f.type)
    local m, l = ADB.PetMult(T), { format("|cffffd100PV|r %d   |cffffd100PM|r %d", pv, pm) }
    for _, sk in ipairs(T.skills) do
        l[#l + 1] = format("|cffffd100%s|r%s : %s", sk.nom, sk.mana > 0 and (" (" .. sk.mana .. " PM)") or "",
            (ADB.TalTexte(sk.desc, true, m, 0)))
    end
    f.Info:SetText(table.concat(l, "\n"))
end

function ADB.PetSauver()
    local f = ADB.petMenu
    local nom = Net(f.Nom:GetText()):sub(1, 30)
    if nom == "" then ADB.Print("Donnez un nom de PNJ.") return end
    if f.type == ADB.ALT_TYPE then
        return ADB.AltSauver(nom, Net(f.RP:GetText()):sub(1, 40), f.aRace, f.aClasse)
    end
    if ADB.alt then ADB.AltSupprimer(true) end
    ADB.db.sec = { type = f.type, nom = nom, rp = Net(f.RP:GetText()):sub(1, 40) }
    ADB.PetSync(true)
    ADB.Print(IsInGroup() and "Personnage secondaire enregistré (envoyé au MJ)."
        or "Enregistré : envoyé au MJ dès que vous serez en groupe.")
    f:Hide()
end

function ADB.PetSupprimer()
    if ADB.alt then ADB.AltSupprimer() ADB.petMenu:Hide() return end
    if IsInGroup() and ADB.GetPet() then ADB.Envoyer("PD") end
    ADB.db.sec, petSig = nil, nil
    ADB.petMenu:Hide()
    ADB.Print("Personnage secondaire supprimé.")
end

function ADB.PetBasculerMenu()
    if ADB.EstMJ() then ADB.Print("Réservé aux joueurs.") return end
    local f = ADB.petMenu
    if not f then
        f = UI.FenetreBase("ADBPetMenu", 300, 250, "Personnage secondaire")
        ADB.petMenu = f
        f:SetPoint("CENTER", -250, 0)
        tinsert(UISpecialFrames, "ADBPetMenu")
        UI.Etiq(f, "Nom du PNJ", 16, -40)
        f.Nom = UI.Saisie(f, 120, -37, 160, 30)
        UI.Etiq(f, "(nom en jeu, sert au ciblage)", 16, -60, "GameFontDisableSmall")
        UI.Etiq(f, "Nom RP", 16, -84)
        f.RP = UI.Saisie(f, 120, -81, 160, 40)
        UI.Etiq(f, "Type", 16, -116)
        f.Drop = CreateFrame("Frame", "ADBPetTypeDrop", f, "UIDropDownMenuTemplate")
        f.Drop:SetPoint("TOPLEFT", 90, -109)
        UIDropDownMenu_SetWidth(f.Drop, 150)
        UIDropDownMenu_Initialize(f.Drop, function(self, niv)
            for _, t in ipairs(ADB.PET_ORDER) do
                local i = UIDropDownMenu_CreateInfo()
                i.text, i.checked = t, (f.type == t)
                i.func = function() f.type = t ADB.PetMajMenu() end
                UIDropDownMenu_AddButton(i, niv)
            end
        end)
        f.Info = UI.Etiq(f, "", 16, -148, "GameFontHighlightSmall")
        f.Info:SetWidth(268)
        f.Info:SetJustifyV("TOP")
        UI.Bouton(f, "Enregistrer", 16, -214, 125, ADB.PetSauver)
        UI.Bouton(f, "Supprimer", 159, -214, 125, ADB.PetSupprimer)
    end
    if f:IsShown() then f:Hide() return end
    local s = ADB.db.sec
    f.Nom:SetText(s and s.nom or "")
    f.RP:SetText(s and s.rp or "")
    f.type = s and s.type or ADB.PET_ORDER[1]
    f:Show()
    ADB.PetMajMenu()
end

------------------------------------------------------------------------------
-- Actions du familier (1 seule compétence par tour, en plus de l'action du joueur)
------------------------------------------------------------------------------
function ADB.PetEtat(p, sk)
    if ADB.phase ~= "PLAYER_TURN" then return false, "Ce n'est pas le tour des joueurs." end
    if ADB.petUsed then return false, "Le familier a déjà agi ce tour." end
    if ADB.BufA("N:" .. p.id, 4) then return false, "Votre familier est étourdi." end
    if (p.pm or 0) < sk.mana then return false, "Mana du familier insuffisant." end
    return true
end

function ADB.PetUtiliser(i)
    local p = ADB.GetPet()
    local sk = p and ADB.PetSkills(p)[i]
    if not sk then return end
    local ok, raison = ADB.PetEtat(p, sk)
    if not ok then UIErrorsFrame:AddMessage(raison, 1, 0.3, 0.3) return end
    if not UnitExists("target") then ADB.Print("Cible requise.") return end

    local e = ADB.EntreeUnite("target")
    local cible = ADB.TalCibleNom() or UnitName("target")
    local bp, bc, bd, adv = ADB.BufBonus("N:" .. p.id)
    local r, lib, c, m, echec = ADB.Jet(sk.prec, bp, bc, adv)
    local val = max(1, floor(sk.base * ADB.PetMult(ADB.PET_TYPES[p.petType]) * bd + 0.5)) * m

    if sk.mana > 0 then
        p.pm = max(0, (p.pm or 0) - sk.mana)
        ADB.Envoyer("PM;" .. sk.mana)
    end
    ADB.petUsed = true

    local msg = format("%s (familier de %s) a utilisé %s sur %s. Jet de précision : %d (%s).",
        ADB.PNJNom(p), ADB.NomAffiche(ADB.playerName), sk.nom, cible, r, lib)
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
-- Cadres réduits (style cadres de groupe)
------------------------------------------------------------------------------
ADB.petMinis, ADB.altMinis = {}, {}

local function MiniBarre(f, y)
    local b = CreateFrame("StatusBar", nil, f, "ADBBarTemplate")
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 47, y)
    b:SetSize(70, 7)
    b:SetStatusBarTexture(TEX .. "UI-StatusBar")
    b.blizz = true
    local st = b:GetStatusBarTexture()
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= st and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    b.Text:SetFontObject(GameFontHighlightSmall)
    b.Text:Hide()
    b:HookScript("OnEnter", function(s) s.Text:Show() end)
    b:HookScript("OnLeave", function(s) s.Text:Hide() end)
    return b
end

local function CreerMini(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(120, 53)
    f:SetScale(0.8)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)
    local fond = f:CreateTexture(nil, "BACKGROUND")
    fond:SetColorTexture(0, 0, 0, 0.5)
    fond:SetSize(71, 18)
    fond:SetPoint("TOPLEFT", 46, -11)
    f.Icon = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.Icon:SetSize(37, 37)
    f.Icon:SetPoint("TOPLEFT", 7, -6)
    f.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local a = CreateFrame("Frame", nil, f)
    a:SetAllPoints()
    a:SetFrameLevel(f:GetFrameLevel() + 5)
    a:EnableMouse(false)
    local t = a:CreateTexture(nil, "ARTWORK")
    t:SetSize(128, 64)
    t:SetPoint("TOPLEFT")
    t:SetTexture(TEX .. "UI-PartyFrame")
    f.Name = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.Name:SetSize(70, 12)
    f.Name:SetJustifyH("LEFT")
    f.Name:SetWordWrap(false)
    f.Name:SetPoint("TOPLEFT", 46, -1)
    f.HP = MiniBarre(f, -12)
    f.HP.kind = "pv"
    f.MP = MiniBarre(f, -20)
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
        local parent, prev = c[1], nil
        for k = 1, 2 do
            local p = (k == 1 and AltDe or PetDe)(c[2])
            if p then
                local reg = k == 1 and ADB.altMinis or ADB.petMinis
                local m = reg[parent]
                if not m then m = CreerMini(parent) reg[parent] = m end
                m:ClearAllPoints()
                if prev then m:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                elseif c[3] then m:SetPoint("LEFT", parent, "RIGHT", 2, 0)
                else m:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 10, 0) end
                prev = m
                m.npcId = p.id
                m.HP.npcId, m.MP.npcId = nil, nil
                if k == 1 then
                    if m.alt ~= p.nom then
                        m.alt = p.nom
                        m.Icon:SetTexture(IconeTex("INV_Misc_QuestionMark"))
                        m.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    end
                else
                    local T = ADB.PET_TYPES[p.petType or ""]
                    m.Icon:SetTexture(IconeTex(T and T.icon or "INV_Misc_QuestionMark"))
                end
                m.Name:SetText("|cff40ff40" .. ADB.PNJNom(p) .. "|r")
                ADB.MajBarre(m.HP, p.pv, p.pvMax, p.sh)
                ADB.MajBarre(m.MP, p.pm, p.pmMax)
                m.MP:SetShown(p.pmMax > 0)
                m:Show()
                vus[m] = true
            end
        end
    end
    for _, reg in ipairs({ ADB.petMinis, ADB.altMinis }) do
        for _, m in pairs(reg) do
            if not vus[m] then m.npcId = nil m:Hide() end
        end
    end
end

------------------------------------------------------------------------------
-- Barre de compétences du familier
------------------------------------------------------------------------------
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
        GameTooltip:AddLine("Précision : " .. sk.prec, 1, 1, 1)
        if sk.mana > 0 then GameTooltip:AddLine("Coût : " .. sk.mana .. " Mana (familier)", 0.3, 0.55, 1) end
        GameTooltip:AddLine((ADB.TalTexte(sk.desc, true, ADB.PetMult(ADB.PET_TYPES[p.petType]), 0)), 1, 0.9, 0.6, true)
        local ok, raison = ADB.PetEtat(p, sk)
        if not ok then GameTooltip:AddLine(raison, 1, 0.2, 0.2, true) end
        GameTooltip:Show()
    end)
    ADB.petBar.btns[i] = b
    return b
end

function ADB.PetRafraichir()
    local bar = ADB.petBar
    if not bar or not ADB.db or not ADB.playerName then return end
    local p = ADB.GetPet()
    ADB.PetMinis()
    local liste = p and ADB.PetSkills(p) or {}
    if #liste == 0 or ADB.EstMJ() or ADB.phase == "IDLE" then bar:Hide() return end
    bar:ClearAllPoints()
    if ADB.barre then bar:SetPoint("BOTTOM", ADB.barre, "TOP", 0, 6)
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 210) end
    bar:SetSize(#liste * 31 + 13, 44)
    for i, sk in ipairs(liste) do
        local b = bar.btns[i] or CreerBtn(i)
        local ok = ADB.PetEtat(p, sk)
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
    local s = ADB.db.sec
    if type(s) == "table" and (ADB.PET_TYPES[s.type or ""] or s.type == ADB.ALT_TYPE) and type(s.nom) == "string" and Net(s.nom) ~= "" then
        s.nom, s.rp = Net(s.nom):sub(1, 30), Net(s.rp or ""):sub(1, 40)
    else
        ADB.db.sec = nil
    end
    ADB.db.pet = nil
    for _, p in ipairs(ADB.db.pnjs) do   -- migration : anciens familiers
        if p.owner and p.owner:sub(1, 1) ~= "+" and not ADB.PET_TYPES[p.petType or ""] then p.owner, p.petType = nil, nil end
    end
    ADB.PetRafraichir()
end

hooksecurefunc(ADB, "RafraichirNPC", function() ADB.PetRafraichir() end)

local dernierePhase = "IDLE"
hooksecurefunc(ADB, "PhaseCombat", function()
    local ph = ADB.phase
    if ph == dernierePhase then return end
    dernierePhase = ph
    if ph == "PLAYER_TURN" or ph == "IDLE" then ADB.petUsed = nil end
    ADB.PetRafraichir()
end)

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
        ADB.PetBasculerMenu()
    elseif cmd == "buff" or cmd == "debuff" then
        ADB.BufCommande(reste)
    else
        oSlash(msg)
    end
end