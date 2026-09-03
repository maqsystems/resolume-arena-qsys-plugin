# Changelog

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
