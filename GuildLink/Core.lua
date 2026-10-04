local ADDON_NAME, ns = ...

ns.SCHEMA = 1
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local PREFIX = "|cff33ccffGuildLink|r: "

function ns.Print(msg)
  print(PREFIX .. tostring(msg))
end

-- Discord snowflakes are 17-20 digit integers. Kept as strings because Lua
-- numbers are doubles and would lose precision.
function ns.IsValidDiscordId(id)
  return type(id) == "string" and id:match("^%d+$") ~= nil and #id >= 17 and #id <= 20
end

local function EnsureDB()
  -- GuildLinkDB may already be set by the real SavedVariables load, or by
  -- Seed.lua (written by the companion app) when the client skips that load.
  if type(GuildLinkDB) ~= "table" then
    GuildLinkDB = {}
  end
  local db = GuildLinkDB
  db.schema = ns.SCHEMA
  if type(db.characters) ~= "table" then
    db.characters = {}
  end
  if db.discordId ~= nil and not ns.IsValidDiscordId(db.discordId) then
    db.discordId = nil
  end
  ns.db = db
end

local function IsPlaceholderName(name)
  return not name or name == "" or name == UNKNOWNOBJECT or name == UNKNOWN or name == "Unknown"
end

local function PlayerRealm()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
  if not realm or realm == "" then
    realm = GetRealmName and GetRealmName() or ""
  end
  return realm or ""
end

-- Forever characters have a first name and a surname, and the client
-- returns the surname where retail returns the realm: UnitFullName("player")
-- gives "First", "Surname". GetUnitName("player", true) gives the full
-- "First Surname". Returns the full name and the first name alone.
function ns.PlayerName()
  local first, second = UnitFullName("player")
  if IsPlaceholderName(first) then return nil end
  local full = GetUnitName and GetUnitName("player", true)
  if full and full:find(" ", 1, true) and not IsPlaceholderName(full) then
    return full, first
  end
  if second and second ~= "" and second ~= PlayerRealm() then
    return first .. " " .. second, first
  end
  return first, first
end

function ns.CharacterKey()
  local name, first = ns.PlayerName()
  if not name then return nil end
  local realm = PlayerRealm()
  return name .. "-" .. realm, name, realm, first
end

-- Returns the saved entry for the logged-in character, creating it if
-- needed, or nil while the character's name is not loaded yet (the client
-- reports "Unknown" for a moment around login).
function ns.CurrentCharacter()
  if not ns.db or not IsLoggedIn() then return nil end
  local key, name, realm = ns.CharacterKey()
  if not key then return nil end
  local c = ns.db.characters[key]
  if type(c) ~= "table" then
    c = {}
    ns.db.characters[key] = c
  end
  c.name = name
  c.realm = realm
  if type(c.professions) ~= "table" then
    c.professions = {}
  end
  return c
end

-- Drops entries saved by older versions: ones recorded under the "Unknown"
-- placeholder, and this character's entry saved under its first name only.
-- Profession data from the old entry is kept if the new one has none.
function ns.PruneLegacyEntries()
  local key, name, realm, first = ns.CharacterKey()
  if not key then return end
  local current = ns.CurrentCharacter()
  if not current then return end
  for k, c in pairs(ns.db.characters) do
    if type(c) ~= "table" or IsPlaceholderName(c.name) then
      ns.db.characters[k] = nil
    elseif k ~= key and name ~= first and c.name == first and (c.realm or "") == realm then
      if next(current.professions) == nil and type(c.professions) == "table" then
        current.professions = c.professions
      end
      ns.db.characters[k] = nil
    end
  end
end

function ns.Touch(c)
  c.updatedAt = time()
  ns.db.updatedAt = c.updatedAt
end

function ns.UpdateBasics()
  local c = ns.CurrentCharacter()
  if not c then return end
  local className, classFile = UnitClass("player")
  c.class = classFile
  c.className = className
  c.level = UnitLevel("player")
  c.race = select(2, UnitRace("player"))
  c.faction = UnitFactionGroup("player")
  -- Forever names are unique per region ("EU", "US", ...), not worldwide.
  if GetCurrentRegionName then
    local ok, region = pcall(GetCurrentRegionName)
    if ok and type(region) == "string" and region ~= "" then
      c.region = region
    end
  end

  if IsInGuild() then
    local guildName, rankName, rankIndex = GetGuildInfo("player")
    -- GetGuildInfo returns nil for a moment after login even when the
    -- character is in a guild; keep the last known value until it loads.
    if guildName then
      c.guild = guildName
      c.guildRank = rankName
      -- 0 is the Guild Master; higher numbers are lower ranks.
      c.guildRankIndex = rankIndex
    end
  else
    c.guild = nil
    c.guildRank = nil
    c.guildRankIndex = nil
  end
  ns.Touch(c)
  if ns.RefreshUI then ns.RefreshUI() end
end

function ns.SetDiscordId(id)
  if id == nil or id == "" then
    ns.db.discordId = nil
    ns.Print("Discord user ID cleared.")
  elseif ns.IsValidDiscordId(id) then
    ns.db.discordId = id
    ns.Print("Discord user ID saved. It is written to disk when you log out or /reload.")
  else
    ns.Print("That does not look like a Discord user ID (17-20 digits).")
    return false
  end
  ns.db.updatedAt = time()
  if ns.RefreshUI then ns.RefreshUI() end
  return true
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame

local handlers = {}
ns.handlers = handlers

-- The Forever client raises an error when registering an event it does not
-- know, so every registration is guarded. An event may have several handlers.
function ns.RegisterEvent(event, fn)
  if handlers[event] then
    table.insert(handlers[event], fn)
  elseif pcall(frame.RegisterEvent, frame, event) then
    handlers[event] = { fn }
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    fn(event, ...)
  end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then return end
  EnsureDB()
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
  if not ns.db then EnsureDB() end
  ns.PruneLegacyEntries()
  ns.UpdateBasics()
  if not ns.db.discordId then
    ns.Print("No Discord user ID set. Type /guildlink to add it.")
  end
end)

local function OnBasicsChanged() ns.UpdateBasics() end
-- The name can still be "Unknown" at PLAYER_LOGIN; retry once it has loaded.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  ns.PruneLegacyEntries()
  ns.UpdateBasics()
end)
ns.RegisterEvent("PLAYER_LEVEL_UP", function()
  -- UnitLevel lags behind PLAYER_LEVEL_UP by a frame.
  C_Timer.After(1, OnBasicsChanged)
end)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", OnBasicsChanged)
ns.RegisterEvent("GUILD_ROSTER_UPDATE", OnBasicsChanged)

SLASH_GUILDLINK1 = "/guildlink"
SLASH_GUILDLINK2 = "/glink"
SlashCmdList.GUILDLINK = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "id" then
    ns.SetDiscordId(rest)
  elseif cmd == "status" then
    local n = 0
    for _ in pairs(ns.db.characters) do n = n + 1 end
    ns.Print(("Discord ID: %s. Characters recorded: %d."):format(ns.db.discordId or "not set", n))
  else
    ns.ToggleUI()
  end
end

function GuildLink_OnAddonCompartmentClick()
  ns.ToggleUI()
end
