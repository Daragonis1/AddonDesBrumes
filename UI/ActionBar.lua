-- UI/ActionBar.lua : combat action bar (learned active skills). Visible only in combat, never for the GM.
-- Alt.lua builds a second bar through Create() and swaps ADB.actionBar.
local ADB = ADB
local floor, min = math.floor, math.min

local AB = {}
ADB.ActionBar = AB

function AB.Usable(n)
    if not ADB.Talents.GetState(n) then return false end
    return n.reaction or (ADB.phase == "PLAYER_TURN" and not ADB.turnPassed)
end

local function Value(n)
    local T = ADB.Talents
    local _, v = T.FormatDescription(n.desc, true, T.Multiplier(n), T.SpecBonus(n))
    if v and n.effect == 1 then
        local _, _, dmg = ADB.Buffs.GetBonus("P:" .. ADB.playerName)
        v = floor(v * dmg + 0.5)
    end
    return (v and n.effect <= 3) and v or nil
end

local function Tooltip(b)
    local n = ADB.Talents.GetNode(b.id)
    if not n then return end
    local G = ADB.TalentWindow.ShowTooltip(b, n, "bar")
    local ok, reason, code = ADB.Talents.GetState(n)
    if not ok then
        G:AddLine(" ")
        G:AddLine(reason, 1, 0.2, 0.2, true)
        if code then G:AddLine("Clic : demander l'autorisation du MJ", 1, 0.6, 0.1, true) end
    end
    G:Show()
end

function AB.OnClick(b)
    local T = ADB.Talents
    local n = T.GetNode(b.id)
    if not n then return end
    local ok, reason, code = T.GetState(n)
    if not ok and not code then
        UIErrorsFrame:AddMessage(reason, 1, 0.3, 0.3)
        return
    end
    local data = { id = n.id, targetName = T.TargetName() }
    if UnitExists("target") then
        if n.aoe > 0 then
            data.targets = ADB.Measure.ZoneTargets(n.aoe / 2)
        else
            local e = ADB.Measure.UnitEntry("target")
            if e then data.targets = { e } end
        end
    end
    if not ok then
        data.force = true
        StaticPopup_Show("ADB_TAL_FORCE", nil, nil, data)
        return
    end
    local suffix = data.targetName and (" sur " .. data.targetName) or ""
    if n.aoe > 0 then
        local l = T.NamesOf(data.targets)
        suffix = suffix .. string.format("\nZone %g m - touchés : %s", n.aoe / 2, l ~= "" and l or "aucun")
    end
    StaticPopup_Show("ADB_TAL_UTILISER", n.name, suffix, data)
end

local function CreateButton(i)
    local bar = ADB.actionBar
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(40, 40)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.dark = b:CreateTexture(nil, "OVERLAY")
    b.dark:SetAllPoints()
    b.dark:SetColorTexture(0, 0, 0, 0.55)
    b.cd = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.cd:SetPoint("CENTER")
    b.flag = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.flag:SetPoint("TOPLEFT", 2, -2)
    b.val = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.val:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self) AB.OnClick(self) end)
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.btns[i] = b
    return b
end

-- Creates a bar and assigns it to ADB.actionBar.
function AB.Create()
    local b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    b:SetFrameStrata("MEDIUM")
    b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    b:SetSize(60, 60)
    ADB.UI.ApplyBackdrop(b)
    b.btns = {}
    b:Hide()
    ADB.actionBar = b
end

function AB.Refresh()
    local b = ADB.actionBar
    if not b or not ADB.db or not ADB.db.talents then return end
    if ADB.phase == "IDLE" or ADB.IsGM() then
        b:Hide()
        return
    end
    local T = ADB.Talents
    local skills = T.ActiveSkills()
    local nb = #skills
    if nb == 0 then
        b:Hide()
        return
    end
    local perRow = 12
    b:SetSize(min(nb, perRow) * 44 + 12, math.ceil(nb / perRow) * 44 + 12)
    for i, n in ipairs(skills) do
        local btn = b.btns[i] or CreateButton(i)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", b, "TOPLEFT", 8 + ((i - 1) % perRow) * 44, -8 - floor((i - 1) / perRow) * 44)
        btn.id = n.id
        btn.tex:SetTexture(ADB.IconTexture(n.icon))
        local ok = AB.Usable(n)
        btn.val:SetText(Value(n) or "")
        if GameTooltip:IsOwned(btn) then Tooltip(btn) end
        btn.tex:SetDesaturated(not ok)
        btn.dark:SetShown(not ok)
        local cd = T.GetCooldown(n)
        btn.cd:SetText(cd > 0 and (cd .. (ADB.TALENT.USE_LIMITS[n.limit].unit == "t" and "t" or "r")) or "")
        btn.flag:SetText((n.reaction and "R" or "") .. (n.bonusAction and "B" or ""))
        btn:Show()
    end
    for i = nb + 1, #b.btns do b.btns[i]:Hide() end
    b:Show()
end
