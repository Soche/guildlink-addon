local _, ns = ...

-- Offers the guild's upcoming Discord events for the game's calendar. The
-- companion app writes them into Events.lua (GuildLinkEvents), which the
-- game reads at login. C_Calendar.AddEvent only works from a click, so each
-- event gets an Add button instead of being added on its own.

local MAX_ROWS = 8
local TITLE_MAX = 31 -- bytes the calendar's title field takes
local DESCRIPTION_MAX = 250
local ROLE = { tank = "tank", healer = "healer", dps = "DPS", attendee = "attending" }

local ui

local function Available()
  return C_Calendar and C_Calendar.AddEvent and C_Calendar.CreatePlayerEvent and C_Calendar.EventSetTitle
    and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and type(GuildLinkEvents) == "table"
end

-- What this account did with each event, by event ID: added (its start time
-- then), skipped, and seen (start time when last offered at login).
local function State()
  local cal = ns.db.calendar
  if type(cal) ~= "table" then
    cal = {}
    ns.db.calendar = cal
  end
  for _, k in ipairs({ "added", "skipped", "seen" }) do
    if type(cal[k]) ~= "table" then cal[k] = {} end
  end
  return cal
end

local function Upcoming()
  local now, out = time(), {}
  for _, e in ipairs(GuildLinkEvents or {}) do
    if type(e) == "table" and type(e.id) == "number" and type(e.startsAt) == "number" and e.startsAt > now then
      out[#out + 1] = e
    end
  end
  return out
end

-- Forget events that are no longer coming up.
local function Prune(events)
  local current = {}
  for _, e in ipairs(events) do current[e.id] = true end
  local cal = State()
  for _, k in ipairs({ "added", "skipped", "seen" }) do
    for id in pairs(cal[k]) do
      if not current[id] then cal[k][id] = nil end
    end
  end
end

-- The calendar runs on server time. The difference between the server's
-- clock and this computer's, to the nearest quarter hour.
local function ServerOffset()
  local t = C_DateAndTime.GetCurrentCalendarTime()
  local wall = time({ year = t.year, month = t.month, day = t.monthDay, hour = t.hour, min = t.minute, sec = 0 })
  return math.floor((wall - time()) / 900 + 0.5) * 900
end

local function ServerDate(unix)
  return date("*t", unix + ServerOffset())
end

-- Cuts to n bytes without leaving half a UTF-8 character.
local function Truncate(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", ""))
end

local function CalendarTitle(e)
  return Truncate(e.title, TITLE_MAX)
end

local function Description(e, forGuild)
  local parts = {}
  if e.description and e.description ~= "" then parts[#parts + 1] = e.description end
  if e.instance and e.instance ~= "" and e.instance ~= e.title then parts[#parts + 1] = e.instance end
  if not forGuild and e.signup then
    parts[#parts + 1] = "Signed up as " .. (ROLE[e.signup] or e.signup) .. (e.signupStatus == "bench" and " (bench)" or "")
  end
  parts[#parts + 1] = "Sign up in Discord. Added by GuildLink."
  return Truncate(table.concat(parts, "\n"), DESCRIPTION_MAX)
end

-- Whether the calendar already has an event with this title at this time,
-- e.g. a guild announcement an officer added.
local function InCalendar(e)
  if not C_Calendar.GetNumDayEvents or not C_Calendar.GetDayEvent then return false end
  local when = ServerDate(e.startsAt)
  local now = C_DateAndTime.GetCurrentCalendarTime()
  local offset = (when.year - now.year) * 12 + (when.month - now.month)
  local ok, n = pcall(C_Calendar.GetNumDayEvents, offset, when.day)
  if not ok or type(n) ~= "number" then return false end
  local title = CalendarTitle(e)
  for i = 1, n do
    local ok2, ev = pcall(C_Calendar.GetDayEvent, offset, when.day, i)
    local st = ok2 and type(ev) == "table" and ev.startTime
    if st and ev.title == title and st.hour == when.hour and st.minute == when.min then
      return true
    end
  end
  return false
end

-- "added", "moved" (added, then its time changed in Discord), "skipped" or "new".
local function StatusOf(e)
  local cal = State()
  if cal.added[e.id] == e.startsAt or InCalendar(e) then return "added" end
  if cal.added[e.id] then return "moved" end
  if cal.skipped[e.id] then return "skipped" end
  return "new"
end

local function CanAddForGuild()
  if not IsInGuild() or type(CanEditGuildEvent) ~= "function" then return false end
  local ok, can = pcall(CanEditGuildEvent)
  return ok and can and C_Calendar.CreateGuildAnnouncementEvent ~= nil
end

-- Reading day events needs the calendar on the current month; leave it alone
-- while the player has the calendar open.
local function PointCalendarAtNow()
  if CalendarFrame and CalendarFrame:IsShown() then return end
  if C_Calendar.SetAbsMonth then
    local now = C_DateAndTime.GetCurrentCalendarTime()
    pcall(C_Calendar.SetAbsMonth, now.month, now.year)
  end
end

local function Add(e, forGuild)
  local ok, err = pcall(function()
    local when = ServerDate(e.startsAt)
    if forGuild then
      C_Calendar.CreateGuildAnnouncementEvent()
    else
      C_Calendar.CreatePlayerEvent()
    end
    C_Calendar.EventSetTitle(CalendarTitle(e))
    C_Calendar.EventSetDescription(Description(e, forGuild))
    -- "Other": raid and dungeon events want an instance picture the game
    -- chooses from its own list.
    C_Calendar.EventSetType(Enum.CalendarEventType and Enum.CalendarEventType.Other or 4)
    C_Calendar.EventSetDate(when.month, when.day, when.year)
    C_Calendar.EventSetTime(when.hour, when.min)
    C_Calendar.AddEvent()
  end)
  if not ok then
    ns.Print("Couldn't add " .. tostring(e.title) .. " to the calendar: " .. tostring(err))
    return
  end
  local cal = State()
  cal.added[e.id] = e.startsAt
  cal.skipped[e.id] = nil
  ns.Print(("Added %s to %s calendar."):format(tostring(e.title), forGuild and "the guild's" or "your"))
end

local function RowText(e, status)
  local text = date("%a %d %b %H:%M", e.startsAt + ServerOffset()) .. "  " .. tostring(e.title)
  if e.signup then
    text = text .. " |cff999999(" .. (ROLE[e.signup] or e.signup) .. (e.signupStatus == "bench" and ", bench" or "") .. ")|r"
  end
  if status == "added" then
    text = text .. "  |cff33ff33In calendar|r"
  elseif status == "moved" then
    text = text .. "  |cffffcc00New time|r"
  elseif status == "skipped" then
    text = text .. "  |cff999999Skipped|r"
  end
  return text
end

local function CreateRow(parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(468, 24)
  row:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 26)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", 0, 0)
  row.text:SetWidth(270)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)

  local function Button(label, width)
    local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(label)
    return b
  end
  row.skip = Button("Skip", 50)
  row.skip:SetPoint("RIGHT", 0, 0)
  row.guild = Button("For guild", 74)
  row.guild:SetPoint("RIGHT", row.skip, "LEFT", -4, 0)
  row.add = Button("Add", 56)
  row.add:SetPoint("RIGHT", row.guild, "LEFT", -4, 0)

  row.add:SetScript("OnClick", function() Add(row.event, false); ns.RefreshEvents() end)
  row.guild:SetScript("OnClick", function() Add(row.event, true); ns.RefreshEvents() end)
  row.skip:SetScript("OnClick", function()
    State().skipped[row.event.id] = true
    ns.RefreshEvents()
  end)
  return row
end

local function Build()
  local f = CreateFrame("Frame", "GuildLinkEventsFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(496, 92 + MAX_ROWS * 26)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  tinsert(UISpecialFrames, f:GetName())

  local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetText("GuildLink: events from Discord")
  if not f.TitleText then title:SetPoint("TOP", 0, -5) end

  f.rows = {}
  for i = 1, MAX_ROWS do f.rows[i] = CreateRow(f, i) end

  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.empty:SetPoint("TOPLEFT", 16, -40)
  f.empty:SetText("No upcoming events.")

  f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMLEFT", 16, 14)
  f.footer:SetWidth(464)
  f.footer:SetJustifyH("LEFT")

  f:SetScript("OnShow", function() ns.RefreshEvents() end)
  return f
end

function ns.RefreshEvents()
  if not ui or not ui:IsShown() then return end
  PointCalendarAtNow()
  local events = Upcoming()
  local forGuild = CanAddForGuild()
  for i, row in ipairs(ui.rows) do
    local e = events[i]
    row:SetShown(e ~= nil)
    if e then
      local status = StatusOf(e)
      row.event = e
      row.text:SetText(RowText(e, status))
      row.add:SetEnabled(status ~= "added")
      row.guild:SetShown(forGuild)
      row.add:ClearAllPoints()
      row.add:SetPoint("RIGHT", forGuild and row.guild or row.skip, "LEFT", -4, 0)
      row.guild:SetEnabled(status ~= "added")
      row.skip:SetShown(status == "new" or status == "moved")
    end
  end
  ui.empty:SetShown(#events == 0)
  local more = #events > MAX_ROWS and ("%d more in Discord. "):format(#events - MAX_ROWS) or ""
  ui.footer:SetText(more .. "Times are server time. Sign up in Discord. "
    .. (forGuild and "For guild adds a guild announcement everyone in the guild sees. " or "")
    .. "Open this list again with /guildlink events.")
end

function ns.ShowEvents()
  if not ns.db then return end
  if not Available() then
    ns.Print("No events from Discord yet. The GuildLink companion app fetches them; they show after your next login or /reload.")
    return
  end
  ui = ui or Build()
  ui:Show()
end

-- At login, open the list when an event is new or got a new time since it
-- was last offered.
local function OfferAtLogin()
  if not ns.db or not Available() then return end
  PointCalendarAtNow()
  local events = Upcoming()
  Prune(events)
  local cal, offer = State(), false
  for _, e in ipairs(events) do
    local status = StatusOf(e)
    if (status == "new" or status == "moved") and cal.seen[e.id] ~= e.startsAt then offer = true end
  end
  for _, e in ipairs(events) do cal.seen[e.id] = e.startsAt end
  if offer then ns.ShowEvents() end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
  if not Available() then return end
  -- Load the calendar's events first, so ones already in it aren't offered.
  C_Timer.After(5, function()
    if C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
    C_Timer.After(5, OfferAtLogin)
  end)
end)
ns.RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", function() ns.RefreshEvents() end)
