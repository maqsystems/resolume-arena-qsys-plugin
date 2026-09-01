local COLORS = {
  Black = { 0, 0, 0 },
  Dark = { 15, 15, 15 },
  Resolume = { 25, 24, 23 },
  Gray = { 79, 79, 79 },
  MintDark = { 42, 82, 68 },
  Mint = { 128, 255, 210 },
  PinkDark = { 146, 83, 114 },
  Pink = { 255, 128, 173 },
  White = { 255, 255, 255 }
}

local currentPage = PageNames[props["page_index"].Value]
local deckCount = props["Deck Count"].Value
local columnCount = props["Maximum Column Count"].Value
local layerCount = props["Maximum Layer Count"].Value
local resolumeLook = props["Look and Feel"].Value == "Resolume"

local margin = 6
local gap = 4
local labelWidth = 94
local cellWidth = 112
local clipHeight = 78
local pageTitleHeight = 26
local columnHeight = 30
local deckHeight = 30
local gridX = margin + labelWidth + gap
local gridY = margin + pageTitleHeight + columnHeight + gap
local pageWidth = math.max(500, gridX + columnCount * cellWidth + margin)
local deckColumns = math.max(1, columnCount)
local deckRows = math.ceil(deckCount / deckColumns)
local decksY = gridY + layerCount * clipHeight + gap
local compositionHeight = decksY + deckRows * deckHeight + margin

local function addBackground(width, height)
  table.insert(graphics, {
    Type = "GroupBox",
    Text = "",
    Position = { 0, 0 },
    Size = { width, height },
    Fill = COLORS.Dark,
    StrokeColor = COLORS.Gray,
    StrokeWidth = 1,
    CornerRadius = 0
  })
end

local function addText(text, position, size, color, alignment, fontSize)
  table.insert(graphics, {
    Type = "Text",
    Text = text,
    Position = position,
    Size = size,
    Font = "Roboto",
    FontSize = fontSize or 11,
    HTextAlign = alignment or "Left",
    Color = color or COLORS.White
  })
end

local function addGroup(text, position, size, color)
  table.insert(graphics, {
    Type = "GroupBox",
    Text = text,
    Position = position,
    Size = size,
    Font = "Roboto",
    FontSize = 11,
    Fill = COLORS.Resolume,
    Color = color or COLORS.White,
    StrokeColor = COLORS.Gray,
    StrokeWidth = 1,
    CornerRadius = 0
  })
end

local function addToggle(name, legend, position, size, prettyName, activeColor)
  local controlLayout = {
    PrettyName = prettyName,
    Style = "Button",
    ButtonStyle = "Toggle",
    Legend = legend,
    Position = position,
    Size = size,
    Font = "Roboto",
    FontSize = 10
  }

  if resolumeLook then
    controlLayout.Color = activeColor or COLORS.Mint
    controlLayout.OffColor = COLORS.Resolume
    controlLayout.UnlinkOffColor = true
    controlLayout.StrokeColor = COLORS.Gray
    controlLayout.StrokeWidth = 1
    controlLayout.CornerRadius = 1
  end

  layout[name] = controlLayout
end

if currentPage == "Composition" then
  addBackground(pageWidth, compositionHeight)
  addText("Composition", { margin, margin }, { pageWidth - margin * 2, pageTitleHeight }, COLORS.Mint, "Left", 14)
  addText("Layers", { margin, margin + pageTitleHeight }, { labelWidth, columnHeight }, COLORS.Gray, "Left", 10)

  for column = 1, columnCount do
    addToggle(
      "Column " .. column,
      "Column " .. column,
      { gridX + (column - 1) * cellWidth, margin + pageTitleHeight },
      { cellWidth - gap, columnHeight },
      "Columns~Column " .. column,
      COLORS.Mint
    )
  end

  for layer = 1, layerCount do
    -- Resolume displays Layer 1 at the bottom of the grid.
    local visualRow = layerCount - layer
    local y = gridY + visualRow * clipHeight

    addToggle(
      "Layer " .. layer,
      "Layer " .. layer,
      { margin, y },
      { labelWidth, clipHeight - gap },
      "Layers~Layer " .. layer,
      COLORS.Mint
    )

    for column = 1, columnCount do
      local name = string.format("Clip L%d C%d", layer, column)
      addToggle(
        name,
        string.format("L%d C%d", layer, column),
        { gridX + (column - 1) * cellWidth, y },
        { cellWidth - gap, clipHeight - gap },
        string.format("Clips~Layer %d~Column %d", layer, column),
        COLORS.Mint
      )
    end
  end

  addText("Decks", { margin, decksY }, { labelWidth, deckHeight }, COLORS.Gray, "Left", 10)
  for deck = 1, deckCount do
    local deckRow = math.floor((deck - 1) / deckColumns)
    local deckColumn = (deck - 1) % deckColumns
    addToggle(
      "Deck " .. deck,
      "Deck " .. deck,
      { gridX + deckColumn * cellWidth, decksY + deckRow * deckHeight },
      { cellWidth - gap, deckHeight - gap },
      "Decks~Deck " .. deck,
      COLORS.Mint
    )
  end
elseif currentPage == "Setup" then
  local setupWidth = 520
  local setupHeight = 260
  addBackground(setupWidth, setupHeight)
  addText("Setup", { margin, margin }, { setupWidth - margin * 2, pageTitleHeight }, COLORS.Pink, "Left", 14)

  addGroup("Network", { 14, 40 }, { 492, 98 }, COLORS.Pink)
  addText("IP Address", { 30, 68 }, { 112, 24 }, COLORS.Gray, "Right", 11)
  layout["IP Address"] = {
    PrettyName = "Network~IP Address",
    Style = "Text",
    Position = { 152, 68 },
    Size = { 250, 24 },
    Font = "Roboto",
    FontSize = 11
  }

  addText("Port", { 30, 100 }, { 112, 24 }, COLORS.Gray, "Right", 11)
  layout["Port"] = {
    PrettyName = "Network~Port",
    Style = "Text",
    Position = { 152, 100 },
    Size = { 100, 24 },
    Font = "Roboto",
    FontSize = 11
  }

  addGroup("Status", { 14, 150 }, { 492, 92 }, COLORS.Mint)
  addText("Connection", { 30, 181 }, { 112, 24 }, COLORS.Gray, "Right", 11)
  layout["Connection Status"] = {
    PrettyName = "Status~Connection",
    Style = "LED",
    Position = { 152, 181 },
    Size = { 24, 24 },
    Color = COLORS.Mint
  }
  layout["Status Text"] = {
    PrettyName = "Status~Details",
    Style = "Text",
    Position = { 184, 181 },
    Size = { 290, 24 },
    Font = "Roboto",
    FontSize = 11
  }
end
