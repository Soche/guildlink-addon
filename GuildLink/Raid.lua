local _, ns = ...

-- Records raids for attendance, loot history and boss progress. While this
-- character is in a raid group inside a raid instance, it notes who is in
-- the group (sampled every minute and on roster changes), the rare and
-- better items looted, and each boss encounter's outcome. Saved per raid in
-- GuildLinkDB.raids; the bot merges everyone's copies of the same raid.

local SAMPLE_SECONDS = 60
-- A raid re-entered within this long (e.g. after a disconnect or /reload)
-- continues the same record.
local RESUME_SECONDS = 30 * 60
local KEEP_SECONDS = 60 * 24 * 3600
local MAX_RAIDS = 40
local MIN_QUALITY = 3 -- rare

local current, ticker

local function Region()
  if not GetCurrentRegionName then return nil end
  local ok, r = pcall(GetCurrentRegionName)
  if ok and type(r) == "string" and r ~= "" then return r end
end

local function Raids()
  if type(ns.db.raids) ~= "table" then ns.db.raids = {} end
  return ns.db.raids
end

-- Name, instance ID and player limit while inside a raid instance in a raid group.
local function RaidInstance()
  if not IsInRaid or not IsInRaid() or not GetInstanceInfo then return nil end
  local name, instanceType, _, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
  if instanceType ~= "raid" or not instanceID or instanceID == 0 then return nil end
  return instanceID, name, maxPlayers
end

local function Prune()
  local raids, cutoff = Raids(), time() - KEEP_SECONDS
  for key, r in pairs(raids) do
    if type(r) ~= "table" or (r.endedAt or 0) < cutoff then raids[key] = nil end
  end
  local list = {}
  for key, r in pairs(raids) do list[#list + 1] = { key = key, at = r.endedAt or 0 } end
  table.sort(list, function(a, b) return a.at > b.at end)
  for i = MAX_RAIDS + 1, #list do raids[list[i].key] = nil end
end

-- The record for the raid this character is in, continuing a recent one
-- of the same instance, or nil outside a raid.
local function Session()
  local instanceID, name, maxPlayers = RaidInstance()
  if not instanceID then
    current = nil
    return nil
  end
  local now = time()
  if current and current.instanceID == instanceID and now - (current.endedAt or 0) <= RESUME_SECONDS then
    return current
  end
  local best
  for _, r in pairs(Raids()) do
    if type(r) == "table" and r.instanceID == instanceID and now - (r.endedAt or 0) <= RESUME_SECONDS then
      if not best or r.endedAt > best.endedAt then best = r end
    end
  end
  if not best then
    best = { instanceID = instanceID, name = name, maxPlayers = maxPlayers, region = Region(),
             startedAt = now, endedAt = now, members = {}, loot = {}, encounters = {} }
    Raids()[instanceID .. ":" .. now] = best
    Prune()
  end
  current = best
  return best
end

function ns.SampleRaid()
  if not ns.db then return end
  local r = Session()
  if not r then return end
  local now = time()
  r.endedAt = now
  if type(r.members) ~= "table" then r.members = {} end
  for i = 1, GetNumGroupMembers() do
    local name, _, _, _, _, classFile, _, online = GetRaidRosterInfo(i)
    if name and online and name ~= UNKNOWNOBJECT then
      local m = r.members[name]
      if type(m) ~= "table" then
        m = { firstSeen = now }
        r.members[name] = m
      end
      m.class = classFile or m.class
      m.lastSeen = now
    end
  end
end

-- Loot messages, from the client's own format strings ("%s receives loot: %s.").
local function Pattern(format)
  if type(format) ~= "string" then return nil end
  local p = format:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

local LOOT_PATTERNS = {}
local function AddPattern(format, self, multiple)
  local p = Pattern(format)
  if p then LOOT_PATTERNS[#LOOT_PATTERNS + 1] = { pattern = p, self = self, multiple = multiple } end
end
-- Multiple-item forms first: they'd also match the single-item ones.
AddPattern(LOOT_ITEM_SELF_MULTIPLE, true, true)
AddPattern(LOOT_ITEM_MULTIPLE, false, true)
AddPattern(LOOT_ITEM_SELF, true, false)
AddPattern(LOOT_ITEM, false, false)

-- Returns who looted (a name, or nil for this character), the item link and count.
function ns.ParseLoot(msg)
  for _, p in ipairs(LOOT_PATTERNS) do
    local a, b, c = msg:match(p.pattern)
    if a then
      if p.self then return nil, a, tonumber(b) or 1 end
      return a, b, tonumber(c) or 1
    end
  end
end

local function OnLoot(_, msg)
  if not ns.db or type(msg) ~= "string" then return end
  local r = Session()
  if not r then return end
  local who, link, count = ns.ParseLoot(msg)
  if not link then return end
  local itemID = tonumber(link:match("item:(%d+)"))
  if not itemID then return end
  local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
  if not quality or quality < MIN_QUALITY then return end
  if not who then who = (ns.PlayerName()) end
  if not who then return end
  if type(r.loot) ~= "table" then r.loot = {} end
  r.loot[#r.loot + 1] = { at = time(), name = who, itemID = itemID, itemName = link:match("%[(.-)%]"), quality = quality, count = count }
  r.endedAt = time()
end

local function OnEncounterEnd(_, encounterID, encounterName, _, groupSize, success)
  if not ns.db then return end
  local r = Session()
  if not r or not encounterID then return end
  if type(r.encounters) ~= "table" then r.encounters = {} end
  r.encounters[#r.encounters + 1] = {
    id = encounterID, name = encounterName, success = success == 1 or success == true, size = groupSize, at = time(),
  }
  r.endedAt = time()
  -- Record who was there for the kill, not only the last minute's sample.
  ns.SampleRaid()
end

local function Update()
  if RaidInstance() then
    ns.SampleRaid()
    if not ticker then ticker = C_Timer.NewTicker(SAMPLE_SECONDS, ns.SampleRaid) end
  else
    current = nil
    if ticker then
      ticker:Cancel()
      ticker = nil
    end
  end
end

local function UpdateSoon() C_Timer.After(2, Update) end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", UpdateSoon)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", UpdateSoon)
ns.RegisterEvent("GROUP_ROSTER_UPDATE", UpdateSoon)
ns.RegisterEvent("CHAT_MSG_LOOT", OnLoot)
ns.RegisterEvent("ENCOUNTER_END", OnEncounterEnd)
ns.RegisterEvent("PLAYER_LOGOUT", function() if current then ns.SampleRaid() end end)
ns.RegisterEvent("PLAYER_LOGIN", function() if ns.db then Prune() end end)
