-- Logic/Alt.lua : secondary "player character". Principle: an alternate context (ADB.db / playerName /
-- action bar / turn state) is swapped by Alt.WithContext, so all existing code (talents, inventory,
-- effects…) runs unchanged on the alt. HP/MP/shield are mirrored with a GM-side allied NPC
-- (owner = "+PlayerName"); the GM is authoritative.
-- Wire (frozen): AS;name;rpName;maxHp;maxMp;hp;mp;shield;race;class;xp;copper;str;agi;int;level  AD (delete)
local ADB = ADB
local Net, UI, Talents = ADB.Net, ADB.UI, ADB.Talents
local floor, max = math.floor, math.max
local format = string.format
local Clamp, Encode, Decode, CleanName = ADB.Clamp, ADB.Encode, ADB.Decode, ADB.CleanName
local ALT_TYPE = ADB.ALT_TYPE

local Alt = {}
ADB.Alt = Alt
Alt.viewTalents, Alt.viewInventory, Alt.popupAlt = false, false, {}
Alt.OfPlayer = function(player) return ADB.Pets.FindAlt(player) end

------------------------------------------------------------------------------
-- Context swap
------------------------------------------------------------------------------
local records = { [false] = {}, [true] = {} }
local lastSig, lastSigTime = nil, 0

local function Swap(to)
    local r = records[not to]
    r.db, r.name, r.bar, r.turnPassed, r.skipTurn = ADB.db, ADB.playerName, ADB.actionBar, ADB.turnPassed, ADB.skipTurn
    r = records[to]
    ADB.db, ADB.playerName, ADB.actionBar, ADB.turnPassed, ADB.skipTurn = r.db, r.name, r.bar, r.turnPassed, r.skipTurn
    ADB.altContext = to or nil
    if to then ADB.db.talents.trees = records[false].db.talents.trees end
end

-- Runs fn in the alt context (to = true) or main context (false). Errors propagate after restoring.
function Alt.WithContext(to, fn, ...)
    to = (to and ADB.altChar) and true or false
    local current = ADB.altContext and true or false
    if to == current then return fn(...) end
    Swap(to)
    local ok, a, b, c = pcall(fn, ...)
    Swap(current)
    if not ok then error(a, 0) end
    return a, b, c
end

local function AltNpc() return ADB.mainName and ADB.Pets.FindAlt(ADB.mainName) end

-- Alt context: pushes state to the GM (+ local copy of the received NPC).
local function SendState(force)
    local a, d = ADB.db, ADB.Stats.GetBlock(ADB.playerName)
    local p = AltNpc()
    if p then p.hp, p.mp, p.shield = a.hp, a.mp, a.shield or 0 end
    if ADB.IsGM() or not IsInGroup() or not ADB.Group.GetGMName() then return end
    local s = format("%s;%s;%d;%d;%d;%d;%d;%s;%s;%d;%d;%d;%d;%d;%d", Encode(a.name), Encode(a.rpName or ""),
        d.maxHp, d.maxMp, a.hp, a.mp, a.shield or 0, Encode(a.race or ""), Encode(a.class or ""),
        a.xp or 0, a.copper or 0, d.strength, d.agility, d.intellect, d.level)
    local t = GetTime()
    if not force and s == lastSig and (p or t < lastSigTime + 10) then return end
    lastSig, lastSigTime = s, t
    Net.Send("AS;" .. s)
end

------------------------------------------------------------------------------
-- Alt action bar (above the pet bar if any, else above the main bar)
------------------------------------------------------------------------------
local function FixBar()
    local b = ADB.altActionBar
    if not b then return end
    for _, btn in ipairs(b.btns) do
        if not btn.adbWrapped then
            btn.adbWrapped = true
            for _, script in ipairs({ "OnEnter", "OnClick" }) do
                local o = btn:GetScript(script)
                btn:SetScript(script, function(...) return Alt.WithContext(true, o, ...) end)
            end
        end
    end
    local pb = ADB.petBar
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", (pb and pb:IsShown()) and pb or ADB.mainActionBar, "TOP", 0, 6)
end

------------------------------------------------------------------------------
-- Portrait: targets the homonymous NPC; dynamic portrait, else "?"
------------------------------------------------------------------------------
local function UpdateMinis()
    for parent, m in pairs(ADB.altMinis) do
        if m:IsShown() and m.alt then
            if not InCombatLockdown() then
                local b = m.targetButton
                if not b then
                    b = CreateFrame("Button", nil, m, "SecureActionButtonTemplate")
                    b:SetSize(44, 44)
                    b:SetPoint("TOPLEFT")
                    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    b:SetAttribute("type1", "macro")
                    b:SetFrameLevel(m:GetFrameLevel() + 10)
                    b:HookScript("OnClick", function(_, btn)
                        if btn == "RightButton" and parent == ADBPlayerFrame then Alt.ToggleSheet() end
                    end)
                    m.targetButton = b
                end
                b:SetAttribute("macrotext1", "/target " .. m.alt)
            end
            local u = ADB.UnitFrames.FindNpcUnit(m.alt)
            if u then
                SetPortraitTexture(m.Icon, u)
                m.Icon:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
end
hooksecurefunc(ADB.UnitFrames, "RefreshMinis", UpdateMinis)
C_Timer.NewTicker(1, UpdateMinis)

------------------------------------------------------------------------------
-- Alt sheet window
------------------------------------------------------------------------------
function Alt.RefreshSheet()
    local f = ADB.altSheet
    if not (f and f:IsShown() and ADB.altChar) then return end
    Alt.WithContext(true, function()
        local d = ADB.Stats.GetBlock(ADB.playerName)
        local xp = d.level >= ADB.MAX_LEVEL and (d.xp .. " (max)") or (d.xp .. " / " .. ADB.XP_THRESHOLDS[d.level + 1])
        f.Body:SetText(format("|cff9d6bff%s|r\n\n|cffffd100Race|r : %s\n|cffffd100Classe|r : %s\n" ..
            "|cffffd100Niveau|r : %d    |cffffd100XP|r : %s\n|cffffd100Or|r : %s\n\n" ..
            "Force : %d   Agilité : %d   Intelligence : %d\n\n|cffff5050PV|r : %d / %d\n|cff5080ffPM|r : %d / %d\n\n" ..
            "Mult. Force : x%.2f\nMult. Agilité : x%.2f\nMult. Intelligence : x%.2f\n\nPoints de talent restants : %d",
            ADB.Stats.DisplayName(ADB.playerName), d.race, d.class, d.level, xp, ADB.FormatMoney(d.copper),
            d.strength, d.agility, d.intellect, d.hp, d.maxHp, d.mp, d.maxMp,
            d.strengthMult, d.agilityMult, d.intellectMult, Talents.PointsLeft()))
        if f.Level and not f.Level:HasFocus() then f.Level:SetText(d.level) end
    end)
end

function Alt.OpenTalents()
    if not ADB.talFrame then ADB.TalentWindow.Create() end
    Alt.viewTalents, Talents.viewClass = true, nil
    ADB.talFrame.sel, ADB.talFrame.mode = nil, nil
    ADB.talFrame:Show()
    ADB.TalentWindow.Draw()
end

function Alt.OpenInventory()
    Alt.viewInventory, ADB.selection = true, nil
    ADB.invFrame:Show()
    ADB.InventoryWindow.Refresh()
end

function Alt.ToggleSheet()
    if not ADB.altChar then
        ADB.Print("Aucun personnage joueur secondaire.")
        return
    end
    local f = ADB.altSheet
    if not f then
        f = UI.BaseWindow("ADBAltFrame", 300, 450, "Personnage secondaire")
        ADB.altSheet = f
        f:SetPoint("CENTER", 260, 40)
        tinsert(UISpecialFrames, "ADBAltFrame")
        f.Body = UI.Label(f, "", 20, -40)
        f.Body:SetWidth(260)
        f.Body:SetJustifyV("TOP")
        f.Body:SetSpacing(4)
        UI.Button(f, "Talents", 50, -384, 200, Alt.OpenTalents)
        UI.Button(f, "Inventaire", 50, -412, 200, Alt.OpenInventory)
        f:SetHeight(480)
        UI.Label(f, "Niveau (1-20)", 20, -446)
        f.Level = UI.Input(f, 120, -443, 40, 2, true)
        UI.Button(f, "Appliquer", 170, -443, 100, function() Alt.SetLevel(tonumber(f.Level:GetText())) end)
        f:SetScript("OnShow", Alt.RefreshSheet)
    end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- Alt context: after any local change.
function Alt.AfterChange()
    SendState()
    ADB.ActionBar.Refresh()
    FixBar()
    Alt.RefreshSheet()
    ADB.InventoryWindow.Refresh()
    Alt.WithContext(false, ADB.UnitFrames.RefreshMinis)
end

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------
local function Validate(s)
    s.race = ADB.RACE_BY_NAME[s.race] and s.race or "Humain"
    s.class = (ADB.CLASS_BY_NAME[s.class] and not ADB.IsSpecialClass(s.class)) and s.class or "Guerrier"
    s.name, s.rpName = CleanName(s.name):sub(1, 30), CleanName(s.rpName or ""):sub(1, 40)
    s.xp = max(0, floor(tonumber(s.xp) or 0))
    s.level = ADB.Stats.LevelForXP(s.xp)
    s.base = type(s.base) == "table" and s.base or { strength = 0, agility = 0, intellect = 0 }
    s.copper = Clamp(floor(tonumber(s.copper) or 0), 0, ADB.COPPER_MAX)
    s.shield = Clamp(floor(tonumber(s.shield) or 0), 0, ADB.SHIELD_MAX)
    local inv, eq = {}, {}
    if type(s.inventory) == "table" then
        for i = 1, ADB.INV_SLOTS do inv[i] = ADB.Items.Validate(s.inventory[i]) end
    end
    if type(s.equipment) == "table" then
        for _, sl in ipairs(ADB.EQUIP_SLOTS) do
            local it = ADB.Items.Validate(s.equipment[sl.key])
            if it and it.kind == "equip" and it.slot == sl.key then eq[sl.key] = it end
        end
    end
    s.inventory, s.equipment = inv, eq
    local t = { talents = { trees = {}, learned = s.learned, cooldowns = s.cooldowns, extraClasses = s.extraClasses } }
    Talents.InitDB(t)
    s.learned, s.cooldowns, s.extraClasses = t.talents.learned, t.talents.cooldowns, t.talents.extraClasses
end

-- Builds the alt context (db proxy: alt fields first, main db as fallback).
local function Prepare()
    local D, a = ADB.db, ADB.db.secondary
    ADB.altChar = (type(a) == "table" and a.type == ALT_TYPE) and a or nil
    if not ADB.altChar then return end
    local P = setmetatable({}, {
        __index = function(_, k)
            if k == "rpName" then return a.rpName end
            local v = a[k]
            if v == nil then v = D[k] end
            return v
        end,
        __newindex = function(_, k, v) a[k] = v end,
    })
    rawset(P, "talents", {
        trees = D.talents.trees,
        learned = a.learned,
        cooldowns = a.cooldowns,
        extraClasses = a.extraClasses
    })
    if not ADB.altActionBar then
        local main = ADB.actionBar
        ADB.ActionBar.Create()
        ADB.altActionBar, ADB.actionBar = ADB.actionBar, main
    end
    ADB.mainActionBar = ADB.actionBar
    records[true].db, records[true].name, records[true].bar = P, a.name, ADB.altActionBar
end

function Alt.Init()
    local s = ADB.db.secondary
    if type(s) == "table" and s.type == ALT_TYPE then
        Validate(s)
        Prepare()
        Alt.WithContext(true, function()
            local d = ADB.Stats.GetBlock(ADB.playerName)
            s.hp = Clamp(floor(tonumber(s.hp) or d.maxHp), 0, d.maxHp)
            s.mp = Clamp(floor(tonumber(s.mp) or d.maxMp), 0, d.maxMp)
        end)
    else
        ADB.altChar = nil
    end
end

function Alt.Save(name, rpName, race, class)
    local s = ADB.db.secondary
    if not (type(s) == "table" and s.type == ALT_TYPE) then
        if IsInGroup() and ADB.Pets.GetPet() then Net.Send("PD") end
        s = { type = ALT_TYPE, xp = ADB.db.xp, copper = 0 }
        ADB.db.secondary = s
    end
    s.name, s.rpName, s.race, s.class = name, rpName, race or "Humain", class or "Guerrier"
    Alt.Init()
    lastSig = nil
    Alt.WithContext(true, Alt.AfterChange)
    ADB.petMenu:Hide()
    ADB.Print("Personnage joueur secondaire enregistré.")
end

function Alt.Delete(silent)
    if IsInGroup() then Net.Send("AD") end
    for i = #ADB.receivedNpcs, 1, -1 do
        if ADB.receivedNpcs[i].owner == "+" .. ADB.mainName then tremove(ADB.receivedNpcs, i) end
    end
    ADB.db.secondary, ADB.altChar, lastSig = nil, nil, nil
    Alt.viewTalents, Alt.viewInventory, ADB.selection = false, false, nil
    for _, f in ipairs({ ADB.altSheet, ADB.altActionBar }) do if f then f:Hide() end end
    ADB.UnitFrames.LayoutNpcs()
    ADB.UnitFrames.RefreshNpcs()
    ADB.InventoryWindow.Refresh()
    ADB.TalentWindow.Draw()
    if not silent then ADB.Print("Personnage secondaire supprimé.") end
end

function Alt.SetLevel(n)
    if not (ADB.altChar and n) then return end
    n = Clamp(floor(n), 1, ADB.MAX_LEVEL)
    local before = Alt.WithContext(true, function() return ADB.Stats.GetBlock(ADB.playerName) end)
    ADB.altChar.xp, ADB.altChar.level = ADB.XP_THRESHOLDS[n], n
    Alt.WithContext(true, function()
        local d, db = ADB.Stats.GetBlock(ADB.playerName), ADB.db
        if db.hp >= before.maxHp then db.hp = d.maxHp end
        if db.mp >= before.maxMp then db.mp = d.maxMp end
        db.hp, db.mp = Clamp(db.hp, 0, d.maxHp), Clamp(db.mp, 0, d.maxMp)
        Talents.CleanupPoints()
        ADB.Sync.AfterLocalChange()
    end)
end

------------------------------------------------------------------------------
-- Pet menu: race / class of the alt
------------------------------------------------------------------------------
local function AltDropdown(f, name, y, list, field)
    local d = CreateFrame("Frame", name, f, "UIDropDownMenuTemplate")
    d:SetPoint("TOPLEFT", 90, y)
    UIDropDownMenu_SetWidth(d, 150)
    UIDropDownMenu_Initialize(d, function(_, level)
        for _, e in ipairs(list) do
            if not ADB.IsSpecialClass(e.name) then
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.checked = e.name, (f[field] == e.name)
                info.func = function()
                    f[field] = e.name
                    UIDropDownMenu_SetText(d, e.name)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    return d
end

hooksecurefunc(ADB.PetUI, "UpdateMenu", function()
    local f = ADB.petMenu
    if not f then return end
    if not f.RaceDrop then
        f.RaceLabel = UI.Label(f, "Race", 16, -151)
        f.RaceDrop = AltDropdown(f, "ADBAltRaceDrop", -144, ADB.RACES, "altRace")
        f.ClassLabel = UI.Label(f, "Classe", 16, -181)
        f.ClassDrop = AltDropdown(f, "ADBAltClasseDrop", -174, ADB.CLASSES, "altClass")
    end
    local on = f.type == ALT_TYPE
    for _, w in ipairs({ f.RaceLabel, f.RaceDrop, f.ClassLabel, f.ClassDrop }) do w:SetShown(on) end
    if on then
        f.altRace, f.altClass = f.altRace or "Humain", f.altClass or "Guerrier"
        UIDropDownMenu_SetText(f.RaceDrop, f.altRace)
        UIDropDownMenu_SetText(f.ClassDrop, f.altClass)
    end
end)

hooksecurefunc(ADB.PetUI, "ToggleMenu", function()
    local f, s = ADB.petMenu, ADB.db and ADB.db.secondary
    if f and f:IsShown() then
        f.altRace, f.altClass = s and s.race, s and s.class
        ADB.PetUI.UpdateMenu()
    end
end)

------------------------------------------------------------------------------
-- Talent / inventory windows: main <-> alt toggle
------------------------------------------------------------------------------
local function WrapWithFlag(tbl, names, flag)
    for _, n in ipairs(names) do
        ADB.Wrap(tbl, n, function(orig, ...) return Alt.WithContext(Alt[flag], orig, ...) end)
    end
end
WrapWithFlag(ADB.TalentWindow, { "Draw", "OnNodeClick", "OnCellClick", "OnNodeEnter", "DeleteSelected" }, "viewTalents")
WrapWithFlag(ADB.InventoryWindow, { "Refresh", "OnSlotClick", "SlotTooltip", "ClickDestroy", "ClickMoney" },
    "viewInventory")

ADB.Wrap(ADB.TalentWindow, "Toggle", function(orig)
    if not (ADB.talFrame and ADB.talFrame:IsShown()) then Alt.viewTalents, Talents.viewClass = false, nil end
    return orig()
end)
ADB.Wrap(ADB.InventoryWindow, "Toggle", function(orig)
    if not ADB.invFrame:IsShown() then Alt.viewInventory, ADB.selection = false, nil end
    return orig()
end)

hooksecurefunc(ADB.TalentWindow, "Draw", function()
    local f = ADB.talFrame
    if f and f.TitleText then
        f.TitleText:SetText(Alt.viewTalents and ADB.altChar and ("Arbre de talents - " .. ADB.altChar.name)
            or "Arbre de talents")
    end
end)

hooksecurefunc(ADB.TalentWindow, "Create", function()
    local f = ADB.talFrame
        f.BtnAlt = UI.Button(f, "Secondaire", f.PX + 126, f.btnY, 120, function()
        Alt.viewTalents, Talents.viewClass = not Alt.viewTalents, nil
        f.sel, f.mode = nil, nil
        ADB.TalentWindow.Draw()
    end)
    local init = f.ClassDrop.initialize
    f.ClassDrop.initialize = function(...) return Alt.WithContext(Alt.viewTalents, init, ...) end
end)

hooksecurefunc(ADB.TalentWindow, "UpdatePanel", function()
    local b = ADB.talFrame and ADB.talFrame.BtnAlt
    if b then
        b:SetShown(ADB.altChar ~= nil)
        b:SetText(Alt.viewTalents and "Principal" or "Secondaire")
    end
end)

-- Moves the selected inventory item to the other character.
function Alt.MoveItem()
    local s, flag = ADB.selection, Alt.viewInventory
    if not (ADB.altChar and s and s.zone == "inv") then return end
    local it = Alt.WithContext(flag, ADB.Items.GetAt, "inv", s.key)
    if not it then return end
    if (Alt.WithContext(not flag, ADB.Items.Add, it, 1) or 0) >= 1 then
        Alt.WithContext(flag, ADB.Items.RemoveAt, s.key)
        ADB.selection = nil
    else
        ADB.Print("Inventaire de destination plein !")
    end
    ADB.InventoryWindow.Refresh()
end

hooksecurefunc(ADB.InventoryWindow, "Create", function()
    local f = ADB.invFrame
    f.AltBtn = UI.Button(f, "Secondaire", 120, -410, 100, function()
        Alt.viewInventory, ADB.selection = not Alt.viewInventory, nil
        ADB.InventoryWindow.Refresh()
    end)
    f.MoveBtn = UI.Button(f, "Vers l'autre", 224, -410, 100, Alt.MoveItem)
end)
hooksecurefunc(ADB.InventoryWindow, "Refresh", function()
    local f = ADB.invFrame
    if not (f and f.AltBtn) then return end
    f.AltBtn:SetShown(ADB.altChar ~= nil)
    f.MoveBtn:SetShown(ADB.altChar ~= nil)
    f.AltBtn:SetText(Alt.viewInventory and "Principal" or "Secondaire")
    f.TitleText:SetText(Alt.viewInventory and ADB.altChar and ("Inventaire - " .. ADB.altChar.name) or "Inventaire")
end)

-- Button in the main sheet (non-GM)
hooksecurefunc(ADB.ConfigWindow, "Refresh", function()
    local f = ADBConfigFrame
    if not (f and f:IsShown() and ADB.db) then return end
    if not f.AltBtn then
        f.AltBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.AltBtn:SetSize(200, 24)
        f.AltBtn:SetText("Fiche du secondaire")
        f.AltBtn:SetScript("OnClick", Alt.ToggleSheet)
    end
    local on = ADB.altChar ~= nil and not ADB.IsGM()
    f.AltBtn:SetShown(on)
    if on then
        f.AltBtn:ClearAllPoints()
        f.AltBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 104)
        f:SetHeight(f:GetHeight() + 28)
    end
end)

------------------------------------------------------------------------------
-- Popups: executed in the context they were opened from (names are frozen)
------------------------------------------------------------------------------
hooksecurefunc("StaticPopup_Show", function(n) Alt.popupAlt[n] = ADB.altContext and true or nil end)
for _, n in ipairs({ "ADB_DETRUIRE", "ADB_POTION", "ADB_DON", "ADB_TAL_UTILISER", "ADB_TAL_HORSTOUR", "ADB_TAL_FORCE" }) do
    local d = StaticPopupDialogs[n]
    local o = d.OnAccept
    d.OnAccept = function(...) return Alt.WithContext(Alt.popupAlt[n], o, ...) end
end
do
    local d = StaticPopupDialogs["ADB_TAL_RESET"]
    local o = d.OnAccept
    d.OnAccept = function(...) return Alt.WithContext(Alt.viewTalents, o, ...) end
end

-- GM-approval requests: tag the origin, replay the answer in the right context.
for _, spec in ipairs({ { Talents, "RequestGmApproval" }, { ADB.Items, "RequestPotionGM" } }) do
    ADB.Wrap(spec[1], spec[2], function(orig, ...)
        local before = Talents.token
        orig(...)
        if ADB.altContext and Talents.token ~= before and Talents.pending[Talents.token] then
            Talents.pending[Talents.token].alt = true
        end
    end)
end

ADB.Wrap(ADB.TalentNet, "Receive", function(orig, cmd, sender, msg)
    if ADB.altContext or not ADB.altChar then return orig(cmd, sender, msg) end
    if cmd == "HR" then
        local _, who, token = strsplit(";", msg)
        local req = who == ADB.playerName and Talents.pending[tonumber(token) or 0]
        if req and req.alt then
            return Alt.WithContext(true, orig, cmd, sender, (msg:gsub("^HR;[^;]*", "HR;" .. ADB.altChar.name)))
        end
    elseif cmd ~= "TQ" and cmd ~= "HQ" then
        Alt.WithContext(true, orig, cmd, sender, msg) -- tree of the alt's class
    end
    return orig(cmd, sender, msg)
end)

------------------------------------------------------------------------------
-- Engine adaptations
------------------------------------------------------------------------------
ADB.Wrap(ADB.Sync, "AfterLocalChange", function(orig)
    if ADB.altContext then return Alt.AfterChange() end
    return orig()
end)

ADB.Wrap(ADB.Combat, "PlayerEndTurn", function(orig)
    if ADB.altContext then
        ADB.turnPassed = true
        ADB.ActionBar.Refresh()
        return
    end
    return orig()
end)

ADB.Wrap(ADB, "Print", function(orig, m)
    if ADB.altContext and ADB.altChar then m = "|cffaaaaaa(" .. ADB.altChar.name .. ")|r " .. m end
    return orig(m)
end)

for _, n in ipairs({ "ReceiveXP", "ReceiveRest" }) do
    ADB.Wrap(ADB.Stats, n, function(orig, v)
        orig(v)
        if ADB.altChar and not ADB.altContext then Alt.WithContext(true, orig, v) end
    end)
end

-- Alt buffs are carried by its NPC ("N:id") on the GM side.
local function BuffKey(k)
    if ADB.altContext and k == "P:" .. ADB.playerName then
        local p = AltNpc()
        if p then return "N:" .. p.id end
    end
    return k
end
ADB.Wrap(ADB.Buffs, "Has", function(orig, k, t) return orig(BuffKey(k), t) end)
ADB.Wrap(ADB.Buffs, "GetBonus", function(orig, k) return orig(BuffKey(k)) end)

-- Effects: the alt is an NPC for the GM; the main character remains a player.
ADB.Wrap(ADB.Measure, "SendEffects", function(orig, list, effect, value)
    if ADB.altContext and IsInGroup() then
        local l = {}
        for i, e in ipairs(list) do
            l[i] = (e.kind == "P" and e.id == ADB.playerName) and { kind = "N", id = e.id, name = e.id } or e
        end
        list = l
    end
    return orig(list, effect, value)
end)

ADB.Wrap(ADB.Measure, "UnitEntry", function(orig, u)
    if ADB.altContext and UnitExists(u) and UnitIsPlayer(u) and UnitName(u) == ADB.mainName then
        return { kind = "P", id = ADB.mainName, name = Alt.WithContext(false, ADB.Stats.DisplayName, ADB.mainName) }
    end
    return orig(u)
end)

------------------------------------------------------------------------------
-- Synchronization / hooks
------------------------------------------------------------------------------
hooksecurefunc(ADB.ActionBar, "Refresh", function()
    if ADB.altContext or not ADB.altChar then return end
    Alt.WithContext(true, ADB.ActionBar.Refresh)
    FixBar()
end)
hooksecurefunc(ADB.PetUI, "Refresh", function() if ADB.altChar then FixBar() end end)

ADB.Combat.OnPhase(function(phase)
    if ADB.altContext or not ADB.altChar then return end
    Alt.WithContext(true, function()
        if phase == "PLAYER_TURN" then ADB.turnPassed = false end
        Talents.OnPhase(phase)
    end)
    FixBar()
end)

-- HP/MP/shield: mirror of the GM NPC
hooksecurefunc(ADB.UnitFrames, "RefreshNpcs", function()
    if ADB.altContext or not ADB.altChar then return end
    local p = AltNpc()
    if p then
        Alt.WithContext(true, function()
            local a, d = ADB.db, ADB.Stats.GetBlock(ADB.playerName)
            a.hp, a.mp, a.shield = Clamp(p.hp, 0, d.maxHp), Clamp(p.mp, 0, d.maxMp), p.shield or 0
            ADB.ActionBar.Refresh()
        end)
        FixBar()
        Alt.RefreshSheet()
    end
end)

hooksecurefunc(ADB, "RefreshAll", function()
    if ADB.altContext or not ADB.altChar then return end
    Alt.WithContext(true, function()
        ADB.TalentNet.RequestTrees()
        if not AltNpc() then SendState() end
    end)
    Alt.RefreshSheet()
end)

-- GM side: AS (state) / AD (delete)
local function GmReceive(sender, message, cmd)
    if not (ADB.IsGM() and ADB.roster[sender]) then return end
    local p, owner, pn = Net.Split(message), "+" .. sender, nil
    for _, x in ipairs(ADB.db.npcs) do
        if x.owner == owner then
            pn = x
            break
        end
    end
    if cmd == "AD" then
        if pn then ADB.NPC.Delete(pn.id) end
        return
    end
    local name, rp = CleanName(Decode(p[2] or "")):sub(1, 30), CleanName(Decode(p[3] or "")):sub(1, 40)
    if name == "" then return end
    local maxHp = Clamp(floor(tonumber(p[4]) or 1), 1, ADB.NPC_STAT_MAX)
    local maxMp = Clamp(floor(tonumber(p[5]) or 0), 0, ADB.NPC_STAT_MAX)
    if not pn then
        if #ADB.db.npcs >= ADB.NPC_MAX then return end
        local id = ADB.db.nextNpcId
        ADB.db.nextNpcId = id + 1
        pn = { id = id, ally = true, owner = owner }
        table.insert(ADB.db.npcs, pn)
    end
    pn.name, pn.rpName, pn.maxHp, pn.maxMp = name, rp ~= "" and rp or nil, maxHp, maxMp
    pn.hp = Clamp(floor(tonumber(p[6]) or maxHp), 0, maxHp)
    pn.mp = Clamp(floor(tonumber(p[7]) or 0), 0, maxMp)
    pn.shield = Clamp(floor(tonumber(p[8]) or 0), 0, ADB.SHIELD_MAX)
    local race, class = Decode(p[9] or ""), Decode(p[10] or "")
    pn.race, pn.class = ADB.RACE_BY_NAME[race] and race or "?", ADB.CLASS_BY_NAME[class] and class or "?"
    pn.xp = max(0, floor(tonumber(p[11]) or 0))
    pn.level = ADB.Stats.LevelForXP(pn.xp)
    pn.copper = Clamp(floor(tonumber(p[12]) or 0), 0, ADB.COPPER_MAX)
    pn.strength, pn.agility, pn.intellect = floor(tonumber(p[13]) or 0), floor(tonumber(p[14]) or 0),
        floor(tonumber(p[15]) or 0)
    ADB.NPC.Schedule(pn.id)
    ADB.UnitFrames.LayoutNpcs()
    ADB.UnitFrames.RefreshNpcs()
end
Net.RegisterMany({ "AS", "AD" }, GmReceive)

ADB.Events.Register("PLAYER_LOGIN", function()
    ADB.mainName = ADB.playerName
    Alt.Init()
    ADB.RefreshAll()
end)
