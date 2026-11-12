-- Core/Slash.lua : /brumes and /adb sub-command registry (modules register their own).
local ADB = ADB
local Slash = {}
ADB.Slash = Slash

SLASH_ADDONDESBRUMES1, SLASH_ADDONDESBRUMES2 = "/brumes", "/adb"

local commands = {}

-- names: string or list of strings; fn(rest)
function Slash.Register(names, fn)
    if type(names) == "string" then names = { names } end
    for _, n in ipairs(names) do commands[n] = fn end
end

local HELP = "Commandes : /brumes (fiche), /brumes fiche [nom], /brumes nom [Nom RP], "
    .. "/brumes inv, /brumes objet, /brumes pnj, /brumes mj (XP), /brumes repos, /brumes talents, /brumes ui"

SlashCmdList["ADDONDESBRUMES"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    local fn = commands[cmd:lower()]
    if fn then fn(rest) else ADB.Print(HELP) end
end