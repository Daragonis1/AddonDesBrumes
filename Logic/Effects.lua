-- Logic/Effects.lua : micro-script engine for talent-specific effects (scripts live in Data/EffectScripts.lua).
-- Scripts are bound to the talent NAME (or to a tag via DefineTag). One rule per line:
--   TRIGGER [cond] : command args ; command args
--   Triggers   : use (always) | hit (success / no roll) | miss (failure) | passive (talent learned)
--   Conditions : [pet] target is pet (or no target)  [!pet]  [self]  [!self]
--   Targets    : self | pet | target | zonepet:R | zonetarget:R   (R in meters)
--   Values     : 7 (scaled by stat/spec/crit) | base (first [n] of the description) | =7 (raw)
--   Commands   : damage WHO V | heal WHO V | shield WHO V | mana V | move M | cd "Talent"|"#tag" N
--                recharge "Talent" | buff WHO ID | say "text"
--   Passives   : bonus "Talent"|#tag V | manatopv | luna THRESHOLD%
-- New effect = new Effects.Define line. New command = COMMANDS.name = function(ctx, args).
local ADB = ADB
local Talents = ADB.Talents
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local Clamp = ADB.Clamp

local Effects = {}
ADB.Effects = Effects

local scripts, tagScripts, cache, tagCache = {}, {}, {}, {}
local COMMANDS = {}
Effects.COMMANDS = COMMANDS

local function Norm(s) return (tostring(s or ""):lower():gsub("[%s'’%-]+", "")) end

-- First [n] of a description.
local function BaseValue(desc)
    local s = (tostring(desc or ""):match("%[([%d%.,]+)%]") or "0")
    s = (s:gsub(",", "."))
    return tonumber(s) or 0
end

function Effects.Define(name, text)
    scripts[Norm(name)] = text
    cache[Norm(name)] = nil
end

function Effects.DefineTag(tag, text)
    tagScripts[Norm(tag)] = text
    tagCache[Norm(tag)] = nil
end

------------------------------------------------------------------------------
-- Parser
------------------------------------------------------------------------------
local function Tokens(s)
    local t, i = {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == '"' then
            local j = s:find('"', i + 1, true) or (#s + 1)
            t[#t + 1] = s:sub(i + 1, j - 1)
            i = j + 1
        else
            local j = s:find("%s", i) or (#s + 1)
            t[#t + 1] = s:sub(i, j - 1)
            i = j
        end
    end
    return t
end

local function Parse(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" and line:sub(1, 2) ~= "--" then
            local trigger, rest = line:match("^(%a+)%s*(.*)$")
            local cond
            if rest and rest:sub(1, 1) == "[" then
                local c, r = rest:match("^%[(.-)%]%s*(.*)$")
                cond, rest = c, r
            end
            rest = rest and rest:match("^:%s*(.*)$")
            if trigger and rest then
                local cmds = {}
                for part in (rest .. ";"):gmatch("(.-);") do
                    local t = Tokens(part)
                    if #t > 0 then
                        t[1] = t[1]:lower()
                        cmds[#cmds + 1] = t
                    end
                end
                out[#out + 1] = { trigger = trigger:lower(), cond = cond, cmds = cmds }
            end
        end
    end
    return out
end

-- Rules of a node: by name + by tags.
local function GetScript(n)
    local key = Norm(n.name)
    if cache[key] == nil then cache[key] = scripts[key] and Parse(scripts[key]) or false end
    local res = {}
    for _, l in ipairs(cache[key] or {}) do res[#res + 1] = l end
    for _, t in ipairs(n.tags or {}) do
        local x = tagScripts[t]
        if x then
            tagCache[t] = tagCache[t] or Parse(x)
            for _, l in ipairs(tagCache[t]) do res[#res + 1] = l end
        end
    end
    return #res > 0 and res or nil
end

------------------------------------------------------------------------------
-- Talent helpers
------------------------------------------------------------------------------
local function Learned()
    if not ADB.db or not ADB.db.talents then return {} end
    return Talents.LearnedNodes()
end

local function LearnedByName(name)
    local k = Norm(name)
    for _, n in ipairs(Learned()) do
        if Norm(n.name) == k then return n end
    end
end

local function LearnedByTag(tag)
    for _, n in ipairs(Learned()) do
        if Talents.HasTag(n, tag) then return n end
    end
end

-- Passive commands (from learned talents) matching `cmd`.
function Effects.Passives(cmd)
    local out = {}
    for _, n in ipairs(Learned()) do
        local sc = GetScript(n)
        if sc then
            for _, l in ipairs(sc) do
                if l.trigger == "passive" then
                    for _, c in ipairs(l.cmds) do
                        if c[1] == cmd then out[#out + 1] = c end
                    end
                end
            end
        end
    end
    return out
end

local function Selector(s, n)
    if s:sub(1, 1) == "#" then return Talents.HasTag(n, s:sub(2):lower()) end
    return Norm(s) == Norm(n.name)
end

------------------------------------------------------------------------------
-- Execution context
------------------------------------------------------------------------------
local function PetUnit(pet)
    if not pet then return nil end
    local function Match(u) return UnitExists(u) and UnitName(u) == pet.name end
    for _, u in ipairs({ "pet", "target", "focus", "mouseover" }) do
        if Match(u) then return u end
    end
    for i = 1, 40 do
        if Match("nameplate" .. i) then return "nameplate" .. i end
    end
    for _, u in ipairs(ADB.Group.ListUnits()) do
        if Match(u .. "target") then return u .. "target" end
    end
end

local function SelfEntry()
    return { kind = "P", id = ADB.playerName, name = ADB.Stats.DisplayName(ADB.playerName) }
end

local function Entries(who, ctx)
    local pet = ADB.Pets.GetPet()
    if who == "self" then return { SelfEntry() } end
    if who == "pet" then
        return pet and { { kind = "N", id = tostring(pet.id), name = pet.name } } or {}
    end
    if who == "target" then return ctx.data.targets or {} end
    local zone, r = who:match("^(zone%a+):(%d+)$")
    if zone then
        local center = (zone == "zonepet") and PetUnit(pet) or "target"
        if not center then
            ADB.Print("Familier introuvable (non visible) : zone centrée sur la cible.")
            center = "target"
        end
        if not UnitExists(center) then return {} end
        local res = {}
        for _, e in ipairs(ADB.Measure.ZoneAround(center, tonumber(r))) do
            if not ((e.kind == "P" and e.id == ADB.playerName) or (e.kind == "N" and pet and e.name == pet.name)) then
                res[#res + 1] = e
            end
        end
        return res
    end
    return {}
end

local function TargetIsPet(ctx)
    local c, pet = ctx.data.targets, ADB.Pets.GetPet()
    if not c or #c == 0 then return true end
    return (pet and c[1].kind == "N" and c[1].name == pet.name) and true or false
end

local function TargetIsSelf(ctx)
    local c = ctx.data.targets
    if not c or #c == 0 then return true end
    return c[1].kind == "P" and c[1].id == ADB.playerName
end

local function CheckCondition(cond, ctx)
    for atom in cond:gmatch("[^,]+") do
        atom = strtrim(atom)
        local negate = atom:sub(1, 1) == "!"
        if negate then atom = atom:sub(2) end
        local r = false
        if atom == "pet" then
            r = TargetIsPet(ctx)
        elseif atom == "self" then
            r = TargetIsSelf(ctx)
        end
        if (r and true or false) == negate then return false end
    end
    return true
end

local function Value(ctx, tok, kind)
    local n = ctx.n
    tok = tok or "base"
    local raw = tok:sub(1, 1) == "="
    local v = (tok == "base") and ctx.base or tonumber(raw and tok:sub(2) or tok) or 0
    if not raw then
        v = floor((v + Talents.SpecBonus(n)) * Talents.Multiplier(n) + 0.5)
        if kind == "damage" then v = floor(v * ctx.damageMult + 0.5) end
    end
    return max(0, v) * ctx.mult
end

local LABEL = { "dégâts", "PV rendus", "de bouclier" }

local function Apply(ctx, who, effect, v)
    local list = Entries(who or "target", ctx)
    if #list == 0 or v <= 0 then return end
    local names = {}
    for _, e in ipairs(list) do
        local luna = Effects.LunaText(e, effect, v)
        ADB.Measure.SendEffects({ e }, effect, v)
        if luna then ctx.msgs[#ctx.msgs + 1] = luna else names[#names + 1] = e.name end
    end
    if #names > 0 then
        ctx.msgs[#ctx.msgs + 1] = format("%s : %d %s.", table.concat(names, ", "), v, LABEL[effect])
    end
end

COMMANDS.damage = function(ctx, a) Apply(ctx, a[2], 1, Value(ctx, a[3], "damage")) end
COMMANDS.heal = function(ctx, a) Apply(ctx, a[2], 2, Value(ctx, a[3], "heal")) end
COMMANDS.shield = function(ctx, a) Apply(ctx, a[2], 3, Value(ctx, a[3], "shield")) end

COMMANDS.cd = function(ctx, a)
    if not (a[2] and ADB.db) then return end
    local cd, reduce, turnOnly = ADB.db.talents.cooldowns, tonumber(a[3]) or 1, a[4] == "t"
    for _, n in ipairs(Learned()) do
        local key = ADB.db.class .. ":" .. n.id
        local v = cd[key]
        if v and Selector(a[2], n) and (not turnOnly or ADB.TALENT.USE_LIMITS[n.limit].unit == "t") then
            local r = v - reduce
            cd[key] = r > 0 and r or nil
            ctx.msgs[#ctx.msgs + 1] = format("Le rechargement de %s est réduit de %d.", n.name, reduce)
        end
    end
end

COMMANDS.recharge = function(ctx, a)
    local n = a[2] and LearnedByName(a[2])
    if not n then return end
    local cd, key = ADB.db.talents.cooldowns, ADB.db.class .. ":" .. n.id
    if cd[key] then
        cd[key] = nil
        ctx.msgs[#ctx.msgs + 1] = format("%s est de nouveau disponible.", n.name)
    end
end

COMMANDS.move = function(ctx, a)
    local m = tonumber(a[2]) or 0
    if ADB.Measure.AddMovement(m) then
        ctx.msgs[#ctx.msgs + 1] = format("%s peut se déplacer de %d m supplémentaires ce tour.", ctx.who, m)
    else
        ADB.Print("Déplacement bonus : utilisable uniquement pendant votre tour.")
    end
end

COMMANDS.mana = function(ctx, a)
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local g = tonumber(a[2]) or 0
    ADB.db.mp = min(d.maxMp, ADB.db.mp + g)
    ctx.msgs[#ctx.msgs + 1] = format("Regain de mana : +%d PM.", g)
end

COMMANDS.manaint = function(ctx, a)
    local d = ADB.Stats.GetBlock(ADB.playerName)
    COMMANDS.mana(ctx, { "mana", max(0, floor((tonumber(a[2]) or 0) * d.intellectMult + 0.5)) })
end

COMMANDS.petheal = function(ctx, a)
    local t, pet = ctx.data.targets, ADB.Pets.GetPet()
    local first = t and t[1]
    local isPet = (pet and first and first.kind == "N"
        and (first.name == pet.name or first.name == ADB.NPC.DisplayName(pet))) and true or false
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local base = tonumber(isPet and a[3] or a[2]) or 0
    local v = max(1, floor(base * d.agilityMult + 0.5)) * ctx.mult
    Apply(ctx, first and "target" or "self", 2, v)
end

COMMANDS.buff = function(ctx, a)
    local id = tonumber(a[3])
    if not id then return end
    for _, e in ipairs(Entries(a[2] or "target", ctx)) do
        ADB.Buffs.Request(id, Talents.SpecBonus(ctx.n), Talents.Multiplier(ctx.n), ADB.Buffs.KeyFromEntry(e))
    end
end

COMMANDS.say = function(ctx, a) ctx.msgs[#ctx.msgs + 1] = a[2] or "" end

local function Run(rules, ctx)
    local hit = not (ctx.roll and ctx.roll.failed)
    for _, l in ipairs(rules) do
        local t = l.trigger
        if (t == "use" or (t == "hit" and hit) or (t == "miss" and not hit))
            and (not l.cond or CheckCondition(l.cond, ctx)) then
            for _, c in ipairs(l.cmds) do
                local f = COMMANDS[c[1]]
                if f then f(ctx, c) else ADB.Print("Effet inconnu : " .. c[1]) end
            end
        end
    end
    for _, m in ipairs(ctx.msgs) do ADB.Net.Announce(m) end
    ADB.ActionBar.Refresh()
end

------------------------------------------------------------------------------
-- Hooks into the base engine
------------------------------------------------------------------------------
local rollCtx -- context of the Execute currently running (to capture its roll)

ADB.Wrap(ADB.Combat, "Roll", function(orig, ...)
    local r, label, color, mult, failed, critFail = orig(...)
    if rollCtx then rollCtx.roll = { mult = mult, failed = failed } end
    return r, label, color, mult, failed, critFail
end)

ADB.Wrap(Talents, "Execute", function(orig, n, data, offTurn)
    data = data or {}
    local deficit = 0
    if n.mana > 0 and #Effects.Passives("manatopv") > 0 then deficit = max(0, n.mana - ADB.db.mp) end
    local ctx = {
        n = n,
        data = data,
        msgs = {},
        mult = 1,
        who = ADB.Stats.DisplayName(ADB.playerName),
        base = BaseValue(n.desc)
    }
    rollCtx = ctx
    local ok = orig(n, data, offTurn)
    rollCtx = nil
    if not ok then return false end
    local _, _, damageMult = ADB.Buffs.GetBonus("P:" .. ADB.playerName)
    ctx.damageMult = damageMult
    ctx.mult = ctx.roll and ctx.roll.mult or 1
    if deficit > 0 then
        ADB.db.hp = max(0, ADB.db.hp - deficit)
        ADB.Net.Announce(format("%s manque de mana : %d PV dépensés à la place.", ctx.who, deficit))
        ADB.Sync.AfterLocalChange()
    end
    local rules = GetScript(n)
    if rules then
        Run(rules, ctx)
        ADB.Sync.AfterLocalChange()
    end
    return true
end)

-- manatopv: missing mana does not block, it is converted into HP.
ADB.Wrap(Talents, "GetState", function(orig, n)
    if n.mana > 0 and #Effects.Passives("manatopv") > 0 then
        local d = ADB.Stats.GetBlock(ADB.playerName)
        if d and d.mp < n.mana then
            local need = (n.mana - d.mp) + max(0, n.hpCost)
            if d.hp <= need then
                return false, format("PV insuffisants pour compenser le mana (%d requis).", need)
            end
            return orig(setmetatable({ mana = 0 }, { __index = n }))
        end
    end
    return orig(n)
end)

-- Passive efficiency bonus (selector "Name" or #tag).
ADB.Wrap(Talents, "SpecBonus", function(orig, n)
    local b = orig(n)
    for _, c in ipairs(Effects.Passives("bonus")) do
        if c[2] and Selector(c[2], n) then b = b + (tonumber(c[3]) or 0) end
    end
    return b
end)

-- luna: heals/shields doubled on an ally under the HP threshold.
function Effects.LunaDoubles(e, effect)
    if effect ~= 2 and effect ~= 3 then return false end
    local p = Effects.Passives("luna")[1]
    if not p then return false end
    local threshold = tonumber(p[2]) or 50
    local hp, maxHp
    if e.kind == "P" then
        local d = ADB.Stats.GetBlock(e.id)
        hp, maxHp = d and d.hp, d and d.maxHp
    else
        local pn = ADB.NPC.FindByName(e.name)
        if not (pn and pn.ally) then return false end
        hp, maxHp = pn.hp, pn.maxHp
    end
    return (hp and maxHp and hp * 100 < maxHp * threshold) and true or false
end

ADB.Wrap(ADB.Measure, "SendEffects", function(orig, list, effect, value)
    if effect ~= 2 and effect ~= 3 then return orig(list, effect, value) end
    for _, e in ipairs(list) do
        orig({ e }, effect, Effects.LunaDoubles(e, effect) and value * 2 or value)
    end
end)

-- Texte d'annonce quand luna a doublé le soin/bouclier (nil sinon). À appeler AVANT SendEffects.
function Effects.LunaText(e, effect, v)
    if not Effects.LunaDoubles(e, effect) then return nil end
    local d = v * 2
    if effect == 2 then
        return format("La lune-mère protège son enfant et renforce l'effet du sort, il rend %d point%s de vie.",
            d, d > 1 and "s" or "")
    end
    return format("La lune-mère protège son enfant et renforce l'effet du sort, il reçoit %d de bouclier.", d)
end

-- Built-in root (id -2, bonus = number of turns).
ADB.Wrap(ADB.Buffs, "Process", function(orig, id, bonus, mult100, key)
    if id == -2 then
        return ADB.Buffs.Apply(key, {
            id = -2,
            left = Clamp(bonus, 1, 3),
            buffType = ADB.Buffs.TYPE.ROOT,
            value = 0,
            icon = "Spell_Nature_Earthbind",
            name = "Immobilisation"
        })
    end
    return orig(id, bonus, mult100, key)
end)

------------------------------------------------------------------------------
-- Tag-driven passives (famhit / healonhounddamage / demonicbolt)
------------------------------------------------------------------------------
local function Heal(x)
    if ADB.IsGM() or x <= 0 then return end
    local d = ADB.Stats.GetBlock(ADB.playerName)
    if d then ADB.Stats.ApplyValue(ADB.playerName, "hp", d.hp + x) end
end

local function GainMana(g, source)
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local new = min(d.maxMp, ADB.db.mp + g)
    if new > ADB.db.mp then
        ADB.Net.Announce(format("%s regagne %d PM (%s).", ADB.Stats.DisplayName(ADB.playerName), new - ADB.db.mp, source))
        ADB.db.mp = new
        ADB.Sync.AfterLocalChange()
    end
end

local function PetHitSource()
    local n = LearnedByTag("famhit")
    if n then return n end
    local s = Talents.ActiveSpec()
    return (s and s.specTagY == "famhit") and s or nil
end

-- Called by Pets.UseSkill when the pet's attack hits.
function Effects.OnPetHit(p)
    if ADB.IsGM() then return end
    local src = PetHitSource()
    if src then GainMana(max(1, floor(Talents.Multiplier(src) + 0.5)), "touche de familier") end
    if p.petType == "Traqueur Corrompu" and LearnedByTag("healonhounddamage") then
        local d = ADB.Stats.GetBlock(ADB.playerName)
        Heal(max(1, floor(d.intellectMult + 0.5)))
    end
end

local function IsAllyKey(key)
    local kind, id = key:sub(1, 1), key:sub(3)
    if kind == "P" then return true end
    if kind == "N" then
        for _, p in ipairs(ADB.NPC.List()) do
            if tostring(p.id) == id then return p.ally end
        end
    end
    return false
end

-- End of enemy turn: "hound" DoTs on enemies feed heal/mana.
local prevPhase = "IDLE"
ADB.Combat.OnPhase(function(phase)
    local prev = prevPhase
    prevPhase = phase
    if prev ~= "ENEMY_TURN" or phase == prev or phase == "IDLE" or ADB.IsGM() then return end
    local count = 0
    for key, list in pairs(ADB.Buffs.active) do
        if not IsAllyKey(key) then
            for _, b in ipairs(list) do
                if b.buffType == ADB.Buffs.TYPE.DAMAGE and ADB.Buffs.HasTag(b, "hound") then count = count + 1 end
            end
        end
    end
    if count == 0 then return end
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local g = max(1, floor(d.intellectMult + 0.5))
    if LearnedByTag("healonhounddamage") then Heal(g * count) end
    if PetHitSource() then GainMana(g * count, "Hound") end
end)

-- cobraaspect: skills tagged "cobrashot" get +5 accuracy and grant +2 mana on a hit (success / critical success).
local cobraActive, cobraFailed = false, false

ADB.Wrap(ADB.Combat, "Roll", function(orig, accuracy, bonusAcc, bonusCrit, advantage)
    if cobraActive then bonusAcc = (bonusAcc or 0) + 5 end
    local r, label, color, mult, failed, critFail = orig(accuracy, bonusAcc, bonusCrit, advantage)
    if cobraActive then cobraFailed = failed end
    return r, label, color, mult, failed, critFail
end)

ADB.Wrap(Talents, "Execute", function(orig, n, data, offTurn)
    cobraActive = (LearnedByTag("cobraaspect") and Talents.HasTag(n, "cobrashot")) and true or false
    cobraFailed = false
    local ok = orig(n, data, offTurn)
    local active = cobraActive
    cobraActive = false
    if ok and active and not cobraFailed then GainMana(2, "Aspect du Cobra") end
    return ok
end)

-- demonicbolt: Shadow Bolt is replaced on the bar during combat.
ADB.Wrap(Talents, "ActiveSkills", function(orig)
    local r = orig()
    if ADB.phase == "IDLE" or not LearnedByTag("demonicbolt") then return r end
    local out = {}
    for _, n in ipairs(r) do
        if not Talents.HasTag(n, "shadowbolt") then out[#out + 1] = n end
    end
    return out
end)

------------------------------------------------------------------------------
-- avatarofvengeance: spawn serveur du PNJ, 1 attaque annoncée au début des 3 tours joueurs suivants, puis despawn.
------------------------------------------------------------------------------
local AVATAR_NPC_ID, AVATAR_NAME, AVATAR_TURNS = 5073847, "Avatar de la Vengeance", 3
local avatarLeft = 0

local avatarTarget = CreateFrame("Button", "ADBAvatarTarget", UIParent, "SecureActionButtonTemplate")
avatarTarget:SetAttribute("type", "macro")
avatarTarget:SetAttribute("macrotext", "/tar " .. AVATAR_NAME)

local function AvatarCleanup()
    avatarLeft = 0
    avatarTarget:Click()
    C_Timer.After(0.5, function() SendChatMessage(".npc del", "SAY") end)
end

local function AvatarAttack()
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local who = ADB.Stats.DisplayName(ADB.playerName)
    local r, label, _, mult, failed = ADB.Combat.Roll(70)
    local v = max(1, floor(4 * d.intellectMult + 0.5)) * mult
    local msg = format("L'avatar de la vengeance de %s attaque. Jet de précision : %d (%s). ", who, r, label)
    if failed then
        msg = msg .. "L'attaque a échoué."
    else
        msg = msg .. format("L'attaque a réussi, l'avatar inflige %d dégâts à l'ennemi le plus proche.", v)
            .. (mult > 1 and " (effet doublé)" or "")
    end
    ADB.Net.Announce(msg)
end

COMMANDS.avatar = function()
    if ADB.IsGM() or ADB.altContext or avatarLeft > 0 then return end
    avatarLeft = AVATAR_TURNS
    SendChatMessage(".npc spawn " .. AVATAR_NPC_ID, "SAY")
end

ADB.Combat.OnPhase(function(phase)
    if ADB.IsGM() or avatarLeft <= 0 then return end
    if phase == "IDLE" then return AvatarCleanup() end
    if phase ~= "PLAYER_TURN" then return end
    AvatarAttack()
    avatarLeft = avatarLeft - 1
    if avatarLeft == 0 then AvatarCleanup() end
end)
