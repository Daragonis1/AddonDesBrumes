-- Logic/EquipmentSkills.lua : skills granted by worn equipment (tree "Équipements", edited by the GM).
-- Equipment node ids are offset by EQUIPMENT_ID_OFFSET (100000) to avoid clashes with class nodes.
local ADB = ADB
local Talents = ADB.Talents
local OFFSET = 100000
ADB.EQUIPMENT_ID_OFFSET = OFFSET

local proxies = {}

local function Tree() return ADB.db and Talents.GetTree(ADB.EQUIPMENT_CLASS) end

-- Proxy node (shifted id, other fields read live from the GM tree).
function Talents.GetEquipmentNode(id)
    local tree = Tree()
    local n = tree and tree.nodes[id - OFFSET]
    if not n then return nil end
    local p = proxies[id]
    if not p or getmetatable(p).__index ~= n then
        p = setmetatable({ id = id }, { __index = n })
        proxies[id] = p
    end
    return p
end

-- Resolves any node id (class, extra class or equipment). Used by cooldown ticking.
function Talents.NodeFromId(tree, id)
    if id and id >= ADB.TALENT.XOFF then return Talents.GetExtraNodeById(id) end
    if id and id >= OFFSET then return Talents.GetEquipmentNode(id) end
    return tree and id and tree.nodes[id] or nil
end

-- Active skills granted by worn equipment.
function Talents.EquipmentGranted()
    local res, seen = {}, {}
    if not ADB.db or not ADB.db.equipment then return res end
    for _, s in ipairs(ADB.EQUIP_SLOTS) do
        local it = ADB.db.equipment[s.key]
        if it and it.skillIds then
            for _, id in ipairs(it.skillIds) do
                local n = (not seen[id]) and Talents.GetEquipmentNode(OFFSET + id)
                if n and n.nodeType == 1 then
                    seen[id] = true
                    res[#res + 1] = n
                end
            end
        end
    end
    return res
end

ADB.Wrap(Talents, "ActiveSkills", function(orig)
    local r = orig()
    for _, n in ipairs(Talents.EquipmentGranted()) do r[#r + 1] = n end
    return r
end)

ADB.Wrap(Talents, "GetNode", function(orig, id)
    if type(id) == "number" and id >= OFFSET and id < ADB.TALENT.XOFF then return Talents.GetEquipmentNode(id) end
    return orig(id)
end)

-- Players also request the equipment tree from the GM.
hooksecurefunc(ADB.TalentNet, "RequestTrees", function()
    local TN = ADB.TalentNet
    if not ADB.db or not TN.requested or not IsInGroup() or ADB.IsGM() or not Talents.source then return end
    local class = ADB.EQUIPMENT_CLASS
    if TN.requested[class] then return end
    TN.requested[class] = true
    local ci = Talents.ClassIndex(class)
    C_Timer.After(2.5, function()
        if ci and IsInGroup() and not ADB.IsGM() then ADB.Net.Send("TQ;" .. ci) end
    end)
end)

-- Item tooltip: granted skills.
ADB.Wrap(ADB.InventoryWindow, "SlotTooltip", function(orig, button)
    orig(button)
    local it = ADB.Items.GetAt(button.zone, button.key)
    if it and it.skillIds and #it.skillIds > 0 then
        local tree = Tree()
        for _, id in ipairs(it.skillIds) do
            local n = tree and tree.nodes[id]
            GameTooltip:AddLine("Compétence : " .. (n and n.name or ("#" .. id)), 0.5, 0.8, 1)
        end
        GameTooltip:Show()
    end
end)