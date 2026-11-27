-- Logic/Professions.lua : professions (Alchemy v1): learning, XP / levels, crafting.
-- Persistence: db.profession = { key, level, xp }. Static data → Data/Professions.lua, UI → UI/ProfessionUI.lua.
local ADB = ADB
local floor, max, min = math.floor, math.max, math.min
local format = string.format

local Prof = {}
ADB.Professions = Prof

function Prof.LevelForXP(xp)
    xp = tonumber(xp) or 0
    local level = 1
    for i, threshold in ipairs(ADB.PROF_XP) do
        if xp >= threshold then level = i else break end
    end
    return level
end

-- Validates db.profession (called from ADB.InitDB).
function Prof.InitDB(db)
    local p = db.profession
    local def = type(p) == "table" and ADB.PROFESSION_BY_KEY[p.key]
    if not (def and def.available) then
        db.profession = nil
        return
    end
    local xp = min(ADB.PROF_XP[ADB.PROF_MAX_LEVEL], max(0, floor(tonumber(p.xp) or 0)))
    db.profession = { key = p.key, xp = xp, level = Prof.LevelForXP(xp) }
end

function Prof.Learn(key)
    local def = ADB.PROFESSION_BY_KEY[key]
    if ADB.db.profession or not (def and def.available) then return false end
    ADB.db.profession = { key = key, level = 1, xp = 0 }
    ADB.Print(format("Vous devenez %s (niveau 1).", def.title or def.name))
    ADB.ProfessionUI.Refresh()
    return true
end

-- Learned recipes (level <= profession level), ascending.
function Prof.Recipes()
    local p, res = ADB.db.profession, {}
    for _, r in ipairs(p and ADB.RECIPES[p.key] or {}) do
        if r.level <= p.level then res[#res + 1] = r end
    end
    return res
end

function Prof.XpOf(r)
    if r.xp then return r.xp end
    local n = 0
    for _, c in ipairs(r.cost) do n = n + c[2] end
    return n
end

function Prof.CanCraft(r)
    for _, c in ipairs(r.cost) do
        if ADB.Items.CountConsumable(c[1]) < c[2] then return false, "Composants insuffisants." end
    end
    if not ADB.Items.CanFit(r.item, 1, r.cost) then return false, "Votre inventaire est plein !" end
    return true
end

function Prof.GainXP(n)
    local p = ADB.db.profession
    if not p or p.level >= ADB.PROF_MAX_LEVEL or n <= 0 then return end
    local before = p.level
    p.xp = min(ADB.PROF_XP[ADB.PROF_MAX_LEVEL], p.xp + n)
    p.level = Prof.LevelForXP(p.xp)
    ADB.Print(format("Métier : +%d XP.", n))
    for lvl = before + 1, p.level do
        ADB.Print(format("Votre métier passe au niveau %d !", lvl))
        for _, r in ipairs(ADB.RECIPES[p.key] or {}) do
            if r.level == lvl then
                ADB.Print("Nouvelle recette : " .. ADB.Items.ColoredName({ kind = r.item }) .. ".")
            end
        end
    end
end

function Prof.Craft(r)
    local ok, reason = Prof.CanCraft(r)
    if not ok then
        ADB.Print(reason)
        return false
    end
    for _, c in ipairs(r.cost) do ADB.Items.Spend(c[1], c[2]) end
    local item = { kind = r.item }
    ADB.Items.Add(item, 1)
    ADB.Print(format("Vous fabriquez : %s.", ADB.Items.ColoredName(item)))
    Prof.GainXP(Prof.XpOf(r))
    ADB.Sync.AfterLocalChange()
    return true
end