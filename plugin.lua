-- Resolume Arena Q-SYS Plugin

--[[ #include "info.lua" ]]

function GetColor(props)
  return { 25, 24, 23 }
end

function GetPrettyName(props)
  return "Resolume Arena " .. PluginInfo.Version
end

PageNames = { "Composition" }

function GetPages(props)
  local pages = {}
  --[[ #include "pages.lua" ]]
  return pages
end

function GetProperties()
  local props = {}
  --[[ #include "properties.lua" ]]
  return props
end

function RectifyProperties(props)
  --[[ #include "rectify_properties.lua" ]]
  return props
end

function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end

function GetControlLayout(props)
  local layout = {}
  local graphics = {}
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

if Controls then
  --[[ #include "runtime.lua" ]]
end
