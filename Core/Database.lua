-- Core/Database.lua : SavedVariables defaults, schema migration (FR→EN keys), validation.
local ADB = ADB
local floor, max = math.floor, math.max
local Clamp, CleanName = ADB.Clamp, ADB.CleanName

ADB.DB_DEFAULTS = {
    xp = 0, level = 1, race = "Humain", class = "Guerrier",
    base = { strength = 0, agility = 0, intellect = 0 },
    rpName = "", replaceUI = true, minimap = { angle = 200 },
    npcs = {}, nextNpcId = 1, copper = 0, shield = 0, inventory = {}, equipment = {},
    talents = { trees = {}, learned = {}, cooldowns = {} },
}

------------------------------------------------------------------------------
-- Migration schema 1 (French keys) -> 2 (English keys). Idempotent.
------------------------------------------------------------------------------
local MAP = {
    root = { nomRP = "rpName", uiRemplacee = "replaceUI", pnjs = "npcs", pnjProchainId = "nextNpcId",
        pc = "copper", sh = "shield", inv = "inventory", equip = "equipment", classe = "class",
        pv = "hp", pm = "mp", quetes = "quests", qMin = "questsMinimized", qPos = "questsPos",
        tyPos = "typingPos", sec = "secondary", sha = "shaForm", buffProchainId = "nextBuffId" },
    base = { force = "strength", agilite = "agility", intelligence = "intellect" },
    talents = { arbres = "trees", appris = "learned", cd = "cooldowns", extras = "extraClasses" },
    tree = { noeuds = "nodes", prochain = "nextId", cbProchain = "nextBoxId" },
    node = { typ = "nodeType", inter = "effect", elem = "element", lim = "limit", reac = "reaction",
        bonus = "bonusAction", req = "requires", nom = "name", coutPV = "hpCost", portee = "range",
        precision = "accuracy", zoe = "aoe", spe = "isSpec", specX = "specTagX", specY = "specTagY" },
    npc = { nom = "name", pvMax = "maxHp", pmMax = "maxMp", pv = "hp", pm = "mp", sh = "shield",
        rp = "rpName", classe = "class", pc = "copper", force = "strength", agilite = "agility",
        intelligence = "intellect" },
    item = { rar = "rarity", st = "stats", nom = "name", comp = "skillsText", sk = "skillIds" },
    buffDef = { nom = "name", duree = "duration", typ = "buffType", val = "value" },
    quest = { t = "title", d = "desc" },
    sha = { niv = "tier", HealthBeforeTransform = "hpBeforeTransform" },
    secondary = { nom = "name", rp = "rpName", classe = "class", pv = "hp", pm = "mp", sh = "shield",
        pc = "copper", inv = "inventory", equip = "equipment", appris = "learned", cd = "cooldowns",
        extras = "extraClasses" },
}

local function Rename(t, map)
    if type(t) ~= "table" then return end
    for old, new in pairs(map) do
        if t[old] ~= nil then
            if t[new] == nil then t[new] = t[old] end
            t[old] = nil
        end
    end
end

local function MigrateItems(inv, eq)
    for _, it in pairs(type(inv) == "table" and inv or {}) do Rename(it, MAP.item) end
    for _, it in pairs(type(eq) == "table" and eq or {}) do Rename(it, MAP.item) end
end

function ADB.MigrateDB(db)
    if (tonumber(db.schema) or 1) >= ADB.DB_SCHEMA then return end
    Rename(db, MAP.root)
    Rename(db.base, MAP.base)
    MigrateItems(db.inventory, db.equipment)
    if type(db.talents) == "table" then
        Rename(db.talents, MAP.talents)
        for _, tree in pairs(type(db.talents.trees) == "table" and db.talents.trees or {}) do
            Rename(tree, MAP.tree)
            for _, node in pairs(type(tree.nodes) == "table" and tree.nodes or {}) do Rename(node, MAP.node) end
        end
    end
    for _, p in ipairs(type(db.npcs) == "table" and db.npcs or {}) do Rename(p, MAP.npc) end
    for _, d in ipairs(type(db.buffDefs) == "table" and db.buffDefs or {}) do Rename(d, MAP.buffDef) end
    for _, q in pairs(type(db.quests) == "table" and db.quests or {}) do Rename(q, MAP.quest) end
    Rename(db.aspiration, MAP.quest)
    Rename(db.shaForm, MAP.sha)
    local s = db.secondary
    if type(s) == "table" then
        Rename(s, MAP.secondary)
        Rename(s.base, MAP.base)
        MigrateItems(s.inventory, s.equipment)
    end
    db.schema = ADB.DB_SCHEMA
end

------------------------------------------------------------------------------
-- Init & validation (called on ADDON_LOADED)
------------------------------------------------------------------------------
function ADB.InitDB()
    AddonDesBrumesDB = AddonDesBrumesDB or {}
    local db = AddonDesBrumesDB
    ADB.MigrateDB(db)
    db.schema = ADB.DB_SCHEMA

    for key, value in pairs(ADB.DB_DEFAULTS) do
        if db[key] == nil then db[key] = (type(value) == "table") and CopyTable(value) or value end
    end
    if type(db.minimap) ~= "table" then db.minimap = CopyTable(ADB.DB_DEFAULTS.minimap) end
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = ADB.DB_DEFAULTS.minimap.angle end
    db.rpName = CleanName(db.rpName)
    db.bonusForce, db.bonusAgi, db.bonusInt = nil, nil, nil   -- legacy fields

    if not ADB.RACE_BY_NAME[db.race] then db.race = "Humain" end
    if not ADB.CLASS_BY_NAME[db.class] or ADB.IsSpecialClass(db.class) then db.class = "Guerrier" end
    if type(db.base) ~= "table" then db.base = CopyTable(ADB.DB_DEFAULTS.base) end
    for _, k in ipairs({ "strength", "agility", "intellect" }) do db.base[k] = tonumber(db.base[k]) or 0 end

    db.xp = max(0, floor(tonumber(db.xp) or 0))
    db.level = ADB.Stats.LevelForXP(db.xp)
    db.copper = Clamp(floor(tonumber(db.copper) or 0), 0, ADB.COPPER_MAX)
    db.shield = Clamp(floor(tonumber(db.shield) or 0), 0, ADB.SHIELD_MAX)

    local inv = {}
    if type(db.inventory) == "table" then
        for i = 1, ADB.INV_SLOTS do
            local it = ADB.Items.Validate(db.inventory[i])
            if it then inv[i] = it end
        end
    end
    db.inventory = inv

    local eq = {}
    if type(db.equipment) == "table" then
        for _, s in ipairs(ADB.EQUIP_SLOTS) do
            local it = ADB.Items.Validate(db.equipment[s.key])
            if it and it.kind == "equip" and it.slot == s.key then eq[s.key] = it end
        end
    end
    db.equipment = eq

    local valid, maxId = {}, 0
    if type(db.npcs) == "table" then
        for _, p in ipairs(db.npcs) do
            if type(p) == "table" and tonumber(p.id) and tonumber(p.maxHp) and tonumber(p.maxMp)
                and #valid < ADB.NPC_MAX then
                local maxHp = Clamp(floor(p.maxHp), 1, ADB.NPC_STAT_MAX)
                local maxMp = Clamp(floor(p.maxMp), 0, ADB.NPC_STAT_MAX)
                local name = CleanName(p.name)
                if name == "" then name = "PNJ" end
                local id = floor(p.id)
                local rp = type(p.rpName) == "string" and CleanName(p.rpName) or ""
                valid[#valid + 1] = {
                    id = id, name = name, maxHp = maxHp, maxMp = maxMp,
                    hp = Clamp(floor(tonumber(p.hp) or maxHp), 0, maxHp),
                    mp = Clamp(floor(tonumber(p.mp) or maxMp), 0, maxMp),
                    shield = Clamp(floor(tonumber(p.shield) or 0), 0, ADB.SHIELD_MAX),
                    ally = p.ally == true,
                    owner = (type(p.owner) == "string" and p.owner ~= "") and CleanName(p.owner) or nil,
                    rpName = rp ~= "" and rp:sub(1, 40) or nil,
                    petType = ADB.PET_TYPES[p.petType or ""] and p.petType or nil,
                }
                maxId = max(maxId, id)
            end
        end
    end
    db.npcs = valid
    if type(db.nextNpcId) ~= "number" or db.nextNpcId <= maxId then db.nextNpcId = maxId + 1 end

    local str, agi, int = ADB.Stats.FinalStats(db)
    local maxHp, maxMp = ADB.Stats.Vitals(str, agi, int)
    if db.hp == nil then db.hp = maxHp end
    if db.mp == nil then db.mp = maxMp end
    db.hp = Clamp(db.hp, 0, maxHp)
    db.mp = Clamp(db.mp, 0, maxMp)

    ADB.Talents.InitDB(db)
    ADB.db = db
end