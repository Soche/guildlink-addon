# GuildLink addon

A World of Warcraft: Forever addon (Interface 16001). It records each of your characters' name, realm, guild, class, level, professions and known recipes, plus your Discord user ID, into the `GuildLinkDB` SavedVariables. The GuildLink companion app uploads that data to the GuildLink Discord bot.

## Install

The easiest way is the GuildLink companion app. It installs the addon and keeps it up to date, so you don't download it yourself.

To install by hand, get `GuildLink-<version>.zip` from [Releases](https://github.com/Soche/guildlink-addon/releases). Unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/`. That is the Forever beta's folder; the release client may use another one.

## Releasing

Bump `## Version:` in `GuildLink.toc`, commit, and push a matching tag (`v0.6.0` for version `0.6.0`). The workflow refuses mismatched tags, zips the addon, and publishes it with `SHA256SUMS`. Companions pick it up at their next check, within about six hours.

## Use

1. In Discord, run `/link` in your server. It gives you the companion app's server address and token.
2. In game, type `/guildlink` (or `/glink`) and paste your **Discord user ID**. To copy it, turn on Discord Settings > Advanced > Developer Mode, then right-click your name and choose Copy User ID.
3. Open each profession window once so its recipes are recorded. They are re-read every time you open the window.
4. Opening the guild vault records the bank tabs you can see, for `/bank` in Discord. Guild Master: open Guild Control's bank tab permissions and click through the ranks once, so Discord gets the exact per-rank settings.
5. Dungeons and raids you enter are recorded automatically, so the bot learns their exact names and sizes.
6. Log out or `/reload`. The game writes the data to disk then, and the companion uploads it.

Other commands: `/guildlink id <id>` and `/guildlink status`.

## About the Forever beta's SavedVariables bug

The beta client writes SavedVariables on logout but does not load them at the next start. Without a workaround, every session starts empty. The companion app works around it by copying your last saved data into `GuildLink/Seed.lua`, which the addon runs before anything else (see `GuildLink.toc`). If you don't use the companion, only the current session's data gets saved, and you have to enter your Discord ID again each session. When Blizzard fixes the bug, the real SavedVariables load takes over and `Seed.lua` stops mattering.

## Saved data

```lua
GuildLinkDB = {
  schema = 1,
  discordId = "123456789012345678",
  characters = {
    ["Thrall-Realm"] = {
      name, realm, region, class, className, race, faction, level, guild, guildRank, guildRankIndex, updatedAt,
      professions = {
        [171] = { name = "Alchemy", rank = 50, maxRank = 75, scannedAt = 1790000000,
                  recipes = { [2330] = { name = "Minor Healing Potion", itemID = 118,
                                         classID = 0, subclassID = 1, equipLoc = nil,   -- C_Item.GetItemInfoInstant
                                         enchant = nil, category = "Potions",           -- profession window category
                                         reagents = { { itemID = 2447, count = 1, name = "Peacebloom" } } } } },  -- basic reagents only
      },
    },
  },
  guildRosters = {  -- newest in-game roster per guild, for Discord rank roles (complete rosters only)
    ["Nobility"] = { guild = "Nobility", region = "EU", scannedAt = 1790000000,
                     ranks = { [0] = "Guild Master", [1] = "Officer" },
                     members = { { name = "Soche-Lightbringer", rankIndex = 1 } } },
  },
  guildBanks = {  -- what this account saw at the guild vault, per guild; tabs the character may view
    ["Nobility"] = { guild = "Nobility", region = "EU", scannedAt = 1790000000, money = 1234567, numTabs = 3,
                     observed = { [2] = { at = 1790000000, tabs = { [1] = true, [3] = false } } },    -- per rank: tabs it can view
                     settings = { [1] = { at = 1790000000, tabs = { [1] = true, [3] = false } } },     -- per rank, read while the GM browses Guild Control
                     tabs = { [1] = { name = "Mats", scannedAt = 1790000000,
                                      items = { { slot = 1, itemID = 2840, name = "Copper Bar", count = 20, quality = 1 } } } } },
  },
  instances = {   -- dungeons and raids entered, from GetInstanceInfo()
    [2050] = { name = "Hyjal Summit", kind = "raid", maxPlayers = 20, seenAt = 1790000000 },
  },
}
```

Recipes are only readable while your own profession window is open. Linked, guild and NPC crafting windows are ignored.
