-- Equip.lua : compétences liées à l'équipement (arbre "Équipements", édité par le MJ)
local ADB = ADB
local OFF = 100000                 -- décalage d'ID des compétences d'équipement
ADB.EQ_OFFSET = OFF
local proxies = {}

local function Arbre() return ADB.db and ADB.TalArbre(ADB.EQUIP_CLASSE) end

-- Nœud proxy (id décalé, le reste lu en direct depuis l'arbre MJ)
function ADB.TalNoeudEquip(id)
    local a = Arbre()
    local n = a and a.noeuds[id - OFF]
    if not n then return nil end
    local p = proxies[id]
    if not p or getmetatable(p).__index ~= n then
        p = setmetatable({ id = id }, { __index = n })
        proxies[id] = p
    end
    return p
end

-- Résolution d'un ID (classe ou équipement) : utilisé par TalTickCD / TalResetTours
function ADB.TalNoeudDepuisId(a, id)
    if id and id >= OFF then return ADB.TalNoeudEquip(id) end
    return a and id and a.noeuds[id] or nil
end

-- Compétences actives accordées par l'équipement porté
function ADB.EquipGranted()
    local res, vus = {}, {}
    if not ADB.db or not ADB.db.equip then return res end
    for _, s in ipairs(ADB.SLOTS) do
        local it = ADB.db.equip[s[1]]
        if it and it.sk then
            for _, id in ipairs(it.sk) do
                local n = (not vus[id]) and ADB.TalNoeudEquip(OFF + id)
                if n and n.typ == 1 then
                    vus[id] = true
                    res[#res + 1] = n
                end
            end
        end
    end
    return res
end

-- Barre d'action : ajoute les compétences accordées (après Attaque.lua)
local oAct = ADB.TalActifs
ADB.TalActifs = function()
    local r = oAct()
    for _, n in ipairs(ADB.EquipGranted()) do r[#r + 1] = n end
    return r
end

-- Résolution par ID (barre, validation MJ, liens de chat)
local oProp = ADB.TalNoeudPropre
ADB.TalNoeudPropre = function(id)
    if type(id) == "number" and id >= OFF then return ADB.TalNoeudEquip(id) end
    return oProp(id)
end

-- Joueurs : demander aussi l'arbre "Équipements" au MJ
hooksecurefunc(ADB, "TalDemanderArbre", function()
    if not ADB.db or not ADB.talDemande or not IsInGroup() or ADB.EstMJ() or not ADB.talSource then return end
    local c = ADB.EQUIP_CLASSE
    if ADB.talDemande[c] then return end
    ADB.talDemande[c] = true
    local ci = ADB.TalIndexClasse(c)
    C_Timer.After(2.5, function()
        if ci and IsInGroup() and not ADB.EstMJ() then ADB.Envoyer("TQ;" .. ci) end
    end)
end)

-- Infobulle d'objet : liste des compétences accordées
local oInfo = ADB.SlotInfobulle
ADB.SlotInfobulle = function(b)
    oInfo(b)
    local it = ADB.ObjetEn(b.zone, b.key)
    if it and it.sk and #it.sk > 0 then
        local a = Arbre()
        for _, id in ipairs(it.sk) do
            local n = a and a.noeuds[id]
            GameTooltip:AddLine("Compétence : " .. (n and n.nom or ("#" .. id)), 0.5, 0.8, 1)
        end
        GameTooltip:Show()
    end
end