import Foundation
import Logging
import AWSS3
import AWSClientRuntime
import SmithyIdentity

// MARK: - S3 Upload Service

/// Manages file uploads to S3 with multipart upload support
public final class S3UploadService: @unchecked Sendable {
    private let logger = Logger(label: "com.dragndrop.s3.upload")

    private var s3Client: S3Client?
    private let lock = NSLock()
    private var credentials: AWSCredentials?
    private var region: String = "us-east-1"

    // Active uploads tracking
    private var activeUploads: [UUID: ActiveUpload] = [:]
    private var uploadQueue: [UploadJob] = []

    // Settings
    private var maxConcurrent: Int = 4
    private var multipartThreshold: Int64 = 16 * 1024 * 1024  // 16 MB
    private var partSize: Int64 = 8 * 1024 * 1024  // 8 MB

    // Bandwidth throttling
    private let bandwidthThrottler = BandwidthThrottler()
    private let bandwidthMonitor = BandwidthMonitor()
    private var uploadSettings: UploadSettings = UploadSettings()

    public init() {}

    // MARK: - Configuration

    public func configure(
        credentials: AWSCredentials,
        region: String,
        settings: UploadSettings
    ) async throws {
        self.credentials = credentials
        self.region = region
        self.maxConcurrent = settings.maxConcurrentUploads
        self.multipartThreshold = Int64(settings.multipartThresholdMB) * 1024 * 1024
        self.partSize = Int64(settings.partSizeMB) * 1024 * 1024
        self.uploadSettings = settings

        // Configure bandwidth throttling
        await configureBandwidthThrottling(settings: settings)

        let staticCreds = try StaticAWSCredentialIdentityResolver(
            AWSCredentialIdentity(
                accessKey: credentials.accessKeyId,
                secret: credentials.secretAccessKey,
                sessionToken: credentials.sessionToken
            )
        )

        let config = try await S3Client.S3ClientConfiguration(
            awsCredentialIdentityResolver: staticCreds,
            region: region
        )

        self.s3Client = S3Client(config: config)
        logger.info("S3 client configured for region \(region)")
    }

    /// Configures bandwidth throttling based on settings
    private func configureBandwidthThrottling(settings: UploadSettings) async {
        if settings.enableBandwidthThrottling {
            // Check for scheduled throttle rules first
            if let schedule = settings.throttleSchedule,
               let scheduledSpeed = schedule.currentSpeedLimitMBps() {
                await bandwidthThrottler.setLimit(mbps: scheduledSpeed)
                logger.info("Bandwidth throttling enabled (scheduled): \(scheduledSpeed) MB/s")
            } else if settings.maxUploadSpeedMBps > 0 {
                await bandwidthThrottler.setLimit(mbps: settings.maxUploadSpeedMBps)
                logger.info("Bandwidth throttling enabled: \(settings.maxUploadSpeedMBps) MB/s")
            } else {
                await bandwidthThrottler.disable()
            }
        } else {
            await bandwidthThrottler.disable()
            logger.info("Bandwidth throttling disabled")
        }
    }

    /// Updates bandwidth throttling settings dynamically
    public func updateBandwidthLimit(mbps: Double) async {
        if mbps > 0 {
            await bandwidthThrottler.setLimit(mbps: mbps)
        } else {
            await bandwidthThrottler.disable()
        }
    }

    /// Gets the current bandwidth limit
    public func getCurrentBandwidthLimit() async -> String {
        return await bandwidthThrottler.currentLimitFormatted
    }

    /// Gets the current measured upload speed
    public func getCurrentUploadSpeed() async -> String {
        return await bandwidthMonitor.currentSpeedFormatted
    }

    public func updateCredentials(_ credentials: AWSCredentials) async throws {
        try await configure(credentials: credentials, region: region, settings: UploadSettings(
            maxConcurrentUploads: maxConcurrent,
            multipartThresholdMB: Int(multipartThreshold / 1024 / 1024),
            partSizeMB: Int(partSize / 1024 / 1024)
        ))
    }

    // MARK: - Single File Upload

    /// Uploads a single file, automatically choosing simple or multipart upload
    public func uploadFile(
        job: inout UploadJob,
        progressHandler: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        job.markStarted()

        let fileSize = job.fileInfo.size

        if fileSize > multipartThreshold {
            try await performMultipartUpload(
                job: &job,
                client: client,
                progressHandler: progressHandler
            )
        } else {
            try await performSimpleUpload(
                job: &job,
                client: client,
                progressHandler: progressHandler
            )
        }
    }

    // MARK: - Simple Upload

    private func performSimpleUpload(
        job: inout UploadJob,
        client: S3Client,
        progressHandler: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        logger.info("Starting simple upload: \(job.displayName) -> \(job.destinationPath)")

        let data = try Data(contentsOf: job.sourceURL)
        let totalSize = Int64(data.count)

        // Apply bandwidth throttling if enabled
        let isThrottled = await bandwidthThrottler.isEnabled

        if isThrottled {
            // For throttled uploads, use chunked approach
            try await performThrottledSimpleUpload(
                job: &job,
                client: client,
                data: data,
                progressHandler: progressHandler
            )
        } else {
            // Non-throttled direct upload
            let input = PutObjectInput(
                body: .data(data),
                bucket: job.bucket,
                contentLength: data.count,
                key: job.destinationPath
            )

            _ = try await client.putObject(input: input)

            job.progress = UploadProgress(
                bytesUploaded: totalSize,
                totalBytes: totalSize,
                percentage: 100.0
            )
            progressHandler(job.progress)
        }

        // Record bandwidth for monitoring
        await bandwidthMonitor.recordBytes(totalSize)

        // Generate presigned URL
        let presignedURL = try await generatePresignedURL(
            bucket: job.bucket,
            key: job.destinationPath,
            expiresIn: 3600
        )

        job.markCompleted(presignedURL: presignedURL)
        logger.info("Simple upload completed: \(job.displayName)")
    }

    /// Performs a throttled simple upload by chunking the data
    private func performThrottledSimpleUpload(
        job: inout UploadJob,
        client: S3Client,
        data: Data,
        progressHandler: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        let totalSize = Int64(data.count)

        // For small files under throttled conditions, we still do a single put
        // but we throttle before sending
        await bandwidthThrottler.waitForBytes(totalSize)

        let input = PutObjectInput(
            body: .data(data),
            bucket: job.bucket,
            contentLength: data.count,
            key: job.destinationPath
        )

        _ = try await client.putObject(input: input)

        job.progress = UploadProgress(
            bytesUploaded: totalSize,
            totalBytes: totalSize,
            percentage: 100.0
        )
        progressHandler(job.progress)
    }

    // MARK: - Multipart Upload

    private func performMultipartUpload(
        job: inout UploadJob,
        client: S3Client,
        progressHandler: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        logger.info("Starting multipart upload: \(job.displayName) -> \(job.destinationPath)")

        let fileSize = job.fileInfo.size
        let totalParts = Int((fileSize + partSize - 1) / partSize)

        // Initiate multipart upload
        let createInput = CreateMultipartUploadInput(
            bucket: job.bucket,
            key: job.destinationPath
        )

        let createOutput = try await client.createMultipartUpload(input: createInput)

        guard let uploadId = createOutput.uploadId else {
            throw S3UploadError.multipartInitFailed
        }

        job.uploadId = uploadId
        job.progress.totalParts = totalParts

        logger.info("Multipart upload initiated with ID: \(uploadId), \(totalParts) parts")

        // Track this upload
        let activeUpload = ActiveUpload(
            jobId: job.id,
            uploadId: uploadId,
            bucket: job.bucket,
            key: job.destinationPath,
            totalParts: totalParts
        )
        activeUploads[job.id] = activeUpload

        // Read file handle
        let fileHandle = try FileHandle(forReadingFrom: job.sourceURL)
        defer { try? fileHandle.close() }

        var completedParts: [S3ClientTypes.CompletedPart] = []
        var uploadedBytes: Int64 = 0

        // Track upload speed
        var lastProgressTime = Date()
        var lastUploadedBytes: Int64 = 0

        // Upload parts sequentially (can be parallelized later)
        for partNumber in 1...totalParts {
            let offset = Int64(partNumber - 1) * partSize
            let remainingBytes = fileSize - offset
            let currentPartSize = min(partSize, remainingBytes)

            try fileHandle.seek(toOffset: UInt64(offset))
            guard let partData = try fileHandle.read(upToCount: Int(currentPartSize)) else {
                throw S3UploadError.readFailed
            }

            // Apply bandwidth throttling before uploading each part
            await bandwidthThrottler.waitForBytes(currentPartSize)

            let uploadPartInput = UploadPartInput(
                body: .data(partData),
                bucket: job.bucket,
                contentLength: Int(currentPartSize),
                key: job.destinationPath,
                partNumber: partNumber,
                uploadId: uploadId
            )

            let partOutput = try await client.uploadPart(input: uploadPartInput)

            guard let eTag = partOutput.eTag else {
                throw S3UploadError.partUploadFailed(partNumber)
            }

            completedParts.append(S3ClientTypes.CompletedPart(
                eTag: eTag,
                partNumber: partNumber
            ))

            job.completedParts.append(CompletedPart(
                partNumber: partNumber,
                eTag: eTag,
                size: currentPartSize
            ))

            uploadedBytes += currentPartSize
            job.progress.bytesUploaded = uploadedBytes
            job.progress.currentPart = partNumber
            job.progress.percentage = Double(uploadedBytes) / Double(fileSize) * 100.0

            // Calculate upload speed
            let now = Date()
            let elapsed = now.timeIntervalSince(lastProgressTime)
            if elapsed > 0.5 {
                let bytesThisInterval = uploadedBytes - lastUploadedBytes
                job.progress.uploadSpeed = Double(bytesThisInterval) / elapsed

                // Estimate time remaining
                if job.progress.uploadSpeed > 0 {
                    let remainingBytes = fileSize - uploadedBytes
                    job.progress.estimatedTimeRemaining = Double(remainingBytes) / job.progress.uploadSpeed
                }

                lastProgressTime = now
                lastUploadedBytes = uploadedBytes

                // Record for bandwidth monitoring
                await bandwidthMonitor.recordBytes(bytesThisInterval)
            }

            progressHandler(job.progress)

            logger.debug("Uploaded part \(partNumber)/\(totalParts)")
        }

        // Complete multipart upload
        let completeInput = CompleteMultipartUploadInput(
            bucket: job.bucket,
            key: job.destinationPath,
            multipartUpload: S3ClientTypes.CompletedMultipartUpload(parts: completedParts),
            uploadId: uploadId
        )

        _ = try await client.completeMultipartUpload(input: completeInput)

        // Generate presigned URL
        let presignedURL = try await generatePresignedURL(
            bucket: job.bucket,
            key: job.destinationPath,
            expiresIn: 3600
        )

        job.markCompleted(presignedURL: presignedURL)

        // Remove from active uploads
        activeUploads.removeValue(forKey: job.id)

        logger.info("Multipart upload completed: \(job.displayName)")
    }

    // MARK: - Resume Upload

    /// Resumes an incomplete multipart upload
    public func resumeUpload(
        job: inout UploadJob,
        progressHandler: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        guard let uploadId = job.uploadId else {
            // No existing upload, start fresh
            try await uploadFile(job: &job, progressHandler: progressHandler)
            return
        }

        logger.info("Resuming upload: \(job.displayName), uploadId: \(uploadId)")

        // List already uploaded parts
        let listInput = ListPartsInput(
            bucket: job.bucket,
            key: job.destinationPath,
            uploadId: uploadId
        )

        let listOutput = try await client.listParts(input: listInput)
        let existingParts = listOutput.parts ?? []

        let existingPartNumbers = Set(existingParts.compactMap { $0.partNumber })
        let uploadedBytes = Int64(existingParts.reduce(0) { $0 + ($1.size ?? 0) })

        job.progress.bytesUploaded = uploadedBytes
        job.progress.currentPart = existingPartNumbers.max() ?? 0
        progressHandler(job.progress)

        // Continue uploading remaining parts
        let fileHandle = try FileHandle(forReadingFrom: job.sourceURL)
        defer { try? fileHandle.close() }

        let fileSize = job.fileInfo.size
        let totalParts = job.progress.totalParts

        var completedParts = existingParts.map {
            S3ClientTypes.CompletedPart(eTag: $0.eTag, partNumber: $0.partNumber)
        }

        var currentUploadedBytes: Int64 = uploadedBytes

        for partNumber in 1...totalParts {
            if existingPartNumbers.contains(partNumber) {
                continue
            }

            let offset = Int64(partNumber - 1) * partSize
            let remainingBytes = fileSize - offset
            let currentPartSize = min(partSize, remainingBytes)

            try fileHandle.seek(toOffset: UInt64(offset))
            guard let partData = try fileHandle.read(upToCount: Int(currentPartSize)) else {
                throw S3UploadError.readFailed
            }

            let uploadPartInput = UploadPartInput(
                body: .data(partData),
                bucket: job.bucket,
                contentLength: Int(currentPartSize),
                key: job.destinationPath,
                partNumber: partNumber,
                uploadId: uploadId
            )

            let partOutput = try await client.uploadPart(input: uploadPartInput)

            guard let eTag = partOutput.eTag else {
                throw S3UploadError.partUploadFailed(partNumber)
            }

            completedParts.append(S3ClientTypes.CompletedPart(
                eTag: eTag,
                partNumber: partNumber
            ))

            currentUploadedBytes += currentPartSize
            job.progress.bytesUploaded = currentUploadedBytes
            job.progress.currentPart = partNumber
            job.progress.percentage = Double(currentUploadedBytes) / Double(fileSize) * 100.0

            progressHandler(job.progress)
        }

        // Sort parts by part number
        completedParts.sort { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }

        // Complete multipart upload
        let completeInput = CompleteMultipartUploadInput(
            bucket: job.bucket,
            key: job.destinationPath,
            multipartUpload: S3ClientTypes.CompletedMultipartUpload(parts: completedParts),
            uploadId: uploadId
        )

        _ = try await client.completeMultipartUpload(input: completeInput)

        let presignedURL = try await generatePresignedURL(
            bucket: job.bucket,
            key: job.destinationPath,
            expiresIn: 3600
        )

        job.markCompleted(presignedURL: presignedURL)
        logger.info("Resumed upload completed: \(job.displayName)")
    }

    // MARK: - Cancel Upload

    /// Cancels an in-progress upload
    public func cancelUpload(job: inout UploadJob) async throws {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        if let uploadId = job.uploadId {
            let abortInput = AbortMultipartUploadInput(
                bucket: job.bucket,
                key: job.destinationPath,
                uploadId: uploadId
            )

            try await client.abortMultipartUpload(input: abortInput)
            logger.info("Aborted multipart upload: \(uploadId)")
        }

        job.status = .cancelled
        activeUploads.removeValue(forKey: job.id)
    }

    // MARK: - Sequence Upload

    /// Uploads an image sequence
    public func uploadSequence(
        job: inout UploadJob,
        progressHandler: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        guard let sequenceInfo = job.fileInfo.sequenceInfo else {
            throw S3UploadError.invalidSequence
        }

        logger.info("Starting sequence upload: \(sequenceInfo.baseName), \(sequenceInfo.fileCount) files")

        job.progress.totalBytes = sequenceInfo.totalSize
        var totalUploaded: Int64 = 0
        let totalSize = sequenceInfo.totalSize
        let fileCount = sequenceInfo.fileCount

        for (index, fileURL) in sequenceInfo.files.enumerated() {
            let fileInfo = FileInfo.from(url: fileURL)
            let destPath = job.destinationPath + fileURL.lastPathComponent

            var fileJob = UploadJob(
                sourceURL: fileURL,
                destinationPath: destPath,
                bucket: job.bucket,
                region: job.region,
                fileInfo: fileInfo
            )

            // Capture current total for this iteration
            let currentTotal = totalUploaded
            let currentIndex = index

            try await uploadFile(job: &fileJob) { progress in
                let sequenceProgress = UploadProgress(
                    bytesUploaded: currentTotal + progress.bytesUploaded,
                    totalBytes: totalSize,
                    percentage: Double(currentTotal + progress.bytesUploaded) / Double(totalSize) * 100.0,
                    currentPart: currentIndex + 1,
                    totalParts: fileCount
                )
                progressHandler(sequenceProgress)
            }

            totalUploaded += fileInfo.size
        }

        job.markCompleted()
        logger.info("Sequence upload completed: \(sequenceInfo.baseName)")
    }

    // MARK: - Presigned URLs

    private let presignService = S3PresignService()

    /// Generates a presigned URL for downloading
    public func generatePresignedURL(
        bucket: String,
        key: String,
        expiresIn: Int = 3600
    ) async throws -> String {
        guard let creds = credentials else {
            // Fall back to S3 URI if no credentials
            return "s3://\(bucket)/\(key)"
        }

        presignService.configure(credentials: creds, region: region)
        let url = try presignService.presignGetObject(
            bucket: bucket,
            key: key,
            expiresIn: expiresIn
        )
        return url.absoluteString
    }

    /// Generates a presigned URL for uploading
    public func generatePresignedUploadURL(
        bucket: String,
        key: String,
        contentType: String? = nil,
        expiresIn: Int = 3600
    ) async throws -> String {
        guard let creds = credentials else {
            throw S3UploadError.notConfigured
        }

        presignService.configure(credentials: creds, region: region)
        let url = try presignService.presignPutObject(
            bucket: bucket,
            key: key,
            contentType: contentType,
            expiresIn: expiresIn
        )
        return url.absoluteString
    }

    /// Gets the AWS Console URL for an object
    public func getConsoleURL(bucket: String, key: String) -> URL? {
        return presignService.consoleURL(bucket: bucket, key: key, region: region)
    }

    // MARK: - Bucket Operations

    /// Verifies credentials are valid by calling ListBuckets
    public func verifyAccess() async throws {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        // This will throw if credentials are invalid
        _ = try await client.listBuckets(input: ListBucketsInput())
        logger.info("Credentials verified successfully")
    }

    /// Lists buckets accessible to the user
    public func listBuckets() async throws -> [String] {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        let output = try await client.listBuckets(input: ListBucketsInput())
        return output.buckets?.compactMap { $0.name } ?? []
    }

    /// Lists objects in a bucket with optional prefix
    public func listObjects(
        bucket: String,
        prefix: String? = nil,
        maxKeys: Int = 1000
    ) async throws -> [S3Object] {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        let input = ListObjectsV2Input(
            bucket: bucket,
            maxKeys: maxKeys,
            prefix: prefix
        )

        let output = try await client.listObjectsV2(input: input)

        return output.contents?.map { obj in
            S3Object(
                key: obj.key ?? "",
                size: Int64(obj.size ?? 0),
                lastModified: obj.lastModified,
                eTag: obj.eTag
            )
        } ?? []
    }

    /// Lists folders (common prefixes) in a bucket at a given path
    public func listFolders(
        bucket: String,
        prefix: String
    ) async throws -> [String] {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        let normalizedPrefix = prefix.hasSuffix("/") ? prefix : prefix + "/"

        let input = ListObjectsV2Input(
            bucket: bucket,
            delimiter: "/",
            prefix: normalizedPrefix
        )

        let output = try await client.listObjectsV2(input: input)

        // Return common prefixes (folders)
        return output.commonPrefixes?.compactMap { $0.prefix } ?? []
    }

    /// Checks if an object exists
    public func objectExists(bucket: String, key: String) async throws -> Bool {
        guard let client = s3Client else {
            throw S3UploadError.notConfigured
        }

        do {
            let input = HeadObjectInput(bucket: bucket, key: key)
            _ = try await client.headObject(input: input)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Status

    public func getActiveUploadCount() -> Int {
        return activeUploads.count
    }

    public func getQueuedCount() -> Int {
        return uploadQueue.count
    }
}

// MARK: - Supporting Types

public struct S3Object: Sendable {
    public let key: String
    public let size: Int64
    public let lastModified: Date?
    public let eTag: String?
}

private struct ActiveUpload {
    let jobId: UUID
    let uploadId: String
    let bucket: String
    let key: String
    let totalParts: Int
    var completedParts: Int = 0
}

// MARK: - Errors

public enum S3UploadError: Error, LocalizedError {
    case notConfigured
    case multipartInitFailed
    case partUploadFailed(Int)
    case readFailed
    case invalidSequence
    case uploadCancelled

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "S3 client not configured"
        case .multipartInitFailed:
            return "Failed to initiate multipart upload"
        case .partUploadFailed(let part):
            return "Failed to upload part \(part)"
        case .readFailed:
            return "Failed to read file data"
        case .invalidSequence:
            return "Invalid image sequence"
        case .uploadCancelled:
            return "Upload was cancelled"
        }
    }
}
