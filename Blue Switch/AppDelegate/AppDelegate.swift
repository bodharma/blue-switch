import Cocoa
import ServiceManagement
import SwiftUI

/// Application delegate handling lifecycle, manager wiring, and device switching.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Dependencies

    @ObservedObject private var networkStore = NetworkDeviceStore.shared

    private let deviceManager = DeviceManager.shared
    let batteryMonitor = BatteryMonitor()
    private let peerNetwork = PeerNetwork()
    private let audioManager = AudioManager()
    private let appCommunicator = AppCommunicator()
    private lazy var shortcutManager = ShortcutManager(
        onSwitchDevice: { [weak self] device in
            self?.handleSwitchDevice(device)
        },
        onSwitchAll: { [weak self] in
            self?.handleSwitchAll()
        }
    )

    private var preferences = AppPreferences()

    // MARK: - UI Components

    private var statusItem: NSStatusItem!
    private var settingsWindowController: NSWindowController?

    // MARK: - Constants

    private let windowSize = NSSize(width: 480, height: 300)

    // MARK: - Lifecycle Methods

    func applicationDidFinishLaunching(_ notification: Notification) {
        DataMigrator.migrateIfNeeded()
        loadPreferences()
        registerDevicesFromPreferences()
        batteryMonitor.startMonitoring(devices: preferences.devices)
        setupNotifications()
        setupStatusBar()
        registerShortcuts()
        startSocketServer()
        configureLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        batteryMonitor.stopMonitoring()
        shortcutManager.unregisterAll()
        appCommunicator.stop()
        savePreferences()
    }

    // MARK: - Setup Methods

    private func loadPreferences() {
        do {
            preferences = try AppPreferences.load()
            Log.app.info("Loaded preferences with \(self.preferences.devices.count) devices")
        } catch {
            Log.app.error("Failed to load preferences: \(error.localizedDescription)")
            preferences = AppPreferences()
        }
    }

    private func registerDevicesFromPreferences() {
        for device in preferences.devices {
            deviceManager.register(device)
        }
        deviceManager.refreshStates()
    }

    private func setupNotifications() {
        NotificationManager.requestAuthorization()
    }

    private func setupStatusBar() {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        configureStatusBarButton(button)
    }

    private func configureStatusBarButton(_ button: NSStatusBarButton) {
        if let customImage = NSImage(named: "StatusBarIcon") {
            customImage.size = NSSize(width: 24, height: 24)
            button.image = customImage
        }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func registerShortcuts() {
        shortcutManager.registerShortcuts(
            for: preferences.devices,
            switchAllName: preferences.switchAllShortcutName
        )
    }

    private func startSocketServer() {
        appCommunicator.start { [weak self] request in
            guard let self else {
                return SocketResponse.error(message: "App shutting down", code: "SHUTDOWN")
            }
            return self.handleSocketCommand(request)
        }
    }

    private func configureLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            Log.app.info("Launch-at-login requires macOS 13.0+")
            return
        }

        if preferences.launchAtLogin {
            do {
                try SMAppService.mainApp.register()
                Log.app.info("Registered launch-at-login")
            } catch {
                Log.app.error("Failed to register launch-at-login: \(error.localizedDescription)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Log.app.debug("Launch-at-login was not registered")
            }
        }
    }

    // MARK: - Action Handlers

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showMenu()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showMenu()
        default:
            // Left click or any other — show the full menu
            showMenu()
        }
    }

    private func handleLeftClick() {
        // Show device picker menu on left-click
        let menu = NSMenu()

        for device in deviceManager.registeredDevices {
            let state = deviceManager.deviceStates[device.id] ?? .disconnected
            let title = "\(device.name) (\(state))"
            let item = NSMenuItem(title: title, action: #selector(deviceMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            menu.addItem(item)
        }

        if deviceManager.registeredDevices.isEmpty {
            let item = NSMenuItem(title: "No devices configured", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func deviceMenuItemClicked(_ sender: NSMenuItem) {
        guard let deviceId = sender.representedObject as? String,
              let device = deviceManager.registeredDevices.first(where: { $0.id == deviceId }) else {
            return
        }
        handleSwitchDevice(device)
    }

    /// Menu-bar device row action: extracts the device ID stored in `representedObject`
    /// and delegates to the core switching logic.
    @objc func menuSwitchDevice(_ sender: NSMenuItem) {
        guard let deviceId = sender.representedObject as? String,
              let device = deviceManager.registeredDevices.first(where: { $0.id == deviceId }) else {
            return
        }
        handleSwitchDevice(device)
    }

    /// "Switch All" menu item action: switches every registered device in order.
    @objc func switchAllDevices() {
        handleSwitchAll()
    }

    private func showMenu() {
        MenuBarView().showMenu(statusItem: statusItem)
    }

    // MARK: - Device Switching

    /// Core per-device switching logic.
    ///
    /// - If device is connected locally, switch it to the peer.
    /// - If device is disconnected, tell peer to disconnect, then connect locally.
    /// - After switch, run appropriate actions via ActionRunner.
    /// - If device type is .headphones and audioAutoSwitch, route audio via AudioManager.
    func handleSwitchDevice(_ device: Device) {
        let currentState = deviceManager.deviceStates[device.id] ?? .disconnected

        if currentState == .connected {
            // Device is connected locally -- switch to peer
            Log.app.info("Switching \(device.name) to peer...")

            deviceManager.switchToPeer(device, sendPeerConnect: { [weak self] device, completion in
                self?.peerNetwork.connectDeviceOnPeer(device, completion: completion)
            }) { [weak self] success in
                guard let self else { return }
                if success {
                    NotificationManager.showNotification(
                        title: "Switched",
                        body: "\(device.name) switched to \(self.peerNetwork.activePeerName ?? "peer")"
                    )
                    self.runActions(for: device, event: .disconnect)
                    if device.type == .headphones && self.preferences.audioAutoSwitch {
                        self.audioManager.revertAudioOutput()
                    }
                } else {
                    NotificationManager.showNotification(
                        title: "Switch Failed",
                        body: "Could not switch \(device.name) to peer"
                    )
                }
            }
        } else if currentState == .disconnected {
            // Device is disconnected -- tell peer to disconnect, then connect locally
            Log.app.info("Connecting \(device.name) locally...")

            peerNetwork.disconnectDeviceOnPeer(device) { [weak self] peerSuccess in
                guard let self else { return }
                Log.app.info("Peer disconnect result for \(device.name): \(peerSuccess)")

                // Delay to let peer's BT stack fully release the device
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.deviceManager.connect(device) { [weak self] success in
                    guard let self else { return }
                    if success {
                        NotificationManager.showNotification(
                            title: "Connected",
                            body: "\(device.name) connected locally"
                        )
                        self.runActions(for: device, event: .connect)
                        if device.type == .headphones && self.preferences.audioAutoSwitch {
                            self.audioManager.switchAudioOutput(to: device.name)
                        }
                    } else {
                        NotificationManager.showNotification(
                            title: "Connection Failed",
                            body: "Could not connect \(device.name)"
                        )
                    }
                    }
                }
            }
        } else {
            // Device is in a transitional state (.connecting / .disconnecting)
            Log.app.warning("Device \(device.name) is in state \(currentState), ignoring switch request")
            NotificationManager.showNotification(
                title: "Please Wait",
                body: "\(device.name) is currently \(currentState)"
            )
        }
    }

    /// Switch all registered devices at once.
    private func handleSwitchAll() {
        Log.app.info("Switching all devices...")
        for device in deviceManager.registeredDevices {
            handleSwitchDevice(device)
        }
    }

    private func runActions(for device: Device, event: ActionRunner.Event) {
        let actions = event == .connect ? device.onConnectActions : device.onDisconnectActions
        guard !actions.isEmpty else { return }

        let context = ActionRunner.Context(
            deviceName: device.name,
            deviceMAC: device.id,
            deviceType: device.type,
            event: event,
            peerName: peerNetwork.activePeerName
        )

        Task {
            await ActionRunner.runAll(actions, context: context)
        }
    }

    // MARK: - Socket Command Handler

    private func handleSocketCommand(_ request: SocketRequest) -> SocketResponse {
        switch request.command {
        case "switch":
            guard let deviceId = request.device,
                  let device = deviceManager.registeredDevices.first(where: { $0.id == deviceId }) else {
                return .error(message: "Device not found", code: "DEVICE_NOT_FOUND")
            }
            DispatchQueue.main.async { [weak self] in
                self?.handleSwitchDevice(device)
            }
            return .ok(message: "Switch initiated for \(device.name)")

        case "connect":
            guard let deviceId = request.device,
                  let device = deviceManager.registeredDevices.first(where: { $0.id == deviceId }) else {
                return .error(message: "Device not found", code: "DEVICE_NOT_FOUND")
            }
            DispatchQueue.main.async { [weak self] in
                self?.deviceManager.connect(device) { success in
                    Log.ipc.info("Connect \(device.name) via socket: \(success)")
                }
            }
            return .ok(message: "Connect initiated for \(device.name)")

        case "disconnect":
            guard let deviceId = request.device,
                  let device = deviceManager.registeredDevices.first(where: { $0.id == deviceId }) else {
                return .error(message: "Device not found", code: "DEVICE_NOT_FOUND")
            }
            DispatchQueue.main.async { [weak self] in
                self?.deviceManager.disconnect(device) { success in
                    Log.ipc.info("Disconnect \(device.name) via socket: \(success)")
                }
            }
            return .ok(message: "Disconnect initiated for \(device.name)")

        case "list":
            let devices = deviceManager.registeredDevices.map { device in
                SocketDeviceInfo(
                    id: device.id,
                    name: device.name,
                    type: device.type.rawValue,
                    status: (deviceManager.deviceStates[device.id] ?? .disconnected).rawValue,
                    battery: batteryMonitor.batteryLevels[device.id] ?? nil
                )
            }
            var response = SocketResponse.ok(message: "Listed \(devices.count) devices")
            response.devices = devices
            return response

        case "status":
            guard let deviceId = request.device,
                  let device = deviceManager.registeredDevices.first(where: { $0.id == deviceId }) else {
                return .error(message: "Device not found", code: "DEVICE_NOT_FOUND")
            }
            let state = deviceManager.deviceStates[device.id] ?? .disconnected
            let battery = batteryMonitor.batteryLevels[device.id] ?? nil
            var response = SocketResponse.ok(message: "\(device.name): \(state)")
            response.devices = [
                SocketDeviceInfo(
                    id: device.id,
                    name: device.name,
                    type: device.type.rawValue,
                    status: state.rawValue,
                    battery: battery
                )
            ]
            return response

        case "battery":
            let devices = deviceManager.registeredDevices.map { device in
                SocketDeviceInfo(
                    id: device.id,
                    name: device.name,
                    type: device.type.rawValue,
                    status: (deviceManager.deviceStates[device.id] ?? .disconnected).rawValue,
                    battery: batteryMonitor.batteryLevels[device.id] ?? nil
                )
            }
            var response = SocketResponse.ok(message: "Battery levels")
            response.devices = devices
            return response

        case "config":
            let message = """
                devices: \(preferences.devices.count), \
                launchAtLogin: \(preferences.launchAtLogin), \
                audioAutoSwitch: \(preferences.audioAutoSwitch), \
                batteryPolling: \(preferences.batteryPollingInterval)s
                """
            return .ok(message: message)

        default:
            return .error(message: "Unknown command: \(request.command)", code: "UNKNOWN_COMMAND")
        }
    }

    // MARK: - Preferences

    func savePreferences() {
        do {
            try preferences.save()
            Log.app.info("Preferences saved")
        } catch {
            Log.app.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings Management

    @objc func openPreferencesWindow() {
        if settingsWindowController == nil {
            let settingsWindow = createSettingsWindow()
            settingsWindowController = NSWindowController(window: settingsWindow)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.orderFrontRegardless()
    }

    private func createSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView())

        return window
    }
}
