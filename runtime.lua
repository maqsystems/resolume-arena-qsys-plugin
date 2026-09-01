if Controls.Port.Value == 0 then
  Controls.Port.Value = 8080
end

Controls["Connection Status"].Value = 0
Controls["Status Text"].String = "Not connected"

local json = require("rapidjson")

local function escapeXml(value)
  return tostring(value or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
    :gsub("'", "&apos;")
end

local function renderStaticToggle(control, label, width, height)
  local active = control.Boolean
  local background = active and "#80ffd2" or "#191817"
  local foreground = active and "#191817" or "#ffffff"
  local baseline = math.floor(height / 2 + 4)

  local svg = table.concat({
    '<svg xmlns="http://www.w3.org/2000/svg" width="', width,
    '" height="', height, '" viewBox="0 0 ', width, ' ', height, '">',
    '<rect x="1" y="1" width="', width - 2, '" height="', height - 2,
    '" rx="2" fill="', background, '" stroke="#4f4f4f" stroke-width="1"/>',
    '<text x="', width / 2, '" y="', baseline,
    '" fill="', foreground,
    '" font-family="Roboto, Arial, sans-serif" font-size="11" text-anchor="middle">',
    escapeXml(label),
    '</text></svg>'
  })

  control.Legend = json.encode({
    DrawChrome = false,
    IconData = Crypto.Base64Encode(svg)
  })
end

local function initializeStaticToggle(name, label, width, height)
  local control = Controls[name]
  if not control then return end

  control.EventHandler = function()
    renderStaticToggle(control, label, width, height)
  end
  renderStaticToggle(control, label, width, height)
end

local deckCount = Properties["Deck Count"].Value
local columnCount = Properties["Maximum Column Count"].Value
local layerCount = Properties["Maximum Layer Count"].Value
local resolumeLook = Properties["Look and Feel"].Value == "Resolume"

if resolumeLook then
  for deck = 1, deckCount do
    initializeStaticToggle("Deck " .. deck, "Deck " .. deck, 108, 26)
  end

  for column = 1, columnCount do
    initializeStaticToggle("Column " .. column, "Column " .. column, 108, 30)
  end

  for layer = 1, layerCount do
    initializeStaticToggle("Layer " .. layer, "Layer " .. layer, 94, 74)

    for column = 1, columnCount do
      initializeStaticToggle(
        string.format("Clip L%d C%d", layer, column),
        string.format("L%d C%d", layer, column),
        108,
        74
      )
    end
  end
end
