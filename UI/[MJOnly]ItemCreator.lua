-- UI/ItemCreator.lua : GM item creation window (equipment, virtual consumables) and the narrative-item window.
local ADB, UI = ADB, ADB.UI
local floor = math.floor
local format = string.format
local Clamp, CleanName = ADB.Clamp, ADB.CleanName

local IC = {}
ADB.ItemCreator = IC

local function RarityText(i)
    local R = ADB.RARITIES[i]
    return "|cff" .. R.hex .. R.name .. "|r"
end

function IC.Refresh()
    local f = ADB.itemFrame
    if not f or not f.ready then return end
    local cap = ADB.RARITIES[f.rarity].statCap
    local total = 0
    for i = 1, 3 do total = total + (tonumber(f.Stats[i]:GetText()) or 0) end
    f.Total:SetText(format("Total : %s%d|r / %d", total > cap and "|cffff4040" or "|cff40ff40", total, cap))
    f.IconTexture:SetTexture(ADB.IconTexture(f.icon))
    local target = ADB.Group.GetTargetPlayer()
    f.TargetText:SetText("Cible : " .. (target and ADB.Stats.DisplayName(target) or "|cffff4040aucune|r"))
end

function IC.CreateEquipment()
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ peut créer des objets.")
        return
    end
    local f = ADB.itemFrame
    local name = CleanName(f.NameEdit:GetText())
    if name == "" then
        ADB.Print("Donnez un nom à l'objet.")
        return
    end
    local stats, total = {}, 0
    for i = 1, 3 do
        stats[i] = Clamp(floor(tonumber(f.Stats[i]:GetText()) or 0), 0, 12)
        total = total + stats[i]
    end
    local cap = ADB.RARITIES[f.rarity].statCap
    if total > cap then
        ADB.Print(format("Trop de points de stats pour cette rareté (max %d).", cap))
        return
    end
    local target = ADB.Group.GetTargetPlayer()
    if not target then
        ADB.Print("Ciblez un joueur possédant l'addon.")
        return
    end
    local it = ADB.Items.Validate({
        kind = "equip", slot = f.slot, rarity = f.rarity, stats = stats, icon = f.icon, name = name,
        skillsText = f.SkillsTextEdit:GetText(), skillIds = f.SkillIdsEdit:GetText(),
        tags = f.TagsEdit and f.TagsEdit:GetText() or "",
    })
    if it then ADB.Items.Send(target, it, 1) end
end

function IC.GiveConsumable(kind)
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ peut donner des objets.")
        return
    end
    local target = ADB.Group.GetTargetPlayer()
    if not target then
        ADB.Print("Ciblez un joueur possédant l'addon.")
        return
    end
    local qty = Clamp(floor(tonumber(ADB.itemFrame.QtyEdit:GetText()) or 1), 1, 20)
    ADB.Items.Send(target, { kind = kind }, qty)
end

function IC.Open()
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ (chef de groupe) peut créer des objets.")
        return
    end
    ADB.itemFrame:Show()
end

local function RarityDropdown(parent, name, x, y, get, set)
    local d = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(d, 150)
    UIDropDownMenu_Initialize(d, function(_, level)
        for i = 1, #ADB.RARITIES do
            local info = UIDropDownMenu_CreateInfo()
            info.text = RarityText(i)
            info.checked = (get() == i)
            info.func = function()
                set(i)
                UIDropDownMenu_SetText(d, RarityText(i))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(d, RarityText(get()))
    return d
end

function IC.Create()
    local f = UI.BaseWindow("ADBItemFrame", 320, 570, "Créer un objet")
    ADB.itemFrame = f
    f:SetPoint("CENTER", -300, 0)
    f.slot, f.rarity, f.icon = "arme", 1, "INV_Sword_04"

    UI.Label(f, "Emplacement", 20, -40)
    f.SlotDrop = CreateFrame("Frame", "ADBItemSlotDrop", f, "UIDropDownMenuTemplate")
    f.SlotDrop:SetPoint("TOPLEFT", 100, -33)
    UIDropDownMenu_SetWidth(f.SlotDrop, 150)
    UIDropDownMenu_Initialize(f.SlotDrop, function(_, level)
        for _, s in ipairs(ADB.EQUIP_SLOTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = s.label
            info.checked = (f.slot == s.key)
            info.func = function()
                f.slot = s.key
                UIDropDownMenu_SetText(f.SlotDrop, s.label)
                IC.Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(f.SlotDrop, ADB.SLOT_LABEL[f.slot])

    UI.Label(f, "Rareté", 20, -74)
    f.RarityDrop = RarityDropdown(f, "ADBItemRarDrop", 100, -67, function() return f.rarity end,
        function(i)
            f.rarity = i
            IC.Refresh()
        end)

    UI.Label(f, "Nom", 20, -112)
    f.NameEdit = UI.Input(f, 106, -109, 190, ADB.ITEM_NAME_MAX)

    UI.Label(f, "Icône", 20, -150)
    local ib = UI.IconButton(f, 106, -142, 36, function()
        ADB.Icons.Open(function(n)
            f.icon = tostring(n)
            IC.Refresh()
        end)
    end)
    f.IconTexture = ib.icon
    UI.Label(f, "(cliquer pour choisir)", 150, -152, "GameFontDisableSmall")

    f.Stats = {}
    for i = 1, 3 do
        UI.Label(f, ADB.STAT_LABELS[i], 20, -196 - (i - 1) * 26)
        local e = UI.Input(f, 124, -193 - (i - 1) * 26, 46, 2, true)
        e:SetText("0")
        e:SetScript("OnTextChanged", function() IC.Refresh() end)
        f.Stats[i] = e
    end
    f.Total = UI.Label(f, "", 190, -222)

    UI.Label(f, "Compétences (optionnel)", 20, -276)
    f.SkillsTextEdit = UI.Input(f, 24, -296, 268, ADB.ITEM_SKILLS_TEXT_MAX)

    f.TargetText = UI.Label(f, "", 20, -328)
    UI.Button(f, "Créer", 100, -350, 120, IC.CreateEquipment)

    UI.Label(f, "Objets virtuels  -  Qté", 20, -388, "GameFontNormalSmall")
    f.QtyEdit = UI.Input(f, 170, -385, 36, 2, true)
    f.QtyEdit:SetText("1")
    UI.Button(f, "Potion de Vie", 12, -412, 100, function() IC.GiveConsumable("potvie") end)
    UI.Button(f, "Potion de mana", 114, -412, 106, function() IC.GiveConsumable("potmana") end)
    UI.Button(f, "Ration", 222, -412, 80, function() IC.GiveConsumable("ration") end)
    UI.Label(f, "Skills d'équipement (IDs, ex: 3,7)", 20, -438, "GameFontNormalSmall")
    f.SkillIdsEdit = UI.Input(f, 24, -456, 268, 20)

    UI.Button(f, "Objet narratif...", 80, -484, 160, function()
        if not ADB.storyFrame then IC.CreateStoryWindow() end
        ADB.storyFrame:Show()
    end)
    UI.Label(f, "Tags (ex: dreadsteed, AddClassMage)", 20, -512, "GameFontNormalSmall")
    f.TagsEdit = UI.Input(f, 24, -530, 268, 600)

    f:SetScript("OnShow", IC.Refresh)
    f:SetScript("OnHide", function() ADB.iconFrame:Hide() end)
    f.ready = true
    IC.Refresh()
end

------------------------------------------------------------------------------
-- Narrative item window
------------------------------------------------------------------------------
function IC.CreateStoryWindow()
    local f = UI.BaseWindow("ADBStoryFrame", 320, 340, "Objet narratif")
    ADB.storyFrame = f
    f:SetPoint("CENTER", -300, 0)
    tinsert(UISpecialFrames, "ADBStoryFrame")
    f.icon, f.rarity = "INV_Misc_Note_01", 1

    UI.Label(f, "Nom", 20, -40)
    f.NameEdit = UI.Input(f, 80, -37, 210, ADB.ITEM_NAME_MAX)
    UI.Label(f, "Icône", 20, -76)
    local ib = UI.IconButton(f, 80, -68, 36, function()
        ADB.Icons.Open(function(v)
            f.icon = ADB.SanitizeIcon(v)
            f.IconTexture:SetTexture(ADB.IconTexture(f.icon))
        end)
    end)
    f.IconTexture = ib.icon
    f.IconTexture:SetTexture(ADB.IconTexture(f.icon))

    UI.Label(f, "Rareté", 124, -78)
    f.RarityDrop = RarityDropdown(f, "ADBStoryRarDrop", 150, -69, function() return f.rarity end,
        function(i) f.rarity = i end)
    UIDropDownMenu_SetWidth(f.RarityDrop, 90)

    UI.Label(f, "Description", 20, -118)
    f.DescEdit = UI.MultilineInput(f, 20, -136, 280, 100, 200)
    UI.Label(f, "Tags", 20, -250)
    f.TagsEdit = UI.Input(f, 60, -247, 240, 600)

    UI.Button(f, "Donner à la cible", 20, -290, 140, function()
        if not ADB.IsGM() then return end
        local name = CleanName(f.NameEdit:GetText())
        if name == "" then
            ADB.Print("Donnez un nom à l'objet.")
            return
        end
        local target = ADB.Group.GetTargetPlayer()
        if not target then
            ADB.Print("Ciblez un joueur possédant l'addon.")
            return
        end
        local it = ADB.Items.Validate({ kind = "story", rarity = f.rarity, icon = f.icon, name = name,
            desc = f.DescEdit:GetText(), tags = f.TagsEdit:GetText() })
        if not it then return end
        if target == ADB.playerName then
            ADB.Items.Receive(it, 1)
        else
            ADB.Gifts.Send(target, it)
            ADB.Print(format("%s envoyé à %s.", ADB.Items.ColoredName(it), ADB.Stats.DisplayName(target)))
        end
    end)
    f:SetScript("OnHide", function() if ADB.iconFrame then ADB.iconFrame:Hide() end end)
end