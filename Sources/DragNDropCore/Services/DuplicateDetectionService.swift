import Foundation
import CommonCrypto
import Logging

// MARK: - Duplicate Detection Service

/// Detects duplicate files before upload using checksums and S3 metadata
public actor DuplicateDetectionService {
    private let logger = Logger(label: "com.dragndrop.duplicate")

    // Cache of known file hashes
    private var hashCache: [URL: String] = [:]

    // Cache of S3 object metadata (bucket/key -> hash)
    private var s3MetadataCache: [String: S3ObjectMetadata] = [:]

    // Recent uploads (to detect duplicates in same session)
    private var recentUploads: [String: RecentUpload] = [:]

    public init() {}

    // MARK: - Configuration

    public struct Config: Sendable {
        public var enableDuplicateDetection: Bool
        public var checkS3ForDuplicates: Bool
        public var checkLocalDuplicates: Bool
        public var hashAlgorithm: HashAlgorithm
        public var maxFileSizeForFullHash: Int64  // Only hash files smaller than this
        public var onDuplicateAction: DuplicateAction

        public init(
            enableDuplicateDetection: Bool = true,
            checkS3ForDuplicates: Bool = true,
            checkLocalDuplicates: Bool = true,
            hashAlgorithm: HashAlgorithm = .md5,
            maxFileSizeForFullHash: Int64 = 500 * 1024 * 1024,  // 500 MB
            onDuplicateAction: DuplicateAction = .warn
        ) {
            self.enableDuplicateDetection = enableDuplicateDetection
            self.checkS3ForDuplicates = checkS3ForDuplicates
            self.checkLocalDuplicates = checkLocalDuplicates
            self.hashAlgorithm = hashAlgorithm
            self.maxFileSizeForFullHash = maxFileSizeForFullHash
            self.onDuplicateAction = onDuplicateAction
        }
    }

    public enum HashAlgorithm: String, Codable, CaseIterable, Sendable {
        case md5 = "MD5"
        case sha256 = "SHA-256"
        case quickHash = "Quick Hash"  // Only hashes first/last chunks

        public var displayName: String { rawValue }
    }

    public enum DuplicateAction: String, Codable, CaseIterable, Sendable {
        case skip = "Skip"
        case warn = "Warn"
        case rename = "Rename"
        case overwrite = "Overwrite"

        public var displayName: String { rawValue }

        public var description: String {
            switch self {
            case .skip: return "Automatically skip duplicate files"
            case .warn: return "Show a warning and let user decide"
            case .rename: return "Automatically add suffix to filename"
            case .overwrite: return "Replace existing file"
            }
        }
    }

    // MARK: - Duplicate Check Result

    public struct DuplicateCheckResult: Sendable {
        public let isDuplicate: Bool
        public let duplicateType: DuplicateType?
        public let existingLocation: String?
        public let hash: String?
        public let suggestion: String?

        public static let notDuplicate = DuplicateCheckResult(
            isDuplicate: false,
            duplicateType: nil,
            existingLocation: nil,
            hash: nil,
            suggestion: nil
        )
    }

    public enum DuplicateType: Sendable {
        case existsInS3(bucket: String, key: String)
        case existsInQueue(jobId: UUID)
        case recentlyUploaded(date: Date)
        case localDuplicate(path: String)
    }

    // MARK: - Check for Duplicates

    /// Checks if a file is a duplicate based on hash and S3 metadata
    public func checkForDuplicate(
        url: URL,
        destinationBucket: String,
        destinationKey: String,
        config: Config,
        s3Client: S3UploadService? = nil
    ) async -> DuplicateCheckResult {
        guard config.enableDuplicateDetection else {
            return .notDuplicate
        }

        // Calculate file hash
        let hash = await calculateHash(for: url, algorithm: config.hashAlgorithm, maxSize: config.maxFileSizeForFullHash)

        guard let fileHash = hash else {
            return .notDuplicate
        }

        // Check recent uploads first (fastest)
        if let recent = recentUploads[fileHash] {
            return DuplicateCheckResult(
                isDuplicate: true,
                duplicateType: .recentlyUploaded(date: recent.uploadedAt),
                existingLocation: recent.s3URI,
                hash: fileHash,
                suggestion: "This file was already uploaded \(formatRelativeTime(recent.uploadedAt))"
            )
        }

        // Check S3 for existing file at destination
        if config.checkS3ForDuplicates, let client = s3Client {
            if let existing = await checkS3ForDuplicate(
                bucket: destinationBucket,
                key: destinationKey,
                hash: fileHash,
                client: client
            ) {
                return existing
            }
        }

        // Store hash for future local duplicate detection
        hashCache[url] = fileHash

        return DuplicateCheckResult(
            isDuplicate: false,
            duplicateType: nil,
            existingLocation: nil,
            hash: fileHash,
            suggestion: nil
        )
    }

    /// Checks multiple files for duplicates among themselves
    public func checkForLocalDuplicates(
        urls: [URL],
        config: Config
    ) async -> [URL: [URL]] {
        guard config.checkLocalDuplicates else {
            return [:]
        }

        var hashToURLs: [String: [URL]] = [:]

        for url in urls {
            if let hash = await calculateHash(for: url, algorithm: config.hashAlgorithm, maxSize: config.maxFileSizeForFullHash) {
                hashToURLs[hash, default: []].append(url)
            }
        }

        // Return only groups with duplicates
        var duplicateGroups: [URL: [URL]] = [:]
        for (_, urls) in hashToURLs where urls.count > 1 {
            let primary = urls[0]
            duplicateGroups[primary] = Array(urls.dropFirst())
        }

        return duplicateGroups
    }

    // MARK: - Record Uploads

    /// Records a successful upload for future duplicate detection
    public func recordUpload(url: URL, bucket: String, key: String, hash: String?) {
        let s3URI = "s3://\(bucket)/\(key)"

        if let fileHash = hash ?? hashCache[url] {
            recentUploads[fileHash] = RecentUpload(
                hash: fileHash,
                s3URI: s3URI,
                uploadedAt: Date()
            )
        }
    }

    /// Clears the recent upload cache
    public func clearRecentUploads() {
        recentUploads.removeAll()
    }

    /// Clears uploads older than a specified time
    public func clearOldUploads(olderThan: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-olderThan)
        recentUploads = recentUploads.filter { $0.value.uploadedAt > cutoff }
    }

    // MARK: - Hash Calculation

    /// Calculates file hash using the specified algorithm
    private func calculateHash(
        for url: URL,
        algorithm: HashAlgorithm,
        maxSize: Int64
    ) async -> String? {
        // Check cache first
        if let cached = hashCache[url] {
            return cached
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        // Get file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }

        // Use quick hash for large files
        let effectiveAlgorithm = size > maxSize ? .quickHash : algorithm

        let hash: String?
        switch effectiveAlgorithm {
        case .md5:
            hash = calculateMD5(for: url)
        case .sha256:
            hash = calculateSHA256(for: url)
        case .quickHash:
            hash = calculateQuickHash(for: url, fileSize: size)
        }

        if let hash = hash {
            hashCache[url] = hash
        }

        return hash
    }

    private func calculateMD5(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func calculateSHA256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Quick hash: combines file size with hash of first and last chunks
    private func calculateQuickHash(for url: URL, fileSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 64 * 1024  // 64 KB chunks

        // Read first chunk
        guard let firstChunk = try? handle.read(upToCount: chunkSize) else { return nil }

        // Read last chunk
        var lastChunk = Data()
        if fileSize > Int64(chunkSize) {
            try? handle.seek(toOffset: UInt64(fileSize) - UInt64(chunkSize))
            lastChunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
        }

        // Combine: size + first chunk hash + last chunk hash
        var combined = Data()
        combined.append(contentsOf: withUnsafeBytes(of: fileSize) { Array($0) })
        combined.append(firstChunk)
        combined.append(lastChunk)

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        combined.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(combined.count), &digest)
        }

        return "quick-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - S3 Duplicate Check

    private func checkS3ForDuplicate(
        bucket: String,
        key: String,
        hash: String,
        client: S3UploadService
    ) async -> DuplicateCheckResult? {
        // Check if object already exists at destination
        do {
            let exists = try await client.objectExists(bucket: bucket, key: key)
            if exists {
                return DuplicateCheckResult(
                    isDuplicate: true,
                    duplicateType: .existsInS3(bucket: bucket, key: key),
                    existingLocation: "s3://\(bucket)/\(key)",
                    hash: hash,
                    suggestion: "A file already exists at this location in S3"
                )
            }
        } catch {
            logger.warning("Failed to check S3 for duplicate: \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Generate Unique Name

    /// Generates a unique filename by adding a suffix
    public func generateUniqueName(
        originalName: String,
        existingNames: Set<String>
    ) -> String {
        let url = URL(fileURLWithPath: originalName)
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newName = originalName

        while existingNames.contains(newName) {
            if ext.isEmpty {
                newName = "\(baseName)_\(counter)"
            } else {
                newName = "\(baseName)_\(counter).\(ext)"
            }
            counter += 1
        }

        return newName
    }

    // MARK: - Helpers

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Types

private struct S3ObjectMetadata {
    let bucket: String
    let key: String
    let etag: String?
    let size: Int64
    let lastModified: Date?
}

private struct RecentUpload {
    let hash: String
    let s3URI: String
    let uploadedAt: Date
}
