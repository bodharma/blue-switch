import Foundation
import IOBluetooth

struct DataMigrator {
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        guard let peripheralsData = defaults.data(forKey: "peripherals") else {
            Log.app.info("No legacy data to migrate")
            return
        }

        if FileManager.default.fileExists(atPath: AppPreferences.defaultURL.path) {
            Log.app.info("Preferences already exist, skipping migration")
            return
        }

        do {
            let oldPeripherals = try JSONDecoder().decode([LegacyPeripheral].self, from: peripheralsData)

            let devices = oldPeripherals.map { peripheral in
                Device(
                    id: peripheral.id,
                    name: peripheral.name,
                    type: detectDeviceType(macAddress: peripheral.id)
                )
            }

            let prefs = AppPreferences(devices: devices)
            try prefs.save()

            // Backup old keys
            defaults.set(peripheralsData, forKey: "_backup_peripherals")
            if let networkData = defaults.data(forKey: "networkDevices") {
                defaults.set(networkData, forKey: "_backup_networkDevices")
            }

            // Remove old keys
            defaults.removeObject(forKey: "peripherals")
            defaults.removeObject(forKey: "networkDevices")

            Log.app.info("Migrated \(devices.count) devices successfully")
        } catch {
            Log.app.error("Migration failed: \(error.localizedDescription)")
        }
    }

    static func detectDeviceType(macAddress: String) -> DeviceType {
        guard let device = IOBluetoothDevice(addressString: macAddress) else {
            return .other
        }
        let minorClass = device.deviceClassMinor
        let majorClass = device.deviceClassMajor

        // Major class 0x05 = Peripheral
        if majorClass == 0x05 {
            switch minorClass & 0xC0 {
            case 0x40: return .keyboard
            case 0x80: return .mouse
            default: break
            }
            if device.name?.lowercased().contains("trackpad") == true {
                return .trackpad
            }
            if device.name?.lowercased().contains("keyboard") == true {
                return .keyboard
            }
            if device.name?.lowercased().contains("mouse") == true {
                return .mouse
            }
        }

        // Major class 0x04 = Audio/Video
        if majorClass == 0x04 {
            return .headphones
        }

        return .other
    }
}

private struct LegacyPeripheral: Codable {
    let id: String
    let name: String
}
