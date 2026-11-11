-- Transfert.lua : export / import de la configuration des talents (MJ)
local ADB = ADB
local floor, max = math.floor, math.max
local format = string.format
local Decoder, UI = ADB.Decoder, ADB.UI

local function Esc(s) return (tostring(s or ""):gsub("[%%;~]", function(c) return format("%%%02X", c:byte()) end)) end

------------------------------------------------------------------------------
-- Export
------------------------------------------------------------------------------
function ADB.TalExporter()
    local out = { "ADB1" }
    local classes = {}
    for classe in pairs(ADB.db.talents.arbres) do classes[#classes + 1] = classe end
    table.sort(classes)
    for _, classe in ipairs(classes) do
        local a = ADB.db.talents.arbres[classe]
        out[#out + 1] = format("T;%s;%d", Esc(classe), a.prochain or 1)
        local bids = {}
        for id in pairs(a.colorBoxes or {}) do bids[#bids + 1] = id end
        table.sort(bids)
        for _, id in ipairs(bids) do
            local b = a.colorBoxes[id]
            out[#out + 1] = format("C;%s;%d;%d;%d;%d;%d;%d;%d;%d;%d", Esc(classe), b.id, b.x1, b.y1, b.x2, b.y2,
                b.r, b.g, b.b, b.a)
        end
        local ids = {}
        for id in pairs(a.noeuds) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local n = a.noeuds[id]
            out[#out + 1] = table.concat({ "N", Esc(classe), n.id, n.x, n.y, n.typ, n.stat, n.inter, n.elem,
                n.mana, n.lim, n.reac and 1 or 0, n.bonus and 1 or 0, table.concat(n.req, ","), n.icon,
                Esc(n.nom), Esc(n.desc), n.coutPV, n.portee, n.precision, n.zoe, n.spe and 1 or 0,
                n.specX, n.specY, table.concat(n.tags, ","), n.buffId or 0 }, ";")
        end
    end
    for _, d in ipairs(ADB.db.buffDefs or {}) do
        out[#out + 1] = format("B;%d;%s;%s;%d;%d;%d", d.id, Esc(d.nom), d.icon, d.duree, d.typ, d.val)
    end
    return table.concat(out, "~")
end

------------------------------------------------------------------------------
-- Import (analyse + validation complète via ValiderNoeud, rien n'est appliqué avant confirmation)
------------------------------------------------------------------------------
local function Parser(txt)
    txt = (txt or ""):gsub("[\r\n]", "")
    if txt:sub(1, 4) ~= "ADB1" then return nil end
    local R = { arbres = {}, buffs = {}, nb = 0, nbBox = 0 }
    for rec in txt:gmatch("[^~]+") do
        local p = { strsplit(";", rec) }
        local k = p[1]
        if k == "T" then
            local cl = Decoder(p[2] or "")
            if ADB.CLASSE_MAP[cl] then
                R.arbres[cl] = R.arbres[cl] or { noeuds = {}, prochain = 1, colorBoxes = {}, cbProchain = 1 }
                R.arbres[cl].prochain = max(1, floor(tonumber(p[3]) or 1))
            end
        elseif k == "N" then
            local a = R.arbres[Decoder(p[2] or "")]
            if a then
                local req = {}
                for s in (p[14] or ""):gmatch("%d+") do req[#req + 1] = tonumber(s) end
                local n = ADB.TalValiderNoeud({
                    id = p[3], x = p[4], y = p[5], typ = p[6], stat = p[7], inter = p[8], elem = p[9],
                    mana = p[10], lim = p[11], reac = (p[12] == "1"), bonus = (p[13] == "1"), req = req,
                    icon = p[15], nom = Decoder(p[16] or ""), desc = Decoder(p[17] or ""),
                    coutPV = p[18], portee = p[19], precision = p[20], zoe = p[21], spe = (p[22] == "1"),
                    specX = p[23], specY = p[24], tags = p[25], buffId = p[26],
                })
                if n and not a.noeuds[n.id] then
                    a.noeuds[n.id] = n
                    a.prochain = max(a.prochain, n.id + 1)
                    R.nb = R.nb + 1
                end
            end
        elseif k == "C" then
            local a = R.arbres[Decoder(p[2] or "")]
            if a then
                local b = ADB.TalValiderColorBox({ id = p[3], x1 = p[4], y1 = p[5], x2 = p[6], y2 = p[7],
                    r = p[8], g = p[9], b = p[10], a = p[11] })
                if b and not a.colorBoxes[b.id] then
                    a.colorBoxes[b.id] = b
                    a.cbProchain = max(a.cbProchain, b.id + 1)
                    R.nbBox = R.nbBox + 1
                end
            end
        elseif k == "B" then
            R.buffs[#R.buffs + 1] = { id = p[2], nom = Decoder(p[3] or ""), icon = p[4],
                duree = p[5], typ = p[6], val = p[7] }
        end
    end
    if R.nb == 0 and #R.buffs == 0 and R.nbBox == 0 then return nil end
    return R
end

local function Appliquer(R)
    if not ADB.PeutEditerTalents() then return end
    local T = ADB.db.talents
    T.arbres, T.appris, T.cd = R.arbres, {}, {}
    ADB.db.buffDefs = R.buffs
    ADB.BufInitDB()                       -- valide + recalcule le prochain ID
    ADB.TalRafraichir()
    if ADB.EstMJ() then
        for ci in ipairs(ADB.CLASSES) do ADB.TalDiffuserClasse(ci) end   -- resynchronise les joueurs
    end
    if ADB.bufFrame then ADB.BufMajFenetre() end
    ADB.Print(format("Configuration importée : %d talents.", R.nb))
end

StaticPopupDialogs["ADB_TAL_IMPORT"] = {
    text = "Importer %s talent(s) ?\nTous les arbres et buffs actuels seront REMPLACÉS.",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(self, data) if data then Appliquer(data) end end,
}

------------------------------------------------------------------------------
-- Fenêtre
------------------------------------------------------------------------------
local function Creer()
    local f = UI.FenetreBase("ADBTransfFrame", 500, 400, "Export / Import des talents")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetPoint("CENTER", 0, 0)
    tinsert(UISpecialFrames, "ADBTransfFrame")
    local sf = CreateFrame("ScrollFrame", "ADBTransfScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -34)
    sf:SetPoint("BOTTOMRIGHT", -32, 50)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(440)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    f.Edit = eb
    UI.Bouton(f, "Exporter", 20, -368, 120, function()
        eb:SetText(ADB.TalExporter())
        eb:SetFocus()
        eb:HighlightText()
    end)
    UI.Bouton(f, "Importer", 150, -368, 120, function()
        local R = Parser(eb:GetText())
        if not R then
            ADB.Print("Texte d'import invalide.")
            return
        end
        StaticPopup_Show("ADB_TAL_IMPORT", tostring(R.nb), nil, R)
    end)
    UI.Etiq(f, "Exporter : Ctrl+C.  Importer : coller (Ctrl+V) puis Importer.", 280, -372, "GameFontDisableSmall")
    return f
end

function ADB.BasculerTransfert()
    if not ADB.transfFrame then ADB.transfFrame = Creer() end
    local f = ADB.transfFrame
    if f:IsShown() then f:Hide() else f:Show() end
end

-- Bouton dans la fenêtre de talents (MJ / hors groupe uniquement)
hooksecurefunc(ADB, "TalCreer", function()
    local f = ADB.talFrame
    f.BtnTransf = UI.Bouton(f, "Export / Import", 672, -660, 120, ADB.BasculerTransfert)
end)
hooksecurefunc(ADB, "TalMajPanneau", function()
    local b = ADB.talFrame and ADB.talFrame.BtnTransf
    if b then b:SetShown(ADB.PeutEditerTalents()) end
end)