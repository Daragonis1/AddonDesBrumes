-- Effets.lua
------------------------------------------------------------------------------
-- Moteur d'effets spécifiques (micro-script). Les scripts sont liés au NOM du talent.
--
-- METHODE : dans l'éditeur, mettre le talent en Effet = "Autre" si le script gère
-- lui-même dégâts/soins/bouclier ; sinon l'effet par défaut ([n] + Effet) reste appliqué
-- et le script s'ajoute (ex: Tir du cobra).
--
-- SYNTAXE (une règle par ligne, commandes séparées par ;) :
--   DECLENCHEUR [condition] : commande args ; commande args
--   Déclencheurs : use (toujours) | hit (réussite / pas de jet) | miss (échec) | passive (talent appris)
--   Conditions   : [pet] cible = familier (ou pas de cible)   [!pet]  [self]  [!self]
--   Cibles (WHO) : self | pet | target | zonepet:R | zonetarget:R   (R en mètres)
--   Valeurs      : 7 (mises à l'échelle stat/spé/crit)  |  base ([n] de la description)  |  =7 (brut)
--   Commandes    : damage WHO V | heal WHO V | shield WHO V | mana V | move M
--                  cd "Talent" N | recharge "Talent" | buff WHO ID | say "texte"
--   Passifs      : bonus "Talent"|#tag V | manatopv | dotheal V "Nom"... | luna SEUIL%
-- Ajouter un effet = ajouter une ligne ADB.FxDef("Nom du talent", [[ ... ]]).
-- Ajouter une commande = ajouter CMD.nom = function(ctx, a) ... end.
------------------------------------------------------------------------------
local ADB = ADB
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local Borner = ADB.Borner

ADB.FX = {}
local cache = {}

local function Norm(s) return (tostring(s or ""):lower():gsub("[%s'’%-]+", "")) end

-- Extrait le premier [n] d'une description (gsub parenthésé : une seule valeur retournée)
local function BaseDesc(desc)
    local s = (tostring(desc or ""):match("%[([%d%.,]+)%]") or "0")
    s = (s:gsub(",", "."))
    return tonumber(s) or 0
end

function ADB.FxDef(nom, txt)
    ADB.FX[Norm(nom)] = txt
    cache[Norm(nom)] = nil
end

------------------------------------------------------------------------------
-- BIBLIOTHEQUE DE SCRIPTS
------------------------------------------------------------------------------
ADB.FXTAG = {}
local tcache = {}
function ADB.FxTag(tag, txt) ADB.FXTAG[Norm(tag)] = txt tcache[Norm(tag)] = nil end
ADB.FxTag("ReducCDKillOrder", [[
hit: cd "#KillOrder" 1
]])
ADB.FxTag("ReducCDTraqueffroi", [[
hit: cd "#Traqueffroi" 1
]])
ADB.FxDef("Guérison du familier", [[
hit [pet]: heal pet 7
hit [!pet]: heal target 4
]])
ADB.FxDef("Aspect de la tortue", [[
hit [pet]: shield self 6; shield pet 6
hit [!pet]: shield self 3; shield target 3
]])
ADB.FxDef("Rossée", [[
hit: damage zonepet:10 3
]])
ADB.FxDef("Ordre de tuer", [[
use: recharge "Rossée"
]])
ADB.FxDef("Ruée ardente", [[
use: move 10
]])
ADB.FxDef("Enchaînement bestial", [[
passive: bonus "Rossée sauvage" 5
]])
ADB.FxDef("Démoniste", [[
passive: manatopv
]])
ADB.FxDef("Luna gardienne", [[
passive: luna 50
]])

------------------------------------------------------------------------------
-- PARSEUR
------------------------------------------------------------------------------
local function Tokens(s)
    local t, i = {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == '"' then
            local j = s:find('"', i + 1, true) or (#s + 1)
            t[#t + 1] = s:sub(i + 1, j - 1)
            i = j + 1
        else
            local j = s:find("%s", i) or (#s + 1)
            t[#t + 1] = s:sub(i, j - 1)
            i = j
        end
    end
    return t
end

local function Parse(txt)
    local out = {}
    for ligne in (txt .. "\n"):gmatch("(.-)\n") do
        ligne = strtrim(ligne)
        if ligne ~= "" and ligne:sub(1, 2) ~= "--" then
            local trig, rest = ligne:match("^(%a+)%s*(.*)$")
            local cond
            if rest and rest:sub(1, 1) == "[" then
                local c, r = rest:match("^%[(.-)%]%s*(.*)$")
                cond, rest = c, r
            end
            rest = rest and rest:match("^:%s*(.*)$")
            if trig and rest then
                local cmds = {}
                for part in (rest .. ";"):gmatch("(.-);") do
                    local t = Tokens(part)
                    if #t > 0 then
                        t[1] = t[1]:lower()
                        cmds[#cmds + 1] = t
                    end
                end
                out[#out + 1] = { trig = trig:lower(), cond = cond, cmds = cmds }
            end
        end
    end
    return out
end

local function Script(n)
    local k = Norm(n.nom)
    if cache[k] == nil then cache[k] = ADB.FX[k] and Parse(ADB.FX[k]) or false end
    local res = {}
    for _, l in ipairs(cache[k] or {}) do res[#res + 1] = l end
    for _, t in ipairs(n.tags or {}) do
        local x = ADB.FXTAG[t]
        if x then
            tcache[t] = tcache[t] or Parse(x)
            for _, l in ipairs(tcache[t]) do res[#res + 1] = l end
        end
    end
    return #res > 0 and res or nil
end

------------------------------------------------------------------------------
-- OUTILS TALENTS
------------------------------------------------------------------------------
local function Appris()
    if not ADB.db or not ADB.db.talents then return {} end
    return ADB.TalNoeudsAppris()
end

local function TalParNom(nom)
    local k = Norm(nom)
    for _, n in ipairs(Appris()) do
        if Norm(n.nom) == k then return n end
    end
end

-- Liste des commandes passives actives (talents appris) pour une commande donnée
function ADB.FxPassifs(cmd)
    local out = {}
    for _, n in ipairs(Appris()) do
        local sc = Script(n)
        if sc then
            for _, l in ipairs(sc) do
                if l.trig == "passive" then
                    for _, c in ipairs(l.cmds) do
                        if c[1] == cmd then out[#out + 1] = c end
                    end
                end
            end
        end
    end
    return out
end

local function Selecteur(s, n)
    if s:sub(1, 1) == "#" then return ADB.TalATag(n, s:sub(2):lower()) end
    return Norm(s) == Norm(n.nom)
end

------------------------------------------------------------------------------
-- ZONE AUTOUR D'UNE UNITE
------------------------------------------------------------------------------
function ADB.ZoneAutour(centre, rayon)
    local res, vus = {}, {}
    local function Ajout(u)
        if not UnitExists(u) or UnitIsDeadOrGhost(u) then return end
        local g = UnitGUID(u)
        if not g or vus[g] then return end
        local e = ADB.EntreeUnite(u)
        if not e then return end
        if not UnitIsUnit(u, centre) then
            local d = ADB.DistEntre(centre, u)
            if not d or d > rayon then return end
        end
        vus[g] = true
        res[#res + 1] = e
    end
    Ajout(centre)
    Ajout("target")
    Ajout("player")
    for _, u in ipairs(ADB.ListerUnites()) do Ajout(u) end
    for i = 1, 40 do Ajout("nameplate" .. i) end
    return res
end

local function UniteFamilier(p)
    if not p then return nil end
    local function ok(u) return UnitExists(u) and UnitName(u) == p.nom end
    for _, u in ipairs({ "pet", "target", "focus", "mouseover" }) do
        if ok(u) then return u end
    end
    for i = 1, 40 do
        if ok("nameplate" .. i) then return "nameplate" .. i end
    end
    for _, u in ipairs(ADB.ListerUnites()) do
        if ok(u .. "target") then return u .. "target" end
    end
end

------------------------------------------------------------------------------
-- EXECUTION
------------------------------------------------------------------------------
local function Soi()
    return { k = "P", id = ADB.playerName, nom = ADB.NomAffiche(ADB.playerName) }
end

local function Entrees(who, ctx)
    local pet = ADB.GetPet()
    if who == "self" then return { Soi() } end
    if who == "pet" then
        return pet and { { k = "N", id = tostring(pet.id), nom = pet.nom } } or {}
    end
    if who == "target" then return ctx.data.cibles or {} end
    local zone, r = who:match("^(zone%a+):(%d+)$")
    if zone then
        local centre = (zone == "zonepet") and UniteFamilier(pet) or "target"
        if not centre then
            ADB.Print("Familier introuvable (non visible) : zone centrée sur la cible.")
            centre = "target"
        end
        if not UnitExists(centre) then return {} end
        local res = {}
        for _, e in ipairs(ADB.ZoneAutour(centre, tonumber(r))) do
            if not ((e.k == "P" and e.id == ADB.playerName) or (e.k == "N" and pet and e.nom == pet.nom)) then
                res[#res + 1] = e
            end
        end
        return res
    end
    return {}
end

local function CiblePet(ctx)
    local c, pet = ctx.data.cibles, ADB.GetPet()
    if not c or #c == 0 then return true end
    return (pet and c[1].k == "N" and c[1].nom == pet.nom) and true or false
end

local function CibleSoi(ctx)
    local c = ctx.data.cibles
    if not c or #c == 0 then return true end
    return c[1].k == "P" and c[1].id == ADB.playerName
end

local function Cond(cond, ctx)
    for atom in cond:gmatch("[^,]+") do
        atom = strtrim(atom)
        local neg = atom:sub(1, 1) == "!"
        if neg then atom = atom:sub(2) end
        local r = false
        if atom == "pet" then r = CiblePet(ctx)
        elseif atom == "self" then r = CibleSoi(ctx) end
        if (r and true or false) == neg then return false end
    end
    return true
end

local function Val(ctx, tok, kind)
    local n = ctx.n
    tok = tok or "base"
    local brut = tok:sub(1, 1) == "="
    local v = (tok == "base") and ctx.base or tonumber(brut and tok:sub(2) or tok) or 0
    if not brut then
        v = floor((v + ADB.TalBonusSpe(n)) * ADB.TalMult(n) + 0.5)
        if kind == "damage" then v = floor(v * ctx.bd + 0.5) end
    end
    return max(0, v) * ctx.mult
end

local LABEL = { "dégâts", "PV rendus", "de bouclier" }

local function Appliquer(ctx, who, inter, v)
    local liste = Entrees(who or "target", ctx)
    if #liste == 0 or v <= 0 then return end
    local noms = {}
    for _, e in ipairs(liste) do
        local dbl = ADB.FxLuna(e, inter)
        ADB.EnvoyerEffets({ e }, inter, v)
        noms[#noms + 1] = e.nom .. (dbl and " (x2)" or "")
    end
    ctx.msgs[#ctx.msgs + 1] = format("%s : %d %s.", table.concat(noms, ", "), v, LABEL[inter])
end

local CMD = {}
ADB.FxCMD = CMD

CMD.damage = function(ctx, a) Appliquer(ctx, a[2], 1, Val(ctx, a[3], "damage")) end
CMD.heal = function(ctx, a) Appliquer(ctx, a[2], 2, Val(ctx, a[3], "heal")) end
CMD.shield = function(ctx, a) Appliquer(ctx, a[2], 3, Val(ctx, a[3], "shield")) end

CMD.cd = function(ctx, a)
    if not (a[2] and ADB.db) then return end
    local cd, red = ADB.db.talents.cd, tonumber(a[3]) or 1
    for _, n in ipairs(Appris()) do
        local cle = ADB.db.classe .. ":" .. n.id
        local v = cd[cle]
        if v and Selecteur(a[2], n) then
            local r = v - red
            cd[cle] = r > 0 and r or nil
            ctx.msgs[#ctx.msgs + 1] = format("Le rechargement de %s est réduit de %d.", n.nom, red)
        end
    end
end

CMD.recharge = function(ctx, a)
    local n = a[2] and TalParNom(a[2])
    if not n then return end
    local cd, cle = ADB.db.talents.cd, ADB.db.classe .. ":" .. n.id
    if cd[cle] then
        cd[cle] = nil
        ctx.msgs[#ctx.msgs + 1] = format("%s est de nouveau disponible.", n.nom)
    end
end

CMD.move = function(ctx, a)
    local m = tonumber(a[2]) or 0
    if ADB.AjouterMouvement and ADB.AjouterMouvement(m) then
        ctx.msgs[#ctx.msgs + 1] = format("%s peut se déplacer de %d m supplémentaires ce tour.", ctx.qui, m)
    else
        ADB.Print("Déplacement bonus : utilisable uniquement pendant votre tour.")
    end
end

CMD.mana = function(ctx, a)
    local d = ADB.GetStatBlock(ADB.playerName)
    local g = tonumber(a[2]) or 0
    ADB.db.pm = min(d.pmMax, ADB.db.pm + g)
    ctx.msgs[#ctx.msgs + 1] = format("Regain de mana : +%d PM.", g)
end

CMD.buff = function(ctx, a)
    local id = tonumber(a[3])
    if not id then return end
    for _, e in ipairs(Entrees(a[2] or "target", ctx)) do
        ADB.BufDemander(id, ADB.TalBonusSpe(ctx.n), ADB.TalMult(ctx.n), ADB.CleDepuisEntree(e))
    end
end

CMD.say = function(ctx, a) ctx.msgs[#ctx.msgs + 1] = a[2] or "" end

local function Run(sc, ctx)
    local hit = not (ctx.jet and ctx.jet.echec)
    for _, l in ipairs(sc) do
        local t = l.trig
        if (t == "use" or (t == "hit" and hit) or (t == "miss" and not hit))
            and (not l.cond or Cond(l.cond, ctx)) then
            for _, c in ipairs(l.cmds) do
                local f = CMD[c[1]]
                if f then f(ctx, c) else ADB.Print("Effet inconnu : " .. c[1]) end
            end
        end
    end
    for _, m in ipairs(ctx.msgs) do ADB.AnnoncerChat(m) end
    ADB.TalRafraichirBarre()
end

------------------------------------------------------------------------------
-- BRANCHEMENTS SUR LE MOTEUR EXISTANT
------------------------------------------------------------------------------
local ctxJet
local oJet = ADB.Jet
ADB.Jet = function(...)
    local r, lib, c, m, e, ce = oJet(...)
    if ctxJet then ctxJet.jet = { mult = m, echec = e } end
    return r, lib, c, m, e, ce
end

local oExec = ADB.TalExecuter
ADB.TalExecuter = function(n, data, horsTour)
    data = data or {}
    local deficit = 0
    if n.mana > 0 and #ADB.FxPassifs("manatopv") > 0 then
        deficit = max(0, n.mana - ADB.db.pm)
    end
    local ctx = {
        n = n, data = data, msgs = {}, mult = 1,
        qui = ADB.NomAffiche(ADB.playerName),
        base = BaseDesc(n.desc),
    }
    ctxJet = ctx
    local ok = oExec(n, data, horsTour)
    ctxJet = nil
    if not ok then return false end
    local _, _, bd = ADB.BufBonus("P:" .. ADB.playerName)
    ctx.bd = bd
    ctx.mult = ctx.jet and ctx.jet.mult or 1
    if deficit > 0 then
        ADB.db.pv = max(0, ADB.db.pv - deficit)
        ADB.AnnoncerChat(format("%s manque de mana : %d PV dépensés à la place.", ctx.qui, deficit))
        ADB.ApresChangementLocal()
    end
    local sc = Script(n)
    if sc then
        Run(sc, ctx)
        ADB.ApresChangementLocal()
    end
    return true
end

-- Démoniste : le manque de mana ne bloque pas, il est converti en PV
local oEtat = ADB.TalEtat
ADB.TalEtat = function(n)
    if n.mana > 0 and #ADB.FxPassifs("manatopv") > 0 then
        local d = ADB.GetStatBlock(ADB.playerName)
        if d and d.pm < n.mana then
            local besoin = (n.mana - d.pm) + max(0, n.coutPV)
            if d.pv <= besoin then
                return false, format("PV insuffisants pour compenser le mana (%d requis).", besoin)
            end
            return oEtat(setmetatable({ mana = 0 }, { __index = n }))
        end
    end
    return oEtat(n)
end

-- Bonus d'efficacité passif (sélecteur "Nom" ou #tag)
local oBonus = ADB.TalBonusSpe
ADB.TalBonusSpe = function(n)
    local b = oBonus(n)
    for _, c in ipairs(ADB.FxPassifs("bonus")) do
        if c[2] and Selecteur(c[2], n) then b = b + (tonumber(c[3]) or 0) end
    end
    return b
end

-- Luna gardienne : soins/boucliers doublés sur allié sous le seuil de PV (hors soi-même)
function ADB.FxLuna(e, inter)
    if inter ~= 2 and inter ~= 3 then return false end
    local p = ADB.FxPassifs("luna")[1]
    if not p then return false end
    local seuil = tonumber(p[2]) or 50
    local pv, pvMax
    if e.k == "P" then
        if e.id == ADB.playerName then return false end
        local d = ADB.GetStatBlock(e.id)
        pv, pvMax = d and d.pv, d and d.pvMax
    else
        local pn = ADB.TrouverPNJNom(e.nom)
        if not (pn and pn.ally) then return false end
        pv, pvMax = pn.pv, pn.pvMax
    end
    return (pv and pvMax and pv * 100 < pvMax * seuil) and true or false
end

local oEnv = ADB.EnvoyerEffets
ADB.EnvoyerEffets = function(liste, inter, val)
    if inter ~= 2 and inter ~= 3 then return oEnv(liste, inter, val) end
    for _, e in ipairs(liste) do
        oEnv({ e }, inter, ADB.FxLuna(e, inter) and val * 2 or val)
    end
end

-- Immobilisation intégrée (id -2, bonus = nb de tours)
local oBT = ADB.BufTraiter
ADB.BufTraiter = function(id, bonus, mult100, key)
    if id == -2 then
        return ADB.BufPoser(key, { id = -2, left = Borner(bonus, 1, 3), typ = 3, val = 0,
            icon = "Spell_Nature_Earthbind", nom = "Immobilisation" })
    end
    return oBT(id, bonus, mult100, key)
end

local function TagActif(tag)
    for _, n in ipairs(Appris()) do
        if ADB.TalATag(n, tag) then return n end
    end
end

local function Soigner(x)
    if ADB.EstMJ() or x <= 0 then return end
    local d = ADB.GetStatBlock(ADB.playerName)
    if d then ADB.AppliquerValeur(ADB.playerName, "pv", d.pv + x) end
end

local function GagnerMana(g, src)
    local d = ADB.GetStatBlock(ADB.playerName)
    local nv = min(d.pmMax, ADB.db.pm + g)
    if nv > ADB.db.pm then
        ADB.AnnoncerChat(format("%s regagne %d PM (%s).", ADB.NomAffiche(ADB.playerName), nv - ADB.db.pm, src))
        ADB.db.pm = nv
        ADB.ApresChangementLocal()
    end
end

local function FamHit()
    local n = TagActif("famhit")
    if n then return n end
    local s = ADB.TalSpeActive()
    return (s and s.specY == "famhit") and s or nil
end

function ADB.FxFamilierTouche(p)
    if ADB.EstMJ() then return end
    local fh = FamHit()
    if fh then GagnerMana(max(1, floor(ADB.TalMult(fh) + 0.5)), "touche de familier") end
    if p.petType == "Traqueur Corrompu" and TagActif("healonhounddamage") then
        local d = ADB.GetStatBlock(ADB.playerName)
        Soigner(max(1, floor(d.multInt + 0.5)))
    end
end

local function EstAllie(key)
    local k, id = key:sub(1, 1), key:sub(3)
    if k == "P" then return true end
    if k == "N" then
        for _, p in ipairs(ADB.ListerPNJ()) do
            if tostring(p.id) == id then return p.ally end
        end
    end
    return false
end

local derniere = "IDLE"
hooksecurefunc(ADB, "PhaseCombat", function()
    local prev, ph = derniere, ADB.phase
    derniere = ph
    if prev ~= "ENEMY_TURN" or ph == prev or ph == "IDLE" or ADB.EstMJ() then return end
    local n = 0
    for key, l in pairs(ADB.buffs) do
        if not EstAllie(key) then
            for _, b in ipairs(l) do
                if b.typ == 1 and ADB.BufATag(b, "hound") then n = n + 1 end
            end
        end
    end
    if n == 0 then return end
    local d = ADB.GetStatBlock(ADB.playerName)
    local g = max(1, floor(d.multInt + 0.5))
    if TagActif("healonhounddamage") then Soigner(g * n) end
    if FamHit() then GagnerMana(g * n, "Hound") end
end)

local oActs = ADB.TalActifs
ADB.TalActifs = function()
    local r = oActs()
    if ADB.phase == "IDLE" or not TagActif("demonicbolt") then return r end
    local o = {}
    for _, n in ipairs(r) do
        if not ADB.TalATag(n, "shadowbolt") then o[#o + 1] = n end
    end
    return o
end