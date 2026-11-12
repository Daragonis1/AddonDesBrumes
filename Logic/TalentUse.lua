-- Logic/TalentUse.lua : using an active talent (execution, GM approval, off-turn flow) and confirmation popups.
-- data = { id, targetName, targets = {entry…}, force, potion, kind }
local ADB = ADB
local Net, Talents = ADB.Net, ADB.Talents
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local Encode = ADB.Encode

local function Announce(text)
    for _, s in ipairs(ADB.SplitUtf8(text, 240)) do ADB.Net.Announce(s) end
end

local function NamesOf(list)
    local t = {}
    for _, e in ipairs(list or {}) do t[#t + 1] = e.name end
    return table.concat(t, ", ")
end
Talents.NamesOf = NamesOf

function Talents.TargetName()
    if not UnitExists("target") then return nil end
    local name = UnitName("target")
    if UnitIsPlayer("target") and (name == ADB.playerName or ADB.roster[name]) then
        return ADB.Stats.DisplayName(name)
    end
    return name
end

-- Spends costs, rolls accuracy, applies effect/buff, announces. Returns true when used.
function Talents.Execute(n, data, offTurn)
    data = data or {}
    local ok, reason, code = Talents.GetState(n)
    if not ok and not (data.force and code) then
        ADB.Print(reason)
        return false
    end

    if n.range > 0 then
        if not UnitExists("target") then
            ADB.Print(format("Cible requise (portée : %dm).", n.range))
            return false
        end
        local d = ADB.Measure.Distance("target")
        if d and d > n.range then
            local m = format("Cible trop éloignée. Portée : %dm, Distance actuelle : %dm", n.range, floor(d + 0.5))
            ADB.Print(m)
            UIErrorsFrame:AddMessage(m, 1, 0.3, 0.3)
            return false
        end
    end

    local db = ADB.db
    db.mp = max(0, db.mp - n.mana)
    if n.hpCost > 0 then db.hp = max(0, db.hp - n.hpCost) end
    Talents.SetCooldown(n)

    local who = ADB.Stats.DisplayName(ADB.playerName)
    local targets = data.targets
    if (not targets or #targets == 0) and not data.targetName and n.effect >= 2 and n.effect <= 3 then
        targets = { { kind = "P", id = ADB.playerName, name = who } }
    end
    local names = (targets and #targets > 0) and NamesOf(targets) or data.targetName
    local msg = format("%s a utilisé %s", who, ADB.Links.Text(n))
        .. ((names and names ~= "") and (" sur " .. names) or "") .. "."
    if n.hpCost > 0 then msg = msg .. format(" (coût : %d PV)", n.hpCost) end

    local _, value = Talents.FormatDescription(n.desc, true, Talents.Multiplier(n), Talents.SpecBonus(n))
    local bonusAcc, bonusCrit, bonusDmg, advantage = ADB.Buffs.GetBonus("P:" .. ADB.playerName)
    if value and n.effect == 1 then value = floor(value * bonusDmg + 0.5) end
    local hasEffect = value and n.effect <= 3
    local mult, failed = 1, false

    if n.accuracy > 0 then
        local r, label, color, m, f = ADB.Combat.Roll(n.accuracy, bonusAcc, bonusCrit, advantage)
        mult, failed = m, f
        msg = msg .. format(" Jet de précision : %d (%s).", r, label)
        UIErrorsFrame:AddMessage(format("%d - %s", r, label), color[1], color[2], color[3])
    end

    if failed then
        msg = msg .. " La compétence échoue."
    else
        if hasEffect then
            local v = value * mult
            local txt = ({ " La compétence inflige %d dégâts.", " La compétence a rendu %d points de vie.",
                " La compétence a procuré %d de bouclier." })[n.effect]
            msg = msg .. format(txt, v) .. (mult > 1 and " (effet doublé)" or "")
            if targets and #targets > 0 then ADB.Measure.SendEffects(targets, n.effect, v) end
        end
        if (n.buffId or 0) > 0 then ADB.Buffs.FromTalent(n, targets) end
        local spec = Talents.ActiveSpec()
        if spec and spec.specTagY ~= "" and Talents.HasTag(n, spec.specTagY) then
            local gain = max(1, floor(Talents.Multiplier(n) + 0.5))
            local d = ADB.Stats.GetBlock(ADB.playerName)
            db.mp = min(d.maxMp, db.mp + gain)
            msg = msg .. format(" Regain de mana : +%d PM.", gain)
        end
    end

    if data.force then msg = msg .. " (validé par le MJ)"
    elseif offTurn then msg = msg .. " (hors-tour, validé par le MJ)" end
    Announce(msg)
    ADB.Sync.AfterLocalChange()
    return true
end

-- GM triggers a "Boss et Évènements" talent on the current target / zone (raw values, no stat scaling).
function Talents.GmTrigger(n)
    local ci = Talents.ClassIndex(ADB.GM_CLASS)
    local targets
    if UnitExists("target") then
        if n.aoe > 0 then
            targets = ADB.Measure.ZoneTargets(n.aoe / 2)
        else
            local e = ADB.Measure.UnitEntry("target")
            targets = e and { e } or nil
        end
    end
    local names = NamesOf(targets)
    local _, value = Talents.FormatDescription(n.desc, true, 1, 0)
    local msg = "[MJ] " .. ADB.Links.Text(n, ci) .. (names ~= "" and (" sur " .. names) or "") .. "."
    if value and n.effect <= 3 then
        msg = msg .. format(({ " Inflige %d dégâts.", " Rend %d PV.", " Procure %d de bouclier." })[n.effect], value)
        if targets and #targets > 0 then ADB.Measure.SendEffects(targets, n.effect, value) end
    end
    Announce(msg)
    if (n.buffId or 0) > 0 and targets and #targets > 0 then ADB.Buffs.FromTalent(n, targets) end
    local plain = n.desc:gsub("[%[%]]", "")
    if plain ~= "" then Announce(plain) end
end

function Talents.AfterConfirm(data)
    local n = data and Talents.GetNode(data.id)
    if not n then return end
    if ADB.phase == "PLAYER_TURN" and not ADB.turnPassed then
        if Talents.Execute(n, data, false) and not n.bonusAction then ADB.Combat.PlayerEndTurn() end
    else
        StaticPopup_Show("ADB_TAL_HORSTOUR", n.name, nil, data)
    end
end

function Talents.RequestGmApproval(data, force)
    local n = data and Talents.GetNode(data.id)
    if not n then return end
    if not IsInGroup() or not Talents.source then
        ADB.Print("Aucun MJ disponible pour valider cette action.")
        return
    end
    Talents.token = (Talents.token or 0) + 1
    Talents.pending[Talents.token] = data
    Net.Send(format("HQ;%d;%d;%s;%s;%s", Talents.token, n.id, Encode(n.name),
        Encode(data.targetName or ""), force and "F" or ""))
    ADB.Print("Demande envoyée au MJ pour « " .. n.name .. " ». En attente de validation...")
end

function Talents.OffTurn(data)
    if data and data.potion then return ADB.Items.RequestPotionGM(data.potion) end
    local n = data and Talents.GetNode(data.id)
    if not n then return end
    if n.reaction then
        if Talents.Execute(n, data, false) then
            ADB.skipTurn = true
            ADB.Print("Compétence de réaction utilisée en avance : votre prochain tour sera sauté.")
        end
        return
    end
    Talents.RequestGmApproval(data)
end

------------------------------------------------------------------------------
-- Popups (names are frozen: wrapped by Alt.lua)
------------------------------------------------------------------------------
local function Dialog(text, onAccept, extra)
    local d = { text = text, button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
        preferredIndex = 3, OnAccept = onAccept }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end

StaticPopupDialogs["ADB_TAL_UTILISER"] = Dialog("Utiliser la compétence %s%s ?",
    function(_, data) Talents.AfterConfirm(data) end)
StaticPopupDialogs["ADB_TAL_HORSTOUR"] = Dialog("Ce n'est pas votre tour (ou vous l'avez déjà passé).\nUtiliser quand même %s ?",
    function(_, data) Talents.OffTurn(data) end)
StaticPopupDialogs["ADB_TAL_FORCE"] = Dialog("Action interdite. Confirmer et envoyer la demande au MJ ?",
    function(_, data) if data then Talents.RequestGmApproval(data, true) end end)
StaticPopupDialogs["ADB_TAL_VALIDATION"] = Dialog("%s demande à utiliser « %s ».\nValider ?",
    function(_, data)
        if data and ADB.IsGM() then Net.Send(format("HR;%s;%d;1", data.player, data.token)) end
    end, {
        button1 = "Valider", button2 = "Refuser",
        OnCancel = function(_, data, reason)
            if data and reason == "clicked" and ADB.IsGM() then
                Net.Send(format("HR;%s;%d;0", data.player, data.token))
            end
        end,
    })