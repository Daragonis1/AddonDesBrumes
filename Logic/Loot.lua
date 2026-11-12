-- Logic/Loot.lua : loot sessions (GM) with public 1-100 rolls. Rolls are read by the GM from CHAT_MSG_SYSTEM
-- ("X rolls N (1-100)"), so they cannot be forged.
-- Wire (frozen): LS;id;rarity;nameEnc (GM→players)  LR;id;1|0 (player→GM)  LW;id;winnerEnc;roll;nameEnc;rarity
local ADB = ADB
local Net = ADB.Net
local floor = math.floor
local format = string.format
local Encode, Decode, CleanName = ADB.Encode, ADB.Decode, ADB.CleanName

local Loot = {}
ADB.Loot = Loot
ADB.loot = nil   -- active session { id, rarity, name, attendees, replies, rolls }

local function Finished(L)
    for n in pairs(L.attendees) do
        if L.replies[n] ~= false and not L.rolls[n] then return false end
    end
    return true
end

local function Resolve()
    local L = ADB.loot
    if not L then return end
    ADB.loot = nil
    local best, tops = 0, {}
    for n, r in pairs(L.rolls) do
        if r > best then best, tops = r, { n } elseif r == best then tops[#tops + 1] = n end
    end
    table.sort(tops)
    local label = format("%s (%s)", L.name, ADB.RARITIES[L.rarity].name)
    if #tops == 0 then
        Net.Announce(format("Butin %s : personne n'a lancé les dés.", label))
        Net.Send(format("LW;%d;;0;%s;%d", L.id, Encode(L.name), L.rarity))
        return
    end
    local winner = tops[math.random(#tops)]   -- tie: random among the best
    if #tops > 1 then
        local t = {}
        for _, n in ipairs(tops) do t[#t + 1] = ADB.Stats.DisplayName(n) end
        Net.Announce(format("Égalité à %d entre %s : tirage au sort.", best, table.concat(t, ", ")))
    end
    Net.Announce(format("%s remporte %s avec un jet de %d !", ADB.Stats.DisplayName(winner), label, best))
    Net.Send(format("LW;%d;%s;%d;%s;%d", L.id, Encode(winner), best, Encode(L.name), L.rarity))
    ADB.CombatUI.Banner(ADB.Stats.DisplayName(winner) .. " remporte " .. L.name)
end

function Loot.Start(rarity, name)
    if not ADB.IsGM() then
        ADB.Print("Réservé au MJ.")
        return
    end
    if ADB.loot then
        ADB.Print("Une session de butin est déjà en cours.")
        return
    end
    rarity = ADB.Clamp(floor(tonumber(rarity) or 3), 1, #ADB.RARITIES)
    name = CleanName(name or ""):sub(1, 30)
    if name == "" then name = "Objet" end
    local attendees, n = {}, 0
    for _, p in ipairs(ADB.Combat.ActivePlayers()) do
        attendees[p] = true
        n = n + 1
    end
    if n == 0 then
        ADB.Print("Aucun joueur avec l'addon dans le groupe.")
        return
    end
    Loot.lastId = (Loot.lastId or floor(GetTime())) + 1
    local id = Loot.lastId
    ADB.loot = { id = id, rarity = rarity, name = name, attendees = attendees, replies = {}, rolls = {} }
    Net.Send(format("LS;%d;%d;%s", id, rarity, Encode(name)))
    Net.Announce(format("[MJ] Butin : %s (%s) - jet de 1 à 100.", name, ADB.RARITIES[rarity].name))
    C_Timer.After(45, function()   -- max delay
        if ADB.loot and ADB.loot.id == id then Resolve() end
    end)
end
ADB.Slash.Register("butin", function(rest) Loot.Start(3, rest) end)   -- default rarity: Rare

-- Pattern built from the localized RANDOM_ROLL_RESULT global string.
local ROLL_PATTERN = (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
    :gsub("([%(%)%.%-%+%[%]%^%$%?%*])", "%%%1")
    :gsub("%%%d%$s", "(.+)"):gsub("%%%d%$d", "(%%d+)")
    :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")

ADB.Events.Register("CHAT_MSG_SYSTEM", function(msg)
    local L = ADB.loot
    if not (L and ADB.IsGM()) then return end
    local who, r, lo, hi = (msg or ""):match(ROLL_PATTERN)
    if not who or tonumber(lo) ~= 1 or tonumber(hi) ~= 100 then return end
    who = Ambiguate(who, "short")
    if L.attendees[who] and L.replies[who] ~= false and not L.rolls[who] then
        L.rolls[who] = tonumber(r)
        if Finished(L) then Resolve() end
    end
end)

------------------------------------------------------------------------------
-- Player side
------------------------------------------------------------------------------
StaticPopupDialogs["ADB_LOOT"] = {
    text = "Butin du MJ : %s\nLancer les dés (1-100) ?",
    button1 = YES, button2 = NO, timeout = 40, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data)
        if not data then return end
        Net.Send(format("LR;%d;1", data.id))
        RandomRoll(1, 100)   -- public /roll 100, read by the GM
    end,
    OnCancel = function(_, data, reason)
        if data and (reason == "clicked" or reason == "timeout") then Net.Send(format("LR;%d;0", data.id)) end
    end,
}

Net.Register("LS", function(sender, message)
    if not ADB.IsGMName(sender) or ADB.IsGM() then return end
    local p = Net.Split(message)
    local id, rarity = tonumber(p[2]), tonumber(p[3])
    if not (id and rarity and ADB.RARITIES[floor(rarity)]) then return end
    local R = ADB.RARITIES[floor(rarity)]
    local name = CleanName(Decode(p[4] or "")):sub(1, 30)
    StaticPopup_Show("ADB_LOOT", format("|cff%s%s|r (%s)", R.hex, name, R.name), nil, { id = floor(id) })
end)

Net.Register("LR", function(sender, message)
    local L = ADB.loot
    local p = Net.Split(message)
    if not (L and ADB.IsGM()) or tonumber(p[2]) ~= L.id or not L.attendees[sender] then return end
    L.replies[sender] = (p[3] == "1")   -- false = declined
    if Finished(L) then Resolve() end
end)

Net.Register("LW", function(sender, message)
    if not ADB.IsGMName(sender) or ADB.IsGM() then return end
    StaticPopup_Hide("ADB_LOOT")
    local p = Net.Split(message)
    local winner, roll = Decode(p[3] or ""), tonumber(p[4]) or 0
    local item = CleanName(Decode(p[5] or "")):sub(1, 30)
    if winner == "" then
        ADB.Print("Butin " .. item .. " : personne n'a lancé les dés.")
    else
        ADB.Print(format("%s remporte %s (jet : %d).", ADB.Stats.DisplayName(winner), item, roll))
        ADB.CombatUI.Banner(ADB.Stats.DisplayName(winner) .. " remporte " .. item)
    end
end)