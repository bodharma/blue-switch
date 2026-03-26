import Cocoa
import SwiftUI

/// Application delegate handling lifecycle and UI setup
final class AppDelegate: NSObject, NSApplicationDelegate {
  // MARK: - Dependencies

  @ObservedObject private var networkStore = NetworkDeviceStore.shared

  // MARK: - UI Components

  private var statusItem: NSStatusItem!
  private var settingsWindowController: NSWindowController?

  // MARK: - Constants

  private let windowSize = NSSize(width: 480, height: 300)

  // MARK: - Lifecycle Methods

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupNotifications()
    setupStatusBar()
  }

  // MARK: - Setup Methods

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

  // MARK: - Action Handlers

  @objc private func handleClick(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    switch event.type {
    case .rightMouseUp:
      showMenu()
    case .leftMouseUp:
      handleLeftClick()
    default:
      break
    }
  }

  private func showMenu() {
    MenuBarView().showMenu(statusItem: statusItem)
  }

  private func handleLeftClick() {
    // TODO: Re-implement via DeviceManager per-device switching
    guard let targetDevice = networkStore.networkDevices.first else {
      NotificationManager.showNotification(
        title: "Error",
        body: "No devices connected. Please connect a device first."
      )
      return
    }

    targetDevice.checkHealth { result in
      switch result {
      case .success:
        NotificationManager.showNotification(
          title: "Info",
          body: "Per-device switching not yet implemented"
        )

      case .failure(let error):
        NotificationManager.showNotification(
          title: "Error",
          body: "Failed to communicate with device: \(error)"
        )

      case .timeout:
        NotificationManager.showNotification(
          title: "Error",
          body: "No response from device. Please check if the app is running."
        )
      }
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
