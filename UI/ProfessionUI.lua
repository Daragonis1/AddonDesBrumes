-- UI/ProfessionUI.lua : profession window (choice, level / XP, learned recipes, crafting).
local ADB, UI = ADB, ADB.UI
local Prof = ADB.Professions
local format = string.format

local PUI = {}
ADB.ProfessionUI = PUI

local ROW_H = 46

StaticPopupDialogs["ADB_METIER_CHOIX"] = {
    text = "Devenir %s ?\n|cffff4040Ce choix est définitif.|r",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data) if data then Prof.Learn(data) end end,
}

function PUI.OnChoose(key)
    local def = ADB.PROFESSION_BY_KEY[key]
    if not def.available then
        UIErrorsFrame:AddMessage("Ce métier n'est pas encore disponible.", 1, 0.3, 0.3)
        ADB.Print("Ce métier n'est pas encore disponible.")
        return
    end
    StaticPopup_Show("ADB_METIER_CHOIX", def.name, nil, key)
end

local function CreateRow(f, i)
    local r = CreateFrame("Frame", nil, f.Main)
    r:SetSize(360, ROW_H - 4)
    r:SetPoint("TOPLEFT", 20, -96 - (i - 1) * ROW_H)
    r:EnableMouse(true)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(36, 36)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("TOPLEFT", 46, -4)
    r.name:SetJustifyH("LEFT")
    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cost:SetPoint("TOPLEFT", 46, -22)
    r.cost:SetJustifyH("LEFT")
    r.btn = UI.Button(r, "Fabriquer", 0, 0, 80, function() Prof.Craft(r.recipe) end)
    r.btn:ClearAllPoints()
    r.btn:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self)
        local it = self.recipe and { kind = self.recipe.item }
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ADB.Items.ColoredName(it))
        GameTooltip:AddLine(ADB.CONSUMABLES[it.kind].desc, 1, 0.82, 0, true)
        GameTooltip:AddLine(format("Niveau requis : %d", self.recipe.level), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = r
    return r
end

function PUI.Refresh()
    local f = ADB.profFrame
    if not (f and f:IsShown() and ADB.db) then return end
    if ADB.altContext then return ADB.Alt.WithContext(false, PUI.Refresh) end
    local p = ADB.db.profession
    f.Choice:SetShown(not p)
    f.Main:SetShown(p ~= nil)
    if not p then return end
    local def = ADB.PROFESSION_BY_KEY[p.key]
    f.Header:SetText(format("%s - Niveau %d / %d", def.name, p.level, ADB.PROF_MAX_LEVEL))
    if p.level >= ADB.PROF_MAX_LEVEL then
        f.Bar:SetMinMaxValues(0, 1)
        f.Bar:SetValue(1)
        f.Bar.Text:SetText(p.xp .. " (niveau max)")
    else
        f.Bar:SetMinMaxValues(ADB.PROF_XP[p.level], ADB.PROF_XP[p.level + 1])
        f.Bar:SetValue(p.xp)
        f.Bar.Text:SetText(format("XP : %d / %d", p.xp, ADB.PROF_XP[p.level + 1]))
    end
    local list = Prof.Recipes()
    for i = 1, ADB.PROF_MAX_LEVEL do
        local r = f.rows[i] or CreateRow(f, i)
        local rec = list[i]
        r.recipe = rec
        r:SetShown(rec ~= nil)
        if rec then
            local c = ADB.CONSUMABLES[rec.item]
            r.icon:SetTexture(ADB.IconTexture(c.icon))
            r.name:SetText(ADB.Items.ColoredName({ kind = rec.item }) ..
                "  |cff999999(" .. ADB.RARITIES[c.rarity].name .. ")|r")
            local parts = {}
            for _, k in ipairs(rec.cost) do
                local have = ADB.Items.CountConsumable(k[1])
                parts[#parts + 1] = format("%s%s : %d / %d|r", have >= k[2] and "|cff40ff40" or "|cffff4040",
                    ADB.CONSUMABLES[k[1]].name, have, k[2])
            end
            r.cost:SetText(table.concat(parts, "   "))
            r.btn:SetEnabled((Prof.CanCraft(rec)))
        end
    end
end

local function Create()
    local f = UI.BaseWindow("ADBProfFrame", 400, 600, "Métier")
    ADB.profFrame = f
    f:SetPoint("CENTER", -260, 0)
    tinsert(UISpecialFrames, "ADBProfFrame")
    f.rows = {}

    f.Choice = CreateFrame("Frame", nil, f)
    f.Choice:SetAllPoints()
    UI.Label(f.Choice, "Choisissez votre métier (choix définitif) :", 20, -42)
    for i, def in ipairs(ADB.PROFESSIONS) do
        UI.Button(f.Choice, def.name, 100, -70 - (i - 1) * 30, 200, function() PUI.OnChoose(def.key) end)
    end

    f.Main = CreateFrame("Frame", nil, f)
    f.Main:SetAllPoints()
    f.Header = UI.Label(f.Main, "", 20, -38, "GameFontNormalLarge")
    local bar = CreateFrame("StatusBar", nil, f.Main)
    bar:SetPoint("TOPLEFT", 20, -66)
    bar:SetSize(360, 16)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.6, 0.4, 0.9)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Text:SetPoint("CENTER")
    f.Bar = bar

    f:SetScript("OnShow", PUI.Refresh)
end

function PUI.Toggle()
    if not ADB.profFrame then Create() end
    local f = ADB.profFrame
    if f:IsShown() then f:Hide() else f:Show() end
end

ADB.Slash.Register({ "metier", "métier" }, PUI.Toggle)