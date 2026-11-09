-- Don.lua : potion = action, transfert d'objets, objets narratifs (MJ)
local ADB = ADB
local floor = math.floor
local format = string.format
local Encoder, Decoder, Net, UI = ADB.Encoder, ADB.Decoder, ADB.NettoyerNom, ADB.UI

ADB.CMD_EXT.IT, ADB.CMD_EXT.IU = true, true

local function Morceaux(s, taille)
    local t, i = {}, 1
    while i <= #s do
        local j = math.min(i + taille - 1, #s)
        while j < #s and j > i and (s:byte(j + 1) or 0) >= 0x80 and (s:byte(j + 1) or 0) < 0xC0 do j = j - 1 end
        t[#t + 1] = s:sub(i, j)
        i = j + 1
    end
    return t
end

------------------------------------------------------------------------------
-- 1. Potion = action
------------------------------------------------------------------------------
function ADB.PotionDemander(i)
    local s = ADB.db.inv[i]
    if not s then return end
    if ADB.phase == "IDLE" or ADB.EstMJ() then return ADB.UtiliserPotion(i) end
    if ADB.phase == "PLAYER_TURN" and not ADB.tourPasse then
        ADB.UtiliserPotion(i)
        ADB.FinTourJoueur()
    else
        StaticPopup_Show("ADB_TAL_HORSTOUR", ADB.CONSO[s.kind].nom, nil, { potion = i })
    end
end

function ADB.PotionDemanderMJ(i)
    local s = ADB.db.inv[i]
    if not s then return end
    if not IsInGroup() or not ADB.talSource then
        ADB.Print("Aucun MJ disponible pour valider cette action.")
        return
    end
    ADB.talJeton = (ADB.talJeton or 0) + 1
    ADB.talAttente[ADB.talJeton] = { potion = i, kind = s.kind }
    ADB.Envoyer(format("HQ;%d;0;%s;;", ADB.talJeton, Encoder(ADB.CONSO[s.kind].nom)))
    ADB.Print("Demande envoyée au MJ pour « " .. ADB.CONSO[s.kind].nom .. " ». En attente de validation...")
end

------------------------------------------------------------------------------
-- 2. Envoi / réception d'objets (IT = en-tête, IU = morceaux de description)
------------------------------------------------------------------------------
function ADB.DonEnvoyer(cible, it)
    local desc = Morceaux(it.desc or "", 60)
    ADB.TalEnfiler(format("IT;%s;%s;%s;%d;%s;%d;%d;%d;%s;%s;%s;%d;%d;%s", cible, it.kind, it.slot or "",
        it.rar or 1, it.icon or "", it.st and it.st[1] or 0, it.st and it.st[2] or 0, it.st and it.st[3] or 0,
        Encoder(it.nom or ""), Encoder(it.comp or ""), table.concat(it.sk or {}, ","), it.count or 1, #desc,
        table.concat(it.tags or {}, ",")))
    for i, s in ipairs(desc) do
        ADB.TalEnfiler(format("IU;%s;%d;%d;%s", cible, i, #desc, Encoder(s)))
    end
end

local buf = {}
local function Livrer(nom, t)
    local it = ADB.ValiderItem(t)
    if not it then return end
    if ADB.AjouterObjet(it, 1) >= 1 then
        ADB.Print(format("%s vous a transféré : %s.", ADB.NomAffiche(nom), ADB.NomColore(it)))
    else
        ADB.Print("Votre inventaire est plein ! " .. ADB.NomColore(it) .. " de " .. ADB.NomAffiche(nom) .. " perdu.")
    end
end

local function Recevoir(cmd, nom, message)
    if not (ADB.roster[nom] or ADB.EstNomMJ(nom)) then return end
    local p = { strsplit(";", message) }
    if p[2] ~= ADB.playerName then return end
    if cmd == "IT" then
        local nb = floor(tonumber(p[14]) or 0)
        local t = {
            kind = p[3],
            slot = p[4],
            rar = tonumber(p[5]),
            icon = p[6],
            st = { tonumber(p[7]), tonumber(p[8]), tonumber(p[9]) },
            nom = Decoder(p[10] or ""),
            comp = Decoder(p[11] or ""),
            sk = p[12],
            count = tonumber(p[13]),
            tags = p[15]
        }
        if nb <= 0 then Livrer(nom, t) elseif nb <= 10 then buf[nom] = { t = t, n = nb, l = {} } end
    else
        local b, i, n = buf[nom], tonumber(p[3]), tonumber(p[4])
        if not (b and i and n == b.n and i >= 1 and i <= n) then return end
        b.l[floor(i)] = Decoder(p[5] or "")
        for j = 1, n do if not b.l[j] then return end end
        buf[nom] = nil
        b.t.desc = table.concat(b.l, "", 1, n)
        Livrer(nom, b.t)
    end
end

local oExt = ADB.RecevoirExt
ADB.RecevoirExt = function(cmd, nom, message)
    if cmd == "IT" or cmd == "IU" then return Recevoir(cmd, nom, message) end
    return oExt(cmd, nom, message)
end

------------------------------------------------------------------------------
-- 3. Transfert : bouton + clic sur objet
------------------------------------------------------------------------------
local function Mode(on)
    ADB.transfMode = on
    local b = ADB.invFrame and ADB.invFrame.TransfBtn
    if b then b:SetText(on and "Annuler" or "Transférer") end
end

StaticPopupDialogs["ADB_DON"] = {
    text = "Transférer %s à %s ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(self, data) if data then ADB.DonConfirmer(data) end end,
}

function ADB.DonDemander(zone, key)
    Mode(false)
    local it = ADB.ObjetEn(zone, key)
    local c = ADB.CibleJoueur()
    if not it then return end
    if not c or c == ADB.playerName or not IsInGroup() then
        ADB.Print("Ciblez un autre joueur (en groupe, avec l'addon).")
        return
    end
    StaticPopup_Show("ADB_DON", ADB.NomColore(it), ADB.NomAffiche(c), { zone = zone, key = key, cible = c })
end

function ADB.DonConfirmer(d)
    local it = ADB.ObjetEn(d.zone, d.key)
    if not it or not ADB.roster[d.cible] then return end
    local copie = CopyTable(it)
    if copie.count then copie.count = 1 end
    ADB.DonEnvoyer(d.cible, copie)
    local txt = ADB.NomColore(it)
    if d.zone == "inv" then
        ADB.RetirerDe(d.key)
        ADB.RafraichirInv()
    else
        ADB.Detruire(d.zone, d.key)
    end
    ADB.Print(format("%s transféré à %s.", txt, ADB.NomAffiche(d.cible)))
end

local oClick = ADB.OnSlotClick
ADB.OnSlotClick = function(b, bouton)
    if ADB.transfMode and bouton == "LeftButton" and ADB.ObjetEn(b.zone, b.key) then
        return ADB.DonDemander(b.zone, b.key)
    end
    return oClick(b, bouton)
end

hooksecurefunc(ADB, "CreerInv", function()
    local f = ADB.invFrame
    f:SetHeight(450)
    f.TransfBtn = UI.Bouton(f, "Transférer", 16, -410, 100, function()
        Mode(not ADB.transfMode)
        if ADB.transfMode then ADB.Print("Ciblez un joueur, puis cliquez sur l'objet à transférer.") end
    end)
    f:HookScript("OnHide", function() Mode(false) end)
end)

------------------------------------------------------------------------------
-- 4. Objet narratif (MJ)
------------------------------------------------------------------------------
local function CreerNarratif()
    local f = UI.FenetreBase("ADBStoryFrame", 320, 340, "Objet narratif")
    ADB.storyFrame = f
    f:SetPoint("CENTER", -300, 0)
    tinsert(UISpecialFrames, "ADBStoryFrame")
    f.icon = "INV_Misc_Note_01"
    UI.Etiq(f, "Nom", 20, -40)
    f.Nom = UI.Saisie(f, 80, -37, 210, ADB.ITEM_NOM_MAX)
    UI.Etiq(f, "Icône", 20, -76)
    local ib = CreateFrame("Button", nil, f)
    ib:SetSize(36, 36)
    ib:SetPoint("TOPLEFT", 80, -68)
    local bg = ib:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.4, 0.4, 0.4, 1)
    f.IconeTex = ib:CreateTexture(nil, "ARTWORK")
    f.IconeTex:SetPoint("TOPLEFT", 2, -2)
    f.IconeTex:SetPoint("BOTTOMRIGHT", -2, 2)
    f.IconeTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.IconeTex:SetTexture(ADB.IconeTex(f.icon))
    ib:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ib:SetScript("OnClick", function()
        ADB.OuvrirIcones(function(v)
            v = tostring(v)
            if #v == 0 or #v > 40 or v:find("[^%w_]") then v = "INV_Misc_QuestionMark" end
            f.icon = v
            f.IconeTex:SetTexture(ADB.IconeTex(v))
        end)
    end)
    UI.Etiq(f, "Description", 20, -118)
    local cadre = CreateFrame("Frame", nil, f, "BackdropTemplate")
    cadre:SetSize(280, 100)
    cadre:SetPoint("TOPLEFT", 20, -136)
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
    eb:SetSize(268, 88)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    f.Desc = eb
    UI.Etiq(f, "Tags", 20, -250)
    f.Tags = UI.Saisie(f, 60, -247, 240, 600)
    UI.Bouton(f, "Donner à la cible", 20, -290, 140, function()
        if not ADB.EstMJ() then return end
        local nom = Net(f.Nom:GetText())
        if nom == "" then
            ADB.Print("Donnez un nom à l'objet.")
            return
        end
        local c = ADB.CibleJoueur()
        if not c then
            ADB.Print("Ciblez un joueur possédant l'addon.")
            return
        end
        local it = ADB.ValiderItem({
            kind = "story",
            rar = 1,
            icon = f.icon,
            nom = nom,
            desc = f.Desc:GetText(),
            tags = f.Tags:GetText()
        })
        if not it then return end
        if c == ADB.playerName then
            ADB.RecevoirObjet(it, 1)
        else
            ADB.DonEnvoyer(c, it)
            ADB.Print(format("%s envoyé à %s.", ADB.NomColore(it), ADB.NomAffiche(c)))
        end
    end)
    f:SetScript("OnHide", function() if ADB.iconFrame then ADB.iconFrame:Hide() end end)
end

hooksecurefunc(ADB, "CreerFenetreItem", function()
    local f = ADB.itemFrame
    f:SetHeight(520)
    UI.Bouton(f, "Objet narratif...", 80, -484, 160, function()
        if not ADB.storyFrame then CreerNarratif() end
        ADB.storyFrame:Show()
    end)
end)
