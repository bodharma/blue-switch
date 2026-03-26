import Foundation

struct SocketRequest: Codable {
    let command: String
    var device: String?
    var version: Int = 1
}

struct SocketResponse: Codable {
    let status: String
    let message: String
    var code: String?
    var version: Int = 1
    var devices: [SocketDeviceInfo]?

    static func ok(message: String) -> SocketResponse {
        SocketResponse(status: "ok", message: message)
    }

    static func error(message: String, code: String) -> SocketResponse {
        SocketResponse(status: "error", message: message, code: code)
    }
}

struct SocketDeviceInfo: Codable {
    let id: String
    let name: String
    let type: String
    let status: String
    let battery: Int?
}
