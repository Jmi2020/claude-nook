//
//  BonjourDiscovery.swift
//  ClaudeNookiOS
//
//  Discovers Claude Nook servers on the local network via Bonjour.
//

import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "BonjourDiscovery")

/// A discovered Claude Nook server
struct DiscoveredHost: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let port: Int

    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.id == rhs.id
    }
}

/// Discovers Claude Nook servers via Bonjour/mDNS
class BonjourDiscovery: ObservableObject {
    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var isScanning = false

    private var browser: NWBrowser?

    /// Start browsing for Claude Nook servers
    func startDiscovery() {
        stopDiscovery()

        logger.info("Starting Bonjour discovery for _claudenook._tcp")
        isScanning = true

        // Add localhost as a fallback for simulator testing
        #if targetEnvironment(simulator)
        let localhostHost = DiscoveredHost(
            id: "localhost-4851",
            name: "Localhost (Simulator)",
            address: "127.0.0.1",
            port: 4851
        )
        if !discoveredHosts.contains(where: { $0.id == localhostHost.id }) {
            discoveredHosts.append(localhostHost)
            logger.info("Added localhost for simulator testing")
        }
        #endif

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_claudenook._tcp", domain: "local.")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                logger.info("Browser ready")
            case .failed(let error):
                logger.error("Browser failed: \(error)")
                Task { @MainActor in
                    self?.isScanning = false
                }
            case .cancelled:
                logger.info("Browser cancelled")
                Task { @MainActor in
                    self?.isScanning = false
                }
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: .main)

        // Auto-stop after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopDiscovery()
        }
    }

    /// Stop browsing
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var hosts: [DiscoveredHost] = []

        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                logger.info("Found service: \(name) (\(type).\(domain))")

                // Resolve the service to get IP and port
                resolveService(name: name, type: type, domain: domain) { host in
                    if let host = host {
                        Task { @MainActor [weak self] in
                            if let self = self,
                               !self.discoveredHosts.contains(where: { $0.id == host.id }) {
                                self.discoveredHosts.append(host)
                            }
                        }
                    }
                }

            default:
                break
            }
        }
    }

    private func resolveService(
        name: String,
        type: String,
        domain: String,
        completion: @escaping (DiscoveredHost?) -> Void
    ) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let parameters = NWParameters.tcp

        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    var hostString: String
                    switch host {
                    case .name(let hostname, _):
                        hostString = hostname
                    case .ipv4(let ipv4):
                        hostString = "\(ipv4)"
                    case .ipv6(let ipv6):
                        hostString = "\(ipv6)"
                    @unknown default:
                        hostString = "unknown"
                    }

                    // Strip interface/zone ID suffix (e.g., "%bridge100", "%en0")
                    // This is common with IPv6 link-local addresses and simulator bridge networks
                    let originalHost = hostString
                    if let percentIndex = hostString.firstIndex(of: "%") {
                        hostString = String(hostString[..<percentIndex])
                        logger.info("Stripped interface suffix: \(originalHost) -> \(hostString)")
                    }

                    let discovered = DiscoveredHost(
                        id: "\(name)-\(hostString):\(port.rawValue)",
                        name: name,
                        address: hostString,
                        port: Int(port.rawValue)
                    )

                    logger.info("Resolved \(name) to \(hostString):\(port.rawValue) (original: \(originalHost))")
                    connection.cancel()
                    completion(discovered)
                }

            case .failed, .cancelled:
                completion(nil)

            default:
                break
            }
        }

        connection.start(queue: .main)

        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready {
                connection.cancel()
                completion(nil)
            }
        }
    }
}
