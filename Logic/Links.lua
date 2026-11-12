-- Logic/Links.lua : clickable skill links in chat. Chat token "{ADB:ci:id:Name}" (plain text accepted by the
-- server) is converted locally into a hyperlink; skill data is broadcast so other players can show tooltips.
-- Wire (frozen): TL;ci;id;0;nChunks;type;stat;effect;element;mana;limit;flags;hpCost;range;accuracy;aoe;icon;name
--                TL;ci;id;i;n;descChunk
local ADB = ADB
local Net, Talents = ADB.Net, ADB.Talents
local floor, max = math.floor, math.max
local format = string.format
local Encode, Decode = ADB.Encode, ADB.Decode

local Links = {}
ADB.Links = Links
Links.cache = {}     -- ["ci:id"] = node received from another player
local pending, sentAt = {}, {}

local function ToHyperlink(msg)
    return (msg:gsub("{ADB:(%d+):(%d+):([^}]*)}", function(ci, id, name)
        name = name:gsub("[|%c]", "")
        return format("|cff71d5ff|Hadb:%s:%s|h[%s]|h|r", ci, id, name)
    end))
end

------------------------------------------------------------------------------
-- Emission
------------------------------------------------------------------------------
function Links.Broadcast(ci, n)
    if not IsInGroup() then return end
    local nid = n.rawid or n.id
    local key, t = ci .. ":" .. nid, GetTime()
    if (sentAt[key] or -999) + 120 > t then return end
    sentAt[key] = t
    local chunks = ADB.SplitUtf8(n.desc or "", 70)
    local flags = (n.reaction and 1 or 0) + (n.bonusAction and 2 or 0)
    Net.Enqueue(format("TL;%d;%d;0;" .. ("%d;"):rep(12) .. "%s;%s", ci, nid, #chunks,
        n.nodeType, n.stat, n.effect, n.element, n.mana, n.limit, flags,
        n.hpCost, n.range, n.accuracy, n.aoe, n.icon, Encode(n.name)))
    for i, s in ipairs(chunks) do
        Net.Enqueue(format("TL;%d;%d;%d;%d;%s", ci, nid, i, #chunks, Encode(s)))
    end
end

-- Chat token for node `n` (broadcasts its data first).
function Links.Text(n, ci)
    if n.class then ci = Talents.ClassIndex(n.class) end
    ci = ci or Talents.ClassIndex(ADB.db.class)
    if not ci then return n.name end
    Links.Broadcast(ci, n)
    return format("{ADB:%d:%d:%s}", ci, n.rawid or n.id, (n.name:gsub("[{}]", "")))
end

------------------------------------------------------------------------------
-- Reception
------------------------------------------------------------------------------
Net.Register("TL", function(sender, message)
    if not (ADB.roster[sender] or ADB.IsGMName(sender)) then return end
    local p = Net.Split(message)
    local ci, id, idx, total = tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5])
    if not (ci and id and idx and total and ADB.CLASSES[floor(ci)] and id >= 0 and total >= 0 and total <= 40) then return end
    ci, id, idx, total = floor(ci), floor(id), floor(idx), floor(total)
    local key = ci .. ":" .. id
    local pk = sender .. key
    local e = pending[pk]
    if idx == 0 then
        local flags = tonumber(p[12]) or 0
        e = { total = total, parts = {}, t = {
            nodeType = p[6], stat = p[7], effect = p[8], element = p[9], mana = p[10], limit = p[11],
            reaction = (flags % 2 == 1), bonusAction = (floor(flags / 2) % 2 == 1),
            hpCost = p[13], range = p[14], accuracy = p[15], aoe = p[16],
            icon = p[17], name = Decode(p[18] or ""),
        } }
        pending[pk] = e
    elseif e and idx >= 1 and idx <= e.total then
        e.parts[idx] = Decode(p[6] or "")
    else
        return
    end
    for i = 1, e.total do
        if not e.parts[i] then return end
    end
    pending[pk] = nil
    e.t.id = max(1, id)   -- ValidateNode rejects id < 1 (basic attack = id 0)
    e.t.desc = table.concat(e.parts, "", 1, e.total)
    local n = Talents.ValidateNode(e.t)
    if n then
        n.id = id
        Links.cache[key] = n
    end
end)

------------------------------------------------------------------------------
-- Display: chat filters (token → hyperlink) and solo announcements
------------------------------------------------------------------------------
local function Filter(_, _, msg, ...)
    if msg and msg:find("{ADB:", 1, true) then return false, ToHyperlink(msg), ... end
end
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ChatFrame_AddMessageEventFilter(ev, Filter)
end

ADB.Wrap(Net, "Announce", function(orig, text)
    if not IsInGroup() then return ADB.Print(ToHyperlink(text)) end
    return orig(text)
end)

------------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------------
local function Lookup(ci, id)
    local n = Links.cache[ci .. ":" .. id]
    if n then return n end
    local c = ADB.CLASSES[ci]
    if not c then return nil end
    if c.name == ADB.db.class then return Talents.GetNode(id) end
    local tree = Talents.GetTree(c.name)
    return tree and tree.nodes[id]
end

local function ParseLink(link) return (link or ""):match("^adb:(%d+):(%d+)$") end

hooksecurefunc("SetItemRef", function(link, text)
    local ci, id = ParseLink(link)
    if not ci or not ADB.db then return end
    local n = Lookup(tonumber(ci), tonumber(id))
    local T = ItemRefTooltip
    if n then
        ADB.TalentWindow.ShowTooltip(UIParent, n, "tree", T, "ANCHOR_PRESERVE")
        T:AddLine(" ")
        T:AddLine("Compétence JDR", 0.6, 0.6, 0.6)
    else
        T:SetOwner(UIParent, "ANCHOR_PRESERVE")
        T:AddLine((text or ""):match("|h%[(.-)%]|h") or "Compétence", 1, 0.82, 0)
        T:AddLine("Données indisponibles (utilisée avant votre connexion).", 1, 0.3, 0.3, true)
    end
    T:Show()
end)

local function OnHyperlinkEnter(self, link)
    local ci, id = ParseLink(link)
    if not ci or not ADB.db then return end
    local n = Lookup(tonumber(ci), tonumber(id))
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if n then
        ADB.TalentWindow.ShowTooltip(self, n, "tree", GameTooltip, "ANCHOR_CURSOR")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Compétence JDR", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Compétence", 1, 0.82, 0)
        GameTooltip:AddLine("Données indisponibles (utilisée avant votre connexion).", 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

local function OnHyperlinkLeave() GameTooltip:Hide() end

local function HookChatFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf and not cf.adbHooked then
            cf.adbHooked = true
            cf:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
            cf:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
        end
    end
end
HookChatFrames()
hooksecurefunc("FCF_OpenTemporaryWindow", HookChatFrames)   -- whisper/temporary tabs