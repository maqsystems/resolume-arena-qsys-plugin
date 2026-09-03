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

local margin = 14
local gap = 2
local layerGap = 4
local sectionGap = 5
local labelWidth = 329
local cellWidth = 95
local clipHeight = 65
local pageTitleHeight = 16
local columnHeight = 30
local deckHeight = 28
local headerHeight = 104
local gridX = margin + labelWidth + sectionGap
local columnY = headerHeight + margin
local gridY = columnY + columnHeight + gap
local pageWidth = math.max(980, gridX + columnCount * cellWidth + margin)
local deckColumns = math.max(1, columnCount)
local deckRows = math.ceil(deckCount / deckColumns)
local decksY = gridY + layerCount * clipHeight + gap
local dashboardHeight = 52
local compositionHeight = decksY + math.max(deckRows * deckHeight, dashboardHeight) + margin

local function addBackground(width, height)
  table.insert(graphics, {
    Type = "GroupBox",
    Text = "",
    Position = { 0, 0 },
    Size = { width, height },
    Fill = COLORS.Black,
    StrokeColor = COLORS.Gray,
    StrokeWidth = 1,
    CornerRadius = 0
  })
end

local function addText(text, position, size, color, alignment, fontSize)
  table.insert(graphics, {
    Type = "Label",
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
    FontSize = 10,
    Margin = 0,
    Padding = 0,
    CornerRadius = 2,
    Radius = 2
  }

  if resolumeLook then
    controlLayout.Color = activeColor or COLORS.Mint
    controlLayout.OffColor = COLORS.Resolume
    controlLayout.UnlinkOffColor = true
    controlLayout.StrokeColor = COLORS.Gray
    controlLayout.StrokeWidth = 0
    controlLayout.CornerRadius = 2
    controlLayout.Radius = 2
  end

  layout[name] = controlLayout
end

local function addPositionMeter(name, position, size, prettyName, color, className)
  layout[name] = {
    PrettyName = prettyName,
    Style = "Text",
    TextBoxStyle = "Meter",
    Position = position,
    Size = size,
    Color = color,
    TextColor = COLORS.White,
    Margin = 0,
    Padding = 0,
    CornerRadius = 0,
    Radius = 0,
    StrokeWidth = 0,
    Font = "Roboto",
    FontSize = 10,
    ClassName = className
  }
end

if currentPage == "Composition" then
  addBackground(pageWidth, compositionHeight)
  local headerX = margin
  local headerY = 10
  local headerWidth = labelWidth
  table.insert(graphics, {
    Type = "GroupBox", Text = "", Position = { headerX, headerY + 78 },
    Size = { headerWidth, 22 }, Fill = COLORS.Gray,
    StrokeWidth = 0, CornerRadius = 0
  })
  addText(
    "Q-SYS Plugin for Resolume Arena",
    { headerX + 74, headerY + 12 },
    { headerWidth - 82, 20 },
    COLORS.White,
    "Left",
    14
  )
  addText("Designed by Mathieu Maquet (MAQ SYSTEMS)", { headerX + 74, headerY + 34 }, { headerWidth - 82, 14 }, COLORS.Mint, "Left", 8)
  addText("version " .. PluginInfo.BuildVersion, { headerX + 74, headerY + 50 }, { headerWidth - 82, 12 }, COLORS.White, "Left", 7)
  local setupY = headerY + 80
  local setupHeight = 18
  addText("IP", { headerX + 8, setupY }, { 14, setupHeight }, COLORS.White, "Left", 8)
  layout["IP Address"] = {
    PrettyName = "Network~IP Address",
    Style = "Text",
    Position = { headerX + 26, setupY },
    Size = { 82, 18 },
    Font = "Roboto",
    FontSize = 10,
    Margin = 0,
    Padding = 0,
    CornerRadius = 2
  }
  addText("Port", { headerX + 116, setupY }, { 26, setupHeight }, COLORS.White, "Right", 8)
  layout["Port"] = {
    PrettyName = "Network~Port",
    Style = "Text",
    Position = { headerX + 146, setupY },
    Size = { 48, 18 },
    Font = "Roboto",
    FontSize = 10,
    Margin = 0,
    Padding = 0,
    CornerRadius = 2
  }
  layout["Connection Status"] = {
    PrettyName = "Status~Connection",
    Style = "LED",
    Position = { headerX + 244, setupY },
    Size = { 77, setupHeight },
    Color = COLORS.Mint
  }
  addText("Status", { headerX + 202, setupY }, { 38, setupHeight }, COLORS.White, "Right", 8)
  table.insert(graphics, {
    Type = "GroupBox",
    Text = "",
    Position = { margin, columnY },
    Size = { 324, pageTitleHeight },
    Fill = COLORS.Gray,
    Padding = 0,
    StrokeWidth = 0,
    CornerRadius = 2
  })
  addText("Composition", { margin + 4, columnY }, { 320, pageTitleHeight }, COLORS.White, "Left", 10)
  local controlsY = columnY + pageTitleHeight
  local compositionControlHeight = columnHeight - pageTitleHeight
  addToggle("Composition Clear", "X", { margin, controlsY }, { 36, compositionControlHeight }, "Composition Controls~Clear", COLORS.Mint)
  addToggle("Composition Bypass", "B", { margin + 38, controlsY }, { 36, compositionControlHeight }, "Composition Controls~Bypass", COLORS.Mint)
  addText("M", { margin + 76, controlsY }, { 12, compositionControlHeight }, COLORS.White, "Center", 8)
  addPositionMeter("Composition Master", { margin + 88, controlsY }, { 62, compositionControlHeight }, "Composition Controls~Master", COLORS.Gray, "resolume-master")
  addText("S", { margin + 152, controlsY }, { 12, compositionControlHeight }, COLORS.White, "Center", 8)
  addPositionMeter("Composition Speed", { margin + 164, controlsY }, { 64, compositionControlHeight }, "Composition Controls~Speed", COLORS.Gray, "resolume-speed")
  addToggle("Global Play Backwards", "◀", { margin + 230, controlsY }, { 31, compositionControlHeight }, "Composition Controls~Global Play Backwards", COLORS.Mint)
  addToggle("Global Pause", "Ⅱ", { margin + 263, controlsY }, { 31, compositionControlHeight }, "Composition Controls~Global Pause", COLORS.Mint)
  addToggle("Global Play Forward", "▶", { margin + 296, controlsY }, { 28, compositionControlHeight }, "Composition Controls~Global Play Forward", COLORS.Mint)

  for column = 1, columnCount do
    addToggle(
      "Column " .. column,
      "Column " .. column,
      { gridX + (column - 1) * cellWidth, columnY },
      { cellWidth - gap, columnHeight },
      "Columns~Column " .. column,
      COLORS.Mint
    )
  end

  table.insert(graphics, {
    Type = "GroupBox",
    Text = "",
    Position = { margin + labelWidth + 2, columnY },
    Size = { 2, gridY + layerCount * clipHeight - layerGap - columnY },
    Fill = COLORS.PinkDark,
    StrokeWidth = 0,
    CornerRadius = 0
  })

  for layer = 1, layerCount do
    -- Resolume displays Layer 1 at the bottom of the grid.
    local visualRow = layerCount - layer
    local y = gridY + visualRow * clipHeight

    addToggle(
      "Layer Clear " .. layer,
      "X",
      { margin, y },
      { 36, 44 },
      "Layers~Layer " .. layer .. "~Clear",
      COLORS.Mint
    )
    addToggle(
      "Layer Bypass " .. layer,
      "B",
      { margin + 38, y },
      { 36, 44 },
      "Layers~Layer " .. layer .. "~Bypass",
      COLORS.Pink
    )
    addToggle(
      "Layer Solo " .. layer,
      "S",
      { margin + 76, y },
      { 36, 44 },
      "Layers~Layer " .. layer .. "~Solo",
      COLORS.Mint
    )
    addText("M", { margin + 114, y }, { 12, 14 }, COLORS.Gray, "Center", 8)
    addPositionMeter("Layer Master " .. layer, { margin + 126, y }, { 102, 14 }, "Layers~Layer " .. layer .. "~Master", COLORS.Gray, "resolume-layer-master")
    addText("A", { margin + 114, y + 15 }, { 12, 14 }, COLORS.Pink, "Center", 8)
    addPositionMeter("Layer Audio " .. layer, { margin + 126, y + 15 }, { 102, 14 }, "Layers~Layer " .. layer .. "~Audio", COLORS.Pink, "resolume-layer-audio")
    addText("V", { margin + 114, y + 30 }, { 12, 14 }, COLORS.Mint, "Center", 8)
    addPositionMeter("Layer Video " .. layer, { margin + 126, y + 30 }, { 102, 14 }, "Layers~Layer " .. layer .. "~Video", COLORS.MintDark, "resolume-layer-video")
    table.insert(graphics, {
      Type = "GroupBox",
      Text = "",
      Position = { margin, y + 45 },
      Size = { 228, 16 },
      Margin = 0,
      Padding = 0,
      CornerRadius = 2,
      Radius = 2,
      Fill = COLORS.Gray,
      StrokeColor = COLORS.Gray,
      StrokeWidth = 0
    })
    layout["Layer Name " .. layer] = {
      PrettyName = "Layers~Layer " .. layer .. "~Name",
      Style = "Text",
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      Position = { margin + 4, y + 45 },
      Size = { 224, 16 },
      Margin = 0,
      Padding = 0,
      TextColor = COLORS.White,
      Font = "Roboto",
      FontSize = 10,
      HTextAlign = "Left",
      VTextAlign = "Center"
    }
    addToggle(
      "Layer " .. layer,
      "Layer " .. layer,
      { margin + labelWidth - 98, y },
      { 93, clipHeight - layerGap },
      "Layers~Layer " .. layer .. "~Thumbnail",
      COLORS.Mint
    )

    for column = 1, columnCount do
      local name = string.format("Clip L%d C%d", layer, column)
      addToggle(
        name,
        string.format("L%d C%d", layer, column),
        { gridX + (column - 1) * cellWidth, y },
        { cellWidth - gap, clipHeight - layerGap },
        string.format("Clips~Layer %d~Column %d", layer, column),
        COLORS.Mint
      )
    end
  end

  local dashboardCellWidth = math.floor(labelWidth / 8)
  for link = 1, 8 do
    local x = margin + (link - 1) * dashboardCellWidth
    layout["Dashboard Link " .. link] = {
      PrettyName = "Dashboard~Link " .. link,
      Style = "Knob",
      Position = { x + 5, decksY },
      Size = { dashboardCellWidth - 10, 34 },
      Color = COLORS.Mint,
      Margin = 0,
      Padding = 0,
      Font = "Roboto",
      FontSize = 9
    }
    layout["Dashboard Link Name " .. link] = {
      PrettyName = "Dashboard~Link " .. link .. "~Name",
      Style = "Text",
      IsReadOnly = true,
      TextBoxStyle = "NoBackground",
      Position = { x, decksY + 35 },
      Size = { dashboardCellWidth - 2, 15 },
      Margin = 0,
      Padding = 0,
      TextColor = COLORS.White,
      Font = "Roboto",
      FontSize = 8,
      HTextAlign = "Center",
      VTextAlign = "Center"
    }
  end
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

  -- Keep the logo last in the natural graphics paint order. QDS reliably
  -- renders this after the full-page background without explicit ZOrder.
  table.insert(graphics, {
    Type = "Svg",
    Image = "--[[ #encode "app-logo.svg" ]]",
    Position = { headerX + 8, headerY + 5 },
    Size = { 58, 58 }
  })
end
