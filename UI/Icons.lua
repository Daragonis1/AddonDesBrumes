-- UI/Icons.lua : searchable picker of every game icon (lazy-loaded on first open).
local ADB, UI = ADB, ADB.UI
local floor, max, min = math.floor, math.max, math.min
local format = string.format

local Icons = {}
ADB.Icons = Icons

local PER_PAGE, COLS = 56, 8
local list, names, filterCache = nil, nil, {}

local function BaseName(s)
    return (tostring(s or ""):gsub("^.*[\\/]", ""):gsub("%.%w+$", ""))
end

local tmpTexture
local function NameFromFileId(id)
    local read = C_Texture and C_Texture.GetFilenameFromFileDataID
    if read then
        local ok, r = pcall(read, id)
        if ok and r and r ~= "" then return BaseName(r) end
    end
    if not tmpTexture then tmpTexture = UIParent:CreateTexture(nil, "BACKGROUND") end
    tmpTexture:SetTexture(id)
    local t = tmpTexture:GetTexture()
    if type(t) == "string" then return BaseName(t) end
    return ""
end

local function Load()
    if list then return end
    list, names = {}, {}
    local seen, raw = {}, {}
    for _, fnName in ipairs({ "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons" }) do
        local fn = _G[fnName]
        if fn then
            wipe(raw)
            pcall(fn, raw)
            for _, v in ipairs(raw) do
                local name = (type(v) == "string") and BaseName(v) or NameFromFileId(v)
                local key = (name ~= "") and name:lower() or tostring(v)
                if not seen[key] then
                    seen[key] = true
                    list[#list + 1] = (type(v) == "string") and name or v
                    names[#names + 1] = name:lower()
                end
            end
        end
    end
end

local function Filter(text)
    text = ((text or ""):lower():gsub("%s+", ""))
    if text == "" then return list end
    if filterCache.text == text then return filterCache.result end
    local res
    if text:match("^%d+$") then
        res = { tonumber(text) }
    else
        res = {}
        for i = 1, #names do
            if names[i]:find(text, 1, true) then res[#res + 1] = list[i] end
        end
    end
    filterCache.text, filterCache.result = text, res
    return res
end

function Icons.Refresh()
    local f = ADB.iconFrame
    if not f then return end
    Load()
    local res = Filter(f.Filter:GetText())
    local pages = max(1, math.ceil(#res / PER_PAGE))
    f.page = max(1, min(f.page, pages))
    for i, b in ipairs(f.buttons) do
        local v = res[(f.page - 1) * PER_PAGE + i]
        b.value = v
        if v ~= nil then
            b.tex:SetTexture(ADB.IconTexture(v))
            b:Show()
        else
            b:Hide()
        end
    end
    f.updating = true
    f.Slider:SetMinMaxValues(1, max(2, pages))
    f.Slider:SetValue(f.page)
    f.updating = false
    f.PageText:SetText(format("%d / %d  (%d icônes)", f.page, pages, #res))
end

function Icons.CreateWindow()
    local f = UI.BaseWindow("ADBIconFrame", 360, 440, "Choisir une icône")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    ADB.iconFrame = f
    f:SetPoint("CENTER", 0, 0)
    f.page = 1

    UI.Label(f, "Recherche", 16, -34, "GameFontNormalSmall")
    f.Filter = UI.Input(f, 80, -31, 180, 40)
    f.Filter:SetScript("OnTextChanged", function()
        f.page = 1
        Icons.Refresh()
    end)
    UI.Label(f, "(nom ou ID)", 268, -34, "GameFontDisableSmall")

    f.buttons = {}
    for i = 1, PER_PAGE do
        local col, row = (i - 1) % COLS, floor((i - 1) / COLS)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(38, 38)
        b:SetPoint("TOPLEFT", 16 + col * 42, -62 - row * 42)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self)
            if self.value ~= nil then
                local cb = f.callback
                f:Hide()
                if cb then cb(self.value) end
            end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tostring(self.value or ""), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.buttons[i] = b
    end

    local s = CreateFrame("Slider", "ADBIconSlider", f, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 20, -372)
    s:SetSize(320, 16)
    s:SetMinMaxValues(1, 2)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    _G["ADBIconSliderLow"]:SetText("")
    _G["ADBIconSliderHigh"]:SetText("")
    _G["ADBIconSliderText"]:SetText("")
    s:SetScript("OnValueChanged", function(_, v)
        if f.updating then return end
        f.page = floor(v + 0.5)
        Icons.Refresh()
    end)
    f.Slider = s

    local function Page(delta) f.page = f.page + delta Icons.Refresh() end
    UI.Button(f, "<<", 16, -398, 40, function() Page(-10) end)
    UI.Button(f, "<", 60, -398, 40, function() Page(-1) end)
    f.PageText = UI.Label(f, "", 112, -402, "GameFontHighlightSmall")
    UI.Button(f, ">", 260, -398, 40, function() Page(1) end)
    UI.Button(f, ">>", 304, -398, 40, function() Page(10) end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) Page(-delta) end)
    f:SetScript("OnShow", Icons.Refresh)
end

function Icons.Open(callback)
    if not ADB.iconFrame then Icons.CreateWindow() end
    ADB.iconFrame.callback = callback
    ADB.iconFrame:Show()
    ADB.iconFrame:Raise()
end