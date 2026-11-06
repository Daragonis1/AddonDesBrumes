------------------------------------------------------------------------------
-- Liens.lua
------------------------------------------------------------------------------
local ADB = ADB
local floor, max = math.floor, math.max
local format = string.format
local Encoder, Decoder = ADB.Encoder, ADB.Decoder

ADB.lienCache, ADB.lienPend, ADB.lienEnvoye = {}, {}, {}
ADB.CMD_EXT.TL = true

-- Jeton envoyé dans le chat (texte brut, accepté par le serveur) : {ADB:ci:id:Nom}
-- Converti localement en hyperlien cliquable à l'affichage.
local function Conv(msg)
    return (msg:gsub("{ADB:(%d+):(%d+):([^}]*)}", function(ci, id, nom)
        nom = nom:gsub("[|%c]", "")
        return format("|cff71d5ff|Hadb:%s:%s|h[%s]|h|r", ci, id, nom)
    end))
end

local function Decouper(s, taille)
    local t, i = {}, 1
    while i <= #s do
        local j = math.min(i + taille - 1, #s)
        while j < #s and j > i and (s:byte(j + 1) or 0) >= 0x80 and (s:byte(j + 1) or 0) < 0xC0 do
            j = j - 1
        end
        t[#t + 1] = s:sub(i, j)
        i = j + 1
    end
    return t
end

------------------------------------------------------------------------------
-- Emission : jeton + diffusion des données du talent (cache chez les autres joueurs)
------------------------------------------------------------------------------
function ADB.LienDiffuser(ci, n)
    if not IsInGroup() then return end
    local cle, t = ci .. ":" .. n.id, GetTime()
    if (ADB.lienEnvoye[cle] or -999) + 120 > t then return end
    ADB.lienEnvoye[cle] = t
    local ch = Decouper(n.desc or "", 70)
    local flags = (n.reac and 1 or 0) + (n.bonus and 2 or 0)
    ADB.TalEnfiler(format("TL;%d;%d;0;" .. ("%d;"):rep(12) .. "%s;%s", ci, n.id, #ch,
        n.typ, n.stat, n.inter, n.elem, n.mana, n.lim, flags,
        n.coutPV, n.portee, n.precision, n.zoe, n.icon, Encoder(n.nom)))
    for i, s in ipairs(ch) do
        ADB.TalEnfiler(format("TL;%d;%d;%d;%d;%s", ci, n.id, i, #ch, Encoder(s)))
    end
end

function ADB.LienTexte(n, ci)
    ci = ci or ADB.TalIndexClasse(ADB.db.classe)
    if not ci then return n.nom end
    ADB.LienDiffuser(ci, n)
    return format("{ADB:%d:%d:%s}", ci, n.id, (n.nom:gsub("[{}]", "")))
end

------------------------------------------------------------------------------
-- Réception des données (addon message "TL")
------------------------------------------------------------------------------
local function RecevoirLien(nom, message)
    if not (ADB.roster[nom] or ADB.EstNomMJ(nom)) then return end
    local p = { strsplit(";", message) }
    local ci, id, idx, tot = tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5])
    if not (ci and id and idx and tot and ADB.CLASSES[floor(ci)] and id >= 0 and tot >= 0 and tot <= 40) then return end
    ci, id, idx, tot = floor(ci), floor(id), floor(idx), floor(tot)
    local cle = ci .. ":" .. id
    local pk = nom .. cle
    local e = ADB.lienPend[pk]
    if idx == 0 then
        local fl = tonumber(p[12]) or 0
        e = { tot = tot, dp = {}, t = {
            typ = p[6], stat = p[7], inter = p[8], elem = p[9], mana = p[10], lim = p[11],
            reac = (fl % 2 == 1), bonus = (floor(fl / 2) % 2 == 1),
            coutPV = p[13], portee = p[14], precision = p[15], zoe = p[16],
            icon = p[17], nom = Decoder(p[18] or ""),
        } }
        ADB.lienPend[pk] = e
    elseif e and idx >= 1 and idx <= e.tot then
        e.dp[idx] = Decoder(p[6] or "")
    else
        return
    end
    for i = 1, e.tot do
        if not e.dp[i] then return end
    end
    ADB.lienPend[pk] = nil
    e.t.id = max(1, id) -- ValiderNoeud refuse id < 1 (attaque de base = id 0)
    e.t.desc = table.concat(e.dp, "", 1, e.tot)
    local n = ADB.TalValiderNoeud(e.t)
    if n then
        n.id = id
        ADB.lienCache[cle] = n
    end
end

local oExt = ADB.RecevoirExt
ADB.RecevoirExt = function(cmd, nom, message)
    if cmd == "TL" then return RecevoirLien(nom, message) end
    return oExt(cmd, nom, message)
end

------------------------------------------------------------------------------
-- Affichage : filtres de chat (jeton -> hyperlien) + solo
------------------------------------------------------------------------------
local function Filtre(_, _, msg, ...)
    if msg and msg:find("{ADB:", 1, true) then return false, Conv(msg), ... end
end
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ChatFrame_AddMessageEventFilter(ev, Filtre)
end

local oAnn = ADB.AnnoncerChat
ADB.AnnoncerChat = function(txt)
    if not IsInGroup() then return ADB.Print(Conv(txt)) end
    return oAnn(txt)
end

------------------------------------------------------------------------------
-- Clic sur le lien : tooltip dans ItemRefTooltip
------------------------------------------------------------------------------
local function Chercher(ci, id)
    local n = ADB.lienCache[ci .. ":" .. id]
    if n then return n end
    local c = ADB.CLASSES[ci]
    if not c then return nil end
    if c[1] == ADB.db.classe then return ADB.TalNoeudPropre(id) end
    local a = ADB.TalArbre(c[1])
    return a and a.noeuds[id]
end

hooksecurefunc("SetItemRef", function(link, text)
    local ci, id = (link or ""):match("^adb:(%d+):(%d+)$")
    if not ci or not ADB.db then return end
    ci, id = tonumber(ci), tonumber(id)
    local n = Chercher(ci, id)
    local T = ItemRefTooltip
    if n then
        ADB.TalInfobulle(UIParent, n, "arbre", T, "ANCHOR_PRESERVE")
        T:AddLine(" ")
        T:AddLine("Compétence JDR", 0.6, 0.6, 0.6)
    else
        T:SetOwner(UIParent, "ANCHOR_PRESERVE")
        T:AddLine((text or ""):match("|h%[(.-)%]|h") or "Compétence", 1, 0.82, 0)
        T:AddLine("Données indisponibles (utilisée avant votre connexion).", 1, 0.3, 0.3, true)
    end
    T:Show()
end)

local function SurvolLien(self, link)
    local ci, id = (link or ""):match("^adb:(%d+):(%d+)$")
    if not ci or not ADB.db then return end
    local n = Chercher(tonumber(ci), tonumber(id))
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")          -- ancré au curseur, comme un sort natif
    if n then
        ADB.TalInfobulle(self, n, "arbre", GameTooltip, "ANCHOR_CURSOR")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Compétence JDR", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Compétence", 1, 0.82, 0)
        GameTooltip:AddLine("Données indisponibles (utilisée avant votre connexion).", 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

local function FinSurvolLien()
    GameTooltip:Hide()
end

-- Hook sur toutes les fenêtres de chat existantes (HookScript : n'écrase pas les scripts natifs)
for i = 1, NUM_CHAT_WINDOWS do
    local cf = _G["ChatFrame" .. i]
    if cf then
        cf:HookScript("OnHyperlinkEnter", SurvolLien)
        cf:HookScript("OnHyperlinkLeave", FinSurvolLien)
    end
end

-- Fenêtres de chat créées/ouvertes plus tard (onglets temporaires, whispers...)
hooksecurefunc("FCF_OpenTemporaryWindow", function()
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf and not cf.adbHook then
            cf.adbHook = true
            cf:HookScript("OnHyperlinkEnter", SurvolLien)
            cf:HookScript("OnHyperlinkLeave", FinSurvolLien)
        end
    end
end)