-- Logic/CombatFeedback.lua : critical-roll banners shared with the group.
-- Wire (frozen): CR;type;nameEnc   (type "1" = critical success, "0" = critical failure)
local ADB = ADB
local Net = ADB.Net
local format = string.format
local Encode, Decode, CleanName = ADB.Encode, ADB.Decode, ADB.CleanName

local function CritText(t) return t == "1" and "Réussite critique" or "Échec critique" end

ADB.Wrap(ADB.Combat, "Roll", function(orig, ...)
    local r, label, color, mult, failed, critFail = orig(...)
    local t = critFail and "0" or ((mult > 1 and not failed) and "1" or nil)
    if t then
        local name = ADB.Stats.DisplayName(ADB.playerName)
        ADB.CombatUI.Banner(format("%s : %s !", name, CritText(t)))
        Net.Send(format("CR;%s;%s", t, Encode(name)))
    end
    return r, label, color, mult, failed, critFail
end)

Net.Register("CR", function(sender, message)
    if not (ADB.roster[sender] or ADB.IsGMName(sender)) then return end
    local p = Net.Split(message)
    local name = CleanName(Decode(p[3] or "")):sub(1, 40)
    if name ~= "" then ADB.CombatUI.Banner(format("%s : %s !", name, CritText(p[2]))) end
end)