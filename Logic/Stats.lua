-- Logic/Stats.lua : stat formulas, stat blocks, HP/MP/shield changes, XP & rest.
local ADB = ADB
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local Clamp, CleanName = ADB.Clamp, ADB.CleanName

local Stats = {}
ADB.Stats = Stats

local STAT_KEYS = { "strength", "agility", "intellect" }
Stats.MAX_KEY = { hp = "maxHp", mp = "maxMp" }
Stats.WIRE_KIND = { hp = "pv", mp = "pm", shield = "sh" }   -- wire-frozen names

function Stats.LevelForXP(xp)
    xp = tonumber(xp) or 0
    local level = 1
    for i, threshold in ipairs(ADB.XP_THRESHOLDS) do
        if xp >= threshold then level = i else break end
    end
    return level
end

function Stats.EquipmentBonus(sheet)
    local e = { 0, 0, 0 }
    if type(sheet.equipment) == "table" then
        for _, it in pairs(sheet.equipment) do
            if type(it) == "table" and type(it.stats) == "table" then
                for i = 1, 3 do e[i] = e[i] + (tonumber(it.stats[i]) or 0) end
            end
        end
    end
    return e
end

-- Final = Base + Race + Class + (Level - 1) + Equipment. Returns strength, agility, intellect.
function Stats.FinalStats(sheet)
    local race = ADB.RACE_BY_NAME[sheet.race] or ADB.RACE_BY_NAME["Humain"]
    local class = ADB.CLASS_BY_NAME[sheet.class] or ADB.CLASS_BY_NAME["Guerrier"]
    local base = type(sheet.base) == "table" and sheet.base or {}
    local lvl = max(1, floor(tonumber(sheet.level) or 1)) - 1
    local eq = Stats.EquipmentBonus(sheet)
    local out = {}
    for i, k in ipairs(STAT_KEYS) do
        out[i] = Clamp(floor((tonumber(base[k]) or 0) + race[k] + class[k] + lvl + eq[i]), 0, ADB.MAX_FINAL_STAT)
    end
    return out[1], out[2], out[3]
end

-- Returns maxHp, maxMp, strengthMult, agilityMult, intellectMult.
function Stats.Vitals(strength, agility, intellect)
    local maxHp = floor(15 + strength / 2.5 + agility / 5)
    local maxMp = floor(5 + intellect / 2.5 + agility / 5)
    return maxHp, maxMp, strength / 40, agility / 40, intellect / 40
end

function Stats.DisplayName(name)
    if not name then return "" end
    local src = (name == ADB.playerName) and ADB.db or ADB.roster[name]
    local rp = src and src.rpName
    if rp and rp ~= "" then return rp end
    return name
end

local function LocalSource()
    local db = ADB.db
    local str, agi, int = Stats.FinalStats(db)
    return { strength = str, agility = agi, intellect = int, hp = db.hp, mp = db.mp, rpName = db.rpName,
        race = db.race, class = db.class, xp = db.xp, level = db.level, copper = db.copper, shield = db.shield }
end

function Stats.GetBlock(name)
    local src
    if name == ADB.playerName then
        if not ADB.db then return nil end
        src = LocalSource()
    else
        src = ADB.roster[name]
    end
    if not src then return nil end
    local maxHp, maxMp, sm, am, im = Stats.Vitals(src.strength, src.agility, src.intellect)
    return {
        name = name, rpName = src.rpName, race = src.race, class = src.class,
        xp = src.xp or 0, level = src.level or 1, copper = src.copper or 0, shield = src.shield or 0,
        strength = src.strength, agility = src.agility, intellect = src.intellect,
        hp = Clamp(src.hp, 0, maxHp), mp = Clamp(src.mp, 0, maxMp), maxHp = maxHp, maxMp = maxMp,
        strengthMult = sm, agilityMult = am, intellectMult = im,
    }
end

-- Applies a sheet mutation; full HP/MP follow the new maximum.
function Stats.ModifySheet(fn)
    local db = ADB.db
    local before = Stats.GetBlock(ADB.playerName)
    fn(db)
    local after = Stats.GetBlock(ADB.playerName)
    if db.hp >= before.maxHp then db.hp = after.maxHp end
    if db.mp >= before.maxMp then db.mp = after.maxMp end
    db.hp = Clamp(db.hp, 0, after.maxHp)
    db.mp = Clamp(db.mp, 0, after.maxMp)
    ADB.Sync.AfterLocalChange()
end

function Stats.SetRace(name)
    if not ADB.RACE_BY_NAME[name] then return end
    Stats.ModifySheet(function(db) db.race = name end)
end

function Stats.SetClass(name)
    if not ADB.CLASS_BY_NAME[name] or ADB.IsSpecialClass(name) then return end
    Stats.ModifySheet(function(db) db.class = name end)
end

function Stats.SetRpName(text)
    local new = CleanName(text)
    if new == (ADB.db.rpName or "") then return end
    ADB.db.rpName = new
    ADB.Sync.AfterLocalChange()
end

------------------------------------------------------------------------------
-- XP & rest
------------------------------------------------------------------------------
function Stats.ReceiveXP(amount)
    amount = Clamp(floor(amount), -ADB.XP_SEND_MAX, ADB.XP_SEND_MAX)
    if amount == 0 then return end
    local old = ADB.db.level
    Stats.ModifySheet(function(db)
        db.xp = max(0, db.xp + amount)
        db.level = Stats.LevelForXP(db.xp)
    end)
    ADB.Print(amount > 0 and format("Vous avez reçu %d points d'expérience.", amount)
        or format("Vous avez perdu %d points d'expérience.", -amount))
    if ADB.db.level > old then
        ADB.Print(format("Vous passez au niveau %d !", ADB.db.level))
    elseif ADB.db.level < old then
        ADB.Print(format("Vous retombez au niveau %d.", ADB.db.level))
    end
end

function Stats.ReceiveRest(pct)
    pct = Clamp(floor(pct), 0, 100)
    if ADB.Items.RemoveConsumable("ration") then
        pct = min(100, pct + ADB.RATION_BONUS)
        ADB.Print(format("Vous avez mangé une Ration : +%d%% de récupération.", ADB.RATION_BONUS))
    else
        ADB.Print("Votre repos n'a pas été réparateur car vous n'avez pas mangé à votre faim")
    end
    local db = ADB.db
    local d = Stats.GetBlock(ADB.playerName)
    db.hp = min(d.maxHp, db.hp + floor(d.maxHp * pct / 100 + 0.5))
    db.mp = min(d.maxMp, db.mp + floor(d.maxMp * pct / 100 + 0.5))
    ADB.Print(format("Le repos vous a restauré %d%% de vos PV et PM.", pct))
    ADB.Talents.OnRest()
    ADB.Sync.AfterLocalChange()
end

------------------------------------------------------------------------------
-- HP / MP / shield
------------------------------------------------------------------------------
function Stats.TrackHp() end

-- Damage first depletes the shield. t = { hp, shield }. Returns the resulting HP.
function Stats.Absorb(t, newHp)
    local damage = t.hp - newHp
    if damage <= 0 then return newHp end
    local shield = t.shield or 0
    local absorbed = min(damage, shield)
    t.shield = shield - absorbed
    return t.hp - (damage - absorbed)
end

-- kind: "hp" | "mp" | "shield". exact = bypass shield absorption.
function Stats.ApplyValue(name, kind, value, silent, exact)
    local d = Stats.GetBlock(name)
    if not d then return end
    value = Clamp(floor(value + 0.5), 0, kind == "shield" and ADB.SHIELD_MAX or d[Stats.MAX_KEY[kind]])
    local raw = value
    local isSelf = (name == ADB.playerName)
    local t = isSelf and ADB.db or ADB.roster[name]
    t.shield = t.shield or 0
    if kind == "hp" and not exact then value = Stats.Absorb(t, value) end
    t[kind] = value
    if isSelf then
        ADB.Sync.AfterLocalChange()
    else
        local wire = (kind == "hp" and exact) and "pvx" or Stats.WIRE_KIND[kind]
        ADB.Net.Send(format("SET;%s;%s;%d", name, wire, raw))
        ADB.RefreshAll()
    end
    if not silent then
        local label = Stats.DisplayName(name)
        Stats.TrackHp("J:" .. name, label, t.hp - d.hp)
        Stats.TrackHp("B:" .. name, label, t.shield - d.shield, true)
    end
end

function Stats.ChangeValue(name, kind, delta)
    local d = Stats.GetBlock(name)
    if d then Stats.ApplyValue(name, kind, d[kind] + delta) end
end