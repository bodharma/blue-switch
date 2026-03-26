import Foundation
import IOBluetooth
import Network
import os

/// Protocol defining the interface for managing network connections
protocol NetworkConnectionManaging {
  /// Connects to a specified network device with a message
  /// - Parameters:
  ///   - device: The network device to connect to
  ///   - message: The message to send after connection
  func connectToDevice(_ device: NetworkDevice, message: String)

  /// Sends a message through an existing connection
  /// - Parameters:
  ///   - message: The message to send
  ///   - connection: The connection to send through
  func send(message: String, to connection: NWConnection)

  /// Starts receiving data on the specified connection
  /// - Parameter connection: The connection to receive from
  func receive(on connection: NWConnection)
}

enum ConnectionError: Error {
  case sendFailed(Error)
  case receiveFailed(Error)
  case connectionFailed(Error)
}

/// Manages network connections and message handling
final class ConnectionManager: NetworkConnectionManaging {
  // MARK: - Constants

  private let queue = DispatchQueue(label: "com.blueswitch.connection", qos: .userInitiated)
  private let messageEncoding: String.Encoding = .utf8

  // MARK: - NetworkConnectionManaging Implementation

  func connectToDevice(_ device: NetworkDevice, message: String) {
    guard let port = NWEndpoint.Port(rawValue: UInt16(device.port)) else {
      Log.network.error("Invalid port number: \(device.port)")
      return
    }

    let connection = NWConnection(
      host: NWEndpoint.Host(device.host),
      port: port,
      using: .tcp
    )

    setupConnectionHandler(for: connection, device: device, message: message)
    connection.start(queue: queue)
  }

  func send(message: String, to connection: NWConnection) {
    guard let data = message.data(using: messageEncoding) else {
      Log.network.error("Failed to encode message")
      return
    }

    connection.send(
      content: data,
      completion: .contentProcessed { error in
        if let error = error {
          self.handleSendError(error)
        } else {
          Log.network.debug("Message sent: \(message)")
        }
      })
  }

  func receive(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
      data, _, isComplete, error in
      self.handleReceivedData(
        data: data, error: error, isComplete: isComplete, connection: connection)
    }
  }

  func sendNotification(to device: NetworkDevice, title: String, message: String) {
    Log.network.info("Attempting to send notification to device: \(device.name)")
    let connection = NWConnection(
      host: NWEndpoint.Host(device.host),
      port: NWEndpoint.Port(integerLiteral: UInt16(device.port)),
      using: .tcp
    )

    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        Log.network.debug("Connection ready, sending notification...")
        self.send(message: DeviceCommand.notification.rawValue, to: connection)
        self.send(message: "\(title)|\(message)", to: connection)
        Log.network.info("Notification content sent to \(device.name)")
      case .failed(let error):
        Log.network.error("Failed to send notification to \(device.name): \(error)")
      case .cancelled:
        Log.network.info("Notification connection to \(device.name) was cancelled")
      default:
        break
      }
    }

    connection.start(queue: queue)
  }

  // MARK: - Private Setup Methods

  /// Sets up the connection handler for a given device
  private func setupConnectionHandler(
    for connection: NWConnection, device: NetworkDevice, message: String
  ) {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        Log.network.info("Connected to \(device.name)")
        self.send(message: message, to: connection)
        self.receive(on: connection)
      case .failed(let error):
        self.handleConnectionError(error, deviceName: device.name)
      case .cancelled:
        Log.network.info("Connection to \(device.name) was cancelled")
      default:
        break
      }
    }
  }

  // MARK: - Private Data Handling Methods

  private func handleReceivedData(
    data: Data?, error: Error?, isComplete: Bool, connection: NWConnection
  ) {
    if let error = error {
      handleReceiveError(error)
      connection.cancel()
      return
    }

    if let data = data, !data.isEmpty {
      processReceivedData(data, from: connection)
    }

    if !isComplete {
      receive(on: connection)
    }
  }

  private func processReceivedData(_ data: Data, from connection: NWConnection) {
    if let message = String(data: data, encoding: messageEncoding) {
      if let command = DeviceCommand(rawValue: message) {
        handleCommand(command, connection: connection)
      } else if let lastCommand = lastReceivedCommand {
        handleCommandData(message, for: lastCommand, connection: connection)
      }
    }
  }

  private var lastReceivedCommand: DeviceCommand?

  private func handleCommand(_ command: DeviceCommand, connection: NWConnection) {
    lastReceivedCommand = command
    switch command {
    case .notification:
      // Wait for the next message which will contain notification data
      break
    case .connectAll:
      // TODO: Re-implement via DeviceManager
      send(message: DeviceCommand.operationFailed.rawValue, to: connection)

    case .unregisterAll:
      // TODO: Re-implement via DeviceManager
      send(message: DeviceCommand.operationFailed.rawValue, to: connection)

    case .syncPeripherals:
      // Wait for the next message which will contain peripherals data
      break

    case .connectDevice:
      // Wait for next message containing MAC address
      break

    case .disconnectDevice:
      // Wait for next message containing MAC address
      break

    default:
      Log.network.warning("Unsupported command")
      // Send error response
      send(message: DeviceCommand.operationFailed.rawValue, to: connection)
    }
  }

  private func handleCommandData(
    _ message: String, for command: DeviceCommand, connection: NWConnection
  ) {
    switch command {
    case .notification:
      let components = message.split(separator: "|")
      if components.count == 2 {
        Log.network.info("Received notification from remote device")
        NotificationManager.showNotification(
          title: String(components[0]),
          body: String(components[1])
        )
        Log.network.info("Notification displayed successfully")
      } else {
        Log.network.error("Invalid notification format received")
      }
    case .syncPeripherals:
      // TODO: Re-implement via DeviceManager using Device type
      Log.network.warning("syncPeripherals not yet re-implemented")
      send(message: DeviceCommand.operationFailed.rawValue, to: connection)

    case .connectDevice:
      // message is the MAC address of the device to connect
      let macAddress = message.trimmingCharacters(in: .whitespacesAndNewlines)
      Log.network.info("Received CONNECT_DEVICE for \(macAddress)")
      if let device = DeviceManager.shared.registeredDevices.first(where: { $0.id == macAddress }) {
        DeviceManager.shared.connect(device) { success in
          if success {
            Log.network.info("Connected \(device.name) via peer command")
          } else {
            Log.network.error("Failed to connect \(device.name) via peer command")
          }
        }
        send(message: DeviceCommand.operationSuccess.rawValue, to: connection)
      } else {
        Log.network.error("Device not found for MAC: \(macAddress)")
        send(message: DeviceCommand.operationFailed.rawValue, to: connection)
      }

    case .disconnectDevice:
      // message is the MAC address of the device to disconnect
      // Must use "remove" to prevent macOS from auto-reconnecting HID devices.
      // The requesting Mac will re-pair the device from scratch.
      let macAddress = message.trimmingCharacters(in: .whitespacesAndNewlines)
      Log.network.info("Received DISCONNECT_DEVICE for \(macAddress)")
      if let btDevice = IOBluetoothDevice(addressString: macAddress) {
        // Remove device to prevent auto-reconnect
        if btDevice.responds(to: Selector(("remove"))) {
          btDevice.perform(Selector(("remove")))
          Log.network.info("Removed (unpaired) device \(macAddress) to prevent auto-reconnect")
        }
        if btDevice.isConnected() {
          btDevice.closeConnection()
        }
        send(message: DeviceCommand.operationSuccess.rawValue, to: connection)
      } else {
        Log.network.info("Device \(macAddress) not found (may already be removed)")
        send(message: DeviceCommand.operationSuccess.rawValue, to: connection)
      }

    default:
      break
    }
    lastReceivedCommand = nil
  }

  // MARK: - Error Handling Methods

  private func handleConnectionError(_ error: Error, deviceName: String) {
    Log.network.error("Failed to connect to \(deviceName): \(error)")
    // Update device information
    NetworkDeviceStore.shared.discoveredNetworkDevices.forEach { device in
      if device.name == deviceName {
        NetworkDeviceStore.shared.updateNetworkDevice(device)
        Log.network.info("Updated information for \(deviceName)")
      }
    }
  }

  private func handleSendError(_ error: Error) {
    Log.network.error("Send error: \(error)")
  }

  private func handleReceiveError(_ error: Error) {
    Log.network.error("Receive error: \(error)")
  }
}
