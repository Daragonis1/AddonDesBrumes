-- Data/EffectScripts.lua : effect scripts (see syntax in Logic/Effects.lua).
-- Keys are talent NAMES / TAGS as authored in-game (data, do not translate).
local E = ADB.Effects

E.DefineTag("ReducCDKillOrder", [[
hit: cd "#KillOrder" 1
]])
E.DefineTag("ReducCDTraqueffroi", [[
hit: cd "#Traqueffroi" 1
]])
E.Define("Aspect de la tortue", [[
hit [pet]: shield self 6; shield pet 6
hit [!pet]: shield self 3; shield target 3
]])
E.Define("Rossée", [[
hit: damage zonepet:10 3
]])
E.Define("Ordre de tuer", [[
use: recharge "Rossée"
]])
E.Define("Ruée ardente", [[
use: move 10
]])
E.Define("Enchaînement bestial", [[
passive: bonus "Rossée sauvage" 5
]])
E.Define("Démoniste", [[
passive: manatopv
]])
E.DefineTag("DemonicBolt", [[
hit: cd "#Traqueffroi" 1 t
]])
E.DefineTag("Moonguard", [[
passive: luna 50
]])
E.DefineTag("Immolate", [[
hit: manaint 3
]])
E.DefineTag("PetHeal", [[
hit: petheal 4 7
]])
E.DefineTag("avatarofvengeance", [[
use: avatar
]])