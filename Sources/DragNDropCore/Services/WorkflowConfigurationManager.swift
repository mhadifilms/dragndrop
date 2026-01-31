import Foundation
import Logging

// MARK: - Workflow Configuration Manager

/// Manages loading, saving, and switching between workflow configurations
public actor WorkflowConfigurationManager {
    private let logger = Logger(label: "com.dragndrop.workflow.manager")

    private var workflows: [UUID: WorkflowConfiguration] = [:]
    private var activeWorkflowId: UUID?

    private let storageURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("dragndrop/workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        self.storageURL = appFolder
    }

    // MARK: - Load/Save

    /// Loads all workflows from storage
    public func loadAll() async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for file in files where file.pathExtension == "json" {
            if let workflow = try? loadWorkflow(from: file) {
                workflows[workflow.id] = workflow
            }
        }

        logger.info("Loaded \(workflows.count) workflows")
    }

    /// Saves a workflow to storage
    public func save(_ workflow: WorkflowConfiguration) throws {
        var mutableWorkflow = workflow
        mutableWorkflow.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(mutableWorkflow)
        let fileURL = storageURL.appendingPathComponent("\(workflow.id.uuidString).json")
        try data.write(to: fileURL)

        workflows[workflow.id] = mutableWorkflow
        logger.info("Saved workflow: \(workflow.name)")
    }

    /// Deletes a workflow
    public func delete(id: UUID) throws {
        let fileURL = storageURL.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: fileURL)
        workflows.removeValue(forKey: id)

        if activeWorkflowId == id {
            activeWorkflowId = workflows.keys.first
        }

        logger.info("Deleted workflow: \(id)")
    }

    /// Imports a workflow from a file URL
    public func importWorkflow(from url: URL) throws -> WorkflowConfiguration {
        let workflow = try loadWorkflow(from: url)
        try save(workflow)
        return workflow
    }

    /// Exports a workflow to a file URL
    public func exportWorkflow(id: UUID, to url: URL) throws {
        guard let workflow = workflows[id] else {
            throw WorkflowError.notFound(id)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(workflow)
        try data.write(to: url)

        logger.info("Exported workflow '\(workflow.name)' to \(url.path)")
    }

    private func loadWorkflow(from url: URL) throws -> WorkflowConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkflowConfiguration.self, from: data)
    }

    // MARK: - Access

    /// Gets all workflows
    public func getAll() -> [WorkflowConfiguration] {
        return Array(workflows.values).sorted { $0.name < $1.name }
    }

    /// Gets a specific workflow by ID
    public func get(id: UUID) -> WorkflowConfiguration? {
        return workflows[id]
    }

    /// Gets the active workflow
    public func getActive() -> WorkflowConfiguration? {
        guard let id = activeWorkflowId else { return nil }
        return workflows[id]
    }

    /// Sets the active workflow
    public func setActive(id: UUID) throws {
        guard workflows[id] != nil else {
            throw WorkflowError.notFound(id)
        }
        activeWorkflowId = id
        logger.info("Set active workflow: \(id)")
    }

    /// Creates a new workflow with default values
    public func createNew(name: String, bucket: String, region: String = "us-east-1") throws -> WorkflowConfiguration {
        let workflow = WorkflowConfiguration(
            name: name,
            bucket: bucket,
            region: region,
            pathTemplate: PathTemplate(template: "{folder}/")
        )

        try save(workflow)
        return workflow
    }

    /// Duplicates an existing workflow
    public func duplicate(id: UUID, newName: String) throws -> WorkflowConfiguration {
        guard var workflow = workflows[id] else {
            throw WorkflowError.notFound(id)
        }

        workflow.id = UUID()
        workflow.name = newName
        workflow.createdAt = Date()
        workflow.updatedAt = Date()

        try save(workflow)
        return workflow
    }

    // MARK: - Validation

    /// Validates a workflow configuration
    public func validate(_ workflow: WorkflowConfiguration) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check bucket
        if workflow.bucket.isEmpty {
            issues.append(ValidationIssue(field: "bucket", message: "Bucket name is required", severity: .error))
        }

        // Check path template
        if workflow.pathTemplate.template.isEmpty {
            issues.append(ValidationIssue(field: "pathTemplate", message: "Path template is required", severity: .error))
        }

        // Check extraction rules
        if workflow.extractionRules.isEmpty {
            issues.append(ValidationIssue(
                field: "extractionRules",
                message: "No extraction rules defined. Files may not be matched correctly.",
                severity: .warning
            ))
        }

        // Validate regex patterns
        for rule in workflow.extractionRules {
            do {
                _ = try NSRegularExpression(pattern: rule.pattern, options: [])
            } catch {
                issues.append(ValidationIssue(
                    field: "extractionRules.\(rule.name)",
                    message: "Invalid regex pattern: \(error.localizedDescription)",
                    severity: .error
                ))
            }
        }

        // Check for unmapped placeholders
        let templatePlaceholders = Set(workflow.pathTemplate.extractedPlaceholderNames.map { $0.lowercased() })
        let mappedPlaceholders = Set(workflow.extractionRules.flatMap {
            $0.captureGroupMappings.map { $0.placeholderName.lowercased() }
        })

        let unmapped = templatePlaceholders.subtracting(mappedPlaceholders)
        if !unmapped.isEmpty {
            issues.append(ValidationIssue(
                field: "placeholders",
                message: "Placeholders not mapped by any rule: \(unmapped.joined(separator: ", "))",
                severity: .warning
            ))
        }

        return issues
    }

    // MARK: - Presets

    /// Gets built-in workflow presets
    public static var presets: [WorkflowConfiguration] {
        [
            .sampleVFXWorkflow,
            createFilmWorkflow(),
            createSimpleWorkflow()
        ]
    }

    private static func createFilmWorkflow() -> WorkflowConfiguration {
        WorkflowConfiguration(
            name: "Film/Commercial VFX",
            description: "Standard film/commercial VFX workflow with sequences and versions",
            bucket: "vfx-projects",
            pathTemplate: PathTemplate(
                template: "{PROJECT}/VFX/{SEQUENCE}/{SHOT}/delivery/v{VERSION}/",
                placeholders: [
                    Placeholder(name: "PROJECT", displayName: "Project Code"),
                    Placeholder(name: "SEQUENCE", displayName: "Sequence"),
                    Placeholder(name: "SHOT", displayName: "Shot Number"),
                    Placeholder(name: "VERSION", displayName: "Version", defaultValue: "001")
                ]
            ),
            extractionRules: [
                ExtractionRule(
                    name: "Film Pattern",
                    pattern: "^([A-Z]{3,6})_([A-Z]{2}\\d{3})_(\\d{3,4}).*?v(\\d{3})",
                    captureGroupMappings: [
                        CaptureGroupMapping(groupIndex: 1, placeholderName: "PROJECT"),
                        CaptureGroupMapping(groupIndex: 2, placeholderName: "SEQUENCE"),
                        CaptureGroupMapping(groupIndex: 3, placeholderName: "SHOT"),
                        CaptureGroupMapping(groupIndex: 4, placeholderName: "VERSION")
                    ]
                )
            ]
        )
    }

    private static func createSimpleWorkflow() -> WorkflowConfiguration {
        WorkflowConfiguration(
            name: "Simple Date-Based",
            description: "Simple workflow organizing by date",
            bucket: "uploads",
            pathTemplate: PathTemplate(
                template: "uploads/{YEAR}/{MONTH}/{DAY}/",
                placeholders: [
                    Placeholder(name: "YEAR", displayName: "Year"),
                    Placeholder(name: "MONTH", displayName: "Month"),
                    Placeholder(name: "DAY", displayName: "Day")
                ]
            ),
            extractionRules: [
                ExtractionRule(
                    name: "Date Pattern",
                    pattern: "(\\d{4})[-_](\\d{2})[-_](\\d{2})",
                    captureGroupMappings: [
                        CaptureGroupMapping(groupIndex: 1, placeholderName: "YEAR"),
                        CaptureGroupMapping(groupIndex: 2, placeholderName: "MONTH"),
                        CaptureGroupMapping(groupIndex: 3, placeholderName: "DAY")
                    ]
                )
            ]
        )
    }
}

// MARK: - Supporting Types

public struct ValidationIssue: Sendable {
    public let field: String
    public let message: String
    public let severity: Severity

    public enum Severity: String, Sendable {
        case error
        case warning
        case info
    }
}

public enum WorkflowError: Error, LocalizedError {
    case notFound(UUID)
    case invalidConfiguration(String)
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Workflow not found: \(id)"
        case .invalidConfiguration(let msg):
            return "Invalid configuration: \(msg)"
        case .importFailed(let msg):
            return "Import failed: \(msg)"
        }
    }
}
