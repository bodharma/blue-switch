import IOBluetooth

extension IOBluetoothDevice {
    func toDevice() -> Device {
        let name = self.name ?? "Unknown Device"
        let address = self.addressString ?? "Unknown"
        return Device(
            id: address,
            name: name,
            type: DataMigrator.detectDeviceType(macAddress: address)
        )
    }
}
