//
//  BluetoothPairingService.swift
//  ClaudeNook
//
//  Bluetooth LE peripheral service for iOS app pairing.
//  Advertises a service that iOS can connect to for receiving the auth token.
//

import Combine
import CoreBluetooth
import Foundation
import os.log

private let logger = Logger(subsystem: "com.jmi2020.claudenook", category: "Bluetooth")

/// Custom UUIDs for Claude Nook Bluetooth pairing
enum BluetoothConstants {
    /// Service UUID for Claude Nook pairing
    static let serviceUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

    /// Characteristic UUID for token transfer
    static let tokenCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")

    /// Characteristic UUID for connection info (host, port)
    static let connectionInfoCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")

    /// Local name for advertising
    static let localName = "Claude Nook"
}

/// Bluetooth pairing service state
enum BluetoothPairingState: Equatable {
    case idle
    case poweredOff
    case unauthorized
    case advertising
    case connected(deviceName: String)
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .poweredOff:
            return "Bluetooth is off"
        case .unauthorized:
            return "Bluetooth access denied"
        case .advertising:
            return "Waiting for iPhone..."
        case .connected(let name):
            return "Connected to \(name)"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}

/// Bluetooth LE peripheral service for pairing with iOS app
@MainActor
class BluetoothPairingService: NSObject, ObservableObject {
    static let shared = BluetoothPairingService()

    // MARK: - Published State

    @Published private(set) var state: BluetoothPairingState = .idle
    @Published private(set) var isAdvertising = false

    // MARK: - CoreBluetooth

    private var peripheralManager: CBPeripheralManager?
    private var service: CBMutableService?
    private var tokenCharacteristic: CBMutableCharacteristic?
    private var connectionInfoCharacteristic: CBMutableCharacteristic?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start advertising for iOS pairing
    func startAdvertising() {
        guard peripheralManager == nil else {
            // Already have a manager, just start advertising
            if let pm = peripheralManager, pm.state == .poweredOn {
                advertise()
            }
            return
        }

        // Create peripheral manager (this will trigger delegate callbacks)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        logger.info("Bluetooth: Initializing peripheral manager")
    }

    /// Stop advertising
    func stopAdvertising() {
        guard let pm = peripheralManager else { return }

        if pm.isAdvertising {
            pm.stopAdvertising()
        }

        isAdvertising = false
        state = .idle
        logger.info("Bluetooth: Stopped advertising")
    }

    /// Clean up resources
    func cleanup() {
        stopAdvertising()
        peripheralManager = nil
        service = nil
        tokenCharacteristic = nil
        connectionInfoCharacteristic = nil
    }

    // MARK: - Private Methods

    private func setupService() {
        guard let pm = peripheralManager else { return }

        // Create token characteristic (read-only, requires encryption)
        tokenCharacteristic = CBMutableCharacteristic(
            type: BluetoothConstants.tokenCharacteristicUUID,
            properties: [.read],
            value: nil,  // Will be set dynamically on read
            permissions: [.readable]
        )

        // Create connection info characteristic (read-only)
        connectionInfoCharacteristic = CBMutableCharacteristic(
            type: BluetoothConstants.connectionInfoCharacteristicUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        // Create service
        service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        service?.characteristics = [tokenCharacteristic!, connectionInfoCharacteristic!]

        // Add service to peripheral manager
        pm.add(service!)
        logger.info("Bluetooth: Service added")
    }

    private func advertise() {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BluetoothConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: BluetoothConstants.localName
        ]

        pm.startAdvertising(advertisementData)
        isAdvertising = true
        state = .advertising
        logger.info("Bluetooth: Started advertising")
    }

    /// Get the current token value as Data
    private func getTokenData() -> Data? {
        let token = NetworkSettings.shared.currentToken
        guard !token.isEmpty else { return nil }
        return token.data(using: .utf8)
    }

    /// Get connection info as JSON Data
    private func getConnectionInfoData() -> Data? {
        guard let host = getLocalIP() else { return nil }
        let port = NetworkSettings.shared.configuration.port

        let info: [String: Any] = [
            "host": host,
            "port": port
        ]

        return try? JSONSerialization.data(withJSONObject: info)
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }

            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

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
            address = String(cString: hostname)
            break
        }

        return address
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothPairingService: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn:
                logger.info("Bluetooth: Powered on")
                setupService()
                advertise()

            case .poweredOff:
                logger.info("Bluetooth: Powered off")
                state = .poweredOff
                isAdvertising = false

            case .unauthorized:
                logger.warning("Bluetooth: Unauthorized")
                state = .unauthorized

            case .unsupported:
                logger.warning("Bluetooth: Unsupported")
                state = .error("Bluetooth not supported")

            case .resetting:
                logger.info("Bluetooth: Resetting")
                state = .idle

            case .unknown:
                logger.info("Bluetooth: Unknown state")
                state = .idle

            @unknown default:
                logger.warning("Bluetooth: Unknown state value")
                state = .idle
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("Bluetooth: Failed to add service: \(error.localizedDescription)")
                state = .error(error.localizedDescription)
            } else {
                logger.info("Bluetooth: Service added successfully")
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("Bluetooth: Failed to start advertising: \(error.localizedDescription)")
                state = .error(error.localizedDescription)
                isAdvertising = false
            } else {
                logger.info("Bluetooth: Advertising started")
                state = .advertising
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in
            logger.info("Bluetooth: Central subscribed to characteristic")
            state = .connected(deviceName: "iPhone")
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            logger.info("Bluetooth: Central unsubscribed")
            if isAdvertising {
                state = .advertising
            } else {
                state = .idle
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        Task { @MainActor in
            logger.info("Bluetooth: Received read request for \(request.characteristic.uuid)")

            if request.characteristic.uuid == BluetoothConstants.tokenCharacteristicUUID {
                // Return the auth token
                if let tokenData = getTokenData() {
                    request.value = tokenData
                    peripheral.respond(to: request, withResult: .success)
                    logger.info("Bluetooth: Sent token to central")

                    // Update state to show connected
                    state = .connected(deviceName: "iPhone")

                    // Auto-stop advertising after successful token transfer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.stopAdvertising()
                    }
                } else {
                    peripheral.respond(to: request, withResult: .unlikelyError)
                    logger.warning("Bluetooth: No token available")
                }
            } else if request.characteristic.uuid == BluetoothConstants.connectionInfoCharacteristicUUID {
                // Return connection info
                if let infoData = getConnectionInfoData() {
                    request.value = infoData
                    peripheral.respond(to: request, withResult: .success)
                    logger.info("Bluetooth: Sent connection info to central")
                } else {
                    peripheral.respond(to: request, withResult: .unlikelyError)
                    logger.warning("Bluetooth: No connection info available")
                }
            } else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
            }
        }
    }
}
