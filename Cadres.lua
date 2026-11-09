local ADB = ADB
local floor = math.floor

local TEX = "Interface\\TargetingFrame\\"
local BARRE = TEX .. "UI-StatusBar"
local FONT_TXT = GameFontHighlightSmall
local PITCH = 55

local ART_CIBLE = {
    elite = TEX .. "UI-TargetingFrame-Elite",
    worldboss = TEX .. "UI-TargetingFrame-Elite",
    rareelite = TEX .. "UI-TargetingFrame-Rare-Elite",
    rare = TEX .. "UI-TargetingFrame-Rare",
}

local function Barre(b, f, x, y, w, h, petit)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    b:SetSize(w, h)
    b:SetStatusBarTexture(BARRE)
    b.blizz = true
    local st = b:GetStatusBarTexture()
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= st and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    b.Text:SetFontObject(FONT_TXT)
    if petit then
        b.Text:Hide()
        b:HookScript("OnEnter", function(s) s.Text:Show() end)
        b:HookScript("OnLeave", function(s) s.Text:Hide() end)
    end
end

local function Fond(f, x, y, w, h)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(0, 0, 0, 0.5)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    return t
end

local function Portrait(f, u)
    if f.Portrait and u and UnitExists(u) then SetPortraitTexture(f.Portrait, u) end
end

local function Art(f)
    if f.Model then f.Model:Hide() end
    if f.SetBackdrop then f:SetBackdrop(nil) end
    local a = CreateFrame("Frame", nil, f)
    a:SetAllPoints(f)
    a:SetFrameLevel(f:GetFrameLevel() + 5)
    a:EnableMouse(false)
    f.Art = a
    f.NameText:SetParent(a)
    f.NameText:SetDrawLayer("OVERLAY")
    f.NameText:SetFontObject(GameFontNormalSmall)
    f.NameText:SetWordWrap(false)
    return a
end

local function Construire(f, joueur)
    f:SetSize(175, 76)
    local a = Art(f)
    local px = joueur and 42 or 126
    local bx = joueur and 106 or 7
    f.Fond = Fond(f, bx, -22, 119, 41)
    f.Portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.Portrait:SetSize(64, 64)
    f.Portrait:SetPoint("TOPLEFT", f, "TOPLEFT", px, -12)
    if not joueur then
        f.NomFond = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        f.NomFond:SetTexture(TEX .. "UI-TargetingFrame-LevelBackground")
        f.NomFond:SetSize(119, 19)
        f.NomFond:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -22)
    end
    a.Tex = a:CreateTexture(nil, "ARTWORK")
    a.Tex:SetSize(232, 100)
    a.Tex:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    a.Tex:SetTexture(TEX .. "UI-TargetingFrame")
    if joueur then a.Tex:SetTexCoord(1, 0.09375, 0, 0.78125) else a.Tex:SetTexCoord(0.09375, 1, 0, 0.78125) end
    f.NameText:SetSize(96, 12)
    f.NameText:SetJustifyH("CENTER")
    f.NameText:ClearAllPoints()
    f.NameText:SetPoint("TOPLEFT", f, "TOPLEFT", joueur and 118 or 18, -25)
    f.Level = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.Level:SetPoint("CENTER", f, "TOPLEFT", joueur and 53 or 179, -66)
    Barre(f.HP, f, bx, -41, 119, 12)
    Barre(f.MP, f, bx, -52, 119, 12)
end

function ADB.InitCadre(f)
    Construire(f, f:GetName() == "ADBPlayerFrame")
end

function ADB.Member_OnLoad(self)
    self:RegisterForClicks("AnyUp")
    self:SetAttribute("type1", "target")
    self.HP.kind = "pv"
    self.MP.kind = "pm"
    self:HookScript("OnMouseUp", ADB.OnPortraitMouseUp)
    self:SetSize(120, 53)
    if self.SetBackdrop then self:SetBackdrop(nil) end
    local a = Art(self)
    self.Fond = Fond(self, 46, -11, 71, 18)
    self.Portrait = self:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.Portrait:SetSize(37, 37)
    self.Portrait:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -6)
    a.Tex = a:CreateTexture(nil, "ARTWORK")
    a.Tex:SetSize(128, 64)
    a.Tex:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    a.Tex:SetTexture(TEX .. "UI-PartyFrame")
    self.NameText:SetSize(70, 12)
    self.NameText:SetJustifyH("LEFT")
    self.NameText:ClearAllPoints()
    self.NameText:SetPoint("TOPLEFT", self, "TOPLEFT", 46, -1)
    Barre(self.HP, self, 47, -12, 70, 7, true)
    Barre(self.MP, self, 47, -20, 70, 7, true)
end

local oNpcLoad = ADB.Npc_OnLoad
function ADB.Npc_OnLoad(self)
    if not (ADB.db and ADB.db.uiRemplacee) then return oNpcLoad(self) end
    self.HP.kind = "pv"
    self.MP.kind = "pm"
    self:SetSize(120, 53)
    if self.SetBackdrop then self:SetBackdrop(nil) end
    local a = Art(self)
    self.Fond = Fond(self, 46, -11, 71, 18)
    self.Icon:ClearAllPoints()
    self.Icon:SetSize(37, 37)
    self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -6)
    self.Icon:SetDrawLayer("BACKGROUND", 1)
    a.Tex = a:CreateTexture(nil, "ARTWORK")
    a.Tex:SetSize(128, 64)
    a.Tex:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    a.Tex:SetTexture(TEX .. "UI-PartyFrame")
    self.NameText:SetSize(70, 12)
    self.NameText:SetJustifyH("LEFT")
    self.NameText:ClearAllPoints()
    self.NameText:SetPoint("TOPLEFT", self, "TOPLEFT", 46, -1)
    Barre(self.HP, self, 47, -12, 70, 7, true)
    Barre(self.MP, self, 47, -20, 70, 7, true)
    self.Delete:SetFrameLevel(self:GetFrameLevel() + 10)
end

local oBarre = ADB.MajBarre
function ADB.MajBarre(b, c, m, sh)
    oBarre(b, c, m, sh)
    if b.blizz and c and m then
        if b.kind == "pv" then b:SetStatusBarColor(0, 1, 0) else b:SetStatusBarColor(0, 0, 1) end
    end
end

hooksecurefunc(ADB, "RafraichirJoueur", function()
    local f, d = ADBPlayerFrame, ADB.GetStatBlock(ADB.playerName)
    if not d or not f.Level then return end
    f.NameText:SetText(ADB.NomAffiche(ADB.playerName))
    f.Level:SetText(d.level)
end)

function ADB.RafraichirCible(rafraichirModele)
    local f = ADBTargetFrame
    if not ADB.db or not ADB.db.uiRemplacee or not f.Art then return end
    if not UnitExists("target") then
        f.charName, f.npcId = nil, nil
        f:Hide()
        return
    end
    f:Show()
    local nom, joueur = UnitName("target"), UnitIsPlayer("target")
    f.charName = joueur and nom or nil
    local p = (not joueur) and ADB.TrouverPNJNom(nom) or nil
    f.npcId = p and p.id or nil
    local d = f.charName and ADB.GetStatBlock(f.charName)
    local cl = UnitClassification("target")
    local niv, c = nil, nil
    if d then
        niv = d.level
    else
        local l = UnitLevel("target") or 0
        if cl == "worldboss" or l <= 0 then niv = "??" else niv = l end
        if l > 0 and cl ~= "worldboss" then c = GetQuestDifficultyColor(l) end
    end
    f.Art.Tex:SetTexture(ART_CIBLE[cl] or (TEX .. "UI-TargetingFrame"))
    f.NomFond:SetVertexColor(UnitSelectionColor("target"))
    f.NameText:SetText(d and ADB.NomAffiche(f.charName) or (p and ADB.PNJNom(p)) or nom or "")
    f.Level:SetText(niv)
    if c then f.Level:SetTextColor(c.r, c.g, c.b) else f.Level:SetTextColor(1, 0.82, 0) end
    Portrait(f, "target")
    local src = d or p
    ADB.MajBarre(f.HP, src and src.pv, src and src.pvMax, src and src.sh)
    ADB.MajBarre(f.MP, src and src.pm, src and src.pmMax)
    if not src then ADB.TexteEnnemi(f.HP) end
    f.FicheButton:SetShown(d ~= nil and f.charName ~= ADB.playerName and ADB.EstMJ())
end

local function PortraitsTous()
    Portrait(ADBPlayerFrame, "player")
    Portrait(ADBTargetFrame, "target")
    for _, b in ipairs(ADB.membres) do
        if b.unitToken then Portrait(b, b.unitToken) end
    end
end
hooksecurefunc(ADB, "MajModeles", PortraitsTous)

local function PlacerNPC()
    if ADB.db and ADB.db.uiRemplacee and ADBNpcFrame then
        ADBNpcFrame:ClearAllPoints()
        ADBNpcFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5, -(130 + ADB.nbLignes * PITCH + 8))
        for i, f in ipairs(ADB.pnjFrames) do
            if f:IsShown() then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", ADBNpcFrame, "TOPLEFT",floor((i - 1) / ADB.MEMBRES_PAR_COLONNE) * 123, -24 - ((i - 1) % ADB.MEMBRES_PAR_COLONNE) * PITCH)
            end
        end
    end
end
hooksecurefunc(ADB, "MiseEnPageNPC", PlacerNPC)
hooksecurefunc(ADB, "MiseEnPageGroupe", function()
    if not ADB.db or not ADB.db.uiRemplacee or InCombatLockdown() then return end
    for i, b in ipairs(ADB.membres) do
        if b:IsShown() then
            local col, lig = floor((i - 1) / ADB.MEMBRES_PAR_COLONNE), (i - 1) % ADB.MEMBRES_PAR_COLONNE
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ADBGroupFrame, "TOPLEFT", col * 219, -lig * PITCH)
        end
    end
    PlacerNPC()
    PortraitsTous()
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function()
    if ADB.db and ADB.db.uiRemplacee then PortraitsTous() end
end)

-- Clic sur le portrait d'un PNJ : /target [Nom Réel] (bouton sécurisé, utilisable en combat)
local ciblesEnAttente

local function MajCiblage()
    if InCombatLockdown() then
        ciblesEnAttente = true
        return
    end
    ciblesEnAttente = false
    local liste = ADB.ListerPNJ()
    for _, f in ipairs(ADB.pnjFrames) do
        local b = f.cibleBtn
        if f:IsShown() and f.npcId then
            local p
            for _, x in ipairs(liste) do
                if x.id == f.npcId then p = x break end
            end
            if p then
                if not b then
                    b = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
                    b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                    b:SetSize(44, 44)
                    b:RegisterForClicks("LeftButtonUp")
                    b:SetAttribute("type1", "macro")
                    b:SetFrameLevel(f:GetFrameLevel() + 6)
                    f.cibleBtn = b
                end
                b:SetAttribute("macrotext1", "/target " .. ADB.PNJNom(p))
                b:Show()
            elseif b then
                b:Hide()
            end
        elseif b then
            b:Hide()
        end
    end
end

hooksecurefunc(ADB, "MiseEnPageNPC", MajCiblage)
hooksecurefunc(ADB, "RafraichirNPC", MajCiblage)

local evc = CreateFrame("Frame")
evc:RegisterEvent("PLAYER_REGEN_ENABLED")
evc:SetScript("OnEvent", function() if ciblesEnAttente then MajCiblage() end end)

-- Portrait dynamique des PNJ : copie le portrait de l'unité visible, sinon garde le dernier connu (ou "?")
local PNJ_QM = "Interface\\Icons\\INV_Misc_QuestionMark"

local function UnitePNJ(nom)
    local function ok(u) return UnitExists(u) and not UnitIsPlayer(u) and UnitName(u) == nom and UnitIsVisible(u) end
    for _, u in ipairs({ "target", "focus", "mouseover" }) do
        if ok(u) then return u end
    end
    for i = 1, 40 do
        if ok("nameplate" .. i) then return "nameplate" .. i end
    end
    for _, u in ipairs(ADB.ListerUnites()) do
        if ok(u .. "target") then return u .. "target" end
    end
end

ADB.UnitePNJ = UnitePNJ

local function MajPortraitsPNJ()
    if not ADB.db or not ADB.pnjFrames then return end
    local liste = ADB.ListerPNJ()
    for _, f in ipairs(ADB.pnjFrames) do
        if f:IsShown() and f.npcId and f.Icon then
            if f.portId ~= f.npcId then          -- cadre réattribué à un autre PNJ : retour au "?"
                f.portId = f.npcId
                f.Icon:SetTexture(PNJ_QM)
                f.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end
            local p
            for _, x in ipairs(liste) do
                if x.id == f.npcId then p = x break end
            end
            local u = p and UnitePNJ(p.nom)
            if u then
                SetPortraitTexture(f.Icon, u)
                f.Icon:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
end

hooksecurefunc(ADB, "MiseEnPageNPC", MajPortraitsPNJ)
hooksecurefunc(ADB, "RafraichirNPC", MajPortraitsPNJ)

local evp = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do evp:RegisterEvent(e) end
evp:SetScript("OnEvent", MajPortraitsPNJ)
C_Timer.NewTicker(1, MajPortraitsPNJ)