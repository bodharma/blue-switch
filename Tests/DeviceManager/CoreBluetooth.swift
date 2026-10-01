@_exported import Foundation

public enum CBManagerState {
  case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public protocol CBCentralManagerDelegate: AnyObject {
  func centralManagerDidUpdateState(_ central: CBCentralManager)
}

public final class CBCentralManager {
  public var state: CBManagerState = .poweredOn

  public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {
    DispatchQueue.main.async { delegate?.centralManagerDidUpdateState(self) }
  }
}
