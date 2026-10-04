local _, ns = ...

-- Snapshots the in-game guild roster (every member's name and rank) so the
-- bot can keep Discord roles in line with guild ranks, including for members
-- who demote, leave, or never upload themselves. Saved per guild in
-- GuildLinkDB.guildRosters; the newest snapshot from any member wins.

local function RankNames()
  local ranks = {}
  if GuildControlGetNumRanks and GuildControlGetRankName then
    for i = 1, GuildControlGetNumRanks() do
      -- GuildControlGetRankName is 1-based; roster rank indexes are 0-based.
      ranks[i - 1] = GuildControlGetRankName(i)
    end
  end
  return ranks
end

function ns.ScanGuildRoster()
  if not ns.db or not IsInGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return end
  local guildName = GetGuildInfo("player")
  local total = GetNumGuildMembers()
  if not guildName or not total or total == 0 then return end

  local members = {}
  for i = 1, total do
    local name, _, rankIndex = GetGuildRosterInfo(i)
    if name and rankIndex then
      members[#members + 1] = { name = name, rankIndex = rankIndex }
    end
  end
  -- Only keep a complete roster: a partial one (still loading, or only
  -- online members) would look like everyone else left the guild.
  if #members ~= total then return end

  if type(ns.db.guildRosters) ~= "table" then
    ns.db.guildRosters = {}
  end
  local region
  if GetCurrentRegionName then
    local ok, r = pcall(GetCurrentRegionName)
    if ok and type(r) == "string" and r ~= "" then region = r end
  end
  ns.db.guildRosters[guildName] = {
    guild = guildName,
    region = region,
    scannedAt = time(),
    ranks = RankNames(),
    members = members,
  }
end

-- GUILD_ROSTER_UPDATE fires often; scan once it settles.
local pending = false
local function ScheduleScan()
  if pending then return end
  pending = true
  C_Timer.After(3, function()
    pending = false
    ns.ScanGuildRoster()
  end)
end

ns.RegisterEvent("GUILD_ROSTER_UPDATE", ScheduleScan)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  -- Ask the server for a fresh roster; the update event follows.
  if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
    pcall(C_GuildInfo.GuildRoster)
  end
end)
