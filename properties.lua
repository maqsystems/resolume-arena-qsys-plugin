table.insert(props, {
  Name = "Deck Count",
  Type = "integer",
  Min = 1,
  Max = 16,
  Value = 4
})

table.insert(props, {
  Name = "Maximum Column Count",
  Type = "integer",
  Min = 1,
  Max = 32,
  Value = 9
})

table.insert(props, {
  Name = "Maximum Layer Count",
  Type = "integer",
  Min = 1,
  Max = 16,
  Value = 3
})

table.insert(props, {
  Name = "Look and Feel",
  Type = "enum",
  Choices = { "Resolume", "Q-SYS" },
  Value = "Resolume"
})
