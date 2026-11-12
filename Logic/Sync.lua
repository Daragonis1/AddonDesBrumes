-- Logic/Sync.lua : player-state replication and GM→player commands (S, Q, SET, XP, XPALL, REST, GOLD, GOLDM, IE, IC, phases, CD).
local ADB = ADB
local Net = ADB.Net
local format, floor, min = string.format, math.floor, math.min
local Clamp, CleanName, Encode, Decode = ADB.Clamp, ADB.CleanName, ADB.Encode, ADB.Decode

local Sync = {}
ADB.Sync = Sync

function Sync.AfterLocalChange()
    ADB.RefreshAll()
    Sync.ScheduleBroadcast()
end

-- "S;str;agi;int;hp;mp;rpName;level;xp;race;class;copper;shield"
function Sync.SendState()
    local db = ADB.db
    local d = ADB.Stats.GetBlock(ADB.playerName)
    Net.Send(format("S;%d;%d;%d;%d;%d;%s;%d;%d;%s;%s;%d;%d",
        d.strength, d.agility, d.intellect, d.hp, d.mp, Encode(db.rpName or ""),
        db.level, db.xp, Encode(db.race), Encode(db.class), db.copper, d.shield))
end

local broadcastPending, requestPending = false, false
function Sync.ScheduleBroadcast(request)
    if request then requestPending = true end
    if broadcastPending then return end
    broadcastPending = true
    C_Timer.After(ADB.BROADCAST_DELAY, function()
        broadcastPending = false
        if requestPending then
            requestPending = false
            Net.Send("Q")
        end
        Sync.SendState()
    end)
end

------------------------------------------------------------------------------
-- Handlers
------------------------------------------------------------------------------
Net.Register("S", function(sender, message)
    local p = Net.Split(message)
    local str, agi, int, hp, mp = tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5]), tonumber(p[6])
    if not (str and agi and int and hp and mp) then return end
    local isNew = (ADB.roster[sender] == nil)
    local rp = (p[7] and #p[7] <= 130) and CleanName(Decode(p[7])) or ""
    local xp = math.max(0, floor(tonumber(p[9]) or 0))
    local race = p[10] and Decode(p[10]) or ""
    local class = p[11] and Decode(p[11]) or ""
    if not ADB.RACE_BY_NAME[race] then race = "" end
    if not ADB.CLASS_BY_NAME[class] then class = "" end
    ADB.roster[sender] = {
        strength = Clamp(floor(str), 0, ADB.MAX_FINAL_STAT),
        agility = Clamp(floor(agi), 0, ADB.MAX_FINAL_STAT),
        intellect = Clamp(floor(int), 0, ADB.MAX_FINAL_STAT),
        hp = math.max(0, floor(hp)), mp = math.max(0, floor(mp)),
        rpName = rp, xp = xp, level = ADB.Stats.LevelForXP(xp), race = race, class = class,
        copper = Clamp(floor(tonumber(p[12]) or 0), 0, ADB.COPPER_MAX),
        shield = Clamp(floor(tonumber(p[13]) or 0), 0, ADB.SHIELD_MAX),
    }
    if isNew then ADB.UnitFrames.LayoutGroup() end
    ADB.RefreshAll()
end)

Net.Register("Q", function()
    Sync.ScheduleBroadcast()
    if ADB.IsGM() then ADB.NPC.ScheduleFull() end
end)

local WIRE_TO_KIND = { pv = "hp", pm = "mp", sh = "shield", pvx = "hp" }
Net.Register("SET", function(sender, message)
    local p = Net.Split(message)
    local kind, value = WIRE_TO_KIND[p[3] or ""], tonumber(p[4])
    if p[2] == ADB.playerName and kind and value and ADB.IsGMName(sender) then
        ADB.Stats.ApplyValue(ADB.playerName, kind, value, true, p[3] == "pvx")
    end
end)

Net.Register("XP", function(sender, message)
    local p = Net.Split(message)
    local amount = tonumber(p[3])
    if p[2] == ADB.playerName and amount and ADB.IsGMName(sender) then ADB.Stats.ReceiveXP(amount) end
end)

Net.Register("XPALL", function(sender, message)
    local amount = tonumber(Net.Split(message)[2])
    if amount and ADB.IsGMName(sender) then ADB.Stats.ReceiveXP(amount) end
end)

Net.Register("REST", function(sender, message)
    local pct = tonumber(Net.Split(message)[2])
    if pct and ADB.IsGMName(sender) then ADB.Stats.ReceiveRest(pct) end
end)

Net.RegisterMany({ "GOLD", "GOLDM" }, function(sender, message, cmd)
    local p = Net.Split(message)
    local amount = tonumber(p[3])
    if p[2] ~= ADB.playerName or not amount or not ADB.IsGMName(sender) then return end
    amount = Clamp(floor(amount), 1, ADB.COPPER_MAX)
    if cmd == "GOLD" then
        ADB.Items.ChangeCopper(amount)
        ADB.Print("Vous avez reçu " .. ADB.FormatMoney(amount) .. ".")
    else
        amount = min(amount, ADB.db.copper)
        ADB.Items.ChangeCopper(-amount)
        ADB.Print("Le MJ vous a retiré " .. ADB.FormatMoney(amount) .. ".")
    end
end)

-- "IE;target;slot;rarity;icon;s1;s2;s3;name;skillsText;skillIds;tags"
Net.Register("IE", function(sender, message)
    local p = Net.Split(message)
    if p[2] ~= ADB.playerName or not ADB.IsGMName(sender) then return end
    local it = ADB.Items.Validate({
        kind = "equip", slot = p[3], rarity = tonumber(p[4]), icon = p[5],
        stats = { tonumber(p[6]), tonumber(p[7]), tonumber(p[8]) },
        name = Decode(p[9] or ""), skillsText = Decode(p[10] or ""), skillIds = p[11], tags = p[12],
    })
    if it then ADB.Items.Receive(it, 1) end
end)

-- "IC;target;kind;qty"
Net.Register("IC", function(sender, message)
    local p = Net.Split(message)
    local qty = tonumber(p[4])
    if p[2] == ADB.playerName and qty and ADB.CONSUMABLES[p[3] or ""] and ADB.IsGMName(sender) then
        ADB.Items.Receive({ kind = p[3] }, Clamp(floor(qty), 1, 20))
    end
end)

-- Combat phase broadcast (GM → players)
for cmd, phase in pairs(ADB.PHASE_BY_CMD) do
    Net.Register(cmd, function(sender)
        if ADB.IsGMName(sender) and not ADB.IsGM() then ADB.Combat.SetPhase(phase) end
    end)
end

-- Player ended turn (processed by GM)
Net.Register("CD", function(sender)
    if ADB.IsGM() and ADB.phase == "PLAYER_TURN" then
        ADB.finishedPlayers[sender] = true
        ADB.CombatUI.Refresh()
        ADB.Combat.CheckPlayersDone()
    end
end)