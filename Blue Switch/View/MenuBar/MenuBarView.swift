import SwiftUI

protocol MenuBarPresentable {
  func showMenu(statusItem: NSStatusItem)
}

final class MenuBarView: MenuBarPresentable {
  // MARK: - Constants

  private enum Constants {
    enum Menu {
      static let settings = "Settings..."
      static let quit = "Quit"
    }

    enum KeyEquivalents {
      static let settings = ","
      static let quit = "q"
    }
  }

  // MARK: - Dependencies

  @ObservedObject private var networkStore = NetworkDeviceStore.shared

  // MARK: - Public Methods

  func showMenu(statusItem: NSStatusItem) {
    let menu = createMenu()
    presentMenu(menu, for: statusItem)
  }

  // MARK: - Private Methods

  private func createMenu() -> NSMenu {
    let menu = NSMenu()

    addDeviceItems(to: menu)
    addSettingsItems(to: menu)
    addQuitItem(to: menu)

    return menu
  }

  private func addDeviceItems(to menu: NSMenu) {
    addNetworkDeviceItems(to: menu)
    addSeparator(to: menu)
    addBluetoothDeviceItems(to: menu)
    addSeparator(to: menu)
  }

  private func addNetworkDeviceItems(to menu: NSMenu) {
    for device in networkStore.networkDevices {
      menu.addItem(NSMenuItem(title: device.name, action: nil, keyEquivalent: ""))
    }
  }

  private func addBluetoothDeviceItems(to menu: NSMenu) {
    // TODO: Re-implement using DeviceManager.shared.registeredDevices
    for device in DeviceManager.shared.registeredDevices {
      menu.addItem(NSMenuItem(title: device.name, action: nil, keyEquivalent: ""))
    }
  }

  private func addSettingsItems(to menu: NSMenu) {
    menu.addItem(
      NSMenuItem(
        title: Constants.Menu.settings,
        action: #selector(AppDelegate.openPreferencesWindow),
        keyEquivalent: Constants.KeyEquivalents.settings
      ))
  }

  private func addQuitItem(to menu: NSMenu) {
    menu.addItem(
      NSMenuItem(
        title: Constants.Menu.quit,
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: Constants.KeyEquivalents.quit
      ))
  }

  private func addSeparator(to menu: NSMenu) {
    menu.addItem(NSMenuItem.separator())
  }

  private func presentMenu(_ menu: NSMenu, for statusItem: NSStatusItem) {
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }
}
