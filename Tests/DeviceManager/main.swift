import CoreBluetooth
import Foundation
import IOBluetooth

// Run DeviceManager against fake framework modules so tests cannot pair, remove,
// connect, or disconnect any real peripheral. The production source is compiled unchanged.
extension IOBluetoothDevice {
  func toDevice() -> Device { Device(id: addressString!, name: "Test peripheral") }
}

func drainMainQueue(until predicate: () -> Bool, timeout: TimeInterval = 3) {
  let deadline = Date().addingTimeInterval(timeout)
  while !predicate() && Date() < deadline {
    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
  }
}

let manager = DeviceManager.shared
drainMainQueue(until: { manager.bluetoothPoweredOn })
var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if condition() {
    print("PASS: \(message)")
  } else {
    print("FAIL: \(message)")
    failures += 1
  }
}

func fixture(_ address: String) -> (Device, BluetoothFixture) {
  let fixture = BluetoothFixture()
  IOBluetoothDevice.devices[address] = fixture
  let device = Device(id: address, name: "Test peripheral", showInMenubar: true)
  manager.register(device)
  IOBluetoothDevicePair.startCount = 0
  return (device, fixture)
}

// Reproduce a previously paired peripheral that is unavailable after leaving home.
let (offlineDevice, offline) = fixture("00-00-00-00-00-01")
offline.openStatus = kIOReturnError
var offlineResults: [Bool] = []
manager.connect(offlineDevice) { offlineResults.append($0) }
drainMainQueue(until: { !offlineResults.isEmpty })
check(
  IOBluetoothDevicePair.startCount == 0,
  "offline reconnect and retries never start pairing (started \(IOBluetoothDevicePair.startCount))")
check(offline.openCount == 3, "offline reconnect uses the existing bond for all three attempts")
check(offlineResults == [false], "offline reconnect reports failure exactly once")
check(
  offline.paired && manager.registeredDevices.contains(offlineDevice),
  "offline reconnect preserves the bond and saved device configuration")
manager.unregister(offlineDevice)

// A known device with a lost bond must require explicit pairing in macOS settings.
let (unpairedDevice, unpaired) = fixture("00-00-00-00-00-02")
unpaired.paired = false
var unpairedResults: [Bool] = []
manager.connect(unpairedDevice) { unpairedResults.append($0) }
drainMainQueue(until: { !unpairedResults.isEmpty })
check(
  IOBluetoothDevicePair.startCount == 0 && unpaired.openCount == 0,
  "a missing bond fails without attempting automatic pairing or connection")
check(unpairedResults == [false], "a missing bond reports failure exactly once")
manager.unregister(unpairedDevice)

// A normal reconnect completes through the Objective-C callback used by IOBluetooth.
let (connectedDevice, connected) = fixture("00-00-00-00-00-03")
var connectResults: [Bool] = []
manager.connect(connectedDevice) { connectResults.append($0) }
check(
  IOBluetoothDevicePair.startCount == 0 && connected.openCount == 1,
  "paired reconnect opens a connection without pairing")
check(
  manager.responds(to: NSSelectorFromString("connectionComplete:status:")),
  "the asynchronous connection callback is visible to Objective-C")
connected.connected = true
check(
  IOBluetoothDevice(addressString: connectedDevice.id)!.completeConnection(
    status: kIOReturnSuccess),
  "IOBluetooth can invoke the reconnect callback through Objective-C")
drainMainQueue(until: { !connectResults.isEmpty })
check(
  connectResults == [true] && manager.deviceStates[connectedDevice.id] == .connected,
  "successful reconnect reports success and records the connected state")
_ = IOBluetoothDevice(addressString: connectedDevice.id)!.completeConnection(status: kIOReturnError)
_ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
check(
  connectResults == [true] && manager.deviceStates[connectedDevice.id] == .connected,
  "a duplicate callback cannot fail a completed reconnect")
manager.unregister(connectedDevice)

// A failed asynchronous connection retries with the existing bond, then succeeds.
let (retryDevice, retry) = fixture("00-00-00-00-00-04")
var retryResults: [Bool] = []
manager.connect(retryDevice) { retryResults.append($0) }
for attempt in 1...2 {
  _ = IOBluetoothDevice(addressString: retryDevice.id)!.completeConnection(status: kIOReturnError)
  drainMainQueue(until: { retry.openCount == attempt + 1 })
}
retry.connected = true
_ = IOBluetoothDevice(addressString: retryDevice.id)!.completeConnection(status: kIOReturnSuccess)
drainMainQueue(until: { !retryResults.isEmpty })
check(
  retryResults == [true] && retry.openCount == 3 && IOBluetoothDevicePair.startCount == 0,
  "asynchronous failures retry without pairing and can recover")
manager.unregister(retryDevice)

// An unavailable peer must recover locally without initiating a new pairing.
let rollbackFixture = BluetoothFixture()
rollbackFixture.connected = true
IOBluetoothDevice.devices["00-00-00-00-00-05"] = rollbackFixture
let rollbackDevice = Device(id: "00-00-00-00-00-05", name: "Rollback peripheral")
manager.register(rollbackDevice)
IOBluetoothDevicePair.startCount = 0
var rollbackResults: [Bool] = []
manager.switchToPeer(
  rollbackDevice,
  sendPeerConnect: { _, reply in reply(false) },
  completion: { rollbackResults.append($0) }
)
drainMainQueue(until: { rollbackFixture.openCount > 0 })
rollbackFixture.connected = true
_ = IOBluetoothDevice(addressString: rollbackDevice.id)!.completeConnection(
  status: kIOReturnSuccess)
drainMainQueue(until: { !rollbackResults.isEmpty })
check(
  rollbackResults == [false] && manager.deviceStates[rollbackDevice.id] == .connected,
  "an unavailable peer rolls back to the local connection")
check(
  IOBluetoothDevicePair.startCount == 0 && rollbackFixture.paired,
  "failed handoff recovery preserves the existing bond")
manager.unregister(rollbackDevice)

// Removing a device during reconnection cancels it, including delayed callbacks.
let (removedDevice, removed) = fixture("00-00-00-00-00-06")
var removedResults: [Bool] = []
manager.connect(removedDevice) { removedResults.append($0) }
manager.unregister(removedDevice)
removed.connected = true
_ = IOBluetoothDevice(addressString: removedDevice.id)!.completeConnection(status: kIOReturnSuccess)
_ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
check(
  removedResults == [false] && manager.deviceStates[removedDevice.id] == nil,
  "cancelled reconnects complete once and ignore later callbacks")

let (removedRetryDevice, removedRetry) = fixture("00-00-00-00-00-07")
removedRetry.openStatus = kIOReturnError
var removedRetryResults: [Bool] = []
manager.connect(removedRetryDevice) { removedRetryResults.append($0) }
manager.unregister(removedRetryDevice)
drainMainQueue(until: { !removedRetryResults.isEmpty })
check(
  removedRetryResults == [false] && removedRetry.openCount == 1,
  "unregistering during retry backoff prevents another connection attempt")

// Exercise the real timeout duration; a peripheral out of range must still only
// reconnect, and a callback after exhaustion must not change the final result.
let (timeoutDevice, timeoutFixture) = fixture("00-00-00-00-00-08")
var timeoutResults: [Bool] = []
manager.connect(timeoutDevice) { timeoutResults.append($0) }
timeoutFixture.openStatus = kIOReturnError
drainMainQueue(until: { !timeoutResults.isEmpty }, timeout: 23)
check(
  timeoutResults == [false] && timeoutFixture.openCount == 3,
  "an unavailable peripheral times out, retries twice, and fails once")
check(
  IOBluetoothDevicePair.startCount == 0 && timeoutFixture.paired,
  "timeout recovery preserves the existing bond without pairing")
timeoutFixture.connected = true
_ = IOBluetoothDevice(addressString: timeoutDevice.id)!.completeConnection(status: kIOReturnSuccess)
_ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
check(
  timeoutResults == [false] && manager.deviceStates[timeoutDevice.id] == .disconnected,
  "a callback after exhausted retries cannot report a second result")
manager.unregister(timeoutDevice)

if failures > 0 {
  print("\(failures) regression checks failed")
  exit(1)
}
print("All DeviceManager regression checks passed")
