// ShotDropperCore - Core library for ShotDropper app
// Provides all business logic, services, and models

@_exported import Foundation
@_exported import Logging

// MARK: - Models
// Re-export all model types
public typealias Workflow = WorkflowConfiguration
public typealias Job = UploadJob

// MARK: - Service Container

/// Central container for all app services
public actor ServiceContainer {
    public let authService: AWSAuthenticationService
    public let uploadService: S3UploadService
    public let extractionService: FileExtractionService
    public let workflowManager: WorkflowConfigurationManager
    public let uploadManager: UploadManager
    public let historyStore: UploadHistoryStore
    public let notificationService: NotificationService
    public let cliServer: CLIServerService

    public init() {
        self.authService = AWSAuthenticationService()
        self.uploadService = S3UploadService()
        self.extractionService = FileExtractionService()
        self.workflowManager = WorkflowConfigurationManager()
        self.historyStore = UploadHistoryStore()
        self.notificationService = NotificationService()
        self.cliServer = CLIServerService()

        self.uploadManager = UploadManager(
            authService: authService,
            uploadService: uploadService,
            extractionService: extractionService,
            historyStore: historyStore
        )
    }

    /// Initializes all services
    public func initialize() async throws {
        // Load workflows
        try await workflowManager.loadAll()

        // Load history
        await historyStore.load()

        // Setup notifications
        await notificationService.setupCategories()
        _ = try? await notificationService.requestAuthorization()

        // Setup CLI server command handler
        await cliServer.setCommandHandler { [weak self] command in
            await self?.handleCLICommand(command) ?? CLIResponse(success: false, error: "Service unavailable", data: nil)
        }
    }

    /// Starts the CLI server
    public func startCLIServer(port: UInt16) async throws {
        try await cliServer.start(port: port)
    }

    /// Stops the CLI server
    public func stopCLIServer() async {
        await cliServer.stop()
    }

    // MARK: - CLI Command Handler

    private func handleCLICommand(_ command: CLICommand) async -> CLIResponse {
        switch command.command {
        case CLICommands.status:
            let status = await uploadManager.getStatus()
            return CLIResponse(
                success: true,
                error: nil,
                data: [
                    "isRunning": AnyCodable(status.isRunning),
                    "isPaused": AnyCodable(status.isPaused),
                    "pending": AnyCodable(status.pendingCount),
                    "active": AnyCodable(status.activeCount),
                    "completed": AnyCodable(status.completedCount),
                    "failed": AnyCodable(status.failedCount),
                    "progress": AnyCodable(status.overallProgress)
                ]
            )

        case CLICommands.upload:
            guard let pathArg = command.args?["path"],
                  let path = pathArg.value as? String else {
                return CLIResponse(success: false, error: "Missing path argument", data: nil)
            }

            let url = URL(fileURLWithPath: path)
            guard let workflow = await workflowManager.getActive() else {
                return CLIResponse(success: false, error: "No active workflow", data: nil)
            }

            do {
                let processed = try await uploadManager.addFiles(urls: [url], workflow: workflow)
                await uploadManager.start()

                return CLIResponse(
                    success: true,
                    error: nil,
                    data: [
                        "added": AnyCodable(processed.filter { $0.isSuccess }.count),
                        "failed": AnyCodable(processed.filter { !$0.isSuccess }.count)
                    ]
                )
            } catch {
                return CLIResponse(success: false, error: error.localizedDescription, data: nil)
            }

        case CLICommands.pause:
            await uploadManager.pause()
            return CLIResponse(success: true, error: nil, data: nil)

        case CLICommands.resume:
            await uploadManager.resume()
            return CLIResponse(success: true, error: nil, data: nil)

        case CLICommands.cancel:
            if let idArg = command.args?["id"],
               let idString = idArg.value as? String,
               let id = UUID(uuidString: idString) {
                await uploadManager.cancelJob(id: id)
            } else {
                await uploadManager.stop()
            }
            return CLIResponse(success: true, error: nil, data: nil)

        case CLICommands.list:
            let pending = await uploadManager.getPendingJobs()
            let active = await uploadManager.getActiveJobs()

            let jobs = (pending + active).map { job -> [String: Any] in
                [
                    "id": job.id.uuidString,
                    "name": job.displayName,
                    "status": job.status.rawValue,
                    "progress": job.progress.percentage,
                    "destination": job.destinationPath
                ]
            }

            return CLIResponse(
                success: true,
                error: nil,
                data: ["jobs": AnyCodable(jobs)]
            )

        case CLICommands.history:
            let limit = (command.args?["limit"]?.value as? Int) ?? 10
            let items = await historyStore.getRecent(limit)

            let history = items.map { item -> [String: Any] in
                [
                    "id": item.id.uuidString,
                    "name": item.filename,
                    "status": item.status.rawValue,
                    "s3uri": item.s3URI,
                    "date": ISO8601DateFormatter().string(from: item.startedAt)
                ]
            }

            return CLIResponse(
                success: true,
                error: nil,
                data: ["history": AnyCodable(history)]
            )

        case CLICommands.config:
            if let workflowId = command.args?["workflow"]?.value as? String,
               let id = UUID(uuidString: workflowId) {
                do {
                    try await workflowManager.setActive(id: id)
                    return CLIResponse(success: true, error: nil, data: nil)
                } catch {
                    return CLIResponse(success: false, error: error.localizedDescription, data: nil)
                }
            }

            let workflows = await workflowManager.getAll()
            let active = await workflowManager.getActive()

            let workflowList = workflows.map { w -> [String: Any] in
                [
                    "id": w.id.uuidString,
                    "name": w.name,
                    "bucket": w.bucket,
                    "active": w.id == active?.id
                ]
            }

            return CLIResponse(
                success: true,
                error: nil,
                data: ["workflows": AnyCodable(workflowList)]
            )

        case CLICommands.auth:
            let isAuth = await authService.isAuthenticated
            return CLIResponse(
                success: true,
                error: nil,
                data: ["authenticated": AnyCodable(isAuth)]
            )

        case CLICommands.quit:
            // Signal app to quit (handled by app delegate)
            return CLIResponse(
                success: true,
                error: nil,
                data: ["action": AnyCodable("quit")]
            )

        default:
            return CLIResponse(
                success: false,
                error: "Unknown command: \(command.command)",
                data: nil
            )
        }
    }
}

// MARK: - Convenience Extensions

extension UploadJob {
    /// Creates a simple upload job for direct upload
    public static func simple(
        url: URL,
        bucket: String,
        key: String,
        region: String = "us-east-1"
    ) -> UploadJob {
        let fileInfo = FileInfo.from(url: url)
        return UploadJob(
            sourceURL: url,
            destinationPath: key,
            bucket: bucket,
            region: region,
            fileInfo: fileInfo
        )
    }
}
