------------------------------------------------------------------------------
-- Icones.lua : helpers UI partages (ADB.UI) + selecteur de TOUTES les icones
------------------------------------------------------------------------------
local ADB = ADB
local floor, max, min = math.floor, math.max, math.min
local format = string.format

ADB.UI = {}
local UI = ADB.UI

function UI.Etiq(parent, txt, x, y, police)
    local s = parent:CreateFontString(nil, "ARTWORK", police or "GameFontHighlight")
    s:SetPoint("TOPLEFT", x, y)
    s:SetJustifyH("LEFT")
    s:SetText(txt)
    return s
end

function UI.Saisie(parent, x, y, w, lettres, num)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetMaxLetters(lettres)
    if num then e:SetNumeric(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

function UI.Bouton(parent, txt, x, y, w, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(txt)
    b:SetScript("OnClick", fn)
    return b
end

function UI.FenetreBase(nom, w, h, titre)
    local f = CreateFrame("Frame", nom, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText(titre) end
    f:Hide()
    return f
end

function ADB.IconeTex(icon)
    if tonumber(icon) then return tonumber(icon) end
    return "Interface\\Icons\\" .. icon
end

------------------------------------------------------------------------------
-- Base d'icones du jeu (chargee a la premiere ouverture)
------------------------------------------------------------------------------
local PAR_PAGE, COLS = 56, 8
local liste, noms, cache = nil, nil, {}

local function NomPropre(s)
    s = tostring(s or ""):gsub("^.*[\\/]", ""):gsub("%.%w+$", "")
    return s
end

local function Charger()
    if liste then return end
    liste, noms = {}, {}
    local vus, brut = {}, {}
    local lire = C_Texture and C_Texture.GetFilenameFromFileDataID
    for _, nomFn in ipairs({ "GetLooseMacroIcons", "GetLooseMacroItemIcons",
                             "GetMacroIcons", "GetMacroItemIcons" }) do
        local fn = _G[nomFn]
        if fn then
            wipe(brut)
            pcall(fn, brut)
            for _, v in ipairs(brut) do
                local nom = ""
                if type(v) == "string" then
                    nom = NomPropre(v)
                elseif lire then
                    local ok, r = pcall(lire, v)
                    if ok and r then nom = NomPropre(r) end
                end
                local cle = (nom ~= "") and nom:lower() or tostring(v)
                if not vus[cle] then
                    vus[cle] = true
                    liste[#liste + 1] = (type(v) == "string") and nom or v
                    noms[#noms + 1] = nom:lower()
                end
            end
        end
    end
end

local function Filtrer(txt)
    txt = (txt or ""):lower():gsub("%s+", "")
    if txt == "" then return liste end
    if cache.txt == txt then return cache.res end
    local res
    if txt:match("^%d+$") then
        res = { tonumber(txt) }
    else
        res = {}
        for i = 1, #noms do
            if noms[i]:find(txt, 1, true) then res[#res + 1] = liste[i] end
        end
    end
    cache.txt, cache.res = txt, res
    return res
end

function ADB.RafraichirIcones()
    local f = ADB.iconFrame
    if not f then return end
    Charger()
    local res = Filtrer(f.Filtre:GetText())
    local pages = max(1, math.ceil(#res / PAR_PAGE))
    f.page = max(1, min(f.page, pages))
    for i, b in ipairs(f.btns) do
        local v = res[(f.page - 1) * PAR_PAGE + i]
        b.nom = v
        if v ~= nil then
            b.tex:SetTexture(ADB.IconeTex(v))
            b:Show()
        else
            b:Hide()
        end
    end
    f.maj = true
    f.Slider:SetMinMaxValues(1, max(2, pages))
    f.Slider:SetValue(f.page)
    f.maj = false
    f.PageTxt:SetText(format("%d / %d  (%d icônes)", f.page, pages, #res))
end

function ADB.CreerFenetreIcones()
    local f = UI.FenetreBase("ADBIconFrame", 360, 440, "Choisir une icône")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    ADB.iconFrame = f
    f:SetPoint("CENTER", 0, 0)
    f.page = 1
    UI.Etiq(f, "Recherche", 16, -34, "GameFontNormalSmall")
    f.Filtre = UI.Saisie(f, 80, -31, 180, 40)
    f.Filtre:SetScript("OnTextChanged", function() f.page = 1; ADB.RafraichirIcones() end)
    UI.Etiq(f, "(nom ou ID)", 268, -34, "GameFontDisableSmall")

    f.btns = {}
    for i = 1, PAR_PAGE do
        local col, lig = (i - 1) % COLS, floor((i - 1) / COLS)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(38, 38)
        b:SetPoint("TOPLEFT", 16 + col * 42, -62 - lig * 42)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self)
            if self.nom ~= nil then
                local cb = f.cb
                f:Hide()
                if cb then cb(self.nom) end
            end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tostring(self.nom or ""), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.btns[i] = b
    end

    local s = CreateFrame("Slider", "ADBIconSlider", f, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 20, -372)
    s:SetSize(320, 16)
    s:SetMinMaxValues(1, 2)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    _G["ADBIconSliderLow"]:SetText("")
    _G["ADBIconSliderHigh"]:SetText("")
    _G["ADBIconSliderText"]:SetText("")
    s:SetScript("OnValueChanged", function(self, v)
        if f.maj then return end
        f.page = floor(v + 0.5)
        ADB.RafraichirIcones()
    end)
    f.Slider = s

    UI.Bouton(f, "<<", 16, -398, 40, function() f.page = f.page - 10; ADB.RafraichirIcones() end)
    UI.Bouton(f, "<", 60, -398, 40, function() f.page = f.page - 1; ADB.RafraichirIcones() end)
    f.PageTxt = UI.Etiq(f, "", 112, -402, "GameFontHighlightSmall")
    UI.Bouton(f, ">", 260, -398, 40, function() f.page = f.page + 1; ADB.RafraichirIcones() end)
    UI.Bouton(f, ">>", 304, -398, 40, function() f.page = f.page + 10; ADB.RafraichirIcones() end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        self.page = self.page - delta
        ADB.RafraichirIcones()
    end)
    f:SetScript("OnShow", function() ADB.RafraichirIcones() end)
end

function ADB.OuvrirIcones(callback)
    if not ADB.iconFrame then ADB.CreerFenetreIcones() end
    ADB.iconFrame.cb = callback
    ADB.iconFrame:Show()
    ADB.iconFrame:Raise()
end