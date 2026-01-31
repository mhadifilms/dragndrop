import Foundation

// MARK: - App Settings

/// Global application settings persisted in UserDefaults
public struct AppSettings: Codable, Equatable, Sendable {
    // Authentication
    public var awsRegion: String
    public var awsProfileName: String

    // Active workflow
    public var activeWorkflowId: UUID?
    public var recentWorkflowIds: [UUID]

    // UI Settings
    public var launchAtLogin: Bool
    public var showNotifications: Bool
    public var notificationSound: Bool
    public var autoStartUploads: Bool
    public var confirmBeforeUpload: Bool
    public var closeWindowAfterUploadStart: Bool
    public var theme: AppTheme

    // Upload behavior
    public var defaultUploadSettings: UploadSettings

    // History
    public var keepHistoryDays: Int
    public var maxHistoryItems: Int

    // File filtering
    public var enableFileTypeFilter: Bool
    public var allowedFileExtensions: [String]
    public var blockedFileExtensions: [String]
    public var maxFileSizeMB: Int  // 0 = unlimited
    public var allowHiddenFiles: Bool

    // Duplicate detection
    public var enableDuplicateDetection: Bool
    public var checkS3ForDuplicates: Bool
    public var duplicateAction: DuplicateDetectionService.DuplicateAction

    // Upload scheduling
    public var uploadSchedule: UploadSchedule
    public var selectedSchedulePreset: String  // SchedulePreset rawValue

    // Advanced
    public var enableDebugLogging: Bool
    public var cliServerPort: Int
    public var enableCLIServer: Bool

    // Onboarding
    public var hasCompletedOnboarding: Bool
    public var onboardingVersion: Int  // Track which onboarding version was completed

    public init(
        awsRegion: String = "us-east-1",
        awsProfileName: String = "default",
        activeWorkflowId: UUID? = nil,
        recentWorkflowIds: [UUID] = [],
        launchAtLogin: Bool = false,
        showNotifications: Bool = true,
        notificationSound: Bool = true,
        autoStartUploads: Bool = false,
        confirmBeforeUpload: Bool = true,
        closeWindowAfterUploadStart: Bool = true,
        theme: AppTheme = .system,
        defaultUploadSettings: UploadSettings = UploadSettings(),
        keepHistoryDays: Int = 30,
        maxHistoryItems: Int = 1000,
        enableFileTypeFilter: Bool = false,
        allowedFileExtensions: [String] = AppSettings.defaultAllowedExtensions,
        blockedFileExtensions: [String] = AppSettings.defaultBlockedExtensions,
        maxFileSizeMB: Int = 0,
        allowHiddenFiles: Bool = false,
        enableDuplicateDetection: Bool = true,
        checkS3ForDuplicates: Bool = true,
        duplicateAction: DuplicateDetectionService.DuplicateAction = .warn,
        uploadSchedule: UploadSchedule = UploadSchedule(),
        selectedSchedulePreset: String = SchedulePreset.none.rawValue,
        enableDebugLogging: Bool = false,
        cliServerPort: Int = 9847,
        enableCLIServer: Bool = true,
        hasCompletedOnboarding: Bool = false,
        onboardingVersion: Int = 0
    ) {
        self.awsSSOStartURL = awsSSOStartURL
        self.awsSSORegion = awsSSORegion
        self.awsAccountId = awsAccountId
        self.awsRoleName = awsRoleName
        self.awsProfileName = awsProfileName
        self.activeWorkflowId = activeWorkflowId
        self.recentWorkflowIds = recentWorkflowIds
        self.launchAtLogin = launchAtLogin
        self.showNotifications = showNotifications
        self.notificationSound = notificationSound
        self.autoStartUploads = autoStartUploads
        self.confirmBeforeUpload = confirmBeforeUpload
        self.closeWindowAfterUploadStart = closeWindowAfterUploadStart
        self.theme = theme
        self.defaultUploadSettings = defaultUploadSettings
        self.keepHistoryDays = keepHistoryDays
        self.maxHistoryItems = maxHistoryItems
        self.enableFileTypeFilter = enableFileTypeFilter
        self.allowedFileExtensions = allowedFileExtensions
        self.blockedFileExtensions = blockedFileExtensions
        self.maxFileSizeMB = maxFileSizeMB
        self.allowHiddenFiles = allowHiddenFiles
        self.enableDuplicateDetection = enableDuplicateDetection
        self.checkS3ForDuplicates = checkS3ForDuplicates
        self.duplicateAction = duplicateAction
        self.uploadSchedule = uploadSchedule
        self.selectedSchedulePreset = selectedSchedulePreset
        self.enableDebugLogging = enableDebugLogging
        self.cliServerPort = cliServerPort
        self.enableCLIServer = enableCLIServer
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onboardingVersion = onboardingVersion
    }

    // Current onboarding version - increment when significant changes are made
    public static let currentOnboardingVersion = 1

    public var shouldShowOnboarding: Bool {
        return !hasCompletedOnboarding || onboardingVersion < Self.currentOnboardingVersion
    }

    // MARK: - Default File Extensions

    /// Default allowed extensions for VFX workflows
    public static let defaultAllowedExtensions: [String] = [
        // Nuke
        "nk", "nknc",
        // Image sequences
        "exr", "tif", "tiff", "png", "dpx", "cin", "jpg", "jpeg",
        // Video
        "mov", "mp4", "avi", "mkv", "mxf", "prores", "m4v",
        // Audio
        "wav", "aiff", "mp3", "aac", "flac", "m4a",
        // Project files
        "aep", "prproj", "drp", "blend", "hip", "hipnc", "ma", "mb", "fbx", "abc",
        // Render data
        "json", "xml", "yaml", "yml"
    ]

    /// Default blocked extensions (potentially dangerous or unwanted)
    public static let defaultBlockedExtensions: [String] = [
        // Executables
        "exe", "app", "dmg", "pkg", "deb", "rpm",
        // Scripts that could be dangerous
        "sh", "bat", "cmd", "ps1",
        // Temporary files
        "tmp", "temp", "swp", "bak",
        // System files
        "ds_store", "thumbs.db"
    ]

    // MARK: - Persistence

    private static let userDefaultsKey = "DragNDropAppSettings"

    public static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - App Theme

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    public var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - AWS Credentials

public struct AWSCredentials: Codable, Equatable, Sendable {
    public var accessKeyId: String
    public var secretAccessKey: String
    public var sessionToken: String?
    public var expiration: Date?

    public init(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        expiration: Date? = nil
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    public var isExpired: Bool {
        guard let expiration = expiration else { return false }
        return expiration < Date()
    }

    public var expiresIn: TimeInterval? {
        guard let expiration = expiration else { return nil }
        return expiration.timeIntervalSinceNow
    }
}

// MARK: - Authentication State

public enum AuthenticationState: Equatable, Sendable {
    case notAuthenticated
    case authenticating
    case authenticated(AWSCredentials)
    case expired
    case error(String)

    public var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    public var credentials: AWSCredentials? {
        if case .authenticated(let creds) = self {
            return creds
        }
        return nil
    }

    public var displayText: String {
        switch self {
        case .notAuthenticated:
            return "Not signed in"
        case .authenticating:
            return "Signing in..."
        case .authenticated:
            return "Signed in"
        case .expired:
            return "Session expired"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }

    public var iconName: String {
        switch self {
        case .notAuthenticated:
            return "person.crop.circle.badge.xmark"
        case .authenticating:
            return "arrow.triangle.2.circlepath"
        case .authenticated:
            return "person.crop.circle.badge.checkmark"
        case .expired:
            return "clock.badge.exclamationmark"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Upload History Item

public struct UploadHistoryItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var sourcePath: String
    public var destinationPath: String
    public var bucket: String
    public var region: String
    public var fileSize: Int64
    public var status: UploadStatus
    public var startedAt: Date
    public var completedAt: Date?
    public var durationSeconds: Double?
    public var presignedURL: String?
    public var s3URI: String
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        filename: String,
        sourcePath: String,
        destinationPath: String,
        bucket: String,
        region: String,
        fileSize: Int64,
        status: UploadStatus,
        startedAt: Date,
        completedAt: Date? = nil,
        durationSeconds: Double? = nil,
        presignedURL: String? = nil,
        s3URI: String,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.bucket = bucket
        self.region = region
        self.fileSize = fileSize
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.presignedURL = presignedURL
        self.s3URI = s3URI
        self.errorMessage = errorMessage
    }

    public static func from(job: UploadJob) -> UploadHistoryItem {
        var duration: Double?
        if let started = job.startedAt, let completed = job.completedAt {
            duration = completed.timeIntervalSince(started)
        }

        return UploadHistoryItem(
            id: job.id,
            filename: job.fileInfo.filename,
            sourcePath: job.sourceURL.path,
            destinationPath: job.destinationPath,
            bucket: job.bucket,
            region: job.region,
            fileSize: job.fileInfo.size,
            status: job.status,
            startedAt: job.startedAt ?? job.createdAt,
            completedAt: job.completedAt,
            durationSeconds: duration,
            presignedURL: job.presignedURL,
            s3URI: job.fullS3Path,
            errorMessage: job.error?.localizedDescription
        )
    }
}

// MARK: - History Storage

public actor UploadHistoryStore {
    private var history: [UploadHistoryItem] = []
    private let maxItems: Int
    private let storageURL: URL

    public init(maxItems: Int = 1000) {
        self.maxItems = maxItems
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("DragNDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        self.storageURL = appFolder.appendingPathComponent("upload_history.json")
    }

    public func load() async {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        guard let data = try? Data(contentsOf: storageURL),
              let items = try? JSONDecoder().decode([UploadHistoryItem].self, from: data) else { return }
        self.history = items
    }

    public func save() async {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: storageURL)
    }

    public func add(_ item: UploadHistoryItem) async {
        history.insert(item, at: 0)
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
        await save()
    }

    public func getAll() async -> [UploadHistoryItem] {
        return history
    }

    public func getRecent(_ count: Int) async -> [UploadHistoryItem] {
        return Array(history.prefix(count))
    }

    public func clear() async {
        history = []
        await save()
    }

    public func removeOlderThan(days: Int) async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        history = history.filter { $0.startedAt > cutoff }
        await save()
    }
}
