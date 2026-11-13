-- UI/TalentWindow.lua : talent tree window (player: learn/forget · GM/solo: node editor + ColorBox zones).
-- Alt.lua wraps Draw/OnNodeClick/OnCellClick/OnNodeEnter/DeleteSelected/Toggle: internal calls go through TW.
local ADB, UI = ADB, ADB.UI
local Talents = ADB.Talents
local TALENT = ADB.TALENT
local floor, max = math.floor, math.max
local format = string.format
local Clamp, CleanName = ADB.Clamp, ADB.CleanName

local TW = {}
ADB.TalentWindow = TW

local function Tree() return Talents.GetTree(Talents.viewClass) end

local function SelNode()
    local f = ADB.talFrame
    local a = f and Tree()
    return a and f.sel and a.nodes[f.sel] or nil
end

------------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------------
-- mode: "tree" (raw values) | "bar" (scaled values). Returns the tooltip.
function TW.ShowTooltip(owner, n, mode, G, anchor)
    G = G or GameTooltip
    G:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    G:AddLine(n.name, 1, 0.82, 0)
    G:AddLine(TALENT.NODE_TYPES[n.nodeType], 0.7, 0.7, 0.7)
    if n.isSpec then G:AddLine("Spécialisation (une seule à la fois)", 0.8, 0.5, 1) end
    if n.stat > 1 then
        G:AddLine("Statistique : " .. TALENT.STATS[Talents.EffectiveStat(n)] .. (n.stat == 5 and " (Principale)" or ""),
            1, 1, 1)
    end
    G:AddLine("Interaction : " .. TALENT.EFFECT_TYPES[n.effect], 1, 1, 1)
    G:AddLine("Élément : " .. TALENT.ELEMENTS[n.element], 1, 1, 1)
    if n.nodeType == 1 then
        if n.mana > 0 then G:AddLine("Coût : " .. n.mana .. " Mana", 0.3, 0.55, 1) end
        if n.hpCost > 0 then G:AddLine("Coût : " .. n.hpCost .. " PV", 1, 0.3, 0.3) end
        if n.range > 0 then G:AddLine("Portée : " .. n.range .. " m", 1, 1, 1) end
        if n.accuracy > 0 then G:AddLine("Précision : " .. n.accuracy, 1, 1, 1) end
        if n.aoe > 0 then G:AddLine("Zone d'effet : " .. n.aoe .. " m", 1, 1, 1) end
        if n.limit ~= 5 then G:AddLine("Limite d'utilisation : " .. TALENT.USE_LIMITS[n.limit].label, 1, 1, 1) end
        if n.reaction then G:AddLine("Compétence utilisable en Réaction", 1, 0.5, 0.1) end
        if n.bonusAction then G:AddLine("Compétence utilisant l'Action Bonus", 1, 0.5, 0.1) end
    end
    local bar = (mode == "bar")
    local mult = bar and Talents.Multiplier(n) or 1
    if bar and n.effect == 1 then
        local _, _, dmg = ADB.Buffs.GetBonus("P:" .. ADB.playerName)
        mult = mult * dmg
    end
    local text = Talents.FormatDescription(n.desc, bar, mult, bar and Talents.SpecBonus(n) or 0)
    if text ~= "" then
        G:AddLine(" ")
        G:AddLine(text, 1, 0.9, 0.6, true)
    end
    return G
end

function TW.OnNodeEnter(b)
    local a = Tree()
    local n = a and a.nodes[b.id]
    if not n then return end
    local f = ADB.talFrame
    local own = Talents.HasAccess(Talents.viewClass)
    local G = TW.ShowTooltip(b, n, "tree")
    local learned = own and Talents.Learned(Talents.viewClass) or {}
    local tagReq = Talents.TagRequirements(n)
    if #n.requires > 0 or #tagReq > 0 then
        G:AddLine(" ")
        for _, r in ipairs(n.requires) do
            local p = a.nodes[r]
            if p then
                local ok = own and learned[r]
                G:AddLine("Prérequis : " .. p.name, ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
            end
        end
        for _, r in ipairs(tagReq) do
            local ok = own and r.ok
            G:AddLine("Prérequis : " .. r.name, ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
        end
    end
    G:AddLine(" ")
    if f.edition then
        G:AddLine("Clic : sélectionner", 0.6, 0.6, 0.6)
    elseif Talents.viewClass == ADB.GM_CLASS then
        G:AddLine("Clic gauche : déclencher (annonce au chat)", 1, 0.5, 0.1)
    elseif own then
        if learned[n.id] then
            G:AddLine("Appris - clic droit : désapprendre", 0.3, 1, 0.3)
        elseif Talents.CanLearn(n, Talents.viewClass) then
            G:AddLine("Clic gauche : apprendre (1 point)", 0.3, 1, 0.3)
        else
            G:AddLine("Verrouillé (prérequis, points ou spécialisation)", 1, 0.3, 0.3)
        end
    end
    G:Show()
end

------------------------------------------------------------------------------
-- Editor helpers
------------------------------------------------------------------------------
-- Sets a field on the selected node and replicates it.
local function Modify(field, v)
    local n = SelNode()
    if not n or not Talents.CanEdit() then return end
    n[field] = v
    if field == "nodeType" then
        if v == 2 then
            n.mana, n.limit, n.reaction, n.bonusAction = 0, 5, false, false
            n.hpCost, n.range, n.accuracy, n.aoe = -1, -1, -1, -1
        else
            n.isSpec, n.specTagX, n.specTagY = false, "", ""
        end
    end
    ADB.TalentNet.ScheduleNode(Talents.ClassIndex(Talents.viewClass), n.id)
    TW.Draw()
end

local function Dropdown(name, parent, x, y, w, list, get, set)
    local d = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(d, w)
    UIDropDownMenu_Initialize(d, function(_, level)
        for i, label in ipairs(list()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.checked = (get() == i)
            info.func = function()
                UIDropDownMenu_SetText(d, label)
                set(i, label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    d.Update = function() UIDropDownMenu_SetText(d, list()[get()] or "") end
    return d
end

local function NumField(parent, label, lx, ex, y, field, letters, maxv)
    UI.Label(parent, label, lx, y - 3)
    local e = UI.Input(parent, ex, y, 44, letters, true)
    e:SetScript("OnTextChanged", function(self, user)
        if user then
            local v = tonumber(self:GetText())
            Modify(field, v and Clamp(floor(v), -1, maxv) or -1)
        end
    end)
    return e
end

local function SetNum(e, v)
    if not e:HasFocus() then e:SetText(v > 0 and tostring(v) or "") end
end

-- Would linking `pid` as prerequisite of `target` create a cycle?
local function Requires(tree, id, target, seen)
    seen = seen or {}
    if seen[id] then return false end
    seen[id] = true
    local n = tree.nodes[id]
    if not n then return false end
    for _, r in ipairs(n.requires) do
        if r == target or Requires(tree, r, target, seen) then return true end
    end
    return false
end

function TW.ToggleLink(pid)
    local a, n = Tree(), SelNode()
    if not a or not n or pid == n.id or not a.nodes[pid] then return end
    for i, r in ipairs(n.requires) do
        if r == pid then
            tremove(n.requires, i)
            return true
        end
    end
    if #n.requires >= TALENT.MAX_REQUIRES then
        ADB.Print("Maximum " .. TALENT.MAX_REQUIRES .. " prérequis par talent.")
        return
    end
    if Requires(a, pid, n.id) then
        ADB.Print("Lien impossible : dépendance circulaire.")
        return
    end
    n.requires[#n.requires + 1] = pid
    return true
end

function TW.DeleteSelected()
    local n, a = SelNode(), Tree()
    if not n or not a then return end
    local ci = Talents.ClassIndex(Talents.viewClass)
    a.nodes[n.id] = nil
    for _, m in pairs(a.nodes) do
        for i = #m.requires, 1, -1 do
            if m.requires[i] == n.id then
                tremove(m.requires, i)
                ADB.TalentNet.ScheduleNode(ci, m.id)
            end
        end
    end
    if ADB.IsGM() then ADB.Net.Enqueue(format("TX;%d;%d", ci, n.id)) end
    ADB.talFrame.sel = nil
    TW.Draw()
end

------------------------------------------------------------------------------
-- Clicks
------------------------------------------------------------------------------
function TW.OnNodeClick(b, button)
    local f = ADB.talFrame
    local a = Tree()
    local n = a and a.nodes[b.id]
    if not n then return end
    if f.edition then
        if f.mode == "link" and f.sel and f.sel ~= n.id then
            if TW.ToggleLink(n.id) ~= nil then
                ADB.TalentNet.ScheduleNode(Talents.ClassIndex(Talents.viewClass), f.sel)
            end
            f.mode = nil
        else
            f.sel, f.mode = n.id, nil
        end
    elseif Talents.viewClass == ADB.GM_CLASS then
        if button == "LeftButton" and Talents.CanEdit() then Talents.GmTrigger(n) end
        return
    elseif Talents.HasAccess(Talents.viewClass) then
        local learned = Talents.Learned(Talents.viewClass)
        if button == "LeftButton" then
            if Talents.CanLearn(n, Talents.viewClass) then
                learned[n.id] = true
            elseif not learned[n.id] then
                local s = n.isSpec and Talents.ActiveSpec()
                if s then
                    UIErrorsFrame:AddMessage(
                        "Une seule spécialisation à la fois : oubliez « " .. s.name .. " » d'abord.", 1, 0.3, 0.3)
                else
                    UIErrorsFrame:AddMessage("Talent verrouillé (prérequis ou points manquants).", 1, 0.3, 0.3)
                end
            end
        elseif learned[n.id] then
            for _, m in pairs(a.nodes) do
                if learned[m.id] then
                    for _, r in ipairs(m.requires) do
                        if r == n.id then
                            UIErrorsFrame:AddMessage("D'autres talents appris dépendent de celui-ci.", 1, 0.3, 0.3)
                            return
                        end
                    end
                end
            end
            learned[n.id] = nil
        end
    end
    Talents.Refresh()
end

------------------------------------------------------------------------------
-- ColorBox zones (editor)
------------------------------------------------------------------------------
local BOX_PALETTE = { { 60, 110, 200 }, { 200, 80, 80 }, { 80, 170, 90 }, { 190, 150, 50 }, { 150, 80, 190 }, { 60, 170, 170 } }

function TW.BoxAt(a, x, y)
    local best, area
    for _, b in pairs(a and a.colorBoxes or {}) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            local s = (b.x2 - b.x1 + 1) * (b.y2 - b.y1 + 1)
            if not best or s < area or (s == area and b.id > best.id) then best, area = b, s end
        end
    end
    return best
end

function TW.CreateBox(x1, y1, x2, y2)
    if not Talents.CanEdit() then return end
    local a = Talents.GetTree(Talents.viewClass, true)
    a.colorBoxes = a.colorBoxes or {}
    local id = max(1, floor(tonumber(a.nextBoxId) or 1))
    while a.colorBoxes[id] do id = id + 1 end
    a.nextBoxId = id + 1
    local p = BOX_PALETTE[(id - 1) % #BOX_PALETTE + 1]
    a.colorBoxes[id] = Talents.ValidateColorBox({
        id = id,
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        r = p[1],
        g = p[2],
        b = p[3],
        a = 30
    })
    ADB.talFrame.selBox = id
    ADB.TalentNet.ScheduleColorBox(Talents.ClassIndex(Talents.viewClass), id)
end

function TW.ModifyBox(changes, id)
    if not Talents.CanEdit() then return end
    local f = ADB.talFrame
    local a = Tree()
    id = id or f.selBox
    local b = a and a.colorBoxes and a.colorBoxes[id]
    if not b then return end
    local t = { id = b.id, x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2, r = b.r, g = b.g, b = b.b, a = b.a }
    for k, v in pairs(changes) do t[k] = v end
    a.colorBoxes[id] = Talents.ValidateColorBox(t)
    ADB.TalentNet.ScheduleColorBox(Talents.ClassIndex(Talents.viewClass), id)
    TW.Draw()
end

function TW.DeleteBox()
    if not Talents.CanEdit() then return end
    local f = ADB.talFrame
    local a = Tree()
    local id = f.selBox
    if not (a and id and a.colorBoxes and a.colorBoxes[id]) then return end
    a.colorBoxes[id] = nil
    f.selBox = nil
    if ADB.IsGM() then ADB.Net.Enqueue(format("TK;%d;%d", Talents.ClassIndex(Talents.viewClass), id)) end
    TW.Draw()
end

function TW.PickBoxColor()
    local f = ADB.talFrame
    local a = Tree()
    local b = a and a.colorBoxes and a.colorBoxes[f.selBox or 0]
    if not b then return end
    local P = ColorPickerFrame
    P:SetFrameStrata("FULLSCREEN_DIALOG")
    P.hasOpacity = true
    P.opacity = 1 - b.a / 100
    P.previousValues = { b.r / 255, b.g / 255, b.b / 255, 1 - b.a / 100 }
    P.cancelFunc = function(prev)
        TW.ModifyBox({
            r = floor(prev[1] * 255 + 0.5),
            g = floor(prev[2] * 255 + 0.5),
            b = floor(prev[3] * 255 + 0.5),
            a = floor((1 - prev[4]) * 100 + 0.5)
        })
    end
    P:SetColorRGB(b.r / 255, b.g / 255, b.b / 255)
    P.func = function()
        local r, g, bl = P:GetColorRGB()
        TW.ModifyBox({ r = floor(r * 255 + 0.5), g = floor(g * 255 + 0.5), b = floor(bl * 255 + 0.5) })
    end
    P.opacityFunc = function()
        TW.ModifyBox({ a = floor((1 - OpacitySliderFrame:GetValue()) * 100 + 0.5) })
    end
    P:Hide()
    P:Show()
end

local function ClickZoneCell(c, a)
    local f = ADB.talFrame
    if f.zState == "c1" then
        f.zCorner, f.zState = { c.x, c.y }, "c2"
    elseif f.zState == "c2" and f.zCorner then
        local x1, y1 = f.zCorner[1], f.zCorner[2]
        local edit = f.zEditId
        f.zState, f.zCorner, f.zEditId = nil, nil, nil
        if edit and a.colorBoxes and a.colorBoxes[edit] then
            TW.ModifyBox({ x1 = x1, y1 = y1, x2 = c.x, y2 = c.y }, edit)
        else
            TW.CreateBox(x1, y1, c.x, c.y)
        end
    else
        local b = TW.BoxAt(a, c.x, c.y)
        f.selBox = b and b.id or nil
    end
    TW.Draw()
end

local function UpdateZonePanel()
    local f = ADB.talFrame
    local Z = f.Ed.Z
    local a = Tree()
    local b = f.selBox and a and a.colorBoxes and a.colorBoxes[f.selBox]
    if f.selBox and not b then f.selBox = nil end
    Z.Info:SetText(b and format("Zone #%d : cases (%d,%d) à (%d,%d).", b.id, b.x1, b.y1, b.x2, b.y2)
        or "Aucune zone sélectionnée. Cliquez dans une zone existante pour la sélectionner, ou créez-en une.")
    for _, w in ipairs({ Z.BtnRedefine, Z.BtnDelete, Z.Swatch, Z.Hex, Z.Alpha, Z.LC, Z.LH, Z.LA }) do w:SetShown(b ~= nil) end
    if b then
        Z.SwatchTex:SetColorTexture(b.r / 255, b.g / 255, b.b / 255, 1)
        if not Z.Hex:HasFocus() then Z.Hex:SetText(format("%02X%02X%02X", b.r, b.g, b.b)) end
        if not Z.Alpha:HasFocus() then Z.Alpha:SetText(b.a) end
    end
end

-- Click on an empty cell: zone corner, move selected node (Shift / "move" mode) or create a node.
function TW.OnCellClick(c)
    local f = ADB.talFrame
    local a = Talents.GetTree(Talents.viewClass, true)
    local ci = Talents.ClassIndex(Talents.viewClass)
    if f.zoneMode then return ClickZoneCell(c, a) end
    if (f.mode == "move" or IsShiftKeyDown()) and f.sel and a.nodes[f.sel] then
        local n = a.nodes[f.sel]
        n.x, n.y = c.x, c.y
        ADB.TalentNet.ScheduleNode(ci, n.id)
        f.mode = nil
    else
        local id = a.nextId
        a.nextId = id + 1
        a.nodes[id] = Talents.ValidateNode({ id = id, x = c.x, y = c.y, name = "Nouveau talent", nodeType = 1 })
        f.sel, f.mode = id, nil
        ADB.TalentNet.ScheduleNode(ci, id)
    end
    TW.Draw()
end

------------------------------------------------------------------------------
-- Widgets: cells / node buttons
------------------------------------------------------------------------------
local function CreateCells(f)
    f.cells = {}
    for y = 1, TALENT.ROWS do
        for x = 1, TALENT.COLS do
            local c = CreateFrame("Button", nil, f.canvas)
            c:SetSize(TALENT.CELL - 8, TALENT.CELL - 8)
            c:SetPoint("CENTER", f.canvas, "TOPLEFT", (x - 0.5) * TALENT.CELL, -(y - 0.5) * TALENT.CELL)
            local t = c:CreateTexture(nil, "BACKGROUND")
            t:SetAllPoints()
            t:SetColorTexture(1, 1, 1, 0.07)
            c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            c.x, c.y = x, y
            c:SetScript("OnClick", function(self) TW.OnCellClick(self) end)
            c:Hide()
            f.cells[#f.cells + 1] = c
        end
    end
end

local function CreateNodeButton(f)
    local S = TALENT.ICON
    local b = CreateFrame("Button", nil, f.canvas)
    b:SetSize(S, S)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.frame = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.frame:SetSize(S * 1.8, S * 1.8)
    b.frame:SetPoint("CENTER")
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(S * 1.75, S * 1.75)
    b.glow:SetPoint("CENTER")
    b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.rank:SetPoint("BOTTOMRIGHT", 3, -3)
    b.mark = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.mark:SetPoint("TOPLEFT", 1, -1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, btn) TW.OnNodeClick(self, btn) end)
    b:SetScript("OnEnter", function(self) TW.OnNodeEnter(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.btns[#f.btns + 1] = b
    return b
end

local function ClassList()
    local t = {}
    if Talents.CanEdit() then
        for _, c in ipairs(ADB.CLASSES) do t[#t + 1] = c.name end
    else
        for _, c in ipairs(Talents.AccessibleClasses()) do t[#t + 1] = c end
    end
    return t
end

------------------------------------------------------------------------------
-- Side panel state
------------------------------------------------------------------------------
function TW.UpdatePanel()
    local f = ADB.talFrame
    local Ed, C = f.Ed, f.Ed.C
    local ed = f.edition and true or false
    f.BtnEdit:SetShown(Talents.CanEdit())
    f.BtnEdit:SetText(ed and "Quitter l'éditeur" or "Mode éditeur")
    f.BtnReset:SetShown(not ed)
    f.BtnZone:SetShown(ed)
    f.BtnZone:SetText(f.zoneMode and "Mode talents" or "Zones (ColorBox)")
    local help = f.mode == "link" and "|cffffd100Cliquez le talent PRÉREQUIS.|r"
        or f.mode == "move" and "|cffffd100Cliquez une case vide.|r" or ""
    if f.zoneMode then
        help = f.zState == "c1" and "|cffffd100Cliquez le 1er coin.|r"
            or f.zState == "c2" and "|cffffd100Cliquez le coin opposé.|r" or ""
    end
    f.Help:SetText(help)
    Ed:SetShown(ed)
    if not ed then return end
    if f.zoneMode then
        Ed.Empty:Hide()
        C:Hide()
        Ed.Z:Show()
        UpdateZonePanel()
        return
    end
    Ed.Z:Hide()
    local n = SelNode()
    Ed.Empty:SetShown(n == nil)
    C:SetShown(n ~= nil)
    if not n then return end
    if not C.Name:HasFocus() then C.Name:SetText(n.name) end
    C.Icon:SetTexture(ADB.IconTexture(n.icon))
    C.DType.Update(); C.DStat.Update(); C.DEffect.Update(); C.DElement.Update()
    C.Active:SetShown(n.nodeType == 1)
    C.Area:SetShown(n.nodeType == 1)
    C.SpecPanel:SetShown(n.nodeType == 2)
    if n.nodeType == 1 then
        if not C.Mana:HasFocus() then C.Mana:SetText(n.mana) end
        C.DLimit.Update()
        C.Reaction:SetChecked(n.reaction)
        C.BonusAction:SetChecked(n.bonusAction)
        SetNum(C.HpCost, n.hpCost); SetNum(C.Range, n.range); SetNum(C.Accuracy, n.accuracy); SetNum(C.Aoe, n.aoe)
    else
        C.IsSpec:SetChecked(n.isSpec)
        if not C.SpecX:HasFocus() then C.SpecX:SetText(n.specTagX) end
        if not C.SpecY:HasFocus() then C.SpecY:SetText(n.specTagY) end
    end
    if not C.Tags:HasFocus() then C.Tags:SetText(table.concat(n.tags, ",")) end
    if not C.Desc:HasFocus() then C.Desc:SetText(n.desc) end
end

------------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------------
function TW.Draw()
    local f = ADB.talFrame
    if not f or not f:IsShown() or not ADB.db then return end
    if not Talents.CanEdit() then
        f.edition = false
        if not (Talents.viewClass and Talents.HasAccess(Talents.viewClass)) then Talents.viewClass = ADB.db.class end
    end
    Talents.viewClass = Talents.viewClass or ADB.db.class
    local class = Talents.viewClass
    local own = Talents.HasAccess(class)
    local ed = f.edition and true or false
    if not ed then f.zoneMode, f.zState, f.zCorner, f.zEditId = nil, nil, nil, nil end
    local zm = f.zoneMode and true or false
    local a = Talents.GetTree(class)
    local nodes = a and a.nodes or {}
    local learned = own and Talents.Learned(class) or {}
    if f.sel and not nodes[f.sel] then f.sel = nil end

    local list, occupied = {}, {}
    for _, n in pairs(nodes) do
        list[#list + 1] = n
        occupied[(n.y - 1) * TALENT.COLS + n.x] = true
    end
    table.sort(list, function(p, q) return p.id < q.id end)

    if ed and not f.cells then CreateCells(f) end
    if f.cells then
        for i, c in ipairs(f.cells) do c:SetShown(ed and (zm or not occupied[i])) end
    end

    -- zone backgrounds
    local boxes = {}
    for _, b in pairs(a and a.colorBoxes or {}) do boxes[#boxes + 1] = b end
    table.sort(boxes, function(p, q) return p.id < q.id end)
    for i, b in ipairs(boxes) do
        local t = f.boxTex[i]
        if not t then
            t = f.canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
            f.boxTex[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", (b.x1 - 1) * TALENT.CELL, -(b.y1 - 1) * TALENT.CELL)
        t:SetPoint("BOTTOMRIGHT", f.canvas, "TOPLEFT", b.x2 * TALENT.CELL, -b.y2 * TALENT.CELL)
        t:SetColorTexture(b.r / 255, b.g / 255, b.b / 255, b.a / 100)
        t:Show()
    end
    for i = #boxes + 1, #f.boxTex do f.boxTex[i]:Hide() end
    do
        local bs = f.boxSel
        local sb = a and a.colorBoxes and a.colorBoxes[f.selBox or 0]
        local x1, y1, x2, y2
        if f.zState == "c2" and f.zCorner then
            x1, y1, x2, y2 = f.zCorner[1], f.zCorner[2], f.zCorner[1], f.zCorner[2]
        elseif sb then
            x1, y1, x2, y2 = sb.x1, sb.y1, sb.x2, sb.y2
        end
        if zm and x1 then
            bs:ClearAllPoints()
            bs:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", (x1 - 1) * TALENT.CELL, -(y1 - 1) * TALENT.CELL)
            bs:SetPoint("BOTTOMRIGHT", f.canvas, "TOPLEFT", x2 * TALENT.CELL, -y2 * TALENT.CELL)
            bs:Show()
        else
            bs:Hide()
        end
    end

    -- node buttons
    wipe(f.byId)
    for i, n in ipairs(list) do
        local b = f.btns[i] or CreateNodeButton(f)
        b.id = n.id
        b:ClearAllPoints()
        b:SetPoint("CENTER", f.canvas, "TOPLEFT", (n.x - 0.5) * TALENT.CELL, -(n.y - 0.5) * TALENT.CELL)
        b.tex:SetTexture(ADB.IconTexture(n.icon))
        local isLearned = own and learned[n.id] and true or false
        local ok = (own and not isLearned and Talents.CanLearn(n, class)) or (class == ADB.GM_CLASS and not ed)
        local gr, gg, gb, ga, rank, rr, rg, rb
        if ed then
            gr, gg, gb, ga = 0.8, 0.8, 0.8, 0.5
            if f.sel == n.id then gr, gg, gb, ga = 0.2, 0.9, 1, 1 end
        elseif isLearned then
            gr, gg, gb, ga, rank, rr, rg, rb = 1, 0.82, 0, 1, "1", 1, 0.82, 0
        elseif ok then
            gr, gg, gb, ga, rank, rr, rg, rb = 0.1, 1, 0.1, 1, (class ~= ADB.GM_CLASS and "0" or ""), 0.1, 1, 0.1
        end
        b.glow:SetShown(ga ~= nil)
        if ga then b.glow:SetVertexColor(gr, gg, gb, ga) end
        b.rank:SetText(rank or "")
        if rr then b.rank:SetTextColor(rr, rg, rb) end
        b.tex:SetDesaturated(not (ed or isLearned or ok))
        b.mark:SetText(n.isSpec and "S" or (n.nodeType == 2 and "P" or ""))
        b:EnableMouse(not zm)
        b:Show()
        f.byId[n.id] = b
    end
    for i = #list + 1, #f.btns do f.btns[i]:Hide() end

    -- prerequisite branches (orthogonal, Classic style)
    local k, CS = 0, TALENT.CELL
    local GOLD, GREEN, GREY, EDC = { 1, 0.82, 0, 1 }, { 0.3, 0.9, 0.3, 1 }, { 0.45, 0.45, 0.45, 0.9 },
        { 0.7, 0.7, 0.95, 0.9 }
    local function Seg(x1, y1, x2, y2, col)
        k = k + 1
        local l = f.lines[k]
        if not l then
            l = f.canvas:CreateLine(nil, "ARTWORK")
            f.lines[k] = l
        end
        l:SetThickness(max(4, floor(CS / 10)))
        l:SetStartPoint("TOPLEFT", f.canvas, x1, y1)
        l:SetEndPoint("TOPLEFT", f.canvas, x2, y2)
        l:SetColorTexture(col[1], col[2], col[3], col[4])
        l:Show()
    end
    for _, n in ipairs(list) do
        for _, r in ipairs(n.requires) do
            local p = nodes[r]
            if p and f.byId[r] then
                local pa, na = own and learned[r], own and learned[n.id]
                local col = ed and EDC or ((pa and na) and GOLD or (pa and GREEN or GREY))
                local px, py = (p.x - 0.5) * CS, -(p.y - 0.5) * CS
                local cx, cy = (n.x - 0.5) * CS, -(n.y - 0.5) * CS
                if px ~= cx and py ~= cy then
                    Seg(px, py, px, cy, col)
                    Seg(px, cy, cx, cy, col)
                else
                    Seg(px, py, cx, cy, col)
                end
            end
        end
    end
    for i = k + 1, #f.lines do f.lines[i]:Hide() end

    f.Empty:SetText((#list == 0 and not ed) and "Aucun talent défini pour cette classe." or "")
    if own then
        local u, t = Talents.PointsUsed(), Talents.PointsTotal()
        f.Points:SetText(format("Points : |cffffd100%d|r / %d  (restants : %d)", u, t, t - u))
    else
        f.Points:SetText(class == ADB.GM_CLASS and "|cffffd100Compétences MJ : clic = déclencher|r"
            or "|cffaaaaaaLecture seule (autre classe)|r")
    end
    f.ClassDrop.Update()
    TW.UpdatePanel()
end

------------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------------
local LIMIT_ORDER = { 1, 6, 2, 3, 4, 5 } -- display order of USE_LIMITS

StaticPopupDialogs["ADB_TAL_RESET"] = {
    text = "Réinitialiser tous vos talents appris ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function()
        for _, c in ipairs(Talents.AccessibleClasses()) do wipe(Talents.Learned(c)) end
        Talents.Refresh()
    end,
}

function TW.Create()
    local W = Clamp(floor(UIParent:GetWidth() * 0.96), 1000, 1560)
    local H = Clamp(floor(UIParent:GetHeight() * 0.94), 700, 1000)
    TALENT.CELL = Clamp(floor((W - 318) / TALENT.COLS), 44, 76)
    TALENT.ICON = floor(TALENT.CELL * 0.62)
    local cw = TALENT.COLS * TALENT.CELL
    W = cw + 318
    local PX = 14 + cw + 34
    local f = UI.BaseWindow("ADBTalentFrame", W, H, "Arbre de talents")
    ADB.talFrame = f
    f.PX, f.btnY = PX, -(H - 30)
    f:SetPoint("CENTER", 0, 0)
    f.btns, f.lines, f.byId, f.boxTex = {}, {}, {}, {}
    tinsert(UISpecialFrames, "ADBTalentFrame")

    local sf = CreateFrame("ScrollFrame", "ADBTalScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -34)
    sf:SetSize(cw, H - 54)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(cw, TALENT.ROWS * TALENT.CELL)
    sf:SetScrollChild(c)
    f.canvas = c
    local bg = c:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.09, 0.065, 0.04, 1)
    local tile = c:CreateTexture(nil, "BACKGROUND", nil, -7)
    tile:SetAllPoints()
    tile:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background", "REPEAT", "REPEAT")
    tile:SetVertexColor(1, 0.8, 0.55, 0.45)
    local bd = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bd:SetPoint("TOPLEFT", sf, -6, 6)
    bd:SetPoint("BOTTOMRIGHT", sf, 6, -6)
    bd:SetFrameLevel(sf:GetFrameLevel() + 10)
    bd:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    bd:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    f.Empty = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.Empty:SetPoint("TOP", 0, -20)

    UI.Label(f, "Classe", PX, -40)
    f.ClassDrop = Dropdown("ADBTalClasseDrop", f, PX + 36, -33, 150, ClassList,
        function()
            for i, l in ipairs(ClassList()) do
                if l == Talents.viewClass then return i end
            end
            return 1
        end,
        function(_, label)
            Talents.viewClass = label
            f.sel, f.mode, f.selBox, f.zState, f.zCorner, f.zEditId = nil, nil, nil, nil, nil, nil
            TW.Draw()
        end)
    f.Points = UI.Label(f, "", PX, -76, "GameFontNormal")
    f.BtnReset = UI.Button(f, "Réinitialiser", PX, -98, 120, function() StaticPopup_Show("ADB_TAL_RESET") end)
    f.BtnEdit = UI.Button(f, "Mode éditeur", PX + 126, -98, 120, function()
        f.edition = not f.edition
        f.sel, f.mode = nil, nil
        TW.Draw()
    end)
    f.Help = UI.Label(f, "", PX, -124, "GameFontNormalSmall")
    f.BtnZone = UI.Button(f, "Zones (ColorBox)", PX, -98, 120, function()
        f.zoneMode = not f.zoneMode
        f.sel, f.mode, f.zState, f.zCorner, f.zEditId = nil, nil, nil, nil, nil
        TW.Draw()
    end)
    f.BtnZone:Hide()

    local Ed = CreateFrame("Frame", nil, f)
    Ed:SetSize(250, 540)
    Ed:SetPoint("TOPLEFT", PX, -146)
    f.Ed = Ed
    Ed.Empty = UI.Label(Ed, "Cliquez sur une case vide pour créer un talent, ou sur un talent pour le modifier.", 0, -10,
        "GameFontHighlightSmall")
    Ed.Empty:SetWidth(240)
    Ed.Empty:SetJustifyV("TOP")
    local C = CreateFrame("Frame", nil, Ed)
    C:SetAllPoints()
    Ed.C = C

    local function Prop(field, default)
        local n = SelNode()
        return n and n[field] or default
    end

    UI.Label(C, "Nom", 0, -4)
    C.Name = UI.Input(C, 70, -1, 170, TALENT.NAME_MAX)
    C.Name:SetScript("OnTextChanged", function(self, user)
        if user then
            local t = CleanName(self:GetText())
            Modify("name", t ~= "" and t or "Talent")
        end
    end)

    UI.Label(C, "Icône", 0, -36)
    local ib = UI.IconButton(C, 70, -28, 32, function()
        ADB.Icons.Open(function(v) Modify("icon", ADB.SanitizeIcon(v)) end)
    end)
    C.Icon = ib.icon
    UI.Label(C, "(cliquer pour choisir)", 110, -40, "GameFontDisableSmall")

    UI.Label(C, "Type", 0, -72)
    C.DType = Dropdown("ADBTalTypDrop", C, 48, -66, 130, function() return TALENT.NODE_TYPES end,
        function() return Prop("nodeType", 1) end, function(i) Modify("nodeType", i) end)
    UI.Label(C, "Stat.", 0, -102)
    C.DStat = Dropdown("ADBTalStatDrop", C, 48, -96, 130, function() return TALENT.STATS end,
        function() return Prop("stat", 1) end, function(i) Modify("stat", i) end)
    UI.Label(C, "Effet", 0, -132)
    C.DEffect = Dropdown("ADBTalInterDrop", C, 48, -126, 130, function() return TALENT.EFFECT_TYPES end,
        function() return Prop("effect", 4) end, function(i) Modify("effect", i) end)
    UI.Label(C, "Élément", 0, -162)
    C.DElement = Dropdown("ADBTalElemDrop", C, 48, -156, 130, function() return TALENT.ELEMENTS end,
        function() return Prop("element", 1) end, function(i) Modify("element", i) end)

    -- Active: mana / limit / reaction / bonus action
    local A = CreateFrame("Frame", nil, C)
    A:SetSize(250, 106)
    A:SetPoint("TOPLEFT", 0, -192)
    C.Active = A
    UI.Label(A, "Coût mana", 0, -4)
    C.Mana = UI.Input(A, 80, -1, 50, 3, true)
    C.Mana:SetScript("OnTextChanged", function(self, user)
        if user then Modify("mana", Clamp(floor(tonumber(self:GetText()) or 0), 0, TALENT.MANA_MAX)) end
    end)
    UI.Label(A, "Limite", 0, -34)
    C.DLimit = Dropdown("ADBTalLimDrop", A, 48, -28, 130,
        function()
            local t = {}
            for i, k in ipairs(LIMIT_ORDER) do t[i] = TALENT.USE_LIMITS[k].label end
            return t
        end,
        function()
            local l = Prop("limit", 5)
            for i, k in ipairs(LIMIT_ORDER) do if k == l then return i end end
            return 6
        end,
        function(i) Modify("limit", LIMIT_ORDER[i]) end)
    C.Reaction = CreateFrame("CheckButton", "ADBTalReacCheck", A, "UICheckButtonTemplate")
    C.Reaction:SetPoint("TOPLEFT", -4, -56)
    _G["ADBTalReacCheckText"]:SetText("Réaction")
    C.Reaction:SetScript("OnClick", function(self) Modify("reaction", self:GetChecked() and true or false) end)
    C.BonusAction = CreateFrame("CheckButton", "ADBTalBonusCheck", A, "UICheckButtonTemplate")
    C.BonusAction:SetPoint("TOPLEFT", -4, -82)
    _G["ADBTalBonusCheckText"]:SetText("Action Bonus")
    C.BonusAction:SetScript("OnClick", function(self) Modify("bonusAction", self:GetChecked() and true or false) end)

    -- Active: HP cost / range / accuracy / AoE
    local X = CreateFrame("Frame", nil, C)
    X:SetSize(250, 56)
    X:SetPoint("TOPLEFT", 0, -302)
    C.Area = X
    C.HpCost = NumField(X, "Coût PV", 0, 58, -1, "hpCost", 3, TALENT.HP_COST_MAX)
    C.Range = NumField(X, "Portée", 112, 158, -1, "range", 3, TALENT.RANGE_MAX)
    C.Accuracy = NumField(X, "Précision", 0, 58, -27, "accuracy", 3, 100)
    C.Aoe = NumField(X, "ZoE (m)", 112, 158, -27, "aoe", 3, TALENT.AOE_MAX)

    -- Passive: specialization
    local S = CreateFrame("Frame", nil, C)
    S:SetSize(250, 110)
    S:SetPoint("TOPLEFT", 0, -192)
    C.SpecPanel = S
    C.IsSpec = CreateFrame("CheckButton", "ADBTalSpeCheck", S, "UICheckButtonTemplate")
    C.IsSpec:SetPoint("TOPLEFT", -4, -2)
    _G["ADBTalSpeCheckText"]:SetText("Spécialisation")
    C.IsSpec:SetScript("OnClick", function(self) Modify("isSpec", self:GetChecked() and true or false) end)
    UI.Label(S, "Tag X", 0, -36)
    C.SpecX = UI.Input(S, 50, -33, 190, 16)
    C.SpecX:SetScript("OnTextChanged", function(self, user)
        if user then Modify("specTagX", Talents.SanitizeTag(self:GetText())) end
    end)
    UI.Label(S, "Tag Y", 0, -62)
    C.SpecY = UI.Input(S, 50, -59, 190, 16)
    C.SpecY:SetScript("OnTextChanged", function(self, user)
        if user then Modify("specTagY", Talents.SanitizeTag(self:GetText())) end
    end)
    UI.Label(S, "X : +1 efficacité   Y : regain de mana", 0, -88, "GameFontDisableSmall")

    -- Tags (invisible to players in game)
    UI.Label(C, "Tags", 0, -364)
    C.Tags = UI.Input(C, 40, -361, 205, 600)
    C.Tags:SetScript("OnTextChanged", function(self, user)
        if user then Modify("tags", Talents.SanitizeTags(self:GetText())) end
    end)

    UI.Label(C, "Description  ([2] = valeur dynamique)", 0, -388, "GameFontNormalSmall")
    C.Desc = UI.MultilineInput(C, 0, -404, 250, 76, TALENT.DESC_MAX)
    C.Desc:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    C.Desc:SetScript("OnTextChanged", function(self, user)
        if user then Modify("desc", Talents.SanitizeDesc(self:GetText())) end
    end)

    UI.Button(C, "Prérequis", 0, -490, 80, function()
        f.mode = (f.mode == "link") and nil or "link"
        TW.Draw()
    end)
    UI.Button(C, "Déplacer", 84, -490, 80, function()
        f.mode = (f.mode == "move") and nil or "move"
        TW.Draw()
    end)
    UI.Button(C, "Supprimer", 168, -490, 80, function() TW.DeleteSelected() end)

    -- ColorBox panel (zones mode)
    f.boxSel = CreateFrame("Frame", nil, f.canvas, "BackdropTemplate")
    f.boxSel:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f.boxSel:SetBackdropBorderColor(1, 1, 1, 1)
    f.boxSel:EnableMouse(false)
    f.boxSel:SetFrameLevel(f.canvas:GetFrameLevel() + 5)
    f.boxSel:Hide()

    local Z = CreateFrame("Frame", nil, Ed)
    Z:SetAllPoints()
    Z:Hide()
    Ed.Z = Z
    UI.Label(Z, "Zones de couleur (ColorBox)", 0, -4, "GameFontNormal")
    Z.Info = UI.Label(Z, "", 0, -26, "GameFontHighlightSmall")
    Z.Info:SetWidth(244)
    Z.Info:SetJustifyV("TOP")
    UI.Button(Z, "Nouvelle zone", 0, -78, 120, function()
        f.zState, f.zCorner, f.zEditId, f.selBox = "c1", nil, nil, nil
        TW.Draw()
    end)
    Z.BtnRedefine = UI.Button(Z, "Redéfinir", 124, -78, 120, function()
        if f.selBox then
            f.zState, f.zCorner, f.zEditId = "c1", nil, f.selBox
            TW.Draw()
        end
    end)
    Z.BtnDelete = UI.Button(Z, "Supprimer", 0, -104, 120, function() TW.DeleteBox() end)
    Z.LC = UI.Label(Z, "Couleur", 0, -144)
    Z.Swatch = CreateFrame("Button", nil, Z)
    Z.Swatch:SetSize(26, 26)
    Z.Swatch:SetPoint("TOPLEFT", 70, -138)
    local swb = Z.Swatch:CreateTexture(nil, "BACKGROUND")
    swb:SetAllPoints()
    swb:SetColorTexture(1, 1, 1, 1)
    Z.SwatchTex = Z.Swatch:CreateTexture(nil, "ARTWORK")
    Z.SwatchTex:SetPoint("TOPLEFT", 2, -2)
    Z.SwatchTex:SetPoint("BOTTOMRIGHT", -2, 2)
    Z.Swatch:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    Z.Swatch:SetScript("OnClick", function() TW.PickBoxColor() end)
    Z.LH = UI.Label(Z, "Hex", 0, -178)
    Z.Hex = UI.Input(Z, 70, -175, 80, 6)
    Z.Hex:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local h = self:GetText():match("^%x%x%x%x%x%x$")
        if h then
            TW.ModifyBox({ r = tonumber(h:sub(1, 2), 16), g = tonumber(h:sub(3, 4), 16), b = tonumber(h:sub(5, 6), 16) })
        end
    end)
    Z.LA = UI.Label(Z, "Opacité %", 0, -204)
    Z.Alpha = UI.Input(Z, 70, -201, 50, 3, true)
    Z.Alpha:SetScript("OnTextChanged", function(self, user)
        if user and tonumber(self:GetText()) then TW.ModifyBox({ a = tonumber(self:GetText()) }) end
    end)

    f:SetScript("OnShow", function() TW.Draw() end)
end

function TW.Toggle()
    if not ADB.talFrame then TW.Create() end
    local f = ADB.talFrame
    if f:IsShown() then f:Hide() else f:Show() end
end
