import Foundation

struct AppPreferences: Codable, Equatable {
    var devices: [Device]
    var compactMode: Bool
    var launchAtLogin: Bool
    var switchAllShortcutName: String?
    var batteryPollingInterval: Int
    var showBatteryInMenubar: Bool
    var audioAutoSwitch: Bool

    init(
        devices: [Device] = [],
        compactMode: Bool = true,
        launchAtLogin: Bool = true,
        switchAllShortcutName: String? = nil,
        batteryPollingInterval: Int = 60,
        showBatteryInMenubar: Bool = true,
        audioAutoSwitch: Bool = true
    ) {
        self.devices = devices
        self.compactMode = compactMode
        self.launchAtLogin = launchAtLogin
        self.switchAllShortcutName = switchAllShortcutName
        self.batteryPollingInterval = batteryPollingInterval
        self.showBatteryInMenubar = showBatteryInMenubar
        self.audioAutoSwitch = audioAutoSwitch
    }

    static let defaultURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlueSwitch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("preferences.json")
    }()

    func save(to url: URL = AppPreferences.defaultURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = AppPreferences.defaultURL) throws -> AppPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppPreferences()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }
}
