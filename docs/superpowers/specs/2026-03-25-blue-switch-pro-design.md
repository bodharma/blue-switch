# Blue Switch Pro — Design Spec

## Overview

Upgrade Blue Switch from a basic "toggle all Bluetooth devices" menubar app into a full-featured Bluetooth device manager combining the best of ToothFairy and Magic Switch, with per-device switching, battery monitoring, keyboard shortcuts, automation hooks, audio management, and a CLI tool.

## Requirements

- **Minimum macOS:** 13.0 (Ventura) — required for `SMAppService`, `KeyboardShortcuts` macOS 12+ compatibility, and modern Bluetooth APIs
- **Distribution:** Outside App Store only (uses IOBluetooth private APIs)
- **Sandbox:** Disabled — required for shell script execution, Unix domain sockets, IOBluetooth private APIs, and audio device manipulation. The existing `com.apple.security.app-sandbox` entitlement will be removed. Bluetooth and network entitlements are retained.

## Goals

- Per-device switching (move trackpad without moving keyboard)
- Battery level display in menubar
- Global keyboard shortcuts per device
- User-friendly automation hooks on connect/disconnect
- Audio routing for headphones (auto-switch output/input)
- Audio codec preference (experimental — best-effort, uses undocumented APIs)
- CLI tool that works standalone or talks to the running app
- Dark/light mode adaptive UI
- Launch at login

## Architecture

### Three layers, two targets

```
┌─────────────────┐   ┌──────────────┐
│  Menubar App    │   │  CLI Tool    │
│  (SwiftUI)      │   │  (ArgumentParser)
└────────┬────────┘   └──────┬───────┘
         │                   │
         │  ┌────────────────┤
         │  │  Unix Socket   │  (CLI → App communication)
         │  └────────┬───────┘
         │           │
    ┌────▼───────────▼────┐
    │   BlueSwitchCore    │
    │  (shared library)   │
    ├─────────────────────┤
    │ DeviceManager       │  Per-device state machine
    │ BatteryMonitor      │  Battery level polling
    │ ShortcutManager     │  Global hotkeys
    │ ActionRunner        │  Automation hooks
    │ AudioManager        │  Codec & routing
    │ PeerNetwork         │  Bonjour discovery + TCP commands
    │ Preferences         │  Shared UserDefaults suite (App Group)
    └─────────────────────┘
```

### CLI ↔ App communication

1. CLI checks for running app via Unix domain socket at `~/Library/Application Support/BlueSwitch/blueswitch.sock`
2. **App running:** CLI sends command via socket → app executes → returns result (menubar stays in sync)
3. **App not running:** CLI prints "Blue Switch app is not running. Start it first, or use `blueswitch status` for read-only info." Bluetooth operations require the app to be running (macOS TCC requires a proper app bundle with Info.plist for Bluetooth access; a bare CLI binary cannot obtain BT permissions). Read-only commands (`list`, `status`, `battery`) can read from shared preferences directly.

### Socket wire protocol

Newline-delimited JSON over Unix domain socket. Each message is a single JSON object followed by `\n`.

**Request format:**
```json
{"command": "switch", "device": "Magic Trackpad", "version": 1}
```

**Response format:**
```json
{"status": "ok", "message": "Switched Magic Trackpad → Mac mini", "version": 1}
{"status": "error", "message": "Device not found", "code": "DEVICE_NOT_FOUND", "version": 1}
```

The `version` field enables future protocol evolution. Unknown fields are ignored (forward-compatible).

**Security:** Socket is protected by filesystem permissions (user-only, `0700` on parent directory). No additional authentication needed — only processes running as the same user can connect. This is standard for single-user desktop app IPC.

## Device Model

```swift
struct Device: Identifiable, Codable {
    let id: String                    // MAC address
    var name: String
    var type: DeviceType              // .trackpad, .keyboard, .mouse, .headphones, .other
    var icon: String?                 // SF Symbol name or custom asset
    var shortcutName: String?         // KeyboardShortcuts.Name identifier
    var onConnectActions: [DeviceAction]
    var onDisconnectActions: [DeviceAction]
    var showInMenubar: Bool           // Per-device menubar icon toggle
}

enum DeviceType: String, Codable {
    case trackpad, keyboard, mouse, headphones, other
}

struct DeviceAction: Identifiable, Codable {
    let id: UUID
    var type: ActionType
    var isEnabled: Bool = true

    enum ActionType: Codable {
        case openApp(path: String)
        case openURL(url: String)
        case shortcut(name: String)       // macOS Shortcuts.app
        case shellScript(path: String)    // Advanced — runs via /bin/zsh
    }
}
```

**Shortcut binding:** `shortcutName` is a `String` identifier registered with the `KeyboardShortcuts` package via `KeyboardShortcuts.Name(rawValue:)`. The actual key combo is managed by the package and stored in its own UserDefaults. This avoids duplicating the shortcut serialization format.

**Action extensibility:** `DeviceAction` is a struct with an `ActionType` enum rather than a bare enum, allowing per-action metadata (`id`, `isEnabled`) and future fields without breaking serialization.

`DeviceType` is auto-detected from IOBluetooth device class codes at registration, user can override.

## Per-Device State Machine

Managed by `DeviceManager`, not stored in the model:

```
              ┌──────────────┐
              │ disconnected │◄──────────────┐
              └──────┬───────┘               │
                     │ connect()        timeout/fail
              ┌──────▼───────┐               │
              │  connecting  ├───────────────┘
              └──────┬───────┘
                     │ success
              ┌──────▼───────┐
              │  connected   │
              └──┬───────┬───┘
    disconnect() │       │ switchToPeer()
              ┌──▼───────▼───┐
              │disconnecting ├──────────────┐
              └──────┬───────┘              │
                     │ success         timeout/fail
                     ▼                      │
              (back to disconnected)────────┘
```

**`switchToPeer(device)`** originates from `connected` state: disconnect locally → tell peer to connect → confirm. Cannot be called from `disconnected`.

**Recovery on partial failure:** If local disconnect succeeds but peer fails to connect (timeout after retry), the local Mac automatically attempts to reconnect the device to restore the previous state. User is notified: "Switch failed — device reconnected locally."

**Timeouts and retries:**
- Connect timeout: 10s (IOBluetooth `openConnection` + pairing)
- Disconnect timeout: 5s
- Peer communication timeout: 5s
- Retries: 1 automatic retry on timeout, then fail with notification to user
- No exponential backoff (operations are user-initiated, not background)

### Bluetooth system state

`DeviceManager` also monitors Bluetooth system state (powered on/off/unauthorized) via `CBCentralManager` — this replaces the existing `BluetoothManager` singleton. All device operations check BT system state before proceeding. If BT is off, menubar shows a disabled indicator and operations return immediately with an error.

## Battery Monitoring

`BatteryMonitor` reads battery level via IOBluetooth HID battery reporting (available for Magic Trackpad/Keyboard/Mouse). Publishes per-device battery levels as `@Published var batteryLevels: [String: Int?]` (keyed by device MAC). Polling interval: 60s (configurable).

**Devices without battery reporting** (third-party mice, older peripherals): `batteryLevels[id]` returns `nil`. The UI shows "—" instead of a percentage. No error, no special handling needed.

## Menubar UI

### Compact mode (default)

Single menubar icon. Click opens device list:

```
┌──────────────────────────────────┐
│  Magic Trackpad     🔋 87%  ●   │  green = connected here
│  Magic Keyboard     🔋 62%  ○   │  hollow = connected to peer
│  ─────────────────────────────── │
│  ⇧⌘T  Switch Trackpad           │
│  ⇧⌘K  Switch Keyboard           │
│  ─────────────────────────────── │
│  Switch All                      │
│  ─────────────────────────────── │
│  Settings...              ⌘,    │
│  Quit                     ⌘Q    │
└──────────────────────────────────┘
```

### Expanded mode (opt-in per device)

Individual menubar icons with battery %. Click switches that device.

### Status indicators

- **●** green — connected to this Mac
- **○** hollow — connected to peer
- **⊘** grey — not in range / off

### Dark/light mode

SF Symbols (`computermouse.fill`, `keyboard.fill`, `rectangle.inset.filled` for trackpad) adapt automatically. Menubar icon uses `NSImage` with template rendering.

### Launch at login

`SMAppService.mainApp` (modern macOS API, no helper app needed).

## Keyboard Shortcuts

Using `KeyboardShortcuts` Swift package (Sindre Sorhus — pure Swift, macOS 12+).

Each device gets an optional shortcut. Default suggestions on first setup:
- `⇧⌘T` — Switch trackpad
- `⇧⌘K` — Switch keyboard
- `⇧⌘A` — Switch all

Settings UI provides standard "click to record shortcut" field per device.

## Automation Hooks

### Action types (ordered by simplicity)

1. **Open App** — file picker for .app
2. **Open Link** — text field (supports URL schemes)
3. **Run Shortcut** — dropdown from Shortcuts.app library
4. **Shell Script** — hidden under "Advanced" disclosure

### Settings UI per device

```
When Magic Trackpad connects:
  ┌─────────────────────────────────┐
  │ ▶ Open "Spotify"           [✕] │
  │ ▶ Run "Focus Mode On"     [✕] │
  │                                 │
  │ [+ Add Action]                  │
  └─────────────────────────────────┘
```

Actions are drag-to-reorder, executed top to bottom. Each has a toggle to enable/disable without deleting.

### Shell script execution (Advanced)

Scripts are executed via `Process()` with `/bin/zsh` as the shell. Working directory is the user's home directory.

Environment variables injected:

```bash
BLUESWITCH_DEVICE_NAME="Magic Trackpad"
BLUESWITCH_DEVICE_MAC="AA:BB:CC:DD:EE:FF"
BLUESWITCH_DEVICE_TYPE="trackpad"
BLUESWITCH_EVENT="connect"
BLUESWITCH_PEER_NAME="Mac mini"
```

Scripts run async with 10s timeout, non-blocking. Failures are logged via `os_log` (subsystem: `com.blueswitch`, category: `actions`) and do not block the switch operation.

## Audio Management

Applies only to `DeviceType.headphones`. Settings show extra section:

```
Audio Settings:
  Auto-switch audio output: [✓]
  Auto-switch audio input:  [✓]
  ───────────────────────────
  Experimental:
  Preferred codec:  [AAC ▾]     ← AAC / SBC / auto
```

### Phase 1: Audio routing (reliable)

`AudioObjectSetPropertyData` to set default output/input on connect, revert to previous default on disconnect. This uses public CoreAudio APIs and is fully supported.

### Phase 2: Codec preference (experimental)

There is **no public CoreAudio API** to force AAC vs SBC codec selection. macOS selects the codec during A2DP negotiation. ToothFairy achieves this via undocumented IOBluetooth/CoreAudio private APIs that can break across macOS versions.

Implementation approach: attempt to set codec preference via known private API selectors. If the API is unavailable or fails, silently fall back to system default. The UI marks this as "Experimental" and the setting is disabled by default.

Non-audio devices don't see this section.

## CLI Tool

Binary: `blueswitch`

```
blueswitch list                          # Devices + status + battery
blueswitch switch "Magic Trackpad"       # Switch specific device
blueswitch switch --all                  # Switch all devices
blueswitch connect "Magic Trackpad"      # Connect to this Mac
blueswitch disconnect "Magic Trackpad"   # Disconnect from this Mac
blueswitch status                        # Summary
blueswitch battery                       # Battery levels
blueswitch config                        # Open settings (launches app if not running)
```

Device matching is fuzzy — `blueswitch switch trackpad` matches "Magic Trackpad" by substring, case-insensitive. Ambiguous matches list options and ask.

Built with `swift-argument-parser`. Same Xcode project, second target.

## Preferences & Storage

Shared via App Group `UserDefaults` suite:

```
~/Library/Application Support/BlueSwitch/
├── preferences.json                   ← shared config (CLI + App)
├── scripts/                           ← user shell scripts
└── blueswitch.sock                    ← Unix socket for CLI ↔ App
```

```swift
struct AppPreferences: Codable {
    var devices: [Device]
    var compactMode: Bool = true
    var launchAtLogin: Bool = true
    var switchAllShortcutName: String?  // KeyboardShortcuts.Name identifier
    var batteryPollingInterval: Int = 60
    var showBatteryInMenubar: Bool = true
    var audioAutoSwitch: Bool = true
}
```

Using a JSON file in Application Support (rather than App Group UserDefaults) because: (1) sandbox is disabled so App Groups aren't needed, (2) CLI can read/write without needing group container access, (3) easier to debug and backup.

**Concurrency:** App writes using `Data.write(to:options:.atomic)` to prevent partial reads. CLI only reads, so no file locking needed.

### Data migration

On first launch, detect existing Blue Switch `@AppStorage` data:
1. Read `peripherals` key from `UserDefaults.standard` → decode as `[BluetoothPeripheral]`
2. Read `networkDevices` key from `UserDefaults.standard` → decode as `[NetworkDevice]`
3. Convert each `BluetoothPeripheral` to `Device` (auto-detect `DeviceType` from IOBluetooth class codes)
4. Write to `preferences.json`
5. Back up old keys under prefixed names (`_backup_peripherals`, `_backup_networkDevices`) in `UserDefaults.standard` for rollback safety
6. Remove original old keys from `UserDefaults.standard`
7. If step 1-2 fail (no old data), skip migration silently

## File Changes

### Existing files

| File | Action |
|------|--------|
| `AppDelegate.swift` | Rewrite — per-device switching, new menubar, launch-at-login |
| `Blue_SwitchApp.swift` | Keep — minimal changes |
| `ConnectionManager.swift` | Refactor — extract protocol, per-device commands |
| `BluetoothManager.swift` | Absorb into DeviceManager (BT system state monitoring + per-device ops) |
| `BluetoothPeripheralStore.swift` | Replace with DeviceManager + Device model |
| `NetworkDeviceStore.swift` | Refactor into `PeerNetwork` — keep Bonjour discovery + TCP commands, add per-device command support. `PeerNetwork` wraps `ServiceBrowser`, `ServicePublisher`, and `ConnectionManager` behind a single interface |
| `ServiceBrowser.swift` | Keep — uses `NetServiceBrowser` (deprecated in macOS 15 but still functional). Migrate to `NWBrowser` in a future release |
| `ServicePublisher.swift` | Keep — same deprecation note as ServiceBrowser |
| `NotificationManager.swift` | Keep — minor additions |
| `BluetoothPeripheral.swift` | Replace with Device model |
| `NetworkDevice.swift` | Keep — minor updates |
| `MenuBarView.swift` | Rewrite — per-device items, battery, indicators |
| `BluetoothPeripheralSettingsView.swift` | Rewrite — actions, shortcuts, icons |
| `GeneralSettingsView.swift` | Rewrite — launch-at-login, mode, battery prefs |
| `NetworkDeviceManagementView.swift` | Refactor — minor UI updates |
| `OtherSettingsView.swift` | Remove — absorbed into general |
| `SettingsView.swift` | Refactor — new tab structure |
| `IOBluetoothDevice+Extension.swift` | Keep |
| `NetworkDevice+HealthCheck.swift` | Keep |

### New files

| File | Purpose |
|------|---------|
| `Device.swift` | New device model |
| `DeviceManager.swift` | Per-device state machine |
| `BatteryMonitor.swift` | Battery level polling |
| `ShortcutManager.swift` | Global hotkey registration |
| `ActionRunner.swift` | Execute device actions |
| `AudioManager.swift` | Codec switching, audio routing |
| `AppCommunicator.swift` | Unix socket server (app side) |
| `CLIClient.swift` | Unix socket client + fallback (CLI side) |
| `CLI/main.swift` | CLI entry point |

## Dependencies

| Package | Purpose |
|---------|---------|
| `KeyboardShortcuts` (sindresorhus) | Global hotkey support |
| `swift-argument-parser` (apple) | CLI argument parsing |

## Logging

All components use `os_log` with subsystem `com.blueswitch` and per-component categories:

| Category | Used by |
|----------|---------|
| `bluetooth` | DeviceManager, BatteryMonitor |
| `network` | PeerNetwork, ServiceBrowser, ServicePublisher |
| `actions` | ActionRunner |
| `audio` | AudioManager |
| `ipc` | AppCommunicator, CLIClient |
| `app` | AppDelegate, preferences, migration |

Replaces all existing `print()` statements. Viewable in Console.app filtered by `com.blueswitch`.

## Testing Strategy

- **DeviceManager state machine:** Unit tests with a mocked `IOBluetoothDevice` protocol wrapper. Test all state transitions, timeouts, and retry behavior.
- **ActionRunner:** Unit tests for each action type with mocked `NSWorkspace` and `Process`.
- **Socket protocol:** Unit tests for JSON serialization/deserialization of commands and responses.
- **Integration:** Manual testing with physical Magic Trackpad + Magic Keyboard between two Macs. No way to fully automate BT device interactions.

## Known Issues to Fix from Existing Code

- `BluetoothPeripheralStore` sets `devicePair.delegate = self` but never conforms to `IOBluetoothDevicePairDelegate`. Must be fixed in `DeviceManager`.

## Non-Goals

- Windows/Linux support
- Multi-peer switching (more than 2 Macs) — may add later
- Bluetooth LE device support (Magic devices use Classic BT)
- App Store distribution (uses IOBluetooth private APIs)
- Migrating `NetServiceBrowser`/`NetService` to `NWBrowser` (deferred — current APIs still work)
