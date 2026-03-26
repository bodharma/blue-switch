// KeyboardShortcuts not yet linked — stub implementation
final class ShortcutManager {
    private var onSwitchDevice: ((Device) -> Void)?
    private var onSwitchAll: (() -> Void)?

    init(onSwitchDevice: @escaping (Device) -> Void, onSwitchAll: @escaping () -> Void) {
        self.onSwitchDevice = onSwitchDevice
        self.onSwitchAll = onSwitchAll
    }

    func registerShortcuts(for devices: [Device], switchAllName: String?) {
        // TODO: Wire up KeyboardShortcuts package once linked
        Log.app.info("ShortcutManager: shortcuts registration stubbed (KeyboardShortcuts not yet linked)")
    }

    func unregisterAll() {
        Log.app.info("Unregistered all shortcuts")
    }
}
