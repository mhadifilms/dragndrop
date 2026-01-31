import Foundation
import Logging

// MARK: - File Extraction Service

/// Service for extracting shot information from filenames and matching to paths
public actor FileExtractionService {
    private let logger = Logger(label: "com.dragndrop.extraction")

    public init() {}

    // MARK: - Main Extraction

    /// Extracts placeholder values from a filename using the workflow's extraction rules
    public func extract(
        filename: String,
        using workflow: WorkflowConfiguration
    ) -> ExtractionResult {
        let enabledRules = workflow.extractionRules
            .filter { $0.enabled }
            .sorted { $0.priority > $1.priority }

        for rule in enabledRules {
            if let values = rule.extract(from: filename) {
                let destinationPath = workflow.pathTemplate.buildPath(with: values)

                logger.debug("Extracted values from '\(filename)': \(values)")
                logger.debug("Built destination path: \(destinationPath)")

                return ExtractionResult(
                    success: true,
                    values: values,
                    destinationPath: destinationPath,
                    matchedRule: rule,
                    confidence: calculateConfidence(values: values, template: workflow.pathTemplate)
                )
            }
        }

        logger.warning("No extraction rules matched for: \(filename)")

        return ExtractionResult(
            success: false,
            values: [:],
            destinationPath: nil,
            matchedRule: nil,
            confidence: 0.0,
            error: "No extraction rules matched the filename pattern"
        )
    }

    /// Processes a dropped file URL and creates an upload job
    public func processFile(
        url: URL,
        workflow: WorkflowConfiguration
    ) async throws -> UploadJob {
        let fileInfo = await analyzeFile(url: url, workflow: workflow)
        let extraction = extract(filename: fileInfo.filename, using: workflow)

        guard extraction.success, let destPath = extraction.destinationPath else {
            throw ExtractionError.noMatchingRule(fileInfo.filename)
        }

        // Determine final destination path including file
        var finalPath = destPath
        if !finalPath.hasSuffix("/") {
            finalPath += "/"
        }

        // Add subfolder based on file type if configured
        if let typeConfig = workflow.fileTypeConfigs.first(where: {
            $0.extensions.contains(fileInfo.fileExtension.lowercased())
        }), let subfolder = typeConfig.destinationSubfolder {
            finalPath += subfolder + "/"
        }

        finalPath += fileInfo.filename

        return UploadJob(
            sourceURL: url,
            destinationPath: finalPath,
            bucket: workflow.bucket,
            region: workflow.region,
            fileInfo: fileInfo,
            extractedValues: extraction.values
        )
    }

    /// Processes multiple dropped files/folders
    public func processFiles(
        urls: [URL],
        workflow: WorkflowConfiguration
    ) async throws -> [ProcessedItem] {
        var results: [ProcessedItem] = []

        for url in urls {
            do {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    results.append(ProcessedItem(
                        url: url,
                        job: nil,
                        error: "File not found"
                    ))
                    continue
                }

                if isDirectory.boolValue {
                    // Process directory - could be image sequence or folder of files
                    let sequenceResult = await processDirectory(url: url, workflow: workflow)
                    results.append(contentsOf: sequenceResult)
                } else {
                    let job = try await processFile(url: url, workflow: workflow)
                    results.append(ProcessedItem(url: url, job: job, error: nil))
                }
            } catch {
                results.append(ProcessedItem(
                    url: url,
                    job: nil,
                    error: error.localizedDescription
                ))
            }
        }

        return results
    }

    // MARK: - Directory Processing

    /// Processes a directory, detecting image sequences
    private func processDirectory(
        url: URL,
        workflow: WorkflowConfiguration
    ) async -> [ProcessedItem] {
        var results: [ProcessedItem] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [ProcessedItem(url: url, job: nil, error: "Cannot read directory contents")]
        }

        // Check if this is an image sequence
        let imageExtensions = Set(["exr", "tif", "tiff", "png", "dpx", "cin", "jpg", "jpeg"])
        let imageFiles = contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }

        if !imageFiles.isEmpty {
            // Detect sequences
            let sequences = detectSequences(in: imageFiles)

            for sequence in sequences {
                do {
                    let job = try await processSequence(sequence: sequence, workflow: workflow)
                    results.append(ProcessedItem(url: sequence.files.first ?? url, job: job, error: nil))
                } catch {
                    results.append(ProcessedItem(
                        url: sequence.files.first ?? url,
                        job: nil,
                        error: error.localizedDescription
                    ))
                }
            }

            // Handle non-sequence files
            let sequenceFiles = Set(sequences.flatMap { $0.files })
            let nonSequenceFiles = contents.filter { !sequenceFiles.contains($0) }

            for file in nonSequenceFiles {
                do {
                    let job = try await processFile(url: file, workflow: workflow)
                    results.append(ProcessedItem(url: file, job: job, error: nil))
                } catch {
                    results.append(ProcessedItem(url: file, job: nil, error: error.localizedDescription))
                }
            }
        } else {
            // Process all files in directory individually
            for file in contents {
                do {
                    let job = try await processFile(url: file, workflow: workflow)
                    results.append(ProcessedItem(url: file, job: job, error: nil))
                } catch {
                    results.append(ProcessedItem(url: file, job: nil, error: error.localizedDescription))
                }
            }
        }

        return results
    }

    // MARK: - Sequence Detection

    /// Detects image sequences from a list of files
    private func detectSequences(in files: [URL]) -> [SequenceInfo] {
        // Pattern: name.0001.ext or name_0001.ext
        let sequencePattern = try! NSRegularExpression(
            pattern: "^(.+?)[._]?(\\d{3,})\\.(\\w+)$",
            options: []
        )

        var sequenceGroups: [String: [(url: URL, frame: Int)]] = [:]

        for file in files {
            let filename = file.lastPathComponent
            let range = NSRange(filename.startIndex..., in: filename)

            if let match = sequencePattern.firstMatch(in: filename, options: [], range: range) {
                let baseName = String(filename[Range(match.range(at: 1), in: filename)!])
                let frameStr = String(filename[Range(match.range(at: 2), in: filename)!])
                let ext = String(filename[Range(match.range(at: 3), in: filename)!])

                let key = "\(baseName).\(ext)"
                let frame = Int(frameStr) ?? 0

                if sequenceGroups[key] == nil {
                    sequenceGroups[key] = []
                }
                sequenceGroups[key]?.append((url: file, frame: frame))
            }
        }

        return sequenceGroups.compactMap { key, items -> SequenceInfo? in
            guard items.count > 1 else { return nil }

            let sorted = items.sorted { $0.frame < $1.frame }
            let frames = sorted.map { $0.frame }
            let urls = sorted.map { $0.url }

            // Detect padding from first file
            let firstFrameStr = String(format: "%d", frames.first ?? 0)
            let firstFile = urls.first?.lastPathComponent ?? ""
            let padding = detectPadding(in: firstFile, frame: frames.first ?? 0)

            let totalSize = urls.reduce(0) { sum, url -> Int64 in
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                return sum + (attrs?[.size] as? Int64 ?? 0)
            }

            let components = key.components(separatedBy: ".")
            let baseName = components.dropLast().joined(separator: ".")

            return SequenceInfo(
                baseName: baseName,
                frameRange: (frames.first ?? 0)...(frames.last ?? 0),
                padding: padding,
                fileCount: items.count,
                totalSize: totalSize,
                files: urls
            )
        }
    }

    private func detectPadding(in filename: String, frame: Int) -> Int {
        let frameStr = String(frame)
        let pattern = try! NSRegularExpression(pattern: "(\\d{3,})", options: [])
        let range = NSRange(filename.startIndex..., in: filename)

        if let match = pattern.firstMatch(in: filename, options: [], range: range),
           let matchRange = Range(match.range(at: 1), in: filename) {
            return filename[matchRange].count
        }

        return max(4, frameStr.count)
    }

    /// Processes an image sequence
    private func processSequence(
        sequence: SequenceInfo,
        workflow: WorkflowConfiguration
    ) async throws -> UploadJob {
        guard let firstFile = sequence.files.first else {
            throw ExtractionError.invalidSequence
        }

        // Use the sequence pattern for extraction
        let filenameForExtraction = sequence.baseName + "." + firstFile.pathExtension

        let extraction = extract(filename: filenameForExtraction, using: workflow)

        guard extraction.success, let destPath = extraction.destinationPath else {
            throw ExtractionError.noMatchingRule(filenameForExtraction)
        }

        var finalPath = destPath
        if !finalPath.hasSuffix("/") {
            finalPath += "/"
        }

        // Add renders subfolder for sequences
        finalPath += "renders/" + sequence.baseName + "/"

        let fileInfo = FileInfo(
            filename: sequence.sequencePattern + "." + firstFile.pathExtension,
            fileExtension: firstFile.pathExtension,
            size: sequence.totalSize,
            category: .imageSequence,
            isDirectory: false,
            isSequence: true,
            sequenceInfo: sequence
        )

        return UploadJob(
            sourceURL: firstFile,
            destinationPath: finalPath,
            bucket: workflow.bucket,
            region: workflow.region,
            fileInfo: fileInfo,
            extractedValues: extraction.values
        )
    }

    // MARK: - File Analysis

    /// Analyzes a file and returns detailed info
    private func analyzeFile(url: URL, workflow: WorkflowConfiguration) async -> FileInfo {
        var info = FileInfo.from(url: url)

        // Determine category from workflow configs
        if let config = workflow.fileTypeConfigs.first(where: {
            $0.extensions.contains(info.fileExtension.lowercased())
        }) {
            info.category = config.category
        }

        return info
    }

    // MARK: - Confidence Calculation

    /// Calculates confidence score for an extraction (0.0 - 1.0)
    private func calculateConfidence(values: [String: String], template: PathTemplate) -> Double {
        let requiredPlaceholders = template.placeholders.filter { $0.required }
        let foundRequired = requiredPlaceholders.filter { values[$0.name] != nil }

        if requiredPlaceholders.isEmpty {
            return values.isEmpty ? 0.5 : 1.0
        }

        return Double(foundRequired.count) / Double(requiredPlaceholders.count)
    }

    // MARK: - Validation

    /// Validates that all required placeholders are filled
    public func validate(
        values: [String: String],
        against template: PathTemplate
    ) -> ValidationResult {
        var missing: [String] = []
        var warnings: [String] = []

        for placeholder in template.placeholders {
            let value = values[placeholder.name]

            if placeholder.required && (value == nil || value?.isEmpty == true) {
                if let defaultValue = placeholder.defaultValue {
                    warnings.append("Using default value '\(defaultValue)' for \(placeholder.displayName)")
                } else {
                    missing.append(placeholder.displayName)
                }
            }
        }

        return ValidationResult(
            isValid: missing.isEmpty,
            missingFields: missing,
            warnings: warnings
        )
    }
}

// MARK: - Supporting Types

public struct ExtractionResult: Sendable {
    public let success: Bool
    public let values: [String: String]
    public let destinationPath: String?
    public let matchedRule: ExtractionRule?
    public let confidence: Double
    public let error: String?

    public init(
        success: Bool,
        values: [String: String],
        destinationPath: String?,
        matchedRule: ExtractionRule?,
        confidence: Double,
        error: String? = nil
    ) {
        self.success = success
        self.values = values
        self.destinationPath = destinationPath
        self.matchedRule = matchedRule
        self.confidence = confidence
        self.error = error
    }
}

public struct ProcessedItem: Sendable {
    public let url: URL
    public let job: UploadJob?
    public let error: String?

    public init(url: URL, job: UploadJob?, error: String?) {
        self.url = url
        self.job = job
        self.error = error
    }

    public var isSuccess: Bool {
        job != nil && error == nil
    }
}

public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let missingFields: [String]
    public let warnings: [String]
}

public enum ExtractionError: Error, LocalizedError {
    case noMatchingRule(String)
    case invalidSequence
    case missingRequiredField(String)

    public var errorDescription: String? {
        switch self {
        case .noMatchingRule(let filename):
            return "No extraction rule matched the filename: \(filename)"
        case .invalidSequence:
            return "Invalid image sequence"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}

// MARK: - Predefined Extraction Patterns

extension ExtractionRule {
    /// Common VFX naming patterns
    public static var commonPatterns: [ExtractionRule] {
        [
            // Pattern: SHOW_EPISODE_SHOT_CATEGORY (e.g., MyShow_101_001_comp)
            ExtractionRule(
                name: "Standard VFX Naming",
                description: "SHOW_EPISODE_SHOT_CATEGORY pattern",
                pattern: "^([A-Za-z]+)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z]+)",
                captureGroupMappings: [
                    CaptureGroupMapping(groupIndex: 1, placeholderName: "show"),
                    CaptureGroupMapping(groupIndex: 2, placeholderName: "episode"),
                    CaptureGroupMapping(groupIndex: 3, placeholderName: "shot"),
                    CaptureGroupMapping(groupIndex: 4, placeholderName: "category")
                ]
            ),

            // Pattern: SHOW_S01E01_SHOT (e.g., MyShow_S02E05_0010)
            ExtractionRule(
                name: "Season Episode Format",
                description: "SHOW_S##E##_SHOT pattern",
                pattern: "^([A-Za-z]+)_S(\\d{2})E(\\d{2})_([A-Za-z0-9]+)",
                captureGroupMappings: [
                    CaptureGroupMapping(groupIndex: 1, placeholderName: "show"),
                    CaptureGroupMapping(groupIndex: 2, placeholderName: "season"),
                    CaptureGroupMapping(groupIndex: 3, placeholderName: "episode"),
                    CaptureGroupMapping(groupIndex: 4, placeholderName: "shot")
                ]
            ),

            // Pattern: PROJECT_SEQUENCE_SHOT_VERSION (e.g., FILM_SQ010_0020_v001)
            ExtractionRule(
                name: "Film/Commercial Format",
                description: "PROJECT_SEQUENCE_SHOT_VERSION pattern",
                pattern: "^([A-Za-z]+)_([A-Za-z]{2}\\d{3})_([0-9]+)_v(\\d{3})",
                captureGroupMappings: [
                    CaptureGroupMapping(groupIndex: 1, placeholderName: "project"),
                    CaptureGroupMapping(groupIndex: 2, placeholderName: "sequence"),
                    CaptureGroupMapping(groupIndex: 3, placeholderName: "shot"),
                    CaptureGroupMapping(groupIndex: 4, placeholderName: "version")
                ]
            ),

            // Pattern: Simple SHOT_VERSION (e.g., 0010_v003)
            ExtractionRule(
                name: "Simple Shot Version",
                description: "SHOT_VERSION pattern",
                pattern: "^(\\d{3,4})_v(\\d{2,3})",
                captureGroupMappings: [
                    CaptureGroupMapping(groupIndex: 1, placeholderName: "shot"),
                    CaptureGroupMapping(groupIndex: 2, placeholderName: "version")
                ]
            )
        ]
    }
}
