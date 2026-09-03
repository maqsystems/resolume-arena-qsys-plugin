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
ResolumeDeckRefreshTimer = Timer.New()
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
local thumbnailQueue = {}
local thumbnailRequestsActive = 0
local thumbnailRequestLimit = 4
local thumbnailCache = {}
local thumbnailCacheOrder = {}
local thumbnailCacheLimit = 256
local thumbnailRequestsPending = {}
local activeLayerClips = {}
local deckRefreshToken = 0
local deckRefreshAttempt = 0
local deckRefreshSignature = nil
local deckRefreshPending = false
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
  ResolumeDeckRefreshTimer:Stop()
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

local function scheduleDeckRefresh(delay)
  if connectionState ~= "connected" then return end
  deckRefreshToken = deckRefreshToken + 1
  deckRefreshAttempt = 0
  deckRefreshSignature = nil
  ResolumeDeckRefreshTimer:Stop()
  ResolumeDeckRefreshTimer:Start(delay or 0.5)
end

ResolumeDeckRefreshTimer.EventHandler = function()
  ResolumeDeckRefreshTimer:Stop()
  if connectionState ~= "connected" or deckRefreshPending then return end

  local requestToken = deckRefreshToken
  local requestHost = activeHost
  local requestPort = activePort
  deckRefreshPending = true
  HttpClient.Get({
    Url = string.format("http://%s:%d/api/v1/composition", requestHost, requestPort),
    Headers = { Accept = "application/json" },
    Timeout = 5,
    EventHandler = function(_, code, data, errorMessage)
      deckRefreshPending = false
      if requestToken ~= deckRefreshToken
          or requestHost ~= activeHost
          or requestPort ~= activePort then
        return
      end

      if code ~= 200 or not data or #data == 0 then
        debugLog(string.format(
          "Settled composition refresh failed (HTTP %s): %s",
          tostring(code),
          tostring(errorMessage)
        ))
        return
      end

      local ok, composition = pcall(json.decode, data)
      if not ok or type(composition) ~= "table" then
        debugLog("Settled composition refresh returned invalid JSON")
        return
      end

      local signatureParts = {}
      local layers = type(composition.layers) == "table" and composition.layers or {}
      for layer = 1, #layers do
        local clips = type(layers[layer].clips) == "table" and layers[layer].clips or {}
        for column = 1, #clips do
          local clip = clips[column]
          signatureParts[#signatureParts + 1] = tostring(clip and clip.id or "-")
        end
      end
      local signature = table.concat(signatureParts, ":")
      deckRefreshAttempt = deckRefreshAttempt + 1
      if signature == deckRefreshSignature or deckRefreshAttempt >= 5 then
        applyCompositionSnapshot(composition)
        debugLog(string.format(
          "Composition settled after %d REST checks",
          deckRefreshAttempt
        ))
        return
      end

      deckRefreshSignature = signature
      ResolumeDeckRefreshTimer:Start(0.25)
    end
  })
end

local function handleWebSocketMessage(message)
  receivedMessageCount = receivedMessageCount + 1

  if message.columns and message.layers and applyCompositionSnapshot then
    debugLog(string.format("Applying composition snapshot #%d", receivedMessageCount))
    compositionReceived = true
    initialRefreshRequested = false
    applyCompositionSnapshot(message)
  elseif message.path and message.value ~= nil and applyParameterFeedback then
    applyParameterFeedback(message.path, message.value, message)
  elseif message.type == "thumbnail_update" then
    -- Some large decks first produce a transient snapshot whose clip slots are
    -- still Empty. Debounce the notification burst, then request the settled
    -- composition once Resolume has finished switching decks.
    debugLog("Thumbnail update notification received; scheduling settled refresh")
    scheduleDeckRefresh(0.5)
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
    return
  end

  ResolumeReceiveBufferTimer:Stop()
  receiveBuffer = ""
  handleWebSocketMessage(message)
end

ResolumeWebSocket.Error = function(_, errorMessage)
  connectionState = "idle"
  ResolumeDeckRefreshTimer:Stop()
  stopHealthCheck()
  clearReceiveBuffer("WebSocket error")
  setConnectionStatus(2, "WebSocket error: " .. tostring(errorMessage))
  subscribedFeedbackPaths = {}
  if clearCompositionCache then clearCompositionCache() end
  scheduleReconnect(reconnectDelay)
end

ResolumeWebSocket.Closed = function()
  connectionState = "idle"
  ResolumeDeckRefreshTimer:Stop()
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
  local inactiveBackground = view.kind == "layerCommand" and "#4f4f4f" or "#191817"
  local background = active and "#80ffd2" or inactiveBackground
  local foreground = active and "#191817" or "#ffffff"
  local baseline = math.floor(view.height / 2 + 4)

  if view.kind == "clip" or view.kind == "layer" then
    local isClip = view.kind == "clip"
    local titleHeight = 16
    local thumbnailHeight = view.height - titleHeight
    if isClip and view.state == "Missing" then
      local svg = table.concat({
        '<svg xmlns="http://www.w3.org/2000/svg" width="', view.width,
        '" height="', view.height, '" viewBox="0 0 ', view.width, ' ', view.height,
        '" preserveAspectRatio="none">',
        '<rect width="', view.width, '" height="', view.height,
        '" rx="2" fill="#0f0f0f"/></svg>'
      })
      control.Legend = json.encode({
        DrawChrome = false,
        IconData = Crypto.Base64Encode(svg)
      })
      return
    end
    local outline = ""
    if isClip and active then
      outline = table.concat({
        '<rect x="0" y="0" width="', view.width,
        '" height="', thumbnailHeight,
        '" rx="2" fill="none" stroke="#80ffd2" stroke-width="3"/>'
      })
    end
    local image = ""
    if view.thumbnailBase64 then
      image = table.concat({
        '<image href="data:image/png;base64,', view.thumbnailBase64,
        '" x="0" y="0" width="', view.width,
        '" height="', thumbnailHeight, '" preserveAspectRatio="xMidYMid slice"/>'
      })
    elseif not isClip and label ~= "" then
      local iconX = math.floor((view.width - 26) / 2)
      local iconY = math.floor((thumbnailHeight - 20) / 2)
      image = table.concat({
        '<rect x="0" y="0" width="', view.width,
        '" height="', thumbnailHeight, '" fill="#0f0f0f"/>',
        '<g fill="none" stroke="#191817" stroke-width="2">',
        '<rect x="', iconX, '" y="', iconY,
        '" width="26" height="20" rx="2"/>',
        '<circle cx="', iconX + 19, '" cy="', iconY + 6, '" r="2"/>',
        '<path d="M', iconX + 3, ' ', iconY + 16,
        ' L', iconX + 10, ' ', iconY + 10,
        ' L', iconX + 15, ' ', iconY + 14,
        ' L', iconX + 19, ' ', iconY + 11,
        ' L', iconX + 23, ' ', iconY + 16, '"/>',
        '</g>'
      })
    end

    local svg = table.concat({
      '<svg xmlns="http://www.w3.org/2000/svg" width="', view.width,
      '" height="', view.height, '" viewBox="0 0 ', view.width, ' ', view.height,
      '" preserveAspectRatio="none">',
      '<defs><clipPath id="clipTitle"><rect x="5" y="', thumbnailHeight,
      '" width="', view.width - 10, '" height="', titleHeight, '"/></clipPath></defs>',
      '<rect width="', view.width, '" height="', view.height,
      '" rx="2" fill="#191817"/>',
      image,
      outline,
      '<rect x="0" y="', thumbnailHeight, '" width="', view.width,
      '" height="', titleHeight, '" rx="2" fill="#4f4f4f"/>',
      '<text x="6" y="', view.height - 4, '" fill="#ffffff"',
      ' font-family="Roboto, Arial, sans-serif" font-size="10" ',
      'clip-path="url(#clipTitle)">', escapeXml(label), '</text>',
      '</svg>'
    })

    control.Legend = json.encode({
      DrawChrome = false,
      IconData = Crypto.Base64Encode(svg)
    })
    return
  end

  if view.kind == "column" then
    if view.state == "Missing" then
      local svg = table.concat({
        '<svg xmlns="http://www.w3.org/2000/svg" width="', view.width,
        '" height="', view.height, '" viewBox="0 0 ', view.width, ' ', view.height,
        '" preserveAspectRatio="none">',
        '<rect width="', view.width, '" height="', view.height,
        '" rx="2" fill="#0f0f0f"/></svg>'
      })
      control.Legend = json.encode({
        DrawChrome = false,
        IconData = Crypto.Base64Encode(svg)
      })
      return
    end

    local iconColor = active and "#80ffd2" or "#ffffff"
    local titleHeight = 16
    local titleY = view.height - titleHeight
    local iconCenterY = math.floor(titleY / 2)
    local icon
    if view.state == "Empty" then
      icon = table.concat({
        '<rect x="', view.width / 2 - 5, '" y="', iconCenterY - 5,
        '" width="10" height="10" fill="',
        iconColor, '"/>'
      })
    else
      icon = table.concat({
        '<path d="M ', view.width / 2 - 5, ' ', iconCenterY - 7,
        ' L ', view.width / 2 + 7, ' ', iconCenterY,
        ' L ', view.width / 2 - 5, ' ', iconCenterY + 7,
        ' Z" fill="', iconColor, '"/>'
      })
    end

    local svg = table.concat({
      '<svg xmlns="http://www.w3.org/2000/svg" width="', view.width,
      '" height="', view.height, '" viewBox="0 0 ', view.width, ' ', view.height,
      '" preserveAspectRatio="none">',
      '<rect width="', view.width, '" height="', view.height,
      '" rx="2" fill="#191817"/>',
      icon,
      '<rect x="0" y="', titleY, '" width="', view.width,
      '" height="', titleHeight, '" fill="#4f4f4f"/>',
      '<text x="', view.width / 2, '" y="', view.height - 5,
      '" fill="#ffffff" ',
      'font-family="Roboto, Arial, sans-serif" font-size="10" text-anchor="middle">',
      escapeXml(label), '</text></svg>'
    })

    control.Legend = json.encode({
      DrawChrome = false,
      IconData = Crypto.Base64Encode(svg)
    })
    return
  end

  local svg = table.concat({
    '<svg xmlns="http://www.w3.org/2000/svg" width="', view.width,
    '" height="', view.height, '" viewBox="0 0 ', view.width, ' ', view.height,
    '" preserveAspectRatio="none">',
    '<rect x="0" y="0" width="', view.width, '" height="', view.height,
    '" rx="2" fill="', background, '" stroke="none"/>',
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

local function initializeToggle(name, label, width, height, kind)
  local control = Controls[name]
  if not control then return end

  local view = {
    control = control,
    label = label,
    active = false,
    width = width,
    height = height,
    kind = kind or "standard",
    thumbnailBase64 = nil
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

local function setToggleState(name, label, active, disabled, state)
  local view = toggleViews[name]
  if not view then return end

  view.label = tostring(label or "")
  view.active = active == true
  view.state = state
  if disabled and (view.kind == "clip" or view.kind == "layer") then
    view.thumbnailBase64 = nil
  end
  applyingCacheFeedback = true
  view.control.Boolean = view.active
  view.control.IsDisabled = disabled == true
  applyingCacheFeedback = false
  renderToggle(view)
end

local function setToggleThumbnail(name, thumbnailBase64)
  local view = toggleViews[name]
  if not view or (view.kind ~= "clip" and view.kind ~= "layer") then return end
  view.thumbnailBase64 = thumbnailBase64
  renderToggle(view)
end

local function setKnobState(name, value, disabled)
  local control = Controls[name]
  if not control then return end
  applyingCacheFeedback = true
  control.Value = tonumber(value) or 0
  control.IsDisabled = disabled == true
  applyingCacheFeedback = false
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

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function resolumeId(value)
  if type(value) == "number" then
    return string.format("%.0f", value)
  end
  return tostring(value)
end

local deckCount = Properties["Deck Count"].Value
local columnCount = Properties["Maximum Column Count"].Value
local layerCount = Properties["Maximum Layer Count"].Value

initializeToggle("Composition Clear", "X", 36, 14, "layerCommand")
initializeToggle("Composition Bypass", "B", 36, 14, "layerCommand")
initializeToggle("Global Play Backwards", "◀", 31, 14, "layerCommand")
initializeToggle("Global Pause", "Ⅱ", 31, 14, "layerCommand")
initializeToggle("Global Play Forward", "▶", 28, 14, "layerCommand")

for deck = 1, deckCount do
  initializeToggle("Deck " .. deck, "Deck " .. deck, 93, 26)
end

for column = 1, columnCount do
  initializeToggle("Column " .. column, "Column " .. column, 93, 30, "column")
end

for layer = 1, layerCount do
  initializeToggle("Layer " .. layer, "Layer " .. layer, 93, 61, "layer")
  initializeToggle("Layer Clear " .. layer, "X", 36, 44, "layerCommand")
  initializeToggle("Layer Bypass " .. layer, "B", 36, 44, "layerCommand")
  initializeToggle("Layer Solo " .. layer, "S", 36, 44, "layerCommand")

  for column = 1, columnCount do
    initializeToggle(
      string.format("Clip L%d C%d", layer, column),
      string.format("L%d C%d", layer, column),
      93,
      61,
      "clip"
    )
  end
end

for link = 1, 8 do
  Controls["Dashboard Link Name " .. link].String = ""
  setKnobState("Dashboard Link " .. link, 0, true)
end

ResolumeCompositionCache = {
  name = "",
  bypassed = false,
  bypassedId = nil,
  master = 1,
  masterId = nil,
  speed = 1,
  speedId = nil,
  sourceDeckCount = 0,
  sourceColumnCount = 0,
  sourceLayerCount = 0,
  decks = {},
  columns = {},
  layers = {},
  dashboardLinks = {}
}

local function updateLayerThumbnail(layer)
  local cachedLayer = ResolumeCompositionCache.layers[layer]
  if not cachedLayer then
    setToggleThumbnail("Layer " .. layer, nil)
    return
  end

  local activeClip = cachedLayer.activeClip
  local thumbnail = activeClip and activeClip.thumbnailBase64 or nil
  local clipName = activeClip and activeClip.name or ""

  if activeClip then
    for column = 1, columnCount do
      local clip = cachedLayer.clips[column]
      if clip and clip.id == activeClip.id then
        -- During a deck transition the visible cell can exist before its PNG
        -- has arrived. Never let that temporary nil erase the last valid image
        -- already cached for the layer's active clip.
        if clip.thumbnailBase64 then
          thumbnail = clip.thumbnailBase64
          activeClip.thumbnailBase64 = thumbnail
        end
        break
      end
    end
  end
  setToggleState("Layer " .. layer, clipName, false, false)
  setToggleThumbnail("Layer " .. layer, thumbnail)
end

local pumpThumbnailQueue

local function completeThumbnailRequest(task, code, data, errorMessage)
  thumbnailRequestsActive = math.max(0, thumbnailRequestsActive - 1)
  thumbnailRequestsPending[task.key] = nil

  if connectionState ~= "connected"
      or task.host ~= activeHost
      or task.port ~= activePort then
    debugLog("Ignored stale thumbnail " .. task.debugName)
    pumpThumbnailQueue()
    return
  end

  if code ~= 200 or not data or #data == 0 then
    debugLog(string.format(
      "Thumbnail %s failed (HTTP %s): %s",
      task.debugName,
      tostring(code),
      tostring(errorMessage)
    ))
    pumpThumbnailQueue()
    return
  end

  local existingThumbnail = thumbnailCache[task.clipId]
  local existingVersion = existingThumbnail and tonumber(existingThumbnail.lastUpdate)
  local receivedVersion = tonumber(task.lastUpdate)
  if existingVersion and receivedVersion and existingVersion > receivedVersion then
    debugLog("Ignored older thumbnail version " .. task.debugName)
    pumpThumbnailQueue()
    return
  end

  local thumbnailBase64 = Crypto.Base64Encode(data)
  if not thumbnailCache[task.clipId] then
    thumbnailCacheOrder[#thumbnailCacheOrder + 1] = task.clipId
  end
  thumbnailCache[task.clipId] = {
    lastUpdate = task.lastUpdate,
    thumbnailBase64 = thumbnailBase64
  }
  while #thumbnailCacheOrder > thumbnailCacheLimit do
    local expiredId = table.remove(thumbnailCacheOrder, 1)
    thumbnailCache[expiredId] = nil
  end
  for layer = 1, layerCount do
    local cachedLayer = ResolumeCompositionCache.layers[layer]
    local layerChanged = false
    if cachedLayer then
      if cachedLayer.activeClip and cachedLayer.activeClip.id == task.clipId then
        cachedLayer.activeClip.thumbnailBase64 = thumbnailBase64
        layerChanged = true
      end
      for column = 1, columnCount do
        local cachedClip = cachedLayer.clips[column]
        if cachedClip and cachedClip.id == task.clipId then
          cachedClip.thumbnailBase64 = thumbnailBase64
          setToggleThumbnail(
            string.format("Clip L%d C%d", layer, column),
            thumbnailBase64
          )
          layerChanged = true
        end
      end
    end
    if layerChanged then updateLayerThumbnail(layer) end
  end
  debugLog(string.format(
    "Thumbnail %s received: %d bytes",
    task.debugName,
    #data
  ))
  pumpThumbnailQueue()
end

pumpThumbnailQueue = function()
  while thumbnailRequestsActive < thumbnailRequestLimit and #thumbnailQueue > 0 do
    local task = table.remove(thumbnailQueue, 1)
    thumbnailRequestsActive = thumbnailRequestsActive + 1
    HttpClient.Get({
      Url = task.url,
      Headers = { Accept = "image/png,image/*" },
      Timeout = 5,
      EventHandler = function(_, code, data, errorMessage)
        completeThumbnailRequest(task, code, data, errorMessage)
      end
    })
  end
end

local function queueThumbnail(task)
  if not resolumeLook or connectionState ~= "connected" then return end
  task.key = resolumeId(task.clipId) .. ":" .. tostring(task.lastUpdate or "")
  if thumbnailRequestsPending[task.key] then return end
  task.host = activeHost
  task.port = activePort
  thumbnailRequestsPending[task.key] = true
  if task.priority then
    table.insert(thumbnailQueue, 1, task)
  else
    thumbnailQueue[#thumbnailQueue + 1] = task
  end
  pumpThumbnailQueue()
end

local function clearQueuedThumbnailRequests()
  for _, task in ipairs(thumbnailQueue) do
    thumbnailRequestsPending[task.key] = nil
  end
  thumbnailQueue = {}
end

local function fetchClipThumbnail(layer, column, clipId, lastUpdate)
  queueThumbnail({
    clipId = clipId,
    lastUpdate = lastUpdate,
    debugName = string.format("L%d C%d", layer, column),
    url = string.format(
      "http://%s:%d/api/v1/composition/clips/by-id/%s/thumbnail",
      activeHost, activePort, resolumeId(clipId)
    )
  })
end

local function fetchActiveClipThumbnail(layer, activeClip)
  local path = activeClip.thumbnailPath
  if not path or path == "" then
    path = string.format(
      "/api/v1/composition/clips/by-id/%s/thumbnail",
      resolumeId(activeClip.id)
    )
  end
  queueThumbnail({
    clipId = activeClip.id,
    lastUpdate = activeClip.lastUpdate,
    priority = true,
    debugName = string.format("active L%d", layer),
    url = string.format("http://%s:%d%s", activeHost, activePort, path)
  })
end

local function ensureActiveLayerThumbnail(layer, activeClip)
  if not activeClip then return end

  local cachedThumbnail = thumbnailCache[activeClip.id]
  if cachedThumbnail and cachedThumbnail.thumbnailBase64 then
    activeClip.thumbnailBase64 = cachedThumbnail.thumbnailBase64
    updateLayerThumbnail(layer)
    debugLog(string.format(
      "Active layer L%d thumbnail restored from clip cache (%s)",
      layer,
      resolumeId(activeClip.id)
    ))
    return
  end

  debugLog(string.format(
    "Active layer L%d thumbnail requested by clip ID %s",
    layer,
    resolumeId(activeClip.id)
  ))
  fetchActiveClipThumbnail(layer, activeClip)
end

clearCompositionCache = function()
  clearQueuedThumbnailRequests()
  thumbnailCache = {}
  thumbnailCacheOrder = {}
  activeLayerClips = {}
  ResolumeCompositionCache.name = ""
  ResolumeCompositionCache.sourceDeckCount = 0
  ResolumeCompositionCache.sourceColumnCount = 0
  ResolumeCompositionCache.sourceLayerCount = 0
  ResolumeCompositionCache.bypassed = false
  ResolumeCompositionCache.bypassedId = nil
  ResolumeCompositionCache.masterId = nil
  ResolumeCompositionCache.speedId = nil
  setToggleState("Composition Clear", "X", false, true)
  setToggleState("Composition Bypass", "B", false, true)
  setKnobState("Composition Master", 0, true)
  setKnobState("Composition Speed", 0, true)
  setToggleState("Global Play Backwards", "◀", false, true)
  setToggleState("Global Pause", "Ⅱ", false, true)
  setToggleState("Global Play Forward", "▶", false, true)

  for link = 1, 8 do
    ResolumeCompositionCache.dashboardLinks[link] = nil
    Controls["Dashboard Link Name " .. link].String = ""
    setKnobState("Dashboard Link " .. link, 0, true)
  end

  for deck = 1, deckCount do
    ResolumeCompositionCache.decks[deck] = nil
    setToggleState("Deck " .. deck, "", false, true)
  end

  for column = 1, columnCount do
    ResolumeCompositionCache.columns[column] = nil
    setToggleState("Column " .. column, "", false, true, "Missing")
  end

  for layer = 1, layerCount do
    ResolumeCompositionCache.layers[layer] = nil
    setToggleState("Layer " .. layer, "", false, true)
    Controls["Layer Name " .. layer].String = ""
    setToggleState("Layer Clear " .. layer, "X", false, true)
    setToggleState("Layer Bypass " .. layer, "B", false, true)
    setToggleState("Layer Solo " .. layer, "S", false, true)
    setKnobState("Layer Master " .. layer, 0, true)
    setKnobState("Layer Audio " .. layer, -192, true)
    setKnobState("Layer Video " .. layer, 0, true)
    for column = 1, columnCount do
      setToggleState(string.format("Clip L%d C%d", layer, column), "", false, true)
    end
  end
end

applyCompositionSnapshot = function(composition)
  clearQueuedThumbnailRequests()
  local decks = type(composition.decks) == "table" and composition.decks or {}
  local columns = type(composition.columns) == "table" and composition.columns or {}
  local layers = type(composition.layers) == "table" and composition.layers or {}

  ResolumeCompositionCache.name = displayName(composition, "")
  ResolumeCompositionCache.bypassed = parameterValue(composition.bypassed, false) == true
  ResolumeCompositionCache.bypassedId = composition.bypassed and composition.bypassed.id
  ResolumeCompositionCache.master = parameterValue(composition.master, 1)
  ResolumeCompositionCache.masterId = composition.master and composition.master.id
  ResolumeCompositionCache.speed = parameterValue(composition.speed, 1)
  ResolumeCompositionCache.speedId = composition.speed and composition.speed.id
  setToggleState("Composition Clear", "X", false, false)
  setToggleState("Composition Bypass", "B", ResolumeCompositionCache.bypassed, false)
  setKnobState("Composition Master", ResolumeCompositionCache.master * 100, false)
  setKnobState("Composition Speed", ResolumeCompositionCache.speed, false)
  setToggleState("Global Play Backwards", "◀", false, false)
  setToggleState("Global Pause", "Ⅱ", false, false)
  setToggleState("Global Play Forward", "▶", false, false)

  local dashboard = type(composition.dashboard) == "table"
    and composition.dashboard or {}
  for link = 1, 8 do
    local parameter = dashboard["Link " .. link]
    if type(parameter) == "table" and parameter.id then
      local cachedLink = ResolumeCompositionCache.dashboardLinks[link] or {}
      cachedLink.id = parameter.id
      cachedLink.value = clamp(tonumber(parameter.value) or 0, 0, 1)
      cachedLink.name = parameter.view
        and parameter.view.alternative_name
        or ("Link " .. link)
      ResolumeCompositionCache.dashboardLinks[link] = cachedLink
      Controls["Dashboard Link Name " .. link].String = cachedLink.name
      setKnobState("Dashboard Link " .. link, cachedLink.value, false)
    else
      ResolumeCompositionCache.dashboardLinks[link] = nil
      Controls["Dashboard Link Name " .. link].String = "Not assigned"
      setKnobState("Dashboard Link " .. link, 0, true)
    end
  end
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
        false,
        cached.connected
      )
    else
      ResolumeCompositionCache.columns[column] = nil
      setToggleState("Column " .. column, "", false, true, "Missing")
    end
  end

  for layer = 1, layerCount do
    local source = layers[layer]
    if source then
      local cached = ResolumeCompositionCache.layers[layer] or { clips = {} }
      cached.id = source.id
      cached.name = indexedDisplayName(source, "Layer " .. layer, layer)
      cached.bypassed = parameterValue(source.bypassed, false) == true
      cached.bypassedId = source.bypassed and source.bypassed.id
      cached.solo = parameterValue(source.solo, false) == true
      cached.soloId = source.solo and source.solo.id
      cached.master = parameterValue(source.master, 1)
      cached.masterId = source.master and source.master.id
      cached.audio = parameterValue(source.audio and source.audio.volume, 0)
      cached.audioId = source.audio and source.audio.volume and source.audio.volume.id
      cached.video = parameterValue(source.video and source.video.opacity, 1)
      cached.videoId = source.video and source.video.opacity and source.video.opacity.id
      cached.clips = cached.clips or {}

      local sourceActiveClip = source.active_clip
      if type(sourceActiveClip) == "table" and sourceActiveClip.id then
        local previousActive = activeLayerClips[layer]
        local activeLastUpdate = sourceActiveClip.thumbnail
          and sourceActiveClip.thumbnail.last_update
          and tostring(sourceActiveClip.thumbnail.last_update)
        local activeCache = thumbnailCache[sourceActiveClip.id]
        local activeClip = {
          id = sourceActiveClip.id,
          name = displayName(sourceActiveClip, ""),
          thumbnailPath = sourceActiveClip.thumbnail and sourceActiveClip.thumbnail.path,
          lastUpdate = activeLastUpdate,
          thumbnailBase64 = activeCache
            and (activeLastUpdate == nil or activeCache.lastUpdate == activeLastUpdate)
            and activeCache.thumbnailBase64
            or (previousActive
              and previousActive.id == sourceActiveClip.id
              and (activeLastUpdate == nil
                or previousActive.lastUpdate == activeLastUpdate)
              and previousActive.thumbnailBase64
              or nil),
          playDirectionId = sourceActiveClip.transport
            and sourceActiveClip.transport.controls
            and sourceActiveClip.transport.controls.playdirection
            and sourceActiveClip.transport.controls.playdirection.id
        }
        activeLayerClips[layer] = activeClip
        cached.activeClip = activeClip
      else
        -- A deck snapshot is allowed to omit active_clip transiently. Keep the
        -- last confirmed layer state; clip disconnect feedback clears it.
        cached.activeClip = activeLayerClips[layer]
      end
      ResolumeCompositionCache.layers[layer] = cached
      setToggleState("Layer " .. layer, cached.name, false, false)
      Controls["Layer Name " .. layer].String = cached.name
      setToggleState("Layer Clear " .. layer, "X", false, false)
      setToggleState("Layer Bypass " .. layer, "B", cached.bypassed, false)
      setToggleState("Layer Solo " .. layer, "S", cached.solo, false)
      setKnobState("Layer Master " .. layer, cached.master * 100, false)
      setKnobState("Layer Audio " .. layer, cached.audio, false)
      setKnobState("Layer Video " .. layer, cached.video * 100, false)

      -- The active layer clip is independent from the selected deck. Render
      -- and fetch it before starting any ordinary grid thumbnail requests.
      updateLayerThumbnail(layer)
      ensureActiveLayerThumbnail(layer, cached.activeClip)

      local clips = type(source.clips) == "table" and source.clips or {}
      for column = 1, columnCount do
        local clip = clips[column]
        local connected = parameterValue(clip and clip.connected, "Empty")
        local populated = clip ~= nil and connected ~= "Empty"

        if populated then
          local cachedClip = cached.clips[column] or {}
          local previousId = cachedClip.id
          local previousLastUpdate = cachedClip.lastUpdate
          local lastUpdate = clip.thumbnail and tostring(clip.thumbnail.last_update or "")
          local sharedThumbnail = thumbnailCache[clip.id]
          cachedClip.id = clip.id
          cachedClip.name = displayName(clip, string.format("L%d C%d", layer, column))
          cachedClip.connected = connected
          cachedClip.lastUpdate = lastUpdate
          if sharedThumbnail and sharedThumbnail.lastUpdate == lastUpdate then
            cachedClip.thumbnailBase64 = sharedThumbnail.thumbnailBase64
          elseif previousId ~= clip.id or previousLastUpdate ~= lastUpdate then
            cachedClip.thumbnailBase64 = nil
          end
          cached.clips[column] = cachedClip
          setToggleState(
            string.format("Clip L%d C%d", layer, column),
            cachedClip.name,
            connectedStateIsActive(connected),
            false,
            connected
          )
          setToggleThumbnail(
            string.format("Clip L%d C%d", layer, column),
            cachedClip.thumbnailBase64
          )
          if not cachedClip.thumbnailBase64 then
            fetchClipThumbnail(layer, column, clip.id, lastUpdate)
          end
        else
          cached.clips[column] = nil
          local missingColumn = columns[column] == nil
          setToggleState(
            string.format("Clip L%d C%d", layer, column),
            "",
            false,
            true,
            missingColumn and "Missing" or "Empty"
          )
        end
      end
      if cached.activeClip then
        for column = 1, columnCount do
          local visibleClip = cached.clips[column]
          if visibleClip and visibleClip.id == cached.activeClip.id then
            if visibleClip.thumbnailBase64 then
              cached.activeClip.thumbnailBase64 = visibleClip.thumbnailBase64
            end
            break
          end
        end
      end
      updateLayerThumbnail(layer)
    else
      activeLayerClips[layer] = nil
      ResolumeCompositionCache.layers[layer] = nil
      setToggleState("Layer " .. layer, "", false, true)
      Controls["Layer Name " .. layer].String = ""
      setToggleState("Layer Clear " .. layer, "X", false, true)
      setToggleState("Layer Bypass " .. layer, "B", false, true)
      setToggleState("Layer Solo " .. layer, "S", false, true)
      setKnobState("Layer Master " .. layer, 0, true)
      setKnobState("Layer Audio " .. layer, -192, true)
      setKnobState("Layer Video " .. layer, 0, true)
      for column = 1, columnCount do
        local missingColumn = columns[column] == nil
        setToggleState(
          string.format("Clip L%d C%d", layer, column),
          "",
          false,
          true,
          missingColumn and "Missing" or "Empty"
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

  local compositionBypassPath = "/composition/bypassed"
  desired[compositionBypassPath] = compositionBypassPath
  if ResolumeCompositionCache.masterId then
    desired["/composition/master"] =
      "/parameter/by-id/" .. tostring(ResolumeCompositionCache.masterId)
  end
  if ResolumeCompositionCache.speedId then
    desired["/composition/speed"] =
      "/parameter/by-id/" .. tostring(ResolumeCompositionCache.speedId)
  end
  for link = 1, 8 do
    local cachedLink = ResolumeCompositionCache.dashboardLinks[link]
    if cachedLink and cachedLink.id then
      desired["/composition/dashboard/link" .. link] =
        "/parameter/by-id/" .. resolumeId(cachedLink.id)
    end
  end

  for deck = 1, visibleDecks do
    local path = string.format("/composition/decks/%d/select", deck)
    desired[path] = path
  end
  for column = 1, visibleColumns do
    local path = string.format("/composition/columns/%d/connect", column)
    desired[path] = path
  end
  for layer = 1, visibleLayers do
    local cachedLayer = ResolumeCompositionCache.layers[layer]
    local namePath = string.format("/composition/layers/%d/name", layer)
    local bypassPath = string.format("/composition/layers/%d/bypassed", layer)
    local soloPath = string.format("/composition/layers/%d/solo", layer)
    desired[namePath] = namePath
    desired[bypassPath] = bypassPath
    desired[soloPath] = soloPath
    if cachedLayer and cachedLayer.masterId then
      desired[string.format("/composition/layers/%d/master", layer)] =
        "/parameter/by-id/" .. tostring(cachedLayer.masterId)
    end
    if cachedLayer and cachedLayer.audioId then
      desired[string.format("/composition/layers/%d/audio/volume", layer)] =
        "/parameter/by-id/" .. tostring(cachedLayer.audioId)
    end
    if cachedLayer and cachedLayer.videoId then
      desired[string.format("/composition/layers/%d/video/opacity", layer)] =
        "/parameter/by-id/" .. tostring(cachedLayer.videoId)
    end
    for column = 1, visibleColumns do
      local connectPath = string.format(
        "/composition/layers/%d/clips/%d/connect",
        layer,
        column
      )
      desired[connectPath] = connectPath
      local namePath = string.format(
        "/composition/layers/%d/clips/%d/name",
        layer,
        column
      )
      desired[namePath] = namePath
    end
  end

  local obsolete = {}
  for path in pairs(subscribedFeedbackPaths) do
    if force or not desired[path] then
      table.insert(obsolete, path)
    end
  end
  for _, path in ipairs(obsolete) do
    sendSubscription("unsubscribe", subscribedFeedbackPaths[path])
    subscribedFeedbackPaths[path] = nil
  end

  local subscriptionCount = 0
  for path, requestPath in pairs(desired) do
    subscriptionCount = subscriptionCount + 1
    if not subscribedFeedbackPaths[path] then
      sendSubscription("subscribe", requestPath)
      subscribedFeedbackPaths[path] = requestPath
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

applyParameterFeedback = function(path, value, message)
  if not subscribedFeedbackPaths[path] then return end

  if path == "/composition/bypassed" then
    ResolumeCompositionCache.bypassed = booleanFeedback(value)
    setToggleState(
      "Composition Bypass",
      "B",
      ResolumeCompositionCache.bypassed,
      false
    )
    return
  elseif path == "/composition/master" then
    ResolumeCompositionCache.master = tonumber(value) or ResolumeCompositionCache.master
    setKnobState("Composition Master", ResolumeCompositionCache.master * 100, false)
    return
  elseif path == "/composition/speed" then
    ResolumeCompositionCache.speed = tonumber(value) or ResolumeCompositionCache.speed
    setKnobState("Composition Speed", ResolumeCompositionCache.speed, false)
    return
  end

  local dashboardLink = tonumber(path:match("^/composition/dashboard/link(%d+)$"))
  if dashboardLink and dashboardLink >= 1 and dashboardLink <= 8 then
    local cachedLink = ResolumeCompositionCache.dashboardLinks[dashboardLink]
    if not cachedLink then return end
    cachedLink.value = clamp(tonumber(value) or cachedLink.value, 0, 1)
    local view = type(message) == "table" and message.view or nil
    if not view and type(value) == "table" then view = value.view end
    if type(view) == "table"
        and view.alternative_name ~= nil
        and tostring(view.alternative_name) ~= "" then
      cachedLink.name = tostring(view.alternative_name)
      Controls["Dashboard Link Name " .. dashboardLink].String = cachedLink.name
    end
    setKnobState("Dashboard Link " .. dashboardLink, cachedLink.value, false)
    return
  end

  local nameLayer, nameColumn = path:match(
    "^/composition/layers/(%d+)/clips/(%d+)/name$"
  )
  nameLayer = tonumber(nameLayer)
  nameColumn = tonumber(nameColumn)
  if nameLayer and nameColumn then
    local cachedLayer = ResolumeCompositionCache.layers[nameLayer]
    local cachedClip = cachedLayer and cachedLayer.clips[nameColumn]
    if not cachedClip then return end

    cachedClip.name = tostring(value or "")
    setToggleState(
      string.format("Clip L%d C%d", nameLayer, nameColumn),
      cachedClip.name,
      connectedStateIsActive(cachedClip.connected),
      false,
      cachedClip.connected
    )
    updateLayerThumbnail(nameLayer)
    return
  end

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
      false,
      value
    )
    return
  end

  local layer, layerParameter = path:match(
    "^/composition/layers/(%d+)/([%a]+)$"
  )
  layer = tonumber(layer)
  if layer and (
      layerParameter == "bypassed"
      or layerParameter == "solo"
      or layerParameter == "master"
      or layerParameter == "name"
    ) then
    local cached = ResolumeCompositionCache.layers[layer]
    if not cached then return end
    if layerParameter == "name" then
      cached.name = tostring(value or ""):gsub("#", tostring(layer))
      Controls["Layer Name " .. layer].String = cached.name
    elseif layerParameter == "bypassed" then
      cached.bypassed = booleanFeedback(value)
      setToggleState("Layer Bypass " .. layer, "B", cached.bypassed, false)
    elseif layerParameter == "solo" then
      cached.solo = booleanFeedback(value)
      setToggleState("Layer Solo " .. layer, "S", cached.solo, false)
    else
      cached.master = tonumber(value) or cached.master
      setKnobState("Layer Master " .. layer, cached.master * 100, false)
    end
    return
  end

  local audioLayer = tonumber(path:match(
    "^/composition/layers/(%d+)/audio/volume$"
  ))
  if audioLayer then
    local cached = ResolumeCompositionCache.layers[audioLayer]
    if not cached then return end
    cached.audio = tonumber(value) or cached.audio
    setKnobState("Layer Audio " .. audioLayer, cached.audio, false)
    return
  end

  local videoLayer = tonumber(path:match(
    "^/composition/layers/(%d+)/video/opacity$"
  ))
  if videoLayer then
    local cached = ResolumeCompositionCache.layers[videoLayer]
    if not cached then return end
    cached.video = tonumber(value) or cached.video
    setKnobState("Layer Video " .. videoLayer, cached.video * 100, false)
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
  if connectedStateIsActive(value) then
    local previousActive = activeLayerClips[clipLayer]
    activeLayerClips[clipLayer] = {
      id = cachedClip.id,
      name = cachedClip.name,
      lastUpdate = cachedClip.lastUpdate,
      thumbnailBase64 = cachedClip.thumbnailBase64,
      playDirectionId = previousActive
        and previousActive.id == cachedClip.id
        and previousActive.playDirectionId
        or nil
    }
    cachedLayer.activeClip = activeLayerClips[clipLayer]
  elseif cachedLayer.activeClip and cachedLayer.activeClip.id == cachedClip.id then
    activeLayerClips[clipLayer] = nil
    cachedLayer.activeClip = nil
  end
  setToggleState(
    string.format("Clip L%d C%d", clipLayer, clipColumn),
    cachedClip.name,
    connectedStateIsActive(value),
    false,
    value
  )
  updateLayerThumbnail(clipLayer)
end

ResolumeLayerCommandTimers = {}

local function sendParameterById(parameterId, value)
  if connectionState ~= "connected" or not parameterId then return false end
  ResolumeWebSocket:Write(json.encode({
    action = "set",
    parameter = "/parameter/by-id/" .. resolumeId(parameterId),
    value = value
  }))
  return true
end

local function queueLayerParameter(controlName, parameterId, value)
  if connectionState ~= "connected" or not parameterId then
    Controls["Status Text"].String = "Layer command unavailable while disconnected"
    return
  end

  local pending = ResolumeLayerCommandTimers[controlName]
  if not pending then
    pending = {
      timer = Timer.New(),
      parameterId = parameterId,
      value = value,
      scheduled = false,
      dirty = false
    }
    ResolumeLayerCommandTimers[controlName] = pending
    pending.timer.EventHandler = function()
      pending.timer:Stop()
      pending.scheduled = false
      if pending.dirty then
        pending.dirty = false
        sendParameterById(pending.parameterId, pending.value)
        pending.scheduled = true
        pending.timer:Start(0.025)
      end
    end
  end

  pending.parameterId = parameterId
  pending.value = value
  if pending.scheduled then
    pending.dirty = true
    return
  end

  pending.dirty = false
  sendParameterById(pending.parameterId, pending.value)
  pending.scheduled = true
  pending.timer:Start(0.025)
end

for link = 1, 8 do
  local linkIndex = link
  Controls["Dashboard Link " .. linkIndex].EventHandler = function(control)
    if applyingCacheFeedback then return end
    local cachedLink = ResolumeCompositionCache.dashboardLinks[linkIndex]
    if not cachedLink then
      Controls["Status Text"].String = string.format(
        "Dashboard Link %d is not assigned",
        linkIndex
      )
      return
    end

    local requested = clamp(control.Value, 0, 1)
    setKnobState("Dashboard Link " .. linkIndex, cachedLink.value, false)
    queueLayerParameter(
      "Dashboard Link " .. linkIndex,
      cachedLink.id,
      requested
    )
  end
end

local function postCompositionAction(path, failureLabel)
  if connectionState ~= "connected" then
    Controls["Status Text"].String = failureLabel .. " ignored while disconnected"
    return
  end
  HttpClient.Post({
    Url = string.format("http://%s:%d/api/v1%s", activeHost, activePort, path),
    Data = "",
    Headers = { ["Content-Type"] = "application/json" },
    Timeout = 2,
    EventHandler = function(_, code, _, errorMessage)
      if code ~= 200 and code ~= 204 then
        Controls["Status Text"].String = string.format(
          "%s failed (HTTP %s): %s",
          failureLabel,
          tostring(code),
          tostring(errorMessage)
        )
      end
    end
  })
end

for deck = 1, deckCount do
  local deckIndex = deck
  Controls["Deck " .. deckIndex].EventHandler = function()
    local cached = ResolumeCompositionCache.decks[deckIndex]
    if not cached then return end

    setToggleState("Deck " .. deckIndex, cached.name, cached.selected, false)
    postCompositionAction(
      string.format("/composition/decks/%d/select", deckIndex),
      string.format("Deck %d select", deckIndex)
    )
    scheduleDeckRefresh(0.5)
  end
end

for column = 1, columnCount do
  local columnIndex = column
  Controls["Column " .. columnIndex].EventHandler = function()
    local cached = ResolumeCompositionCache.columns[columnIndex]
    if not cached then return end

    setToggleState(
      "Column " .. columnIndex,
      cached.name,
      connectedStateIsActive(cached.connected),
      false,
      cached.connected
    )
    postCompositionAction(
      string.format("/composition/columns/%d/connect", columnIndex),
      string.format("Column %d connect", columnIndex)
    )
  end
end

for layer = 1, layerCount do
  local layerIndex = layer
  for column = 1, columnCount do
    local columnIndex = column
    local controlName = string.format("Clip L%d C%d", layerIndex, columnIndex)

    Controls[controlName].EventHandler = function()
      local cachedLayer = ResolumeCompositionCache.layers[layerIndex]
      local cachedClip = cachedLayer and cachedLayer.clips[columnIndex]
      if not cachedClip then return end

      setToggleState(
        controlName,
        cachedClip.name,
        connectedStateIsActive(cachedClip.connected),
        false,
        cachedClip.connected
      )
      postCompositionAction(
        string.format(
          "/composition/layers/%d/clips/%d/connect",
          layerIndex,
          columnIndex
        ),
        string.format("Clip L%d C%d connect", layerIndex, columnIndex)
      )
    end
  end
end

Controls["Composition Clear"].EventHandler = function()
  setToggleState("Composition Clear", "X", false, false)
  postCompositionAction("/composition/disconnect-all", "Composition clear")
end

Controls["Composition Bypass"].EventHandler = function(control)
  local requested = control.Boolean
  setToggleState("Composition Bypass", "B", ResolumeCompositionCache.bypassed, false)
  queueLayerParameter("Composition Bypass", ResolumeCompositionCache.bypassedId, requested)
end

Controls["Composition Master"].EventHandler = function(control)
  if applyingCacheFeedback then return end
  local requested = control.Value / 100
  setKnobState("Composition Master", ResolumeCompositionCache.master * 100, false)
  queueLayerParameter("Composition Master", ResolumeCompositionCache.masterId, requested)
end

Controls["Composition Speed"].EventHandler = function(control)
  if applyingCacheFeedback then return end
  local requested = control.Value
  setKnobState("Composition Speed", ResolumeCompositionCache.speed, false)
  queueLayerParameter("Composition Speed", ResolumeCompositionCache.speedId, requested)
end

local function sendGlobalDirection(controlName, label, value)
  setToggleState(controlName, label, false, false)
  if connectionState ~= "connected" then
    Controls["Status Text"].String = "Global transport ignored while disconnected"
    return
  end

  local commandCount = 0
  for layer = 1, layerCount do
    local cachedLayer = ResolumeCompositionCache.layers[layer]
    local activeClip = cachedLayer and cachedLayer.activeClip
    if activeClip and activeClip.playDirectionId then
      if sendParameterById(activeClip.playDirectionId, value) then
        commandCount = commandCount + 1
      end
    end
  end

  if commandCount == 0 then
    Controls["Status Text"].String = "Global transport unavailable: no active clip"
  end
end

Controls["Global Play Backwards"].EventHandler = function()
  sendGlobalDirection("Global Play Backwards", "◀", "<")
end
Controls["Global Pause"].EventHandler = function()
  sendGlobalDirection("Global Pause", "Ⅱ", "||")
end
Controls["Global Play Forward"].EventHandler = function()
  sendGlobalDirection("Global Play Forward", "▶", ">")
end

for layer = 1, layerCount do
  local layerIndex = layer

  Controls["Layer Clear " .. layerIndex].EventHandler = function(control)
    setToggleState("Layer Clear " .. layerIndex, "X", false, false)
    if connectionState ~= "connected" then
      Controls["Status Text"].String = "Clear ignored while disconnected"
      return
    end

    HttpClient.Post({
      Url = string.format(
        "http://%s:%d/api/v1/composition/layers/%d/clear",
        activeHost,
        activePort,
        layerIndex
      ),
      Data = "",
      Headers = { ["Content-Type"] = "application/json" },
      Timeout = 2,
      EventHandler = function(_, code, _, errorMessage)
        if code ~= 200 and code ~= 204 then
          Controls["Status Text"].String = string.format(
            "Layer %d clear failed (HTTP %s): %s",
            layerIndex,
            tostring(code),
            tostring(errorMessage)
          )
        end
      end
    })
  end

  Controls["Layer Bypass " .. layerIndex].EventHandler = function(control)
    local cached = ResolumeCompositionCache.layers[layerIndex]
    if not cached then return end
    local requested = control.Boolean
    setToggleState("Layer Bypass " .. layerIndex, "B", cached.bypassed, false)
    queueLayerParameter(
      "Layer Bypass " .. layerIndex,
      cached.bypassedId,
      requested
    )
  end

  Controls["Layer Solo " .. layerIndex].EventHandler = function(control)
    local cached = ResolumeCompositionCache.layers[layerIndex]
    if not cached then return end
    local requested = control.Boolean
    setToggleState("Layer Solo " .. layerIndex, "S", cached.solo, false)
    queueLayerParameter("Layer Solo " .. layerIndex, cached.soloId, requested)
  end

  Controls["Layer Master " .. layerIndex].EventHandler = function(control)
    if applyingCacheFeedback then return end
    local cached = ResolumeCompositionCache.layers[layerIndex]
    if not cached then return end
    local requested = control.Value / 100
    setKnobState("Layer Master " .. layerIndex, cached.master * 100, false)
    queueLayerParameter("Layer Master " .. layerIndex, cached.masterId, requested)
  end


  Controls["Layer Audio " .. layerIndex].EventHandler = function(control)
    if applyingCacheFeedback then return end
    local cached = ResolumeCompositionCache.layers[layerIndex]
    if not cached then return end
    local requested = control.Value
    setKnobState("Layer Audio " .. layerIndex, cached.audio, false)
    queueLayerParameter("Layer Audio " .. layerIndex, cached.audioId, requested)
  end

  Controls["Layer Video " .. layerIndex].EventHandler = function(control)
    if applyingCacheFeedback then return end
    local cached = ResolumeCompositionCache.layers[layerIndex]
    if not cached then return end
    local requested = control.Value / 100
    setKnobState("Layer Video " .. layerIndex, cached.video * 100, false)
    queueLayerParameter("Layer Video " .. layerIndex, cached.videoId, requested)
  end
end

clearCompositionCache()

Timer.CallAfter(connectWebSocket, 0.1)
