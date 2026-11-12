-- Logic/Buffs.lua : buff/debuff definitions (GM), per-target instances, replication, per-turn resolution.
-- Wire (frozen): BA;id;bonus;mult100;key (player→GM)  BF;key;i;n;"id,left,type,value,icon,name" (GM→players)
--                BT;id;i;n;tags (GM→players)
-- Target keys: "P:<player>", "N:<npcId>", "E:<guid>" (enemy without sheet).
local ADB = ADB
local Net, Talents = ADB.Net, ADB.Talents
local floor, max, sqrt = math.floor, math.max, math.sqrt
local format = string.format
local Clamp, Encode, Decode, CleanName = ADB.Clamp, ADB.Encode, ADB.Decode, ADB.CleanName

local Buffs = {}
ADB.Buffs = Buffs

-- Behavioral type indices (what the code actually checks).
-- NOTE: LABELS keeps the legacy order of the original dropdown, which is misaligned with these
-- indices (label 5 = "Silence" but index 5 behaves as Bestial Wrath). Behavior preserved as-is.
Buffs.TYPE = { DAMAGE = 1, HEAL = 2, ROOT = 3, STUN = 4, WRATH = 5, SILENCE = 6, ADVANTAGE = 7, DISADVANTAGE = 8 }
Buffs.LABELS = { "Dégâts", "Soins", "Immobilisation", "Étourdissement", "Silence", "Avantage", "Désavantage",
    "Courroux Bestial" }
local T = Buffs.TYPE
local MAX_DEFS, PER_TARGET = 12, 8

Buffs.active = {}      -- [key] = { instance… }
Buffs.tmp = {}         -- partial BF reception
Buffs.tags = {}        -- [buffId] = tags (received from GM)
Buffs.tagBuffer = {}
local tagSent = {}

------------------------------------------------------------------------------
-- Definitions (GM)
------------------------------------------------------------------------------
function Buffs.InitDB()
    local db, defs, maxId = ADB.db, {}, 0
    if type(db.buffDefs) == "table" then
        for _, d in ipairs(db.buffDefs) do
            if type(d) == "table" and tonumber(d.id) and #defs < MAX_DEFS then
                local id = floor(d.id)
                defs[#defs + 1] = {
                    id = id, name = CleanName(d.name):sub(1, 24), icon = ADB.SanitizeIcon(d.icon),
                    duration = Clamp(floor(tonumber(d.duration) or 1), 1, 20),
                    buffType = Clamp(floor(tonumber(d.buffType) or 1), 1, #Buffs.LABELS),
                    value = Clamp(floor(tonumber(d.value) or 0), 0, 999),
                    tags = Talents.SanitizeTags(d.tags),
                }
                maxId = max(maxId, id)
            end
        end
    end
    db.buffDefs = defs
    if type(db.nextBuffId) ~= "number" or db.nextBuffId <= maxId then db.nextBuffId = maxId + 1 end
end

function Buffs.GetDef(id)
    for _, d in ipairs(ADB.db.buffDefs) do if d.id == id then return d end end
end

function Buffs.GetDefByName(name)
    name = name:lower()
    for _, d in ipairs(ADB.db.buffDefs) do if d.name:lower() == name then return d end end
end

function Buffs.CreateDef(name, icon, duration, buffType, value, tags, editId)
    if not ADB.IsGM() then return false end
    name = CleanName(name):sub(1, 24)
    if name == "" then
        ADB.Print("Donnez un nom.")
        return false
    end
    local d = editId and Buffs.GetDef(editId)
    if not d then
        if #ADB.db.buffDefs >= MAX_DEFS then
            ADB.Print("Maximum " .. MAX_DEFS .. " buffs/debuffs.")
            return false
        end
        local id = ADB.db.nextBuffId
        ADB.db.nextBuffId = id + 1
        d = { id = id }
        table.insert(ADB.db.buffDefs, d)
    end
    d.name, d.icon, d.duration, d.buffType, d.value = name, icon, Clamp(duration, 1, 20), buffType, Clamp(value, 0, 999)
    d.tags = Talents.SanitizeTags(tags)
    Buffs.ResendTags(d.id)
    return true
end

function Buffs.DeleteDef(id)
    for i, d in ipairs(ADB.db.buffDefs) do
        if d.id == id then
            table.remove(ADB.db.buffDefs, i)
            break
        end
    end
    if ADB.bufFrame and ADB.bufFrame.editId == id then ADB.bufFrame.editId = nil end
    ADB.BuffUI.RefreshWindow()
end

------------------------------------------------------------------------------
-- Tags (GM → players, needed for tag-driven passives)
------------------------------------------------------------------------------
local function SendTags(id)
    local d = Buffs.GetDef(id)
    if not d then return end
    local s = table.concat(d.tags or {}, ",")
    if tagSent[id] == s then return end
    tagSent[id] = s
    local chunks = ADB.SplitUtf8(s, 120)
    if #chunks == 0 then chunks = { "" } end
    for i, c in ipairs(chunks) do Net.Enqueue(format("BT;%d;%d;%d;%s", id, i, #chunks, c)) end
end

function Buffs.ResendTags(id)
    tagSent[id] = nil
    if ADB.IsGM() and ADB.phase ~= "IDLE" then SendTags(id) end
end

function Buffs.GetTags(b)
    if ADB.IsGM() then
        local d = Buffs.GetDef(b.id)
        return d and d.tags or {}
    end
    return Buffs.tags[b.id] or {}
end

function Buffs.HasTag(b, tag)
    for _, t in ipairs(Buffs.GetTags(b)) do if t == tag then return true end end
    return false
end

------------------------------------------------------------------------------
-- Target keys
------------------------------------------------------------------------------
function Buffs.UnitKey(unit)
    if not UnitExists(unit) then return nil end
    local name = UnitName(unit)
    if UnitIsPlayer(unit) then
        if name == ADB.playerName or ADB.roster[name] then return "P:" .. name end
        return nil
    end
    local p = ADB.NPC.FindByName(name)
    if p then return "N:" .. p.id end
    return "E:" .. (UnitGUID(unit) or "?")
end

function Buffs.KeyFromEntry(e)
    if not e then return nil end
    if e.kind == "P" then return "P:" .. e.id end
    local p = ADB.NPC.FindByName(e.name)
    if p then return "N:" .. p.id end
    return "E:" .. e.id
end

function Buffs.KeyName(key)
    local kind, id = key:sub(1, 1), key:sub(3)
    if kind == "P" then return ADB.Stats.DisplayName(id) end
    if kind == "N" and ADB.db then
        local p = ADB.NPC.FindById(ADB.db.npcs, tonumber(id))
        if p then return ADB.NPC.DisplayName(p) end
    end
    return "La cible"
end

-- Player ↔ own pet share certain bonuses.
function Buffs.LinkedKey(key)
    if not ADB.playerName then return nil end
    local pet = ADB.Pets.GetPet()
    if not pet then return nil end
    if key == "P:" .. ADB.playerName then return "N:" .. pet.id end
    if key == "N:" .. pet.id then return "P:" .. ADB.playerName end
end

function Buffs.Has(key, buffType)
    for _, b in ipairs(Buffs.active[key] or {}) do if b.buffType == buffType then return true end end
    return false
end

-- Returns accuracyBonus, critBonus, damageMultiplier, advantage (1 / -1 / 0).
function Buffs.GetBonus(key)
    local acc, crit, dmg = 0, 0, 1
    local function Scan(k)
        for _, b in ipairs(Buffs.active[k] or {}) do
            if b.buffType == T.WRATH then acc, crit, dmg = 5, 5, 1.5 end
        end
    end
    Scan(key)
    local linked = Buffs.LinkedKey(key)
    if linked then Scan(linked) end
    local adv, dis
    for _, b in ipairs(Buffs.active[key] or {}) do
        if b.buffType == T.ADVANTAGE then adv = true elseif b.buffType == T.DISADVANTAGE then dis = true end
    end
    return acc, crit, dmg, (adv and not dis) and 1 or ((dis and not adv) and -1 or 0)
end

------------------------------------------------------------------------------
-- Application / replication
------------------------------------------------------------------------------
local function Entry(b)
    return format("%d,%d,%d,%d,%s,%s", b.id, b.left, b.buffType, b.value, b.icon, ADB.Escape(b.name, "[%%;,]"))
end

local function ReadEntry(e)
    local id, left, bt, value, icon, name = strsplit(",", e)
    id, left, bt, value = tonumber(id), tonumber(left), tonumber(bt), tonumber(value)
    if not (id and left and bt and value and bt >= 1 and bt <= #Buffs.LABELS and icon) then return nil end
    return { id = floor(id), left = Clamp(floor(left), 1, 99), buffType = floor(bt),
        value = Clamp(floor(value), 0, 999), icon = ADB.SanitizeIcon(icon),
        name = CleanName(Decode(name or "")):sub(1, 40) }
end

function Buffs.Broadcast(key)
    if not ADB.IsGM() then return end
    local list, k = Buffs.active[key], Encode(key)
    for _, b in ipairs(list or {}) do SendTags(b.id) end
    if not list or #list == 0 then
        Net.Enqueue(format("BF;%s;0;0;", k))
        return
    end
    for i, b in ipairs(list) do Net.Enqueue(format("BF;%s;%d;%d;%s", k, i, #list, Entry(b))) end
end

function Buffs.BroadcastAll()
    if not ADB.IsGM() then return end
    wipe(tagSent)
    for key in pairs(Buffs.active) do Buffs.Broadcast(key) end
end

-- GM only. inst = { id, left, buffType, value, icon, name }
function Buffs.Apply(key, inst)
    if not ADB.IsGM() then return false end
    if ADB.phase == "IDLE" then
        ADB.Print("Les buffs/debuffs ne s'appliquent qu'en combat.")
        return false
    end
    local list = Buffs.active[key]
    if not list then
        list = {}
        Buffs.active[key] = list
    end
    local placed
    for i, b in ipairs(list) do
        if b.id == inst.id then
            list[i] = inst
            placed = true
            break
        end
    end
    if not placed then
        if #list >= PER_TARGET then return false end
        list[#list + 1] = inst
    end
    ADB.Net.Announce(format("%s est affecté par %s (%d tour%s).", Buffs.KeyName(key), inst.name,
        inst.left, inst.left > 1 and "s" or ""))
    Buffs.Broadcast(key)
    ADB.BuffUI.Refresh()
    return true
end

function Buffs.ApplyDef(def, key, bonus, mult)
    local value = def.value
    if def.buffType <= 2 then value = Clamp(floor((def.value + (bonus or 0)) * (mult or 1) + 0.5), 0, 999) end
    return Buffs.Apply(key, { id = def.id, left = def.duration, buffType = def.buffType, value = value,
        icon = def.icon, name = def.name })
end

-- id < 0 : built-in effect (-1 stun; bonus = number of turns). GM applies; players ask the GM.
function Buffs.Request(id, bonus, mult, key)
    if not key then return end
    if ADB.IsGM() then
        Buffs.Process(id, bonus, floor(mult * 100 + 0.5), key)
    elseif IsInGroup() then
        Net.Enqueue(format("BA;%d;%d;%d;%s", id, bonus, floor(mult * 100 + 0.5), Encode(key)))
    end
end

function Buffs.Process(id, bonus, mult100, key)
    if id == -1 then
        return Buffs.Apply(key, { id = -1, left = Clamp(bonus, 1, 3), buffType = T.STUN, value = 0,
            icon = "Spell_Frost_Stun", name = "Étourdissement" })
    end
    local def = Buffs.GetDef(id)
    if def then Buffs.ApplyDef(def, key, Clamp(bonus, 0, 5), Clamp(mult100, 0, 3000) / 100) end
end

function Buffs.ForceApply(id)
    local def = Buffs.GetDef(id)
    local key = Buffs.UnitKey("target")
    if not ADB.IsGM() or not def then return end
    if not key then
        ADB.Print("Ciblez un personnage valide.")
        return
    end
    Buffs.ApplyDef(def, key, 0, 1)
end

function Buffs.FromTalent(n, targets)
    local mult, bonus = Talents.Multiplier(n), Talents.SpecBonus(n)
    if not targets or #targets == 0 then targets = { { kind = "P", id = ADB.playerName } } end
    for _, e in ipairs(targets) do Buffs.Request(n.buffId, bonus, mult, Buffs.KeyFromEntry(e)) end
end

local function ValidKey(key) return key:match("^[PNE]:.+") and #key < 80 end

local function Receive(cmd, sender, p)
    if cmd == "BA" then
        if not ADB.IsGM() or not ADB.roster[sender] then return end
        local id, bonus, m = tonumber(p[2]), tonumber(p[3]), tonumber(p[4])
        local key = Decode(p[5] or "")
        if id and bonus and m and ValidKey(key) then Buffs.Process(floor(id), floor(bonus), floor(m), key) end
    elseif cmd == "BF" then
        if ADB.IsGM() or not ADB.IsGMName(sender) then return end
        local key = Decode(p[2] or "")
        local i, n = tonumber(p[3]), tonumber(p[4])
        if not (i and n and ValidKey(key)) then return end
        if n == 0 then
            Buffs.active[key] = nil
        elseif i >= 1 and i <= n and n <= PER_TARGET then
            local t = Buffs.tmp[key]
            if i == 1 or not t or t.n ~= n then
                t = { n = n, l = {} }
                Buffs.tmp[key] = t
            end
            t.l[i] = ReadEntry(p[5] or "")
            for j = 1, n do if not t.l[j] then return end end
            Buffs.active[key], Buffs.tmp[key] = t.l, nil
        else
            return
        end
    elseif cmd == "BT" then
        if ADB.IsGM() or not ADB.IsGMName(sender) then return end
        local id, i, n = tonumber(p[2]), tonumber(p[3]), tonumber(p[4])
        if not (id and i and n and n >= 1 and n <= 20 and i >= 1 and i <= n) then return end
        id, i, n = floor(id), floor(i), floor(n)
        local t = Buffs.tagBuffer[id]
        if i == 1 or not t or t.n ~= n then
            t = { n = n, l = {} }
            Buffs.tagBuffer[id] = t
        end
        t.l[i] = p[5] or ""
        for j = 1, n do if not t.l[j] then return end end
        Buffs.tags[id] = Talents.SanitizeTags(table.concat(t.l, "", 1, n))
        Buffs.tagBuffer[id] = nil
    end
    ADB.BuffUI.Refresh()
end
for _, cmd in ipairs({ "BA", "BF", "BT" }) do
    Net.Register(cmd, function(sender, message, c) return Receive(c, sender, Net.Split(message)) end)
end

------------------------------------------------------------------------------
-- Per-turn resolution (GM): damage/heal over time, duration countdown
------------------------------------------------------------------------------
local function ResolveEffect(key, b)
    local kind, id = key:sub(1, 1), key:sub(3)
    local delta = b.buffType == T.DAMAGE and -b.value or b.value
    if kind == "P" then
        local d = ADB.Stats.GetBlock(id)
        if d and id ~= ADB.playerName then ADB.Stats.ApplyValue(id, "hp", d.hp + delta) end
    elseif kind == "N" then
        local p = ADB.NPC.FindById(ADB.db.npcs, tonumber(id))
        if p then ADB.NPC.ApplyValue(p.id, "hp", p.hp + delta) end
    else
        ADB.Measure.AddDamage(id, -delta)
    end
end

local function Resolve(allies)
    local changed = {}
    for key, list in pairs(Buffs.active) do
        local kind, isAlly = key:sub(1, 1), false
        if kind == "P" then
            isAlly = true
        elseif kind == "N" then
            local p = ADB.NPC.FindById(ADB.db.npcs, tonumber(key:sub(3)))
            isAlly = p and p.ally or false
        end
        if isAlly == allies then
            for i = #list, 1, -1 do
                local b = list[i]
                if b.buffType <= 2 then ResolveEffect(key, b) end
                b.left = b.left - 1
                if b.left <= 0 then table.remove(list, i) end
            end
            if #list == 0 then Buffs.active[key] = nil end
            changed[key] = true
        end
    end
    for key in pairs(changed) do Buffs.Broadcast(key) end
    ADB.BuffUI.Refresh()
end

local prevPhase = "IDLE"
ADB.Combat.OnPhase(function(phase)
    local prev = prevPhase
    prevPhase = phase
    if prev == phase then return end
    if phase == "IDLE" then
        wipe(Buffs.active)
        wipe(Buffs.tmp)
        wipe(tagSent)
        ADB.BuffUI.Refresh()
    elseif ADB.IsGM() then
        if prev == "PLAYER_TURN" then Resolve(true)
        elseif prev == "ENEMY_TURN" then Resolve(false) end
    end
end)

hooksecurefunc(ADB.NPC, "ScheduleFull", function()
    if ADB.IsGM() and ADB.phase ~= "IDLE" and not Buffs.resyncPending then
        Buffs.resyncPending = true
        C_Timer.After(2, function()
            Buffs.resyncPending = false
            Buffs.BroadcastAll()
        end)
    end
end)

------------------------------------------------------------------------------
-- Root enforcement: warns the player who moves while rooted
------------------------------------------------------------------------------
local ticker, acc, ix, iy, warned = CreateFrame("Frame"), 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.3 then return end
    acc = 0
    if ADB.db and ADB.playerName and ADB.phase ~= "IDLE" and not ADB.IsGM()
        and Buffs.Has("P:" .. ADB.playerName, T.ROOT) then
        local y, x = UnitPosition("player")
        if x then
            if not ix then
                ix, iy = x, y
            elseif not warned and sqrt((x - ix) ^ 2 + (y - iy) ^ 2) > 1.5 then
                warned = true
                UIErrorsFrame:AddMessage("Vous êtes immobilisé : déplacement interdit !", 1, 0.3, 0.3)
                ADB.Net.Announce(format("%s s'est déplacé alors qu'il est immobilisé.",
                    ADB.Stats.DisplayName(ADB.playerName)))
            end
        end
    else
        ix, iy, warned = nil, nil, nil
    end
end)

ADB.Events.Register("PLAYER_LOGIN", Buffs.InitDB)

function Buffs.SlashCommand(rest)
    if not ADB.IsGM() then
        ADB.Print("Réservé au MJ.")
        return
    end
    rest = strtrim(rest or "")
    if rest == "" then return ADB.BuffUI.ToggleWindow() end
    local def = Buffs.GetDefByName(rest)
    if not def then
        ADB.Print("Buff/debuff inconnu : " .. rest)
        return
    end
    Buffs.ForceApply(def.id)
end
ADB.Slash.Register({ "buff", "debuff" }, Buffs.SlashCommand)