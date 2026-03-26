import Foundation

final class AppCommunicator {
    static let socketPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlueSwitch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("blueswitch.sock").path
    }()

    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var onCommand: ((SocketRequest) -> SocketResponse)?

    func start(onCommand: @escaping (SocketRequest) -> SocketResponse) {
        self.onCommand = onCommand

        unlink(AppCommunicator.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.ipc.error("Failed to create socket")
            return
        }
        listenFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = AppCommunicator.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for i in 0..<min(pathBytes.count, 104) {
                bound[i] = pathBytes[i]
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            Log.ipc.error("Failed to bind socket: errno \(errno)")
            close(fd)
            return
        }

        listen(fd, 5)
        Log.ipc.info("Listening on \(AppCommunicator.socketPath)")

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.listenFD, fd >= 0 {
                close(fd)
            }
        }
        source.resume()
        listenSource = source
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
        unlink(AppCommunicator.socketPath)
        listenFD = -1
        Log.ipc.info("Socket server stopped")
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }

        DispatchQueue.global().async { [weak self] in
            self?.handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])
        let trimmed = data.filter { $0 != 0x0A }

        guard let request = try? JSONDecoder().decode(SocketRequest.self, from: trimmed) else {
            let errorResponse = SocketResponse.error(message: "Invalid request", code: "PARSE_ERROR")
            sendResponse(errorResponse, to: fd)
            return
        }

        let response = onCommand?(request) ?? SocketResponse.error(message: "No handler", code: "INTERNAL_ERROR")
        sendResponse(response, to: fd)
    }

    private func sendResponse(_ response: SocketResponse, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, data.count)
        }
    }
}
