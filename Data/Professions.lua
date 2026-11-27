-- Data/Professions.lua : professions, profession XP table and recipes. Keys are persisted values.
local ADB = ADB

ADB.PROFESSIONS = {
    { key = "alchimie", name = "Alchimie", title = "Alchimiste", component = "herbe", available = true },
    { key = "enchantement", name = "Enchantement" },
    { key = "forgeron", name = "Forgeron" },
    { key = "couturier", name = "Couturier" },
    { key = "travailducuir", name = "Travail du cuir" },
    { key = "ingenieur", name = "Ingénieur" },
    { key = "calligraphie", name = "Calligraphie" },
    { key = "joaillerie", name = "Joaillerie" },
}
ADB.PROFESSION_BY_KEY = {}
for _, p in ipairs(ADB.PROFESSIONS) do ADB.PROFESSION_BY_KEY[p.key] = p end

-- Cumulative profession XP required to reach each level (level 10 = max, no XP gained beyond).
ADB.PROF_XP = { 0, 5, 15, 30, 50, 75, 105, 140, 180, 225 }
ADB.PROF_MAX_LEVEL = #ADB.PROF_XP

-- cost = { { consumableKind, count } } ; xp (optional) = profession XP per craft, default = components spent.
-- The recipe of level N is learned automatically on reaching level N.
ADB.RECIPES = {
    alchimie = {
        { level = 1,  item = "potvie_inf",  cost = { { "herbe", 2 } } },
        { level = 2,  item = "potmana_inf", cost = { { "herbe", 3 } } },
        { level = 3,  item = "potgeant",    cost = { { "herbe", 4 } } },
        { level = 4,  item = "potvie",      cost = { { "herbe", 2 } } },
        { level = 5,  item = "potmana",     cost = { { "herbe", 3 } } },
        { level = 6,  item = "potvitesse",  cost = { { "herbe", 4 } } },
        { level = 7,  item = "potvie_sup",  cost = { { "herbe", 3 } } },
        { level = 8,  item = "potmana_sup", cost = { { "herbe", 4 } } },
        { level = 9,  item = "potinvinc",   cost = { { "herbe", 5 } } },
        { level = 10, item = "potresu",     cost = { { "herbe", 50 } } },
    },
}