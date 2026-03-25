import os

enum Log {
    static let bluetooth = Logger(subsystem: "com.blueswitch", category: "bluetooth")
    static let network = Logger(subsystem: "com.blueswitch", category: "network")
    static let actions = Logger(subsystem: "com.blueswitch", category: "actions")
    static let audio = Logger(subsystem: "com.blueswitch", category: "audio")
    static let ipc = Logger(subsystem: "com.blueswitch", category: "ipc")
    static let app = Logger(subsystem: "com.blueswitch", category: "app")
}
