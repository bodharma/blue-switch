import AppKit
import Foundation

enum ActionRunner {
    enum Event: String {
        case connect
        case disconnect
    }

    struct Context {
        let deviceName: String
        let deviceMAC: String
        let deviceType: DeviceType
        let event: Event
        let peerName: String?
    }

    static func runAll(_ actions: [DeviceAction], context: Context) async {
        for action in actions where action.isEnabled {
            await run(action, context: context)
        }
    }

    static func run(_ action: DeviceAction, context: Context) async {
        guard action.isEnabled else { return }

        switch action.type {
        case .openApp(let path):
            openApp(at: path)
        case .openURL(let urlString):
            openURL(urlString)
        case .shortcut(let name):
            await runShortcut(name)
        case .shellScript(path: let path):
            await runScript(at: path, context: context)
        }
    }

    private static func openApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error {
                Log.actions.error("Failed to open app at \(path): \(error.localizedDescription)")
            } else {
                Log.actions.info("Opened app: \(path)")
            }
        }
    }

    private static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            Log.actions.error("Invalid URL: \(urlString)")
            return
        }
        NSWorkspace.shared.open(url)
        Log.actions.info("Opened URL: \(urlString)")
    }

    private static func runShortcut(_ name: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        Log.actions.info("Ran shortcut: \(name)")
                    } else {
                        Log.actions.error("Shortcut '\(name)' exited with status \(process.terminationStatus)")
                    }
                } catch {
                    Log.actions.error("Failed to run shortcut '\(name)': \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private static func runScript(at path: String, context: Context) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [path]
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

                var env = ProcessInfo.processInfo.environment
                env["BLUESWITCH_DEVICE_NAME"] = context.deviceName
                env["BLUESWITCH_DEVICE_MAC"] = context.deviceMAC
                env["BLUESWITCH_DEVICE_TYPE"] = context.deviceType.rawValue
                env["BLUESWITCH_EVENT"] = context.event.rawValue
                if let peer = context.peerName {
                    env["BLUESWITCH_PEER_NAME"] = peer
                }
                process.environment = env

                do {
                    try process.run()

                    let deadline = DispatchTime.now() + .seconds(10)
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            process.terminate()
                            Log.actions.warning("Script at \(path) timed out after 10s")
                        }
                    }

                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        Log.actions.info("Script completed: \(path)")
                    } else {
                        Log.actions.error("Script '\(path)' exited with status \(process.terminationStatus)")
                    }
                } catch {
                    Log.actions.error("Failed to run script '\(path)': \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
}
