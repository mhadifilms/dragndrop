import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Clipboard Manager

/// Manages clipboard operations for copying S3 URIs and URLs
public struct ClipboardManager: Sendable {

    public init() {}

    /// Copies text to the system clipboard
    public func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    /// Copies an S3 URI to the clipboard
    public func copyS3URI(bucket: String, key: String) {
        let uri = "s3://\(bucket)/\(key)"
        copyToClipboard(uri)
    }

    /// Copies a presigned URL to the clipboard
    public func copyPresignedURL(_ url: String) {
        copyToClipboard(url)
    }

    /// Copies the AWS Console URL for an object
    public func copyConsoleURL(bucket: String, key: String, region: String) {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let url = "https://\(region).console.aws.amazon.com/s3/object/\(bucket)?prefix=\(encodedKey)"
        copyToClipboard(url)
    }

    /// Gets text from clipboard
    public func getFromClipboard() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

// MARK: - URL Utilities

public struct URLUtilities {

    /// Generates an AWS Console URL for browsing a bucket path
    public static func consoleURL(bucket: String, prefix: String, region: String) -> URL? {
        let encodedPrefix = prefix.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? prefix
        let urlString = "https://\(region).console.aws.amazon.com/s3/buckets/\(bucket)?prefix=\(encodedPrefix)"
        return URL(string: urlString)
    }

    /// Generates an AWS Console URL for a specific object
    public static func objectConsoleURL(bucket: String, key: String, region: String) -> URL? {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let urlString = "https://\(region).console.aws.amazon.com/s3/object/\(bucket)?prefix=\(encodedKey)"
        return URL(string: urlString)
    }

    /// Formats an S3 URI
    public static func s3URI(bucket: String, key: String) -> String {
        return "s3://\(bucket)/\(key)"
    }

    /// Parses an S3 URI into bucket and key
    public static func parseS3URI(_ uri: String) -> (bucket: String, key: String)? {
        guard uri.hasPrefix("s3://") else { return nil }

        let withoutPrefix = String(uri.dropFirst(5))
        guard let slashIndex = withoutPrefix.firstIndex(of: "/") else {
            return (bucket: withoutPrefix, key: "")
        }

        let bucket = String(withoutPrefix[..<slashIndex])
        let key = String(withoutPrefix[withoutPrefix.index(after: slashIndex)...])

        return (bucket: bucket, key: key)
    }

    /// Formats a file size in human-readable form
    public static func formatFileSize(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Formats a duration in human-readable form
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }

    /// Formats a date for display
    public static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Formats a date as relative time
    public static func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - File Utilities

public struct FileUtilities {

    /// Calculates total size of files at URLs
    public static func totalSize(of urls: [URL]) -> Int64 {
        return urls.reduce(0) { total, url in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return total + (attrs?[.size] as? Int64 ?? 0)
        }
    }

    /// Gets file count in directory (including subdirectories)
    public static func fileCount(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let url as URL in enumerator {
            if let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
               isFile {
                count += 1
            }
        }
        return count
    }

    /// Detects if a directory contains an image sequence
    public static func isImageSequenceDirectory(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let imageExtensions = Set(["exr", "tif", "tiff", "png", "dpx", "cin", "jpg", "jpeg"])
        let imageFiles = contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }

        // Need at least 2 image files to be a sequence
        return imageFiles.count >= 2
    }

    /// Validates that a path exists and is accessible
    public static func validatePath(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDirectory)
    }

    /// Gets the MIME type for a file extension
    public static func mimeType(for extension: String) -> String {
        let ext = `extension`.lowercased()
        switch ext {
        case "exr": return "image/x-exr"
        case "tif", "tiff": return "image/tiff"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mxf": return "application/mxf"
        case "wav": return "audio/wav"
        case "aiff": return "audio/aiff"
        case "mp3": return "audio/mpeg"
        case "aac": return "audio/aac"
        case "nk": return "application/x-nuke"
        case "aep": return "application/x-aftereffects"
        case "blend": return "application/x-blender"
        case "hip", "hipnc": return "application/x-houdini"
        case "ma", "mb": return "application/x-maya"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Sequence Detection

public struct SequenceDetector {

    /// Frame number pattern detection
    private static let framePatterns: [NSRegularExpression] = {
        let patterns = [
            "^(.+?)[._]?(\\d{3,})\\.(\\w+)$",           // name.0001.ext or name_0001.ext
            "^(.+?)\\.(\\d{3,})\\.(\\w+)$",             // name.0001.ext
            "^(.+?)_(\\d{3,})\\.(\\w+)$",               // name_0001.ext
            "^(.+?)\\s(\\d{3,})\\.(\\w+)$"              // name 0001.ext
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    /// Detects sequences in a list of files
    public static func detectSequences(in files: [URL]) -> [DetectedSequence] {
        var groups: [String: [SequenceFile]] = [:]

        for file in files {
            if let parsed = parseFrameFile(file) {
                let key = "\(parsed.baseName).\(parsed.extension)"
                if groups[key] == nil {
                    groups[key] = []
                }
                groups[key]?.append(parsed)
            }
        }

        return groups.compactMap { key, files -> DetectedSequence? in
            guard files.count >= 2 else { return nil }

            let sorted = files.sorted { $0.frame < $1.frame }
            let frames = sorted.map { $0.frame }

            return DetectedSequence(
                baseName: sorted.first!.baseName,
                extension: sorted.first!.extension,
                startFrame: frames.first!,
                endFrame: frames.last!,
                frameCount: files.count,
                padding: sorted.first!.padding,
                files: sorted.map { $0.url },
                isContinuous: isContinuous(frames)
            )
        }
    }

    private static func parseFrameFile(_ url: URL) -> SequenceFile? {
        let filename = url.lastPathComponent

        for pattern in framePatterns {
            let range = NSRange(filename.startIndex..., in: filename)
            if let match = pattern.firstMatch(in: filename, options: [], range: range) {
                guard match.numberOfRanges >= 4 else { continue }

                let baseName = String(filename[Range(match.range(at: 1), in: filename)!])
                let frameStr = String(filename[Range(match.range(at: 2), in: filename)!])
                let ext = String(filename[Range(match.range(at: 3), in: filename)!])

                guard let frame = Int(frameStr) else { continue }

                return SequenceFile(
                    url: url,
                    baseName: baseName,
                    frame: frame,
                    padding: frameStr.count,
                    extension: ext
                )
            }
        }

        return nil
    }

    private static func isContinuous(_ frames: [Int]) -> Bool {
        guard frames.count >= 2 else { return true }

        for i in 1..<frames.count {
            if frames[i] != frames[i-1] + 1 {
                return false
            }
        }
        return true
    }
}

struct SequenceFile {
    let url: URL
    let baseName: String
    let frame: Int
    let padding: Int
    let `extension`: String
}

public struct DetectedSequence: Sendable {
    public let baseName: String
    public let `extension`: String
    public let startFrame: Int
    public let endFrame: Int
    public let frameCount: Int
    public let padding: Int
    public let files: [URL]
    public let isContinuous: Bool

    public var frameRange: String {
        "\(startFrame)-\(endFrame)"
    }

    public var sequencePattern: String {
        let paddingStr = String(repeating: "#", count: padding)
        return "\(baseName).\(paddingStr).\(`extension`)"
    }

    public var totalSize: Int64 {
        FileUtilities.totalSize(of: files)
    }
}
