-- UI/InventoryWindow.lua : inventory window (equipment slots, 16 bag slots, money, destroy).
-- Alt.lua / Gifts.lua / EquipmentSkills.lua extend it through ADB.Wrap / hooksecurefunc on these functions;
-- every internal call therefore goes through the IW table.
local ADB, UI = ADB, ADB.UI
local floor, min = math.floor, math.min
local format = string.format

local IW = {}
ADB.InventoryWindow = IW
ADB.selection = nil   -- { zone, key } of the selected slot

local function CreateSlot(parent, zone, key, x, y, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetPoint("TOPLEFT", x, y)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.label:SetPoint("CENTER")
    b.highlight = b:CreateTexture(nil, "OVERLAY")
    b.highlight:SetAllPoints()
    b.highlight:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.highlight:SetBlendMode("ADD")
    b.highlight:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.zone, b.key = zone, key
    b:SetScript("OnClick", function(self, button) IW.OnSlotClick(self, button) end)
    b:SetScript("OnEnter", function(self) IW.SlotTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function UpdateSlot(b)
    local it = ADB.Items.GetAt(b.zone, b.key)
    local selected = ADB.selection and ADB.selection.zone == b.zone and ADB.selection.key == b.key
    b.highlight:SetShown(selected and true or false)
    if it then
        local _, tex, r, g, bl = ADB.Items.Info(it)
        b.bg:SetColorTexture(r, g, bl, 1)
        b.icon:SetTexture(tex)
        b.icon:Show()
        b.label:SetText("")
        b.count:SetText((it.count and it.count > 1) and it.count or "")
    else
        b.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        b.icon:Hide()
        b.count:SetText("")
        b.label:SetText(b.zone == "eq" and ADB.SLOT_LABEL[b.key] or "")
    end
end

function IW.Create()
    local f = UI.BaseWindow("ADBInvFrame", 340, 420, "Inventaire")
    ADB.invFrame = f
    f:SetPoint("CENTER", 300, 0)
    f.slots = {}
    for k, s in ipairs(ADB.EQUIP_SLOTS) do
        f.slots[#f.slots + 1] = CreateSlot(f, "eq", s.key, 28 + (k - 1) * 60, -38, 44)
    end
    for i = 1, ADB.INV_SLOTS do
        local col, row = (i - 1) % 4, floor((i - 1) / 4)
        f.slots[#f.slots + 1] = CreateSlot(f, "inv", i, 70 + col * 52, -100 - row * 52, 44)
    end
    f.Money = UI.Label(f, "", 20, -312)
    f.TargetText = UI.Label(f, "", 20, -330, "GameFontNormalSmall")
    f.Gold = UI.Input(f, 28, -352, 46, 4, true)
    UI.Label(f, "Po", 82, -355)
    f.Silver = UI.Input(f, 124, -352, 46, 4, true)
    UI.Label(f, "Pa", 178, -355)
    f.Copper = UI.Input(f, 220, -352, 46, 4, true)
    UI.Label(f, "Pc", 274, -355)
    f.AddBtn = UI.Button(f, "Ajouter (MJ)", 16, -382, 100, function() IW.ClickMoney(true) end)
    f.RemoveBtn = UI.Button(f, "Retirer", 120, -382, 96, function() IW.ClickMoney(false) end)
    f.DestroyBtn = UI.Button(f, "Détruire", 220, -382, 100, function() IW.ClickDestroy() end)
    f:SetScript("OnShow", function() IW.Refresh() end)
    f:SetScript("OnHide", function() ADB.selection = nil end)
end

function IW.Refresh()
    local f = ADB.invFrame
    if not f or not f:IsShown() or not ADB.db then return end
    if ADB.selection and not ADB.Items.GetAt(ADB.selection.zone, ADB.selection.key) then ADB.selection = nil end
    for _, b in ipairs(f.slots) do UpdateSlot(b) end
    f.Money:SetText("Or : " .. ADB.FormatMoney(ADB.db.copper))
    local target = ADB.Items.MoneyTarget()
    if target ~= ADB.playerName then
        local d = ADB.Stats.GetBlock(target)
        f.TargetText:SetText("Montants appliqués à : " .. ADB.Stats.DisplayName(target)
            .. " (" .. ADB.FormatMoney(d and d.copper or 0) .. ")")
    elseif ADB.IsGM() then
        f.TargetText:SetText("Montants appliqués à : vous-même")
    else
        f.TargetText:SetText("")
    end
    f.AddBtn:SetShown(ADB.IsGM())
    f.DestroyBtn:SetEnabled(ADB.selection ~= nil)
end

function IW.Toggle()
    if ADB.invFrame:IsShown() then ADB.invFrame:Hide() else ADB.invFrame:Show() end
end

------------------------------------------------------------------------------
-- Slot interaction
------------------------------------------------------------------------------
StaticPopupDialogs["ADB_DETRUIRE"] = {
    text = "Détruire définitivement %s ?\nCette action est irréversible.",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data)
        if data and ADB.Items.GetAt(data.zone, data.key) then ADB.Items.Destroy(data.zone, data.key) end
    end,
}

StaticPopupDialogs["ADB_POTION"] = {
    text = "Utiliser %s ?\n%s",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data) ADB.Items.RequestPotion(data) end,
}

function IW.ClickDestroy()
    local s = ADB.selection
    if not s then return end
    local it = ADB.Items.GetAt(s.zone, s.key)
    if not it then
        ADB.selection = nil
        IW.Refresh()
        return
    end
    if ADB.IsGM() then
        ADB.Items.Destroy(s.zone, s.key)
    else
        StaticPopup_Show("ADB_DETRUIRE", ADB.Items.ColoredName(it), nil, { zone = s.zone, key = s.key })
    end
end

function IW.OnSlotClick(b, button)
    local it = ADB.Items.GetAt(b.zone, b.key)
    if button == "LeftButton" then
        ADB.selection = it and { zone = b.zone, key = b.key } or nil
        IW.Refresh()
    elseif button == "RightButton" and it then
        if b.zone == "eq" then
            ADB.Items.Unequip(b.key)
        elseif it.kind == "equip" then
            ADB.Items.Equip(b.key)
        elseif it.kind == "potvie" or it.kind == "potmana" then
            StaticPopup_Show("ADB_POTION", ADB.Items.ColoredName(it), ADB.CONSUMABLES[it.kind].desc, b.key)
        end
    end
end

function IW.SlotTooltip(b)
    local it = ADB.Items.GetAt(b.zone, b.key)
    if not it then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ADB.Items.ColoredName(it))
    local def = ADB.CONSUMABLES[it.kind]
    if def then
        GameTooltip:AddLine(def.desc, 1, 0.82, 0, true)
        if def.stack > 1 then GameTooltip:AddLine("Quantité : " .. it.count .. " / " .. def.stack, 1, 1, 1) end
        if it.kind ~= "ration" then GameTooltip:AddLine("Clic droit : utiliser", 0.6, 0.6, 0.6) end
    elseif it.kind == "story" then
        GameTooltip:AddLine(it.desc ~= "" and it.desc or "Objet narratif", 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(ADB.SLOT_LABEL[it.slot], 1, 1, 1)
        for i = 1, 3 do
            if it.stats[i] > 0 then
                GameTooltip:AddLine("+" .. it.stats[i] .. " " .. ADB.STAT_LABELS[i], 0.1, 1, 0.1)
            end
        end
        if it.skillsText ~= "" then GameTooltip:AddLine("Compétences : " .. it.skillsText, 1, 0.82, 0, true) end
        GameTooltip:AddLine(b.zone == "eq" and "Clic droit : déséquiper" or "Clic droit : équiper", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

------------------------------------------------------------------------------
-- Money
------------------------------------------------------------------------------
local function ReadAmount()
    local f = ADB.invFrame
    return floor((tonumber(f.Gold:GetText()) or 0) * 10000
        + (tonumber(f.Silver:GetText()) or 0) * 100 + (tonumber(f.Copper:GetText()) or 0))
end

-- add = true (GM only) / false (remove). GM can act on the targeted player.
function IW.ClickMoney(add)
    local m = ReadAmount()
    if m < 1 then
        ADB.Print("Montant invalide.")
        return
    end
    m = min(m, ADB.COPPER_MAX)
    local target = ADB.Items.MoneyTarget()
    if add then
        if not ADB.IsGM() then
            ADB.Print("Seul le MJ peut ajouter de l'or.")
            return
        end
        if target == ADB.playerName then
            ADB.Items.ChangeCopper(m)
        else
            ADB.Net.Send(format("GOLD;%s;%d", target, m))
            ADB.Print(format("%s ajoutés à %s.", ADB.FormatMoney(m), ADB.Stats.DisplayName(target)))
        end
    else
        if target == ADB.playerName then
            if m > ADB.db.copper then
                ADB.Print("Fonds insuffisants.")
                return
            end
            ADB.Items.ChangeCopper(-m)
        else
            ADB.Net.Send(format("GOLDM;%s;%d", target, m))
            ADB.Print(format("%s retirés à %s.", ADB.FormatMoney(m), ADB.Stats.DisplayName(target)))
        end
    end
    local f = ADB.invFrame
    f.Gold:SetText("")
    f.Silver:SetText("")
    f.Copper:SetText("")
end