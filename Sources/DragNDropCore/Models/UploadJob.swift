import Foundation

// MARK: - Upload Job

/// Represents a file or folder to be uploaded
public struct UploadJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sourceURL: URL
    public var destinationPath: String
    public var bucket: String
    public var region: String
    public var status: UploadStatus
    public var progress: UploadProgress
    public var fileInfo: FileInfo
    public var extractedValues: [String: String]
    public var error: UploadError?
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    // Multipart upload tracking
    public var uploadId: String?
    public var completedParts: [CompletedPart]
    public var presignedURL: String?
    public var s3URI: String?
    public var consoleURL: String?

    // Retry tracking
    public var retryAttempts: Int
    public var lastRetryAt: Date?
    public var retryErrors: [String]

    // Companion files from skills
    public var companionFiles: [CompanionFile]
    public var skillStatus: SkillStatus

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationPath: String,
        bucket: String,
        region: String,
        status: UploadStatus = .pending,
        progress: UploadProgress = UploadProgress(),
        fileInfo: FileInfo,
        extractedValues: [String: String] = [:],
        error: UploadError? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        uploadId: String? = nil,
        completedParts: [CompletedPart] = [],
        presignedURL: String? = nil,
        s3URI: String? = nil,
        consoleURL: String? = nil,
        retryAttempts: Int = 0,
        lastRetryAt: Date? = nil,
        retryErrors: [String] = [],
        companionFiles: [CompanionFile] = [],
        skillStatus: SkillStatus = .notStarted
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.bucket = bucket
        self.region = region
        self.status = status
        self.progress = progress
        self.fileInfo = fileInfo
        self.extractedValues = extractedValues
        self.error = error
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.uploadId = uploadId
        self.completedParts = completedParts
        self.presignedURL = presignedURL
        self.s3URI = s3URI
        self.consoleURL = consoleURL
        self.retryAttempts = retryAttempts
        self.lastRetryAt = lastRetryAt
        self.retryErrors = retryErrors
        self.companionFiles = companionFiles
        self.skillStatus = skillStatus
    }

    public var fullS3Path: String {
        "s3://\(bucket)/\(destinationPath)"
    }

    public var awsConsoleURL: URL? {
        URL(string: "https://\(region).console.aws.amazon.com/s3/buckets/\(bucket)?prefix=\(destinationPath)")
    }

    public var displayName: String {
        sourceURL.lastPathComponent
    }

    public mutating func markStarted() {
        status = .uploading
        startedAt = Date()
    }

    public mutating func markCompleted(presignedURL: String? = nil) {
        status = .completed
        completedAt = Date()
        progress.bytesUploaded = progress.totalBytes
        progress.percentage = 100.0
        self.presignedURL = presignedURL
        self.s3URI = fullS3Path
    }

    public mutating func markFailed(_ error: UploadError) {
        status = .failed
        self.error = error
        completedAt = Date()
    }

    public mutating func markPaused() {
        status = .paused
    }

    public mutating func markForRetry(error: UploadError) {
        retryAttempts += 1
        lastRetryAt = Date()
        retryErrors.append(error.localizedDescription)
        // Reset state for retry but preserve completed parts for resumable uploads
        status = .pending
        self.error = nil
    }

    public mutating func resetForRetry() {
        status = .pending
        error = nil
        progress = UploadProgress(totalBytes: progress.totalBytes)
        // Keep completedParts for resumable uploads
    }

    public mutating func updateProgress(bytesUploaded: Int64) {
        progress.bytesUploaded = bytesUploaded
        if progress.totalBytes > 0 {
            progress.percentage = Double(bytesUploaded) / Double(progress.totalBytes) * 100.0
        }
    }
}

// MARK: - Upload Status

public enum UploadStatus: String, Codable, CaseIterable, Sendable {
    case pending = "Pending"
    case preparing = "Preparing"
    case uploading = "Uploading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"

    public var iconName: String {
        switch self {
        case .pending: return "clock"
        case .preparing: return "gearshape"
        case .uploading: return "arrow.up.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    public var isActive: Bool {
        self == .uploading || self == .preparing
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

// MARK: - Upload Progress

public struct UploadProgress: Equatable, Sendable {
    public var bytesUploaded: Int64
    public var totalBytes: Int64
    public var percentage: Double
    public var currentPart: Int
    public var totalParts: Int
    public var uploadSpeed: Double // bytes per second
    public var estimatedTimeRemaining: TimeInterval?

    public init(
        bytesUploaded: Int64 = 0,
        totalBytes: Int64 = 0,
        percentage: Double = 0.0,
        currentPart: Int = 0,
        totalParts: Int = 0,
        uploadSpeed: Double = 0,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.bytesUploaded = bytesUploaded
        self.totalBytes = totalBytes
        self.percentage = percentage
        self.currentPart = currentPart
        self.totalParts = totalParts
        self.uploadSpeed = uploadSpeed
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }

    public var formattedBytesUploaded: String {
        ByteCountFormatter.string(fromByteCount: bytesUploaded, countStyle: .file)
    }

    public var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var formattedUploadSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(uploadSpeed)))/s"
    }

    public var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining, remaining > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: remaining)
    }
}

// MARK: - File Info

public struct FileInfo: Equatable, Sendable {
    public var filename: String
    public var fileExtension: String
    public var size: Int64
    public var category: FileCategory
    public var isDirectory: Bool
    public var isSequence: Bool
    public var sequenceInfo: SequenceInfo?
    public var modificationDate: Date?
    public var checksum: String?

    public init(
        filename: String,
        fileExtension: String,
        size: Int64,
        category: FileCategory = .other,
        isDirectory: Bool = false,
        isSequence: Bool = false,
        sequenceInfo: SequenceInfo? = nil,
        modificationDate: Date? = nil,
        checksum: String? = nil
    ) {
        self.filename = filename
        self.fileExtension = fileExtension
        self.size = size
        self.category = category
        self.isDirectory = isDirectory
        self.isSequence = isSequence
        self.sequenceInfo = sequenceInfo
        self.modificationDate = modificationDate
        self.checksum = checksum
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public static func from(url: URL) -> FileInfo {
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        var size: Int64 = 0
        var isDirectory = false
        var modDate: Date?

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            size = attrs[.size] as? Int64 ?? 0
            isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
            modDate = attrs[.modificationDate] as? Date
        }

        let category = FileCategory.fromExtension(ext)

        return FileInfo(
            filename: filename,
            fileExtension: ext,
            size: size,
            category: category,
            isDirectory: isDirectory,
            modificationDate: modDate
        )
    }
}

// MARK: - Sequence Info

public struct SequenceInfo: Equatable, Sendable {
    public var baseName: String
    public var frameRange: ClosedRange<Int>
    public var padding: Int
    public var fileCount: Int
    public var totalSize: Int64
    public var files: [URL]

    public init(
        baseName: String,
        frameRange: ClosedRange<Int>,
        padding: Int,
        fileCount: Int,
        totalSize: Int64,
        files: [URL] = []
    ) {
        self.baseName = baseName
        self.frameRange = frameRange
        self.padding = padding
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.files = files
    }

    public var frameRangeString: String {
        "\(frameRange.lowerBound)-\(frameRange.upperBound)"
    }

    public var sequencePattern: String {
        let paddingStr = String(repeating: "#", count: padding)
        return "\(baseName).\(paddingStr)"
    }
}

// MARK: - Completed Part

public struct CompletedPart: Equatable, Sendable {
    public var partNumber: Int
    public var eTag: String
    public var size: Int64

    public init(partNumber: Int, eTag: String, size: Int64) {
        self.partNumber = partNumber
        self.eTag = eTag
        self.size = size
    }
}

// MARK: - Upload Error

public enum UploadError: Error, Equatable, Sendable {
    case networkError(String)
    case authenticationError(String)
    case accessDenied(String)
    case bucketNotFound(String)
    case keyTooLong(String)
    case fileTooLarge(String)
    case checksumMismatch(String)
    case multipartUploadFailed(String)
    case cancelled
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .authenticationError(let msg): return "Authentication failed: \(msg)"
        case .accessDenied(let msg): return "Access denied: \(msg)"
        case .bucketNotFound(let msg): return "Bucket not found: \(msg)"
        case .keyTooLong(let msg): return "Key too long: \(msg)"
        case .fileTooLarge(let msg): return "File too large: \(msg)"
        case .checksumMismatch(let msg): return "Checksum mismatch: \(msg)"
        case .multipartUploadFailed(let msg): return "Multipart upload failed: \(msg)"
        case .cancelled: return "Upload cancelled"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .networkError, .unknown, .multipartUploadFailed:
            return true
        case .authenticationError, .accessDenied, .bucketNotFound, .keyTooLong, .fileTooLarge, .checksumMismatch, .cancelled:
            return false
        }
    }

    /// A more detailed description for the error suitable for logging
    public var debugDescription: String {
        switch self {
        case .networkError(let msg): return "[Network] \(msg)"
        case .authenticationError(let msg): return "[Auth] \(msg)"
        case .accessDenied(let msg): return "[Access] \(msg)"
        case .bucketNotFound(let msg): return "[Bucket] \(msg)"
        case .keyTooLong(let msg): return "[Key] \(msg)"
        case .fileTooLarge(let msg): return "[Size] \(msg)"
        case .checksumMismatch(let msg): return "[Checksum] \(msg)"
        case .multipartUploadFailed(let msg): return "[Multipart] \(msg)"
        case .cancelled: return "[Cancelled]"
        case .unknown(let msg): return "[Unknown] \(msg)"
        }
    }
}

// MARK: - Extensions

extension FileCategory {
    public static func fromExtension(_ ext: String) -> FileCategory {
        let lowercased = ext.lowercased()

        switch lowercased {
        case "nk", "nknc":
            return .nukeComp
        case "exr", "tif", "tiff", "png", "dpx", "cin":
            return .imageSequence
        case "mov", "mp4", "avi", "mkv", "mxf", "prores", "m4v":
            return .video
        case "wav", "aiff", "mp3", "aac", "flac", "m4a":
            return .audio
        case "aep", "prproj", "drp", "blend", "hip", "hipnc", "ma", "mb", "fbx", "abc":
            return .project
        default:
            return .other
        }
    }
}
