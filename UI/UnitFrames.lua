-- UI/UnitFrames.lua : replacement unit frames (player / target / group / NPC / minis), bar interaction,
-- native context menu, Blizzard frame hiding. Merges the old Cadres.lua + the frame code of AddonDesBrumes.lua.
local ADB = ADB
local floor, min, max = math.floor, math.min, math.max
local format = string.format

local UF = {}
ADB.UnitFrames = UF
ADB.petMinis, ADB.altMinis = {}, {} -- registries: parent frame -> mini frame

local TEX = "Interface\\TargetingFrame\\"
local BAR_TEXTURE = TEX .. "UI-StatusBar"
local PITCH, LEGACY_PITCH = 55, 47
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local TARGET_ART = {
    elite = TEX .. "UI-TargetingFrame-Elite",
    worldboss = TEX .. "UI-TargetingFrame-Elite",
    rareelite = TEX .. "UI-TargetingFrame-Rare-Elite",
    rare = TEX .. "UI-TargetingFrame-Rare",
}

local function Pitch() return ADB.db and ADB.db.replaceUI and PITCH or LEGACY_PITCH end

------------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------------
local function StyleBar(b, f, x, y, w, h, small)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    b:SetSize(w, h)
    b:SetStatusBarTexture(BAR_TEXTURE)
    b.blizz = true
    local st = b:GetStatusBarTexture()
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= st and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    b.Text:SetFontObject(GameFontHighlightSmall)
    if small then
        b.Text:Hide()
        b:HookScript("OnEnter", function(s) s.Text:Show() end)
        b:HookScript("OnLeave", function(s) s.Text:Hide() end)
    end
end

local function Background(f, x, y, w, h)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(0, 0, 0, 0.5)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    return t
end

local function SetPortrait(f, unit)
    if f.Portrait and unit and UnitExists(unit) then SetPortraitTexture(f.Portrait, unit) end
end

-- Overlay frame that carries the frame art and the name text.
local function CreateArt(f)
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

-- Player (isPlayer) or target frame.
function UF.InitFrame(f)
    local isPlayer = f:GetName() == "ADBPlayerFrame"
    f:SetSize(175, 76)
    local a = CreateArt(f)
    local px = isPlayer and 42 or 126
    local bx = isPlayer and 106 or 7
    f.Background = Background(f, bx, -22, 119, 41)
    f.Portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.Portrait:SetSize(64, 64)
    f.Portrait:SetPoint("TOPLEFT", f, "TOPLEFT", px, -12)
    if not isPlayer then
        f.NameBackground = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        f.NameBackground:SetTexture(TEX .. "UI-TargetingFrame-LevelBackground")
        f.NameBackground:SetSize(119, 19)
        f.NameBackground:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -22)
    end
    a.Tex = a:CreateTexture(nil, "ARTWORK")
    a.Tex:SetSize(232, 100)
    a.Tex:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    a.Tex:SetTexture(TEX .. "UI-TargetingFrame")
    if isPlayer then a.Tex:SetTexCoord(1, 0.09375, 0, 0.78125) else a.Tex:SetTexCoord(0.09375, 1, 0, 0.78125) end
    f.NameText:SetSize(96, 12)
    f.NameText:SetJustifyH("CENTER")
    f.NameText:ClearAllPoints()
    f.NameText:SetPoint("TOPLEFT", f, "TOPLEFT", isPlayer and 118 or 18, -25)
    f.Level = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.Level:SetPoint("CENTER", f, "TOPLEFT", isPlayer and 53 or 179, -66)
    StyleBar(f.HP, f, bx, -41, 119, 12)
    StyleBar(f.MP, f, bx, -52, 119, 12)
end

local function BuildSmallFrame(f)
    f:SetSize(120, 53)
    local a = CreateArt(f)
    f.Background = Background(f, 46, -11, 71, 18)
    a.Tex = a:CreateTexture(nil, "ARTWORK")
    a.Tex:SetSize(128, 64)
    a.Tex:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    a.Tex:SetTexture(TEX .. "UI-PartyFrame")
    f.NameText:SetSize(70, 12)
    f.NameText:SetJustifyH("LEFT")
    f.NameText:ClearAllPoints()
    f.NameText:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -1)
    StyleBar(f.HP, f, 47, -12, 70, 7, true)
    StyleBar(f.MP, f, 47, -20, 70, 7, true)
end

-- Group member frame (XML template ADBMemberTemplate).
function UF.OnMemberLoad(self)
    self:RegisterForClicks("AnyUp")
    self:SetAttribute("type1", "target")
    self.HP.kind = "hp"
    self.MP.kind = "mp"
    self:HookScript("OnMouseUp", UF.OnPortraitMouseUp)
    BuildSmallFrame(self)
    self.Portrait = self:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.Portrait:SetSize(37, 37)
    self.Portrait:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -6)
end

-- NPC frame (XML template ADBNpcTemplate).
function UF.OnNpcLoad(self)
    self.HP.kind = "hp"
    self.MP.kind = "mp"
    if not (ADB.db and ADB.db.replaceUI) then
        ADB.UI.ApplyBackdrop(self)
        self.NameText:SetWordWrap(false)
        return
    end
    BuildSmallFrame(self)
    self.Icon:ClearAllPoints()
    self.Icon:SetSize(37, 37)
    self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -6)
    self.Icon:SetDrawLayer("BACKGROUND", 1)
    self.Delete:SetFrameLevel(self:GetFrameLevel() + 10)
end

------------------------------------------------------------------------------
-- Bars
------------------------------------------------------------------------------
function UF.UpdateBar(bar, cur, maxValue, shield)
    local isHp = bar.kind == "hp"
    if cur and maxValue then
        bar:SetMinMaxValues(0, max(maxValue, 1))
        bar:SetValue(cur)
        bar.Text:SetText(cur .. "/" .. maxValue .. ((shield and shield > 0) and (" (+" .. shield .. ")") or ""))
        if isHp then
            if bar.blizz then bar:SetStatusBarColor(0, 1, 0) else bar:SetStatusBarColor(0.75, 0.10, 0.15) end
        else
            if bar.blizz then bar:SetStatusBarColor(0, 0, 1) else bar:SetStatusBarColor(0.20, 0.40, 0.90) end
        end
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar.Text:SetText("?")
        if isHp then bar:SetStatusBarColor(1, 0, 0) else bar:SetStatusBarColor(0, 0, 1) end
    end
end

function UF.EnemyText(bar)
    local x = ADB.Measure.enemyDamage[UnitGUID("target") or ""]
    bar.Text:SetText((ADB.phase ~= "IDLE" and x and x > 0) and ("-" .. x) or "?")
end

StaticPopupDialogs["ADB_SAISIE_VALEUR"] = {
    text = "Nouvelle valeur pour %s (0 à %s) :",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 4,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnShow = function(self, data)
        self.editBox:SetNumeric(true)
        self.editBox:SetText(tostring(data and data.current or 0))
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self, data) UF.ValidateInput(data, self.editBox:GetText()) end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        UF.ValidateInput(parent.data, self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

-- data = { name, kind } | { npcId, kind } | { guid } (enemy damage)
function UF.ValidateInput(data, text)
    local v = tonumber(text)
    if not (data and v) then return end
    if data.guid then
        ADB.Measure.AddDamage(data.guid, floor(v) - (ADB.Measure.enemyDamage[data.guid] or 0))
    elseif data.npcId then
        ADB.NPC.ApplyValue(data.npcId, data.kind, v)
    elseif ADB.Group.CanEdit(data.name) then
        ADB.Stats.ApplyValue(data.name, data.kind, v)
    end
end

function UF.OpenInput(name, kind)
    local d = ADB.Stats.GetBlock(name)
    if not d then return end
    local label = (kind == "hp" and "PV" or "PM") .. " de " .. ADB.Stats.DisplayName(name)
    StaticPopup_Show("ADB_SAISIE_VALEUR", label, d[ADB.Stats.MAX_KEY[kind]],
        { name = name, kind = kind, current = d[kind] })
end

function UF.OnEnemyBarClick(bar, button)
    if not ADB.IsGM() then
        UIErrorsFrame:AddMessage("Seul le MJ peut modifier cette valeur.", 1, 0.3, 0.3)
        return
    end
    if bar.kind ~= "hp" then return end
    local guid = UnitGUID("target")
    if not guid then return end
    if IsShiftKeyDown() then
        StaticPopup_Show("ADB_SAISIE_VALEUR", "dégâts subis de " .. (UnitName("target") or "?"), "9999",
            { guid = guid, kind = "dmg", current = ADB.Measure.enemyDamage[guid] or 0 })
    elseif button == "RightButton" then
        ADB.Measure.AddDamage(guid, 1)
    elseif button == "LeftButton" then
        ADB.Measure.AddDamage(guid, -1)
    end
end

function UF.OnNpcBarClick(bar, id, button)
    if not ADB.IsGM() then
        UIErrorsFrame:AddMessage("Seul le MJ peut modifier les PNJ.", 1, 0.3, 0.3)
        return
    end
    local p = ADB.NPC.FindById(ADB.db.npcs, id)
    if not p then return end
    local kind = bar.kind
    if kind == "hp" and IsControlKeyDown() then
        ADB.NPC.ApplyValue(id, "shield", (p.shield or 0) + (button == "RightButton" and -1 or 1))
    elseif kind == "hp" and IsShiftKeyDown() then
        ADB.CombatUI.OpenHpInput(nil, id)
    elseif IsShiftKeyDown() then
        local label = (kind == "hp" and "PV" or "PM") .. " de " .. p.name
        StaticPopup_Show("ADB_SAISIE_VALEUR", label, p[ADB.Stats.MAX_KEY[kind]],
            { npcId = id, kind = kind, current = p[kind] })
    elseif button == "LeftButton" then
        ADB.NPC.ApplyValue(id, kind, p[kind] + 1)
    elseif button == "RightButton" then
        ADB.NPC.ApplyValue(id, kind, p[kind] - 1)
    end
end

-- XML: <OnMouseUp>ADB.UnitFrames.OnBarClick(self, button)</OnMouseUp>
function UF.OnBarClick(bar, button)
    local parent = bar:GetParent()
    if parent.npcId then return UF.OnNpcBarClick(bar, parent.npcId, button) end
    if parent == ADBTargetFrame and not parent.charName and not parent.npcId then
        return UF.OnEnemyBarClick(bar, button)
    end
    local name = parent.charName
    if not name or not ADB.Group.CanEdit(name) then return end
    if bar.kind == "hp" and IsControlKeyDown() then
        ADB.Stats.ChangeValue(name, "shield", button == "RightButton" and -1 or 1)
    elseif IsShiftKeyDown() then
        if bar.kind == "hp" then ADB.CombatUI.OpenHpInput(name) else UF.OpenInput(name, bar.kind) end
    elseif button == "LeftButton" then
        ADB.Stats.ChangeValue(name, bar.kind, 1)
    elseif button == "RightButton" then
        ADB.Stats.ChangeValue(name, bar.kind, -1)
    end
end

-- XML: <OnEnter>ADB.UnitFrames.ShowBarTooltip(self)</OnEnter>
function UF.ShowBarTooltip(bar)
    if not ADB.IsGM() then return end
    local p = bar:GetParent()
    local editable
    if p.npcId then
        editable = true
    elseif p.charName then
        editable = ADB.Group.CanEdit(p.charName)
    else
        editable = true
    end
    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:AddLine(bar.kind == "hp" and "Points de vie" or "Points de mana", 1, 1, 1)
    if editable then
        GameTooltip:AddLine("Clic gauche : +1", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Clic droit : -1", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Maj + clic : saisir une valeur", 0.8, 0.8, 0.8)
        if bar.kind == "hp" then GameTooltip:AddLine("Ctrl + clic : bouclier +1 (droit : -1)", 0.8, 0.8, 0.8) end
    end
    GameTooltip:Show()
end

------------------------------------------------------------------------------
-- Native context menu
------------------------------------------------------------------------------
local function MenuType(unit)
    if UnitIsUnit(unit, "player") then return "SELF" end
    if UnitIsPlayer(unit) then
        if UnitInRaid(unit) then return "RAID_PLAYER" end
        if UnitInParty(unit) then return "PARTY" end
        return "PLAYER"
    end
    if UnitIsUnit(unit, "pet") then return "PET" end
    if UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit) then return "OTHERPET" end
    return "TARGET"
end

local function InitMenu(self)
    local unit = ADB.menuUnit
    if not unit or not UnitExists(unit) then return end
    UnitPopup_ShowMenu(self, MenuType(unit), unit, UnitName(unit))
end

function UF.OpenMenu(unit)
    if not unit or not UnitExists(unit) then return end
    if not ADB.menuFrame then
        ADB.menuFrame = CreateFrame("Frame", "ADBDropDown", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(ADB.menuFrame, InitMenu, "MENU")
    end
    CloseDropDownMenus()
    ADB.menuUnit = unit
    ToggleDropDownMenu(1, nil, ADB.menuFrame, "cursor", 0, 0)
end

function UF.OnPortraitMouseUp(self, button)
    if button ~= "RightButton" then return end
    if self.unitToken then UF.OpenMenu(self.unitToken) end
end

------------------------------------------------------------------------------
-- Refresh: player / target / members
------------------------------------------------------------------------------
function UF.RefreshPlayer()
    local f = ADBPlayerFrame
    local d = ADB.Stats.GetBlock(ADB.playerName)
    if not d or not f.Level then return end
    f.NameText:SetText(ADB.Stats.DisplayName(ADB.playerName))
    f.Level:SetText(d.level)
    UF.UpdateBar(f.HP, d.hp, d.maxHp, d.shield)
    UF.UpdateBar(f.MP, d.mp, d.maxMp)
end

function UF.RefreshTarget()
    local f = ADBTargetFrame
    if not ADB.db or not ADB.db.replaceUI or not f.Art then return end
    if not UnitExists("target") then
        f.charName, f.npcId = nil, nil
        f:Hide()
        return
    end
    f:Show()
    local name, isPlayer = UnitName("target"), UnitIsPlayer("target")
    f.charName = isPlayer and name or nil
    local p = (not isPlayer) and ADB.NPC.FindByName(name) or nil
    f.npcId = p and p.id or nil
    local d = f.charName and ADB.Stats.GetBlock(f.charName)
    local class = UnitClassification("target")
    local level, color
    if d then
        level = d.level
    else
        local l = UnitLevel("target") or 0
        if class == "worldboss" or l <= 0 then level = "??" else level = l end
        if l > 0 and class ~= "worldboss" then color = GetQuestDifficultyColor(l) end
    end
    f.Art.Tex:SetTexture(TARGET_ART[class] or (TEX .. "UI-TargetingFrame"))
    f.NameBackground:SetVertexColor(UnitSelectionColor("target"))
    f.NameText:SetText(d and ADB.Stats.DisplayName(f.charName) or (p and ADB.NPC.DisplayName(p)) or name or "")
    f.Level:SetText(level)
    if color then f.Level:SetTextColor(color.r, color.g, color.b) else f.Level:SetTextColor(1, 0.82, 0) end
    SetPortrait(f, "target")
    local src = d or p
    UF.UpdateBar(f.HP, src and src.hp, src and src.maxHp, src and src.shield)
    UF.UpdateBar(f.MP, src and src.mp, src and src.maxMp)
    if not src then UF.EnemyText(f.HP) end
    f.SheetButton:SetShown(d ~= nil and f.charName ~= ADB.playerName and ADB.IsGM())
end

function UF.SetDistanceText(text)
    local t = ADBTargetFrame
    if not t then return end
    if not t.Dist then
        t.Dist = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t.Dist:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 6, -3)
    end
    t.Dist:SetText(text)
end

function UF.RefreshMembers()
    for _, b in ipairs(ADB.memberFrames) do
        if b:IsShown() and b.charName then
            local ok = ADB.Group.IsMemberDisplayable(b.unitToken, b.charName) and UnitName(b.unitToken) == b.charName
            b:SetAlpha(ok and 1 or 0)
            if ok then
                local d = ADB.Stats.GetBlock(b.charName)
                b.NameText:SetText(ADB.Stats.DisplayName(b.charName))
                UF.UpdateBar(b.HP, d and d.hp, d and d.maxHp, d and d.shield)
                UF.UpdateBar(b.MP, d and d.mp, d and d.maxMp)
            end
        end
    end
end

local function RefreshAllPortraits()
    SetPortrait(ADBPlayerFrame, "player")
    SetPortrait(ADBTargetFrame, "target")
    for _, b in ipairs(ADB.memberFrames) do
        if b.unitToken then SetPortrait(b, b.unitToken) end
    end
end

function UF.UpdateModels()
    if not ADB.db or not ADB.db.replaceUI then return end
    UF.RefreshTarget()
    RefreshAllPortraits()
end

------------------------------------------------------------------------------
-- Layout: group
------------------------------------------------------------------------------
local layoutPending, layoutScheduled = false, false

local function GetMemberFrame(i)
    if not ADB.memberFrames[i] then
        ADB.memberFrames[i] = CreateFrame("Button", "ADBMember" .. i, ADBGroupFrame, "ADBMemberTemplate")
    end
    return ADB.memberFrames[i]
end

function UF.LayoutGroup()
    if not ADB.db then return end
    if not ADB.db.replaceUI then
        ADB.memberRows = 0
        UF.LayoutNpcs()
        return
    end
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    layoutPending = false
    local list = ADB.Group.ListDisplayedMembers()
    for i, m in ipairs(list) do
        local b = GetMemberFrame(i)
        b:SetScale(UF.GetScale("groupScale"))
        local col = floor((i - 1) / ADB.MEMBERS_PER_COLUMN)
        local row = (i - 1) % ADB.MEMBERS_PER_COLUMN
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ADBGroupFrame, "TOPLEFT", col * 219, -row * PITCH)
        b:SetAttribute("unit", m.unit)
        b.unitToken = m.unit
        b.charName = m.name
        b:SetAlpha(1)
        b:Show()
    end
    for i = #list + 1, #ADB.memberFrames do
        local b = ADB.memberFrames[i]
        b.charName, b.unitToken = nil, nil
        b:Hide()
    end
    ADB.memberRows = min(#list, ADB.MEMBERS_PER_COLUMN)
    UF.RefreshMembers()
    UF.LayoutNpcs()
    RefreshAllPortraits()
end

function UF.ScheduleLayout()
    if layoutScheduled then return end
    layoutScheduled = true
    C_Timer.After(0.2, function()
        layoutScheduled = false
        UF.LayoutGroup()
        ADB.RefreshAll()
    end)
end

function UF.GetScale(key)
    local s = ADB.db and ADB.db.settings and tonumber(ADB.db.settings[key])
    return s or 1
end

local scalePending
function UF.ApplyScales()
    if not ADB.db or not ADBPlayerFrame then return end
    ADBTargetFrame:SetScale(UF.GetScale("targetScale"))
    if InCombatLockdown() then
        scalePending = true -- cadres sécurisés : SetScale interdit en combat
    else
        scalePending = false
        ADBPlayerFrame:SetScale(UF.GetScale("playerScale"))
        local g = UF.GetScale("groupScale")
        for _, b in ipairs(ADB.memberFrames) do b:SetScale(g) end
    end
    UF.LayoutNpcs()
    UF.RefreshMinis()
end

------------------------------------------------------------------------------
-- NPC frames
------------------------------------------------------------------------------
local function GetNpcFrame(i)
    if not ADB.npcFrames[i] then
        ADB.npcFrames[i] = CreateFrame("Frame", "ADBNpc" .. i, ADBNpcFrame, "ADBNpcTemplate")
    end
    return ADB.npcFrames[i]
end

function UF.LayoutNpcs()
    if not ADB.db or not ADBNpcFrame then return end
    local pitch = Pitch()
    ADBNpcFrame:ClearAllPoints()
    ADBNpcFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5,
        -(130 + ADB.memberRows * pitch * UF.GetScale("groupScale") + 8))
    local list = {}
    for _, p in ipairs(ADB.NPC.List()) do
        if not p.owner then list[#list + 1] = p end
    end
    for i, p in ipairs(list) do
        local f = GetNpcFrame(i)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", ADBNpcFrame, "TOPLEFT",
            floor((i - 1) / ADB.MEMBERS_PER_COLUMN) * 123, -24 - ((i - 1) % ADB.MEMBERS_PER_COLUMN) * pitch)
        f.npcId = p.id
        f:Show()
    end
    for i = #list + 1, #ADB.npcFrames do
        ADB.npcFrames[i].npcId = nil
        ADB.npcFrames[i]:Hide()
    end
    UF.RefreshNpcs()
    UF.UpdateTargeting()
    UF.UpdatePortraits()
end

function UF.RefreshNpcs()
    if not ADB.db then return end
    local list, isGM = ADB.NPC.List(), ADB.IsGM()
    for _, f in ipairs(ADB.npcFrames) do
        if f:IsShown() and f.npcId then
            local p = ADB.NPC.FindById(list, f.npcId)
            if p then
                f.NameText:SetText("|cff" .. (p.ally and "40ff40" or "ffa040") .. ADB.NPC.DisplayName(p) .. "|r")
                UF.UpdateBar(f.HP, p.hp, p.maxHp, p.shield)
                UF.UpdateBar(f.MP, p.mp, p.maxMp)
                f.Delete:SetShown(isGM)
            end
        end
    end
    if ADBNpcFrame then
        ADBNpcFrame.CreateButton:SetShown(isGM)
        ADBNpcFrame.RestButton:SetShown(isGM)
        ADBNpcFrame.XPButton:SetShown(isGM)
    end
    UF.RefreshTarget()
    UF.UpdateTargeting()
    UF.UpdatePortraits()
end

StaticPopupDialogs["ADB_SUPPRIMER_PNJ"] = {
    text = "Supprimer le PNJ « %s » du groupe ?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    OnAccept = function(_, data) ADB.NPC.Delete(data) end,
}

-- XML: Delete button OnClick
function UF.RequestDeleteNpc(frame)
    if not ADB.IsGM() or not frame.npcId then return end
    local p = ADB.NPC.FindById(ADB.db.npcs, frame.npcId)
    if p then StaticPopup_Show("ADB_SUPPRIMER_PNJ", p.name, nil, p.id) end
end

-- Click on an NPC portrait: "/target <real name>" through a secure button (works in combat).
local targetingPending
function UF.UpdateTargeting()
    if InCombatLockdown() then
        targetingPending = true
        return
    end
    targetingPending = false
    local list = ADB.NPC.List()
    for _, f in ipairs(ADB.npcFrames) do
        local b = f.targetButton
        local p = (f:IsShown() and f.npcId) and ADB.NPC.FindById(list, f.npcId) or nil
        if p then
            if not b then
                b = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
                b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                b:SetSize(44, 44)
                b:RegisterForClicks("LeftButtonUp")
                b:SetAttribute("type1", "macro")
                b:SetFrameLevel(f:GetFrameLevel() + 6)
                f.targetButton = b
            end
            b:SetAttribute("macrotext1", "/target " .. ADB.NPC.DisplayName(p))
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

-- Visible unit with the given (non-player) name, if any.
function UF.FindNpcUnit(name)
    local function Match(u)
        return UnitExists(u) and not UnitIsPlayer(u) and UnitName(u) == name and UnitIsVisible(u)
    end
    for _, u in ipairs({ "target", "focus", "mouseover" }) do
        if Match(u) then return u end
    end
    for i = 1, 40 do
        if Match("nameplate" .. i) then return "nameplate" .. i end
    end
    for _, u in ipairs(ADB.Group.ListUnits()) do
        if Match(u .. "target") then return u .. "target" end
    end
end

-- Dynamic NPC portrait: copies the visible unit's portrait, else keeps the last one (or "?").
function UF.UpdatePortraits()
    if not ADB.db or not ADB.npcFrames then return end
    local list = ADB.NPC.List()
    for _, f in ipairs(ADB.npcFrames) do
        if f:IsShown() and f.npcId and f.Icon then
            if f.portraitId ~= f.npcId then -- frame reassigned to another NPC: back to "?"
                f.portraitId = f.npcId
                f.Icon:SetTexture(QUESTION_MARK)
                f.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end
            local p = ADB.NPC.FindById(list, f.npcId)
            local u = p and UF.FindNpcUnit(p.name)
            if u then
                SetPortraitTexture(f.Icon, u)
                f.Icon:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
end

------------------------------------------------------------------------------
-- Mini frames (alt + pet) under/next to the owner's frame
------------------------------------------------------------------------------
local function CreateMiniBar(f, y)
    local b = CreateFrame("StatusBar", nil, f, "ADBBarTemplate")
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 47, y)
    b:SetSize(70, 7)
    b:SetStatusBarTexture(BAR_TEXTURE)
    b.blizz = true
    local st = b:GetStatusBarTexture()
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= st and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    b.Text:SetFontObject(GameFontHighlightSmall)
    b.Text:Hide()
    b:HookScript("OnEnter", function(s) s.Text:Show() end)
    b:HookScript("OnLeave", function(s) s.Text:Hide() end)
    return b
end

local function CreateMini(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(120, 53)
    f:SetScale(0.8)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetSize(71, 18)
    bg:SetPoint("TOPLEFT", 46, -11)
    f.Icon = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.Icon:SetSize(37, 37)
    f.Icon:SetPoint("TOPLEFT", 7, -6)
    f.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local a = CreateFrame("Frame", nil, f)
    a:SetAllPoints()
    a:SetFrameLevel(f:GetFrameLevel() + 5)
    a:EnableMouse(false)
    local t = a:CreateTexture(nil, "ARTWORK")
    t:SetSize(128, 64)
    t:SetPoint("TOPLEFT")
    t:SetTexture(TEX .. "UI-PartyFrame")
    f.Name = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.Name:SetSize(70, 12)
    f.Name:SetJustifyH("LEFT")
    f.Name:SetWordWrap(false)
    f.Name:SetPoint("TOPLEFT", 46, -1)
    f.HP = CreateMiniBar(f, -12)
    f.HP.kind = "hp"
    f.MP = CreateMiniBar(f, -20)
    f.MP.kind = "mp"
    return f
end

function UF.RefreshMinis()
    local targets = {}
    if ADB.db.replaceUI then
        targets[1] = { ADBPlayerFrame, ADB.playerName, false }
        for _, b in ipairs(ADB.memberFrames) do
            if b:IsShown() and b.charName then targets[#targets + 1] = { b, b.charName, true } end
        end
    end
    local seen = {}
    for _, c in ipairs(targets) do
        local parent, prev = c[1], nil
        for k = 1, 2 do -- k = 1: alt character, k = 2: pet
            local p = (k == 1 and ADB.Pets.FindAlt or ADB.Pets.FindByOwner)(c[2])
            if p then
                local registry = k == 1 and ADB.altMinis or ADB.petMinis
                local m = registry[parent]
                if not m then
                    m = CreateMini(parent)
                    registry[parent] = m
                end
                m:ClearAllPoints()
                if prev then
                    m:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                elseif c[3] then
                    m:SetPoint("LEFT", parent, "RIGHT", 2, 0)
                else
                    m:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 10, 0)
                end
                prev = m
                m:SetScale(c[3] and 0.8 or (0.8 * UF.GetScale("petScale") / UF.GetScale("playerScale")))
                m.npcId = p.id
                if k == 1 then
                    if m.alt ~= p.name then
                        m.alt = p.name
                        m.Icon:SetTexture(ADB.IconTexture("INV_Misc_QuestionMark"))
                        m.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    end
                else
                    local T = ADB.PET_TYPES[p.petType or ""]
                    m.Icon:SetTexture(ADB.IconTexture(T and T.icon or "INV_Misc_QuestionMark"))
                end
                m.Name:SetText("|cff40ff40" .. ADB.NPC.DisplayName(p) .. "|r")
                UF.UpdateBar(m.HP, p.hp, p.maxHp, p.shield)
                UF.UpdateBar(m.MP, p.mp, p.maxMp)
                m.MP:SetShown(p.maxMp > 0)
                m:Show()
                seen[m] = true
            end
        end
    end
    for _, registry in ipairs({ ADB.petMinis, ADB.altMinis }) do
        for _, m in pairs(registry) do
            if not seen[m] then
                m.npcId = nil
                m:Hide()
            end
        end
    end
end

------------------------------------------------------------------------------
-- Blizzard UI hiding / positions
------------------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()
local hidePending = false

local function Hide(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetParent(hider)
    frame:Hide()
end

function UF.HideBlizzard()
    if InCombatLockdown() then
        hidePending = true
        return
    end
    hidePending = false
    Hide(PlayerFrame)
    Hide(TargetFrame)
    for i = 1, 4 do Hide(_G["PartyMemberFrame" .. i]) end
    if CompactRaidFrameManager_SetSetting then CompactRaidFrameManager_SetSetting("IsShown", "0") end
    Hide(CompactRaidFrameManager)
    Hide(CompactRaidFrameContainer)
    Hide(CompactPartyFrame)
end

function UF.CopyPosition(source, target, minX)
    if not source or not source.GetPoint then return end
    local point, rel, relPoint, x, y = source:GetPoint(1)
    if point and (rel == nil or rel == UIParent) then
        target:ClearAllPoints()
        target:SetPoint(point, UIParent, relPoint or point, max(x or 0, minX or 0), y or 0)
    end
end

function UF.OnCombatEnd()
    if hidePending then UF.HideBlizzard() end
    if layoutPending then UF.LayoutGroup() end
    if targetingPending then UF.UpdateTargeting() end
    if scalePending then UF.ApplyScales() end
end

------------------------------------------------------------------------------
-- Portrait refresh events / ticker
------------------------------------------------------------------------------
local frameEvents = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do frameEvents:RegisterEvent(e) end
frameEvents:SetScript("OnEvent", function()
    if ADB.db and ADB.db.replaceUI then RefreshAllPortraits() end
end)

local npcPortraitEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do npcPortraitEvents:RegisterEvent(e) end
npcPortraitEvents:SetScript("OnEvent", UF.UpdatePortraits)
C_Timer.NewTicker(1, UF.UpdatePortraits)
