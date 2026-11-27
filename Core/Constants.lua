-- Core/Constants.lua : static game rules and limits.
local ADB                  = ADB

-- Limits & timings
ADB.MAX_FINAL_STAT         = 9999
ADB.MEMBERS_PER_COLUMN     = 5
ADB.BROADCAST_DELAY        = 0.5
ADB.NPC_SYNC_DELAY         = 1.0
ADB.CHAT_DELAY             = 1.5
ADB.NAME_MAX               = 30
ADB.NPC_MAX                = 20
ADB.NPC_STAT_MAX           = 9999
ADB.XP_SEND_MAX            = 100000
ADB.INV_SLOTS              = 16
ADB.COPPER_MAX             = 99999999
ADB.ITEM_NAME_MAX          = 24
ADB.ITEM_SKILLS_TEXT_MAX   = 50
ADB.POTION_RESTORE         = 12
ADB.RATION_BONUS           = 10
ADB.SHIELD_MAX             = 999
ADB.GM_NAME                = "Istriä"
ADB.GIANT_BONUS            = 20   -- Potion de taille de géant : +Force jusqu'au prochain repos
ADB.REST_EXTRA_PCT         = 10   -- choix de repos "Prendre du repos"
ADB.TRAIN_XP               = 2    -- choix de repos "S'entraîner"
ADB.WORK_MIN, ADB.WORK_MAX = 2, 4 -- choix de repos "Travailler" (composants)

-- Combat phases
ADB.PHASE_BY_CMD           = { CS = "STARTING", CP = "PLAYER_TURN", CA = "ALLY_TURN", CE = "ENEMY_TURN", CF = "IDLE" }
ADB.PHASE_BANNER           = {
    STARTING    = "Début du Combat - Tour par Tour",
    PLAYER_TURN = "Tour des Joueurs",
    ALLY_TURN   = "Tour des Alliés",
    ENEMY_TURN  = "Tour des Ennemis",
    IDLE        = "Fin du Combat",
}

-- Experience
ADB.XP_THRESHOLDS          = { 0, 10, 30, 60, 100, 150, 210, 280, 360, 450, 550, 660, 780, 910,
    1050, 1200, 1360, 1530, 1710, 2000 }
ADB.MAX_LEVEL              = #ADB.XP_THRESHOLDS

-- Special (non-playable) classes: names are data keys, do not translate
ADB.GM_CLASS               = "Boss et Évènements"
ADB.EQUIPMENT_CLASS        = "Équipements"
ADB.ECLIPSE_CLASS          = "Eclipse"

local function Build(raw)
    local list, byName = {}, {}
    for _, r in ipairs(raw) do
        local e = { name = r[1], strength = r[2], agility = r[3], intellect = r[4] }
        list[#list + 1] = e
        byName[e.name] = e
    end
    return list, byName
end

ADB.RACES, ADB.RACE_BY_NAME = Build({
    { "Humain",  10, 10, 15 }, { "Gnome", 10, 10, 15 }, { "Elfe de sang", 10, 10, 15 },
    { "Gobelin", 10, 10, 15 }, { "Troll", 10, 10, 15 }, { "Réprouvé", 10, 10, 15 },
    { "Elfe de la nuit", 10, 15, 10 }, { "Hozen", 10, 15, 10 },
    { "Nain",            15, 10, 10 }, { "Draenei", 15, 10, 10 }, { "Worgen", 15, 10, 10 },
    { "Tauren", 15, 10, 10 }, { "Orc", 15, 10, 10 }, { "Dragon Noir", 15, 10, 10 },
    { "Ogre",   15, 10, 10 }, { "Ogre Magi", 15, 10, 10 }, { "Sacrenuit", 10, 10, 15 },
})

ADB.CLASSES, ADB.CLASS_BY_NAME = Build({
    { "Guerrier",             10, 0,  0 }, { "Chaman", 10, 0, 0 }, { "Paladin", 10, 0, 0 },
    { "Chevalier de la Mort", 10, 0,  0 },
    { "Chasseur",             0,  10, 0 }, { "Voleur", 0, 10, 0 }, { "Moine", 0, 10, 0 },
    { "Chasseur de démons", 0, 10, 0 },
    { "Démoniste",          0, 0,  10 }, { "Druide", 0, 0, 10 }, { "Mage", 0, 0, 10 }, { "Prêtre", 0, 0, 10 },
    { ADB.GM_CLASS, 0, 0, 0 }, { ADB.EQUIPMENT_CLASS, 0, 0, 0 }, { ADB.ECLIPSE_CLASS, 0, 0, 0 },
})

ADB.RACIAL_BY_RACE, ADB.RACIAL_CLASS = {}, {}
for _, r in ipairs(ADB.RACES) do
    local name = "Racial - " .. r.name
    local e = { name = name, strength = 0, agility = 0, intellect = 0 }
    ADB.CLASSES[#ADB.CLASSES + 1] = e
    ADB.CLASS_BY_NAME[name] = e
    ADB.RACIAL_BY_RACE[r.name] = name
    ADB.RACIAL_CLASS[name] = true
end

function ADB.IsSpecialClass(name)
    return name == ADB.GM_CLASS or name == ADB.EQUIPMENT_CLASS or name == ADB.ECLIPSE_CLASS
        or ADB.RACIAL_CLASS[name] == true
end

-- Equipment slots (keys are persisted / wire values)
ADB.EQUIP_SLOTS = {
    { key = "arme", label = "Arme" }, { key = "tete", label = "Tête" }, { key = "haut", label = "Haut" },
    { key = "bas",  label = "Bas" }, { key = "bijou", label = "Bijou" },
}
ADB.SLOT_LABEL = {}
for _, s in ipairs(ADB.EQUIP_SLOTS) do ADB.SLOT_LABEL[s.key] = s.label end

ADB.RARITIES = {
    { name = "Commun",     color = { 1, 1, 1 },          statCap = 2,  hex = "ffffff" },
    { name = "Peu Commun", color = { 0.12, 1, 0 },       statCap = 4,  hex = "1eff00" },
    { name = "Rare",       color = { 0, 0.44, 0.87 },    statCap = 8,  hex = "0070dd" },
    { name = "Épique",     color = { 0.64, 0.21, 0.93 }, statCap = 12, hex = "a335ee" },
}
ADB.STAT_LABELS = { "Force", "Agilité", "Intelligence" }

-- use = effect on use (hp / mp / shield = amount, giant = Force bonus, haste / revive = flag). No `use` = inert.
ADB.CONSUMABLES = {
    ration      = {
        name = "Ration",
        icon = "INV_Misc_Food_14",
        stack = 5,
        desc = "Quand vous vous reposez, mange automatiquement une Ration pour récupérer plus."
    },
    herbe       = { name = "Herbes médicinales", icon = "INV_Misc_Herb_01", stack = 5, rarity = 1,
        desc = "Composant d'alchimie." },
    potvie_inf  = { name = "Potion de soins inférieure", icon = "INV_Potion_51", stack = 1, rarity = 1,
        desc = "Restaure 6 PV.", use = { hp = 6 } },
    potvie      = { name = "Potion de Vie", icon = "INV_Potion_54", stack = 1, rarity = 2,
        desc = "Restaure 12 PV.", use = { hp = ADB.POTION_RESTORE } },
    potvie_sup  = { name = "Potion de soins supérieure", icon = "INV_Potion_55", stack = 1, rarity = 3,
        desc = "Restaure 18 PV.", use = { hp = 18 } },
    potmana_inf = { name = "Potion de mana inférieure", icon = "INV_Potion_71", stack = 1, rarity = 1,
        desc = "Restaure 6 PM.", use = { mp = 6 } },
    potmana     = { name = "Potion de mana", icon = "INV_Potion_76", stack = 1, rarity = 2,
        desc = "Restaure 12 PM.", use = { mp = ADB.POTION_RESTORE } },
    potmana_sup = { name = "Potion de mana supérieure", icon = "INV_Potion_77", stack = 1, rarity = 3,
        desc = "Restaure 18 PM.", use = { mp = 18 } },
    potgeant    = { name = "Potion de taille de géant", icon = "INV_Potion_27", stack = 1, rarity = 1,
        desc = "+20 Force jusqu'au prochain repos (non cumulable).", use = { giant = ADB.GIANT_BONUS } },
    potvitesse  = { name = "Potion de vitesse", icon = "INV_Potion_95", stack = 1, rarity = 2,
        desc = "Permet de rejouer immédiatement une action en combat (n'utilise pas d'action).",
        use = { haste = true } },
    potinvinc   = { name = "Potion d'invincibilité", icon = "INV_Potion_62", stack = 1, rarity = 3,
        desc = "Génère un bouclier de 30 points.", use = { shield = 30 } },
    potresu     = { name = "Potion de résurrection", icon = "INV_Potion_98", stack = 1, rarity = 4,
        desc = "Ressuscite le joueur ciblé (ou vous-même) mort, avec 1 PV.", use = { revive = true } },
}
-- Order shown in the GM item menu.
ADB.CONSUMABLE_ORDER = { "ration", "herbe", "potvie_inf", "potvie", "potvie_sup", "potmana_inf", "potmana",
    "potmana_sup", "potgeant", "potvitesse", "potinvinc", "potresu" }