import Foundation

// MARK: - Workflow Configuration

/// Represents a complete workflow configuration that can be saved/loaded
public struct WorkflowConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var version: String
    public var createdAt: Date
    public var updatedAt: Date

    // Storage configuration
    public var storageProvider: StorageProvider
    public var bucket: String
    public var region: String

    // Path template with placeholders
    public var pathTemplate: PathTemplate

    // Extraction rules for parsing filenames
    public var extractionRules: [ExtractionRule]

    // File type configurations
    public var fileTypeConfigs: [FileTypeConfig]

    // Upload settings
    public var uploadSettings: UploadSettings

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        version: String = "1.0",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        storageProvider: StorageProvider = .s3,
        bucket: String,
        region: String = "us-east-1",
        pathTemplate: PathTemplate,
        extractionRules: [ExtractionRule] = [],
        fileTypeConfigs: [FileTypeConfig] = FileTypeConfig.defaultConfigs,
        uploadSettings: UploadSettings = UploadSettings()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storageProvider = storageProvider
        self.bucket = bucket
        self.region = region
        self.pathTemplate = pathTemplate
        self.extractionRules = extractionRules
        self.fileTypeConfigs = fileTypeConfigs
        self.uploadSettings = uploadSettings
    }
}

// MARK: - Storage Provider

public enum StorageProvider: String, Codable, CaseIterable, Sendable {
    case s3 = "Amazon S3"
    case gcs = "Google Cloud Storage"
    case azure = "Azure Blob Storage"
    case local = "Local/Network Path"

    public var iconName: String {
        switch self {
        case .s3: return "cloud"
        case .gcs: return "cloud"
        case .azure: return "cloud"
        case .local: return "folder"
        }
    }
}

// MARK: - Path Template

/// Defines the destination path structure with placeholders
public struct PathTemplate: Codable, Equatable, Sendable {
    /// The template string with placeholders like {SHOW}, {EPISODE}, {SHOT}
    public var template: String

    /// Defined placeholders and their properties
    public var placeholders: [Placeholder]

    /// Static prefix path (e.g., "projects/")
    public var staticPrefix: String

    /// Static suffix path (e.g., "/03_VFX/")
    public var staticSuffix: String

    public init(
        template: String,
        placeholders: [Placeholder] = [],
        staticPrefix: String = "",
        staticSuffix: String = ""
    ) {
        self.template = template
        self.placeholders = placeholders
        self.staticPrefix = staticPrefix
        self.staticSuffix = staticSuffix
    }

    /// Builds the full path by substituting placeholders with values
    public func buildPath(with values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
            result = result.replacingOccurrences(of: "{\(key.lowercased())}", with: value)
            result = result.replacingOccurrences(of: "{\(key.uppercased())}", with: value)
        }
        return result
    }

    /// Extract all placeholder names from the template
    public var extractedPlaceholderNames: [String] {
        let regex = try? NSRegularExpression(pattern: "\\{([^}]+)\\}", options: [])
        let range = NSRange(template.startIndex..., in: template)
        let matches = regex?.matches(in: template, options: [], range: range) ?? []

        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: template) else { return nil }
            return String(template[range])
        }
    }
}

// MARK: - Placeholder

/// Defines a placeholder variable in the path template
public struct Placeholder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var displayName: String
    public var description: String
    public var required: Bool
    public var defaultValue: String?
    public var transformations: [PlaceholderTransformation]

    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        description: String = "",
        required: Bool = true,
        defaultValue: String? = nil,
        transformations: [PlaceholderTransformation] = []
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
        self.transformations = transformations
    }
}

// MARK: - Placeholder Transformation

/// Transformations that can be applied to extracted values
public enum PlaceholderTransformation: String, Codable, CaseIterable, Sendable {
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case capitalize = "Capitalize"
    case trimWhitespace = "Trim Whitespace"
    case removeSpecialChars = "Remove Special Characters"
    case padLeft = "Pad Left (zeros)"
    case padRight = "Pad Right (zeros)"

    public func apply(to value: String, padding: Int = 3) -> String {
        switch self {
        case .uppercase:
            return value.uppercased()
        case .lowercase:
            return value.lowercased()
        case .capitalize:
            return value.capitalized
        case .trimWhitespace:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeSpecialChars:
            return value.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        case .padLeft:
            return String(repeating: "0", count: max(0, padding - value.count)) + value
        case .padRight:
            return value + String(repeating: "0", count: max(0, padding - value.count))
        }
    }
}

// MARK: - Extraction Rule

/// Defines how to extract placeholder values from filenames
public struct ExtractionRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var enabled: Bool
    public var priority: Int

    /// The regex pattern to match against filenames
    public var pattern: String

    /// Mapping of regex capture groups to placeholder names
    public var captureGroupMappings: [CaptureGroupMapping]

    /// File extensions this rule applies to (empty = all)
    public var applicableExtensions: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        enabled: Bool = true,
        priority: Int = 0,
        pattern: String,
        captureGroupMappings: [CaptureGroupMapping] = [],
        applicableExtensions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.priority = priority
        self.pattern = pattern
        self.captureGroupMappings = captureGroupMappings
        self.applicableExtensions = applicableExtensions
    }

    /// Attempts to extract values from a filename using this rule
    public func extract(from filename: String) -> [String: String]? {
        guard enabled else { return nil }

        // Check extension filter
        if !applicableExtensions.isEmpty {
            let ext = (filename as NSString).pathExtension.lowercased()
            if !applicableExtensions.contains(where: { $0.lowercased() == ext }) {
                return nil
            }
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(filename.startIndex..., in: filename)
        guard let match = regex.firstMatch(in: filename, options: [], range: range) else {
            return nil
        }

        var results: [String: String] = [:]

        for mapping in captureGroupMappings {
            let groupRange = match.range(at: mapping.groupIndex)
            if groupRange.location != NSNotFound,
               let swiftRange = Range(groupRange, in: filename) {
                var value = String(filename[swiftRange])

                // Apply transformations
                for transformation in mapping.transformations {
                    value = transformation.apply(to: value)
                }

                results[mapping.placeholderName] = value
            }
        }

        return results.isEmpty ? nil : results
    }
}

// MARK: - Capture Group Mapping

/// Maps a regex capture group to a placeholder
public struct CaptureGroupMapping: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var groupIndex: Int
    public var groupName: String?
    public var placeholderName: String
    public var transformations: [PlaceholderTransformation]

    public init(
        id: UUID = UUID(),
        groupIndex: Int,
        groupName: String? = nil,
        placeholderName: String,
        transformations: [PlaceholderTransformation] = []
    ) {
        self.id = id
        self.groupIndex = groupIndex
        self.groupName = groupName
        self.placeholderName = placeholderName
        self.transformations = transformations
    }
}

// MARK: - File Type Configuration

/// Configuration for different file types
public struct FileTypeConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var category: FileCategory
    public var extensions: [String]
    public var enabled: Bool
    public var destinationSubfolder: String?
    public var isSequence: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        category: FileCategory,
        extensions: [String],
        enabled: Bool = true,
        destinationSubfolder: String? = nil,
        isSequence: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.extensions = extensions
        self.enabled = enabled
        self.destinationSubfolder = destinationSubfolder
        self.isSequence = isSequence
    }

    public static var defaultConfigs: [FileTypeConfig] {
        [
            FileTypeConfig(
                name: "Nuke Comp",
                category: .nukeComp,
                extensions: ["nk", "nknc"],
                destinationSubfolder: "nuke"
            ),
            FileTypeConfig(
                name: "EXR Sequence",
                category: .imageSequence,
                extensions: ["exr"],
                destinationSubfolder: "renders",
                isSequence: true
            ),
            FileTypeConfig(
                name: "TIFF Sequence",
                category: .imageSequence,
                extensions: ["tif", "tiff"],
                destinationSubfolder: "renders",
                isSequence: true
            ),
            FileTypeConfig(
                name: "PNG Sequence",
                category: .imageSequence,
                extensions: ["png"],
                destinationSubfolder: "renders",
                isSequence: true
            ),
            FileTypeConfig(
                name: "Video",
                category: .video,
                extensions: ["mov", "mp4", "avi", "mkv", "mxf", "prores"],
                destinationSubfolder: "video"
            ),
            FileTypeConfig(
                name: "Audio",
                category: .audio,
                extensions: ["wav", "aiff", "mp3", "aac", "flac"],
                destinationSubfolder: "audio"
            ),
            FileTypeConfig(
                name: "Project Files",
                category: .project,
                extensions: ["aep", "prproj", "drp", "blend", "hip", "hipnc", "ma", "mb"],
                destinationSubfolder: "projects"
            )
        ]
    }
}

// MARK: - File Category

public enum FileCategory: String, Codable, CaseIterable, Sendable {
    case nukeComp = "Nuke Comp"
    case imageSequence = "Image Sequence"
    case video = "Video"
    case audio = "Audio"
    case project = "Project File"
    case other = "Other"

    public var iconName: String {
        switch self {
        case .nukeComp: return "wand.and.rays"
        case .imageSequence: return "photo.stack"
        case .video: return "film"
        case .audio: return "waveform"
        case .project: return "doc.badge.gearshape"
        case .other: return "doc"
        }
    }

    public var color: String {
        switch self {
        case .nukeComp: return "orange"
        case .imageSequence: return "purple"
        case .video: return "blue"
        case .audio: return "green"
        case .project: return "yellow"
        case .other: return "gray"
        }
    }
}

// MARK: - Upload Settings

public struct UploadSettings: Codable, Equatable, Sendable {
    public var maxConcurrentUploads: Int
    public var multipartThresholdMB: Int
    public var partSizeMB: Int
    public var enableResumable: Bool
    public var retryCount: Int
    public var retryDelaySeconds: Int
    public var enableCompression: Bool
    public var verifyChecksum: Bool
    public var storageClass: S3StorageClass
    public var enableEncryption: Bool
    public var encryptionType: S3EncryptionType

    // Bandwidth throttling
    public var enableBandwidthThrottling: Bool
    public var maxUploadSpeedMBps: Double  // MB/s - 0 means unlimited
    public var throttleSchedule: ThrottleSchedule?

    public init(
        maxConcurrentUploads: Int = 4,
        multipartThresholdMB: Int = 16,
        partSizeMB: Int = 8,
        enableResumable: Bool = true,
        retryCount: Int = 3,
        retryDelaySeconds: Int = 5,
        enableCompression: Bool = false,
        verifyChecksum: Bool = true,
        storageClass: S3StorageClass = .standard,
        enableEncryption: Bool = false,
        encryptionType: S3EncryptionType = .aes256,
        enableBandwidthThrottling: Bool = false,
        maxUploadSpeedMBps: Double = 0,
        throttleSchedule: ThrottleSchedule? = nil
    ) {
        self.maxConcurrentUploads = maxConcurrentUploads
        self.multipartThresholdMB = multipartThresholdMB
        self.partSizeMB = partSizeMB
        self.enableResumable = enableResumable
        self.retryCount = retryCount
        self.retryDelaySeconds = retryDelaySeconds
        self.enableCompression = enableCompression
        self.verifyChecksum = verifyChecksum
        self.storageClass = storageClass
        self.enableEncryption = enableEncryption
        self.encryptionType = encryptionType
        self.enableBandwidthThrottling = enableBandwidthThrottling
        self.maxUploadSpeedMBps = maxUploadSpeedMBps
        self.throttleSchedule = throttleSchedule
    }

    /// The effective max upload speed in bytes per second
    public var maxUploadSpeedBps: Int64 {
        guard enableBandwidthThrottling && maxUploadSpeedMBps > 0 else { return 0 }
        return Int64(maxUploadSpeedMBps * 1024 * 1024)
    }
}

// MARK: - Throttle Schedule

/// Allows scheduling different bandwidth limits at different times
public struct ThrottleSchedule: Codable, Equatable, Sendable {
    public var rules: [ThrottleRule]

    public init(rules: [ThrottleRule] = []) {
        self.rules = rules
    }

    /// Gets the applicable throttle speed for the current time
    public func currentSpeedLimitMBps() -> Double? {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeInMinutes = currentHour * 60 + currentMinute

        for rule in rules where rule.enabled {
            if rule.isActive(at: currentTimeInMinutes) {
                return rule.speedLimitMBps
            }
        }

        return nil
    }
}

/// A single throttle rule for a time period
public struct ThrottleRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var startTimeMinutes: Int  // Minutes from midnight (0-1439)
    public var endTimeMinutes: Int    // Minutes from midnight (0-1439)
    public var speedLimitMBps: Double
    public var daysOfWeek: Set<Int>   // 1=Sunday, 7=Saturday

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        startTimeMinutes: Int,
        endTimeMinutes: Int,
        speedLimitMBps: Double,
        daysOfWeek: Set<Int> = Set(1...7)
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.startTimeMinutes = startTimeMinutes
        self.endTimeMinutes = endTimeMinutes
        self.speedLimitMBps = speedLimitMBps
        self.daysOfWeek = daysOfWeek
    }

    /// Checks if this rule is active at the given time
    public func isActive(at timeInMinutes: Int) -> Bool {
        guard enabled else { return false }

        // Check day of week
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: Date())
        guard daysOfWeek.contains(dayOfWeek) else { return false }

        // Check time range (handles overnight ranges)
        if startTimeMinutes <= endTimeMinutes {
            return timeInMinutes >= startTimeMinutes && timeInMinutes < endTimeMinutes
        } else {
            // Overnight range (e.g., 22:00 - 06:00)
            return timeInMinutes >= startTimeMinutes || timeInMinutes < endTimeMinutes
        }
    }

    /// Formatted start time string
    public var startTimeString: String {
        let hours = startTimeMinutes / 60
        let minutes = startTimeMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Formatted end time string
    public var endTimeString: String {
        let hours = endTimeMinutes / 60
        let minutes = endTimeMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

public enum S3StorageClass: String, Codable, CaseIterable, Sendable {
    case standard = "STANDARD"
    case standardIA = "STANDARD_IA"
    case onezoneIA = "ONEZONE_IA"
    case intelligentTiering = "INTELLIGENT_TIERING"
    case glacier = "GLACIER"
    case glacierIR = "GLACIER_IR"
    case deepArchive = "DEEP_ARCHIVE"

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .standardIA: return "Standard-IA"
        case .onezoneIA: return "One Zone-IA"
        case .intelligentTiering: return "Intelligent-Tiering"
        case .glacier: return "Glacier Flexible Retrieval"
        case .glacierIR: return "Glacier Instant Retrieval"
        case .deepArchive: return "Glacier Deep Archive"
        }
    }
}

public enum S3EncryptionType: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case aes256 = "AES256"
    case awsKms = "aws:kms"

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .aes256: return "SSE-S3 (AES-256)"
        case .awsKms: return "SSE-KMS"
        }
    }
}

// MARK: - Sample Configuration

extension WorkflowConfiguration {
    /// Creates a sample VFX workflow configuration
    public static var sampleVFXWorkflow: WorkflowConfiguration {
        WorkflowConfiguration(
            name: "VFX Shot Delivery",
            description: "Upload VFX shots to the correct S3 folder structure",
            bucket: "sync-services",
            region: "us-east-1",
            pathTemplate: PathTemplate(
                template: "projects/{SHOW}/season02/{EPISODE}/shots/{shot}_{category}/vfx/",
                placeholders: [
                    Placeholder(name: "SHOW", displayName: "Show Name", description: "The name of the show"),
                    Placeholder(name: "EPISODE", displayName: "Episode", description: "Episode number"),
                    Placeholder(name: "shot", displayName: "Shot ID", description: "Shot identifier"),
                    Placeholder(name: "category", displayName: "Category", description: "Shot category")
                ],
                staticPrefix: "projects/",
                staticSuffix: "/vfx/"
            ),
            extractionRules: [
                ExtractionRule(
                    name: "VFX Shot Pattern",
                    description: "Extracts show, episode, shot, and category from filename",
                    pattern: "^([A-Za-z]+)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z]+)",
                    captureGroupMappings: [
                        CaptureGroupMapping(groupIndex: 1, placeholderName: "SHOW"),
                        CaptureGroupMapping(groupIndex: 1, placeholderName: "show", transformations: [.lowercase]),
                        CaptureGroupMapping(groupIndex: 2, placeholderName: "EPISODE"),
                        CaptureGroupMapping(groupIndex: 2, placeholderName: "episode"),
                        CaptureGroupMapping(groupIndex: 3, placeholderName: "shot"),
                        CaptureGroupMapping(groupIndex: 4, placeholderName: "category")
                    ]
                )
            ]
        )
    }
}
