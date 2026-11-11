------------------------------------------------------------------------------
-- Talents.lua : arbres, editeur MJ, barre d'action, resolution, cooldowns, specs
------------------------------------------------------------------------------
local ADB = ADB
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local Borner, Encoder, Decoder, Net = ADB.Borner, ADB.Encoder, ADB.Decoder, ADB.NettoyerNom
local UI = ADB.UI
local Etiq, Saisie, Bouton, FenetreBase = UI.Etiq, UI.Saisie, UI.Bouton, UI.FenetreBase
local IconeTex = ADB.IconeTex

local TAL = {
    COLS = 12,
    ROWS = 32,
    XOFF = 1000000,
    CELL = 52,
    ICON = 38,
    MAX_REQ = 6,
    DESC_MAX = 1000,
    NOM_MAX = 40,
    MANA_MAX = 999,
    COUT_MAX = 999,
    POR_MAX = 200,
    ZOE_MAX = 200,
    TAGS_MAX = 30,
    TYPES = { "Actif", "Passif" },
    STATS = { "Aucune", "Force", "Agilité", "Intelligence", "Principale" },
    INTERS = { "Dégâts", "Soins", "Bouclier", "Autre" },
    ELEMS = { "Physique", "Sacré", "Ombre", "Chaos", "Feu", "Nature", "Astral", "Givre" },
    LIMITES = { { "1/repos", 1, "r" }, { "1/5 tours", 5, "t" }, { "1/10 tours", 10, "t" },
        { "1/3 repos", 3, "r" }, { "Illimité", 0, "i" }, { "2/repos", 2, "r", 2 } },
}
TAL.TAGREQ = {
    dreadsteed = "Pierre d'âme de Destrier",
}
ADB.TAL = TAL
ADB.CMD_TAL = { TN = true, TD = true, TF = true, TG = true, TX = true, TS = true, TE = true, TQ = true, HQ = true, HR = true, TC = true, TK = true }

------------------------------------------------------------------------------
-- 1. DONNEES
------------------------------------------------------------------------------
local function NetDesc(s)
    s = tostring(s or ""):gsub("[%c|]", " ")
    return strtrim(s):sub(1, TAL.DESC_MAX * 2)
end

local function NetTag(s)
    return (tostring(s or ""):lower():match("[%w_]+") or ""):sub(1, 16)
end

local function NetTags(s)
    local t, vus = {}, {}
    local src = type(s) == "table" and table.concat(s, ",") or tostring(s or "")
    for w in src:lower():gmatch("[%w_]+") do
        w = w:sub(1, 32)
        if not vus[w] and #t < TAL.TAGS_MAX then
            vus[w] = true
            t[#t + 1] = w
        end
    end
    return t
end

ADB.TalNetTags = NetTags

local function Extras(n, t)
    n.coutPV = Borner(floor(tonumber(t.coutPV) or -1), -1, TAL.COUT_MAX)
    n.portee = Borner(floor(tonumber(t.portee) or -1), -1, TAL.POR_MAX)
    n.precision = Borner(floor(tonumber(t.precision) or -1), -1, 100)
    n.zoe = Borner(floor(tonumber(t.zoe) or -1), -1, TAL.ZOE_MAX)
    n.tags = NetTags(t.tags)
    n.spe, n.specX, n.specY = (t.spe == true), NetTag(t.specX), NetTag(t.specY)
    n.buffId = (n.typ == 1) and Borner(floor(tonumber(t.buffId) or 0), 0, 9999) or 0
    if n.typ == 2 then
        n.coutPV, n.portee, n.precision, n.zoe = -1, -1, -1, -1
    else
        n.spe, n.specX, n.specY = false, "", ""
    end
end

local function ValiderNoeud(t)
    if type(t) ~= "table" then return nil end
    local id = floor(tonumber(t.id) or 0)
    if id < 1 then return nil end
    local icon = tostring(t.icon or "")
    if #icon == 0 or #icon > 40 or icon:find("[^%w_]") then icon = "INV_Misc_QuestionMark" end
    local nom = Net(t.nom):sub(1, TAL.NOM_MAX * 2)
    if nom == "" then nom = "Talent" end
    local req, vus = {}, {}
    if type(t.req) == "table" then
        for _, r in ipairs(t.req) do
            r = floor(tonumber(r) or 0)
            if r >= 1 and r ~= id and not vus[r] and #req < TAL.MAX_REQ then
                vus[r] = true
                req[#req + 1] = r
            end
        end
    end
    local n = {
        id = id,
        x = Borner(floor(tonumber(t.x) or 1), 1, TAL.COLS),
        y = Borner(floor(tonumber(t.y) or 1), 1, TAL.ROWS),
        typ = Borner(floor(tonumber(t.typ) or 1), 1, 2),
        stat = Borner(floor(tonumber(t.stat) or 1), 1, #TAL.STATS),
        inter = Borner(floor(tonumber(t.inter) or 4), 1, 4),
        elem = Borner(floor(tonumber(t.elem) or 1), 1, 8),
        mana = Borner(floor(tonumber(t.mana) or 0), 0, TAL.MANA_MAX),
        lim = Borner(floor(tonumber(t.lim) or 5), 1, #TAL.LIMITES),
        reac = t.reac == true,
        bonus = t.bonus == true,
        icon = icon,
        nom = nom,
        desc = NetDesc(t.desc),
        req = req,
    }
    Extras(n, t)
    if n.typ == 2 then n.mana, n.lim, n.reac, n.bonus = 0, 5, false, false end
    return n
end

ADB.TalValiderNoeud = ValiderNoeud

------------------------------------------------------------------------------
-- ColorBox : rectangles colorés de fond (purement visuels), par classe
------------------------------------------------------------------------------
local function ValiderColorBox(t)
    if type(t) ~= "table" then return nil end
    local id = floor(tonumber(t.id) or 0)
    if id < 1 then return nil end
    local x1 = Borner(floor(tonumber(t.x1) or 1), 1, TAL.COLS)
    local x2 = Borner(floor(tonumber(t.x2) or 1), 1, TAL.COLS)
    local y1 = Borner(floor(tonumber(t.y1) or 1), 1, TAL.ROWS)
    local y2 = Borner(floor(tonumber(t.y2) or 1), 1, TAL.ROWS)
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end
    return {
        id = id,
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        r = Borner(floor(tonumber(t.r) or 80), 0, 255),
        g = Borner(floor(tonumber(t.g) or 80), 0, 255),
        b = Borner(floor(tonumber(t.b) or 80), 0, 255),
        a = Borner(floor(tonumber(t.a) or 30), 5, 100),
    }
end
ADB.TalValiderColorBox = ValiderColorBox

function ADB.ColorBoxMessage(ci, b)
    return format("TC;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d", ci, b.id, b.x1, b.y1, b.x2, b.y2, b.r, b.g, b.b, b.a)
end

function ADB.TalInitDB(db)
    if type(db.talents) ~= "table" then db.talents = {} end
    local T = db.talents
    local arbres = {}
    if type(T.arbres) == "table" then
        for classe, a in pairs(T.arbres) do
            if ADB.CLASSE_MAP[classe] and type(a) == "table" and type(a.noeuds) == "table" then
                local noeuds, maxId = {}, 0
                for _, t in pairs(a.noeuds) do
                    local n = ValiderNoeud(t)
                    if n and not noeuds[n.id] then
                        noeuds[n.id] = n
                        maxId = max(maxId, n.id)
                    end
                end
                local boxes, maxB = {}, 0
                if type(a.colorBoxes) == "table" then
                    for _, tb in pairs(a.colorBoxes) do
                        local b = ValiderColorBox(tb)
                        if b and not boxes[b.id] then
                            boxes[b.id] = b
                            maxB = max(maxB, b.id)
                        end
                    end
                end
                arbres[classe] = {
                    prochain = max(maxId + 1, floor(tonumber(a.prochain) or 1)),
                    noeuds = noeuds,
                    colorBoxes = boxes,
                    cbProchain = max(maxB + 1, floor(tonumber(a.cbProchain) or 1)),
                }
            end
        end
    end
    T.arbres = arbres
    local appris = {}
    if type(T.appris) == "table" then
        for classe, ids in pairs(T.appris) do
            if ADB.CLASSE_MAP[classe] and type(ids) == "table" then
                appris[classe] = {}
                for id, v in pairs(ids) do
                    if v and tonumber(id) then appris[classe][floor(id)] = true end
                end
            end
        end
    end
    T.appris = appris
    local cd = {}
    if type(T.cd) == "table" then
        for cle, v in pairs(T.cd) do
            if type(cle) == "string" and tonumber(v) and v > 0 then cd[cle] = Borner(floor(v), 1, 99) end
        end
    end
    T.cd = cd
    local ex = {}
    if type(T.extras) == "table" then
        for c, v in pairs(T.extras) do
            if v and ADB.CLASSE_MAP[c] then ex[c] = true end
        end
    end
    T.extras = ex
end

local function Appris(classe)
    local ap = ADB.db.talents.appris
    if type(ap[classe]) ~= "table" then ap[classe] = {} end
    return ap[classe]
end

function ADB.TalArbre(classe, creer)
    local arbres = ADB.db.talents.arbres
    if not arbres[classe] and creer then
        arbres[classe] = { prochain = 1, noeuds = {}, colorBoxes = {}, cbProchain = 1 }
    end
    return arbres[classe]
end

function ADB.TalIndexClasse(nom)
    for i, c in ipairs(ADB.CLASSES) do
        if c[1] == nom then return i end
    end
end

-- Nœuds des classes additionnelles : proxys à ID décalé (classe * XOFF + id)
local proxies = {}
function ADB.TalNoeudExtra(cl, id)
    local ci = ADB.TalIndexClasse(cl)
    local a = ADB.TalArbre(cl)
    local n = a and a.noeuds[id]
    if not (ci and n) then return nil end
    local pid = ci * TAL.XOFF + id
    local p = proxies[pid]
    if not p or getmetatable(p).__index ~= n then
        p = setmetatable({ id = pid, rawid = id, classe = cl }, { __index = n })
        proxies[pid] = p
    end
    return p
end

function ADB.TalNoeudExtraId(pid)
    local ci, id = floor(pid / TAL.XOFF), pid % TAL.XOFF
    local c = ADB.CLASSES[ci]
    if not c or c[1] == ADB.db.classe or not ADB.TalAcces(c[1]) then return nil end
    return ADB.TalNoeudExtra(c[1], id)
end

function ADB.TalNoeudPropre(id)
    if type(id) == "number" and id >= TAL.XOFF then return ADB.TalNoeudExtraId(id) end
    local a = ADB.TalArbre(ADB.db.classe)
    return a and a.noeuds[id] or nil
end

function ADB.PeutEditerTalents()
    return ADB.EstMJ() or not IsInGroup()
end

function ADB.TalPointsTotal() return 3 + (ADB.db.level or 1) end

------------------------------------------------------------------------------
-- Classes additionnelles : tag d'objet "AddClassNom" (inventaire ou équipement porté)
------------------------------------------------------------------------------
local ACCENTS = {
    ["é"] = "e",
    ["è"] = "e",
    ["ê"] = "e",
    ["ë"] = "e",
    ["É"] = "e",
    ["à"] = "a",
    ["â"] = "a",
    ["î"] = "i",
    ["ï"] = "i",
    ["ô"] = "o",
    ["û"] = "u",
    ["ù"] = "u",
    ["ç"] = "c"
}
local function Slug(s)
    s = s:lower()
    s = s:gsub("[\195][\128-\191]", function(c) return ACCENTS[c] or "" end)
    return (s:gsub("[^%w]", ""))
end
TAL.CLASSTAG = {}
for _, c in ipairs(ADB.CLASSES) do
    if c[1] ~= ADB.MJ_CLASSE and c[1] ~= ADB.EQUIP_CLASSE then
        TAL.CLASSTAG["addclass" .. Slug(c[1])] = c[1]
    end
end

function ADB.TalClassesSupp()
    local res, vus, db = {}, {}, ADB.db
    if not db then return res end
    local function Scan(it)
        if type(it) ~= "table" or type(it.tags) ~= "table" then return end
        for _, t in ipairs(it.tags) do
            local c = TAL.CLASSTAG[t]
            if c and c ~= db.classe then vus[c] = true end
        end
    end
    for i = 1, ADB.INV_SLOTS do Scan(db.inv and db.inv[i]) end
    for _, s in ipairs(ADB.SLOTS) do Scan(db.equip and db.equip[s[1]]) end
    for _, c in ipairs(ADB.CLASSES) do
        if vus[c[1]] then res[#res + 1] = c[1] end
    end
    return res
end

function ADB.TalClassesAcces()
    local res = { ADB.db.classe }
    for _, c in ipairs(ADB.TalClassesSupp()) do res[#res + 1] = c end
    return res
end

function ADB.TalAcces(cl)
    if not cl then return false end
    for _, c in ipairs(ADB.TalClassesAcces()) do
        if c == cl then return true end
    end
    return false
end

local function CV(cl)
    if cl then return cl end
    if ADB.talVue and ADB.TalAcces(ADB.talVue) then return ADB.talVue end
    return ADB.db.classe
end

function ADB.TalPointsUtilises()
    local n = 0
    for _, cl in ipairs(ADB.TalClassesAcces()) do
        local a = ADB.TalArbre(cl)
        if a then
            for id in pairs(Appris(cl)) do
                local nd = a.noeuds[id]
                if nd and not ADB.TalATag(nd, "refund") then n = n + 1 end
            end
        end
    end
    return n
end

function ADB.TalPointsRestants() return ADB.TalPointsTotal() - ADB.TalPointsUtilises() end

function ADB.TalNettoyerPoints()
    local T = ADB.db.talents
    if type(T.extras) ~= "table" then T.extras = {} end
    local acces, ok = ADB.TalClassesAcces(), {}
    for i, c in ipairs(acces) do
        ok[c] = true
        if i > 1 then T.extras[c] = true end
    end
    -- classe additionnelle perdue (objet retiré) : compétences oubliées, points récupérés
    for c in pairs(T.extras) do
        if not ok[c] then
            T.appris[c] = nil
            T.extras[c] = nil
        end
    end
    local ids = {}
    for rang, cl in ipairs(acces) do
        local a = ADB.TalArbre(cl)
        if a and next(a.noeuds) ~= nil then
            local ap = Appris(cl)
            for id in pairs(ap) do
                if a.noeuds[id] then ids[#ids + 1] = { cl = cl, id = id, r = rang } else ap[id] = nil end
            end
        end
    end
    table.sort(ids, function(p, q)
        if p.r ~= q.r then return p.r < q.r end
        return p.id < q.id
    end)
    local payants = {}
    for _, e in ipairs(ids) do
        if not ADB.TalATag(ADB.TalArbre(e.cl).noeuds[e.id], "refund") then payants[#payants + 1] = e end
    end
    for i = #payants, ADB.TalPointsTotal() + 1, -1 do Appris(payants[i].cl)[payants[i].id] = nil end
    local vue
    for _, e in ipairs(ids) do
        local ap = Appris(e.cl)
        if ap[e.id] and ADB.TalArbre(e.cl).noeuds[e.id].spe then
            if vue then ap[e.id] = nil else vue = true end
        end
    end
end

-- Specialisation apprise (une seule, toutes classes confondues)
function ADB.TalSpeActive()
    for _, cl in ipairs(ADB.TalClassesAcces()) do
        local a = ADB.TalArbre(cl)
        if a then
            local best
            for id in pairs(Appris(cl)) do
                local n = a.noeuds[id]
                if n and n.spe and (not best or n.id < best.id) then best = n end
            end
            if best then return best end
        end
    end
    return nil
end

function ADB.TalATag(n, tag)
    for _, t in ipairs(n.tags) do
        if t == tag then return true end
    end
    return false
end

-- Tag X : +1 sur la valeur de base
function ADB.TalBonusSpe(n)
    local s = ADB.TalSpeActive()
    if s and s.specX ~= "" and ADB.TalATag(n, s.specX) then return 1 end
    return 0
end

function ADB.InvATag(tag)
    local inv = ADB.db and ADB.db.inv
    if not inv then return nil end
    for i = 1, ADB.INV_SLOTS do
        local it = inv[i]
        if it and it.tags then
            for _, t in ipairs(it.tags) do
                if t == tag then return it end
            end
        end
    end
    return nil
end

-- Prérequis dus aux tags du talent : { { nom = "...", ok = bool }, ... }
function ADB.TalTagsRequis(n)
    local res = {}
    for _, t in ipairs(n.tags or {}) do
        local nom = TAL.TAGREQ[t]
        if nom then res[#res + 1] = { nom = nom, ok = ADB.InvATag(t) ~= nil } end
    end
    return res
end

function ADB.TalPrerequisOK(n, cl)
    cl = CV(cl)
    local a, ap = ADB.TalArbre(cl), Appris(cl)
    for _, r in ipairs(n.req) do
        if a.noeuds[r] and not ap[r] then return false end
    end
    for _, r in ipairs(ADB.TalTagsRequis(n)) do
        if not r.ok then return false end
    end
    return true
end

function ADB.TalPeutApprendre(n, cl)
    cl = CV(cl)
    if Appris(cl)[n.id] then return false end
    if ADB.TalPointsRestants() <= 0 and not ADB.TalATag(n, "refund") then return false end
    if n.spe and ADB.TalSpeActive() then return false end
    return ADB.TalPrerequisOK(n, cl)
end

-- Tous les talents appris (classe principale : nœuds réels ; classes additionnelles : proxys)
function ADB.TalNoeudsAppris()
    local res = {}
    for i, cl in ipairs(ADB.TalClassesAcces()) do
        local a = ADB.TalArbre(cl)
        if a then
            for id in pairs(Appris(cl)) do
                local n = a.noeuds[id]
                if n then res[#res + 1] = (i == 1) and n or ADB.TalNoeudExtra(cl, id) end
            end
        end
    end
    return res
end

function ADB.TalActifs()
    local rk = {}
    for i, c in ipairs(ADB.TalClassesAcces()) do rk[c] = i end
    local res = {}
    for _, n in ipairs(ADB.TalNoeudsAppris()) do
        if n.typ == 1 then res[#res + 1] = n end
    end
    local function R(n) return n.classe and rk[n.classe] or 1 end
    table.sort(res, function(p, q)
        local rp, rq = R(p), R(q)
        if rp ~= rq then return rp < rq end
        if p.y ~= q.y then return p.y < q.y end
        if p.x ~= q.x then return p.x < q.x end
        return p.id < q.id
    end)
    return res
end

------------------------------------------------------------------------------
-- 2. VALEURS DYNAMIQUES, COOLDOWNS, ETAT
------------------------------------------------------------------------------
function ADB.TalStatEff(n)
    if n.stat ~= 5 then return n.stat end
    local d = ADB.GetStatBlock(ADB.playerName)
    if not d then return 1 end
    if d.force >= d.agilite and d.force >= d.intelligence then return 2 end
    return d.agilite >= d.intelligence and 3 or 4
end

function ADB.TalMult(n)
    local s = ADB.TalStatEff(n)
    if s <= 1 then return 1 end
    local d = ADB.GetStatBlock(ADB.playerName)
    if not d then return 1 end
    return ({ d.multForce, d.multAgi, d.multInt })[s - 1]
end

-- "[2]" -> brut : "2" (bleu) / modifie : (valeur+bonus)*mult (vert). Retourne texte, 1re valeur modifiee.
function ADB.TalTexte(desc, modifie, mult, bonus)
    local premier
    local txt = (tostring(desc or ""):gsub("%[([%d%.,]+)%]", function(x)
        local v = tonumber((x:gsub(",", ".")))
        if not v then return nil end
        if modifie then
            local r = floor((v + (bonus or 0)) * mult + 0.5)
            premier = premier or r
            return "|cff40ff40" .. r .. "|r"
        end
        return "|cff66ccff" .. x .. "|r"
    end))
    return txt, premier
end

local function CleCD(id) return ADB.db.classe .. ":" .. id end

function ADB.TalCD(n) return ADB.db.talents.cd[CleCD(n.id)] or 0 end

function ADB.TalPoserCD(n)
    local L = TAL.LIMITES[n.lim]
    if L[2] <= 0 then return end
    local cd, k = ADB.db.talents.cd, CleCD(n.id)
    if L[4] then cd[k] = (cd[k] or 0) + 1 else cd[k] = L[2] end
end

function ADB.TalTickCD(unite)
    local cd, arbres = ADB.db.talents.cd, ADB.db.talents.arbres
    for cle, v in pairs(cd) do
        local classe, id = cle:match("^(.-):(%d+)$")
        local a = classe and arbres[classe]
        local n = ADB.TalNoeudDepuisId(a, tonumber(id))
        if not n then
            cd[cle] = nil
        elseif TAL.LIMITES[n.lim][3] == unite then
            if TAL.LIMITES[n.lim][4] or v <= 1 then cd[cle] = nil else cd[cle] = v - 1 end
        end
    end
end

function ADB.TalResetTours()
    local cd, arbres = ADB.db.talents.cd, ADB.db.talents.arbres
    for cle in pairs(cd) do
        local classe, id = cle:match("^(.-):(%d+)$")
        local a = classe and arbres[classe]
        local n = ADB.TalNoeudDepuisId(a, tonumber(id))
        if not n or TAL.LIMITES[n.lim][3] == "t" then cd[cle] = nil end
    end
end

function ADB.TalRepos()
    ADB.TalTickCD("r")
    ADB.TalRafraichirBarre()
end

function ADB.TalEtat(n)
    local d = ADB.GetStatBlock(ADB.playerName)
    if n.mana > 0 and d.pm < n.mana then
        return false, format("Mana insuffisant (%d / %d requis).", d.pm, n.mana), "mana"
    end
    if n.coutPV > 0 and d.pv < n.coutPV then
        return false, format("PV insuffisants (%d / %d requis).", d.pv, n.coutPV)
    end
    local cd, L = ADB.TalCD(n), TAL.LIMITES[n.lim]
    if cd >= (L[4] or 1) then
        if L[4] then return false, "Limite d'utilisation atteinte (jusqu'au prochain repos).", "cd" end
        local u = L[3]
        return false, format("Compétence en recharge : %d %s restant%s.", cd,
            u == "t" and (cd > 1 and "tours" or "tour") or "repos", ""), "cd"
    end
    return true
end

function ADB.TalPhase(ph)
    if not ADB.db or not ADB.db.talents then return end
    if ph == "PLAYER_TURN" and not ADB.EstMJ() then
        ADB.TalTickCD("t")
        if ADB.saut then
            ADB.saut = nil
            ADB.Print("Vous avez joué en avance avec une compétence de réaction, vous ne pouvez jouer ce tour-ci.")
            ADB.FinTourJoueur()
        end
    elseif ph == "IDLE" then
        ADB.TalResetTours()
        ADB.saut, ADB.tourPasse = nil, nil
    end
    ADB.TalRafraichirBarre()
end

------------------------------------------------------------------------------
-- 3. INFO-BULLES
------------------------------------------------------------------------------
function ADB.TalInfobulle(owner, n, mode, G, ancre)
    G = G or GameTooltip
    G:SetOwner(owner, ancre or "ANCHOR_RIGHT")
    G:AddLine(n.nom, 1, 0.82, 0)
    G:AddLine(TAL.TYPES[n.typ], 0.7, 0.7, 0.7)
    if n.spe then G:AddLine("Spécialisation (une seule à la fois)", 0.8, 0.5, 1) end
    if n.stat > 1 then
        G:AddLine("Statistique : " .. TAL.STATS[ADB.TalStatEff(n)] .. (n.stat == 5 and " (Principale)" or ""), 1, 1, 1)
    end
    G:AddLine("Interaction : " .. TAL.INTERS[n.inter], 1, 1, 1)
    G:AddLine("Élément : " .. TAL.ELEMS[n.elem], 1, 1, 1)
    if n.typ == 1 then
        if n.mana > 0 then G:AddLine("Coût : " .. n.mana .. " Mana", 0.3, 0.55, 1) end
        if n.coutPV > 0 then G:AddLine("Coût : " .. n.coutPV .. " PV", 1, 0.3, 0.3) end
        if n.portee > 0 then G:AddLine("Portée : " .. n.portee .. " m", 1, 1, 1) end
        if n.precision > 0 then G:AddLine("Précision : " .. n.precision, 1, 1, 1) end
        if n.zoe > 0 then G:AddLine("Zone d'effet : " .. n.zoe .. " m", 1, 1, 1) end
        if n.lim ~= 5 then G:AddLine("Limite d'utilisation : " .. TAL.LIMITES[n.lim][1], 1, 1, 1) end
        if n.reac then G:AddLine("Compétence utilisable en Réaction", 1, 0.5, 0.1) end
        if n.bonus then G:AddLine("Compétence utilisant l'Action Bonus", 1, 0.5, 0.1) end
    end
    local barre = (mode == "barre")
    local txt = ADB.TalTexte(n.desc, barre, barre and ADB.TalMult(n) or 1, barre and ADB.TalBonusSpe(n) or 0)
    if txt ~= "" then
        G:AddLine(" ")
        G:AddLine(txt, 1, 0.9, 0.6, true)
    end
    return G
end

function ADB.TalSurvol(b)
    local a = ADB.TalArbre(ADB.talVue)
    local n = a and a.noeuds[b.id]
    if not n then return end
    local f = ADB.talFrame
    local propre = ADB.TalAcces(ADB.talVue)
    local G = ADB.TalInfobulle(b, n, "arbre")
    local ap = propre and Appris(ADB.talVue) or {}
    local tr = ADB.TalTagsRequis(n)
    if #n.req > 0 or #tr > 0 then
        G:AddLine(" ")
        for _, r in ipairs(n.req) do
            local p = a.noeuds[r]
            if p then
                local ok = propre and ap[r]
                G:AddLine("Prérequis : " .. p.nom, ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
            end
        end
        for _, r in ipairs(tr) do
            local ok = propre and r.ok
            G:AddLine("Prérequis : " .. r.nom, ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
        end
    end
    G:AddLine(" ")
    if f.edition then
        G:AddLine("Clic : sélectionner", 0.6, 0.6, 0.6)
    elseif ADB.talVue == ADB.MJ_CLASSE then
        G:AddLine("Clic gauche : déclencher (annonce au chat)", 1, 0.5, 0.1)
    elseif propre then
        if ap[n.id] then
            G:AddLine("Appris - clic droit : désapprendre", 0.3, 1, 0.3)
        elseif ADB.TalPeutApprendre(n, ADB.talVue) then
            G:AddLine("Clic gauche : apprendre (1 point)", 0.3, 1, 0.3)
        else
            G:AddLine("Verrouillé (prérequis, points ou spécialisation)", 1, 0.3, 0.3)
        end
    end
    G:Show()
end

------------------------------------------------------------------------------
-- 4. SYNCHRONISATION DES ARBRES (MJ -> joueurs)
--   TN;ci;id;x;y;typ;stat;inter;elem;mana;lim;reac;bonus;req;icone;nom
--   TD;ci;id;n;total;morceau
--   TF;ci;id;coutPV;portee;precision;zoe;spe;specX;specY;tags
--   TX;ci;id  TS;ci  TE;ci  TQ;ci  HQ / HR (validation hors-tour)
------------------------------------------------------------------------------
local function Decouper(s, taille)
    local t, i = {}, 1
    while i <= #s do
        local j = min(i + taille - 1, #s)
        while j < #s and j > i and (s:byte(j + 1) or 0) >= 0x80 and (s:byte(j + 1) or 0) < 0xC0 do
            j = j - 1
        end
        t[#t + 1] = s:sub(i, j)
        i = j + 1
    end
    return t
end

ADB.Decouper = Decouper

local function MessagesNoeud(ci, n)
    local msgs = { format("TN;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%s;%s;%s",
        ci, n.id, n.x, n.y, n.typ, n.stat, n.inter, n.elem, n.mana, n.lim,
        n.reac and 1 or 0, n.bonus and 1 or 0, table.concat(n.req, ","), n.icon, Encoder(n.nom)) }
    local ch = Decouper(n.desc, 70)
    for i, s in ipairs(ch) do
        msgs[#msgs + 1] = format("TD;%d;%d;%d;%d;%s", ci, n.id, i, #ch, Encoder(s))
    end
    msgs[#msgs + 1] = format("TF;%d;%d;%d;%d;%d;%d;%d;%s;%s;%s;%d", ci, n.id, n.coutPV, n.portee,
        n.precision, n.zoe, n.spe and 1 or 0, n.specX, n.specY, "", n.buffId or 0)
    local tg = Decouper(table.concat(n.tags, ","), 120)
    for i, s in ipairs(tg) do msgs[#msgs + 1] = format("TG;%d;%d;%d;%d;%s", ci, n.id, i, #tg, s) end
    return msgs
end

function ADB.TalEnfiler(msg)
    local f = ADB.talFile
    f[#f + 1] = msg
    if not ADB.talTicker then
        ADB.talTicker = C_Timer.NewTicker(0.12, function()
            local m = tremove(ADB.talFile, 1)
            if m then ADB.Envoyer(m) end
            if #ADB.talFile == 0 and ADB.talTicker then
                ADB.talTicker:Cancel()
                ADB.talTicker = nil
            end
        end)
    end
end

function ADB.TalDiffuserClasse(ci)
    if not ADB.EstMJ() or not ADB.CLASSES[ci] then return end
    local a = ADB.db.talents.arbres[ADB.CLASSES[ci][1]]
    ADB.TalEnfiler(format("TS;%d", ci))
    if a then
        local ids = {}
        for id in pairs(a.noeuds) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            for _, m in ipairs(MessagesNoeud(ci, a.noeuds[id])) do ADB.TalEnfiler(m) end
        end
        local bid = {}
        for id in pairs(a.colorBoxes or {}) do bid[#bid + 1] = id end
        table.sort(bid)
        for _, id in ipairs(bid) do ADB.TalEnfiler(ADB.ColorBoxMessage(ci, a.colorBoxes[id])) end
    end
    ADB.TalEnfiler(format("TE;%d", ci))
end

function ADB.TalPlanifierClasse(ci)
    if ADB.talPlan[ci] then return end
    ADB.talPlan[ci] = true
    C_Timer.After(1, function()
        ADB.talPlan[ci] = nil
        ADB.TalDiffuserClasse(ci)
    end)
end

function ADB.TalPlanifierNoeud(ci, id)
    if not ci or not ADB.EstMJ() then return end
    ADB.talNoeudsPlan[ci .. ":" .. id] = { ci, id }
    if ADB.talNoeudsTimer then return end
    ADB.talNoeudsTimer = true
    C_Timer.After(0.8, function()
        ADB.talNoeudsTimer = false
        if ADB.EstMJ() then
            for _, p in pairs(ADB.talNoeudsPlan) do
                local a = ADB.db.talents.arbres[ADB.CLASSES[p[1]][1]]
                local n = a and a.noeuds[p[2]]
                if n then
                    for _, m in ipairs(MessagesNoeud(p[1], n)) do ADB.TalEnfiler(m) end
                end
            end
        end
        wipe(ADB.talNoeudsPlan)
    end)
end

function ADB.TalPlanifierColorBox(ci, id)
    if not ci or not ADB.EstMJ() then return end
    ADB.talBoxPlan[ci .. ":" .. id] = { ci, id }
    if ADB.talBoxTimer then return end
    ADB.talBoxTimer = true
    C_Timer.After(0.8, function()
        ADB.talBoxTimer = false
        if ADB.EstMJ() then
            for _, p in pairs(ADB.talBoxPlan) do
                local a = ADB.db.talents.arbres[ADB.CLASSES[p[1]][1]]
                local b = a and a.colorBoxes and a.colorBoxes[p[2]]
                if b then ADB.TalEnfiler(ADB.ColorBoxMessage(p[1], b)) end
            end
        end
        wipe(ADB.talBoxPlan)
    end)
end

function ADB.TalDemanderArbre()
    if not ADB.db or not ADB.talDemande then return end
    if not IsInGroup() then
        ADB.talSource = nil
        if next(ADB.talDemande) then wipe(ADB.talDemande) end
        return
    end
    if ADB.EstMJ() then return end
    local mj = ADB.NomMJ()
    if mj ~= ADB.talSource then
        ADB.talSource = mj
        wipe(ADB.talDemande)
    end
    if not mj then return end
    local liste = { ADB.db.classe }
    for _, c in ipairs(ADB.TalClassesSupp()) do liste[#liste + 1] = c end
    for k, classe in ipairs(liste) do
        if not ADB.talDemande[classe] then
            ADB.talDemande[classe] = true
            local ci = ADB.TalIndexClasse(classe)
            C_Timer.After(2 + (k - 1) * 0.5, function()
                if ci and IsInGroup() and not ADB.EstMJ() then ADB.Envoyer("TQ;" .. ci) end
            end)
        end
    end
end

function ADB.RecevoirTalent(cmd, nom, message)
    local p = { strsplit(";", message) }

    if cmd == "TQ" then
        if ADB.EstMJ() then
            local ci = tonumber(p[2])
            if ci and ADB.CLASSES[ci] then ADB.TalPlanifierClasse(floor(ci)) end
        end
        return
    elseif cmd == "HQ" then
        if ADB.EstMJ() then
            local jeton = tonumber(p[2])
            if not jeton then return end
            local nt = Net(Decoder(p[4] or ""))
            nt = nt .. (p[6] == "F" and " (recharge / mana)" or " (hors-tour)")
            StaticPopup_Show("ADB_TAL_VALIDATION", ADB.NomAffiche(nom), nt,
                { joueur = nom, jeton = floor(jeton) })
        end
        return
    elseif cmd == "HR" then
        if ADB.EstNomMJ(nom) and p[2] == ADB.playerName then
            local jeton = tonumber(p[3])
            local att = jeton and ADB.talAttente[jeton]
            if att then
                ADB.talAttente[jeton] = nil
                if p[4] == "1" then
                    if att.potion then
                        local s = ADB.db.inv[att.potion]
                        if s and s.kind == att.kind then ADB.UtiliserPotion(att.potion) end
                    end
                    local n = att.id and ADB.TalNoeudPropre(att.id)
                    if n then
                        local enTour = att.force and ADB.phase == "PLAYER_TURN" and not ADB.tourPasse
                        if ADB.TalExecuter(n, att, not enTour) and enTour and not n.bonus then
                            ADB.FinTourJoueur()
                        end
                    end
                else
                    ADB.Print("Le MJ a refusé l'utilisation de la compétence.")
                end
            end
        end
        return
    end

    if ADB.EstMJ() or not ADB.EstNomMJ(nom) then return end
    local ci = tonumber(p[2])
    local classe = ci and ADB.CLASSES[floor(ci)] and ADB.CLASSES[floor(ci)][1]
    if not classe or (classe ~= ADB.EQUIP_CLASSE and not ADB.TalAcces(classe)) then return end
    local a = ADB.TalArbre(classe, true)

    if cmd == "TS" then
        for _, n in pairs(a.noeuds) do n.perime = true end
        for _, b in pairs(a.colorBoxes or {}) do b.perime = true end
    elseif cmd == "TE" then
        for id, n in pairs(a.noeuds) do
            if n.perime then a.noeuds[id] = nil end
        end
        for id, b in pairs(a.colorBoxes or {}) do
            if b.perime then a.colorBoxes[id] = nil end
        end
    elseif cmd == "TC" then
        local b = ValiderColorBox({
            id = p[3],
            x1 = p[4],
            y1 = p[5],
            x2 = p[6],
            y2 = p[7],
            r = p[8],
            g = p[9],
            b = p[10],
            a = p[11]
        })
        if b then
            a.colorBoxes = a.colorBoxes or {}
            a.colorBoxes[b.id] = b
            a.cbProchain = max(a.cbProchain or 1, b.id + 1)
        end
    elseif cmd == "TK" then
        if a.colorBoxes then a.colorBoxes[floor(tonumber(p[3]) or 0)] = nil end
    elseif cmd == "TX" then
        a.noeuds[floor(tonumber(p[3]) or 0)] = nil
    elseif cmd == "TN" then
        local req = {}
        for s in (p[14] or ""):gmatch("%d+") do req[#req + 1] = tonumber(s) end
        local n = ValiderNoeud({
            id = p[3],
            x = p[4],
            y = p[5],
            typ = p[6],
            stat = p[7],
            inter = p[8],
            elem = p[9],
            mana = p[10],
            lim = p[11],
            reac = (p[12] == "1"),
            bonus = (p[13] == "1"),
            req = req,
            icon = p[15],
            nom = Decoder(p[16] or ""),
            desc = ""
        })
        if n then
            a.noeuds[n.id] = n
            a.prochain = max(a.prochain, n.id + 1)
        end
    elseif cmd == "TD" then
        local n = a.noeuds[floor(tonumber(p[3]) or 0)]
        local idx, tot = tonumber(p[4]), tonumber(p[5])
        if n and idx and tot and tot >= 1 and tot <= 40 and idx >= 1 and idx <= tot then
            n.dp = n.dp or {}
            n.dp[floor(idx)] = Decoder(p[6] or "")
            local complet = true
            for i = 1, tot do
                if not n.dp[i] then
                    complet = false
                    break
                end
            end
            if complet then
                n.desc = NetDesc(table.concat(n.dp, "", 1, tot))
                n.dp = nil
            end
        end
    elseif cmd == "TF" then
        local n = a.noeuds[floor(tonumber(p[3]) or 0)]
        if n then
            Extras(n, {
                coutPV = p[4],
                portee = p[5],
                precision = p[6],
                zoe = p[7],
                spe = (p[8] == "1"),
                specX = p[9],
                specY = p[10],
                tags = p[11],
                buffId = p[12]
            })
        end
    elseif cmd == "TG" then
        local n = a.noeuds[floor(tonumber(p[3]) or 0)]
        local i, tot = tonumber(p[4]), tonumber(p[5])
        if n and i and tot and tot >= 1 and tot <= 20 and i >= 1 and i <= tot then
            i, tot = floor(i), floor(tot)
            if i == 1 or not n.tgp then n.tgp = {} end
            n.tgp[i] = p[6] or ""
            for k = 1, tot do if not n.tgp[k] then return end end
            n.tags = NetTags(table.concat(n.tgp, "", 1, tot))
            n.tgp = nil
        end
    end
    ADB.TalRafraichir()
end

------------------------------------------------------------------------------
-- 5. UTILISATION D'UN TALENT ACTIF
------------------------------------------------------------------------------
function ADB.TalCibleNom()
    if not UnitExists("target") then return nil end
    local nom = UnitName("target")
    if UnitIsPlayer("target") and (nom == ADB.playerName or ADB.roster[nom]) then
        return ADB.NomAffiche(nom)
    end
    return nom
end

local function Annoncer(txt)
    for _, s in ipairs(Decouper(txt, 240)) do ADB.AnnoncerChat(s) end
end

local function NomsListe(l)
    local t = {}
    for _, e in ipairs(l or {}) do t[#t + 1] = e.nom end
    return table.concat(t, ", ")
end

-- data = { id, cible (nom affiche), cibles (liste d'entrees k/id/nom) }
function ADB.TalExecuter(n, data, horsTour)
    data = data or {}
    local ok, raison, code = ADB.TalEtat(n)
    if not ok and not (data.force and code) then
        ADB.Print(raison)
        return false
    end

    if n.portee > 0 then
        if not UnitExists("target") then
            ADB.Print(format("Cible requise (portée : %dm).", n.portee))
            return false
        end
        local d = ADB.Distance("target")
        if d and d > n.portee then
            local m = format("Cible trop éloignée. Portée : %dm, Distance actuelle : %dm", n.portee, floor(d + 0.5))
            ADB.Print(m)
            UIErrorsFrame:AddMessage(m, 1, 0.3, 0.3)
            return false
        end
    end

    local db = ADB.db
    db.pm = max(0, db.pm - n.mana)
    if n.coutPV > 0 then db.pv = max(0, db.pv - n.coutPV) end
    ADB.TalPoserCD(n)
    local qui = ADB.NomAffiche(ADB.playerName)
    local cibles = data.cibles
    if (not cibles or #cibles == 0) and not data.cible and n.inter >= 2 and n.inter <= 3 then
        cibles = { { k = "P", id = ADB.playerName, nom = qui } }
    end
    local noms = (cibles and #cibles > 0) and NomsListe(cibles) or data.cible
    local msg = format("%s a utilisé %s", qui, ADB.LienTexte(n)) ..
        ((noms and noms ~= "") and (" sur " .. noms) or "") .. "."
    if n.coutPV > 0 then msg = msg .. format(" (coût : %d PV)", n.coutPV) end

    local _, val = ADB.TalTexte(n.desc, true, ADB.TalMult(n), ADB.TalBonusSpe(n))
    local bp, bc, bd, adv = ADB.BufBonus("P:" .. ADB.playerName)
    if val and n.inter == 1 then val = floor(val * bd + 0.5) end
    local effet = val and n.inter <= 3
    local mult, echec, critEchec = 1, false, false

    if n.precision > 0 then
        local r, lib, c, m, e, ce = ADB.Jet(n.precision, bp, bc, adv)
        mult, echec, critEchec = m, e, ce
        msg = msg .. format(" Jet de précision : %d (%s).", r, lib)
        UIErrorsFrame:AddMessage(format("%d - %s", r, lib), c[1], c[2], c[3])
    end

    if echec then
        msg = msg .. " La compétence échoue."
    else
        if effet then
            local v = val * mult
            local txt = ({ " La compétence inflige %d dégâts.", " La compétence a rendu %d points de vie.",
                " La compétence a procuré %d de bouclier." })[n.inter]
            msg = msg .. format(txt, v) .. (mult > 1 and " (effet doublé)" or "")
            if cibles and #cibles > 0 then ADB.EnvoyerEffets(cibles, n.inter, v) end
        end
        if (n.buffId or 0) > 0 then ADB.BufDepuisTalent(n, cibles) end
        local s = ADB.TalSpeActive()
        if s and s.specY ~= "" and ADB.TalATag(n, s.specY) then
            local g = max(1, floor(ADB.TalMult(n) + 0.5))
            local d = ADB.GetStatBlock(ADB.playerName)
            db.pm = min(d.pmMax, db.pm + g)
            msg = msg .. format(" Regain de mana : +%d PM.", g)
        end
    end

    if data.force then
        msg = msg .. " (validé par le MJ)"
    elseif horsTour then
        msg = msg .. " (hors-tour, validé par le MJ)"
    end
    Annoncer(msg)
    ADB.ApresChangementLocal()
    return true
end

function ADB.MJDeclencher(n)
    local ci = ADB.TalIndexClasse(ADB.MJ_CLASSE)
    local cibles
    if UnitExists("target") then
        if n.zoe > 0 then
            cibles = ADB.ZoneCibles(n.zoe / 2)
        else
            local e = ADB.EntreeUnite("target")
            cibles = e and { e } or nil
        end
    end
    local noms = NomsListe(cibles)
    local _, val = ADB.TalTexte(n.desc, true, 1, 0) -- [n] brut, sans mult. de stat du MJ
    local msg = "[MJ] " .. ADB.LienTexte(n, ci) .. (noms ~= "" and (" sur " .. noms) or "") .. "."
    if val and n.inter <= 3 then
        msg = msg .. format(({ " Inflige %d dégâts.", " Rend %d PV.", " Procure %d de bouclier." })[n.inter], val)
        if cibles and #cibles > 0 then ADB.EnvoyerEffets(cibles, n.inter, val) end
    end
    Annoncer(msg)
    if (n.buffId or 0) > 0 and cibles and #cibles > 0 then ADB.BufDepuisTalent(n, cibles) end
    local plain = n.desc:gsub("[%[%]]", "")
    if plain ~= "" then Annoncer(plain) end
end

function ADB.TalApresConfirmation(data)
    local n = data and ADB.TalNoeudPropre(data.id)
    if not n then return end
    if ADB.phase == "PLAYER_TURN" and not ADB.tourPasse then
        if ADB.TalExecuter(n, data, false) and not n.bonus then
            ADB.FinTourJoueur()
        end
    else
        StaticPopup_Show("ADB_TAL_HORSTOUR", n.nom, nil, data)
    end
end

function ADB.TalDemanderMJ(data, force)
    local n = data and ADB.TalNoeudPropre(data.id)
    if not n then return end
    if not IsInGroup() or not ADB.talSource then
        ADB.Print("Aucun MJ disponible pour valider cette action.")
        return
    end
    ADB.talJeton = (ADB.talJeton or 0) + 1
    ADB.talAttente[ADB.talJeton] = data
    ADB.Envoyer(format("HQ;%d;%d;%s;%s;%s", ADB.talJeton, n.id, Encoder(n.nom),
        Encoder(data.cible or ""), force and "F" or ""))
    ADB.Print("Demande envoyée au MJ pour « " .. n.nom .. " ». En attente de validation...")
end

function ADB.TalHorsTour(data)
    if data and data.potion then return ADB.PotionDemanderMJ(data.potion) end
    local n = data and ADB.TalNoeudPropre(data.id)
    if not n then return end
    if n.reac then
        if ADB.TalExecuter(n, data, false) then
            ADB.saut = true
            ADB.Print("Compétence de réaction utilisée en avance : votre prochain tour sera sauté.")
        end
        return
    end
    ADB.TalDemanderMJ(data)
end

StaticPopupDialogs["ADB_TAL_UTILISER"] = {
    text = "Utiliser la compétence %s%s ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) ADB.TalApresConfirmation(data) end,
}
StaticPopupDialogs["ADB_TAL_HORSTOUR"] = {
    text = "Ce n'est pas votre tour (ou vous l'avez déjà passé).\nUtiliser quand même %s ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) ADB.TalHorsTour(data) end,
}
StaticPopupDialogs["ADB_TAL_VALIDATION"] = {
    text = "%s demande à utiliser « %s ».\nValider ?",
    button1 = "Valider",
    button2 = "Refuser",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data)
        if data and ADB.EstMJ() then ADB.Envoyer(format("HR;%s;%d;1", data.joueur, data.jeton)) end
    end,
    OnCancel = function(self, data, reason)
        if data and reason == "clicked" and ADB.EstMJ() then
            ADB.Envoyer(format("HR;%s;%d;0", data.joueur, data.jeton))
        end
    end,
}
StaticPopupDialogs["ADB_TAL_RESET"] = {
    text = "Réinitialiser tous vos talents appris ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function()
        for _, c in ipairs(ADB.TalClassesAcces()) do wipe(Appris(c)) end
        ADB.TalRafraichir()
    end,
}
StaticPopupDialogs["ADB_TAL_FORCE"] = {
    text = "Action interdite. Confirmer et envoyer la demande au MJ ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) if data then ADB.TalDemanderMJ(data, true) end end,
}

------------------------------------------------------------------------------
-- 6. BARRE D'ACTION (visible uniquement en combat, hors MJ)
------------------------------------------------------------------------------
local function SurvolBarre(b)
    local n = ADB.TalNoeudPropre(b.id)
    if not n then return end
    local G = ADB.TalInfobulle(b, n, "barre")
    local ok, raison, code = ADB.TalEtat(n)
    if not ok then
        G:AddLine(" ")
        G:AddLine(raison, 1, 0.2, 0.2, true)
        if code then G:AddLine("Clic : demander l'autorisation du MJ", 1, 0.6, 0.1, true) end
    end
    G:Show()
end

function ADB.TalClicBarre(b)
    local n = ADB.TalNoeudPropre(b.id)
    if not n then return end
    local ok, raison, code = ADB.TalEtat(n)
    if not ok and not code then
        UIErrorsFrame:AddMessage(raison, 1, 0.3, 0.3)
        return
    end
    local data = { id = n.id, cible = ADB.TalCibleNom() }
    if UnitExists("target") then
        if n.zoe > 0 then
            data.cibles = ADB.ZoneCibles(n.zoe / 2)
        else
            local e = ADB.EntreeUnite("target")
            if e then data.cibles = { e } end
        end
    end
    if not ok then
        data.force = true
        StaticPopup_Show("ADB_TAL_FORCE", nil, nil, data)
        return
    end
    local suf = data.cible and (" sur " .. data.cible) or ""
    if n.zoe > 0 then
        local l = NomsListe(data.cibles)
        suf = suf .. format("\nZone %g m - touchés : %s", n.zoe / 2, l ~= "" and l or "aucun")
    end
    StaticPopup_Show("ADB_TAL_UTILISER", n.nom, suf, data)
end

local function CreerBtnBarre(i)
    local b = CreateFrame("Button", nil, ADB.barre)
    b:SetSize(40, 40)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.noir = b:CreateTexture(nil, "OVERLAY")
    b.noir:SetAllPoints()
    b.noir:SetColorTexture(0, 0, 0, 0.55)
    b.cd = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.cd:SetPoint("CENTER")
    b.flag = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.flag:SetPoint("TOPLEFT", 2, -2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", ADB.TalClicBarre)
    b:SetScript("OnEnter", SurvolBarre)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ADB.barre.btns[i] = b
    return b
end

function ADB.TalCreerBarre()
    local b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    b:SetFrameStrata("MEDIUM")
    b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    b:SetSize(60, 60)
    ADB.AppliquerFond(b)
    b.btns = {}
    b:Hide()
    ADB.barre = b
end

function ADB.TalRafraichirBarre()
    local b = ADB.barre
    if not b or not ADB.db or not ADB.db.talents then return end
    if ADB.phase == "IDLE" or ADB.EstMJ() then
        b:Hide()
        return
    end
    local actifs = ADB.TalActifs()
    local nb = #actifs
    if nb == 0 then
        b:Hide()
        return
    end
    local par = 12
    b:SetSize(min(nb, par) * 44 + 12, math.ceil(nb / par) * 44 + 12)
    for i, n in ipairs(actifs) do
        local btn = b.btns[i] or CreerBtnBarre(i)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", b, "TOPLEFT", 8 + ((i - 1) % par) * 44, -8 - floor((i - 1) / par) * 44)
        btn.id = n.id
        btn.tex:SetTexture(IconeTex(n.icon))
        local ok = ADB.TalEtat(n)
        btn.tex:SetDesaturated(not ok)
        btn.noir:SetShown(not ok)
        local cd = ADB.TalCD(n)
        btn.cd:SetText(cd > 0 and (cd .. (TAL.LIMITES[n.lim][3] == "t" and "t" or "r")) or "")
        btn.flag:SetText((n.reac and "R" or "") .. (n.bonus and "B" or ""))
        btn:Show()
    end
    for i = nb + 1, #b.btns do b.btns[i]:Hide() end
    b:Show()
end

------------------------------------------------------------------------------
-- 7. FENETRE D'ARBRE (joueur + editeur MJ)
------------------------------------------------------------------------------
local function SelNode()
    local f = ADB.talFrame
    local a = f and ADB.TalArbre(ADB.talVue)
    return a and f.sel and a.noeuds[f.sel] or nil
end

local function Modif(champ, v)
    local n = SelNode()
    if not n or not ADB.PeutEditerTalents() then return end
    n[champ] = v
    if champ == "typ" then
        if v == 2 then
            n.mana, n.lim, n.reac, n.bonus = 0, 5, false, false
            n.coutPV, n.portee, n.precision, n.zoe = -1, -1, -1, -1
        else
            n.spe, n.specX, n.specY = false, "", ""
        end
    end
    ADB.TalPlanifierNoeud(ADB.TalIndexClasse(ADB.talVue), n.id)
    ADB.TalDessiner()
end

local function Drop(nom, parent, x, y, w, liste, get, set)
    local d = CreateFrame("Frame", nom, parent, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(d, w)
    UIDropDownMenu_Initialize(d, function(self, niveau)
        for i, lbl in ipairs(liste()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = lbl
            info.checked = (get() == i)
            info.func = function()
                UIDropDownMenu_SetText(d, lbl)
                set(i, lbl)
            end
            UIDropDownMenu_AddButton(info, niveau)
        end
    end)
    d.Maj = function() UIDropDownMenu_SetText(d, liste()[get()] or "") end
    return d
end

local function ChampNum(parent, lbl, lx, ex, y, champ, lettres, maxv)
    Etiq(parent, lbl, lx, y - 3)
    local e = Saisie(parent, ex, y, 44, lettres, true)
    e:SetScript("OnTextChanged", function(self, user)
        if user then
            local v = tonumber(self:GetText())
            Modif(champ, v and Borner(floor(v), -1, maxv) or -1)
        end
    end)
    return e
end

local function Requiert(a, id, cible, vus)
    vus = vus or {}
    if vus[id] then return false end
    vus[id] = true
    local n = a.noeuds[id]
    if not n then return false end
    for _, r in ipairs(n.req) do
        if r == cible or Requiert(a, r, cible, vus) then return true end
    end
    return false
end

function ADB.TalBasculerLien(pid)
    local a, n = ADB.TalArbre(ADB.talVue), SelNode()
    if not a or not n or pid == n.id or not a.noeuds[pid] then return end
    for i, r in ipairs(n.req) do
        if r == pid then
            tremove(n.req, i)
            return true
        end
    end
    if #n.req >= TAL.MAX_REQ then
        ADB.Print("Maximum " .. TAL.MAX_REQ .. " prérequis par talent.")
        return
    end
    if Requiert(a, pid, n.id) then
        ADB.Print("Lien impossible : dépendance circulaire.")
        return
    end
    n.req[#n.req + 1] = pid
    return true
end

function ADB.TalSupprimer()
    local n, a = SelNode(), ADB.TalArbre(ADB.talVue)
    if not n or not a then return end
    local ci = ADB.TalIndexClasse(ADB.talVue)
    a.noeuds[n.id] = nil
    for _, m in pairs(a.noeuds) do
        for i = #m.req, 1, -1 do
            if m.req[i] == n.id then
                tremove(m.req, i)
                ADB.TalPlanifierNoeud(ci, m.id)
            end
        end
    end
    if ADB.EstMJ() then ADB.TalEnfiler(format("TX;%d;%d", ci, n.id)) end
    ADB.talFrame.sel = nil
    ADB.TalDessiner()
end

function ADB.TalClicNoeud(b, bouton)
    local f = ADB.talFrame
    local a = ADB.TalArbre(ADB.talVue)
    local n = a and a.noeuds[b.id]
    if not n then return end
    if f.edition then
        if f.mode == "lien" and f.sel and f.sel ~= n.id then
            if ADB.TalBasculerLien(n.id) ~= nil then
                ADB.TalPlanifierNoeud(ADB.TalIndexClasse(ADB.talVue), f.sel)
            end
            f.mode = nil
        else
            f.sel, f.mode = n.id, nil
        end
    elseif ADB.talVue == ADB.MJ_CLASSE then
        if bouton == "LeftButton" and ADB.PeutEditerTalents() then ADB.MJDeclencher(n) end
        return
    elseif ADB.TalAcces(ADB.talVue) then
        local ap = Appris(ADB.talVue)
        if bouton == "LeftButton" then
            if ADB.TalPeutApprendre(n, ADB.talVue) then
                ap[n.id] = true
            elseif not ap[n.id] then
                local s = n.spe and ADB.TalSpeActive()
                if s then
                    UIErrorsFrame:AddMessage("Une seule spécialisation à la fois : oubliez « " .. s.nom .. " » d'abord.",
                        1, 0.3, 0.3)
                else
                    UIErrorsFrame:AddMessage("Talent verrouillé (prérequis ou points manquants).", 1, 0.3, 0.3)
                end
            end
        elseif ap[n.id] then
            for _, m in pairs(a.noeuds) do
                if ap[m.id] then
                    for _, r in ipairs(m.req) do
                        if r == n.id then
                            UIErrorsFrame:AddMessage("D'autres talents appris dépendent de celui-ci.", 1, 0.3, 0.3)
                            return
                        end
                    end
                end
            end
            ap[n.id] = nil
        end
    end
    ADB.TalRafraichir()
end

------------------------------------------------------------------------------
-- ColorBox : creation / edition / suppression (mode editeur)
------------------------------------------------------------------------------
local CB_PAL = { { 60, 110, 200 }, { 200, 80, 80 }, { 80, 170, 90 }, { 190, 150, 50 }, { 150, 80, 190 }, { 60, 170, 170 } }

function ADB.ColorBoxEn(a, x, y)
    local best, aire
    for _, b in pairs(a and a.colorBoxes or {}) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            local s = (b.x2 - b.x1 + 1) * (b.y2 - b.y1 + 1)
            if not best or s < aire or (s == aire and b.id > best.id) then best, aire = b, s end
        end
    end
    return best
end

function ADB.ColorBoxCreer(x1, y1, x2, y2)
    if not ADB.PeutEditerTalents() then return end
    local a = ADB.TalArbre(ADB.talVue, true)
    a.colorBoxes = a.colorBoxes or {}
    local id = max(1, floor(tonumber(a.cbProchain) or 1))
    while a.colorBoxes[id] do id = id + 1 end
    a.cbProchain = id + 1
    local p = CB_PAL[(id - 1) % #CB_PAL + 1]
    a.colorBoxes[id] = ValiderColorBox({
        id = id,
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        r = p[1],
        g = p[2],
        b = p[3],
        a = 30
    })
    ADB.talFrame.selBox = id
    ADB.TalPlanifierColorBox(ADB.TalIndexClasse(ADB.talVue), id)
end

function ADB.ColorBoxModifier(ch, id)
    if not ADB.PeutEditerTalents() then return end
    local f = ADB.talFrame
    local a = ADB.TalArbre(ADB.talVue)
    id = id or f.selBox
    local b = a and a.colorBoxes and a.colorBoxes[id]
    if not b then return end
    local t = { id = b.id, x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2, r = b.r, g = b.g, b = b.b, a = b.a }
    for k, v in pairs(ch) do t[k] = v end
    a.colorBoxes[id] = ValiderColorBox(t)
    ADB.TalPlanifierColorBox(ADB.TalIndexClasse(ADB.talVue), id)
    ADB.TalDessiner()
end

function ADB.ColorBoxSupprimer()
    if not ADB.PeutEditerTalents() then return end
    local f = ADB.talFrame
    local a = ADB.TalArbre(ADB.talVue)
    local id = f.selBox
    if not (a and id and a.colorBoxes and a.colorBoxes[id]) then return end
    a.colorBoxes[id] = nil
    f.selBox = nil
    if ADB.EstMJ() then ADB.TalEnfiler(format("TK;%d;%d", ADB.TalIndexClasse(ADB.talVue), id)) end
    ADB.TalDessiner()
end

function ADB.ColorBoxSelecteur()
    local f = ADB.talFrame
    local a = ADB.TalArbre(ADB.talVue)
    local b = a and a.colorBoxes and a.colorBoxes[f.selBox or 0]
    if not b then return end
    local P = ColorPickerFrame
    P:SetFrameStrata("FULLSCREEN_DIALOG")
    P.hasOpacity = true
    P.opacity = 1 - b.a / 100
    P.previousValues = { b.r / 255, b.g / 255, b.b / 255, 1 - b.a / 100 }
    P.cancelFunc = function(prev)
        ADB.ColorBoxModifier({
            r = floor(prev[1] * 255 + 0.5),
            g = floor(prev[2] * 255 + 0.5),
            b = floor(prev[3] * 255 + 0.5),
            a = floor((1 - prev[4]) * 100 + 0.5)
        })
    end
    P:SetColorRGB(b.r / 255, b.g / 255, b.b / 255)
    P.func = function()
        local r, g, bl = P:GetColorRGB()
        ADB.ColorBoxModifier({ r = floor(r * 255 + 0.5), g = floor(g * 255 + 0.5), b = floor(bl * 255 + 0.5) })
    end
    P.opacityFunc = function()
        ADB.ColorBoxModifier({ a = floor((1 - OpacitySliderFrame:GetValue()) * 100 + 0.5) })
    end
    P:Hide()
    P:Show()
end

function ADB.TalClicCaseZone(c, a)
    local f = ADB.talFrame
    if f.zEtat == "c1" then
        f.zc, f.zEtat = { c.x, c.y }, "c2"
    elseif f.zEtat == "c2" and f.zc then
        local x1, y1 = f.zc[1], f.zc[2]
        local edit = f.zEdit
        f.zEtat, f.zc, f.zEdit = nil, nil, nil
        if edit and a.colorBoxes and a.colorBoxes[edit] then
            ADB.ColorBoxModifier({ x1 = x1, y1 = y1, x2 = c.x, y2 = c.y }, edit)
        else
            ADB.ColorBoxCreer(x1, y1, c.x, c.y)
        end
    else
        local b = ADB.ColorBoxEn(a, c.x, c.y)
        f.selBox = b and b.id or nil
    end
    ADB.TalDessiner()
end

function ADB.TalMajZone()
    local f = ADB.talFrame
    local Z = f.Ed.Z
    local a = ADB.TalArbre(ADB.talVue)
    local b = f.selBox and a and a.colorBoxes and a.colorBoxes[f.selBox]
    if f.selBox and not b then f.selBox = nil end
    Z.Info:SetText(b and format("Zone #%d : cases (%d,%d) à (%d,%d).", b.id, b.x1, b.y1, b.x2, b.y2)
        or "Aucune zone sélectionnée. Cliquez dans une zone existante pour la sélectionner, ou créez-en une.")
    for _, w in ipairs({ Z.BtnRedef, Z.BtnSuppr, Z.Sw, Z.Hex, Z.Alpha, Z.LC, Z.LH, Z.LA }) do w:SetShown(b ~= nil) end
    if b then
        Z.SwTex:SetColorTexture(b.r / 255, b.g / 255, b.b / 255, 1)
        if not Z.Hex:HasFocus() then Z.Hex:SetText(format("%02X%02X%02X", b.r, b.g, b.b)) end
        if not Z.Alpha:HasFocus() then Z.Alpha:SetText(b.a) end
    end
end

function ADB.TalClicCase(c)
    local f = ADB.talFrame
    local a = ADB.TalArbre(ADB.talVue, true)
    local ci = ADB.TalIndexClasse(ADB.talVue)
    if f.zoneMode then return ADB.TalClicCaseZone(c, a) end
    if (f.mode == "deplacer" or IsShiftKeyDown()) and f.sel and a.noeuds[f.sel] then
        local n = a.noeuds[f.sel]
        n.x, n.y = c.x, c.y
        ADB.TalPlanifierNoeud(ci, n.id)
        f.mode = nil
    else
        local id = a.prochain
        a.prochain = id + 1
        a.noeuds[id] = ValiderNoeud({ id = id, x = c.x, y = c.y, nom = "Nouveau talent", typ = 1 })
        f.sel, f.mode = id, nil
        ADB.TalPlanifierNoeud(ci, id)
    end
    ADB.TalDessiner()
end

local function CreerCases(f)
    f.cases = {}
    for y = 1, TAL.ROWS do
        for x = 1, TAL.COLS do
            local c = CreateFrame("Button", nil, f.canvas)
            c:SetSize(TAL.CELL - 8, TAL.CELL - 8)
            c:SetPoint("CENTER", f.canvas, "TOPLEFT", (x - 0.5) * TAL.CELL, -(y - 0.5) * TAL.CELL)
            local t = c:CreateTexture(nil, "BACKGROUND")
            t:SetAllPoints()
            t:SetColorTexture(1, 1, 1, 0.07)
            c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            c.x, c.y = x, y
            c:SetScript("OnClick", ADB.TalClicCase)
            c:Hide()
            f.cases[#f.cases + 1] = c
        end
    end
end

local function CreerBoutonNoeud(f)
    local b = CreateFrame("Button", nil, f.canvas)
    b:SetSize(TAL.ICON, TAL.ICON)
    b.bord = b:CreateTexture(nil, "BACKGROUND")
    b.bord:SetPoint("TOPLEFT", -2, 2)
    b.bord:SetPoint("BOTTOMRIGHT", 2, -2)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.marque = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.marque:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", ADB.TalClicNoeud)
    b:SetScript("OnEnter", ADB.TalSurvol)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.btns[#f.btns + 1] = b
    return b
end

local function ListeClasses()
    local t = {}
    if ADB.PeutEditerTalents() then
        for _, c in ipairs(ADB.CLASSES) do t[#t + 1] = c[1] end
    else
        for _, c in ipairs(ADB.TalClassesAcces()) do t[#t + 1] = c end
    end
    return t
end

local function Num(e, v)
    if not e:HasFocus() then e:SetText(v > 0 and tostring(v) or "") end
end

function ADB.TalMajPanneau()
    local f = ADB.talFrame
    local Ed, C = f.Ed, f.Ed.C
    local ed = f.edition and true or false
    f.BtnEdit:SetShown(ADB.PeutEditerTalents())
    f.BtnEdit:SetText(ed and "Quitter l'éditeur" or "Mode éditeur")
    f.BtnReset:SetShown(not ed)
    f.BtnZone:SetShown(ed)
    f.BtnZone:SetText(f.zoneMode and "Mode talents" or "Zones (ColorBox)")
    local aide = f.mode == "lien" and "|cffffd100Cliquez le talent PRÉREQUIS.|r"
        or f.mode == "deplacer" and "|cffffd100Cliquez une case vide.|r" or ""
    if f.zoneMode then
        aide = f.zEtat == "c1" and "|cffffd100Cliquez le 1er coin.|r"
            or f.zEtat == "c2" and "|cffffd100Cliquez le coin opposé.|r" or ""
    end
    f.Aide:SetText(aide)
    Ed:SetShown(ed)
    if not ed then return end
    if f.zoneMode then
        Ed.Vide:Hide()
        C:Hide()
        Ed.Z:Show()
        ADB.TalMajZone()
        return
    end
    Ed.Z:Hide()
    local n = SelNode()
    Ed.Vide:SetShown(n == nil)
    C:SetShown(n ~= nil)
    if not n then return end
    if not C.Nom:HasFocus() then C.Nom:SetText(n.nom) end
    C.Icone:SetTexture(IconeTex(n.icon))
    C.DTyp.Maj(); C.DStat.Maj(); C.DInter.Maj(); C.DElem.Maj()
    C.Actif:SetShown(n.typ == 1)
    C.Zone:SetShown(n.typ == 1)
    C.Spec:SetShown(n.typ == 2)
    if n.typ == 1 then
        if not C.Mana:HasFocus() then C.Mana:SetText(n.mana) end
        C.DLim.Maj()
        C.Reac:SetChecked(n.reac)
        C.Bonus:SetChecked(n.bonus)
        Num(C.Cout, n.coutPV); Num(C.Port, n.portee); Num(C.Prec, n.precision); Num(C.Zoe, n.zoe)
    else
        C.Spe:SetChecked(n.spe)
        if not C.SpeX:HasFocus() then C.SpeX:SetText(n.specX) end
        if not C.SpeY:HasFocus() then C.SpeY:SetText(n.specY) end
    end
    if not C.Tags:HasFocus() then C.Tags:SetText(table.concat(n.tags, ",")) end
    if not C.Desc:HasFocus() then C.Desc:SetText(n.desc) end
end

function ADB.TalDessiner()
    local f = ADB.talFrame
    if not f or not f:IsShown() or not ADB.db then return end
    if not ADB.PeutEditerTalents() then
        f.edition = false
        if not (ADB.talVue and ADB.TalAcces(ADB.talVue)) then ADB.talVue = ADB.db.classe end
    end
    ADB.talVue = ADB.talVue or ADB.db.classe
    local cl = ADB.talVue
    local propre = ADB.TalAcces(cl)
    local ed = f.edition and true or false
    if not ed then f.zoneMode, f.zEtat, f.zc, f.zEdit = nil, nil, nil, nil end
    local zm = f.zoneMode and true or false
    local a = ADB.TalArbre(cl)
    local noeuds = a and a.noeuds or {}
    local ap = propre and Appris(cl) or {}
    if f.sel and not noeuds[f.sel] then f.sel = nil end

    local liste, occ = {}, {}
    for _, n in pairs(noeuds) do
        liste[#liste + 1] = n
        occ[(n.y - 1) * TAL.COLS + n.x] = true
    end
    table.sort(liste, function(p, q) return p.id < q.id end)

    if ed and not f.cases then CreerCases(f) end
    if f.cases then
        for i, c in ipairs(f.cases) do c:SetShown(ed and (zm or not occ[i])) end
    end

    local cbs = {}
    for _, b in pairs(a and a.colorBoxes or {}) do cbs[#cbs + 1] = b end
    table.sort(cbs, function(p, q) return p.id < q.id end)
    for i, b in ipairs(cbs) do
        local t = f.boxTex[i]
        if not t then
            t = f.canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
            f.boxTex[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", (b.x1 - 1) * TAL.CELL, -(b.y1 - 1) * TAL.CELL)
        t:SetPoint("BOTTOMRIGHT", f.canvas, "TOPLEFT", b.x2 * TAL.CELL, -b.y2 * TAL.CELL)
        t:SetColorTexture(b.r / 255, b.g / 255, b.b / 255, b.a / 100)
        t:Show()
    end
    for i = #cbs + 1, #f.boxTex do f.boxTex[i]:Hide() end
    do
        local bs = f.boxSel
        local sb = a and a.colorBoxes and a.colorBoxes[f.selBox or 0]
        local x1, y1, x2, y2
        if f.zEtat == "c2" and f.zc then
            x1, y1, x2, y2 = f.zc[1], f.zc[2], f.zc[1], f.zc[2]
        elseif sb then
            x1, y1, x2, y2 = sb.x1, sb.y1, sb.x2, sb.y2
        end
        if zm and x1 then
            bs:ClearAllPoints()
            bs:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", (x1 - 1) * TAL.CELL, -(y1 - 1) * TAL.CELL)
            bs:SetPoint("BOTTOMRIGHT", f.canvas, "TOPLEFT", x2 * TAL.CELL, -y2 * TAL.CELL)
            bs:Show()
        else
            bs:Hide()
        end
    end

    wipe(f.par)
    for i, n in ipairs(liste) do
        local b = f.btns[i] or CreerBoutonNoeud(f)
        b.id = n.id
        b:ClearAllPoints()
        b:SetPoint("CENTER", f.canvas, "TOPLEFT", (n.x - 0.5) * TAL.CELL, -(n.y - 0.5) * TAL.CELL)
        b.tex:SetTexture(IconeTex(n.icon))
        local appris = propre and ap[n.id] and true or false
        local ok = (propre and not appris and ADB.TalPeutApprendre(n, cl)) or (cl == ADB.MJ_CLASSE and not ed)
        local r, g, bl = 0.35, 0.35, 0.35
        if ed then
            r, g, bl = 0.8, 0.8, 0.8
        elseif appris then
            r, g, bl = 1, 0.82, 0
        elseif ok then
            r, g, bl = 0.3, 1, 0.3
        end
        if ed and f.sel == n.id then r, g, bl = 0.2, 0.9, 1 end
        b.bord:SetColorTexture(r, g, bl, 1)
        b.tex:SetDesaturated(not (ed or appris or ok))
        b.marque:SetText(n.spe and "S" or (n.typ == 2 and "P" or ""))
        b:EnableMouse(not zm)
        b:Show()
        f.par[n.id] = b
    end
    for i = #liste + 1, #f.btns do f.btns[i]:Hide() end

    local k = 0
    for _, n in ipairs(liste) do
        for _, r in ipairs(n.req) do
            local pb = f.par[r]
            if pb then
                k = k + 1
                local l = f.lines[k]
                if not l then
                    l = f.canvas:CreateLine(nil, "ARTWORK")
                    f.lines[k] = l
                end
                l:SetThickness(3)
                l:SetStartPoint("CENTER", pb)
                l:SetEndPoint("CENTER", f.par[n.id])
                local pa, na = propre and ap[r], propre and ap[n.id]
                if ed then
                    l:SetColorTexture(0.7, 0.7, 0.95, 0.9)
                elseif pa and na then
                    l:SetColorTexture(1, 0.82, 0, 1)
                elseif pa then
                    l:SetColorTexture(0.3, 0.8, 0.3, 1)
                else
                    l:SetColorTexture(0.4, 0.4, 0.4, 1)
                end
                l:Show()
            end
        end
    end
    for i = k + 1, #f.lines do f.lines[i]:Hide() end

    f.Vide:SetText((#liste == 0 and not ed) and "Aucun talent défini pour cette classe." or "")
    if propre then
        local u, t = ADB.TalPointsUtilises(), ADB.TalPointsTotal()
        f.Pts:SetText(format("Points : |cffffd100%d|r / %d  (restants : %d)", u, t, t - u))
    else
        f.Pts:SetText(cl == ADB.MJ_CLASSE and "|cffffd100Compétences MJ : clic = déclencher|r"
            or "|cffaaaaaaLecture seule (autre classe)|r")
    end
    f.DClasse.Maj()
    ADB.TalMajPanneau()
end

local LIM_ORDRE = { 1, 6, 2, 3, 4, 5 }

function ADB.TalCreer()
    local PX = 672
    local f = FenetreBase("ADBTalentFrame", 950, 690, "Arbre de talents")
    ADB.talFrame = f
    f:SetPoint("CENTER", 0, 0)
    f.btns, f.lines, f.par, f.boxTex = {}, {}, {}, {}
    tinsert(UISpecialFrames, "ADBTalentFrame")

    local sf = CreateFrame("ScrollFrame", "ADBTalScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -34)
    sf:SetSize(TAL.COLS * TAL.CELL, 640)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(TAL.COLS * TAL.CELL, TAL.ROWS * TAL.CELL)
    sf:SetScrollChild(c)
    f.canvas = c
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.03, 0.09, 0.9)
    f.Vide = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.Vide:SetPoint("TOP", 0, -20)

    Etiq(f, "Classe", PX, -40)
    f.DClasse = Drop("ADBTalClasseDrop", f, PX + 36, -33, 150, ListeClasses,
        function()
            for i, l in ipairs(ListeClasses()) do
                if l == ADB.talVue then return i end
            end
            return 1
        end,
        function(i, lbl)
            ADB.talVue = lbl
            f.sel, f.mode, f.selBox, f.zEtat, f.zc, f.zEdit = nil, nil, nil, nil, nil, nil
            ADB.TalDessiner()
        end)
    f.Pts = Etiq(f, "", PX, -76, "GameFontNormal")
    f.BtnReset = Bouton(f, "Réinitialiser", PX, -98, 120, function() StaticPopup_Show("ADB_TAL_RESET") end)
    f.BtnEdit = Bouton(f, "Mode éditeur", PX + 126, -98, 120, function()
        f.edition = not f.edition
        f.sel, f.mode = nil, nil
        ADB.TalDessiner()
    end)
    f.Aide = Etiq(f, "", PX, -124, "GameFontNormalSmall")
    f.BtnZone = Bouton(f, "Zones (ColorBox)", PX, -98, 120, function()
        f.zoneMode = not f.zoneMode
        f.sel, f.mode, f.zEtat, f.zc, f.zEdit = nil, nil, nil, nil, nil
        ADB.TalDessiner()
    end)
    f.BtnZone:Hide()

    local Ed = CreateFrame("Frame", nil, f)
    Ed:SetSize(250, 540)
    Ed:SetPoint("TOPLEFT", PX, -146)
    f.Ed = Ed
    Ed.Vide = Etiq(Ed, "Cliquez sur une case vide pour créer un talent, ou sur un talent pour le modifier.", 0, -10,
        "GameFontHighlightSmall")
    Ed.Vide:SetWidth(240)
    Ed.Vide:SetJustifyV("TOP")
    local C = CreateFrame("Frame", nil, Ed)
    C:SetAllPoints()
    Ed.C = C

    local function Prop(champ, def)
        local n = SelNode()
        return n and n[champ] or def
    end

    Etiq(C, "Nom", 0, -4)
    C.Nom = Saisie(C, 70, -1, 170, TAL.NOM_MAX)
    C.Nom:SetScript("OnTextChanged", function(self, user)
        if user then
            local t = Net(self:GetText())
            Modif("nom", t ~= "" and t or "Talent")
        end
    end)

    Etiq(C, "Icône", 0, -36)
    local ib = CreateFrame("Button", nil, C)
    ib:SetSize(32, 32)
    ib:SetPoint("TOPLEFT", 70, -28)
    local ibg = ib:CreateTexture(nil, "BACKGROUND")
    ibg:SetAllPoints()
    ibg:SetColorTexture(0.4, 0.4, 0.4, 1)
    C.Icone = ib:CreateTexture(nil, "ARTWORK")
    C.Icone:SetPoint("TOPLEFT", 2, -2)
    C.Icone:SetPoint("BOTTOMRIGHT", -2, 2)
    C.Icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ib:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ib:SetScript("OnClick", function()
        ADB.OuvrirIcones(function(v)
            v = tostring(v)
            if #v == 0 or #v > 40 or v:find("[^%w_]") then v = "INV_Misc_QuestionMark" end
            Modif("icon", v)
        end)
    end)
    Etiq(C, "(cliquer pour choisir)", 110, -40, "GameFontDisableSmall")

    Etiq(C, "Type", 0, -72)
    C.DTyp = Drop("ADBTalTypDrop", C, 48, -66, 130, function() return TAL.TYPES end,
        function() return Prop("typ", 1) end, function(i) Modif("typ", i) end)
    Etiq(C, "Stat.", 0, -102)
    C.DStat = Drop("ADBTalStatDrop", C, 48, -96, 130, function() return TAL.STATS end,
        function() return Prop("stat", 1) end, function(i) Modif("stat", i) end)
    Etiq(C, "Effet", 0, -132)
    C.DInter = Drop("ADBTalInterDrop", C, 48, -126, 130, function() return TAL.INTERS end,
        function() return Prop("inter", 4) end, function(i) Modif("inter", i) end)
    Etiq(C, "Élément", 0, -162)
    C.DElem = Drop("ADBTalElemDrop", C, 48, -156, 130, function() return TAL.ELEMS end,
        function() return Prop("elem", 1) end, function(i) Modif("elem", i) end)

    -- Actif : mana / limite / reaction / bonus
    local A = CreateFrame("Frame", nil, C)
    A:SetSize(250, 106)
    A:SetPoint("TOPLEFT", 0, -192)
    C.Actif = A
    Etiq(A, "Coût mana", 0, -4)
    C.Mana = Saisie(A, 80, -1, 50, 3, true)
    C.Mana:SetScript("OnTextChanged", function(self, user)
        if user then Modif("mana", Borner(floor(tonumber(self:GetText()) or 0), 0, TAL.MANA_MAX)) end
    end)
    Etiq(A, "Limite", 0, -34)
    C.DLim = Drop("ADBTalLimDrop", A, 48, -28, 130,
        function()
            local t = {}
            for i, k in ipairs(LIM_ORDRE) do t[i] = TAL.LIMITES[k][1] end
            return t
        end,
        function()
            local l = Prop("lim", 5)
            for i, k in ipairs(LIM_ORDRE) do if k == l then return i end end
            return 6
        end,
        function(i) Modif("lim", LIM_ORDRE[i]) end)
    C.Reac = CreateFrame("CheckButton", "ADBTalReacCheck", A, "UICheckButtonTemplate")
    C.Reac:SetPoint("TOPLEFT", -4, -56)
    _G["ADBTalReacCheckText"]:SetText("Réaction")
    C.Reac:SetScript("OnClick", function(self) Modif("reac", self:GetChecked() and true or false) end)
    C.Bonus = CreateFrame("CheckButton", "ADBTalBonusCheck", A, "UICheckButtonTemplate")
    C.Bonus:SetPoint("TOPLEFT", -4, -82)
    _G["ADBTalBonusCheckText"]:SetText("Action Bonus")
    C.Bonus:SetScript("OnClick", function(self) Modif("bonus", self:GetChecked() and true or false) end)

    -- Actif : cout PV / portee / precision / ZoE
    local X = CreateFrame("Frame", nil, C)
    X:SetSize(250, 56)
    X:SetPoint("TOPLEFT", 0, -302)
    C.Zone = X
    C.Cout = ChampNum(X, "Coût PV", 0, 58, -1, "coutPV", 3, TAL.COUT_MAX)
    C.Port = ChampNum(X, "Portée", 112, 158, -1, "portee", 3, TAL.POR_MAX)
    C.Prec = ChampNum(X, "Précision", 0, 58, -27, "precision", 3, 100)
    C.Zoe = ChampNum(X, "ZoE (m)", 112, 158, -27, "zoe", 3, TAL.ZOE_MAX)

    -- Passif : specialisation
    local S = CreateFrame("Frame", nil, C)
    S:SetSize(250, 110)
    S:SetPoint("TOPLEFT", 0, -192)
    C.Spec = S
    C.Spe = CreateFrame("CheckButton", "ADBTalSpeCheck", S, "UICheckButtonTemplate")
    C.Spe:SetPoint("TOPLEFT", -4, -2)
    _G["ADBTalSpeCheckText"]:SetText("Spécialisation")
    C.Spe:SetScript("OnClick", function(self) Modif("spe", self:GetChecked() and true or false) end)
    Etiq(S, "Tag X", 0, -36)
    C.SpeX = Saisie(S, 50, -33, 190, 16)
    C.SpeX:SetScript("OnTextChanged", function(self, user)
        if user then Modif("specX", NetTag(self:GetText())) end
    end)
    Etiq(S, "Tag Y", 0, -62)
    C.SpeY = Saisie(S, 50, -59, 190, 16)
    C.SpeY:SetScript("OnTextChanged", function(self, user)
        if user then Modif("specY", NetTag(self:GetText())) end
    end)
    Etiq(S, "X : +1 efficacité   Y : regain de mana", 0, -88, "GameFontDisableSmall")

    -- Tags (invisibles pour les joueurs en jeu)
    Etiq(C, "Tags", 0, -364)
    C.Tags = Saisie(C, 40, -361, 205, 600)
    C.Tags:SetScript("OnTextChanged", function(self, user)
        if user then Modif("tags", NetTags(self:GetText())) end
    end)

    Etiq(C, "Description  ([2] = valeur dynamique)", 0, -388, "GameFontNormalSmall")
    local cadre = CreateFrame("Frame", nil, C, "BackdropTemplate")
    cadre:SetSize(250, 76)
    cadre:SetPoint("TOPLEFT", 0, -404)
    cadre:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    cadre:SetBackdropColor(0, 0, 0, 0.6)
    local eb = CreateFrame("EditBox", nil, cadre)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetPoint("TOPLEFT", 6, -6)
    eb:SetSize(238, 64)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(TAL.DESC_MAX)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self, user)
        if user then Modif("desc", NetDesc(self:GetText())) end
    end)
    C.Desc = eb

    Bouton(C, "Prérequis", 0, -490, 80, function()
        f.mode = (f.mode == "lien") and nil or "lien"
        ADB.TalDessiner()
    end)
    Bouton(C, "Déplacer", 84, -490, 80, function()
        f.mode = (f.mode == "deplacer") and nil or "deplacer"
        ADB.TalDessiner()
    end)
    Bouton(C, "Supprimer", 168, -490, 80, ADB.TalSupprimer)

    -- Panneau ColorBox (mode zones)
    f.boxSel = CreateFrame("Frame", nil, f.canvas, "BackdropTemplate")
    f.boxSel:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f.boxSel:SetBackdropBorderColor(1, 1, 1, 1)
    f.boxSel:EnableMouse(false)
    f.boxSel:SetFrameLevel(f.canvas:GetFrameLevel() + 5)
    f.boxSel:Hide()

    local Z = CreateFrame("Frame", nil, Ed)
    Z:SetAllPoints()
    Z:Hide()
    Ed.Z = Z
    Etiq(Z, "Zones de couleur (ColorBox)", 0, -4, "GameFontNormal")
    Z.Info = Etiq(Z, "", 0, -26, "GameFontHighlightSmall")
    Z.Info:SetWidth(244)
    Z.Info:SetJustifyV("TOP")
    Bouton(Z, "Nouvelle zone", 0, -78, 120, function()
        f.zEtat, f.zc, f.zEdit, f.selBox = "c1", nil, nil, nil
        ADB.TalDessiner()
    end)
    Z.BtnRedef = Bouton(Z, "Redéfinir", 124, -78, 120, function()
        if f.selBox then
            f.zEtat, f.zc, f.zEdit = "c1", nil, f.selBox
            ADB.TalDessiner()
        end
    end)
    Z.BtnSuppr = Bouton(Z, "Supprimer", 0, -104, 120, function() ADB.ColorBoxSupprimer() end)
    Z.LC = Etiq(Z, "Couleur", 0, -144)
    Z.Sw = CreateFrame("Button", nil, Z)
    Z.Sw:SetSize(26, 26)
    Z.Sw:SetPoint("TOPLEFT", 70, -138)
    local swb = Z.Sw:CreateTexture(nil, "BACKGROUND")
    swb:SetAllPoints()
    swb:SetColorTexture(1, 1, 1, 1)
    Z.SwTex = Z.Sw:CreateTexture(nil, "ARTWORK")
    Z.SwTex:SetPoint("TOPLEFT", 2, -2)
    Z.SwTex:SetPoint("BOTTOMRIGHT", -2, 2)
    Z.Sw:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    Z.Sw:SetScript("OnClick", function() ADB.ColorBoxSelecteur() end)
    Z.LH = Etiq(Z, "Hex", 0, -178)
    Z.Hex = Saisie(Z, 70, -175, 80, 6)
    Z.Hex:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local h = self:GetText():match("^%x%x%x%x%x%x$")
        if h then
            ADB.ColorBoxModifier({
                r = tonumber(h:sub(1, 2), 16),
                g = tonumber(h:sub(3, 4), 16),
                b = tonumber(h:sub(5, 6), 16)
            })
        end
    end)
    Z.LA = Etiq(Z, "Opacité %", 0, -204)
    Z.Alpha = Saisie(Z, 70, -201, 50, 3, true)
    Z.Alpha:SetScript("OnTextChanged", function(self, user)
        if user and tonumber(self:GetText()) then ADB.ColorBoxModifier({ a = tonumber(self:GetText()) }) end
    end)

    f:SetScript("OnShow", function() ADB.TalDessiner() end)
end

function ADB.BasculerTalents()
    if not ADB.talFrame then ADB.TalCreer() end
    local f = ADB.talFrame
    if f:IsShown() then f:Hide() else f:Show() end
end

------------------------------------------------------------------------------
-- 8. INITIALISATION / RAFRAICHISSEMENT GLOBAL
------------------------------------------------------------------------------
function ADB.TalRafraichir()
    if not ADB.db or not ADB.playerName or not ADB.talAttente then return end
    ADB.TalNettoyerPoints()
    ADB.TalDemanderArbre()
    ADB.TalRafraichirBarre()
    if ADB.talFrame and ADB.talFrame:IsShown() then ADB.TalDessiner() end
end

function ADB.InitTalents()
    ADB.talAttente, ADB.talDemande, ADB.talFile = {}, {}, {}
    ADB.talPlan, ADB.talNoeudsPlan, ADB.talBoxPlan = {}, {}, {}
    ADB.TalCreerBarre()
end

hooksecurefunc(ADB, "RafraichirInv", function()
    if ADB.db and ADB.talAttente then ADB.TalRafraichir() end
end)
