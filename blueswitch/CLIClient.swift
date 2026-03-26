import Foundation

struct CLIClient {
    static let socketPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] + "/BlueSwitch/blueswitch.sock"
    static let prefsPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] + "/BlueSwitch/preferences.json"

    static var isAppRunning: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    static func send(_ request: SocketRequest) throws -> SocketResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError.socketFailed }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for i in 0..<min(pathBytes.count, 104) {
                bound[i] = pathBytes[i]
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else { throw CLIError.connectionFailed }

        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, data.count)
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { throw CLIError.noResponse }

        let responseData = Data(buffer[0..<bytesRead]).filter { $0 != 0x0A }
        return try JSONDecoder().decode(SocketResponse.self, from: responseData)
    }

    static func loadPreferences() throws -> AppPreferences {
        let url = URL(fileURLWithPath: prefsPath)
        guard FileManager.default.fileExists(atPath: prefsPath) else {
            return AppPreferences()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }

    /// Fuzzy match device name (case-insensitive substring)
    static func findDevice(_ query: String, in devices: [Device]) -> Device? {
        let lower = query.lowercased()
        let matches = devices.filter { $0.name.lowercased().contains(lower) || $0.type.rawValue.contains(lower) }
        if matches.count == 1 { return matches[0] }
        return nil
    }

    static func findDeviceOrExit(_ query: String, in devices: [Device]) -> Device {
        let lower = query.lowercased()
        let matches = devices.filter { $0.name.lowercased().contains(lower) || $0.type.rawValue.contains(lower) }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty {
            print("No device matching '\(query)'. Available devices:")
            for d in devices { print("  - \(d.name) (\(d.type.rawValue))") }
            Foundation.exit(1)
        }
        print("Ambiguous match for '\(query)'. Did you mean:")
        for d in matches { print("  - \(d.name) (\(d.type.rawValue))") }
        Foundation.exit(1)
    }

    enum CLIError: Error, CustomStringConvertible {
        case socketFailed
        case connectionFailed
        case noResponse
        case appNotRunning

        var description: String {
            switch self {
            case .socketFailed: return "Failed to create socket"
            case .connectionFailed: return "Could not connect to Blue Switch app. Is it running?"
            case .noResponse: return "No response from Blue Switch app"
            case .appNotRunning: return "Blue Switch app is not running. Start it first."
            }
        }
    }
}
