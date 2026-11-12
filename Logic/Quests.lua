-- Logic/Quests.lua : GM quests (5 slots, "G1".."G5") and player aspirations ("P:Name"). UI → UI/QuestUI.lua.
-- Wire (frozen): QD;key;i;n;chunk (title\tdesc)  QX;key  QC;key;titleEnc (completed)  QQ (resync request)
-- Persistence: db.quests[1..5] = { title, desc } · db.aspiration = { title, desc } · db.questsMinimized
local ADB = ADB
local Net = ADB.Net
local floor, min = math.floor, math.min
local format = string.format
local Encode, Decode, CleanName = ADB.Encode, ADB.Decode, ADB.CleanName

local Quests = {}
ADB.Quests = Quests

local MAX_QUESTS, MAX_ASPIRATIONS, TITLE_MAX, DESC_MAX = 5, 5, 40, 300
Quests.MAX_QUESTS, Quests.TITLE_MAX, Quests.DESC_MAX = MAX_QUESTS, TITLE_MAX, DESC_MAX
Quests.received = { G = {}, P = {} }   -- memory only: GM quests / other players' aspirations
local chunkBuffers, gmSource = {}, nil

local function CleanDesc(s) return strtrim((tostring(s or ""):gsub("[%c|]", " "))):sub(1, DESC_MAX * 2) end
local function CleanTitle(s) return CleanName(s):sub(1, TITLE_MAX * 2) end

------------------------------------------------------------------------------
-- Access
------------------------------------------------------------------------------
function Quests.CanEdit(key)
    if key:match("^G[1-5]$") then return ADB.IsGM() or not IsInGroup() end
    return key == "P:" .. ADB.playerName and not ADB.IsGM()
end

function Quests.CanComplete() return ADB.IsGM() or not IsInGroup() end

-- GM quest table shown (own when GM/solo, received otherwise).
function Quests.Source()
    if ADB.IsGM() or not IsInGroup() then
        ADB.db.quests = type(ADB.db.quests) == "table" and ADB.db.quests or {}
        return ADB.db.quests
    end
    return Quests.received.G
end

function Quests.Get(key)
    local g = key:match("^G([1-5])$")
    if g then return Quests.Source()[tonumber(g)] end
    local name = key:match("^P:(.+)$")
    if name == ADB.playerName then return ADB.db.aspiration end
    return name and Quests.received.P[name] or nil
end

-- Ordered list for the tracker: { key, entry, owner? }
function Quests.List()
    local res, src = {}, Quests.Source()
    for i = 1, MAX_QUESTS do
        if src[i] then res[#res + 1] = { key = "G" .. i, entry = src[i] } end
    end
    local names = {}
    if not ADB.IsGM() and ADB.db.aspiration then names[1] = ADB.playerName end
    local others = {}
    for n in pairs(Quests.received.P) do
        if n ~= ADB.playerName then others[#others + 1] = n end
    end
    table.sort(others)
    for _, n in ipairs(others) do names[#names + 1] = n end
    for i = 1, min(#names, MAX_ASPIRATIONS) do
        local e = Quests.Get("P:" .. names[i])
        if e then res[#res + 1] = { key = "P:" .. names[i], entry = e, owner = names[i] } end
    end
    return res
end

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------
local function SendEntry(key, e)
    if not IsInGroup() then return end
    if not e then
        Net.Enqueue("QX;" .. key)
        return
    end
    local chunks = ADB.SplitUtf8(e.title .. "\t" .. e.desc, 60)
    for i, s in ipairs(chunks) do Net.Enqueue(format("QD;%s;%d;%d;%s", key, i, #chunks, Encode(s))) end
end

local broadcastPending
function Quests.ScheduleBroadcast()   -- GM: all 5 slots · player: own aspiration
    if broadcastPending then return end
    broadcastPending = true
    C_Timer.After(1.5, function()
        broadcastPending = false
        if not (ADB.db and IsInGroup()) then return end
        if ADB.IsGM() then
            for i = 1, MAX_QUESTS do
                SendEntry("G" .. i, type(ADB.db.quests) == "table" and ADB.db.quests[i] or nil)
            end
        elseif ADB.db.aspiration then
            SendEntry("P:" .. ADB.playerName, ADB.db.aspiration)
        end
    end)
end

------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------
function Quests.AlertText(key, title)
    local owner = key:match("^P:(.+)$")
    if owner then return "Aspiration accomplie : " .. ADB.Stats.DisplayName(owner), title end
    return "Quête terminée", title
end

function Quests.Save(key, title, desc)
    if not Quests.CanEdit(key) then return end
    title = CleanTitle(title)
    if title == "" then
        ADB.Print("Donnez un titre.")
        return
    end
    local e = { title = title, desc = CleanDesc(desc) }
    local g = key:match("^G([1-5])$")
    if g then Quests.Source()[tonumber(g)] = e else ADB.db.aspiration = e end
    SendEntry(key, e)
    ADB.QuestUI.Draw()
    ADB.Print("Enregistré : " .. title)
end

function Quests.Delete(key)
    if not Quests.CanEdit(key) then return end
    local g = key:match("^G([1-5])$")
    if g then Quests.Source()[tonumber(g)] = nil else ADB.db.aspiration = nil end
    SendEntry(key, nil)
    ADB.QuestUI.Draw()
end

-- GM / solo: removes the entry, local flash + "QC" broadcast.
function Quests.Complete(key)
    if not Quests.CanComplete() then return end
    local e = Quests.Get(key)
    if not e then return end
    local g, owner = key:match("^G([1-5])$"), key:match("^P:(.+)$")
    if g then
        Quests.Source()[tonumber(g)] = nil
    elseif owner then
        Quests.received.P[owner] = nil
        if owner == ADB.playerName then ADB.db.aspiration = nil end
    end
    ADB.QuestUI.Alert(Quests.AlertText(key, e.title))
    if IsInGroup() then Net.Send(format("QC;%s;%s", key, Encode(e.title))) end
    ADB.QuestUI.Draw()
    if ADB.qEditor and ADB.qEditor:IsShown() then ADB.QuestUI.OpenEditor(ADB.qEditor.key) end
end

function Quests.ToggleMinimized()
    ADB.db.questsMinimized = not ADB.db.questsMinimized
    ADB.QuestUI.Draw()
end

StaticPopupDialogs["ADB_QUETE_TERMINER"] = {
    text = "Terminer « %s » pour tout le groupe ?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data) if data then Quests.Complete(data) end end,
}

------------------------------------------------------------------------------
-- Reception
------------------------------------------------------------------------------
-- Validates that `sender` may publish `key`. Returns "G", index | "P", owner | nil.
local function ParseKey(key, sender)
    local g = key:match("^G([1-5])$")
    if g then
        if ADB.IsGMName(sender) and not ADB.IsGM() then return "G", tonumber(g) end
        return nil
    end
    local owner = key:match("^P:(.+)$")
    if owner and owner == sender and #owner < 40 and not ADB.IsGMName(sender) then return "P", owner end
end

local function Store(key, sender, e)
    local kind, ref = ParseKey(key, sender)
    if not kind then return false end
    if kind == "G" then
        Quests.received.G[ref] = e
    else
        if e and not Quests.received.P[ref] then
            local n = 0
            for _ in pairs(Quests.received.P) do n = n + 1 end
            if n >= 40 then return false end
        end
        Quests.received.P[ref] = e
    end
    return true
end

local function Receive(sender, message, cmd)
    local p = Net.Split(message)
    if cmd == "QQ" then
        Quests.ScheduleBroadcast()
    elseif cmd == "QD" then
        local key, i, n = p[2] or "", tonumber(p[3]), tonumber(p[4])
        if not (ParseKey(key, sender) and i and n and n >= 1 and n <= 20 and i >= 1 and i <= n) then return end
        i, n = floor(i), floor(n)
        local bk = sender .. key
        local b = chunkBuffers[bk]
        if i == 1 or not b or b.n ~= n then
            b = { n = n, parts = {} }
            chunkBuffers[bk] = b
        end
        b.parts[i] = Decode(p[5] or "")
        for j = 1, n do if not b.parts[j] then return end end
        chunkBuffers[bk] = nil
        local title, desc = table.concat(b.parts, "", 1, n):match("^(.-)\t(.*)$")
        if not title then return end
        title = CleanTitle(title)
        if title == "" then return end
        if Store(key, sender, { title = title, desc = CleanDesc(desc) }) then ADB.QuestUI.Draw() end
    elseif cmd == "QX" then
        if Store(p[2] or "", sender, nil) then ADB.QuestUI.Draw() end
    elseif cmd == "QC" then
        if not ADB.IsGMName(sender) or ADB.IsGM() then return end
        local key, title = p[2] or "", CleanTitle(Decode(p[3] or ""))
        local g, owner = key:match("^G([1-5])$"), key:match("^P:(.+)$")
        if g then
            Quests.received.G[tonumber(g)] = nil
        elseif owner then
            Quests.received.P[owner] = nil
            if owner == ADB.playerName then ADB.db.aspiration = nil end
        else
            return
        end
        ADB.QuestUI.Alert(Quests.AlertText(key, title))
        ADB.QuestUI.Draw()
        if ADB.qEditor and ADB.qEditor:IsShown() then ADB.QuestUI.RefreshEditor() end
    end
end
Net.RegisterMany({ "QD", "QX", "QC", "QQ" }, Receive)

------------------------------------------------------------------------------
-- Group resync
------------------------------------------------------------------------------
local resyncPending
local function Resync()
    if resyncPending then return end
    resyncPending = true
    C_Timer.After(2.5, function()
        resyncPending = false
        if not ADB.db or not ADB.playerName then return end
        if not IsInGroup() then
            wipe(Quests.received.G)
            wipe(Quests.received.P)
            gmSource = nil
        else
            local present = ADB.Group.GetNames()
            for n in pairs(Quests.received.P) do
                if not present[n] then Quests.received.P[n] = nil end
            end
            local gm = ADB.Group.GetGMName()
            if ADB.IsGM() or gmSource ~= gm then
                wipe(Quests.received.G)
                gmSource = gm
            end
            Net.Send("QQ")   -- others answer with their data
            Quests.ScheduleBroadcast()
        end
        ADB.QuestUI.Draw()
    end)
end
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ADB.Events.Register(ev, Resync)
end

ADB.Events.Register("PLAYER_LOGIN", function()
    local q = {}
    if type(ADB.db.quests) == "table" then
        for i = 1, MAX_QUESTS do
            local e = ADB.db.quests[i]
            if type(e) == "table" and type(e.title) == "string" then
                q[i] = { title = CleanTitle(e.title), desc = CleanDesc(e.desc) }
            end
        end
    end
    ADB.db.quests = q
    local a = ADB.db.aspiration
    ADB.db.aspiration = (type(a) == "table" and type(a.title) == "string")
        and { title = CleanTitle(a.title), desc = CleanDesc(a.desc) } or nil
    ADB.QuestUI.Create()
end)

ADB.Slash.Register({ "quete", "quetes", "aspiration" }, function() ADB.QuestUI.OpenEditor() end)
ADB.Slash.Register("suivi", function() Quests.ToggleMinimized() end)