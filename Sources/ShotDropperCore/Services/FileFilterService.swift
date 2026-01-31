import Foundation

// MARK: - File Filter Service

/// Filters files based on configured criteria (extensions, size, etc.)
public struct FileFilterService: Sendable {

    public init() {}

    // MARK: - Filter Configuration

    public struct FilterConfig: Sendable {
        public var enableFilter: Bool
        public var allowedExtensions: Set<String>
        public var blockedExtensions: Set<String>
        public var maxFileSizeBytes: Int64  // 0 = unlimited
        public var allowHiddenFiles: Bool

        public init(
            enableFilter: Bool = false,
            allowedExtensions: [String] = [],
            blockedExtensions: [String] = [],
            maxFileSizeMB: Int = 0,
            allowHiddenFiles: Bool = false
        ) {
            self.enableFilter = enableFilter
            self.allowedExtensions = Set(allowedExtensions.map { $0.lowercased() })
            self.blockedExtensions = Set(blockedExtensions.map { $0.lowercased() })
            self.maxFileSizeBytes = Int64(maxFileSizeMB) * 1024 * 1024
            self.allowHiddenFiles = allowHiddenFiles
        }

        public static func from(settings: AppSettings) -> FilterConfig {
            return FilterConfig(
                enableFilter: settings.enableFileTypeFilter,
                allowedExtensions: settings.allowedFileExtensions,
                blockedExtensions: settings.blockedFileExtensions,
                maxFileSizeMB: settings.maxFileSizeMB,
                allowHiddenFiles: settings.allowHiddenFiles
            )
        }
    }

    // MARK: - Filter Result

    public enum FilterResult: Equatable, Sendable {
        case allowed
        case blockedByExtension(String)
        case notInAllowedList(String)
        case fileTooLarge(Int64, Int64)  // actual, max
        case hiddenFile
        case directoryNotAllowed
        case fileNotFound

        public var isAllowed: Bool {
            self == .allowed
        }

        public var reason: String {
            switch self {
            case .allowed:
                return "File is allowed"
            case .blockedByExtension(let ext):
                return "File extension '.\(ext)' is blocked"
            case .notInAllowedList(let ext):
                return "File extension '.\(ext)' is not in the allowed list"
            case .fileTooLarge(let actual, let max):
                let actualStr = ByteCountFormatter.string(fromByteCount: actual, countStyle: .file)
                let maxStr = ByteCountFormatter.string(fromByteCount: max, countStyle: .file)
                return "File size (\(actualStr)) exceeds limit (\(maxStr))"
            case .hiddenFile:
                return "Hidden files are not allowed"
            case .directoryNotAllowed:
                return "Directories must be processed individually"
            case .fileNotFound:
                return "File not found"
            }
        }
    }

    // MARK: - Filtering

    /// Checks if a file is allowed based on the filter configuration
    public func checkFile(at url: URL, config: FilterConfig) -> FilterResult {
        guard config.enableFilter else {
            return .allowed
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .fileNotFound
        }

        // Check for hidden files
        if !config.allowHiddenFiles && url.lastPathComponent.hasPrefix(".") {
            return .hiddenFile
        }

        // Get file attributes
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return .fileNotFound
        }

        // Check if it's a directory
        if let fileType = attrs[.type] as? FileAttributeType, fileType == .typeDirectory {
            return .directoryNotAllowed
        }

        // Get extension
        let ext = url.pathExtension.lowercased()

        // Check blocked extensions first
        if config.blockedExtensions.contains(ext) {
            return .blockedByExtension(ext)
        }

        // Check allowed extensions (if filter is enabled and list is not empty)
        if !config.allowedExtensions.isEmpty && !config.allowedExtensions.contains(ext) {
            return .notInAllowedList(ext)
        }

        // Check file size
        if config.maxFileSizeBytes > 0 {
            let size = attrs[.size] as? Int64 ?? 0
            if size > config.maxFileSizeBytes {
                return .fileTooLarge(size, config.maxFileSizeBytes)
            }
        }

        return .allowed
    }

    /// Filters a list of URLs, returning only allowed files
    public func filterFiles(_ urls: [URL], config: FilterConfig) -> FilteredFiles {
        var allowed: [URL] = []
        var rejected: [(URL, FilterResult)] = []

        for url in urls {
            let result = checkFile(at: url, config: config)
            if result.isAllowed {
                allowed.append(url)
            } else {
                rejected.append((url, result))
            }
        }

        return FilteredFiles(allowed: allowed, rejected: rejected)
    }

    /// Recursively filters files in a directory
    public func filterDirectory(at url: URL, config: FilterConfig) -> FilteredFiles {
        var allowed: [URL] = []
        var rejected: [(URL, FilterResult)] = []

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return FilteredFiles(allowed: [], rejected: [(url, .directoryNotAllowed)])
        }

        for case let fileURL as URL in enumerator {
            // Skip directories
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let result = checkFile(at: fileURL, config: config)
            if result.isAllowed {
                allowed.append(fileURL)
            } else {
                rejected.append((fileURL, result))
            }
        }

        return FilteredFiles(allowed: allowed, rejected: rejected)
    }
}

// MARK: - Filtered Files Result

public struct FilteredFiles: Sendable {
    public let allowed: [URL]
    public let rejected: [(URL, FileFilterService.FilterResult)]

    public var allowedCount: Int { allowed.count }
    public var rejectedCount: Int { rejected.count }
    public var totalCount: Int { allowed.count + rejected.count }

    public var hasRejected: Bool { !rejected.isEmpty }

    /// Summary of rejection reasons
    public var rejectionSummary: [String: Int] {
        var summary: [String: Int] = [:]
        for (_, result) in rejected {
            let key: String
            switch result {
            case .blockedByExtension(let ext):
                key = "Blocked extension: .\(ext)"
            case .notInAllowedList(let ext):
                key = "Not allowed: .\(ext)"
            case .fileTooLarge:
                key = "File too large"
            case .hiddenFile:
                key = "Hidden file"
            case .directoryNotAllowed:
                key = "Directory"
            case .fileNotFound:
                key = "Not found"
            case .allowed:
                continue
            }
            summary[key, default: 0] += 1
        }
        return summary
    }
}

// MARK: - File Extension Presets

public enum FileExtensionPreset: String, CaseIterable, Sendable {
    case vfxAll = "VFX (All)"
    case vfxNukeOnly = "VFX (Nuke Only)"
    case imageSequences = "Image Sequences"
    case videoOnly = "Video Files"
    case audioOnly = "Audio Files"
    case custom = "Custom"

    public var extensions: [String] {
        switch self {
        case .vfxAll:
            return AppSettings.defaultAllowedExtensions
        case .vfxNukeOnly:
            return ["nk", "nknc", "exr", "tif", "tiff", "png", "dpx"]
        case .imageSequences:
            return ["exr", "tif", "tiff", "png", "dpx", "cin", "jpg", "jpeg"]
        case .videoOnly:
            return ["mov", "mp4", "avi", "mkv", "mxf", "prores", "m4v"]
        case .audioOnly:
            return ["wav", "aiff", "mp3", "aac", "flac", "m4a"]
        case .custom:
            return []
        }
    }

    public var displayName: String {
        rawValue
    }

    public var description: String {
        switch self {
        case .vfxAll:
            return "All common VFX file types including Nuke, images, video, and audio"
        case .vfxNukeOnly:
            return "Nuke scripts and common render formats (EXR, TIFF, PNG, DPX)"
        case .imageSequences:
            return "Image sequence formats only"
        case .videoOnly:
            return "Video container formats"
        case .audioOnly:
            return "Audio formats"
        case .custom:
            return "Define your own allowed extensions"
        }
    }
}
