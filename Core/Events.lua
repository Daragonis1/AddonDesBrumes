-- Core/Events.lua : ordered multi-handler registry for WoW events.
-- Handlers run in registration order (= TOC load order), replacing the old oLogin wrapper chains.
local ADB = ADB
local Events = {}
ADB.Events = Events

local handlers = {}

function Events.Register(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
end

function Events.Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

local REQUIRED = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "PARTY_LEADER_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "UNIT_MODEL_CHANGED",
    "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM" }
local OPTIONAL = { "UNIT_CONNECTION", "PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE" }

-- XML: <OnLoad>ADB.Events.OnLoad(self)</OnLoad>
function Events.OnLoad(frame)
    for _, e in ipairs(REQUIRED) do frame:RegisterEvent(e) end
    for _, e in ipairs(OPTIONAL) do pcall(frame.RegisterEvent, frame, e) end
end

-- XML: <OnEvent>ADB.Events.OnEvent(self, event, ...)</OnEvent>
function Events.OnEvent(_, event, ...) Events.Fire(event, ...) end