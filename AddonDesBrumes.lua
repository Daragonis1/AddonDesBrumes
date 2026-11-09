------------------------------------------------------------------------------
-- Addon des Brumes  -  Pacte des Brumes  (v1.3)
-- Cible : World of Warcraft 9.2.7 (Shadowlands)  -  API native (sans Ace)
------------------------------------------------------------------------------
ADB = ADB or {}
local ADB = ADB

local floor, min, max = math.floor, math.min, math.max
local format = string.format

------------------------------------------------------------------------------
-- 1. CONSTANTES
------------------------------------------------------------------------------
ADB.PREFIX = "AddonDesBrumes"
ADB.STAT_FINALE_MAX = 9999
ADB.MEMBRES_PAR_COLONNE = 5
ADB.DELAI_DIFFUSION = 0.5
ADB.DELAI_SYNC_PNJ = 1.0
ADB.DELAI_CHAT = 1.5
ADB.NOM_MAX = 30
ADB.PNJ_MAX = 20
ADB.PNJ_STAT_MAX = 9999
ADB.XP_MAX_ENVOI = 100000
ADB.Arrondir = floor

ADB.INV_SLOTS = 16
ADB.OR_MAX = 99999999
ADB.ITEM_NOM_MAX = 24
ADB.ITEM_COMP_MAX = 50
ADB.POTION_SOIN = 12
ADB.BONUS_RATION = 10
ADB.SHIELD_MAX = 999
ADB.CMD_PH = { CS = "STARTING", CP = "PLAYER_TURN", CA = "ALLY_TURN", CE = "ENEMY_TURN", CF = "IDLE" }
ADB.BAN = {
    STARTING = "Début du Combat - Tour par Tour",
    PLAYER_TURN = "Tour des Joueurs",
    ALLY_TURN = "Tour des Alliés",
    ENEMY_TURN = "Tour des Ennemis",
    IDLE = "Fin du Combat"
}
ADB.MJ_NOM = "Istriä"

ADB.XP_SEUILS = { 0, 10, 30, 60, 100, 150, 210, 280, 360, 450, 550, 660, 780, 910,
    1050, 1200, 1360, 1530, 1710, 2000 }
ADB.NIVEAU_MAX = #ADB.XP_SEUILS

ADB.RACES = {
    { "Humain",  10, 10, 15 }, { "Gnome", 10, 10, 15 }, { "Elfe de sang", 10, 10, 15 },
    { "Gobelin", 10, 10, 15 }, { "Troll", 10, 10, 15 }, { "Réprouvé", 10, 10, 15 },
    { "Elfe de la nuit", 10, 15, 10 }, { "Hozen", 10, 15, 10 },
    { "Nain",            15, 10, 10 }, { "Draenei", 15, 10, 10 }, { "Worgen", 15, 10, 10 },
    { "Tauren", 15, 10, 10 }, { "Orc", 15, 10, 10 }, { "Dragon Noir", 15, 10, 10 },
    { "Ogre",   15, 10, 10 }, { "Ogre Magi", 15, 10, 10 },
}
ADB.CLASSES = {
    { "Guerrier",             10, 0,  0 }, { "Chaman", 10, 0, 0 }, { "Paladin", 10, 0, 0 },
    { "Chevalier de la Mort", 10, 0,  0 },
    { "Chasseur",             0,  10, 0 }, { "Voleur", 0, 10, 0 }, { "Moine", 0, 10, 0 },
    { "Chasseur de démons", 0, 10, 0 },
    { "Démoniste",          0, 0,  10 }, { "Druide", 0, 0, 10 }, { "Mage", 0, 0, 10 },
    { "Prêtre", 0, 0, 10 },
}
ADB.MJ_CLASSE = "Boss et Évènements"
ADB.CLASSES[#ADB.CLASSES + 1] = { ADB.MJ_CLASSE, 0, 0, 0 }
ADB.EQUIP_CLASSE = "Équipements"
ADB.CLASSES[#ADB.CLASSES + 1] = { ADB.EQUIP_CLASSE, 0, 0, 0 }
function ADB.ClasseSpeciale(n) return n == ADB.MJ_CLASSE or n == ADB.EQUIP_CLASSE end

ADB.RACE_MAP, ADB.CLASSE_MAP = {}, {}
for _, r in ipairs(ADB.RACES) do ADB.RACE_MAP[r[1]] = { r[2], r[3], r[4] } end
for _, c in ipairs(ADB.CLASSES) do ADB.CLASSE_MAP[c[1]] = { c[2], c[3], c[4] } end

ADB.SLOTS = { { "arme", "Arme" }, { "tete", "Tête" }, { "haut", "Haut" },
    { "bas",  "Bas" }, { "bijou", "Bijou" } }
ADB.SLOT_NOM = {}
for _, s in ipairs(ADB.SLOTS) do ADB.SLOT_NOM[s[1]] = s[2] end

-- { nom, r, g, b, cap de stats, hex }
ADB.RARETES = {
    { "Commun",     1,    1,    1,    2,  "ffffff" },
    { "Peu Commun", 0.12, 1,    0,    4,  "1eff00" },
    { "Rare",       0,    0.44, 0.87, 8,  "0070dd" },
    { "Épique",     0.64, 0.21, 0.93, 12, "a335ee" },
}
ADB.STAT_NOMS = { "Force", "Agilité", "Intelligence" }

ADB.CONSO = {
    potvie = {
        nom = "Potion de Vie",
        icon = "INV_Potion_54",
        stack = 1,
        desc = "Restaure 12 PV."
    },
    potmana = {
        nom = "Potion de mana",
        icon = "INV_Potion_76",
        stack = 1,
        desc = "Restaure 12 PM."
    },
    ration = {
        nom = "Ration",
        icon = "INV_Misc_Food_14",
        stack = 5,
        desc = "Quand vous vous reposez, mange automatiquement une Ration pour récupérer plus."
    },
}

ADB.DEFAUTS = {
    xp = 0,
    level = 1,
    race = "Humain",
    classe = "Guerrier",
    base = { force = 0, agilite = 0, intelligence = 0 },
    nomRP = "",
    uiRemplacee = true,
    minimap = { angle = 200 },
    pnjs = {},
    pnjProchainId = 1,
    pc = 0,
    sh = 0,
    inv = {},
    equip = {},
    talents = { arbres = {}, appris = {}, cd = {} },
}

ADB.roster = {}
ADB.membres = {}
ADB.pnjFrames = {}
ADB.pnjRecus = {}
ADB.pnjSource = nil
ADB.pnjModifies = {}
ADB.pvAgreg = {}
ADB.phase = "IDLE"
ADB.finis = {}
ADB.nbLignes = 0
ADB.Evenements = {}

------------------------------------------------------------------------------
-- 2. OUTILS
------------------------------------------------------------------------------
local function Borner(v, a, b) return max(a, min(b, v)) end

local function NettoyerNom(s)
    s = tostring(s or "")
    s = s:gsub("%c", "")
    s = s:gsub("|", "")
    return strtrim(s)
end

local function Encoder(s)
    return (s:gsub("[%%;]", function(c) return format("%%%02X", c:byte()) end))
end
local function Decoder(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
ADB.Encoder, ADB.Decoder, ADB.Borner, ADB.NettoyerNom = Encoder, Decoder, Borner, NettoyerNom
local function IconeTex(icon)
    if tonumber(icon) then return tonumber(icon) end
    return "Interface\\Icons\\" .. icon
end

local function NetSk(s)
    local r, vus = {}, {}
    local src = type(s) == "table" and table.concat(s, ",") or tostring(s or "")
    for w in src:gmatch("%d+") do
        local id = floor(tonumber(w))
        if id >= 1 and id <= 99999 and not vus[id] and #r < 3 then
            vus[id] = true
            r[#r + 1] = id
        end
    end
    return r
end

-- Valide / nettoie un objet (local ou recu par message). Retourne nil si invalide.
local function ValiderItem(t)
    if type(t) ~= "table" then return nil end
    local def = ADB.CONSO[t.kind]
    if def then
        return { kind = t.kind, count = Borner(floor(tonumber(t.count) or 1), 1, def.stack) }
    end
    if t.kind == "story" then
        local icon = tostring(t.icon or "")
        if #icon == 0 or #icon > 40 or icon:find("[^%w_]") then icon = "INV_Misc_QuestionMark" end
        local nom = NettoyerNom(t.nom)
        if nom == "" then nom = "Objet" end
        return {
            kind = "story",
            rar = Borner(floor(tonumber(t.rar) or 1), 1, 4),
            icon = icon,
            nom = nom,
            desc = NettoyerNom(t.desc):sub(1, 400),
            tags = ADB.TalNetTags(t.tags),
        }
    end
    if t.kind ~= "equip" or not ADB.SLOT_NOM[t.slot] then return nil end
    local rar = Borner(floor(tonumber(t.rar) or 1), 1, 4)
    local st, tot = {}, 0
    for i = 1, 3 do
        st[i] = Borner(floor(tonumber((type(t.st) == "table" and t.st[i]) or 0) or 0), 0, 12)
        tot = tot + st[i]
    end
    if tot > ADB.RARETES[rar][5] then return nil end
    local icon = tostring(t.icon or "")
    if #icon == 0 or #icon > 40 or icon:find("[^%w_]") then icon = "INV_Misc_QuestionMark" end
    local nom = NettoyerNom(t.nom)
    if nom == "" then nom = "Objet" end
    return {
        kind = "equip",
        slot = t.slot,
        rar = rar,
        st = st,
        icon = icon,
        nom = nom,
        comp = NettoyerNom(t.comp),
        sk = NetSk(t.sk),
        tags = ADB.TalNetTags(t.tags),
    }
end

ADB.ValiderItem = ValiderItem

function ADB.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9d6bff[Brumes]|r " .. msg)
end

function ADB.AppliquerFond(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.02, 0.1, 0.85)
    f:SetBackdropBorderColor(0.55, 0.35, 0.85, 1)
end

function ADB.InitCadre(f)
    ADB.AppliquerFond(f)
    if f.NameText then f.NameText:SetWordWrap(false) end
end

function ADB.FormatOr(pc)
    pc = floor(tonumber(pc) or 0)
    return format("|cffffd700%d Po|r |cffc7c7cf%d Pa|r |cffeda55f%d Pc|r",
        floor(pc / 10000), floor((pc % 10000) / 100), pc % 100)
end

------------------------------------------------------------------------------
-- 3. DONNEES & FORMULES
------------------------------------------------------------------------------
function ADB.NiveauPourXP(xp)
    xp = tonumber(xp) or 0
    local niv = 1
    for i, seuil in ipairs(ADB.XP_SEUILS) do
        if xp >= seuil then niv = i else break end
    end
    return niv
end

function ADB.BonusEquip(s)
    local e = { 0, 0, 0 }
    if type(s.equip) == "table" then
        for _, it in pairs(s.equip) do
            if type(it) == "table" and type(it.st) == "table" then
                for i = 1, 3 do e[i] = e[i] + (tonumber(it.st[i]) or 0) end
            end
        end
    end
    return e
end

-- FinalStat = Base + Race + Classe + (Niveau - 1) + Equipement.
function ADB.StatsFinales(s)
    local r = ADB.RACE_MAP[s.race] or ADB.RACE_MAP["Humain"]
    local c = ADB.CLASSE_MAP[s.classe] or ADB.CLASSE_MAP["Guerrier"]
    local b = type(s.base) == "table" and s.base or {}
    local niv = max(1, floor(tonumber(s.level) or 1)) - 1
    local e = ADB.BonusEquip(s)
    local function f(cle, i)
        return Borner(floor((tonumber(b[cle]) or 0) + r[i] + c[i] + niv + e[i]),
            0, ADB.STAT_FINALE_MAX)
    end
    return f("force", 1), f("agilite", 2), f("intelligence", 3)
end

local function InitialiserDB()
    AddonDesBrumesDB = AddonDesBrumesDB or {}
    local db = AddonDesBrumesDB

    for cle, valeur in pairs(ADB.DEFAUTS) do
        if db[cle] == nil then
            db[cle] = (type(valeur) == "table") and CopyTable(valeur) or valeur
        end
    end
    if type(db.minimap) ~= "table" then db.minimap = CopyTable(ADB.DEFAUTS.minimap) end
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = ADB.DEFAUTS.minimap.angle end
    db.nomRP = NettoyerNom(db.nomRP)

    db.bonusForce, db.bonusAgi, db.bonusInt = nil, nil, nil

    if not ADB.RACE_MAP[db.race] then db.race = "Humain" end
    if not ADB.CLASSE_MAP[db.classe] or ADB.ClasseSpeciale(db.classe) then db.classe = "Guerrier" end
    if type(db.base) ~= "table" then db.base = CopyTable(ADB.DEFAUTS.base) end
    for _, k in ipairs({ "force", "agilite", "intelligence" }) do
        db.base[k] = tonumber(db.base[k]) or 0
    end
    db.xp = max(0, floor(tonumber(db.xp) or 0))
    db.level = ADB.NiveauPourXP(db.xp)
    db.pc = Borner(floor(tonumber(db.pc) or 0), 0, ADB.OR_MAX)
    db.sh = Borner(floor(tonumber(db.sh) or 0), 0, ADB.SHIELD_MAX)

    local inv = {}
    if type(db.inv) == "table" then
        for i = 1, ADB.INV_SLOTS do
            local it = ValiderItem(db.inv[i])
            if it then inv[i] = it end
        end
    end
    db.inv = inv
    local eq = {}
    if type(db.equip) == "table" then
        for _, s in ipairs(ADB.SLOTS) do
            local it = ValiderItem(db.equip[s[1]])
            if it and it.kind == "equip" and it.slot == s[1] then eq[s[1]] = it end
        end
    end
    db.equip = eq

    local valides, maxId = {}, 0
    if type(db.pnjs) == "table" then
        for _, p in ipairs(db.pnjs) do
            if type(p) == "table" and tonumber(p.id) and tonumber(p.pvMax) and tonumber(p.pmMax)
                and #valides < ADB.PNJ_MAX then
                local pvMax = Borner(floor(p.pvMax), 1, ADB.PNJ_STAT_MAX)
                local pmMax = Borner(floor(p.pmMax), 0, ADB.PNJ_STAT_MAX)
                local nom = NettoyerNom(p.nom)
                if nom == "" then nom = "PNJ" end
                local id = floor(p.id)
                valides[#valides + 1] = {
                    id = id,
                    nom = nom,
                    pvMax = pvMax,
                    pmMax = pmMax,
                    pv = Borner(floor(tonumber(p.pv) or pvMax), 0, pvMax),
                    pm = Borner(floor(tonumber(p.pm) or pmMax), 0, pmMax),
                    sh = Borner(floor(tonumber(p.sh) or 0), 0, ADB.SHIELD_MAX),
                    ally = p.ally == true,
                    owner = (type(p.owner) == "string" and p.owner ~= "") and NettoyerNom(p.owner) or nil,
                    rp = (type(p.rp) == "string" and NettoyerNom(p.rp) ~= "") and NettoyerNom(p.rp):sub(1, 40) or nil,
                    petType = ADB.PET_TYPES[p.petType or ""] and p.petType or nil,
                }
                maxId = max(maxId, id)
            end
        end
    end
    db.pnjs = valides
    if type(db.pnjProchainId) ~= "number" or db.pnjProchainId <= maxId then
        db.pnjProchainId = maxId + 1
    end

    local fo, ag, it = ADB.StatsFinales(db)
    local pvMax, pmMax = ADB.Calculer(fo, ag, it)
    if db.pv == nil then db.pv = pvMax end
    if db.pm == nil then db.pm = pmMax end
    db.pv = Borner(db.pv, 0, pvMax)
    db.pm = Borner(db.pm, 0, pmMax)
    ADB.TalInitDB(db)
    ADB.db = db
end

function ADB.Calculer(force, agilite, intelligence)
    local pvMax = ADB.Arrondir(15 + force / 2.5 + agilite / 5)
    local pmMax = ADB.Arrondir(5 + intelligence / 2.5 + agilite / 5)
    return pvMax, pmMax, force / 40, agilite / 40, intelligence / 40
end

function ADB.NomAffiche(nom)
    if not nom then return "" end
    local src
    if nom == ADB.playerName then src = ADB.db else src = ADB.roster[nom] end
    local rp = src and src.nomRP
    if rp and rp ~= "" then return rp end
    return nom
end

local function SourceLocale()
    local db = ADB.db
    local fo, ag, it = ADB.StatsFinales(db)
    return {
        force = fo,
        agilite = ag,
        intelligence = it,
        pv = db.pv,
        pm = db.pm,
        nomRP = db.nomRP,
        race = db.race,
        classe = db.classe,
        xp = db.xp,
        level = db.level,
        pc = db.pc,
        sh = db.sh,
    }
end

function ADB.GetStatBlock(nom)
    local src
    if nom == ADB.playerName then
        if not ADB.db then return nil end
        src = SourceLocale()
    else
        src = ADB.roster[nom]
    end
    if not src then return nil end

    local pvMax, pmMax, mf, ma, mi = ADB.Calculer(src.force, src.agilite, src.intelligence)
    return {
        nom = nom,
        nomRP = src.nomRP,
        race = src.race,
        classe = src.classe,
        xp = src.xp or 0,
        level = src.level or 1,
        pc = src.pc or 0,
        sh = src.sh or 0,
        force = src.force,
        agilite = src.agilite,
        intelligence = src.intelligence,
        pv = Borner(src.pv, 0, pvMax),
        pm = Borner(src.pm, 0, pmMax),
        pvMax = pvMax,
        pmMax = pmMax,
        multForce = mf,
        multAgi = ma,
        multInt = mi,
    }
end

-- Applique une modification de fiche et ajuste PV/PM (pleins => suivent le max).
local function ModifierFiche(fn)
    local db = ADB.db
    local avant = ADB.GetStatBlock(ADB.playerName)
    fn(db)
    local apres = ADB.GetStatBlock(ADB.playerName)
    if db.pv >= avant.pvMax then db.pv = apres.pvMax end
    if db.pm >= avant.pmMax then db.pm = apres.pmMax end
    db.pv = Borner(db.pv, 0, apres.pvMax)
    db.pm = Borner(db.pm, 0, apres.pmMax)
    ADB.ApresChangementLocal()
end

function ADB.DefinirRace(nom)
    if not ADB.RACE_MAP[nom] then return end
    ModifierFiche(function(db) db.race = nom end)
end

function ADB.DefinirClasse(nom)
    if not ADB.CLASSE_MAP[nom] or ADB.ClasseSpeciale(nom) then return end
    ModifierFiche(function(db) db.classe = nom end)
end

function ADB.DefinirNomRP(texte)
    local nouveau = NettoyerNom(texte)
    if nouveau == (ADB.db.nomRP or "") then return end
    ADB.db.nomRP = nouveau
    ADB.ApresChangementLocal()
end

function ADB.ApresChangementLocal()
    ADB.RafraichirTout()
    ADB.PlanifierDiffusion()
end

------------------------------------------------------------------------------
-- 4. GROUPE & ROLES
------------------------------------------------------------------------------
function ADB.ListerUnites()
    local unites = {}
    if not IsInGroup() then return unites end
    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do unites[#unites + 1] = "raid" .. i end
    else
        for i = 1, n - 1 do unites[#unites + 1] = "party" .. i end
    end
    return unites
end

function ADB.NomMJ()
    if not IsInGroup() then
        return UnitName("player") == ADB.MJ_NOM and ADB.MJ_NOM or nil
    end
    local units = { "player" }
    for _, u in ipairs(ADB.ListerUnites()) do units[#units + 1] = u end
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitName(u) == ADB.MJ_NOM then return ADB.MJ_NOM end
    end
    return nil
end

function ADB.EstMJ()
    local mj = ADB.NomMJ()
    return mj ~= nil and mj == UnitName("player")
end

function ADB.EstNomMJ(nom)
    local mj = ADB.NomMJ()
    return mj ~= nil and mj == nom
end

function ADB.NomsGroupe()
    local t = { [ADB.playerName] = true }
    for _, u in ipairs(ADB.ListerUnites()) do
        local n = UnitName(u)
        if n then t[n] = true end
    end
    return t
end

function ADB.MembreAffichable(unit, nom)
    return (nom and nom ~= UNKNOWNOBJECT and unit and UnitExists(unit)
        and UnitIsConnected(unit) and ADB.roster[nom] ~= nil) and true or false
end

function ADB.ListerMembresAffiches()
    local res = {}
    for _, u in ipairs(ADB.ListerUnites()) do
        if UnitExists(u) and not UnitIsUnit(u, "player") and not ADB.EstNomMJ(UnitName(u)) then
            local nom = UnitName(u)
            if ADB.MembreAffichable(u, nom) then
                res[#res + 1] = { unit = u, nom = nom }
            end
        end
    end
    return res
end

function ADB.PeutModifier(nom)
    if not nom then return false end
    if ADB.EstMJ() then return nom == ADB.playerName or ADB.roster[nom] ~= nil end
    return not IsInGroup() and nom == ADB.playerName
end

-- Joueur cible (soi-meme ou membre du groupe avec l'addon), sinon nil.
function ADB.CibleJoueur()
    if not UnitExists("target") or not UnitIsPlayer("target") then return nil end
    local n = UnitName("target")
    if n == ADB.playerName or ADB.roster[n] then return n end
    return nil
end

------------------------------------------------------------------------------
-- 5. SYNCHRONISATION (messages d'addon)
--   "S;force;agi;int;pv;pm;nomRP;niveau;xp;race;classe;pc" : etat complet
--   "Q" / "SET;cible;pv|pm;valeur" / "XP;cible;montant" / "XPALL;montant"
--   "REST;pourcent" / "N;..." "ND;id" "NC" "NS" "NE" : PNJ
--   "GOLD;cible;montant" "GOLDM;cible;montant" : or (MJ)
--   "IE;cible;slot;rar;icone;s1;s2;s3;nom;comp" : equipement (MJ)
--   "IC;cible;kind;qte" : consommable (MJ)
------------------------------------------------------------------------------
function ADB.Envoyer(msg)
    if not IsInGroup() then return end
    local canal = "PARTY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        canal = "INSTANCE_CHAT"
    elseif IsInRaid() then
        canal = "RAID"
    end
    C_ChatInfo.SendAddonMessage(ADB.PREFIX, msg, canal)
end

function ADB.EnvoyerEtat()
    local db = ADB.db
    local d = ADB.GetStatBlock(ADB.playerName)
    ADB.Envoyer(format("S;%d;%d;%d;%d;%d;%s;%d;%d;%s;%s;%d;%d",
        d.force, d.agilite, d.intelligence, d.pv, d.pm, Encoder(db.nomRP or ""),
        db.level, db.xp, Encoder(db.race), Encoder(db.classe), db.pc, d.sh))
end

function ADB.PlanifierDiffusion(demander)
    if demander then ADB.demandePlanifiee = true end
    if ADB.diffusionPlanifiee then return end
    ADB.diffusionPlanifiee = true
    C_Timer.After(ADB.DELAI_DIFFUSION, function()
        ADB.diffusionPlanifiee = false
        if ADB.demandePlanifiee then
            ADB.demandePlanifiee = false
            ADB.Envoyer("Q")
        end
        ADB.EnvoyerEtat()
    end)
end

function ADB.Evenements.CHAT_MSG_ADDON(prefixe, message, canal, expediteur)
    if prefixe ~= ADB.PREFIX then return end
    local nom = Ambiguate(expediteur, "short")
    if nom == ADB.playerName then return end

    local cmd, a, b, c, d, e, f, g, h, k, l, m, n = strsplit(";", message)

    if cmd == "S" then
        local fo, ag, it, pv, pm = tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e)
        if fo and ag and it and pv and pm then
            local nouveau = (ADB.roster[nom] == nil)
            local rp = ""
            if f and #f <= 130 then rp = NettoyerNom(Decoder(f)) end
            local xp = max(0, floor(tonumber(h) or 0))
            local race = k and Decoder(k) or ""
            local classe = l and Decoder(l) or ""
            if not ADB.RACE_MAP[race] then race = "" end
            if not ADB.CLASSE_MAP[classe] then classe = "" end
            ADB.roster[nom] = {
                force = Borner(floor(fo), 0, ADB.STAT_FINALE_MAX),
                agilite = Borner(floor(ag), 0, ADB.STAT_FINALE_MAX),
                intelligence = Borner(floor(it), 0, ADB.STAT_FINALE_MAX),
                pv = max(0, floor(pv)),
                pm = max(0, floor(pm)),
                nomRP = rp,
                xp = xp,
                level = ADB.NiveauPourXP(xp),
                race = race,
                classe = classe,
                pc = Borner(floor(tonumber(m) or 0), 0, ADB.OR_MAX),
                sh = Borner(floor(tonumber(n) or 0), 0, ADB.SHIELD_MAX),
            }
            if nouveau then ADB.MiseEnPageGroupe() end
            ADB.RafraichirTout()
        end
    elseif cmd == "Q" then
        ADB.PlanifierDiffusion()
        if ADB.EstMJ() then ADB.PlanifierPNJComplet() end
    elseif cmd == "SET" then
        local valeur = tonumber(c)
        if a == ADB.playerName and (b == "pv" or b == "pm" or b == "sh" or b == "pvx") and valeur and ADB.EstNomMJ(nom) then
            ADB.AppliquerValeur(ADB.playerName, b == "pvx" and "pv" or b, valeur, true, b == "pvx")
        end
    elseif cmd == "XP" then
        local montant = tonumber(b)
        if a == ADB.playerName and montant and ADB.EstNomMJ(nom) then ADB.RecevoirXP(montant) end
    elseif cmd == "XPALL" then
        local montant = tonumber(a)
        if montant and ADB.EstNomMJ(nom) then ADB.RecevoirXP(montant) end
    elseif cmd == "REST" then
        local pct = tonumber(a)
        if pct and ADB.EstNomMJ(nom) then ADB.RecevoirRepos(pct) end
    elseif cmd == "GOLD" or cmd == "GOLDM" then
        local mt = tonumber(b)
        if a == ADB.playerName and mt and ADB.EstNomMJ(nom) then
            mt = Borner(floor(mt), 1, ADB.OR_MAX)
            if cmd == "GOLD" then
                ADB.ModifierOr(mt)
                ADB.Print("Vous avez reçu " .. ADB.FormatOr(mt) .. ".")
            else
                mt = min(mt, ADB.db.pc)
                ADB.ModifierOr(-mt)
                ADB.Print("Le MJ vous a retiré " .. ADB.FormatOr(mt) .. ".")
            end
        end
    elseif cmd == "IE" then
        if a == ADB.playerName and ADB.EstNomMJ(nom) then
            local it = ValiderItem({
                kind = "equip",
                slot = b,
                rar = tonumber(c),
                icon = d,
                st = { tonumber(e), tonumber(f), tonumber(g) },
                nom = Decoder(h or ""),
                comp = Decoder(k or ""),
                sk = l,
                tags = m,
            })
            if it then ADB.RecevoirObjet(it, 1) end
        end
    elseif cmd == "IC" then
        local q = tonumber(c)
        if a == ADB.playerName and q and ADB.CONSO[b or ""] and ADB.EstNomMJ(nom) then
            ADB.RecevoirObjet({ kind = b }, Borner(floor(q), 1, 20))
        end
    elseif ADB.CMD_PH[cmd] then
        if ADB.EstNomMJ(nom) and not ADB.EstMJ() then ADB.PhaseCombat(ADB.CMD_PH[cmd]) end
    elseif cmd == "CD" then
        if ADB.EstMJ() and ADB.phase == "PLAYER_TURN" then
            ADB.finis[nom] = true
            ADB.MajCombatUI()
            ADB.VerifierFinJoueurs()
        end
    elseif cmd == "EF" or cmd == "DG" then
        ADB.RecevoirMesure(cmd, nom, message)
    elseif ADB.CMD_TAL[cmd] then
        ADB.RecevoirTalent(cmd, nom, message)
    elseif ADB.CMD_EXT[cmd] then
        ADB.RecevoirExt(cmd, nom, message)
    elseif cmd == "N" or cmd == "ND" or cmd == "NC" or cmd == "NS" or cmd == "NE" then
        ADB.RecevoirPNJ(cmd, nom, a, b, c, d, e, f, g, h, k, l, m)
    end
end

------------------------------------------------------------------------------
-- 5b. XP, NIVEAUX & REPOS
------------------------------------------------------------------------------
function ADB.RecevoirXP(montant)
    montant = Borner(floor(montant), -ADB.XP_MAX_ENVOI, ADB.XP_MAX_ENVOI)
    if montant == 0 then return end
    local ancien = ADB.db.level
    ModifierFiche(function(db)
        db.xp = max(0, db.xp + montant)
        db.level = ADB.NiveauPourXP(db.xp)
    end)
    ADB.Print(montant > 0 and format("Vous avez reçu %d points d'expérience.", montant)
        or format("Vous avez perdu %d points d'expérience.", -montant))
    if ADB.db.level > ancien then
        ADB.Print(format("Vous passez au niveau %d !", ADB.db.level))
    elseif ADB.db.level < ancien then
        ADB.Print(format("Vous retombez au niveau %d.", ADB.db.level))
    end
end

function ADB.RecevoirRepos(pct)
    pct = Borner(floor(pct), 0, 100)
    if ADB.RetirerConso("ration") then
        pct = min(100, pct + ADB.BONUS_RATION)
        ADB.Print(format("Vous avez mangé une Ration : +%d%% de récupération.", ADB.BONUS_RATION))
    else
        ADB.Print("Votre repos n'a pas été réparateur car vous n'avez pas mangé à votre faim")
    end
    local db = ADB.db
    local d = ADB.GetStatBlock(ADB.playerName)
    db.pv = min(d.pvMax, db.pv + floor(d.pvMax * pct / 100 + 0.5))
    db.pm = min(d.pmMax, db.pm + floor(d.pmMax * pct / 100 + 0.5))
    ADB.Print(format("Le repos vous a restauré %d%% de vos PV et PM.", pct))
    ADB.TalRepos()
    ADB.ApresChangementLocal()
end

function ADB.OuvrirMJ()
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ (chef de groupe) peut utiliser cet outil.")
        return
    end
    ADBMJFrame:Show()
end

local function LireXP()
    local v = tonumber(ADBMJFrame.XPEdit:GetText())
    if not v or floor(v) == 0 then
        ADB.Print("Montant d'XP invalide (1 à " .. ADB.XP_MAX_ENVOI .. ").")
        return nil
    end
    return Borner(floor(v), -ADB.XP_MAX_ENVOI, ADB.XP_MAX_ENVOI)
end

function ADB.XPCible()
    if not ADB.EstMJ() then return end
    if not UnitExists("target") or not UnitIsPlayer("target") then
        ADB.Print("Ciblez d'abord un joueur.")
        return
    end
    local m = LireXP()
    if not m then return end
    local nom = UnitName("target")
    if nom == ADB.playerName then
        ADB.RecevoirXP(m)
    elseif ADB.roster[nom] then
        ADB.Envoyer(format("XP;%s;%d", nom, m))
        ADB.Print(format("%d XP envoyés à %s.", m, ADB.NomAffiche(nom)))
    else
        ADB.Print(nom .. " n'a pas l'addon (aucune fiche reçue).")
    end
end

function ADB.XPGroupe()
    if not ADB.EstMJ() then return end
    local m = LireXP()
    if not m then return end
    ADB.Envoyer(format("XPALL;%d", m))
    ADB.Print(format("%d XP envoyés au groupe.", m))
end

function ADB.PourcentRepos()
    local f = ADBRestFrame
    local n = 0
    for _, cb in ipairs({ f.Securise, f.Confortable }) do
        if cb:GetChecked() then n = n + 1 end
    end
    return 10 + 10 * n
end

function ADB.RafraichirRepos()
    local f = ADBRestFrame
    if not f then return end
    f.Pct:SetText(format("Restauration : |cffffd100%d%%|r (+%d%% si Ration)",
        ADB.PourcentRepos(), ADB.BONUS_RATION))
end

function ADB.InitRepos(f)
    ADBRestSecuriseText:SetText("Lieu sécurisé ?")
    ADBRestConfortableText:SetText("Lieu confortable ?")
    ADB.RafraichirRepos()
end

function ADB.OuvrirRepos()
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ (chef de groupe) peut lancer un repos.")
        return
    end
    ADBRestFrame:Show()
    ADB.RafraichirRepos()
end

function ADB.LancerRepos()
    if not ADB.EstMJ() then return end
    local pct = ADB.PourcentRepos()
    ADB.Envoyer(format("REST;%d", pct))
    for _, p in ipairs(ADB.db.pnjs) do
        if p.owner then
            ADB.AppliquerValeurPNJ(p.id, "pv", min(p.pvMax, p.pv + floor(p.pvMax * pct / 100 + 0.5)))
            ADB.AppliquerValeurPNJ(p.id, "pm", min(p.pmMax, p.pm + floor(p.pmMax * pct / 100 + 0.5)))
        end
    end
    ADB.Print(format("Repos lancé : %d%% des PV et PM restaurés (+%d%% avec Ration).",
        pct, ADB.BONUS_RATION))
    ADBRestFrame:Hide()
end

------------------------------------------------------------------------------
-- 6. MODIFICATION DES PV / PM + ANNONCES CHAT (DEBOUNCE)
------------------------------------------------------------------------------
function ADB.AnnoncerChat(txt)
    if not IsInGroup() then
        ADB.Print(txt)
        return
    end
    local canal = "PARTY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        canal = "INSTANCE_CHAT"
    elseif IsInRaid() then
        canal = "RAID"
    end
    SendChatMessage(txt, canal)
end

function ADB.SuivrePV(cle, libelle, delta, bouclier)
    if not delta or delta == 0 then return end
    local e = ADB.pvAgreg[cle]
    if not e then
        e = { net = 0, jeton = 0 }
        ADB.pvAgreg[cle] = e
    end
    e.net = e.net + delta
    e.libelle = libelle
    e.b = bouclier
    e.jeton = e.jeton + 1
    local jeton = e.jeton
    C_Timer.After(ADB.DELAI_CHAT, function()
        if e.jeton ~= jeton then return end
        ADB.pvAgreg[cle] = nil
        local net = e.net
        if net == 0 then return end
        if net > 0 then
            ADB.AnnoncerChat(format(e.b and "%s gagne %d Bouclier." or "%s regagne %d PV.", e.libelle, net))
        else
            ADB.AnnoncerChat(format(e.b and "%s perd %d Bouclier." or "%s perd %d PV.", e.libelle, -net))
        end
    end)
end

local function Absorber(t, v)
    local deg = t.pv - v
    if deg <= 0 then return v end
    local sh = t.sh or 0
    local absorb = min(deg, sh)
    t.sh = sh - absorb
    return t.pv - (deg - absorb)
end

function ADB.AppliquerValeur(nom, kind, valeur, silencieux, exact)
    local d = ADB.GetStatBlock(nom)
    if not d then return end
    valeur = Borner(floor(valeur + 0.5), 0, kind == "sh" and ADB.SHIELD_MAX or d[kind .. "Max"])
    local brut = valeur
    local moi = (nom == ADB.playerName)
    local t = moi and ADB.db or ADB.roster[nom]
    t.sh = t.sh or 0
    if kind == "pv" and not exact then valeur = Absorber(t, valeur) end
    t[kind] = valeur
    if moi then
        ADB.ApresChangementLocal()
    else
        ADB.Envoyer(format("SET;%s;%s;%d", nom, (kind == "pv" and exact) and "pvx" or kind, brut))
        ADB.RafraichirTout()
    end
    if not silencieux then
        local lib = ADB.NomAffiche(nom)
        ADB.SuivrePV("J:" .. nom, lib, t.pv - d.pv)
        ADB.SuivrePV("B:" .. nom, lib, t.sh - d.sh, true)
    end
end

function ADB.ModifierValeur(nom, kind, delta)
    local d = ADB.GetStatBlock(nom)
    if d then ADB.AppliquerValeur(nom, kind, d[kind] + delta) end
end

function ADB.OnBarClick(barre, bouton)
    local parent = barre:GetParent()
    if parent.npcId then
        return ADB.OnNpcBarClick(barre, parent.npcId, bouton)
    end
    if parent == ADBTargetFrame and not parent.charName and not parent.npcId then
        return ADB.OnEnnemiBarClick(barre, bouton)
    end
    local nom = parent.charName
    if not nom then return end
    if not ADB.PeutModifier(nom) then return end
    if barre.kind == "pv" and IsControlKeyDown() then
        ADB.ModifierValeur(nom, "sh", bouton == "RightButton" and -1 or 1)
    elseif IsShiftKeyDown() then
        if barre.kind == "pv" then ADB.OuvrirSaisiePV(nom) else ADB.OuvrirSaisie(nom, barre.kind) end
    elseif bouton == "LeftButton" then
        ADB.ModifierValeur(nom, barre.kind, 1)
    elseif bouton == "RightButton" then
        ADB.ModifierValeur(nom, barre.kind, -1)
    end
end

function ADB.BarreInfobulle(barre)
    if not ADB.EstMJ() then return end
    local p, edit = barre:GetParent(), false
    if p.npcId then
        edit = ADB.EstMJ()
    elseif p.charName then
        edit = ADB.PeutModifier(p.charName)
    else
        edit = ADB.EstMJ()
    end
    GameTooltip:SetOwner(barre, "ANCHOR_RIGHT")
    GameTooltip:AddLine(barre.kind == "pv" and "Points de vie" or "Points de mana", 1, 1, 1)
    if edit then
        GameTooltip:AddLine("Clic gauche : +1", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Clic droit : -1", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Maj + clic : saisir une valeur", 0.8, 0.8, 0.8)
        if barre.kind == "pv" then GameTooltip:AddLine("Ctrl + clic : bouclier +1 (droit : -1)", 0.8, 0.8, 0.8) end
    end
    GameTooltip:Show()
end

StaticPopupDialogs["ADB_SAISIE_VALEUR"] = {
    text = "Nouvelle valeur pour %s (0 à %s) :",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 4,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnShow = function(self, data)
        self.editBox:SetNumeric(true)
        self.editBox:SetText(tostring(data and data.courant or 0))
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self, data)
        ADB.ValiderSaisie(data, self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        ADB.ValiderSaisie(parent.data, self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
}

function ADB.OuvrirSaisie(nom, kind)
    local d = ADB.GetStatBlock(nom)
    if not d then return end
    local libelle = (kind == "pv" and "PV" or "PM") .. " de " .. ADB.NomAffiche(nom)
    StaticPopup_Show("ADB_SAISIE_VALEUR", libelle, d[kind .. "Max"],
        { nom = nom, kind = kind, courant = d[kind] })
end

function ADB.ValiderSaisie(data, texte)
    local v = tonumber(texte)
    if not (data and v) then return end
    if data.guid then
        ADB.AjouterDegats(data.guid, floor(v) - (ADB.degats[data.guid] or 0))
    elseif data.npcId then
        ADB.AppliquerValeurPNJ(data.npcId, data.kind, v)
    elseif ADB.PeutModifier(data.nom) then
        ADB.AppliquerValeur(data.nom, data.kind, v)
    end
end

------------------------------------------------------------------------------
-- 7. MENU CONTEXTUEL NATIF
------------------------------------------------------------------------------
local function TypeMenu(unit)
    if UnitIsUnit(unit, "player") then return "SELF" end
    if UnitIsPlayer(unit) then
        if UnitInRaid(unit) then return "RAID_PLAYER" end
        if UnitInParty(unit) then return "PARTY" end
        return "PLAYER"
    end
    if UnitIsUnit(unit, "pet") then return "PET" end
    if UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit) then return "OTHERPET" end
    return "TARGET"
end

function ADB.InitMenu(self)
    local unit = ADB.menuUnit
    if not unit or not UnitExists(unit) then return end
    UnitPopup_ShowMenu(self, TypeMenu(unit), unit, UnitName(unit))
end

function ADB.OuvrirMenu(unit)
    if not unit or not UnitExists(unit) then return end
    if not ADB.menuFrame then
        ADB.menuFrame = CreateFrame("Frame", "ADBDropDown", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(ADB.menuFrame, ADB.InitMenu, "MENU")
    end
    CloseDropDownMenus()
    ADB.menuUnit = unit
    ToggleDropDownMenu(1, nil, ADB.menuFrame, "cursor", 0, 0)
end

function ADB.OnPortraitMouseUp(self, bouton)
    if bouton ~= "RightButton" then return end
    if self.unitToken then ADB.OuvrirMenu(self.unitToken) end
end

------------------------------------------------------------------------------
-- 8. AFFICHAGE : PORTRAITS JOUEUR / CIBLE / GROUPE
------------------------------------------------------------------------------
function ADB.MajBarre(barre, c, m, sh)
    local pv = barre.kind == "pv"
    if c and m then
        barre:SetMinMaxValues(0, max(m, 1))
        barre:SetValue(c)
        barre.Text:SetText(c .. "/" .. m .. ((sh and sh > 0) and (" (+" .. sh .. ")") or ""))
        if pv then barre:SetStatusBarColor(0.75, 0.10, 0.15) else barre:SetStatusBarColor(0.20, 0.40, 0.90) end
    else
        barre:SetMinMaxValues(0, 1)
        barre:SetValue(1)
        barre.Text:SetText("?")
        if pv then barre:SetStatusBarColor(1, 0, 0) else barre:SetStatusBarColor(0, 0, 1) end
    end
end

function ADB.RafraichirJoueur()
    local f = ADBPlayerFrame
    local d = ADB.GetStatBlock(ADB.playerName)
    if not d then return end
    f.NameText:SetText(ADB.NomAffiche(ADB.playerName) .. " |cffaaaaaaNiv " .. d.level .. "|r")
    ADB.MajBarre(f.HP, d.pv, d.pvMax, d.sh)
    ADB.MajBarre(f.MP, d.pm, d.pmMax)
end

function ADB.PNJNom(p) return (p.rp and p.rp ~= "") and p.rp or p.nom end

function ADB.TrouverPNJNom(nom)
    for _, p in ipairs(ADB.ListerPNJ()) do
        if p.nom == nom then return p end
    end
end

local TEINTES = {
    boss  = { bg = { 0.35, 0, 0.02, 0.92 }, bd = { 1, 0.1, 0.1, 1 }, nom = { 1, 0.35, 0.3 } },
    elite = { bg = { 0.30, 0.22, 0, 0.92 }, bd = { 1, 0.82, 0, 1 }, nom = { 1, 0.9, 0.4 } },
}

local function EchelleCible(f, s)
    local old, l, t = f:GetScale(), f:GetLeft(), f:GetTop()
    f:SetScale(s)
    if l and t and old ~= s then -- garde le coin haut-gauche en place
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / s, t * old / s)
    end
end

function ADB.RafraichirCible(rafraichirModele)
    local f = ADBTargetFrame
    if not ADB.db or not ADB.db.uiRemplacee then return end

    if not UnitExists("target") then
        f.charName, f.npcId = nil, nil
        f:Hide()
        return
    end
    f:Show()

    local nom = UnitName("target")
    local joueur = UnitIsPlayer("target")
    f.charName = joueur and nom or nil
    local p = (not joueur) and ADB.TrouverPNJNom(nom) or nil
    f.npcId = p and p.id or nil
    local d = f.charName and ADB.GetStatBlock(f.charName)

    local cl = UnitClassification("target")
    local boss, elite = cl == "worldboss", (cl == "elite" or cl == "rareelite")
    local niv
    if d then
        niv = d.level
    else
        local l = UnitLevel("target") or 0
        niv = (boss or l <= 0) and "?" or l
    end

    local s = boss and 2 or (elite and 1.5 or 1)
    if f.echelle ~= s then
        f.echelle = s
        EchelleCible(f, s)
        rafraichirModele = true
    end
    local T = boss and TEINTES.boss or (elite and TEINTES.elite)
    if T then
        f:SetBackdropColor(unpack(T.bg))
        f:SetBackdropBorderColor(unpack(T.bd))
        f.NameText:SetTextColor(unpack(T.nom))
    else
        f:SetBackdropColor(0.05, 0.02, 0.1, 0.85)
        f:SetBackdropBorderColor(0.55, 0.35, 0.85, 1)
        f.NameText:SetTextColor(1, 0.82, 0)
    end

    f.NameText:SetText((f.charName and ADB.NomAffiche(f.charName) or nom or "")
        .. " |cffaaaaaaNiv " .. niv .. "|r")

    if rafraichirModele then
        f.Model:SetUnit("target")
        f.Model:SetPortraitZoom(1)
    end

    local src = d or p
    ADB.MajBarre(f.HP, src and src.pv, src and src.pvMax, src and src.sh)
    ADB.MajBarre(f.MP, src and src.pm, src and src.pmMax)
    if not src then ADB.TexteEnnemi(f.HP) end
    f.FicheButton:SetShown(d ~= nil and f.charName ~= ADB.playerName and ADB.EstMJ())
end

function ADB.Member_OnLoad(self)
    ADB.AppliquerFond(self)
    self:RegisterForClicks("AnyUp")
    self:SetAttribute("type1", "target")
    self.HP.kind = "pv"
    self.MP.kind = "pm"
    self.NameText:SetWordWrap(false)
    self:HookScript("OnMouseUp", ADB.OnPortraitMouseUp)
end

local function ObtenirMembre(i)
    if not ADB.membres[i] then
        ADB.membres[i] = CreateFrame("Button", "ADBMember" .. i, ADBGroupFrame, "ADBMemberTemplate")
    end
    return ADB.membres[i]
end

function ADB.MiseEnPageGroupe()
    if not ADB.db then return end
    if not ADB.db.uiRemplacee then
        ADB.nbLignes = 0
        ADB.MiseEnPageNPC()
        return
    end
    if InCombatLockdown() then
        ADB.layoutEnAttente = true
        return
    end
    ADB.layoutEnAttente = false

    local liste = ADB.ListerMembresAffiches()
    local largeur, hauteur, espace = 120, 44, 3

    for i, m in ipairs(liste) do
        local b = ObtenirMembre(i)
        local col = floor((i - 1) / ADB.MEMBRES_PAR_COLONNE)
        local ligne = (i - 1) % ADB.MEMBRES_PAR_COLONNE
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ADBGroupFrame, "TOPLEFT",
            col * (largeur + espace + 96), -ligne * (hauteur + espace))
        b:SetAttribute("unit", m.unit)
        b.unitToken = m.unit
        b.charName = m.nom
        b.Model:SetUnit(m.unit)
        b.Model:SetPortraitZoom(1)
        b:SetAlpha(1)
        b:Show()
    end
    for i = #liste + 1, #ADB.membres do
        ADB.membres[i].charName = nil
        ADB.membres[i].unitToken = nil
        ADB.membres[i]:Hide()
    end

    ADB.nbLignes = min(#liste, ADB.MEMBRES_PAR_COLONNE)
    ADB.RafraichirMembres()
    ADB.MiseEnPageNPC()
end

function ADB.RafraichirMembres()
    for _, b in ipairs(ADB.membres) do
        if b:IsShown() and b.charName then
            local ok = ADB.MembreAffichable(b.unitToken, b.charName)
                and UnitName(b.unitToken) == b.charName
            b:SetAlpha(ok and 1 or 0)
            if ok then
                local d = ADB.GetStatBlock(b.charName)
                b.NameText:SetText(ADB.NomAffiche(b.charName))
                ADB.MajBarre(b.HP, d and d.pv, d and d.pvMax, d and d.sh)
                ADB.MajBarre(b.MP, d and d.pm, d and d.pmMax)
            end
        end
    end
end

function ADB.MajModeles()
    if not ADB.db or not ADB.db.uiRemplacee then return end
    ADBPlayerFrame.Model:SetUnit("player")
    ADBPlayerFrame.Model:SetPortraitZoom(1)
    ADB.RafraichirCible(true)
    for _, b in ipairs(ADB.membres) do
        if b:IsShown() and b.unitToken then
            b.Model:SetUnit(b.unitToken)
            b.Model:SetPortraitZoom(1)
        end
    end
end

function ADB.RafraichirTout()
    if not ADB.db or not ADB.playerName then return end
    ADB.RafraichirJoueur()
    ADB.RafraichirCible(false)
    ADB.RafraichirMembres()
    ADB.RafraichirNPC()
    ADB.RafraichirConfig()
    ADB.RafraichirFiche()
    ADB.RafraichirInv()
    if ADB.itemFrame and ADB.itemFrame:IsShown() then ADB.MajItemFrame() end
    ADB.MajCombatUI()
    ADB.TalRafraichir()
end

function ADB.PlanifierMiseEnPage()
    if ADB.layoutPlanifie then return end
    ADB.layoutPlanifie = true
    C_Timer.After(0.2, function()
        ADB.layoutPlanifie = false
        ADB.MiseEnPageGroupe()
        ADB.RafraichirTout()
    end)
end

------------------------------------------------------------------------------
-- 9. PNJ
------------------------------------------------------------------------------
local function TrouverPNJ(liste, id)
    for i, p in ipairs(liste) do
        if p.id == id then return p, i end
    end
end

function ADB.ListerPNJ()
    if not ADB.db then return {} end
    if ADB.EstMJ() then return ADB.db.pnjs end
    if IsInGroup() then return ADB.pnjRecus end
    return {}
end

function ADB.EnvoyerPNJ(p)
    ADB.Envoyer(format("N;%d;%d;%d;%d;%d;%s;%d;%d;%s;%s;%s", p.id, p.pv, p.pvMax, p.pm, p.pmMax,
        Encoder(p.nom), p.sh or 0, p.ally and 1 or 0, Encoder(p.owner or ""), p.petType or "",
        Encoder(p.rp or "")))
end

function ADB.PlanifierPNJ(id)
    ADB.pnjModifies[id] = true
    if ADB.pnjPlanifie then return end
    ADB.pnjPlanifie = true
    C_Timer.After(ADB.DELAI_DIFFUSION, function()
        ADB.pnjPlanifie = false
        if ADB.EstMJ() then
            for pid in pairs(ADB.pnjModifies) do
                local p = TrouverPNJ(ADB.db.pnjs, pid)
                if p then ADB.EnvoyerPNJ(p) end
            end
        end
        wipe(ADB.pnjModifies)
    end)
end

function ADB.PlanifierPNJComplet()
    if ADB.syncPNJPlanifiee then return end
    ADB.syncPNJPlanifiee = true
    C_Timer.After(ADB.DELAI_SYNC_PNJ, function()
        ADB.syncPNJPlanifiee = false
        ADB.DiffuserPNJComplet()
    end)
end

function ADB.DiffuserPNJComplet()
    if not ADB.EstMJ() then return end
    ADB.jetonSync = (ADB.jetonSync or 0) + 1
    local jeton = ADB.jetonSync
    local liste = ADB.db.pnjs

    if #liste == 0 then
        ADB.Envoyer("NC")
        return
    end

    ADB.Envoyer("NS")
    local ids = {}
    for _, p in ipairs(liste) do ids[#ids + 1] = p.id end
    for i, id in ipairs(ids) do
        C_Timer.After(0.15 * i, function()
            if jeton ~= ADB.jetonSync or not ADB.EstMJ() then return end
            local p = TrouverPNJ(ADB.db.pnjs, id)
            if p then ADB.EnvoyerPNJ(p) end
        end)
    end
    C_Timer.After(0.15 * (#ids + 1), function()
        if jeton == ADB.jetonSync and ADB.EstMJ() then ADB.Envoyer("NE") end
    end)
end

function ADB.RecevoirPNJ(cmd, nom, a, b, c, d, e, f, g, h, k, l, m)
    if ADB.EstMJ() then return end
    if not ADB.EstNomMJ(nom) then return end

    if ADB.pnjSource ~= nom then
        wipe(ADB.pnjRecus)
        ADB.pnjSource = nom
    end
    local liste = ADB.pnjRecus

    if cmd == "NC" then
        wipe(liste)
    elseif cmd == "NS" then
        for _, p in ipairs(liste) do p.perime = true end
        return
    elseif cmd == "NE" then
        for i = #liste, 1, -1 do
            if liste[i].perime then tremove(liste, i) end
        end
    elseif cmd == "ND" then
        local _, idx = TrouverPNJ(liste, tonumber(a))
        if idx then tremove(liste, idx) end
    elseif cmd == "N" then
        local id, pv, pvMax, pm, pmMax = tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e)
        if not (id and pv and pvMax and pm and pmMax) then return end
        id = floor(id)
        local nomPNJ = "PNJ"
        if f and #f <= 130 then
            nomPNJ = NettoyerNom(Decoder(f))
            if nomPNJ == "" then nomPNJ = "PNJ" end
        end
        pvMax = Borner(floor(pvMax), 1, ADB.PNJ_STAT_MAX)
        pmMax = Borner(floor(pmMax), 0, ADB.PNJ_STAT_MAX)
        local p = TrouverPNJ(liste, id)
        if not p then
            if #liste >= ADB.PNJ_MAX then return end
            p = { id = id }
            liste[#liste + 1] = p
        end
        p.nom, p.pvMax, p.pmMax = nomPNJ, pvMax, pmMax
        p.sh = Borner(floor(tonumber(g) or 0), 0, ADB.SHIELD_MAX)
        p.ally = (h == "1")
        p.owner = (k and k ~= "") and NettoyerNom(Decoder(k)) or nil
        p.petType = ADB.PET_TYPES[l or ""] and l or nil
        local rp = (m and m ~= "" and #m <= 130) and NettoyerNom(Decoder(m)):sub(1, 40) or ""
        p.rp = rp ~= "" and rp or nil
        p.pv = Borner(floor(pv), 0, pvMax)
        p.pm = Borner(floor(pm), 0, pmMax)
        p.perime = nil
    end

    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
end

function ADB.CreerPNJ(nom, pvMax, pmMax, ally, rp)
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ (chef de groupe) peut créer des PNJ.")
        return false
    end
    local liste = ADB.db.pnjs
    if #liste >= ADB.PNJ_MAX then
        ADB.Print("Nombre maximum de PNJ atteint (" .. ADB.PNJ_MAX .. ").")
        return false
    end
    pvMax = Borner(floor(pvMax), 1, ADB.PNJ_STAT_MAX)
    pmMax = Borner(floor(pmMax), 0, ADB.PNJ_STAT_MAX)
    local id = ADB.db.pnjProchainId
    ADB.db.pnjProchainId = id + 1
    liste[#liste + 1] = {
        id = id,
        nom = nom,
        pvMax = pvMax,
        pmMax = pmMax,
        pv = pvMax,
        pm = pmMax,
        sh = 0,
        ally = ally and true or false,
        rp = (rp and rp ~= "") and rp or nil,
    }
    ADB.PlanifierPNJ(id)
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
    return true
end

function ADB.SupprimerPNJ(id)
    if not ADB.EstMJ() then return end
    local _, idx = TrouverPNJ(ADB.db.pnjs, id)
    if not idx then return end
    tremove(ADB.db.pnjs, idx)
    ADB.pnjModifies[id] = nil
    ADB.Envoyer(format("ND;%d", id))
    ADB.MiseEnPageNPC()
    ADB.RafraichirNPC()
end

function ADB.AppliquerValeurPNJ(id, kind, valeur, exact)
    if not ADB.EstMJ() then return end
    local p = TrouverPNJ(ADB.db.pnjs, id)
    if not p or (kind ~= "pv" and kind ~= "pm" and kind ~= "sh") then return end
    local pv0, sh0 = p.pv, p.sh or 0
    p.sh = sh0
    valeur = Borner(floor(valeur + 0.5), 0, kind == "sh" and ADB.SHIELD_MAX or p[kind .. "Max"])
    if kind == "pv" and not exact then valeur = Absorber(p, valeur) end
    p[kind] = valeur
    ADB.SuivrePV("N:" .. id, ADB.PNJNom(p), p.pv - pv0)
    ADB.SuivrePV("NB:" .. id, ADB.PNJNom(p), p.sh - sh0, true)
    ADB.PlanifierPNJ(id)
    ADB.RafraichirNPC()
end

function ADB.OnNpcBarClick(barre, id, bouton)
    if not ADB.EstMJ() then
        UIErrorsFrame:AddMessage("Seul le MJ peut modifier les PNJ.", 1, 0.3, 0.3)
        return
    end
    local p = TrouverPNJ(ADB.db.pnjs, id)
    if not p then return end
    local kind = barre.kind
    if kind == "pv" and IsControlKeyDown() then
        ADB.AppliquerValeurPNJ(id, "sh", (p.sh or 0) + (bouton == "RightButton" and -1 or 1))
    elseif kind == "pv" and IsShiftKeyDown() then
        ADB.OuvrirSaisiePV(nil, id)
    elseif IsShiftKeyDown() then
        local libelle = (kind == "pv" and "PV" or "PM") .. " de " .. p.nom
        StaticPopup_Show("ADB_SAISIE_VALEUR", libelle, p[kind .. "Max"],
            { npcId = id, kind = kind, courant = p[kind] })
    elseif bouton == "LeftButton" then
        ADB.AppliquerValeurPNJ(id, kind, p[kind] + 1)
    elseif bouton == "RightButton" then
        ADB.AppliquerValeurPNJ(id, kind, p[kind] - 1)
    end
end

StaticPopupDialogs["ADB_SUPPRIMER_PNJ"] = {
    text = "Supprimer le PNJ « %s » du groupe ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) ADB.SupprimerPNJ(data) end,
}

function ADB.DemanderSuppressionPNJ(cadre)
    if not ADB.EstMJ() or not cadre.npcId then return end
    local p = TrouverPNJ(ADB.db.pnjs, cadre.npcId)
    if p then StaticPopup_Show("ADB_SUPPRIMER_PNJ", p.nom, nil, p.id) end
end

function ADB.Npc_OnLoad(self)
    ADB.AppliquerFond(self)
    self.HP.kind = "pv"
    self.MP.kind = "pm"
    self.NameText:SetWordWrap(false)
end

local function ObtenirNPC(i)
    if not ADB.pnjFrames[i] then
        ADB.pnjFrames[i] = CreateFrame("Frame", "ADBNpc" .. i, ADBNpcFrame, "ADBNpcTemplate")
    end
    return ADB.pnjFrames[i]
end

function ADB.MiseEnPageNPC()
    if not ADB.db or not ADBNpcFrame then return end
    local largeur, hauteur, espace = 120, 44, 3

    ADBNpcFrame:ClearAllPoints()
    ADBNpcFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
        5, -(130 + ADB.nbLignes * (44 + 3) + 8))

    local liste = {}
    for _, p in ipairs(ADB.ListerPNJ()) do
        if not p.owner then liste[#liste + 1] = p end
    end
    for i, p in ipairs(liste) do
        local f = ObtenirNPC(i)
        local col = floor((i - 1) / ADB.MEMBRES_PAR_COLONNE)
        local ligne = (i - 1) % ADB.MEMBRES_PAR_COLONNE
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", ADBNpcFrame, "TOPLEFT",
            col * (largeur + espace), -24 - ligne * (hauteur + espace))
        f.npcId = p.id
        f:Show()
    end
    for i = #liste + 1, #ADB.pnjFrames do
        ADB.pnjFrames[i].npcId = nil
        ADB.pnjFrames[i]:Hide()
    end
    ADB.RafraichirNPC()
end

function ADB.RafraichirNPC()
    if not ADB.db then return end
    local liste = ADB.ListerPNJ()
    local estMJ = ADB.EstMJ()
    for _, f in ipairs(ADB.pnjFrames) do
        if f:IsShown() and f.npcId then
            local p = TrouverPNJ(liste, f.npcId)
            if p then
                f.NameText:SetText("|cff" .. (p.ally and "40ff40" or "ffa040") .. ADB.PNJNom(p) .. "|r")
                ADB.MajBarre(f.HP, p.pv, p.pvMax, p.sh)
                ADB.MajBarre(f.MP, p.pm, p.pmMax)
                f.Delete:SetShown(estMJ)
            end
        end
    end
    if ADBNpcFrame then
        ADBNpcFrame.CreateButton:SetShown(estMJ)
        ADBNpcFrame.RestButton:SetShown(estMJ)
        ADBNpcFrame.XPButton:SetShown(estMJ)
    end
    ADB.RafraichirCible(false)
end

function ADB.OuvrirCreationPNJ()
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ (chef de groupe) peut créer des PNJ.")
        return
    end
    ADBNpcCreateFrame:Show()
end

function ADB.InitCreationPNJ()
    local f = ADBNpcCreateFrame
    f.NameEdit:SetText("")
    f.PvEdit:SetText("10")
    f.PmEdit:SetText("10")
    ADBNpcAllyCheckText:SetText("PNJ allié")
    f.AllyCheck:SetChecked(false)
    f.NameEdit:SetFocus()
end

function ADB.ValiderCreationPNJ()
    local f = ADBNpcCreateFrame
    local nom = NettoyerNom(f.NameEdit:GetText())
    if nom == "" then nom = "PNJ" end
    local pv = tonumber(f.PvEdit:GetText())
    local pm = tonumber(f.PmEdit:GetText()) or 0
    if not pv or pv < 1 then
        ADB.Print("PV max invalide (1 à " .. ADB.PNJ_STAT_MAX .. ").")
        return
    end
    local rp = f.RPEdit and NettoyerNom(f.RPEdit:GetText()):sub(1, 40) or ""
    if ADB.CreerPNJ(nom, pv, pm, f.AllyCheck:GetChecked(), rp) then f:Hide() end
end

------------------------------------------------------------------------------
-- 10. MASQUAGE DE L'UI BLIZZARD
------------------------------------------------------------------------------
ADB.cacheur = CreateFrame("Frame")
ADB.cacheur:Hide()

local function Masquer(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetParent(ADB.cacheur)
    frame:Hide()
end

function ADB.MasquerUIBlizzard()
    if InCombatLockdown() then
        ADB.masquageEnAttente = true
        return
    end
    ADB.masquageEnAttente = false

    Masquer(PlayerFrame)
    Masquer(TargetFrame)
    for i = 1, 4 do Masquer(_G["PartyMemberFrame" .. i]) end

    if CompactRaidFrameManager_SetSetting then
        CompactRaidFrameManager_SetSetting("IsShown", "0")
    end
    Masquer(CompactRaidFrameManager)
    Masquer(CompactRaidFrameContainer)
    Masquer(CompactPartyFrame)
end

local function CopierPosition(source, cible, decalageMinX)
    if not source or not source.GetPoint then return end
    local point, rel, relPoint, x, y = source:GetPoint(1)
    if point and (rel == nil or rel == UIParent) then
        cible:ClearAllPoints()
        cible:SetPoint(point, UIParent, relPoint or point, max(x or 0, decalageMinX or 0), y or 0)
    end
end

------------------------------------------------------------------------------
-- 11. FENETRE DE CONFIGURATION & FICHES
------------------------------------------------------------------------------
function ADB.BasculerConfig()
    if ADBConfigFrame:IsShown() then ADBConfigFrame:Hide() else ADBConfigFrame:Show() end
end

function ADB.OnNomRPEdit(edit)
    ADB.DefinirNomRP(edit:GetText())
    edit:SetText(ADB.db.nomRP or "")
end

function ADB.OnNomRPEscape(edit)
    edit:SetText(ADB.db.nomRP or "")
    edit:ClearFocus()
end

local function InitialiserListe(drop, liste, cle, fnDefinir)
    UIDropDownMenu_SetWidth(drop, 150)
    UIDropDownMenu_Initialize(drop, function(self, niveau)
        for _, entree in ipairs(liste) do
            if not ADB.ClasseSpeciale(entree[1]) then
                local info = UIDropDownMenu_CreateInfo()
                info.text = entree[1]
                info.checked = (ADB.db[cle] == entree[1])
                info.func = function() fnDefinir(entree[1]) end
                UIDropDownMenu_AddButton(info, niveau)
            end
        end
    end)
end

function ADB.InitDropdowns()
    local f = ADBConfigFrame
    InitialiserListe(f.RaceDrop, ADB.RACES, "race", ADB.DefinirRace)
    InitialiserListe(f.ClasseDrop, ADB.CLASSES, "classe", ADB.DefinirClasse)
end

function ADB.RafraichirConfig()
    local f = ADBConfigFrame
    if not f or not f:IsShown() or not ADB.db then return end
    local d = ADB.GetStatBlock(ADB.playerName)

    if not f.NomRPEdit:HasFocus() then f.NomRPEdit:SetText(ADB.db.nomRP or "") end
    UIDropDownMenu_SetText(f.RaceDrop, ADB.db.race)
    UIDropDownMenu_SetText(f.ClasseDrop, ADB.db.classe)

    local role
    if not IsInGroup() then
        role = "Hors groupe"
    elseif ADB.EstMJ() then
        role = "|cffffd100MJ (chef de groupe)|r"
    else
        role = "Joueur"
    end

    local xpTxt
    if d.level >= ADB.NIVEAU_MAX then
        xpTxt = format("%d (niveau max)", d.xp)
    else
        xpTxt = format("%d / %d", d.xp, ADB.XP_SEUILS[d.level + 1])
    end

    f.Derived:SetText(format(
        "|cffffd100Rôle|r : %s\n\n" ..
        "|cffffd100Niveau|r : %d    |cffffd100XP|r : %s\n\n" ..
        "|cffffd100Or|r : %s\n\n" ..
        "Force : %d   Agilité : %d   Intelligence : %d\n\n" ..
        "|cffff5050PV max|r : %d    (actuels : %d)\n" ..
        "|cff5080ffPM max|r : %d    (actuels : %d)\n\n" ..
        "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f",
        role, d.level, xpTxt, ADB.FormatOr(d.pc), d.force, d.agilite, d.intelligence,
        d.pvMax, d.pv, d.pmMax, d.pm, d.multForce, d.multAgi, d.multInt))

    local mj = ADB.EstMJ()
    local gm = { f.ItemButton, f.MJButton, f.PNJButton, f.FicheCibleButton }
    local liste = { f.TalentButton, f.InvButton }
    f.PetButton:SetShown(not mj)
    if not mj then liste[#liste + 1] = f.PetButton end
    for _, b in ipairs(gm) do
        b:SetShown(mj)
        if mj then liste[#liste + 1] = b end
    end
    local n = #liste
    for i, b in ipairs(liste) do
        b:ClearAllPoints()
        b:SetPoint("BOTTOM", f, "BOTTOM", 0, 20 + (n - i) * 28)
    end
    f:SetHeight(430 + (n - 1) * 28)
end

function ADB.OuvrirFiche(nom)
    ADBFicheFrame.nomAffiche = nom
    ADBFicheFrame:Show()
    ADB.RafraichirFiche()
end

function ADB.RafraichirFiche()
    local f = ADBFicheFrame
    if not f or not f:IsShown() or not f.nomAffiche then return end
    local d = ADB.GetStatBlock(f.nomAffiche)
    if not d then
        f.Body:SetText("Aucune donnée reçue pour " .. f.nomAffiche .. ".")
        return
    end
    local titre = ADB.NomAffiche(d.nom)
    if titre ~= d.nom then titre = titre .. " |cff999999(" .. d.nom .. ")|r" end
    local race = (d.race and d.race ~= "") and d.race or "?"
    local classe = (d.classe and d.classe ~= "") and d.classe or "?"
    f.Body:SetText(format(
        "|cff9d6bff%s|r\n\n" ..
        "|cffffd100Race|r : %s\n|cffffd100Classe|r : %s\n|cffffd100Niveau|r : %d    |cffffd100XP|r : %d\n" ..
        "|cffffd100Or|r : %s\n\n" ..
        "|cffffd100Force|r : %d\n|cffffd100Agilité|r : %d\n|cffffd100Intelligence|r : %d\n\n" ..
        "|cffff5050PV|r : %d / %d\n|cff5080ffPM|r : %d / %d\n\n" ..
        "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f",
        titre, race, classe, d.level, d.xp, ADB.FormatOr(d.pc), d.force, d.agilite, d.intelligence,
        d.pv, d.pvMax, d.pm, d.pmMax, d.multForce, d.multAgi, d.multInt))
end

function ADB.VoirFicheCible()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        ADB.Print("Ciblez d'abord un joueur.")
        return
    end
    local nom = UnitName("target")
    if nom ~= ADB.playerName and not ADB.EstMJ() then
        ADB.Print("Seul le MJ peut consulter la fiche des autres joueurs.")
        return
    end
    if not ADB.GetStatBlock(nom) then
        ADB.Print("Aucune fiche reçue pour " .. nom .. " (a-t-il l'addon ?). Nouvelle demande envoyée.")
        ADB.PlanifierDiffusion(true)
        return
    end
    ADB.OuvrirFiche(nom)
end

------------------------------------------------------------------------------
-- 12. BOUTON DE MINIMAP
------------------------------------------------------------------------------
function ADB.PositionnerBouton()
    local a = math.rad(ADB.db.minimap.angle)
    ADBMinimapButton:ClearAllPoints()
    ADBMinimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

function ADB.BoutonGlisse()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local echelle = Minimap:GetEffectiveScale()
    px, py = px / echelle, py / echelle
    ADB.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    ADB.PositionnerBouton()
end

------------------------------------------------------------------------------
-- 13. OR, INVENTAIRE & EQUIPEMENT
------------------------------------------------------------------------------
function ADB.ModifierOr(delta)
    ADB.db.pc = Borner(ADB.db.pc + delta, 0, ADB.OR_MAX)
    ADB.ApresChangementLocal()
end

function ADB.CibleOr()
    if ADB.EstMJ() and UnitExists("target") and UnitIsPlayer("target") then
        local n = UnitName("target")
        if n ~= ADB.playerName and ADB.roster[n] then return n end
    end
    return ADB.playerName
end

function ADB.LireMontant()
    local f = ADB.invFrame
    return floor((tonumber(f.Po:GetText()) or 0) * 10000
        + (tonumber(f.Pa:GetText()) or 0) * 100 + (tonumber(f.Pc:GetText()) or 0))
end

function ADB.ClicOr(ajout)
    local m = ADB.LireMontant()
    if m < 1 then
        ADB.Print("Montant invalide."); return
    end
    m = min(m, ADB.OR_MAX)
    local cible = ADB.CibleOr()
    if ajout then
        if not ADB.EstMJ() then
            ADB.Print("Seul le MJ peut ajouter de l'or."); return
        end
        if cible == ADB.playerName then
            ADB.ModifierOr(m)
        else
            ADB.Envoyer(format("GOLD;%s;%d", cible, m))
            ADB.Print(format("%s ajoutés à %s.", ADB.FormatOr(m), ADB.NomAffiche(cible)))
        end
    else
        if cible == ADB.playerName then
            if m > ADB.db.pc then
                ADB.Print("Fonds insuffisants."); return
            end
            ADB.ModifierOr(-m)
        else
            ADB.Envoyer(format("GOLDM;%s;%d", cible, m))
            ADB.Print(format("%s retirés à %s.", ADB.FormatOr(m), ADB.NomAffiche(cible)))
        end
    end
    local f = ADB.invFrame
    f.Po:SetText(""); f.Pa:SetText(""); f.Pc:SetText("")
end

function ADB.InfoObjet(it)
    local def = ADB.CONSO[it.kind]
    if def then return def.nom, IconeTex(def.icon), 0.5, 0.5, 0.5, "ffffff" end
    local R = ADB.RARETES[it.rar]
    return it.nom, IconeTex(it.icon), R[2], R[3], R[4], R[6]
end

function ADB.NomColore(it)
    local nom, _, _, _, _, hex = ADB.InfoObjet(it)
    return "|cff" .. hex .. nom .. "|r"
end

function ADB.ObjetEn(zone, key)
    if not ADB.db then return nil end
    if zone == "inv" then return ADB.db.inv[key] end
    return ADB.db.equip[key]
end

function ADB.AjouterObjet(it, qty)
    local inv = ADB.db.inv
    local def = ADB.CONSO[it.kind]
    local ajoutes = 0
    for _ = 1, (def and (qty or 1) or 1) do
        local place = false
        if def and def.stack > 1 then
            for i = 1, ADB.INV_SLOTS do
                local s = inv[i]
                if s and s.kind == it.kind and s.count < def.stack then
                    s.count = s.count + 1
                    place = true
                    break
                end
            end
        end
        if not place then
            for i = 1, ADB.INV_SLOTS do
                if not inv[i] then
                    inv[i] = def and { kind = it.kind, count = 1 } or CopyTable(it)
                    place = true
                    break
                end
            end
        end
        if not place then break end
        ajoutes = ajoutes + 1
    end
    ADB.RafraichirInv()
    return ajoutes
end

function ADB.RecevoirObjet(it, qty)
    qty = qty or 1
    local n = ADB.AjouterObjet(it, qty)
    if n >= 1 then
        ADB.Print(format("Vous recevez : %s%s.", ADB.NomColore(it), n > 1 and (" x" .. n) or ""))
    end
    if n < qty then ADB.Print("Votre inventaire est plein !") end
end

function ADB.RetirerDe(i)
    local s = ADB.db.inv[i]
    if not s then return end
    if s.count and s.count > 1 then s.count = s.count - 1 else ADB.db.inv[i] = nil end
end

function ADB.RetirerConso(kind)
    for i = 1, ADB.INV_SLOTS do
        local s = ADB.db.inv[i]
        if s and s.kind == kind then
            ADB.RetirerDe(i)
            return true
        end
    end
    return false
end

function ADB.Equiper(i)
    local it = ADB.db.inv[i]
    if not it or it.kind ~= "equip" then return end
    ModifierFiche(function(db)
        local ancien = db.equip[it.slot]
        db.equip[it.slot] = it
        db.inv[i] = ancien
    end)
end

function ADB.Desequiper(slot)
    local it = ADB.db.equip[slot]
    if not it then return end
    for i = 1, ADB.INV_SLOTS do
        if not ADB.db.inv[i] then
            ModifierFiche(function(db)
                db.inv[i] = it
                db.equip[slot] = nil
            end)
            return
        end
    end
    ADB.Print("Votre inventaire est plein !")
end

function ADB.Detruire(zone, key)
    ADB.sel = nil
    if zone == "inv" then
        ADB.db.inv[key] = nil
        ADB.RafraichirInv()
    else
        ModifierFiche(function(db) db.equip[key] = nil end)
    end
end

StaticPopupDialogs["ADB_DETRUIRE"] = {
    text = "Détruire définitivement %s ?\nCette action est irréversible.",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data)
        if data and ADB.ObjetEn(data.zone, data.key) then ADB.Detruire(data.zone, data.key) end
    end,
}

StaticPopupDialogs["ADB_POTION"] = {
    text = "Utiliser %s ?\n%s",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) ADB.PotionDemander(data) end,
}

function ADB.UtiliserPotion(i)
    local s = ADB.db.inv[i]
    if not s or (s.kind ~= "potvie" and s.kind ~= "potmana") then return end
    ADB.RetirerDe(i)
    local cle = (s.kind == "potvie") and "pv" or "pm"
    local d = ADB.GetStatBlock(ADB.playerName)
    local nouveau = min(d[cle .. "Max"], d[cle] + ADB.POTION_SOIN)
    ADB.db[cle] = nouveau
    ADB.Print(format("Vous utilisez %s : +%d %s.", ADB.CONSO[s.kind].nom, nouveau - d[cle],
        cle == "pv" and "PV" or "PM"))
    ADB.ApresChangementLocal()
    if cle == "pv" then
        ADB.SuivrePV("J:" .. ADB.playerName, ADB.NomAffiche(ADB.playerName), nouveau - d.pv)
    end
end

function ADB.ClicDetruire()
    local s = ADB.sel
    if not s then return end
    local it = ADB.ObjetEn(s.zone, s.key)
    if not it then
        ADB.sel = nil; ADB.RafraichirInv(); return
    end
    if ADB.EstMJ() then
        ADB.Detruire(s.zone, s.key)
    else
        StaticPopup_Show("ADB_DETRUIRE", ADB.NomColore(it), nil, { zone = s.zone, key = s.key })
    end
end

function ADB.OnSlotClick(b, bouton)
    local it = ADB.ObjetEn(b.zone, b.key)
    if bouton == "LeftButton" then
        ADB.sel = it and { zone = b.zone, key = b.key } or nil
        ADB.RafraichirInv()
    elseif bouton == "RightButton" and it then
        if b.zone == "eq" then
            ADB.Desequiper(b.key)
        elseif it.kind == "equip" then
            ADB.Equiper(b.key)
        elseif it.kind == "potvie" or it.kind == "potmana" then
            StaticPopup_Show("ADB_POTION", ADB.NomColore(it), ADB.CONSO[it.kind].desc, b.key)
        end
    end
end

function ADB.SlotInfobulle(b)
    local it = ADB.ObjetEn(b.zone, b.key)
    if not it then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ADB.NomColore(it))
    local def = ADB.CONSO[it.kind]
    if def then
        GameTooltip:AddLine(def.desc, 1, 0.82, 0, true)
        if def.stack > 1 then GameTooltip:AddLine("Quantité : " .. it.count .. " / " .. def.stack, 1, 1, 1) end
        if it.kind ~= "ration" then GameTooltip:AddLine("Clic droit : utiliser", 0.6, 0.6, 0.6) end
    elseif it.kind == "story" then
        GameTooltip:AddLine(it.desc ~= "" and it.desc or "Objet narratif", 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(ADB.SLOT_NOM[it.slot], 1, 1, 1)
        for i = 1, 3 do
            if it.st[i] > 0 then
                GameTooltip:AddLine("+" .. it.st[i] .. " " .. ADB.STAT_NOMS[i], 0.1, 1, 0.1)
            end
        end
        if it.comp ~= "" then
            GameTooltip:AddLine("Compétences : " .. it.comp, 1, 0.82, 0, true)
        end
        GameTooltip:AddLine(b.zone == "eq" and "Clic droit : déséquiper" or "Clic droit : équiper",
            0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Helpers UI ---------------------------------------------------------------
local function Etiq(parent, txt, x, y, police)
    local s = parent:CreateFontString(nil, "ARTWORK", police or "GameFontHighlight")
    s:SetPoint("TOPLEFT", x, y)
    s:SetJustifyH("LEFT")
    s:SetText(txt)
    return s
end

local function Saisie(parent, x, y, w, lettres, num)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetMaxLetters(lettres)
    if num then e:SetNumeric(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

local function Bouton(parent, txt, x, y, w, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(txt)
    b:SetScript("OnClick", fn)
    return b
end

local function FenetreBase(nom, w, h, titre)
    local f = CreateFrame("Frame", nom, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText(titre) end
    f:Hide()
    return f
end

local function CreerSlot(parent, zone, key, x, y, taille)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(taille, taille)
    b:SetPoint("TOPLEFT", x, y)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetPoint("TOPLEFT", 2, -2)
    b.icone:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.nombre = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.nombre:SetPoint("BOTTOMRIGHT", -3, 3)
    b.etiquette = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.etiquette:SetPoint("CENTER")
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetAllPoints()
    b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.sel:SetBlendMode("ADD")
    b.sel:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.zone, b.key = zone, key
    b:SetScript("OnClick", ADB.OnSlotClick)
    b:SetScript("OnEnter", ADB.SlotInfobulle)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function MajSlot(b)
    local it = ADB.ObjetEn(b.zone, b.key)
    local sel = ADB.sel and ADB.sel.zone == b.zone and ADB.sel.key == b.key
    b.sel:SetShown(sel and true or false)
    if it then
        local _, tex, r, g, bl = ADB.InfoObjet(it)
        b.fond:SetColorTexture(r, g, bl, 1)
        b.icone:SetTexture(tex)
        b.icone:Show()
        b.etiquette:SetText("")
        b.nombre:SetText((it.count and it.count > 1) and it.count or "")
    else
        b.fond:SetColorTexture(0.15, 0.15, 0.15, 1)
        b.icone:Hide()
        b.nombre:SetText("")
        b.etiquette:SetText(b.zone == "eq" and ADB.SLOT_NOM[b.key] or "")
    end
end

function ADB.CreerInv()
    local f = FenetreBase("ADBInvFrame", 340, 420, "Inventaire")
    ADB.invFrame = f
    f:SetPoint("CENTER", 300, 0)
    f.slots = {}
    for k, s in ipairs(ADB.SLOTS) do
        f.slots[#f.slots + 1] = CreerSlot(f, "eq", s[1], 28 + (k - 1) * 60, -38, 44)
    end
    for i = 1, ADB.INV_SLOTS do
        local col, lig = (i - 1) % 4, floor((i - 1) / 4)
        f.slots[#f.slots + 1] = CreerSlot(f, "inv", i, 70 + col * 52, -100 - lig * 52, 44)
    end
    f.Or = Etiq(f, "", 20, -312)
    f.CibleTxt = Etiq(f, "", 20, -330, "GameFontNormalSmall")
    f.Po = Saisie(f, 28, -352, 46, 4, true)
    Etiq(f, "Po", 82, -355)
    f.Pa = Saisie(f, 124, -352, 46, 4, true)
    Etiq(f, "Pa", 178, -355)
    f.Pc = Saisie(f, 220, -352, 46, 4, true)
    Etiq(f, "Pc", 274, -355)
    f.AddBtn = Bouton(f, "Ajouter (MJ)", 16, -382, 100, function() ADB.ClicOr(true) end)
    f.RemBtn = Bouton(f, "Retirer", 120, -382, 96, function() ADB.ClicOr(false) end)
    f.DestroyBtn = Bouton(f, "Détruire", 220, -382, 100, ADB.ClicDetruire)
    f:SetScript("OnShow", function() ADB.RafraichirInv() end)
    f:SetScript("OnHide", function() ADB.sel = nil end)
end

function ADB.RafraichirInv()
    local f = ADB.invFrame
    if not f or not f:IsShown() or not ADB.db then return end
    if ADB.sel and not ADB.ObjetEn(ADB.sel.zone, ADB.sel.key) then ADB.sel = nil end
    for _, b in ipairs(f.slots) do MajSlot(b) end
    f.Or:SetText("Or : " .. ADB.FormatOr(ADB.db.pc))
    local cible = ADB.CibleOr()
    if cible ~= ADB.playerName then
        local d = ADB.GetStatBlock(cible)
        f.CibleTxt:SetText("Montants appliqués à : " .. ADB.NomAffiche(cible)
            .. " (" .. ADB.FormatOr(d and d.pc or 0) .. ")")
    elseif ADB.EstMJ() then
        f.CibleTxt:SetText("Montants appliqués à : vous-même")
    else
        f.CibleTxt:SetText("")
    end
    f.AddBtn:SetShown(ADB.EstMJ())
    f.DestroyBtn:SetEnabled(ADB.sel ~= nil)
end

function ADB.BasculerInv()
    if ADB.invFrame:IsShown() then ADB.invFrame:Hide() else ADB.invFrame:Show() end
end

------------------------------------------------------------------------------
-- 14. CREATION D'OBJETS PAR LE MJ
------------------------------------------------------------------------------
function ADB.EnvoyerObjet(cible, it, qty)
    if cible == ADB.playerName then
        ADB.RecevoirObjet(it, qty)
        return
    end
    if it.kind == "equip" then
        ADB.Envoyer(format("IE;%s;%s;%d;%s;%d;%d;%d;%s;%s;%s;%s", cible, it.slot, it.rar, it.icon,
            it.st[1], it.st[2], it.st[3], Encoder(it.nom), Encoder(it.comp),
            table.concat(it.sk or {}, ","), table.concat(it.tags or {}, ",")))
    else
        ADB.Envoyer(format("IC;%s;%s;%d", cible, it.kind, qty))
    end
    ADB.Print(format("%s envoyé à %s.", ADB.NomColore(it), ADB.NomAffiche(cible)))
end

function ADB.MajItemFrame()
    local f = ADB.itemFrame
    if not f or not f.pret then return end
    local cap = ADB.RARETES[f.rar][5]
    local tot = 0
    for i = 1, 3 do tot = tot + (tonumber(f.Stats[i]:GetText()) or 0) end
    f.Total:SetText(format("Total : %s%d|r / %d", tot > cap and "|cffff4040" or "|cff40ff40", tot, cap))
    f.IconeTex:SetTexture(IconeTex(f.icon))
    local cible = ADB.CibleJoueur()
    f.CibleTxt:SetText("Cible : " .. (cible and ADB.NomAffiche(cible) or "|cffff4040aucune|r"))
end

function ADB.ValiderCreationItem()
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ peut créer des objets."); return
    end
    local f = ADB.itemFrame
    local nom = NettoyerNom(f.NameEdit:GetText())
    if nom == "" then
        ADB.Print("Donnez un nom à l'objet."); return
    end
    local st, tot = {}, 0
    for i = 1, 3 do
        st[i] = Borner(floor(tonumber(f.Stats[i]:GetText()) or 0), 0, 12)
        tot = tot + st[i]
    end
    local cap = ADB.RARETES[f.rar][5]
    if tot > cap then
        ADB.Print(format("Trop de points de stats pour cette rareté (max %d).", cap))
        return
    end
    local cible = ADB.CibleJoueur()
    if not cible then
        ADB.Print("Ciblez un joueur possédant l'addon."); return
    end
    local it = ValiderItem({
        kind = "equip",
        slot = f.slot,
        rar = f.rar,
        st = st,
        icon = f.icon,
        nom = nom,
        comp = f.CompEdit:GetText(),
        sk = f.SkEdit:GetText(),
        tags = f.TagsEdit and f.TagsEdit:GetText() or "",
    })
    if it then ADB.EnvoyerObjet(cible, it, 1) end
end

function ADB.DonnerConso(kind)
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ peut donner des objets."); return
    end
    local cible = ADB.CibleJoueur()
    if not cible then
        ADB.Print("Ciblez un joueur possédant l'addon."); return
    end
    local q = Borner(floor(tonumber(ADB.itemFrame.QtyEdit:GetText()) or 1), 1, 20)
    ADB.EnvoyerObjet(cible, { kind = kind }, q)
end

function ADB.OuvrirCreationItem()
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ (chef de groupe) peut créer des objets.")
        return
    end
    ADB.itemFrame:Show()
end

function ADB.CreerFenetreItem()
    local f = FenetreBase("ADBItemFrame", 320, 490, "Créer un objet")
    ADB.itemFrame = f
    f:SetPoint("CENTER", -300, 0)
    f.slot, f.rar, f.icon = "arme", 1, "INV_Sword_04"

    Etiq(f, "Emplacement", 20, -40)
    f.SlotDrop = CreateFrame("Frame", "ADBItemSlotDrop", f, "UIDropDownMenuTemplate")
    f.SlotDrop:SetPoint("TOPLEFT", 100, -33)
    UIDropDownMenu_SetWidth(f.SlotDrop, 150)
    UIDropDownMenu_Initialize(f.SlotDrop, function(self, niveau)
        for _, s in ipairs(ADB.SLOTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = s[2]
            info.checked = (f.slot == s[1])
            info.func = function()
                f.slot = s[1]
                UIDropDownMenu_SetText(f.SlotDrop, s[2])
                ADB.MajItemFrame()
            end
            UIDropDownMenu_AddButton(info, niveau)
        end
    end)
    UIDropDownMenu_SetText(f.SlotDrop, ADB.SLOT_NOM[f.slot])

    Etiq(f, "Rareté", 20, -74)
    f.RarDrop = CreateFrame("Frame", "ADBItemRarDrop", f, "UIDropDownMenuTemplate")
    f.RarDrop:SetPoint("TOPLEFT", 100, -67)
    UIDropDownMenu_SetWidth(f.RarDrop, 150)
    UIDropDownMenu_Initialize(f.RarDrop, function(self, niveau)
        for i, R in ipairs(ADB.RARETES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = "|cff" .. R[6] .. R[1] .. "|r"
            info.checked = (f.rar == i)
            info.func = function()
                f.rar = i
                UIDropDownMenu_SetText(f.RarDrop, "|cff" .. R[6] .. R[1] .. "|r")
                ADB.MajItemFrame()
            end
            UIDropDownMenu_AddButton(info, niveau)
        end
    end)
    UIDropDownMenu_SetText(f.RarDrop, "|cff" .. ADB.RARETES[1][6] .. ADB.RARETES[1][1] .. "|r")

    Etiq(f, "Nom", 20, -112)
    f.NameEdit = Saisie(f, 106, -109, 190, ADB.ITEM_NOM_MAX)

    Etiq(f, "Icône", 20, -150)
    local ib = CreateFrame("Button", nil, f)
    ib:SetSize(36, 36)
    ib:SetPoint("TOPLEFT", 106, -142)
    local bg = ib:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.4, 0.4, 0.4, 1)
    f.IconeTex = ib:CreateTexture(nil, "ARTWORK")
    f.IconeTex:SetPoint("TOPLEFT", 2, -2)
    f.IconeTex:SetPoint("BOTTOMRIGHT", -2, 2)
    f.IconeTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ib:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ib:SetScript("OnClick", function()
        ADB.OuvrirIcones(function(n)
            f.icon = tostring(n); ADB.MajItemFrame()
        end)
    end)
    Etiq(f, "(cliquer pour choisir)", 150, -152, "GameFontDisableSmall")

    f.Stats = {}
    for i = 1, 3 do
        Etiq(f, ADB.STAT_NOMS[i], 20, -196 - (i - 1) * 26)
        local e = Saisie(f, 124, -193 - (i - 1) * 26, 46, 2, true)
        e:SetText("0")
        e:SetScript("OnTextChanged", function() ADB.MajItemFrame() end)
        f.Stats[i] = e
    end
    f.Total = Etiq(f, "", 190, -222)

    Etiq(f, "Compétences (optionnel)", 20, -276)
    f.CompEdit = Saisie(f, 24, -296, 268, ADB.ITEM_COMP_MAX)

    f.CibleTxt = Etiq(f, "", 20, -328)
    Bouton(f, "Créer", 100, -350, 120, ADB.ValiderCreationItem)

    Etiq(f, "Objets virtuels  -  Qté", 20, -388, "GameFontNormalSmall")
    f.QtyEdit = Saisie(f, 170, -385, 36, 2, true)
    f.QtyEdit:SetText("1")
    Bouton(f, "Potion de Vie", 12, -412, 100, function() ADB.DonnerConso("potvie") end)
    Bouton(f, "Potion de mana", 114, -412, 106, function() ADB.DonnerConso("potmana") end)
    Bouton(f, "Ration", 222, -412, 80, function() ADB.DonnerConso("ration") end)
    Etiq(f, "Skills d'équipement (IDs, ex: 3,7)", 20, -438, "GameFontNormalSmall")
    f.SkEdit = Saisie(f, 24, -456, 268, 20)
    f:SetScript("OnShow", function() ADB.MajItemFrame() end)
    f:SetScript("OnHide", function() ADB.iconFrame:Hide() end)
    f.pret = true
    ADB.MajItemFrame()
end

------------------------------------------------------------------------------
-- 14b. COMBAT PAR TOURS, BANNIERES & SAISIE PV/BOUCLIER
------------------------------------------------------------------------------
function ADB.Banniere(txt)
    local b = ADB.banniere
    if not b then
        b = CreateFrame("Frame", "ADBBanner", UIParent)
        b:SetFrameStrata("FULLSCREEN_DIALOG")
        b:SetSize(1200, 80)
        b:SetPoint("TOP", UIParent, "TOP", 0, -180)
        b.t = b:CreateFontString(nil, "OVERLAY")
        b.t:SetFont(STANDARD_TEXT_FONT, 44, "THICKOUTLINE")
        b.t:SetPoint("CENTER")
        b.t:SetTextColor(1, 0.82, 0.3)
        b:SetScript("OnUpdate", function(s, el)
            s.e = s.e + el
            if s.e > 3.5 then s:Hide() elseif s.e > 2.5 then s:SetAlpha(3.5 - s.e) end
        end)
        ADB.banniere = b
    end
    b.t:SetText(txt)
    b.e = 0
    b:SetAlpha(1)
    b:Show()
end

function ADB.DissiperBoucliers()
    local db = ADB.db
    if (db.sh or 0) > 0 then
        db.sh = 0
        ADB.Print("Votre bouclier s'est dissipé à la fin du combat.")
        ADB.ApresChangementLocal()
    end
    for _, r in pairs(ADB.roster) do r.sh = 0 end
    for _, p in ipairs(ADB.ListerPNJ()) do
        if (p.sh or 0) > 0 then
            p.sh = 0
            if ADB.EstMJ() then ADB.PlanifierPNJ(p.id) end
        end
    end
    ADB.RafraichirTout()
end

function ADB.PhaseCombat(ph)
    if ph == "IDLE" and ADB.phase == "IDLE" then return end
    ADB.phase = ph
    ADB.Banniere(ADB.BAN[ph])
    if ph == "PLAYER_TURN" then
        ADB.finis = {}
        ADB.tourPasse = false
        if ADB.cbJ then ADB.cbJ.Btn:Enable() end
    end
    ADB.MesuresPhase(ph)
    ADB.TalPhase(ph)
    ADB.MajCombatUI()
    if ph == "IDLE" then ADB.DissiperBoucliers() end
end

function ADB.JoueursActifs()
    local t = {}
    for _, u in ipairs(ADB.ListerUnites()) do
        local n = UnitName(u)
        if n and ADB.roster[n] and UnitIsConnected(u) then t[#t + 1] = n end
    end
    return t
end

local BTN = {
    PLAYER_TURN = "Forcer la fin du tour",
    ALLY_TURN = "Fin du Tour Allié",
    ENEMY_TURN = "Fin du Tour Ennemi"
}

ADB.TOUR_NOM = { STARTING = "Préparation", PLAYER_TURN = "Joueurs", ALLY_TURN = "Alliés", ENEMY_TURN = "Ennemis" }
ADB.TOUR_COUL = {
    STARTING = { 1, 0.82, 0.3 },
    PLAYER_TURN = { 0.4, 1, 0.4 },
    ALLY_TURN = { 0.4, 0.7, 1 },
    ENEMY_TURN = { 1, 0.4, 0.3 }
}

function ADB.MajIndicateurTour()
    local t = ADB.indTour
    if not t then
        t = CreateFrame("Frame", "ADBTurnIndicator", UIParent)
        t:SetFrameStrata("HIGH")
        t:SetSize(600, 30)
        t:SetPoint("TOP", UIParent, "TOP", 0, -50)
        t.t = t:CreateFontString(nil, "OVERLAY")
        t.t:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
        t.t:SetPoint("CENTER")
        t:Hide()
        ADB.indTour = t
    end
    local ph = ADB.phase
    local nom = ADB.TOUR_NOM[ph]
    if ph == "IDLE" or not nom then
        t:Hide()
        return
    end
    local txt = "Tour de : " .. nom
    if ph == "PLAYER_TURN" and ADB.tourPasse and not ADB.EstMJ() then
        txt = txt .. " |cff999999(vous avez passé)|r"
    end
    local c = ADB.TOUR_COUL[ph]
    t.t:SetTextColor(c[1], c[2], c[3])
    t.t:SetText(txt)
    t:Show()
end

function ADB.MajCombatUI()
    ADB.MajIndicateurTour()
    local d, p = ADB.cbDM, ADB.cbJ
    if not d then return end
    local ph, mj = ADB.phase, ADB.EstMJ()
    d:SetShown(mj and ph ~= "IDLE")
    p:SetShown((not mj) and ph == "PLAYER_TURN")
    if mj and ph ~= "IDLE" then
        local extra = ""
        if ph == "PLAYER_TURN" then
            local act, ok = ADB.JoueursActifs(), 0
            for _, n in ipairs(act) do if ADB.finis[n] then ok = ok + 1 end end
            extra = format(" (%d/%d)", ok, #act)
        end
        d.Etat:SetText(ADB.BAN[ph] .. extra)
        d.Next:SetShown(BTN[ph] ~= nil)
        if BTN[ph] then d.Next:SetText(BTN[ph]) end
    end
end

function ADB.DiffPhase(code, ph)
    ADB.Envoyer(code)
    ADB.PhaseCombat(ph)
end

function ADB.VerifierFinJoueurs()
    if not ADB.EstMJ() or ADB.phase ~= "PLAYER_TURN" then return end
    local act, ok = ADB.JoueursActifs(), 0
    for _, n in ipairs(act) do if ADB.finis[n] then ok = ok + 1 end end
    if ok >= #act then ADB.PhaseAlliee() end
end

function ADB.LancerCombat()
    if not ADB.EstMJ() then
        ADB.Print("Seul le MJ (chef de groupe) peut lancer un combat."); return
    end
    if ADB.phase ~= "IDLE" then return end
    ADB.DiffPhase("CS", "STARTING")
    ADB.jetonCb = (ADB.jetonCb or 0) + 1
    local j = ADB.jetonCb
    C_Timer.After(3, function()
        if j == ADB.jetonCb and ADB.phase == "STARTING" and ADB.EstMJ() then ADB.PhaseJoueurs() end
    end)
end

function ADB.PhaseJoueurs()
    ADB.DiffPhase("CP", "PLAYER_TURN")
    ADB.VerifierFinJoueurs()
end

function ADB.PhaseAlliee()
    for _, p in ipairs(ADB.db.pnjs) do
        if p.ally then
            ADB.DiffPhase("CA", "ALLY_TURN"); return
        end
    end
    ADB.PhaseEnnemie()
end

function ADB.PhaseEnnemie()
    ADB.DiffPhase("CE", "ENEMY_TURN")
end

function ADB.FinTourMJ()
    if not ADB.EstMJ() then return end
    local ph = ADB.phase
    if ph == "PLAYER_TURN" then
        ADB.PhaseAlliee()
    elseif ph == "ALLY_TURN" then
        ADB.PhaseEnnemie()
    elseif ph == "ENEMY_TURN" then
        ADB.PhaseJoueurs()
    end
end

function ADB.FinCombat()
    if not ADB.EstMJ() or ADB.phase == "IDLE" then return end
    ADB.jetonCb = (ADB.jetonCb or 0) + 1
    ADB.DiffPhase("CF", "IDLE")
end

function ADB.FinTourJoueur()
    ADB.tourPasse = true
    ADB.Envoyer("CD")
    ADB.cbJ.Btn:Disable()
    ADB.MajCombatUI()
end

function ADB.OuvrirSaisiePV(nom, npcId)
    local f = ADB.pvFrame
    local d
    if npcId then d = TrouverPNJ(ADB.db.pnjs, npcId) elseif nom then d = ADB.GetStatBlock(nom) end
    if not d then return end
    f.nom, f.npcId = nom, npcId
    f.Titre:SetText(npcId and ADB.PNJNom(d) or ADB.NomAffiche(nom))
    f.PV:SetText(d.pv)
    f.SH:SetText(d.sh or 0)
    f:Show()
    f.PV:SetFocus()
    f.PV:HighlightText()
end

function ADB.ValiderSaisiePV()
    local f = ADB.pvFrame
    local pv, sh = tonumber(f.PV:GetText()), tonumber(f.SH:GetText())
    if f.npcId then
        if ADB.EstMJ() then
            if sh then ADB.AppliquerValeurPNJ(f.npcId, "sh", sh) end
            if pv then ADB.AppliquerValeurPNJ(f.npcId, "pv", pv, true) end
        end
    elseif f.nom and ADB.PeutModifier(f.nom) then
        if sh then ADB.AppliquerValeur(f.nom, "sh", sh) end
        if pv then ADB.AppliquerValeur(f.nom, "pv", pv, nil, true) end
    end
    f:Hide()
end

function ADB.CreerCombat()
    local d = FenetreBase("ADBCombatDMFrame", 220, 124, "Combat (MJ)")
    ADB.cbDM = d
    d:SetPoint("TOP", UIParent, "TOP", 0, -260)
    d.Etat = Etiq(d, "", 16, -34)
    d.Etat:SetWidth(190)
    d.Next = Bouton(d, "", 20, -62, 180, ADB.FinTourMJ)
    d.Fin = Bouton(d, "Fin du Combat", 20, -90, 180, ADB.FinCombat)

    local p = CreateFrame("Frame", "ADBCombatPlayerFrame", UIParent, "BackdropTemplate")
    ADB.cbJ = p
    p:SetSize(150, 44)
    p:SetFrameStrata("MEDIUM")
    p:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -12, 110)
    ADB.AppliquerFond(p)
    p.Btn = Bouton(p, "Fin de Tour", 12, -11, 126, ADB.FinTourJoueur)
    p:Hide()

    local mj = ADBMJFrame
    mj.RestButton:ClearAllPoints()
    mj.RestButton:SetPoint("BOTTOMLEFT", 20, 16)
    mj.RestButton:SetWidth(125)
    Bouton(mj, "Combat", 155, -130, 125, ADB.LancerCombat)

    local c = CreateFrame("CheckButton", "ADBNpcAllyCheck", ADBNpcCreateFrame, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", 94, -136)
    ADBNpcCreateFrame.AllyCheck = c

    local g = FenetreBase("ADBPVFrame", 240, 130, "PV / Bouclier")
    ADB.pvFrame = g
    g:SetPoint("CENTER", 0, 100)
    g.Titre = Etiq(g, "", 16, -34, "GameFontNormal")
    Etiq(g, "PV", 16, -60)
    g.PV = Saisie(g, 76, -57, 60, 4, true)
    Etiq(g, "Bouclier", 16, -86)
    g.SH = Saisie(g, 76, -83, 60, 3, true)
    g.PV:SetScript("OnEnterPressed", ADB.ValiderSaisiePV)
    g.SH:SetScript("OnEnterPressed", ADB.ValiderSaisiePV)
    Bouton(g, "OK", 150, -70, 70, ADB.ValiderSaisiePV)
    tinsert(UISpecialFrames, "ADBPVFrame")
end

------------------------------------------------------------------------------
-- 15. EVENEMENTS
------------------------------------------------------------------------------
function ADB.OnLoad(frame)
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_LEADER_CHANGED")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("UNIT_MODEL_CHANGED")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    for _, evt in ipairs({ "UNIT_CONNECTION", "PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE" }) do
        pcall(frame.RegisterEvent, frame, evt)
    end
end

function ADB.OnEvent(frame, event, ...)
    local gestionnaire = ADB.Evenements[event]
    if gestionnaire then gestionnaire(...) end
end

function ADB.Evenements.ADDON_LOADED(nomAddon)
    if nomAddon == "AddonDesBrumes" then
        InitialiserDB()
        C_ChatInfo.RegisterAddonMessagePrefix(ADB.PREFIX)
    elseif nomAddon == "Blizzard_CompactRaidFrames" and ADB.db and ADB.db.uiRemplacee then
        ADB.MasquerUIBlizzard()
    end
end

function ADB.Evenements.PLAYER_LOGIN()
    if not ADB.db then InitialiserDB() end
    ADB.playerName = UnitName("player")
    ADBPlayerFrame.charName = ADB.playerName
    ADBPlayerFrame.unitToken = "player"
    ADBTargetFrame.unitToken = "target"

    ADB.InitDropdowns()
    ADB.CreerInv()
    ADB.CreerFenetreItem()
    ADB.CreerFenetreIcones()

    ADB.CreerCombat()
    ADB.InitTalents()
    tinsert(UISpecialFrames, "ADBConfigFrame")
    tinsert(UISpecialFrames, "ADBFicheFrame")
    tinsert(UISpecialFrames, "ADBNpcCreateFrame")
    tinsert(UISpecialFrames, "ADBMJFrame")
    tinsert(UISpecialFrames, "ADBRestFrame")
    tinsert(UISpecialFrames, "ADBInvFrame")
    tinsert(UISpecialFrames, "ADBItemFrame")
    tinsert(UISpecialFrames, "ADBIconFrame")

    ADB.PositionnerBouton()

    if ADB.db.uiRemplacee then
        CopierPosition(PlayerFrame, ADBPlayerFrame, 5)
        CopierPosition(TargetFrame, ADBTargetFrame, 5)
        ADB.MasquerUIBlizzard()
        ADBPlayerFrame:Show()
        ADBGroupFrame:Show()
        ADB.MiseEnPageGroupe()
    end
    ADB.MiseEnPageNPC()
    ADB.RafraichirTout()
end

function ADB.Evenements.PLAYER_ENTERING_WORLD()
    if not ADB.db then return end
    if ADB.db.uiRemplacee then ADB.MasquerUIBlizzard() end
    ADB.MiseEnPageGroupe()
    ADB.MiseEnPageNPC()
    ADB.RafraichirTout()
    C_Timer.After(1, ADB.MajModeles)
    if IsInGroup() then
        ADB.PlanifierDiffusion(true)
        if ADB.EstMJ() then ADB.PlanifierPNJComplet() end
    end
end

function ADB.Evenements.GROUP_ROSTER_UPDATE()
    if not ADB.db or not ADB.playerName then return end
    if not IsInGroup() and ADB.phase ~= "IDLE" then ADB.PhaseCombat("IDLE") end
    local presents = ADB.NomsGroupe()
    for nom in pairs(ADB.roster) do
        if not presents[nom] then ADB.roster[nom] = nil end
    end
    if ADB.EstMJ() or not IsInGroup()
        or (ADB.pnjSource and not ADB.EstNomMJ(ADB.pnjSource)) then
        if #ADB.pnjRecus > 0 then wipe(ADB.pnjRecus) end
        ADB.pnjSource = nil
    end
    ADB.MiseEnPageGroupe()
    ADB.MiseEnPageNPC()
    ADB.RafraichirTout()
    if IsInGroup() then
        ADB.PlanifierDiffusion(true)
        if ADB.EstMJ() then ADB.PlanifierPNJComplet() end
    end
end

ADB.Evenements.PARTY_LEADER_CHANGED = ADB.Evenements.GROUP_ROSTER_UPDATE

ADB.Evenements.UNIT_CONNECTION = function() ADB.PlanifierMiseEnPage() end
ADB.Evenements.PARTY_MEMBER_DISABLE = ADB.Evenements.UNIT_CONNECTION
ADB.Evenements.PARTY_MEMBER_ENABLE = ADB.Evenements.UNIT_CONNECTION

function ADB.Evenements.PLAYER_TARGET_CHANGED()
    if ADB.db and ADB.playerName then
        ADB.RafraichirCible(true)
        ADB.RafraichirInv()
        if ADB.itemFrame and ADB.itemFrame:IsShown() then ADB.MajItemFrame() end
    end
end

function ADB.Evenements.UNIT_MODEL_CHANGED()
    ADB.MajModeles()
end

function ADB.Evenements.PLAYER_REGEN_ENABLED()
    if ADB.masquageEnAttente then ADB.MasquerUIBlizzard() end
    if ADB.layoutEnAttente then ADB.MiseEnPageGroupe() end
end

------------------------------------------------------------------------------
-- 16. COMMANDES /brumes
------------------------------------------------------------------------------
SLASH_ADDONDESBRUMES1 = "/brumes"
SLASH_ADDONDESBRUMES2 = "/adb"
SlashCmdList["ADDONDESBRUMES"] = function(msg)
    local cmd, reste = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "config" then
        ADB.BasculerConfig()
    elseif cmd == "fiche" then
        if reste ~= "" then
            if reste ~= ADB.playerName and not ADB.EstMJ() then
                ADB.Print("Seul le MJ peut consulter la fiche des autres joueurs.")
            elseif ADB.GetStatBlock(reste) then
                ADB.OuvrirFiche(reste)
            else
                ADB.Print("Aucune fiche connue pour " .. reste .. ".")
            end
        else
            ADB.VoirFicheCible()
        end
    elseif cmd == "nom" then
        ADB.DefinirNomRP(reste)
        ADB.Print("Nom RP : " .. ADB.NomAffiche(ADB.playerName))
    elseif cmd == "pnj" then
        ADB.OuvrirCreationPNJ()
    elseif cmd == "mj" or cmd == "xp" then
        ADB.OuvrirMJ()
    elseif cmd == "combat" then
        ADB.LancerCombat()
    elseif cmd == "repos" then
        ADB.OuvrirRepos()
    elseif cmd == "inv" or cmd == "sac" then
        ADB.BasculerInv()
    elseif cmd == "objet" then
        ADB.OuvrirCreationItem()
    elseif cmd == "ui" then
        ADB.db.uiRemplacee = not ADB.db.uiRemplacee
        ADB.Print("Remplacement de l'interface : " .. (ADB.db.uiRemplacee and "ACTIVÉ" or "DÉSACTIVÉ")
            .. ". Tapez /reload pour appliquer.")
    elseif cmd == "talents" then
        ADB.BasculerTalents()
    else
        ADB.Print("Commandes : /brumes (fiche), /brumes fiche [nom], /brumes nom [Nom RP], "
            .. "/brumes inv, /brumes objet, /brumes pnj, /brumes mj (XP), /brumes repos, /brumes talents, /brumes ui")
    end
end
