-- Logic/Measure.lua : distances, movement budget, area targeting, effect application, off-group enemy damage.
-- Wire: "EF;effect;value;kind;id;name" (player→GM), "DG;guid;total" (GM→players).
local ADB = ADB
local Net = ADB.Net
local floor, max, abs, sqrt = math.floor, math.max, math.abs, math.sqrt
local format = string.format

local Measure = {}
ADB.Measure = Measure

Measure.enemyDamage = {}   -- [guid] = cumulative damage on enemies that have no sheet
local movement = nil       -- { m, x0, y0, info, raid } during the player's turn
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
    if ax and bx and ai == bi then return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
    local da, db = Measure.Distance(a), Measure.Distance(b)
    if da and db then return abs(da - db) end
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

-- All living entries within `radius` m of `center` (unit token).
function Measure.ZoneAround(center, radius)
    local res, seen = {}, {}
    local function Add(u)
        if not UnitExists(u) or UnitIsDeadOrGhost(u) then return end
        local guid = UnitGUID(u)
        if not guid or seen[guid] then return end
        local e = Measure.UnitEntry(u)
        if not e then return end
        if not UnitIsUnit(u, center) then
            local d = Measure.DistanceBetween(center, u)
            if not d or d > radius then return end
        end
        seen[guid] = true
        res[#res + 1] = e
    end
    Add(center)
    Add("target")
    Add("player")
    for _, u in ipairs(ADB.Group.ListUnits()) do Add(u) end
    for i = 1, 40 do Add("nameplate" .. i) end
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
-- Effects: effect 1 = damage, 2 = heal, 3 = shield (applied by GM / solo, requested otherwise)
------------------------------------------------------------------------------
function Measure.ApplyEffect(effect, value, kind, id, name)
    if kind == "P" then
        local d = ADB.Stats.GetBlock(id)
        if not d or (id == ADB.playerName and ADB.IsGM()) then return end
        if effect == 1 then ADB.Stats.ApplyValue(id, "hp", d.hp - value)
        elseif effect == 2 then ADB.Stats.ApplyValue(id, "hp", d.hp + value)
        else ADB.Stats.ApplyValue(id, "shield", d.shield + value) end
    else
        local p = ADB.NPC.FindByName(name)
        if p then
            if not ADB.IsGM() then return end
            if effect == 1 then ADB.NPC.ApplyValue(p.id, "hp", p.hp - value)
            elseif effect == 2 then ADB.NPC.ApplyValue(p.id, "hp", p.hp + value)
            else ADB.NPC.ApplyValue(p.id, "shield", (p.shield or 0) + value) end
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
    if effect and value and effect >= 1 and effect <= 3 and (p[4] == "P" or p[4] == "N") and p[5] then
        Measure.ApplyEffect(floor(effect), ADB.Clamp(floor(value), 1, 999), p[4], p[5],
            ADB.CleanName(ADB.Decode(p[6] or "")))
    end
end)

------------------------------------------------------------------------------
-- Phases & movement budget
------------------------------------------------------------------------------
function Measure.OnPhase(phase)
    if phase == "PLAYER_TURN" then
        movement = { m = 0 }
        movement.x0, movement.y0 = Position("player")
        moveLimit = BASE_MOVE_LIMIT
    elseif phase == "IDLE" then
        movement = nil
        moveLimit = BASE_MOVE_LIMIT
        wipe(Measure.enemyDamage)
        if ADB.db and ADB.playerName then ADB.UnitFrames.RefreshTarget(false) end
    end
end

function Measure.AddMovement(meters)
    if not movement then return false end
    moveLimit = moveLimit + meters
    movement.info, movement.raid = nil, nil
    return true
end

-- 0.2 s ticker: target distance label + movement counter during the player's turn.
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
        ADB.UnitFrames.SetDistanceText(d and format(est and "Distance : ~%d m" or "Distance : %d m", floor(d + 0.5)) or "")
    end

    if movement and ADB.phase == "PLAYER_TURN" and not ADB.IsGM() then
        if not ADB.turnPassed then
            local x, y = Position("player")
            if x then
                if not movement.x0 then movement.x0, movement.y0 = x, y end
                movement.m = sqrt((x - movement.x0) ^ 2 + (y - movement.y0) ^ 2)
            end
            if movement.m >= moveLimit and not movement.info then
                movement.info = true
                local msg = format("Vous avez atteint votre limite de %dm ce tour.", moveLimit)
                ADB.Print(msg)
                UIErrorsFrame:AddMessage(msg, 1, 0.8, 0.2)
            end
            if movement.m >= moveLimit + 1 and not movement.raid then
                movement.raid = true
                ADB.Net.Announce(format("%s a dépassé les %dm de déplacement ce tour.",
                    ADB.Stats.DisplayName(ADB.playerName), moveLimit))
            end
        end
        ADB.CombatUI.SetMovementText(format("%sDéplacement : %.1f / %d m|r",
            movement.m >= moveLimit and "|cffff5050" or "", movement.m, moveLimit))
    end
end)