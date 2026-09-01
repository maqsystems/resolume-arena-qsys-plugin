local function rectifyIntegerProperty(property, minimum, maximum, fallback)
  local value = math.floor(tonumber(property.Value) or fallback)
  property.Value = math.max(minimum, math.min(maximum, value))
end

rectifyIntegerProperty(props["Deck Count"], 1, 16, 4)
rectifyIntegerProperty(props["Maximum Column Count"], 1, 32, 9)
rectifyIntegerProperty(props["Maximum Layer Count"], 1, 16, 3)
