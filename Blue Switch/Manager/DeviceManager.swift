import Combine
import CoreBluetooth
import IOBluetooth
import os

// MARK: - Device State

/// Represents the connection state of a single Bluetooth device.
enum DeviceConnectionState: String, CustomStringConvertible {
    case disconnected
    case connecting
    case connected
    case disconnecting

    var description: String { rawValue }
}

// MARK: - DeviceManager

/// Manages per-device Bluetooth state, connection, disconnection, and peer switching.
///
/// Replaces the legacy `BluetoothPeripheralStore` and `BluetoothManager` with a unified
/// manager that tracks individual device states through a well-defined state machine:
/// `.disconnected` -> `.connecting` -> `.connected` -> `.disconnecting` -> `.disconnected`
final class DeviceManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = DeviceManager()

    // MARK: - Published Properties

    @Published private(set) var registeredDevices: [Device] = []
    @Published private(set) var deviceStates: [String: DeviceConnectionState] = [:]
    @Published private(set) var bluetoothPoweredOn: Bool = false

    // MARK: - Private Properties

    private var centralManager: CBCentralManager?
    private var pendingPairCompletions: [String: (Bool) -> Void] = [:]
    private var connectTimeouts: [String: DispatchWorkItem] = [:]
    private var retryCount: [String: Int] = [:]

    private let queue = DispatchQueue(label: "com.blueswitch.devicemanager", qos: .userInitiated)
    private static let connectTimeoutSeconds: TimeInterval = 10
    private static let disconnectTimeoutSeconds: TimeInterval = 5
    private static let maxRetries = 1

    // MARK: - Initialization

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Registration

    /// Registers a device for management. Sets initial state to `.disconnected`.
    func register(_ device: Device) {
        guard !registeredDevices.contains(where: { $0.id == device.id }) else {
            Log.bluetooth.warning("Device already registered: \(device.name)")
            return
        }
        registeredDevices.append(device)
        deviceStates[device.id] = .disconnected
        Log.bluetooth.info("Registered device: \(device.name) [\(device.id)]")
    }

    /// Unregisters a device and cancels any in-flight operations.
    func unregister(_ device: Device) {
        cancelTimeout(for: device.id)
        registeredDevices.removeAll { $0.id == device.id }
        deviceStates.removeValue(forKey: device.id)
        retryCount.removeValue(forKey: device.id)
        Log.bluetooth.info("Unregistered device: \(device.name) [\(device.id)]")
    }

    // MARK: - Connect

    /// Connects to a Bluetooth device using IOBluetooth pairing and connection.
    ///
    /// The flow is: pair (if needed) -> openConnection. A 10-second timeout is applied,
    /// with one automatic retry on failure.
    func connect(_ device: Device, completion: @escaping (Bool) -> Void) {
        guard bluetoothPoweredOn else {
            Log.bluetooth.error("Cannot connect \(device.name): Bluetooth is off")
            completion(false)
            return
        }

        guard let ioDevice = IOBluetoothDevice(addressString: device.id) else {
            Log.bluetooth.error("Cannot find IOBluetoothDevice for \(device.id)")
            completion(false)
            return
        }

        let currentState = deviceStates[device.id] ?? .disconnected
        guard currentState == .disconnected else {
            Log.bluetooth.warning("Cannot connect \(device.name): state is \(currentState)")
            completion(false)
            return
        }

        deviceStates[device.id] = .connecting
        Log.bluetooth.info("Connecting to \(device.name)...")

        // Set up timeout
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Log.bluetooth.warning("Connect timeout for \(device.name)")
            self.handleConnectFailure(device: device, completion: completion)
        }
        connectTimeouts[device.id] = timeout
        queue.asyncAfter(deadline: .now() + Self.connectTimeoutSeconds, execute: timeout)

        // Pair
        let pair = IOBluetoothDevicePair(device: ioDevice)
        pair?.delegate = self
        pendingPairCompletions[device.id] = { [weak self] pairSuccess in
            guard let self = self else { return }
            self.cancelTimeout(for: device.id)

            guard pairSuccess else {
                self.handleConnectFailure(device: device, completion: completion)
                return
            }

            // Open connection
            let status = ioDevice.openConnection()
            if status == kIOReturnSuccess {
                DispatchQueue.main.async {
                    self.deviceStates[device.id] = .connected
                    self.retryCount[device.id] = 0
                    Log.bluetooth.info("Connected to \(device.name)")
                    completion(true)
                }
            } else {
                Log.bluetooth.error("openConnection failed for \(device.name): \(status)")
                self.handleConnectFailure(device: device, completion: completion)
            }
        }

        let pairResult = pair?.start() ?? kIOReturnError
        if pairResult != kIOReturnSuccess {
            // Pairing start failed -- device may already be paired, try direct connect
            Log.bluetooth.info("Pair start returned \(pairResult), attempting direct connection for \(device.name)")
            cancelTimeout(for: device.id)
            pendingPairCompletions.removeValue(forKey: device.id)

            let status = ioDevice.openConnection()
            if status == kIOReturnSuccess {
                DispatchQueue.main.async {
                    self.deviceStates[device.id] = .connected
                    self.retryCount[device.id] = 0
                    Log.bluetooth.info("Connected to \(device.name) (direct)")
                    completion(true)
                }
            } else {
                Log.bluetooth.error("Direct openConnection failed for \(device.name): \(status)")
                handleConnectFailure(device: device, completion: completion)
            }
        }
    }

    // MARK: - Disconnect

    /// Disconnects a Bluetooth device with a 5-second timeout.
    func disconnect(_ device: Device, completion: @escaping (Bool) -> Void) {
        guard let ioDevice = IOBluetoothDevice(addressString: device.id) else {
            Log.bluetooth.error("Cannot find IOBluetoothDevice for \(device.id)")
            completion(false)
            return
        }

        let currentState = deviceStates[device.id] ?? .disconnected
        guard currentState == .connected else {
            Log.bluetooth.warning("Cannot disconnect \(device.name): state is \(currentState)")
            completion(false)
            return
        }

        deviceStates[device.id] = .disconnecting
        Log.bluetooth.info("Disconnecting \(device.name)...")

        var completed = false
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, !completed else { return }
            completed = true
            Log.bluetooth.warning("Disconnect timeout for \(device.name)")
            DispatchQueue.main.async {
                self.deviceStates[device.id] = .disconnected
                completion(false)
            }
        }
        queue.asyncAfter(deadline: .now() + Self.disconnectTimeoutSeconds, execute: timeoutItem)

        let status = ioDevice.closeConnection()
        timeoutItem.cancel()
        if !completed {
            completed = true
            if status == kIOReturnSuccess {
                DispatchQueue.main.async {
                    self.deviceStates[device.id] = .disconnected
                    Log.bluetooth.info("Disconnected \(device.name)")
                    completion(true)
                }
            } else {
                Log.bluetooth.error("closeConnection failed for \(device.name): \(status)")
                DispatchQueue.main.async {
                    self.deviceStates[device.id] = .disconnected
                    completion(false)
                }
            }
        }
    }

    // MARK: - Switch to Peer

    /// Switches a device to a peer: disconnects locally, tells the peer to connect,
    /// and reconnects locally if the peer fails.
    ///
    /// - Parameters:
    ///   - device: The device to switch.
    ///   - sendPeerConnect: Closure that asks the peer to connect the device.
    ///     The closure receives the device and a completion handler `(Bool) -> Void`.
    ///   - completion: Called with `true` if the peer successfully connected, `false` otherwise.
    func switchToPeer(
        _ device: Device,
        sendPeerConnect: @escaping (Device, @escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        Log.bluetooth.info("Switching \(device.name) to peer...")

        disconnect(device) { [weak self] disconnectSuccess in
            guard let self = self else {
                completion(false)
                return
            }

            guard disconnectSuccess else {
                Log.bluetooth.error("Failed to disconnect \(device.name) locally, aborting switch")
                completion(false)
                return
            }

            // Ask the peer to connect this device
            sendPeerConnect(device) { [weak self] peerSuccess in
                guard let self = self else {
                    completion(false)
                    return
                }

                if peerSuccess {
                    Log.bluetooth.info("Peer connected \(device.name) successfully")
                    completion(true)
                } else {
                    // Recovery: reconnect locally
                    Log.bluetooth.warning("Peer failed to connect \(device.name), reconnecting locally")
                    self.connect(device) { reconnectSuccess in
                        if reconnectSuccess {
                            Log.bluetooth.info("Recovered: reconnected \(device.name) locally")
                        } else {
                            Log.bluetooth.error("Recovery failed: could not reconnect \(device.name)")
                        }
                        completion(false)
                    }
                }
            }
        }
    }

    // MARK: - Fetch Paired Devices

    /// Returns all currently paired Bluetooth devices as `[Device]`.
    func fetchPairedDevices() -> [Device] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            Log.bluetooth.info("No paired devices found")
            return []
        }
        return paired.map { $0.toDevice() }
    }

    // MARK: - Refresh States

    /// Syncs `deviceStates` with actual IOBluetooth connection state for all registered devices.
    func refreshStates() {
        for device in registeredDevices {
            guard let ioDevice = IOBluetoothDevice(addressString: device.id) else {
                deviceStates[device.id] = .disconnected
                continue
            }
            let isConnected = ioDevice.isConnected()
            let currentState = deviceStates[device.id] ?? .disconnected

            // Only update if not in a transitional state
            if currentState != .connecting && currentState != .disconnecting {
                let newState: DeviceConnectionState = isConnected ? .connected : .disconnected
                if newState != currentState {
                    deviceStates[device.id] = newState
                    Log.bluetooth.info("Refreshed \(device.name): \(newState)")
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func handleConnectFailure(device: Device, completion: @escaping (Bool) -> Void) {
        let currentRetry = retryCount[device.id] ?? 0
        if currentRetry < Self.maxRetries {
            retryCount[device.id] = currentRetry + 1
            Log.bluetooth.info("Retrying connect for \(device.name) (attempt \(currentRetry + 1))")
            DispatchQueue.main.async {
                self.deviceStates[device.id] = .disconnected
            }
            connect(device, completion: completion)
        } else {
            Log.bluetooth.error("Connect failed for \(device.name) after \(Self.maxRetries) retries")
            retryCount[device.id] = 0
            DispatchQueue.main.async {
                self.deviceStates[device.id] = .disconnected
                completion(false)
            }
        }
    }

    private func cancelTimeout(for deviceId: String) {
        connectTimeouts[deviceId]?.cancel()
        connectTimeouts.removeValue(forKey: deviceId)
    }
}

// MARK: - CBCentralManagerDelegate

extension DeviceManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let powered = central.state == .poweredOn
        DispatchQueue.main.async {
            self.bluetoothPoweredOn = powered
        }

        switch central.state {
        case .poweredOn:
            Log.bluetooth.info("Bluetooth is powered on")
        case .poweredOff:
            Log.bluetooth.warning("Bluetooth is powered off")
        case .unauthorized:
            Log.bluetooth.error("Bluetooth is not authorized")
        case .unsupported:
            Log.bluetooth.error("Bluetooth is not supported")
        case .resetting:
            Log.bluetooth.warning("Bluetooth is resetting")
        case .unknown:
            Log.bluetooth.info("Bluetooth state is unknown")
        @unknown default:
            Log.bluetooth.warning("Unexpected Bluetooth state")
        }
    }
}

// MARK: - IOBluetoothDevicePairDelegate

extension DeviceManager: IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any?, error: IOReturn) {
        guard let pair = sender as? IOBluetoothDevicePair,
              let address = pair.device()?.addressString else {
            return
        }

        let success = error == kIOReturnSuccess
        if success {
            Log.bluetooth.info("Pairing succeeded for \(address)")
        } else {
            Log.bluetooth.error("Pairing failed for \(address): \(error)")
        }

        if let completion = pendingPairCompletions.removeValue(forKey: address) {
            completion(success)
        }
    }
}
