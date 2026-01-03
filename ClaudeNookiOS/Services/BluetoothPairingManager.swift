//
//  BluetoothPairingManager.swift
//  ClaudeNookiOS
//
//  Bluetooth LE central manager for pairing with Mac.
//  Scans for Claude Nook peripherals and receives auth token.
//

import Combine
import CoreBluetooth
import Foundation
import os.log

private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "Bluetooth")

/// Custom UUIDs for Claude Nook Bluetooth pairing (must match macOS)
enum BluetoothConstants {
    /// Service UUID for Claude Nook pairing
    static let serviceUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

    /// Characteristic UUID for token transfer
    static let tokenCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")

    /// Characteristic UUID for connection info (host, port)
    static let connectionInfoCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")
}

/// Discovered Mac via Bluetooth
struct DiscoveredBluetoothMac: Identifiable, Equatable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    var rssi: Int

    static func == (lhs: DiscoveredBluetoothMac, rhs: DiscoveredBluetoothMac) -> Bool {
        lhs.id == rhs.id
    }
}

/// Bluetooth pairing state
enum BluetoothPairingState: Equatable {
    case idle
    case poweredOff
    case unauthorized
    case scanning
    case connecting(macName: String)
    case connected(macName: String)
    case receivingToken
    case success(host: String, port: Int, token: String)
    case error(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

/// Bluetooth central manager for pairing with Mac
class BluetoothPairingManager: NSObject, ObservableObject {
    static let shared = BluetoothPairingManager()

    // MARK: - Published State

    @Published private(set) var state: BluetoothPairingState = .idle
    @Published private(set) var discoveredMacs: [DiscoveredBluetoothMac] = []

    // MARK: - CoreBluetooth

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?

    // MARK: - Connection Data

    private var receivedToken: String?
    private var receivedHost: String?
    private var receivedPort: Int?

    // MARK: - Callbacks

    var onPairingComplete: ((String, Int, String) -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start scanning for Claude Nook Macs
    func startScanning() {
        // Reset state
        discoveredMacs = []
        receivedToken = nil
        receivedHost = nil
        receivedPort = nil

        if centralManager == nil {
            // Create central manager (triggers delegate callback)
            centralManager = CBCentralManager(delegate: self, queue: nil)
            logger.info("Bluetooth: Initializing central manager")
        } else if let cm = centralManager, cm.state == .poweredOn {
            scan()
        }
    }

    /// Stop scanning
    func stopScanning() {
        centralManager?.stopScan()
        state = .idle
        logger.info("Bluetooth: Stopped scanning")
    }

    /// Connect to a discovered Mac
    func connect(to mac: DiscoveredBluetoothMac) {
        guard let cm = centralManager else { return }

        state = .connecting(macName: mac.name)
        connectedPeripheral = mac.peripheral
        mac.peripheral.delegate = self
        cm.connect(mac.peripheral, options: nil)
        logger.info("Bluetooth: Connecting to \(mac.name)")
    }

    /// Disconnect from current peripheral
    func disconnect() {
        if let peripheral = connectedPeripheral, let cm = centralManager {
            cm.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        state = .idle
    }

    /// Clean up resources
    func cleanup() {
        disconnect()
        stopScanning()
        centralManager = nil
        discoveredMacs = []
    }

    // MARK: - Private Methods

    private func scan() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }

        state = .scanning
        cm.scanForPeripherals(
            withServices: [BluetoothConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Bluetooth: Started scanning for Claude Nook peripherals")
    }

    private func checkPairingComplete() {
        guard let token = receivedToken,
              let host = receivedHost,
              let port = receivedPort else {
            return
        }

        logger.info("Bluetooth: Pairing complete - host: \(host), port: \(port)")
        state = .success(host: host, port: port, token: token)

        // Notify callback
        onPairingComplete?(host, port, token)

        // Disconnect after successful pairing
        disconnect()
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothPairingManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("Bluetooth: Powered on")
            scan()

        case .poweredOff:
            logger.info("Bluetooth: Powered off")
            state = .poweredOff
            discoveredMacs = []

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

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Mac"

        logger.info("Bluetooth: Discovered \(name) with RSSI \(RSSI)")

        // Check if we already have this peripheral
        if let index = discoveredMacs.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
            // Update RSSI
            discoveredMacs[index].rssi = RSSI.intValue
        } else {
            // Add new
            let mac = DiscoveredBluetoothMac(
                id: peripheral.identifier,
                name: name,
                peripheral: peripheral,
                rssi: RSSI.intValue
            )
            discoveredMacs.append(mac)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Bluetooth: Connected to \(peripheral.name ?? "Unknown")")
        state = .connected(macName: peripheral.name ?? "Mac")

        // Discover services
        peripheral.discoverServices([BluetoothConstants.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Bluetooth: Failed to connect: \(error?.localizedDescription ?? "unknown")")
        state = .error(error?.localizedDescription ?? "Connection failed")
        connectedPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("Bluetooth: Disconnected from \(peripheral.name ?? "Unknown")")

        // Only reset state if we haven't successfully paired
        if case .success = state {
            // Keep success state
        } else {
            state = .idle
        }
        connectedPeripheral = nil
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothPairingManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("Bluetooth: Service discovery error: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == BluetoothConstants.serviceUUID {
                logger.info("Bluetooth: Found Claude Nook service")
                // Discover characteristics
                peripheral.discoverCharacteristics(
                    [BluetoothConstants.tokenCharacteristicUUID, BluetoothConstants.connectionInfoCharacteristicUUID],
                    for: service
                )
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logger.error("Bluetooth: Characteristic discovery error: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            return
        }

        guard let characteristics = service.characteristics else { return }

        state = .receivingToken

        for characteristic in characteristics {
            if characteristic.uuid == BluetoothConstants.tokenCharacteristicUUID {
                logger.info("Bluetooth: Reading token characteristic")
                peripheral.readValue(for: characteristic)
            } else if characteristic.uuid == BluetoothConstants.connectionInfoCharacteristicUUID {
                logger.info("Bluetooth: Reading connection info characteristic")
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Bluetooth: Read error: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            return
        }

        guard let data = characteristic.value else {
            logger.warning("Bluetooth: No data in characteristic")
            return
        }

        if characteristic.uuid == BluetoothConstants.tokenCharacteristicUUID {
            if let token = String(data: data, encoding: .utf8) {
                logger.info("Bluetooth: Received token (\(token.count) chars)")
                receivedToken = token
                checkPairingComplete()
            }
        } else if characteristic.uuid == BluetoothConstants.connectionInfoCharacteristicUUID {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let host = json["host"] as? String,
               let port = json["port"] as? Int {
                logger.info("Bluetooth: Received connection info - \(host):\(port)")
                receivedHost = host
                receivedPort = port
                checkPairingComplete()
            }
        }
    }
}
