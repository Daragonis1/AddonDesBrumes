-- Core/Network.lua : addon-message transport, throttled queue, command router.
-- Wire format is frozen: "CMD;field;field;…" on ADB.PREFIX.
local ADB = ADB
local Net = {}
ADB.Net = Net

local handlers = {}   -- [cmd] = fn(sender, message, cmd)

function Net.Register(cmd, fn) handlers[cmd] = fn end

function Net.RegisterMany(cmds, fn)
    for _, c in ipairs(cmds) do handlers[c] = fn end
end

function Net.Split(message) return { strsplit(";", message) } end

function Net.GetChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    return "PARTY"
end

function Net.Send(msg)
    if not IsInGroup() then return end
    C_ChatInfo.SendAddonMessage(ADB.PREFIX, msg, Net.GetChannel())
end

-- Public chat announcement (solo: printed locally).
function Net.Announce(text)
    if not IsInGroup() then
        ADB.Print(text)
        return
    end
    SendChatMessage(text, Net.GetChannel())
end

-- Throttled send queue (1 message / 0.12 s) to avoid addon-message flooding.
local queue, ticker = {}, nil
function Net.Enqueue(msg)
    queue[#queue + 1] = msg
    if ticker then return end
    ticker = C_Timer.NewTicker(0.12, function()
        local m = tremove(queue, 1)
        if m then Net.Send(m) end
        if #queue == 0 and ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

function Net.OnAddonMessage(prefix, message, _, sender)
    if prefix ~= ADB.PREFIX then return end
    local name = Ambiguate(sender, "short")
    if name == ADB.playerName then return end
    local cmd = strsplit(";", message)
    local fn = handlers[cmd]
    if fn then fn(name, message, cmd) end
end

ADB.Events.Register("CHAT_MSG_ADDON", Net.OnAddonMessage)