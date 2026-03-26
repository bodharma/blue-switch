import ArgumentParser
import Foundation

@main
struct BlueSwitchCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blueswitch",
        abstract: "Control Bluetooth device switching from the command line",
        subcommands: [
            ListCommand.self,
            SwitchCommand.self,
            ConnectCommand.self,
            DisconnectCommand.self,
            StatusCommand.self,
            BatteryCommand.self,
            ConfigCommand.self,
        ]
    )
}

// MARK: - List

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List registered devices")

    func run() throws {
        let prefs = try CLIClient.loadPreferences()
        if prefs.devices.isEmpty {
            print("No devices registered. Open Blue Switch settings to add devices.")
            return
        }
        print(String(format: "%-22s %-12s %-8s", "DEVICE", "TYPE", "SHORTCUT"))
        for device in prefs.devices {
            let shortcut = device.shortcutName ?? "—"
            print(String(format: "%-22s %-12s %-8s", device.name, device.type.rawValue, shortcut))
        }
    }
}

// MARK: - Switch

struct SwitchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "switch", abstract: "Switch a device to/from peer")

    @Flag(name: .long, help: "Switch all devices")
    var all = false

    @Argument(help: "Device name (fuzzy match)")
    var device: String?

    func run() throws {
        guard CLIClient.isAppRunning else {
            print("Blue Switch app is not running. Start it first.")
            throw ExitCode.failure
        }

        let command: String
        let deviceName: String?

        if all {
            command = "switch"
            deviceName = nil
        } else {
            guard let query = device else {
                print("Specify a device name or use --all")
                throw ExitCode.failure
            }
            let prefs = try CLIClient.loadPreferences()
            let matched = CLIClient.findDeviceOrExit(query, in: prefs.devices)
            command = "switch"
            deviceName = matched.name
        }

        let request = SocketRequest(command: command, device: deviceName ?? "--all")
        let response = try CLIClient.send(request)
        print(response.message)
        if response.status == "error" { throw ExitCode.failure }
    }
}

// MARK: - Connect

struct ConnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "connect", abstract: "Connect a device to this Mac")

    @Argument(help: "Device name (fuzzy match)")
    var device: String

    func run() throws {
        guard CLIClient.isAppRunning else {
            print("Blue Switch app is not running. Start it first.")
            throw ExitCode.failure
        }
        let prefs = try CLIClient.loadPreferences()
        let matched = CLIClient.findDeviceOrExit(device, in: prefs.devices)
        let response = try CLIClient.send(SocketRequest(command: "connect", device: matched.name))
        print(response.message)
        if response.status == "error" { throw ExitCode.failure }
    }
}

// MARK: - Disconnect

struct DisconnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disconnect", abstract: "Disconnect a device from this Mac")

    @Argument(help: "Device name (fuzzy match)")
    var device: String

    func run() throws {
        guard CLIClient.isAppRunning else {
            print("Blue Switch app is not running. Start it first.")
            throw ExitCode.failure
        }
        let prefs = try CLIClient.loadPreferences()
        let matched = CLIClient.findDeviceOrExit(device, in: prefs.devices)
        let response = try CLIClient.send(SocketRequest(command: "disconnect", device: matched.name))
        print(response.message)
        if response.status == "error" { throw ExitCode.failure }
    }
}

// MARK: - Status

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show device status summary")

    func run() throws {
        if CLIClient.isAppRunning {
            let response = try CLIClient.send(SocketRequest(command: "status"))
            if let devices = response.devices {
                print(String(format: "%-22s %-12s %-15s %-8s", "DEVICE", "TYPE", "STATUS", "BATTERY"))
                for d in devices {
                    let battery = d.battery.map { "\($0)%" } ?? "—"
                    print(String(format: "%-22s %-12s %-15s %-8s", d.name, d.type, d.status, battery))
                }
            } else {
                print(response.message)
            }
        } else {
            // Read-only from prefs
            let prefs = try CLIClient.loadPreferences()
            if prefs.devices.isEmpty {
                print("No devices registered.")
                return
            }
            print(String(format: "%-22s %-12s %-15s", "DEVICE", "TYPE", "STATUS"))
            for device in prefs.devices {
                print(String(format: "%-22s %-12s %-15s", device.name, device.type.rawValue, "(app not running)"))
            }
        }
    }
}

// MARK: - Battery

struct BatteryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "battery", abstract: "Show battery levels")

    func run() throws {
        guard CLIClient.isAppRunning else {
            print("Blue Switch app is not running. Battery info requires the app.")
            throw ExitCode.failure
        }
        let response = try CLIClient.send(SocketRequest(command: "battery"))
        if let devices = response.devices {
            print(String(format: "%-22s %-8s", "DEVICE", "BATTERY"))
            for d in devices {
                let battery = d.battery.map { "\($0)%" } ?? "—"
                print(String(format: "%-22s %-8s", d.name, battery))
            }
        } else {
            print(response.message)
        }
    }
}

// MARK: - Config

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "config", abstract: "Open settings window")

    func run() throws {
        if CLIClient.isAppRunning {
            let response = try CLIClient.send(SocketRequest(command: "config"))
            print(response.message)
        } else {
            // Launch the app
            let appPath = "/Applications/Blue Switch.app"
            if FileManager.default.fileExists(atPath: appPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [appPath]
                try process.run()
                print("Launching Blue Switch...")
            } else {
                print("Blue Switch app not found at \(appPath)")
                throw ExitCode.failure
            }
        }
    }
}
