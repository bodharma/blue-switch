import SwiftUI

// MARK: - DeviceSettingsView

/// View for managing registered and available Bluetooth devices
struct DeviceSettingsView: View {
  // MARK: - Dependencies

  @ObservedObject private var deviceManager = DeviceManager.shared

  // MARK: - Properties

  @State private var prefs = (try? AppPreferences.load()) ?? AppPreferences()

  // MARK: - View Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List {
        Section(header: Text("Registered Devices")) {
          ForEach(prefs.devices) { device in
            DeviceRow(
              device: device,
              state: deviceManager.deviceStates[device.id] ?? .disconnected
            )
          }
          .onDelete(perform: removeDevices)
        }

        Section(header: Text("Available Devices")) {
          let available = deviceManager.fetchPairedDevices().filter { paired in
            !prefs.devices.contains(where: { $0.id == paired.id })
          }
          if available.isEmpty {
            Text("No new devices found")
              .foregroundColor(.secondary)
          } else {
            ForEach(available) { device in
              HStack {
                Image(systemName: iconForDeviceType(device.type))
                Text(device.name)
                Spacer()
                Button("Add") {
                  addDevice(device)
                }
              }
            }
          }
        }
      }
    }
    .onAppear {
      deviceManager.refreshStates()
    }
  }

  // MARK: - Private Methods

  private func addDevice(_ device: Device) {
    prefs.devices.append(device)
    deviceManager.register(device)
    try? prefs.save()
  }

  private func removeDevices(at offsets: IndexSet) {
    for index in offsets {
      let device = prefs.devices[index]
      deviceManager.unregister(device)
    }
    prefs.devices.remove(atOffsets: offsets)
    try? prefs.save()
  }
}

// MARK: - DeviceRow

/// Row view displaying an individual device with its connection state
struct DeviceRow: View {
  // MARK: - Properties

  let device: Device
  let state: DeviceConnectionState

  // MARK: - View Content

  var body: some View {
    HStack {
      Image(systemName: iconForDeviceType(device.type))
        .foregroundColor(state == .connected ? .green : .secondary)
      VStack(alignment: .leading) {
        Text(device.name)
          .font(.body)
        Text(device.type.rawValue.capitalized)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      Text(stateText)
        .font(.caption)
        .foregroundColor(stateColor)
    }
  }

  // MARK: - Private Computed Properties

  private var stateText: String {
    switch state {
    case .connected: return "Connected"
    case .connecting: return "Connecting..."
    case .disconnecting: return "Disconnecting..."
    case .disconnected: return "Disconnected"
    }
  }

  private var stateColor: Color {
    switch state {
    case .connected: return .green
    case .connecting, .disconnecting: return .orange
    case .disconnected: return .secondary
    }
  }
}

// MARK: - Helpers

private func iconForDeviceType(_ type: DeviceType) -> String {
  switch type {
  case .trackpad: return "rectangle.inset.filled"
  case .keyboard: return "keyboard.fill"
  case .mouse: return "computermouse.fill"
  case .headphones: return "headphones"
  case .other: return "circle.fill"
  }
}

// MARK: - Preview

#Preview {
  DeviceSettingsView()
}
