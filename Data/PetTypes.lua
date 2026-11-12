-- Data/PetTypes.lua : pet archetypes. stat: 3 = agility, 4 = intellect (of the OWNER).
-- boost = spec tag giving +25 %. Keys of PET_TYPES are persisted/wire values.
local ADB = ADB
local format = string.format

local function Attack(name, icon, base, mana, stun)
    return { name = name, icon = icon, base = base, accuracy = 60, mana = mana, stun = stun,
        desc = format("Inflige [%d] dégât%s%s.", base, base > 1 and "s" or "",
            stun and (" et étourdit la cible " .. stun .. " tour") or "") }
end

ADB.ALT_TYPE = "Personnage joueur"
ADB.PET_ORDER = { "Diablotin", "Traqueur Corrompu", "Sanglier", "Machine", ADB.ALT_TYPE }
ADB.PET_TYPES = {
    ["Diablotin"] = { icon = "Spell_Shadow_SummonImp", stat = 4, boost = "boostwarlockpet", hp = 7, mp = 0,
        skills = { Attack("Trait de Feu", "Spell_Fire_FlameBolt", 1, 0) } },
    ["Traqueur Corrompu"] = { icon = "Spell_Shadow_SummonFelHunter", stat = 4, boost = "boostwarlockpet", hp = 14, mp = 0,
        skills = { Attack("Morsure de traqueur", "Ability_Hunter_Pet_Wolf", 3, 0) } },
    ["Sanglier"] = { icon = "Ability_Hunter_Pet_Boar", stat = 3, boost = "boosthunterpet", hp = 18, mp = 10, baseHp = 15,
        skills = { Attack("Attaque de base", "INV_Sword_04", 1, 0),
            Attack("Charge de sanglier", "Ability_Warrior_Charge", 1, 3, 1) } },
    ["Machine"] = { icon = "INV_Misc_Gear_01", stat = 3, boost = "boosthunterpet", hp = 18, mp = 10, baseHp = 15,
        skills = { Attack("Attaque de base", "INV_Sword_04", 1, 0), Attack("Déchiquetage", "INV_Misc_Gear_03", 3, 3) } },
}