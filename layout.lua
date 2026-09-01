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

table.insert(graphics, {
  Type = "Text",
  Text = currentPage,
  Position = { 0, 0 },
  Size = { 640, 32 },
  FontSize = 16,
  Font = "Roboto",
  HTextAlign = "Left",
  Color = COLORS.Mint,
  Fill = COLORS.Resolume
})

table.insert(graphics, {
  Type = "GroupBox",
  Text = "",
  Position = { 0, 32 },
  Size = { 640, 328 },
  Fill = COLORS.Dark,
  StrokeColor = COLORS.Gray,
  StrokeWidth = 1,
  CornerRadius = 0
})

if currentPage == "Composition" then
  table.insert(graphics, {
    Type = "Text",
    Text = "Composition controls will be generated from plugin properties in M2.",
    Position = { 20, 64 },
    Size = { 600, 24 },
    FontSize = 12,
    Color = COLORS.Mint,
    HTextAlign = "Left"
  })
elseif currentPage == "Setup" then
  table.insert(graphics, {
    Type = "Text",
    Text = "Connection settings and diagnostics will be added in M2 and M4.",
    Position = { 20, 64 },
    Size = { 600, 24 },
    FontSize = 12,
    Color = COLORS.Pink,
    HTextAlign = "Left"
  })
end
