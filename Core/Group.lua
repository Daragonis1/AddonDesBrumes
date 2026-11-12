-- Core/Group.lua : party/raid helpers and GM role.
local ADB = ADB
local Group = {}
ADB.Group = Group

function Group.ListUnits()
    local units = {}
    if not IsInGroup() then return units end
    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        for i = 1, n - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Returns the GM name if the GM is present in the group (or is the solo player), else nil.
function Group.GetGMName()
    if not IsInGroup() then
        return UnitName("player") == ADB.GM_NAME and ADB.GM_NAME or nil
    end
    local units = { "player" }
    for _, u in ipairs(Group.ListUnits()) do units[#units + 1] = u end
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitName(u) == ADB.GM_NAME then return ADB.GM_NAME end
    end
    return nil
end

function Group.IsGM()
    local gm = Group.GetGMName()
    return gm ~= nil and gm == UnitName("player")
end

function Group.IsGMName(name)
    local gm = Group.GetGMName()
    return gm ~= nil and gm == name
end

ADB.IsGM, ADB.IsGMName = Group.IsGM, Group.IsGMName

function Group.GetNames()
    local t = { [ADB.playerName] = true }
    for _, u in ipairs(Group.ListUnits()) do
        local n = UnitName(u)
        if n then t[n] = true end
    end
    return t
end

function Group.IsMemberDisplayable(unit, name)
    return (name and name ~= UNKNOWNOBJECT and unit and UnitExists(unit)
        and UnitIsConnected(unit) and ADB.roster[name] ~= nil) and true or false
end

function Group.ListDisplayedMembers()
    local res = {}
    for _, u in ipairs(Group.ListUnits()) do
        if UnitExists(u) and not UnitIsUnit(u, "player") and not Group.IsGMName(UnitName(u)) then
            local name = UnitName(u)
            if Group.IsMemberDisplayable(u, name) then res[#res + 1] = { unit = u, name = name } end
        end
    end
    return res
end

function Group.CanEdit(name)
    if not name then return false end
    if Group.IsGM() then return name == ADB.playerName or ADB.roster[name] ~= nil end
    return not IsInGroup() and name == ADB.playerName
end

-- Targeted player (self or addon-equipped group member), else nil.
function Group.GetTargetPlayer()
    if not UnitExists("target") or not UnitIsPlayer("target") then return nil end
    local n = UnitName("target")
    if n == ADB.playerName or ADB.roster[n] then return n end
    return nil
end