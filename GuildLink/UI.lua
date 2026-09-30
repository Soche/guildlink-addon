local _, ns = ...

local ui

local function CreateLabel(parent, template, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

local function Build()
  local f = CreateFrame("Frame", "GuildLinkFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(380, 300)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  -- Close with Escape.
  tinsert(UISpecialFrames, f:GetName())

  local title = f.TitleText or CreateLabel(f, "GameFontHighlight")
  title:SetText("GuildLink")
  if not f.TitleText then title:SetPoint("TOP", 0, -5) end

  local label = CreateLabel(f, "GameFontNormal", "Discord user ID")
  label:SetPoint("TOPLEFT", 16, -36)

  local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  edit:SetSize(220, 22)
  edit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -6)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(20)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.edit = edit

  local save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  save:SetSize(70, 22)
  save:SetPoint("LEFT", edit, "RIGHT", 8, 0)
  save:SetText("Save")
  save:SetScript("OnClick", function()
    local value = strtrim(edit:GetText() or "")
    if ns.SetDiscordId(value) then edit:ClearFocus() end
  end)
  edit:SetScript("OnEnterPressed", function() save:Click() end)

  local help = CreateLabel(f, "GameFontHighlightSmall",
    "In Discord, turn on Settings > Advanced > Developer Mode, then right-click your name and choose Copy User ID. " ..
    "It must match the account you used for /link in Discord.")
  help:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -6, -8)
  help:SetWidth(348)

  local header = CreateLabel(f, "GameFontNormal", "This character")
  header:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -14)

  local details = CreateLabel(f, "GameFontHighlightSmall")
  details:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
  details:SetWidth(348)
  details:SetJustifyV("TOP")
  f.details = details

  local footer = CreateLabel(f, "GameFontDisableSmall",
    "Open each profession window to record its recipes. Data is written to disk on logout or /reload; the companion app uploads it from there.")
  footer:SetPoint("BOTTOMLEFT", 16, 14)
  footer:SetWidth(348)

  f:SetScript("OnShow", function() ns.RefreshUI() end)
  return f
end

function ns.RefreshUI()
  if not ui or not ui:IsShown() or not ns.db then return end
  if not ui.edit:HasFocus() then
    ui.edit:SetText(ns.db.discordId or "")
  end

  local c = ns.CurrentCharacter()
  local lines = {}
  lines[#lines + 1] = ("%s, level %s %s"):format(c.name or "?", tostring(c.level or "?"), c.className or c.class or "")
  lines[#lines + 1] = "Guild: " .. (c.guild or "none")

  local profs = {}
  for _, p in pairs(c.professions) do profs[#profs + 1] = p end
  table.sort(profs, function(a, b) return (a.name or "") < (b.name or "") end)
  if #profs == 0 then
    lines[#lines + 1] = "No professions."
  end
  for _, p in ipairs(profs) do
    local n = 0
    for _ in pairs(p.recipes or {}) do n = n + 1 end
    local recipeText = p.scannedAt and (n .. " recipes") or "window not opened yet"
    lines[#lines + 1] = ("%s %s/%s: %s"):format(p.name or "?", tostring(p.rank or 0), tostring(p.maxRank or 0), recipeText)
  end

  local total = 0
  for _ in pairs(ns.db.characters) do total = total + 1 end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("Characters recorded on this account: %d"):format(total)
  ui.details:SetText(table.concat(lines, "\n"))
end

function ns.ToggleUI()
  if not ns.db then return end
  ui = ui or Build()
  ui:SetShown(not ui:IsShown())
end
