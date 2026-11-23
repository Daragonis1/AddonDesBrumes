-- Logic/Measure.lua : distances, movement budget, area targeting, effect application, off-group enemy damage.
-- Wire: "EF;effect;value;kind;id;name" (player→GM), "DG;guid;total" (GM→players).
local ADB = ADB
local Net = ADB.Net
local floor, max, abs, sqrt = math.floor, math.max, math.abs, math.sqrt
local format = string.format

local Measure = {}
ADB.Measure = Measure

Measure.enemyDamage = {} -- [guid] = cumulative damage on enemies that have no sheet
local movement = nil     -- { m, x0, y0, info, raid } during the player's turn
local BASE_MOVE_LIMIT = 15
local moveLimit = BASE_MOVE_LIMIT

-- { range, itemID } : range estimation for units without coordinates
local RANGE_ITEMS = {
    harm = { { 5, 37727 }, { 8, 34368 }, { 10, 32321 }, { 15, 33069 }, { 20, 10645 }, { 25, 24268 },
        { 30, 835 }, { 35, 24269 }, { 40, 28767 }, { 45, 23836 }, { 60, 116139 }, { 80, 35278 } },
    help = { { 5, 37727 }, { 8, 34368 }, { 10, 32321 }, { 15, 1251 }, { 20, 21519 }, { 25, 31463 },
        { 30, 34191 }, { 35, 18904 }, { 40, 34471 }, { 45, 32698 }, { 60, 32825 }, { 80, 35278 } },
}

local function Position(unit)
    local y, x, _, instance = UnitPosition(unit)
    if x and y and not (x == 0 and y == 0) then return x, y, instance end
end

local function EstimateRange(unit)
    local list = UnitCanAttack("player", unit) and RANGE_ITEMS.harm or RANGE_ITEMS.help
    local seen
    for _, e in ipairs(list) do
        local r = IsItemInRange(e[2], unit)
        if r ~= nil then
            seen = true
            if r == true or r == 1 then return e[1] end
        end
    end
    return seen and 100 or nil
end

Measure.known = {} -- [guid] = { name, range, t } : PNJ déjà vus (portée estimée depuis le joueur)
local KNOWN_TTL = 30

-- unitIDs résolvables (le seul moyen d'obtenir un token depuis un GUID sans nameplate).
function Measure.Tokens()
    local t = { "target", "focus", "mouseover", "player", "pet", "pettarget" }
    for i = 1, 5 do t[#t + 1] = "boss" .. i end
    for _, u in ipairs(ADB.Group.ListUnits()) do
        t[#t + 1] = u
        t[#t + 1] = u .. "target"
        t[#t + 1] = u .. "pettarget"
    end
    return t
end

function Measure.FindUnit(match)
    for _, u in ipairs(Measure.Tokens()) do
        if match(u) then return u end
    end
end

local function Snapshot(u)
    if not UnitExists(u) or UnitIsPlayer(u) or UnitPlayerControlled(u) then return end
    local guid = UnitGUID(u)
    if not guid then return end
    if UnitIsDeadOrGhost(u) then
        Measure.known[guid] = nil
        return
    end
    local r = EstimateRange(u)
    if r then Measure.known[guid] = { name = UnitName(u), range = r, t = GetTime() } end
end

function Measure.SnapshotNpcs()
    for _, u in ipairs(Measure.Tokens()) do Snapshot(u) end
end

local tracker = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET" }) do
    tracker:RegisterEvent(e)
end
tracker:SetScript("OnEvent", function(_, event, unit)
    if ADB.phase == "IDLE" then return end
    if event == "UNIT_TARGET" then
        if unit then Snapshot(unit .. "target") end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Snapshot("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Snapshot("mouseover")
    else
        Snapshot("target")
    end
end)
C_Timer.NewTicker(1, function()
    if ADB.phase ~= "IDLE" then Measure.SnapshotNpcs() end
end)

-- Player → unit distance. Returns distance, isEstimate.
function Measure.Distance(unit)
    if not UnitExists(unit) then return nil end
    if UnitIsUnit(unit, "player") then return 0 end
    local ax, ay, ai = Position("player")
    local bx, by, bi = Position(unit)
    if ax and bx and ai == bi then return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
    return EstimateRange(unit), true
end

function Measure.DistanceBetween(a, b)
    local ax, ay, ai = Position(a)
    local bx, by, bi = Position(b)
    if ax and bx then
        if ai == bi then return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
        return nil
    end
    if UnitIsUnit(a, "player") then return Measure.Distance(b) end
    if UnitIsUnit(b, "player") then return Measure.Distance(a) end
    local da, db = Measure.Distance(a), Measure.Distance(b)
    if not (da and db) then return nil end
    if ax or bx then return max(da, db) end -- one exact position only: no bearing, conservative estimate
    return abs(da - db)                     -- both without coordinates (enemies): lower bound
end

-- Unit → entry { kind = "P"|"N", id, name } or nil (GM, unknown players are excluded).
function Measure.UnitEntry(unit)
    if not UnitExists(unit) then return nil end
    local name = UnitName(unit)
    if UnitIsPlayer(unit) then
        if IsInGroup() and UnitIsGroupLeader(unit) then return nil end
        if name == ADB.playerName or ADB.roster[name] then
            return { kind = "P", id = name, name = ADB.Stats.DisplayName(name) }
        end
        return nil
    end
    return { kind = "N", id = UnitGUID(unit), name = name }
end

-- All living entries within `radius` m of `center` (unit token): exact for players, range bands for NPCs.
function Measure.ZoneAround(center, radius)
    Measure.SnapshotNpcs()
    local res, seen = {}, {}
    local function Add(e, guid)
        seen[guid] = true
        res[#res + 1] = e
    end
    for _, u in ipairs(Measure.Tokens()) do
        local guid = UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitGUID(u)
        if guid and not seen[guid] then
            local e = Measure.UnitEntry(u)
            if e then
                local d = UnitIsUnit(u, center) and 0 or Measure.DistanceBetween(center, u)
                if d and d <= radius then Add(e, guid) end
            end
        end
    end
    local dc = Measure.Distance(center)
    if dc then
        local now = GetTime()
        for guid, k in pairs(Measure.known) do
            if not seen[guid] and now - k.t <= KNOWN_TTL and abs(dc - k.range) <= radius then
                Add({ kind = "N", id = guid, name = k.name }, guid)
            end
        end
    end
    return res
end

function Measure.ZoneTargets(radius) return Measure.ZoneAround("target", radius) end

------------------------------------------------------------------------------
-- Off-group enemy damage (tracked by the GM, mirrored to players)
------------------------------------------------------------------------------
function Measure.AddDamage(guid, delta)
    if not guid or delta == 0 or ADB.phase == "IDLE" then return end
    if IsInGroup() and not ADB.IsGM() then return end
    local total = max(0, (Measure.enemyDamage[guid] or 0) + delta)
    Measure.enemyDamage[guid] = total > 0 and total or nil
    if ADB.IsGM() then Net.Send(format("DG;%s;%d", guid, total)) end
    ADB.UnitFrames.RefreshTarget(false)
end

Net.Register("DG", function(sender, message)
    if not ADB.IsGMName(sender) then return end
    local p = Net.Split(message)
    local v = max(0, floor(tonumber(p[3]) or 0))
    Measure.enemyDamage[p[2]] = v > 0 and v or nil
    ADB.UnitFrames.RefreshTarget(false)
end)

------------------------------------------------------------------------------
-- Effects: effect 1 = damage, 2 = heal, 3 = shield, 4 = mana (applied by GM / solo, requested otherwise)
------------------------------------------------------------------------------
function Measure.ApplyEffect(effect, value, kind, id, name)
    if kind == "P" then
        local d = ADB.Stats.GetBlock(id)
        if not d or (id == ADB.playerName and ADB.IsGM()) then return end
        if effect == 1 then
            ADB.Stats.ApplyValue(id, "hp", d.hp - value)
        elseif effect == 2 then
            ADB.Stats.ApplyValue(id, "hp", d.hp + value)
        elseif effect == 3 then
            ADB.Stats.ApplyValue(id, "shield", d.shield + value)
        else
            ADB.Stats.ApplyValue(id, "mp", d.mp + value)
        end
    else
        local p = ADB.NPC.FindByName(name)
        if p then
            if not ADB.IsGM() then return end
            if effect == 1 then
                ADB.NPC.ApplyValue(p.id, "hp", p.hp - value)
            elseif effect == 2 then
                ADB.NPC.ApplyValue(p.id, "hp", p.hp + value)
            elseif effect == 3 then
                ADB.NPC.ApplyValue(p.id, "shield", (p.shield or 0) + value)
            else
                ADB.NPC.ApplyValue(p.id, "mp", p.mp + value)
            end
        else
            Measure.AddDamage(id, effect == 1 and value or (effect == 2 and -value or 0))
        end
    end
end

function Measure.SendEffects(entries, effect, value)
    local direct = ADB.IsGM() or not IsInGroup()
    for _, e in ipairs(entries) do
        if direct then
            Measure.ApplyEffect(effect, value, e.kind, e.id, e.name)
        else
            Net.Enqueue(format("EF;%d;%d;%s;%s;%s", effect, value, e.kind, e.id, ADB.Encode(e.name)))
        end
    end
end

Net.Register("EF", function(sender, message)
    if not (ADB.IsGM() and ADB.roster[sender]) then return end
    local p = Net.Split(message)
    local effect, value = tonumber(p[2]), tonumber(p[3])
    if effect and value and effect >= 1 and effect <= 4 and (p[4] == "P" or p[4] == "N") and p[5] then
        Measure.ApplyEffect(floor(effect), ADB.Clamp(floor(value), 1, 999), p[4], p[5],
            ADB.CleanName(ADB.Decode(p[6] or "")))
    end
end)

------------------------------------------------------------------------------
-- Phases & movement counter
------------------------------------------------------------------------------
Measure.reported = {} -- GM: [player] = metres travelled this turn
Measure.moveAnnounced = false

function Measure.OnPhase(phase)
    if phase == "STARTING" or phase == "PLAYER_TURN" then Measure.SnapshotNpcs() end
    if phase == "PLAYER_TURN" then
        movement = { m = 0 }
        movement.x0, movement.y0 = Position("player")
        moveLimit = BASE_MOVE_LIMIT
        wipe(Measure.reported)
        Measure.moveAnnounced = false
    elseif phase == "IDLE" then
        movement = nil
        moveLimit = BASE_MOVE_LIMIT
        wipe(Measure.enemyDamage)
        wipe(Measure.reported)
        wipe(Measure.known)
        Measure.moveAnnounced = false
        if ADB.db and ADB.playerName then ADB.UnitFrames.RefreshTarget(false) end
    end
end

function Measure.AddMovement(meters)
    if not movement then return false end
    moveLimit = moveLimit + meters
    return true
end

-- Distance compared to the thresholds (bonus movement shifts them).
local function Effective() return max(0, movement.m - (moveLimit - BASE_MOVE_LIMIT)) end

-- Wire: "MV;metres" (player→GM), "MA;textEnc" (GM→players)
function Measure.SendDistance()
    if ADB.IsGM() or not movement then return end
    Net.Send(format("MV;%.1f", Effective()))
end

Net.Register("MV", function(sender, message)
    if not (ADB.IsGM() and ADB.roster[sender]) then return end
    local m = tonumber(Net.Split(message)[2])
    if m then Measure.reported[sender] = ADB.Clamp(m, 0, 99999) end
end)

-- GM: true if someone sprinted / went over the limit (announces once, turn must then be forced by the GM).
function Measure.CheckViolations()
    local sprint, illegal = {}, {}
    for n, m in pairs(Measure.reported) do
        local name = ADB.Stats.DisplayName(n)
        if m > BASE_MOVE_LIMIT * 2 then
            illegal[#illegal + 1] = name
        elseif m > BASE_MOVE_LIMIT then
            sprint[#sprint + 1] = name
        end
    end
    if #sprint + #illegal == 0 then return false end
    if not Measure.moveAnnounced then
        Measure.moveAnnounced = true
        table.sort(sprint)
        table.sort(illegal)
        local parts = {}
        if #sprint > 0 then parts[#parts + 1] = "SPRINT: " .. table.concat(sprint, ", ") end
        if #illegal > 0 then parts[#parts + 1] = "PLUS QUE 30m: " .. table.concat(illegal, ", ") end
        local text = ADB.SplitUtf8("Déplacement - " .. table.concat(parts, " - "), 200)[1]
        Net.Send("MA;" .. ADB.Encode(text))
        ADB.CombatUI.Alert(text, 1, 0.2, 0.2)
    end
    return true
end

Net.Register("MA", function(sender, message)
    if not ADB.IsGMName(sender) or ADB.IsGM() then return end
    local text = ADB.CleanName(ADB.Decode(Net.Split(message)[2] or "")):sub(1, 200)
    if text ~= "" then ADB.CombatUI.Alert(text, 1, 0.2, 0.2) end
end)

-- 0.2 s ticker: target distance label + movement counter (kept visible until the end of combat).
local ticker, acc = CreateFrame("Frame"), 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    if not ADB.db or not ADB.playerName then return end

    local tf = ADBTargetFrame
    if tf and tf:IsShown() then
        local d, est
        if UnitExists("target") then d, est = Measure.Distance("target") end
        ADB.UnitFrames.SetDistanceText(d and format(est and "Distance : ~%d m" or "Distance : %d m", floor(d + 0.5)) or
            "")
    end

    if movement and ADB.phase ~= "IDLE" and not ADB.IsGM() then
        local x, y = Position("player")
        if x then
            if not movement.x0 then movement.x0, movement.y0 = x, y end
            movement.m = sqrt((x - movement.x0) ^ 2 + (y - movement.y0) ^ 2)
        end
        local m = Effective()
        local status, r, g, b = "Déplacement normal", 0.4, 1, 0.4
        if m > BASE_MOVE_LIMIT * 2 then
            status, r, g, b = "Illégal", 1, 0.3, 0.3
        elseif m > BASE_MOVE_LIMIT then
            status, r, g, b = "Sprint", 1, 0.8, 0.2
        end
        ADB.CombatUI.SetMovementText(format("Distance du point de départ : %.1f m", movement.m), status, r, g, b)
    end
end)
