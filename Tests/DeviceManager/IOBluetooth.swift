@_exported import Foundation
@_exported import IOKit

public final class IOBluetoothUserNotification: NSObject {
  public override init() { super.init() }
  public func unregister() {}
}

public final class BluetoothFixture {
  public var connected = false
  public var paired = true
  public var openStatus = kIOReturnSuccess
  public var openCount = 0
  public var connectionTarget: AnyObject?
  public init() {}
}

public final class IOBluetoothDevice: NSObject {
  public static var devices: [String: BluetoothFixture] = [:]
  public let addressString: String?
  private let fixture: BluetoothFixture

  public init?(addressString: String) {
    guard let fixture = Self.devices[addressString] else { return nil }
    self.addressString = addressString
    self.fixture = fixture
  }

  public func isConnected() -> Bool { fixture.connected }
  public func isPaired() -> Bool { fixture.paired }
  public func register(forDisconnectNotification observer: AnyObject, selector: Selector)
    -> IOBluetoothUserNotification?
  { IOBluetoothUserNotification() }
  public func openConnection() -> IOReturn {
    fixture.openCount += 1
    return fixture.openStatus
  }
  public func openConnection(
    _ target: AnyObject, withPageTimeout: UInt16,
    authenticationRequired: Bool
  ) -> IOReturn {
    fixture.openCount += 1
    fixture.connectionTarget = target
    return fixture.openStatus
  }
  public func completeConnection(status: IOReturn) -> Bool {
    let selector = NSSelectorFromString("connectionComplete:status:")
    guard let target = fixture.connectionTarget as? NSObject,
      target.responds(to: selector)
    else { return false }
    typealias Callback = @convention(c) (AnyObject, Selector, AnyObject, IOReturn) -> Void
    let callback = unsafeBitCast(target.method(for: selector), to: Callback.self)
    callback(target, selector, self, status)
    return true
  }
  public func closeConnection() -> IOReturn {
    fixture.connected = false
    return kIOReturnSuccess
  }
  public static func pairedDevices() -> [Any]? {
    devices.keys.compactMap { IOBluetoothDevice(addressString: $0) }
  }
}

public protocol IOBluetoothDevicePairDelegate: AnyObject {
  func devicePairingFinished(_ sender: Any?, error: IOReturn)
}

public final class IOBluetoothDevicePair {
  public static var startCount = 0
  public weak var delegate: IOBluetoothDevicePairDelegate?
  private let target: IOBluetoothDevice
  public init?(device: IOBluetoothDevice) { target = device }
  public func start() -> IOReturn {
    Self.startCount += 1
    return kIOReturnError
  }
  public func device() -> IOBluetoothDevice? { target }
}
