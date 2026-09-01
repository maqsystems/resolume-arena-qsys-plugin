local COLORS = {
  Black = { 0, 0, 0 },
  Dark = { 15, 15, 15 },
  Resolume = { 25, 24, 23 },
  Gray = { 79, 79, 79 },
  MintDark = { 42, 82, 68 },
  Mint = { 128, 255, 210 },
  PinkDark = { 146, 83, 114 },
  Pink = { 255, 128, 173 }
}

local currentPage = PageNames[props["page_index"].Value]
local deckCount = props["Deck Count"].Value
local columnCount = props["Maximum Column Count"].Value
local layerCount = props["Maximum Layer Count"].Value

local margin = 8
local labelWidth = 88
local cellWidth = 72
local clipHeight = 52
local headerHeight = 30
local columnHeight = 28
local deckHeight = 28
local gridX = margin + labelWidth
local gridY = margin + headerHeight + columnHeight
local pageWidth = math.max(480, gridX + columnCount * cellWidth + margin)
local deckRows = math.ceil(deckCount / math.max(1, columnCount))
local compositionHeight = gridY + layerCount * clipHeight + deckRows * deckHeight + margin * 2

local function addPageBackground(width, height, title, titleColor)
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

  table.insert(graphics, {
    Type = "Text",
    Text = title,
    Position = { margin, margin },
    Size = { width - margin * 2, headerHeight - 4 },
    FontSize = 15,
    Font = "Roboto",
    HTextAlign = "Left",
    Color = titleColor
  })
end

local function addToggleLayout(name, position, size, prettyName)
  layout[name] = {
    PrettyName = prettyName,
    Style = "Button",
    ButtonStyle = "Toggle",
    Position = position,
    Size = size,
    Color = COLORS.Gray,
    OffColor = COLORS.Resolume,
    UnlinkOffColor = true
  }
end

if currentPage == "Composition" then
  addPageBackground(pageWidth, compositionHeight, "Composition", COLORS.Mint)

  for column = 1, columnCount do
    addToggleLayout(
      "Column " .. column,
      { gridX + (column - 1) * cellWidth, margin + headerHeight },
      { cellWidth - 4, columnHeight - 4 },
      "Columns~Column " .. column
    )
  end

  for layer = 1, layerCount do
    local y = gridY + (layer - 1) * clipHeight
    addToggleLayout(
      "Layer " .. layer,
      { margin, y },
      { labelWidth - 4, clipHeight - 4 },
      "Layers~Layer " .. layer
    )

    for column = 1, columnCount do
      local name = string.format("Clip L%d C%d", layer, column)
      addToggleLayout(
        name,
        { gridX + (column - 1) * cellWidth, y },
        { cellWidth - 4, clipHeight - 4 },
        string.format("Clips~Layer %d~Column %d", layer, column)
      )
    end
  end

  local decksY = gridY + layerCount * clipHeight + margin
  for deck = 1, deckCount do
    local deckRow = math.floor((deck - 1) / columnCount)
    local deckColumn = (deck - 1) % columnCount
    addToggleLayout(
      "Deck " .. deck,
      { gridX + deckColumn * cellWidth, decksY + deckRow * deckHeight },
      { cellWidth - 4, deckHeight - 4 },
      "Decks~Deck " .. deck
    )
  end
elseif currentPage == "Setup" then
  local setupWidth = 480
  local setupHeight = 220
  addPageBackground(setupWidth, setupHeight, "Setup", COLORS.Pink)

  table.insert(graphics, {
    Type = "Text",
    Text = "IP Address",
    Position = { 20, 55 },
    Size = { 120, 24 },
    FontSize = 12,
    HTextAlign = "Right",
    Color = COLORS.Gray
  })
  layout["IP Address"] = {
    PrettyName = "Network~IP Address",
    Style = "Text",
    Position = { 150, 55 },
    Size = { 220, 24 }
  }

  table.insert(graphics, {
    Type = "Text",
    Text = "Port",
    Position = { 20, 87 },
    Size = { 120, 24 },
    FontSize = 12,
    HTextAlign = "Right",
    Color = COLORS.Gray
  })
  layout["Port"] = {
    PrettyName = "Network~Port",
    Style = "Text",
    Position = { 150, 87 },
    Size = { 100, 24 }
  }

  table.insert(graphics, {
    Type = "Text",
    Text = "Connection",
    Position = { 20, 127 },
    Size = { 120, 24 },
    FontSize = 12,
    HTextAlign = "Right",
    Color = COLORS.Gray
  })
  layout["Connection Status"] = {
    PrettyName = "Status~Connection",
    Style = "LED",
    Position = { 150, 127 },
    Size = { 24, 24 },
    Color = COLORS.Mint
  }
  layout["Status Text"] = {
    PrettyName = "Status~Details",
    Style = "Text",
    Position = { 182, 127 },
    Size = { 260, 24 }
  }
end
