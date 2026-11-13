-- Logic/TalentNet.lua : GM → players tree replication and GM approval protocol.
-- Wire (frozen): TN;ci;id;x;y;type;stat;effect;element;mana;limit;reaction;bonus;requires;icon;name
--   TD;ci;id;i;n;chunk  TF;ci;id;hpCost;range;accuracy;aoe;isSpec;tagX;tagY;"";buffId  TG;ci;id;i;n;tags
--   TX;ci;id  TS;ci  TE;ci  TC/TK (color boxes)  TQ;ci (request)  HQ/HR (approval request/response)
local ADB = ADB
local Net, Talents = ADB.Net, ADB.Talents
local floor, max = math.floor, math.max
local format = string.format
local Encode, Decode, CleanName = ADB.Encode, ADB.Decode, ADB.CleanName

local TalentNet = {}
ADB.TalentNet = TalentNet
TalentNet.requested = {}   -- [class] = true once TQ sent to the current GM

local COMMANDS = { "TN", "TD", "TF", "TG", "TX", "TS", "TE", "TQ", "HQ", "HR", "TC", "TK" }

------------------------------------------------------------------------------
-- Serialization
------------------------------------------------------------------------------
local function NodeMessages(ci, n)
    local msgs = { format("TN;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%s;%s;%s",
        ci, n.id, n.x, n.y, n.nodeType, n.stat, n.effect, n.element, n.mana, n.limit,
        n.reaction and 1 or 0, n.bonusAction and 1 or 0, table.concat(n.requires, ","), n.icon, Encode(n.name)) }
    local chunks = ADB.SplitUtf8(n.desc, 70)
    for i, s in ipairs(chunks) do
        msgs[#msgs + 1] = format("TD;%d;%d;%d;%d;%s", ci, n.id, i, #chunks, Encode(s))
    end
    msgs[#msgs + 1] = format("TF;%d;%d;%d;%d;%d;%d;%d;%s;%s;%s;%d", ci, n.id, n.hpCost, n.range,
        n.accuracy, n.aoe, n.isSpec and 1 or 0, n.specTagX, n.specTagY, "", n.buffId or 0)
    local tags = ADB.SplitUtf8(table.concat(n.tags, ","), 120)
    for i, s in ipairs(tags) do msgs[#msgs + 1] = format("TG;%d;%d;%d;%d;%s", ci, n.id, i, #tags, s) end
    return msgs
end

function TalentNet.ColorBoxMessage(ci, b)
    return format("TC;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d", ci, b.id, b.x1, b.y1, b.x2, b.y2, b.r, b.g, b.b, b.a)
end

local function SortedKeys(t)
    local ids = {}
    for id in pairs(t or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- Full class tree: TS (mark stale) → nodes/boxes → TE (drop stale).
function TalentNet.BroadcastClass(ci)
    if not ADB.IsGM() or not ADB.CLASSES[ci] then return end
    local tree = ADB.db.talents.trees[ADB.CLASSES[ci].name]
    Net.Enqueue(format("TS;%d", ci))
    if tree then
        for _, id in ipairs(SortedKeys(tree.nodes)) do
            for _, m in ipairs(NodeMessages(ci, tree.nodes[id])) do Net.Enqueue(m) end
        end
        for _, id in ipairs(SortedKeys(tree.colorBoxes)) do
            Net.Enqueue(TalentNet.ColorBoxMessage(ci, tree.colorBoxes[id]))
        end
    end
    Net.Enqueue(format("TE;%d", ci))
end

------------------------------------------------------------------------------
-- Debounced scheduling
------------------------------------------------------------------------------
local classPlan, nodePlan, boxPlan = {}, {}, {}
local nodeTimer, boxTimer = false, false

function TalentNet.ScheduleClass(ci)
    if classPlan[ci] then return end
    classPlan[ci] = true
    C_Timer.After(1, function()
        classPlan[ci] = nil
        TalentNet.BroadcastClass(ci)
    end)
end

local function Flush(plan, build)
    if ADB.IsGM() then
        for _, p in pairs(plan) do
            local tree = ADB.db.talents.trees[ADB.CLASSES[p[1]].name]
            build(p[1], tree, p[2])
        end
    end
    wipe(plan)
end

function TalentNet.ScheduleNode(ci, id)
    if not ci or not ADB.IsGM() then return end
    nodePlan[ci .. ":" .. id] = { ci, id }
    if nodeTimer then return end
    nodeTimer = true
    C_Timer.After(0.8, function()
        nodeTimer = false
        Flush(nodePlan, function(c, tree, nid)
            local n = tree and tree.nodes[nid]
            if n then for _, m in ipairs(NodeMessages(c, n)) do Net.Enqueue(m) end end
        end)
    end)
end

function TalentNet.ScheduleColorBox(ci, id)
    if not ci or not ADB.IsGM() then return end
    boxPlan[ci .. ":" .. id] = { ci, id }
    if boxTimer then return end
    boxTimer = true
    C_Timer.After(0.8, function()
        boxTimer = false
        Flush(boxPlan, function(c, tree, bid)
            local b = tree and tree.colorBoxes and tree.colorBoxes[bid]
            if b then Net.Enqueue(TalentNet.ColorBoxMessage(c, b)) end
        end)
    end)
end

-- Player: asks the GM for own-class + extra-class trees (once per GM).
function TalentNet.RequestTrees()
    if not ADB.db or not TalentNet.requested then return end
    if not IsInGroup() then
        Talents.source = nil
        if next(TalentNet.requested) then wipe(TalentNet.requested) end
        return
    end
    if ADB.IsGM() then return end
    local gm = ADB.Group.GetGMName()
    if gm ~= Talents.source then
        Talents.source = gm
        wipe(TalentNet.requested)
    end
    if not gm then return end
    local list = { ADB.db.class }
    for _, c in ipairs(Talents.ExtraClasses()) do list[#list + 1] = c end
    for k, class in ipairs(list) do
        if not TalentNet.requested[class] then
            TalentNet.requested[class] = true
            local ci = Talents.ClassIndex(class)
            C_Timer.After(2 + (k - 1) * 0.5, function()
                if ci and IsInGroup() and not ADB.IsGM() then Net.Send("TQ;" .. ci) end
            end)
        end
    end
end

------------------------------------------------------------------------------
-- Reception
------------------------------------------------------------------------------
local function HandleApproval(cmd, sender, p)
    if cmd == "TQ" then
        if ADB.IsGM() then
            local ci = tonumber(p[2])
            if ci and ADB.CLASSES[ci] then TalentNet.ScheduleClass(floor(ci)) end
        end
    elseif cmd == "HQ" then
        if ADB.IsGM() then
            local token = tonumber(p[2])
            if not token then return end
            local label = CleanName(Decode(p[4] or ""))
            label = label .. (p[6] == "F" and " (recharge / mana)" or " (hors-tour)")
            StaticPopup_Show("ADB_TAL_VALIDATION", ADB.Stats.DisplayName(sender), label,
                { player = sender, token = floor(token) })
        end
    elseif cmd == "HR" then
        if not (ADB.IsGMName(sender) and p[2] == ADB.playerName) then return end
        local token = tonumber(p[3])
        local req = token and Talents.pending[token]
        if not req then return end
        Talents.pending[token] = nil
        if p[4] ~= "1" then
            ADB.Print("Le MJ a refusé l'utilisation de la compétence.")
            return
        end
        if req.potion then
            local s = ADB.db.inventory[req.potion]
            if s and s.kind == req.kind then ADB.Items.UsePotion(req.potion) end
        end
        local n = req.id and Talents.GetNode(req.id)
        if n then
            local inTurn = req.force and ADB.phase == "PLAYER_TURN" and not ADB.turnPassed
            if Talents.Execute(n, req, not inTurn) and inTurn and not n.bonusAction then
                ADB.Combat.PlayerEndTurn()
            end
        end
    end
end

function TalentNet.Receive(cmd, sender, message)
    local p = Net.Split(message)
    if cmd == "TQ" or cmd == "HQ" or cmd == "HR" then return HandleApproval(cmd, sender, p) end

    if ADB.IsGM() or not ADB.IsGMName(sender) then return end
    local ci = tonumber(p[2])
    local class = ci and ADB.CLASSES[floor(ci)] and ADB.CLASSES[floor(ci)].name
    if not class or (class ~= ADB.EQUIPMENT_CLASS and not Talents.HasAccess(class)) then return end
    local tree = Talents.GetTree(class, true)
    local nodeId = floor(tonumber(p[3]) or 0)

    if cmd == "TS" then
        for _, n in pairs(tree.nodes) do n.stale = true end
        for _, b in pairs(tree.colorBoxes or {}) do b.stale = true end
    elseif cmd == "TE" then
        for id, n in pairs(tree.nodes) do if n.stale then tree.nodes[id] = nil end end
        for id, b in pairs(tree.colorBoxes or {}) do if b.stale then tree.colorBoxes[id] = nil end end
    elseif cmd == "TC" then
        local b = Talents.ValidateColorBox({ id = p[3], x1 = p[4], y1 = p[5], x2 = p[6], y2 = p[7],
            r = p[8], g = p[9], b = p[10], a = p[11] })
        if b then
            tree.colorBoxes = tree.colorBoxes or {}
            tree.colorBoxes[b.id] = b
            tree.nextBoxId = max(tree.nextBoxId or 1, b.id + 1)
        end
    elseif cmd == "TK" then
        if tree.colorBoxes then tree.colorBoxes[nodeId] = nil end
    elseif cmd == "TX" then
        tree.nodes[nodeId] = nil
    elseif cmd == "TN" then
        local requires = {}
        for s in (p[14] or ""):gmatch("%d+") do requires[#requires + 1] = tonumber(s) end
        local n = Talents.ValidateNode({
            id = p[3], x = p[4], y = p[5], nodeType = p[6], stat = p[7], effect = p[8], element = p[9],
            mana = p[10], limit = p[11], reaction = (p[12] == "1"), bonusAction = (p[13] == "1"),
            requires = requires, icon = p[15], name = Decode(p[16] or ""), desc = "",
        })
        if n then
            tree.nodes[n.id] = n
            tree.nextId = max(tree.nextId, n.id + 1)
        end
        elseif cmd == "TD" then
        local n = tree.nodes[nodeId]
        local idx, total = tonumber(p[4]), tonumber(p[5])
        if n and idx and total and total >= 1 and total <= 40 and idx >= 1 and idx <= total then
            n.descParts = n.descParts or {}
            n.descParts[floor(idx)] = Decode(p[6] or "")
            local complete = true
            for i = 1, total do
                if not n.descParts[i] then
                    complete = false
                    break
                end
            end
            if complete then
                n.desc = Talents.SanitizeDesc(table.concat(n.descParts, "", 1, total))
                n.descParts = nil
            end
        end
    elseif cmd == "TF" then
        local n = tree.nodes[nodeId]
        if n then
            Talents.ApplyExtras(n, { hpCost = p[4], range = p[5], accuracy = p[6], aoe = p[7],
                isSpec = (p[8] == "1"), specTagX = p[9], specTagY = p[10], tags = p[11], buffId = p[12] })
        end
    elseif cmd == "TG" then
        local n = tree.nodes[nodeId]
        local i, total = tonumber(p[4]), tonumber(p[5])
        if n and i and total and total >= 1 and total <= 20 and i >= 1 and i <= total then
            i, total = floor(i), floor(total)
            if i == 1 or not n.tagParts then n.tagParts = {} end
            n.tagParts[i] = p[6] or ""
            for k = 1, total do if not n.tagParts[k] then return end end
            n.tags = Talents.SanitizeTags(table.concat(n.tagParts, "", 1, total))
            n.tagParts = nil
        end
    end
    Talents.Refresh()
end

for _, cmd in ipairs(COMMANDS) do
    Net.Register(cmd, function(sender, message, c) return TalentNet.Receive(c, sender, message) end)
end