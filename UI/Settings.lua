-- UI/Settings.lua : options d'affichage accessibles à tous (police des quêtes, tailles des cadres).
local ADB, UI = ADB, ADB.UI
local floor = math.floor
local format = string.format

local Settings = {}
ADB.Settings = Settings

local DEFS = {
    { key = "questFont",   label = "Police des quêtes",             lo = 70 },
    { key = "playerScale", label = "Votre portrait",                lo = 50 },
    { key = "petScale",    label = "Votre familier / secondaire",   lo = 50 },
    { key = "groupScale",  label = "Membres du groupe (+ familiers)", lo = 50 },
    { key = "targetScale", label = "Cible actuelle",                lo = 50 },
}

local function Apply(key)
    if key == "questFont" then ADB.QuestUI.Draw() else ADB.UnitFrames.ApplyScales() end
end

function Settings.Refresh()
    local f = ADB.settingsFrame
    if not (f and ADB.db) then return end
    for _, s in ipairs(f.sliders) do
        s.updating = true
        s:SetValue(floor(ADB.db.settings[s.def.key] * 100 + 0.5))
        s.updating = false
        _G[s:GetName() .. "Text"]:SetText(format("%s : %d%%", s.def.label, floor(s:GetValue() + 0.5)))
    end
end

local function Create()
    local f = UI.BaseWindow("ADBSettingsFrame", 320, 350, "Options d'affichage")
    ADB.settingsFrame = f
    f:SetPoint("CENTER", 0, 0)
    tinsert(UISpecialFrames, "ADBSettingsFrame")
    f.sliders = {}
    for i, d in ipairs(DEFS) do
        local name = "ADBSettingsSlider" .. i
        local s = CreateFrame("Slider", name, f, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 20, -62 - (i - 1) * 50)
        s:SetSize(280, 16)
        s:SetMinMaxValues(d.lo, 150)
        s:SetValueStep(5)
        s:SetObeyStepOnDrag(true)
        _G[name .. "Low"]:SetText(d.lo .. "%")
        _G[name .. "High"]:SetText("150%")
        s.def = d
        s:SetScript("OnValueChanged", function(self, v)
            v = floor(v + 0.5)
            _G[name .. "Text"]:SetText(format("%s : %d%%", d.label, v))
            if self.updating or not ADB.db then return end
            ADB.db.settings[d.key] = v / 100
            Apply(d.key)
        end)
        f.sliders[i] = s
    end
    UI.Button(f, "Réinitialiser", 100, -312, 120, function()
        for _, d in ipairs(DEFS) do ADB.db.settings[d.key] = 1 end
        Settings.Refresh()
        ADB.QuestUI.Draw()
        ADB.UnitFrames.ApplyScales()
    end)
    f:SetScript("OnShow", Settings.Refresh)
end

function Settings.Toggle()
    if not ADB.settingsFrame then Create() end
    local f = ADB.settingsFrame
    if f:IsShown() then f:Hide() else f:Show() end
end

ADB.Slash.Register({ "options", "param" }, Settings.Toggle)

ADB.Events.Register("PLAYER_LOGIN", function()
    UI.Button(ADBConfigFrame, "Options", 8, -3, 64, Settings.Toggle)
    ADB.UnitFrames.ApplyScales()
end)