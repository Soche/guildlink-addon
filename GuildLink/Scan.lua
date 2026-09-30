local _, ns = ...

-- Profession ranks come from the spellbook API and are always available.
-- Recipes can only be read while the character's own profession window is
-- open, so each profession's recipe list is refreshed whenever it is opened.

local worldEntered = false
local reportedCounts = {}

function ns.UpdateProfessions()
  if not GetProfessions then return end
  local c = ns.CurrentCharacter()
  local seen = {}
  local indices = { GetProfessions() }
  -- GetProfessions returns prof1, prof2, archaeology, fishing, cooking; any
  -- of them may be nil, so iterate the fixed slots rather than ipairs.
  for slot = 1, 5 do
    local index = indices[slot]
    if index then
      local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
      if skillLine and name then
        seen[skillLine] = true
        local p = c.professions[skillLine]
        if type(p) ~= "table" then
          p = {}
          c.professions[skillLine] = p
        end
        p.name = name
        p.rank = rank
        p.maxRank = maxRank
      end
    end
  end
  -- Before PLAYER_ENTERING_WORLD the spellbook may not be loaded yet, so an
  -- empty result then does not mean the character unlearned everything.
  if worldEntered then
    for skillLine in pairs(c.professions) do
      if not seen[skillLine] then
        c.professions[skillLine] = nil
      end
    end
  end
  ns.Touch(c)
  if ns.RefreshUI then ns.RefreshUI() end
end

local function IsOwnTradeSkill(T)
  if not T.IsTradeSkillReady or not T.IsTradeSkillReady() then return false end
  if T.IsDataSourceChanging and T.IsDataSourceChanging() then return false end
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
  if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
  return true
end

function ns.ScanOpenTradeSkill()
  local T = C_TradeSkillUI
  if not T or not IsOwnTradeSkill(T) then return end

  local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  if not base or not base.professionID or base.professionID == 0 then return end

  local recipes, count = {}, 0
  for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(recipeID)
    if info and info.learned and not info.isDummyRecipe and not info.isRecraft
        and not info.isSalvageRecipe and not info.isGatheringRecipe then
      local itemID
      local ok, output = pcall(T.GetRecipeOutputItemData, recipeID)
      if ok and type(output) == "table" then
        itemID = output.itemID
      end
      recipes[recipeID] = { name = info.name, itemID = itemID }
      count = count + 1
    end
  end

  -- The list is briefly empty while the window is still loading; do not wipe
  -- a previously scanned profession because of that.
  if count == 0 then return end

  local c = ns.CurrentCharacter()
  local p = c.professions[base.professionID]
  if type(p) ~= "table" then
    p = {}
    c.professions[base.professionID] = p
  end
  p.name = base.professionName or p.name
  p.rank = base.skillLevel or p.rank
  p.maxRank = base.maxSkillLevel or p.maxRank
  p.recipes = recipes
  p.scannedAt = time()
  ns.Touch(c)

  if reportedCounts[base.professionID] ~= count then
    reportedCounts[base.professionID] = count
    ns.Print(("Recorded %d %s recipes."):format(count, p.name or "profession"))
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

-- TRADE_SKILL_LIST_UPDATE fires in bursts; scan once things settle.
local pending = false
local function ScheduleScan()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    ns.ScanOpenTradeSkill()
  end)
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  worldEntered = true
  ns.UpdateProfessions()
end)
ns.RegisterEvent("SKILL_LINES_CHANGED", function() ns.UpdateProfessions() end)
ns.RegisterEvent("TRADE_SKILL_SHOW", ScheduleScan)
ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE", ScheduleScan)
ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", ScheduleScan)
ns.RegisterEvent("NEW_RECIPE_LEARNED", ScheduleScan)
