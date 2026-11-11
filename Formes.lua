-- Formes.lua : tags Blink / Sha0 / Sha1 / Sha2
local ADB = ADB
local floor, max, sqrt = math.floor, math.max, math.sqrt
local format = string.format
local Borner, UI = ADB.Borner, ADB.UI

local BONUS = { [0] = 0.5, [1] = 1, [2] = 2 }   -- bonus dégâts attaque basique

local function EnForme() return (not ADB.ctxAlt and ADB.db) and ADB.db.sha or nil end
local function NivSha(n)
    for lv = 2, 0, -1 do if ADB.TalATag(n, "sha" .. lv) then return lv end end
end
local function MaxNiv()
    local m
    for _, n in ipairs(ADB.TalNoeudsAppris()) do
        local l = NivSha(n)
        if l and (not m or l > m) then m = l end
    end
    return m
end
local function MaxSha(normal, niv)
    if niv == 0 then return max(1, floor(normal / 2)) end
    return niv == 1 and normal or normal * 2
end

-- PV max / PV en forme de Sha
local oGSB = ADB.GetStatBlock
ADB.GetStatBlock = function(nom)
    local d = oGSB(nom)
    local s = d and nom == ADB.playerName and EnForme()
    if s then
        d.pvMax = MaxSha(d.pvMax, s.niv)
        d.pv = Borner(floor(ADB.db.pv or 0), 0, d.pvMax)
    end
    return d
end

-- Barre : forme Sha = attaque basique + sorts d'Ombre ; Sha inférieurs masqués
local oAct = ADB.TalActifs
ADB.TalActifs = function()
    local r, m, f = oAct(), MaxNiv(), EnForme()
    if not m and not f then return r end
    local o = {}
    for _, n in ipairs(r) do
        local l = NivSha(n)
        if not (l and m and l < m) and (not f or n.id == 0 or n.elem == 3) then o[#o + 1] = n end
    end
    return o
end

-- Bonus de dégâts de l'attaque basique
local basic
local oBB = ADB.BufBonus
ADB.BufBonus = function(k)
    local bp, bc, bd, adv = oBB(k)
    local s = basic and EnForme()
    if s and k == "P:" .. ADB.playerName then bd = bd + BONUS[s.niv] end
    return bp, bc, bd, adv
end

local function Transformer(niv, hb)
    local db = ADB.db
    hb = hb or max(1, ADB.GetStatBlock(ADB.playerName).pv)
    db.sha = { niv = niv, HealthBeforeTransform = hb }
    db.pv = ADB.GetStatBlock(ADB.playerName).pvMax
    ADB.Banniere("Vous prenez votre forme de Sha")
    ADB.Print("Vous prenez votre forme de Sha.")
    ADB.AnnoncerChat(format("%s prend sa forme de Sha.", ADB.NomAffiche(ADB.playerName)))
    ADB.ApresChangementLocal()
end

local function Quitter()
    local db = ADB.db
    local s = db.sha
    db.sha = nil
    db.pv = Borner(s.HealthBeforeTransform or 1, 1, ADB.GetStatBlock(ADB.playerName).pvMax)
    ADB.Print("Vous reprenez votre forme normale.")
    ADB.ApresChangementLocal()
end

-- À 0 PV hors forme : active immédiatement le meilleur Sha disponible (PV de retour = 1)
local function Auto()
    local hl, best = MaxNiv(), nil
    if not hl then return end
    for _, n in ipairs(ADB.TalNoeudsAppris()) do
        if n.typ == 1 and NivSha(n) == hl and ADB.TalCD(n) < (ADB.TAL.LIMITES[n.lim][4] or 1) then best = n break end
    end
    if not best then return end
    ADB.TalPoserCD(best)
    Transformer(hl, 1)
end

hooksecurefunc(ADB, "ApresChangementLocal", function()
    if ADB.ctxAlt or not ADB.db or ADB.EstMJ() or (ADB.db.pv or 1) > 0 then return end
    if ADB.db.sha then Quitter() else Auto() end
end)

-- Fin du tour joueur en forme : -1/10 PV max ; fin de combat : retour forme normale
local prev = "IDLE"
hooksecurefunc(ADB, "PhaseCombat", function()
    local p, ph = prev, ADB.phase
    prev = ph
    if p == ph or ADB.ctxAlt or ADB.EstMJ() or not EnForme() then return end
    if ph == "IDLE" then return Quitter() end
    if p == "PLAYER_TURN" then
        local d = ADB.GetStatBlock(ADB.playerName)
        local perte = max(1, floor(d.pvMax / 10))
        ADB.db.pv = max(0, ADB.db.pv - perte)
        ADB.Print(format("Forme de Sha : vous perdez %d PV.", perte))
        ADB.ApresChangementLocal()
    end
end)

------------------------------------------------------------------------------
-- Blink
------------------------------------------------------------------------------
local blink
local function PosJ()
    local y, x = UnitPosition("player")
    if x and not (x == 0 and y == 0) then return x, y end
end

local function OuvrirBlink(n)
    local f = blink
    if not f then
        f = UI.FenetreBase("ADBBlinkFrame", 240, 110, "Déplacement instantané")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetPoint("CENTER", 0, 150)
        tinsert(UISpecialFrames, "ADBBlinkFrame")
        f.T = UI.Etiq(f, "", 20, -40, "GameFontNormalLarge")
        f.B = UI.Bouton(f, "Valider", 20, -75, 100, function()
            if f.d and f.d > 30 then return end
            ADB.AnnoncerChat(format("%s a utilisé %s : déplacement instantané.",
                ADB.NomAffiche(ADB.playerName), ADB.LienTexte(f.n)))
            f:Hide()
        end)
        UI.Bouton(f, "Annuler", 130, -75, 90, function() f:Hide() end)
        f:SetScript("OnUpdate", function(s, el)
            s.acc = (s.acc or 0) + el
            if s.acc < 0.1 then return end
            s.acc = 0
            local x, y = PosJ()
            if x and s.x0 then
                s.d = sqrt((x - s.x0) ^ 2 + (y - s.y0) ^ 2)
                s.T:SetText(format("%.1f / 30 m", s.d))
                s.B:SetEnabled(s.d <= 30)
            else
                s.d = nil
                s.T:SetText("Position indisponible")
                s.B:SetEnabled(true)
            end
        end)
        blink = f
    end
    f.n, f.d = n, 0
    f.x0, f.y0 = PosJ()
    f:Show()
end

------------------------------------------------------------------------------
-- Activation des tags
------------------------------------------------------------------------------
local oExec = ADB.TalExecuter
ADB.TalExecuter = function(n, data, horsTour)
    basic = (n.id == 0)
    local ok = oExec(n, data, horsTour)
    basic = false
    if ok then
        local lv = NivSha(n)
        if lv and not ADB.ctxAlt and not ADB.EstMJ() and not EnForme() then Transformer(lv) end
        if ADB.TalATag(n, "blink") then OuvrirBlink(n) end
    end
    return ok
end

local oLogin = ADB.Evenements.PLAYER_LOGIN
ADB.Evenements.PLAYER_LOGIN = function(...)
    oLogin(...)
    local s = ADB.db.sha
    if type(s) ~= "table" or not BONUS[s.niv] then
        ADB.db.sha = nil
    else
        s.HealthBeforeTransform = Borner(floor(tonumber(s.HealthBeforeTransform) or 1), 1, 99999)
    end
end