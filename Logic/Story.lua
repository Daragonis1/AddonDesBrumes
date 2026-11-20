-- Logic/Story.lua : StoryEnd (1/Trame), death saves (FeintDeath / StoneForm), aspiration points,
-- GM talent reset, screen effects.
-- Wire: SE (GM→players)  AP;player  TR;player  FX;name;seconds
local ADB = ADB
local Net, Talents, Slash = ADB.Net, ADB.Talents, ADB.Slash
local format = string.format
local Clamp = ADB.Clamp

local Story = {}
ADB.Story = Story

local function FromGM(sender) return ADB.IsGMName(sender) and not ADB.IsGM() end

------------------------------------------------------------------------------
-- StoryEnd: recharges "1/Trame" talents and death saves
------------------------------------------------------------------------------
function Story.End()
    if not ADB.db then return end
    ADB.db.deathSave = nil
    local cd, trees = ADB.db.talents.cooldowns, ADB.db.talents.trees
    for key in pairs(cd) do
        local class, id = key:match("^(.-):(%d+)$")
        local n = Talents.NodeFromId(class and trees[class], tonumber(id))
        if n and ADB.TALENT.USE_LIMITS[n.limit].unit == "s" then cd[key] = nil end
    end
    ADB.Print("Fin de la trame : vos capacités à usage unique sont de nouveau disponibles.")
    ADB.ActionBar.Refresh()
end

Net.Register("SE", function(sender)
    if not FromGM(sender) then return end
    Story.End()
    if ADB.altChar then ADB.Alt.WithContext(true, Story.End) end
end)

Slash.Register("storyend", function()
    if not ADB.IsGM() then
        ADB.Print("Réservé au MJ.")
        return
    end
    Net.Send("SE")
    ADB.Print("Fin de trame envoyée au groupe.")
end)

------------------------------------------------------------------------------
-- Death saves (passive tags). FeintDeath first; StoneForm only when FeintDeath is unavailable.
------------------------------------------------------------------------------
local DEATH = {
    { tag = "feintdeath", text = "%s a feint la mort, il survit à l'attaque.", buff = true },
    { tag = "stoneform", text = "%s s'est changé en pierre, il survit à l'attaque." },
}

local function LearnedByTag(tag)
    for _, n in ipairs(Talents.LearnedNodes()) do
        if Talents.HasTag(n, tag) then return n end
    end
end

hooksecurefunc(ADB.Sync, "AfterLocalChange", function()
    if ADB.altContext or not ADB.db or ADB.IsGM() or (ADB.db.hp or 1) > 0 then return end
    ADB.db.deathSave = ADB.db.deathSave or {}
    local used = ADB.db.deathSave
    for _, d in ipairs(DEATH) do
        local n = not used[d.tag] and LearnedByTag(d.tag)
        if n then
            used[d.tag] = true
            ADB.db.hp = 1
            ADB.Net.Announce(format(d.text, ADB.Stats.DisplayName(ADB.playerName)))
            SendChatMessage(".aura 13333", "SAY")
            if d.buff and (n.buffId or 0) > 0 then
                ADB.Buffs.Request(n.buffId, Talents.SpecBonus(n), Talents.Multiplier(n), "P:" .. ADB.playerName)
            end
            ADB.Sync.AfterLocalChange()
            return
        end
    end
end)

------------------------------------------------------------------------------
-- Aspiration points
------------------------------------------------------------------------------
Slash.Register("aspirationcompleted", function()
    if not ADB.IsGM() then
        ADB.Print("Réservé au MJ.")
        return
    end
    local name = ADB.Group.GetTargetPlayer()
    if not name or name == ADB.playerName then
        ADB.Print("Ciblez un joueur possédant l'addon.")
        return
    end
    Net.Send("AP;" .. name)
    ADB.Print(format("Point d'aspiration accordé à %s.", ADB.Stats.DisplayName(name)))
end)

Net.Register("AP", function(sender, message)
    if not FromGM(sender) or Net.Split(message)[2] ~= ADB.playerName or not ADB.db then return end
    ADB.db.aspirationPoints = (ADB.db.aspirationPoints or 0) + 1
    ADB.Print(format("Vous gagnez un point d'aspiration (total : %d).", ADB.db.aspirationPoints))
    ADB.Sync.AfterLocalChange()
end)

------------------------------------------------------------------------------
-- GM: /brumes talent reset (targeted player)
------------------------------------------------------------------------------
Slash.Register("talent", function(rest)
    if (rest or ""):lower() ~= "reset" then
        ADB.Print("Usage : /brumes talent reset")
        return
    end
    if not ADB.IsGM() then
        ADB.Print("Réservé au MJ.")
        return
    end
    local name = ADB.Group.GetTargetPlayer()
    if not name or name == ADB.playerName then
        ADB.Print("Ciblez un joueur possédant l'addon.")
        return
    end
    Net.Send("TR;" .. name)
    ADB.Print(format("Talents de %s réinitialisés.", ADB.Stats.DisplayName(name)))
end)

Net.Register("TR", function(sender, message)
    if not FromGM(sender) or Net.Split(message)[2] ~= ADB.playerName or not ADB.db then return end
    for _, c in ipairs(Talents.AccessibleClasses()) do wipe(Talents.Learned(c)) end
    ADB.Print("Le MJ a réinitialisé vos talents.")
    Talents.Refresh()
end)

------------------------------------------------------------------------------
-- Screen effects (cosmetic overlay under the UI): /brumes fx <name> [seconds]
------------------------------------------------------------------------------
local FX = {
    noir = { 0, 0, 0, 1 }, blanc = { 1, 1, 1, 0.9 }, rouge = { 0.7, 0, 0, 0.5 }, bleu = { 0, 0.2, 0.7, 0.4 },
    vert = { 0, 0.5, 0, 0.4 }, violet = { 0.4, 0, 0.6, 0.45 },
}

local fx = CreateFrame("Frame", "ADBScreenFX", UIParent)
fx:SetAllPoints(UIParent)
fx:SetFrameStrata("BACKGROUND")
fx:EnableMouse(false)
fx:Hide()
fx.tex = fx:CreateTexture(nil, "BACKGROUND")
fx.tex:SetAllPoints()
fx:SetScript("OnUpdate", function(s, elapsed)
    s.e = s.e + elapsed
    local t = s.e / s.dur
    if t >= 1 then
        s:Hide()
        return
    end
    s.tex:SetAlpha(s.a * (t < 0.2 and t / 0.2 or (t > 0.8 and (1 - t) / 0.2 or 1)))
end)

function Story.ScreenFX(name, dur)
    local c = FX[name or ""]
    if not c then return false end
    fx.tex:SetColorTexture(c[1], c[2], c[3], 1)
    fx.a, fx.dur, fx.e = c[4], Clamp(tonumber(dur) or 3, 0.5, 30), 0
    fx.tex:SetAlpha(0)
    fx:Show()
    return true
end

Slash.Register("fx", function(rest)
    if not ADB.IsGM() then
        ADB.Print("Réservé au MJ.")
        return
    end
    local name, dur = (rest or ""):match("^(%S+)%s*(%d*%.?%d*)$")
    name = name and name:lower()
    dur = tonumber(dur) or 3
    if not Story.ScreenFX(name, dur) then
        ADB.Print("Effets : noir, blanc, rouge, bleu, vert, violet. Usage : /brumes fx <nom> [secondes]")
        return
    end
    Net.Send(format("FX;%s;%s", name, dur))
end)

Net.Register("FX", function(sender, message)
    if not FromGM(sender) then return end
    local p = Net.Split(message)
    Story.ScreenFX(p[2], p[3])
end)