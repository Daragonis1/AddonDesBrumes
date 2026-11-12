-- UI/PetUI.lua : "Personnage secondaire" menu (pet type or alt character) and the pet skill bar.
local ADB, UI = ADB, ADB.UI
local Pets = ADB.Pets
local format = string.format
local CleanName = ADB.CleanName

local PU = {}
ADB.PetUI = PU

------------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------------
function PU.UpdateMenu()
    local f = ADB.petMenu
    if not f then return end
    if f.type == ADB.ALT_TYPE then
        UIDropDownMenu_SetText(f.Drop, f.type)
        f.Info:SetText("")
        return
    end
    local T = ADB.PET_TYPES[f.type]
    UIDropDownMenu_SetText(f.Drop, f.type)
    local hp, mp = Pets.MaxStats(f.type)
    local m, lines = Pets.Multiplier(T), { format("|cffffd100PV|r %d   |cffffd100PM|r %d", hp, mp) }
    for _, sk in ipairs(T.skills) do
        lines[#lines + 1] = format("|cffffd100%s|r%s : %s", sk.name, sk.mana > 0 and (" (" .. sk.mana .. " PM)") or "",
            (ADB.Talents.FormatDescription(sk.desc, true, m, 0)))
    end
    f.Info:SetText(table.concat(lines, "\n"))
end

function PU.Save()
    local f = ADB.petMenu
    local name = CleanName(f.Name:GetText()):sub(1, 30)
    if name == "" then
        ADB.Print("Donnez un nom de PNJ.")
        return
    end
    local rp = CleanName(f.RP:GetText()):sub(1, 40)
    if f.type == ADB.ALT_TYPE then return ADB.Alt.Save(name, rp, f.altRace, f.altClass) end
    if ADB.altChar then ADB.Alt.Delete(true) end
    ADB.db.secondary = { type = f.type, name = name, rpName = rp }
    Pets.Sync(true)
    ADB.Print(IsInGroup() and "Personnage secondaire enregistré (envoyé au MJ)."
        or "Enregistré : envoyé au MJ dès que vous serez en groupe.")
    f:Hide()
end

function PU.Delete()
    if ADB.altChar then
        ADB.Alt.Delete()
        ADB.petMenu:Hide()
        return
    end
    if IsInGroup() and Pets.GetPet() then ADB.Net.Send("PD") end
    ADB.db.secondary = nil
    Pets.ResetSync()
    ADB.petMenu:Hide()
    ADB.Print("Personnage secondaire supprimé.")
end

function PU.ToggleMenu()
    if ADB.IsGM() then
        ADB.Print("Réservé aux joueurs.")
        return
    end
    local f = ADB.petMenu
    if not f then
        f = UI.BaseWindow("ADBPetMenu", 300, 250, "Personnage secondaire")
        ADB.petMenu = f
        f:SetPoint("CENTER", -250, 0)
        tinsert(UISpecialFrames, "ADBPetMenu")
        UI.Label(f, "Nom du PNJ", 16, -40)
        f.Name = UI.Input(f, 120, -37, 160, 30)
        UI.Label(f, "(nom en jeu, sert au ciblage)", 16, -60, "GameFontDisableSmall")
        UI.Label(f, "Nom RP", 16, -84)
        f.RP = UI.Input(f, 120, -81, 160, 40)
        UI.Label(f, "Type", 16, -116)
        f.Drop = CreateFrame("Frame", "ADBPetTypeDrop", f, "UIDropDownMenuTemplate")
        f.Drop:SetPoint("TOPLEFT", 90, -109)
        UIDropDownMenu_SetWidth(f.Drop, 150)
        UIDropDownMenu_Initialize(f.Drop, function(_, level)
            for _, t in ipairs(ADB.PET_ORDER) do
                local i = UIDropDownMenu_CreateInfo()
                i.text, i.checked = t, (f.type == t)
                i.func = function()
                    f.type = t
                    PU.UpdateMenu()
                end
                UIDropDownMenu_AddButton(i, level)
            end
        end)
        f.Info = UI.Label(f, "", 16, -148, "GameFontHighlightSmall")
        f.Info:SetWidth(268)
        f.Info:SetJustifyV("TOP")
        UI.Button(f, "Enregistrer", 16, -214, 125, function() PU.Save() end)
        UI.Button(f, "Supprimer", 159, -214, 125, function() PU.Delete() end)
    end
    if f:IsShown() then
        f:Hide()
        return
    end
    local s = ADB.db.secondary
    f.Name:SetText(s and s.name or "")
    f.RP:SetText(s and s.rpName or "")
    f.type = s and s.type or ADB.PET_ORDER[1]
    f:Show()
    PU.UpdateMenu()
end

------------------------------------------------------------------------------
-- Pet skill bar
------------------------------------------------------------------------------
local function CreateButton(i)
    local b = CreateFrame("Button", nil, ADB.petBar)
    b:SetSize(28, 28)
    b:SetPoint("TOPLEFT", 8 + (i - 1) * 31, -8)
    b.i = i
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.dark = b:CreateTexture(nil, "OVERLAY")
    b.dark:SetAllPoints()
    b.dark:SetColorTexture(0, 0, 0, 0.55)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self) Pets.UseSkill(self.i) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnEnter", function(self)
        local p = Pets.GetPet()
        local sk = p and Pets.Skills(p)[self.i]
        if not sk then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(sk.name, 1, 0.82, 0)
        GameTooltip:AddLine("Précision : " .. sk.accuracy, 1, 1, 1)
        if sk.mana > 0 then GameTooltip:AddLine("Coût : " .. sk.mana .. " Mana (familier)", 0.3, 0.55, 1) end
        GameTooltip:AddLine((ADB.Talents.FormatDescription(sk.desc, true, Pets.Multiplier(ADB.PET_TYPES[p.petType]), 0)),
            1, 0.9, 0.6, true)
        local ok, reason = Pets.GetState(p, sk)
        if not ok then GameTooltip:AddLine(reason, 1, 0.2, 0.2, true) end
        GameTooltip:Show()
    end)
    ADB.petBar.btns[i] = b
    return b
end

function PU.Refresh()
    local bar = ADB.petBar
    if not bar or not ADB.db or not ADB.playerName then return end
    local p = Pets.GetPet()
    ADB.UnitFrames.RefreshMinis()
    local list = p and Pets.Skills(p) or {}
    if #list == 0 or ADB.IsGM() or ADB.phase == "IDLE" then
        bar:Hide()
        return
    end
    bar:ClearAllPoints()
    if ADB.actionBar then bar:SetPoint("BOTTOM", ADB.actionBar, "TOP", 0, 6)
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 210) end
    bar:SetSize(#list * 31 + 13, 44)
    for i, sk in ipairs(list) do
        local b = bar.btns[i] or CreateButton(i)
        local ok = Pets.GetState(p, sk)
        b.tex:SetTexture(ADB.IconTexture(sk.icon))
        b.tex:SetDesaturated(not ok)
        b.dark:SetShown(not ok)
        b:Show()
    end
    for i = #list + 1, #bar.btns do bar.btns[i]:Hide() end
    bar:Show()
end

function PU.Create()
    local bar = CreateFrame("Frame", "ADBPetBar", UIParent, "BackdropTemplate")
    bar:SetSize(100, 44)
    bar:SetFrameStrata("MEDIUM")
    UI.ApplyBackdrop(bar)
    bar.btns = {}
    bar:Hide()
    ADB.petBar = bar
end