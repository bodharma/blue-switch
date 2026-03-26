import SwiftUI

/// View responsible for managing Bluetooth peripheral device connections and settings
struct BluetoothPeripheralSettingsView: View {
  // MARK: - Dependencies

  @StateObject private var deviceManager = DeviceManager.shared

  // MARK: - View Content

  private var content: some View {
    Form {
      RegisteredDevicesSectionView(
        devices: deviceManager.registeredDevices,
        deviceStates: deviceManager.deviceStates,
        onDeviceToggleConnection: handleDeviceToggleConnection,
        onDeviceRemove: handleDeviceRemove
      )

      AvailableDevicesSectionView(
        devices: deviceManager.fetchPairedDevices().filter { paired in
          !deviceManager.registeredDevices.contains(where: { $0.id == paired.id })
        },
        onDeviceAdd: handleDeviceAdd
      )
    }
    .onAppear {
      deviceManager.refreshStates()
    }
  }

  var body: some View {
    if #available(macOS 13.0, *) {
      content.formStyle(.grouped)
    } else {
      content
    }
  }

  // MARK: - Private Methods

  private func handleDeviceToggleConnection(_ device: Device) {
    let state = deviceManager.deviceStates[device.id] ?? .disconnected
    if state == .connected {
      deviceManager.disconnect(device) { _ in }
    } else {
      deviceManager.connect(device) { _ in }
    }
  }

  private func handleDeviceRemove(_ device: Device) {
    deviceManager.unregister(device)
  }

  private func handleDeviceAdd(_ device: Device) {
    deviceManager.register(device)
  }
}

// MARK: - Supporting Views

/// Section for displaying registered Bluetooth devices
private struct RegisteredDevicesSectionView: View {
  let devices: [Device]
  let deviceStates: [String: DeviceConnectionState]
  let onDeviceToggleConnection: (Device) -> Void
  let onDeviceRemove: (Device) -> Void

  var body: some View {
    Section(header: Text("Registered Peripherals")) {
      if devices.isEmpty {
        Text("No registered peripherals")
          .foregroundColor(.secondary)
      } else {
        DeviceListView(
          devices: devices,
          deviceStates: deviceStates,
          showConnectionStatus: true,
          primaryAction: onDeviceToggleConnection,
          secondaryAction: onDeviceRemove
        )
      }
    }
  }
}

/// Section for displaying available Bluetooth devices
private struct AvailableDevicesSectionView: View {
  let devices: [Device]
  let onDeviceAdd: (Device) -> Void

  var body: some View {
    Section(header: Text("Available Peripherals")) {
      if devices.isEmpty {
        Text("No available peripherals found")
          .foregroundColor(.secondary)
      } else {
        DeviceListView(
          devices: devices,
          deviceStates: [:],
          showConnectionStatus: false,
          primaryAction: onDeviceAdd
        )
      }
    }
  }
}

/// List view for displaying Bluetooth devices
private struct DeviceListView: View {
  let devices: [Device]
  let deviceStates: [String: DeviceConnectionState]
  let showConnectionStatus: Bool
  let primaryAction: (Device) -> Void
  var secondaryAction: ((Device) -> Void)?

  var body: some View {
    List {
      ForEach(devices) { device in
        DeviceRowView(
          device: device,
          state: deviceStates[device.id] ?? .disconnected,
          showConnectionStatus: showConnectionStatus,
          primaryAction: { primaryAction(device) },
          secondaryAction: secondaryAction.map { action in
            { action(device) }
          }
        )
      }
    }
  }
}

/// Row view for displaying individual Bluetooth device
private struct DeviceRowView: View {
  let device: Device
  let state: DeviceConnectionState
  let showConnectionStatus: Bool
  let primaryAction: () -> Void
  var secondaryAction: (() -> Void)?

  var body: some View {
    HStack {
      Text(device.name)
      Spacer()
      if showConnectionStatus {
        Button(state == .connected ? "Disconnect" : "Connect", action: primaryAction)
        Button(action: { secondaryAction?() }) {
          Image(systemName: "minus.circle")
            .foregroundColor(.red)
        }
      } else {
        Button(action: primaryAction) {
          Image(systemName: "plus.circle")
            .foregroundColor(.blue)
        }
      }
    }
  }
}

// MARK: - Preview

#Preview {
  BluetoothPeripheralSettingsView()
}
