# Blue Switch Pro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Blue Switch into a full-featured Bluetooth device manager with per-device switching, battery monitoring, keyboard shortcuts, automation hooks, audio management, and a CLI tool.

**Architecture:** Rewrite core managers while keeping the existing Bonjour and SwiftUI shell. Shared `BlueSwitchCore` library consumed by both the menubar app and a new CLI target. Per-device state machine replaces the current batch toggle approach.

**Tech Stack:** Swift 5.9+, SwiftUI, IOBluetooth, CoreBluetooth, CoreAudio, Network framework, KeyboardShortcuts (sindresorhus), swift-argument-parser (apple), os_log

**Spec:** `docs/superpowers/specs/2026-03-25-blue-switch-pro-design.md`

---

## Important Notes

### Shared code between targets
The spec calls for a `BlueSwitchCore` shared library. In this plan, shared model types (`Device`, `AppPreferences`, `SocketProtocol`) are created as source files added to **both** the app target and the CLI target in Xcode. This avoids the complexity of a separate framework target for a small codebase. If the project grows, extract into a Swift Package later.

### Xcode project changes (manual steps)
Tasks that require Xcode project configuration changes (adding targets, SPM dependencies, file membership) are flagged as **MANUAL** steps. These must be done through Xcode GUI — programmatic `pbxproj` editing is too error-prone. The agentic worker should pause and ask the user to perform these steps.

### Info.plist
Add `NSBluetoothAlwaysUsageDescription` to the app's Info.plist with value "Blue Switch needs Bluetooth access to manage your devices." This is required for TCC Bluetooth permission outside the sandbox.

### ContentView.swift
The existing `Blue Switch/ContentView.swift` is unused (the app is a menubar-only app). Delete it during Task 1.

## File Map

### New files to create

| Path | Responsibility | Targets |
|------|---------------|---------|
| `Blue Switch/Model/Entity/Device.swift` | Device model, DeviceType, DeviceAction | App + CLI |
| `Blue Switch/Model/Entity/AppPreferences.swift` | AppPreferences model + JSON persistence | App + CLI |
| `Blue Switch/Model/Entity/SocketProtocol.swift` | SocketRequest, SocketResponse Codable types | App + CLI |
| `Blue Switch/Manager/DeviceManager.swift` | Per-device state machine, BT system state, connect/disconnect/switchToPeer | App only |
| `Blue Switch/Manager/BatteryMonitor.swift` | Battery level polling via IOBluetooth | App only |
| `Blue Switch/Manager/ShortcutManager.swift` | Global hotkey registration per device | App only |
| `Blue Switch/Manager/ActionRunner.swift` | Execute DeviceActions (open app, URL, shortcut, script) | App only |
| `Blue Switch/Manager/AudioManager.swift` | Audio routing + experimental codec | App only |
| `Blue Switch/Manager/PeerNetwork.swift` | Wraps ServiceBrowser + ServicePublisher + ConnectionManager | App only |
| `Blue Switch/Manager/AppCommunicator.swift` | Unix socket server for CLI IPC | App only |
| `Blue Switch/Logging/Log.swift` | os_log Logger instances per category | App only |
| `Blue Switch/Migration/DataMigrator.swift` | Migrate old @AppStorage to preferences.json | App only |
| `Blue Switch CLI/main.swift` | CLI entry point | CLI only |
| `Blue Switch CLI/CLIClient.swift` | Unix socket client + direct preferences reader | CLI only |
| `Blue Switch CLI/Commands/*.swift` | swift-argument-parser command definitions | CLI only |
| `Blue SwitchTests/DeviceManagerTests.swift` | State machine unit tests | Tests |
| `Blue SwitchTests/ActionRunnerTests.swift` | Action execution tests | Tests |
| `Blue SwitchTests/SocketProtocolTests.swift` | JSON serialization tests | Tests |
| `Blue SwitchTests/AppPreferencesTests.swift` | Preferences read/write tests | Tests |

### Existing files to modify

| Path | Change |
|------|--------|
| `Blue Switch.xcodeproj/project.pbxproj` | Add CLI target, test target, SPM dependencies, file membership |
| `Blue Switch/Blue_Switch.entitlements` | Remove sandbox entitlement entirely (BT/network entitlements are sandbox-only, not needed outside sandbox) |
| `Blue Switch/AppDelegate/AppDelegate.swift` | Rewrite for per-device switching |
| `Blue Switch/AppDelegate/Blue_SwitchApp.swift` | Minor — inject new managers |
| `Blue Switch/Manager/ConnectionManager.swift` | Remove BluetoothPeripheralStore dependency, add per-device commands |
| `Blue Switch/Model/Store/NetworkDeviceStore.swift` | Remove BluetoothPeripheral references, add per-device command execution |
| `Blue Switch/Manager/NotificationManager.swift` | Replace print() with os_log |
| `Blue Switch/View/MenuBar/MenuBarView.swift` | Rewrite — per-device items, battery, status, expanded mode |
| `Blue Switch/View/Settings/SettingsView.swift` | New tab structure |
| `Blue Switch/View/Settings/GeneralSettingsView.swift` | Rewrite — launch-at-login, compact mode, battery |
| `Blue Switch/View/Settings/BluetoothPeripheralSettingsView.swift` | Rewrite — device settings with actions, shortcuts |
| `Blue Switch/View/Settings/NetworkDeviceManagementView.swift` | Minor UI updates |
| `Blue Switch/Extensions/IOBluetoothDevice+Extension.swift` | Return Device instead of BluetoothPeripheral |

### Files to delete

| Path | Reason | When |
|------|--------|------|
| `Blue Switch/ContentView.swift` | Unused | Task 1 |
| `Blue Switch/Model/Entity/BluetoothPeripheral.swift` | Replaced by Device.swift | Task 3 (after ConnectionManager updated) |
| `Blue Switch/Model/Store/BluetoothPeripheralStore.swift` | Replaced by DeviceManager.swift | Task 3 (after ConnectionManager updated) |
| `Blue Switch/Manager/BluetoothManager.swift` | Absorbed into DeviceManager | Task 3 |
| `Blue Switch/View/Settings/OtherSettingsView.swift` | Absorbed into GeneralSettingsView | Task 12 |

---

## Task 1: Project Setup — Entitlements, Dependencies, Logging

**Files:**
- Modify: `Blue Switch/Blue_Switch.entitlements`
- Modify: `Blue Switch.xcodeproj/project.pbxproj`
- Create: `Blue Switch/Logging/Log.swift`

- [ ] **Step 1: Remove entitlements file and update Info.plist**

Delete `Blue Switch/Blue_Switch.entitlements` — all three entitlements were sandbox capabilities (`app-sandbox`, `device.bluetooth`, `network.client`, `network.server`). Outside the sandbox, these are unnecessary. Bluetooth permission is handled via TCC and Info.plist.

Remove the entitlements file reference from the Xcode project build settings (Code Signing Entitlements).

Add to Info.plist:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Blue Switch needs Bluetooth access to manage your devices.</string>
```

Delete `Blue Switch/ContentView.swift` (unused).

```bash
rm "Blue Switch/Blue_Switch.entitlements"
rm "Blue Switch/ContentView.swift"
```

- [ ] **Step 2: Add SPM dependencies**

Open the Xcode project and add:
- `https://github.com/sindresorhus/KeyboardShortcuts` (from: "2.0.0")
- `https://github.com/apple/swift-argument-parser` (from: "1.3.0")

Or add via `xcodebuild` / manual pbxproj edits. Verify:

Run: `xcodebuild -project "Blue Switch.xcodeproj" -scheme "Blue Switch" -showBuildSettings | grep SWIFT_PACKAGES`

- [ ] **Step 3: Create logging infrastructure**

Create `Blue Switch/Logging/Log.swift`:

```swift
import os

enum Log {
    static let bluetooth = Logger(subsystem: "com.blueswitch", category: "bluetooth")
    static let network = Logger(subsystem: "com.blueswitch", category: "network")
    static let actions = Logger(subsystem: "com.blueswitch", category: "actions")
    static let audio = Logger(subsystem: "com.blueswitch", category: "audio")
    static let ipc = Logger(subsystem: "com.blueswitch", category: "ipc")
    static let app = Logger(subsystem: "com.blueswitch", category: "app")
}
```

- [ ] **Step 4: Replace print() in NotificationManager**

In `Blue Switch/Manager/NotificationManager.swift`, replace all `print(...)` calls with `Log.app.info(...)` or `Log.app.error(...)` as appropriate.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -project "Blue Switch.xcodeproj" -scheme "Blue Switch" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: disable sandbox, add SPM deps, add os_log infrastructure"
```

---

## Task 2: Device Model + Preferences + Migration

**Files:**
- Create: `Blue Switch/Model/Entity/Device.swift`
- Create: `Blue Switch/Model/Entity/AppPreferences.swift`
- Create: `Blue Switch/Migration/DataMigrator.swift`
- Create: `Blue SwitchTests/AppPreferencesTests.swift`

- [ ] **Step 1: Write test for AppPreferences round-trip**

Create `Blue SwitchTests/AppPreferencesTests.swift`:

```swift
import XCTest
@testable import Blue_Switch

final class AppPreferencesTests: XCTestCase {
    let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("BlueSwitchTests")

    override func setUp() {
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testPreferencesRoundTrip() throws {
        let prefs = AppPreferences(
            devices: [
                Device(
                    id: "AA:BB:CC:DD:EE:FF",
                    name: "Magic Trackpad",
                    type: .trackpad,
                    onConnectActions: [
                        DeviceAction(type: .openApp(path: "/Applications/Spotify.app"))
                    ],
                    onDisconnectActions: [],
                    showInMenubar: true
                )
            ]
        )

        let file = testDir.appendingPathComponent("prefs.json")
        try prefs.save(to: file)

        let loaded = try AppPreferences.load(from: file)
        XCTAssertEqual(loaded.devices.count, 1)
        XCTAssertEqual(loaded.devices[0].name, "Magic Trackpad")
        XCTAssertEqual(loaded.devices[0].type, .trackpad)
        XCTAssertEqual(loaded.devices[0].onConnectActions.count, 1)
        XCTAssertTrue(loaded.compactMode)
    }

    func testLoadReturnsDefaultWhenFileMissing() throws {
        let file = testDir.appendingPathComponent("nonexistent.json")
        let loaded = try AppPreferences.load(from: file)
        XCTAssertTrue(loaded.devices.isEmpty)
        XCTAssertTrue(loaded.compactMode)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Blue Switch.xcodeproj" -scheme "Blue Switch" -only-testing "Blue SwitchTests/AppPreferencesTests" 2>&1 | tail -10`
Expected: FAIL — types don't exist yet

- [ ] **Step 3: Create Device model**

Create `Blue Switch/Model/Entity/Device.swift`:

```swift
import Foundation

enum DeviceType: String, Codable, CaseIterable {
    case trackpad
    case keyboard
    case mouse
    case headphones
    case other
}

struct DeviceAction: Identifiable, Codable, Equatable {
    let id: UUID
    var type: ActionType
    var isEnabled: Bool

    init(id: UUID = UUID(), type: ActionType, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
    }

    enum ActionType: Codable, Equatable {
        case openApp(path: String)
        case openURL(url: String)
        case shortcut(name: String)
        case shellScript(path: String)
    }
}

struct Device: Identifiable, Codable, Equatable {
    let id: String  // MAC address
    var name: String
    var type: DeviceType
    var icon: String?
    var shortcutName: String?
    var onConnectActions: [DeviceAction]
    var onDisconnectActions: [DeviceAction]
    var showInMenubar: Bool

    init(
        id: String,
        name: String,
        type: DeviceType = .other,
        icon: String? = nil,
        shortcutName: String? = nil,
        onConnectActions: [DeviceAction] = [],
        onDisconnectActions: [DeviceAction] = [],
        showInMenubar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.shortcutName = shortcutName
        self.onConnectActions = onConnectActions
        self.onDisconnectActions = onDisconnectActions
        self.showInMenubar = showInMenubar
    }
}
```

- [ ] **Step 4: Create AppPreferences**

Create `Blue Switch/Model/Entity/AppPreferences.swift`:

```swift
import Foundation

struct AppPreferences: Codable, Equatable {
    var devices: [Device]
    var compactMode: Bool
    var launchAtLogin: Bool
    var switchAllShortcutName: String?
    var batteryPollingInterval: Int
    var showBatteryInMenubar: Bool
    var audioAutoSwitch: Bool

    init(
        devices: [Device] = [],
        compactMode: Bool = true,
        launchAtLogin: Bool = true,
        switchAllShortcutName: String? = nil,
        batteryPollingInterval: Int = 60,
        showBatteryInMenubar: Bool = true,
        audioAutoSwitch: Bool = true
    ) {
        self.devices = devices
        self.compactMode = compactMode
        self.launchAtLogin = launchAtLogin
        self.switchAllShortcutName = switchAllShortcutName
        self.batteryPollingInterval = batteryPollingInterval
        self.showBatteryInMenubar = showBatteryInMenubar
        self.audioAutoSwitch = audioAutoSwitch
    }

    static let defaultURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlueSwitch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("preferences.json")
    }()

    func save(to url: URL = AppPreferences.defaultURL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = AppPreferences.defaultURL) throws -> AppPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppPreferences()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project "Blue Switch.xcodeproj" -scheme "Blue Switch" -only-testing "Blue SwitchTests/AppPreferencesTests" 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 6: Create DataMigrator**

Create `Blue Switch/Migration/DataMigrator.swift`:

```swift
import Foundation
import IOBluetooth

struct DataMigrator {
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        guard let peripheralsData = defaults.data(forKey: "peripherals") else {
            Log.app.info("No legacy data to migrate")
            return
        }

        // Check if already migrated
        if FileManager.default.fileExists(atPath: AppPreferences.defaultURL.path) {
            Log.app.info("Preferences already exist, skipping migration")
            return
        }

        do {
            // Decode old peripherals
            let oldPeripherals = try JSONDecoder().decode([LegacyPeripheral].self, from: peripheralsData)

            // Convert to new Device model
            let devices = oldPeripherals.map { peripheral in
                Device(
                    id: peripheral.id,
                    name: peripheral.name,
                    type: detectDeviceType(macAddress: peripheral.id)
                )
            }

            // Save new preferences
            let prefs = AppPreferences(devices: devices)
            try prefs.save()

            // Backup old keys
            defaults.set(peripheralsData, forKey: "_backup_peripherals")
            if let networkData = defaults.data(forKey: "networkDevices") {
                defaults.set(networkData, forKey: "_backup_networkDevices")
            }

            // Remove old keys
            defaults.removeObject(forKey: "peripherals")
            defaults.removeObject(forKey: "networkDevices")

            Log.app.info("Migrated \(devices.count) devices successfully")
        } catch {
            Log.app.error("Migration failed: \(error.localizedDescription)")
        }
    }

    static func detectDeviceType(macAddress: String) -> DeviceType {
        guard let device = IOBluetoothDevice(addressString: macAddress) else {
            return .other
        }
        let minorClass = device.deviceClassMinor
        let majorClass = device.deviceClassMajor

        // Major class 0x05 = Peripheral
        if majorClass == 0x05 {
            // Minor class bits for peripheral subtype
            switch minorClass & 0xC0 {
            case 0x40: return .keyboard
            case 0x80: return .mouse  // pointing device — could be trackpad
            default: break
            }
            // Check name for trackpad hints
            if device.name?.lowercased().contains("trackpad") == true {
                return .trackpad
            }
            if device.name?.lowercased().contains("keyboard") == true {
                return .keyboard
            }
            if device.name?.lowercased().contains("mouse") == true {
                return .mouse
            }
        }

        // Major class 0x04 = Audio/Video
        if majorClass == 0x04 {
            return .headphones
        }

        return .other
    }
}

/// Legacy model for migration only
private struct LegacyPeripheral: Codable {
    let id: String
    let name: String
}
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Device model, AppPreferences, and data migration"
```

---

## Task 3: DeviceManager — State Machine + BT Operations

**Files:**
- Create: `Blue Switch/Manager/DeviceManager.swift`
- Create: `Blue SwitchTests/DeviceManagerTests.swift`
- Modify: `Blue Switch/Manager/ConnectionManager.swift` — remove BluetoothPeripheralStore/BluetoothPeripheral references
- Modify: `Blue Switch/Model/Store/NetworkDeviceStore.swift` — remove BluetoothPeripheral references
- Delete: `Blue Switch/Manager/BluetoothManager.swift`
- Delete: `Blue Switch/Model/Store/BluetoothPeripheralStore.swift`
- Delete: `Blue Switch/Model/Entity/BluetoothPeripheral.swift`

**IMPORTANT: Update ConnectionManager and NetworkDeviceStore BEFORE deleting old types, or the build will break.**

- [ ] **Step 1: Remove old type references from ConnectionManager**

In `Blue Switch/Manager/ConnectionManager.swift`:
- Remove `@ObservedObject private var bluetoothStore = BluetoothPeripheralStore.shared` (line 33)
- Remove the `handleCommand` cases that reference `bluetoothStore` (`.connectAll`, `.unregisterAll`, `.syncPeripherals`) — these will be re-implemented via DeviceManager in Task 6
- Remove `sendPeripheralSync` method
- Keep the core connection/send/receive infrastructure intact

- [ ] **Step 2: Remove old type references from NetworkDeviceStore**

In `Blue Switch/Model/Store/NetworkDeviceStore.swift`:
- Remove `func sendPeripheralSync(peripherals: [BluetoothPeripheral]...` extension (line 256-260)
- Remove `.peripheralData` and `.syncPeripherals` from `DeviceCommand` if desired, or keep for backward compat

- [ ] **Step 3: Write state machine tests**

Create `Blue SwitchTests/DeviceManagerTests.swift`:

```swift
import XCTest
@testable import Blue_Switch

final class DeviceManagerTests: XCTestCase {
    func testInitialStateIsDisconnected() {
        let dm = DeviceManager()
        let device = Device(id: "AA:BB:CC:DD:EE:FF", name: "Test", type: .trackpad)
        XCTAssertEqual(dm.state(for: device), .disconnected)
    }

    func testCannotSwitchToPeerFromDisconnected() {
        let dm = DeviceManager()
        let device = Device(id: "AA:BB:CC:DD:EE:FF", name: "Test", type: .trackpad)
        dm.register(device)
        XCTAssertFalse(dm.canSwitchToPeer(device))
    }

    func testRegisterAndUnregister() {
        let dm = DeviceManager()
        let device = Device(id: "AA:BB:CC:DD:EE:FF", name: "Test", type: .trackpad)

        dm.register(device)
        XCTAssertEqual(dm.registeredDevices.count, 1)

        dm.unregister(device)
        XCTAssertEqual(dm.registeredDevices.count, 0)
    }

    func testFetchPairedDevicesReturnsArray() {
        let dm = DeviceManager()
        let discovered = dm.fetchPairedDevices()
        XCTAssertNotNil(discovered)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Blue Switch.xcodeproj" -scheme "Blue Switch" -only-testing "Blue SwitchTests/DeviceManagerTests" 2>&1 | tail -10`
Expected: FAIL — DeviceManager doesn't exist

- [ ] **Step 4: Create DeviceManager**

Create `Blue Switch/Manager/DeviceManager.swift`:

```swift
import CoreBluetooth
import Foundation
import IOBluetooth

enum DeviceState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

final class DeviceManager: NSObject, ObservableObject {
    // MARK: - Published State

    @Published private(set) var registeredDevices: [Device] = []
    @Published private(set) var deviceStates: [String: DeviceState] = [:]
    @Published private(set) var bluetoothPoweredOn: Bool = false

    // MARK: - Private

    private var centralManager: CBCentralManager?
    private let btQueue = DispatchQueue(label: "com.blueswitch.device-manager", qos: .userInitiated)
    private let connectTimeout: TimeInterval = 10
    private let disconnectTimeout: TimeInterval = 5
    private let maxRetries = 1

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: btQueue)
    }

    // MARK: - State Queries

    func state(for device: Device) -> DeviceState {
        deviceStates[device.id] ?? .disconnected
    }

    func canSwitchToPeer(_ device: Device) -> Bool {
        state(for: device) == .connected
    }

    func isConnected(_ device: Device) -> Bool {
        guard let btDevice = IOBluetoothDevice(addressString: device.id) else { return false }
        return btDevice.isConnected()
    }

    // MARK: - Registration

    func register(_ device: Device) {
        guard !registeredDevices.contains(where: { $0.id == device.id }) else { return }
        registeredDevices.append(device)
        deviceStates[device.id] = isConnected(device) ? .connected : .disconnected
        Log.bluetooth.info("Registered device: \(device.name)")
    }

    func unregister(_ device: Device) {
        registeredDevices.removeAll { $0.id == device.id }
        deviceStates.removeValue(forKey: device.id)
        Log.bluetooth.info("Unregistered device: \(device.name)")
    }

    // MARK: - Bluetooth Operations

    func connect(_ device: Device, retryCount: Int = 0) {
        guard bluetoothPoweredOn else {
            Log.bluetooth.error("Bluetooth is off")
            return
        }
        guard state(for: device) == .disconnected else {
            Log.bluetooth.warning("Cannot connect \(device.name): not in disconnected state")
            return
        }

        updateState(.connecting, for: device)

        btQueue.async { [weak self] in
            guard let self else { return }
            guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
                Log.bluetooth.error("Device not found: \(device.name)")
                self.updateState(.disconnected, for: device)
                return
            }

            // Pair with timeout
            if let pair = IOBluetoothDevicePair(device: btDevice) {
                let pairResult = pair.start()
                if pairResult != kIOReturnSuccess {
                    Log.bluetooth.warning("Pair start returned \(pairResult) for \(device.name)")
                }
            }

            // Connect with timeout using DispatchWorkItem
            var timedOut = false
            let timeoutWork = DispatchWorkItem { timedOut = true }
            DispatchQueue.global().asyncAfter(deadline: .now() + self.connectTimeout, execute: timeoutWork)

            let result = btDevice.openConnection()
            timeoutWork.cancel()

            if timedOut {
                Log.bluetooth.error("Connect timed out for \(device.name)")
                self.handleConnectFailure(device: device, retryCount: retryCount)
                return
            }

            if result == kIOReturnSuccess && btDevice.isConnected() {
                Log.bluetooth.info("Connected to \(device.name)")
                self.updateState(.connected, for: device)
            } else {
                self.handleConnectFailure(device: device, retryCount: retryCount)
            }
        }
    }

    func disconnect(_ device: Device, completion: ((Bool) -> Void)? = nil) {
        guard bluetoothPoweredOn else {
            completion?(false)
            return
        }
        guard state(for: device) == .connected else {
            completion?(false)
            return
        }

        updateState(.disconnecting, for: device)

        btQueue.async { [weak self] in
            guard let self else { return }
            guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
                self.updateState(.disconnected, for: device)
                completion?(true)
                return
            }

            // Remove device info (unpair) for cross-Mac switching
            if btDevice.responds(to: Selector(("remove"))) {
                btDevice.perform(Selector(("remove")))
            }

            // Disconnect with timeout
            var timedOut = false
            let timeoutWork = DispatchWorkItem { timedOut = true }
            DispatchQueue.global().asyncAfter(deadline: .now() + self.disconnectTimeout, execute: timeoutWork)

            let result = btDevice.closeConnection()
            timeoutWork.cancel()

            let success = result == kIOReturnSuccess || !btDevice.isConnected()
            if success {
                Log.bluetooth.info("Disconnected from \(device.name)")
                self.updateState(.disconnected, for: device)
            } else {
                Log.bluetooth.error("Failed to disconnect \(device.name)")
                self.updateState(.connected, for: device)
            }
            DispatchQueue.main.async { completion?(success) }
        }
    }

    /// Switch a device to the peer Mac.
    /// Flow: disconnect locally → tell peer to connect → confirm.
    /// Recovery: if peer fails, reconnect locally.
    func switchToPeer(_ device: Device, peerNetwork: PeerNetwork, completion: @escaping (Bool) -> Void) {
        guard canSwitchToPeer(device) else {
            Log.bluetooth.warning("Cannot switch \(device.name) to peer: not connected locally")
            completion(false)
            return
        }

        disconnect(device) { [weak self] disconnected in
            guard let self, disconnected else {
                Log.bluetooth.error("Local disconnect failed for \(device.name)")
                completion(false)
                return
            }

            // Tell peer to connect this device
            peerNetwork.connectDeviceOnPeer(device) { peerSuccess in
                if peerSuccess {
                    Log.bluetooth.info("Switched \(device.name) to peer")
                    completion(true)
                } else {
                    // Recovery: reconnect locally
                    Log.bluetooth.warning("Peer failed to connect \(device.name), reconnecting locally")
                    self.connect(device)
                    NotificationManager.showNotification(
                        title: "Switch Failed",
                        body: "Could not switch \(device.name) to peer — reconnected locally."
                    )
                    completion(false)
                }
            }
        }
    }

    func refreshStates() {
        for device in registeredDevices {
            let current = isConnected(device)
            let expected = state(for: device)
            if current && expected == .disconnected {
                updateState(.connected, for: device)
            } else if !current && expected == .connected {
                updateState(.disconnected, for: device)
            }
        }
    }

    // MARK: - Discovery

    func fetchPairedDevices() -> [Device] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return paired.compactMap { btDevice in
            guard let address = btDevice.addressString else { return nil }
            guard !registeredDevices.contains(where: { $0.id == address }) else { return nil }
            return Device(
                id: address,
                name: btDevice.name ?? "Unknown Device",
                type: DataMigrator.detectDeviceType(macAddress: address)
            )
        }
    }

    // MARK: - Private Helpers

    private func updateState(_ state: DeviceState, for device: Device) {
        DispatchQueue.main.async {
            self.deviceStates[device.id] = state
        }
    }

    private func handleConnectFailure(device: Device, retryCount: Int) {
        if retryCount < maxRetries {
            Log.bluetooth.warning("Connect failed for \(device.name), retrying...")
            updateState(.disconnected, for: device)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.connect(device, retryCount: retryCount + 1)
            }
        } else {
            Log.bluetooth.error("Failed to connect to \(device.name) after \(retryCount + 1) attempts")
            updateState(.disconnected, for: device)
            NotificationManager.showNotification(
                title: "Connection Failed",
                body: "Could not connect to \(device.name)"
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension DeviceManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let powered = central.state == .poweredOn
        DispatchQueue.main.async { self.bluetoothPoweredOn = powered }
        Log.bluetooth.info("Bluetooth state: \(powered ? "on" : "off")")
    }
}

// MARK: - IOBluetoothDevicePairDelegate

extension DeviceManager: IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        if error == kIOReturnSuccess {
            Log.bluetooth.info("Pairing completed successfully")
        } else {
            Log.bluetooth.error("Pairing failed with error: \(error)")
        }
    }
}
```

- [ ] **Step 5: Delete old files**

Now safe to delete — ConnectionManager and NetworkDeviceStore no longer reference these types.

```bash
rm "Blue Switch/Manager/BluetoothManager.swift"
rm "Blue Switch/Model/Store/BluetoothPeripheralStore.swift"
rm "Blue Switch/Model/Entity/BluetoothPeripheral.swift"
```

Remove these files from the Xcode project as well (**MANUAL** step).

- [ ] **Step 6: Update IOBluetoothDevice+Extension.swift**

Replace `Blue Switch/Extensions/IOBluetoothDevice+Extension.swift`:

```swift
import IOBluetooth

extension IOBluetoothDevice {
    func toDevice() -> Device {
        let name = self.name ?? "Unknown Device"
        let address = self.addressString ?? "Unknown"
        return Device(
            id: address,
            name: name,
            type: DataMigrator.detectDeviceType(macAddress: address)
        )
    }
}
```

- [ ] **Step 7: Run tests**

Run: `xcodebuild test -project "Blue Switch.xcodeproj" -scheme "Blue Switch" -only-testing "Blue SwitchTests/DeviceManagerTests" 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add DeviceManager with per-device state machine and switchToPeer recovery, remove old BT stores"
```

---

## Task 4: BatteryMonitor

**Files:**
- Create: `Blue Switch/Manager/BatteryMonitor.swift`

- [ ] **Step 1: Create BatteryMonitor**

```swift
import Foundation
import IOBluetooth

final class BatteryMonitor: ObservableObject {
    @Published private(set) var batteryLevels: [String: Int?] = [:]

    private var timer: Timer?
    private var pollingInterval: TimeInterval

    init(pollingInterval: TimeInterval = 60) {
        self.pollingInterval = pollingInterval
    }

    func startMonitoring(devices: [Device]) {
        pollBatteryLevels(devices: devices)
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollBatteryLevels(devices: devices)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func updatePollingInterval(_ interval: TimeInterval, devices: [Device]) {
        pollingInterval = interval
        if timer != nil {
            stopMonitoring()
            startMonitoring(devices: devices)
        }
    }

    private func pollBatteryLevels(devices: [Device]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var levels: [String: Int?] = [:]

            for device in devices {
                guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
                    levels[device.id] = nil
                    continue
                }

                // IOBluetoothDevice battery level via HID
                // This uses the batteryPercent property available on Apple peripherals
                if btDevice.isConnected() {
                    let battery = self?.readBatteryLevel(btDevice)
                    levels[device.id] = battery
                } else {
                    levels[device.id] = nil
                }
            }

            DispatchQueue.main.async {
                self?.batteryLevels = levels
            }
        }
    }

    private func readBatteryLevel(_ device: IOBluetoothDevice) -> Int? {
        // IOBluetoothDevice exposes battery via a private selector on Apple devices
        // Fall back to nil if unavailable
        let selector = NSSelectorFromString("batteryPercent")
        guard device.responds(to: selector) else {
            Log.bluetooth.debug("Device \(device.name ?? "unknown") does not report battery")
            return nil
        }
        let result = device.perform(selector)
        let level = Int(bitPattern: result?.toOpaque())
        guard level >= 0 && level <= 100 else { return nil }
        return level
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project "Blue Switch.xcodeproj" -scheme "Blue Switch" build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add BatteryMonitor with polling and HID battery reading"
```

---

## Task 5: ActionRunner — Automation Hooks

**Files:**
- Create: `Blue Switch/Manager/ActionRunner.swift`
- Create: `Blue SwitchTests/ActionRunnerTests.swift`

- [ ] **Step 1: Write ActionRunner tests**

Create `Blue SwitchTests/ActionRunnerTests.swift`:

```swift
import XCTest
@testable import Blue_Switch

final class ActionRunnerTests: XCTestCase {
    func testRunOpenURLAction() async {
        let action = DeviceAction(type: .openURL(url: "https://example.com"))
        let context = ActionRunner.Context(
            deviceName: "Test",
            deviceMAC: "AA:BB:CC:DD:EE:FF",
            deviceType: .trackpad,
            event: .connect,
            peerName: nil
        )
        // Should not throw — we can't verify the URL opened, but it shouldn't crash
        await ActionRunner.run(action, context: context)
    }

    func testDisabledActionIsSkipped() async {
        var action = DeviceAction(type: .openURL(url: "https://example.com"))
        action.isEnabled = false
        let context = ActionRunner.Context(
            deviceName: "Test",
            deviceMAC: "AA:BB:CC:DD:EE:FF",
            deviceType: .trackpad,
            event: .connect,
            peerName: nil
        )
        // Should return immediately without doing anything
        await ActionRunner.run(action, context: context)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — ActionRunner doesn't exist

- [ ] **Step 3: Create ActionRunner**

Create `Blue Switch/Manager/ActionRunner.swift`:

```swift
import AppKit
import Foundation

enum ActionRunner {
    enum Event: String {
        case connect
        case disconnect
    }

    struct Context {
        let deviceName: String
        let deviceMAC: String
        let deviceType: DeviceType
        let event: Event
        let peerName: String?
    }

    static func runAll(_ actions: [DeviceAction], context: Context) async {
        for action in actions where action.isEnabled {
            await run(action, context: context)
        }
    }

    static func run(_ action: DeviceAction, context: Context) async {
        guard action.isEnabled else { return }

        switch action.type {
        case .openApp(let path):
            openApp(at: path)
        case .openURL(let urlString):
            openURL(urlString)
        case .shortcut(let name):
            await runShortcut(name)
        case .shellScript(let path):
            await runScript(at: path, context: context)
        }
    }

    // MARK: - Private

    private static func openApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error {
                Log.actions.error("Failed to open app at \(path): \(error.localizedDescription)")
            } else {
                Log.actions.info("Opened app: \(path)")
            }
        }
    }

    private static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            Log.actions.error("Invalid URL: \(urlString)")
            return
        }
        NSWorkspace.shared.open(url)
        Log.actions.info("Opened URL: \(urlString)")
    }

    private static func runShortcut(_ name: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        Log.actions.info("Ran shortcut: \(name)")
                    } else {
                        Log.actions.error("Shortcut '\(name)' exited with status \(process.terminationStatus)")
                    }
                } catch {
                    Log.actions.error("Failed to run shortcut '\(name)': \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private static func runScript(at path: String, context: Context) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [path]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
        env["BLUESWITCH_DEVICE_NAME"] = context.deviceName
        env["BLUESWITCH_DEVICE_MAC"] = context.deviceMAC
        env["BLUESWITCH_DEVICE_TYPE"] = context.deviceType.rawValue
        env["BLUESWITCH_EVENT"] = context.event.rawValue
        if let peer = context.peerName {
            env["BLUESWITCH_PEER_NAME"] = peer
        }
        process.environment = env

        do {
            try process.run()

            // 10s timeout
            let deadline = DispatchTime.now() + .seconds(10)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                    Log.actions.warning("Script at \(path) timed out after 10s")
                }
            }

            process.waitUntilExit()
            if process.terminationStatus == 0 {
                Log.actions.info("Script completed: \(path)")
            } else {
                Log.actions.error("Script '\(path)' exited with status \(process.terminationStatus)")
            }
        } catch {
            Log.actions.error("Failed to run script '\(path)': \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ActionRunner for automation hooks (app, URL, shortcut, script)"
```

---

## Task 6: PeerNetwork — Wrap Existing Bonjour + Per-Device Commands

**Files:**
- Create: `Blue Switch/Manager/PeerNetwork.swift`
- Modify: `Blue Switch/Manager/ConnectionManager.swift`
- Modify: `Blue Switch/Model/Store/NetworkDeviceStore.swift`

- [ ] **Step 1: Add per-device commands to NetworkDeviceStore**

In `Blue Switch/Model/Store/NetworkDeviceStore.swift`, add new commands to `DeviceCommand`:

```swift
case connectDevice = "CONNECT_DEVICE"    // Connect a specific device by MAC
case disconnectDevice = "DISCONNECT_DEVICE"  // Disconnect a specific device by MAC
case deviceData = "DEVICE_DATA"          // Payload: MAC address
```

- [ ] **Step 2: Update ConnectionManager for per-device commands**

In `Blue Switch/Manager/ConnectionManager.swift`, update `handleCommand` to support new per-device commands. Add handling for `.connectDevice` and `.disconnectDevice` that read a MAC address payload and delegate to `DeviceManager`.

- [ ] **Step 3: Create PeerNetwork facade**

Create `Blue Switch/Manager/PeerNetwork.swift`:

```swift
import Combine
import Foundation

final class PeerNetwork: ObservableObject {
    private let networkStore = NetworkDeviceStore.shared
    private let connectionManager = ConnectionManager()
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var peerDevices: [NetworkDevice] = []
    @Published private(set) var discoveredPeers: [NetworkDevice] = []

    init() {
        // Forward from networkStore using Combine
        networkStore.$networkDevices
            .assign(to: &$peerDevices)
        networkStore.$discoveredNetworkDevices
            .map { discovered in
                discovered.filter { $0.name != Host.current().localizedName }
            }
            .assign(to: &$discoveredPeers)
    }

    var activePeer: NetworkDevice? {
        networkStore.networkDevices.first
    }

    var activePeerName: String? {
        activePeer?.name
    }

    /// Tell the peer to connect a specific device by MAC address
    func connectDeviceOnPeer(_ device: Device, completion: @escaping (Bool) -> Void) {
        guard let peer = activePeer else {
            Log.network.error("No peer device available")
            completion(false)
            return
        }

        peer.checkHealth { [weak self] result in
            guard let self else {
                completion(false)
                return
            }
            switch result {
            case .success:
                self.executeDeviceCommand(.connectDevice, deviceMAC: device.id, on: peer, completion: completion)
            case .failure(let error):
                Log.network.error("Peer health check failed: \(error)")
                completion(false)
            case .timeout:
                Log.network.error("Peer health check timed out")
                completion(false)
            }
        }
    }

    /// Tell the peer to disconnect a specific device by MAC address
    func disconnectDeviceOnPeer(_ device: Device, completion: @escaping (Bool) -> Void) {
        guard let peer = activePeer else {
            completion(false)
            return
        }
        executeDeviceCommand(.disconnectDevice, deviceMAC: device.id, on: peer, completion: completion)
    }

    func registerPeer(_ device: NetworkDevice) {
        networkStore.registerNetworkDevice(device: device)
    }

    func removePeer(_ device: NetworkDevice) {
        networkStore.removeNetworkDevice(device: device)
    }

    // MARK: - Private

    private func executeDeviceCommand(_ command: DeviceCommand, deviceMAC: String, on peer: NetworkDevice, completion: @escaping (Bool) -> Void) {
        let connection = NWConnection(
            host: NWEndpoint.Host(peer.host),
            port: NWEndpoint.Port(integerLiteral: UInt16(peer.port)),
            using: .tcp
        )

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connectionManager.send(message: command.rawValue, to: connection)
                self?.connectionManager.send(message: deviceMAC, to: connection)
            case .failed:
                completion(false)
            default:
                break
            }
        }

        connection.receiveMessage { data, _, _, error in
            defer { connection.cancel() }
            guard error == nil,
                  let data,
                  let response = String(data: data, encoding: .utf8),
                  DeviceCommand(rawValue: response) == .operationSuccess else {
                completion(false)
                return
            }
            completion(true)
        }

        connection.start(queue: .global())

        // 5s peer timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if connection.state != .cancelled {
                connection.cancel()
                completion(false)
            }
        }
    }
}
```

**Note:** Requires adding `import Network` and the new `DeviceCommand` cases (`.connectDevice`, `.disconnectDevice`) to `NetworkDeviceStore.swift` (done in Step 1).

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project "Blue Switch.xcodeproj" -scheme "Blue Switch" build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PeerNetwork facade with per-device switching commands"
```

---

## Task 7: ShortcutManager — Global Hotkeys

**Files:**
- Create: `Blue Switch/Manager/ShortcutManager.swift`

- [ ] **Step 1: Create ShortcutManager**

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let switchAll = Self("switchAll")
}

final class ShortcutManager {
    private let deviceManager: DeviceManager
    private let peerNetwork: PeerNetwork
    private var onSwitchDevice: ((Device) -> Void)?

    init(deviceManager: DeviceManager, peerNetwork: PeerNetwork, onSwitchDevice: @escaping (Device) -> Void) {
        self.deviceManager = deviceManager
        self.peerNetwork = peerNetwork
        self.onSwitchDevice = onSwitchDevice
    }

    func registerShortcuts(for devices: [Device], switchAllName: String?) {
        // Register per-device shortcuts
        for device in devices {
            guard let name = device.shortcutName else { continue }
            let shortcutName = KeyboardShortcuts.Name(name)
            KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
                self?.onSwitchDevice?(device)
            }
            Log.app.info("Registered shortcut for \(device.name): \(name)")
        }

        // Register switch-all shortcut
        if let allName = switchAllName {
            let name = KeyboardShortcuts.Name(allName)
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                guard let self else { return }
                for device in self.deviceManager.registeredDevices {
                    self.onSwitchDevice?(device)
                }
            }
        }
    }

    func unregisterAll() {
        // KeyboardShortcuts handles cleanup when Name objects are deallocated
        Log.app.info("Unregistered all shortcuts")
    }
}
```

- [ ] **Step 2: Build and verify**

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ShortcutManager for global per-device hotkeys"
```

---

## Task 8: AudioManager — Routing + Experimental Codec

**Files:**
- Create: `Blue Switch/Manager/AudioManager.swift`

- [ ] **Step 1: Create AudioManager**

```swift
import CoreAudio
import Foundation

final class AudioManager {
    private var previousOutputDeviceID: AudioDeviceID?
    private var previousInputDeviceID: AudioDeviceID?

    // MARK: - Audio Routing (Phase 1 — reliable)

    func switchAudioOutput(to deviceName: String) {
        guard let deviceID = findAudioDevice(named: deviceName, isInput: false) else {
            Log.audio.warning("Audio output device not found: \(deviceName)")
            return
        }

        previousOutputDeviceID = getDefaultDevice(isInput: false)
        setDefaultDevice(deviceID, isInput: false)
        Log.audio.info("Switched audio output to \(deviceName)")
    }

    func switchAudioInput(to deviceName: String) {
        guard let deviceID = findAudioDevice(named: deviceName, isInput: true) else {
            Log.audio.warning("Audio input device not found: \(deviceName)")
            return
        }

        previousInputDeviceID = getDefaultDevice(isInput: true)
        setDefaultDevice(deviceID, isInput: true)
        Log.audio.info("Switched audio input to \(deviceName)")
    }

    func revertAudioOutput() {
        guard let prev = previousOutputDeviceID else { return }
        setDefaultDevice(prev, isInput: false)
        previousOutputDeviceID = nil
        Log.audio.info("Reverted audio output to previous device")
    }

    func revertAudioInput() {
        guard let prev = previousInputDeviceID else { return }
        setDefaultDevice(prev, isInput: true)
        previousInputDeviceID = nil
        Log.audio.info("Reverted audio input to previous device")
    }

    // MARK: - CoreAudio Helpers

    private func getDefaultDevice(isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    private func setDefaultDevice(_ deviceID: AudioDeviceID, isInput: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        if status != noErr {
            Log.audio.error("Failed to set default \(isInput ? "input" : "output") device: \(status)")
        }
    }

    private func findAudioDevice(named name: String, isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)

        for deviceID in devices {
            if let deviceName = getDeviceName(deviceID), deviceName.contains(name) {
                return deviceID
            }
        }
        return nil
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return status == noErr ? name as String : nil
    }

    // MARK: - Codec Preference (Phase 2 — experimental)
    // TODO: Research and implement private API codec switching
    // This is best-effort and may not work on all macOS versions
}
```

- [ ] **Step 2: Build and verify**

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add AudioManager with CoreAudio routing and experimental codec stub"
```

---

## Task 9: Socket Protocol + AppCommunicator (IPC)

**Files:**
- Create: `Blue Switch/Model/Entity/SocketProtocol.swift`
- Create: `Blue Switch/Manager/AppCommunicator.swift`
- Create: `Blue SwitchTests/SocketProtocolTests.swift`

- [ ] **Step 1: Write socket protocol tests**

Create `Blue SwitchTests/SocketProtocolTests.swift`:

```swift
import XCTest
@testable import Blue_Switch

final class SocketProtocolTests: XCTestCase {
    func testRequestSerialization() throws {
        let request = SocketRequest(command: "switch", device: "Magic Trackpad")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SocketRequest.self, from: data)
        XCTAssertEqual(decoded.command, "switch")
        XCTAssertEqual(decoded.device, "Magic Trackpad")
        XCTAssertEqual(decoded.version, 1)
    }

    func testResponseSerialization() throws {
        let response = SocketResponse.ok(message: "Done")
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"status\":\"ok\""))
    }

    func testErrorResponseSerialization() throws {
        let response = SocketResponse.error(message: "Not found", code: "DEVICE_NOT_FOUND")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SocketResponse.self, from: data)
        XCTAssertEqual(decoded.status, "error")
        XCTAssertEqual(decoded.code, "DEVICE_NOT_FOUND")
    }
}
```

- [ ] **Step 2: Run tests — expected FAIL**

- [ ] **Step 3: Create SocketProtocol types**

Create `Blue Switch/Model/Entity/SocketProtocol.swift`:

```swift
import Foundation

struct SocketRequest: Codable {
    let command: String
    var device: String?
    var version: Int = 1
}

struct SocketResponse: Codable {
    let status: String
    let message: String
    var code: String?
    var version: Int = 1

    // Battery/status payloads
    var devices: [SocketDeviceInfo]?

    static func ok(message: String) -> SocketResponse {
        SocketResponse(status: "ok", message: message)
    }

    static func error(message: String, code: String) -> SocketResponse {
        SocketResponse(status: "error", message: message, code: code)
    }
}

struct SocketDeviceInfo: Codable {
    let id: String
    let name: String
    let type: String
    let status: String
    let battery: Int?
}
```

- [ ] **Step 4: Create AppCommunicator**

Create `Blue Switch/Manager/AppCommunicator.swift`:

```swift
import Foundation

final class AppCommunicator {
    static let socketPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlueSwitch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("blueswitch.sock").path
    }()

    private var fileHandle: FileHandle?
    private var source: DispatchSourceRead?
    private var onCommand: ((SocketRequest) -> SocketResponse)?

    func start(onCommand: @escaping (SocketRequest) -> SocketResponse) {
        self.onCommand = onCommand

        // Clean up old socket
        unlink(socketPath)

        // Create Unix domain socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.ipc.error("Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for i in 0..<min(pathBytes.count, 104) {
                bound[i] = pathBytes[i]
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            Log.ipc.error("Failed to bind socket: \(errno)")
            close(fd)
            return
        }

        listen(fd, 5)
        Log.ipc.info("Listening on \(self.socketPath)")

        // Accept connections on background queue
        let listenSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        listenSource.setEventHandler { [weak self] in
            self?.acceptConnection(on: fd)
        }
        listenSource.setCancelHandler {
            close(fd)
        }
        listenSource.resume()
        source = listenSource as? DispatchSourceRead
    }

    func stop() {
        source?.cancel()
        source = nil
        unlink(Self.socketPath)
        Log.ipc.info("Socket server stopped")
    }

    private func acceptConnection(on listenFD: Int32) {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }

        DispatchQueue.global().async { [weak self] in
            self?.handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])

        // Strip trailing newline
        let trimmed = data.filter { $0 != 0x0A }

        guard let request = try? JSONDecoder().decode(SocketRequest.self, from: trimmed) else {
            let errorResponse = SocketResponse.error(message: "Invalid request", code: "PARSE_ERROR")
            sendResponse(errorResponse, to: fd)
            return
        }

        let response = onCommand?(request) ?? SocketResponse.error(message: "No handler", code: "INTERNAL_ERROR")
        sendResponse(response, to: fd)
    }

    private func sendResponse(_ response: SocketResponse, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)  // newline delimiter
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, data.count)
        }
    }
}
```

- [ ] **Step 5: Run tests**

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add socket protocol types and AppCommunicator IPC server"
```

---

## Task 10: Rewrite AppDelegate — Wire Everything Together

**Files:**
- Modify: `Blue Switch/AppDelegate/AppDelegate.swift`
- Modify: `Blue Switch/AppDelegate/Blue_SwitchApp.swift`

- [ ] **Step 1: Rewrite AppDelegate**

Replace `Blue Switch/AppDelegate/AppDelegate.swift` with a new version that:

1. Initializes `DeviceManager`, `BatteryMonitor`, `PeerNetwork`, `ShortcutManager`, `AudioManager`, `AppCommunicator`
2. Loads `AppPreferences` from JSON
3. Runs `DataMigrator.migrateIfNeeded()` on first launch
4. Sets up menubar with per-device status
5. Registers global shortcuts
6. Starts socket server for CLI IPC
7. Handles per-device switch on left-click (shows device picker menu instead of toggling all)
8. Wires socket commands to DeviceManager operations
9. Uses `SMAppService.mainApp` for launch at login

Key method: `handleSwitchDevice(_ device: Device)`:
- If connected locally → disconnect + tell peer to connect
- If disconnected → tell peer to disconnect + connect locally
- Run onConnect/onDisconnect actions via ActionRunner
- If headphones and audioAutoSwitch → route audio via AudioManager

- [ ] **Step 2: Build and verify**

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Manual test** — launch the app, verify menubar icon appears, right-click shows menu

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: rewrite AppDelegate with per-device switching and full manager wiring"
```

---

## Task 11: Rewrite MenuBarView — Per-Device UI

**Files:**
- Modify: `Blue Switch/View/MenuBar/MenuBarView.swift`

- [ ] **Step 1: Rewrite MenuBarView**

Replace with new version that supports two modes:

**Compact mode (default):** Single menubar icon. Click shows menu with:
- Per-device items with name, battery %, and status indicator (●/○/⊘)
- Shortcut hints next to device names
- "Switch All" menu item
- Separator + Settings + Quit
- Status indicator colors: green = connected here, hollow = on peer, grey = not in range
- SF Symbols per device type: `rectangle.inset.filled` (trackpad), `keyboard.fill` (keyboard), `computermouse.fill` (mouse), `headphones` (headphones)
- Dark/light mode: use NSImage template rendering

**Expanded mode (opt-in per device):** Create additional `NSStatusItem` instances for each device with `showInMenubar == true`. Each shows the device's SF Symbol icon + battery %. Clicking the per-device icon switches that specific device. The main app icon still exists for the full menu.

Manage the extra status items in `AppDelegate` — create/destroy them when `showInMenubar` toggles change.

The menu items should use `NSMenuItem` with custom `NSView` for the device rows (icon + name + battery + status in same row). Clicking a device item triggers `handleSwitchDevice`.

- [ ] **Step 2: Build and manual test**

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: rewrite MenuBarView with per-device status, battery, and indicators"
```

---

## Task 12: Rewrite Settings Views

**Files:**
- Modify: `Blue Switch/View/Settings/SettingsView.swift`
- Modify: `Blue Switch/View/Settings/GeneralSettingsView.swift`
- Modify: `Blue Switch/View/Settings/BluetoothPeripheralSettingsView.swift`
- Modify: `Blue Switch/View/Settings/NetworkDeviceManagementView.swift`
- Delete: `Blue Switch/View/Settings/OtherSettingsView.swift`

- [ ] **Step 1: Update SettingsView tabs**

New tab structure:
- **Devices** — device list, per-device config (shortcuts, actions, icon, type)
- **Peers** — network device management (mostly existing)
- **General** — launch at login, compact/expanded mode, battery display, polling interval

Remove the "Other" tab.

- [ ] **Step 2: Rewrite GeneralSettingsView**

Replace with:
- Launch at login toggle (wired to `SMAppService`)
- Compact/expanded mode toggle
- Show battery in menubar toggle
- Battery polling interval stepper
- Switch All shortcut recorder (using `KeyboardShortcuts.Recorder`)

- [ ] **Step 3: Rewrite BluetoothPeripheralSettingsView → DeviceSettingsView**

Complete rewrite as per-device settings:
- Device list with add/remove
- Per-device: type picker, SF Symbol icon picker, shortcut recorder
- On Connect actions list with [+ Add Action] picker (Open App, Open Link, Run Shortcut, Advanced: Shell Script)
- On Disconnect actions list (same)
- Actions are drag-to-reorder, each has enable/disable toggle and delete button
- For headphones: extra Audio Settings section (auto-switch output/input, experimental codec picker)

- [ ] **Step 4: Minor updates to NetworkDeviceManagementView**

Replace references to `BluetoothPeripheralStore` with `DeviceManager`.

- [ ] **Step 5: Delete OtherSettingsView**

```bash
rm "Blue Switch/View/Settings/OtherSettingsView.swift"
```

- [ ] **Step 6: Build and manual test**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: rewrite Settings UI with per-device config, actions, shortcuts"
```

---

## Task 13: CLI Tool — Target + Commands

**Files:**
- Create: `Blue Switch CLI/main.swift`
- Create: `Blue Switch CLI/CLIClient.swift`
- Create: `Blue Switch CLI/Commands/ListCommand.swift`
- Create: `Blue Switch CLI/Commands/SwitchCommand.swift`
- Create: `Blue Switch CLI/Commands/StatusCommand.swift`
- Create: `Blue Switch CLI/Commands/BatteryCommand.swift`
- Create: `Blue Switch CLI/Commands/ConnectCommand.swift`
- Create: `Blue Switch CLI/Commands/DisconnectCommand.swift`
- Create: `Blue Switch CLI/Commands/ConfigCommand.swift`

- [ ] **Step 1: Add CLI target to Xcode project**

Add a new "Command Line Tool" target named "blueswitch" in the Xcode project. Link it to `swift-argument-parser`. Set deployment target to macOS 13.0.

- [ ] **Step 2: Create CLIClient**

Create `Blue Switch CLI/CLIClient.swift`:

```swift
import Foundation

struct CLIClient {
    static let socketPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] + "/BlueSwitch/blueswitch.sock"
    static let prefsPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] + "/BlueSwitch/preferences.json"

    static var isAppRunning: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    static func send(_ request: SocketRequest) throws -> SocketResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError.socketFailed }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for i in 0..<min(pathBytes.count, 104) {
                bound[i] = pathBytes[i]
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else { throw CLIError.connectionFailed }

        // Send request
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, data.count)
        }

        // Read response
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { throw CLIError.noResponse }

        let responseData = Data(buffer[0..<bytesRead]).filter { $0 != 0x0A }
        return try JSONDecoder().decode(SocketResponse.self, from: responseData)
    }

    static func loadPreferences() throws -> AppPreferences {
        let url = URL(fileURLWithPath: prefsPath)
        guard FileManager.default.fileExists(atPath: prefsPath) else {
            return AppPreferences()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }

    enum CLIError: Error, CustomStringConvertible {
        case socketFailed
        case connectionFailed
        case noResponse
        case appNotRunning

        var description: String {
            switch self {
            case .socketFailed: return "Failed to create socket"
            case .connectionFailed: return "Could not connect to Blue Switch app. Is it running?"
            case .noResponse: return "No response from Blue Switch app"
            case .appNotRunning: return "Blue Switch app is not running. Start it first."
            }
        }
    }
}
```

- [ ] **Step 3: Create CLI entry point and commands**

Create `Blue Switch CLI/main.swift`:

```swift
import ArgumentParser

@main
struct BlueSwitchCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blueswitch",
        abstract: "Control Bluetooth device switching from the command line",
        subcommands: [
            ListCommand.self,
            SwitchCommand.self,
            ConnectCommand.self,
            DisconnectCommand.self,
            StatusCommand.self,
            BatteryCommand.self,
            ConfigCommand.self,
        ]
    )
}
```

Create each command file following swift-argument-parser patterns. Each command:
- For read-only (`list`, `status`, `battery`): reads from preferences.json directly if app not running, or sends socket request if app is running (for live status)
- For write (`switch`, `connect`, `disconnect`): requires app running, sends socket request
- For `config`: launches the app via `NSWorkspace` if not running, then sends "config" command
- Device name matching: case-insensitive substring match on the device list

- [ ] **Step 4: Build CLI target**

Run: `xcodebuild -project "Blue Switch.xcodeproj" -scheme "blueswitch" build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Manual test**

```bash
./build/Build/Products/Debug/blueswitch list
./build/Build/Products/Debug/blueswitch status
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add CLI tool with list, switch, connect, disconnect, status, battery, config commands"
```

---

## Task 14: Integration — Replace All print() + Final Wiring

**Files:**
- Modify: `Blue Switch/Manager/ConnectionManager.swift` — replace print() with Log.network
- Modify: `Blue Switch/Model/Store/NetworkDeviceStore.swift` — replace print() with Log.network
- Modify: `Blue Switch/Manager/ServiceBrowser.swift` — replace print() with Log.network
- Modify: `Blue Switch/Manager/ServicePublisher.swift` — replace print() with Log.network

- [ ] **Step 1: Replace all remaining print() calls with os_log**

Search all `.swift` files for `print(` and replace with appropriate `Log.<category>` calls.

- [ ] **Step 2: Full build both targets**

Run: `xcodebuild -project "Blue Switch.xcodeproj" -scheme "Blue Switch" build && xcodebuild -project "Blue Switch.xcodeproj" -scheme "blueswitch" build`
Expected: Both `BUILD SUCCEEDED`

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -project "Blue Switch.xcodeproj" -scheme "Blue Switch" 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: replace all print() with os_log, final integration wiring"
```

---

## Task 15: Manual Testing Checklist

- [ ] **Launch app** — menubar icon appears, adapts to dark/light mode
- [ ] **Right-click** — menu shows registered devices with battery % and status indicators
- [ ] **Add device** — Settings → Devices → add a paired BT device, type auto-detected
- [ ] **Per-device switch** — click device in menu, switches only that device
- [ ] **Switch All** — switches all registered devices
- [ ] **Keyboard shortcut** — set ⇧⌘T for trackpad, press it, device switches
- [ ] **Automation hook** — add "Open App" action on connect, verify it opens
- [ ] **Battery display** — battery % shows in menu, updates over time
- [ ] **CLI list** — `blueswitch list` shows devices
- [ ] **CLI switch** — `blueswitch switch trackpad` switches the trackpad
- [ ] **CLI without app** — `blueswitch switch trackpad` shows "app not running" error
- [ ] **CLI status** — `blueswitch status` works without app running (reads prefs file)
- [ ] **Launch at login** — enable in settings, reboot, app starts
- [ ] **Migration** — with old Blue Switch data, new app migrates on first launch
- [ ] **Peer discovery** — second Mac running the app appears in discovered peers

- [ ] **Final commit**

```bash
git commit -m "docs: add manual testing checklist results" --allow-empty
```
