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
    end
  })
end

ResolumeHealthTimer.EventHandler = checkResolumeHealth

local function startHealthCheck()
  stopHealthCheck()
  ResolumeHealthTimer:Start(healthCheckInterval)
end

local function handleWebSocketMessage(message)
  -- Composition mapping starts in M5. M4 only validates and counts messages.
  receivedMessageCount = receivedMessageCount + 1
  debugLog(string.format("Received JSON message #%d", receivedMessageCount))
end

ResolumeReceiveBufferTimer.EventHandler = function()
  clearReceiveBuffer("incomplete or invalid JSON")
end

ResolumeWebSocket.Connected = function()
  ResolumeReconnectTimer:Stop()
  connectionState = "connected"
  reconnectRequested = false
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
  scheduleReconnect(reconnectDelay)
end

ResolumeWebSocket.Closed = function()
  connectionState = "idle"
  stopHealthCheck()
  clearReceiveBuffer("WebSocket closed")

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

Timer.CallAfter(connectWebSocket, 0.1)
