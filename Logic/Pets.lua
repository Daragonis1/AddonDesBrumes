-- Logic/Pets.lua : pet logic (stats, sync to GM as owned ally NPC, skill use). UI → UI/PetUI.lua.
-- Wire (frozen): PS;type;name;rpName;hp;mp (owner→GM)  PD (delete)  PM;cost (mana spent)
local ADB = ADB
local Net = ADB.Net
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local Clamp, Encode, Decode, CleanName = ADB.Clamp, ADB.Encode, ADB.Decode, ADB.CleanName

local Pets = {}
ADB.Pets = Pets
Pets.used = nil   -- pet already acted this turn

function Pets.FindByOwner(owner)
    for _, x in ipairs(ADB.NPC.List()) do
        if x.owner == owner then return x end
    end
end

-- Alt characters are stored as allied NPCs owned by "+PlayerName".
function Pets.FindAlt(player)
    for _, x in ipairs(ADB.NPC.List()) do
        if x.owner == "+" .. player then return x end
    end
end

function Pets.GetPet() return ADB.db and ADB.playerName and Pets.FindByOwner(ADB.playerName) or nil end

function Pets.Skills(p)
    local T = ADB.PET_TYPES[p and p.petType or ""]
    return T and T.skills or {}
end

-- Owner stat multiplier (+25 % with the matching spec tag).
function Pets.Multiplier(T)
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local m = ({ d.strengthMult, d.agilityMult, d.intellectMult })[T.stat - 1]
    local spec = ADB.Talents.ActiveSpec()
    if spec and ADB.Talents.HasTag(spec, T.boost) then m = m * 1.25 end
    return m
end

function Pets.MaxStats(typeName)
    local T = ADB.PET_TYPES[typeName or ""]
    if not T then return 1, 0 end
    local m = Pets.Multiplier(T)
    return max(1, floor((T.baseHp or 0) + T.hp * m + 0.5)), floor(T.mp * m + 0.5)
end

------------------------------------------------------------------------------
-- Sync owner → GM
------------------------------------------------------------------------------
local lastSig, lastTime = nil, 0
function Pets.Sync(force)
    local s = ADB.db.secondary
    if not s or s.type == ADB.ALT_TYPE or ADB.IsGM() or not IsInGroup() or not ADB.Group.GetGMName() then return end
    local hp, mp = Pets.MaxStats(s.type)
    local sig = format("%s;%s;%s;%d;%d", s.type, Encode(s.name), Encode(s.rpName or ""), hp, mp)
    local t = GetTime()
    if not force and sig == lastSig and (Pets.GetPet() or t < lastTime + 10) then return end
    lastSig, lastTime = sig, t
    Net.Send("PS;" .. sig)
end
hooksecurefunc(ADB.Sync, "SendState", function() Pets.Sync() end)

function Pets.ResetSync() lastSig = nil end

-- GM: creates/updates the pet NPC of `owner`.
function Pets.Define(owner, petType, name, rpName, hp, mp)
    local pn = Pets.FindByOwner(owner)
    if not pn then
        if #ADB.db.npcs >= ADB.NPC_MAX then return end
        local id = ADB.db.nextNpcId
        ADB.db.nextNpcId = id + 1
        pn = { id = id, maxHp = hp, maxMp = mp, hp = hp, mp = mp, shield = 0, ally = true, owner = owner }
        table.insert(ADB.db.npcs, pn)
    else
        if pn.hp >= pn.maxHp then pn.hp = hp end
        if pn.mp >= pn.maxMp then pn.mp = mp end
        pn.maxHp, pn.maxMp = hp, mp
        pn.hp, pn.mp = min(pn.hp, hp), min(pn.mp, mp)
    end
    pn.name, pn.rpName, pn.petType = name, rpName ~= "" and rpName or nil, petType
    ADB.NPC.Schedule(pn.id)
    ADB.UnitFrames.LayoutNpcs()
    ADB.UnitFrames.RefreshNpcs()
end

local function GmOnly(sender) return ADB.IsGM() and ADB.roster[sender] end

Net.Register("PS", function(sender, message)
    if not GmOnly(sender) then return end
    local p = Net.Split(message)
    local name, rp = CleanName(Decode(p[3] or "")):sub(1, 30), CleanName(Decode(p[4] or "")):sub(1, 40)
    if not ADB.PET_TYPES[p[2] or ""] or name == "" then return end
    Pets.Define(sender, p[2], name, rp,
        Clamp(floor(tonumber(p[5]) or 1), 1, ADB.NPC_STAT_MAX), Clamp(floor(tonumber(p[6]) or 0), 0, ADB.NPC_STAT_MAX))
end)

Net.Register("PD", function(sender)
    if not GmOnly(sender) then return end
    local pn = Pets.FindByOwner(sender)
    if pn then ADB.NPC.Delete(pn.id) end
end)

Net.Register("PM", function(sender, message)
    if not GmOnly(sender) then return end
    local pn, cost = Pets.FindByOwner(sender), tonumber(Net.Split(message)[2])
    if pn and cost then ADB.NPC.ApplyValue(pn.id, "mp", pn.mp - Clamp(floor(cost), 0, 99)) end
end)

------------------------------------------------------------------------------
-- Pet actions (1 skill per turn, in addition to the player's action)
------------------------------------------------------------------------------
function Pets.GetState(p, sk)
    if ADB.phase ~= "PLAYER_TURN" then return false, "Ce n'est pas le tour des joueurs." end
    if Pets.used then return false, "Le familier a déjà agi ce tour." end
    if ADB.Buffs.Has("N:" .. p.id, ADB.Buffs.TYPE.STUN) then return false, "Votre familier est étourdi." end
    if (p.mp or 0) < sk.mana then return false, "Mana du familier insuffisant." end
    return true
end

function Pets.UseSkill(i)
    local p = Pets.GetPet()
    local sk = p and Pets.Skills(p)[i]
    if not sk then return end
    local ok, reason = Pets.GetState(p, sk)
    if not ok then
        UIErrorsFrame:AddMessage(reason, 1, 0.3, 0.3)
        return
    end
    if not UnitExists("target") then
        ADB.Print("Cible requise.")
        return
    end

    local entry = ADB.Measure.UnitEntry("target")
    local targetName = ADB.Talents.TargetName() or UnitName("target")
    local bonusAcc, bonusCrit, bonusDmg, advantage = ADB.Buffs.GetBonus("N:" .. p.id)
    local r, label, color, mult, failed = ADB.Combat.Roll(sk.accuracy, bonusAcc, bonusCrit, advantage)
    local value = max(1, floor(sk.base * Pets.Multiplier(ADB.PET_TYPES[p.petType]) * bonusDmg + 0.5)) * mult

    if sk.mana > 0 then
        p.mp = max(0, (p.mp or 0) - sk.mana)
        Net.Send("PM;" .. sk.mana)
    end
    Pets.used = true

    local msg = format("%s (familier de %s) a utilisé %s sur %s. Jet de précision : %d (%s).",
        ADB.NPC.DisplayName(p), ADB.Stats.DisplayName(ADB.playerName), sk.name, targetName, r, label)
    UIErrorsFrame:AddMessage(format("%d - %s", r, label), color[1], color[2], color[3])
    if failed then
        msg = msg .. " La compétence échoue."
    else
        msg = msg .. format(" La compétence inflige %d dégâts.", value) .. (mult > 1 and " (effet doublé)" or "")
        if entry then
            ADB.Measure.SendEffects({ entry }, 1, value)
            if sk.stun then
                ADB.Buffs.Request(-1, sk.stun, 1, ADB.Buffs.KeyFromEntry(entry))
                msg = msg .. format(" La cible est étourdie (%d tour).", sk.stun)
            end
        end
        if ADB.Effects.OnPetHit then ADB.Effects.OnPetHit(p) end
    end
    ADB.Net.Announce(msg)
    ADB.PetUI.Refresh()
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------
local lastPhase = "IDLE"
ADB.Combat.OnPhase(function(phase)
    if phase == lastPhase then return end
    lastPhase = phase
    if phase == "PLAYER_TURN" or phase == "IDLE" then Pets.used = nil end
    ADB.PetUI.Refresh()
end)

hooksecurefunc(ADB.UnitFrames, "RefreshNpcs", function() ADB.PetUI.Refresh() end)

function Pets.Init()
    local db = ADB.db
    ADB.PetUI.Create()
    local s = db.secondary
    if type(s) == "table" and (ADB.PET_TYPES[s.type or ""] or s.type == ADB.ALT_TYPE)
        and type(s.name) == "string" and CleanName(s.name) ~= "" then
        s.name, s.rpName = CleanName(s.name):sub(1, 30), CleanName(s.rpName or ""):sub(1, 40)
    else
        db.secondary = nil
    end
    db.pet = nil   -- legacy field
    for _, p in ipairs(db.npcs) do   -- migration: legacy pets
        if p.owner and p.owner:sub(1, 1) ~= "+" and not ADB.PET_TYPES[p.petType or ""] then
            p.owner, p.petType = nil, nil
        end
    end
    ADB.PetUI.Refresh()
end
ADB.Events.Register("PLAYER_LOGIN", Pets.Init)

ADB.Slash.Register("pet", function() ADB.PetUI.ToggleMenu() end)