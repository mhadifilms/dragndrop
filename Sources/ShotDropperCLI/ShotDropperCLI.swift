import Foundation
import ArgumentParser
import ShotDropperCore
import Network

// MARK: - Main CLI Entry Point

@main
struct ShotDropperCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shotdrop",
        abstract: "CLI tool for ShotDropper - control uploads from the command line",
        version: "1.0.0",
        subcommands: [
            Status.self,
            Upload.self,
            List.self,
            Pause.self,
            Resume.self,
            Cancel.self,
            History.self,
            Config.self,
            Server.self
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Port to connect to the ShotDropper app")
    var port: UInt16 = 9847

    @Option(name: .long, help: "Output format (text, json)")
    var format: OutputFormat = .text
}

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
}

// MARK: - CLI Client

actor CLIClient {
    private var connection: NWConnection?

    func connect(port: UInt16) async throws {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        connection = NWConnection(to: endpoint, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CLIError.connectionCancelled)
                default:
                    break
                }
            }
            connection?.start(queue: .global())
        }
    }

    func send(command: CLICommand) async throws -> CLIResponse {
        guard let connection = connection else {
            throw CLIError.notConnected
        }

        let data = try JSONEncoder().encode(command)

        // Send
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        // Receive response
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: CLIError.noResponse)
                    return
                }

                do {
                    let response = try JSONDecoder().decode(CLIResponse.self, from: data)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }
}

enum CLIError: Error, LocalizedError {
    case notConnected
    case connectionCancelled
    case noResponse
    case appNotRunning

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to ShotDropper"
        case .connectionCancelled:
            return "Connection was cancelled"
        case .noResponse:
            return "No response received"
        case .appNotRunning:
            return "ShotDropper app is not running. Please start the app first."
        }
    }
}

// MARK: - Status Command

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show current upload status"
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        let response = try await client.send(command: CLICommand(command: CLICommands.status))
        await client.disconnect()

        if !response.success {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }

        if options.format == .json {
            let jsonData = try JSONEncoder().encode(response.data)
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
        } else {
            printStatus(response.data)
        }
    }

    private func printStatus(_ data: [String: AnyCodable]?) {
        guard let data = data else {
            print("No status data available")
            return
        }

        let isRunning = (data["isRunning"]?.value as? Bool) ?? false
        let isPaused = (data["isPaused"]?.value as? Bool) ?? false
        let pending = (data["pending"]?.value as? Int) ?? 0
        let active = (data["active"]?.value as? Int) ?? 0
        let completed = (data["completed"]?.value as? Int) ?? 0
        let failed = (data["failed"]?.value as? Int) ?? 0
        let progress = (data["progress"]?.value as? Double) ?? 0.0

        print("=== ShotDropper Status ===")
        print("")

        if isRunning {
            if isPaused {
                print("Status: \u{1F7E1} Paused")
            } else {
                print("Status: \u{1F7E2} Uploading")
            }
        } else {
            print("Status: \u{26AA} Idle")
        }

        print("")
        print("Pending:   \(pending)")
        print("Active:    \(active)")
        print("Completed: \(completed)")
        print("Failed:    \(failed)")

        if active > 0 || pending > 0 {
            print("")
            print("Progress:  \(String(format: "%.1f", progress))%")
        }
    }
}

// MARK: - Upload Command

struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload a file or folder"
    )

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Path to file or folder to upload")
    var path: String

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        // Expand path
        let expandedPath = (path as NSString).expandingTildeInPath
        let absolutePath = (expandedPath as NSString).standardizingPath

        // Check file exists
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            print("Error: File not found: \(absolutePath)")
            throw ExitCode.failure
        }

        let command = CLICommand(
            command: CLICommands.upload,
            args: ["path": AnyCodable(absolutePath)]
        )

        let response = try await client.send(command: command)
        await client.disconnect()

        if !response.success {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }

        if options.format == .json {
            let jsonData = try JSONEncoder().encode(response.data)
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
        } else {
            let added = (response.data?["added"]?.value as? Int) ?? 0
            let failed = (response.data?["failed"]?.value as? Int) ?? 0

            print("Added \(added) file(s) to upload queue")
            if failed > 0 {
                print("\(failed) file(s) failed to process")
            }
        }
    }
}

// MARK: - List Command

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List queued and active uploads"
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        let response = try await client.send(command: CLICommand(command: CLICommands.list))
        await client.disconnect()

        if !response.success {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }

        if options.format == .json {
            let jsonData = try JSONEncoder().encode(response.data)
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
        } else {
            printJobs(response.data)
        }
    }

    private func printJobs(_ data: [String: AnyCodable]?) {
        guard let data = data,
              let jobs = data["jobs"]?.value as? [[String: Any]] else {
            print("No jobs in queue")
            return
        }

        if jobs.isEmpty {
            print("No jobs in queue")
            return
        }

        print("=== Upload Queue ===")
        print("")

        for job in jobs {
            let name = job["name"] as? String ?? "Unknown"
            let status = job["status"] as? String ?? "Unknown"
            let progress = job["progress"] as? Double ?? 0.0
            let id = job["id"] as? String ?? ""

            let statusIcon: String
            switch status {
            case "Uploading": statusIcon = "\u{1F7E2}"
            case "Pending": statusIcon = "\u{26AA}"
            case "Paused": statusIcon = "\u{1F7E1}"
            case "Completed": statusIcon = "\u{2705}"
            case "Failed": statusIcon = "\u{274C}"
            default: statusIcon = "\u{2753}"
            }

            print("\(statusIcon) \(name)")
            print("   Status: \(status)")
            if status == "Uploading" {
                print("   Progress: \(String(format: "%.1f", progress))%")
            }
            print("   ID: \(id)")
            print("")
        }
    }
}

// MARK: - Pause Command

struct Pause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pause all uploads"
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        let response = try await client.send(command: CLICommand(command: CLICommands.pause))
        await client.disconnect()

        if response.success {
            print("Uploads paused")
        } else {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }
    }
}

// MARK: - Resume Command

struct Resume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Resume paused uploads"
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        let response = try await client.send(command: CLICommand(command: CLICommands.resume))
        await client.disconnect()

        if response.success {
            print("Uploads resumed")
        } else {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }
    }
}

// MARK: - Cancel Command

struct Cancel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Cancel uploads"
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "ID of specific upload to cancel")
    var id: String?

    @Flag(name: .long, help: "Cancel all uploads")
    var all: Bool = false

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        var args: [String: AnyCodable]? = nil
        if let id = id {
            args = ["id": AnyCodable(id)]
        }

        let response = try await client.send(command: CLICommand(command: CLICommands.cancel, args: args))
        await client.disconnect()

        if response.success {
            if id != nil {
                print("Upload cancelled")
            } else {
                print("All uploads cancelled")
            }
        } else {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }
    }
}

// MARK: - History Command

struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show upload history"
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "Number of items to show")
    var limit: Int = 10

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        let command = CLICommand(
            command: CLICommands.history,
            args: ["limit": AnyCodable(limit)]
        )

        let response = try await client.send(command: command)
        await client.disconnect()

        if !response.success {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }

        if options.format == .json {
            let jsonData = try JSONEncoder().encode(response.data)
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
        } else {
            printHistory(response.data)
        }
    }

    private func printHistory(_ data: [String: AnyCodable]?) {
        guard let data = data,
              let history = data["history"]?.value as? [[String: Any]] else {
            print("No upload history")
            return
        }

        if history.isEmpty {
            print("No upload history")
            return
        }

        print("=== Upload History ===")
        print("")

        for item in history {
            let name = item["name"] as? String ?? "Unknown"
            let status = item["status"] as? String ?? "Unknown"
            let s3uri = item["s3uri"] as? String ?? ""
            let date = item["date"] as? String ?? ""

            let statusIcon = status == "Completed" ? "\u{2705}" : "\u{274C}"

            print("\(statusIcon) \(name)")
            print("   Date: \(date)")
            print("   S3: \(s3uri)")
            print("")
        }
    }
}

// MARK: - Config Command

struct Config: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage workflow configurations"
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Set active workflow by ID")
    var setWorkflow: String?

    func run() async throws {
        let client = CLIClient()

        do {
            try await client.connect(port: options.port)
        } catch {
            print("Error: \(CLIError.appNotRunning.errorDescription ?? "App not running")")
            throw ExitCode.failure
        }

        var args: [String: AnyCodable]? = nil
        if let workflowId = setWorkflow {
            args = ["workflow": AnyCodable(workflowId)]
        }

        let command = CLICommand(command: CLICommands.config, args: args)
        let response = try await client.send(command: command)
        await client.disconnect()

        if !response.success {
            print("Error: \(response.error ?? "Unknown error")")
            throw ExitCode.failure
        }

        if setWorkflow != nil {
            print("Workflow updated")
        } else if options.format == .json {
            let jsonData = try JSONEncoder().encode(response.data)
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
        } else {
            printWorkflows(response.data)
        }
    }

    private func printWorkflows(_ data: [String: AnyCodable]?) {
        guard let data = data,
              let workflows = data["workflows"]?.value as? [[String: Any]] else {
            print("No workflows configured")
            return
        }

        print("=== Workflows ===")
        print("")

        for workflow in workflows {
            let name = workflow["name"] as? String ?? "Unknown"
            let bucket = workflow["bucket"] as? String ?? ""
            let id = workflow["id"] as? String ?? ""
            let active = workflow["active"] as? Bool ?? false

            let activeIndicator = active ? " [ACTIVE]" : ""

            print("\(name)\(activeIndicator)")
            print("   Bucket: \(bucket)")
            print("   ID: \(id)")
            print("")
        }
    }
}

// MARK: - Server Command (Standalone mode)

struct Server: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run ShotDropper in headless server mode (without GUI)"
    )

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: UInt16 = 9847

    @Option(name: .long, help: "AWS profile to use")
    var profile: String = "default"

    func run() async throws {
        print("Starting ShotDropper server on port \(port)...")

        let services = ServiceContainer()

        do {
            try await services.initialize()
            try await services.startCLIServer(port: port)

            print("Server running. Press Ctrl+C to stop.")

            // Keep running forever
            while true {
                try await Task.sleep(for: .seconds(3600))
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
