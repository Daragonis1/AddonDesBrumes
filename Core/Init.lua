-- Core/Init.lua : single global namespace (required by XML scripts) and shared runtime state.
ADB = ADB or {}
local ADB = ADB

ADB.VERSION   = "2.0"
ADB.PREFIX    = "AddonDesBrumes"   -- addon-message prefix (wire-frozen)
ADB.DB_SCHEMA = 2

-- Shared runtime state (memory only)
ADB.roster          = {}      -- [playerName] = remote stat sheet received via "S"
ADB.phase           = "IDLE"  -- IDLE | STARTING | PLAYER_TURN | ALLY_TURN | ENEMY_TURN
ADB.finishedPlayers = {}      -- [playerName] = true once turn ended (GM side)
ADB.memberFrames    = {}
ADB.npcFrames       = {}
ADB.receivedNpcs    = {}      -- NPC list received from the GM
ADB.npcSource       = nil
ADB.dirtyNpcs       = {}      -- NPC ids pending broadcast
ADB.hpAggregates    = {}      -- debounced HP/shield chat announcements
ADB.memberRows      = 0