-- Logic/Combat.lua : turn-based combat state machine (GM-driven) and dice rolls.
local ADB = ADB
local Net = ADB.Net
local format = string.format

local Combat = {}
ADB.Combat = Combat

local PHASE_CMD = {}
for cmd, phase in pairs(ADB.PHASE_BY_CMD) do PHASE_CMD[phase] = cmd end

ADB.combatEnemies, ADB.npcPlayed, ADB.cbSelected = {}, {}, nil

-- Post-phase listeners (registered in TOC order). fn(phase)
local listeners = {}
function Combat.OnPhase(fn) listeners[#listeners + 1] = fn end

------------------------------------------------------------------------------
-- Dice
------------------------------------------------------------------------------
-- Returns roll, label, {r,g,b}, multiplier, failed, criticalFailure.
local function SingleRoll(accuracy, bonusAcc, bonusCrit)
    local r = math.random(1, 100)
    if r <= 5 + bonusCrit then
        return r, "Réussite critique", { 0.4, 0.7, 1 }, 2, false, false
    elseif r >= 96 then
        return r, "Échec critique", { 1, 0.2, 0.2 }, 1, true, true
    elseif r <= accuracy + bonusAcc then
        return r, "Réussite", { 0.3, 1, 0.3 }, 1, false, false
    end
    return r, "Échec", { 1, 0.6, 0.1 }, 1, true, false
end

-- advantage: 1 = advantage, -1 = disadvantage, 0/nil = normal.
function Combat.Roll(accuracy, bonusAcc, bonusCrit, advantage)
    bonusAcc, bonusCrit = bonusAcc or 0, bonusCrit or 0
    local a = { SingleRoll(accuracy, bonusAcc, bonusCrit) }
    if not advantage or advantage == 0 then return unpack(a) end
    local b = { SingleRoll(accuracy, bonusAcc, bonusCrit) }
    local useB
    if advantage > 0 then useB = b[1] < a[1] else useB = b[1] > a[1] end
    local k = useB and b or a
    k[2] = format("%s - %s : %d et %d", k[2], advantage > 0 and "Avantage" or "Désavantage", a[1], b[1])
    return unpack(k)
end

------------------------------------------------------------------------------
-- Phase handling
------------------------------------------------------------------------------
function Combat.DissipateShields()
    local db = ADB.db
    if (db.shield or 0) > 0 then
        db.shield = 0
        ADB.Print("Votre bouclier s'est dissipé à la fin du combat.")
        ADB.Sync.AfterLocalChange()
    end
    for _, r in pairs(ADB.roster) do r.shield = 0 end
    for _, p in ipairs(ADB.NPC.List()) do
        if (p.shield or 0) > 0 then
            p.shield = 0
            if ADB.IsGM() then ADB.NPC.Schedule(p.id) end
        end
    end
    ADB.RefreshAll()
end

local function Apply(phase)
    if phase == "IDLE" and ADB.phase == "IDLE" then return end
    ADB.phase = phase
    ADB.cbSelected = nil
    if phase == "ALLY_TURN" or phase == "ENEMY_TURN" then ADB.npcPlayed = {} end
    if phase == "IDLE" then ADB.npcPlayed, ADB.combatEnemies = {}, {} end
    local text = ADB.PHASE_BANNER[phase]
    if phase == "STARTING" then
        ADB.turnCount = 0
    elseif phase == "PLAYER_TURN" then
        ADB.turnCount = (ADB.turnCount or 0) + 1
        text = format("Tour %d - %s", ADB.turnCount, text)
    elseif phase == "IDLE" then
        local n = ADB.turnCount or 0
        if n > 0 then text = format("%s - %d tour%s au total", text, n, n > 1 and "s" or "") end
        ADB.turnCount = 0
    end
    ADB.CombatUI.Banner(text)
    if phase == "PLAYER_TURN" then
        ADB.finishedPlayers = {}
        ADB.turnPassed = false
        ADB.CombatUI.SetEndTurnEnabled(true)
    end
    ADB.Measure.OnPhase(phase)
    ADB.Talents.OnPhase(phase)
    ADB.CombatUI.Refresh()
    if phase == "IDLE" then Combat.DissipateShields() end
end

function Combat.SetPhase(phase)
    Apply(phase)
    for i = 1, #listeners do listeners[i](phase) end
end

local function BroadcastPhase(phase)
    Net.Send(PHASE_CMD[phase])
    Combat.SetPhase(phase)
end

------------------------------------------------------------------------------
-- GM flow
------------------------------------------------------------------------------
function Combat.ActivePlayers()
    local t = {}
    for _, u in ipairs(ADB.Group.ListUnits()) do
        local n = UnitName(u)
        if n and ADB.roster[n] and UnitIsConnected(u) then t[#t + 1] = n end
    end
    return t
end

-- GM : liste des combattants de la phase { key, name, done }
function Combat.Roster(phase)
    local res = {}
    if phase == "PLAYER_TURN" then
        for _, n in ipairs(Combat.ActivePlayers()) do
            res[#res + 1] = {
                key = "P:" .. n,
                name = ADB.Stats.DisplayName(n),
                done = ADB.finishedPlayers[n] and true or
                    false
            }
        end
    elseif phase == "ALLY_TURN" then
        for _, p in ipairs(ADB.db.npcs) do
            if p.ally and not p.owner then
                local k = "N:" .. p.id
                res[#res + 1] = { key = k, name = ADB.NPC.DisplayName(p), done = ADB.npcPlayed[k] and true or false }
            end
        end
    elseif phase == "ENEMY_TURN" then
        for _, e in ipairs(ADB.combatEnemies) do
            res[#res + 1] = { key = e.key, name = e.name, done = ADB.npcPlayed[e.key] and true or false }
        end
    end
    return res
end

-- Passe à la phase suivante quand tout le groupe de la phase a joué (alliés/ennemis : jamais si liste vide).
function Combat.CheckPlayersDone()
    if not ADB.IsGM() then return end
    local ph = ADB.phase
    if ph ~= "PLAYER_TURN" and ph ~= "ALLY_TURN" and ph ~= "ENEMY_TURN" then return end
    local list = Combat.Roster(ph)
    if #list == 0 and ph ~= "PLAYER_TURN" then return end
    for _, r in ipairs(list) do
        if not r.done then return end
    end
    Combat.GmEndTurn()
end

local token = 0
function Combat.Start()
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ (chef de groupe) peut lancer un combat.")
        return
    end
    if ADB.phase ~= "IDLE" then return end
    BroadcastPhase("STARTING")
    token = token + 1
    local t = token
    C_Timer.After(3, function()
        if t == token and ADB.phase == "STARTING" and ADB.IsGM() then Combat.PlayerPhase() end
    end)
end

function Combat.PlayerPhase()
    BroadcastPhase("PLAYER_TURN")
    Combat.CheckPlayersDone()
end

function Combat.AllyPhase()
    for _, p in ipairs(ADB.db.npcs) do
        if p.ally and not p.owner then
            BroadcastPhase("ALLY_TURN")
            return
        end
    end
    Combat.EnemyPhase()
end

function Combat.EnemyPhase() BroadcastPhase("ENEMY_TURN") end

function Combat.GmEndTurn()
    if not ADB.IsGM() then return end
    local ph = ADB.phase
    if ph == "STARTING" then
        Combat.PlayerPhase()
    elseif ph == "PLAYER_TURN" then
        Combat.AllyPhase()
    elseif ph == "ALLY_TURN" then
        Combat.EnemyPhase()
    elseif ph == "ENEMY_TURN" then
        Combat.PlayerPhase()
    end
end

function Combat.End()
    if not ADB.IsGM() or ADB.phase == "IDLE" then return end
    token = token + 1
    BroadcastPhase("IDLE")
end

-- Player side
function Combat.PlayerEndTurn()
    ADB.turnPassed = true
    Net.Send("CD")
    ADB.CombatUI.SetEndTurnEnabled(false)
    ADB.CombatUI.Refresh()
    ADB.ActionBar.Refresh()
end
