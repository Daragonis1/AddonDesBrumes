-- Core/Lifecycle.lua : base event handlers, global refresh, minimap button, base slash commands.
-- Other modules append their own PLAYER_LOGIN handlers; they run after this one (TOC order).
local ADB = ADB
local Events, Slash = ADB.Events, ADB.Slash
local format = string.format

------------------------------------------------------------------------------
-- Global refresh
------------------------------------------------------------------------------
function ADB.RefreshAll()
    if not ADB.db or not ADB.playerName then return end
    local UF = ADB.UnitFrames
    UF.RefreshPlayer()
    UF.RefreshTarget(false)
    UF.RefreshMembers()
    UF.RefreshNpcs()
    ADB.ConfigWindow.Refresh()
    ADB.ConfigWindow.RefreshSheet()
    ADB.InventoryWindow.Refresh()
    if ADB.itemFrame and ADB.itemFrame:IsShown() then ADB.ItemCreator.Refresh() end
    ADB.CombatUI.Refresh()
    ADB.Talents.Refresh()
end

------------------------------------------------------------------------------
-- Minimap button (XML: OnDragStart -> ADB.MinimapButtonDrag)
------------------------------------------------------------------------------
function ADB.PositionMinimapButton()
    local a = math.rad(ADB.db.minimap.angle)
    ADBMinimapButton:ClearAllPoints()
    ADBMinimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

function ADB.MinimapButtonDrag()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ADB.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    ADB.PositionMinimapButton()
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------
Events.Register("ADDON_LOADED", function(addon)
    if addon == "AddonDesBrumes" then
        ADB.InitDB()
        C_ChatInfo.RegisterAddonMessagePrefix(ADB.PREFIX)
    elseif addon == "Blizzard_CompactRaidFrames" and ADB.db and ADB.db.replaceUI then
        ADB.UnitFrames.HideBlizzard()
    end
end)

local SPECIAL_FRAMES = { "ADBConfigFrame", "ADBFicheFrame", "ADBNpcCreateFrame", "ADBMJFrame",
    "ADBRestFrame", "ADBInvFrame", "ADBItemFrame", "ADBIconFrame" }

Events.Register("PLAYER_LOGIN", function()
    if not ADB.db then ADB.InitDB() end
    ADB.playerName = UnitName("player")
    ADBPlayerFrame.charName = ADB.playerName
    ADBPlayerFrame.unitToken = "player"
    ADBTargetFrame.unitToken = "target"

    ADB.ConfigWindow.InitDropdowns()
    ADB.InventoryWindow.Create()
    ADB.ItemCreator.Create()
    ADB.Icons.CreateWindow()
    ADB.CombatUI.Create()
    ADB.Talents.Init()
    for _, name in ipairs(SPECIAL_FRAMES) do tinsert(UISpecialFrames, name) end

    ADB.PositionMinimapButton()

    local UF = ADB.UnitFrames
    if ADB.db.replaceUI then
        UF.CopyPosition(PlayerFrame, ADBPlayerFrame, 5)
        UF.CopyPosition(TargetFrame, ADBTargetFrame, 5)
        UF.HideBlizzard()
        ADBPlayerFrame:Show()
        ADBGroupFrame:Show()
        UF.LayoutGroup()
    end
    UF.LayoutNpcs()
    ADB.RefreshAll()
end)

Events.Register("PLAYER_ENTERING_WORLD", function()
    if not ADB.db then return end
    local UF = ADB.UnitFrames
    if ADB.db.replaceUI then UF.HideBlizzard() end
    UF.LayoutGroup()
    UF.LayoutNpcs()
    ADB.RefreshAll()
    C_Timer.After(1, UF.UpdateModels)
    if IsInGroup() then
        ADB.Sync.ScheduleBroadcast(true)
        if ADB.IsGM() then ADB.NPC.ScheduleFull() end
    end
end)

local function OnGroupChanged()
    if not ADB.db or not ADB.playerName then return end
    if not IsInGroup() and ADB.phase ~= "IDLE" then ADB.Combat.SetPhase("IDLE") end
    local present = ADB.Group.GetNames()
    for name in pairs(ADB.roster) do
        if not present[name] then ADB.roster[name] = nil end
    end
    if ADB.IsGM() or not IsInGroup() or (ADB.npcSource and not ADB.IsGMName(ADB.npcSource)) then
        if #ADB.receivedNpcs > 0 then wipe(ADB.receivedNpcs) end
        ADB.npcSource = nil
    end
    ADB.UnitFrames.LayoutGroup()
    ADB.UnitFrames.LayoutNpcs()
    ADB.RefreshAll()
    if IsInGroup() then
        ADB.Sync.ScheduleBroadcast(true)
        if ADB.IsGM() then ADB.NPC.ScheduleFull() end
    end
end
Events.Register("GROUP_ROSTER_UPDATE", OnGroupChanged)
Events.Register("PARTY_LEADER_CHANGED", OnGroupChanged)

local function OnConnectionChanged() ADB.UnitFrames.ScheduleLayout() end
Events.Register("UNIT_CONNECTION", OnConnectionChanged)
Events.Register("PARTY_MEMBER_DISABLE", OnConnectionChanged)
Events.Register("PARTY_MEMBER_ENABLE", OnConnectionChanged)

Events.Register("PLAYER_TARGET_CHANGED", function()
    if not (ADB.db and ADB.playerName) then return end
    ADB.UnitFrames.RefreshTarget(true)
    ADB.InventoryWindow.Refresh()
    if ADB.itemFrame and ADB.itemFrame:IsShown() then ADB.ItemCreator.Refresh() end
end)

Events.Register("UNIT_MODEL_CHANGED", function() ADB.UnitFrames.UpdateModels() end)
Events.Register("PLAYER_REGEN_ENABLED", function() ADB.UnitFrames.OnCombatEnd() end)

------------------------------------------------------------------------------
-- Base slash commands
------------------------------------------------------------------------------
Slash.Register({ "", "config" }, function() ADB.ConfigWindow.Toggle() end)

Slash.Register("fiche", function(rest)
    if rest == "" then return ADB.ConfigWindow.ViewTargetSheet() end
    if rest ~= ADB.playerName and not ADB.IsGM() then
        ADB.Print("Seul le MJ peut consulter la fiche des autres joueurs.")
    elseif ADB.Stats.GetBlock(rest) then
        ADB.ConfigWindow.OpenSheet(rest)
    else
        ADB.Print("Aucune fiche connue pour " .. rest .. ".")
    end
end)

Slash.Register("nom", function(rest)
    ADB.Stats.SetRpName(rest)
    ADB.Print("Nom RP : " .. ADB.Stats.DisplayName(ADB.playerName))
end)

Slash.Register("pnj", function() ADB.GmTools.OpenNpcCreate() end)
Slash.Register({ "mj", "xp" }, function() ADB.GmTools.OpenXp() end)
Slash.Register("combat", function() ADB.Combat.Start() end)
Slash.Register("repos", function() ADB.GmTools.OpenRest() end)
Slash.Register({ "inv", "sac" }, function() ADB.InventoryWindow.Toggle() end)
Slash.Register("objet", function() ADB.ItemCreator.Open() end)
Slash.Register("talents", function() ADB.TalentWindow.Toggle() end)
Slash.Register("ui", function()
    ADB.db.replaceUI = not ADB.db.replaceUI
    ADB.Print("Remplacement de l'interface : " .. (ADB.db.replaceUI and "ACTIVÉ" or "DÉSACTIVÉ")
        .. ". Tapez /reload pour appliquer.")
end)