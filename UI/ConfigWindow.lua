-- UI/ConfigWindow.lua : own character window ("Ma fiche": RP name, race, class, derived stats) and the
-- read-only character sheet window (GM inspects a player). Frames are declared in Templates.xml.
local ADB = ADB
local format = string.format

local CW = {}
ADB.ConfigWindow = CW

function CW.Toggle()
    if ADBConfigFrame:IsShown() then ADBConfigFrame:Hide() else ADBConfigFrame:Show() end
end

-- XML: OnEnterPressed / OnEditFocusLost
function CW.OnRpNameEdit(edit)
    ADB.Stats.SetRpName(edit:GetText())
    edit:SetText(ADB.db.rpName or "")
end

-- XML: OnEscapePressed
function CW.OnRpNameEscape(edit)
    edit:SetText(ADB.db.rpName or "")
    edit:ClearFocus()
end

local function InitList(drop, list, key, setter)
    UIDropDownMenu_SetWidth(drop, 150)
    UIDropDownMenu_Initialize(drop, function(_, level)
        for _, entry in ipairs(list) do
            if not ADB.IsSpecialClass(entry.name) then
                local info = UIDropDownMenu_CreateInfo()
                info.text = entry.name
                info.checked = (ADB.db[key] == entry.name)
                info.func = function() setter(entry.name) end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
end

function CW.InitDropdowns()
    local f = ADBConfigFrame
    InitList(f.RaceDrop, ADB.RACES, "race", ADB.Stats.SetRace)
    InitList(f.ClassDrop, ADB.CLASSES, "class", ADB.Stats.SetClass)
end

function CW.Refresh()
    local f = ADBConfigFrame
    if not f or not f:IsShown() or not ADB.db then return end
    local d = ADB.Stats.GetBlock(ADB.playerName)

    if not f.RpNameEdit:HasFocus() then f.RpNameEdit:SetText(ADB.db.rpName or "") end
    UIDropDownMenu_SetText(f.RaceDrop, ADB.db.race)
    UIDropDownMenu_SetText(f.ClassDrop, ADB.db.class)

    local role
    if not IsInGroup() then role = "Hors groupe"
    elseif ADB.IsGM() then role = "|cffffd100MJ (chef de groupe)|r"
    else role = "Joueur" end

    local xp
    if d.level >= ADB.MAX_LEVEL then
        xp = format("%d (niveau max)", d.xp)
    else
        xp = format("%d / %d", d.xp, ADB.XP_THRESHOLDS[d.level + 1])
    end

    f.Derived:SetText(format(
        "|cffffd100Rôle|r : %s\n\n" ..
        "|cffffd100Niveau|r : %d    |cffffd100XP|r : %s\n\n" ..
        "|cffffd100Or|r : %s\n\n" ..
        "Force : %d   Agilité : %d   Intelligence : %d\n\n" ..
        "|cffff5050PV max|r : %d    (actuels : %d)\n" ..
        "|cff5080ffPM max|r : %d    (actuels : %d)\n\n" ..
        "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f",
        role, d.level, xp, ADB.FormatMoney(d.copper), d.strength, d.agility, d.intellect,
        d.maxHp, d.hp, d.maxMp, d.mp, d.strengthMult, d.agilityMult, d.intellectMult))

    -- Buttons stacked from the bottom: shared first, then GM-only or player-only
    local isGM = ADB.IsGM()
    local gmButtons = { f.ItemButton, f.GmButton, f.NpcButton, f.TargetSheetButton }
    local list = { f.TalentButton, f.InventoryButton }
    f.PetButton:SetShown(not isGM)
    if not isGM then list[#list + 1] = f.PetButton end
    for _, b in ipairs(gmButtons) do
        b:SetShown(isGM)
        if isGM then list[#list + 1] = b end
    end
    local n = #list
    for i, b in ipairs(list) do
        b:ClearAllPoints()
        b:SetPoint("BOTTOM", f, "BOTTOM", 0, 20 + (n - i) * 28)
    end
    f:SetHeight(430 + (n - 1) * 28)
end

------------------------------------------------------------------------------
-- Read-only sheet (ADBFicheFrame)
------------------------------------------------------------------------------
function CW.OpenSheet(name)
    ADBFicheFrame.displayName = name
    ADBFicheFrame:Show()
    CW.RefreshSheet()
end

function CW.RefreshSheet()
    local f = ADBFicheFrame
    if not f or not f:IsShown() or not f.displayName then return end
    local d = ADB.Stats.GetBlock(f.displayName)
    if not d then
        f.Body:SetText("Aucune donnée reçue pour " .. f.displayName .. ".")
        return
    end
    local title = ADB.Stats.DisplayName(d.name)
    if title ~= d.name then title = title .. " |cff999999(" .. d.name .. ")|r" end
    local race = (d.race and d.race ~= "") and d.race or "?"
    local class = (d.class and d.class ~= "") and d.class or "?"
    f.Body:SetText(format(
        "|cff9d6bff%s|r\n\n" ..
        "|cffffd100Race|r : %s\n|cffffd100Classe|r : %s\n|cffffd100Niveau|r : %d    |cffffd100XP|r : %d\n" ..
        "|cffffd100Or|r : %s\n\n" ..
        "|cffffd100Force|r : %d\n|cffffd100Agilité|r : %d\n|cffffd100Intelligence|r : %d\n\n" ..
        "|cffff5050PV|r : %d / %d\n|cff5080ffPM|r : %d / %d\n\n" ..
        "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f",
        title, race, class, d.level, d.xp, ADB.FormatMoney(d.copper), d.strength, d.agility, d.intellect,
        d.hp, d.maxHp, d.mp, d.maxMp, d.strengthMult, d.agilityMult, d.intellectMult))
end

function CW.ViewTargetSheet()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        ADB.Print("Ciblez d'abord un joueur.")
        return
    end
    local name = UnitName("target")
    if name ~= ADB.playerName and not ADB.IsGM() then
        ADB.Print("Seul le MJ peut consulter la fiche des autres joueurs.")
        return
    end
    if not ADB.Stats.GetBlock(name) then
        ADB.Print("Aucune fiche reçue pour " .. name .. " (a-t-il l'addon ?). Nouvelle demande envoyée.")
        ADB.Sync.ScheduleBroadcast(true)
        return
    end
    CW.OpenSheet(name)
end