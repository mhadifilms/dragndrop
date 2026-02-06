import Foundation
import Logging

// MARK: - Upload Manager

/// Orchestrates the upload process, managing queue and parallel uploads
public actor UploadManager {
    private let logger = Logger(label: "com.dragndrop.upload.manager")

    private let authService: AWSAuthenticationService
    private let uploadService: S3UploadService
    private let extractionService: FileExtractionService
    private let historyStore: UploadHistoryStore

    // State
    private var pendingJobs: [UploadJob] = []
    private var activeJobs: [UUID: UploadJob] = [:]
    private var completedJobs: [UploadJob] = []
    private var failedJobs: [UploadJob] = []

    // Settings
    private var maxConcurrent: Int = 4
    private var isRunning: Bool = false
    private var isPaused: Bool = false

    // Pre-processing
    private var enablePreProcessing: Bool = false
    private var preProcessingScript: String = ""
    private var bundledToolsPath: String?

    // Skills
    private var skillManager: SkillManager?
    private var skillExecutor: SkillExecutor?
    private var enableSkills: Bool = false

    // Retry settings
    private var maxRetryAttempts: Int = 3
    private var baseRetryDelaySeconds: Double = 5.0
    private var maxRetryDelaySeconds: Double = 300.0  // 5 minutes max
    private var retryJitter: Double = 0.1  // 10% jitter

    // Progress tracking
    private var progressCallbacks: [UUID: @Sendable (UploadProgress) -> Void] = [:]
    private var statusCallback: (@Sendable (UploadManagerStatus) -> Void)?

    public init(
        authService: AWSAuthenticationService,
        uploadService: S3UploadService,
        extractionService: FileExtractionService,
        historyStore: UploadHistoryStore
    ) {
        self.authService = authService
        self.uploadService = uploadService
        self.extractionService = extractionService
        self.historyStore = historyStore
    }

    // MARK: - Configuration

    public func configure(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    public func configure(settings: UploadSettings) {
        self.maxConcurrent = settings.maxConcurrentUploads
        self.maxRetryAttempts = settings.retryCount
        self.baseRetryDelaySeconds = Double(settings.retryDelaySeconds)
    }

    /// Configures pre-processing script
    public func configurePreProcessing(enabled: Bool, script: String, toolsPath: String?) {
        self.enablePreProcessing = enabled
        self.preProcessingScript = script
        self.bundledToolsPath = toolsPath
    }

    /// Configures skills execution
    public func configureSkills(enabled: Bool, manager: SkillManager, executor: SkillExecutor) {
        self.enableSkills = enabled
        self.skillManager = manager
        self.skillExecutor = executor
    }

    /// Updates the skills enabled state
    public func setSkillsEnabled(_ enabled: Bool) {
        self.enableSkills = enabled
    }

    /// Runs the pre-processing script on a file
    private func runPreProcessingScript(job: UploadJob) async throws {
        guard enablePreProcessing, !preProcessingScript.isEmpty else { return }

        let filePath = job.sourceURL.path
        let filename = job.sourceURL.lastPathComponent
        let destination = job.destinationPath

        logger.info("Running pre-processing script for: \(filename)")

        // Write script to temp file
        let scriptPath = FileManager.default.temporaryDirectory.appendingPathComponent("dragndrop_preprocess_\(UUID().uuidString).sh")
        try preProcessingScript.write(to: scriptPath, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: scriptPath)
        }

        // Build environment
        var environment = ProcessInfo.processInfo.environment
        environment["INPUT_FILE"] = filePath
        environment["FILENAME"] = filename
        environment["DESTINATION"] = destination

        // Add bundled tools to PATH if available
        if let toolsPath = bundledToolsPath {
            let currentPath = environment["PATH"] ?? "/usr/bin:/bin"
            environment["PATH"] = "\(toolsPath):\(currentPath)"
            environment["FFMPEG"] = "\(toolsPath)/ffmpeg"
            environment["FFPROBE"] = "\(toolsPath)/ffprobe"
        }

        // Run script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath.path]
        process.environment = environment
        process.currentDirectoryURL = job.sourceURL.deletingLastPathComponent()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            logger.info("Pre-processing output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if process.terminationStatus != 0 {
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.warning("Pre-processing script exited with status \(process.terminationStatus): \(errorOutput)")
            // Don't fail the upload, just log the warning
        }
    }

    /// Runs skills for a job and returns companion files
    private func runSkillsForJob(job: inout UploadJob) async -> [CompanionFile] {
        guard let skillManager = skillManager,
              let skillExecutor = skillExecutor else {
            return []
        }

        // Get enabled skills applicable to this file
        let fileExtension = job.sourceURL.pathExtension
        let applicableSkills = await skillManager.getApplicable(forExtension: fileExtension)

        guard !applicableSkills.isEmpty else {
            job.skillStatus = .skipped
            return []
        }

        logger.info("Running \(applicableSkills.count) skills for: \(job.displayName)")

        // Update job status with total count
        job.skillStatus = .running(currentSkill: applicableSkills.first?.name ?? "", completed: 0, total: applicableSkills.count)
        activeJobs[job.id] = job
        notifyStatusChange()

        // Set bundled tools path
        if let toolsPath = bundledToolsPath {
            await skillExecutor.setBundledToolsPath(toolsPath)
        }

        let jobId = job.id
        let totalSkills = applicableSkills.count

        // Execute skills in parallel
        let companionFiles = await skillExecutor.executeSkills(
            applicableSkills,
            for: job.sourceURL
        ) { [weak self] skill, status in
            self?.logger.debug("Skill '\(skill.name)' \(status)")
        }

        logger.info("Generated \(companionFiles.count) companion files for: \(job.displayName)")
        return companionFiles
    }

    /// Uploads companion files to the same S3 path as the main file
    private func uploadCompanionFiles(for job: UploadJob) async {
        guard !job.companionFiles.isEmpty else { return }

        let basePath = (job.destinationPath as NSString).deletingLastPathComponent

        for companion in job.companionFiles {
            let companionKey = basePath.isEmpty
                ? companion.filename
                : "\(basePath)/\(companion.filename)"

            logger.info("Uploading companion file: \(companion.filename) -> \(companionKey)")

            do {
                // Create a simple job for the companion file
                var companionJob = UploadJob.simple(
                    url: companion.url,
                    bucket: job.bucket,
                    key: companionKey,
                    region: job.region
                )

                try await uploadService.uploadFile(job: &companionJob) { _ in }
                logger.info("Companion file uploaded: \(companion.filename)")
            } catch {
                // Log error but don't fail the main upload
                logger.warning("Failed to upload companion file \(companion.filename): \(error.localizedDescription)")
            }
        }
    }

    /// Calculates exponential backoff delay with jitter
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: baseDelay * 2^attempt
        let exponentialDelay = baseRetryDelaySeconds * pow(2.0, Double(attempt - 1))
        let clampedDelay = min(exponentialDelay, maxRetryDelaySeconds)

        // Add jitter to prevent thundering herd
        let jitterRange = clampedDelay * retryJitter
        let jitter = Double.random(in: -jitterRange...jitterRange)

        return max(1.0, clampedDelay + jitter)
    }

    public func setStatusCallback(_ callback: @escaping @Sendable (UploadManagerStatus) -> Void) {
        self.statusCallback = callback
    }

    // MARK: - Job Management

    /// Adds files to the upload queue after processing
    public func addFiles(
        urls: [URL],
        workflow: WorkflowConfiguration,
        settings: AppSettings? = nil
    ) async throws -> [ProcessedItem] {
        let processed = try await extractionService.processFiles(urls: urls, workflow: workflow, settings: settings)

        for item in processed {
            if let job = item.job {
                pendingJobs.append(job)
                logger.info("Added job to queue: \(job.displayName) -> \(job.destinationPath)")
            }
        }

        notifyStatusChange()
        return processed
    }

    /// Adds a pre-configured job to the queue
    public func addJob(_ job: UploadJob) {
        pendingJobs.append(job)
        notifyStatusChange()
    }

    /// Removes a pending job from the queue
    public func removeJob(id: UUID) {
        pendingJobs.removeAll { $0.id == id }
        notifyStatusChange()
    }

    /// Clears all pending jobs
    public func clearQueue() {
        pendingJobs.removeAll()
        notifyStatusChange()
    }

    /// Gets all pending jobs
    public func getPendingJobs() -> [UploadJob] {
        return pendingJobs
    }

    /// Gets all active jobs
    public func getActiveJobs() -> [UploadJob] {
        return Array(activeJobs.values)
    }

    /// Gets all completed jobs
    public func getCompletedJobs() -> [UploadJob] {
        return completedJobs
    }

    /// Gets all failed jobs
    public func getFailedJobs() -> [UploadJob] {
        return failedJobs
    }

    // MARK: - Upload Control

    /// Starts processing the upload queue
    public func start() async {
        guard !isRunning else { return }

        isRunning = true
        isPaused = false
        logger.info("Upload manager started")

        await processQueue()
    }

    /// Pauses all uploads
    public func pause() {
        isPaused = true
        logger.info("Upload manager paused")
        notifyStatusChange()
    }

    /// Resumes paused uploads
    public func resume() async {
        isPaused = false
        logger.info("Upload manager resumed")
        await processQueue()
    }

    /// Stops all uploads and clears the queue
    public func stop() async {
        isRunning = false
        isPaused = false

        // Cancel active uploads
        for (_, var job) in activeJobs {
            try? await uploadService.cancelUpload(job: &job)
            job.status = .cancelled
            failedJobs.append(job)
        }

        activeJobs.removeAll()
        logger.info("Upload manager stopped")
        notifyStatusChange()
    }

    /// Cancels a specific upload
    public func cancelJob(id: UUID) async {
        if var job = activeJobs[id] {
            try? await uploadService.cancelUpload(job: &job)
            job.status = .cancelled
            failedJobs.append(job)
            activeJobs.removeValue(forKey: id)
            notifyStatusChange()
        } else {
            removeJob(id: id)
        }
    }

    /// Retries a failed job (manual retry)
    public func retryJob(id: UUID) async {
        guard let index = failedJobs.firstIndex(where: { $0.id == id }) else { return }

        var job = failedJobs.remove(at: index)

        // Reset job for retry but keep retry history
        job.resetForRetry()

        pendingJobs.append(job)
        notifyStatusChange()

        if isRunning && !isPaused {
            await processQueue()
        }
    }

    /// Retries a failed job with reset of all retry counters (fresh start)
    public func retryJobFresh(id: UUID) async {
        guard let index = failedJobs.firstIndex(where: { $0.id == id }) else { return }

        var job = failedJobs.remove(at: index)

        // Full reset including retry counters
        job.status = .pending
        job.error = nil
        job.progress = UploadProgress(totalBytes: job.progress.totalBytes)
        job.completedParts = []
        job.uploadId = nil
        job.retryAttempts = 0
        job.lastRetryAt = nil
        job.retryErrors = []

        pendingJobs.append(job)
        notifyStatusChange()

        if isRunning && !isPaused {
            await processQueue()
        }
    }

    /// Retries all failed jobs
    public func retryAllFailed() async {
        let jobsToRetry = failedJobs
        failedJobs.removeAll()

        for var job in jobsToRetry {
            job.resetForRetry()
            pendingJobs.append(job)
        }

        notifyStatusChange()

        if isRunning && !isPaused {
            await processQueue()
        }
    }

    // MARK: - Queue Processing

    private func processQueue() async {
        guard isRunning && !isPaused else { return }

        while !pendingJobs.isEmpty && activeJobs.count < maxConcurrent && !isPaused {
            let job = pendingJobs.removeFirst()
            activeJobs[job.id] = job

            Task {
                await processJob(id: job.id)
            }
        }
    }

    private func processJob(id: UUID) async {
        guard var job = activeJobs[id] else { return }

        let attemptNumber = job.retryAttempts + 1
        logger.info("Starting upload: \(job.displayName) (attempt \(attemptNumber))")

        do {
            // Configure upload service with credentials
            if let creds = await authService.credentials {
                try await uploadService.configure(
                    credentials: creds,
                    region: job.region,
                    settings: UploadSettings()
                )
            } else {
                throw UploadError.authenticationError("Not authenticated")
            }

            // Run pre-processing script if enabled (only on first attempt)
            if job.retryAttempts == 0 {
                try await runPreProcessingScript(job: job)
            }

            // Run skills if enabled (only on first attempt, and not for sequences)
            if job.retryAttempts == 0 && enableSkills && !job.fileInfo.isSequence {
                job.skillStatus = .running(currentSkill: "Preparing", completed: 0, total: 0)
                activeJobs[id] = job
                notifyStatusChange()

                job.companionFiles = await runSkillsForJob(job: &job)
                job.skillStatus = .completed(count: job.companionFiles.count)
                activeJobs[id] = job
                notifyStatusChange()
            }

            // Check if this is a sequence
            if job.fileInfo.isSequence {
                try await uploadService.uploadSequence(job: &job) { [weak self] progress in
                    Task { [weak self] in
                        await self?.updateJobProgress(id: id, progress: progress)
                    }
                }
            } else {
                try await uploadService.uploadFile(job: &job) { [weak self] progress in
                    Task { [weak self] in
                        await self?.updateJobProgress(id: id, progress: progress)
                    }
                }
            }

            // Upload companion files if any
            if !job.companionFiles.isEmpty {
                await uploadCompanionFiles(for: job)
            }

            // Success
            activeJobs.removeValue(forKey: id)
            completedJobs.append(job)

            // Clean up companion files
            if let executor = skillExecutor {
                for companion in job.companionFiles {
                    await executor.cleanupCompanionFile(companion)
                }
            }

            // Add to history
            let historyItem = UploadHistoryItem.from(job: job)
            await historyStore.add(historyItem)

            logger.info("Upload completed: \(job.displayName) with \(job.companionFiles.count) companion files")

        } catch {
            let uploadError = mapToUploadError(error)

            // Check if we should retry
            if uploadError.isRetryable && job.retryAttempts < maxRetryAttempts {
                job.markForRetry(error: uploadError)
                activeJobs.removeValue(forKey: id)

                let delay = calculateRetryDelay(attempt: job.retryAttempts)
                logger.warning("Upload failed (attempt \(attemptNumber)): \(job.displayName) - \(error.localizedDescription). Retrying in \(String(format: "%.1f", delay))s")

                // Schedule retry with exponential backoff
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await self.scheduleRetry(job: job)
                }
            } else {
                // Max retries exceeded or non-retryable error
                job.markFailed(uploadError)
                activeJobs.removeValue(forKey: id)
                failedJobs.append(job)

                if job.retryAttempts >= maxRetryAttempts {
                    logger.error("Upload permanently failed after \(job.retryAttempts) retries: \(job.displayName) - \(error.localizedDescription)")
                } else {
                    logger.error("Upload failed (non-retryable): \(job.displayName) - \(error.localizedDescription)")
                }

                // Add to history as failed
                let historyItem = UploadHistoryItem.from(job: job)
                await historyStore.add(historyItem)
            }
        }

        notifyStatusChange()

        // Process more jobs
        if isRunning && !isPaused {
            await processQueue()
        }

        // Check if all done
        if activeJobs.isEmpty && pendingJobs.isEmpty {
            isRunning = false
            logger.info("All uploads completed")
        }
    }

    /// Schedules a job for retry, adding it back to the pending queue
    private func scheduleRetry(job: UploadJob) async {
        guard isRunning && !isPaused else {
            // If paused, add to pending for later
            pendingJobs.append(job)
            notifyStatusChange()
            return
        }

        pendingJobs.append(job)
        notifyStatusChange()
        await processQueue()
    }

    /// Maps generic errors to UploadError
    private func mapToUploadError(_ error: Error) -> UploadError {
        if let uploadError = error as? UploadError {
            return uploadError
        }

        let description = error.localizedDescription.lowercased()

        // Network-related errors (retryable)
        if description.contains("network") ||
           description.contains("connection") ||
           description.contains("timeout") ||
           description.contains("timed out") ||
           description.contains("internet") ||
           description.contains("offline") ||
           description.contains("socket") ||
           description.contains("dns") {
            return .networkError(error.localizedDescription)
        }

        // AWS throttling/rate limiting (retryable)
        if description.contains("throttl") ||
           description.contains("rate") ||
           description.contains("slow down") ||
           description.contains("503") ||
           description.contains("service unavailable") ||
           description.contains("500") ||
           description.contains("internal server error") ||
           description.contains("502") ||
           description.contains("bad gateway") ||
           description.contains("504") ||
           description.contains("gateway timeout") {
            return .networkError(error.localizedDescription)
        }

        // Authentication errors (not retryable)
        if description.contains("auth") ||
           description.contains("credential") ||
           description.contains("401") ||
           description.contains("403") ||
           description.contains("forbidden") ||
           description.contains("access denied") {
            return .authenticationError(error.localizedDescription)
        }

        // Bucket/key errors (not retryable)
        if description.contains("bucket") ||
           description.contains("nosuchbucket") ||
           description.contains("404") ||
           description.contains("not found") {
            return .bucketNotFound(error.localizedDescription)
        }

        return .unknown(error.localizedDescription)
    }

    private func updateJobProgress(id: UUID, progress: UploadProgress) {
        if var job = activeJobs[id] {
            job.progress = progress
            activeJobs[id] = job
        }
        progressCallbacks[id]?(progress)
        notifyStatusChange()
    }

    // MARK: - Progress Tracking

    public func onProgress(jobId: UUID, callback: @escaping @Sendable (UploadProgress) -> Void) {
        progressCallbacks[jobId] = callback
    }

    public func removeProgressCallback(jobId: UUID) {
        progressCallbacks.removeValue(forKey: jobId)
    }

    // MARK: - Status

    public func getStatus() -> UploadManagerStatus {
        let activeProgress = activeJobs.values.map { $0.progress }
        let totalBytes = activeProgress.reduce(0) { $0 + $1.totalBytes }
        let uploadedBytes = activeProgress.reduce(0) { $0 + $1.bytesUploaded }

        return UploadManagerStatus(
            isRunning: isRunning,
            isPaused: isPaused,
            pendingCount: pendingJobs.count,
            activeCount: activeJobs.count,
            completedCount: completedJobs.count,
            failedCount: failedJobs.count,
            totalBytes: totalBytes,
            uploadedBytes: uploadedBytes,
            activeJobs: Array(activeJobs.values)
        )
    }

    private func notifyStatusChange() {
        statusCallback?(getStatus())
    }

    // MARK: - Utilities

    /// Gets presigned URL for a completed job
    public func getPresignedURL(jobId: UUID) async throws -> String? {
        if let job = completedJobs.first(where: { $0.id == jobId }) {
            return try await uploadService.generatePresignedURL(
                bucket: job.bucket,
                key: job.destinationPath,
                expiresIn: 3600
            )
        }
        return nil
    }

    /// Gets the AWS Console URL for a job
    public func getConsoleURL(jobId: UUID) -> URL? {
        let allJobs = pendingJobs + Array(activeJobs.values) + completedJobs + failedJobs
        return allJobs.first(where: { $0.id == jobId })?.awsConsoleURL
    }

    /// Gets S3 URI for a job
    public func getS3URI(jobId: UUID) -> String? {
        let allJobs = pendingJobs + Array(activeJobs.values) + completedJobs + failedJobs
        return allJobs.first(where: { $0.id == jobId })?.fullS3Path
    }

    /// Verifies credentials work by listing S3 buckets
    public func verifyCredentials(region: String = "us-east-1") async throws {
        // Make sure upload service is configured with current credentials
        if let creds = authService.credentials {
            try await uploadService.configure(
                credentials: creds,
                region: region,
                settings: UploadSettings()
            )
        }
        try await uploadService.verifyAccess()
    }
}

// MARK: - Upload Manager Status

public struct UploadManagerStatus: Sendable {
    public let isRunning: Bool
    public let isPaused: Bool
    public let pendingCount: Int
    public let activeCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let totalBytes: Int64
    public let uploadedBytes: Int64
    public let activeJobs: [UploadJob]

    public var overallProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(uploadedBytes) / Double(totalBytes) * 100.0
    }

    public var totalCount: Int {
        pendingCount + activeCount + completedCount + failedCount
    }

    public var hasActiveUploads: Bool {
        activeCount > 0 || pendingCount > 0
    }

    public var statusText: String {
        if !isRunning && totalCount == 0 {
            return "Ready"
        } else if isPaused {
            return "Paused - \(activeCount + pendingCount) uploads pending"
        } else if isRunning {
            if activeCount > 0 {
                return "Uploading \(activeCount) file\(activeCount == 1 ? "" : "s")..."
            } else {
                return "Processing..."
            }
        } else if completedCount > 0 && failedCount == 0 {
            return "\(completedCount) upload\(completedCount == 1 ? "" : "s") completed"
        } else if failedCount > 0 {
            return "\(failedCount) failed, \(completedCount) completed"
        }
        return "Ready"
    }

    public var menuBarIcon: String {
        if isRunning && activeCount > 0 {
            return "arrow.up.circle.fill"
        } else if isPaused {
            return "pause.circle.fill"
        } else if failedCount > 0 {
            return "exclamationmark.circle.fill"
        } else if completedCount > 0 {
            return "checkmark.circle.fill"
        }
        return "tray.and.arrow.up"
    }
}
