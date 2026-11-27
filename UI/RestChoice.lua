-- UI/RestChoice.lua : choice window shown to players after a GM rest (rest / train / work / other).
local ADB, UI = ADB, ADB.UI
local floor = math.floor

local RC = {}
ADB.RestChoice = RC

function RC.Rest()
    local db, d = ADB.db, ADB.Stats.GetBlock(ADB.playerName)
    db.hp = math.min(d.maxHp, db.hp + floor(d.maxHp * ADB.REST_EXTRA_PCT / 100 + 0.5))
    db.mp = math.min(d.maxMp, db.mp + floor(d.maxMp * ADB.REST_EXTRA_PCT / 100 + 0.5))
    ADB.Print(string.format("Vous prenez du repos : +%d%% de PV et de PM.", ADB.REST_EXTRA_PCT))
    ADB.Sync.AfterLocalChange()
end

function RC.Train() ADB.Stats.ReceiveXP(ADB.TRAIN_XP) end

function RC.Work()
    local p = ADB.db.profession
    local def = p and ADB.PROFESSION_BY_KEY[p.key]
    if not def then return end
    ADB.Items.Receive({ kind = def.component }, math.random(ADB.WORK_MIN, ADB.WORK_MAX))
end

function RC.Other()
    ADB.Print("Précisez votre action de repos au MJ.")
    ADB.Net.Announce(string.format("%s doit préciser son action de repos au MJ.",
        ADB.Stats.DisplayName(ADB.playerName)))
end

local function Create()
    local f = UI.BaseWindow("ADBRestChoiceFrame", 260, 200, "Repos")
    ADB.restChoiceFrame = f
    f:SetPoint("CENTER", 0, 120)
    UI.Label(f, "Comment employez-vous ce repos ?", 16, -38)
    local function Choice(y, text, fn)
        return UI.Button(f, text, 20, y, 220, function()
            f:Hide()
            fn()
        end)
    end
    Choice(-66, "Prendre du repos", RC.Rest)
    Choice(-94, "S'entraîner", RC.Train)
    f.Work = Choice(-122, "Travailler", RC.Work)
    Choice(-150, "Autres", RC.Other)
end

function RC.Show()
    if ADB.IsGM() or not ADB.db then return end
    if not ADB.restChoiceFrame then Create() end
    local f = ADB.restChoiceFrame
    f.Work:SetEnabled(ADB.db.profession ~= nil)
    f:Show()
end