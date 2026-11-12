-- Logic/Items.lua : item validation, inventory, equipment, consumables, money, GM item sending, potion-as-action.
local ADB = ADB
local floor = math.floor
local format = string.format
local Clamp, CleanName, Encode = ADB.Clamp, ADB.CleanName, ADB.Encode

local Items = {}
ADB.Items = Items

function Items.SanitizeSkillIds(s)
    local out, seen = {}, {}
    local src = type(s) == "table" and table.concat(s, ",") or tostring(s or "")
    for w in src:gmatch("%d+") do
        local id = floor(tonumber(w))
        if id >= 1 and id <= 99999 and not seen[id] and #out < 3 then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

-- Validates/sanitizes an item (local or received). Returns nil if invalid.
function Items.Validate(t)
    if type(t) ~= "table" then return nil end
    local def = ADB.CONSUMABLES[t.kind]
    if def then
        return { kind = t.kind, count = Clamp(floor(tonumber(t.count) or 1), 1, def.stack) }
    end
    local name = CleanName(t.name)
    if name == "" then name = "Objet" end
    if t.kind == "story" then
        return { kind = "story", rarity = Clamp(floor(tonumber(t.rarity) or 1), 1, #ADB.RARITIES),
            icon = ADB.SanitizeIcon(t.icon), name = name, desc = CleanName(t.desc):sub(1, 400),
            tags = ADB.Talents.SanitizeTags(t.tags) }
    end
    if t.kind ~= "equip" or not ADB.SLOT_LABEL[t.slot] then return nil end
    local rarity = Clamp(floor(tonumber(t.rarity) or 1), 1, #ADB.RARITIES)
    local stats, total = {}, 0
    for i = 1, 3 do
        stats[i] = Clamp(floor(tonumber((type(t.stats) == "table" and t.stats[i]) or 0) or 0), 0, 12)
        total = total + stats[i]
    end
    if total > ADB.RARITIES[rarity].statCap then return nil end
    return { kind = "equip", slot = t.slot, rarity = rarity, stats = stats, icon = ADB.SanitizeIcon(t.icon),
        name = name, skillsText = CleanName(t.skillsText), skillIds = Items.SanitizeSkillIds(t.skillIds),
        tags = ADB.Talents.SanitizeTags(t.tags) }
end

-- Returns name, texture, r, g, b, hex.
function Items.Info(it)
    local def = ADB.CONSUMABLES[it.kind]
    if def then return def.name, ADB.IconTexture(def.icon), 0.5, 0.5, 0.5, "ffffff" end
    local R = ADB.RARITIES[it.rarity]
    return it.name, ADB.IconTexture(it.icon), R.color[1], R.color[2], R.color[3], R.hex
end

function Items.ColoredName(it)
    local name, _, _, _, _, hex = Items.Info(it)
    return "|cff" .. hex .. name .. "|r"
end

-- zone: "inv" (key = slot index) | "eq" (key = slot key)
function Items.GetAt(zone, key)
    if not ADB.db then return nil end
    if zone == "inv" then return ADB.db.inventory[key] end
    return ADB.db.equipment[key]
end

function Items.FindByTag(tag)
    local inv = ADB.db and ADB.db.inventory
    if not inv then return nil end
    for i = 1, ADB.INV_SLOTS do
        local it = inv[i]
        if it and it.tags then
            for _, t in ipairs(it.tags) do
                if t == tag then return it end
            end
        end
    end
    return nil
end

------------------------------------------------------------------------------
-- Inventory
------------------------------------------------------------------------------
-- Adds `qty` (consumables only) of `it`. Returns number actually added.
function Items.Add(it, qty)
    local inv = ADB.db.inventory
    local def = ADB.CONSUMABLES[it.kind]
    local added = 0
    for _ = 1, (def and (qty or 1) or 1) do
        local placed = false
        if def and def.stack > 1 then
            for i = 1, ADB.INV_SLOTS do
                local s = inv[i]
                if s and s.kind == it.kind and s.count < def.stack then
                    s.count = s.count + 1
                    placed = true
                    break
                end
            end
        end
        if not placed then
            for i = 1, ADB.INV_SLOTS do
                if not inv[i] then
                    inv[i] = def and { kind = it.kind, count = 1 } or CopyTable(it)
                    placed = true
                    break
                end
            end
        end
        if not placed then break end
        added = added + 1
    end
    ADB.InventoryWindow.Refresh()
    return added
end

function Items.Receive(it, qty)
    qty = qty or 1
    local n = Items.Add(it, qty)
    if n >= 1 then
        ADB.Print(format("Vous recevez : %s%s.", Items.ColoredName(it), n > 1 and (" x" .. n) or ""))
    end
    if n < qty then ADB.Print("Votre inventaire est plein !") end
end

function Items.RemoveAt(i)
    local s = ADB.db.inventory[i]
    if not s then return end
    if s.count and s.count > 1 then s.count = s.count - 1 else ADB.db.inventory[i] = nil end
end

function Items.RemoveConsumable(kind)
    for i = 1, ADB.INV_SLOTS do
        local s = ADB.db.inventory[i]
        if s and s.kind == kind then
            Items.RemoveAt(i)
            return true
        end
    end
    return false
end

function Items.Equip(i)
    local it = ADB.db.inventory[i]
    if not it or it.kind ~= "equip" then return end
    ADB.Stats.ModifySheet(function(db)
        local old = db.equipment[it.slot]
        db.equipment[it.slot] = it
        db.inventory[i] = old
    end)
end

function Items.Unequip(slot)
    local it = ADB.db.equipment[slot]
    if not it then return end
    for i = 1, ADB.INV_SLOTS do
        if not ADB.db.inventory[i] then
            ADB.Stats.ModifySheet(function(db)
                db.inventory[i] = it
                db.equipment[slot] = nil
            end)
            return
        end
    end
    ADB.Print("Votre inventaire est plein !")
end

function Items.Destroy(zone, key)
    ADB.selection = nil
    if zone == "inv" then
        ADB.db.inventory[key] = nil
        ADB.InventoryWindow.Refresh()
    else
        ADB.Stats.ModifySheet(function(db) db.equipment[key] = nil end)
    end
end

------------------------------------------------------------------------------
-- Money
------------------------------------------------------------------------------
function Items.ChangeCopper(delta)
    ADB.db.copper = Clamp(ADB.db.copper + delta, 0, ADB.COPPER_MAX)
    ADB.Sync.AfterLocalChange()
end

-- Who money operations apply to: GM's targeted player, else self.
function Items.MoneyTarget()
    if ADB.IsGM() and UnitExists("target") and UnitIsPlayer("target") then
        local n = UnitName("target")
        if n ~= ADB.playerName and ADB.roster[n] then return n end
    end
    return ADB.playerName
end

------------------------------------------------------------------------------
-- Potions (= an action)
------------------------------------------------------------------------------
function Items.UsePotion(i)
    local s = ADB.db.inventory[i]
    if not s or (s.kind ~= "potvie" and s.kind ~= "potmana") then return end
    Items.RemoveAt(i)
    local kind = (s.kind == "potvie") and "hp" or "mp"
    local d = ADB.Stats.GetBlock(ADB.playerName)
    local new = math.min(d[ADB.Stats.MAX_KEY[kind]], d[kind] + ADB.POTION_RESTORE)
    ADB.db[kind] = new
    ADB.Print(format("Vous utilisez %s : +%d %s.", ADB.CONSUMABLES[s.kind].name, new - d[kind],
        kind == "hp" and "PV" or "PM"))
    ADB.Sync.AfterLocalChange()
    if kind == "hp" then
        ADB.Stats.TrackHp("J:" .. ADB.playerName, ADB.Stats.DisplayName(ADB.playerName), new - d.hp)
    end
end

function Items.RequestPotion(i)
    local s = ADB.db.inventory[i]
    if not s then return end
    if ADB.phase == "IDLE" or ADB.IsGM() then return Items.UsePotion(i) end
    if ADB.phase == "PLAYER_TURN" and not ADB.turnPassed then
        Items.UsePotion(i)
        ADB.Combat.PlayerEndTurn()
    else
        StaticPopup_Show("ADB_TAL_HORSTOUR", ADB.CONSUMABLES[s.kind].name, nil, { potion = i })
    end
end

function Items.RequestPotionGM(i)
    local s = ADB.db.inventory[i]
    if not s then return end
    local T = ADB.Talents
    if not IsInGroup() or not T.source then
        ADB.Print("Aucun MJ disponible pour valider cette action.")
        return
    end
    T.token = (T.token or 0) + 1
    T.pending[T.token] = { potion = i, kind = s.kind }
    ADB.Net.Send(format("HQ;%d;0;%s;;", T.token, Encode(ADB.CONSUMABLES[s.kind].name)))
    ADB.Print("Demande envoyée au MJ pour « " .. ADB.CONSUMABLES[s.kind].name .. " ». En attente de validation...")
end

------------------------------------------------------------------------------
-- GM → player item sending
------------------------------------------------------------------------------
function Items.Send(target, it, qty)
    if target == ADB.playerName then
        Items.Receive(it, qty)
        return
    end
    if it.kind == "equip" then
        ADB.Net.Send(format("IE;%s;%s;%d;%s;%d;%d;%d;%s;%s;%s;%s", target, it.slot, it.rarity, it.icon,
            it.stats[1], it.stats[2], it.stats[3], Encode(it.name), Encode(it.skillsText),
            table.concat(it.skillIds or {}, ","), table.concat(it.tags or {}, ",")))
    else
        ADB.Net.Send(format("IC;%s;%s;%d", target, it.kind, qty))
    end
    ADB.Print(format("%s envoyé à %s.", Items.ColoredName(it), ADB.Stats.DisplayName(target)))
end