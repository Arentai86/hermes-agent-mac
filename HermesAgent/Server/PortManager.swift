import Darwin
import Foundation

struct PortManager {
    let defaultPort = 9119
    let searchRange = 9119...9179

    func firstAvailablePort(startingAt preferredPort: Int) -> Int? {
        if (1024...65535).contains(preferredPort), isPortAvailable(UInt16(preferredPort)) {
            return preferredPort
        }
        for port in searchRange where isPortAvailable(UInt16(port)) {
            return port
        }
        return nil
    }

    func isPortAvailable(_ port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
