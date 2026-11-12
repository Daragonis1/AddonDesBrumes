-- Logic/Inspect.lua : the GM inspects a player's (or alt's) inventory. Includes its small display window.
-- Wire (frozen): VQ;player[;alt] (GM→player)  VB;copper  VI;zone;key;kind;slot;rarity;icon;s1;s2;s3;name;skillsText;skillIds;count;tags  VE
local ADB = ADB
local Net, UI = ADB.Net, ADB.UI
local floor = math.floor
local format = string.format
local Encode, Decode = ADB.Encode, ADB.Decode

local Inspect = {}
ADB.Inspect = Inspect
Inspect.pending, Inspect.tmp, Inspect.data = {}, {}, {}   -- [player] = true / partial / final
Inspect.altMode = nil

-- Player side: sends the current context's inventory.
local function SendInventory()
    local db = ADB.db
    Net.Enqueue("VB;" .. (db.copper or 0))
    local function Item(zone, key, it)
        Net.Enqueue(format("VI;%s;%s;%s;%s;%d;%s;%d;%d;%d;%s;%s;%s;%d;%s", zone, key, it.kind, it.slot or "",
            it.rarity or 1, it.icon or "", it.stats and it.stats[1] or 0, it.stats and it.stats[2] or 0,
            it.stats and it.stats[3] or 0, Encode(it.name or ""), Encode(it.skillsText or ""),
            table.concat(it.skillIds or {}, ","), it.count or 1, table.concat(it.tags or {}, ",")))
    end
    for i = 1, ADB.INV_SLOTS do if db.inventory[i] then Item("inv", i, db.inventory[i]) end end
    for _, s in ipairs(ADB.EQUIP_SLOTS) do
        if db.equipment[s.key] then Item("eq", s.key, db.equipment[s.key]) end
    end
    Net.Enqueue("VE")
end

Net.Register("VQ", function(sender, message)
    local p = Net.Split(message)
    if not (ADB.IsGMName(sender) and not ADB.IsGM() and p[2] == ADB.playerName) then return end
    if p[3] == "alt" then
        if ADB.altChar then ADB.Alt.WithContext(true, SendInventory) end
    else
        SendInventory()
    end
end)

local function GmReceive(sender, message, cmd)
    if not (ADB.IsGM() and Inspect.pending[sender] and ADB.roster[sender]) then return end
    local p = Net.Split(message)
    if cmd == "VB" then
        Inspect.tmp[sender] = { inv = {}, eq = {}, copper = tonumber(p[2]) or 0 }
    elseif cmd == "VI" then
        local t = Inspect.tmp[sender]
        if not t then return end
        local it = ADB.Items.Validate({
            kind = p[4], slot = p[5], rarity = tonumber(p[6]), icon = p[7],
            stats = { tonumber(p[8]), tonumber(p[9]), tonumber(p[10]) },
            name = Decode(p[11] or ""), skillsText = Decode(p[12] or ""), skillIds = p[13],
            count = tonumber(p[14]), tags = p[15],
        })
        if not it then return end
        if p[2] == "inv" then
            local k = tonumber(p[3])
            if k and k >= 1 and k <= ADB.INV_SLOTS then t.inv[floor(k)] = it end
        elseif ADB.SLOT_LABEL[p[3] or ""] then
            t.eq[p[3]] = it
        end
    elseif cmd == "VE" then
        Inspect.data[sender], Inspect.tmp[sender], Inspect.pending[sender] = Inspect.tmp[sender], nil, nil
        Inspect.Show(sender)
    end
end
Net.RegisterMany({ "VB", "VI", "VE" }, GmReceive)

------------------------------------------------------------------------------
-- GM window
------------------------------------------------------------------------------
local function CreateSlot(f, x, y, label)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(40, 40)
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
    b.label:SetText(label or "")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnEnter", function(s)
        local it = s.item
        if not it then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ADB.Items.ColoredName(it))
        if it.kind == "equip" then
            GameTooltip:AddLine(ADB.SLOT_LABEL[it.slot], 1, 1, 1)
            for i = 1, 3 do
                if it.stats[i] > 0 then GameTooltip:AddLine("+" .. it.stats[i] .. " " .. ADB.STAT_LABELS[i], 0.1, 1, 0.1) end
            end
            if it.skillsText ~= "" then GameTooltip:AddLine("Compétences : " .. it.skillsText, 1, 0.82, 0, true) end
            if it.skillIds and #it.skillIds > 0 then
                GameTooltip:AddLine("Skills IDs : " .. table.concat(it.skillIds, ","), 0.5, 0.8, 1)
            end
        elseif ADB.CONSUMABLES[it.kind] then
            GameTooltip:AddLine(ADB.CONSUMABLES[it.kind].desc, 1, 0.82, 0, true)
        end
        if it.tags and #it.tags > 0 then GameTooltip:AddLine("Tags : " .. table.concat(it.tags, ","), 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    return b
end

local function UpdateSlot(b, it)
    b.item = it
    if it then
        local _, tex, r, g, bl = ADB.Items.Info(it)
        b.bg:SetColorTexture(r, g, bl, 1)
        b.icon:SetTexture(tex)
        b.icon:Show()
        b.count:SetText((it.count and it.count > 1) and it.count or "")
        b.label:SetText("")
    else
        b.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        b.icon:Hide()
        b.count:SetText("")
        b.label:SetText(b.emptyLabel or "")
    end
end

function Inspect.Show(player)
    local f = ADB.inspectFrame
    if not f then
        f = UI.BaseWindow("ADBVueInvFrame", 280, 330, "Inventaire")
        ADB.inspectFrame = f
        f:SetPoint("CENTER", 300, 0)
        tinsert(UISpecialFrames, "ADBVueInvFrame")
        f.eq, f.inv = {}, {}
        for k, s in ipairs(ADB.EQUIP_SLOTS) do
            f.eq[s.key] = CreateSlot(f, 16 + (k - 1) * 48, -64)
            f.eq[s.key].emptyLabel = s.label
        end
        for i = 1, ADB.INV_SLOTS do
            f.inv[i] = CreateSlot(f, 40 + ((i - 1) % 4) * 52, -122 - floor((i - 1) / 4) * 48)
        end
        f.Name = UI.Label(f, "", 16, -36, "GameFontNormal")
        f.Money = UI.Label(f, "", 16, -312, "GameFontHighlightSmall")
    end
    local d = Inspect.data[player]
    if not d then return end
    local label = ADB.Stats.DisplayName(player)
    if Inspect.altMode then
        local pn = ADB.Pets.FindAlt(player)
        label = (pn and ADB.NPC.DisplayName(pn) or label) .. " (secondaire)"
    end
    f.Name:SetText(label)
    f.Money:SetText("Or : " .. ADB.FormatMoney(d.copper))
    for _, s in ipairs(ADB.EQUIP_SLOTS) do UpdateSlot(f.eq[s.key], d.eq[s.key]) end
    for i = 1, ADB.INV_SLOTS do UpdateSlot(f.inv[i], d.inv[i]) end
    f:Show()
end

function Inspect.Request(player, alt)
    if not ADB.IsGM() or not player then return end
    if player == ADB.playerName then return ADB.InventoryWindow.Toggle() end
    if not ADB.roster[player] then
        ADB.Print("Aucune donnée pour " .. player .. ".")
        return
    end
    Inspect.pending[player] = true
    Inspect.altMode = alt and true or nil
    Net.Send("VQ;" .. player .. (alt and ";alt" or ""))
    C_Timer.After(10, function() Inspect.pending[player] = nil end)
end

-- "Inventaire" button in the GM's character sheet window
local function UpdateSheetButton()
    local f = ADBFicheFrame
    if not f then return end
    if not f.BtnInventory then
        f.BtnInventory = UI.Button(f, "Inventaire", 90, -296, 100, function() Inspect.Request(f.displayName) end)
    end
    f.BtnInventory:SetShown(ADB.IsGM() and f.displayName ~= nil)
end
hooksecurefunc(ADB.ConfigWindow, "OpenSheet", UpdateSheetButton)
hooksecurefunc(ADB.ConfigWindow, "RefreshSheet", UpdateSheetButton)