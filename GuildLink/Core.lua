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

function ns.CharacterKey()
  local name = UnitName("player")
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
  if not realm or realm == "" then
    realm = GetRealmName and GetRealmName() or ""
  end
  return name .. "-" .. (realm or ""), name, realm or ""
end

-- Returns the saved entry for the logged-in character, creating it if needed.
function ns.CurrentCharacter()
  local key, name, realm = ns.CharacterKey()
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

function ns.Touch(c)
  c.updatedAt = time()
  ns.db.updatedAt = c.updatedAt
end

function ns.UpdateBasics()
  local c = ns.CurrentCharacter()
  local className, classFile = UnitClass("player")
  c.class = classFile
  c.className = className
  c.level = UnitLevel("player")
  c.race = select(2, UnitRace("player"))
  c.faction = UnitFactionGroup("player")

  if IsInGuild() then
    local guildName, rankName = GetGuildInfo("player")
    -- GetGuildInfo returns nil for a moment after login even when the
    -- character is in a guild; keep the last known value until it loads.
    if guildName then
      c.guild = guildName
      c.guildRank = rankName
    end
  else
    c.guild = nil
    c.guildRank = nil
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
-- know, so every registration is guarded.
function ns.RegisterEvent(event, fn)
  if pcall(frame.RegisterEvent, frame, event) then
    handlers[event] = fn
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if fn then fn(event, ...) end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then return end
  EnsureDB()
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
  if not ns.db then EnsureDB() end
  ns.UpdateBasics()
  if not ns.db.discordId then
    ns.Print("No Discord user ID set. Type /guildlink to add it.")
  end
end)

local function OnBasicsChanged() ns.UpdateBasics() end
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
