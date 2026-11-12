-- Logic/NPC.lua : GM-owned NPCs (and pets/alts as owned allies): storage, replication, reception.
-- Wire: "N;id;hp;maxHp;mp;maxMp;name;shield;ally;owner;petType;rpName", "ND;id", "NC", "NS", "NE".
local ADB = ADB
local Net = ADB.Net
local floor = math.floor
local format = string.format
local Clamp, CleanName, Encode, Decode = ADB.Clamp, ADB.CleanName, ADB.Encode, ADB.Decode

local NPC = {}
ADB.NPC = NPC

function NPC.FindById(list, id)
    for i, p in ipairs(list) do
        if p.id == id then return p, i end
    end
end

-- GM: own list; player in group: list received from the GM; solo: empty.
function NPC.List()
    if not ADB.db then return {} end
    if ADB.IsGM() then return ADB.db.npcs end
    if IsInGroup() then return ADB.receivedNpcs end
    return {}
end

function NPC.DisplayName(p) return (p.rpName and p.rpName ~= "") and p.rpName or p.name end

function NPC.FindByName(name)
    for _, p in ipairs(NPC.List()) do
        if p.name == name then return p end
    end
end

------------------------------------------------------------------------------
-- Replication (GM → players)
------------------------------------------------------------------------------
function NPC.Send(p)
    Net.Send(format("N;%d;%d;%d;%d;%d;%s;%d;%d;%s;%s;%s", p.id, p.hp, p.maxHp, p.mp, p.maxMp,
        Encode(p.name), p.shield or 0, p.ally and 1 or 0, Encode(p.owner or ""), p.petType or "",
        Encode(p.rpName or "")))
end

local flushScheduled = false
function NPC.Schedule(id)
    ADB.dirtyNpcs[id] = true
    if flushScheduled then return end
    flushScheduled = true
    C_Timer.After(ADB.BROADCAST_DELAY, function()
        flushScheduled = false
        if ADB.IsGM() then
            for npcId in pairs(ADB.dirtyNpcs) do
                local p = NPC.FindById(ADB.db.npcs, npcId)
                if p then NPC.Send(p) end
            end
        end
        wipe(ADB.dirtyNpcs)
    end)
end

local fullScheduled = false
function NPC.ScheduleFull()
    if fullScheduled then return end
    fullScheduled = true
    C_Timer.After(ADB.NPC_SYNC_DELAY, function()
        fullScheduled = false
        NPC.BroadcastAll()
    end)
end

-- Full resync: NS (mark stale) → N… → NE (drop stale). Token cancels superseded runs.
local syncToken = 0
function NPC.BroadcastAll()
    if not ADB.IsGM() then return end
    syncToken = syncToken + 1
    local token = syncToken
    local list = ADB.db.npcs
    if #list == 0 then
        Net.Send("NC")
        return
    end
    Net.Send("NS")
    local ids = {}
    for _, p in ipairs(list) do ids[#ids + 1] = p.id end
    for i, id in ipairs(ids) do
        C_Timer.After(0.15 * i, function()
            if token ~= syncToken or not ADB.IsGM() then return end
            local p = NPC.FindById(ADB.db.npcs, id)
            if p then NPC.Send(p) end
        end)
    end
    C_Timer.After(0.15 * (#ids + 1), function()
        if token == syncToken and ADB.IsGM() then Net.Send("NE") end
    end)
end

------------------------------------------------------------------------------
-- Reception (players)
------------------------------------------------------------------------------
local function Receive(sender, message, cmd)
    if ADB.IsGM() or not ADB.IsGMName(sender) then return end
    if ADB.npcSource ~= sender then
        wipe(ADB.receivedNpcs)
        ADB.npcSource = sender
    end
    local list = ADB.receivedNpcs
    local p = Net.Split(message)

    if cmd == "NC" then
        wipe(list)
    elseif cmd == "NS" then
        for _, n in ipairs(list) do n.stale = true end
        return
    elseif cmd == "NE" then
        for i = #list, 1, -1 do
            if list[i].stale then tremove(list, i) end
        end
    elseif cmd == "ND" then
        local _, idx = NPC.FindById(list, tonumber(p[2]))
        if idx then tremove(list, idx) end
    elseif cmd == "N" then
        local id, hp, maxHp, mp, maxMp = tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5]), tonumber(p[6])
        if not (id and hp and maxHp and mp and maxMp) then return end
        id = floor(id)
        local name = "PNJ"
        if p[7] and #p[7] <= 130 then
            name = CleanName(Decode(p[7]))
            if name == "" then name = "PNJ" end
        end
        maxHp = Clamp(floor(maxHp), 1, ADB.NPC_STAT_MAX)
        maxMp = Clamp(floor(maxMp), 0, ADB.NPC_STAT_MAX)
        local n = NPC.FindById(list, id)
        if not n then
            if #list >= ADB.NPC_MAX then return end
            n = { id = id }
            list[#list + 1] = n
        end
        n.name, n.maxHp, n.maxMp = name, maxHp, maxMp
        n.shield = Clamp(floor(tonumber(p[8]) or 0), 0, ADB.SHIELD_MAX)
        n.ally = (p[9] == "1")
        n.owner = (p[10] and p[10] ~= "") and CleanName(Decode(p[10])) or nil
        n.petType = ADB.PET_TYPES[p[11] or ""] and p[11] or nil
        local rp = (p[12] and p[12] ~= "" and #p[12] <= 130) and CleanName(Decode(p[12])):sub(1, 40) or ""
        n.rpName = rp ~= "" and rp or nil
        n.hp = Clamp(floor(hp), 0, maxHp)
        n.mp = Clamp(floor(mp), 0, maxMp)
        n.stale = nil
    end
    ADB.UnitFrames.LayoutNpcs()
    ADB.UnitFrames.RefreshNpcs()
end
Net.RegisterMany({ "N", "ND", "NC", "NS", "NE" }, Receive)

------------------------------------------------------------------------------
-- GM operations
------------------------------------------------------------------------------
function NPC.Create(name, maxHp, maxMp, ally, rpName)
    if not ADB.IsGM() then
        ADB.Print("Seul le MJ (chef de groupe) peut créer des PNJ.")
        return false
    end
    local list = ADB.db.npcs
    if #list >= ADB.NPC_MAX then
        ADB.Print("Nombre maximum de PNJ atteint (" .. ADB.NPC_MAX .. ").")
        return false
    end
    maxHp = Clamp(floor(maxHp), 1, ADB.NPC_STAT_MAX)
    maxMp = Clamp(floor(maxMp), 0, ADB.NPC_STAT_MAX)
    local id = ADB.db.nextNpcId
    ADB.db.nextNpcId = id + 1
    list[#list + 1] = { id = id, name = name, maxHp = maxHp, maxMp = maxMp, hp = maxHp, mp = maxMp,
        shield = 0, ally = ally and true or false, rpName = (rpName and rpName ~= "") and rpName or nil }
    NPC.Schedule(id)
    ADB.UnitFrames.LayoutNpcs()
    ADB.UnitFrames.RefreshNpcs()
    return true
end

function NPC.Delete(id)
    if not ADB.IsGM() then return end
    local _, idx = NPC.FindById(ADB.db.npcs, id)
    if not idx then return end
    tremove(ADB.db.npcs, idx)
    ADB.dirtyNpcs[id] = nil
    Net.Send(format("ND;%d", id))
    ADB.UnitFrames.LayoutNpcs()
    ADB.UnitFrames.RefreshNpcs()
end

-- kind: "hp" | "mp" | "shield". exact = bypass shield absorption.
function NPC.ApplyValue(id, kind, value, exact)
    if not ADB.IsGM() then return end
    local p = NPC.FindById(ADB.db.npcs, id)
    if not p or not ADB.Stats.WIRE_KIND[kind] then return end
    local hp0, shield0 = p.hp, p.shield or 0
    p.shield = shield0
    value = Clamp(floor(value + 0.5), 0, kind == "shield" and ADB.SHIELD_MAX or p[ADB.Stats.MAX_KEY[kind]])
    if kind == "hp" and not exact then value = ADB.Stats.Absorb(p, value) end
    p[kind] = value
    ADB.Stats.TrackHp("N:" .. id, NPC.DisplayName(p), p.hp - hp0)
    ADB.Stats.TrackHp("NB:" .. id, NPC.DisplayName(p), p.shield - shield0, true)
    NPC.Schedule(id)
    ADB.UnitFrames.RefreshNpcs()
end