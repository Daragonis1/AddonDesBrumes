local ADB = ADB
local floor = math.floor
local format = string.format

local BASE_DEG = 4
local base = { id = 0, x = 0, y = 0, typ = 1, inter = 1, elem = 1, mana = 0, lim = 5,
    reac = false, bonus = false, icon = "INV_Sword_04", nom = "Attaque de base",
    desc = "Inflige [" .. BASE_DEG .. "] dégâts.", req = {}, tags = {}, coutPV = -1, zoe = -1,
    precision = 70, spe = false, specX = "", specY = "", buffId = 0, stat = 2, portee = 5 }

function ADB.AttaqueBase()
    local c = ADB.CLASSE_MAP[ADB.db.classe] or ADB.CLASSE_MAP["Guerrier"]
    base.stat = c[1] > 0 and 2 or (c[2] > 0 and 3 or 4)
    base.portee = (ADB.db.classe == "Chasseur") and 30 or 5
    return base
end

local function Un(prec, bp, bc)
    local r = math.random(1, 100)
    if r <= 5 + bc then return r, "Réussite critique", { 0.4, 0.7, 1 }, 2, false, false
    elseif r >= 96 then return r, "Échec critique", { 1, 0.2, 0.2 }, 1, true, true
    elseif r <= prec + bp then return r, "Réussite", { 0.3, 1, 0.3 }, 1, false, false end
    return r, "Échec", { 1, 0.6, 0.1 }, 1, true, false
end

function ADB.Jet(prec, bp, bc, adv)
    bp, bc = bp or 0, bc or 0
    local a = { Un(prec, bp, bc) }
    if not adv or adv == 0 then return unpack(a) end
    local b = { Un(prec, bp, bc) }
    local useB
    if adv > 0 then useB = b[1] < a[1] else useB = b[1] > a[1] end
    local k = useB and b or a
    k[2] = format("%s - %s : %d et %d", k[2], adv > 0 and "Avantage" or "Désavantage", a[1], b[1])
    return unpack(k)
end

local oAct, oProp, oEtat = ADB.TalActifs, ADB.TalNoeudPropre, ADB.TalEtat
ADB.TalActifs = function()
    local r = oAct()
    if ADB.db then table.insert(r, 1, ADB.AttaqueBase()) end
    return r
end
ADB.TalNoeudPropre = function(id)
    if id == 0 then return ADB.AttaqueBase() end
    return oProp(id)
end
ADB.TalEtat = function(n)
    if ADB.BufA("P:" .. ADB.playerName, 4) then
        return false, "Vous êtes étourdi : aucune action possible."
    end
    return oEtat(n)
end