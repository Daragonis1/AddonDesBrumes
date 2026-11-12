-- Logic/BasicAttack.lua : the always-available basic attack (node id 0), injected into the skill pipeline.
local ADB = ADB
local BasicAttack = {}
ADB.BasicAttack = BasicAttack

local BASE_DAMAGE = 4
local node = {
    id = 0, x = 0, y = 0, nodeType = 1, effect = 1, element = 1, mana = 0, limit = 5,
    reaction = false, bonusAction = false, icon = "INV_Sword_04", name = "Attaque de base",
    desc = "Inflige [" .. BASE_DAMAGE .. "] dégâts.", requires = {}, tags = {}, hpCost = -1, aoe = -1,
    accuracy = 70, isSpec = false, specTagX = "", specTagY = "", buffId = 0, stat = 2, range = 5,
}

-- Stat follows the class' main attribute; hunters shoot at 30 m.
function BasicAttack.Get()
    local c = ADB.CLASS_BY_NAME[ADB.db.class] or ADB.CLASS_BY_NAME["Guerrier"]
    node.stat = c.strength > 0 and 2 or (c.agility > 0 and 3 or 4)
    node.range = (ADB.db.class == "Chasseur") and 30 or 5
    return node
end

local T = ADB.Talents

ADB.Wrap(T, "ActiveSkills", function(orig)
    local r = orig()
    if ADB.db then table.insert(r, 1, BasicAttack.Get()) end
    return r
end)

ADB.Wrap(T, "GetNode", function(orig, id)
    if id == 0 then return BasicAttack.Get() end
    return orig(id)
end)

ADB.Wrap(T, "GetState", function(orig, n)
    if ADB.Buffs.Has("P:" .. ADB.playerName, 4) then
        return false, "Vous êtes étourdi : aucune action possible."
    end
    return orig(n)
end)