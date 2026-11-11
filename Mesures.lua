------------------------------------------------------------------------------
-- Mesures.lua : distances, mouvement, ZoE, effets, degats subis hors-groupe
------------------------------------------------------------------------------
local ADB = ADB
local floor, max, abs, sqrt = math.floor, math.max, math.abs, math.sqrt
local format = string.format

ADB.degats = {}
local mv = nil
local LIMITE_MOUV = 15

-- { portee, itemID } : estimation de distance pour les unites sans coordonnees
local ITEMS = {
    harm = { { 5, 37727 }, { 8, 34368 }, { 10, 32321 }, { 15, 33069 }, { 20, 10645 }, { 25, 24268 },
        { 30, 835 }, { 35, 24269 }, { 40, 28767 }, { 45, 23836 }, { 60, 116139 }, { 80, 35278 } },
    aide = { { 5, 37727 }, { 8, 34368 }, { 10, 32321 }, { 15, 1251 }, { 20, 21519 }, { 25, 31463 },
        { 30, 34191 }, { 35, 18904 }, { 40, 34471 }, { 45, 32698 }, { 60, 32825 }, { 80, 35278 } },
}

local function Pos(u)
    local y, x, _, inst = UnitPosition(u)
    if x and y and not (x == 0 and y == 0) then return x, y, inst end
end

local function Estimer(unit)
    local liste = UnitCanAttack("player", unit) and ITEMS.harm or ITEMS.aide
    local vu
    for _, e in ipairs(liste) do
        local r = IsItemInRange(e[2], unit)
        if r ~= nil then
            vu = true
            if r == true or r == 1 then return e[1] end
        end
    end
    return vu and 100 or nil
end

-- Distance joueur -> unite (exacte pour le groupe, estimee sinon)
function ADB.Distance(unit)
    if not UnitExists(unit) then return nil end
    if UnitIsUnit(unit, "player") then return 0 end
    local ax, ay, ai = Pos("player")
    local bx, by, bi = Pos(unit)
    if ax and bx and ai == bi then return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
    return Estimer(unit), true
end

-- Distance entre deux unites (exacte si coordonnees connues, sinon approximation par anneau)
function ADB.DistEntre(a, b)
    local ax, ay, ai = Pos(a)
    local bx, by, bi = Pos(b)
    if ax and bx and ai == bi then return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
    local da, db = ADB.Distance(a), ADB.Distance(b)
    if da and db then return abs(da - db) end
end

function ADB.EntreeUnite(u)
    if not UnitExists(u) then return nil end
    local nom = UnitName(u)
    if UnitIsPlayer(u) then
        if IsInGroup() and UnitIsGroupLeader(u) then return nil end
        if nom == ADB.playerName or ADB.roster[nom] then
            return { k = "P", id = nom, nom = ADB.NomAffiche(nom) }
        end
        return nil
    end
    return { k = "N", id = UnitGUID(u), nom = nom }
end

function ADB.ZoneCibles(rayon)
    local res, vus = {}, {}
    local function Ajout(u)
        if not UnitExists(u) or UnitIsDeadOrGhost(u) then return end
        local g = UnitGUID(u)
        if not g or vus[g] then return end
        local e = ADB.EntreeUnite(u)
        if not e then return end
        if not UnitIsUnit(u, "target") then
            local d = ADB.DistEntre("target", u)
            if not d or d > rayon then return end
        end
        vus[g] = true
        res[#res + 1] = e
    end
    Ajout("target")
    Ajout("player")
    for _, u in ipairs(ADB.ListerUnites()) do Ajout(u) end
    for i = 1, 40 do Ajout("nameplate" .. i) end
    return res
end

------------------------------------------------------------------------------
-- Degats cumules des ennemis hors-groupe
------------------------------------------------------------------------------
function ADB.AjouterDegats(guid, delta)
    if not guid or delta == 0 or ADB.phase == "IDLE" then return end
    if IsInGroup() and not ADB.EstMJ() then return end
    local t = max(0, (ADB.degats[guid] or 0) + delta)
    ADB.degats[guid] = t > 0 and t or nil
    if ADB.EstMJ() then ADB.Envoyer(format("DG;%s;%d", guid, t)) end
    ADB.RafraichirCible(false)
end

function ADB.TexteEnnemi(barre)
    local x = ADB.degats[UnitGUID("target") or ""]
    barre.Text:SetText((ADB.phase ~= "IDLE" and x and x > 0) and ("-" .. x) or "?")
end

function ADB.OnEnnemiBarClick(barre, bouton)
    if not ADB.EstMJ() then
        UIErrorsFrame:AddMessage("Seul le MJ peut modifier cette valeur.", 1, 0.3, 0.3)
        return
    end
    if barre.kind ~= "pv" then return end
    local g = UnitGUID("target")
    if not g then return end
    if IsShiftKeyDown() then
        StaticPopup_Show("ADB_SAISIE_VALEUR", "dégâts subis de " .. (UnitName("target") or "?"), "9999",
            { guid = g, kind = "deg", courant = ADB.degats[g] or 0 })
    elseif bouton == "RightButton" then
        ADB.AjouterDegats(g, 1)
    elseif bouton == "LeftButton" then
        ADB.AjouterDegats(g, -1)
    end
end

------------------------------------------------------------------------------
-- Effets (appliques par le MJ / en solo) et reception
------------------------------------------------------------------------------
function ADB.AppliquerEffet(inter, val, k, id, nom)
    if k == "P" then
        local d = ADB.GetStatBlock(id)
        if not d or (id == ADB.playerName and ADB.EstMJ()) then return end
        if inter == 1 then
            ADB.AppliquerValeur(id, "pv", d.pv - val)
        elseif inter == 2 then
            ADB.AppliquerValeur(id, "pv", d.pv + val)
        else
            ADB.AppliquerValeur(id, "sh", d.sh + val)
        end
    else
        local p = ADB.TrouverPNJNom(nom)
        if p then
            if not ADB.EstMJ() then return end
            if inter == 1 then
                ADB.AppliquerValeurPNJ(p.id, "pv", p.pv - val)
            elseif inter == 2 then
                ADB.AppliquerValeurPNJ(p.id, "pv", p.pv + val)
            else
                ADB.AppliquerValeurPNJ(p.id, "sh", (p.sh or 0) + val)
            end
        else
            ADB.AjouterDegats(id, inter == 1 and val or (inter == 2 and -val or 0))
        end
    end
end

function ADB.EnvoyerEffets(liste, inter, val)
    local auto = ADB.EstMJ() or not IsInGroup()
    for _, e in ipairs(liste) do
        if auto then
            ADB.AppliquerEffet(inter, val, e.k, e.id, e.nom)
        else
            ADB.TalEnfiler(format("EF;%d;%d;%s;%s;%s", inter, val, e.k, e.id, ADB.Encoder(e.nom)))
        end
    end
end

function ADB.RecevoirMesure(cmd, nom, message)
    local p = { strsplit(";", message) }
    if cmd == "DG" then
        if not ADB.EstNomMJ(nom) then return end
        local v = max(0, floor(tonumber(p[3]) or 0))
        ADB.degats[p[2]] = v > 0 and v or nil
        ADB.RafraichirCible(false)
    elseif cmd == "EF" and ADB.EstMJ() then
        local inter, val = tonumber(p[2]), tonumber(p[3])
        if inter and val and inter >= 1 and inter <= 3 and (p[4] == "P" or p[4] == "N") and p[5] then
            ADB.AppliquerEffet(floor(inter), ADB.Borner(floor(val), 1, 999), p[4], p[5],
                ADB.NettoyerNom(ADB.Decoder(p[6] or "")))
        end
    end
end

------------------------------------------------------------------------------
-- Phases, mouvement, distance de la cible
------------------------------------------------------------------------------
function ADB.MesuresPhase(ph)
    if ph == "PLAYER_TURN" then
        mv = { m = 0 }
        mv.x0, mv.y0 = Pos("player")
        LIMITE_MOUV = 15
    elseif ph == "IDLE" then
        mv = nil
        LIMITE_MOUV = 15
        wipe(ADB.degats)
        if ADB.db and ADB.playerName then ADB.RafraichirCible(false) end
    end
end

local tk, acc = CreateFrame("Frame"), 0
tk:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.2 then return end
    acc = 0
    if not ADB.db or not ADB.playerName then return end

    local t = ADBTargetFrame
    if t and t:IsShown() then
        if not t.Dist then
            t.Dist = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t.Dist:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 6, -3)
        end
        local d, est
        if UnitExists("target") then d, est = ADB.Distance("target") end
        t.Dist:SetText(d and format(est and "Distance : ~%d m" or "Distance : %d m", floor(d + 0.5)) or "")
    end

    if mv and ADB.phase == "PLAYER_TURN" and not ADB.EstMJ() then
        if not ADB.tourPasse then
            local x, y = Pos("player")
            if x then
                if not mv.x0 then mv.x0, mv.y0 = x, y end
                mv.m = sqrt((x - mv.x0) ^ 2 + (y - mv.y0) ^ 2)
            end
            if mv.m >= LIMITE_MOUV and not mv.info then
                mv.info = true
                local msg = format("Vous avez atteint votre limite de %dm ce tour.", LIMITE_MOUV)
                ADB.Print(msg)
                UIErrorsFrame:AddMessage(msg, 1, 0.8, 0.2)
            end
            if mv.m >= LIMITE_MOUV + 1 and not mv.raid then
                mv.raid = true
                ADB.AnnoncerChat(format("%s a dépassé les %dm de déplacement ce tour.",
                    ADB.NomAffiche(ADB.playerName), LIMITE_MOUV))
            end
        end
        local cb = ADB.cbJ
        if cb and cb:IsShown() then
            if not cb.Mouv then
                cb:SetHeight(64)
                cb.Mouv = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cb.Mouv:SetPoint("BOTTOM", 0, 8)
            end
            cb.Mouv:SetText(format("%sDéplacement : %.1f / %d m|r",
                mv.m >= LIMITE_MOUV and "|cffff5050" or "", mv.m, LIMITE_MOUV))
        end
    end
end)

function ADB.AjouterMouvement(m)
    if not mv then return false end
    LIMITE_MOUV = LIMITE_MOUV + m
    mv.info, mv.raid = nil, nil
    return true
end
