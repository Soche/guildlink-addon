local _, ns = ...

-- Records the dungeons and raids characters enter, with the game's own name
-- and player limit, so the bot can offer them when scheduling. The client's
-- Encounter Journal is empty on Forever, so this is the reliable source.

local KINDS = { party = "dungeon", raid = "raid" }

function ns.RecordInstance()
  if not ns.db or not GetInstanceInfo then return end
  local name, instanceType, _, _, maxPlayers, _, _, instanceID, groupSize = GetInstanceInfo()
  local kind = KINDS[instanceType]
  if not kind or not name or name == "" or not instanceID or instanceID == 0 then return end
  local players = (maxPlayers and maxPlayers > 0) and maxPlayers or groupSize
  if not players or players <= 0 then return end

  if type(ns.db.instances) ~= "table" then
    ns.db.instances = {}
  end
  local entry = ns.db.instances[instanceID]
  if type(entry) ~= "table" then
    entry = {}
    ns.db.instances[instanceID] = entry
  end
  entry.name = name
  entry.kind = kind
  entry.maxPlayers = players
  entry.seenAt = time()
end

-- Instance info can lag the loading screen slightly.
local function RecordSoon()
  C_Timer.After(2, ns.RecordInstance)
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", RecordSoon)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", RecordSoon)
