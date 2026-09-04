# Changelog

## 0.1.0.81 — 2026-09-04

### Changed

- Consolidated connection health and diagnostic text into the reserved `Status`
  indicator control.
- Replaced `BuildVersion` with the Q-SYS-supported `Version` field throughout the
  plugin and build workflow.
- Exposed Layer Name and Dashboard Link Name controls as output pins.
- Replaced spaces in internal control names with periods and moved every
  `PrettyName` definition to the layout table.
- Rendered the Status indicator as a rectangular text field.
- Added explicit manufacturer metadata.

### Compatibility

- Internal control names changed in this release. Existing designs wired to the
  `0.1.0` control pins must reconnect them using the new period-separated names.

### Validation

- Q-SYS Plugin Evaluation Script: zero errors with default properties and with
  the maximum 715-control configuration.

## 0.1.0 — 2026-09-03

First validated preview release.

### Added

- Single-page Q-SYS interface with an integrated branded connection header.
- Configurable deck, column and layer counts with stable control families.
- Resolume-inspired and native Q-SYS appearance modes.
- REST commands and realtime WebSocket feedback for decks, columns, clips,
  layers, composition controls and global transport.
- Clip and active-layer thumbnails with bounded concurrency, cross-deck caching
  and an explicit unavailable-image state.
- Eight dynamically discovered Composition Dashboard Links with smooth,
  rate-limited bidirectional control.
- Realtime name updates for clips, layers and Dashboard Links.
- Automatic connection health detection, reconnection and support diagnostics.

### Known limitation

- Resolume may not serve a never-exposed, non-selected deck thumbnail by clip ID.
  In that case the plugin shows the clip title and an unavailable-image icon until
  the image becomes available.
