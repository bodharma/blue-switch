import SwiftUI

/// Main settings view that handles all application configuration through tab-based navigation
struct SettingsView: View {
  // MARK: - Properties

  /// Window dimensions for the settings view
  private let windowSize = CGSize(width: 650, height: 450)

  // MARK: - View Content

  var body: some View {
    TabView {
      DeviceSettingsView()
        .tabItem { Label("Devices", systemImage: "keyboard") }

      NetworkDeviceManagementView()
        .tabItem { Label("Peers", systemImage: "desktopcomputer") }

      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape.fill") }
    }
    .frame(width: windowSize.width, height: windowSize.height)
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
}
