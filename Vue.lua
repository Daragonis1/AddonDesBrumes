-- Vue.lua : le MJ consulte l'inventaire d'un joueur (VQ demande ; VB/VI/VE réponse)
local ADB = ADB
local floor = math.floor
local format = string.format
local Encoder, Decoder, UI = ADB.Encoder, ADB.Decoder, ADB.UI

for _, c in ipairs({ "VQ", "VB", "VI", "VE" }) do ADB.CMD_EXT[c] = true end
ADB.vueAttente, ADB.vueTmp, ADB.vueInv = {}, {}, {}

-- Joueur : envoie son inventaire
local function EnvoyerInv()
    local db = ADB.db
    ADB.TalEnfiler("VB;" .. (db.pc or 0))
    local function It(zone, key, it)
        ADB.TalEnfiler(format("VI;%s;%s;%s;%s;%d;%s;%d;%d;%d;%s;%s;%s;%d;%s", zone, key, it.kind, it.slot or "",
            it.rar or 1, it.icon or "", it.st and it.st[1] or 0, it.st and it.st[2] or 0, it.st and it.st[3] or 0,
            Encoder(it.nom or ""), Encoder(it.comp or ""), table.concat(it.sk or {}, ","), it.count or 1,
            table.concat(it.tags or {}, ",")))
    end
    for i = 1, ADB.INV_SLOTS do if db.inv[i] then It("inv", i, db.inv[i]) end end
    for _, s in ipairs(ADB.SLOTS) do if db.equip[s[1]] then It("eq", s[1], db.equip[s[1]]) end end
    ADB.TalEnfiler("VE")
end

local function Recevoir(cmd, nom, message)
    local p = { strsplit(";", message) }
    -- Recevoir, branche VQ :
    if cmd == "VQ" then
        if ADB.EstNomMJ(nom) and not ADB.EstMJ() and p[2] == ADB.playerName then
            if p[3] == "alt" then
                if ADB.alt then ADB.Ctx(true, EnvoyerInv) end
            else
                EnvoyerInv()
            end
        end
        return
    end
    if not (ADB.EstMJ() and ADB.vueAttente[nom] and ADB.roster[nom]) then return end
    if cmd == "VB" then
        ADB.vueTmp[nom] = { inv = {}, eq = {}, pc = tonumber(p[2]) or 0 }
    elseif cmd == "VI" then
        local t = ADB.vueTmp[nom]
        if not t then return end
        local it = ADB.ValiderItem({
            kind = p[4],
            slot = p[5],
            rar = tonumber(p[6]),
            icon = p[7],
            st = { tonumber(p[8]), tonumber(p[9]), tonumber(p[10]) },
            nom = Decoder(p[11] or ""),
            comp = Decoder(p[12] or ""),
            sk = p[13],
            count = tonumber(p[14]),
            tags = p[15],
        })
        if not it then return end
        if p[2] == "inv" then
            local k = tonumber(p[3])
            if k and k >= 1 and k <= ADB.INV_SLOTS then t.inv[floor(k)] = it end
        elseif ADB.SLOT_NOM[p[3] or ""] then
            t.eq[p[3]] = it
        end
    elseif cmd == "VE" then
        ADB.vueInv[nom], ADB.vueTmp[nom], ADB.vueAttente[nom] = ADB.vueTmp[nom], nil, nil
        ADB.VueAfficher(nom)
    end
end

local oExt = ADB.RecevoirExt
ADB.RecevoirExt = function(cmd, nom, message)
    if cmd == "VQ" or cmd == "VB" or cmd == "VI" or cmd == "VE" then return Recevoir(cmd, nom, message) end
    return oExt(cmd, nom, message)
end

-- MJ : fenêtre d'affichage
local function Slot(f, x, y, label)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(40, 40)
    b:SetPoint("TOPLEFT", x, y)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetPoint("TOPLEFT", 2, -2)
    b.icone:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.nb = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.nb:SetPoint("BOTTOMRIGHT", -3, 3)
    b.lbl = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.lbl:SetPoint("CENTER")
    b.lbl:SetText(label or "")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnEnter", function(s)
        local it = s.it
        if not it then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ADB.NomColore(it))
        if it.kind == "equip" then
            GameTooltip:AddLine(ADB.SLOT_NOM[it.slot], 1, 1, 1)
            for i = 1, 3 do
                if it.st[i] > 0 then GameTooltip:AddLine("+" .. it.st[i] .. " " .. ADB.STAT_NOMS[i], 0.1, 1, 0.1) end
            end
            if it.comp ~= "" then GameTooltip:AddLine("Compétences : " .. it.comp, 1, 0.82, 0, true) end
            if it.sk and #it.sk > 0 then GameTooltip:AddLine("Skills IDs : " .. table.concat(it.sk, ","), 0.5, 0.8, 1) end
        elseif ADB.CONSO[it.kind] then
            GameTooltip:AddLine(ADB.CONSO[it.kind].desc, 1, 0.82, 0, true)
        end
        if it.tags and #it.tags > 0 then GameTooltip:AddLine("Tags : " .. table.concat(it.tags, ","), 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    return b
end

local function MajSlot(b, it)
    b.it = it
    if it then
        local _, tex, r, g, bl = ADB.InfoObjet(it)
        b.fond:SetColorTexture(r, g, bl, 1)
        b.icone:SetTexture(tex)
        b.icone:Show()
        b.nb:SetText((it.count and it.count > 1) and it.count or "")
        b.lbl:SetText("")
    else
        b.fond:SetColorTexture(0.15, 0.15, 0.15, 1)
        b.icone:Hide()
        b.nb:SetText("")
        b.lbl:SetText(b.vide or "")
    end
end

function ADB.VueAfficher(nom)
    local f = ADB.vueFrame
    if not f then
        f = UI.FenetreBase("ADBVueInvFrame", 280, 330, "Inventaire")
        ADB.vueFrame = f
        f:SetPoint("CENTER", 300, 0)
        tinsert(UISpecialFrames, "ADBVueInvFrame")
        f.eq, f.inv = {}, {}
        for k, s in ipairs(ADB.SLOTS) do
            f.eq[s[1]] = Slot(f, 16 + (k - 1) * 48, -64)
            f.eq[s[1]].vide = s[2]
        end
        for i = 1, ADB.INV_SLOTS do
            f.inv[i] = Slot(f, 40 + ((i - 1) % 4) * 52, -122 - floor((i - 1) / 4) * 48)
        end
        f.Nom = UI.Etiq(f, "", 16, -36, "GameFontNormal")
        f.Or = UI.Etiq(f, "", 16, -312, "GameFontHighlightSmall")
    end
    local d = ADB.vueInv[nom]
    if not d then return end
    local lib = ADB.NomAffiche(nom)
    if ADB.vueModeAlt then
        local pn = ADB.AltDe(nom)
        lib = (pn and ADB.PNJNom(pn) or lib) .. " (secondaire)"
    end
    f.Nom:SetText(lib)
    f.Or:SetText("Or : " .. ADB.FormatOr(d.pc))
    for _, s in ipairs(ADB.SLOTS) do MajSlot(f.eq[s[1]], d.eq[s[1]]) end
    for i = 1, ADB.INV_SLOTS do MajSlot(f.inv[i], d.inv[i]) end
    f:Show()
end

function ADB.VueDemander(nom, alt)
    if not ADB.EstMJ() or not nom then return end
    if nom == ADB.playerName then
        ADB.BasculerInv()
        return
    end
    if not ADB.roster[nom] then
        ADB.Print("Aucune donnée pour " .. nom .. ".")
        return
    end
    ADB.vueAttente[nom] = true
    ADB.vueModeAlt = alt and true or nil
    ADB.Envoyer("VQ;" .. nom .. (alt and ";alt" or ""))
    C_Timer.After(10, function() ADB.vueAttente[nom] = nil end)
end

-- Bouton "Inventaire" dans la fiche JDR (MJ uniquement)
local function MajBouton()
    local f = ADBFicheFrame
    if not f then return end
    if not f.BtnInv then
        f.BtnInv = UI.Bouton(f, "Inventaire", 90, -296, 100, function() ADB.VueDemander(f.nomAffiche) end)
    end
    f.BtnInv:SetShown(ADB.EstMJ() and f.nomAffiche ~= nil)
end
hooksecurefunc(ADB, "OuvrirFiche", MajBouton)
hooksecurefunc(ADB, "RafraichirFiche", MajBouton)
