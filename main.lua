local template = require("cameron.Booksmart.template")
local skills = require("cameron.Booksmart.skills")
local configPath = "Booksmart"


local config = mwse.loadConfig(configPath, {
  enabled = true,
  tooltipTemplate = "{{bookName}} {% if hasSkill then %}({{skillName}}){% end %} {% if hasOpened then %}({{statusLabel}}){% end %}",
})

local currentBook
local BookStatus = {
  unopened = "unopened",
  opened = "opened",
  read = "read",
}
local bookStatusLabels = {
  [BookStatus.unopened] = "Unopened",
  [BookStatus.opened] = "Opened",
  [BookStatus.read] = "Read",
}

local function getData()
  if tes3.player then
    return tes3.player.data.bookIndicator
  end
end

local function getBookStatus(book)
  local status
  for _, val in ipairs(getData().booksRead) do
    if val.id == book.id then
      status = val.status
    end
  end
  return status or BookStatus.unopened
end

local function setBookStatus(book, status)
  local existingBookIndex

  for i, val in ipairs(getData().booksRead) do
    if val.id == book.id then
      existingBookIndex = i
    end
  end

  if existingBookIndex then
    getData().booksRead[existingBookIndex].status = status
  else
    table.insert(getData().booksRead, {
      id = book.id,
      name = book.name,
      status = status,
    })
  end
end

-- Initialise tables
local function onLoad()
  tes3.player.data.bookIndicator = tes3.player.data.bookIndicator or {}
  tes3.player.data.bookIndicator.booksRead = tes3.player.data.bookIndicator.booksRead or {}
  if not tes3.player.data.bookIndicator.bookWormConverted then
    for _, val in ipairs(getData().booksRead) do
      setBookStatus(val, BookStatus.read)
    end
    tes3.player.data.bookIndicator.bookWormConverted = true
  end
end
event.register("loaded", onLoad)

-- Add books to list when activated
local function checkBookActivate(e)
  if currentBook then
    local readList = getData().booksRead
    local nextButton = e.element:findChild(tes3ui.registerID("MenuBook_button_next"))
    local currentStatus = getBookStatus(currentBook)

    if nextButton.visible then
      if currentStatus ~= BookStatus.read then
        setBookStatus(currentBook, BookStatus.opened)
        e.element:register("update", function(event)
          timer.frame.delayOneFrame(function()
            e.element:forwardEvent(event)
            checkBookActivate(e)
          end)
        end)
      end
    else
      setBookStatus(currentBook, BookStatus.read)
    end
  end
end
event.register("uiActivated", checkBookActivate, { filter = "MenuBook" })

local function updateCurrentBook(e)
  currentBook = e.book
end
event.register("bookGetText", updateCurrentBook)

local function getTooltip(book)
  local tooltip = book.name
  if config.enabled then
    local status = getBookStatus(book)
    local skill = skills.getBookSkill(book.id)

    -- The trailing space must be present owing to a bug in the template
    -- function that eats variables if they're at the end of the string.
    -- We trim off trailing spaces later.
    tooltip = template.compile(config.tooltipTemplate .. " ", {
      bookName = book.name,
      bookId = book.id,
      hasOpened = status == BookStatus.opened or status == BookStatus.read,
      hasRead = status == BookStatus.read,
      hasSkill = skill and true or false,
      status = status,
      statusLabel = bookStatusLabels[status],
      skill = skill and skill.id or nil,
      skillName = skill and skill.name or nil,
      skillShortName = skill and skill.shortName or nil,
    })

    tooltip = tooltip
      -- Collapse whitespace
      :gsub("%s+", " ")
      -- Trim
      :gsub("^%s*(.-)%s*$", "%1")
  end
  return tooltip
end

local function onTooltip(e)
  if e.object.objectType == tes3.objectType.book then
    local label = e.tooltip:findChild(tes3ui.registerID("HelpMenu_name"))
    label.text = getTooltip(e.object)
  end
end
event.register("uiObjectTooltip", onTooltip)

--------------------------------------
-- MCM
--------------------------------------

local function registerMCM()
    -- Initilaise MCM

  local sideBarDefault = ("This mod can display some helpful info about books, including what skills you can learn for them and whether you've opened/read them.\n\nIt was adapted from Merlord's Book Worm, and the skill display was inspired by Skill Names for Skill Books by Chronoch, with the short skill names taken directly from that mod.")
  local function addSideBar(component)
    component.sidebar:createInfo({ text = sideBarDefault })
    component.sidebar:createHyperLink({
      text = "Book Worm made by Merlord",
      exec = "start https://www.nexusmods.com/users/3040468?tab=user+files",
    })
    component.sidebar:createHyperLink({
      text = "Skill Names for Skill Books made by Chronoch",
      exec = "start https://www.nexusmods.com/users/3676808?tab=user+files",
    })
  end
  local template = mwse.mcm:createTemplate("Booksmart")
  template:saveOnClose(configPath, config)
  local page = template:createSideBarPage()
  addSideBar(page)
  local enableButton = page:createOnOffButton({
    label = "Enable Mod",
    description = "Enable or disable this mod.",
    variable = mwse.mcm.createTableVariable({
      id = "enabled",
      table = config,
    })
  })
  local tooltipTemplateField = page:createTextField({
    label = "Tooltip Template",
    description = [[The template to use for the tooltip display.

{{ variable }} to display variables (see table below).
{% -- code %} to run arbitrary Lua code.

The following variables are available:
  bookName - e.g. "The Lusty Argonian Maid".
  bookId - The internal ID of the book, e.g. "bk_lustyargonianmaid".
  hasOpened - Boolean. Whether the book has ever been opened before.
  hasRead - Boolean. Whether the book has been read to the end.
  hasSkill - Boolean. Is this a skill book?
  status - "unopened", "opened", or "read".
  statusLabel - "Unopened", "Opened", or "Read".
  skillName - e.g "Alchemy". Nil if not a skill book.
  skillShortName - A 3-letter skill abbreviation, e.g. "ALC". Nil if not a skill book.
]],
    variable = mwse.mcm.createTableVariable({
      id = "tooltipTemplate",
      table = config,
    })
  })
  local category = page:createCategory({ label = "Books you have read:", inGameOnly = true })
  local bookList = category:createInfo({
    text = "",
    inGameOnly = true,
    postCreate = function(self)
      local callMessage = (tes3.player and tes3.player.data.bookIndicator and getData().booksRead)
      if callMessage then
        local list = ""
        local readList = getData().booksRead
        if #readList == 0 then
          self.elements.info.text = "None"
        else
          local sort_func = function(a, b)
            return string.lower(a.name) > string.lower(b.name)
          end
          table.sort(readList, sort_func)
          for _, book in ipairs(readList) do
            if book.status == BookStatus.read then
              list = book.name .. "\n" .. list
            end
          end
          self.elements.info.text = list
        end
      end
    end
  })
  template:register()
end
event.register("modConfigReady", registerMCM)
