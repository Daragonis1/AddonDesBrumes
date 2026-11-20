-- Logic/Boss.lua : boss health bars at the top of the screen (Dark Souls style).
-- Wire: BO;guid;nameEnc (GM→players)  BX;guid (remove)
local ADB = ADB
local Net = ADB.Net
local min = math.min
local format = string.format
local Encode, Decode, CleanName = ADB.Encode, ADB.Decode, ADB.CleanName

local Boss = {}
ADB.Boss = Boss
Boss.list = {} -- [guid] = display name
local rows, MAX_ROWS = {}, 3

local function FindNpc(name)
    for _, p in ipairs(ADB.NPC.List()) do
        if p.name == name or ADB.NPC.DisplayName(p) == name then return p end
    end
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, UIParent)
    r:SetSize(440, 36)
    r:SetFrameStrata("MEDIUM")
    r:SetPoint("TOP", UIParent, "TOP", 0, -90 - (i - 1) * 46)
    r.Name = r:CreateFontString(nil, "OVERLAY")
    r.Name:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    r.Name:SetPoint("TOPLEFT", 2, 0)
    r.Name:SetTextColor(0.9, 0.85, 0.7)
    local box = CreateFrame("Frame", nil, r, "BackdropTemplate")
    box:SetSize(440, 14)
    box:SetPoint("BOTTOM")
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.6, 0.55, 0.4, 1)
    r.Bar = CreateFrame("StatusBar", nil, box)
    r.Bar:SetPoint("TOPLEFT", 1, -1)
    r.Bar:SetPoint("BOTTOMRIGHT", -1, 1)
    r.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.Bar:SetStatusBarColor(0.1, 0.75, 0.15)
    r.Text = r.Bar:CreateFontString(nil, "OVERLAY")
    r.Text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    r.Text:SetPoint("RIGHT", -4, 0)
    rows[i] = r
    return r
end

function Boss.Refresh()
    local list = {}
    for guid, name in pairs(Boss.list) do list[#list + 1] = { guid = guid, name = name } end
    table.sort(list, function(a, b) return a.guid < b.guid end)
    local n = min(#list, MAX_ROWS)
    for i = 1, n do
        local b, r = list[i], GetRow(i)
        local p = FindNpc(b.name)
        local lost = ADB.Measure.enemyDamage[b.guid] or 0
        if p then
            lost = p.maxHp - p.hp
            r.Bar:SetMinMaxValues(0, p.maxHp)
            r.Bar:SetValue(p.hp)
        else
            r.Bar:SetMinMaxValues(0, 1)
            r.Bar:SetValue(1)
        end
        r.Name:SetText(b.name)
        r.Text:SetText(lost > 0 and ("-" .. lost) or "0")
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
end

function Boss.Add(guid, name)
    Boss.list[guid] = name
    if ADB.IsGM() then Net.Send(format("BO;%s;%s", guid, Encode(name))) end
    Boss.Refresh()
end

function Boss.Remove(guid)
    Boss.list[guid] = nil
    if ADB.IsGM() then Net.Send("BX;" .. guid) end
    Boss.Refresh()
end

Net.RegisterMany({ "BO", "BX" }, function(sender, message, cmd)
    if ADB.IsGM() or not ADB.IsGMName(sender) then return end
    local p = Net.Split(message)
    local guid = p[2] or ""
    if #guid > 60 or not guid:match("^[%w%-]+$") then return end
    if cmd == "BO" then
        local name = CleanName(Decode(p[3] or "")):sub(1, 40)
        if name ~= "" then Boss.list[guid] = name end
    else
        Boss.list[guid] = nil
    end
    Boss.Refresh()
end)

hooksecurefunc(ADB.UnitFrames, "RefreshTarget", function() Boss.Refresh() end)
hooksecurefunc(ADB.UnitFrames, "RefreshNpcs", function() Boss.Refresh() end)

ADB.Combat.OnPhase(function(phase)
    if phase == "IDLE" then
        wipe(Boss.list)
        Boss.Refresh()
    end
end)