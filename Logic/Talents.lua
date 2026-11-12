-- Logic/Talents.lua : talent trees (data model, validation), learning, points, cooldowns, state.
-- Networking → TalentNet.lua · execution → TalentUse.lua · windows → UI/TalentWindow.lua, UI/ActionBar.lua.
-- NOTE: every wrappable function is called through the `Talents` table (never a local alias).
local ADB = ADB
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local Clamp, CleanName = ADB.Clamp, ADB.CleanName

local Talents = {}
ADB.Talents = Talents
Talents.viewClass = nil   -- tree currently displayed in the window (nil = own class)
Talents.pending   = nil   -- [token] = request awaiting GM approval (set in Init)
Talents.token     = 0
Talents.source    = nil   -- GM name trees were requested from

local TALENT = {
    COLS = 12, ROWS = 32, XOFF = 1000000, CELL = 52, ICON = 38,
    MAX_REQUIRES = 6, DESC_MAX = 1000, NAME_MAX = 40, MANA_MAX = 999, HP_COST_MAX = 999,
    RANGE_MAX = 200, AOE_MAX = 200, TAGS_MAX = 30,
    NODE_TYPES = { "Actif", "Passif" },
    STATS = { "Aucune", "Force", "Agilité", "Intelligence", "Principale" },
    EFFECT_TYPES = { "Dégâts", "Soins", "Bouclier", "Autre" },
    ELEMENTS = { "Physique", "Sacré", "Ombre", "Chaos", "Feu", "Nature", "Astral", "Givre" },
    -- order is persisted (node.limit = index). unit: r = rest, t = turn, i = unlimited. charges: multi-use.
    USE_LIMITS = {
        { label = "1/repos", duration = 1, unit = "r" },
        { label = "1/5 tours", duration = 5, unit = "t" },
        { label = "1/10 tours", duration = 10, unit = "t" },
        { label = "1/3 repos", duration = 3, unit = "r" },
        { label = "Illimité", duration = 0, unit = "i" },
        { label = "2/repos", duration = 2, unit = "r", charges = 2 },
    },
    TAG_REQUIREMENTS = { dreadsteed = "Pierre d'âme de Destrier" },
}
ADB.TALENT = TALENT
local USE_LIMITS = TALENT.USE_LIMITS

------------------------------------------------------------------------------
-- Sanitizers & validation
------------------------------------------------------------------------------
function Talents.SanitizeDesc(s)
    s = tostring(s or ""):gsub("[%c|]", " ")
    return strtrim(s):sub(1, TALENT.DESC_MAX * 2)
end

function Talents.SanitizeTag(s)
    return (tostring(s or ""):lower():match("[%w_]+") or ""):sub(1, 16)
end

function Talents.SanitizeTags(s)
    local out, seen = {}, {}
    local src = type(s) == "table" and table.concat(s, ",") or tostring(s or "")
    for w in src:lower():gmatch("[%w_]+") do
        w = w:sub(1, 32)
        if not seen[w] and #out < TALENT.TAGS_MAX then
            seen[w] = true
            out[#out + 1] = w
        end
    end
    return out
end

local function ApplyExtras(n, t)
    n.hpCost = Clamp(floor(tonumber(t.hpCost) or -1), -1, TALENT.HP_COST_MAX)
    n.range = Clamp(floor(tonumber(t.range) or -1), -1, TALENT.RANGE_MAX)
    n.accuracy = Clamp(floor(tonumber(t.accuracy) or -1), -1, 100)
    n.aoe = Clamp(floor(tonumber(t.aoe) or -1), -1, TALENT.AOE_MAX)
    n.tags = Talents.SanitizeTags(t.tags)
    n.isSpec, n.specTagX, n.specTagY = (t.isSpec == true), Talents.SanitizeTag(t.specTagX), Talents.SanitizeTag(t.specTagY)
    n.buffId = (n.nodeType == 1) and Clamp(floor(tonumber(t.buffId) or 0), 0, 9999) or 0
    if n.nodeType == 2 then
        n.hpCost, n.range, n.accuracy, n.aoe = -1, -1, -1, -1
    else
        n.isSpec, n.specTagX, n.specTagY = false, "", ""
    end
end
Talents.ApplyExtras = ApplyExtras

function Talents.ValidateNode(t)
    if type(t) ~= "table" then return nil end
    local id = floor(tonumber(t.id) or 0)
    if id < 1 then return nil end
    local name = CleanName(t.name):sub(1, TALENT.NAME_MAX * 2)
    if name == "" then name = "Talent" end
    local requires, seen = {}, {}
    if type(t.requires) == "table" then
        for _, r in ipairs(t.requires) do
            r = floor(tonumber(r) or 0)
            if r >= 1 and r ~= id and not seen[r] and #requires < TALENT.MAX_REQUIRES then
                seen[r] = true
                requires[#requires + 1] = r
            end
        end
    end
    local n = {
        id = id,
        x = Clamp(floor(tonumber(t.x) or 1), 1, TALENT.COLS),
        y = Clamp(floor(tonumber(t.y) or 1), 1, TALENT.ROWS),
        nodeType = Clamp(floor(tonumber(t.nodeType) or 1), 1, 2),
        stat = Clamp(floor(tonumber(t.stat) or 1), 1, #TALENT.STATS),
        effect = Clamp(floor(tonumber(t.effect) or 4), 1, 4),
        element = Clamp(floor(tonumber(t.element) or 1), 1, 8),
        mana = Clamp(floor(tonumber(t.mana) or 0), 0, TALENT.MANA_MAX),
        limit = Clamp(floor(tonumber(t.limit) or 5), 1, #USE_LIMITS),
        reaction = t.reaction == true,
        bonusAction = t.bonusAction == true,
        icon = ADB.SanitizeIcon(t.icon),
        name = name,
        desc = Talents.SanitizeDesc(t.desc),
        requires = requires,
    }
    ApplyExtras(n, t)
    if n.nodeType == 2 then n.mana, n.limit, n.reaction, n.bonusAction = 0, 5, false, false end
    return n
end

-- ColorBox: purely visual background rectangle of a tree.
function Talents.ValidateColorBox(t)
    if type(t) ~= "table" then return nil end
    local id = floor(tonumber(t.id) or 0)
    if id < 1 then return nil end
    local x1 = Clamp(floor(tonumber(t.x1) or 1), 1, TALENT.COLS)
    local x2 = Clamp(floor(tonumber(t.x2) or 1), 1, TALENT.COLS)
    local y1 = Clamp(floor(tonumber(t.y1) or 1), 1, TALENT.ROWS)
    local y2 = Clamp(floor(tonumber(t.y2) or 1), 1, TALENT.ROWS)
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end
    return { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        r = Clamp(floor(tonumber(t.r) or 80), 0, 255), g = Clamp(floor(tonumber(t.g) or 80), 0, 255),
        b = Clamp(floor(tonumber(t.b) or 80), 0, 255), a = Clamp(floor(tonumber(t.a) or 30), 5, 100) }
end

-- Validates db.talents = { trees, learned, cooldowns, extraClasses }.
function Talents.InitDB(db)
    if type(db.talents) ~= "table" then db.talents = {} end
    local T = db.talents
    local trees = {}
    if type(T.trees) == "table" then
        for class, a in pairs(T.trees) do
            if ADB.CLASS_BY_NAME[class] and type(a) == "table" and type(a.nodes) == "table" then
                local nodes, maxId = {}, 0
                for _, t in pairs(a.nodes) do
                    local n = Talents.ValidateNode(t)
                    if n and not nodes[n.id] then
                        nodes[n.id] = n
                        maxId = max(maxId, n.id)
                    end
                end
                local boxes, maxBox = {}, 0
                if type(a.colorBoxes) == "table" then
                    for _, tb in pairs(a.colorBoxes) do
                        local b = Talents.ValidateColorBox(tb)
                        if b and not boxes[b.id] then
                            boxes[b.id] = b
                            maxBox = max(maxBox, b.id)
                        end
                    end
                end
                trees[class] = {
                    nextId = max(maxId + 1, floor(tonumber(a.nextId) or 1)), nodes = nodes,
                    colorBoxes = boxes, nextBoxId = max(maxBox + 1, floor(tonumber(a.nextBoxId) or 1)),
                }
            end
        end
    end
    T.trees = trees
    local learned = {}
    if type(T.learned) == "table" then
        for class, ids in pairs(T.learned) do
            if ADB.CLASS_BY_NAME[class] and type(ids) == "table" then
                learned[class] = {}
                for id, v in pairs(ids) do
                    if v and tonumber(id) then learned[class][floor(id)] = true end
                end
            end
        end
    end
    T.learned = learned
    local cd = {}
    if type(T.cooldowns) == "table" then
        for key, v in pairs(T.cooldowns) do
            if type(key) == "string" and tonumber(v) and v > 0 then cd[key] = Clamp(floor(v), 1, 99) end
        end
    end
    T.cooldowns = cd
    local extra = {}
    if type(T.extraClasses) == "table" then
        for c, v in pairs(T.extraClasses) do
            if v and ADB.CLASS_BY_NAME[c] then extra[c] = true end
        end
    end
    T.extraClasses = extra
end

------------------------------------------------------------------------------
-- Tree access
------------------------------------------------------------------------------
local function Learned(class)
    local l = ADB.db.talents.learned
    if type(l[class]) ~= "table" then l[class] = {} end
    return l[class]
end
Talents.Learned = Learned

function Talents.GetTree(class, create)
    local trees = ADB.db.talents.trees
    if not trees[class] and create then
        trees[class] = { nextId = 1, nodes = {}, colorBoxes = {}, nextBoxId = 1 }
    end
    return trees[class]
end

function Talents.ClassIndex(name)
    for i, c in ipairs(ADB.CLASSES) do
        if c.name == name then return i end
    end
end

-- Nodes of additional classes: proxies with shifted ID (classIndex * XOFF + id).
local proxies = {}
function Talents.GetExtraNode(class, id)
    local ci = Talents.ClassIndex(class)
    local tree = Talents.GetTree(class)
    local n = tree and tree.nodes[id]
    if not (ci and n) then return nil end
    local pid = ci * TALENT.XOFF + id
    local p = proxies[pid]
    if not p or getmetatable(p).__index ~= n then
        p = setmetatable({ id = pid, rawid = id, class = class }, { __index = n })
        proxies[pid] = p
    end
    return p
end

function Talents.GetExtraNodeById(pid)
    local ci, id = floor(pid / TALENT.XOFF), pid % TALENT.XOFF
    local c = ADB.CLASSES[ci]
    if not c or c.name == ADB.db.class or not Talents.HasAccess(c.name) then return nil end
    return Talents.GetExtraNode(c.name, id)
end

-- Own-class node, or additional-class proxy (id >= XOFF).
function Talents.GetNode(id)
    if type(id) == "number" and id >= TALENT.XOFF then return Talents.GetExtraNodeById(id) end
    local tree = Talents.GetTree(ADB.db.class)
    return tree and tree.nodes[id] or nil
end

function Talents.CanEdit() return ADB.IsGM() or not IsInGroup() end

function Talents.PointsTotal() return 3 + (ADB.db.level or 1) end

------------------------------------------------------------------------------
-- Additional classes: item tag "AddClass<Name>" (inventory or worn equipment)
------------------------------------------------------------------------------
local ACCENTS = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["à"] = "a", ["â"] = "a",
    ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["û"] = "u", ["ù"] = "u", ["ç"] = "c" }
local function Slug(s)
    s = s:lower()
    s = s:gsub("[\195][\128-\191]", function(c) return ACCENTS[c] or "" end)
    return (s:gsub("[^%w]", ""))
end

local CLASS_TAG = {}   -- ["addclassmage"] = "Mage"
for _, c in ipairs(ADB.CLASSES) do
    if c.name ~= ADB.GM_CLASS and c.name ~= ADB.EQUIPMENT_CLASS then
        CLASS_TAG["addclass" .. Slug(c.name)] = c.name
    end
end

function Talents.ExtraClasses()
    local res, seen, db = {}, {}, ADB.db
    if not db then return res end
    local function Scan(it)
        if type(it) ~= "table" or type(it.tags) ~= "table" then return end
        for _, t in ipairs(it.tags) do
            local c = CLASS_TAG[t]
            if c and c ~= db.class then seen[c] = true end
        end
    end
    for i = 1, ADB.INV_SLOTS do Scan(db.inventory and db.inventory[i]) end
    for _, s in ipairs(ADB.EQUIP_SLOTS) do Scan(db.equipment and db.equipment[s.key]) end
    for _, c in ipairs(ADB.CLASSES) do
        if seen[c.name] then res[#res + 1] = c.name end
    end
    return res
end

function Talents.AccessibleClasses()
    local res = { ADB.db.class }
    for _, c in ipairs(Talents.ExtraClasses()) do res[#res + 1] = c end
    return res
end

function Talents.HasAccess(class)
    if not class then return false end
    for _, c in ipairs(Talents.AccessibleClasses()) do
        if c == class then return true end
    end
    return false
end

local function ViewClass(class)
    if class then return class end
    if Talents.viewClass and Talents.HasAccess(Talents.viewClass) then return Talents.viewClass end
    return ADB.db.class
end

------------------------------------------------------------------------------
-- Points & learning
------------------------------------------------------------------------------
function Talents.PointsUsed()
    local n = 0
    for _, class in ipairs(Talents.AccessibleClasses()) do
        local tree = Talents.GetTree(class)
        if tree then
            for id in pairs(Learned(class)) do
                local nd = tree.nodes[id]
                if nd and not Talents.HasTag(nd, "refund") then n = n + 1 end
            end
        end
    end
    return n
end

function Talents.PointsLeft() return Talents.PointsTotal() - Talents.PointsUsed() end

-- Drops invalid learned nodes, forgets lost extra classes, trims excess points, enforces single spec.
function Talents.CleanupPoints()
    local T = ADB.db.talents
    if type(T.extraClasses) ~= "table" then T.extraClasses = {} end
    local access, ok = Talents.AccessibleClasses(), {}
    for i, c in ipairs(access) do
        ok[c] = true
        if i > 1 then T.extraClasses[c] = true end
    end
    for c in pairs(T.extraClasses) do
        if not ok[c] then
            T.learned[c] = nil
            T.extraClasses[c] = nil
        end
    end
    local ids = {}
    for rank, class in ipairs(access) do
        local tree = Talents.GetTree(class)
        if tree and next(tree.nodes) ~= nil then
            local ap = Learned(class)
            for id in pairs(ap) do
                if tree.nodes[id] then ids[#ids + 1] = { class = class, id = id, rank = rank } else ap[id] = nil end
            end
        end
    end
    table.sort(ids, function(p, q)
        if p.rank ~= q.rank then return p.rank < q.rank end
        return p.id < q.id
    end)
    local paying = {}
    for _, e in ipairs(ids) do
        if not Talents.HasTag(Talents.GetTree(e.class).nodes[e.id], "refund") then paying[#paying + 1] = e end
    end
    for i = #paying, Talents.PointsTotal() + 1, -1 do Learned(paying[i].class)[paying[i].id] = nil end
    local hasSpec
    for _, e in ipairs(ids) do
        local ap = Learned(e.class)
        if ap[e.id] and Talents.GetTree(e.class).nodes[e.id].isSpec then
            if hasSpec then ap[e.id] = nil else hasSpec = true end
        end
    end
end

-- The single learned specialization (all classes), lowest id wins.
function Talents.ActiveSpec()
    for _, class in ipairs(Talents.AccessibleClasses()) do
        local tree = Talents.GetTree(class)
        if tree then
            local best
            for id in pairs(Learned(class)) do
                local n = tree.nodes[id]
                if n and n.isSpec and (not best or n.id < best.id) then best = n end
            end
            if best then return best end
        end
    end
    return nil
end

function Talents.HasTag(n, tag)
    for _, t in ipairs(n.tags) do
        if t == tag then return true end
    end
    return false
end

-- Spec tag X: +1 on the base value.
function Talents.SpecBonus(n)
    local s = Talents.ActiveSpec()
    if s and s.specTagX ~= "" and Talents.HasTag(n, s.specTagX) then return 1 end
    return 0
end

-- Tag-based prerequisites: { { name, ok }, … }
function Talents.TagRequirements(n)
    local res = {}
    for _, t in ipairs(n.tags or {}) do
        local name = TALENT.TAG_REQUIREMENTS[t]
        if name then res[#res + 1] = { name = name, ok = ADB.Items.FindByTag(t) ~= nil } end
    end
    return res
end

function Talents.PrerequisitesMet(n, class)
    class = ViewClass(class)
    local tree, ap = Talents.GetTree(class), Learned(class)
    for _, r in ipairs(n.requires) do
        if tree.nodes[r] and not ap[r] then return false end
    end
    for _, r in ipairs(Talents.TagRequirements(n)) do
        if not r.ok then return false end
    end
    return true
end

function Talents.CanLearn(n, class)
    class = ViewClass(class)
    if Learned(class)[n.id] then return false end
    if Talents.PointsLeft() <= 0 and not Talents.HasTag(n, "refund") then return false end
    if n.isSpec and Talents.ActiveSpec() then return false end
    return Talents.PrerequisitesMet(n, class)
end

-- All learned nodes (own class: real nodes; extra classes: proxies).
function Talents.LearnedNodes()
    local res = {}
    for i, class in ipairs(Talents.AccessibleClasses()) do
        local tree = Talents.GetTree(class)
        if tree then
            for id in pairs(Learned(class)) do
                local n = tree.nodes[id]
                if n then res[#res + 1] = (i == 1) and n or Talents.GetExtraNode(class, id) end
            end
        end
    end
    return res
end

-- Action bar content: learned active skills sorted by class rank, row, column, id.
function Talents.ActiveSkills()
    local rank = {}
    for i, c in ipairs(Talents.AccessibleClasses()) do rank[c] = i end
    local res = {}
    for _, n in ipairs(Talents.LearnedNodes()) do
        if n.nodeType == 1 then res[#res + 1] = n end
    end
    local function Rank(n) return n.class and rank[n.class] or 1 end
    table.sort(res, function(p, q)
        local rp, rq = Rank(p), Rank(q)
        if rp ~= rq then return rp < rq end
        if p.y ~= q.y then return p.y < q.y end
        if p.x ~= q.x then return p.x < q.x end
        return p.id < q.id
    end)
    return res
end

------------------------------------------------------------------------------
-- Dynamic values
------------------------------------------------------------------------------
-- Effective stat index (2 strength, 3 agility, 4 intellect); stat 5 = highest attribute.
function Talents.EffectiveStat(n)
    if n.stat ~= 5 then return n.stat end
    local d = ADB.Stats.GetBlock(ADB.playerName)
    if not d then return 1 end
    if d.strength >= d.agility and d.strength >= d.intellect then return 2 end
    return d.agility >= d.intellect and 3 or 4
end

function Talents.Multiplier(n)
    local s = Talents.EffectiveStat(n)
    if s <= 1 then return 1 end
    local d = ADB.Stats.GetBlock(ADB.playerName)
    if not d then return 1 end
    return ({ d.strengthMult, d.agilityMult, d.intellectMult })[s - 1]
end

-- "[2]" → raw (blue) or scaled (value+bonus)*mult (green). Returns text, first scaled value.
function Talents.FormatDescription(desc, scaled, mult, bonus)
    local first
    local text = (tostring(desc or ""):gsub("%[([%d%.,]+)%]", function(x)
        local v = tonumber((x:gsub(",", ".")))
        if not v then return nil end
        if scaled then
            local r = floor((v + (bonus or 0)) * mult + 0.5)
            first = first or r
            return "|cff40ff40" .. r .. "|r"
        end
        return "|cff66ccff" .. x .. "|r"
    end))
    return text, first
end

------------------------------------------------------------------------------
-- Cooldowns & state
------------------------------------------------------------------------------
local function CooldownKey(id) return ADB.db.class .. ":" .. id end

function Talents.GetCooldown(n) return ADB.db.talents.cooldowns[CooldownKey(n.id)] or 0 end

function Talents.SetCooldown(n)
    local L = USE_LIMITS[n.limit]
    if L.duration <= 0 then return end
    local cd, key = ADB.db.talents.cooldowns, CooldownKey(n.id)
    if L.charges then cd[key] = (cd[key] or 0) + 1 else cd[key] = L.duration end
end

-- unit: "t" (turn) or "r" (rest)
function Talents.TickCooldowns(unit)
    local cd, trees = ADB.db.talents.cooldowns, ADB.db.talents.trees
    for key, v in pairs(cd) do
        local class, id = key:match("^(.-):(%d+)$")
        local n = Talents.NodeFromId(class and trees[class], tonumber(id))
        if not n then
            cd[key] = nil
        else
            local L = USE_LIMITS[n.limit]
            if L.unit == unit then
                if L.charges or v <= 1 then cd[key] = nil else cd[key] = v - 1 end
            end
        end
    end
end

function Talents.ResetTurnCooldowns()
    local cd, trees = ADB.db.talents.cooldowns, ADB.db.talents.trees
    for key in pairs(cd) do
        local class, id = key:match("^(.-):(%d+)$")
        local n = Talents.NodeFromId(class and trees[class], tonumber(id))
        if not n or USE_LIMITS[n.limit].unit == "t" then cd[key] = nil end
    end
end

function Talents.OnRest()
    Talents.TickCooldowns("r")
    ADB.ActionBar.Refresh()
end

-- Returns ok, reason, code ("mana" | "cd") ; a code means the GM may still force it.
function Talents.GetState(n)
    local d = ADB.Stats.GetBlock(ADB.playerName)
    if n.mana > 0 and d.mp < n.mana then
        return false, format("Mana insuffisant (%d / %d requis).", d.mp, n.mana), "mana"
    end
    if n.hpCost > 0 and d.hp < n.hpCost then
        return false, format("PV insuffisants (%d / %d requis).", d.hp, n.hpCost)
    end
    local cd, L = Talents.GetCooldown(n), USE_LIMITS[n.limit]
    if cd >= (L.charges or 1) then
        if L.charges then return false, "Limite d'utilisation atteinte (jusqu'au prochain repos).", "cd" end
        return false, format("Compétence en recharge : %d %s restant%s.", cd,
            L.unit == "t" and (cd > 1 and "tours" or "tour") or "repos", ""), "cd"
    end
    return true
end

function Talents.OnPhase(phase)
    if not ADB.db or not ADB.db.talents then return end
    if phase == "PLAYER_TURN" and not ADB.IsGM() then
        Talents.TickCooldowns("t")
        if ADB.skipTurn then
            ADB.skipTurn = nil
            ADB.Print("Vous avez joué en avance avec une compétence de réaction, vous ne pouvez jouer ce tour-ci.")
            ADB.Combat.PlayerEndTurn()
        end
    elseif phase == "IDLE" then
        Talents.ResetTurnCooldowns()
        ADB.skipTurn, ADB.turnPassed = nil, nil
    end
    ADB.ActionBar.Refresh()
end

------------------------------------------------------------------------------
-- Global refresh / init
------------------------------------------------------------------------------
function Talents.Refresh()
    if not ADB.db or not ADB.playerName or not Talents.pending then return end
    Talents.CleanupPoints()
    ADB.TalentNet.RequestTrees()
    ADB.ActionBar.Refresh()
    if ADB.talFrame and ADB.talFrame:IsShown() then ADB.TalentWindow.Draw() end
end

function Talents.Init()
    Talents.pending = {}
    ADB.TalentNet.requested = {}
    ADB.ActionBar.Create()
end

hooksecurefunc(ADB.InventoryWindow, "Refresh", function()
    if ADB.db and Talents.pending then Talents.Refresh() end
end)