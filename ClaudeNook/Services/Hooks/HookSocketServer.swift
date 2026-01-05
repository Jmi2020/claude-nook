//
//  HookSocketServer.swift
//  ClaudeNook
//
//  Socket server for real-time hook events
//  Supports Unix domain socket (local) and TCP (remote) connections
//  Supports request/response for permission decisions
//  Supports Bonjour/mDNS for auto-discovery
//

import ClaudeNookShared
import Foundation
import Network
import os.log

/// Type of connection (for routing authentication)
enum ConnectionType: Sendable {
    case unix           // Local Unix socket, no auth needed
    case tcp(address: String)  // Remote TCP, requires authentication
}

/// Logger for hook socket server
private let logger = Logger(subsystem: "com.jmi2020.claudenook", category: "Hooks")

/// Pending permission request waiting for user decision
struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
}

/// Callback for hook events
typealias HookEventHandler = @Sendable (HookEvent) -> Void

/// Callback for permission response failures (socket died)
typealias PermissionFailureHandler = @Sendable (_ sessionId: String, _ toolUseId: String) -> Void

/// Callback to get current session states for iOS subscription
typealias SessionStateProvider = @Sendable () async -> [SessionState]

/// Socket server that receives events from Claude Code hooks
/// Supports both Unix domain socket (local) and TCP (remote) connections
/// Uses GCD DispatchSource for non-blocking I/O
class HookSocketServer {
    static let shared = HookSocketServer()
    static let socketPath = "/tmp/claude-nook.sock"

    // MARK: - Unix Socket Properties
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    // MARK: - TCP Socket Properties
    private var tcpSocket: Int32 = -1
    private var tcpAcceptSource: DispatchSourceRead?
    private var expectedToken: String = ""
    private var trustTailscale: Bool = true

    // MARK: - Bonjour Properties
    private var netService: NetService?
    private var bonjourEnabled: Bool = true

    // MARK: - Common Properties
    private var eventHandler: HookEventHandler?
    private var permissionFailureHandler: PermissionFailureHandler?
    private var sessionStateProvider: SessionStateProvider?
    private let queue = DispatchQueue(label: "com.jmi2020.claudenook.socket", qos: .userInitiated)

    /// Pending permission requests indexed by toolUseId
    private var pendingPermissions: [String: PendingPermission] = [:]
    private let permissionsLock = NSLock()

    /// Cache tool_use_id from PreToolUse to correlate with PermissionRequest
    /// Key: "sessionId:toolName:serializedInput" -> Queue of tool_use_ids (FIFO)
    /// PermissionRequest events don't include tool_use_id, so we cache from PreToolUse
    private var toolUseIdCache: [String: [String]] = [:]
    private let cacheLock = NSLock()

    /// Observer for configuration changes
    private var configObserver: NSObjectProtocol?

    private init() {
        // Listen for TCP configuration changes
        configObserver = NotificationCenter.default.addObserver(
            forName: .tcpConfigurationChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                self?.updateTCPServer()
            }
        }
    }

    private func notifySocketState() {
        let unixRunning = serverSocket >= 0
        let tcpRunning = tcpSocket >= 0
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .hookSocketStateChanged,
                object: nil,
                userInfo: ["unix": unixRunning, "tcp": tcpRunning]
            )
        }
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Start the socket server
    func start(
        onEvent: @escaping HookEventHandler,
        onPermissionFailure: PermissionFailureHandler? = nil,
        sessionStateProvider: SessionStateProvider? = nil
    ) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent, onPermissionFailure: onPermissionFailure, sessionStateProvider: sessionStateProvider)
        }
    }

    private func startServer(
        onEvent: @escaping HookEventHandler,
        onPermissionFailure: PermissionFailureHandler?,
        sessionStateProvider: SessionStateProvider?
    ) {
        guard serverSocket < 0 else { return }

        eventHandler = onEvent
        permissionFailureHandler = onPermissionFailure
        self.sessionStateProvider = sessionStateProvider

        // Set up iOS connection manager message handler
        iOSConnectionManager.shared.setMessageHandler { [weak self] clientId, message in
            self?.handleiOSMessage(clientId: clientId, message: message)
        }

        // Start Unix socket server (always runs for local connections)
        startUnixSocketServer()

        // Start TCP server if configured
        updateTCPServer()
    }

    /// Handle messages from iOS clients
    private func handleiOSMessage(clientId: UUID, message: iOSClientMessage) {
        switch message {
        case .approve(let sessionId, let toolUseId):
            logger.info("iOS: Approve from \(clientId.uuidString.prefix(8), privacy: .public) for \(sessionId.prefix(8), privacy: .public)")
            sendPermissionResponse(toolUseId: toolUseId, decision: "allow", reason: nil)
            // Broadcast resolution to other iOS clients
            iOSConnectionManager.shared.broadcast(.permissionResolved(sessionId: sessionId, toolUseId: toolUseId))

        case .deny(let sessionId, let toolUseId, let reason):
            logger.info("iOS: Deny from \(clientId.uuidString.prefix(8), privacy: .public) for \(sessionId.prefix(8), privacy: .public)")
            sendPermissionResponse(toolUseId: toolUseId, decision: "deny", reason: reason)
            // Broadcast resolution to other iOS clients
            iOSConnectionManager.shared.broadcast(.permissionResolved(sessionId: sessionId, toolUseId: toolUseId))

        case .pong:
            // Heartbeat response, client is alive
            break

        case .disconnect:
            // Client disconnected, already handled by iOSConnectionManager
            break
        }
    }

    // MARK: - Unix Socket Server

    private func startUnixSocketServer() {
        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o777)

        guard listen(serverSocket, 10) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        logger.info("Listening on \(Self.socketPath, privacy: .public)")

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptUnixConnection()
        }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        acceptSource?.resume()
        notifySocketState()
    }

    // MARK: - TCP Socket Server

    /// Update TCP server based on current configuration
    private func updateTCPServer() {
        // Get current configuration from main thread
        Task { @MainActor in
            let config = NetworkSettings.shared.configuration

            // Switch back to socket queue for server operations
            self.queue.async { [weak self] in
                self?.applyTCPConfiguration(config)
            }
        }
    }

    private func applyTCPConfiguration(_ config: TCPConfiguration) {
        // Stop existing TCP server if running
        stopTCPServer()

        guard config.bindMode != .disabled else {
            logger.info("TCP server disabled")
            return
        }

        guard let bindAddress = config.bindMode.bindAddress else {
            return
        }

        expectedToken = config.authToken
        trustTailscale = config.trustTailscale
        bonjourEnabled = config.bonjourEnabled

        // Create TCP socket
        tcpSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard tcpSocket >= 0 else {
            logger.error("TCP: Failed to create socket: \(errno)")
            return
        }

        // Set socket options
        var reuseAddr: Int32 = 1
        setsockopt(tcpSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(tcpSocket, F_GETFL)
        _ = fcntl(tcpSocket, F_SETFL, flags | O_NONBLOCK)

        // Bind to address
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = config.port.bigEndian

        if bindAddress == "0.0.0.0" {
            addr.sin_addr.s_addr = INADDR_ANY
        } else {
            inet_pton(AF_INET, bindAddress, &addr.sin_addr)
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(tcpSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("TCP: Failed to bind to \(bindAddress, privacy: .public):\(config.port): errno \(errno)")
            close(tcpSocket)
            tcpSocket = -1
            return
        }

        guard listen(tcpSocket, 10) == 0 else {
            logger.error("TCP: Failed to listen: \(errno)")
            close(tcpSocket)
            tcpSocket = -1
            return
        }

        logger.info("TCP: Listening on \(bindAddress, privacy: .public):\(config.port, privacy: .public)")

        tcpAcceptSource = DispatchSource.makeReadSource(fileDescriptor: tcpSocket, queue: queue)
        tcpAcceptSource?.setEventHandler { [weak self] in
            self?.acceptTCPConnection()
        }
        tcpAcceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.tcpSocket, fd >= 0 {
                close(fd)
                self?.tcpSocket = -1
            }
        }
        tcpAcceptSource?.resume()
        notifySocketState()

        // Start Bonjour advertising if enabled
        if bonjourEnabled {
            startBonjourService(port: config.port)
        }
    }

    // MARK: - Bonjour Service

    private func startBonjourService(port: UInt16) {
        stopBonjourService()

        // Create NetService for _claudenook._tcp
        netService = NetService(domain: "", type: "_claudenook._tcp.", name: "", port: Int32(port))
        netService?.publish()
        logger.info("Bonjour: Advertising _claudenook._tcp on port \(port)")
    }

    private func stopBonjourService() {
        netService?.stop()
        netService = nil
    }

    private func stopTCPServer() {
        stopBonjourService()
        tcpAcceptSource?.cancel()
        tcpAcceptSource = nil
        if tcpSocket >= 0 {
            close(tcpSocket)
            tcpSocket = -1
        }
        notifySocketState()
    }

    /// Stop the socket server
    func stop() {
        // Stop Unix socket
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)
        serverSocket = -1

        // Stop TCP socket
        stopTCPServer()

        permissionsLock.lock()
        for (_, pending) in pendingPermissions {
            close(pending.clientSocket)
        }
        pendingPermissions.removeAll()
        permissionsLock.unlock()

        notifySocketState()
    }

    /// Respond to a pending permission request by toolUseId
    func respondToPermission(toolUseId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponse(toolUseId: toolUseId, decision: decision, reason: reason)
        }
    }

    /// Respond to permission by sessionId (finds the most recent pending for that session)
    func respondToPermissionBySession(sessionId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponseBySession(sessionId: sessionId, decision: decision, reason: reason)
        }
    }

    /// Cancel all pending permissions for a session (when Claude stops waiting)
    func cancelPendingPermissions(sessionId: String) {
        queue.async { [weak self] in
            self?.cleanupPendingPermissions(sessionId: sessionId)
        }
    }

    /// Check if there's a pending permission request for a session
    func hasPendingPermission(sessionId: String) -> Bool {
        permissionsLock.lock()
        defer { permissionsLock.unlock() }
        return pendingPermissions.values.contains { $0.sessionId == sessionId }
    }

    /// Get the pending permission details for a session (if any)
    func getPendingPermission(sessionId: String) -> (toolName: String?, toolId: String?, toolInput: [String: AnyCodable]?)? {
        permissionsLock.lock()
        defer { permissionsLock.unlock() }
        guard let pending = pendingPermissions.values.first(where: { $0.sessionId == sessionId }) else {
            return nil
        }
        return (pending.event.tool, pending.toolUseId, pending.event.toolInput)
    }

    /// Cancel a specific pending permission by toolUseId (when tool completes via terminal approval)
    func cancelPendingPermission(toolUseId: String) {
        queue.async { [weak self] in
            self?.cleanupSpecificPermission(toolUseId: toolUseId)
        }
    }

    private func cleanupSpecificPermission(toolUseId: String) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            return
        }
        permissionsLock.unlock()

        logger.debug("Tool completed externally, closing socket for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
        close(pending.clientSocket)
    }

    private func cleanupPendingPermissions(sessionId: String) {
        permissionsLock.lock()
        let matching = pendingPermissions.filter { $0.value.sessionId == sessionId }
        for (toolUseId, pending) in matching {
            logger.debug("Cleaning up stale permission for \(sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
            close(pending.clientSocket)
            pendingPermissions.removeValue(forKey: toolUseId)
        }
        permissionsLock.unlock()
    }

    // MARK: - Tool Use ID Cache

    /// Encoder with sorted keys for deterministic cache keys
    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Generate cache key from event properties
    private func cacheKey(sessionId: String, toolName: String?, toolInput: [String: AnyCodable]?) -> String {
        let inputStr: String
        if let input = toolInput,
           let data = try? Self.sortedEncoder.encode(input),
           let str = String(data: data, encoding: .utf8) {
            inputStr = str
        } else {
            inputStr = "{}"
        }
        return "\(sessionId):\(toolName ?? "unknown"):\(inputStr)"
    }

    /// Cache tool_use_id from PreToolUse event (FIFO queue per key)
    private func cacheToolUseId(event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }

        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        if toolUseIdCache[key] == nil {
            toolUseIdCache[key] = []
        }
        toolUseIdCache[key]?.append(toolUseId)
        cacheLock.unlock()

        logger.debug("Cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
    }

    /// Pop and return cached tool_use_id for PermissionRequest (FIFO)
    private func popCachedToolUseId(event: HookEvent) -> String? {
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard var queue = toolUseIdCache[key], !queue.isEmpty else {
            return nil
        }

        let toolUseId = queue.removeFirst()

        if queue.isEmpty {
            toolUseIdCache.removeValue(forKey: key)
        } else {
            toolUseIdCache[key] = queue
        }

        logger.debug("Retrieved cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
        return toolUseId
    }

    /// Clean up cache entries for a session (on session end)
    private func cleanupCache(sessionId: String) {
        cacheLock.lock()
        let keysToRemove = toolUseIdCache.keys.filter { $0.hasPrefix("\(sessionId):") }
        for key in keysToRemove {
            toolUseIdCache.removeValue(forKey: key)
        }
        cacheLock.unlock()

        if !keysToRemove.isEmpty {
            logger.debug("Cleaned up \(keysToRemove.count) cache entries for session \(sessionId.prefix(8), privacy: .public)")
        }
    }

    // MARK: - Connection Handling

    private func acceptUnixConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket, connectionType: .unix)
    }

    private func acceptTCPConnection() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(tcpSocket, sockaddrPtr, &addrLen)
            }
        }

        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Extract client IP for logging
        var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &clientAddr.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
        let clientIP = String(cString: ipBuffer)

        logger.debug("TCP: Connection from \(clientIP, privacy: .public)")

        handleClient(clientSocket, connectionType: .tcp(address: clientIP))
    }

    /// Authenticate TCP client using AUTH protocol
    /// Tailscale IPs (100.64.0.0/10) are auto-trusted if trustTailscale is enabled
    /// Returns (success, leftoverData) - leftover data is anything read after the AUTH line
    private func authenticateTCPClient(_ clientSocket: Int32, address: String) -> (success: Bool, leftover: Data?) {
        // Check if this is a trusted Tailscale connection
        if trustTailscale && TCPConfiguration.isTailscaleIP(address) {
            logger.info("TCP: Auto-trusting Tailscale connection from \(address, privacy: .public)")
            // Send OK immediately for trusted connections
            let okResponse = "OK\n"
            _ = okResponse.withCString { ptr in
                write(clientSocket, ptr, strlen(ptr))
            }
            return (true, nil)
        }

        // Read auth line (AUTH <token>\n)
        var authBuffer = [UInt8](repeating: 0, count: 256)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        // 5 second timeout for auth
        let pollResult = poll(&pollFd, 1, 5000)
        guard pollResult > 0 else {
            logger.warning("TCP: Auth timeout from \(address, privacy: .public)")
            sendTCPError(to: clientSocket, message: "Auth timeout")
            return (false, nil)
        }

        let bytesRead = read(clientSocket, &authBuffer, authBuffer.count)
        guard bytesRead > 0 else {
            logger.warning("TCP: No auth data from \(address, privacy: .public)")
            return (false, nil)
        }

        // Parse auth line
        guard let authString = String(bytes: authBuffer[0..<bytesRead], encoding: .utf8) else {
            sendTCPError(to: clientSocket, message: "Invalid auth format")
            return (false, nil)
        }

        // Find newline and extract auth part
        guard let newlineIndex = authString.firstIndex(of: "\n") else {
            sendTCPError(to: clientSocket, message: "Invalid auth format")
            return (false, nil)
        }

        let authLine = String(authString[..<newlineIndex])
        logger.info("TCP: Received auth line (len=\(authLine.count))")

        let parts = authLine.split(separator: " ", maxSplits: 1)

        guard parts.count == 2, parts[0] == "AUTH" else {
            let firstPart = parts.first.map { String($0) } ?? "nil"
            logger.error("TCP: Invalid AUTH format from \(address, privacy: .public) - parts: \(parts.count), first='\(firstPart, privacy: .public)'")
            sendTCPError(to: clientSocket, message: "Invalid auth format")
            return (false, nil)
        }

        let receivedToken = String(parts[1])

        guard receivedToken == expectedToken else {
            logger.warning("TCP: Auth failed - token mismatch from \(address, privacy: .public)")
            sendTCPError(to: clientSocket, message: "Invalid token")
            return (false, nil)
        }

        // Send OK response
        let okResponse = "OK\n"
        _ = okResponse.withCString { ptr in
            write(clientSocket, ptr, strlen(ptr))
        }

        logger.info("TCP: Authenticated client from \(address, privacy: .public)")

        // Check for leftover data after AUTH line (e.g., SUBSCRIBE sent in same packet)
        let afterNewline = authString.index(after: newlineIndex)
        if afterNewline < authString.endIndex {
            let leftoverString = String(authString[afterNewline...])
            logger.info("TCP: Found leftover data after AUTH: '\(leftoverString.prefix(20), privacy: .public)'")
            return (true, leftoverString.data(using: .utf8))
        }

        return (true, nil)
    }

    /// Send error message to TCP client
    private func sendTCPError(to clientSocket: Int32, message: String) {
        let errorResponse = "ERR: \(message)\n"
        _ = errorResponse.withCString { ptr in
            write(clientSocket, ptr, strlen(ptr))
        }
    }

    // MARK: - iOS Pairing

    /// Handle PAIR command from iOS client
    /// Format: PAIR <6-digit-code>
    /// Response: TOKEN <64-char-token> or ERR: <message>
    private func handlePairCommand(_ clientSocket: Int32, command: String, address: String) {
        logger.info("PAIR command from \(address, privacy: .public)")

        // Extract the 6-digit code
        let parts = command.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else {
            sendTCPError(to: clientSocket, message: "Invalid PAIR format")
            close(clientSocket)
            return
        }

        let code = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate the pairing code
        guard let token = PairingCodeManager.shared.validateCode(code) else {
            sendTCPError(to: clientSocket, message: "Invalid or expired pairing code")
            close(clientSocket)
            return
        }

        logger.info("PAIR: Returning token: \(token.prefix(8), privacy: .public)... (len=\(token.count))")
        logger.info("PAIR: Expected token is: \(self.expectedToken.prefix(8), privacy: .public)... (len=\(self.expectedToken.count))")

        // Send the token back
        let response = "TOKEN \(token)\n"
        _ = response.withCString { ptr in
            write(clientSocket, ptr, strlen(ptr))
        }

        logger.info("PAIR successful from \(address, privacy: .public)")
        close(clientSocket)
    }

    // MARK: - iOS SUBSCRIBE Mode

    /// Handle iOS client that sent SUBSCRIBE command
    private func handleSubscribeClient(_ clientSocket: Int32, address: String) {
        logger.info("iOS: SUBSCRIBE from \(address, privacy: .public)")

        // Add to iOS connection manager (this keeps the socket open)
        let clientId = iOSConnectionManager.shared.addClient(socket: clientSocket, address: address)

        // Send initial state snapshot
        Task {
            await sendInitialState(to: clientId)
        }
    }

    /// Send initial state snapshot to a newly subscribed iOS client
    private func sendInitialState(to clientId: UUID) async {
        guard let provider = sessionStateProvider else {
            logger.warning("iOS: No session state provider - sending empty state")
            let emptySnapshot = StateSnapshot(sessions: [])
            iOSConnectionManager.shared.send(.state(emptySnapshot), to: clientId)
            return
        }

        let sessions = await provider()
        let lightSessions = sessions.map { SessionStateLight(from: $0) }
        let snapshot = StateSnapshot(sessions: lightSessions)
        iOSConnectionManager.shared.send(.state(snapshot), to: clientId)

        logger.info("iOS: Sent initial state with \(sessions.count) sessions")
    }

    /// Broadcast a session update to all connected iOS clients
    func broadcastSessionUpdate(_ session: SessionState) {
        guard iOSConnectionManager.shared.hasClients else { return }

        let lightSession = SessionStateLight(from: session)
        iOSConnectionManager.shared.broadcast(.sessionUpdate(lightSession))
    }

    /// Broadcast session removed to all connected iOS clients
    func broadcastSessionRemoved(sessionId: String) {
        guard iOSConnectionManager.shared.hasClients else { return }

        iOSConnectionManager.shared.broadcast(.sessionRemoved(sessionId: sessionId))
    }

    /// Broadcast a permission request to all connected iOS clients
    func broadcastPermissionRequest(sessionId: String, toolUseId: String, toolName: String, toolInput: String?, projectName: String) {
        guard iOSConnectionManager.shared.hasClients else { return }

        let request = PermissionRequest(
            sessionId: sessionId,
            toolUseId: toolUseId,
            toolName: toolName,
            toolInput: toolInput,
            projectName: projectName
        )
        iOSConnectionManager.shared.broadcast(.permissionRequest(request))
    }

    /// Get count of connected iOS clients
    var iOSClientCount: Int {
        iOSConnectionManager.shared.clientCount
    }

    private func handleClient(_ clientSocket: Int32, connectionType: ConnectionType) {
        // For TCP connections, check for PAIR command first (no auth needed)
        // then authenticate other connections
        var clientAddress = ""
        if case .tcp(let address) = connectionType {
            clientAddress = address

            // Peek at first few bytes to check for PAIR command
            // PAIR commands don't require authentication - they're used to GET a token
            var peekBuffer = [UInt8](repeating: 0, count: 16)
            var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pollFd, 1, 5000)

            if pollResult > 0 {
                // Peek without consuming the data
                let peeked = recv(clientSocket, &peekBuffer, peekBuffer.count, MSG_PEEK)
                if peeked > 0,
                   let peekStr = String(bytes: peekBuffer[0..<peeked], encoding: .utf8),
                   peekStr.hasPrefix("PAIR ") {
                    // This is a PAIR command - handle without authentication
                    logger.info("TCP: Detected PAIR command from \(address, privacy: .public)")

                    // Now read the full line
                    var pairBuffer = [UInt8](repeating: 0, count: 256)
                    let bytesRead = read(clientSocket, &pairBuffer, pairBuffer.count)
                    if bytesRead > 0,
                       let pairStr = String(bytes: pairBuffer[0..<bytesRead], encoding: .utf8) {
                        let trimmed = pairStr.trimmingCharacters(in: .whitespacesAndNewlines)
                        handlePairCommand(clientSocket, command: trimmed, address: address)
                        return
                    }
                    close(clientSocket)
                    return
                }
            }

            // Not a PAIR command - require authentication
            let authResult = authenticateTCPClient(clientSocket, address: address)
            guard authResult.success else {
                close(clientSocket)
                return
            }

            // Check if leftover data contains SUBSCRIBE
            if let leftover = authResult.leftover,
               let leftoverStr = String(data: leftover, encoding: .utf8) {
                let trimmed = leftoverStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "SUBSCRIBE" {
                    logger.info("TCP: Found SUBSCRIBE in leftover data from \(address, privacy: .public)")
                    handleSubscribeClient(clientSocket, address: address)
                    return
                }
            }
        }

        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 131072)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)

                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])

                    // Check for SUBSCRIBE command (iOS client)
                    if let str = String(data: allData, encoding: .utf8) {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed == "SUBSCRIBE" {
                            handleSubscribeClient(clientSocket, address: clientAddress)
                            return
                        }
                        // Check for PAIR command (iOS client pairing with 6-digit code)
                        if trimmed.hasPrefix("PAIR ") {
                            handlePairCommand(clientSocket, command: trimmed, address: clientAddress)
                            return
                        }
                    }

                    // Check if data looks like complete JSON (starts with { and ends with })
                    if allData.first == 0x7B {  // '{'
                        if let lastNonWhitespace = allData.last(where: { !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar($0)) }),
                           lastNonWhitespace == 0x7D {  // '}'
                            break
                        }
                    }
                } else if bytesRead == 0 {
                    break
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty {
                    break
                }
            } else {
                break
            }
        }

        guard !allData.isEmpty else {
            close(clientSocket)
            return
        }

        let data = allData

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
            // Check one more time for SUBSCRIBE in case we missed it
            if let str = String(data: data, encoding: .utf8),
               str.trimmingCharacters(in: .whitespacesAndNewlines) == "SUBSCRIBE" {
                handleSubscribeClient(clientSocket, address: clientAddress)
                return
            }
            logger.warning("Failed to parse event: \(String(data: data, encoding: .utf8) ?? "?", privacy: .public)")
            close(clientSocket)
            return
        }

        logger.debug("Received: \(event.event, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)")

        if event.event == "PreToolUse" {
            cacheToolUseId(event: event)
        }

        if event.event == "SessionEnd" {
            cleanupCache(sessionId: event.sessionId)
        }

        if event.expectsResponse {
            let toolUseId: String
            if let eventToolUseId = event.toolUseId {
                toolUseId = eventToolUseId
            } else if let cachedToolUseId = popCachedToolUseId(event: event) {
                toolUseId = cachedToolUseId
            } else {
                logger.warning("Permission request missing tool_use_id for \(event.sessionId.prefix(8), privacy: .public) - no cache hit")
                close(clientSocket)
                eventHandler?(event)
                return
            }

            logger.debug("Permission request - keeping socket open for \(event.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")

            let updatedEvent = HookEvent(
                sessionId: event.sessionId,
                cwd: event.cwd,
                event: event.event,
                status: event.status,
                pid: event.pid,
                tty: event.tty,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,  // Use resolved toolUseId
                notificationType: event.notificationType,
                message: event.message
            )

            let pending = PendingPermission(
                sessionId: event.sessionId,
                toolUseId: toolUseId,
                clientSocket: clientSocket,
                event: updatedEvent,
                receivedAt: Date()
            )
            permissionsLock.lock()
            pendingPermissions[toolUseId] = pending
            permissionsLock.unlock()

            eventHandler?(updatedEvent)
            return
        } else {
            close(clientSocket)
        }

        eventHandler?(event)
    }

    private func sendPermissionResponse(toolUseId: String, decision: String, reason: String?) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            logger.debug("No pending permission for toolUseId: \(toolUseId.prefix(12), privacy: .public)")
            return
        }
        permissionsLock.unlock()

        let response = HookResponse(decision: decision, reason: reason)
        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            return
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(decision, privacy: .public) for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                logger.error("Failed to get data buffer address")
                return
            }
            let result = write(pending.clientSocket, baseAddress, data.count)
            if result < 0 {
                logger.error("Write failed with errno: \(errno)")
            } else {
                logger.debug("Write succeeded: \(result) bytes")
            }
        }

        close(pending.clientSocket)
    }

    private func sendPermissionResponseBySession(sessionId: String, decision: String, reason: String?) {
        permissionsLock.lock()
        let matchingPending = pendingPermissions.values
            .filter { $0.sessionId == sessionId }
            .sorted { $0.receivedAt > $1.receivedAt }
            .first

        guard let pending = matchingPending else {
            permissionsLock.unlock()
            logger.debug("No pending permission for session: \(sessionId.prefix(8), privacy: .public)")
            return
        }

        pendingPermissions.removeValue(forKey: pending.toolUseId)
        permissionsLock.unlock()

        let response = HookResponse(decision: decision, reason: reason)
        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            permissionFailureHandler?(sessionId, pending.toolUseId)
            return
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(decision, privacy: .public) for \(sessionId.prefix(8), privacy: .public) tool:\(pending.toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")

        var writeSuccess = false
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                logger.error("Failed to get data buffer address")
                return
            }
            let result = write(pending.clientSocket, baseAddress, data.count)
            if result < 0 {
                logger.error("Write failed with errno: \(errno)")
            } else {
                logger.debug("Write succeeded: \(result) bytes")
                writeSuccess = true
            }
        }

        close(pending.clientSocket)

        if !writeSuccess {
            permissionFailureHandler?(sessionId, pending.toolUseId)
        }
    }
}
