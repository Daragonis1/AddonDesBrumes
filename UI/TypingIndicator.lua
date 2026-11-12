-- UI/TypingIndicator.lua : "<name> est en train d'écrire." indicator shared with the group.
-- Wire (frozen): TY;1|0
local ADB = ADB
local Net = ADB.Net
local floor = math.floor

local TI = {}
ADB.TypingIndicator = TI

local typers, typing, lastSent = {}, false, 0   -- typers[name] = expiry time

local function Notify(on)
    if ADB.IsGM() or not IsInGroup() then return end
    Net.Send("TY;" .. (on and 1 or 0))
end

local function Update()
    local f = ADB.typingFrame
    if not f then return end
    local now, group, names = GetTime(), ADB.Group.GetNames(), {}
    for n, expiry in pairs(typers) do
        if expiry < now or not group[n] or n == ADB.playerName then
            typers[n] = nil
        else
            names[#names + 1] = ADB.Stats.DisplayName(n)
        end
    end
    if #names == 0 then
        f:Hide()
        return
    end
    table.sort(names)
    f.Text:SetText(#names == 1 and (names[1] .. " est en train d'écrire.")
        or (table.concat(names, ", ", 1, #names - 1) .. " et " .. names[#names] .. " sont en train d'écrire."))
    f:SetWidth(f.Text:GetStringWidth() + 20)
    f:Show()
end

function TI.Create()
    local f = CreateFrame("Frame", "ADBTypingFrame", UIParent, "BackdropTemplate")
    ADB.typingFrame = f
    f:SetSize(200, 22)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint(1)
        ADB.db.typingPos = { p, rp, floor(x + 0.5), floor(y + 0.5) }
    end)
    ADB.UI.ApplyBackdrop(f)
    f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Text:SetPoint("CENTER")
    local pos = ADB.db.typingPos
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
        and tonumber(pos[3]) and tonumber(pos[4]) then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
    end
    f:Hide()

    local function Begin()
        if not typing then
            typing, lastSent = true, GetTime()
            Notify(true)
        end
    end
    local function Finish()
        if typing then
            typing = false
            Notify(false)
        end
    end
    for i = 1, NUM_CHAT_WINDOWS do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:HookScript("OnEditFocusGained", Begin)
            eb:HookScript("OnEditFocusLost", Finish)
            eb:HookScript("OnShow", Begin)
            eb:HookScript("OnHide", Finish)
        end
    end
    C_Timer.NewTicker(1, function()
        if typing and GetTime() - lastSent > 8 then
            lastSent = GetTime()
            Notify(true)
        end
        Update()
    end)
end

Net.Register("TY", function(sender, message)
    if not ADB.Group.GetNames()[sender] or ADB.IsGMName(sender) then return end
    typers[sender] = (Net.Split(message)[2] == "1") and (GetTime() + 20) or nil
    Update()
end)

ADB.Events.Register("PLAYER_LOGIN", TI.Create)