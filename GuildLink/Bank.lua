local _, ns = ...

-- Guild bank contents can only be read while the guild vault is open, and
-- only for tabs this character's rank may view. When the vault opens, each
-- viewable tab is requested from the server in turn and recorded once its
-- data arrives. Saved per guild in GuildLinkDB.guildBanks; the bot keeps the
-- newest copy of each tab across everyone's uploads.

local SLOTS_PER_TAB = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local TAB_TIMEOUT = 3

local queue, waitingTab, timeoutTimer, vaultOpen = {}, nil, nil, false

local function ItemFromLink(link)
  local itemID = tonumber(link:match("item:(%d+)"))
  local name = link:match("%[(.-)%]")
  return itemID, name
end

local function CurrentBank()
  local guildName = GetGuildInfo("player")
  if not guildName or not ns.db then return nil end
  if type(ns.db.guildBanks) ~= "table" then
    ns.db.guildBanks = {}
  end
  local bank = ns.db.guildBanks[guildName]
  if type(bank) ~= "table" then
    bank = { guild = guildName, tabs = {} }
    ns.db.guildBanks[guildName] = bank
  end
  if type(bank.tabs) ~= "table" then bank.tabs = {} end
  if GetCurrentRegionName then
    local ok, region = pcall(GetCurrentRegionName)
    if ok and type(region) == "string" and region ~= "" then bank.region = region end
  end
  return bank
end

local function RecordTab(tab)
  local bank = CurrentBank()
  if not bank then return end
  local name, icon, isViewable = GetGuildBankTabInfo(tab)
  if not isViewable then return end
  local items = {}
  for slot = 1, SLOTS_PER_TAB do
    local link = GetGuildBankItemLink(tab, slot)
    if link then
      local _, count, _, _, quality = GetGuildBankItemInfo(tab, slot)
      local itemID, itemName = ItemFromLink(link)
      if itemID then
        items[#items + 1] = { slot = slot, itemID = itemID, name = itemName, count = count or 1, quality = quality }
      end
    end
  end
  bank.tabs[tab] = { name = name, icon = icon, scannedAt = time(), items = items }
  bank.numTabs = GetNumGuildBankTabs()
  bank.scannedAt = time()
end

local function NextTab()
  if timeoutTimer then
    timeoutTimer:Cancel()
    timeoutTimer = nil
  end
  waitingTab = table.remove(queue, 1)
  if not waitingTab or not vaultOpen then
    waitingTab = nil
    return
  end
  QueryGuildBankTab(waitingTab)
  -- If the server doesn't answer (e.g. throttled), move on.
  timeoutTimer = C_Timer.NewTimer(TAB_TIMEOUT, NextTab)
end

local function OnVaultOpened()
  -- Both "opened" events may fire for one visit.
  if vaultOpen or not ns.db or not GetNumGuildBankTabs then return end
  vaultOpen = true
  local bank = CurrentBank()
  if not bank then return end
  if GetGuildBankMoney then bank.money = GetGuildBankMoney() end
  queue = {}
  for tab = 1, GetNumGuildBankTabs() do
    local _, _, isViewable = GetGuildBankTabInfo(tab)
    if isViewable then queue[#queue + 1] = tab end
  end
  local n = #queue
  NextTab()
  if n > 0 then ns.Print(("Reading %d guild bank tab%s for Discord."):format(n, n == 1 and "" or "s")) end
end

local function OnVaultClosed()
  vaultOpen = false
  queue = {}
end

ns.RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function()
  if waitingTab then
    RecordTab(waitingTab)
    NextTab()
  end
end)

ns.RegisterEvent("GUILDBANK_UPDATE_MONEY", function()
  local bank = vaultOpen and CurrentBank()
  if bank and GetGuildBankMoney then bank.money = GetGuildBankMoney() end
end)

-- Retail-based clients announce the vault through the interaction manager;
-- older ones through GUILDBANKFRAME_OPENED. Either may be absent.
local GUILD_BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
ns.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
  if GUILD_BANKER and kind == GUILD_BANKER then OnVaultOpened() end
end)
ns.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  if GUILD_BANKER and kind == GUILD_BANKER then OnVaultClosed() end
end)
ns.RegisterEvent("GUILDBANKFRAME_OPENED", OnVaultOpened)
ns.RegisterEvent("GUILDBANKFRAME_CLOSED", OnVaultClosed)
