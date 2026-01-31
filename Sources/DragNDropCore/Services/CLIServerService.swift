import Foundation
import Logging
import Network

// MARK: - CLI Server Service

/// Provides a local TCP server for CLI control of the app
public actor CLIServerService {
    private let logger = Logger(label: "com.dragndrop.cli.server")

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var isRunning = false

    // Command handlers
    private var commandHandler: ((CLICommand) async -> CLIResponse)?

    public init() {}

    // MARK: - Server Control

    public func start(port: UInt16) async throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateChange(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .global())
        isRunning = true

        logger.info("CLI server started on port \(port)")
    }

    public func stop() async {
        listener?.cancel()
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        isRunning = false
        logger.info("CLI server stopped")
    }

    public func setCommandHandler(_ handler: @escaping (CLICommand) async -> CLIResponse) {
        self.commandHandler = handler
    }

    // MARK: - Connection Handling

    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.debug("Listener ready")
        case .failed(let error):
            logger.error("Listener failed: \(error)")
        case .cancelled:
            logger.debug("Listener cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionState(connection: connection, state: state)
            }
        }

        connection.start(queue: .global())
        receiveData(on: connection)
    }

    private func handleConnectionState(connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            logger.debug("Connection ready")
        case .failed(let error):
            logger.error("Connection failed: \(error)")
            removeConnection(connection)
        case .cancelled:
            removeConnection(connection)
        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    private nonisolated func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                if let data = data, !data.isEmpty {
                    await self?.processData(data, on: connection)
                }

                if isComplete {
                    connection.cancel()
                } else if error == nil {
                    self?.receiveData(on: connection)
                }
            }
        }
    }

    private func processData(_ data: Data, on connection: NWConnection) async {
        guard let json = try? JSONDecoder().decode(CLICommand.self, from: data) else {
            let errorResponse = CLIResponse(
                success: false,
                error: "Invalid command format",
                data: nil
            )
            await send(response: errorResponse, on: connection)
            return
        }

        logger.debug("Received command: \(json.command)")

        let response: CLIResponse
        if let handler = commandHandler {
            response = await handler(json)
        } else {
            response = CLIResponse(success: false, error: "No command handler registered", data: nil)
        }

        await send(response: response, on: connection)
    }

    private func send(response: CLIResponse, on connection: NWConnection) async {
        guard let data = try? JSONEncoder().encode(response) else { return }

        let dataWithNewline = data + Data("\n".utf8)

        connection.send(content: dataWithNewline, completion: .contentProcessed { error in
            if let error = error {
                self.logger.error("Send error: \(error)")
            }
        })
    }
}

// MARK: - CLI Types

public struct CLICommand: Codable, Sendable {
    public let command: String
    public let args: [String: AnyCodable]?

    public init(command: String, args: [String: AnyCodable]? = nil) {
        self.command = command
        self.args = args
    }
}

public struct CLIResponse: Codable, Sendable {
    public let success: Bool
    public let error: String?
    public let data: [String: AnyCodable]?

    public init(success: Bool, error: String?, data: [String: AnyCodable]?) {
        self.success = success
        self.error = error
        self.data = data
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - CLI Commands

public enum CLICommands {
    public static let status = "status"
    public static let upload = "upload"
    public static let pause = "pause"
    public static let resume = "resume"
    public static let cancel = "cancel"
    public static let list = "list"
    public static let history = "history"
    public static let config = "config"
    public static let auth = "auth"
    public static let quit = "quit"
}
