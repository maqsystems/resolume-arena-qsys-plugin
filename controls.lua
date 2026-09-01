local deckCount = props["Deck Count"].Value
local columnCount = props["Maximum Column Count"].Value
local layerCount = props["Maximum Layer Count"].Value

local function addToggle(name, prettyName)
  table.insert(ctrls, {
    Name = name,
    PrettyName = prettyName,
    ControlType = "Button",
    ButtonType = "Toggle",
    UserPin = true,
    PinStyle = "Both"
  })
end

for deck = 1, deckCount do
  addToggle("Deck " .. deck, "Composition~Decks~Deck " .. deck)
end

for column = 1, columnCount do
  addToggle("Column " .. column, "Composition~Columns~Column " .. column)
end

for layer = 1, layerCount do
  addToggle("Layer " .. layer, "Composition~Layers~Layer " .. layer)

  for column = 1, columnCount do
    addToggle(
      string.format("Clip L%d C%d", layer, column),
      string.format("Composition~Clips~Layer %d~Column %d", layer, column)
    )
  end
end

table.insert(ctrls, {
  Name = "IP Address",
  PrettyName = "Setup~Network~IP Address",
  ControlType = "Text",
  UserPin = true,
  PinStyle = "Both"
})

table.insert(ctrls, {
  Name = "Port",
  PrettyName = "Setup~Network~Port",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min = 1,
  Max = 65535,
  DefaultValue = 8080,
  UserPin = true,
  PinStyle = "Both"
})

table.insert(ctrls, {
  Name = "Connection Status",
  PrettyName = "Setup~Status~Connection",
  ControlType = "Indicator",
  IndicatorType = "Status",
  UserPin = true,
  PinStyle = "Output"
})

table.insert(ctrls, {
  Name = "Status Text",
  PrettyName = "Setup~Status~Details",
  ControlType = "Text",
  UserPin = true,
  PinStyle = "Output"
})
