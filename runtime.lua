if Controls.Port.Value == 0 then
  Controls.Port.Value = 8080
end

Controls["Connection Status"].Value = 0
Controls["Status Text"].String = "Not connected"

local json = require("rapidjson")

-- Q-SYS asynchronous objects must remain globally referenced. Locally scoped
-- WebSocket and Timer objects can be collected while their callbacks are active.
ResolumeWebSocket = WebSocket.New()
ResolumeReconnectTimer = Timer.New()
ResolumeReceiveBufferTimer = Timer.New()
ResolumeHealthTimer = Timer.New()
local reconnectDelay = 5
local receiveBufferTimeout = 1
local receiveBufferLimit = 8 * 1024 * 1024
local healthCheckInterval = 5
local receiveBuffer = ""
local connectionState = "idle"
local reconnectRequested = false
local activeHost = ""
local activePort = 0
local receivedMessageCount = 0
local lastStatusMessage = nil
local healthCheckPending = false
local compositionReceived = false
local initialRefreshRequested = false
local applyCompositionSnapshot
local clearCompositionCache
local synchronizeFeedbackSubscriptions
local applyParameterFeedback
local subscribedFeedbackPaths = {}

local function debugEnabled()
  local property = Properties.plugin_show_debug or Properties["Show Debug"]
  return property and (
    property.Value == true
      or property.Value == "Yes"
      or property.Value == 1
  )
end

local function debugLog(message)
  if debugEnabled() then
    print("[Resolume] " .. tostring(message))
  end
end

local function setConnectionStatus(value, message)
  Controls["Connection Status"].Value = value
  Controls["Status Text"].String = message
  if message ~= lastStatusMessage then
    print("[Resolume] " .. message)
    lastStatusMessage = message
  end
end

local function configuredEndpoint()
  local host = Controls["IP Address"].String
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  local port = math.floor(tonumber(Controls.Port.Value) or 8080)
  port = math.max(1, math.min(65535, port))
  return host, port
end

local connectWebSocket

local function requestCompositionState()
  if connectionState ~= "connected" then return false end

  ResolumeWebSocket:Write(json.encode({
    action = "get",
    parameter = "/composition"
  }))
  debugLog("Requested one composition refresh")
  return true
end

local function scheduleReconnect(delay)
  ResolumeReconnectTimer:Stop()
  ResolumeReconnectTimer.EventHandler = function()
    ResolumeReconnectTimer:Stop()
    connectWebSocket()
  end
  ResolumeReconnectTimer:Start(delay or reconnectDelay)
end

connectWebSocket = function()
  local host, port = configuredEndpoint()
  if host == "" then
    connectionState = "idle"
    setConnectionStatus(2, "IP address is required")
    return
  end

  if connectionState == "connected"
      and host == activeHost
      and port == activePort then
    return
  end

  activeHost = host
  activePort = port
  connectionState = "connecting"
  reconnectRequested = false
  setConnectionStatus(1, string.format("Connecting to %s:%d...", host, port))
  ResolumeWebSocket:Connect("ws", host, "/api/v1", port)
end

local function restartConnection()
  ResolumeReconnectTimer:Stop()
  reconnectRequested = true

  if connectionState == "connected" or connectionState == "connecting" then
    connectionState = "closing"
    setConnectionStatus(1, "Applying connection settings...")
    ResolumeWebSocket:Close()
  else
    scheduleReconnect(0.1)
  end
end

local function clearReceiveBuffer(reason)
  ResolumeReceiveBufferTimer:Stop()
  if receiveBuffer ~= "" then
    debugLog(string.format(
      "Discarding receive buffer (%d bytes): %s",
      #receiveBuffer,
      reason
    ))
  end
  receiveBuffer = ""
end

local function stopHealthCheck()
  ResolumeHealthTimer:Stop()
  healthCheckPending = false
end

local function failHealthCheck(message)
  healthCheckPending = false
  if connectionState ~= "connected" then return end

  connectionState = "closing"
  setConnectionStatus(2, message)
  ResolumeWebSocket:Close()
end

local function checkResolumeHealth()
  if connectionState ~= "connected" then
    stopHealthCheck()
    return
  end
  if healthCheckPending then return end

  healthCheckPending = true
  local requestHost = activeHost
  local requestPort = activePort
  debugLog("Checking Resolume Webserver health")

  HttpClient.Get({
    Url = string.format("http://%s:%d/api/v1/product", requestHost, requestPort),
    Headers = { Accept = "application/json" },
    Timeout = 2,
    EventHandler = function(_, code, data, errorMessage)
      if requestHost ~= activeHost or requestPort ~= activePort then return end
      healthCheckPending = false

      if code ~= 200 or not data or #data == 0 then
        failHealthCheck("Resolume Webserver is unavailable")
        debugLog(string.format(
          "Health check failed (HTTP %s): %s",
          tostring(code),
          tostring(errorMessage)
        ))
        return
      end

      debugLog("Resolume Webserver health check succeeded")
      if not compositionReceived and not initialRefreshRequested then
        initialRefreshRequested = requestCompositionState()
      end
    end
  })
end

ResolumeHealthTimer.EventHandler = checkResolumeHealth

local function startHealthCheck()
  stopHealthCheck()
  ResolumeHealthTimer:Start(healthCheckInterval)
end

local function handleWebSocketMessage(message)
  receivedMessageCount = receivedMessageCount + 1
  debugLog(string.format("Received JSON message #%d", receivedMessageCount))

  if message.columns and message.layers and applyCompositionSnapshot then
    compositionReceived = true
    initialRefreshRequested = false
    applyCompositionSnapshot(message)
  elseif message.path and message.value ~= nil and applyParameterFeedback then
    applyParameterFeedback(message.path, message.value)
  end
end

ResolumeReceiveBufferTimer.EventHandler = function()
  clearReceiveBuffer("incomplete or invalid JSON")
end

ResolumeWebSocket.Connected = function()
  ResolumeReconnectTimer:Stop()
  connectionState = "connected"
  reconnectRequested = false
  compositionReceived = false
  initialRefreshRequested = false
  setConnectionStatus(0, string.format("Connected to %s:%d", activeHost, activePort))
  startHealthCheck()
end

ResolumeWebSocket.Data = function(_, data, isBinary)
  local payload = data
  if type(payload) == "table" then
    payload = payload.Data or payload.data or payload[1]
  end
  if type(payload) ~= "string" or payload == "" then return end

  if receiveBuffer == "" then
    payload = payload:gsub("^\239\187\191", "")
  end
  receiveBuffer = receiveBuffer .. payload

  if #receiveBuffer > receiveBufferLimit then
    clearReceiveBuffer("size limit exceeded")
    setConnectionStatus(1, "Receive buffer reset; connection remains active")
    return
  end

  ResolumeReceiveBufferTimer:Stop()
  ResolumeReceiveBufferTimer:Start(receiveBufferTimeout)

  local ok, message = pcall(json.decode, receiveBuffer)
  if not ok or type(message) ~= "table" then
    debugLog(string.format(
      "Received fragment: %d bytes (buffer %d, binary=%s)",
      #payload,
      #receiveBuffer,
      tostring(isBinary)
    ))
    return
  end

  local completeLength = #receiveBuffer
  ResolumeReceiveBufferTimer:Stop()
  receiveBuffer = ""
  debugLog(string.format("Complete JSON message: %d bytes", completeLength))
  handleWebSocketMessage(message)
end

ResolumeWebSocket.Error = function(_, errorMessage)
  connectionState = "idle"
  stopHealthCheck()
  clearReceiveBuffer("WebSocket error")
  setConnectionStatus(2, "WebSocket error: " .. tostring(errorMessage))
  subscribedFeedbackPaths = {}
  if clearCompositionCache then clearCompositionCache() end
  scheduleReconnect(reconnectDelay)
end

ResolumeWebSocket.Closed = function()
  connectionState = "idle"
  stopHealthCheck()
  clearReceiveBuffer("WebSocket closed")
  compositionReceived = false
  initialRefreshRequested = false
  subscribedFeedbackPaths = {}
  if clearCompositionCache then clearCompositionCache() end

  if reconnectRequested then
    reconnectRequested = false
    setConnectionStatus(1, "Reconnecting with new settings...")
    scheduleReconnect(0.1)
  else
    setConnectionStatus(2, string.format(
      "Disconnected; retrying in %d seconds",
      reconnectDelay
    ))
    scheduleReconnect(reconnectDelay)
  end
end

ResolumeReconnectTimer.EventHandler = function()
  ResolumeReconnectTimer:Stop()
  connectWebSocket()
end

Controls["IP Address"].EventHandler = restartConnection
Controls.Port.EventHandler = restartConnection

print(string.format(
  "[Resolume] Starting plugin %s (build %s, debug=%s)",
  tostring(PluginInfo.Version),
  tostring(PluginInfo.BuildVersion),
  tostring(debugEnabled())
))

local function escapeXml(value)
  return tostring(value or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
    :gsub("'", "&apos;")
end

local resolumeLook = Properties["Look and Feel"].Value == "Resolume"
local toggleViews = {}
local applyingCacheFeedback = false

local function renderToggle(view)
  local control = view.control
  local label = view.label
  if not resolumeLook then
    control.Legend = label
    return
  end

  local active = view.active
  local background = active and "#80ffd2" or "#191817"
  local foreground = active and "#191817" or "#ffffff"
  local baseline = math.floor(view.height / 2 + 4)

  local svg = table.concat({
    '<svg xmlns="http://www.w3.org/2000/svg" width="', view.width,
    '" height="', view.height, '" viewBox="0 0 ', view.width, ' ', view.height, '">',
    '<rect x="1" y="1" width="', view.width - 2, '" height="', view.height - 2,
    '" rx="2" fill="', background, '" stroke="#4f4f4f" stroke-width="1"/>',
    '<text x="', view.width / 2, '" y="', baseline,
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

local function initializeToggle(name, label, width, height)
  local control = Controls[name]
  if not control then return end

  local view = {
    control = control,
    label = label,
    active = false,
    width = width,
    height = height
  }
  toggleViews[name] = view

  control.EventHandler = function()
    if not applyingCacheFeedback then
      applyingCacheFeedback = true
      control.Boolean = view.active
      applyingCacheFeedback = false
    end
    renderToggle(view)
  end
  renderToggle(view)
end

local function setToggleState(name, label, active, disabled)
  local view = toggleViews[name]
  if not view then return end

  view.label = tostring(label or "")
  view.active = active == true
  applyingCacheFeedback = true
  view.control.Boolean = view.active
  view.control.IsDisabled = disabled == true
  applyingCacheFeedback = false
  renderToggle(view)
end

local function parameterValue(parameter, fallback)
  if type(parameter) == "table" and parameter.value ~= nil then
    return parameter.value
  end
  if parameter ~= nil and type(parameter) ~= "table" then
    return parameter
  end
  return fallback
end

local function displayName(item, fallback)
  local name = parameterValue(item and item.name, "")
  if name == nil or tostring(name) == "" then return fallback end
  return tostring(name)
end

local function indexedDisplayName(item, fallback, index)
  local name = displayName(item, fallback)
  return name:gsub("#", tostring(index))
end

local function connectedStateIsActive(value)
  return value == "Connected" or value == "Connected & previewing"
end

local deckCount = Properties["Deck Count"].Value
local columnCount = Properties["Maximum Column Count"].Value
local layerCount = Properties["Maximum Layer Count"].Value

for deck = 1, deckCount do
  initializeToggle("Deck " .. deck, "Deck " .. deck, 108, 26)
end

for column = 1, columnCount do
  initializeToggle("Column " .. column, "Column " .. column, 108, 30)
end

for layer = 1, layerCount do
  initializeToggle("Layer " .. layer, "Layer " .. layer, 94, 74)

  for column = 1, columnCount do
    initializeToggle(
      string.format("Clip L%d C%d", layer, column),
      string.format("L%d C%d", layer, column),
      108,
      74
    )
  end
end

ResolumeCompositionCache = {
  name = "",
  sourceDeckCount = 0,
  sourceColumnCount = 0,
  sourceLayerCount = 0,
  decks = {},
  columns = {},
  layers = {}
}

clearCompositionCache = function()
  ResolumeCompositionCache.name = ""
  ResolumeCompositionCache.sourceDeckCount = 0
  ResolumeCompositionCache.sourceColumnCount = 0
  ResolumeCompositionCache.sourceLayerCount = 0

  for deck = 1, deckCount do
    ResolumeCompositionCache.decks[deck] = nil
    setToggleState("Deck " .. deck, "", false, true)
  end

  for column = 1, columnCount do
    ResolumeCompositionCache.columns[column] = nil
    setToggleState("Column " .. column, "", false, true)
  end

  for layer = 1, layerCount do
    ResolumeCompositionCache.layers[layer] = nil
    setToggleState("Layer " .. layer, "", false, true)
    for column = 1, columnCount do
      setToggleState(string.format("Clip L%d C%d", layer, column), "", false, true)
    end
  end
end

applyCompositionSnapshot = function(composition)
  local decks = type(composition.decks) == "table" and composition.decks or {}
  local columns = type(composition.columns) == "table" and composition.columns or {}
  local layers = type(composition.layers) == "table" and composition.layers or {}

  ResolumeCompositionCache.name = displayName(composition, "")
  ResolumeCompositionCache.sourceDeckCount = #decks
  ResolumeCompositionCache.sourceColumnCount = #columns
  ResolumeCompositionCache.sourceLayerCount = #layers

  for deck = 1, deckCount do
    local source = decks[deck]
    if source then
      local cached = ResolumeCompositionCache.decks[deck] or {}
      cached.id = source.id
      cached.name = indexedDisplayName(source, "Deck " .. deck, deck)
      cached.selected = parameterValue(source.selected, false) == true
      ResolumeCompositionCache.decks[deck] = cached
      setToggleState("Deck " .. deck, cached.name, cached.selected, false)
    else
      ResolumeCompositionCache.decks[deck] = nil
      setToggleState("Deck " .. deck, "", false, true)
    end
  end

  for column = 1, columnCount do
    local source = columns[column]
    if source then
      local cached = ResolumeCompositionCache.columns[column] or {}
      cached.id = source.id
      cached.name = indexedDisplayName(source, "Column " .. column, column)
      cached.connected = parameterValue(source.connected, "Empty")
      cached.selected = parameterValue(source.selected, false) == true
      ResolumeCompositionCache.columns[column] = cached
      setToggleState(
        "Column " .. column,
        cached.name,
        connectedStateIsActive(cached.connected),
        false
      )
    else
      ResolumeCompositionCache.columns[column] = nil
      setToggleState("Column " .. column, "", false, true)
    end
  end

  for layer = 1, layerCount do
    local source = layers[layer]
    if source then
      local cached = ResolumeCompositionCache.layers[layer] or { clips = {} }
      cached.id = source.id
      cached.name = indexedDisplayName(source, "Layer " .. layer, layer)
      cached.selected = parameterValue(source.selected, false) == true
      cached.clips = cached.clips or {}
      ResolumeCompositionCache.layers[layer] = cached
      setToggleState("Layer " .. layer, cached.name, cached.selected, false)

      local clips = type(source.clips) == "table" and source.clips or {}
      for column = 1, columnCount do
        local clip = clips[column]
        local connected = parameterValue(clip and clip.connected, "Empty")
        local populated = clip ~= nil and connected ~= "Empty"

        if populated then
          local cachedClip = cached.clips[column] or {}
          cachedClip.id = clip.id
          cachedClip.name = displayName(clip, string.format("L%d C%d", layer, column))
          cachedClip.connected = connected
          cached.clips[column] = cachedClip
          setToggleState(
            string.format("Clip L%d C%d", layer, column),
            cachedClip.name,
            connectedStateIsActive(connected),
            false
          )
        else
          cached.clips[column] = nil
          setToggleState(
            string.format("Clip L%d C%d", layer, column),
            "",
            false,
            true
          )
        end
      end
    else
      ResolumeCompositionCache.layers[layer] = nil
      setToggleState("Layer " .. layer, "", false, true)
      for column = 1, columnCount do
        setToggleState(
          string.format("Clip L%d C%d", layer, column),
          "",
          false,
          true
        )
      end
    end
  end

  debugLog(string.format(
    "Cached composition '%s': %d/%d decks, %d/%d columns, %d/%d layers",
    ResolumeCompositionCache.name,
    math.min(#decks, deckCount),
    #decks,
    math.min(#columns, columnCount),
    #columns,
    math.min(#layers, layerCount),
    #layers
  ))

  if synchronizeFeedbackSubscriptions then
    synchronizeFeedbackSubscriptions(true)
  end
end

local function sendSubscription(action, path)
  if connectionState ~= "connected" then return end
  ResolumeWebSocket:Write(json.encode({
    action = action,
    parameter = path
  }))
end

synchronizeFeedbackSubscriptions = function(force)
  if connectionState ~= "connected" then return end

  local desired = {}
  local visibleDecks = math.min(ResolumeCompositionCache.sourceDeckCount, deckCount)
  local visibleColumns = math.min(ResolumeCompositionCache.sourceColumnCount, columnCount)
  local visibleLayers = math.min(ResolumeCompositionCache.sourceLayerCount, layerCount)

  for deck = 1, visibleDecks do
    desired[string.format("/composition/decks/%d/select", deck)] = true
  end
  for column = 1, visibleColumns do
    desired[string.format("/composition/columns/%d/connect", column)] = true
  end
  for layer = 1, visibleLayers do
    desired[string.format("/composition/layers/%d/select", layer)] = true
    for column = 1, visibleColumns do
      desired[string.format(
        "/composition/layers/%d/clips/%d/connect",
        layer,
        column
      )] = true
    end
  end

  local obsolete = {}
  for path in pairs(subscribedFeedbackPaths) do
    if force or not desired[path] then
      table.insert(obsolete, path)
    end
  end
  for _, path in ipairs(obsolete) do
    sendSubscription("unsubscribe", path)
    subscribedFeedbackPaths[path] = nil
  end

  local subscriptionCount = 0
  for path in pairs(desired) do
    subscriptionCount = subscriptionCount + 1
    if not subscribedFeedbackPaths[path] then
      sendSubscription("subscribe", path)
      subscribedFeedbackPaths[path] = true
    end
  end

  debugLog(string.format(
    "Synchronized %d realtime feedback subscriptions%s",
    subscriptionCount,
    force and " (deck/snapshot refresh)" or ""
  ))
end

local function booleanFeedback(value)
  return value == true or value == 1 or value == "true"
end

applyParameterFeedback = function(path, value)
  if not subscribedFeedbackPaths[path] then return end

  local deck = tonumber(path:match("^/composition/decks/(%d+)/select$"))
  if deck then
    local cached = ResolumeCompositionCache.decks[deck]
    if not cached then return end
    local active = booleanFeedback(value)
    if active then
      for index, other in pairs(ResolumeCompositionCache.decks) do
        other.selected = index == deck
        setToggleState("Deck " .. index, other.name, other.selected, false)
      end
    else
      cached.selected = false
      setToggleState("Deck " .. deck, cached.name, false, false)
    end
    return
  end

  local column = tonumber(path:match("^/composition/columns/(%d+)/connect$"))
  if column then
    local cached = ResolumeCompositionCache.columns[column]
    if not cached then return end
    cached.connected = value
    setToggleState(
      "Column " .. column,
      cached.name,
      connectedStateIsActive(value),
      false
    )
    return
  end

  local layer = tonumber(path:match("^/composition/layers/(%d+)/select$"))
  if layer then
    local cached = ResolumeCompositionCache.layers[layer]
    if not cached then return end
    local active = booleanFeedback(value)
    if active then
      for index, other in pairs(ResolumeCompositionCache.layers) do
        other.selected = index == layer
        setToggleState("Layer " .. index, other.name, other.selected, false)
      end
    else
      cached.selected = false
      setToggleState("Layer " .. layer, cached.name, false, false)
    end
    return
  end

  local clipLayer, clipColumn = path:match(
    "^/composition/layers/(%d+)/clips/(%d+)/connect$"
  )
  clipLayer = tonumber(clipLayer)
  clipColumn = tonumber(clipColumn)
  if not clipLayer or not clipColumn then return end

  local cachedLayer = ResolumeCompositionCache.layers[clipLayer]
  local cachedClip = cachedLayer and cachedLayer.clips[clipColumn]
  if not cachedClip then return end

  cachedClip.connected = value
  setToggleState(
    string.format("Clip L%d C%d", clipLayer, clipColumn),
    cachedClip.name,
    connectedStateIsActive(value),
    false
  )
end

clearCompositionCache()

Timer.CallAfter(connectWebSocket, 0.1)
