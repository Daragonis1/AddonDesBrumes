-- Logic/Gifts.lua : player → player item transfer. (Story-item creation window → UI/ItemCreator.lua.)
-- Wire (frozen): IT;target;kind;slot;rarity;icon;s1;s2;s3;name;skillsText;skillIds;count;nChunks;tags
--                IU;target;i;n;descChunk
local ADB = ADB
local Net, UI = ADB.Net, ADB.UI
local floor = math.floor
local format = string.format
local Encode, Decode = ADB.Encode, ADB.Decode

local Gifts = {}
ADB.Gifts = Gifts
ADB.transferMode = nil

-- Queues an item for `target` (header + description chunks).
function Gifts.Send(target, it)
    local desc = ADB.SplitUtf8(it.desc or "", 60)
    Net.Enqueue(format("IT;%s;%s;%s;%d;%s;%d;%d;%d;%s;%s;%s;%d;%d;%s", target, it.kind, it.slot or "",
        it.rarity or 1, it.icon or "", it.stats and it.stats[1] or 0, it.stats and it.stats[2] or 0,
        it.stats and it.stats[3] or 0, Encode(it.name or ""), Encode(it.skillsText or ""),
        table.concat(it.skillIds or {}, ","), it.count or 1, #desc, table.concat(it.tags or {}, ",")))
    for i, s in ipairs(desc) do
        Net.Enqueue(format("IU;%s;%d;%d;%s", target, i, #desc, Encode(s)))
    end
end

local buffers = {}   -- [sender] = { t, n, parts }
local function Deliver(sender, t)
    local it = ADB.Items.Validate(t)
    if not it then return end
    if ADB.Items.Add(it, 1) >= 1 then
        ADB.Print(format("%s vous a transféré : %s.", ADB.Stats.DisplayName(sender), ADB.Items.ColoredName(it)))
    else
        ADB.Print("Votre inventaire est plein ! " .. ADB.Items.ColoredName(it) .. " de "
            .. ADB.Stats.DisplayName(sender) .. " perdu.")
    end
end

local function Receive(sender, message, cmd)
    if not (ADB.roster[sender] or ADB.IsGMName(sender)) then return end
    local p = Net.Split(message)
    if p[2] ~= ADB.playerName then return end
    if cmd == "IT" then
        local nb = floor(tonumber(p[14]) or 0)
        local t = {
            kind = p[3], slot = p[4], rarity = tonumber(p[5]), icon = p[6],
            stats = { tonumber(p[7]), tonumber(p[8]), tonumber(p[9]) },
            name = Decode(p[10] or ""), skillsText = Decode(p[11] or ""), skillIds = p[12],
            count = tonumber(p[13]), tags = p[15],
        }
        if nb <= 0 then Deliver(sender, t)
        elseif nb <= 10 then buffers[sender] = { t = t, n = nb, parts = {} } end
    else
        local b, i, n = buffers[sender], tonumber(p[3]), tonumber(p[4])
        if not (b and i and n == b.n and i >= 1 and i <= n) then return end
        b.parts[floor(i)] = Decode(p[5] or "")
        for j = 1, n do if not b.parts[j] then return end end
        buffers[sender] = nil
        b.t.desc = table.concat(b.parts, "", 1, n)
        Deliver(sender, b.t)
    end
end
Net.RegisterMany({ "IT", "IU" }, Receive)

------------------------------------------------------------------------------
-- Transfer mode: button + click on item
------------------------------------------------------------------------------
local function SetMode(on)
    ADB.transferMode = on
    local b = ADB.invFrame and ADB.invFrame.TransferBtn
    if b then b:SetText(on and "Annuler" or "Transférer") end
end

-- Popup name frozen (wrapped by Alt.lua)
StaticPopupDialogs["ADB_DON"] = {
    text = "Transférer %s à %s ?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(_, data) if data then Gifts.Confirm(data) end end,
}

function Gifts.Request(zone, key)
    SetMode(false)
    local it = ADB.Items.GetAt(zone, key)
    local target = ADB.Group.GetTargetPlayer()
    if not it then return end
    if not target or target == ADB.playerName or not IsInGroup() then
        ADB.Print("Ciblez un autre joueur (en groupe, avec l'addon).")
        return
    end
    StaticPopup_Show("ADB_DON", ADB.Items.ColoredName(it), ADB.Stats.DisplayName(target),
        { zone = zone, key = key, target = target })
end

function Gifts.Confirm(d)
    local it = ADB.Items.GetAt(d.zone, d.key)
    if not it or not ADB.roster[d.target] then return end
    local copy = CopyTable(it)
    if copy.count then copy.count = 1 end
    Gifts.Send(d.target, copy)
    local text = ADB.Items.ColoredName(it)
    if d.zone == "inv" then
        ADB.Items.RemoveAt(d.key)
        ADB.InventoryWindow.Refresh()
    else
        ADB.Items.Destroy(d.zone, d.key)
    end
    ADB.Print(format("%s transféré à %s.", text, ADB.Stats.DisplayName(d.target)))
end

ADB.Wrap(ADB.InventoryWindow, "OnSlotClick", function(orig, button, mouseButton)
    if ADB.transferMode and mouseButton == "LeftButton" and ADB.Items.GetAt(button.zone, button.key) then
        return Gifts.Request(button.zone, button.key)
    end
    return orig(button, mouseButton)
end)

hooksecurefunc(ADB.InventoryWindow, "Create", function()
    local f = ADB.invFrame
    f:SetHeight(450)
    f.TransferBtn = UI.Button(f, "Transférer", 16, -410, 100, function()
        SetMode(not ADB.transferMode)
        if ADB.transferMode then ADB.Print("Ciblez un joueur, puis cliquez sur l'objet à transférer.") end
    end)
    f:HookScript("OnHide", function() SetMode(false) end)
end)