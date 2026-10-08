local _, ns = ...

-- Each character's items, for looking things up across your characters in
-- Discord: bags (any time), the bank (only readable while it's open) and
-- equipped gear. Stacks of an item are added up per place:
--   characters[key].inventory = { bags = { scannedAt, items = { [itemID] = { name, count, quality } } }, bank = ..., equipped = ... }
-- An account-wide bank, if the client has one, goes to GuildLinkDB.accountBank.

local C = C_Container
local BagIndex = Enum and Enum.BagIndex or {}
local NUM_BAGS = (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or NUM_BAG_SLOTS or 4

-- Carried bags: the backpack, the bag slots, and a reagent bag if the client has one.
local function CarriedBags()
  local ids = {}
  for bag = 0, NUM_BAGS do ids[#ids + 1] = bag end
  if BagIndex.ReagentBag then ids[#ids + 1] = BagIndex.ReagentBag end
  return ids
end

-- Bank containers: the bank itself, bank bags or character bank tabs, and a
-- reagent bank. Taken from Enum.BagIndex where the client names them; else
-- the classic numbering (-1 and the seven bags after the carried ones).
local function BankContainers()
  local character, account, seen = {}, {}, {}
  local function add(list, id)
    if type(id) == "number" and not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  add(character, BagIndex.Bank or -1)
  for name, id in pairs(BagIndex) do
    if name:match("^BankBag_") or name:match("^CharacterBankTab_") or name == "Reagentbank" then add(character, id) end
    if name:match("^AccountBankTab_") then add(account, id) end
  end
  if not BagIndex.BankBag_1 and not BagIndex.CharacterBankTab_1 then
    for bag = NUM_BAGS + 1, NUM_BAGS + 7 do add(character, bag) end
  end
  return character, account
end

local function ItemName(info, itemID)
  local fromLink = info.hyperlink and info.hyperlink:match("%[(.-)%]")
  return fromLink or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
end

local function ScanContainers(ids)
  local items = {}
  for _, bag in ipairs(ids) do
    local ok, slots = pcall(C.GetContainerNumSlots, bag)
    for slot = 1, (ok and slots or 0) do
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local e = items[info.itemID]
        if not e then
          e = { name = ItemName(info, info.itemID), count = 0, quality = info.quality }
          items[info.itemID] = e
        end
        e.count = e.count + (info.stackCount or 1)
      end
    end
  end
  return items
end

local function ScanEquipped()
  local items = {}
  for slot = 1, 19 do
    local itemID = GetInventoryItemID("player", slot)
    if itemID then
      local link = GetInventoryItemLink("player", slot)
      local e = items[itemID] or { name = link and link:match("%[(.-)%]"), count = 0, quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID) }
      e.count = e.count + 1
      items[itemID] = e
    end
  end
  return items
end

local function Store(place, items)
  local c = ns.CurrentCharacter()
  if not c then return end
  if type(c.inventory) ~= "table" then c.inventory = {} end
  c.inventory[place] = { scannedAt = time(), items = items }
end

function ns.ScanBags()
  if not C or not C.GetContainerNumSlots then return end
  Store("bags", ScanContainers(CarriedBags()))
end

function ns.ScanEquipped()
  if not GetInventoryItemID then return end
  Store("equipped", ScanEquipped())
end

local bankOpen = false

function ns.ScanBank()
  if not bankOpen or not C or not C.GetContainerNumSlots then return end
  local character, account = BankContainers()
  Store("bank", ScanContainers(character))
  if #account > 0 and ns.db then
    local items = ScanContainers(account)
    if next(items) then ns.db.accountBank = { scannedAt = time(), items = items } end
  end
end

-- Bag events come in bursts; scan once things settle.
local pending = {}
local function Soon(fn, delay)
  if pending[fn] then return end
  pending[fn] = true
  C_Timer.After(delay or 1, function()
    pending[fn] = nil
    fn()
  end)
end

local function OnBankOpened()
  bankOpen = true
  -- The bank's contents arrive just after the window opens.
  Soon(ns.ScanBank, 0.5)
end
local function OnBankClosed()
  bankOpen = false
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  Soon(ns.ScanBags, 3)
  Soon(ns.ScanEquipped, 3)
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
  Soon(ns.ScanBags)
  if bankOpen then Soon(ns.ScanBank) end
end)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() Soon(ns.ScanEquipped) end)
ns.RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() Soon(ns.ScanBank) end)
-- SavedVariables are written at logout; make sure they're current.
ns.RegisterEvent("PLAYER_LOGOUT", function()
  ns.ScanBags()
  ns.ScanEquipped()
end)

local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
ns.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
  if BANKER and kind == BANKER then OnBankOpened() end
end)
ns.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  if BANKER and kind == BANKER then OnBankClosed() end
end)
ns.RegisterEvent("BANKFRAME_OPENED", OnBankOpened)
ns.RegisterEvent("BANKFRAME_CLOSED", OnBankClosed)
