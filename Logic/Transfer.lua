-- Logic/Transfer.lua : export / import of the whole talent configuration (GM / solo).
-- Format "ADB1" is frozen: records separated by "~", fields by ";", text percent-escaped on [%;~].
local ADB = ADB
local Talents = ADB.Talents
local floor, max = math.floor, math.max
local format = string.format
local Decode, UI = ADB.Decode, ADB.UI

local Transfer = {}
ADB.Transfer = Transfer

local function Esc(s) return ADB.Escape(s, "[%%;~]") end

------------------------------------------------------------------------------
-- Export
------------------------------------------------------------------------------
function Transfer.Export()
    local out = { "ADB1" }
    local classes = {}
    for class in pairs(ADB.db.talents.trees) do classes[#classes + 1] = class end
    table.sort(classes)
    for _, class in ipairs(classes) do
        local tree = ADB.db.talents.trees[class]
        out[#out + 1] = format("T;%s;%d", Esc(class), tree.nextId or 1)
        local boxIds = {}
        for id in pairs(tree.colorBoxes or {}) do boxIds[#boxIds + 1] = id end
        table.sort(boxIds)
        for _, id in ipairs(boxIds) do
            local b = tree.colorBoxes[id]
            out[#out + 1] = format("C;%s;%d;%d;%d;%d;%d;%d;%d;%d;%d", Esc(class), b.id, b.x1, b.y1, b.x2, b.y2,
                b.r, b.g, b.b, b.a)
        end
        local ids = {}
        for id in pairs(tree.nodes) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local n = tree.nodes[id]
            out[#out + 1] = table.concat({ "N", Esc(class), n.id, n.x, n.y, n.nodeType, n.stat, n.effect, n.element,
                n.mana, n.limit, n.reaction and 1 or 0, n.bonusAction and 1 or 0, table.concat(n.requires, ","), n.icon,
                Esc(n.name), Esc(n.desc), n.hpCost, n.range, n.accuracy, n.aoe, n.isSpec and 1 or 0,
                n.specTagX, n.specTagY, table.concat(n.tags, ","), n.buffId or 0 }, ";")
        end
    end
    for _, d in ipairs(ADB.db.buffDefs or {}) do
        out[#out + 1] = format("B;%d;%s;%s;%d;%d;%d", d.id, Esc(d.name), d.icon, d.duration, d.buffType, d.value)
    end
    return table.concat(out, "~")
end

------------------------------------------------------------------------------
-- Import (full validation through ValidateNode; nothing applied before confirmation)
------------------------------------------------------------------------------
function Transfer.Parse(text)
    text = (text or ""):gsub("[\r\n]", "")
    if text:sub(1, 4) ~= "ADB1" then return nil end
    local R = { trees = {}, buffs = {}, nodeCount = 0, boxCount = 0 }
    for rec in text:gmatch("[^~]+") do
        local p = { strsplit(";", rec) }
        local kind = p[1]
        if kind == "T" then
            local class = Decode(p[2] or "")
            if ADB.CLASS_BY_NAME[class] then
                R.trees[class] = R.trees[class] or { nodes = {}, nextId = 1, colorBoxes = {}, nextBoxId = 1 }
                R.trees[class].nextId = max(1, floor(tonumber(p[3]) or 1))
            end
        elseif kind == "N" then
            local tree = R.trees[Decode(p[2] or "")]
            if tree then
                local requires = {}
                for s in (p[14] or ""):gmatch("%d+") do requires[#requires + 1] = tonumber(s) end
                local n = Talents.ValidateNode({
                    id = p[3], x = p[4], y = p[5], nodeType = p[6], stat = p[7], effect = p[8], element = p[9],
                    mana = p[10], limit = p[11], reaction = (p[12] == "1"), bonusAction = (p[13] == "1"),
                    requires = requires, icon = p[15], name = Decode(p[16] or ""), desc = Decode(p[17] or ""),
                    hpCost = p[18], range = p[19], accuracy = p[20], aoe = p[21], isSpec = (p[22] == "1"),
                    specTagX = p[23], specTagY = p[24], tags = p[25], buffId = p[26],
                })
                if n and not tree.nodes[n.id] then
                    tree.nodes[n.id] = n
                    tree.nextId = max(tree.nextId, n.id + 1)
                    R.nodeCount = R.nodeCount + 1
                end
            end
        elseif kind == "C" then
            local tree = R.trees[Decode(p[2] or "")]
            if tree then
                local b = Talents.ValidateColorBox({ id = p[3], x1 = p[4], y1 = p[5], x2 = p[6], y2 = p[7],
                    r = p[8], g = p[9], b = p[10], a = p[11] })
                if b and not tree.colorBoxes[b.id] then
                    tree.colorBoxes[b.id] = b
                    tree.nextBoxId = max(tree.nextBoxId, b.id + 1)
                    R.boxCount = R.boxCount + 1
                end
            end
        elseif kind == "B" then
            R.buffs[#R.buffs + 1] = { id = p[2], name = Decode(p[3] or ""), icon = p[4],
                duration = p[5], buffType = p[6], value = p[7] }
        end
    end
    if R.nodeCount == 0 and #R.buffs == 0 and R.boxCount == 0 then return nil end
    return R
end

local function ApplyImport(R)
    if not Talents.CanEdit() then return end
    local T = ADB.db.talents
    T.trees, T.learned, T.cooldowns = R.trees, {}, {}
    ADB.db.buffDefs = R.buffs
    ADB.Buffs.InitDB()   -- validates + recomputes next id
    Talents.Refresh()
    if ADB.IsGM() then
        for ci in ipairs(ADB.CLASSES) do ADB.TalentNet.BroadcastClass(ci) end   -- resync players
    end
    if ADB.bufFrame then ADB.BuffUI.RefreshWindow() end
    ADB.Print(format("Configuration importée : %d talents.", R.nodeCount))
end

StaticPopupDialogs["ADB_TAL_IMPORT"] = {
    text = "Importer %s talent(s) ?\nTous les arbres et buffs actuels seront REMPLACÉS.",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data) if data then ApplyImport(data) end end,
}

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------
local function CreateWindow()
    local f = UI.BaseWindow("ADBTransfFrame", 500, 400, "Export / Import des talents")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetPoint("CENTER", 0, 0)
    tinsert(UISpecialFrames, "ADBTransfFrame")
    local sf = CreateFrame("ScrollFrame", "ADBTransfScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -34)
    sf:SetPoint("BOTTOMRIGHT", -32, 50)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(440)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    f.Edit = eb
    UI.Button(f, "Exporter", 20, -368, 120, function()
        eb:SetText(Transfer.Export())
        eb:SetFocus()
        eb:HighlightText()
    end)
    UI.Button(f, "Importer", 150, -368, 120, function()
        local R = Transfer.Parse(eb:GetText())
        if not R then
            ADB.Print("Texte d'import invalide.")
            return
        end
        StaticPopup_Show("ADB_TAL_IMPORT", tostring(R.nodeCount), nil, R)
    end)
    UI.Label(f, "Exporter : Ctrl+C.  Importer : coller (Ctrl+V) puis Importer.", 280, -372, "GameFontDisableSmall")
    return f
end

function Transfer.ToggleWindow()
    if not ADB.transfFrame then ADB.transfFrame = CreateWindow() end
    local f = ADB.transfFrame
    if f:IsShown() then f:Hide() else f:Show() end
end

-- Button in the talent window (GM / solo only)
hooksecurefunc(ADB.TalentWindow, "Create", function()
    ADB.talFrame.BtnTransfer = UI.Button(ADB.talFrame, "Export / Import", 672, -660, 120, Transfer.ToggleWindow)
end)
hooksecurefunc(ADB.TalentWindow, "UpdatePanel", function()
    local b = ADB.talFrame and ADB.talFrame.BtnTransfer
    if b then b:SetShown(Talents.CanEdit()) end
end)