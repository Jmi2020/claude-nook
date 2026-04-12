//
//  NetworkInterfaceResolver.swift
//  ClaudeNook
//
//  Enumerates all network interfaces and categorizes them for smart IP selection.
//  Used by QR code generation and Bluetooth pairing to prefer Tailscale over LAN.
//

import Foundation

/// Type of network interface
enum NetworkInterfaceType: Int, Comparable {
    case tailscale = 0  // utun* with Tailscale IP ranges (100.64-127.x.x, 10.x.x.x)
    case lan = 1        // en0 (WiFi), en1 (Ethernet)
    case other = 2      // bridge, awdl, etc.
    case loopback = 3   // lo0

    static func < (lhs: NetworkInterfaceType, rhs: NetworkInterfaceType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A discovered network interface with its address and type
struct NetworkInterface {
    let name: String       // e.g., "utun4", "en0"
    let address: String    // e.g., "100.100.1.23"
    let type: NetworkInterfaceType
}

/// Utility for discovering and categorizing network interfaces.
/// Replaces the limited getLocalIP() that only checked en0/en1.
struct NetworkInterfaceResolver {

    /// Enumerate all IPv4 network interfaces on the system
    static func allInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }

            // Only IPv4 for now
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)

            // Resolve IP address
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let address = String(cString: hostname)
            guard !address.isEmpty else { continue }

            let type = categorize(name: name, address: address)
            interfaces.append(NetworkInterface(name: name, address: address, type: type))
        }

        return interfaces.sorted { $0.type < $1.type }
    }

    /// Get the best address for QR code generation or pairing.
    /// Prefers Tailscale when available, falls back to LAN.
    static func bestAddress(preferTailscale: Bool = true) -> String? {
        let interfaces = allInterfaces()

        if preferTailscale, let ts = interfaces.first(where: { $0.type == .tailscale }) {
            return ts.address
        }
        if let lan = interfaces.first(where: { $0.type == .lan }) {
            return lan.address
        }
        // Fallback to any non-loopback
        return interfaces.first(where: { $0.type != .loopback })?.address
    }

    /// Get all available addresses grouped by type
    static func addressesByType() -> [NetworkInterfaceType: [NetworkInterface]] {
        Dictionary(grouping: allInterfaces(), by: \.type)
    }

    // MARK: - Private

    private static func categorize(name: String, address: String) -> NetworkInterfaceType {
        if name == "lo0" {
            return .loopback
        }
        // Tailscale typically uses utun interfaces, but check any interface with Tailscale IPs
        if name.hasPrefix("utun") && TCPConfiguration.isTailscaleIP(address) {
            return .tailscale
        }
        if name == "en0" || name == "en1" {
            return .lan
        }
        // Check for Tailscale IPs on non-standard interfaces (e.g., bridge)
        if TCPConfiguration.isTailscaleIP(address) {
            return .tailscale
        }
        return .other
    }
}
