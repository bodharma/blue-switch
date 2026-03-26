import Combine
import Foundation
import Network

/// Facade for peer-to-peer network operations, coordinating device discovery and per-device Bluetooth switching commands.
final class PeerNetwork: ObservableObject {
  private let networkStore = NetworkDeviceStore.shared
  private let connectionManager = ConnectionManager()
  private var cancellables = Set<AnyCancellable>()

  /// The registered peer devices managed by this node.
  @Published private(set) var peerDevices: [NetworkDevice] = []

  /// Discovered peers on the local network, excluding this machine.
  @Published private(set) var discoveredPeers: [NetworkDevice] = []

  init() {
    networkStore.$networkDevices
      .assign(to: &$peerDevices)
    networkStore.$discoveredNetworkDevices
      .map { discovered in
        discovered.filter { $0.name != Host.current().localizedName }
      }
      .assign(to: &$discoveredPeers)
  }

  /// The first registered peer device, used as the active switching target.
  var activePeer: NetworkDevice? {
    networkStore.networkDevices.first
  }

  /// The display name of the active peer, or `nil` if no peer is registered.
  var activePeerName: String? {
    activePeer?.name
  }

  /// Sends a connect command for the given device to the active peer after a health check.
  /// - Parameters:
  ///   - device: The Bluetooth device to connect on the remote peer.
  ///   - completion: Called with `true` on success, `false` on any failure.
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

  /// Sends a disconnect command for the given device to the active peer.
  /// - Parameters:
  ///   - device: The Bluetooth device to disconnect on the remote peer.
  ///   - completion: Called with `true` on success, `false` on any failure.
  func disconnectDeviceOnPeer(_ device: Device, completion: @escaping (Bool) -> Void) {
    guard let peer = activePeer else {
      completion(false)
      return
    }
    executeDeviceCommand(.disconnectDevice, deviceMAC: device.id, on: peer, completion: completion)
  }

  /// Registers a discovered peer as a known network device.
  /// - Parameter device: The network device to register.
  func registerPeer(_ device: NetworkDevice) {
    networkStore.registerNetworkDevice(device: device)
  }

  /// Removes a registered peer from the known device list.
  /// - Parameter device: The network device to remove.
  func removePeer(_ device: NetworkDevice) {
    networkStore.removeNetworkDevice(device: device)
  }

  // MARK: - Private

  private func executeDeviceCommand(
    _ command: DeviceCommand,
    deviceMAC: String,
    on peer: NetworkDevice,
    completion: @escaping (Bool) -> Void
  ) {
    var completed = false
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
        if !completed {
          completed = true
          completion(false)
        }
      default:
        break
      }
    }

    connection.receiveMessage { data, _, _, error in
      defer { connection.cancel() }
      guard !completed else { return }
      completed = true
      guard error == nil,
        let data,
        let response = String(data: data, encoding: .utf8),
        DeviceCommand(rawValue: response) == .operationSuccess
      else {
        completion(false)
        return
      }
      completion(true)
    }

    connection.start(queue: .global())

    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
      if !completed {
        completed = true
        connection.cancel()
        completion(false)
      }
    }
  }
}
