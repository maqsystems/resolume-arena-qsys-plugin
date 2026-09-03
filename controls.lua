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

local function addDisplayText(name, prettyName)
  table.insert(ctrls, {
    Name = name,
    PrettyName = prettyName,
    ControlType = "Text",
    UserPin = false
  })
end

local function addKnob(name, prettyName, minimum, maximum, defaultValue)
  table.insert(ctrls, {
    Name = name,
    PrettyName = prettyName,
    ControlType = "Knob",
    ControlUnit = "Float",
    Min = minimum,
    Max = maximum,
    DefaultValue = defaultValue,
    UserPin = true,
    PinStyle = "Both"
  })
end

local function addTypedKnob(name, prettyName, unit, minimum, maximum, defaultValue)
  table.insert(ctrls, {
    Name = name,
    PrettyName = prettyName,
    ControlType = "Knob",
    ControlUnit = unit,
    Min = minimum,
    Max = maximum,
    DefaultValue = defaultValue,
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

addToggle("Composition Clear", "Composition~Controls~Clear")
addToggle("Composition Bypass", "Composition~Controls~Bypass")
addTypedKnob("Composition Master", "Composition~Controls~Master", "Percent", 0, 100, 100)
addTypedKnob("Composition Speed", "Composition~Controls~Speed", "Float", 0, 10, 1)
addToggle("Global Play Backwards", "Composition~Controls~Global Play Backwards")
addToggle("Global Pause", "Composition~Controls~Global Pause")
addToggle("Global Play Forward", "Composition~Controls~Global Play Forward")

for layer = 1, layerCount do
  addToggle("Layer " .. layer, "Composition~Layers~Layer " .. layer)
  addDisplayText(
    "Layer Name " .. layer,
    "Composition~Layers~Layer " .. layer .. "~Name"
  )
  addToggle("Layer Clear " .. layer, "Composition~Layers~Layer " .. layer .. "~Clear")
  addToggle("Layer Bypass " .. layer, "Composition~Layers~Layer " .. layer .. "~Bypass")
  addToggle("Layer Solo " .. layer, "Composition~Layers~Layer " .. layer .. "~Solo")
  addTypedKnob(
    "Layer Master " .. layer,
    "Composition~Layers~Layer " .. layer .. "~Master",
    "Percent", 0, 100, 100
  )
  addTypedKnob(
    "Layer Audio " .. layer,
    "Composition~Layers~Layer " .. layer .. "~Audio",
    "dB", -192, 0, 0
  )
  addTypedKnob(
    "Layer Video " .. layer,
    "Composition~Layers~Layer " .. layer .. "~Video",
    "Percent", 0, 100, 100
  )

  for column = 1, columnCount do
    addToggle(
      string.format("Clip L%d C%d", layer, column),
      string.format("Composition~Clips~Layer %d~Column %d", layer, column)
    )
  end
end

for link = 1, 8 do
  addDisplayText(
    "Dashboard Link Name " .. link,
    "Dashboard~Link " .. link .. "~Name"
  )
  addTypedKnob(
    "Dashboard Link " .. link,
    "Dashboard~Link " .. link,
    "Position", 0, 1, 0
  )
end

table.insert(ctrls, {
  Name = "IP Address",
  PrettyName = "Composition~Header~IP Address",
  ControlType = "Text",
  UserPin = true,
  PinStyle = "Both"
})

table.insert(ctrls, {
  Name = "Port",
  PrettyName = "Composition~Header~Port",
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
  PrettyName = "Composition~Header~Connection",
  ControlType = "Indicator",
  IndicatorType = "Status",
  UserPin = true,
  PinStyle = "Output"
})

table.insert(ctrls, {
  Name = "Status Text",
  PrettyName = "Composition~Header~Status",
  ControlType = "Text",
  UserPin = true,
  PinStyle = "Output"
})
