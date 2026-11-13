-- UI/BuffUI.lua : buff icons (player / target), GM buff definition window, "Buff ID" field in the talent editor.
local ADB, UI = ADB, ADB.UI
local Buffs = ADB.Buffs
local T = Buffs.TYPE
local floor = math.floor
local format = string.format

local BU = {}
ADB.BuffUI = BU

local function IsGood(b) return b.buffType == T.HEAL or b.buffType == T.WRATH or b.buffType == T.ADVANTAGE end

local function Describe(b)
    local t = b.buffType
    if b.desc and b.desc ~= "" then return b.desc end
    if t == T.DAMAGE then
        return format("Inflige %d dégâts par tour.", b.value)
    elseif t == T.HEAL then
        return format("Rend %d PV par tour.", b.value)
    elseif t == T.ROOT then
        return "Immobilisation : bloque tout déplacement."
    elseif t == T.STUN then
        return "Étourdissement : empêche toute action."
    elseif t == T.SILENCE then
        return "Silence."
    elseif t == T.ADVANTAGE then
        return "Avantage : jets de précision lancés 2 fois, le meilleur est gardé."
    elseif t == T.DISADVANTAGE then
        return "Désavantage : jets de précision lancés 2 fois, le pire est gardé."
    end
    return "+50% de dégâts, +5 de précision et +5% de coup critique (joueur et familier)."
end

local function ShowTooltip(ic)
    local b = ic.b
    if not b then return end
    local good = IsGood(b)
    GameTooltip:SetOwner(ic, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(b.name, good and 0.3 or 1, good and 1 or 0.3, 0.3)
    GameTooltip:AddLine(Describe(b), 1, 1, 1, true)
    GameTooltip:AddLine(format("Tours restants : %d", b.left), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function CreateIcon(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- dir: 1 = grows right, -1 = grows left
local function UpdateRow(c, list, size, perRow, dir)
    c.btns = c.btns or {}
    list = list or {}
    for i, b in ipairs(list) do
        local ic = c.btns[i]
        if not ic then
            ic = CreateIcon(c, size)
            c.btns[i] = ic
        end
        local col, row = (i - 1) % perRow, floor((i - 1) / perRow)
        local point = dir > 0 and "TOPLEFT" or "TOPRIGHT"
        ic:ClearAllPoints()
        ic:SetPoint(point, c, point, dir * col * (size + 3), -row * (size + 3))
        ic.b = b
        ic.tex:SetTexture(ADB.IconTexture(b.icon))
        ic.count:SetText(b.left)
        if IsGood(b) then ic.border:SetColorTexture(0.1, 0.7, 0.1, 1) else ic.border:SetColorTexture(0.8, 0.1, 0.1, 1) end
        ic:Show()
    end
    for i = #list + 1, #c.btns do
        c.btns[i]:Hide()
        c.btns[i].b = nil
    end
end

function BU.Refresh()
    if not ADB.playerName then return end
    if ADB.buffAnchor then UpdateRow(ADB.buffAnchor, Buffs.active["P:" .. ADB.playerName], 30, 8, -1) end
    if ADB.buffTarget then
        local k = Buffs.UnitKey("target")
        UpdateRow(ADB.buffTarget, k and Buffs.active[k], 22, 8, 1)
    end
end

hooksecurefunc(ADB.UnitFrames, "RefreshTarget", function() BU.Refresh() end)
hooksecurefunc(BU, "Refresh", function() ADB.ActionBar.Refresh() end)

------------------------------------------------------------------------------
-- GM window
------------------------------------------------------------------------------
function BU.RefreshWindow()
    local f = ADB.bufFrame
    if not f or not f:IsShown() then return end
    f.IconTexture:SetTexture(ADB.IconTexture(f.icon))
    UIDropDownMenu_SetText(f.TypeDrop, Buffs.LABELS[f.buffType])
    f.Btn:SetText(f.editId and "Enregistrer" or "Créer")
    local defs = ADB.db.buffDefs
    for i, r in ipairs(f.rows) do
        local d = defs[i]
        r.id = d and d.id
        for _, w in ipairs({ r.ic, r.txt, r.edit, r.apply, r.del }) do w:SetShown(d ~= nil) end
        if d then
            r.ic:SetTexture(ADB.IconTexture(d.icon))
            r.txt:SetText(format("#%d %s |cffaaaaaa(%s, %dt%s)|r", d.id, d.name, Buffs.LABELS[d.buffType], d.duration,
                d.buffType <= 2 and (", " .. d.value) or ""))
        end
    end
end

function BU.ToggleWindow()
    local f = ADB.bufFrame
    if f:IsShown() then f:Hide() else f:Show() end
end

local MAX_DEFS = 12
local function CreateWindow()
    local f = UI.BaseWindow("ADBBuffMJFrame", 380, 526, "Buffs / Debuffs (MJ)")
    ADB.bufFrame = f
    f:SetPoint("CENTER", -300, 0)
    tinsert(UISpecialFrames, "ADBBuffMJFrame")
    f.icon, f.buffType = "INV_Misc_QuestionMark", 1

    UI.Label(f, "Nom", 16, -40)
    f.Name = UI.Input(f, 70, -37, 170, 24)
    UI.Label(f, "Icône", 16, -76)
    local ib = UI.IconButton(f, 70, -66, 32, function()
        ADB.Icons.Open(function(v)
            f.icon = ADB.SanitizeIcon(v)
            BU.RefreshWindow()
        end)
    end)
    f.IconTexture = ib.icon
    UI.Label(f, "Durée (tours)", 130, -76)
    f.Duration = UI.Input(f, 230, -73, 40, 2, true)
    f.Duration:SetText("3")

    UI.Label(f, "Type", 16, -116)
    f.TypeDrop = CreateFrame("Frame", "ADBBuffTypeDrop", f, "UIDropDownMenuTemplate")
    f.TypeDrop:SetPoint("TOPLEFT", 50, -109)
    UIDropDownMenu_SetWidth(f.TypeDrop, 160)
    UIDropDownMenu_Initialize(f.TypeDrop, function(_, level)
        for i, t in ipairs(Buffs.LABELS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = t, (f.buffType == i)
            info.func = function()
                f.buffType = i
                BU.RefreshWindow()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UI.Label(f, "Valeur", 16, -150)
    f.Value = UI.Input(f, 70, -147, 50, 3, true)
    f.Value:SetText("3")
    UI.Label(f, "Tags", 16, -176)
    f.Tags = UI.Input(f, 70, -173, 280, 600)

    local function Reset()
        f.editId = nil
        f.Name:SetText("")
        f.Tags:SetText("")
        f.Desc:SetText("")
        BU.RefreshWindow()
    end
    f.Btn = UI.Button(f, "Créer", 150, -147, 100, function()
        if Buffs.CreateDef(f.Name:GetText(), f.icon, tonumber(f.Duration:GetText()) or 1, f.buffType,
                tonumber(f.Value:GetText()) or 0, f.Tags:GetText(), f.editId, f.Desc:GetText()) then
            Reset()
        end
    end)
    UI.Button(f, "Nouveau", 256, -147, 90, Reset)
    UI.Label(f, "Texte", 16, -202)
    f.Desc = UI.Input(f, 70, -199, 280, 100)
    UI.Label(f, "ID à saisir dans l'éditeur de talents pour lier un debuff.", 16, -226, "GameFontDisableSmall")

    f.rows = {}
    for i = 1, MAX_DEFS do
        local y, r = -244 - (i - 1) * 22, {}
        r.ic = f:CreateTexture(nil, "ARTWORK")
        r.ic:SetSize(18, 18)
        r.ic:SetPoint("TOPLEFT", 16, y - 2)
        r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.txt = UI.Label(f, "", 40, y - 5, "GameFontHighlightSmall")
        r.txt:SetWidth(150)
        r.txt:SetWordWrap(false)
        r.edit = UI.Button(f, "Éditer", 194, y, 52, function()
            local d = r.id and Buffs.GetDef(r.id)
            if not d then return end
            f.editId, f.icon, f.buffType = d.id, d.icon, d.buffType
            f.Name:SetText(d.name)
            f.Duration:SetText(d.duration)
            f.Value:SetText(d.value)
            f.Desc:SetText(d.desc or "")
            f.Tags:SetText(table.concat(d.tags or {}, ","))
            BU.RefreshWindow()
        end)
        r.apply = UI.Button(f, "Appliquer", 248, y, 70, function() Buffs.ForceApply(r.id) end)
        r.del = UI.Button(f, "X", 322, y, 28, function() Buffs.DeleteDef(r.id) end)
        f.rows[i] = r
    end
    f:SetScript("OnShow", BU.RefreshWindow)
end

function BU.Create()
    local a = CreateFrame("Frame", "ADBBuffAnchor", UIParent)
    a:SetSize(260, 40)
    a:SetFrameStrata("LOW")
    a:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -215, -14)
    ADB.buffAnchor = a
    local t = CreateFrame("Frame", nil, ADBTargetFrame)
    t:SetSize(190, 24)
    t:SetPoint("TOPLEFT", ADBTargetFrame, "BOTTOMLEFT", 4, -18)
    ADB.buffTarget = t
    CreateWindow()
    UI.Button(ADBMJFrame, "Buffs / Debuffs", 155, -220, 125, function() Buffs.SlashCommand("") end)
end

ADB.Events.Register("PLAYER_LOGIN", BU.Create)

------------------------------------------------------------------------------
-- Talent editor: "Buff ID" field (active talents)
------------------------------------------------------------------------------
local function SelectedNode()
    local f = ADB.talFrame
    local a = f and ADB.Talents.GetTree(ADB.Talents.viewClass)
    return a and f.sel and a.nodes[f.sel] or nil
end

hooksecurefunc(ADB.TalentWindow, "Create", function()
    local A = ADB.talFrame.Ed.C.Active
    UI.Label(A, "Buff ID", 138, -4)
    local e = UI.Input(A, 190, -1, 50, 4, true)
    e:SetScript("OnTextChanged", function(self, user)
        local n = SelectedNode()
        if user and n and ADB.Talents.CanEdit() then
            n.buffId = ADB.Clamp(floor(tonumber(self:GetText()) or 0), 0, 9999)
            ADB.TalentNet.ScheduleNode(ADB.Talents.ClassIndex(ADB.Talents.viewClass), n.id)
        end
    end)
    ADB.talFrame.Ed.C.BuffId = e
end)

hooksecurefunc(ADB.TalentWindow, "UpdatePanel", function()
    local f, n = ADB.talFrame, SelectedNode()
    local e = f and f.Ed.C.BuffId
    if e and n and f.edition and not e:HasFocus() then e:SetText((n.buffId or 0) > 0 and n.buffId or "") end
end)
