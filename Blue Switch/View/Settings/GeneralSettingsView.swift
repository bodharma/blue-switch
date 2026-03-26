import SwiftUI
import ServiceManagement

/// View responsible for managing general application configuration settings
struct GeneralSettingsView: View {
  // MARK: - Properties

  @State private var prefs = (try? AppPreferences.load()) ?? AppPreferences()
  @State private var launchAtLogin = false

  // MARK: - View Content

  private var formContent: some View {
    Form {
      Section(header: Text("Startup")) {
        Toggle("Launch at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { newValue in
            if #available(macOS 13.0, *) {
              do {
                if newValue {
                  try SMAppService.mainApp.register()
                } else {
                  try SMAppService.mainApp.unregister()
                }
              } catch {
                Log.app.error("Failed to update launch at login: \(error.localizedDescription)")
              }
            }
            prefs.launchAtLogin = newValue
            savePrefs()
          }
      }

      Section(header: Text("Display")) {
        Toggle("Compact menubar mode", isOn: $prefs.compactMode)
          .onChange(of: prefs.compactMode) { _ in savePrefs() }

        Toggle("Show battery in menubar", isOn: $prefs.showBatteryInMenubar)
          .onChange(of: prefs.showBatteryInMenubar) { _ in savePrefs() }

        Stepper(
          "Battery polling: \(prefs.batteryPollingInterval)s",
          value: $prefs.batteryPollingInterval,
          in: 15...300,
          step: 15
        )
        .onChange(of: prefs.batteryPollingInterval) { _ in savePrefs() }
      }

      Section(header: Text("Audio")) {
        Toggle("Auto-switch audio for headphones", isOn: $prefs.audioAutoSwitch)
          .onChange(of: prefs.audioAutoSwitch) { _ in savePrefs() }
      }

      Section(header: Text("Notifications")) {
        Toggle("Enable notifications", isOn: .constant(true))
          .disabled(true)
          .help("Manage in System Settings → Notifications")
      }
    }
  }

  var body: some View {
    if #available(macOS 13.0, *) {
      formContent
        .formStyle(.grouped)
        .onAppear { refreshLaunchAtLogin() }
    } else {
      formContent
        .onAppear { refreshLaunchAtLogin() }
    }
  }

  // MARK: - Private Methods

  private func refreshLaunchAtLogin() {
    if #available(macOS 13.0, *) {
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }

  private func savePrefs() {
    try? prefs.save()
  }
}

// MARK: - Preview

#Preview {
  GeneralSettingsView()
}
