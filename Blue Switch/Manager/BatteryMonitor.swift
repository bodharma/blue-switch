import Foundation
import IOBluetooth

final class BatteryMonitor: ObservableObject {
    @Published private(set) var batteryLevels: [String: Int?] = [:]

    private var timer: Timer?
    private var pollingInterval: TimeInterval

    init(pollingInterval: TimeInterval = 60) {
        self.pollingInterval = pollingInterval
    }

    func startMonitoring(devices: [Device]) {
        pollBatteryLevels(devices: devices)
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollBatteryLevels(devices: devices)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func updatePollingInterval(_ interval: TimeInterval, devices: [Device]) {
        pollingInterval = interval
        if timer != nil {
            stopMonitoring()
            startMonitoring(devices: devices)
        }
    }

    private func pollBatteryLevels(devices: [Device]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var levels: [String: Int?] = [:]

            for device in devices {
                guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
                    levels[device.id] = nil
                    continue
                }

                if btDevice.isConnected() {
                    let battery = self?.readBatteryLevel(btDevice)
                    levels[device.id] = battery
                } else {
                    levels[device.id] = nil
                }
            }

            DispatchQueue.main.async {
                self?.batteryLevels = levels
            }
        }
    }

    private func readBatteryLevel(_ device: IOBluetoothDevice) -> Int? {
        let selector = NSSelectorFromString("batteryPercent")
        guard device.responds(to: selector) else {
            Log.bluetooth.debug("Device \(device.name ?? "unknown") does not report battery")
            return nil
        }
        let result = device.perform(selector)
        let level = Int(bitPattern: result?.toOpaque())
        guard level >= 0 && level <= 100 else { return nil }
        return level
    }
}
