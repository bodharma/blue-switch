import Cocoa

// MARK: - Protocol

protocol MenuBarPresentable {
    func showMenu(statusItem: NSStatusItem)
}

// MARK: - MenuBarView

/// Builds and presents the status-item menu with per-device status rows,
/// a "Switch All" action, Settings, and Quit.
final class MenuBarView: MenuBarPresentable {

    // MARK: - Constants

    private enum Constants {
        enum Menu {
            static let switchAll = "Switch All"
            static let settings = "Settings..."
            static let quit = "Quit"
            static let noDevices = "No devices configured"
        }
        enum KeyEquivalents {
            static let settings = ","
            static let quit = "q"
        }
    }

    // MARK: - MenuBarPresentable

    func showMenu(statusItem: NSStatusItem) {
        let menu = createMenu()
        presentMenu(menu, for: statusItem)
    }

    // MARK: - Menu Construction

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        addDeviceItems(to: menu)
        menu.addItem(.separator())
        addSwitchAllItem(to: menu)
        menu.addItem(.separator())
        addSettingsItem(to: menu)
        addQuitItem(to: menu)

        return menu
    }

    private func addDeviceItems(to menu: NSMenu) {
        let deviceManager = DeviceManager.shared

        if deviceManager.registeredDevices.isEmpty {
            let emptyItem = NSMenuItem(
                title: Constants.Menu.noDevices,
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for device in deviceManager.registeredDevices {
            menu.addItem(createDeviceMenuItem(for: device, deviceManager: deviceManager))
        }
    }

    private func addSwitchAllItem(to menu: NSMenu) {
        let item = NSMenuItem(
            title: Constants.Menu.switchAll,
            action: #selector(AppDelegate.switchAllDevices),
            keyEquivalent: ""
        )
        menu.addItem(item)
    }

    private func addSettingsItem(to menu: NSMenu) {
        menu.addItem(NSMenuItem(
            title: Constants.Menu.settings,
            action: #selector(AppDelegate.openPreferencesWindow),
            keyEquivalent: Constants.KeyEquivalents.settings
        ))
    }

    private func addQuitItem(to menu: NSMenu) {
        menu.addItem(NSMenuItem(
            title: Constants.Menu.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: Constants.KeyEquivalents.quit
        ))
    }

    // MARK: - Device Menu Item

    private func createDeviceMenuItem(for device: Device, deviceManager: DeviceManager) -> NSMenuItem {
        let state = deviceManager.deviceStates[device.id] ?? .disconnected
        let statusGlyph = statusGlyph(for: state)
        let batteryText = batteryText(for: device)
        let stateLabel = stateLabel(for: state)

        let title = "\(device.name)  \(batteryText)  \(statusGlyph) \(stateLabel)"
        let item = NSMenuItem(
            title: title,
            action: #selector(AppDelegate.menuSwitchDevice(_:)),
            keyEquivalent: ""
        )
        item.representedObject = device.id

        // Set SF Symbol as proper image
        let symbolName = sfSymbolName(for: device.type)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: device.type.rawValue) {
            image.isTemplate = true
            item.image = image
        }

        return item
    }

    private func stateLabel(for state: DeviceConnectionState) -> String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnecting: return "Disconnecting..."
        case .disconnected: return "Disconnected"
        }
    }

    // MARK: - Helpers

    /// Returns the SF Symbol name appropriate for the given device type.
    private func sfSymbolName(for type: DeviceType) -> String {
        switch type {
        case .trackpad:  return "rectangle.inset.filled"
        case .keyboard:  return "keyboard.fill"
        case .mouse:     return "computermouse.fill"
        case .headphones: return "headphones"
        case .other:     return "circle.fill"
        }
    }

    /// Returns the Unicode status glyph for a connection state.
    ///
    /// - "●" green: connected locally
    /// - "◐": transitional (connecting / disconnecting)
    /// - "⊘": disconnected / out of range
    private func statusGlyph(for state: DeviceConnectionState) -> String {
        switch state {
        case .connected:                  return "●"
        case .connecting, .disconnecting: return "◐"
        case .disconnected:               return "⊘"
        }
    }

    /// Returns a formatted battery string, or "—" when the level is unavailable.
    private func batteryText(for device: Device) -> String {
        guard let delegate = NSApp.delegate as? AppDelegate else { return "—" }
        guard let entry = delegate.batteryMonitor.batteryLevels[device.id] else { return "—" }
        guard let level = entry else { return "—" }
        return "\(level)%"
    }

    // MARK: - Presentation

    private func presentMenu(_ menu: NSMenu, for statusItem: NSStatusItem) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
