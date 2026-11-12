-- Logic/Forms.lua : tags "blink" / "sha0" / "sha1" / "sha2" (Sha form: HP scaling, shadow-only bar, basic attack bonus).
-- Persistence: db.shaForm = { tier, hpBeforeTransform }
local ADB = ADB
local Talents, UI = ADB.Talents, ADB.UI
local floor, max, sqrt = math.floor, math.max, math.sqrt
local format = string.format
local Clamp = ADB.Clamp

local Forms = {}
ADB.Forms = Forms

local BASIC_DAMAGE_BONUS = { [0] = 0.5, [1] = 1, [2] = 2 }   -- by tier
local SHADOW_ELEMENT = 3

local function InForm() return (not ADB.altContext and ADB.db) and ADB.db.shaForm or nil end

local function NodeTier(n)
    for t = 2, 0, -1 do
        if Talents.HasTag(n, "sha" .. t) then return t end
    end
end

local function MaxTier()
    local best
    for _, n in ipairs(Talents.LearnedNodes()) do
        local t = NodeTier(n)
        if t and (not best or t > best) then best = t end
    end
    return best
end

local function FormMaxHp(normal, tier)
    if tier == 0 then return max(1, floor(normal / 2)) end
    return tier == 1 and normal or normal * 2
end

-- Max HP / HP while in Sha form
ADB.Wrap(ADB.Stats, "GetBlock", function(orig, name)
    local d = orig(name)
    local s = d and name == ADB.playerName and InForm()
    if s then
        d.maxHp = FormMaxHp(d.maxHp, s.tier)
        d.hp = Clamp(floor(ADB.db.hp or 0), 0, d.maxHp)
    end
    return d
end)

-- Bar: Sha form = basic attack + shadow spells; lower Sha tiers hidden
ADB.Wrap(Talents, "ActiveSkills", function(orig)
    local r, best, form = orig(), MaxTier(), InForm()
    if not best and not form then return r end
    local out = {}
    for _, n in ipairs(r) do
        local t = NodeTier(n)
        if not (t and best and t < best) and (not form or n.id == 0 or n.element == SHADOW_ELEMENT) then
            out[#out + 1] = n
        end
    end
    return out
end)

-- Basic attack damage bonus
local basicAttack
ADB.Wrap(ADB.Buffs, "GetBonus", function(orig, key)
    local acc, crit, dmg, adv = orig(key)
    local s = basicAttack and InForm()
    if s and key == "P:" .. ADB.playerName then dmg = dmg + BASIC_DAMAGE_BONUS[s.tier] end
    return acc, crit, dmg, adv
end)

local function Transform(tier, hpBefore)
    local db = ADB.db
    hpBefore = hpBefore or max(1, ADB.Stats.GetBlock(ADB.playerName).hp)
    db.shaForm = { tier = tier, hpBeforeTransform = hpBefore }
    db.hp = ADB.Stats.GetBlock(ADB.playerName).maxHp
    ADB.CombatUI.Banner("Vous prenez votre forme de Sha")
    ADB.Print("Vous prenez votre forme de Sha.")
    ADB.Net.Announce(format("%s prend sa forme de Sha.", ADB.Stats.DisplayName(ADB.playerName)))
    ADB.Sync.AfterLocalChange()
end

local function Revert()
    local db = ADB.db
    local s = db.shaForm
    db.shaForm = nil
    db.hp = Clamp(s.hpBeforeTransform or 1, 1, ADB.Stats.GetBlock(ADB.playerName).maxHp)
    ADB.Print("Vous reprenez votre forme normale.")
    ADB.Sync.AfterLocalChange()
end

-- At 0 HP outside the form: immediately activates the best available Sha (return HP = 1).
local function AutoActivate()
    local tier, best = MaxTier(), nil
    if not tier then return end
    for _, n in ipairs(Talents.LearnedNodes()) do
        if n.nodeType == 1 and NodeTier(n) == tier
            and Talents.GetCooldown(n) < (ADB.TALENT.USE_LIMITS[n.limit].charges or 1) then
            best = n
            break
        end
    end
    if not best then return end
    Talents.SetCooldown(best)
    Transform(tier, 1)
end

hooksecurefunc(ADB.Sync, "AfterLocalChange", function()
    if ADB.altContext or not ADB.db or ADB.IsGM() or (ADB.db.hp or 1) > 0 then return end
    if ADB.db.shaForm then Revert() else AutoActivate() end
end)

-- End of player turn in form: -1/10 max HP; end of combat: back to normal form.
local prevPhase = "IDLE"
ADB.Combat.OnPhase(function(phase)
    local prev = prevPhase
    prevPhase = phase
    if prev == phase or ADB.altContext or ADB.IsGM() or not InForm() then return end
    if phase == "IDLE" then return Revert() end
    if prev == "PLAYER_TURN" then
        local d = ADB.Stats.GetBlock(ADB.playerName)
        local loss = max(1, floor(d.maxHp / 10))
        ADB.db.hp = max(0, ADB.db.hp - loss)
        ADB.Print(format("Forme de Sha : vous perdez %d PV.", loss))
        ADB.Sync.AfterLocalChange()
    end
end)

------------------------------------------------------------------------------
-- Blink (instant move, max 30 m)
------------------------------------------------------------------------------
local blinkWindow

local function PlayerPosition()
    local y, x = UnitPosition("player")
    if x and not (x == 0 and y == 0) then return x, y end
end

function Forms.OpenBlink(n)
    local f = blinkWindow
    if not f then
        f = UI.BaseWindow("ADBBlinkFrame", 240, 110, "Déplacement instantané")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetPoint("CENTER", 0, 150)
        tinsert(UISpecialFrames, "ADBBlinkFrame")
        f.Text = UI.Label(f, "", 20, -40, "GameFontNormalLarge")
        f.Confirm = UI.Button(f, "Valider", 20, -75, 100, function()
            if f.distance and f.distance > 30 then return end
            ADB.Net.Announce(format("%s a utilisé %s : déplacement instantané.",
                ADB.Stats.DisplayName(ADB.playerName), ADB.Links.Text(f.node)))
            f:Hide()
        end)
        UI.Button(f, "Annuler", 130, -75, 90, function() f:Hide() end)
        f:SetScript("OnUpdate", function(s, elapsed)
            s.acc = (s.acc or 0) + elapsed
            if s.acc < 0.1 then return end
            s.acc = 0
            local x, y = PlayerPosition()
            if x and s.x0 then
                s.distance = sqrt((x - s.x0) ^ 2 + (y - s.y0) ^ 2)
                s.Text:SetText(format("%.1f / 30 m", s.distance))
                s.Confirm:SetEnabled(s.distance <= 30)
            else
                s.distance = nil
                s.Text:SetText("Position indisponible")
                s.Confirm:SetEnabled(true)
            end
        end)
        blinkWindow = f
    end
    f.node, f.distance = n, 0
    f.x0, f.y0 = PlayerPosition()
    f:Show()
end

------------------------------------------------------------------------------
-- Tag activation
------------------------------------------------------------------------------
ADB.Wrap(Talents, "Execute", function(orig, n, data, offTurn)
    basicAttack = (n.id == 0)
    local ok = orig(n, data, offTurn)
    basicAttack = false
    if ok then
        local tier = NodeTier(n)
        if tier and not ADB.altContext and not ADB.IsGM() and not InForm() then Transform(tier) end
        if Talents.HasTag(n, "blink") then Forms.OpenBlink(n) end
    end
    return ok
end)

ADB.Events.Register("PLAYER_LOGIN", function()
    local s = ADB.db.shaForm
    if type(s) ~= "table" or not BASIC_DAMAGE_BONUS[s.tier] then
        ADB.db.shaForm = nil
    else
        s.hpBeforeTransform = Clamp(floor(tonumber(s.hpBeforeTransform) or 1), 1, 99999)
    end
end)