import Foundation

enum DeviceType: String, Codable, CaseIterable {
    case trackpad
    case keyboard
    case mouse
    case headphones
    case other
}

struct DeviceAction: Identifiable, Codable, Equatable {
    let id: UUID
    var type: ActionType
    var isEnabled: Bool

    init(id: UUID = UUID(), type: ActionType, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
    }

    enum ActionType: Codable, Equatable {
        case openApp(path: String)
        case openURL(url: String)
        case shortcut(name: String)
        case shellScript(path: String)
    }
}

struct Device: Identifiable, Codable, Equatable {
    let id: String  // MAC address
    var name: String
    var type: DeviceType
    var icon: String?
    var shortcutName: String?
    var onConnectActions: [DeviceAction]
    var onDisconnectActions: [DeviceAction]
    var showInMenubar: Bool

    init(
        id: String,
        name: String,
        type: DeviceType = .other,
        icon: String? = nil,
        shortcutName: String? = nil,
        onConnectActions: [DeviceAction] = [],
        onDisconnectActions: [DeviceAction] = [],
        showInMenubar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.shortcutName = shortcutName
        self.onConnectActions = onConnectActions
        self.onDisconnectActions = onDisconnectActions
        self.showInMenubar = showInMenubar
    }
}
