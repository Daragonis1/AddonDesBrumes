local ADB = ADB
local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
local format = string.format
local Borner, Encoder, Decoder, Net = ADB.Borner, ADB.Encoder, ADB.Decoder, ADB.NettoyerNom
local UI = ADB.UI
local IconeTex = ADB.IconeTex

local TYPES = { "Dégâts", "Soins", "Immobilisation", "Étourdissement", "Courroux Bestial" }
ADB.BUF_TYPES = TYPES
local BUF_MAX, PAR_CIBLE = 12, 8
ADB.buffs, ADB.bufTmp = {}, {}

local function Esc(s) return (tostring(s):gsub("[%%;,]", function(c) return format("%%%02X", c:byte()) end)) end
local function Entree(b) return format("%d,%d,%d,%d,%s,%s", b.id, b.left, b.typ, b.val, b.icon, Esc(b.nom)) end
local function Lire(e)
    local id, left, typ, val, icon, nom = strsplit(",", e)
    id, left, typ, val = tonumber(id), tonumber(left), tonumber(typ), tonumber(val)
    if not (id and left and typ and val and typ >= 1 and typ <= 5 and icon) then return nil end
    if #icon == 0 or #icon > 40 or icon:find("[^%w_]") then icon = "INV_Misc_QuestionMark" end
    return { id = floor(id), left = Borner(floor(left), 1, 99), typ = floor(typ),
        val = Borner(floor(val), 0, 999), icon = icon, nom = Net(Decoder(nom or "")):sub(1, 40) }
end

local function PNJ(id)
    for _, p in ipairs(ADB.db.pnjs) do if p.id == id then return p end end
end

------------------------------------------------------------------------------
-- Definitions (MJ)
------------------------------------------------------------------------------
function ADB.BufInitDB()
    local db, defs, maxId = ADB.db, {}, 0
    if type(db.buffDefs) == "table" then
        for _, d in ipairs(db.buffDefs) do
            if type(d) == "table" and tonumber(d.id) and #defs < BUF_MAX then
                local icon = tostring(d.icon or "")
                if #icon == 0 or #icon > 40 or icon:find("[^%w_]") then icon = "INV_Misc_QuestionMark" end
                local id = floor(d.id)
                defs[#defs + 1] = { id = id, nom = Net(d.nom):sub(1, 24), icon = icon,
                    duree = Borner(floor(tonumber(d.duree) or 1), 1, 20),
                    typ = Borner(floor(tonumber(d.typ) or 1), 1, 5),
                    val = Borner(floor(tonumber(d.val) or 0), 0, 999) }
                maxId = max(maxId, id)
            end
        end
    end
    db.buffDefs = defs
    if type(db.buffProchainId) ~= "number" or db.buffProchainId <= maxId then db.buffProchainId = maxId + 1 end
end

function ADB.BufDef(id)
    for _, d in ipairs(ADB.db.buffDefs) do if d.id == id then return d end end
end

function ADB.BufDefNom(nom)
    nom = nom:lower()
    for _, d in ipairs(ADB.db.buffDefs) do if d.nom:lower() == nom then return d end end
end

function ADB.BufCreerDef(nom, icon, duree, typ, val)
    if not ADB.EstMJ() then return false end
    if #ADB.db.buffDefs >= BUF_MAX then ADB.Print("Maximum " .. BUF_MAX .. " buffs/debuffs.") return false end
    nom = Net(nom):sub(1, 24)
    if nom == "" then ADB.Print("Donnez un nom.") return false end
    local id = ADB.db.buffProchainId
    ADB.db.buffProchainId = id + 1
    table.insert(ADB.db.buffDefs, { id = id, nom = nom, icon = icon, duree = Borner(duree, 1, 20),
        typ = typ, val = Borner(val, 0, 999) })
    return true
end

function ADB.BufSupprDef(id)
    for i, d in ipairs(ADB.db.buffDefs) do
        if d.id == id then table.remove(ADB.db.buffDefs, i) break end
    end
    ADB.BufMajFenetre()
end

------------------------------------------------------------------------------
-- Cles de cibles
------------------------------------------------------------------------------
function ADB.CleUnite(u)
    if not UnitExists(u) then return nil end
    local nom = UnitName(u)
    if UnitIsPlayer(u) then
        if nom == ADB.playerName or ADB.roster[nom] then return "P:" .. nom end
        return nil
    end
    local p = ADB.TrouverPNJNom(nom)
    if p then return "N:" .. p.id end
    return "E:" .. (UnitGUID(u) or "?")
end

function ADB.CleDepuisEntree(e)
    if not e then return nil end
    if e.k == "P" then return "P:" .. e.id end
    local p = ADB.TrouverPNJNom(e.nom)
    if p then return "N:" .. p.id end
    return "E:" .. e.id
end

function ADB.NomCle(key)
    local k, id = key:sub(1, 1), key:sub(3)
    if k == "P" then return ADB.NomAffiche(id) end
    if k == "N" and ADB.db then
        local p = PNJ(tonumber(id))
        if p then return p.nom end
    end
    return "La cible"
end

function ADB.CleLiee(key)
    if not ADB.playerName then return nil end
    local p = ADB.GetPet()
    if not p then return nil end
    if key == "P:" .. ADB.playerName then return "N:" .. p.id end
    if key == "N:" .. p.id then return "P:" .. ADB.playerName end
end

function ADB.BufA(key, typ)
    for _, b in ipairs(ADB.buffs[key] or {}) do if b.typ == typ then return true end end
    return false
end

-- bonus precision, bonus critique, multiplicateur degats (Courroux Bestial : joueur + familier)
function ADB.BufBonus(key)
    local bp, bc, bd = 0, 0, 1
    local function scan(k)
        for _, b in ipairs(ADB.buffs[k] or {}) do
            if b.typ == 5 then bp, bc, bd = 5, 5, 1.5 end
        end
    end
    scan(key)
    local l = ADB.CleLiee(key)
    if l then scan(l) end
    return bp, bc, bd
end

------------------------------------------------------------------------------
-- Pose / diffusion (MJ autoritaire)
------------------------------------------------------------------------------
function ADB.BufDiffuser(key)
    if not ADB.EstMJ() then return end
    local l, k = ADB.buffs[key], Encoder(key)
    if not l or #l == 0 then ADB.TalEnfiler(format("BF;%s;0;0;", k)) return end
    for i, b in ipairs(l) do ADB.TalEnfiler(format("BF;%s;%d;%d;%s", k, i, #l, Entree(b))) end
end

function ADB.BufDiffuserTout()
    if not ADB.EstMJ() then return end
    for key in pairs(ADB.buffs) do ADB.BufDiffuser(key) end
end

function ADB.BufPoser(key, inst)
    if not ADB.EstMJ() then return false end
    if ADB.phase == "IDLE" then ADB.Print("Les buffs/debuffs ne s'appliquent qu'en combat.") return false end
    local l = ADB.buffs[key]
    if not l then l = {} ADB.buffs[key] = l end
    local place
    for i, b in ipairs(l) do
        if b.id == inst.id then l[i] = inst place = true break end
    end
    if not place then
        if #l >= PAR_CIBLE then return false end
        l[#l + 1] = inst
    end
    ADB.AnnoncerChat(format("%s est affecté par %s (%d tour%s).", ADB.NomCle(key), inst.nom,
        inst.left, inst.left > 1 and "s" or ""))
    ADB.BufDiffuser(key)
    ADB.BufRafraichir()
    return true
end

function ADB.BufPoserDef(def, key, bonus, mult)
    local val = def.val
    if def.typ <= 2 then val = Borner(floor((def.val + (bonus or 0)) * (mult or 1) + 0.5), 0, 999) end
    return ADB.BufPoser(key, { id = def.id, left = def.duree, typ = def.typ, val = val,
        icon = def.icon, nom = def.nom })
end

-- Demande de pose (id < 0 : etourdissement integre, bonus = nb de tours)
function ADB.BufDemander(id, bonus, mult, key)
    if not key then return end
    if ADB.EstMJ() then
        ADB.BufTraiter(id, bonus, floor(mult * 100 + 0.5), key)
    elseif IsInGroup() then
        ADB.TalEnfiler(format("BA;%d;%d;%d;%s", id, bonus, floor(mult * 100 + 0.5), Encoder(key)))
    end
end

function ADB.BufTraiter(id, bonus, mult100, key)
    if id == -1 then
        return ADB.BufPoser(key, { id = -1, left = Borner(bonus, 1, 3), typ = 4, val = 0,
            icon = "Spell_Frost_Stun", nom = "Étourdissement" })
    end
    local def = ADB.BufDef(id)
    if def then ADB.BufPoserDef(def, key, Borner(bonus, 0, 5), Borner(mult100, 0, 3000) / 100) end
end

function ADB.BufAppliquerForce(id)
    local def = ADB.BufDef(id)
    local key = ADB.CleUnite("target")
    if not ADB.EstMJ() or not def then return end
    if not key then ADB.Print("Ciblez un personnage valide.") return end
    ADB.BufPoserDef(def, key, 0, 1)
end

function ADB.BufDepuisTalent(n, cibles)
    local mult, bonus = ADB.TalMult(n), ADB.TalBonusSpe(n)
    if not cibles or #cibles == 0 then cibles = { { k = "P", id = ADB.playerName } } end
    for _, e in ipairs(cibles) do ADB.BufDemander(n.buffId, bonus, mult, ADB.CleDepuisEntree(e)) end
end

function ADB.BufRecevoir(cmd, nom, p)
    if cmd == "BA" then
        if not ADB.EstMJ() or not ADB.roster[nom] then return end
        local id, bonus, m = tonumber(p[2]), tonumber(p[3]), tonumber(p[4])
        local key = Decoder(p[5] or "")
        if id and bonus and m and key:match("^[PNE]:.+") and #key < 80 then
            ADB.BufTraiter(floor(id), floor(bonus), floor(m), key)
        end
    elseif cmd == "BF" then
        if ADB.EstMJ() or not ADB.EstNomMJ(nom) then return end
        local key = Decoder(p[2] or "")
        local i, n = tonumber(p[3]), tonumber(p[4])
        if not (i and n and key:match("^[PNE]:.+") and #key < 80) then return end
        if n == 0 then
            ADB.buffs[key] = nil
        elseif i >= 1 and i <= n and n <= PAR_CIBLE then
            local t = ADB.bufTmp[key]
            if i == 1 or not t or t.n ~= n then t = { n = n, l = {} } ADB.bufTmp[key] = t end
            t.l[i] = Lire(p[5] or "")
            for j = 1, n do if not t.l[j] then return end end
            ADB.buffs[key], ADB.bufTmp[key] = t.l, nil
        else
            return
        end
        ADB.BufRafraichir()
    end
end

------------------------------------------------------------------------------
-- Resolution des effets (MJ)
------------------------------------------------------------------------------
local function Effet(key, b)
    local k, id = key:sub(1, 1), key:sub(3)
    local delta = b.typ == 1 and -b.val or b.val
    if k == "P" then
        local d = ADB.GetStatBlock(id)
        if d and id ~= ADB.playerName then ADB.AppliquerValeur(id, "pv", d.pv + delta) end
    elseif k == "N" then
        local p = PNJ(tonumber(id))
        if p then ADB.AppliquerValeurPNJ(p.id, "pv", p.pv + delta) end
    else
        ADB.AjouterDegats(id, -delta)
    end
end

local function Resoudre(allies)
    local modif = {}
    for key, l in pairs(ADB.buffs) do
        local k, est = key:sub(1, 1), false
        if k == "P" then est = true
        elseif k == "N" then
            local p = PNJ(tonumber(key:sub(3)))
            est = p and p.ally or false
        end
        if est == allies then
            for i = #l, 1, -1 do
                local b = l[i]
                if b.typ <= 2 then Effet(key, b) end
                b.left = b.left - 1
                if b.left <= 0 then table.remove(l, i) end
            end
            if #l == 0 then ADB.buffs[key] = nil end
            modif[key] = true
        end
    end
    for key in pairs(modif) do ADB.BufDiffuser(key) end
    ADB.BufRafraichir()
end

local derniere = "IDLE"
hooksecurefunc(ADB, "PhaseCombat", function()
    local prev, ph = derniere, ADB.phase
    derniere = ph
    if prev == ph then return end
    if ph == "IDLE" then
        wipe(ADB.buffs)
        wipe(ADB.bufTmp)
        ADB.BufRafraichir()
    elseif ADB.EstMJ() then
        if prev == "PLAYER_TURN" then Resoudre(true)
        elseif prev == "ENEMY_TURN" then Resoudre(false) end
    end
end)

hooksecurefunc(ADB, "PlanifierPNJComplet", function()
    if ADB.EstMJ() and ADB.phase ~= "IDLE" and not ADB.bufPlan then
        ADB.bufPlan = true
        C_Timer.After(2, function() ADB.bufPlan = false ADB.BufDiffuserTout() end)
    end
end)

------------------------------------------------------------------------------
-- Affichage
------------------------------------------------------------------------------
function ADB.BufDesc(b)
    if b.typ == 1 then return format("Inflige %d dégâts par tour.", b.val)
    elseif b.typ == 2 then return format("Rend %d PV par tour.", b.val)
    elseif b.typ == 3 then return "Immobilisation : bloque tout déplacement."
    elseif b.typ == 4 then return "Étourdissement : empêche toute action." end
    return "+50% de dégâts, +5 de précision et +5% de coup critique (joueur et familier)."
end

function ADB.BufInfobulle(ic)
    local b = ic.b
    if not b then return end
    local bien = (b.typ == 2 or b.typ == 5)
    GameTooltip:SetOwner(ic, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(b.nom, bien and 0.3 or 1, bien and 1 or 0.3, 0.3)
    GameTooltip:AddLine(ADB.BufDesc(b), 1, 1, 1, true)
    GameTooltip:AddLine(format("Tours restants : %d", b.left), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function CreerIcone(parent, t)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(t, t)
    b.bord = b:CreateTexture(nil, "BACKGROUND")
    b.bord:SetPoint("TOPLEFT", -1, 1)
    b.bord:SetPoint("BOTTOMRIGHT", 1, -1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.nb = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.nb:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnEnter", ADB.BufInfobulle)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Maj(c, liste, t, parLigne, dir)
    c.btns = c.btns or {}
    liste = liste or {}
    for i, b in ipairs(liste) do
        local ic = c.btns[i]
        if not ic then ic = CreerIcone(c, t) c.btns[i] = ic end
        local col, lig = (i - 1) % parLigne, floor((i - 1) / parLigne)
        local pt = dir > 0 and "TOPLEFT" or "TOPRIGHT"
        ic:ClearAllPoints()
        ic:SetPoint(pt, c, pt, dir * col * (t + 3), -lig * (t + 3))
        ic.b = b
        ic.tex:SetTexture(IconeTex(b.icon))
        ic.nb:SetText(b.left)
        if b.typ == 2 or b.typ == 5 then ic.bord:SetColorTexture(0.1, 0.7, 0.1, 1)
        else ic.bord:SetColorTexture(0.8, 0.1, 0.1, 1) end
        ic:Show()
    end
    for i = #liste + 1, #c.btns do c.btns[i]:Hide() c.btns[i].b = nil end
end

function ADB.BufRafraichir()
    if not ADB.playerName then return end
    if ADB.buffAnchor then Maj(ADB.buffAnchor, ADB.buffs["P:" .. ADB.playerName], 30, 8, -1) end
    if ADB.buffTarget then
        local k = ADB.CleUnite("target")
        Maj(ADB.buffTarget, k and ADB.buffs[k], 22, 8, 1)
    end
end
hooksecurefunc(ADB, "RafraichirCible", function() ADB.BufRafraichir() end)

------------------------------------------------------------------------------
-- Fenetre MJ
------------------------------------------------------------------------------
function ADB.BufMajFenetre()
    local f = ADB.bufFrame
    if not f or not f:IsShown() then return end
    f.IconeTex:SetTexture(IconeTex(f.icon))
    UIDropDownMenu_SetText(f.TypeDrop, TYPES[f.typ])
    local defs = ADB.db.buffDefs
    for i, r in ipairs(f.rows) do
        local d = defs[i]
        r.id = d and d.id
        for _, w in ipairs({ r.ic, r.txt, r.app, r.del }) do w:SetShown(d ~= nil) end
        if d then
            r.ic:SetTexture(IconeTex(d.icon))
            r.txt:SetText(format("#%d %s |cffaaaaaa(%s, %dt%s)|r", d.id, d.nom, TYPES[d.typ], d.duree,
                d.typ <= 2 and (", " .. d.val) or ""))
        end
    end
end

function ADB.BufCreerFenetre()
    local f = UI.FenetreBase("ADBBuffMJFrame", 380, 470, "Buffs / Debuffs (MJ)")
    ADB.bufFrame = f
    f:SetPoint("CENTER", -300, 0)
    tinsert(UISpecialFrames, "ADBBuffMJFrame")
    f.icon, f.typ = "INV_Misc_QuestionMark", 1

    UI.Etiq(f, "Nom", 16, -40)
    f.Nom = UI.Saisie(f, 70, -37, 170, 24)

    UI.Etiq(f, "Icône", 16, -76)
    local ib = CreateFrame("Button", nil, f)
    ib:SetSize(32, 32)
    ib:SetPoint("TOPLEFT", 70, -66)
    local bg = ib:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.4, 0.4, 0.4, 1)
    f.IconeTex = ib:CreateTexture(nil, "ARTWORK")
    f.IconeTex:SetPoint("TOPLEFT", 2, -2)
    f.IconeTex:SetPoint("BOTTOMRIGHT", -2, 2)
    f.IconeTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ib:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ib:SetScript("OnClick", function()
        ADB.OuvrirIcones(function(v)
            v = tostring(v)
            if #v == 0 or #v > 40 or v:find("[^%w_]") then v = "INV_Misc_QuestionMark" end
            f.icon = v
            ADB.BufMajFenetre()
        end)
    end)
    UI.Etiq(f, "Durée (tours)", 130, -76)
    f.Duree = UI.Saisie(f, 230, -73, 40, 2, true)
    f.Duree:SetText("3")

    UI.Etiq(f, "Type", 16, -116)
    f.TypeDrop = CreateFrame("Frame", "ADBBuffTypeDrop", f, "UIDropDownMenuTemplate")
    f.TypeDrop:SetPoint("TOPLEFT", 50, -109)
    UIDropDownMenu_SetWidth(f.TypeDrop, 160)
    UIDropDownMenu_Initialize(f.TypeDrop, function(self, niveau)
        for i, t in ipairs(TYPES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = t, (f.typ == i)
            info.func = function() f.typ = i ADB.BufMajFenetre() end
            UIDropDownMenu_AddButton(info, niveau)
        end
    end)

    UI.Etiq(f, "Valeur", 16, -150)
    f.Val = UI.Saisie(f, 70, -147, 50, 3, true)
    f.Val:SetText("3")
    UI.Bouton(f, "Créer", 150, -147, 100, function()
        if ADB.BufCreerDef(f.Nom:GetText(), f.icon, tonumber(f.Duree:GetText()) or 1, f.typ,
            tonumber(f.Val:GetText()) or 0) then
            f.Nom:SetText("")
            ADB.BufMajFenetre()
        end
    end)
    UI.Etiq(f, "ID à saisir dans l'éditeur de talents pour lier un debuff.", 16, -176, "GameFontDisableSmall")

    f.rows = {}
    for i = 1, BUF_MAX do
        local y, r = -196 - (i - 1) * 22, {}
        r.ic = f:CreateTexture(nil, "ARTWORK")
        r.ic:SetSize(18, 18)
        r.ic:SetPoint("TOPLEFT", 16, y - 2)
        r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.txt = UI.Etiq(f, "", 40, y - 5, "GameFontHighlightSmall")
        r.txt:SetWidth(190)
        r.txt:SetWordWrap(false)
        r.app = UI.Bouton(f, "Appliquer", 236, y, 70, function() ADB.BufAppliquerForce(r.id) end)
        r.del = UI.Bouton(f, "X", 310, y, 28, function() ADB.BufSupprDef(r.id) end)
        f.rows[i] = r
    end
    f:SetScript("OnShow", ADB.BufMajFenetre)
end

function ADB.BufCommande(reste)
    if not ADB.EstMJ() then ADB.Print("Réservé au MJ.") return end
    reste = strtrim(reste or "")
    if reste == "" then
        local f = ADB.bufFrame
        if f:IsShown() then f:Hide() else f:Show() end
        return
    end
    local def = ADB.BufDefNom(reste)
    if not def then ADB.Print("Buff/debuff inconnu : " .. reste) return end
    ADB.BufAppliquerForce(def.id)
end

------------------------------------------------------------------------------
-- Editeur de talents : champ "Buff ID" + immobilisation
------------------------------------------------------------------------------
local function NoeudSel()
    local f = ADB.talFrame
    local a = f and ADB.TalArbre(ADB.talVue)
    return a and f.sel and a.noeuds[f.sel] or nil
end

hooksecurefunc(ADB, "TalCreer", function()
    local A = ADB.talFrame.Ed.C.Actif
    UI.Etiq(A, "Buff ID", 138, -4)
    local e = UI.Saisie(A, 190, -1, 50, 4, true)
    e:SetScript("OnTextChanged", function(self, user)
        local n = NoeudSel()
        if user and n and ADB.PeutEditerTalents() then
            n.buffId = Borner(floor(tonumber(self:GetText()) or 0), 0, 9999)
            ADB.TalPlanifierNoeud(ADB.TalIndexClasse(ADB.talVue), n.id)
        end
    end)
    ADB.talFrame.Ed.C.BuffId = e
end)

hooksecurefunc(ADB, "TalMajPanneau", function()
    local f, n = ADB.talFrame, NoeudSel()
    local e = f and f.Ed.C.BuffId
    if e and n and f.edition and not e:HasFocus() then
        e:SetText((n.buffId or 0) > 0 and n.buffId or "")
    end
end)

local tk, acc, ix, iy, warn = CreateFrame("Frame"), 0
tk:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.3 then return end
    acc = 0
    if ADB.db and ADB.playerName and ADB.phase ~= "IDLE" and not ADB.EstMJ()
        and ADB.BufA("P:" .. ADB.playerName, 3) then
        local y, x = UnitPosition("player")
        if x then
            if not ix then ix, iy = x, y
            elseif not warn and sqrt((x - ix) ^ 2 + (y - iy) ^ 2) > 1.5 then
                warn = true
                UIErrorsFrame:AddMessage("Vous êtes immobilisé : déplacement interdit !", 1, 0.3, 0.3)
                ADB.AnnoncerChat(format("%s s'est déplacé alors qu'il est immobilisé.",
                    ADB.NomAffiche(ADB.playerName)))
            end
        end
    else
        ix, iy, warn = nil, nil, nil
    end
end)

function ADB.BufInit()
    ADB.BufInitDB()
    local a = CreateFrame("Frame", "ADBBuffAnchor", UIParent)
    a:SetSize(260, 40)
    a:SetFrameStrata("LOW")
    a:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -215, -14)
    ADB.buffAnchor = a
    local t = CreateFrame("Frame", nil, ADBTargetFrame)
    t:SetSize(190, 24)
    t:SetPoint("TOPLEFT", ADBTargetFrame, "BOTTOMLEFT", 4, -18)
    ADB.buffTarget = t
    ADB.BufCreerFenetre()
end